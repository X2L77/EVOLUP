import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/format/dates.dart';
import '../../app/session/app_session.dart';
import '../../app/session/local_day_clock.dart';
import '../../app/widgets/button_spinner.dart';
import '../../app/widgets/evolup_page.dart';
import '../../app/widgets/glass_card.dart';
import '../../app/widgets/press_scale.dart';
import '../../app/widgets/status_message.dart';
import '../../data/local_date.dart';
import '../../data/metrics/metric_models.dart';
import '../../data/metrics/metric_values.dart';
import '../../theme/evolup_theme.dart';
import '../metrics/metric_texts.dart';
import 'entry_controller.dart';
import 'widgets/value_input.dart';

/// Entry form of one metric: value in its unit, local date (today on the
/// device by default, editable back to one year, never in the future) and
/// « Valider ». The date follows a change of day while the form is open
/// (see `EntryController`), and an identical value already recorded that
/// day is only counted once the user confirms it is a new measure.
///
/// Opened from Mes données, a metric's page, the overview, or Polomix (then
/// with [suggestedValue] pre-filled). Only « Valider » writes to Supabase.
class MetricEntryScreen extends StatefulWidget {
  const MetricEntryScreen({
    required this.definition,
    required this.tracked,
    this.suggestedValue,
    this.fromPolomix = false,
    this.today,
    super.key,
  });

  final MetricDefinition definition;
  final TrackedMetric tracked;

  /// Value proposed by Polomix, in the storage unit; editable.
  final num? suggestedValue;
  final bool fromPolomix;

  /// Overrides the device's date (tests).
  final LocalDate? today;

  @override
  State<MetricEntryScreen> createState() => _MetricEntryScreenState();
}

class _MetricEntryScreenState extends State<MetricEntryScreen> {
  EntryController? _controller;
  final _number = TextEditingController();
  final _durations = <DurationField, TextEditingController>{};
  final _focus = FocusNode();
  Animation<double>? _routeAnimation;
  LocalDayClock? _day;

