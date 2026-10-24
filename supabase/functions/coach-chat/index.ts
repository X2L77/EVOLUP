// Coach IA chat: Flutter -> this Edge Function -> Polomix -> Flutter.
//
// The platform JWT check is disabled for this function (config.toml) and the
// caller is verified here with `auth.getClaims`, as recommended by Supabase
// for JWT signing keys; it also lets the browser's CORS preflight through.
// Only a signed-in, non-anonymous user can reach Polomix. No database access
// and no service_role key are used.

import { createClient } from '@supabase/supabase-js';
import { allowedOriginsFrom } from './cors.ts';
import { createHandler } from './handler.ts';
import { createPolomixClient } from './polomix.ts';
import { InMemoryRateLimiter } from './rate_limit.ts';

const auth = createClient(
  Deno.env.get('SUPABASE_URL') ?? '',
  publicApiKey(),
  { auth: { persistSession: false, autoRefreshToken: false } },
).auth;

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
    polomix: createPolomixClient({
      apiKey: () => Deno.env.get('POLOMIX_API_KEY'),
    }),
    rateLimiter: new InMemoryRateLimiter(),
    allowedOrigins: allowedOriginsFrom(Deno.env.get('COACH_ALLOWED_ORIGINS')),
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
