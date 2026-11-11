import assert from 'node:assert/strict';
import { MAX_BODY_BYTES, MAX_MESSAGE_LENGTH } from './contract.ts';
import { type OriginPolicy, originPolicyFrom } from './cors.ts';
import {
  createHandler,
  localToday,
  type LogEvent,
  PROBE_MESSAGE,
} from './handler.ts';
import type { PolomixClient, PolomixResult } from './polomix.ts';
import { InMemoryRateLimiter } from './rate_limit.ts';
import { FakeData } from './test_fixtures.ts';

const VALID_TOKEN = 'valid-user-token';
const URL = 'https://example.supabase.co/functions/v1/coach-chat';
// 2026-11-09 12:00 UTC.
const NOW = Date.UTC(2026, 10, 9, 12);
const PRODUCTION = 'https://app.evolup.example';

function setup(
  options: {
    configured?: boolean;
    result?: PolomixResult;
    limiter?: InMemoryRateLimiter;
    data?: FakeData;
    origins?: OriginPolicy;
  } = {},
) {
  const calls: string[] = [];
  const logs: LogEvent[] = [];
  const tokens: string[] = [];
  const data = options.data ?? new FakeData();
  const polomix: PolomixClient = {
    isConfigured: () => options.configured ?? true,
    chat: (message) => {
      calls.push(message);
      return Promise.resolve(
        options.result ?? {
          ok: true,
          reply: 'Réponse',
          model: 'chatix-25',
          tokensUsed: 3,
        },
      );
    },
  };
  const handle = createHandler({
    verifyUser: (token) =>
      Promise.resolve(token === VALID_TOKEN ? 'user-1' : null),
    dataFor: (token) => {
      tokens.push(token);
      return data;
    },
    polomix,
    rateLimiter: options.limiter ?? new InMemoryRateLimiter(),
    origins: options.origins ?? originPolicyFrom(PRODUCTION),
    log: (event) => logs.push(event),
    now: () => NOW,
  });
  return { handle, calls, logs, data, tokens };
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

const chat = (message: string) => post({ kind: 'chat', message });

async function errorCode(response: Response): Promise<string> {
  const body = await response.json();
  return body.error.code;
}

Deno.test('a question returns the real Polomix reply, as is', async () => {
  const reply = 'Bonjour !\n\nLes balises <answer> ne sont pas interprétées.';
  const { handle, calls, tokens } = setup({
    result: { ok: true, reply, model: 'chatix-25', tokensUsed: 9 },
  });
  const response = await handle(chat('  Qui es-tu ?  '));
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), {
    kind: 'chat',
    reply,
    model: 'chatix-25',
    action: null,
    context: { metrics: [], data_access: true },
  });
  assert.equal(calls.length, 1);
  assert.match(calls[0], /^Tu es Polomix/);
  assert.ok(calls[0].endsWith('Message de l’utilisateur :\nQui es-tu ?'));
  // The data is read with the caller's own session.
  assert.deepEqual(tokens, [VALID_TOKEN]);
  assert.equal(response.headers.get('Cache-Control'), 'no-store');
});

