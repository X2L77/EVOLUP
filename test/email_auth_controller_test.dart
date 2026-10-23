import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_training/auth/auth_error.dart';
import 'package:my_training/features/auth/email_auth_controller.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/fake_auth_repository.dart';

void main() {
  late FakeAuthRepository auth;
  late EmailAuthController controller;

  setUp(() {
    auth = FakeAuthRepository();
    controller = EmailAuthController(auth);
  });

  tearDown(() async {
    controller.dispose();
    await auth.dispose();
  });

  test(
    'sign-in failures never trigger sign-up, resend or verification',
    () async {
      final failures = <Object, AuthFailure>{
        const AuthException('x', code: 'invalid_credentials'):
            AuthFailure.invalidCredentials,
        const AuthException('x', code: 'email_not_confirmed'):
            AuthFailure.emailNotConfirmed,
        AuthRetryableFetchException(message: 'offline'): AuthFailure.network,
        TimeoutException('slow'): AuthFailure.network,
      };
      for (final MapEntry(key: error, value: failure) in failures.entries) {
        auth.signInError = error;
        await controller.signIn(email: 'a@b.fr', password: 'whatever');
        expect(controller.failure, failure);
        expect(controller.step, EmailAuthStep.credentials);
      }
      expect(auth.signUpCalls, 0);
      expect(auth.resendCalls, 0);
      expect(auth.verifyCalls, 0);
    },
  );

  test('sign-up shows the code step and starts the resend delay', () async {
    await controller.signUp(email: 'new@b.fr', password: 'password-123');
    expect(auth.signUpCalls, 1);
    expect(controller.step, EmailAuthStep.code);
    expect(controller.notice, EmailAuthNotice.codeSent);
    expect(controller.pendingEmail, 'new@b.fr');
    expect(controller.resendSecondsLeft, 60);
    await controller.resendCode();
    expect(auth.resendCalls, 0);
  });

  test('an existing address gives exactly the same result', () async {
    auth.signUpError = const AuthException('x', code: 'user_already_exists');
    await controller.signUp(email: 'old@b.fr', password: 'password-123');
    expect(controller.step, EmailAuthStep.code);
    expect(controller.notice, EmailAuthNotice.codeSent);
    expect(controller.failure, isNull);
  });

  test('sign-up errors other than an existing address are shown', () async {
    auth.signUpError = const AuthException('x', code: 'weak_password');
    await controller.signUp(email: 'new@b.fr', password: 'password-123');
    expect(controller.step, EmailAuthStep.credentials);
    expect(controller.failure, AuthFailure.weakPassword);
  });

  test('the code is sent to Supabase with the pending address', () async {
    await controller.signUp(email: 'new@b.fr', password: 'password-123');
    auth.verifyError = const AuthException('x', code: 'otp_expired');
    await controller.verifyCode('000000');
    expect(controller.failure, AuthFailure.invalidCode);
    expect(auth.currentUserId, isNull);

    auth.verifyError = null;
    await controller.verifyCode('123456');
    expect(auth.lastVerifiedEmail, 'new@b.fr');
    expect(auth.lastVerifiedCode, '123456');
    expect(auth.currentUserId, 'user-1');
  });

  test('without configuration actions fail explicitly', () async {
    final unconfigured = EmailAuthController(null);
    await unconfigured.signIn(email: 'a@b.fr', password: 'password-123');
    expect(unconfigured.failure, AuthFailure.notConfigured);
    await unconfigured.signUp(email: 'a@b.fr', password: 'password-123');
    expect(unconfigured.step, EmailAuthStep.credentials);
    unconfigured.dispose();
  });
}
