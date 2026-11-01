import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

class Msg {
  Msg(this.user, this.text, [List<Tool>? tools, List<Attachment>? files]) : tools = tools ?? [], files = files ?? [];
  final bool user;
  String text;

  /// What the user attached to this message.
  final List<Attachment> files;

  /// The tools Hermes ran for this reply, in order.
  final List<Tool> tools;

  /// A command waiting for the user's approval: the server request [GatewayEvent.id] and its params.
  ({Object id, Map params})? ask;
}

/// A photo or file sent with a message; [bytes] is null for one read back from the server's history.
typedef Attachment = ({String name, Uint8List? bytes, bool image});

/// One tool call of a reply; [detail] is what it works on (a command, a path, a query), [args] its arguments.
class Tool {
  Tool(this.id, this.name, this.detail, {this.done = false, this.args = const {}});
  final String id, name, detail;
  bool done;
  Map args;
}

/// What a `memory` tool call wrote, as (entry, forgotten) pairs; empty for another tool.
List<(String, bool)> memoryChanges(Tool t) => [
  if (t.name == 'memory')
    for (final o in t.args['action'] == 'batch' ? (t.args['operations'] as List? ?? const []).whereType<Map>() : [t.args])
      if ((o['action'] == 'remove' ? o['old_text'] : o['content'] ?? o['new_text']) case final String text when text.trim().isNotEmpty)
        (text.trim(), o['action'] == 'remove'),
];

/// Whether a `memory` tool [result] wrote to memory (not refused, nor staged for approval).
bool memorySaved(Object? result) => switch (result is String ? _json(result) : result) {
  {'success': true} && final Map r => r['staged'] != true,
  _ => false,
};

/// A model offered by the Hermes server; [id] = "providerSlug/model".
/// A server model; [reasoning] is false for one that takes no reasoning effort.
typedef Model = ({String provider, String name, String id, bool reasoning});

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
            (
              provider: '${p['name'] ?? p['slug']}',
              name: m,
              id: '${p['slug']}/$m',
              reasoning: ((p['capabilities'] as Map?)?[m] as Map?)?['reasoning'] != false,
            ),
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
typedef _Auth = ({List<Cookie> cookies, String? token});

/// Sign-ins kept per server and account: the dashboard rate-limits its login (HTTP 429).
final _auths = <String, Future<_Auth>>{};

/// Drops the kept sign-ins (the server settings changed).
void forgetSignIns() => _auths.clear();

/// The kept sign-in for [base], made with [client] on first use; [fresh] drops the kept one.
Future<_Auth> _session(HttpClient client, Uri base, String? user, String? password, {bool fresh = false}) {
  final key = '$base\n$user\n$password';
  if (fresh) _auths.remove(key);
  // a sign-in left hanging (tunnel down) must fail, or every later call would wait on it
  return _auths[key] ??= _signIn(client, base, user, password).timeout(const Duration(seconds: 15))
    ..catchError((Object _) {
      _auths.remove(key); // a failed sign-in is retried next time
      return (cookies: <Cookie>[], token: null);
    });
}

