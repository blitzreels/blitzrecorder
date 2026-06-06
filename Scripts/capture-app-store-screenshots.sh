#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODE="${1:---all}"

MAC_APP_NAME="BlitzRecorder"
MAC_APP_PATH="$ROOT/build/BlitzRecorder.app"
MAC_OUTPUT_DIR="$ROOT/AppStore/ScreenshotAssets/macOS"
IPHONE_OUTPUT_DIR="$ROOT/AppStore/ScreenshotAssets/iPhone-6.9"
IPAD_OUTPUT_DIR="$ROOT/AppStore/ScreenshotAssets/iPad-13"
IOS_BUNDLE_ID="dev.blitzreels.blitzrecorder.camera"
IOS_APP_PATH="$ROOT/build/Debug-iphonesimulator/BlitzRecorderCamera.app"

usage() {
  cat <<'USAGE'
Usage:
  Scripts/capture-app-store-screenshots.sh [--all|--mac|--iphone|--ipad]

Captures real app UI screenshots into the App Store upload folders:
  AppStore/ScreenshotAssets/macOS/
  AppStore/ScreenshotAssets/iPhone-6.9/
  AppStore/ScreenshotAssets/iPad-13/

Environment overrides:
  MAC_CAPTURE_WAIT_SECONDS=12
  MAC_WINDOW_SIZE="1440x900"
  IPHONE_SIMULATOR_NAME="BlitzRecorder iPhone 6.9"
  IPHONE_DEVICE_TYPE="com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro-Max"
  IPAD_SIMULATOR_NAME="BlitzRecorder iPad 13"
  IPAD_DEVICE_TYPE="com.apple.CoreSimulator.SimDeviceType.iPad-Pro-13-inch-M4-8GB"

Notes:
  - Mac capture launches the real app UI in screenshot mode and asks the app to
    render its content view to PNG. This avoids host screen-recording permission.
  - Simulator screenshots are useful for App Store asset prep, but final iPhone/iPad
    screenshots should be reviewed against the real companion workflow before upload.
USAGE
}

if [[ "$MODE" == "--help" || "$MODE" == "-h" ]]; then
  usage
  exit 0
fi

require_tool() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "error: missing required tool: $1" >&2
    exit 1
  }
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

assert_dimensions_one_of() {
  local file="$1"
  shift
  local dimensions
  dimensions="$(image_dimensions "$file")"
  for accepted in "$@"; do
    if [[ "$dimensions" == "$accepted" ]]; then
      echo "✓ $(basename "$file") captured at $dimensions"
      return 0
    fi
  done
  echo "error: $(basename "$file") captured at ${dimensions:-unknown}; expected one of: $*" >&2
  return 1
}

capture_mac() {
  require_tool sips

  mkdir -p "$MAC_OUTPUT_DIR"
  "$ROOT/Scripts/package-app.sh" >/dev/null

  pkill -x "$MAC_APP_NAME" >/dev/null 2>&1 || true
  for _ in 1 2 3 4 5; do
    pgrep -x "$MAC_APP_NAME" >/dev/null 2>&1 || break
    sleep 1
  done
  if pgrep -x "$MAC_APP_NAME" >/dev/null 2>&1; then
    pkill -9 -x "$MAC_APP_NAME" >/dev/null 2>&1 || true
  fi

  capture_mac_variant "" "01-main-recording-canvas.png"
  capture_mac_variant "plan" "02-plan-popover.png"
  capture_mac_variant "iphone-controls" "03-iphone-camera-controls.png"
}

capture_mac_variant() {
  local variant="$1"
  local file_name="$2"
  local output="$MAC_OUTPUT_DIR/$file_name"
  local requested_output="/tmp/blitzrecorder-${file_name}"
  local app_pid
  local window_size="${MAC_WINDOW_SIZE:-1440x900}"
  rm -f "$requested_output" /tmp/blitzrecorder-screenshot.log

  BLITZRECORDER_SCREENSHOT_MODE=1 \
    BLITZRECORDER_SCREENSHOT_VARIANT="$variant" \
    BLITZRECORDER_SCREENSHOT_WINDOW_SIZE="$window_size" \
    BLITZRECORDER_SCREENSHOT_OUTPUT="$requested_output" \
    "$MAC_APP_PATH/Contents/MacOS/$MAC_APP_NAME" >/tmp/blitzrecorder-screenshot.log 2>&1 &
  app_pid="$!"

  local deadline=$((SECONDS + ${MAC_CAPTURE_WAIT_SECONDS:-12}))
  while kill -0 "$app_pid" >/dev/null 2>&1 && [[ "$SECONDS" -lt "$deadline" ]]; do
    sleep 0.25
  done

  if kill -0 "$app_pid" >/dev/null 2>&1; then
    kill "$app_pid" >/dev/null 2>&1 || true
  fi
  wait "$app_pid" >/dev/null 2>&1 || true

  local written_output
  written_output="$(
    awk -F= '/^BLITZRECORDER_SCREENSHOT_WRITTEN=/ { value=$2 } END { print value }' /tmp/blitzrecorder-screenshot.log
  )"

  if [[ -z "$written_output" || ! -s "$written_output" ]]; then
    cat /tmp/blitzrecorder-screenshot.log >&2 || true
    echo "error: Mac screenshot was not written" >&2
    exit 1
  fi

  cp "$written_output" "$output"
  rm -f "$written_output"
  assert_dimensions_one_of "$output" "1440x900" "2880x1800"
}

