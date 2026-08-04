#!/bin/bash
# verify-event-audit.sh — read-only cross-check: does every CHECKED plan
# task have a matching `flip-verdict` verification EVENT on record?
#
# ============================================================
# WHY THIS EXISTS (2026-08-04, operator directive verbatim: "update the
# task verifiers to check off the check boxes in two places (plan file and
# ledger)... they are still keeping track of their single source of truth
# within the plan file like they normally do, and they additionally are
# updating the global status at the same time")
# ============================================================
#
# `plan-edit-validator.sh`'s `emit_flip_ledger_event` (SE4, status-event-
# ledger plan, extended 2026-08-04) writes a `flip-verdict` row to
# $SIGNAL_LEDGER_PATH on every AUTHORIZED checkbox flip, BEFORE the flip
# itself lands on disk. THE EVENT IS THE FACT ("verifier V passed plan P
# task N at time T with evidence E"); the plan-file checkbox is the
# PROJECTION of that event. This script is the detector half of that
# framing: it never fabricates a missing event, and it never claims a
# checked-but-eventless task is either "verified" or "unverified" — it
# reports the true third state, NO_VERIFICATION_EVENT_ON_RECORD, honestly.
#
# A checked box with no matching event is not automatically a problem — it
# is the ANOMALY signal the event/projection design deliberately makes
# visible: a hand-edit, a bypassed hook, a bulk Write, or (see the
# CONFIRMED-EMPIRICALLY note in plan-edit-validator.sh's own EVENT-NOT-
# SECOND-SOURCE comment) simply a flip whose task id used a convention the
# gate's own TASK_ID regex does not yet parse (HARNESS-GAP-62,
# docs/backlog.md). This script surfaces the state; it does not judge it.
#
# ============================================================
# USAGE
# ============================================================
#   verify-event-audit.sh --task <plan-file> <task-id>
#       One task. Exit 0 + "HAS_EVENT_ON_RECORD ..." if a matching event
#       exists; exit 1 + "NO_VERIFICATION_EVENT_ON_RECORD ..." otherwise.
#
#   verify-event-audit.sh --plan <plan-file>
#       Every CHECKED ("- [x] ...") task line in one plan file. Prints one
#       tab-separated row per checked task, then a summary line to stderr:
#         plan=<slug> total_checked=<N> has_event=<H> no_event=<M>
#       Exit 0 always (a report, not a gate).
#
#   verify-event-audit.sh --sweep [<root-dir>]
#       Every *.md file under <root-dir> (default: docs/plans), recursive —
#       covers docs/plans/archive/ and docs/plans/deferred/ too, which is
#       the point: a backfill count must see every plan, not just active
#       ones. Excludes *-evidence.md companion files. Prints one row per
#       checked task with NO event, then a final summary line to stderr:
#         sweep root=<dir> total_checked=<N> has_event=<H> no_event=<M>
#       Exit 0 always (a report, not a gate).
#
#   verify-event-audit.sh --self-test
#       Sandboxed (own SIGNAL_LEDGER_PATH + temp plan fixtures). Exit 0/1.
#
# ============================================================
# CONFIGURATION
# ============================================================
#   SIGNAL_LEDGER_PATH   the ledger to read. Default: $HOME/.claude/state/
#                        signal-ledger.jsonl (same resolution + same file
#                        plan-edit-validator.sh's emit_flip_ledger_event
#                        writes to via signal-ledger.sh — one ledger, this
#                        is its reader, not a second store).
#
# ============================================================
# HEURISTIC DISCLOSURE (never a gate, never blocking — read-only always)
# ============================================================
# Checked-task-id extraction is a best-effort regex over
# "- [x] <token>" / "- [X] <token>" lines (a trailing literal "." is
# stripped, matching hooks/lib/review-chain-lib.sh's own convention for
# plan task lists) — it does not distinguish a genuine plan task line from
# an unrelated checklist item that happens to open the same way (e.g. a
# stray checkbox in prose). This is acceptable for an OBSERVABILITY tool
# that never blocks anything; a caller wanting a stricter oracle should
# cross-check the plan's own `## Tasks` section by hand.

set -uo pipefail

