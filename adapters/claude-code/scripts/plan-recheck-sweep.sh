#!/bin/bash
# plan-recheck-sweep.sh — accountable-estate-program-2026-07, T9: the
# AUTO-REOPEN half of outcome-gated closure semantics ("done-without-
# outcome -> reopened", docs/designs/accountable-estate-2026-07-27.md §2).
#
# ============================================================
# WHAT THIS IS / WHAT IT IS NOT (Chesterton's Fence for the next reader)
# ============================================================
#
# close-plan.sh's T9 outcome-gate (verify_closure_outcome_declared +
# write_closure_outcome_section) writes a `## Closure Outcome` section
# into every plan it archives: an Outcome metric, a Re-check date, an
# OPTIONAL Recurrence check command, and derived Evidence pointers. That
# is the WRITE half. This script is the READ half: it sweeps
# docs/plans/archive/*.md for archived (Status: COMPLETED) plans whose
# re-check date has passed, or whose declared Recurrence check command now
# exits nonzero, and REOPENS them -- moves the file back to docs/plans/,
# flips Status back to ACTIVE, appends a Reopen Log entry naming the
# reason, writes a docs/backlog.md row + a needs-you.sh cockpit-visible
# entry, and emits a plan_reopened progress-log event. NEVER silent
# (program rule 2: "recurrence auto-reopens... never silently").
#
# It is NOT a new daemon. It has no scheduling logic of its own; it is a
# plain, idempotent, bounded, read-mostly sweep any chokepoint can invoke.
# See "DETERMINISTIC TRIGGER" below for which chokepoint actually invokes
# it and why.
#
# ============================================================
# DETERMINISTIC TRIGGER (SE design law: chokepoint, not memory)
# ============================================================
#
# The task spec named two candidate triggers: "the supervisor/health tick
# or a doctor check". MEASURED on this machine (2026-07-30, `launchctl
# list | grep -i 'nl-\|supervisor\|health-tick'`): NEITHER
# supervisor-tick.sh NOR health-tick.sh is actually registered as a
# periodic OS task here -- both ship Windows-Task-Scheduler installers
# only (the SAME honest gap T1's estate-janitor.sh already disclosed for
# itself). Picking either as "the" trigger would be aspirational, not
# real -- exactly the "memory" failure mode the design law warns against.
#
# The one chokepoint PROVEN to fire on every real session on this machine
# is the SessionStart hook chain (settings.json.template, 8/8-capacity
# array) -- `session-start-digest.sh` specifically, which ALREADY runs a
# `feed_doctor` call (a doctor check) as its first feed and a
# `feed_stale_plans` call immediately after (the existing analogue: ACTIVE
# plans going stale). This script is wired as a NEW feed
# (`feed_plan_recheck`, adjacent to those two) in that same file --
# `session-start-digest.sh` is the general-purpose SessionStart surfacer
# the file's own header names ("NOT a new SessionStart hooks[] entry --
# that array is at its 8/8 cap; this hook is the general-purpose
# SessionStart surfacer every session already runs through"). It composes
# with, rather than duplicates, the doctor-check option the task named.
#
# HONEST GAP: this is a real, firing chokepoint for INTERACTIVE sessions,
# not a true session-independent periodic tick -- a re-check date that
# passes while no session opens for days goes unnoticed until the next
# session starts. Once T1's estate-janitor.sh (or supervisor-tick.sh /
# health-tick.sh) is actually registered on macOS (tracked pre-existing
# debt, not this task's to close), the SAME `--quick` entry point below
# can be additionally invoked from there with zero changes to this file --
# the sweep logic is fully decoupled from its caller by design.
#
# ============================================================
# SAFETY CONTRACT
# ============================================================
#
# - NEVER destructive: the only mutations are `git mv` (archive -> active),
#   a Status: COMPLETED -> ACTIVE sed flip, and append-only writes
#   (Reopen Log section, docs/backlog.md, NEEDS-YOU.md). Nothing is ever
#   deleted.
# - NEVER SILENT: every reopen writes to TWO durable, cockpit-visible
#   surfaces (docs/backlog.md row + needs-you.sh question entry) in
#   addition to the progress-log event, so "why did this plan come back"
#   is answerable from either surface alone.
# - IDEMPOTENT BY CONSTRUCTION, not by a separate tracking file: the sweep
#   only scans docs/plans/archive/*.md with Status: COMPLETED. The instant
#   a plan reopens, it is Status: ACTIVE and lives under docs/plans/ (not
#   archive/) -- the NEXT sweep simply does not find it again. No second,
#   drifting "already reopened" ledger to keep in sync.
# - BOUNDED: any author-declared Recurrence check command runs under
#   nl_run_bounded (portable-timeout.sh), default 10s. A hung/misbehaving
#   command can never hang the sweep.
# - EXIT 0 ALWAYS on `--quick` (writer semantics, mirrors health-tick.sh's
#   own "never blocks" contract) -- this is a SessionStart-adjacent feed,
#   never allowed to fail a session start.
#
# Subcommands:
#   sweep [--repo <path>] [--dry-run]   Full sweep, verbose stderr log.
#   --quick [--repo <path>]             Bounded, single-line-or-silent
#                                       summary for session-start-digest.sh's
#                                       feed_plan_recheck (stdout: nothing if
#                                       clean, one "plan-recheck: ..." line
#                                       per reopened plan otherwise).
#   --self-test                        Sandboxed scenario suite.
#   --help
#
# Exit codes: 0 success (including "nothing to reopen"). 1 usage/internal
# error. --quick never returns non-zero (see EXIT 0 ALWAYS above).

