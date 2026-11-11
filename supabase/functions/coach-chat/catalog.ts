// EVOLUP catalog metrics as read by the function, and their French
// formatting (same rules as lib/data/metrics/metric_values.dart).

export type CatalogMetric = {
  id: number;
  slug: string;
  name: string;
  category: string;
  value_kind: 'integer' | 'decimal' | 'duration' | 'score';
  storage_unit: string;
  storage_scale: number;
  unit_label: string;
  display_factor: number;
  display_decimals: number;
  aggregation: 'average' | 'sum' | 'max' | 'min' | 'last';
  record_direction: 'higher' | 'lower' | null;
  min_value: number | null;
  max_value: number | null;
  keywords: string[];
  duration_fields: string[];
  is_active: boolean;
};

/** Lowercase, without accents, apostrophes unified, single spaces. */
export function normalize(text: string): string {
  return text
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .toLowerCase()
    .replace(/[’`]/g, "'")
    .replace(/œ/g, 'oe')
    .replace(/\s+/g, ' ')
    .trim();
}

export const AGGREGATION_LABEL: Record<CatalogMetric['aggregation'], string> = {
  average: 'moyenne des saisies du jour',
  sum: 'total du jour',
  max: 'maximum du jour',
  min: 'minimum du jour',
  last: 'dernière valeur du jour',
};

function formatNumber(value: number, decimals: number): string {
  const fixed = Math.abs(value).toFixed(decimals);
  const [integer, fraction = ''] = fixed.split('.');
  const trimmed = fraction.replace(/0+$/, '');
  const grouped = integer.replace(/\B(?=(\d{3})+(?!\d))/g, ' ');
  const sign = value < 0 && Number(fixed) !== 0 ? '−' : '';
  return `${sign}${grouped}${trimmed ? `,${trimmed}` : ''}`;
}

function formatDuration(seconds: number, fields: string[]): string {
  const showSeconds = fields.includes('seconds');
  let total = Math.round(seconds);
  if (!showSeconds) total = Math.round(total / 60) * 60;
  const h = Math.floor(total / 3600);
  const m = Math.floor((total % 3600) / 60);
  const s = total % 60;
  const two = (n: number) => String(n).padStart(2, '0');
  if (showSeconds) {
    if (h > 0) return `${h} h ${two(m)} min ${two(s)} s`;
    if (m > 0) return s > 0 ? `${m} min ${two(s)} s` : `${m} min`;
    return `${s} s`;
  }
  if (h > 0) return m > 0 ? `${h} h ${two(m)}` : `${h} h`;
  return `${m} min`;
}

/** A stored value in the metric's display unit, e.g. "5,25 km", "7 h 30". */
export function formatValue(
  metric: CatalogMetric,
  stored: number,
  aggregated = false,
): string {
  if (metric.value_kind === 'duration') {
    return formatDuration(stored, metric.duration_fields);
  }
  const number = formatNumber(
    stored / metric.display_factor,
    metric.display_decimals + (aggregated ? 1 : 0),
  );
  return metric.unit_label.startsWith('/')
    ? `${number}${metric.unit_label}`
    : `${number} ${metric.unit_label}`;
}

/** Parses a catalog row selected by data.ts (numbers may be strings). */
export function catalogMetricFrom(row: Record<string, unknown>): CatalogMetric {
  const num = (v: unknown) =>
    v === null || v === undefined || v === '' ? null : Number(v);
  const config = row.form_config as Record<string, unknown> | null;
  const fields = Array.isArray(config?.duration_fields)
    ? (config!.duration_fields as unknown[]).filter((f) =>
      typeof f === 'string'
    ) as string[]
    : [];
  const category = row.metric_categories as Record<string, unknown> | null;
  return {
    id: Number(row.id),
    slug: String(row.slug),
    name: String(row.name),
    category: typeof category?.name === 'string' ? category.name : '',
    value_kind: row.value_kind as CatalogMetric['value_kind'],
    storage_unit: String(row.storage_unit),
    storage_scale: Number(row.storage_scale ?? 0),
    unit_label: String(row.unit_label ?? ''),
    display_factor: Number(row.display_factor ?? 1),
    display_decimals: Number(row.display_decimals ?? 0),
    aggregation: row.aggregation as CatalogMetric['aggregation'],
    record_direction: (row.record_direction ?? null) as
      | 'higher'
      | 'lower'
      | null,
    min_value: num(row.min_value),
    max_value: num(row.max_value),
    keywords: Array.isArray(row.keywords)
      ? (row.keywords as unknown[]).filter((k) => typeof k === 'string')
        .map((k) => normalize(k as string))
      : [],
    duration_fields: fields.length > 0 ? fields : ['hours', 'minutes'],
    is_active: row.is_active === true,
  };
}
