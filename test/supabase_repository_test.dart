import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:my_training/data/data_error.dart';
import 'package:my_training/data/data_request.dart';
import 'package:my_training/data/local_date.dart';
import 'package:my_training/data/metrics/metric_models.dart';
import 'package:my_training/data/metrics/metrics_repository.dart';
import 'package:my_training/data/profile/profile_repository.dart';
import 'package:my_training/data/profile/user_profile.dart';

import 'support/supabase_test_server.dart';

/// The real Supabase repositories against a fake HTTP server: no network,
/// no Supabase project. Widget tests give a fake clock for the timeouts.
const _userId = testUserId;

typedef _Server = SupabaseTestServer;

http.Response _json(Object body, [int status = 200]) =>
    jsonResponse(body, status);

final _entry = EntryRequest(
  trackedMetricId: 'um-1',
  value: 8,
  unit: 'repetition',
  localDate: LocalDate(2026, 11, 2),
  timezone: 'Europe/Paris',
  idempotencyKey: '22222222-2222-2222-2222-222222222222',
);

Matcher _fails(DataFailure failure) =>
    isA<DataException>().having((e) => e.failure, 'failure', failure);

/// Runs [future] under the test's fake clock, advancing it by [elapse].
Future<Object?> _errorOf(
  WidgetTester tester,
  Future<Object?> future, {
  Duration elapse = Duration.zero,
}) async {
  Object? error;
  var done = false;
  unawaited(
    future.then<void>(
      (_) => done = true,
      onError: (Object e) {
        error = e;
        done = true;
      },
    ),
  );
  await tester.pump(elapse);
  await tester.pump();
  expect(done, isTrue, reason: 'the operation is still running');
  return error;
}