set -u

SCRIPT_NAME="plan-recheck-sweep.sh"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<'EOF'
Usage: plan-recheck-sweep.sh sweep [--repo <path>] [--dry-run]
       plan-recheck-sweep.sh --quick [--repo <path>]
       plan-recheck-sweep.sh --self-test
       plan-recheck-sweep.sh --help

Sweeps docs/plans/archive/*.md for plans whose T9 "## Closure Outcome"
Re-check date has passed, or whose declared Recurrence check command now
exits nonzero, and reopens them (Status: COMPLETED -> ACTIVE, moved back
to docs/plans/, backlog row + needs-you entry + plan_reopened event).
Never silent, never destructive. See this script's own header for the
full design rationale.
EOF
}

_prs_repo_root() {
  local override="${1:-}"
  if [[ -n "$override" ]]; then
    printf '%s\n' "$override"
    return 0
  fi
  local root
  root="$(git rev-parse --show-toplevel 2>/dev/null)"
  if [[ -n "$root" ]]; then
    printf '%s\n' "$root"
  else
    pwd
  fi
}

# _prs_field <plan_file> <field-name> -- same convention as close-plan.sh's
# extract_closure_outcome_field_cp (duplicated, not sourced: this script
# must run standalone from a bare `bash plan-recheck-sweep.sh`, the same
# one-process-per-invocation convention every sibling script in this repo
# follows rather than `source`-ing a sibling CLI script).
_prs_field() {
  local plan_file="$1" field="$2"
  awk '
    /^## Closure Outcome[[:space:]]*$/ { in_sec = 1; next }
    in_sec && /^## / { in_sec = 0 }
    in_sec { print }
  ' "$plan_file" 2>/dev/null \
    | grep -iE "^${field}:" \
    | head -1 \
    | sed -E "s/^${field}:[[:space:]]*//I"
}

# _prs_load_portable_time -- source portable-time.sh (M4's shared GNU/BSD
# date primitives) rather than hand-rolling a new dual-branch.
#
# CORRECTED CLAIM (2026-07-30, harness-reviewer Minor): this comment used
# to claim a "falls back to bare `date +%s`" behavior that was never
# actually implemented below. The real behavior when the lib is missing:
# every caller already guards each portable-time function behind
# `command -v ... >/dev/null 2>&1` before use (see _prs_reason_for), so an
# absent/unreadable lib means the re-check-date and recurrence-check
# conditions are silently SKIPPED for this sweep -- never a fabricated
# fallback timestamp. Warn once, loudly, so that is at least visible to
# whoever is debugging why a plan's re-check date never fires, rather than
# a second silent failure layered on top of the first.
_prs_load_portable_time() {
  local pt_lib="$SCRIPT_DIR/../hooks/lib/portable-time.sh"
  if [[ -f "$pt_lib" ]]; then
    # shellcheck disable=SC1090
    source "$pt_lib" 2>/dev/null || true
  else
    printf '%s: WARNING: portable-time.sh not found at %s -- re-check-date and recurrence-check evaluation will be skipped entirely for this sweep\n' "$SCRIPT_NAME" "$pt_lib" >&2
  fi
}

_prs_load_portable_timeout() {
  local pto_lib="$SCRIPT_DIR/../hooks/lib/portable-timeout.sh"
  if [[ -f "$pto_lib" ]]; then
    # shellcheck disable=SC1090
    source "$pto_lib" 2>/dev/null || true
  fi
}

# _prs_is_default_recheck <recheck_field_value> -- true (rc 0) if the
# value carries close-plan.sh's OWN "(default)" marker (a Re-check date
# THAT SCRIPT mechanically defaulted, never something the plan's author
# declared). See the C1 header block below for why this distinction is
# the whole fix.
#
# SELF-TEST-ONLY MUTATION HATCH: _PRS_SELFTEST_DISABLE_DEFAULT_SKIP, when
# set to any non-empty value, forces this to always report "not default"
# -- i.e. reproduces the PRE-FIX behavior where a defaulted date could not
# be told apart from an author-declared one. This exists ONLY so this
# script's own --self-test can mutation-prove the storm regression fixture
# (disable the skip, watch the pre-fix reopen happen; re-enable, watch it
# stop) rather than merely asserting the fixed behavior in isolation. It
# has no effect outside a self-test process that explicitly exports it.
_prs_is_default_recheck() {
  [[ -z "${_PRS_SELFTEST_DISABLE_DEFAULT_SKIP:-}" ]] || return 1
  printf '%s' "$1" | grep -qiE '\(default\)[[:space:]]*$' 2>/dev/null
}

