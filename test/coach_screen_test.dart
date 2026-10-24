import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_training/coach/coach_error.dart';
import 'package:my_training/coach/coach_repository.dart';
import 'package:my_training/features/coach/coach_screen.dart';
import 'package:my_training/features/coach/widgets/coach_message_bubble.dart';
import 'package:my_training/theme/evolup_theme.dart';

import 'support/fake_coach_repository.dart';
import 'support/test_helpers.dart';

void main() {
  Future<void> pumpCoach(
    WidgetTester tester,
    CoachRepository? repository, {
    Size size = const Size(400, 800),
  }) async {
    useSurfaceSize(tester, size);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildEvolupBrandTheme(),
        home: CoachScreen(repository: repository),
      ),
    );
    await tester.pumpAndSettle();
  }

  final input = find.byKey(const Key('coach-input'));
  final sendButton = find.byKey(const Key('coach-send'));

  bool sendEnabled(WidgetTester tester) =>
      tester.widget<IconButton>(sendButton).onPressed != null;

  Finder bubbles(String text) => find.descendant(
    of: find.byType(CoachMessageBubble),
    matching: find.text(text),
  );

  testWidgets('starts with an honest empty state', (tester) async {
    await pumpCoach(tester, FakeCoachRepository());
    expect(find.text('Posez votre question'), findsOneWidget);
    expect(find.textContaining('Polomix'), findsOneWidget);
    expect(find.textContaining('n’est pas conservée'), findsOneWidget);
    expect(find.byType(CoachMessageBubble), findsNothing);
    expect(sendEnabled(tester), isFalse);

    await tester.enterText(input, '   ');
    await tester.pump();
    expect(sendEnabled(tester), isFalse);
  });

  testWidgets('shows the message, a loading state, then the real reply', (
    tester,
  ) async {
    final repository = FakeCoachRepository(manual: true);
    await pumpCoach(tester, repository);

    await tester.enterText(input, 'Comment bien m’échauffer ?');
    await tester.pump();
    expect(sendEnabled(tester), isTrue);
    await tester.tap(sendButton);
    await tester.pump();

    expect(repository.sent, ['Comment bien m’échauffer ?']);
    expect(bubbles('Comment bien m’échauffer ?'), findsOneWidget);
    expect(find.byKey(const Key('coach-pending')), findsOneWidget);
    expect(tester.widget<TextField>(input).controller!.text, isEmpty);

    // A new message cannot be sent while the reply is awaited.
    await tester.enterText(input, 'Autre question');
    await tester.pump();
    expect(sendEnabled(tester), isFalse);

    repository.reply('Commencez par cinq minutes de mobilité.');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('coach-pending')), findsNothing);
    expect(bubbles('Commencez par cinq minutes de mobilité.'), findsOneWidget);
    expect(sendEnabled(tester), isTrue);
  });

  testWidgets('an error shows no coach answer and can be retried', (
    tester,
  ) async {
    final repository = FakeCoachRepository(manual: true);
    await pumpCoach(tester, repository);
    await tester.enterText(input, 'Bonjour');
    await tester.pump();
    await tester.tap(sendButton);
    await tester.pump();

    repository.fail(const CoachException(CoachFailure.timeout));
    await tester.pumpAndSettle();
    expect(
      find.text('Le coach a mis trop de temps à répondre.'),
      findsOneWidget,
    );
    expect(find.byType(CoachMessageBubble), findsOneWidget);
    expect(bubbles('Bonjour'), findsOneWidget);

    await tester.tap(find.byKey(const Key('coach-retry')));
    await tester.pump();
    expect(repository.sent, ['Bonjour', 'Bonjour']);
    expect(find.byKey(const Key('coach-failure')), findsNothing);
    repository.reply('Bonjour !');
    await tester.pumpAndSettle();
    expect(bubbles('Bonjour'), findsOneWidget);
    expect(bubbles('Bonjour !'), findsOneWidget);
    expect(find.byKey(const Key('coach-retry')), findsNothing);
  });

  testWidgets('a configuration error offers no retry and leaks nothing', (
    tester,
  ) async {
    final repository = FakeCoachRepository()
      ..error = const CoachException(CoachFailure.notConfigured);
    await pumpCoach(tester, repository);
    await tester.enterText(input, 'Bonjour');
    await tester.pump();
    await tester.tap(sendButton);
    await tester.pumpAndSettle();
    expect(
      find.text('Le coach IA n’est pas encore activé. Réessayez plus tard.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('coach-retry')), findsNothing);
    expect(find.textContaining('POLOMIX'), findsNothing);
  });

  testWidgets('a too long message is refused and kept for editing', (
    tester,
  ) async {
    final repository = FakeCoachRepository();
    await pumpCoach(tester, repository);
    final text = 'a' * (coachMaxMessageLength + 1);
    await tester.enterText(input, text);
    await tester.pump();
    expect(find.byKey(const Key('coach-counter')), findsOneWidget);
    await tester.tap(sendButton);
    await tester.pumpAndSettle();
    expect(repository.sent, isEmpty);
    expect(find.textContaining('trop long'), findsOneWidget);
    expect(tester.widget<TextField>(input).controller!.text, text);
  });

  testWidgets(
    'Enter sends and Shift+Enter does not, with a keyboard',
    (tester) async {
      final repository = FakeCoachRepository();
      await pumpCoach(tester, repository);
      await tester.enterText(input, 'Première ligne');
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      expect(repository.sent, isEmpty);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(repository.sent, ['Première ligne']);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'on Android the keyboard send key sends',
    (tester) async {
      final repository = FakeCoachRepository();
      await pumpCoach(tester, repository);
      await tester.enterText(input, 'Bonjour');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(repository.sent, isEmpty);

      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pumpAndSettle();
      expect(repository.sent, ['Bonjour']);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets('the latest message stays visible in a long conversation', (
    tester,
  ) async {
    final repository = FakeCoachRepository();
    await pumpCoach(tester, repository, size: const Size(360, 640));
    for (var i = 1; i <= 8; i++) {
      repository.replyText = 'Réponse numéro $i';
      await tester.enterText(input, 'Question numéro $i');
      await tester.pump();
      await tester.tap(sendButton);
      await tester.pumpAndSettle();
    }
    expect(repository.sent.length, 8);
    expect(bubbles('Réponse numéro 8'), findsOneWidget);
    final latest = tester.getRect(bubbles('Réponse numéro 8'));
    final composer = tester.getRect(input);
    expect(latest.bottom, lessThanOrEqualTo(composer.top));
    expect(latest.top, greaterThan(0));
  });

  testWidgets('without Supabase the coach is shown as unavailable', (
    tester,
  ) async {
    await pumpCoach(tester, null);
    expect(find.text('Coach indisponible'), findsOneWidget);
    expect(tester.widget<TextField>(input).enabled, isFalse);
    expect(sendEnabled(tester), isFalse);
  });

  testWidgets('the composer stays above the keyboard on a small phone', (
    tester,
  ) async {
    await pumpCoach(tester, FakeCoachRepository(), size: const Size(320, 568));
    tester.view.viewInsets = const FakeViewPadding(bottom: 260);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(tester.getRect(input).bottom, lessThanOrEqualTo(568 - 260));
    expect(tester.getRect(sendButton).bottom, lessThanOrEqualTo(568 - 260));
  });
}
