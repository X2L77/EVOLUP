import '../../data/metrics/metric_models.dart';

/// How several entries of the same day are combined, in plain French.
String aggregationExplanation(MetricDefinition metric) =>
    switch (metric.aggregation) {
      MetricAggregation.average =>
        'Plusieurs saisies le même jour sont fusionnées : EVOLUP garde leur '
            'total et leur nombre, et affiche leur moyenne.',
      MetricAggregation.sum => 'Les saisies d’un même jour sont additionnées.',
      MetricAggregation.max => 'La valeur la plus haute du jour est retenue.',
      MetricAggregation.min => 'La valeur la plus basse du jour est retenue.',
      MetricAggregation.last =>
        'La dernière valeur saisie du jour est retenue.',
    };

const duplicateRule =
    'Une valeur identique déjà saisie le même jour n’est pas comptée deux '
    'fois.';

/// "1 saisie", "3 saisies".
String entriesLabel(int count) => '$count saisie${count > 1 ? 's' : ''}';

/// "1 journée", "12 journées".
String daysLabel(int count) => '$count journée${count > 1 ? 's' : ''}';

String recordLabel(MetricDefinition metric) =>
    metric.recordDirection == RecordDirection.lower
    ? 'Meilleure saisie (la plus basse)'
    : 'Meilleure saisie';
