#!/usr/bin/env bash
# Builds libsippier_core if needed and runs the spike app on macOS.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LIB="$ROOT/build/macos-arm64/lib/libsippier_core.dylib"
[ -f "$LIB" ] || "$ROOT/native/scripts/build.sh" macos arm64
cd "$ROOT/spike_app"
flutter run -d macos --dart-define=SIPPIER_CORE_LIB="$LIB" "$@"
