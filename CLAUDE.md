# CLAUDE.md

Guidance for Claude Code when working in this repository.

## Project

EVOLUP is a Flutter app (Dart package `my_training`, imports
`package:my_training/...`): a **personal data platform**. Each user picks
metrics from a catalog controlled by EVOLUP (sport, concentration, discipline,
sleep, learning, productivity, personal development), records values by hand,
and analyses their evolution; Polomix (an external AI behind a Supabase Edge
Function) answers questions on that data and can prepare an entry form. Five
sections: Vue d'ensemble · Mes données · Statistiques · Polomix · Paramètres.
User-facing strings are in French.

## Rules (read `SPEC_PROJECT.md` before any task)

- `SPEC_PROJECT.md` is the living specification (sections numbered like the
  owner's 2026-11-09 reconstruction brief; code comments cite them). Record
  every validated decision in its journal (§19); keep undecided points
  **[Ouvert]** (§20). Do not invent features; nothing from V2 (§14: watches,
  Health Connect, sync, third-party services, file import, social).
- Never fake: no decorative button, no sample data in charts or lists, no
  invented coach reply, no simulated connection. Empty states explain why.
- The old sports vision (programme, sessions, quests, EXP, levels, score /100,
  questionnaire) is retired from the app (§13). Do not bring it back without
  a new owner decision. `public.athlete_profiles` stays in the database.
- Security: RLS on every table, tested with several identities; no secret in
  Flutter, Git or logs; private calls through Edge Functions; Polomix never
  writes user data (§10.3).
- Remote Supabase (project `zhvhbtqpxorhrxfgeaen`): read-only checks are fine;
  **every migration, function deploy, secret, account or role change needs a
  presented plan and the owner's explicit go**. Never `db reset` remotely,
  never `supabase config push` (`config.toml` holds local defaults).
- A feature is done only when tested. Report untested work as such.
- Toolchain floor: Flutter 3.32 / Dart 3.8 (Replit). Do not use newer APIs
  (e.g. `DropdownButtonFormField.initialValue`; use `LabeledDropdown`).

## Commands

```powershell
flutter pub get
flutter analyze
flutter test                                   # 126 widget/unit tests
flutter test test/entry_form_test.dart         # one file
dart format lib test

# Database: migrations on a local PostgreSQL 17 (no Docker, no remote)
cd supabase/tests/db; npm install; npm test     # 46 tests

# Edge Function (from supabase/functions/coach-chat)
npx -y deno@2.9.6 fmt --check . ; npx -y deno@2.9.6 lint .
npx -y deno@2.9.6 check *.ts
npx -y deno@2.9.6 test --no-prompt --allow-read=. *_test.ts   # 43 tests

# Remote, read-only check of pending migrations
npx supabase db push --linked --dry-run
```

Run: `flutter run -d chrome --web-port=5000` (any port works for Polomix:
`coach-chat` accepts loopback origins on every port and private LAN
addresses with a port; see its README). The EVOLUP project's public URL and
publishable key are the defaults in `lib/config/supabase_config.dart`.
The owner opens the parent folder, whose `../.vscode/launch.json` is a copy
of this repo's: keep both in sync.

## Architecture

- **Startup** (`lib/main.dart`): Supabase client, `SupabaseAuthRepository`,
  `SessionServices` (profiles, metrics, coach repositories, device time zone).
  `null` services = unconfigured; the UI handles it.
- **App** (`lib/app/evolup_app.dart`): `EvolupApp` holds the
  `SignedInSession` above the navigator (`MaterialApp.builder` →
  `SessionScope`) and builds the theme from the profile (brand theme when
  signed out). `AppGate`: password recovery → sign-in → session loading
  (profile created on first sign-in with the device's IANA zone, catalog and
  tracked metrics) → error with retry → `AppShell`.
- **Session** (`lib/app/session/`): `SignedInSession` (profile controller,
  `MetricsController`, coach repository, device time zone, current section).
  `MetricsController` holds categories, catalog, tracked metrics and every
  write; its `revision` increases when recorded data changes. Pages that load
  data use the `RevisionReload` mixin. In callbacks use `SessionScope.read`,
  in `build` `SessionScope.of`.
- **Shell** (`lib/app/shell/`): five `AppDestination`s in an `IndexedStack`
  (built on first visit, kept alive), floating glass `EvolupNavBar` (hidden
  with the keyboard), back → overview. Pages above the sections are pushed
  with `evolupRoute` (`lib/app/routes.dart`; `emphasized` for Polomix → form).
- **Data** (`lib/data/`): `LocalDate` (calendar day, no time zone),
  `metrics/metric_models.dart`, `metrics/metric_values.dart` (conversion
  display ↔ storage unit, validation, French formatting),
  `metrics/metrics_repository.dart` (PostgREST + RPC), `profile/`,
  `data_error.dart` (database error codes → French), `uuid.dart`,
  `device_timezone.dart` (`flutter_timezone`).
- **Features** (`lib/features/`): `overview/`, `data/` (Mes données, search),
  `metrics/` (metric page, navigation helpers, tiles, correction dialog,
  texts), `entry/` (`EntryController` + `MetricEntryScreen` + `ValueInput`),
  `stats/` (screen, generic `MetricChart` CustomPainter, `MetricAnalysis`,
  period/bucket selectors), `coach/` (Polomix chat, action card), `settings/`
  (profile, appearance, privacy, connections V2 notice, data management,
  `PolomixStatusCard`), `auth/` (unchanged sign-in).
- **Theme** (`lib/theme/evolup_theme.dart`): `EvolupColors` ThemeExtension
  resolved from `AppPalette` (gold, black_white, blue, violet) × `AppThemeMode`
  (dark default); widgets read `EvolupColors.of(context)`, never fixed colors.
  `EvolupBrand` = fixed night-blue identity of the sign-in screens. Logo only
  in `lib/app/evolup_logo.dart`.
- **Supabase** (`supabase/migrations/`): `profiles`, `metric_categories`,
  `metric_catalog` (+ seed), `user_metrics`, `metric_daily_aggregates`, view
  `metric_daily_values`, functions `record_metric_entry` /
  `correct_metric_day` (the only writers, SECURITY DEFINER), read functions
  `get_overview`, `get_metric_history`, `get_metric_statistics`,
  `compare_metric_periods`, `list_timezones`; helpers in schema `private`.
  Catalog changes: new migration only; never delete or redefine a tracked
  metric (retire it). Every new SQL function: `set search_path = ''`, fully
  qualified names, explicit `revoke ... from public, anon, authenticated,
  service_role` then the needed grant; add tests in `supabase/tests/db`.
- **Polomix** (`supabase/functions/coach-chat/`): `handler.ts` (flow),
  `intent.ts` (deterministic entry detection → `open_metric_form`),
  `context.ts` (prompt: rules + relevant data), `data.ts` (read-only, user
  session, header `x-evolup-actor: polomix`), `polomix.ts`, `catalog.ts`.
  The Polomix reply is shown as is (no tags, no text filters: owner's
  decision). Flutter: `lib/coach/` (`CoachReply`, `CoachAction`,
  `CoachProbe`), `lib/features/coach/`.
- **Tests**: Flutter tests use in-memory fakes (`test/support/`:
  `FakeMetricsRepository` mirrors the SQL rules, `TestWorld`, `pumpApp`,
  `pumpInSession`); they never touch Supabase. The real rules are tested on
  PostgreSQL in `supabase/tests/db`.
- **Visual checks of the web build**: headless Chrome lays pages out at
  ≥500 px wide, so phone screenshots need DevTools device emulation
  (`Emulation.setDeviceMetricsOverride`). Screens behind sign-in can be
  previewed with a temporary entry point that wires the fakes of
  `test/support/` (delete it afterwards).
