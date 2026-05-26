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
    fail "$file unexpectedly contains: $pattern"
  fi
}

plist_value() {
  /usr/libexec/PlistBuddy -c "Print :$2" "$1" 2>/dev/null || true
}

require_plist_value() {
  local plist="$1"
  local key="$2"
  local expected="$3"
  local value
  value="$(plist_value "$plist" "$key")"
  [[ "$value" == "$expected" ]] || fail "$plist $key is ${value:-missing}, expected $expected"
}

require_plist_contains() {
  local plist="$1"
  local key="$2"
  local expected="$3"
  local value
  value="$(plist_value "$plist" "$key")"
  [[ "$value" == *"$expected"* ]] || fail "$plist $key does not contain $expected"
}

reject_plist_key() {
  local plist="$1"
  local key="$2"
  if /usr/libexec/PlistBuddy -c "Print :$key" "$plist" >/dev/null 2>&1; then
    fail "$plist unexpectedly contains $key"
  fi
}

first_section_line() {
  local file="$1"
  local heading="$2"
  awk -v heading="## $heading" '
    $0 == heading { found = 1; next }
    found && /^## / { exit }
    found && NF { print; exit }
  ' "$file"
}

section_text() {
  local file="$1"
  local heading="$2"
  awk -v heading="## $heading" '
    $0 == heading { found = 1; next }
    found && /^## / { exit }
    found { print }
  ' "$file"
}

require_max_length() {
  local label="$1"
  local value="$2"
  local max="$3"
  local length="${#value}"
  [[ "$length" -le "$max" ]] || fail "$label is $length characters, max is $max"
}

image_dimensions() {
  local file="$1"
  sips -g pixelWidth -g pixelHeight "$file" 2>/dev/null |
    awk '
      /pixelWidth/ { width = $2 }
      /pixelHeight/ { height = $2 }
      END {
        if (width && height) {
          print width "x" height
        }
      }
    '
}

image_has_alpha() {
  local file="$1"
  sips -g hasAlpha "$file" 2>/dev/null |
    awk '/hasAlpha/ { print $2 }'
}

require_image() {
  local file="$1"
  local expected_dimensions="$2"
  local alpha_policy="${3:-allow-alpha}"

  require_file "$file"
  [[ -f "$file" ]] || return

  local dimensions
  dimensions="$(image_dimensions "$file")"
  [[ "$dimensions" == "$expected_dimensions" ]] || fail "$file is ${dimensions:-unknown}, expected $expected_dimensions"

  if [[ "$alpha_policy" == "no-alpha" ]]; then
    local has_alpha
    has_alpha="$(image_has_alpha "$file")"
    [[ "$has_alpha" == "no" ]] || fail "$file has alpha channel; App Store icons must be opaque"
  fi
}

validate_metadata_file() {
  local file="$1"
  local app_name
  local subtitle
  local promotional_text
  local description
  local keywords

  app_name="$(first_section_line "$file" "App Name")"
  subtitle="$(first_section_line "$file" "Subtitle")"
  promotional_text="$(first_section_line "$file" "Promotional Text")"
  description="$(section_text "$file" "Description")"
  keywords="$(first_section_line "$file" "Keywords")"

  [[ -n "$app_name" ]] || fail "$file missing App Name value"
  [[ -n "$subtitle" ]] || fail "$file missing Subtitle value"
  [[ -n "$promotional_text" ]] || fail "$file missing Promotional Text value"
  [[ -n "$description" ]] || fail "$file missing Description value"
  [[ -n "$keywords" ]] || fail "$file missing Keywords value"

  require_max_length "$file App Name" "$app_name" 30
  require_max_length "$file Subtitle" "$subtitle" 30
  require_max_length "$file Promotional Text" "$promotional_text" 170
  require_max_length "$file Description" "$description" 4000
  require_max_length "$file Keywords" "$keywords" 100
}

require_file "AppStore/BlitzRecorder.storekit"
require_file "AppStore/BlitzReelsEntitlementContract.md"
require_file "AppStore/Metadata.md"
require_file "AppStore/AppStoreConnectFields.generated.json"
require_file "AppStore/Metadata-macOS.md"
require_file "AppStore/Metadata-iOS.md"
require_file "AppStore/AppStoreConnectManualSetup.md"
require_file "AppStore/AppStoreQuestionnaires.md"
require_file "AppStore/AppStoreQuestionnaireAnswers.generated.json"
require_file "AppStore/Screenshots.md"
require_file "AppStore/ReviewNotes.md"
require_file "AppStore/DeviceQAChecklist.md"
require_file "AppStore/PrivacyNutritionLabels.md"
require_file "AppStore/PrivacyNutritionLabels.generated.json"
require_file "AppStore/ReleaseEvidence.md"
require_file "AppStore/SubmissionChecklist.md"
require_file "Resources/BlitzRecorder.icns"
require_file "Sources/BlitzRecorderApp/PrivacyInfo.xcprivacy"
require_file "Apps/iOSCamera/Resources/PrivacyInfo.xcprivacy"
require_file "Web/blitzrecorder/index.html"
require_file "Web/blitzrecorder/privacy.html"
require_file "Web/blitzrecorder/terms.html"
require_file "Web/blitzrecorder/support.html"
require_file "Scripts/preflight-app-store-local.sh"
require_file "Scripts/validate-entitlement-endpoint.sh"
require_file "Scripts/capture-app-store-screenshots.sh"
require_file "Scripts/app-store-connect-bootstrap.py"
require_file "Scripts/app-store-connect-readiness.py"
require_file "Scripts/test-app-store-connect-readiness.py"
require_file "Scripts/test-app-store-connect-bootstrap.py"
require_file "Scripts/validate-submission-artifacts.sh"
require_file "Scripts/validate-storekit-local.sh"
require_file "Scripts/release-status.sh"
require_file "Scripts/collect-release-evidence.sh"
require_file "Scripts/update-release-evidence.py"
require_file "Scripts/prepare-app-store-review-package.sh"
require_file "Scripts/generate-app-store-connect-fields.py"
require_file "Scripts/generate-app-store-questionnaire-answers.py"
require_file "Scripts/generate-app-store-privacy-labels.py"

