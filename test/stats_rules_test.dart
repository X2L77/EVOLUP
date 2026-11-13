import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_training/data/local_date.dart';
import 'package:my_training/data/metrics/metric_models.dart';
import 'package:my_training/features/stats/widgets/metric_chart.dart';
import 'package:my_training/features/stats/widgets/period_selector.dart';
import 'package:my_training/theme/evolup_theme.dart';

import 'support/fake_metrics_repository.dart';
import 'support/test_catalog.dart';
import 'support/test_helpers.dart';

SeriesPoint _point(LocalDate start, double value) =>
    SeriesPoint(start: start, value: value, sampleCount: 1, daysCount: 1);

/// Lot of 2026-11-12: « Jour » up to 365 days (B1), one request for the
/// series shared by the analysis and the comparison (B4), lines broken where
/// values are missing, incomplete weeks and months shown as such.
void main() {
  final today = LocalDate(2026, 11, 12);

  group('B1 · « Jour » up to 365 days', () {
    test('the period length counts both ends', () {
      expect(periodLength(today, today), 1);
      expect(dayBucketAvailable(today.addDays(-364), today), isTrue);
      expect(dayBucketAvailable(today.addDays(-365), today), isFalse);
      // « 1 an » keeps the daily grouping.
      final (from, to) = StatsPeriod.year.range(today, null);
      expect(periodLength(from, to), 365);
    });

    testWidgets('« Tout » beyond 365 days: « Jour » is disabled and explained, '
        'no SQL error', (tester) async {
      final metrics = FakeMetricsRepository(today: today);
      final t = metrics.addTracked(tractions);
      // A day recorded 400 days ago, before the one-year rule.
      metrics
        ..seed(t, 8, date: today.addDays(-400))
        ..seed(t, 9, date: today);
      await pumpApp(
        tester,
        TestWorld(metrics: metrics)..clock = DateTime(2026, 11, 12, 10),
      );
      await openSection(tester, 'stats');
      await tapKey(tester, 'bucket-day');
      expect(metrics.seriesQueries.last.$4, SeriesBucket.day);

      await tapKey(tester, 'period-all');
      expect(tester.takeException(), isNull);
      final selector = tester.widget<SegmentedButton<SeriesBucket?>>(
        find.byKey(const Key('bucket-selector')),
      );
      expect(
        selector.segments
            .firstWhere((s) => s.value == SeriesBucket.day)
            .enabled,
        isFalse,
      );
      expect(selector.selected, {null});
      final note = find.byKey(const Key('stats-day-unavailable'));
      expect(note, findsOneWidget);
      expect(
        find.descendant(of: note, matching: find.textContaining('401')),
        findsOneWidget,
      );
      expect(find.textContaining('Regroupement automatique'), findsOneWidget);
      // The automatic grouping was asked, never 'day' over 401 days.
      expect(metrics.seriesQueries.last.$4, isNull);
      expect(find.byKey(const Key('analysis-empty')), findsNothing);
      expect(find.byType(MetricChart), findsOneWidget);

      // Back to a year: the daily grouping chosen before comes back.
      await tapKey(tester, 'period-year');
      expect(find.byKey(const Key('stats-day-unavailable')), findsNothing);
      expect(metrics.seriesQueries.last.$4, SeriesBucket.day);
    });
  });

  group('B4 · the series shared by the analysis and the comparison', () {
    testWidgets('the first metric is loaded once; results unchanged', (
      tester,
    ) async {
      final metrics = FakeMetricsRepository(today: today);
      final t = metrics.addTracked(tractions);
      final s = metrics.addTracked(sommeil);
      for (var i = 0; i < 5; i++) {
        metrics
          ..seed(t, 8 + i, date: today.addDays(-i))
          ..seed(s, 27000, date: today.addDays(-i));
      }
      await pumpApp(
        tester,
        TestWorld(metrics: metrics)..clock = DateTime(2026, 11, 12, 10),
      );
      await openSection(tester, 'stats');
      await tester.ensureVisible(find.byKey(const Key('stats-second')));
      await tester.tap(find.byKey(const Key('stats-second')));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Durée de sommeil').last);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('stats-comparison')), findsOneWidget);
      expect(find.byType(MetricChart), findsNWidgets(3));

      final first = metrics.seriesQueries.where((q) => q.$1 == t.id).toList();
      expect(first, hasLength(1), reason: 'one request for the same series');
      final second = metrics.seriesQueries.where((q) => q.$1 == s.id).toList();
      expect(second, hasLength(1));
      // Same days and the grouping of the first series.
      expect(
        (second.single.$2, second.single.$3),
        (first.single.$2, first.single.$3),
      );
      expect(second.single.$4, SeriesBucket.day);
      // Both charts of the comparison show their own points.
      final charts = tester
          .widgetList<MetricChart>(find.byType(MetricChart))
          .toList();
      expect(charts[1].series.points, hasLength(5));
      expect(charts[2].series.points, hasLength(5));
      expect(charts[1].series.points.first.value, 12);
    });
  });

  group('lines broken where values are missing', () {
    test('days, weeks and months', () {
      final d = LocalDate(2026, 11, 2);
      expect(
        continuousRuns([
          _point(d, 1),
          _point(d.addDays(1), 2),
          _point(d.addDays(3), 3),
          _point(d.addDays(4), 4),
          _point(d.addDays(9), 5),
        ], SeriesBucket.day),
        [
          [0, 1],
          [2, 3],
          [4],
        ],
      );
      final monday = LocalDate(2026, 10, 5);
      expect(
        continuousRuns([
          _point(monday, 1),
          _point(monday.addDays(7), 2),
          _point(monday.addDays(21), 3),
        ], SeriesBucket.week),
        [
          [0, 1],
          [2],
        ],
      );
      expect(
        continuousRuns([
          _point(LocalDate(2025, 12, 1), 1),
          _point(LocalDate(2026, 1, 1), 2),
          _point(LocalDate(2026, 2, 1), 3),
          _point(LocalDate(2026, 4, 1), 4),
        ], SeriesBucket.month),
        [
          [0, 1, 2],
          [3],
        ],
      );
      expect(continuousRuns(const [], SeriesBucket.day), isEmpty);
    });
  });

  group('incomplete weeks and months', () {
    test('cut by the period, or not over yet', () {
      // Thursday 12 November 2026: its week (from Monday 9) has 4 days.
      expect(
        partialCoverage(
          LocalDate(2026, 11, 9),
          SeriesBucket.week,
          from: LocalDate(2026, 8, 15),
          to: today,
          today: today,
        ),
        const BucketCoverage(4, 7),
      );
      // The period starts on Saturday 15 August: 2 days of that week.
      expect(
        partialCoverage(
          LocalDate(2026, 8, 10),
          SeriesBucket.week,
          from: LocalDate(2026, 8, 15),
          to: today,
          today: today,
        ),
        const BucketCoverage(2, 7),
      );
      // A full week inside the period.
      expect(
        partialCoverage(
          LocalDate(2026, 10, 5),
          SeriesBucket.week,
          from: LocalDate(2026, 8, 15),
          to: today,
          today: today,
        ),
        isNull,
      );
      // November so far: 12 days out of 30; February 2028: 29 days.
      expect(
        partialCoverage(
          LocalDate(2026, 11, 1),
          SeriesBucket.month,
          from: LocalDate(2025, 1, 1),
          to: today,
          today: today,
        ),
        const BucketCoverage(12, 30),
      );
      expect(
        partialCoverage(
          LocalDate(2028, 2, 1),
          SeriesBucket.month,
          from: LocalDate(2028, 1, 1),
          to: LocalDate(2028, 3, 31),
          today: LocalDate(2028, 6, 1),
        ),
        isNull,
      );
      expect(bucketEnd(LocalDate(2028, 2, 1), SeriesBucket.month).day, 29);
      // Days are never incomplete.
      expect(
        partialCoverage(
          today,
          SeriesBucket.day,
          from: today,
          to: today,
          today: today,
        ),
        isNull,
      );
      expect(
        partialLabel(SeriesBucket.week, const BucketCoverage(4, 7)),
        'semaine incomplète (4 jours sur 7)',
      );
      expect(
        partialLabel(SeriesBucket.month, const BucketCoverage(1, 31)),
        'mois incomplet (1 jour sur 31)',
      );
    });

    testWidgets('the chart says it: note, selection and screen reader', (
      tester,
    ) async {
      final series = MetricSeries(
        bucket: SeriesBucket.week,
        points: [
          _point(LocalDate(2026, 10, 19), 8),
          _point(LocalDate(2026, 10, 26), 9),
          // No value in the week of 2 November: the line stops.
          _point(LocalDate(2026, 11, 9), 10),
        ],
      );
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          theme: buildEvolupTheme(),
          home: Scaffold(
            body: MetricChart(
              definition: tractions,
              series: series,
              from: LocalDate(2026, 10, 19),
              to: today,
              today: today,
            ),
          ),
        ),
      );
      expect(find.byKey(const Key('chart-partial-note')), findsOneWidget);
      expect(
        find.bySemanticsLabel(
          RegExp('1 semaine incomplète.*Ligne interrompue'),
        ),
        findsOneWidget,
      );
      // Touching the last point (current week).
      final chart = tester.getRect(find.byKey(const Key('metric-chart')));
      await tester.tapAt(Offset(chart.right - 8, chart.center.dy));
      await tester.pump();
      expect(
        find.textContaining('semaine incomplète (4 jours sur 7)'),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('complete weeks and days: no note', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildEvolupTheme(),
          home: Scaffold(
            body: MetricChart(
              definition: tractions,
              series: MetricSeries(
                bucket: SeriesBucket.day,
                points: [_point(today.addDays(-1), 8), _point(today, 9)],
              ),
              from: today.addDays(-6),
              to: today,
              today: today,
            ),
          ),
        ),
      );
      expect(find.byKey(const Key('chart-partial-note')), findsNothing);
    });
  });
}
