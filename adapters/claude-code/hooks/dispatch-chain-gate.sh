#!/bin/bash
# dispatch-chain-gate.sh — G2 (plan -> build), gated-pipeline-master-2026-08
# Task 1 (skeleton: --check + --self-test) + Task 17 (REQ-B8 full form: the
# PreToolUse Task|Agent enforce mode, the subagent_type/attribution logic,
# the grandfather list, and THE THREE-VARIANT D-15 ACCEPTANCE-BAR DEMO).
# Design: docs/designs/gated-pipeline-master-2026-08-03.md Section 4 "G2".
#
# ============================================================
# WIRING (settings.json.template PreToolUse Task|Agent, Task 17)
# ============================================================
# This gate's no-args mode is wired as its OWN "matcher": "Task|Agent" block,
# placed AFTER model-pin-gate.sh's block and BEFORE workstreams-emit.sh
# --on-builder-dispatch's Task|Agent|Workflow block. Order-safe: every
# PreToolUse hook on this matcher (teammate-spawn-validator.sh,
# model-pin-gate.sh, this gate, workstreams-emit.sh) is READ-ONLY on
# tool_input — none rewrites or consumes what another produced, so they
# compose regardless of relative order; the ordering above is chosen only
# so a model-pin block (a usage/config defect) surfaces before a
# chain-validity block (a process defect) when a dispatch trips both, the
# more actionable fix first.
#
# ============================================================
# THE TWO MODES
# ============================================================
#   dispatch-chain-gate.sh --check <plan-file>
#     Ad-hoc pre-flight: validates <plan-file>'s `## Review Chain` block
#     directly via rc_validate_chain, independent of any dispatch event.
#     Task 1 scope, unchanged in shape by Task 17 (still no subagent_type
#     logic, no grandfather list — this mode answers "is THIS plan's chain
#     valid," not "should THIS dispatch proceed").
#
#   dispatch-chain-gate.sh                      (no args — PreToolUse mode)
#     Reads a PreToolUse hook event (Task|Agent) from CLAUDE_TOOL_INPUT or
#     stdin, per design SS4 / REQ-B8:
#       1. tool_name must be Task or Agent (else untouched, rc 0 — the
#          matcher in settings.json.template already scopes this, this is
#          belt-and-suspenders for direct invocation).
#       2. subagent_type is classified BUILD-CATEGORY or not, dynamically,
#          against config/model-policy.json's `category: "build"` agents
#          (today: plan-phase-builder, test-writer) — "regardless of prose"
#          (design H1): an NL-ATTRIBUTION role= field never overrides this.
#       3. NOT build-category -> untouched (rc 0), EXCEPT the M-7 evasion
#          heuristic: a prompt/description/content referencing a
#          `docs/plans/<slug>.md` path from a non-build subagent_type is a
#          possible G2-evasion pattern (a mislabeled dispatch doing build
#          work) — logged via gc_escape_used as a workaround-sensor row,
#          NEVER blocked (measurement only, design's named residual).
#       4. build-category -> a plan slug is derived: an NL-ATTRIBUTION
#          `plan=` field REFINES it (never gates — H1); absent or empty,
#          fall back to the first `docs/plans/<slug>.md` reference anywhere
#          in the joined prompt+description+content. Underivable:
#          plan-phase-builder BLOCKS (that agent exists only for plan
#          work); test-writer WARNs + ledgers (ad-hoc use is legitimate).
#       5. With a slug: resolved against the SESSION CWD's git toplevel
#          (`git rev-parse --show-toplevel`, run with the hook's inherited
#          cwd — NOT this harness's own checkout via nl-paths.sh, which
#          answers a different question). No repo at cwd -> WARN pass
#          (Mi-5), never block.
#       6. CHAIN VALIDATES FIRST (fidelity review F-4, binding): the plan's
#          `## Review Chain` is validated via rc_validate_chain BEFORE any
#          grandfather check, unconditionally. PASS/WARN -> proceed
#          (rc 0). FAIL:
#            - no chain parses at all (`no ## Review Chain section` or
#              `...contains no parseable reviewer entries`) -> THIS is the
#              only condition under which the grandfather list is even
#              consulted (F-4's letter: "applies the grandfather path only
#              when no chain parses"). Listed slug -> LEDGERED WARN naming
#              the retrofit path, proceed. Unlisted -> BLOCK.
#            - chain PRESENT but a rule genuinely fails (stale anchor,
#              never-dispatched reviewer, re-anchor without a fresh
#              record, ...) -> BLOCK unconditionally. Never
#              grandfather-eligible — a plan that HAS a chain block is, by
#              definition, not part of the pre-pipeline legacy population
#              the grandfather list exists for.
#
# Exit codes (PreToolUse mode): 0 = proceed (silently, WARN, or ledgered
# WARN — all three are "proceed" to Claude Code's hook contract), 2 = block
# (matches model-pin-gate.sh's PreToolUse-block convention and this gate's
# own pre-existing --check enforce_code, gc_exit_code "enforce" 2).
#
# Exit codes (--check mode, unchanged from Task 1): 0 = proceed (PASS or
# WARN), 1 = blocked (--check "would-block" reading per
# lib/gate-contract-lib.sh's check-mode contract), 2 = usage error, 3 =
# --self-test failure.

