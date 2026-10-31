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
  String get cron => 'Tâches planifiées';

  @override
  String get cronEmpty => 'Aucune tâche planifiée.';

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
  String get cronFooter =>
      'Tâches que Hermes exécute tout seul. Tire vers le bas pour actualiser.';

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
}
