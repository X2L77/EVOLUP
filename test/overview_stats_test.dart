import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_training/features/data/my_data_screen.dart';
import 'package:my_training/features/metrics/metric_detail_screen.dart';
import 'package:my_training/features/stats/widgets/metric_chart.dart';

import 'support/fake_metrics_repository.dart';
import 'support/test_catalog.dart';
import 'support/test_helpers.dart';

void main() {
  const nbsp = ' ';

  testWidgets('a new user gets an explanation, no score and no sample data', (
    tester,
  ) async {
    await pumpApp(tester, TestWorld());
    expect(find.byKey(const Key('overview-empty')), findsOneWidget);
    expect(find.textContaining('/100'), findsNothing);
    expect(find.textContaining('Score'), findsNothing);
    await tapKey(tester, 'overview-browse');
    expect(find.byType(MyDataScreen), findsOneWidget);
  });

  testWidgets('the overview shows only recorded values, favourites first', (
    tester,
  ) async {
    final metrics = FakeMetricsRepository();
    final t = metrics.addTracked(tractions);
    metrics
      ..seed(t, 8)
      ..seed(t, 10);
    metrics.addTracked(sommeil, favorite: true);
    await pumpApp(tester, TestWorld(metrics: metrics));

    expect(find.text('2'), findsWidgets);
    expect(find.byKey(const Key('summary-days')), findsOneWidget);
    expect(
      find.textContaining('9${nbsp}rép.', findRichText: true),
      findsOneWidget,
    );
    expect(find.textContaining('2 saisies'), findsWidgets);
    expect(find.text('Aucune valeur enregistrée'), findsOneWidget);
    expect(
      find.textContaining('pas assez de données pour comparer'),
      findsOneWidget,
    );
    final favorite = tester.getTopLeft(
      find.byKey(const Key('overview-sommeil_duree')),
    );
    final other = tester.getTopLeft(
      find.byKey(const Key('overview-tractions')),
    );
    expect(favorite.dy, lessThan(other.dy));
    expect(find.textContaining('/100'), findsNothing);
  });

  testWidgets('statistics wait for real data', (tester) async {
    final metrics = FakeMetricsRepository()..addTracked(tractions);
    await pumpApp(tester, TestWorld(metrics: metrics));
    await openSection(tester, 'stats');
    expect(find.byKey(const Key('stats-empty')), findsOneWidget);
    expect(find.byType(MetricChart), findsNothing);
  });

  testWidgets('statistics: figures, chart, and honest limits', (tester) async {
    final metrics = FakeMetricsRepository();
    final t = metrics.addTracked(tractions);
    final today = metrics.today;
    for (final (offset, v) in [(0, 10), (1, 9), (2, 8)]) {
      metrics.seed(t, v, date: today.addDays(-offset));
    }
    metrics.seed(t, 12, date: today);
    await pumpApp(tester, TestWorld(metrics: metrics));
    await openSection(tester, 'stats');

    expect(find.byType(MetricChart), findsOneWidget);
    // (10 + 12 + 9 + 8) / 4, weighted by entries.
    expect(find.text('9,8${nbsp}rép.'), findsOneWidget);
    expect(find.byKey(const Key('figure-days')), findsOneWidget);
    expect(find.byKey(const Key('figure-record')), findsOneWidget);
    expect(find.text('12${nbsp}rép.'), findsWidgets);
    // 3 days: no trend, no comparison with nothing before.
    expect(find.byKey(const Key('insight-trend-missing')), findsOneWidget);
    expect(
      find.textContaining('Pas assez de données pour comparer'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('bucket-week')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('period-all')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(MetricChart), findsOneWidget);

    await tester.tap(find.byKey(const Key('metric-chart')));
    await tester.pumpAndSettle();
    expect(find.textContaining('saisie'), findsWidgets);
  });

  testWidgets(
    'a second metric is compared over the same days, without causality',
    (tester) async {
      final metrics = FakeMetricsRepository();
      final t = metrics.addTracked(tractions);
      final s = metrics.addTracked(sommeil);
      metrics
        ..seed(t, 8)
        ..seed(s, 27000);
      await pumpApp(tester, TestWorld(metrics: metrics));
      await openSection(tester, 'stats');
      await tester.ensureVisible(find.byKey(const Key('stats-second')));
      await tester.tap(find.byKey(const Key('stats-second')));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Durée de sommeil').last);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('stats-comparison')), findsOneWidget);
      expect(find.byType(MetricChart), findsNWidgets(3));
      expect(find.textContaining('ne prouvent pas'), findsOneWidget);
    },
  );

  testWidgets('a day can be corrected or deleted from the metric page', (
    tester,
  ) async {
    final metrics = FakeMetricsRepository();
    final t = metrics.addTracked(tractions);
    metrics
      ..seed(t, 8)
      ..seed(t, 10);
    await pumpApp(tester, TestWorld(metrics: metrics));
    await openSection(tester, 'data');
    await tapKey(tester, 'tracked-tractions');
    expect(find.byType(MetricDetailScreen), findsOneWidget);

    final day = 'day-${metrics.today.iso}';
    await tapKey(tester, day);
    await tapKey(tester, 'day-correct');
    expect(
      find.textContaining('remplacée par la seule valeur'),
      findsOneWidget,
    );
    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('correct-day-dialog')),
        matching: find.byKey(const Key('entry-value')),
      ),
      '12',
    );
    await tapKey(tester, 'correct-day-save');
    final corrected = metrics.day(t.id, metrics.today)!;
    expect(corrected.sampleCount, 1);
    expect(corrected.value, 12);

    await tapKey(tester, day);
    await tapKey(tester, 'day-delete');
    await tapKey(tester, 'confirm-accept');
    expect(metrics.day(t.id, metrics.today), isNull);
    expect(find.text('Aucune journée enregistrée'), findsOneWidget);
  });
}
