import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herapp/agents_page.dart';
import 'package:herapp/cron_page.dart';
import 'package:herapp/hermes.dart';
import 'package:herapp/lock.dart';
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

  testWidgets('Enter sends, Shift+Enter keeps typing', (t) async {
    final calls = fakeServer(replies);
    await t.pumpWidget(const App());
    await t.showKeyboard(find.byType(EditableText).last);
    t.testTextInput.updateEditingValue(const TextEditingValue(text: 'Two', selection: TextSelection.collapsed(offset: 3)));
    await t.sendKeyDownEvent(LogicalKeyboardKey.shift);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.sendKeyUpEvent(LogicalKeyboardKey.shift);
    await t.pump();
    expect(calls.where((c) => c.$1 == 'prompt.submit'), isEmpty);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pump(const Duration(seconds: 10));
    expect(calls.where((c) => c.$1 == 'prompt.submit').single.$2, {'session_id': 'rt', 'text': 'Two'});
  });

  testWidgets('a code block in a reply names its language and copies', (t) async {
    const code = 'void main() {\n  print(1);\n}';
    fakeServer((method, params, emit) {
      if (method != 'prompt.submit') return replies(method, params, emit);
      emit('message.delta', {'text': 'Voici :\n\n```dart\n$code\n```\n'});
      emit('message.complete', {'status': 'complete'});
      return {'status': 'streaming'};
    });
    String? copied;
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
      return null;
    });
    await t.pumpWidget(const App());
    await t.enterText(find.byType(EditableText).last, 'Code');
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pump(const Duration(seconds: 10));
    expect(find.text('dart'), findsOneWidget);
    await t.tap(find.byIcon(CupertinoIcons.doc_on_doc).first); // the block's, above the reply's own
    await t.pump();
    expect(copied, code);
    await t.pump(const Duration(seconds: 3)); // the check mark goes back
    expect(find.byIcon(CupertinoIcons.doc_on_doc), findsNWidgets(2));
  });

  testWidgets('a skill is picked after / and the server expands it', (t) async {
    final calls = fakeServer((method, params, emit) {
      switch (method) {
        case 'complete.slash':
          return {
            'items': [
              {'text': '/github', 'display': '/github', 'meta': 'GitHub via gh CLI', 'kind': 'skill'},
              {'text': '/help', 'display': '/help', 'meta': 'Show commands', 'kind': 'command'},
            ],
          };
        case 'command.dispatch':
          return {'type': 'skill', 'message': 'SKILL BODY\n\nlist my PRs', 'name': 'github'};
      }
      return replies(method, params, emit);
    });
    await t.pumpWidget(const App());
    await t.enterText(find.byType(EditableText).last, '/gi');
    await t.pumpAndSettle();
    expect(find.text('GitHub via gh CLI'), findsOneWidget);
    expect(find.text('/help'), findsNothing); // commands aren't offered, only skills
    await t.tap(find.text('/github'));
    await t.pumpAndSettle();
    expect(t.widget<EditableText>(find.byType(EditableText).last).controller.text, '/github ');
    expect(find.text('GitHub via gh CLI'), findsNothing);

    await t.enterText(find.byType(EditableText).last, '/github list my PRs');
    await t.pumpAndSettle();
    await t.tap(find.byIcon(CupertinoIcons.arrow_up));
    await t.pump(const Duration(seconds: 10));
    expect(calls.where((c) => c.$1 == 'command.dispatch').single.$2, {'name': 'github', 'arg': 'list my PRs', 'session_id': 'rt'});
    expect(calls.where((c) => c.$1 == 'prompt.submit').single.$2, {
      'session_id': 'rt',
      'text': 'SKILL BODY\n\nlist my PRs',
      'title_preview': '/github list my PRs',
    });
    expect(find.text('/github list my PRs'), findsWidgets); // the bubble (and title) show what was typed
    expect(find.textContaining('Hello there'), findsOneWidget);
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
      if (path == '/api/sessions/s9') return jsonEncode({'estimated_cost_usd': 0.5, 'actual_cost_usd': 0.84});
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
    expect(
      t.widget<Tooltip>(find.ancestor(of: find.byType(CircularProgressIndicator), matching: find.byType(Tooltip))).message,
      'Context: 7% used\nCost: \$0.84',
    );

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
        (provider: 'Anthropic', name: 'claude-sonnet-5-5', id: 'anthropic/claude-sonnet-5-5', reasoning: true),
        (provider: 'OpenRouter', name: 'openai/gpt-5', id: 'openrouter/openai/gpt-5', reasoning: true),
        (provider: 'OpenRouter', name: 'plain', id: 'openrouter/plain', reasoning: false),
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

    // the effort is picked on top of the same sheet, kept for the next chats
    await t.tap(find.text('OpenRouter'));
    await t.pumpAndSettle();
    await t.tap(find.text('High'));
    await t.pumpAndSettle();
    expect(settings.effort, 'high');
    await t.tap(find.text('openai/gpt-5').last);
    await t.pumpAndSettle();
    expect(find.text('OpenRouter · High'), findsOneWidget);

    await t.enterText(find.byType(EditableText).last, 'Salut');
    await t.pumpAndSettle();
    await t.tap(find.byIcon(CupertinoIcons.arrow_up));
    await t.pump(const Duration(seconds: 10));
    expect(calls.firstWhere((c) => c.$1 == 'session.create').$2, {
      'provider': 'openrouter',
      'model': 'openai/gpt-5',
      'reasoning_effort': 'high',
    });
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
        return '{"runs":[{"id":"cron_j1_1","source":"cron","title":"Morning digest","started_at":1793520000},'
            '{"id":"cron_output:j1:x","source":"cron_output","title":"OK","preview":"3 new mails","started_at":1793430000}]}';
      }
      if (path == '/api/sessions/cron_j1_1/messages') {
        return '{"messages":[{"role":"user","content":"Summarize the night"},{"role":"assistant","content":"All quiet overnight."}]}';
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

  testWidgets('agents page shows the kanban workers', (t) async {
    t.platformDispatcher.accessibilityFeaturesTestValue = FakeAccessibilityFeatures(disableAnimations: true); // still characters
    addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
    fakeServer((_, _, _) => null);
    addTearDown(() => callApi = hermesApi);
    final started = DateTime.now().subtract(const Duration(minutes: 25)).millisecondsSinceEpoch / 1000;
    callApi = (base, method, path, {query, body, user, password}) async {
      if (path == '/api/plugins/kanban/board') {
        return '{"columns":[{"name":"ready","tasks":[{"id":"t1","title":"Fix the map","status":"ready","consecutive_failures":1,'
            '"last_failure_error":"worker exited 1"}]},{"name":"running","tasks":[{"id":"t2","title":"Build the bridge",'
            '"status":"running","current_run_started_at":$started,"last_heartbeat_at":$started}]},{"name":"done","tasks":[]}]}';
      }
      return '[]';
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
  });

  testWidgets('a wide window keeps the menu beside the chat and its pages', (t) async {
    t.view.physicalSize = const Size(1400, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    fakeServer((_, _, _) => null);
    addTearDown(() => callApi = hermesApi);
    callApi = (base, method, path, {query, body, user, password}) async => path.endsWith('/board') ? '{"columns":[]}' : '[]';
    await t.pumpWidget(const App());
    await t.pumpAndSettle();
    expect(find.byWidgetPredicate((w) => w.runtimeType.toString() == '_MenuIcon'), findsNothing);
    await t.tap(find.text('Kanban'));
    await t.pumpAndSettle();
    expect(find.text('Nothing is waiting for you.'), findsOneWidget);
    expect(find.text('New chat'), findsOneWidget); // the menu stays
    await t.tap(find.text('New chat'));
    await t.pumpAndSettle();
    expect(find.text('Nothing is waiting for you.'), findsNothing); // back to the chat
  });

  testWidgets('keyboard commands open pages, search and close', (t) async {
    t.view.physicalSize = const Size(1400, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    fakeServer((_, _, _) => null);
    addTearDown(() => callApi = hermesApi);
    callApi = (base, method, path, {query, body, user, password}) async => path.endsWith('/board') ? '{"columns":[]}' : '[]';
    await t.pumpWidget(const App());
    await t.pumpAndSettle();
    Future<void> press(LogicalKeyboardKey k) async {
      await t.sendKeyDownEvent(LogicalKeyboardKey.control);
      await t.sendKeyEvent(k);
      await t.sendKeyUpEvent(LogicalKeyboardKey.control);
      await t.pumpAndSettle();
    }

    await press(LogicalKeyboardKey.digit3); // the third page: Kanban
    expect(find.text('Nothing is waiting for you.'), findsOneWidget);
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(find.text('Nothing is waiting for you.'), findsNothing);
    await press(LogicalKeyboardKey.keyK);
    expect(t.widget<TextField>(find.byType(TextField).first).focusNode!.hasFocus, isTrue); // the search field
  });

  testWidgets('a file dropped on the window joins the next message', (t) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final dir = Directory.systemTemp.createTempSync();
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/notes.txt')..writeAsStringSync('hi');
    fakeServer((_, _, _) => null);
    await t.pumpWidget(const App());
    await t.pump();
    Future<void> platform(String method, Object args) => t.binding.defaultBinaryMessenger.handlePlatformMessage(
      'desktop_drop',
      const StandardMethodCodec().encodeMethodCall(MethodCall(method, args)),
      (_) {},
    );
    await platform('entered', [400.0, 300.0]);
    await t.pump();
    expect(find.text('Drop to attach to your message'), findsOneWidget);
    await t.runAsync(() async {
      await platform('performOperation', [file.path]);
      await Future<void>.delayed(const Duration(milliseconds: 200)); // the file is read for real
    });
    await t.pump();
    expect(find.text('Drop to attach to your message'), findsNothing);
    expect(find.text('notes.txt'), findsOneWidget); // in the draft
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('a locked app opens only once the device unlocks', (t) async {
    final saved = deviceAuth;
    addTearDown(() => deviceAuth = saved);
    var answer = false;
    var asked = 0;
    deviceAuth = (available: () async => true, confirm: (_) async => ++asked > 0 && answer);
    settings.lock = true;
    fakeServer((_, _, _) => null);
    await t.pumpWidget(const App());
    await t.pump();
    expect(asked, 1); // asked at launch, refused
    expect(find.text('Unlock'), findsOneWidget);
    answer = true;
    await t.tap(find.text('Unlock'));
    await t.pump();
    expect(find.text('Unlock'), findsNothing);

    // leaving the screen locks it again; coming back asks
    for (final s in [AppLifecycleState.inactive, AppLifecycleState.hidden]) {
      t.binding.handleAppLifecycleStateChanged(s);
    }
    await t.pump();
    expect(find.text('Unlock'), findsOneWidget);
    for (final s in [AppLifecycleState.inactive, AppLifecycleState.resumed]) {
      t.binding.handleAppLifecycleStateChanged(s);
    }
    await t.pump();
    expect(asked, 3);
    expect(find.text('Unlock'), findsNothing);
  });

  testWidgets("the Mac's global shortcut opens a new question", (t) async {
    fakeServer(replies);
    await t.pumpWidget(const App());
    await t.enterText(find.byType(EditableText).last, 'Salut');
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pump(const Duration(seconds: 10));
    await t.binding.defaultBinaryMessenger.handlePlatformMessage(
      'herapp/quick',
      const StandardMethodCodec().encodeMethodCall(const MethodCall('ask')),
      (_) {},
    );
    await t.pumpAndSettle();
    expect(find.text('How can I help?'), findsOneWidget);
    expect(t.widget<EditableText>(find.byType(EditableText).last).focusNode.hasFocus, isTrue);
  });

  testWidgets('what was shared from another app opens in a new chat, unsent', (t) async {
    final calls = fakeServer(replies);
    var shares = [
      {
        'text': 'https://example.test/article',
        'files': [
          {'name': 'photo.jpg', 'bytes': Uint8List.fromList([1, 2, 3])},
        ],
      },
    ];
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('herapp/quick'), (call) async {
      if (call.method != 'shared') return null;
      final taken = shares;
      shares = []; // the inbox empties as it is read
      return taken;
    });
    addTearDown(() => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('herapp/quick'), null));
    await t.pumpWidget(const App());
    await t.pumpAndSettle();
    expect(find.text('https://example.test/article'), findsOneWidget); // in the composer
    expect(find.byType(Image), findsOneWidget); // the photo's thumbnail
    expect(calls.where((c) => c.$1 == 'prompt.submit'), isEmpty);
  });

  testWidgets('a question asked through Siri is sent in a new chat', (t) async {
    final calls = fakeServer(replies);
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('herapp/quick'), (call) async {
      return call.method == 'ready' ? ['Quel temps demain ?'] : null; // asked before the app was up
    });
    addTearDown(() => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('herapp/quick'), null));
    await t.pumpWidget(const App());
    await t.pump(const Duration(seconds: 10));
    expect(calls.where((c) => c.$1 == 'prompt.submit').single.$2['text'], 'Quel temps demain ?');
  });

  testWidgets('a Mac gets a menu bar with the commands', (t) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    fakeServer((_, _, _) => null);
    Object? menus;
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.menu, (call) async {
      if (call.method == 'Menu.setMenus') menus = call.arguments;
      return null;
    });
    await t.pumpWidget(const App());
    await t.pump();
    final sent = jsonEncode(menus);
    for (final label in ['File', 'New chat', 'Search', 'Settings', 'View', 'Kanban', 'Window']) {
      expect(sent, contains('"$label"'));
    }
    debugDefaultTargetPlatformOverride = null;
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
    await t.tap(find.text('Model'));
    await t.pumpAndSettle();
    await t.tap(find.text('High'));
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

  testWidgets('a message sent during a reply waits, then goes after it', (t) async {
    late void Function(String, Map) push;
    final calls = fakeServer((method, params, emit) {
      if (method != 'prompt.submit') return replies(method, params, emit);
      if (params['queued'] == true) return replies(method, params, emit);
      push = emit;
      emit('message.delta', {'text': 'Working'});
      return {'status': 'streaming'};
    });
    await t.pumpWidget(const App());
    await t.enterText(find.byType(EditableText).last, 'First');
    await t.pumpAndSettle();
    await t.tap(find.byIcon(CupertinoIcons.arrow_up));
    await t.pump(const Duration(seconds: 1));
    expect(find.textContaining('Writing… 0:'), findsOneWidget); // the header tells what the turn does
    expect(find.text('Queue a message'), findsOneWidget);

    // the stop button turns into send (the reply's own animations keep pumpAndSettle from settling)
    Future<void> swap() async {
      for (final d in const [Duration.zero, Duration(milliseconds: 300), Duration.zero]) {
        await t.pump(d);
      }
    }

    await t.enterText(find.byType(EditableText).last, 'And then?');
    await swap();
    await t.tap(find.byIcon(CupertinoIcons.arrow_up)); // with text, the button queues instead of stopping
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('Queued · tap to edit'), findsOneWidget);
    expect(calls.where((c) => c.$1 == 'prompt.submit'), hasLength(1));

    // a tap takes it back to edit; sent again, it waits again
    await t.tap(find.text('And then?'));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('Queued · tap to edit'), findsNothing);
    expect(t.widget<EditableText>(find.byType(EditableText).last).controller.text, 'And then?');
    await swap();
    await t.tap(find.byIcon(CupertinoIcons.arrow_up));
    await t.pump(const Duration(milliseconds: 300));

    push('message.complete', {'text': 'Working', 'status': 'complete'});
    await t.pump(const Duration(seconds: 1));
    await t.pump(const Duration(seconds: 1));
    final submits = calls.where((c) => c.$1 == 'prompt.submit').toList();
    expect(submits.last.$2, {'session_id': 'rt', 'text': 'And then?', 'queued': true});
    expect(calls.where((c) => c.$1 == 'session.interrupt'), isEmpty); // a finished turn isn't interrupted
    expect(find.text('Queued · tap to edit'), findsNothing);
    expect(find.textContaining('Hello there'), findsOneWidget);
    await t.pump(const Duration(seconds: 10));
  });

  testWidgets('what a reply writes to memory shows as a card', (t) async {
    fakeServer((method, params, emit) {
      if (method != 'prompt.submit') return replies(method, params, emit);
      emit('tool.start', {
        'tool_id': 'm1',
        'name': 'memory',
        'args': {'action': 'add', 'target': 'user', 'content': 'Likes green tea'},
      });
      emit('tool.complete', {
        'tool_id': 'm1',
        'name': 'memory',
        'result': {'success': true},
      });
      emit('tool.start', {
        'tool_id': 'm2',
        'name': 'memory',
        'args': {'action': 'add', 'content': 'Refused note'},
      });
      emit('tool.complete', {
        'tool_id': 'm2',
        'name': 'memory',
        'result': {'success': false, 'error': 'disabled'},
      });
      emit('message.complete', {'text': 'Noted', 'status': 'complete'});
      return {'status': 'streaming'};
    });
    await t.pumpWidget(const App());
    await t.enterText(find.byType(EditableText).last, 'I like green tea');
    await t.pumpAndSettle();
    await t.tap(find.byIcon(CupertinoIcons.arrow_up));
    await t.pump(const Duration(seconds: 1));
    await t.pump(const Duration(seconds: 1));
    expect(find.text('MEMORY UPDATED'), findsOneWidget);
    expect(find.text('Likes green tea'), findsOneWidget);
    expect(find.text('Refused note'), findsNothing);
    await t.pump(const Duration(seconds: 10));
  });
}
