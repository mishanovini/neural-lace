#!/bin/bash
# backfill-classify-amendment-candidates.sh — ONE-SHOT, IDEMPOTENT historical
# repair for the 2026-07-30 "Requests tab isn't showing much of anything"
# defect.
#
# ============================================================
# THE BUG (full story: ask-registry.sh's DETERMINISTIC CLASSIFIER header
# comment, and workstreams-ui/server/verbatim-resolver.js's own header)
# ============================================================
#
# ~/.claude/state/ask-registry.jsonl accumulates `amendment_candidate`
# records for every operator prompt AFTER a session's first — one per
# ask-attached session, because `pl_ask_id_for_session` derives ask_id 1:1
# from session_id for the session's WHOLE LIFETIME (hooks/workstreams-
# read.sh). A long-running session therefore files dozens of substantively
# unrelated later requests as pending "amendments" of its FIRST ask, and —
# PROVEN 2026-07-30 — the async LLM classifier meant to sort these
# (ask-registry.sh's `_ar_classify_candidate_text`, `claude --model haiku`)
# hangs 100% of the time when invoked from a hook running inside an
# already-live Claude Code session (the nested-session guard's bypass does
# not fail fast; it hangs until the 20s bound kills it). Zero of the 114
# real candidates captured 2026-07-28..30 on this machine ever got
# classified — every one sat at `classification:"pending"` forever, with no
# raw text (by design: the registry never stores it, only a `verbatim_ref`
# pointer), rendering as a single generic, content-free timeline entry.
#
# The forward fix (same commit series as this script) makes NEW captures
# self-heal: a deterministic (no model call) classifier now runs
# immediately on every new candidate. This script is the retroactive half —
# it cannot un-happen the 114 records that already sat unclassified, so it
# runs the SAME resolve+classify decision against them now, using the SAME
# verbatim-resolver.js the live path uses, and applies the verdict through
# ask-registry.sh's own public verbs (classify-candidate / register) — the
# ONE-WRITER discipline this file's whole design rests on. NEVER touches
# ask-registry.jsonl directly; NEVER rewrites or deletes a single line —
# every repair is a NEW appended record, exactly like every other mutation
# this registry has ever recorded.
#
# ============================================================
# USAGE
# ============================================================
#   backfill-classify-amendment-candidates.sh [--dry-run|--apply] [--limit N]
#     --dry-run (DEFAULT)  Report what WOULD be classified/promoted; touches
#                          NOTHING on disk. Safe to run any number of times.
#     --apply              Actually append the classify-candidate/register
#                          records via ask-registry.sh.
#     --limit N            Process at most N still-pending candidates this
#                          run (default: unlimited). Useful for a cautious
#                          first pass against the real registry.
#   backfill-classify-amendment-candidates.sh --self-test
#     Self-contained assertion suite, entirely sandboxed under
#     ASK_REGISTRY_STATE_DIR / a synthetic transcript tree — never touches
#     the real machine's state.
#
# ============================================================
# IDEMPOTENCY
# ============================================================
# A candidate is "still pending" iff NO `candidate_classified` record exists
# anywhere in the registry for its `candidate_id` (any emitter — the live
# deterministic lane, a prior backfill run, an operator correction, or the
# (empirically dead but still wired) LLM lane). Re-running this script is
# always safe: every candidate it already classified is skipped on the next
# run because that classify record now exists.
#
# ============================================================
# SANDBOXING / RESOLUTION
# ============================================================
#   - Registry file: BACKFILL_ASK_REGISTRY_CLI (defaults to the
#     ask-registry.sh next to this script) is asked for its own state dir
#     resolution indirectly — this script reads ASK_REGISTRY_STATE_DIR (or
#     falls back to $HOME/.claude/state, matching ask-registry.sh's own
#     `ar_state_dir` contract) so both agree on the SAME file without this
#     script re-deriving or duplicating that resolver.
#   - Node resolver/classifier: BACKFILL_RESOLVER_OVERRIDE, else the copy
#     shipped next to this script's own checkout
#     (neural-lace/workstreams-ui/server/verbatim-resolver.js) — same
#     SCRIPT_DIR-relative-first precedence as ask-registry.sh's
#     `_ar_resolver_cli_path`, so a builder's worktree resolves its OWN
#     in-progress resolver before merge, not a stale main-checkout copy.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- portable bounded subprocess (harness-reviewer Minor, 2026-07-30: the
# resolver/classifier call below had no time bound, unlike the live lane's
# own `nl_run_bounded 15s` in ask-registry.sh) -----------------------------
# shellcheck disable=SC1091
{ source "$SCRIPT_DIR/../hooks/lib/portable-timeout.sh" 2>/dev/null; } || true
if ! declare -F nl_run_bounded >/dev/null 2>&1; then
  nl_run_bounded() {
    local s="${1:-0}"; shift 2>/dev/null || true
    echo "backfill-classify-amendment-candidates.sh: WARN hooks/lib/portable-timeout.sh missing — running UNBOUNDED (wanted ${s}s): ${1:-<none>}" >&2
    [ "$#" -gt 0 ] || return 2
    "$@"
  }