: "${SIGNAL_LEDGER_PATH:=$HOME/.claude/state/signal-ledger.jsonl}"
if [[ "${HARNESS_SELFTEST:-0}" == "1" ]] && [[ -z "${_VEA_LEDGER_PATH_EXPLICIT:-}" ]]; then
  # Self-test always sandboxes even if the caller forgot to export an
  # explicit SIGNAL_LEDGER_PATH — mirrors signal-ledger.sh's own contract.
  SIGNAL_LEDGER_PATH="${TMPDIR:-/tmp}/verify-event-audit-selftest/$$.jsonl"
fi

# _vea_norm_task_id <task-id> — strips ONE leading T/t when immediately
# followed by a digit (the same T7-incident normalization used by
# hooks/lib/review-chain-lib.sh's _rc_norm_task_id and workstreams-emit.sh's
# _ledger_task_id_known). "T7" -> "7", "7" -> "7", "3.2" -> "3.2".
_vea_norm_task_id() {
  local t="$1"
  [[ "$t" =~ ^[Tt][0-9] ]] && t="${t:1}"
  printf '%s' "$t"
}

# _vea_checked_task_ids <plan-file> — one task id per line for every
# "- [x] <id>" / "- [X] <id>" line in the file. A bare trailing "." (the
# "- [x] 7. Do the thing" numeric convention's sentence-ending punctuation,
# as opposed to an internal dotted id like "3.2" or "A.1") is excluded by
# the regex itself: each "." only extends the match when followed by an
# alphanumeric, so a dot immediately before whitespace/EOL is never part of
# the captured token in the first place — no separate strip step needed
# (verified directly: this differs from hooks/lib/review-chain-lib.sh's
# sibling `_ledger_known_task_ids`, whose numeric-only pattern captures the
# trailing dot as a MANDATORY part of the match and strips it with sed;
# this script's pattern additionally has to accept undotted-trailing forms
# like "A.1", so it was built the other way around from the start).
# Empty output (never an error) for a missing/unreadable file.
_vea_checked_task_ids() {
  local f="$1"
  [[ -f "$f" ]] || return 0
  grep -oE '^- \[[xX]\][[:space:]]+[A-Za-z0-9]+(\.[A-Za-z0-9]+)*' "$f" 2>/dev/null \
    | sed -E 's/^- \[[xX]\][[:space:]]+//'
}

# _vea_fetch_details — ONE pass over $SIGNAL_LEDGER_PATH, printing every
# `flip-verdict`/plan-edit-validator row's `.detail` string, one per line
# (jq available) or the raw matching JSONL lines (jq unavailable — same
# degraded-but-correct fallback as before, unified into one fetch site).
# Empty output if the ledger is missing. A caller processing MANY tasks
# (--plan, --sweep) MUST call this exactly ONCE and pass the result into
# _vea_ledger_has_event's optional 3rd argument — see that function's own
# header for why: re-parsing the whole ledger per task does not scale.
_vea_fetch_details() {
  [[ -f "$SIGNAL_LEDGER_PATH" ]] || return 0
  if command -v jq >/dev/null 2>&1; then
    jq -r 'select(.event=="flip-verdict" and .gate=="plan-edit-validator") | .detail' "$SIGNAL_LEDGER_PATH" 2>/dev/null
  else
    grep -F '"event":"flip-verdict"' "$SIGNAL_LEDGER_PATH" 2>/dev/null
  fi
}

