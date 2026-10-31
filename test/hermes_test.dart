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

  test('chat gateway opens with a sign-in ticket and speaks JSON-RPC', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      switch (req.uri.path) {
        case '/auth/password-login':
          req.response.cookies.add(Cookie('session', 'abc'));
        case '/api/auth/ws-ticket' when req.method == 'POST' && req.cookies.any((c) => c.value == 'abc'):
          req.response.write('{"ticket":"t1","ttl_seconds":30}');
        case '/api/ws' when req.uri.queryParameters['ticket'] == 't1':
          final ws = await WebSocketTransformer.upgrade(req);
          ws.listen((f) {
            final j = jsonDecode(f as String) as Map;
            ws.add(
              jsonEncode({
                'jsonrpc': '2.0',
                'method': 'event',
                'params': {
                  'type': 'message.delta',
                  'session_id': 'rt',
                  'payload': {'text': 'hi'},
                },
              }),
            );
            ws.add(
              jsonEncode(
                j['method'] == 'session.list'
                    ? {
                        'jsonrpc': '2.0',
                        'id': j['id'],
                        'result': {
                          'sessions': [
                            {'id': 's1', 'title': '', 'preview': 'First question'},
                            {'id': 's2', 'title': 'Nightly', 'source': 'cron'},
                          ],
                        },
                      }
                    : {
                        'jsonrpc': '2.0',
                        'id': j['id'],
                        'error': {'code': 4004, 'message': 'unknown method'},
                      },
              ),
            );
          });
          return;
        default:
          req.response.statusCode = 401;
      }
      await req.response.close();
    });
    addTearDown(server.close);
    final g = await hermesGateway(Uri.parse('http://127.0.0.1:${server.port}'), user: 'alice', password: 'right');
    addTearDown(g.close);

    final event = g.events.first;
    expect(parseSessions(await g.call('session.list')), [(id: 's1', title: 'First question')]);
    final e = await event;
    expect((e.type, e.session, e.payload['text']), ('message.delta', 'rt', 'hi'));
    expect(g.call('nope'), throwsA(isA<HttpException>().having((e) => e.message, 'message', 'unknown method')));
  });

  test('transcript keeps user and assistant text only', () {
    final msgs = transcript([
      {'role': 'system', 'text': 'You are Hermes'},
      {'role': 'user', 'text': 'Q'},
      {'role': 'assistant', 'text': ''}, // tool call only
      {'role': 'tool', 'content': 'output', 'name': 'terminal'},
      {'role': 'user', 'text': 'note', 'display_kind': 'hidden'},
      {'role': 'assistant', 'text': 'A'},
    ]);
    expect([for (final m in msgs) (m.user, m.text)], [(true, 'Q'), (false, 'A')]);
    expect(contextOf({'context_percent': 42}), .42);
    expect(contextOf({'context_percent': null}), isNull);
  });

  test('cron jobs keep schedule, state, runs and the last error', () {
    const body =
        '[{"id":"a1","name":"Nightly summary","enabled":false,"state":"paused","schedule":{"kind":"cron","expr":"0 7 * * *",'
        '"display":"0 7 * * *"},"schedule_display":"0 7 * * *","next_run_at":"2026-10-30T07:00:00+01:00",'
        '"last_run_at":"2026-10-29T07:00:12+01:00","last_status":"ok","last_error":null},'
        '{"id":"b2","name":"Backup","schedule":{"kind":"once","display":"once at 2026-10-30 07:30"},"last_status":"error",'
        '"last_error":"disk full","state":"scheduled"}]';
    final jobs = parseCronJobs(body);
    expect(
      [for (final j in jobs) (j.id, j.schedule, j.enabled, j.state, j.lastError)],
      [('a1', '0 7 * * *', false, 'paused', null), ('b2', 'once at 2026-10-30 07:30', true, 'scheduled', 'disk full')],
    );
    expect(jobs.first.lastRun!.toUtc(), DateTime.utc(2026, 10, 29, 6, 0, 12));
    expect(parseCronJobs('{"jobs":[{"id":"x"}]}').single.name, 'x');
  });

  test('cron form shows the CLI strings and sends the wire shapes', () {
    final v = cronFormValues({
      'name': 'Planner',
      'schedule': {'kind': 'cron', 'expr': '0 * * * *', 'display': '0 * * * *'},
      'repeat': {'times': null, 'completed': 11},
      'skill': 'kanban',
      'skills': ['kanban', 'git'],
      'script': 'planner-tick.py',
      'deliver': 'discord',
      'enabled_toolsets': null,
      'context_from': ['a1', 'b2'],
    });
    expect((v['schedule'], v['repeat'], v['skills'], v['context_from'], v['model']), ('0 * * * *', '', 'kanban, git', 'a1, b2', ''));
    expect(
      cronFormValues({
        'schedule': {'kind': 'interval', 'minutes': 30},
      })['schedule'],
      'every 30m',
    );
    expect(
      cronFormValues({
        'schedule': {'kind': 'once', 'run_at': '2026-11-02T08:00:00+01:00'},
      })['schedule'],
      '2026-11-02T08:00:00+01:00',
    );
    expect(cronFormValues({})['deliver'], 'local'); // new job default

    final p = cronPayload({...v, 'repeat': '3', 'enabled_toolsets': ' ', 'model': ' gpt-5 '});
    expect(
      [p['repeat'], p['skills'], p['context_from'], p['enabled_toolsets'], p['model']],
      [
        3,
        ['kanban', 'git'],
        ['a1', 'b2'],
        null,
        'gpt-5',
      ],
    );
    expect(cronPayload({'repeat': ''})['repeat'], 'forever');
  });
}
