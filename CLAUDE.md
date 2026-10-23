# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

EVOLUP is a Flutter app (Dart package name `my_training`, so imports are `package:my_training/...`) for a personal sports progression journey. Implemented so far: the build-guide sign-in screen with Supabase email/password auth and email-code sign-up verification, theme preferences (4 palettes × light/dark), and a resumable 3-step athlete-profile onboarding. Workouts, stats, quests, social features and the AI coach are not implemented. The AI coach screen is deliberately an "unavailable" state, so never generate fake analysis or programs. User-facing strings are in French.

## Cahier des charges & règles du projet (à lire avant toute tâche)

- **`SPEC_PROJECT.md` est le cahier des charges vivant.** Le lire avant toute tâche, y consigner chaque décision validée (journal des décisions) et garder les points non tranchés marqués **[Ouvert]**. Il est **incomplet** : seul le « Guide de construction #1 » (sections 0–1, copie dans `../Guide_de_construcion_#1.md`) a été reçu ; le second cahier des charges, le « cahier des charges initial » et la capture de référence visuelle manquent (ne jamais prétendre avoir vu cette capture).
- **Ne coder que ce qui est noté dans le guide de construction.** Une fonctionnalité seulement nommée (programme, séances, records, score, quêtes, EXP…) n'est pas spécifiée : la définir avec le propriétaire avant de l'implémenter. Aucun ajout de périmètre sans discussion.
- **Méthode** : phases Analyse → Vérification → Planification → Préparation → Développement ; ne pas passer à la phase suivante sans validation du propriétaire. Questions posées dans l'ordre du parcours utilisateur, toujours avec une option « Autre / réponse personnalisée » ; ne pas reposer un point déjà validé. Le propriétaire décide du fonctionnel et du visuel.
- **Règles non négociables** : pas de bouton décoratif ni de donnée fictive ; ne jamais inventer performances, mesures ou intégrations ; RLS configuré **et testé** sur chaque table privée ; aucune clé secrète (dont Polomix) côté client ou dans Git, appels privés via Edge Functions ; scores/récompenses à règles explicites et testables ; compiler ne suffit pas, tester chaque fonctionnalité ; tenir `README.md` à jour.
- **Coach IA** : ne bloque jamais le reste ; si indisponible, afficher « N/A » / indisponible ; état et tests de compatibilité visibles dans les Paramètres ; toute modification de programme proposée puis validée par l'utilisateur avant enregistrement.
- **Plateformes** : Android, Web, iOS prioritaires (pas encore de dossier `ios/`) ; garder Windows/macOS possibles. Hors V1 : modèles 3D, social réel, dashboard ordinateur avancé.
- **Supabase** : configurer Supabase en même temps que le code ; le formulaire de connexion doit être utilisable dès la V1. Projet distant « EVOLUP [App] » (ref `zhvhbtqpxorhrxfgeaen`, eu-west-1), accessible via le connecteur MCP Supabase, qui gère la base mais **pas** la configuration Auth (modèles d'e-mail, longueur de mot de passe, redirections, SMTP : tableau de bord, par le propriétaire). Au 2026-10-23 : une table `public.Profiles` non versionnée, aucune migration, migration `athlete_profiles` **non appliquée**.
- **Autorisations distantes** : toute écriture (migration, schéma, données, fonctions dont `rls_auto_enable()`, RLS, utilisateurs de test, Google/Apple, secrets) exige l'accord explicite du propriétaire pour cette opération précise. Lectures (`SELECT`, advisors, `/auth/v1/settings`) autorisées. Ne pas changer `com.example.my_training` sans accord.
- **Authentification (implémentée)** : « Continuer » = connexion uniquement ; « Créer un compte » = action séparée → code e-mail vérifié par Supabase (`verifyOTP`, `OtpType.signup`) ; un échec de connexion ne déclenche **jamais** d'inscription (tests dédiés) ; messages neutres (ne jamais révéler qu'une adresse a un compte) ; Google/Apple visibles mais « Non configuré » tant que `SocialAuthConfig.verified` est vide. Parcours détaillé dans `SPEC_PROJECT.md` §1.6.

## Commands

```powershell
flutter pub get
flutter analyze                      # lints: package:flutter_lints/flutter.yaml
flutter test                         # all tests
flutter test test/widget_test.dart   # one file
flutter test --plain-name "Questionnaire saves each step"   # one test by name
```

