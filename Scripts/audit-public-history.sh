#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

usage() {
  cat <<'USAGE'
Usage:
  Scripts/audit-public-history.sh

Scans Git history for files and content that should not be published in an
open-source repository. This is intentionally conservative; use it before
making the repo public or before pushing a rewritten/sanitized public history.
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

cd "$ROOT"

failures=0

pass() {
  printf 'ok: %s\n' "$1"
}

fail() {
  printf 'error: %s\n' "$1" >&2
  failures=$((failures + 1))
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "error: missing required command: $1" >&2
    exit 1
  }
}

require_command git
require_command rg

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "error: not inside a Git worktree" >&2
  exit 2
fi

ALL_PATHS="$(mktemp)"
SUSPICIOUS_PATHS="$(mktemp)"
ALL_SUSPICIOUS_PATHS="$(mktemp)"
SECRET_HITS="$(mktemp)"
trap 'rm -f "$ALL_PATHS" "$ALL_SUSPICIOUS_PATHS" "$SUSPICIOUS_PATHS" "$SECRET_HITS"' EXIT

git log --all --name-only --pretty=format: | sed '/^$/d' | sort -u >"$ALL_PATHS"

if rg -n --no-heading --ignore-case \
  '(^|/)(\.env($|\.)|\.vercel/|\.netlify/|\.supabase/|\.firebase/|\.aws/|\.ssh/|\.claude/|CLAUDE\.md$|.*\.(p8|p12|pem|key|mobileprovision)$|id_rsa|id_ed25519|secret|secrets|credential|credentials|token|tokens)' \
  "$ALL_PATHS" >"$ALL_SUSPICIOUS_PATHS"; then
  grep -Ev '^[0-9]+:(.*/)?\.env\.example$' "$ALL_SUSPICIOUS_PATHS" >"$SUSPICIOUS_PATHS" || true
  if [[ -s "$SUSPICIOUS_PATHS" ]]; then
    cat "$SUSPICIOUS_PATHS" >&2
    fail "suspicious paths exist in Git history"
  else
    pass "no suspicious path names found in Git history"
  fi
else
  pass "no suspicious path names found in Git history"
fi

SECRET_PATTERN='AKIA[0-9A-Z]{16}|ASIA[0-9A-Z]{16}|ghp_[A-Za-z0-9_]{20,}|github_pat_[A-Za-z0-9_]{20,}|gho_[A-Za-z0-9_]{20,}|sk-[A-Za-z0-9]{20,}|xox[baprs]-[A-Za-z0-9-]{10,}|-----BEGIN (RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----|AuthKey_[A-Z0-9]{10}\.p8'

while IFS= read -r revision; do
  git grep -I -n -E "$SECRET_PATTERN" "$revision" -- \
    ':!LICENSE' \
    ':!Web/blitzrecorder/package-lock.json' || true
done < <(git rev-list --all) >"$SECRET_HITS"

if [[ -s "$SECRET_HITS" ]]; then
  head -200 "$SECRET_HITS" >&2
  if [[ "$(wc -l <"$SECRET_HITS" | tr -d ' ')" -gt 200 ]]; then
    echo "... additional history secret-pattern hits omitted" >&2
  fi
  fail "secret-like content exists in Git history"
else
  pass "no common secret patterns found in Git history"
fi

echo "Commit author identities found in history:"
git log --all --format='%an <%ae>' | sort -u | sed 's/^/- /'

if [[ "$failures" -gt 0 ]]; then
  echo "Public history audit failed with $failures issue(s)." >&2
  exit 1
fi

echo "Public history audit passed."
