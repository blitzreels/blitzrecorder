#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO="blitzreels/blitzrecorder"
PUBLIC_BRANCH="public-main"
APPLY=0
MAKE_PUBLIC=0
DELETE_MAIN=0
CONFIRM=""

usage() {
  cat <<'USAGE'
Usage:
  Scripts/promote-public-branch.sh [options]

Options:
  --repo OWNER/REPO          GitHub repo to update. Default: blitzreels/blitzrecorder.
  --public-branch NAME       Verified fresh-history branch. Default: public-main.
  --make-public              Change repo visibility to public.
  --delete-main              Delete remote main after changing default branch.
  --confirm TEXT             Required for destructive ops. Use: promote-clean-public-branch
  --apply                    Execute. Without this, prints the planned commands.
  -h, --help                 Show this help.

Promotes a verified fresh-history branch as the default branch for the current
repo. This is safer than making the private repo public while old refs remain,
but deleting main is destructive and requires explicit confirmation.
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
    --repo)
      [[ $# -ge 2 ]] || { echo "error: --repo needs OWNER/REPO" >&2; exit 2; }
      REPO="$2"
      shift
      ;;
    --public-branch)
      [[ $# -ge 2 ]] || { echo "error: --public-branch needs a name" >&2; exit 2; }
      PUBLIC_BRANCH="$2"
      shift
      ;;
    --make-public)
      MAKE_PUBLIC=1
      ;;
    --delete-main)
      DELETE_MAIN=1
      ;;
    --confirm)
      [[ $# -ge 2 ]] || { echo "error: --confirm needs text" >&2; exit 2; }
      CONFIRM="$2"
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

cd "$ROOT"

if [[ "$DELETE_MAIN" == "1" && "$CONFIRM" != "promote-clean-public-branch" ]]; then
  echo "error: --delete-main requires --confirm promote-clean-public-branch" >&2
  exit 2
fi

gh repo view "$REPO" --json nameWithOwner >/dev/null

REMOTE_URL="git@github.com:${REPO}.git"
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT

git clone --depth 1 --branch "$PUBLIC_BRANCH" "$REMOTE_URL" "$TEMP_DIR" >/dev/null 2>&1 || {
  echo "error: could not clone $REPO branch $PUBLIC_BRANCH" >&2
  exit 2
}

(
  cd "$TEMP_DIR"
  Scripts/check-open-source-readiness.sh >/dev/null
  Scripts/audit-public-history.sh >/dev/null
)

run_cmd gh repo edit "$REPO" --default-branch "$PUBLIC_BRANCH"

if [[ "$MAKE_PUBLIC" == "1" ]]; then
  run_cmd gh repo edit "$REPO" --visibility public
fi

if [[ "$DELETE_MAIN" == "1" ]]; then
  run_cmd git push "$REMOTE_URL" --delete main
fi

if [[ "$APPLY" != "1" ]]; then
  echo
  echo "Dry run only. Re-run with --apply to execute."
fi
