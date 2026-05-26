#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EXPECTED_MIN_MACOS="${EXPECTED_MIN_MACOS:-15.0}"
ASSESS_DMG="${ASSESS_DMG:-${NOTARIZE:-0}}"

cd "$ROOT"

chmod +x Scripts/package-dmg.sh
DMG_PATH="$(Scripts/package-dmg.sh | tail -n 1)"

if [[ -z "$DMG_PATH" || ! -f "$DMG_PATH" ]]; then
  echo "error: DMG was not produced." >&2
  exit 1
fi

hdiutil verify "$DMG_PATH"

if codesign -dv "$DMG_PATH" >/dev/null 2>&1; then
  codesign --verify --verbose=2 "$DMG_PATH"
fi

if [[ "$ASSESS_DMG" == "1" ]]; then
  spctl -a -t open --context context:primary-signature -v "$DMG_PATH"
fi

MOUNT_OUTPUT="$(hdiutil attach "$DMG_PATH" -nobrowse -readonly)"
echo "$MOUNT_OUTPUT"
MOUNT_POINT="$(printf '%s\n' "$MOUNT_OUTPUT" | awk -F '\t' '/\/Volumes\// { print $NF; exit }')"
if [[ -z "$MOUNT_POINT" ]]; then
  echo "error: unable to determine DMG mount point." >&2
  exit 1
fi

cleanup() {
  hdiutil detach "$MOUNT_POINT" >/dev/null || true
}
trap cleanup EXIT

APP_PATH="$MOUNT_POINT/BlitzRecorder.app"
BINARY_PATH="$APP_PATH/Contents/MacOS/BlitzRecorder"
INFO_PLIST="$APP_PATH/Contents/Info.plist"

test -x "$BINARY_PATH"

MIN_MACOS="$(plutil -extract LSMinimumSystemVersion raw "$INFO_PLIST")"
if [[ "$MIN_MACOS" != "$EXPECTED_MIN_MACOS" ]]; then
  echo "error: LSMinimumSystemVersion is $MIN_MACOS, expected $EXPECTED_MIN_MACOS." >&2
  exit 1
fi

if ! vtool -show-build "$BINARY_PATH" | grep -q "minos $EXPECTED_MIN_MACOS"; then
  echo "error: Mach-O minimum macOS is not $EXPECTED_MIN_MACOS." >&2
  vtool -show-build "$BINARY_PATH" >&2
  exit 1
fi

codesign --verify --deep --strict --verbose=2 "$APP_PATH"

if [[ "${NOTARIZE:-0}" == "1" ]]; then
  xcrun stapler validate "$DMG_PATH"
fi

echo "$DMG_PATH"
