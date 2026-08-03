#!/bin/bash
# review-chain-lib.sh — THE Review Chain parser/validator (gated-pipeline-master
# 2026-08, Task 1; docs/plans/gated-pipeline-master-2026-08.md Task 1; design
# docs/designs/gated-pipeline-master-2026-08-03.md §4, REQ-B6).
#
# ============================================================
# WHY THIS EXISTS
# ============================================================
# D-15 (docs/handoffs/2026-08-03-EXHAUSTIVE-issue-inventory.md): every pipeline
# transition (design -> plan -> build -> deploy) must carry mechanical proof its
# predecessor's review ran and passed. "Review-linked" (a doc that NAMES a review
# file) is not "review-performed" (a doc a real reviewer agent actually produced,
# still describing the SAME bytes) — the old Check 17 single-link semantics let a
# self-assembled *derived* record satisfy the gate (P-30, PROVEN). This lib is the
# ONE validity oracle (REQ-B6) every gate/check in the pipeline consumes (G1, G2,
# G3, plan-reviewer Checks 20-22) — exactly one implementation, so no two callers
# can silently drift (the M-3 "no second implementation" rule).
#
# ============================================================
# THE THREE VALIDITY RULES (design §4 — read that section for full rationale)
# ============================================================
#   RULE 1 — record parse: the record: file exists, its LAST `## Verdict:` /
#     `## Delta Verdict:` heading (amendment rounds append a later heading — the
#     real gated-pipeline review records open REFORMULATE and close with an
#     amendment-confirmed PASS; the FINAL heading in the file wins) equals the
#     chain's declared verdict, AND the record's own `**Reviewer:**` line's base
#     agent-name token (the leading word, before any " (" annotation) equals the
#     chain's declared reviewer's base token. A record that is honest about being
#     self-derived (its Reviewer line names no real dispatched agent) fails HERE.
#   RULE 2 — three-way anchor match: chain-declared blob == the blob the record's
#     own `**Reviewed:** <path> @ <blob>` header attests == `git hash-object` of
#     the artifact at HEAD right now. Because the attested blob lives in the
#     REVIEWER's own record, an author cannot re-anchor by editing one hex string
#     in the chain: re-anchoring requires a fresh record, which rule 3 ties to a
#     fresh reviewer dispatch. Plan-side bytes are CANONICALIZED (this file's own
#     `## Review Chain` + `## In-flight scope updates` sections excluded) — both
#     comparison sides are computed the SAME way (rc_blob_of), so appending a
#     chain entry never self-invalidates the anchor, and the record's attested
#     blob for a plan is likewise the canonicalized blob (a raw-file attestation
#     could never three-way-match, since appending the chain entry changes the
#     raw blob). A mismatch WARNs during the calibration window
#     (RC_ANCHOR_CALIBRATION_END_DATE — unset means "still calibrating", the
#     conservative shipped default) and FAILs once that date has passed.
#     Inflight visibility (delta-D3): the chain also carries an `inflight-blob:`
#     hash of the excluded In-flight section; a change there is a SEPARATE,
#     WARN-ONLY check — never a rule-2 failure, never a block — because that
#     section is deliberately excluded from the anchor so appending scope updates
#     never self-invalidates it (the P-32 side door stays visible, never silent).
#   RULE 3 — dispatch-ledger cross-check: a completion row in the ledger
#     (RC_LEDGER_PATH, schema {subagent_type, model, ts, session_id, artifact_ref}
#     — the SAME schema Task 15's workstreams-emit.sh writer produces, quoted here
#     as the shared fixture contract) matches the entry's reviewer TYPE, and (when
#     the row's artifact_ref is non-empty) the reviewed artifact's path, and `ts`
#     falls in the window [artifact's first commit, record's HEAD commit time]. An
#     empty artifact_ref satisfies type-match only — the DEGRADED form, always
#     named as such in output, never silently equated with a real match. Records
#     whose OWN first-commit time (`git log --follow`, never a self-declared
#     header date — that would reopen the backdating seam) predates
#     RC_LEDGER_LANDING_DATE are EXEMPT from this rule entirely (rules 1-2 still
#     apply in full) — this is how every review record written before the ledger
#     existed (REQ-B14 / Task 15, including this plan's own bootstrap records)
#     stays valid instead of retroactively failing the moment this lib ships.
#
# ============================================================
# CONFIGURATION (env-overridable; --self-test overrides all of these in its own
# sandboxed subshell scope — never touches a real machine's state)
# ============================================================
#   RC_LEDGER_PATH                  dispatch-ledger.jsonl location.
#                                    default: ~/.claude/state/dispatch-ledger.jsonl
#   RC_LEDGER_LANDING_DATE           ISO YYYY-MM-DD. SET to 2026-08-03 as of the
#                                    commit that lands Task 15 (REQ-B14 —
#                                    workstreams-emit.sh's `--on-builder-complete`
#                                    ledger writer; this is that boundary, named
#                                    per this file's own rule-3 comment above:
#                                    "records whose... first-commit time...
#                                    predates RC_LEDGER_LANDING_DATE are EXEMPT").
#                                    Every review record whose OWN first-commit
#                                    predates this date (including every
#                                    gated-pipeline bootstrap record written
#                                    before the ledger existed) stays exempt from
#                                    rule 3 forever; every record first-committed
#                                    ON or AFTER this date must clear rule 3 in
#                                    full. Empty would mean "unset — treated as
#                                    in the far future, every record exempt" (the
#                                    same flip-in-data pattern as G2's own
#                                    gate-landing date) — that was the correct
#                                    shipped default before this commit, when no
#                                    writer existed yet to produce real rows.
#   RC_ANCHOR_CALIBRATION_END_DATE   ISO YYYY-MM-DD. Empty (shipped default) means
#                                    "still calibrating" — rule-2 mismatches WARN,
#                                    never hard-FAIL, until an operator sets this
#                                    (the HR-F7 "no prose flips, only data" rule).
#
# ============================================================
# PUBLIC API
# ============================================================
#   rc_chain_present <artifact-file>     rc 0 iff a `## Review Chain` section
#                                         exists in the file.
#   rc_validate_chain <plan-file>        validates every design-reviews +
#     plan-reviews entry in <plan-file>'s Review Chain block, plus the
#     inflight-blob visibility check. Sets globals (NOT via $() — a subshell
#     would lose them, the spawn-worktree.sh `decide()` convention):
#       RC_VERDICT       PASS | WARN | FAIL
#       RC_REASON        one-line human summary (first failing/warning detail —
#                         a gate's WHY field)
#       RC_DETAIL_LINES  bash array, one line per rule check performed:
#                         "[PASS|WARN|FAIL] <role> reviewer=<name> rule<N>: <why>"
#     Return code: 0 for PASS or WARN, 1 for FAIL (WARN is a passing gate
#     decision that still surfaces detail — inspect RC_VERDICT to distinguish
#     PASS from WARN; a caller that only checks $? treats both as "proceed").
#
# Lower-level helpers (rc_record_*, rc_chain_*, rc_blob_of, rc_rule1/2/3) are
# documented at their own definitions below — useful individually for a caller
# building a more granular report (e.g. the three-variant demo, Task 17).

