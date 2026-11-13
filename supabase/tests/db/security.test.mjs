// RLS, privileges and function security with several identities
// (SPEC_PROJECT.md §9, tests of §17.1 and §17.5).

import assert from 'node:assert/strict';
import { describe, test } from 'node:test';
import {
  asAnon,
  asOwner,
  asUser,
  catalogId,
  createUser,
  expectPgError,
  inRollback,
  inSavepoint,
  record,
  startDatabase,
  track,
} from './harness.mjs';

const { pool } = await startDatabase();

/** Alice tracks tractions with one recorded day and has a profile. */
async function aliceAndBob(c) {
  const alice = await createUser(c, 'alice@test.local');
  const bob = await createUser(c, 'bob@test.local');
  const aliceMetric = await track(c, alice, 'tractions');
  await c.query("insert into public.profiles (timezone) values ('Europe/Paris')");
  await record(c, aliceMetric, 8);
  await asUser(c, bob);
  return { alice, bob, aliceMetric };
}

const privateTables = [
  'public.profiles',
  'public.user_metrics',
  'public.metric_daily_aggregates',
  'public.metric_daily_values',
];

/** A column every API role may read when allowed (no fingerprints). */
const readableColumn = {
  'public.profiles': 'user_id',
  'public.user_metrics': 'id',
  'public.metric_daily_aggregates': 'id',
  'public.metric_daily_values': 'id',
  'public.metric_catalog': 'id',
  'public.metric_categories': 'id',
  'public.athlete_profiles': 'user_id',
};

describe('catalog', () => {
  test('signed-in users read the active catalog and its categories', () =>
    inRollback(pool, async (c) => {
      const user = await createUser(c);
      await asUser(c, user);
      const metrics = await c.query(
        'select slug from public.metric_catalog where is_active order by id',
      );
      assert.equal(metrics.rowCount, 16);
      assert.equal(metrics.rows[0].slug, 'tractions');
      const categories = await c.query('select slug from public.metric_categories');
      assert.equal(categories.rowCount, 7);
    }));

  test('nobody can write the catalog through the Data API roles', () =>
    inRollback(pool, async (c) => {
      const user = await createUser(c);
      for (const act of [(cl) => asUser(cl, user), asAnon]) {
        await act(c);
        for (const sql of [
          "update public.metric_catalog set name = 'x' where id = 1",
          'delete from public.metric_catalog where id = 1',
          `insert into public.metric_catalog (id, slug, category_id, name, description,
             value_kind, storage_unit, unit_label, aggregation)
           values (999, 'hack', 1, 'x', 'x', 'integer', 'repetition', 'x', 'sum')`,
          "update public.metric_categories set name = 'x' where id = 1",
          "insert into public.metric_categories (id, slug, name) values (99, 'x', 'x')",
        ]) {
          await inSavepoint(c, () => expectPgError(c.query(sql), { code: '42501' }));
        }
      }
    }));

  test('a metric is tracked once; an inactive catalog metric cannot be added', () =>
    inRollback(pool, async (c) => {
      const user = await createUser(c);
      const tractions = await track(c, user, 'tractions');
      assert.ok(tractions);
      await inSavepoint(c, () => expectPgError(track(c, user, 'tractions'), { code: '23505' }));
      await asOwner(c);
      await c.query("update public.metric_catalog set is_active = false where slug in ('pompes', 'tractions')");
      // A retired metric stays readable (history) but cannot be added.
      await asUser(c, user);
      assert.equal(
        (await c.query("select is_active from public.metric_catalog where slug = 'pompes'")).rows[0].is_active,
        false,
      );
      await inSavepoint(c, () => expectPgError(track(c, user, 'pompes'), { code: '42501' }));
      // Entries into a retired metric are refused, its history is kept.
      await inSavepoint(c, () => expectPgError(record(c, tractions, 9), { message: 'metric_retired' }));
      await c.query('update public.user_metrics set is_active = false where id = $1', [tractions]);
      await inSavepoint(c, () =>
        expectPgError(
          c.query('update public.user_metrics set is_active = true where id = $1', [tractions]),
          { code: '42501' },
        ));
    }));

  test('tracked metrics cannot be moved to another metric or user', () =>
    inRollback(pool, async (c) => {
      const { bob, aliceMetric } = await aliceAndBob(c);
      const bobMetric = await track(c, bob, 'pompes');
      for (const sql of [
        `update public.user_metrics set metric_catalog_id = 1 where id = '${bobMetric}'`,
        `update public.user_metrics set user_id = user_id where id = '${bobMetric}'`,
        `update public.user_metrics set added_at = now() where id = '${bobMetric}'`,
      ]) {
        await inSavepoint(c, () => expectPgError(c.query(sql), { code: '42501' }));
      }
      assert.ok(aliceMetric);
    }));

  test('catalog definitions are permanent once tracked', () =>
    inRollback(pool, async (c) => {
      const user = await createUser(c);
      await track(c, user, 'tractions');
      await asOwner(c);
      await inSavepoint(c, () =>
        expectPgError(c.query("update public.metric_catalog set slug = 'pullups' where slug = 'tractions'"), {
          message: 'metric_identity_is_permanent',
        }));
      await inSavepoint(c, () =>
        expectPgError(c.query("update public.metric_catalog set aggregation = 'sum' where slug = 'tractions'"), {
          message: 'metric_storage_is_permanent_once_tracked',
        }));
      await inSavepoint(c, () =>
        expectPgError(c.query("delete from public.metric_catalog where slug = 'tractions'"), {
          code: '23503',
        }));
      // Untracked metrics can still be adjusted by a migration.
      await c.query("update public.metric_catalog set aggregation = 'max' where slug = 'pompes'");
      // Descriptions of tracked metrics too.
      await c.query("update public.metric_catalog set description = 'Séries.' where slug = 'tractions'");
    }));
});

