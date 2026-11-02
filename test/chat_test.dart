import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herapp/hermes.dart';
import 'package:herapp/mac.dart';
import 'package:herapp/main.dart';
import 'package:herapp/settings.dart';

import 'support.dart';

void main() {
  resetApp();

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
    await t.enterText(find.byType(EditableText).last, 'Next');
    await t.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing); // faded away while typing
    await t.enterText(find.byType(EditableText).last, '');
    await t.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await t.tap(find.byIcon(CupertinoIcons.arrow_2_circlepath).last); // the reply's; the first is the message's
    await t.pump(const Duration(seconds: 10));
    expect(calls.where((c) => c.$1 == 'prompt.submit').last.$2, containsPair('truncate_before_user_ordinal', 0));
    expect(find.textContaining('Hello there'), findsOneWidget); // replaced, not appended
    expect(calls.where((c) => c.$1 == 'session.create'), hasLength(1));
  });

  testWidgets('a reply runs its steps on this computer, asking for those that need it, and hands back the results', (t) async {
    settings.macShell = true;
    final token = settings.macToken;
    var prompts = 0;
    final calls = fakeServer((method, params, emit) {
      if (method == 'session.create') return {'session_id': 'rt', 'stored_session_id': 's1'};
      if (method != 'prompt.submit') return null;
      final text = prompts++ == 0 ? 'Je regarde.\n\n```mac-$token\necho auto-ran\n```\n\n```mac-$token\nprintf asked\n```\n' : 'Vu.';
      emit('message.delta', {'text': text});
      emit('message.complete', {'text': text, 'status': 'complete'});
      return {'status': 'streaming'};
    });
    Future<void> until(bool Function() done) async {
      for (var i = 0; i < 100 && !done(); i++) {
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(done(), isTrue);
    }

    await t.pumpWidget(const App());
    await t.enterText(find.byType(EditableText).last, 'Salut');
    await t.pumpAndSettle();
    await t.tap(find.byIcon(CupertinoIcons.arrow_up));
    await t.pump(const Duration(seconds: 1));
    // the instructions go before the first message, which still titles the chat
    final asked = calls.where((c) => c.$1 == 'prompt.submit').single.$2;
    expect(asked['text'], allOf(startsWith(macNoteTag), contains('mac-$token'), endsWith('\n\nSalut')));
    expect(asked['title_preview'], 'Salut');

    // the read-only step ran at once; the other waits for the user
    await until(() => find.text('Run').evaluate().isNotEmpty);
    expect(find.text('Je regarde.'), findsOneWidget);
    expect(find.textContaining('mac-$token'), findsNothing); // the blocks are cards
    expect(find.text('auto-ran'), findsOneWidget);
    await t.ensureVisible(find.text('Run'));
    await t.pump();
    await t.tap(find.text('Run'));
    await until(() => calls.where((c) => c.$1 == 'prompt.submit').length == 2);
    expect(
      calls.where((c) => c.$1 == 'prompt.submit').last.$2['text'],
      '$macResultTag\n\$ echo auto-ran\nexit 0\nauto-ran\n\n\$ printf asked\nexit 0\nasked\n\n</herapp-mac-result>', // told once
    );
    await t.pump(const Duration(seconds: 1));
    // the cards push the end out of view
    await t.drag(find.ancestor(of: find.text('Je regarde.'), matching: find.byType(Scrollable)).last, const Offset(0, -2000));
    await t.pumpAndSettle();
    expect(find.text('Results sent to Hermes'), findsOneWidget);
    expect(find.textContaining('Vu.'), findsOneWidget);
  }, skip: !macCapable);

  testWidgets('on a computer, the chat works in a folder picked on the server', (t) async {
    settings.macShell = false;
    final calls = fakeServer(
      (method, params, emit) => switch (method) {
        'complete.path' => {
          'items': switch (params['word']) {
            '@~/' => [
              {'text': '@folder:code/', 'display': 'code/', 'meta': 'dir'},
              {'text': '@file:notes.txt', 'display': 'notes.txt', 'meta': ''},
            ],
            '@folder:~/' => [
              {'text': '@folder:.config/', 'display': '.config/', 'meta': 'dir'},
              {'text': '@folder:code/', 'display': 'code/', 'meta': 'dir'},
            ],
            _ => [],
          },
        },
        'session.create' => {'session_id': 'rt', 'stored_session_id': 's1'},
        'session.cwd.set' => {'cwd': '/home/me/code'},
        'prompt.submit' => {'status': 'streaming'},
        _ => null,
      },
    );
    await t.pumpWidget(const App());
    await t.tap(find.text('Folder'));
    await t.pump();
    await t.pump(const Duration(seconds: 1)); // not settled: this computer's tab lists for real
    await t.tap(find.text('Server'));
    await t.pumpAndSettle();
    expect(find.text('notes.txt'), findsNothing); // folders only, hidden ones last
    expect(t.getTopLeft(find.text('code')).dy, lessThan(t.getTopLeft(find.text('.config')).dy));
    await t.tap(find.text('code'));
    await t.pumpAndSettle();
    expect(find.text('No folders here'), findsOneWidget);
    await t.tap(find.text('Choose'));
    await t.pumpAndSettle();
    expect(find.text('~/code · server'), findsOneWidget);

    // what the bot changed there: files, a diff, a commit then a push
    addTearDown(() => callApi = hermesApi);
    final sent = <String>[];
    var committed = false;
    callApi = (base, method, path, {query, body, user, password}) async {
      if (method == 'POST') {
        sent.add('$path ${jsonEncode(body)}');
        committed = true;
        return '{"ok":true}';
      }
      expect(query?['path'], '~/code');
      return jsonEncode(switch (path) {
        '/api/git/status' => {'branch': 'main', 'ahead': committed ? 1 : 0, 'behind': 0},
        '/api/git/review/list' => {
          'files': [
            if (!committed) {'path': 'lib/a.dart', 'added': 3, 'removed': 1, 'status': 'M'},
          ],
        },
        '/api/git/review/ship-info' => {'ghReady': false, 'pr': null},
        '/api/git/review/diff' => {'diff': '@@ -1 +1 @@\n-old\n+new'},
        _ => {},
      });
    };
    await t.tap(find.text('Changes'));
    await t.pumpAndSettle();
    expect(find.text('~/code · main'), findsOneWidget);
    expect(find.text('lib/a.dart'), findsOneWidget);
    await t.tap(find.text('lib/a.dart'));
    await t.pumpAndSettle();
    expect(find.textContaining('+new', findRichText: true), findsOneWidget);
    await t.tap(find.byIcon(CupertinoIcons.chevron_back));
    await t.pumpAndSettle();
    await t.enterText(find.byType(CupertinoTextField), 'Fix a');
    await t.pumpAndSettle();
    await t.tap(find.text('Commit everything'));
    await t.pumpAndSettle();
    expect(find.text('Nothing changed'), findsOneWidget);
    await t.tap(find.text('Push 1 commit'));
    await t.pumpAndSettle();
    expect(sent, ['/api/git/review/commit {"path":"~/code","message":"Fix a"}', '/api/git/review/push {"path":"~/code"}']);
    await t.tap(find.byIcon(CupertinoIcons.chevron_back));
    await t.pumpAndSettle();

    // the session starts there, as the server names it
    await t.enterText(find.byType(EditableText).last, 'Salut');
    await t.pumpAndSettle();
    await t.tap(find.byIcon(CupertinoIcons.arrow_up));
    await t.pump(const Duration(seconds: 1));
    expect(calls.where((c) => c.$1 == 'session.cwd.set').single.$2, {'session_id': 'rt', 'cwd': '~/code'});
    expect(calls.where((c) => c.$1 == 'prompt.submit').single.$2['text'], 'Salut');
    expect(find.text('/home/me/code · server'), findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets('a reply being written lets the user scroll up through it', (t) async {
    late void Function(String, Map) push;
    fakeServer((method, params, emit) {
      if (method == 'prompt.submit') push = emit;
      return method == 'session.create' ? {'session_id': 'rt', 'stored_session_id': 's1'} : null;
    });
    await t.pumpWidget(const App());
    await t.enterText(find.byType(EditableText).last, 'Tell a long story');
    await t.pumpAndSettle();
    await t.tap(find.byIcon(CupertinoIcons.arrow_up));
    await t.pump(const Duration(milliseconds: 100));
    for (var i = 0; i < 40; i++) {
      push('message.delta', {'text': 'Line $i of the story.\n\n'});
    }
    await t.pump(const Duration(milliseconds: 100));
    await t.pump();
    final list = find.ancestor(of: find.textContaining('Line 0 of'), matching: find.byType(Scrollable)).last;
    final position = t.state<ScrollableState>(list).position;
    expect(position.pixels, position.maxScrollExtent); // follows the reply

    final finger = await t.startGesture(t.getCenter(list));
    await finger.moveBy(const Offset(0, 30)); // a slow drag up, still near the bottom
    await t.pump();
    push('message.delta', {'text': 'More.\n\n'});
    await t.pump(const Duration(milliseconds: 100));
    await finger.moveBy(const Offset(0, 300));
    await t.pump();
    await finger.up();
    await t.pumpAndSettle();
    expect(position.maxScrollExtent - position.pixels, greaterThan(200)); // the drag wasn't taken back
    push('message.delta', {'text': 'Even more.\n\n'});
    await t.pump(const Duration(milliseconds: 100));
    expect(position.maxScrollExtent - position.pixels, greaterThan(200)); // and stays where the user left it
    push('message.complete', {'text': '', 'status': 'complete'});
    await t.pump(const Duration(seconds: 1));
  });

  testWidgets('a sent message is rewritten or sent again in its place', (t) async {
    final calls = fakeServer(replies);
    await t.pumpWidget(const App());
    Future<void> sendText(String text) async {
      await t.enterText(find.byType(EditableText).last, text);
      await t.pumpAndSettle();
      await t.tap(find.byIcon(CupertinoIcons.arrow_up));
      await t.pump(const Duration(seconds: 1));
      await t.pump(const Duration(seconds: 1));
    }

    await sendText('One');
    await sendText('Two');
    expect(find.textContaining('Hello there'), findsNWidgets(2));
    expect(find.byIcon(CupertinoIcons.pencil), findsNWidgets(2));

    // the first message, rewritten: the conversation goes on from it, without what followed
    await t.tap(find.byIcon(CupertinoIcons.pencil).first);
    await t.pumpAndSettle();
    expect(t.widget<EditableText>(find.byType(EditableText).last).controller.text, 'One');
    expect(find.text('Editing message · sent in its place'), findsOneWidget);
    await sendText('Uno');
    expect(calls.where((c) => c.$1 == 'prompt.submit').last.$2, {
      'session_id': 'rt',
      'text': 'Uno',
      'truncate_before_user_ordinal': 0,
      'confirm_truncate': true,
    });
    expect(find.text('One'), findsNothing);
    expect(find.text('Two'), findsNothing);
    expect(find.textContaining('Hello there'), findsOneWidget);
    expect(find.text('Editing message · sent in its place'), findsNothing);

    // sent again as is
    await t.tap(find.byIcon(CupertinoIcons.arrow_2_circlepath).first);
    await t.pump(const Duration(seconds: 1));
    await t.pump(const Duration(seconds: 1));
    expect(calls.where((c) => c.$1 == 'prompt.submit').last.$2, containsPair('text', 'Uno'));
    expect(calls.where((c) => c.$1 == 'prompt.submit').last.$2, containsPair('truncate_before_user_ordinal', 0));
    expect(find.textContaining('Hello there'), findsOneWidget);

    // an edit can be dropped
    await t.tap(find.byIcon(CupertinoIcons.pencil));
    await t.pumpAndSettle();
    await t.tap(find.byIcon(CupertinoIcons.xmark_circle_fill));
    await t.pumpAndSettle();
    expect(t.widget<EditableText>(find.byType(EditableText).last).controller.text, isEmpty);
    await t.pump(const Duration(seconds: 10));
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

  testWidgets('a reply browsing the web shows the bot screen, which opens to take over', (t) async {
    const png = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';
    final calls = fakeServer((method, params, emit) {
      switch (method) {
        case 'session.create':
          return {'session_id': 'rt', 'stored_session_id': 's1'};
        case 'prompt.submit':
          emit('tool.start', {'tool_id': 't1', 'name': 'browser_navigate', 'context': 'https://mail.test'});
        case 'display.thumbnail':
          return {'data_url': png};
        case 'display.status':
          return {'installed': false};
      }
      return null;
    });
    await t.pumpWidget(const App());
    await t.enterText(find.byType(EditableText).last, 'Read my mail');
    await t.pumpAndSettle();
    await t.tap(find.byIcon(CupertinoIcons.arrow_up));
    await t.pump(const Duration(seconds: 1));
    expect(find.text('Bot screen · take over'), findsOneWidget);
    await t.pump(); // the frame asked for as it showed
    expect(find.byType(Image), findsOneWidget);
    await t.pump(const Duration(seconds: 4));
    expect(calls.where((c) => c.$1 == 'display.thumbnail').length, greaterThan(1)); // kept fresh while it browses

    // the reply still runs (its spinners never settle)
    await t.tap(find.text('Bot screen · take over'));
    await t.pump(const Duration(seconds: 1));
    await t.pump(const Duration(seconds: 1));
    expect(find.text('Bot screen'), findsOneWidget);
    expect(find.textContaining("isn't installed on the server"), findsOneWidget);
    await t.tap(find.byIcon(CupertinoIcons.chevron_back));
    await t.pump(const Duration(seconds: 1));
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
    expect(find.text('claude-sonnet-5-5'), findsNWidgets(2)); // the session's own model: in the title, over its reply
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

  testWidgets('a chat reopened while it answers shows the reply coming in', (t) async {
    late void Function(String, Map) push;
    final calls = fakeServer((method, params, emit) {
      switch (method) {
        case 'session.list':
          return {
            'sessions': [
              {'id': 's9', 'title': 'Long task', 'preview': ''},
            ],
          };
        case 'session.resume':
          push = emit;
          return {
            'session_id': 'rt',
            'running': true,
            'turn_started_at': DateTime.now().millisecondsSinceEpoch / 1000 - 65,
            'inflight': {'user': 'Do the long task', 'assistant': 'Step one', 'streaming': true},
          };
      }
      return null;
    });
    addTearDown(() => callApi = hermesApi);
    callApi = (base, method, path, {query, body, user, password}) async => jsonEncode({
      'messages': [
        {'role': 'user', 'content': 'Hi'},
        {'role': 'assistant', 'content': 'Hello'},
        {'role': 'user', 'content': 'Do the long task'}, // already stored, not shown twice
      ],
    });
    await t.pumpWidget(const App());
    await t.tap(find.byWidgetPredicate((w) => w.runtimeType.toString() == '_MenuIcon'), warnIfMissed: false);
    await t.pumpAndSettle();
    await t.tap(find.text('Long task'));
    for (final d in const [Duration.zero, Duration(milliseconds: 400), Duration(milliseconds: 400)]) {
      await t.pump(d);
    }
    expect(find.text('Do the long task'), findsOneWidget);
    expect(find.textContaining('Step one'), findsOneWidget);
    expect(find.textContaining('Writing… 1:0'), findsOneWidget); // the turn's own start, not the reopening

    push('message.delta', {'text': ', step two'});
    await t.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('Step one, step two'), findsOneWidget);
    push('message.complete', {'text': 'Step one, step two', 'status': 'complete'});
    await t.pump(const Duration(seconds: 1));
    expect(find.textContaining('Writing…'), findsNothing);
    expect(calls.where((c) => c.$1 == 'session.interrupt'), isEmpty);
    await t.pump(const Duration(seconds: 10));
  });

  testWidgets('a chat reopened while the server wraps up its finished reply is idle', (t) async {
    fakeServer(
      (method, params, emit) => switch (method) {
        'session.list' => {
          'sessions': [
            {'id': 's9', 'title': 'Done task', 'preview': ''},
          ],
        },
        'session.resume' => {'session_id': 'rt', 'running': true}, // titling or saving memory: no inflight reply
        _ => null,
      },
    );
    addTearDown(() => callApi = hermesApi);
    callApi = (base, method, path, {query, body, user, password}) async => jsonEncode({
      'messages': [
        {'role': 'user', 'content': 'Hi'},
        {'role': 'assistant', 'content': 'Hello'},
      ],
    });
    await t.pumpWidget(const App());
    await t.tap(find.byWidgetPredicate((w) => w.runtimeType.toString() == '_MenuIcon'), warnIfMissed: false);
    await t.pumpAndSettle();
    await t.tap(find.text('Done task'));
    await t.pumpAndSettle();
    expect(find.text('Hello'), findsOneWidget);
    expect(find.text('Ask anything'), findsOneWidget); // not "Queue a message" behind a stop button
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

  testWidgets('a chat is pinned from its menu, archived by swiping right, and comes back from Archived', (t) async {
    final rows = [
      {'id': 's8', 'title': 'Groceries'},
      {'id': 's9', 'title': 'Trip to Lyon'},
    ];
    final archived = <Map>[];
    final calls = fakeServer((method, params, emit) {
      if (method == 'session.archive') {
        final row = [...rows, ...archived].firstWhere((r) => r['id'] == params['session_id']);
        (params['archived'] == true ? rows : archived).remove(row);
        (params['archived'] == true ? archived : rows).add(row);
      }
      return method == 'session.list' ? {'sessions': rows} : null;
    });
    final patches = <(String, Object?)>[];
    var pinned = false;
    addTearDown(() => callApi = hermesApi);
    callApi = (base, method, path, {query, body, user, password}) async {
      if (method == 'PATCH') {
        patches.add((path, jsonEncode(body)));
        pinned = (body as Map)['pinned'] as bool;
      }
      return jsonEncode(switch (path) {
        '/api/sessions' when query?['archived'] == 'only' => {'sessions': archived},
        '/api/sessions' => {
          'sessions': [
            for (final r in rows) {...r, 'pinned': pinned && r['id'] == 's8'},
          ],
        },
        '/api/sessions/s8/mutation-snapshot' => {'exists': true, 'runtime_revision': 3},
        _ => {'ok': true},
      });
    };
    t.view.physicalSize = const Size(2400, 4200); // a tall phone: the whole menu in view
    addTearDown(t.view.reset);
    await t.pumpWidget(const App());
    await t.tap(find.byWidgetPredicate((w) => w.runtimeType.toString() == '_MenuIcon'), warnIfMissed: false);
    await t.pumpAndSettle();
    expect(find.text('Pinned'), findsNothing);

    await t.longPress(find.text('Groceries'));
    await t.pumpAndSettle();
    await t.tap(find.text('Pin'));
    await t.pumpAndSettle();
    expect(patches.single.$1, '/api/sessions/s8');
    expect(jsonDecode(patches.single.$2 as String), allOf(containsPair('pinned', true), containsPair('expected_revision', 3)));
    expect(find.text('Pinned'), findsOneWidget);
    expect(t.getTopLeft(find.text('Groceries')).dy, lessThan(t.getTopLeft(find.text('Chats')).dy)); // above the others

    await t.drag(find.text('Trip to Lyon'), const Offset(300, 0));
    await t.pumpAndSettle();
    expect(calls.where((c) => c.$1 == 'session.archive').single.$2, {'session_id': 's9', 'archived': true});
    expect(find.text('Trip to Lyon'), findsNothing);

    await t.tap(find.text('Archived'));
    await t.pumpAndSettle();
    expect(find.text('Trip to Lyon'), findsOneWidget);
    await t.tap(find.text('Unarchive'));
    await t.pumpAndSettle();
    expect(calls.where((c) => c.$1 == 'session.archive').last.$2, {'session_id': 's9', 'archived': false});
    expect(find.text('Trip to Lyon'), findsNothing); // gone from Archived
    await t.pageBack();
    await t.pumpAndSettle();
    expect(find.text('Trip to Lyon'), findsOneWidget); // back in the menu
  });

  testWidgets('server models can be picked while the chat is empty', (t) async {
    stillStripes(t);
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
    // the models used last come first, the others behind a button
    expect(find.text('openai/gpt-5'), findsNothing);
    await t.tap(find.text('More models'));
    await t.pumpAndSettle();
    await t.tap(find.text('openai/gpt-5').last);
    await t.pumpAndSettle();
    expect(settings.model, 'openrouter/openai/gpt-5');
    expect(find.text('OpenRouter'), findsOneWidget);

    // the effort is picked on top of the same sheet, kept for the next chats
    await t.tap(find.text('OpenRouter'));
    await t.pumpAndSettle();
    expect(settings.recentModels, ['openrouter/openai/gpt-5']);
    expect(find.text('openai/gpt-5'), findsNWidgets(2)); // the pill, and the sheet's recent ones
    expect(find.text('claude-sonnet-5-5'), findsNothing);
    expect(find.text('plain'), findsNothing);
    await tapEffort(t, 'high');
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
    expect(find.text('openai/gpt-5'), findsNWidgets(2)); // title shown and over the reply, pill gone
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

  testWidgets('a reply keeps streaming while another chat is open', (t) async {
    late void Function(String, Map) push;
    var listed = false; // the server lists the chat once its first reply is done
    final calls = fakeServer((method, params, emit) {
      if (method == 'session.list' && listed && params['title'] == null) {
        return {
          'sessions': [
            {'id': 's1', 'title': 'First', 'preview': ''},
          ],
        };
      }
      if (method != 'prompt.submit') return replies(method, params, emit);
      push = emit;
      emit('message.delta', {'text': 'Working'});
      return {'status': 'streaming'};
    });
    Future<void> menu() async {
      await t.tap(find.byWidgetPredicate((w) => w.runtimeType.toString() == '_MenuIcon'), warnIfMissed: false);
      for (final d in const [Duration.zero, Duration(milliseconds: 400)]) {
        await t.pump(d);
      }
    }

    await t.pumpWidget(const App());
    await t.enterText(find.byType(EditableText).last, 'First');
    await t.pumpAndSettle();
    await t.tap(find.byIcon(CupertinoIcons.arrow_up));
    await t.pump(const Duration(seconds: 1));

    await menu();
    await t.tap(find.text('New chat'));
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('How can I help?'), findsOneWidget);
    await menu(); // still listed while it answers, though the server doesn't list it yet
    expect(find.text('First'), findsOneWidget);
    await t.tap(find.text('New chat'));
    await t.pump(const Duration(milliseconds: 400));
    listed = true;
    push('message.delta', {'text': ' done'});
    push('message.complete', {'text': 'Working done', 'status': 'complete'});
    await t.pump(const Duration(seconds: 1));
    expect(calls.where((c) => c.$1 == 'session.interrupt'), isEmpty);

    // back in the first chat, the whole reply is there
    await menu();
    await t.tap(find.text('First'));
    await t.pump(const Duration(seconds: 1));
    expect(find.textContaining('Working done'), findsOneWidget);
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

  testWidgets('the Bot Chat opens from the menu, with routine results apart', (t) async {
    final calls = fakeServer(
      (method, params, emit) => switch (method) {
        'session.list' when params['title'] == 'Bot Chat' => {
          'sessions': [
            {'id': 'b1', 'resolved_id': 'b2', 'title': 'Bot Chat'},
          ],
        },
        'session.list' => {'sessions': []},
        _ => null,
      },
    );
    addTearDown(() => callApi = hermesApi);
    final paths = <String>[];
    callApi = (base, method, path, {query, body, user, password}) async {
      paths.add(path);
      return jsonEncode({
        'messages': [
          {'role': 'user', 'content': '[Cronjob "Daily news" output — scheduled job, not the user. Review it.]\n\nRain in Lyon'},
          {'role': 'assistant', 'content': 'Take an umbrella today.'},
        ],
      });
    };
    await t.pumpWidget(const App());
    await t.tap(find.byWidgetPredicate((w) => w.runtimeType.toString() == '_MenuIcon'), warnIfMissed: false);
    await t.pumpAndSettle();
    await t.tap(find.text('Bot Chat'));
    await t.pumpAndSettle();
    expect(paths, contains('/api/sessions/b2/messages')); // the live end of the chat
    expect(find.text('ROUTINE · DAILY NEWS'), findsOneWidget);
    expect(find.text('Rain in Lyon'), findsOneWidget);
    expect(find.textContaining('[Cronjob'), findsNothing); // not shown as the user's words
    expect(find.text('Take an umbrella today.'), findsOneWidget);

    // it isn't listed again among the chats, and reopening it reads what came in meanwhile
    await t.tap(find.byWidgetPredicate((w) => w.runtimeType.toString() == '_MenuIcon'), warnIfMissed: false);
    await t.pumpAndSettle();
    expect(find.text('Bot Chat'), findsOneWidget);
    await t.tap(find.text('Bot Chat'));
    await t.pumpAndSettle();
    expect(paths.where((p) => p == '/api/sessions/b2/messages'), hasLength(2));
    expect(calls.where((c) => c.$1 == 'session.list' && c.$2['title'] == 'Bot Chat'), isNotEmpty);
  });

  testWidgets('every button of a conversation is named for screen readers', (t) async {
    final handle = t.ensureSemantics();
    fakeServer(replies);
    await t.pumpWidget(const App());
    await t.enterText(find.byType(EditableText).last, 'Salut');
    await t.pumpAndSettle();
    await expectLater(t, meetsGuideline(labeledTapTargetGuideline)); // the composer, send shown
    await t.tap(find.byIcon(CupertinoIcons.arrow_up));
    await t.pump(const Duration(seconds: 10));
    await t.pump(const Duration(seconds: 1));
    expect(find.textContaining('Hello there'), findsOneWidget);
    await expectLater(t, meetsGuideline(labeledTapTargetGuideline)); // a reply and its actions, the mic
    expect(find.byTooltip('Read aloud'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('an image the server draws joins the next message, and a PDF goes with its pages', (t) async {
    const png = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';
    final calls = fakeServer(
      (method, params, emit) => switch (method) {
        'image.generate' => {'available': true, 'success': true, 'image_data': 'data:image/png;base64,$png'},
        'file.attach' => {'attached': true, 'ref_text': '@file:attachments/${params['name']}'},
        _ => replies(method, params, emit),
      },
    );
    var shares = [
      {
        'text': '',
        'files': [
          {'name': 'Report.PDF', 'bytes': Uint8List.fromList('%PDF-1.4'.codeUnits)},
        ],
      },
    ];
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('herapp/quick'), (call) async {
      if (call.method != 'shared') return null;
      final taken = shares;
      shares = [];
      return taken;
    });
    addTearDown(() => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('herapp/quick'), null));
    await t.pumpWidget(const App());
    await t.pumpAndSettle();
    expect(find.text('Report.PDF'), findsOneWidget); // in the draft

    await t.tap(find.byTooltip('Attach files'));
    await t.pumpAndSettle();
    await t.tap(find.text('Create an image'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(CupertinoTextField), 'A lighthouse at dawn');
    await t.tap(find.text('Landscape'));
    await t.pump();
    await t.tap(find.text('Create'));
    await t.pumpAndSettle();
    expect(calls.where((c) => c.$1 == 'image.generate').single.$2, {'prompt': 'A lighthouse at dawn', 'aspect_ratio': 'landscape'});
    await t.tap(find.text('Attach to the message'));
    await t.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget); // its thumbnail in the draft

    await t.enterText(find.byType(EditableText).last, 'Here');
    await t.pumpAndSettle();
    await t.tap(find.byIcon(CupertinoIcons.arrow_up));
    await t.pump(const Duration(seconds: 10));
    expect(calls.where((c) => c.$1 == 'image.attach_bytes').single.$2, containsPair('filename', 'hermes-image.png'));
    expect(calls.where((c) => c.$1 == 'file.attach').single.$2, containsPair('name', 'Report.PDF'));
    expect(calls.where((c) => c.$1 == 'pdf.attach').single.$2, {
      'session_id': 'rt',
      'content_base64': base64Encode('%PDF-1.4'.codeUnits),
      'filename': 'Report.PDF',
    });
    expect(calls.where((c) => c.$1 == 'prompt.submit').single.$2['text'], 'Here\n\n@file:attachments/Report.PDF');
  });

  testWidgets('the menu groups chats by their last activity and marks the one answering', (t) async {
    double at(Duration ago) => DateTime.now().subtract(ago).millisecondsSinceEpoch / 1000;
    fakeServer(
      (method, params, emit) => switch (method) {
        'session.list' => {
          'sessions': [
            {'id': 's1', 'title': 'Old plan', 'started_at': at(const Duration(days: 90))},
            {'id': 's2', 'title': 'Fresh idea', 'started_at': at(const Duration(days: 90))},
          ],
        },
        _ => null,
      },
    );
    addTearDown(() => callApi = hermesApi);
    callApi = (base, method, path, {query, body, user, password}) async => jsonEncode({
      // the REST page knows the last activity
      'sessions': [
        {'id': 's2', 'title': 'Fresh idea', 'last_active': at(const Duration(minutes: 5))},
      ],
    });
    await t.pumpWidget(const App());
    await t.tap(find.byWidgetPredicate((w) => w.runtimeType.toString() == '_MenuIcon'), warnIfMissed: false);
    await t.pumpAndSettle();
    double y(String text) => t.getTopLeft(find.text(text)).dy;
    expect(y('Today'), lessThan(y('Fresh idea')));
    expect(y('Fresh idea'), lessThan(y('Older')));
    expect(y('Older'), lessThan(y('Old plan')));
  });

  testWidgets('an empty chat suggests what to ask, and shows what runs now', (t) async {
    late void Function(String, Map) push;
    final calls = fakeServer((method, params, emit) {
      if (method == 'session.list') push = emit;
      return null;
    });
    await t.pumpWidget(const App());
    await t.pump(const Duration(milliseconds: 100));
    await t.tap(find.text('Give me a status of my kanban'));
    await t.pump();
    expect(t.widget<EditableText>(find.byType(EditableText).last).controller.text, 'Give me a status of my kanban');
    expect(calls.where((c) => c.$1 == 'prompt.submit'), isEmpty); // filled in, not sent

    push('subagent.start', {'subagent_id': 'a1', 'goal': 'Read the docs', 'task_count': 1, 'task_index': 0});
    await t.pump(const Duration(milliseconds: 100));
    expect(find.text('1 subagent at work'), findsOneWidget);
  });

  testWidgets('on a computer, an earlier reply shows its actions only under the mouse', (t) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    fakeServer(replies);
    await t.pumpWidget(const App());
    for (final q in ['One', 'Two']) {
      await t.enterText(find.byType(EditableText).last, q);
      await t.pump(const Duration(seconds: 1));
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.pump(const Duration(seconds: 10));
      await t.pump(const Duration(seconds: 1));
    }
    double shown(Finder copy) => t.widget<AnimatedOpacity>(find.ancestor(of: copy, matching: find.byType(AnimatedOpacity)).first).opacity;
    final copies = find.byTooltip('Copy');
    expect(shown(copies.first), 0); // the first reply's, till hovered
    expect(shown(copies.last), 1); // the latest reply's stay in sight

    final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: t.getCenter(find.textContaining('Hello there').first));
    await t.pump(const Duration(milliseconds: 200));
    expect(shown(copies.first), 1);
    await mouse.removePointer();
    debugDefaultTargetPlatformOverride = null;
  });
}
