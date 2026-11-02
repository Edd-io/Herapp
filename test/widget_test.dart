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
import 'package:herapp/mac.dart';
import 'package:herapp/main.dart';
import 'package:herapp/model_sheet.dart';
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

/// Asks for less motion, which stills the effort bar's stripes: running, they never let a test settle.
void stillStripes(WidgetTester t) {
  t.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
}

/// Taps [effort]'s place on the effort bar.
Future<void> tapEffort(WidgetTester t, String effort) async {
  final bar = t.getRect(find.byKey(const ValueKey('effort')));
  await t.tapAt(Offset(bar.left + 17 + (bar.width - 34) * efforts.indexOf(effort) / (efforts.length - 1), bar.center.dy));
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await settings.load();
    dropGateway();
    subagents.value = const {};
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
    expect(find.text('openai/gpt-5'), findsOneWidget); // title shown, pill gone
  });

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

  testWidgets('picker explains a missing server', (t) async {
    stillStripes(t);
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
          {
            'name': 'photo.jpg',
            'bytes': Uint8List.fromList([1, 2, 3]),
          },
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

  testWidgets('a strip tells while the server does not answer, until it is back', (t) async {
    stillStripes(t);
    fakeServer(replies);
    addTearDown(() => callApi = hermesApi);
    var down = true;
    callApi = (base, method, path, {query, body, user, password}) async =>
        down ? throw const SocketException('Connection refused') : jsonEncode(path == '/api/status' ? {'version': '1'} : []);
    await t.pumpWidget(const App());
    await serverApi('GET', '/api/skills').catchError((Object _) => null);
    await t.pump();
    expect(find.text('The server isn’t answering'), findsOneWidget);

    await t.tap(find.text('Try again'));
    await t.pump();
    expect(find.text('The server isn’t answering'), findsOneWidget); // still down

    down = false;
    await t.pump(const Duration(seconds: 5)); // asked again on its own
    await t.pump();
    expect(find.text('The server isn’t answering'), findsNothing);
  });
}