describe('row-level security', () => {
  test('a user never reads another user\'s data', () =>
    inRollback(pool, async (c) => {
      const { aliceMetric } = await aliceAndBob(c);
      for (const table of privateTables) {
        const { rowCount } = await c.query(`select ${readableColumn[table]} from ${table}`);
        assert.equal(rowCount, 0, table);
      }
      const history = await c.query(
        "select * from public.get_metric_history($1, '2026-01-01', '2026-12-31', 'day')",
        [aliceMetric],
      );
      assert.equal(history.rowCount, 0);
      const stats = await c.query(
        "select public.get_metric_statistics($1, '2026-01-01', '2026-12-31') as s",
        [aliceMetric],
      );
      assert.equal(stats.rows[0].s, null);
      const compare = await c.query(
        "select public.compare_metric_periods($1, '2026-01-01', '2026-06-30', '2026-07-01', '2026-12-31') as s",
        [aliceMetric],
      );
      assert.equal(compare.rows[0].s, null);
      const overview = (await c.query('select public.get_overview() as o')).rows[0].o;
      assert.deepEqual(overview.metrics, []);
      assert.equal(overview.days_recorded, 0);
    }));

  test('a user never modifies or deletes another user\'s data', () =>
    inRollback(pool, async (c) => {
      const { alice, aliceMetric } = await aliceAndBob(c);
      const writes = [
        ["update public.profiles set display_name = 'x'", []],
        ['update public.user_metrics set is_active = false where id = $1', [aliceMetric]],
        ['delete from public.user_metrics where id = $1', [aliceMetric]],
        ['delete from public.metric_daily_aggregates where user_metric_id = $1', [aliceMetric]],
      ];
      for (const [sql, params] of writes) {
        assert.equal((await c.query(sql, params)).rowCount, 0, sql);
      }
      await asUser(c, alice);
      assert.equal((await c.query('select * from public.metric_daily_values')).rowCount, 1);
      assert.equal((await c.query('select display_name from public.profiles')).rows[0].display_name, null);
    }));

  test('a foreign user_metric_id is refused everywhere', () =>
    inRollback(pool, async (c) => {
      const { alice, bob, aliceMetric } = await aliceAndBob(c);
      await inSavepoint(c, () => expectPgError(record(c, aliceMetric, 9), { message: 'metric_not_tracked' }));
      await inSavepoint(c, () =>
        expectPgError(
          c.query('select public.correct_metric_day($1, $2, $3, $4)', [
            aliceMetric, '2026-11-02', 1, 'repetition',
          ]),
          { message: 'metric_not_tracked' },
        ));
      // Tracking on behalf of someone else is refused.
      await inSavepoint(c, () =>
        expectPgError(
          c.query('insert into public.user_metrics (user_id, metric_catalog_id) values ($1, 2)', [alice]),
          { code: '42501' },
        ));
      await inSavepoint(c, () =>
        expectPgError(
          c.query("insert into public.profiles (user_id, timezone) values ($1, 'UTC')", [alice]),
          { code: '42501' },
        ));
      // Even the owner cannot attach an aggregate to another user's metric.
      await asOwner(c);
      await inSavepoint(c, () =>
        expectPgError(
          c.query(
            `insert into public.metric_daily_aggregates (user_id, user_metric_id, local_date,
               timezone_name, sample_count, value_sum, value_min, value_max, value_last,
               entry_fingerprints)
             values ($1, $2, '2026-11-01', 'UTC', 1, 1, 1, 1, 1, '{1}')`,
            [bob, aliceMetric],
          ),
          { code: '23503' },
        ));
    }));

  test('aggregates cannot be written directly, and fingerprints are not readable', () =>
    inRollback(pool, async (c) => {
      const { bob } = await aliceAndBob(c);
      const bobMetric = await track(c, bob, 'tractions');
      await record(c, bobMetric, 8);
      for (const sql of [
        `insert into public.metric_daily_aggregates (user_id, user_metric_id, local_date,
           timezone_name, sample_count, value_sum, value_min, value_max, value_last,
           entry_fingerprints)
         values ('${bob}', '${bobMetric}', '2026-11-01', 'UTC', 1, 1, 1, 1, 1, '{1}')`,
        `update public.metric_daily_aggregates set sample_count = 5 where user_metric_id = '${bobMetric}'`,
        'select entry_fingerprints from public.metric_daily_aggregates',
        'select request_keys from public.metric_daily_aggregates',
        'select * from public.metric_daily_aggregates',
      ]) {
        await inSavepoint(c, () => expectPgError(c.query(sql), { code: '42501' }));
      }
      const own = await c.query('select id, value_sum from public.metric_daily_aggregates');
      assert.equal(own.rowCount, 1);
    }));

  test('profiles: own row only, valid IANA zone, server-managed timestamps', () =>
    inRollback(pool, async (c) => {
      const user = await createUser(c);
      await asUser(c, user);
      await inSavepoint(c, () =>
        expectPgError(c.query("insert into public.profiles (timezone) values ('Europe/Atlantis')"), {
          message: 'invalid_timezone',
        }));
      await c.query("insert into public.profiles (timezone) values ('America/Montreal')");
      await c.query("update public.profiles set theme_palette = 'gold', theme_mode = 'light'");
      await inSavepoint(c, () =>
        expectPgError(c.query("update public.profiles set theme_palette = 'pink'"), { code: '23514' }));
      await inSavepoint(c, () =>
        expectPgError(c.query("update public.profiles set created_at = now() - interval '1 year'"), {
          code: '42501',
        }));
      await inSavepoint(c, () =>
        expectPgError(c.query('delete from public.profiles'), { code: '42501' }));
      const { rows } = await c.query('select * from public.profiles');
      assert.equal(rows[0].coach_data_access, false);
      assert.equal(rows[0].theme_mode, 'light');
      const zones = (await c.query('select z from public.list_timezones() z')).rows.map((r) => r.z);
      assert.ok(zones.includes('Europe/Paris'));
      assert.ok(zones.includes('UTC'));
      assert.ok(!zones.some((z) => z.startsWith('posix/')));
    }));

  test('an anonymous caller reads nothing and calls nothing', () =>
    inRollback(pool, async (c) => {
      const { aliceMetric } = await aliceAndBob(c);
      await asAnon(c);
      for (const table of [...privateTables, 'public.metric_catalog', 'public.metric_categories', 'public.athlete_profiles']) {
        await inSavepoint(c, () =>
          expectPgError(c.query(`select ${readableColumn[table]} from ${table}`), { code: '42501' }));
      }
      for (const sql of [
        `select public.record_metric_entry('${aliceMetric}', 1, 'repetition', '2026-11-01', 'UTC', gen_random_uuid())`,
        `select public.correct_metric_day('${aliceMetric}', '2026-11-01', 1, 'repetition')`,
        'select public.get_overview()',
        `select public.get_metric_statistics('${aliceMetric}', '2026-01-01', '2026-12-31')`,
        `select * from public.get_metric_history('${aliceMetric}', '2026-01-01', '2026-12-31')`,
        `select public.compare_metric_periods('${aliceMetric}', '2026-01-01', '2026-01-31', '2026-02-01', '2026-02-28')`,
        'select * from public.list_timezones()',
        "select private.is_valid_timezone('UTC')",
      ]) {
        await inSavepoint(c, () => expectPgError(c.query(sql), { code: '42501' }));
      }
    }));

  test('requests relayed by the Polomix function cannot write', () =>
    inRollback(pool, async (c) => {
      const user = await createUser(c);
      const tractions = await track(c, user, 'tractions');
      await record(c, tractions, 8);
      await asUser(c, user, { headers: { 'x-evolup-actor': 'polomix' } });
      await inSavepoint(c, () => expectPgError(record(c, tractions, 9), { message: 'coach_cannot_write' }));
      await inSavepoint(c, () =>
        expectPgError(
          c.query('select public.correct_metric_day($1, $2, $3, $4)', [
            tractions, '2026-11-02', 9, 'repetition',
          ]),
          { message: 'coach_cannot_write' },
        ));
      // Reading stays possible for the coach context.
      const s = (await c.query(
        "select public.get_metric_statistics($1, '2026-11-01', '2026-11-30') as s",
        [tractions],
      )).rows[0].s;
      assert.equal(s.period.sample_count, 1);
    }));

  test('service_role has no privilege on the new tables (as on athlete_profiles)', () =>
    inRollback(pool, async (c) => {
      await c.query('set local role service_role');
      for (const table of [...privateTables, 'public.metric_catalog']) {
        await inSavepoint(c, () =>
          expectPgError(c.query(`select ${readableColumn[table]} from ${table}`), { code: '42501' }));
      }
    }));
});

