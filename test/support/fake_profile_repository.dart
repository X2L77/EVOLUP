import 'dart:async';

import 'package:my_training/data/athlete_profile.dart';
import 'package:my_training/data/athlete_profile_repository.dart';
import 'package:my_training/data/questionnaire_draft_store.dart';

/// In-memory profile table. Tests never contact Supabase.
class FakeProfileRepository implements AthleteProfileRepository {
  FakeProfileRepository({this.profile});

  AthleteProfile? profile;
  Object? loadError;
  Object? saveError;
  Completer<void>? saveCompleter;
  final saved = <AthleteProfile>[];
  int loadCalls = 0;
  int saveCalls = 0;

  @override
  Future<AthleteProfile?> loadCurrent() async {
    loadCalls++;
    if (loadError case final error?) throw error;
    return profile;
  }

  @override
  Future<void> saveCurrent(AthleteProfile value) async {
    saveCalls++;
    await saveCompleter?.future;
    if (saveError case final error?) throw error;
    saved.add(value);
    profile = value;
  }
}

class MemoryDraftStore implements QuestionnaireDraftStore {
  final drafts = <String, SavedQuestionnaire>{};

  @override
  Future<SavedQuestionnaire?> load(String userId) async => drafts[userId];

  @override
  Future<void> save(String userId, SavedQuestionnaire questionnaire) async {
    drafts[userId] = questionnaire;
  }

  @override
  Future<void> clear(String userId) async {
    drafts.remove(userId);
  }
}

const completedProfile = AthleteProfile(
  age: 30,
  heightCm: 180,
  weightKg: 75.5,
  weeklySessions: 3,
  trainingDays: ['Lundi', 'Mercredi', 'Vendredi'],
  level: 'Intermédiaire',
  primaryGoal: 'Force',
  trainingLocations: ['Salle de sport'],
  sessionDurationMinutes: 60,
);