fi

_bc_ar_cli() {
  if [[ -n "${BACKFILL_ASK_REGISTRY_CLI:-}" ]]; then
    printf '%s' "$BACKFILL_ASK_REGISTRY_CLI"
    return 0
  fi
  printf '%s/ask-registry.sh' "$SCRIPT_DIR"
}

_bc_registry_file() {
  if [[ -n "${ASK_REGISTRY_STATE_DIR:-}" ]]; then
    printf '%s/ask-registry.jsonl' "$ASK_REGISTRY_STATE_DIR"
    return 0
  fi
  printf '%s/.claude/state/ask-registry.jsonl' "${HOME:-$PWD}"
}

_bc_resolver_cli() {
  if [[ -n "${BACKFILL_RESOLVER_OVERRIDE:-}" ]]; then
    printf '%s' "$BACKFILL_RESOLVER_OVERRIDE"
    return 0
  fi
  local local_path="$SCRIPT_DIR/../../../neural-lace/workstreams-ui/server/verbatim-resolver.js"
  if [[ -f "$local_path" ]]; then
    printf '%s' "$local_path"
    return 0
  fi
  local _bc_nlpaths="$SCRIPT_DIR/../hooks/lib/nl-paths.sh"
  if [[ -f "$_bc_nlpaths" ]]; then
    # shellcheck disable=SC1090
    source "$_bc_nlpaths"
    if command -v nl_workstreams_ui >/dev/null 2>&1; then
      local ui_root; ui_root="$(nl_workstreams_ui)"
      if [[ -n "$ui_root" && -f "$ui_root/server/verbatim-resolver.js" ]]; then
        printf '%s/server/verbatim-resolver.js' "$ui_root"
        return 0
      fi
    fi
  fi
  printf ''
}

