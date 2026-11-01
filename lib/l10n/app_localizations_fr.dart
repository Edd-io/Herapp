// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

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
}
