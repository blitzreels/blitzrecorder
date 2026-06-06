#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SNAPSHOT_DIR="$ROOT/build/public-snapshot"
REPO="blitzreels/blitzrecorder"
DESCRIPTION="Native Mac screen recorder with an iPhone camera companion."
HOMEPAGE="https://blitzrecorder.com"
BRANCH="main"
VISIBILITY="public"
APPLY=0

usage() {
  cat <<'USAGE'
Usage:
  Scripts/publish-public-snapshot.sh [options]

Options:
  --snapshot-dir DIR      Existing verified snapshot. Defaults to build/public-snapshot.
  --repo OWNER/REPO       Public GitHub repo to create/update. Default: blitzreels/blitzrecorder.
  --branch NAME           Branch to publish in the public repo. Default: main.
  --private               Create/update the target repo as private.
  --public                Create/update the target repo as public. Default.
  --description TEXT      Repository description.
  --homepage URL          Repository homepage.
  --apply                 Execute. Without this, prints the planned commands.
  -h, --help              Show this help.

Publishes a fresh-history public snapshot to a separate GitHub repository.
This avoids exposing the private development repo's old history.
USAGE
}

quote_cmd() {
  printf '+'
  printf ' %q' "$@"
  printf '\n'
}

run_cmd() {
  quote_cmd "$@"
  if [[ "$APPLY" == "1" ]]; then
    "$@"
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --snapshot-dir)
      [[ $# -ge 2 ]] || { echo "error: --snapshot-dir needs a directory" >&2; exit 2; }
      SNAPSHOT_DIR="$2"
      shift
      ;;
    --repo)
      [[ $# -ge 2 ]] || { echo "error: --repo needs OWNER/REPO" >&2; exit 2; }
      REPO="$2"
      shift
      ;;
    --branch)
      [[ $# -ge 2 ]] || { echo "error: --branch needs a name" >&2; exit 2; }
      BRANCH="$2"
      shift
      ;;
    --private)
      VISIBILITY="private"
      ;;
    --public)
      VISIBILITY="public"
      ;;
    --description)
      [[ $# -ge 2 ]] || { echo "error: --description needs text" >&2; exit 2; }
      DESCRIPTION="$2"
      shift
      ;;
    --homepage)
      [[ $# -ge 2 ]] || { echo "error: --homepage needs URL" >&2; exit 2; }
      HOMEPAGE="$2"
      shift
      ;;
    --apply)
      APPLY=1
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

require_command gh
require_command git

SNAPSHOT_DIR="$(cd "$SNAPSHOT_DIR" && pwd)"
[[ -d "$SNAPSHOT_DIR/.git" ]] || {
  echo "error: snapshot repo not found at $SNAPSHOT_DIR; run Scripts/create-public-snapshot.sh first" >&2
  exit 2
}

(
  cd "$SNAPSHOT_DIR"
  Scripts/check-open-source-readiness.sh >/dev/null
  Scripts/audit-public-history.sh >/dev/null
)

REMOTE_URL="git@github.com:${REPO}.git"

if gh repo view "$REPO" --json nameWithOwner >/dev/null 2>&1; then
  echo "Repository already exists and is accessible: $REPO"
  run_cmd gh repo edit "$REPO" "--$VISIBILITY" --description "$DESCRIPTION" --homepage "$HOMEPAGE"
else
  run_cmd gh repo create "$REPO" "--$VISIBILITY" --description "$DESCRIPTION" --homepage "$HOMEPAGE"
fi

(
  cd "$SNAPSHOT_DIR"
  if git remote get-url origin >/dev/null 2>&1; then
    run_cmd git remote set-url origin "$REMOTE_URL"
  else
    run_cmd git remote add origin "$REMOTE_URL"
  fi
  run_cmd git branch -M "$BRANCH"
  run_cmd git push -u origin "$BRANCH"
)

if [[ "$APPLY" != "1" ]]; then
  echo
  echo "Dry run only. Re-run with --apply to execute."
fi
