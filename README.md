# EVOLUP

EVOLUP is a Flutter app for building a personal sports progression journey.
Implemented so far: the first-launch sign-in screen of the build guide
(Supabase email authentication with an email code at sign-up), saved theme
preferences, and a resumable athlete-profile onboarding questionnaire.

The living specification is [`SPEC_PROJECT.md`](SPEC_PROJECT.md).

## Architecture

- `lib/main.dart` initializes local preferences and, when configured, the
  Supabase client.
- `lib/app/` contains the application gate and reusable theme-preference UI.
- `lib/auth/` contains the authentication repository boundary and Supabase
  implementation.
- `lib/data/` contains the athlete-profile model, Supabase repository, and
  local theme-preference store.
- `lib/theme/` defines the four palettes and light/dark Material themes.
- `lib/features/auth/`, `lib/features/onboarding/`, and `lib/features/home/`
  contain the entry, profile questionnaire, and post-onboarding screens.
  The sign-in flow logic is `EmailAuthController`; Supabase errors are
  classified by code in `lib/auth/auth_error.dart`.
- `lib/app/evolup_logo.dart` is the only place that draws the logo; replace
  its `build` method to swap in a final asset.
- `lib/config/social_auth_config.dart` lists the social providers that have
  been verified (none yet).
- `supabase/migrations/` contains the profile schema, grants, and row-level
  security policies.

## Supabase setup

The Flutter client requires these **public client configuration** values at
build/run time:

- `SUPABASE_URL`
- `SUPABASE_PUBLISHABLE_KEY` (the project's publishable client key)
- `SUPABASE_AUTH_REDIRECT_URL` (optional; set to a registered redirect URL to
  return password-recovery links to your app)

Pass them using Flutter's compile-time defines; for example, in PowerShell:

```powershell
flutter run `
  --dart-define=SUPABASE_URL=$env:SUPABASE_URL `
  --dart-define=SUPABASE_PUBLISHABLE_KEY=$env:SUPABASE_PUBLISHABLE_KEY
```

For Android password recovery, the app declares the custom callback
`evolup://auth-callback`. Add
`--dart-define=SUPABASE_AUTH_REDIRECT_URL=evolup://auth-callback` and that exact
URL to the Supabase Auth redirect allow list. For web, use the deployed
HTTPS origin as the redirect value and allow-list entry instead.

Never use a `service_role` key, secret API key, or Polomix credential in the
Flutter app. The publishable key is public by design; database authorization
must rely on RLS, not on hiding that key.

### Required Dashboard steps

1. In Supabase Dashboard, open **Project Settings → API Keys** and provide the
   project URL and publishable key through your local environment/build
   pipeline. Do not commit either value.
2. In **Authentication → Providers → Email**: keep Email enabled and
   **Confirm email** on (verified enabled on 2026-10-23), and set
   **Minimum password length** to 8 so Supabase enforces the same rule as the
   app.
3. In **Authentication → Email Templates → Confirm signup**, include the
   code variable `{{ .Token }}` (for example
   `<p>Votre code EVOLUP : <strong>{{ .Token }}</strong></p>`). Without it,
   Supabase sends a link instead of a code and the app's code step cannot be
   completed.
4. In **Authentication → URL Configuration**, allow-list the password-recovery
   redirect URLs: `evolup://auth-callback` (Android) and the web origin used
   for testing (for example `http://localhost:5000`). The app handles
   Supabase's password-recovery event and lets the recovery session set a new
   password. The Flutter client uses the PKCE flow, so a reset link must be
   opened on the same device and browser that requested it.
5. Supabase's built-in email service has a low hourly limit and is
   best-effort. Before real users sign up, configure **Authentication → SMTP**
   with an email provider, a domain you own and its SPF/DKIM DNS records.
6. Apply
   [`20261021000000_create_athlete_profiles.sql`](supabase/migrations/20261021000000_create_athlete_profiles.sql)
   through the Supabase CLI (`supabase db push`, after initializing and linking
   the local Supabase project) or the Dashboard SQL Editor.
   The migration creates `public.athlete_profiles`, enables RLS, revokes
   unauthenticated access and grants signed-in users only select/insert/update
   access to their own row.
   It is **not applied** on the connected project yet; until it is, a
   successful sign-in ends on the "Impossible de charger votre profil" screen.
7. Verify the migration and auth settings before using real accounts. Check
   through authenticated client requests (the SQL Editor uses an elevated role
   and is not an RLS test): two test users should each read and update only
   their own row; an insert/update that claims the other user's `user_id` must
   be rejected; unauthenticated access and deletion must be denied.

### Local-only checks without Supabase

The app starts in a clearly marked unconfigured state if the two compile-time
values are absent. The forms remain visible, but authentication is not
simulated and cannot succeed. Widget tests use in-memory test repositories;
they never contact a production project or change remote data.

## Implemented behavior

- Sign-in screen from the build guide: night-blue background with two halos
  and a dot grid, zigzag arrow logo, « Login » title, translucent glass card,
  discreet animations (skipped when the device asks for reduced motion).
- « Continuer » only signs in. « Créer un compte » is a separate action that
  calls Supabase sign-up and then asks for the code sent by email, which
  Supabase verifies (`verifyOTP`) before opening a session. A failed sign-in
  never creates an account. Messages never reveal whether an address has an
  account. Code resend is limited to once per minute.
- « Mot de passe oublié ? » sends Supabase's password-reset link; session
  restoration and sign-out.
- Google and Apple buttons are visible but labelled « Non configuré »; they
  never start a sign-in until a provider is configured and tested.
- Gold, Black & White, Blue, and Violet palettes with light and dark themes
  after sign-in (the sign-in screen keeps its own dark identity). Dark Gold is
  the default. Local preferences are restored on startup and signed-in
  profile preferences are loaded from Supabase and synchronized.
- A three-step profile questionnaire with validated required fields, optional
  height/weight and wearable preference, saved drafts, resume, and editing.
- A post-onboarding screen with profile editing and theme settings.
- An explicit unavailable state for the AI coach; no fictional analysis or
  training program is generated.

## Not implemented yet

Workout tracking, exercise catalog, performance records, statistics, quests,
levels, social features, 3D models, paid plans, and the AI coach/server
integration remain future work. Selecting a wearable only records a preference;
it does not connect or synchronize device data.

## Verification

Run:

```powershell
flutter pub get
flutter analyze
flutter test
```

Tests cover the sign-in flow (including that no failed sign-in triggers a
sign-up), error classification, validation, navigation, profile-completion
routing, and local theme persistence using fakes.

Verified against the real project (2026-10-23): a sign-in with an unknown
address returns `invalid_credentials` and the web app shows « Adresse e-mail
ou mot de passe incorrect. »; no account was created. Not yet verified for
real: email code delivery and verification (needs the dashboard steps above
and a test address from the owner), password-reset links, session restoration
after sign-up, and the profile table and its policies (migration not
applied).
