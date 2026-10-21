import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:my_training/main.dart';

void _useSurfaceSize(WidgetTester tester, Size size, {double bottomInset = 0}) {
  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = size
    ..viewInsets = FakeViewPadding(bottom: bottomInset);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetViewInsets);
}

Finder get _pageScrollable => find.descendant(
  of: find.byType(SingleChildScrollView),
  matching: find.byType(Scrollable),
    ).first;

void main() {
  testWidgets('Welcome screen fields remain editable and password is hidden', (
    tester,
  ) async {
    _useSurfaceSize(tester, const Size(400, 760));
    await tester.pumpWidget(const MyApp());

    expect(find.text('Welcome'), findsOneWidget);
    expect(find.text('Sign in / Login'), findsOneWidget);
    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Mot de passe'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(2));

    await tester.enterText(find.byType(TextField).first, 'test@example.com');
    await tester.enterText(find.byType(TextField).last, 'test-password');
    await tester.pump();

    expect(find.text('test@example.com'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField).last).obscureText,
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Short phone screen keeps the card within the viewport', (
    tester,
  ) async {
    const screenSize = Size(320, 480);
    _useSurfaceSize(tester, screenSize);
    await tester.pumpWidget(const MyApp());

    final cardRect = tester.getRect(find.byKey(const ValueKey('sign-in-card')));
    final scrollable = tester.state<ScrollableState>(_pageScrollable).position;

    expect(cardRect.left, greaterThanOrEqualTo(0));
    expect(cardRect.right, lessThanOrEqualTo(screenSize.width));
    expect(scrollable.maxScrollExtent, greaterThan(0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Narrow landscape phone can scroll without layout overflow', (
    tester,
  ) async {
    const screenSize = Size(667, 375);
    _useSurfaceSize(tester, screenSize);
    await tester.pumpWidget(const MyApp());

    final cardRect = tester.getRect(find.byKey(const ValueKey('sign-in-card')));
    final scrollable = tester.state<ScrollableState>(_pageScrollable).position;

    expect(cardRect.left, greaterThanOrEqualTo(0));
    expect(cardRect.right, lessThanOrEqualTo(screenSize.width));
    expect(scrollable.maxScrollExtent, greaterThan(0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Desktop screen centers the card at a readable maximum width', (
    tester,
  ) async {
    const screenSize = Size(1280, 800);
    _useSurfaceSize(tester, screenSize);
    await tester.pumpWidget(const MyApp());

    final cardRect = tester.getRect(find.byKey(const ValueKey('sign-in-card')));

    expect(cardRect.width, lessThanOrEqualTo(440));
    expect(cardRect.center.dx, closeTo(screenSize.width / 2, 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Password field can be scrolled into view with the keyboard open',
    (tester) async {
      _useSurfaceSize(tester, const Size(320, 640), bottomInset: 280);
      await tester.pumpWidget(const MyApp());

      final scrollableState = tester.state<ScrollableState>(_pageScrollable);
      expect(scrollableState.position.maxScrollExtent, greaterThan(0));

      final passwordField = find.byType(TextField).last;
      await tester.ensureVisible(passwordField);
      await tester.pumpAndSettle();

      final fieldRect = tester.getRect(passwordField);
      final viewportRect = tester.getRect(_pageScrollable);
      expect(fieldRect.top, greaterThanOrEqualTo(viewportRect.top));
      expect(fieldRect.bottom, lessThanOrEqualTo(viewportRect.bottom));
      expect(tester.takeException(), isNull);
    },
  );
}
