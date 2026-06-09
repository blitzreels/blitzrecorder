#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED_DATA="$ROOT/build/XcodeDerivedData"
MAC_APP="$DERIVED_DATA/Build/Products/Release/BlitzRecorder.app"
IOS_APP="$DERIVED_DATA/Build/Products/Release-iphoneos/BlitzRecorderCamera.app"
EXPECTED_MARKETING_VERSION="0.1.2"
EXPECTED_BUILD_NUMBER="3"

cd "$ROOT"

plist_value() {
  /usr/libexec/PlistBuddy -c "Print :$2" "$1" 2>/dev/null || true
}

require_plist_value() {
  local plist="$1"
  local key="$2"
  local expected="$3"
  local value
  value="$(plist_value "$plist" "$key")"
  [[ "$value" == "$expected" ]] || {
    echo "error: $plist $key is ${value:-missing}, expected $expected" >&2
    exit 1
  }
}

require_plist_contains() {
  local plist="$1"
  local key="$2"
  local expected="$3"
  local value
  value="$(plist_value "$plist" "$key")"
  [[ "$value" == *"$expected"* ]] || {
    echo "error: $plist $key does not contain $expected" >&2
    exit 1
  }
}

reject_plist_key() {
  local plist="$1"
  local key="$2"
  if /usr/libexec/PlistBuddy -c "Print :$key" "$plist" >/dev/null 2>&1; then
    echo "error: $plist unexpectedly contains $key" >&2
    exit 1
  fi
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
  local dimensions
  local has_alpha

  [[ -f "$file" ]] || {
    echo "error: missing image: $file" >&2
    exit 1
  }

  dimensions="$(image_dimensions "$file")"
  [[ "$dimensions" == "$expected_dimensions" ]] || {
    echo "error: $file is ${dimensions:-unknown}, expected $expected_dimensions" >&2
    exit 1
  }

  has_alpha="$(image_has_alpha "$file")"
  [[ "$has_alpha" == "no" ]] || {
    echo "error: $file has alpha channel; App Store icons must be opaque" >&2
    exit 1
  }
}

swift test
Scripts/test-app-store-connect-readiness.py
Scripts/test-app-store-connect-bootstrap.py
Scripts/validate-launch-readiness.sh

xcodebuild \
  -project BlitzRecorder.xcodeproj \
  -scheme BlitzRecorder \
  -configuration Release \
  -destination "platform=macOS" \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO \
  build

xcodebuild \
  -project BlitzRecorder.xcodeproj \
  -scheme BlitzRecorderCamera \
  -configuration Release \
  -sdk iphoneos \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO \
  build

[[ -f "$MAC_APP/Contents/Resources/BlitzRecorder.icns" ]] || {
  echo "error: Mac app is missing BlitzRecorder.icns" >&2
  exit 1
}

[[ -f "$MAC_APP/Contents/Resources/PrivacyInfo.xcprivacy" ]] || {
  echo "error: Mac app is missing PrivacyInfo.xcprivacy" >&2
  exit 1
}

[[ -f "$IOS_APP/PrivacyInfo.xcprivacy" ]] || {
  echo "error: iOS app is missing PrivacyInfo.xcprivacy" >&2
  exit 1
}

[[ -f "$IOS_APP/Icon-App-60x60@3x.png" ]] || {
  echo "error: iOS app is missing primary iPhone icon PNG" >&2
  exit 1
}

