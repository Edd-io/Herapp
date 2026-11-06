import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herapp/hermes.dart';
import 'package:herapp/lock.dart';
import 'package:herapp/main.dart';
import 'package:herapp/settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support.dart';

void main() {
  resetApp();

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

    await t.ensureVisible(find.byTooltip('Gold'));
    await t.tap(find.byTooltip('Gold'));
    await t.pumpAndSettle();
    final theme = t.widget<MaterialApp>(find.byType(MaterialApp)).darkTheme!.colorScheme;
    // the send button, filled buttons, links: gold deepened until white text reads on it
    expect(theme.primary, isNot(const Color(0xFFC9A227)));
    expect(theme.onPrimary, Colors.white);
    expect(contrast(Colors.white, theme.primary), greaterThanOrEqualTo(4.5));
    final cupertino = CupertinoTheme.of(t.element(find.byType(CupertinoSwitch).first));
    expect((cupertino.applyThemeToAll, cupertino.primaryColor), (true, theme.primary)); // switches on, in the accent

    await settings.load();
    expect(settings.theme, ThemeMode.dark);
    expect(settings.accent, 0xFFC9A227);
  });

  testWidgets('every text color reads on every surface, in both themes', (t) async {
    await t.pumpWidget(const App());
    final app = t.widget<MaterialApp>(find.byType(MaterialApp));
    for (final c in [app.theme!.colorScheme, app.darkTheme!.colorScheme]) {
      for (final text in [c.onSurface, c.onSurfaceVariant, c.outline]) {
        for (final ground in [c.surface, c.surfaceContainerHighest, c.surfaceContainerLow]) {
          expect(contrast(text, ground), greaterThanOrEqualTo(4.5), reason: '$text on $ground (${c.brightness})');
        }
      }
    }
    settings.accent = 0xFFC9A227; // gold: too light for links on white
    expect(accentText(app.theme!.colorScheme.copyWith(primary: const Color(0xFFC9A227))), isNull);
    expect(accentText(app.darkTheme!.colorScheme.copyWith(primary: const Color(0xFFC9A227))), const Color(0xFFC9A227));
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

  test('each server keeps its own settings, the first one under the keys it always had', () async {
    SharedPreferences.setMockInitialValues({'url': 'https://home.test', 'model': 'a/b', 'user': 'me'});
    FlutterSecureStorage.setMockInitialValues({'hermes_password': 'secret'});
    await settings.load();
    expect(settings.servers, ['']);
    expect((settings.url, settings.model, settings.user, settings.password), ('https://home.test', 'a/b', 'me', 'secret'));

    final switched = serverSwitched.value;
    await addServer();
    expect(settings.servers, hasLength(2));
    expect(serverSwitched.value, switched + 1);
    expect((settings.url, settings.model, settings.user, settings.password), ('', '', '', ''));
    settings
      ..url = 'https://work.test/'
      ..model = 'c/d';
    await settings.setPassword('other');
    final work = settings.server;
    expect(serverLabel(work, 'New'), 'work.test');
    settings.name = 'Work';
    expect(serverLabel(work, 'New'), 'Work');

    await switchServer('');
    expect((settings.url, settings.model, settings.password), ('https://home.test', 'a/b', 'secret'));
    await switchServer(work);
    expect((settings.url, settings.model, settings.password), ('https://work.test/', 'c/d', 'other'));

    // the one in use removed: back on the other, which can't be removed in turn
    await removeServer(work);
    expect(settings.servers, ['']);
    expect(settings.url, 'https://home.test');
    expect(await const FlutterSecureStorage().read(key: 'hermes_password_$work'), isNull);
    await removeServer('');
    expect(settings.servers, ['']);
  });

  testWidgets('the menu switches between servers, each with its own chats', (t) async {
    fakeServer(
      (method, params, emit) => method == 'session.list' && params['title'] == null
          ? {
              'sessions': [
                {
                  'id': settings.url.contains('work') ? 'w1' : 'h1',
                  'title': settings.url.contains('work') ? 'Quarterly plan' : 'Trip to Lyon',
                },
              ],
            }
          : null,
    );
    addTearDown(() => callApi = hermesApi);
    callApi = (base, method, path, {query, body, user, password}) async => '{}';
    settings.url = 'https://home.test';
    await addServer();
    settings
      ..url = 'https://work.test'
      ..name = 'Work';
    await switchServer('');

    await t.pumpWidget(const App());
    await t.tap(find.byWidgetPredicate((w) => w.runtimeType.toString() == '_MenuIcon'), warnIfMissed: false);
    await t.pumpAndSettle();
    expect(find.text('Trip to Lyon'), findsOneWidget);
    await t.tap(find.text('home.test'));
    await t.pumpAndSettle();
    await t.tap(find.text('Work'));
    await t.pumpAndSettle();
    await t.tap(find.byWidgetPredicate((w) => w.runtimeType.toString() == '_MenuIcon'), warnIfMissed: false);
    await t.pumpAndSettle();
    expect(find.text('Work'), findsOneWidget);
    expect(find.text('Quarterly plan'), findsOneWidget);
    expect(find.text('Trip to Lyon'), findsNothing);
  });

  testWidgets('settings add a server and switch between them', (t) async {
    fakeServer((_, _, _) => null);
    addTearDown(() => callApi = hermesApi);
    callApi = (base, method, path, {query, body, user, password}) async => '{}';
    settings.url = 'https://home.test';
    await t.pumpWidget(const App());
    await t.tapAt(const Offset(30, 50)); // menu icon
    await t.pumpAndSettle();
    await t.tap(find.text('Settings'));
    await t.pumpAndSettle();
    expect(find.text('Remove this server'), findsNothing); // the only one

    await t.tap(find.text('Add a server'));
    await t.pumpAndSettle();
    expect(settings.servers, hasLength(2));
    expect(find.widgetWithText(CupertinoTextField, 'https://home.test'), findsNothing); // the new one's fields, blank
    await t.enterText(find.widgetWithText(CupertinoTextField, 'Name (optional)'), 'Lab');
    await t.pumpAndSettle();
    expect(find.text('LAB'), findsOneWidget); // its section, titled with its name

    await t.tap(find.text('home.test'));
    await t.pumpAndSettle();
    expect(settings.url, 'https://home.test');
    expect(find.widgetWithText(CupertinoTextField, 'https://home.test'), findsOneWidget);

    await t.tap(find.text('Lab'));
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('Remove this server'));
    await t.pumpAndSettle();
    await t.tap(find.text('Remove this server'));
    await t.pumpAndSettle();
    await t.tap(find.text('Remove this server').last); // confirmed
    await t.pumpAndSettle();
    expect(settings.servers, ['']);
    expect(settings.url, 'https://home.test');
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

  testWidgets('keyboard commands open pages and the palette, and close', (t) async {
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
    // the palette: typed, moved through with the arrows, run with Enter
    await press(LogicalKeyboardKey.keyK);
    expect(find.text('A command, a page or a chat'), findsOneWidget);
    await t.enterText(find.byType(TextField).last, 'a');
    await t.pump();
    expect(find.text('Ctrl+3'), findsOneWidget); // Kanban, with its shortcut
    await t.enterText(find.byType(TextField).last, 'kan');
    await t.pump();
    expect(find.text('Ctrl+1'), findsNothing); // Quotas left out
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    expect(find.text('A command, a page or a chat'), findsNothing);
    expect(find.text('Nothing is waiting for you.'), findsOneWidget);
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
    for (final label in ['File', 'New chat', 'Find or Run…', 'Settings', 'View', 'Kanban', 'Window']) {
      expect(sent, contains('"$label"'));
    }
    debugDefaultTargetPlatformOverride = null;
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

  testWidgets('the open conversation is handed to other devices, and one handed over opens', (t) async {
    fakeServer(
      (method, params, emit) => switch (method) {
        'session.list' => {
          'sessions': [
            {'id': 's9', 'title': 'Trip plans', 'message_count': 2},
          ],
        },
        _ => replies(method, params, emit),
      },
    );
    final offers = <Object?>[];
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('herapp/quick'), (call) async {
      if (call.method == 'handoff') offers.add(call.arguments);
      return call.method == 'continued' ? {'session': 's9', 'title': 'Trip plans', 'server': 'https://hermes.test/'} : null;
    });
    addTearDown(() => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('herapp/quick'), null));
    await t.pumpWidget(const App());
    await t.pump(const Duration(seconds: 1));
    expect(offers.last, {'session': 's9', 'title': 'Trip plans', 'server': 'https://hermes.test'});

    await t.tap(find.byTooltip('New chat'));
    await t.pump();
    expect(offers.last, isNull); // nothing stored to hand over yet
  });
}
