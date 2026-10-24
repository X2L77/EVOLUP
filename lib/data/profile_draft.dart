import 'package:flutter/foundation.dart';

import 'athlete_profile.dart';

/// Answers given so far in the questionnaire. Every field may still be empty.
@immutable
class ProfileDraft {
  const ProfileDraft({
    this.age,
    this.heightCm,
    this.weightKg,
    this.weeklySessions,
    this.trainingDays = const [],
    this.level,
    this.primaryGoal,
    this.goalDetails,
    this.trainingLocations = const [],
    this.homeEquipment = const [],
    this.sessionDurationMinutes,
  });

  factory ProfileDraft.fromProfile(AthleteProfile profile) => ProfileDraft(
    age: profile.age,
    heightCm: profile.heightCm,
    weightKg: profile.weightKg,
    weeklySessions: profile.weeklySessions,
    trainingDays: profile.trainingDays,
    level: profile.level,
    primaryGoal: profile.primaryGoal,
    goalDetails: profile.goalDetails,
    trainingLocations: profile.trainingLocations,
    homeEquipment: profile.homeEquipment,
    sessionDurationMinutes: profile.sessionDurationMinutes,
  );

  final int? age;
  final double? heightCm;
  final double? weightKg;
  final int? weeklySessions;
  final List<String> trainingDays;
  final String? level;
  final String? primaryGoal;
  final String? goalDetails;
  final List<String> trainingLocations;
  final List<String> homeEquipment;
  final int? sessionDurationMinutes;

  ProfileDraft copyWith({
    ValueGetter<int?>? age,
    ValueGetter<double?>? heightCm,
    ValueGetter<double?>? weightKg,
    ValueGetter<int?>? weeklySessions,
    List<String>? trainingDays,
    ValueGetter<String?>? level,
    ValueGetter<String?>? primaryGoal,
    ValueGetter<String?>? goalDetails,
    List<String>? trainingLocations,
    List<String>? homeEquipment,
    ValueGetter<int?>? sessionDurationMinutes,
  }) => ProfileDraft(
    age: age == null ? this.age : age(),
    heightCm: heightCm == null ? this.heightCm : heightCm(),
    weightKg: weightKg == null ? this.weightKg : weightKg(),
    weeklySessions: weeklySessions == null
        ? this.weeklySessions
        : weeklySessions(),
    trainingDays: trainingDays ?? this.trainingDays,
    level: level == null ? this.level : level(),
    primaryGoal: primaryGoal == null ? this.primaryGoal : primaryGoal(),
    goalDetails: goalDetails == null ? this.goalDetails : goalDetails(),
    trainingLocations: trainingLocations ?? this.trainingLocations,
    homeEquipment: homeEquipment ?? this.homeEquipment,
    sessionDurationMinutes: sessionDurationMinutes == null
        ? this.sessionDurationMinutes
        : sessionDurationMinutes(),
  );

  Map<String, dynamic> toJson() => {
    'age': age,
    'heightCm': heightCm,
    'weightKg': weightKg,
    'weeklySessions': weeklySessions,
    'trainingDays': trainingDays,
    'level': level,
    'primaryGoal': primaryGoal,
    'goalDetails': goalDetails,
    'trainingLocations': trainingLocations,
    'homeEquipment': homeEquipment,
    'sessionDurationMinutes': sessionDurationMinutes,
  };

  factory ProfileDraft.fromJson(Map<String, dynamic> json) => ProfileDraft(
    age: (json['age'] as num?)?.toInt(),
    heightCm: (json['heightCm'] as num?)?.toDouble(),
    weightKg: (json['weightKg'] as num?)?.toDouble(),
    weeklySessions: (json['weeklySessions'] as num?)?.toInt(),
    trainingDays: _strings(json['trainingDays']),
    level: json['level'] as String?,
    primaryGoal: json['primaryGoal'] as String?,
    goalDetails: json['goalDetails'] as String?,
    trainingLocations: _strings(json['trainingLocations']),
    homeEquipment: _strings(json['homeEquipment']),
    sessionDurationMinutes: (json['sessionDurationMinutes'] as num?)?.toInt(),
  );

  static List<String> _strings(Object? value) =>
      value is List ? value.whereType<String>().toList() : const [];
}
