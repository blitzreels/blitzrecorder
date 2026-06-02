#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO=""
REPO_ARGS=()

usage() {
  cat <<'USAGE'
Usage:
  Scripts/configure-github-app-store-secrets.sh [--repo OWNER/REPO]

Reads local environment variables and writes the GitHub Actions secrets used by
the App Store and TestFlight workflows. Secret values are never printed.

Required environment:
  APPLE_TEAM_ID
  APPLE_DISTRIBUTION_CERTIFICATE_PATH
  APPLE_DISTRIBUTION_CERTIFICATE_PASSWORD or APPLE_DISTRIBUTION_CERTIFICATE_PASSWORD_FILE
  KEYCHAIN_PASSWORD
  ASC_KEY_ID
  ASC_ISSUER_ID
  ASC_PRIVATE_KEY_PATH or ASC_PRIVATE_KEY

Optional environment:
  MAC_APP_STORE_PROVISION_PROFILE_PATH
  IOS_APP_STORE_PROVISION_PROFILE_PATH

Example:
  APPLE_TEAM_ID="$APPLE_TEAM_ID" \
  APPLE_DISTRIBUTION_CERTIFICATE_PATH="$PWD/private/AppleDistribution.p12" \
  APPLE_DISTRIBUTION_CERTIFICATE_PASSWORD_FILE="$PWD/private/apple-distribution-password.txt" \
  KEYCHAIN_PASSWORD="$(openssl rand -base64 32)" \
  ASC_KEY_ID="$ASC_KEY_ID" \
  ASC_ISSUER_ID="$ASC_ISSUER_ID" \
  ASC_PRIVATE_KEY_PATH="$PWD/private/AuthKey_$ASC_KEY_ID.p8" \
  IOS_APP_STORE_PROVISION_PROFILE_PATH="$PWD/private/BlitzRecorderCamera.mobileprovision" \
  Scripts/configure-github-app-store-secrets.sh
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      [[ $# -ge 2 ]] || { echo "error: --repo needs OWNER/REPO" >&2; exit 2; }
      REPO="$2"
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

require_env() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    echo "error: missing environment variable $name" >&2
    exit 2
  fi
}

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

set_secret() {
  local name="$1"
  gh secret set "$name" "${REPO_ARGS[@]}" >/dev/null
  echo "Set $name"
}

set_file_secret_if_present() {
  local env_name="$1"
  local secret_name="$2"
  if [[ -n "${!env_name:-}" ]]; then
    [[ -f "${!env_name}" ]] || {
      echo "error: $env_name does not exist" >&2
      exit 2
    }
    base64 -i "${!env_name}" | set_secret "$secret_name"
  fi
}

cd "$ROOT"
require_command gh
require_command git
require_command base64
require_env APPLE_TEAM_ID
require_env APPLE_DISTRIBUTION_CERTIFICATE_PATH
require_env KEYCHAIN_PASSWORD
require_env ASC_KEY_ID
require_env ASC_ISSUER_ID

if [[ -z "$REPO" ]]; then
  REPO="$(repo_from_origin)"
fi
if [[ -z "$REPO" ]]; then
  echo "error: could not infer GitHub repo from origin remote; pass --repo OWNER/REPO" >&2
  exit 2
fi
REPO_ARGS=(--repo "$REPO")

gh repo view "$REPO" --json nameWithOwner >/dev/null

[[ -f "$APPLE_DISTRIBUTION_CERTIFICATE_PATH" ]] || {
  echo "error: APPLE_DISTRIBUTION_CERTIFICATE_PATH does not exist" >&2
  exit 2
}

printf '%s' "$APPLE_TEAM_ID" | set_secret APPLE_TEAM_ID
base64 -i "$APPLE_DISTRIBUTION_CERTIFICATE_PATH" | set_secret APPLE_DISTRIBUTION_CERTIFICATE_BASE64
read_secret_value APPLE_DISTRIBUTION_CERTIFICATE_PASSWORD | set_secret APPLE_DISTRIBUTION_CERTIFICATE_PASSWORD
printf '%s' "$KEYCHAIN_PASSWORD" | set_secret KEYCHAIN_PASSWORD
printf '%s' "$ASC_KEY_ID" | set_secret ASC_KEY_ID
printf '%s' "$ASC_ISSUER_ID" | set_secret ASC_ISSUER_ID
read_secret_value ASC_PRIVATE_KEY | set_secret ASC_PRIVATE_KEY
set_file_secret_if_present MAC_APP_STORE_PROVISION_PROFILE_PATH MAC_APP_STORE_PROVISION_PROFILE_BASE64
set_file_secret_if_present IOS_APP_STORE_PROVISION_PROFILE_PATH IOS_APP_STORE_PROVISION_PROFILE_BASE64

echo "GitHub App Store/TestFlight secrets configured."
