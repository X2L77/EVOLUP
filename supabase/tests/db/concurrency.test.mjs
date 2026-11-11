// Simultaneous entries on separate connections (SPEC_PROJECT.md §6.2,
// test 4 of §17.3). Data is committed so that the connections see each other,
// then removed.

import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { after, describe, test } from 'node:test';
import { asUser, createUser, startDatabase, track } from './harness.mjs';

const { pool } = await startDatabase();
const users = [];

async function setup() {
  const client = await pool.connect();
  try {
    await client.query('begin');
    const user = await createUser(client);
    const metric = await track(client, user, 'tractions');
    await client.query('commit');
    users.push(user);
    return { user, metric };
  } finally {
    client.release();
  }
}

/** Opens [count] connections, then sends every entry at the same time. */
async function simultaneously(user, entries) {
  const clients = await Promise.all(entries.map(() => pool.connect()));
  try {
    await Promise.all(clients.map(async (client) => {
      await client.query('begin');
      await asUser(client, user);
    }));
    const results = await Promise.all(clients.map(async (client, i) => {
      const { metric, value, key = randomUUID(), date = '2026-11-02' } = entries[i];
      const { rows } = await client.query(
        'select public.record_metric_entry($1, $2, $3, $4, $5, $6) as r',
        [metric, value, 'repetition', date, 'Europe/Paris', key],
      );
      await client.query('commit');
      return rows[0].r;
    }));
    return results;
  } finally {
    for (const client of clients) client.release();
  }
}

async function dayRow(metric, date = '2026-11-02') {
  const { rows } = await pool.query(
    `select sample_count, value_sum::text, value_min::text, value_max::text,
            cardinality(entry_fingerprints) as fingerprints
     from public.metric_daily_aggregates
     where user_metric_id = $1 and local_date = $2`,
    [metric, date],
  );
  return rows[0];
}

after(async () => {
  for (const user of users) {
    await pool.query('delete from auth.users where id = $1', [user]);
  }
});

describe('concurrency', () => {
  test('30 different values sent at once: none is lost', async () => {
    const { user, metric } = await setup();
    const values = Array.from({ length: 30 }, (_, i) => i + 1);
    const results = await simultaneously(user, values.map((value) => ({ metric, value })));
    assert.ok(results.every((r) => r.status === 'recorded'));
    const row = await dayRow(metric);
    assert.equal(row.sample_count, 30);
    assert.equal(row.value_sum, String(values.reduce((a, b) => a + b)));
    assert.equal(row.value_min, '1');
    assert.equal(row.value_max, '30');
    assert.equal(row.fingerprints, 30);
  });

  test('the same value sent 20 times at once is merged once', async () => {
    const { user, metric } = await setup();
    const results = await simultaneously(
      user,
      Array.from({ length: 20 }, () => ({ metric, value: 8 })),
    );
    assert.equal(results.filter((r) => r.status === 'recorded').length, 1);
    assert.equal(results.filter((r) => r.status === 'duplicate').length, 19);
    assert.equal((await dayRow(metric)).sample_count, 1);
  });

  test('a request retried 10 times at once with its key is merged once', async () => {
    const { user, metric } = await setup();
    const key = randomUUID();
    const results = await simultaneously(
      user,
      Array.from({ length: 10 }, () => ({ metric, value: 12, key })),
    );
    assert.equal(results.filter((r) => r.status === 'recorded').length, 1);
    assert.equal(results.filter((r) => r.status === 'already_recorded').length, 9);
    assert.equal((await dayRow(metric)).value_sum, '12');
  });

  test('simultaneous entries on different days create separate rows', async () => {
    const { user, metric } = await setup();
    const dates = ['2026-10-01', '2026-10-02', '2026-10-03', '2026-10-01', '2026-10-02'];
    await simultaneously(user, dates.map((date, i) => ({ metric, value: i + 1, date })));
    assert.equal((await dayRow(metric, '2026-10-01')).value_sum, '5');
    assert.equal((await dayRow(metric, '2026-10-02')).value_sum, '7');
    assert.equal((await dayRow(metric, '2026-10-03')).value_sum, '3');
  });
});
