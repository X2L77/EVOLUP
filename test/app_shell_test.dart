import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_training/app/shell/app_destination.dart';
import 'package:my_training/app/shell/evolup_nav_bar.dart';
import 'package:my_training/features/coach/coach_screen.dart';
import 'package:my_training/features/data/my_data_screen.dart';
import 'package:my_training/features/overview/overview_screen.dart';
import 'package:my_training/features/settings/settings_screen.dart';
import 'package:my_training/features/stats/stats_screen.dart';

import 'support/fake_coach_repository.dart';
import 'support/test_helpers.dart';

void main() {
  Finder navItem(String name) => find.byKey(Key('nav-$name'));

  void expectSelected(WidgetTester tester, AppDestination selected) {
    for (final destination in AppDestination.values) {
      final semantics = tester.widget<Semantics>(
        find
            .descendant(
              of: navItem(destination.name),
              matching: find.byType(Semantics),
            )
            .first,
      );
      expect(
        semantics.properties.selected,
        destination == selected,
        reason: '$destination',
      );
    }
  }

  testWidgets('five sections, in the validated order, the overview first', (
    tester,
  ) async {
    await pumpApp(tester, TestWorld(coach: FakeCoachRepository()));
    final labels = [
      'Vue d’ensemble',
      'Mes données',
      'Statistiques',
      'Polomix',
      'Paramètres',
    ];
    final xs = <double>[];
    for (final (i, destination) in AppDestination.values.indexed) {
      expect(destination.label, labels[i]);
      expect(
        find.descendant(
          of: find.byType(EvolupNavBar),
          matching: find.text(labels[i]),
        ),
        findsOneWidget,
      );
      xs.add(tester.getCenter(navItem(destination.name)).dx);
    }
    expect(xs, [...xs]..sort());
    expect(find.byType(OverviewScreen), findsOneWidget);
    expectSelected(tester, AppDestination.overview);
    // The other sections are only built when first opened.
    expect(find.byType(StatsScreen, skipOffstage: false), findsNothing);
    // No social section and no old sports pages.
    expect(find.text('Social'), findsNothing);
    expect(find.text('Coach IA'), findsNothing);
  });

  testWidgets('each section opens its page; back returns to the overview', (
    tester,
  ) async {
    await pumpApp(tester, TestWorld(coach: FakeCoachRepository()));
    final pages = {
      'data': MyDataScreen,
      'stats': StatsScreen,
      'polomix': CoachScreen,
      'settings': SettingsScreen,
    };
    for (final entry in pages.entries) {
      await openSection(tester, entry.key);
      expect(find.byType(entry.value), findsOneWidget, reason: entry.key);
      expectSelected(tester, AppDestination.values.byName(entry.key));
    }
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(OverviewScreen), findsOneWidget);
    expectSelected(tester, AppDestination.overview);
  });

  testWidgets('the conversation survives a section change', (tester) async {
    final coach = FakeCoachRepository();
    await pumpApp(tester, TestWorld(coach: coach));
    await openSection(tester, 'polomix');
    await tester.enterText(find.byKey(const Key('coach-input')), 'Bonjour');
    await tester.pump();
    await tester.tap(find.byKey(const Key('coach-send')));
    await tester.pumpAndSettle();
    await openSection(tester, 'data');
    await openSection(tester, 'polomix');
    expect(find.text('Réponse du faux coach'), findsOneWidget);
  });

  testWidgets('a small phone with large text shows the bar without overflow', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpApp(tester, TestWorld(), size: const Size(320, 600));
    expect(tester.takeException(), isNull);
    final bar = tester.getRect(find.byType(EvolupNavBar));
    expect(bar.left, greaterThanOrEqualTo(0));
    expect(bar.right, lessThanOrEqualTo(320));
    for (final destination in AppDestination.values) {
      final item = tester.getRect(navItem(destination.name));
      expect(item.left, greaterThanOrEqualTo(0));
      expect(item.right, lessThanOrEqualTo(320));
    }
  });

  testWidgets('the bar steps aside while the keyboard is open', (tester) async {
    await pumpApp(tester, TestWorld(coach: FakeCoachRepository()));
    expect(find.byKey(const Key('nav-overview')), findsOneWidget);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('nav-overview')), findsNothing);
    tester.view.resetViewInsets();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('nav-overview')), findsOneWidget);
  });
}
