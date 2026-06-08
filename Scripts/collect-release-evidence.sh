#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

FULL=0
OUTPUT="build/release-evidence.md"
LOG_DIR="build/release-evidence-logs"

usage() {
  cat <<'USAGE'
Usage:
  Scripts/collect-release-evidence.sh [--full] [--output PATH]

Runs the release checks that can be executed locally and writes a Markdown
evidence report. Logs are written under build/release-evidence-logs.

--full also runs Scripts/preflight-app-store-local.sh, which builds both apps.
Live App Store Connect checks run only when their credentials are present in the
environment.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --full)
      FULL=1
      shift
      ;;
    --output)
      OUTPUT="$2"
      shift 2
      ;;
    --help|-h)
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

mkdir -p "$LOG_DIR" "$(dirname "$OUTPUT")"
rm -f "$LOG_DIR"/*.log 2>/dev/null || true

RUN_ID="$(date -u +"%Y%m%dT%H%M%SZ")"

append() {
  printf '%s\n' "$*" >>"$OUTPUT"
}

start_report() {
  cat >"$OUTPUT" <<EOF
# BlitzRecorder Generated Release Evidence

Generated: $(date -u +"%Y-%m-%d %H:%M:%S UTC")

This report captures command results for the current workspace. It is generated
under \`build/\` so release evidence stays local unless explicitly packaged.

## Release Identity

- Version/build: \`0.1.1 / 2\`
- macOS bundle ID: \`dev.blitzreels.blitzrecorder\`
- iOS companion bundle ID: \`dev.blitzreels.blitzrecorder.camera\`
- Pricing: \`free\`
- In-app purchases: \`none\`
- Export quota: \`none\`

## Command Evidence
EOF
}

status_label() {
  case "$1" in
    0) printf 'passed' ;;
    99) printf 'pending' ;;
    *) printf 'failed' ;;
  esac
}

run_evidence() {
  local slug="$1"
  local label="$2"
  shift 2

  local log="$LOG_DIR/${RUN_ID}-${slug}.log"
  local status=0
  "$@" >"$log" 2>&1 || status=$?

  append ""
  append "### $label"
  append ""
  append "- Status: $(status_label "$status")"
  append "- Log: \`$log\`"
  append "- Command: \`$*\`"

  if [[ "$status" -ne 0 && "$status" -ne 99 ]]; then
    append ""
    append "Last log lines:"
    append ""
    append '```text'
    tail -80 "$log" >>"$OUTPUT"
    append '```'
  fi

  return "$status"
}

pending_evidence() {
  local slug="$1"
  local label="$2"
  local reason="$3"
  local log="$LOG_DIR/${RUN_ID}-${slug}.log"
  printf 'pending: %s\n' "$reason" >"$log"

  append ""
  append "### $label"
  append ""
  append "- Status: pending"
  append "- Reason: $reason"
  append "- Log: \`$log\`"
}

has_asc_credentials() {
  [[ -n "${ASC_KEY_ID:-}" && -n "${ASC_ISSUER_ID:-}" && ( -n "${ASC_PRIVATE_KEY_PATH:-}" || -n "${ASC_PRIVATE_KEY:-}" ) ]]
}

has_archives() {
  [[ -d "build/AppStoreArchives/BlitzRecorder-macOS.xcarchive" && -d "build/AppStoreArchives/BlitzRecorderCamera-iOS.xcarchive" ]]
}

start_report

failures=0

run_evidence "launch-readiness" "Launch Readiness" Scripts/validate-launch-readiness.sh || failures=$((failures + 1))
run_evidence "storekit-removal" "StoreKit Removal" Scripts/validate-storekit-local.sh || failures=$((failures + 1))
run_evidence "submission-artifacts" "Submission Artifacts" Scripts/validate-submission-artifacts.sh || failures=$((failures + 1))
pending_evidence "app-store-connect-live" "App Store Connect Live Verification" "not run; App Store Connect helpers need the free/no-IAP model before use"

if [[ "$FULL" == "1" ]]; then
  run_evidence "local-preflight" "Local Build/Test Preflight" Scripts/preflight-app-store-local.sh || failures=$((failures + 1))
else
  pending_evidence "local-preflight" "Local Build/Test Preflight" "not run; pass --full to build and test both apps"
fi

if has_asc_credentials; then
  run_evidence "app-store-connect-live" "Live App Store Connect Verification" Scripts/app-store-connect-readiness.py || failures=$((failures + 1))
else
  pending_evidence "app-store-connect-live" "Live App Store Connect Verification" "ASC_KEY_ID, ASC_ISSUER_ID, and ASC_PRIVATE_KEY_PATH/ASC_PRIVATE_KEY are not all set"
fi

if has_archives && has_asc_credentials; then
  run_evidence "submission-artifacts-strict" "Strict Submission Artifact Validation" Scripts/validate-submission-artifacts.sh --strict || failures=$((failures + 1))
elif has_archives; then
  pending_evidence "submission-artifacts-strict" "Strict Submission Artifact Validation" "archives exist, but App Store Connect credentials are missing"
else
  pending_evidence "submission-artifacts-strict" "Strict Submission Artifact Validation" "signed App Store archives are not present under build/AppStoreArchives"
fi

append ""
append "## Remaining Manual Evidence"
append ""
append "- Complete \`AppStore/AppStoreConnectManualSetup.md\` in App Store Connect."
append "- Complete \`AppStore/AppStoreQuestionnaires.md\` for age rating, export compliance, content rights, IDFA, Kids Category, and paid-content answers."
append "- Fill \`AppStore/DeviceQAChecklist.md\` after physical Mac/iPhone/iPad QA."
append "- Record legal/privacy approval for terms, privacy policy, and privacy nutrition labels."
append "- Keep account-side records, signed archive paths, QA evidence, and the final submission decision in the maintainer release archive."

append ""
append "## Result"
append ""
if [[ "$failures" -eq 0 ]]; then
  append "- Local evidence collection completed without command failures."
  echo "Release evidence written to $OUTPUT"
else
  append "- Evidence collection completed with $failures failed command(s)."
  echo "Release evidence written to $OUTPUT with $failures failed command(s)." >&2
  exit 1
fi
