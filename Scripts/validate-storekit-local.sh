#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

failures=0

fail() {
  echo "error: $*" >&2
  failures=$((failures + 1))
}

require_file() {
  [[ -f "$1" ]] || fail "missing file: $1"
}

require_absent() {
  local path="$1"
  [[ ! -e "$path" ]] || fail "$path should not exist for the direct-download Stripe license build"
}

require_not_contains() {
  local file="$1"
  local pattern="$2"
  if [[ ! -f "$file" ]]; then
    fail "missing file: $file"
    return
  fi
  if rg -q --fixed-strings -- "$pattern" "$file"; then
    fail "$file still contains: $pattern"
  fi
}

require_file "project.yml"
require_file "BlitzRecorder.xcodeproj/xcshareddata/xcschemes/BlitzRecorder.xcscheme"
require_file "Sources/BlitzRecorderApp/AccessController.swift"
require_file "Sources/BlitzRecorderApp/UI/BlitzReelsCreatorPage.swift"

require_absent "AppStore/BlitzRecorder.storekit"
require_not_contains "project.yml" "storeKitConfiguration"
require_not_contains "BlitzRecorder.xcodeproj/xcshareddata/xcschemes/BlitzRecorder.xcscheme" "StoreKitConfigurationFileReference"
require_not_contains "Sources/BlitzRecorderApp/UI/BlitzReelsCreatorPage.swift" "purchaseAnnual"
require_not_contains "Sources/BlitzRecorderApp/UI/BlitzReelsCreatorPage.swift" "purchaseMonthly"
require_not_contains "Sources/BlitzRecorderApp/UI/BlitzReelsCreatorPage.swift" "Restore Purchases"
require_not_contains "Sources/BlitzRecorderApp/UI/BlitzReelsCreatorPage.swift" "Manage Subscription"

if (( failures > 0 )); then
  echo "StoreKit removal validation failed with $failures issue(s)." >&2
  exit 1
fi

echo "StoreKit removal validation passed."
