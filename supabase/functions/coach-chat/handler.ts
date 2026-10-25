// Request handling of the coach-chat function, independent of the Deno
// runtime: authentication, Polomix and the rate limiter are injected, so the
// whole flow is testable without a key or a deployed project.

import { chatPrompt, extractAnswer } from './answer_format.ts';
import {
  MAX_BODY_BYTES,
  parseCoachRequest,
  type RequestError,
} from './contract.ts';
import { corsHeadersFor } from './cors.ts';
import type { PolomixClient, PolomixFailure } from './polomix.ts';
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

/** What is logged: outcome and timings only, never message, user or key. */
export type LogEvent = {
  event: 'coach_chat';
  outcome: 'ok' | ErrorCode;
  upstreamStatus?: number;
  /** Polomix replied without the requested <answer> block. */
  detail?: 'answer_missing';
  durationMs: number;
};

export interface HandlerDeps {
  /** Returns the user id of a valid signed-in session, `null` otherwise. */
  verifyUser(token: string): Promise<string | null>;
  polomix: PolomixClient;
  rateLimiter: RateLimiter;
  allowedOrigins: ReadonlySet<string>;
  log?: (event: LogEvent) => void;
  now?: () => number;
}

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

export function createHandler(deps: HandlerDeps) {
  const now = deps.now ?? Date.now;

  return async function handle(request: Request): Promise<Response> {
    const started = now();
    const cors = corsHeadersFor(
      request.headers.get('Origin'),
      deps.allowedOrigins,
    );
    let upstreamStatus: number | undefined;
    let detail: LogEvent['detail'];

    const finish = (
      outcome: 'ok' | ErrorCode,
      response: Response,
    ): Response => {
      deps.log?.({
        event: 'coach_chat',
        outcome,
        ...(upstreamStatus === undefined ? {} : { upstreamStatus }),
        ...(detail === undefined ? {} : { detail }),
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

    if (cors === null) return fail('origin_not_allowed');
    if (request.method === 'OPTIONS') {
      return new Response(null, { status: 204, headers: cors });
    }
    if (request.method !== 'POST') {
      return fail('method_not_allowed', { Allow: 'POST, OPTIONS' });
    }

    const token = bearerToken(request.headers.get('Authorization'));
    const userId = token === null ? null : await safeVerify(deps, token);
    if (userId === null) return fail('unauthorized');

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

    if (!deps.polomix.isConfigured()) return fail('coach_not_configured');

    const decision = deps.rateLimiter.tryAcquire(userId, now());
    if (!decision.allowed) {
      return fail('rate_limited', {
        'Retry-After': String(decision.retryAfterSeconds),
      });
    }
    try {
      const result = await deps.polomix.chat(
        chatPrompt(parsed.request.message),
      );
      if (!result.ok) {
        upstreamStatus = result.status;
        return fail(UPSTREAM_ERROR[result.failure]);
      }
      // Only the requested answer reaches the user (answer_format.ts).
      const answer = extractAnswer(result.reply);
      if (answer === null) {
        detail = 'answer_missing';
        return fail('coach_bad_response');
      }
      return finish(
        'ok',
        json(
          { kind: 'chat', reply: answer, model: result.model },
          200,
          cors,
        ),
      );
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
