import assert from 'node:assert/strict';
import { MAX_BODY_BYTES, MAX_MESSAGE_LENGTH } from './contract.ts';
import { allowedOriginsFrom } from './cors.ts';
import { createHandler, type LogEvent } from './handler.ts';
import type { PolomixClient, PolomixResult } from './polomix.ts';
import { InMemoryRateLimiter } from './rate_limit.ts';

const VALID_TOKEN = 'valid-user-token';
const URL = 'https://example.supabase.co/functions/v1/coach-chat';

function setup(
  options: {
    configured?: boolean;
    result?: PolomixResult;
    limiter?: InMemoryRateLimiter;
  } = {},
) {
  const calls: string[] = [];
  const logs: LogEvent[] = [];
  const polomix: PolomixClient = {
    isConfigured: () => options.configured ?? true,
    chat: (message) => {
      calls.push(message);
      return Promise.resolve(
        options.result ??
          { ok: true, reply: 'Réponse', model: 'chatix-25', tokensUsed: 3 },
      );
    },
  };
  const handle = createHandler({
    verifyUser: (token) =>
      Promise.resolve(token === VALID_TOKEN ? 'user-1' : null),
    polomix,
    rateLimiter: options.limiter ?? new InMemoryRateLimiter(),
    allowedOrigins: allowedOriginsFrom(undefined),
    log: (event) => logs.push(event),
    now: () => 1_000_000,
  });
  return { handle, calls, logs };
}

