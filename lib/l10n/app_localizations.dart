import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_fr.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('fr'),
  ];

  /// No description provided for @newChat.
  ///
  /// In en, this message translates to:
  /// **'New chat'**
  String get newChat;

  /// No description provided for @emptyHeadline.
  ///
  /// In en, this message translates to:
  /// **'How can I help?'**
  String get emptyHeadline;

  /// No description provided for @composerHint.
  ///
  /// In en, this message translates to:
  /// **'Ask anything'**
  String get composerHint;

  /// No description provided for @search.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get search;

  /// No description provided for @chats.
  ///
  /// In en, this message translates to:
  /// **'Chats'**
  String get chats;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @model.
  ///
  /// In en, this message translates to:
  /// **'Model'**
  String get model;

  /// No description provided for @done.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// No description provided for @appearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get appearance;

  /// No description provided for @themeSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get themeSystem;

  /// No description provided for @themeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get themeLight;

  /// No description provided for @themeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get themeDark;

  /// No description provided for @general.
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get general;

  /// No description provided for @haptics.
  ///
  /// In en, this message translates to:
  /// **'Haptic feedback'**
  String get haptics;

  /// No description provided for @hermesServer.
  ///
  /// In en, this message translates to:
  /// **'Hermes server'**
  String get hermesServer;

  /// No description provided for @hermesServerFooter.
  ///
  /// In en, this message translates to:
  /// **'Address the app will send messages to.'**
  String get hermesServerFooter;

  /// No description provided for @wireguard.
  ///
  /// In en, this message translates to:
  /// **'WireGuard'**
  String get wireguard;

  /// No description provided for @wgConfig.
  ///
  /// In en, this message translates to:
  /// **'Configuration'**
  String get wgConfig;

  /// No description provided for @wgImport.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get wgImport;

  /// No description provided for @wgUse.
  ///
  /// In en, this message translates to:
  /// **'Route through WireGuard'**
  String get wgUse;

  /// No description provided for @wgConnected.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get wgConnected;

  /// No description provided for @wgConnecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting…'**
  String get wgConnecting;

  /// No description provided for @wgError.
  ///
  /// In en, this message translates to:
  /// **'Error: {message}'**
  String wgError(String message);

  /// No description provided for @wgUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Not available on this platform'**
  String get wgUnavailable;

  /// No description provided for @wgRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove configuration'**
  String get wgRemove;

  /// No description provided for @wgFooter.
  ///
  /// In en, this message translates to:
  /// **'All of the app\'s network traffic goes through the tunnel. If the tunnel is on but down, the app can\'t communicate.'**
  String get wgFooter;

  /// No description provided for @wgInvalidFile.
  ///
  /// In en, this message translates to:
  /// **'This file isn\'t a WireGuard configuration.'**
  String get wgInvalidFile;

  /// No description provided for @serverTest.
  ///
  /// In en, this message translates to:
  /// **'Test connection'**
  String get serverTest;

  /// No description provided for @serverUnreachable.
  ///
  /// In en, this message translates to:
  /// **'Unreachable: {message}'**
  String serverUnreachable(String message);

  /// No description provided for @serverInvalidUrl.
  ///
  /// In en, this message translates to:
  /// **'Invalid address'**
  String get serverInvalidUrl;

  /// No description provided for @serverBlocked.
  ///
  /// In en, this message translates to:
  /// **'Blocked: the WireGuard tunnel isn\'t connected'**
  String get serverBlocked;

  /// No description provided for @serverTimeout.
  ///
  /// In en, this message translates to:
  /// **'no response after 15 s'**
  String get serverTimeout;

  /// No description provided for @viaWireguard.
  ///
  /// In en, this message translates to:
  /// **'via WireGuard'**
  String get viaWireguard;

  /// No description provided for @serverHermes.
  ///
  /// In en, this message translates to:
  /// **'Hermes {version} · {ms} ms'**
  String serverHermes(String version, int ms);

  /// No description provided for @serverNotHermes.
  ///
  /// In en, this message translates to:
  /// **'Reachable, but not a Hermes server (HTTP {status})'**
  String serverNotHermes(int status);

  /// No description provided for @hermesAuth.
  ///
  /// In en, this message translates to:
  /// **'Authentication'**
  String get hermesAuth;

  /// No description provided for @hermesUser.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get hermesUser;

  /// No description provided for @hermesPassword.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get hermesPassword;

  /// No description provided for @serverAuthRequired.
  ///
  /// In en, this message translates to:
  /// **'Hermes {version} · sign-in required, turn on authentication'**
  String serverAuthRequired(String version);

  /// No description provided for @serverAuthRejected.
  ///
  /// In en, this message translates to:
  /// **'Hermes {version} · credentials rejected'**
  String serverAuthRejected(String version);

  /// No description provided for @serverAuthOk.
  ///
  /// In en, this message translates to:
  /// **'Hermes {version} · signed in · {ms} ms'**
  String serverAuthOk(String version, int ms);

  /// No description provided for @serverAuthRateLimited.
  ///
  /// In en, this message translates to:
  /// **'Hermes {version} · too many attempts, try again later'**
  String serverAuthRateLimited(String version);

  /// No description provided for @serverAuthFailed.
  ///
  /// In en, this message translates to:
  /// **'Hermes {version} · sign-in failed (HTTP {status})'**
  String serverAuthFailed(String version, int status);

  /// No description provided for @serverTunnelFailed.
  ///
  /// In en, this message translates to:
  /// **'the WireGuard tunnel can\'t reach the server'**
  String get serverTunnelFailed;

  /// No description provided for @modelsNone.
  ///
  /// In en, this message translates to:
  /// **'No model is configured on the server.'**
  String get modelsNone;

  /// No description provided for @contextUsage.
  ///
  /// In en, this message translates to:
  /// **'Context: {percent}% used'**
  String contextUsage(int percent);

  /// No description provided for @serverNotSet.
  ///
  /// In en, this message translates to:
  /// **'Set your Hermes server address in Settings.'**
  String get serverNotSet;

  /// No description provided for @serverRestart.
  ///
  /// In en, this message translates to:
  /// **'Hermes was updated but is still running the old version. Restart the Hermes server.'**
  String get serverRestart;

  /// No description provided for @serverLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t reach the Hermes server.\n{message}'**
  String serverLoadFailed(String message);

  /// No description provided for @quotas.
  ///
  /// In en, this message translates to:
  /// **'Quotas'**
  String get quotas;

  /// No description provided for @quotaNoData.
  ///
  /// In en, this message translates to:
  /// **'No quota data'**
  String get quotaNoData;

  /// No description provided for @quotaLimited.
  ///
  /// In en, this message translates to:
  /// **'Rate-limited'**
  String get quotaLimited;

  /// No description provided for @quotaLimitedUntil.
  ///
  /// In en, this message translates to:
  /// **'Rate-limited, back in {time}'**
  String quotaLimitedUntil(String time);

  /// No description provided for @quotaResets.
  ///
  /// In en, this message translates to:
  /// **'Resets in {time}'**
  String quotaResets(String time);

  /// No description provided for @durationDays.
  ///
  /// In en, this message translates to:
  /// **'{days}d {hours}h'**
  String durationDays(int days, int hours);

  /// No description provided for @durationHours.
  ///
  /// In en, this message translates to:
  /// **'{hours}h {minutes}min'**
  String durationHours(int hours, int minutes);

  /// No description provided for @durationMinutes.
  ///
  /// In en, this message translates to:
  /// **'{minutes} min'**
  String durationMinutes(int minutes);

  /// No description provided for @quotaFooter.
  ///
  /// In en, this message translates to:
  /// **'Usage reported by Hermes for subscription providers. Pull down to refresh.'**
  String get quotaFooter;

  /// No description provided for @deleteChat.
  ///
  /// In en, this message translates to:
  /// **'Delete chat'**
  String get deleteChat;

  /// No description provided for @deleteChatMessage.
  ///
  /// In en, this message translates to:
  /// **'This chat will be deleted from Hermes for good.'**
  String get deleteChatMessage;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @deleteFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t delete the chat.\n{message}'**
  String deleteFailed(String message);

  /// No description provided for @cron.
  ///
  /// In en, this message translates to:
  /// **'Scheduled jobs'**
  String get cron;

  /// No description provided for @cronEmpty.
  ///
  /// In en, this message translates to:
  /// **'No scheduled jobs.'**
  String get cronEmpty;

  /// No description provided for @cronNext.
  ///
  /// In en, this message translates to:
  /// **'Next run in {time}'**
  String cronNext(String time);

  /// No description provided for @cronLast.
  ///
  /// In en, this message translates to:
  /// **'Last run {time} ago'**
  String cronLast(String time);

  /// No description provided for @cronLastFailed.
  ///
  /// In en, this message translates to:
  /// **'Last run failed: {error}'**
  String cronLastFailed(String error);

  /// No description provided for @cronCompleted.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get cronCompleted;

  /// No description provided for @cronRunning.
  ///
  /// In en, this message translates to:
  /// **'Running…'**
  String get cronRunning;

  /// No description provided for @cronRunNow.
  ///
  /// In en, this message translates to:
  /// **'Run now'**
  String get cronRunNow;

  /// No description provided for @cronStarted.
  ///
  /// In en, this message translates to:
  /// **'“{name}” started'**
  String cronStarted(String name);

  /// No description provided for @cronActionFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t update the job.\n{message}'**
  String cronActionFailed(String message);

  /// No description provided for @cronFooter.
  ///
  /// In en, this message translates to:
  /// **'Jobs Hermes runs on its own. Pull down to refresh.'**
  String get cronFooter;

  /// No description provided for @cronNew.
  ///
  /// In en, this message translates to:
  /// **'New job'**
  String get cronNew;

  /// No description provided for @cronEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit job'**
  String get cronEdit;

  /// No description provided for @cronSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get cronSave;

  /// No description provided for @cronGeneral.
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get cronGeneral;

  /// No description provided for @cronName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get cronName;

  /// No description provided for @cronSchedule.
  ///
  /// In en, this message translates to:
  /// **'Schedule'**
  String get cronSchedule;

  /// No description provided for @cronScheduleHint.
  ///
  /// In en, this message translates to:
  /// **'0 9 * * *, every 30m, every monday 9am, or a date like 2026-11-02T08:00'**
  String get cronScheduleHint;

  /// No description provided for @cronRepeat.
  ///
  /// In en, this message translates to:
  /// **'Repeat'**
  String get cronRepeat;

  /// No description provided for @cronRepeatHint.
  ///
  /// In en, this message translates to:
  /// **'forever, once or a number'**
  String get cronRepeatHint;

  /// No description provided for @cronRepeatDone.
  ///
  /// In en, this message translates to:
  /// **'{count} runs so far'**
  String cronRepeatDone(int count);

  /// No description provided for @cronTask.
  ///
  /// In en, this message translates to:
  /// **'Task'**
  String get cronTask;

  /// No description provided for @cronPrompt.
  ///
  /// In en, this message translates to:
  /// **'Prompt'**
  String get cronPrompt;

  /// No description provided for @cronScript.
  ///
  /// In en, this message translates to:
  /// **'Script'**
  String get cronScript;

  /// No description provided for @cronScriptHint.
  ///
  /// In en, this message translates to:
  /// **'Name of a script in the cron scripts folder'**
  String get cronScriptHint;

  /// No description provided for @cronNoAgent.
  ///
  /// In en, this message translates to:
  /// **'Script only, no AI'**
  String get cronNoAgent;

  /// No description provided for @cronSkills.
  ///
  /// In en, this message translates to:
  /// **'Skills'**
  String get cronSkills;

  /// No description provided for @cronListHint.
  ///
  /// In en, this message translates to:
  /// **'Comma-separated'**
  String get cronListHint;

  /// No description provided for @cronModelSection.
  ///
  /// In en, this message translates to:
  /// **'Model'**
  String get cronModelSection;

  /// No description provided for @cronModel.
  ///
  /// In en, this message translates to:
  /// **'Model'**
  String get cronModel;

  /// No description provided for @cronProvider.
  ///
  /// In en, this message translates to:
  /// **'Provider'**
  String get cronProvider;

  /// No description provided for @cronBaseUrl.
  ///
  /// In en, this message translates to:
  /// **'Base URL'**
  String get cronBaseUrl;

  /// No description provided for @cronServerDefault.
  ///
  /// In en, this message translates to:
  /// **'Server default'**
  String get cronServerDefault;

  /// No description provided for @cronDelivery.
  ///
  /// In en, this message translates to:
  /// **'Delivery'**
  String get cronDelivery;

  /// No description provided for @cronDeliver.
  ///
  /// In en, this message translates to:
  /// **'Deliver to'**
  String get cronDeliver;

  /// No description provided for @cronFailureDeliver.
  ///
  /// In en, this message translates to:
  /// **'On failure, deliver to'**
  String get cronFailureDeliver;

  /// No description provided for @cronFailureHint.
  ///
  /// In en, this message translates to:
  /// **'Same as above'**
  String get cronFailureHint;

  /// No description provided for @cronAdvanced.
  ///
  /// In en, this message translates to:
  /// **'Advanced'**
  String get cronAdvanced;

  /// No description provided for @cronWorkdir.
  ///
  /// In en, this message translates to:
  /// **'Working directory'**
  String get cronWorkdir;

  /// No description provided for @cronToolsets.
  ///
  /// In en, this message translates to:
  /// **'Toolsets'**
  String get cronToolsets;

  /// No description provided for @cronContextFrom.
  ///
  /// In en, this message translates to:
  /// **'Context from jobs'**
  String get cronContextFrom;

  /// No description provided for @cronContextHint.
  ///
  /// In en, this message translates to:
  /// **'Job ids whose latest output is given to this one'**
  String get cronContextHint;

  /// No description provided for @cronDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete job'**
  String get cronDelete;

  /// No description provided for @cronDeleteMessage.
  ///
  /// In en, this message translates to:
  /// **'This job will be deleted from Hermes for good.'**
  String get cronDeleteMessage;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'fr'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'fr':
      return AppLocalizationsFr();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
