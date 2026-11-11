import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/format/dates.dart';
import '../../app/session/revision_reload.dart';
import '../../app/widgets/confirm_dialog.dart';
import '../../app/widgets/evolup_page.dart';
import '../../app/widgets/glass_card.dart';
import '../../app/widgets/state_views.dart';
import '../../app/widgets/status_message.dart';
import '../../data/data_error.dart';
import '../../data/local_date.dart';
import '../../data/metrics/metric_models.dart';
import '../../data/metrics/metric_values.dart';
import '../../theme/evolup_theme.dart';
import '../stats/widgets/metric_analysis.dart';
import '../stats/widgets/period_selector.dart';
import 'metric_navigation.dart';
import 'metric_texts.dart';
import 'widgets/correct_day_dialog.dart';

/// Page of one tracked metric: definition, entry, statistics over a period
/// and the list of recorded days (each can be corrected or deleted).
/// Available for removed metrics too: their history stays readable.
class MetricDetailScreen extends StatefulWidget {
  const MetricDetailScreen({required this.trackedMetricId, super.key});

  final String trackedMetricId;

  @override
  State<MetricDetailScreen> createState() => _MetricDetailScreenState();
}

class _MetricDetailScreenState extends State<MetricDetailScreen>
    with RevisionReload {
  static const _pageSize = 30;

  StatsPeriod _period = StatsPeriod.days30;
  List<DailyValue> _days = const [];
  bool _hasMore = false;
  bool _loadingDays = true;
  bool _loadingMore = false;
  Object? _daysError;
  LocalDate? _firstDate;
  int _request = 0;

  @override
  Future<void> reload() async {
    final request = ++_request;
    final repository = metrics.repository;
    try {
      final results = await Future.wait<Object>([
        repository.loadDays(widget.trackedMetricId, limit: _pageSize),
        // Only for the first recorded day (start of « Tout »): the overview
        // shared by the pages, usually already loaded.
        metrics.loadOverview(),
      ]);
      if (!mounted || request != _request) return;
      final days = results[0] as List<DailyValue>;
      final overview = results[1] as Overview;
      setState(() {
        _days = days;
        _hasMore = days.length == _pageSize;
        _firstDate = overview.metricFor(widget.trackedMetricId)?.firstDate;
        _daysError = null;
        _loadingDays = false;
      });
    } on Object catch (error) {
      if (!mounted || request != _request) return;
      setState(() {
        _daysError = error;
        _loadingDays = false;
      });
    }
  }

  Future<void> _loadMore() async {
    setState(() => _loadingMore = true);
    try {
      final more = await metrics.repository.loadDays(
        widget.trackedMetricId,
        limit: _pageSize,
        offset: _days.length,
      );
      if (!mounted) return;
      setState(() {
        _days = [..._days, ...more];
        _hasMore = more.length == _pageSize;
      });
    } on Object catch (error) {
      if (mounted) showMessage(context, dataErrorMessage(error));
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _run(Future<void> Function() action, String done) async {
    try {
      await action();
      if (mounted) showMessage(context, done);
    } on Object catch (error) {
      if (mounted) showMessage(context, dataErrorMessage(error));
    }
  }

  Future<void> _dayActions(
    MetricDefinition definition,
    TrackedMetric tracked,
    DailyValue day,
  ) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                formatLongDate(day.localDate),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                '${formatValue(definition, day.value, aggregated: day.sampleCount > 1)}'
                ' · ${entriesLabel(day.sampleCount)}',
              ),
            ),
            ListTile(
              key: const Key('day-correct'),
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Corriger la valeur de la journée'),
              onTap: () => Navigator.of(context).pop('correct'),
            ),
            ListTile(
              key: const Key('day-delete'),
              leading: Icon(
                Icons.delete_outline_rounded,
                color: EvolupColors.of(context).error,
              ),
              title: const Text('Supprimer cette journée'),
              onTap: () => Navigator.of(context).pop('delete'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == 'correct') {
      final saved = await showCorrectDayDialog(
        context,
        definition: definition,
        tracked: tracked,
        day: day,
      );
      if (saved && mounted) showMessage(context, 'Journée corrigée.');
    } else if (choice == 'delete') {
      final confirmed = await confirmAction(
        context,
        title: 'Supprimer le ${formatDate(day.localDate)} ?',
        message:
            'La valeur de cette journée (${entriesLabel(day.sampleCount)}) '
            'sera définitivement supprimée.',
        confirmLabel: 'Supprimer',
        destructive: true,
      );
      if (confirmed && mounted) {
        await _run(
          () => metrics.deleteDay(tracked, day.localDate),
          'Journée supprimée.',
        );
      }
    }
  }

  Future<void> _menu(
    String action,
    MetricDefinition definition,
    TrackedMetric tracked,
  ) async {
    switch (action) {
      case 'deactivate':
        await _run(
          () => metrics.setActive(tracked, false),
          '« ${definition.name} » est retiré de votre liste. Son historique '
          'est conservé.',
        );
      case 'reactivate':
        await _run(
          () => metrics.setActive(tracked, true),
          '« ${definition.name} » est de nouveau suivi.',
        );
      case 'clear':
        final confirmed = await confirmAction(
          context,
          title: 'Effacer l’historique ?',
          message:
              'Toutes les journées enregistrées pour « ${definition.name} » '
              'seront définitivement supprimées. L’indicateur reste dans '
              'votre liste.',
          confirmLabel: 'Effacer',
          destructive: true,
        );
        if (confirmed && mounted) {
          await _run(
            () => metrics.deleteHistory(tracked),
            'Historique effacé.',
          );
        }
      case 'delete':
        final confirmed = await confirmAction(
          context,
          title: 'Supprimer « ${definition.name} » ?',
          message:
              'L’indicateur sera retiré de vos données avec tout son '
              'historique, définitivement. Pour seulement le masquer en '
              'gardant l’historique, choisissez plutôt « Retirer de ma '
              'liste ».',
          confirmLabel: 'Supprimer',
          destructive: true,
        );
        if (confirmed && mounted) {
          final navigator = Navigator.of(context);
          try {
            await metrics.deleteTracked(tracked);
            navigator.pop();
          } on Object catch (error) {
            if (mounted) showMessage(context, dataErrorMessage(error));
          }
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tracked = metrics.trackedById(widget.trackedMetricId);
    final definition = tracked == null
        ? null
        : metrics.definition(tracked.metricCatalogId);
    if (tracked == null || definition == null) {
      return const EvolupPage(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: EmptyState(
              icon: Icons.delete_outline_rounded,
              title: 'Indicateur supprimé',
              message: 'Cet indicateur ne fait plus partie de vos données.',
            ),
          ),
        ),
      );
    }
    final colors = EvolupColors.of(context);
    final textTheme = Theme.of(context).textTheme;
    final category = metrics.category(definition.categoryId);
    final canRecord = tracked.isActive && definition.isActive;
    return EvolupPage(
      actions: [
        IconButton(
          key: const Key('detail-favorite'),
          tooltip: tracked.isFavorite
              ? 'Retirer des favoris'
              : 'Ajouter aux favoris',
          icon: Icon(
            tracked.isFavorite
                ? Icons.star_rounded
                : Icons.star_outline_rounded,
            color: tracked.isFavorite ? colors.accent : null,
          ),
          onPressed: () => unawaited(
            _run(
              () => metrics.setFavorite(tracked, !tracked.isFavorite),
              tracked.isFavorite
                  ? 'Retiré des favoris.'
                  : 'Ajouté aux favoris.',
            ),
          ),
        ),
        PopupMenuButton<String>(
          key: const Key('detail-menu'),
          tooltip: 'Plus d’actions',
          onSelected: (action) => unawaited(_menu(action, definition, tracked)),
          itemBuilder: (context) => [
            if (tracked.isActive)
              const PopupMenuItem(
                value: 'deactivate',
                child: Text('Retirer de ma liste'),
              )
            else if (definition.isActive)
              const PopupMenuItem(
                value: 'reactivate',
                child: Text('Réactiver'),
              ),
            const PopupMenuItem(
              value: 'clear',
              child: Text('Effacer l’historique'),
            ),
            const PopupMenuItem(
              value: 'delete',
              child: Text('Supprimer l’indicateur et son historique'),
            ),
          ],
        ),
      ],
      body: PageBody(
        children: [
          Text(
            definition.name,
            key: const Key('detail-title'),
            style: textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            [
              category?.name ?? '',
              if (!definition.isActive)
                'retiré du catalogue'
              else if (!tracked.isActive)
                'retiré de ma liste',
            ].where((s) => s.isNotEmpty).join(' · '),
            style: TextStyle(color: colors.textSecondary),
          ),
          const SizedBox(height: 10),
          Text(definition.description),
          const SizedBox(height: 16),
          if (canRecord)
            FilledButton.icon(
              key: const Key('detail-record'),
              onPressed: () => unawaited(
                openEntryForm(
                  context,
                  definition: definition,
                  tracked: tracked,
                ),
              ),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Saisir une valeur'),
            )
          else
            StatusMessage(
              message: definition.isActive
                  ? 'Cet indicateur est retiré de votre liste : son '
                        'historique reste consultable. Réactivez-le depuis '
                        'le menu pour enregistrer une valeur.'
                  : dataFailureMessage(DataFailure.metricRetired),
            ),
          SectionHeader('Statistiques'),
          PeriodSelector(
            value: _period,
            onChanged: (value) => setState(() => _period = value),
          ),
          const SizedBox(height: 12),
          MetricAnalysis(
            tracked: tracked,
            definition: definition,
            period: _period,
            firstDate: _firstDate,
          ),
          SectionHeader('Journées enregistrées'),
          if (_loadingDays)
            const LoadingView()
          else if (_daysError != null)
            ErrorView(
              message: dataErrorMessage(_daysError!),
              onRetry: () => unawaited(reload()),
            )
          else if (_days.isEmpty)
            const EmptyState(
              icon: Icons.event_note_outlined,
              title: 'Aucune journée enregistrée',
              message:
                  'Les valeurs que vous validerez apparaîtront ici, une '
                  'ligne par journée.',
            )
          else
            GlassCard(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                children: [
                  for (final day in _days)
                    ListTile(
                      key: Key('day-${day.localDate.iso}'),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                      ),
                      title: Text(
                        formatValue(
                          definition,
                          day.value,
                          aggregated: day.sampleCount > 1,
                        ),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        '${formatLongDate(day.localDate)}'
                        '${day.sampleCount > 1 ? ' · ${definition.aggregation.dailyLabel} de ${entriesLabel(day.sampleCount)}' : ''}',
                      ),
                      trailing: const Icon(Icons.more_horiz_rounded),
                      onTap: () =>
                          unawaited(_dayActions(definition, tracked, day)),
                    ),
                ],
              ),
            ),
          if (_hasMore) ...[
            const SizedBox(height: 10),
            OutlinedButton(
              key: const Key('days-more'),
              onPressed: _loadingMore ? null : _loadMore,
              child: Text(
                _loadingMore ? 'Chargement…' : 'Afficher plus de journées',
              ),
            ),
          ],
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}
