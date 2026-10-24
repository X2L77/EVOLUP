import '../../coach/coach_error.dart';
import '../../coach/coach_repository.dart';

/// French message for a coach failure. Never reveals internal details.
String coachFailureMessage(CoachFailure failure) => switch (failure) {
  CoachFailure.notSignedIn =>
    'Votre session a expiré. Reconnectez-vous pour écrire au coach.',
  CoachFailure.invalidMessage => 'Ce message ne peut pas être envoyé.',
  CoachFailure.messageTooLong =>
    'Votre message est trop long ($coachMaxMessageLength caractères '
        'maximum).',
  CoachFailure.rateLimited =>
    'Vous envoyez beaucoup de messages. Patientez un instant, puis '
        'réessayez.',
  CoachFailure.notConfigured =>
    'Le coach IA n’est pas encore activé. Réessayez plus tard.',
  CoachFailure.quotaReached =>
    'Le coach a atteint sa limite d’utilisation. Réessayez plus tard.',
  CoachFailure.rejected =>
    'Le coach n’a pas pu traiter ce message. Essayez de le reformuler.',
  CoachFailure.unavailable =>
    'Le coach est momentanément indisponible. Réessayez dans quelques '
        'instants.',
  CoachFailure.timeout => 'Le coach a mis trop de temps à répondre.',
  CoachFailure.network =>
    'Connexion impossible. Vérifiez votre réseau, puis réessayez.',
  CoachFailure.badResponse => 'La réponse du coach est inutilisable.',
  CoachFailure.unknown => 'Une erreur inattendue est survenue.',
};