_dcg_dir="$(cd -- "${BASH_SOURCE[0]%/*}" 2>/dev/null && pwd)"
# shellcheck source=./lib/review-chain-lib.sh
source "$_dcg_dir/lib/review-chain-lib.sh"
# shellcheck source=./lib/gate-contract-lib.sh
source "$_dcg_dir/lib/gate-contract-lib.sh"

# ============================================================================
# --- T25 verify-obligation WIP-limit ---
# (gated-pipeline-master-2026-08 Task 25; operator directive 2026-08-03 /
# OD-022. design r3 is NOT amended for this — the frozen-flip clause was not
# triggered; see the plan's own In-flight scope-updates entry for Task 25.)
#
# APPENDED, SELF-CONTAINED ON PURPOSE: Task 17 is concurrently landing G2's
# live PreToolUse enforcement + subagent_type triggering in THIS SAME FILE
# (see the file-header comment above: "the FULL G2 ... is Task 17"). To
# minimize merge conflict with that in-flight work, this block is
# deliberately NOT interleaved into `_dcg_check` or the existing CLI `case`
# statement below — it intercepts its OWN flag before the file's
# pre-existing dispatch logic ever sees it, and calls a function that lives
# on the LEDGER LIB side (review-chain-lib.sh's rc_wip_limit_decision, added
# the same commit as this block — reuses the SAME dispatch-ledger reader
# rule 3 already consumes, per the M-3 "no second implementation" rule)
# rather than re-parsing the ledger here. When Task 17 wires the live
# subagent_type-keyed PreToolUse trigger, its own consult path can call
# `_dcg_check_wip_limit` (defined below) directly — no further edit to this
# block should be needed.
#
# CONTRACT: dispatch-chain-gate.sh --check-wip-limit <plan-file>
#   [--threshold N] [--waive <reason>]
#   Exit 0 (proceed) unless the plan's open verify-obligation count is >=
#   threshold (default 3) AND no verifier dispatch is in flight — see
#   rc_wip_limit_decision's own header (hooks/lib/review-chain-lib.sh) for
#   the full decision. `--waive <reason>` always proceeds (exit 0) but
#   LEDGERS the escape via gate-contract-lib.sh's gc_escape_used (the SAME
#   workaround-sensor ledger every other gate's named-reason waiver already
#   feeds — Task 5's dashboard friction pane reads it), never a silent skip.
#
# EXPECTED FALSE-POSITIVE RATE (constitution §10 calibration requirement;
# text corrected 2026-08-03 harness-review remediation round, C3 — the
# PRIOR wording ("never trips this" for any active verifier dispatch) was
# PROVEN FALSE: rc_verifier_in_flight's actual semantics are STRICT-NEWER —
# a verifier marker whose ts is OLDER than the newest open build still
# leaves the gate BLOCKING, matching rc_open_verify_obligations' own
# self-test OBL4b. "In flight" means dispatched AFTER the newest unverified
# merge, not merely dispatched at some point):
# near-zero BY CONSTRUCTION for a legitimate parallel wave — obligations
# only count as blocking when no verifier was dispatched AFTER the newest
# unverified merge, so a session actively working the verify backlog
# (dispatching a FRESH task-verifier while more builders land) never trips
# this. The remaining FP surface is a plan whose task-verifier dispatches
# never carry a role=verifier NL-ATTRIBUTION header (silently degrades the
# in-flight check to "never in flight", which makes the gate STRICTER,
# never looser — a false BLOCK is recoverable via --waive, so this
# direction of error is the one accepted). Calibrated
# against THIS session's own timeline (docs/plans/gated-pipeline-master-
# 2026-08-evidence.md Task 25): 11 builder-complete rows landed with 0
# verifier-complete rows over several hours before the operator's directive
# — a threshold of 3 would have fired once, long before 11 accumulated.
#
# RETIREMENT CONDITION: retire this block once Stage-2 auto-dispatch
# (design NON-GOALS / REQ-C6, Task 24's admission trigger) supersedes manual
# builder-dispatch WIP management entirely — at that point an orchestrator
# session never accumulates unverified merges to begin with, and this
# consult becomes a dead check on an unreachable state.
# ============================================================================

# _dcg_wip_ledger_escape <plan-slug> <reason> — records a --waive escape via
# the canonical gc_escape_used ledger (never a bespoke ledger file).
_dcg_wip_ledger_escape() {
  local slug="$1" reason="$2"
  gc_escape_used "dispatch-chain-gate-wip-limit" "waiver" "$slug" "$reason" 2>/dev/null || true
}

# _dcg_check_wip_limit <plan-file> [<threshold>] [<waive-reason>] — the WIP-
# limit decision, callable directly by a sourcing caller (e.g. a future
# Task 17 PreToolUse consult) or via the --check-wip-limit CLI entry point
# below. Prints a gc_block (FIX/ESCAPE fields included) on block, a summary
# line otherwise. Return code: 0 proceed, 1 block (same convention as
# _dcg_check).
_dcg_check_wip_limit() {
  local plan="$1" threshold="${2:-3}" waive="${3:-}"
  local slug; slug="$(basename "$plan" .md)"

  # C4 (harness-review remediation round, 2026-08-03 -- PROVEN: a
  # slash-less invocation of this script, e.g. bare `dispatch-chain-
  # gate.sh` with no leading path component, leaves
  # `_dcg_dir="${BASH_SOURCE[0]%/*}"` UNCHANGED (no `/` to strip), so the
  # `cd -- "dispatch-chain-gate.sh"` at file-top tries to cd into a FILE as
  # a directory, fails, and _dcg_dir silently resolves EMPTY -- both
  # `source` calls then target "/lib/*.sh" and fail with no error checking
  # on either. Every rc_*/gc_* call afterward is "command not found",
  # returning a nonzero exit that this function's own `local rc=$?` catches
  # and reports as a legitimate BLOCK (exit 1) -- a self-test asserting
  # "exit 1 = blocked correctly" FALSE-GREENS on a completely non-
  # functioning gate. Guard explicitly: verify the two functions this
  # function depends on actually exist BEFORE calling either.
  if ! declare -F rc_wip_limit_decision >/dev/null 2>&1 || ! declare -F gc_block >/dev/null 2>&1; then
    echo "dispatch-chain-gate --check-wip-limit: FATAL — required libs did not source (rc_wip_limit_decision/gc_block undefined; _dcg_dir='${_dcg_dir:-<empty>}') -- refusing to report a decision that would be meaningless. Re-invoke with a path-qualified script name (e.g. 'bash adapters/claude-code/hooks/dispatch-chain-gate.sh', never a bare slash-less name)." >&2
    return 3
  fi

  if [[ -n "$waive" ]]; then
    _dcg_wip_ledger_escape "$slug" "$waive"
    echo "dispatch-chain-gate --check-wip-limit: $plan -- WAIVED ($waive), ledgered to the workaround-sensor ledger, proceeding" >&2
    return 0
  fi

  rc_wip_limit_decision "$slug" "$threshold"
  local rc=$?
  if [[ "$rc" -eq 0 ]]; then
    echo "dispatch-chain-gate --check-wip-limit: $plan -- $RC_WIP_REASON" >&2
    return 0
  fi

  local tasks_csv=""
  [[ "${#RC_OPEN_OBLIGATIONS[@]}" -gt 0 ]] && tasks_csv="$(IFS=,; echo "${RC_OPEN_OBLIGATIONS[*]}")"
  gc_block \
    "plan '$slug' has ${RC_OPEN_OBLIGATIONS_COUNT} open verify obligation(s) (tasks: $tasks_csv) with no verifier dispatch in flight" \
    "OD-022 (operator directive 2026-08-03): the build->verified transition is mechanical and present-moment -- unverified builder-complete work must not accumulate past $threshold open task(s) on one plan without active verification" \
    "dispatch task-verifier against the open task(s) above before dispatching another builder on this plan, or verify the oldest open tasks first to drop below $threshold -- if you already verified these tasks, check the verifier dispatch carried task= ids in its NL-ATTRIBUTION header (an untagged verifier dispatch can never close a specific task's obligation)" \
    "re-run with --waive '<reason>' to proceed anyway (ledgered to the workaround-sensor ledger via gc_escape_used, named reason required)" \
    >&2
  return 1
}

if [[ "${BASH_SOURCE[0]:-$0}" == "${0}" ]] && [[ "${1:-}" == "--check-wip-limit" ]]; then
  if [[ -z "${2:-}" ]]; then
    echo "usage: dispatch-chain-gate.sh --check-wip-limit <plan-file> [--threshold N] [--waive <reason>]" >&2
    exit 2
  fi
  _dcg_wl_plan="$2"; shift 2
  _dcg_wl_threshold=3
  _dcg_wl_waive=""
  # C2 fix (harness-review remediation round, 2026-08-03 -- PROVEN via
  # isolated reproduction: bash's `shift N` silently no-ops, does NOT error
  # and does NOT decrement $#, when N exceeds the remaining positional
  # count. A trailing valueless `--threshold`/`--waive` (no value token
  # after it) left `shift 2` unable to shift, so `$1` never changed and
  # this loop spun forever on the SAME arg -- a genuine hang, not a
  # theoretical one. Arity-checked before every `shift 2` now: a missing
  # value is a usage error (exit 2), never a silent hang.
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --threshold)
        [[ -n "${2:-}" ]] || { echo "usage: dispatch-chain-gate.sh --check-wip-limit <plan-file> [--threshold N] [--waive <reason>] -- --threshold requires a value" >&2; exit 2; }
        _dcg_wl_threshold="$2"; shift 2 ;;
      --waive)
        [[ -n "${2:-}" ]] || { echo "usage: dispatch-chain-gate.sh --check-wip-limit <plan-file> [--threshold N] [--waive <reason>] -- --waive requires a value" >&2; exit 2; }
        _dcg_wl_waive="$2"; shift 2 ;;
      *) shift ;;
    esac
  done
  _dcg_check_wip_limit "$_dcg_wl_plan" "$_dcg_wl_threshold" "$_dcg_wl_waive"
  _dcg_wl_rc=$?
  # C4: propagate rc=3 (broken lib sourcing) DISTINCTLY from rc=1 (a real
  # WIP-limit block) — collapsing both to exit 1 is exactly the false-green
  # this fix exists to close.
  case "$_dcg_wl_rc" in
    0) exit 0 ;;
    3) exit 3 ;;
    *) exit 1 ;;
  esac
fi

