import 'package:flutter/material.dart';

import '../../../app/format/dates.dart';
import '../../../app/session/app_session.dart';
import '../../../app/widgets/button_spinner.dart';
import '../../../app/widgets/status_message.dart';
import '../../../data/data_error.dart';
import '../../../data/metrics/metric_models.dart';
import '../../../data/metrics/metric_values.dart';
import '../../../theme/evolup_theme.dart';
import '../../entry/widgets/value_input.dart';
import '../metric_texts.dart';

/// Replaces a recorded day by one corrected value. Entries merged into the
/// day are not stored separately, so they cannot be edited one by one: the
/// dialog says so instead of pretending otherwise. Returns `true` once saved.
Future<bool> showCorrectDayDialog(
  BuildContext context, {
  required MetricDefinition definition,
  required TrackedMetric tracked,
  required DailyValue day,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (_) =>
          _CorrectDayDialog(definition: definition, tracked: tracked, day: day),
    ) ==
    true;

class _CorrectDayDialog extends StatefulWidget {
  const _CorrectDayDialog({
    required this.definition,
    required this.tracked,
    required this.day,
  });

  final MetricDefinition definition;
  final TrackedMetric tracked;
  final DailyValue day;

  @override
  State<_CorrectDayDialog> createState() => _CorrectDayDialogState();
}

class _CorrectDayDialogState extends State<_CorrectDayDialog> {
  final _number = TextEditingController();
  final _durations = <DurationField, TextEditingController>{};
  int? _score;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    for (final field in widget.definition.durationFields) {
      _durations[field] = TextEditingController();
    }
  }

  @override
  void dispose() {
    _number.dispose();
    for (final c in _durations.values) {
      c.dispose();
    }
    super.dispose();
  }

  ParsedValue get _parsed => switch (widget.definition.valueKind) {
    MetricValueKind.duration => parseDurationInput(widget.definition, {
      for (final e in _durations.entries) e.key: e.value.text,
    }),
    MetricValueKind.score =>
      _score == null
          ? const ParsedValue.invalid('Choisissez une note.')
          : validateStored(widget.definition, _score!),
    _ => parseNumberInput(widget.definition, _number.text),
  };

  Future<void> _save() async {
    final parsed = _parsed;
    if (!parsed.isValid) {
      setState(() => _error = parsed.error);
      return;
    }
    final metrics = SessionScope.read(context).metrics;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await metrics.correctDay(
        widget.tracked,
        widget.day.localDate,
        parsed.stored!,
      );
      if (mounted) Navigator.of(context).pop(true);
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = dataErrorMessage(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.definition;
    final day = widget.day;
    final colors = EvolupColors.of(context);
    return AlertDialog(
      key: const Key('correct-day-dialog'),
      title: Text('Corriger le ${formatDate(day.localDate)}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Valeur actuelle : '
              '${formatValue(d, day.value, aggregated: day.sampleCount > 1)}'
              ' (${entriesLabel(day.sampleCount)}).',
            ),
            const SizedBox(height: 8),
            Text(
              'Les saisies fusionnées ne sont pas conservées séparément : la '
              'journée sera remplacée par la seule valeur ci-dessous '
              '(1 saisie).',
              style: TextStyle(color: colors.textSecondary),
            ),
            const SizedBox(height: 14),
            ValueInput(
              definition: d,
              numberController: _number,
              durationControllers: _durations,
              score: _score,
              enabled: !_saving,
              onNumberChanged: (_) => setState(() => _error = null),
              onDurationChanged: (_, _) => setState(() => _error = null),
              onScoreChanged: (value) => setState(() {
                _score = value;
                _error = null;
              }),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              StatusMessage(message: _error!, kind: StatusMessageKind.error),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Annuler'),
        ),
        FilledButton(
          key: const Key('correct-day-save'),
          style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
          onPressed: _saving ? null : _save,
          child: _saving ? const ButtonSpinner() : const Text('Remplacer'),
        ),
      ],
    );
  }
}