# NOTE: this lib deliberately does NOT `set -u`/`set -e` at source time (same
# convention as lib/gate-contract-lib.sh and lib/single-flight-lib.sh — a
# sourced lib must never change the CALLING script's shell options out from
# under it). Every function below is written to tolerate unset callers'
# variables on its own (`${VAR:-}` / `: "${VAR:=default}"`), and every rule
# function's nonzero return is a MEANINGFUL result (fail/warn), not an error —
# a caller (including this file's own --self-test) must never wrap calls to
# rc_rule1/rc_rule2/rc_rule3/rc_validate_chain in a `set -e` context without
# explicitly tolerating their nonzero returns.

: "${RC_LEDGER_PATH:=$HOME/.claude/state/dispatch-ledger.jsonl}"
# 2026-08-03: Task 15 (REQ-B14) lands the ledger WRITER
# (workstreams-emit.sh --on-builder-complete) in this same commit — this date
# is the rule-3 pre-ledger exemption boundary the comment above documents.
# 2026-08-04, not -03: the ledger WRITER went live on master mid-day 2026-08-03
# (T15 merge). The exemption is day-granular, so a -03 boundary would subject
# that same day's EARLIER records (the design/plan reviews, committed hours
# before the writer existed) to a rule-3 check no honest row can satisfy —
# caught live by Check 22 FAILing on the gated-pipeline plan's own chain at the
# T14+T15 merge. Records first-committed 2026-08-04+ are fully enforced.
: "${RC_LEDGER_LANDING_DATE:=2026-08-04}"
: "${RC_ANCHOR_CALIBRATION_END_DATE:=}"

# ============================================================
# Record-field parsers
# ============================================================

# rc_record_verdict <record-file> — echoes the LAST `## Verdict:` or
# `## Delta Verdict:` heading's token (amendment rounds append a later heading;
# the final one in the file is authoritative — see the r3 gated-pipeline plan-
# fidelity review record, which opens REFORMULATE and closes PASS).
rc_record_verdict() {
  local f="$1"
  [[ -f "$f" ]] || return 1
  grep -E '^## (Delta )?Verdict:' "$f" 2>/dev/null | tail -1 \
    | sed -E 's/^## (Delta )?Verdict:[[:space:]]*//'
}

# rc__base_token <text> — the leading agent-name word (stops at the first
# space, '(', or other non-identifier character). Used on BOTH a chain entry's
# declared `reviewer:` field and a record's `**Reviewer:**` line, so annotated
# forms ("harness-reviewer (role: plan-fidelity, bootstrap per design §8.1)")
# compare correctly against the plain agent name.
rc__base_token() {
  printf '%s' "$1" | sed -E 's/^([A-Za-z0-9_-]+).*/\1/'
}

# rc_record_reviewer <record-file> — echoes the base token of the record's own
# `**Reviewer:**` line. Empty output (rc 1) means no such line exists — the
# honest-derived-record failure mode (rule 1).
rc_record_reviewer() {
  local f="$1" line
  [[ -f "$f" ]] || return 1
  line="$(grep -m1 -E '^\*\*Reviewer:\*\*' "$f" 2>/dev/null | sed -E 's/^\*\*Reviewer:\*\*[[:space:]]*//')"
  [[ -n "$line" ]] || return 1
  rc__base_token "$line"
}

# rc_record_attested <record-file> — echoes "path<TAB>blob" parsed from the
# record's own `**Reviewed:** <path> @ <blob>` header line (the field rule 2's
# three-way match anchors to). rc 1 if the header line or its '@' is absent.
rc_record_attested() {
  local f="$1" line path blob
  [[ -f "$f" ]] || return 1
  line="$(grep -m1 -E '^\*\*Reviewed:\*\*' "$f" 2>/dev/null | sed -E 's/^\*\*Reviewed:\*\*[[:space:]]*//')"
  [[ -n "$line" ]] || return 1
  [[ "$line" == *"@"* ]] || return 1
  path="$(printf '%s' "$line" | sed -E 's/[[:space:]]*@.*//')"
  blob="$(printf '%s' "$line" | sed -E 's/^[^@]*@[[:space:]]*//' | awk '{print $1}' | tr -d '`')"
  [[ -n "$blob" ]] || return 1
  printf '%s\t%s\n' "$path" "$blob"
}

# rc_file_first_commit_epoch <file> — epoch of the file's first commit in this
# repo's history (`--follow`, never a self-declared header date). Generic over
# ANY tracked file — used on a RECORD for the rule-3 pre-ledger exemption
# boundary, and on the REVIEWED ARTIFACT for rule 3's window lower bound
# (FM-023 fix: these are two different files with two different first-commit
# times; conflating them collapses the window — see rc_rule3 below).
rc_file_first_commit_epoch() {
  # --find-renames=100%: `--follow`'s DEFAULT similarity threshold (~50%) can
  # mis-trace a file's history across an UNRELATED file that happens to share
  # boilerplate structure (the review-record template's fixed fields — this
  # was observed directly during this lib's own self-test development).
  # Pinning renames to exact-content-match keeps `--follow`'s real job (a
  # file genuinely moved/renamed keeps its true first-commit time) without
  # false-positive cross-file attribution.
  git log --follow --find-renames=100% --format=%ct -- "$1" 2>/dev/null | tail -1
}

# rc_record_head_commit_epoch <record-file> — epoch of the file's most recent
# commit at HEAD ("the record's commit time" in rule 3's window).
rc_record_head_commit_epoch() {
  git log -1 --format=%ct -- "$1" 2>/dev/null
}

# ============================================================
# Canonicalization + blob helpers (rule 2)
# ============================================================

# rc_canonicalize_plan_bytes <plan-file> — stdout: the file's bytes MINUS its
# `## Review Chain` and `## In-flight scope updates` sections (heading through
# the next `## ` heading, or EOF). Both comparison sides of rule 2 for a plan
# artifact are computed through this SAME function, so appending a chain entry
# or an in-flight update never self-invalidates the anchor.
rc_canonicalize_plan_bytes() {
  awk '
    /^## Review Chain[[:space:]]*$/ { skip=1; next }
    /^## In-flight scope updates[[:space:]]*$/ { skip=1; next }
    /^## / && skip==1 { skip=0 }
    skip!=1 { print }
  ' "$1"
}

# rc_blob_of <artifact-file> <role: plan|design> — the comparison blob for
# rule 2. role=plan canonicalizes first (see above); role=design (default)
# hashes the raw file — design docs carry no Review Chain/In-flight sections
# of their own (those live on the downstream plan that reviews them).
rc_blob_of() {
  local f="$1" role="${2:-design}"
  [[ -f "$f" ]] || return 1
  if [[ "$role" == "plan" ]]; then
    rc_canonicalize_plan_bytes "$f" | git hash-object --stdin
  else
    git hash-object -- "$f"
  fi
}

