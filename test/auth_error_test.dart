import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_training/auth/auth_error.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('Supabase error codes map to interface failures', () {
    const expected = {
      'invalid_credentials': AuthFailure.invalidCredentials,
      'email_not_confirmed': AuthFailure.emailNotConfirmed,
      'user_already_exists': AuthFailure.accountExists,
      'email_exists': AuthFailure.accountExists,
      'otp_expired': AuthFailure.invalidCode,
      'weak_password': AuthFailure.weakPassword,
      'same_password': AuthFailure.samePassword,
      'over_email_send_rate_limit': AuthFailure.rateLimited,
      'over_request_rate_limit': AuthFailure.rateLimited,
      'signup_disabled': AuthFailure.signupDisabled,
      'email_provider_disabled': AuthFailure.signupDisabled,
      'session_not_found': AuthFailure.sessionExpired,
    };
    for (final MapEntry(key: code, value: failure) in expected.entries) {
      expect(
        classifyAuthError(AuthException('any wording', code: code)),
        failure,
        reason: code,
      );
    }
  });

  test('Network problems are reported as network failures', () {
    expect(
      classifyAuthError(AuthRetryableFetchException(message: 'offline')),
      AuthFailure.network,
    );
    expect(classifyAuthError(TimeoutException('slow')), AuthFailure.network);
  });

  test('Other errors stay generic and never claim success', () {
    expect(
      classifyAuthError(const AuthException('Too many', statusCode: '429')),
      AuthFailure.rateLimited,
    );
    expect(
      classifyAuthError(const AuthException('Invalid login credentials')),
      AuthFailure.invalidCredentials,
    );
    expect(
      classifyAuthError(const AuthException('Unexpected', code: 'new_code')),
      AuthFailure.unknown,
    );
    expect(classifyAuthError(StateError('bug')), AuthFailure.unknown);
  });

  test('OAuth returns are reported without claiming success', () {
    expect(
      classifyAuthError(const AuthException('denied', code: 'access_denied')),
      AuthFailure.oauthCancelled,
    );
    for (final code in [
      'bad_oauth_state',
      'flow_state_expired',
      'oauth_launch_failed',
    ]) {
      expect(
        classifyAuthError(AuthException('x', code: code)),
        AuthFailure.oauthFailed,
        reason: code,
      );
    }
    expect(
      classifyAuthError(const AuthPKCEGrantCodeExchangeError('x')),
      AuthFailure.oauthFailed,
    );
  });
}
