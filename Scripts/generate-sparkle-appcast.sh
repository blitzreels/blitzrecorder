#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DMG_PATH=""
OUTPUT_DIR=""
REPO="${GITHUB_REPOSITORY:-}"
TAG="${GITHUB_REF_NAME:-}"
RELEASE_NOTES_PATH=""
EXISTING_APPCAST_PATH=""
APPCAST_NAME="appcast.xml"
MAXIMUM_VERSIONS="${SPARKLE_MAXIMUM_VERSIONS:-3}"

usage() {
  cat <<'USAGE'
Usage:
  Scripts/generate-sparkle-appcast.sh --dmg PATH [options]

Options:
  --dmg PATH                Notarized DMG to publish in the appcast.
  --output-dir DIR          Directory for appcast output. Defaults to the DMG directory.
  --repo OWNER/REPO         GitHub repository. Defaults to GITHUB_REPOSITORY.
  --tag TAG                 Release tag. Defaults to GITHUB_REF_NAME.
  --release-notes PATH      Markdown, text, or HTML release notes to embed.
  --existing-appcast PATH   Existing appcast.xml to preserve older entries.
  --appcast-name NAME       Output appcast filename. Defaults to appcast.xml.
  -h, --help                Show this help.

Required environment:
  SPARKLE_PRIVATE_ED_KEY or SPARKLE_PRIVATE_ED_KEY_FILE

Optional environment:
  SPARKLE_DOWNLOAD_URL_PREFIX
  SPARKLE_FULL_RELEASE_NOTES_URL
  SPARKLE_PRODUCT_URL
  SPARKLE_MAXIMUM_VERSIONS
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dmg)
      [[ $# -ge 2 ]] || { echo "error: --dmg needs a path" >&2; exit 2; }
      DMG_PATH="$2"
      shift
      ;;
    --output-dir)
      [[ $# -ge 2 ]] || { echo "error: --output-dir needs a directory" >&2; exit 2; }
      OUTPUT_DIR="$2"
      shift
      ;;
    --repo)
      [[ $# -ge 2 ]] || { echo "error: --repo needs OWNER/REPO" >&2; exit 2; }
      REPO="$2"
      shift
      ;;
    --tag)
      [[ $# -ge 2 ]] || { echo "error: --tag needs a release tag" >&2; exit 2; }
      TAG="$2"
      shift
      ;;
    --release-notes)
      [[ $# -ge 2 ]] || { echo "error: --release-notes needs a path" >&2; exit 2; }
      RELEASE_NOTES_PATH="$2"
      shift
      ;;
    --existing-appcast)
      [[ $# -ge 2 ]] || { echo "error: --existing-appcast needs a path" >&2; exit 2; }
      EXISTING_APPCAST_PATH="$2"
      shift
      ;;
    --appcast-name)
      [[ $# -ge 2 ]] || { echo "error: --appcast-name needs a filename" >&2; exit 2; }
      APPCAST_NAME="$2"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown option $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

read_secret_value() {
  local value_name="$1"
  local file_name="${value_name}_FILE"
  if [[ -n "${!file_name:-}" ]]; then
    cat "${!file_name}"
  elif [[ -n "${!value_name:-}" ]]; then
    printf '%s' "${!value_name}"
  else
    echo "error: missing $value_name or $file_name" >&2
    exit 2
  fi
}

find_generate_appcast() {
  local candidate
  for candidate in \
    "$ROOT/.build/artifacts/sparkle/Sparkle/bin/generate_appcast" \
    "$ROOT/.build/checkouts/Sparkle/bin/generate_appcast"
  do
    if [[ -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  candidate="$(
    find "$ROOT/.build/artifacts" "$ROOT/.build/checkouts" \
      -type f \
      -name generate_appcast \
      -perm -111 \
      -print \
      -quit 2>/dev/null || true
  )"
  [[ -n "$candidate" ]] || {
    echo "error: Sparkle generate_appcast was not found. Build once with DIRECT_DISTRIBUTION=1 first." >&2
    exit 1
  }
  printf '%s\n' "$candidate"
}

cd "$ROOT"

[[ -n "$DMG_PATH" ]] || { echo "error: --dmg is required" >&2; usage >&2; exit 2; }
[[ -f "$DMG_PATH" ]] || { echo "error: DMG does not exist: $DMG_PATH" >&2; exit 2; }
[[ -n "$REPO" ]] || { echo "error: repo is required via --repo or GITHUB_REPOSITORY" >&2; exit 2; }
[[ -n "$TAG" ]] || { echo "error: tag is required via --tag or GITHUB_REF_NAME" >&2; exit 2; }

GENERATE_APPCAST="$(find_generate_appcast)"
OUTPUT_DIR="${OUTPUT_DIR:-$(dirname "$DMG_PATH")}"
mkdir -p "$OUTPUT_DIR"

DOWNLOAD_URL_PREFIX="${SPARKLE_DOWNLOAD_URL_PREFIX:-https://github.com/${REPO}/releases/download/${TAG}/}"
FULL_RELEASE_NOTES_URL="${SPARKLE_FULL_RELEASE_NOTES_URL:-https://github.com/${REPO}/releases/tag/${TAG}}"
PRODUCT_URL="${SPARKLE_PRODUCT_URL:-https://blitzrecorder.com}"

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

DMG_BASENAME="$(basename "$DMG_PATH")"
ARCHIVE_PATH="$WORK_DIR/$DMG_BASENAME"
ditto "$DMG_PATH" "$ARCHIVE_PATH"

if [[ -n "$EXISTING_APPCAST_PATH" && -f "$EXISTING_APPCAST_PATH" ]]; then
  cp "$EXISTING_APPCAST_PATH" "$WORK_DIR/$APPCAST_NAME"
fi

NOTES_DEST="$WORK_DIR/${DMG_BASENAME%.*}.md"
if [[ -n "$RELEASE_NOTES_PATH" && -f "$RELEASE_NOTES_PATH" ]]; then
  cp "$RELEASE_NOTES_PATH" "$NOTES_DEST"
else
  cat >"$NOTES_DEST" <<EOF
# BlitzRecorder ${TAG}

See the full release notes on GitHub:
${FULL_RELEASE_NOTES_URL}
EOF
fi

read_secret_value SPARKLE_PRIVATE_ED_KEY | "$GENERATE_APPCAST" \
  --ed-key-file - \
  --download-url-prefix "$DOWNLOAD_URL_PREFIX" \
  --full-release-notes-url "$FULL_RELEASE_NOTES_URL" \
  --link "$PRODUCT_URL" \
  --embed-release-notes \
  --maximum-versions "$MAXIMUM_VERSIONS" \
  -o "$WORK_DIR/$APPCAST_NAME" \
  "$WORK_DIR" >/dev/null

cp "$WORK_DIR/$APPCAST_NAME" "$OUTPUT_DIR/$APPCAST_NAME"
echo "$OUTPUT_DIR/$APPCAST_NAME"
