import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:herapp/hermes.dart';

void main() {
  test('status URL is built from the base URL', () {
    expect(hermesStatusUri(Uri.parse('https://h.example/')).toString(), 'https://h.example/api/status');
    expect(hermesStatusUri(Uri.parse('https://h.example')).toString(), 'https://h.example/api/status');
    expect(hermesStatusUri(Uri.parse('https://h.example/sub/')).toString(), 'https://h.example/sub/api/status');
  });

  test('only a Hermes /api/status payload is recognized', () {
    // trimmed sample of a real Hermes 0.22.5 response
    const hermes =
        '{"version":"0.22.5","release_date":"2026.9.24","can_update_hermes":true,'
        '"gateway_running":true,"gateway_state":"running","auth_required":true}';
    expect(hermesStatus(hermes), (version: '0.22.5', authRequired: true));
    expect(hermesStatus('{"ok":true,"version":"1.0"}'), isNull); // generic API
    expect(hermesStatus('<!DOCTYPE html><title>Homelab</title>'), isNull); // dashboard page
    expect(hermesStatus('[]'), isNull);
  });

  test('login posts the web form JSON and reports the outcome', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      final body = jsonDecode(await utf8.decoder.bind(req).join()) as Map;
      final good = req.method == 'POST' && req.uri.path == '/sub/auth/password-login' && body['provider'] == 'basic';
      if (good && body['username'] == 'alice' && body['password'] == 'right') {
        req.response.cookies.add(Cookie('session', 'abc'));
      } else {
        req.response.statusCode = good ? 401 : 404;
      }
      await req.response.close();
    });
    addTearDown(server.close);
    final client = HttpClient();
    addTearDown(client.close);
    final base = Uri.parse('http://127.0.0.1:${server.port}/sub/');

    final ok = await hermesLogin(client, base, 'alice', 'right');
    expect((ok.ok, ok.cookies.single.name), (true, 'session'));
    final bad = await hermesLogin(client, base, 'alice', 'wrong');
    expect((bad.ok, bad.status), (false, 401));
  });
}
