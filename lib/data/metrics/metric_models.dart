import 'package:flutter/foundation.dart';

import '../local_date.dart';

/// Kind of value, which decides the input widget and the validation.
enum MetricValueKind {
  integer,
  decimal,
  duration,
  score;

  static MetricValueKind parse(Object? value) =>
      values.firstWhere((k) => k.name == value, orElse: () => decimal);
}

/// How the entries of one local day are combined (catalog `aggregation`).
enum MetricAggregation {
  average('Moyenne', 'moyenne du jour'),
  sum('Total', 'total du jour'),
  max('Maximum', 'maximum du jour'),
  min('Minimum', 'minimum du jour'),
  last('Dernière valeur', 'dernière valeur du jour');

  const MetricAggregation(this.label, this.dailyLabel);

  final String label;
  final String dailyLabel;

  static MetricAggregation parse(Object? value) =>
      values.firstWhere((a) => a.name == value, orElse: () => last);
}

enum RecordDirection {
  higher,
  lower;

  static RecordDirection? parse(Object? value) =>
      values.where((d) => d.name == value).firstOrNull;
}

/// Parts of a duration input (catalog `form_config.duration_fields`).
enum DurationField { hours, minutes, seconds }

@immutable
class MetricCategory {
  const MetricCategory({
    required this.id,
    required this.slug,
    required this.name,
    this.description = '',
    this.sortOrder = 0,
  });

  factory MetricCategory.fromMap(Map<String, dynamic> map) => MetricCategory(
    id: (map['id'] as num).toInt(),
    slug: map['slug'] as String,
    name: map['name'] as String,
    description: map['description'] as String? ?? '',
    sortOrder: (map['sort_order'] as num?)?.toInt() ?? 0,
  );

  final int id;
  final String slug;
  final String name;
  final String description;
  final int sortOrder;
}

/// A metric of the EVOLUP catalog. Values are always handled in
/// [storageUnit]; see `metric_values.dart` for display and input.
@immutable
class MetricDefinition {
  const MetricDefinition({
    required this.id,
    required this.slug,
    required this.categoryId,
    required this.name,
    required this.description,
    required this.valueKind,
    required this.storageUnit,
    required this.unitLabel,
    required this.aggregation,
    this.storageScale = 0,
    this.displayFactor = 1,
    this.displayDecimals = 0,
    this.recordDirection,
    this.minValue,
    this.maxValue,
    this.dailySumMax,
    this.durationFields = const [DurationField.hours, DurationField.minutes],
    this.keywords = const [],
    this.isActive = true,
    this.sortOrder = 0,
  });

  factory MetricDefinition.fromMap(Map<String, dynamic> map) {
    final config = map['form_config'];
    final fields = config is Map ? config['duration_fields'] : null;
    final durationFields = fields is List
        ? [
            for (final field in DurationField.values)
              if (fields.contains(field.name)) field,
          ]
        : const <DurationField>[];
    return MetricDefinition(
      id: (map['id'] as num).toInt(),
      slug: map['slug'] as String,
      categoryId: (map['category_id'] as num).toInt(),
      name: map['name'] as String,
      description: map['description'] as String? ?? '',
      valueKind: MetricValueKind.parse(map['value_kind']),
      storageUnit: map['storage_unit'] as String,
      storageScale: (map['storage_scale'] as num?)?.toInt() ?? 0,
      unitLabel: map['unit_label'] as String? ?? '',
      displayFactor: _number(map['display_factor']) ?? 1,
      displayDecimals: (map['display_decimals'] as num?)?.toInt() ?? 0,
      aggregation: MetricAggregation.parse(map['aggregation']),
      recordDirection: RecordDirection.parse(map['record_direction']),
      minValue: _number(map['min_value']),
      maxValue: _number(map['max_value']),
      dailySumMax: _number(map['daily_sum_max']),
      durationFields: durationFields.isEmpty
          ? const [DurationField.hours, DurationField.minutes]
          : durationFields,
      keywords: map['keywords'] is List
          ? (map['keywords'] as List).whereType<String>().toList()
          : const [],
      isActive: map['is_active'] as bool? ?? true,
      sortOrder: (map['sort_order'] as num?)?.toInt() ?? 0,
    );
  }

  final int id;
  final String slug;
  final int categoryId;
  final String name;
  final String description;
  final MetricValueKind valueKind;
  final String storageUnit;
  final int storageScale;
  final String unitLabel;
  final double displayFactor;
  final int displayDecimals;
  final MetricAggregation aggregation;
  final RecordDirection? recordDirection;
  final double? minValue;
  final double? maxValue;
  final double? dailySumMax;
  final List<DurationField> durationFields;
  final List<String> keywords;
  final bool isActive;
  final int sortOrder;

