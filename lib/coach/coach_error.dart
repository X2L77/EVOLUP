import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Why a coach message could not be answered.
enum CoachFailure {
  notSignedIn,
  invalidMessage,
  messageTooLong,
  rateLimited,
  notConfigured,
  quotaReached,
  rejected,
  unavailable,
  timeout,
  network,
  badResponse,
  unknown;

  /// Whether sending the same message again may succeed.
  bool get isRetryable => switch (this) {
    rateLimited ||
    quotaReached ||
    unavailable ||
    timeout ||
    network ||
    badResponse ||
    unknown => true,
    _ => false,
  };
}

class CoachException implements Exception {
  const CoachException(this.failure);

  final CoachFailure failure;

  @override
  String toString() => 'CoachException($failure)';
}

/// Classifies an error of the coach-chat Edge Function by its error code
/// (supabase/functions/coach-chat/README.md), then by HTTP status.
CoachFailure classifyCoachError(Object error) {
  if (error is CoachException) return error.failure;
  if (error is TimeoutException) return CoachFailure.timeout;
  if (error is AuthException) return CoachFailure.notSignedIn;
  if (error is FunctionsFetchException) return CoachFailure.network;
  if (error is FunctionsRelayException) return CoachFailure.unavailable;
  if (error is FunctionException) {
    return _failureForCode(_errorCode(error.details)) ??
        _failureForStatus(error.status);
  }
  return CoachFailure.unknown;
}

String? _errorCode(Object? details) {
  if (details is! Map) return null;
  final error = details['error'];
  if (error is! Map) return null;
  final code = error['code'];
  return code is String ? code : null;
}

CoachFailure? _failureForCode(String? code) => switch (code) {
  'unauthorized' => CoachFailure.notSignedIn,
  'message_too_long' => CoachFailure.messageTooLong,
  'empty_message' ||
  'invalid_request' ||
  'invalid_json' ||
  'unsupported_kind' ||
  'payload_too_large' => CoachFailure.invalidMessage,
  'rate_limited' => CoachFailure.rateLimited,
  'coach_not_configured' => CoachFailure.notConfigured,
  'coach_quota_reached' => CoachFailure.quotaReached,
  'coach_rejected' => CoachFailure.rejected,
  'coach_timeout' => CoachFailure.timeout,
  'coach_bad_response' => CoachFailure.badResponse,
  'coach_unavailable' || 'origin_not_allowed' => CoachFailure.unavailable,
  _ => null,
};

CoachFailure _failureForStatus(int status) => switch (status) {
  401 => CoachFailure.notSignedIn,
  404 => CoachFailure.notConfigured,
  429 => CoachFailure.rateLimited,
  504 => CoachFailure.timeout,
  >= 500 => CoachFailure.unavailable,
  _ => CoachFailure.unknown,
};
