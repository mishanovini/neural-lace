#!/usr/bin/env bash
# circuit-health-probe.sh
#
# Probes Circuit production routes and reports health. Designed to run
# autonomously (cron / scheduled-tasks MCP) every 30 minutes and surface
# regressions to the Dispatch orchestrator via marker files at
# `~/.claude/state/circuit-prod-anomaly-alerts/`.
#
# Usage:
#   bash tools/circuit-health-probe.sh                   # probe prod (default)
#   CIRCUIT_URL=https://example.com bash tools/circuit-health-probe.sh
#   bash tools/circuit-health-probe.sh --quiet            # JSON only on stdout
#   bash tools/circuit-health-probe.sh --self-test        # exercise the probe logic
#
# Exit codes:
#   0 — all routes healthy (no anomalies)
#   1 — at least one anomaly detected (alert file written)
#   2 — usage error / probe itself broken
#
# Outputs:
#   - JSON report on stdout (or to STDOUT-suppressed when --quiet)
#   - Historical log: ~/.claude/state/circuit-health-log/<ISO-timestamp>.json
#   - Anomaly marker (only on FAIL):
#       ~/.claude/state/circuit-prod-anomaly-alerts/<ISO-timestamp>.json
#
# Maintenance pause:
#   touch ~/.claude/state/circuit-health-monitor-paused
#   Removes/skips alert emission while the file exists. Probe still runs
#   and still logs history (so we know what would have alerted).
#
# Route catalog is declared inline (ROUTES array). To add a route, append
# a 'METHOD|PATH|EXPECTED_CODES|TIMEOUT_S|LABEL' line. Multiple expected
# codes are comma-separated. See `## Updating the route catalog` in the
# runbook for guidance.

set -u

# -------- Configuration ------------------------------------------------------

CIRCUIT_URL="${CIRCUIT_URL:-https://circuit.pocket-technician.com}"
DEFAULT_TIMEOUT="${CIRCUIT_PROBE_TIMEOUT:-15}"      # seconds per request
SLOW_THRESHOLD_MS="${CIRCUIT_PROBE_SLOW_MS:-10000}" # >10s response = slow anomaly
LOG_DIR="${HOME}/.claude/state/circuit-health-log"
# Alert directory uses the generic name shared with the external-monitor surfacer hook.
ALERT_DIR="${HOME}/.claude/state/external-monitor-alerts"
PAUSE_MARKER="${HOME}/.claude/state/circuit-health-monitor-paused"
QUIET=0

# Route catalog — 24 critical routes.
# Format: METHOD|PATH|EXPECTED_CODES|TIMEOUT_S|LABEL
# Status code expectations follow tests/e2e.js conventions:
#   - public health/page routes: 200 (or 503 for degraded /api/health)
#   - auth-required API routes: 307 (Next middleware redirect to /login)
#   - webhooks: 401/403 (signature rejected) or 200 (twilio empty-TwiML)
#   - public lead intake: 400/401 (validation or webhook-secret mismatch)
ROUTES=(
  # Public + health
  "GET|/api/health|200,503|15|api-health"
  "GET|/|200,302,307|15|root"
  "GET|/login|200|15|login-page"
  "GET|/signup|200,302,307|15|signup-page"

  # Auth-required API routes (expect 307 redirect to /login)
  "GET|/api/auth/session|307,302|15|auth-session"
  "GET|/api/booking?org_id=00000000-0000-0000-0000-000000000000|307,302|15|booking"
  "GET|/api/campaigns?org_id=00000000-0000-0000-0000-000000000000|307,302|15|campaigns"
  "GET|/api/reps?org_id=00000000-0000-0000-0000-000000000000|307,302|15|reps"
  "GET|/api/templates?org_id=00000000-0000-0000-0000-000000000000|307,302|15|templates"
  "GET|/api/costs|307,302|15|costs"
  "GET|/api/dashboard|307,302|15|dashboard-api"
  "GET|/api/conversations|307,302|15|conversations"
  "GET|/api/analytics/funnel|307,302|15|analytics-funnel"
  "GET|/api/alerts|307,302|15|alerts"
  "GET|/api/notifications|307,302|15|notifications"
  "GET|/api/contacts/00000000-0000-0000-0000-000000000000?org_id=00000000-0000-0000-0000-000000000000|307,302|15|contacts-by-id"
  "GET|/api/settings/usage|307,302|15|settings-usage"

  # Webhook endpoints (expect signature rejection)
  "POST|/api/webhooks/retell|401|15|webhook-retell"
  "POST|/api/webhooks/resend|401|15|webhook-resend"
  "POST|/api/webhooks/twilio|200,403|15|webhook-twilio"

  # Page routes (auth-required, expect 307 to /login)
  "GET|/dashboard|307,302|15|dashboard-page"
  "GET|/contacts|307,302|15|contacts-page"
  "GET|/settings|307,302|15|settings-page"

  # Public lead intake (validation path)
  "POST|/api/leads|400,401|15|leads-post"
)

