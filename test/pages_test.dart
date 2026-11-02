import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herapp/agents_page.dart';
import 'package:herapp/cron_page.dart';
import 'package:herapp/hermes.dart';
import 'package:herapp/main.dart';

import 'support.dart';

void main() {
  resetApp();

  testWidgets('quota page opens from the menu', (t) async {
    fakeServer((_, _, _) => null);
    addTearDown(() => fetchModels = hermesModels);
    var calls = 0;
    fetchModels = (base, {user, password}) async => (
      models: <Model>[],
      current: '',
      quotas: <Quota>[
        (
          provider: 'Claude',
          account: '',
          // a server just restarted has no usage the first time
          windows: [if (calls++ > 0) (label: 'Weekly', used: 42.0, resetsAt: DateTime.now().add(const Duration(hours: 5)))],
          limited: false,
          limitedUntil: null,
        ),
        (provider: 'Copilot', account: '', windows: <QuotaWindow>[], limited: false, limitedUntil: null),
      ],
    );
    await t.pumpWidget(const App());
    await t.tap(find.byWidgetPredicate((w) => w.runtimeType.toString() == '_MenuIcon'), warnIfMissed: false);
    await t.pumpAndSettle();
    calls = 0; // the chat asked for the models already
    await t.tap(find.text('Quotas'));
    await t.pumpAndSettle();
    expect(find.text('Weekly'), findsNothing);
    await t.pump(const Duration(seconds: 3));
    await t.pumpAndSettle();
    expect(find.text('Weekly'), findsOneWidget);
    expect(find.text('42%'), findsOneWidget);
    expect(find.textContaining('Resets in 4h'), findsOneWidget);
    expect(find.text('NO QUOTA DATA'), findsOneWidget);
    expect(find.text('Copilot'), findsOneWidget);
  });

  testWidgets('usage lists each model with its provider, calls and share', (t) async {
    fakeServer((_, _, _) => null);
    addTearDown(() => callApi = hermesApi);
    final at = DateTime.now().subtract(const Duration(hours: 2)).millisecondsSinceEpoch / 1000;
    callApi = (base, method, path, {query, body, user, password}) async => jsonEncode(switch (path) {
      '/api/analytics/usage' => {
        'daily': [
          {'day': '2026-11-01', 'input_tokens': 900, 'output_tokens': 100, 'sessions': 2},
        ],
        'by_model': [],
        'totals': {'total_input': 900, 'total_output': 100, 'total_sessions': 2},
      },
      '/api/analytics/models' => {
        'models': [
          {'model': 'gpt-4.1', 'provider': 'copilot', 'input_tokens': 100, 'output_tokens': 0, 'sessions': 1, 'api_calls': 1},
          {
            'model': 'gpt-6.1-sol',
            'provider': 'openai-codex',
            'input_tokens': 800,
            'output_tokens': 100,
            'actual_cost': 0.5,
            'sessions': 2,
            'api_calls': 12,
            'last_used_at': at,
          },
        ],
      },
      _ => {},
    });
    await t.pumpWidget(const App());
    await t.tap(find.byWidgetPredicate((w) => w.runtimeType.toString() == '_MenuIcon'), warnIfMissed: false);
    await t.pumpAndSettle();
    await t.tap(find.text('Quotas'));
    await t.pumpAndSettle();
    await t.scrollUntilVisible(find.text('gpt-4.1'), 200, scrollable: find.byType(Scrollable).last);
    expect(find.text('openai-codex · 12 calls · 2 chats · 2h 0min ago'), findsOneWidget);
    expect(find.text('900 · \$0.50'), findsOneWidget);
    final bars = t.widgetList<LinearProgressIndicator>(find.byType(LinearProgressIndicator)).map((b) => b.value).toList();
    expect(bars.last, closeTo(100 / 900, .001)); // the busiest first, the others against it
  });

  testWidgets('script jobs list under agents, pause and run', (t) async {
    t.platformDispatcher.accessibilityFeaturesTestValue = FakeAccessibilityFeatures(disableAnimations: true); // still characters
    addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
    fakeServer((_, _, _) => null);
    addTearDown(() => callApi = hermesApi);
    final posts = <String>[];
    var paused = false;
    callApi = (base, method, path, {query, body, user, password}) async {
      if (method == 'POST') {
        posts.add(path);
        paused = path.endsWith('/pause');
        return '{}';
      }
      return '[{"id":"j1","name":"Morning digest","no_agent":true,"schedule_display":"0 7 * * *","enabled":${!paused},'
          '"state":"${paused ? 'paused' : 'scheduled'}","next_run_at":"${DateTime.now().add(const Duration(hours: 2, minutes: 30)).toIso8601String()}"}]';
    };
    await t.pumpWidget(const App());
    await t.tap(find.byWidgetPredicate((w) => w.runtimeType.toString() == '_MenuIcon'), warnIfMissed: false);
    await t.pumpAndSettle();
    await t.tap(find.text('Agents'));
    await t.pumpAndSettle();
    expect(find.text('Morning digest'), findsOneWidget);
    expect(find.text('0 7 * * *'), findsOneWidget);
    expect(find.textContaining('Next run in 2h'), findsOneWidget);

    await t.tap(find.byType(CupertinoSwitch));
    await t.pumpAndSettle();
    expect(posts, ['/api/cron/jobs/j1/pause']);
    expect(t.widget<CupertinoSwitch>(find.byType(CupertinoSwitch)).value, isFalse);

    await t.tap(find.byIcon(CupertinoIcons.play_fill));
    await t.pumpAndSettle();
    expect(posts.last, '/api/cron/jobs/j1/trigger');
    expect(find.text('“Morning digest” started'), findsOneWidget);
  });

  testWidgets('a cron job is edited, created and deleted', (t) async {
    t.platformDispatcher.accessibilityFeaturesTestValue = FakeAccessibilityFeatures(disableAnimations: true); // still characters
    addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
    fakeServer((_, _, _) => null);
    addTearDown(() => callApi = hermesApi);
    final sent = <(String, String, Object?)>[];
    callApi = (base, method, path, {query, body, user, password}) async {
      if (method != 'GET') {
        sent.add((method, path, body));
        return path == '/api/cron/jobs' ? '{"id":"j2"}' : '{}';
      }
      if (path.endsWith('/runs')) {
        return '{"runs":[{"id":"cron_j1_1","source":"cron","title":"Morning digest","started_at":1793520000,"end_reason":"cron_incomplete_no_output"},'
            '{"id":"cron_output:j1:x","source":"cron_output","title":"OK","preview":"3 new mails","started_at":1793430000}]}';
      }
      if (path == '/api/sessions/cron_j1_1/messages') {
        return '{"messages":[{"role":"user","content":"Summarize the night"},{"role":"assistant","content":"Blocked by a CAPTCHA on the mail site."}]}';
      }
      if (path.endsWith('blueprints')) return '{"blueprints":[]}';
      if (path == '/api/files/read' && query?['path'] == '/home/alice/.hermes/cron/output/j1/x.md') {
        final doc = base64Encode(utf8.encode('# Cron Job: Morning digest\n\n**Job ID:** j1\n\n---\n\n3 new mails\nfrom Bob and Ann'));
        return '{"name":"x.md","mime_type":"text/markdown","data_url":"data:text/markdown;base64,$doc"}';
      }
      if (path.endsWith('delivery-targets')) return '{"targets":[{"id":"local","name":"Local"},{"id":"discord","name":"Discord"}]}';
      return '[{"id":"j1","name":"Morning digest","no_agent":true,"hermes_home":"/home/alice/.hermes","schedule":{"kind":"cron","expr":"0 7 * * *","display":"0 7 * * *"},'
          '"repeat":{"times":null,"completed":4},"prompt":"Summarize the night","deliver":"local","enabled":true,"state":"scheduled"}]';
    };
    await t.pumpWidget(const App());
    await t.tap(find.byWidgetPredicate((w) => w.runtimeType.toString() == '_MenuIcon'), warnIfMissed: false);
    await t.pumpAndSettle();
    await t.tap(find.text('Agents'));
    await t.pumpAndSettle();

    // run history: an agent run opens on its reply, a script run shows its output
    await t.tap(find.text('Morning digest'));
    await t.pumpAndSettle();
    await t.tap(find.text('Run history'));
    await t.pumpAndSettle();
    expect(find.text('OK — 3 new mails'), findsOneWidget);
    await t.tap(find.text('OK — 3 new mails'));
    await t.pumpAndSettle();
    expect(find.text('3 new mails\nfrom Bob and Ann'), findsOneWidget); // the whole output, not the list's preview
    await t.tap(find.byIcon(CupertinoIcons.chevron_back));
    await t.pumpAndSettle();
    await t.tap(find.text('Morning digest'));
    await t.pumpAndSettle();
    expect(find.text('Blocked by a CAPTCHA on the mail site.'), findsOneWidget);
    expect(find.text("Solve it on the bot's screen"), findsOneWidget);
    await t.tap(find.byIcon(CupertinoIcons.chevron_back));
    await t.pumpAndSettle();
    expect(find.textContaining('Failed'), findsOneWidget); // the agent run, not the script's
    await t.tap(find.text('Run again'));
    await t.pump(const Duration(seconds: 2));
    await t.pumpAndSettle();
    expect(sent.map((x) => (x.$1, x.$2)), [('POST', '/api/cron/jobs/j1/trigger')]);
    sent.clear();
    await t.tap(find.byIcon(CupertinoIcons.chevron_back));
    await t.pumpAndSettle();

    // edit: only the changed fields go to the server
    expect(find.text('Summarize the night'), findsOneWidget);
    expect(find.textContaining('4 runs so far'), findsOneWidget);
    await t.enterText(find.widgetWithText(TextField, '0 7 * * *'), 'every 2h');
    final form = find.descendant(of: find.byType(CronEditPage), matching: find.byType(Scrollable)).first;
    await t.scrollUntilVisible(find.byIcon(CupertinoIcons.chevron_up_chevron_down), 200, scrollable: form);
    await t.tap(find.byIcon(CupertinoIcons.chevron_up_chevron_down));
    await t.pumpAndSettle();
    await t.tap(find.text('Discord'));
    await t.pumpAndSettle();
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    expect((sent.single.$1, sent.single.$2), ('PUT', '/api/cron/jobs/j1'));
    expect(sent.single.$3, {
      'updates': {'schedule': 'every 2h', 'deliver': 'discord'},
    });
    expect(find.text('SCRIPTS'), findsOneWidget); // back on the list

    // create
    await t.tap(find.byIcon(CupertinoIcons.add));
    await t.pumpAndSettle();
    await t.tap(find.text('Start from scratch'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField).at(0), 'Weekly report');
    await t.enterText(find.byType(TextField).at(1), 'every monday 9am');
    await t.enterText(find.byType(TextField).at(3), 'Write the weekly report');
    final newForm = find.descendant(of: find.byType(CronEditPage), matching: find.byType(Scrollable)).first;
    await t.scrollUntilVisible(find.widgetWithText(TextField, 'https://'), 200, scrollable: newForm);
    await t.enterText(find.widgetWithText(TextField, 'https://'), 'https://example.test/status');
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    // the monitor isn't a create field: it follows as an update of the new job
    expect((sent.last.$1, sent.last.$2), ('PUT', '/api/cron/jobs/j2'));
    expect(sent.last.$3, {
      'updates': {'monitor_url': 'https://example.test/status'},
    });
    final (method, path, body as Map) = sent[sent.length - 2];
    expect((method, path), ('POST', '/api/cron/jobs'));
    expect(body, containsPair('schedule', 'every monday 9am'));
    expect(body, containsPair('repeat', 'forever'));
    expect(body, containsPair('no_agent', false));
    expect(body.containsKey('failure_deliver') || body.containsKey('monitor_url'), isFalse); // not create fields

    // delete
    await t.tap(find.text('Morning digest'));
    await t.pumpAndSettle();
    await t.scrollUntilVisible(find.text('Delete job'), 200, scrollable: form);
    await t.drag(form, const Offset(0, -300)); // clear of the screen's bottom edge
    await t.pumpAndSettle();
    await t.tap(find.text('Delete job'));
    await t.pumpAndSettle();
    await t.tap(find.text('Delete job').last); // the confirmation
    await t.pumpAndSettle();
    expect(sent.last, ('DELETE', '/api/cron/jobs/j1', null));
  });

  testWidgets('agents page shows the kanban workers', (t) async {
    t.platformDispatcher.accessibilityFeaturesTestValue = FakeAccessibilityFeatures(disableAnimations: true); // still characters
    addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
    fakeServer((_, _, _) => null);
    addTearDown(() => callApi = hermesApi);
    final started = DateTime.now().subtract(const Duration(minutes: 25)).millisecondsSinceEpoch / 1000;
    var later = false; // a worker another board starts once the page is open
    callApi = (base, method, path, {query, body, user, password}) async => switch ((path, query?['board'])) {
      // each project's board runs its own workers, not only the active one
      ('/api/plugins/kanban/boards', _) =>
        '{"boards":[{"slug":"default","total":1},{"slug":"site","total":1},{"slug":"empty","total":0},{"slug":"app","total":${later ? 1 : 0}}]}',
      ('/api/plugins/kanban/board', 'default') =>
        '{"columns":[{"name":"ready","tasks":[{"id":"t1","title":"Fix the map","status":"ready","consecutive_failures":1,'
            '"last_failure_error":"worker exited 1"}]},{"name":"done","tasks":[]}]}',
      ('/api/plugins/kanban/board', 'site') =>
        '{"columns":[{"name":"running","tasks":[{"id":"t2","title":"Build the bridge",'
            '"status":"running","current_run_started_at":$started,"last_heartbeat_at":$started}]}]}',
      ('/api/plugins/kanban/board', 'app') =>
        '{"columns":[{"name":"running","tasks":[{"id":"t3","title":"Ship the app","status":"running"}]}]}',
      _ => '[]',
    };
    await t.pumpWidget(const App());
    await t.tap(find.byWidgetPredicate((w) => w.runtimeType.toString() == '_MenuIcon'), warnIfMissed: false);
    await t.pumpAndSettle();
    await t.tap(find.text('Agents'));
    await t.pumpAndSettle();
    expect(find.text('WORKERS'), findsOneWidget);
    expect(find.text('Build the bridge'), findsOneWidget);
    expect(find.text('Working for 25 min'), findsOneWidget);
    expect(find.text('No sign of life for 25 min'), findsOneWidget);
    expect(find.text('Failed: worker exited 1'), findsOneWidget);
    expect(find.text('1 ready'), findsOneWidget); // empty columns aren't counted

    later = true;
    await t.pump(const Duration(seconds: 10));
    await t.pump();
    expect(find.text('Ship the app'), findsOneWidget);
  });

  testWidgets('agents page shows the subagents the chats started, running or just ended', (t) async {
    t.platformDispatcher.accessibilityFeaturesTestValue = FakeAccessibilityFeatures(disableAnimations: true); // still characters
    addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
    late void Function(String, Map) push;
    fakeServer((method, params, emit) {
      if (method == 'session.list') push = emit;
      return null;
    });
    addTearDown(() => callApi = hermesApi);
    callApi = (base, method, path, {query, body, user, password}) async => '[]';
    await t.pumpWidget(const App());
    await t.pump(const Duration(milliseconds: 100));
    push('subagent.start', {'subagent_id': 'a1', 'goal': 'Read the docs', 'task_count': 2, 'task_index': 0});
    push('subagent.tool', {'subagent_id': 'a1', 'goal': 'Read the docs', 'task_count': 2, 'task_index': 0, 'tool_name': 'web_search'});
    push('subagent.start', {'subagent_id': 'a2', 'goal': 'Write the tests', 'task_count': 2, 'task_index': 1});
    push('subagent.complete', {'subagent_id': 'a2', 'goal': 'Write the tests', 'task_count': 2, 'task_index': 1, 'status': 'completed'});
    await t.pump(const Duration(milliseconds: 100));

    await t.tap(find.byWidgetPredicate((w) => w.runtimeType.toString() == '_MenuIcon'), warnIfMissed: false);
    await t.pumpAndSettle();
    await t.tap(find.text('Agents'));
    await t.pumpAndSettle();
    expect(find.text('SUBAGENTS'), findsOneWidget);
    expect(find.text('Read the docs'), findsOneWidget);
    expect(find.textContaining('web_search'), findsOneWidget);
    expect(find.text('Write the tests'), findsOneWidget);
    expect(find.text('Finished'), findsOneWidget);
  });

  testWidgets('a running subagent shows what it does, takes a direction and stops', (t) async {
    t.platformDispatcher.accessibilityFeaturesTestValue = FakeAccessibilityFeatures(disableAnimations: true); // still characters
    addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
    late void Function(String, Map) push;
    final calls = fakeServer((method, params, emit) {
      if (method == 'session.list') push = emit;
      return switch (method) {
        'subagent.tail' => {'available': true, 'text': 'Reading README.md'},
        'subagent.steer' => {'status': 'queued'},
        'subagent.interrupt' => {'found': true},
        _ => null,
      };
    });
    addTearDown(() => callApi = hermesApi);
    callApi = (base, method, path, {query, body, user, password}) async => '[]';
    await t.pumpWidget(const App());
    await t.pump(const Duration(milliseconds: 100));
    push('subagent.start', {'subagent_id': 'a1', 'goal': 'Read the docs', 'task_count': 1, 'task_index': 0});
    await t.pump(const Duration(milliseconds: 100));
    await t.tap(find.byWidgetPredicate((w) => w.runtimeType.toString() == '_MenuIcon'), warnIfMissed: false);
    await t.pumpAndSettle();
    await t.tap(find.text('Agents'));
    await t.pumpAndSettle();
    await t.tap(find.text('Read the docs'));
    await t.pumpAndSettle();
    expect(find.text('Reading README.md'), findsOneWidget);

    await t.enterText(find.byType(CupertinoTextField), 'Skip the changelog');
    await t.tap(find.byTooltip('Send'));
    await t.pumpAndSettle();
    expect(calls.where((c) => c.$1 == 'subagent.steer').single.$2, {'session_id': 'rt', 'subagent_id': 'a1', 'text': 'Skip the changelog'});
    expect(find.textContaining('Sent'), findsOneWidget);

    await t.tap(find.text('Stop'));
    await t.pump();
    expect(calls.where((c) => c.$1 == 'subagent.interrupt').single.$2, {'session_id': 'rt', 'subagent_id': 'a1'});
    push('subagent.complete', {'subagent_id': 'a1', 'goal': 'Read the docs', 'task_count': 1, 'task_index': 0, 'status': 'interrupted'});
    await t.pump(const Duration(milliseconds: 100));
    await t.pump(const Duration(seconds: 5)); // the snack bar goes
    expect(find.text('Stop'), findsNothing); // ended: nothing left to steer
    expect(find.byType(CupertinoTextField), findsNothing);
  });

  testWidgets('a kanban card in review is answered and approved', (t) async {
    fakeServer((_, _, _) => null);
    addTearDown(() => callApi = hermesApi);
    final sent = <(String, String, Object?)>[];
    callApi = (base, method, path, {query, body, user, password}) async {
      if (method != 'GET') {
        sent.add((method, path, body));
        return '{}';
      }
      if (path == '/api/plugins/kanban/board') {
        return '{"columns":[{"name":"review","tasks":[{"id":"t1","title":"Check the bridge","status":"review","comment_count":1}]},'
            '{"name":"todo","tasks":[{"id":"t2","title":"Plain","status":"todo"}]}]}';
      }
      if (path == '/api/plugins/kanban/tasks/t1') {
        return '{"task":{"id":"t1","title":"Check the bridge","status":"review","body":"Look at the arch"},'
            '"comments":[{"author":"planner","body":"Ready for you","created_at":1793350000}],"events":[]}';
      }
      return '[]';
    };
    await t.pumpWidget(const App());
    await t.tap(find.byWidgetPredicate((w) => w.runtimeType.toString() == '_MenuIcon'), warnIfMissed: false);
    await t.pumpAndSettle();
    await t.tap(find.text('Kanban'));
    await t.pumpAndSettle();
    expect(find.text('YOUR TURN'), findsOneWidget);
    expect(find.text('Plain'), findsNothing);
    await t.tap(find.text('Check the bridge'));
    await t.pumpAndSettle();
    expect(find.text('Look at the arch'), findsOneWidget);
    expect(find.text('Ready for you'), findsOneWidget);
    await t.enterText(find.byType(TextField), 'Looks good');
    await t.tap(find.byIcon(CupertinoIcons.checkmark_seal));
    await t.pumpAndSettle();
    await t.tap(find.text('Approve'));
    await t.pumpAndSettle();
    expect(
      [for (final (m, p, b) in sent) (m, p, jsonEncode(b))],
      [
        ('POST', '/api/plugins/kanban/tasks/t1/comments', '{"body":"Looks good"}'),
        ('PATCH', '/api/plugins/kanban/tasks/t1', '{"status":"done"}'),
      ],
    );
    expect(find.text('YOUR TURN'), findsOneWidget); // back on the refreshed list
  });

  testWidgets('agents show with a character, go quiet and team up', (t) async {
    t.platformDispatcher.accessibilityFeaturesTestValue = FakeAccessibilityFeatures(disableAnimations: true); // still characters
    addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
    fakeServer((_, _, _) => null);
    addTearDown(() => callApi = hermesApi);
    final sent = <(String, String, Object?)>[];
    var prompt = 'Summarize the night';
    callApi = (base, method, path, {query, body, user, password}) async {
      if (method != 'GET') {
        sent.add((method, path, body));
        if (body case {'updates': {'prompt': final String p}}) prompt = p;
        return '{}';
      }
      if (path.endsWith('/runs')) return '{"runs":[{"id":"cron_a1_1","source":"cron","title":"Night","preview":"Summarize the night"}]}';
      if (path.startsWith('/api/sessions/')) {
        return '{"messages":[{"role":"user","content":"Summarize the night"},{"role":"assistant","content":"All quiet."}]}';
      }
      return jsonEncode([
        {'id': 'a1', 'name': 'Night owl', 'prompt': prompt, 'enabled': true, 'state': 'scheduled'},
        {'id': 'a2', 'name': 'Mail watch', 'prompt': 'Check mail', 'enabled': false, 'state': 'paused'},
        {'id': 's1', 'name': 'Backup', 'no_agent': true, 'script': 'backup.sh'}, // a script, not an agent
      ]);
    };
    await t.pumpWidget(const App());
    await t.tap(find.byWidgetPredicate((w) => w.runtimeType.toString() == '_MenuIcon'), warnIfMissed: false);
    await t.pumpAndSettle();
    await t.tap(find.text('Agents'));
    await t.pumpAndSettle();
    expect(find.text('Night owl'), findsOneWidget);
    expect(find.text('Asleep'), findsOneWidget); // the paused one
    expect(find.text('Backup'), findsOneWidget); // a script, listed apart
    expect(find.byType(Critter), findsNWidgets(2));

    await t.tap(find.text('Night owl'));
    await t.pumpAndSettle();
    expect(find.text('All quiet.'), findsOneWidget); // its last reply
    final page = find.descendant(of: find.byType(AgentPage), matching: find.byType(Scrollable)).first;
    final quiet = find.descendant(
      of: find.ancestor(of: find.text('Speaks only when it matters'), matching: find.byType(Row)).first,
      matching: find.byType(CupertinoSwitch),
    );
    await t.scrollUntilVisible(find.text('Speaks only when it matters'), 200, scrollable: page);
    await t.drag(page, const Offset(0, -200)); // clear of the screen edge
    await t.pumpAndSettle();
    await t.tap(quiet);
    await t.pumpAndSettle();
    expect(sent.last.$3, {
      'updates': {'prompt': 'Summarize the night$quietRule'},
    });
    expect(t.widget<CupertinoSwitch>(quiet).value, isTrue);

    await t.scrollUntilVisible(find.text('No one'), 200, scrollable: page);
    await t.tap(find.text('No one'));
    await t.pumpAndSettle();
    await t.tap(find.text('Mail watch'));
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    expect(sent.last.$3, {
      'updates': {
        'context_from': ['a2'],
      },
    });

    // its own model and effort
    addTearDown(() => fetchModels = hermesModels);
    fetchModels = (base, {user, password}) async => (
      models: <Model>[(provider: 'Anthropic', name: 'claude-sonnet-5-5', id: 'anthropic/claude-sonnet-5-5', reasoning: true)],
      current: '',
      quotas: <Quota>[],
    );
    await t.scrollUntilVisible(find.text('Model'), -200, scrollable: page);
    await t.drag(page, const Offset(0, 150)); // clear of the header
    await t.pumpAndSettle();
    stillStripes(t);
    await t.tap(find.text('Model'));
    await t.pumpAndSettle();
    await tapEffort(t, 'high');
    await t.pumpAndSettle();
    expect(sent.last.$3, {
      'updates': {'reasoning_effort': 'high'},
    });
    await t.tap(find.text('claude-sonnet-5-5'));
    await t.pumpAndSettle();
    expect(sent.last.$3, {
      'updates': {'provider': 'anthropic', 'model': 'claude-sonnet-5-5'},
    });
  });

  testWidgets('vault lists accounts, adds a login and removes one', (t) async {
    final items = [
      {
        'id': 'v1',
        'kind': 'login',
        'label': 'Forge',
        'origin': 'https://forge.test',
        'identifier': 'alice',
        'has_otp': true,
        'backend': 'local',
      },
    ];
    final calls = fakeServer((method, params, emit) {
      switch (method) {
        case 'vault.list':
          return {'items': items};
        case 'vault.add':
          items.add({'id': 'v2', 'kind': 'login', 'label': params['label'], 'origin': params['origin'], 'backend': 'local'});
          return {'id': 'v2'};
        case 'vault.remove':
          items.removeWhere((i) => i['id'] == params['id']);
          return {'removed': true};
      }
      return null;
    });
    await t.pumpWidget(const App());
    await t.tap(find.byWidgetPredicate((w) => w.runtimeType.toString() == '_MenuIcon'), warnIfMissed: false);
    await t.pumpAndSettle();
    await t.tap(find.text('Vault'));
    await t.pumpAndSettle();
    expect(find.text('Forge'), findsOneWidget);
    expect(find.text('alice · forge.test'), findsOneWidget);
    expect(find.text('2FA'), findsOneWidget);

    await t.tap(find.byIcon(CupertinoIcons.add));
    await t.pumpAndSettle();
    final fields = find.byType(TextField);
    await t.enterText(fields.at(0), 'Wiki');
    await t.enterText(fields.at(1), 'wiki.test');
    await t.enterText(fields.at(2), 'alice@wiki.test');
    await t.enterText(fields.at(3), 'test-password');
    await t.pump();
    expect(t.widget<TextField>(fields.at(3)).obscureText, isTrue);
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    final add = calls.lastWhere((c) => c.$1 == 'vault.add').$2;
    expect((add['kind'], add['label'], add['origin']), ('login', 'Wiki', 'https://wiki.test')); // a bare site gets https://
    expect(add['secret'], {'identifier_type': 'email', 'identifier': 'alice@wiki.test', 'password': 'test-password'});
    expect(find.text('Wiki'), findsOneWidget); // back on the refreshed list

    await t.drag(find.text('Forge'), const Offset(-600, 0));
    await t.pumpAndSettle();
    await t.tap(find.text('Remove the account'));
    await t.pumpAndSettle();
    expect((calls.last.$1, calls.last.$2['id']), ('vault.remove', 'v1'));
    expect(find.text('Forge'), findsNothing);
  });

  testWidgets('skills and MCP servers switch on and off, a server is tested', (t) async {
    fakeServer((_, _, _) => null);
    addTearDown(() => callApi = hermesApi);
    final sent = <(String, String, Object?)>[];
    callApi = (base, method, path, {query, body, user, password}) async {
      if (method != 'GET') sent.add((method, path, body));
      return jsonEncode(switch (path) {
        '/api/mcp/servers' => {
          'servers': [
            {'name': 'github', 'transport': 'http', 'url': 'https://mcp.github.test', 'enabled': true, 'source': 'config'},
          ],
        },
        '/api/skills' => [
          {'name': 'bookstack', 'description': 'Homelab wiki', 'category': 'docs', 'enabled': true},
          {'name': 'github-pr', 'description': 'Open pull requests', 'category': 'dev', 'enabled': false},
        ],
        '/api/mcp/servers/github/test' => {
          'ok': true,
          'tools': [
            {'name': 'a'},
            {'name': 'b'},
          ],
        },
        _ => {'ok': true},
      });
    };
    await t.pumpWidget(const App());
    await t.tap(find.byWidgetPredicate((w) => w.runtimeType.toString() == '_MenuIcon'), warnIfMissed: false);
    await t.pumpAndSettle();
    await t.tap(find.text('Skills & MCP'));
    await t.pumpAndSettle();
    expect(find.text('MCP SERVERS'), findsOneWidget);
    expect(find.text('https://mcp.github.test'), findsOneWidget);
    expect(find.text('DEV'), findsOneWidget);

    await t.tap(find.byIcon(CupertinoIcons.bolt_horizontal));
    await t.pumpAndSettle();
    expect(find.text('Connected · 2 tools'), findsOneWidget);

    await t.tap(find.byType(CupertinoSwitch).first); // the server off
    await t.pumpAndSettle();
    await t.tap(find.byType(CupertinoSwitch).at(1)); // github-pr on (dev, the first category)
    await t.pumpAndSettle();
    expect(
      [for (final (m, p, b) in sent) '$m $p ${jsonEncode(b)}'],
      [
        'POST /api/mcp/servers/github/test null',
        'PUT /api/mcp/servers/github/enabled {"enabled":false}',
        'PUT /api/skills/toggle {"name":"github-pr","enabled":true}',
      ],
    );
    expect(t.widget<CupertinoSwitch>(find.byType(CupertinoSwitch).at(1)).value, isTrue);

    await t.enterText(find.byType(CupertinoSearchTextField), 'wiki');
    await t.pumpAndSettle();
    expect(find.text('bookstack'), findsOneWidget);
    expect(find.text('github-pr'), findsNothing);
  });

  testWidgets('the system page shows the server, updates it and restarts its gateway', (t) async {
    fakeServer((_, _, _) => null);
    addTearDown(() => callApi = hermesApi);
    final posts = <String>[];
    var updated = false, polls = 0;
    callApi = (base, method, path, {query, body, user, password}) async {
      if (method == 'POST') posts.add(path);
      return jsonEncode(switch (path) {
        '/api/status' => {
          'version': '0.22.3',
          'release_date': '2026-10-20',
          'gateway_running': true,
          'gateway_state': 'running',
          'overall': 'ok',
          'active_sessions': 3,
          'components': {
            'platforms': {'configured': 2, 'connected': 1},
          },
        },
        '/api/system/stats' => {
          'cpu_percent': 12.4,
          'load_avg': [0.5, 0.4, 0.3],
          'cpu_count': 8,
          'memory': {'total': 16e9, 'used': 6.2e9, 'available': 9.8e9, 'percent': 38.8},
          'disk': {'total': 500e9, 'used': 460e9, 'free': 40e9, 'percent': 92.0},
          'uptime_seconds': 3 * 86400 + 4 * 3600 + 120,
        },
        '/api/hermes/update/check' when updated => {'update_available': false, 'behind': 0, 'can_apply': true},
        '/api/hermes/update/check' => {
          'update_available': true,
          'behind': 12,
          'can_apply': true,
          'commits': [
            {'sha': 'abc1234', 'summary': 'Faster replies'},
          ],
        },
        '/api/hermes/update' => {'ok': true, 'name': 'hermes-update'},
        '/api/actions/hermes-update/status' => ++polls < 2 ? {'running': true} : {'running': false, 'exit_code': 0},
        _ => {'ok': true},
      });
    };
    await t.pumpWidget(const App());
    await t.tap(find.byWidgetPredicate((w) => w.runtimeType.toString() == '_MenuIcon'), warnIfMissed: false);
    await t.pumpAndSettle();
    await t.tap(find.text('System'));
    await t.pumpAndSettle();
    expect(find.text('0.22.3 · Oct 20, 2026'), findsOneWidget);
    expect(find.text('Running'), findsOneWidget);
    expect(find.text('All good'), findsOneWidget);
    expect(find.text('1 of 2 connected'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('12 % · load 0.5 on 8 cores'), findsOneWidget);
    expect(find.text('6.2 of 16 GB · 39 %'), findsOneWidget);
    expect(find.text('460 of 500 GB · 92 %'), findsOneWidget);
    expect(find.text('3d 4h'), findsOneWidget);
    expect(find.text('12 changes'), findsOneWidget);
    expect(find.text('Faster replies'), findsOneWidget);

    await t.ensureVisible(find.text('Update now'));
    await t.pumpAndSettle();
    await t.tap(find.text('Update now'));
    await t.pumpAndSettle();
    await t.tap(find.text('Update now').last); // confirmed
    updated = true;
    for (var i = 0; i < 4; i++) {
      await t.pump(const Duration(seconds: 2));
    }
    await t.pumpAndSettle();
    expect(posts, ['/api/hermes/update']);
    expect(find.text('Update done.'), findsOneWidget);
    expect(find.text('Hermes is up to date.'), findsOneWidget);

    await t.ensureVisible(find.text('Restart the gateway'));
    await t.pumpAndSettle();
    await t.tap(find.text('Restart the gateway'));
    await t.pumpAndSettle();
    await t.tap(find.text('Restart the gateway').last);
    await t.pumpAndSettle();
    expect(posts.last, '/api/gateway/restart');
    expect(find.text('The gateway is restarting.'), findsOneWidget);
  });
}
