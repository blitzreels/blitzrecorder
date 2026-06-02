#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${CONFIGURATION:-release}"

cd "$ROOT"

MARKETING_VERSION="${MARKETING_VERSION:-$(awk -F '"' '/MARKETING_VERSION:/ { print $2; exit }' "$ROOT/project.yml")}"
CURRENT_PROJECT_VERSION="${CURRENT_PROJECT_VERSION:-$(awk -F '"' '/CURRENT_PROJECT_VERSION:/ { print $2; exit }' "$ROOT/project.yml")}"
DMG_ARCH_LABEL="${DMG_ARCH_LABEL:-universal}"
DMG_NAME="${DMG_NAME:-BlitzRecorder-${MARKETING_VERSION}-${CURRENT_PROJECT_VERSION}-macOS-${DMG_ARCH_LABEL}.dmg}"
DIST_DIR="$ROOT/build/Distributions"
STAGE_DIR="$ROOT/build/dmg-stage"
DMG_PATH="$DIST_DIR/$DMG_NAME"

CONFIGURATION="$CONFIG" "$ROOT/Scripts/package-app.sh" >/dev/null

rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR" "$DIST_DIR"
ditto "$ROOT/build/BlitzRecorder.app" "$STAGE_DIR/BlitzRecorder.app"

rm -f "$DMG_PATH"
hdiutil create \
  -volname BlitzRecorder \
  -srcfolder "$STAGE_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH" >/dev/null

DMG_SIGN_IDENTITY="${DMG_SIGN_IDENTITY:-$(
  security find-identity -v -p codesigning 2>/dev/null \
    | awk -F '"' '/Developer ID Application/ { print $2; exit }'
)}"

if [[ -n "$DMG_SIGN_IDENTITY" ]]; then
  codesign --force --timestamp --sign "$DMG_SIGN_IDENTITY" "$DMG_PATH" >/dev/null
elif [[ "${NOTARIZE:-0}" == "1" ]]; then
  echo "NOTARIZE=1 requires a Developer ID Application identity for DMG signing." >&2
  exit 2
fi

if [[ "${NOTARIZE:-0}" == "1" ]]; then
  if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
  elif [[ -n "${ASC_KEY_ID:-}" && -n "${ASC_ISSUER_ID:-}" && -n "${ASC_PRIVATE_KEY:-}" ]]; then
    TEMP_ROOT="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"
    PRIVATE_KEY_PATH="$(mktemp "$TEMP_ROOT/AuthKey_${ASC_KEY_ID}.XXXXXX.p8")"
    trap 'rm -f "$PRIVATE_KEY_PATH"' EXIT
    printf '%s' "$ASC_PRIVATE_KEY" >"$PRIVATE_KEY_PATH"
    xcrun notarytool submit "$DMG_PATH" \
      --key "$PRIVATE_KEY_PATH" \
      --key-id "$ASC_KEY_ID" \
      --issuer "$ASC_ISSUER_ID" \
      --wait
    rm -f "$PRIVATE_KEY_PATH"
    trap - EXIT
  else
    echo "NOTARIZE=1 requires NOTARY_PROFILE or ASC_KEY_ID, ASC_ISSUER_ID, and ASC_PRIVATE_KEY." >&2
    exit 2
  fi

  xcrun stapler staple "$DMG_PATH"
  xcrun stapler validate "$DMG_PATH"
fi

echo "$DMG_PATH"
