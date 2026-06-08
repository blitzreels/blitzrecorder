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

require_contains() {
  local file="$1"
  local pattern="$2"
  if [[ ! -f "$file" ]]; then
    fail "missing file: $file"
    return
  fi
  rg -q --fixed-strings -- "$pattern" "$file" || fail "$file missing: $pattern"
}

reject_contains() {
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

require_file "README.md"
require_file "LICENSE"
require_file "AppStore/Metadata-macOS.md"
require_file "AppStore/Metadata-iOS.md"
require_file "AppStore/ReviewNotes.md"
require_file "AppStore/AppStoreConnectFields.generated.json"
require_file "AppStore/AppStoreQuestionnaires.md"
require_file "AppStore/PrivacyNutritionLabels.md"
require_file "Sources/BlitzRecorderApp/AccessController.swift"
require_file "Sources/BlitzRecorderApp/UI/BlitzReelsCreatorPage.swift"
require_file "Web/blitzrecorder/lib/content.ts"
require_file "Scripts/validate-storekit-local.sh"

require_contains "Sources/BlitzRecorderApp/AccessController.swift" "var canRenderExport: Bool"
require_contains "Sources/BlitzRecorderApp/AccessController.swift" "Early Price unlocks iPhone camera"
require_contains "Sources/BlitzRecorderApp/UI/BlitzReelsCreatorPage.swift" "No export limit, no account, no subscription."
require_contains "Web/blitzrecorder/lib/content.ts" "There is no account, card, watermark, or subscription requirement."
require_contains "AppStore/Metadata-macOS.md" "In-App Purchases"
require_contains "AppStore/Metadata-macOS.md" "Paused for direct-download launch"
require_contains "AppStore/AppStoreConnectFields.generated.json" '"subscription": null'

reject_contains "project.yml" "storeKitConfiguration"
reject_contains "BlitzRecorder.xcodeproj/xcshareddata/xcschemes/BlitzRecorder.xcscheme" "StoreKitConfigurationFileReference"
reject_contains "Sources/BlitzRecorderApp/UI/BlitzReelsCreatorPage.swift" "Get Pro"
reject_contains "Sources/BlitzRecorderApp/UI/BlitzReelsCreatorPage.swift" "Restore Purchases"
reject_contains "Web/blitzrecorder/lib/content.ts" '$7.99'
reject_contains "Web/blitzrecorder/lib/content.ts" '$49.99'
reject_contains "AppStore/Metadata-macOS.md" '$7.99'
reject_contains "AppStore/Metadata-macOS.md" '$49.99'
reject_contains "AppStore/ReviewNotes.md" "BlitzRecorder Pro"

Scripts/validate-storekit-local.sh

if (( failures > 0 )); then
  echo "Launch readiness failed with $failures issue(s)." >&2
  exit 1
fi

echo "Launch readiness validation passed."