  bool get isDuration => valueKind == MetricValueKind.duration;
  bool get hasRecord => recordDirection != null;
}

/// A catalog metric added to the user's space (`user_metrics`).
@immutable
class TrackedMetric {
  const TrackedMetric({
    required this.id,
    required this.metricCatalogId,
    this.isActive = true,
    this.isFavorite = false,
    this.sortOrder = 0,
  });

  factory TrackedMetric.fromMap(Map<String, dynamic> map) => TrackedMetric(
    id: map['id'] as String,
    metricCatalogId: (map['metric_catalog_id'] as num).toInt(),
    isActive: map['is_active'] as bool? ?? true,
    isFavorite: map['is_favorite'] as bool? ?? false,
    sortOrder: (map['sort_order'] as num?)?.toInt() ?? 0,
  );

  final String id;
  final int metricCatalogId;
  final bool isActive;
  final bool isFavorite;
  final int sortOrder;

  TrackedMetric copyWith({bool? isActive, bool? isFavorite}) => TrackedMetric(
    id: id,
    metricCatalogId: metricCatalogId,
    isActive: isActive ?? this.isActive,
    isFavorite: isFavorite ?? this.isFavorite,
    sortOrder: sortOrder,
  );
}

/// The aggregate of one tracked metric for one local day.
@immutable
class DailyValue {
  const DailyValue({
    required this.localDate,
    required this.sampleCount,
    required this.value,
    required this.valueSum,
    required this.valueMin,
    required this.valueMax,
    required this.valueLast,
    this.timezoneName,
  });

  factory DailyValue.fromMap(Map<String, dynamic> map) => DailyValue(
    localDate: LocalDate.parse(map['local_date'] as String),
    timezoneName: map['timezone_name'] as String?,
    sampleCount: (map['sample_count'] as num).toInt(),
    value: _number(map['daily_value']) ?? 0,
    valueSum: _number(map['value_sum']) ?? 0,
    valueMin: _number(map['value_min']) ?? 0,
    valueMax: _number(map['value_max']) ?? 0,
    valueLast: _number(map['value_last']) ?? 0,
  );

  final LocalDate localDate;
  final String? timezoneName;
  final int sampleCount;

  /// The day's value according to the metric's aggregation.
  final double value;
  final double valueSum;
  final double valueMin;
  final double valueMax;
  final double valueLast;
}

/// One entry submitted by the form, already converted to the storage unit.
@immutable
class EntryRequest {
  const EntryRequest({
    required this.trackedMetricId,
    required this.value,
    required this.unit,
    required this.localDate,
    required this.timezone,
    required this.idempotencyKey,
    this.confirmDuplicate = false,
  });

  final String trackedMetricId;
  final num value;
  final String unit;
  final LocalDate localDate;
  final String timezone;
  final String idempotencyKey;

  /// The user confirmed that a value identical to one already recorded that
  /// day is a new measure: it is counted (otherwise it is a [duplicate]).
  final bool confirmDuplicate;

  /// The same entry (same key), confirmed as a new measure.
  EntryRequest confirmed() => EntryRequest(
    trackedMetricId: trackedMetricId,
    value: value,
    unit: unit,
    localDate: localDate,
    timezone: timezone,
    idempotencyKey: idempotencyKey,
    confirmDuplicate: true,
  );
}

enum EntryStatus {
  /// The value was merged into the day.
  recorded,

  /// The same value is already part of this day and the entry was not
  /// confirmed as a new measure: nothing changed, the app asks the user.
  duplicate,

  /// This exact request had already been merged (retry): nothing changed.
  alreadyRecorded;

  static EntryStatus parse(Object? value) => switch (value) {
    'recorded' => recorded,
    'duplicate' => duplicate,
    'already_recorded' => alreadyRecorded,
    _ => throw FormatException('Unknown entry status', value),
  };
}

@immutable
class EntryResult {
  const EntryResult({required this.status, required this.day});

  factory EntryResult.fromResponse(Object? data) {
    if (data is! Map) throw const FormatException('Invalid entry result');
    final aggregate = data['aggregate'];
    if (aggregate is! Map) throw const FormatException('Missing aggregate');
    return EntryResult(
      status: EntryStatus.parse(data['status']),
      day: DailyValue.fromMap(Map<String, dynamic>.from(aggregate)),
    );
  }

  final EntryStatus status;
  final DailyValue day;
}

