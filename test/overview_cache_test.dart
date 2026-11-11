import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_training/app/session/app_session.dart';
import 'package:my_training/app/session/metrics_controller.dart';
import 'package:my_training/data/data_error.dart';
import 'package:my_training/data/metrics/metric_models.dart';
import 'package:my_training/features/metrics/metric_detail_screen.dart';
import 'package:my_training/features/overview/overview_screen.dart';

import 'support/fake_metrics_repository.dart';
import 'support/test_catalog.dart';
import 'support/test_helpers.dart';

/// T3: `get_overview` is shared by the pages through the session's
/// MetricsController: one request at a time, reused until the data changes.
void main() {
  group('the shared overview', () {
    late FakeMetricsRepository repository;
    late MetricsController controller;
    late DateTime now;

    setUp(() async {
      repository = FakeMetricsRepository();
      repository.seed(repository.addTracked(tractions), 8);
      now = DateTime(2026, 11, 11, 12);
      controller = MetricsController(repository, now: () => now);
      await controller.load();
    });

    tearDown(() => controller.dispose());

    test('pages asking at the same time share one request', () async {
      final gate = repository.overviewGate = Completer<void>();
      final answers = Future.wait([
        controller.loadOverview(),
        controller.loadOverview(),
        controller.loadOverview(),
      ]);
      gate.complete();
      final [a, b, c] = await answers;
      expect(repository.overviewLoads, 1);
      expect(identical(a, b) && identical(b, c), isTrue);
    });

    test('a recent answer is reused, an older one is read again', () async {
      await controller.loadOverview();
      now = now.add(const Duration(seconds: 29));
      await controller.loadOverview();
      expect(repository.overviewLoads, 1);
      now = now.add(const Duration(seconds: 2));
      await controller.loadOverview();
      expect(repository.overviewLoads, 2, reason: 'never kept for long');
    });

    test('pull to refresh always asks the server', () async {
      await controller.loadOverview();
      await controller.loadOverview(refresh: true);
      expect(repository.overviewLoads, 2);
    });

    test('a recorded value makes it stale', () async {
      final before = await controller.loadOverview();
      expect(before.entriesCount, 1);
      await controller.record(_entry(controller, 9));
      final after = await controller.loadOverview();
      expect(repository.overviewLoads, 2);
      expect(after.entriesCount, 2);
    });

    test('a change of the tracked list makes it stale', () async {
      await controller.loadOverview();
      await controller.setFavorite(controller.tracked.single, true);
      final after = await controller.loadOverview();
      expect(repository.overviewLoads, 2);
      expect(after.metrics.single.isFavorite, isTrue);
      await controller.track(pompes);
      expect((await controller.loadOverview()).metrics, hasLength(2));
      expect(repository.overviewLoads, 3);
    });

    test('an answer asked before a change is never kept', () async {
      final gate = repository.overviewGate = Completer<void>();
      final early = controller.loadOverview(); // Reads 1 entry.
      repository.overviewGate = null;
      await controller.record(_entry(controller, 9));
      gate.complete();
      expect((await early).entriesCount, 1);
      final next = await controller.loadOverview();
      expect(next.entriesCount, 2, reason: 'the old answer was not reused');
      expect(repository.overviewLoads, 2);
    });

    test(
      'an older answer arriving last does not replace a newer one',
      () async {
        final gate = repository.overviewGate = Completer<void>();
        final early = controller.loadOverview();
        repository.overviewGate = null;
        await controller.record(_entry(controller, 9));
        expect((await controller.loadOverview()).entriesCount, 2);
        gate.complete(); // The first request answers last.
        await early;
        expect((await controller.loadOverview()).entriesCount, 2);
        expect(repository.overviewLoads, 2, reason: 'newer answer kept');
      },
    );

    test('a failure is not kept: the next call asks again', () async {
      repository.overviewError = StateError('server down');
      await expectLater(
        controller.loadOverview(),
        throwsA(isA<DataException>()),
      );
      repository.overviewError = null;
      expect((await controller.loadOverview()).entriesCount, 1);
      expect(repository.overviewLoads, 2);
    });

    test('an answer arriving after dispose is harmless', () async {
      final gate = repository.overviewGate = Completer<void>();
      final pending = controller.loadOverview();
      controller.dispose();
      gate.complete();
      expect((await pending).entriesCount, 1);
      controller = MetricsController(repository); // For tearDown.
    });
  });

  group('the pages', () {
    testWidgets('one write reloads the overview once for every open page', (
      tester,
    ) async {
      final metrics = FakeMetricsRepository();
      final tracked = metrics.addTracked(tractions);
      metrics.seed(tracked, 8);
      await pumpApp(tester, TestWorld(metrics: metrics));
      for (final section in ['data', 'stats', 'settings']) {
        await openSection(tester, section);
      }
      // Overview, then the 3 sections opened right after: one request.
      expect(metrics.overviewLoads, 1);

      final controller = _controller(tester);
      final before = metrics.overviewLoads;
      await controller.record(_entry(controller, 9));
      await tester.pumpAndSettle();
      // 4 pages listen to the change: one shared request (4 before T3).
      expect(metrics.overviewLoads - before, 1);
    });

    testWidgets('the metric page reuses the overview for its first day', (
      tester,
    ) async {
      final metrics = FakeMetricsRepository();
      final tracked = metrics.addTracked(tractions);
      metrics.seed(tracked, 8);
      await pumpApp(tester, TestWorld(metrics: metrics));
      expect(metrics.overviewLoads, 1);
      await tapKey(tester, 'overview-tractions');
      expect(find.byType(MetricDetailScreen), findsOneWidget);
      expect(
        metrics.overviewLoads,
        1,
        reason: 'already loaded by the overview',
      );
    });

    testWidgets('added metrics and favourites show at once, without request', (
      tester,
    ) async {
      final metrics = FakeMetricsRepository();
      metrics.seed(metrics.addTracked(tractions), 8);
      await pumpApp(tester, TestWorld(metrics: metrics));
      final controller = _controller(tester);
      final loads = metrics.overviewLoads;

      await controller.track(pompes);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('overview-pompes')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('overview-pompes')),
          matching: find.text('Aucune valeur enregistrée'),
        ),
        findsOneWidget,
      );

      await controller.setFavorite(controller.trackedFor(pompes.id)!, true);
      await tester.pumpAndSettle();
      expect(find.text('Favoris'), findsOneWidget);
      final favorite = tester.getTopLeft(
        find.byKey(const Key('overview-pompes')),
      );
      final other = tester.getTopLeft(
        find.byKey(const Key('overview-tractions')),
      );
      expect(favorite.dy, lessThan(other.dy));

      await controller.setActive(controller.trackedFor(tractions.id)!, false);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('overview-tractions')), findsNothing);
      expect(metrics.overviewLoads, loads, reason: 'nothing recorded changed');
    });

    testWidgets('another account never sees the previous overview', (
      tester,
    ) async {
      final metrics = FakeMetricsRepository();
      metrics.seed(metrics.addTracked(tractions), 8);
      final world = TestWorld(metrics: metrics);
      await pumpApp(tester, world);
      expect(find.byKey(const Key('overview-tractions')), findsOneWidget);
      final first = _controller(tester);
      final loads = metrics.overviewLoads;

      // The other account's data (the fake server answers for whoever is
      // signed in).
      metrics.tracked.clear();
      metrics.seed(metrics.addTracked(pompes), 12);
      world.auth.openSession('user-2');
      await tester.pumpAndSettle();

      final second = _controller(tester);
      expect(identical(first, second), isFalse, reason: 'new session');
      expect(metrics.overviewLoads, loads + 1, reason: 'read again');
      expect(find.byKey(const Key('overview-tractions')), findsNothing);
      expect(find.byKey(const Key('overview-pompes')), findsOneWidget);
    });
  });
}

MetricsController _controller(WidgetTester tester) => SessionScope.of(
  tester.element(find.byType(OverviewScreen, skipOffstage: false)),
).metrics;

var _key = 0;

EntryRequest _entry(MetricsController controller, num value) => EntryRequest(
  trackedMetricId: controller.trackedFor(tractions.id)!.id,
  value: value,
  unit: tractions.storageUnit,
  localDate: (controller.repository as FakeMetricsRepository).today,
  timezone: 'Europe/Paris',
  idempotencyKey: 'key-${_key++}',
);