Run with Supabase (compile-time defines; the app runs in a marked "unconfigured" state without them):

```powershell
flutter run `
  --dart-define=SUPABASE_URL=$env:SUPABASE_URL `
  --dart-define=SUPABASE_PUBLISHABLE_KEY=$env:SUPABASE_PUBLISHABLE_KEY `
  --dart-define=SUPABASE_AUTH_REDIRECT_URL=evolup://auth-callback   # optional, Android password recovery
```

Web preview (Replit/bash): `bash scripts/run-web.sh` builds `flutter build web --release --no-web-resources-cdn` and serves `build/web` on port 5000 via `scripts/serve-web.py`. It does not hot reload. The toolchain floor is Dart 3.8 / Flutter 3.32 (Replit's Nix toolchain), so don't use newer language features. `replit.md` describes an older scope (no backend auth) and is outdated.

## Architecture

- **Startup (`lib/main.dart`)**: loads `ThemeController` from `SharedPreferences`, then initializes Supabase only if `SupabaseConfig.isConfigured` (`lib/config/supabase_config.dart`, which reads `String.fromEnvironment`). Repositories are passed into `EvolupApp` as **nullable**. `null` means unconfigured, and the UI must handle that case. Only the publishable key ever goes in the client. Authorization relies on RLS.
- **Routing (`lib/app/evolup_app.dart`, `AppGate`)**: there is no router. `AppGate` is a state machine driven by `AuthRepository.userIdChanges` and `passwordRecoveryEvents`. The order is: password recovery → loading → load error → unconfigured sign-in → sign-in → onboarding (profile not `onboardingCompleted`, not `isComplete`, or being edited) → `HomeScreen`. Screens receive callbacks (`onSave`, `onSignOut`, `onThemeChanged`) instead of repositories. Async results are discarded when `userId` changed meanwhile.
- **Repository boundaries**: `AuthRepository` (`lib/auth/`), `AthleteProfileRepository` and `PreferencesStore` (`lib/data/`) are abstract interfaces with Supabase/SharedPreferences implementations. Tests replace them with in-memory fakes (`test/support/fake_auth_repository.dart`, the others in `test/widget_test.dart`). Tests never touch Supabase.
- **Sign-in screen (`lib/features/auth/`)**: `SignInScreen` is layout only; the flow lives in `EmailAuthController` (a `ChangeNotifier`: credentials step ↔ code step, busy action, failure, notice, 60 s resend cooldown). Errors are classified by Supabase error **code** in `lib/auth/auth_error.dart` (`AuthFailure`), and French strings live in `auth_messages.dart` (also `minimumPasswordLength = 8`). The screen always uses `buildAuthTheme()` (`lib/theme/auth_theme.dart`), never the user's palette. Visual pieces are in `widgets/` (`AuthBackground`, `GlassCard`, `SocialAuthButtons`); the logo is only drawn in `lib/app/evolup_logo.dart` so it can be swapped. Animations are skipped when `MediaQuery.disableAnimations` is set.
- **Theme sync**: `ThemeController` (a `ChangeNotifier` in `lib/data/preferences_store.dart`) persists locally. When signed in, palette/dark mode are also stored on the profile row (`preferred_palette`, `is_dark_mode`), and the profile's values override local ones on load. The default is dark Gold. Palettes and `ThemeData` are in `lib/theme/app_theme.dart`.
- **Profile persistence**: `AthleteProfile.toMap/fromMap` map to snake_case columns of `public.athlete_profiles`, upserted on `user_id`. Onboarding saves each step (`onboarding_step`) so drafts resume. A schema change requires a new migration in `supabase/migrations/` plus matching updates to `toMap/fromMap`. The migration enables RLS with own-row select/insert/update for `authenticated` only (no delete).
- **Password recovery**: Android declares the `evolup://auth-callback` intent filter in `AndroidManifest.xml`. The redirect URL must also be allow-listed in the Supabase Auth dashboard. `supabase_flutter` uses the PKCE flow by default, so a reset link only works on the device/browser that requested it.
- **Visual checks of the web build**: headless Chrome lays pages out at ≥500 px wide even with `--window-size=390,…`, so phone screenshots must use DevTools device emulation (`Emulation.setDeviceMetricsOverride` over `--remote-debugging-port`; Node 24 has a global `WebSocket`).