  EntryController get _entry => _controller!;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller == null) {
      final session = SessionScope.of(context);
      final fixed = widget.today;
      final day = _day = session.day..addListener(_onDayChanged);
      _controller = EntryController(
        definition: widget.definition,
        tracked: widget.tracked,
        metrics: session.metrics,
        timezone: () async =>
            await session.deviceTimezone.current() ??
            session.profile.profile.timezone,
        clock: fixed == null ? () => day.today : () => fixed,
        suggestedValue: widget.suggestedValue,
      )..addListener(_onChanged);
      _number.text = _entry.numberText;
      for (final field in widget.definition.durationFields) {
        _durations[field] = TextEditingController(
          text: _entry.durationTexts[field] ?? '',
        );
      }
      _focusAfterTransition();
    }
  }

  /// The keyboard opens once the page has finished appearing.
  void _focusAfterTransition() {
    if (_entry.isScore) return;
    final animation = ModalRoute.of(context)?.animation;
    if (animation == null || animation.status == AnimationStatus.completed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focus.requestFocus();
      });
      return;
    }
    _routeAnimation = animation..addStatusListener(_onRouteStatus);
  }

  void _onRouteStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    _routeAnimation?.removeStatusListener(_onRouteStatus);
    _routeAnimation = null;
    if (mounted) _focus.requestFocus();
  }

  void _onChanged() => setState(() {});

  /// Midnight, time zone or return to the foreground: the date of the form
  /// is checked again.
  void _onDayChanged() => _entry.refreshDay();

  @override
  void dispose() {
    _day?.removeListener(_onDayChanged);
    _routeAnimation?.removeStatusListener(_onRouteStatus);
    _controller?.dispose();
    _number.dispose();
    for (final c in _durations.values) {
      c.dispose();
    }
    _focus.dispose();
    super.dispose();
  }

  /// From the same calendar day one year ago to today.
  Future<void> _pickDate() async {
    _entry.refreshDay();
    final picked = await showDatePicker(
      context: context,
      initialDate: _entry.date.toDateTime(),
      firstDate: _entry.earliestDate.toDateTime(),
      lastDate: _entry.today.toDateTime(),
      helpText: 'Date de la mesure',
    );
    if (picked != null) _entry.setDate(LocalDate.fromDateTime(picked));
  }

  String _dayChangeMessage(DayChange change) {
    final date = formatLongDate(_entry.date);
    return switch (change) {
      DayChange.followed =>
        'Le jour a changé : la date de la mesure est maintenant aujourd’hui, '
            '$date.',
      DayChange.kept =>
        'Le jour a changé. La date que vous avez choisie est conservée : '
            '$date.',
      DayChange.clampedToToday =>
        'Le jour a changé : la date choisie serait dans le futur, elle est '
            'ramenée à aujourd’hui, $date.',
      DayChange.clampedToEarliest =>
        'Le jour a changé : la date choisie dépasserait un an, elle est '
            'ramenée au $date.',
    };
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    await _entry.submit();
  }

  void _startAnother() {
    _entry.startAnother();
    _number.clear();
    for (final c in _durations.values) {
      c.clear();
    }
    if (!_entry.isScore) _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final colors = EvolupColors.of(context);
    final session = SessionScope.of(context);
    final category = session.metrics.category(widget.definition.categoryId);
    return EvolupPage(
      leading: IconButton(
        key: const Key('entry-close'),
        tooltip: 'Annuler',
        icon: const Icon(Icons.close_rounded),
        onPressed: () => Navigator.of(context).maybePop(_entry.result),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          widget.definition.name,
                          key: const Key('entry-title'),
                          style: Theme.of(context).textTheme.headlineMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.5,
                              ),
                        ),
                        if (category != null) ...[
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Icon(
                                Icons.label_outline_rounded,
                                size: 16,
                                color: colors.accent,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                category.name,
                                key: const Key('entry-category'),
                                style: TextStyle(color: colors.textSecondary),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 20),
                        AnimatedSwitcher(
                          duration: MediaQuery.disableAnimationsOf(context)
                              ? Duration.zero
                              : const Duration(milliseconds: 220),
                          child: _entry.isSaved
                              ? _SavedPanel(
                                  key: const Key('entry-saved'),
                                  controller: _entry,
                                  onDone: () =>
                                      Navigator.of(context).pop(_entry.result),
                                  onAnother: _startAnother,
                                )
                              : _form(context),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (!_entry.isSaved)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: PressScale(
                    child: FilledButton(
                      key: const Key('entry-submit'),
                      // While a duplicate waits for the user's answer, the
                      // two choices below the form replace it.
                      onPressed: _entry.saving || _entry.isDuplicate
                          ? null
                          : _submit,
                      child: _entry.saving
                          ? const ButtonSpinner()
                          : const Text('Valider'),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _form(BuildContext context) {
    final colors = EvolupColors.of(context);
    final definition = widget.definition;
    final textTheme = Theme.of(context).textTheme;
    final hint = boundsHint(definition);
    return Column(
      key: const Key('entry-form'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_entry.suggestedFromCoach) ...[
          const StatusMessage(
            key: Key('entry-suggested'),
            message:
                'Valeur proposée par Polomix à partir de votre message. '
                'Vérifiez-la : rien n’est enregistré avant « Valider ».',
          ),
          const SizedBox(height: 14),
        ] else if (widget.fromPolomix) ...[
          const StatusMessage(
            message:
                'Formulaire ouvert depuis Polomix. Saisissez la valeur, puis '
                'validez.',
          ),
          const SizedBox(height: 14),
        ],
        GlassCard(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                definition.isDuration ? 'Durée' : 'Valeur',
                style: textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              ValueInput(
                definition: definition,
                numberController: _number,
                durationControllers: _durations,
                score: _entry.score,
                focusNode: _focus,
                enabled: !_entry.saving,
                onNumberChanged: _entry.setNumber,
                onDurationChanged: _entry.setDuration,
                onScoreChanged: _entry.setScore,
                onSubmitted: () => unawaited(_submit()),
              ),
              const SizedBox(height: 10),
              if (_entry.fieldError != null)
                Text(
                  _entry.fieldError!,
                  key: const Key('entry-field-error'),
                  style: TextStyle(color: colors.error),
                )
              else if (hint.isNotEmpty)
                Text(
                  hint,
                  style: textTheme.bodySmall?.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        GlassCard(
          padding: const EdgeInsets.fromLTRB(18, 12, 10, 12),
          child: Row(
            children: [
              Icon(Icons.event_rounded, color: colors.accent),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Date de la mesure',
                      style: textTheme.bodySmall?.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                    Text(
                      _entry.date == _entry.today
                          ? 'Aujourd’hui · ${formatLongDate(_entry.date)}'
                          : formatLongDate(_entry.date),
                      key: const Key('entry-date'),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      'Jusqu’à un an en arrière, depuis le '
                      '${formatDate(_entry.earliestDate)}.',
                      key: const Key('entry-date-limit'),
                      style: textTheme.bodySmall?.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(
                key: const Key('entry-date-change'),
                onPressed: _entry.saving ? null : _pickDate,
                child: const Text('Modifier'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Text(
          '${aggregationExplanation(definition)} $duplicateRule',
          style: textTheme.bodySmall?.copyWith(color: colors.textSecondary),
        ),
        if (_entry.dayChange case final change?) ...[
          const SizedBox(height: 14),
          StatusMessage(
            key: const Key('entry-day-changed'),
            message:
                '${_dayChangeMessage(change)} Vérifiez-la, puis validez '
                'de nouveau.',
          ),
        ],
        if (_entry.isDuplicate) ...[
          const SizedBox(height: 14),
          _DuplicateQuestion(
            date: _entry.date,
            saving: _entry.saving,
            onNewMeasure: () => unawaited(_entry.confirmDuplicate()),
            onMistake: _entry.rejectDuplicate,
          ),
        ],
        if (_entry.duplicateRejected) ...[
          const SizedBox(height: 14),
          const StatusMessage(
            key: Key('entry-duplicate-rejected'),
            message:
                'Rien n’a été enregistré : la valeur déjà saisie reste comptée '
                'une seule fois. Corrigez la valeur si besoin.',
          ),
        ],
        if (_entry.submitError != null) ...[
          const SizedBox(height: 14),
          StatusMessage(
            key: const Key('entry-error'),
            message: _entry.submitError!,
            kind: StatusMessageKind.error,
          ),
        ],
      ],
    );
  }
}

/// The same value is already recorded that day: a new measure, or a typing
/// error? Nothing is counted before the answer.
class _DuplicateQuestion extends StatelessWidget {
  const _DuplicateQuestion({
    required this.date,
    required this.saving,
    required this.onNewMeasure,
    required this.onMistake,
  });

  final LocalDate date;
  final bool saving;
  final VoidCallback onNewMeasure;
  final VoidCallback onMistake;

  @override
  Widget build(BuildContext context) => GlassCard(
    key: const Key('entry-duplicate'),
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Cette valeur est déjà enregistrée pour le ${formatDate(date)}. '
          'S’agit-il d’une nouvelle mesure ?',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        Text(
          'Rien n’est compté tant que vous n’avez pas répondu.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: EvolupColors.of(context).textSecondary,
          ),
        ),
        const SizedBox(height: 12),
        FilledButton(
          key: const Key('entry-duplicate-new'),
          onPressed: saving ? null : onNewMeasure,
          child: saving
              ? const ButtonSpinner()
              : const Text('Oui, nouvelle mesure'),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          key: const Key('entry-duplicate-mistake'),
          onPressed: saving ? null : onMistake,
          child: const Text('Non, erreur de saisie'),
        ),
      ],
    ),
  );
}

class _SavedPanel extends StatelessWidget {
  const _SavedPanel({
    required this.controller,
    required this.onDone,
    required this.onAnother,
    super.key,
  });

  final EntryController controller;
  final VoidCallback onDone;
  final VoidCallback onAnother;

  @override
  Widget build(BuildContext context) {
    final colors = EvolupColors.of(context);
    final result = controller.result!;
    final day = result.day;
    final definition = controller.definition;
    final aggregated = day.sampleCount > 1;
    return GlassCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle_rounded, size: 44, color: colors.success),
          const SizedBox(height: 12),
          Text(
            result.status == EntryStatus.alreadyRecorded
                ? 'Saisie déjà enregistrée'
                : 'Valeur enregistrée',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            '${formatDate(day.localDate)} : '
            '${formatValue(definition, day.value, aggregated: aggregated)}'
            '${aggregated ? ' (${definition.aggregation.dailyLabel})' : ''}'
            ' · ${entriesLabel(day.sampleCount)}',
            key: const Key('entry-saved-summary'),
            textAlign: TextAlign.center,
          ),
          if (result.status == EntryStatus.alreadyRecorded) ...[
            const SizedBox(height: 8),
            Text(
              'Cette saisie avait déjà été reçue : elle n’a été comptée '
              'qu’une fois.',
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.textSecondary),
            ),
          ],
          const SizedBox(height: 20),
          FilledButton(
            key: const Key('entry-done'),
            onPressed: onDone,
            child: const Text('Terminé'),
          ),
          const SizedBox(height: 8),
          TextButton(
            key: const Key('entry-another'),
            onPressed: onAnother,
            child: const Text('Nouvelle saisie'),
          ),
        ],
      ),
    );
  }
}
