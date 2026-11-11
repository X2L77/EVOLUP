import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:my_training/app/session/metrics_controller.dart';
import 'package:my_training/app/widgets/state_views.dart';
import 'package:my_training/data/data_error.dart';
import 'package:my_training/data/data_request.dart';
import 'package:my_training/features/data/my_data_screen.dart';
import 'package:my_training/features/entry/entry_controller.dart';
import 'package:my_training/features/overview/overview_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/fake_metrics_repository.dart';
import 'support/test_catalog.dart';
import 'support/test_helpers.dart';

/// Lot 2 (T4, T5, T6) through the controllers and the screens.
void main() {
  group('T5 · loading ends after a timeout', () {
    testWidgets('the overview stops loading and offers a retry', (
      tester,
    ) async {
      final metrics = FakeMetricsRepository()..overviewGate = Completer<void>();
      await pumpInSession(
        tester,
        const OverviewScreen(),
        world: TestWorld(metrics: metrics),
      );
      // pumpInSession settles the screen: the spinner keeps animating until
      // the read bound fires, so it settles only once the timeout ended the
      // loading, although the request never answered.
      await tester.pump(DataTimeouts.read + const Duration(seconds: 1));
      await tester.pump();
      expect(metrics.overviewGate!.isCompleted, isFalse);
      expect(find.byType(LoadingView), findsNothing);
      expect(find.byType(ErrorView), findsOneWidget);
      expect(find.textContaining('trop de temps à répondre'), findsOneWidget);
      expect(find.textContaining('enregistré'), findsNothing);

      metrics.overviewGate = null;
      await tester.tap(find.text('Réessayer'));
      await tester.pumpAndSettle();
      expect(find.byType(ErrorView), findsNothing);
      expect(find.byType(LoadingView), findsNothing);
    });

    testWidgets('a read without network is not shown as a save problem', (
      tester,
    ) async {
      final metrics = FakeMetricsRepository()
        ..overviewError = http.ClientException('XMLHttpRequest error.');
      await pumpInSession(
        tester,
        const OverviewScreen(),
        world: TestWorld(metrics: metrics),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Connexion impossible. Vérifiez votre réseau, puis réessayez.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('enregistré'), findsNothing);
    });

    test(
      'a write finishing after its controller is disposed is harmless',
      () async {
        final repository = FakeMetricsRepository()
          ..deleteAllGate = Completer<void>();
        repository.addTracked(tractions);
        final controller = MetricsController(repository);
        await controller.load();
        final pending = controller.deleteAllTracked();
        controller.dispose();
        repository.deleteAllGate!.complete();
        await pending; // No "used after being disposed" error.
        expect(repository.tracked, isEmpty);
      },
    );

    test('an entry answered after its form is closed is harmless', () async {
      final repository = FakeMetricsRepository()
        ..recordGate = Completer<void>();
      final tracked = repository.addTracked(tractions);
      final metrics = MetricsController(repository);
      await metrics.load();
      final form = EntryController(
        definition: tractions,
        tracked: tracked,
        metrics: metrics,
        timezone: () async => 'Europe/Paris',
      )..setNumber('8');
      final pending = form.submit();
      form.dispose();
      repository.recordGate!.complete();
      expect(await pending, isNotNull);
      metrics.dispose();
    });
  });

  group('T6 · uncertain writes and double taps', () {
    test('an uncertain write reloads what the server really holds', () async {
      final repository = FakeMetricsRepository()
        ..deleteAllAppliedBeforeError = true
        ..deleteAllError = http.ClientException('Connection reset by peer');
      repository.addTracked(tractions);
      repository.addTracked(sommeil);
      final controller = MetricsController(repository);
      await controller.load();
      final revision = controller.revision;

      await expectLater(
        controller.deleteAllTracked(),
        throwsA(
          isA<DataException>().having(
            (e) => e.failure,
            'failure',
            DataFailure.writeUncertain,
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      // The deletion did happen on the server: the app now says so.
      expect(controller.tracked, isEmpty);
      expect(controller.revision, revision + 1);
      controller.dispose();
    });

    testWidgets('tapping « Suivre » twice sends one request', (tester) async {
      final metrics = FakeMetricsRepository()..trackGate = Completer<void>();
      await pumpInSession(
        tester,
        const MyDataScreen(),
        world: TestWorld(metrics: metrics),
      );
      await tester.tap(find.byKey(const Key('track-tractions')));
      await tester.pump();
      await tester.tap(
        find.byKey(const Key('track-tractions')),
        warnIfMissed: false,
      );
      await tester.pump();
      metrics.trackGate!.complete();
      await tester.pumpAndSettle();
      expect(metrics.trackCalls, 1);
      expect(metrics.tracked, hasLength(1));
      expect(find.textContaining('déjà partie'), findsNothing);
      expect(find.textContaining('ajouté à vos données'), findsWidgets);
    });

    test('a second global deletion during the first shares it', () async {
      final repository = FakeMetricsRepository()
        ..deleteAllGate = Completer<void>();
      repository.addTracked(tractions);
      final controller = MetricsController(repository);
      await controller.load();
      final first = controller.deleteAllTracked();
      final second = controller.deleteAllTracked();
      repository.deleteAllGate!.complete();
      await Future.wait([first, second]);
      expect(repository.deleteAllCalls, 1);
      controller.dispose();
    });
  });

  group('T4 · deleting all tracking data', () {
    Future<MetricsController> loaded(FakeMetricsRepository repository) async {
      final controller = MetricsController(repository);
      await controller.load();
      return controller;
    }

    test('several metrics: one request, one reload, everything gone', () async {
      final repository = FakeMetricsRepository();
      for (final d in [tractions, sommeil, humeur]) {
        final t = repository.addTracked(d);
        repository.seed(t, 7);
        repository.seed(t, 8, date: repository.today.addDays(-1));
      }
      final controller = await loaded(repository);
      var notifications = 0;
      controller.addListener(() => notifications++);
      final revision = controller.revision;

      await controller.deleteAllTracked();

      expect(repository.deleteAllCalls, 1);
      expect(repository.deleteTrackedCalls, 0);
      expect(repository.tracked, isEmpty);
      expect(controller.tracked, isEmpty);
      for (final d in [tractions, sommeil, humeur]) {
        expect(controller.trackedFor(d.id), isNull);
      }
      // A single change signal: pages reload once, not once per metric.
      expect(controller.revision, revision + 1);
      expect(notifications, 1);
      controller.dispose();
    });

    test('a refused deletion changes nothing (all or nothing)', () async {
      final repository = FakeMetricsRepository()
        ..deleteAllError = const PostgrestException(
          message: 'internal',
          code: 'XX000',
        );
      final a = repository.addTracked(tractions);
      repository.seed(a, 8);
      repository.addTracked(sommeil);
      final controller = await loaded(repository);
      final revision = controller.revision;

      await expectLater(
        controller.deleteAllTracked(),
        throwsA(
          isA<DataException>().having(
            (e) => e.failure,
            'failure',
            DataFailure.writeFailed,
          ),
        ),
      );
      expect(repository.tracked, hasLength(2));
      expect(repository.dayCount(a.id), 1);
      expect(controller.tracked, hasLength(2));
      expect(controller.revision, revision);
      controller.dispose();
    });

    testWidgets('the settings report success precisely', (tester) async {
      final metrics = FakeMetricsRepository();
      metrics.seed(metrics.addTracked(tractions), 8);
      metrics.addTracked(sommeil);
      metrics.addTracked(humeur);
      await pumpApp(tester, TestWorld(metrics: metrics));
      await openSection(tester, 'settings');
      await tapKey(tester, 'settings-delete-all');
      await tapKey(tester, 'confirm-accept');
      expect(metrics.deleteAllCalls, 1);
      expect(metrics.deleteTrackedCalls, 0);
      expect(metrics.tracked, isEmpty);
      expect(
        find.text('Vos données de suivi sont supprimées.'),
        findsOneWidget,
      );
    });

    testWidgets('the settings report a refused deletion precisely', (
      tester,
    ) async {
      final metrics = FakeMetricsRepository()
        ..deleteAllError = const PostgrestException(
          message: 'permission denied for table user_metrics',
          code: '42501',
        );
      metrics.addTracked(tractions);
      metrics.addTracked(sommeil);
      await pumpApp(tester, TestWorld(metrics: metrics));
      await openSection(tester, 'settings');
      await tapKey(tester, 'settings-delete-all');
      await tapKey(tester, 'confirm-accept');
      expect(metrics.tracked, hasLength(2));
      expect(find.text('Cette action n’est pas autorisée.'), findsOneWidget);
      expect(find.text('Vos données de suivi sont supprimées.'), findsNothing);
    });

    testWidgets('the settings never claim nothing was deleted when unsure', (
      tester,
    ) async {
      final metrics = FakeMetricsRepository()
        ..deleteAllGate = Completer<void>();
      metrics.addTracked(tractions);
      await pumpApp(tester, TestWorld(metrics: metrics));
      await openSection(tester, 'settings');
      await tapKey(tester, 'settings-delete-all');
      await tester.tap(find.byKey(const Key('confirm-accept')));
      await tester.pump();
      await tester.pump();
      // Busy: the button cannot start a second deletion.
      expect(
        tester
            .widget<ButtonStyleButton>(
              find.byKey(const Key('settings-delete-all')),
            )
            .onPressed,
        isNull,
      );

      await tester.pump(DataTimeouts.write + const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.textContaining('peut-être été enregistrée'), findsOneWidget);
      expect(find.textContaining('Rien n’a été'), findsNothing);
      expect(metrics.deleteAllCalls, 1);
      metrics.deleteAllGate!.complete();
      await tester.pumpAndSettle();
    });
  });
}
