import 'package:flutter/material.dart';

import '../../../app/format/dates.dart';
import '../../../app/widgets/glass_card.dart';
import '../../../data/local_date.dart';
import '../../../data/metrics/metric_models.dart';
import '../../../data/metrics/metric_values.dart';
import '../../../theme/evolup_theme.dart';
import '../metric_texts.dart';

/// Card of a metric: name, category, latest recorded value, and optionally
/// the 30-day comparison and a trailing action (quick entry, add…).
class MetricTile extends StatelessWidget {
  const MetricTile({
    required this.definition,
    required this.categoryName,
    this.latest,
    this.today,
    this.comparisonText,
    this.status,
    this.favorite = false,
    this.onTap,
    this.trailing,
    super.key,
  });

  final MetricDefinition definition;
  final String categoryName;
  final DatedValue? latest;
  final LocalDate? today;
  final String? comparisonText;

  /// Short state shown under the name ("Retiré de ma liste"…).
  final String? status;
  final bool favorite;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = EvolupColors.of(context);
    final textTheme = Theme.of(context).textTheme;
    final latest = this.latest;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        padding: EdgeInsets.zero,
        radius: 20,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            if (favorite) ...[
                              Icon(
                                Icons.star_rounded,
                                size: 18,
                                color: colors.accent,
                                semanticLabel: 'Favori',
                              ),
                              const SizedBox(width: 4),
                            ],
                            Flexible(
                              child: Text(
                                definition.name,
                                style: textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          status == null
                              ? categoryName
                              : '$categoryName · $status',
                          style: textTheme.bodySmall?.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                        if (latest != null) ...[
                          const SizedBox(height: 8),
                          Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: formatValue(
                                    definition,
                                    latest.value,
                                    aggregated: (latest.count ?? 1) > 1,
                                  ),
                                  style: textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                TextSpan(
                                  text:
                                      '  ${today == null ? formatDate(latest.date) : formatRelativeDay(latest.date, today!)}'
                                      '${(latest.count ?? 1) > 1 ? ' · ${entriesLabel(latest.count!)}' : ''}',
                                  style: textTheme.bodySmall?.copyWith(
                                    color: colors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        if (comparisonText != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            comparisonText!,
                            style: textTheme.bodySmall?.copyWith(
                              color: colors.textSecondary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  ?trailing,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