describe('schema hardening', () => {
  test('RLS is enabled on every table of public', () =>
    inRollback(pool, async (c) => {
      const { rows } = await c.query(`
        select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
        where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity`);
      assert.deepEqual(rows, []);
    }));

  test('only the two write functions are SECURITY DEFINER; every function pins search_path', () =>
    inRollback(pool, async (c) => {
      const { rows } = await c.query(`
        select n.nspname || '.' || p.proname as name, p.prosecdef, p.proconfig
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
        where n.nspname in ('public', 'private')
        order by 1`);
      assert.deepEqual(
        rows.filter((r) => r.prosecdef).map((r) => r.name),
        ['public.correct_metric_day', 'public.record_metric_entry'],
      );
      for (const row of rows) {
        assert.ok(row.proconfig?.includes('search_path=""'), `${row.name} must set search_path`);
      }
    }));

  test('private helpers are not executable by the API roles, except the read helpers', () =>
    inRollback(pool, async (c) => {
      const { rows } = await c.query(`
        select p.proname, r.rolname
        from pg_proc p
        join pg_namespace n on n.oid = p.pronamespace
        cross join (values ('anon'), ('authenticated'), ('service_role')) r(rolname)
        where n.nspname = 'private'
          and has_function_privilege(r.rolname, p.oid, 'execute')
        order by 1, 2`);
      assert.deepEqual(rows.map((r) => `${r.proname}:${r.rolname}`), [
        'assert_period:authenticated',
        'is_valid_timezone:authenticated',
        'local_today:authenticated',
        'metric_daily_value:authenticated',
      ]);
    }));

  test('the catalog seed uses each id and slug once and valid units', () =>
    inRollback(pool, async (c) => {
      const id = await catalogId(c, 'course_5km');
      assert.equal(id, 4);
      const { rows } = await c.query(`
        select slug, value_kind, storage_unit, aggregation, record_direction
        from public.metric_catalog order by id`);
      assert.equal(new Set(rows.map((r) => r.slug)).size, rows.length);
      const durations = rows.filter((r) => r.value_kind === 'duration');
      assert.ok(durations.every((r) => r.storage_unit === 'second'));
    }));
});

