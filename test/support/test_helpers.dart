import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_training/app/evolup_app.dart';
import 'package:my_training/app/session/app_session.dart';
import 'package:my_training/app/session/metrics_controller.dart';
import 'package:my_training/coach/coach_repository.dart';
import 'package:my_training/data/profile/user_profile.dart';
import 'package:my_training/theme/evolup_theme.dart';

import 'fake_auth_repository.dart';
import 'fake_metrics_repository.dart';
import 'fake_profile_repository.dart';

void useSurfaceSize(WidgetTester tester, Size size, {double bottomInset = 0}) {
  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = size
    ..viewInsets = FakeViewPadding(bottom: bottomInset);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetViewInsets);
}

/// Fakes of a signed-in user, ready to be pumped with [pumpApp].
class TestWorld {
  TestWorld({
    FakeAuthRepository? auth,
    FakeProfileRepository? profiles,
    FakeMetricsRepository? metrics,
    this.coach,
    this.deviceZone = 'Europe/Paris',
    bool signedIn = true,
  }) : auth =
           auth ??
           FakeAuthRepository(currentUserId: signedIn ? 'user-1' : null),
       profiles =
           profiles ??
           FakeProfileRepository(
             profile: const UserProfile(timezone: 'Europe/Paris'),
           ),
       metrics = metrics ?? FakeMetricsRepository();

  final FakeAuthRepository auth;
  final FakeProfileRepository profiles;
  final FakeMetricsRepository metrics;
  final CoachRepository? coach;
  final String? deviceZone;

  SessionServices get services => SessionServices(
    profiles: profiles,
    metrics: metrics,
    coach: coach,
    deviceTimezone: FakeDeviceTimezone(deviceZone),
  );
}

Future<void> pumpApp(
  WidgetTester tester,
  TestWorld world, {
  Size size = const Size(400, 900),
  bool disableAnimations = false,
}) async {
  useSurfaceSize(tester, size);
  if (disableAnimations) {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  }
  await tester.pumpWidget(
    EvolupApp(authRepository: world.auth, services: world.services),
  );
  await tester.pumpAndSettle();
}

Future<void> tapKey(WidgetTester tester, String key) async {
  final finder = find.byKey(Key(key));
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> openSection(WidgetTester tester, String name) =>
    tapKey(tester, 'nav-$name');

/// Pumps [screen] alone, inside a signed-in session built from [world]'s
/// fakes (as `AppGate` does after sign-in).
Future<SignedInSession> pumpInSession(
  WidgetTester tester,
  Widget screen, {
  TestWorld? world,
  Size size = const Size(400, 900),
}) async {
  final w = world ?? TestWorld();
  useSurfaceSize(tester, size);
  final profile = await w.profiles.loadOrCreate(timezone: 'Europe/Paris');
  final metrics = MetricsController(w.metrics);
  await metrics.load();
  final session = SignedInSession(
    userId: 'user-1',
    email: 'athlete@evolup.fr',
    profile: ProfileController(w.profiles, profile),
    metrics: metrics,
    deviceTimezone: FakeDeviceTimezone(w.deviceZone),
    coach: w.coach,
    signOut: () async {},
  );
  await tester.pumpWidget(
    MaterialApp(
      theme: buildEvolupTheme(),
      locale: const Locale('fr'),
      supportedLocales: const [Locale('fr')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      builder: (context, child) =>
          SessionScope(session: session, child: child!),
      home: screen,
    ),
  );
  await tester.pumpAndSettle();
  return session;
}
