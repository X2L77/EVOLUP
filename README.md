# EVOLUP

EVOLUP is a Flutter app for building a personal sports progression journey.
Implemented so far: the first-launch sign-in screen of the build guide
(Supabase email authentication with an email code at sign-up, Google and Apple
OAuth ready to be enabled), the initial questionnaire saved to Supabase, a
home screen showing the saved profile, a floating navigation bar, and a Coach
IA chat answered by Polomix through a Supabase Edge Function (Statistiques is
a « bientôt disponible » page for now).

The living specification is [`SPEC_PROJECT.md`](SPEC_PROJECT.md).

## Architecture

- `lib/main.dart` creates the local questionnaire-draft store and, when
  configured, the Supabase client and repositories.
- `lib/app/` contains `EvolupApp`/`AppGate` (sign-in → questionnaire →
  main destinations), `shell/` (`AppShell` and the floating `EvolupNavBar`:
  Coach IA · Home · Statistiques), the logo (`evolup_logo.dart`, the only
  place that draws it) and shared visual widgets (`widgets/`: background,
  glass card, messages, button feedback, « bientôt disponible » page).
- `lib/auth/` contains the authentication repository (email, code, password
  reset, OAuth, public Auth settings), Supabase error classification by code
  and the social providers.
- `lib/data/` contains the profile model, the validated questionnaire rules
  (`profile_rules.dart`), the draft model and its local store, and the
  Supabase profile repository (the user always comes from the session).
- `lib/coach/` contains the coach repository (calls the `coach-chat` Edge
  Function with the user's session; never Polomix directly) and its error
  classification.
- `lib/features/auth/`, `lib/features/onboarding/`, `lib/features/home/`,
  `lib/features/coach/` and `lib/features/stats/` contain the screens. Flow
  logic lives in `EmailAuthController`, `QuestionnaireController` and
  `CoachController`; question widgets are in `features/onboarding/widgets/`.
- `lib/theme/evolup_theme.dart` defines the single EVOLUP dark identity used
  everywhere (colour themes are postponed to V1.1.0).
- `supabase/migrations/` contains the versioned profile schema, grants and
  row-level security policies.
- `supabase/functions/coach-chat/` is the Edge Function between the app and
  Polomix (protocol, security and future structured tasks in its
  `README.md`).

## Supabase setup

The EVOLUP project's **public** client values (project URL and publishable
key) are the defaults in
[`lib/config/supabase_config.dart`](lib/config/supabase_config.dart), so
`flutter run`, VS Code ▶️ and `flutter build` need no arguments. Optional
compile-time overrides, for example to target another project:

- `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY`, e.g.
  `--dart-define-from-file=config/supabase.local.json` (git-ignored; template
  [`config/supabase.example.json`](config/supabase.example.json)).
- `SUPABASE_AUTH_REDIRECT_URL`. By default the app uses the current page
  origin on the web and `evolup://auth-callback` on Android/iOS for OAuth
  returns and password-reset links.

- **VS Code**: Run and Debug (▶️) → « EVOLUP · Chrome » (port 5000, so the
  origin is `http://localhost:5000`) or « EVOLUP · appareil sélectionné
  (Android) ».
- **Command line**: `flutter run -d chrome --web-port=5000`;
  releases: `flutter build web --release`, `flutter build apk --release`.

Never use a `service_role` key, secret API key, OAuth client secret, or
Polomix credential in the Flutter app. The publishable key is public by
design; database authorization relies on RLS, not on hiding that key.

### Required Dashboard steps (email)

1. In **Project Settings → API Keys**, keep the `default` publishable key
   enabled (the app embeds it); if it is rotated, update
   `lib/config/supabase_config.dart`.
2. In **Authentication → Providers → Email**: keep Email enabled and
   **Confirm email** on (verified enabled on 2026-10-23), and set
   **Minimum password length** to 8 so Supabase enforces the same rule as the
   app.
