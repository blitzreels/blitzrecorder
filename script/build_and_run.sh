#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="BlitzRecorder"
BUNDLE_ID="dev.blitzreels.blitzrecorder"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILT_APP="$ROOT_DIR/build/$APP_NAME.app"
INSTALLED_APP="/Applications/$APP_NAME.app"
PERMISSION_LOG="/tmp/$APP_NAME.permission-state.log"

usage() {
  echo "usage: $0 [run|--debug|--logs|--telemetry|--verify|--reset-screen-permission]" >&2
}

stop_app() {
  osascript -e "tell application \"$APP_NAME\" to quit" >/dev/null 2>&1 || true
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
}

build_app() {
  ENTITLEMENTS_PATH="$ROOT_DIR/BlitzRecorder.local.entitlements" "$ROOT_DIR/Scripts/package-app.sh" >/dev/null
  rm -rf "$INSTALLED_APP"
  /usr/bin/ditto "$BUILT_APP" "$INSTALLED_APP"
}

open_app() {
  rm -f "$PERMISSION_LOG"
  /usr/bin/open "$INSTALLED_APP"
}

show_permission_state() {
  sleep 2
  if [[ -f "$PERMISSION_LOG" ]]; then
    tail -n 5 "$PERMISSION_LOG"
  else
    echo "No permission diagnostic written yet: $PERMISSION_LOG" >&2
  fi
}

case "$MODE" in
  run)
    stop_app
    build_app
    open_app
    ;;
  --debug|debug)
    stop_app
    build_app
    lldb -- "$INSTALLED_APP/Contents/MacOS/$APP_NAME"
    ;;
  --logs|logs)
    stop_app
    build_app
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    stop_app
    build_app
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    stop_app
    build_app
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    show_permission_state
    ;;
  --reset-screen-permission|reset-screen-permission)
    stop_app
    tccutil reset ScreenCapture "$BUNDLE_ID"
    echo "Reset ScreenCapture for $BUNDLE_ID"
    /usr/bin/open "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
    echo "Run $0, then enable $APP_NAME in System Settings and quit/reopen."
    ;;
  *)
    usage
    exit 2
    ;;
esac