// The app deletes all tracking data with one PostgREST request,
// `DELETE /user_metrics?user_id=eq.<me>`: one statement in one transaction
// (lot 2, T4). No migration: these tests check the existing rules.
describe('deleting all tracking data', () => {
  /** Alice tracks two metrics with history; Bob one. Acts as Alice. */
  async function twoUsers(c) {
    const alice = await createUser(c, 'alice@test.local');
    const bob = await createUser(c, 'bob@test.local');
    const bobMetric = await track(c, bob, 'tractions');
    await record(c, bobMetric, 5);
    const tractions = await track(c, alice, 'tractions');
    await record(c, tractions, 8, { date: '2026-11-01' });
    await record(c, tractions, 9, { date: '2026-11-02' });
    const pompes = await track(c, alice, 'pompes');
    await record(c, pompes, 20);
    await c.query("insert into public.profiles (timezone) values ('Europe/Paris')");
    return { alice, bob, bobMetric, tractions, pompes };
  }

  async function count(c, sql, params = []) {
    return (await c.query(`select count(*)::int as n from ${sql}`, params)).rows[0].n;
  }

  test('one statement deletes every tracked metric and its history, only the user\'s', () =>
    inRollback(pool, async (c) => {
      const { alice, bob, bobMetric } = await twoUsers(c);
      const deleted = await c.query(
        'delete from public.user_metrics where user_id = $1 returning id',
        [alice],
      );
      assert.equal(deleted.rowCount, 2);
      assert.equal(await count(c, 'public.user_metrics'), 0);
      assert.equal(await count(c, 'public.metric_daily_aggregates'), 0);
      // The profile is kept.
      assert.equal(await count(c, 'public.profiles'), 1);
      await asOwner(c);
      assert.equal(
        await count(c, 'public.metric_daily_aggregates where user_id = $1', [alice]),
        0,
      );
      assert.equal(await count(c, 'public.user_metrics where user_id = $1', [bob]), 1);
      assert.equal(
        await count(c, 'public.metric_daily_aggregates where user_metric_id = $1', [bobMetric]),
        1,
      );
    }));

  test('another user\'s id in the filter deletes nothing', () =>
    inRollback(pool, async (c) => {
      const { alice, bob } = await twoUsers(c);
      await asUser(c, bob);
      const deleted = await c.query('delete from public.user_metrics where user_id = $1', [alice]);
      assert.equal(deleted.rowCount, 0);
      await asOwner(c);
      assert.equal(await count(c, 'public.user_metrics where user_id = $1', [alice]), 2);
      assert.equal(await count(c, 'public.metric_daily_aggregates where user_id = $1', [alice]), 3);
    }));

  test('a failure in the middle of the cascade leaves everything in place', () =>
    inRollback(pool, async (c) => {
      const { alice, pompes } = await twoUsers(c);
      // Test-only trigger (rolled back with the transaction): the cascade
      // fails on one metric's history, whatever was already deleted by the
      // same statement before it.
      await asOwner(c);
      await c.query(`
        create function public.test_fail_on_delete() returns trigger
        language plpgsql as $$
        begin
          if old.user_metric_id = '${pompes}' then
            raise exception 'simulated failure';
          end if;
          return old;
        end;
        $$`);
      await c.query(`
        create trigger test_fail_on_delete before delete
        on public.metric_daily_aggregates
        for each row execute function public.test_fail_on_delete()`);
      await asUser(c, alice);
      await inSavepoint(c, () =>
        expectPgError(
          c.query('delete from public.user_metrics where user_id = $1', [alice]),
          { message: 'simulated failure' },
        ));
      assert.equal(await count(c, 'public.user_metrics'), 2);
      assert.equal(await count(c, 'public.metric_daily_aggregates'), 3);
    }));
});
