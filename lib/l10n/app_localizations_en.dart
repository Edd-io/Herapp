// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get newChat => 'New chat';

  @override
  String get emptyHeadline => 'How can I help?';

  @override
  String get composerHint => 'Ask anything';

  @override
  String get search => 'Search';

  @override
  String get chats => 'Chats';

  @override
  String get settings => 'Settings';

  @override
  String get model => 'Model';

  @override
  String get done => 'Done';

  @override
  String get appearance => 'Appearance';

  @override
  String get themeSystem => 'System';

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';

  @override
  String get general => 'General';

  @override
  String get haptics => 'Haptic feedback';

  @override
  String get hermesServer => 'Hermes server';

  @override
  String get hermesServerFooter => 'Address the app will send messages to.';

  @override
  String get wireguard => 'WireGuard';

  @override
  String get wgConfig => 'Configuration';

  @override
  String get wgImport => 'Import';

  @override
  String get wgUse => 'Route through WireGuard';

  @override
  String get wgConnected => 'Connected';

  @override
  String get wgConnecting => 'Connecting…';

  @override
  String wgError(String message) {
    return 'Error: $message';
  }

  @override
  String get wgUnavailable => 'Not available on this platform';

  @override
  String get wgRemove => 'Remove configuration';

  @override
  String get wgFooter =>
      'All of the app\'s network traffic goes through the tunnel. If the tunnel is on but down, the app can\'t communicate.';

  @override
  String get wgInvalidFile => 'This file isn\'t a WireGuard configuration.';

  @override
  String get serverTest => 'Test connection';

  @override
  String serverReachable(int status, int ms) {
    return 'Reachable · HTTP $status · $ms ms';
  }

  @override
  String serverUnreachable(String message) {
    return 'Unreachable: $message';
  }

  @override
  String get serverInvalidUrl => 'Invalid address';

  @override
  String get serverBlocked => 'Blocked: the WireGuard tunnel isn\'t connected';

  @override
  String get serverTimeout => 'no response after 15 s';

  @override
  String get viaWireguard => 'via WireGuard';
}