# rc_inflight_section_bytes <plan-file> — stdout: ONLY the excluded In-flight
# section's body (used for the WARN-only visibility hash, never rule 2).
rc_inflight_section_bytes() {
  awk '
    /^## In-flight scope updates[[:space:]]*$/ { grab=1; next }
    /^## / && grab==1 { grab=0 }
    grab==1 { print }
  ' "$1"
}

rc_inflight_blob() {
  local f="$1"
  [[ -f "$f" ]] || return 1
  rc_inflight_section_bytes "$f" | git hash-object --stdin
}

# rc__sha_eq <a> <b> — prefix-tolerant equality (abbreviated SHAs are a
# standard git citation convention — the real gated-pipeline review records
# use 8-char commit-style prefixes in prose; this stays forward-compatible
# with both abbreviated and full 40-hex hash-object output).
rc__sha_eq() {
  local a="$1" b="$2"
  [[ -n "$a" && -n "$b" ]] || return 1
  case "$a" in "$b"*) return 0 ;; esac
  case "$b" in "$a"*) return 0 ;; esac
  return 1
}

# ============================================================
# Chain-block extraction (the `## Review Chain` section of a plan)
# ============================================================

rc_chain_present() {
  grep -qE '^## Review Chain[[:space:]]*$' "$1" 2>/dev/null
}

# rc_chain_section <artifact-file> — stdout: the raw lines of the Review Chain
# section (heading line excluded).
rc_chain_section() {
  awk '
    /^## Review Chain[[:space:]]*$/ { grab=1; next }
    /^## / && grab==1 { grab=0 }
    grab==1 { print }
  ' "$1"
}

# rc_chain_design_ref <artifact-file> — echoes "path<TAB>blob" from the
# `design-ref: <path>@<blob>` field inside the Review Chain section. rc 1 if
# absent (a plan with no design-ref, e.g. one that never required a design).
rc_chain_design_ref() {
  local line
  line="$(rc_chain_section "$1" | grep -m1 -E '^design-ref:')"
  [[ -n "$line" ]] || return 1
  line="$(printf '%s' "$line" | sed -E 's/^design-ref:[[:space:]]*//')"
  [[ "$line" == *"@"* ]] || return 1
  printf '%s\t%s\n' "${line%@*}" "${line##*@}"
}

# rc_chain_inflight_blob <artifact-file> — echoes the `inflight-blob: <sha>`
# field's value. rc 1 if absent (older chains predating delta-D3, or a design
# doc with no In-flight section at all).
rc_chain_inflight_blob() {
  local line
  line="$(rc_chain_section "$1" | grep -m1 -E '^inflight-blob:')"
  [[ -n "$line" ]] || return 1
  printf '%s' "$line" | sed -E 's/^inflight-blob:[[:space:]]*//'
}

# rc_chain_entries <artifact-file> — stdout: one TSV row per reviewer entry,
# "role<TAB>reviewer<TAB>verdict<TAB>record<TAB>planblob". role is "design" for
# entries under `design-reviews:`, "plan" under `plan-reviews:`. planblob is
# the entry's own `plan-blob:` field (empty for design entries, which anchor
# via the shared top-level design-ref instead).
rc_chain_entries() {
  rc_chain_section "$1" | awk '
    /^design-reviews:[[:space:]]*$/ { state="design"; next }
    /^plan-reviews:[[:space:]]*$/ { state="plan"; next }
    /^[a-zA-Z_-]+:/ && !/^[[:space:]]*-/ { state="" }
    /^[[:space:]]*-[[:space:]]*reviewer:/ && state!="" { print state "\t" $0 }
  ' | while IFS=$'\t' read -r role rest; do
    local reviewer verdict record planblob
    reviewer="$(printf '%s' "$rest" | sed -E 's/^[[:space:]]*-[[:space:]]*reviewer:[[:space:]]*//; s/[[:space:]]*verdict:.*//')"
    verdict="$(printf '%s' "$rest" | sed -E 's/.*verdict:[[:space:]]*([A-Za-z0-9_-]+).*/\1/')"
    record="$(printf '%s' "$rest" | sed -E 's/.*record:[[:space:]]*([^[:space:]]+).*/\1/')"
    planblob=""
    if [[ "$rest" == *"plan-blob:"* ]]; then
      planblob="$(printf '%s' "$rest" | sed -E 's/.*plan-blob:[[:space:]]*([^[:space:]]+).*/\1/')"
    fi
    printf '%s\t%s\t%s\t%s\t%s\n' "$role" "$reviewer" "$verdict" "$record" "$planblob"
  done
}

# ============================================================
# Date/epoch helpers
# ============================================================

# rc__date_to_epoch <ISO YYYY-MM-DD> — GNU `date -d` then BSD/macOS `date -j`
# fallback (the existing repo convention — harness-doctor.sh's cadence check).
rc__date_to_epoch() {
  local d="$1"
  [[ -n "$d" ]] || return 1
  date -d "$d" +%s 2>/dev/null || date -j -f "%Y-%m-%d" "$d" +%s 2>/dev/null
}

# rc_ledger_landing_epoch — rc 1 (empty stdout) if RC_LEDGER_LANDING_DATE is
# unset, meaning "treat as infinitely future" — every record is pre-ledger.
rc_ledger_landing_epoch() {
  [[ -n "$RC_LEDGER_LANDING_DATE" ]] || return 1
  rc__date_to_epoch "$RC_LEDGER_LANDING_DATE"
}

# rc_calibration_end_epoch — rc 1 (empty stdout) if RC_ANCHOR_CALIBRATION_END_DATE
# is unset, meaning "still calibrating" — rule-2 mismatches always WARN.
rc_calibration_end_epoch() {
  [[ -n "$RC_ANCHOR_CALIBRATION_END_DATE" ]] || return 1
  rc__date_to_epoch "$RC_ANCHOR_CALIBRATION_END_DATE"
}

# ============================================================
# The three validity rules
# ============================================================

# rc_rule1 <record-file> <expected-verdict> <expected-reviewer-token>
# stdout: one-line reason. rc 0 pass, 1 fail.
rc_rule1() {
  local record="$1" exp_verdict="$2" exp_reviewer="$3"
  local got_verdict got_reviewer
  if [[ ! -f "$record" ]]; then
    echo "record file not found: $record"
    return 1
  fi
  got_verdict="$(rc_record_verdict "$record")"
  if [[ -z "$got_verdict" ]]; then
    echo "no ## Verdict: (or ## Delta Verdict:) heading in $record"
    return 1
  fi
  if [[ "$got_verdict" != "$exp_verdict" ]]; then
    echo "record's final verdict '$got_verdict' != chain-declared '$exp_verdict'"
    return 1
  fi
  got_reviewer="$(rc_record_reviewer "$record")"
  if [[ -z "$got_reviewer" ]]; then
    echo "no **Reviewer:** line in $record (an honest-derived record fails here — no real agent named)"
    return 1
  fi
  if [[ "$got_reviewer" != "$exp_reviewer" ]]; then
    echo "record's Reviewer '$got_reviewer' != chain-declared '$exp_reviewer'"
    return 1
  fi
  echo "record parses; verdict=$got_verdict reviewer=$got_reviewer"
  return 0
}