enum SeriesBucket {
  day('Jour'),
  week('Semaine'),
  month('Mois');

  const SeriesBucket(this.label);

  final String label;

  static SeriesBucket parse(Object? value) =>
      values.firstWhere((b) => b.name == value, orElse: () => day);
}

/// One point of a chart: a day, an ISO week (starting Monday) or a month.
@immutable
class SeriesPoint {
  const SeriesPoint({
    required this.start,
    required this.value,
    required this.sampleCount,
    required this.daysCount,
    this.valueMin,
    this.valueMax,
  });

  factory SeriesPoint.fromMap(Map<String, dynamic> map) => SeriesPoint(
    start: LocalDate.parse(map['bucket_start'] as String),
    value: _number(map['value']) ?? 0,
    sampleCount: (map['sample_count'] as num?)?.toInt() ?? 0,
    daysCount: (map['days_count'] as num?)?.toInt() ?? 0,
    valueMin: _number(map['value_min']),
    valueMax: _number(map['value_max']),
  );

  final LocalDate start;
  final double value;
  final int sampleCount;
  final int daysCount;
  final double? valueMin;
  final double? valueMax;
}

@immutable
class MetricSeries {
  const MetricSeries({required this.bucket, required this.points});

  /// The rows of `get_metric_history` (none when nothing is recorded in
  /// the period).
  factory MetricSeries.fromRows(Object? data, {SeriesBucket? requested}) {
    final rows = _list(data, 'series');
    final points = [
      for (final row in rows) SeriesPoint.fromMap(_map(row, 'series point')),
    ];
    final bucket = rows.isNotEmpty
        ? SeriesBucket.parse((rows.first as Map)['bucket'])
        : requested ?? SeriesBucket.day;
    return MetricSeries(bucket: bucket, points: points);
  }

  final SeriesBucket bucket;
  final List<SeriesPoint> points;
}

/// Aggregated values over a set of days.
@immutable
class PeriodSummary {
  const PeriodSummary({
    required this.daysCount,
    required this.sampleCount,
    this.value,
    this.perDayAverage,
    this.firstDate,
    this.lastDate,
  });

  /// Always an object in the SQL answers, with zero days when nothing is
  /// recorded: a missing one is an unusable answer, not an empty period.
  factory PeriodSummary.fromMap(Object? data) {
    final map = _map(data, 'period summary');
    return PeriodSummary(
      value: _number(map['value']),
      perDayAverage: _number(map['per_day_average']),
      daysCount: (map['days_count'] as num?)?.toInt() ?? 0,
      sampleCount: (map['sample_count'] as num?)?.toInt() ?? 0,
      firstDate: _date(map['first_date']),
      lastDate: _date(map['last_date']),
    );
  }

  /// `null` when the period has no recorded day.
  final double? value;

  /// Total divided by recorded days, for sum metrics only.
  final double? perDayAverage;
  final int daysCount;
  final int sampleCount;
  final LocalDate? firstDate;
  final LocalDate? lastDate;
}

@immutable
class DatedValue {
  const DatedValue({required this.date, required this.value, this.count});

  static DatedValue? fromMap(Object? data) {
    if (data is! Map) return null;
    final value = _number(data['value']);
    final date = _date(data['local_date']);
    if (value == null || date == null) return null;
    return DatedValue(
      date: date,
      value: value,
      count: (data['sample_count'] as num?)?.toInt(),
    );
  }

  final LocalDate date;
  final double value;
  final int? count;
}

@immutable
class MetricTrend {
  const MetricTrend({required this.slopePerDay, required this.points, this.r2});

  static MetricTrend? fromMap(Object? data) {
    if (data is! Map) return null;
    final slope = _number(data['slope_per_day']);
    if (slope == null) return null;
    return MetricTrend(
      slopePerDay: slope,
      points: (data['points'] as num?)?.toInt() ?? 0,
      r2: _number(data['r2']),
    );
  }

  final double slopePerDay;
  final int points;
  final double? r2;
}

@immutable
class MetricStatistics {
  const MetricStatistics({
    required this.period,
    required this.allTime,
    this.latest,
    this.record,
    this.trend,
  });

  factory MetricStatistics.fromResponse(Object? data) {
    final map = _map(data, 'statistics');
    return MetricStatistics(
      period: PeriodSummary.fromMap(map['period']),
      allTime: PeriodSummary.fromMap(map['all_time']),
      latest: DatedValue.fromMap(map['latest']),
      record: DatedValue.fromMap(map['record']),
      trend: MetricTrend.fromMap(map['trend']),
    );
  }

  final PeriodSummary period;
  final PeriodSummary allTime;
  final DatedValue? latest;

