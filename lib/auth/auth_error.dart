import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Authentication failures the interface distinguishes.
///
/// Classification relies on Supabase Auth error codes, not on the wording of
/// server messages, so that translations or wording changes do not break it.
enum AuthFailure {
  /// Wrong password or unknown address. Supabase deliberately does not say
  /// which one, to prevent account enumeration.
  invalidCredentials,

  /// The password was correct but the address has not been confirmed yet.
  emailNotConfirmed,

  /// The address is already registered. Only returned by Supabase when email
  /// confirmation is disabled; the interface must not reveal it.
  accountExists,

  /// The verification code is wrong or expired.
  invalidCode,
  weakPassword,
  samePassword,
  rateLimited,
  signupDisabled,
  sessionExpired,
  network,
  notConfigured,
  unknown,
}

AuthFailure classifyAuthError(Object error) {
  if (error is TimeoutException ||
      error.runtimeType.toString().contains('SocketException') ||
      error.runtimeType.toString().contains('ClientException')) {
    return AuthFailure.network;
  }
  if (error is AuthWeakPasswordException) return AuthFailure.weakPassword;
  if (error is AuthSessionMissingException) return AuthFailure.sessionExpired;
  // Raised by the client when the request never got a usable answer
  // (no connection, DNS failure, server unavailable).
  if (error is AuthRetryableFetchException) return AuthFailure.network;
  if (error is! AuthException) return AuthFailure.unknown;

  switch (error.code) {
    case 'invalid_credentials':
      return AuthFailure.invalidCredentials;
    case 'email_not_confirmed':
      return AuthFailure.emailNotConfirmed;
    case 'user_already_exists':
    case 'email_exists':
      return AuthFailure.accountExists;
    case 'otp_expired':
    case 'otp_disabled':
      return AuthFailure.invalidCode;
    case 'weak_password':
      return AuthFailure.weakPassword;
    case 'same_password':
      return AuthFailure.samePassword;
    case 'over_email_send_rate_limit':
    case 'over_request_rate_limit':
      return AuthFailure.rateLimited;
    case 'signup_disabled':
    case 'email_provider_disabled':
      return AuthFailure.signupDisabled;
    case 'session_not_found':
    case 'session_expired':
    case 'refresh_token_not_found':
      return AuthFailure.sessionExpired;
  }
  if (error.statusCode == '429') return AuthFailure.rateLimited;
  // Older Auth servers do not send codes for this case.
  if (error.message.toLowerCase().contains('invalid login credentials')) {
    return AuthFailure.invalidCredentials;
  }
  return AuthFailure.unknown;
}
