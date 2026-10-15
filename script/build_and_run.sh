#!/usr/bin/env bash
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="${1:-run}"
case "$MODE" in run|--debug|--logs|--telemetry|--verify) ;; *) echo "Usage: $0 [--debug|--logs|--telemetry|--verify]" >&2; exit 2 ;; esac
cd "$TASK_ROOT"
mkdir -p build
BUILD_CONFIGURATION=Release
if [ "$MODE" = --debug ]; then BUILD_CONFIGURATION=Debug; fi
if ! xcodebuild -project Teleprompter.xcodeproj -scheme Teleprompter -configuration "$BUILD_CONFIGURATION" -derivedDataPath build -destination 'platform=macOS,arch=arm64' build > build/build.log 2>&1; then
  tail -80 build/build.log
  exit 1
fi
APP_BUNDLE="$TASK_ROOT/build/Build/Products/$BUILD_CONFIGURATION/Teleprompter.app"
# Use the bundle identifier: other installed apps are also named Teleprompter.
swift "$TASK_ROOT/script/app_process.swift" stop
if [ "$MODE" = --debug ]; then exec lldb -- "$APP_BUNDLE/Contents/MacOS/Teleprompter"; fi
open -n "$APP_BUNDLE"
case "$MODE" in
  --verify) sleep 1; swift "$TASK_ROOT/script/app_process.swift" verify; echo "Teleprompter built and launched." ;;
  --logs) exec /usr/bin/log stream --info --style compact --predicate 'process == "Teleprompter"' ;;
  --telemetry) exec /usr/bin/log stream --info --style compact --predicate 'subsystem == "com.bitl8byteshort.Teleprompter"' ;;
esac
