import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herapp/main.dart';
import 'package:herapp/settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await settings.load();
  });

  testWidgets('envoi puis réponse en flux', (t) async {
    await t.pumpWidget(const App());
    expect(find.text('Par quoi commençons-nous ?'), findsOneWidget);

    await t.enterText(find.byType(EditableText).last, 'Salut');
    await t.pumpAndSettle(); // laisse finir l'animation de l'icône d'envoi
    await t.tap(find.byIcon(CupertinoIcons.arrow_up));
    await t.pump();
    expect(find.text('Salut'), findsWidgets);

    await t.pump(const Duration(seconds: 10));
    await t.pump(const Duration(seconds: 1));
    expect(find.textContaining('Bien reçu'), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.arrow_2_circlepath), findsOneWidget);
  });

  testWidgets('choix du modèle tant que la conversation est vide', (t) async {
    await t.pumpWidget(const App());
    await t.tap(find.text('Anthropic')); // pastille sous le titre
    await t.pumpAndSettle();
    await t.tap(find.text('GPT-5').last);
    await t.pumpAndSettle();
    expect(settings.model, 'openai/gpt-5');
    expect(find.text('OpenAI'), findsOneWidget);

    await t.enterText(find.byType(EditableText).last, 'Salut');
    await t.pumpAndSettle();
    await t.tap(find.byIcon(CupertinoIcons.arrow_up));
    await t.pump(const Duration(seconds: 10));
    expect(find.textContaining('(GPT-5)'), findsOneWidget);
    expect(find.text('GPT-5'), findsOneWidget); // titre affiché, pastille disparue
  });

  testWidgets('les réglages changent le thème et sont persistés', (t) async {
    await t.pumpWidget(const App());
    await t.tapAt(const Offset(30, 50)); // icône menu
    await t.pumpAndSettle();
    await t.tap(find.text('Paramètres'));
    await t.pumpAndSettle();

    await t.tap(find.text('Sombre'));
    await t.pumpAndSettle();
    expect(settings.theme, ThemeMode.dark);
    expect(t.widget<MaterialApp>(find.byType(MaterialApp)).themeMode, ThemeMode.dark);

    await settings.load();
    expect(settings.theme, ThemeMode.dark);
  });
}
