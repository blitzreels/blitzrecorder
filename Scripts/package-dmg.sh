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
NOTARY_EVIDENCE_DIR="${NOTARY_EVIDENCE_DIR:-$ROOT/build/ReleaseEvidence/notarization}"

if ! command -v create-dmg >/dev/null 2>&1; then
  echo "create-dmg is required to build the branded release DMG. Install it with: brew install create-dmg" >&2
  exit 2
fi

# Finder layout comes from Resources/dmg/dmgly.json. Arrow and wordmark are
# baked into background.png; Finder supplies the real icons and labels.
DMG_BACKGROUND="$ROOT/Resources/dmg/background.png"
[[ -f "$DMG_BACKGROUND" ]] || { echo "error: missing Dmgly background: $DMG_BACKGROUND" >&2; exit 2; }

SKIP_DMG=1 CONFIGURATION="$CONFIG" "$ROOT/Scripts/package-app.sh" >/dev/null
codesign --verify --deep --strict --verbose=2 "$ROOT/build/BlitzRecorder.app" >/dev/null

rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR" "$DIST_DIR"
ditto "$ROOT/build/BlitzRecorder.app" "$STAGE_DIR/BlitzRecorder.app"

CREATE_DMG_ARGS=(
  --volname BlitzRecorder \
  --volicon "$ROOT/Resources/BlitzRecorder.icns" \
  --background "$DMG_BACKGROUND" \
  --window-pos 200 120 \
  --window-size 760 480 \
  --icon-size 128 \
  --icon "BlitzRecorder.app" 210 228 \
  --hide-extension "BlitzRecorder.app" \
  --app-drop-link 550 228 \
  "$DMG_PATH" \
  "$STAGE_DIR"
)

rm -f "$DMG_PATH"
if ! create-dmg "${CREATE_DMG_ARGS[@]}" >&2; then
  echo "create-dmg Finder layout failed; retrying without Finder AppleScript." >&2
  rm -f "$DMG_PATH"
  if ! create-dmg --skip-jenkins "${CREATE_DMG_ARGS[@]}" >&2; then
    echo "create-dmg direct copy failed; retrying with sandbox-safe image creation." >&2
    rm -f "$DMG_PATH"
    create-dmg --sandbox-safe "${CREATE_DMG_ARGS[@]}" >&2
  fi
fi

"$ROOT/Scripts/dmg/hide-support-files.sh" "$DMG_PATH"

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

notarytool_log() {
  local submission_id="$1"
  shift

  [[ -n "$submission_id" ]] || return 0
  xcrun notarytool log "$submission_id" "$@" \
    >"$NOTARY_EVIDENCE_DIR/notarytool-log.json" \
    2>"$NOTARY_EVIDENCE_DIR/notarytool-log.stderr" || true
}

notarytool_submit_and_log() {
  local submission_id
  local status=0

  mkdir -p "$NOTARY_EVIDENCE_DIR"
  xcrun notarytool submit "$DMG_PATH" "$@" --wait --output-format json \
    >"$NOTARY_EVIDENCE_DIR/notarytool-submit.json" \
    2>"$NOTARY_EVIDENCE_DIR/notarytool-submit.stderr" || status=$?

  submission_id="$(
    python3 - "$NOTARY_EVIDENCE_DIR/notarytool-submit.json" <<'PY' || true
import json
import sys

try:
    with open(sys.argv[1], encoding="utf-8") as handle:
        data = json.load(handle)
except Exception:
    data = {}

print(data.get("id", ""))
PY
  )"

  notarytool_log "$submission_id" "$@"

  if [[ "$status" -ne 0 ]]; then
    echo "notarytool submit failed; see $NOTARY_EVIDENCE_DIR/notarytool-submit.stderr and notarytool-log.json." >&2
    exit "$status"
  fi
}

if [[ "${NOTARIZE:-0}" == "1" ]]; then
  if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    notarytool_submit_and_log --keychain-profile "$NOTARY_PROFILE"
  elif [[ -n "${ASC_KEY_ID:-}" && -n "${ASC_ISSUER_ID:-}" && -n "${ASC_PRIVATE_KEY:-}" ]]; then
    TEMP_ROOT="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"
    PRIVATE_KEY_PATH="$(mktemp "$TEMP_ROOT/AuthKey_${ASC_KEY_ID}.XXXXXX.p8")"
    trap 'rm -f "$PRIVATE_KEY_PATH"' EXIT
    printf '%s' "$ASC_PRIVATE_KEY" >"$PRIVATE_KEY_PATH"
    notarytool_submit_and_log \
      --key "$PRIVATE_KEY_PATH" \
      --key-id "$ASC_KEY_ID" \
      --issuer "$ASC_ISSUER_ID"
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