latest_ios_runtime() {
  xcrun simctl list runtimes --json | python3 -c '
import json, re, sys
data = json.load(sys.stdin)
runtimes = [
    runtime for runtime in data.get("runtimes", [])
    if runtime.get("platform") == "iOS" and runtime.get("isAvailable")
]
def key(runtime):
    version = runtime.get("version") or "0"
    return tuple(int(part) for part in re.findall(r"\d+", version))
runtimes.sort(key=key)
if not runtimes:
    raise SystemExit("No available iOS simulator runtime found")
print(runtimes[-1]["identifier"])
'
}

find_or_create_simulator() {
  local name="$1"
  local device_type="$2"
  local runtime="$3"
  local udid

  udid="$(xcrun simctl list devices --json | python3 -c '
import json, sys
name = sys.argv[1]
data = json.load(sys.stdin)
for devices in data.get("devices", {}).values():
    for device in devices:
        if device.get("name") == name and device.get("isAvailable", True):
            print(device["udid"])
            raise SystemExit(0)
' "$name")"

  if [[ -n "$udid" ]]; then
    echo "$udid"
    return
  fi

  xcrun simctl create "$name" "$device_type" "$runtime"
}

build_ios_for_simulator() {
  local udid="$1"
  xcodebuild \
    -project "$ROOT/BlitzRecorder.xcodeproj" \
    -target BlitzRecorderCamera \
    -configuration Debug \
    -sdk iphonesimulator \
    -destination "platform=iOS Simulator,id=$udid" \
    SYMROOT="$ROOT/build" \
    build >/dev/null
}

capture_simulator() {
  local label="$1"
  local output_dir="$2"
  local simulator_name="$3"
  local device_type="$4"
  local accepted_csv="$5"          # space-separated accepted dimensions
  shift 5
  local variant_specs=("$@")       # "file_name:variant" entries (relaunch per shot)

  require_tool xcrun
  require_tool sips

  mkdir -p "$output_dir"
  local runtime
  runtime="$(latest_ios_runtime)"
  local udid
  udid="$(find_or_create_simulator "$simulator_name" "$device_type" "$runtime")"

  xcrun simctl boot "$udid" >/dev/null 2>&1 || true
  xcrun simctl bootstatus "$udid" -b >/dev/null
  build_ios_for_simulator "$udid"
  xcrun simctl uninstall "$udid" "$IOS_BUNDLE_ID" >/dev/null 2>&1 || true
  xcrun simctl install "$udid" "$IOS_APP_PATH"

  local accepted_dimensions
  read -r -a accepted_dimensions <<<"$accepted_csv"

  local spec file_name variant output
  for spec in "${variant_specs[@]}"; do
    file_name="${spec%%:*}"
    variant="${spec##*:}"
    xcrun simctl terminate "$udid" "$IOS_BUNDLE_ID" >/dev/null 2>&1 || true
    SIMCTL_CHILD_BLITZRECORDER_CAMERA_SCREENSHOT_MODE=1 \
      SIMCTL_CHILD_BLITZRECORDER_CAMERA_SCREENSHOT_VARIANT="$variant" \
      xcrun simctl launch "$udid" "$IOS_BUNDLE_ID" \
        --blitzrecorder-camera-screenshot-mode \
        "--blitzrecorder-camera-screenshot-variant=$variant" >/dev/null
    sleep "${SIMULATOR_CAPTURE_WAIT_SECONDS:-4}"

    output="$output_dir/$file_name.png"
    xcrun simctl io "$udid" screenshot --type=png "$output" >/dev/null
    assert_dimensions_one_of "$output" "${accepted_dimensions[@]}"
    echo "✓ $label/$file_name captured ($variant)"
  done
}

capture_iphone() {
  # Capture the real UI to a raw/ subfolder, then compose branded marketing
  # screenshots (gradient + headline + device bezel) into the upload folder.
  local raw_dir="$IPHONE_OUTPUT_DIR/raw"
  capture_simulator \
    "iPhone 6.9-inch" \
    "$raw_dir" \
    "${IPHONE_SIMULATOR_NAME:-BlitzRecorder iPhone 6.9}" \
    "${IPHONE_DEVICE_TYPE:-com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro-Max}" \
    "1260x2736 1290x2796 1320x2868" \
    "01-pairing-screen:pairing" \
    "02-connected:connected" \
    "03-recording:recording" \
    "04-transfer:transfer"
  swift "$ROOT/Scripts/compose-app-store-screenshots.swift" "$raw_dir" "$IPHONE_OUTPUT_DIR"
}

capture_ipad() {
  capture_simulator \
    "iPad 13-inch" \
    "$IPAD_OUTPUT_DIR" \
    "${IPAD_SIMULATOR_NAME:-BlitzRecorder iPad 13}" \
    "${IPAD_DEVICE_TYPE:-com.apple.CoreSimulator.SimDeviceType.iPad-Pro-13-inch-M4-8GB}" \
    "2048x2732 2064x2752" \
    "01-pairing-screen:pairing"
}

case "$MODE" in
  --all)
    capture_mac
    capture_iphone
    capture_ipad
    ;;
  --mac)
    capture_mac
    ;;
  --iphone)
    capture_iphone
    ;;
  --ipad)
    capture_ipad
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac

"$ROOT/Scripts/validate-submission-artifacts.sh"
