// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get statusThinking => 'Thinking…';

  @override
  String get statusWriting => 'Writing…';

  @override
  String statusTool(String tool) {
    return 'Using $tool…';
  }

  @override
  String get composerQueueHint => 'Queue a message';

  @override
  String get queued => 'Queued · tap to edit';

  @override
  String get editingMessage => 'Editing message · sent in its place';

  @override
  String get memoryUpdated => 'Memory updated';

  @override
  String routineResult(String job) {
    return 'Routine · $job';
  }

  @override
  String get system => 'System';

  @override
  String get systemServer => 'Server';

  @override
  String get systemVersion => 'Version';

  @override
  String get systemGateway => 'Gateway';

  @override
  String get systemRunning => 'Running';

  @override
  String get systemStopped => 'Stopped';

  @override
  String get systemHealth => 'Health';

  @override
  String get systemHealthy => 'All good';

  @override
  String get systemDegraded => 'Degraded';

  @override
  String get systemSessions => 'Active sessions';

  @override
  String get systemPlatforms => 'Messaging';

  @override
  String systemConnected(int count, int total) {
    return '$count of $total connected';
  }

  @override
  String get systemUpdate => 'Update';

  @override
  String get systemUpToDate => 'Hermes is up to date.';

  @override
  String get systemUpdateReady => 'Update available';

  @override
  String systemChanges(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count changes',
      one: '1 change',
    );
    return '$_temp0';
  }

  @override
  String get systemUpdateNow => 'Update now';

  @override
  String get systemUpdateConfirm =>
      'Hermes will update and restart. Replies in progress will stop.';

  @override
  String get systemUpdating => 'Updating…';

  @override
  String get systemUpdated => 'Update done.';

  @override
  String get systemRestart => 'Restart the gateway';

  @override
  String get systemRestartConfirm => 'Replies in progress will stop.';

  @override
  String get systemRestarting => 'The gateway is restarting.';

  @override
  String systemFailed(String reason) {
    return 'It didn\'t work: $reason';
  }

  @override
  String get lockApp => 'Lock the app';

  @override
  String get unlock => 'Unlock';

  @override
  String get unlockReason => 'Unlock Hermes';

  @override
  String get dropFiles => 'Drop to attach to your message';

  @override
  String get menuFile => 'File';

  @override
  String get menuView => 'View';

  @override
  String get menuWindow => 'Window';

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
  String get macShell => 'Commands on this computer';

  @override
  String get macShellHint =>
      'Hermes can ask from the chat to run commands here; you approve them in the app.';

  @override
  String get macTitle => 'On this computer';

  @override
  String macWrite(String path) {
    return 'Write $path';
  }

  @override
  String get macRun => 'Run';

  @override
  String get macAlways => 'Always in this chat';

  @override
  String get macRefuse => 'Refuse';

  @override
  String get macStop => 'Stop';

  @override
  String get macRefused => 'Refused';

  @override
  String get macSkipped => 'Not run';

  @override
  String get macResults => 'Results sent to Hermes';

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
  String chatCost(String cost) {
    return 'Cost: $cost';
  }

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

  @override
  String get approvalTitle => 'Hermes wants to run a command';

  @override
  String get approveOnce => 'Allow once';

  @override
  String get approveSession => 'For this chat';

  @override
  String get approveAlways => 'Always';

  @override
  String get approveDeny => 'Deny';

  @override
  String toolsUsed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count actions',
      one: '1 action',
    );
    return '$_temp0';
  }

  @override
  String get cronRuns => 'Run history';

  @override
  String get cronRunsEmpty => 'No runs yet';

  @override
  String get cronMonitor => 'Monitor';

  @override
  String get cronMonitorScript => 'Monitor script';

  @override
  String get cronMonitorUrl => 'Monitored URL';

  @override
  String get cronMonitorHint =>
      'Checked before each run: when its output hasn\'t changed, the AI doesn\'t run. A script or a URL, not both, and not with Script only.';

  @override
  String get ok => 'OK';

  @override
  String get agents => 'Agents';

  @override
  String get agentNew => 'New agent';

  @override
  String get agentsEmpty =>
      'No agents yet. An agent works on its own on a schedule, and tells you what matters.';

  @override
  String get agentWorking => 'Working on it…';

  @override
  String get agentDone => 'Mission complete';

  @override
  String get agentAsleep => 'Asleep';

  @override
  String get agentTrouble => 'Ran into a problem';

  @override
  String agentWakesIn(String time) {
    return 'Wakes up in $time';
  }

  @override
  String get agentIdle => 'Ready';

  @override
  String get agentWake => 'Wake up now';

  @override
  String get agentSaid => 'Last word';

  @override
  String get agentSaidNothing => 'Hasn\'t said anything yet.';

  @override
  String get agentMission => 'Mission';

  @override
  String get agentRhythm => 'Rhythm';

  @override
  String get agentActive => 'Active';

  @override
  String get agentQuiet => 'Speaks only when it matters';

  @override
  String get agentTeam => 'Listens to';

  @override
  String get agentTeamNone => 'No one';

  @override
  String get agentTeamAlone => 'There\'s no other agent yet.';

  @override
  String get agentSettings => 'All settings';

  @override
  String get agentBlank => 'Start from scratch';

  @override
  String get agentBlankHint => 'Your own mission, rhythm and model';

  @override
  String get agentCreate => 'Create';

  @override
  String get vault => 'Vault';

  @override
  String get vaultAdd => 'Add an account';

  @override
  String get vaultEmpty =>
      'No accounts yet. Add the ones Hermes may sign in with for you.';

  @override
  String get vaultFooter =>
      'Hermes can sign in to these sites for you. Passwords are encrypted on your server and never sent back to the app. Swipe left to remove an account.';

  @override
  String get vaultDelete => 'Remove the account';

  @override
  String get vaultDeleteMessage =>
      'Hermes will no longer be able to sign in with this account.';

  @override
  String get vaultTwoFactor => '2FA';

  @override
  String get vaultLabel => 'Name';

  @override
  String get vaultLabelHint => 'GitHub (work)';

  @override
  String get vaultSite => 'Site';

  @override
  String get vaultEmail => 'Email';

  @override
  String get vaultPhone => 'Phone';

  @override
  String get vaultUsername => 'Username';

  @override
  String get vaultPassword => 'Password';

  @override
  String get vaultOtp => 'Two-factor key (optional)';

  @override
  String get vaultOtpHint => 'Base32 key or otpauth:// link';

  @override
  String get vaultOtpFooter =>
      'The key shown when you set up an authenticator app. With it, Hermes generates the 6-digit codes itself.';

  @override
  String get agentScripts => 'Scripts';

  @override
  String get attachPhotos => 'Photos';

  @override
  String get attachCamera => 'Take a photo';

  @override
  String get attachFiles => 'Files';

  @override
  String get workers => 'Workers';

  @override
  String get subagents => 'Subagents';

  @override
  String get subagentDone => 'Finished';

  @override
  String get subagentFailed => 'Did not finish';

  @override
  String get workersNone => 'No worker running';

  @override
  String get workerRunning => 'Working';

  @override
  String workerSince(String time) {
    return 'Working for $time';
  }

  @override
  String workerSilent(String time) {
    return 'No sign of life for $time';
  }

  @override
  String workerFailed(String error) {
    return 'Failed: $error';
  }

  @override
  String kanbanReady(int n) {
    return '$n ready';
  }

  @override
  String kanbanTodo(int n) {
    return '$n to do';
  }

  @override
  String kanbanReview(int n) {
    return '$n in review';
  }

  @override
  String kanbanBlocked(int n) {
    return '$n blocked';
  }

  @override
  String kanbanDone(int n) {
    return '$n done';
  }

  @override
  String get effort => 'Effort';

  @override
  String get effortAuto => 'Auto';

  @override
  String get effortMinimal => 'Minimal';

  @override
  String get effortLow => 'Low';

  @override
  String get effortMedium => 'Medium';

  @override
  String get effortHigh => 'High';

  @override
  String get effortXhigh => 'Extra high';

  @override
  String get effortMax => 'Max';

  @override
  String get usage => 'Usage';

  @override
  String usageDays(int n) {
    return '$n days';
  }

  @override
  String get usageTokens => 'Tokens';

  @override
  String get usageCost => 'Estimated cost';

  @override
  String get usageSessions => 'Conversations';

  @override
  String get usageByModel => 'By model';

  @override
  String usageCache(String n) {
    return 'Plus $n tokens read from cache';
  }

  @override
  String get memory => 'Memory';

  @override
  String get memoryAboutYou => 'About you';

  @override
  String get memoryNotes => 'Its notes';

  @override
  String get memoryEmpty => 'Hermes hasn\'t remembered anything yet.';

  @override
  String get memoryFooter =>
      'Hermes writes these itself as you talk. Fix what\'s wrong, or swipe left to forget it.';

  @override
  String get memoryForget => 'Forget';

  @override
  String get memoryForgetMessage => 'Hermes will no longer know this.';

  @override
  String get searchInMessages => 'In messages';

  @override
  String get kanban => 'Kanban';

  @override
  String get kanbanYourTurn => 'Your turn';

  @override
  String get kanbanNothing => 'Nothing is waiting for you.';

  @override
  String get kanbanToReview => 'To review';

  @override
  String get kanbanIsBlocked => 'Blocked';

  @override
  String get kanbanDecision => 'Decision';

  @override
  String get kanbanBoard => 'Board';

  @override
  String get kanbanAdd => 'New idea';

  @override
  String get kanbanTitle => 'Title';

  @override
  String get kanbanDetails => 'Details';

  @override
  String get kanbanAddFooter =>
      'It goes to Triage, where the planner picks it up.';

  @override
  String get kanbanDescription => 'Description';

  @override
  String get kanbanSummary => 'Latest summary';

  @override
  String get kanbanHistory => 'History';

  @override
  String get kanbanReplyHint => 'Your answer…';

  @override
  String get kanbanApprove => 'Approve';

  @override
  String get kanbanSendBack => 'Send back';

  @override
  String get kanbanSendBackMessage =>
      'The task goes back to Ready, with your comment if you wrote one.';

  @override
  String get kanbanReviewRequested => 'Review requested';

  @override
  String get kanbanCompleted => 'Completed';

  @override
  String get language => 'Language';

  @override
  String get folder => 'Folder';

  @override
  String get folderTitle => 'Working folder';

  @override
  String get folderHere => 'This computer';

  @override
  String get folderServer => 'Server';

  @override
  String get folderHereHint =>
      'Hermes runs its commands here from the chat; you approve them.';

  @override
  String get folderServerHint =>
      'Hermes works there with its own tools, on the server.';

  @override
  String get folderChoose => 'Choose';

  @override
  String get folderEmpty => 'No folders here';

  @override
  String get folderOnHere => 'this computer';

  @override
  String get folderOnServer => 'server';

  @override
  String folderFailed(String error) {
    return 'Folder not changed: $error';
  }

  @override
  String get modelsRecent => 'Recent';

  @override
  String get modelsMore => 'More models';

  @override
  String get screen => 'Bot screen';

  @override
  String get screenTakeOver => 'Take over';

  @override
  String get screenHandBack => 'Hand back';

  @override
  String get screenBot =>
      'The bot has control. Take over to click and type, e.g. to solve a CAPTCHA.';

  @override
  String get screenYours =>
      'You have control: the bot waits until you hand it back.';

  @override
  String get screenSomeone => 'Someone else has control.';

  @override
  String get screenMissing =>
      'The bot\'s screen isn\'t installed on the server (hermes computer-use screen install).';

  @override
  String get screenLost => 'Connection to the screen lost.';

  @override
  String get screenRetry => 'Retry';

  @override
  String get screenType => 'Type on the screen';

  @override
  String screenFailed(String error) {
    return 'Failed: $error';
  }

  @override
  String get systemMachine => 'Machine';

  @override
  String get systemCpu => 'Processor';

  @override
  String get systemMemory => 'Memory';

  @override
  String get systemDisk => 'Disk';

  @override
  String get systemUptime => 'Up for';

  @override
  String systemLoad(String load, String cores) {
    return 'load $load on $cores cores';
  }

  @override
  String systemSpace(String used, String total, int percent) {
    return '$used of $total GB · $percent %';
  }

  @override
  String systemUptimeValue(int days, int hours) {
    return '${days}d ${hours}h';
  }

  @override
  String get cronRunAgain => 'Run again';

  @override
  String get cronFailed => 'Failed';

  @override
  String get cronSolveCaptcha => 'Solve it on the bot\'s screen';

  @override
  String get screenOpen => 'Bot screen · take over';

  @override
  String get tools => 'Skills & MCP';

  @override
  String get toolsMcp => 'MCP servers';

  @override
  String get toolsSkills => 'Skills';

  @override
  String get toolsSearch => 'Search skills';

  @override
  String get toolsNone => 'No skill matches.';

  @override
  String get toolsNextChats =>
      'A change applies to the chats started after it.';

  @override
  String get toolsMcpTest => 'Test the connection';

  @override
  String toolsMcpOk(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count tools',
      one: '1 tool',
    );
    return 'Connected · $_temp0';
  }

  @override
  String get toolsMcpFailed => 'Connection failed';

  @override
  String toolsFailed(String error) {
    return 'Not changed: $error';
  }

  @override
  String get gitTitle => 'Changes';

  @override
  String get gitChanges => 'Files changed';

  @override
  String get gitClean => 'Nothing changed';

  @override
  String get gitNotRepo => 'This folder isn\'t a git repository.';

  @override
  String get gitMessage => 'Commit message';

  @override
  String get gitCommit => 'Commit everything';

  @override
  String get gitShare => 'Share';

  @override
  String get gitPush => 'Push';

  @override
  String gitPushCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count commits',
      one: '1 commit',
    );
    return 'Push $_temp0';
  }

  @override
  String get gitPr => 'Open a pull request';

  @override
  String gitPrSee(String number) {
    return 'See pull request #$number';
  }

  @override
  String gitAhead(int count) {
    return '$count ahead';
  }

  @override
  String gitBehind(int count) {
    return '$count behind';
  }

  @override
  String get gitCommitted => 'Committed';

  @override
  String get gitPushed => 'Pushed';

  @override
  String get gitPrOpened => 'Pull request opened';

  @override
  String gitFailed(String error) {
    return 'Git: $error';
  }

  @override
  String get voiceUnavailable =>
      'Dictation isn\'t available: allow the microphone and speech recognition in the system settings.';

  @override
  String get linkDown => 'The server isn’t answering';

  @override
  String get linkDownVpn => 'The server isn’t answering through the VPN';

  @override
  String get vpnConnectingBanner => 'Connecting to the VPN…';

  @override
  String get linkRetry => 'Try again';

  @override
  String get linkRestartVpn => 'Restart VPN';

  @override
  String get a11yMenu => 'Menu';

  @override
  String get a11yToBottom => 'Scroll to bottom';

  @override
  String get a11yEdit => 'Edit';

  @override
  String get a11yResend => 'Send again';

  @override
  String get a11yCopy => 'Copy';

  @override
  String get a11yRead => 'Read aloud';

  @override
  String get a11yStopReading => 'Stop reading';

  @override
  String get a11yRegenerate => 'Regenerate';

  @override
  String get a11yRemove => 'Remove';

  @override
  String get a11yCancelEdit => 'Cancel editing';

  @override
  String get a11yAttach => 'Attach files';

  @override
  String get a11yDictate => 'Dictate';

  @override
  String get a11yStopDictating => 'Stop dictating';

  @override
  String get a11ySend => 'Send';

  @override
  String get a11yParent => 'Parent folder';

  @override
  String get a11yBack => 'Back';

  @override
  String get a11yPickTarget => 'Pick the destination';

  @override
  String get a11yShow => 'Show';

  @override
  String get a11yHide => 'Hide';

  @override
  String usageCalls(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n calls',
      one: '1 call',
    );
    return '$_temp0';
  }

  @override
  String usageInSessions(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n chats',
      one: '1 chat',
    );
    return '$_temp0';
  }

  @override
  String usageLastUsed(String time) {
    return '$time ago';
  }

  @override
  String get chatPin => 'Pin';

  @override
  String get chatUnpin => 'Unpin';

  @override
  String get chatArchive => 'Archive';

  @override
  String get chatsPinned => 'Pinned';

  @override
  String get chatsArchived => 'Archived';

  @override
  String get chatUnarchive => 'Unarchive';

  @override
  String get archivedNone => 'No archived chats.';

  @override
  String chatActionFailed(String message) {
    return 'That didn’t work.\n$message';
  }

  @override
  String get subagentSteerHint => 'A word to steer this subagent';

  @override
  String get subagentSteered =>
      'Sent: it reads it after the tool it is running.';

  @override
  String get subagentSteerRefused => 'It no longer takes directions.';

  @override
  String get spawnTrees => 'Past delegations';

  @override
  String get spawnTreesNone => 'No delegation saved yet.';

  @override
  String spawnTreeCount(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n agents',
      one: '1 agent',
    );
    return '$_temp0';
  }

  @override
  String get imageCreate => 'Create an image';

  @override
  String get imagePrompt => 'Describe the image';

  @override
  String get imageSquare => 'Square';

  @override
  String get imageLandscape => 'Landscape';

  @override
  String get imagePortrait => 'Portrait';

  @override
  String get imageMake => 'Create';

  @override
  String get imageMaking => 'Drawing it… (up to a minute or two)';

  @override
  String get imageAttach => 'Attach to the message';

  @override
  String get imageAgain => 'Try again';

  @override
  String get imageSave => 'Save…';

  @override
  String get imageFailed => 'The server couldn’t create the image.';

  @override
  String get chatsToday => 'Today';

  @override
  String get chatsYesterday => 'Yesterday';

  @override
  String get chatsWeek => 'Previous 7 days';

  @override
  String get chatsMonth => 'Previous 30 days';

  @override
  String get chatsOlder => 'Older';

  @override
  String get accent => 'Accent color';

  @override
  String get accentNeutral => 'Neutral';

  @override
  String get accentIndigo => 'Indigo';

  @override
  String get accentBlue => 'Blue';

  @override
  String get accentTeal => 'Teal';

  @override
  String get accentGreen => 'Green';

  @override
  String get accentOrange => 'Orange';

  @override
  String get accentPink => 'Pink';

  @override
  String get accentGold => 'Gold';

  @override
  String get welcomeDay => 'Hello';

  @override
  String get welcomeEvening => 'Good evening';

  @override
  String get suggestRoutines => 'Sum up my scheduled jobs’ results';

  @override
  String get suggestSchedule => 'Schedule a job every morning at 8: ';

  @override
  String get suggestKanban => 'Give me a status of my kanban';

  @override
  String get suggestWeb => 'Search the web and sum up: ';

  @override
  String get welcomeNow => 'RIGHT NOW';

  @override
  String welcomeSubagents(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n subagents at work',
      one: '1 subagent at work',
    );
    return '$_temp0';
  }

  @override
  String get welcomeRoutines => 'Scheduled jobs’ results';

  @override
  String toolsEarlier(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n earlier steps',
      one: '1 earlier step',
    );
    return '$_temp0';
  }

  @override
  String get toolsFold => 'Fold';

  @override
  String get askClarify => 'Hermes has a question';

  @override
  String get askSudo => 'Hermes needs the sudo password';

  @override
  String get askSecret => 'Hermes needs a secret';

  @override
  String get askPassword => 'Password';

  @override
  String get askValue => 'Value';

  @override
  String get askAnswer => 'Your answer';

  @override
  String get askOther => 'Something else…';

  @override
  String get askSend => 'Send';

  @override
  String get askSkip => 'Skip';

  @override
  String get backgroundTask => 'Background task';

  @override
  String get backgroundNext => 'The next message goes to a background task';

  @override
  String backgroundRunning(String task) {
    return 'In the background: $task';
  }

  @override
  String get backgroundLabel => 'background';

  @override
  String backgroundDone(String chat) {
    return 'Background task done in “$chat”';
  }

  @override
  String get backgroundOpen => 'Open';

  @override
  String get subagentModelInherit => 'Same as the chat';

  @override
  String get curator => 'Curator';

  @override
  String get curatorActive => 'Tidies up the skills';

  @override
  String get curatorOff => 'Turned off in the server\'s config';

  @override
  String curatorEvery(int hours) {
    return 'every $hours h';
  }

  @override
  String curatorLast(String when) {
    return 'last on $when';
  }

  @override
  String get curatorMerge => 'AI merges and rewrites them';

  @override
  String get curatorRun => 'Run now';

  @override
  String get curatorStarted => 'The curator is running';

  @override
  String curatorFooter(int stale, int archive) {
    return 'Between chats, a skill Hermes wrote for itself and hasn\'t used for $stale days is marked stale, then archived after $archive days. The AI pass also merges and rewrites similar skills, at the cost of a model call.';
  }

  @override
  String get codeCopied => 'Copied';

  @override
  String codeUnfold(int n) {
    return 'Show all $n lines';
  }

  @override
  String get toBottomWriting => 'Writing';

  @override
  String toBottomNew(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n new messages',
      one: '1 new message',
    );
    return '$_temp0';
  }

  @override
  String get paletteMenu => 'Find or Run…';

  @override
  String get paletteHint => 'A command, a page or a chat';

  @override
  String get paletteNone => 'Nothing matches';

  @override
  String get paletteChats => 'Chat';

  @override
  String get paletteModel => 'Change the model';

  @override
  String get paletteFolder => 'Pick the folder';

  @override
  String get notifications => 'Notifications';

  @override
  String get notificationsInfo =>
      'A reply or background task done while Herapp is out of sight tells you.';

  @override
  String get compare => 'Compare with another model';

  @override
  String get compareClose => 'Close the comparison';

  @override
  String get compareNoModels => 'No other model to compare with';

  @override
  String serverRefused(String message) {
    return 'Hermes refused: $message';
  }
}
