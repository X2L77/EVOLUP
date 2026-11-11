import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:my_training/data/data_error.dart';
import 'package:my_training/data/local_date.dart';
import 'package:my_training/data/metrics/metric_models.dart';
import 'package:my_training/data/metrics/metrics_repository.dart';
import 'package:my_training/data/profile/user_profile.dart';
import 'package:my_training/theme/evolup_theme.dart';

import 'support/supabase_test_server.dart';

/// T10: the models read the JSON that Supabase really sends, as written by
/// the migrations (tables through PostgREST, `jsonb` of the SQL functions).
/// Every sample below is JSON text, decoded like an HTTP answer: numbers
/// come as int or double, dates as text, absent values as null.
Object? _decode(String json) => jsonDecode(json);

Map<String, dynamic> _object(String json) =>
    _decode(json)! as Map<String, dynamic>;

/// A row of `metric_daily_aggregates` as `private.aggregate_json` builds it;
/// `numeric` keeps its scale (`8.3333333333333333`).
const _aggregate = '''
{
  "user_metric_id": "6f1c1d4e-0b8a-4c43-9a55-1e1f2c3d4e5f",
  "local_date": "2026-11-02",
  "timezone_name": "Europe/Paris",
  "sample_count": 3,
  "value_sum": 25,
  "value_min": 8,
  "value_max": 9,
  "value_last": 8,
  "daily_value": 8.3333333333333333
}''';

/// `get_overview` for a user with one metric recorded and one just added.
const _overview = '''
{
  "today": "2026-11-11",
  "timezone": "Europe/Paris",
  "min_days": 3,
  "days_recorded": 4,
  "entries_count": 7,
  "first_date": "2026-10-01",
  "metrics": [
    {
      "user_metric_id": "6f1c1d4e-0b8a-4c43-9a55-1e1f2c3d4e5f",
      "metric_catalog_id": 1,
      "is_active": true,
      "is_favorite": true,
      "days_count": 4,
      "first_date": "2026-10-01",
      "latest": {"local_date": "2026-11-10", "value": 9.5, "sample_count": 2},
      "recent": {"from": "2026-10-13", "to": "2026-11-11", "value": 9.25,
                 "days_count": 3},
      "previous": {"from": "2026-09-13", "to": "2026-10-12", "value": 8,
                   "days_count": 1},
      "comparable": false
    },
    {
      "user_metric_id": "0a6b9c55-6c43-4e8e-b8f6-3c0e5a1d2b7f",
      "metric_catalog_id": 11,
      "is_active": false,
      "is_favorite": false,
      "days_count": 0,
      "first_date": null,
      "latest": null,
      "recent": {"from": "2026-10-13", "to": "2026-11-11", "value": null,
                 "days_count": 0},
      "previous": {"from": "2026-09-13", "to": "2026-10-12", "value": null,
                   "days_count": 0},
      "comparable": false
    }
  ]
}''';

/// `get_metric_statistics` of an average metric with a record direction.
const _statistics = '''
{
  "aggregation": "average",
  "record_direction": "higher",
  "period": {"from": "2026-10-13", "to": "2026-11-11", "value": 8.6,
             "per_day_average": null, "days_count": 5, "sample_count": 5,
             "first_date": "2026-10-20", "last_date": "2026-11-10",
             "value_min": 7, "value_max": 10},
  "all_time": {"value": 8.5, "days_count": 6, "sample_count": 6,
               "first_date": "2026-10-01", "last_date": "2026-11-10"},
  "latest": {"local_date": "2026-11-10", "value": 10, "sample_count": 1},
  "record": {"value": 10, "local_date": "2026-11-10"},
  "trend": {"slope_per_day": 0.0712, "r2": 0.41, "points": 5}
}''';

/// `get_metric_statistics` over a period without any recorded day.
const _emptyStatistics = '''
{
  "aggregation": "sum",
  "record_direction": null,
  "period": {"from": "2026-11-05", "to": "2026-11-11", "value": null,
             "per_day_average": null, "days_count": 0, "sample_count": 0,
             "first_date": null, "last_date": null, "value_min": null,
             "value_max": null},
  "all_time": {"value": 3600, "days_count": 2, "sample_count": 3,
               "first_date": "2026-09-01", "last_date": "2026-09-02"},
  "latest": {"local_date": "2026-09-02", "value": 1800, "sample_count": 2},
  "record": null,
  "trend": null
}''';