# rc_rule2 <artifact-file> <role: plan|design> <chain-anchor-blob> <record-file>
# stdout: one-line reason. rc 0 pass, 1 hard-fail (past calibration), 2 warn
# (mismatch, still calibrating).
rc_rule2() {
  local artifact="$1" role="$2" chain_blob="$3" record="$4"
  local head_blob attested attested_path attested_blob reason cal_end cal_rc now
  head_blob="$(rc_blob_of "$artifact" "$role" 2>/dev/null)"
  if [[ -z "$head_blob" ]]; then
    echo "could not compute HEAD blob for $artifact (role=$role)"
    return 1
  fi
  attested="$(rc_record_attested "$record")"
  if [[ -z "$attested" ]]; then
    echo "record $record has no **Reviewed:** <path> @ <blob> header"
    return 1
  fi
  attested_path="${attested%%$'\t'*}"
  attested_blob="${attested#*$'\t'}"
  if rc__sha_eq "$chain_blob" "$head_blob" && rc__sha_eq "$chain_blob" "$attested_blob"; then
    echo "three-way match: chain=$chain_blob record-attested=$attested_blob HEAD=$head_blob"
    return 0
  fi
  reason="three-way mismatch: chain=$chain_blob record-attested=$attested_blob HEAD(role=$role)=$head_blob"
  cal_end="$(rc_calibration_end_epoch 2>/dev/null)"
  cal_rc=$?
  now="$(date +%s)"
  if [[ $cal_rc -ne 0 ]] || [[ "$now" -le "$cal_end" ]]; then
    echo "$reason -- WARN (anchor-calibration window active; RC_ANCHOR_CALIBRATION_END_DATE unset or not yet reached)"
    return 2
  fi
  echo "$reason -- FAIL (past the anchor-calibration window)"
  return 1
}

# rc_rule3 <reviewer-token> <artifact-ref-path> <artifact-file> <record-file>
# stdout: one-line reason. rc 0 pass (incl. exempt/degraded forms, both named),
# 1 fail.
#
# FM-023 (comprehension-reviewer, PROVEN): the ts-window's lower bound is the
# REVIEWED ARTIFACT's first commit, NOT the record's — design §4 rule 3 and
# this file's own header (above) both say "[artifact's first commit, record's
# HEAD commit time]". A record almost always lands in ONE commit (rules 1-2
# don't require history), so keying lo off the record collapses lo==hi to a
# single second — no realistic completion row (which fires BEFORE the record
# documenting it gets committed) can ever land inside that window. <artifact>
# is now a required 3rd argument so the caller (rc_validate_chain, which
# already has this path — the same value it passes to rc_rule2) supplies it.
rc_rule3() {
  local reviewer="$1" artifact_ref="$2" artifact="$3" record="$4"
  local record_first_commit landing_epoch landing_rc artifact_first_commit head_commit lo hi
  local row rt rts rref match_degraded match_full skipped_malformed
  # The PRE-LEDGER EXEMPTION is keyed on the RECORD's own first-commit time
  # (design: "records whose OWN first-commit time... predates
  # RC_LEDGER_LANDING_DATE are EXEMPT") — this is deliberately NOT the
  # artifact's first commit; a long-lived artifact reviewed for the first
  # time post-ledger must NOT inherit an old exemption from its own history.
  record_first_commit="$(rc_file_first_commit_epoch "$record")"
  landing_epoch="$(rc_ledger_landing_epoch 2>/dev/null)"
  landing_rc=$?
  if [[ $landing_rc -ne 0 ]]; then
    echo "EXEMPT: RC_LEDGER_LANDING_DATE unset (ledger not yet landed — Task 15) — every record is pre-ledger"
    return 0
  fi
  if [[ -n "$record_first_commit" ]] && [[ "$record_first_commit" -lt "$landing_epoch" ]]; then
    echo "EXEMPT: record's first commit ($record_first_commit) predates ledger-landing ($landing_epoch)"
    return 0
  fi
  if [[ ! -f "$RC_LEDGER_PATH" ]]; then
    echo "FAIL: no dispatch ledger at $RC_LEDGER_PATH (reviewer type=$reviewer never dispatched, or ledger missing)"
    return 1
  fi
  # THE WINDOW: [reviewed artifact's first commit, record's HEAD commit time]
  # — two DIFFERENT files, two different git-log calls. (FM-023: previously
  # both bounds were derived from the record, collapsing the window.)
  artifact_first_commit="$(rc_file_first_commit_epoch "$artifact")"
  head_commit="$(rc_record_head_commit_epoch "$record")"
  lo="${artifact_first_commit:-0}"
  hi="${head_commit:-9999999999}"
  match_degraded=0
  match_full=0
  skipped_malformed=0
  while IFS= read -r row; do
    [[ -n "$row" ]] || continue
    rt="$(printf '%s' "$row" | jq -r '.subagent_type // empty' 2>/dev/null)"
    [[ "$rt" == "$reviewer" ]] || continue
    rts="$(printf '%s' "$row" | jq -r '.ts // empty' 2>/dev/null)"
    [[ -n "$rts" ]] || continue
    # Fail-open on a malformed ts (plan's Behavioral Contracts: never silent,
    # never fail-closed on a data-shape error) — skip THIS row, not the whole
    # rule, and say so, rather than letting `[[ "$rts" -lt "$lo" ]]` abort
    # with a bash "integer expression expected" error on a non-numeric value.
    if ! [[ "$rts" =~ ^-?[0-9]+$ ]]; then
      skipped_malformed=1
      continue
    fi
    if [[ "$rts" -lt "$lo" ]] || [[ "$rts" -gt "$hi" ]]; then
      continue
    fi
    rref="$(printf '%s' "$row" | jq -r '.artifact_ref // empty' 2>/dev/null)"
    if [[ -z "$rref" ]]; then
      match_degraded=1
    elif [[ "$rref" == "$artifact_ref" ]]; then
      match_full=1
      break
    fi
  done < "$RC_LEDGER_PATH"
  local malformed_note=""
  [[ "$skipped_malformed" == 1 ]] && malformed_note=" -- WARN: at least one row for type=$reviewer had a non-numeric ts and was skipped (degraded ledger data, fail-open per the plan's Behavioral Contracts)"
  if [[ "$match_full" == 1 ]]; then
    echo "PASS: ledger row matches type=$reviewer artifact_ref=$artifact_ref within window [$lo,$hi]$malformed_note"
    return 0
  fi
  if [[ "$match_degraded" == 1 ]]; then
    echo "PASS (DEGRADED: type-match only — ledger row had an empty artifact_ref) type=$reviewer$malformed_note"
    return 0
  fi
  echo "FAIL: no dispatch-ledger row for type=$reviewer artifact_ref=$artifact_ref within window [$lo,$hi] (never dispatched, or wrong artifact_ref)$malformed_note"
  return 1
}

# ============================================================
# Top-level: validate an entire plan's Review Chain block
# ============================================================

