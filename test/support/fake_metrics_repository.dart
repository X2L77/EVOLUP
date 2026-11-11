import 'dart:async';
import 'dart:math' as math;

import 'package:my_training/data/data_request.dart';
import 'package:my_training/data/local_date.dart';
import 'package:my_training/data/metrics/metric_models.dart';
import 'package:my_training/data/metrics/metrics_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'test_catalog.dart';

class _Day {
  _Day(this.timezone);

  final String timezone;
  double sum = 0;
  int count = 0;
  double min = double.infinity;
  double max = double.negativeInfinity;
  double last = 0;
  final fingerprints = <double>{};
  final keys = <String>{};

  void reset(double value) {
    sum = value;
    count = 1;
    min = value;
    max = value;
    last = value;
    fingerprints
      ..clear()
      ..add(value);
  }
}

PostgrestException _error(String message, [String code = '22023']) =>
    PostgrestException(message: message, code: code);

double? _aggregate(
  MetricAggregation aggregation,
  Iterable<_Day> days,
  List<LocalDate> dates,
) {
  final list = days.toList();
  if (list.isEmpty) return null;
  return switch (aggregation) {
    MetricAggregation.average =>
      list.fold<double>(0, (a, d) => a + d.sum) /
          list.fold<int>(0, (a, d) => a + d.count),
    MetricAggregation.sum => list.fold<double>(0, (a, d) => a + d.sum),
    MetricAggregation.max => list.map((d) => d.max).reduce(math.max),
    MetricAggregation.min => list.map((d) => d.min).reduce(math.min),
    MetricAggregation.last =>
      list[dates.indexOf(dates.reduce((a, b) => a.isAfter(b) ? a : b))].last,
  };
}

/// In-memory version of the EVOLUP tables and functions, with the same
/// rules as the database (supabase/tests/db checks the real ones): one row
/// per tracked metric and day, duplicate values and retried keys ignored,
/// catalog bounds, no future date. Entries, the global deletion and the
/// overview go through the same guards (timeouts, error classification) as
/// `SupabaseMetricsRepository`.
class FakeMetricsRepository implements MetricsRepository {
  FakeMetricsRepository({
    this.categories = testCategories,
    this.catalog = testCatalog,
    LocalDate? today,
  }) : today = today ?? LocalDate.today();

  final List<MetricCategory> categories;
  final List<MetricDefinition> catalog;
  final LocalDate today;
  final tracked = <TrackedMetric>[];
  final _days = <String, Map<LocalDate, _Day>>{};
  final requests = <EntryRequest>[];
  int _nextId = 1;

  /// Thrown by the next [recordEntry] (then cleared).
  Object? recordError;

  /// When set, [recordEntry] waits for it.
  Completer<void>? recordGate;
  Object? loadError;

  /// Thrown by [loadOverview] while set.
  Object? overviewError;

  /// When set, [loadOverview] waits for it.
  Completer<void>? overviewGate;
  int overviewLoads = 0;

  int trackCalls = 0;

  /// When set, [track] waits for it.
  Completer<void>? trackGate;

  int deleteTrackedCalls = 0;
  int deleteAllCalls = 0;

  /// Thrown by the next [deleteAllTracked] (then cleared), nothing deleted.
  Object? deleteAllError;

  /// When set, [deleteAllTracked] waits for it.
  Completer<void>? deleteAllGate;

  /// When true, [deleteAllTracked] deletes everything, then its answer is
  /// lost: the client sees [deleteAllError] although the server applied it.
  bool deleteAllAppliedBeforeError = false;

  MetricDefinition _definition(int id) => catalog.firstWhere((d) => d.id == id);

  /// Test setup: tracks [definition] directly.
  TrackedMetric addTracked(
    MetricDefinition definition, {
    bool active = true,
    bool favorite = false,
  }) {
    final t = TrackedMetric(
      id: 'um-${_nextId++}',
      metricCatalogId: definition.id,
      isActive: active,
      isFavorite: favorite,
    );
    tracked.add(t);
    return t;
  }

  /// Test setup: records [value] on [date] (default: today).
  void seed(TrackedMetric metric, num value, {LocalDate? date}) {
    final day = _days
        .putIfAbsent(metric.id, () => {})
        .putIfAbsent(date ?? today, () => _Day('Europe/Paris'));
    final v = value.toDouble();
    day.sum += v;
    day.count += 1;
    day.min = math.min(day.min, v);
    day.max = math.max(day.max, v);
    day.last = v;
    day.fingerprints.add(v);
  }

  int dayCount(String trackedId) => _days[trackedId]?.length ?? 0;

