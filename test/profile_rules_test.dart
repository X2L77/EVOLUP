import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_training/data/athlete_profile.dart';
import 'package:my_training/data/profile_rules.dart';

import 'support/fake_profile_repository.dart';

void main() {
  final migration = File(
    'supabase/migrations/20261021000000_create_athlete_profiles.sql',
  ).readAsStringSync();

  test('the migration allows exactly the values offered by the app', () {
    for (final value in [
      ...ProfileRules.levels,
      ...ProfileRules.primaryGoals,
      ...ProfileRules.trainingLocations,
      ...ProfileRules.homeEquipment,
      ...ProfileRules.trainingDays,
    ]) {
      expect(migration, contains("'$value'"), reason: value);
    }
    expect(
      migration,
      contains(
        'session_duration_minutes in '
        '(${ProfileRules.sessionDurations.join(', ')})',
      ),
    );
    expect(
      migration,
      contains('age between ${ProfileRules.minAge} and ${ProfileRules.maxAge}'),
    );
    expect(migration, contains('height_cm between 80 and 250'));
    expect(migration, contains('weight_kg between 25 and 350'));
    expect(
      migration,
      contains(
        'weekly_sessions between ${ProfileRules.minWeeklySessions} and '
        '${ProfileRules.maxWeeklySessions}',
      ),
    );
    expect(migration, contains('cardinality(training_days) = weekly_sessions'));
    for (final day in ProfileRules.trainingDays) {
      expect(
        migration,
        contains("cardinality(array_positions(training_days, '$day')) <= 1"),
        reason: 'duplicate check for $day',
      );
    }
    expect(
      migration,
      contains("when '${ProfileRules.home}' = any (training_locations)"),
    );
    expect(
      migration,
      contains(
        'char_length(goal_details) between 1 and '
        '${ProfileRules.goalDetailsMaxLength}',
      ),
    );
  });

  test('every column written by the app exists in the migration', () {
    for (final column in ['user_id', ...completedProfile.toMap().keys]) {
      expect(migration, contains('\n  $column '), reason: column);
    }
  });

  test('a profile survives a round trip through its database row', () {
    const profile = AthleteProfile(
      age: 42,
      heightCm: 168.5,
      weightKg: 61,
      weeklySessions: 2,
      trainingDays: ['Mardi', 'Samedi'],
      level: 'Avancé',
      primaryGoal: 'Endurance',
      goalDetails: 'Semi-marathon',
      trainingLocations: ['À domicile', 'Street workout'],
      homeEquipment: ['Aucun matériel'],
      sessionDurationMinutes: 75,
    );
    final copy = AthleteProfile.fromMap({
      ...profile.toMap(),
      'user_id': 'user-1',
      'created_at': '2026-10-23T00:00:00Z',
    });
    expect(copy.toMap(), profile.toMap());
  });
}
