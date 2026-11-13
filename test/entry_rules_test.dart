import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:my_training/app/session/metrics_controller.dart';
import 'package:my_training/data/data_error.dart';
import 'package:my_training/data/local_date.dart';
import 'package:my_training/data/metrics/metric_models.dart';
import 'package:my_training/features/entry/entry_controller.dart';
import 'package:my_training/features/entry/metric_entry_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/fake_metrics_repository.dart';
import 'support/test_catalog.dart';
import 'support/test_helpers.dart';

/// Lot of 2026-11-12: new entries at most one year back (B2), the form
/// across midnight or a change of time zone (B5), confirmed duplicates.
void main() {
  final submit = find.byKey(const Key('entry-submit'));
  final value = find.byKey(const Key('entry-value'));

  /// A form controller on a session-less MetricsController whose device's
  /// day is [day] (read through [clock]).
  Future<(EntryController, FakeMetricsRepository)> form({
    required LocalDate Function() clock,
    FakeMetricsRepository? repository,
  }) async {
    final fake = repository ?? FakeMetricsRepository(today: clock());
    final tracked = fake.tracked.isEmpty
        ? fake.addTracked(tractions)
        : fake.tracked.first;
    final metrics = MetricsController(fake, today: clock);
    await metrics.load();
    addTearDown(metrics.dispose);
    final controller = EntryController(
      definition: tractions,
      tracked: tracked,
      metrics: metrics,
      timezone: () async => 'Europe/Paris',
      clock: clock,
    );
    addTearDown(controller.dispose);
    return (controller, fake);
  }

  group('B2 · one year back at most', () {
    test('the same calendar day one year ago is the oldest allowed', () async {
      final (entry, _) = await form(clock: () => LocalDate(2026, 11, 12));
      expect(entry.earliestDate, LocalDate(2025, 11, 12));
      entry.setDate(LocalDate(2025, 11, 11));
      expect(entry.date, LocalDate(2026, 11, 12));
      entry.setDate(LocalDate(2025, 11, 12));
      expect(entry.date, LocalDate(2025, 11, 12));
      entry.setDate(LocalDate(2026, 11, 13));
      expect(entry.date, LocalDate(2025, 11, 12));
    });

    test('29 February: one year back is 28 February', () async {
      final (entry, _) = await form(clock: () => LocalDate(2028, 2, 29));
      expect(entry.earliestDate, LocalDate(2027, 2, 28));
    });

    test('the server refusals are explained in French', () {
      String message(String code) =>
          dataErrorMessage(PostgrestException(message: code, code: '22023'));
      expect(message('date_too_old'), contains('dernière année'));
      expect(
        classifyDataError(PostgrestException(message: 'too_many_points')),
        DataFailure.tooManyPoints,
      );
      expect(message('too_many_points'), contains('365 jours'));
      expect(message('invalid_today'), contains('date de votre appareil'));
      expect(message('invalid_period'), 'Cette période n’est pas valide.');
    });

    testWidgets('the form says how far back a date may go', (tester) async {
      final metrics = FakeMetricsRepository(today: LocalDate(2026, 11, 12));
      final tracked = metrics.addTracked(tractions);
      await pumpInSession(
        tester,
        MetricEntryScreen(definition: tractions, tracked: tracked),
        world: TestWorld(metrics: metrics)..clock = DateTime(2026, 11, 12, 9),
      );
      expect(
        find.text('Jusqu’à un an en arrière, depuis le 12 novembre 2025.'),
        findsOneWidget,
      );
    });
  });

  group('B5 · the form across a change of day', () {
    test('the default date follows the new day', () async {
      var day = LocalDate(2026, 11, 12);
      final (entry, _) = await form(clock: () => day);
      day = LocalDate(2026, 11, 13);
      expect(entry.refreshDay(), isTrue);
      expect(entry.date, LocalDate(2026, 11, 13));
      expect(entry.today, LocalDate(2026, 11, 13));
      expect(entry.dayChange, DayChange.followed);
      expect(entry.refreshDay(), isFalse);
    });

    test('a chosen date is kept while it is allowed', () async {
      var day = LocalDate(2026, 11, 12);
      final (entry, _) = await form(clock: () => day);
      entry.setDate(LocalDate(2026, 11, 10));
      day = LocalDate(2026, 11, 13);
      entry.refreshDay();
      expect(entry.date, LocalDate(2026, 11, 10));
      expect(entry.dayChange, DayChange.kept);
    });

    test('a chosen date that became future is brought back to today', () async {
      var day = LocalDate(2026, 11, 14);
      final (entry, _) = await form(clock: () => day);
      entry.setDate(LocalDate(2026, 11, 13));
      // Across the date line, westward: two days back.
      day = LocalDate(2026, 11, 12);
      entry.refreshDay();
      expect(entry.date, LocalDate(2026, 11, 12));
      expect(entry.dayChange, DayChange.clampedToToday);
    });

    test('a chosen date that became older than one year is the oldest '
        'allowed one', () async {
      var day = LocalDate(2026, 11, 12);
      final (entry, _) = await form(clock: () => day);
      entry.setDate(LocalDate(2025, 11, 12));
      day = LocalDate(2026, 11, 13);
      entry.refreshDay();
      expect(entry.date, LocalDate(2025, 11, 13));
      expect(entry.dayChange, DayChange.clampedToEarliest);
    });

    test('a change of day at « Valider » sends nothing; the next one sends '
        'the new date', () async {
      var day = LocalDate(2026, 11, 12);
      final (entry, fake) = await form(clock: () => day);
      entry.setNumber('8');
      day = LocalDate(2026, 11, 13);
      fake.today = day;
      expect(await entry.submit(), isNull);
      expect(fake.requests, isEmpty);
      expect(entry.dayChange, DayChange.followed);
      expect((await entry.submit())!.status, EntryStatus.recorded);
      expect(fake.requests.single.localDate, LocalDate(2026, 11, 13));
    });

    testWidgets('the open form shows the new date and says why', (
      tester,
    ) async {
      final metrics = FakeMetricsRepository(today: LocalDate(2026, 11, 12));
      final tracked = metrics.addTracked(tractions);
      final world = TestWorld(metrics: metrics)
        ..clock = DateTime(2026, 11, 12, 23, 59);
      final session = await pumpInSession(
        tester,
        MetricEntryScreen(definition: tractions, tracked: tracked),
        world: world,
      );
      expect(find.text('Aujourd’hui · jeudi 12 novembre 2026'), findsOneWidget);
      await tester.enterText(value, '8');

      world.clock = DateTime(2026, 11, 13, 0, 0, 30);
      metrics.today = LocalDate(2026, 11, 13);
      session.day.check();
      await tester.pumpAndSettle();
      expect(
        find.text('Aujourd’hui · vendredi 13 novembre 2026'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('entry-day-changed')), findsOneWidget);
      expect(metrics.requests, isEmpty);

      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(find.text('Valeur enregistrée'), findsOneWidget);
      expect(metrics.requests.single.localDate, LocalDate(2026, 11, 13));
    });
  });

  group('identical value on the same day', () {
    Future<(FakeMetricsRepository, TrackedMetric)> openWithEight(
      WidgetTester tester,
    ) async {
      final metrics = FakeMetricsRepository(today: LocalDate(2026, 11, 12));
      final tracked = metrics.addTracked(tractions);
      metrics.seed(tracked, 8);
      await pumpInSession(
        tester,
        MetricEntryScreen(definition: tractions, tracked: tracked),
        world: TestWorld(metrics: metrics)..clock = DateTime(2026, 11, 12, 18),
      );
      await tester.enterText(value, '8');
      await tester.tap(submit);
      await tester.pumpAndSettle();
      return (metrics, tracked);
    }

    testWidgets('the user is asked; nothing is counted before the answer', (
      tester,
    ) async {
      final (metrics, tracked) = await openWithEight(tester);
      expect(find.byKey(const Key('entry-duplicate')), findsOneWidget);
      expect(
        find.textContaining('S’agit-il d’une nouvelle mesure ?'),
        findsOneWidget,
      );
      expect(tester.widget<FilledButton>(submit).onPressed, isNull);
      expect(metrics.day(tracked.id, metrics.today)!.sampleCount, 1);
    });

    testWidgets('« Oui, nouvelle mesure » counts it, with the same key', (
      tester,
    ) async {
      final (metrics, tracked) = await openWithEight(tester);
      await tapKey(tester, 'entry-duplicate-new');
      expect(find.text('Valeur enregistrée'), findsOneWidget);
      final day = metrics.day(tracked.id, metrics.today)!;
      expect(day.sampleCount, 2);
      expect(day.valueSum, 16);
      expect(metrics.requests, hasLength(2));
      expect(metrics.requests.first.confirmDuplicate, isFalse);
      expect(metrics.requests.last.confirmDuplicate, isTrue);
      expect(
        metrics.requests.last.idempotencyKey,
        metrics.requests.first.idempotencyKey,
      );
    });

    testWidgets('« Non, erreur de saisie » records nothing and says so', (
      tester,
    ) async {
      final (metrics, tracked) = await openWithEight(tester);
      await tapKey(tester, 'entry-duplicate-mistake');
      expect(find.byKey(const Key('entry-duplicate')), findsNothing);
      expect(find.byKey(const Key('entry-duplicate-rejected')), findsOneWidget);
      expect(metrics.requests, hasLength(1));
      expect(metrics.day(tracked.id, metrics.today)!.sampleCount, 1);
      // The form is still usable: another value can be sent.
      await tester.enterText(value, '9');
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(find.text('Valeur enregistrée'), findsOneWidget);
      expect(metrics.day(tracked.id, metrics.today)!.sampleCount, 2);
    });

    testWidgets('a confirmation lost on the network can be retried, '
        'counted once', (tester) async {
      final (metrics, tracked) = await openWithEight(tester);
      metrics.recordError = http.ClientException('Failed host lookup');
      await tapKey(tester, 'entry-duplicate-new');
      expect(find.byKey(const Key('entry-error')), findsOneWidget);
      // Still waiting for the answer to the question.
      expect(find.byKey(const Key('entry-duplicate')), findsOneWidget);
      await tapKey(tester, 'entry-duplicate-new');
      expect(find.text('Valeur enregistrée'), findsOneWidget);
      expect(metrics.day(tracked.id, metrics.today)!.sampleCount, 2);
    });
  });
}
