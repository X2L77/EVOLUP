import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_training/app/shell/app_shell.dart';
import 'package:my_training/app/shell/evolup_nav_bar.dart';
import 'package:my_training/coach/coach_repository.dart';
import 'package:my_training/features/coach/coach_screen.dart';
import 'package:my_training/features/home/home_screen.dart';
import 'package:my_training/features/stats/stats_screen.dart';

import 'support/fake_auth_repository.dart';
import 'support/fake_coach_repository.dart';
import 'support/fake_profile_repository.dart';
import 'support/test_helpers.dart';

void main() {
  Future<FakeAuthRepository> pumpHome(
    WidgetTester tester, {
    Size size = const Size(400, 900),
    CoachRepository? coach,
  }) async {
    final auth = FakeAuthRepository(currentUserId: 'user-1');
    await pumpApp(
      tester,
      auth: auth,
      profiles: FakeProfileRepository(profile: completedProfile),
      coach: coach,
      size: size,
    );
    return auth;
  }

  Finder navItem(String name) => find.byKey(Key('nav-$name'));

  Finder homeScrollable() => find.descendant(
    of: find.byType(HomeScreen),
    matching: find.byType(Scrollable),
  );

  /// The selected item is announced as selected and shows its filled icon.
  void expectSelected(WidgetTester tester, AppDestination selected) {
    for (final destination in AppDestination.values) {
      final isSelected = destination == selected;
      final semantics = tester.widget<Semantics>(
        find
            .descendant(
              of: navItem(destination.name),
              matching: find.byType(Semantics),
            )
            .first,
      );
      expect(semantics.properties.button, isTrue);
      expect(semantics.properties.selected, isSelected, reason: '$destination');
      expect(
        find.descendant(
          of: navItem(destination.name),
          matching: find.byIcon(
            isSelected ? destination.selectedIcon : destination.icon,
          ),
        ),
        findsOneWidget,
        reason: '$destination',
      );
    }
  }

  testWidgets('the bar shows Coach IA, Home and Statistiques, Home centered', (
    tester,
  ) async {
    final auth = await pumpHome(tester);

    final coach = tester.getCenter(navItem('coach'));
    final home = tester.getCenter(navItem('home'));
    final stats = tester.getCenter(navItem('stats'));
    expect(coach.dx, lessThan(home.dx));
    expect(home.dx, lessThan(stats.dx));
    expect(home.dx, moreOrLessEquals(200, epsilon: 0.5));
    expect(home.dx - coach.dx, moreOrLessEquals(stats.dx - home.dx));
    for (final label in ['Coach IA', 'Home', 'Statistiques']) {
      expect(
        find.descendant(
          of: find.byType(EvolupNavBar),
          matching: find.text(label),
        ),
        findsOneWidget,
      );
    }
    expect(find.byIcon(Icons.sms_outlined), findsOneWidget);
    expect(find.byIcon(Icons.home_rounded), findsOneWidget);
    expect(find.byIcon(Icons.bar_chart_outlined), findsOneWidget);
    expectSelected(tester, AppDestination.home);

    // The other pages are only built when first opened.
    expect(find.byType(CoachScreen, skipOffstage: false), findsNothing);
    expect(find.byType(StatsScreen, skipOffstage: false), findsNothing);
    await auth.dispose();
  });

  testWidgets('each destination opens its page and Home brings it back', (
    tester,
  ) async {
    final auth = await pumpHome(tester);

    await tapKey(tester, 'nav-coach');
    expect(find.byType(CoachScreen), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);
    expectSelected(tester, AppDestination.coach);

    await tapKey(tester, 'nav-stats');
    expect(find.byType(StatsScreen), findsOneWidget);
    expect(find.byType(CoachScreen), findsNothing);
    expectSelected(tester, AppDestination.stats);

    await tapKey(tester, 'nav-home');
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(
      find.text('3 par semaine · Lundi, Mercredi, Vendredi'),
      findsOneWidget,
    );
    expectSelected(tester, AppDestination.home);

    // Visited pages stay alive instead of being rebuilt on every change.
    expect(find.byType(CoachScreen, skipOffstage: false), findsOneWidget);
    expect(find.byType(StatsScreen, skipOffstage: false), findsOneWidget);
    await auth.dispose();
  });

  testWidgets('Coach IA opens the chat; Statistiques shows no data', (
    tester,
  ) async {
    final auth = await pumpHome(tester, coach: FakeCoachRepository());

    await tapKey(tester, 'nav-coach');
    expect(find.text('Posez votre question'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(CoachScreen),
        matching: find.byKey(const Key('coach-input')),
      ),
      findsOneWidget,
    );

    await tapKey(tester, 'nav-stats');
    expect(find.text('Bientôt disponible'), findsOneWidget);
    expect(find.textContaining('Aucune donnée'), findsOneWidget);
    await auth.dispose();
  });

  testWidgets('the conversation survives a destination change', (tester) async {
    final coach = FakeCoachRepository()..replyText = 'Réponse reçue';
    final auth = await pumpHome(tester, coach: coach);
    await tapKey(tester, 'nav-coach');
    await tester.enterText(find.byKey(const Key('coach-input')), 'Bonjour');
    await tester.pump();
    await tapKey(tester, 'coach-send');
    expect(find.text('Réponse reçue'), findsOneWidget);

    await tapKey(tester, 'nav-home');
    await tapKey(tester, 'nav-coach');
    expect(find.text('Bonjour'), findsOneWidget);
    expect(find.text('Réponse reçue'), findsOneWidget);
    expect(coach.sent, ['Bonjour']);
    await auth.dispose();
  });

  testWidgets('while typing, the bar steps aside and the field stays visible', (
    tester,
  ) async {
    final auth = await pumpHome(
      tester,
      coach: FakeCoachRepository(),
      size: const Size(360, 740),
    );
    await tapKey(tester, 'nav-coach');
    final input = find.byKey(const Key('coach-input'));
    final bar = tester.getRect(
      find.descendant(
        of: find.byType(EvolupNavBar),
        matching: find.byType(ClipRRect),
      ),
    );
    expect(tester.getRect(input).bottom, lessThanOrEqualTo(bar.top));

    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    expect(navItem('coach'), findsNothing);
    expect(tester.getRect(input).bottom, lessThanOrEqualTo(740 - 300));
    expect(tester.takeException(), isNull);
    await auth.dispose();
  });

  testWidgets('home keeps its scroll position across destination changes', (
    tester,
  ) async {
    final auth = await pumpHome(tester, size: const Size(400, 600));
    await tester.drag(homeScrollable(), const Offset(0, -150));
    await tester.pumpAndSettle();
    final offset = tester
        .state<ScrollableState>(homeScrollable())
        .position
        .pixels;
    expect(offset, greaterThan(0));

    await tapKey(tester, 'nav-coach');
    await tapKey(tester, 'nav-home');
    expect(
      tester.state<ScrollableState>(homeScrollable()).position.pixels,
      offset,
    );
    await auth.dispose();
  });

  testWidgets('the system back action returns home from another page', (
    tester,
  ) async {
    final auth = await pumpHome(tester);
    await tapKey(tester, 'nav-stats');
    expect(find.byType(StatsScreen), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(StatsScreen), findsNothing);
    await auth.dispose();
  });

  testWidgets('the bar floats above the system inset and never hides content', (
    tester,
  ) async {
    tester.view
      ..padding = const FakeViewPadding(bottom: 34)
      ..viewPadding = const FakeViewPadding(bottom: 34);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewPadding);
    final auth = await pumpHome(tester, size: const Size(400, 700));

    final bar = tester.getRect(
      find.descendant(
        of: find.byType(EvolupNavBar),
        matching: find.byType(ClipRRect),
      ),
    );
    expect(bar.bottom, lessThanOrEqualTo(700 - 34 - 8));
    expect(bar.left, greaterThanOrEqualTo(12));
    expect(bar.right, lessThanOrEqualTo(400 - 12));

    await tester.drag(homeScrollable(), const Offset(0, -2000));
    await tester.pumpAndSettle();
    final lastCard = tester.getRect(
      find.descendant(
        of: find.byType(HomeScreen),
        matching: find.textContaining('Le coach IA n’est pas connecté'),
      ),
    );
    expect(lastCard.bottom, lessThanOrEqualTo(bar.top));
    await auth.dispose();
  });

  testWidgets('a small phone with large text shows the bar without overflow', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final auth = await pumpHome(tester, size: const Size(320, 568));
    expect(tester.takeException(), isNull);

    for (final item in ['coach', 'stats', 'home']) {
      await tapKey(tester, 'nav-$item');
      expect(tester.takeException(), isNull, reason: item);
    }
    expect(find.text('Statistiques'), findsOneWidget);
    await auth.dispose();
  });

  testWidgets('the bar steps aside while the keyboard is open', (tester) async {
    final auth = await pumpHome(tester);
    expect(navItem('home'), findsOneWidget);

    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pump();
    expect(navItem('home'), findsNothing);

    tester.view.viewInsets = FakeViewPadding.zero;
    await tester.pump();
    expect(navItem('home'), findsOneWidget);
    await auth.dispose();
  });
}
