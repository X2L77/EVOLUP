import 'package:flutter/foundation.dart';

import 'profile_rules.dart';

/// Completed initial questionnaire, stored in `public.athlete_profiles`.
///
/// A row only exists once the questionnaire has been finished, so every
/// required answer is non-nullable here.
@immutable
class AthleteProfile {
  const AthleteProfile({
    required this.age,
    required this.heightCm,
    required this.weightKg,
    required this.weeklySessions,
    required this.trainingDays,
    required this.level,
    required this.primaryGoal,
    required this.trainingLocations,
    required this.sessionDurationMinutes,
    this.goalDetails,
    this.homeEquipment = const [],
  });

  final int age;
  final double heightCm;
  final double weightKg;
  final int weeklySessions;

  /// Exactly [weeklySessions] days. The other days are rest days.
  final List<String> trainingDays;
  final String level;
  final String primaryGoal;
  final String? goalDetails;
  final List<String> trainingLocations;

  /// Empty unless the user trains at home.
  final List<String> homeEquipment;
  final int sessionDurationMinutes;

  bool get trainsAtHome => trainingLocations.contains(ProfileRules.home);

  /// Columns written by the app. `user_id` is added by the repository from
  /// the Supabase session; `created_at`/`updated_at` are set by the database.
  Map<String, dynamic> toMap() => {
    'age': age,
    'height_cm': heightCm,
    'weight_kg': weightKg,
    'weekly_sessions': weeklySessions,
    'training_days': trainingDays,
    'level': level,
    'primary_goal': primaryGoal,
    'goal_details': goalDetails,
    'training_locations': trainingLocations,
    'home_equipment': homeEquipment,
    'session_duration_minutes': sessionDurationMinutes,
  };

  factory AthleteProfile.fromMap(Map<String, dynamic> map) => AthleteProfile(
    age: (map['age'] as num).toInt(),
    heightCm: (map['height_cm'] as num).toDouble(),
    weightKg: (map['weight_kg'] as num).toDouble(),
    weeklySessions: (map['weekly_sessions'] as num).toInt(),
    trainingDays: _stringList(map['training_days']),
    level: map['level'] as String,
    primaryGoal: map['primary_goal'] as String,
    goalDetails: map['goal_details'] as String?,
    trainingLocations: _stringList(map['training_locations']),
    homeEquipment: _stringList(map['home_equipment']),
    sessionDurationMinutes: (map['session_duration_minutes'] as num).toInt(),
  );

  static List<String> _stringList(Object? value) =>
      value is List ? value.whereType<String>().toList() : const [];
}