Deno.test('only the data relevant to the question is read and sent', async () => {
  const { handle, calls, data } = setup();
  const response = await handle(chat('Comment évoluent mes tractions ?'));
  const body = await response.json();
  assert.deepEqual(body.context, { metrics: ['tractions'], data_access: true });
  assert.match(calls[0], /Tractions \(Sport\)/);
  assert.match(calls[0], /30 derniers jours : 9,3 rép\./);
  // Sleep is tracked but unrelated: neither read nor sent.
  assert.doesNotMatch(calls[0], /Durée de sommeil \(/);
  assert.deepEqual(data.reads, [
    'catalog',
    'profile',
    'tracked',
    'statistics:um-tractions',
    'weeks:um-tractions',
    'days:um-tractions',
  ]);
});

Deno.test('a question about the whole gets a summary of every tracked metric', async () => {
  const { handle, calls, data } = setup();
  const body = await (await handle(chat('Fais-moi un bilan de mes données')))
    .json();
  assert.deepEqual(body.context.metrics, ['tractions', 'sommeil_duree']);
  assert.ok(data.reads.includes('overview'));
  assert.match(calls[0], /Indicateurs suivis :/);
  assert.match(
    calls[0],
    /Durée de sommeil \(Sommeil\) : aucune valeur enregistrée/,
  );
});

Deno.test("without the user's consent no personal data is read or sent", async () => {
  const data = new FakeData({
    timezone: 'Europe/Paris',
    coach_data_access: false,
  });
  const { handle, calls } = setup({ data });
  const body = await (await handle(chat('Comment évoluent mes tractions ?')))
    .json();
  assert.deepEqual(body.context, { metrics: [], data_access: false });
  assert.deepEqual(data.reads, ['catalog', 'profile']);
  assert.match(calls[0], /n’a pas autorisé Polomix/);
  assert.doesNotMatch(calls[0], /9,3/);
});

Deno.test('unreadable data: Polomix still answers, told it has no data', async () => {
  const data = new FakeData();
  data.failProfile = true;
  const { handle, calls } = setup({ data });
  const response = await handle(chat('Comment évoluent mes tractions ?'));
  assert.equal(response.status, 200);
  assert.deepEqual((await response.json()).context, {
    metrics: [],
    data_access: null,
  });
  assert.match(calls[0], /n’ont pas pu être lues/);
  assert.doesNotMatch(calls[0], /n’a pas autorisé/);
});

Deno.test('"Je viens de faire 8 tractions." opens the form, without Polomix', async () => {
  const { handle, calls, logs } = setup();
  const response = await handle(chat('Je viens de faire 8 tractions.'));
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), {
    kind: 'chat',
    reply: null,
    model: null,
    action: {
      type: 'open_metric_form',
      metric_slug: 'tractions',
      suggested_value: 8,
    },
    context: { metrics: [], data_access: null },
  });
  assert.deepEqual(calls, []);
  assert.equal(logs.at(-1)?.action, true);
});

Deno.test('forms still open when Polomix is not configured or down', async () => {
  for (
    const options of [
      { configured: false },
      { result: { ok: false, failure: 'unavailable', status: 500 } as const },
    ]
  ) {
    const { handle } = setup(options);
    const body = await (await handle(chat("J'ai dormi 7h30"))).json();
    assert.equal(body.action.metric_slug, 'sommeil_duree');
    assert.equal(body.action.suggested_value, 27000);
  }
});

Deno.test('no action for a question, a retired metric or an unreadable catalog', async () => {
  const { handle } = setup();
  for (
    const message of [
      "J'ai fait 8 tractions, c'est bien ?",
      "J'ai fait 20 minutes de gainage",
    ]
  ) {
    const body = await (await handle(chat(message))).json();
    assert.equal(body.action, null, message);
  }
  const data = new FakeData();
  data.failCatalog = true;
  const broken = setup({ data });
  const body =
    await (await broken.handle(chat('Je viens de faire 8 tractions.'))).json();
  assert.equal(body.action, null);
  assert.equal(body.reply, 'Réponse');
});

Deno.test('status tells whether the secret is set, without calling Polomix', async () => {
  for (const configured of [true, false]) {
    const { handle, calls } = setup({ configured });
    const response = await handle(post({ kind: 'status' }));
    assert.deepEqual(await response.json(), {
      kind: 'status',
      configured,
      model: 'chatix-25',
    });
    assert.deepEqual(calls, []);
  }
});

Deno.test('the compatibility probe reports each check', async () => {
  const ok = setup();
  const okBody = await (await ok.handle(post({ kind: 'probe' }))).json();
  assert.equal(okBody.ok, true);
  assert.deepEqual(okBody.checks, {
    secret: true,
    reachable: true,
    authorized: true,
    contract: true,
  });
  assert.deepEqual(ok.calls, [PROBE_MESSAGE]);

  const cases: [PolomixResult, Record<string, boolean | null>, string][] = [
    [
      { ok: false, failure: 'auth', status: 401 },
      { secret: true, reachable: true, authorized: false, contract: null },
      'coach_unavailable',
    ],
    [
      { ok: false, failure: 'bad_response', status: 200 },
      { secret: true, reachable: true, authorized: true, contract: false },
      'coach_bad_response',
    ],
    [
      { ok: false, failure: 'timeout' },
      { secret: true, reachable: false, authorized: null, contract: null },
      'coach_timeout',
    ],
    [
      { ok: false, failure: 'unavailable' },
      { secret: true, reachable: false, authorized: null, contract: null },
      'coach_unavailable',
    ],
  ];
  for (const [result, checks, error] of cases) {
    const { handle } = setup({ result });
    const body = await (await handle(post({ kind: 'probe' }))).json();
    assert.equal(body.ok, false);
    assert.deepEqual(body.checks, checks, error);
    assert.equal(body.error, error);
  }

  const unconfigured = setup({ configured: false });
  const body = await (await unconfigured.handle(post({ kind: 'probe' })))
    .json();
  assert.equal(body.ok, false);
  assert.equal(body.checks.secret, false);
  assert.equal(body.error, 'coach_not_configured');
  assert.deepEqual(unconfigured.calls, []);
});

