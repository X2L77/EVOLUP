import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_training/app/session/local_day_clock.dart';
import 'package:my_training/app/session/metrics_controller.dart';
import 'package:my_training/data/local_date.dart';
import 'package:my_training/features/overview/overview_screen.dart';

import 'support/fake_metrics_repository.dart';
import 'support/test_catalog.dart';
import 'support/test_helpers.dart';

/// B3 (lot of 2026-11-12): "today" is the device's day; when it changes
/// (midnight, time zone, return to the foreground) the data depending on it
/// are read again, and recorded days never move.
void main() {
  group('LocalDayClock', () {
    test('notifies once per change of day, in both directions', () {
      var now = DateTime(2026, 11, 12, 23, 59);
      final clock = LocalDayClock(now: () => now);
      var notified = 0;
      clock.addListener(() => notified++);
      expect(clock.today, LocalDate(2026, 11, 12));
      expect(clock.check(), isFalse);

      now = DateTime(2026, 11, 13, 0, 0, 1);
      expect(clock.check(), isTrue);
      expect(clock.check(), isFalse);
      expect(clock.today, LocalDate(2026, 11, 13));
      // A time zone further west: the device is back on the 12th.
      now = DateTime(2026, 11, 12, 18, 30);
      expect(clock.check(), isTrue);
      expect(clock.today, LocalDate(2026, 11, 12));
      expect(notified, 2);
      clock.dispose();
    });

    testWidgets('watched: reads the clock just after midnight', (tester) async {
      var now = DateTime(2026, 11, 12, 23, 59, 59);
      final clock = LocalDayClock(now: () => now)..watch();
      LocalDate? seen;
      clock.addListener(() => seen = clock.today);
      now = DateTime(2026, 11, 13, 0, 0, 0, 100);
      // The first reading is scheduled ~1 s ahead (midnight + 50 ms).
      await tester.pump(const Duration(seconds: 2));
      expect(seen, LocalDate(2026, 11, 13));
      clock.dispose();
    });

    testWidgets('watched: reads the clock at least every 30 seconds', (
      tester,
    ) async {
      var now = DateTime(2026, 11, 12, 10);
      final clock = LocalDayClock(now: () => now)..watch();
      LocalDate? seen;
      clock.addListener(() => seen = clock.today);
      // A change of time zone sends no event.
      now = DateTime(2026, 11, 13, 1);
      await tester.pump(const Duration(seconds: 29));
      expect(seen, isNull);
      await tester.pump(const Duration(seconds: 2));
      expect(seen, LocalDate(2026, 11, 13));
      clock.dispose();
    });

    testWidgets('watched: reads the clock when the app comes back', (
      tester,
    ) async {
      var now = DateTime(2026, 11, 12, 10);
      final clock = LocalDayClock(now: () => now)..watch();
      LocalDate? seen;
      clock.addListener(() => seen = clock.today);
      void go(List<AppLifecycleState> states) {
        for (final state in states) {
          tester.binding.handleAppLifecycleStateChanged(state);
        }
      }

      go(const [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]);
      // Two days later, back to the foreground (no timer ran meanwhile).
      now = DateTime(2026, 11, 14, 9);
      go(const [
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]);
      expect(seen, LocalDate(2026, 11, 14));
      clock.dispose();
    });
  });

  group('the overview follows the device day', () {
    test('a change of day makes the shared overview stale', () async {
      final repository = FakeMetricsRepository(today: LocalDate(2026, 11, 12));
      repository.seed(repository.addTracked(tractions), 8);
      var day = LocalDate(2026, 11, 12);
      final controller = MetricsController(
        repository,
        now: () => DateTime(2026, 11, 12, 23, 59),
        today: () => day,
      );
      await controller.load();
      expect((await controller.loadOverview()).today, day);
      await controller.loadOverview();
      expect(repository.overviewLoads, 1);

      day = LocalDate(2026, 11, 13);
      repository.today = day;
      final next = await controller.loadOverview();
      expect(repository.overviewLoads, 2);
      expect(next.today, LocalDate(2026, 11, 13));
      expect(repository.overviewDays, [
        LocalDate(2026, 11, 12),
        LocalDate(2026, 11, 13),
      ]);
      controller.dispose();
    });

    testWidgets('midnight reloads the page; recorded days do not move', (
      tester,
    ) async {
      final metrics = FakeMetricsRepository(today: LocalDate(2026, 11, 12));
      final t = metrics.addTracked(tractions);
      metrics.seed(t, 8, date: LocalDate(2026, 11, 12));
      final world = TestWorld(metrics: metrics)
        ..clock = DateTime(2026, 11, 12, 23, 59);
      final session = await pumpInSession(
        tester,
        const OverviewScreen(),
        world: world,
      );
      expect(find.textContaining('aujourd’hui'), findsWidgets);
      final loads = metrics.overviewLoads;

      world.clock = DateTime(2026, 11, 13, 0, 1);
      metrics.today = LocalDate(2026, 11, 13);
      session.day.check();
      await tester.pumpAndSettle();
      expect(metrics.overviewLoads, loads + 1);
      expect(metrics.overviewDays.last, LocalDate(2026, 11, 13));
      // The value of the 12th is now "yesterday", still on the 12th.
      expect(find.textContaining('hier'), findsWidgets);
      expect(metrics.day(t.id, LocalDate(2026, 11, 12))!.sampleCount, 1);
      expect(metrics.dayCount(t.id), 1);
    });

    testWidgets('a time zone further west moves "today" back, not the data', (
      tester,
    ) async {
      final metrics = FakeMetricsRepository(today: LocalDate(2026, 11, 13));
      final t = metrics.addTracked(tractions);
      metrics.seed(t, 8, date: LocalDate(2026, 11, 13));
      // 00:30 in Paris…
      final world = TestWorld(metrics: metrics)
        ..clock = DateTime(2026, 11, 13, 0, 30);
      final session = await pumpInSession(
        tester,
        const OverviewScreen(),
        world: world,
      );
      // …18:30 the day before in Montréal.
      world.clock = DateTime(2026, 11, 12, 18, 30);
      session.day.check();
      await tester.pumpAndSettle();
      expect(metrics.overviewDays.last, LocalDate(2026, 11, 12));
      expect(tester.takeException(), isNull);
      // The day recorded in Paris stays the 13th.
      expect(metrics.day(t.id, LocalDate(2026, 11, 13)), isNotNull);
      expect(metrics.day(t.id, LocalDate(2026, 11, 12)), isNull);
    });
  });
}
