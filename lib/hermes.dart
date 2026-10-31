import 'dart:convert';
import 'dart:io';

class Msg {
  Msg(this.user, this.text);
  final bool user;
  String text;
}

/// A model offered by the Hermes server; [id] = "providerSlug/model".
typedef Model = ({String provider, String name, String id});

/// Display name of a model id, readable even before the server list is loaded.
String modelName(String id) => id.substring(id.indexOf('/') + 1);

/// One usage window of a subscription (e.g. "Weekly"), [used] in percent.
typedef QuotaWindow = ({String label, double used, DateTime? resetsAt});

/// Usage of one provider account; [limited] = currently rate-limited, until [limitedUntil] if known.
typedef Quota = ({String provider, String account, List<QuotaWindow> windows, bool limited, DateTime? limitedUntil});

/// What `/api/model/options` tells: the models, the server's default model id and the quotas.
typedef ModelOptions = ({List<Model> models, String current, List<Quota> quotas});

/// Server catalog loader, swappable in tests.
var fetchModels = hermesModels;

DateTime? _date(Object? v) => v is String ? DateTime.tryParse(v)?.toLocal() : null;

List<QuotaWindow> _windows(Object? v) => [
  for (final w in (v is List ? v : const []).whereType<Map>())
    if (w['used_percent'] is num)
      (label: '${w['label'] ?? ''}', used: (w['used_percent'] as num).toDouble(), resetsAt: _date(w['resets_at'])),
];

/// Quotas of a provider row: one per account when the server reports several, else one.
List<Quota> _quotas(Map p) {
  final name = '${p['name'] ?? p['slug']}';
  final usage = p['usage'] is Map ? p['usage'] as Map : const {};
  if (usage['accounts'] case final List accounts when accounts.isNotEmpty) {
    return [
      for (final a in accounts.whereType<Map>())
        (
          provider: name,
          account: '${a['label'] ?? ''}',
          windows: _windows(a['windows']),
          limited: a['state'] == 'limited',
          limitedUntil: a['state'] == 'limited' ? _date(a['resets_at']) : null,
        ),
    ];
  }
  final limit = p['limit'] is Map && (p['limit'] as Map)['scope'] == 'account' ? p['limit'] as Map : null;
  return [
    (provider: name, account: '', windows: _windows(usage['windows']), limited: limit != null, limitedUntil: _date(limit?['resets_at'])),
  ];
}

/// Merges quotas that are the same subscription reached through several providers (e.g. Anthropic
/// and Claude Subscription DirectSDK): they share a window with the same label, usage and reset time.
List<Quota> mergeSameAccounts(List<Quota> quotas) {
  bool same(QuotaWindow a, QuotaWindow b) =>
      a.label == b.label &&
      (a.used - b.used).abs() < .1 &&
      a.resetsAt != null &&
      b.resetsAt != null &&
      a.resetsAt!.difference(b.resetsAt!).abs() < const Duration(minutes: 1);
  final out = <Quota>[];
  for (final q in quotas) {
    final i = out.indexWhere((o) => o.windows.any((w) => q.windows.any((x) => same(w, x))));
    if (i < 0) {
      out.add(q);
      continue;
    }
    final o = out[i];
    out[i] = (
      provider: '${o.provider} · ${q.provider}',
      account: o.account.isNotEmpty ? o.account : q.account,
      windows: [...o.windows, ...q.windows.where((x) => !o.windows.any((w) => same(w, x)))],
      limited: o.limited || q.limited,
      limitedUntil: o.limitedUntil ?? q.limitedUntil,
    );
  }
  return out;
}

/// Parses the server's `/api/model/options`. Null if [body] isn't that payload.
ModelOptions? parseModelOptions(String body) {
  try {
    final j = jsonDecode(body);
    if (j is! Map || j['providers'] is! List) return null;
    final providers = (j['providers'] as List).whereType<Map>().where((p) => p['authenticated'] != false);
    return (
      models: [
        for (final p in providers)
          for (final m in (p['models'] as List? ?? []).whereType<String>())
            (provider: '${p['name'] ?? p['slug']}', name: m, id: '${p['slug']}/$m'),
      ],
      current: j['model'] is String && j['provider'] is String && j['model'] != '' ? '${j['provider']}/${j['model']}' : '',
      quotas: mergeSameAccounts([for (final p in providers) ..._quotas(p)]),
    );
  } on FormatException {
    return null;
  }
}

