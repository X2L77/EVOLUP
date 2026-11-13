// Rules of migration 20261112100000 (owner's decisions of 2026-11-12):
// one-year window of new entries, confirmed duplicates, 'day' grouping up
// to 365 days, the device's "today" in the overview.
//
// "Today" is pinned to 2026-11-12 12:00 UTC (harness PINNED_NOW): 12 November
// in Paris, Tokyo and UTC-11, already 13 November in UTC+14.

import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { describe, test } from 'node:test';
import {
  asAnon,
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

async function dayRow(c, userMetricId, date) {
  await asOwner(c);
  const { rows } = await c.query(
    `select sample_count, value_sum::text, cardinality(entry_fingerprints) as fingerprints
     from public.metric_daily_aggregates
     where user_metric_id = $1 and local_date = $2`,
    [userMetricId, date],
  );
  return rows[0];
}

/** A day recorded before the one-year rule existed (written as the owner). */
async function seedOldDay(c, user, userMetricId, date, value) {
  await asOwner(c);
  await c.query(
    `insert into public.metric_daily_aggregates (
       user_id, user_metric_id, local_date, timezone_name, sample_count,
       value_sum, value_min, value_max, value_last, entry_fingerprints)
     values ($1, $2, $3, 'Europe/Paris', 1, $4, $4, $4, $4,
             array[private.metric_value_fingerprint($2, $3, $4)])`,
    [user, userMetricId, date, value],
  );
  await asUser(c, user);
}

describe('one-year window of new entries', () => {
  test('the same calendar day one year ago is accepted, the day before is not', () =>
    inRollback(pool, async (c) => {
      const user = await createUser(c);
      const tractions = await track(c, user, 'tractions');
      assert.equal((await record(c, tractions, 8, { date: '2025-11-12' })).status, 'recorded');
      await inSavepoint(c, () =>
        expectPgError(record(c, tractions, 8, { date: '2025-11-11' }), {
          message: 'date_too_old',
          code: '22023',
        }));
      assert.equal((await record(c, tractions, 8, { date: '2026-11-12' })).status, 'recorded');
      await inSavepoint(c, () =>
        expectPgError(record(c, tractions, 8, { date: '2026-11-13' }), {
          message: 'date_in_future',
        }));
    }));

  test('the window is counted in the zone of the entry', () =>
    inRollback(pool, async (c) => {
      const user = await createUser(c);
      const tractions = await track(c, user, 'tractions');
      // Already 13 November in UTC+14: the window starts on 13 November 2025.
      await inSavepoint(c, () =>
        expectPgError(record(c, tractions, 8, { date: '2025-11-12', timezone: 'Pacific/Kiritimati' }), {
          message: 'date_too_old',
        }));
      assert.equal(
        (await record(c, tractions, 8, { date: '2026-11-13', timezone: 'Pacific/Kiritimati' })).status,
        'recorded',
      );
      // Still 12 November in UTC-11.
      assert.equal(
        (await record(c, tractions, 8, { date: '2025-11-12', timezone: 'Pacific/Pago_Pago' })).status,
        'recorded',
      );
    }));

  test('one year before 29 February is 28 February', () =>
    inRollback(pool, async (c) => {
      const { rows } = await c.query(`
        select private.earliest_entry_date('2028-02-29')::text as leap,
               private.earliest_entry_date('2027-03-01')::text as after_leap,
               private.earliest_entry_date('2026-11-12')::text as plain`);
      assert.deepEqual(rows[0], {
        leap: '2027-02-28',
        after_leap: '2026-03-01',
        plain: '2025-11-12',
      });
    }));

  test('days older than one year stay readable, correctable and deletable', () =>
    inRollback(pool, async (c) => {
      const user = await createUser(c);
      const tractions = await track(c, user, 'tractions');
      await seedOldDay(c, user, tractions, '2024-05-10', 7);
      const days = await c.query(
        'select local_date, daily_value from public.metric_daily_values where user_metric_id = $1',
        [tractions],
      );
      assert.deepEqual(days.rows.map((r) => r.local_date), ['2024-05-10']);
      const history = await c.query(
        "select * from public.get_metric_history($1, '2024-01-01', '2026-11-12', 'month')",
        [tractions],
      );
      assert.equal(history.rowCount, 1);
      const corrected = (await c.query(
        "select public.correct_metric_day($1, '2024-05-10', 9, 'repetition') as r",
        [tractions],
      )).rows[0].r;
      assert.equal(corrected.status, 'corrected');
      assert.equal(corrected.aggregate.value_sum, 9);
      // A new entry on that day is refused: the limit is for new entries.
      await inSavepoint(c, () =>
        expectPgError(record(c, tractions, 5, { date: '2024-05-10' }), { message: 'date_too_old' }));
      const deleted = await c.query(
        "delete from public.metric_daily_aggregates where user_metric_id = $1 and local_date = '2024-05-10'",
        [tractions],
      );
      assert.equal(deleted.rowCount, 1);
    }));

  test('without the pinned clock, "today" follows the server time in the zone', () =>
    inRollback(pool, async (c) => {
      const { rows } = await c.query(`
        select private.local_today('UTC') = (now() at time zone 'UTC')::date as utc,
               private.local_today('Asia/Tokyo') = (now() at time zone 'Asia/Tokyo')::date as tokyo`);
      assert.deepEqual(rows[0], { utc: true, tokyo: true });
    }, { realClock: true }));
});

describe('confirmed duplicates', () => {
  test('an identical value is a duplicate until the user confirms a new measure', () =>
    inRollback(pool, async (c) => {
      const user = await createUser(c);
      const tractions = await track(c, user, 'tractions');
      await record(c, tractions, 8, { date: '2026-11-10' });
      // Former six-argument call, then an explicit "no".
      assert.equal((await record(c, tractions, 8, { date: '2026-11-10' })).status, 'duplicate');
      const key = randomUUID();
      const refused = await record(c, tractions, '8.0', { date: '2026-11-10', key, confirmDuplicate: false });
      assert.equal(refused.status, 'duplicate');
      assert.equal(refused.aggregate.sample_count, 1);
      // The user confirms: same request key, counted once more.
      await asUser(c, user);
      const confirmed = await record(c, tractions, 8, { date: '2026-11-10', key, confirmDuplicate: true });
      assert.equal(confirmed.status, 'recorded');
      assert.equal(confirmed.aggregate.sample_count, 2);
      assert.equal(confirmed.aggregate.value_sum, 16);
      assert.equal(confirmed.aggregate.daily_value, 8);
      // A retry of the confirmed request is not counted again.
      await asUser(c, user);
      const retry = await record(c, tractions, 8, { date: '2026-11-10', key, confirmDuplicate: true });
      assert.equal(retry.status, 'already_recorded');
      assert.deepEqual(await dayRow(c, tractions, '2026-11-10'), {
        sample_count: 2,
        value_sum: '16',
        fingerprints: 2,
      });
      // A correction still resets the day to one entry.
      await asUser(c, user);
      const corrected = (await c.query(
        "select public.correct_metric_day($1, '2026-11-10', 8, 'repetition') as r",
        [tractions],
      )).rows[0].r;
      assert.equal(corrected.aggregate.sample_count, 1);
    }));

  test('a confirmed duplicate respects the daily limits', () =>
    inRollback(pool, async (c) => {
      const user = await createUser(c);
      const focus = await track(c, user, 'concentration_duree');
      // 16 h twice would exceed 24 h in the day.
      await record(c, focus, 57600, { unit: 'second' });
      await inSavepoint(c, () =>
        expectPgError(record(c, focus, 57600, { unit: 'second', confirmDuplicate: true }), {
          message: 'daily_sum_exceeded',
        }));
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
        expectPgError(record(c, tractions, 5, { confirmDuplicate: true }), {
          message: 'daily_entry_limit',
        }));
    }));

  test('Polomix cannot confirm a duplicate; anonymous callers cannot call it', () =>
    inRollback(pool, async (c) => {
      const user = await createUser(c);
      const tractions = await track(c, user, 'tractions');
      await record(c, tractions, 8);
      await asUser(c, user, { headers: { 'x-evolup-actor': 'polomix' } });
      await inSavepoint(c, () =>
        expectPgError(record(c, tractions, 8, { confirmDuplicate: true }), {
          message: 'coach_cannot_write',
        }));
      await asAnon(c);
      await inSavepoint(c, () =>
        expectPgError(record(c, tractions, 8, { confirmDuplicate: true }), { code: '42501' }));
    }));

  test('one function per name remains (no ambiguous overload for PostgREST)', () =>
    inRollback(pool, async (c) => {
      const { rows } = await c.query(`
        select p.proname, pg_catalog.pg_get_function_identity_arguments(p.oid) as args
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
        where n.nspname = 'public' and p.proname in ('record_metric_entry', 'get_overview')
        order by 1`);
      assert.deepEqual(rows, [
        { proname: 'get_overview', args: 'p_today date' },
        {
          proname: 'record_metric_entry',
          args: 'p_user_metric_id uuid, p_value numeric, p_unit text, p_local_date date, '
            + 'p_timezone text, p_idempotency_key uuid, p_confirm_duplicate boolean',
        },
      ]);
    }));
});

