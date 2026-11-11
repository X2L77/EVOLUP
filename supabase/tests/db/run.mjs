// Entry point: `npm test` from this folder. Starts one local PostgreSQL,
// applies supabase/migrations, runs every test file, then stops it.

import { after } from 'node:test';
import { startDatabase } from './harness.mjs';

const database = await startDatabase();
console.log(`# migrations applied: ${database.migrations.join(', ')}`);

await import('./aggregation.test.mjs');
await import('./statistics.test.mjs');
await import('./security.test.mjs');
await import('./concurrency.test.mjs');

after(() => database.stop());
