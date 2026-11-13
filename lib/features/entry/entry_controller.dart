import 'package:flutter/foundation.dart';

import '../../app/session/metrics_controller.dart';
import '../../data/data_error.dart';
import '../../data/local_date.dart';
import '../../data/metrics/metric_models.dart';
import '../../data/metrics/metric_values.dart';
import '../../data/uuid.dart';

/// What happened to the date of the form when the device's day changed
/// while it was open (midnight, time zone, clock).
enum DayChange {
  /// The date was the default one (today): it follows the new day.
  followed,

  /// A date chosen by the user is kept: it is still allowed.
  kept,

  /// The chosen date became a future day: it is now today.
  clampedToToday,

  /// The chosen date became older than one year: it is now the oldest
  /// allowed day.
  clampedToEarliest,
}

/// State of the entry form of one metric.
///
/// Nothing is written before [submit], which the user triggers with
/// « Valider »; a value proposed by Polomix only pre-fills the field.
/// The idempotency key changes whenever the value or the date changes, and
/// stays the same when the same entry is retried after an error, so a
/// request that reached the server is never counted twice.
///
/// Dates: today on the device ([today], read again by [refreshDay]) by
/// default, never in the future, at most one year back (same calendar day
/// one year earlier; 29 February → 28 February). If the day changes while
/// the form is open, the default date follows it, a chosen date is kept
/// while it is allowed, and [dayChange] says what happened; a submission
/// during which the day changed is not sent and must be validated again.
///
/// A value identical to one already recorded that day comes back as a
/// duplicate: the user tells a new measure ([confirmDuplicate], counted)
/// from a typing error ([rejectDuplicate], nothing recorded).
class EntryController extends ChangeNotifier {
  EntryController({
    required this.definition,
    required this.tracked,
    required MetricsController metrics,
    required Future<String> Function() timezone,
    LocalDate Function()? clock,
    LocalDate? today,
    num? suggestedValue,
  }) : _metrics = metrics,
       _timezone = timezone,
       _clock = clock ?? (today == null ? LocalDate.today : () => today) {
    this.today = _clock();
    date = this.today;
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

  /// The device's day.
  final LocalDate Function() _clock;

  /// Today on the device's clock: the default date and the latest allowed.
  late LocalDate today;

  late LocalDate date;
  String numberText = '';
  final durationTexts = <DurationField, String>{};
  int? score;

  /// The field was pre-filled with a value proposed by Polomix.
  late final bool suggestedFromCoach;

  String? fieldError;
  String? submitError;
  bool saving = false;
  EntryResult? result;

  /// Set when the day changed with the form open; cleared by the next edit.
  DayChange? dayChange;

  /// The user said the identical value was a typing error: nothing was
  /// recorded. Cleared by the next edit.
  bool duplicateRejected = false;

  /// The user picked a date other than today.
  bool _dateChosen = false;

  /// The request answered `duplicate`, resent as is if confirmed.
  EntryRequest? _duplicateRequest;
  String _key = newUuid();
  bool _disposed = false;

  bool get isScore => definition.valueKind == MetricValueKind.score;

  /// Oldest day allowed for a new entry: the same calendar day one year
  /// before [today] (the server checks the same rule).
  LocalDate get earliestDate => today.addMonths(-12);

  /// Last result was a duplicate: the app asks whether it is a new measure.
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

  /// A day between [earliestDate] and [today]; other days are ignored.
  void setDate(LocalDate value) {
    if (value.isAfter(today) || value.isBefore(earliestDate)) return;
    _changed(() {
      date = value;
      // Picking today again is the default date: it follows the next day.
      _dateChosen = value != today;
    });
  }

  void _changed(VoidCallback apply) {
    if (saving) return;
    apply();
    _key = newUuid();
    fieldError = null;
    submitError = null;
    dayChange = null;
    duplicateRejected = false;
    if (isDuplicate) {
      result = null;
      _duplicateRequest = null;
    }
    _notify();
  }

  /// Reads the device's day again (the page calls it when the session's
  /// clock changes; [submit] calls it before sending). Returns whether the
  /// day changed. Ignored while a request runs: it is checked again after.
  bool refreshDay() {
    if (saving || _disposed) return false;
    final now = _clock();
    if (now == today) return false;
    today = now;
    final previous = date;
    if (!_dateChosen) {
      date = now;
      dayChange = DayChange.followed;
    } else if (date.isAfter(now)) {
      date = now;
      _dateChosen = false;
      dayChange = DayChange.clampedToToday;
    } else if (date.isBefore(earliestDate)) {
      date = earliestDate;
      dayChange = DayChange.clampedToEarliest;
    } else {
      dayChange = DayChange.kept;
    }
    if (date != previous) {
      _key = newUuid();
      // A duplicate found on the former date says nothing about this one.
      if (isDuplicate) result = null;
      _duplicateRequest = null;
      duplicateRejected = false;
    }
    _notify();
    return true;
  }

  /// Sends the entry once; ignored while a request is running. If the day
  /// changed since the form was shown, nothing is sent: the form shows the
  /// updated date and must be validated again.
  Future<EntryResult?> submit() async {
    if (saving || isSaved) return null;
    if (refreshDay()) return null;
    final value = parsed;
    if (!value.isValid) {
      fieldError = value.error;
      _notify();
      return null;
    }
    saving = true;
    fieldError = null;
    submitError = null;
    dayChange = null;
    duplicateRejected = false;
    result = null;
    _duplicateRequest = null;
    _notify();
    try {
      final timezone = await _timezone();
      final request = EntryRequest(
        trackedMetricId: tracked.id,
        value: value.stored!,
        unit: definition.storageUnit,
        localDate: date,
        timezone: timezone,
        idempotencyKey: _key,
      );
      result = await _metrics.record(request);
      if (isDuplicate) _duplicateRequest = request;
      return result;
    } on Object catch (error) {
      submitError = dataErrorMessage(error);
      return null;
    } finally {
      saving = false;
      // A change of day noticed while the request ran.
      if (!isSaved) refreshDay();
      _notify();
    }
  }

  /// The identical value is a new measure: the same request (same key, so
  /// a retry is never counted twice) is sent again, confirmed.
  Future<EntryResult?> confirmDuplicate() async {
    final request = _duplicateRequest;
    if (saving || request == null) return null;
    saving = true;
    submitError = null;
    _notify();
    try {
      final confirmed = await _metrics.record(request.confirmed());
      result = confirmed;
      if (!isDuplicate) _duplicateRequest = null;
      return confirmed;
    } on Object catch (error) {
      // Still a duplicate waiting for an answer: the user may try again.
      submitError = dataErrorMessage(error);
      return null;
    } finally {
      saving = false;
      if (!isSaved) refreshDay();
      _notify();
    }
  }

  /// The identical value was a typing error: nothing is recorded, the form
  /// stays open with its value so that it can be corrected.
  void rejectDuplicate() {
    if (saving || !isDuplicate) return;
    result = null;
    _duplicateRequest = null;
    submitError = null;
    duplicateRejected = true;
    _key = newUuid();
    _notify();
  }

  /// After a saved entry: an empty form for the same metric, on the same
  /// date (today's date if it was the default one and the day changed).
  void startAnother() {
    final now = _clock();
    if (now != today) {
      today = now;
      if (!_dateChosen || date.isAfter(now)) {
        date = now;
        _dateChosen = false;
      } else if (date.isBefore(earliestDate)) {
        date = earliestDate;
      }
    }
    numberText = '';
    durationTexts.clear();
    score = null;
    result = null;
    fieldError = null;
    submitError = null;
    dayChange = null;
    duplicateRejected = false;
    _duplicateRequest = null;
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
