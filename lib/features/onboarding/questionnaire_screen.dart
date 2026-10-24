import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/widgets/button_spinner.dart';
import '../../app/widgets/evolup_background.dart';
import '../../app/widgets/glass_card.dart';
import '../../app/widgets/press_scale.dart';
import '../../app/widgets/status_message.dart';
import '../../data/athlete_profile.dart';
import '../../data/profile_draft.dart';
import '../../data/profile_rules.dart';
import '../../data/questionnaire_draft_store.dart';
import '../../theme/evolup_theme.dart';
import 'questionnaire_controller.dart';
import 'questionnaire_messages.dart';
import 'questionnaire_step.dart';
import 'widgets/choice_answer.dart';
import 'widgets/day_circles.dart';
import 'widgets/number_answer.dart';
import 'widgets/questionnaire_header.dart';
import 'widgets/weekly_sessions_slider.dart';

/// Initial questionnaire, one question per screen.
///
/// When [initialProfile] is given, the saved answers are edited instead.
class QuestionnaireScreen extends StatefulWidget {
  const QuestionnaireScreen({
    required this.userId,
    required this.draftStore,
    required this.onSave,
    required this.onFinished,
    required this.onSignOut,
    this.initialProfile,
    this.onCancel,
    super.key,
  });

  final String userId;
  final QuestionnaireDraftStore draftStore;

  /// Saves the profile to Supabase; throws when it was not saved.
  final Future<void> Function(AthleteProfile profile) onSave;

  /// Called from the confirmation screen.
  final ValueChanged<AthleteProfile> onFinished;
  final Future<void> Function() onSignOut;
  final AthleteProfile? initialProfile;
  final VoidCallback? onCancel;

  @override
  State<QuestionnaireScreen> createState() => _QuestionnaireScreenState();
}

class _QuestionnaireScreenState extends State<QuestionnaireScreen> {
  QuestionnaireController? _controller;

  bool get _editing => widget.initialProfile != null;

  @override
  void initState() {
    super.initState();
    final profile = widget.initialProfile;
    if (profile != null) {
      _controller = QuestionnaireController(
        draft: ProfileDraft.fromProfile(profile),
        onSave: widget.onSave,
      );
    } else {
      unawaited(_restoreDraft());
    }
  }

  Future<void> _restoreDraft() async {
    SavedQuestionnaire? saved;
    try {
      saved = await widget.draftStore.load(widget.userId);
    } on Object {
      saved = null;
    }
    if (!mounted) return;
    setState(() {
      _controller = QuestionnaireController(
        draft: saved?.draft ?? const ProfileDraft(),
        initialStep: saved?.step,
        onSave: widget.onSave,
        onProgress: _keepProgress,
      );
    });
  }

  void _keepProgress(ProfileDraft draft, QuestionnaireStep step) {
    unawaited(() async {
      try {
        await widget.draftStore.save(
          widget.userId,
          SavedQuestionnaire(draft: draft, step: step.name),
        );
      } on Object {
        // Losing the local copy only means answering again after a restart.
      }
    }());
  }

  Future<void> _signOut() async {
    try {
      await widget.onSignOut();
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('La déconnexion a échoué. Réessayez.')),
        );
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return EvolupBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: controller == null
              ? const Center(child: CircularProgressIndicator())
              : ListenableBuilder(
                  listenable: controller,
                  builder: (context, _) {
                    final saved = controller.savedProfile;
                    return saved != null
                        ? _SavedView(
                            editing: _editing,
                            onContinue: () => widget.onFinished(saved),
                          )
                        : _QuestionView(
                            controller: controller,
                            editing: _editing,
                            onCancel: widget.onCancel,
                            onSignOut: _editing ? null : _signOut,
                          );
                  },
                ),
        ),
      ),
    );
  }
}

class _QuestionView extends StatelessWidget {
  const _QuestionView({
    required this.controller,
    required this.editing,
    required this.onCancel,
    required this.onSignOut,
  });

  final QuestionnaireController controller;
  final bool editing;
  final VoidCallback? onCancel;
  final VoidCallback? onSignOut;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final step = controller.step;
    final failure = controller.saveFailure;
    final lastLabel = editing ? 'Enregistrer' : 'Créer mon profil';
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              child: QuestionnaireHeader(
                stepNumber: controller.index + 1,
                stepCount: controller.steps.length,
                onBack: controller.saving
                    ? null
                    : controller.isFirst
                    ? onCancel
                    : controller.back,
                backTooltip: controller.isFirst
                    ? 'Annuler'
                    : 'Question précédente',
                onSignOut: controller.saving ? null : onSignOut,
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                child: AnimatedSwitcher(
                  duration: reduceMotion
                      ? Duration.zero
                      : const Duration(milliseconds: 240),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  layoutBuilder: (current, previous) => Stack(
                    alignment: Alignment.topCenter,
                    children: [...previous, ?current],
                  ),
                  transitionBuilder: (child, animation) {
                    final incoming = child.key == ValueKey(step);
                    final dx =
                        0.08 * controller.direction * (incoming ? 1 : -1);
                    return FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween(
                          begin: Offset(dx, 0),
                          end: Offset.zero,
                        ).animate(animation),
                        child: child,
                      ),
                    );
                  },
                  child: KeyedSubtree(
                    key: ValueKey(step),
                    child: _QuestionCard(controller: controller, step: step),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (failure != null) ...[
                    StatusMessage(
                      key: const Key('questionnaire-save-failure'),
                      message: profileSaveFailureMessage(failure),
                      kind: StatusMessageKind.error,
                    ),
                    const SizedBox(height: 12),
                  ],
                  PressScale(
                    child: FilledButton(
                      key: const Key('questionnaire-continue'),
                      onPressed: controller.saving ? null : controller.next,
                      child: controller.saving
                          ? const ButtonSpinner()
                          : Text(controller.isLast ? lastLabel : 'Continuer'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuestionCard extends StatelessWidget {
  const _QuestionCard({required this.controller, required this.step});

  final QuestionnaireController controller;
  final QuestionnaireStep step;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final explanation = step.explanation;
    final error = controller.error;
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            step.question,
            style: textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
            ),
          ),
          if (explanation != null) ...[
            const SizedBox(height: 8),
            Text(
              explanation,
              style: textTheme.bodyMedium?.copyWith(
                color: EvolupColors.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: 22),
          _Answer(controller: controller, step: step),
          if (error != null) ...[
            const SizedBox(height: 16),
            Text(
              error,
              key: const Key('questionnaire-error'),
              style: textTheme.bodyMedium?.copyWith(color: EvolupColors.error),
            ),
          ],
        ],
      ),
    );
  }
}

class _Answer extends StatelessWidget {
  const _Answer({required this.controller, required this.step});

