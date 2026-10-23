import '../theme/app_theme.dart';

class AthleteProfile {
  const AthleteProfile({
    this.age,
    this.sports = const [],
    this.weeklyFrequency,
    this.level,
    this.primaryGoal,
    this.secondaryGoals = const [],
    this.customGoal,
    this.trainingLocations = const [],
    this.equipment = const [],
    this.availableDays = const [],
    this.sessionDurationMinutes,
    this.limitations,
    this.heightCm,
    this.weightKg,
    this.wearableSource,
    this.palette = EvolupPalette.gold,
    this.isDark = true,
    this.onboardingStep = 0,
    this.onboardingCompleted = false,
  });

  final int? age;
  final List<String> sports;
  final int? weeklyFrequency;
  final String? level;
  final String? primaryGoal;
  final List<String> secondaryGoals;
  final String? customGoal;
  final List<String> trainingLocations;
  final List<String> equipment;
  final List<String> availableDays;
  final int? sessionDurationMinutes;
  final String? limitations;
  final double? heightCm;
  final double? weightKg;
  final String? wearableSource;
  final EvolupPalette palette;
  final bool isDark;
  final int onboardingStep;
  final bool onboardingCompleted;

  bool get isComplete =>
      age != null &&
      sports.isNotEmpty &&
      weeklyFrequency != null &&
      level != null &&
      primaryGoal != null &&
      trainingLocations.isNotEmpty;

  ThemePreferences get themePreferences =>
      ThemePreferences(palette: palette, isDark: isDark);

  AthleteProfile copyWith({int? onboardingStep, bool? onboardingCompleted}) =>
      AthleteProfile(
        age: age,
        sports: sports,
        weeklyFrequency: weeklyFrequency,
        level: level,
        primaryGoal: primaryGoal,
        secondaryGoals: secondaryGoals,
        customGoal: customGoal,
        trainingLocations: trainingLocations,
        equipment: equipment,
        availableDays: availableDays,
        sessionDurationMinutes: sessionDurationMinutes,
        limitations: limitations,
        heightCm: heightCm,
        weightKg: weightKg,
        wearableSource: wearableSource,
        palette: palette,
        isDark: isDark,
        onboardingStep: onboardingStep ?? this.onboardingStep,
        onboardingCompleted: onboardingCompleted ?? this.onboardingCompleted,
      );

  Map<String, dynamic> toMap() => {
    'age': age,
    'sports': sports,
    'weekly_frequency': weeklyFrequency,
    'level': level,
    'primary_goal': primaryGoal,
    'secondary_goals': secondaryGoals,
    'custom_goal': customGoal,
    'training_locations': trainingLocations,
    'equipment': equipment,
    'available_days': availableDays,
    'session_duration_minutes': sessionDurationMinutes,
    'limitations': limitations,
    'height_cm': heightCm,
    'weight_kg': weightKg,
    'wearable_source': wearableSource,
    'preferred_palette': palette.name,
    'is_dark_mode': isDark,
    'onboarding_step': onboardingStep,
    'onboarding_completed': onboardingCompleted,
  };

  factory AthleteProfile.fromMap(Map<String, dynamic> map) => AthleteProfile(
    age: (map['age'] as num?)?.toInt(),
    sports: _stringList(map['sports']),
    weeklyFrequency: (map['weekly_frequency'] as num?)?.toInt(),
    level: map['level'] as String?,
    primaryGoal: map['primary_goal'] as String?,
    secondaryGoals: _stringList(map['secondary_goals']),
    customGoal: map['custom_goal'] as String?,
    trainingLocations: _stringList(map['training_locations']),
    equipment: _stringList(map['equipment']),
    availableDays: _stringList(map['available_days']),
    sessionDurationMinutes: (map['session_duration_minutes'] as num?)?.toInt(),
    limitations: map['limitations'] as String?,
    heightCm: (map['height_cm'] as num?)?.toDouble(),
    weightKg: (map['weight_kg'] as num?)?.toDouble(),
    wearableSource: map['wearable_source'] as String?,
    palette: EvolupPalette.fromName(map['preferred_palette'] as String?),
    isDark: map['is_dark_mode'] as bool? ?? true,
    onboardingStep: (map['onboarding_step'] as num?)?.toInt() ?? 0,
    onboardingCompleted: map['onboarding_completed'] as bool? ?? false,
  );

  static List<String> _stringList(Object? value) =>
      value is List ? value.whereType<String>().toList() : const [];
}
