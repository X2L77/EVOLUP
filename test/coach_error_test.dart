import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_training/coach/coach_error.dart';
import 'package:my_training/coach/coach_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

FunctionException _functionError(int status, [String? code]) =>
    FunctionException(
      status: status,
      details: code == null
          ? null
          : {
              'error': {'code': code, 'message': 'x'},
            },
    );

void main() {
  test('function error codes map to coach failures', () {
    final cases = {
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
        classifyCoachError(_functionError(400, code)),
        failure,
        reason: code,
      );
    });
  });

  test('without a known code the HTTP status decides', () {
    expect(classifyCoachError(_functionError(401)), CoachFailure.notSignedIn);
    expect(classifyCoachError(_functionError(404)), CoachFailure.notConfigured);
    expect(classifyCoachError(_functionError(429)), CoachFailure.rateLimited);
    expect(classifyCoachError(_functionError(504)), CoachFailure.timeout);
    expect(classifyCoachError(_functionError(500)), CoachFailure.unavailable);
    expect(classifyCoachError(_functionError(418)), CoachFailure.unknown);
  });

  test('transport errors are classified', () {
    expect(classifyCoachError(TimeoutException('x')), CoachFailure.timeout);
    expect(
      classifyCoachError(const AuthException('expired')),
      CoachFailure.notSignedIn,
    );
    expect(classifyCoachError(StateError('x')), CoachFailure.unknown);
  });

  test('a chat response gives the reply, the context and a valid action', () {
    final reply = CoachReply.fromResponse({
      'kind': 'chat',
      'reply': '  Bonjour  ',
      'model': 'chatix-25',
      'action': null,
      'context': {
        'metrics': ['tractions'],
        'data_access': true,
      },
    });
    expect(reply.text, 'Bonjour');
    expect(reply.model, 'chatix-25');
    expect(reply.action, isNull);
    expect(reply.consultedMetrics, ['tractions']);
    expect(reply.dataAccess, isTrue);

    final action = CoachReply.fromResponse({
      'kind': 'chat',
      'reply': null,
      'action': {
        'type': 'open_metric_form',
        'metric_slug': 'tractions',
        'suggested_value': 8,
      },
    });
    expect(action.text, isNull);
    expect(action.action!.metricSlug, 'tractions');
    expect(action.action!.suggestedValue, 8);
  });

  test('anything else is rejected rather than shown or opened', () {
    for (final data in <Object?>[
      null,
      'text',
      {'reply': 'x'},
      {'kind': 'chat', 'reply': '   '},
      {'kind': 'chat', 'reply': 42},
      {
        'kind': 'chat',
        'action': {'type': 'record_value', 'metric_slug': 'tractions'},
      },
      {
        'kind': 'chat',
        'action': {'type': 'open_metric_form', 'metric_slug': '../admin'},
      },
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
    // An invalid action next to a reply is dropped, the reply is kept.
    final reply = CoachReply.fromResponse({
      'kind': 'chat',
      'reply': 'Texte',
      'action': {'type': 'delete_everything'},
    });
    expect(reply.action, isNull);
    expect(reply.text, 'Texte');
    expect(
      CoachAction.fromJson({
        'type': 'open_metric_form',
        'metric_slug': 'tractions',
        'suggested_value': 'huit',
      })!.suggestedValue,
      isNull,
    );
  });

  test('the compatibility probe is read check by check', () {
    final probe = CoachProbe.fromResponse({
      'kind': 'probe',
      'ok': false,
      'latency_ms': 1200,
      'checks': {
        'secret': true,
        'reachable': true,
        'authorized': false,
        'contract': null,
      },
      'error': 'coach_unavailable',
    }, DateTime(2026, 11, 9));
    expect(probe.ok, isFalse);
    expect(probe.authorized, isFalse);
    expect(probe.contract, isNull);
    expect(probe.failure, CoachFailure.unavailable);
    expect(probe.latencyMs, 1200);
  });

  test('only transient failures are retryable', () {
    expect(CoachFailure.timeout.isRetryable, isTrue);
    expect(CoachFailure.network.isRetryable, isTrue);
    expect(CoachFailure.notConfigured.isRetryable, isFalse);
    expect(CoachFailure.messageTooLong.isRetryable, isFalse);
  });
}
