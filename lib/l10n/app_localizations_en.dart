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

  @override
  String serverHermes(String version, int ms) {
    return 'Hermes $version · $ms ms';
  }

  @override
  String serverNotHermes(int status) {
    return 'Reachable, but not a Hermes server (HTTP $status)';
  }

  @override
  String get hermesAuth => 'Authentication';

  @override
  String get hermesUser => 'Username';

  @override
  String get hermesPassword => 'Password';

  @override
  String serverAuthRequired(String version) {
    return 'Hermes $version · sign-in required, turn on authentication';
  }

  @override
  String serverAuthRejected(String version) {
    return 'Hermes $version · credentials rejected';
  }

  @override
  String serverAuthOk(String version, int ms) {
    return 'Hermes $version · signed in · $ms ms';
  }

  @override
  String serverAuthRateLimited(String version) {
    return 'Hermes $version · too many attempts, try again later';
  }

  @override
  String serverAuthFailed(String version, int status) {
    return 'Hermes $version · sign-in failed (HTTP $status)';
  }

  @override
  String get serverTunnelFailed =>
      'the WireGuard tunnel can\'t reach the server';

  @override
  String get modelsNone => 'No model is configured on the server.';

  @override
  String contextUsage(int percent) {
    return 'Context: $percent% used';
  }

  @override
  String get serverNotSet => 'Set your Hermes server address in Settings.';

  @override
  String get serverRestart =>
      'Hermes was updated but is still running the old version. Restart the Hermes server.';

  @override
  String serverLoadFailed(String message) {
    return 'Couldn\'t reach the Hermes server.\n$message';
  }

  @override
  String get quotas => 'Quotas';

  @override
  String get quotaNoData => 'No quota data';

  @override
  String get quotaLimited => 'Rate-limited';

  @override
  String quotaLimitedUntil(String time) {
    return 'Rate-limited, back in $time';
  }

  @override
  String quotaResets(String time) {
    return 'Resets in $time';
  }

  @override
  String durationDays(int days, int hours) {
    return '${days}d ${hours}h';
  }

  @override
  String durationHours(int hours, int minutes) {
    return '${hours}h ${minutes}min';
  }

  @override
  String durationMinutes(int minutes) {
    return '$minutes min';
  }

  @override
  String get quotaFooter =>
      'Usage reported by Hermes for subscription providers. Pull down to refresh.';

  @override
  String get deleteChat => 'Delete chat';

  @override
  String get deleteChatMessage =>
      'This chat will be deleted from Hermes for good.';

  @override
  String get cancel => 'Cancel';

  @override
  String deleteFailed(String message) {
    return 'Couldn\'t delete the chat.\n$message';
  }

  @override
  String get cron => 'Scheduled jobs';

  @override
  String get cronEmpty => 'No scheduled jobs.';

  @override
  String cronNext(String time) {
    return 'Next run in $time';
  }

  @override
  String cronLast(String time) {
    return 'Last run $time ago';
  }

  @override
  String cronLastFailed(String error) {
    return 'Last run failed: $error';
  }

  @override
  String get cronCompleted => 'Done';

  @override
  String get cronRunning => 'Running…';

  @override
  String get cronRunNow => 'Run now';

  @override
  String cronStarted(String name) {
    return '“$name” started';
  }

  @override
  String cronActionFailed(String message) {
    return 'Couldn\'t update the job.\n$message';
  }

  @override
  String get cronFooter => 'Jobs Hermes runs on its own. Pull down to refresh.';

  @override
  String get cronNew => 'New job';

  @override
  String get cronEdit => 'Edit job';

  @override
  String get cronSave => 'Save';

  @override
  String get cronGeneral => 'General';

  @override
  String get cronName => 'Name';

  @override
  String get cronSchedule => 'Schedule';

  @override
  String get cronScheduleHint =>
      '0 9 * * *, every 30m, every monday 9am, or a date like 2026-11-02T08:00';

  @override
  String get cronRepeat => 'Repeat';

  @override
  String get cronRepeatHint => 'forever, once or a number';

  @override
  String cronRepeatDone(int count) {
    return '$count runs so far';
  }

  @override
  String get cronTask => 'Task';

  @override
  String get cronPrompt => 'Prompt';

  @override
  String get cronScript => 'Script';

  @override
  String get cronScriptHint => 'Name of a script in the cron scripts folder';

  @override
  String get cronNoAgent => 'Script only, no AI';

  @override
  String get cronSkills => 'Skills';

  @override
  String get cronListHint => 'Comma-separated';

  @override
  String get cronModelSection => 'Model';

  @override
  String get cronModel => 'Model';

  @override
  String get cronProvider => 'Provider';

  @override
  String get cronBaseUrl => 'Base URL';

  @override
  String get cronServerDefault => 'Server default';

  @override
  String get cronDelivery => 'Delivery';

  @override
  String get cronDeliver => 'Deliver to';

  @override
  String get cronFailureDeliver => 'On failure, deliver to';

  @override
  String get cronFailureHint => 'Same as above';

  @override
  String get cronAdvanced => 'Advanced';

  @override
  String get cronWorkdir => 'Working directory';

  @override
  String get cronToolsets => 'Toolsets';

  @override
  String get cronContextFrom => 'Context from jobs';

  @override
  String get cronContextHint =>
      'Job ids whose latest output is given to this one';

  @override
  String get cronDelete => 'Delete job';

  @override
  String get cronDeleteMessage =>
      'This job will be deleted from Hermes for good.';
}