const _comparison = '''
{
  "aggregation": "sum",
  "a": {"from": "2026-10-06", "to": "2026-10-12", "value": 12000,
        "days_count": 4, "sample_count": 5},
  "b": {"from": "2026-10-13", "to": "2026-10-19", "value": 15000,
        "days_count": 3, "sample_count": 3},
  "min_days": 3,
  "comparable": true,
  "difference": 3000,
  "percent_change": 25.0000000000000000
}''';

/// Rows of `get_metric_history` (a `returns table` function).
const _history = '''
[
  {"bucket": "week", "bucket_start": "2026-10-26", "value": 12.5,
   "sample_count": 4, "days_count": 3, "value_min": 10, "value_max": 15,
   "first_date": "2026-10-27", "last_date": "2026-10-30"},
  {"bucket": "week", "bucket_start": "2026-11-02", "value": 9,
   "sample_count": 1, "days_count": 1, "value_min": 9, "value_max": 9,
   "first_date": "2026-11-04", "last_date": "2026-11-04"}
]''';

/// A `metric_catalog` row (seed 20261109100200, « Course — temps sur 5 km »).
const _course5km = '''
{
  "id": 4, "slug": "course_5km", "category_id": 1,
  "name": "Course — temps sur 5 km",
  "description": "Temps réalisé sur 5 km.",
  "value_kind": "duration", "storage_unit": "second", "storage_scale": 0,
  "unit_label": "temps", "display_factor": 1, "display_decimals": 0,
  "aggregation": "min", "record_direction": "lower",
  "min_value": 600, "max_value": 10800, "daily_sum_max": null,
  "form_config": {"duration_fields": ["minutes", "seconds"]},
  "keywords": ["5 km", "5km", "5 kilometres", "cinq kilometres"],
  "is_active": true, "sort_order": 40
}''';

/// « Course — distance »: decimals, display factor and daily maximum.
const _courseDistance = '''
{
  "id": 3, "slug": "course_distance", "category_id": 1,
  "name": "Course — distance", "description": "Distance parcourue.",
  "value_kind": "decimal", "storage_unit": "meter", "storage_scale": 0,
  "unit_label": "km", "display_factor": 1000, "display_decimals": 2,
  "aggregation": "sum", "record_direction": "higher",
  "min_value": 10, "max_value": 300000, "daily_sum_max": 500000,
  "form_config": {}, "keywords": ["course", "running"],
  "is_active": false, "sort_order": 30
}''';

Matcher _fails(DataFailure failure) =>
    isA<DataException>().having((e) => e.failure, 'failure', failure);

