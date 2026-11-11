import '../../coach/coach_error.dart';
import '../../coach/coach_repository.dart';

/// French message for a Polomix failure. Never reveals internal details.
String coachFailureMessage(CoachFailure failure) => switch (failure) {
  CoachFailure.notSignedIn =>
    'Votre session a expiré. Reconnectez-vous pour écrire à Polomix.',
  CoachFailure.invalidMessage => 'Ce message ne peut pas être envoyé.',
  CoachFailure.messageTooLong =>
    'Votre message est trop long ($coachMaxMessageLength caractères '
        'maximum).',
  CoachFailure.rateLimited =>
    'Vous envoyez beaucoup de messages. Patientez un instant, puis '
        'réessayez.',
  CoachFailure.notConfigured =>
    'Polomix n’est pas encore activé sur le serveur. Vos données et vos '
        'saisies restent accessibles.',
  CoachFailure.quotaReached =>
    'Polomix a atteint sa limite d’utilisation. Réessayez plus tard.',
  CoachFailure.rejected =>
    'Polomix n’a pas pu traiter ce message. Essayez de le reformuler.',
  CoachFailure.unavailable =>
    'Polomix est momentanément indisponible. Vos données et vos saisies '
        'restent accessibles.',
  CoachFailure.timeout => 'Polomix a mis trop de temps à répondre.',
  CoachFailure.network =>
    'Connexion impossible. Vérifiez votre réseau, puis réessayez.',
  CoachFailure.badResponse => 'La réponse de Polomix est inutilisable.',
  CoachFailure.unknown => 'Une erreur inattendue est survenue.',
};
