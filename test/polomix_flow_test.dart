import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_training/coach/coach_error.dart';
import 'package:my_training/coach/coach_repository.dart';
import 'package:my_training/features/entry/metric_entry_screen.dart';

import 'support/fake_coach_repository.dart';
import 'support/fake_metrics_repository.dart';
import 'support/fake_profile_repository.dart';
import 'support/test_catalog.dart';
import 'support/test_helpers.dart';

void main() {
  final value = find.byKey(const Key('entry-value'));

  Future<void> say(WidgetTester tester, String message) async {
    await tester.enterText(find.byKey(const Key('coach-input')), message);
    await tester.pump();
    await tester.tap(find.byKey(const Key('coach-send')));
    await tester.pumpAndSettle();
    // The form opens after the card's short appearance.
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
  }

  Future<(FakeCoachRepository, FakeMetricsRepository)> pumpPolomix(
    WidgetTester tester, {
    FakeMetricsRepository? metrics,
    FakeProfileRepository? profiles,
    CoachReply? reply,
  }) async {
    final coach = FakeCoachRepository()..nextReply = reply;
    final repository = metrics ?? FakeMetricsRepository();
    await pumpApp(
      tester,
      TestWorld(coach: coach, metrics: repository, profiles: profiles),
    );
    await openSection(tester, 'polomix');
    return (coach, repository);
  }

  testWidgets(
    '« Je viens de faire 8 tractions » opens the right form, pre-filled',
    (tester) async {
      final metrics = FakeMetricsRepository()..addTracked(tractions);
      await pumpPolomix(
        tester,
        metrics: metrics,
        reply: const CoachReply(
          action: CoachAction(metricSlug: 'tractions', suggestedValue: 8),
        ),
      );
      await say(tester, 'Je viens de faire 8 tractions.');

      expect(find.byType(MetricEntryScreen), findsOneWidget);
      expect(find.text('Tractions'), findsWidgets);
      expect(tester.widget<TextField>(value).controller!.text, '8');
      expect(find.byKey(const Key('entry-suggested')), findsOneWidget);
      // Nothing is recorded by Polomix or by the opening of the form.
      expect(metrics.requests, isEmpty);

      // The proposed value stays editable; only « Valider » records.
      await tester.enterText(value, '9');
      await tester.tap(find.byKey(const Key('entry-submit')));
      await tester.pumpAndSettle();
      expect(metrics.requests.single.value, 9);

      await tapKey(tester, 'entry-done');
      expect(find.byKey(const Key('coach-action')), findsOneWidget);
    },
  );

  testWidgets('an untracked metric is proposed for tracking before the form', (
    tester,
  ) async {
    final (_, metrics) = await pumpPolomix(
      tester,
      reply: const CoachReply(
        action: CoachAction(metricSlug: 'pompes', suggestedValue: 20),
      ),
    );
    await say(tester, "J'ai fait 20 pompes");
    expect(find.byKey(const Key('track-confirm')), findsOneWidget);
    expect(find.byType(MetricEntryScreen), findsNothing);
    await tapKey(tester, 'track-confirm-accept');
    expect(metrics.tracked.single.metricCatalogId, pompes.id);
    expect(find.byType(MetricEntryScreen), findsOneWidget);
    expect(tester.widget<TextField>(value).controller!.text, '20');
    expect(metrics.requests, isEmpty);
  });

  testWidgets('declining the proposal opens nothing and adds nothing', (
    tester,
  ) async {
    final (_, metrics) = await pumpPolomix(
      tester,
      reply: const CoachReply(action: CoachAction(metricSlug: 'pompes')),
    );
    await say(tester, "J'ai fait des pompes");
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
    expect(find.byType(MetricEntryScreen), findsNothing);
    expect(metrics.tracked, isEmpty);
  });

  testWidgets('an unknown or retired metric never opens a form', (
    tester,
  ) async {
    for (final slug in ['gainage', 'inconnu']) {
      final (_, metrics) = await pumpPolomix(
        tester,
        reply: CoachReply(action: CoachAction(metricSlug: slug)),
      );
      await say(tester, 'Message');
      expect(find.byKey(const Key('coach-action-invalid')), findsOneWidget);
      expect(find.byType(MetricEntryScreen), findsNothing);
      expect(find.byKey(const Key('track-confirm')), findsNothing);
      expect(metrics.tracked, isEmpty);
    }
  });

  testWidgets('a value outside the catalog bounds is not pre-filled', (
    tester,
  ) async {
    final metrics = FakeMetricsRepository()..addTracked(tractions);
    await pumpPolomix(
      tester,
      metrics: metrics,
      reply: const CoachReply(
        action: CoachAction(metricSlug: 'tractions', suggestedValue: 9000),
      ),
    );
    await say(tester, "J'ai fait 9000 tractions");
    expect(find.byType(MetricEntryScreen), findsOneWidget);
    expect(tester.widget<TextField>(value).controller!.text, isEmpty);
    expect(find.byKey(const Key('entry-suggested')), findsNothing);
  });

  testWidgets('a text reply never creates data', (tester) async {
    final metrics = FakeMetricsRepository()..addTracked(tractions);
    final (coach, _) = await pumpPolomix(
      tester,
      metrics: metrics,
      reply: const CoachReply(
        text: 'Bravo, 8 tractions enregistrées !',
        consultedMetrics: ['tractions'],
      ),
    );
    await say(tester, 'Comment évoluent mes tractions ?');
    expect(find.text('Bravo, 8 tractions enregistrées !'), findsOneWidget);
    expect(find.text('Données consultées : Tractions'), findsOneWidget);
    expect(find.byType(MetricEntryScreen), findsNothing);
    expect(metrics.requests, isEmpty);
    expect(metrics.dayCount(metrics.tracked.single.id), 0);
    expect(coach.sent, ['Comment évoluent mes tractions ?']);
  });

  testWidgets('Polomix down: no fake answer, the rest of the app works', (
    tester,
  ) async {
    final metrics = FakeMetricsRepository()..addTracked(tractions);
    final (coach, _) = await pumpPolomix(tester, metrics: metrics);
    coach.error = const CoachException(CoachFailure.unavailable);
    await say(tester, 'Bonjour');
    expect(find.byKey(const Key('coach-failure')), findsOneWidget);
    expect(find.textContaining('restent accessibles'), findsOneWidget);
    expect(find.text('Réponse du faux coach'), findsNothing);

    await openSection(tester, 'data');
    await tapKey(tester, 'quick-entry-tractions');
    await tester.enterText(value, '8');
    await tester.tap(find.byKey(const Key('entry-submit')));
    await tester.pumpAndSettle();
    expect(metrics.requests.single.value, 8);
  });

  testWidgets('access to the data needs the user\'s consent', (tester) async {
    final profiles = FakeProfileRepository();
    await pumpPolomix(tester, profiles: profiles);
    expect(find.byKey(const Key('coach-consent')), findsOneWidget);
    await tapKey(tester, 'coach-consent-allow');
    expect(profiles.updates.single.coachDataAccess, isTrue);
    expect(profiles.profile!.coachDataAccess, isTrue);
    expect(find.byKey(const Key('coach-consent')), findsNothing);
  });
}
