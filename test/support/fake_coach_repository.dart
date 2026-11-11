import 'dart:async';

import 'package:my_training/coach/coach_repository.dart';

/// In-memory Polomix server. By default it answers immediately with
/// [replyText]; with [manual], each call waits for [reply] or [fail].
class FakeCoachRepository implements CoachRepository {
  FakeCoachRepository({this.manual = false});

  final bool manual;
  final List<String> sent = [];
  final List<Completer<CoachReply>> _pending = [];
  String replyText = 'Réponse du faux coach';

  /// Returned instead of [replyText] when set.
  CoachReply? nextReply;
  Object? error;
  CoachStatus statusValue = const CoachStatus(
    configured: true,
    model: 'chatix-25',
  );
  CoachProbe? probeValue;
  int probeCalls = 0;

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
    final reply = nextReply ?? CoachReply(text: replyText);
    nextReply = null;
    return Future.value(reply);
  }

  void reply(String text) =>
      _pending.removeAt(0).complete(CoachReply(text: text));

  void fail(Object error) => _pending.removeAt(0).completeError(error);

  @override
  Future<CoachStatus> status() async => statusValue;

  @override
  Future<CoachProbe> probe() async {
    probeCalls++;
    final error = this.error;
    if (error != null) throw error;
    return probeValue ??
        CoachProbe(
          ok: true,
          checkedAt: DateTime(2026, 11, 9, 10, 30),
          secret: true,
          reachable: true,
          authorized: true,
          contract: true,
          latencyMs: 820,
          model: 'chatix-25',
        );
  }
}
