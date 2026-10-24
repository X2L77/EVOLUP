import 'package:flutter_test/flutter_test.dart';
import 'package:my_training/coach/coach_error.dart';
import 'package:my_training/coach/coach_repository.dart';
import 'package:my_training/features/coach/coach_controller.dart';

import 'support/fake_coach_repository.dart';

void main() {
  test('a message gets the reply really returned by the repository', () async {
    final repository = FakeCoachRepository(manual: true);
    final chat = CoachController(repository);

    final sending = chat.send('  Bonjour  ');
    expect(chat.isSending, isTrue);
    expect(chat.messages.single.text, 'Bonjour');
    expect(chat.messages.single.author, CoachAuthor.user);
    expect(repository.sent, ['Bonjour']);

    repository.reply('Bonjour, comment puis-je aider ?');
    expect(await sending, isTrue);
    expect(chat.isSending, isFalse);
    expect(chat.messages.map((m) => (m.author, m.text)), [
      (CoachAuthor.user, 'Bonjour'),
      (CoachAuthor.coach, 'Bonjour, comment puis-je aider ?'),
    ]);
    expect(chat.failure, isNull);
  });

  test('empty messages are not sent', () async {
    final repository = FakeCoachRepository();
    final chat = CoachController(repository);
    expect(await chat.send(''), isFalse);
    expect(await chat.send('   \n '), isFalse);
    expect(repository.sent, isEmpty);
    expect(chat.messages, isEmpty);
  });

  test('a too long message is refused before any call', () async {
    final repository = FakeCoachRepository();
    final chat = CoachController(repository);
    expect(await chat.send('a' * (coachMaxMessageLength + 1)), isFalse);
    expect(chat.failure, CoachFailure.messageTooLong);
    expect(chat.canRetry, isFalse);
    expect(repository.sent, isEmpty);
    expect(chat.messages, isEmpty);

    expect(await chat.send('a' * coachMaxMessageLength), isTrue);
    expect(chat.failure, isNull);
  });

  test('only one message is sent at a time', () async {
    final repository = FakeCoachRepository(manual: true);
    final chat = CoachController(repository);
    final first = chat.send('Un');
    expect(await chat.send('Deux'), isFalse);
    expect(repository.sent, ['Un']);
    repository.reply('Ok');
    await first;
    expect(chat.messages.length, 2);
  });

  test('a failure adds no coach message and allows a retry', () async {
    final repository = FakeCoachRepository(manual: true);
    final chat = CoachController(repository);

    final sending = chat.send('Bonjour');
    repository.fail(const CoachException(CoachFailure.unavailable));
    expect(await sending, isFalse);
    expect(chat.failure, CoachFailure.unavailable);
    expect(chat.canRetry, isTrue);
    expect(chat.messages.where((m) => m.author == CoachAuthor.coach), isEmpty);

    final retrying = chat.retry();
    expect(chat.failure, isNull);
    expect(repository.sent, ['Bonjour', 'Bonjour']);
    repository.reply('Réponse');
    expect(await retrying, isTrue);
    expect(chat.messages.map((m) => m.text), ['Bonjour', 'Réponse']);
    expect(chat.canRetry, isFalse);
  });

  test('errors that a retry cannot fix offer no retry', () async {
    final repository = FakeCoachRepository()
      ..error = const CoachException(CoachFailure.notConfigured);
    final chat = CoachController(repository);
    expect(await chat.send('Bonjour'), isFalse);
    expect(chat.failure, CoachFailure.notConfigured);
    expect(chat.canRetry, isFalse);
    expect(await chat.retry(), isFalse);
  });

  test('without a repository the coach is unavailable', () async {
    final chat = CoachController(null);
    expect(chat.isAvailable, isFalse);
    expect(await chat.send('Bonjour'), isFalse);
    expect(chat.messages, isEmpty);
  });

  test('a reply arriving after dispose is ignored safely', () async {
    final repository = FakeCoachRepository(manual: true);
    final chat = CoachController(repository);
    final sending = chat.send('Bonjour');
    chat.dispose();
    repository.reply('Trop tard');
    expect(await sending, isTrue);
  });
}