# _prs_repo_is_trusted <repo_root> -- true (rc 0) if THIS repo is trusted
# to auto-EXECUTE an author-declared Recurrence check shell command.
#
# ============================================================
# M3 FIX (2026-07-30, harness-reviewer Major — "SessionStart auto-exec of
# repo-authored commands")
# ============================================================
# plan-recheck-sweep.sh --quick is wired at SessionStart (feed_plan_recheck
# in session-start-digest.sh) for EVERY repo a Claude Code session opens
# in, not just this harness's own repo. Before this fix, ANY repo with a
# docs/plans/archive/*.md file carrying a `Recurrence check:` field got
# that field's shell command silently `bash -c`'d at session start -- a
# pure repo-content -> auto-exec channel with zero project-trust gating
# (opening a session in an untrusted/malicious repo would run whatever
# shell command that repo's own plan file declared).
#
# Trust is granted, by the simplest honest mechanism available (no config
# file, no registry to keep in sync), to:
#   (a) the harness repo itself, fingerprinted by the presence of its own
#       adapters/claude-code/manifest.json -- a file that exists ONLY in
#       this harness's source checkout, never in an arbitrary consumer
#       repo and never in a bare ~/.claude install copy (which has no
#       manifest.json of its own at that path); or
#   (b) any repo the operator has explicitly opted in via a
#       `.claude/trust-recurrence-exec` marker file at the repo root
#       (empty sentinel -- an operator who wants a non-harness repo's
#       recurrence checks to auto-run creates this ONE file once).
# Untrusted repos still get the field's EXISTENCE reported (never
# silently dropped) -- see _prs_reason_for below -- just never executed.
_prs_repo_is_trusted() {
  local repo_root="$1"
  [[ -n "$repo_root" ]] || return 1
  [[ -f "$repo_root/adapters/claude-code/manifest.json" ]] && return 0
  [[ -f "$repo_root/.claude/trust-recurrence-exec" ]] && return 0
  return 1
}

# _prs_reason_for <plan_file> [repo_root] -- prints a non-empty STRING
# reason if this plan should reopen (either "re-check date <d> passed" or
# "recurrence check '<cmd>' exited <n>"), or prints nothing and returns 1
# if neither condition fires. Two independent checks; EITHER firing is
# sufficient (task spec: "when a re-check date passes OR the metric's
# recurrence condition fires").
#
# C1 FIX (2026-07-30, CRITICAL — "default-date x sweep = scheduled
# auto-reopen storm + infinite loop"): a Re-check date carrying close-
# plan.sh's own "(default)" marker (nobody asked for this check-in; the
# script mechanically defaulted it because the plan declared none) NEVER
# triggers a reopen here, no matter how far past it is. Only an
# AUTHOR-declared date (no marker) is a real commitment worth auto-
# reopening for. Without this, EVERY plan this repo's close-plan.sh ever
# closes -- opted into outcome-gating or not -- would auto-reopen ~14 days
# later, and a re-close that preserved the same stale default verbatim fed
# the exact same trigger right back in on the next sweep: a self-
# sustaining storm. See close-plan.sh's generate_closure_outcome_section
# for the write-side half (the other two layers of this fix).
_prs_reason_for() {
  local plan_file="$1" repo_root="${2:-}"
  local recheck recurrence

  recheck="$(_prs_field "$plan_file" "Re-check date" 2>/dev/null || true)"
  recurrence="$(_prs_field "$plan_file" "Recurrence check" 2>/dev/null || true)"

  # M3: decide (and report) trust BEFORE the recheck-date branch below, so
  # the "field reported, not executed" note surfaces in the verbose sweep
  # log regardless of whether a re-check-date condition also fires.
  local recurrence_trusted=1
  if [[ -n "$recurrence" ]]; then
    if ! _prs_repo_is_trusted "$repo_root"; then
      recurrence_trusted=0
      printf 'plan-recheck-sweep: NOTE: %s declares a Recurrence check (%s) but this repo is not trusted to auto-execute it -- field reported, not executed. See plan-recheck-sweep.sh _prs_repo_is_trusted for the trust gate (harness repo, or a .claude/trust-recurrence-exec marker).\n' "$plan_file" "$recurrence" >&2
    fi
  fi

  if [[ -n "$recheck" ]] && ! _prs_is_default_recheck "$recheck" && command -v nl_iso_to_epoch >/dev/null 2>&1; then
    # Strip any "(default)" marker before parsing regardless of the skip
    # decision above -- the marker is metadata about PROVENANCE, never
    # part of the ISO-8601 value itself.
    local recheck_bare recheck_epoch now_epoch
    recheck_bare="$(printf '%s' "$recheck" | sed -E 's/[[:space:]]*\(default\)[[:space:]]*$//')"
    recheck_epoch="$(nl_iso_to_epoch "$recheck_bare" 2>/dev/null || true)"
    now_epoch="$(nl_now_epoch 2>/dev/null || true)"
    if [[ -n "$recheck_epoch" ]] && [[ -n "$now_epoch" ]] && [[ "$now_epoch" -gt "$recheck_epoch" ]]; then
      printf 're-check date %s passed' "$recheck_bare"
      return 0
    fi
  fi

  if [[ -n "$recurrence" ]] && [[ "$recurrence_trusted" -eq 1 ]] && command -v nl_run_bounded >/dev/null 2>&1; then
    local rc
    nl_run_bounded 10 bash -c "$recurrence" >/dev/null 2>&1
    rc=$?
    if [[ "$rc" -ne 0 ]]; then
      printf "recurrence check '%s' exited %s" "$recurrence" "$rc"
      return 0
    fi
  fi

  return 1
}

