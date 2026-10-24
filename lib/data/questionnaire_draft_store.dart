import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'profile_draft.dart';

/// Questionnaire progress kept on the device so it can resume after the app
/// is closed. Nothing is sent to Supabase before the final step.
class SavedQuestionnaire {
  const SavedQuestionnaire({required this.draft, this.step});

  final ProfileDraft draft;

  /// Name of the step the user was on.
  final String? step;
}

abstract interface class QuestionnaireDraftStore {
  Future<SavedQuestionnaire?> load(String userId);
  Future<void> save(String userId, SavedQuestionnaire questionnaire);
  Future<void> clear(String userId);
}

class SharedPreferencesDraftStore implements QuestionnaireDraftStore {
  SharedPreferencesDraftStore(this._preferences);

  final Future<SharedPreferences> _preferences;

  static String _key(String userId) => 'evolup.questionnaire.$userId';

  @override
  Future<SavedQuestionnaire?> load(String userId) async {
    final raw = (await _preferences).getString(_key(userId));
    if (raw == null) return null;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return SavedQuestionnaire(
        draft: ProfileDraft.fromJson(json['draft'] as Map<String, dynamic>),
        step: json['step'] as String?,
      );
    } on Object {
      // A corrupted draft must not block the questionnaire.
      return null;
    }
  }

  @override
  Future<void> save(String userId, SavedQuestionnaire questionnaire) async {
    await (await _preferences).setString(
      _key(userId),
      jsonEncode({
        'draft': questionnaire.draft.toJson(),
        'step': questionnaire.step,
      }),
    );
  }

  @override
  Future<void> clear(String userId) async {
    await (await _preferences).remove(_key(userId));
  }
}
