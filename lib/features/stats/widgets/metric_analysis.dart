import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/format/dates.dart';
import '../../../app/session/revision_reload.dart';
import '../../../app/widgets/glass_card.dart';
import '../../../app/widgets/state_views.dart';
import '../../../data/data_error.dart';
import '../../../data/local_date.dart';
import '../../../data/metrics/metric_models.dart';
import '../../../data/metrics/metric_values.dart';
import '../../../theme/evolup_theme.dart';
import '../../metrics/metric_texts.dart';
import 'metric_chart.dart';
import 'period_selector.dart';

/// Statistics of one tracked metric over a period, computed by PostgreSQL:
/// key figures, chart, comparison with the previous period of the same
/// length and trend. Reloads when the period or the recorded data change.
/// Shows an explanation instead of figures that the data cannot support.
class MetricAnalysis extends StatefulWidget {
  const MetricAnalysis({
    required this.tracked,
    required this.definition,
    required this.period,
    this.firstDate,
    this.bucket,
    this.today,
    super.key,
  });

  final TrackedMetric tracked;
  final MetricDefinition definition;
  final StatsPeriod period;

  /// First recorded day, start of the « Tout » period.
  final LocalDate? firstDate;

  /// `null` = automatic grouping.
  final SeriesBucket? bucket;
  final LocalDate? today;

  @override
  State<MetricAnalysis> createState() => _MetricAnalysisState();
}

/// What one load asks the server: the metric, the period's days, the period
/// it is compared with and the grouping. Two equal queries give the same
/// answer as long as the recorded data did not change.
@immutable
class _Query {
  const _Query(this.trackedId, this.from, this.to, this.previous, this.bucket);

  final String trackedId;
  final LocalDate from;
  final LocalDate to;
  final (LocalDate, LocalDate)? previous;
  final SeriesBucket? bucket;

  @override
  bool operator ==(Object other) =>
      other is _Query &&
      other.trackedId == trackedId &&
      other.from == from &&
      other.to == to &&
      other.previous == previous &&
      other.bucket == bucket;

  @override
  int get hashCode => Object.hash(trackedId, from, to, previous, bucket);
}

class _AnalysisData {
  const _AnalysisData(
    this.query,
    this.period,
    this.stats,
    this.series,
    this.comparison,
  );

  final _Query query;
  final StatsPeriod period;
  final MetricStatistics stats;
  final MetricSeries series;
  final PeriodComparison? comparison;
  LocalDate get from => query.from;
  LocalDate get to => query.to;
}

/// Loads once the session is available, again when the recorded data
/// change ([RevisionReload]) and when the query changes. Only the latest
/// load may update the figures; a failed reload keeps the figures of the
/// same query, never those of another metric or period.
class _MetricAnalysisState extends State<MetricAnalysis> with RevisionReload {
  _AnalysisData? _data;
  Object? _error;
  int _request = 0;

  /// Query of the latest load, running or done: a rebuild with the same
  /// query does not load it again.
  _Query? _asked;

  LocalDate get _today => widget.today ?? LocalDate.today();

  /// The first recorded day only matters for « Tout »: for the other
  /// periods, learning it must not reload anything.
  _Query get _query {
    final (from, to) = widget.period.range(_today, widget.firstDate);
    return _Query(
      widget.tracked.id,
      from,
      to,
      widget.period.previous(_today),
      widget.bucket,
    );
  }

  @override
  Future<void> reload() => _load();

