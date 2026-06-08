#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO=""
LOCAL_ONLY=0
CHECK_LOCAL_DMG=0

usage() {
  cat <<'USAGE'
Usage:
  Scripts/check-github-release-readiness.sh [options]

Options:
  --repo OWNER/REPO     GitHub repository to check. Defaults to origin remote.
  --local-only          Skip GitHub repo and secret checks.
  --local-dmg           Also build and verify a local throwaway universal DMG.
  -h, --help            Show this help.

Checks release scripts, workflow syntax, version metadata, universal DMG settings,
and, unless --local-only is used, GitHub repo access plus required Actions secrets.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      [[ $# -ge 2 ]] || { echo "error: --repo needs OWNER/REPO" >&2; exit 2; }
      REPO="$2"
      shift
      ;;
    --local-only)
      LOCAL_ONLY=1
      ;;
    --local-dmg)
      CHECK_LOCAL_DMG=1
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

require_command() {
  if command -v "$1" >/dev/null 2>&1; then
    pass "found $1"
  else
    fail "missing command: $1"
  fi
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

require_file() {
  [[ -f "$1" ]] && pass "found $1" || fail "missing file: $1"
}

require_executable() {
  [[ -x "$1" ]] && pass "executable $1" || fail "not executable: $1"
}

require_contains() {
  local file="$1"
  local text="$2"
  if grep -Fq -- "$text" "$file"; then
    pass "$file contains $text"
  else
    fail "$file missing $text"
  fi
}

reject_contains() {
  local file="$1"
  local text="$2"
  if grep -Fq -- "$text" "$file"; then
    fail "$file should not contain $text"
  else
    pass "$file does not contain $text"
  fi
}

require_command git
require_command bash
require_command python3
require_command ruby
require_command npm
require_command swift
require_command hdiutil
require_command lipo
require_command codesign

require_file ".github/workflows/macos-dmg.yml"
require_file ".github/workflows/ios-testflight.yml"
require_file ".github/workflows/app-store-release.yml"
require_file ".github/release.yml"
require_file ".github/labels.json"
require_file "Scripts/package-app.sh"
require_file "Scripts/package-dmg.sh"
require_file "Scripts/ci-macos-dmg.sh"
require_file "Scripts/validate-public-dmg.sh"
require_file "Scripts/ci-ios-testflight.sh"
require_file "Scripts/archive-app-store.sh"
require_file "Scripts/set-version.py"
require_file "Scripts/prepare-github-release.sh"
require_file "Scripts/bootstrap-github-repo.sh"
require_file "Scripts/generate-sparkle-appcast.sh"
require_file "Scripts/check-github-release-readiness.sh"
require_file "Scripts/sync-github-labels.py"

require_executable "Scripts/package-app.sh"
require_executable "Scripts/package-dmg.sh"
require_executable "Scripts/ci-macos-dmg.sh"
require_executable "Scripts/validate-public-dmg.sh"
require_executable "Scripts/ci-ios-testflight.sh"
require_executable "Scripts/archive-app-store.sh"
require_executable "Scripts/set-version.py"
require_executable "Scripts/prepare-github-release.sh"
require_executable "Scripts/bootstrap-github-repo.sh"
require_executable "Scripts/generate-sparkle-appcast.sh"
require_executable "Scripts/check-github-release-readiness.sh"
require_executable "Scripts/sync-github-labels.py"

if bash -n Scripts/package-app.sh Scripts/package-dmg.sh Scripts/ci-macos-dmg.sh Scripts/validate-public-dmg.sh Scripts/archive-app-store.sh Scripts/ci-ios-testflight.sh Scripts/prepare-github-release.sh Scripts/bootstrap-github-repo.sh Scripts/generate-sparkle-appcast.sh Scripts/check-github-release-readiness.sh; then
  pass "release shell scripts parse"
else
  fail "release shell scripts do not parse"
fi

if python3 -m py_compile Scripts/set-version.py; then
  pass "set-version.py compiles"
else
  fail "set-version.py does not compile"
fi

if python3 -m py_compile Scripts/sync-github-labels.py; then
  pass "sync-github-labels.py compiles"
else
  fail "sync-github-labels.py does not compile"
fi

if ruby -e 'require "yaml"; ARGV.each { |path| YAML.load_file(path) }' .github/workflows/macos-dmg.yml .github/workflows/ios-testflight.yml .github/workflows/app-store-release.yml >/dev/null; then
  pass "release workflow YAML parses"
else
  fail "release workflow YAML does not parse"
fi

if python3 Scripts/generate-app-store-connect-fields.py --check >/dev/null; then
  pass "App Store Connect field export is current"
else
  fail "App Store Connect field export is stale"
fi

require_contains ".github/workflows/ci.yml" "pull_request:"
require_contains ".github/workflows/ci.yml" "- main"
require_contains ".github/workflows/macos-dmg.yml" "pull_request:"
require_contains ".github/workflows/macos-dmg.yml" "- main"
require_contains ".github/workflows/macos-dmg.yml" "tags:"
require_contains ".github/workflows/macos-dmg.yml" "\"v*\""
require_contains ".github/workflows/macos-dmg.yml" "APP_ARCHS: arm64 x86_64"
require_contains ".github/workflows/macos-dmg.yml" "EXPECTED_ARCHS: arm64 x86_64"
require_contains ".github/workflows/macos-dmg.yml" "SHA256SUMS"
require_contains ".github/workflows/macos-dmg.yml" "SPARKLE_PUBLIC_ED_KEY"
require_contains ".github/workflows/macos-dmg.yml" "SPARKLE_PRIVATE_ED_KEY"
require_contains ".github/workflows/macos-dmg.yml" "Scripts/generate-sparkle-appcast.sh"
require_contains ".github/workflows/macos-dmg.yml" "appcast.xml"
require_contains ".github/workflows/macos-dmg.yml" "release-metadata.json"
require_contains ".github/workflows/macos-dmg.yml" "build/ReleaseEvidence"
require_contains ".github/workflows/macos-dmg.yml" "gh release create"
require_contains ".github/workflows/ios-testflight.yml" "Scripts/ci-ios-testflight.sh"
require_contains ".github/workflows/ios-testflight.yml" "workflow_dispatch:"
require_contains ".github/workflows/ios-testflight.yml" "Validate iOS Submission Artifacts"
require_contains ".github/workflows/ios-testflight.yml" "build/ReleaseEvidence/ios-testflight"
require_contains ".github/workflows/app-store-release.yml" "Scripts/archive-app-store.sh"
require_contains ".github/workflows/app-store-release.yml" "workflow_dispatch:"
require_contains ".github/workflows/app-store-release.yml" "Validate App Store Submission Artifacts"
require_contains ".github/workflows/app-store-release.yml" "build/ReleaseEvidence/app-store"
private_branch_glob="$(printf '%s/%s' 'co''dex' '**')"
reject_contains ".github/workflows/ci.yml" "$private_branch_glob"
reject_contains ".github/workflows/macos-dmg.yml" "$private_branch_glob"
reject_contains ".github/workflows/blitzrecorder-web.yml" "$private_branch_glob"
reject_contains ".github/workflows/ios-testflight.yml" "$private_branch_glob"
reject_contains ".github/workflows/app-store-release.yml" "$private_branch_glob"
require_contains ".github/release.yml" "ignore-for-release"
require_contains ".github/labels.json" "\"ignore-for-release\""
require_contains "Scripts/package-dmg.sh" "macOS-\${DMG_ARCH_LABEL}"
require_contains "Scripts/package-dmg.sh" "notarytool-submit.json"
require_contains "Scripts/ci-macos-dmg.sh" "EXPECTED_ARCHS"
require_contains "Scripts/ci-macos-dmg.sh" "Scripts/validate-public-dmg.sh"
require_contains "Scripts/archive-app-store.sh" "TARGET=all|mac|ios"

public_download_dmgs=()
while IFS= read -r dmg; do
  public_download_dmgs+=("$dmg")
done < <(git ls-files 'Web/blitzrecorder/public/downloads/*.dmg')

if [[ "${#public_download_dmgs[@]}" -eq 0 ]]; then
  pass "no static public DMG fallback"
else
  for dmg in "${public_download_dmgs[@]}"; do
    if Scripts/validate-public-dmg.sh \
        --dmg "$dmg" \
        --require-notarized \
        --evidence-dir "$ROOT/build/ReleaseEvidence/static-public-dmg/$(basename "$dmg" .dmg)" >/dev/null; then
      pass "public DMG is signed, notarized, and stapled: $dmg"
    else
      fail "public DMG is not ready for end users: $dmg"
    fi
  done
fi

if [[ "$CHECK_LOCAL_DMG" == "1" ]]; then
  if ALLOW_AD_HOC_RELEASE_SIGNING=1 ENTITLEMENTS_PATH="$ROOT/BlitzRecorder.local.entitlements" Scripts/ci-macos-dmg.sh >/dev/null; then
    pass "local throwaway universal DMG builds and verifies"
  else
    fail "local throwaway universal DMG failed"
  fi
fi

if [[ "$LOCAL_ONLY" != "1" ]]; then
  require_command gh
  if [[ -z "$REPO" ]]; then
    REPO="$(repo_from_origin)"
  fi
  if [[ -z "$REPO" ]]; then
    fail "could not infer GitHub repo from origin remote; pass --repo OWNER/REPO"
  elif gh repo view "$REPO" --json nameWithOwner >/dev/null 2>&1; then
    pass "GitHub repo is accessible: $REPO"
    secrets="$(gh secret list --repo "$REPO" --json name --jq '.[].name' 2>/dev/null || true)"
    for secret in \
      APPLE_TEAM_ID \
      APPLE_DISTRIBUTION_CERTIFICATE_BASE64 \
      APPLE_DISTRIBUTION_CERTIFICATE_PASSWORD \
      DEVELOPER_ID_CERTIFICATE_BASE64 \
      DEVELOPER_ID_CERTIFICATE_PASSWORD \
      KEYCHAIN_PASSWORD \
      ASC_KEY_ID \
      ASC_ISSUER_ID \
      ASC_PRIVATE_KEY \
      SPARKLE_PUBLIC_ED_KEY \
      SPARKLE_PRIVATE_ED_KEY
    do
      if printf '%s\n' "$secrets" | grep -Fxq "$secret"; then
        pass "GitHub secret exists: $secret"
      else
        fail "missing GitHub secret: $secret"
      fi
    done
    if python3 Scripts/sync-github-labels.py --repo "$REPO" >/dev/null; then
      pass "GitHub labels dry-run completed"
    else
      fail "GitHub labels dry-run failed"
    fi
  else
    fail "GitHub repo is not accessible: $REPO"
  fi
fi

if [[ "$failures" -gt 0 ]]; then
  echo "Release readiness failed with $failures issue(s)." >&2
  exit 1
fi

echo "Release readiness checks passed."
