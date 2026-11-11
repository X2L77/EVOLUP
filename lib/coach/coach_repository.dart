import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'coach_error.dart';

/// Same limit as `MAX_MESSAGE_LENGTH` in the coach-chat Edge Function.
const coachMaxMessageLength = 2000;

/// A form that Polomix's server asks the app to open. It never records
/// anything: the app checks the metric against the catalog, then the user
/// fills, checks and validates the form.
@immutable
class CoachAction {
  const CoachAction({required this.metricSlug, this.suggestedValue});

  static final _slug = RegExp(r'^[a-z][a-z0-9_]{1,63}$');

  /// Reads `{"type": "open_metric_form", "metric_slug", "suggested_value"}`;
  /// anything else is ignored (`null`), never turned into a form.
  static CoachAction? fromJson(Object? data) {
    if (data is! Map || data['type'] != 'open_metric_form') return null;
    final slug = data['metric_slug'];
    if (slug is! String || !_slug.hasMatch(slug)) return null;
    final value = data['suggested_value'];
    return CoachAction(
      metricSlug: slug,
      suggestedValue: value is num && value.isFinite ? value : null,
    );
  }

  final String metricSlug;

  /// In the metric's storage unit; only pre-fills the field.
  final num? suggestedValue;
}

/// What the server returned for a message: Polomix's reply, a form to open,
/// or both. Never invented: built only from the server's response.
@immutable
class CoachReply {
  const CoachReply({
    this.text,
    this.model,
    this.action,
    this.consultedMetrics = const [],
    this.dataAccess,
  });

  /// Reads the function's `{"kind": "chat", "reply", "action", "context"}`
  /// response. A response with neither a reply nor a valid action is
  /// rejected rather than shown.
  factory CoachReply.fromResponse(Object? data) {
    if (data is Map && data['kind'] == 'chat') {
      final reply = data['reply'];
      final model = data['model'];
      final text = reply is String && reply.trim().isNotEmpty
          ? reply.trim()
          : null;
      final action = CoachAction.fromJson(data['action']);
      final context = data['context'];
      final metrics = context is Map ? context['metrics'] : null;
      final access = context is Map ? context['data_access'] : null;
      if (text != null || action != null) {
        return CoachReply(
          text: text,
          model: model is String ? model : null,
          action: action,
          consultedMetrics: metrics is List
              ? metrics.whereType<String>().toList()
              : const [],
          dataAccess: access is bool ? access : null,
        );
      }
    }
    throw const CoachException(CoachFailure.badResponse);
  }

  /// Polomix's reply, as received.
  final String? text;
  final String? model;
  final CoachAction? action;

  /// Slugs of the metrics whose data was sent with the question.
  final List<String> consultedMetrics;
  final bool? dataAccess;
}

@immutable
class CoachStatus {
  const CoachStatus({required this.configured, this.model});

  final bool configured;
  final String? model;
}

/// Result of the compatibility test with Polomix (Paramètres). Each check is
/// `null` when it could not be evaluated.
@immutable
class CoachProbe {
  const CoachProbe({
    required this.ok,
    required this.checkedAt,
    this.secret,
    this.reachable,
    this.authorized,
    this.contract,
    this.latencyMs,
    this.model,
    this.failure,
  });

  factory CoachProbe.fromResponse(Object? data, DateTime checkedAt) {
    if (data is! Map || data['kind'] != 'probe') {
      throw const CoachException(CoachFailure.badResponse);
    }
    final checks = data['checks'] is Map ? data['checks'] as Map : const {};
    bool? check(String name) =>
        checks[name] is bool ? checks[name] as bool : null;
    final error = data['error'];
    return CoachProbe(
      ok: data['ok'] == true,
      checkedAt: checkedAt,
      secret: check('secret'),
      reachable: check('reachable'),
      authorized: check('authorized'),
      contract: check('contract'),
      latencyMs: (data['latency_ms'] as num?)?.toInt(),
      model: data['model'] as String?,
      failure: error is String ? failureForCode(error) : null,
    );
  }

  final bool ok;
  final DateTime checkedAt;
  final bool? secret;
  final bool? reachable;
  final bool? authorized;
  final bool? contract;
  final int? latencyMs;
  final String? model;
  final CoachFailure? failure;
}

/// Talks to Polomix through the server. Implementations never invent a
/// reply: they return the server's answer or throw.
abstract interface class CoachRepository {
  Future<CoachReply> sendMessage(String message);
  Future<CoachStatus> status();
  Future<CoachProbe> probe();
}

/// Calls the `coach-chat` Edge Function with the user's Supabase session.
/// Polomix and its key stay on the server.
class SupabaseCoachRepository implements CoachRepository {
  SupabaseCoachRepository(
    this._client, {
    this.timeout = const Duration(seconds: 45),
  });

  static const functionName = 'coach-chat';

  final SupabaseClient _client;

  /// Above the function's own 30-second limit for Polomix.
  final Duration timeout;

  Future<Object?> _invoke(Map<String, dynamic> body) async {
    if (_client.auth.currentSession == null) {
      throw const CoachException(CoachFailure.notSignedIn);
    }
    final response = await _client.functions
        .invoke(functionName, body: body)
        .timeout(timeout);
    return response.data;
  }

  @override
  Future<CoachReply> sendMessage(String message) async =>
      CoachReply.fromResponse(
        await _invoke({'kind': 'chat', 'message': message}),
      );

  @override
  Future<CoachStatus> status() async {
    final data = await _invoke({'kind': 'status'});
    if (data is! Map || data['kind'] != 'status') {
      throw const CoachException(CoachFailure.badResponse);
    }
    return CoachStatus(
      configured: data['configured'] == true,
      model: data['model'] as String?,
    );
  }

  @override
  Future<CoachProbe> probe() async =>
      CoachProbe.fromResponse(await _invoke({'kind': 'probe'}), DateTime.now());
}