# _prs_reopen_one <repo_root> <archived_path> <reason> <dry_run>
# Performs the actual reopen: git mv, Status flip, Reopen Log append,
# backlog row, needs-you entry, plan_reopened event, commit
# (pathspec-limited). Prints the new active path on success.
_prs_reopen_one() {
  local repo_root="$1" archived_path="$2" reason="$3" dry_run="$4"

  local slug
  slug="$(basename "$archived_path" .md)"
  local active_path="docs/plans/${slug}.md"
  local ts
  ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date +"%Y-%m-%dT%H:%M:%S")"

  if [[ "$dry_run" == "1" ]]; then
    printf 'plan-recheck-sweep: [dry-run] would reopen %s (%s)\n' "$slug" "$reason" >&2
    return 0
  fi

  (
    cd "$repo_root" || exit 1

    mkdir -p "$(dirname "$active_path")"
    if git ls-files --error-unmatch "$archived_path" >/dev/null 2>&1; then
      git mv "$archived_path" "$active_path" 2>/dev/null || mv "$archived_path" "$active_path"
    else
      mv "$archived_path" "$active_path"
    fi

    local tmp
    tmp=$(mktemp)
    sed -e 's/^Status:[[:space:]]*COMPLETED[[:space:]]*$/Status: ACTIVE/' "$active_path" > "$tmp"
    cp "$tmp" "$active_path"
    rm -f "$tmp"

    # Append a Reopen Log entry — the heading is written ONCE (a plan can
    # legitimately reopen more than once across its lifetime; subsequent
    # reopens append a new bullet under the SAME existing heading, never a
    # duplicate heading).
    if ! grep -q '^## Reopen Log' "$active_path" 2>/dev/null; then
      printf '\n## Reopen Log\n' >> "$active_path"
    fi
    printf -- '- %s — REOPENED by plan-recheck-sweep.sh. Reason: %s.\n' "$ts" "$reason" >> "$active_path"

    # Backlog row (single canonical section so repeated reopens don't
    # scatter across the file).
    local backlog="docs/backlog.md"
    if [[ -f "$backlog" ]]; then
      if ! grep -q '^## Auto-reopened plans (plan-recheck-sweep.sh)' "$backlog" 2>/dev/null; then
        printf '\n## Auto-reopened plans (plan-recheck-sweep.sh)\n' >> "$backlog"
      fi
      printf -- '- **PLAN-REOPENED-%s-%s** — plan `%s` auto-reopened by plan-recheck-sweep.sh at %s. Reason: %s. Moved back from `%s` to `%s`; Status flipped ACTIVE. See NEEDS-YOU.md for the operator-facing entry.\n' \
        "$slug" "$(date -u +%Y%m%d%H%M%S 2>/dev/null || echo "$ts")" "$slug" "$ts" "$reason" "$archived_path" "$active_path" >> "$backlog"
    fi

    # Cockpit-visible entry (needs-you.sh; --mechanical since this is a
    # hook/script caller with no live actor to retry).
    local ny="$SCRIPT_DIR/needs-you.sh"
    if [[ -x "$ny" ]] || [[ -f "$ny" ]]; then
      bash "$ny" add --section question \
        --text "Plan \`$slug\` auto-reopened at $ts by plan-recheck-sweep.sh (docs/plans/$slug.md). Reason: $reason. This plan was previously closed (docs/plans/archive/$slug.md) with a T9 Closure Outcome re-check date or recurrence check that has now fired — decide whether to re-verify/re-close it, defer it, or supersede it. To stop this from reopening again: update the Re-check date (or remove it) before re-closing, or the sweep will reopen this again next session." \
        --session "plan-recheck-sweep" \
        --mechanical >/dev/null 2>&1 || true
    fi

    # plan_reopened progress-log event (T9). dedup-extra: content-hash of
    # (reason + this reopen's ts) so a DIFFERENT re-check/recurrence fire
    # on a later sweep is a legitimately-distinct new event.
    local pl_cli="$SCRIPT_DIR/progress-log.sh"
    if [[ -f "$pl_cli" ]]; then
      local hash
      if command -v sha1sum >/dev/null 2>&1; then
        hash="$(printf '%s' "${reason}|${ts}" | sha1sum 2>/dev/null | awk '{print $1}')"
      else
        hash="$(printf '%s' "${reason}|${ts}" | cksum 2>/dev/null | awk '{print $1"-"$2}')"
      fi
      local ask_id
      ask_id="$(grep -E '^ask-id:[[:space:]]*[^[:space:]]+' "$active_path" 2>/dev/null | head -1 | sed -E 's/^ask-id:[[:space:]]*//' | awk '{ if ($1 == "none" || $1 ~ /^</) exit; print $1 }')"
      bash "$pl_cli" emit \
        --type plan_reopened \
        --ask "$ask_id" \
        --plan-slug "$slug" \
        --summary "plan $slug reopened: $reason" \
        --evidence-link "$repo_root/$active_path" \
        --emitter plan-recheck-sweep \
        --dedup-extra "$hash" \
        >/dev/null 2>&1 || true
    fi

    git add -- "$active_path" "$archived_path" "$backlog" 2>/dev/null
    if [[ -n "$(git status --porcelain -- "$active_path" "$archived_path" "$backlog" 2>/dev/null)" ]]; then
      git commit -q -m "chore(plans): auto-reopen $slug (plan-recheck-sweep.sh — $reason)" -- "$active_path" "$archived_path" "$backlog" 2>/dev/null || true
    fi

    printf '%s\n' "$active_path"
  )
}

