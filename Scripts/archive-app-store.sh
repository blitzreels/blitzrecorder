#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TARGET="${TARGET:-all}"
TEAM_ID="${TEAM_ID:-${DEVELOPMENT_TEAM:-}}"
EXPORT="${EXPORT:-0}"
UPLOAD="${UPLOAD:-0}"
DRY_RUN="${DRY_RUN:-0}"
SKIP_PREFLIGHT="${SKIP_PREFLIGHT:-0}"
APP_STORE_REQUIRE_MANUAL_SIGNING="${APP_STORE_REQUIRE_MANUAL_SIGNING:-0}"
MAC_PROVISIONING_PROFILE_SPECIFIER="${MAC_PROVISIONING_PROFILE_SPECIFIER:-}"
IOS_PROVISIONING_PROFILE_SPECIFIER="${IOS_PROVISIONING_PROFILE_SPECIFIER:-}"
ASC_KEY_TEMP=""

usage() {
  cat <<'USAGE'
Usage:
  TEAM_ID=APPLE_TEAM_ID Scripts/archive-app-store.sh

Environment:
  TARGET=all|mac|ios                 Archive target set. Default: all
  EXPORT=0|1                         Export App Store packages after archive. Default: 0
  UPLOAD=0|1                         Export with destination=upload. Default: 0
  ALLOW_PROVISIONING_UPDATES=0|1      Let Xcode create/update profiles. Default: 0
  SKIP_PREFLIGHT=0|1                 Skip local preflight before archiving. Default: 0
  DRY_RUN=0|1                         Print xcodebuild commands without running. Default: 0

Output:
  build/AppStoreArchives/BlitzRecorder-macOS.xcarchive
  build/AppStoreArchives/BlitzRecorderCamera-iOS.xcarchive
  build/AppStoreExports/
USAGE
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

if [[ -z "$TEAM_ID" ]]; then
  echo "Set TEAM_ID to your Apple Developer Team ID." >&2
  exit 2
fi

cd "$ROOT"
mkdir -p "$ROOT/build"

if [[ "$TARGET" != "all" && "$TARGET" != "mac" && "$TARGET" != "ios" ]]; then
  echo "TARGET must be mac, ios, or all." >&2
  exit 2
fi

for boolean_name in EXPORT UPLOAD ALLOW_PROVISIONING_UPDATES SKIP_PREFLIGHT DRY_RUN APP_STORE_REQUIRE_MANUAL_SIGNING; do
  boolean_value="${!boolean_name:-0}"
  if [[ "$boolean_value" != "0" && "$boolean_value" != "1" ]]; then
    echo "$boolean_name must be 0 or 1." >&2
    exit 2
  fi
done

PROVISIONING_ARGS=()
if [[ "${ALLOW_PROVISIONING_UPDATES:-0}" == "1" ]]; then
  PROVISIONING_ARGS+=("-allowProvisioningUpdates")
fi

cleanup() {
  if [[ -n "$ASC_KEY_TEMP" && -f "$ASC_KEY_TEMP" ]]; then
    rm -f "$ASC_KEY_TEMP"
  fi
}
trap cleanup EXIT

if [[ "${ALLOW_PROVISIONING_UPDATES:-0}" == "1" &&
      -n "${ASC_KEY_ID:-}" &&
      -n "${ASC_ISSUER_ID:-}" &&
      ( -n "${ASC_PRIVATE_KEY_PATH:-}" || -n "${ASC_PRIVATE_KEY:-}" ) ]]; then
  ASC_AUTH_KEY_PATH="${ASC_PRIVATE_KEY_PATH:-}"
  if [[ -z "$ASC_AUTH_KEY_PATH" ]]; then
    ASC_KEY_TEMP="$(mktemp "$ROOT/build/AuthKey_XXXXXX.p8")"
    printf '%s' "$ASC_PRIVATE_KEY" >"$ASC_KEY_TEMP"
    chmod 600 "$ASC_KEY_TEMP"
    ASC_AUTH_KEY_PATH="$ASC_KEY_TEMP"
  fi
  PROVISIONING_ARGS+=(
    "-authenticationKeyID" "$ASC_KEY_ID"
    "-authenticationKeyIssuerID" "$ASC_ISSUER_ID"
    "-authenticationKeyPath" "$ASC_AUTH_KEY_PATH"
  )
fi

ARCHIVE_DIR="$ROOT/build/AppStoreArchives"
EXPORT_DIR="$ROOT/build/AppStoreExports"
mkdir -p "$ARCHIVE_DIR" "$EXPORT_DIR"

run_cmd() {
  if [[ "$DRY_RUN" == "1" ]]; then
    printf '+'
    printf ' %q' "$@"
    printf '\n'
  else
    "$@"
  fi
}

xml_escape() {
  local value="$1"
  value="${value//&/&amp;}"
  value="${value//</&lt;}"
  value="${value//>/&gt;}"
  value="${value//\"/&quot;}"
  printf '%s' "$value"
}

signing_args_for_profile() {
  local profile_specifier="$1"
  if [[ -n "$profile_specifier" ]]; then
    printf '%s\0' \
      "CODE_SIGN_STYLE=Manual" \
      "CODE_SIGN_IDENTITY=Apple Distribution" \
      "PROVISIONING_PROFILE_SPECIFIER=$profile_specifier"
  elif [[ "$APP_STORE_REQUIRE_MANUAL_SIGNING" == "1" ]]; then
    echo "error: missing App Store provisioning profile specifier for manual signing." >&2
    exit 2
  fi
}

preflight_if_needed() {
  if [[ "$SKIP_PREFLIGHT" == "1" || "$DRY_RUN" == "1" ]]; then
    return
  fi

  Scripts/preflight-app-store-local.sh
  Scripts/validate-submission-artifacts.sh
}

write_export_options() {
  local plist="$1"
  local bundle_id="$2"
  local profile_specifier="$3"
  local destination="export"
  local signing_style="automatic"

  if [[ "$UPLOAD" == "1" ]]; then
    destination="upload"
  fi
  if [[ -n "$profile_specifier" ]]; then
    signing_style="manual"
  fi

  cat >"$plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>destination</key>
  <string>${destination}</string>
  <key>manageAppVersionAndBuildNumber</key>
  <true/>
  <key>method</key>
  <string>app-store-connect</string>
  <key>signingStyle</key>
  <string>${signing_style}</string>
PLIST

  if [[ -n "$profile_specifier" ]]; then
    cat >>"$plist" <<PLIST
  <key>provisioningProfiles</key>
  <dict>
    <key>$(xml_escape "$bundle_id")</key>
    <string>$(xml_escape "$profile_specifier")</string>
  </dict>
PLIST
  fi

  cat >>"$plist" <<PLIST
  <key>stripSwiftSymbols</key>
  <true/>
  <key>teamID</key>
  <string>${TEAM_ID}</string>
  <key>uploadSymbols</key>
  <true/>
</dict>
</plist>
PLIST

  echo "$plist"
}

validate_archive() {
  local archive="$1"
  local app_relative_path="$2"
  local bundle_id="$3"
  local label="$4"
  local app_path="$archive/$app_relative_path"

  if [[ ! -d "$app_path" ]]; then
    echo "error: $label archived app missing at $app_path" >&2
    exit 1
  fi

  local actual_bundle_id
  actual_bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app_path/Info.plist")"
  if [[ "$actual_bundle_id" != "$bundle_id" ]]; then
    echo "error: $label archive bundle id is $actual_bundle_id, expected $bundle_id" >&2
    exit 1
  fi

  codesign --verify --strict --deep "$app_path"

  if [[ "$label" == "iOS" ]]; then
    local capabilities
    capabilities="$(/usr/libexec/PlistBuddy -c 'Print :UIRequiredDeviceCapabilities' "$app_path/Info.plist" 2>/dev/null || true)"
    if [[ "$capabilities" != *"arm64"* ]]; then
      echo "error: iOS archive UIRequiredDeviceCapabilities is ${capabilities:-missing}, expected arm64" >&2
      exit 1
    fi
    if [[ "$capabilities" == *"camera"* ]]; then
      echo "error: iOS archive UIRequiredDeviceCapabilities contains camera, which App Store validation rejects for iOS 18.0" >&2
      exit 1
    fi
  fi

  local signing_authority
  signing_authority="$(
    codesign -dvv "$app_path" 2>&1 |
      awk -F= '/^Authority=/ { print $2 }' |
      paste -sd '|' -
  )"

  if [[ "$signing_authority" != *"Apple Distribution"* &&
        "$signing_authority" != *"3rd Party Mac Developer Application"* &&
        "$signing_authority" != *"iPhone Distribution"* ]]; then
    echo "error: $label archive is not signed with an App Store distribution identity." >&2
    echo "       Signing authorities: ${signing_authority:-unknown}" >&2
    exit 1
  fi

  echo "✓ $label archive validated at $archive"
}

