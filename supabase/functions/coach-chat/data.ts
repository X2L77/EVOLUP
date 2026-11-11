// Read-only access to the user's EVOLUP data for the coach context.
//
// The client carries the user's own session (RLS applies: only their rows)
// and the header `x-evolup-actor: polomix`, which the database write
// functions refuse (defence in depth). This module only selects and calls
// read functions; data_test.ts checks that it contains no write.

import { createClient } from '@supabase/supabase-js';
import { type CatalogMetric, catalogMetricFrom } from './catalog.ts';

export type Profile = { timezone: string; coach_data_access: boolean };
export type Tracked = {
  id: string;
  metric_catalog_id: number;
  is_active: boolean;
};
export type Summary = {
  value: number | null;
  per_day_average?: number | null;
  days_count: number;
  sample_count?: number;
  first_date?: string | null;
  last_date?: string | null;
};
export type Statistics = {
  period: Summary;
  all_time: Summary;
  latest: { local_date: string; value: number; sample_count: number } | null;
  record: { local_date: string; value: number } | null;
  trend: { slope_per_day: number; points: number } | null;
};
export type Point = {
  bucket_start: string;
  value: number;
  sample_count: number;
  days_count: number;
};
export type Day = {
  local_date: string;
  daily_value: number;
  sample_count: number;
};
export type OverviewMetric = {
  user_metric_id: string;
  metric_catalog_id: number;
  is_active: boolean;
  days_count: number;
  latest: { local_date: string; value: number; sample_count: number } | null;
  recent: Summary;
  previous: Summary;
  comparable: boolean;
};
export type Overview = { today: string; metrics: OverviewMetric[] };

export interface CoachData {
  catalog(): Promise<CatalogMetric[]>;
  profile(): Promise<Profile | null>;
  tracked(): Promise<Tracked[]>;
  statistics(id: string, from: string, to: string): Promise<Statistics | null>;
  weeks(id: string, from: string, to: string): Promise<Point[]>;
  recentDays(id: string, limit: number): Promise<Day[]>;
  overview(): Promise<Overview | null>;
}

export function createCoachData(
  url: string,
  publicKey: string,
  accessToken: string,
): CoachData {
  const client = createClient(url, publicKey, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: {
      headers: {
        Authorization: `Bearer ${accessToken}`,
        'x-evolup-actor': 'polomix',
      },
    },
  });
  const rows = <T>(result: { data: unknown; error: unknown }): T => {
    if (result.error) throw result.error;
    return result.data as T;
  };
  return {
    async catalog() {
      const data = rows<Record<string, unknown>[]>(
        await client
          .from('metric_catalog')
          .select(
            'id, slug, name, value_kind, storage_unit, storage_scale, ' +
              'unit_label, display_factor, display_decimals, aggregation, ' +
              'record_direction, min_value, max_value, form_config, keywords, ' +
              'is_active, metric_categories(name)',
          )
          .order('id'),
      );
      return data.map(catalogMetricFrom);
    },
    async profile() {
      return rows<Profile | null>(
        await client
          .from('profiles')
          .select('timezone, coach_data_access')
          .maybeSingle(),
      );
    },
    async tracked() {
      return rows<Tracked[]>(
        await client
          .from('user_metrics')
          .select('id, metric_catalog_id, is_active'),
      );
    },
    async statistics(id, from, to) {
      return rows<Statistics | null>(
        await client.rpc('get_metric_statistics', {
          p_user_metric_id: id,
          p_from: from,
          p_to: to,
        }),
      );
    },
    async weeks(id, from, to) {
      return rows<Point[]>(
        await client.rpc('get_metric_history', {
          p_user_metric_id: id,
          p_from: from,
          p_to: to,
          p_bucket: 'week',
        }),
      );
    },
    async recentDays(id, limit) {
      return rows<Day[]>(
        await client
          .from('metric_daily_values')
          .select('local_date, daily_value, sample_count')
          .eq('user_metric_id', id)
          .order('local_date', { ascending: false })
          .limit(limit),
      );
    },
    async overview() {
      return rows<Overview | null>(await client.rpc('get_overview'));
    },
  };
}
