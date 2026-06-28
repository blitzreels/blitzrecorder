#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_BUNDLE_NAME="${APP_BUNDLE_NAME:-BlitzRecorder Dev}"
APP_DISPLAY_NAME="${APP_DISPLAY_NAME:-BlitzRecorder Dev}"
PRODUCT_BUNDLE_IDENTIFIER="${PRODUCT_BUNDLE_IDENTIFIER:-dev.blitzreels.blitzrecorder.debug}"
ENTITLEMENTS_PATH="${ENTITLEMENTS_PATH:-$ROOT/BlitzRecorder.local.entitlements}"
CONFIGURATION="${CONFIGURATION:-debug}"
SKIP_DMG="${SKIP_DMG:-1}"
ENABLE_SPARKLE_UPDATES="${ENABLE_SPARKLE_UPDATES:-0}"
DIRECT_DISTRIBUTION="${DIRECT_DISTRIBUTION:-1}"

if [[ -z "${SIGN_IDENTITY:-}" ]]; then
  DEV_SIGN_IDENTITY="$(
    security find-identity -v -p codesigning 2>/dev/null \
      | awk -F '"' '/Apple Development/ { print $2; exit }'
  )"
  if [[ -n "$DEV_SIGN_IDENTITY" ]]; then
    export SIGN_IDENTITY="$DEV_SIGN_IDENTITY"
  fi
else
  export SIGN_IDENTITY
fi

export APP_BUNDLE_NAME APP_DISPLAY_NAME PRODUCT_BUNDLE_IDENTIFIER
export ENTITLEMENTS_PATH CONFIGURATION SKIP_DMG ENABLE_SPARKLE_UPDATES DIRECT_DISTRIBUTION

APP="$(Scripts/package-app.sh)"
DEST="/Applications/${APP_BUNDLE_NAME}.app"

osascript -e "tell application id \"${PRODUCT_BUNDLE_IDENTIFIER}\" to quit" >/dev/null 2>&1 || true
sleep 1
rm -rf "$DEST"
ditto "$APP" "$DEST"
open "$DEST"
open "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"

echo "$DEST"
