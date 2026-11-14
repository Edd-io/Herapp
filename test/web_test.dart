@TestOn('browser')
library;

import 'dart:convert';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herapp/hermes.dart';
import 'package:herapp/mac.dart';
import 'package:herapp/l10n/app_localizations.dart';
import 'package:herapp/main.dart';
import 'package:herapp/network.dart';
import 'package:herapp/settings.dart';
import 'package:herapp/wireguard.dart';

import 'support.dart';

void main() {
  final base = Uri.parse('http://localhost:8766');
  setUp(forgetSignIns);

  test('browser keeps HttpOnly login cookies, shares sign-in and renews an expired session', () async {
    final client = createNetworkClient();
    addTearDown(client.close);
    final first = await hermesModels(base, user: 'web', password: 'correct');
    expect(first.current, 'p/m');
    final before = jsonDecode((await client.request('GET', base.resolve('/test/stats'))).body) as Map;
    await hermesModels(base, user: 'web', password: 'correct');
    final kept = jsonDecode((await client.request('GET', base.resolve('/test/stats'))).body) as Map;
    expect(kept, before);
    await client.request('POST', base.resolve('/test/expire'));
    expect((await hermesModels(base, user: 'web', password: 'correct')).current, 'p/m');
    final renewed = jsonDecode((await client.request('GET', base.resolve('/test/stats'))).body) as Map;
    expect(renewed['session'], (before['session'] as int) + 2);
    expect((await hermesLogin(client, base, 'web', 'wrong')).status, 401);
  });

  test('browser opens a ticketed gateway and receives streamed events', () async {
    final g = await hermesGateway(base, user: 'web', password: 'correct');
    addTearDown(g.close);
    final event = g.events.first;
    expect(parseSessions(await g.call('session.list')), isEmpty);
    expect((await event).payload['text'], 'Bonjour');
  });

  test('loopback token authentication works for REST and WebSockets', () async {
    final tokenBase = base.resolve('/token/');
    expect((await hermesModels(tokenBase)).current, 'p/m');
    final g = await hermesGateway(tokenBase);
    addTearDown(g.close);
    expect(parseSessions(await g.call('session.list')), isEmpty);
  });

  test('browser reuses an existing HttpOnly session without app credentials', () async {
    final client = createNetworkClient();
    addTearDown(client.close);
    expect((await hermesLogin(client, base, 'web', 'correct')).ok, isTrue);
    final g = await hermesGateway(base);
    addTearDown(g.close);
    expect(parseSessions(await g.call('session.list')), isEmpty);
  });

  test('failed WebSockets report an unreachable server', () async {
    await expectLater(
      openNetworkSocket(base.replace(scheme: 'ws', path: '/missing')),
      throwsA(isA<NetworkException>().having(unreachable, 'unreachable', isTrue)),
    );
  });

  test('display WebSocket delivers binary frames as bytes', () async {
    final socket = await openNetworkSocket(base.replace(scheme: 'ws', path: '/binary'));
    addTearDown(socket.close);
    final frame = socket.stream.first;
    socket.add(Uint8List.fromList([82, 70, 66, 10]));
    expect(await frame, [82, 70, 66, 10]);
  });

  group('web application', () {
    resetApp();

    testWidgets('a Mac browser streams chat, keeps keyboard UI and hides native settings', (t) async {
      stillStripes(t);
      fakeServer(replies);
      fetchModels = (base, {user, password}) async => (models: <Model>[], current: '', quotas: <Quota>[]);
      addTearDown(() => fetchModels = hermesModels);
      callApi = (base, method, path, {query, body, user, password}) async => '{}';
      addTearDown(() => callApi = hermesApi);
      await vpn.load();
      expect((vpn.enabled, macCapable), (false, false));
      await t.pumpWidget(const App());
      await t.pumpAndSettle();
      expect(find.byType(PlatformMenuBar), findsNothing);
      await t.sendKeyDownEvent(LogicalKeyboardKey.meta);
      await t.sendKeyEvent(LogicalKeyboardKey.keyK);
      await t.sendKeyUpEvent(LogicalKeyboardKey.meta);
      await t.pumpAndSettle();
      expect(find.text('A command, a page or a chat'), findsOneWidget);
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pumpAndSettle();
      final drop = t.widget<DropTarget>(find.byType(DropTarget));
      await t.runAsync(() async {
        drop.onDragDone!(
          DropDoneDetails(
            localPosition: Offset.zero,
            globalPosition: Offset.zero,
            files: [DropItemFile.fromData(Uint8List.fromList(utf8.encode('notes')), name: 'notes.txt')],
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await t.pumpAndSettle();
      expect(find.text('notes.txt'), findsOneWidget);
      await t.enterText(find.byType(EditableText).last, 'Bonjour');
      await t.pumpAndSettle();
      await t.tap(find.byIcon(CupertinoIcons.arrow_up));
      await t.pump(const Duration(seconds: 10));
      await t.pump(const Duration(seconds: 1));
      expect(find.text('Hello there'), findsOneWidget);
      await t.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: SettingsSheet()),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('WireGuard'), findsNothing);
      expect(find.text('Commands on this computer'), findsNothing);
      expect(find.text('Lock the app'), findsNothing);
      expect(find.text('Notifications'), findsNothing);
    }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
  });
}
