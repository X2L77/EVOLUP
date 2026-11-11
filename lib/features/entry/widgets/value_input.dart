import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../data/metrics/metric_models.dart';
import '../../../data/metrics/metric_values.dart';
import '../../../theme/evolup_theme.dart';

/// Input adapted to the metric's kind: a whole number, a decimal number in
/// the display unit, hours/minutes/seconds for a duration, or the allowed
/// notes for a score. It only reports what is typed; conversion and checks
/// are done by `metric_values.dart`.
class ValueInput extends StatelessWidget {
  const ValueInput({
    required this.definition,
    required this.numberController,
    required this.durationControllers,
    required this.score,
    required this.onNumberChanged,
    required this.onDurationChanged,
    required this.onScoreChanged,
    this.focusNode,
    this.enabled = true,
    this.onSubmitted,
    super.key,
  });

  final MetricDefinition definition;
  final TextEditingController numberController;
  final Map<DurationField, TextEditingController> durationControllers;
  final int? score;
  final ValueChanged<String> onNumberChanged;
  final void Function(DurationField field, String text) onDurationChanged;
  final ValueChanged<int> onScoreChanged;

  /// Focused when the form opens (first field).
  final FocusNode? focusNode;
  final bool enabled;
  final VoidCallback? onSubmitted;

  static const _durationLabels = {
    DurationField.hours: 'heures',
    DurationField.minutes: 'minutes',
    DurationField.seconds: 'secondes',
  };

  @override
  Widget build(BuildContext context) => switch (definition.valueKind) {
    MetricValueKind.duration => _duration(context),
    MetricValueKind.score => _score(context),
    _ => _number(context),
  };

  Widget _number(BuildContext context) {
    final decimals = inputDecimals(definition);
    return TextField(
      key: const Key('entry-value'),
      controller: numberController,
      focusNode: focusNode,
      enabled: enabled,
      keyboardType: TextInputType.numberWithOptions(decimal: decimals > 0),
      textInputAction: TextInputAction.done,
      inputFormatters: [
        FilteringTextInputFormatter.allow(
          RegExp(decimals > 0 ? r'[0-9.,]' : r'[0-9]'),
        ),
        LengthLimitingTextInputFormatter(12),
      ],
      style: Theme.of(
        context,
      ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
      decoration: InputDecoration(
        hintText: '0',
        suffixIcon: Padding(
          padding: const EdgeInsets.only(right: 16),
          child: Text(
            definition.unitLabel,
            style: TextStyle(
              color: EvolupColors.of(context).textSecondary,
              fontSize: 16,
            ),
          ),
        ),
        suffixIconConstraints: const BoxConstraints(),
      ),
      onChanged: onNumberChanged,
      onSubmitted: (_) => onSubmitted?.call(),
    );
  }

  Widget _duration(BuildContext context) {
    final fields = definition.durationFields;
    return Row(
      children: [
        for (var i = 0; i < fields.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(
            child: TextField(
              key: Key('entry-duration-${fields[i].name}'),
              controller: durationControllers[fields[i]],
              focusNode: i == 0 ? focusNode : null,
              enabled: enabled,
              keyboardType: TextInputType.number,
              textInputAction: i == fields.length - 1
                  ? TextInputAction.done
                  : TextInputAction.next,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(4),
              ],
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
              decoration: InputDecoration(
                hintText: '0',
                labelText: _durationLabels[fields[i]],
                floatingLabelBehavior: FloatingLabelBehavior.always,
              ),
              onChanged: (text) => onDurationChanged(fields[i], text),
              onSubmitted: i == fields.length - 1
                  ? (_) => onSubmitted?.call()
                  : null,
            ),
          ),
        ],
      ],
    );
  }

  Widget _score(BuildContext context) {
    final colors = EvolupColors.of(context);
    final min = (definition.minValue ?? 1).round();
    final max = (definition.maxValue ?? 10).round();
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (var value = min; value <= max; value++)
          Semantics(
            label: '$value${definition.unitLabel}',
            selected: score == value,
            button: true,
            child: ChoiceChip(
              key: Key('entry-score-$value'),
              label: Text(
                '$value',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: score == value
                      ? colors.textPrimary
                      : colors.textSecondary,
                ),
              ),
              showCheckmark: false,
              selected: score == value,
              onSelected: enabled ? (_) => onScoreChanged(value) : null,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            ),
          ),
      ],
    );
  }
}
