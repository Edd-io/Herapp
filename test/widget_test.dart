import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herapp/main.dart';

void main() {
  testWidgets('envoi puis réponse en flux', (t) async {
    await t.pumpWidget(const App());
    expect(find.text('Par quoi commençons-nous ?'), findsOneWidget);

    await t.enterText(find.byType(EditableText).last, 'Salut');
    await t.pump();
    await t.tap(find.byIcon(CupertinoIcons.arrow_up));
    await t.pump();
    expect(find.text('Salut'), findsWidgets);

    await t.pump(const Duration(seconds: 10));
    await t.pump(const Duration(seconds: 1));
    expect(find.textContaining('Bien reçu'), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.arrow_2_circlepath), findsOneWidget);
  });
}
