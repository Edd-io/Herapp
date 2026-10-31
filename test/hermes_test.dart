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

  test('model options become a flat list keyed by provider', () {
    // shape of /api/model/options (trimmed)
    const body =
        '{"model":"claude-sonnet-5-5","provider":"anthropic","providers":['
        '{"slug":"anthropic","name":"Anthropic","is_current":true,"models":["claude-sonnet-5-5","claude-haiku-5-5"]},'
        '{"slug":"openrouter","name":"OpenRouter","models":["openai/gpt-5"]},'
        '{"slug":"nous","name":"Nous Portal","authenticated":false,"models":["hermes-4"]}]}';
    final r = parseModelOptions(body)!;
    expect(r.current, 'anthropic/claude-sonnet-5-5');
    expect(r.models.map((m) => m.id), ['anthropic/claude-sonnet-5-5', 'anthropic/claude-haiku-5-5', 'openrouter/openai/gpt-5']);
    expect(r.models.last.provider, 'OpenRouter');
    expect(modelName(r.models.last.id), 'openai/gpt-5');
    expect(parseModelOptions('{"detail":"Unauthorized"}'), isNull);
  });

  test('quotas: one per account, windows and rate limits', () {
    // shape of the usage/limit fields of /api/model/options (trimmed)
    const body =
        '{"model":"","provider":"","providers":['
        '{"slug":"a","name":"Sub","models":[],"usage":{"windows":[{"label":"Weekly","used_percent":9.3,'
        '"resets_at":"2026-11-05T12:12:39+00:00","scope":"account"}]}},'
        '{"slug":"b","name":"Pool","models":[],"usage":{"accounts":[{"id":"1","label":"work","windows":[],'
        '"state":"limited","resets_at":"2026-11-01T00:00:00+00:00"}]}},'
        '{"slug":"c","name":"Plain","models":[]}]}';
    final q = parseModelOptions(body)!.quotas;
    expect(q.map((q) => (q.provider, q.account, q.limited)), [('Sub', '', false), ('Pool', 'work', true), ('Plain', '', false)]);
    expect((q[0].windows.single.label, q[0].windows.single.used), ('Weekly', 9.3));
    expect(q[0].windows.single.resetsAt?.toUtc(), DateTime.utc(2026, 11, 5, 12, 12, 39));
    expect(q[1].limitedUntil?.toUtc(), DateTime.utc(2026, 11, 1));
    expect(q[2].windows, isEmpty);
  });

  test('one subscription seen through two providers is shown once', () {
    final reset = DateTime(2026, 11, 1, 4, 20);
    QuotaWindow w(String label, double used, DateTime at) => (label: label, used: used, resetsAt: at);
    final merged = mergeSameAccounts([
      (provider: 'Anthropic', account: '', windows: [w('Current session', 3, reset)], limited: false, limitedUntil: null),
      (
        provider: 'Codex',
        account: '',
        windows: [w('Current session', 3, reset.add(const Duration(hours: 1)))],
        limited: false,
        limitedUntil: null,
      ),
      (
        provider: 'Claude DirectSDK',
        account: '',
        windows: [w('Current session', 3, reset.add(const Duration(seconds: 20))), w('Fable week', 0, reset)],
        limited: false,
        limitedUntil: null,
      ),
    ]);
    expect(merged.map((q) => q.provider), ['Anthropic · Claude DirectSDK', 'Codex']);
    expect(merged.first.windows.map((w) => w.label), ['Current session', 'Fable week']);
  });

  test('models are fetched with the sign-in cookie', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      if (req.uri.path == '/auth/password-login') {
        req.response.cookies.add(Cookie('session', 'abc'));
      } else if (req.uri.path == '/api/model/options' && req.cookies.any((c) => c.value == 'abc')) {
        req.response.write('{"model":"m","provider":"p","providers":[{"slug":"p","name":"P","models":["m"]}]}');
      } else {
        req.response.statusCode = 401;
      }
      await req.response.close();
    });
    addTearDown(server.close);
    final base = Uri.parse('http://127.0.0.1:${server.port}');

    final r = await hermesModels(base, user: 'alice', password: 'right');
    expect((r.current, r.models.single.provider), ('p/m', 'P'));
    expect(hermesModels(base), throwsA(isA<HttpException>())); // no session
  });
}
