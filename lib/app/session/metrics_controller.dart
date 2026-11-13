import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/data_error.dart';
import '../../data/local_date.dart';
import '../../data/metrics/metric_models.dart';
import '../../data/metrics/metrics_repository.dart';

/// Catalog and tracked metrics shared by every page of the session, and the
/// write operations on the user's data.
///
/// [revision] increases whenever recorded data changes (entry, correction,
/// deletion), so pages showing data know they must reload.
///
/// A write whose outcome is uncertain ([DataFailure.writeUncertain]) is never
/// assumed cancelled: the tracked metrics are read again at once, and once
/// more when the abandoned request ends ([DataException.settled]), since the
/// server may apply it after the first read. A read is applied only if no
/// newer change of the list happened while it ran.
///
/// The overview (`get_overview`) is shared by the pages through
/// [loadOverview]: one request at a time, its answer reused until the data
/// or the device's day change, or it gets older than [overviewMaxAge]. The
/// chart series are shared the same way through [loadSeries], so two pages
/// or widgets asking for the same series send one request.
class MetricsController extends ChangeNotifier {
  MetricsController(
    this.repository, {
    DateTime Function()? now,
    LocalDate Function()? today,
  }) : _now = now ?? DateTime.now,
       _today = today ?? LocalDate.today;

  /// How long a loaded overview is reused. Every change made from this
  /// device invalidates it at once; this bound only covers what changes
  /// elsewhere (another device, a new day in the profile's time zone), so
  /// a page opened later reads it again, as before the cache.
  static const overviewMaxAge = Duration(seconds: 30);

  final MetricsRepository repository;
  final DateTime Function() _now;

  /// The device's day (the session's `LocalDayClock`), sent to the overview.
  final LocalDate Function() _today;
  List<MetricCategory> _categories = const [];
  List<MetricDefinition> _catalog = const [];
  List<TrackedMetric> _tracked = const [];

  /// Increases at each local change of [_tracked] (load, confirmed write):
  /// a re-read that started before it brings an older state.
  int _localChanges = 0;

  /// Re-reads are numbered when they start; only one started after the
  /// last applied one may replace the list.
  int _readTicket = 0;
  int _appliedTicket = 0;
  int _revision = 0;
  bool _disposed = false;
  final _pendingTracks = <int, Future<TrackedMetric>>{};
  Future<void>? _pendingDeleteAll;
  _OverviewRead? _overview;
  _OverviewRead? _pendingOverview;
  final _series = <_SeriesQuery, _SeriesRead>{};

  List<MetricCategory> get categories => _categories;
  List<MetricDefinition> get catalog => _catalog;
  List<TrackedMetric> get tracked => _tracked;
  int get revision => _revision;

  Future<void> load() async {
    final results = await Future.wait<Object>([
      repository.loadCategories(),
      repository.loadCatalog(),
      repository.loadTracked(),
    ]);
    _categories = results[0] as List<MetricCategory>;
    // `metric_catalog.sort_order` is numbered inside each category: grouping
    // by category first keeps the catalog from mixing categories.
    _catalog = (results[1] as List<MetricDefinition>).toList()
      ..sort(_compareDefinitions);
    _setTracked(results[2] as List<TrackedMetric>);
    _notify();
  }

  /// Catalog order: category order, then the metric's order inside it.
  int _compareDefinitions(MetricDefinition? a, MetricDefinition? b) {
    int categoryOrder(MetricDefinition? d) =>
        (d == null ? null : category(d.categoryId))?.sortOrder ?? 0;
    final byCategory = categoryOrder(a).compareTo(categoryOrder(b));
    if (byCategory != 0) return byCategory;
    final byMetric = (a?.sortOrder ?? 0).compareTo(b?.sortOrder ?? 0);
    if (byMetric != 0) return byMetric;
    return (a?.id ?? 0).compareTo(b?.id ?? 0);
  }

  MetricCategory? category(int id) =>
      _categories.where((c) => c.id == id).firstOrNull;

  MetricDefinition? definition(int id) =>
      _catalog.where((d) => d.id == id).firstOrNull;

  /// The catalog metric named by [slug], only if it is active.
  MetricDefinition? activeDefinition(String slug) =>
      _catalog.where((d) => d.slug == slug && d.isActive).firstOrNull;

  TrackedMetric? trackedFor(int metricCatalogId) =>
      _tracked.where((t) => t.metricCatalogId == metricCatalogId).firstOrNull;

  TrackedMetric? trackedById(String id) =>
      _tracked.where((t) => t.id == id).firstOrNull;

  /// Active tracked metrics: favourites first, then in catalog order.
  List<TrackedMetric> get activeTracked =>
      _sorted(_tracked.where((t) => t.isActive));

