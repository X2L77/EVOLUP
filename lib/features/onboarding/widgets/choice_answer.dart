import 'package:flutter/material.dart';

import '../../../theme/evolup_theme.dart';

/// List of selectable options. With [multiple], several can be selected.
class ChoiceAnswer extends StatelessWidget {
  const ChoiceAnswer({
    required this.options,
    required this.selected,
    required this.onTap,
    this.multiple = false,
    this.labelOf,
    super.key,
  });

  final List<String> options;
  final Set<String> selected;
  final ValueChanged<String> onTap;
  final bool multiple;
  final String Function(String option)? labelOf;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final option in options) ...[
        _ChoiceTile(
          key: Key('choice-$option'),
          label: labelOf?.call(option) ?? option,
          selected: selected.contains(option),
          multiple: multiple,
          onTap: () => onTap(option),
        ),
        if (option != options.last) const SizedBox(height: 10),
      ],
    ],
  );
}

class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({
    required this.label,
    required this.selected,
    required this.multiple,
    required this.onTap,
    super.key,
  });

  final String label;
  final bool selected;
  final bool multiple;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final duration = MediaQuery.of(context).disableAnimations
        ? Duration.zero
        : const Duration(milliseconds: 160);
    final icon = multiple
        ? (selected ? Icons.check_box_rounded : Icons.check_box_outline_blank)
        : (selected
              ? Icons.radio_button_checked_rounded
              : Icons.radio_button_unchecked_rounded);
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: AnimatedContainer(
            duration: duration,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: selected
                  ? EvolupColors.focus.withValues(alpha: 0.14)
                  : EvolupColors.fieldFill,
              border: Border.all(
                color: selected ? EvolupColors.focus : EvolupColors.fieldBorder,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 22,
                  color: selected
                      ? EvolupColors.focus
                      : EvolupColors.textSecondary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
