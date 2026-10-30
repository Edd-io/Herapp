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
  String get modelsNoServer =>
      'Renseigne l\'adresse de ton serveur Hermes dans les réglages pour voir ses modèles.';

  @override
  String modelsFailed(String message) {
    return 'Impossible de charger les modèles du serveur.\n$message';
  }

  @override
  String get modelsNone => 'Aucun modèle n\'est configuré sur le serveur.';

  @override
  String get modelsRestart =>
      'Hermes a été mis à jour mais tourne encore sur l\'ancienne version. Redémarre le serveur Hermes pour voir ses modèles.';
}
