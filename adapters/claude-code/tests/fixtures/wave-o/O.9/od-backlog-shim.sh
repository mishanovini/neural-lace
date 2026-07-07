#!/usr/bin/env bash
# od-backlog-shim.sh — PRIVATE test/dev shim for contract C4's
# od_backlog_health (specs-o §O.9, CANONICAL-COUNTERS-01).
#
# THIS IS NOT THE SHIPPED ORACLE. The shipped oracle is
# `adapters/claude-code/hooks/lib/observability-derive.sh`, owned and built
# by task O.3 (in progress in parallel — §O.0.1 rule: O.9 never creates or
# edits that file). This shim is a byte-for-byte copy of the same functions
# documented as the splice fragment in
# `tests/fixtures/wave-o/O.9/od-backlog-health-functions.md`, kept here ONLY
# so O.9's own consumers (session-start-digest.sh, plan-edit-validator.sh,
# harness-kpis.sh) can run green standalone BEFORE O.3 merges.
#
# Consumers source this via a guarded, feature-detected fallback:
#
#   { source ".../hooks/lib/observability-derive.sh" 2>/dev/null; } || true
#   if ! declare -F od_backlog_health >/dev/null 2>&1; then
#     { source ".../tests/fixtures/wave-o/O.9/od-backlog-shim.sh" 2>/dev/null; } || true
#   fi
#
# so that:
#   - standalone (pre-O.3-merge): observability-derive.sh doesn't exist yet
#     (source is a silent no-op), declare -F fails, this shim sources and
#     supplies od_backlog_health -> consumer runs green.
#   - post-splice (real lib has od_backlog_health): observability-derive.sh
#     sources successfully, declare -F succeeds, this shim is NEVER sourced
#     -> consumer runs against the real oracle, zero duplicate function
#     definitions, zero drift risk.
#
# DELETE THIS FILE once O.3 merges and the orchestrator confirms all three
# consumers pass self-test against the real observability-derive.sh (the
# guarded-source call sites can stay — they degrade to sourcing nothing once
# this file is gone, which is fine: at that point the real lib always wins
# the declare -F check first).
#
# Sandboxing: this file performs ZERO state writes of its own (pure
# functions only, per C4's "pure READ functions, zero state writes"
# requirement) — inherits whatever BACKLOG_MD_PATH / HARNESS_SELFTEST
# sandboxing the caller has already set up. Safe to source unconditionally.

# Guard against double-sourcing (consumers may guard-source from multiple
# call sites in the same process, e.g. a self-test harness that re-sources
# per-scenario).
if [[ -n "${_OD_BACKLOG_SHIM_LOADED:-}" ]]; then
  return 0 2>/dev/null || exit 0
fi
_OD_BACKLOG_SHIM_LOADED=1

_od_backlog_path() {
  if [[ -n "${BACKLOG_MD_PATH:-}" ]]; then
    printf '%s' "$BACKLOG_MD_PATH"
    return 0
  fi
  local root
  if command -v nl_repo_root >/dev/null 2>&1; then
    root="$(nl_repo_root)"
  else
    root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  fi
  printf '%s/docs/backlog.md' "$root"
}

_od_backlog_date_epoch() {
  local d="$1"
  date -u -d "$d" +%s 2>/dev/null \
    || date -u -j -f '%Y-%m-%d' "$d" +%s 2>/dev/null \
    || echo ""
}

# _od_backlog_row_is_terminal <row line> -> 0 (terminal) / 1 (open).
# POSITION-ANCHORED marker detection (87f357f) — see
# od-backlog-health-functions.md for the full rationale. R1-R4 verbatim.
_OD_BACKLOG_TERM_U='(DISPOSITIONED|IMPLEMENTED|ABSORBED|CLOSED|SUPERSEDED|WONTFIX)'
_od_backlog_row_is_terminal() {
  local line="$1"
  printf '%s' "$line" | grep -qE "^- \*\*[^*]*\b${_OD_BACKLOG_TERM_U}\b" && return 0
  printf '%s' "$line" | grep -qE "\*\*[[:space:]]+(—|--?)[[:space:]]+${_OD_BACKLOG_TERM_U}\b" && return 0
  printf '%s' "$line" | grep -qiE '\*\*\((dispositioned|implemented|absorbed|closed|superseded|wontfix)\b' && return 0
  printf '%s' "$line" | grep -qE "\*\*((PARTIALLY|LARGELY)[[:space:]]+)?${_OD_BACKLOG_TERM_U}\b" && return 0
  return 1
}

