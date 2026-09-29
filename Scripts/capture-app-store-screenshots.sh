#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODE="${1:---mac}"

MAC_APP_NAME="BlitzRecorder"
MAC_APP_PATH="$ROOT/build/BlitzRecorder.app"
MAC_OUTPUT_DIR="$ROOT/AppStore/ScreenshotAssets/macOS"
usage() {
  cat <<'USAGE'
Usage:
  Scripts/capture-app-store-screenshots.sh [--mac]

Captures the real Mac app UI into the App Store upload folder:
  AppStore/ScreenshotAssets/macOS/

Environment overrides:
  MAC_CAPTURE_WAIT_SECONDS=12
  MAC_WINDOW_SIZE="1440x900"

Notes:
  - Mac capture launches the app and renders its current content view to PNG.
  - Review the captured state before App Store upload.
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

  capture_mac_screenshot "01-main-recording-canvas.png"
}

capture_mac_screenshot() {
  local file_name="$1"
  local output="$MAC_OUTPUT_DIR/$file_name"
  local requested_output="/tmp/blitzrecorder-${file_name}"
  local app_pid
  local window_size="${MAC_WINDOW_SIZE:-1440x900}"
  rm -f "$requested_output" /tmp/blitzrecorder-screenshot.log

  BLITZRECORDER_SCREENSHOT_MODE=1 \
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

case "$MODE" in
  --mac)
    capture_mac
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
