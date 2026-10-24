import assert from 'node:assert/strict';
import {
  createPolomixClient,
  MAX_REPLY_LENGTH,
  POLOMIX_CHAT_URL,
  POLOMIX_MODEL,
} from './polomix.ts';
import { InMemoryRateLimiter } from './rate_limit.ts';

const TEST_KEY = 'fake-test-key';

function clientReturning(
  response: Response | Error,
  options: { key?: string } = { key: TEST_KEY },
) {
  const requests: Request[] = [];
  const client = createPolomixClient({
    apiKey: () => options.key,
    fetch: (input, init) => {
      requests.push(new Request(input, init));
      return response instanceof Error
        ? Promise.reject(response)
        : Promise.resolve(response);
    },
  });
  return { client, requests };
}

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });

Deno.test('sends the documented request and reads the documented reply', async () => {
  const { client, requests } = clientReturning(
    json({ reply: ' Bonjour ! ', tokens_used: '12', model: 'chatix-25' }),
  );
  assert.deepEqual(await client.chat('Bonjour Polomix'), {
    ok: true,
    reply: 'Bonjour !',
    model: 'chatix-25',
    tokensUsed: 12,
  });
  const [request] = requests;
  assert.equal(request.url, POLOMIX_CHAT_URL);
  assert.equal(request.method, 'POST');
  assert.equal(request.headers.get('Authorization'), `Bearer ${TEST_KEY}`);
  assert.deepEqual(await request.json(), {
    message: 'Bonjour Polomix',
    model: POLOMIX_MODEL,
  });
});

Deno.test('tokens_used may be a number; missing model falls back', async () => {
  const { client } = clientReturning(json({ reply: 'Ok', tokens_used: 7 }));
  assert.deepEqual(await client.chat('x'), {
    ok: true,
    reply: 'Ok',
    model: POLOMIX_MODEL,
    tokensUsed: 7,
  });
  const odd = clientReturning(json({ reply: 'Ok', tokens_used: 'beaucoup' }));
  const result = await odd.client.chat('x');
  assert.equal(result.ok && result.tokensUsed, null);
});

Deno.test('HTTP errors are classified without exposing the body', async () => {
  const cases: [number, string][] = [
    [401, 'auth'],
    [403, 'auth'],
    [402, 'quota'],
    [429, 'quota'],
    [400, 'rejected'],
    [413, 'rejected'],
    [422, 'rejected'],
    [500, 'unavailable'],
    [503, 'unavailable'],
    [404, 'unavailable'],
  ];
  for (const [status, failure] of cases) {
    const { client } = clientReturning(
      json({ error: { message: 'Clé API manquante ou invalide.' } }, status),
    );
    assert.deepEqual(await client.chat('x'), { ok: false, failure, status });
  }
});

Deno.test('malformed successful responses are rejected', async () => {
  const bodies: (string | unknown)[] = [
    'pas du JSON',
    [],
    null,
    {},
    { reply: 42 },
    { reply: '   ' },
    { reply: 'a'.repeat(MAX_REPLY_LENGTH + 1) },
  ];
  for (const body of bodies) {
    const response = typeof body === 'string'
      ? new Response(body, { status: 200 })
      : json(body);
    const { client } = clientReturning(response);
    const result = await client.chat('x');
    assert.deepEqual(result, {
      ok: false,
      failure: 'bad_response',
      status: 200,
    });
  }
});

Deno.test('network errors and timeouts are distinguished', async () => {
  const network = clientReturning(new TypeError('fetch failed'));
  assert.deepEqual(await network.client.chat('x'), {
    ok: false,
    failure: 'unavailable',
  });
  const timeout = clientReturning(
    new DOMException('The operation timed out.', 'TimeoutError'),
  );
  assert.deepEqual(await timeout.client.chat('x'), {
    ok: false,
    failure: 'timeout',
  });
});

Deno.test('a real timeout aborts a slow Polomix call', async () => {
  const client = createPolomixClient({
    apiKey: () => TEST_KEY,
    timeoutMs: 20,
    fetch: (_input, init) =>
      new Promise((_resolve, reject) => {
        init?.signal?.addEventListener('abort', () =>
          reject(init.signal?.reason));
      }),
  });
  assert.deepEqual(await client.chat('x'), { ok: false, failure: 'timeout' });
});

Deno.test('without a key nothing is sent', async () => {
  for (const key of [undefined, '', '   ']) {
    const { client, requests } = clientReturning(json({ reply: 'x' }), { key });
    assert.equal(client.isConfigured(), false);
    assert.deepEqual(await client.chat('x'), { ok: false, failure: 'auth' });
    assert.equal(requests.length, 0);
  }
});

Deno.test('the rate limiter counts per user, per minute and in flight', () => {
  const limiter = new InMemoryRateLimiter({
    perMinute: 2,
    perHour: 3,
    concurrent: 1,
  });
  const t = 0;
  assert.deepEqual(limiter.tryAcquire('a', t), { allowed: true });
  // Same user, previous request still in flight.
  assert.equal(limiter.tryAcquire('a', t).allowed, false);
  // Another user is independent.
  assert.deepEqual(limiter.tryAcquire('b', t), { allowed: true });
  limiter.release('a');
  assert.deepEqual(limiter.tryAcquire('a', t + 1), { allowed: true });
  limiter.release('a');
  const minute = limiter.tryAcquire('a', t + 2);
  assert.equal(minute.allowed, false);
  assert.equal(!minute.allowed && minute.retryAfterSeconds, 60);
  assert.deepEqual(limiter.tryAcquire('a', t + 61_000), { allowed: true });
  limiter.release('a');
  const hour = limiter.tryAcquire('a', t + 130_000);
  assert.equal(hour.allowed, false);
});
