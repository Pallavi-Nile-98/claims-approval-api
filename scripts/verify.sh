#!/usr/bin/env bash
# Smoke-test a running deployment over HTTP: health, the full claim lifecycle, and errors.
# Usage: bash scripts/verify.sh                         (uses the ALB URL from Terraform)
#        bash scripts/verify.sh http://localhost:8080   (any other base URL)
source "$(dirname "$0")/common.sh"

require_tools curl
BASE_URL="${1:-$(tf_output alb_url)}"
BASE_URL="${BASE_URL%/}"

# Unique users per run, so repeated runs never interfere with each other's claims.
RUN_ID=$(date +%s)
SUBMITTER="verify-submitter-$RUN_ID"
APPROVER="verify-approver-$RUN_ID"

BODY_FILE=$(native_path "$(mktemp)") # curl.exe on Windows needs a C:/ style path
trap 'rm -f "$BODY_FILE"' EXIT
FAILURES=0

# request <expected-status> <method> <path> [user] [role] [json-body]
request() {
  local expected=$1 method=$2 path=$3 user=${4:-} role=${5:-} body=${6:-}
  local args=(-s -o "$BODY_FILE" -w '%{http_code}' --max-time 15 -X "$method" "$BASE_URL$path")
  [ -n "$user" ] && args+=(-H "X-User-Id: $user" -H "X-User-Role: $role")
  [ -n "$body" ] && args+=(-H "Content-Type: application/json" -d "$body")

  local status
  status=$(curl "${args[@]}") || status="000 (no response)"

  if [ "$status" = "$expected" ]; then
    printf '  PASS  %-6s %-34s -> %s\n' "$method" "$path" "$status"
  else
    printf '  FAIL  %-6s %-34s -> %s (expected %s)\n' "$method" "$path" "$status" "$expected"
    sed 's/^/        /' "$BODY_FILE"; echo
    FAILURES=$((FAILURES + 1))
  fi
}

log "Verifying $BASE_URL"

request 200 GET /actuator/health
request 200 GET /v3/api-docs

request 201 POST /api/claims "$SUBMITTER" SUBMITTER '{"title":"Smoke test","amount":12.34}'
CLAIM_ID=$(sed -nE 's/.*"id":([0-9]+).*/\1/p' "$BODY_FILE")
[ -n "$CLAIM_ID" ] || die "Creating a claim failed (see above), so the lifecycle checks can't run."

request 200 POST "/api/claims/$CLAIM_ID/submit"  "$SUBMITTER" SUBMITTER
request 200 POST "/api/claims/$CLAIM_ID/approve" "$APPROVER"  APPROVER
request 200 GET  "/api/claims/$CLAIM_ID"         "$SUBMITTER" SUBMITTER
request 409 POST "/api/claims/$CLAIM_ID/reject"  "$APPROVER"  APPROVER   # already APPROVED
request 400 GET  /api/claims                                              # no identity headers
request 404 GET  /api/claims/999999999 "$APPROVER" APPROVER

if [ "$FAILURES" -eq 0 ]; then
  log "All checks passed."
else
  die "$FAILURES check(s) failed."
fi