function post(
  body: unknown,
  headers: Record<string, string> = {},
): Request {
  return new Request(URL, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${VALID_TOKEN}`,
      'Content-Type': 'application/json',
      ...headers,
    },
    body: typeof body === 'string' ? body : JSON.stringify(body),
  });
}

async function errorCode(response: Response): Promise<string> {
  const body = await response.json();
  return body.error.code;
}

Deno.test('a signed-in chat message returns the real Polomix reply', async () => {
  const { handle, calls } = setup();
  const response = await handle(post({ kind: 'chat', message: '  Bonjour  ' }));
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), {
    kind: 'chat',
    reply: 'Réponse',
    model: 'chatix-25',
  });
  assert.deepEqual(calls, ['Bonjour']);
  assert.equal(response.headers.get('Cache-Control'), 'no-store');
});

Deno.test('requests without a valid session never reach Polomix', async () => {
  const { handle, calls } = setup();
  for (
    const authorization of [
      undefined,
      'Bearer',
      'Basic abc',
      'Bearer wrong-token',
      `Bearer ${VALID_TOKEN} extra`,
    ]
  ) {
    const headers: Record<string, string> = {
      'Content-Type': 'application/json',
    };
    if (authorization) headers.Authorization = authorization;
    const response = await handle(
      new Request(URL, {
        method: 'POST',
        headers,
        body: JSON.stringify({ kind: 'chat', message: 'Bonjour' }),
      }),
    );
    assert.equal(response.status, 401, String(authorization));
    assert.equal(await errorCode(response), 'unauthorized');
  }
  assert.deepEqual(calls, []);
});

Deno.test('a verification error is treated as an invalid session', async () => {
  const handle = createHandler({
    verifyUser: () => Promise.reject(new Error('JWKS unreachable')),
    polomix: { isConfigured: () => true, chat: () => assert.fail() },
    rateLimiter: new InMemoryRateLimiter(),
    allowedOrigins: allowedOriginsFrom(undefined),
  });
  const response = await handle(post({ kind: 'chat', message: 'Bonjour' }));
  assert.equal(response.status, 401);
});

Deno.test('invalid bodies are rejected with precise codes', async () => {
  const { handle, calls } = setup();
  const cases: [unknown, number, string][] = [
    ['{not json', 400, 'invalid_json'],
    [[1, 2], 400, 'invalid_request'],
    [{ message: 'Bonjour' }, 400, 'invalid_request'],
    [{ kind: 'task', task: 'score' }, 400, 'unsupported_kind'],
    [{ kind: 'chat', message: 42 }, 400, 'invalid_request'],
    [{ kind: 'chat', message: '   ' }, 400, 'empty_message'],
    [
      { kind: 'chat', message: 'a'.repeat(MAX_MESSAGE_LENGTH + 1) },
      400,
      'message_too_long',
    ],
    [
      { kind: 'chat', message: 'a'.repeat(MAX_BODY_BYTES) },
      413,
      'payload_too_large',
    ],
  ];
  for (const [body, status, code] of cases) {
    const response = await handle(post(body));
    assert.equal(response.status, status, code);
    assert.equal(await errorCode(response), code);
  }
  assert.deepEqual(calls, []);

  const longest = await handle(
    post({ kind: 'chat', message: 'é'.repeat(MAX_MESSAGE_LENGTH) }),
  );
  assert.equal(longest.status, 200);
});

Deno.test('only POST and the CORS preflight are accepted', async () => {
  const { handle } = setup();
  const get = await handle(
    new Request(URL, { headers: { Authorization: `Bearer ${VALID_TOKEN}` } }),
  );
  assert.equal(get.status, 405);
  assert.equal(await errorCode(get), 'method_not_allowed');
});

Deno.test('CORS: allowed origins get headers, others are refused', async () => {
  const { handle, calls } = setup();
  const preflight = await handle(
    new Request(URL, {
      method: 'OPTIONS',
      headers: { Origin: 'http://localhost:5000' },
    }),
  );
  assert.equal(preflight.status, 204);
  assert.equal(
    preflight.headers.get('Access-Control-Allow-Origin'),
    'http://localhost:5000',
  );
  assert.match(
    preflight.headers.get('Access-Control-Allow-Headers') ?? '',
    /authorization/,
  );

  const allowed = await handle(
    post({ kind: 'chat', message: 'Bonjour' }, {
      Origin: 'http://localhost:5000',
    }),
  );
  assert.equal(allowed.status, 200);
  assert.equal(
    allowed.headers.get('Access-Control-Allow-Origin'),
    'http://localhost:5000',
  );

  for (const method of ['OPTIONS', 'POST']) {
    const refused = await handle(
      new Request(URL, {
        method,
        headers: {
          Origin: 'https://evil.example',
          Authorization: `Bearer ${VALID_TOKEN}`,
        },
        body: method === 'POST'
          ? JSON.stringify({ kind: 'chat', message: 'Bonjour' })
          : undefined,
      }),
    );
    assert.equal(refused.status, 403, method);
    assert.equal(refused.headers.get('Access-Control-Allow-Origin'), null);
  }
  assert.deepEqual(calls, ['Bonjour']);

  // A preflight never carries a session; a POST without one is still refused.
  const noSession = await handle(
    new Request(URL, {
      method: 'POST',
      headers: { Origin: 'http://localhost:5000' },
      body: JSON.stringify({ kind: 'chat', message: 'Bonjour' }),
    }),
  );
  assert.equal(noSession.status, 401);
});

Deno.test('without the POLOMIX_API_KEY secret the coach is not configured', async () => {
  const { handle, calls } = setup({ configured: false });
  const response = await handle(post({ kind: 'chat', message: 'Bonjour' }));
  assert.equal(response.status, 503);
  assert.equal(await errorCode(response), 'coach_not_configured');
  assert.deepEqual(calls, []);
});

Deno.test('Polomix failures become clear, non-revealing errors', async () => {
  const cases: [PolomixResult, number, string][] = [
    [{ ok: false, failure: 'auth', status: 401 }, 502, 'coach_unavailable'],
    [{ ok: false, failure: 'quota', status: 429 }, 503, 'coach_quota_reached'],
    [{ ok: false, failure: 'rejected', status: 400 }, 502, 'coach_rejected'],
    [
      { ok: false, failure: 'unavailable', status: 500 },
      502,
      'coach_unavailable',
    ],
    [{ ok: false, failure: 'timeout' }, 504, 'coach_timeout'],
    [
      { ok: false, failure: 'bad_response', status: 200 },
      502,
      'coach_bad_response',
    ],
  ];
  for (const [result, status, code] of cases) {
    const { handle, logs } = setup({ result });
    const response = await handle(post({ kind: 'chat', message: 'Bonjour' }));
    assert.equal(response.status, status, code);
    const body = await response.json();
    assert.equal(body.error.code, code);
    assert.equal(body.reply, undefined);
    assert.equal(logs.at(-1)?.outcome, code);
  }
});

Deno.test('logs carry no message, user or token', async () => {
  const { handle, logs } = setup();
  await handle(post({ kind: 'chat', message: 'Message très personnel' }));
  await handle(post({ kind: 'chat', message: '' }));
  const text = JSON.stringify(logs);
  assert.equal(logs.length, 2);
  for (const secret of ['personnel', 'user-1', VALID_TOKEN]) {
    assert.equal(text.includes(secret), false, secret);
  }
});

Deno.test('excessive calls are limited per user and announce a retry delay', async () => {
  const limiter = new InMemoryRateLimiter({
    perMinute: 2,
    perHour: 10,
    concurrent: 1,
  });
  const { handle, calls } = setup({ limiter });
  for (let i = 0; i < 2; i++) {
    assert.equal(
      (await handle(post({ kind: 'chat', message: 'Bonjour' }))).status,
      200,
    );
  }
  const limited = await handle(post({ kind: 'chat', message: 'Bonjour' }));
  assert.equal(limited.status, 429);
  assert.equal(await errorCode(limited), 'rate_limited');
  assert.ok(Number(limited.headers.get('Retry-After')) >= 1);
  assert.equal(calls.length, 2);
});
