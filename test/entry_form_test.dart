import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_training/data/local_date.dart';
import 'package:my_training/features/entry/metric_entry_screen.dart';

import 'support/fake_metrics_repository.dart';
import 'support/test_catalog.dart';
import 'support/test_helpers.dart';

void main() {
  final submit = find.byKey(const Key('entry-submit'));
  final value = find.byKey(const Key('entry-value'));

  /// Opens the form of [definition] from « Mes données », in the whole app.
  Future<FakeMetricsRepository> openFromMyData(
    WidgetTester tester, {
    FakeMetricsRepository? metrics,
    Size size = const Size(400, 900),
  }) async {
    final repository = metrics ?? FakeMetricsRepository();
    if (repository.tracked.isEmpty) repository.addTracked(tractions);
    await pumpApp(tester, TestWorld(metrics: repository), size: size);
    await openSection(tester, 'data');
    await tapKey(tester, 'quick-entry-tractions');
    return repository;
  }

  testWidgets('opens from Mes données: name top left, category, today', (
    tester,
  ) async {
    await openFromMyData(tester);
    expect(find.byType(MetricEntryScreen), findsOneWidget);
    final title = find.byKey(const Key('entry-title'));
    expect(tester.widget<Text>(title).data, 'Tractions');
    final topLeft = tester.getTopLeft(title);
    expect(topLeft.dx, lessThan(40));
    expect(topLeft.dy, lessThan(140));
    expect(
      tester.widget<Text>(find.byKey(const Key('entry-category'))).data,
      'Sport',
    );
    expect(find.textContaining('Aujourd’hui'), findsOneWidget);
    expect(find.textContaining('rép.'), findsWidgets);
  });

  testWidgets('values are checked before anything is sent', (tester) async {
    final metrics = await openFromMyData(tester);
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(find.text('Saisissez une valeur.'), findsOneWidget);

    await tester.enterText(value, '501');
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('entry-field-error')), findsOneWidget);
    expect(find.textContaining('hors limites'), findsOneWidget);

    // Letters and decimals cannot even be typed for repetitions.
    await tester.enterText(value, '8,5a');
    await tester.pump();
    expect(tester.widget<TextField>(value).controller!.text, '85');
    expect(metrics.requests, isEmpty);
  });

  testWidgets('« Valider » really records once, with the local date and zone', (
    tester,
  ) async {
    final metrics = await openFromMyData(tester);
    await tester.enterText(value, '8');
    await tester.tap(submit);
    await tester.pumpAndSettle();

    final request = metrics.requests.single;
    expect(request.value, 8);
    expect(request.unit, 'repetition');
    expect(request.localDate, LocalDate.today());
    expect(request.timezone, 'Europe/Paris');
    expect(find.byKey(const Key('entry-saved')), findsOneWidget);
    expect(find.text('Valeur enregistrée'), findsOneWidget);
    expect(
      metrics.day(metrics.tracked.single.id, LocalDate.today())!.sampleCount,
      1,
    );

    await tapKey(tester, 'entry-done');
    expect(find.byType(MetricEntryScreen), findsNothing);
  });

  testWidgets('cancelling records nothing', (tester) async {
    final metrics = await openFromMyData(tester);
    await tester.enterText(value, '9');
    await tapKey(tester, 'entry-close');
    expect(find.byType(MetricEntryScreen), findsNothing);
    expect(metrics.requests, isEmpty);
  });

  testWidgets('8 then 10 on the same day: one day, average 9, 2 entries', (
    tester,
  ) async {
    final metrics = await openFromMyData(tester);
    await tester.enterText(value, '8');
    await tester.tap(submit);
    await tester.pumpAndSettle();
    await tapKey(tester, 'entry-another');
    await tester.enterText(value, '10');
    await tester.tap(submit);
    await tester.pumpAndSettle();
    final summary = tester
        .widget<Text>(find.byKey(const Key('entry-saved-summary')))
        .data!;
    expect(summary, contains('9 rép.'));
    expect(summary, contains('moyenne du jour'));
    expect(summary, contains('2 saisies'));
    expect(metrics.dayCount(metrics.tracked.single.id), 1);
  });

  testWidgets('a repeated tap sends a single request', (tester) async {
    final metrics = FakeMetricsRepository()..recordGate = Completer<void>();
    await openFromMyData(tester, metrics: metrics);
    await tester.enterText(value, '8');
    await tester.tap(submit);
    await tester.pump();
    await tester.tap(submit, warnIfMissed: false);
    await tester.pump();
    expect(metrics.requests, hasLength(1));
    expect(tester.widget<FilledButton>(submit).onPressed, isNull);
    metrics.recordGate!.complete();
    await tester.pumpAndSettle();
    expect(metrics.requests, hasLength(1));
    expect(find.text('Valeur enregistrée'), findsOneWidget);
  });

  testWidgets(
    'a network error is never shown as a success; a retry is not counted twice',
    (tester) async {
      final metrics = FakeMetricsRepository()
        ..recordError = TimeoutException('offline');
      await openFromMyData(tester, metrics: metrics);
      await tester.enterText(value, '8');
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('entry-error')), findsOneWidget);
      // The request may have reached the server: never "nothing saved".
      expect(find.textContaining('Rien n’a été enregistré'), findsNothing);
      expect(find.textContaining('peut-être été enregistrée'), findsOneWidget);
      expect(find.text('Valeur enregistrée'), findsNothing);

      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(metrics.requests, hasLength(2));
      // Same entry, same idempotency key.
      expect(
        metrics.requests[0].idempotencyKey,
        metrics.requests[1].idempotencyKey,
      );
      expect(find.text('Valeur enregistrée'), findsOneWidget);
    },
  );

  testWidgets('the same value on the same day is reported as a duplicate', (
    tester,
  ) async {
    final metrics = FakeMetricsRepository();
    metrics.seed(metrics.addTracked(tractions), 8);
    await openFromMyData(tester, metrics: metrics);
    await tester.enterText(value, '8');
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('entry-duplicate')), findsOneWidget);
    expect(find.text('Valeur enregistrée'), findsNothing);
    expect(
      metrics.day(metrics.tracked.single.id, metrics.today)!.sampleCount,
      1,
    );
  });

  testWidgets('a past date can be chosen, never a future one', (tester) async {
    final today = LocalDate(2026, 11, 9);
    final metrics = FakeMetricsRepository(today: today);
    final tracked = metrics.addTracked(tractions);
    await pumpInSession(
      tester,
      MetricEntryScreen(definition: tractions, tracked: tracked, today: today),
      world: TestWorld(metrics: metrics),
    );
    expect(find.text('Aujourd’hui · lundi 9 novembre 2026'), findsOneWidget);
    await tapKey(tester, 'entry-date-change');
    // Days after today are disabled in the picker.
    await tester.tap(find.text('3'));
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('mardi 3 novembre 2026'), findsOneWidget);

    await tester.enterText(value, '8');
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(metrics.requests.single.localDate, LocalDate(2026, 11, 3));
    expect(metrics.day(tracked.id, LocalDate(2026, 11, 3)), isNotNull);
  });

  testWidgets('durations are typed in hours and minutes', (tester) async {
    final metrics = FakeMetricsRepository();
    final tracked = metrics.addTracked(sommeil);
    await pumpInSession(
      tester,
      MetricEntryScreen(definition: sommeil, tracked: tracked),
      world: TestWorld(metrics: metrics),
    );
    await tester.enterText(find.byKey(const Key('entry-duration-hours')), '7');
    await tester.enterText(
      find.byKey(const Key('entry-duration-minutes')),
      '30',
    );
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(metrics.requests.single.value, 27000);
    expect(metrics.requests.single.unit, 'second');
  });

  testWidgets('scores use the allowed notes only', (tester) async {
    final metrics = FakeMetricsRepository();
    final tracked = metrics.addTracked(humeur);
    await pumpInSession(
      tester,
      MetricEntryScreen(definition: humeur, tracked: tracked),
      world: TestWorld(metrics: metrics),
    );
    expect(find.byKey(const Key('entry-score-0')), findsNothing);
    expect(find.byKey(const Key('entry-score-11')), findsNothing);
    await tester.tap(find.byKey(const Key('entry-score-7')));
    await tester.pump();
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(metrics.requests.single.value, 7);
  });

  testWidgets('the form stays usable with the keyboard on a small phone', (
    tester,
  ) async {
    await openFromMyData(tester, size: const Size(360, 640));
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(tester.getRect(submit).bottom, lessThanOrEqualTo(640 - 300));
    expect(tester.getRect(value).bottom, lessThanOrEqualTo(640 - 300));
  });
}
