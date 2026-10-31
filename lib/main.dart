import 'dart:io';

import 'package:flutter/material.dart';

import 'chat_page.dart';
import 'l10n/app_localizations.dart';
import 'settings.dart';
import 'wireguard.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await settings.load();
  await vpn.load();
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});

  static ThemeData _theme(ColorScheme c) => ThemeData(
    colorScheme: c,
    scaffoldBackgroundColor: c.surface,
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    textSelectionTheme: TextSelectionThemeData(cursorColor: c.onSurface),
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: settings,
    builder: (context, _) => MaterialApp(
      title: 'Hermes',
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
          outline: Color(0xFF8F8F8F),
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
      builder: Platform.isMacOS || Platform.isWindows || Platform.isLinux
          ? (context, child) {
              const edges = EdgeInsets.fromLTRB(4, 12, 12, 16);
              return MediaQuery(
                data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(.9), padding: edges, viewPadding: edges),
                child: child!,
              );
            }
          : null,
      home: const ChatPage(),
    ),
  );
}