  @override
  void didUpdateWidget(MetricAnalysis oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_asked != _query) unawaited(_load());
  }

  Future<void> _load() async {
    final request = ++_request;
    final query = _asked = _query;
    // An error belongs to the load it ended; this one starts clean (the
    // rebuild that follows shows the figures kept, or the loading state).
    _error = null;
    final period = widget.period;
    final repository = metrics.repository;
    final id = query.trackedId;
    final previous = query.previous;
    try {
      final stats = repository.loadStatistics(id, query.from, query.to);
      final series = repository.loadSeries(
        id,
        query.from,
        query.to,
        bucket: query.bucket,
      );
      final comparison = previous == null
          ? Future<PeriodComparison?>.value()
          : repository.comparePeriods(
              id,
              referenceFrom: previous.$1,
              referenceTo: previous.$2,
              comparedFrom: query.from,
              comparedTo: query.to,
            );
      final results = await Future.wait<Object?>([stats, series, comparison]);
      if (!mounted || request != _request) return;
      setState(() {
        _data = _AnalysisData(
          query,
          period,
          results[0]! as MetricStatistics,
          results[1]! as MetricSeries,
          results[2] as PeriodComparison?,
        );
        _error = null;
      });
    } on Object catch (error) {
      if (!mounted || request != _request) return;
      setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    final shown = _data;
    // Figures of another metric would be read with this metric's units.
    final data = shown?.query.trackedId == widget.tracked.id ? shown : null;
    // A failed reload keeps the figures it would have refreshed; figures of
    // another period are not shown as if they answered this one.
    if (error != null && (data == null || data.query != _query)) {
      return ErrorView(message: dataErrorMessage(error), onRetry: _retry);
    }
    if (data == null) return const LoadingView();
    return _Switching(
      // Figures of the previous period, kept in place while the selected one
      // loads (no jump), but visibly not its answer.
      loading: data.query != _query,
      child: _figures(context, data),
    );
  }

  /// The error is replaced by the usual loading view until the answer.
  void _retry() {
    setState(() {
      _error = null;
      // Only shown in error when it did not answer this query: not kept.
      _data = null;
    });
    unawaited(_load());
  }

  Widget _figures(BuildContext context, _AnalysisData data) {
    final d = widget.definition;
    final period = data.stats.period;
    final colors = EvolupColors.of(context);
    final textTheme = Theme.of(context).textTheme;
    if (period.daysCount == 0) {
      return GlassCard(
        child: EmptyState(
          key: const Key('analysis-empty'),
          compact: true,
          icon: Icons.insights_outlined,
          title: 'Aucune donnée sur cette période',
          message: data.stats.allTime.daysCount == 0
              ? 'Enregistrez une première valeur pour voir vos statistiques.'
              : 'Choisissez une période plus longue, comme « Tout », pour '
                    'voir vos ${daysLabel(data.stats.allTime.daysCount)} '
                    'enregistrées.',
        ),
      );
    }
    final aggregated = period.sampleCount > 1;
    final figures = <Widget>[
      _Figure(
        key: const Key('figure-period-value'),
        label: d.aggregation == MetricAggregation.average
            ? 'Moyenne (pondérée)'
            : d.aggregation.label,
        value: period.value == null
            ? '—'
            : formatValue(d, period.value!, aggregated: aggregated),
      ),
      if (period.perDayAverage != null)
        _Figure(
          label: 'Par journée enregistrée',
          value: formatAverage(d, period.perDayAverage!),
        ),
      _Figure(
        key: const Key('figure-days'),
        label: 'Journées',
        value: '${period.daysCount}',
      ),
      _Figure(
        key: const Key('figure-entries'),
        label: 'Saisies intégrées',
        value: '${period.sampleCount}',
      ),
      if (d.hasRecord && data.stats.record != null)
        _Figure(
          key: const Key('figure-record'),
          label: recordLabel(d),
          value: formatValue(d, data.stats.record!.value),
          detail: formatDate(data.stats.record!.date),
        ),
      if (data.stats.latest != null)
        _Figure(
          label: 'Dernière journée',
          value: formatValue(
            d,
            data.stats.latest!.value,
            aggregated: (data.stats.latest!.count ?? 1) > 1,
          ),
          detail: formatDate(data.stats.latest!.date),
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 560 ? 3 : 2;
            final width = (constraints.maxWidth - 10 * (columns - 1)) / columns;
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final figure in figures)
                  SizedBox(width: width, child: figure),
              ],
            );
          },
        ),
        const SizedBox(height: 14),
        GlassCard(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                d.aggregation == MetricAggregation.sum
                    ? 'Total par ${_bucketName(data.series.bucket)}'
                    : '${d.aggregation.label} par ${_bucketName(data.series.bucket)}',
                style: textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              MetricChart(
                definition: d,
                series: data.series,
                from: data.from,
                to: data.to,
              ),
              if (data.series.points.length < 2) ...[
                const SizedBox(height: 8),
                Text(
                  'Un seul point sur cette période : pas encore d’évolution à '
                  'afficher.',
                  style: textTheme.bodySmall?.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        _Insights(
          definition: d,
          period: data.period,
          stats: data.stats,
          comparison: data.comparison,
        ),
      ],
    );
  }

  static String _bucketName(SeriesBucket bucket) => switch (bucket) {
    SeriesBucket.day => 'jour',
    SeriesBucket.week => 'semaine',
    SeriesBucket.month => 'mois',
  };
}

