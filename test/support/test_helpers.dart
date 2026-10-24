import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_training/app/evolup_app.dart';
import 'package:my_training/coach/coach_repository.dart';

import 'fake_auth_repository.dart';
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

Future<void> pumpApp(
  WidgetTester tester, {
  required FakeAuthRepository auth,
  required FakeProfileRepository profiles,
  MemoryDraftStore? drafts,
  CoachRepository? coach,
  Size size = const Size(400, 900),
}) async {
  useSurfaceSize(tester, size);
  await tester.pumpWidget(
    EvolupApp(
      authRepository: auth,
      profileRepository: profiles,
      draftStore: drafts ?? MemoryDraftStore(),
      coachRepository: coach,
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> tapKey(WidgetTester tester, String key) async {
  final finder = find.byKey(Key(key));
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}
