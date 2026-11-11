import 'dart:math' as math;

import 'metric_models.dart';

/// Conversion, validation and French formatting of metric values.
///
/// Values travel in the metric's storage unit (whole seconds for durations,
/// meters for distances…); the app only converts at the edges: what the user
/// types, and what is shown.

const _nbsp = ' ';

/// A typed value converted to the storage unit, or the reason it is refused.
class ParsedValue {
  const ParsedValue.valid(num this.stored) : error = null;
  const ParsedValue.invalid(String this.error) : stored = null;

  final num? stored;
  final String? error;

  bool get isValid => stored != null;
}

/// French number: decimal comma, narrow space between thousands, trailing
/// zeros of the decimals removed.
String formatNumber(num value, {int decimals = 0}) {
  final fixed = value.abs().toStringAsFixed(decimals);
  var parts = fixed.split('.');
  var integer = parts[0];
  var fraction = parts.length > 1 ? parts[1] : '';
  fraction = fraction.replaceFirst(RegExp(r'0+$'), '');
  final grouped = StringBuffer();
  for (var i = 0; i < integer.length; i++) {
    if (i > 0 && (integer.length - i) % 3 == 0) grouped.write(' ');
    grouped.write(integer[i]);
  }
  final negative = value < 0 && double.parse(fixed) != 0;
  parts = [grouped.toString(), if (fraction.isNotEmpty) fraction];
  return '${negative ? '−' : ''}${parts.join(',')}';
}

/// Number of decimals allowed when typing a value of [metric].
int inputDecimals(MetricDefinition metric) => switch (metric.valueKind) {
  MetricValueKind.decimal => metric.displayDecimals,
  _ => 0,
};

num _roundTo(double value, int scale) {
  if (scale == 0) return value.round();
  final factor = math.pow(10, scale);
  return (value * factor).round() / factor;
}

/// Reads a number typed for an integer, decimal or score metric.
ParsedValue parseNumberInput(MetricDefinition metric, String text) {
  final cleaned = text
      .trim()
      .replaceAll(RegExp(r'[\s  ]'), '')
      .replaceAll(',', '.');
  if (cleaned.isEmpty) {
    return const ParsedValue.invalid('Saisissez une valeur.');
  }
  if (!RegExp(r'^\d+(\.\d+)?$').hasMatch(cleaned)) {
    return const ParsedValue.invalid('Saisissez un nombre positif valide.');
  }
  final typedDecimals = cleaned.contains('.')
      ? cleaned.split('.')[1].length
      : 0;
  final allowed = inputDecimals(metric);
  if (typedDecimals > allowed) {
    return ParsedValue.invalid(
      allowed == 0
          ? 'Saisissez un nombre entier.'
          : 'Au maximum $allowed décimale${allowed > 1 ? 's' : ''}.',
    );
  }
  final stored = _roundTo(
    double.parse(cleaned) * metric.displayFactor,
    metric.storageScale,
  );
  return validateStored(metric, stored);
}

/// Reads a duration typed in separate fields (empty fields count as 0).
ParsedValue parseDurationInput(
  MetricDefinition metric,
  Map<DurationField, String> texts,
) {
  final values = <DurationField, int>{};
  for (final field in metric.durationFields) {
    final text = (texts[field] ?? '').trim();
    if (text.isEmpty) continue;
    if (!RegExp(r'^\d+$').hasMatch(text)) {
      return const ParsedValue.invalid('Saisissez des nombres entiers.');
    }
    values[field] = int.parse(text);
  }
  if (values.isEmpty) return const ParsedValue.invalid('Saisissez une durée.');
  final fields = metric.durationFields;
  if (fields.contains(DurationField.hours) &&
      (values[DurationField.minutes] ?? 0) >= 60) {
    return const ParsedValue.invalid(
      'Les minutes doivent être inférieures à 60.',
    );
  }
  if (fields.contains(DurationField.minutes) &&
      (values[DurationField.seconds] ?? 0) >= 60) {
    return const ParsedValue.invalid(
      'Les secondes doivent être inférieures à 60.',
    );
  }
  final seconds =
      (values[DurationField.hours] ?? 0) * 3600 +
      (values[DurationField.minutes] ?? 0) * 60 +
      (values[DurationField.seconds] ?? 0);
  return validateStored(metric, seconds);
}

