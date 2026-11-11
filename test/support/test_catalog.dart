import 'package:my_training/data/metrics/metric_models.dart';

/// Part of the seed catalog (supabase/migrations/20261109100200), with one
/// retired metric. Tests never read the real database.
const testCategories = [
  MetricCategory(id: 1, slug: 'sport', name: 'Sport', sortOrder: 10),
  MetricCategory(
    id: 2,
    slug: 'concentration',
    name: 'Concentration',
    sortOrder: 20,
  ),
  MetricCategory(id: 4, slug: 'sommeil', name: 'Sommeil', sortOrder: 40),
  MetricCategory(
    id: 7,
    slug: 'developpement_personnel',
    name: 'Développement personnel',
    sortOrder: 70,
  ),
];

const tractions = MetricDefinition(
  id: 1,
  slug: 'tractions',
  categoryId: 1,
  name: 'Tractions',
  description: 'Nombre de répétitions d’une série de tractions.',
  valueKind: MetricValueKind.integer,
  storageUnit: 'repetition',
  unitLabel: 'rép.',
  aggregation: MetricAggregation.average,
  recordDirection: RecordDirection.higher,
  minValue: 0,
  maxValue: 500,
  keywords: ['traction', 'tractions', 'pull-up'],
  sortOrder: 10,
);

const pompes = MetricDefinition(
  id: 2,
  slug: 'pompes',
  categoryId: 1,
  name: 'Pompes',
  description: 'Nombre de répétitions d’une série de pompes.',
  valueKind: MetricValueKind.integer,
  storageUnit: 'repetition',
  unitLabel: 'rép.',
  aggregation: MetricAggregation.average,
  recordDirection: RecordDirection.higher,
  minValue: 0,
  maxValue: 1000,
  keywords: ['pompe', 'pompes'],
  sortOrder: 20,
);

const courseDistance = MetricDefinition(
  id: 3,
  slug: 'course_distance',
  categoryId: 1,
  name: 'Course — distance',
  description: 'Distance parcourue en courant.',
  valueKind: MetricValueKind.decimal,
  storageUnit: 'meter',
  unitLabel: 'km',
  displayFactor: 1000,
  displayDecimals: 2,
  aggregation: MetricAggregation.sum,
  recordDirection: RecordDirection.higher,
  minValue: 10,
  maxValue: 300000,
  dailySumMax: 500000,
  sortOrder: 30,
);

const course5km = MetricDefinition(
  id: 4,
  slug: 'course_5km',
  categoryId: 1,
  name: 'Course — temps sur 5 km',
  description: 'Temps réalisé sur 5 km.',
  valueKind: MetricValueKind.duration,
  storageUnit: 'second',
  unitLabel: 'temps',
  aggregation: MetricAggregation.min,
  recordDirection: RecordDirection.lower,
  minValue: 600,
  maxValue: 10800,
  durationFields: [DurationField.minutes, DurationField.seconds],
  sortOrder: 40,
);

const concentration = MetricDefinition(
  id: 5,
  slug: 'concentration_duree',
  categoryId: 2,
  name: 'Temps de concentration',
  description: 'Temps de travail concentré.',
  valueKind: MetricValueKind.duration,
  storageUnit: 'second',
  unitLabel: 'durée',
  aggregation: MetricAggregation.sum,
  minValue: 60,
  maxValue: 57600,
  dailySumMax: 86400,
  sortOrder: 10,
);

const sommeil = MetricDefinition(
  id: 8,
  slug: 'sommeil_duree',
  categoryId: 4,
  name: 'Durée de sommeil',
  description: 'Temps de sommeil.',
  valueKind: MetricValueKind.duration,
  storageUnit: 'second',
  unitLabel: 'durée',
  aggregation: MetricAggregation.sum,
  minValue: 60,
  maxValue: 86400,
  dailySumMax: 86400,
  keywords: ['sommeil', 'dormi'],
  sortOrder: 10,
);

const humeur = MetricDefinition(
  id: 16,
  slug: 'humeur',
  categoryId: 7,
  name: 'Humeur',
  description: 'Note de 1 à 10 de votre humeur.',
  valueKind: MetricValueKind.score,
  storageUnit: 'point',
  unitLabel: '/10',
  aggregation: MetricAggregation.average,
  minValue: 1,
  maxValue: 10,
  keywords: ['humeur', 'moral'],
  sortOrder: 20,
);

/// Retired from the catalog: readable, not trackable.
const gainage = MetricDefinition(
  id: 99,
  slug: 'gainage',
  categoryId: 1,
  name: 'Gainage',
  description: 'Ancien indicateur.',
  valueKind: MetricValueKind.duration,
  storageUnit: 'second',
  unitLabel: 'durée',
  aggregation: MetricAggregation.sum,
  minValue: 1,
  maxValue: 3600,
  isActive: false,
  sortOrder: 90,
);

const testCatalog = [
  tractions,
  pompes,
  courseDistance,
  course5km,
  concentration,
  sommeil,
  humeur,
  gainage,
];
