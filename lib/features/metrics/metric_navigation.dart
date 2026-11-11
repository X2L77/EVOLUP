import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/routes.dart';
import '../../app/session/app_session.dart';
import '../../data/data_error.dart';
import '../../data/metrics/metric_models.dart';
import '../entry/metric_entry_screen.dart';
import 'metric_detail_screen.dart';

Future<void> openMetricDetail(BuildContext context, TrackedMetric tracked) =>
    Navigator.of(context).push(
      evolupRoute<void>((_) => MetricDetailScreen(trackedMetricId: tracked.id)),
    );

/// Opens the entry form of a metric the user tracks and keeps active.
Future<EntryResult?> openEntryForm(
  BuildContext context, {
  required MetricDefinition definition,
  required TrackedMetric tracked,
  num? suggestedValue,
  bool fromPolomix = false,
}) => Navigator.of(context).push<EntryResult?>(
  evolupRoute<EntryResult?>(
    (_) => MetricEntryScreen(
      definition: definition,
      tracked: tracked,
      suggestedValue: suggestedValue,
      fromPolomix: fromPolomix,
    ),
    emphasized: fromPolomix,
  ),
);

/// Returns the active tracked metric for [definition]; when it is not
/// tracked (or was removed from the list), asks the user first. `null` when
/// the user declines or the change fails.
Future<TrackedMetric?> ensureTracked(
  BuildContext context,
  MetricDefinition definition,
) async {
  final metrics = SessionScope.read(context).metrics;
  final existing = metrics.trackedFor(definition.id);
  if (existing != null && existing.isActive) return existing;
  if (!definition.isActive) {
    _showError(context, dataFailureMessage(DataFailure.metricRetired));
    return null;
  }
  final reactivate = existing != null;
  final accepted = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      key: const Key('track-confirm'),
      title: Text(
        reactivate
            ? 'Réactiver « ${definition.name} » ?'
            : 'Suivre « ${definition.name} » ?',
      ),
      content: Text(
        reactivate
            ? 'Cet indicateur a été retiré de votre liste. Réactivez-le pour '
                  'enregistrer une nouvelle valeur ; son historique est '
                  'conservé.'
            : 'Cet indicateur ne fait pas encore partie de vos données. '
                  'Ajoutez-le pour pouvoir enregistrer une valeur.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Annuler'),
        ),
        FilledButton(
          key: const Key('track-confirm-accept'),
          style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(reactivate ? 'Réactiver' : 'Ajouter'),
        ),
      ],
    ),
  );
  if (accepted != true || !context.mounted) return null;
  try {
    return await metrics.track(definition);
  } on Object catch (error) {
    if (context.mounted) _showError(context, dataErrorMessage(error));
    return null;
  }
}

/// [ensureTracked], then the entry form.
Future<void> startEntry(
  BuildContext context,
  MetricDefinition definition, {
  num? suggestedValue,
  bool fromPolomix = false,
}) async {
  final tracked = await ensureTracked(context, definition);
  if (tracked == null || !context.mounted) return;
  await openEntryForm(
    context,
    definition: definition,
    tracked: tracked,
    suggestedValue: suggestedValue,
    fromPolomix: fromPolomix,
  );
}

/// Lets the user choose one of their active metrics, then opens its form.
Future<void> pickMetricAndEnter(BuildContext context) async {
  final metrics = SessionScope.read(context).metrics;
  final choices = [
    for (final tracked in metrics.activeTracked)
      if (metrics.definition(tracked.metricCatalogId) case final d?)
        if (d.isActive) (tracked, d),
  ];
  if (choices.isEmpty) {
    _showError(
      context,
      'Ajoutez d’abord un indicateur depuis « Mes données ».',
    );
    return;
  }
  final picked = await showModalBottomSheet<(TrackedMetric, MetricDefinition)>(
    context: context,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
              child: Text(
                'Que voulez-vous enregistrer ?',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            for (final (tracked, definition) in choices)
              ListTile(
                key: Key('pick-${definition.slug}'),
                title: Text(definition.name),
                subtitle: Text(
                  metrics.category(definition.categoryId)?.name ?? '',
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.of(context).pop((tracked, definition)),
              ),
          ],
        ),
      ),
    ),
  );
  if (picked == null || !context.mounted) return;
  unawaited(openEntryForm(context, definition: picked.$2, tracked: picked.$1));
}

void _showError(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}