if [[ "${BASH_SOURCE[0]:-$0}" == "${0}" ]] && [[ "${1:-}" == "--self-test-wip-limit" ]]; then
  # Run ALONGSIDE the existing --self-test (not merged into it) — see the
  # block header above for why (T17 conflict minimization). A full
  # verification pass for this file runs BOTH:
  #   bash dispatch-chain-gate.sh --self-test
  #   bash dispatch-chain-gate.sh --self-test-wip-limit
  #
  # C4 (harness-review remediation round, 2026-08-03): guard THIS
  # process's own lib sourcing before running anything — see
  # _dcg_check_wip_limit's matching guard for the full false-green
  # rationale. This process calls rc_wip_limit_decision directly nowhere,
  # but a broken _dcg_dir here means every subprocess this suite spawns
  # (`bash "$0" --check-wip-limit ...`) is ALSO broken identically, so
  # failing loud here — before spending time on 10 scenarios that would
  # all report misleading PASS/FAIL noise — is strictly more honest.
  if ! declare -F rc_wip_limit_decision >/dev/null 2>&1 || ! declare -F gc_block >/dev/null 2>&1; then
    echo "self-test-wip-limit: FATAL — required libs did not source (rc_wip_limit_decision/gc_block undefined; _dcg_dir='${_dcg_dir:-<empty>}'). Re-invoke with a path-qualified script name." >&2
    exit 3
  fi
  WL_PASSED=0
  WL_FAILED=0
  _wlst() { # <label> <expected> <actual>
    if [[ "$2" == "$3" ]]; then
      echo "self-test-wip-limit ($1): PASS" >&2
      WL_PASSED=$((WL_PASSED + 1))
    else
      echo "self-test-wip-limit ($1): FAIL (expected '$2', got '$3')" >&2
      WL_FAILED=$((WL_FAILED + 1))
    fi
  }

  WLT="$(mktemp -d)" || { echo "self-test-wip-limit: mktemp failed" >&2; exit 3; }
  trap 'rm -rf "$WLT" 2>/dev/null || true' EXIT
  WL_LEDGER="$WLT/ledger.jsonl"
  WL_PLAN="$WLT/docs-plans/wip-fixture.md"
  mkdir -p "$(dirname "$WL_PLAN")"
  echo "# WIP fixture plan" > "$WL_PLAN"
  export RC_LEDGER_PATH="$WL_LEDGER"
  export DISPATCH_PROVENANCE_STATE_DIR="$WLT/dispatch-provenance"
  mkdir -p "$DISPATCH_PROVENANCE_STATE_DIR"

  _wl_row() { # <subagent_type> <ts> <task_id>
    printf '{"subagent_type":"%s","model":"claude-fable-5","ts":%s,"session_id":"selftest","artifact_ref":"docs/plans/wip-fixture.md","task_id":"%s"}\n' \
      "$1" "$2" "$3" >> "$WL_LEDGER"
  }

  # ---- GOLDEN SCENARIO (§10 evidence bar item 1): 3 builder-complete rows,
  # no verifier rows -> BLOCKS a 4th builder dispatch, naming the open
  # obligations. ----
  : > "$WL_LEDGER"
  _wl_row "plan-phase-builder" 1000 "5"
  _wl_row "plan-phase-builder" 1001 "6"
  _wl_row "plan-phase-builder" 1002 "7"
  WL_OUT="$(bash "$0" --check-wip-limit "$WL_PLAN" 2>&1)"
  WL_RC=$?
  _wlst "golden-3-open-no-verifier-blocks-exit1" "1" "$WL_RC"
  WL_NAMES_ALL=1
  for t in 5 6 7; do printf '%s' "$WL_OUT" | grep -q "$t" || WL_NAMES_ALL=0; done
  _wlst "golden-block-names-all-open-tasks" "1" "$WL_NAMES_ALL"
  for marker in "[GATE:WHAT]" "[GATE:WHY]" "[GATE:FIX]" "[GATE:ESCAPE]"; do
    WL_MC=$(printf '%s' "$WL_OUT" | grep -c -F "$marker")
    _wlst "golden-block-has-$marker" "1" "$WL_MC"
  done

  # ---- GOLDEN SCENARIO continued: add verifier rows for each open task ->
  # dispatch passes (exit 0). ----
  _wl_row "task-verifier" 2000 "5"
  _wl_row "task-verifier" 2001 "6"
  _wl_row "task-verifier" 2002 "7"
  WL_OUT2="$(bash "$0" --check-wip-limit "$WL_PLAN" 2>&1)"
  WL_RC2=$?
  _wlst "golden-after-verify-rows-passes-exit0" "0" "$WL_RC2"

  # ---- Below-threshold (2 open, default threshold 3) -> proceeds. ----
  : > "$WL_LEDGER"
  _wl_row "plan-phase-builder" 1000 "1"
  _wl_row "plan-phase-builder" 1001 "2"
  bash "$0" --check-wip-limit "$WL_PLAN" >/dev/null 2>&1
  _wlst "below-threshold-proceeds-exit0" "0" "$?"

  # ---- --waive always proceeds and ledgers the escape. ----
  : > "$WL_LEDGER"
  _wl_row "plan-phase-builder" 1000 "1"
  _wl_row "plan-phase-builder" 1001 "2"
  _wl_row "plan-phase-builder" 1002 "3"
  export HARNESS_SELFTEST=1
  export WORKAROUND_SENSOR_LEDGER_PATH="$WLT/workaround-ledger.jsonl"
  bash "$0" --check-wip-limit "$WL_PLAN" --waive "operator-approved parallel wave" >/dev/null 2>&1
  _wlst "waive-proceeds-exit0" "0" "$?"
  WL_WAIVED=0
  grep -q '"bypass_kind":"waiver"' "$WORKAROUND_SENSOR_LEDGER_PATH" 2>/dev/null && WL_WAIVED=1
  _wlst "waive-ledgered-to-workaround-sensor" "1" "$WL_WAIVED"
  unset WORKAROUND_SENSOR_LEDGER_PATH HARNESS_SELFTEST

  echo "self-test-wip-limit summary: $WL_PASSED passed, $WL_FAILED failed (of $((WL_PASSED + WL_FAILED)) scenarios)" >&2
  if [[ "$WL_FAILED" -eq 0 ]]; then
    exit 0
  else
    exit 1
  fi
fi
# --- end T25 verify-obligation WIP-limit block ---
# ============================================================================

# ============================================================
# Config resolution (script-location-relative, like model-pin-gate.sh's
# agents_dir — NOT session-cwd-relative and NOT nl-paths.sh's
# nl_repo_root(), which answers "where is THIS harness checked out," a
# different question from "what repo is the dispatching session sitting
# in" (SS5 below uses THAT one). A gate's own config always travels with
# the gate's own installed location, regardless of which repo/cwd a given
# dispatch happens to fire from.)
# ============================================================

# _dcg_build_types — stdout: one build-category subagent_type per line,
# read from config/model-policy.json's `category: "build"` agents (design
# H1: "any build-category agent type per model-policy.json ... is a
# builder dispatch regardless of prose" — NOT a hardcoded
# plan-phase-builder/test-writer pair, so a future third build-category
# agent is covered without an edit here).
_dcg_build_types() {
  local file="${DCG_MODEL_POLICY_PATH:-$_dcg_dir/../config/model-policy.json}"
  [[ -f "$file" ]] || return 0
  jq -r '.agents | to_entries[] | select(.value.category=="build") | .key' "$file" 2>/dev/null
}

# _dcg_is_build_type <subagent_type> — rc 0 iff listed by _dcg_build_types.
# CRLF-safe (same convention as model-pin-gate.sh's frontmatter readers):
# model-policy.json's jq output was observed carrying a trailing \r per line
# on this platform (Windows source checkout), which `read -r` does NOT
# strip (only `\n` is stripped) — an un-stripped "plan-phase-builder\r"
# never equals "plan-phase-builder" and silently mis-classifies every
# build-category dispatch as non-build. Caught live in this task's own
# self-test (demo variants i/ii/iii all fell through to the M-7 branch
# instead of blocking, before this strip was added).
_dcg_is_build_type() {
  local atype="$1" bt
  [[ -n "$atype" ]] || return 1
  while IFS= read -r bt; do
    bt="${bt%$'\r'}"
    [[ -n "$bt" ]] || continue
    [[ "$bt" == "$atype" ]] && return 0
  done < <(_dcg_build_types)
  return 1
}

# _dcg_grandfathered <slug> — rc 0 iff sha256(<slug>) is a non-comment,
# non-blank line in the grandfather list (config/g2-grandfather-slugs.txt,
# generated once at G2's install per that file's own header — "the slug
# list IS the mechanism," design C-2). Entries are OPAQUE sha256 hex, not
# plaintext slugs: the machine-wide population includes other repos' plan
# slugs, and plaintext would ship product/identity strings inside the
# harness repo (constitution §9 / harness-hygiene denylist — caught live
# at the T17 merge train, 2026-08-03).
_dcg_grandfathered() {
  local slug="$1" file="${DCG_GRANDFATHER_PATH:-$_dcg_dir/../config/g2-grandfather-slugs.txt}"
  [[ -n "$slug" && -f "$file" ]] || return 1
  local h; h="$(printf '%s' "$slug" | sha256sum 2>/dev/null | cut -d' ' -f1)"
  [[ -n "$h" ]] || return 1
  grep -vE '^[[:space:]]*(#|$)' "$file" 2>/dev/null | grep -qxF "$h"
}

# ============================================================
# Dispatch-text parsing (PreToolUse mode)
# ============================================================

# _dcg_extract_plan_ref <text> — first `docs/plans/<slug>.md` reference
# anywhere in <text>, or empty. Same regex vocabulary
# workstreams-emit.sh's _extract_plan_slug uses (shared contract, REQ-B14's
# "extend, don't add" spirit applied to a second consumer of the same
# convention rather than a second parser).
_dcg_extract_plan_ref() {
  printf '%s' "$1" | grep -oE 'docs/plans/[A-Za-z0-9_.-]+\.md' | head -n1
}