  /// Metrics removed from the active list; their history is kept.
  List<TrackedMetric> get inactiveTracked =>
      _sorted(_tracked.where((t) => !t.isActive));

  /// Active catalog metrics the user does not track yet.
  List<MetricDefinition> get untrackedActive => [
    for (final d in _catalog)
      if (d.isActive && trackedFor(d.id) == null) d,
  ];

  List<TrackedMetric> _sorted(Iterable<TrackedMetric> metrics) =>
      metrics.toList()..sort((a, b) {
        if (a.isFavorite != b.isFavorite) return a.isFavorite ? -1 : 1;
        return _compareDefinitions(
          definition(a.metricCatalogId),
          definition(b.metricCatalogId),
        );
      });

  /// Adds [metric] to the user's space, or reactivates it if it was removed.
  /// A second call while the first is running (double tap) shares its
  /// request and result.
  Future<TrackedMetric> track(MetricDefinition metric) =>
      _pendingTracks[metric.id] ??= _track(metric).whenComplete(() {
        // Block body: returning the removed future would make whenComplete
        // wait for itself.
        _pendingTracks.remove(metric.id);
      });

  Future<TrackedMetric> _track(MetricDefinition metric) async {
    final existing = trackedFor(metric.id);
    if (existing != null) {
      return existing.isActive ? existing : setActive(existing, true);
    }
    final added = await _write(() => repository.track(metric.id));
    _setTracked([..._tracked, added]);
    _notify();
    return added;
  }

  Future<TrackedMetric> setActive(TrackedMetric metric, bool active) => _update(
    metric,
    () => repository.updateTracked(metric.id, isActive: active),
  );

  Future<TrackedMetric> setFavorite(TrackedMetric metric, bool favorite) =>
      _update(
        metric,
        () => repository.updateTracked(metric.id, isFavorite: favorite),
      );

  Future<TrackedMetric> _update(
    TrackedMetric metric,
    Future<TrackedMetric> Function() call,
  ) async {
    final updated = await _write(call);
    _setTracked([for (final t in _tracked) t.id == metric.id ? updated : t]);
    _notify();
    return updated;
  }

  /// Deletes the metric from the user's space with its whole history.
  Future<void> deleteTracked(TrackedMetric metric) async {
    await _write(() => repository.deleteTracked(metric.id));
    _setTracked([
      for (final t in _tracked)
        if (t.id != metric.id) t,
    ]);
    _dataChanged();
  }

  /// Deletes every tracked metric with its whole history in one atomic
  /// request, then notifies the pages once. Nothing changes locally if it
  /// fails. A second call while it runs shares the same request.
  Future<void> deleteAllTracked() =>
      _pendingDeleteAll ??= _deleteAll().whenComplete(() {
        _pendingDeleteAll = null;
      });

  Future<void> _deleteAll() async {
    await _write(repository.deleteAllTracked);
    _setTracked(const []);
    _dataChanged();
  }

  Future<EntryResult> record(EntryRequest request) async {
    final result = await _write(() => repository.recordEntry(request));
    if (result.status == EntryStatus.recorded) _dataChanged();
    return result;
  }

  Future<DailyValue> correctDay(
    TrackedMetric metric,
    LocalDate day,
    num storedValue,
  ) async {
    final definition = this.definition(metric.metricCatalogId);
    if (definition == null) throw StateError('Unknown metric');
    final value = await _write(
      () => repository.correctDay(
        metric.id,
        day,
        storedValue,
        definition.storageUnit,
      ),
    );
    _dataChanged();
    return value;
  }

  Future<void> deleteDay(TrackedMetric metric, LocalDate day) async {
    await _write(() => repository.deleteDay(metric.id, day));
    _dataChanged();
  }

  Future<void> deleteHistory(TrackedMetric metric) async {
    await _write(() => repository.deleteHistory(metric.id));
    _dataChanged();
  }

  /// The overview, shared by every page of the session.
  ///
  /// - A request already running for the current state is shared.
  /// - The last answer is reused while nothing changed since it was asked
  ///   (no write, no change of the tracked list) and it is recent
  ///   ([overviewMaxAge]); [refresh] skips it (pull to refresh).
  /// - An answer asked before a change is returned to its caller (pages
  ///   order their own reloads) but never kept: it may predate the change.
  /// - Failures are not kept: the next call asks again.
  Future<Overview> loadOverview({bool refresh = false}) {
    final state = _overviewState;
    final cached = _overview;
    if (!refresh &&
        cached != null &&
        cached.state == state &&
        _now().difference(cached.askedAt) < overviewMaxAge) {
      return cached.answer;
    }
    final pending = _pendingOverview;
    if (pending != null && pending.state == state) return pending.answer;
    final read = _OverviewRead(
      state,
      _now(),
      repository.loadOverview(today: state.$3),
    );
    _pendingOverview = read;
    unawaited(
      read.answer.then<void>(
        (_) {
          if (identical(_pendingOverview, read)) _pendingOverview = null;
          if (!_disposed && read.state == _overviewState) _overview = read;
        },
        onError: (Object _) {
          // The caller gets the error; nothing is kept.
          if (identical(_pendingOverview, read)) _pendingOverview = null;
        },
      ),
    );
    return read.answer;
  }

