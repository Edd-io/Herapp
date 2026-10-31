import 'dart:async';
import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herapp/cron_page.dart';
import 'package:herapp/hermes.dart';
import 'package:herapp/main.dart';
import 'package:herapp/settings.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What a [fakeServer] call receives: the method, its params, and [emit] to push an event later.
/// An answer to a server request arrives as method 'reply' with the whole frame; emitting
/// `'request:method'` sends that server request (id 'r1') instead of an event.
typedef Handler = Object? Function(String method, Map params, void Function(String type, Map payload) emit);

/// Points the app at a fake Hermes gateway answering with [handle]; returns the calls it got.
List<(String, Map)> fakeServer(Handler handle) {
  final calls = <(String, Map)>[];
  settings.url = 'https://hermes.test';
  connectGateway = (base, {user, password}) async {
    final frames = StreamController<String>();
    return Gateway(frames.stream, (out) {
      final j = jsonDecode(out) as Map;
      final method = j['method'] as String? ?? 'reply';
      calls.add((method, j['params'] as Map? ?? j));
      void emit(String type, Map payload) => Timer(
        const Duration(milliseconds: 50),
        () => frames.add(
          jsonEncode(
            type.startsWith('request:')
                ? {
                    'jsonrpc': '2.0',
                    'id': 'r1',
                    'method': type.substring(8),
                    'params': {...payload, 'session_id': 'rt'},
                  }
                : {
                    'jsonrpc': '2.0',
                    'method': 'event',
                    'params': {'type': type, 'session_id': 'rt', 'payload': payload},
                  },
          ),
        ),
      );
      final result = handle(method, j['params'] as Map? ?? j, emit) ?? {};
      if (method == 'reply') return;
      scheduleMicrotask(() => frames.add(jsonEncode({'jsonrpc': '2.0', 'id': j['id'], 'result': result})));
    }, frames.close);
  };
  return calls;
}

