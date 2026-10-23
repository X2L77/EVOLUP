import 'package:supabase_flutter/supabase_flutter.dart';

abstract interface class AuthRepository {
  String? get currentUserId;
  Stream<String?> get userIdChanges;
  Stream<void> get passwordRecoveryEvents;
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
  Future<void> signOut();
}

class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository(this._client, {this.passwordResetRedirectTo});

  final SupabaseClient _client;
  final String? passwordResetRedirectTo;

  @override
  String? get currentUserId => _client.auth.currentUser?.id;

  @override
  Stream<String?> get userIdChanges => _client.auth.onAuthStateChange
      .map((state) => state.session?.user.id)
      .distinct();

  @override
  Stream<void> get passwordRecoveryEvents => _client.auth.onAuthStateChange
      .where((state) => state.event == AuthChangeEvent.passwordRecovery)
      .map((_) {});

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
  Future<void> sendPasswordReset(String email) => _client.auth
      .resetPasswordForEmail(email, redirectTo: passwordResetRedirectTo);

  @override
  Future<void> updatePassword(String password) async {
    await _client.auth.updateUser(UserAttributes(password: password));
  }

  @override
  Future<void> signOut() => _client.auth.signOut();
}
