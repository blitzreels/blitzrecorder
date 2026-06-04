#!/usr/bin/env bash
set -euo pipefail

URL="${BLITZRECORDER_ENTITLEMENT_URL:-https://blitzrecorder.com/api/blitzrecorder/entitlement}"
TOKEN="${BLITZRECORDER_ENTITLEMENT_TOKEN:-}"
EXPECTED_ACTIVE="${BLITZRECORDER_ENTITLEMENT_EXPECTED_ACTIVE:-}"
BODY="$(mktemp)"
trap 'rm -f "$BODY"' EXIT

usage() {
  cat <<'USAGE'
Usage:
  Scripts/validate-entitlement-endpoint.sh
  BLITZRECORDER_ENTITLEMENT_TOKEN=TOKEN Scripts/validate-entitlement-endpoint.sh
  BLITZRECORDER_ENTITLEMENT_TOKEN=TOKEN BLITZRECORDER_ENTITLEMENT_EXPECTED_ACTIVE=true Scripts/validate-entitlement-endpoint.sh
  BLITZRECORDER_ENTITLEMENT_TOKEN=TOKEN BLITZRECORDER_ENTITLEMENT_EXPECTED_ACTIVE=false Scripts/validate-entitlement-endpoint.sh

Environment:
  BLITZRECORDER_ENTITLEMENT_URL              Override entitlement endpoint URL.
  BLITZRECORDER_ENTITLEMENT_TOKEN            Bearer token to validate. Omit to verify unauthenticated rejection.
  BLITZRECORDER_ENTITLEMENT_EXPECTED_ACTIVE  Optional true|false assertion for authenticated checks.
USAGE
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

if [[ -n "$EXPECTED_ACTIVE" && "$EXPECTED_ACTIVE" != "true" && "$EXPECTED_ACTIVE" != "false" ]]; then
  echo "error: BLITZRECORDER_ENTITLEMENT_EXPECTED_ACTIVE must be true or false." >&2
  exit 2
fi

if [[ -z "$TOKEN" && -n "$EXPECTED_ACTIVE" ]]; then
  echo "error: BLITZRECORDER_ENTITLEMENT_EXPECTED_ACTIVE requires BLITZRECORDER_ENTITLEMENT_TOKEN." >&2
  exit 2
fi

print_body_excerpt() {
  head -c 1200 "$BODY" >&2
  echo >&2
}

headers=(
  -H "Accept: application/json"
)

if [[ -n "$TOKEN" ]]; then
  headers+=(-H "Authorization: Bearer $TOKEN")
fi

status="$(
  curl -sS \
    --max-time 20 \
    -o "$BODY" \
    -w "%{http_code}" \
    "${headers[@]}" \
    "$URL"
)"

if [[ -z "$TOKEN" ]]; then
  case "$status" in
    401|403)
      echo "Unauthenticated entitlement requests are rejected with HTTP $status."
      exit 0
      ;;
    *)
      echo "error: expected HTTP 401 or 403 without token, got HTTP $status from $URL" >&2
      print_body_excerpt
      exit 1
      ;;
  esac
fi

if [[ "$status" != "200" ]]; then
  echo "error: expected HTTP 200 with token, got HTTP $status from $URL" >&2
  print_body_excerpt
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "error: jq is required to validate entitlement JSON." >&2
  exit 1
fi

jq -e '
  (.active | type == "boolean")
  and (
    (.planName == null)
    or (.planName | type == "string")
  )
' "$BODY" >/dev/null

active="$(jq -r '.active' "$BODY")"
plan_name="$(jq -r '.planName // ""' "$BODY")"

if [[ "$active" == "true" && -z "$plan_name" ]]; then
  echo "error: active entitlement responses must include planName." >&2
  exit 1
fi

if [[ -n "$EXPECTED_ACTIVE" && "$active" != "$EXPECTED_ACTIVE" ]]; then
  echo "error: expected entitlement active=$EXPECTED_ACTIVE, got active=$active." >&2
  exit 1
fi

echo "Entitlement endpoint response is valid: active=$active planName=${plan_name:-null}"
