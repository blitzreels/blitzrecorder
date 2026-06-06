#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_DIR="$ROOT/build/public-snapshot"
BRANCH="public-main"
REMOTE=""
PUSH=0

usage() {
  cat <<'USAGE'
Usage:
  Scripts/create-public-snapshot.sh [options]

Options:
  --output-dir DIR       Snapshot directory. Defaults to build/public-snapshot.
  --branch NAME          Branch name in the snapshot repo. Defaults to public-main.
  --remote URL           Optional Git remote to add to the snapshot repo.
  --push                 Push the snapshot branch to --remote.
  -h, --help             Show this help.

Creates a fresh Git repository from the current working tree, excluding local
private/build artifacts and old Git history. Use this when the existing repo
history is not safe to make public.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output-dir)
      [[ $# -ge 2 ]] || { echo "error: --output-dir needs a directory" >&2; exit 2; }
      OUTPUT_DIR="$2"
      shift
      ;;
    --branch)
      [[ $# -ge 2 ]] || { echo "error: --branch needs a name" >&2; exit 2; }
      BRANCH="$2"
      shift
      ;;
    --remote)
      [[ $# -ge 2 ]] || { echo "error: --remote needs a URL" >&2; exit 2; }
      REMOTE="$2"
      shift
      ;;
    --push)
      PUSH=1
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

require_command() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "error: missing required command: $1" >&2
    exit 1
  }
}

require_command git
require_command rsync

OUTPUT_DIR="$(cd "$(dirname "$OUTPUT_DIR")" && pwd)/$(basename "$OUTPUT_DIR")"
case "$OUTPUT_DIR" in
  "$ROOT"/build/*) ;;
  *)
    echo "error: refusing to delete output outside $ROOT/build: $OUTPUT_DIR" >&2
    exit 2
    ;;
esac

if [[ "$PUSH" == "1" && -z "$REMOTE" ]]; then
  echo "error: --push requires --remote" >&2
  exit 2
fi

rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

rsync -a --delete \
  --exclude '.git/' \
  --exclude '.build/' \
  --exclude '.claude/' \
  --include '.env.example' \
  --include '*/.env.example' \
  --exclude '.env' \
  --exclude '.env.*' \
  --exclude '.vercel/' \
  --exclude '.next/' \
  --exclude 'build/' \
  --exclude 'DerivedData/' \
  --exclude 'Web/blitzrecorder/.next/' \
  --exclude 'Web/blitzrecorder/node_modules/' \
  --exclude 'node_modules/' \
  --exclude 'private/' \
  --exclude '*.p8' \
  --exclude '*.p12' \
  --exclude '*.mobileprovision' \
  "$ROOT"/ "$OUTPUT_DIR"/

(
  cd "$OUTPUT_DIR"
  git init -b "$BRANCH" >/dev/null
  git add .
  git commit -m "Initial public snapshot" >/dev/null
  Scripts/check-open-source-readiness.sh >/dev/null
  Scripts/audit-public-history.sh >/dev/null

  if [[ -n "$REMOTE" ]]; then
    git remote add origin "$REMOTE"
  fi
  if [[ "$PUSH" == "1" ]]; then
    git fetch --quiet origin "$BRANCH:refs/remotes/origin/$BRANCH" 2>/dev/null || true
    git push --force-with-lease origin "$BRANCH"
  fi
)

cat <<EOF
Public snapshot created and verified:
  $OUTPUT_DIR

Branch:
  $BRANCH
EOF

if [[ -n "$REMOTE" ]]; then
  cat <<EOF

Remote:
  $REMOTE
EOF
fi