  /// What the overview depends on: the recorded data ([revision]), the
  /// tracked list (active, favourite, added) and the device's day (its
  /// "today" and 30-day windows). Any change makes it stale.
  (int, int, LocalDate) get _overviewState =>
      (_revision, _localChanges, _today());

  /// What a series depends on besides its query: the recorded data and the
  /// tracked list (its days are explicit, not relative to today).
  (int, int) get _dataState => (_revision, _localChanges);

  /// The points of a chart, shared: a request running or answered for the
  /// same query while the data did not change, and not older than
  /// [overviewMaxAge], is reused instead of sending another one (the
  /// analysis and the comparison of the statistics ask for the same series).
  /// Failures are not kept.
  Future<MetricSeries> loadSeries(
    String trackedMetricId,
    LocalDate from,
    LocalDate to, {
    SeriesBucket? bucket,
  }) {
    final query = _SeriesQuery(trackedMetricId, from, to, bucket);
    final state = _dataState;
    final known = _series[query];
    if (known != null &&
        known.state == state &&
        _now().difference(known.askedAt) < overviewMaxAge) {
      return known.answer;
    }
    // Series of an older state are never reused: forget them.
    _series.removeWhere((_, read) => read.state != state);
    if (_series.length >= 32) _series.remove(_series.keys.first);
    final read = _SeriesRead(
      state,
      _now(),
      repository.loadSeries(trackedMetricId, from, to, bucket: bucket),
    );
    _series[query] = read;
    unawaited(
      read.answer.then<void>(
        (_) {},
        onError: (Object _) {
          // The caller gets the error; the next call asks again.
          if (identical(_series[query], read)) _series.remove(query);
        },
      ),
    );
    return read.answer;
  }

  Future<T> _write<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on Object catch (error) {
      if (classifyDataError(error) == DataFailure.writeUncertain) {
        unawaited(_resync());
        if (error case DataException(:final settled?)) {
          // The server may still apply it: read again once it is done.
          unawaited(settled.then((_) => _resync()));
        }
      }
      rethrow;
    }
  }

  /// After a write whose outcome is unknown: reads the tracked metrics again
  /// and makes every page reload its data. A read overtaken by a newer
  /// change (a local write, or a later re-read that finished first) is
  /// dropped instead of bringing an older state back.
  Future<void> _resync() async {
    final ticket = ++_readTicket;
    final localChanges = _localChanges;
    try {
      final tracked = await repository.loadTracked();
      if (_disposed) return;
      if (ticket > _appliedTicket && localChanges == _localChanges) {
        _appliedTicket = ticket;
        _tracked = tracked;
      }
    } on Object {
      // Still unreachable: pages reload, and show their own error if any.
    }
    if (!_disposed) _dataChanged();
  }

  /// A local change of the list: overtakes the re-reads still running.
  void _setTracked(List<TrackedMetric> tracked) {
    _tracked = tracked;
    _localChanges++;
  }

  void _dataChanged() {
    _revision++;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _overview = null;
    _series.clear();
    super.dispose();
  }
}

/// One `get_overview` request, with the state of the data when it was asked.
class _OverviewRead {
  _OverviewRead(this.state, this.askedAt, this.answer);

  final (int, int, LocalDate) state;

  /// Age is counted from the request, not the answer: the server read the
  /// data at some point in between.
  final DateTime askedAt;
  final Future<Overview> answer;
}

@immutable
class _SeriesQuery {
  const _SeriesQuery(this.trackedId, this.from, this.to, this.bucket);

  final String trackedId;
  final LocalDate from;
  final LocalDate to;

  /// `null` = automatic grouping (the server picks it from the period).
  final SeriesBucket? bucket;

  @override
  bool operator ==(Object other) =>
      other is _SeriesQuery &&
      other.trackedId == trackedId &&
      other.from == from &&
      other.to == to &&
      other.bucket == bucket;

  @override
  int get hashCode => Object.hash(trackedId, from, to, bucket);
}

/// One `get_metric_history` request, with the state of the data when it was
/// asked.
class _SeriesRead {
  _SeriesRead(this.state, this.askedAt, this.answer);

  final (int, int) state;
  final DateTime askedAt;
  final Future<MetricSeries> answer;
}
