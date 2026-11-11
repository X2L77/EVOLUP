import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:my_training/data/data_error.dart';
import 'package:my_training/data/data_request.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Failure of [guardRead] / [guardWrite] for a request failing with [error].
Future<DataFailure> _failure(Object error, {required bool write}) async {
  Future<int> request() async {
    if (error != 0) throw error;
    return 0;
  }

  try {
    await (write ? guardWrite('test', request) : guardRead('test', request));
  } on DataException catch (e) {
    return e.failure;
  }
  fail('no error');
}

const _short = Duration(milliseconds: 20);

void main() {
  group('T5 · timeouts', () {
    test('a request that answers in time returns its value', () async {
      expect(await guardRead('test', () async => 42, timeout: _short), 42);
      expect(await guardWrite('test', () async => 'ok', timeout: _short), 'ok');
    });

    test('a read without answer ends with a timeout, not a hang', () async {
      final never = Completer<int>();
      await expectLater(
        guardRead('test', () => never.future, timeout: _short),
        throwsA(
          isA<DataException>().having(
            (e) => e.failure,
            'failure',
            DataFailure.timeout,
          ),
        ),
      );
    });

    test('a write without answer is uncertain, never cancelled', () async {
      final never = Completer<int>();
      await expectLater(
        guardWrite('test', () => never.future, timeout: _short),
        throwsA(
          isA<DataException>().having(
            (e) => e.failure,
            'failure',
            DataFailure.writeUncertain,
          ),
        ),
      );
    });

    test('an answer arriving after the timeout is ignored safely', () async {
      final late = Completer<int>();
      await expectLater(
        guardWrite('test', () => late.future, timeout: _short),
        throwsA(isA<DataException>()),
      );
      // Neither a late success nor a late error escapes as an unhandled
      // error once the caller stopped waiting.
      late.completeError(http.ClientException('late'));
      await Future<void>.delayed(_short);
    });

    test('the bounds leave room for slow networks', () {
      expect(
        DataTimeouts.read,
        greaterThanOrEqualTo(const Duration(seconds: 15)),
      );
      expect(DataTimeouts.write, greaterThan(DataTimeouts.read));
    });
  });

  group('T6 · reads', () {
    test('each cause has its own failure', () async {
      expect(
        await _failure(
          http.ClientException('XMLHttpRequest error.'),
          write: false,
        ),
        DataFailure.network,
      );
      expect(
        await _failure(TimeoutException('x'), write: false),
        DataFailure.timeout,
      );
      expect(
        await _failure(
          const PostgrestException(message: 'boom', code: 'XX000'),
          write: false,
        ),
        DataFailure.server,
      );
      expect(
        await _failure(
          const PostgrestException(message: '<html>', code: '502'),
          write: false,
        ),
        DataFailure.server,
      );
      expect(
        await _failure(
          const PostgrestException(
            message: 'permission denied for table user_metrics',
            code: '42501',
          ),
          write: false,
        ),
        DataFailure.notAllowed,
      );
      expect(
        await _failure(AuthSessionMissingException(), write: false),
        DataFailure.sessionExpired,
      );
    });

    test('a read error never talks about saving', () async {
      final errors = <Object>[
        http.ClientException('Failed host lookup: x'),
        TimeoutException('x'),
        const PostgrestException(message: 'boom', code: 'XX000'),
        const PostgrestException(message: '<html>', code: '504'),
        const FormatException('bad'),
        StateError('bug'),
      ];
      for (final error in errors) {
        final message = dataFailureMessage(await _failure(error, write: false));
        expect(message, isNot(contains('enregistr')), reason: '$error');
      }
    });

    test('the word "Connection" alone is not a network error', () {
      expect(
        classifyDataError(StateError('Connection pool exhausted')),
        DataFailure.unknown,
      );
    });
  });

  group('T6 · writes', () {
    test('a connection that never opened: nothing was sent', () async {
      for (final text in [
        "Failed host lookup: 'x.supabase.co'",
        'Connection refused',
        'Network is unreachable',
      ]) {
        final failure = await _failure(http.ClientException(text), write: true);
        expect(failure, DataFailure.writeNotSent, reason: text);
      }
      expect(
        dataFailureMessage(DataFailure.writeNotSent),
        contains('rien n’a été enregistré'),
      );
    });

    test('a connection lost after sending: the outcome is uncertain', () async {
      final uncertain = <Object>[
        TimeoutException('x'),
        http.ClientException(
          'Connection closed before full header was received',
        ),
        http.ClientException('XMLHttpRequest error.'),
        const PostgrestException(message: '<html>', code: '504'),
        const PostgrestException(message: '<html>', code: '502'),
        const FormatException('unreadable answer'),
        StateError('unexpected'),
      ];
      for (final error in uncertain) {
        expect(
          await _failure(error, write: true),
          DataFailure.writeUncertain,
          reason: '$error',
        );
      }
      final message = dataFailureMessage(DataFailure.writeUncertain);
      expect(message, isNot(contains('Rien n’a été enregistré')));
      expect(message, contains('peut-être été enregistrée'));
      expect(message, contains('Vérifiez vos données avant de réessayer'));
    });

    test('a database error is a confirmed failure', () async {
      expect(
        await _failure(
          const PostgrestException(message: 'boom', code: 'XX000'),
          write: true,
        ),
        DataFailure.writeFailed,
      );
      expect(
        dataFailureMessage(DataFailure.writeFailed),
        contains('rien n’a été changé'),
      );
    });

    test('access rules and validation are not network errors', () async {
      expect(
        await _failure(
          const PostgrestException(
            message: 'new row violates row-level security policy',
            code: '42501',
          ),
          write: true,
        ),
        DataFailure.notAllowed,
      );
      expect(
        await _failure(
          const PostgrestException(
            message: 'coach_cannot_write',
            code: '42501',
          ),
          write: true,
        ),
        DataFailure.notAllowed,
      );
      expect(
        await _failure(
          const PostgrestException(
            message: 'value_out_of_range',
            code: '22023',
          ),
          write: true,
        ),
        DataFailure.valueOutOfRange,
      );
      expect(
        await _failure(
          const PostgrestException(message: 'duplicate key', code: '23505'),
          write: true,
        ),
        DataFailure.alreadyTracked,
      );
      expect(
        await _failure(AuthSessionMissingException(), write: true),
        DataFailure.sessionExpired,
      );
      expect(
        dataFailureMessage(DataFailure.notAllowed),
        isNot(contains('réseau')),
      );
    });

    test('a failure decided by the repository is kept as is', () async {
      expect(
        await _failure(
          const DataException(DataFailure.dayNotFound),
          write: true,
        ),
        DataFailure.dayNotFound,
      );
    });
  });

  test('logs carry the error type and code, never its text', () {
    const error = PostgrestException(
      message: 'Key (user_id)=(secret-user-id) already exists',
      code: '23505',
    );
    final line = describeDataErrorForLog(error);
    expect(line, contains('23505'));
    expect(line, isNot(contains('secret-user-id')));
    expect(
      describeDataErrorForLog(
        http.ClientException('x', Uri.parse('https://x.co/?id=eq.secret')),
      ),
      isNot(contains('secret')),
    );
  });

  test('no raw Supabase text ever reaches a message', () {
    for (final failure in DataFailure.values) {
      final message = dataFailureMessage(failure);
      expect(message, isNot(contains('Postgrest')));
      expect(message, isNot(contains('Exception')));
      expect(message, isNot(contains('42501')));
    }
  });
}