# -------- Argv ---------------------------------------------------------------

while [ "$#" -gt 0 ]; do
  case "$1" in
    --quiet) QUIET=1 ; shift ;;
    --self-test) shift ; SELF_TEST_REQUESTED=1 ;;
    --help|-h)
      sed -n '2,30p' "$0"
      exit 0
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      echo "Usage: $0 [--quiet] [--self-test] [--help]" >&2
      exit 2
      ;;
  esac
done

# -------- Helpers ------------------------------------------------------------

iso_now() {
  date -u +%Y-%m-%dT%H:%M:%SZ
}

iso_now_for_filename() {
  date -u +%Y-%m-%dT%H-%M-%SZ
}

# Build POST body + content-type for routes that require it. Returns
# nothing for GET routes. For known webhook paths, emit a minimal body
# the route will reject cleanly (so the probe exercises the signature
# check, not the body parser).
post_body_for() {
  local path="$1"
  case "$path" in
    "/api/webhooks/twilio")
      printf 'application/x-www-form-urlencoded\037%s' \
        'MessageSid=probe&From=%2B15555550100&To=%2B15555550101&Body=probe'
      ;;
    "/api/webhooks/retell")
      printf 'application/json\037%s' \
        '{"event":"call_ended","call_id":"probe"}'
      ;;
    "/api/webhooks/resend")
      printf 'application/json\037%s' \
        '{"type":"email.delivered","data":{"email_id":"probe"}}'
      ;;
    "/api/leads")
      printf 'application/json\037%s' '{}'
      ;;
    *)
      # No body for other POSTs; should not occur in current ROUTES.
      printf '%s\037%s' 'application/json' '{}'
      ;;
  esac
}