archive_mac() {
  local archive="$ARCHIVE_DIR/BlitzRecorder-macOS.xcarchive"
  local signing_args=()
  while IFS= read -r -d '' arg; do
    signing_args+=("$arg")
  done < <(signing_args_for_profile "$MAC_PROVISIONING_PROFILE_SPECIFIER")

  run_cmd xcodebuild \
    -project BlitzRecorder.xcodeproj \
    -scheme BlitzRecorder \
    -configuration Release \
    -destination "generic/platform=macOS" \
    -archivePath "$archive" \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    ${signing_args[@]+"${signing_args[@]}"} \
    ${PROVISIONING_ARGS[@]+"${PROVISIONING_ARGS[@]}"} \
    archive

  if [[ "$DRY_RUN" != "1" ]]; then
    validate_archive "$archive" "Products/Applications/BlitzRecorder.app" "dev.blitzreels.blitzrecorder" "macOS"
  fi

  if [[ "$EXPORT" == "1" || "$UPLOAD" == "1" ]]; then
    local plist="$EXPORT_DIR/macOS-export-options.plist"
    write_export_options "$plist" "dev.blitzreels.blitzrecorder" "$MAC_PROVISIONING_PROFILE_SPECIFIER" >/dev/null
    run_cmd xcodebuild \
      -exportArchive \
      -archivePath "$archive" \
      -exportPath "$EXPORT_DIR/macOS" \
      -exportOptionsPlist "$plist" \
      ${PROVISIONING_ARGS[@]+"${PROVISIONING_ARGS[@]}"}
  fi
}