Deno.test('requests without a valid session never reach Polomix or the data', async () => {
  const { handle, calls, tokens } = setup();
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
  assert.deepEqual(tokens, []);
});

Deno.test('a verification error is treated as an invalid session', async () => {
  const handle = createHandler({
    verifyUser: () => Promise.reject(new Error('JWKS unreachable')),
    dataFor: () => assert.fail(),
    polomix: { isConfigured: () => true, chat: () => assert.fail() },
    rateLimiter: new InMemoryRateLimiter(),
    origins: originPolicyFrom(undefined),
  });
  const response = await handle(chat('Bonjour'));
  assert.equal(response.status, 401);
});

Deno.test('invalid bodies are rejected with precise codes', async () => {
  const { handle, calls } = setup();
  const cases: [unknown, number, string][] = [
    ['{not json', 400, 'invalid_json'],
    [[1, 2], 400, 'invalid_request'],
    [{ message: 'Bonjour' }, 400, 'invalid_request'],
    [{ kind: 'task', task: 'score' }, 400, 'unsupported_kind'],
    [
      { kind: 'record', metric: 'tractions', value: 8 },
      400,
      'unsupported_kind',
    ],
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

  const longest = await handle(chat('é'.repeat(MAX_MESSAGE_LENGTH)));
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

const preflight = (origin: string) =>
  new Request(URL, {
    method: 'OPTIONS',
    headers: {
      Origin: origin,
      'Access-Control-Request-Method': 'POST',
      'Access-Control-Request-Headers':
        'authorization, x-client-info, apikey, content-type',
    },
  });

const ALLOWED_ORIGINS = [
  'http://localhost:5000',
  'http://localhost:8080',
  'http://localhost:61234',
  'http://127.0.0.1:5000',
  'http://127.0.0.1:3000',
  'http://192.168.1.42:8080', // a phone on the same Wi-Fi
  'http://10.0.0.5:5000',
  PRODUCTION,
];

Deno.test('CORS: local origins on any port and production are allowed', async () => {
  const { handle, calls } = setup({
    limiter: new InMemoryRateLimiter({
      perMinute: 100,
      perHour: 100,
      concurrent: 1,
    }),
  });
  for (const origin of ALLOWED_ORIGINS) {
    const options = await handle(preflight(origin));
    assert.equal(options.status, 204, origin);
    assert.equal(options.headers.get('Access-Control-Allow-Origin'), origin);
    assert.equal(
      options.headers.get('Access-Control-Allow-Methods'),
      'POST, OPTIONS',
    );
    for (const header of ['authorization', 'x-client-info', 'apikey']) {
      assert.match(
        options.headers.get('Access-Control-Allow-Headers') ?? '',
        new RegExp(header),
      );
    }
    assert.equal(options.headers.get('Vary'), 'Origin');

    // Signed in: the request goes through, with the CORS headers.
    const allowed = await handle(
      post({ kind: 'chat', message: 'Bonjour' }, { Origin: origin }),
    );
    assert.equal(allowed.status, 200, origin);
    assert.equal(allowed.headers.get('Access-Control-Allow-Origin'), origin);
  }
  assert.equal(calls.length, ALLOWED_ORIGINS.length);
});

Deno.test('CORS: other origins are refused before anything else', async () => {
  const { handle, calls, tokens } = setup();
  const refused = [
    'https://evil.example',
    'http://evil.example:5000',
    'http://localhost.evil.example:5000',
    'https://app.evolup.example.evil.example',
    'http://app.evolup.example', // production is https only
    'http://192.168.1.1', // a LAN address without a port: not a dev server
    'http://8.8.8.8:5000',
    'null',
  ];
  for (const origin of refused) {
    for (
      const request of [
        preflight(origin),
        post({ kind: 'status' }, { Origin: origin }),
      ]
    ) {
      const response = await handle(request);
      assert.equal(response.status, 403, `${request.method} ${origin}`);
      assert.equal(await errorCode(response), 'origin_not_allowed');
      assert.equal(response.headers.get('Access-Control-Allow-Origin'), null);
    }
  }
  assert.deepEqual(calls, []);
  assert.deepEqual(tokens, []);
});

Deno.test('CORS never replaces the session check', async () => {
  const { handle, calls } = setup();
  for (const origin of [...ALLOWED_ORIGINS, null]) {
    const headers: Record<string, string> = {
      'Content-Type': 'application/json',
    };
    if (origin !== null) headers.Origin = origin;
    for (const authorization of [undefined, 'Bearer forged-token']) {
      const response = await handle(
        new Request(URL, {
          method: 'POST',
          headers: authorization === undefined
            ? headers
            : { ...headers, Authorization: authorization },
          body: JSON.stringify({ kind: 'chat', message: 'Bonjour' }),
        }),
      );
      assert.equal(response.status, 401, `${origin} ${authorization}`);
      assert.equal(await errorCode(response), 'unauthorized');
    }
  }
  assert.deepEqual(calls, []);
});

Deno.test('native apps send no Origin: no CORS headers, session still required', async () => {
  const { handle, calls } = setup();
  const signedIn = await handle(post({ kind: 'chat', message: 'Bonjour' }));
  assert.equal(signedIn.status, 200);
  assert.equal(signedIn.headers.get('Access-Control-Allow-Origin'), null);
  assert.equal(calls.length, 1);

  const status = await handle(post({ kind: 'status' }));
  assert.equal(status.status, 200);
  assert.equal((await status.json()).kind, 'status');
});

Deno.test('COACH_LOCAL_ORIGINS=off keeps only the production origins', async () => {
  const { handle } = setup({ origins: originPolicyFrom(PRODUCTION, 'off') });
  for (const origin of ['http://localhost:5000', 'http://192.168.1.42:8080']) {
    assert.equal((await handle(preflight(origin))).status, 403, origin);
  }
  assert.equal((await handle(preflight(PRODUCTION))).status, 204);
  assert.equal((await handle(post({ kind: 'status' }))).status, 200);
});

Deno.test('without the POLOMIX_API_KEY secret a question is not answered', async () => {
  const { handle, calls } = setup({ configured: false });
  const response = await handle(chat('Bonjour'));
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
    const response = await handle(chat('Bonjour'));
    assert.equal(response.status, status, code);
    const body = await response.json();
    assert.equal(body.error.code, code);
    assert.equal(body.reply, undefined);
    assert.equal(logs.at(-1)?.outcome, code);
  }
});

Deno.test('logs carry no message, data, user or token', async () => {
  const { handle, logs } = setup();
  await handle(chat('Message très personnel sur mes tractions'));
  await handle(chat(''));
  const text = JSON.stringify(logs);
  assert.equal(logs.length, 2);
  for (
    const secret of ['personnel', 'tractions', '9,3', 'user-1', VALID_TOKEN]
  ) {
    assert.equal(text.includes(secret), false, secret);
  }
  assert.equal(logs[0].metricsSent, 1);
});

Deno.test('excessive calls are limited per user and announce a retry delay', async () => {
  const limiter = new InMemoryRateLimiter({
    perMinute: 2,
    perHour: 10,
    concurrent: 1,
  });
  const { handle, calls } = setup({ limiter });
  for (let i = 0; i < 2; i++) {
    assert.equal((await handle(chat('Bonjour'))).status, 200);
  }
  const limited = await handle(chat('Bonjour'));
  assert.equal(limited.status, 429);
  assert.equal(await errorCode(limited), 'rate_limited');
  assert.ok(Number(limited.headers.get('Retry-After')) >= 1);
  assert.equal(calls.length, 2);
});

Deno.test('"today" follows the user\'s time zone', () => {
  // 2026-11-09 23:30 UTC is already the 10th in Tokyo.
  const late = Date.UTC(2026, 10, 9, 23, 30);
  assert.equal(localToday('UTC', late), '2026-11-09');
  assert.equal(localToday('Asia/Tokyo', late), '2026-11-10');
  assert.equal(localToday('Not/AZone', late), '2026-11-09');
});
