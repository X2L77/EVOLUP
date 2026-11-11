import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Why a database operation failed, from the stable codes raised by the
/// EVOLUP functions (SPEC_PROJECT.md §8.3), PostgREST and the network.
///
/// Reads and writes are told apart: a write whose answer never came back
/// may have been applied, so it is [writeUncertain], never "nothing saved".
enum DataFailure {
  /// No connection to the server (read, or write context unknown).
  network,

  /// The server did not answer in time (read).
  timeout,

  /// The server answered with an error (read, or context unknown).
  server,

  /// Write: the connection could not even be opened, nothing was sent.
  writeNotSent,

  /// Write: the server answered that it did not apply it.
  writeFailed,

  /// Write: sent, but its outcome could not be confirmed (timeout,
  /// connection lost, gateway error, unreadable answer).
  writeUncertain,

  sessionExpired,

  /// Refused by the access rules (RLS, privileges, Polomix context).
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
  const DataException(this.failure, {this.settled});

  final DataFailure failure;

  /// For a write the client stopped waiting for ([DataFailure.writeUncertain]
  /// after a timeout): completes once that request has ended on the network
  /// side, successfully or not. PostgREST commits before answering, so a
  /// late answer means the server is done with it. Its result is unknown
  /// and ignored; only the server's data says what happened.
  final Future<void>? settled;

  String get message => dataFailureMessage(failure);

  @override
  String toString() => 'DataException($failure)';
}

/// Failure of an error whose operation is a read, or unknown. Never claims
/// anything about a write.
DataFailure classifyDataError(Object error) {
  if (error is DataException) return error.failure;
  if (error is TimeoutException) return DataFailure.timeout;
  if (error is AuthException) return DataFailure.sessionExpired;
  // An answer that does not have the expected shape: a wrong type or a
  // missing field while reading it.
  if (error is FormatException || error is TypeError) {
    return DataFailure.badResponse;
  }
  if (error is PostgrestException) return _classifyPostgrest(error);
  if (_isConnectionError(error)) return DataFailure.network;
  return DataFailure.unknown;
}

/// Failure of an error raised by a write: only what the server explicitly
/// refused is a confirmed failure; everything else may have been applied.
DataFailure classifyWriteError(Object error) {
  final failure = classifyDataError(error);
  return switch (failure) {
    // Already decided for a write (nested guard).
    DataFailure.writeNotSent ||
    DataFailure.writeFailed ||
    DataFailure.writeUncertain => failure,
    DataFailure.network =>
      _connectionNeverOpened(error)
          ? DataFailure.writeNotSent
          : DataFailure.writeUncertain,
    // The server accepted the request but its answer is unusable, or the
    // client stopped waiting: the write may have been applied.
    DataFailure.timeout ||
    DataFailure.badResponse ||
    DataFailure.unknown => DataFailure.writeUncertain,
    DataFailure.server =>
      _isGatewayError(error)
          ? DataFailure.writeUncertain
          : DataFailure.writeFailed,
    _ => failure,
  };
}

DataFailure _classifyPostgrest(PostgrestException error) {
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
    _ => DataFailure.server,
  };
}

/// A PostgREST error without a database answer: an HTTP status from a proxy
/// or gateway (502, 503, 504…), as postgrest-dart reports a non-JSON body.
/// The database may still have run the request.
bool _isGatewayError(Object error) =>
    error is PostgrestException &&
    RegExp(r'^5\d\d$').hasMatch(error.code ?? '');

/// The request could not reach the server. `http` wraps socket errors in a
/// [http.ClientException] on every platform (`dart:io` is not available on
/// the web, so its types are matched by name).
bool _isConnectionError(Object error) {
  if (error is http.ClientException) return true;
  final type = error.runtimeType.toString();
  return type == 'SocketException' ||
      type == 'HandshakeException' ||
      type == 'HttpException';
}

/// Errors raised before any byte of the request left the device (DNS,
/// refused connection, no route). Anything else, including the web's
/// opaque "XMLHttpRequest error", may happen after the request was sent.
bool _connectionNeverOpened(Object error) {
  final text = error.toString();
  const markers = [
    'Failed host lookup',
    'Connection refused',
    'refused the network connection',
    'Network is unreachable',
    'No route to host',
  ];
  return markers.any(text.contains);
}

/// Safe text for the logs: the error type and, for PostgREST, its code.
/// Never the message, the URL or the values (they may hold user data).
String describeDataErrorForLog(Object error) => switch (error) {
  PostgrestException(:final code) => 'PostgrestException(code: $code)',
  DataException(:final failure) => 'DataException($failure)',
  _ => error.runtimeType.toString(),
};

String dataErrorMessage(Object error) =>
    dataFailureMessage(classifyDataError(error));

String dataFailureMessage(DataFailure failure) => switch (failure) {
  DataFailure.network =>
    'Connexion impossible. Vérifiez votre réseau, puis réessayez.',
  DataFailure.timeout =>
    'Le serveur met trop de temps à répondre. Réessayez dans un instant.',
  DataFailure.server =>
    'Le serveur a rencontré un problème. Réessayez dans un instant.',
  DataFailure.writeNotSent =>
    'Connexion impossible : la modification n’a pas été envoyée et rien n’a '
        'été enregistré. Vérifiez votre réseau, puis réessayez.',
  DataFailure.writeFailed =>
    'Le serveur n’a pas pu enregistrer la modification : rien n’a été '
        'changé. Réessayez dans un instant.',
  DataFailure.writeUncertain =>
    'La connexion a été interrompue avant la confirmation du serveur : la '
        'modification a peut-être été enregistrée. Vérifiez vos données avant '
        'de réessayer.',
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
  DataFailure.badResponse =>
    'Réponse du serveur inutilisable. Réessayez dans un instant.',
  DataFailure.unknown => 'Une erreur inattendue est survenue. Réessayez.',
};