  DailyValue? day(String trackedId, LocalDate date) {
    final d = _days[trackedId]?[date];
    if (d == null) return null;
    final metric = tracked.firstWhere((t) => t.id == trackedId);
    return _value(_definition(metric.metricCatalogId), date, d);
  }

  DailyValue _value(MetricDefinition definition, LocalDate date, _Day d) =>
      DailyValue(
        localDate: date,
        timezoneName: d.timezone,
        sampleCount: d.count,
        value: _aggregate(definition.aggregation, [d], [date])!,
        valueSum: d.sum,
        valueMin: d.min,
        valueMax: d.max,
        valueLast: d.last,
      );

  @override
  Future<List<MetricCategory>> loadCategories() async {
    if (loadError case final error?) throw error;
    return categories;
  }

  @override
  Future<List<MetricDefinition>> loadCatalog() async => catalog;

  /// When set, [loadTracked] answers once it completes, with the state read
  /// when it was called (a read run by the server, delivered late).
  Completer<void>? trackedGate;
  int trackedLoads = 0;

  @override
  Future<List<TrackedMetric>> loadTracked() async {
    trackedLoads++;
    final snapshot = List.of(tracked);
    final gate = trackedGate;
    await gate?.future;
    return snapshot;
  }

  @override
  Future<TrackedMetric> track(int metricCatalogId) async {
    trackCalls++;
    await trackGate?.future;
    if (tracked.any((t) => t.metricCatalogId == metricCatalogId)) {
      throw _error('duplicate key', '23505');
    }
    if (!_definition(metricCatalogId).isActive) {
      throw _error('new row violates row-level security policy', '42501');
    }
    final t = TrackedMetric(
      id: 'um-${_nextId++}',
      metricCatalogId: metricCatalogId,
    );
    tracked.add(t);
    return t;
  }

  @override
  Future<TrackedMetric> updateTracked(
    String trackedMetricId, {
    bool? isActive,
    bool? isFavorite,
  }) async {
    final index = tracked.indexWhere((t) => t.id == trackedMetricId);
    final current = tracked[index];
    if (isActive == true && !_definition(current.metricCatalogId).isActive) {
      throw _error('new row violates row-level security policy', '42501');
    }
    final updated = current.copyWith(
      isActive: isActive,
      isFavorite: isFavorite,
    );
    tracked[index] = updated;
    return updated;
  }

  @override
  Future<void> deleteTracked(String trackedMetricId) async {
    deleteTrackedCalls++;
    tracked.removeWhere((t) => t.id == trackedMetricId);
    _days.remove(trackedMetricId);
  }

  /// Like the single DELETE statement: everything or nothing.
  @override
  Future<int> deleteAllTracked() => guardWrite('deleteAllTracked', () async {
    deleteAllCalls++;
    await deleteAllGate?.future;
    final error = deleteAllError;
    if (error != null && !deleteAllAppliedBeforeError) {
      deleteAllError = null;
      throw error;
    }
    final count = tracked.length;
    tracked.clear();
    _days.clear();
    if (error != null) {
      deleteAllError = null;
      throw error;
    }
    return count;
  });

  @override
  Future<EntryResult> recordEntry(EntryRequest request) =>
      guardWrite('recordEntry', () => _recordEntry(request));

  Future<EntryResult> _recordEntry(EntryRequest request) async {
    requests.add(request);
    await recordGate?.future;
    if (recordError case final error?) {
      recordError = null;
      throw error;
    }
    final metric = tracked
        .where((t) => t.id == request.trackedMetricId)
        .firstOrNull;
    if (metric == null) throw _error('metric_not_tracked');
    if (!metric.isActive) throw _error('metric_not_active');
    final definition = _definition(metric.metricCatalogId);
    if (!definition.isActive) throw _error('metric_retired');
    if (request.unit != definition.storageUnit) throw _error('unit_mismatch');
    final value = request.value.toDouble();
    if ((definition.minValue != null && value < definition.minValue!) ||
        (definition.maxValue != null && value > definition.maxValue!)) {
      throw _error('value_out_of_range');
    }
    if (request.localDate.isAfter(today)) throw _error('date_in_future');
    final days = _days.putIfAbsent(metric.id, () => {});
    final day = days[request.localDate];
    if (day == null) {
      final created = _Day(request.timezone)
        ..reset(value)
        ..keys.add(request.idempotencyKey);
      days[request.localDate] = created;
      return EntryResult(
        status: EntryStatus.recorded,
        day: _value(definition, request.localDate, created),
      );
    }
    if (day.keys.contains(request.idempotencyKey)) {
      return EntryResult(
        status: EntryStatus.alreadyRecorded,
        day: _value(definition, request.localDate, day),
      );
    }
    if (day.fingerprints.contains(value)) {
      return EntryResult(
        status: EntryStatus.duplicate,
        day: _value(definition, request.localDate, day),
      );
    }
    if (definition.dailySumMax != null &&
        day.sum + value > definition.dailySumMax!) {
      throw _error('daily_sum_exceeded');
    }
    day
      ..sum += value
      ..count += 1
      ..min = math.min(day.min, value)
      ..max = math.max(day.max, value)
      ..last = value
      ..fingerprints.add(value)
      ..keys.add(request.idempotencyKey);
    return EntryResult(
      status: EntryStatus.recorded,
      day: _value(definition, request.localDate, day),
    );
  }