rc_validate_chain() {
  local plan="$1"
  RC_VERDICT="PASS"
  RC_REASON=""
  RC_DETAIL_LINES=()
  local any_fail=0 any_warn=0 saw_any_entry=0
  local design_ref design_path="" design_blob=""

  if ! rc_chain_present "$plan"; then
    RC_VERDICT="FAIL"
    RC_REASON="no ## Review Chain section found in $plan"
    RC_DETAIL_LINES+=("[FAIL] chain-presence: $RC_REASON")
    return 1
  fi

  design_ref="$(rc_chain_design_ref "$plan" 2>/dev/null)"
  if [[ -n "$design_ref" ]]; then
    design_path="${design_ref%%$'\t'*}"
    design_blob="${design_ref#*$'\t'}"
  fi

  local role reviewer verdict record planblob
  local reviewer_token artifact anchor artifact_ref rule_out rule_rc
  while IFS=$'\t' read -r role reviewer verdict record planblob; do
    [[ -n "$role" ]] || continue
    saw_any_entry=1
    reviewer_token="$(rc__base_token "$reviewer")"

    if [[ "$role" == "design" ]]; then
      if [[ -z "$design_path" ]]; then
        RC_DETAIL_LINES+=("[FAIL] design reviewer=$reviewer_token rule2: design-reviews entry present but no design-ref: field in the chain")
        any_fail=1
        continue
      fi
      artifact="$design_path"
      anchor="$design_blob"
      artifact_ref="$design_path"
    else
      artifact="$plan"
      anchor="$planblob"
      artifact_ref="$plan"
    fi

    rule_out="$(rc_rule1 "$record" "$verdict" "$reviewer_token")"
    rule_rc=$?
    if [[ $rule_rc -ne 0 ]]; then
      RC_DETAIL_LINES+=("[FAIL] $role reviewer=$reviewer_token rule1: $rule_out")
      any_fail=1
      continue
    fi
    RC_DETAIL_LINES+=("[PASS] $role reviewer=$reviewer_token rule1: $rule_out")

    if [[ -z "$anchor" ]]; then
      RC_DETAIL_LINES+=("[FAIL] $role reviewer=$reviewer_token rule2: no chain-side anchor blob to compare (missing design-ref@blob or plan-blob:)")
      any_fail=1
      continue
    fi
    rule_out="$(rc_rule2 "$artifact" "$role" "$anchor" "$record")"
    rule_rc=$?
    case $rule_rc in
      0) RC_DETAIL_LINES+=("[PASS] $role reviewer=$reviewer_token rule2: $rule_out") ;;
      2) RC_DETAIL_LINES+=("[WARN] $role reviewer=$reviewer_token rule2: $rule_out"); any_warn=1 ;;
      *) RC_DETAIL_LINES+=("[FAIL] $role reviewer=$reviewer_token rule2: $rule_out"); any_fail=1; continue ;;
    esac

    rule_out="$(rc_rule3 "$reviewer_token" "$artifact_ref" "$artifact" "$record")"
    rule_rc=$?
    if [[ $rule_rc -ne 0 ]]; then
      RC_DETAIL_LINES+=("[FAIL] $role reviewer=$reviewer_token rule3: $rule_out")
      any_fail=1
      continue
    fi
    RC_DETAIL_LINES+=("[PASS] $role reviewer=$reviewer_token rule3: $rule_out")
  done < <(rc_chain_entries "$plan")

  if [[ "$saw_any_entry" != 1 ]]; then
    RC_VERDICT="FAIL"
    RC_REASON="## Review Chain section present but contains no parseable reviewer entries in $plan"
    RC_DETAIL_LINES+=("[FAIL] chain-entries: $RC_REASON")
    return 1
  fi

  # Inflight visibility (WARN-only, never a failure — design §4 delta-D3).
  local chain_inflight cur_inflight
  chain_inflight="$(rc_chain_inflight_blob "$plan" 2>/dev/null)"
  if [[ -n "$chain_inflight" ]]; then
    cur_inflight="$(rc_inflight_blob "$plan" 2>/dev/null)"
    if ! rc__sha_eq "$chain_inflight" "$cur_inflight"; then
      RC_DETAIL_LINES+=("[WARN] inflight-blob: chain=$chain_inflight current=$cur_inflight (In-flight scope updates changed since the last chain anchor — never a failure; the next fidelity re-anchor covers it)")
      any_warn=1
    fi
  fi

  if [[ "$any_fail" == 1 ]]; then
    RC_VERDICT="FAIL"
  elif [[ "$any_warn" == 1 ]]; then
    RC_VERDICT="WARN"
  else
    RC_VERDICT="PASS"
  fi
  RC_REASON="$(printf '%s\n' "${RC_DETAIL_LINES[@]}" | grep -m1 -E '^\[(FAIL|WARN)\]')"
  [[ -n "$RC_REASON" ]] || RC_REASON="all review-chain entries valid"
  if [[ "$RC_VERDICT" == "FAIL" ]]; then
    return 1
  fi
  return 0
}

