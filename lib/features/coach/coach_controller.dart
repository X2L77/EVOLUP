import 'package:flutter/foundation.dart';

import '../../coach/coach_error.dart';
import '../../coach/coach_repository.dart';

enum CoachAuthor {
  user,

  /// A reply really received from Polomix.
  coach,

  /// A form prepared by the server for a reported value (not a Polomix text).
  action,
}

@immutable
class CoachMessage {
  const CoachMessage({
    required this.id,
    required this.author,
    this.text = '',
    this.consultedMetrics = const [],
    this.action,
  });

  final int id;
  final CoachAuthor author;
  final String text;

  /// Metrics whose data was sent with the question (coach messages).
  final List<String> consultedMetrics;
  final CoachAction? action;
}

/// Temporary conversation with Polomix (kept while the app runs, never
/// saved).
///
/// Only one message is sent at a time. A Polomix message is only ever added
/// from a reply really returned by the repository; a form action is only
/// added from the server's validated action. A failure adds nothing and
/// keeps the user's message for [retry]. Nothing here writes user data.
class CoachController extends ChangeNotifier {
  CoachController(this._repository);

  final CoachRepository? _repository;
  final List<CoachMessage> _messages = [];
  int _nextId = 0;
  bool _sending = false;
  CoachFailure? _failure;
  String? _pendingRetry;
  CoachMessage? _pendingAction;
  bool _disposed = false;

  /// `false` when Supabase is not configured: nothing can be sent.
  bool get isAvailable => _repository != null;
  List<CoachMessage> get messages => List.unmodifiable(_messages);
  bool get isSending => _sending;
  CoachFailure? get failure => _failure;
  bool get canRetry => _pendingRetry != null && !_sending;

  /// The last form action received, until the screen handles it.
  CoachMessage? get pendingAction => _pendingAction;

  void consumeAction() => _pendingAction = null;

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
      final text = reply.text;
      if (text != null) {
        _messages.add(
          CoachMessage(
            id: _nextId++,
            author: CoachAuthor.coach,
            text: text,
            consultedMetrics: reply.consultedMetrics,
          ),
        );
      }
      final action = reply.action;
      if (action != null) {
        final item = CoachMessage(
          id: _nextId++,
          author: CoachAuthor.action,
          action: action,
        );
        _messages.add(item);
        _pendingAction = item;
      }
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
