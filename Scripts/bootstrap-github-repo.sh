#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO="blitzreels/blitzrecorder"
VISIBILITY="public"
DESCRIPTION="Native Mac screen recorder with an iPhone camera companion."
HOMEPAGE="https://blitzrecorder.com"
REMOTE_NAME="origin"
APPLY=0
PUSH=0
PUSH_TAGS=0

usage() {
  cat <<'USAGE'
Usage:
  Scripts/bootstrap-github-repo.sh [options]

Options:
  --repo OWNER/REPO       GitHub repo to create or configure. Default: blitzreels/blitzrecorder.
  --private               Create as private.
  --public                Create as public. Default.
  --description TEXT      Repository description.
  --homepage URL          Repository homepage.
  --remote NAME           Git remote name. Default: origin.
  --push                  Push the current branch after creating/configuring the repo.
  --push-tags             Push tags too. Implies --push.
  --apply                 Execute commands. Without this, prints the planned commands.
  -h, --help              Show this help.

Examples:
  Scripts/bootstrap-github-repo.sh
  Scripts/bootstrap-github-repo.sh --repo blitzreels/blitzrecorder --private --apply
  Scripts/bootstrap-github-repo.sh --repo blitzreels/blitzrecorder --apply --push --push-tags
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
    --remote)
      [[ $# -ge 2 ]] || { echo "error: --remote needs name" >&2; exit 2; }
      REMOTE_NAME="$2"
      shift
      ;;
    --push)
      PUSH=1
      ;;
    --push-tags)
      PUSH=1
      PUSH_TAGS=1
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

cd "$ROOT"

if ! command -v gh >/dev/null 2>&1; then
  echo "error: gh is required" >&2
  exit 1
fi

if ! gh auth status >/dev/null 2>&1; then
  echo "error: gh is not authenticated" >&2
  exit 1
fi

REMOTE_URL="git@github.com:${REPO}.git"
CURRENT_BRANCH="$(git branch --show-current)"
if [[ -z "$CURRENT_BRANCH" ]]; then
  echo "error: not on a named branch" >&2
  exit 2
fi

if gh repo view "$REPO" --json nameWithOwner >/dev/null 2>&1; then
  echo "Repository already exists and is accessible: $REPO"
else
  CREATE_ARGS=(gh repo create "$REPO" "--$VISIBILITY" --description "$DESCRIPTION" --homepage "$HOMEPAGE")
  run_cmd "${CREATE_ARGS[@]}"
fi

if git remote get-url "$REMOTE_NAME" >/dev/null 2>&1; then
  run_cmd git remote set-url "$REMOTE_NAME" "$REMOTE_URL"
else
  run_cmd git remote add "$REMOTE_NAME" "$REMOTE_URL"
fi

if [[ "$PUSH" == "1" ]]; then
  run_cmd git push -u "$REMOTE_NAME" "$CURRENT_BRANCH"
fi

if [[ "$PUSH_TAGS" == "1" ]]; then
  run_cmd git push "$REMOTE_NAME" --tags
fi

if [[ "$APPLY" != "1" ]]; then
  echo
  echo "Dry run only. Re-run with --apply to execute."
fi
