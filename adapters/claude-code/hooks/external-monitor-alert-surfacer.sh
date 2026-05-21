#!/usr/bin/env bash
# external-monitor-alert-surfacer.sh
#
# Generic SessionStart hook that scans a configured external-monitor output
# directory for unacked alert JSON markers and surfaces them as a
# system-reminder so the orchestrator (or the user) sees prod regressions or
# other external-monitor anomalies before further work begins.
#
# Default alert directory: ~/.claude/state/external-monitor-alerts/
# Override per-invocation by passing a directory as the FIRST argument
# (this is what the maintainer's instance-tooling wires).
#
# Alert file contract (JSON):
#   - Filenames are ISO-like timestamps with the .json suffix.
#   - An alert is "acked" when a sibling file with the same name plus
#     .acked exists. Acked alerts are not surfaced.
#   - The hook expects top-level fields when present: started_at,
#     total_routes (or similar count field), healthy_count, anomaly_count,
#     and an array `results` whose entries carry `verdict`. The hook is
#     defensive: when fields are missing, it falls back gracefully.
#
# Design notes:
# - Mirrors `spawned-task-result-surfacer.sh` shape: SessionStart hook,
#   silent-when-empty, exit-0-always, --self-test flag.
# - Reads JSON on stdin per the Claude Code SessionStart hook contract,
#   but the payload is unused.
# - Surfacing cap: up to 5 newest unacked alerts to avoid flooding.
#
# Self-test: invoke with --self-test to exercise six scenarios.

set -u

ALERT_DIR_DEFAULT="${HOME}/.claude/state/external-monitor-alerts"

# -------- Utility: extract a top-level JSON scalar field --------
json_field() {
  local file="$1" key="$2"
  if command -v jq >/dev/null 2>&1; then
    jq -r --arg k "$key" '.[$k] // empty' "$file" 2>/dev/null
  else
    grep -E "\"${key}\"[[:space:]]*:" "$file" 2>/dev/null \
      | head -n 1 \
      | sed -E "s/.*\"${key}\"[[:space:]]*:[[:space:]]*\"?//; s/\"?[[:space:]]*,?[[:space:]]*$//"
  fi
}

is_valid_json() {
  local file="$1"
  [ -f "$file" ] || return 1
  if command -v jq >/dev/null 2>&1; then
    jq empty "$file" >/dev/null 2>&1
    return $?
  fi
  local first last
  first=$(awk 'NF { print substr($0, 1, 1); exit }' "$file" 2>/dev/null)
  last=$(awk 'NF { line = $0 } END { if (line) print substr(line, length(line), 1) }' "$file" 2>/dev/null)
  [ "$first" = "{" ] && [ "$last" = "}" ]
}

extract_anomaly_lines() {
  local file="$1"
  if command -v jq >/dev/null 2>&1; then
    jq -r '.results[]? | select((.verdict // "") != "HEALTHY") | "    - \(.label // "n/a") [\(.method // "?") \(.path // "?")] verdict=\(.verdict // "?") status=\(.status // "?") elapsed=\(.elapsed_ms // 0)ms reason=\(.failure_reason // "")"' "$file" 2>/dev/null
  else
    grep -v '"verdict":"HEALTHY"' "$file" 2>/dev/null \
      | grep '"label":' \
      | sed -E 's/.*"label":"([^"]+)","method":"([^"]+)","path":"([^"]+)".*"status":"([^"]+)","elapsed_ms":([0-9]+),"verdict":"([^"]+)","failure_reason":"([^"]*)".*/    - \1 [\2 \3] verdict=\6 status=\4 elapsed=\5ms reason=\7/'
  fi
}