# ----------------------------------------------------------------------
# cmd_run [--apply] [--limit N] — the one-shot backfill.
# ----------------------------------------------------------------------
cmd_run() {
  local apply=0 limit=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --apply) apply=1 ;;
      --dry-run) apply=0 ;;
      --limit) shift; limit="${1:-0}" ;;
    esac
    shift
  done

  command -v jq >/dev/null 2>&1 || { echo "backfill-classify-amendment-candidates.sh: jq is required and was not found on PATH — aborting, nothing touched." >&2; return 1; }
  command -v node >/dev/null 2>&1 || { echo "backfill-classify-amendment-candidates.sh: node is required and was not found on PATH — aborting, nothing touched." >&2; return 1; }

  local reg; reg="$(_bc_registry_file)"
  if [[ ! -f "$reg" ]]; then
    echo "backfill-classify-amendment-candidates.sh: no registry file found at $reg — nothing to backfill."
    return 0
  fi
  local resolver; resolver="$(_bc_resolver_cli)"
  if [[ -z "$resolver" || ! -f "$resolver" ]]; then
    echo "backfill-classify-amendment-candidates.sh: could not locate verbatim-resolver.js (checked SCRIPT_DIR-relative + nl_workstreams_ui) — aborting, nothing touched." >&2
    return 1
  fi
  local ar_cli; ar_cli="$(_bc_ar_cli)"
  if [[ ! -f "$ar_cli" ]]; then
    echo "backfill-classify-amendment-candidates.sh: could not locate ask-registry.sh at $ar_cli — aborting, nothing touched." >&2
    return 1
  fi

  # Every candidate_id that ALREADY has a candidate_classified record, from
  # ANY emitter — the idempotency set. A prior backfill run, the live
  # deterministic lane, an operator correction, or (if it ever starts
  # working) the LLM lane all count; re-running this script never
  # reprocesses a candidate that already has a verdict.
  local already_classified
  already_classified="$(jq -r 'select(.record_type=="candidate_classified" and (.candidate_id // "") != "") | .candidate_id' "$reg" 2>/dev/null | sort -u)"

  # Every amendment_candidate birth record — (ask_id, candidate_id,
  # verbatim_ref, ts) tab-separated, oldest-first (processing order doesn't
  # affect correctness, but oldest-first reads naturally in --dry-run output
  # and in a partial --limit run).
  local pending_tsv
  pending_tsv="$(jq -r 'select(.record_type=="amendment_candidate" and (.candidate_id // "") != "") | [.ts, .ask_id, .candidate_id, .verbatim_ref] | @tsv' "$reg" 2>/dev/null | sort)"

  local total_candidates=0 already_done=0 to_process=0
  local n_amendment=0 n_noise=0 n_promoted=0 n_unresolved=0 n_processed=0
  local before_visible after_visible

  before_visible="$(_bc_count_visible_toplevel "$reg")"

  local line ts ask_id candidate_id vref
  while IFS=$'\t' read -r ts ask_id candidate_id vref; do
    [[ -z "$candidate_id" ]] && continue
    total_candidates=$((total_candidates + 1))
    if printf '%s\n' "$already_classified" | grep -qxF "$candidate_id"; then
      already_done=$((already_done + 1))
      continue
    fi
    to_process=$((to_process + 1))
    if [[ "$limit" -gt 0 && "$n_processed" -ge "$limit" ]]; then
      continue
    fi
    n_processed=$((n_processed + 1))

    local verdict_json vok classification candidate_text
    verdict_json="$(nl_run_bounded 15s node "$resolver" classify "$reg" "$ask_id" "$vref" "$ts" 2>/dev/null)"
    vok="$(printf '%s' "$verdict_json" | jq -r '.ok // false' 2>/dev/null)"
    if [[ "$vok" != "true" ]]; then
      n_unresolved=$((n_unresolved + 1))
      echo "  UNRESOLVED  ask=$ask_id candidate=$candidate_id ref=$vref — left pending (transcript not resolvable)"
      continue
    fi
    classification="$(printf '%s' "$verdict_json" | jq -r '.classification // ""' 2>/dev/null)"
    candidate_text="$(printf '%s' "$verdict_json" | jq -r '.candidate_text // ""' 2>/dev/null)"

    case "$classification" in
      noise)
        n_noise=$((n_noise + 1))
        echo "  NOISE       ask=$ask_id candidate=$candidate_id: ${candidate_text:0:80}"
        if [[ "$apply" == "1" ]]; then
          bash "$ar_cli" classify-candidate --ask-id "$ask_id" --candidate-id "$candidate_id" \
            --classification noise --emitter "backfill-2026-07-30" >/dev/null
        fi
        ;;
      amendment)
        n_amendment=$((n_amendment + 1))
        local label
        label="$(bash "$ar_cli" heuristic-summarize --text "$candidate_text" 2>/dev/null)"
        echo "  AMENDMENT   ask=$ask_id candidate=$candidate_id: $label"
        if [[ "$apply" == "1" ]]; then
          bash "$ar_cli" classify-candidate --ask-id "$ask_id" --candidate-id "$candidate_id" \
            --classification amendment --summary "$label" --emitter "backfill-2026-07-30" >/dev/null
        fi
        ;;
      new-topic)
        n_promoted=$((n_promoted + 1))
        echo "  PROMOTE     ask=$ask_id candidate=$candidate_id -> new ask: ${candidate_text:0:80}"
        if [[ "$apply" == "1" ]]; then
          # Mint the new ask_id UP FRONT (harness-reviewer Minor,
          # 2026-07-30) — the SAME technique the live deterministic
          # classifier already uses in-process — rather than `register`
          # then re-deriving the id by grepping for a matching
          # verbatim_ref. Removes both the lookup-failure surface (a
          # failed re-derive used to leave the candidate classify-less
          # with a "safe to re-run" warning that was NOT actually safe:
          # re-running would re-register a duplicate ask, since the
          # candidate_classified record IS this script's idempotency key)
          # and the narrow same-vref race window entirely.
          local label new_ask_id session_id
          label="$(bash "$ar_cli" heuristic-summarize --text "$candidate_text" 2>/dev/null)"
          new_ask_id="$(bash "$ar_cli" gen-ask-id --summary "$label" 2>/dev/null)"
          session_id="$(jq -r --arg a "$ask_id" 'select(.record_type=="created" and .ask_id==$a) | .session_id' "$reg" 2>/dev/null | head -n1)"
          if [[ -n "$new_ask_id" ]]; then
            bash "$ar_cli" register --ask-id "$new_ask_id" --summary "$label" \
              --session-id "$session_id" --verbatim-ref "$vref" >/dev/null
            bash "$ar_cli" classify-candidate --ask-id "$ask_id" --candidate-id "$candidate_id" \
              --classification promoted --summary "$new_ask_id" --emitter "backfill-2026-07-30" >/dev/null
            echo "              -> promoted to $new_ask_id"
          else
            echo "              -> WARNING: could not mint a new ask_id (gen-ask-id/heuristic-summarize unavailable) — candidate left pending, safe to re-run" >&2
          fi
        fi
        ;;
      *)
        n_unresolved=$((n_unresolved + 1))
        echo "  UNKNOWN     ask=$ask_id candidate=$candidate_id classification='$classification' — left pending"
        ;;
    esac
  done <<< "$pending_tsv"

  after_visible="$(_bc_count_visible_toplevel "$reg")"

  echo ""
  echo "backfill-classify-amendment-candidates.sh $( [[ "$apply" == "1" ]] && echo "--apply" || echo "--dry-run" ): $total_candidates total candidate(s), $already_done already classified, $to_process still pending$( [[ "$limit" -gt 0 ]] && echo " (processed $n_processed of them, --limit $limit)" )."
  echo "  amendment: $n_amendment   noise: $n_noise   promoted-to-new-ask: $n_promoted   unresolved(left pending): $n_unresolved"
  echo "  visible top-level requests (record_type=created): before=$before_visible"
  if [[ "$apply" == "1" ]]; then
    echo "  visible top-level requests (record_type=created): after=$after_visible"
  else
    echo "  (--dry-run: after-count not applicable — nothing was written; pass --apply to actually classify/promote)"
  fi
  return 0
}