# _vea_ledger_has_event <plan_slug> <task_id> [pre-fetched details] — rc 0
# iff a `flip-verdict` row exists whose detail carries EXACTLY
# "plan=<slug> task=<id> " (fixed-string match — deliberately NOT a regex,
# so a dotted task id like "3.2" can never be misread as a wildcard-any-
# char pattern). Also tries the T/t-normalized form of task_id, since the
# checked box and the ledger row could in principle differ by exactly that
# one leading letter (the same T7-incident class every other reader in this
# repo defends against).
#
# PERFORMANCE (measured 2026-08-04): this repo's real
# $HOME/.claude/state/signal-ledger.jsonl is 17MB+ (years of block/warn/
# waiver/... rows from every gate, not just flip-verdict) — re-running
# _vea_fetch_details for EVERY checked task across a 254-file docs/plans/
# sweep (many hundreds of tasks) did not finish in a reasonable time. The
# optional 3rd arg lets --plan/--sweep fetch ONCE and reuse the same
# pre-filtered (much smaller) string for every task; --task (a single
# lookup) omits it and fetches fresh, which stays correct and simple for
# that one-shot case.
_vea_ledger_has_event() {
  local slug="$1" tid="$2" details
  if [[ $# -ge 3 ]]; then
    details="$3"
  else
    details="$(_vea_fetch_details)"
  fi
  [[ -n "$details" ]] || return 1
  local norm_tid; norm_tid="$(_vea_norm_task_id "$tid")"
  local needle1="plan=${slug} task=${tid} " needle2="plan=${slug} task=${norm_tid} "
  grep -F "$needle1" <<<"$details" >/dev/null 2>&1 && return 0
  if [[ "$norm_tid" != "$tid" ]]; then
    grep -F "$needle2" <<<"$details" >/dev/null 2>&1 && return 0
  fi
  return 1
}

_vea_cmd_task() {
  local plan_file="$1" task_id="$2" slug
  slug="$(basename "$plan_file" .md)"
  if _vea_ledger_has_event "$slug" "$task_id"; then
    echo "HAS_EVENT_ON_RECORD plan=$slug task=$task_id"
    return 0
  fi
  echo "NO_VERIFICATION_EVENT_ON_RECORD plan=$slug task=$task_id"
  return 1
}

_vea_cmd_plan() {
  local plan_file="$1"
  if [[ ! -f "$plan_file" ]]; then
    echo "verify-event-audit: no such plan file: $plan_file" >&2
    return 2
  fi
  local slug; slug="$(basename "$plan_file" .md)"
  local details; details="$(_vea_fetch_details)"
  local total=0 has=0 missing=0 tid
  while IFS= read -r tid; do
    [[ -n "$tid" ]] || continue
    total=$((total+1))
    if _vea_ledger_has_event "$slug" "$tid" "$details"; then
      has=$((has+1))
      printf 'HAS_EVENT_ON_RECORD\t%s\t%s\n' "$plan_file" "$tid"
    else
      missing=$((missing+1))
      printf 'NO_VERIFICATION_EVENT_ON_RECORD\t%s\t%s\n' "$plan_file" "$tid"
    fi
  done < <(_vea_checked_task_ids "$plan_file")
  echo "plan=$slug total_checked=$total has_event=$has no_event=$missing" >&2
  return 0
}

_vea_cmd_sweep() {
  local root="${1:-docs/plans}"
  if [[ ! -d "$root" ]]; then
    echo "verify-event-audit: no such directory: $root" >&2
    return 2
  fi
  local details; details="$(_vea_fetch_details)"
  local total=0 has=0 missing=0 f
  while IFS= read -r f; do
    [[ -f "$f" ]] || continue
    local slug tid
    slug="$(basename "$f" .md)"
    while IFS= read -r tid; do
      [[ -n "$tid" ]] || continue
      total=$((total+1))
      if _vea_ledger_has_event "$slug" "$tid" "$details"; then
        has=$((has+1))
      else
        missing=$((missing+1))
        printf 'NO_VERIFICATION_EVENT_ON_RECORD\t%s\t%s\n' "$f" "$tid"
      fi
    done < <(_vea_checked_task_ids "$f")
  done < <(find "$root" -type f -name '*.md' ! -name '*-evidence.md' 2>/dev/null | LC_ALL=C sort)
  echo "" >&2
  echo "sweep root=$root total_checked=$total has_event=$has no_event=$missing" >&2
  return 0
}

# ============================================================
# --self-test
# ============================================================
if [[ "${BASH_SOURCE[0]:-$0}" == "${0}" ]] && [[ "${1:-}" == "--self-test" ]]; then
  PASSED=0
  FAILED=0
  pass() { PASSED=$((PASSED+1)); echo "  PASS: $1" >&2; }
  fail() { FAILED=$((FAILED+1)); echo "  FAIL: $1" >&2; }

  TMP=$(mktemp -d 2>/dev/null || mktemp -d -t 'veast')
  if [[ -z "$TMP" ]] || [[ ! -d "$TMP" ]]; then
    echo "self-test: could not create tempdir" >&2
    exit 1
  fi
  trap 'rm -rf "$TMP"' EXIT

  export HARNESS_SELFTEST=1
  export _VEA_LEDGER_PATH_EXPLICIT=1
  LEDGER="$TMP/signal-ledger.jsonl"
  export SIGNAL_LEDGER_PATH="$LEDGER"

  _emit_row() { # <plan> <task> <verdict>
    printf '{"ts":"2026-08-04T00:00:00Z","session_id":"selftest","gate":"plan-edit-validator","event":"flip-verdict","detail":"plan=%s task=%s verdict=%s confidence=8 verifier=task-verifier evidence=%s-evidence.md#task=%s"}\n' \
      "$1" "$2" "$3" "$1" "$2" >> "$LEDGER"
  }

  echo "Scenario 1: a checked task WITH a matching flip-verdict event -> HAS_EVENT_ON_RECORD, rc 0"
  rm -f "$LEDGER"
  _emit_row "s1-plan" "SE.4.1" "PASS"
  OUT="$(_vea_cmd_task "docs/plans/s1-plan.md" "SE.4.1")"; RC=$?
  if [[ "$RC" -eq 0 ]] && [[ "$OUT" == *"HAS_EVENT_ON_RECORD"* ]]; then
    pass "matching event reports HAS_EVENT_ON_RECORD (rc 0)"
  else
    fail "expected rc=0 + HAS_EVENT_ON_RECORD, got rc=$RC out=[$OUT]"
  fi

  echo "Scenario 2: a checked task with NO event -> NO_VERIFICATION_EVENT_ON_RECORD, rc 1 (never fabricated)"
  rm -f "$LEDGER"
  OUT="$(_vea_cmd_task "docs/plans/s2-plan.md" "SE.4.2")"; RC=$?
  if [[ "$RC" -eq 1 ]] && [[ "$OUT" == *"NO_VERIFICATION_EVENT_ON_RECORD"* ]]; then
    pass "absent event reports NO_VERIFICATION_EVENT_ON_RECORD (rc 1), not fabricated as either state"
  else
    fail "expected rc=1 + NO_VERIFICATION_EVENT_ON_RECORD, got rc=$RC out=[$OUT]"
  fi

  echo "Scenario 3: --plan sweep counts total/has/missing across a 3-task plan; unchecked tasks are ignored"
  PLAN3="$TMP/docs/plans/s3-plan.md"
  mkdir -p "$(dirname "$PLAN3")"
  printf '# S3 Plan\n\n## Tasks\n\n- [x] 1. Has an event\n- [x] 2. Missing an event\n- [ ] 3. Not checked at all\n' > "$PLAN3"
  rm -f "$LEDGER"
  _emit_row "s3-plan" "1" "PASS"
  SUMMARY="$(_vea_cmd_plan "$PLAN3" 2>&1 1>/dev/null)"
  if [[ "$SUMMARY" == *"total_checked=2"* ]] && [[ "$SUMMARY" == *"has_event=1"* ]] && [[ "$SUMMARY" == *"no_event=1"* ]]; then
    pass "3-task plan (2 checked, 1 unchecked): total_checked=2 has_event=1 no_event=1 (unchecked task 3 correctly excluded)"
  else
    fail "expected total_checked=2 has_event=1 no_event=1, got [$SUMMARY]"
  fi

  echo "Scenario 4: --sweep recurses into archive/ and deferred/ subdirectories and aggregates"
  SWEEP_ROOT="$TMP/docs/plans-sweep"
  mkdir -p "$SWEEP_ROOT/archive" "$SWEEP_ROOT/deferred"
  printf '# Active\n\n## Tasks\n\n- [x] 1. Active task\n' > "$SWEEP_ROOT/active-plan.md"
  printf '# Archived\n\n## Tasks\n\n- [x] 1. Archived task\n' > "$SWEEP_ROOT/archive/archived-plan.md"
  printf '# Deferred\n\n## Tasks\n\n- [x] 1. Deferred task\n' > "$SWEEP_ROOT/deferred/deferred-plan.md"
  rm -f "$LEDGER"
  _emit_row "active-plan" "1" "PASS"
  SWEEP_OUT="$(_vea_cmd_sweep "$SWEEP_ROOT" 2>&1 1>/dev/null)"
  if [[ "$SWEEP_OUT" == *"total_checked=3"* ]] && [[ "$SWEEP_OUT" == *"has_event=1"* ]] && [[ "$SWEEP_OUT" == *"no_event=2"* ]]; then
    pass "sweep across active+archive+deferred finds all 3 checked tasks (total_checked=3 has_event=1 no_event=2)"
  else
    fail "expected total_checked=3 has_event=1 no_event=2, got [$SWEEP_OUT]"
  fi

  echo "Scenario 5: no ledger file at all -> every checked task reports NO_VERIFICATION_EVENT_ON_RECORD, never crashes"
  rm -f "$LEDGER"
  SUMMARY5="$(_vea_cmd_plan "$PLAN3" 2>&1 1>/dev/null)"
  RC5=$?
  if [[ "$RC5" -eq 0 ]] && [[ "$SUMMARY5" == *"has_event=0"* ]] && [[ "$SUMMARY5" == *"no_event=2"* ]]; then
    pass "missing ledger file degrades to all-NO_EVENT, rc 0 (report, not a crash or a gate)"
  else
    fail "expected rc=0 has_event=0 no_event=2, got rc=$RC5 [$SUMMARY5]"
  fi

  echo "Scenario 6: a dotted task id (1.2) queried against a ledger row for a DIFFERENT, same-length id (1X2)"
  echo "must NOT false-match via the regex dot-as-any-char trap (fixed-string match required)"
  rm -f "$LEDGER"
  _emit_row "s6-plan" "1X2" "PASS"
  OUT6="$(_vea_cmd_task "docs/plans/s6-plan.md" "1.2")"; RC6=$?
  if [[ "$RC6" -eq 1 ]] && [[ "$OUT6" == *"NO_VERIFICATION_EVENT_ON_RECORD"* ]]; then
    pass "task 1.2 does not false-match task 1X2's row (fixed-string match, not regex-dot-as-wildcard)"
  else
    fail "expected task 1.2 to NOT match task 1X2's event (a regex '.' would wrongly match 'X'), got rc=$RC6 out=[$OUT6]"
  fi

  echo "Scenario 7: bare-numeric trailing-dot extraction (- [x] 7. Foo -> id '7', not '7.') matches a ledger row keyed on '7'"
  PLAN7="$TMP/docs/plans/s7-plan.md"
  mkdir -p "$(dirname "$PLAN7")"
  printf '# S7 Plan\n\n## Tasks\n\n- [x] 7. Bare numeric id with trailing dot\n' > "$PLAN7"
  rm -f "$LEDGER"
  _emit_row "s7-plan" "7" "PASS"
  OUT7="$(_vea_cmd_task "$PLAN7" "7")"; RC7=$?
  EXTRACTED7="$(_vea_checked_task_ids "$PLAN7")"
  if [[ "$RC7" -eq 0 ]] && [[ "$EXTRACTED7" == "7" ]]; then
    pass "extracted id excludes the sentence-ending dot ('7', not '7.') and matches the ledger row"
  else
    fail "expected extracted id '7' and rc=0, got extracted=[$EXTRACTED7] rc=$RC7 out=[$OUT7]"
  fi

  echo ""
  echo "self-test summary: $PASSED passed, $FAILED failed"
  if [[ "$FAILED" == "0" ]]; then
    exit 0
  else
    exit 1
  fi
fi

# ============================================================
# Dispatch
# ============================================================
case "${1:-}" in
  --task)
    [[ $# -eq 3 ]] || { echo "usage: verify-event-audit.sh --task <plan-file> <task-id>" >&2; exit 2; }
    _vea_cmd_task "$2" "$3"
    exit $?
    ;;
  --plan)
    [[ $# -eq 2 ]] || { echo "usage: verify-event-audit.sh --plan <plan-file>" >&2; exit 2; }
    _vea_cmd_plan "$2"
    exit $?
    ;;
  --sweep)
    _vea_cmd_sweep "${2:-docs/plans}"
    exit $?
    ;;
  *)
    echo "usage: verify-event-audit.sh --task <plan-file> <task-id> | --plan <plan-file> | --sweep [<root-dir>] | --self-test" >&2
    exit 2
    ;;
esac
