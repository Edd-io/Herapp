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

/// Models from the server's `/api/model/options`, plus its default model id.
/// Null if [body] isn't that payload.
({List<Model> models, String current})? parseModelOptions(String body) {
  try {
    final j = jsonDecode(body);
    if (j is! Map || j['providers'] is! List) return null;
    return (
      models: [
        for (final p in (j['providers'] as List).whereType<Map>())
          if (p['authenticated'] != false)
            for (final m in (p['models'] as List? ?? []).whereType<String>())
              (provider: '${p['name'] ?? p['slug']}', name: m, id: '${p['slug']}/$m'),
      ],
      current: j['model'] is String && j['provider'] is String && j['model'] != '' ? '${j['provider']}/${j['model']}' : '',
    );
  } on FormatException {
    return null;
  }
}

/// Fetches the models the server can use. Signs in when [user] is set; otherwise
/// reuses the session token a loopback dashboard injects into its page.
// ponytail: signs in on every call, keep the session cookie once the chat needs it too
Future<({List<Model> models, String current})> hermesModels(Uri base, {String? user, String? password}) async {
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
    final req = await client.getUrl(_at(base, '/api/model/options'));
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
