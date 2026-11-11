// Request handling of the coach-chat function, independent of the Deno
// runtime: authentication, data access, Polomix and the rate limiter are
// injected, so the whole flow is testable without a key or a deployed
// project.

import type { CatalogMetric } from './catalog.ts';
import { buildPrompt, type CoachContext } from './context.ts';
import {
  MAX_BODY_BYTES,
  parseCoachRequest,
  type RequestError,
} from './contract.ts';
import { corsHeadersFor, type OriginPolicy } from './cors.ts';
import type { CoachData } from './data.ts';
import {
  detectEntryIntent,
  isGeneralQuestion,
  relevantMetrics,
} from './intent.ts';
import {
  POLOMIX_MODEL,
  type PolomixClient,
  type PolomixFailure,
  type PolomixResult,
} from './polomix.ts';
import type { RateLimiter } from './rate_limit.ts';

/** Stable error codes; the app turns them into French messages. */
export type ErrorCode =
  | RequestError
  | 'origin_not_allowed'
  | 'method_not_allowed'
  | 'unauthorized'
  | 'payload_too_large'
  | 'invalid_json'
  | 'rate_limited'
  | 'coach_not_configured'
  | 'coach_unavailable'
  | 'coach_quota_reached'
  | 'coach_rejected'
  | 'coach_timeout'
  | 'coach_bad_response';

/** What is logged: outcome and counts only, never message, user or key. */
export type LogEvent = {
  event: 'coach_chat';
  kind?: 'chat' | 'status' | 'probe';
  outcome: 'ok' | ErrorCode;
  action?: boolean;
  metricsSent?: number;
  upstreamStatus?: number;
  durationMs: number;
};

export interface HandlerDeps {
  /** Returns the user id of a valid signed-in session, `null` otherwise. */
  verifyUser(token: string): Promise<string | null>;
  /** Read-only data of the user owning [token] (RLS applies). */
  dataFor(token: string): CoachData;
  polomix: PolomixClient;
  rateLimiter: RateLimiter;
  /** Web origins allowed by CORS (see cors.ts); native apps send none. */
  origins: OriginPolicy;
  log?: (event: LogEvent) => void;
  now?: () => number;
}

/** Message of the compatibility test (Paramètres → Polomix). */
export const PROBE_MESSAGE =
  'Test de compatibilité EVOLUP : réponds uniquement « OK ».';

const ERROR_STATUS: Record<ErrorCode, number> = {
  invalid_request: 400,
  unsupported_kind: 400,
  empty_message: 400,
  message_too_long: 400,
  invalid_json: 400,
  unauthorized: 401,
  origin_not_allowed: 403,
  method_not_allowed: 405,
  payload_too_large: 413,
  rate_limited: 429,
  coach_unavailable: 502,
  coach_rejected: 502,
  coach_bad_response: 502,
  coach_not_configured: 503,
  coach_quota_reached: 503,
  coach_timeout: 504,
};

const ERROR_MESSAGE: Record<ErrorCode, string> = {
  invalid_request: 'Requête invalide.',
  unsupported_kind: 'Type de requête non pris en charge.',
  empty_message: 'Le message est vide.',
  message_too_long: 'Le message est trop long.',
  invalid_json: 'Requête invalide.',
  unauthorized: 'Session invalide ou expirée.',
  origin_not_allowed: 'Origine non autorisée.',
  method_not_allowed: 'Méthode non autorisée.',
  payload_too_large: 'Requête trop volumineuse.',
  rate_limited: 'Trop de messages. Réessayez dans un instant.',
  coach_unavailable: 'Le coach est indisponible.',
  coach_rejected: 'Le coach n’a pas pu traiter ce message.',
  coach_bad_response: 'Réponse du coach inutilisable.',
  coach_not_configured: 'Le coach n’est pas configuré.',
  coach_quota_reached: 'Limite d’utilisation du coach atteinte.',
  coach_timeout: 'Le coach n’a pas répondu à temps.',
};

const UPSTREAM_ERROR: Record<PolomixFailure, ErrorCode> = {
  // An invalid key is a server problem: the user sees "unavailable".
  auth: 'coach_unavailable',
  quota: 'coach_quota_reached',
  rejected: 'coach_rejected',
  unavailable: 'coach_unavailable',
  timeout: 'coach_timeout',
  bad_response: 'coach_bad_response',
};

