import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_error.dart';
import 'social_auth_provider.dart';

abstract interface class AuthRepository {
  String? get currentUserId;
  Stream<String?> get userIdChanges;
  Stream<void> get passwordRecoveryEvents;

  /// Failures reported by Supabase outside a direct call, such as an OAuth
  /// sign-in cancelled or refused in the browser.
  Stream<AuthFailure> get authFailures;
  Future<void> signIn({required String email, required String password});

  /// Creates an account. Returns `true` only if Supabase opened a session,
  /// which happens when email confirmation is disabled on the project.
  Future<bool> signUp({required String email, required String password});

  /// Checks the sign-up code sent by email. Supabase verifies it server-side
  /// and opens a session only when it is valid.
  Future<void> verifySignUpCode({required String email, required String code});

  /// Asks Supabase to send a new sign-up code to an unconfirmed address.
  Future<void> resendSignUpCode(String email);
  Future<void> sendPasswordReset(String email);
  Future<void> updatePassword(String password);

  /// Providers enabled in the Supabase project (public Auth settings).
  Future<Set<SocialAuthProvider>> enabledSocialProviders();

  /// Opens the provider's sign-in page. The session arrives later through
  /// [userIdChanges], or a failure through [authFailures].
  Future<void> signInWithProvider(SocialAuthProvider provider);
  Future<void> signOut();
}

class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository(
    this._client, {
    required this.projectUrl,
    required this.publishableKey,
    this.redirectUrl,
  });

  final SupabaseClient _client;
  final String projectUrl;
  final String publishableKey;

  /// Where Supabase sends the user back after OAuth or a password-reset link.
  /// Must be allow-listed in Authentication → URL Configuration.
  final String? redirectUrl;

  @override
  String? get currentUserId => _client.auth.currentUser?.id;

  @override
  Stream<String?> get userIdChanges => _client.auth.onAuthStateChange
      .transform(
        StreamTransformer<AuthState, String?>.fromHandlers(
          handleData: (state, sink) => sink.add(state.session?.user.id),
          // Auth errors are reported through [authFailures] instead.
          handleError: (error, stackTrace, sink) {
            if (error is! AuthException) sink.addError(error, stackTrace);
          },
        ),
      )
      .distinct();

  @override
  Stream<void> get passwordRecoveryEvents => _client.auth.onAuthStateChange
      .where((state) => state.event == AuthChangeEvent.passwordRecovery)
      .map((_) {});

  @override
  Stream<AuthFailure> get authFailures =>
      _client.auth.onAuthStateChange.transform(
        StreamTransformer<AuthState, AuthFailure>.fromHandlers(
          handleData: (state, sink) {},
          handleError: (error, stackTrace, sink) {
            if (error is AuthException) sink.add(classifyAuthError(error));
          },
        ),
      );

  @override
  Future<void> signIn({required String email, required String password}) async {
    await _client.auth.signInWithPassword(email: email, password: password);
  }

  @override
  Future<bool> signUp({required String email, required String password}) async {
    final response = await _client.auth.signUp(
      email: email,
      password: password,
    );
    return response.session != null;
  }

  @override
  Future<void> verifySignUpCode({
    required String email,
    required String code,
  }) async {
    await _client.auth.verifyOTP(
      email: email,
      token: code,
      type: OtpType.signup,
    );
  }

  @override
  Future<void> resendSignUpCode(String email) async {
    await _client.auth.resend(email: email, type: OtpType.signup);
  }

  @override
  Future<void> sendPasswordReset(String email) =>
      _client.auth.resetPasswordForEmail(email, redirectTo: redirectUrl);

  @override
  Future<void> updatePassword(String password) async {
    await _client.auth.updateUser(UserAttributes(password: password));
  }

  @override
  Future<Set<SocialAuthProvider>> enabledSocialProviders() async {
    final response = await http
        .get(
          Uri.parse('$projectUrl/auth/v1/settings'),
          headers: {'apikey': publishableKey},
        )
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw http.ClientException(
        'Auth settings returned ${response.statusCode}',
      );
    }
    final settings = jsonDecode(response.body) as Map<String, dynamic>;
    final external = settings['external'] as Map<String, dynamic>? ?? {};
    return {
      for (final provider in SocialAuthProvider.values)
        if (external[provider.name] == true) provider,
    };
  }

  @override
  Future<void> signInWithProvider(SocialAuthProvider provider) async {
    final launched = await _client.auth.signInWithOAuth(
      provider.oauthProvider,
      redirectTo: redirectUrl,
      authScreenLaunchMode: kIsWeb
          ? LaunchMode.platformDefault
          : LaunchMode.externalApplication,
    );
    if (!launched) {
      throw const AuthException(
        'The sign-in page could not be opened',
        code: 'oauth_launch_failed',
      );
    }
  }

  @override
  Future<void> signOut() => _client.auth.signOut();
}
