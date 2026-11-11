import 'package:flutter/foundation.dart';

import '../../app/session/metrics_controller.dart';
import '../../data/data_error.dart';
import '../../data/local_date.dart';
import '../../data/metrics/metric_models.dart';
import '../../data/metrics/metric_values.dart';
import '../../data/uuid.dart';

/// State of the entry form of one metric.
///
/// Nothing is written before [submit], which the user triggers with
/// « Valider »; a value proposed by Polomix only pre-fills the field.
/// The idempotency key changes whenever the value or the date changes, and
/// stays the same when the same entry is retried after an error, so a
/// request that reached the server is never counted twice.
class EntryController extends ChangeNotifier {
  EntryController({
    required this.definition,
    required this.tracked,
    required MetricsController metrics,
    required Future<String> Function() timezone,
    LocalDate? today,
    num? suggestedValue,
  }) : _metrics = metrics,
       _timezone = timezone,
       today = today ?? LocalDate.today(),
       date = today ?? LocalDate.today() {
    final suggested = suggestedValue == null
        ? null
        : validateStored(definition, suggestedValue).stored;
    if (suggested != null) _prefill(suggested);
    suggestedFromCoach = suggested != null;
  }

  final MetricDefinition definition;
  final TrackedMetric tracked;
  final MetricsController _metrics;
  final Future<String> Function() _timezone;

  /// Today on the device's clock: the default date and the latest allowed.
  final LocalDate today;

  LocalDate date;
  String numberText = '';
  final durationTexts = <DurationField, String>{};
  int? score;

  /// The field was pre-filled with a value proposed by Polomix.
  late final bool suggestedFromCoach;

  String? fieldError;
  String? submitError;
  bool saving = false;
  EntryResult? result;
  String _key = newUuid();
  bool _disposed = false;

  bool get isScore => definition.valueKind == MetricValueKind.score;

  /// Last result was a duplicate: shown as information, form kept.
  bool get isDuplicate => result?.status == EntryStatus.duplicate;

  /// The entry is saved (or was already saved by a previous attempt).
  bool get isSaved => result != null && result!.status != EntryStatus.duplicate;

  void _prefill(num stored) {
    if (definition.isDuration) {
      splitDuration(definition, stored).forEach((field, value) {
        durationTexts[field] = value.toString();
      });
    } else if (isScore) {
      score = stored.round();
    } else {
      numberText = inputText(definition, stored);
    }
  }

  ParsedValue get parsed {
    if (definition.isDuration) {
      return parseDurationInput(definition, durationTexts);
    }
    if (isScore) {
      final value = score;
      return value == null
          ? const ParsedValue.invalid('Choisissez une note.')
          : validateStored(definition, value);
    }
    return parseNumberInput(definition, numberText);
  }

  void setNumber(String text) => _changed(() => numberText = text);

  void setDuration(DurationField field, String text) =>
      _changed(() => durationTexts[field] = text);

  void setScore(int value) => _changed(() => score = value);

  void setDate(LocalDate value) {
    if (value.isAfter(today)) return;
    _changed(() => date = value);
  }

  void _changed(VoidCallback apply) {
    if (saving) return;
    apply();
    _key = newUuid();
    fieldError = null;
    submitError = null;
    if (isDuplicate) result = null;
    _notify();
  }

  /// Sends the entry once; ignored while a request is running.
  Future<EntryResult?> submit() async {
    if (saving || isSaved) return null;
    final value = parsed;
    if (!value.isValid) {
      fieldError = value.error;
      _notify();
      return null;
    }
    saving = true;
    fieldError = null;
    submitError = null;
    result = null;
    _notify();
    try {
      final timezone = await _timezone();
      result = await _metrics.record(
        EntryRequest(
          trackedMetricId: tracked.id,
          value: value.stored!,
          unit: definition.storageUnit,
          localDate: date,
          timezone: timezone,
          idempotencyKey: _key,
        ),
      );
      return result;
    } on Object catch (error) {
      submitError = dataErrorMessage(error);
      return null;
    } finally {
      saving = false;
      _notify();
    }
  }

  /// After a saved entry: an empty form for the same metric and date.
  void startAnother() {
    numberText = '';
    durationTexts.clear();
    score = null;
    result = null;
    fieldError = null;
    submitError = null;
    _key = newUuid();
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