# ----------------------------------------------------------------------
# _bc_count_visible_toplevel <registry_file> — number of distinct ask_ids
# with at least one 'created' record (the Requests tab's top-level row
# count) — used for the before/after acceptance readout.
# ----------------------------------------------------------------------
_bc_count_visible_toplevel() {
  local f="$1"
  [[ -f "$f" ]] || { printf '0'; return 0; }
  jq -r 'select(.record_type=="created") | .ask_id' "$f" 2>/dev/null | sort -u | wc -l | tr -d ' '
}

# ============================================================
# --self-test (sandboxed: synthetic registry + synthetic transcript, own tmpdir)
# ============================================================
cmd_selftest() {
  local PASSED=0 FAILED=0
  pass() { PASSED=$((PASSED+1)); echo "  PASS: $1"; }
  fail() { FAILED=$((FAILED+1)); echo "  FAIL: $1" >&2; }

  local TMP
  TMP=$(mktemp -d 2>/dev/null || mktemp -d -t 'bcst')
  if [[ -z "$TMP" ]] || [[ ! -d "$TMP" ]]; then
    echo "self-test: could not create tempdir" >&2
    return 1
  fi
  trap 'rm -rf "$TMP"' RETURN

  export HARNESS_SELFTEST=1
  export ASK_REGISTRY_STATE_DIR="$TMP/ar"
  export PROGRESS_LOG_STATE_DIR="$TMP/pl"
  mkdir -p "$ASK_REGISTRY_STATE_DIR" "$PROGRESS_LOG_STATE_DIR"
  local REG="$ASK_REGISTRY_STATE_DIR/ask-registry.jsonl"
  local AR_CLI="$SCRIPT_DIR/ask-registry.sh"

  # ASK_VERBATIM_RESOLVER_OVERRIDE points ask-registry.sh's OWN live
  # deterministic classifier (the forward-fix this script complements) at a
  # path that can never exist, so EVERY capture-candidate call below leaves
  # its candidate genuinely, honestly pending — exactly the historical
  # damage shape (114 real records, zero ever classified) — and this
  # self-test then genuinely exercises THIS SCRIPT's own resolve+classify
  # logic (a DIFFERENT resolver-path resolution function, `_bc_resolver_cli`)
  # rather than accidentally re-testing ask-registry.sh's already-proven
  # live lane (ask-registry.sh's own self-test Scenarios R5-R8 own that).
  export ASK_VERBATIM_RESOLVER_OVERRIDE="$TMP/no-such-resolver.js"

  local T1="$TMP/t1.jsonl"
  local ts0 ts1 ts2 ts3
  ts0="$(date -u '+%Y-%m-%dT%H:%M:%S.000Z')"
  printf '{"type":"user","timestamp":"%s","isSidechain":false,"message":{"role":"user","content":"Please fix the login page so the submit button actually submits the form."}}\n' "$ts0" > "$T1"
  bash "$AR_CLI" register --ask-id "ask-bc-1" --summary "Please fix the login page so the submit button actually submits the form." \
    --verbatim-ref "${T1}#0" --session-id "sess-bc-1" >/dev/null
  sleep 1.2
  ts1="$(date -u '+%Y-%m-%dT%H:%M:%S.000Z')"
  printf '{"type":"user","timestamp":"%s","isSidechain":false,"message":{"role":"user","content":"also please disable the submit button while the form is submitting"}}\n' "$ts1" >> "$T1"
  bash "$AR_CLI" capture-candidate --ask-id "ask-bc-1" --candidate-id "cand-bc-amend" \
    --session-id "sess-bc-1" --verbatim-ref "${T1}#1" >/dev/null

  sleep 1.2
  ts2="$(date -u '+%Y-%m-%dT%H:%M:%S.000Z')"
  printf '{"type":"user","timestamp":"%s","isSidechain":false,"message":{"role":"user","content":"Completely unrelated: can you also set up weekly backups for the database?"}}\n' "$ts2" >> "$T1"
  bash "$AR_CLI" capture-candidate --ask-id "ask-bc-1" --candidate-id "cand-bc-promote" \
    --session-id "sess-bc-1" --verbatim-ref "${T1}#2" >/dev/null

  sleep 1.2
  ts3="$(date -u '+%Y-%m-%dT%H:%M:%S.000Z')"
  printf '{"type":"user","timestamp":"%s","isSidechain":false,"message":{"role":"user","content":"thanks looks good"}}\n' "$ts3" >> "$T1"
  bash "$AR_CLI" capture-candidate --ask-id "ask-bc-1" --candidate-id "cand-bc-noise" \
    --session-id "sess-bc-1" --verbatim-ref "${T1}#3" >/dev/null

  # A candidate with an UNRESOLVABLE ref (fake path) — must stay pending
  # through the backfill too, never crash, never fabricate.
  bash "$AR_CLI" capture-candidate --ask-id "ask-bc-1" --candidate-id "cand-bc-unresolvable" \
    --session-id "sess-bc-1" --verbatim-ref "/does/not/exist.jsonl#0" >/dev/null

  sleep 1.5
  # Confirm the block actually worked BEFORE testing this script's own
  # logic — if this ever fails, every downstream assertion below would be
  # meaningless (silently re-testing ask-registry.sh's lane instead of this
  # script's), so fail LOUDLY and distinctly rather than let it masquerade
  # as a pass.
  if grep -q '"record_type":"candidate_classified"' "$REG" 2>/dev/null; then
    fail "FIXTURE SETUP INVALID: ask-registry.sh's own live classifier already classified a candidate despite ASK_VERBATIM_RESOLVER_OVERRIDE pointing nowhere — every assertion below would be testing the wrong thing"
  else
    pass "fixture setup: all candidates are genuinely pending (live classifier correctly blocked) — the tests below exercise THIS script's own resolution"
  fi
  unset ASK_VERBATIM_RESOLVER_OVERRIDE

  echo "Scenario 1: --dry-run touches NOTHING (line count unchanged, no candidate_classified appended)"
  local before_lines after_lines
  before_lines=$(wc -l < "$REG" | tr -d ' ')
  local dry_out
  dry_out="$(cmd_run --dry-run 2>&1)"
  after_lines=$(wc -l < "$REG" | tr -d ' ')
  if [[ "$before_lines" == "$after_lines" ]]; then
    pass "--dry-run left the registry byte-for-byte line-count unchanged"
  else
    fail "--dry-run modified the registry ($before_lines -> $after_lines lines)"
  fi
  if printf '%s' "$dry_out" | grep -q "AMENDMENT" && printf '%s' "$dry_out" | grep -q "PROMOTE"; then
    pass "--dry-run reports the projected classification/promotion decisions"
  else
    fail "--dry-run output missing expected AMENDMENT/PROMOTE lines: $dry_out"
  fi

  echo "Scenario 2: --apply actually classifies the amendment + noise candidates and promotes the new-topic one"
  cmd_run --apply >/dev/null 2>&1
  if grep '"candidate_id":"cand-bc-amend"' "$REG" | grep -q '"classification":"amendment"'; then
    pass "cand-bc-amend was classified 'amendment'"
  else
    fail "expected cand-bc-amend classified 'amendment' after --apply"
  fi
  if grep '"candidate_id":"cand-bc-noise"' "$REG" | grep -q '"classification":"noise"'; then
    pass "cand-bc-noise was classified 'noise'"
  else
    fail "expected cand-bc-noise classified 'noise' after --apply"
  fi
  local promoted_to
  promoted_to="$(grep '"candidate_id":"cand-bc-promote"' "$REG" | grep '"classification":"promoted"' | sed -E 's/.*"summary":"([^"]*)".*/\1/' | head -n1)"
  if [[ -n "$promoted_to" ]] && grep -q '"ask_id":"'"$promoted_to"'".*"record_type":"created"' "$REG"; then
    pass "cand-bc-promote was promoted into its own new top-level ask ($promoted_to)"
  else
    fail "expected cand-bc-promote promoted into a real new top-level ask"
  fi
  if ! grep -q '"candidate_id":"cand-bc-unresolvable".*"record_type":"candidate_classified"' "$REG" 2>/dev/null \
     && ! grep '"candidate_id":"cand-bc-unresolvable"' "$REG" | grep -q '"record_type":"candidate_classified"'; then
    pass "the unresolvable candidate was left pending (no fabricated classification)"
  else
    fail "the unresolvable candidate unexpectedly got classified"
  fi

  echo "Scenario 3: a second --apply run is a safe no-op (idempotent — nothing reprocessed, no duplicate records)"
  local classified_count_before classified_count_after
  classified_count_before=$(jq -r 'select(.record_type=="candidate_classified") | .candidate_id' "$REG" | sort -u | wc -l | tr -d ' ')
  cmd_run --apply >/dev/null 2>&1
  classified_count_after=$(jq -r 'select(.record_type=="candidate_classified") | .candidate_id' "$REG" | sort -u | wc -l | tr -d ' ')
  local lines_before2 lines_after2
  lines_before2=$(wc -l < "$REG" | tr -d ' ')
  cmd_run --apply >/dev/null 2>&1
  lines_after2=$(wc -l < "$REG" | tr -d ' ')
  if [[ "$classified_count_before" == "$classified_count_after" ]] && [[ "$lines_before2" == "$lines_after2" ]]; then
    pass "re-running --apply after everything is classified appends nothing new (idempotent)"
  else
    fail "a re-run appended duplicate records (classified count $classified_count_before -> $classified_count_after; lines $lines_before2 -> $lines_after2)"
  fi

  echo "Scenario 4: --limit bounds how many pending candidates get processed in one run"
  local T2="$TMP/t2.jsonl"
  local lts0
  lts0="$(date -u '+%Y-%m-%dT%H:%M:%S.000Z')"
  printf '{"type":"user","timestamp":"%s","isSidechain":false,"message":{"role":"user","content":"Please set up the staging environment."}}\n' "$lts0" > "$T2"
  bash "$AR_CLI" register --ask-id "ask-bc-limit" --summary "Please set up the staging environment." \
    --verbatim-ref "${T2}#0" --session-id "sess-bc-limit" >/dev/null
  local i
  for i in 1 2; do
    sleep 1.2
    local lts
    lts="$(date -u '+%Y-%m-%dT%H:%M:%S.000Z')"
    printf '{"type":"user","timestamp":"%s","isSidechain":false,"message":{"role":"user","content":"unrelated candidate number %s about a totally different subject entirely"}}\n' "$lts" "$i" >> "$T2"
    bash "$AR_CLI" capture-candidate --ask-id "ask-bc-limit" --candidate-id "cand-bc-limit-$i" \
      --session-id "sess-bc-limit" --verbatim-ref "${T2}#$i" >/dev/null
  done
  sleep 2
  local limit_out
  limit_out="$(cmd_run --dry-run --limit 1 2>&1)"
  if printf '%s' "$limit_out" | grep -q "still pending (processed 1 of them, --limit 1)"; then
    pass "--limit 1 processed exactly one pending candidate this run (reported honestly)"
  else
    fail "--limit 1 did not report processing exactly 1: $limit_out"
  fi

  echo "Scenario 5: no registry file at all -> clean no-op, no error"
  local EMPTY_STATE="$TMP/empty-state"
  mkdir -p "$EMPTY_STATE"
  local out5
  out5="$(ASK_REGISTRY_STATE_DIR="$EMPTY_STATE" cmd_run --dry-run 2>&1)"
  if printf '%s' "$out5" | grep -qi "nothing to backfill"; then
    pass "absent registry reports nothing-to-backfill and exits cleanly"
  else
    fail "expected a nothing-to-backfill message; got: $out5"
  fi

  echo "Scenario 6 (harness-reviewer Minor, 2026-07-30): CLI entry point — '--limit N' as the FIRST/only argument (no explicit mode flag) is recognized, not silently swallowed as an unknown argument"
  local out6 rc6
  out6="$(bash "$SCRIPT_DIR/backfill-classify-amendment-candidates.sh" --limit 1 2>&1)"; rc6=$?
  if [[ "$rc6" == "0" ]] && printf '%s' "$out6" | grep -qi "nothing to backfill\|still pending"; then
    pass "'--limit 1' alone is treated as a --dry-run mode flag (not an unknown argument)"
  else
    fail "'--limit 1' alone should be a valid dry-run invocation; rc=$rc6 out=$out6"
  fi

  echo "Scenario 7 (harness-reviewer Minor, 2026-07-30): an OPERATOR typo exits NON-ZERO with a loud message — this is an operator CLI, not a hook, so 'never blocks a caller' does not apply"
  local out7 rc7
  out7="$(bash "$SCRIPT_DIR/backfill-classify-amendment-candidates.sh" --aply 2>&1)"; rc7=$?
  if [[ "$rc7" != "0" ]] && printf '%s' "$out7" | grep -qi "unknown argument"; then
    pass "an unrecognized argument exits non-zero with a named error, never a silent no-op"
  else
    fail "expected a non-zero exit + named error for an unknown argument; rc=$rc7 out=$out7"
  fi

  echo ""
  echo "self-test summary: $PASSED passed, $FAILED failed"
  if [[ "$FAILED" == "0" ]]; then
    return 0
  else
    return 1
  fi
}

# ============================================================
# Entry point
# ============================================================
# harness-reviewer Minor (2026-07-30): this is an OPERATOR-run one-shot
# CLI, not a hook — the "never blocks a caller" hook convention (silently
# exit 0 on anything unrecognized) does NOT apply here. `--limit N` as the
# FIRST/only argument (no explicit --dry-run/--apply) used to fall through
# to the unknown-argument branch and silently no-op with exit 0; every mode
# flag is now recognized regardless of position, and a genuinely unknown
# argument exits NON-ZERO with a loud message (an operator typo like
# --aply must never look like a clean, successful, did-nothing run).
case "${1:-}" in
  --self-test|--selftest|selftest|self-test)
    cmd_selftest
    exit $?
    ;;
  --apply)
    shift
    cmd_run --apply "$@"
    exit $?
    ;;
  --dry-run|""|--limit)
    cmd_run --dry-run "$@"
    exit $?
    ;;
  -h|--help)
    cat <<'USAGE'
