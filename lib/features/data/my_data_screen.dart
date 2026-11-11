import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/session/revision_reload.dart';
import '../../app/widgets/confirm_dialog.dart';
import '../../app/widgets/evolup_background.dart';
import '../../app/widgets/state_views.dart';
import '../../data/data_error.dart';
import '../../data/local_date.dart';
import '../../data/metrics/metric_models.dart';
import '../../data/metrics/metric_values.dart';
import '../../theme/evolup_theme.dart';
import '../metrics/metric_navigation.dart';
import '../metrics/metric_texts.dart';
import '../metrics/widgets/metric_tile.dart';
import 'metric_search.dart';

/// « Mes données »: the metrics the user tracks, the ones removed from the
/// list (history kept) and the EVOLUP catalog, with search and category
/// filters.
class MyDataScreen extends StatefulWidget {
  const MyDataScreen({super.key});

  @override
  State<MyDataScreen> createState() => _MyDataScreenState();
}

class _MyDataScreenState extends State<MyDataScreen> with RevisionReload {
  final _search = TextEditingController();
  int? _categoryId;
  Overview? _overview;

  @override
  Future<void> reload() async {
    try {
      final overview = await metrics.repository.loadOverview();
      if (mounted) setState(() => _overview = overview);
    } on Object {
      // Latest values are a convenience here; the lists stay usable.
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _visible(MetricDefinition definition) =>
      (_categoryId == null || definition.categoryId == _categoryId) &&
      matchesSearch(
        definition,
        metrics.category(definition.categoryId)?.name ?? '',
        _search.text,
      );

  Future<void> _track(MetricDefinition definition) async {
    try {
      await metrics.track(definition);
      if (mounted) {
        showMessage(context, '« ${definition.name} » ajouté à vos données.');
      }
    } on Object catch (error) {
      if (mounted) showMessage(context, dataErrorMessage(error));
    }
  }

  Future<void> _showDefinition(MetricDefinition definition) async {
    final colors = EvolupColors.of(context);
    final category = metrics.category(definition.categoryId);
    final track = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                definition.name,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                category?.name ?? '',
                style: TextStyle(color: colors.textSecondary),
              ),
              const SizedBox(height: 12),
              Text(definition.description),
              const SizedBox(height: 12),
              _Fact(
                'Unité',
                definition.isDuration
                    ? 'durée (heures, minutes, secondes)'
                    : definition.unitLabel,
              ),
              if (boundsHint(definition).isNotEmpty)
                _Fact('Valeurs acceptées', boundsHint(definition)),
              _Fact(
                'Plusieurs saisies par jour',
                aggregationExplanation(definition),
              ),
              _Fact(
                'Record',
                definition.hasRecord
                    ? recordLabel(definition)
                    : 'Pas de record pour cet indicateur.',
              ),
              const SizedBox(height: 16),
              FilledButton(
                key: const Key('catalog-track'),
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Suivre cet indicateur'),
              ),
            ],
          ),
        ),
      ),
    );
    if (track == true && mounted) await _track(definition);
  }

  @override
  Widget build(BuildContext context) {
    final colors = EvolupColors.of(context);
    final overview = _overview;
    final today = overview?.today ?? LocalDate.today();
    final active = [
      for (final t in metrics.activeTracked)
        if (metrics.definition(t.metricCatalogId) case final d?)
          if (_visible(d)) (t, d),
    ];
    final inactive = [
      for (final t in metrics.inactiveTracked)
        if (metrics.definition(t.metricCatalogId) case final d?)
          if (_visible(d)) (t, d),
    ];
    final catalog = [
      for (final d in metrics.untrackedActive)
        if (_visible(d)) d,
    ];
    final nothing = active.isEmpty && inactive.isEmpty && catalog.isEmpty;

    MetricTile trackedTile(TrackedMetric t, MetricDefinition d) => MetricTile(
      key: Key('tracked-${d.slug}'),
      definition: d,
      categoryName: metrics.category(d.categoryId)?.name ?? '',
      latest: overview?.metricFor(t.id)?.latest,
      today: today,
      favorite: t.isFavorite,
      status: t.isActive
          ? null
          : (d.isActive
                ? 'retiré, historique conservé'
                : 'retiré du catalogue'),
      onTap: () => unawaited(openMetricDetail(context, t)),
      trailing: t.isActive && d.isActive
          ? IconButton(
              key: Key('quick-entry-${d.slug}'),
              tooltip: 'Saisir une valeur',
              icon: Icon(
                Icons.add_circle_outline_rounded,
                color: colors.accent,
              ),
              onPressed: () =>
                  unawaited(openEntryForm(context, definition: d, tracked: t)),
            )
          : (!t.isActive && d.isActive
                ? TextButton(
                    key: Key('reactivate-${d.slug}'),
                    onPressed: () => unawaited(_track(d)),
                    child: const Text('Réactiver'),
                  )
                : null),
    );

    return EvolupBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(title: const Text('Mes données')),
        body: PageBody(
          children: [
            TextField(
              key: const Key('data-search'),
              controller: _search,
              onChanged: (_) => setState(() {}),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Rechercher un indicateur',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Effacer',
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => setState(_search.clear),
                      ),
              ),
            ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _CategoryChip(
                    label: 'Toutes',
                    selected: _categoryId == null,
                    onSelected: () => setState(() => _categoryId = null),
                  ),
                  for (final category in metrics.categories)
                    _CategoryChip(
                      key: Key('category-${category.slug}'),
                      label: category.name,
                      selected: _categoryId == category.id,
                      onSelected: () =>
                          setState(() => _categoryId = category.id),
                    ),
                ],
              ),
            ),
            if (nothing) ...[
              const SizedBox(height: 24),
              const EmptyState(
                icon: Icons.search_off_rounded,
                title: 'Aucun indicateur ne correspond',
                message: 'Modifiez la recherche ou la catégorie.',
              ),
            ],
            if (active.isNotEmpty) ...[
              const SectionHeader('Mes indicateurs'),
              for (final (t, d) in active) trackedTile(t, d),
            ] else if (metrics.activeTracked.isEmpty && !nothing) ...[
              const SizedBox(height: 16),
              const EmptyState(
                icon: Icons.dataset_outlined,
                title: 'Choisissez ce que vous voulez suivre',
                message:
                    'Ajoutez des indicateurs du catalogue EVOLUP ci-dessous : '
                    'sport, sommeil, concentration, apprentissage…',
              ),
            ],
            if (inactive.isNotEmpty) ...[
              const SectionHeader('Retirés de ma liste'),
              for (final (t, d) in inactive) trackedTile(t, d),
            ],
            if (catalog.isNotEmpty) ...[
              const SectionHeader('Catalogue EVOLUP'),
              for (final d in catalog)
                MetricTile(
                  key: Key('catalog-${d.slug}'),
                  definition: d,
                  categoryName: metrics.category(d.categoryId)?.name ?? '',
                  comparisonText: d.description,
                  onTap: () => unawaited(_showDefinition(d)),
                  trailing: TextButton(
                    key: Key('track-${d.slug}'),
                    onPressed: () => unawaited(_track(d)),
                    child: const Text('Suivre'),
                  ),
                ),
            ],
            const SizedBox(height: 90),
          ],
        ),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.selected,
    required this.onSelected,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: ChoiceChip(
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      onSelected: (_) => onSelected(),
    ),
  );
}

class _Fact extends StatelessWidget {
  const _Fact(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: EvolupColors.of(context).textSecondary,
          ),
        ),
        Text(value),
      ],
    ),
  );
}