/** "YYYY-MM-DD" in [timezone] (UTC when the zone is unknown). */
export function localToday(timezone: string, nowMs: number): string {
  const format = (zone: string) =>
    new Intl.DateTimeFormat('en-CA', {
      timeZone: zone,
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
    }).format(new Date(nowMs));
  try {
    return format(timezone);
  } catch {
    return format('UTC');
  }
}

export function addDays(isoDate: string, days: number): string {
  const [y, m, d] = isoDate.split('-').map(Number);
  return new Date(Date.UTC(y, m - 1, d + days)).toISOString().slice(0, 10);
}

/**
 * Reads only what the message is about: the metrics it names (at most 3,
 * with 30-day statistics, 12 weeks and the last 7 days), or a summary of
 * every tracked metric for a question about the whole; nothing when the
 * user has not allowed Polomix to read their data.
 */
export async function gatherContext(
  message: string,
  data: CoachData,
  catalog: CatalogMetric[],
  nowMs: number,
): Promise<CoachContext> {
  const profile = await data.profile();
  const timezone = profile?.timezone ?? 'UTC';
  const today = localToday(timezone, nowMs);
  const context: CoachContext = {
    today,
    timezone,
    dataAccess: profile?.coach_data_access === true,
    catalog,
    metrics: [],
  };
  if (!context.dataAccess) return context;

  const tracked = await data.tracked();
  const byCatalog = new Map(tracked.map((t) => [t.metric_catalog_id, t]));
  const visible = catalog.filter((m) => m.is_active || byCatalog.has(m.id));
  const relevant = relevantMetrics(message, visible, 3);
  for (const metric of relevant) {
    const t = byCatalog.get(metric.id);
    if (!t) {
      context.metrics.push({ metric, tracked: false, active: false });
      continue;
    }
    const [stats, weeks, days] = await Promise.all([
      data.statistics(t.id, addDays(today, -29), today),
      data.weeks(t.id, addDays(today, -83), today),
      data.recentDays(t.id, 7),
    ]);
    context.metrics.push({
      metric,
      tracked: true,
      active: t.is_active,
      stats,
      weeks,
      days,
    });
  }
  if (relevant.length === 0 && isGeneralQuestion(message)) {
    const overview = await data.overview();
    context.overview = (overview?.metrics ?? [])
      .filter((item) => item.is_active)
      .flatMap((item) => {
        const metric = catalog.find((m) => m.id === item.metric_catalog_id);
        return metric ? [{ metric, item }] : [];
      });
  }
  return context;
}

/** Slugs of the metrics whose user data was sent to Polomix. */
function consulted(context: CoachContext): string[] {
  if (!context.dataAccess) return [];
  return [
    ...context.metrics.filter((m) => m.tracked).map((m) => m.metric.slug),
    ...(context.overview ?? []).map((e) => e.metric.slug),
  ];
}

type ProbeChecks = {
  secret: boolean;
  reachable: boolean | null;
  authorized: boolean | null;
  contract: boolean | null;
};

function probeChecks(result: PolomixResult): ProbeChecks {
  if (result.ok) {
    return { secret: true, reachable: true, authorized: true, contract: true };
  }
  switch (result.failure) {
    case 'auth':
      return {
        secret: true,
        reachable: true,
        authorized: false,
        contract: null,
      };
    case 'quota':
      return {
        secret: true,
        reachable: true,
        authorized: true,
        contract: null,
      };
    case 'rejected':
    case 'bad_response':
      return {
        secret: true,
        reachable: true,
        authorized: true,
        contract: false,
      };
    case 'timeout':
      return {
        secret: true,
        reachable: false,
        authorized: null,
        contract: null,
      };
    case 'unavailable':
      return {
        secret: true,
        reachable: result.status !== undefined,
        authorized: null,
        contract: null,
      };
  }
}