expected_product_id="dev.blitzreels.blitzrecorder.pro.monthly"
expected_annual_product_id="dev.blitzreels.blitzrecorder.pro.annual"
expected_price="7.99"
expected_annual_price="49.99"
expected_subscription_description="Unlimited exports in BlitzRecorder."
expected_marketing_version="0.1.0"
expected_build_number="1"
bonjour_service="_blitzrecorder-camera._tcp"

if command -v jq >/dev/null 2>&1; then
  storekit_product_id="$(jq -r ".subscriptionGroups[].subscriptions[] | select(.productID == \"$expected_product_id\") | .productID" AppStore/BlitzRecorder.storekit)"
  storekit_annual_product_id="$(jq -r ".subscriptionGroups[].subscriptions[] | select(.productID == \"$expected_annual_product_id\") | .productID" AppStore/BlitzRecorder.storekit)"
  storekit_price="$(jq -r ".subscriptionGroups[].subscriptions[] | select(.productID == \"$expected_product_id\") | .displayPrice" AppStore/BlitzRecorder.storekit)"
  storekit_annual_price="$(jq -r ".subscriptionGroups[].subscriptions[] | select(.productID == \"$expected_annual_product_id\") | .displayPrice" AppStore/BlitzRecorder.storekit)"
  storekit_description="$(jq -r ".subscriptionGroups[].subscriptions[] | select(.productID == \"$expected_product_id\") | .localizations[] | select(.locale == \"en_US\") | .description" AppStore/BlitzRecorder.storekit)"
  [[ "$storekit_product_id" == "$expected_product_id" ]] || fail "StoreKit product ID is $storekit_product_id, expected $expected_product_id"
  [[ "$storekit_annual_product_id" == "$expected_annual_product_id" ]] || fail "StoreKit annual product ID is $storekit_annual_product_id, expected $expected_annual_product_id"
  [[ "$storekit_price" == "$expected_price" ]] || fail "StoreKit price is $storekit_price, expected $expected_price"
  [[ "$storekit_annual_price" == "$expected_annual_price" ]] || fail "StoreKit annual price is $storekit_annual_price, expected $expected_annual_price"
  [[ "$storekit_description" == "$expected_subscription_description" ]] || fail "StoreKit description is $storekit_description, expected $expected_subscription_description"

  fields_mac_bundle_id="$(jq -r '.apps.macOS.bundleId' AppStore/AppStoreConnectFields.generated.json)"
  fields_ios_bundle_id="$(jq -r '.apps.iOS.bundleId' AppStore/AppStoreConnectFields.generated.json)"
  fields_product_id="$(jq -r '.subscription.productId' AppStore/AppStoreConnectFields.generated.json)"
  fields_annual_product_id="$(jq -r '.subscription.annualProductId' AppStore/AppStoreConnectFields.generated.json)"
  fields_price="$(jq -r '.subscription.priceUSD' AppStore/AppStoreConnectFields.generated.json)"
  fields_annual_price="$(jq -r '.subscription.annualPriceUSD' AppStore/AppStoreConnectFields.generated.json)"
  fields_ios_companion_only="$(jq -r '.apps.iOS.companionOnly' AppStore/AppStoreConnectFields.generated.json)"
  fields_ios_initiates_purchases="$(jq -r '.apps.iOS.initiatesPurchases' AppStore/AppStoreConnectFields.generated.json)"
  questionnaire_age_rating="$(jq -r '.ageRating.recommendedTarget' AppStore/AppStoreQuestionnaireAnswers.generated.json)"
  questionnaire_uses_idfa="$(jq -r '.advertisingIdentifier.usesIDFA' AppStore/AppStoreQuestionnaireAnswers.generated.json)"
  questionnaire_tracking="$(jq -r '.advertisingIdentifier.tracking' AppStore/AppStoreQuestionnaireAnswers.generated.json)"
  questionnaire_kids="$(jq -r '.kidsCategory.madeForKids' AppStore/AppStoreQuestionnaireAnswers.generated.json)"
  questionnaire_encryption="$(jq -r '.exportCompliance.itsAppUsesNonExemptEncryption' AppStore/AppStoreQuestionnaireAnswers.generated.json)"
  questionnaire_product_id="$(jq -r '.paidContentAndSubscriptions.productId' AppStore/AppStoreQuestionnaireAnswers.generated.json)"
  questionnaire_annual_product_id="$(jq -r '.paidContentAndSubscriptions.annualProductId' AppStore/AppStoreQuestionnaireAnswers.generated.json)"
  privacy_mac_tracking="$(jq -r '.apps.macOS.dataUsedToTrackYou' AppStore/PrivacyNutritionLabels.generated.json)"
  privacy_mac_linked="$(jq -r '.apps.macOS.dataLinkedToYou' AppStore/PrivacyNutritionLabels.generated.json)"
  privacy_ios_collected="$(jq -r '.apps.iOS.dataCollected' AppStore/PrivacyNutritionLabels.generated.json)"
  privacy_ios_microphone="$(jq -r '.apps.iOS.permissions.microphone' AppStore/PrivacyNutritionLabels.generated.json)"
  privacy_shared_tracking="$(jq -r '.shared.tracking' AppStore/PrivacyNutritionLabels.generated.json)"
  [[ "$fields_mac_bundle_id" == "dev.blitzreels.blitzrecorder" ]] || fail "App Store Connect fields macOS bundle ID is $fields_mac_bundle_id"
  [[ "$fields_ios_bundle_id" == "dev.blitzreels.blitzrecorder.camera" ]] || fail "App Store Connect fields iOS bundle ID is $fields_ios_bundle_id"
  [[ "$fields_product_id" == "$expected_product_id" ]] || fail "App Store Connect fields product ID is $fields_product_id, expected $expected_product_id"
  [[ "$fields_annual_product_id" == "$expected_annual_product_id" ]] || fail "App Store Connect fields annual product ID is $fields_annual_product_id, expected $expected_annual_product_id"
  [[ "$fields_price" == "$expected_price" ]] || fail "App Store Connect fields price is $fields_price, expected $expected_price"
  [[ "$fields_annual_price" == "$expected_annual_price" ]] || fail "App Store Connect fields annual price is $fields_annual_price, expected $expected_annual_price"
  [[ "$fields_ios_companion_only" == "true" ]] || fail "App Store Connect fields iOS companionOnly is $fields_ios_companion_only"
  [[ "$fields_ios_initiates_purchases" == "false" ]] || fail "App Store Connect fields iOS initiatesPurchases is $fields_ios_initiates_purchases"
  [[ "$questionnaire_age_rating" == "4+" ]] || fail "Questionnaire age rating is $questionnaire_age_rating"
  [[ "$questionnaire_uses_idfa" == "false" ]] || fail "Questionnaire usesIDFA is $questionnaire_uses_idfa"
  [[ "$questionnaire_tracking" == "false" ]] || fail "Questionnaire tracking is $questionnaire_tracking"
  [[ "$questionnaire_kids" == "false" ]] || fail "Questionnaire madeForKids is $questionnaire_kids"
  [[ "$questionnaire_encryption" == "false" ]] || fail "Questionnaire ITSAppUsesNonExemptEncryption is $questionnaire_encryption"
  [[ "$questionnaire_product_id" == "$expected_product_id" ]] || fail "Questionnaire product ID is $questionnaire_product_id, expected $expected_product_id"
  [[ "$questionnaire_annual_product_id" == "$expected_annual_product_id" ]] || fail "Questionnaire annual product ID is $questionnaire_annual_product_id, expected $expected_annual_product_id"
  [[ "$privacy_mac_tracking" == "false" ]] || fail "Privacy labels macOS dataUsedToTrackYou is $privacy_mac_tracking"
  [[ "$privacy_mac_linked" == "true" ]] || fail "Privacy labels macOS dataLinkedToYou is $privacy_mac_linked"
  [[ "$privacy_ios_collected" == "false" ]] || fail "Privacy labels iOS dataCollected is $privacy_ios_collected"
  [[ "$privacy_ios_microphone" == "Not requested"* ]] || fail "Privacy labels iOS microphone text is $privacy_ios_microphone"
  [[ "$privacy_shared_tracking" == "false" ]] || fail "Privacy labels shared tracking is $privacy_shared_tracking"