  /// Best single entry ever, for metrics with a record direction.
  final DatedValue? record;

  /// Only computed from 5 recorded days in the period.
  final MetricTrend? trend;
}

@immutable
class PeriodComparison {
  const PeriodComparison({
    required this.reference,
    required this.compared,
    required this.comparable,
    required this.minDays,
    this.difference,
    this.percentChange,
  });

  factory PeriodComparison.fromResponse(Object? data) {
    final map = _map(data, 'comparison');
    return PeriodComparison(
      reference: PeriodSummary.fromMap(map['a']),
      compared: PeriodSummary.fromMap(map['b']),
      comparable: map['comparable'] == true,
      minDays: (map['min_days'] as num?)?.toInt() ?? 3,
      difference: _number(map['difference']),
      percentChange: _number(map['percent_change']),
    );
  }

  final PeriodSummary reference;
  final PeriodSummary compared;

  /// Both periods have at least [minDays] recorded days.
  final bool comparable;
  final int minDays;
  final double? difference;
  final double? percentChange;
}

@immutable
class OverviewMetric {
  const OverviewMetric({
    required this.trackedMetricId,
    required this.metricCatalogId,
    required this.isActive,
    required this.isFavorite,
    required this.daysCount,
    required this.recent,
    required this.previous,
    required this.comparable,
    this.firstDate,
    this.latest,
  });

  factory OverviewMetric.fromMap(Map<String, dynamic> map) => OverviewMetric(
    trackedMetricId: map['user_metric_id'] as String,
    metricCatalogId: (map['metric_catalog_id'] as num).toInt(),
    isActive: map['is_active'] as bool? ?? true,
    isFavorite: map['is_favorite'] as bool? ?? false,
    daysCount: (map['days_count'] as num?)?.toInt() ?? 0,
    firstDate: _date(map['first_date']),
    latest: DatedValue.fromMap(map['latest']),
    recent: PeriodSummary.fromMap(map['recent']),
    previous: PeriodSummary.fromMap(map['previous']),
    comparable: map['comparable'] == true,
  );

  final String trackedMetricId;
  final int metricCatalogId;
  final bool isActive;
  final bool isFavorite;
  final int daysCount;
  final LocalDate? firstDate;
  final DatedValue? latest;

  /// Last 30 days (profile time zone) and the 30 days before.
  final PeriodSummary recent;
  final PeriodSummary previous;
  final bool comparable;
}

@immutable
class Overview {
  const Overview({
    required this.today,
    required this.timezone,
    required this.daysRecorded,
    required this.entriesCount,
    required this.metrics,
    this.firstDate,
  });

  /// The answer of `get_overview`, which always has a day and a list (empty
  /// for a new user). Anything else is an unusable answer, never an empty
  /// overview: "nothing recorded" must only be shown when it is true.
  factory Overview.fromResponse(Object? data) {
    final map = _map(data, 'overview');
    final today = _date(map['today']);
    if (today == null) throw const FormatException('Overview without today');
    return Overview(
      today: today,
      timezone: map['timezone'] as String? ?? 'UTC',
      daysRecorded: (map['days_recorded'] as num?)?.toInt() ?? 0,
      entriesCount: (map['entries_count'] as num?)?.toInt() ?? 0,
      firstDate: _date(map['first_date']),
      metrics: [
        for (final item in _list(map['metrics'], 'overview metrics'))
          OverviewMetric.fromMap(_map(item, 'overview metric')),
      ],
    );
  }

  final LocalDate today;
  final String timezone;
  final int daysRecorded;
  final int entriesCount;
  final LocalDate? firstDate;
  final List<OverviewMetric> metrics;

  OverviewMetric? metricFor(String trackedMetricId) =>
      metrics.where((m) => m.trackedMetricId == trackedMetricId).firstOrNull;
}

double? _number(Object? value) => switch (value) {
  num() => value.toDouble(),
  String() => double.tryParse(value),
  _ => null,
};

LocalDate? _date(Object? value) =>
    value is String && value.isNotEmpty ? LocalDate.parse(value) : null;

/// A JSON object of the answer; anything else makes the answer unusable
/// ([FormatException], reported as `DataFailure.badResponse`).
Map<String, dynamic> _map(Object? value, String what) => switch (value) {
  Map<String, dynamic>() => value,
  Map() => Map<String, dynamic>.from(value),
  _ => throw FormatException('Invalid $what', value),
};

List<Object?> _list(Object? value, String what) => switch (value) {
  List() => value,
  _ => throw FormatException('Invalid $what', value),
};
