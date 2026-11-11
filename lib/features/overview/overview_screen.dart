import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/evolup_logo.dart';
import '../../app/format/dates.dart';
import '../../app/session/app_session.dart';
import '../../app/session/revision_reload.dart';
import '../../app/shell/app_destination.dart';
import '../../app/widgets/evolup_background.dart';
import '../../app/widgets/glass_card.dart';
import '../../app/widgets/state_views.dart';
import '../../data/data_error.dart';
import '../../data/metrics/metric_models.dart';
import '../../data/metrics/metric_values.dart';
import '../../theme/evolup_theme.dart';
import '../metrics/metric_navigation.dart';
import '../metrics/metric_texts.dart';
import '../metrics/widgets/metric_tile.dart';

/// Home page: a summary of what is recorded, favourite and tracked metrics
/// with their latest value and the last 30 days compared with the 30 before
/// (only when both have enough days), and shortcuts. Everything shown comes
/// from the user's data; no score, no sample.
class OverviewScreen extends StatefulWidget {
  const OverviewScreen({super.key});

  @override
  State<OverviewScreen> createState() => _OverviewScreenState();
}

class _OverviewScreenState extends State<OverviewScreen> with RevisionReload {
  Overview? _overview;
  Object? _error;
  int _request = 0;

  @override
  Future<void> reload() async {
    final request = ++_request;
    try {
      final overview = await metrics.repository.loadOverview();
      if (!mounted || request != _request) return;
      setState(() {
        _overview = overview;
        _error = null;
      });
    } on Object catch (error) {
      if (!mounted || request != _request) return;
      setState(() => _error = error);
    }
  }

