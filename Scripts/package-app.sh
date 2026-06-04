#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${CONFIGURATION:-release}"
PRODUCT_NAME="BlitzRecorder"
MACOS_TRIPLE_VERSION="${MACOS_TRIPLE_VERSION:-15.0}"
DIRECT_DISTRIBUTION="${DIRECT_DISTRIBUTION:-1}"
export DIRECT_DISTRIBUTION

cd "$ROOT"

SIGN_IDENTITY="${SIGN_IDENTITY:-$(
  security find-identity -v -p codesigning 2>/dev/null \
    | awk -F '"' '/Developer ID Application/ { print $2; found=1; exit } /Apple Distribution/ && !dist { dist=$2 } /3rd Party Mac Developer Application/ && !third { third=$2 } /Apple Development/ && !dev { dev=$2 } END { if (!found && dist) print dist; else if (!found && third) print third; else if (!found && dev) print dev }'
)}"

SWIFT_BUILD_ARGS=(-c "$CONFIG" --product "$PRODUCT_NAME")
if [[ "$CONFIG" == "release" && "${APP_INTEGRITY_CHECKS:-1}" == "1" && -n "$SIGN_IDENTITY" ]]; then
  SWIFT_BUILD_ARGS+=(-Xswiftc -D -Xswiftc RELEASE_APP_INTEGRITY_CHECKS)
fi

APP="$ROOT/build/BlitzRecorder.app"
APP_BINARY="$APP/Contents/MacOS/BlitzRecorder"

APP_ARCHS="${APP_ARCHS:-}"
if [[ -z "$APP_ARCHS" && "$CONFIG" == "release" ]]; then
  APP_ARCHS="arm64 x86_64"
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"

if [[ -n "$APP_ARCHS" && "$APP_ARCHS" != "native" ]]; then
  ARCH_BINARIES=()
  for ARCH in $APP_ARCHS; do
    TRIPLE="${ARCH}-apple-macosx${MACOS_TRIPLE_VERSION}"
    echo "Building $PRODUCT_NAME for $ARCH..." >&2
    swift build "${SWIFT_BUILD_ARGS[@]}" --triple "$TRIPLE"
    ARCH_BINARY="$ROOT/.build/${ARCH}-apple-macosx/$CONFIG/$PRODUCT_NAME"
    if [[ ! -f "$ARCH_BINARY" ]]; then
      echo "error: expected $ARCH binary at $ARCH_BINARY" >&2
      exit 1
    fi
    ARCH_BINARIES+=("$ARCH_BINARY")
  done

  if [[ "${#ARCH_BINARIES[@]}" -eq 1 ]]; then
    cp "${ARCH_BINARIES[0]}" "$APP_BINARY"
  else
    lipo -create "${ARCH_BINARIES[@]}" -output "$APP_BINARY"
  fi
else
  echo "Building $PRODUCT_NAME for native host architecture..." >&2
  swift build "${SWIFT_BUILD_ARGS[@]}"
  BINARY="$ROOT/.build/$CONFIG/$PRODUCT_NAME"
  if [[ ! -f "$BINARY" ]]; then
    echo "error: expected native binary at $BINARY" >&2
    exit 1
  fi
  cp "$BINARY" "$APP_BINARY"
fi

chmod +x "$APP_BINARY"

if [[ "$DIRECT_DISTRIBUTION" == "1" ]] &&
   ! otool -l "$APP_BINARY" | grep -q '@executable_path/../Frameworks'; then
  install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP_BINARY"
fi

MARKETING_VERSION="${MARKETING_VERSION:-$(awk -F '"' '/MARKETING_VERSION:/ { print $2; exit }' "$ROOT/project.yml")}"
CURRENT_PROJECT_VERSION="${CURRENT_PROJECT_VERSION:-$(awk -F '"' '/CURRENT_PROJECT_VERSION:/ { print $2; exit }' "$ROOT/project.yml")}"
PRODUCT_BUNDLE_IDENTIFIER="${PRODUCT_BUNDLE_IDENTIFIER:-dev.blitzreels.blitzrecorder}"
sed \
  -e "s/\$(MARKETING_VERSION)/$MARKETING_VERSION/g" \
  -e "s/\$(CURRENT_PROJECT_VERSION)/$CURRENT_PROJECT_VERSION/g" \
  -e "s/\$(PRODUCT_BUNDLE_IDENTIFIER)/$PRODUCT_BUNDLE_IDENTIFIER/g" \
  "$ROOT/Info.plist" >"$APP/Contents/Info.plist"

plist_set_string() {
  /usr/libexec/PlistBuddy -c "Delete :$1" "$APP/Contents/Info.plist" >/dev/null 2>&1 || true
  /usr/libexec/PlistBuddy -c "Add :$1 string $2" "$APP/Contents/Info.plist"
}

plist_set_bool() {
  /usr/libexec/PlistBuddy -c "Delete :$1" "$APP/Contents/Info.plist" >/dev/null 2>&1 || true
  /usr/libexec/PlistBuddy -c "Add :$1 bool $2" "$APP/Contents/Info.plist"
}

plist_set_integer() {
  /usr/libexec/PlistBuddy -c "Delete :$1" "$APP/Contents/Info.plist" >/dev/null 2>&1 || true
  /usr/libexec/PlistBuddy -c "Add :$1 integer $2" "$APP/Contents/Info.plist"
}

