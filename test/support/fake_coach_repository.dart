import 'dart:async';

import 'package:my_training/coach/coach_repository.dart';

/// In-memory coach. By default it answers immediately with [replyText];
/// with [manual], each call waits for [reply] or [fail].
class FakeCoachRepository implements CoachRepository {
  FakeCoachRepository({this.manual = false});

  final bool manual;
  final List<String> sent = [];
  final List<Completer<CoachReply>> _pending = [];
  String replyText = 'Réponse du faux coach';
  Object? error;

  int get pendingCount => _pending.length;

  @override
  Future<CoachReply> sendMessage(String message) {
    sent.add(message);
    if (manual) {
      final completer = Completer<CoachReply>();
      _pending.add(completer);
      return completer.future;
    }
    final error = this.error;
    if (error != null) return Future.error(error);
    return Future.value(CoachReply(text: replyText));
  }

  void reply(String text) =>
      _pending.removeAt(0).complete(CoachReply(text: text));

  void fail(Object error) => _pending.removeAt(0).completeError(error);
}