/// Checks a value already in the storage unit against the catalog bounds.
ParsedValue validateStored(MetricDefinition metric, num stored) {
  final min = metric.minValue;
  final max = metric.maxValue;
  if ((min != null && stored < min) || (max != null && stored > max)) {
    final hint = boundsHint(metric);
    return ParsedValue.invalid(
      'Valeur hors limites : ${hint[0].toLowerCase()}${hint.substring(1)}',
    );
  }
  return ParsedValue.valid(stored);
}

/// "Entre 0 et 500 rép." in display units; empty without bounds.
String boundsHint(MetricDefinition metric) {
  final min = metric.minValue;
  final max = metric.maxValue;
  if (min != null && max != null) {
    return 'Entre ${formatValue(metric, min)} et ${formatValue(metric, max)}';
  }
  if (min != null) return 'Au moins ${formatValue(metric, min)}';
  if (max != null) return 'Au plus ${formatValue(metric, max)}';
  return '';
}

/// Splits a stored duration into the metric's input fields.
Map<DurationField, int> splitDuration(
  MetricDefinition metric,
  num storedSeconds,
) {
  var rest = storedSeconds.round();
  final fields = metric.durationFields;
  final result = <DurationField, int>{};
  if (fields.contains(DurationField.hours)) {
    result[DurationField.hours] = rest ~/ 3600;
    rest %= 3600;
  }
  if (fields.contains(DurationField.minutes)) {
    result[DurationField.minutes] = rest ~/ 60;
    rest %= 60;
  }
  if (fields.contains(DurationField.seconds)) {
    result[DurationField.seconds] = rest;
  }
  return result;
}

/// The stored value as typed in a number field (no unit, no grouping).
String inputText(MetricDefinition metric, num stored) {
  final display = stored / metric.displayFactor;
  final decimals = inputDecimals(metric);
  var text = display.toStringAsFixed(decimals);
  if (text.contains('.')) text = text.replaceFirst(RegExp(r'\.?0+$'), '');
  return text.replaceAll('.', ',');
}

/// A value of [metric] in French with its unit. [aggregated] values (an
/// average, for example) get one more decimal than typed values.
String formatValue(
  MetricDefinition metric,
  num stored, {
  bool aggregated = false,
  bool withUnit = true,
}) {
  if (metric.isDuration) return formatDuration(stored, metric.durationFields);
  final decimals = metric.displayDecimals + (aggregated ? 1 : 0);
  final number = formatNumber(
    stored / metric.displayFactor,
    decimals: decimals,
  );
  if (!withUnit || metric.unitLabel.isEmpty) return number;
  return metric.unitLabel.startsWith('/')
      ? '$number${metric.unitLabel}'
      : '$number$_nbsp${metric.unitLabel}';
}

/// A signed difference ("+2 rép.", "−12 min").
String formatDifference(MetricDefinition metric, num delta) {
  final sign = delta > 0 ? '+' : (delta < 0 ? '−' : '');
  return '$sign${formatValue(metric, delta.abs(), aggregated: true)}';
}

/// "7 h 30", "45 min", "25 min 30 s", "1 h 02 min 05 s".
String formatDuration(num seconds, List<DurationField> fields) {
  final showSeconds = fields.contains(DurationField.seconds);
  var total = seconds.round();
  if (!showSeconds) total = (total / 60).round() * 60;
  final hours = total ~/ 3600;
  final minutes = (total % 3600) ~/ 60;
  final secs = total % 60;
  String two(int value) => value.toString().padLeft(2, '0');
  if (showSeconds) {
    if (hours > 0) {
      return '$hours${_nbsp}h ${two(minutes)}${_nbsp}min ${two(secs)}${_nbsp}s';
    }
    if (minutes > 0) {
      return secs > 0
          ? '$minutes${_nbsp}min ${two(secs)}${_nbsp}s'
          : '$minutes${_nbsp}min';
    }
    return '$secs${_nbsp}s';
  }
  if (hours > 0) {
    return minutes > 0 ? '$hours${_nbsp}h ${two(minutes)}' : '$hours${_nbsp}h';
  }
  return '$minutes${_nbsp}min';
}
