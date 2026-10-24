// CORS for the Flutter web build. Mobile apps send no `Origin` header and are
// not affected. CORS is not an authentication mechanism: every POST still
// needs a valid user session.

/** Web origins allowed by default (local development, see README.md). */
export const DEFAULT_ALLOWED_ORIGINS = ['http://localhost:5000'];

/**
 * Parses `COACH_ALLOWED_ORIGINS` (comma-separated, e.g. the published web
 * app's origin). Falls back to [DEFAULT_ALLOWED_ORIGINS] when unset.
 */
export function allowedOriginsFrom(value: string | undefined): Set<string> {
  const origins = (value ?? '')
    .split(',')
    .map((origin) => origin.trim().replace(/\/+$/, ''))
    .filter((origin) => origin.length > 0);
  return new Set(origins.length > 0 ? origins : DEFAULT_ALLOWED_ORIGINS);
}

/**
 * Headers to add for this request's `Origin`: none without an origin, `null`
 * when the origin is not allowed.
 */
export function corsHeadersFor(
  origin: string | null,
  allowed: ReadonlySet<string>,
): Record<string, string> | null {
  if (origin === null) return {};
  if (!allowed.has(origin)) return null;
  return {
    'Access-Control-Allow-Origin': origin,
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Access-Control-Allow-Headers':
      'authorization, x-client-info, apikey, content-type, x-region',
    'Access-Control-Max-Age': '600',
    Vary: 'Origin',
  };
}
