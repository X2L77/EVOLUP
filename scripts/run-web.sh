#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

flutter pub get
flutter build web --release --no-web-resources-cdn
exec python3 scripts/serve-web.py
