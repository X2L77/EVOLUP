import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_training/coach/coach_error.dart';
import 'package:my_training/coach/coach_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  Map<String, Object> body(String code) => {
    'error': {'code': code, 'message': 'x'},
  };

  test('function error codes map to coach failures', () {
    const cases = {
      'unauthorized': CoachFailure.notSignedIn,
      'message_too_long': CoachFailure.messageTooLong,
      'empty_message': CoachFailure.invalidMessage,
      'invalid_request': CoachFailure.invalidMessage,
      'invalid_json': CoachFailure.invalidMessage,
      'unsupported_kind': CoachFailure.invalidMessage,
      'payload_too_large': CoachFailure.invalidMessage,
      'rate_limited': CoachFailure.rateLimited,
      'coach_not_configured': CoachFailure.notConfigured,
      'coach_quota_reached': CoachFailure.quotaReached,
      'coach_rejected': CoachFailure.rejected,
      'coach_timeout': CoachFailure.timeout,
      'coach_bad_response': CoachFailure.badResponse,
      'coach_unavailable': CoachFailure.unavailable,
      'origin_not_allowed': CoachFailure.unavailable,
    };
    cases.forEach((code, failure) {
      expect(
        classifyCoachError(
          FunctionsHttpException(status: 400, details: body(code)),
        ),
        failure,
        reason: code,
      );
    });
  });

  test('without a known code the HTTP status decides', () {
    const cases = {
      401: CoachFailure.notSignedIn,
      404: CoachFailure.notConfigured,
      429: CoachFailure.rateLimited,
      500: CoachFailure.unavailable,
      503: CoachFailure.unavailable,
      504: CoachFailure.timeout,
      418: CoachFailure.unknown,
    };
    cases.forEach((status, failure) {
      expect(
        classifyCoachError(
          FunctionsHttpException(status: status, details: 'texte brut'),
        ),
        failure,
        reason: '$status',
      );
    });
  });

  test('transport errors are classified', () {
    expect(
      classifyCoachError(const FunctionsFetchException(details: 'offline')),
      CoachFailure.network,
    );
    expect(
      classifyCoachError(const FunctionsRelayException(status: 502)),
      CoachFailure.unavailable,
    );
    expect(classifyCoachError(TimeoutException('slow')), CoachFailure.timeout);
    expect(
      classifyCoachError(const AuthException('expired')),
      CoachFailure.notSignedIn,
    );
    expect(classifyCoachError(StateError('?')), CoachFailure.unknown);
  });

  test('only a well-formed chat response becomes a coach reply', () {
    final reply = CoachReply.fromResponse({
      'kind': 'chat',
      'reply': '  Bonne séance !  ',
      'model': 'chatix-25',
    });
    expect(reply.text, 'Bonne séance !');
    expect(reply.model, 'chatix-25');

    for (final data in <Object?>[
      null,
      'texte',
      <String, Object>{},
      {'reply': 'Sans kind'},
      {'kind': 'task', 'reply': 'Mauvais type'},
      {'kind': 'chat', 'reply': '   '},
      {'kind': 'chat', 'reply': 42},
    ]) {
      expect(
        () => CoachReply.fromResponse(data),
        throwsA(
          isA<CoachException>().having(
            (e) => e.failure,
            'failure',
            CoachFailure.badResponse,
          ),
        ),
        reason: '$data',
      );
    }
  });

  test('only transient failures are retryable', () {
    expect(CoachFailure.values.where((f) => f.isRetryable).toSet(), {
      CoachFailure.rateLimited,
      CoachFailure.quotaReached,
      CoachFailure.unavailable,
      CoachFailure.timeout,
      CoachFailure.network,
      CoachFailure.badResponse,
      CoachFailure.unknown,
    });
  });
}