# _dcg_extract_plan_slug <text> — the ref above, minus `docs/plans/` and
# `.md`. Empty if no ref found.
_dcg_extract_plan_slug() {
  local ref slug
  ref="$(_dcg_extract_plan_ref "$1")"
  [[ -z "$ref" ]] && { printf ''; return 0; }
  slug="${ref#docs/plans/}"
  slug="${slug%.md}"
  printf '%s' "$slug"
}

# _dcg_attributed_slug <text> — the NL-ATTRIBUTION `plan=` field, parsed
# with the EXACT anchor semantics workstreams-emit.sh's
# _extract_nl_attribution carries as of the T15/REQ-B14 quoted-header fix
# (workstreams-emit.sh:3533-3676, "share the fixed parse semantics with
# workstreams-emit" per this task's own brief): the header must start a
# line (COLUMN 0, no leading whitespace) within the first
# NL_ATTRIBUTION_MAX_LINE (default 5) lines of <text>, AND the line
# immediately preceding it (within that window) must not open/continue a
# markdown fence (``` or ~~~) — a quoted header in a handoff/review prompt
# must never forge attribution here either.
#
# THIS IS A REIMPLEMENTATION, NOT A SOURCE, of that function. Verified
# live before writing this: workstreams-emit.sh has NO direct-execution
# guard around its bottom `case "$MODE" in ... esac` dispatch, so sourcing
# it terminates the sourcing shell —
#   bash -c 'source adapters/claude-code/hooks/workstreams-emit.sh; echo x'
# prints NOTHING (the unknown/empty-MODE branch's own `exit 0` fires
# first, killing this gate's process before "echo x" — or any of this
# gate's own remaining logic — ever runs). Reimplementing here is the only
# safe option; the two copies are kept adjacent in comment form (this
# block cites the origin's exact line range above) so a future edit to
# either anchor rule is a visible two-file diff, never a silent drift —
# the same intent the M-3 "one lib" rule serves where the origin function
# actually lives in a sourceable lib, extended to a case it cannot reach
# because the origin lives inside a non-sourceable hook script instead.
_dcg_attributed_slug() {
  local text="$1" maxln=5
  local fence_re='^[[:space:]]*(```|~~~)'
  local line="" prevline="" candidate lineno=0
  while IFS= read -r candidate; do
    lineno=$((lineno + 1))
    [[ "$lineno" -gt "$maxln" ]] && break
    if [[ -z "$line" && "$candidate" =~ ^NL-ATTRIBUTION: ]]; then
      if [[ "$prevline" =~ $fence_re ]]; then
        : # fence-preceded -- quoted content, not a live dispatch. Keep scanning.
      else
        line="$candidate"
      fi
    fi
    prevline="$candidate"
  done <<< "$text"
  [[ -z "$line" ]] && { printf ''; return 0; }
  local plan
  plan=$(printf '%s' "$line" | grep -oE 'plan=[A-Za-z0-9_.-]+' | head -n1)
  printf '%s' "${plan#plan=}"
}

# ============================================================
# Shared chain-verdict-to-block-message mapping (--check AND PreToolUse
# both reach this — ONE decision, not two that can drift; the same reason
# gate-contract-lib.sh's own header gives for its four-field convention).
# Assumes RC_VERDICT/RC_REASON/RC_DETAIL_LINES are already set by a prior
# rc_validate_chain call.
# ============================================================

# _dcg_chain_unparsed — rc 0 iff RC_REASON indicates NO chain block parsed
# at all (no `## Review Chain` section, or a section with zero reviewer
# entries) — the ONLY condition under which F-4 permits the grandfather
# path. rc 1 for every other FAIL reason (a chain that parses but fails a
# rule) — never grandfather-eligible.
_dcg_chain_unparsed() {
  case "$RC_REASON" in
    "no ## Review Chain section"*) return 0 ;;
    "## Review Chain section present but contains no parseable reviewer entries"*) return 0 ;;
    *) return 1 ;;
  esac
}

# _dcg_chain_fail_fields <plan> — prints the gc_block four fields (+ the
# detail dump) for a FAIL verdict, wording adapted per _dcg_chain_unparsed.
_dcg_chain_fail_fields() {
  local plan="$1" what why fix escape
  if _dcg_chain_unparsed; then
    what="$plan has no ## Review Chain block"
    why="G2 (plan -> build) requires mechanical proof the design/plan reviews ran before a builder dispatches against this plan (D-15's acceptance bar; design docs/designs/gated-pipeline-master-2026-08-03.md SS4)"
    fix="dispatch the required reviewers (plan-fidelity-reviewer at minimum; design-author's reviewers too if design-ref is required), then add a ## Review Chain block naming each reviewer/verdict/record — schema in design SS4"
    escape="none for a new plan — a legacy plan predating this gate is exempted only via the install-generated grandfather slug list (config/g2-grandfather-slugs.txt), never by this flag"
  else
    what="$plan's Review Chain fails validity: $RC_REASON"
    why="review-chain-lib.sh's rc_validate_chain found at least one entry that does not satisfy the three validity rules (record parse / three-way anchor match / dispatch-ledger cross-check) — design SS4"
    fix="re-dispatch the named reviewer against the current bytes and commit its record (rule 1/3), or restore the chain's anchor to a blob a real record actually attests (rule 2) — see the full detail below"
    escape="none — a chain entry that fails validity cannot be waived by editing the plan file; escalate to the plan's owner"
  fi
  gc_block "$what" "$why" "$fix" "$escape"
  echo "-- detail --"
  printf '%s\n' "${RC_DETAIL_LINES[@]}"
}

# ============================================================
# --check <plan-file> (Task 1 mode, unchanged shape)
# ============================================================

_dcg_check() {
  local plan="$1" mode
  mode="$(gc_mode --check)"

  if [[ ! -f "$plan" ]]; then
    echo "$(gc_header 'dispatch-chain-gate: plan file not found' "$mode")" >&2
    gc_block \
      "no such file: $plan" \
      "G2 validates a plan's Review Chain block; the named file does not exist so there is nothing to validate" \
      "pass the plan's real path (relative to the repo root or absolute)" \
      "none — this is a usage error, not a chain-validity decision" \
      >&2
    return 1
  fi

  rc_validate_chain "$plan"

  if [[ "$RC_VERDICT" == "FAIL" ]]; then
    echo "$(gc_header 'dispatch-chain-gate: Review Chain validation failed' "$mode")" >&2
    _dcg_chain_fail_fields "$plan" >&2
    return 1
  fi

  if [[ "$RC_VERDICT" == "WARN" ]]; then
    echo "dispatch-chain-gate: $plan — Review Chain WARN (proceeding): $RC_REASON" >&2
    printf '%s\n' "${RC_DETAIL_LINES[@]}" >&2
  else
    echo "dispatch-chain-gate: $plan — Review Chain valid, all entries PASS" >&2
  fi
  return 0
}

# ============================================================
# PreToolUse enforce mode (Task 17 / REQ-B8)
# ============================================================

