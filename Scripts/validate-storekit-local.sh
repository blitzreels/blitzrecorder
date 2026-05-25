#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

failures=0

fail() {
  echo "error: $*" >&2
  failures=$((failures + 1))
}

require_tool() {
  command -v "$1" >/dev/null 2>&1 || fail "missing required tool: $1"
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

require_jq_value() {
  local file="$1"
  local expression="$2"
  local expected="$3"
  local label="$4"
  local actual
  actual="$(jq -r "$expression" "$file" 2>/dev/null || true)"
  [[ "$actual" == "$expected" ]] || fail "$label is ${actual:-missing}, expected $expected"
}

require_tool jq
require_tool rg

expected_product_id="dev.blitzreels.blitzrecorder.pro.monthly"
expected_price="4.99"
expected_period="P1M"
expected_description="Unlimited exports in BlitzRecorder."

require_file "AppStore/BlitzRecorder.storekit"
require_file "project.yml"
require_file "BlitzRecorder.xcodeproj/xcshareddata/xcschemes/BlitzRecorder.xcscheme"
require_file "Sources/BlitzRecorderApp/AccessController.swift"
require_file "Sources/BlitzRecorderApp/UI/TopBar.swift"

if [[ -f "AppStore/BlitzRecorder.storekit" ]] && command -v jq >/dev/null 2>&1; then
  require_jq_value \
    "AppStore/BlitzRecorder.storekit" \
    '.subscriptionGroups | length' \
    "1" \
    "StoreKit subscription group count"
  require_jq_value \
    "AppStore/BlitzRecorder.storekit" \
    '.subscriptionGroups[0].subscriptions | length' \
    "1" \
    "StoreKit subscription count"
  require_jq_value \
    "AppStore/BlitzRecorder.storekit" \
    '.subscriptionGroups[0].subscriptions[0].productID' \
    "$expected_product_id" \
    "StoreKit product ID"
  require_jq_value \
    "AppStore/BlitzRecorder.storekit" \
    '.subscriptionGroups[0].subscriptions[0].displayPrice' \
    "$expected_price" \
    "StoreKit display price"
  require_jq_value \
    "AppStore/BlitzRecorder.storekit" \
    '.subscriptionGroups[0].subscriptions[0].recurringSubscriptionPeriod' \
    "$expected_period" \
    "StoreKit subscription period"
  require_jq_value \
    "AppStore/BlitzRecorder.storekit" \
    '.subscriptionGroups[0].subscriptions[0].localizations[] | select(.locale == "en_US") | .displayName' \
    "BlitzRecorder Pro" \
    "StoreKit en-US display name"
  require_jq_value \
    "AppStore/BlitzRecorder.storekit" \
    '.subscriptionGroups[0].subscriptions[0].localizations[] | select(.locale == "en_US") | .description' \
    "$expected_description" \
    "StoreKit en-US description"
fi

require_contains "project.yml" "storeKitConfiguration: AppStore/BlitzRecorder.storekit"
require_contains "BlitzRecorder.xcodeproj/xcshareddata/xcschemes/BlitzRecorder.xcscheme" "../../AppStore/BlitzRecorder.storekit"

require_contains "Sources/BlitzRecorderApp/AccessController.swift" "import StoreKit"
require_contains "Sources/BlitzRecorderApp/AccessController.swift" "static let monthlyProductID = \"$expected_product_id\""
require_contains "Sources/BlitzRecorderApp/AccessController.swift" "Product.products(for: [ProductConfiguration.monthlyProductID])"
require_contains "Sources/BlitzRecorderApp/AccessController.swift" "try await product.purchase()"
require_contains "Sources/BlitzRecorderApp/AccessController.swift" "try await AppStore.sync()"
require_contains "Sources/BlitzRecorderApp/AccessController.swift" "Transaction.currentEntitlements"
require_contains "Sources/BlitzRecorderApp/AccessController.swift" "macappstore://showSubscriptions"

require_contains "Sources/BlitzRecorderApp/UI/TopBar.swift" "Subscribe \\(access.monthlyPriceLabel) / month"
require_contains "Sources/BlitzRecorderApp/UI/TopBar.swift" "Task { await access.purchaseMonthly() }"
require_contains "Sources/BlitzRecorderApp/UI/TopBar.swift" "Task { await access.restorePurchases() }"
require_contains "Sources/BlitzRecorderApp/UI/TopBar.swift" "Manage Subscription"
require_contains "Sources/BlitzRecorderApp/UI/TopBar.swift" "The App Store subscription renews monthly until cancelled in Apple account settings."

if [[ "$failures" -gt 0 ]]; then
  echo "StoreKit local validation failed with $failures issue(s)." >&2
  exit 1
fi

echo "StoreKit local validation passed."
