import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herapp/chat_page.dart';
import 'package:herapp/hermes.dart';
import 'package:herapp/main.dart';
import 'package:herapp/settings.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await settings.load();
  });

  testWidgets('send then streamed reply', (t) async {
    await t.pumpWidget(const App());
    expect(find.text('How can I help?'), findsOneWidget);

    await t.enterText(find.byType(EditableText).last, 'Salut');
    await t.pumpAndSettle(); // let the send icon animation finish
    await t.tap(find.byIcon(CupertinoIcons.arrow_up));
    await t.pump();
    expect(find.text('Salut'), findsWidgets);

    await t.pump(const Duration(seconds: 10));
    await t.pump(const Duration(seconds: 1));
    expect(find.textContaining('Got it'), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.arrow_2_circlepath), findsOneWidget);
  });

  testWidgets('server models can be picked while the chat is empty', (t) async {
    settings.url = 'https://hermes.test';
    addTearDown(() => fetchModels = hermesModels);
    fetchModels = (base, {user, password}) async => (
      models: <Model>[
        (provider: 'Anthropic', name: 'claude-sonnet-5-5', id: 'anthropic/claude-sonnet-5-5'),
        (provider: 'OpenRouter', name: 'openai/gpt-5', id: 'openrouter/openai/gpt-5'),
      ],
      current: 'anthropic/claude-sonnet-5-5',
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
    expect(find.textContaining('(openai/gpt-5)'), findsOneWidget);
    expect(find.text('openai/gpt-5'), findsOneWidget); // title shown, pill gone
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