copy_sparkle_framework() {
  local sparkle_framework
  sparkle_framework="$(
    find "$ROOT/.build/artifacts" "$ROOT/.build/checkouts" \
      -path '*/Sparkle.framework' \
      -type d \
      -print \
      -quit 2>/dev/null || true
  )"

  if [[ -z "$sparkle_framework" || ! -d "$sparkle_framework" ]]; then
    echo "error: Sparkle.framework was not found after swift build." >&2
    exit 1
  fi

  ditto "$sparkle_framework" "$APP/Contents/Frameworks/Sparkle.framework"
}

if [[ "$DIRECT_DISTRIBUTION" == "1" ]]; then
  copy_sparkle_framework

  if [[ "${ENABLE_SPARKLE_UPDATES:-1}" == "1" ]]; then
    SPARKLE_APPCAST_URL="${SPARKLE_APPCAST_URL:-https://blitzrecorder.com/appcast.xml}"
    if [[ -n "${SPARKLE_PUBLIC_ED_KEY:-}" ]]; then
      plist_set_string "SUFeedURL" "$SPARKLE_APPCAST_URL"
      plist_set_string "SUPublicEDKey" "$SPARKLE_PUBLIC_ED_KEY"
      plist_set_bool "SUEnableAutomaticChecks" "true"
      plist_set_bool "SUAutomaticallyUpdate" "true"
      plist_set_bool "SUAllowsAutomaticUpdates" "true"
      plist_set_bool "SUVerifyUpdateBeforeExtraction" "true"
      plist_set_integer "SUScheduledCheckInterval" "86400"
    else
      echo "warning: SPARKLE_PUBLIC_ED_KEY is not set; embedded Sparkle updater will stay disabled." >&2
    fi
  fi
fi

cp "$ROOT/Sources/BlitzRecorderApp/PrivacyInfo.xcprivacy" "$APP/Contents/Resources/PrivacyInfo.xcprivacy"
cp "$ROOT/Resources/CompanionAppIcon.png" "$APP/Contents/Resources/CompanionAppIcon.png"
cp "$ROOT/Resources/BlitzReelsWordmarkWhite.png" "$APP/Contents/Resources/BlitzReelsWordmarkWhite.png"
if [[ -f "$ROOT/Resources/BlitzRecorder.icns" ]]; then
  cp "$ROOT/Resources/BlitzRecorder.icns" "$APP/Contents/Resources/BlitzRecorder.icns"
else
  ICONSET="$APP/Contents/Resources/BlitzRecorder.iconset"
  swift "$ROOT/Scripts/make-icon.swift" "$ICONSET"
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/BlitzRecorder.icns"
  rm -rf "$ICONSET"
fi

if [[ -n "${ENTITLEMENTS_PATH:-}" ]]; then
  ENTITLEMENTS="$ENTITLEMENTS_PATH"
elif [[ "$DIRECT_DISTRIBUTION" == "1" ]]; then
  ENTITLEMENTS="$ROOT/BlitzRecorder.local.entitlements"
else
  ENTITLEMENTS="$ROOT/BlitzRecorder.entitlements"
fi

if [[ -n "$SIGN_IDENTITY" ]]; then
  codesign --force --deep --options runtime --entitlements "$ENTITLEMENTS" --sign "$SIGN_IDENTITY" "$APP" >/dev/null
else
  if [[ "$CONFIG" == "release" && "${ALLOW_AD_HOC_RELEASE_SIGNING:-0}" != "1" ]]; then
    echo "Release packaging requires a valid Apple code-signing identity. Set ALLOW_AD_HOC_RELEASE_SIGNING=1 only for local throwaway builds." >&2
    exit 2
  fi
  codesign --force --deep --entitlements "$ENTITLEMENTS" --sign - "$APP" >/dev/null
fi

# --- Branded DMG ----------------------------------------------------------
# Wrap the signed app in a drag-to-install disk image. Art + icon coordinates
# live in Scripts/dmg/ (regen the background with Scripts/dmg/render.sh).
# Set SKIP_DMG=1 to skip. NOTE: create-dmg drives Finder via AppleScript, so
# the first run on a machine prompts for Automation permission.
if [[ "${SKIP_DMG:-0}" != "1" ]]; then
  if command -v create-dmg >/dev/null 2>&1; then
    DMG="$ROOT/build/${PRODUCT_NAME}-${MARKETING_VERSION}.dmg"
    STAGE="$(mktemp -d)"
    cp -R "$APP" "$STAGE/${PRODUCT_NAME}.app"
    rm -f "$DMG"
    echo "Building DMG..." >&2
    if create-dmg \
        --volname "$PRODUCT_NAME" \
        --volicon "$ROOT/Resources/BlitzRecorder.icns" \
        --background "$ROOT/Resources/dmg/background.png" \
        --window-pos 200 120 \
        --window-size 660 400 \
        --icon-size 128 \
        --icon "${PRODUCT_NAME}.app" 175 185 \
        --hide-extension "${PRODUCT_NAME}.app" \
        --app-drop-link 485 185 \
        "$DMG" "$STAGE" >&2; then
      if [[ -n "$SIGN_IDENTITY" && "$SIGN_IDENTITY" != "-" ]]; then
        codesign --force --sign "$SIGN_IDENTITY" "$DMG" >/dev/null 2>&1 || true
      fi
      echo "Created DMG: $DMG" >&2
    else
      echo "warning: create-dmg failed; the signed .app is still at $APP" >&2
    fi
    rm -rf "$STAGE"
  else
    echo "note: create-dmg not installed (run: brew install create-dmg) — skipping DMG." >&2
  fi
fi

echo "$APP"
