import 'dart:convert';
import 'dart:io';

/// Local Hermes fixture for browser integration tests. Binds only to loopback.
Future<void> main() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 8766);
  var session = 0;
  final tickets = <String>{};
  stdout.writeln('Browser test server ready on http://localhost:${server.port}');
  await for (final req in server) {
    final origin = req.headers.value('origin');
    if (origin != null && Uri.tryParse(origin)?.host == 'localhost') {
      req.response.headers
        ..set('Access-Control-Allow-Origin', origin)
        ..set('Access-Control-Allow-Credentials', 'true')
        ..set('Access-Control-Allow-Headers', 'Content-Type, X-Hermes-Session-Token')
        ..set('Access-Control-Allow-Methods', 'GET, POST, PATCH, DELETE, OPTIONS');
    }
    if (req.method == 'OPTIONS') {
      req.response.statusCode = 204;
      await req.response.close();
      continue;
    }
    final path = req.uri.path;
    final signedIn = req.cookies.any((c) => c.name == 'herapp_test_session' && c.value == '$session') && session > 0;
    switch (path) {
      case '/health':
        req.response.write('ok');
      case '/auth/password-login':
        final body = jsonDecode(await utf8.decoder.bind(req).join()) as Map;
        if (body['username'] == 'web' && body['password'] == 'correct') {
          session++;
          req.response.cookies.add(
            Cookie('herapp_test_session', '$session')
              ..httpOnly = true
              ..path = '/',
          );
          req.response.write('{}');
        } else {
          req.response.statusCode = 401;
        }
      case '/test/expire':
        session++;
        req.response.write('{}');
      case '/test/stats':
        req.response.write(jsonEncode({'session': session}));
      case '/api/model/options' when signedIn:
      case '/token/api/model/options' when req.headers.value('X-Hermes-Session-Token') == 'loopback-token':
        req.response.write('{"model":"m","provider":"p","providers":[{"slug":"p","name":"Provider","models":["m"]}]}');
      case '/api/auth/ws-ticket' when signedIn:
        final ticket = 'ticket-$session';
        tickets.add(ticket);
        req.response.write(jsonEncode({'ticket': ticket}));
      case '/api/ws' when tickets.remove(req.uri.queryParameters['ticket']):
      case '/token/api/ws' when req.uri.queryParameters['token'] == 'loopback-token':
        final ws = await WebSocketTransformer.upgrade(req);
        ws.listen((frame) {
          final request = jsonDecode(frame as String) as Map;
          ws.add(
            jsonEncode({
              'id': request['id'],
              'result': {'sessions': []},
            }),
          );
          ws.add(
            jsonEncode({
              'method': 'event',
              'params': {
                'type': 'message.delta',
                'session_id': 'rt',
                'payload': {'text': 'Bonjour'},
              },
            }),
          );
        });
        continue;
      case '/binary':
        final ws = await WebSocketTransformer.upgrade(req);
        ws.listen(ws.add); // echo a binary display frame
        continue;
      case '/token/':
        req.response.write('<script>window.__HERMES_SESSION_TOKEN__ = "loopback-token";</script>');
      default:
        req.response.statusCode = 401;
        req.response.write('{"detail":"Unauthorized"}');
    }
    await req.response.close();
  }
}
