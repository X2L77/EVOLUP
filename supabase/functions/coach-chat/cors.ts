// CORS for the Flutter web build. Native apps (Android, iOS) send no `Origin`
// header and are not affected. CORS is not an authentication mechanism: every
// POST still needs a valid user session, whatever its origin.
//
// Allowed web origins:
// - production: the exact `https://` origins listed in `COACH_ALLOWED_ORIGINS`
//   (comma-separated), e.g. the published web app;
// - local development, unless `COACH_LOCAL_ORIGINS=off`: loopback on any port
//   (`localhost`, `127.x.x.x`, `[::1]`), and private LAN IPv4 addresses
//   (10/8, 172.16/12, 192.168/16) with an explicit port, for a phone on the
//   same network reaching `flutter run -d web-server`. Without a port, a LAN
//   address is a router or device page, not a development server.
// Everything else is refused; there is no wildcard.

export interface OriginPolicy {
  /** Exact production origins (`scheme://host[:port]`). */
  readonly production: ReadonlySet<string>;
  /** Whether local development origins are allowed. */
  readonly local: boolean;
  /** Entries of `COACH_ALLOWED_ORIGINS` that were ignored. */
  readonly ignored: readonly string[];
}

/**
 * Reads the policy from `COACH_ALLOWED_ORIGINS` and `COACH_LOCAL_ORIGINS`.
 * Production entries must be plain `https://` origins (a trailing slash is
 * accepted); anything else, `*` included, is ignored.
 */
export function originPolicyFrom(
  allowedOrigins: string | undefined,
  localOrigins?: string,
): OriginPolicy {
  const production = new Set<string>();
  const ignored: string[] = [];
  for (const entry of (allowedOrigins ?? '').split(',')) {
    const value = entry.trim();
    if (value.length === 0) continue;
    const origin = productionOrigin(value);
    if (origin === null) ignored.push(value);
    else production.add(origin);
  }
  const local = (localOrigins ?? '').trim().toLowerCase() !== 'off';
  return { production, local, ignored };
}

/** Whether a browser `Origin` header value is allowed by [policy]. */
export function isAllowedOrigin(origin: string, policy: OriginPolicy): boolean {
  const url = parseOrigin(origin);
  if (url === null) return false;
  if (policy.production.has(url.origin)) return true;
  return policy.local && isLocalDevelopment(url);
}

/**
 * Headers to add for this request's `Origin`: none without an origin (native
 * apps), `null` when the origin is not allowed.
 */
export function corsHeadersFor(
  origin: string | null,
  policy: OriginPolicy,
): Record<string, string> | null {
  if (origin === null) return {};
  if (!isAllowedOrigin(origin, policy)) return null;
  return {
    'Access-Control-Allow-Origin': origin,
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Access-Control-Allow-Headers':
      'authorization, x-client-info, apikey, content-type, x-region',
    'Access-Control-Max-Age': '600',
    Vary: 'Origin',
  };
}

/**
 * A browser sends `scheme://host[:port]` in canonical form (lowercase host,
 * no default port); any other spelling, `null` included, is refused.
 */
function parseOrigin(value: string): URL | null {
  let url: URL;
  try {
    url = new URL(value);
  } catch {
    return null;
  }
  if (url.protocol !== 'http:' && url.protocol !== 'https:') return null;
  return url.origin === value ? url : null;
}

function productionOrigin(value: string): string | null {
  let url: URL;
  try {
    url = new URL(value);
  } catch {
    return null;
  }
  // `URL` accepts `*` in a host name: only letters, digits, dots and hyphens
  // (punycode included) or a bracketed IPv6 address are taken.
  const host = /^[a-z0-9.-]+$/.test(url.hostname) ||
    /^\[[0-9a-f:.]+\]$/.test(url.hostname);
  const plain = host && url.protocol === 'https:' && url.username === '' &&
    url.password === '' && url.pathname === '/' && url.search === '' &&
    url.hash === '' && !value.endsWith('?') && !value.endsWith('#');
  return plain ? url.origin : null;
}

function isLocalDevelopment(url: URL): boolean {
  const host = url.hostname;
  if (host === 'localhost' || host === '[::1]') return true;
  const ip = ipv4(host);
  if (ip === null) return false;
  if (ip[0] === 127) return true;
  const privateLan = ip[0] === 10 ||
    (ip[0] === 172 && ip[1] >= 16 && ip[1] <= 31) ||
    (ip[0] === 192 && ip[1] === 168);
  return privateLan && url.port !== '';
}

/** The four bytes of a dotted IPv4 address, as normalized by `URL`. */
function ipv4(host: string): number[] | null {
  const match = /^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/.exec(host);
  if (match === null) return null;
  const bytes = match.slice(1).map(Number);
  return bytes.every((byte) => byte <= 255) ? bytes : null;
}
