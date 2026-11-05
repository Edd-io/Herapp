import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'chat_page.dart';
import 'firebase_options.dart';
import 'l10n/app_localizations.dart';
import 'lock.dart';
import 'notifications_page.dart';
import 'settings.dart';
import 'wireguard.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // out of the sandbox (to run commands), the Mac app reads its preferences outside the container it kept them in
  if (Platform.isMacOS) {
    const id = 'com.edd-io.herapp';
    final home = Platform.environment['HOME'];
    final kept = File('$home/Library/Containers/$id/Data/Library/Preferences/$id.plist');
    if (kept.existsSync() && !File('$home/Library/Preferences/$id.plist').existsSync()) {
      await Process.run('defaults', ['import', id, kept.path]);
    }
  }
  await settings.load();
  await vpn.load();
  runApp(const App());
  if (Platform.isIOS || Platform.isAndroid) setupPush();
}

/// Asks for notification permission and returns this device's FCM token, or null if refused.
Future<String?> setupPush() async {
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    final m = FirebaseMessaging.instance;
    final s = await m.requestPermission();
    if (s.authorizationStatus == AuthorizationStatus.denied) return null;
    // cron results also show while the app is open
    await m.setForegroundNotificationPresentationOptions(alert: true, badge: true, sound: true);
    // FCM gives no token before iOS has handed over the APNs one
    if (Platform.isIOS) {
      for (var i = 0; i < 20 && await m.getAPNSToken() == null; i++) {
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }
    // register()'s installation id fails with invalid-request on iOS, the deprecated token works
    // ignore: deprecated_member_use
    final token = await m.getToken();
    debugPrint('FCM token: $token');
    // the server's cron watcher (server/herapp-push.py) sends to this topic
    await m.subscribeToTopic('herapp-crons');
    // a tapped push opens its notice: while the app runs in the background, or the one that started it
    FirebaseMessaging.onMessageOpenedApp.listen(openPushed);
    // one more to read, until the next count from the server
    FirebaseMessaging.onMessage.listen((_) => unreadNotices.value++);
    if (await m.getInitialMessage() case final first?) openPushed(first);
    return token;
  } catch (e) {
    debugPrint('push setup failed: $e');
    return null;
  }
}

/// The notice [message] names (server/herapp-push.py sends its id), opened by the chat page.
void openPushed(RemoteMessage message) => openedNotice.value = message.data['notice'] as String? ?? '';

class App extends StatelessWidget {
  const App({super.key});

  static ThemeData _theme(ColorScheme c) {
    // the accent takes the neutral primary's place, with readable text on it
    if (settings.accent case final a when a != 0) {
      // deepened until white text reads on it (WCAG 4.5:1), which a light accent's black text did poorly
      var accent = Color(a);
      for (var t = .05; contrast(Colors.white, accent) < 4.5 && t < 1; t += .05) {
        accent = Color.lerp(Color(a), Colors.black, t)!;
      }
      c = c.copyWith(primary: accent, onPrimary: Colors.white);
    }
    return ThemeData(
      colorScheme: c,
      scaffoldBackgroundColor: c.surface,
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      // a picked accent also colors what is switched on, in place of the green of the switches
      cupertinoOverrideTheme: settings.accent == 0 ? null : const CupertinoThemeData(applyThemeToAll: true),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: settings.accent == 0 ? c.onSurface : c.primary,
        selectionColor: settings.accent == 0 ? null : c.primary.withValues(alpha: .3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: settings,
    builder: (context, _) => MaterialApp(
      title: 'Herapp',
      debugShowCheckedModeBanner: false,
      themeMode: settings.theme,
      locale: settings.language.isEmpty ? null : Locale(settings.language),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      // surface = background, surfaceContainerHighest = bubbles/composer, surfaceContainerLow = sidebar
      theme: _theme(
        const ColorScheme.light(
          surface: Colors.white,
          onSurface: Color(0xFF0D0D0D),
          surfaceContainerHighest: Color(0xFFF4F4F4),
          surfaceContainerLow: Color(0xFFF9F9F9),
          onSurfaceVariant: Color(0xFF5D5D5D),
          outline: Color(0xFF6E6E6E), // 4.5:1 at least on every light surface, for the small grey text
          primary: Color(0xFF0D0D0D),
          onPrimary: Colors.white,
        ),
      ),
      darkTheme: _theme(
        const ColorScheme.dark(
          surface: Color(0xFF212121),
          onSurface: Color(0xFFECECEC),
          surfaceContainerHighest: Color(0xFF303030),
          surfaceContainerLow: Color(0xFF171717),
          onSurfaceVariant: Color(0xFFB4B4B4),
          outline: Color(0xFFAFAFAF),
          primary: Colors.white,
          onPrimary: Colors.black,
        ),
      ),
      // sizes are set for a phone held close; a computer screen sits further away and its UI runs smaller.
      // A window has no safe area: an inset of its own keeps the content off its edges, through every SafeArea.
      builder: (context, child) {
        if (!(Platform.isMacOS || Platform.isWindows || Platform.isLinux)) return AppLock(child: ConnectionBanner(child: child!));
        // the Mac window draws under its title bar: the content starts below the traffic lights
        final edges = EdgeInsets.fromLTRB(4, Platform.isMacOS ? 30 : 12, 12, 16);
        return AppLock(
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(.9), padding: edges, viewPadding: edges),
            child: ConnectionBanner(child: child!),
          ),
        );
      },
      home: const ChatPage(),
    ),
  );
}
