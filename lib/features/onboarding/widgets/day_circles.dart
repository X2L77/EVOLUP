import 'package:flutter/material.dart';

import '../../../data/profile_rules.dart';
import '../../../theme/evolup_theme.dart';

/// The seven days of the week as small circles. Exactly [required] days must
/// be selected; once reached, the other days are dimmed.
class DayCircles extends StatelessWidget {
  const DayCircles({
    required this.selected,
    required this.required,
    required this.onToggle,
    super.key,
  });

  final List<String> selected;
  final int required;
  final ValueChanged<String> onToggle;

  static const _gap = 6.0;

  @override
  Widget build(BuildContext context) {
    final duration = MediaQuery.of(context).disableAnimations
        ? Duration.zero
        : const Duration(milliseconds: 160);
    final textTheme = Theme.of(context).textTheme;
    final full = selected.length >= required;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            const days = ProfileRules.trainingDays;
            final size =
                ((constraints.maxWidth - _gap * (days.length - 1)) /
                        days.length)
                    .clamp(30.0, 48.0);
            return Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final day in days)
                  _DayCircle(
                    key: Key('day-$day'),
                    day: day,
                    size: size,
                    selected: selected.contains(day),
                    dimmed: full && !selected.contains(day),
                    duration: duration,
                    onTap: () => onToggle(day),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        Text(
          '${selected.length} / $required jours sélectionnés',
          key: const Key('days-count'),
          textAlign: TextAlign.center,
          style: textTheme.bodyMedium?.copyWith(
            color: EvolupColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _DayCircle extends StatelessWidget {
  const _DayCircle({
    required this.day,
    required this.size,
    required this.selected,
    required this.dimmed,
    required this.duration,
    required this.onTap,
    super.key,
  });

  final String day;
  final double size;
  final bool selected;
  final bool dimmed;
  final Duration duration;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    label: day,
    selected: selected,
    button: true,
    excludeSemantics: true,
    child: GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedOpacity(
        duration: duration,
        opacity: dimmed ? 0.4 : 1,
        child: AnimatedContainer(
          duration: duration,
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: selected
                ? const LinearGradient(
                    begin: Alignment.bottomLeft,
                    end: Alignment.topRight,
                    colors: [
                      EvolupColors.haloBlueViolet,
                      EvolupColors.haloCyan,
                    ],
                  )
                : null,
            color: selected ? null : EvolupColors.fieldFill,
            border: Border.all(
              color: selected ? Colors.transparent : EvolupColors.fieldBorder,
            ),
          ),
          child: Text(
            day.substring(0, 2),
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: size * 0.32,
              color: selected
                  ? EvolupColors.textPrimary
                  : EvolupColors.textSecondary,
            ),
          ),
        ),
      ),
    ),
  );
}
