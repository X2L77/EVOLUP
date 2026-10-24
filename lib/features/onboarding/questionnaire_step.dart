import '../../data/profile_draft.dart';
import '../../data/profile_rules.dart';

/// Questions of the initial questionnaire, one per screen, in display order.
enum QuestionnaireStep {
  age(
    'Quel âge avez-vous ?',
    'Votre âge adapte l’intensité de votre futur programme.',
  ),
  height('Quelle est votre taille ?', 'En centimètres.'),
  weight('Quel est votre poids ?', 'En kilogrammes.'),
  weeklySessions(
    'Combien de séances par semaine ?',
    'Le nombre de séances que vous souhaitez ou pouvez faire chaque semaine.',
  ),
  trainingDays(
    'Quels jours vous entraînez-vous ?',
    'Vos séances et quêtes auront lieu ces jours-là. Les autres jours sont '
        'des jours de repos.',
  ),
  level('Quel est votre niveau sportif ?', null),
  primaryGoal('Quel est votre objectif principal ?', 'Un seul choix.'),
  trainingLocations('Où vous entraînez-vous ?', 'Plusieurs choix possibles.'),
  homeEquipment(
    'De quel matériel disposez-vous à domicile ?',
    'Plusieurs choix possibles.',
  ),
  sessionDuration('Combien de temps dure une séance ?', null);

  const QuestionnaireStep(this.question, this.explanation);

  final String question;
  final String? explanation;

  /// Steps that apply to [draft]. Equipment is only asked for home training.
  static List<QuestionnaireStep> stepsFor(ProfileDraft draft) => [
    for (final step in values)
      if (step != homeEquipment ||
          draft.trainingLocations.contains(ProfileRules.home))
        step,
  ];

  /// Error message if the answer to this step is missing or invalid.
  String? validate(ProfileDraft draft) {
    switch (this) {
      case age:
        final value = draft.age;
        return value != null &&
                value >= ProfileRules.minAge &&
                value <= ProfileRules.maxAge
            ? null
            : 'Indiquez un âge entre ${ProfileRules.minAge} et '
                  '${ProfileRules.maxAge} ans.';
      case height:
        final value = draft.heightCm;
        return value != null &&
                value >= ProfileRules.minHeightCm &&
                value <= ProfileRules.maxHeightCm
            ? null
            : 'Indiquez une taille entre 80 et 250 cm.';
      case weight:
        final value = draft.weightKg;
        return value != null &&
                value >= ProfileRules.minWeightKg &&
                value <= ProfileRules.maxWeightKg
            ? null
            : 'Indiquez un poids entre 25 et 350 kg.';
      case weeklySessions:
        final value = draft.weeklySessions;
        return value != null &&
                value >= ProfileRules.minWeeklySessions &&
                value <= ProfileRules.maxWeeklySessions
            ? null
            : 'Choisissez le nombre de séances par semaine.';
      case trainingDays:
        final expected = draft.weeklySessions;
        if (expected == null) {
          return 'Choisissez d’abord le nombre de séances par semaine.';
        }
        final selected = draft.trainingDays.length;
        return selected == expected
            ? null
            : 'Sélectionnez exactement $expected jours '
                  '($selected sélectionné${selected > 1 ? 's' : ''}).';
      case level:
        return ProfileRules.levels.contains(draft.level)
            ? null
            : 'Choisissez votre niveau.';
      case primaryGoal:
        if (!ProfileRules.primaryGoals.contains(draft.primaryGoal)) {
          return 'Choisissez votre objectif principal.';
        }
        final details = draft.goalDetails ?? '';
        return details.length <= ProfileRules.goalDetailsMaxLength
            ? null
            : 'La précision est limitée à '
                  '${ProfileRules.goalDetailsMaxLength} caractères.';
      case trainingLocations:
        return draft.trainingLocations.isNotEmpty
            ? null
            : 'Choisissez au moins un lieu d’entraînement.';
      case homeEquipment:
        return draft.homeEquipment.isNotEmpty
            ? null
            : 'Choisissez votre matériel, ou « ${ProfileRules.noEquipment} ».';
      case sessionDuration:
        return ProfileRules.sessionDurations.contains(
              draft.sessionDurationMinutes,
            )
            ? null
            : 'Choisissez la durée d’une séance.';
    }
  }
}
