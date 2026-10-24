import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'coach_error.dart';

/// Same limit as `MAX_MESSAGE_LENGTH` in the coach-chat Edge Function.
const coachMaxMessageLength = 2000;

/// A reply really received from the coach (Polomix, through the server).
@immutable
class CoachReply {
  const CoachReply({required this.text, this.model});

  /// Reads the function's `{"kind": "chat", "reply", "model"}` response.
  /// Anything else is rejected rather than shown as a coach answer.
  factory CoachReply.fromResponse(Object? data) {
    if (data is Map && data['kind'] == 'chat') {
      final reply = data['reply'];
      final model = data['model'];
      if (reply is String && reply.trim().isNotEmpty) {
        return CoachReply(
          text: reply.trim(),
          model: model is String ? model : null,
        );
      }
    }
    throw const CoachException(CoachFailure.badResponse);
  }

  final String text;
  final String? model;
}

/// Sends chat messages to the coach. Implementations never invent a reply:
/// they return the server's answer or throw.
abstract interface class CoachRepository {
  Future<CoachReply> sendMessage(String message);
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

  @override
  Future<CoachReply> sendMessage(String message) async {
    if (_client.auth.currentSession == null) {
      throw const CoachException(CoachFailure.notSignedIn);
    }
    final response = await _client.functions
        .invoke(functionName, body: {'kind': 'chat', 'message': message})
        .timeout(timeout);
    return CoachReply.fromResponse(response.data);
  }
}