cmd_sweep() {
  local repo_override="" dry_run="0"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --repo) repo_override="$2"; shift 2 ;;
      --dry-run) dry_run="1"; shift ;;
      *) printf '%s: unknown flag: %s\n' "$SCRIPT_NAME" "$1" >&2; return 1 ;;
    esac
  done

  _prs_load_portable_time
  _prs_load_portable_timeout

  local repo_root
  repo_root="$(_prs_repo_root "$repo_override")"

  local archive_dir="$repo_root/docs/plans/archive"
  [[ -d "$archive_dir" ]] || { printf '[plan-recheck-sweep] no archive dir at %s; nothing to sweep\n' "$archive_dir" >&2; return 0; }

  local found=0 f rel_path reason new_path
  for f in "$archive_dir"/*.md; do
    [[ -f "$f" ]] || continue
    grep -qE '^Status:[[:space:]]*COMPLETED' "$f" 2>/dev/null || continue
    grep -qE '^## Closure Outcome[[:space:]]*$' "$f" 2>/dev/null || continue

    rel_path="docs/plans/archive/$(basename "$f")"
    if reason="$(_prs_reason_for "$f" "$repo_root")"; then
      found=$((found + 1))
      printf '[plan-recheck-sweep] REOPEN CANDIDATE: %s (%s)\n' "$rel_path" "$reason" >&2
      new_path="$(_prs_reopen_one "$repo_root" "$rel_path" "$reason" "$dry_run")"
      [[ -n "$new_path" ]] && printf '[plan-recheck-sweep]   -> %s\n' "$new_path" >&2
    fi
  done

  if [[ "$found" -eq 0 ]]; then
    printf '[plan-recheck-sweep] clean: no plan met a re-check or recurrence condition\n' >&2
  fi

  return 0
}

cmd_quick() {
  local repo_override=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --repo) repo_override="$2"; shift 2 ;;
      *) shift ;;
    esac
  done

  _prs_load_portable_time
  _prs_load_portable_timeout

  local repo_root
  repo_root="$(_prs_repo_root "$repo_override")"
  local archive_dir="$repo_root/docs/plans/archive"
  [[ -d "$archive_dir" ]] || return 0

  local f reason
  for f in "$archive_dir"/*.md; do
    [[ -f "$f" ]] || continue
    grep -qE '^Status:[[:space:]]*COMPLETED' "$f" 2>/dev/null || continue
    grep -qE '^## Closure Outcome[[:space:]]*$' "$f" 2>/dev/null || continue
    if reason="$(_prs_reason_for "$f" "$repo_root")"; then
      _prs_reopen_one "$repo_root" "docs/plans/archive/$(basename "$f")" "$reason" "0" >/dev/null 2>&1
      printf 'plan-recheck: %s reopened (%s)\n' "$(basename "$f" .md)" "$reason"
    fi
  done
  return 0
}

# ---------------------------------------------------------------------------
# Self-test
# ---------------------------------------------------------------------------
_prs_setup_repo() {
  local slug="$1" recheck_field="$2" recurrence_field="$3" trust="${4:-}"
  local d
  d=$(mktemp -d 2>/dev/null || mktemp -d -t prsst)
  (
    cd "$d" || exit 1
    git init -q
    git config user.email "test@example.test"
    git config user.name "Test"
    mkdir -p docs/plans/archive
    # M3 trust gate: a 4th "trusted" arg opts this fixture repo IN to
    # Recurrence-check execution (via the .claude/trust-recurrence-exec
    # marker, the simplest allowlist mechanism _prs_repo_is_trusted
    # checks) -- ONLY the scenarios that specifically exercise recurrence-
    # check EXECUTION request this; every other fixture stays untrusted by
    # default, matching a real consumer repo's default posture.
    if [[ "$trust" == "trusted" ]]; then
      mkdir -p .claude
      : > .claude/trust-recurrence-exec
    fi
    {
      printf '# Plan: %s\n' "$slug"
      printf 'Status: COMPLETED\n'
      printf 'Backlog items absorbed: none\n\n'
      printf '## Goal\ntest\n\n'
      printf '## Files to Modify/Create\n- `docs/plans/archive/%s.md`\n\n' "$slug"
      printf '## Closure Outcome\n'
      printf 'Outcome metric: test metric\n'
      [[ -n "$recheck_field" ]] && printf 'Re-check date: %s\n' "$recheck_field"
      [[ -n "$recurrence_field" ]] && printf 'Recurrence check: %s\n' "$recurrence_field"
      printf 'Evidence pointers:\n- (none)\n'
    } > "docs/plans/archive/${slug}.md"
    printf '# Backlog\n\n## Open work\n' > docs/backlog.md
    git add . && git commit -q -m init
  )
  printf '%s\n' "$d"
}

run_self_test() {
  local SELF_PATH
  if [[ "$0" == /* ]]; then SELF_PATH="$0"; else SELF_PATH="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"; fi
  export HARNESS_SELFTEST=1
  local ST_DIR
  ST_DIR=$(mktemp -d 2>/dev/null || mktemp -d -t prsselftest)
  export NEEDS_YOU_STATE_DIR="$ST_DIR/ny-state"
  export NEEDS_YOU_MD_PATH="$ST_DIR/NEEDS-YOU.md"
  export PROGRESS_LOG_STATE_DIR="$ST_DIR/progress-logs"
  mkdir -p "$NEEDS_YOU_STATE_DIR" "$PROGRESS_LOG_STATE_DIR"

  local PASSED=0 FAILED=0
  printf 'plan-recheck-sweep.sh self-test (10 scenarios)\n\n' >&2

  # ----- S1: re-check date in the past -> REOPENS -----
  local D1; D1=$(_prs_setup_repo "p-past" "2020-01-01T00:00:00Z" "")
  bash "$SELF_PATH" sweep --repo "$D1" >/dev/null 2>&1
  if [[ -f "$D1/docs/plans/p-past.md" ]] \
     && grep -q '^Status: ACTIVE' "$D1/docs/plans/p-past.md" \
     && grep -q '^## Reopen Log' "$D1/docs/plans/p-past.md" \
     && grep -q 'PLAN-REOPENED-p-past' "$D1/docs/backlog.md" \
     && [[ ! -f "$D1/docs/plans/archive/p-past.md" ]]; then
    printf 'self-test (S1) past-recheck-date-reopens: PASS\n' >&2
    PASSED=$((PASSED+1))
  else
    printf 'self-test (S1) past-recheck-date-reopens: FAIL\n' >&2
    FAILED=$((FAILED+1))
  fi
  rm -rf "$D1"

  # ----- S2: re-check date in the future -> does NOT reopen -----
  local D2; D2=$(_prs_setup_repo "p-future" "2099-01-01T00:00:00Z" "")
  bash "$SELF_PATH" sweep --repo "$D2" >/dev/null 2>&1
  if [[ -f "$D2/docs/plans/archive/p-future.md" ]] \
     && grep -q '^Status: COMPLETED' "$D2/docs/plans/archive/p-future.md" \
     && [[ ! -f "$D2/docs/plans/p-future.md" ]]; then
    printf 'self-test (S2) future-recheck-date-does-not-reopen: PASS\n' >&2
    PASSED=$((PASSED+1))
  else
    printf 'self-test (S2) future-recheck-date-does-not-reopen: FAIL\n' >&2
    FAILED=$((FAILED+1))
  fi
  rm -rf "$D2"

  # ----- S3: recurrence check exits nonzero (future re-check date) -> REOPENS -----
  # ("trusted": this scenario tests EXECUTION of the recurrence command
  # itself, so the fixture repo opts in to the M3 trust gate.)
  local D3; D3=$(_prs_setup_repo "p-recur-fail" "2099-01-01T00:00:00Z" "exit 3" "trusted")
  bash "$SELF_PATH" sweep --repo "$D3" >/dev/null 2>&1
  if [[ -f "$D3/docs/plans/p-recur-fail.md" ]] \
     && grep -q '^Status: ACTIVE' "$D3/docs/plans/p-recur-fail.md" \
     && grep -qE "recurrence check.*exited 3" "$D3/docs/plans/p-recur-fail.md"; then
    printf 'self-test (S3) recurrence-check-nonzero-reopens: PASS\n' >&2
    PASSED=$((PASSED+1))
  else
    printf 'self-test (S3) recurrence-check-nonzero-reopens: FAIL\n' >&2
    FAILED=$((FAILED+1))
  fi
  rm -rf "$D3"

  # ----- S4: recurrence check exits zero (future re-check date) -> does NOT reopen -----
  # ("trusted": likewise exercises real execution -- must run to prove it
  # exits 0, not merely be skipped as untrusted.)
  local D4; D4=$(_prs_setup_repo "p-recur-ok" "2099-01-01T00:00:00Z" "exit 0" "trusted")
  bash "$SELF_PATH" sweep --repo "$D4" >/dev/null 2>&1
  if [[ -f "$D4/docs/plans/archive/p-recur-ok.md" ]] \
     && [[ ! -f "$D4/docs/plans/p-recur-ok.md" ]]; then
    printf 'self-test (S4) recurrence-check-zero-does-not-reopen: PASS\n' >&2
    PASSED=$((PASSED+1))
  else
    printf 'self-test (S4) recurrence-check-zero-does-not-reopen: FAIL\n' >&2
    FAILED=$((FAILED+1))
  fi
  rm -rf "$D4"

  # ----- S5: idempotency -- a second sweep after reopen does not crash and
  # does not re-append a second Reopen Log entry for the SAME condition
  # (the plan is no longer in archive/, so the scan simply skips it). -----
  local D5; D5=$(_prs_setup_repo "p-idem" "2020-01-01T00:00:00Z" "")
  bash "$SELF_PATH" sweep --repo "$D5" >/dev/null 2>&1
  local count_after_1
  count_after_1=$(grep -c '^- .*REOPENED' "$D5/docs/plans/p-idem.md" 2>/dev/null || echo 0)
  bash "$SELF_PATH" sweep --repo "$D5" >/dev/null 2>&1
  local count_after_2
  count_after_2=$(grep -c '^- .*REOPENED' "$D5/docs/plans/p-idem.md" 2>/dev/null || echo 0)
  if [[ "$count_after_1" == "1" ]] && [[ "$count_after_2" == "1" ]]; then
    printf 'self-test (S5) idempotent-second-sweep-no-double-reopen: PASS\n' >&2
    PASSED=$((PASSED+1))
  else
    printf 'self-test (S5) idempotent-second-sweep-no-double-reopen: FAIL (count1=%s count2=%s)\n' "$count_after_1" "$count_after_2" >&2
    FAILED=$((FAILED+1))
  fi
  rm -rf "$D5"

  # ----- S6: unparseable Re-check date -> skip gracefully, never crash, never reopen -----
  local D6; D6=$(_prs_setup_repo "p-bad-date" "not-a-date" "")
  local s6_rc
  bash "$SELF_PATH" sweep --repo "$D6" >/dev/null 2>&1
  s6_rc=$?
  if [[ "$s6_rc" -eq 0 ]] \
     && [[ -f "$D6/docs/plans/archive/p-bad-date.md" ]] \
     && [[ ! -f "$D6/docs/plans/p-bad-date.md" ]]; then
    printf 'self-test (S6) unparseable-date-skips-gracefully: PASS\n' >&2
    PASSED=$((PASSED+1))
  else
    printf 'self-test (S6) unparseable-date-skips-gracefully: FAIL (rc=%s)\n' "$s6_rc" >&2
    FAILED=$((FAILED+1))
  fi
  rm -rf "$D6"

  # ----- S7: --quick is silent when nothing needs reopening, and prints
  # exactly one line when something does. -----
  local D7a; D7a=$(_prs_setup_repo "p-quick-clean" "2099-01-01T00:00:00Z" "")
  local s7a_out
  s7a_out="$(bash "$SELF_PATH" --quick --repo "$D7a" 2>/dev/null)"
  local D7b; D7b=$(_prs_setup_repo "p-quick-dirty" "2020-01-01T00:00:00Z" "")
  local s7b_out
  s7b_out="$(bash "$SELF_PATH" --quick --repo "$D7b" 2>/dev/null)"
  if [[ -z "$s7a_out" ]] && printf '%s' "$s7b_out" | grep -q '^plan-recheck: p-quick-dirty reopened'; then
    printf 'self-test (S7) quick-mode-silent-when-clean-one-line-when-dirty: PASS\n' >&2
    PASSED=$((PASSED+1))
  else
    printf 'self-test (S7) quick-mode-silent-when-clean-one-line-when-dirty: FAIL (clean_out=%s dirty_out=%s)\n' "$s7a_out" "$s7b_out" >&2
    FAILED=$((FAILED+1))
  fi
  rm -rf "$D7a" "$D7b"

  # ----- S8: plan_reopened progress-log event emitted with the correct type -----
  local D8; D8=$(_prs_setup_repo "p-event" "2020-01-01T00:00:00Z" "")
  (
    cd "$D8" || exit 1
    printf 'ask-id: ask-selftest-reopen-event\n' >> docs/plans/archive/p-event.md
  )
  local S8_LOG="$PROGRESS_LOG_STATE_DIR/ask-selftest-reopen-event.jsonl"
  rm -f "$S8_LOG"
  bash "$SELF_PATH" sweep --repo "$D8" >/dev/null 2>&1
  if grep -q '"type":"plan_reopened"' "$S8_LOG" 2>/dev/null; then
    printf 'self-test (S8) plan-reopened-event-emitted: PASS\n' >&2
    PASSED=$((PASSED+1))
  else
    printf 'self-test (S8) plan-reopened-event-emitted: FAIL (log=%s)\n' "$(cat "$S8_LOG" 2>/dev/null)" >&2
    FAILED=$((FAILED+1))
  fi
  rm -rf "$D8"

  # ----- S9 (C1 CRITICAL regression, harness-reviewer, 2026-07-30): a
  # Re-check date carrying close-plan.sh's "(default)" marker -- even
  # stale -- must NEVER trigger an auto-reopen (the storm this fixes:
  # EVERY post-close default recheck date used to be indistinguishable
  # from an author's own declared date, so every closed plan would
  # auto-reopen ~14 days later). Mutation-proven: the SAME stale-default
  # fixture DOES reopen when _PRS_SELFTEST_DISABLE_DEFAULT_SKIP simulates
  # the pre-fix behavior, proving the fixed-behavior assertion below is
  # not vacuous. -----
  local D9; D9=$(_prs_setup_repo "p-default-stale" "2020-01-01T00:00:00Z (default)" "")
  bash "$SELF_PATH" sweep --repo "$D9" >/dev/null 2>&1
  local s9_fixed_ok=0
  if [[ -f "$D9/docs/plans/archive/p-default-stale.md" ]] \
     && grep -q '^Status: COMPLETED' "$D9/docs/plans/archive/p-default-stale.md" \
     && [[ ! -f "$D9/docs/plans/p-default-stale.md" ]]; then
    s9_fixed_ok=1
  fi
  _PRS_SELFTEST_DISABLE_DEFAULT_SKIP=1 bash "$SELF_PATH" sweep --repo "$D9" >/dev/null 2>&1
  local s9_mutation_reopened=0
  if [[ -f "$D9/docs/plans/p-default-stale.md" ]] && grep -q '^Status: ACTIVE' "$D9/docs/plans/p-default-stale.md" 2>/dev/null; then
    s9_mutation_reopened=1
  fi
  if [[ "$s9_fixed_ok" -eq 1 ]] && [[ "$s9_mutation_reopened" -eq 1 ]]; then
    printf 'self-test (S9) defaulted-stale-recheck-never-auto-reopens: PASS (mutation-proven)\n' >&2
    PASSED=$((PASSED+1))
  else
    printf 'self-test (S9) defaulted-stale-recheck-never-auto-reopens: FAIL (fixed_ok=%s mutation_reopened=%s)\n' "$s9_fixed_ok" "$s9_mutation_reopened" >&2
    FAILED=$((FAILED+1))
  fi
  rm -rf "$D9"

  # ----- S10 (M3 Major regression, harness-reviewer, 2026-07-30): a
  # Recurrence check command declared in an UNTRUSTED repo (no
  # .claude/trust-recurrence-exec marker, no adapters/claude-code/
  # manifest.json) is reported but NEVER executed -- the plan must NOT
  # reopen even though the declared command would exit nonzero if it ran,
  # and the sweep's verbose log must say so ("field reported, not
  # executed"). -----
  local D10; D10=$(_prs_setup_repo "p-untrusted-recur" "2099-01-01T00:00:00Z" "exit 3")
  local s10_out
  s10_out="$(bash "$SELF_PATH" sweep --repo "$D10" 2>&1)"
  if [[ -f "$D10/docs/plans/archive/p-untrusted-recur.md" ]] \
     && [[ ! -f "$D10/docs/plans/p-untrusted-recur.md" ]] \
     && printf '%s' "$s10_out" | grep -q 'not executed'; then
    printf 'self-test (S10) untrusted-repo-recurrence-reported-not-executed: PASS\n' >&2
    PASSED=$((PASSED+1))
  else
    printf 'self-test (S10) untrusted-repo-recurrence-reported-not-executed: FAIL (out=%s)\n' "$s10_out" >&2
    FAILED=$((FAILED+1))
  fi
  rm -rf "$D10"

  rm -rf "$ST_DIR" 2>/dev/null || true

  printf '\nself-test summary: %d passed, %d failed (of 10 scenarios)\n' "$PASSED" "$FAILED" >&2
  [[ "$FAILED" -eq 0 ]] && return 0
  return 1
}

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------
case "${1:-}" in
  sweep) shift; cmd_sweep "$@" ;;
  --quick) shift; cmd_quick "$@" ;;
  --self-test) run_self_test ;;
  --help|-h|"") usage ;;
  *) printf '%s: unknown subcommand: %s\n' "$SCRIPT_NAME" "$1" >&2; usage >&2; exit 1 ;;
esac
