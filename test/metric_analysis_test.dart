import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_training/app/session/metrics_controller.dart';
import 'package:my_training/app/widgets/state_views.dart';
import 'package:my_training/data/local_date.dart';
import 'package:my_training/data/metrics/metric_models.dart';
import 'package:my_training/features/metrics/metric_detail_screen.dart';
import 'package:my_training/features/stats/widgets/metric_analysis.dart';
import 'package:my_training/features/stats/widgets/period_selector.dart';

import 'support/fake_metrics_repository.dart';
import 'support/test_catalog.dart';
import 'support/test_helpers.dart';

/// T7: the analysis of one metric reloads only when its query or the
/// recorded data change, and only the latest load may update it.
void main() {
  late FakeMetricsRepository repository;
  late TrackedMetric tractionsTracked;
  late TrackedMetric pompesTracked;
  late LocalDate today;
  late ValueNotifier<_Params> params;
  late MetricsController controller;

  Future<void> pumpAnalysis(WidgetTester tester) async {
    repository = FakeMetricsRepository();
    today = repository.today;
    tractionsTracked = repository.addTracked(tractions);
    pompesTracked = repository.addTracked(pompes);
    // Tractions: 1 day in 7 days, 2 in 30, 3 in 90. Pompes: 1 day.
    for (final daysAgo in [0, 10, 50]) {
      repository.seed(tractionsTracked, 8, date: today.addDays(-daysAgo));
    }
    repository.seed(pompesTracked, 20);
    params = ValueNotifier(
      _Params(tractionsTracked, tractions, StatsPeriod.days7, null),
    );
    addTearDown(params.dispose);
    final session = await pumpInSession(
      tester,
      Scaffold(
        body: SingleChildScrollView(
          child: ValueListenableBuilder<_Params>(
            valueListenable: params,
            builder: (context, p, _) => MetricAnalysis(
              tracked: p.tracked,
              definition: p.definition,
              period: p.period,
              firstDate: p.firstDate,
              today: today,
            ),
          ),
        ),
      ),
      world: TestWorld(metrics: repository),
    );
    controller = session.metrics;
  }

  /// "Journées" figure: recorded days of the period shown.
  String? days(WidgetTester tester) {
    final figure = find.byKey(const Key('figure-days'));
    if (figure.evaluate().isEmpty) return null;
    return tester
        .widget<Text>(
          find.descendant(of: figure, matching: find.byType(Text)).at(1),
        )
        .data;
  }

  var key = 0;
  Future<void> record(TrackedMetric tracked, int daysAgo) async {
    await controller.record(
      EntryRequest(
        trackedMetricId: tracked.id,
        value: 9,
        unit: 'repetition',
        localDate: today.addDays(-daysAgo),
        timezone: 'Europe/Paris',
        idempotencyKey: 'analysis-${key++}',
      ),
    );
  }

  void set({TrackedMetric? tracked, StatsPeriod? period, LocalDate? first}) {
    final p = params.value;
    final metric = tracked ?? p.tracked;
    params.value = _Params(
      metric,
      metric == pompesTracked ? pompes : tractions,
      period ?? p.period,
      first ?? p.firstDate,
    );
  }

  testWidgets('loads once, and not again for the same query', (tester) async {
    await pumpAnalysis(tester);
    expect(days(tester), '1');
    expect(repository.statisticsLoads, 1);
    expect(repository.seriesLoads, 1);
    expect(repository.comparisonLoads, 1);

    // Same query rebuilt; first day learnt for a period that ignores it;
    // favourite changed (no recorded data changed): nothing to reload.
    set();
    await tester.pumpAndSettle();
    set(first: today.addDays(-50));
    await tester.pumpAndSettle();
    await controller.setFavorite(tractionsTracked, true);
    await tester.pumpAndSettle();
    expect(repository.statisticsLoads, 1);
    expect(repository.seriesLoads, 1);
  });

  testWidgets('« Tout » reloads once the first day is known', (tester) async {
    await pumpAnalysis(tester);
    set(period: StatsPeriod.all);
    await tester.pumpAndSettle();
    expect(days(tester), '1', reason: 'only today without the first day');
    set(first: today.addDays(-50));
    await tester.pumpAndSettle();
    expect(days(tester), '3');
    expect(repository.statisticsLoads, 3);
  });

  testWidgets('two reloads: the older answer arriving last is dropped', (
    tester,
  ) async {
    await pumpAnalysis(tester);
    final slow = repository.analysisGate = Completer<void>();
    await record(tractionsTracked, 1); // Reload 1 reads 2 days, answers late.
    await tester.pump();
    repository.analysisGate = null;
    await record(tractionsTracked, 2); // Reload 2 reads 3 days.
    await tester.pumpAndSettle();
    expect(days(tester), '3');

    slow.complete();
    await tester.pumpAndSettle();
    expect(days(tester), '3', reason: 'older answer dropped');
  });

  testWidgets('period change: only the latest period is shown', (tester) async {
    await pumpAnalysis(tester);
    final slow = repository.analysisGate = Completer<void>();
    set(period: StatsPeriod.days30); // Answers late.
    await tester.pump();
    repository.analysisGate = null;
    set(period: StatsPeriod.days90);
    await tester.pumpAndSettle();
    expect(days(tester), '3');

    slow.complete();
    await tester.pumpAndSettle();
    expect(days(tester), '3', reason: 'the 30-day answer came too late');
  });

  testWidgets('metric change: never the figures of the other metric', (
    tester,
  ) async {
    await pumpAnalysis(tester);
    set(period: StatsPeriod.days90);
    await tester.pumpAndSettle();
    expect(days(tester), '3');

    final slow = repository.analysisGate = Completer<void>();
    await record(tractionsTracked, 1); // Tractions reload, answers late.
    await tester.pump();
    final pompesGate = repository.analysisGate = Completer<void>();
    set(tracked: pompesTracked);
    await tester.pump();
    expect(find.byType(LoadingView), findsOneWidget);
    expect(days(tester), isNull, reason: 'tractions figures not shown');

    pompesGate.complete();
    await tester.pumpAndSettle();
    expect(days(tester), '1');
    slow.complete();
    await tester.pumpAndSettle();
    expect(days(tester), '1', reason: 'late tractions answer dropped');
  });

  testWidgets('a failed reload keeps the figures of the same query', (
    tester,
  ) async {
    await pumpAnalysis(tester);
    repository.analysisError = StateError('server down');
    await record(tractionsTracked, 1);
    await tester.pumpAndSettle();
    expect(days(tester), '1', reason: 'kept, not replaced by an error');
    expect(find.byType(ErrorView), findsNothing);
  });

  testWidgets('a failed load never shows another period as this one', (
    tester,
  ) async {
    await pumpAnalysis(tester);
    repository.analysisError = StateError('server down');
    set(period: StatsPeriod.days90);
    await tester.pumpAndSettle();
    expect(find.byType(ErrorView), findsOneWidget);
    expect(days(tester), isNull, reason: 'the 7-day figures are not shown');

    repository.analysisError = null;
    await tester.tap(find.text('Réessayer'));
    await tester.pumpAndSettle();
    expect(days(tester), '3');
  });

  group('while another period loads', () {
    final bar = find.byKey(const Key('analysis-loading'));

    /// Opacity actually painted (the transition's current value).
    double opacity(WidgetTester tester) => tester
        .widget<FadeTransition>(
          find
              .descendant(
                of: find.byKey(const Key('analysis-content')),
                matching: find.byType(FadeTransition),
              )
              .first,
        )
        .opacity
        .value;

    bool inactive(WidgetTester tester) => tester
        .widget<IgnorePointer>(
          find
              .descendant(
                of: find.byKey(const Key('analysis-content')),
                matching: find.byType(IgnorePointer),
              )
              .first,
        )
        .ignoring;

    testWidgets('the old figures are dimmed under a bar until the answer', (
      tester,
    ) async {
      await pumpAnalysis(tester);
      expect(bar, findsNothing);
      expect(opacity(tester), 1);

      final gate = repository.analysisGate = Completer<void>();
      set(period: StatsPeriod.days90);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(bar, findsOneWidget);
      expect(find.bySemanticsLabel('Chargement de la période'), findsOneWidget);
      expect(days(tester), '1', reason: 'kept in place, nothing moves');
      expect(opacity(tester), 0.45);
      expect(inactive(tester), isTrue);

      gate.complete();
      await tester.pumpAndSettle();
      expect(bar, findsNothing);
      expect(opacity(tester), 1);
      expect(inactive(tester), isFalse);
      expect(days(tester), '3');
    });

    testWidgets('reloading the same period shows no loading state', (
      tester,
    ) async {
      await pumpAnalysis(tester);
      final gate = repository.analysisGate = Completer<void>();
      await record(tractionsTracked, 1);
      await tester.pump(const Duration(milliseconds: 300));
      expect(bar, findsNothing, reason: 'same period: figures still valid');
      expect(opacity(tester), 1);
      gate.complete();
      await tester.pumpAndSettle();
      expect(days(tester), '2');
    });

    testWidgets('a failure shows the error, never dimmed old figures', (
      tester,
    ) async {
      await pumpAnalysis(tester);
      final gate = repository.analysisGate = Completer<void>();
      repository.analysisError = StateError('server down');
      set(period: StatsPeriod.days90);
      await tester.pump(const Duration(milliseconds: 300));
      expect(bar, findsOneWidget);

      gate.complete();
      await tester.pumpAndSettle();
      expect(find.byType(ErrorView), findsOneWidget);
      expect(bar, findsNothing);
      expect(days(tester), isNull, reason: 'no 7-day figures under « 90 j »');
    });

    testWidgets('« Réessayer » shows the loading view, then the figures', (
      tester,
    ) async {
      await pumpAnalysis(tester);
      repository.analysisError = StateError('server down');
      set(period: StatsPeriod.days90);
      await tester.pumpAndSettle();
      expect(find.byType(ErrorView), findsOneWidget);

      repository.analysisError = null;
      final gate = repository.analysisGate = Completer<void>();
      await tester.tap(find.text('Réessayer'));
      await tester.pump();
      expect(find.byType(ErrorView), findsNothing);
      expect(find.byType(LoadingView), findsOneWidget);
      expect(days(tester), isNull);

      gate.complete();
      await tester.pumpAndSettle();
      expect(find.byType(LoadingView), findsNothing);
      expect(days(tester), '3');
      expect(opacity(tester), 1);
    });

    testWidgets('« Réessayer » failing again shows the error again', (
      tester,
    ) async {
      await pumpAnalysis(tester);
      repository.analysisError = StateError('server down');
      set(period: StatsPeriod.days90);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Réessayer'));
      await tester.pumpAndSettle();
      expect(find.byType(ErrorView), findsOneWidget);
      expect(days(tester), isNull);
    });

    testWidgets('reduced motion: dimmed and restored without transition', (
      tester,
    ) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await pumpAnalysis(tester);
      final gate = repository.analysisGate = Completer<void>();
      set(period: StatsPeriod.days90);
      await tester.pump();
      expect(opacity(tester), 0.45, reason: 'at once, no fade');
      expect(bar, findsOneWidget);

      gate.complete();
      await tester.pump();
      await tester.pump();
      expect(opacity(tester), 1, reason: 'at once, no fade');
      expect(bar, findsNothing);
      expect(days(tester), '3');
    });

    testWidgets('with motion, the dimming is a short transition', (
      tester,
    ) async {
      await pumpAnalysis(tester);
      final gate = repository.analysisGate = Completer<void>();
      set(period: StatsPeriod.days90);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(opacity(tester), allOf(greaterThan(0.45), lessThan(1)));
      gate.complete();
      await tester.pumpAndSettle();
      expect(opacity(tester), 1);
    });
  });

  testWidgets('closed while loading: nothing happens', (tester) async {
    await pumpAnalysis(tester);
    final slow = repository.analysisGate = Completer<void>();
    set(period: StatsPeriod.days30);
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    slow.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('the metric page loads its analysis once', (tester) async {
    final metrics = FakeMetricsRepository();
    metrics.seed(metrics.addTracked(tractions), 8);
    await pumpApp(tester, TestWorld(metrics: metrics));
    await tapKey(tester, 'overview-tractions');
    expect(find.byType(MetricDetailScreen), findsOneWidget);
    // Before T7 the first day arriving reloaded all three (2 each).
    expect(metrics.statisticsLoads, 1);
    expect(metrics.seriesLoads, 1);
    expect(metrics.comparisonLoads, 1);
  });
}

class _Params {
  const _Params(this.tracked, this.definition, this.period, this.firstDate);

  final TrackedMetric tracked;
  final MetricDefinition definition;
  final StatsPeriod period;
  final LocalDate? firstDate;
}
