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
    'Si la même valeur est déjà enregistrée ce jour-là, EVOLUP vous demande '
    's’il s’agit d’une nouvelle mesure avant de la compter.';

/// [singular] for 0 and 1, [plural] from 2 (French rule).
String pluralize(int count, String singular, String plural) =>
    count > 1 ? plural : singular;

/// "0 indicateur", "1 indicateur", "3 indicateurs".
String countLabel(int count, String singular, String plural) =>
    '$count ${pluralize(count, singular, plural)}';

/// "1 saisie", "3 saisies".
String entriesLabel(int count) => countLabel(count, 'saisie', 'saisies');

/// "1 journée", "12 journées".
String daysLabel(int count) => countLabel(count, 'journée', 'journées');

/// "1 indicateur", "3 indicateurs".
String metricsLabel(int count) =>
    countLabel(count, 'indicateur', 'indicateurs');

String recordLabel(MetricDefinition metric) =>
    metric.recordDirection == RecordDirection.lower
    ? 'Meilleure saisie (la plus basse)'
    : 'Meilleure saisie';