/// [child] dimmed and inactive while [loading], under a thin progress bar
/// laid over its top edge (nothing moves). Without transition when the
/// system asks to reduce motion.
class _Switching extends StatelessWidget {
  const _Switching({required this.loading, required this.child});

  final bool loading;
  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.passthrough,
    children: [
      AnimatedOpacity(
        key: const Key('analysis-content'),
        opacity: loading ? 0.45 : 1,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 200),
        child: IgnorePointer(ignoring: loading, child: child),
      ),
      if (loading)
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Semantics(
            label: 'Chargement de la période',
            child: LinearProgressIndicator(
              key: const Key('analysis-loading'),
              minHeight: 3,
              color: EvolupColors.of(context).accent,
              backgroundColor: Colors.transparent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
    ],
  );
}

class _Figure extends StatelessWidget {
  const _Figure({
    required this.label,
    required this.value,
    this.detail,
    super.key,
  });

  final String label;
  final String value;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final colors = EvolupColors.of(context);
    final textTheme = Theme.of(context).textTheme;
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      radius: 18,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.bodySmall?.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (detail != null)
            Text(
              detail!,
              style: textTheme.bodySmall?.copyWith(color: colors.textSecondary),
            ),
        ],
      ),
    );
  }
}

/// Comparison with the previous period and trend, each only when the data
/// allows it.
class _Insights extends StatelessWidget {
  const _Insights({
    required this.definition,
    required this.period,
    required this.stats,
    required this.comparison,
  });

  final MetricDefinition definition;
  final StatsPeriod period;
  final MetricStatistics stats;
  final PeriodComparison? comparison;

  @override
  Widget build(BuildContext context) {
    final colors = EvolupColors.of(context);
    final textTheme = Theme.of(context).textTheme;
    final lines = <Widget>[];
    final comparison = this.comparison;
    if (comparison != null) {
      final days = period.days!;
      String text;
      if (comparison.comparable && comparison.difference != null) {
        final percent = comparison.percentChange;
        text =
            '${formatDifference(definition, comparison.difference!)}'
            '${percent == null ? '' : ' (${percent >= 0 ? '+' : '−'}${formatNumber(percent.abs(), decimals: 1)} %)'}'
            ' par rapport aux $days jours précédents '
            '(${daysLabel(comparison.reference.daysCount)} contre '
            '${comparison.compared.daysCount}).';
        if (definition.recordDirection == RecordDirection.lower) {
          text += ' Pour cet indicateur, une baisse est une amélioration.';
        }
      } else {
        text =
            'Pas assez de données pour comparer avec les $days jours '
            'précédents : au moins ${comparison.minDays} journées sont '
            'nécessaires sur chaque période (actuellement '
            '${comparison.reference.daysCount} et '
            '${comparison.compared.daysCount}).';
      }
      lines.add(
        _InsightLine(
          key: const Key('insight-comparison'),
          icon: Icons.compare_arrows_rounded,
          text: text,
        ),
      );
    }
    final trend = stats.trend;
    if (trend != null) {
      lines.add(
        _InsightLine(
          key: const Key('insight-trend'),
          icon: Icons.trending_flat_rounded,
          text:
              'Tendance : ${formatDifference(definition, trend.slopePerDay * 7)}'
              ' par semaine (ajustement linéaire sur '
              '${daysLabel(trend.points)}). Indication à interpréter avec '
              'prudence.',
        ),
      );
    } else {
      lines.add(
        _InsightLine(
          key: const Key('insight-trend-missing'),
          icon: Icons.info_outline_rounded,
          text:
              'La tendance est calculée à partir de 5 journées enregistrées '
              'sur la période (${stats.period.daysCount} pour l’instant).',
        ),
      );
    }
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Évolution',
            style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          ...lines,
          Text(
            aggregationExplanation(definition),
            style: textTheme.bodySmall?.copyWith(color: colors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _InsightLine extends StatelessWidget {
  const _InsightLine({required this.icon, required this.text, super.key});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: EvolupColors.of(context).accent),
        const SizedBox(width: 10),
        Expanded(child: Text(text)),
      ],
    ),
  );
}
