# EVOLUP

EVOLUP is a personal data platform: each user chooses what to track in a
catalog controlled by EVOLUP (pull-ups, push-ups, running, focus time,
discipline, sleep, reading, study, tasks, meditation, mood…), records values
by hand, and follows their evolution over any period. **Polomix**, an AI
analyst, answers questions about that data and prepares entry forms; it
never records anything itself.

The living specification is [`SPEC_PROJECT.md`](SPEC_PROJECT.md); rules for
AI-assisted development are in [`CLAUDE.md`](CLAUDE.md).

## Features (V1)

- **Vue d'ensemble**: summary of what is recorded, favourite and tracked
  metrics with their latest value and the last 30 days compared with the 30
  before (only when each side has 3 recorded days), shortcuts.
- **Mes données**: search and category filters, tracked metrics, metrics
  removed from the list (history kept), the catalog. Each metric has a page
  with its statistics and recorded days (correct or delete a day).
- **Entry form**: value in the metric's unit (number, km, hours/minutes,
  score), local date (today by default, past allowed), « Valider ». Several
  entries of a day are merged into one daily aggregate (average, sum, min…
  per metric); an identical value on the same day is not counted twice.
- **Statistiques**: periods (7 days to all history), grouping by day, week or
  month computed by PostgreSQL (weighted averages), key figures, record,
  comparison with the previous period, trend, chart, and a second metric over
  the same days.
- **Polomix**: chat; with the user's consent, only the data of the metrics a
  question is about is sent. « Je viens de faire 8 tractions » opens the
  pull-ups form pre-filled with 8, to be checked and validated.
- **Paramètres**: profile and IANA time zone, palettes (Gold, Black & White,
  Blue, Violet) and dark/light mode, privacy (Polomix consent), connections
  (next version), deletion of tracking data, Polomix status and
  compatibility test, sign-out.

Not in V1: watches, Health Connect, sync, third-party services, file import,
social features, account deletion from the app.

## Architecture

```
Flutter app ──(publishable key + user session, RLS)──► Supabase PostgreSQL
     │                                                   ▲
     └──► Edge Function coach-chat ──(user session, read-only)┘
                     └──(POLOMIX_API_KEY)──► Polomix API
```

- `lib/` — Flutter app (see `CLAUDE.md` for the module map).
- `supabase/migrations/` — schema, catalog seed, RLS and functions.
- `supabase/functions/coach-chat/` — Polomix gateway
  ([README](supabase/functions/coach-chat/README.md)).
- `supabase/tests/db/` — database tests on a local PostgreSQL 17.
- `test/` — Flutter tests with in-memory fakes.

Data model: `profiles`; `metric_categories` and `metric_catalog` (read-only
reference data); `user_metrics` (metrics a user tracks); and
`metric_daily_aggregates`, with one row per tracked metric and local day
(sum, count, min, max, last value, duplicate fingerprints, idempotency keys).
Individual entries are never stored. Writes go only through
`record_metric_entry` and `correct_metric_day`.

## Prerequisites

- Flutter ≥ 3.32 (Dart ≥ 3.8); developed with Flutter 3.41.6.
- Node.js ≥ 20 (database tests, Supabase CLI through `npx`).
- Deno is not required: `npx -y deno@2.9.6 …`.
- A Supabase project (the EVOLUP one is the default).

## Install and run

```powershell
flutter pub get
flutter run -d chrome --web-port=5000
flutter build web --release        # or: flutter build apk --release
```

The EVOLUP project's **public** URL and publishable key are the defaults in
[`lib/config/supabase_config.dart`](lib/config/supabase_config.dart). To target
another project: `--dart-define-from-file=config/supabase.local.json`
(git-ignored; template `config/supabase.example.json`). Never put a
`service_role` key, secret key or Polomix key in the app.

## Supabase setup

### Database migrations

| File | Content |
| --- | --- |
| `20261021000000_create_athlete_profiles.sql` | Former questionnaire (applied 2026-10-24; kept, no longer used) |
| `20261109100000_create_profiles.sql` | `profiles`, schema `private`, time-zone check, `list_timezones()` |
| `20261109100100_create_metric_catalog.sql` | Categories and catalog, permanent definitions |
| `20261109100200_seed_metric_catalog.sql` | 7 categories, 16 metrics |
| `20261109100300_create_user_metrics_and_daily_aggregates.sql` | Tracked metrics, daily aggregates, RLS |
| `20261109100400_create_metric_functions.sql` | Entry, correction, statistics, overview |
| `20261112100000_entry_rules_and_device_today.sql` | Entries within one year, confirmed duplicates, « Jour » ≤ 365 days, `get_overview(p_today)` |