Future<_Auth> _signIn(HttpClient client, Uri base, String? user, String? password) async {
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
    for (var fresh = false; ; fresh = true) {
      final auth = await _session(client, base, user, password, fresh: fresh);
      final req = await client.openUrl(method, _at(base, path).replace(queryParameters: query));
      req.cookies.addAll(auth.cookies);
      if (auth.token != null) req.headers.set('X-Hermes-Session-Token', auth.token!);
      if (body != null) {
        req.headers.contentType = ContentType.json;
        req.write(jsonEncode(body));
      }
      final res = await req.close();
      final text = await res.transform(utf8.decoder).join();
      if (res.statusCode == 401 && !fresh) continue; // the kept sign-in expired: sign in again, once
      if (res.statusCode ~/ 100 != 2) throw HttpException(_detail(text) ?? '$path failed (HTTP ${res.statusCode})');
      return text;
    }
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
/// An event, or a server→client request when [id] is set (its answer goes back through [Gateway.reply]).
typedef GatewayEvent = ({String type, String session, Map payload, Object? id});

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
          id: null,
        ));
      case {'id': final Object id, 'method': final String m, 'params': final Map p}:
        _events.add((type: m, session: '${p['session_id'] ?? ''}', payload: p, id: id));
      case {'id': final int id}:
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

  /// Answers the server request [id] with [result], or refuses it when [result] is null.
  void reply(Object id, Map<String, Object?>? result) {
    if (closed) return;
    _send(
      jsonEncode({
        'jsonrpc': '2.0',
        'id': id,
        if (result != null) 'result': result else 'error': {'code': -32601, 'message': 'not supported by Herapp'},
      }),
    );
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
    var auth = await _session(client, base, user, password);
    var query = {'token': ?auth.token};
    for (var fresh = false; user != null; fresh = true) {
      if (fresh) auth = await _session(client, base, user, password, fresh: true);
      final req = await client.postUrl(_at(base, '/api/auth/ws-ticket'));
      req.cookies.addAll(auth.cookies);
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      if (res.statusCode == 401 && !fresh) continue; // the kept sign-in expired
      final ticket = switch (_json(body)) {
        {'ticket': final String t} when res.statusCode == 200 => t,
        _ => throw HttpException(_detail(body) ?? 'chat unavailable (HTTP ${res.statusCode})'),
      };
      query = {'ticket': ticket};
      break;
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

/// The user and assistant turns of a transcript; tool rows go to the reply that follows them.
List<Msg> transcript(Object? messages) {
  final out = <Msg>[];
  var tools = <Tool>[];
  final args = <String, Map>{}; // of each tool call, by id, from the assistant turn that made it
  for (final m in (messages is List ? messages : const []).whereType<Map>()) {
    // compaction notes and the gateway's own notices (background jobs done...) aren't the user's words
    if (m['display_kind'] == 'hidden' || m['display_kind'] == 'internal_notification') continue;
    for (final call in (m['tool_calls'] is List ? m['tool_calls'] as List : const []).whereType<Map>()) {
      final a = (call['function'] as Map?)?['arguments'];
      if ((a is String ? _json(a) : a) case final Map map) args['${call['id']}'] = map;
    }
    if (m['role'] == 'tool') {
      final name = '${m['name'] ?? m['tool_name'] ?? 'tool'}';
      final tool = Tool('${m['tool_call_id'] ?? tools.length}', name, '', done: true);
      // a memory card only for what was really written
      if (name != 'memory' || memorySaved(m['content'])) tool.args = args[tool.id] ?? const {};
      tools.add(tool);
    }
    if (m['role'] != 'user' && m['role'] != 'assistant') continue;
    final user = m['role'] == 'user';
    var text = '';
    final files = <Attachment>[];
    switch (m['text'] ?? m['content']) {
      case final String t:
        text = t;
      case final List parts: // a message sent with images
        for (final p in parts.whereType<Map>()) {
          if (p['text'] is String) {
            text += p['text'] as String;
          } else if ('${p['type']}'.contains('image')) {
            files.add((name: 'image', bytes: null, image: true));
          }
        }
    }
    if (user) {
      // what the app sent along: an attached image's marker, a staged file's @file: reference
      text = (skillInvocation(text) ?? text).replaceAllMapped(RegExp(r'\[User attached image: ([^\]]+)\]|@file:"([^"]+)"|@file:(\S+)'), (
        x,
      ) {
        files.add((name: (x[1] ?? x[2] ?? x[3]!).split('/').last, bytes: null, image: x[1] != null));
        return '';
      }).trim();
    }
    if (text.trim().isNotEmpty || files.isNotEmpty) {
      out.add(Msg(user, text, user ? null : tools, files));
      tools = [];
    }
  }
  return out;
}

/// The `/skill instruction` a skill-expanded user turn came from, null when [text] isn't one
/// (the server stores the skill's whole body as the user's message).
String? skillInvocation(String text) {
  const prefix = '[IMPORTANT: The user has invoked the "',
      said = 'The user has provided the following instruction alongside the skill invocation: ';
  if (!text.startsWith(prefix)) return null;
  final name = text.substring(prefix.length).split('"').first;
  final at = text.lastIndexOf(said);
  final instruction = at < 0 ? '' : text.substring(at + said.length).split('\n\n[Runtime note:').first.trim();
  final command = name.startsWith('/') ? name : '/$name';
  return instruction.isEmpty ? command : '$command $instruction';
}

/// A `/` completion: a Hermes command or one of its skills.
typedef Slash = ({String text, String display, String meta, bool skill});

/// `complete.slash`.
List<Slash> parseSlash(Map result) => [
  if (result case {'items': final List items})
    for (final i in items.whereType<Map>())
      (text: '${i['text'] ?? ''}', display: '${i['display'] ?? i['text'] ?? ''}', meta: '${i['meta'] ?? ''}', skill: i['kind'] == 'skill'),
];

/// A task of the kanban board; [heartbeat] is a running worker's last sign of life.
typedef KTask = ({String id, String title, DateTime? since, DateTime? heartbeat, String summary, String error});

/// The kanban board as the workers see it: tasks per status, the ones running, the ones failing.
typedef Board = ({Map<String, int> counts, List<KTask> running, List<KTask> failing});

/// `/api/plugins/kanban/board`; null when the server has no kanban.
Board? parseBoard(String body) {
  if (_json(body) case {'columns': final List columns}) {
    DateTime? at(Object? s) => s is num ? DateTime.fromMillisecondsSinceEpoch((s * 1000).round()) : null;
    KTask task(Map t) => (
      id: '${t['id']}',
      title: '${t['title'] ?? ''}',
      since: at(t['current_run_started_at'] ?? t['started_at']),
      heartbeat: at(t['last_heartbeat_at']),
      summary: '${t['latest_summary'] ?? ''}'.trim(),
      error: '${t['last_failure_error'] ?? ''}'.trim(),
    );
    final counts = <String, int>{}, running = <KTask>[], failing = <KTask>[];
    for (final c in columns.whereType<Map>()) {
      final tasks = (c['tasks'] as List? ?? const []).whereType<Map>();
      counts['${c['name']}'] = tasks.length;
      for (final t in tasks) {
        if (t['status'] == 'running') running.add(task(t));
        if (t['status'] != 'done' && (t['consecutive_failures'] as num? ?? 0) > 0 && task(t).error.isNotEmpty) failing.add(task(t));
      }
    }
    return (counts: counts, running: running, failing: failing);
  }
  return null;
}

/// One past run of a cron job; [session] runs (agent ones) have a transcript, the others only [preview].
typedef CronRun = ({String id, String title, String preview, DateTime? at, bool active, bool session});

/// Where a script run's whole output lies on the server (the runs list only gives 180 characters of it),
/// null for a run with no output file.
String? cronOutputPath(CronRun r, String hermesHome) => switch (RegExp(r'^cron_output:([^:]+):(.+)$').firstMatch(r.id)) {
  final m? when hermesHome.isNotEmpty && !m[2]!.startsWith('exec:') => '$hermesHome/cron/output/${m[1]}/${m[2]}.md',
  _ => null,
};

/// A script run's output file without the header Hermes writes above it (job, id, time, mode).
String cronOutputText(String doc) {
  final cut = doc.indexOf('\n---\n');
  return (doc.startsWith('# Cron Job:') && cut >= 0 ? doc.substring(cut + 5) : doc).trim();
}

/// `/api/cron/jobs/{id}/runs`, newest first.
List<CronRun> parseCronRuns(String body) => [
  if (_json(body) case {'runs': final List runs})
    for (final r in runs.whereType<Map>())
      (
        id: '${r['id']}',
        title: '${r['title'] ?? ''}',
        preview: '${r['preview'] ?? ''}',
        at: r['started_at'] is num ? DateTime.fromMillisecondsSinceEpoch(((r['started_at'] as num) * 1000).round()) : null,
        active: r['is_active'] == true,
        session: r['source'] != 'cron_output',
      ),
];

/// An item of Hermes' vault, metadata only: the server never sends a password back.
typedef VaultItem = ({String id, String kind, String label, String origin, String identifier, bool otp, String backend});

/// `vault.list`.
List<VaultItem> parseVault(Map result) => [
  if (result case {'items': final List items})
    for (final i in items.whereType<Map>())
      if (i['id'] is String)
        (
          id: i['id'] as String,
          kind: '${i['kind'] ?? 'login'}',
          label: '${i['label'] ?? ''}',
          origin: '${i['origin'] ?? ''}',
          identifier: '${i['identifier'] ?? ''}',
          otp: i['has_otp'] == true,
          backend: '${i['backend'] ?? 'local'}',
        ),
];

/// A site typed without a scheme ("github.com") as the vault wants it ("https://github.com").
String vaultOrigin(String site) {
  final s = site.trim();
  return s.isEmpty || s.contains('://') ? s : 'https://$s';
}

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
    'reasoning_effort': text(raw['reasoning_effort']),
    'deliver': text(raw['deliver'] ?? 'local'),
    'failure_deliver': text(raw['failure_deliver']),
    'workdir': text(raw['workdir']),
    'enabled_toolsets': list(raw['enabled_toolsets']),
    'context_from': list(raw['context_from']),
    'monitor_script': text(raw['monitor_script']),
    'monitor_url': text(raw['monitor_url']),
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

int _int(Object? v) => v is num ? v.round() : 0;
double _num(Object? v) => v is num ? v.toDouble() : 0;
DateTime? _epoch(Object? s) => s is num ? DateTime.fromMillisecondsSinceEpoch((s * 1000).round()) : null;

/// Token use of one day or one model; [cost] is the billed cost, else Hermes' estimate.
typedef UsageRow = ({String name, int input, int output, double cost, int sessions});

/// `/api/analytics/usage`: per day (oldest first) and per model (busiest first), and the totals.
typedef Usage = ({List<UsageRow> days, List<UsageRow> models, UsageRow total, int cache});

Usage? parseUsage(String body) {
  if (_json(body) case {'daily': final List daily, 'totals': final Map t} && final j) {
    double cost(Object? actual, Object? estimated) => _num(actual) > 0 ? _num(actual) : _num(estimated);
    UsageRow row(Map r, String name) => (
      name: name,
      input: _int(r['input_tokens']),
      output: _int(r['output_tokens']),
      cost: cost(r['actual_cost'], r['estimated_cost']),
      sessions: _int(r['sessions']),
    );
    final models = [for (final m in (j['by_model'] as List? ?? const []).whereType<Map>()) row(m, '${m['model'] ?? ''}')]
      ..sort((a, b) => (b.input + b.output).compareTo(a.input + a.output));
    return (
      days: [for (final d in daily.whereType<Map>()) row(d, '${d['day'] ?? ''}')],
      models: models,
      total: (
        name: '',
        input: _int(t['total_input']),
        output: _int(t['total_output']),
        cost: cost(t['total_actual_cost'], t['total_estimated_cost']),
        sessions: _int(t['total_sessions']),
      ),
      cache: _int(t['total_cache_read']),
    );
  }
  return null;
}

/// An entry of what Hermes remembers: of the user ([profile], USER.md) or its own notes (MEMORY.md).
/// [id] carries a fingerprint, so it goes stale once the entry changes: reload after an edit.
typedef Memory = ({String id, String title, bool profile, DateTime? at});

/// The memory entries of `/api/learning/graph`, newest first.
List<Memory> parseMemories(String body) => [
  if (_json(body) case {'nodes': final List nodes})
    for (final n in nodes.whereType<Map>())
      if (n['kind'] == 'memory' && n['id'] is String)
        (id: n['id'] as String, title: '${n['label'] ?? ''}', profile: n['memorySource'] == 'profile', at: _epoch(n['timestamp'])),
]..sort((a, b) => (b.at ?? DateTime(0)).compareTo(a.at ?? DateTime(0)));

/// A conversation whose content matches a search; [snippet] marks the hits with `>>>` and `<<<`.
typedef Found = ({String id, String title, String snippet});

/// `/api/sessions/search`, scheduled runs and subagents left out as in the sidebar.
List<Found> parseFound(String body) => [
  if (_json(body) case {'results': final List results})
    for (final r in results.whereType<Map>())
      if ((r['session_id'] ?? r['id']) is String && r['source'] != 'cron' && r['source'] != 'subagent')
        (
          id: (r['session_id'] ?? r['id']) as String,
          title: '${(r['title'] ?? '') == '' ? r['preview'] ?? '' : r['title']}'.trim(),
          snippet: '${r['snippet'] ?? ''}'.replaceAll(RegExp(r'\s+'), ' ').trim(),
        ),
];

/// A Kanban card; [attention] says why it waits for the user ('' when it doesn't).
typedef KCard = ({String id, String title, String status, String body, String summary, int comments, String attention, DateTime? at});

KCard _kcard(Map t) {
  final status = '${t['status'] ?? ''}';
  final diagnostics = t['diagnostics'] is List ? (t['diagnostics'] as List).whereType<Map>() : const <Map>[];
  return (
    id: '${t['id']}',
    title: '${t['title'] ?? ''}',
    status: status,
    body: '${t['body'] ?? ''}'.trim(),
    summary: '${t['latest_summary'] ?? ''}'.trim(),
    comments: _int(t['comment_count']),
    attention: switch (status) {
      'review' || 'blocked' => status,
      'done' || 'archived' => '',
      _ when diagnostics.isNotEmpty => '${diagnostics.first['title'] ?? 'diagnostic'}',
      _ when '${t['title']}'.startsWith('[DEC]') => 'decision',
      _ => '',
    },
    at: _epoch(t['created_at']),
  );
}

/// The cards of a `/board` waiting for the user (to review, blocked, flagged, decisions), oldest first.
List<KCard> parseAttention(String body) => [
  if (_json(body) case {'columns': final List columns})
    for (final c in columns.whereType<Map>())
      for (final t in (c['tasks'] as List? ?? const []).whereType<Map>())
        if (_kcard(t) case final k when k.attention.isNotEmpty) k,
]..sort((a, b) => (a.at ?? DateTime(0)).compareTo(b.at ?? DateTime(0)));

/// A comment on a card, or a step of its history ([event] then names its kind).
typedef KNote = ({String author, String text, DateTime? at, String event});

/// `/tasks/{id}`: the card in full and its comments, with the reviews and runs it went through.
({KCard card, List<KNote> notes})? parseCard(String body) {
  if (_json(body) case {'task': final Map t} && final j) {
    final notes = <KNote>[
      for (final c in (j['comments'] as List? ?? const []).whereType<Map>())
        (author: '${c['author'] ?? ''}', text: '${c['body'] ?? ''}'.trim(), at: _epoch(c['created_at']), event: ''),
      for (final e in (j['events'] as List? ?? const []).whereType<Map>())
        if (e['payload'] case {'summary': final String s} when s.trim().isNotEmpty)
          (author: '', text: s.trim(), at: _epoch(e['created_at']), event: '${e['kind'] ?? ''}'),
    ]..sort((a, b) => (a.at ?? DateTime(0)).compareTo(b.at ?? DateTime(0)));
    return (card: _kcard(t), notes: notes);
  }
  return null;
}
