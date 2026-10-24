import '../../auth/auth_error.dart';
import '../../auth/social_auth_provider.dart';
import 'email_auth_controller.dart';

const minimumPasswordLength = 8;

String authFailureMessage(AuthFailure failure) => switch (failure) {
  // Same message for a wrong password and an unknown address.
  AuthFailure.invalidCredentials => 'Adresse e-mail ou mot de passe incorrect.',
  AuthFailure.emailNotConfirmed =>
    'Votre adresse e-mail n’est pas encore confirmée. Recevez un code pour '
        'la vérifier.',
  AuthFailure.accountExists =>
    'Cette opération n’a pas pu aboutir. Si vous avez déjà un compte, '
        'connectez-vous ou utilisez « Mot de passe oublié ? ».',
  AuthFailure.invalidCode =>
    'Code incorrect ou expiré. Vérifiez-le ou demandez un nouveau code.',
  AuthFailure.weakPassword =>
    'Ce mot de passe est trop faible. Utilisez au moins '
        '$minimumPasswordLength caractères.',
  AuthFailure.samePassword =>
    'Choisissez un mot de passe différent de l’ancien.',
  AuthFailure.rateLimited =>
    'Trop de tentatives. Patientez quelques minutes avant de réessayer.',
  AuthFailure.signupDisabled =>
    'La création de compte est momentanément indisponible.',
  AuthFailure.sessionExpired =>
    'Votre lien de récupération a expiré. Demandez-en un nouveau.',
  AuthFailure.oauthCancelled =>
    'Connexion annulée. Réessayez ou utilisez votre adresse e-mail.',
  AuthFailure.oauthFailed =>
    'La connexion n’a pas pu aboutir. Réessayez ou utilisez votre adresse '
        'e-mail.',
  AuthFailure.network =>
    'Connexion impossible. Vérifiez votre accès à Internet et réessayez.',
  AuthFailure.notConfigured =>
    'La connexion n’est pas configurée sur cette version de l’application.',
  AuthFailure.unknown =>
    'Une erreur est survenue. Réessayez dans quelques instants.',
};

String authErrorMessage(Object error) =>
    authFailureMessage(classifyAuthError(error));

String authNoticeMessage(EmailAuthNotice notice) => switch (notice) {
  EmailAuthNotice.codeSent =>
    'Si cette adresse peut être utilisée, un code de vérification vient d’y '
        'être envoyé. Vous avez déjà un compte ? Modifiez l’adresse puis '
        'utilisez « Mot de passe oublié ? ».',
  EmailAuthNotice.codeResent =>
    'Si cette adresse peut être utilisée, un nouveau code vient d’y être '
        'envoyé.',
  EmailAuthNotice.resetEmailSent =>
    'Si un compte correspond à cette adresse, un lien de réinitialisation '
        'vient de lui être envoyé.',
  EmailAuthNotice.oauthPending =>
    'Terminez la connexion dans la fenêtre qui vient de s’ouvrir. Si vous '
        'l’avez fermée, vous pouvez réessayer.',
};

String socialUnavailableMessage(
  SocialAuthProvider provider,
  SocialAvailability availability,
) => switch (availability) {
  SocialAvailability.unknown =>
    'La disponibilité de la connexion avec ${provider.label} n’a pas pu être '
        'vérifiée. Vérifiez votre accès à Internet.',
  SocialAvailability.unsupportedPlatform =>
    'La connexion avec ${provider.label} n’est pas disponible sur cette '
        'plateforme. Utilisez votre adresse e-mail.',
  SocialAvailability.checking =>
    'Vérification de la connexion avec ${provider.label} en cours…',
  _ =>
    'La connexion avec ${provider.label} n’est pas encore configurée. '
        'Utilisez votre adresse e-mail.',
};

bool isValidEmail(String email) =>
    RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email);

/// Supabase lets projects choose a code length between 6 and 10 digits.
bool isValidCode(String code) => RegExp(r'^\d{6,10}$').hasMatch(code);