**Status: the first six migrations are applied (the five `20261109…` ones on
2026-11-09, with the owner's approval). `20261112100000` is not applied
(tested on the local PostgreSQL only); it must be applied before the app
that calls `get_overview(p_today)` is shipped.** It changes no table, column
or row: it replaces four functions (`record_metric_entry` and
`get_overview` gain a parameter with a default, so the former calls, among
them Polomix v5's `get_overview()`, keep working). Future migrations, with
the owner's approval:

```powershell
npx supabase db push --linked --dry-run   # lists pending migrations
npx supabase db push --linked             # applies them
```

Then check **Advisors → Security** in the dashboard. Never run `db reset` on
the project or `supabase config push` (`supabase/config.toml` holds local CLI
defaults).

### Dashboard (Authentication), unchanged

1. **Providers → Email**: Email and « Confirm email » on; minimum password
   length 8.
2. **Email Templates → Confirm signup**: include `{{ .Token }}` (the app asks
   for the code).
3. **URL Configuration**: allow `evolup://auth-callback` and every web origin
   (e.g. `http://localhost:5000`). Reset links use PKCE (same device and
   browser).
4. Before opening to other users: custom **SMTP**; consider enabling
   **leaked password protection** (security advisor).
5. Google / Apple: OAuth clients in Google Cloud / Apple Developer, entered in
   **Providers** (never in the app); callback
   `https://zhvhbtqpxorhrxfgeaen.supabase.co/auth/v1/callback`.

Recommended (needs approval, not done): revoke the API roles' EXECUTE on
`public.rls_auto_enable()` (security advisor, function created outside the
migrations).

### Polomix (Edge Function `coach-chat`)

Secrets (Dashboard → Edge Functions → Secrets; names only, never share
values): `POLOMIX_API_KEY` (set since 2026-10-25) and, for a published web
app, `COACH_ALLOWED_ORIGINS` (comma-separated exact `https://` origins, e.g.
`https://evolup.example`). Without it, only local development origins are
accepted: `localhost` / `127.0.0.1` on any port, and private LAN addresses
with a port (a phone on the same Wi-Fi). Android and iOS send no origin and
need nothing. Optional `COACH_LOCAL_ORIGINS=off` refuses the local origins.
CORS never replaces the session check.

v4 deployed on 2026-11-09 (function version 4), then the origin rules above
(function version 5). Redeploy **after the
migrations**, with the owner's approval:

```powershell
npx supabase functions deploy coach-chat --use-api
```

`verify_jwt = false` is set for it in `supabase/config.toml`: the function
checks the session itself. Then in the app: Paramètres → Polomix → « Tester
la compatibilité », a question, and « Je viens de faire 8 tractions ».

### Deployment order

1. Migrations (`db push`) — the new app needs these tables and, since
   2026-11-12, `get_overview(p_today)` and `record_metric_entry(…,
   p_confirm_duplicate)`.
2. `coach-chat` v4 — it reads the new tables (the deployed v3 keeps working
   for plain chat; with v3, « État » and « Tester la compatibilité » in the
   settings show an error because v3 does not know these requests).
3. Ship the app (web build / APK).

## Tests

```powershell
flutter analyze
flutter test                                # 277 tests, no network

cd supabase/tests/db
npm install
npm test                                    # 61 tests, local PostgreSQL 17.11

cd supabase/functions/coach-chat
npx -y deno@2.9.6 test --no-prompt --allow-read=. *_test.ts   # 54 tests
```

The database tests start a throwaway PostgreSQL (package `embedded-postgres`,
no Docker), apply a minimal Supabase stand-in (`supabase_stub.sql`: API
roles, `auth.uid()`, default privileges) and every migration, then test
aggregation, duplicates, idempotency, 30 simultaneous entries, dates and time
zones, weighted grouping, statistics, RLS with two users, anonymous access
and catalog protection. They never touch the remote project. Inside each
rolled-back test transaction, "today" (`private.local_today`) is pinned to
2026-11-12 12:00 UTC (`PINNED_NOW` in `harness.mjs`), so that the scenario
dates stay within the one-year entry window whatever the day the suite
runs; `{ realClock: true }` keeps the real clock. Counts verified on
2026-11-12.

Verified on 2026-11-09: `flutter build web --release` succeeds; the main
screens were checked on a 390 × 844 phone viewport (dark Blue and light
Gold). Verified on the real project after deployment: objects, grants,
anonymous access refused, calculation functions, function answers without a
session. Not verified: Android and iOS devices, a full session with a real
account (entries, statistics), Polomix v4 with the real API.
