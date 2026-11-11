// Polomix, the user's analyst: Flutter -> this Edge Function -> Polomix ->
// Flutter.
//
// The platform JWT check is disabled for this function (config.toml) and the
// caller is verified here with `auth.getClaims`, as recommended by Supabase
// for JWT signing keys; it also lets the browser's CORS preflight through.
// Only a signed-in, non-anonymous user can reach Polomix. The user's data is
// read with the user's own session (RLS), read-only; no service_role key is
// used.

import { createClient } from '@supabase/supabase-js';
import { originPolicyFrom } from './cors.ts';
import { createCoachData } from './data.ts';
import { createHandler } from './handler.ts';
import { createPolomixClient } from './polomix.ts';
import { InMemoryRateLimiter } from './rate_limit.ts';

const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
const publicKey = publicApiKey();

const origins = originPolicyFrom(
  Deno.env.get('COACH_ALLOWED_ORIGINS'),
  Deno.env.get('COACH_LOCAL_ORIGINS'),
);
if (origins.ignored.length > 0) {
  // Counts only: the entries are not secret, but logs stay minimal.
  console.warn(JSON.stringify({
    event: 'coach_chat_config',
    ignoredOrigins: origins.ignored.length,
  }));
}

const auth = createClient(supabaseUrl, publicKey, {
  auth: { persistSession: false, autoRefreshToken: false },
}).auth;

Deno.serve(
  createHandler({
    async verifyUser(token) {
      const { data, error } = await auth.getClaims(token);
      if (error || !data) return null;
      const { sub, role, is_anonymous: anonymous } = data.claims;
      return role === 'authenticated' && typeof sub === 'string' &&
          sub.length > 0 && anonymous !== true
        ? sub
        : null;
    },
    dataFor: (token) => createCoachData(supabaseUrl, publicKey, token),
    polomix: createPolomixClient({
      apiKey: () => Deno.env.get('POLOMIX_API_KEY'),
    }),
    rateLimiter: new InMemoryRateLimiter(),
    origins,
    log: (event) => console.log(JSON.stringify(event)),
  }),
);

/** The project's public (publishable) key, injected by the platform. */
function publicApiKey(): string {
  const keys = Deno.env.get('SUPABASE_PUBLISHABLE_KEYS');
  if (keys) {
    try {
      const parsed: unknown = JSON.parse(keys);
      if (typeof parsed === 'object' && parsed !== null) {
        const key = (parsed as Record<string, unknown>)['default'];
        if (typeof key === 'string' && key.length > 0) return key;
      }
    } catch {
      // Fall back to the single-key variables below.
    }
  }
  return Deno.env.get('SUPABASE_PUBLISHABLE_KEY') ??
    Deno.env.get('SUPABASE_ANON_KEY') ?? '';
}
