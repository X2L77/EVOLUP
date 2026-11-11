import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_training/app/session/app_session.dart';
import 'package:my_training/data/data_error.dart';
import 'package:my_training/features/data/my_data_screen.dart';
import 'package:my_training/features/metrics/metric_detail_screen.dart';

import 'support/fake_metrics_repository.dart';
import 'support/test_catalog.dart';
import 'support/test_helpers.dart';

void main() {
  Future<SignedInSession> pumpData(
    WidgetTester tester,
    FakeMetricsRepository metrics,
  ) => pumpInSession(
    tester,
    const MyDataScreen(),
    world: TestWorld(metrics: metrics),
  );

  testWidgets('the active catalog can be browsed, searched and filtered', (
    tester,
  ) async {
    await pumpData(tester, FakeMetricsRepository());
    expect(find.text('Catalogue EVOLUP'), findsOneWidget);
    for (final d in [tractions, pompes, sommeil, humeur]) {
      expect(
        find.byKey(Key('catalog-${d.slug}'), skipOffstage: false),
        findsOneWidget,
      );
    }
    // A metric retired from the catalog is not offered.
    expect(
      find.byKey(const Key('catalog-gainage'), skipOffstage: false),
      findsNothing,
    );

    await tester.enterText(find.byKey(const Key('data-search')), 'sommeil');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('catalog-sommeil_duree')), findsOneWidget);
    expect(find.byKey(const Key('catalog-tractions')), findsNothing);

    await tester.enterText(find.byKey(const Key('data-search')), '');
    await tapKey(tester, 'category-developpement_personnel');
    expect(find.byKey(const Key('catalog-humeur')), findsOneWidget);
    expect(find.byKey(const Key('catalog-tractions')), findsNothing);
  });

  testWidgets('a metric is added once to the user\'s space', (tester) async {
    final metrics = FakeMetricsRepository();
    final session = await pumpData(tester, metrics);
    await tapKey(tester, 'track-tractions');
    expect(metrics.tracked.single.metricCatalogId, tractions.id);
    expect(find.byKey(const Key('tracked-tractions')), findsOneWidget);
    expect(
      find.byKey(const Key('catalog-tractions'), skipOffstage: false),
      findsNothing,
    );
    expect(find.text('Mes indicateurs'), findsOneWidget);

    // Adding it again is refused by the database.
    await expectLater(
      metrics.track(tractions.id),
      throwsA(
        predicate((e) => classifyDataError(e!) == DataFailure.alreadyTracked),
      ),
    );
    // The controller does not create a second one either.
    await session.metrics.track(tractions);
    expect(metrics.tracked, hasLength(1));
  });

  testWidgets('a retired catalog metric cannot be added', (tester) async {
    final metrics = FakeMetricsRepository();
    final session = await pumpData(tester, metrics);
    await expectLater(
      session.metrics.track(gainage),
      throwsA(
        predicate((e) => classifyDataError(e!) == DataFailure.notAllowed),
      ),
    );
    expect(metrics.tracked, isEmpty);
  });

  testWidgets('removing a metric from the list keeps its history', (
    tester,
  ) async {
    final metrics = FakeMetricsRepository();
    final tracked = metrics.addTracked(tractions);
    metrics.seed(tracked, 8);
    await pumpData(tester, metrics);

    await tapKey(tester, 'tracked-tractions');
    expect(find.byType(MetricDetailScreen), findsOneWidget);
    await tapKey(tester, 'detail-menu');
    await tester.tap(find.text('Retirer de ma liste'));
    await tester.pumpAndSettle();
    expect(metrics.tracked.single.isActive, isFalse);
    expect(metrics.dayCount(tracked.id), 1);
    // The history stays readable, and no entry can be added.
    expect(find.byKey(Key('day-${metrics.today.iso}')), findsOneWidget);
    expect(find.byKey(const Key('detail-record')), findsNothing);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Retirés de ma liste'), findsOneWidget);
    expect(find.textContaining('historique conservé'), findsOneWidget);
    await tapKey(tester, 'reactivate-tractions');
    expect(metrics.tracked.single.isActive, isTrue);
    expect(find.byKey(const Key('quick-entry-tractions')), findsOneWidget);
  });

  testWidgets(
    'deleting a metric removes it with its history, after confirmation',
    (tester) async {
      final metrics = FakeMetricsRepository();
      final tracked = metrics.addTracked(tractions);
      metrics.seed(tracked, 8);
      await pumpData(tester, metrics);
      await tapKey(tester, 'tracked-tractions');
      await tapKey(tester, 'detail-menu');
      await tester.tap(find.text('Supprimer l’indicateur et son historique'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('confirm-dialog')), findsOneWidget);
      await tapKey(tester, 'confirm-accept');
      expect(metrics.tracked, isEmpty);
      expect(metrics.dayCount(tracked.id), 0);
      expect(find.byType(MetricDetailScreen), findsNothing);
    },
  );
}