3. In **Authentication → Email Templates → Confirm signup**, include the
   code variable `{{ .Token }}` (for example
   `<p>Votre code EVOLUP : <strong>{{ .Token }}</strong></p>`). Without it,
   Supabase sends a link instead of a code and the app's code step cannot be
   completed.
4. In **Authentication → URL Configuration**, allow-list the redirect URLs:
   `evolup://auth-callback` (Android/iOS) and every web origin used (for
   example `http://localhost:5000`). The Flutter client uses the PKCE flow, so
   a reset link must be opened on the same device and browser that requested
   it.
5. Supabase's built-in email service has a low hourly limit and is
   best-effort. Before real users sign up, configure **Authentication → SMTP**
   with an email provider, a domain you own and its SPF/DKIM DNS records.

### Profile table

[`20261021000000_create_athlete_profiles.sql`](supabase/migrations/20261021000000_create_athlete_profiles.sql)
creates `public.athlete_profiles` (one row per user, written when the
questionnaire is finished), its value checks, an `updated_at` trigger, and RLS:
signed-in users can only read, create and update their own row; no anonymous
access; no deletion from the app; `service_role` gets no privileges on it.

It was **applied** on 2026-10-24 with the Supabase CLI (`npx supabase db push
--linked`, version `20261021000000` in the remote migration history). Apply
future migrations the same way: add a file to `supabase/migrations/`, then
`npx supabase db push --linked --dry-run` before `npx supabase db push
--linked`. Never run `supabase config push`: `supabase/config.toml` holds the
CLI's local-development defaults (6-character passwords, no email
confirmation), not the project's settings.

The dashboard (Table Editor) runs as the table owner, so rows can be read and
edited there; the check constraints still apply. It is not an RLS test: RLS
was verified with simulated `anon`/`authenticated`/`service_role` requests in
rolled-back transactions and with the REST API without a session (HTTP 401).

### Google and Apple (OAuth)

The app reads `GET /auth/v1/settings` and only enables a provider button when
the provider is **enabled in Supabase** and the platform can receive the
OAuth return (web, Android, iOS). Nothing else needs to change in the code.

- **Google**: in Google Cloud, create an OAuth consent screen and an OAuth
  client of type *Web application* with the authorized redirect URI
  `https://zhvhbtqpxorhrxfgeaen.supabase.co/auth/v1/callback`. Enter its
  client ID and secret in **Supabase → Authentication → Providers → Google**
  (never in the app).
- **Apple**: requires a paid Apple Developer account: an App ID with Sign in
  with Apple, a Services ID whose return URL is the same Supabase callback,
  and a signing key used to generate the client secret (valid at most six
  months). Enter them in **Supabase → Authentication → Providers → Apple**.
  Building and testing on iOS also requires a Mac with Xcode.
- Both: allow-list the redirect URLs listed in step 4 above.

### Coach IA (Polomix)

The app sends chat messages to the `coach-chat` Edge Function with the
user's session; the function checks the session, calls Polomix with the
`POLOMIX_API_KEY` secret and returns the reply. The key never reaches the app,
Git or the logs. It was **deployed on 2026-10-25** (version 1) and answered
real messages from an Android phone; calls without a session are refused
(HTTP 401, verified). The function asks Polomix for the final answer inside an
`<answer>` block and only returns that block, because Polomix's reply can
start with the model's analysis (details in the function's `README.md`). This
is version 2, deployed on 2026-10-25: on the phone, two of three questions got
a clean answer and the third was refused (no `<answer>` block), so the model
does not follow this format reliably; the next step is open. Owner steps, in
order:

1. Create a key in Polomix (API dashboard; it is shown once) and keep it in a
   password manager, never in a file of this repository.
2. Store it as a project secret named `POLOMIX_API_KEY` in **Dashboard →
   Edge Functions → Secrets** (preferred: a key typed in a terminal command,
   e.g. `npx supabase secrets set POLOMIX_API_KEY=…`, stays in the shell
   history). For the published web app, also add `COACH_ALLOWED_ORIGINS` with
   its origin (default when unset: `http://localhost:5000`).
