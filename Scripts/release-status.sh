#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

FULL=0
if [[ "${1:-}" == "--full" ]]; then
  FULL=1
elif [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  cat <<'USAGE'
Usage:
  Scripts/release-status.sh [--full]

Prints a release-readiness summary for the BlitzRecorder macOS app and iOS
companion. The default mode runs the document/artifact validators. --full also
runs the local build/test preflight.

For a Markdown evidence report, run Scripts/collect-release-evidence.sh.
USAGE
  exit 0
fi

run_check() {
  local label="$1"
  shift

  printf '\n== %s ==\n' "$label"
  if "$@"; then
    printf 'status: passed\n'
  else
    printf 'status: failed\n' >&2
    return 1
  fi
}

print_pending_items() {
  cat <<'PENDING'

== External Pending Items ==
- Create/confirm macOS App Store Connect app record: dev.blitzreels.blitzrecorder
- Create/confirm iOS App Store Connect app record: dev.blitzreels.blitzrecorder.camera
- Confirm no in-app purchases, subscriptions, or export quotas are configured
- Complete AppStore/AppStoreConnectManualSetup.md while configuring App Store Connect
- Complete AppStore/AppStoreQuestionnaires.md while answering App Store Connect questionnaires
- Generate local evidence with Scripts/collect-release-evidence.sh --full before submission
- Prepare the App Store review handoff folder with Scripts/prepare-app-store-review-package.sh
- Run live App Store Connect verification with ASC credentials
- Confirm App Store Connect app info and version localizations match AppStore/AppStoreConnectFields.generated.json
- Confirm App Store Connect shows no in-app purchases for BlitzRecorder
- Create signed App Store archives with the real Apple team ID
- Export local App Store packages with EXPORT=1 or upload with UPLOAD=1 after archive validation
- Confirm App Store Connect build 1 for both apps has finished processing as VALID
- Run Scripts/validate-submission-artifacts.sh --strict after archives and ASC credentials exist
- Complete physical Mac/iPhone/iPad QA using AppStore/DeviceQAChecklist.md
- Complete legal review of privacy policy, terms, and privacy nutrition labels
- Keep account-side records, signed archive paths, QA evidence, and the final submission decision with the private release handoff
PENDING
}

run_check "Launch Readiness" Scripts/validate-launch-readiness.sh
run_check "StoreKit Removal" Scripts/validate-storekit-local.sh
run_check "Submission Artifacts" Scripts/validate-submission-artifacts.sh

if [[ "$FULL" == "1" ]]; then
  run_check "Local Build/Test Preflight" Scripts/preflight-app-store-local.sh
fi

print_pending_items
