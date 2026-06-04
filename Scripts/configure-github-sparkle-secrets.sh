#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO=""
ACCOUNT="${SPARKLE_KEYCHAIN_ACCOUNT:-blitzreels-blitzrecorder}"

usage() {
  cat <<'USAGE'
Usage:
  Scripts/configure-github-sparkle-secrets.sh [--repo OWNER/REPO] [--account KEYCHAIN_ACCOUNT]

Generates or reuses a Sparkle EdDSA signing key in the macOS Keychain, then
writes the public/private values to GitHub Actions secrets.

Secrets written:
  SPARKLE_PUBLIC_ED_KEY
  SPARKLE_PRIVATE_ED_KEY

The secret values are never printed.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      [[ $# -ge 2 ]] || { echo "error: --repo needs OWNER/REPO" >&2; exit 2; }
      REPO="$2"
      shift
      ;;
    --account)
      [[ $# -ge 2 ]] || { echo "error: --account needs a keychain account" >&2; exit 2; }
      ACCOUNT="$2"
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

require_command() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "error: missing required command: $1" >&2
    exit 1
  }
}

repo_from_origin() {
  local remote
  remote="$(git remote get-url origin 2>/dev/null || true)"
  case "$remote" in
    git@github.com:*.git)
      remote="${remote#git@github.com:}"
      printf '%s\n' "${remote%.git}"
      ;;
    https://github.com/*.git)
      remote="${remote#https://github.com/}"
      printf '%s\n' "${remote%.git}"
      ;;
    https://github.com/*)
      printf '%s\n' "${remote#https://github.com/}"
      ;;
  esac
}

find_generate_keys() {
  local candidate
  for candidate in \
    "$ROOT/.build/artifacts/sparkle/Sparkle/bin/generate_keys" \
    "$ROOT/.build/checkouts/Sparkle/bin/generate_keys"
  do
    if [[ -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  candidate="$(
    find "$ROOT/.build/artifacts" "$ROOT/.build/checkouts" \
      -type f \
      -name generate_keys \
      -perm -111 \
      -print \
      -quit 2>/dev/null || true
  )"
  [[ -n "$candidate" ]] || {
    echo "error: Sparkle generate_keys was not found. Run DIRECT_DISTRIBUTION=1 swift build first." >&2
    exit 1
  }
  printf '%s\n' "$candidate"
}

set_secret() {
  local name="$1"
  gh secret set "$name" --repo "$REPO" >/dev/null
  echo "Set $name"
}

cd "$ROOT"
require_command gh
require_command git

if [[ -z "$REPO" ]]; then
  REPO="$(repo_from_origin)"
fi
[[ -n "$REPO" ]] || { echo "error: could not infer GitHub repo from origin; pass --repo OWNER/REPO" >&2; exit 2; }
gh repo view "$REPO" --json nameWithOwner >/dev/null

GENERATE_KEYS="$(find_generate_keys)"
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT
PRIVATE_KEY_PATH="$TEMP_DIR/sparkle-private-ed-key.txt"

if ! "$GENERATE_KEYS" --account "$ACCOUNT" -p >/dev/null 2>&1; then
  "$GENERATE_KEYS" --account "$ACCOUNT" >/dev/null
fi

PUBLIC_KEY="$("$GENERATE_KEYS" --account "$ACCOUNT" -p)"
"$GENERATE_KEYS" --account "$ACCOUNT" -x "$PRIVATE_KEY_PATH" >/dev/null

printf '%s' "$PUBLIC_KEY" | set_secret SPARKLE_PUBLIC_ED_KEY
cat "$PRIVATE_KEY_PATH" | set_secret SPARKLE_PRIVATE_ED_KEY

echo "GitHub Sparkle secrets configured for $REPO."
