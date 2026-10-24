import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_training/data/profile_draft.dart';
import 'package:my_training/data/questionnaire_draft_store.dart';
import 'package:my_training/features/home/home_screen.dart';
import 'package:my_training/features/onboarding/questionnaire_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/fake_auth_repository.dart';
import 'support/fake_profile_repository.dart';
import 'support/test_helpers.dart';

void main() {
  late FakeAuthRepository auth;
  late FakeProfileRepository profiles;
  late MemoryDraftStore drafts;

  setUp(() {
    auth = FakeAuthRepository(currentUserId: 'user-1');
    profiles = FakeProfileRepository();
    drafts = MemoryDraftStore();
  });

  tearDown(() => auth.dispose());

  Future<void> start(WidgetTester tester, {Size size = const Size(400, 860)}) =>
      pumpApp(
        tester,
        auth: auth,
        profiles: profiles,
        drafts: drafts,
        size: size,
      );

  Future<void> next(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('questionnaire-continue')));
    await tester.pumpAndSettle();
  }

  Future<void> answerNumber(WidgetTester tester, String value) async {
    await tester.enterText(find.byKey(const Key('answer-number')), value);
    await tester.pump();
  }

  String progress(WidgetTester tester) => tester
      .widget<Text>(find.byKey(const Key('questionnaire-progress')))
      .data!;

  String? error(WidgetTester tester) {
    final finder = find.byKey(const Key('questionnaire-error'));
    return finder.evaluate().isEmpty ? null : tester.widget<Text>(finder).data;
  }

  /// Answers age → frequency → days (3 sessions: Mon, Wed, Fri).
  Future<void> answerBodyAndSchedule(WidgetTester tester) async {
    await answerNumber(tester, '30');
    await next(tester);
    await answerNumber(tester, '180');
    await next(tester);
    await answerNumber(tester, '75,5');
    await next(tester);
    await tapKey(tester, 'sessions-3');
    await next(tester);
    for (final day in ['Lundi', 'Mercredi', 'Vendredi']) {
      await tapKey(tester, 'day-$day');
    }
    await next(tester);
  }

  testWidgets('shows one question at a time with progress', (tester) async {
    await start(tester);
    expect(find.byType(QuestionnaireScreen), findsOneWidget);
    expect(find.text('Quel âge avez-vous ?'), findsOneWidget);
    expect(progress(tester), 'Étape 1 sur 9');
    expect(find.text('Continuer'), findsOneWidget);
    // Questions that were removed from the validated questionnaire.
    expect(find.textContaining('sport'), findsNothing);
    expect(find.textContaining('secondaire'), findsNothing);
  });

  testWidgets('required answers block « Continuer » until valid', (
    tester,
  ) async {
    await start(tester);
    await next(tester);
    expect(error(tester), 'Indiquez un âge entre 15 et 120 ans.');
    await answerNumber(tester, '14');
    await next(tester);
    expect(error(tester), 'Indiquez un âge entre 15 et 120 ans.');
    expect(progress(tester), 'Étape 1 sur 9');

    await answerNumber(tester, '15');
    await next(tester);
    expect(progress(tester), 'Étape 2 sur 9');

    await next(tester);
    expect(error(tester), 'Indiquez une taille entre 80 et 250 cm.');
    await answerNumber(tester, '300');
    await next(tester);
    expect(error(tester), 'Indiquez une taille entre 80 et 250 cm.');
    await answerNumber(tester, '172,5');
    await next(tester);

    await next(tester);
    expect(error(tester), 'Indiquez un poids entre 25 et 350 kg.');
    await answerNumber(tester, '68');
    await next(tester);

    expect(find.text('–'), findsOneWidget);
    await next(tester);
    expect(error(tester), 'Choisissez le nombre de séances par semaine.');
  });

  testWidgets('days must match the number of sessions (at least two)', (
    tester,
  ) async {
    await start(tester);
    await answerNumber(tester, '30');
    await next(tester);
    await answerNumber(tester, '180');
    await next(tester);
    await answerNumber(tester, '80');
    await next(tester);

    // The vertical slider starts at the minimum of 2 sessions.
    final slider = tester.widget<Slider>(
      find.byKey(const Key('sessions-slider')),
    );
    expect(slider.min, 2);
    expect(slider.max, 7);
    await tapKey(tester, 'sessions-3');
    expect(
      tester.widget<Text>(find.byKey(const Key('sessions-value'))).data,
      '3',
    );
    await next(tester);

    await tapKey(tester, 'day-Lundi');
    await tapKey(tester, 'day-Jeudi');
    await next(tester);
    expect(error(tester), 'Sélectionnez exactement 3 jours (2 sélectionnés).');

    await tapKey(tester, 'day-Samedi');
    await tapKey(tester, 'day-Dimanche'); // a 4th day is refused
    expect(find.text('3 / 3 jours sélectionnés'), findsOneWidget);
    await next(tester);
    expect(find.text('Quel est votre niveau sportif ?'), findsOneWidget);

    // Lowering the number of sessions keeps the days visible but invalid.
    await tapKey(tester, 'questionnaire-back');
    await tapKey(tester, 'questionnaire-back');
    await tapKey(tester, 'sessions-2');
    await next(tester);
    await next(tester);
    expect(error(tester), 'Sélectionnez exactement 2 jours (3 sélectionnés).');
    await tapKey(tester, 'day-Samedi');
    await next(tester);
    expect(find.text('Quel est votre niveau sportif ?'), findsOneWidget);
  });

  testWidgets('equipment is only asked for home training', (tester) async {
    await start(tester);
    await answerBodyAndSchedule(tester);
    await tapKey(tester, 'choice-Débutant');
    await next(tester);
    await tapKey(tester, 'choice-Endurance');
    await next(tester);

    expect(find.text('Où vous entraînez-vous ?'), findsOneWidget);
    await tapKey(tester, 'choice-Salle de sport');
    expect(progress(tester), 'Étape 8 sur 9');
    await next(tester);
    expect(find.text('Combien de temps dure une séance ?'), findsOneWidget);

    await tapKey(tester, 'questionnaire-back');
    await tapKey(tester, 'choice-À domicile');
    expect(progress(tester), 'Étape 8 sur 10');
    await next(tester);
    expect(
      find.text('De quel matériel disposez-vous à domicile ?'),
      findsOneWidget,
    );
    await next(tester);
    expect(error(tester), 'Choisissez votre matériel, ou « Aucun matériel ».');
    await tapKey(tester, 'choice-Haltères');
    await tapKey(tester, 'choice-Aucun matériel');
    await tapKey(tester, 'choice-Élastiques');
    await next(tester);

    // Removing home training drops the equipment answer.
    await tapKey(tester, 'questionnaire-back');
    await tapKey(tester, 'questionnaire-back');
    await tapKey(tester, 'choice-À domicile');
    expect(progress(tester), 'Étape 8 sur 9');
    await next(tester);
    await tapKey(tester, 'choice-45');
    await next(tester);

    expect(profiles.saved.single.trainingLocations, ['Salle de sport']);
    expect(profiles.saved.single.homeEquipment, isEmpty);
  });

  testWidgets('going back keeps every answer', (tester) async {
    await start(tester);
    await answerBodyAndSchedule(tester);
    await tapKey(tester, 'choice-Avancé');
    for (var i = 0; i < 5; i++) {
      await tapKey(tester, 'questionnaire-back');
    }
    expect(progress(tester), 'Étape 1 sur 9');
    expect(find.text('30'), findsOneWidget);
    await next(tester);
    expect(find.text('180'), findsOneWidget);
    await next(tester);
    expect(find.text('75,5'), findsOneWidget);
    await next(tester);
    await next(tester);
    expect(find.text('3 / 3 jours sélectionnés'), findsOneWidget);
    await next(tester);
    expect(
      find.descendant(
        of: find.byKey(const Key('choice-Avancé')),
        matching: find.byIcon(Icons.radio_button_checked_rounded),
      ),
      findsOneWidget,
    );
  });

  testWidgets('saves the profile once, confirms, then opens home', (
    tester,
  ) async {
    await start(tester);
    await answerBodyAndSchedule(tester);
    await tapKey(tester, 'choice-Intermédiaire');
    await next(tester);
    await tapKey(tester, 'choice-Force');
    await tester.enterText(find.byKey(const Key('goal-details')), 'Tractions');
    await next(tester);
    await tapKey(tester, 'choice-À domicile');
    await next(tester);
    await tapKey(tester, 'choice-Barre de traction');
    await next(tester);
    await tapKey(tester, 'choice-60');
    expect(find.text('Créer mon profil'), findsOneWidget);

    profiles.saveCompleter = Completer<void>();
    await tester.tap(find.byKey(const Key('questionnaire-continue')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('questionnaire-continue')));
    await tester.pump();
    expect(profiles.saveCalls, 1);
    profiles.saveCompleter!.complete();
    await tester.pumpAndSettle();

    final profile = profiles.saved.single;
    expect(profile.age, 30);
    expect(profile.heightCm, 180);
    expect(profile.weightKg, 75.5);
    expect(profile.weeklySessions, 3);
    expect(profile.trainingDays, ['Lundi', 'Mercredi', 'Vendredi']);
    expect(profile.level, 'Intermédiaire');
    expect(profile.primaryGoal, 'Force');
    expect(profile.goalDetails, 'Tractions');
    expect(profile.trainingLocations, ['À domicile']);
    expect(profile.homeEquipment, ['Barre de traction']);
    expect(profile.sessionDurationMinutes, 60);
    expect(drafts.drafts, isEmpty);

    expect(find.text('Profil enregistré'), findsOneWidget);
    await tapKey(tester, 'questionnaire-finish');
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('a persistence error keeps the answers and allows a retry', (
    tester,
  ) async {
    profiles.saveError = const PostgrestException(
      message: 'relation "public.athlete_profiles" does not exist',
      code: '42P01',
    );
    await start(tester);
    await answerBodyAndSchedule(tester);
    await tapKey(tester, 'choice-Débutant');
    await next(tester);
    await tapKey(tester, 'choice-Reprise progressive');
    await next(tester);
    await tapKey(tester, 'choice-Street workout');
    await next(tester);
    await tapKey(tester, 'choice-30');
    await next(tester);

    expect(
      find.textContaining('Le service de profil n’est pas encore disponible'),
      findsOneWidget,
    );
    expect(find.text('Profil enregistré'), findsNothing);
    expect(find.byType(HomeScreen), findsNothing);
    expect(drafts.drafts['user-1']?.draft.primaryGoal, 'Reprise progressive');

    profiles.saveError = TimeoutException('offline');
    await next(tester);
    expect(
      find.textContaining('vérifiez votre accès à Internet'),
      findsOneWidget,
    );

    profiles.saveError = null;
    await next(tester);
    expect(find.text('Profil enregistré'), findsOneWidget);
    expect(profiles.saved, hasLength(1));
  });

  testWidgets('resumes where the user left after the app was closed', (
    tester,
  ) async {
    drafts.drafts['user-1'] = const SavedQuestionnaire(
      draft: ProfileDraft(
        age: 40,
        heightCm: 170,
        weightKg: 70,
        weeklySessions: 2,
        trainingDays: ['Mardi', 'Jeudi'],
      ),
      step: 'level',
    );
    await start(tester);
    expect(find.text('Quel est votre niveau sportif ?'), findsOneWidget);
    expect(progress(tester), 'Étape 6 sur 9');
    await tapKey(tester, 'questionnaire-back');
    expect(find.text('2 / 2 jours sélectionnés'), findsOneWidget);
  });

  testWidgets('progress is kept on the device while answering', (tester) async {
    await start(tester);
    await answerNumber(tester, '22');
    await next(tester);
    expect(drafts.drafts['user-1']?.draft.age, 22);
    expect(drafts.drafts['user-1']?.step, 'height');
  });

  testWidgets('a completed profile can be edited from home', (tester) async {
    profiles.profile = completedProfile;
    await start(tester);
    await tapKey(tester, 'home-edit-profile');
    expect(find.text('30'), findsOneWidget);
    for (var i = 0; i < 8; i++) {
      await next(tester);
    }
    expect(find.text('Enregistrer'), findsOneWidget);
    await next(tester);
    expect(find.text('Profil mis à jour'), findsOneWidget);
    expect(profiles.saved.single.primaryGoal, completedProfile.primaryGoal);
    await tapKey(tester, 'questionnaire-finish');
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('fits a small phone with the keyboard open', (tester) async {
    await start(tester, size: const Size(320, 568));
    useSurfaceSize(tester, const Size(320, 568), bottomInset: 260);
    await tester.pumpAndSettle();
    final button = tester.getRect(
      find.byKey(const Key('questionnaire-continue')),
    );
    expect(button.bottom, lessThanOrEqualTo(568 - 260));
    await answerNumber(tester, '30');
    await next(tester);
    await answerNumber(tester, '180');
    await next(tester);
    await answerNumber(tester, '80');
    await next(tester);
    await tapKey(tester, 'sessions-7');
    await next(tester);
    expect(tester.takeException(), isNull);
  });
}
