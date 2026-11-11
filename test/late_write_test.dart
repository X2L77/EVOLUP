import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:my_training/app/session/app_session.dart';
import 'package:my_training/app/session/metrics_controller.dart';
import 'package:my_training/data/data_error.dart';
import 'package:my_training/data/data_request.dart';
import 'package:my_training/data/metrics/metric_models.dart';
import 'package:my_training/features/settings/settings_screen.dart';

import 'support/fake_metrics_repository.dart';
import 'support/test_catalog.dart';
import 'support/test_helpers.dart';

/// A write the client stopped waiting for may still be applied by the
/// server after the app re-read its data. The app must end on the server's
/// final state, and a late answer to an older read must never win.
void main() {
  const short = Duration(milliseconds: 20);

  group('the guard keeps track of an abandoned write', () {
    test('settled completes when the abandoned request ends', () async {
      final server = Completer<int>();
      DataException? caught;
      try {
        await guardWrite('test', () => server.future, timeout: short);
      } on DataException catch (e) {
        caught = e;
      }
      expect(caught?.failure, DataFailure.writeUncertain);
      var ended = false;
      unawaited(caught!.settled!.then((_) => ended = true));
      await Future<void>.delayed(short);
      expect(ended, isFalse, reason: 'the request is still running');
      server.complete(1); // Its result is ignored, only its end matters.
      await Future<void>.delayed(Duration.zero);
      expect(ended, isTrue);
    });

    test('settled also completes when the request ends in error', () async {
      final server = Completer<int>();
      DataException? caught;
      try {
        await guardWrite('test', () => server.future, timeout: short);
      } on DataException catch (e) {
        caught = e;
      }
      server.completeError(http.ClientException('Connection reset by peer'));
      await expectLater(caught!.settled, completes);
    });

    test('no signal when nothing is left running', () async {
      Future<DataException> failure(
        Future<int> Function() request, {
        bool write = true,
      }) async {
        try {
          await (write
              ? guardWrite('test', request, timeout: short)
              : guardRead('test', request, timeout: short));
        } on DataException catch (e) {
          return e;
        }
        throw StateError('no error');
      }

      // Connection lost: the request already ended.
      final lost = await failure(
        () async => throw http.ClientException('Connection reset by peer'),
      );
      expect(lost.failure, DataFailure.writeUncertain);
      expect(lost.settled, isNull);
      // A read: its late answer is simply dropped.
      final read = await failure(() => Completer<int>().future, write: false);
      expect(read.failure, DataFailure.timeout);
      expect(read.settled, isNull);
      // A confirmed refusal.
      final refused = await failure(
        () async => throw const DataException(DataFailure.dayNotFound),
      );
      expect(refused.settled, isNull);
    });
  });

  group('re-reading after an uncertain write', () {
    Future<(FakeMetricsRepository, MetricsController)> twoTracked() async {
      final repository = FakeMetricsRepository()
        ..deleteAllGate = Completer<void>();
      repository.addTracked(tractions);
      repository.addTracked(sommeil);
      final controller = MetricsController(repository);
      await controller.load();
      return (repository, controller);
    }

    void startDeletion(MetricsController controller, List<Object> errors) =>
        unawaited(
          controller.deleteAllTracked().then<void>(
            (_) {},
            onError: (Object e) => errors.add(e),
          ),
        );

    testWidgets('a write applied after the first re-read is shown once done', (
      tester,
    ) async {
      final (repository, controller) = await twoTracked();
      final errors = <Object>[];
      startDeletion(controller, errors);

      await tester.pump(DataTimeouts.write + const Duration(seconds: 1));
      expect(errors.single, isA<DataException>());
      expect(
        (errors.single as DataException).failure,
        DataFailure.writeUncertain,
      );
      // Immediate re-read: the server has not applied it yet.
      expect(repository.tracked, hasLength(2));
      expect(controller.tracked, hasLength(2));
      final revision = controller.revision;

      // The abandoned request now ends: the server applied it.
      repository.deleteAllGate!.complete();
      await tester.pump();
      expect(repository.tracked, isEmpty);
      expect(controller.tracked, isEmpty, reason: 'read again once done');
      expect(controller.revision, revision + 1);
      controller.dispose();
    });

    testWidgets(
      'the first re-read answering last does not bring old data back',
      (tester) async {
        final (repository, controller) = await twoTracked();
        final firstRead = Completer<void>();
        repository.trackedGate = firstRead; // The immediate re-read is slow.
        final errors = <Object>[];
        startDeletion(controller, errors);
        await tester.pump(DataTimeouts.write + const Duration(seconds: 1));
        expect(errors, hasLength(1));

        // The write lands; the second re-read answers at once.
        repository.trackedGate = null;
        repository.deleteAllGate!.complete();
        await tester.pump();
        expect(controller.tracked, isEmpty);

        // The first re-read (run before the write landed) answers last.
        firstRead.complete();
        await tester.pump();
        expect(controller.tracked, isEmpty, reason: 'older snapshot dropped');
        controller.dispose();
      },
    );

    testWidgets('a confirmed local change is not undone by an older re-read', (
      tester,
    ) async {
      final repository = FakeMetricsRepository()
        ..deleteAllError = http.ClientException('Connection reset by peer');
      repository.addTracked(tractions);
      final controller = MetricsController(repository);
      await controller.load();
      final slowRead = Completer<void>();
      repository.trackedGate = slowRead;
      final errors = <Object>[];
      startDeletion(controller, errors);
      await tester.pump();
      expect(
        (errors.single as DataException).failure,
        DataFailure.writeUncertain,
      );

      // Meanwhile the user adds a metric, confirmed by the server.
      repository.trackedGate = null;
      await controller.track(pompes);
      expect(controller.trackedFor(pompes.id), isNotNull);

      // The re-read started before that change answers now.
      slowRead.complete();
      await tester.pump();
      expect(controller.trackedFor(pompes.id), isNotNull);
      expect(controller.tracked, hasLength(2));
      controller.dispose();
    });

    testWidgets('nothing happens after the controller is disposed', (
      tester,
    ) async {
      final (repository, controller) = await twoTracked();
      final errors = <Object>[];
      startDeletion(controller, errors);
      await tester.pump(DataTimeouts.write + const Duration(seconds: 1));
      controller.dispose();
      repository.deleteAllGate!.complete();
      await tester.pump(); // No "used after being disposed" error.
      expect(repository.tracked, isEmpty);
    });
  });

  testWidgets('a page keeps the latest reload, not the last answer', (
    tester,
  ) async {
    final metrics = FakeMetricsRepository();
    final tracked = metrics.addTracked(tractions);
    metrics.seed(tracked, 8);
    await pumpApp(tester, TestWorld(metrics: metrics));
    await openSection(tester, 'settings');
    final controller = SessionScope.of(
      tester.element(find.byType(SettingsScreen)),
    ).metrics;
    String summary() => tester
        .widget<Text>(
          find.byKey(const Key('settings-data-summary'), skipOffstage: false),
        )
        .data!;
    expect(summary(), contains('1 journée renseignée'));

    EntryRequest entry(int daysAgo) => EntryRequest(
      trackedMetricId: tracked.id,
      value: 8,
      unit: tractions.storageUnit,
      localDate: metrics.today.addDays(-daysAgo),
      timezone: 'Europe/Paris',
      idempotencyKey: 'key-$daysAgo',
    );

    // Reload 1 reads 2 days but answers late; reload 2 reads 3 days at once.
    final slow = Completer<void>();
    metrics.overviewGate = slow;
    await controller.record(entry(1));
    await tester.pump();
    metrics.overviewGate = null;
    await controller.record(entry(2));
    await tester.pumpAndSettle();
    expect(summary(), contains('3 journées renseignées'));

    slow.complete();
    await tester.pumpAndSettle();
    expect(summary(), contains('3 journées renseignées'));
  });
}
