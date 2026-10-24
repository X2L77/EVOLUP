// Request contract between the EVOLUP app and this function.
//
// Every request is an envelope with a `kind`. Only `chat` exists today. Future
// structured tasks (see README.md) will get their own kind, validated by a
// server-side registry: the model never chooses which data is read.

/** Same limit as `coachMaxMessageLength` in the Flutter app. */
export const MAX_MESSAGE_LENGTH = 2000;

/** Upper bound of a request body, far above a maximal chat message. */
export const MAX_BODY_BYTES = 16 * 1024;

export type CoachRequest = { kind: 'chat'; message: string };

export type RequestError =
  | 'invalid_request'
  | 'unsupported_kind'
  | 'empty_message'
  | 'message_too_long';

export type ParsedRequest =
  | { ok: true; request: CoachRequest }
  | { ok: false; error: RequestError };

export function parseCoachRequest(body: unknown): ParsedRequest {
  if (typeof body !== 'object' || body === null || Array.isArray(body)) {
    return { ok: false, error: 'invalid_request' };
  }
  const { kind, message } = body as Record<string, unknown>;
  if (kind !== 'chat') {
    return {
      ok: false,
      error: typeof kind === 'string' ? 'unsupported_kind' : 'invalid_request',
    };
  }
  if (typeof message !== 'string') {
    return { ok: false, error: 'invalid_request' };
  }
  const trimmed = message.trim();
  if (trimmed.length === 0) return { ok: false, error: 'empty_message' };
  if (trimmed.length > MAX_MESSAGE_LENGTH) {
    return { ok: false, error: 'message_too_long' };
  }
  return { ok: true, request: { kind: 'chat', message: trimmed } };
}
