import 'package:flutter_test/flutter_test.dart';
import 'package:my_training/data/athlete_profile.dart';
import 'package:my_training/data/profile_draft.dart';
import 'package:my_training/data/profile_rules.dart';
import 'package:my_training/features/onboarding/questionnaire_controller.dart';
import 'package:my_training/features/onboarding/questionnaire_messages.dart';
import 'package:my_training/features/onboarding/questionnaire_step.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  const filled = ProfileDraft(
    age: 25,
    heightCm: 175,
    weightKg: 70,
    weeklySessions: 2,
    trainingDays: ['Lundi', 'Jeudi'],
    level: 'Débutant',
    primaryGoal: 'Force',
    trainingLocations: ['Salle de sport'],
    sessionDurationMinutes: 45,
  );

  QuestionnaireController controllerAtLastStep({
    required Future<void> Function(AthleteProfile) onSave,
    ProfileDraft draft = filled,
  }) => QuestionnaireController(
    draft: draft,
    initialStep: QuestionnaireStep.sessionDuration.name,
    onSave: onSave,
  );

  test('the equipment step only exists for home training', () {
    expect(
      QuestionnaireStep.stepsFor(filled),
      isNot(contains(QuestionnaireStep.homeEquipment)),
    );
    final atHome = filled.copyWith(trainingLocations: [ProfileRules.home]);
    expect(
      QuestionnaireStep.stepsFor(atHome),
      contains(QuestionnaireStep.homeEquipment),
    );
  });

  test('« Aucun matériel » excludes other equipment', () {
    final controller = QuestionnaireController(onSave: (_) async {})
      ..toggleLocation(ProfileRules.home)
      ..toggleEquipment('Haltères')
      ..toggleEquipment('Banc');
    expect(controller.draft.homeEquipment, ['Haltères', 'Banc']);
    controller.toggleEquipment(ProfileRules.noEquipment);
    expect(controller.draft.homeEquipment, [ProfileRules.noEquipment]);
    controller.toggleEquipment('Banc');
    expect(controller.draft.homeEquipment, ['Banc']);
    controller.toggleLocation(ProfileRules.home);
    expect(controller.draft.homeEquipment, isEmpty);
  });

  test('days are kept in week order and capped by the sessions', () {
    final controller = QuestionnaireController(onSave: (_) async {})
      ..setWeeklySessions(2)
      ..toggleDay('Vendredi')
      ..toggleDay('Lundi')
      ..toggleDay('Mercredi');
    expect(controller.draft.trainingDays, ['Lundi', 'Vendredi']);
  });

  test('submitting twice saves once', () async {
    var saves = 0;
    final controller = controllerAtLastStep(
      onSave: (_) async {
        saves++;
        await Future<void>.delayed(const Duration(milliseconds: 10));
      },
    );
    final first = controller.next();
    final second = controller.next();
    await Future.wait([first, second]);
    expect(saves, 1);
    expect(controller.savedProfile, isNotNull);
  });

  test('save failures are classified and keep the answers', () async {
    final failures = <Object, ProfileSaveFailure>{
      const PostgrestException(message: 'x', code: '42P01'):
          ProfileSaveFailure.unavailable,
      const PostgrestException(message: 'x', code: '23514'):
          ProfileSaveFailure.rejected,
      const PostgrestException(message: 'x', code: 'PGRST301'):
          ProfileSaveFailure.sessionExpired,
      AuthSessionMissingException(): ProfileSaveFailure.sessionExpired,
      AuthRetryableFetchException(message: 'offline'):
          ProfileSaveFailure.network,
      StateError('bug'): ProfileSaveFailure.unknown,
    };
    for (final MapEntry(key: error, value: failure) in failures.entries) {
      final controller = controllerAtLastStep(onSave: (_) async => throw error);
      await controller.next();
      expect(controller.saveFailure, failure, reason: '$error');
      expect(controller.savedProfile, isNull);
      expect(controller.draft.primaryGoal, 'Force');
    }
  });

  test('an invalid earlier answer sends the user back to it', () async {
    var saves = 0;
    final controller = controllerAtLastStep(
      draft: filled.copyWith(age: () => 12),
      onSave: (_) async => saves++,
    );
    await controller.next();
    expect(saves, 0);
    expect(controller.step, QuestionnaireStep.age);
    expect(controller.error, isNotNull);
  });
}
