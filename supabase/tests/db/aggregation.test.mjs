// Daily aggregation engine (SPEC_PROJECT.md §6, tests of §17.3).

import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { describe, test } from 'node:test';
import {
  asOwner,
  asUser,
  createUser,
  expectPgError,
  inRollback,
  inSavepoint,
  record,
  startDatabase,
  track,
} from './harness.mjs';

const { pool } = await startDatabase();

async function day(client, userMetricId, date = '2026-11-02') {
  const { rows } = await client.query(
    `select sample_count, value_sum, value_min, value_max, value_last,
            daily_value, timezone_name
     from public.metric_daily_values
     where user_metric_id = $1 and local_date = $2`,
    [userMetricId, date],
  );
  return rows[0];
}

describe('aggregation', () => {
  test('8 then 10 tractions: sum 18, 2 entries, average 9, one row', () =>
    inRollback(pool, async (c) => {
      const user = await createUser(c);
      const tractions = await track(c, user, 'tractions');
      const first = await record(c, tractions, 8);
      assert.equal(first.status, 'recorded');
      assert.equal(first.aggregate.sample_count, 1);
      const second = await record(c, tractions, 10);
      assert.equal(second.status, 'recorded');
      assert.equal(second.aggregate.value_sum, 18);
      assert.equal(second.aggregate.sample_count, 2);
      assert.equal(second.aggregate.daily_value, 9);
      const row = await day(c, tractions);
      assert.equal(row.sample_count, 2);
      assert.equal(row.value_sum, '18');
      assert.equal(Number(row.daily_value), 9);
      const { rows } = await c.query(
        'select count(*)::int as n from public.metric_daily_values where user_metric_id = $1',
        [tractions],
      );
      assert.equal(rows[0].n, 1);
    }));

  test('the same value on the same day is a duplicate and changes nothing', () =>
    inRollback(pool, async (c) => {
      const user = await createUser(c);
      const tractions = await track(c, user, 'tractions');
      await record(c, tractions, 8);
      const again = await record(c, tractions, 8);
      assert.equal(again.status, 'duplicate');
      assert.equal(again.aggregate.sample_count, 1);
      assert.equal(again.aggregate.value_sum, 8);
      // Normalisation: 8.0 and 8.00 are the same value.
      assert.equal((await record(c, tractions, '8.0')).status, 'duplicate');
      assert.equal((await record(c, tractions, '8.00')).status, 'duplicate');
      assert.equal((await day(c, tractions)).sample_count, 1);
      // The same value on another day is not a duplicate.
      assert.equal(
        (await record(c, tractions, 8, { date: '2026-11-01' })).status,
        'recorded',
      );
    }));

  test('three distinct entries keep full precision', () =>
    inRollback(pool, async (c) => {
      const user = await createUser(c);
      const tractions = await track(c, user, 'tractions');
      await record(c, tractions, 7);
      await record(c, tractions, 8);
      const third = await record(c, tractions, 10);
      assert.equal(third.aggregate.sample_count, 3);
      assert.equal(third.aggregate.value_sum, 25);
      assert.equal(third.aggregate.value_min, 7);
      assert.equal(third.aggregate.value_max, 10);
      assert.equal(third.aggregate.value_last, 10);
      const row = await day(c, tractions);
      // 25 / 3 = 8.333… with at least 15 exact decimals.
      assert.match(row.daily_value, /^8\.3{15,}$/);
    }));

  test('two different days stay separate', () =>
    inRollback(pool, async (c) => {
      const user = await createUser(c);
      const tractions = await track(c, user, 'tractions');
      await record(c, tractions, 8, { date: '2026-11-01' });
      await record(c, tractions, 12, { date: '2026-11-02' });
      assert.equal((await day(c, tractions, '2026-11-01')).value_sum, '8');
      assert.equal((await day(c, tractions, '2026-11-02')).value_sum, '12');
    }));

  test('a past date is stored on that local day with the zone used', () =>
    inRollback(pool, async (c) => {
      const user = await createUser(c);
      const tractions = await track(c, user, 'tractions');
      // Daylight-saving change day in Paris: no shift to the previous day.
      await record(c, tractions, 9, { date: '2025-03-30', timezone: 'Europe/Paris' });
      const row = await day(c, tractions, '2025-03-30');
      assert.equal(row.sample_count, 1);
      assert.equal(row.timezone_name, 'Europe/Paris');
      assert.equal(await day(c, tractions, '2025-03-29'), undefined);
    }));

  test('"today" is checked in the zone of the entry, not in UTC', () =>
    inRollback(pool, async (c) => {
      const user = await createUser(c);
      const tractions = await track(c, user, 'tractions');
      const { rows } = await c.query(`
        select (now() at time zone 'Pacific/Kiritimati')::date::text as east,
               (now() at time zone 'Pacific/Pago_Pago')::date::text as west`);
      // UTC+14 can already be "tomorrow" compared with UTC: accepted there.
      assert.equal(
        (await record(c, tractions, 9, { date: rows[0].east, timezone: 'Pacific/Kiritimati' })).status,
        'recorded',
      );
      // The same day may still be in the future in UTC-11.
      if (rows[0].east !== rows[0].west) {
        await inSavepoint(c, () =>
          expectPgError(record(c, tractions, 10, { date: rows[0].east, timezone: 'Pacific/Pago_Pago' }), {
            message: 'date_in_future',
            code: '22023',
          }));
      }
      const tomorrow = await c.query(
        "select ((now() at time zone 'Europe/Paris')::date + 1)::text as d",
      );
      await inSavepoint(c, () =>
        expectPgError(record(c, tractions, 10, { date: tomorrow.rows[0].d }), {
          message: 'date_in_future',
        }));
    }));

  test('a retried request (same idempotency key) is not counted twice', () =>
    inRollback(pool, async (c) => {
      const user = await createUser(c);
      const tractions = await track(c, user, 'tractions');
      const key = randomUUID();
      assert.equal((await record(c, tractions, 8, { key })).status, 'recorded');
      const retry = await record(c, tractions, 8, { key });
      assert.equal(retry.status, 'already_recorded');
      assert.equal(retry.aggregate.sample_count, 1);
      await record(c, tractions, 10);
      // Even when the day changed since, the key is still recognised.
      assert.equal((await record(c, tractions, 8, { key })).status, 'already_recorded');
      assert.equal((await day(c, tractions)).sample_count, 2);
    }));

  test('values are checked against the catalog definition', () =>
    inRollback(pool, async (c) => {
      const user = await createUser(c);
      const tractions = await track(c, user, 'tractions');
      const cases = [
        [501, {}, 'value_out_of_range'],
        [-1, {}, 'value_out_of_range'],
        ['8.5', {}, 'value_precision'],
        ['NaN', {}, 'value_invalid'],
        ['Infinity', {}, 'value_invalid'],
        [8, { unit: 'second' }, 'unit_mismatch'],
        [8, { timezone: 'Mars/Olympus' }, 'invalid_timezone'],
        [8, { timezone: 'UTC+3' }, 'invalid_timezone'],
        [8, { date: '1899-12-31' }, 'date_too_old'],
        [8, { key: null }, 'missing_parameter'],
      ];
      for (const [value, options, message] of cases) {
        await inSavepoint(c, () =>
          expectPgError(record(c, tractions, value, options), { message, code: '22023' }));
      }
      assert.equal(await day(c, tractions), undefined);
    }));

  test('sum metrics add up and respect the daily maximum', () =>
    inRollback(pool, async (c) => {
      const user = await createUser(c);
      const focus = await track(c, user, 'concentration_duree');
      await record(c, focus, 1800, { unit: 'second' });
      const total = await record(c, focus, 1200, { unit: 'second' });
      assert.equal(total.aggregate.daily_value, 3000);
      assert.equal(total.aggregate.sample_count, 2);
      await record(c, focus, 57600, { unit: 'second' });
      // 3000 + 57600 = 60600 s; another 8 h would exceed 24 h in one day.
      await inSavepoint(c, () =>
        expectPgError(record(c, focus, 28800, { unit: 'second' }), {
          message: 'daily_sum_exceeded',
        }));
      // Exactly 24 h is accepted.
      assert.equal((await record(c, focus, 25800, { unit: 'second' })).aggregate.value_sum, 86400);
    }));

  test('min metrics keep the best time of the day', () =>
    inRollback(pool, async (c) => {
      const user = await createUser(c);
      const run = await track(c, user, 'course_5km');
      await record(c, run, 1500, { unit: 'second' });
      const best = await record(c, run, 1450, { unit: 'second' });
      assert.equal(best.aggregate.daily_value, 1450);
      const slower = await record(c, run, 1600, { unit: 'second' });
      assert.equal(slower.aggregate.daily_value, 1450);
      assert.equal(slower.aggregate.value_last, 1600);
    }));

  test('distances are whole meters', () =>
    inRollback(pool, async (c) => {
      const user = await createUser(c);
      const run = await track(c, user, 'course_distance');
      await record(c, run, 5250, { unit: 'meter' });
      await inSavepoint(c, () =>
        expectPgError(record(c, run, '5250.5', { unit: 'meter' }), {
          message: 'value_precision',
        }));
      assert.equal((await record(c, run, 3000, { unit: 'meter' })).aggregate.daily_value, 8250);
    }));

  test('a correction replaces the day by one value and resets the fingerprints', () =>
    inRollback(pool, async (c) => {
      const user = await createUser(c);
      const tractions = await track(c, user, 'tractions');
      await record(c, tractions, 8);
      await record(c, tractions, 10);
      const { rows } = await c.query(
        'select public.correct_metric_day($1, $2, $3, $4) as r',
        [tractions, '2026-11-02', 12, 'repetition'],
      );
      assert.equal(rows[0].r.status, 'corrected');
      assert.equal(rows[0].r.aggregate.sample_count, 1);
      assert.equal(rows[0].r.aggregate.value_sum, 12);
      // 12 is now the day's only value; 8 is no longer part of it.
      assert.equal((await record(c, tractions, 12)).status, 'duplicate');
      const added = await record(c, tractions, 8);
      assert.equal(added.status, 'recorded');
      assert.equal(added.aggregate.sample_count, 2);
      assert.equal(added.aggregate.daily_value, 10);
      await inSavepoint(c, () =>
        expectPgError(
          c.query('select public.correct_metric_day($1, $2, $3, $4)', [
            tractions, '2026-10-01', 12, 'repetition',
          ]),
          { message: 'day_not_found' },
        ));
      await inSavepoint(c, () =>
        expectPgError(
          c.query('select public.correct_metric_day($1, $2, $3, $4)', [
            tractions, '2026-11-02', 9999, 'repetition',
          ]),
          { message: 'value_out_of_range' },
        ));
    }));

  test('a day can be deleted, then recorded again', () =>
    inRollback(pool, async (c) => {
      const user = await createUser(c);
      const tractions = await track(c, user, 'tractions');
      await record(c, tractions, 8);
      const deleted = await c.query(
        'delete from public.metric_daily_aggregates where user_metric_id = $1 and local_date = $2',
        [tractions, '2026-11-02'],
      );
      assert.equal(deleted.rowCount, 1);
      assert.equal(await day(c, tractions), undefined);
      assert.equal((await record(c, tractions, 8)).status, 'recorded');
    }));

  test('deleting a tracked metric deletes its whole history', () =>
    inRollback(pool, async (c) => {
      const user = await createUser(c);
      const tractions = await track(c, user, 'tractions');
      await record(c, tractions, 8, { date: '2026-11-01' });
      await record(c, tractions, 9, { date: '2026-11-02' });
      const deleted = await c.query('delete from public.user_metrics where id = $1', [tractions]);
      assert.equal(deleted.rowCount, 1);
      await asOwner(c);
      const { rows } = await c.query(
        'select count(*)::int as n from public.metric_daily_aggregates where user_metric_id = $1',
        [tractions],
      );
      assert.equal(rows[0].n, 0);
    }));

  test('the overview gives each metric its first recorded day', () =>
    inRollback(pool, async (c) => {
      const user = await createUser(c);
      const tractions = await track(c, user, 'tractions');
      await record(c, tractions, 8, { date: '2025-06-01' });
      await record(c, tractions, 9, { date: '2026-11-02' });
      const overview = (await c.query('select public.get_overview() as o')).rows[0].o;
      assert.equal(overview.metrics[0].first_date, '2025-06-01');
      assert.equal(overview.first_date, '2025-06-01');
      assert.equal(overview.metrics[0].days_count, 2);
    }));

  test('a day accepts at most 200 entries', () =>
    inRollback(pool, async (c) => {
      const user = await createUser(c);
      const tractions = await track(c, user, 'tractions');
      await asOwner(c);
      await c.query(
        `insert into public.metric_daily_aggregates (
           user_id, user_metric_id, local_date, timezone_name, sample_count,
           value_sum, value_min, value_max, value_last, entry_fingerprints)
         select $1, $2, '2026-11-02', 'Europe/Paris', 200, 20100, 1, 200, 200,
                array_agg(private.metric_value_fingerprint($2, '2026-11-02', v))
         from generate_series(1, 200) v`,
        [user, tractions],
      );
      await asUser(c, user);
      await inSavepoint(c, () =>
        expectPgError(record(c, tractions, 300), { message: 'daily_entry_limit' }));
      // A duplicate is still reported as such.
      assert.equal((await record(c, tractions, 5)).status, 'duplicate');
    }));

  test('inactive metrics keep their history but refuse new entries', () =>
    inRollback(pool, async (c) => {
      const user = await createUser(c);
      const tractions = await track(c, user, 'tractions');
      await record(c, tractions, 8);
      await c.query('update public.user_metrics set is_active = false where id = $1', [tractions]);
      assert.equal((await day(c, tractions)).sample_count, 1);
      await inSavepoint(c, () =>
        expectPgError(record(c, tractions, 9), { message: 'metric_not_active' }));
      await c.query('update public.user_metrics set is_active = true where id = $1', [tractions]);
      assert.equal((await record(c, tractions, 9)).status, 'recorded');
    }));
});
