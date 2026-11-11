import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Why a database operation failed, from the stable codes raised by the
/// EVOLUP functions (SPEC_PROJECT.md §8.3) and PostgREST.
enum DataFailure {
  network,
  sessionExpired,
  notAllowed,
  alreadyTracked,
  metricNotTracked,
  metricNotActive,
  metricRetired,
  valueOutOfRange,
  valuePrecision,
  valueInvalid,
  unitMismatch,
  invalidTimezone,
  dateInFuture,
  dateTooOld,
  dailyEntryLimit,
  dailySumExceeded,
  dayNotFound,
  invalidPeriod,
  badResponse,
  unknown,
}

class DataException implements Exception {
  const DataException(this.failure);

  final DataFailure failure;

  String get message => dataFailureMessage(failure);

  @override
  String toString() => 'DataException($failure)';
}

DataFailure classifyDataError(Object error) {
  if (error is DataException) return error.failure;
  if (error is TimeoutException) return DataFailure.network;
  if (error is AuthException) return DataFailure.sessionExpired;
  if (error is FormatException) return DataFailure.badResponse;
  if (error is PostgrestException) {
    final byMessage = switch (error.message) {
      'not_authenticated' => DataFailure.sessionExpired,
      'coach_cannot_write' => DataFailure.notAllowed,
      'metric_not_tracked' => DataFailure.metricNotTracked,
      'metric_not_active' => DataFailure.metricNotActive,
      'metric_retired' => DataFailure.metricRetired,
      'value_out_of_range' => DataFailure.valueOutOfRange,
      'value_precision' => DataFailure.valuePrecision,
      'value_invalid' || 'missing_parameter' => DataFailure.valueInvalid,
      'unit_mismatch' => DataFailure.unitMismatch,
      'invalid_timezone' => DataFailure.invalidTimezone,
      'date_in_future' => DataFailure.dateInFuture,
      'date_too_old' => DataFailure.dateTooOld,
      'daily_entry_limit' => DataFailure.dailyEntryLimit,
      'daily_sum_exceeded' => DataFailure.dailySumExceeded,
      'day_not_found' => DataFailure.dayNotFound,
      'invalid_period' ||
      'invalid_bucket' ||
      'too_many_points' => DataFailure.invalidPeriod,
      _ => null,
    };
    if (byMessage != null) return byMessage;
    return switch (error.code) {
      '23505' => DataFailure.alreadyTracked,
      '42501' => DataFailure.notAllowed,
      'PGRST301' || 'PGRST302' || 'PGRST303' => DataFailure.sessionExpired,
      _ => DataFailure.unknown,
    };
  }
  final text = error.toString();
  if (text.contains('SocketException') ||
      text.contains('ClientException') ||
      text.contains('XMLHttpRequest') ||
      text.contains('Failed host lookup') ||
      text.contains('Connection')) {
    return DataFailure.network;
  }
  return DataFailure.unknown;
}

String dataErrorMessage(Object error) =>
    dataFailureMessage(classifyDataError(error));

String dataFailureMessage(DataFailure failure) => switch (failure) {
  DataFailure.network =>
    'Connexion impossible. Vérifiez votre réseau, puis réessayez. '
        'Rien n’a été enregistré.',
  DataFailure.sessionExpired =>
    'Votre session a expiré. Reconnectez-vous, puis réessayez.',
  DataFailure.notAllowed => 'Cette action n’est pas autorisée.',
  DataFailure.alreadyTracked =>
    'Cet indicateur fait déjà partie de vos données.',
  DataFailure.metricNotTracked =>
    'Cet indicateur ne fait pas partie de vos données.',
  DataFailure.metricNotActive =>
    'Cet indicateur est retiré de votre liste. Réactivez-le pour enregistrer '
        'une valeur.',
  DataFailure.metricRetired =>
    'Cet indicateur n’est plus proposé par EVOLUP : son historique reste '
        'consultable, mais aucune nouvelle valeur ne peut être ajoutée.',
  DataFailure.valueOutOfRange =>
    'Cette valeur est en dehors des limites autorisées pour cet indicateur.',
  DataFailure.valuePrecision => 'Cette valeur a trop de décimales.',
  DataFailure.valueInvalid => 'Cette valeur est invalide.',
  DataFailure.unitMismatch =>
    'L’unité ne correspond plus au catalogue. Mettez l’application à jour.',
  DataFailure.invalidTimezone =>
    'Le fuseau horaire n’est pas reconnu. Vérifiez-le dans les Paramètres.',
  DataFailure.dateInFuture => 'La date ne peut pas être dans le futur.',
  DataFailure.dateTooOld => 'Cette date est trop ancienne.',
  DataFailure.dailyEntryLimit =>
    'Limite de 200 saisies par jour atteinte pour cet indicateur.',
  DataFailure.dailySumExceeded =>
    'Le total de cette journée dépasserait la limite autorisée.',
  DataFailure.dayNotFound => 'Cette journée n’existe plus.',
  DataFailure.invalidPeriod => 'Cette période n’est pas valide.',
  DataFailure.badResponse => 'Réponse du serveur inutilisable.',
  DataFailure.unknown => 'Une erreur est survenue. Réessayez.',
};
