// Grouping by week and month, statistics, period comparison and overview
// (SPEC_PROJECT.md §6.7, §8 and §11).

import assert from 'node:assert/strict';
import { describe, test } from 'node:test';
import {
  createUser,
  expectPgError,
  inRollback,
  inSavepoint,
  record,
  startDatabase,
  track,
} from './harness.mjs';

const { pool } = await startDatabase();

async function history(c, userMetricId, from, to, bucket) {
  const { rows } = await c.query(
    'select * from public.get_metric_history($1, $2, $3, $4)',
    [userMetricId, from, to, bucket],
  );
  return rows;
}

describe('statistics', () => {
  test('weekly average is weighted by the number of entries', () =>
    inRollback(pool, async (c) => {
      const user = await createUser(c);
      const tractions = await track(c, user, 'tractions');
      // Monday 2026-11-02: 8 and 10 (sum 18, 2 entries); Tuesday: 3;
      // Sunday 2026-11-08 (same ISO week): 12.
      await record(c, tractions, 8, { date: '2026-11-02' });
      await record(c, tractions, 10, { date: '2026-11-02' });
      await record(c, tractions, 3, { date: '2026-11-03' });
      await record(c, tractions, 12, { date: '2026-11-08' });
      const weeks = await history(c, tractions, '2026-11-01', '2026-11-08', 'week');
      // 2026-11-01 is a Sunday: it belongs to the ISO week of 2026-10-26.
      assert.deepEqual(weeks.map((w) => w.bucket_start), ['2026-11-02']);
      // (18 + 3 + 12) / 4 = 8.25, not the mean of daily means (9 + 3 + 12) / 3.
      assert.equal(Number(weeks[0].value), 8.25);
      assert.equal(weeks[0].sample_count, '4');
      assert.equal(weeks[0].days_count, '3');
      assert.equal(weeks[0].bucket, 'week');
    }));

  test('monthly buckets and sum metrics', () =>
    inRollback(pool, async (c) => {
      const user = await createUser(c);
      const sleep = await track(c, user, 'sommeil_duree');
      const tractions = await track(c, user, 'tractions');
      await record(c, sleep, 25200, { unit: 'second', date: '2026-09-30' });
      await record(c, sleep, 27000, { unit: 'second', date: '2026-10-01' });
      await record(c, sleep, 1800, { unit: 'second', date: '2026-10-01' });
      await record(c, sleep, 28800, { unit: 'second', date: '2026-10-15' });
      const months = await history(c, sleep, '2026-09-01', '2026-10-31', 'month');
      assert.deepEqual(months.map((m) => [m.bucket_start, Number(m.value)]), [
        ['2026-09-01', 25200],
        ['2026-10-01', 57600],
      ]);
      await record(c, tractions, 10, { date: '2026-09-10' });
      await record(c, tractions, 20, { date: '2026-10-10' });
      await record(c, tractions, 4, { date: '2026-10-10' });
      await record(c, tractions, 6, { date: '2026-10-11' });
      const tm = await history(c, tractions, '2026-09-01', '2026-10-31', 'month');
      // October: (20 + 4 + 6) / 3 = 10.
      assert.deepEqual(tm.map((m) => Number(m.value)), [10, 10]);
    }));

  test("'auto' picks days, weeks or months from the period length", () =>
    inRollback(pool, async (c) => {
      const user = await createUser(c);
      const tractions = await track(c, user, 'tractions');
      await record(c, tractions, 10, { date: '2026-01-05' });
      const pick = async (from, to) =>
        (await history(c, tractions, from, to, 'auto'))[0]?.bucket;
      assert.equal(await pick('2026-01-01', '2026-03-31'), 'day');
      assert.equal(await pick('2025-06-01', '2026-06-01'), 'week');
      assert.equal(await pick('2020-01-01', '2026-06-01'), 'month');
      await inSavepoint(c, () =>
        expectPgError(history(c, tractions, '2020-01-01', '2026-01-01', 'day'), {
          message: 'too_many_points',
        }));
      await inSavepoint(c, () =>
        expectPgError(history(c, tractions, '2026-02-01', '2026-01-01', 'day'), {
          message: 'invalid_period',
        }));
      await inSavepoint(c, () =>
        expectPgError(history(c, tractions, '2026-01-01', '2026-02-01', 'year'), {
          message: 'invalid_bucket',
        }));
    }));

  test('statistics: period value, record, trend only from 5 days', () =>
    inRollback(pool, async (c) => {
      const user = await createUser(c);
      const tractions = await track(c, user, 'tractions');
      const stats = async () =>
        (await c.query('select public.get_metric_statistics($1, $2, $3) as s', [
          tractions, '2026-10-01', '2026-10-31',
        ])).rows[0].s;

      const empty = await stats();
      assert.equal(empty.period.days_count, 0);
      assert.equal(empty.period.value, null);
      assert.equal(empty.latest, null);
      assert.equal(empty.record, null);
      assert.equal(empty.trend, null);

      for (const [date, value] of [
        ['2026-10-01', 6], ['2026-10-02', 7], ['2026-10-03', 8], ['2026-10-04', 9],
      ]) {
        await record(c, tractions, value, { date });
      }
      assert.equal((await stats()).trend, null);
      await record(c, tractions, 10, { date: '2026-10-05' });
      await record(c, tractions, 14, { date: '2026-10-05' });
      const s = await stats();
      assert.equal(s.aggregation, 'average');
      assert.equal(s.period.days_count, 5);
      assert.equal(s.period.sample_count, 6);
      // (6 + 7 + 8 + 9 + 10 + 14) / 6 = 9.
      assert.equal(s.period.value, 9);
      assert.equal(s.period.per_day_average, null);
      assert.deepEqual(s.record, { value: 14, local_date: '2026-10-05' });
      assert.deepEqual(s.latest, { local_date: '2026-10-05', value: 12, sample_count: 2 });
      assert.equal(s.trend.points, 5);
      // Daily values 6, 7, 8, 9, 12: least-squares slope 1.4 per day.
      assert.ok(Math.abs(s.trend.slope_per_day - 1.4) < 1e-9);
    }));

  test('no record for metrics without a record direction; lower is better for 5 km', () =>
    inRollback(pool, async (c) => {
      const user = await createUser(c);
      const mood = await track(c, user, 'humeur');
      const run = await track(c, user, 'course_5km');
      await record(c, mood, 7, { unit: 'point', date: '2026-10-01' });
      await record(c, run, 1500, { unit: 'second', date: '2026-10-01' });
      await record(c, run, 1430, { unit: 'second', date: '2026-10-08' });
      await record(c, run, 1470, { unit: 'second', date: '2026-10-09' });
      const get = async (id) =>
        (await c.query('select public.get_metric_statistics($1, $2, $3) as s', [
          id, '2026-10-01', '2026-10-31',
        ])).rows[0].s;
      assert.equal((await get(mood)).record, null);
      assert.deepEqual((await get(run)).record, { value: 1430, local_date: '2026-10-08' });
    }));

  test('sum metrics expose the average per recorded day', () =>
    inRollback(pool, async (c) => {
      const user = await createUser(c);
      const sleep = await track(c, user, 'sommeil_duree');
      await record(c, sleep, 25200, { unit: 'second', date: '2026-10-01' });
      await record(c, sleep, 28800, { unit: 'second', date: '2026-10-02' });
      const s = (await c.query('select public.get_metric_statistics($1, $2, $3) as s', [
        sleep, '2026-10-01', '2026-10-31',
      ])).rows[0].s;
      assert.equal(s.period.value, 54000);
      assert.equal(s.period.per_day_average, 27000);
    }));

  test('period comparison needs 3 recorded days on each side', () =>
    inRollback(pool, async (c) => {
      const user = await createUser(c);
      const tractions = await track(c, user, 'tractions');
      const compare = async () =>
        (await c.query('select public.compare_metric_periods($1, $2, $3, $4, $5) as r', [
          tractions, '2026-09-01', '2026-09-30', '2026-10-01', '2026-10-31',
        ])).rows[0].r;
      for (const date of ['2026-09-02', '2026-09-03', '2026-09-04']) {
        await record(c, tractions, 8, { date });
      }
      for (const date of ['2026-10-02', '2026-10-03']) {
        await record(c, tractions, 10, { date });
      }
      const early = await compare();
      assert.equal(early.comparable, false);
      assert.equal(early.difference, null);
      await record(c, tractions, 10, { date: '2026-10-04' });
      const ready = await compare();
      assert.equal(ready.comparable, true);
      assert.equal(ready.a.value, 8);
      assert.equal(ready.b.value, 10);
      assert.equal(ready.difference, 2);
      assert.equal(ready.percent_change, 25);
    }));

  test('overview: tracked metrics, latest values and 30-day comparison in the profile zone', () =>
    inRollback(pool, async (c) => {
      const user = await createUser(c);
      const tractions = await track(c, user, 'tractions');
      const sleep = await track(c, user, 'sommeil_duree');
      await c.query("insert into public.profiles (timezone) values ('Asia/Tokyo')");
      await c.query('update public.user_metrics set is_favorite = true where id = $1', [sleep]);
      const { rows: today } = await c.query(
        "select (now() at time zone 'Asia/Tokyo')::date as d",
      );
      const tokyoToday = today[0].d;
      const d = (offset) => {
        const value = new Date(`${tokyoToday}T00:00:00Z`);
        value.setUTCDate(value.getUTCDate() - offset);
        return value.toISOString().slice(0, 10);
      };
      for (const offset of [0, 1, 2]) await record(c, tractions, 10, { date: d(offset), timezone: 'Asia/Tokyo' });
      for (const offset of [31, 32, 33]) await record(c, tractions, 8, { date: d(offset), timezone: 'Asia/Tokyo' });
      const overview = (await c.query('select public.get_overview() as o')).rows[0].o;
      assert.equal(overview.timezone, 'Asia/Tokyo');
      assert.equal(overview.today, tokyoToday);
      assert.equal(overview.days_recorded, 6);
      assert.equal(overview.entries_count, 6);
      assert.equal(overview.metrics.length, 2);
      // Favourites first.
      assert.equal(overview.metrics[0].user_metric_id, sleep);
      assert.equal(overview.metrics[0].latest, null);
      assert.equal(overview.metrics[0].comparable, false);
      const t = overview.metrics[1];
      assert.equal(t.latest.local_date, tokyoToday);
      assert.equal(t.recent.value, 10);
      assert.equal(t.previous.value, 8);
      assert.equal(t.comparable, true);
    }));
});
