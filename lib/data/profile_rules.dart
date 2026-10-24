/// Validated rules of the initial questionnaire (SPEC_PROJECT.md §2).
///
/// The same values are enforced by the `athlete_profiles` migration; the test
/// `profile_rules_test.dart` checks that both stay identical.
abstract final class ProfileRules {
  static const minAge = 15;
  static const maxAge = 120;
  static const minHeightCm = 80.0;
  static const maxHeightCm = 250.0;
  static const minWeightKg = 25.0;
  static const maxWeightKg = 350.0;

  /// Sessions per week. The user then picks exactly this number of days.
  static const minWeeklySessions = 2;
  static const maxWeeklySessions = 7;

  static const levels = ['Débutant', 'Intermédiaire', 'Avancé'];

  static const primaryGoals = [
    'Force',
    'Développement musculaire',
    'Endurance',
    'Street workout / calisthenics',
    'Condition physique générale',
    'Reprise progressive',
  ];
  static const goalDetailsMaxLength = 200;

  static const home = 'À domicile';
  static const trainingLocations = [home, 'Salle de sport', 'Street workout'];

  /// Only asked when [home] is one of the training locations.
  static const noEquipment = 'Aucun matériel';
  static const homeEquipment = [
    noEquipment,
    'Haltères',
    'Barre et poids',
    'Élastiques',
    'Kettlebell',
    'Banc',
    'Machines',
    'Barre de traction',
    'Autre',
  ];

  static const trainingDays = [
    'Lundi',
    'Mardi',
    'Mercredi',
    'Jeudi',
    'Vendredi',
    'Samedi',
    'Dimanche',
  ];

  static const sessionDurations = [30, 45, 60, 75, 90];
}
