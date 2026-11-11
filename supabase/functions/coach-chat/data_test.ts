import assert from 'node:assert/strict';

// Polomix must never write user data (SPEC_PROJECT.md §10.3). The function's
// only access to the database is data.ts: it must contain reads only.
Deno.test('the data access of the coach contains no write', async () => {
  const source = await Deno.readTextFile(new URL('./data.ts', import.meta.url));
  for (
    const forbidden of [
      '.insert(',
      '.update(',
      '.upsert(',
      '.delete(',
      'record_metric_entry',
      'correct_metric_day',
      'service_role',
      'SERVICE_ROLE',
    ]
  ) {
    assert.equal(source.includes(forbidden), false, forbidden);
  }
  // Every request carries the header the write functions refuse.
  assert.match(source, /'x-evolup-actor': 'polomix'/);
});

Deno.test('no other module of the function talks to the database', async () => {
  for (const file of ['handler.ts', 'context.ts', 'intent.ts', 'polomix.ts']) {
    const source = await Deno.readTextFile(
      new URL(`./${file}`, import.meta.url),
    );
    assert.equal(source.includes('createClient'), false, file);
    assert.equal(source.includes('.rpc('), false, file);
  }
});
