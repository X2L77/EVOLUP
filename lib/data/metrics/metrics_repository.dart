import 'package:supabase_flutter/supabase_flutter.dart';

import '../data_error.dart';
import '../local_date.dart';
import 'metric_models.dart';

/// Catalog, tracked metrics and daily aggregates of the signed-in user.
///
/// The user always comes from the Supabase session; RLS restricts every
/// read and write to the user's own rows. Entries and corrections go through
/// the database functions, which validate and aggregate them.
abstract interface class MetricsRepository {
  Future<List<MetricCategory>> loadCategories();
  Future<List<MetricDefinition>> loadCatalog();
  Future<List<TrackedMetric>> loadTracked();

  /// Adds an active catalog metric to the user's space.
  Future<TrackedMetric> track(int metricCatalogId);
  Future<TrackedMetric> updateTracked(
    String trackedMetricId, {
    bool? isActive,
    bool? isFavorite,
  });

  /// Deletes a tracked metric and its whole history.
  Future<void> deleteTracked(String trackedMetricId);

  Future<EntryResult> recordEntry(EntryRequest request);

  /// Replaces a recorded day by a single corrected value.
  Future<DailyValue> correctDay(
    String trackedMetricId,
    LocalDate day,
    num storedValue,
    String unit,
  );
  Future<void> deleteDay(String trackedMetricId, LocalDate day);
  Future<void> deleteHistory(String trackedMetricId);

  /// Recorded days, most recent first.
  Future<List<DailyValue>> loadDays(
    String trackedMetricId, {
    int limit = 30,
    int offset = 0,
  });
  Future<MetricSeries> loadSeries(
    String trackedMetricId,
    LocalDate from,
    LocalDate to, {
    SeriesBucket? bucket,
  });
  Future<MetricStatistics> loadStatistics(
    String trackedMetricId,
    LocalDate from,
    LocalDate to,
  );
  Future<PeriodComparison> comparePeriods(
    String trackedMetricId, {
    required LocalDate referenceFrom,
    required LocalDate referenceTo,
    required LocalDate comparedFrom,
    required LocalDate comparedTo,
  });
  Future<Overview> loadOverview();
  Future<List<String>> loadTimezones();
}

class SupabaseMetricsRepository implements MetricsRepository {
  SupabaseMetricsRepository(this._client);

  final SupabaseClient _client;

  static const _catalogColumns =
      'id, slug, category_id, name, description, value_kind, storage_unit, '
      'storage_scale, unit_label, display_factor, display_decimals, '
      'aggregation, record_direction, min_value, max_value, daily_sum_max, '
      'form_config, keywords, is_active, sort_order';
  static const _trackedColumns =
      'id, metric_catalog_id, is_active, is_favorite, sort_order';

  String get _userId {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw AuthSessionMissingException();
    return userId;
  }

  @override
  Future<List<MetricCategory>> loadCategories() async {
    final rows = await _client
        .from('metric_categories')
        .select('id, slug, name, description, sort_order')
        .order('sort_order');
    return rows.map(MetricCategory.fromMap).toList();
  }

  @override
  Future<List<MetricDefinition>> loadCatalog() async {
    final rows = await _client
        .from('metric_catalog')
        .select(_catalogColumns)
        .order('sort_order');
    return rows.map(MetricDefinition.fromMap).toList();
  }

  @override
  Future<List<TrackedMetric>> loadTracked() async {
    final rows = await _client
        .from('user_metrics')
        .select(_trackedColumns)
        .eq('user_id', _userId)
        .order('added_at');
    return rows.map(TrackedMetric.fromMap).toList();
  }

  @override
  Future<TrackedMetric> track(int metricCatalogId) async {
    final row = await _client
        .from('user_metrics')
        .insert({'user_id': _userId, 'metric_catalog_id': metricCatalogId})
        .select(_trackedColumns)
        .single();
    return TrackedMetric.fromMap(row);
  }

  @override
  Future<TrackedMetric> updateTracked(
    String trackedMetricId, {
    bool? isActive,
    bool? isFavorite,
  }) async {
    final row = await _client
        .from('user_metrics')
        .update({'is_active': ?isActive, 'is_favorite': ?isFavorite})
        .eq('id', trackedMetricId)
        .select(_trackedColumns)
        .single();
    return TrackedMetric.fromMap(row);
  }

