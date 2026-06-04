#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO=""
IDENTITY_NAME=""
KEYCHAIN_PASSWORD="${KEYCHAIN_PASSWORD:-}"

usage() {
  cat <<'USAGE'
Usage:
  Scripts/configure-github-developer-id-from-keychain.sh [options]

Options:
  --repo OWNER/REPO       GitHub repository. Defaults to origin remote.
  --identity NAME         Developer ID Application identity subject. Defaults to
                          the first local Developer ID Application identity.
  -h, --help              Show this help.

Exports only the matching Developer ID Application certificate/private-key pair
from the local Keychain into a temporary .p12, writes the GitHub Actions secrets,
then deletes the temporary files.

Secrets written:
  DEVELOPER_ID_CERTIFICATE_BASE64
  DEVELOPER_ID_CERTIFICATE_PASSWORD
  KEYCHAIN_PASSWORD
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      [[ $# -ge 2 ]] || { echo "error: --repo needs OWNER/REPO" >&2; exit 2; }
      REPO="$2"
      shift
      ;;
    --identity)
      [[ $# -ge 2 ]] || { echo "error: --identity needs a certificate subject" >&2; exit 2; }
      IDENTITY_NAME="$2"
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

first_developer_id_identity() {
  security find-identity -v -p codesigning 2>/dev/null \
    | awk -F '"' '/Developer ID Application/ { print $2; exit }'
}

set_secret() {
  local name="$1"
  gh secret set "$name" --repo "$REPO" >/dev/null
  echo "Set $name"
}

cd "$ROOT"
require_command gh
require_command git
require_command openssl
require_command security
require_command base64

if [[ -z "$REPO" ]]; then
  REPO="$(repo_from_origin)"
fi
[[ -n "$REPO" ]] || { echo "error: could not infer GitHub repo from origin; pass --repo OWNER/REPO" >&2; exit 2; }
gh repo view "$REPO" --json nameWithOwner >/dev/null

if [[ -z "$IDENTITY_NAME" ]]; then
  IDENTITY_NAME="$(first_developer_id_identity)"
fi
[[ -n "$IDENTITY_NAME" ]] || { echo "error: no Developer ID Application identity found" >&2; exit 2; }

if [[ -z "$KEYCHAIN_PASSWORD" ]]; then
  KEYCHAIN_PASSWORD="$(openssl rand -base64 32)"
fi

TMP_DIR="$(mktemp -d)"
cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT

EXPORT_PASS="$(openssl rand -base64 32)"
P12_PASS="$(openssl rand -base64 32)"
ALL_P12="$TMP_DIR/all-identities.p12"
ALL_PEM="$TMP_DIR/all-identities.pem"
DEV_P12="$TMP_DIR/developer-id-application.p12"

security export -t identities -f pkcs12 -P "$EXPORT_PASS" -o "$ALL_P12" >/dev/null
openssl pkcs12 -in "$ALL_P12" -passin "pass:$EXPORT_PASS" -nodes -legacy -out "$ALL_PEM" >/dev/null 2>&1

awk -v dir="$TMP_DIR" '
  /-----BEGIN CERTIFICATE-----/ {n++; file=sprintf("%s/cert-%03d.pem", dir, n); inblock=1}
  inblock {print > file}
  /-----END CERTIFICATE-----/ && inblock {inblock=0; close(file)}
' "$ALL_PEM"

awk -v dir="$TMP_DIR" '
  /-----BEGIN .*PRIVATE KEY-----/ {n++; file=sprintf("%s/key-%03d.pem", dir, n); inblock=1}
  inblock {print > file}
  /-----END .*PRIVATE KEY-----/ && inblock {inblock=0; close(file)}
' "$ALL_PEM"

DEV_CERT=""
for cert in "$TMP_DIR"/cert-*.pem; do
  [[ -f "$cert" ]] || continue
  subject="$(openssl x509 -in "$cert" -noout -subject 2>/dev/null || true)"
  if [[ "$subject" == *"$IDENTITY_NAME"* ]]; then
    DEV_CERT="$cert"
    break
  fi
done
[[ -n "$DEV_CERT" ]] || { echo "error: Developer ID certificate not found in exported identities: $IDENTITY_NAME" >&2; exit 1; }

CERT_FP="$(openssl x509 -in "$DEV_CERT" -pubkey -noout | openssl pkey -pubin -pubout -outform DER 2>/dev/null | openssl dgst -sha256 -binary | base64)"
DEV_KEY=""
for key in "$TMP_DIR"/key-*.pem; do
  [[ -f "$key" ]] || continue
  KEY_FP="$(openssl pkey -in "$key" -pubout -outform DER 2>/dev/null | openssl dgst -sha256 -binary | base64 || true)"
  if [[ "$KEY_FP" == "$CERT_FP" ]]; then
    DEV_KEY="$key"
    break
  fi
done
[[ -n "$DEV_KEY" ]] || { echo "error: matching Developer ID private key not found" >&2; exit 1; }

openssl pkcs12 -export \
  -inkey "$DEV_KEY" \
  -in "$DEV_CERT" \
  -out "$DEV_P12" \
  -passout "pass:$P12_PASS" \
  -name "$IDENTITY_NAME" >/dev/null 2>&1

base64 -i "$DEV_P12" | set_secret DEVELOPER_ID_CERTIFICATE_BASE64
printf '%s' "$P12_PASS" | set_secret DEVELOPER_ID_CERTIFICATE_PASSWORD
printf '%s' "$KEYCHAIN_PASSWORD" | set_secret KEYCHAIN_PASSWORD

echo "GitHub Developer ID secrets configured for $REPO."
