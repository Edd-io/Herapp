import 'dart:convert';
import 'dart:io';

class Msg {
  Msg(this.user, this.text);
  final bool user;
  String text;
}

typedef Model = ({String provider, String name, String desc, String id});

// ponytail: hardcoded list, replace with the one exposed by Hermes
const models = <Model>[
  (provider: 'Anthropic', name: 'Claude Opus 5.5', desc: 'Most capable, deep reasoning', id: 'anthropic/claude-opus-5-5'),
  (provider: 'Anthropic', name: 'Claude Sonnet 5.5', desc: 'Balance of speed and quality', id: 'anthropic/claude-sonnet-5-5'),
  (provider: 'Anthropic', name: 'Claude Haiku 5.5', desc: 'Fast and lightweight', id: 'anthropic/claude-haiku-5-5'),
  (provider: 'OpenAI', name: 'GPT-5', desc: 'OpenAI flagship model', id: 'openai/gpt-5'),
  (provider: 'Google', name: 'Gemini 2.5 Pro', desc: 'Very long context, multimodal', id: 'google/gemini-2.5-pro'),
  (provider: 'Nous Research', name: 'Hermes 4 405B', desc: 'Open-weight, agent-oriented', id: 'nousresearch/hermes-4-405b'),
  (provider: 'Local', name: 'Ollama', desc: 'Runs on your machine', id: 'ollama/default'),
];

Model modelOf(String id) => models.firstWhere((m) => m.id == id, orElse: () => models.first);

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
      'Got it (${modelOf(model).name}): "${history.last.text}". I\'m not connected yet, '
      'but once Hermes is hooked up, its replies will stream in here '
      'with the same progressive fade as this demo.';
  for (final word in reply.split(' ')) {
    await Future.delayed(const Duration(milliseconds: 45));
    yield '$word ';
  }
}