# od_backlog_health [--json] — contract C4. See od-backlog-health-functions.md
# for the JSON schema. Both flag states print the same JSON document.
od_backlog_health() {
  local backlog; backlog="$(_od_backlog_path)"
  local tier_high="${BACKLOG_TIER_HIGH_DAYS:-7}"
  local tier_medium="${BACKLOG_TIER_MEDIUM_DAYS:-30}"
  local tier_low="${BACKLOG_TIER_LOW_DAYS:-90}"
  local window_days="${BACKLOG_HEALTH_WINDOW_DAYS:-7}"
  local now; now="$(date -u +%s)"
  local now_iso; now_iso="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  local window_start=$((now - window_days * 86400))

  if [[ ! -f "$backlog" ]]; then
    if command -v node >/dev/null 2>&1; then
      node -e '
        var doc = {schema:1, oracle:"od_backlog_health", generated_at:process.argv[1],
          backlog_path:process.argv[2], window_days:Number(process.argv[3]), rows:[],
          summary:{open_total:0, terminal_total:0,
            priority_counts:{high:0,medium:0,low:0,unlabeled:0},
            age_tiers:{"0_7":0,"8_30":0,"31_90":0,over_90:0,undated:0},
            overdue_ids:[], adds_in_window:0, terminal_in_window:0, terminal_undated:0},
          note:"no backlog file at backlog_path"};
        process.stdout.write(JSON.stringify(doc));
      ' "$now_iso" "$backlog" "$window_days"
    else
      printf '{"schema":1,"oracle":"od_backlog_health","degraded":"node unavailable","rows":[],"summary":{}}'
    fi
    printf '\n'
    return 0
  fi

  local rows_tmp; rows_tmp="$(mktemp 2>/dev/null || mktemp -t odbacklog)"
  trap 'rm -f "$rows_tmp"' RETURN

  local line id added added_epoch age_days prio_label prio threshold is_terminal term_date term_epoch
  while IFS= read -r line; do
    id="$(printf '%s' "$line" | grep -oE '^- \*\*[A-Z][A-Z0-9-]{3,}' | sed 's/^- \*\*//')"
    [[ -z "$id" ]] && continue

    added="$(printf '%s' "$line" | grep -oE 'added [0-9]{4}-[0-9]{2}-[0-9]{2}' | head -n1 | sed 's/^added //')"
    added_epoch=""
    [[ -n "$added" ]] && added_epoch="$(_od_backlog_date_epoch "$added")"
    age_days=""
    [[ -n "$added_epoch" ]] && age_days=$(( (now - added_epoch) / 86400 ))

    prio_label="$(printf '%s' "$line" | grep -oE 'priority:(high|medium|low)' | head -n1 | sed 's/^priority://')"
    prio="$prio_label"
    [[ -z "$prio" ]] && prio="low"
    case "$prio" in
      high)   threshold="$tier_high" ;;
      medium) threshold="$tier_medium" ;;
      *)      threshold="$tier_low" ;;
    esac

    is_terminal="false"
    term_date=""
    term_epoch=""
    if _od_backlog_row_is_terminal "$line"; then
      is_terminal="true"
      term_date="$(printf '%s' "$line" \
        | grep -oiE "${_OD_BACKLOG_TERM_U}[^0-9]{0,12}[0-9]{4}-[0-9]{2}-[0-9]{2}" \
        | head -n1 | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' || true)"
      [[ -n "$term_date" ]] && term_epoch="$(_od_backlog_date_epoch "$term_date")"
    fi

    node -e '
      var a = process.argv.slice(1);
      var row = {id:a[0], line:a[1], terminal: a[2] === "true",
        added: a[3] || null, added_epoch: a[4] ? Number(a[4]) : null,
        age_days: a[5] ? Number(a[5]) : null,
        priority_label: a[6] || "", priority: a[7],
        threshold_days: Number(a[8]),
        terminal_date: a[9] || null,
        terminal_epoch: a[10] ? Number(a[10]) : null};
      process.stdout.write(JSON.stringify(row) + "\n");
    ' "$id" "$line" "$is_terminal" "$added" "$added_epoch" "$age_days" \
      "$prio_label" "$prio" "$threshold" "$term_date" "$term_epoch" >> "$rows_tmp" 2>/dev/null
  done < <(grep -E '^- \*\*[A-Z]' "$backlog" 2>/dev/null)

  if ! command -v node >/dev/null 2>&1; then
    printf '{"schema":1,"oracle":"od_backlog_health","degraded":"node unavailable","rows":[],"summary":{}}\n'
    rm -f "$rows_tmp"
    return 0
  fi

  node -e '
    "use strict";
    var fs = require("fs");
    var rowsPath = process.argv[1], backlogPath = process.argv[2];
    var nowIso = process.argv[3], windowDays = Number(process.argv[4]);
    var windowStart = Number(process.argv[5]);
    var raw = "";
    try { raw = fs.readFileSync(rowsPath, "utf8"); } catch (e) {}
    var rows = raw.split("\n").filter(Boolean).map(function (l) {
      try { return JSON.parse(l); } catch (e) { return null; }
    }).filter(Boolean);

    var summary = {
      open_total: 0, terminal_total: 0,
      priority_counts: {high:0, medium:0, low:0, unlabeled:0},
      age_tiers: {"0_7":0, "8_30":0, "31_90":0, over_90:0, undated:0},
      overdue_ids: [], adds_in_window: 0, terminal_in_window: 0, terminal_undated: 0
    };
    var overdue = [];

    rows.forEach(function (r) {
      if (r.added_epoch !== null && r.added_epoch >= windowStart) {
        summary.adds_in_window++;
      }
      if (r.terminal) {
        summary.terminal_total++;
        if (r.terminal_epoch !== null) {
          if (r.terminal_epoch >= windowStart) summary.terminal_in_window++;
        } else {
          summary.terminal_undated++;
        }
        r.is_overdue = false;
        r.terminal_in_window = (r.terminal_epoch !== null && r.terminal_epoch >= windowStart);
        return;
      }
      summary.open_total++;
      var pl = r.priority_label || "";
      if (pl === "high") summary.priority_counts.high++;
      else if (pl === "medium") summary.priority_counts.medium++;
      else if (pl === "low") summary.priority_counts.low++;
      else summary.priority_counts.unlabeled++;

      if (r.age_days === null) {
        summary.age_tiers.undated++;
      } else if (r.age_days <= 7) summary.age_tiers["0_7"]++;
      else if (r.age_days <= 30) summary.age_tiers["8_30"]++;
      else if (r.age_days <= 90) summary.age_tiers["31_90"]++;
      else summary.age_tiers.over_90++;

      r.is_overdue = (r.age_days !== null && r.age_days > r.threshold_days);
      r.terminal_in_window = false;
      if (r.is_overdue) overdue.push(r);
    });

    overdue.sort(function (a, b) { return (b.age_days||0) - (a.age_days||0); });
    summary.overdue_ids = overdue.map(function (r) { return r.id; });

    var doc = {
      schema: 1, oracle: "od_backlog_health", generated_at: nowIso,
      backlog_path: backlogPath, window_days: windowDays,
      rows: rows, summary: summary
    };
    process.stdout.write(JSON.stringify(doc));
  ' "$rows_tmp" "$backlog" "$now_iso" "$window_days" "$window_start"
  printf '\n'

  rm -f "$rows_tmp"
  trap - RETURN
  return 0
}