_dcg_gate() {
  local input
  input="${CLAUDE_TOOL_INPUT:-}"
  [[ -z "$input" ]] && input="$(cat 2>/dev/null || true)"
  [[ -z "$input" ]] && return 0 # nothing to inspect -> fail-open

  if ! command -v jq >/dev/null 2>&1; then
    echo "dispatch-chain-gate: WARN — jq not found, G2 cannot inspect this dispatch (fail-open, per design's Behavioral Contracts: never fail-closed on an internal limitation)" >&2
    return 0
  fi

  local tool
  tool="$(printf '%s' "$input" | jq -r '.tool_name // ""' 2>/dev/null || true)"
  case "$tool" in Task | Agent) ;; *) return 0 ;; esac # matcher already scopes this; belt-and-suspenders

  # Same extraction pattern as model-pin-gate.sh:156-167 (subagent_type
  # falls back to agentType; this hook only needs subagent_type, but keeps
  # the fallback so the two gates classify the SAME dispatch identically).
  local atype
  atype="$(printf '%s' "$input" | jq -r '.tool_input.subagent_type // .tool_input.agentType // ""' 2>/dev/null || true)"

  local text
  text="$(printf '%s' "$input" | jq -r '[(.tool_input.prompt // ""),(.tool_input.description // ""),(.tool_input.content // "")] | join("\n")' 2>/dev/null || true)"

  if ! _dcg_is_build_type "$atype"; then
    # M-7 evasion heuristic (design SS4 named residual): a non-build
    # subagent_type whose dispatch text references a docs/plans/ path is a
    # POSSIBLE role-mislabeled build dispatch dodging G2's subagent_type
    # keying. Measured, never blocked — research-type dispatches with no
    # such reference are fully untouched (no ledger row, no output).
    local ref
    ref="$(_dcg_extract_plan_ref "$text")"
    if [[ -n "$ref" ]]; then
      gc_escape_used "dispatch-chain-gate" "role-mislabeled-build-reference" "${atype:-<none>}:${ref}" \
        "M-7 evasion heuristic: non-build subagent_type='${atype:-<none>}' dispatch prompt/description references ${ref} — G2 only inspects build-category subagent_types (config/model-policy.json); recorded as a possible evasion pattern, never blocked" >/dev/null 2>&1
      echo "dispatch-chain-gate: WARN — non-build dispatch (subagent_type=${atype:-<none>}) references ${ref}; recorded (M-7 evasion heuristic), never blocked" >&2
    fi
    return 0
  fi

  # subagent_type IS build-category (plan-phase-builder, test-writer, ...).
  local slug
  slug="$(_dcg_attributed_slug "$text")"
  [[ -z "$slug" ]] && slug="$(_dcg_extract_plan_slug "$text")"

  if [[ -z "$slug" ]]; then
    if [[ "$atype" == "plan-phase-builder" ]]; then
      echo "$(gc_header 'dispatch-chain-gate: plan-phase-builder dispatch with no derivable plan slug' 'enforce')" >&2
      gc_block \
        "this ${tool} dispatch (subagent_type=plan-phase-builder) carries no derivable docs/plans/<slug>.md reference — no NL-ATTRIBUTION plan= field and no docs/plans/ path anywhere in prompt/description/content" \
        "plan-phase-builder exists only for plan work (design docs/designs/gated-pipeline-master-2026-08-03.md SS4 G2); a dispatch of this type must name the plan it is building" \
        "add an NL-ATTRIBUTION: plan=<slug> task=<id> role=builder header (doctrine/orchestrator-pattern.md) or reference docs/plans/<slug>.md directly in the prompt" \
        "none — a plan-phase-builder dispatch always names a plan; there is no legitimate ad-hoc use of this agent type" \
        >&2
      return 2
    fi
    gc_escape_used "dispatch-chain-gate" "underivable-slug" "$atype" \
      "test-writer dispatch with no derivable plan slug — ad-hoc use is legitimate (design SS4 G2); ledgered, never blocked" >/dev/null 2>&1
    echo "dispatch-chain-gate: WARN — test-writer dispatch with no derivable plan slug; ad-hoc use is legitimate, proceeding (ledgered)" >&2
    return 0
  fi

  # Slug resolved — anchor against the SESSION CWD's git toplevel (design
  # SS4: "resolved against the session cwd's git toplevel"), NOT this
  # harness's own checkout (nl-paths.sh answers a different question).
  local toplevel
  toplevel="$(git rev-parse --show-toplevel 2>/dev/null)"
  if [[ -z "$toplevel" ]]; then
    echo "dispatch-chain-gate: WARN — session cwd is not inside a git repo; cannot resolve docs/plans/$slug.md (Mi-5), proceeding" >&2
    return 0
  fi

  # cd into the toplevel and pass a REPO-ROOT-RELATIVE plan path from here
  # on — not an absolute one. rc_validate_chain uses its OWN argument
  # verbatim as rule 3's artifact_ref (review-chain-lib.sh: `artifact_ref="$plan"`
  # in the plan-role branch), and the REAL ledger writer
  # (workstreams-emit.sh's _extract_artifact_ref) always reconstructs
  # `docs/plans/<slug>.md` as a repo-root-relative string (it is built from
  # a regex match over dispatch-prompt text, which by convention is always
  # written relative — never an absolute filesystem path). An absolute
  # $plan_file here would never equal a real ledger row's artifact_ref,
  # so every genuinely valid chain would spuriously fail rule 3 — caught
  # live by this task's own self-test (the "valid-chain plan -> silent
  # pass" scenario BLOCKED until this fix, rule3 reporting "no
  # dispatch-ledger row ... artifact_ref=<absolute path>").
  cd "$toplevel" 2>/dev/null || {
    echo "dispatch-chain-gate: WARN — could not cd into resolved toplevel $toplevel; proceeding" >&2
    return 0
  }
  local plan_file="docs/plans/$slug.md"

  # F-4 (fidelity review, binding order): CHAIN VALIDATES FIRST.
  # Grandfather is consulted ONLY when rc_validate_chain reports NO chain
  # parses at all. A chain that parses but fails a rule BLOCKS
  # unconditionally, never rescued by the grandfather list.
  rc_validate_chain "$plan_file"

  case "$RC_VERDICT" in
    PASS)
      echo "dispatch-chain-gate: $plan_file — Review Chain valid, dispatch proceeds (subagent_type=$atype)" >&2
      # T25 / OD-022 WIP-limit consult (harness-review remediation round,
      # 2026-08-03, C1): placement HERE — inside the build-category branch,
      # after the chain already validated — means only a genuine BUILDER
      # dispatch (this branch is unreachable for task-verifier, a "review"
      # category type per model-policy.json, so remedy verifier dispatches
      # are never blockable by this consult) can trip the WIP limit.
      # C4: rc=3 (broken lib sourcing) fails OPEN here, never blocks a real
      # dispatch on an internal tooling failure — matches this design's own
      # Behavioral Contract ("never fail-closed on an internal error"); only
      # rc=1 (a genuine WIP-limit decision) blocks.
      _dcg_wip_rc=0; _dcg_check_wip_limit "$plan_file" || _dcg_wip_rc=$?
      if [[ "$_dcg_wip_rc" -eq 3 ]]; then
        echo "dispatch-chain-gate: WARN — WIP-limit consult could not run (lib sourcing broken); proceeding (fail-open, never fail-closed on an internal error)" >&2
      elif [[ "$_dcg_wip_rc" -ne 0 ]]; then
        return 2
      fi
      return 0
      ;;
    WARN)
      echo "dispatch-chain-gate: $plan_file — Review Chain WARN (proceeding): $RC_REASON" >&2
      printf '%s\n' "${RC_DETAIL_LINES[@]}" >&2
      _dcg_wip_rc=0; _dcg_check_wip_limit "$plan_file" || _dcg_wip_rc=$?
      if [[ "$_dcg_wip_rc" -eq 3 ]]; then
        echo "dispatch-chain-gate: WARN — WIP-limit consult could not run (lib sourcing broken); proceeding (fail-open, never fail-closed on an internal error)" >&2
      elif [[ "$_dcg_wip_rc" -ne 0 ]]; then
        return 2
      fi
      return 0
      ;;
  esac

  # RC_VERDICT == FAIL
  if _dcg_chain_unparsed; then
    if _dcg_grandfathered "$slug"; then
      gc_escape_used "dispatch-chain-gate" "grandfather" "$slug" \
        "legacy plan predates G2 (install-generated grandfather list, config/g2-grandfather-slugs.txt); retrofit path: dispatch plan-fidelity-reviewer (+ design-author's reviewers if design-ref is required) against $plan_file and add a ## Review Chain block per design SS4; retired by REQ-C2's estate drain" >/dev/null 2>&1
      echo "dispatch-chain-gate: $plan_file — no Review Chain (grandfathered legacy plan slug='$slug', LEDGERED WARN), dispatch proceeds. Retrofit: dispatch plan-fidelity-reviewer against this plan and add a ## Review Chain block (docs/designs/gated-pipeline-master-2026-08-03.md SS4)." >&2
      return 0
    fi
    echo "$(gc_header "dispatch-chain-gate: ${atype} dispatch BLOCKED — $plan_file has no Review Chain" 'enforce')" >&2
    _dcg_chain_fail_fields "$plan_file" >&2
    return 2
  fi

  echo "$(gc_header "dispatch-chain-gate: ${atype} dispatch BLOCKED — $plan_file's Review Chain fails validity" 'enforce')" >&2
  _dcg_chain_fail_fields "$plan_file" >&2
  return 2
}

_dcg_usage() {
  cat >&2 <<'EOF'
usage: dispatch-chain-gate.sh --check <plan-file>
       dispatch-chain-gate.sh --self-test
       dispatch-chain-gate.sh                 (no args — PreToolUse mode,
                                                 reads a Task|Agent dispatch
                                                 event from CLAUDE_TOOL_INPUT
                                                 or stdin)
EOF
}

