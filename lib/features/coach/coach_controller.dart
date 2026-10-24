import 'package:flutter/foundation.dart';

import '../../coach/coach_error.dart';
import '../../coach/coach_repository.dart';

enum CoachAuthor { user, coach }

@immutable
class CoachMessage {
  const CoachMessage({
    required this.id,
    required this.author,
    required this.text,
  });

  final int id;
  final CoachAuthor author;
  final String text;
}

/// Temporary conversation with the coach (kept while the app runs, never
/// saved).
///
/// Only one message is sent at a time. A coach message is only ever added
/// from a reply really returned by the repository: a failure adds nothing
/// and keeps the user's message for [retry].
class CoachController extends ChangeNotifier {
  CoachController(this._repository);

  final CoachRepository? _repository;
  final List<CoachMessage> _messages = [];
  int _nextId = 0;
  bool _sending = false;
  CoachFailure? _failure;
  String? _pendingRetry;
  bool _disposed = false;

  /// `false` when Supabase is not configured: nothing can be sent.
  bool get isAvailable => _repository != null;
  List<CoachMessage> get messages => List.unmodifiable(_messages);
  bool get isSending => _sending;
  CoachFailure? get failure => _failure;
  bool get canRetry => _pendingRetry != null && !_sending;

  /// Sends [text]. Returns `false` when it was not sent (empty, too long,
  /// request already running, coach unavailable).
  Future<bool> send(String text) async {
    final message = text.trim();
    if (_sending || _repository == null || message.isEmpty) return false;
    if (message.length > coachMaxMessageLength) {
      _failure = CoachFailure.messageTooLong;
      _pendingRetry = null;
      _notify();
      return false;
    }
    _messages.add(
      CoachMessage(id: _nextId++, author: CoachAuthor.user, text: message),
    );
    return _request(message);
  }

  /// Sends the last unanswered message again, without duplicating it.
  Future<bool> retry() async {
    final message = _pendingRetry;
    if (message == null || _sending) return false;
    return _request(message);
  }

  Future<bool> _request(String message) async {
    _sending = true;
    _failure = null;
    _pendingRetry = null;
    _notify();
    try {
      final reply = await _repository!.sendMessage(message);
      _messages.add(
        CoachMessage(
          id: _nextId++,
          author: CoachAuthor.coach,
          text: reply.text,
        ),
      );
      return true;
    } on Object catch (error) {
      final failure = classifyCoachError(error);
      _failure = failure;
      if (failure.isRetryable) _pendingRetry = message;
      return false;
    } finally {
      _sending = false;
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