archive_ios() {
  local archive="$ARCHIVE_DIR/BlitzRecorderCamera-iOS.xcarchive"
  local signing_args=()
  while IFS= read -r -d '' arg; do
    signing_args+=("$arg")
  done < <(signing_args_for_profile "$IOS_PROVISIONING_PROFILE_SPECIFIER")

  run_cmd xcodebuild \
    -project BlitzRecorder.xcodeproj \
    -scheme BlitzRecorderCamera \
    -configuration Release \
    -destination "generic/platform=iOS" \
    -archivePath "$archive" \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    ${signing_args[@]+"${signing_args[@]}"} \
    ${PROVISIONING_ARGS[@]+"${PROVISIONING_ARGS[@]}"} \
    archive

  if [[ "$DRY_RUN" != "1" ]]; then
    validate_archive "$archive" "Products/Applications/BlitzRecorderCamera.app" "dev.blitzreels.blitzrecorder.camera" "iOS"
  fi

  if [[ "$EXPORT" == "1" || "$UPLOAD" == "1" ]]; then
    local plist="$EXPORT_DIR/iOS-export-options.plist"
    write_export_options "$plist" "dev.blitzreels.blitzrecorder.camera" "$IOS_PROVISIONING_PROFILE_SPECIFIER" >/dev/null
    run_cmd xcodebuild \
      -exportArchive \
      -archivePath "$archive" \
      -exportPath "$EXPORT_DIR/iOS" \
      -exportOptionsPlist "$plist" \
      ${PROVISIONING_ARGS[@]+"${PROVISIONING_ARGS[@]}"}
  fi
}

preflight_if_needed

case "$TARGET" in
  mac)
    archive_mac
    ;;
  ios)
    archive_ios
    ;;
  all)
    archive_mac
    archive_ios
    ;;
esac

if [[ "$DRY_RUN" != "1" ]]; then
  TARGET="$TARGET" Scripts/validate-submission-artifacts.sh
fi