  final QuestionnaireController controller;
  final QuestionnaireStep step;

  @override
  Widget build(BuildContext context) {
    final draft = controller.draft;
    void submit() => unawaited(controller.next());
    switch (step) {
      case QuestionnaireStep.age:
        return NumberAnswer(
          value: draft.age,
          unit: 'ans',
          label: 'Âge',
          onChanged: (value) => controller.setAge(value?.toInt()),
          onSubmitted: submit,
        );
      case QuestionnaireStep.height:
        return NumberAnswer(
          value: draft.heightCm,
          unit: 'cm',
          label: 'Taille',
          decimal: true,
          onChanged: (value) => controller.setHeight(value?.toDouble()),
          onSubmitted: submit,
        );
      case QuestionnaireStep.weight:
        return NumberAnswer(
          value: draft.weightKg,
          unit: 'kg',
          label: 'Poids',
          decimal: true,
          onChanged: (value) => controller.setWeight(value?.toDouble()),
          onSubmitted: submit,
        );
      case QuestionnaireStep.weeklySessions:
        return WeeklySessionsSlider(
          value: draft.weeklySessions,
          onChanged: controller.setWeeklySessions,
        );
      case QuestionnaireStep.trainingDays:
        return DayCircles(
          selected: draft.trainingDays,
          required: draft.weeklySessions ?? 0,
          onToggle: controller.toggleDay,
        );
      case QuestionnaireStep.level:
        return ChoiceAnswer(
          options: ProfileRules.levels,
          selected: {?draft.level},
          onTap: controller.setLevel,
        );
      case QuestionnaireStep.primaryGoal:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ChoiceAnswer(
              options: ProfileRules.primaryGoals,
              selected: {?draft.primaryGoal},
              onTap: controller.setPrimaryGoal,
            ),
            const SizedBox(height: 18),
            TextFormField(
              key: const Key('goal-details'),
              initialValue: draft.goalDetails,
              maxLength: ProfileRules.goalDetailsMaxLength,
              maxLines: 2,
              minLines: 1,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Précisez votre objectif (facultatif)',
              ),
              onChanged: controller.setGoalDetails,
            ),
          ],
        );
      case QuestionnaireStep.trainingLocations:
        return ChoiceAnswer(
          options: ProfileRules.trainingLocations,
          selected: draft.trainingLocations.toSet(),
          multiple: true,
          onTap: controller.toggleLocation,
        );
      case QuestionnaireStep.homeEquipment:
        return ChoiceAnswer(
          options: ProfileRules.homeEquipment,
          selected: draft.homeEquipment.toSet(),
          multiple: true,
          onTap: controller.toggleEquipment,
        );
      case QuestionnaireStep.sessionDuration:
        return ChoiceAnswer(
          options: [
            for (final minutes in ProfileRules.sessionDurations) '$minutes',
          ],
          selected: {
            if (draft.sessionDurationMinutes case final minutes?) '$minutes',
          },
          labelOf: (option) => '$option minutes',
          onTap: (option) => controller.setSessionDuration(int.parse(option)),
        );
    }
  }
}

class _SavedView extends StatelessWidget {
  const _SavedView({required this.editing, required this.onContinue});

  final bool editing;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: GlassCard(
                    child: Column(
                      children: [
                        const Icon(
                          Icons.check_circle_rounded,
                          size: 56,
                          color: EvolupColors.success,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          editing ? 'Profil mis à jour' : 'Profil enregistré',
                          key: const Key('questionnaire-saved'),
                          textAlign: TextAlign.center,
                          style: textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Vos réponses ont bien été enregistrées dans votre '
                          'profil.',
                          textAlign: TextAlign.center,
                          style: textTheme.bodyMedium?.copyWith(
                            color: EvolupColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: SizedBox(
                width: double.infinity,
                child: PressScale(
                  child: FilledButton(
                    key: const Key('questionnaire-finish'),
                    autofocus: true,
                    onPressed: onContinue,
                    child: Text(
                      editing ? 'Retour à l’accueil' : 'Accéder à EVOLUP',
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