# Probe one route. Echoes a JSON object on stdout describing the result.
probe_one() {
  local method="$1"
  local path="$2"
  local expected="$3"   # comma-separated codes
  local timeout="$4"
  local label="$5"

  local url="${CIRCUIT_URL}${path}"
  local start_ns end_ns elapsed_ms status verdict failure_reason
  local curl_out curl_rc

  # curl outputs '%{http_code}'. --max-time enforces total timeout.
  # We use -o /dev/null to discard the body (we don't need it for
  # status-only checks; webhook bodies aren't validated here).
  # --silent --show-error keeps stderr empty unless something blows up.
  start_ns=$(date +%s%N 2>/dev/null || echo 0)

  if [ "$method" = "POST" ]; then
    local body_pair content_type body
    body_pair="$(post_body_for "$path")"
    content_type="${body_pair%%$'\037'*}"
    body="${body_pair#*$'\037'}"
    curl_out="$(curl --silent --show-error --max-time "$timeout" \
                   --request POST \
                   --header "Content-Type: ${content_type}" \
                   --data-raw "$body" \
                   --write-out '%{http_code}' \
                   --output /dev/null \
                   "$url" 2>&1)"
    curl_rc=$?
  else
    curl_out="$(curl --silent --show-error --max-time "$timeout" \
                   --request GET \
                   --write-out '%{http_code}' \
                   --output /dev/null \
                   "$url" 2>&1)"
    curl_rc=$?
  fi

  end_ns=$(date +%s%N 2>/dev/null || echo 0)
  # Compute elapsed_ms safely (date +%s%N on some Windows bashes outputs
  # the same literal, so we fall back to 0).
  if [ "$start_ns" != "0" ] && [ "$end_ns" != "0" ]; then
    elapsed_ms=$(( (end_ns - start_ns) / 1000000 ))
  else
    elapsed_ms=0
  fi

  # Determine status code: curl outputs '%{http_code}' as the last token.
  # On timeout / unresolved DNS / connection refused, curl_rc != 0 and the
  # http_code is "000".
  status="$(printf '%s' "$curl_out" | tail -c 6 | grep -Eo '[0-9]{3}$' | head -1)"
  if [ -z "$status" ]; then
    status="000"
  fi

  # Verdict logic:
  #   curl_rc != 0 AND status == 000 → TIMEOUT or NETWORK (errored before HTTP)
  #   status in expected list        → HEALTHY
  #   status starts with 5           → 5XX (down)
  #   status starts with 4 but not in expected → UNEXPECTED-4XX
  #   elapsed_ms > SLOW_THRESHOLD_MS → SLOW (degraded, even if status OK)
  #   else                           → UNEXPECTED-STATUS
  verdict="HEALTHY"
  failure_reason=""

  if [ "$curl_rc" -ne 0 ] && [ "$status" = "000" ]; then
    verdict="TIMEOUT_OR_NETWORK"
    failure_reason="curl exit ${curl_rc}: $(printf '%s' "$curl_out" | head -c 200 | tr '\n' ' ')"
  else
    # Check if status is in expected list.
    local code_ok=0
    local IFS=','
    for code in $expected; do
      if [ "$status" = "$code" ]; then
        code_ok=1
        break
      fi
    done
    unset IFS

    if [ "$code_ok" -eq 0 ]; then
      case "$status" in
        5*)
          verdict="HTTP_5XX"
          failure_reason="server error (status ${status})"
          ;;
        000)
          verdict="TIMEOUT_OR_NETWORK"
          failure_reason="curl exit ${curl_rc}"
          ;;
        *)
          verdict="UNEXPECTED_STATUS"
          failure_reason="got ${status}, expected one of (${expected})"
          ;;
      esac
    fi

    # Slowness: any response taking longer than SLOW_THRESHOLD_MS is a
    # degradation signal even when status is OK.
    if [ "$verdict" = "HEALTHY" ] && [ "$elapsed_ms" -gt "$SLOW_THRESHOLD_MS" ]; then
      verdict="SLOW"
      failure_reason="elapsed ${elapsed_ms}ms exceeds ${SLOW_THRESHOLD_MS}ms threshold"
    fi
  fi

  # Emit JSON for this route. We use a fixed schema so the alert and log
  # consumers can rely on it.
  printf '    {"label":"%s","method":"%s","path":"%s","expected":"%s","status":"%s","elapsed_ms":%d,"verdict":"%s","failure_reason":"%s"}' \
    "$label" "$method" "$(printf '%s' "$path" | sed 's/"/\\"/g')" "$expected" "$status" "$elapsed_ms" "$verdict" "$(printf '%s' "$failure_reason" | sed 's/"/\\"/g; s/\\/\\\\/g')"
}

