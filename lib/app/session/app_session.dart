import 'package:flutter/material.dart';

import '../../coach/coach_repository.dart';
import '../../data/device_timezone.dart';
import '../../data/profile/profile_repository.dart';
import '../../data/profile/user_profile.dart';
import '../shell/app_destination.dart';
import 'local_day_clock.dart';
import 'metrics_controller.dart';

/// The signed-in user's profile; every change is saved to Supabase first.
class ProfileController extends ChangeNotifier {
  ProfileController(this._repository, this._profile);

  final ProfileRepository _repository;
  UserProfile _profile;
  bool _disposed = false;

  UserProfile get profile => _profile;

  Future<void> update(ProfileChanges changes) async {
    _profile = await _repository.update(changes);
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// Everything the signed-in part of the app shares: built by `AppGate` once
/// the profile and the catalog are loaded, disposed at sign-out.
class SignedInSession {
  SignedInSession({
    required this.userId,
    required this.profile,
    required this.metrics,
    required this.deviceTimezone,
    required this.day,
    required this.signOut,
    this.email,
    this.coach,
  });

  final String userId;
  final String? email;
  final ProfileController profile;
  final MetricsController metrics;
  final DeviceTimezone deviceTimezone;

  /// The device's "today", shared with [metrics]; pages that depend on it
  /// reload when it changes (`RevisionReload`).
  final LocalDayClock day;

  /// `null` when the coach cannot be reached at all (no Supabase).
  final CoachRepository? coach;
  final Future<void> Function() signOut;

  /// Section shown by the navigation bar.
  final destination = ValueNotifier(AppDestination.overview);

  /// Shows [section]; pages opened above the sections are closed first.
  void show(BuildContext context, AppDestination section) {
    Navigator.of(context).popUntil((route) => route.isFirst);
    destination.value = section;
  }

  void dispose() {
    profile.dispose();
    metrics.dispose();
    day.dispose();
    destination.dispose();
  }
}

/// Makes the [SignedInSession] available to every page, including the ones
/// pushed on the navigator (it is placed above it, in `MaterialApp.builder`).
class SessionScope extends InheritedWidget {
  const SessionScope({required this.session, required super.child, super.key});

  final SignedInSession? session;

  static SignedInSession of(BuildContext context) {
    final session = maybeOf(context);
    if (session == null) throw StateError('No signed-in session.');
    return session;
  }

  static SignedInSession? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SessionScope>()?.session;

  /// For callbacks (outside `build`): no dependency is registered.
  static SignedInSession read(BuildContext context) {
    final session = context
        .getInheritedWidgetOfExactType<SessionScope>()
        ?.session;
    if (session == null) throw StateError('No signed-in session.');
    return session;
  }

  @override
  bool updateShouldNotify(SessionScope oldWidget) =>
      session != oldWidget.session;
}