# ============================================================
# --self-test (direct-execution guard — same convention as
# lib/gate-contract-lib.sh: only runs when this file is executed directly).
# Builds its OWN throwaway git repo (mktemp -d; git init) with controlled
# commit timestamps — the spawn-worktree.sh --self-test pattern — so rule 3's
# first-commit-time semantics are exercised for real, never faked, and this
# self-test never touches the real repo's history or a real dispatch ledger.
# ============================================================
if [[ "${BASH_SOURCE[0]:-$0}" == "${0}" ]] && [[ "${1:-}" == "--self-test" ]]; then
  # Deliberately NOT `set -e`: every rc_rule*/rc_validate_chain call below
  # returns nonzero BY DESIGN for fail/warn scenarios — that is the behavior
  # under test, not an error to abort on. Fatal setup steps are checked
  # explicitly instead.
  T=$(mktemp -d) || { echo "self-test: mktemp failed" >&2; exit 3; }
  trap 'rm -rf "$T" 2>/dev/null || true' EXIT
  # Resolved BEFORE the `cd "$R"` below (Scenario 11 needs it, and this
  # file's own directory is meaningless once cwd moves into the throwaway
  # repo) -- mirrors workstreams-emit.sh's own $SELF self-resolution.
  WSE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." 2>/dev/null && pwd)/workstreams-emit.sh"
  R="$T/repo"
  git init -q -b master "$R" || { echo "self-test: git init failed" >&2; exit 3; }
  cd "$R" || { echo "self-test: cd to temp repo failed" >&2; exit 3; }
  git config user.email t@example.com
  git config user.name t
  git config core.autocrlf false
  mkdir -p docs/plans docs/reviews .claude-state

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

  # Global calibration state for the whole suite: past both dates, so rule-2
  # mismatches hard-FAIL (not WARN) and the ledger is fully "landed" for every
  # normally-dated commit — matching the plan's fixture list, which names
  # unconditional FAILs for the mismatch scenarios, not WARNs.
  export RC_ANCHOR_CALIBRATION_END_DATE="2020-01-01"
  export RC_LEDGER_LANDING_DATE="2026-01-01"
  export RC_LEDGER_PATH="$R/.claude-state/dispatch-ledger.jsonl"
  : > "$RC_LEDGER_PATH"

  # --- helper: writes a minimal fixture plan with one plan-reviews entry ----
  _write_plan() { # <path> <reviewer> <verdict> <record-path> <planblob> <inflight-blob-field-or-empty> <body-extra>
    local path="$1" reviewer="$2" verdict="$3" record="$4" planblob="$5" inflight="$6" extra="${7:-}"
    {
      echo "# Fixture plan"
      echo "Status: ACTIVE"
      echo
      echo "## Review Chain"
      echo "plan-reviews:"
      echo "  - reviewer: $reviewer  verdict: $verdict  record: $record  plan-blob: $planblob"
      [[ -n "$inflight" ]] && echo "inflight-blob: $inflight"
      echo
      echo "## Body"
      echo "fixture content $extra"
      echo
      echo "## In-flight scope updates"
      echo "line A"
    } > "$path"
  }

  _write_record() { # <path> <reviewer-line> <reviewed-path> <reviewed-blob> <verdict>
    local path="$1" reviewer_line="$2" reviewed_path="$3" reviewed_blob="$4" verdict="$5"
    {
      echo "# Fixture Review Record"
      echo "**Reviewer:** $reviewer_line"
      echo "**Reviewed:** $reviewed_path @ $reviewed_blob"
      echo "**Reviewed at:** 2026-08-03"
      echo
      echo "## Verdict: $verdict"
    } > "$path"
  }

  _commit() { # <message> [<iso-date-for-backdating>]
    if [[ -n "${2:-}" ]]; then
      GIT_AUTHOR_DATE="${2}T00:00:00+00:00" GIT_COMMITTER_DATE="${2}T00:00:00+00:00" \
        git -c commit.gpgsign=false commit -q -m "$1"
    else
      git -c commit.gpgsign=false commit -q -m "$1"
    fi
  }

  _ledger_row() { # <subagent_type> <ts> <artifact_ref>
    printf '{"subagent_type":"%s","model":"claude-fable-5","ts":%s,"session_id":"selftest","artifact_ref":"%s"}\n' "$1" "$2" "$3" >> "$RC_LEDGER_PATH"
  }

  # ── Scenario 1: honest-derived record FAILS rule 1 ────────────────────────
  P=docs/plans/f1.md
  _write_plan "$P" "architecture-reviewer" "PASS" "docs/reviews/f1-record.md" "PENDING" ""
  git add "$P" >/dev/null
  _commit "f1 plan"
  BLOB="$(rc_blob_of "$P" plan)"
  sed -i "s/PENDING/$BLOB/" "$P"
  _write_record docs/reviews/f1-record.md "derived-by-author (no agent dispatched — self-assembled)" "$P" "$BLOB" "PASS"
  git add "$P" docs/reviews/f1-record.md >/dev/null
  _commit "f1 record (honest-derived)"
  rc_validate_chain "$P"
  _st "s1-honest-derived-fails" "FAIL" "$RC_VERDICT"

  # ── Scenario 2: never-dispatched reviewer FAILS rule 3 ─────────────────────
  P=docs/plans/f2.md
  _write_plan "$P" "architecture-reviewer" "SOUND" "docs/reviews/f2-record.md" "PENDING" ""
  git add "$P" >/dev/null
  _commit "f2 plan"
  BLOB="$(rc_blob_of "$P" plan)"
  sed -i "s/PENDING/$BLOB/" "$P"
  _write_record docs/reviews/f2-record.md "architecture-reviewer (model: fable, dispatched by session x)" "$P" "$BLOB" "SOUND"
  git add "$P" docs/reviews/f2-record.md >/dev/null
  _commit "f2 record"
  # no ledger row at all for architecture-reviewer
  rc_validate_chain "$P"
  _st "s2-never-dispatched-fails" "FAIL" "$RC_VERDICT"

  # ── Scenario 3: author-re-anchored chain without a fresh record FAILS rule 2
  P=docs/plans/f3.md
  _write_plan "$P" "architecture-reviewer" "SOUND" "docs/reviews/f3-record.md" "PENDING" ""
  git add "$P" >/dev/null
  _commit "f3 plan v1"
  BLOB_V1="$(rc_blob_of "$P" plan)"
  sed -i "s/PENDING/$BLOB_V1/" "$P"
  _write_record docs/reviews/f3-record.md "architecture-reviewer (model: fable)" "$P" "$BLOB_V1" "SOUND"
  git add "$P" docs/reviews/f3-record.md >/dev/null
  _commit "f3 record for v1"
  RTS="$(rc_record_head_commit_epoch docs/reviews/f3-record.md)"
  _ledger_row "architecture-reviewer" "$RTS" "$P"
  # Author edits the body (new bytes) and re-anchors the chain's plan-blob to
  # match — WITHOUT a fresh record. Rule 1/3 still reference the SAME (old)
  # record, which now attests the WRONG (v1) blob against the NEW (v2) HEAD.
  sed -i "s/fixture content /fixture content EDITED /" "$P"
  BLOB_V2="$(rc_blob_of "$P" plan)"
  sed -i "s/$BLOB_V1/$BLOB_V2/" "$P"
  git add "$P" >/dev/null
  _commit "f3 plan v2 (re-anchored, no fresh record)"
  rc_validate_chain "$P"
  _st "s3-reanchor-without-fresh-record-fails" "FAIL" "$RC_VERDICT"

  # ── Scenario 4: wrong-artifact-ref row FAILS rule 3 ─────────────────────────
  P=docs/plans/f4.md
  _write_plan "$P" "architecture-reviewer" "SOUND" "docs/reviews/f4-record.md" "PENDING" ""
  git add "$P" >/dev/null
  _commit "f4 plan"
  BLOB="$(rc_blob_of "$P" plan)"
  sed -i "s/PENDING/$BLOB/" "$P"
  _write_record docs/reviews/f4-record.md "architecture-reviewer (model: fable)" "$P" "$BLOB" "SOUND"
  git add "$P" docs/reviews/f4-record.md >/dev/null
  _commit "f4 record"
  RTS="$(rc_record_head_commit_epoch docs/reviews/f4-record.md)"
  _ledger_row "architecture-reviewer" "$RTS" "docs/plans/some-other-plan.md"
  rc_validate_chain "$P"
  _st "s4-wrong-artifact-ref-fails" "FAIL" "$RC_VERDICT"

  # ── Scenario 5: pre-ledger-dated record PASSES rules 1-2, exempt from 3 ────
  P=docs/plans/f5.md
  _write_plan "$P" "architecture-reviewer" "SOUND" "docs/reviews/f5-record.md" "PENDING" ""
  git add "$P" >/dev/null
  _commit "f5 plan" "2025-06-01"
  BLOB="$(rc_blob_of "$P" plan)"
  sed -i "s/PENDING/$BLOB/" "$P"
  _write_record docs/reviews/f5-record.md "architecture-reviewer (model: fable)" "$P" "$BLOB" "SOUND"
  git add "$P" docs/reviews/f5-record.md >/dev/null
  _commit "f5 record (pre-ledger)" "2025-06-01"
  # no ledger row needed — first-commit (2025-06-01) predates RC_LEDGER_LANDING_DATE (2026-01-01)
  rc_validate_chain "$P"
  _st "s5-pre-ledger-passes" "PASS" "$RC_VERDICT"

  # ── Scenario 6: stale anchor FAILS (post-calibration mode) ─────────────────
  P=docs/plans/f6.md
  _write_plan "$P" "architecture-reviewer" "SOUND" "docs/reviews/f6-record.md" "PENDING" ""
  git add "$P" >/dev/null
  _commit "f6 plan v1"
  BLOB_V1="$(rc_blob_of "$P" plan)"
  sed -i "s/PENDING/$BLOB_V1/" "$P"
  _write_record docs/reviews/f6-record.md "architecture-reviewer (model: fable)" "$P" "$BLOB_V1" "SOUND"
  git add "$P" docs/reviews/f6-record.md >/dev/null
  _commit "f6 record for v1"
  RTS="$(rc_record_head_commit_epoch docs/reviews/f6-record.md)"
  _ledger_row "architecture-reviewer" "$RTS" "$P"
  # Content drifts (body edited); the chain's plan-blob is NEVER updated —
  # chain-anchor == record-attested == BLOB_V1, but HEAD is now BLOB_V2.
  sed -i "s/fixture content /fixture content DRIFTED /" "$P"
  git add "$P" >/dev/null
  _commit "f6 plan v2 (content drifted, chain never touched)"
  rc_validate_chain "$P"
  _st "s6-stale-anchor-fails-post-calibration" "FAIL" "$RC_VERDICT"

  # ── Scenario 7: inflight change -> ledgered WARN, still passes ─────────────
  P=docs/plans/f7.md
  _write_plan "$P" "architecture-reviewer" "SOUND" "docs/reviews/f7-record.md" "PENDING" "IBPENDING"
  git add "$P" >/dev/null
  _commit "f7 plan v1"
  BLOB="$(rc_blob_of "$P" plan)"
  IBLOB_V1="$(rc_inflight_blob "$P")"
  sed -i "s/PENDING/$BLOB/; s/IBPENDING/$IBLOB_V1/" "$P"
  git add "$P" >/dev/null
  _commit "f7 plan v1 anchored"
  # NOTE: editing the plan-blob placeholder above did not change the
  # canonicalized bytes (the chain/inflight sections are excluded from
  # canonicalization), so BLOB computed before this edit still matches HEAD.
  _write_record docs/reviews/f7-record.md "architecture-reviewer (model: fable)" "$P" "$BLOB" "SOUND"
  git add docs/reviews/f7-record.md >/dev/null
  _commit "f7 record"
  RTS="$(rc_record_head_commit_epoch docs/reviews/f7-record.md)"
  _ledger_row "architecture-reviewer" "$RTS" "$P"
  # Now edit ONLY the In-flight section — canonicalized plan-blob is
  # unaffected (rule 2 still matches), but the inflight-blob field is now
  # stale relative to the real section content.
  sed -i "s/^line A\$/line A\nline B/" "$P"
  git add "$P" >/dev/null
  _commit "f7 plan v2 (in-flight scope updated only)"
  rc_validate_chain "$P"
  _st "s7-inflight-change-warns" "WARN" "$RC_VERDICT"
  IFOUND=0
  for l in "${RC_DETAIL_LINES[@]}"; do [[ "$l" == "[WARN] inflight-blob:"* ]] && IFOUND=1; done
  _st "s7-inflight-warn-detail-present" "1" "$IFOUND"

  # ── Scenario 8: fully valid chain PASSES ────────────────────────────────────
  P=docs/plans/f8.md
  _write_plan "$P" "architecture-reviewer" "SOUND-WITH-AMENDMENTS" "docs/reviews/f8-record.md" "PENDING" ""
  git add "$P" >/dev/null
  _commit "f8 plan"
  BLOB="$(rc_blob_of "$P" plan)"
  sed -i "s/PENDING/$BLOB/" "$P"
  _write_record docs/reviews/f8-record.md "architecture-reviewer (model: fable, dispatched by session x)" "$P" "$BLOB" "SOUND-WITH-AMENDMENTS"
  git add "$P" docs/reviews/f8-record.md >/dev/null
  _commit "f8 record"
  RTS="$(rc_record_head_commit_epoch docs/reviews/f8-record.md)"
  _ledger_row "architecture-reviewer" "$RTS" "$P"
  rc_validate_chain "$P"
  _st "s8-valid-chain-passes" "PASS" "$RC_VERDICT"

  # ── Scenario 9 (FM-023 regression): rule-3 window uses the ARTIFACT's first
  # commit as lo, not the record's — non-coincident timestamps t0<t1<t2, so a
  # degenerate lo==hi window (the bug: both bounds derived from the record,
  # which usually lands in one commit) would falsely reject the INSIDE row
  # too, and could never distinguish "before" from "after". Direct rc_rule3
  # calls (not rc_validate_chain) for precise, isolated window assertions.
  P=docs/plans/f9-artifact.md
  _write_plan "$P" "architecture-reviewer" "SOUND" "docs/reviews/f9-record.md" "IGNORED-NOT-PARSED-BY-RULE3" ""
  git add "$P" >/dev/null
  _commit "f9 artifact (t0)" "2026-02-01"
  BLOB="$(rc_blob_of "$P" plan)"
  T0="$(rc_file_first_commit_epoch "$P")"
  _write_record docs/reviews/f9-record.md "architecture-reviewer (model: fable)" "$P" "$BLOB" "SOUND"
  git add docs/reviews/f9-record.md >/dev/null
  _commit "f9 record (t2)" "2026-03-01"
  T2="$(rc_record_head_commit_epoch docs/reviews/f9-record.md)"
  T1_INSIDE=$(( T0 + (T2 - T0) / 2 ))          # strictly between t0 and t2
  T_BEFORE=$(( T0 - 86400 ))                    # one day before t0
  T_AFTER=$(( T2 + 86400 ))                     # one day after t2

  SAVED_LEDGER="$RC_LEDGER_PATH"

  RC_LEDGER_PATH="$T/f9-inside.jsonl"; : > "$RC_LEDGER_PATH"
  _ledger_row "architecture-reviewer" "$T1_INSIDE" "$P"
  rc_rule3 "architecture-reviewer" "$P" "$P" docs/reviews/f9-record.md >/dev/null
  _st "s9-window-inside-passes" "0" "$?"

  RC_LEDGER_PATH="$T/f9-before.jsonl"; : > "$RC_LEDGER_PATH"
  _ledger_row "architecture-reviewer" "$T_BEFORE" "$P"
  rc_rule3 "architecture-reviewer" "$P" "$P" docs/reviews/f9-record.md >/dev/null
  _st "s9-window-before-rejected" "1" "$?"

  RC_LEDGER_PATH="$T/f9-after.jsonl"; : > "$RC_LEDGER_PATH"
  _ledger_row "architecture-reviewer" "$T_AFTER" "$P"
  rc_rule3 "architecture-reviewer" "$P" "$P" docs/reviews/f9-record.md >/dev/null
  _st "s9-window-after-rejected" "1" "$?"

  # ── Scenario 10: a malformed (non-numeric) ts row is skipped, not fatal ────
  RC_LEDGER_PATH="$T/f9-malformed-only.jsonl"
  printf '{"subagent_type":"architecture-reviewer","model":"claude-fable-5","ts":"not-a-number","session_id":"selftest","artifact_ref":"%s"}\n' "$P" > "$RC_LEDGER_PATH"
  OUT="$(rc_rule3 "architecture-reviewer" "$P" "$P" docs/reviews/f9-record.md)"
  RC=$?
  _st "s10-malformed-ts-only-fails-not-crashes" "1" "$RC"
  MW=$(printf '%s' "$OUT" | grep -c "non-numeric ts")
  _st "s10-malformed-ts-warn-text-present" "1" "$MW"

  # Malformed row ALONGSIDE a genuinely valid one: the guard skips the bad
  # row and still finds the good one — fail-open never costs a real match.
  RC_LEDGER_PATH="$T/f9-malformed-plus-valid.jsonl"
  printf '{"subagent_type":"architecture-reviewer","model":"claude-fable-5","ts":"garbage","session_id":"selftest","artifact_ref":"%s"}\n' "$P" > "$RC_LEDGER_PATH"
  _ledger_row "architecture-reviewer" "$T1_INSIDE" "$P"
  OUT="$(rc_rule3 "architecture-reviewer" "$P" "$P" docs/reviews/f9-record.md)"
  RC=$?
  _st "s10-malformed-plus-valid-still-passes" "0" "$RC"
  MW=$(printf '%s' "$OUT" | grep -c "non-numeric ts")
  _st "s10-malformed-plus-valid-warn-text-present" "1" "$MW"

  RC_LEDGER_PATH="$SAVED_LEDGER"

  # ── Scenario 11 (Task 15 round-trip, REQ-B14 H1): the REAL writer's row
  # validates through rc_rule3, and a chain that only sees THAT row still
  # REJECTS when it names a DIFFERENT artifact -- binds Task 1's reader
  # (this file) to Task 15's writer (workstreams-emit.sh
  # --on-builder-complete) via the ONE shared JSONL contract quoted in this
  # file's own header above and in
  # adapters/claude-code/tests/fixtures/review-chain/README.md.
  #
  # ORDER MATTERS: the artifact commits, THEN the writer fires (a real
  # completion row lands BEFORE its record is ever written -- the record
  # documents a COMPLETED dispatch, so it can only be authored afterward),
  # THEN the record commits -- mirroring the sequence rule 3's window
  # assumes (design §4 rule 3 / the FM-023 comment above rc_rule3: "a
  # realistic completion row... fires BEFORE the record documenting it gets
  # committed").
  if [[ -f "$WSE" ]] && command -v jq >/dev/null 2>&1; then
    P=docs/plans/f11.md
    _write_plan "$P" "architecture-reviewer" "SOUND" "docs/reviews/f11-record.md" "PENDING" ""
    git add "$P" >/dev/null
    _commit "f11 plan"
    BLOB="$(rc_blob_of "$P" plan)"
    sed -i "s/PENDING/$BLOB/" "$P"
    git add "$P" >/dev/null
    _commit "f11 plan anchored"

    F11_LEDGER="$T/f11-ledger.jsonl"
    DISPATCH_LEDGER_PATH="$F11_LEDGER" CONV_TREE_STATE_PATH="$T/f11-conv-tree.json" HARNESS_SELFTEST=1 \
      bash "$WSE" --on-builder-complete <<EOF2 >/dev/null 2>&1
{"tool_name":"Task","tool_input":{"subagent_type":"architecture-reviewer","description":"Review","prompt":"Review $P"},"tool_response":"SOUND","session_id":"rc-rt-1"}
EOF2

    _write_record docs/reviews/f11-record.md "architecture-reviewer (model: fable)" "$P" "$BLOB" "SOUND"
    git add docs/reviews/f11-record.md >/dev/null
    _commit "f11 record"

    RC_LEDGER_PATH="$F11_LEDGER"
    rc_validate_chain "$P"
    _st "s11-writer-roundtrip-passes" "PASS" "$RC_VERDICT"

    if [[ -s "$F11_LEDGER" ]] && jq -e --arg p "$P" '.subagent_type=="architecture-reviewer" and .artifact_ref==$p and (.ts|type=="number")' "$F11_LEDGER" >/dev/null 2>&1; then
      echo "self-test (s11-writer-row-shape): PASS" >&2; PASSED=$((PASSED + 1))
    else
      echo "self-test (s11-writer-row-shape): FAIL (row: $(cat "$F11_LEDGER" 2>/dev/null))" >&2; FAILED=$((FAILED + 1))
    fi

    # Wrong-artifact_ref: the ledger's only row names f11.md (from the
    # writer call above). Validate a DIFFERENT plan (f11c, its own valid
    # chain otherwise) against that SAME ledger -- rule 3 must find no row
    # whose artifact_ref matches f11c's path and FAIL.
    P3=docs/plans/f11c.md
    _write_plan "$P3" "architecture-reviewer" "SOUND" "docs/reviews/f11c-record.md" "PENDING" ""
    git add "$P3" >/dev/null
    _commit "f11c plan"
    BLOB3="$(rc_blob_of "$P3" plan)"
    sed -i "s/PENDING/$BLOB3/" "$P3"
    git add "$P3" >/dev/null
    _commit "f11c plan anchored"
    _write_record docs/reviews/f11c-record.md "architecture-reviewer (model: fable)" "$P3" "$BLOB3" "SOUND"
    git add docs/reviews/f11c-record.md >/dev/null
    _commit "f11c record"

    RC_LEDGER_PATH="$F11_LEDGER"
    rc_validate_chain "$P3"
    _st "s11c-writer-wrong-artifact-ref-rejected" "FAIL" "$RC_VERDICT"

    RC_LEDGER_PATH="$SAVED_LEDGER"
  else
    echo "self-test (s11-writer-roundtrip-passes): SKIP (workstreams-emit.sh or jq not found)" >&2
  fi

  # ── Extra: rc_chain_present / rc_validate_chain on a chain-less plan ────────
  P=docs/plans/chainless.md
  { echo "# Chainless"; echo "Status: ACTIVE"; echo; echo "## Body"; echo "no chain here"; } > "$P"
  git add "$P" >/dev/null
  _commit "chainless plan"
  rc_validate_chain "$P"
  _st "chainless-plan-fails" "FAIL" "$RC_VERDICT"

  echo "self-test summary: $PASSED passed, $FAILED failed (of $((PASSED + FAILED)) scenarios)" >&2
  if [[ "$FAILED" -eq 0 ]]; then
    exit 0
  else
    exit 1
  fi
fi
