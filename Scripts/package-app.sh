#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${CONFIGURATION:-release}"

cd "$ROOT"
swift build -c "$CONFIG"

BINARY="$ROOT/.build/$CONFIG/BlitzRecorder"
APP="$ROOT/build/BlitzRecorder.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/BlitzRecorder"

MARKETING_VERSION="${MARKETING_VERSION:-$(awk -F '"' '/MARKETING_VERSION:/ { print $2; exit }' "$ROOT/project.yml")}"
CURRENT_PROJECT_VERSION="${CURRENT_PROJECT_VERSION:-$(awk -F '"' '/CURRENT_PROJECT_VERSION:/ { print $2; exit }' "$ROOT/project.yml")}"
sed \
  -e "s/\$(MARKETING_VERSION)/$MARKETING_VERSION/g" \
  -e "s/\$(CURRENT_PROJECT_VERSION)/$CURRENT_PROJECT_VERSION/g" \
  "$ROOT/Info.plist" >"$APP/Contents/Info.plist"
cp "$ROOT/Sources/BlitzRecorderApp/PrivacyInfo.xcprivacy" "$APP/Contents/Resources/PrivacyInfo.xcprivacy"
if [[ -f "$ROOT/Resources/BlitzRecorder.icns" ]]; then
  cp "$ROOT/Resources/BlitzRecorder.icns" "$APP/Contents/Resources/BlitzRecorder.icns"
else
  ICONSET="$APP/Contents/Resources/BlitzRecorder.iconset"
  swift "$ROOT/Scripts/make-icon.swift" "$ICONSET"
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/BlitzRecorder.icns"
  rm -rf "$ICONSET"
fi

SIGN_IDENTITY="$(
  security find-identity -v -p codesigning 2>/dev/null \
    | awk -F '"' '/3rd Party Mac Developer Application/ { print $2; found=1; exit } /Apple Distribution/ && !dist { dist=$2 } /Developer ID Application/ && !devID { devID=$2 } /Apple Development/ && !dev { dev=$2 } END { if (!found && dist) print dist; else if (!found && devID) print devID; else if (!found && dev) print dev }'
)"

ENTITLEMENTS="${ENTITLEMENTS_PATH:-$ROOT/BlitzRecorder.entitlements}"

if [[ -n "$SIGN_IDENTITY" ]]; then
  codesign --force --deep --options runtime --entitlements "$ENTITLEMENTS" --sign "$SIGN_IDENTITY" "$APP" >/dev/null
else
  codesign --force --deep --entitlements "$ENTITLEMENTS" --sign - "$APP" >/dev/null
fi

echo "$APP"
