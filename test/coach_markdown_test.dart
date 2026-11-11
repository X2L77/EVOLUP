import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_training/features/coach/coach_controller.dart';
import 'package:my_training/features/coach/widgets/coach_message_bubble.dart';
import 'package:my_training/theme/evolup_theme.dart';

void main() {
  Future<void> pumpBubble(
    WidgetTester tester,
    String text, {
    CoachAuthor author = CoachAuthor.coach,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildEvolupTheme(),
        home: Scaffold(
          body: ListView(
            children: [
              CoachMessageBubble(
                message: CoachMessage(id: 0, author: author, text: text),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Every text span shown in the bubble, with its effective style.
  List<(String, TextStyle)> spans(WidgetTester tester) {
    final result = <(String, TextStyle)>[];
    void visit(InlineSpan span, TextStyle inherited) {
      if (span is! TextSpan) return;
      final style = inherited.merge(span.style);
      if (span.text != null) result.add((span.text!, style));
      for (final child in span.children ?? const <InlineSpan>[]) {
        visit(child, style);
      }
    }

    final texts = find.descendant(
      of: find.byType(CoachMessageBubble),
      matching: find.byType(RichText),
    );
    for (final text in tester.widgetList<RichText>(texts)) {
      visit(text.text, const TextStyle());
    }
    return result;
  }

  TextStyle styleOf(WidgetTester tester, String text) =>
      spans(tester).firstWhere((span) => span.$1 == text).$2;

  String shownText(WidgetTester tester) =>
      spans(tester).map((span) => span.$1).join();

  testWidgets('bold is rendered, not shown as asterisks', (tester) async {
    await pumpBubble(tester, 'Un point **Important** ici.');
    expect(styleOf(tester, 'Important').fontWeight, FontWeight.w700);
    expect(styleOf(tester, 'Un point ').fontWeight, isNot(FontWeight.w700));
    expect(shownText(tester), 'Un point Important ici.');
  });

  testWidgets('italic is rendered, not shown as asterisks', (tester) async {
    await pumpBubble(tester, 'Du *texte en italique* et _aussi_.');
    expect(styleOf(tester, 'texte en italique').fontStyle, FontStyle.italic);
    expect(styleOf(tester, 'aussi').fontStyle, FontStyle.italic);
    expect(shownText(tester), 'Du texte en italique et aussi.');
  });

  testWidgets('headings are real titles, larger than the body', (tester) async {
    await pumpBubble(tester, '## Programme\n\n### Mon titre\n\nTexte.');
    final h2 = styleOf(tester, 'Programme');
    final h3 = styleOf(tester, 'Mon titre');
    final body = styleOf(tester, 'Texte.');
    expect(h3.fontWeight, FontWeight.w700);
    expect(h3.fontSize, greaterThan(body.fontSize!));
    expect(h2.fontSize, greaterThan(h3.fontSize!));
    expect(body.fontWeight, isNot(FontWeight.w700));
    expect(shownText(tester), isNot(contains('#')));
  });

  testWidgets('bullet and numbered lists are laid out as lists', (
    tester,
  ) async {
    await pumpBubble(
      tester,
      'À faire :\n\n- Premier élément\n- Deuxième élément\n\n'
      '1. Échauffement\n2. Course',
    );
    final shown = shownText(tester);
    expect('•'.allMatches(shown).length, 2);
    for (final text in [
      'Premier élément',
      'Deuxième élément',
      '1.',
      '2.',
      'Échauffement',
      'Course',
    ]) {
      expect(
        spans(tester).any((span) => span.$1 == text),
        isTrue,
        reason: text,
      );
    }
    expect(shown, isNot(contains('- ')));
    // Each item is on its own line, in order.
    final first = tester.getRect(find.text('Premier élément'));
    final second = tester.getRect(find.text('Deuxième élément'));
    expect(second.top, greaterThan(first.bottom - 1));
  });

  testWidgets('plain text keeps its line breaks and paragraphs', (
    tester,
  ) async {
    await pumpBubble(tester, 'Bonjour !\nComment allez-vous ?\n\nÀ bientôt.');
    expect(
      spans(tester).any((span) => span.$1 == 'Bonjour !\nComment allez-vous ?'),
      isTrue,
    );
    expect(spans(tester).any((span) => span.$1 == 'À bientôt.'), isTrue);
    expect(styleOf(tester, 'À bientôt.').fontWeight, isNot(FontWeight.w700));
  });

  testWidgets('code is shown in a monospace font', (tester) async {
    await pumpBubble(tester, 'Tapez `squat` puis :\n\n```\n3 x 10\n```');
    expect(styleOf(tester, 'squat').fontFamily, 'monospace');
    expect(styleOf(tester, '3 x 10').fontFamily, 'monospace');
    expect(shownText(tester), isNot(contains('`')));
  });

  testWidgets('HTML, images and links are never executed or fetched', (
    tester,
  ) async {
    await pumpBubble(
      tester,
      'Voir <b>ceci</b> <script>alert(1)</script>\n\n'
      '<div onclick="steal()">bloc HTML</div>\n\n'
      '![Photo de squat](https://example.com/squat.png)\n\n'
      '[le site](https://example.com)',
    );
    expect(tester.takeException(), isNull);
    // Raw HTML stays visible as text; nothing interprets it.
    expect(shownText(tester), contains('<b>ceci</b>'));
    expect(shownText(tester), contains('<script>alert(1)</script>'));
    expect(shownText(tester), contains('<div onclick="steal()">bloc HTML'));
    // No image is loaded: only its alternative text is shown.
    expect(find.byType(Image), findsNothing);
    expect(find.text('Photo de squat'), findsOneWidget);
    // A link is plain text, styled like the rest of the reply.
    expect(
      styleOf(tester, 'le site').decoration,
      isNot(TextDecoration.underline),
    );
    await tester.tap(find.text('le site'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets("the user's own message is shown exactly as typed", (
    tester,
  ) async {
    await pumpBubble(
      tester,
      '**pas du gras** et # pas un titre',
      author: CoachAuthor.user,
    );
    expect(find.text('**pas du gras** et # pas un titre'), findsOneWidget);
  });

  testWidgets('a coach reply stays selectable and readable', (tester) async {
    await pumpBubble(tester, 'Réponse **simple**.');
    expect(
      find.descendant(
        of: find.byType(CoachMessageBubble),
        matching: find.byType(SelectionArea),
      ),
      findsOneWidget,
    );
    expect(styleOf(tester, 'Réponse ').color, EvolupColors.brand.textPrimary);
  });
}
