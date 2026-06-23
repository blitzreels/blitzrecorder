#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STRICT=0
TARGET="${TARGET:-all}"
REQUIRE_EXPORTS="${REQUIRE_EXPORTS:-1}"
EXPECTED_MARKETING_VERSION="0.2.0"
EXPECTED_BUILD_NUMBER="4"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --strict)
      STRICT=1
      shift
      ;;
    --target)
      [[ $# -ge 2 ]] || { echo "error: --target needs all, mac, or ios" >&2; exit 2; }
      TARGET="$2"
      shift 2
      ;;
    --help|-h)
  cat <<'USAGE'
Usage:
  Scripts/validate-submission-artifacts.sh [--strict] [--target all|mac|ios]

Checks the artifacts App Store Connect actually needs after local builds pass:
public URLs, screenshot asset dimensions, signed archive locations, export
options/packages, and optional live App Store Connect records.

Without --strict, missing screenshots/archives/exports are reported as pending
and the script exits 0. With --strict, missing or invalid final artifacts fail.
Set REQUIRE_EXPORTS=0 to validate archives and metadata without requiring
exported .pkg/.ipa files.
USAGE
      exit 0
      ;;
    *)
      echo "error: unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

if [[ "$TARGET" != "all" && "$TARGET" != "mac" && "$TARGET" != "ios" ]]; then
  echo "TARGET must be all, mac, or ios." >&2
  exit 2
fi

if [[ "$REQUIRE_EXPORTS" != "0" && "$REQUIRE_EXPORTS" != "1" ]]; then
  echo "REQUIRE_EXPORTS must be 0 or 1." >&2
  exit 2
fi

cd "$ROOT"

failures=0
pending=0

fail() {
  echo "error: $*" >&2
  failures=$((failures + 1))
}

note_pending() {
  echo "pending: $*" >&2
  pending=$((pending + 1))
}

require_or_pending() {
  local path="$1"
  local label="$2"
  if [[ -e "$path" ]]; then
    echo "✓ $label exists: $path"
  elif [[ "$STRICT" == "1" ]]; then
    fail "missing $label: $path"
  else
    note_pending "missing $label: $path"
  fi
}

check_url_status() {
  local url="$1"
  local expected="$2"
  local code
  local attempt
  local reached=0
  for attempt in 1 2 3; do
    if code="$(curl --connect-timeout 10 --max-time 25 -sS -o /tmp/blitzrecorder-submission-url.out -w '%{http_code}' "$url")"; then
      reached=1
      break
    fi
    sleep "$attempt"
  done
  if [[ "$reached" != "1" ]]; then
    fail "failed to reach $url"
    return
  fi
  if [[ "$code" == "$expected" ]]; then
    echo "✓ $url returns HTTP $expected"
  else
    fail "$url returned HTTP $code, expected $expected"
  fi
}

check_redirect_location_contains() {
  local url="$1"
  local expected_status="$2"
  local expected_location_fragment="$3"
  local headers_file
  headers_file="$(mktemp /tmp/blitzrecorder-submission-headers.XXXXXX)"

  local code
  local attempt
  local reached=0
  for attempt in 1 2 3; do
    : >"$headers_file"
    if code="$(curl --connect-timeout 10 --max-time 25 -sS -D "$headers_file" -o /tmp/blitzrecorder-submission-url.out -w '%{http_code}' "$url")"; then
      reached=1
      break
    fi
    sleep "$attempt"
  done
  if [[ "$reached" != "1" ]]; then
    fail "failed to reach $url"
    rm -f "$headers_file"
    return
  fi

  if [[ "$code" != "$expected_status" ]]; then
    fail "$url returned HTTP $code, expected $expected_status"
    rm -f "$headers_file"
    return
  fi

  local location
  location="$(awk 'BEGIN { IGNORECASE = 1 } /^location:/ { sub(/\r$/, ""); print substr($0, index($0, ":") + 2); exit }' "$headers_file")"
  rm -f "$headers_file"

  if [[ "$location" == *"$expected_location_fragment"* ]]; then
    echo "✓ $url redirects to $expected_location_fragment"
  else
    fail "$url redirect location is ${location:-missing}, expected it to contain $expected_location_fragment"
  fi
}

