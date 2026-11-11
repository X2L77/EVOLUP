import 'package:flutter/foundation.dart';

import '../../data/local_date.dart';
import '../../data/metrics/metric_models.dart';
import '../../data/metrics/metrics_repository.dart';

/// Catalog and tracked metrics shared by every page of the session, and the
/// write operations on the user's data.
///
/// [revision] increases whenever recorded data changes (entry, correction,
/// deletion), so pages showing data know they must reload.
class MetricsController extends ChangeNotifier {
  MetricsController(this.repository);

  final MetricsRepository repository;
  List<MetricCategory> _categories = const [];
  List<MetricDefinition> _catalog = const [];
  List<TrackedMetric> _tracked = const [];
  int _revision = 0;
  bool _disposed = false;

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
    _tracked = results[2] as List<TrackedMetric>;
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
  Future<TrackedMetric> track(MetricDefinition metric) async {
    final existing = trackedFor(metric.id);
    if (existing != null) {
      return existing.isActive ? existing : setActive(existing, true);
    }
    final added = await repository.track(metric.id);
    _tracked = [..._tracked, added];
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
    final updated = await call();
    _tracked = [for (final t in _tracked) t.id == metric.id ? updated : t];
    _notify();
    return updated;
  }

  /// Deletes the metric from the user's space with its whole history.
  Future<void> deleteTracked(TrackedMetric metric) async {
    await repository.deleteTracked(metric.id);
    _tracked = [
      for (final t in _tracked)
        if (t.id != metric.id) t,
    ];
    _dataChanged();
  }

  Future<EntryResult> record(EntryRequest request) async {
    final result = await repository.recordEntry(request);
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
    final value = await repository.correctDay(
      metric.id,
      day,
      storedValue,
      definition.storageUnit,
    );
    _dataChanged();
    return value;
  }

  Future<void> deleteDay(TrackedMetric metric, LocalDate day) async {
    await repository.deleteDay(metric.id, day);
    _dataChanged();
  }

  Future<void> deleteHistory(TrackedMetric metric) async {
    await repository.deleteHistory(metric.id);
    _dataChanged();
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
    super.dispose();
  }
}