  @override
  Future<DailyValue> correctDay(
    String trackedMetricId,
    LocalDate day,
    num storedValue,
    String unit,
  ) async {
    final d = _days[trackedMetricId]?[day];
    if (d == null) throw _error('day_not_found');
    d.reset(storedValue.toDouble());
    return this.day(trackedMetricId, day)!;
  }

  @override
  Future<void> deleteDay(String trackedMetricId, LocalDate day) async {
    if (_days[trackedMetricId]?.remove(day) == null) {
      throw _error('day_not_found');
    }
  }

  @override
  Future<void> deleteHistory(String trackedMetricId) async =>
      _days.remove(trackedMetricId);

  @override
  Future<List<DailyValue>> loadDays(
    String trackedMetricId, {
    int limit = 30,
    int offset = 0,
  }) async {
    final metric = tracked.firstWhere((t) => t.id == trackedMetricId);
    final definition = _definition(metric.metricCatalogId);
    final entries = (_days[trackedMetricId] ?? {}).entries.toList()
      ..sort((a, b) => b.key.compareTo(a.key));
    return [
      for (final e in entries.skip(offset).take(limit))
        _value(definition, e.key, e.value),
    ];
  }

  Iterable<MapEntry<LocalDate, _Day>> _range(
    String id,
    LocalDate from,
    LocalDate to,
  ) => (_days[id] ?? {}).entries.where(
    (e) => !e.key.isBefore(from) && !e.key.isAfter(to),
  );

  MetricDefinition _definitionOf(String trackedId) =>
      _definition(tracked.firstWhere((t) => t.id == trackedId).metricCatalogId);

  PeriodSummary _summary(
    MetricDefinition d,
    Iterable<MapEntry<LocalDate, _Day>> days,
  ) {
    final list = days.toList()..sort((a, b) => a.key.compareTo(b.key));
    final value = _aggregate(
      d.aggregation,
      list.map((e) => e.value),
      list.map((e) => e.key).toList(),
    );
    return PeriodSummary(
      value: value,
      perDayAverage: d.aggregation == MetricAggregation.sum && list.isNotEmpty
          ? value! / list.length
          : null,
      daysCount: list.length,
      sampleCount: list.fold(0, (a, e) => a + e.value.count),
      firstDate: list.firstOrNull?.key,
      lastDate: list.lastOrNull?.key,
    );
  }

  @override
  Future<MetricSeries> loadSeries(
    String trackedMetricId,
    LocalDate from,
    LocalDate to, {
    SeriesBucket? bucket,
  }) async {
    final d = _definitionOf(trackedMetricId);
    final span = to.daysSince(from);
    final used =
        bucket ??
        (span <= 120
            ? SeriesBucket.day
            : (span <= 731 ? SeriesBucket.week : SeriesBucket.month));
    LocalDate start(LocalDate date) => switch (used) {
      SeriesBucket.day => date,
      SeriesBucket.week => date.addDays(1 - date.weekday),
      SeriesBucket.month => LocalDate(date.year, date.month, 1),
    };
    final groups = <LocalDate, List<MapEntry<LocalDate, _Day>>>{};
    for (final e in _range(trackedMetricId, from, to)) {
      groups.putIfAbsent(start(e.key), () => []).add(e);
    }
    final starts = groups.keys.toList()..sort();
    return MetricSeries(
      bucket: used,
      points: [
        for (final s in starts)
          SeriesPoint(
            start: s,
            value: _summary(d, groups[s]!).value!,
            sampleCount: _summary(d, groups[s]!).sampleCount,
            daysCount: groups[s]!.length,
          ),
      ],
    );
  }

