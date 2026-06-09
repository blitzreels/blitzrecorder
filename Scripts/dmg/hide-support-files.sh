#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: Scripts/dmg/hide-support-files.sh PATH_TO_DMG" >&2
  exit 2
fi

DMG_PATH="$1"
[[ -f "$DMG_PATH" ]] || { echo "error: DMG does not exist: $DMG_PATH" >&2; exit 1; }

TMP_DIR="$(mktemp -d)"
RW_DMG="$TMP_DIR/rw.dmg"
HIDDEN_DMG="$TMP_DIR/hidden.dmg"
ATTACH_LOG="$TMP_DIR/attach.log"
MOUNT_POINT=""
DEVICE_NAME=""

cleanup() {
  if [[ -n "$DEVICE_NAME" ]]; then
    hdiutil detach "$DEVICE_NAME" >/dev/null 2>&1 || true
  elif [[ -n "$MOUNT_POINT" ]]; then
    hdiutil detach "$MOUNT_POINT" >/dev/null 2>&1 || true
  fi
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

hdiutil convert "$DMG_PATH" -format UDRW -o "$RW_DMG" >/dev/null
hdiutil attach "$RW_DMG" -readwrite -noverify -noautoopen -nobrowse >"$ATTACH_LOG"
DEVICE_NAME="$(awk '/^\/dev\// { print $1; exit }' "$ATTACH_LOG")"
MOUNT_POINT="$(awk -F '\t' '/\/Volumes\// { print $NF; exit }' "$ATTACH_LOG")"
if [[ -z "$MOUNT_POINT" ]]; then
  echo "error: unable to determine DMG mount point." >&2
  cat "$ATTACH_LOG" >&2
  exit 1
fi

for SUPPORT_NAME in ".background" ".VolumeIcon.icns"; do
  SUPPORT_PATH="$MOUNT_POINT/$SUPPORT_NAME"
  if [[ -e "$SUPPORT_PATH" ]]; then
    chflags -R hidden "$SUPPORT_PATH"
    if command -v SetFile >/dev/null 2>&1; then
      SetFile -a V "$SUPPORT_PATH" || true
    fi
  fi
done

rm -rf "$MOUNT_POINT/.fseventsd"
hdiutil detach "${DEVICE_NAME:-$MOUNT_POINT}" >/dev/null
DEVICE_NAME=""
MOUNT_POINT=""

hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -o "$HIDDEN_DMG" >/dev/null
mv "$HIDDEN_DMG" "$DMG_PATH"
