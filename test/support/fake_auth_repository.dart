import 'dart:async';

import 'package:my_training/auth/auth_repository.dart';

/// In-memory auth repository. Tests never contact Supabase.
class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({this.currentUserId});

  @override
  String? currentUserId;
  final changes = StreamController<String?>.broadcast(sync: true);
  final recoveryChanges = StreamController<void>.broadcast(sync: true);
  Object? signInError;
  Object? signUpError;
  Object? verifyError;
  Object? resendError;
  Completer<void>? signInCompleter;
  bool signUpHasSession = false;
  int signInCalls = 0;
  int signUpCalls = 0;
  int verifyCalls = 0;
  int resendCalls = 0;
  int resetCalls = 0;
  int signOutCalls = 0;
  int passwordUpdates = 0;
  String? lastVerifiedEmail;
  String? lastVerifiedCode;
  String? lastResentEmail;

  @override
  Stream<String?> get userIdChanges => changes.stream;

  @override
  Stream<void> get passwordRecoveryEvents => recoveryChanges.stream;

  void _openSession() {
    currentUserId = 'user-1';
    changes.add(currentUserId);
  }

  @override
  Future<void> signIn({required String email, required String password}) async {
    signInCalls++;
    await signInCompleter?.future;
    if (signInError case final error?) throw error;
    _openSession();
  }

  @override
  Future<bool> signUp({required String email, required String password}) async {
    signUpCalls++;
    if (signUpError case final error?) throw error;
    if (signUpHasSession) _openSession();
    return signUpHasSession;
  }

  @override
  Future<void> verifySignUpCode({
    required String email,
    required String code,
  }) async {
    verifyCalls++;
    lastVerifiedEmail = email;
    lastVerifiedCode = code;
    if (verifyError case final error?) throw error;
    _openSession();
  }

  @override
  Future<void> resendSignUpCode(String email) async {
    resendCalls++;
    lastResentEmail = email;
    if (resendError case final error?) throw error;
  }

  @override
  Future<void> sendPasswordReset(String email) async {
    resetCalls++;
  }

  @override
  Future<void> updatePassword(String password) async {
    passwordUpdates++;
  }

  @override
  Future<void> signOut() async {
    signOutCalls++;
    currentUserId = null;
    changes.add(null);
  }

  Future<void> dispose() async {
    await changes.close();
    await recoveryChanges.close();
  }
}
