import 'dart:async';
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

/// Signs in when [user] is set (session cookies); otherwise reads the session token a loopback
/// dashboard injects into its page.
Future<({List<Cookie> cookies, String? token})> _signIn(HttpClient client, Uri base, String? user, String? password) async {
  if (user != null) {
    final login = await hermesLogin(client, base, user, password ?? '');
    if (!login.ok) throw HttpException('sign-in failed (HTTP ${login.status})');
    return (cookies: login.cookies, token: null);
  }
  final page = await client.getUrl(base).then((r) => r.close()).then((r) => r.transform(utf8.decoder).join());
  return (cookies: <Cookie>[], token: RegExp(r'__HERMES_SESSION_TOKEN__\s*=\s*"([^"]+)"').firstMatch(page)?.group(1));
}

/// Calls the dashboard's REST API as the signed-in user and returns the body; a non-2xx answer
/// throws an [HttpException] with the server's `detail`.
Future<String> hermesApi(
  Uri base,
  String method,
  String path, {
  Map<String, String>? query,
  Object? body,
  String? user,
  String? password,
}) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final auth = await _signIn(client, base, user, password);
    final req = await client.openUrl(method, _at(base, path).replace(queryParameters: query));
    req.cookies.addAll(auth.cookies);
    if (auth.token != null) req.headers.set('X-Hermes-Session-Token', auth.token!);
    if (body != null) {
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(body));
    }
    final res = await req.close();
    final text = await res.transform(utf8.decoder).join();
    if (res.statusCode ~/ 100 != 2) throw HttpException(_detail(text) ?? '$path failed (HTTP ${res.statusCode})');
    return text;
  } finally {
    client.close(force: true);
  }
}

/// REST caller, swappable in tests.
var callApi = hermesApi;

/// Fetches the models the server can use.
Future<ModelOptions> hermesModels(Uri base, {String? user, String? password}) async {
  final body = await hermesApi(base, 'GET', '/api/model/options', query: {'explicit_only': 'true'}, user: user, password: password);
  return parseModelOptions(body) ?? (throw const HttpException('model list unavailable'));
}

/// A scheduled job; [state] is the server's (`scheduled`, `paused`, `completed`, `running`, …).
typedef CronJob = ({
  String id,
  String name,
  String schedule,
  bool enabled,
  String state,
  DateTime? nextRun,
  DateTime? lastRun,
  String? lastError,
  Map raw, // the whole record, for the editor
});

/// Parses `GET /api/cron/jobs` (a list, or `{jobs: [...]}`).
List<CronJob> parseCronJobs(String body) {
  final j = _json(body);
  final list = j is List ? j : (j is Map && j['jobs'] is List ? j['jobs'] as List : const []);
  return [
    for (final x in list.whereType<Map>())
      if (x['id'] is String)
        (
          id: x['id'] as String,
          name: '${x['name'] ?? x['id']}',
          schedule: '${x['schedule_display'] ?? (x['schedule'] is Map ? (x['schedule'] as Map)['display'] : null) ?? ''}',
          enabled: x['enabled'] != false,
          state: '${x['state'] ?? ''}',
          nextRun: _date(x['next_run_at']),
          lastRun: _date(x['last_run_at']),
          lastError: x['last_status'] == 'error' || x['last_status'] == 'failed' ? '${x['last_error'] ?? x['last_status']}' : null,
          raw: x,
        ),
  ];
}

/// The `detail` message of a FastAPI error body, if any.
String? _detail(String body) => switch (_json(body)) {
  {'detail': final String d} => d,
  {'detail': [{'msg': final String m}, ...]} => m, // request validation error
  _ => null,
};