  @override
  Future<void> deleteTracked(String trackedMetricId) async {
    final rows = await _client
        .from('user_metrics')
        .delete()
        .eq('id', trackedMetricId)
        .select('id');
    if (rows.isEmpty) throw const DataException(DataFailure.metricNotTracked);
  }

  @override
  Future<EntryResult> recordEntry(EntryRequest request) async {
    final data = await _client.rpc(
      'record_metric_entry',
      params: {
        'p_user_metric_id': request.trackedMetricId,
        'p_value': request.value,
        'p_unit': request.unit,
        'p_local_date': request.localDate.iso,
        'p_timezone': request.timezone,
        'p_idempotency_key': request.idempotencyKey,
      },
    );
    return EntryResult.fromResponse(data);
  }

  @override
  Future<DailyValue> correctDay(
    String trackedMetricId,
    LocalDate day,
    num storedValue,
    String unit,
  ) async {
    final data = await _client.rpc(
      'correct_metric_day',
      params: {
        'p_user_metric_id': trackedMetricId,
        'p_local_date': day.iso,
        'p_value': storedValue,
        'p_unit': unit,
      },
    );
    if (data is! Map || data['aggregate'] is! Map) {
      throw const DataException(DataFailure.badResponse);
    }
    return DailyValue.fromMap(Map<String, dynamic>.from(data['aggregate']));
  }

  @override
  Future<void> deleteDay(String trackedMetricId, LocalDate day) async {
    final rows = await _client
        .from('metric_daily_aggregates')
        .delete()
        .eq('user_metric_id', trackedMetricId)
        .eq('local_date', day.iso)
        .select('id');
    if (rows.isEmpty) throw const DataException(DataFailure.dayNotFound);
  }

  @override
  Future<void> deleteHistory(String trackedMetricId) async {
    await _client
        .from('metric_daily_aggregates')
        .delete()
        .eq('user_metric_id', trackedMetricId);
  }

  @override
  Future<List<DailyValue>> loadDays(
    String trackedMetricId, {
    int limit = 30,
    int offset = 0,
  }) async {
    final rows = await _client
        .from('metric_daily_values')
        .select(
          'local_date, timezone_name, sample_count, value_sum, value_min, '
          'value_max, value_last, daily_value',
        )
        .eq('user_metric_id', trackedMetricId)
        .order('local_date', ascending: false)
        .range(offset, offset + limit - 1);
    return rows.map(DailyValue.fromMap).toList();
  }

  @override
  Future<MetricSeries> loadSeries(
    String trackedMetricId,
    LocalDate from,
    LocalDate to, {
    SeriesBucket? bucket,
  }) async {
    final data = await _client.rpc(
      'get_metric_history',
      params: {
        'p_user_metric_id': trackedMetricId,
        'p_from': from.iso,
        'p_to': to.iso,
        'p_bucket': bucket?.name ?? 'auto',
      },
    );
    return MetricSeries.fromRows(data, requested: bucket);
  }

  @override
  Future<MetricStatistics> loadStatistics(
    String trackedMetricId,
    LocalDate from,
    LocalDate to,
  ) async {
    final data = await _client.rpc(
      'get_metric_statistics',
      params: {
        'p_user_metric_id': trackedMetricId,
        'p_from': from.iso,
        'p_to': to.iso,
      },
    );
    if (data == null) throw const DataException(DataFailure.metricNotTracked);
    return MetricStatistics.fromResponse(data);
  }

  @override
  Future<PeriodComparison> comparePeriods(
    String trackedMetricId, {
    required LocalDate referenceFrom,
    required LocalDate referenceTo,
    required LocalDate comparedFrom,
    required LocalDate comparedTo,
  }) async {
    final data = await _client.rpc(
      'compare_metric_periods',
      params: {
        'p_user_metric_id': trackedMetricId,
        'p_a_from': referenceFrom.iso,
        'p_a_to': referenceTo.iso,
        'p_b_from': comparedFrom.iso,
        'p_b_to': comparedTo.iso,
      },
    );
    if (data == null) throw const DataException(DataFailure.metricNotTracked);
    return PeriodComparison.fromResponse(data);
  }

  @override
  Future<Overview> loadOverview() async =>
      Overview.fromResponse(await _client.rpc('get_overview'));

  @override
  Future<List<String>> loadTimezones() async {
    final data = await _client.rpc('list_timezones');
    if (data is! List) return const [];
    return [
      for (final item in data)
        if (item is String)
          item
        else if (item is Map && item.values.firstOrNull is String)
          item.values.first as String,
    ];
  }
}