  @override
  Future<MetricStatistics> loadStatistics(
    String trackedMetricId,
    LocalDate from,
    LocalDate to,
  ) async {
    final d = _definitionOf(trackedMetricId);
    final all = (_days[trackedMetricId] ?? {}).entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    DatedValue? record;
    if (d.recordDirection != null && all.isNotEmpty) {
      final higher = d.recordDirection == RecordDirection.higher;
      final best = all.reduce((a, b) {
        final va = higher ? a.value.max : a.value.min;
        final vb = higher ? b.value.max : b.value.min;
        return (higher ? vb > va : vb < va) ? b : a;
      });
      record = DatedValue(
        date: best.key,
        value: higher ? best.value.max : best.value.min,
      );
    }
    final latest = all.lastOrNull;
    final inRange = _range(trackedMetricId, from, to).toList();
    MetricTrend? trend;
    if (inRange.length >= 5) {
      final xs = [for (final e in inRange) e.key.daysSince(from).toDouble()];
      final ys = [for (final e in inRange) _value(d, e.key, e.value).value];
      final mx = xs.reduce((a, b) => a + b) / xs.length;
      final my = ys.reduce((a, b) => a + b) / ys.length;
      var num = 0.0;
      var den = 0.0;
      for (var i = 0; i < xs.length; i++) {
        num += (xs[i] - mx) * (ys[i] - my);
        den += (xs[i] - mx) * (xs[i] - mx);
      }
      trend = MetricTrend(slopePerDay: num / den, points: xs.length);
    }
    return MetricStatistics(
      period: _summary(d, inRange),
      allTime: _summary(d, all),
      latest: latest == null
          ? null
          : DatedValue(
              date: latest.key,
              value: _value(d, latest.key, latest.value).value,
              count: latest.value.count,
            ),
      record: record,
      trend: trend,
    );
  }

  @override
  Future<PeriodComparison> comparePeriods(
    String trackedMetricId, {
    required LocalDate referenceFrom,
    required LocalDate referenceTo,
    required LocalDate comparedFrom,
    required LocalDate comparedTo,
  }) async {
    final d = _definitionOf(trackedMetricId);
    final a = _summary(d, _range(trackedMetricId, referenceFrom, referenceTo));
    final b = _summary(d, _range(trackedMetricId, comparedFrom, comparedTo));
    final comparable = a.daysCount >= 3 && b.daysCount >= 3;
    return PeriodComparison(
      reference: a,
      compared: b,
      comparable: comparable,
      minDays: 3,
      difference: comparable ? b.value! - a.value! : null,
      percentChange: comparable && a.value != 0
          ? (b.value! - a.value!) / a.value!.abs() * 100
          : null,
    );
  }

  @override
  Future<Overview> loadOverview() => guardRead('loadOverview', _loadOverview);

  /// The overview is computed when called and delivered once
  /// [overviewGate] completes (a late answer carries an older state).
  Future<Overview> _loadOverview() async {
    overviewLoads++;
    final gate = overviewGate;
    final overview = await _computeOverview();
    await gate?.future;
    return overview;
  }

  Future<Overview> _computeOverview() async {
    if (loadError case final error?) throw error;
    if (overviewError case final error?) throw error;
    final metrics = <OverviewMetric>[];
    var entries = 0;
    final dates = <LocalDate>{};
    for (final t in tracked) {
      final d = _definition(t.metricCatalogId);
      final all = (_days[t.id] ?? {}).entries.toList()
        ..sort((a, b) => a.key.compareTo(b.key));
      entries += all.fold(0, (a, e) => a + e.value.count);
      dates.addAll(all.map((e) => e.key));
      final recent = _summary(d, _range(t.id, today.addDays(-29), today));
      final previous = _summary(
        d,
        _range(t.id, today.addDays(-59), today.addDays(-30)),
      );
      final latest = all.lastOrNull;
      metrics.add(
        OverviewMetric(
          trackedMetricId: t.id,
          metricCatalogId: t.metricCatalogId,
          isActive: t.isActive,
          isFavorite: t.isFavorite,
          daysCount: all.length,
          firstDate: all.firstOrNull?.key,
          latest: latest == null
              ? null
              : DatedValue(
                  date: latest.key,
                  value: _value(d, latest.key, latest.value).value,
                  count: latest.value.count,
                ),
          recent: recent,
          previous: previous,
          comparable: recent.daysCount >= 3 && previous.daysCount >= 3,
        ),
      );
    }
    metrics.sort(
      (a, b) => a.isFavorite == b.isFavorite ? 0 : (a.isFavorite ? -1 : 1),
    );
    final sorted = dates.toList()..sort();
    return Overview(
      today: today,
      timezone: 'Europe/Paris',
      daysRecorded: dates.length,
      entriesCount: entries,
      firstDate: sorted.firstOrNull,
      metrics: metrics,
    );
  }

  @override
  Future<List<String>> loadTimezones() async => const [
    'America/Montreal',
    'Asia/Tokyo',
    'Europe/Paris',
    'UTC',
  ];
}
