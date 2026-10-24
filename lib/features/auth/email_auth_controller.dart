import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../auth/auth_error.dart';
import '../../auth/auth_repository.dart';
import '../../auth/social_auth_provider.dart';

enum EmailAuthStep { credentials, code }

enum EmailAuthAction {
  signIn,
  signUp,
  requestCode,
  verifyCode,
  resendCode,
  resetPassword,
  social,
}

enum EmailAuthNotice { codeSent, codeResent, resetEmailSent, oauthPending }

/// Email authentication flow of the sign-in screen.
///
/// Signing in and creating an account are two explicit actions: a failed
/// sign-in never creates an account. Account creation always leads to the
/// same code step, whether or not the address is already registered, so the
/// interface never reveals which addresses have an account.
class EmailAuthController extends ChangeNotifier {
  EmailAuthController(
    this._auth, {
    this.resendDelay = const Duration(seconds: 60),
    this.socialPlatformSupported = true,
  });

  final AuthRepository? _auth;
  final Duration resendDelay;
  final bool socialPlatformSupported;

  EmailAuthStep _step = EmailAuthStep.credentials;
  EmailAuthAction? _busy;
  AuthFailure? _failure;
  EmailAuthNotice? _notice;
  String? _pendingEmail;
  int _resendSecondsLeft = 0;
  Timer? _resendTimer;
  bool _disposed = false;
  Set<SocialAuthProvider>? _enabledProviders;
  bool _providersUnknown = false;
  SocialAuthProvider? _socialProvider;

  EmailAuthStep get step => _step;
  EmailAuthAction? get busy => _busy;
  bool get isBusy => _busy != null;
  AuthFailure? get failure => _failure;
  EmailAuthNotice? get notice => _notice;
  String? get pendingEmail => _pendingEmail;
  int get resendSecondsLeft => _resendSecondsLeft;

  /// Provider of the OAuth sign-in being opened or awaited.
  SocialAuthProvider? get socialProvider => _socialProvider;

  SocialAvailability availabilityOf(SocialAuthProvider provider) {
    if (_auth == null) return SocialAvailability.notConfigured;
    if (!socialPlatformSupported) return SocialAvailability.unsupportedPlatform;
    if (_providersUnknown) return SocialAvailability.unknown;
    final enabled = _enabledProviders;
    if (enabled == null) return SocialAvailability.checking;
    return enabled.contains(provider)
        ? SocialAvailability.available
        : SocialAvailability.notConfigured;
  }

  /// Reads which OAuth providers are enabled in the Supabase project.
  Future<void> loadSocialProviders() async {
    final auth = _auth;
    if (auth == null || !socialPlatformSupported) return;
    try {
      _enabledProviders = await auth.enabledSocialProviders();
      _providersUnknown = false;
    } on Object {
      _providersUnknown = true;
    }
    _notify();
  }

  /// Opens the provider's page. The session (or a failure) comes back later
  /// through the auth state, never from this call.
  Future<void> signInWithProvider(SocialAuthProvider provider) {
    if (availabilityOf(provider) != SocialAvailability.available) {
      return Future.value();
    }
    return _run(EmailAuthAction.social, (auth) async {
      _socialProvider = provider;
      await auth.signInWithProvider(provider);
      _notice = EmailAuthNotice.oauthPending;
    });
  }

  Future<void> signIn({required String email, required String password}) =>
      _run(EmailAuthAction.signIn, (auth) async {
        _pendingEmail = email;
        await auth.signIn(email: email, password: password);
      });

  Future<void> signUp({required String email, required String password}) =>
      _run(EmailAuthAction.signUp, (auth) async {
        try {
          final hasSession = await auth.signUp(
            email: email,
            password: password,
          );
          if (hasSession) return;
        } on Object catch (error) {
          // Never reveal that an address is already registered.
          if (classifyAuthError(error) != AuthFailure.accountExists) rethrow;
        }
        _showCodeStep(email, EmailAuthNotice.codeSent);
      });

  /// Sends a code to an address whose sign-in failed only because it is not
  /// confirmed yet. Supabase returns that error only for a correct password.
  Future<void> requestCode() => _run(EmailAuthAction.requestCode, (auth) async {
    final email = _pendingEmail;
    if (email == null) return;
    await auth.resendSignUpCode(email);
    _showCodeStep(email, EmailAuthNotice.codeSent);
  });

  Future<void> verifyCode(String code) =>
      _run(EmailAuthAction.verifyCode, (auth) async {
        final email = _pendingEmail;
        if (email == null) return;
        await auth.verifySignUpCode(email: email, code: code);
      });

  Future<void> resendCode() async {
    if (_resendSecondsLeft > 0) return;
    await _run(EmailAuthAction.resendCode, (auth) async {
      final email = _pendingEmail;
      if (email == null) return;
      await auth.resendSignUpCode(email);
      _notice = EmailAuthNotice.codeResent;
      _startResendCooldown();
    });
  }

  Future<void> sendPasswordReset(String email) =>
      _run(EmailAuthAction.resetPassword, (auth) async {
        await auth.sendPasswordReset(email);
        _notice = EmailAuthNotice.resetEmailSent;
      });

  void changeEmail() {
    _resendTimer?.cancel();
    _resendSecondsLeft = 0;
    _step = EmailAuthStep.credentials;
    _failure = null;
    _notice = null;
    _notify();
  }

  void showFailure(AuthFailure failure) {
    _failure = failure;
    _notice = null;
    _notify();
  }

  void clearMessages() {
    if (_failure == null && _notice == null) return;
    _failure = null;
    _notice = null;
    _notify();
  }

  Future<void> _run(
    EmailAuthAction action,
    Future<void> Function(AuthRepository auth) body,
  ) async {
    if (_busy != null) return;
    final auth = _auth;
    if (auth == null) {
      showFailure(AuthFailure.notConfigured);
      return;
    }
    _busy = action;
    _failure = null;
    _notice = null;
    _notify();
    try {
      await body(auth);
    } on Object catch (error) {
      _failure = classifyAuthError(error);
    } finally {
      _busy = null;
      _notify();
    }
  }

  void _showCodeStep(String email, EmailAuthNotice notice) {
    _pendingEmail = email;
    _step = EmailAuthStep.code;
    _notice = notice;
    _startResendCooldown();
  }

  void _startResendCooldown() {
    _resendTimer?.cancel();
    _resendSecondsLeft = resendDelay.inSeconds;
    if (_resendSecondsLeft <= 0) return;
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _resendSecondsLeft--;
      if (_resendSecondsLeft <= 0) timer.cancel();
      _notify();
    });
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _resendTimer?.cancel();
    super.dispose();
  }
}
