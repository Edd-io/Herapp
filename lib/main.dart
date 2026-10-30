import 'package:flutter/material.dart';

import 'chat_page.dart';
import 'settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await settings.load();
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
      // surface = fond, surfaceContainerHighest = bulles/composer, surfaceContainerLow = sidebar
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
      home: const ChatPage(),
    ),
  );
}