export function createHandler(deps: HandlerDeps) {
  const now = deps.now ?? Date.now;

  return async function handle(request: Request): Promise<Response> {
    const started = now();
    const cors = corsHeadersFor(
      request.headers.get('Origin'),
      deps.origins,
    );
    const details: Partial<LogEvent> = {};

    const finish = (
      outcome: 'ok' | ErrorCode,
      response: Response,
    ): Response => {
      deps.log?.({
        event: 'coach_chat',
        ...details,
        outcome,
        durationMs: now() - started,
      });
      return response;
    };
    const fail = (code: ErrorCode, extra: Record<string, string> = {}) =>
      finish(
        code,
        json(
          { error: { code, message: ERROR_MESSAGE[code] } },
          ERROR_STATUS[code],
          { ...(cors ?? {}), ...extra },
        ),
      );
    const ok = (body: unknown) => finish('ok', json(body, 200, cors ?? {}));

    if (cors === null) return fail('origin_not_allowed');
    if (request.method === 'OPTIONS') {
      return new Response(null, { status: 204, headers: cors });
    }
    if (request.method !== 'POST') {
      return fail('method_not_allowed', { Allow: 'POST, OPTIONS' });
    }

    const token = bearerToken(request.headers.get('Authorization'));
    const userId = token === null ? null : await safeVerify(deps, token);
    if (userId === null || token === null) return fail('unauthorized');

    const declaredLength = Number(request.headers.get('Content-Length') ?? 0);
    if (declaredLength > MAX_BODY_BYTES) return fail('payload_too_large');
    const raw = await request.text();
    if (new TextEncoder().encode(raw).length > MAX_BODY_BYTES) {
      return fail('payload_too_large');
    }
    let body: unknown;
    try {
      body = JSON.parse(raw);
    } catch {
      return fail('invalid_json');
    }
    const parsed = parseCoachRequest(body);
    if (!parsed.ok) return fail(parsed.error);
    const coachRequest = parsed.request;
    details.kind = coachRequest.kind;

    if (coachRequest.kind === 'status') {
      return ok({
        kind: 'status',
        configured: deps.polomix.isConfigured(),
        model: POLOMIX_MODEL,
      });
    }

    const decision = deps.rateLimiter.tryAcquire(userId, now());
    if (!decision.allowed) {
      return fail('rate_limited', {
        'Retry-After': String(decision.retryAfterSeconds),
      });
    }
    try {
      if (coachRequest.kind === 'probe') {
        if (!deps.polomix.isConfigured()) {
          return ok({
            kind: 'probe',
            ok: false,
            model: POLOMIX_MODEL,
            latency_ms: null,
            checks: {
              secret: false,
              reachable: null,
              authorized: null,
              contract: null,
            },
            error: 'coach_not_configured',
          });
        }
        const callStarted = now();
        const result = await deps.polomix.chat(PROBE_MESSAGE);
        if (!result.ok) details.upstreamStatus = result.status;
        return ok({
          kind: 'probe',
          ok: result.ok,
          model: result.ok ? result.model : POLOMIX_MODEL,
          latency_ms: now() - callStarted,
          checks: probeChecks(result),
          error: result.ok ? null : UPSTREAM_ERROR[result.failure],
        });
      }

      const message = coachRequest.message;
      const data = deps.dataFor(token);
      let catalog: CatalogMetric[] = [];
      try {
        catalog = await data.catalog();
      } catch {
        // Without the catalog: no form action and no data, chat still works.
      }

      // A report of something just done opens its form, without Polomix:
      // the user checks and validates the value in the app.
      const action = detectEntryIntent(message, catalog);
      if (action) {
        details.action = true;
        return ok({
          kind: 'chat',
          reply: null,
          model: null,
          action,
          context: { metrics: [], data_access: null },
        });
      }

      if (!deps.polomix.isConfigured()) return fail('coach_not_configured');

      let context: CoachContext;
      try {
        context = await gatherContext(message, data, catalog, now());
      } catch {
        // Data unreadable: Polomix is told it has none rather than guessing.
        context = {
          today: localToday('UTC', now()),
          timezone: 'UTC',
          dataAccess: false,
          unavailable: true,
          catalog,
          metrics: [],
        };
      }
      const sent = consulted(context);
      details.metricsSent = sent.length;
      const result = await deps.polomix.chat(buildPrompt(message, context));
      if (!result.ok) {
        details.upstreamStatus = result.status;
        return fail(UPSTREAM_ERROR[result.failure]);
      }
      return ok({
        kind: 'chat',
        reply: result.reply,
        model: result.model,
        action: null,
        context: {
          metrics: sent,
          data_access: context.unavailable ? null : context.dataAccess,
        },
      });
    } finally {
      deps.rateLimiter.release(userId);
    }
  };
}

function bearerToken(header: string | null): string | null {
  const match = /^Bearer\s+(\S+)$/i.exec(header?.trim() ?? '');
  return match ? match[1] : null;
}

async function safeVerify(deps: HandlerDeps, token: string) {
  try {
    return await deps.verifyUser(token);
  } catch {
    return null;
  }
}

function json(
  body: unknown,
  status: number,
  headers: Record<string, string>,
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...headers,
      'Content-Type': 'application/json; charset=utf-8',
      'Cache-Control': 'no-store',
      'X-Content-Type-Options': 'nosniff',
    },
  });
}
