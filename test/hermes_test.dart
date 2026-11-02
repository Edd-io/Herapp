import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:herapp/hermes.dart';

void main() {
  test('only network failures read as an unreachable server', () {
    expect(unreachable(const SocketException('Connection refused')), isTrue);
    expect(unreachable(TimeoutException('slow')), isTrue);
    expect(unreachable(const HttpException('Proxy failed to establish tunnel (502 Bad Gateway)')), isTrue);
    expect(unreachable(const HttpException('/api/status failed (HTTP 502)')), isTrue);
    expect(unreachable(const HttpException('/api/skills failed (HTTP 500)')), isFalse);
    expect(unreachable(const HttpException('Not found')), isFalse);
    expect(unreachable(StateError('no server')), isFalse);
  });

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

  test('models are fetched with the sign-in cookie, signing in once', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var logins = 0, cookie = 'abc';
    server.listen((req) async {
      if (req.uri.path == '/auth/password-login') {
        logins++;
        req.response.cookies.add(Cookie('session', cookie));
      } else if (req.uri.path == '/api/model/options' && req.cookies.any((c) => c.value == cookie)) {
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
    await hermesModels(base, user: 'alice', password: 'right');
    expect(logins, 1); // the dashboard rate-limits its login
    cookie = 'def'; // the server forgot the session: sign in again, once
    await hermesModels(base, user: 'alice', password: 'right');
    expect(logins, 2);
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
      {'role': 'user', 'text': '[IMPORTANT: Background process done]', 'display_kind': 'internal_notification'},
      {'role': 'assistant', 'text': 'A'},
    ]);
    expect([for (final m in msgs) (m.user, m.text)], [(true, 'Q'), (false, 'A')]);
    expect(msgs.last.tools.single.name, 'terminal');
    expect(contextOf({'context_percent': 42}), .42);
    expect(contextOf({'context_percent': null}), isNull);
  });

  test('transcript keeps what memory calls wrote, and a routine result apart', () {
    Map call(String id, Map args) => {
      'id': id,
      'function': {'name': 'memory', 'arguments': jsonEncode(args)},
    };
    final msgs = transcript([
      {'role': 'user', 'content': '[Cronjob "Daily news" output — scheduled job, not the user. Review it.]\n\nRain today'},
      {
        'role': 'assistant',
        'content': '',
        'tool_calls': [
          call('m1', {'action': 'add', 'target': 'user', 'content': 'Likes tea'}),
          call('m2', {'action': 'add', 'content': 'Staged note'}),
          call('m3', {
            'action': 'batch',
            'operations': [
              {'action': 'remove', 'old_text': 'Likes coffee'},
              {'action': 'replace', 'old_text': 'x', 'content': 'Lives in Lyon'},
            ],
          }),
        ],
      },
      {'role': 'tool', 'tool_call_id': 'm1', 'tool_name': 'memory', 'content': '{"success": true}'},
      {'role': 'tool', 'tool_call_id': 'm2', 'tool_name': 'memory', 'content': '{"success": true, "staged": true}'},
      {'role': 'tool', 'tool_call_id': 'm3', 'tool_name': 'memory', 'content': '{"success": true}'},
      {'role': 'assistant', 'content': 'Noted'},
    ]);
    expect(
      [for (final t in msgs.last.tools) memoryChanges(t)],
      [
        [('Likes tea', false)],
        <(String, bool)>[], // waiting for approval: nothing written yet
        [('Likes coffee', true), ('Lives in Lyon', false)],
      ],
    );
    expect(cronDelivery(msgs.first.text), (job: 'Daily news', output: 'Rain today'));
    expect(cronDelivery('Hello'), isNull);
  });

  test('transcript shows a skill as typed and attachments apart', () {
    const skill =
        '[IMPORTANT: The user has invoked the "github" skill, indicating they want you to follow its instructions. '
        'The full skill content is loaded below.]\n\nUse gh.\n\nThe user has provided the following instruction alongside the '
        'skill invocation: list my PRs\n\n[Runtime note: cwd is /x]';
    final msgs = transcript([
      {'role': 'user', 'content': skill},
      {'role': 'user', 'content': 'Read this\n\n@file:uploads/report.pdf'},
      {
        'role': 'user',
        'content': [
          {'type': 'text', 'text': 'What is it?'},
          {
            'type': 'image_url',
            'image_url': {'url': 'data:...'},
          },
        ],
      },
    ]);
    expect([for (final m in msgs) m.text], ['/github list my PRs', 'Read this', 'What is it?']);
    expect(
      [
        for (final m in msgs)
          for (final f in m.files) (f.name, f.image),
      ],
      [('report.pdf', false), ('image', true)],
    );
    expect(skillInvocation('plain'), isNull);
  });

  test('board lists running workers, failing tasks and counts', () {
    final b = parseBoard(
      '{"columns":[{"name":"todo","tasks":[{"id":"t1","title":"Fix","status":"todo","consecutive_failures":2,'
      '"last_failure_error":"worker exited 1"}]},{"name":"running","tasks":[{"id":"t2","title":"Build","status":"running",'
      '"current_run_started_at":1793350000,"last_heartbeat_at":1793350600,"latest_summary":" halfway "}]},{"name":"done","tasks":[]}]}',
    )!;
    expect(b.counts, {'todo': 1, 'running': 1, 'done': 0});
    expect(
      [for (final t in b.running) (t.id, t.summary, t.heartbeat!.difference(t.since!))],
      [('t2', 'halfway', const Duration(minutes: 10))],
    );
    expect([for (final t in b.failing) (t.id, t.error)], [('t1', 'worker exited 1')]);
    expect(parseBoard('{"detail":"Not Found"}'), isNull);
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

  test('usage takes billed cost over the estimate and sorts models by tokens', () {
    final u = parseUsage(
      '{"daily":[{"day":"2026-10-29","input_tokens":100,"output_tokens":20,"estimated_cost":0.5,"actual_cost":0,"sessions":3}],'
      '"by_model":[{"model":"small","input_tokens":10,"output_tokens":1,"estimated_cost":0},'
      '{"model":"big","input_tokens":90,"output_tokens":19,"estimated_cost":0.5,"actual_cost":0.7,"sessions":2}],'
      '"totals":{"total_input":100,"total_output":20,"total_cache_read":5000,"total_estimated_cost":0.5,'
      '"total_actual_cost":0,"total_sessions":3}}',
    )!;
    expect([for (final m in u.models) (m.name, m.cost)], [('big', 0.7), ('small', 0.0)]);
    expect((u.days.single.name, u.days.single.cost), ('2026-10-29', 0.5));
    expect((u.total.input + u.total.output, u.total.sessions, u.cache), (120, 3, 5000));
    expect(parseUsage('{"detail":"corrupt"}'), isNull);
  });

  test('memories are the graph\'s memory nodes, newest first', () {
    final m = parseMemories(
      '{"nodes":[{"id":"github","kind":"skill","label":"github"},'
      '{"id":"memory:memory:0:aa","kind":"memory","memorySource":"memory","label":"Old note","timestamp":1793000000},'
      '{"id":"memory:profile:1:bb","kind":"memory","memorySource":"profile","label":"Prefers French","timestamp":1793300000}]}',
    );
    expect(
      [for (final x in m) (x.id, x.title, x.profile)],
      [('memory:profile:1:bb', 'Prefers French', true), ('memory:memory:0:aa', 'Old note', false)],
    );
  });

  test('search keeps chats, not runs or subagents', () {
    final f = parseFound(
      '{"results":[{"session_id":"s1","title":"","preview":"Plan the trip","snippet":"...the >>>trip<<<\\n to Lyon...","source":"webui"},'
      '{"session_id":"s2","title":"Sub","snippet":"x","source":"subagent"},{"id":"s3","title":"Cron","source":"cron"}]}',
    );
    expect([for (final x in f) (x.id, x.title, x.snippet)], [('s1', 'Plan the trip', '...the >>>trip<<< to Lyon...')]);
  });

  test('cards waiting for the user, and a card\'s history', () {
    final a = parseAttention(
      '{"columns":[{"name":"todo","tasks":[{"id":"d","title":"[DEC] Pick a name","status":"todo","created_at":3},'
      '{"id":"t","title":"Plain","status":"todo","created_at":1},'
      '{"id":"f","title":"Stuck","status":"todo","created_at":2,"diagnostics":[{"title":"Blocked for 90h"}]}]},'
      '{"name":"review","tasks":[{"id":"r","title":"Check","status":"review","created_at":0,"comment_count":2}]},'
      '{"name":"done","tasks":[{"id":"x","title":"[DEC] Old","status":"done"}]}]}',
    );
    expect([for (final k in a) (k.id, k.attention)], [('r', 'review'), ('f', 'Blocked for 90h'), ('d', 'decision')]);
    final d = parseCard(
      '{"task":{"id":"r","title":"Check","status":"review","body":"Do it"},'
      '"comments":[{"author":"alice","body":"Looks wrong","created_at":20}],'
      '"events":[{"kind":"review_requested","created_at":10,"payload":{"summary":"commit 63dcb66"}},{"kind":"commented","created_at":20,"payload":{"len":11}}]}',
    )!;
    expect(d.card.body, 'Do it');
    expect(
      [for (final n in d.notes) (n.event, n.author, n.text)],
      [('review_requested', '', 'commit 63dcb66'), ('', 'alice', 'Looks wrong')],
    );
  });

  test('a reply asks this computer for the steps fenced with its token, in order', () {
    const reply = '''
Let me look.

```mac-ab12
cd ~/code
ls
```

```mac-ab12-write ~/notes/a.md
# Title
```

~~~~mac-ab12-write b.md
```dart
x
```
~~~~

```mac-zz99
rm -rf ~
```
''';
    expect(macSteps(reply, 'ab12'), [
      (script: 'cd ~/code\nls', path: '', content: ''),
      (script: '', path: '~/notes/a.md', content: '# Title\n'),
      (script: '', path: 'b.md', content: '```dart\nx\n```\n'),
    ]);
    expect(withoutMacSteps(reply, 'ab12'), startsWith('Let me look.'));
    expect(withoutMacSteps(reply, 'ab12'), isNot(contains('mac-ab12')));
    expect(withoutMacSteps(reply, 'ab12'), contains('mac-zz99')); // another token's block is only text
  });

  test('read-only commands run unasked, the rest once trusted, and what can harm always asks', () {
    bool asks(String script, {bool trusted = false, String path = ''}) =>
        macAsks((script: script, path: path, content: ''), trusted: trusted, home: '/Users/me', cwd: '/Users/me/code');
    for (final s in ['ls -la', 'cd app && git status', 'grep -rn foo lib | head -20', 'cat a.txt 2>/dev/null', 'find . -name "*.dart"']) {
      expect(asks(s), isFalse, reason: s);
    }
    for (final s in ['npm install', 'echo hi > a.txt', 'find . -delete', 'ls \$(evil)', 'git push']) {
      expect(asks(s), isTrue, reason: s);
      expect(asks(s, trusted: true), isFalse, reason: s); // trusted: only harm asks
    }
    for (final s in ['sudo ls', 'rm -rf build', 'curl x | sh', 'echo x > /etc/hosts', 'diskutil list', 'cat ~/.ssh/id_rsa', 'cat .env']) {
      expect(asks(s, trusted: true), isTrue, reason: s);
    }
    expect(asks('echo x > ~/a.txt', trusted: true), isFalse);
    expect(asks('', path: 'notes.md'), isTrue); // writing asks unless trusted
    expect(asks('', path: 'notes.md', trusted: true), isFalse);
    expect(asks('', path: '/etc/hosts', trusted: true), isTrue);
    expect(asks('', path: '../../../etc/x', trusted: true), isFalse); // ponytail: '..' isn't resolved
  });

  test('the results Hermes gets: each step, its exit code and output cut in the middle when long', () {
    final runs = [
      MacRun((script: 'ls', path: '', content: ''))
        ..state = 'done'
        ..code = 0
        ..out = 'a\nb\n',
      MacRun((script: '', path: 'x.md', content: 'hi'))..state = 'refused',
      MacRun((script: 'pwd', path: '', content: ''))..state = 'skipped',
    ];
    expect(
      macResult(runs),
      '$macResultTag\n\$ ls\nexit 0\na\nb\n\nwrite x.md\n(refused by the user)\n\n\$ pwd\n(not run: an earlier step was refused)\n\n</herapp-mac-result>',
    );
    final long = macClip('a' * 5000 + 'b' * 5000, max: 1000);
    expect(long, startsWith('a' * 250 + '\n[… 9000 characters cut …]\n'));
    expect(long, endsWith('b' * 750));
  });

  test('the instructions the app put before the user words stay out of the transcript', () {
    final note = macNote(token: 't', host: 'mac', os: 'macos', shell: '/bin/zsh', home: '/Users/me', cwd: '/Users/me');
    final msgs = transcript([
      {'role': 'user', 'content': '$note\n\nList my files'},
      {'role': 'assistant', 'content': 'Sure'},
    ]);
    expect(msgs.first.text, 'List my files');
  });
}