3. Deploy after review: `npx supabase functions deploy coach-chat --use-api`
   (`--use-api` bundles on Supabase's side, no Docker needed;
   `verify_jwt = false` is set for it in `supabase/config.toml`: the session
   is verified inside the function).
4. Test from the app, signed in, with a neutral message such as « Bonjour ».

### Local-only checks without Supabase

The app only starts in its marked unconfigured state if a build overrides the
URL or key with an empty value (`--dart-define=SUPABASE_URL=`). The forms
remain visible, but authentication is not simulated and cannot succeed. Tests
use in-memory repositories; they never contact a Supabase project or change
remote data.

## Implemented behavior

- Sign-in screen from the build guide: night-blue background with two halos
  and a dot grid, zigzag arrow logo, « Login » title, translucent glass card,
  discreet animations (skipped when the device asks for reduced motion).
- « Continuer » only signs in. « Créer un compte » is a separate action that
  calls Supabase sign-up and then asks for the code sent by email, which
  Supabase verifies (`verifyOTP`) before opening a session. A failed sign-in
  never creates an account. Messages never reveal whether an address has an
  account. Code resend is limited to once per minute.
- « Mot de passe oublié ? » sends Supabase's password-reset link.
- Google and Apple start a real OAuth sign-in when enabled in Supabase;
  otherwise they say « Non configuré » and start nothing. Cancelled or refused
  OAuth returns are shown on the sign-in screen.
- After sign-in, the profile is loaded: no profile → initial questionnaire,
  profile → home. A session alone is never treated as a completed profile.
- Questionnaire: one question per screen, « Continuer » fixed at the bottom,
  progress, back without losing answers, equipment only for home training,
  exactly as many training days as weekly sessions (2 to 7), draft kept on
  the device, single save to Supabase at the end, confirmation, then home.
  The profile can be edited from home.
- A floating translucent navigation bar (same glass as the sign-in card):
  Coach IA · Home (centered) · Statistiques. Home is the default; the other
  pages are built on first visit and kept alive; the system back action
  returns to Home; the bar clears the system bars and hides while the
  keyboard is open.
- Coach IA chat: empty state, user and coach bubbles, a loading state, one
  message at a time, clear errors with retry, Enter to send with a hardware
  keyboard (Shift+Enter for a new line) and the send key on Android/iOS,
  latest message kept in view, field kept above the keyboard. Only replies
  really received from Polomix are shown; nothing is invented on failure. The
  conversation is temporary (not saved) and each message is answered on its
  own (no history sent). No profile data is sent to Polomix.
- An explicit unavailable state for statistics; no fictional data.

## Not implemented yet

Colour themes (V1.1.0), workout tracking, exercise catalog, performance
records, statistics, quests, levels, social features, 3D models, coach
history, coach access to the sports profile, and structured AI tasks (scores,
programme proposals) remain future work.

## Verification

Run:

```powershell
flutter pub get
flutter analyze
flutter test
```

Tests cover the sign-in flow (no failed sign-in triggers a sign-up), OAuth
availability and failures, the questionnaire rules and navigation, save
errors and double submission, local drafts, session/profile routing, the
navigation bar, the coach chat (states, errors, retry, keyboard), and the
consistency between `profile_rules.dart` and the migration.

The Edge Function has its own tests (fake Polomix and session, no key, no
network), run from `supabase/functions/coach-chat/` with Deno, e.g.
`npx -y deno@2.9.6 test --no-prompt answer_format_test.ts handler_test.ts polomix_test.ts`.

Verified against the real project (2026-10-23, read-only, no account
created): an unknown address returns `invalid_credentials` and the web app
shows « Adresse e-mail ou mot de passe incorrect. ». After the migration
(2026-10-24): the profile endpoint without a session answers HTTP 401
(`42501`), and simulated requests confirm that a signed-in user only sees and
writes their own row. Not yet verified for real: email code delivery and
verification, password-reset links, OAuth providers, a full save with a real
account, and Android/iOS devices.
