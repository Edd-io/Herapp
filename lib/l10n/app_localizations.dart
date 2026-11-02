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

  /// No description provided for @statusThinking.
  ///
  /// In en, this message translates to:
  /// **'Thinking…'**
  String get statusThinking;

  /// No description provided for @statusWriting.
  ///
  /// In en, this message translates to:
  /// **'Writing…'**
  String get statusWriting;

  /// No description provided for @statusTool.
  ///
  /// In en, this message translates to:
  /// **'Using {tool}…'**
  String statusTool(String tool);

  /// No description provided for @composerQueueHint.
  ///
  /// In en, this message translates to:
  /// **'Queue a message'**
  String get composerQueueHint;

  /// No description provided for @queued.
  ///
  /// In en, this message translates to:
  /// **'Queued · tap to edit'**
  String get queued;

  /// No description provided for @editingMessage.
  ///
  /// In en, this message translates to:
  /// **'Editing message · sent in its place'**
  String get editingMessage;

  /// No description provided for @memoryUpdated.
  ///
  /// In en, this message translates to:
  /// **'Memory updated'**
  String get memoryUpdated;

  /// No description provided for @routineResult.
  ///
  /// In en, this message translates to:
  /// **'Routine · {job}'**
  String routineResult(String job);

  /// No description provided for @system.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get system;

  /// No description provided for @systemServer.
  ///
  /// In en, this message translates to:
  /// **'Server'**
  String get systemServer;

  /// No description provided for @systemVersion.
  ///
  /// In en, this message translates to:
  /// **'Version'**
  String get systemVersion;

  /// No description provided for @systemGateway.
  ///
  /// In en, this message translates to:
  /// **'Gateway'**
  String get systemGateway;

  /// No description provided for @systemRunning.
  ///
  /// In en, this message translates to:
  /// **'Running'**
  String get systemRunning;

  /// No description provided for @systemStopped.
  ///
  /// In en, this message translates to:
  /// **'Stopped'**
  String get systemStopped;

  /// No description provided for @systemHealth.
  ///
  /// In en, this message translates to:
  /// **'Health'**
  String get systemHealth;

  /// No description provided for @systemHealthy.
  ///
  /// In en, this message translates to:
  /// **'All good'**
  String get systemHealthy;

  /// No description provided for @systemDegraded.
  ///
  /// In en, this message translates to:
  /// **'Degraded'**
  String get systemDegraded;

  /// No description provided for @systemSessions.
  ///
  /// In en, this message translates to:
  /// **'Active sessions'**
  String get systemSessions;

  /// No description provided for @systemPlatforms.
  ///
  /// In en, this message translates to:
  /// **'Messaging'**
  String get systemPlatforms;

  /// No description provided for @systemConnected.
  ///
  /// In en, this message translates to:
  /// **'{count} of {total} connected'**
  String systemConnected(int count, int total);

  /// No description provided for @systemUpdate.
  ///
  /// In en, this message translates to:
  /// **'Update'**
  String get systemUpdate;

  /// No description provided for @systemUpToDate.
  ///
  /// In en, this message translates to:
  /// **'Hermes is up to date.'**
  String get systemUpToDate;

  /// No description provided for @systemUpdateReady.
  ///
  /// In en, this message translates to:
  /// **'Update available'**
  String get systemUpdateReady;

  /// No description provided for @systemChanges.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 change} other{{count} changes}}'**
  String systemChanges(int count);

  /// No description provided for @systemUpdateNow.
  ///
  /// In en, this message translates to:
  /// **'Update now'**
  String get systemUpdateNow;

  /// No description provided for @systemUpdateConfirm.
  ///
  /// In en, this message translates to:
  /// **'Hermes will update and restart. Replies in progress will stop.'**
  String get systemUpdateConfirm;

  /// No description provided for @systemUpdating.
  ///
  /// In en, this message translates to:
  /// **'Updating…'**
  String get systemUpdating;

  /// No description provided for @systemUpdated.
  ///
  /// In en, this message translates to:
  /// **'Update done.'**
  String get systemUpdated;

  /// No description provided for @systemRestart.
  ///
  /// In en, this message translates to:
  /// **'Restart the gateway'**
  String get systemRestart;

  /// No description provided for @systemRestartConfirm.
  ///
  /// In en, this message translates to:
  /// **'Replies in progress will stop.'**
  String get systemRestartConfirm;

  /// No description provided for @systemRestarting.
  ///
  /// In en, this message translates to:
  /// **'The gateway is restarting.'**
  String get systemRestarting;

  /// No description provided for @systemFailed.
  ///
  /// In en, this message translates to:
  /// **'It didn\'t work: {reason}'**
  String systemFailed(String reason);

  /// No description provided for @lockApp.
  ///
  /// In en, this message translates to:
  /// **'Lock the app'**
  String get lockApp;

  /// No description provided for @unlock.
  ///
  /// In en, this message translates to:
  /// **'Unlock'**
  String get unlock;

  /// No description provided for @unlockReason.
  ///
  /// In en, this message translates to:
  /// **'Unlock Hermes'**
  String get unlockReason;

  /// No description provided for @dropFiles.
  ///
  /// In en, this message translates to:
  /// **'Drop to attach to your message'**
  String get dropFiles;

  /// No description provided for @menuFile.
  ///
  /// In en, this message translates to:
  /// **'File'**
  String get menuFile;

  /// No description provided for @menuView.
  ///
  /// In en, this message translates to:
  /// **'View'**
  String get menuView;

  /// No description provided for @menuWindow.
  ///
  /// In en, this message translates to:
  /// **'Window'**
  String get menuWindow;

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

  /// No description provided for @macShell.
  ///
  /// In en, this message translates to:
  /// **'Commands on this computer'**
  String get macShell;

  /// No description provided for @macShellHint.
  ///
  /// In en, this message translates to:
  /// **'Hermes can ask from the chat to run commands here; you approve them in the app.'**
  String get macShellHint;

  /// No description provided for @macTitle.
  ///
  /// In en, this message translates to:
  /// **'On this computer'**
  String get macTitle;

  /// No description provided for @macWrite.
  ///
  /// In en, this message translates to:
  /// **'Write {path}'**
  String macWrite(String path);

  /// No description provided for @macRun.
  ///
  /// In en, this message translates to:
  /// **'Run'**
  String get macRun;

  /// No description provided for @macAlways.
  ///
  /// In en, this message translates to:
  /// **'Always in this chat'**
  String get macAlways;

  /// No description provided for @macRefuse.
  ///
  /// In en, this message translates to:
  /// **'Refuse'**
  String get macRefuse;

  /// No description provided for @macStop.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get macStop;

  /// No description provided for @macRefused.
  ///
  /// In en, this message translates to:
  /// **'Refused'**
  String get macRefused;

  /// No description provided for @macSkipped.
  ///
  /// In en, this message translates to:
  /// **'Not run'**
  String get macSkipped;

  /// No description provided for @macResults.
  ///
  /// In en, this message translates to:
  /// **'Results sent to Hermes'**
  String get macResults;

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

  /// No description provided for @chatCost.
  ///
  /// In en, this message translates to:
  /// **'Cost: {cost}'**
  String chatCost(String cost);

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

  /// No description provided for @approvalTitle.
  ///
  /// In en, this message translates to:
  /// **'Hermes wants to run a command'**
  String get approvalTitle;

  /// No description provided for @approveOnce.
  ///
  /// In en, this message translates to:
  /// **'Allow once'**
  String get approveOnce;

  /// No description provided for @approveSession.
  ///
  /// In en, this message translates to:
  /// **'For this chat'**
  String get approveSession;

  /// No description provided for @approveAlways.
  ///
  /// In en, this message translates to:
  /// **'Always'**
  String get approveAlways;

  /// No description provided for @approveDeny.
  ///
  /// In en, this message translates to:
  /// **'Deny'**
  String get approveDeny;

  /// No description provided for @toolsUsed.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 action} other{{count} actions}}'**
  String toolsUsed(int count);

  /// No description provided for @cronRuns.
  ///
  /// In en, this message translates to:
  /// **'Run history'**
  String get cronRuns;

  /// No description provided for @cronRunsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No runs yet'**
  String get cronRunsEmpty;

  /// No description provided for @cronMonitor.
  ///
  /// In en, this message translates to:
  /// **'Monitor'**
  String get cronMonitor;

  /// No description provided for @cronMonitorScript.
  ///
  /// In en, this message translates to:
  /// **'Monitor script'**
  String get cronMonitorScript;

  /// No description provided for @cronMonitorUrl.
  ///
  /// In en, this message translates to:
  /// **'Monitored URL'**
  String get cronMonitorUrl;

  /// No description provided for @cronMonitorHint.
  ///
  /// In en, this message translates to:
  /// **'Checked before each run: when its output hasn\'t changed, the AI doesn\'t run. A script or a URL, not both, and not with Script only.'**
  String get cronMonitorHint;

  /// No description provided for @ok.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get ok;

  /// No description provided for @agents.
  ///
  /// In en, this message translates to:
  /// **'Agents'**
  String get agents;

  /// No description provided for @agentNew.
  ///
  /// In en, this message translates to:
  /// **'New agent'**
  String get agentNew;

  /// No description provided for @agentsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No agents yet. An agent works on its own on a schedule, and tells you what matters.'**
  String get agentsEmpty;

  /// No description provided for @agentWorking.
  ///
  /// In en, this message translates to:
  /// **'Working on it…'**
  String get agentWorking;

  /// No description provided for @agentDone.
  ///
  /// In en, this message translates to:
  /// **'Mission complete'**
  String get agentDone;

  /// No description provided for @agentAsleep.
  ///
  /// In en, this message translates to:
  /// **'Asleep'**
  String get agentAsleep;

  /// No description provided for @agentTrouble.
  ///
  /// In en, this message translates to:
  /// **'Ran into a problem'**
  String get agentTrouble;

  /// No description provided for @agentWakesIn.
  ///
  /// In en, this message translates to:
  /// **'Wakes up in {time}'**
  String agentWakesIn(String time);

  /// No description provided for @agentIdle.
  ///
  /// In en, this message translates to:
  /// **'Ready'**
  String get agentIdle;

  /// No description provided for @agentWake.
  ///
  /// In en, this message translates to:
  /// **'Wake up now'**
  String get agentWake;

  /// No description provided for @agentSaid.
  ///
  /// In en, this message translates to:
  /// **'Last word'**
  String get agentSaid;

  /// No description provided for @agentSaidNothing.
  ///
  /// In en, this message translates to:
  /// **'Hasn\'t said anything yet.'**
  String get agentSaidNothing;

  /// No description provided for @agentMission.
  ///
  /// In en, this message translates to:
  /// **'Mission'**
  String get agentMission;

  /// No description provided for @agentRhythm.
  ///
  /// In en, this message translates to:
  /// **'Rhythm'**
  String get agentRhythm;

  /// No description provided for @agentActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get agentActive;

  /// No description provided for @agentQuiet.
  ///
  /// In en, this message translates to:
  /// **'Speaks only when it matters'**
  String get agentQuiet;

  /// No description provided for @agentTeam.
  ///
  /// In en, this message translates to:
  /// **'Listens to'**
  String get agentTeam;

  /// No description provided for @agentTeamNone.
  ///
  /// In en, this message translates to:
  /// **'No one'**
  String get agentTeamNone;

  /// No description provided for @agentTeamAlone.
  ///
  /// In en, this message translates to:
  /// **'There\'s no other agent yet.'**
  String get agentTeamAlone;

  /// No description provided for @agentSettings.
  ///
  /// In en, this message translates to:
  /// **'All settings'**
  String get agentSettings;

  /// No description provided for @agentBlank.
  ///
  /// In en, this message translates to:
  /// **'Start from scratch'**
  String get agentBlank;

  /// No description provided for @agentBlankHint.
  ///
  /// In en, this message translates to:
  /// **'Your own mission, rhythm and model'**
  String get agentBlankHint;

  /// No description provided for @agentCreate.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get agentCreate;

  /// No description provided for @vault.
  ///
  /// In en, this message translates to:
  /// **'Vault'**
  String get vault;

  /// No description provided for @vaultAdd.
  ///
  /// In en, this message translates to:
  /// **'Add an account'**
  String get vaultAdd;

  /// No description provided for @vaultEmpty.
  ///
  /// In en, this message translates to:
  /// **'No accounts yet. Add the ones Hermes may sign in with for you.'**
  String get vaultEmpty;

  /// No description provided for @vaultFooter.
  ///
  /// In en, this message translates to:
  /// **'Hermes can sign in to these sites for you. Passwords are encrypted on your server and never sent back to the app. Swipe left to remove an account.'**
  String get vaultFooter;

  /// No description provided for @vaultDelete.
  ///
  /// In en, this message translates to:
  /// **'Remove the account'**
  String get vaultDelete;

  /// No description provided for @vaultDeleteMessage.
  ///
  /// In en, this message translates to:
  /// **'Hermes will no longer be able to sign in with this account.'**
  String get vaultDeleteMessage;

  /// No description provided for @vaultTwoFactor.
  ///
  /// In en, this message translates to:
  /// **'2FA'**
  String get vaultTwoFactor;

  /// No description provided for @vaultLabel.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get vaultLabel;

  /// No description provided for @vaultLabelHint.
  ///
  /// In en, this message translates to:
  /// **'GitHub (work)'**
  String get vaultLabelHint;

  /// No description provided for @vaultSite.
  ///
  /// In en, this message translates to:
  /// **'Site'**
  String get vaultSite;

  /// No description provided for @vaultEmail.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get vaultEmail;

  /// No description provided for @vaultPhone.
  ///
  /// In en, this message translates to:
  /// **'Phone'**
  String get vaultPhone;

  /// No description provided for @vaultUsername.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get vaultUsername;

  /// No description provided for @vaultPassword.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get vaultPassword;

  /// No description provided for @vaultOtp.
  ///
  /// In en, this message translates to:
  /// **'Two-factor key (optional)'**
  String get vaultOtp;

  /// No description provided for @vaultOtpHint.
  ///
  /// In en, this message translates to:
  /// **'Base32 key or otpauth:// link'**
  String get vaultOtpHint;

  /// No description provided for @vaultOtpFooter.
  ///
  /// In en, this message translates to:
  /// **'The key shown when you set up an authenticator app. With it, Hermes generates the 6-digit codes itself.'**
  String get vaultOtpFooter;

  /// No description provided for @agentScripts.
  ///
  /// In en, this message translates to:
  /// **'Scripts'**
  String get agentScripts;

  /// No description provided for @attachPhotos.
  ///
  /// In en, this message translates to:
  /// **'Photos'**
  String get attachPhotos;

  /// No description provided for @attachCamera.
  ///
  /// In en, this message translates to:
  /// **'Take a photo'**
  String get attachCamera;

  /// No description provided for @attachFiles.
  ///
  /// In en, this message translates to:
  /// **'Files'**
  String get attachFiles;

  /// No description provided for @workers.
  ///
  /// In en, this message translates to:
  /// **'Workers'**
  String get workers;

  /// No description provided for @subagents.
  ///
  /// In en, this message translates to:
  /// **'Subagents'**
  String get subagents;

  /// No description provided for @subagentDone.
  ///
  /// In en, this message translates to:
  /// **'Finished'**
  String get subagentDone;

  /// No description provided for @subagentFailed.
  ///
  /// In en, this message translates to:
  /// **'Did not finish'**
  String get subagentFailed;

  /// No description provided for @workersNone.
  ///
  /// In en, this message translates to:
  /// **'No worker running'**
  String get workersNone;

  /// No description provided for @workerRunning.
  ///
  /// In en, this message translates to:
  /// **'Working'**
  String get workerRunning;

  /// No description provided for @workerSince.
  ///
  /// In en, this message translates to:
  /// **'Working for {time}'**
  String workerSince(String time);

  /// No description provided for @workerSilent.
  ///
  /// In en, this message translates to:
  /// **'No sign of life for {time}'**
  String workerSilent(String time);

  /// No description provided for @workerFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed: {error}'**
  String workerFailed(String error);

  /// No description provided for @kanbanReady.
  ///
  /// In en, this message translates to:
  /// **'{n} ready'**
  String kanbanReady(int n);

  /// No description provided for @kanbanTodo.
  ///
  /// In en, this message translates to:
  /// **'{n} to do'**
  String kanbanTodo(int n);

  /// No description provided for @kanbanReview.
  ///
  /// In en, this message translates to:
  /// **'{n} in review'**
  String kanbanReview(int n);

  /// No description provided for @kanbanBlocked.
  ///
  /// In en, this message translates to:
  /// **'{n} blocked'**
  String kanbanBlocked(int n);

  /// No description provided for @kanbanDone.
  ///
  /// In en, this message translates to:
  /// **'{n} done'**
  String kanbanDone(int n);

  /// No description provided for @effort.
  ///
  /// In en, this message translates to:
  /// **'Effort'**
  String get effort;

  /// No description provided for @effortAuto.
  ///
  /// In en, this message translates to:
  /// **'Auto'**
  String get effortAuto;

  /// No description provided for @effortMinimal.
  ///
  /// In en, this message translates to:
  /// **'Minimal'**
  String get effortMinimal;

  /// No description provided for @effortLow.
  ///
  /// In en, this message translates to:
  /// **'Low'**
  String get effortLow;

  /// No description provided for @effortMedium.
  ///
  /// In en, this message translates to:
  /// **'Medium'**
  String get effortMedium;

  /// No description provided for @effortHigh.
  ///
  /// In en, this message translates to:
  /// **'High'**
  String get effortHigh;

  /// No description provided for @effortXhigh.
  ///
  /// In en, this message translates to:
  /// **'Extra high'**
  String get effortXhigh;

  /// No description provided for @effortMax.
  ///
  /// In en, this message translates to:
  /// **'Max'**
  String get effortMax;

  /// No description provided for @usage.
  ///
  /// In en, this message translates to:
  /// **'Usage'**
  String get usage;

  /// No description provided for @usageDays.
  ///
  /// In en, this message translates to:
  /// **'{n} days'**
  String usageDays(int n);

  /// No description provided for @usageTokens.
  ///
  /// In en, this message translates to:
  /// **'Tokens'**
  String get usageTokens;

  /// No description provided for @usageCost.
  ///
  /// In en, this message translates to:
  /// **'Estimated cost'**
  String get usageCost;

  /// No description provided for @usageSessions.
  ///
  /// In en, this message translates to:
  /// **'Conversations'**
  String get usageSessions;

  /// No description provided for @usageByModel.
  ///
  /// In en, this message translates to:
  /// **'By model'**
  String get usageByModel;

  /// No description provided for @usageCache.
  ///
  /// In en, this message translates to:
  /// **'Plus {n} tokens read from cache'**
  String usageCache(String n);

  /// No description provided for @memory.
  ///
  /// In en, this message translates to:
  /// **'Memory'**
  String get memory;

  /// No description provided for @memoryAboutYou.
  ///
  /// In en, this message translates to:
  /// **'About you'**
  String get memoryAboutYou;

  /// No description provided for @memoryNotes.
  ///
  /// In en, this message translates to:
  /// **'Its notes'**
  String get memoryNotes;

  /// No description provided for @memoryEmpty.
  ///
  /// In en, this message translates to:
  /// **'Hermes hasn\'t remembered anything yet.'**
  String get memoryEmpty;

  /// No description provided for @memoryFooter.
  ///
  /// In en, this message translates to:
  /// **'Hermes writes these itself as you talk. Fix what\'s wrong, or swipe left to forget it.'**
  String get memoryFooter;

  /// No description provided for @memoryForget.
  ///
  /// In en, this message translates to:
  /// **'Forget'**
  String get memoryForget;

  /// No description provided for @memoryForgetMessage.
  ///
  /// In en, this message translates to:
  /// **'Hermes will no longer know this.'**
  String get memoryForgetMessage;

  /// No description provided for @searchInMessages.
  ///
  /// In en, this message translates to:
  /// **'In messages'**
  String get searchInMessages;

  /// No description provided for @kanban.
  ///
  /// In en, this message translates to:
  /// **'Kanban'**
  String get kanban;

  /// No description provided for @kanbanYourTurn.
  ///
  /// In en, this message translates to:
  /// **'Your turn'**
  String get kanbanYourTurn;

  /// No description provided for @kanbanNothing.
  ///
  /// In en, this message translates to:
  /// **'Nothing is waiting for you.'**
  String get kanbanNothing;

  /// No description provided for @kanbanToReview.
  ///
  /// In en, this message translates to:
  /// **'To review'**
  String get kanbanToReview;

  /// No description provided for @kanbanIsBlocked.
  ///
  /// In en, this message translates to:
  /// **'Blocked'**
  String get kanbanIsBlocked;

  /// No description provided for @kanbanDecision.
  ///
  /// In en, this message translates to:
  /// **'Decision'**
  String get kanbanDecision;

  /// No description provided for @kanbanBoard.
  ///
  /// In en, this message translates to:
  /// **'Board'**
  String get kanbanBoard;

  /// No description provided for @kanbanAdd.
  ///
  /// In en, this message translates to:
  /// **'New idea'**
  String get kanbanAdd;

  /// No description provided for @kanbanTitle.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get kanbanTitle;

  /// No description provided for @kanbanDetails.
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get kanbanDetails;

  /// No description provided for @kanbanAddFooter.
  ///
  /// In en, this message translates to:
  /// **'It goes to Triage, where the planner picks it up.'**
  String get kanbanAddFooter;

  /// No description provided for @kanbanDescription.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get kanbanDescription;

  /// No description provided for @kanbanSummary.
  ///
  /// In en, this message translates to:
  /// **'Latest summary'**
  String get kanbanSummary;

  /// No description provided for @kanbanHistory.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get kanbanHistory;

  /// No description provided for @kanbanReplyHint.
  ///
  /// In en, this message translates to:
  /// **'Your answer…'**
  String get kanbanReplyHint;

  /// No description provided for @kanbanApprove.
  ///
  /// In en, this message translates to:
  /// **'Approve'**
  String get kanbanApprove;

  /// No description provided for @kanbanSendBack.
  ///
  /// In en, this message translates to:
  /// **'Send back'**
  String get kanbanSendBack;

  /// No description provided for @kanbanSendBackMessage.
  ///
  /// In en, this message translates to:
  /// **'The task goes back to Ready, with your comment if you wrote one.'**
  String get kanbanSendBackMessage;

  /// No description provided for @kanbanReviewRequested.
  ///
  /// In en, this message translates to:
  /// **'Review requested'**
  String get kanbanReviewRequested;

  /// No description provided for @kanbanCompleted.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get kanbanCompleted;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @folder.
  ///
  /// In en, this message translates to:
  /// **'Folder'**
  String get folder;

  /// No description provided for @folderTitle.
  ///
  /// In en, this message translates to:
  /// **'Working folder'**
  String get folderTitle;

  /// No description provided for @folderHere.
  ///
  /// In en, this message translates to:
  /// **'This computer'**
  String get folderHere;

  /// No description provided for @folderServer.
  ///
  /// In en, this message translates to:
  /// **'Server'**
  String get folderServer;

  /// No description provided for @folderHereHint.
  ///
  /// In en, this message translates to:
  /// **'Hermes runs its commands here from the chat; you approve them.'**
  String get folderHereHint;

  /// No description provided for @folderServerHint.
  ///
  /// In en, this message translates to:
  /// **'Hermes works there with its own tools, on the server.'**
  String get folderServerHint;

  /// No description provided for @folderChoose.
  ///
  /// In en, this message translates to:
  /// **'Choose'**
  String get folderChoose;

  /// No description provided for @folderEmpty.
  ///
  /// In en, this message translates to:
  /// **'No folders here'**
  String get folderEmpty;

  /// No description provided for @folderOnHere.
  ///
  /// In en, this message translates to:
  /// **'this computer'**
  String get folderOnHere;

  /// No description provided for @folderOnServer.
  ///
  /// In en, this message translates to:
  /// **'server'**
  String get folderOnServer;

  /// No description provided for @folderFailed.
  ///
  /// In en, this message translates to:
  /// **'Folder not changed: {error}'**
  String folderFailed(String error);

  /// No description provided for @modelsRecent.
  ///
  /// In en, this message translates to:
  /// **'Recent'**
  String get modelsRecent;

  /// No description provided for @modelsMore.
  ///
  /// In en, this message translates to:
  /// **'More models'**
  String get modelsMore;

  /// No description provided for @screen.
  ///
  /// In en, this message translates to:
  /// **'Bot screen'**
  String get screen;

  /// No description provided for @screenTakeOver.
  ///
  /// In en, this message translates to:
  /// **'Take over'**
  String get screenTakeOver;

  /// No description provided for @screenHandBack.
  ///
  /// In en, this message translates to:
  /// **'Hand back'**
  String get screenHandBack;

  /// No description provided for @screenBot.
  ///
  /// In en, this message translates to:
  /// **'The bot has control. Take over to click and type, e.g. to solve a CAPTCHA.'**
  String get screenBot;

  /// No description provided for @screenYours.
  ///
  /// In en, this message translates to:
  /// **'You have control: the bot waits until you hand it back.'**
  String get screenYours;

  /// No description provided for @screenSomeone.
  ///
  /// In en, this message translates to:
  /// **'Someone else has control.'**
  String get screenSomeone;

  /// No description provided for @screenMissing.
  ///
  /// In en, this message translates to:
  /// **'The bot\'s screen isn\'t installed on the server (hermes computer-use screen install).'**
  String get screenMissing;

  /// No description provided for @screenLost.
  ///
  /// In en, this message translates to:
  /// **'Connection to the screen lost.'**
  String get screenLost;

  /// No description provided for @screenRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get screenRetry;

  /// No description provided for @screenType.
  ///
  /// In en, this message translates to:
  /// **'Type on the screen'**
  String get screenType;

  /// No description provided for @screenFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed: {error}'**
  String screenFailed(String error);

  /// No description provided for @systemMachine.
  ///
  /// In en, this message translates to:
  /// **'Machine'**
  String get systemMachine;

  /// No description provided for @systemCpu.
  ///
  /// In en, this message translates to:
  /// **'Processor'**
  String get systemCpu;

  /// No description provided for @systemMemory.
  ///
  /// In en, this message translates to:
  /// **'Memory'**
  String get systemMemory;

  /// No description provided for @systemDisk.
  ///
  /// In en, this message translates to:
  /// **'Disk'**
  String get systemDisk;

  /// No description provided for @systemUptime.
  ///
  /// In en, this message translates to:
  /// **'Up for'**
  String get systemUptime;

  /// No description provided for @systemLoad.
  ///
  /// In en, this message translates to:
  /// **'load {load} on {cores} cores'**
  String systemLoad(String load, String cores);

  /// No description provided for @systemSpace.
  ///
  /// In en, this message translates to:
  /// **'{used} of {total} GB · {percent} %'**
  String systemSpace(String used, String total, int percent);

  /// No description provided for @systemUptimeValue.
  ///
  /// In en, this message translates to:
  /// **'{days}d {hours}h'**
  String systemUptimeValue(int days, int hours);

  /// No description provided for @cronRunAgain.
  ///
  /// In en, this message translates to:
  /// **'Run again'**
  String get cronRunAgain;

  /// No description provided for @cronFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get cronFailed;

  /// No description provided for @cronSolveCaptcha.
  ///
  /// In en, this message translates to:
  /// **'Solve it on the bot\'s screen'**
  String get cronSolveCaptcha;

  /// No description provided for @screenOpen.
  ///
  /// In en, this message translates to:
  /// **'Bot screen · take over'**
  String get screenOpen;
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
