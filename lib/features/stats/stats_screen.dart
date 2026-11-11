import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/session/app_session.dart';
import '../../app/session/revision_reload.dart';
import '../../app/shell/app_destination.dart';
import '../../app/widgets/evolup_background.dart';
import '../../app/widgets/glass_card.dart';
import '../../app/widgets/labeled_dropdown.dart';
import '../../app/widgets/state_views.dart';
import '../../data/data_error.dart';
import '../../data/local_date.dart';
import '../../data/metrics/metric_models.dart';
import '../../theme/evolup_theme.dart';
import '../metrics/metric_navigation.dart';
import 'widgets/metric_analysis.dart';
import 'widgets/metric_chart.dart';
import 'widgets/period_selector.dart';

/// « Statistiques »: analysis of one metric with any period and grouping,
/// and its chart side by side with a second metric over the same days.
/// Only metrics with recorded days are offered.
class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> with RevisionReload {
  Overview? _overview;
  Object? _error;
  String? _selectedId;
  String? _secondId;
  StatsPeriod _period = StatsPeriod.days90;
  SeriesBucket? _bucket;

  @override
  Future<void> reload() async {
    try {
      final overview = await metrics.repository.loadOverview();
      if (!mounted) return;
      setState(() {
        _overview = overview;
        _error = null;
      });
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.of(context);
    final overview = _overview;
    return EvolupBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(title: const Text('Statistiques')),
        body: PageBody(
          children: [
            if (overview == null && _error == null)
              const LoadingView()
            else if (overview == null)
              ErrorView(
                message: dataErrorMessage(_error!),
                onRetry: () => unawaited(reload()),
              )
            else
              ..._content(context, session, overview),
            const SizedBox(height: 90),
          ],
        ),
      ),
    );
  }

  List<Widget> _content(
    BuildContext context,
    SignedInSession session,
    Overview overview,
  ) {
    final withData = [
      for (final m in overview.metrics)
        if (m.daysCount > 0)
          if (metrics.trackedById(m.trackedMetricId) case final t?)
            if (metrics.definition(t.metricCatalogId) case final d?) (m, t, d),
    ];
    if (withData.isEmpty) {
      return [
        EmptyState(
          key: const Key('stats-empty'),
          icon: Icons.insights_outlined,
          title: 'Pas encore de statistiques',
          message:
              'Les graphiques et les analyses apparaissent dès que vous avez '
              'enregistré des valeurs. Rien n’est affiché sans données '
              'réelles.',
          action: FilledButton(
            onPressed: () => metrics.activeTracked.isEmpty
                ? session.show(context, AppDestination.data)
                : unawaited(pickMetricAndEnter(context)),
            child: Text(
              metrics.activeTracked.isEmpty
                  ? 'Choisir des indicateurs'
                  : 'Saisir une valeur',
            ),
          ),
        ),
      ];
    }
    final selected =
        withData.where((e) => e.$2.id == _selectedId).firstOrNull ??
        withData.first;
    final second = withData
        .where((e) => e.$2.id == _secondId && e.$2.id != selected.$2.id)
        .firstOrNull;
    final today = LocalDate.today();
    final firstDates = [
      selected.$1.firstDate,
      second?.$1.firstDate,
    ].whereType<LocalDate>().toList()..sort();
    final firstDate = firstDates.firstOrNull;
    final (from, to) = _period.range(today, firstDate);

    DropdownMenuItem<String> item(
      (OverviewMetric, TrackedMetric, MetricDefinition) e,
    ) => DropdownMenuItem(
      value: e.$2.id,
      child: Text(
        '${e.$3.name} · ${metrics.category(e.$3.categoryId)?.name ?? ''}',
        overflow: TextOverflow.ellipsis,
      ),
    );

    return [
      LabeledDropdown<String>(
        key: const Key('stats-metric'),
        label: 'Indicateur',
        value: selected.$2.id,
        items: [for (final e in withData) item(e)],
        onChanged: (id) => setState(() => _selectedId = id),
      ),
      const SizedBox(height: 12),
      PeriodSelector(
        value: _period,
        onChanged: (value) => setState(() => _period = value),
      ),
      const SizedBox(height: 8),
      BucketSelector(
        value: _bucket,
        onChanged: (value) => setState(() => _bucket = value),
      ),
      const SizedBox(height: 14),
      MetricAnalysis(
        key: ValueKey('analysis-${selected.$2.id}'),
        tracked: selected.$2,
        definition: selected.$3,
        period: _period,
        firstDate: firstDate,
        bucket: _bucket,
        today: today,
      ),
      TextButton.icon(
        onPressed: () => unawaited(openMetricDetail(context, selected.$2)),
        icon: const Icon(Icons.open_in_new_rounded),
        label: const Text('Fiche et historique de l’indicateur'),
      ),
      const SectionHeader('Comparer avec un autre indicateur'),
      LabeledDropdown<String?>(
        key: const Key('stats-second'),
        label: 'Second indicateur',
        value: second?.$2.id,
        items: [
          const DropdownMenuItem<String?>(value: null, child: Text('Aucun')),
          for (final e in withData)
            if (e.$2.id != selected.$2.id)
              DropdownMenuItem<String?>(
                value: e.$2.id,
                child: Text(
                  '${e.$3.name} · ${metrics.category(e.$3.categoryId)?.name ?? ''}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
        ],
        onChanged: (id) => setState(() => _secondId = id),
      ),
      if (second != null) ...[
        const SizedBox(height: 12),
        _ComparisonCharts(
          key: ValueKey(
            'compare-${selected.$2.id}-${second.$2.id}-$_period-$_bucket',
          ),
          first: (selected.$2, selected.$3),
          second: (second.$2, second.$3),
          from: from,
          to: to,
          bucket: _bucket,
        ),
      ],
    ];
  }
}

/// Both metrics over the same days and the same grouping, one chart each
/// (their units differ). A shared evolution is not a cause-and-effect link.
class _ComparisonCharts extends StatefulWidget {
  const _ComparisonCharts({
    required this.first,
    required this.second,
    required this.from,
    required this.to,
    required this.bucket,
    super.key,
  });

  final (TrackedMetric, MetricDefinition) first;
  final (TrackedMetric, MetricDefinition) second;
  final LocalDate from;
  final LocalDate to;
  final SeriesBucket? bucket;

  @override
  State<_ComparisonCharts> createState() => _ComparisonChartsState();
}

class _ComparisonChartsState extends State<_ComparisonCharts>
    with RevisionReload {
  (MetricSeries, MetricSeries)? _series;
  Object? _error;

  @override
  Future<void> reload() async {
    try {
      final repository = metrics.repository;
      // Same grouping for both: the first series decides it in 'auto'.
      final first = await repository.loadSeries(
        widget.first.$1.id,
        widget.from,
        widget.to,
        bucket: widget.bucket,
      );
      final second = await repository.loadSeries(
        widget.second.$1.id,
        widget.from,
        widget.to,
        bucket: widget.bucket ?? first.bucket,
      );
      if (mounted) setState(() => _series = (first, second));
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final series = _series;
    if (series == null) {
      return _error == null
          ? const LoadingView()
          : ErrorView(
              message: dataErrorMessage(_error!),
              onRetry: () => unawaited(reload()),
            );
    }
    final textTheme = Theme.of(context).textTheme;
    Widget chart(MetricDefinition d, MetricSeries s, bool secondary) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          d.name,
          style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        if (s.points.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Text('Aucune donnée sur cette période.'),
          )
        else
          MetricChart(
            definition: d,
            series: s,
            from: widget.from,
            to: widget.to,
            height: 160,
            secondary: secondary,
          ),
      ],
    );
    return GlassCard(
      key: const Key('stats-comparison'),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          chart(widget.first.$2, series.$1, false),
          const SizedBox(height: 18),
          chart(widget.second.$2, series.$2, true),
          const SizedBox(height: 12),
          Text(
            'Mêmes jours, même regroupement. Deux indicateurs qui évoluent '
            'ensemble ne prouvent pas que l’un cause l’autre.',
            style: textTheme.bodySmall?.copyWith(
              color: EvolupColors.of(context).textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