void main() {
  group('T5 · timeouts on the real repository', () {
    testWidgets('a read answering in time succeeds', (tester) async {
      // The shape of `get_overview` (a new user's day, no metric yet).
      final server = _Server(
        (_) async => _json({
          'today': '2026-11-11',
          'timezone': 'Europe/Paris',
          'min_days': 3,
          'days_recorded': 3,
          'entries_count': 3,
          'first_date': '2026-11-01',
          'metrics': <Object>[],
        }),
      );
      final repository = SupabaseMetricsRepository(server.client);
      Overview? overview;
      unawaited(repository.loadOverview().then((o) => overview = o));
      await tester.pump();
      expect(overview?.daysRecorded, 3);
    });

    testWidgets('a read without answer stops after the read bound', (
      tester,
    ) async {
      final server = _Server((_) => Completer<http.Response>().future);
      final repository = SupabaseMetricsRepository(server.client);
      final pending = repository.loadOverview();
      final error = await _errorOf(
        tester,
        pending,
        elapse: DataTimeouts.read + const Duration(seconds: 1),
      );
      expect(error, _fails(DataFailure.timeout));
    });

    testWidgets('an entry without answer is uncertain after the write bound', (
      tester,
    ) async {
      final server = _Server((_) => Completer<http.Response>().future);
      final repository = SupabaseMetricsRepository(server.client);
      final pending = repository.recordEntry(_entry);
      // Still waiting just before the bound: a slow server is not cut short.
      await tester.pump(DataTimeouts.read + const Duration(seconds: 1));
      final error = await _errorOf(
        tester,
        pending,
        elapse: DataTimeouts.write - DataTimeouts.read,
      );
      expect(error, _fails(DataFailure.writeUncertain));
      expect(server.requests, hasLength(1), reason: 'never resent');
    });
  });

  group('T6 · errors of the real repository', () {
    testWidgets('a network error on a read', (tester) async {
      final server = _Server(
        (_) async => throw http.ClientException('XMLHttpRequest error.'),
      );
      final error = await _errorOf(
        tester,
        SupabaseMetricsRepository(server.client).loadOverview(),
      );
      expect(error, _fails(DataFailure.network));
    });

    testWidgets('a server error on a read', (tester) async {
      final server = _Server(
        (_) async => _json({'code': 'XX000', 'message': 'internal'}, 500),
      );
      final error = await _errorOf(
        tester,
        SupabaseMetricsRepository(server.client).loadOverview(),
      );
      expect(error, _fails(DataFailure.server));
      expect(
        dataErrorMessage(error!),
        'Le serveur a rencontré un problème. Réessayez dans un instant.',
      );
    });

    testWidgets('writes: confirmed refusals and uncertain outcomes', (
      tester,
    ) async {
      final cases = <String, (Future<http.Response> Function(), DataFailure)>{
        'validation': (
          () async =>
              _json({'code': '22023', 'message': 'value_out_of_range'}, 400),
          DataFailure.valueOutOfRange,
        ),
        'access rules': (
          () async => _json({
            'code': '42501',
            'message': 'permission denied for function record_metric_entry',
          }, 403),
          DataFailure.notAllowed,
        ),
        'database error': (
          () async => _json({'code': 'XX000', 'message': 'internal'}, 500),
          DataFailure.writeFailed,
        ),
        'gateway timeout': (
          () async => http.Response('<html>504</html>', 504),
          DataFailure.writeUncertain,
        ),
        'connection lost': (
          () async => throw http.ClientException(
            'Connection closed before full header was received',
          ),
          DataFailure.writeUncertain,
        ),
        'unreadable answer': (
          () async => _json({'status': 'unexpected'}),
          DataFailure.writeUncertain,
        ),
        'no connection': (
          () async =>
              throw http.ClientException("Failed host lookup: 'localhost'"),
          DataFailure.writeNotSent,
        ),
      };
      for (final MapEntry(key: name, value: (respond, expected))
          in cases.entries) {
        final server = _Server((_) => respond());
        final error = await _errorOf(
          tester,
          SupabaseMetricsRepository(server.client).recordEntry(_entry),
        );
        expect(error, _fails(expected), reason: name);
      }
    });

    testWidgets('a profile change refused by RLS is not a network error', (
      tester,
    ) async {
      final server = _Server(
        (_) async => _json({
          'code': '42501',
          'message': 'new row violates row-level security policy',
        }, 403),
      );
      await server.signIn();
      final error = await _errorOf(
        tester,
        SupabaseProfileRepository(
          server.client,
        ).update(const ProfileChanges(displayName: 'Léo')),
      );
      expect(error, _fails(DataFailure.notAllowed));
    });
  });

  group('T4 · deleting all tracked metrics', () {
    testWidgets('one DELETE limited to the signed-in user', (tester) async {
      final server = _Server(
        (_) async => _json([
          {'id': 'a'},
          {'id': 'b'},
          {'id': 'c'},
        ]),
      );
      await server.signIn();
      int? deleted;
      unawaited(
        SupabaseMetricsRepository(
          server.client,
        ).deleteAllTracked().then((n) => deleted = n),
      );
      await tester.pump();
      expect(deleted, 3);
      expect(server.requests, hasLength(1));
      final request = server.requests.single;
      expect(request.method, 'DELETE');
      expect(request.url.path, '/rest/v1/user_metrics');
      expect(request.url.queryParameters['user_id'], 'eq.$_userId');
      expect(request.headers['Authorization'], 'Bearer test-access-token');
    });

    testWidgets('without a session nothing is sent', (tester) async {
      final server = _Server((_) async => _json([]));
      final error = await _errorOf(
        tester,
        SupabaseMetricsRepository(server.client).deleteAllTracked(),
      );
      expect(error, _fails(DataFailure.sessionExpired));
      expect(server.requests, isEmpty);
    });

    testWidgets('an interrupted deletion is uncertain, not "nothing deleted"', (
      tester,
    ) async {
      final server = _Server(
        (_) async => throw http.ClientException('Connection reset by peer'),
      );
      await server.signIn();
      final error = await _errorOf(
        tester,
        SupabaseMetricsRepository(server.client).deleteAllTracked(),
      );
      expect(error, _fails(DataFailure.writeUncertain));
    });
  });
}