# ============================================================
# --self-test — oracle-level regression coverage, independent of the
# three consumers (which have their own self-tests exercising this same
# logic end-to-end). Only runs when this file is invoked directly (not
# when sourced by a consumer) — the double-source guard above already
# returns early for the sourced case.
#
# HARNESS_SELFTEST=1 posture (§O.0.1 rule 3): every fixture backlog lives
# under a mktemp dir passed via BACKLOG_MD_PATH; the real docs/backlog.md
# is never read here.
# ============================================================
if [[ "${BASH_SOURCE[0]}" == "${0}" ]] && [[ "${1:-}" == "--self-test" ]]; then
  set +u
  PASSED=0
  FAILED=0
  pass() { PASSED=$((PASSED+1)); printf '  PASS: %s\n' "$1"; }
  fail() { FAILED=$((FAILED+1)); printf '  FAIL: %s\n' "$1" >&2; }

  TMP="$(mktemp -d 2>/dev/null || mktemp -d -t odbacklog-self)"
  trap 'rm -rf "$TMP"' EXIT

  d8="$(date -u -d '8 days ago' '+%Y-%m-%d' 2>/dev/null || date -u -v-8d '+%Y-%m-%d' 2>/dev/null)"
  d31="$(date -u -d '31 days ago' '+%Y-%m-%d' 2>/dev/null || date -u -v-31d '+%Y-%m-%d' 2>/dev/null)"
  d91="$(date -u -d '91 days ago' '+%Y-%m-%d' 2>/dev/null || date -u -v-91d '+%Y-%m-%d' 2>/dev/null)"
  d6="$(date -u -d '6 days ago' '+%Y-%m-%d' 2>/dev/null || date -u -v-6d '+%Y-%m-%d' 2>/dev/null)"

  echo "Scenario 1: basic tiers + 87f357f positional terminal-marker regression"
  BL1="$TMP/backlog1.md"
  cat > "$BL1" <<EOF
# Fixture Backlog

