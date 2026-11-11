import 'package:flutter/material.dart';

import '../../../app/widgets/glass_card.dart';
import '../../../coach/coach_repository.dart';
import '../../../data/metrics/metric_models.dart';
import '../../../data/metrics/metric_values.dart';
import '../../../theme/evolup_theme.dart';

/// A form prepared from the user's message. It says clearly that nothing is
/// recorded yet. [definition] is `null` when the proposed metric is not an
/// active catalog metric: no form is offered then.
class CoachActionCard extends StatelessWidget {
  const CoachActionCard({
    required this.action,
    required this.definition,
    required this.onOpen,
    super.key,
  });

  final CoachAction action;
  final MetricDefinition? definition;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = EvolupColors.of(context);
    final textTheme = Theme.of(context).textTheme;
    final definition = this.definition;
    final suggested = definition == null || action.suggestedValue == null
        ? null
        : validateStored(definition, action.suggestedValue!).stored;
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: GlassCard(
            padding: const EdgeInsets.all(16),
            radius: 18,
            child: definition == null
                ? Row(
                    key: const Key('coach-action-invalid'),
                    children: [
                      Icon(Icons.block_rounded, color: colors.textSecondary),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'L’indicateur proposé n’est pas disponible dans le '
                          'catalogue : aucun formulaire n’a été ouvert.',
                        ),
                      ),
                    ],
                  )
                : Column(
                    key: const Key('coach-action'),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.edit_note_rounded, color: colors.accent),
                          const SizedBox(width: 8),
                          Text(
                            'Saisie préparée',
                            style: textTheme.labelLarge?.copyWith(
                              color: colors.accent,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        definition.name,
                        style: textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        suggested == null
                            ? 'Valeur à saisir dans le formulaire.'
                            : 'Valeur proposée : '
                                  '${formatValue(definition, suggested)}',
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Rien n’est enregistré tant que vous n’avez pas validé '
                        'le formulaire.',
                        style: textTheme.bodySmall?.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        key: const Key('coach-action-open'),
                        onPressed: onOpen,
                        icon: const Icon(Icons.open_in_new_rounded),
                        label: const Text('Ouvrir le formulaire'),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