# ============================================================
# --self-test
# ============================================================
if [[ "${BASH_SOURCE[0]:-$0}" == "${0}" ]] && [[ "${1:-}" == "--self-test" ]]; then
  FIXDIR="$_dcg_dir/../tests/fixtures/review-chain"
  PASSED=0
  FAILED=0
  _st() { # <label> <expected> <actual>
    if [[ "$2" == "$3" ]]; then
      echo "self-test ($1): PASS" >&2
      PASSED=$((PASSED + 1))
    else
      echo "self-test ($1): FAIL (expected '$2', got '$3')" >&2
      FAILED=$((FAILED + 1))
    fi
  }

  if [[ ! -f "$FIXDIR/chainless-plan.md" || ! -f "$FIXDIR/valid-chain-plan.md" ]]; then
    echo "self-test: fixtures missing under $FIXDIR (expected chainless-plan.md + valid-chain-plan.md)" >&2
    exit 3
  fi

  # ---- Task 1 --check scenarios (unchanged) --------------------------------
  OUT="$(bash "$0" --check "$FIXDIR/chainless-plan.md" 2>&1)"
  RC=$?
  _st "chainless-exit-nonzero" "1" "$RC"
  for marker in "[GATE:WHAT]" "[GATE:WHY]" "[GATE:FIX]" "[GATE:ESCAPE]"; do
    C=$(printf '%s\n' "$OUT" | grep -c -F "$marker")
    _st "chainless-has-$marker" "1" "$C"
  done

  # Run from the repo root so the fixture's own committed HEAD blobs and
  # ledger-fixture-relative paths resolve exactly as they will for a real
  # invocation (dispatch-chain-gate.sh --check is always run with cwd = repo
  # root by its caller — the hook/session convention, not a self-test-only
  # assumption).
  REPO_ROOT="$(cd -- "$_dcg_dir/../../.." 2>/dev/null && pwd)"
  RC_LEDGER_PATH="$FIXDIR/dispatch-ledger.jsonl"
  export RC_LEDGER_PATH
  OUT="$(cd "$REPO_ROOT" && RC_LEDGER_PATH="$REPO_ROOT/adapters/claude-code/tests/fixtures/review-chain/dispatch-ledger.jsonl" bash "$_dcg_dir/dispatch-chain-gate.sh" --check "adapters/claude-code/tests/fixtures/review-chain/valid-chain-plan.md" 2>&1)"
  RC=$?
  _st "valid-chain-exit-zero" "0" "$RC"

  # ============================================================
  # Task 17 / REQ-B8 — PreToolUse mode: THE THREE-VARIANT D-15 DEMO plus the
  # full branch coverage (grandfather, underivable-slug per role, no-repo,
  # M-7 heuristic, non-build untouched). Built against a THROWAWAY git repo
  # (mktemp -d; git init — the review-chain-lib.sh --self-test convention)
  # so this never touches the real repo's docs/plans/ or the real machine's
  # dispatch ledger / workaround-sensor ledger. Every gc_escape_used call in
  # this section is sandboxed via HARNESS_SELFTEST=1 +
  # WORKAROUND_SENSOR_LEDGER_PATH (gate-contract-lib.sh's own self-test
  # convention) for the SAME reason.
  # ============================================================
  G2T=$(mktemp -d) || { echo "self-test: mktemp failed (PreToolUse section)" >&2; exit 3; }
  trap 'rm -rf "$G2T" 2>/dev/null || true' EXIT
  export HARNESS_SELFTEST=1
  export WORKAROUND_SENSOR_LEDGER_PATH="$G2T/workaround-sensor.jsonl"

  G2R="$G2T/repo"
  git init -q -b master "$G2R" >/dev/null 2>&1
  (
    cd "$G2R" || exit 1
    git config user.email g2@example.com
    git config user.name g2
    git config core.autocrlf false
    mkdir -p docs/plans docs/reviews
  )

  _g_write_plan() { # <path> <reviewer> <verdict> <record> <planblob-or-placeholder>
    {
      echo "# G2 PreToolUse self-test fixture plan"
      echo "Status: ACTIVE"
      echo
      echo "## Review Chain"
      echo "plan-reviews:"
      echo "  - reviewer: $2  verdict: $3  record: $4  plan-blob: $5"
      echo
      echo "## Goal"
      echo "G2 self-test fixture — not a real build plan."
    } >"$1"
  }
  _g_write_record() { # <path> <reviewer-line> <reviewed-path> <reviewed-blob> <verdict>
    {
      echo "# G2 PreToolUse self-test fixture record"
      echo "**Reviewer:** $2"
      echo "**Reviewed:** $3 @ $4"
      echo "**Reviewed at:** 2026-08-03"
      echo
      echo "## Verdict: $5"
    } >"$1"
  }
  _g_ledger_row() { # <subagent_type> <ts> <artifact_ref> <ledger-file>
    printf '{"subagent_type":"%s","model":"claude-fable-5","ts":%s,"session_id":"g2-selftest","artifact_ref":"%s"}\n' "$1" "$2" "$3" >>"$4"
  }
  # _g_count <pattern> <file> — grep -c ALWAYS prints a number (0 included)
  # even when its exit status is nonzero (zero matches); appending
  # `|| echo 0` to that is a real bug, not defensive coding — it makes
  # bash ALSO run the echo (since grep's own exit was nonzero), so a
  # genuine zero-match count comes back as the TWO-LINE string "0\n0"
  # instead of "0", breaking any `$(( ... ))` arithmetic downstream. This
  # helper reads grep's printed count only, never OR-fallback-appends to it.
  _g_count() {
    local c
    c="$(grep -c -- "$1" "$2" 2>/dev/null)"
    printf '%s' "${c:-0}"
  }

  # --- (i)/(ii): chain-less NEW plan -- the demo's flagship shape ----------
  (
    cd "$G2R" || exit 1
    {
      echo "# G2 self-test: chain-less new plan"
      echo "Status: ACTIVE"
      echo
      echo "## Goal"
      echo "The P-39 shape — dispatchable, zero mechanical proof any review ran."
    } >docs/plans/g2-demo-new-plan.md
    git add docs/plans/g2-demo-new-plan.md >/dev/null
    git -c commit.gpgsign=false commit -q -m "g2-demo-new-plan (chain-less)"
  )

  # DEMO VARIANT (i): plan-phase-builder, WITH an NL-ATTRIBUTION header.
  OUT1="$(cd "$G2R" && bash "$_dcg_dir/dispatch-chain-gate.sh" <<<'{"tool_name":"Task","tool_input":{"subagent_type":"plan-phase-builder","description":"Build Task 1 of docs/plans/g2-demo-new-plan.md","prompt":"NL-ATTRIBUTION: plan=g2-demo-new-plan task=1 role=builder\nBuild Task 1 of docs/plans/g2-demo-new-plan.md in your worktree."}}' 2>&1)"
  RC1=$?
  DEMO_VARIANT_1="$OUT1"
  DEMO_VARIANT_1_RC="$RC1"
  _st "demo-i-chainless-new-plan-blocked-rc2" "2" "$RC1"
  for marker in "[GATE:WHAT]" "[GATE:WHY]" "[GATE:FIX]" "[GATE:ESCAPE]"; do
    C=$(printf '%s\n' "$OUT1" | grep -c -F "$marker")
    _st "demo-i-has-$marker" "1" "$C"
  done

  # DEMO VARIANT (ii): SAME plan, NO NL-ATTRIBUTION line anywhere -- slug
  # must still resolve via the docs/plans/ prompt scrape (H1 subagent_type
  # keying, not attribution presence) -- STILL BLOCKED.
  OUT2="$(cd "$G2R" && bash "$_dcg_dir/dispatch-chain-gate.sh" <<<'{"tool_name":"Task","tool_input":{"subagent_type":"plan-phase-builder","description":"Build Task 1","prompt":"Build Task 1 of docs/plans/g2-demo-new-plan.md in your worktree. No attribution header anywhere in this prompt at all."}}' 2>&1)"
  RC2=$?
  DEMO_VARIANT_2="$OUT2"
  DEMO_VARIANT_2_RC="$RC2"
  _st "demo-ii-no-attribution-still-blocked-rc2" "2" "$RC2"
  for marker in "[GATE:WHAT]" "[GATE:WHY]" "[GATE:FIX]" "[GATE:ESCAPE]"; do
    C=$(printf '%s\n' "$OUT2" | grep -c -F "$marker")
    _st "demo-ii-has-$marker" "1" "$C"
  done
  NLA=$(printf '%s\n' "$OUT2" | grep -c -F "NL-ATTRIBUTION")
  _st "demo-ii-prompt-carried-no-attribution-line" "0" "$NLA"

  # --- (iii): chain entry naming a NEVER-DISPATCHED reviewer ---------------
  # Landing/calibration dates pinned to the PAST so this throwaway repo's
  # real-now commits are never pre-ledger-exempt and any (absent, by
  # construction) rule-2 mismatch would hard-FAIL rather than WARN --
  # review-chain-lib.sh's own --self-test uses the identical pinning
  # technique for the identical reason.
  (
    cd "$G2R" || exit 1
    RECORD="docs/reviews/g2-demo-never-dispatched-record.md"
    _g_write_plan docs/plans/g2-demo-never-dispatched.md "harness-reviewer" "PASS" "$RECORD" "PENDING"
    git add docs/plans/g2-demo-never-dispatched.md >/dev/null
    git -c commit.gpgsign=false commit -q -m "g2-demo-never-dispatched plan"
    BLOB="$(rc_blob_of docs/plans/g2-demo-never-dispatched.md plan)"
    sed -i "s/PENDING/$BLOB/" docs/plans/g2-demo-never-dispatched.md
    _g_write_record "$RECORD" "harness-reviewer (model: fable)" docs/plans/g2-demo-never-dispatched.md "$BLOB" "PASS"
    git add docs/plans/g2-demo-never-dispatched.md "$RECORD" >/dev/null
    git -c commit.gpgsign=false commit -q -m "g2-demo-never-dispatched record (well-formed, never actually dispatched)"
    # Deliberately NO ledger row for harness-reviewer -- that is the point.
    : >"$G2T/g2-never-dispatched-ledger.jsonl"
  )
  OUT3="$(cd "$G2R" && RC_LEDGER_LANDING_DATE="2020-01-01" RC_LEDGER_PATH="$G2T/g2-never-dispatched-ledger.jsonl" bash "$_dcg_dir/dispatch-chain-gate.sh" <<<'{"tool_name":"Task","tool_input":{"subagent_type":"plan-phase-builder","description":"Build Task 1 of docs/plans/g2-demo-never-dispatched.md","prompt":"NL-ATTRIBUTION: plan=g2-demo-never-dispatched task=1 role=builder\nBuild Task 1 of docs/plans/g2-demo-never-dispatched.md in your worktree."}}' 2>&1)"
  RC3=$?
  DEMO_VARIANT_3="$OUT3"
  DEMO_VARIANT_3_RC="$RC3"
  _st "demo-iii-never-dispatched-reviewer-blocked-rc2" "2" "$RC3"
  for marker in "[GATE:WHAT]" "[GATE:WHY]" "[GATE:FIX]" "[GATE:ESCAPE]"; do
    C=$(printf '%s\n' "$OUT3" | grep -c -F "$marker")
    _st "demo-iii-has-$marker" "1" "$C"
  done
  # "fails validity" legitimately appears more than once (header line +
  # [GATE:WHAT] line) -- assert PRESENT (>=1), not an exact count; the
  # actual class-distinguishing assertion is its ABSENCE of the chain-less
  # framing, checked separately below.
  FAILSVALIDITY=$(_g_count "fails validity" <(printf '%s\n' "$OUT3"))
  _st "demo-iii-message-says-fails-validity" "1" "$(( FAILSVALIDITY > 0 ? 1 : 0 ))"
  NOCHAINPHRASING=$(_g_count "has no ## Review Chain block" <(printf '%s\n' "$OUT3"))
  _st "demo-iii-message-is-not-the-chain-less-framing" "0" "$NOCHAINPHRASING"

  # --- grandfathered slug: chain-less, but on the grandfather list ---------
  (
    cd "$G2R" || exit 1
    {
      echo "# G2 self-test: grandfathered legacy plan"
      echo "Status: ACTIVE"
      echo
      echo "## Goal"
      echo "Chain-less, but listed on the grandfather slug list."
    } >docs/plans/g2-demo-grandfathered.md
    git add docs/plans/g2-demo-grandfathered.md >/dev/null
    git -c commit.gpgsign=false commit -q -m "g2-demo-grandfathered (chain-less, legacy)"
  )
  GFLIST="$G2T/grandfather-list.txt"
  printf '%s\n' "# g2 self-test grandfather list (opaque sha256 entries)" "$(printf '%s' "g2-demo-grandfathered" | sha256sum | cut -d' ' -f1)" >"$GFLIST"
  OUT4="$(cd "$G2R" && DCG_GRANDFATHER_PATH="$GFLIST" bash "$_dcg_dir/dispatch-chain-gate.sh" <<<'{"tool_name":"Task","tool_input":{"subagent_type":"plan-phase-builder","description":"Build Task 1 of docs/plans/g2-demo-grandfathered.md","prompt":"NL-ATTRIBUTION: plan=g2-demo-grandfathered task=1 role=builder\nBuild Task 1 of docs/plans/g2-demo-grandfathered.md in your worktree."}}' 2>&1)"
  RC4=$?
  _st "grandfathered-slug-proceeds-rc0" "0" "$RC4"
  GFWARN=$(printf '%s\n' "$OUT4" | grep -ci "grandfathered")
  _st "grandfathered-slug-warn-names-grandfather" "1" "$(( GFWARN > 0 ? 1 : 0 ))"
  GFROWS=$(_g_count '"bypass_kind":"grandfather"' "$WORKAROUND_SENSOR_LEDGER_PATH")
  _st "grandfathered-slug-writes-ledger-row" "1" "$(( GFROWS > 0 ? 1 : 0 ))"

  # --- valid-chain plan (mirrors the live plan's shape) -> silent pass -----
  (
    cd "$G2R" || exit 1
    RECORD="docs/reviews/g2-demo-valid-record.md"
    _g_write_plan docs/plans/g2-demo-valid.md "plan-fidelity-reviewer" "PASS" "$RECORD" "PENDING"
    git add docs/plans/g2-demo-valid.md >/dev/null
    git -c commit.gpgsign=false commit -q -m "g2-demo-valid plan"
    BLOB="$(rc_blob_of docs/plans/g2-demo-valid.md plan)"
    sed -i "s/PENDING/$BLOB/" docs/plans/g2-demo-valid.md
    _g_write_record "$RECORD" "plan-fidelity-reviewer (model: fable)" docs/plans/g2-demo-valid.md "$BLOB" "PASS"
    git add docs/plans/g2-demo-valid.md "$RECORD" >/dev/null
    git -c commit.gpgsign=false commit -q -m "g2-demo-valid record"
    RTS="$(rc_record_head_commit_epoch "$RECORD")"
    _g_ledger_row "plan-fidelity-reviewer" "$RTS" "docs/plans/g2-demo-valid.md" "$G2T/g2-valid-ledger.jsonl"
  )
  OUT5="$(cd "$G2R" && RC_LEDGER_LANDING_DATE="2020-01-01" RC_LEDGER_PATH="$G2T/g2-valid-ledger.jsonl" bash "$_dcg_dir/dispatch-chain-gate.sh" <<<'{"tool_name":"Task","tool_input":{"subagent_type":"plan-phase-builder","description":"Build Task 1 of docs/plans/g2-demo-valid.md","prompt":"NL-ATTRIBUTION: plan=g2-demo-valid task=1 role=builder\nBuild Task 1 of docs/plans/g2-demo-valid.md in your worktree."}}' 2>&1)"
  RC5=$?
  _st "valid-chain-plan-silent-pass-rc0" "0" "$RC5"
  BLOCKMARKERS5=$(printf '%s\n' "$OUT5" | grep -c -F "[GATE:")
  _st "valid-chain-plan-no-gate-block-markers" "0" "$BLOCKMARKERS5"

  # --- C1 (harness-review remediation round, 2026-08-03): the T25 WIP-limit
  # consult LIVE inside PreToolUse mode -- reuses the SAME g2-demo-valid.md
  # plan + ledger the scenario immediately above just proved has a VALID
  # chain (so any block below is attributable to the WIP limit, not a chain
  # failure), then layers 3 builder-complete rows for that plan's tasks onto
  # the SAME ledger file.
  # ------------------------------------------------------------------------
  WIPLEDGER="$G2T/g2-valid-ledger.jsonl"
  {
    printf '{"subagent_type":"plan-phase-builder","model":"claude-fable-5","ts":9001,"session_id":"wip1","artifact_ref":"docs/plans/g2-demo-valid.md","task_id":"2"}\n'
    printf '{"subagent_type":"plan-phase-builder","model":"claude-fable-5","ts":9002,"session_id":"wip2","artifact_ref":"docs/plans/g2-demo-valid.md","task_id":"3"}\n'
    printf '{"subagent_type":"plan-phase-builder","model":"claude-fable-5","ts":9003,"session_id":"wip3","artifact_ref":"docs/plans/g2-demo-valid.md","task_id":"4"}\n'
  } >>"$WIPLEDGER"

  # A 4th BUILDER dispatch against the same plan -> WIP-limit BLOCK (rc 2,
  # not rc 1 -- this is the PreToolUse enforce path, distinct from --check's
  # would-block convention).
  OUT8="$(cd "$G2R" && RC_LEDGER_LANDING_DATE="2020-01-01" RC_LEDGER_PATH="$WIPLEDGER" DISPATCH_PROVENANCE_STATE_DIR="$G2T/g2-wip-dispatch-provenance" bash "$_dcg_dir/dispatch-chain-gate.sh" <<<'{"tool_name":"Task","tool_input":{"subagent_type":"plan-phase-builder","description":"Build Task 5 of docs/plans/g2-demo-valid.md","prompt":"NL-ATTRIBUTION: plan=g2-demo-valid task=5 role=builder\nBuild Task 5 of docs/plans/g2-demo-valid.md in your worktree."}}' 2>&1)"
  RC8=$?
  _st "c1-wip-limit-blocks-4th-builder-rc2" "2" "$RC8"
  WIPNAMES=1
  for t in 2 3 4; do printf '%s' "$OUT8" | grep -q "$t" || WIPNAMES=0; done
  _st "c1-wip-limit-block-names-open-tasks" "1" "$WIPNAMES"

  # The SAME open-obligation ledger, but a task-verifier dispatch (a
  # "review" category type, never build-category) -> proceeds untouched;
  # _dcg_is_build_type's early return means this dispatch never even
  # reaches the WIP-limit consult, so remedy verifier dispatches are
  # provably unblockable by construction, not just by policy.
  OUT9="$(cd "$G2R" && RC_LEDGER_LANDING_DATE="2020-01-01" RC_LEDGER_PATH="$WIPLEDGER" DISPATCH_PROVENANCE_STATE_DIR="$G2T/g2-wip-dispatch-provenance" bash "$_dcg_dir/dispatch-chain-gate.sh" <<<'{"tool_name":"Task","tool_input":{"subagent_type":"task-verifier","description":"Verify Task 2 of docs/plans/g2-demo-valid.md","prompt":"NL-ATTRIBUTION: plan=g2-demo-valid task=2 role=verifier\nVerify Task 2 of docs/plans/g2-demo-valid.md."}}' 2>&1)"
  RC9=$?
  _st "c1-verifier-dispatch-unblockable-rc0" "0" "$RC9"

  # --- research-type dispatch -> fully untouched ----------------------------
  BEFORE_LEDGER_LINES=$(wc -l <"$WORKAROUND_SENSOR_LEDGER_PATH" 2>/dev/null || echo 0)
  OUT6="$(cd "$G2R" && bash "$_dcg_dir/dispatch-chain-gate.sh" <<<'{"tool_name":"Task","tool_input":{"subagent_type":"architecture-reviewer","description":"Review the design","prompt":"Review docs/designs/gated-pipeline-master-2026-08-03.md for soundness. No plan reference in this prompt."}}' 2>&1)"
  RC6=$?
  _st "research-dispatch-untouched-rc0" "0" "$RC6"
  AFTER_LEDGER_LINES=$(wc -l <"$WORKAROUND_SENSOR_LEDGER_PATH" 2>/dev/null || echo 0)
  _st "research-dispatch-no-ledger-row-written" "$BEFORE_LEDGER_LINES" "$AFTER_LEDGER_LINES"

  # --- M-7 evasion heuristic: non-build type referencing docs/plans/ -------
  OUT7="$(cd "$G2R" && bash "$_dcg_dir/dispatch-chain-gate.sh" <<<'{"tool_name":"Task","tool_input":{"subagent_type":"general-purpose","description":"Handle the plan","prompt":"Please build out Task 1 of docs/plans/g2-demo-new-plan.md yourself, no need for a real builder agent."}}' 2>&1)"
  RC7=$?
  _st "m7-heuristic-never-blocks-rc0" "0" "$RC7"
  M7ROWS=$(_g_count '"bypass_kind":"role-mislabeled-build-reference"' "$WORKAROUND_SENSOR_LEDGER_PATH")
  _st "m7-heuristic-writes-ledger-row" "1" "$(( M7ROWS > 0 ? 1 : 0 ))"

  # --- test-writer, underivable slug -> WARN + ledger row, never blocks ----
  OUT8="$(cd "$G2R" && bash "$_dcg_dir/dispatch-chain-gate.sh" <<<'{"tool_name":"Task","tool_input":{"subagent_type":"test-writer","description":"Write some tests","prompt":"Write unit tests for the new helper function. No plan reference anywhere."}}' 2>&1)"
  RC8=$?
  _st "test-writer-underivable-slug-warns-rc0" "0" "$RC8"
  TWROWS=$(_g_count '"bypass_kind":"underivable-slug"' "$WORKAROUND_SENSOR_LEDGER_PATH")
  _st "test-writer-underivable-slug-writes-ledger-row" "1" "$(( TWROWS > 0 ? 1 : 0 ))"

  # --- plan-phase-builder, underivable slug -> BLOCK (distinct from the
  # chain-less-plan block: this one fires before any plan file resolution) -
  OUT9="$(bash "$_dcg_dir/dispatch-chain-gate.sh" <<<'{"tool_name":"Task","tool_input":{"subagent_type":"plan-phase-builder","description":"Build the thing","prompt":"Build the thing. No plan reference anywhere in this prompt."}}' 2>&1)"
  RC9=$?
  _st "plan-phase-builder-underivable-slug-blocked-rc2" "2" "$RC9"
  NODERIVE=$(printf '%s\n' "$OUT9" | grep -c -F "no derivable plan slug")
  _st "plan-phase-builder-underivable-slug-message" "1" "$NODERIVE"

  # --- no-repo (Mi-5): session cwd outside any git repo -> WARN pass -------
  NOGIT="$G2T/nogit"
  mkdir -p "$NOGIT"
  OUT10="$(cd "$NOGIT" && bash "$_dcg_dir/dispatch-chain-gate.sh" <<<'{"tool_name":"Task","tool_input":{"subagent_type":"plan-phase-builder","description":"Build Task 1 of docs/plans/some-plan.md","prompt":"NL-ATTRIBUTION: plan=some-plan task=1 role=builder\nBuild Task 1 of docs/plans/some-plan.md in your worktree."}}' 2>&1)"
  RC10=$?
  _st "no-repo-cwd-warns-and-passes-rc0" "0" "$RC10"
  NOREPOWARN=$(printf '%s\n' "$OUT10" | grep -c -i "not inside a git repo")
  _st "no-repo-cwd-warn-names-no-repo" "1" "$(( NOREPOWARN > 0 ? 1 : 0 ))"

  # --- non-spawn tool (Bash) -> silently untouched --------------------------
  OUT11="$(bash "$_dcg_dir/dispatch-chain-gate.sh" <<<'{"tool_name":"Bash","tool_input":{"command":"ls"}}' 2>&1)"
  RC11=$?
  _st "non-spawn-tool-untouched-rc0" "0" "$RC11"

  unset HARNESS_SELFTEST WORKAROUND_SENSOR_LEDGER_PATH
  rm -rf "$G2T" 2>/dev/null || true
  trap - EXIT

  echo "self-test summary: $PASSED passed, $FAILED failed (of $((PASSED + FAILED)) scenarios)" >&2
  if [[ "$FAILED" -eq 0 ]]; then
    exit 0
  else
    exit 1
  fi
fi

# ============================================================
# CLI dispatch (direct-execution guard — sourcing this file for its functions
# is not a supported use, unlike the libs; this is a gate entry point).
# ============================================================
if [[ "${BASH_SOURCE[0]:-$0}" == "${0}" ]]; then
  case "${1:-}" in
    --check)
      [[ -n "${2:-}" ]] || { _dcg_usage; exit 2; }
      if _dcg_check "$2"; then
        exit 0
      else
        mode="$(gc_mode --check)"
        exit "$(gc_exit_code "$mode" 2)"
      fi
      ;;
    "")
      _dcg_gate
      exit $?
      ;;
    *)
      _dcg_usage
      exit 2
      ;;
  esac
fi
