import 'package:flutter/foundation.dart';

import '../../data/athlete_profile.dart';
import '../../data/profile_draft.dart';
import '../../data/profile_rules.dart';
import 'questionnaire_messages.dart';
import 'questionnaire_step.dart';

/// State of the one-question-per-screen questionnaire.
///
/// Answers stay in [draft] when moving back and forth. Nothing is sent to
/// Supabase before the last step; [onSave] then stores the whole profile.
class QuestionnaireController extends ChangeNotifier {
  QuestionnaireController({
    required this.onSave,
    ProfileDraft draft = const ProfileDraft(),
    String? initialStep,
    this.onProgress,
  }) : _draft = draft {
    final steps = this.steps;
    final restored = steps.indexWhere((step) => step.name == initialStep);
    _index = restored < 0 ? 0 : restored;
  }

  final Future<void> Function(AthleteProfile profile) onSave;

  /// Called after each answer and move, so progress can be kept on the device.
  final void Function(ProfileDraft draft, QuestionnaireStep step)? onProgress;

  ProfileDraft _draft;
  late int _index;
  int _direction = 1;
  String? _error;
  bool _saving = false;
  ProfileSaveFailure? _saveFailure;
  AthleteProfile? _savedProfile;
  bool _disposed = false;

  ProfileDraft get draft => _draft;
  List<QuestionnaireStep> get steps => QuestionnaireStep.stepsFor(_draft);
  int get index => _index;
  QuestionnaireStep get step => steps[_index];
  bool get isFirst => _index == 0;
  bool get isLast => _index == steps.length - 1;

  /// 1 when moving forward, -1 when going back (for transitions).
  int get direction => _direction;

  /// Validation message shown after an attempt to continue.
  String? get error => _error;
  bool get saving => _saving;
  ProfileSaveFailure? get saveFailure => _saveFailure;

  /// Set once Supabase has accepted the profile.
  AthleteProfile? get savedProfile => _savedProfile;

  void setAge(int? value) => _update(_draft.copyWith(age: () => value));

  void setHeight(double? value) =>
      _update(_draft.copyWith(heightCm: () => value));

  void setWeight(double? value) =>
      _update(_draft.copyWith(weightKg: () => value));

  void setWeeklySessions(int value) =>
      _update(_draft.copyWith(weeklySessions: () => value));

  /// Selects or unselects a day. No more days than sessions can be selected;
  /// extra days (after lowering the number of sessions) can be unselected.
  void toggleDay(String day) {
    final days = [..._draft.trainingDays];
    if (days.contains(day)) {
      days.remove(day);
    } else {
      if (days.length >= (_draft.weeklySessions ?? 0)) return;
      days.add(day);
    }
    _update(
      _draft.copyWith(trainingDays: _ordered(days, ProfileRules.trainingDays)),
    );
  }

  void setLevel(String value) => _update(_draft.copyWith(level: () => value));

  void setPrimaryGoal(String value) =>
      _update(_draft.copyWith(primaryGoal: () => value));

  void setGoalDetails(String value) {
    final trimmed = value.trim();
    _update(
      _draft.copyWith(goalDetails: () => trimmed.isEmpty ? null : trimmed),
    );
  }

  /// Leaving home training drops the equipment answer, which no longer applies.
  void toggleLocation(String location) {
    final locations = [..._draft.trainingLocations];
    locations.contains(location)
        ? locations.remove(location)
        : locations.add(location);
    final atHome = locations.contains(ProfileRules.home);
    _update(
      _draft.copyWith(
        trainingLocations: _ordered(locations, ProfileRules.trainingLocations),
        homeEquipment: atHome ? null : const [],
      ),
    );
  }

  /// « Aucun matériel » excludes every other choice.
  void toggleEquipment(String item) {
    var equipment = [..._draft.homeEquipment];
    if (equipment.contains(item)) {
      equipment.remove(item);
    } else if (item == ProfileRules.noEquipment) {
      equipment = [item];
    } else {
      equipment
        ..remove(ProfileRules.noEquipment)
        ..add(item);
    }
    _update(
      _draft.copyWith(
        homeEquipment: _ordered(equipment, ProfileRules.homeEquipment),
      ),
    );
  }

  void setSessionDuration(int minutes) =>
      _update(_draft.copyWith(sessionDurationMinutes: () => minutes));

  /// Goes to the next step, or saves the profile on the last one.
  Future<void> next() async {
    if (_saving) return;
    final error = step.validate(_draft);
    if (error != null) {
      _error = error;
      _notify();
      return;
    }
    if (isLast) return _submit();
    _direction = 1;
    _index++;
    _error = null;
    onProgress?.call(_draft, step);
    _notify();
  }

  void back() {
    if (_saving || isFirst) return;
    _direction = -1;
    _index--;
    _error = null;
    _saveFailure = null;
    onProgress?.call(_draft, step);
    _notify();
  }

  Future<void> _submit() async {
    final profile = _toProfile();
    if (profile == null) {
      // A previous step became invalid (should not happen): go back to it.
      final firstInvalid = steps.indexWhere(
        (step) => step.validate(_draft) != null,
      );
      _direction = -1;
      _index = firstInvalid < 0 ? 0 : firstInvalid;
      _error = steps[_index].validate(_draft);
      _notify();
      return;
    }
    _saving = true;
    _saveFailure = null;
    _notify();
    try {
      await onSave(profile);
      _savedProfile = profile;
    } on Object catch (error) {
      _saveFailure = classifyProfileSaveError(error);
    } finally {
      _saving = false;
      _notify();
    }
  }

  AthleteProfile? _toProfile() {
    if (steps.any((step) => step.validate(_draft) != null)) return null;
    final draft = _draft;
    return AthleteProfile(
      age: draft.age!,
      heightCm: draft.heightCm!,
      weightKg: draft.weightKg!,
      weeklySessions: draft.weeklySessions!,
      trainingDays: draft.trainingDays,
      level: draft.level!,
      primaryGoal: draft.primaryGoal!,
      goalDetails: draft.goalDetails,
      trainingLocations: draft.trainingLocations,
      homeEquipment: draft.trainingLocations.contains(ProfileRules.home)
          ? draft.homeEquipment
          : const [],
      sessionDurationMinutes: draft.sessionDurationMinutes!,
    );
  }

  void _update(ProfileDraft draft) {
    if (_saving) return;
    _draft = draft;
    _error = null;
    _saveFailure = null;
    onProgress?.call(_draft, step);
    _notify();
  }

  static List<String> _ordered(List<String> selection, List<String> order) => [
    for (final option in order)
      if (selection.contains(option)) option,
  ];

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