check_url_contains() {
  local url="$1"
  local expected="$2"
  local body_file
  body_file="$(mktemp /tmp/blitzrecorder-submission-body.XXXXXX)"

  local code
  local attempt
  local reached=0
  for attempt in 1 2 3; do
    if code="$(curl --connect-timeout 10 --max-time 25 -sS -L -o "$body_file" -w '%{http_code}' "$url")"; then
      reached=1
      break
    fi
    sleep "$attempt"
  done
  if [[ "$reached" != "1" ]]; then
    fail "failed to reach $url"
    rm -f "$body_file"
    return
  fi

  if [[ "$code" != "200" ]]; then
    fail "$url returned HTTP $code while checking content, expected 200"
    rm -f "$body_file"
    return
  fi

  if LC_ALL=C grep -Fq -- "$expected" "$body_file"; then
    echo "✓ $url contains $expected"
  else
    fail "$url missing expected content: $expected"
  fi
  rm -f "$body_file"
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

validate_image() {
  local label="$1"
  local file="$2"
  local expected_dimensions="$3"

  if [[ ! -f "$file" ]]; then
    fail "missing $label image: $file"
    return
  fi

  local dimensions
  dimensions="$(image_dimensions "$file")"
  if [[ "$dimensions" == "$expected_dimensions" ]]; then
    echo "✓ $label image is $dimensions"
  else
    fail "$label image is ${dimensions:-unknown}, expected $expected_dimensions"
  fi

  local has_alpha
  has_alpha="$(image_has_alpha "$file")"
  if [[ "$has_alpha" == "no" ]]; then
    echo "✓ $label image is opaque"
  else
    fail "$label image has alpha channel; App Store icons must be opaque"
  fi
}

plist_value() {
  /usr/libexec/PlistBuddy -c "Print :$2" "$1" 2>/dev/null || true
}

validate_plist_value() {
  local label="$1"
  local plist="$2"
  local key="$3"
  local expected="$4"
  local value
  value="$(plist_value "$plist" "$key")"
  if [[ "$value" == "$expected" ]]; then
    echo "✓ $label $key is $expected"
  else
    fail "$label $key is ${value:-missing}, expected $expected"
  fi
}

validate_plist_contains() {
  local label="$1"
  local plist="$2"
  local key="$3"
  local expected="$4"
  local value
  value="$(plist_value "$plist" "$key")"
  if [[ "$value" == *"$expected"* ]]; then
    echo "✓ $label $key contains $expected"
  else
    fail "$label $key does not contain $expected"
  fi
}

validate_export_options_plist() {
  local label="$1"
  local plist="$2"

  if [[ ! -f "$plist" ]]; then
    if [[ "$STRICT" == "1" ]]; then
      fail "missing $label export options plist: $plist"
    else
      note_pending "missing $label export options plist: $plist"
    fi
    return
  fi

  validate_plist_value "$label export options" "$plist" "method" "app-store-connect"
  local signing_style
  signing_style="$(plist_value "$plist" "signingStyle")"
  if [[ "$signing_style" == "automatic" || "$signing_style" == "manual" ]]; then
    echo "✓ $label export options signingStyle is $signing_style"
  else
    fail "$label export options signingStyle is ${signing_style:-missing}, expected automatic or manual"
  fi
  validate_plist_value "$label export options" "$plist" "stripSwiftSymbols" "true"
  validate_plist_value "$label export options" "$plist" "uploadSymbols" "true"
  validate_plist_value "$label export options" "$plist" "manageAppVersionAndBuildNumber" "true"

  local destination
  destination="$(plist_value "$plist" "destination")"
  if [[ "$destination" == "export" || "$destination" == "upload" ]]; then
    echo "✓ $label export options destination is $destination"
  else
    fail "$label export options destination is ${destination:-missing}, expected export or upload"
  fi

  local team_id
  team_id="$(plist_value "$plist" "teamID")"
  if [[ "$team_id" =~ ^[A-Z0-9]{10}$ && "$team_id" != "ABCDE12345" ]]; then
    echo "✓ $label export options teamID is set"
  elif [[ "$STRICT" == "1" ]]; then
    fail "$label export options teamID is ${team_id:-missing}; set a real 10-character Apple team ID"
  else
    note_pending "$label export options teamID is ${team_id:-missing}; regenerate with a real TEAM_ID before upload"
  fi
}

validate_screenshot_set() {
  local label="$1"
  local dir="$2"
  shift 2
  local accepted=("$@")
  local count=0
  local invalid=0

  if [[ ! -d "$dir" ]]; then
    if [[ "$STRICT" == "1" ]]; then
      fail "missing screenshot directory for $label: $dir"
    else
      note_pending "missing screenshot directory for $label: $dir"
    fi
    return
  fi

  while IFS= read -r file; do
    [[ -n "$file" ]] || continue
    count=$((count + 1))
    local dimensions
    dimensions="$(image_dimensions "$file")"
    local ok=0
    for accepted_dimensions in "${accepted[@]}"; do
      if [[ "$dimensions" == "$accepted_dimensions" ]]; then
        ok=1
        break
      fi
    done
    if [[ "$ok" == "1" ]]; then
      echo "✓ $label screenshot $(basename "$file") is $dimensions"
    else
      echo "error: $label screenshot $(basename "$file") is ${dimensions:-unknown}, expected one of: ${accepted[*]}" >&2
      invalid=$((invalid + 1))
    fi
  done < <(find "$dir" -maxdepth 1 -type f \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' \) | sort)

  if [[ "$count" -lt 1 || "$count" -gt 10 ]]; then
    if [[ "$STRICT" == "1" ]]; then
      fail "$label needs 1 to 10 screenshots, found $count"
    else
      note_pending "$label needs 1 to 10 screenshots, found $count"
    fi
  fi

  if [[ "$invalid" -gt 0 ]]; then
    failures=$((failures + invalid))
  fi
}

require_screenshot_file() {
  local label="$1"
  local file="$2"
  shift 2
  local accepted=("$@")

  if [[ ! -f "$file" ]]; then
    if [[ "$STRICT" == "1" ]]; then
      fail "missing required $label screenshot: $file"
    else
      note_pending "missing required $label screenshot: $file"
    fi
    return
  fi

  local dimensions
  dimensions="$(image_dimensions "$file")"
  for accepted_dimensions in "${accepted[@]}"; do
    if [[ "$dimensions" == "$accepted_dimensions" ]]; then
      echo "✓ required $label screenshot $(basename "$file") is $dimensions"
      return
    fi
  done

  fail "required $label screenshot $(basename "$file") is ${dimensions:-unknown}, expected one of: ${accepted[*]}"
}

check_public_urls() {
  check_url_status "https://blitzrecorder.com" "200"
  check_url_status "https://blitzrecorder.com/privacy" "200"
  check_url_status "https://blitzrecorder.com/terms" "200"
  check_url_status "https://blitzrecorder.com/support" "200"
  check_url_contains "https://blitzrecorder.com/privacy" "support@blitzreels.com"
  check_url_contains "https://blitzrecorder.com/terms" "support@blitzreels.com"
  check_url_contains "https://blitzrecorder.com/support" "support@blitzreels.com"
}

check_screenshots() {
  if [[ "$TARGET" == "all" || "$TARGET" == "mac" ]]; then
    validate_screenshot_set \
      "macOS" \
      "AppStore/ScreenshotAssets/macOS" \
      "1280x800" "1440x900" "2560x1600" "2880x1800"
    require_screenshot_file \
      "macOS main canvas" \
      "AppStore/ScreenshotAssets/macOS/01-main-recording-canvas.png" \
      "1280x800" "1440x900" "2560x1600" "2880x1800"
    require_screenshot_file \
      "macOS plan popover" \
      "AppStore/ScreenshotAssets/macOS/02-plan-popover.png" \
      "1280x800" "1440x900" "2560x1600" "2880x1800"
    require_screenshot_file \
      "macOS iPhone camera controls" \
      "AppStore/ScreenshotAssets/macOS/03-iphone-camera-controls.png" \
      "1280x800" "1440x900" "2560x1600" "2880x1800"
  fi

  if [[ "$TARGET" == "all" || "$TARGET" == "ios" ]]; then
    validate_screenshot_set \
      "iPhone 6.9-inch" \
      "AppStore/ScreenshotAssets/iPhone-6.9" \
      "1260x2736" "1290x2796" "1320x2868"

    validate_screenshot_set \
      "iPad 13-inch" \
      "AppStore/ScreenshotAssets/iPad-13" \
      "2048x2732" "2064x2752"
  fi
}

require_export_output() {
  local label="$1"
  local dir="$2"
  local extension="$3"

  if [[ ! -d "$dir" ]]; then
    if [[ "$STRICT" == "1" ]]; then
      fail "missing $label export directory: $dir"
    else
      note_pending "missing $label export directory: $dir"
    fi
    return
  fi

  local outputs=()
  while IFS= read -r file; do
    [[ -n "$file" ]] || continue
    outputs+=("$file")
  done < <(find "$dir" -maxdepth 1 -type f -name "*.$extension" | sort)

  if [[ "${#outputs[@]}" -gt 0 ]]; then
    for output in "${outputs[@]}"; do
      echo "✓ $label export exists: $output"
    done
  elif [[ "$STRICT" == "1" ]]; then
    fail "missing $label App Store export *.$extension in $dir"
  else
    note_pending "missing $label App Store export *.$extension in $dir"
  fi
}

validate_archived_app() {
  local label="$1"
  local app_path="$2"
  local expected_bundle_id="$3"
  shift 3
  local accepted_authorities=("$@")

  if [[ ! -d "$app_path" ]]; then
    if [[ "$STRICT" == "1" ]]; then
      fail "missing $label archived app: $app_path"
    else
      note_pending "missing $label archived app: $app_path"
    fi
    return
  fi

  local info_plist="$app_path/Info.plist"
  if [[ ! -f "$info_plist" ]]; then
    fail "$label archived app is missing Info.plist"
    return
  fi

  local bundle_id
  bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$info_plist" 2>/dev/null || true)"
  if [[ "$bundle_id" != "$expected_bundle_id" ]]; then
    fail "$label archived app bundle id is ${bundle_id:-unknown}, expected $expected_bundle_id"
  else
    echo "✓ $label archived app bundle id is $bundle_id"
  fi

  validate_plist_value "$label archived app" "$info_plist" "CFBundleShortVersionString" "$EXPECTED_MARKETING_VERSION"
  validate_plist_value "$label archived app" "$info_plist" "CFBundleVersion" "$EXPECTED_BUILD_NUMBER"

  if ! codesign --verify --strict --deep "$app_path" >/dev/null 2>&1; then
    fail "$label archived app does not pass strict codesign verification"
    return
  fi

  local signing_authority
  signing_authority="$(
    codesign -dvv "$app_path" 2>&1 |
      awk -F= '/^Authority=/ { print $2 }' |
      paste -sd '|' -
  )"

  local distribution_signed=0
  for accepted in "${accepted_authorities[@]}"; do
    if [[ "$signing_authority" == *"$accepted"* ]]; then
      distribution_signed=1
      break
    fi
  done

  if [[ "$distribution_signed" == "1" ]]; then
    echo "✓ $label archived app is distribution signed"
  else
    fail "$label archived app is not signed with an App Store distribution identity (${signing_authority:-unknown})"
  fi

  if [[ "$label" == "macOS" ]]; then
    if [[ -f "$app_path/Contents/Resources/BlitzRecorder.icns" ]]; then
      echo "✓ macOS archived app icon exists"
    else
      fail "macOS archived app is missing BlitzRecorder.icns"
    fi

    local category
    category="$(/usr/libexec/PlistBuddy -c 'Print :LSApplicationCategoryType' "$info_plist" 2>/dev/null || true)"
    if [[ "$category" == "public.app-category.video" ]]; then
      echo "✓ macOS archived app category is $category"
    else
      fail "macOS archived app category is ${category:-missing}, expected public.app-category.video"
    fi

    validate_plist_value "macOS archived app" "$info_plist" "ITSAppUsesNonExemptEncryption" "false"
    validate_plist_contains "macOS archived app" "$info_plist" "NSBonjourServices" "_blitzrecorder-camera._tcp"
    validate_plist_contains "macOS archived app" "$info_plist" "NSLocalNetworkUsageDescription" "local network"
    validate_plist_contains "macOS archived app" "$info_plist" "NSCameraUsageDescription" "camera"
    validate_plist_contains "macOS archived app" "$info_plist" "NSMicrophoneUsageDescription" "microphone"
    validate_plist_contains "macOS archived app" "$info_plist" "NSScreenCaptureUsageDescription" "screen"

    local privacy_manifest="$app_path/Contents/Resources/PrivacyInfo.xcprivacy"
    if [[ -f "$privacy_manifest" ]]; then
      validate_plist_value "macOS privacy manifest" "$privacy_manifest" "NSPrivacyTracking" "false"
      validate_plist_contains "macOS privacy manifest" "$privacy_manifest" "NSPrivacyAccessedAPITypes" "NSPrivacyAccessedAPICategoryUserDefaults"
      validate_plist_contains "macOS privacy manifest" "$privacy_manifest" "NSPrivacyAccessedAPITypes" "NSPrivacyAccessedAPICategoryFileTimestamp"
    else
      fail "macOS archived app is missing PrivacyInfo.xcprivacy"
    fi

    local entitlements_file
    entitlements_file="$(mktemp /tmp/blitzrecorder-entitlements.XXXXXX.plist)"
    if codesign -d --entitlements :- "$app_path" >"$entitlements_file" 2>/dev/null; then
      for entitlement in \
        "com.apple.security.app-sandbox" \
        "com.apple.security.network.client" \
        "com.apple.security.device.camera" \
        "com.apple.security.device.audio-input" \
        "com.apple.security.files.user-selected.read-write"; do
        local entitlement_value
        entitlement_value="$(/usr/libexec/PlistBuddy -c "Print :$entitlement" "$entitlements_file" 2>/dev/null || true)"
        if [[ "$entitlement_value" == "true" ]]; then
          echo "✓ macOS archived app entitlement enabled: $entitlement"
        else
          fail "macOS archived app entitlement $entitlement is ${entitlement_value:-missing}, expected true"
        fi
      done
    else
      fail "unable to read macOS archived app entitlements"
    fi
    rm -f "$entitlements_file"
  fi

  if [[ "$label" == "iOS" ]]; then
    validate_image "iOS archived primary iPhone icon" "$app_path/Icon-App-60x60@3x.png" "180x180"
    validate_image "iOS archived App Store icon" "$app_path/Icon-App-1024x1024@1x.png" "1024x1024"

    local device_family
    device_family="$(/usr/libexec/PlistBuddy -c 'Print :UIDeviceFamily' "$info_plist" 2>/dev/null || true)"
    if [[ "$device_family" == *"1"* && "$device_family" == *"2"* ]]; then
      echo "✓ iOS archived app supports iPhone and iPad"
    else
      fail "iOS archived app UIDeviceFamily is ${device_family:-missing}, expected iPhone and iPad"
    fi

    local capabilities
    capabilities="$(/usr/libexec/PlistBuddy -c 'Print :UIRequiredDeviceCapabilities' "$info_plist" 2>/dev/null || true)"
    if [[ "$capabilities" == *"arm64"* && "$capabilities" != *"camera"* ]]; then
      echo "✓ iOS archived app required capabilities are App Store compatible"
    else
      fail "iOS archived app UIRequiredDeviceCapabilities is ${capabilities:-missing}, expected arm64 and no camera"
    fi

    validate_plist_value "iOS archived app" "$info_plist" "ITSAppUsesNonExemptEncryption" "false"
    validate_plist_contains "iOS archived app" "$info_plist" "NSBonjourServices" "_blitzrecorder-camera._tcp"
    validate_plist_contains "iOS archived app" "$info_plist" "NSLocalNetworkUsageDescription" "local network"
    validate_plist_contains "iOS archived app" "$info_plist" "NSCameraUsageDescription" "camera"

    validate_plist_contains "iOS archived app" "$info_plist" "NSMicrophoneUsageDescription" "microphone"

    local privacy_manifest="$app_path/PrivacyInfo.xcprivacy"
    if [[ -f "$privacy_manifest" ]]; then
      validate_plist_value "iOS privacy manifest" "$privacy_manifest" "NSPrivacyTracking" "false"
      validate_plist_contains "iOS privacy manifest" "$privacy_manifest" "NSPrivacyAccessedAPITypes" "NSPrivacyAccessedAPICategoryUserDefaults"
      validate_plist_contains "iOS privacy manifest" "$privacy_manifest" "NSPrivacyAccessedAPITypes" "NSPrivacyAccessedAPICategoryFileTimestamp"
      validate_plist_contains "iOS privacy manifest" "$privacy_manifest" "NSPrivacyAccessedAPITypes" "NSPrivacyAccessedAPICategoryDiskSpace"
    else
      fail "iOS archived app is missing PrivacyInfo.xcprivacy"
    fi
  fi
}

check_archives() {
  if [[ "$TARGET" == "all" || "$TARGET" == "mac" ]]; then
    require_or_pending "build/AppStoreArchives/BlitzRecorder-macOS.xcarchive" "macOS App Store archive"
  fi
  if [[ "$TARGET" == "all" || "$TARGET" == "ios" ]]; then
    require_or_pending "build/AppStoreArchives/BlitzRecorderCamera-iOS.xcarchive" "iOS App Store archive"
  fi

  if [[ "$TARGET" == "all" || "$TARGET" == "mac" ]] &&
     [[ -d "build/AppStoreArchives/BlitzRecorder-macOS.xcarchive" ]]; then
    validate_archived_app \
      "macOS" \
      "build/AppStoreArchives/BlitzRecorder-macOS.xcarchive/Products/Applications/BlitzRecorder.app" \
      "dev.blitzreels.blitzrecorder" \
      "Apple Distribution" \
      "3rd Party Mac Developer Application"
  fi

  if [[ "$TARGET" == "all" || "$TARGET" == "ios" ]] &&
     [[ -d "build/AppStoreArchives/BlitzRecorderCamera-iOS.xcarchive" ]]; then
    validate_archived_app \
      "iOS" \
      "build/AppStoreArchives/BlitzRecorderCamera-iOS.xcarchive/Products/Applications/BlitzRecorderCamera.app" \
      "dev.blitzreels.blitzrecorder.camera" \
      "Apple Distribution" \
      "iPhone Distribution"
  fi
}

check_exports() {
  if [[ "$REQUIRE_EXPORTS" == "0" ]]; then
    echo "✓ App Store exports are not required for this validation"
    return
  fi

  if [[ "$TARGET" == "all" || "$TARGET" == "mac" ]]; then
    local mac_export_options="build/AppStoreExports/macOS-export-options.plist"
    validate_export_options_plist "macOS" "$mac_export_options"
    if [[ "$(plist_value "$mac_export_options" "destination")" == "upload" ]]; then
      echo "✓ macOS export output is not required for upload destination"
    else
      require_export_output "macOS" "build/AppStoreExports/macOS" "pkg"
    fi
  fi
  if [[ "$TARGET" == "all" || "$TARGET" == "ios" ]]; then
    local ios_export_options="build/AppStoreExports/iOS-export-options.plist"
    validate_export_options_plist "iOS" "$ios_export_options"
    if [[ "$(plist_value "$ios_export_options" "destination")" == "upload" ]]; then
      echo "✓ iOS export output is not required for upload destination"
    else
      require_export_output "iOS" "build/AppStoreExports/iOS" "ipa"
    fi
  fi
}

check_app_store_connect() {
  if [[ -n "${ASC_KEY_ID:-}" && -n "${ASC_ISSUER_ID:-}" && ( -n "${ASC_PRIVATE_KEY_PATH:-}" || -n "${ASC_PRIVATE_KEY:-}" ) ]]; then
    Scripts/app-store-connect-readiness.py
  elif [[ "$STRICT" == "1" ]]; then
    fail "missing ASC_KEY_ID, ASC_ISSUER_ID, and ASC_PRIVATE_KEY_PATH/ASC_PRIVATE_KEY for live App Store Connect verification"
  else
    note_pending "live App Store Connect verification skipped; run Scripts/app-store-connect-readiness.py with ASC credentials"
    Scripts/app-store-connect-readiness.py --dry-run >/dev/null
  fi
}

check_public_urls
check_screenshots
check_archives
check_exports
check_app_store_connect

if [[ "$failures" -gt 0 ]]; then
  echo "Submission artifact validation failed with $failures issue(s)." >&2
  exit 1
fi

if [[ "$pending" -gt 0 ]]; then
  echo "Submission artifact validation passed with $pending pending final artifact(s)."
else
  echo "Submission artifact validation passed."
fi
