import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_training/app/widgets/evolup_background.dart';
import 'package:my_training/app/widgets/evolup_page.dart';
import 'package:my_training/app/widgets/state_views.dart';

import 'support/fake_metrics_repository.dart';
import 'support/test_catalog.dart';
import 'support/test_helpers.dart';

/// T2: every signed-in page uses the same frame (EvolupPage), keeps its
/// content within the same width and clear of the floating navigation bar,
/// on phones, tablets and desktops.
void main() {
  const sizes = {
    'small phone': Size(320, 568),
    'phone': Size(390, 844),
    'tablet': Size(820, 1180),
    'desktop': Size(1440, 900),
  };

  TestWorld world() {
    final metrics = FakeMetricsRepository();
    final t = metrics.addTracked(tractions, favorite: true);
    metrics.addTracked(sommeil);
    for (var i = 0; i < 12; i++) {
      metrics.seed(t, 8 + i, date: metrics.today.addDays(-i * 3));
    }
    return TestWorld(metrics: metrics);
  }

  /// The page on screen (the others are kept offstage by the shell).
  Finder visible(Type type) => find.byType(type).hitTestable();

  for (final MapEntry(key: name, value: size) in sizes.entries) {
    testWidgets('$name: every page in the same frame, without overflow', (
      tester,
    ) async {
      await pumpApp(tester, world(), size: size);
      final titleLefts = <String, double>{};
      for (final section in [
        'overview',
        'data',
        'stats',
        'polomix',
        'settings',
      ]) {
        await openSection(tester, section);
        expect(tester.takeException(), isNull, reason: section);
        // One frame: the page's background behind a transparent Scaffold.
        final page = visible(EvolupPage);
        expect(page, findsOneWidget, reason: section);
        expect(
          find.descendant(of: page, matching: find.byType(EvolupBackground)),
          findsOneWidget,
        );
        if (section != 'overview' && section != 'polomix') {
          final title = find.descendant(
            of: find.descendant(of: page, matching: find.byType(AppBar)),
            matching: find.byType(Text),
          );
          titleLefts[section] = tester.getTopLeft(title.first).dx;
        }
        // Content width: at most 720, centered, 16 from the edges below.
        final body = find.descendant(of: page, matching: find.byType(PageBody));
        if (body.evaluate().isNotEmpty) {
          final column = tester.getRect(
            find.descendant(of: body, matching: find.byType(Column)).first,
          );
          final expected = (size.width - 32).clamp(0, 720).toDouble();
          expect(column.width, expected, reason: section);
          expect(
            column.center.dx,
            closeTo(size.width / 2, 0.5),
            reason: section,
          );
        }
      }
      // Titles of the plain sections start at the same place.
      expect(titleLefts.values.toSet(), hasLength(1), reason: '$titleLefts');

      await openSection(tester, 'overview');
      await tapKey(tester, 'overview-tractions');
      expect(tester.takeException(), isNull, reason: 'metric page');
      expect(visible(EvolupPage), findsOneWidget);
      await tapKey(tester, 'detail-record');
      expect(tester.takeException(), isNull, reason: 'entry form');
      expect(visible(EvolupPage), findsOneWidget);
    });
  }

  for (final MapEntry(key: name, value: size) in sizes.entries) {
    testWidgets('$name: the end of a page stays above the navigation bar', (
      tester,
    ) async {
      await pumpApp(tester, world(), size: size);
      await openSection(tester, 'settings');
      final signOut = find.byKey(const Key('settings-sign-out'));
      await tester.scrollUntilVisible(
        signOut,
        200,
        scrollable: find
            .descendant(
              of: visible(PageBody),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      // Scrolled to the very end: the last button is fully above the bar.
      final scrollable = tester.state<ScrollableState>(
        find
            .descendant(
              of: visible(PageBody),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
      await tester.pumpAndSettle();
      final bar = tester.getRect(find.byKey(const Key('nav-overview')));
      final button = tester.getRect(signOut);
      expect(button.bottom, lessThan(bar.top), reason: 'not hidden by the bar');
      // No fixed spacer: the page ends close to the bar (padding only).
      expect(bar.top - button.bottom, lessThan(80));
    });
  }
}
