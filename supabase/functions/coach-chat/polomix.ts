// Client of the documented Polomix "simple" endpoint (README.md):
//   POST /api/v1/chat, Authorization: Bearer <key>,
//   body {"message", "model"} -> {"reply", "tokens_used", "model"}.
// The key is read from the POLOMIX_API_KEY secret only; it is never logged,
// returned or included in an error.

export const POLOMIX_CHAT_URL = 'https://polomix-ai.netlify.app/api/v1/chat';
export const POLOMIX_MODEL = 'chatix-25';
export const POLOMIX_TIMEOUT_MS = 30_000;

/** Longest reply accepted; longer ones are treated as malformed. */
export const MAX_REPLY_LENGTH = 20_000;
const MAX_RESPONSE_BYTES = 256 * 1024;

export type PolomixFailure =
  | 'auth' // key rejected (401/403): server configuration problem
  | 'quota' // 402/429: Polomix plan or rate limit reached
  | 'rejected' // 400/413/422: Polomix refused this message
  | 'unavailable' // network error, 5xx or unexpected status
  | 'timeout'
  | 'bad_response'; // 2xx without a usable reply

export type PolomixResult =
  | { ok: true; reply: string; model: string; tokensUsed: number | null }
  | { ok: false; failure: PolomixFailure; status?: number };

export interface PolomixClient {
  isConfigured(): boolean;
  chat(message: string): Promise<PolomixResult>;
}

export interface PolomixOptions {
  /** Read on every call, so a newly set secret is picked up. */
  apiKey: () => string | undefined;
  fetch?: typeof fetch;
  timeoutMs?: number;
  url?: string;
}

export function createPolomixClient(options: PolomixOptions): PolomixClient {
  const doFetch = options.fetch ?? fetch;
  const timeoutMs = options.timeoutMs ?? POLOMIX_TIMEOUT_MS;
  const url = options.url ?? POLOMIX_CHAT_URL;
  const key = () => options.apiKey()?.trim() ?? '';

  return {
    isConfigured: () => key().length > 0,
    async chat(message) {
      const apiKey = key();
      if (apiKey.length === 0) return { ok: false, failure: 'auth' };
      let response: Response;
      try {
        response = await doFetch(url, {
          method: 'POST',
          headers: {
            Authorization: `Bearer ${apiKey}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({ message, model: POLOMIX_MODEL }),
          signal: AbortSignal.timeout(timeoutMs),
        });
      } catch (error) {
        const name = error instanceof Error ? error.name : '';
        return {
          ok: false,
          failure: name === 'TimeoutError' || name === 'AbortError'
            ? 'timeout'
            : 'unavailable',
        };
      }
      if (!response.ok) {
        await response.body?.cancel();
        return {
          ok: false,
          failure: failureForStatus(response.status),
          status: response.status,
        };
      }
      return parseReply(response);
    },
  };
}

export function failureForStatus(status: number): PolomixFailure {
  if (status === 401 || status === 403) return 'auth';
  if (status === 402 || status === 429) return 'quota';
  if (status === 400 || status === 413 || status === 422) return 'rejected';
  return 'unavailable';
}

async function parseReply(response: Response): Promise<PolomixResult> {
  const malformed: PolomixResult = {
    ok: false,
    failure: 'bad_response',
    status: response.status,
  };
  let text: string;
  try {
    text = await response.text();
  } catch (error) {
    const name = error instanceof Error ? error.name : '';
    return name === 'TimeoutError' || name === 'AbortError'
      ? { ok: false, failure: 'timeout' }
      : malformed;
  }
  if (text.length > MAX_RESPONSE_BYTES) return malformed;
  let body: unknown;
  try {
    body = JSON.parse(text);
  } catch {
    return malformed;
  }
  if (typeof body !== 'object' || body === null || Array.isArray(body)) {
    return malformed;
  }
  const { reply, model, tokens_used: tokensUsed } = body as Record<
    string,
    unknown
  >;
  if (typeof reply !== 'string') return malformed;
  const trimmed = reply.trim();
  if (trimmed.length === 0 || trimmed.length > MAX_REPLY_LENGTH) {
    return malformed;
  }
  return {
    ok: true,
    reply: trimmed,
    model: typeof model === 'string' && model.trim().length > 0
      ? model.trim()
      : POLOMIX_MODEL,
    tokensUsed: parseTokens(tokensUsed),
  };
}

/** The documentation shows `tokens_used` as a string: accept both forms. */
function parseTokens(value: unknown): number | null {
  const number = typeof value === 'number'
    ? value
    : typeof value === 'string' && /^\d+$/.test(value.trim())
    ? Number(value.trim())
    : NaN;
  return Number.isSafeInteger(number) && number >= 0 ? number : null;
}