Object? _json(String body) {
  try {
    return jsonDecode(body);
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

// ponytail: rough estimate (~4 chars per token, fixed window), only until the server reports the real usage
const contextWindow = 200000;

/// Share of the context window [text] fills, 0 to 1.
double contextUse(String text) => (text.length / 4 / contextWindow).clamp(0, 1);

/// Context share a gateway `usage` object reports, 0 to 1; null when unknown.
double? contextOf(Object? usage) => switch (usage) {
  {'context_percent': final num p} => (p / 100).clamp(0, 1).toDouble(),
  _ => null,
};

/// A gateway event: [type] (`message.delta`, `message.complete`, …) for the runtime [session].
typedef GatewayEvent = ({String type, String session, Map payload});

/// JSON-RPC connection to the dashboard's `/api/ws`, the gateway Hermes' own web and desktop chats use.
class Gateway {
  Gateway(Stream<dynamic> frames, this._send, this._close) {
    frames.listen(_frame, onDone: _done, onError: (Object _) => _done(), cancelOnError: true);
  }
  final void Function(String) _send;
  final void Function() _close;
  final _pending = <int, Completer<Map>>{};
  final _events = StreamController<GatewayEvent>.broadcast();
  var _id = 0;
  bool closed = false;

  Stream<GatewayEvent> get events => _events.stream;

  void _frame(dynamic f) {
    final j = f is String ? _json(f) : null;
    switch (j) {
      case {'method': 'event', 'params': final Map p}:
        _events.add((
          type: '${p['type']}',
          session: '${p['session_id'] ?? ''}',
          payload: p['payload'] is Map ? p['payload'] as Map : const {},
        ));
      case {'id': final int id} when !j.containsKey('method'): // server→client requests are not answered
        _pending.remove(id)?.complete(j);
    }
  }

  void _done() {
    closed = true;
    for (final c in _pending.values) {
      c.completeError(const HttpException('connection to Hermes lost'));
    }
    _pending.clear();
    _events.close();
  }

  /// Calls [method]; a JSON-RPC error becomes an [HttpException] with the server's message.
  Future<Map> call(String method, [Map<String, Object?> params = const {}]) async {
    if (closed) throw const HttpException('connection to Hermes lost');
    final id = ++_id;
    final c = _pending[id] = Completer<Map>();
    _send(jsonEncode({'jsonrpc': '2.0', 'id': id, 'method': method, 'params': params}));
    final r = await c.future.timeout(const Duration(seconds: 60), onTimeout: () => throw HttpException('$method timed out'));
    if (r['error'] case final Map e) throw HttpException('${e['message'] ?? 'Hermes error'}');
    return r['result'] is Map ? r['result'] as Map : const {};
  }

  void close() => _close();
}

/// Gateway opener, swappable in tests.
var connectGateway = hermesGateway;

/// Opens the chat gateway. Signed in, the socket takes a one-use ticket; on loopback, the page's token.
Future<Gateway> hermesGateway(Uri base, {String? user, String? password}) async {
  // a fresh client follows the tunnel's HttpOverrides (WebSocket's shared default client would not)
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final auth = await _signIn(client, base, user, password);
    var query = {'token': ?auth.token};
    if (user != null) {
      final req = await client.postUrl(_at(base, '/api/auth/ws-ticket'));
      req.cookies.addAll(auth.cookies);
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      final ticket = switch (_json(body)) {
        {'ticket': final String t} when res.statusCode == 200 => t,
        _ => throw HttpException(_detail(body) ?? 'chat unavailable (HTTP ${res.statusCode})'),
      };
      query = {'ticket': ticket};
    }
    final url = _at(base, '/api/ws').replace(scheme: base.scheme == 'https' ? 'wss' : 'ws', queryParameters: query);
    final ws = await WebSocket.connect(url.toString(), customClient: client);
    ws.pingInterval = const Duration(seconds: 30);
    client.close(); // the upgraded socket is detached from the client
    return Gateway(ws, ws.add, ws.close);
  } catch (_) {
    client.close(force: true);
    rethrow;
  }
}

/// A stored conversation, as `session.list` lists it.
typedef Session = ({String id, String title});

/// The conversations of a `session.list` result; scheduled (cron) runs are left out, as in Hermes' desktop recents.
List<Session> parseSessions(Map result) => [
  for (final s in (result['sessions'] is List ? result['sessions'] as List : const []).whereType<Map>())
    if (s['id'] is String && s['source'] != 'cron')
      (id: s['id'] as String, title: '${(s['title'] ?? '') == '' ? s['preview'] ?? '' : s['title']}'.trim()),
];

/// The user and assistant turns of a gateway transcript (tool rows and hidden rows dropped).
List<Msg> transcript(Object? messages) => [
  for (final m in (messages is List ? messages : const []).whereType<Map>())
    if ((m['role'] == 'user' || m['role'] == 'assistant') && m['display_kind'] != 'hidden')
      if ((m['text'] ?? m['content']) case final String t when t.trim().isNotEmpty) Msg(m['role'] == 'user', t),
];

/// Editable text of each cron job field, from the server's record ([raw] empty for a new job).
Map<String, String> cronFormValues(Map raw) {
  String text(Object? v) => v == null ? '' : '$v';
  String list(Object? v) => v is List ? v.join(', ') : text(v);
  return {
    'name': text(raw['name']),
    // the form takes the same strings the CLI does
    'schedule': switch (raw['schedule']) {
      {'kind': 'cron', 'expr': final String e} => e,
      {'kind': 'interval', 'minutes': final num m} => 'every ${m}m',
      {'kind': 'once', 'run_at': final String t} => t,
      {'display': final String d} => d,
      final String s => s,
      _ => '',
    },
    'repeat': switch (raw['repeat']) {
      {'times': final int t} || final int t => '$t',
      _ => '', // forever
    },
    'prompt': text(raw['prompt']),
    'script': text(raw['script']),
    'skills': list({?raw['skill'], ...(raw['skills'] is List ? raw['skills'] as List : const [])}.toList()),
    'model': text(raw['model']),
    'provider': text(raw['provider']),
    'base_url': text(raw['base_url']),
    'deliver': text(raw['deliver'] ?? 'local'),
    'failure_deliver': text(raw['failure_deliver']),
    'workdir': text(raw['workdir']),
    'enabled_toolsets': list(raw['enabled_toolsets']),
    'context_from': list(raw['context_from']),
  };
}

/// Wire value of each [cronFormValues] field: lists split on commas, repeat as a count or "forever".
Map<String, Object?> cronPayload(Map<String, String> values) => {
  for (final MapEntry(:key, :value) in values.entries)
    key: switch (key) {
      'skills' => [
        for (final s in value.split(','))
          if (s.trim().isNotEmpty) s.trim(),
      ],
      'enabled_toolsets' || 'context_from' when value.trim().isEmpty => null,
      'enabled_toolsets' || 'context_from' => [
        for (final s in value.split(','))
          if (s.trim().isNotEmpty) s.trim(),
      ],
      'repeat' => value.trim().isEmpty ? 'forever' : int.tryParse(value.trim()) ?? value.trim(),
      _ => value.trim(),
    },
};