backfill-classify-amendment-candidates.sh — one-shot, idempotent repair for
the 2026-07-30 "Requests tab isn't showing much of anything" defect: every
amendment_candidate stuck at classification=pending (because the async LLM
classifier hangs 100% of the time in production) gets resolved+classified by
the same deterministic classifier the forward-fix now runs on every NEW
capture, and a genuinely new topic is promoted into its own top-level
request instead of staying buried forever.

Usage:
  backfill-classify-amendment-candidates.sh              Report only (default = --dry-run).
  backfill-classify-amendment-candidates.sh --dry-run     Explicit report-only.
  backfill-classify-amendment-candidates.sh --apply       Actually classify/promote via ask-registry.sh.
  backfill-classify-amendment-candidates.sh [--dry-run|--apply] --limit N
                                                           Process at most N still-pending candidates.
  backfill-classify-amendment-candidates.sh --self-test   Run the sandboxed self-test suite.

NEVER rewrites or deletes ask-registry.jsonl — every repair is a new
appended record via ask-registry.sh's own classify-candidate/register verbs
(one-writer discipline). Idempotent: a candidate already carrying ANY
candidate_classified record is skipped on every subsequent run.
USAGE
    exit 0
    ;;
  *)
    echo "backfill-classify-amendment-candidates.sh: unknown argument '$1' (run --help for usage)" >&2
    exit 2
    ;;
esac