describe("'day' grouping up to 365 days", () => {
  test('365 calendar days are accepted, 366 are refused; other groupings unchanged', () =>
    inRollback(pool, async (c) => {
      const user = await createUser(c);
      const tractions = await track(c, user, 'tractions');
      await record(c, tractions, 10, { date: '2026-11-01' });
      const history = (from, to, bucket) => c.query(
        'select * from public.get_metric_history($1, $2, $3, $4)',
        [tractions, from, to, bucket],
      );
      assert.equal((await history('2025-11-13', '2026-11-12', 'day')).rowCount, 1);
      await inSavepoint(c, () =>
        expectPgError(history('2025-11-12', '2026-11-12', 'day'), {
          message: 'too_many_points',
          code: '22023',
        }));
      assert.equal((await history('2025-11-12', '2026-11-12', 'week')).rows[0].bucket, 'week');
      assert.equal((await history('2025-11-12', '2026-11-12', 'auto')).rows[0].bucket, 'week');
      assert.equal((await history('2020-01-01', '2026-11-12', 'month')).rowCount, 1);
    }));
});

describe("the overview uses the device's day", () => {
  test('p_today sets "today" and the 30-day windows; without it, the profile zone', () =>
    inRollback(pool, async (c) => {
      const user = await createUser(c);
      const tractions = await track(c, user, 'tractions');
      await c.query("insert into public.profiles (timezone) values ('Europe/Paris')");
      await record(c, tractions, 10, { date: '2026-11-12' });
      await record(c, tractions, 8, { date: '2026-10-14' });
      const overview = async (sql) => (await c.query(sql)).rows[0].o;
      const profileDay = await overview('select public.get_overview() as o');
      assert.equal(profileDay.today, '2026-11-12');
      assert.equal(profileDay.timezone, 'Europe/Paris');
      assert.equal(profileDay.metrics[0].recent.days_count, 2);
      // Device already on 13 November (UTC+14): its window moves by one day,
      // the recorded days do not.
      const device = await overview("select public.get_overview(p_today => '2026-11-13') as o");
      assert.equal(device.today, '2026-11-13');
      assert.equal(device.metrics[0].recent.from, '2026-10-15');
      assert.equal(device.metrics[0].recent.days_count, 1);
      assert.equal(device.metrics[0].latest.local_date, '2026-11-12');
      assert.equal(device.timezone, 'Europe/Paris');
    }));

  test('a day that exists nowhere on Earth right now is refused', () =>
    inRollback(pool, async (c) => {
      const user = await createUser(c);
      await asUser(c, user);
      // Pinned instant: 12 November in UTC-12, 13 November in UTC+14.
      for (const day of ['2026-11-12', '2026-11-13']) {
        const o = (await c.query('select public.get_overview($1::date) as o', [day])).rows[0].o;
        assert.equal(o.today, day);
      }
      for (const day of ['2026-11-11', '2026-11-14', '1900-01-01']) {
        await inSavepoint(c, () =>
          expectPgError(c.query('select public.get_overview($1::date)', [day]), {
            message: 'invalid_today',
            code: '22023',
          }));
      }
      await asAnon(c);
      await inSavepoint(c, () =>
        expectPgError(c.query("select public.get_overview('2026-11-12'::date)"), { code: '42501' }));
    }));
});
