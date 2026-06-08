#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RUN_RELEASE_CHECK=1
RUN_SECRET_SCAN=1

usage() {
  cat <<'USAGE'
Usage:
  Scripts/check-open-source-readiness.sh [options]

Options:
  --skip-release-check   Skip release readiness checks.
  --skip-secret-scan     Skip public-text secret pattern scan.
  -h, --help             Show this help.

Checks the public files and local gates expected in the open-source repository.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-release-check)
      RUN_RELEASE_CHECK=0
      ;;
    --skip-secret-scan)
      RUN_SECRET_SCAN=0
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

failures=0

pass() {
  printf 'ok: %s\n' "$1"
}

fail() {
  printf 'error: %s\n' "$1" >&2
  failures=$((failures + 1))
}

require_file() {
  [[ -f "$1" ]] && pass "found $1" || fail "missing file: $1"
}

require_contains() {
  local file="$1"
  local text="$2"
  if grep -Fq "$text" "$file"; then
    pass "$file contains $text"
  else
    fail "$file missing $text"
  fi
}

require_file "README.md"
require_file "LICENSE"
require_file "COMMERCIAL-LICENSE.md"
require_file "CONTRIBUTING.md"
require_file "SECURITY.md"
require_file "CHANGELOG.md"
require_file ".gitignore"
require_file ".github/PULL_REQUEST_TEMPLATE.md"
require_file ".github/ISSUE_TEMPLATE/bug_report.yml"
require_file ".github/ISSUE_TEMPLATE/feature_request.yml"
require_file ".github/ISSUE_TEMPLATE/config.yml"
require_file ".github/release.yml"
require_file ".github/labels.json"
require_file ".github/workflows/ci.yml"
require_file ".github/workflows/macos-dmg.yml"
require_file ".github/workflows/ios-testflight.yml"
require_file ".github/workflows/app-store-release.yml"
require_file "Scripts/check-github-release-readiness.sh"
require_file "Scripts/generate-sparkle-appcast.sh"
require_file "Scripts/sync-github-labels.py"

require_contains "README.md" "License"
require_contains "README.md" "CONTRIBUTING.md"
require_contains "README.md" "SECURITY.md"
require_contains "README.md" "CHANGELOG.md"
require_contains "COMMERCIAL-LICENSE.md" "Commercial license"
require_contains "CONTRIBUTING.md" "does not mean it will be merged"
require_contains "SECURITY.md" "support@blitzreels.com"
require_contains ".gitignore" ".env"
require_contains ".gitignore" ".claude/"
require_contains ".github/release.yml" "Build and release"
require_contains ".github/labels.json" "\"good first issue\""
require_contains ".github/workflows/macos-dmg.yml" "SPARKLE_PRIVATE_ED_KEY"
require_contains ".github/workflows/macos-dmg.yml" "appcast.xml"

if [[ "$RUN_RELEASE_CHECK" == "1" ]]; then
  if Scripts/check-github-release-readiness.sh --local-only >/dev/null; then
    pass "local release readiness passes"
  else
    fail "local release readiness fails"
  fi
fi

if [[ "$RUN_SECRET_SCAN" == "1" ]]; then
  if rg -n --hidden --glob '!LICENSE' --glob '!.git/**' --glob '!build/**' --glob '!.build/**' --glob '!Web/blitzrecorder/node_modules/**' --glob '!Web/blitzrecorder/.next/**' \
    'AKIA[0-9A-Z]{16}|ASIA[0-9A-Z]{16}|ghp_[A-Za-z0-9_]{20,}|github_pat_[A-Za-z0-9_]{20,}|sk-[A-Za-z0-9]{20,}|xox[baprs]-[A-Za-z0-9-]{10,}|-----BEGIN (RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----' \
    README.md CONTRIBUTING.md COMMERCIAL-LICENSE.md SECURITY.md CHANGELOG.md docs AppStore .github Scripts >/tmp/blitzrecorder-open-source-secret-scan.txt; then
    cat /tmp/blitzrecorder-open-source-secret-scan.txt >&2
    fail "public files contain secret-like patterns"
  else
    pass "public file secret pattern scan found no hits"
  fi
fi

if [[ "$failures" -gt 0 ]]; then
  echo "Open-source readiness failed with $failures issue(s)." >&2
  exit 1
fi

echo "Open-source readiness checks passed."