/// Fetches the models the server can use. Signs in when [user] is set; otherwise
/// reuses the session token a loopback dashboard injects into its page.
// ponytail: signs in on every call, keep the session cookie once the chat needs it too
Future<ModelOptions> hermesModels(Uri base, {String? user, String? password}) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    var cookies = <Cookie>[];
    String? token;
    if (user != null) {
      final login = await hermesLogin(client, base, user, password ?? '');
      if (!login.ok) throw HttpException('sign-in failed (HTTP ${login.status})');
      cookies = login.cookies;
    } else {
      final page = await client.getUrl(base).then((r) => r.close()).then((r) => r.transform(utf8.decoder).join());
      token = RegExp(r'__HERMES_SESSION_TOKEN__\s*=\s*"([^"]+)"').firstMatch(page)?.group(1);
    }
    final req = await client.getUrl(_at(base, '/api/model/options').replace(queryParameters: {'explicit_only': 'true'}));
    req.cookies.addAll(cookies);
    if (token != null) req.headers.set('X-Hermes-Session-Token', token);
    final res = await req.close();
    final body = await res.transform(utf8.decoder).join();
    final r = res.statusCode == 200 ? parseModelOptions(body) : null;
    if (r == null) throw HttpException(_detail(body) ?? 'model list unavailable (HTTP ${res.statusCode})');
    return r;
  } finally {
    client.close(force: true);
  }
}

/// The `detail` message of a FastAPI error body, if any.
String? _detail(String body) {
  try {
    final j = jsonDecode(body);
    return j is Map && j['detail'] is String ? j['detail'] as String : null;
  } on FormatException {
    return null;
  }
}

Uri _at(Uri base, String path) => base.replace(path: '${base.path.replaceAll(RegExp(r'/+$'), '')}$path');

/// Status endpoint a Hermes server answers without authentication.
Uri hermesStatusUri(Uri base) => _at(base, '/api/status');

/// Outcome of [hermesLogin], with the HTTP status for unexpected answers.
typedef HermesLogin = ({bool ok, int status, List<Cookie> cookies});

/// Signs in like Hermes' web login form ("basic" provider): JSON POST, session cookie on success.
/// 401 = wrong credentials, 429 = rate limited.
Future<HermesLogin> hermesLogin(HttpClient client, Uri base, String user, String password) async {
  final req = await client.postUrl(_at(base, '/auth/password-login'));
  req.headers.contentType = ContentType.json;
  req.write(jsonEncode({'provider': 'basic', 'username': user, 'password': password, 'next': ''}));
  final res = await req.close();
  await res.drain<void>();
  return (ok: res.statusCode == 200, status: res.statusCode, cookies: res.cookies);
}

/// Parsed Hermes `/api/status` payload, null if [body] isn't one.
({String version, bool authRequired})? hermesStatus(String body) {
  try {
    final j = jsonDecode(body);
    // keys specific to Hermes, so any other JSON API with a "version" field is rejected
    if (j is Map && j['version'] is String && j.containsKey('can_update_hermes') && j.containsKey('gateway_state')) {
      return (version: j['version'] as String, authRequired: j['auth_required'] == true);
    }
  } on FormatException {
    // not JSON: not Hermes
  }
  return null;
}

// ponytail: rough estimate (~4 chars per token, fixed window); use the usage Hermes reports once the chat is hooked up
const contextWindow = 200000;

/// Share of the context window [text] fills, 0 to 1.
double contextUse(String text) => (text.length / 4 / contextWindow).clamp(0, 1);

/// Hermes hook-up point: takes the history, returns the reply chunk by chunk.
// ponytail: fake reply, replace with the network call to Hermes (SSE / websocket)
Stream<String> hermes(List<Msg> history, String model) async* {
  await Future.delayed(const Duration(milliseconds: 700));
  final reply =
      'Got it (${modelName(model)}): "${history.last.text}". I\'m not connected yet, '
      'but once Hermes is hooked up, its replies will stream in here '
      'with the same progressive fade as this demo.';
  for (final word in reply.split(' ')) {
    await Future.delayed(const Duration(milliseconds: 45));
    yield '$word ';
  }
}
