# Running this project on Replit

This is the imported `my_training` Flutter application. Its original Dart app
and Android, Windows, and web project structure are preserved.

## Run

Use the **Run** button / **Flutter web** workflow, or:

```sh
bash scripts/run-web.sh
```

The script resolves Flutter dependencies, creates a release web build with local
CanvasKit assets, and serves `build/web` on `0.0.0.0:5000`. The Python preview
server disables browser caching. After editing Dart code, restart the workflow
to rebuild; this release preview does not hot reload.

Replit's Nix configuration supplies Flutter 3.32.0 (Dart 3.8.0) and Python 3.
The SDK minimum is Dart 3.8 rather than the imported 3.11.4 requirement so the
existing app can compile with this toolchain. Dependency versions are locked
in `pubspec.lock`. No secrets or external services are needed for this screen.

## Verify

```sh
flutter test
flutter build web --release --no-web-resources-cdn
```

## Current scope

The app displays a welcome screen and editable email/password fields.
It has no sign-in submission, user accounts, or backend authentication.
The original fixed-position mobile layout is unchanged.
The Python server is for development preview, not a production deployment.
