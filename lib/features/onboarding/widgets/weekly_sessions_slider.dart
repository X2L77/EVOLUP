import 'package:flutter/material.dart';

import '../../../data/profile_rules.dart';
import '../../../theme/evolup_theme.dart';

/// Vertical slider for the number of sessions per week, with tappable
/// values beside it. No value is preselected.
class WeeklySessionsSlider extends StatelessWidget {
  const WeeklySessionsSlider({
    required this.value,
    required this.onChanged,
    super.key,
  });

  final int? value;
  final ValueChanged<int> onChanged;

  static const _min = ProfileRules.minWeeklySessions;
  static const _max = ProfileRules.maxWeeklySessions;
  static const _height = 260.0;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final current = value;
    return SizedBox(
      height: _height,
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  current?.toString() ?? '–',
                  key: const Key('sessions-value'),
                  style: textTheme.displayMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: current == null
                        ? EvolupColors.textSecondary
                        : EvolupColors.textPrimary,
                  ),
                ),
                Text(
                  current == null
                      ? 'Faites glisser le curseur'
                      : 'séances par semaine',
                  textAlign: TextAlign.center,
                  style: textTheme.bodyMedium?.copyWith(
                    color: EvolupColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Semantics(
            label: 'Séances par semaine',
            child: RotatedBox(
              quarterTurns: 3,
              child: SizedBox(
                width: _height,
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 6,
                    activeTrackColor: EvolupColors.focus,
                    inactiveTrackColor: EvolupColors.fieldBorder,
                    thumbColor: current == null
                        ? EvolupColors.textSecondary
                        : EvolupColors.primaryButton,
                    overlayColor: EvolupColors.focus.withValues(alpha: 0.12),
                    showValueIndicator: ShowValueIndicator.never,
                  ),
                  child: Slider(
                    key: const Key('sessions-slider'),
                    min: _min.toDouble(),
                    max: _max.toDouble(),
                    divisions: _max - _min,
                    value: (current ?? _min).toDouble(),
                    semanticFormatterCallback: (value) =>
                        '${value.round()} séances',
                    onChangeStart: (value) => onChanged(value.round()),
                    onChanged: (value) => onChanged(value.round()),
                  ),
                ),
              ),
            ),
          ),
          SizedBox(
            width: 36,
            // Inset so each value faces its position on the slider track.
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (var count = _max; count >= _min; count--)
                    InkWell(
                      key: Key('sessions-$count'),
                      onTap: () => onChanged(count),
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        child: Text(
                          '$count',
                          style: textTheme.labelLarge?.copyWith(
                            fontWeight: count == current
                                ? FontWeight.w800
                                : FontWeight.w500,
                            color: count == current
                                ? EvolupColors.textPrimary
                                : EvolupColors.textSecondary,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