# Aggregate results from probing all routes. Emits the full JSON report
# on stdout. Returns 0 if all routes healthy, 1 otherwise.
probe_all() {
  local started_at ended_at
  started_at="$(iso_now)"

  # Collect each route's JSON, comma-separated.
  local results=""
  local healthy=0 anomalies=0 first=1
  local route method path expected timeout label result verdict

  for route in "${ROUTES[@]}"; do
    method="$(printf '%s' "$route" | awk -F'|' '{print $1}')"
    path="$(printf '%s'   "$route" | awk -F'|' '{print $2}')"
    expected="$(printf '%s' "$route" | awk -F'|' '{print $3}')"
    timeout="$(printf '%s' "$route" | awk -F'|' '{print $4}')"
    label="$(printf '%s'  "$route" | awk -F'|' '{print $5}')"

    result="$(probe_one "$method" "$path" "$expected" "$timeout" "$label")"
    verdict="$(printf '%s' "$result" | sed -E 's/.*"verdict":"([^"]+)".*/\1/')"

    if [ "$verdict" = "HEALTHY" ]; then
      healthy=$((healthy + 1))
    else
      anomalies=$((anomalies + 1))
    fi

    if [ "$first" -eq 1 ]; then
      results="$result"
      first=0
    else
      results="${results},
${result}"
    fi
  done

  ended_at="$(iso_now)"

  # Emit aggregate report.
  cat <<EOF
{
  "schema_version": 1,
  "monitor_url": "${CIRCUIT_URL}",
  "circuit_url": "${CIRCUIT_URL}",
  "started_at": "${started_at}",
  "ended_at": "${ended_at}",
  "total_routes": ${#ROUTES[@]},
  "healthy_count": ${healthy},
  "anomaly_count": ${anomalies},
  "slow_threshold_ms": ${SLOW_THRESHOLD_MS},
  "results": [
${results}
  ]
}
EOF

  if [ "$anomalies" -gt 0 ]; then
    return 1
  fi
  return 0
}

# Persist the report to history. Always writes (whether healthy or not).
persist_log() {
  local report="$1"
  local ts
  ts="$(iso_now_for_filename)"
  mkdir -p "$LOG_DIR" 2>/dev/null || return 0
  printf '%s\n' "$report" > "${LOG_DIR}/${ts}.json"
}

# Emit an anomaly alert marker (consumed by the SessionStart surfacer).
# Skips emission when the pause marker exists.
emit_alert() {
  local report="$1"
  local ts
  ts="$(iso_now_for_filename)"

  if [ -f "$PAUSE_MARKER" ]; then
    # Maintenance pause active — log the suppression but no alert file.
    if [ "$QUIET" -eq 0 ]; then
      echo "[circuit-health-probe] pause marker present (${PAUSE_MARKER}); suppressing alert" >&2
    fi
    return 0
  fi

  mkdir -p "$ALERT_DIR" 2>/dev/null || return 0
  printf '%s\n' "$report" > "${ALERT_DIR}/${ts}.json"
  if [ "$QUIET" -eq 0 ]; then
    echo "[circuit-health-probe] anomaly alert written to ${ALERT_DIR}/${ts}.json" >&2
  fi
}

# -------- Self-test ----------------------------------------------------------

run_self_test() {
  local failures=0
  echo "SELF-TEST: tools/circuit-health-probe.sh"

  # Scenario 1: the script's flag parsing works.
  if bash "$0" --help >/dev/null 2>&1; then
    echo "  [PASS] s1 --help exits 0"
  else
    echo "  [FAIL] s1 --help did not exit 0" >&2
    failures=$((failures + 1))
  fi

  # Scenario 2: unknown flag returns exit 2.
  if bash "$0" --bogus-flag >/dev/null 2>&1; then
    echo "  [FAIL] s2 expected exit 2 for unknown flag, got 0" >&2
    failures=$((failures + 1))
  else
    local rc=$?
    if [ "$rc" -eq 2 ]; then
      echo "  [PASS] s2 unknown flag exits 2"
    else
      echo "  [FAIL] s2 expected exit 2, got ${rc}" >&2
      failures=$((failures + 1))
    fi
  fi

  # Scenario 3: probe_one against a deliberately unreachable host returns
  # TIMEOUT_OR_NETWORK and exits the function cleanly.
  local result verdict
  result="$(CIRCUIT_URL='http://127.0.0.1:1' probe_one GET / 200 2 root 2>/dev/null)"
  verdict="$(printf '%s' "$result" | sed -E 's/.*"verdict":"([^"]+)".*/\1/')"
  if [ "$verdict" = "TIMEOUT_OR_NETWORK" ]; then
    echo "  [PASS] s3 unreachable host → TIMEOUT_OR_NETWORK"
  else
    echo "  [FAIL] s3 expected TIMEOUT_OR_NETWORK, got '${verdict}'" >&2
    failures=$((failures + 1))
  fi

  # Scenario 4: probe_one against example.com on a route that returns 200
  # when we expect 200 yields HEALTHY (uses public DNS — skipped if no
  # network).
  if curl --silent --max-time 5 https://example.com/ -o /dev/null 2>/dev/null; then
    local result4 verdict4
    result4="$(CIRCUIT_URL='https://example.com' probe_one GET / 200 10 example 2>/dev/null)"
    verdict4="$(printf '%s' "$result4" | sed -E 's/.*"verdict":"([^"]+)".*/\1/')"
    if [ "$verdict4" = "HEALTHY" ]; then
      echo "  [PASS] s4 example.com 200 → HEALTHY"
    else
      echo "  [FAIL] s4 expected HEALTHY, got '${verdict4}'" >&2
      failures=$((failures + 1))
    fi
  else
    echo "  [SKIP] s4 no network to example.com"
  fi

  # Scenario 5: probe_one against example.com expecting 999 (impossible)
  # yields UNEXPECTED_STATUS.
  if curl --silent --max-time 5 https://example.com/ -o /dev/null 2>/dev/null; then
    local result5 verdict5
    result5="$(CIRCUIT_URL='https://example.com' probe_one GET / 999 10 example 2>/dev/null)"
    verdict5="$(printf '%s' "$result5" | sed -E 's/.*"verdict":"([^"]+)".*/\1/')"
    if [ "$verdict5" = "UNEXPECTED_STATUS" ]; then
      echo "  [PASS] s5 status mismatch → UNEXPECTED_STATUS"
    else
      echo "  [FAIL] s5 expected UNEXPECTED_STATUS, got '${verdict5}'" >&2
      failures=$((failures + 1))
    fi
  else
    echo "  [SKIP] s5 no network to example.com"
  fi

  # Scenario 6: pause marker suppresses alert emission. Use a temp marker
  # at a non-default path so we don't disturb real state.
  local tmp_alert_dir tmp_pause
  tmp_alert_dir="$(mktemp -d 2>/dev/null || mktemp -d -t circuit-probe-test.XXXXXX)"
  tmp_pause="${tmp_alert_dir}/paused"
  touch "$tmp_pause"
  ALERT_DIR="${tmp_alert_dir}/alerts" PAUSE_MARKER="$tmp_pause" emit_alert '{"test":1}' >/dev/null 2>&1
  if [ ! -d "${tmp_alert_dir}/alerts" ] || [ -z "$(ls -A "${tmp_alert_dir}/alerts" 2>/dev/null)" ]; then
    echo "  [PASS] s6 pause marker suppresses alert"
  else
    echo "  [FAIL] s6 pause marker did NOT suppress alert" >&2
    failures=$((failures + 1))
  fi
  rm -rf "$tmp_alert_dir" 2>/dev/null

  if [ "$failures" -eq 0 ]; then
    echo ""
    echo "SELF-TEST: all scenarios passed"
    return 0
  else
    echo ""
    echo "SELF-TEST: ${failures} scenario(s) failed" >&2
    return 1
  fi
}

if [ "${SELF_TEST_REQUESTED:-0}" -eq 1 ]; then
  run_self_test
  exit $?
fi

# -------- Main ---------------------------------------------------------------

# Pre-flight: ensure curl exists.
if ! command -v curl >/dev/null 2>&1; then
  echo "ERROR: curl is required but not in PATH" >&2
  exit 2
fi

report="$(probe_all)"
probe_rc=$?

# Always persist history.
persist_log "$report"

# Print the JSON report (unless quiet, in which case still print so a
# caller piping to jq gets something — --quiet only suppresses stderr
# narration).
if [ "$QUIET" -eq 0 ]; then
  echo "$report"
else
  echo "$report"
fi

# Anomaly: emit alert marker (unless paused).
if [ "$probe_rc" -ne 0 ]; then
  emit_alert "$report"
fi

exit "$probe_rc"
