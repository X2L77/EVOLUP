import 'package:flutter/material.dart';

import '../../../theme/evolup_theme.dart';

/// Back button, « Étape x sur n » and an animated progress bar.
class QuestionnaireHeader extends StatelessWidget {
  const QuestionnaireHeader({
    required this.stepNumber,
    required this.stepCount,
    required this.onBack,
    required this.backTooltip,
    required this.onSignOut,
    super.key,
  });

  final int stepNumber;
  final int stepCount;
  final VoidCallback? onBack;
  final String backTooltip;
  final VoidCallback? onSignOut;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final progress = stepNumber / stepCount;
    return Row(
      children: [
        SizedBox.square(
          dimension: 48,
          child: onBack == null
              ? null
              : IconButton(
                  key: const Key('questionnaire-back'),
                  tooltip: backTooltip,
                  onPressed: onBack,
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Étape $stepNumber sur $stepCount',
                key: const Key('questionnaire-progress'),
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: EvolupColors.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: TweenAnimationBuilder<double>(
                  tween: Tween(end: progress),
                  duration: reduceMotion
                      ? Duration.zero
                      : const Duration(milliseconds: 280),
                  curve: Curves.easeOutCubic,
                  builder: (context, value, _) => LinearProgressIndicator(
                    value: value,
                    minHeight: 4,
                    backgroundColor: EvolupColors.fieldFill,
                    color: EvolupColors.focus,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 4),
        SizedBox.square(
          dimension: 48,
          child: onSignOut == null
              ? null
              : IconButton(
                  key: const Key('questionnaire-sign-out'),
                  tooltip: 'Se déconnecter',
                  onPressed: onSignOut,
                  icon: const Icon(Icons.logout_rounded),
                ),
        ),
      ],
    );
  }
}