  String? _comparison(MetricDefinition d, OverviewMetric m) {
    if (m.recent.daysCount == 0) return null;
    final recent = m.recent.value;
    if (!m.comparable || recent == null || m.previous.value == null) {
      return '30 derniers jours : ${daysLabel(m.recent.daysCount)} · pas '
          'assez de données pour comparer';
    }
    final delta = recent - m.previous.value!;
    return '30 derniers jours : '
        '${formatValue(d, recent, aggregated: true)} '
        '(${d.aggregation.label.toLowerCase()}), '
        '${formatDifference(d, delta)} par rapport aux 30 jours précédents';
  }

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.of(context);
    final colors = EvolupColors.of(context);
    final textTheme = Theme.of(context).textTheme;
    final name = session.profile.profile.displayName;
    final overview = _overview;
    return EvolupBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              EvolupLogo(size: 28),
              SizedBox(width: 12),
              Flexible(
                child: Text('Vue d’ensemble', overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
        ),
        body: RefreshIndicator(
          onRefresh: reload,
          child: PageBody(
            children: [
              Text(
                name == null ? 'Bonjour' : 'Bonjour, $name',
                style: textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Vos données, leur évolution, au même endroit.',
                style: TextStyle(color: colors.textSecondary),
              ),
              const SizedBox(height: 16),
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
      ),
    );
  }

  List<Widget> _content(
    BuildContext context,
    SignedInSession session,
    Overview overview,
  ) {
    final active = [
      for (final m in overview.metrics)
        if (m.isActive)
          if (metrics.definition(m.metricCatalogId) case final d?) (m, d),
    ];
    if (active.isEmpty) {
      return [
        EmptyState(
          key: const Key('overview-empty'),
          icon: Icons.dataset_outlined,
          title: 'Choisissez vos premiers indicateurs',
          message:
              'EVOLUP suit uniquement ce que vous choisissez : tractions, '
              'sommeil, concentration, lecture… Ajoutez des indicateurs depuis '
              'le catalogue, puis enregistrez vos valeurs.',
          action: FilledButton(
            key: const Key('overview-browse'),
            onPressed: () => session.show(context, AppDestination.data),
            child: const Text('Parcourir le catalogue'),
          ),
        ),
        const SizedBox(height: 14),
        _PolomixCard(session: session),
      ];
    }
    final favorites = [
      for (final e in active)
        if (e.$1.isFavorite) e,
    ];
    final others = [
      for (final e in active)
        if (!e.$1.isFavorite) e,
    ];

    Widget tile((OverviewMetric, MetricDefinition) entry) {
      final (m, d) = entry;
      final tracked = metrics.trackedById(m.trackedMetricId);
      return MetricTile(
        key: Key('overview-${d.slug}'),
        definition: d,
        categoryName: metrics.category(d.categoryId)?.name ?? '',
        latest: m.latest,
        today: overview.today,
        favorite: m.isFavorite,
        comparisonText: m.latest == null
            ? 'Aucune valeur enregistrée'
            : _comparison(d, m),
        onTap: tracked == null
            ? null
            : () => unawaited(openMetricDetail(context, tracked)),
        trailing: tracked == null || !d.isActive
            ? null
            : IconButton(
                tooltip: 'Saisir une valeur',
                icon: Icon(
                  Icons.add_circle_outline_rounded,
                  color: EvolupColors.of(context).accent,
                ),
                onPressed: () => unawaited(
                  openEntryForm(context, definition: d, tracked: tracked),
                ),
              ),
      );
    }

    return [
      _Summary(overview: overview, activeCount: active.length),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              key: const Key('overview-record'),
              onPressed: () => unawaited(pickMetricAndEnter(context)),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Saisir'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton.icon(
              key: const Key('overview-stats'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
              onPressed: () => session.show(context, AppDestination.stats),
              icon: const Icon(Icons.insights_rounded),
              label: const Text('Statistiques'),
            ),
          ),
        ],
      ),
      if (favorites.isNotEmpty) ...[
        const SectionHeader('Favoris'),
        for (final e in favorites) tile(e),
      ],
      SectionHeader(
        favorites.isEmpty ? 'Mes indicateurs' : 'Autres indicateurs',
      ),
      if (others.isEmpty)
        Text(
          'Tous vos indicateurs sont en favoris.',
          style: TextStyle(color: EvolupColors.of(context).textSecondary),
        ),
      for (final e in others) tile(e),
      const SizedBox(height: 14),
      _PolomixCard(session: session),
    ];
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.overview, required this.activeCount});

  final Overview overview;
  final int activeCount;

  @override
  Widget build(BuildContext context) {
    final colors = EvolupColors.of(context);
    final textTheme = Theme.of(context).textTheme;
    Widget figure(String value, String label, Key key) => Expanded(
      child: Column(
        key: key,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            label,
            style: textTheme.bodySmall?.copyWith(color: colors.textSecondary),
          ),
        ],
      ),
    );
    final first = overview.firstDate;
    return GlassCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              figure(
                '$activeCount',
                pluralize(
                  activeCount,
                  'indicateur suivi',
                  'indicateurs suivis',
                ),
                const Key('summary-tracked'),
              ),
              figure(
                '${overview.daysRecorded}',
                pluralize(
                  overview.daysRecorded,
                  'journée renseignée',
                  'journées renseignées',
                ),
                const Key('summary-days'),
              ),
              figure(
                '${overview.entriesCount}',
                pluralize(overview.entriesCount, 'saisie', 'saisies'),
                const Key('summary-entries'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            first == null
                ? 'Aucune valeur enregistrée pour l’instant.'
                : 'Données depuis le ${formatDate(first)}.',
            style: textTheme.bodySmall?.copyWith(color: colors.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// Shortcut to Polomix. EVOLUP keeps no Polomix message outside the chat:
/// nothing is shown here as if it were advice from the coach.
class _PolomixCard extends StatelessWidget {
  const _PolomixCard({required this.session});

  final SignedInSession session;

  @override
  Widget build(BuildContext context) {
    final colors = EvolupColors.of(context);
    final available = session.coach != null;
    return GlassCard(
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          Icon(Icons.forum_rounded, color: colors.accent),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Polomix, votre analyste',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  available
                      ? 'Posez une question sur vos données, ou dites ce que '
                            'vous venez de faire pour préparer la saisie.'
                      : 'Polomix n’est pas joignable : la connexion au '
                            'serveur n’est pas configurée.',
                  style: TextStyle(color: colors.textSecondary),
                ),
              ],
            ),
          ),
          if (available)
            IconButton(
              key: const Key('overview-polomix'),
              tooltip: 'Ouvrir Polomix',
              icon: const Icon(Icons.arrow_forward_rounded),
              onPressed: () => session.show(context, AppDestination.polomix),
            ),
        ],
      ),
    );
  }
}