else
  fail "jq is required to validate AppStore/BlitzRecorder.storekit"
fi

require_contains "Sources/BlitzRecorderApp/AccessController.swift" "static let monthlyProductID = \"$expected_product_id\""
require_contains "Sources/BlitzRecorderApp/AccessController.swift" "static let annualProductID = \"$expected_annual_product_id\""
require_contains "Sources/BlitzRecorderApp/AccessController.swift" "static let freeExportLimit = 3"
require_contains "Sources/BlitzRecorderApp/UI/BlitzReelsCreatorPage.swift" "BlitzRecorder Pro unlocks unlimited exports on Mac."
require_contains "Sources/BlitzRecorderApp/UI/BlitzReelsCreatorPage.swift" "App Store subscriptions renew until cancelled in Apple account settings."
require_contains "Sources/BlitzRecorderApp/UI/BlitzReelsCreatorPage.swift" "Eligible active BlitzReels subscribers can sign in for included Pro access."
require_contains "Sources/BlitzRecorderApp/UI/BlitzReelsCreatorPage.swift" "BlitzReels Sign In"
require_contains "Sources/BlitzRecorderApp/UI/BlitzReelsCreatorPage.swift" "Restore"
require_contains "Sources/BlitzRecorderApp/UI/BlitzReelsCreatorPage.swift" "Terms"
require_contains "Sources/BlitzRecorderApp/UI/BlitzReelsCreatorPage.swift" "Privacy"
require_contains "Sources/BlitzRecorderApp/UI/BlitzReelsCreatorPage.swift" "Support"
require_contains "AppStore/Metadata.md" "$expected_product_id"
require_contains "AppStore/Metadata.md" "$expected_annual_product_id"
require_contains "AppStore/Metadata.md" '$7.99 per month'
require_contains "AppStore/Metadata.md" '$49.99 per year'
require_contains "AppStore/Metadata-macOS.md" "dev.blitzreels.blitzrecorder"
require_contains "AppStore/Metadata-macOS.md" "$expected_product_id"
require_contains "AppStore/Metadata-macOS.md" "$expected_annual_product_id"
require_contains "AppStore/Metadata-macOS.md" '$7.99 per month'
require_contains "AppStore/Metadata-macOS.md" '$49.99 per year'
require_contains "AppStore/Metadata-macOS.md" "3 free exports"
require_contains "AppStore/Metadata-macOS.md" "macOS Keychain"
require_contains "AppStore/Metadata-iOS.md" "dev.blitzreels.blitzrecorder.camera"
require_contains "AppStore/Metadata-iOS.md" "$expected_product_id"
require_contains "AppStore/Metadata-iOS.md" "$expected_annual_product_id"
require_contains "AppStore/Metadata-iOS.md" '$7.99 per month'
require_contains "AppStore/Metadata-iOS.md" '$49.99 per year'
require_contains "AppStore/Metadata-iOS.md" "does not function as a standalone recorder"
require_contains "AppStore/Screenshots.md" "2880 x 1800"
require_contains "AppStore/Screenshots.md" "1260 x 2736"
require_contains "AppStore/Screenshots.md" "2064 x 2752"
require_contains "AppStore/BlitzReelsEntitlementContract.md" "https://www.blitzreels.com/api/blitzrecorder/entitlement"
require_contains "AppStore/BlitzReelsEntitlementContract.md" "Sign-In Redirect"
require_contains "AppStore/BlitzReelsEntitlementContract.md" "must reject arbitrary"
require_contains "AppStore/BlitzReelsEntitlementContract.md" '"active": true'
require_contains "AppStore/BlitzReelsEntitlementContract.md" '"planName": "BlitzReels Pro"'
require_contains "AppStore/BlitzReelsEntitlementContract.md" "BLITZRECORDER_ENTITLEMENT_EXPECTED_ACTIVE=true"
require_contains "AppStore/BlitzReelsEntitlementContract.md" "BLITZRECORDER_ENTITLEMENT_EXPECTED_ACTIVE=false"
require_contains "AppStore/SubmissionChecklist.md" "$expected_product_id"
require_contains "AppStore/SubmissionChecklist.md" "$expected_annual_product_id"
require_contains "AppStore/SubmissionChecklist.md" '$7.99 per month'
require_contains "AppStore/SubmissionChecklist.md" '$49.99 per year'
require_contains "AppStore/SubmissionChecklist.md" "Scripts/capture-app-store-screenshots.sh --all"
require_contains "AppStore/SubmissionChecklist.md" "Scripts/app-store-connect-bootstrap.py --apply"
require_contains "AppStore/SubmissionChecklist.md" "Scripts/app-store-connect-readiness.py"
require_contains "AppStore/SubmissionChecklist.md" "Scripts/validate-storekit-local.sh"
require_contains "AppStore/SubmissionChecklist.md" "Scripts/validate-submission-artifacts.sh --strict"
require_contains "AppStore/SubmissionChecklist.md" "Scripts/release-status.sh --full"
require_contains "AppStore/SubmissionChecklist.md" "Scripts/collect-release-evidence.sh --full"
require_contains "AppStore/SubmissionChecklist.md" "Scripts/prepare-app-store-review-package.sh"
require_contains "AppStore/SubmissionChecklist.md" "AppStore/AppStoreConnectManualSetup.md"
require_contains "AppStore/SubmissionChecklist.md" "AppStore/AppStoreQuestionnaires.md"
require_contains "AppStore/SubmissionChecklist.md" "BLITZRECORDER_ENTITLEMENT_EXPECTED_ACTIVE=true"
require_contains "AppStore/SubmissionChecklist.md" "BLITZRECORDER_ENTITLEMENT_EXPECTED_ACTIVE=false"
require_contains "AppStore/Screenshots.md" "AppStore/ScreenshotAssets/macOS/"
require_contains "AppStore/Screenshots.md" "AppStore/ScreenshotAssets/iPhone-6.9/"
require_contains "AppStore/Screenshots.md" "AppStore/ScreenshotAssets/iPad-13/"
require_contains "AppStore/Screenshots.md" "Scripts/capture-app-store-screenshots.sh --mac"
require_contains "AppStore/Screenshots.md" "02-plan-popover.png"
require_contains "AppStore/Screenshots.md" "03-iphone-camera-controls.png"
require_contains "Scripts/capture-app-store-screenshots.sh" "BLITZRECORDER_SCREENSHOT_VARIANT"
require_contains "Scripts/capture-app-store-screenshots.sh" "02-plan-popover.png"
require_contains "Scripts/capture-app-store-screenshots.sh" "03-iphone-camera-controls.png"
require_contains "Scripts/validate-submission-artifacts.sh" "02-plan-popover.png"
require_contains "Scripts/validate-submission-artifacts.sh" "03-iphone-camera-controls.png"
require_contains "Scripts/validate-submission-artifacts.sh" "check_url_contains"
require_contains "Scripts/validate-submission-artifacts.sh" "eligible BlitzReels subscribers"
require_contains "Scripts/validate-submission-artifacts.sh" "macOS Keychain"
require_contains "Scripts/validate-submission-artifacts.sh" "StoreKit"
require_contains "Scripts/validate-submission-artifacts.sh" "validate_export_options_plist"
require_contains "Scripts/validate-submission-artifacts.sh" "require_export_output"
require_contains "Scripts/validate-submission-artifacts.sh" "--connect-timeout 10 --max-time 25"
require_contains "Scripts/validate-submission-artifacts.sh" "build/AppStoreExports/macOS-export-options.plist"
require_contains "Scripts/validate-submission-artifacts.sh" "build/AppStoreExports/iOS-export-options.plist"
require_contains "Scripts/validate-submission-artifacts.sh" "ABCDE12345"
require_contains "Scripts/app-store-connect-readiness.py" "verify_app_store_version"
require_contains "Scripts/app-store-connect-readiness.py" "verify_uploaded_build"
require_contains "Scripts/app-store-connect-readiness.py" "verify_app_info_localization"
require_contains "Scripts/app-store-connect-readiness.py" "verify_version_localization"
require_contains "Scripts/app-store-connect-readiness.py" "verify_subscription_group_localization"
require_contains "Scripts/app-store-connect-readiness.py" "verify_subscription_metadata"
require_contains "Scripts/app-store-connect-readiness.py" "processingState"
require_contains "Scripts/app-store-connect-readiness.py" "appStoreVersionLocalizations"
require_contains "Scripts/app-store-connect-readiness.py" "appInfoLocalizations"
require_contains "Scripts/app-store-connect-readiness.py" "AppStoreConnectFields.generated.json"
require_contains "Scripts/app-store-connect-readiness.py" 'SUBSCRIPTION_REFERENCE_NAME = "BlitzRecorder Pro Monthly"'
require_contains "Scripts/app-store-connect-readiness.py" 'SUBSCRIPTION_DESCRIPTION = "Unlimited exports in BlitzRecorder."'
require_contains "Scripts/test-app-store-connect-readiness.py" "verify_app_info_localization"
require_contains "Scripts/test-app-store-connect-readiness.py" "verify_version_localization"
require_contains "Scripts/test-app-store-connect-readiness.py" "verify_subscription_group_localization"
require_contains "Scripts/test-app-store-connect-readiness.py" "verify_subscription_metadata"
require_contains "Scripts/test-app-store-connect-readiness.py" "App Store Connect readiness fixture tests passed."
require_contains "Scripts/app-store-connect-bootstrap.py" "SUBSCRIPTION_REFERENCE_NAME = readiness.SUBSCRIPTION_REFERENCE_NAME"
require_contains "Scripts/app-store-connect-bootstrap.py" "SUBSCRIPTION_DISPLAY_NAME = readiness.SUBSCRIPTION_DISPLAY_NAME"
require_contains "Scripts/app-store-connect-bootstrap.py" "SUBSCRIPTION_DESCRIPTION = readiness.SUBSCRIPTION_DESCRIPTION"
require_contains "Scripts/app-store-connect-bootstrap.py" "description\": SUBSCRIPTION_DESCRIPTION"
require_contains "Scripts/test-app-store-connect-bootstrap.py" "SUBSCRIPTION_REFERENCE_NAME"
require_contains "Scripts/test-app-store-connect-bootstrap.py" "SUBSCRIPTION_DISPLAY_NAME"
require_contains "Scripts/test-app-store-connect-bootstrap.py" "SUBSCRIPTION_DESCRIPTION"
require_contains "Scripts/test-app-store-connect-bootstrap.py" "App Store Connect bootstrap fixture tests passed."
require_contains "Sources/BlitzRecorderApp/UI/MainView.swift" "BLITZRECORDER_SCREENSHOT_VARIANT"
require_contains "Sources/BlitzRecorderApp/UI/MainView.swift" 'Subscribe $49.99 / year'
require_contains "AppStore/ReviewNotes.md" "dev.blitzreels.blitzrecorder"
require_contains "AppStore/ReviewNotes.md" "dev.blitzreels.blitzrecorder.camera"
require_contains "AppStore/ReviewNotes.md" "$expected_product_id"
require_contains "AppStore/ReviewNotes.md" "$expected_annual_product_id"
require_contains "AppStore/ReviewNotes.md" '$7.99 per month'
require_contains "AppStore/ReviewNotes.md" '$49.99 per year'
require_contains "AppStore/ReviewNotes.md" "redirects to BlitzReels login"
require_contains "AppStore/ReviewNotes.md" "3 free exports"
require_contains "AppStore/ReviewNotes.md" "does not request microphone access"
require_contains "AppStore/ReviewNotes.md" "macOS Keychain"
require_contains "AppStore/Metadata.md" "AppStore/ReviewNotes.md"
require_contains "AppStore/Metadata.md" "AppStore/DeviceQAChecklist.md"
require_contains "AppStore/Metadata.md" "AppStore/PrivacyNutritionLabels.md"
require_contains "AppStore/Metadata.md" "AppStore/PrivacyNutritionLabels.generated.json"
require_contains "AppStore/Metadata.md" "AppStore/ReleaseEvidence.md"
require_contains "AppStore/Metadata.md" "AppStore/AppStoreConnectManualSetup.md"
require_contains "AppStore/Metadata.md" "AppStore/AppStoreQuestionnaires.md"
require_contains "AppStore/Metadata.md" "AppStore/AppStoreQuestionnaireAnswers.generated.json"
require_contains "AppStore/Metadata.md" "AppStore/AppStoreConnectFields.generated.json"
require_contains "AppStore/AppStoreConnectFields.generated.json" "$expected_product_id"
require_contains "AppStore/AppStoreConnectFields.generated.json" "$expected_annual_product_id"
require_contains "AppStore/AppStoreConnectFields.generated.json" '"priceUSD": "7.99"'
require_contains "AppStore/AppStoreConnectFields.generated.json" '"annualPriceUSD": "49.99"'
require_contains "AppStore/AppStoreConnectFields.generated.json" '"companionOnly": true'
require_contains "AppStore/AppStoreConnectFields.generated.json" '"initiatesPurchases": false'
require_contains "AppStore/AppStoreConnectFields.generated.json" "AppStore/ScreenshotAssets/iPhone-6.9"
require_contains "AppStore/BlitzRecorder.storekit" "$expected_subscription_description"
require_contains "AppStore/AppStoreQuestionnaireAnswers.generated.json" '"recommendedTarget": "4+"'
require_contains "AppStore/AppStoreQuestionnaireAnswers.generated.json" '"usesIDFA": false'
require_contains "AppStore/AppStoreQuestionnaireAnswers.generated.json" '"tracking": false'
require_contains "AppStore/AppStoreQuestionnaireAnswers.generated.json" '"madeForKids": false'
require_contains "AppStore/AppStoreQuestionnaireAnswers.generated.json" '"itsAppUsesNonExemptEncryption": false'
require_contains "AppStore/AppStoreQuestionnaireAnswers.generated.json" "$expected_product_id"
require_contains "AppStore/AppStoreQuestionnaireAnswers.generated.json" "$expected_annual_product_id"
require_contains "AppStore/PrivacyNutritionLabels.generated.json" '"dataUsedToTrackYou": false'
require_contains "AppStore/PrivacyNutritionLabels.generated.json" '"dataLinkedToYou": true'
require_contains "AppStore/PrivacyNutritionLabels.generated.json" '"dataCollected": false'
require_contains "AppStore/PrivacyNutritionLabels.generated.json" '"NSPrivacyAccessedAPICategoryDiskSpace"'
require_contains "AppStore/PrivacyNutritionLabels.generated.json" "Not requested and must not be listed for the iOS companion."
require_contains "AppStore/SubmissionChecklist.md" "AppStore/ReviewNotes.md"
require_contains "AppStore/SubmissionChecklist.md" "AppStore/DeviceQAChecklist.md"
require_contains "AppStore/SubmissionChecklist.md" "AppStore/PrivacyNutritionLabels.md"
require_contains "AppStore/SubmissionChecklist.md" "AppStore/PrivacyNutritionLabels.generated.json"
require_contains "AppStore/SubmissionChecklist.md" "AppStore/ReleaseEvidence.md"
require_contains "AppStore/SubmissionChecklist.md" "AppStore/AppStoreConnectFields.generated.json"
require_contains "AppStore/SubmissionChecklist.md" "AppStore/AppStoreQuestionnaireAnswers.generated.json"
require_contains "AppStore/DeviceQAChecklist.md" "Mac App Subscription And Export Gate"
require_contains "AppStore/DeviceQAChecklist.md" "BlitzReels Included Access"
require_contains "AppStore/DeviceQAChecklist.md" "iOS Companion Pairing"
require_contains "AppStore/DeviceQAChecklist.md" "Remote Camera Recording"
require_contains "AppStore/DeviceQAChecklist.md" "Recovery And Failure Handling"
require_contains "AppStore/DeviceQAChecklist.md" "Scripts/preflight-app-store-local.sh"
require_contains "AppStore/DeviceQAChecklist.md" "Scripts/validate-submission-artifacts.sh --strict"
require_contains "AppStore/PrivacyNutritionLabels.md" "dev.blitzreels.blitzrecorder"
require_contains "AppStore/PrivacyNutritionLabels.md" "dev.blitzreels.blitzrecorder.camera"
require_contains "AppStore/PrivacyNutritionLabels.md" "Data Used to Track You: No"
require_contains "AppStore/PrivacyNutritionLabels.md" "Identifiers"
require_contains "AppStore/PrivacyNutritionLabels.md" "User ID"
require_contains "AppStore/PrivacyNutritionLabels.md" "BlitzReels sign-in returns an access token"
require_contains "AppStore/PrivacyNutritionLabels.md" "Data Collected: No"
require_contains "AppStore/PrivacyNutritionLabels.md" "Microphone: not requested"
require_contains "AppStore/PrivacyNutritionLabels.md" "NSPrivacyAccessedAPICategoryDiskSpace"
require_contains "AppStore/ReleaseEvidence.md" "dev.blitzreels.blitzrecorder.pro.monthly"
require_contains "AppStore/ReleaseEvidence.md" "3 free exports"
require_contains "AppStore/ReleaseEvidence.md" "3 free exports"
require_contains "AppStore/ReleaseEvidence.md" "Scripts/validate-submission-artifacts.sh --strict"
require_contains "AppStore/ReleaseEvidence.md" "Scripts/collect-release-evidence.sh --full"
require_contains "AppStore/ReleaseEvidence.md" "AppStore/ReleaseEvidence.generated.md"
require_contains "AppStore/ReleaseEvidence.md" "BLITZRECORDER_ENTITLEMENT_TOKEN=TOKEN Scripts/validate-entitlement-endpoint.sh"
require_contains "AppStore/ReleaseEvidence.md" "BLITZRECORDER_ENTITLEMENT_EXPECTED_ACTIVE=true"
require_contains "AppStore/ReleaseEvidence.md" "BLITZRECORDER_ENTITLEMENT_EXPECTED_ACTIVE=false"
require_contains "AppStore/ReleaseEvidence.md" "Final Decision"
require_contains "AppStore/ReleaseEvidence.md" "AppStore/AppStoreConnectManualSetup.md"
require_contains "AppStore/ReleaseEvidence.md" "AppStore/AppStoreQuestionnaires.md"
require_contains "AppStore/AppStoreConnectManualSetup.md" "dev.blitzreels.blitzrecorder"
require_contains "AppStore/AppStoreConnectManualSetup.md" "dev.blitzreels.blitzrecorder.camera"
require_contains "AppStore/AppStoreConnectManualSetup.md" "BLITZRECORDER-MAC"
require_contains "AppStore/AppStoreConnectManualSetup.md" "BLITZRECORDER-CAMERA-IOS"
require_contains "AppStore/AppStoreConnectManualSetup.md" "$expected_product_id"
require_contains "AppStore/AppStoreConnectManualSetup.md" "$expected_annual_product_id"
require_contains "AppStore/AppStoreConnectManualSetup.md" '$7.99 per month'
require_contains "AppStore/AppStoreConnectManualSetup.md" '$49.99 per year'
require_contains "AppStore/AppStoreConnectManualSetup.md" "3 free exports"
require_contains "AppStore/AppStoreConnectManualSetup.md" "AppStore/Metadata-macOS.md"
require_contains "AppStore/AppStoreConnectManualSetup.md" "AppStore/Metadata-iOS.md"
require_contains "AppStore/AppStoreConnectManualSetup.md" "AppStore/AppStoreConnectFields.generated.json"
require_contains "AppStore/AppStoreConnectManualSetup.md" "AppStore/PrivacyNutritionLabels.md"
require_contains "AppStore/AppStoreConnectManualSetup.md" "AppStore/PrivacyNutritionLabels.generated.json"
require_contains "AppStore/AppStoreConnectManualSetup.md" "AppStore/ReleaseEvidence.md"
require_contains "AppStore/AppStoreConnectManualSetup.md" "Scripts/validate-submission-artifacts.sh --strict"
require_contains "AppStore/AppStoreConnectManualSetup.md" "Positive production BlitzReels entitlement token test passed."
require_contains "AppStore/AppStoreConnectManualSetup.md" "AppStore/AppStoreQuestionnaires.md"
require_contains "AppStore/AppStoreConnectManualSetup.md" "AppStore/AppStoreQuestionnaireAnswers.generated.json"
require_contains "AppStore/AppStoreQuestionnaires.md" 'Recommended rating target: `4+`'
require_contains "AppStore/AppStoreQuestionnaires.md" "ITSAppUsesNonExemptEncryption"
require_contains "AppStore/AppStoreQuestionnaires.md" "no non-exempt encryption"
require_contains "AppStore/AppStoreQuestionnaires.md" "SHA-256 transfer digest"
require_contains "AppStore/AppStoreQuestionnaires.md" 'Does the app use IDFA? `No`'
require_contains "AppStore/AppStoreQuestionnaires.md" 'Tracking: `No`'
require_contains "AppStore/AppStoreQuestionnaires.md" 'Made for Kids: `No`'
require_contains "AppStore/AppStoreQuestionnaires.md" "iOS companion has no in-app purchases and no paywall."
require_contains "AppStore/AppStoreQuestionnaires.md" "Users are responsible for rights"
require_contains "Web/blitzrecorder/index.html" '$7.99 per month'
require_contains "Web/blitzrecorder/index.html" '$49.99 per year'
require_contains "Web/blitzrecorder/index.html" "3 free exports"
require_contains "Web/blitzrecorder/index.html" "eligible BlitzReels subscribers"
require_contains "Web/blitzrecorder/terms.html" '$7.99 per month'
require_contains "Web/blitzrecorder/terms.html" '$49.99 per year'
require_contains "Web/blitzrecorder/terms.html" "Eligible active BlitzReels subscribers"
require_contains "Web/blitzrecorder/terms.html" "support@blitzreels.com"
require_contains "Web/blitzrecorder/privacy.html" "macOS Keychain"
require_contains "Web/blitzrecorder/privacy.html" "support@blitzreels.com"
require_contains "Web/blitzrecorder/support.html" "support@blitzreels.com"
reject_contains "Web/blitzrecorder/terms.html" "intended as launch copy"
reject_contains "Web/blitzrecorder/privacy.html" "intended as product copy"
reject_contains "Web/blitzrecorder/support.html" "For launch"
reject_contains "Web/blitzrecorder/support.html" "support inbox or help desk"
require_contains "BlitzRecorder.xcodeproj/xcshareddata/xcschemes/BlitzRecorder.xcscheme" "../../AppStore/BlitzRecorder.storekit"
require_contains "project.yml" "storeKitConfiguration: AppStore/BlitzRecorder.storekit"
require_contains "Scripts/release-status.sh" "Scripts/collect-release-evidence.sh"
require_contains "Scripts/release-status.sh" "Scripts/validate-storekit-local.sh"
require_contains "Scripts/release-status.sh" "Scripts/test-app-store-connect-readiness.py"
require_contains "Scripts/release-status.sh" "Scripts/test-app-store-connect-bootstrap.py"
require_contains "Scripts/collect-release-evidence.sh" "Scripts/validate-launch-readiness.sh"
require_contains "Scripts/collect-release-evidence.sh" "Scripts/test-app-store-connect-readiness.py"
require_contains "Scripts/collect-release-evidence.sh" "Scripts/test-app-store-connect-bootstrap.py"
require_contains "Scripts/collect-release-evidence.sh" "Scripts/preflight-app-store-local.sh"
require_contains "Scripts/collect-release-evidence.sh" "Scripts/validate-entitlement-endpoint.sh"
require_contains "Scripts/collect-release-evidence.sh" "BLITZRECORDER_INACTIVE_ENTITLEMENT_TOKEN"
require_contains "Scripts/collect-release-evidence.sh" "BLITZRECORDER_ENTITLEMENT_EXPECTED_ACTIVE=true"
require_contains "Scripts/collect-release-evidence.sh" "BLITZRECORDER_ENTITLEMENT_EXPECTED_ACTIVE=false"
require_contains "Scripts/collect-release-evidence.sh" "AppStore/ReleaseEvidence.generated.md"
require_contains "Scripts/collect-release-evidence.sh" "AppStore/AppStoreQuestionnaires.md"
require_contains "Scripts/collect-release-evidence.sh" "Scripts/update-release-evidence.py"
require_contains "Scripts/update-release-evidence.py" 'Synced from `AppStore/ReleaseEvidence.generated.md`'
require_contains "Scripts/update-release-evidence.py" "Landing page pricing copy"
require_contains "Scripts/update-release-evidence.py" "Privacy page Keychain copy"
require_contains "Scripts/update-release-evidence.py" "Terms page included access copy"
require_contains "Scripts/update-release-evidence.py" "App Store Connect Verifier Fixtures"
require_contains "Scripts/update-release-evidence.py" "App Store Connect Bootstrap Fixtures"
require_contains "Scripts/update-release-evidence.py" "Positive BlitzReels Entitlement Token Check"
require_contains "Scripts/update-release-evidence.py" "Negative BlitzReels Entitlement Token Check"
require_contains "Scripts/validate-entitlement-endpoint.sh" "BLITZRECORDER_ENTITLEMENT_EXPECTED_ACTIVE"
require_contains "Scripts/validate-entitlement-endpoint.sh" 'expected entitlement active=$EXPECTED_ACTIVE'
require_contains "Scripts/prepare-app-store-review-package.sh" "build/AppStoreReviewPackage"
require_contains "Scripts/prepare-app-store-review-package.sh" "Manifest.md"
require_contains "Scripts/prepare-app-store-review-package.sh" "AppStoreConnectFields.generated.json"
require_contains "Scripts/prepare-app-store-review-package.sh" "AppStoreQuestionnaireAnswers.generated.json"
require_contains "Scripts/prepare-app-store-review-package.sh" "PrivacyNutritionLabels.generated.json"
require_contains "Scripts/prepare-app-store-review-package.sh" "Scripts/generate-app-store-connect-fields.py"
require_contains "Scripts/prepare-app-store-review-package.sh" "Scripts/generate-app-store-questionnaire-answers.py"
require_contains "Scripts/prepare-app-store-review-package.sh" "Scripts/generate-app-store-privacy-labels.py"
require_contains "Scripts/generate-app-store-connect-fields.py" 'SUBSCRIPTION_PERIOD = "ONE_MONTH"'
require_contains "Scripts/generate-app-store-connect-fields.py" 'STOREKIT_SUBSCRIPTION_PERIOD = "P1M"'
require_contains "Scripts/generate-app-store-connect-fields.py" "--check"
require_contains "Scripts/generate-app-store-connect-fields.py" "json.dumps(payload, indent=2, ensure_ascii=True)"
require_contains "Scripts/generate-app-store-questionnaire-answers.py" "--check"
require_contains "Scripts/generate-app-store-questionnaire-answers.py" "json.dumps(payload, indent=2, ensure_ascii=True)"
require_contains "Scripts/generate-app-store-privacy-labels.py" "--check"
require_contains "Scripts/generate-app-store-privacy-labels.py" "json.dumps(payload, indent=2, ensure_ascii=True)"
require_contains "Scripts/validate-storekit-local.sh" "StoreKit local validation passed."
require_contains "Scripts/validate-storekit-local.sh" "$expected_subscription_description"
require_contains "Scripts/collect-release-evidence.sh" "StoreKit Local Configuration"
require_contains "project.yml" "Resources/BlitzRecorder.icns"
require_contains "project.yml" "MARKETING_VERSION: \"$expected_marketing_version\""
require_contains "project.yml" "CURRENT_PROJECT_VERSION: \"$expected_build_number\""
require_contains "Info.plist" "CFBundleIconFile"
require_contains "Info.plist" "BlitzRecorder"
require_contains "BlitzRecorder.entitlements" "com.apple.security.app-sandbox"
require_contains "BlitzRecorder.entitlements" "com.apple.security.network.client"
require_contains "BlitzRecorder.entitlements" "com.apple.security.device.camera"
require_contains "BlitzRecorder.entitlements" "com.apple.security.device.audio-input"
require_contains "BlitzRecorder.entitlements" "com.apple.security.files.user-selected.read-write"
require_plist_value "Info.plist" "CFBundleIdentifier" "dev.blitzreels.blitzrecorder"
require_plist_value "Info.plist" "CFBundleShortVersionString" '$(MARKETING_VERSION)'
require_plist_value "Info.plist" "CFBundleVersion" '$(CURRENT_PROJECT_VERSION)'
require_plist_value "Info.plist" "LSApplicationCategoryType" "public.app-category.video"
require_plist_value "Info.plist" "ITSAppUsesNonExemptEncryption" "false"
require_plist_contains "Info.plist" "NSBonjourServices" "$bonjour_service"
require_plist_contains "Info.plist" "NSLocalNetworkUsageDescription" "local network"
require_plist_contains "Info.plist" "NSCameraUsageDescription" "camera"
require_plist_contains "Info.plist" "NSMicrophoneUsageDescription" "microphone"
require_plist_contains "Info.plist" "NSScreenCaptureUsageDescription" "screen"
require_contains "Apps/iOSCamera/Info.plist" "Icon-App-60x60"
require_contains "Apps/iOSCamera/Info.plist" "Icon-App-83.5x83.5"
require_contains "Apps/iOSCamera/Info.plist" "UIRequiredDeviceCapabilities"
require_contains "Apps/iOSCamera/Info.plist" "<string>camera</string>"
require_contains "Apps/iOSCamera/Info.plist" "UIInterfaceOrientationPortraitUpsideDown"
require_plist_value "Apps/iOSCamera/Info.plist" "ITSAppUsesNonExemptEncryption" "false"
require_plist_value "Apps/iOSCamera/Info.plist" "CFBundleShortVersionString" '$(MARKETING_VERSION)'
require_plist_value "Apps/iOSCamera/Info.plist" "CFBundleVersion" '$(CURRENT_PROJECT_VERSION)'
require_plist_contains "Apps/iOSCamera/Info.plist" "NSBonjourServices" "$bonjour_service"
require_plist_contains "Apps/iOSCamera/Info.plist" "NSLocalNetworkUsageDescription" "local network"
require_plist_contains "Apps/iOSCamera/Info.plist" "NSCameraUsageDescription" "camera"
reject_plist_key "Apps/iOSCamera/Info.plist" "NSMicrophoneUsageDescription"
require_plist_value "Sources/BlitzRecorderApp/PrivacyInfo.xcprivacy" "NSPrivacyTracking" "false"
require_plist_contains "Sources/BlitzRecorderApp/PrivacyInfo.xcprivacy" "NSPrivacyAccessedAPITypes" "NSPrivacyAccessedAPICategoryUserDefaults"
require_plist_contains "Sources/BlitzRecorderApp/PrivacyInfo.xcprivacy" "NSPrivacyAccessedAPITypes" "NSPrivacyAccessedAPICategoryFileTimestamp"
require_plist_value "Apps/iOSCamera/Resources/PrivacyInfo.xcprivacy" "NSPrivacyTracking" "false"
require_plist_contains "Apps/iOSCamera/Resources/PrivacyInfo.xcprivacy" "NSPrivacyAccessedAPITypes" "NSPrivacyAccessedAPICategoryUserDefaults"
require_plist_contains "Apps/iOSCamera/Resources/PrivacyInfo.xcprivacy" "NSPrivacyAccessedAPITypes" "NSPrivacyAccessedAPICategoryFileTimestamp"
require_plist_contains "Apps/iOSCamera/Resources/PrivacyInfo.xcprivacy" "NSPrivacyAccessedAPITypes" "NSPrivacyAccessedAPICategoryDiskSpace"
require_contains "Sources/BlitzRecorderApp/AccessController.swift" "KeychainBlitzReelsTokenStore"
require_contains "Sources/BlitzRecorderApp/AccessController.swift" "kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly"
if rg -q --fixed-strings "simulateConnectedForPreview" Apps/iOSCamera/Sources; then
  fail "iOS companion exposes simulated pairing in release sources"
