#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EXPECTED_MIN_MACOS="${EXPECTED_MIN_MACOS:-15.0}"
EXPECTED_ARCHS="${EXPECTED_ARCHS:-arm64 x86_64}"
ASSESS_DMG="${ASSESS_DMG:-${NOTARIZE:-0}}"
REQUIRE_NOTARIZED="${REQUIRE_NOTARIZED:-${NOTARIZE:-0}}"
EVIDENCE_DIR="${EVIDENCE_DIR:-$ROOT/build/ReleaseEvidence/dmg}"

cd "$ROOT"

chmod +x Scripts/package-dmg.sh
DMG_PATH="$(Scripts/package-dmg.sh | tail -n 1)"

if [[ -z "$DMG_PATH" || ! -f "$DMG_PATH" ]]; then
  echo "error: DMG was not produced." >&2
  exit 1
fi

VALIDATE_ARGS=(
  --dmg "$DMG_PATH"
  --expected-min-macos "$EXPECTED_MIN_MACOS"
  --expected-archs "$EXPECTED_ARCHS"
  --evidence-dir "$EVIDENCE_DIR"
)

if [[ "$REQUIRE_NOTARIZED" == "1" ]]; then
  VALIDATE_ARGS+=(--require-notarized)
fi

ASSESS_DMG="$ASSESS_DMG" Scripts/validate-public-dmg.sh "${VALIDATE_ARGS[@]}"

echo "$DMG_PATH"
