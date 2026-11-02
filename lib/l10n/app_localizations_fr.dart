// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get statusThinking => 'Réfléchit…';

  @override
  String get statusWriting => 'Écrit…';

  @override
  String statusTool(String tool) {
    return 'Utilise $tool…';
  }

  @override
  String get composerQueueHint => 'Message suivant';

  @override
  String get queued => 'En attente · touche pour modifier';

  @override
  String get editingMessage => 'Modification du message · renvoyé à sa place';

  @override
  String get memoryUpdated => 'Mémoire mise à jour';

  @override
  String routineResult(String job) {
    return 'Routine · $job';
  }

  @override
  String get system => 'Système';

  @override
  String get systemServer => 'Serveur';

  @override
  String get systemVersion => 'Version';

  @override
  String get systemGateway => 'Passerelle';

  @override
  String get systemRunning => 'En marche';

  @override
  String get systemStopped => 'Arrêtée';

  @override
  String get systemHealth => 'Santé';

  @override
  String get systemHealthy => 'Tout va bien';

  @override
  String get systemDegraded => 'Dégradée';

  @override
  String get systemSessions => 'Sessions actives';

  @override
  String get systemPlatforms => 'Messageries';

  @override
  String systemConnected(int count, int total) {
    return '$count sur $total connectées';
  }

  @override
  String get systemUpdate => 'Mise à jour';

  @override
  String get systemUpToDate => 'Hermes est à jour.';

  @override
  String get systemUpdateReady => 'Mise à jour disponible';

  @override
  String systemChanges(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count nouveautés',
      one: '1 nouveauté',
    );
    return '$_temp0';
  }

  @override
  String get systemUpdateNow => 'Mettre à jour';

  @override
  String get systemUpdateConfirm =>
      'Hermes va se mettre à jour et redémarrer. Les réponses en cours s\'arrêteront.';

  @override
  String get systemUpdating => 'Mise à jour en cours…';

  @override
  String get systemUpdated => 'Mise à jour terminée.';

  @override
  String get systemRestart => 'Redémarrer la passerelle';

  @override
  String get systemRestartConfirm => 'Les réponses en cours s\'arrêteront.';

  @override
  String get systemRestarting => 'La passerelle redémarre.';

  @override
  String systemFailed(String reason) {
    return 'Ça n\'a pas marché : $reason';
  }

  @override
  String get lockApp => 'Verrouiller l’app';

  @override
  String get unlock => 'Déverrouiller';

  @override
  String get unlockReason => 'Déverrouille Hermes';

  @override
  String get dropFiles => 'Dépose pour joindre à ton message';

  @override
  String get menuFile => 'Fichier';

  @override
  String get menuView => 'Présentation';

  @override
  String get menuWindow => 'Fenêtre';

  @override
  String get newChat => 'Nouveau chat';

  @override
  String get emptyHeadline => 'Comment puis-je aider ?';

  @override
  String get composerHint => 'Poser une question';

  @override
  String get search => 'Rechercher';

  @override
  String get chats => 'Chats';

  @override
  String get settings => 'Paramètres';

  @override
  String get model => 'Modèle';

  @override
  String get done => 'OK';

  @override
  String get appearance => 'Apparence';

  @override
  String get themeSystem => 'Système';

  @override
  String get themeLight => 'Clair';

  @override
  String get themeDark => 'Sombre';

  @override
  String get general => 'Général';

  @override
  String get haptics => 'Retours haptiques';

  @override
  String get macShell => 'Commandes sur cet ordinateur';

  @override
  String get macShellHint =>
      'Hermes peut demander depuis le chat à lancer des commandes ici ; tu les valides dans l’app.';

  @override
  String get macTitle => 'Sur cet ordinateur';

  @override
  String macWrite(String path) {
    return 'Écrire $path';
  }

  @override
  String get macRun => 'Lancer';

  @override
  String get macAlways => 'Toujours dans cette conversation';

  @override
  String get macRefuse => 'Refuser';

  @override
  String get macStop => 'Arrêter';

  @override
  String get macRefused => 'Refusé';

  @override
  String get macSkipped => 'Non lancé';

  @override
  String get macResults => 'Résultats envoyés à Hermes';

  @override
  String get hermesServer => 'Serveur Hermes';

  @override
  String get hermesServerFooter =>
      'Adresse à laquelle l’app enverra les messages.';

  @override
  String get wireguard => 'WireGuard';

  @override
  String get wgConfig => 'Configuration';

  @override
  String get wgImport => 'Importer';

  @override
  String get wgUse => 'Passer par WireGuard';

  @override
  String get wgConnected => 'Connecté';

  @override
  String get wgConnecting => 'Connexion…';

  @override
  String wgError(String message) {
    return 'Erreur : $message';
  }

  @override
  String get wgUnavailable => 'Indisponible sur cette plateforme';

  @override
  String get wgRemove => 'Supprimer la configuration';

  @override
  String get wgFooter =>
      'Tout le trafic réseau de l’app passe par le tunnel. Tunnel activé mais coupé : l’app ne communique plus.';

  @override
  String get wgInvalidFile =>
      'Ce fichier n’est pas une configuration WireGuard.';

  @override
  String get serverTest => 'Tester la connexion';

  @override
  String serverUnreachable(String message) {
    return 'Injoignable : $message';
  }

  @override
  String get serverInvalidUrl => 'Adresse invalide';

  @override
  String get serverBlocked => 'Bloqué : le tunnel WireGuard n’est pas connecté';

  @override
  String get serverTimeout => 'aucune réponse après 15 s';

  @override
  String get viaWireguard => 'via WireGuard';

  @override
  String serverHermes(String version, int ms) {
    return 'Hermes $version · $ms ms';
  }

  @override
  String serverNotHermes(int status) {
    return 'Joignable, mais ce n’est pas un serveur Hermes (HTTP $status)';
  }

  @override
  String get hermesAuth => 'Authentification';

  @override
  String get hermesUser => 'Identifiant';

  @override
  String get hermesPassword => 'Mot de passe';

  @override
  String serverAuthRequired(String version) {
    return 'Hermes $version · connexion requise, active l’authentification';
  }

  @override
  String serverAuthRejected(String version) {
    return 'Hermes $version · identifiants refusés';
  }

  @override
  String serverAuthOk(String version, int ms) {
    return 'Hermes $version · connecté · $ms ms';
  }

  @override
  String serverAuthRateLimited(String version) {
    return 'Hermes $version · trop de tentatives, réessaie plus tard';
  }

  @override
  String serverAuthFailed(String version, int status) {
    return 'Hermes $version · échec de la connexion (HTTP $status)';
  }

  @override
  String get serverTunnelFailed =>
      'le tunnel WireGuard n’arrive pas à joindre le serveur';

  @override
  String get modelsNone => 'Aucun modèle n\'est configuré sur le serveur.';

  @override
  String chatCost(String cost) {
    return 'Coût : $cost';
  }

  @override
  String contextUsage(int percent) {
    return 'Contexte : $percent % utilisé';
  }

  @override
  String get serverNotSet =>
      'Renseigne l\'adresse de ton serveur Hermes dans les réglages.';

  @override
  String get serverRestart =>
      'Hermes a été mis à jour mais tourne encore sur l\'ancienne version. Redémarre le serveur Hermes.';

  @override
  String serverLoadFailed(String message) {
    return 'Impossible de joindre le serveur Hermes.\n$message';
  }

  @override
  String get quotas => 'Quotas';

  @override
  String get quotaNoData => 'Pas de données de quota';

  @override
  String get quotaLimited => 'Limité';

  @override
  String quotaLimitedUntil(String time) {
    return 'Limité, de retour dans $time';
  }

  @override
  String quotaResets(String time) {
    return 'Réinitialisé dans $time';
  }

  @override
  String durationDays(int days, int hours) {
    return '$days j $hours h';
  }

  @override
  String durationHours(int hours, int minutes) {
    return '$hours h $minutes min';
  }

  @override
  String durationMinutes(int minutes) {
    return '$minutes min';
  }

  @override
  String get quotaFooter =>
      'Utilisation remontée par Hermes pour les abonnements. Tire vers le bas pour actualiser.';

  @override
  String get deleteChat => 'Supprimer le chat';

  @override
  String get deleteChatMessage =>
      'Ce chat sera supprimé définitivement de Hermes.';

  @override
  String get cancel => 'Annuler';

  @override
  String deleteFailed(String message) {
    return 'Impossible de supprimer le chat.\n$message';
  }

  @override
  String cronNext(String time) {
    return 'Prochaine exécution dans $time';
  }

  @override
  String cronLast(String time) {
    return 'Dernière exécution il y a $time';
  }

  @override
  String cronLastFailed(String error) {
    return 'Dernière exécution en échec : $error';
  }

  @override
  String get cronCompleted => 'Terminée';

  @override
  String get cronRunning => 'En cours…';

  @override
  String get cronRunNow => 'Lancer maintenant';

  @override
  String cronStarted(String name) {
    return '« $name » lancée';
  }

  @override
  String cronActionFailed(String message) {
    return 'Impossible de modifier la tâche.\n$message';
  }

  @override
  String get cronNew => 'Nouvelle tâche';

  @override
  String get cronEdit => 'Modifier la tâche';

  @override
  String get cronSave => 'Enregistrer';

  @override
  String get cronGeneral => 'Général';

  @override
  String get cronName => 'Nom';

  @override
  String get cronSchedule => 'Planification';

  @override
  String get cronScheduleHint =>
      '0 9 * * *, every 30m, every monday 9am, ou une date comme 2026-11-02T08:00';

  @override
  String get cronRepeat => 'Répétitions';

  @override
  String get cronRepeatHint => 'forever, once ou un nombre';

  @override
  String cronRepeatDone(int count) {
    return '$count exécutions jusqu’ici';
  }

  @override
  String get cronTask => 'Tâche';

  @override
  String get cronPrompt => 'Prompt';

  @override
  String get cronScript => 'Script';

  @override
  String get cronScriptHint => 'Nom d’un script du dossier des scripts cron';

  @override
  String get cronNoAgent => 'Script seul, sans IA';

  @override
  String get cronSkills => 'Skills';

  @override
  String get cronListHint => 'Séparés par des virgules';

  @override
  String get cronModelSection => 'Modèle';

  @override
  String get cronModel => 'Modèle';

  @override
  String get cronProvider => 'Fournisseur';

  @override
  String get cronBaseUrl => 'URL de base';

  @override
  String get cronServerDefault => 'Défaut du serveur';

  @override
  String get cronDelivery => 'Livraison';

  @override
  String get cronDeliver => 'Livrer à';

  @override
  String get cronFailureDeliver => 'En cas d’échec, livrer à';

  @override
  String get cronFailureHint => 'Comme ci-dessus';

  @override
  String get cronAdvanced => 'Avancé';

  @override
  String get cronWorkdir => 'Dossier de travail';

  @override
  String get cronToolsets => 'Toolsets';

  @override
  String get cronContextFrom => 'Contexte des tâches';

  @override
  String get cronContextHint =>
      'Ids des tâches dont la dernière sortie est transmise à celle-ci';

  @override
  String get cronDelete => 'Supprimer la tâche';

  @override
  String get cronDeleteMessage =>
      'Cette tâche sera supprimée définitivement de Hermes.';

  @override
  String get approvalTitle => 'Hermes veut lancer une commande';

  @override
  String get approveOnce => 'Autoriser une fois';

  @override
  String get approveSession => 'Pour ce chat';

  @override
  String get approveAlways => 'Toujours';

  @override
  String get approveDeny => 'Refuser';

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
  String get cronRuns => 'Historique des exécutions';

  @override
  String get cronRunsEmpty => 'Aucune exécution pour l’instant';

  @override
  String get cronMonitor => 'Surveillance';

  @override
  String get cronMonitorScript => 'Script de surveillance';

  @override
  String get cronMonitorUrl => 'URL surveillée';

  @override
  String get cronMonitorHint =>
      'Vérifié avant chaque exécution : si sa sortie n’a pas changé, l’IA ne tourne pas. Un script ou une URL, pas les deux, et pas avec Script seul.';

  @override
  String get ok => 'OK';

  @override
  String get agents => 'Agents';

  @override
  String get agentNew => 'Nouvel agent';

  @override
  String get agentsEmpty =>
      'Aucun agent pour l’instant. Un agent travaille seul à son rythme et te dit ce qui compte.';

  @override
  String get agentWorking => 'Au travail…';

  @override
  String get agentDone => 'Mission accomplie';

  @override
  String get agentAsleep => 'Endormi';

  @override
  String get agentTrouble => 'A rencontré un problème';

  @override
  String agentWakesIn(String time) {
    return 'Se réveille dans $time';
  }

  @override
  String get agentIdle => 'Prêt';

  @override
  String get agentWake => 'Réveiller maintenant';

  @override
  String get agentSaid => 'Dernier mot';

  @override
  String get agentSaidNothing => 'N’a encore rien dit.';

  @override
  String get agentMission => 'Mission';

  @override
  String get agentRhythm => 'Rythme';

  @override
  String get agentActive => 'Actif';

  @override
  String get agentQuiet => 'Ne parle que si c’est utile';

  @override
  String get agentTeam => 'Écoute';

  @override
  String get agentTeamNone => 'Personne';

  @override
  String get agentTeamAlone => 'Il n’y a pas encore d’autre agent.';

  @override
  String get agentSettings => 'Tous les réglages';

  @override
  String get agentBlank => 'Partir de zéro';

  @override
  String get agentBlankHint => 'Ta mission, ton rythme et ton modèle';

  @override
  String get agentCreate => 'Créer';

  @override
  String get vault => 'Coffre-fort';

  @override
  String get vaultAdd => 'Ajouter un compte';

  @override
  String get vaultEmpty =>
      'Aucun compte pour l’instant. Ajoute ceux avec lesquels Hermes peut se connecter à ta place.';

  @override
  String get vaultFooter =>
      'Hermes peut se connecter à ces sites à ta place. Les mots de passe sont chiffrés sur ton serveur et ne reviennent jamais vers l’app. Glisse vers la gauche pour retirer un compte.';

  @override
  String get vaultDelete => 'Retirer le compte';

  @override
  String get vaultDeleteMessage =>
      'Hermes ne pourra plus se connecter avec ce compte.';

  @override
  String get vaultTwoFactor => '2FA';

  @override
  String get vaultLabel => 'Nom';

  @override
  String get vaultLabelHint => 'GitHub (travail)';

  @override
  String get vaultSite => 'Site';

  @override
  String get vaultEmail => 'E-mail';

  @override
  String get vaultPhone => 'Téléphone';

  @override
  String get vaultUsername => 'Identifiant';

  @override
  String get vaultPassword => 'Mot de passe';

  @override
  String get vaultOtp => 'Clé de double authentification (facultatif)';

  @override
  String get vaultOtpHint => 'Clé base32 ou lien otpauth://';

  @override
  String get vaultOtpFooter =>
      'La clé affichée quand tu configures une app d’authentification. Avec elle, Hermes génère lui-même les codes à 6 chiffres.';

  @override
  String get agentScripts => 'Scripts';

  @override
  String get attachPhotos => 'Photos';

  @override
  String get attachCamera => 'Prendre une photo';

  @override
  String get attachFiles => 'Fichiers';

  @override
  String get workers => 'Workers';

  @override
  String get subagents => 'Sous-agents';

  @override
  String get subagentDone => 'Terminé';

  @override
  String get subagentFailed => 'N\'a pas abouti';

  @override
  String get workersNone => 'Aucun worker en cours';

  @override
  String get workerRunning => 'Au travail';

  @override
  String workerSince(String time) {
    return 'Au travail depuis $time';
  }

  @override
  String workerSilent(String time) {
    return 'Aucun signe de vie depuis $time';
  }

  @override
  String workerFailed(String error) {
    return 'Échec : $error';
  }

  @override
  String kanbanReady(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n prêtes',
      one: '1 prête',
    );
    return '$_temp0';
  }

  @override
  String kanbanTodo(int n) {
    return '$n à faire';
  }

  @override
  String kanbanReview(int n) {
    return '$n en revue';
  }

  @override
  String kanbanBlocked(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n bloquées',
      one: '1 bloquée',
    );
    return '$_temp0';
  }

  @override
  String kanbanDone(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n terminées',
      one: '1 terminée',
    );
    return '$_temp0';
  }

  @override
  String get effort => 'Effort';

  @override
  String get effortAuto => 'Auto';

  @override
  String get effortMinimal => 'Minimal';

  @override
  String get effortLow => 'Faible';

  @override
  String get effortMedium => 'Moyen';

  @override
  String get effortHigh => 'Élevé';

  @override
  String get effortXhigh => 'Très élevé';

  @override
  String get effortMax => 'Maximal';

  @override
  String get usage => 'Utilisation';

  @override
  String usageDays(int n) {
    return '$n jours';
  }

  @override
  String get usageTokens => 'Tokens';

  @override
  String get usageCost => 'Coût estimé';

  @override
  String get usageSessions => 'Conversations';

  @override
  String get usageByModel => 'Par modèle';

  @override
  String usageCache(String n) {
    return 'Plus $n tokens lus depuis le cache';
  }

  @override
  String get memory => 'Mémoire';

  @override
  String get memoryAboutYou => 'Sur toi';

  @override
  String get memoryNotes => 'Ses notes';

  @override
  String get memoryEmpty => 'Hermes n\'a encore rien retenu.';

  @override
  String get memoryFooter =>
      'Hermes les écrit lui-même au fil des conversations. Corrige ce qui est faux, ou glisse vers la gauche pour l\'oublier.';

  @override
  String get memoryForget => 'Oublier';

  @override
  String get memoryForgetMessage => 'Hermes ne le saura plus.';

  @override
  String get searchInMessages => 'Dans les messages';

  @override
  String get kanban => 'Kanban';

  @override
  String get kanbanYourTurn => 'À toi de jouer';

  @override
  String get kanbanNothing => 'Rien ne t\'attend.';

  @override
  String get kanbanToReview => 'À vérifier';

  @override
  String get kanbanIsBlocked => 'Bloquée';

  @override
  String get kanbanDecision => 'Décision';

  @override
  String get kanbanBoard => 'Tableau';

  @override
  String get kanbanAdd => 'Nouvelle idée';

  @override
  String get kanbanTitle => 'Titre';

  @override
  String get kanbanDetails => 'Détails';

  @override
  String get kanbanAddFooter =>
      'Elle part en Triage, où le planificateur la reprend.';

  @override
  String get kanbanDescription => 'Description';

  @override
  String get kanbanSummary => 'Dernier résumé';

  @override
  String get kanbanHistory => 'Historique';

  @override
  String get kanbanReplyHint => 'Ta réponse…';

  @override
  String get kanbanApprove => 'Valider';

  @override
  String get kanbanSendBack => 'Renvoyer';

  @override
  String get kanbanSendBackMessage =>
      'La tâche repart en Prête, avec ton commentaire si tu en as écrit un.';

  @override
  String get kanbanReviewRequested => 'Revue demandée';

  @override
  String get kanbanCompleted => 'Terminée';

  @override
  String get language => 'Langue';

  @override
  String get folder => 'Dossier';

  @override
  String get folderTitle => 'Dossier de travail';

  @override
  String get folderHere => 'Cet ordinateur';

  @override
  String get folderServer => 'Serveur';

  @override
  String get folderHereHint =>
      'Hermes y lance ses commandes depuis le chat ; tu les valides.';

  @override
  String get folderServerHint =>
      'Hermes y travaille avec ses propres outils, sur le serveur.';

  @override
  String get folderChoose => 'Choisir';

  @override
  String get folderEmpty => 'Aucun dossier ici';

  @override
  String get folderOnHere => 'cet ordinateur';

  @override
  String get folderOnServer => 'serveur';

  @override
  String folderFailed(String error) {
    return 'Dossier non changé : $error';
  }

  @override
  String get modelsRecent => 'Récents';

  @override
  String get modelsMore => 'Plus de modèles';

  @override
  String get screen => 'Écran du bot';

  @override
  String get screenTakeOver => 'Prendre la main';

  @override
  String get screenHandBack => 'Rendre la main';

  @override
  String get screenBot =>
      'Le bot a la main. Prends-la pour cliquer et taper, par exemple pour résoudre un captcha.';

  @override
  String get screenYours => 'Tu as la main : le bot attend que tu la rendes.';

  @override
  String get screenSomeone => 'Quelqu\'un d\'autre a la main.';

  @override
  String get screenMissing =>
      'L\'écran du bot n\'est pas installé sur le serveur (hermes computer-use screen install).';

  @override
  String get screenLost => 'Connexion à l\'écran perdue.';

  @override
  String get screenRetry => 'Réessayer';

  @override
  String get screenType => 'Taper sur l\'écran';

  @override
  String screenFailed(String error) {
    return 'Échec : $error';
  }

  @override
  String get systemMachine => 'Machine';

  @override
  String get systemCpu => 'Processeur';

  @override
  String get systemMemory => 'Mémoire';

  @override
  String get systemDisk => 'Disque';

  @override
  String get systemUptime => 'Allumée depuis';

  @override
  String systemLoad(String load, String cores) {
    return 'charge $load sur $cores cœurs';
  }

  @override
  String systemSpace(String used, String total, int percent) {
    return '$used sur $total Go · $percent %';
  }

  @override
  String systemUptimeValue(int days, int hours) {
    return '$days j $hours h';
  }

  @override
  String get cronRunAgain => 'Relancer';

  @override
  String get cronFailed => 'Échec';

  @override
  String get cronSolveCaptcha => 'Le résoudre sur l\'écran du bot';

  @override
  String get screenOpen => 'Écran du bot · prendre la main';

  @override
  String get tools => 'Skills et MCP';

  @override
  String get toolsMcp => 'Serveurs MCP';

  @override
  String get toolsSkills => 'Skills';

  @override
  String get toolsSearch => 'Chercher un skill';

  @override
  String get toolsNone => 'Aucun skill ne correspond.';

  @override
  String get toolsNextChats =>
      'Un changement vaut pour les chats lancés après.';

  @override
  String get toolsMcpTest => 'Tester la connexion';

  @override
  String toolsMcpOk(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count outils',
      one: '1 outil',
    );
    return 'Connecté · $_temp0';
  }

  @override
  String get toolsMcpFailed => 'Connexion impossible';

  @override
  String toolsFailed(String error) {
    return 'Non modifié : $error';
  }

  @override
  String get gitTitle => 'Modifications';

  @override
  String get gitChanges => 'Fichiers modifiés';

  @override
  String get gitClean => 'Rien de modifié';

  @override
  String get gitNotRepo => 'Ce dossier n\'est pas un dépôt git.';

  @override
  String get gitMessage => 'Message du commit';

  @override
  String get gitCommit => 'Tout valider';

  @override
  String get gitShare => 'Partager';

  @override
  String get gitPush => 'Pousser';

  @override
  String gitPushCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count commits',
      one: '1 commit',
    );
    return 'Pousser $_temp0';
  }

  @override
  String get gitPr => 'Ouvrir une pull request';

  @override
  String gitPrSee(String number) {
    return 'Voir la pull request #$number';
  }

  @override
  String gitAhead(int count) {
    return '$count en avance';
  }

  @override
  String gitBehind(int count) {
    return '$count en retard';
  }

  @override
  String get gitCommitted => 'Validé';

  @override
  String get gitPushed => 'Poussé';

  @override
  String get gitPrOpened => 'Pull request ouverte';

  @override
  String gitFailed(String error) {
    return 'Git : $error';
  }

  @override
  String get voiceUnavailable =>
      'Dictée indisponible : autorise le micro et la reconnaissance vocale dans les réglages du système.';

  @override
  String get linkDown => 'Le serveur ne répond pas';

  @override
  String get linkDownVpn => 'Le serveur ne répond pas par le VPN';

  @override
  String get linkRetry => 'Réessayer';

  @override
  String get linkRestartVpn => 'Relancer le VPN';

  @override
  String get a11yMenu => 'Menu';

  @override
  String get a11yToBottom => 'Aller en bas';

  @override
  String get a11yEdit => 'Modifier';

  @override
  String get a11yResend => 'Renvoyer';

  @override
  String get a11yCopy => 'Copier';

  @override
  String get a11yRead => 'Lire à voix haute';

  @override
  String get a11yStopReading => 'Arrêter la lecture';

  @override
  String get a11yRegenerate => 'Régénérer';

  @override
  String get a11yRemove => 'Retirer';

  @override
  String get a11yCancelEdit => 'Annuler la modification';

  @override
  String get a11yAttach => 'Joindre des fichiers';

  @override
  String get a11yDictate => 'Dicter';

  @override
  String get a11yStopDictating => 'Arrêter la dictée';

  @override
  String get a11ySend => 'Envoyer';

  @override
  String get a11yParent => 'Dossier parent';

  @override
  String get a11yBack => 'Retour';

  @override
  String get a11yPickTarget => 'Choisir la destination';

  @override
  String get a11yShow => 'Afficher';

  @override
  String get a11yHide => 'Masquer';

  @override
  String usageCalls(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n appels',
      one: '1 appel',
    );
    return '$_temp0';
  }

  @override
  String usageInSessions(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n conversations',
      one: '1 conversation',
    );
    return '$_temp0';
  }

  @override
  String usageLastUsed(String time) {
    return 'il y a $time';
  }

  @override
  String get chatPin => 'Épingler';

  @override
  String get chatUnpin => 'Désépingler';

  @override
  String get chatArchive => 'Archiver';

  @override
  String get chatsPinned => 'Épinglées';

  @override
  String get chatsArchived => 'Archivées';

  @override
  String get chatUnarchive => 'Désarchiver';

  @override
  String get archivedNone => 'Aucune conversation archivée.';

  @override
  String chatActionFailed(String message) {
    return 'Impossible.\n$message';
  }

  @override
  String get subagentSteerHint => 'Une consigne pour ce sous-agent';

  @override
  String get subagentSteered =>
      'Consigne transmise : il la lira après son outil en cours.';

  @override
  String get subagentSteerRefused => 'Il n’accepte plus de consigne.';

  @override
  String get spawnTrees => 'Délégations passées';

  @override
  String get spawnTreesNone => 'Aucune délégation enregistrée pour l’instant.';

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
  String get imageCreate => 'Créer une image';

  @override
  String get imagePrompt => 'Décris l’image';

  @override
  String get imageSquare => 'Carrée';

  @override
  String get imageLandscape => 'Paysage';

  @override
  String get imagePortrait => 'Portrait';

  @override
  String get imageMake => 'Créer';

  @override
  String get imageMaking => 'Création de l’image… (jusqu’à une minute ou deux)';

  @override
  String get imageAttach => 'Joindre au message';

  @override
  String get imageAgain => 'Recommencer';

  @override
  String get imageSave => 'Enregistrer…';

  @override
  String get imageFailed => 'Le serveur n’a pas pu créer l’image.';

  @override
  String get chatsToday => 'Aujourd’hui';

  @override
  String get chatsYesterday => 'Hier';

  @override
  String get chatsWeek => '7 derniers jours';

  @override
  String get chatsMonth => '30 derniers jours';

  @override
  String get chatsOlder => 'Plus ancien';

  @override
  String get accent => 'Couleur d’accent';

  @override
  String get accentNeutral => 'Neutre';

  @override
  String get accentIndigo => 'Indigo';

  @override
  String get accentBlue => 'Bleu';

  @override
  String get accentTeal => 'Turquoise';

  @override
  String get accentGreen => 'Vert';

  @override
  String get accentOrange => 'Orange';

  @override
  String get accentPink => 'Rose';

  @override
  String get accentGold => 'Or';

  @override
  String get welcomeDay => 'Bonjour';

  @override
  String get welcomeEvening => 'Bonsoir';

  @override
  String get suggestRoutines => 'Résume les résultats de mes tâches planifiées';

  @override
  String get suggestSchedule => 'Programme une tâche chaque matin à 8 h : ';

  @override
  String get suggestKanban => 'Fais le point sur mon kanban';

  @override
  String get suggestWeb => 'Cherche sur le web et résume : ';

  @override
  String get welcomeNow => 'EN CE MOMENT';

  @override
  String welcomeSubagents(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n sous-agents au travail',
      one: '1 sous-agent au travail',
    );
    return '$_temp0';
  }

  @override
  String get welcomeRoutines => 'Résultats des tâches planifiées';

  @override
  String toolsEarlier(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n étapes avant',
      one: '1 étape avant',
    );
    return '$_temp0';
  }

  @override
  String get toolsFold => 'Replier';

  @override
  String get askClarify => 'Hermes a une question';

  @override
  String get askSudo => 'Hermes a besoin du mot de passe sudo';

  @override
  String get askSecret => 'Hermes a besoin d’un secret';

  @override
  String get askPassword => 'Mot de passe';

  @override
  String get askValue => 'Valeur';

  @override
  String get askAnswer => 'Ta réponse';

  @override
  String get askOther => 'Autre chose…';

  @override
  String get askSend => 'Envoyer';

  @override
  String get askSkip => 'Passer';

  @override
  String get backgroundTask => 'Tâche en arrière-plan';

  @override
  String get backgroundNext =>
      'Le prochain message part en tâche d’arrière-plan';

  @override
  String backgroundRunning(String task) {
    return 'En arrière-plan : $task';
  }

  @override
  String get backgroundLabel => 'arrière-plan';

  @override
  String backgroundDone(String chat) {
    return 'Tâche en arrière-plan terminée dans « $chat »';
  }

  @override
  String get backgroundOpen => 'Ouvrir';

  @override
  String get subagentModelInherit => 'Comme la conversation';

  @override
  String get curator => 'Curateur';

  @override
  String get curatorActive => 'Range les compétences';

  @override
  String get curatorOff => 'Désactivé dans la config du serveur';

  @override
  String curatorEvery(int hours) {
    return 'toutes les $hours h';
  }

  @override
  String curatorLast(String when) {
    return 'dernière fois le $when';
  }

  @override
  String get curatorMerge => 'L’IA les fusionne et les réécrit';

  @override
  String get curatorRun => 'Lancer maintenant';

  @override
  String get curatorStarted => 'Le curateur est lancé';

  @override
  String curatorFooter(int stale, int archive) {
    return 'Entre les conversations, une compétence qu’Hermes s’est écrite et qu’il n’a pas utilisée depuis $stale jours est marquée périmée, puis archivée après $archive jours. Le passage par l’IA fusionne et réécrit aussi les compétences proches, au prix d’un appel au modèle.';
  }

  @override
  String get codeCopied => 'Copié';

  @override
  String codeUnfold(int n) {
    return 'Afficher les $n lignes';
  }

  @override
  String get toBottomWriting => 'En train d’écrire';

  @override
  String toBottomNew(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n nouveaux messages',
      one: '1 nouveau message',
    );
    return '$_temp0';
  }
}