require_plist_value "$MAC_APP/Contents/Info.plist" "CFBundleIdentifier" "dev.blitzreels.blitzrecorder"
require_plist_value "$MAC_APP/Contents/Info.plist" "CFBundleShortVersionString" "$EXPECTED_MARKETING_VERSION"
require_plist_value "$MAC_APP/Contents/Info.plist" "CFBundleVersion" "$EXPECTED_BUILD_NUMBER"
require_plist_value "$MAC_APP/Contents/Info.plist" "LSApplicationCategoryType" "public.app-category.video"
require_plist_value "$MAC_APP/Contents/Info.plist" "ITSAppUsesNonExemptEncryption" "false"
require_plist_contains "$MAC_APP/Contents/Info.plist" "NSBonjourServices" "_blitzrecorder-camera._tcp"
require_plist_contains "$MAC_APP/Contents/Info.plist" "NSLocalNetworkUsageDescription" "local network"
require_plist_contains "$MAC_APP/Contents/Info.plist" "NSCameraUsageDescription" "camera"
require_plist_contains "$MAC_APP/Contents/Info.plist" "NSMicrophoneUsageDescription" "microphone"
require_plist_contains "$MAC_APP/Contents/Info.plist" "NSScreenCaptureUsageDescription" "screen"
require_plist_value "$MAC_APP/Contents/Resources/PrivacyInfo.xcprivacy" "NSPrivacyTracking" "false"
require_plist_contains "$MAC_APP/Contents/Resources/PrivacyInfo.xcprivacy" "NSPrivacyAccessedAPITypes" "NSPrivacyAccessedAPICategoryUserDefaults"
require_plist_contains "$MAC_APP/Contents/Resources/PrivacyInfo.xcprivacy" "NSPrivacyAccessedAPITypes" "NSPrivacyAccessedAPICategoryFileTimestamp"
require_plist_value "$IOS_APP/Info.plist" "CFBundleIdentifier" "dev.blitzreels.blitzrecorder.camera"
require_plist_value "$IOS_APP/Info.plist" "CFBundleShortVersionString" "$EXPECTED_MARKETING_VERSION"
require_plist_value "$IOS_APP/Info.plist" "CFBundleVersion" "$EXPECTED_BUILD_NUMBER"
require_plist_value "$IOS_APP/Info.plist" "ITSAppUsesNonExemptEncryption" "false"
require_plist_contains "$IOS_APP/Info.plist" "UIDeviceFamily" "1"
require_plist_contains "$IOS_APP/Info.plist" "UIDeviceFamily" "2"
require_plist_contains "$IOS_APP/Info.plist" "UIRequiredDeviceCapabilities" "arm64"
if /usr/libexec/PlistBuddy -c "Print :UIRequiredDeviceCapabilities" "$IOS_APP/Info.plist" 2>/dev/null | grep -Fq "camera"; then
  echo "error: $IOS_APP/Info.plist UIRequiredDeviceCapabilities contains camera, which App Store validation rejects for iOS 18.0" >&2
  exit 1
fi
require_plist_contains "$IOS_APP/Info.plist" "NSBonjourServices" "_blitzrecorder-camera._tcp"
require_plist_contains "$IOS_APP/Info.plist" "NSLocalNetworkUsageDescription" "local network"
require_plist_contains "$IOS_APP/Info.plist" "NSCameraUsageDescription" "camera"
require_plist_contains "$IOS_APP/Info.plist" "NSMicrophoneUsageDescription" "microphone"
require_plist_value "$IOS_APP/PrivacyInfo.xcprivacy" "NSPrivacyTracking" "false"
require_plist_contains "$IOS_APP/PrivacyInfo.xcprivacy" "NSPrivacyAccessedAPITypes" "NSPrivacyAccessedAPICategoryUserDefaults"
require_plist_contains "$IOS_APP/PrivacyInfo.xcprivacy" "NSPrivacyAccessedAPITypes" "NSPrivacyAccessedAPICategoryFileTimestamp"
require_plist_contains "$IOS_APP/PrivacyInfo.xcprivacy" "NSPrivacyAccessedAPITypes" "NSPrivacyAccessedAPICategoryDiskSpace"
require_image "$IOS_APP/Icon-App-60x60@3x.png" "180x180"
require_image "$IOS_APP/Icon-App-1024x1024@1x.png" "1024x1024"

echo "Local App Store preflight passed."