# Core surfacing logic. Writes the system-reminder block to stdout.
surface_external_monitor_alerts() {
  local alert_dir="${1:-$ALERT_DIR_DEFAULT}"

  if [ ! -d "$alert_dir" ]; then
    return 0
  fi

  local unread_files=()
  local f base
  for f in "$alert_dir"/*.json; do
    [ -f "$f" ] || continue
    case "$f" in
      *.json.acked) continue ;;
    esac
    if [ -f "${f}.acked" ]; then
      continue
    fi
    if ! is_valid_json "$f"; then
      base=$(basename "$f")
      echo "[external-monitor-surfacer] skipping $base (malformed JSON)" >&2
      continue
    fi
    unread_files+=("$f")
  done

  if [ "${#unread_files[@]}" -eq 0 ]; then
    return 0
  fi

  local sorted_files=()
  while IFS= read -r line; do
    [ -n "$line" ] && sorted_files+=("$line")
  done < <(printf '%s\n' "${unread_files[@]}" | sort -r)

  local total="${#sorted_files[@]}"
  local cap=5

  echo ""
  echo "<system-reminder>"
  echo "SessionStart:startup hook success: [external-monitor-surfacer] ${total} unacked alert(s) in ${alert_dir}."
  if [ "$total" -gt "$cap" ]; then
    echo "Showing newest ${cap}; the remaining $(( total - cap )) are visible by listing the directory."
  fi
  echo ""

  local i=0
  local file ts started_at total_routes healthy anomaly anomalies_block monitor_url
  for file in "${sorted_files[@]}"; do
    [ "$i" -ge "$cap" ] && break
    i=$((i + 1))

    base=$(basename "$file")
    ts=$(printf '%s' "$base" | sed -E 's/\.json$//')
    monitor_url="$(json_field "$file" monitor_url)"
    started_at="$(json_field "$file" started_at)"
    total_routes="$(json_field "$file" total_routes)"
    healthy="$(json_field "$file" healthy_count)"
    anomaly="$(json_field "$file" anomaly_count)"
    anomalies_block="$(extract_anomaly_lines "$file")"

    echo "  • Alert ${ts} — ${anomaly}/${total_routes} routes anomalous (${healthy} healthy)"
    if [ -n "$monitor_url" ]; then
      echo "    Monitor target: ${monitor_url}"
    fi
    echo "    Probed at: ${started_at}"
    echo "    File: ${file}"
    if [ -n "$anomalies_block" ]; then
      printf '%s\n' "$anomalies_block"
    fi
    echo ""
  done

  cat <<'EOF'
Triage options for any unacked alert:
  (a) Investigate the regression and open a fix branch in the affected repo.
  (b) Acknowledge if known/already-tracked:
        touch <alert-file>.acked
  (c) Pause the monitor during maintenance (per its runbook).

If multiple alerts repeat the SAME anomalies, the regression is ongoing and
unacknowledged — investigate before acknowledging.
</system-reminder>
EOF
}

# -------- Self-test --------

run_self_test() {
  local failures=0
  local tmp_root
  tmp_root="$(mktemp -d 2>/dev/null || mktemp -d -t external-monitor-surfacer-test.XXXXXX)"
  trap "rm -rf '$tmp_root'" EXIT

  echo "SELF-TEST: hooks/external-monitor-alert-surfacer.sh"

  # s1: missing directory → silent.
  local out1
  out1="$(surface_external_monitor_alerts "${tmp_root}/does-not-exist" 2>/dev/null)"
  if [ -z "$out1" ]; then
    echo "  [PASS] s1 missing dir -> silent"
  else
    echo "  [FAIL] s1 expected silent, got: $out1" >&2
    failures=$((failures + 1))
  fi

  # s2: empty directory → silent.
  local dir2="${tmp_root}/s2"
  mkdir -p "$dir2"
  local out2
  out2="$(surface_external_monitor_alerts "$dir2" 2>/dev/null)"
  if [ -z "$out2" ]; then
    echo "  [PASS] s2 empty dir -> silent"
  else
    echo "  [FAIL] s2 expected silent, got: $out2" >&2
    failures=$((failures + 1))
  fi

  # s3: single unacked alert → surfaces system-reminder with details.
  local dir3="${tmp_root}/s3"
  mkdir -p "$dir3"
  cat > "${dir3}/2026-05-21T13-57-45Z.json" <<'JSON'
{
  "schema_version": 1,
  "monitor_url": "https://example.com",
  "started_at": "2026-05-21T13:55:46Z",
  "ended_at": "2026-05-21T13:57:44Z",
  "total_routes": 24,
  "healthy_count": 18,
  "anomaly_count": 6,
  "slow_threshold_ms": 10000,
  "results": [
    {"label":"a","method":"GET","path":"/x","expected":"200","status":"000","elapsed_ms":15480,"verdict":"TIMEOUT_OR_NETWORK","failure_reason":"curl exit 28"}
  ]
}
JSON
  local out3
  out3="$(surface_external_monitor_alerts "$dir3" 2>/dev/null)"
  if printf '%s' "$out3" | grep -q "1 unacked" \
     && printf '%s' "$out3" | grep -q "example.com" \
     && printf '%s' "$out3" | grep -q "TIMEOUT_OR_NETWORK"; then
    echo "  [PASS] s3 unacked alert surfaces with detail"
  else
    echo "  [FAIL] s3 expected surfaced detail, got:" >&2
    echo "$out3" | sed 's/^/    /' >&2
    failures=$((failures + 1))
  fi

  # s4: acked alert → not surfaced.
  touch "${dir3}/2026-05-21T13-57-45Z.json.acked"
  local out4
  out4="$(surface_external_monitor_alerts "$dir3" 2>/dev/null)"
  if [ -z "$out4" ]; then
    echo "  [PASS] s4 acked alert is suppressed"
  else
    echo "  [FAIL] s4 expected suppression, got: $out4" >&2
    failures=$((failures + 1))
  fi

  # s5: malformed JSON → skipped, valid one surfaces.
  local dir5="${tmp_root}/s5"
  mkdir -p "$dir5"
  echo "this is not json" > "${dir5}/2026-05-20T10-00-00Z.json"
  cat > "${dir5}/2026-05-21T10-00-00Z.json" <<'JSON'
{
  "schema_version": 1,
  "monitor_url": "https://example.com",
  "started_at": "2026-05-21T10:00:00Z",
  "ended_at": "2026-05-21T10:00:30Z",
  "total_routes": 1,
  "healthy_count": 0,
  "anomaly_count": 1,
  "slow_threshold_ms": 10000,
  "results": [
    {"label":"x","method":"GET","path":"/x","expected":"200","status":"500","elapsed_ms":50,"verdict":"HTTP_5XX","failure_reason":"server error"}
  ]
}
JSON
  local out5 err5
  err5="$(mktemp)"
  out5="$(surface_external_monitor_alerts "$dir5" 2>"$err5")"
  if printf '%s' "$out5" | grep -q "1 unacked" \
     && grep -q "malformed JSON" "$err5"; then
    echo "  [PASS] s5 malformed JSON skipped, valid one surfaced"
  else
    echo "  [FAIL] s5 expected malformed-skip + valid-surfaced" >&2
    echo "    stdout: $out5" >&2
    echo "    stderr: $(cat "$err5")" >&2
    failures=$((failures + 1))
  fi
  rm -f "$err5"

  # s6: > 5 alerts → cap at 5 with overflow note.
  local dir6="${tmp_root}/s6"
  mkdir -p "$dir6"
  local n
  for n in 01 02 03 04 05 06 07; do
    cat > "${dir6}/2026-05-21T10-${n}-00Z.json" <<JSON
{"schema_version":1,"monitor_url":"x","started_at":"x","ended_at":"x","total_routes":1,"healthy_count":0,"anomaly_count":1,"slow_threshold_ms":10000,"results":[{"label":"r${n}","method":"GET","path":"/x","expected":"200","status":"500","elapsed_ms":1,"verdict":"HTTP_5XX","failure_reason":""}]}
JSON
  done
  local out6
  out6="$(surface_external_monitor_alerts "$dir6" 2>/dev/null)"
  if printf '%s' "$out6" | grep -q "7 unacked" \
     && printf '%s' "$out6" | grep -q "Showing newest 5"; then
    echo "  [PASS] s6 cap-at-5 with overflow message"
  else
    echo "  [FAIL] s6 expected cap message" >&2
    echo "$out6" | sed 's/^/    /' >&2
    failures=$((failures + 1))
  fi

  trap - EXIT
  rm -rf "$tmp_root"

  if [ "$failures" -eq 0 ]; then
    echo ""
    echo "SELF-TEST: all scenarios passed (6/6 required)"
    return 0
  else
    echo ""
    echo "SELF-TEST: ${failures} scenario(s) failed" >&2
    return 1
  fi
}

# -------- Entry point --------
if [ "${1:-}" = "--self-test" ]; then
  run_self_test
  exit $?
fi

if [ ! -t 0 ]; then
  cat >/dev/null 2>&1 || true
fi

surface_external_monitor_alerts "${1:-$ALERT_DIR_DEFAULT}"
exit 0