void main() {
  group('catalog and tracked metrics (tables)', () {
    test('a category', () {
      final category = MetricCategory.fromMap(
        _object(
          '{"id": 4, "slug": "sommeil", "name": "Sommeil", '
          '"description": "Durée et qualité du sommeil.", "sort_order": 40}',
        ),
      );
      expect(category.id, 4);
      expect(category.slug, 'sommeil');
      expect(category.sortOrder, 40);
      // Optional columns (not selected, or absent).
      final bare = MetricCategory.fromMap(
        _object('{"id": 1, "slug": "sport", "name": "Sport"}'),
      );
      expect(bare.description, '');
      expect(bare.sortOrder, 0);
    });

    test('a duration metric with its form options', () {
      final d = MetricDefinition.fromMap(_object(_course5km));
      expect(d.id, 4);
      expect(d.categoryId, 1);
      expect(d.valueKind, MetricValueKind.duration);
      expect(d.isDuration, isTrue);
      expect(d.aggregation, MetricAggregation.min);
      expect(d.recordDirection, RecordDirection.lower);
      expect(d.minValue, 600);
      expect(d.maxValue, 10800);
      expect(d.dailySumMax, isNull);
      expect(d.durationFields, [DurationField.minutes, DurationField.seconds]);
      expect(d.keywords, contains('cinq kilometres'));
      expect(d.sortOrder, 40);
    });

    test('a decimal metric: numeric columns as int or double', () {
      final d = MetricDefinition.fromMap(_object(_courseDistance));
      expect(d.displayFactor, 1000.0);
      expect(d.displayDecimals, 2);
      expect(d.dailySumMax, 500000.0);
      expect(d.isActive, isFalse, reason: 'retired metric');
      // No duration_fields: hours and minutes.
      expect(d.durationFields, [DurationField.hours, DurationField.minutes]);
      final decimal = MetricDefinition.fromMap({
        ..._object(_courseDistance),
        'display_factor': 0.5,
        'min_value': '10.25', // A numeric sent as text is still read.
      });
      expect(decimal.displayFactor, 0.5);
      expect(decimal.minValue, 10.25);
    });

    test('unexpected values fall back to safe defaults', () {
      final d = MetricDefinition.fromMap({
        ..._object(_courseDistance),
        'value_kind': 'percentage',
        'aggregation': 'median',
        'record_direction': 'sideways',
        'form_config': {'duration_fields': 'minutes', 'unknown': true},
        'keywords': ['course', 3, null],
      });
      expect(d.valueKind, MetricValueKind.decimal);
      expect(d.aggregation, MetricAggregation.last);
      expect(d.recordDirection, isNull);
      expect(d.durationFields, [DurationField.hours, DurationField.minutes]);
      expect(d.keywords, ['course']);
    });

    test('a missing or mistyped required field is an error', () {
      final row = _object(_course5km);
      expect(
        () => MetricDefinition.fromMap({...row}..remove('slug')),
        throwsA(isA<TypeError>()),
      );
      expect(
        () => MetricDefinition.fromMap({...row, 'id': '4'}),
        throwsA(isA<TypeError>()),
      );
      expect(
        () => MetricDefinition.fromMap({...row, 'storage_unit': null}),
        throwsA(isA<TypeError>()),
      );
    });

    test('a tracked metric', () {
      final t = TrackedMetric.fromMap(
        _object(
          '{"id": "6f1c1d4e-0b8a-4c43-9a55-1e1f2c3d4e5f", '
          '"metric_catalog_id": 3, "is_active": false, '
          '"is_favorite": true, "sort_order": 2}',
        ),
      );
      expect(t.id, '6f1c1d4e-0b8a-4c43-9a55-1e1f2c3d4e5f');
      expect(t.metricCatalogId, 3);
      expect(t.isActive, isFalse);
      expect(t.isFavorite, isTrue);
      expect(t.sortOrder, 2);
      expect(
        () => TrackedMetric.fromMap(_object('{"metric_catalog_id": 3}')),
        throwsA(isA<TypeError>()),
      );
    });
  });

  group('recorded days', () {
    test('a day of metric_daily_values', () {
      final day = DailyValue.fromMap(_object(_aggregate));
      expect(day.localDate, LocalDate(2026, 11, 2));
      expect(day.timezoneName, 'Europe/Paris');
      expect(day.sampleCount, 3);
      expect(day.value, closeTo(8.3333, 0.0001));
      expect(day.valueSum, 25.0);
      expect(day.valueMin, 8.0);
      expect(day.valueMax, 9.0);
      expect(day.valueLast, 8.0);
    });

    test('a date sent as a timestamp keeps its calendar day', () {
      final day = DailyValue.fromMap({
        ..._object(_aggregate),
        'local_date': '2026-11-02T00:00:00+00:00',
      });
      expect(day.localDate, LocalDate(2026, 11, 2));
    });

    test('a missing or unreadable day is an error', () {
      final row = _object(_aggregate);
      expect(
        () => DailyValue.fromMap({...row, 'local_date': '02/11/2026'}),
        throwsFormatException,
      );
      expect(
        () => DailyValue.fromMap({...row}..remove('local_date')),
        throwsA(isA<TypeError>()),
      );
      expect(
        () => DailyValue.fromMap({...row}..remove('sample_count')),
        throwsA(isA<TypeError>()),
      );
    });

    test('the answer of record_metric_entry, for each status', () {
      for (final (status, expected) in [
        ('recorded', EntryStatus.recorded),
        ('duplicate', EntryStatus.duplicate),
        ('already_recorded', EntryStatus.alreadyRecorded),
      ]) {
        final result = EntryResult.fromResponse(
          _decode('{"status": "$status", "aggregate": $_aggregate}'),
        );
        expect(result.status, expected);
        expect(result.day.sampleCount, 3);
      }
    });

    test('an unusable entry answer is an error, never a success', () {
      expect(
        () => EntryResult.fromResponse(
          _decode('{"status": "saved", "aggregate": $_aggregate}'),
        ),
        throwsFormatException,
      );
      expect(
        () => EntryResult.fromResponse(_decode('{"status": "recorded"}')),
        throwsFormatException,
      );
      expect(() => EntryResult.fromResponse(null), throwsFormatException);
      expect(
        () => EntryResult.fromResponse(_decode('[]')),
        throwsFormatException,
      );
    });
  });

  group('statistics (SQL functions)', () {
    test('chart points of get_metric_history', () {
      final series = MetricSeries.fromRows(_decode(_history));
      expect(series.bucket, SeriesBucket.week);
      expect(series.points, hasLength(2));
      final first = series.points.first;
      expect(first.start, LocalDate(2026, 10, 26));
      expect(first.value, 12.5);
      expect(first.sampleCount, 4);
      expect(first.daysCount, 3);
      expect(first.valueMin, 10.0);
      expect(first.valueMax, 15.0);
      expect(series.points.last.value, 9.0, reason: 'int read as double');
    });

    test('no point: the requested grouping is kept', () {
      expect(MetricSeries.fromRows(_decode('[]')).bucket, SeriesBucket.day);
      expect(
        MetricSeries.fromRows(
          _decode('[]'),
          requested: SeriesBucket.month,
        ).bucket,
        SeriesBucket.month,
      );
    });

    test('an unusable history is an error, not an empty chart', () {
      expect(() => MetricSeries.fromRows(null), throwsFormatException);
      expect(
        () => MetricSeries.fromRows(_decode('{"bucket": "day"}')),
        throwsFormatException,
      );
      expect(
        () => MetricSeries.fromRows(_decode('["2026-11-02"]')),
        throwsFormatException,
      );
    });

    test('get_metric_statistics with every part', () {
      final stats = MetricStatistics.fromResponse(_decode(_statistics));
      expect(stats.period.value, 8.6);
      expect(stats.period.perDayAverage, isNull);
      expect(stats.period.daysCount, 5);
      expect(stats.period.sampleCount, 5);
      expect(stats.period.firstDate, LocalDate(2026, 10, 20));
      expect(stats.period.lastDate, LocalDate(2026, 11, 10));
      expect(stats.allTime.daysCount, 6);
      expect(stats.allTime.firstDate, LocalDate(2026, 10, 1));
      expect(stats.latest!.date, LocalDate(2026, 11, 10));
      expect(stats.latest!.value, 10.0);
      expect(stats.latest!.count, 1);
      expect(stats.record!.value, 10.0);
      expect(stats.record!.count, isNull);
      expect(stats.trend!.slopePerDay, 0.0712);
      expect(stats.trend!.r2, 0.41);
      expect(stats.trend!.points, 5);
    });

    test('get_metric_statistics over an empty period', () {
      final stats = MetricStatistics.fromResponse(_decode(_emptyStatistics));
      expect(stats.period.daysCount, 0);
      expect(stats.period.value, isNull);
      expect(stats.period.firstDate, isNull);
      expect(stats.allTime.daysCount, 2);
      expect(stats.allTime.value, 3600.0);
      expect(stats.record, isNull);
      expect(stats.trend, isNull);
      // A trend whose fit is undefined (all values equal): r2 is null.
      final flat = MetricStatistics.fromResponse({
        ..._object(_statistics),
        'trend': {'slope_per_day': 0, 'r2': null, 'points': 5},
      });
      expect(flat.trend!.slopePerDay, 0.0);
      expect(flat.trend!.r2, isNull);
    });

    test('unusable statistics are an error, never an empty period', () {
      expect(
        () => MetricStatistics.fromResponse(_decode('[]')),
        throwsFormatException,
      );
      expect(
        () => MetricStatistics.fromResponse(
          {..._object(_statistics)}..remove('period'),
        ),
        throwsFormatException,
      );
    });

    test('compare_metric_periods, comparable or not', () {
      final c = PeriodComparison.fromResponse(_decode(_comparison));
      expect(c.comparable, isTrue);
      expect(c.minDays, 3);
      expect(c.reference.value, 12000.0);
      expect(c.reference.daysCount, 4);
      expect(c.compared.daysCount, 3);
      expect(c.difference, 3000.0);
      expect(c.percentChange, 25.0);

      final not = PeriodComparison.fromResponse({
        ..._object(_comparison),
        'b': {
          'from': '2026-10-13',
          'to': '2026-10-19',
          'value': 4000,
          'days_count': 1,
          'sample_count': 1,
        },
        'comparable': false,
        'difference': null,
        'percent_change': null,
      });
      expect(not.comparable, isFalse);
      expect(not.difference, isNull);
      expect(not.percentChange, isNull);
      expect(
        () => PeriodComparison.fromResponse('comparable'),
        throwsFormatException,
      );
    });
  });

  group('overview (get_overview)', () {
    test('a metric with data and a metric without', () {
      final overview = Overview.fromResponse(_decode(_overview));
      expect(overview.today, LocalDate(2026, 11, 11));
      expect(overview.timezone, 'Europe/Paris');
      expect(overview.daysRecorded, 4);
      expect(overview.entriesCount, 7);
      expect(overview.firstDate, LocalDate(2026, 10, 1));
      expect(overview.metrics, hasLength(2));

      final withData = overview.metricFor(
        '6f1c1d4e-0b8a-4c43-9a55-1e1f2c3d4e5f',
      )!;
      expect(withData.metricCatalogId, 1);
      expect(withData.isFavorite, isTrue);
      expect(withData.daysCount, 4);
      expect(withData.latest!.value, 9.5);
      expect(withData.latest!.count, 2);
      expect(withData.recent.value, 9.25);
      expect(withData.recent.daysCount, 3);
      expect(withData.previous.value, 8.0);
      expect(withData.comparable, isFalse);

      final empty = overview.metrics.last;
      expect(empty.isActive, isFalse);
      expect(empty.daysCount, 0);
      expect(empty.firstDate, isNull);
      expect(empty.latest, isNull);
      expect(empty.recent.value, isNull);
    });

    test('a new user: nothing recorded yet', () {
      final overview = Overview.fromResponse(
        _decode(
          '{"today": "2026-11-11", "timezone": "UTC", "min_days": 3, '
          '"days_recorded": 0, "entries_count": 0, "first_date": null, '
          '"metrics": []}',
        ),
      );
      expect(overview.daysRecorded, 0);
      expect(overview.firstDate, isNull);
      expect(overview.metrics, isEmpty);
    });

    test('an unusable overview is an error, never "nothing recorded"', () {
      final full = _object(_overview);
      for (final bad in <Object?>[
        null,
        <Object>[],
        'overview',
        {...full}..remove('today'),
        {...full, 'metrics': null},
        {...full, 'metrics': 'none'},
        {
          ...full,
          'metrics': [1],
        },
      ]) {
        expect(
          () => Overview.fromResponse(bad),
          throwsFormatException,
          reason: '$bad',
        );
      }
      expect(
        () => Overview.fromResponse({...full, 'days_recorded': '4'}),
        throwsA(isA<TypeError>()),
      );
    });
  });

  group('profile (profiles)', () {
    test('a profile row', () {
      final profile = UserProfile.fromMap(
        _object(
          '{"display_name": "Léo", "timezone": "America/Montreal", '
          '"theme_palette": "violet", "theme_mode": "light", '
          '"coach_data_access": true}',
        ),
      );
      expect(profile.displayName, 'Léo');
      expect(profile.timezone, 'America/Montreal');
      expect(profile.appearance.palette, AppPalette.violet);
      expect(profile.appearance.mode, AppThemeMode.light);
      expect(profile.coachDataAccess, isTrue);
    });

    test('a new profile: null name, defaults for unknown values', () {
      final profile = UserProfile.fromMap(
        _object(
          '{"display_name": null, "timezone": "UTC", '
          '"theme_palette": "pink", "theme_mode": null, '
          '"coach_data_access": false}',
        ),
      );
      expect(profile.displayName, isNull);
      expect(profile.appearance.palette, AppPalette.blue);
      expect(profile.appearance.mode, AppThemeMode.dark);
      expect(profile.coachDataAccess, isFalse);
    });
  });

  group('through the real repository and HTTP', () {
    late SupabaseTestServer server;
    late SupabaseMetricsRepository repository;
    final answers = <String, String>{};

    setUp(() async {
      answers.clear();
      server = SupabaseTestServer((request) async {
        // RPCs: /rest/v1/rpc/<name>; tables: /rest/v1/<table>.
        final name = request.url.pathSegments.last;
        final body = answers[name];
        if (body == null) return http.Response('not found', 404);
        return http.Response(
          body,
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      await server.signIn();
      repository = SupabaseMetricsRepository(server.client);
    });

    test('tables: catalog and tracked metrics', () async {
      answers['metric_catalog'] = '[$_course5km, $_courseDistance]';
      answers['user_metrics'] =
          '[{"id": "6f1c1d4e-0b8a-4c43-9a55-1e1f2c3d4e5f", '
          '"metric_catalog_id": 4, "is_active": true, "is_favorite": false, '
          '"sort_order": 0}]';
      final catalog = await repository.loadCatalog();
      expect(catalog.map((d) => d.slug), ['course_5km', 'course_distance']);
      expect(catalog.first.durationFields, [
        DurationField.minutes,
        DurationField.seconds,
      ]);
      final tracked = await repository.loadTracked();
      expect(tracked.single.metricCatalogId, 4);
      expect(
        server.requests.last.url.queryParameters['user_id'],
        'eq.$testUserId',
      );
    });

    test('view: recorded days', () async {
      answers['metric_daily_values'] = '[$_aggregate]';
      final days = await repository.loadDays('um-1');
      expect(days.single.value, closeTo(8.3333, 0.0001));
    });

    test('functions: overview, history, statistics, comparison', () async {
      answers['get_overview'] = _overview;
      answers['get_metric_history'] = _history;
      answers['get_metric_statistics'] = _statistics;
      answers['compare_metric_periods'] = _comparison;
      final overview = await repository.loadOverview();
      expect(overview.metrics, hasLength(2));
      final from = LocalDate(2026, 10, 13);
      final to = LocalDate(2026, 11, 11);
      final series = await repository.loadSeries('um-1', from, to);
      expect(series.bucket, SeriesBucket.week);
      expect(
        (await repository.loadStatistics('um-1', from, to)).trend,
        isNotNull,
      );
      final comparison = await repository.comparePeriods(
        'um-1',
        referenceFrom: from,
        referenceTo: to,
        comparedFrom: from,
        comparedTo: to,
      );
      expect(comparison.percentChange, 25.0);
    });

    test('a metric that is not (or no longer) tracked', () async {
      // get_metric_statistics and compare_metric_periods return SQL null.
      answers['get_metric_statistics'] = 'null';
      final day = LocalDate(2026, 11, 11);
      await expectLater(
        repository.loadStatistics('um-1', day, day),
        throwsA(_fails(DataFailure.metricNotTracked)),
      );
      // get_metric_history returns no row.
      answers['get_metric_history'] = '[]';
      expect((await repository.loadSeries('um-1', day, day)).points, isEmpty);
    });

    test('writes: an entry and a corrected day', () async {
      answers['record_metric_entry'] =
          '{"status": "duplicate", "aggregate": $_aggregate}';
      answers['correct_metric_day'] =
          '{"status": "corrected", "aggregate": $_aggregate}';
      final result = await repository.recordEntry(
        EntryRequest(
          trackedMetricId: 'um-1',
          value: 8,
          unit: 'repetition',
          localDate: LocalDate(2026, 11, 2),
          timezone: 'Europe/Paris',
          idempotencyKey: '22222222-2222-2222-2222-222222222222',
        ),
      );
      expect(result.status, EntryStatus.duplicate);
      final corrected = await repository.correctDay(
        'um-1',
        LocalDate(2026, 11, 2),
        8,
        'repetition',
      );
      expect(corrected.sampleCount, 3);
    });

    test('time zones, in both shapes of a set of text', () async {
      answers['list_timezones'] = '["Europe/Paris", "UTC"]';
      expect(await repository.loadTimezones(), ['Europe/Paris', 'UTC']);
      answers['list_timezones'] =
          '[{"list_timezones": "Asia/Tokyo"}, {"list_timezones": "UTC"}]';
      expect(await repository.loadTimezones(), ['Asia/Tokyo', 'UTC']);
    });

    test('unusable answers are reported as such', () async {
      answers['get_overview'] = '[]';
      await expectLater(
        repository.loadOverview(),
        throwsA(_fails(DataFailure.badResponse)),
      );
      answers['metric_catalog'] = '[{"id": 4, "name": "Sans slug"}]';
      await expectLater(
        repository.loadCatalog(),
        throwsA(_fails(DataFailure.badResponse)),
      );
      answers['list_timezones'] = '{"zones": []}';
      await expectLater(
        repository.loadTimezones(),
        throwsA(_fails(DataFailure.badResponse)),
      );
      // A write whose answer cannot be read may have been applied.
      answers['record_metric_entry'] = '{"status": "recorded"}';
      await expectLater(
        repository.recordEntry(
          EntryRequest(
            trackedMetricId: 'um-1',
            value: 8,
            unit: 'repetition',
            localDate: LocalDate(2026, 11, 2),
            timezone: 'Europe/Paris',
            idempotencyKey: '33333333-3333-3333-3333-333333333333',
          ),
        ),
        throwsA(_fails(DataFailure.writeUncertain)),
      );
    });
  });
}
