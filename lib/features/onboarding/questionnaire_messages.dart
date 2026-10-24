import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

enum ProfileSaveFailure {
  network,
  sessionExpired,
  unavailable,
  rejected,
  unknown,
}

/// Classifies errors returned while saving the profile to Supabase.
ProfileSaveFailure classifyProfileSaveError(Object error) {
  if (error is TimeoutException ||
      error is AuthRetryableFetchException ||
      error.runtimeType.toString().contains('SocketException') ||
      error.runtimeType.toString().contains('ClientException')) {
    return ProfileSaveFailure.network;
  }
  if (error is AuthException) return ProfileSaveFailure.sessionExpired;
  if (error is PostgrestException) {
    return switch (error.code) {
      // Expired or invalid session token.
      'PGRST301' ||
      'PGRST302' ||
      'PGRST303' => ProfileSaveFailure.sessionExpired,
      // The table does not exist yet (migration not applied).
      '42P01' || 'PGRST205' || 'PGRST204' => ProfileSaveFailure.unavailable,
      // A database rule refused a value.
      '23514' || '23502' || '22P02' || '22003' => ProfileSaveFailure.rejected,
      _ => ProfileSaveFailure.unknown,
    };
  }
  return ProfileSaveFailure.unknown;
}

String profileSaveFailureMessage(ProfileSaveFailure failure) =>
    switch (failure) {
      ProfileSaveFailure.network =>
        'Enregistrement impossible : vérifiez votre accès à Internet, puis '
            'réessayez. Vos réponses sont conservées.',
      ProfileSaveFailure.sessionExpired =>
        'Votre session a expiré. Reconnectez-vous pour enregistrer votre '
            'profil. Vos réponses sont conservées sur cet appareil.',
      ProfileSaveFailure.unavailable =>
        'Le service de profil n’est pas encore disponible. Vos réponses sont '
            'conservées ; réessayez plus tard.',
      ProfileSaveFailure.rejected =>
        'Certaines réponses ont été refusées. Vérifiez-les, puis réessayez.',
      ProfileSaveFailure.unknown =>
        'Le profil n’a pas pu être enregistré. Réessayez dans quelques '
            'instants. Vos réponses sont conservées.',
    };