- **HIGH-OVERDUE-01 — fixture high crossed** (added $d8; \`priority:high\`). Prose.
- **HIGH-FRESH-01 — fixture high NOT crossed** (added $d6; \`priority:high\`). Prose.
- **MED-OVERDUE-01 — fixture medium crossed** (added $d31; \`priority:medium\`). Prose.
- **TERM-CLOSED-01 — [CLOSED $d8] terminal** (added $d91; \`priority:high\`). Prose.
- **TERM-ABSORBED-01 — done long ago** (added $d91; \`priority:high\`). **(absorbed by docs/plans/fixture.md)**.
- **TERM-IMPL-01** — IMPLEMENTED $d8 via docs/plans/fixture2.md (added $d91; \`priority:high\`).
- **OPEN-REF-01 — open row referencing another row's terminal state** (added $d8; \`priority:high\`). **This is distinct from OTHER-GAP-99 (IMPLEMENTED 2026-01-01).** Still open.
EOF
  OUT1="$(BACKLOG_MD_PATH="$BL1" od_backlog_health --json)"

  if printf '%s' "$OUT1" | node -e '
    var d=JSON.parse(require("fs").readFileSync(0,"utf8"));
    var ids=d.summary.overdue_ids;
    process.exit((ids.includes("HIGH-OVERDUE-01") && ids.includes("MED-OVERDUE-01")
      && ids.includes("OPEN-REF-01") && !ids.includes("HIGH-FRESH-01")
      && !ids.includes("TERM-CLOSED-01") && !ids.includes("TERM-ABSORBED-01")
      && !ids.includes("TERM-IMPL-01")) ? 0 : 1);
  '; then
    pass "overdue_ids correct (3 overdue incl. positional-reference row, terminal rows excluded, fresh row excluded)"
  else
    fail "overdue_ids wrong: $(printf '%s' "$OUT1" | node -e 'console.log(JSON.stringify(JSON.parse(require("fs").readFileSync(0,"utf8")).summary.overdue_ids))')"
  fi

  if printf '%s' "$OUT1" | node -e '
    var d=JSON.parse(require("fs").readFileSync(0,"utf8"));
    process.exit((d.summary.open_total === 4 && d.summary.terminal_total === 3) ? 0 : 1);
  '; then
    pass "open_total=4 (incl. OPEN-REF-01 and HIGH-FRESH-01), terminal_total=3"
  else
    fail "open/terminal totals wrong"
  fi

  echo "Scenario 2: no backlog file -> honest empty JSON, no crash"
  OUT2="$(BACKLOG_MD_PATH="$TMP/does-not-exist.md" od_backlog_health --json)"
  if printf '%s' "$OUT2" | node -e '
    var d=JSON.parse(require("fs").readFileSync(0,"utf8"));
    process.exit((Array.isArray(d.rows) && d.rows.length === 0 && d.summary.open_total === 0) ? 0 : 1);
  '; then
    pass "absent backlog -> empty rows, zeroed summary, no crash"
  else
    fail "absent backlog produced unexpected output: $OUT2"
  fi

  echo "Scenario 3: adds-vs-terminal 7d window"
  BL3="$TMP/backlog3.md"
  cat > "$BL3" <<EOF
- **WINDOW-ADD-01 — added inside window** (added $d6; \`priority:low\`). Prose.
- **WINDOW-TERM-01 — [CLOSED $d6] terminal inside window** (added $d91; \`priority:low\`). Prose.
- **WINDOW-TERM-UNDATED-01 — done, no adjacent date** (added $d91; \`priority:low\`). **(absorbed by docs/plans/x.md)**.
EOF
  OUT3="$(BACKLOG_MD_PATH="$BL3" BACKLOG_HEALTH_WINDOW_DAYS=7 od_backlog_health --json)"
  if printf '%s' "$OUT3" | node -e '
    var d=JSON.parse(require("fs").readFileSync(0,"utf8"));
    var s=d.summary;
    process.exit((s.adds_in_window === 1 && s.terminal_in_window === 1 && s.terminal_undated === 1) ? 0 : 1);
  '; then
    pass "adds_in_window=1, terminal_in_window=1, terminal_undated=1"
  else
    fail "flow window counts wrong: $(printf '%s' "$OUT3" | node -e 'console.log(JSON.stringify(JSON.parse(require("fs").readFileSync(0,"utf8")).summary))')"
  fi

  echo "Scenario 4: real flagless invocation shape — source + call, no fixture-scoped flags on the command line"
  ( source "${BASH_SOURCE[0]}"; declare -F od_backlog_health >/dev/null 2>&1 )
  if [[ $? -eq 0 ]]; then
    pass "sourcing this file in a fresh subshell defines od_backlog_health (the exact shape consumers use)"
  else
    fail "sourcing this file did not define od_backlog_health"
  fi

  printf '\nself-test summary: %d passed, %d failed\n' "$PASSED" "$FAILED"
  if [[ "$FAILED" -gt 0 ]]; then
    echo "self-test: FAIL"
    exit 1
  fi
  echo "self-test: PASS"
  exit 0
fi