fi
if rg -q --fixed-strings "Microphone access" AppStore/Metadata-iOS.md; then
  fail "iOS companion metadata claims microphone access, but the iOS target does not request it"
fi

validate_metadata_file "AppStore/Metadata-macOS.md"
validate_metadata_file "AppStore/Metadata-iOS.md"

python3 Scripts/generate-app-store-connect-fields.py --check >/dev/null || fail "App Store Connect field export is stale"
python3 Scripts/generate-app-store-questionnaire-answers.py --check >/dev/null || fail "App Store questionnaire answer export is stale"
python3 Scripts/generate-app-store-privacy-labels.py --check >/dev/null || fail "App Store privacy label export is stale"
Scripts/app-store-connect-readiness.py --dry-run >/dev/null || fail "App Store Connect readiness dry-run failed"
Scripts/app-store-connect-bootstrap.py >/dev/null || fail "App Store Connect bootstrap dry-run failed"

require_image "Resources/AppIcon.png" "1024x1024" "no-alpha"
require_image "Apps/iOSCamera/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png" "1024x1024" "no-alpha"
require_image "Apps/iOSCamera/Resources/Icons/Icon-App-20x20@2x.png" "40x40" "no-alpha"
require_image "Apps/iOSCamera/Resources/Icons/Icon-App-20x20@3x.png" "60x60" "no-alpha"
require_image "Apps/iOSCamera/Resources/Icons/Icon-App-29x29@2x.png" "58x58" "no-alpha"
require_image "Apps/iOSCamera/Resources/Icons/Icon-App-29x29@3x.png" "87x87" "no-alpha"
require_image "Apps/iOSCamera/Resources/Icons/Icon-App-40x40@2x.png" "80x80" "no-alpha"
require_image "Apps/iOSCamera/Resources/Icons/Icon-App-40x40@3x.png" "120x120" "no-alpha"
require_image "Apps/iOSCamera/Resources/Icons/Icon-App-60x60@2x.png" "120x120" "no-alpha"
require_image "Apps/iOSCamera/Resources/Icons/Icon-App-60x60@3x.png" "180x180" "no-alpha"
require_image "Apps/iOSCamera/Resources/Icons/Icon-App-76x76@1x.png" "76x76" "no-alpha"
require_image "Apps/iOSCamera/Resources/Icons/Icon-App-76x76@2x.png" "152x152" "no-alpha"
require_image "Apps/iOSCamera/Resources/Icons/Icon-App-83.5x83.5@2x.png" "167x167" "no-alpha"
require_image "Apps/iOSCamera/Resources/Icons/Icon-App-1024x1024@1x.png" "1024x1024" "no-alpha"

if [[ "$failures" -gt 0 ]]; then
  echo "Launch readiness validation failed with $failures issue(s)." >&2
  exit 1
fi

echo "Launch readiness validation passed."
