// Local PostgreSQL 17 for the database tests: a throwaway cluster in a
// temporary folder, the Supabase stand-in (supabase_stub.sql), then every
// migration of supabase/migrations in order. Nothing touches a Supabase
// project.

import EmbeddedPostgres from 'embedded-postgres';
import pg from 'pg';
import { randomUUID } from 'node:crypto';
import { mkdtemp, readdir, readFile, rm } from 'node:fs/promises';
import net from 'node:net';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
export const migrationsDir = path.resolve(here, '..', '..', 'migrations');

// numeric and bigint come back as strings: keep them exact.
pg.types.setTypeParser(pg.types.builtins.NUMERIC, (value) => value);
pg.types.setTypeParser(pg.types.builtins.INT8, (value) => value);
// Dates stay 'YYYY-MM-DD' (no conversion through the machine's time zone).
pg.types.setTypeParser(pg.types.builtins.DATE, (value) => value);

let database;

export async function startDatabase() {
  if (database) return database;
  const dir = await mkdtemp(path.join(os.tmpdir(), 'evolup-pg-'));
  const port = await freePort();
  const server = new EmbeddedPostgres({
    databaseDir: dir,
    user: 'postgres',
    password: 'postgres',
    port,
    persistent: false,
    onLog: () => {},
    onError: () => {},
  });
  await server.initialise();
  await server.start();
  await server.createDatabase('evolup');
  const pool = new pg.Pool({
    host: '127.0.0.1',
    port,
    user: 'postgres',
    password: 'postgres',
    database: 'evolup',
    max: 40,
  });
  const client = await pool.connect();
  try {
    await client.query(await readFile(path.join(here, 'supabase_stub.sql'), 'utf8'));
    const files = (await readdir(migrationsDir)).filter((f) => f.endsWith('.sql')).sort();
    for (const file of files) {
      try {
        await client.query(await readFile(path.join(migrationsDir, file), 'utf8'));
      } catch (error) {
        error.message = `${file}: ${error.message}`;
        throw error;
      }
    }
  } finally {
    client.release();
  }
  database = {
    pool,
    migrations: (await readdir(migrationsDir)).filter((f) => f.endsWith('.sql')).sort(),
    async stop() {
      await pool.end();
      await server.stop();
      await rm(dir, { recursive: true, force: true });
      database = undefined;
    },
  };
  return database;
}

function freePort() {
  return new Promise((resolve, reject) => {
    const probe = net.createServer();
    probe.once('error', reject);
    probe.listen(0, '127.0.0.1', () => {
      const { port } = probe.address();
      probe.close(() => resolve(port));
    });
  });
}

/** Runs [fn] in a transaction that is always rolled back. */
export async function inRollback(pool, fn) {
  const client = await pool.connect();
  try {
    await client.query('begin');
    return await fn(client);
  } finally {
    await client.query('rollback');
    client.release();
  }
}

/** Creates an auth user (as the database owner) and returns its id. */
export async function createUser(client, email = `${randomUUID()}@test.local`) {
  const id = randomUUID();
  await client.query('reset role');
  await client.query('insert into auth.users (id, email) values ($1, $2)', [id, email]);
  return id;
}

/** Acts as a signed-in user for the rest of the transaction (like PostgREST). */
export async function asUser(client, userId, { headers } = {}) {
  await client.query('reset role');
  await client.query("select set_config('request.jwt.claims', $1, true)", [
    JSON.stringify({ sub: userId, role: 'authenticated' }),
  ]);
  await client.query("select set_config('request.headers', $1, true)", [
    JSON.stringify(headers ?? {}),
  ]);
  await client.query('set local role authenticated');
}

export async function asAnon(client) {
  await client.query('reset role');
  await client.query("select set_config('request.jwt.claims', $1, true)", [
    JSON.stringify({ role: 'anon' }),
  ]);
  await client.query('set local role anon');
}

export async function asOwner(client) {
  await client.query('reset role');
}

/** Rejects unless [promise] fails with [message] (and [code] when given). */
export async function expectPgError(promise, { message, code }) {
  try {
    await promise;
  } catch (error) {
    if (message !== undefined && !String(error.message).includes(message)) {
      throw new Error(`expected error "${message}", got "${error.message}"`);
    }
    if (code !== undefined && error.code !== code) {
      throw new Error(`expected SQLSTATE ${code}, got ${error.code} (${error.message})`);
    }
    return error;
  }
  throw new Error(`expected error "${message ?? code}", but the statement succeeded`);
}

/** Inside a rolled-back transaction, a failing statement aborts it: wrap it. */
export async function inSavepoint(client, fn) {
  await client.query('savepoint t');
  try {
    return await fn();
  } finally {
    await client.query('rollback to savepoint t');
  }
}

export async function catalogId(client, slug) {
  const { rows } = await client.query('select id from public.metric_catalog where slug = $1', [slug]);
  if (rows.length !== 1) throw new Error(`unknown metric ${slug}`);
  return rows[0].id;
}

/** Signed in as [userId]: tracks [slug] and returns the user_metrics id. */
export async function track(client, userId, slug) {
  await asUser(client, userId);
  const id = await catalogId(client, slug);
  const { rows } = await client.query(
    'insert into public.user_metrics (metric_catalog_id) values ($1) returning id',
    [id],
  );
  return rows[0].id;
}

export async function record(client, userMetricId, value, {
  unit = 'repetition',
  date = '2026-11-02',
  timezone = 'Europe/Paris',
  key = randomUUID(),
} = {}) {
  const { rows } = await client.query(
    'select public.record_metric_entry($1, $2, $3, $4, $5, $6) as result',
    [userMetricId, value, unit, date, timezone, key],
  );
  return rows[0].result;
}
