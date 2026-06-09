#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DMG_PATH=""
EXPECTED_MIN_MACOS="${EXPECTED_MIN_MACOS:-15.0}"
EXPECTED_ARCHS="${EXPECTED_ARCHS:-arm64 x86_64}"
EXPECTED_BUNDLE_ID="${EXPECTED_BUNDLE_ID:-dev.blitzreels.blitzrecorder}"
REQUIRE_NOTARIZED="${REQUIRE_NOTARIZED:-0}"
ASSESS_DMG="${ASSESS_DMG:-$REQUIRE_NOTARIZED}"
EVIDENCE_DIR="${EVIDENCE_DIR:-$ROOT/build/ReleaseEvidence/dmg}"
MOUNT_POINT=""

usage() {
  cat <<'USAGE'
Usage:
  Scripts/validate-public-dmg.sh --dmg PATH [options]

Options:
  --dmg PATH               DMG to validate.
  --expected-archs LIST    Space-separated expected app binary archs.
  --expected-min-macos V   Expected LSMinimumSystemVersion and Mach-O minos.
  --expected-bundle-id ID  Expected CFBundleIdentifier.
  --require-notarized      Require Gatekeeper acceptance and stapled ticket.
  --evidence-dir DIR       Directory for validation logs and metadata.
  -h, --help               Show this help.

Environment:
  EXPECTED_ARCHS           Default: arm64 x86_64
  EXPECTED_MIN_MACOS       Default: 15.0
  EXPECTED_BUNDLE_ID       Default: dev.blitzreels.blitzrecorder
  REQUIRE_NOTARIZED        Default: 0
  ASSESS_DMG               Default: REQUIRE_NOTARIZED
  EVIDENCE_DIR             Default: build/ReleaseEvidence/dmg
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dmg)
      [[ $# -ge 2 ]] || { echo "error: --dmg needs PATH" >&2; exit 2; }
      DMG_PATH="$2"
      shift 2
      ;;
    --expected-archs)
      [[ $# -ge 2 ]] || { echo "error: --expected-archs needs LIST" >&2; exit 2; }
      EXPECTED_ARCHS="$2"
      shift 2
      ;;
    --expected-min-macos)
      [[ $# -ge 2 ]] || { echo "error: --expected-min-macos needs VERSION" >&2; exit 2; }
      EXPECTED_MIN_MACOS="$2"
      shift 2
      ;;
    --expected-bundle-id)
      [[ $# -ge 2 ]] || { echo "error: --expected-bundle-id needs ID" >&2; exit 2; }
      EXPECTED_BUNDLE_ID="$2"
      shift 2
      ;;
    --require-notarized)
      REQUIRE_NOTARIZED=1
      ASSESS_DMG=1
      shift
      ;;
    --evidence-dir)
      [[ $# -ge 2 ]] || { echo "error: --evidence-dir needs DIR" >&2; exit 2; }
      EVIDENCE_DIR="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

[[ -n "$DMG_PATH" ]] || { echo "error: --dmg is required" >&2; usage >&2; exit 2; }
[[ -f "$DMG_PATH" ]] || { echo "error: DMG does not exist: $DMG_PATH" >&2; exit 1; }

cd "$ROOT"
mkdir -p "$EVIDENCE_DIR"
rm -f "$EVIDENCE_DIR"/*.log "$EVIDENCE_DIR"/metadata.json 2>/dev/null || true

DMG_PATH="$(cd "$(dirname "$DMG_PATH")" && pwd)/$(basename "$DMG_PATH")"

cleanup() {
  if [[ -n "$MOUNT_POINT" ]]; then
    hdiutil detach "$MOUNT_POINT" >"$EVIDENCE_DIR/hdiutil-detach.log" 2>&1 || true
  fi
}
trap cleanup EXIT

run_log() {
  local slug="$1"
  shift
  "$@" >"$EVIDENCE_DIR/$slug.log" 2>&1
}

capture_log() {
  local slug="$1"
  shift
  "$@" >"$EVIDENCE_DIR/$slug.log" 2>&1 || return $?
}

run_log "hdiutil-verify" hdiutil verify "$DMG_PATH"

if capture_log "dmg-codesign-display" codesign -dv "$DMG_PATH"; then
  run_log "dmg-codesign-verify" codesign --verify --verbose=2 "$DMG_PATH"
else
  if [[ "$REQUIRE_NOTARIZED" == "1" ]]; then
    echo "error: release DMG is not signed: $DMG_PATH" >&2
    exit 1
  fi
  printf 'unsigned DMG accepted for non-release validation\n' >"$EVIDENCE_DIR/dmg-codesign-verify.log"
fi

if [[ "$ASSESS_DMG" == "1" ]]; then
  run_log "spctl-open-assessment" spctl -a -t open --context context:primary-signature -v "$DMG_PATH"
fi

if [[ "$REQUIRE_NOTARIZED" == "1" ]]; then
  run_log "stapler-validate-dmg" xcrun stapler validate "$DMG_PATH"
fi

run_log "hdiutil-attach" hdiutil attach "$DMG_PATH" -nobrowse -readonly
MOUNT_POINT="$(awk -F '\t' '/\/Volumes\// { print $NF; exit }' "$EVIDENCE_DIR/hdiutil-attach.log")"
if [[ -z "$MOUNT_POINT" ]]; then
  echo "error: unable to determine DMG mount point." >&2
  cat "$EVIDENCE_DIR/hdiutil-attach.log" >&2
  exit 1
fi

APP_PATH="$MOUNT_POINT/BlitzRecorder.app"
BINARY_PATH="$APP_PATH/Contents/MacOS/BlitzRecorder"
INFO_PLIST="$APP_PATH/Contents/Info.plist"

[[ -d "$APP_PATH" ]] || { echo "error: app is missing in DMG: $APP_PATH" >&2; exit 1; }
[[ -x "$BINARY_PATH" ]] || { echo "error: app binary is not executable: $BINARY_PATH" >&2; exit 1; }
[[ -f "$INFO_PLIST" ]] || { echo "error: Info.plist is missing: $INFO_PLIST" >&2; exit 1; }

for SUPPORT_NAME in ".background" ".VolumeIcon.icns"; do
  SUPPORT_PATH="$MOUNT_POINT/$SUPPORT_NAME"
  if [[ -e "$SUPPORT_PATH" ]]; then
    SUPPORT_FLAGS="$(stat -f '%Sf' "$SUPPORT_PATH")"
    printf '%s %s\n' "$SUPPORT_NAME" "$SUPPORT_FLAGS" >>"$EVIDENCE_DIR/dmg-support-file-flags.log"
    if [[ " $SUPPORT_FLAGS " != *" hidden "* ]]; then
      echo "error: $SUPPORT_NAME is not Finder-hidden in DMG root." >&2
      exit 1
    fi
  fi
done

run_log "app-codesign-verify" codesign --verify --deep --strict --verbose=2 "$APP_PATH"
run_log "app-codesign-display" codesign -dvv "$APP_PATH"
run_log "app-entitlements" codesign -d --entitlements :- "$APP_PATH"

ACTUAL_ARCHS="$(lipo -archs "$BINARY_PATH")"
printf '%s\n' "$ACTUAL_ARCHS" >"$EVIDENCE_DIR/app-archs.log"
for EXPECTED_ARCH in $EXPECTED_ARCHS; do
  if ! printf ' %s ' "$ACTUAL_ARCHS" | grep -q " $EXPECTED_ARCH "; then
    echo "error: $BINARY_PATH is missing architecture $EXPECTED_ARCH. Found: $ACTUAL_ARCHS" >&2
    exit 1
  fi
done

MIN_MACOS="$(plutil -extract LSMinimumSystemVersion raw "$INFO_PLIST")"
printf '%s\n' "$MIN_MACOS" >"$EVIDENCE_DIR/app-min-macos.log"
if [[ "$MIN_MACOS" != "$EXPECTED_MIN_MACOS" ]]; then
  echo "error: LSMinimumSystemVersion is $MIN_MACOS, expected $EXPECTED_MIN_MACOS." >&2
  exit 1
fi

run_log "app-vtool-build" vtool -show-build "$BINARY_PATH"
if ! grep -q "minos $EXPECTED_MIN_MACOS" "$EVIDENCE_DIR/app-vtool-build.log"; then
  echo "error: Mach-O minimum macOS is not $EXPECTED_MIN_MACOS." >&2
  cat "$EVIDENCE_DIR/app-vtool-build.log" >&2
  exit 1
fi

SHA256="$(shasum -a 256 "$DMG_PATH" | awk '{ print $1 }')"
DMG_SIZE_BYTES="$(stat -f %z "$DMG_PATH")"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST" 2>/dev/null || true)"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO_PLIST" 2>/dev/null || true)"
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INFO_PLIST" 2>/dev/null || true)"
if [[ "$BUNDLE_ID" != "$EXPECTED_BUNDLE_ID" ]]; then
  echo "error: CFBundleIdentifier is ${BUNDLE_ID:-missing}, expected $EXPECTED_BUNDLE_ID." >&2
  exit 1
fi
TEAM_ID="$(awk -F= '/^TeamIdentifier=/ { print $2; exit }' "$EVIDENCE_DIR/dmg-codesign-display.log" 2>/dev/null || true)"
XCODE_VERSION="$(xcodebuild -version 2>/dev/null | paste -sd ' ' -)"
RUNNER_UNAME="$(uname -a)"

export \
  ACTUAL_ARCHS \
  BUNDLE_ID \
  BUILD \
  DMG_PATH \
  DMG_SIZE_BYTES \
  EXPECTED_ARCHS \
  EXPECTED_BUNDLE_ID \
  EXPECTED_MIN_MACOS \
  MIN_MACOS \
  REQUIRE_NOTARIZED \
  RUNNER_UNAME \
  SHA256 \
  TEAM_ID \
  VERSION \
  XCODE_VERSION

python3 - "$EVIDENCE_DIR/metadata.json" <<PY
import json
import os
import sys

metadata = {
    "artifact": os.environ["DMG_PATH"],
    "sha256": os.environ["SHA256"],
    "sizeBytes": int(os.environ["DMG_SIZE_BYTES"]),
    "bundleIdentifier": os.environ["BUNDLE_ID"],
    "expectedBundleIdentifier": os.environ["EXPECTED_BUNDLE_ID"],
    "version": os.environ["VERSION"],
    "build": os.environ["BUILD"],
    "architectures": os.environ["ACTUAL_ARCHS"].split(),
    "expectedArchitectures": os.environ["EXPECTED_ARCHS"].split(),
    "minimumMacOS": os.environ["MIN_MACOS"],
    "expectedMinimumMacOS": os.environ["EXPECTED_MIN_MACOS"],
    "teamIdentifier": os.environ["TEAM_ID"],
    "requireNotarized": os.environ["REQUIRE_NOTARIZED"] == "1",
    "xcodeVersion": os.environ["XCODE_VERSION"],
    "runner": os.environ["RUNNER_UNAME"],
}

with open(sys.argv[1], "w", encoding="utf-8") as handle:
    json.dump(metadata, handle, indent=2, sort_keys=True)
    handle.write("\\n")
PY

echo "Validated DMG: $DMG_PATH"
echo "Evidence: $EVIDENCE_DIR"
