// Shared fakes of the tests: a catalog mirroring the seed migration and an
// in-memory CoachData. No network, no key, no database.

import type { CatalogMetric } from './catalog.ts';
import type {
  CoachData,
  Day,
  Overview,
  Point,
  Profile,
  Statistics,
  Tracked,
} from './data.ts';

function metric(
  id: number,
  slug: string,
  name: string,
  category: string,
  value_kind: CatalogMetric['value_kind'],
  extra: Partial<CatalogMetric>,
): CatalogMetric {
  return {
    id,
    slug,
    name,
    category,
    value_kind,
    storage_unit: 'repetition',
    storage_scale: 0,
    unit_label: 'rép.',
    display_factor: 1,
    display_decimals: 0,
    aggregation: 'average',
    record_direction: null,
    min_value: null,
    max_value: null,
    keywords: [],
    duration_fields: ['hours', 'minutes'],
    is_active: true,
    ...extra,
  };
}

const duration = {
  storage_unit: 'second',
  unit_label: 'durée',
  aggregation: 'sum' as const,
  min_value: 60,
  max_value: 86400,
};
const score = {
  storage_unit: 'point',
  unit_label: '/10',
  min_value: 1,
  max_value: 10,
};

export const CATALOG: CatalogMetric[] = [
  metric(1, 'tractions', 'Tractions', 'Sport', 'integer', {
    record_direction: 'higher',
    min_value: 0,
    max_value: 500,
    keywords: ['traction', 'tractions', 'pull-up', 'pullup'],
  }),
  metric(2, 'pompes', 'Pompes', 'Sport', 'integer', {
    record_direction: 'higher',
    min_value: 0,
    max_value: 1000,
    keywords: ['pompe', 'pompes', 'push-up'],
  }),
  metric(3, 'course_distance', 'Course — distance', 'Sport', 'decimal', {
    storage_unit: 'meter',
    unit_label: 'km',
    display_factor: 1000,
    display_decimals: 2,
    aggregation: 'sum',
    record_direction: 'higher',
    min_value: 10,
    max_value: 300000,
    keywords: ['course', 'couru', 'courir', 'running', 'footing', 'distance'],
  }),
  metric(4, 'course_5km', 'Course — temps sur 5 km', 'Sport', 'duration', {
    ...duration,
    aggregation: 'min',
    record_direction: 'lower',
    min_value: 600,
    max_value: 10800,
    duration_fields: ['minutes', 'seconds'],
    keywords: ['5 km', '5km'],
  }),
  metric(
    5,
    'concentration_duree',
    'Temps de concentration',
    'Concentration',
    'duration',
    {
      ...duration,
      max_value: 57600,
      keywords: ['concentration', 'concentre', 'focus', 'deep work'],
    },
  ),
  metric(
    6,
    'concentration_qualite',
    'Qualité de concentration',
    'Concentration',
    'score',
    {
      ...score,
      keywords: ['qualite de concentration'],
    },
  ),
  metric(8, 'sommeil_duree', 'Durée de sommeil', 'Sommeil', 'duration', {
    ...duration,
    keywords: ['sommeil', 'dormi', 'dormir', 'sieste', 'nuit'],
  }),
  metric(9, 'sommeil_qualite', 'Qualité du sommeil', 'Sommeil', 'score', {
    ...score,
    keywords: ['qualite du sommeil', 'qualite de sommeil'],
  }),
  metric(10, 'lecture_duree', 'Temps de lecture', 'Apprentissage', 'duration', {
    ...duration,
    keywords: ['lecture', 'lire', 'lu'],
  }),
  metric(11, 'pages_lues', 'Pages lues', 'Apprentissage', 'integer', {
    storage_unit: 'page',
    unit_label: 'pages',
    aggregation: 'sum',
    min_value: 1,
    max_value: 2000,
    keywords: ['page', 'pages'],
  }),
  metric(16, 'humeur', 'Humeur', 'Développement personnel', 'score', {
    ...score,
    keywords: ['humeur', 'moral'],
  }),
  metric(99, 'gainage', 'Gainage', 'Sport', 'duration', {
    ...duration,
    is_active: false,
    keywords: ['gainage', 'planche'],
  }),
];

export const TRACTIONS_STATS: Statistics = {
  period: { value: 9.25, days_count: 4, sample_count: 6 },
  all_time: {
    value: 8.5,
    days_count: 12,
    sample_count: 20,
    first_date: '2026-09-01',
    last_date: '2026-11-08',
  },
  latest: { local_date: '2026-11-08', value: 10, sample_count: 2 },
  record: { local_date: '2026-10-05', value: 14 },
  trend: null,
};

/** In-memory data of one user; records what was read. */
export class FakeData implements CoachData {
  reads: string[] = [];
  failCatalog = false;
  failProfile = false;

  constructor(
    public profileRow: Profile | null = {
      timezone: 'Europe/Paris',
      coach_data_access: true,
    },
    public trackedRows: Tracked[] = [
      { id: 'um-tractions', metric_catalog_id: 1, is_active: true },
      { id: 'um-sommeil', metric_catalog_id: 8, is_active: true },
    ],
  ) {}

  catalog() {
    this.reads.push('catalog');
    return this.failCatalog
      ? Promise.reject(new Error('down'))
      : Promise.resolve(CATALOG);
  }
  profile() {
    this.reads.push('profile');
    return this.failProfile
      ? Promise.reject(new Error('down'))
      : Promise.resolve(this.profileRow);
  }
  tracked() {
    this.reads.push('tracked');
    return Promise.resolve(this.trackedRows);
  }
  statistics(id: string) {
    this.reads.push(`statistics:${id}`);
    return Promise.resolve(id === 'um-tractions' ? TRACTIONS_STATS : null);
  }
  weeks(id: string): Promise<Point[]> {
    this.reads.push(`weeks:${id}`);
    return Promise.resolve(
      id === 'um-tractions'
        ? [{
          bucket_start: '2026-11-02',
          value: 9.5,
          sample_count: 4,
          days_count: 2,
        }]
        : [],
    );
  }
  recentDays(id: string): Promise<Day[]> {
    this.reads.push(`days:${id}`);
    return Promise.resolve(
      id === 'um-tractions'
        ? [{ local_date: '2026-11-08', daily_value: 10, sample_count: 2 }]
        : [],
    );
  }
  overview(): Promise<Overview> {
    this.reads.push('overview');
    return Promise.resolve({
      today: '2026-11-09',
      metrics: [
        {
          user_metric_id: 'um-tractions',
          metric_catalog_id: 1,
          is_active: true,
          days_count: 12,
          latest: { local_date: '2026-11-08', value: 10, sample_count: 2 },
          recent: { value: 9.25, days_count: 4 },
          previous: { value: null, days_count: 0 },
          comparable: false,
        },
        {
          user_metric_id: 'um-sommeil',
          metric_catalog_id: 8,
          is_active: true,
          days_count: 0,
          latest: null,
          recent: { value: null, days_count: 0 },
          previous: { value: null, days_count: 0 },
          comparable: false,
        },
      ],
    });
  }
}
