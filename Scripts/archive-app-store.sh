#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TARGET="${TARGET:-all}"
TEAM_ID="${TEAM_ID:-${DEVELOPMENT_TEAM:-}}"
EXPORT="${EXPORT:-0}"
UPLOAD="${UPLOAD:-0}"
DRY_RUN="${DRY_RUN:-0}"
SKIP_PREFLIGHT="${SKIP_PREFLIGHT:-0}"
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

if [[ "$TARGET" != "all" && "$TARGET" != "mac" && "$TARGET" != "ios" ]]; then
  echo "TARGET must be mac, ios, or all." >&2
  exit 2
fi

for boolean_name in EXPORT UPLOAD ALLOW_PROVISIONING_UPDATES SKIP_PREFLIGHT DRY_RUN; do
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

preflight_if_needed() {
  if [[ "$SKIP_PREFLIGHT" == "1" || "$DRY_RUN" == "1" ]]; then
    return
  fi

  Scripts/preflight-app-store-local.sh
  Scripts/validate-submission-artifacts.sh
}

write_export_options() {
  local plist="$1"
  local destination="export"

  if [[ "$UPLOAD" == "1" ]]; then
    destination="upload"
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
  <string>automatic</string>
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
  run_cmd xcodebuild \
    -project BlitzRecorder.xcodeproj \
    -scheme BlitzRecorder \
    -configuration Release \
    -destination "generic/platform=macOS" \
    -archivePath "$archive" \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    ${PROVISIONING_ARGS[@]+"${PROVISIONING_ARGS[@]}"} \
    archive

  if [[ "$DRY_RUN" != "1" ]]; then
    validate_archive "$archive" "Products/Applications/BlitzRecorder.app" "dev.blitzreels.blitzrecorder" "macOS"
  fi

  if [[ "$EXPORT" == "1" || "$UPLOAD" == "1" ]]; then
    local plist="$EXPORT_DIR/macOS-export-options.plist"
    write_export_options "$plist" >/dev/null
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
  run_cmd xcodebuild \
    -project BlitzRecorder.xcodeproj \
    -scheme BlitzRecorderCamera \
    -configuration Release \
    -destination "generic/platform=iOS" \
    -archivePath "$archive" \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    ${PROVISIONING_ARGS[@]+"${PROVISIONING_ARGS[@]}"} \
    archive

  if [[ "$DRY_RUN" != "1" ]]; then
    validate_archive "$archive" "Products/Applications/BlitzRecorderCamera.app" "dev.blitzreels.blitzrecorder.camera" "iOS"
  fi

  if [[ "$EXPORT" == "1" || "$UPLOAD" == "1" ]]; then
    local plist="$EXPORT_DIR/iOS-export-options.plist"
    write_export_options "$plist" >/dev/null
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
  Scripts/validate-submission-artifacts.sh
fi
