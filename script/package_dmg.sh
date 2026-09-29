#!/usr/bin/env bash
set -euo pipefail

TASK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGING_ROOT="$TASK_ROOT/build/packaging"
DIST_ROOT="$TASK_ROOT/dist"
APP_BUNDLE=""
case "${1:-}" in
  "") ;;
  --app)
    [ "$#" -eq 2 ] || { echo 'Usage: package_dmg.sh [--app /path/to/Teleprompter.app]' >&2; exit 2; }
    APP_BUNDLE="$(cd "$(dirname "$2")" && pwd)/$(basename "$2")"
    ;;
  *) echo 'Usage: package_dmg.sh [--app /path/to/Teleprompter.app]' >&2; exit 2 ;;
esac
mkdir -p "$PACKAGING_ROOT" "$DIST_ROOT"

run_logged() {
  local log_file="$1"
  shift
  if ! "$@" > "$log_file" 2>&1; then
    tail -60 "$log_file"
    return 1
  fi
}

if [ -z "$APP_BUNDLE" ]; then
  echo 'Archiving the Release app...'
  run_logged "$PACKAGING_ROOT/archive.log" xcodebuild \
    -project "$TASK_ROOT/Teleprompter.xcodeproj" -scheme Teleprompter \
    -configuration Release -derivedDataPath "$TASK_ROOT/build" \
    -destination 'generic/platform=macOS' \
    -archivePath "$PACKAGING_ROOT/Teleprompter.xcarchive" archive

  echo 'Exporting with Developer ID signing through the Xcode account...'
  run_logged "$PACKAGING_ROOT/export.log" xcodebuild -exportArchive \
    -archivePath "$PACKAGING_ROOT/Teleprompter.xcarchive" \
    -exportOptionsPlist "$TASK_ROOT/script/ExportOptions.plist" \
    -exportPath "$PACKAGING_ROOT/export" -allowProvisioningUpdates
  APP_BUNDLE="$PACKAGING_ROOT/export/Teleprompter.app"

  python3 - "$TASK_ROOT/script/ExportOptions.plist" "$PACKAGING_ROOT/NotarizeOptions.plist" <<'PY'
import plistlib
import sys
from pathlib import Path
options = plistlib.loads(Path(sys.argv[1]).read_bytes())
options['destination'] = 'upload'
Path(sys.argv[2]).write_bytes(plistlib.dumps(options))
PY
  echo 'Submitting to Apple for notarization...'
  run_logged "$PACKAGING_ROOT/notarize.log" xcodebuild -exportArchive \
    -archivePath "$PACKAGING_ROOT/Teleprompter.xcarchive" \
    -exportOptionsPlist "$PACKAGING_ROOT/NotarizeOptions.plist" \
    -allowProvisioningUpdates

  # Upload completion is not notarization approval. Wait for a valid ticket.
  STAPLED=false
  for attempt in {1..30}; do
    if xcrun stapler staple "$APP_BUNDLE" > "$PACKAGING_ROOT/staple.log" 2>&1; then
      STAPLED=true
      break
    fi
    echo "Waiting for Apple's notarization ticket ($attempt/30)..."
    sleep 10
  done
  if [ "$STAPLED" != true ]; then
    cat "$PACKAGING_ROOT/staple.log"
    echo 'No notarization ticket yet. Check the archive in Xcode Organizer; no DMG was created.' >&2
    exit 1
  fi
fi

INFO_PLIST="$APP_BUNDLE/Contents/Info.plist"
IDENTIFIER=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INFO_PLIST")
[ "$IDENTIFIER" = com.bitl8byteshort.Teleprompter ] || { echo 'Expected the Teleprompter app bundle.' >&2; exit 1; }
[ "$(lipo -archs "$APP_BUNDLE/Contents/MacOS/Teleprompter")" = arm64 ] || { echo 'Expected an Apple Silicon build.' >&2; exit 1; }
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
xcrun stapler validate "$APP_BUNDLE"
spctl --assess --type execute -vv "$APP_BUNDLE"

VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")
DMG_NAME="Teleprompter-$VERSION-arm64.dmg"
DMG_PATH="$DIST_ROOT/$DMG_NAME"
STAGING_ROOT=$(mktemp -d "$PACKAGING_ROOT/dmg.XXXXXX")
trap 'rm -rf "$STAGING_ROOT"' EXIT
ditto "$APP_BUNDLE" "$STAGING_ROOT/Teleprompter.app"
ln -s /Applications "$STAGING_ROOT/Applications"
cat > "$STAGING_ROOT/Install.txt" <<'TXT'
Install Teleprompter

1. Drag Teleprompter.app into Applications.
2. Eject this disk image.
3. Open Teleprompter from Applications.

Requires macOS 26 or later and Apple Silicon. Keep the MacBook display open.
The app inside this disk image is Developer ID signed and notarized by Apple.

Apple Speech is the default voice engine. Optional models download inside the
app. Your scripts and settings stay on this Mac; microphone audio is never saved.

The repository and releases are private:
https://github.com/BitL8-ByteShort/Teleprompter
TXT
hdiutil create -volname Teleprompter -srcfolder "$STAGING_ROOT" \
  -format UDZO -fs HFS+ -ov "$DMG_PATH"
hdiutil verify "$DMG_PATH"
(cd "$DIST_ROOT" && shasum -a 256 "$DMG_NAME" > "$DMG_NAME.sha256")
echo "Created $DMG_PATH"
