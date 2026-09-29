#!/usr/bin/env bash
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="${1:-run}"
case "$MODE" in run|--debug|--logs|--telemetry|--verify) ;; *) echo "Usage: $0 [--debug|--logs|--telemetry|--verify]" >&2; exit 2 ;; esac
cd "$TASK_ROOT"
# Ask this app to quit so the current draft is saved before replacing the build.
if pgrep -x Teleprompter >/dev/null; then
  pkill -TERM -x Teleprompter || true
  for attempt in {1..20}; do pgrep -x Teleprompter >/dev/null || break; sleep 0.1; done
fi
mkdir -p build
if ! xcodebuild -project Teleprompter.xcodeproj -scheme Teleprompter -configuration Debug -derivedDataPath build -destination 'platform=macOS,arch=arm64' build > build/build.log 2>&1; then
  tail -80 build/build.log
  exit 1
fi
APP_BUNDLE="$TASK_ROOT/build/Build/Products/Debug/Teleprompter.app"
if [ "$MODE" = --debug ]; then exec lldb -- "$APP_BUNDLE/Contents/MacOS/Teleprompter"; fi
open -n "$APP_BUNDLE"
case "$MODE" in
  --verify) sleep 1; pgrep -x Teleprompter; echo "Teleprompter built and launched." ;;
  --logs) exec /usr/bin/log stream --info --style compact --predicate 'process == "Teleprompter"' ;;
  --telemetry) exec /usr/bin/log stream --info --style compact --predicate 'subsystem == "com.bitl8byteshort.Teleprompter"' ;;
esac