/// A server with no history that streams "Hello there" to every prompt.
Object? replies(String method, Map params, void Function(String, Map) emit) {
  switch (method) {
    case 'session.create':
      return {'session_id': 'rt', 'stored_session_id': 's1'};
    case 'prompt.submit':
      emit('message.delta', {'text': 'Hello '});
      emit('message.delta', {'text': 'there'});
      emit('message.complete', {
        'text': 'Hello there',
        'status': 'complete',
        'usage': {'context_percent': 42},
      });
      return {'status': 'streaming'};
  }
  return null;
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await settings.load();
    dropGateway();
    addTearDown(() => connectGateway = hermesGateway);
  });

  testWidgets('send then streamed reply', (t) async {
    final calls = fakeServer(replies);
    await t.pumpWidget(const App());
    expect(find.text('How can I help?'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing); // no context ring before the first message

    await t.enterText(find.byType(EditableText).last, 'Salut');
    await t.pumpAndSettle(); // let the send icon animation finish
    await t.tap(find.byIcon(CupertinoIcons.arrow_up));
    await t.pump();
    expect(find.text('Salut'), findsWidgets);

    await t.pump(const Duration(seconds: 10));
    await t.pump(const Duration(seconds: 1));
    expect(find.textContaining('Hello there'), findsOneWidget);
    expect(calls.where((c) => c.$1 == 'prompt.submit').single.$2, {'session_id': 'rt', 'text': 'Salut'});
    // the ring shows the server's context usage
    expect(t.widget<CircularProgressIndicator>(find.byType(CircularProgressIndicator)).value, closeTo(.42, .001));

    await t.tap(find.byIcon(CupertinoIcons.arrow_2_circlepath));
    await t.pump(const Duration(seconds: 10));
    expect(calls.where((c) => c.$1 == 'prompt.submit').last.$2, containsPair('truncate_before_user_ordinal', 0));
    expect(find.textContaining('Hello there'), findsOneWidget); // replaced, not appended
    expect(calls.where((c) => c.$1 == 'session.create'), hasLength(1));
  });

  testWidgets('tool calls show and a command waits for approval', (t) async {
    final calls = fakeServer((method, params, emit) {
      switch (method) {
        case 'session.create':
          return {'session_id': 'rt', 'stored_session_id': 's1'};
        case 'prompt.submit':
          emit('tool.start', {'tool_id': 't1', 'name': 'terminal', 'context': 'rm -rf build\nmore'});
          emit('request:approval', {
            'request_id': 'a1',
            'command': 'rm -rf build',
            'choices': ['once', 'session', 'always', 'deny'],
            'allow_permanent': false,
          });
          emit('request:clarify', {'questions': []});
        case 'reply' when '${params['result']}' == '{choice: once}':
          emit('tool.complete', {'tool_id': 't1', 'name': 'terminal'});
          emit('message.complete', {'text': 'Cleaned', 'status': 'complete'});
      }
      return null;
    });
    await t.pumpWidget(const App());
    await t.enterText(find.byType(EditableText).last, 'Clean up');
    await t.pumpAndSettle();
    await t.tap(find.byIcon(CupertinoIcons.arrow_up));
    await t.pump(const Duration(seconds: 1));

    expect(find.textContaining('terminal  rm -rf build', findRichText: true), findsOneWidget); // first line only
    expect(find.text('Hermes wants to run a command'), findsOneWidget);
    expect(find.text('Always'), findsNothing); // the server allows no permanent approval
    expect(calls.where((c) => c.$1 == 'reply').single.$2, containsPair('error', isA<Map>())); // clarify refused

    await t.tap(find.text('Allow once'));
    await t.pump(const Duration(seconds: 1));
    expect(calls.where((c) => c.$1 == 'reply').last.$2, containsPair('result', {'choice': 'once'}));
    expect(find.text('Hermes wants to run a command'), findsNothing);
    expect(find.textContaining('Cleaned'), findsOneWidget);
    expect(find.text('1 action'), findsOneWidget); // folded once the reply is done
    await t.pump(const Duration(seconds: 10));
  });

  testWidgets('history lists and reopens server sessions', (t) async {
    final rows = [
      {'id': 's9', 'title': 'Trip to Lyon', 'preview': ''},
    ];
    fakeServer(
      (method, params, emit) => switch (method) {
        'session.list' => {'sessions': rows},
        'session.resume' => {
          'session_id': 'rt',
          'info': {'provider': 'anthropic', 'model': 'claude-sonnet-5-5'},
        },
        'session.context_breakdown' => {'context_percent': 7, 'context_max': 200000},
        _ => null,
      },
    );
    addTearDown(() => callApi = hermesApi);
    callApi = (base, method, path, {query, body, user, password}) async {
      expect(path, '/api/sessions/s9/messages');
      return jsonEncode({
        'messages': [
          {'role': 'user', 'content': 'Plan a trip'},
          {'role': 'tool', 'content': '…', 'tool_name': 'web_search'},
          {'role': 'assistant', 'content': 'Day 1: Vieux Lyon'},
        ],
      });
    };
    await t.pumpWidget(const App());
    await t.tap(find.byWidgetPredicate((w) => w.runtimeType.toString() == '_MenuIcon'), warnIfMissed: false);
    await t.pumpAndSettle();
    await t.tap(find.text('Trip to Lyon'));
    await t.pumpAndSettle();
    expect(find.text('Plan a trip'), findsOneWidget);
    expect(find.text('Day 1: Vieux Lyon'), findsOneWidget);
    expect(find.text('claude-sonnet-5-5'), findsOneWidget); // the session's own model
    expect(find.text('1 action'), findsOneWidget); // the tool it ran
    expect(t.widget<CircularProgressIndicator>(find.byType(CircularProgressIndicator)).value, closeTo(.07, .001));

    // a session gone from the server's list (deleted, or filtered out) leaves the sidebar
    rows.clear();
    await t.tap(find.byWidgetPredicate((w) => w.runtimeType.toString() == '_MenuIcon'), warnIfMissed: false);
    await t.pumpAndSettle();
    await t.tap(find.text('New chat'));
    await t.pumpAndSettle();
    await t.tap(find.byWidgetPredicate((w) => w.runtimeType.toString() == '_MenuIcon'), warnIfMissed: false);
    await t.pumpAndSettle();
    expect(find.text('Trip to Lyon'), findsNothing);
  });

  testWidgets('a chat is deleted by swiping it left, after confirming', (t) async {
    final rows = [
      {'id': 's9', 'title': 'Trip to Lyon'},
    ];
    final calls = fakeServer((method, params, emit) {
      if (method == 'session.delete') rows.clear();
      return method == 'session.list' ? {'sessions': rows} : null;
    });
    await t.pumpWidget(const App());
    await t.tap(find.byWidgetPredicate((w) => w.runtimeType.toString() == '_MenuIcon'), warnIfMissed: false);
    await t.pumpAndSettle();

    await t.drag(find.text('Trip to Lyon'), const Offset(-300, 0));
    await t.pumpAndSettle();
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(find.text('Trip to Lyon'), findsOneWidget); // kept

    await t.drag(find.text('Trip to Lyon'), const Offset(-300, 0));
    await t.pumpAndSettle();
    await t.tap(find.text('Delete chat'));
    await t.pumpAndSettle();
    expect(calls.where((c) => c.$1 == 'session.delete').single.$2, {'session_id': 's9'});
    expect(find.text('Trip to Lyon'), findsNothing);
  });

  testWidgets('server models can be picked while the chat is empty', (t) async {
    final calls = fakeServer(replies);
    addTearDown(() => fetchModels = hermesModels);
    fetchModels = (base, {user, password}) async => (
      models: <Model>[
        (provider: 'Anthropic', name: 'claude-sonnet-5-5', id: 'anthropic/claude-sonnet-5-5'),
        (provider: 'OpenRouter', name: 'openai/gpt-5', id: 'openrouter/openai/gpt-5'),
      ],
      current: 'anthropic/claude-sonnet-5-5',
      quotas: <Quota>[],
    );
    await t.pumpWidget(const App());
    await t.pumpAndSettle();
    expect(settings.model, 'anthropic/claude-sonnet-5-5'); // server default

    await t.tap(find.text('Anthropic')); // pill under the headline
    await t.pumpAndSettle();
    await t.tap(find.text('openai/gpt-5').last);
    await t.pumpAndSettle();
    expect(settings.model, 'openrouter/openai/gpt-5');
    expect(find.text('OpenRouter'), findsOneWidget);

    await t.enterText(find.byType(EditableText).last, 'Salut');
    await t.pumpAndSettle();
    await t.tap(find.byIcon(CupertinoIcons.arrow_up));
    await t.pump(const Duration(seconds: 10));
    expect(calls.firstWhere((c) => c.$1 == 'session.create').$2, {'provider': 'openrouter', 'model': 'openai/gpt-5'});
    expect(find.text('openai/gpt-5'), findsOneWidget); // title shown, pill gone
  });

  testWidgets('quota page opens from the menu', (t) async {
    fakeServer((_, _, _) => null);
    addTearDown(() => fetchModels = hermesModels);
    fetchModels = (base, {user, password}) async => (
      models: <Model>[],
      current: '',
      quotas: <Quota>[
        (
          provider: 'Claude',
          account: '',
          windows: [(label: 'Weekly', used: 42.0, resetsAt: DateTime.now().add(const Duration(hours: 5)))],
          limited: false,
          limitedUntil: null,
        ),
        (provider: 'Copilot', account: '', windows: <QuotaWindow>[], limited: false, limitedUntil: null),
      ],
    );
    await t.pumpWidget(const App());
    await t.tap(find.byWidgetPredicate((w) => w.runtimeType.toString() == '_MenuIcon'), warnIfMissed: false);
    await t.pumpAndSettle();
    await t.tap(find.text('Quotas'));
    await t.pumpAndSettle();
    expect(find.text('Weekly'), findsOneWidget);
    expect(find.text('42%'), findsOneWidget);
    expect(find.textContaining('Resets in 4h'), findsOneWidget);
    expect(find.text('NO QUOTA DATA'), findsOneWidget);
    expect(find.text('Copilot'), findsOneWidget);
  });

  testWidgets('cron page lists jobs, pauses and runs them', (t) async {
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
      return '[{"id":"j1","name":"Morning digest","schedule_display":"0 7 * * *","enabled":${!paused},'
          '"state":"${paused ? 'paused' : 'scheduled'}","next_run_at":"${DateTime.now().add(const Duration(hours: 2, minutes: 30)).toIso8601String()}"}]';
    };
    await t.pumpWidget(const App());
    await t.tap(find.byWidgetPredicate((w) => w.runtimeType.toString() == '_MenuIcon'), warnIfMissed: false);
    await t.pumpAndSettle();
    await t.tap(find.text('Scheduled jobs'));
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
    fakeServer((_, _, _) => null);
    addTearDown(() => callApi = hermesApi);
    final sent = <(String, String, Object?)>[];
    callApi = (base, method, path, {query, body, user, password}) async {
      if (method != 'GET') {
        sent.add((method, path, body));
        return path == '/api/cron/jobs' ? '{"id":"j2"}' : '{}';
      }
      if (path.endsWith('/runs')) {
        return '{"runs":[{"id":"cron_j1_1","source":"cron","title":"Morning digest","started_at":1793520000},'
            '{"id":"cron_output:j1:x","source":"cron_output","title":"OK","preview":"3 new mails","started_at":1793430000}]}';
      }
      if (path == '/api/sessions/cron_j1_1/messages') {
        return '{"messages":[{"role":"user","content":"Summarize the night"},{"role":"assistant","content":"All quiet overnight."}]}';
      }
      if (path.endsWith('delivery-targets')) return '{"targets":[{"id":"local","name":"Local"},{"id":"discord","name":"Discord"}]}';
      return '[{"id":"j1","name":"Morning digest","schedule":{"kind":"cron","expr":"0 7 * * *","display":"0 7 * * *"},'
          '"repeat":{"times":null,"completed":4},"prompt":"Summarize the night","deliver":"local","enabled":true,"state":"scheduled"}]';
    };
    await t.pumpWidget(const App());
    await t.tap(find.byWidgetPredicate((w) => w.runtimeType.toString() == '_MenuIcon'), warnIfMissed: false);
    await t.pumpAndSettle();
    await t.tap(find.text('Scheduled jobs'));
    await t.pumpAndSettle();

    // run history: an agent run opens on its reply, a script run shows its output
    await t.tap(find.text('Morning digest'));
    await t.pumpAndSettle();
    await t.tap(find.text('Run history'));
    await t.pumpAndSettle();
    expect(find.text('OK — 3 new mails'), findsOneWidget);
    await t.tap(find.text('Morning digest'));
    await t.pumpAndSettle();
    expect(find.text('All quiet overnight.'), findsOneWidget);
    await t.tap(find.byIcon(CupertinoIcons.chevron_back));
    await t.pumpAndSettle();
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
    expect(find.text('Scheduled jobs'), findsOneWidget); // back on the list

    // create
    await t.tap(find.byIcon(CupertinoIcons.add));
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
    await t.tap(find.text('Delete job'));
    await t.pumpAndSettle();
    await t.tap(find.text('Delete job').last); // the confirmation
    await t.pumpAndSettle();
    expect(sent.last, ('DELETE', '/api/cron/jobs/j1', null));
  });

  testWidgets('picker explains a missing server', (t) async {
    await t.pumpWidget(const App());
    await t.tap(find.text('Model'));
    await t.pumpAndSettle();
    expect(find.textContaining('Set your Hermes server address'), findsOneWidget);
  });

  testWidgets('settings change the theme and persist', (t) async {
    await t.pumpWidget(const App());
    await t.tapAt(const Offset(30, 50)); // menu icon
    await t.pumpAndSettle();
    await t.tap(find.text('Settings'));
    await t.pumpAndSettle();

    await t.tap(find.text('Dark'));
    await t.pumpAndSettle();
    expect(settings.theme, ThemeMode.dark);
    expect(t.widget<MaterialApp>(find.byType(MaterialApp)).themeMode, ThemeMode.dark);

    await settings.load();
    expect(settings.theme, ThemeMode.dark);
  });

  testWidgets('UI follows the French locale', (t) async {
    t.platformDispatcher.localesTestValue = const [Locale('fr')];
    addTearDown(t.platformDispatcher.clearLocalesTestValue);
    await t.pumpWidget(const App());
    expect(find.text('Comment puis-je aider ?'), findsOneWidget);
    expect(find.text('Poser une question'), findsOneWidget);
  });

  testWidgets('server test rejects invalid addresses and non-Hermes servers', (t) async {
    settings.url = 'not a url';
    await t.pumpWidget(const App());
    await t.tapAt(const Offset(30, 50)); // menu icon
    await t.pumpAndSettle();
    await t.tap(find.text('Settings'));
    await t.pumpAndSettle();

    await t.tap(find.text('Test connection'));
    await t.pump();
    expect(find.text('Invalid address'), findsOneWidget);

    settings.url = 'https://example.com'; // flutter_test's fake HttpClient answers 400
    await t.tap(find.text('Test connection'));
    await t.pumpAndSettle();
    expect(find.text('Reachable, but not a Hermes server (HTTP 400)'), findsOneWidget);
  });
}
