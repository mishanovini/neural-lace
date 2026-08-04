#!/bin/bash
# harness-doctor.sh — truth-reconciliation doctor for the NL harness (ADR 058 D4)
#
# WHY THIS EXISTS
# ===============
# The 2026-07-01 effectiveness audit (RC2 "enforcement theater") found that
# claimed enforcement (a hook documented as wired, a rule classified
# "Mechanism") frequently does not actually fire: hooks referenced in
# settings.json that don't exist on disk, hooks whose `lib/`-sourced
# dependency is missing, hooks still pointing at retired legacy paths, and
# drift between the committed template and the live mirror. This doctor is
# the single command that turns "I believe the harness enforces X" into
# "the harness provably enforces X, checked in <2s."
#
# See docs/plans/nl-overhaul-program-2026-07.md task B.1 and
# docs/plans/nl-overhaul-program-2026-07-specs-b.md §B.1 for the full spec
# this file implements.
#
# MODES
# =====
#   --quick (default): checks 1-7 against the LIVE mirror ($HOME/.claude)
#                       and the repo. Never runs self-tests. Fast (<2s
#                       typical). Exit 0 iff zero RED lines; exit 1 if any
#                       RED; exit 3 (gated-pipeline-master-2026-08 Task 4,
#                       REQ-A2/HR-F2+F5+F8) when the invocation itself was
#                       SKIPPED (single-flight guard held, or HALT draining)
#                       and no valid cached verdict existed to serve honestly
#                       instead -- NEVER a bare "exit 0" for a skip (that was
#                       indistinguishable from GREEN to every caller). See
#                       "DOCTOR VERDICT CACHE" below for the single-writer
#                       contract and the sf-skip serve-or-3 behavior.
#   --full            : quick + check 8 (self-test sweep across every live
#                       hook that declares --self-test) + check 9 (the
#                       portability sweep vs its committed baseline).
#                       Exit 0 iff zero RED. Subject to the SAME sf_guard
#                       serve-or-3 skip behavior as --quick (one lock covers
#                       every mode), but only --quick reads/writes the
#                       verdict cache -- a skipped --full/--portability call
#                       with no cache to serve exits 3 with no fast-path.
#   --portability     : check 9 ONLY — run scripts/portability-sweep.sh
#                       against the repo under the stock system interpreter
#                       and RED when the failing set grew relative to
#                       docs/portability-baseline.txt. Minutes, not seconds.
#   --self-test       : fixture suite in mktemp -d sandboxes
#                       (HARNESS_SELFTEST=1). One RED-producing fixture AND
#                       one GREEN fixture per check class (1-7), plus a
#                       --full fixture exercising check 8 against a stub
#                       hook. Exit 0 iff every scenario behaves as expected.
#
# OUTPUT FORMAT
# =============
#   [doctor] RED <check-id>: <one-line detail>
#   [doctor] WARN <check-id>: <one-line detail>      (non-blocking)
#   [doctor] GREEN — <n> checks passed                (final line, quick/full)
#
# DEPENDENCIES
# ============
# No hard jq dependency — jq is used opportunistically for anything that
# would otherwise need JSON parsing (there is none required for v1's
# checks; settings.json hook-name extraction is done via grep, which is
# adequate for the flat "command": "bash ~/.claude/hooks/<name>.sh" shape
# every hook wiring uses). node is allowed only with graceful absence
# handling; v1 does not require node either. Both are checked defensively
# so a bare-bash environment still runs every check.
#
# CHECKS (v2 — manifest-driven as of C.1; adapters/claude-code/manifest.json)
# ==================================================================
#   1. wiring-resolves     : every hook basename referenced in live
#                             settings.json AND in the committed template
#                             exists under ~/.claude/hooks/ or
#                             ~/.claude/scripts/ and is readable.
#   2. lib-deps             : for every live hook, each `source`/`.`-included
#                             path under lib/ resolves relative to the
#                             hook's own directory.
#   3. legacy-paths         : no live hook/script references the retired
#                             legacy repo path family (claude-projects/neural…-lace, written split here so the doctor never matches itself).
#   4. template-live-drift  : the sorted basename set of hooks wired in live
#                             settings vs the committed template must match.
#   5. claim-honesty        : manifest-driven (replaced the embedded v1
#                             checklist in C.1) — every `kind: gate` entry
#                             in manifest.json must EITHER declare
#                             wired_template true AND have all its hooks[]
#                             present in live settings.json, OR carry a
#                             non-empty honest_status string naming how it
#                             actually fires. WARN (skip) when no
#                             manifest.json exists (pre-C.1 machine) or no
#                             JSON parser (node/jq) is available.
#   6. byte-budget          : total bytes of ~/.claude/rules/*.md vs the
#                             threshold in ~/.claude/local/doctor-budget
#                             (default 1000000 = warn-only era; C.5 lowers
#                             this to 30000). Over budget -> RED if the
#                             threshold file exists and sets a strict value,
#                             else WARN in the default (absent-file) era.
#   7. manifest-check       : when a repo manifest.json exists, invoke
#                             scripts/manifest-check.sh check (schema
#                             validation + hooks<->disk coverage both ways +
#                             wired_template truth vs the template +
#                             doctrine_file existence + gate honest_status).
#                             Non-zero exit -> RED. WARN (skip, graceful)
#                             when the manifest is absent (pre-C.1 machine)
#                             or the checker script cannot be found.
#   8. selftest-sweep       : (--full only) run every live hook containing
#                             the string "--self-test" with
#                             HARNESS_SELFTEST=1 timeout 1500
#                             bash <hook> --self-test </dev/null; RED per
#                             non-zero exit. Scope is hooks/*.sh AND
#                             hooks/lib/*.sh (the lib glob was added by
#                             macos-portability-2026-07 M5 — a top-level
#                             glob never matched the subdirectory, so 20
#                             libraries' assertions had never run here).
#   9. portability-sweep    : (--full and --portability) run
#                             scripts/portability-sweep.sh over the REPO
#                             under the stock system interpreter
#                             (/bin/bash by default) and RED when a script's
#                             --self-test FAILS or TIMES OUT while absent
#                             from the committed baseline
#                             docs/portability-baseline.txt. A new script
#                             with a passing suite is not a regression; a
#                             baseline entry that now passes is a WARN, not
#                             a RED. See check_portability_sweep's header.
#
# WAVE F BUDGET CHECKS (task F.1, specs-f §F.1 — all in --quick)
# ===============================================================
#   budget-chains           : Stop <= 6, SessionStart <= 8 total hook
#                             entries, checked against BOTH the live
#                             settings.json and the committed template.
#   budget-blocking-gates   : <= 14 blocking session-event UNITS (raised
#                             13 -> 14, agent-efficiency batch 2026-07-23:
#                             find-disk-scan-gate; prior 12 -> 13,
#                             harness-governance-batch 2026-07-16:
#                             gh-merge-canonical + review-before-deploy are
#                             this batch's governance gates, each carrying
#                             the full §10 evidence bar; evidence-before-fix
#                             (task 3) is WARN-MODE, consumes no unit. 13 is
#                             the MEASURED integrated count, not headroom;
#                             budget stays deliberately tight, raise only
#                             with named gates) per the
#                             specs-d §D.0.4 frozen counting rule (wired_
#                             template:true + live-session event + same-
#                             class consolidation), via
#                             scripts/blocking-budget-check.js — NOT a bare
#                             count of blocking:true manifest entries (fixed
#                             during Wave-F integration; see the check's own
#                             header comment for the pre-fix defect).
#   budget-always-loaded    : byte-sum of ~/.claude/rules/*.md +
#                             ~/.claude/CLAUDE.md <= 30000 (dedicated,
#                             non-configurable — distinct from the older
#                             configurable check_byte_budget/rules-only
#                             mechanism, which stays as-is).
#   budget-active-plans     : `Status: ACTIVE` plans <= 3 machine-wide,
#                             walking the exact root list documented at
#                             _budget_active_plans_roots()'s header
#                             comment; fail-open (WARN) per unreadable
#                             root, count what is readable.
#   budget-worktrees-branches: git worktree count <= 6, none >7d without
#                             a commit; local branches with no upstream
#                             and no commit in 7d flagged.
#   new-gate-evidence-bar   : manifest entries with added_after >=
#                             "2026-07" must carry golden_scenario,
#                             fp_expectation, retirement_condition, and
#                             (waiver_path OR honesty_rationale) —
#                             ADR 059 D4. Doctor-side half only; the
#                             constitution §10 prose half is
#                             orchestrator-owned. ALSO: every blocking:true
#                             entry (any added_after) MUST have a non-empty
#                             added_after at all — a missing field used to
#                             let a new gate evade the whole bar by simply
#                             omitting it (exactly how model-pin evaded it
#                             before being fixed; batch task 5,
#                             harness-governance-batch-2026-07-15).
#
# Staleness ESCALATION (deferral/removal proposals) is NOT here — it
# lives in session-start-digest.sh (a SessionStart feed), per specs-f
# §F.1: "the doctor only REDs on budget breach; the digest carries the
# remediation proposals."
#
# ESCAPE HATCH
# ============
# None needed — this is a read-only diagnostic tool, not a blocking
# PreToolUse/Stop gate. It IS wired into settings.json.template's SessionStart
# hook (`--quick`, NL_SESSIONSTART_ORIGIN=1 marked as of T3 in
# agent-efficiency-fixes-2026-07 — see the single-flight guard below), and is
# also invoked on demand (`harness-doctor.sh --quick`/`--full`) by an operator
# or agent. (Earlier revisions of this comment claimed "not currently wired
# into settings.json" — that had gone stale; corrected honestly per
# constitution §10, no behavior change.) `--full` is NOT wired anywhere
# automatic (verified: no CI workflow, cron, or scheduled task invokes it;
# see check_selftest_sweep's header comment) — it is manual-only.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
# shellcheck disable=SC1091
{ source "$SCRIPT_DIR/lib/hook-reentry-guard.sh" 2>/dev/null; } || true
# harness-execution-redesign-2026-08 Task 1 (Stage 0a, invariant 4): the
# universal single-flight/recursion guard, sourced UNCONDITIONALLY here
# (not gated on any wiring marker) so it protects this entry point
# regardless of how it was invoked -- see lib/single-flight-lib.sh header.
# shellcheck disable=SC1091
{ source "$SCRIPT_DIR/lib/single-flight-lib.sh" 2>/dev/null; } || true

# --- portable bounded subprocess (plan macos-portability-2026-07, M3) -----
# The self-test sweep below bounds every child `--self-test` with a wall-clock
# budget. That bound used to be a bare `timeout`, which is GNU coreutils and
# absent on stock macOS: rc=127 came back for EVERY hook and the doctor
# RED-flagged the entire harness with "--self-test exited 127" — the loudest
# possible false alarm, and one the operator cannot distinguish from a real
# mass failure. nl_run_bounded keeps the bound on every platform.
# shellcheck disable=SC1091
{ source "$SCRIPT_DIR/lib/portable-timeout.sh" 2>/dev/null; } || true
if ! declare -F nl_run_bounded >/dev/null 2>&1; then
  nl_run_bounded() {
    local s="${1:-0}"; shift 2>/dev/null || true
    echo "harness-doctor: WARN hooks/lib/portable-timeout.sh missing — running UNBOUNDED (wanted ${s}s): ${1:-<none>}" >&2
    [ "$#" -gt 0 ] || return 2
    "$@"
  }
fi

# ------------------------------------------------------------
# resolve_repo_root — echoes the repo root, or empty if unresolvable.
# Order: git -C <script dir> rev-parse --show-toplevel > $NL_REPO_ROOT
# ------------------------------------------------------------
resolve_repo_root() {
  local root
  root="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null)"
  if [[ -n "$root" ]]; then
    printf '%s\n' "$root"
    return 0
  fi
  if [[ -n "${NL_REPO_ROOT:-}" ]]; then
    printf '%s\n' "$NL_REPO_ROOT"
    return 0
  fi
  # Config-file tier (written by install.sh; same anchor nl-paths.sh uses) —
  # the live mirror is not a git repo, so this is the tier that fires there.
  local cfg="${HOME:-}/.claude/local/nl-repo-path"
  if [[ -f "$cfg" ]]; then
    root="$(head -1 "$cfg" | tr -d '\r\n')"
    if [[ -n "$root" && -d "$root" ]]; then
      printf '%s\n' "$root"
      return 0
    fi
  fi
  return 1
}

# ------------------------------------------------------------
# resolve_live_home — the live mirror root ($HOME/.claude), overridable
# for self-test sandboxing via HARNESS_DOCTOR_HOME.
# ------------------------------------------------------------
resolve_live_home() {
  if [[ -n "${HARNESS_DOCTOR_HOME:-}" ]]; then
    printf '%s\n' "$HARNESS_DOCTOR_HOME"
    return 0
  fi
  printf '%s\n' "${HOME:-}/.claude"
}

# ------------------------------------------------------------
# Doctor verdict cache (harness-execution-redesign-2026-08 Task 3, invariant
# 3 + 7 + 8). REUSES the exact file/schema session-start-digest.sh's
# `refresh_doctor_cache`/`feed_doctor` already read/write
# (~/.claude/state/digest/doctor-cache.json: {"ts","verdict_line",
# "exit_code"}) -- this is a second READER (and, on a real cache-miss run,
# a second WRITER) of the SAME materialized snapshot, not a parallel cache
# (anti-bloat R3.3: one source of truth for "what did doctor last say").
# What digest's existing mechanism did NOT do: `harness-doctor.sh --quick`
# invoked DIRECTLY (an operator/scheduled task calling this file, not going
# through session-start-digest.sh) always recomputed -- this is the real
# gap Task 3 closes (**Prove it works** #4: "doctor --quick serves the
# cached verdict in <2s"). nl-maintenance.sh's `doctor-verdict-refresh` job
# (schedule-manifest.json) is what keeps this fresh on a dedicated 30-min
# (D5) cadence, in addition to health-tick.sh's pre-existing hourly refresh
# via session-start-digest.sh --refresh-doctor-cache.
#
# Path resolution mirrors session-start-digest.sh's own _doctor_cache_path
# EXACTLY (same DOCTOR_CACHE_PATH override) but scopes the real-machine
# default to $LIVE_HOME (== $HOME/.claude on a real run, identical to
# digest's literal $HOME/.claude/state/digest/... path) instead of a bare
# $HOME, so every doctor self-test scenario (which sandboxes LIVE_HOME via
# HARNESS_DOCTOR_HOME) gets automatic per-scenario isolation the same way
# SF_STATE_DIR already does two lines below in the normal-invocation
# section -- no self-test scenario can ever read/write the REAL machine's
# cache file.
#
# SINGLE-WRITER CONTRACT (gated-pipeline-master-2026-08 Task 4, REQ-A2,
# fixing HR-F2+F5+F8): this doctor's own quick-mode write path (below,
# "Doctor verdict cache -- WRITE path") is the cache file's ONLY writer,
# full stop. session-start-digest.sh's `refresh_doctor_cache` is
# invoke-and-read-only -- it forces a real recompute here (via
# SF_DISABLE=1 DOCTOR_VERDICT_CACHE_DISABLE=1) and then reads back
# whatever THIS script just wrote; it never printfs the file itself.
# Before this fix, digest's refresher was a SECOND writer with a
# different (3-field, no fingerprint) schema, which composed with the old
# sf-skip's bare `exit 0` to corrupt the cache (F2): a skip produced no
# verdict line, so the refresher overwrote a valid fingerprinted entry
# with "verdict unavailable (exit 0)", and every digest-side write
# stripped the fingerprint outright. The fix is structural, not a
# discipline promise: there is exactly one `>`/`printf ... >` to this
# file in the whole codebase now (see the WRITE path below); grep
# `doctor-cache.json|DOCTOR_CACHE_PATH` to re-verify.
# ------------------------------------------------------------
_doctor_verdict_cache_path() {
  if [[ -n "${DOCTOR_CACHE_PATH:-}" ]]; then
    printf '%s' "$DOCTOR_CACHE_PATH"
    return 0
  fi
  printf '%s/state/digest/doctor-cache.json' "${1:-${HOME:-$PWD}/.claude}"
}

# _doctor_serve_cache_or_skip <reason> — gated-pipeline-master-2026-08 Task 4
# (REQ-A2, fixing HR-F8): called ONLY from the sf_guard skip path below
# (single-flight lock held, or HALT draining). NEVER a bare `exit 0` -- that
# was indistinguishable from a real GREEN to every exit-code consumer
# (`rg -n "harness-doctor.sh --quick"` is the sweep query; F8's proven
# casualty was F2's cache corruption). Read-only: this function NEVER writes
# doctor-cache.json (the quick-mode WRITE path far below is the cache's
# ONLY writer -- the single-writer contract this task establishes).
#   - A VALID cached record exists (non-empty verdict_line + numeric
#     exit_code -- the doctor's own 5-field writer always produces both) ->
#     serve it verbatim (honest AND fast; the cache mostly makes the skip
#     redundant) and exit ITS exit_code, so a caller that only checks
#     "0 == pass" still gets the right answer on a skip immediately after a
#     real run.
#   - No cache, or an unreadable/incomplete one (e.g. a stale 3-field record
#     from before this fix) -> exit a DISTINCT documented code, 3, with a
#     machine-parseable "[doctor] SKIPPED (<reason>)" line. 3 is chosen to
#     be neither 0 (GREEN) nor 1 (FAILED) -- every exit-code consumer swept
#     in this task's commit treats 3 as "inconclusive," never as either.
_doctor_serve_cache_or_skip() {
  local reason="${1:-single-flight guard active}"
  local cache; cache="$(_doctor_verdict_cache_path "$LIVE_HOME")"
  if [[ -f "$cache" ]]; then
    local verdict exit_code
    verdict="$(sed -nE 's/.*"verdict_line":"([^"]*)".*/\1/p' "$cache" 2>/dev/null | head -1)"
    exit_code="$(sed -nE 's/.*"exit_code":([0-9]+).*/\1/p' "$cache" 2>/dev/null | head -1)"
    if [[ -n "$verdict" && "$exit_code" =~ ^[0-9]+$ ]]; then
      echo "$verdict"
      exit "$exit_code"
    fi
  fi
  echo "[doctor] SKIPPED (${reason})"
  exit 3
}

# _doctor_compute_fingerprint <live_home> <repo_root> — invariant 8
# ("derived, never authored"): a coarse fingerprint of the inputs
# run_quick_checks actually reads from disk -- the live settings.json, the
# committed settings template, manifest.json, and schedule-manifest.json
# (mtimes), plus the repo's current commit (if resolvable), plus (gated-
# pipeline-master-2026-08 Task 4, REQ-A2, fixing HR-F5) the newest mtime
# anywhere under the LIVE hooks mirror ($live_home/hooks -- the doctor's
# primary claimed-vs-actual drift surface: wiring-resolves/lib-deps/legacy-
# paths all read live hook files the original 4-file list never covered)
# and a working-tree-dirty bit (`git -C repo_root diff --quiet`, unstaged
# changes vs the index -- covers a repo file edited but not yet committed,
# the other half of D5's "wiring changes bust the cache immediately"
# promise the original 4-file list only kept for 2 of the ~40 checks'
# config inputs). Documented as a FIRST-APPROXIMATION fingerprint, not true
# per-check declared-input tracking (that would need every one of the ~40
# check_* functions to declare its own inputs individually -- real scope
# beyond this task; see the plan's In-flight scope updates / this task's
# build report for the named follow-up). It is still a REAL derived value:
# any edit to the files/dirs it covers busts the cache on the next read,
# which is what invariant 8 is actually guarding against (a cache that
# lies while the world burns) for the highest-traffic input classes.
_doctor_compute_fingerprint() {
  local live_home="$1" repo_root="$2" parts=""
  local f
  for f in "${live_home}/settings.json" \
           "${repo_root}/adapters/claude-code/settings.json.template" \
           "${repo_root}/adapters/claude-code/manifest.json" \
           "${repo_root}/adapters/claude-code/config/schedule-manifest.json"; do
    if [[ -f "$f" ]]; then
      parts="${parts}|$(date -r "$f" +%s 2>/dev/null || stat -c %Y "$f" 2>/dev/null || echo 0)"
    else
      parts="${parts}|absent"
    fi
  done
  # Live-hooks-dir newest-mtime (HR-F5): a portable (GNU+BSD) newest-file
  # scan -- `find -printf` is GNU-only (portability-sweep's own baseline
  # would RED it), so this loops `find <dir> -type f` (portable) and reuses
  # the exact date -r/stat -c fallback the 4-file loop above already uses,
  # rather than a second mtime-reading idiom.
  local hooks_dir="${live_home}/hooks" hooks_newest=0
  if [[ -d "$hooks_dir" ]]; then
    local hf hf_mtime
    while IFS= read -r hf; do
      hf_mtime="$(date -r "$hf" +%s 2>/dev/null || stat -c %Y "$hf" 2>/dev/null || echo 0)"
      [[ "$hf_mtime" =~ ^[0-9]+$ && "$hf_mtime" -gt "$hooks_newest" ]] && hooks_newest="$hf_mtime"
    done < <(find "$hooks_dir" -type f 2>/dev/null)
  fi
  parts="${parts}|hooksnewest:${hooks_newest}"
  local head=""
  if [[ -n "$repo_root" ]]; then
    head="$(git -C "$repo_root" rev-parse HEAD 2>/dev/null || echo "")"
  fi
  parts="${parts}|${head}"
  # Working-tree-dirty bit (HR-F5): an uncommitted edit to a checked-in
  # repo file (e.g. a hook mid-edit) busts the cache immediately instead of
  # serving a stale-but-plausible verdict for up to DOCTOR_VERDICT_CACHE_TTL_
  # SECONDS. Unstaged only (`git diff`, not `--cached`), matching REQ-A2's
  # literal contract; correct honest-recompute is preferred over cheap here
  # (Edge Cases: "dirty bit changes the fingerprint -> cache miss -> honest
  # recompute, slightly slower -- never stale-serve").
  local dirty="clean"
  if [[ -n "$repo_root" ]]; then
    git -C "$repo_root" diff --quiet 2>/dev/null || dirty="dirty"
  fi
  parts="${parts}|${dirty}"
  if command -v cksum >/dev/null 2>&1; then
    printf '%s' "$parts" | cksum | awk '{print $1}'
  else
    # No cksum -> the concatenated mtimes/HEAD string IS the fingerprint
    # (still deterministic and comparable, just longer).
    printf '%s' "$parts"
  fi
}

# _doctor_ledger_bypass <reason> — invariant 7 (escape hatches are
# ledgered). Appends a JSONL row to the SAME state area the verdict cache
# lives under; best-effort, never blocks.
_doctor_ledger_bypass() {
  local live_home="$1" reason="$2" dir file ts
  dir="${live_home}/state/digest"
  mkdir -p "$dir" 2>/dev/null || return 0
  file="${dir}/doctor-cache-bypass-ledger.jsonl"
  ts="$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || echo unknown)"
  printf '{"ts":"%s","reason":"%s"}\n' "$ts" "${reason//\"/\\\"}" >> "$file" 2>/dev/null || true
}

RED_COUNT=0
WARN_COUNT=0
CHECKS_RUN=0

_red() {
  local id="$1" detail="$2"
  echo "[doctor] RED ${id}: ${detail}"
  RED_COUNT=$((RED_COUNT + 1))
}

_warn() {
  local id="$1" detail="$2"
  echo "[doctor] WARN ${id}: ${detail}"
  WARN_COUNT=$((WARN_COUNT + 1))
}

# _note <id> <detail> -- HR-F7 (2026-08-03 harness review, gated-pipeline
# T7/REQ-A5): an informational, non-counting annotation. Used for
# "satisfied-by-construction" states (e.g. a cadence violation whose
# prescribed remedy is already active) that are worth surfacing to the
# operator but are neither a defect (RED) nor a thing-to-watch (WARN) --
# printing nothing here would silently hide the fact the check even
# considered the entry; a WARN would misclassify an already-fixed state as
# still-open. Never increments RED_COUNT/WARN_COUNT, so it never affects
# the doctor's exit code or its GREEN/FAILED summary line.
_note() {
  local id="$1" detail="$2"
  echo "[doctor] NOTE ${id}: ${detail}"
}

# ------------------------------------------------------------
# extract_wired_hook_basenames <settings-json-path>
# Extracts the set of hook basenames referenced by
# "command": "bash ~/.claude/hooks/<name>.sh" (or scripts/<name>.sh, or
# quoted-path variants with $HOME) lines. Grep-based (no jq dependency) —
# adequate because every hook wiring in this repo uses the flat
# "command": "bash <path>" shape.
# ------------------------------------------------------------
extract_wired_hook_basenames() {
  local settings_file="$1"
  [[ -f "$settings_file" ]] || return 0
  grep -oE '"command"[[:space:]]*:[[:space:]]*"[^"]*bash[[:space:]]+[^"]*\.claude/(hooks|scripts)/[A-Za-z0-9_.-]+\.sh' "$settings_file" 2>/dev/null \
    | grep -oE '[A-Za-z0-9_.-]+\.sh"?$' \
    | sed 's/"$//' \
    | sort -u
}

# ------------------------------------------------------------
# Check 1: wiring-resolves
# ------------------------------------------------------------
check_wiring_resolves() {
  local live_home="$1" repo_root="$2"
  local live_settings="${live_home}/settings.json"
  local template_settings="${repo_root}/adapters/claude-code/settings.json.template"
  local any_source=0
  local names

  if [[ -f "$live_settings" ]]; then
    any_source=1
    names="$(extract_wired_hook_basenames "$live_settings")"
    while IFS= read -r name; do
      [[ -z "$name" ]] && continue
      if [[ ! -e "${live_home}/hooks/${name}" && ! -e "${live_home}/scripts/${name}" ]]; then
        _red "wiring-resolves" "live settings.json references '${name}' but it does not exist under ~/.claude/hooks/ or ~/.claude/scripts/"
      elif [[ -e "${live_home}/hooks/${name}" && ! -r "${live_home}/hooks/${name}" ]]; then
        _red "wiring-resolves" "'${name}' exists but is not readable"
      elif [[ -e "${live_home}/scripts/${name}" && ! -r "${live_home}/scripts/${name}" ]]; then
        _red "wiring-resolves" "'${name}' exists but is not readable"
      fi
    done <<< "$names"
  fi

  if [[ -f "$template_settings" ]]; then
    any_source=1
    names="$(extract_wired_hook_basenames "$template_settings")"
    while IFS= read -r name; do
      [[ -z "$name" ]] && continue
      if [[ ! -e "${repo_root}/adapters/claude-code/hooks/${name}" && ! -e "${repo_root}/adapters/claude-code/scripts/${name}" ]]; then
        _red "wiring-resolves" "template references '${name}' but it does not exist under adapters/claude-code/hooks/ or scripts/"
      fi
    done <<< "$names"
  fi

  if [[ "$any_source" -eq 0 ]]; then
    _warn "wiring-resolves" "no settings.json found (neither live mirror nor template) — nothing to check"
  fi
  CHECKS_RUN=$((CHECKS_RUN + 1))
}

# ------------------------------------------------------------
# Check 2: lib-deps
# For every live hook, each `source`/`.`-included path under lib/ must
# resolve relative to the hook's own directory (mirrors how bash resolves
# `source "$(dirname ...)/lib/x.sh"` idioms used across the codebase).
# ------------------------------------------------------------
check_lib_deps() {
  local live_home="$1"
  local hooks_dir="${live_home}/hooks"
  [[ -d "$hooks_dir" ]] || { _warn "lib-deps" "no live hooks directory at ${hooks_dir} — nothing to check"; CHECKS_RUN=$((CHECKS_RUN + 1)); return 0; }

  local hook
  for hook in "$hooks_dir"/*.sh; do
    [[ -f "$hook" ]] || continue
    # Skip this scanner itself — its self-test section embeds fixture
    # source-lines (lib/missing-lib.sh etc.) that are data, not includes.
    [[ "$(basename "$hook")" == "harness-doctor.sh" ]] && continue
    local hook_dir
    hook_dir="$(cd "$(dirname "$hook")" && pwd)"
    # Match any line containing a source/. include directive, then extract
    # only the "lib/<name>.sh" tail so we don't false-positive on sourcing
    # unrelated files (e.g. .env files). The line-level filter tolerates
    # nested command substitutions like "$(dirname "${BASH_SOURCE[0]}")/lib/x.sh"
    # that a single quote-aware regex can't span.
    # process-substitution (not a trailing pipe) so the while-loop body runs
    # in THIS shell, not a subshell — otherwise _red's RED_COUNT increment
    # would be invisible to the caller.
    while IFS= read -r rel; do
      [[ -z "$rel" ]] && continue
      if [[ ! -f "${hook_dir}/${rel}" ]]; then
        _red "lib-deps" "$(basename "$hook") sources '${rel}' but ${hook_dir}/${rel} does not exist"
      fi
    done < <(grep -E '(^|[^A-Za-z_])(source|\.)[[:space:]]+["'"'"']?.*lib/[A-Za-z0-9_.-]+\.sh' "$hook" 2>/dev/null \
      | grep -oE 'lib/[A-Za-z0-9_.-]+\.sh' \
      | sort -u)
  done
  CHECKS_RUN=$((CHECKS_RUN + 1))
}

# ------------------------------------------------------------
# Check 3: legacy-paths
# ------------------------------------------------------------
check_legacy_paths() {
  local live_home="$1"
  local hooks_dir="${live_home}/hooks"
  local scripts_dir="${live_home}/scripts"
  local found=0
  # Pattern built by concatenation so this script's own text never matches it
  # (the doctor must not RED-flag itself; see Wave-B integration note).
  local legacy_pat="claude-projects/neural""-lace"

  if [[ -d "$hooks_dir" ]]; then
    while IFS= read -r f; do
      [[ -z "$f" ]] && continue
      _red "legacy-paths" "${f} references the retired legacy repo path (${legacy_pat})"
      found=1
    done < <(grep -rl "$legacy_pat" "$hooks_dir" 2>/dev/null)
  fi
  if [[ -d "$scripts_dir" ]]; then
    while IFS= read -r f; do
      [[ -z "$f" ]] && continue
      _red "legacy-paths" "${f} references the retired legacy repo path (${legacy_pat})"
      found=1
    done < <(grep -rl "$legacy_pat" "$scripts_dir" 2>/dev/null)
  fi
  if [[ ! -d "$hooks_dir" && ! -d "$scripts_dir" ]]; then
    _warn "legacy-paths" "no live hooks/ or scripts/ directory — nothing to check"
  fi
  CHECKS_RUN=$((CHECKS_RUN + 1))
}

# ------------------------------------------------------------
# Check 4: template-live-drift
# ------------------------------------------------------------
check_template_live_drift() {
  local live_home="$1" repo_root="$2"
  local live_settings="${live_home}/settings.json"
  local template_settings="${repo_root}/adapters/claude-code/settings.json.template"

  if [[ ! -f "$live_settings" || ! -f "$template_settings" ]]; then
    _warn "template-live-drift" "cannot compare — live settings.json or template missing"
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi

  local live_names template_names
  live_names="$(extract_wired_hook_basenames "$live_settings")"
  template_names="$(extract_wired_hook_basenames "$template_settings")"

  local live_only template_only
  live_only="$(comm -23 <(printf '%s\n' "$live_names" | grep -v '^$' | sort -u) <(printf '%s\n' "$template_names" | grep -v '^$' | sort -u))"
  template_only="$(comm -13 <(printf '%s\n' "$live_names" | grep -v '^$' | sort -u) <(printf '%s\n' "$template_names" | grep -v '^$' | sort -u))"

  if [[ -n "$live_only" ]]; then
    while IFS= read -r n; do
      [[ -z "$n" ]] && continue
      _red "template-live-drift" "'${n}' is wired in live settings.json but not in the committed template"
    done <<< "$live_only"
  fi
  if [[ -n "$template_only" ]]; then
    while IFS= read -r n; do
      [[ -z "$n" ]] && continue
      _red "template-live-drift" "'${n}' is wired in the committed template but not in live settings.json"
    done <<< "$template_only"
  fi
  CHECKS_RUN=$((CHECKS_RUN + 1))
}

# ------------------------------------------------------------
# resolve_manifest <live_home> <repo_root>
# Echoes the manifest path (live-first, repo fallback) or nothing.
# ------------------------------------------------------------
resolve_manifest() {
  local live_home="$1" repo_root="$2"
  if [[ -f "${live_home}/manifest.json" ]]; then
    printf '%s\n' "${live_home}/manifest.json"
    return 0
  fi
  if [[ -n "$repo_root" && -f "${repo_root}/adapters/claude-code/manifest.json" ]]; then
    printf '%s\n' "${repo_root}/adapters/claude-code/manifest.json"
    return 0
  fi
  return 1
}

# ------------------------------------------------------------
# extract_manifest_gates <manifest>
# Emits a normalized stream for check 5:
#   GATE|<id>|<wired01>|<honest01>
#   GH|<id>|<hook-basename>
# node preferred, jq fallback; caller handles the neither-case.
# ------------------------------------------------------------
extract_manifest_gates() {
  local manifest="$1"
  if command -v node >/dev/null 2>&1; then
    node -e '
const m = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
for (const e of m.entries || []) {
  if (e.kind !== "gate") continue;
  const honest = (typeof e.honest_status === "string" && e.honest_status.trim().length > 0) ? "1" : "0";
  console.log(["GATE", e.id, e.wired_template ? "1" : "0", honest].join("|"));
  for (const h of e.hooks || []) console.log(["GH", e.id, h].join("|"));
}' "$manifest" 2>/dev/null
  elif command -v jq >/dev/null 2>&1; then
    jq -r '
.entries[] | select(.kind == "gate") as $e |
(["GATE", $e.id,
  (if $e.wired_template then "1" else "0" end),
  (if (($e.honest_status // "") | length) > 0 then "1" else "0" end)] | join("|")),
((($e.hooks // [])[]) | "GH|\($e.id)|\(.)")' "$manifest" 2>/dev/null
  fi
}

# ------------------------------------------------------------
# Check 5: claim-honesty (manifest-driven, C.1)
# Every `kind: gate` entry in manifest.json must EITHER be wired_template
# true with all its hooks present in live settings.json, OR carry a
# non-empty honest_status. Graceful WARN when no manifest / no parser.
# ------------------------------------------------------------
check_claim_honesty() {
  local live_home="$1" repo_root="$2"
  local manifest
  if ! manifest="$(resolve_manifest "$live_home" "$repo_root")"; then
    _warn "claim-honesty" "no manifest.json found (live mirror or repo) — manifest-driven claim-honesty skipped (pre-C.1 machine)"
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi
  if ! command -v node >/dev/null 2>&1 && ! command -v jq >/dev/null 2>&1; then
    _warn "claim-honesty" "neither node nor jq available — manifest-driven claim-honesty skipped"
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi

  local stream
  stream="$(extract_manifest_gates "$manifest")"
  if [[ -z "$stream" ]]; then
    _warn "claim-honesty" "manifest at ${manifest} yielded no gate entries (parse failure or none declared)"
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi

  local live_settings="${live_home}/settings.json"
  local live_missing=0
  if [[ ! -f "$live_settings" ]]; then
    live_missing=1
    _warn "claim-honesty" "live settings.json missing — live-wiring verification for wired gates skipped"
  fi

  local tag id wired honest t2 i2 hook
  while IFS='|' read -r tag id wired honest; do
    [[ "$tag" == "GATE" ]] || continue
    if [[ "$honest" == "1" ]]; then
      continue
    fi
    if [[ "$wired" == "0" ]]; then
      _red "claim-honesty" "manifest gate '${id}' has wired_template false and no honest_status — name how it fires or which Wave lands its wiring"
      continue
    fi
    [[ "$live_missing" -eq 1 ]] && continue
    while IFS='|' read -r t2 i2 hook; do
      [[ "$t2" == "GH" && "$i2" == "$id" ]] || continue
      if ! grep -qF "$hook" "$live_settings" 2>/dev/null; then
        _red "claim-honesty" "manifest gate '${id}' claims wired_template true but hook '${hook}' does not appear in live settings.json — run install"
      fi
    done <<< "$stream"
  done <<< "$stream"
  CHECKS_RUN=$((CHECKS_RUN + 1))
}

# ------------------------------------------------------------
# Check 7: manifest-check
# When a repo manifest exists, run scripts/manifest-check.sh check against
# the repo. Graceful WARN when the manifest is absent (pre-C.1 machine),
# the repo root is unresolved, or the checker script cannot be found.
# ------------------------------------------------------------
check_manifest() {
  local live_home="$1" repo_root="$2"
  local repo_manifest=""
  [[ -n "$repo_root" && -f "${repo_root}/adapters/claude-code/manifest.json" ]] \
    && repo_manifest="${repo_root}/adapters/claude-code/manifest.json"

  if [[ -z "$repo_manifest" ]]; then
    if [[ -f "${live_home}/manifest.json" ]]; then
      _warn "manifest-check" "manifest present in live mirror but no repo manifest resolved — manifest-check needs the repo (hooks/ coverage); skipped"
    else
      _warn "manifest-check" "no manifest.json found — manifest-check skipped (pre-C.1 machine)"
    fi
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi

  local checker="${repo_root}/adapters/claude-code/scripts/manifest-check.sh"
  [[ -f "$checker" ]] || checker="${live_home}/scripts/manifest-check.sh"
  if [[ ! -f "$checker" ]]; then
    _warn "manifest-check" "manifest.json present but manifest-check.sh not found (repo scripts/ or live scripts/) — cannot validate"
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi

  local out rc n
  out="$(MANIFEST_CHECK_ROOT="$repo_root" bash "$checker" check 2>&1)"
  rc=$?
  if [[ "$rc" -ne 0 ]]; then
    n="$(printf '%s\n' "$out" | grep -c 'RED' 2>/dev/null || true)"
    _red "manifest-check" "manifest-check reported ${n:-?} RED finding(s) — run: bash adapters/claude-code/scripts/manifest-check.sh"
  fi
  CHECKS_RUN=$((CHECKS_RUN + 1))
}

# ------------------------------------------------------------
# _hash_file <path> — best-effort content hash (sha1sum -> shasum ->
# openssl -> byte-count fallback). Mirrors install.sh's _hash_path (item
# 4's copy-then-verify backup) so both sides of the NL-FINDING-017 fix
# use the same hashing discipline.
# ------------------------------------------------------------
_hash_file() {
  local p="$1"
  if command -v sha1sum >/dev/null 2>&1; then
    sha1sum "$p" 2>/dev/null | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum "$p" 2>/dev/null | awk '{print $1}'
  elif command -v openssl >/dev/null 2>&1; then
    openssl sha1 "$p" 2>/dev/null | awk '{print $NF}'
  else
    wc -c < "$p" 2>/dev/null | tr -d '[:space:]'
  fi
}

# ------------------------------------------------------------
# Check: manifest-freshness (NL-FINDING-017, specs-e §E.10 item 4)
# Live ~/.claude/manifest.json hash vs the repo's manifest.json hash. A
# mismatch means install.sh has not been run since the repo manifest
# last changed (the exact D.5 cutover failure: install.sh aborted
# mid-run, live manifest.json stayed at its stale pre-cutover state, and
# the doctor's OTHER checks then reported 20 claim-honesty REDs against
# retired-gate entries that no longer existed on master — the true
# defect was manifest STALENESS, not the gates themselves). RED with an
# honest "run install" remediation; graceful WARN when either side is
# absent (pre-C.1 machine, or repo manifest not resolved).
# ------------------------------------------------------------
check_manifest_freshness() {
  local live_home="$1" repo_root="$2"
  local live_manifest="${live_home}/manifest.json"
  local repo_manifest=""
  [[ -n "$repo_root" && -f "${repo_root}/adapters/claude-code/manifest.json" ]] \
    && repo_manifest="${repo_root}/adapters/claude-code/manifest.json"

  if [[ ! -f "$live_manifest" || -z "$repo_manifest" ]]; then
    _warn "manifest-freshness" "cannot compare — live manifest.json (${live_manifest}) or repo manifest.json missing (pre-C.1 machine or unresolved repo root)"
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi

  local live_hash repo_hash
  live_hash="$(_hash_file "$live_manifest")"
  repo_hash="$(_hash_file "$repo_manifest")"
  if [[ -z "$live_hash" || -z "$repo_hash" ]]; then
    _warn "manifest-freshness" "could not hash one or both manifests (live=${live_manifest}, repo=${repo_manifest}) — no hashing tool available"
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi

  if [[ "$live_hash" != "$repo_hash" ]]; then
    _red "manifest-freshness" "live ~/.claude/manifest.json (hash ${live_hash:0:12}) does not match repo adapters/claude-code/manifest.json (hash ${repo_hash:0:12}) — run: bash adapters/claude-code/install.sh"
  fi
  CHECKS_RUN=$((CHECKS_RUN + 1))
}

# ------------------------------------------------------------
# Check: wave-f-f2-docs (Wave F, task F.2) — doctor predicates from the F.2
# fragment, implemented VERBATIM per
# adapters/claude-code/tests/fixtures/wave-f/F.2/doctor-predicate.md.
#
# Predicate 1 — docs/harness-architecture.md byte-equals a fresh regen
# (gen-architecture-doc.sh --check). WARN (not RED) when the script itself
# is missing OR when it degrades gracefully (neither node nor jq present —
# same posture manifest-check.sh takes; distinguished from a real drift
# RED by grepping the script's own graceful-degradation WARN line so this
# check does not have to re-implement the node/jq probe).
#
# Predicate 2 — the five README surfaces named in the fragment each carry
# a `<!-- last-verified: YYYY-MM-DD (doctor-checked) -->` anchor no more
# than 90 days old. Implemented verbatim from the fragment's check command
# (same grep/date logic), inlined here rather than shelled out so it
# shares this file's _red/_warn accounting.
#
# Predicate 2b (doctrine/INDEX.md) and Predicate 3 (scripts/README.md
# carve-out) are handled by check_manifest / existing generator drift
# checks and documented-no-op respectively — the fragment itself notes
# both need no additional doctor code (see doctor-predicate.md).
# ------------------------------------------------------------
check_wave_f_f2_docs() {
  local live_home="$1" repo_root="$2"

  # --- Predicate 1: harness-architecture.md drift ---
  if [[ -z "$repo_root" ]]; then
    _warn "wave-f-f2-docs" "repo root unresolved — skipped harness-architecture.md drift check"
  else
    local gen_script="${repo_root}/adapters/claude-code/scripts/gen-architecture-doc.sh"
    if [[ ! -f "$gen_script" ]]; then
      _warn "wave-f-f2-docs" "gen-architecture-doc.sh missing from ${gen_script} — F.2 not yet installed on this machine"
    else
      local gen_out gen_rc
      gen_out="$(bash "$gen_script" --check 2>&1)"
      gen_rc=$?
      if printf '%s' "$gen_out" | grep -q 'WARN: needs node or jq'; then
        _warn "wave-f-f2-docs" "gen-architecture-doc.sh --check degraded (neither node nor jq available) — drift check skipped, same posture as manifest-check.sh"
      elif [[ "$gen_rc" -ne 0 ]]; then
        _red "wave-f-f2-docs" "docs/harness-architecture.md drift — gen-architecture-doc.sh --check exited ${gen_rc}: $(printf '%s' "$gen_out" | tail -n 1)"
      fi
    fi
  fi

  # --- Predicate 2: README freshness anchors, verbatim per the fragment ---
  # Absence-tolerant at the SURFACE level (same contract as the E.1/E.7/
  # E.8/E.9 wave-fragment sub-checks below): a fixture/machine where NONE
  # of the five README surfaces exist at all is "F.2 not yet installed
  # here" (WARN, not RED) — this is the shape every doctor self-test
  # fixture repo takes unless it explicitly opts into an F.2 scenario, and
  # a real repo pre-dating F.2 would otherwise RED on every one of the
  # five files for a doc-surface convention it never adopted. Once at
  # least one of the five exists, F.2 is "installed" on this
  # repo/fixture and every surface is held to the full predicate
  # (missing/no-anchor/stale all RED) — that is the partial-adoption case
  # the predicate exists to catch.
  if [[ -z "$repo_root" ]]; then
    _warn "wave-f-f2-docs" "repo root unresolved — skipped README freshness-anchor scan"
  else
    local -a f2_readmes=(
      "${repo_root}/README.md"
      "${repo_root}/adapters/claude-code/README.md"
      "${repo_root}/adapters/claude-code/attic/README.md"
      "${repo_root}/evals/README.md"
      "${repo_root}/neural-lace/workstreams-ui/README.md"
    )
    local f2_any_present=0
    for f in "${f2_readmes[@]}"; do
      [[ -f "$f" ]] && { f2_any_present=1; break; }
    done

    if [[ "$f2_any_present" -eq 0 ]]; then
      _warn "wave-f-f2-docs" "none of the five F.2 README surfaces present under ${repo_root} — F.2 not yet installed on this repo/fixture"
    else
      local today_epoch max_age_days=90
      today_epoch=$(date +%s)
      local f line date_str anchor_epoch age_days
      for f in "${f2_readmes[@]}"
      do
        if [[ ! -f "$f" ]]; then
          _red "wave-f-f2-docs" "MISSING README surface: ${f}"
          continue
        fi
        line="$(grep -m1 -E '<!-- last-verified: [0-9]{4}-[0-9]{2}-[0-9]{2} \(doctor-checked\) -->' "$f" 2>/dev/null)"
        if [[ -z "$line" ]]; then
          _red "wave-f-f2-docs" "NO-ANCHOR: ${f} missing '<!-- last-verified: YYYY-MM-DD (doctor-checked) -->'"
          continue
        fi
        date_str="$(printf '%s' "$line" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}')"
        anchor_epoch="$(date -d "$date_str" +%s 2>/dev/null || date -j -f "%Y-%m-%d" "$date_str" +%s 2>/dev/null)"
        if [[ -z "$anchor_epoch" ]]; then
          _red "wave-f-f2-docs" "UNPARSEABLE-DATE: ${f} anchor date '${date_str}'"
          continue
        fi
        age_days=$(( (today_epoch - anchor_epoch) / 86400 ))
        if [[ "$age_days" -gt "$max_age_days" ]]; then
          _red "wave-f-f2-docs" "STALE (${age_days}d, budget <= ${max_age_days}d): ${f} — re-verify and bump the last-verified anchor"
        fi
      done
    fi
  fi

  CHECKS_RUN=$((CHECKS_RUN + 1))
}

# ------------------------------------------------------------
# Check: wave-e-surfaces (specs-e §E.10 item 12) — doctor predicates from
# the E.1/E.7/E.8/E.9 fragments, implemented VERBATIM per
# adapters/claude-code/tests/fixtures/wave-e/{E.1,E.7,E.8,E.9}/doctor-predicate.md.
# E.5/E.6 fragments are being built in PARALLEL (batch 2) and are being
# built by the orchestrator at integration per specs-e §E.10 item 12 —
# they are SKIPPED here (noted, not implemented) because their fragments
# do not exist on this builder's tree.
# ------------------------------------------------------------
check_wave_e_surfaces() {
  local live_home="$1" repo_root="$2"

  # --- E.1: session-start-digest.sh (predicates 1, 2, 4; predicate 3 is a
  # one-time point-in-time check per the fragment, not a recurring gate). ---
  #
  # T2 FIX (agent-efficiency-fixes-2026-07, docs/lessons/2026-07-20-
  # efficiency-recurrence-live-diagnosis.md — THE dominant root cause, found
  # via live process capture during this fix's own build: 7 concurrent
  # 12+-minute `session-start-digest.sh --self-test` runs + 3 concurrent
  # `harness-doctor.sh --quick` runs, 94 bash.exe total). Predicate 1 used to
  # EXECUTE `bash session-start-digest.sh --self-test` (the full ~19-
  # scenario suite, no timeout, no HARNESS_SELFTEST env set by the caller)
  # INLINE and UNCONDITIONALLY as part of run_quick_checks — i.e. on EVERY
  # SessionStart and resume, contradicting this file's own header claim
  # ("--quick ... Never runs self-tests. Fast (<2s typical)"). As the digest
  # suite grew (git-heavy worktree/heartbeat fixtures) this turned a
  # documented <2s check into a multi-MINUTE blocking call that piled up
  # across every simultaneously-starting/resuming session — the true origin
  # of the 07-20 recursion observation (check_selftest_sweep, --full-only
  # and already timeout-guarded, was a real but secondary contributor).
  # Fixed to match the sibling E.7/E.8 predicates just below (structural
  # presence — exists, executable, declares --self-test — never execution).
  # The REAL suite execution is check_selftest_sweep's job (--full only,
  # already covers this exact hook via its live-hooks-dir sweep, already
  # timeout-guarded, already reentry-guarded as of this same fix). Deliberate
  # fidelity trade: a digest hook whose own self-test suite is logically
  # broken now surfaces via an explicit `--full` run, not automatically on
  # every --quick/SessionStart — the alternative (this exact predicate) is
  # the incident being fixed. Follow-up logged to docs/backlog.md: a
  # health-tick-driven cache of the digest's last self-test verdict would let
  # --quick WARN with detail between --full runs instead of going silent.
  local e1_hook="${live_home}/hooks/session-start-digest.sh"
  if [[ ! -f "$e1_hook" ]]; then
    _warn "wave-e-e1-digest" "session-start-digest.sh missing from live mirror at ${e1_hook} — E.1 not yet installed on this machine"
  elif [[ ! -x "$e1_hook" ]]; then
    _red "wave-e-e1-digest" "session-start-digest.sh missing or not executable at ${e1_hook}"
  elif ! grep -q -- '--self-test' "$e1_hook" 2>/dev/null; then
    _red "wave-e-e1-digest" "session-start-digest.sh has no --self-test entrypoint"
  fi
  local e1_probe_guard="${repo_root}/adapters/claude-code/attic/principles-compliance-gate.sh"
  if [[ -n "$repo_root" && -f "$e1_probe_guard" ]]; then
    if ! grep -q 'NL-FINDING-021' "$e1_probe_guard" 2>/dev/null || ! grep -q 'ALERT_ANOMALY_COUNT' "$e1_probe_guard" 2>/dev/null; then
      _red "wave-e-e1-digest" "NL-FINDING-021 probe guard missing from ${e1_probe_guard} (anomaly-count/health check before the alert write)"
    fi
  fi

  # --- E.7: session-resumer.sh (Check A always; Check B Windows-only /
  # --full-style honest warn, per the fragment's "Why WARN not RED"). ---
  local e7_script="${live_home}/scripts/session-resumer.sh"
  if [[ ! -f "$e7_script" ]]; then
    _warn "session-resumer" "session-resumer.sh missing from live mirror at ${e7_script} — E.7 not yet installed on this machine"
  else
    if [[ ! -x "$e7_script" ]]; then
      _red "session-resumer" "session-resumer.sh missing or not executable at ${e7_script}"
    elif ! grep -q -- '--self-test' "$e7_script" 2>/dev/null; then
      _red "session-resumer" "session-resumer.sh has no --self-test entrypoint"
    fi
    if command -v schtasks >/dev/null 2>&1; then
      if MSYS_NO_PATHCONV=1 schtasks /Query /TN "NL-session-resumer" >/dev/null 2>&1; then
        :
      else
        _warn "session-resumer" "scheduled task 'NL-session-resumer' not registered — documented (see session-resumer.sh header), not registered. Honest warn until specs-e §E.W.6 runs on this machine."
      fi
    fi
  fi

  # --- E.8: nl-issue.sh (predicate 1: exists+executable; predicate 2:
  # digest wiring grep, absence-tolerant on the digest hook itself). ---
  local e8_script="${live_home}/scripts/nl-issue.sh"
  if [[ ! -f "$e8_script" ]]; then
    _warn "wave-e-e8-nl-issue" "nl-issue.sh missing from live mirror at ${e8_script} — E.8 not yet installed on this machine"
  elif [[ ! -x "$e8_script" ]]; then
    _red "wave-e-e8-nl-issue" "nl-issue.sh exists but is not executable at ${e8_script}"
  fi
  if [[ -f "$e1_hook" ]]; then
    if ! grep -q "nl-issue.sh" "$e1_hook" 2>/dev/null; then
      _red "wave-e-e8-nl-issue" "session-start-digest.sh exists but does not wire nl-issue.sh (silent no-op digest feed)"
    fi
  fi

  # --- E.9: context-watermark.sh + pre-compact-continuity.sh (hook
  # presence + PostToolUse/PreCompact template wiring + handoff dir
  # writable). Mirrors check_wave_e_e9_precompaction from the fragment. ---
  local e9_template=""
  [[ -n "$repo_root" && -f "${repo_root}/adapters/claude-code/settings.json.template" ]] \
    && e9_template="${repo_root}/adapters/claude-code/settings.json.template"
  [[ -z "$e9_template" && -f "${live_home}/settings.json" ]] && e9_template="${live_home}/settings.json"

  # E.9 predicates are scoped to fire ONLY when the template actually wires
  # (or is expected to wire) these hooks — an unrelated settings.json
  # fixture (pre-Wave-E, or a doctor self-test fixture built for a
  # different check) that never mentions either hook name is simply
  # "E.9 not yet installed on this machine" (WARN, tolerate-absent — same
  # contract as the E.1/E.7/E.8 sub-checks above), NOT a RED. RED is
  # reserved for the case the fragment calls "the primary signal": the
  # template DOES reference one of the two hooks (so E.9 wiring was
  # attempted) but is missing the OTHER hook, missing a matcher, or the
  # hook file itself is absent from disk despite being wired.
  local e9_cw_wired=0 e9_pc_wired=0
  if [[ -n "$e9_template" ]]; then
    grep -q 'context-watermark\.sh' "$e9_template" 2>/dev/null && e9_cw_wired=1
    grep -q 'pre-compact-continuity\.sh' "$e9_template" 2>/dev/null && e9_pc_wired=1
  fi

  if [[ -z "$e9_template" ]]; then
    _warn "wave-e-e9-precompaction" "no settings template/live settings resolved — skipped"
  elif [[ "$e9_cw_wired" -eq 0 && "$e9_pc_wired" -eq 0 ]]; then
    _warn "wave-e-e9-precompaction" "neither context-watermark.sh nor pre-compact-continuity.sh referenced in ${e9_template} — E.9 not yet installed/wired on this machine"
  else
    local e9_hooks_dir="${repo_root}/adapters/claude-code/hooks"
    [[ -d "$e9_hooks_dir" ]] || e9_hooks_dir="${live_home}/hooks"
    if [[ ! -f "${e9_hooks_dir}/context-watermark.sh" ]]; then
      _red "wave-e-e9-precompaction" "context-watermark.sh missing from ${e9_hooks_dir} — run: bash install.sh (or restore from adapters/claude-code/hooks/)"
    fi
    if [[ ! -f "${e9_hooks_dir}/pre-compact-continuity.sh" ]]; then
      _red "wave-e-e9-precompaction" "pre-compact-continuity.sh missing from ${e9_hooks_dir} — run: bash install.sh (or restore from adapters/claude-code/hooks/)"
    fi

    if [[ "$e9_cw_wired" -eq 0 ]]; then
      _red "wave-e-e9-precompaction" "context-watermark.sh not wired into PostToolUse — add a PostToolUse entry (matcher covering all tools) invoking ~/.claude/hooks/context-watermark.sh"
    fi

    if [[ "$e9_pc_wired" -eq 0 ]]; then
      _red "wave-e-e9-precompaction" "pre-compact-continuity.sh not wired into PreCompact — add PreCompact entries for both auto and manual matchers invoking ~/.claude/hooks/pre-compact-continuity.sh"
    elif command -v node >/dev/null 2>&1; then
      local e9_matchers
      # NL-FINDING-033: feed the file via STDIN (fd 0), not as a path arg —
      # native Windows node cannot resolve MSYS paths ('/c/Users/...' becomes
      # 'C:\c\User...' → ENOENT → silent false-empty → false RED), whereas the
      # MSYS `cat` reads the path fine. Reading stdin sidesteps translation.
      e9_matchers="$(cat "$e9_template" 2>/dev/null | node -e "
        const fs=require('fs');
        let cfg;
        try { cfg = JSON.parse(fs.readFileSync(0,'utf8')); } catch(e) { process.exit(0); }
        const pc = (cfg.hooks && cfg.hooks.PreCompact) || [];
        console.log(pc.map(b => b.matcher).join(','));
      " 2>/dev/null)"
      if ! printf '%s' "$e9_matchers" | grep -q 'auto' || ! printf '%s' "$e9_matchers" | grep -q 'manual'; then
        _red "wave-e-e9-precompaction" "PreCompact chain missing one of the auto/manual matchers (found: '${e9_matchers}') — pre-compact-continuity.sh must be wired on BOTH"
      fi
    fi

    local e9_handoff_dir="${HOME:-}/.claude/state/session-handoff"
    if ! mkdir -p "$e9_handoff_dir" 2>/dev/null || ! touch "${e9_handoff_dir}/.doctor-write-probe" 2>/dev/null; then
      _red "wave-e-e9-precompaction" "session-handoff directory not writable: ${e9_handoff_dir} — check permissions"
    else
      rm -f "${e9_handoff_dir}/.doctor-write-probe" 2>/dev/null || true
    fi
  fi

  # E.6 (needs-you.sh) doctor predicate — implemented at §E.W integration
  # verbatim per adapters/claude-code/tests/fixtures/wave-e/E.6/doctor-predicate.md
  # (Predicate 1: script exists+executable+--self-test; Predicate 2: NEEDS-YOU.md
  # freshness ≤7d whenever an Awaiting-decision item is open — tolerate-absent when
  # the ledger has never been created). (E.5 harness-kpis predicate remains an
  # optional follow-up; E.5's Done-when was met without a doctor check.)
  #
  # NL-FINDING (F.1 fix, found running the doctor's own --self-test on
  # master before this wave's changes): predicate 1 used to RED
  # unconditionally when needs-you.sh was absent, instead of the
  # tolerate-absent WARN every sibling E.1/E.7/E.8/E.9 sub-check uses for
  # "not yet installed on THIS machine/fixture" — a bare mktemp -d fixture
  # (every self-test scenario in this file) naturally lacks
  # scripts/needs-you.sh, so this made check_wave_e_surfaces RED on every
  # single self-test scenario regardless of what that scenario was
  # actually testing, masking real self-test signal entirely. Also fixed:
  # ny_state read from literal "${HOME}" instead of the passed-in
  # live_home, so a self-test run (which sandboxes via
  # HARNESS_DOCTOR_HOME, not HOME) leaked the REAL machine's
  # needs-you ledger into every fixture's verdict (the same class of bug
  # as NL-FINDING-025/028 — self-test state must never escape to the real
  # machine's paths).
  local ny_script="${repo_root}/adapters/claude-code/scripts/needs-you.sh"
  if [[ ! -f "$ny_script" ]]; then
    _warn "wave-e-e6-needs-you" "needs-you.sh missing at ${ny_script} — E.6 not yet installed on this machine"
  elif [[ ! -x "$ny_script" ]]; then
    _red "wave-e-e6-needs-you" "needs-you.sh present but not executable — chmod +x ${ny_script}"
  elif ! grep -q -- '--self-test' "$ny_script"; then
    _red "wave-e-e6-needs-you" "needs-you.sh missing a --self-test entrypoint despite its manifest selftest claim"
  fi
  local ny_nlpaths="${repo_root}/adapters/claude-code/hooks/lib/nl-paths.sh"
  local ny_main_root=""
  [[ -f "$ny_nlpaths" ]] && ny_main_root=$(bash -c "source '$ny_nlpaths'; nl_main_checkout_root" 2>/dev/null)
  [[ -n "$ny_main_root" ]] || ny_main_root="$repo_root"
  local ny_md="${ny_main_root}/NEEDS-YOU.md"
  local ny_state="${live_home}/state/needs-you/ledger.json"
  if [[ -f "$ny_state" ]] && command -v jq >/dev/null 2>&1; then
    local ny_open
    ny_open=$(jq '[.items[] | select(.section == "decision" and .state == "open")] | length' "$ny_state" 2>/dev/null || echo 0)
    if [[ "${ny_open:-0}" -gt 0 ]]; then
      if [[ ! -f "$ny_md" ]]; then
        _red "wave-e-e6-needs-you" "NEEDS-YOU.md missing at main-checkout root (${ny_md}) despite ${ny_open} open decision item(s) — run: bash adapters/claude-code/scripts/needs-you.sh render"
      else
        local ny_now ny_mtime ny_age
        ny_now=$(date -u +%s)
        ny_mtime=$(stat -c %Y "$ny_md" 2>/dev/null || stat -f %m "$ny_md" 2>/dev/null || echo 0)
        ny_age=$(( ny_now - ny_mtime ))
        if [[ "$ny_age" -gt $((7 * 86400)) ]]; then
          _red "wave-e-e6-needs-you" "NEEDS-YOU.md is $((ny_age / 86400))d stale despite ${ny_open} open decision item(s) — run: bash adapters/claude-code/scripts/needs-you.sh render"
        fi
      fi
    fi
  fi
  CHECKS_RUN=$((CHECKS_RUN + 1))
}

# ------------------------------------------------------------
# Check: heartbeat-task (NL-FINDING-022, specs-e §E.10 item 6 — DECISION:
# WIRE). Verifies the `NL-workstreams-heartbeat` scheduled task exists.
# WARN (not RED) when schtasks is unavailable (non-Windows) or the task
# is not yet registered (honest-status territory pre-§E.W, mirrors the
# E.7 session-resumer predicate's own WARN rationale) — this doctor
# check's job is "did install.sh's registration code run/succeed", not
# "punish a machine that hasn't run install.sh since this task shipped".
# ------------------------------------------------------------
check_heartbeat_task() {
  local live_home="$1" repo_root="$2"
  if ! command -v schtasks >/dev/null 2>&1; then
    _warn "heartbeat-task" "schtasks not available on this platform — scheduled-task check skipped (non-Windows)"
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi
  if MSYS_NO_PATHCONV=1 schtasks /Query /TN "NL-workstreams-heartbeat" >/dev/null 2>&1; then
    :
  else
    _warn "heartbeat-task" "scheduled task 'NL-workstreams-heartbeat' not registered — run: bash adapters/claude-code/install.sh (registers workstreams-emit.sh --heartbeat every 5 min)"
  fi
  CHECKS_RUN=$((CHECKS_RUN + 1))
}

# ------------------------------------------------------------
# Check: untracked-dirt-ignore-rule (NL-FINDING-026 class 2, specs-e
# §E.10 item 9). Verifies the ignore rule work-integrity-gate's check (c)
# now hard-codes (grep -v .claude/state) is ALSO backed by this repo's own
# .gitignore, so a governed repo relying on .gitignore (rather than the
# gate's built-in exclusion alone) stays honest. WARN (not RED) when the
# repo is unresolved — this is a hygiene check on the governed repo the
# doctor is running against, not a hard gate on every possible caller.
# ------------------------------------------------------------
check_untracked_dirt_ignore_rule() {
  local repo_root="$2"
  [[ -z "$repo_root" ]] && { _warn "untracked-dirt-ignore-rule" "repo root unresolved — skipped"; CHECKS_RUN=$((CHECKS_RUN + 1)); return 0; }
  local gi="${repo_root}/.gitignore"
  if [[ ! -f "$gi" ]]; then
    _warn "untracked-dirt-ignore-rule" "no .gitignore found at ${gi} — cannot verify .claude/state/ ignore rule (work-integrity-gate's check-c exclusion still applies unconditionally as a code-level fallback)"
  elif ! grep -qE '(^|[^#])\.claude/state/?[[:space:]]*$' "$gi" 2>/dev/null; then
    _warn "untracked-dirt-ignore-rule" ".gitignore at ${gi} does not appear to ignore .claude/state/ — work-integrity-gate's check-c grep -v exclusion covers this in code, but the repo's own .gitignore should too (NL-FINDING-026 class 2)"
  fi
  CHECKS_RUN=$((CHECKS_RUN + 1))
}

# ============================================================
# NL Observability Program Wave O, task O.6 (specs-o §O.6): six pipeline-
# health predicates. Spliced verbatim from
# tests/fixtures/wave-o/O.6/doctor-predicate.md (orchestrator integration,
# batch 2). Placement: immediately after check_untracked_dirt_ignore_rule,
# before check_pin_f_waiver_purpose_clauses, per the fragment's own
# suggested insertion point.
# ============================================================

# ------------------------------------------------------------
# Check: obs-writers-firing (specs-o §O.6 item 1). Ledger mtime <24h AND
# line-count grew since the doctor's own last-seen stamp
# (${live_home}/state/doctor-cache/obs-ledger-stamp.txt, self-updating).
# A ledger that exists but has gone stale/stopped-growing means every
# writer upstream silently died. First-ever run (stamp absent) always
# passes and just seeds the baseline.
# ------------------------------------------------------------
check_obs_writers_firing() {
  local live_home="$1" repo_root="$2"
  local ledger="${live_home}/state/signal-ledger.jsonl"

  if [[ ! -f "$ledger" ]]; then
    _warn "obs-writers-firing" "signal ledger not found at ${ledger} — observability pipeline not yet installed/run on this machine"
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi

  local now_epoch mtime_epoch age_hours
  now_epoch=$(date -u +%s 2>/dev/null || echo 0)
  mtime_epoch=$(stat -c %Y "$ledger" 2>/dev/null || stat -f %m "$ledger" 2>/dev/null || echo 0)
  age_hours=$(( (now_epoch - mtime_epoch) / 3600 ))

  if [[ "$age_hours" -gt 24 ]]; then
    _red "obs-writers-firing" "signal ledger ${ledger} has not been written to in ${age_hours}h (budget 24h) — every ledger writer may have silently stopped firing; check session-start-digest.sh/stop-verdict-dispatcher.sh/workstreams-stop-writer.sh wiring"
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi

  local line_count
  line_count=$(wc -l < "$ledger" 2>/dev/null | tr -d ' ')
  [[ -n "$line_count" ]] || line_count=0

  local stamp_dir="${live_home}/state/doctor-cache"
  local stamp_file="${stamp_dir}/obs-ledger-stamp.txt"
  mkdir -p "$stamp_dir" 2>/dev/null || true

  if [[ ! -f "$stamp_file" ]]; then
    printf '%s %s\n' "$mtime_epoch" "$line_count" > "$stamp_file" 2>/dev/null || true
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi

  local prev_mtime prev_lines
  read -r prev_mtime prev_lines < "$stamp_file" 2>/dev/null
  prev_mtime="${prev_mtime:-0}"
  prev_lines="${prev_lines:-0}"

  if [[ "$mtime_epoch" -le "$prev_mtime" || "$line_count" -le "$prev_lines" ]]; then
    _red "obs-writers-firing" "signal ledger ${ledger} has NOT grown since the last doctor check (was ${prev_lines} lines at mtime ${prev_mtime}, now ${line_count} lines at mtime ${mtime_epoch}) despite being <24h old — writers may be looping without emitting, or the file was truncated/rotated without the rotation being reflected here"
  fi

  printf '%s %s\n' "$mtime_epoch" "$line_count" > "$stamp_file" 2>/dev/null || true
  CHECKS_RUN=$((CHECKS_RUN + 1))
}

# ------------------------------------------------------------
# Check: obs-heartbeats-fresh (specs-o §O.6 item 2, re-fixed 2026-07-06 —
# see "CANONICAL-ORACLE FIX" below). Every session with a transcript
# mtime <30min must have a heartbeat file that is NOT classified `missing`
# by the canonical read-side oracle (else RED naming the missing sids).
# Zero live sessions is GREEN.
#
# ORCHESTRATOR FIX (found running this predicate's own self-test
# scenarios against the full suite, batch 2): the fragment's original
# default fell back to "${HOME}/.claude/projects" — the REAL machine's
# transcript tree — rather than deriving from $live_home (which every
# self-test scenario already sandboxes via HARNESS_DOCTOR_HOME). That
# leaked this machine's real live sessions into EVERY OTHER unrelated
# doctor self-test scenario that doesn't explicitly set
# OBS_TRANSCRIPTS_DIR, RED-ing them all with "N session(s) ... no
# heartbeat directory". Default now derives from $live_home
# (${live_home}/projects, i.e. $HOME/.claude/projects when live_home is
# the real $HOME/.claude — see resolve_live_home) so a sandboxed
# HARNESS_DOCTOR_HOME automatically isolates transcripts too; explicit
# OBS_TRANSCRIPTS_DIR still overrides for fixtures that want a flat
# (non-nested) layout.
#
# CANONICAL-ORACLE FIX (O.6 re-verifier round, FAIL conf 9 —
# duplicated-staleness-oracle / mid-turn false-stall): this predicate used
# to re-implement its OWN raw heartbeat-file-mtime staleness math (an
# equal 30/30-minute window against the heartbeat file's mtime alone).
# That duplicated (and silently diverged from) the canonical read-side
# oracle in hooks/lib/session-heartbeat-lib.sh (`hb_classify`/
# `hb_is_stale`), which already carries the C1 transcript-mtime join: a
# long, tool-heavy turn produces no NEW heartbeat write for its entire
# duration (heartbeats only refresh at Stop), so a session whose current
# turn simply runs past 30 minutes has a stale-BY-MTIME heartbeat file
# while being demonstrably alive (its transcript is still being appended
# to). The old raw-mtime math could not see that and false-REDed the
# session's own heartbeat mid-turn. Fixed by sourcing the canonical lib
# and reusing `hb_classify` instead of re-deriving staleness locally —
# per CANONICAL-COUNTERS-01, two implementations of "is this heartbeat
# stale" drifting apart is exactly the bug class this predicate must not
# reintroduce. RED now fires ONLY on `missing` (the genuine
# writer-not-wired signal: no heartbeat file exists at all for a session
# with a fresh transcript) — a PRESENT-but-stale-by-mtime heartbeat
# resolves through the lib's own transcript-mtime join and is classified
# `live` (or, if genuinely stalled/throttled/crashed by the lib's own
# pid + api-error-tail checks, `stale`/`throttled`/`crashed` — none of
# which this doctor predicate treats as a writer-wiring failure; only
# `missing` is).
# ------------------------------------------------------------
check_obs_heartbeats_fresh() {
  local live_home="$1" repo_root="$2"
  local hb_dir="${live_home}/state/heartbeats"
  local transcripts_dir="${OBS_TRANSCRIPTS_DIR:-${live_home}/projects}"

  if [[ ! -d "$transcripts_dir" ]]; then
    _warn "obs-heartbeats-fresh" "no transcripts directory at ${transcripts_dir} — nothing to check (zero live sessions)"
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi

  local now_epoch
  now_epoch=$(date -u +%s 2>/dev/null || echo 0)

  local -a live_sids=()
  local f mtime age_min sid
  # ORCHESTRATOR FIX (verifier-round FAIL, O.6 conf 9): a session's
  # subagent transcripts live under <sid>/subagents/*.jsonl (and future
  # workflow sub-transcripts under <sid>/workflows/*.jsonl) — these are
  # NOT independent sessions and never write their own heartbeat file
  # (only the top-level session heartbeat writer runs), so counting them
  # as "sessions requiring a heartbeat" false-REDs this check on any
  # estate with recent agent/subagent activity, which is the common case.
  # Exclude both path shapes from enumeration entirely.
  while IFS= read -r -d '' f; do
    case "$f" in
      */subagents/*|*/workflows/*) continue ;;
    esac
    mtime=$(stat -c %Y "$f" 2>/dev/null || stat -f %m "$f" 2>/dev/null || echo 0)
    age_min=$(( (now_epoch - mtime) / 60 ))
    if [[ "$age_min" -lt 30 ]]; then
      sid="$(basename "$f" .jsonl)"
      live_sids+=("$sid")
    fi
  done < <(find "$transcripts_dir" -type f -name '*.jsonl' -print0 2>/dev/null)

  if [[ "${#live_sids[@]}" -eq 0 ]]; then
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi

  if [[ ! -d "$hb_dir" ]]; then
    _red "obs-heartbeats-fresh" "${#live_sids[@]} session(s) have a transcript <30min old but no heartbeat directory exists at ${hb_dir} — session-heartbeat.sh touch is not wired or O.2 is not installed on this machine"
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi

  # Source the canonical read-side oracle (hb_classify/hb_is_stale) once.
  # Guarded by the lib's own source-guard (_SESSION_HEARTBEAT_LIB_SOURCED),
  # so re-sourcing across repeated check invocations in the same process
  # is a safe no-op.
  local hb_lib="${SCRIPT_DIR}/lib/session-heartbeat-lib.sh"
  if [[ -f "$hb_lib" ]]; then
    # shellcheck disable=SC1090
    source "$hb_lib"
  fi

  local -a stale_sids=()
  for sid in "${live_sids[@]}"; do
    local hbf="${hb_dir}/${sid}.json"
    if ! command -v hb_classify >/dev/null 2>&1; then
      # Canonical lib unavailable (should not happen on an installed
      # estate) — degrade to the one check we CAN still make honestly:
      # file presence. Never re-derive mtime staleness locally here again.
      if [[ ! -f "$hbf" ]]; then
        stale_sids+=("${sid}:missing")
      fi
      continue
    fi
    # HEARTBEAT_STATE_DIR / OBS_TRANSCRIPTS_ROOT bridge this doctor
    # predicate's own sandboxing vars (HARNESS_DOCTOR_HOME-derived
    # $hb_dir / $transcripts_dir) into the lib's env-var contract so its
    # transcript-mtime join (_hb_find_transcript) looks in the SAME
    # sandboxed fixture tree this check just enumerated, not the real
    # machine's $HOME/.claude estate.
    local cls
    cls="$(HEARTBEAT_STATE_DIR="$hb_dir" OBS_TRANSCRIPTS_ROOT="$transcripts_dir" hb_classify "$hbf" 30)"
    if [[ "$cls" == "missing" ]]; then
      stale_sids+=("${sid}:missing")
    fi
  done

  if [[ "${#stale_sids[@]}" -gt 0 ]]; then
    _red "obs-heartbeats-fresh" "$(IFS=,; echo "${stale_sids[*]}") — session(s) with a transcript <30min old have NO heartbeat file at all; the heartbeat writer may not be wired into this session's chain (see tests/fixtures/wave-o/O.2/callsite-wiring.md)"
  fi
  CHECKS_RUN=$((CHECKS_RUN + 1))
}

# ------------------------------------------------------------
# Check: obs-scheduled-tasks (specs-o §O.6 item 3, SCHEDULED-TASK-HEALTH-01).
# Every registered NL-owned task (via scripts/scheduled-task-health.sh
# list) has Last Result in {0, 267009, 267011}; else RED naming the task +
# code. Not-registered stays the existing WARN semantics elsewhere.
# ------------------------------------------------------------
check_obs_scheduled_tasks() {
  local live_home="$1" repo_root="$2"
  local script=""
  [[ -n "$repo_root" && -f "${repo_root}/adapters/claude-code/scripts/scheduled-task-health.sh" ]] \
    && script="${repo_root}/adapters/claude-code/scripts/scheduled-task-health.sh"
  [[ -z "$script" && -f "${live_home}/scripts/scheduled-task-health.sh" ]] \
    && script="${live_home}/scripts/scheduled-task-health.sh"

  if [[ -z "$script" ]]; then
    _warn "obs-scheduled-tasks" "scheduled-task-health.sh missing — O.6 not yet installed on this machine"
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi
  if ! command -v schtasks >/dev/null 2>&1 && [[ -z "${SCHTASKS_CMD:-}" ]]; then
    _warn "obs-scheduled-tasks" "schtasks not available on this platform — scheduled-task health check skipped (non-Windows)"
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi

  local out
  out="$(bash "$script" list 2>/dev/null)"
  if [[ -z "$out" ]]; then
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi

  local line name code bad=0
  while IFS=$'\t' read -r name code; do
    [[ -z "$name" ]] && continue
    case "$code" in
      0|267009|267011) ;;
      *)
        _red "obs-scheduled-tasks" "task '${name}' Last Result=${code} (expected one of 0/267009/267011) — check the task's registered command path; run: MSYS_NO_PATHCONV=1 schtasks /Query /V /FO LIST /TN \"${name}\""
        bad=1
        ;;
    esac
  done <<< "$out"

  CHECKS_RUN=$((CHECKS_RUN + 1))
}

# ------------------------------------------------------------
# Check: obs-consumer-map (specs-o §O.6 item 4, contract C3's enforcing
# predicate). Two-sided: (a) every event type observed in the ledger's
# last 1000 lines has an entry in observability-consumer-map.json; (b)
# every literal event-type string passed as the SECOND argument to
# ledger_emit/ledger_emit_typed anywhere in the repo has an entry; (c)
# every entry in the map has >=1 consumer. Unknown-in-map = RED naming
# the type. The literal-scan filters out variable-named 2nd-args
# (grep -vE '^\$') — several real pre-existing call sites
# (stop-verdict-dispatcher.sh, work-integrity-gate.sh, session-resumer.sh,
# test-gate.sh's own self-test) pass a variable, not a literal, as the
# 2nd arg; without the filter this predicate would RED on bogus
# "unmapped event type '$ev'" noise. CRLF: `tr -d '\r'` on the ledger-side
# jq output is required — this machine's real ledger round-trips through
# jq with CRLF line endings (findings 030/038-class).
# ------------------------------------------------------------
check_obs_consumer_map() {
  local live_home="$1" repo_root="$2"
  local map=""
  [[ -n "$repo_root" && -f "${repo_root}/adapters/claude-code/observability-consumer-map.json" ]] \
    && map="${repo_root}/adapters/claude-code/observability-consumer-map.json"
  [[ -z "$map" && -f "${live_home}/observability-consumer-map.json" ]] \
    && map="${live_home}/observability-consumer-map.json"

  if [[ -z "$map" ]]; then
    _warn "obs-consumer-map" "observability-consumer-map.json not found — O.1 not yet installed on this machine"
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi
  if ! command -v jq >/dev/null 2>&1; then
    _warn "obs-consumer-map" "jq not available — cannot verify observability-consumer-map.json coverage"
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi
  if ! jq -e . "$map" >/dev/null 2>&1; then
    _red "obs-consumer-map" "${map} is not valid JSON"
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi

  # (c) every map entry has >=1 consumer
  local empty_entries
  empty_entries="$(jq -r '.event_types | to_entries[] | select((.value.consumers // []) | length == 0) | .key' "$map" 2>/dev/null)"
  if [[ -n "$empty_entries" ]]; then
    _red "obs-consumer-map" "event type(s) with zero consumers in ${map}: $(printf '%s' "$empty_entries" | tr '\n' ',' | sed 's/,$//')"
  fi

  # (a) every ledger-observed event type (last 1000 lines) is in the map.
  local ledger="${live_home}/state/signal-ledger.jsonl"
  if [[ -f "$ledger" ]]; then
    local unmapped_ledger
    unmapped_ledger="$(tail -n 1000 "$ledger" 2>/dev/null | jq -r '.event // empty' 2>/dev/null | tr -d '\r' | sort -u | while read -r ev; do
      [[ -z "$ev" ]] && continue
      jq -e --arg e "$ev" '.event_types | has($e)' "$map" >/dev/null 2>&1 || echo "$ev"
    done)"
    if [[ -n "$unmapped_ledger" ]]; then
      _red "obs-consumer-map" "ledger event type(s) observed in last 1000 lines but absent from ${map}: $(printf '%s' "$unmapped_ledger" | tr '\n' ',' | sed 's/,$//')"
    fi
  fi

  # (b) every literal ledger_emit(_typed) 2nd-arg literal in the repo is in
  # the map. grep -vE '^\$' filters variable-named 2nd-args (see header
  # comment above).
  if [[ -n "$repo_root" ]]; then
    local unmapped_repo
    unmapped_repo="$(grep -rhoE 'ledger_emit(_typed)?[[:space:]]+"[^"]*"[[:space:]]+"[^"]*"' \
        "${repo_root}/adapters/claude-code/hooks" "${repo_root}/adapters/claude-code/scripts" 2>/dev/null \
      | sed -E 's/ledger_emit(_typed)?[[:space:]]+"[^"]*"[[:space:]]+"([^"]*)"/\2/' \
      | grep -vE '^\$' \
      | sort -u | while read -r ev; do
        [[ -z "$ev" ]] && continue
        jq -e --arg e "$ev" '.event_types | has($e)' "$map" >/dev/null 2>&1 || echo "$ev"
      done)"
    if [[ -n "$unmapped_repo" ]]; then
      _red "obs-consumer-map" "literal ledger_emit event type(s) found in repo source but absent from ${map}: $(printf '%s' "$unmapped_repo" | tr '\n' ',' | sed 's/,$//')"
    fi
  fi

  CHECKS_RUN=$((CHECKS_RUN + 1))
}

# ------------------------------------------------------------
# Check: obs-cockpit-fresh (specs-o §O.6 item 5; semantics upgraded
# 2026-07-09 review fix — supersedes the spec's original "WARN-only"
# posture, see gate-change record below). Probes the cockpit's
# /api/health and grades the BODY, not just the listener:
#   no listener / no response      -> WARN (cockpit not up while sessions
#                                     are live; the SessionStart ensure
#                                     should have started it)
#   200 + "lobotomized":true       -> RED  (cockpit up but panes not
#                                     deriving: rc!=0 across ALL panes
#                                     with server uptime >120s — the
#                                     server's own judgment, not
#                                     re-derived here)
#   200, `lobotomized` field ABSENT-> WARN when "any_pane_failed":true
#     (older server build)            (cannot distinguish transient from
#                                     wedged without the uptime guard)
#   else                           -> GREEN
#
# Gate-change record (constitution §10 — evidence bar for the new RED):
#   golden scenario: 2026-07-09 — cockpit lobotomized ALL DAY (every pane
#     rc!=0, UI rendering stale/empty panes) with ZERO doctor signal: the
#     prior check gated on a schtask name nothing registered (and the
#     logon task itself was retired that same day) and keyed on
#     ~/.claude/state/workstreams-cache/derived-cache-stamp.txt, a file
#     NO production code writes — double-dead theater (nl-issue [56] +
#     2026-07-09 audit).
#   expected false positives: transient first-refresh pane failures —
#     guarded server-side by the lobotomized semantics (ALL panes failed
#     AND uptime >120s); transients surface at most as the WARN tier via
#     any_pane_failed on older server builds lacking the field.
#   retirement condition: cockpit surface retirement (workstreams-ui +
#     ensure-cockpit.sh removed).
#
# Gates (each a silent GREEN skip):
#   1. cockpit code present: ${repo_root}/neural-lace/workstreams-ui/
#      server (the ACTUAL O.4 build location; nl-issue [56] drift layer 2
#      was checking a flat path where the build never lived).
#   2. Windows/MSYS only — matches ensure-cockpit.sh's OS guard (the
#      launcher is a .ps1; on any other OS the cockpit cannot be expected
#      up). Fixture override: OBS_COCKPIT_UNAME_OVERRIDE (same idiom as
#      ENSURE_COCKPIT_UNAME_OVERRIDE) so the self-test runs on Linux CI.
#   3. operator kill-switch ${live_home}/local/cockpit-disabled — the
#      same durable off-switch ensure-cockpit.sh honors; disabled means
#      "not up" is intended, not a defect.
#   4. launch mechanism installed: ${live_home}/scripts/ensure-cockpit.sh
#      — the session-tied SessionStart ensure (session-start-digest.sh ->
#      launch-gui.ps1) that replaced the retired logon scheduled task
#      (bf2b8c7, 2026-07-09; docs/HANDOFF.md). Absent = cockpit not
#      expected on this machine (e.g. mid-install).
#   5. live-session signal: >=1 heartbeat *.json under
#      ${live_home}/state/heartbeats fresher than 30min (the O.2
#      liveness files). No live sessions -> cockpit legitimately idle.
#   6. curl present (probe unobservable otherwise; never guess).
# Health URL: http://127.0.0.1:7733/api/health (server.js fixed default;
# launch-gui.ps1 -Port matches); env override OBS_COCKPIT_HEALTH_URL for
# fixtures/manual probing. Body parsing: jq when available, grep
# fallback (file convention). Self-test controls the probe via a
# PATH-injected `curl` stub that prints fixture health JSON.
# ------------------------------------------------------------
check_obs_cockpit_fresh() {
  local live_home="$1" repo_root="$2"

  # Gate 1 — cockpit code present in the repo.
  if [[ -z "$repo_root" || ! -d "${repo_root}/neural-lace/workstreams-ui/server" ]]; then
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi

  # Gate 2 — Windows/MSYS only (the cockpit launcher is a .ps1).
  local uname_s
  uname_s="${OBS_COCKPIT_UNAME_OVERRIDE:-$(uname -s 2>/dev/null || echo unknown)}"
  case "$uname_s" in
    MINGW*|MSYS*|CYGWIN*|Windows_NT*) : ;;
    *)
      CHECKS_RUN=$((CHECKS_RUN + 1))
      return 0
      ;;
  esac

  # Gate 3 — operator kill-switch: cockpit deliberately disabled.
  if [[ -n "$live_home" && -f "${live_home}/local/cockpit-disabled" ]]; then
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi

  # Gate 4 — session-tied launch mechanism absent -> cockpit not expected
  # on this machine: GREEN skip.
  if [[ -z "$live_home" || ! -f "${live_home}/scripts/ensure-cockpit.sh" ]]; then
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi

  # Gate 5 — live-session signal (fresh O.2 heartbeat files, <30min).
  local hb_dir="${live_home}/state/heartbeats"
  local now_epoch any_live=0
  now_epoch=$(date -u +%s 2>/dev/null || echo 0)
  if [[ -d "$hb_dir" ]]; then
    local f mtime age_min
    while IFS= read -r -d '' f; do
      mtime=$(stat -c %Y "$f" 2>/dev/null || stat -f %m "$f" 2>/dev/null || echo 0)
      age_min=$(( (now_epoch - mtime) / 60 ))
      [[ "$age_min" -lt 30 ]] && any_live=1
    done < <(find "$hb_dir" -maxdepth 1 -type f -name '*.json' -print0 2>/dev/null)
  fi
  if [[ "$any_live" -eq 0 ]]; then
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi

  # Gate 6 — no curl on this machine: liveness unobservable -> GREEN skip
  # (best-effort probe; never guess).
  if ! command -v curl >/dev/null 2>&1; then
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi

  local health_url="${OBS_COCKPIT_HEALTH_URL:-http://127.0.0.1:7733/api/health}"
  local body=""
  # -f: HTTP >=400 fails the probe (a 404/500 responder is NOT a healthy
  # cockpit). Harness-review Major 2026-07-09: without positive
  # identification, any responder on :7733 graded GREEN — the silent-GREEN
  # class this check exists to kill, reincarnated.
  if ! body="$(curl -sf --max-time 3 "$health_url" 2>/dev/null)" || [[ -z "$body" ]]; then
    _warn "obs-cockpit-fresh" "cockpit not up (${health_url} not answering) while sessions are live — the SessionStart ensure (scripts/ensure-cockpit.sh) should have started it; the next SessionStart digest re-ensures, or run neural-lace/workstreams-ui/scripts/launch-gui.ps1"
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi

  # Positive identification: every O.4+ cockpit build emits the
  # any_pane_failed key. A responder without it (foreign listener's HTML,
  # a proxy error page, a pre-O.4 build) is graded as NOT-a-cockpit —
  # WARN, never GREEN.
  if ! printf '%s' "$body" | grep -q '"any_pane_failed"'; then
    _warn "obs-cockpit-fresh" "unrecognized listener on ${health_url} (response lacks the any_pane_failed health marker) — something else holds port 7733, or the server predates the O.4 rebuild; the cockpit is effectively down. Identify the process holding the port, then restart via neural-lace/workstreams-ui/scripts/launch-gui.ps1"
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi

  # Grade the health body. jq when available; grep fallback tolerant of
  # older server builds without the `lobotomized` field.
  local lob="absent" apf="false"
  if command -v jq >/dev/null 2>&1 && printf '%s' "$body" | jq -e . >/dev/null 2>&1; then
    lob="$(printf '%s' "$body" | jq -r 'if has("lobotomized") then (.lobotomized|tostring) else "absent" end' 2>/dev/null || echo absent)"
    apf="$(printf '%s' "$body" | jq -r '.any_pane_failed // false | tostring' 2>/dev/null || echo false)"
  else
    if printf '%s' "$body" | grep -qE '"lobotomized"[[:space:]]*:[[:space:]]*true'; then
      lob="true"
    elif printf '%s' "$body" | grep -q '"lobotomized"'; then
      lob="false"
    fi
    printf '%s' "$body" | grep -qE '"any_pane_failed"[[:space:]]*:[[:space:]]*true' && apf="true"
  fi

  if [[ "$lob" == "true" ]]; then
    _red "obs-cockpit-fresh" "cockpit up but lobotomized — panes not deriving (rc!=0 across all panes with uptime >120s, per ${health_url}); the UI is rendering stale/empty panes; restart via neural-lace/workstreams-ui/scripts/launch-gui.ps1. DISCRIMINATOR: if a FRESH instance reports lobotomized again within minutes, the cause is the nl estate (CLI broken / all panes timing out), not the server env — run 'nl status --json' by hand and read the per-pane stderr_tails at ${health_url}"
  elif [[ "$lob" == "absent" && "$apf" == "true" ]]; then
    _warn "obs-cockpit-fresh" "cockpit up with >=1 failing pane (any_pane_failed=true; older server build without the lobotomized field, so transient-vs-wedged cannot be distinguished) — check ${health_url}"
  else
    # --------------------------------------------------------
    # ask-rooted-workstreams-p1 Task 17(a)/(b) EXTENSION (not a new
    # predicate — same obs-cockpit-fresh name, per the plan's explicit
    # "extend the existing check, don't duplicate" instruction). Only
    # reached when the health body ITSELF graded clean above (neither
    # lobotomized nor the legacy any_pane_failed fallback) — a cockpit
    # that is already RED/WARN for a health reason is not further
    # diagnosed here; these two probes add FINER-GRAINED failure
    # detection on top of an otherwise-healthy cockpit, they do not
    # re-derive cockpit health.
    #
    # (a) Anti-noise/absolute-href schema check, surfaced live: the
    # server already self-validates every /api/asks response against
    # payload-schema.js's allowlist BEFORE it hits the wire (Task 11,
    # server.js) and degrades to a 500 `{ok:false,
    # error:"payload schema validation failed", diagnostics:[...]}`
    # rather than ever leaking the bad payload. This predicate does NOT
    # re-run validateLanding/validateAskDetail itself (that would be a
    # re-derivation, exactly the class this check exists to avoid) — it
    # reads the mechanism's OWN verdict off the wire, the same way the
    # lobotomized grading above reads the server's own judgment rather
    # than re-deriving pane health locally. Deliberately no `-f` on this
    # curl: `-f` discards the body on HTTP>=400, and the failure body
    # (the exact diagnostic this check greps for) rides on a 500.
    local asks_url="${OBS_COCKPIT_ASKS_URL:-http://127.0.0.1:7733/api/asks}"
    local asks_body
    asks_body="$(curl -s --max-time 3 "$asks_url" 2>/dev/null)"
    if [[ -n "$asks_body" ]] \
       && printf '%s' "$asks_body" | grep -q '"error"[[:space:]]*:[[:space:]]*"payload schema validation failed"'; then
      _red "obs-cockpit-fresh" "ask-landing payload at ${asks_url} is FAILING its own anti-noise/absolute-href schema validation (payload-schema.js, Task 11) — a gate/hook identifier or a relative href reached the landing builder and the server correctly refused to ship it; curl ${asks_url} for the diagnostics[] detail and fix the offending field at its source"
    fi

    # (b) Waiting-on-you count reconciliation (sketch §8-3): the
    # background auditor (Task 12) already compares the ledger-parsed
    # open-decision count against the count actually rendered across
    # every ask's waiting_count and publishes the verdict at
    # GET /api/diagnostics/drift (`count_reconciliation.mismatch`). This
    # predicate reads that PUBLISHED verdict — it does not re-parse
    # NEEDS-YOU.md or re-walk progress logs itself (that would duplicate
    # auditor.js's own reconciliation, the exact drift class review
    # round 1 flagged for a re-derived population filter). A mismatch
    # means an open decision exists that no ask's log references at all
    # — it would otherwise silently vanish from the landing.
    local drift_url="${OBS_COCKPIT_DIAGNOSTICS_URL:-http://127.0.0.1:7733/api/diagnostics/drift}"
    local drift_body
    drift_body="$(curl -s --max-time 3 "$drift_url" 2>/dev/null)"
    if [[ -n "$drift_body" ]]; then
      local recon_mismatch="false"
      if command -v jq >/dev/null 2>&1 && printf '%s' "$drift_body" | jq -e . >/dev/null 2>&1; then
        recon_mismatch="$(printf '%s' "$drift_body" | jq -r '.count_reconciliation.mismatch // false | tostring' 2>/dev/null || echo false)"
      else
        printf '%s' "$drift_body" | grep -qE '"count_reconciliation"[^}]*"mismatch"[[:space:]]*:[[:space:]]*true' && recon_mismatch="true"
      fi
      if [[ "$recon_mismatch" == "true" ]]; then
        _red "obs-cockpit-fresh" "waiting-on-you count reconciliation MISMATCH at ${drift_url} (design sketch §8-3) — the auditor's ledger-parsed open-decision count disagrees with the count actually rendered across every ask's waiting_count; an open NEEDS-YOU decision may be silently missing from the landing. See ${drift_url}'s count_reconciliation.unaccounted_needs_you_ids for the specific id(s)"
      fi
    fi
  fi
  CHECKS_RUN=$((CHECKS_RUN + 1))
}

# ------------------------------------------------------------
# Check: obs-ask-capture-completeness (ask-rooted-workstreams-p1 Task 17c;
# Task 9's own invariant, restated in its "Prove it works" step 5: "doctor
# predicate from Task 17 counts trailing-24h sessions lacking a registered
# ask — must be 0 on every future doctor run, so regressions surface
# without anyone re-testing by hand").
#
# POPULATION-PARITY LAW (review round 1, systems Minor 8 — the single most
# important correctness property of this predicate): the population this
# check audits MUST be filtered by the IDENTICAL predicate Task 9's
# automatic-capture guard uses to decide who registers an ask in the first
# place — `pl_classify_session` in hooks/lib/progress-log-lib.sh. A
# RE-DERIVED filter here (e.g. "skip anything under .claude/worktrees/"
# reimplemented locally) is exactly the drift class that would silently
# diverge from the guard's own logic and false-RED every orchestrated day
# (spawned/builder sessions never register asks BY DESIGN — they attach to
# the dispatching ask instead — so counting them as a capture gap is a bug,
# not a finding). This check sources the SAME lib file and calls the SAME
# function; it never reimplements the classification.
#
# Population source: every heartbeat file (${live_home}/state/heartbeats/
# *.json — the O.2 liveness files, one per top-level session; subagent/
# workflow transcripts never write their own heartbeat, so no extra
# filtering is needed here the way check_obs_heartbeats_fresh needs it for
# TRANSCRIPTS) whose mtime falls within the trailing 24h. For each such
# session classified OPERATOR (not SPAWNED) by pl_classify_session, this
# check derives the ask_id the Task 9 capture splice would have minted
# (`pl_ask_id_for_session <session_id>` — the SAME deterministic derivation
# hooks/workstreams-read.sh's splice uses at registration time, per its own
# header) and confirms a record for that ask_id exists in
# ${live_home}/state/ask-registry.jsonl. A session whose cwd/heartbeat
# fields cannot be read is SKIPPED, never guessed into the population (a
# false RED here is a false alarm; a false skip merely narrows the audited
# set for one cycle).
#
# Gates (each a silent GREEN skip):
#   1. progress-log-lib.sh absent (mechanism not installed) -> nothing to
#      audit (mirrors check_obs_heartbeats_fresh's own canonical-oracle
#      sourcing convention: source once, guarded by the lib's own
#      re-source guard).
#   2. pl_classify_session/pl_ask_id_for_session not resolvable after
#      sourcing (should not happen on an installed estate; degrade
#      honestly rather than guess).
#   3. no heartbeats directory -> zero live sessions, nothing to check.
#   4. zero OPERATOR-classified sessions in the trailing-24h population
#      (e.g. every session in the window was spawned/builder/sub-agent —
#      the exact "orchestrated day" case population parity exists to
#      protect) -> GREEN, nothing to check. This is NOT the same as "zero
#      heartbeats" — it is reached only AFTER classification.
# ------------------------------------------------------------
check_obs_ask_capture_completeness() {
  local live_home="$1" repo_root="$2"

  local pllib="${SCRIPT_DIR}/lib/progress-log-lib.sh"
  if [[ ! -f "$pllib" ]]; then
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi
  # shellcheck disable=SC1090
  source "$pllib"
  if ! command -v pl_classify_session >/dev/null 2>&1 \
     || ! command -v pl_ask_id_for_session >/dev/null 2>&1; then
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi

  local hb_dir="${live_home}/state/heartbeats"
  if [[ ! -d "$hb_dir" ]]; then
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi

  local dp_dir="${live_home}/state/dispatch-provenance"
  local registry_file="${live_home}/state/ask-registry.jsonl"

  local now_epoch
  now_epoch=$(date -u +%s 2>/dev/null || echo 0)

  local -a checked_sids=()
  local -a missing_sids=()
  local f mtime age_min sid cwd

  while IFS= read -r -d '' f; do
    mtime=$(stat -c %Y "$f" 2>/dev/null || stat -f %m "$f" 2>/dev/null || echo 0)
    age_min=$(( (now_epoch - mtime) / 60 ))
    [[ "$age_min" -lt 1440 ]] || continue  # trailing-24h population window

    sid="$(_pl_marker_field "$f" session_id)"
    [[ -n "$sid" ]] || continue

    cwd="$(_pl_marker_field "$f" cwd)"
    # An unresolvable cwd cannot be safely classified — skip rather than
    # guess (see header: a false skip is cheap, a false RED is not).
    [[ -n "$cwd" ]] || continue

    if pl_classify_session --cwd "$cwd" --dispatch-provenance-dir "$dp_dir" >/dev/null 2>&1; then
      continue  # SPAWNED — excluded from the population BY CONSTRUCTION,
                # not re-derived: population parity with Task 9's guard.
    fi

    checked_sids+=("$sid")
    local expected_ask
    expected_ask="$(pl_ask_id_for_session "$sid")"
    [[ -n "$expected_ask" ]] || continue

    if [[ ! -f "$registry_file" ]] || ! grep -qF "\"ask_id\":\"${expected_ask}\"" "$registry_file"; then
      missing_sids+=("$sid")
    fi
  done < <(find "$hb_dir" -maxdepth 1 -type f -name '*.json' -print0 2>/dev/null)

  if [[ "${#checked_sids[@]}" -eq 0 ]]; then
    # Nothing operator-origin in the trailing-24h window — GREEN. This is
    # the population-parity guarantee made visible: an estate with only
    # orchestrated/worktree activity in the window stays silent, exactly
    # because those sessions were correctly excluded above, not because
    # there was nothing to look at.
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi

  if [[ "${#missing_sids[@]}" -gt 0 ]]; then
    _red "obs-ask-capture-completeness" "${#missing_sids[@]} of ${#checked_sids[@]} trailing-24h OPERATOR-origin session(s) have NO registered ask in ${registry_file} (Task 9's automatic-capture invariant) — session(s): $(printf '%s, ' "${missing_sids[@]}" | sed 's/, $//'). Check whether hooks/workstreams-read.sh's ask-capture splice fired for these sessions (see ~/.claude/logs/progress-log-emit.log if present, or re-check the session's own first-prompt marker under ~/.claude/state/ask-capture/)"
  fi

  CHECKS_RUN=$((CHECKS_RUN + 1))
}

# ------------------------------------------------------------
# Check: needs-you-headers (specs-o §O.6 item 6, E6-HEADER-HARDENING-01).
# When the needs-you ledger's open decision-count is >0, NEEDS-YOU.md
# must contain all 4 NY_CANONICAL_HEADERS. Gated on ny_open>0, same
# posture as the existing E.6 staleness check in check_wave_e_surfaces.
# ------------------------------------------------------------
check_needs_you_headers() {
  local live_home="$1" repo_root="$2"

  local ny_nlpaths="${repo_root}/adapters/claude-code/hooks/lib/nl-paths.sh"
  local ny_main_root=""
  [[ -f "$ny_nlpaths" ]] && ny_main_root=$(bash -c "source '$ny_nlpaths'; nl_main_checkout_root" 2>/dev/null)
  [[ -n "$ny_main_root" ]] || ny_main_root="$repo_root"
  local ny_md="${ny_main_root}/NEEDS-YOU.md"
  local ny_state="${live_home}/state/needs-you/ledger.json"

  if [[ ! -f "$ny_state" ]]; then
    _warn "needs-you-headers" "needs-you ledger not found at ${ny_state} — E.6 not yet installed on this machine"
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi
  if ! command -v jq >/dev/null 2>&1; then
    _warn "needs-you-headers" "jq not available — cannot check needs-you open-count"
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi

  local ny_open
  ny_open=$(jq '[.items[] | select(.section == "decision" and .state == "open")] | length' "$ny_state" 2>/dev/null || echo 0)
  [[ "${ny_open:-0}" -gt 0 ]] || { CHECKS_RUN=$((CHECKS_RUN + 1)); return 0; }

  if [[ ! -f "$ny_md" ]]; then
    _red "needs-you-headers" "NEEDS-YOU.md missing at ${ny_md} despite ${ny_open} open decision item(s) — run: bash adapters/claude-code/scripts/needs-you.sh render"
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi

  local -a headers=(
    "## Awaiting your decision"
    "## Open questions"
    "## In flight (sessions + waves)"
    "## Recently decided for your §8 review"
  )
  local -a missing=()
  local h
  for h in "${headers[@]}"; do
    grep -qF "$h" "$ny_md" 2>/dev/null || missing+=("$h")
  done
  if [[ "${#missing[@]}" -gt 0 ]]; then
    _red "needs-you-headers" "NEEDS-YOU.md (${ny_md}) missing $(printf '%s' "${#missing[@]}") of 4 canonical header(s) despite ${ny_open} open decision item(s): $(IFS='|'; echo "${missing[*]}") — run: bash adapters/claude-code/scripts/needs-you.sh render"
  fi
  CHECKS_RUN=$((CHECKS_RUN + 1))
}

# ------------------------------------------------------------
# Check: pin-f-waiver-purpose-clauses (ADR 058 D5 pin f, specs-e §E.10
# item 2). Every waiver-accepting hook must validate the two named
# clauses ("this gate exists to prevent X" / "that does not apply here
# because Y") via the shared _wig_check_waiver-style helper (or an
# equivalent per-hook implementation). This doctor check is a GREP
# assertion, not a runtime probe: it verifies each hook enumerated by
# `rg -l "waiver" hooks/*.sh` actually references a purpose-clause
# validation routine, so a future waiver-accepting hook added WITHOUT
# purpose-clause validation is caught structurally.
# ------------------------------------------------------------
check_pin_f_waiver_purpose_clauses() {
  local repo_root="$2"
  [[ -z "$repo_root" ]] && { _warn "pin-f-waiver-purpose-clauses" "repo root unresolved — skipped"; CHECKS_RUN=$((CHECKS_RUN + 1)); return 0; }
  local hooks_dir="${repo_root}/adapters/claude-code/hooks"
  [[ -d "$hooks_dir" ]] || { _warn "pin-f-waiver-purpose-clauses" "no repo hooks/ directory at ${hooks_dir} — skipped"; CHECKS_RUN=$((CHECKS_RUN + 1)); return 0; }

  local f
  for f in "$hooks_dir"/*.sh; do
    [[ -f "$f" ]] || continue
    # Narrow signal (not a bare "waiver" mention — that false-positives on
    # comments about REMOVED waiver paths, self-tests asserting a waiver
    # string is ABSENT, and unrelated "waiver-density" telemetry, none of
    # which are waiver-reading hooks): a hook that actually READS a waiver
    # file as an escape hatch names a `*-waiver-*`/`*-attested-*`/
    # `*-approved-*` filename pattern somewhere (a `find -name` probe, a
    # `WAIVER_GLOB=` variable, a `compgen -G` check, or a native bash glob
    # loop `for f in dir/prefix-*.txt`) — the union of shapes every real
    # waiver reader in this repo uses (work-integrity-gate.sh,
    # workstreams-state-gate.sh, workstreams-stop-gate.sh,
    # teammate-spawn-validator.sh, workstreams-task-binding.sh,
    # bug-persistence-gate.sh).
    grep -qE '(waiver-|attested-|approved-)[A-Za-z0-9._$*{}-]*\.txt' "$f" 2>/dev/null || continue
    # A file that reads a waiver family purely as a downstream SIGNAL (not
    # as its own escape hatch — the family is validated where it is
    # written/honored by a DIFFERENT gate) can declare that explicitly with
    # a `pin-f-doctor-exempt:` marker comment naming why, rather than
    # re-implementing/re-referencing a validator it doesn't own.
    grep -qE 'pin-f-doctor-exempt' "$f" 2>/dev/null && continue
    # Every waiver-reading hook must reference the shared purpose-clause
    # validator (_wig_check_waiver, waiver_has_purpose_clauses per pin-f)
    # OR its own inline purpose-clause validation marker.
    if ! grep -qE '_wig_check_waiver|waiver_has_purpose_clauses|_check_waiver_purpose_clauses|purpose[-_ ]clause' "$f" 2>/dev/null; then
      _warn "pin-f-waiver-purpose-clauses" "$(basename "$f") reads a waiver-family file but does not reference a purpose-clause validator (_wig_check_waiver / waiver_has_purpose_clauses / a 'purpose-clause' marker / a 'pin-f-doctor-exempt' comment) — pin (f) requires validating 'this gate exists to prevent X' + 'that does not apply here because Y'"
    fi
  done
  CHECKS_RUN=$((CHECKS_RUN + 1))
}

# ------------------------------------------------------------
# Check: limit-resume-watchdog (2026-07-30, manifest entry "limit-resume")
#
# Makes a NON-FIRING or STUCK watchdog VISIBLE instead of silent (the
# operator's own build requirement: "a doctor check or an honest_status
# line that makes a NON-FIRING watchdog visible instead of silent").
# Reads ${live_home}/state/limit-resume/armed/*.json — ONE file per
# TRACKED SESSION (per-session keying, harness-reviewer REJECT finding
# F3 fix: a single machine-global marker let two concurrent sessions in
# different repos clobber each other's tracked state) — HARNESS_DOCTOR_
# HOME/NL_REPO_ROOT-overridable, exactly like check_obs_cockpit_fresh's
# heartbeat-dir read, so this check is fixture-testable the same way.
#
# Per tracked session, two WARN conditions (both WARN, not RED — they
# report a real-world operational fact, not a structural harness defect
# the doctor can prove; matches check_obs_cockpit_fresh's own
# WARN-not-RED precedent for "expected-but-not-currently-up"):
#
#   1. <key>.giveup present -> the watchdog tried MAX_RETRIES times and
#      gave up; that session likely never got resumed. The single most
#      important thing this check exists to surface — a silent giveup is
#      exactly "non-firing but nobody notices."
#   2. no .attempts file yet AND armed_at is older than
#      LIMIT_RESUME_STALE_ARMED_MINUTES (default 70 -- comfortably past
#      limit-resume.sh's own MIN_SILENCE_SECONDS floor, default 1800s/
#      30min, plus roughly two 15-minute tick intervals of margin, so a
#      HEALTHY watchdog respecting its own floor never false-positives
#      here) -> the LaunchAgent is very likely not ticking at all (not
#      loaded, a PATH-resolution defect recurring, etc.), since a healthy
#      watchdog would have made its first attempt by now. This is the
#      DEFECT-1-CLASS regression detector: the exact "every tick fails
#      silently" shape that motivated this whole build.
# ------------------------------------------------------------
check_limit_resume_watchdog() {
  local live_home="$1"
  local armed_dir="${live_home}/state/limit-resume/armed"
  [[ -d "$armed_dir" ]] || { CHECKS_RUN=$((CHECKS_RUN + 1)); return 0; }

  local f
  for f in "$armed_dir"/*.json; do
    [[ -e "$f" ]] || continue
    local key="${f##*/}"; key="${key%.json}"
    local giveup_f="${armed_dir}/${key}.giveup"
    local attempts_f="${armed_dir}/${key}.attempts"
    local sid; sid="$(sed -nE 's/.*"session_id"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/p' "$f" 2>/dev/null | head -1)"

    if [[ -f "$giveup_f" ]]; then
      local detail; detail="$(cat "$giveup_f" 2>/dev/null | tr -d '\n')"
      _warn "limit-resume-giveup" "the limit-resume watchdog gave up on session '${sid:-unknown}' (${detail}) — it may still be waiting on a usage-limit reset; disarm (rm ${f}) once you've confirmed it's no longer needed, or investigate why ${LIMIT_RESUME_MAX_RETRIES:-8} attempts all failed (${live_home}/state/limit-resume/log.txt)"
    elif [[ ! -f "$attempts_f" ]]; then
      local armed_at now_epoch armed_epoch age_min stale_min
      armed_at="$(sed -nE 's/.*"armed_at"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/p' "$f" 2>/dev/null | head -1)"
      stale_min="${LIMIT_RESUME_STALE_ARMED_MINUTES:-70}"
      if [[ -n "$armed_at" ]]; then
        now_epoch=$(date -u +%s 2>/dev/null || echo 0)
        armed_epoch=$(date -u -d "$armed_at" +%s 2>/dev/null || date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$armed_at" +%s 2>/dev/null || echo 0)
        if [[ "$armed_epoch" -gt 0 ]]; then
          age_min=$(( (now_epoch - armed_epoch) / 60 ))
          if [[ "$age_min" -ge "$stale_min" ]]; then
            _warn "limit-resume-stale-armed" "watchdog marker for session '${sid:-unknown}' has been armed for ${age_min}m with zero recorded attempts (>= ${stale_min}m threshold -- comfortably past the watchdog's own 30min initial-silence floor) — the LaunchAgent may not be ticking at all (check: launchctl list | grep local.neurallace.limit-resume), OR (round-5 review finding, instance-only) a SIGKILLed tick left a wedged attempt.lock whose recorded owner pid was later reused by an unrelated process (check: cat ~/.claude/state/limit-resume/attempt.lock/owner, then whether that pid is this watchdog); this is the exact 'every tick fails silently' shape (DEFECT 1) this build exists to catch"
          fi
        fi
      fi
    fi
  done
  CHECKS_RUN=$((CHECKS_RUN + 1))
}

# ------------------------------------------------------------
# Check: budget-chains (Wave F, task F.1, specs-f §F.1 item 1)
# Stop <= 6, SessionStart <= 8 chain entries, checked against BOTH the
# committed template and the live settings.json. A single check id
# ("budget-chains") consolidates what earlier waves only discussed in
# comments (session-start-surfacer-pack.sh's header note) — there was no
# prior mechanical enforcement to "consolidate" other than that comment,
# so this is the first real implementation under the budget-chains id.
# Counts TOTAL hook entries across every matcher block for the event
# (not matcher-block count), matching how Claude Code actually executes
# the chain (every hooks[] entry in every matching block runs).
# ------------------------------------------------------------
_count_chain_entries() {
  # $1 = settings.json path, $2 = event name (Stop|SessionStart) -> prints total hook count (or empty on parse failure)
  local settings="$1" event="$2"
  [[ -f "$settings" ]] || { printf ''; return 0; }
  if command -v node >/dev/null 2>&1; then
    cat "$settings" 2>/dev/null | node -e "
      const fs = require('fs');
      let cfg;
      try { cfg = JSON.parse(fs.readFileSync(0, 'utf8')); } catch (e) { process.exit(0); }
      const arr = (cfg.hooks && cfg.hooks['$event']) || [];
      let total = 0;
      for (const block of arr) total += (block.hooks || []).length;
      console.log(total);
    " 2>/dev/null
  elif command -v jq >/dev/null 2>&1; then
    jq -r --arg ev "$event" '[(.hooks[$ev] // [])[] | (.hooks // []) | length] | add // 0' "$settings" 2>/dev/null
  else
    printf ''
  fi
}

check_budget_chains() {
  local live_home="$1" repo_root="$2"
  local live_settings="${live_home}/settings.json"
  local template_settings="${repo_root}/adapters/claude-code/settings.json.template"

  if ! command -v node >/dev/null 2>&1 && ! command -v jq >/dev/null 2>&1; then
    _warn "budget-chains" "neither node nor jq available — chain-length budgets skipped"
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi

  local src path event count max
  for src in live template; do
    if [[ "$src" == "live" ]]; then path="$live_settings"; else path="$template_settings"; fi
    if [[ ! -f "$path" ]]; then
      _warn "budget-chains" "${src} settings.json not found at ${path} — skipped for ${src}"
      continue
    fi
    for event in Stop SessionStart; do
      if [[ "$event" == "Stop" ]]; then max=6; else max=8; fi
      count="$(_count_chain_entries "$path" "$event")"
      if [[ -z "$count" ]]; then
        _warn "budget-chains" "could not parse ${event} chain length from ${src} settings (${path})"
        continue
      fi
      if [[ "$count" -gt "$max" ]]; then
        _red "budget-chains" "${event} chain has ${count} hook entries in ${src} settings (budget <= ${max}) — ${path}"
      fi
    done
  done
  CHECKS_RUN=$((CHECKS_RUN + 1))
}

# ------------------------------------------------------------
# Check: budget-blocking-gates (Wave F, task F.1, specs-f §F.1 item 2)
#
# Blocking gates <= 12. COUNTING RULE (Wave-F integration fix, 2026-07-06):
# this budget was FROZEN at Wave D as specs-d §D.0.4's "blocking session-event
# UNITS" definition — manifest entries with blocking:true AND wired_template:
# true AND wired to a live-session event (Stop/PreToolUse/SessionStart/
# PostToolUse/UserPromptSubmit/TaskCreated/TaskCompleted), with same-class
# entries CONSOLIDATED into one unit (e.g. env-local-protection +
# deploy-automation-mode = one "command-safety" unit; the 5 commit-time-only
# gates = one "commit-boundary" unit). git-boundary hooks (precommit/prepush)
# are an explicitly SEPARATE budget class, not counted here. D.5's evidence
# block ("blocking budget 12/12 GREEN") was produced by exactly this counting
# method via scripts/blocking-budget-check.js — that script is kept as the
# SOLE implementation (avoid a second, drifting reimplementation here); this
# check shells out to it.
#
# An earlier version of this check counted every manifest entry with bare
# blocking:true (no wired_template/live-event filter, no consolidation),
# which conflates the D.0.4 budget with a raw entry count and inflates the
# reported number well past 12 for reasons the budget was never meant to
# flag (git-boundary-only gates, GAP entries not yet wired live, and
# same-class hooks the frozen rule explicitly treats as one unit). Fixed
# during Wave-F integration (F.1+F.5+F.2 merge) rather than relaxing the
# budget number itself — the true post-Wave-D-and-E number, by the correct
# definition, is 10/12 (GREEN, 2 units of headroom).
# ------------------------------------------------------------
check_budget_blocking_gates() {
  local live_home="$1" repo_root="$2"
  local manifest
  if ! manifest="$(resolve_manifest "$live_home" "$repo_root")"; then
    _warn "budget-blocking-gates" "no manifest.json found (live mirror or repo) — skipped (pre-C.1 machine)"
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi
  if ! command -v node >/dev/null 2>&1; then
    _warn "budget-blocking-gates" "node not available — blocking-budget-check.js requires node — skipped"
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi

  local checker="${repo_root}/adapters/claude-code/scripts/blocking-budget-check.js"
  [[ -f "$checker" ]] || checker="${live_home}/scripts/blocking-budget-check.js"
  if [[ ! -f "$checker" ]]; then
    _warn "budget-blocking-gates" "manifest.json present but blocking-budget-check.js not found (repo scripts/ or live scripts/) — cannot validate"
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi

  local out rc
  out="$(node "$checker" "$manifest" 2>&1)"
  rc=$?
  if [[ "$rc" -ne 0 ]]; then
    local units_line
    units_line="$(printf '%s\n' "$out" | grep -m1 'blocking session-event units:' || true)"
    _red "budget-blocking-gates" "${units_line:-blocking-budget-check.js reported over-budget} (budget <= 14 consolidated units per specs-d §D.0.4, raised 13->14 agent-efficiency batch 2026-07-23) — ${manifest}; remediation: demote via scripts/gate-demotion.sh (F.5) or consolidate per ADR 059 D7"
  fi
  CHECKS_RUN=$((CHECKS_RUN + 1))
}

# ------------------------------------------------------------
# Check: budget-always-loaded (Wave F, task F.1, specs-f §F.1 item 3)
# Always-loaded <= 30KB: byte-sum of ~/.claude/rules/*.md + CLAUDE.md.
# This is a DEDICATED, always-strict 30KB rule (independent of the
# existing configurable check_byte_budget/~/.claude/local/doctor-budget
# mechanism, which stays as the machine-tunable soft-by-default check) —
# specs-f §F.1 item 3 names an exact, non-configurable threshold.
# ------------------------------------------------------------
check_budget_always_loaded() {
  local live_home="$1"
  local rules_dir="${live_home}/rules"
  local claude_md="${live_home}/CLAUDE.md"
  local max=30000

  if [[ ! -d "$rules_dir" && ! -f "$claude_md" ]]; then
    _warn "budget-always-loaded" "neither ${rules_dir} nor ${claude_md} exist — nothing to check"
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi

  local total
  total="$( { cat "$rules_dir"/*.md 2>/dev/null; cat "$claude_md" 2>/dev/null; } | wc -c | tr -d '[:space:]')"
  total="${total:-0}"

  if [[ "$total" -gt "$max" ]]; then
    _red "budget-always-loaded" "${total} bytes across ~/.claude/rules/*.md + CLAUDE.md exceeds the always-loaded budget of ${max} bytes — move content to doctrine/ (JIT-delivered) per constitution §10"
  fi
  CHECKS_RUN=$((CHECKS_RUN + 1))
}

# ------------------------------------------------------------
# Check: budget-active-plans (Wave F, task F.1, specs-f §F.1 item 4)
# ACTIVE plans <= 3 machine-wide: `grep -l "^Status: ACTIVE" docs/plans/*.md
# | wc -l` across every repo listed in ~/.claude/local/nl-repo-path +
# registered project roots.
#
# EXACT ROOT LIST THIS CHECK WALKS (documented per spec's explicit
# requirement):
#   1. The repo_root passed in (this invocation's own resolved repo).
#   2. The single line in <live_home>/local/nl-repo-path, if that file
#      exists and names a readable directory (this machine's canonical
#      NL checkout — see hooks/lib/nl-paths.sh's identical resolution;
#      live_home is $HOME/.claude, overridable to a sandbox root via
#      HARNESS_DOCTOR_HOME exactly like every other live-mirror read in
#      this file — self-test fixtures must never leak the REAL machine's
#      nl-repo-path into a fixture's verdict).
#   3. Every line in <live_home>/local/nl-project-roots (one absolute path
#      per line, '#'-comments and blanks skipped) IF that file exists —
#      this is the "registered project roots" extension point named by
#      the spec; no such file exists on this machine today (single-repo
#      machine), so this tier is a no-op here but is honestly documented
#      and wired for a future multi-repo machine.
# Duplicate roots (e.g. repo_root == nl-repo-path on a single-repo
# machine) are counted once. Fail-open per spec: an unreadable/missing
# root contributes 0 to the count (WARN, not RED) rather than aborting
# the whole check.
# ------------------------------------------------------------
_budget_active_plans_roots() {
  # Emits the de-duplicated list of candidate roots, one per line.
  local repo_root="$1" live_home="$2"
  local -a roots=()
  [[ -n "$repo_root" ]] && roots+=("$repo_root")

  local cfg="${live_home}/local/nl-repo-path"
  if [[ -f "$cfg" ]]; then
    local line
    line="$(head -1 "$cfg" 2>/dev/null | tr -d '\r')"
    [[ -n "$line" ]] && roots+=("$line")
  fi

  local extra="${live_home}/local/nl-project-roots"
  if [[ -f "$extra" ]]; then
    local rline
    while IFS= read -r rline; do
      rline="${rline%$'\r'}"
      [[ -z "$rline" ]] && continue
      [[ "$rline" == \#* ]] && continue
      roots+=("$rline")
    done < "$extra"
  fi

  # De-dup by GIT IDENTITY, not raw path string. When the doctor runs from a
  # linked worktree, resolve_repo_root()'s own root (this worktree's
  # toplevel) and <live_home>/local/nl-repo-path (the main checkout) are two
  # DIFFERENT absolute paths that are nonetheless the SAME repository —
  # `git worktree` gives every linked worktree its own toplevel but they all
  # share one `git rev-parse --git-common-dir` (the shared .git). A raw
  # `sort -u` on path strings does not catch this and double-counts every
  # plan in docs/plans/ once per worktree that resolves to the same repo
  # (verifier live-probe: "6 across 2 roots" vs true 3, both roots worktrees
  # of one repo). Fix: key de-dup on each root's resolved git-common-dir
  # (falling back to the raw path itself for non-git roots, e.g. the live
  # mirror tier or a future non-repo project-roots entry) so two worktrees
  # of one repo collapse to a single counted root. Linear scan (not
  # associative arrays — this file targets bash 3.2 for macOS parity) over
  # a handful of roots; first-seen root per key wins, preserving the
  # documented priority order (repo_root, then nl-repo-path, then
  # nl-project-roots).
  local -a seen_keys=() out=()
  local r key already
  for r in "${roots[@]}"; do
    [[ -z "$r" ]] && continue
    key=""
    if [[ -d "$r" ]] && command -v git >/dev/null 2>&1; then
      key="$(git -C "$r" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"
      # Older git (pre-2.31) lacks --path-format; fall back to the raw
      # (possibly relative) --git-common-dir and normalize it against $r.
      if [[ -z "$key" ]]; then
        local raw_gcd
        raw_gcd="$(git -C "$r" rev-parse --git-common-dir 2>/dev/null)"
        if [[ -n "$raw_gcd" ]]; then
          case "$raw_gcd" in
            /*) key="$raw_gcd" ;;
            *) key="${r}/${raw_gcd}" ;;
          esac
        fi
      fi
    fi
    [[ -z "$key" ]] && key="$r"

    already=0
    local sk
    for sk in "${seen_keys[@]+"${seen_keys[@]}"}"; do
      [[ "$sk" == "$key" ]] && { already=1; break; }
    done
    if [[ "$already" -eq 0 ]]; then
      seen_keys+=("$key")
      out+=("$r")
    fi
  done

  [[ "${#out[@]}" -eq 0 ]] && return 0
  printf '%s\n' "${out[@]}"
}

check_budget_active_plans() {
  local live_home="$1" repo_root="$2"
  local max=3
  local roots
  roots="$(_budget_active_plans_roots "$repo_root" "$live_home")"
  if [[ -z "$roots" ]]; then
    _warn "budget-active-plans" "no roots resolved (repo_root unset, no <live_home>/local/nl-repo-path) — skipped"
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi

  local total=0 root plans_dir n unreadable=()
  while IFS= read -r root; do
    [[ -z "$root" ]] && continue
    plans_dir="${root}/docs/plans"
    if [[ ! -d "$plans_dir" || ! -r "$plans_dir" ]]; then
      unreadable+=("$root")
      continue
    fi
    n=0
    local f
    for f in "$plans_dir"/*.md; do
      [[ -f "$f" ]] || continue
      head -n 30 "$f" 2>/dev/null | grep -qE '^Status:[[:space:]]*ACTIVE' && n=$((n + 1))
    done
    total=$((total + n))
  done <<< "$roots"

  if [[ "${#unreadable[@]}" -gt 0 ]]; then
    _warn "budget-active-plans" "$(IFS=,; echo "${unreadable[*]}") had no readable docs/plans/ — counted as 0 (fail-open)"
  fi

  if [[ "$total" -gt "$max" ]]; then
    _red "budget-active-plans" "${total} plans with Status: ACTIVE across $(printf '%s' "$roots" | grep -c .) root(s) (budget <= ${max}) — defer/complete/abandon via the F.3-style disposition process"
  fi
  CHECKS_RUN=$((CHECKS_RUN + 1))
}

# ------------------------------------------------------------
# Check: budget-worktrees-branches (Wave F, task F.1, specs-f §F.1 item 5)
# Worktree count <= 6 and none older than 7 days without a commit; local
# branches with no upstream and no commit in 7 days flagged.
# ------------------------------------------------------------
check_budget_worktrees_branches() {
  local repo_root="$2"
  [[ -z "$repo_root" ]] && { _warn "budget-worktrees-branches" "repo root unresolved — skipped"; CHECKS_RUN=$((CHECKS_RUN + 1)); return 0; }
  command -v git >/dev/null 2>&1 || { _warn "budget-worktrees-branches" "git not available — skipped"; CHECKS_RUN=$((CHECKS_RUN + 1)); return 0; }

  local max_worktrees=6
  local stale_secs=$((7 * 86400))
  local now; now=$(date +%s)

  # --- worktree count + age ---
  local wt_list
  wt_list="$(git -C "$repo_root" worktree list --porcelain 2>/dev/null)"
  if [[ -z "$wt_list" ]]; then
    _warn "budget-worktrees-branches" "git worktree list produced no output — skipped worktree sub-check"
  else
    local wt_count
    wt_count="$(printf '%s\n' "$wt_list" | grep -c '^worktree ')"
    if [[ "$wt_count" -gt "$max_worktrees" ]]; then
      _red "budget-worktrees-branches" "${wt_count} git worktrees registered (budget <= ${max_worktrees}) — prune with: git worktree prune; git worktree remove <stale-path>"
    fi

    # Per-worktree staleness: no commit in 7 days on that worktree's HEAD.
    local wt_path=""
    while IFS= read -r line; do
      case "$line" in
        "worktree "*) wt_path="${line#worktree }" ;;
        "HEAD "*)
          local sha ts age
          sha="${line#HEAD }"
          [[ -z "$wt_path" ]] && continue
          [[ "$wt_path" == "$repo_root" ]] && continue  # main checkout is not a "worktree" for this budget
          ts="$(git -C "$repo_root" log -1 --format=%ct "$sha" 2>/dev/null)"
          [[ -z "$ts" ]] && continue
          age=$((now - ts))
          if [[ "$age" -ge "$stale_secs" ]]; then
            _red "budget-worktrees-branches" "worktree ${wt_path} has no commit in $((age / 86400))d (budget: 7d) — remove with: git worktree remove '${wt_path}'"
          fi
          ;;
      esac
    done <<< "$wt_list"
  fi

  # --- local branch staleness: no upstream + no commit in 7 days ---
  local br_list
  br_list="$(git -C "$repo_root" for-each-ref --format='%(refname:short)|%(upstream:short)|%(committerdate:unix)' refs/heads/ 2>/dev/null)"
  if [[ -n "$br_list" ]]; then
    local name upstream ts age
    while IFS='|' read -r name upstream ts; do
      [[ -z "$name" ]] && continue
      [[ -n "$upstream" ]] && continue
      [[ -z "$ts" ]] && continue
      age=$((now - ts))
      if [[ "$age" -ge "$stale_secs" ]]; then
        _red "budget-worktrees-branches" "branch '${name}' has no upstream and no commit in $((age / 86400))d (budget: 7d) — push it (git push -u origin ${name}) or delete it (git branch -D ${name})"
      fi
    done <<< "$br_list"
  fi
  CHECKS_RUN=$((CHECKS_RUN + 1))
}

# ------------------------------------------------------------
# resolve_schedule_manifest <live_home> <repo_root>
# Echoes the schedule-manifest.json path (live-first, repo fallback,
# mirrors resolve_manifest's own order) or nothing.
# ------------------------------------------------------------
resolve_schedule_manifest() {
  local live_home="$1" repo_root="$2"
  if [[ -f "${live_home}/config/schedule-manifest.json" ]]; then
    printf '%s\n' "${live_home}/config/schedule-manifest.json"
    return 0
  fi
  if [[ -n "$repo_root" && -f "${repo_root}/adapters/claude-code/config/schedule-manifest.json" ]]; then
    printf '%s\n' "${repo_root}/adapters/claude-code/config/schedule-manifest.json"
    return 0
  fi
  return 1
}

# ------------------------------------------------------------
# Check: schedule-manifest-cadence (harness-execution-redesign-2026-08
# Task 1, invariant 2: "Cadence >= 2x measured cycle time for every
# scheduled task, from a central schedule manifest; doctor-enforced.")
#
# WARN-only at this stage (task 1 spec: "WARN for 1 calibration week, then
# RED" -- the RED flip is explicitly a LATER task, not this one). For every
# mechanisms[] entry that carries a non-null measured_cycle_seconds, RED-
# grade the SEVERITY down to WARN and flag when
# declared_cadence_seconds < ratio_floor * measured_cycle_seconds. Entries
# with measured_cycle_seconds == null are calibration-pending and are
# silently skipped (their absence of a measurement is not itself flagged --
# adding a measurement is exactly the calibration week's job).
# ------------------------------------------------------------
check_schedule_manifest_cadence() {
  local live_home="$1" repo_root="$2"
  local manifest
  if ! manifest="$(resolve_schedule_manifest "$live_home" "$repo_root")"; then
    _warn "schedule-manifest-cadence" "no adapters/claude-code/config/schedule-manifest.json found (live mirror or repo) -- skipped (pre-Task-1 machine)"
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi
  if ! command -v node >/dev/null 2>&1 && ! command -v jq >/dev/null 2>&1; then
    _warn "schedule-manifest-cadence" "neither node nor jq available -- cadence check skipped"
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi

  # HR-F7 (2026-08-03 harness review, gated-pipeline T7/REQ-A5): the WARN
  # -> RED flip lives in DATA (cadence_check.red_after in schedule-
  # manifest.json), never prose-only -- "WARN for 1 calibration week, then
  # RED" with no stored date is constitution paragraph-1's exact
  # prohibited shape. An absent/unparseable red_after means stay-WARN-
  # forever (never a fabricated RED from a missing field).
  local red_after="" now_epoch red_epoch is_red=0
  if command -v jq >/dev/null 2>&1; then
    red_after="$(jq -r '.cadence_check.red_after // empty' "$manifest" 2>/dev/null | tr -d '\r')"
  elif command -v node >/dev/null 2>&1; then
    red_after="$(node -e 'try{const m=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));process.stdout.write((m.cadence_check&&m.cadence_check.red_after)||"")}catch(e){}' "$manifest" 2>/dev/null)"
  fi
  if [[ -n "$red_after" ]]; then
    now_epoch="$(date +%s 2>/dev/null || echo 0)"
    red_epoch="$(date -d "$red_after" +%s 2>/dev/null || echo 0)"
    [[ "$red_epoch" -gt 0 && "$now_epoch" -ge "$red_epoch" ]] && is_red=1
  fi

  # HR-F7's own PROVEN false positive: a managed_by=nl-maintenance entry's
  # prescribed remedy (completion-anchored scheduling, per this file's own
  # schema note) is satisfied THE MOMENT nl-maintenance is active -- the
  # old check never read managed_by, so the remedy never cleared the WARN.
  # Exempt those entries from the clock entirely once the activation
  # marker exists (same marker check_maintenance_both_substrates_alive
  # uses) -- annotated (_note), never warned or redded.
  local activation="${live_home}/state/nl-maintenance/activation-marker"
  local activated=0
  [[ -f "$activation" ]] && activated=1

  local out
  if command -v node >/dev/null 2>&1; then
    out="$(node -e '
const fs = require("fs");
let m;
try { m = JSON.parse(fs.readFileSync(process.argv[1], "utf8")); } catch (e) { process.exit(0); }
const floor = (m.cadence_check && m.cadence_check.ratio_floor) || 2;
for (const e of m.mechanisms || []) {
  if (e == null || e.measured_cycle_seconds == null) continue;
  const declared = e.declared_cadence_seconds;
  const measured = e.measured_cycle_seconds;
  if (typeof declared !== "number" || typeof measured !== "number") continue;
  const required = floor * measured;
  if (declared < required) {
    console.log([e.id, declared, measured, required, e.managed_by || ""].join("|"));
  }
}' "$manifest" 2>/dev/null)"
  else
    out="$(jq -r --argjson floor "$(jq -r '.cadence_check.ratio_floor // 2' "$manifest" 2>/dev/null)" '
      (.mechanisms // [])[]
      | select(.measured_cycle_seconds != null)
      | select(.declared_cadence_seconds < ($floor * .measured_cycle_seconds))
      | [.id, .declared_cadence_seconds, .measured_cycle_seconds, ($floor * .measured_cycle_seconds), (.managed_by // "")] | join("|")
    ' "$manifest" 2>/dev/null)"
  fi

  if [[ -n "$out" ]]; then
    local id declared measured required managed_by
    while IFS='|' read -r id declared measured required managed_by; do
      [[ -z "$id" ]] && continue
      if [[ "$managed_by" == "nl-maintenance" && "$activated" -eq 1 ]]; then
        _note "schedule-manifest-cadence" "'${id}' declared cadence ${declared}s < 2x measured ${measured}s -- satisfied-by-construction: managed_by=nl-maintenance and its activation marker is present, so its completion-anchored scheduling already enforces this by construction (not warned)"
        continue
      fi
      if [[ "$is_red" -eq 1 ]]; then
        _red "schedule-manifest-cadence" "'${id}' declared cadence ${declared}s < 2x its measured cycle ${measured}s (needs >= ${required}s) since ${red_after} -- it can never fully drain between fires (structural overlap); fix: raise declared_cadence_seconds in ${manifest}, OR move it to completion-anchored scheduling (Stage 1)"
      else
        _warn "schedule-manifest-cadence" "'${id}' declared cadence ${declared}s < 2x its measured cycle ${measured}s (needs >= ${required}s) -- it can never fully drain between fires (structural overlap); fix: raise declared_cadence_seconds in ${manifest}, OR move it to completion-anchored scheduling (Stage 1) -- WARN until ${red_after:-an undated flip}, RED after"
      fi
    done <<< "$out"
  fi
  CHECKS_RUN=$((CHECKS_RUN + 1))
}

# ------------------------------------------------------------
# Check: budget-bash-hooks (harness-execution-redesign-2026-08 Task 1,
# R3.3 inventory target: "Hooks per Bash call: 25 -> ~5 per-category
# stubs"). WARN-only at this stage (task 1 spec: "per-Bash hook-count
# budget doctor check (WARN at this stage)" -- Stage 2 is what actually
# shrinks the count; this check only makes the number VISIBLE and
# doctor-tracked, which is the missing aggregate artifact invariant 1
# names). Counts total hook entries across every PreToolUse matcher block
# whose matcher STRING CONTAINS "Bash" (covers both the bare "Bash"
# matcher and the "Bash|PowerShell" combined matcher) -- checked against
# BOTH the live settings.json and the committed template, same two-source
# pattern as check_budget_chains.
# ------------------------------------------------------------
_count_bash_hooks() {
  # $1 = settings.json path -> prints total hook count across every
  # PreToolUse matcher block containing "Bash" (or empty on parse failure)
  local settings="$1"
  [[ -f "$settings" ]] || { printf ''; return 0; }
  if command -v node >/dev/null 2>&1; then
    cat "$settings" 2>/dev/null | node -e "
      const fs = require('fs');
      let cfg;
      try { cfg = JSON.parse(fs.readFileSync(0, 'utf8')); } catch (e) { process.exit(0); }
      const arr = (cfg.hooks && cfg.hooks['PreToolUse']) || [];
      let total = 0;
      for (const block of arr) {
        if (typeof block.matcher === 'string' && block.matcher.includes('Bash')) {
          total += (block.hooks || []).length;
        }
      }
      console.log(total);
    " 2>/dev/null
  elif command -v jq >/dev/null 2>&1; then
    jq -r '[(.hooks.PreToolUse // [])[] | select(.matcher // "" | contains("Bash")) | (.hooks // []) | length] | add // 0' "$settings" 2>/dev/null
  else
    printf ''
  fi
}

check_budget_bash_hooks() {
  local live_home="$1" repo_root="$2"
  local live_settings="${live_home}/settings.json"
  local template_settings="${repo_root}/adapters/claude-code/settings.json.template"
  local max=6

  if ! command -v node >/dev/null 2>&1 && ! command -v jq >/dev/null 2>&1; then
    _warn "budget-bash-hooks" "neither node nor jq available -- per-Bash hook-count budget skipped"
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi

  # HR-F7 (2026-08-03 harness review, gated-pipeline T7/REQ-A5): same
  # data-driven flip as schedule-manifest-cadence -- "Stage 2 is the
  # actual fix" was prose-only with no stored date; budget_check.red_after
  # in schedule-manifest.json is the mechanized flip. Manifest resolution
  # failure (pre-Task-1 machine, or neither node/jq usable for the manifest
  # read) leaves this WARN-forever, the same fail-open-to-WARN posture the
  # cadence check takes on a missing manifest.
  local manifest="" red_after="" is_red=0
  manifest="$(resolve_schedule_manifest "$live_home" "$repo_root" 2>/dev/null)"
  if [[ -n "$manifest" ]] && command -v jq >/dev/null 2>&1; then
    red_after="$(jq -r '.budget_check.red_after // empty' "$manifest" 2>/dev/null | tr -d '\r')"
  elif [[ -n "$manifest" ]] && command -v node >/dev/null 2>&1; then
    red_after="$(node -e 'try{const m=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));process.stdout.write((m.budget_check&&m.budget_check.red_after)||"")}catch(e){}' "$manifest" 2>/dev/null)"
  fi
  if [[ -n "$red_after" ]]; then
    local now_epoch red_epoch
    now_epoch="$(date +%s 2>/dev/null || echo 0)"
    red_epoch="$(date -d "$red_after" +%s 2>/dev/null || echo 0)"
    [[ "$red_epoch" -gt 0 && "$now_epoch" -ge "$red_epoch" ]] && is_red=1
  fi

  local src path count
  for src in live template; do
    if [[ "$src" == "live" ]]; then path="$live_settings"; else path="$template_settings"; fi
    if [[ ! -f "$path" ]]; then
      _warn "budget-bash-hooks" "${src} settings.json not found at ${path} -- skipped for ${src}"
      continue
    fi
    count="$(_count_bash_hooks "$path")"
    if [[ -z "$count" ]]; then
      _warn "budget-bash-hooks" "could not parse per-Bash hook count from ${src} settings (${path})"
      continue
    fi
    if [[ "$count" -gt "$max" ]]; then
      if [[ "$is_red" -eq 1 ]]; then
        _red "budget-bash-hooks" "${count} hook entries fire on every Bash call in ${src} settings (target <= ${max} per R3.3 -- harness-execution-redesign-2026-08) -- ${path}; flipped to RED since ${red_after} per schedule-manifest.json budget_check -- Stage 2 (per-category stubs) is the actual fix"
      else
        _warn "budget-bash-hooks" "${count} hook entries fire on every Bash call in ${src} settings (target <= ${max} per R3.3 -- harness-execution-redesign-2026-08) -- ${path}; WARN until ${red_after:-an undated flip}, Stage 2 (per-category stubs) is the actual fix"
      fi
    fi
  done
  CHECKS_RUN=$((CHECKS_RUN + 1))
}

# ------------------------------------------------------------
# Check: maintenance-both-substrates-alive (harness-execution-redesign-2026-08
# Task 3, invariant 9: "doctor REDs both-substrates-alive > 14 days"). RED
# when nl-maintenance.sh's daemon has been alive (fresh heartbeat observed
# at least once, per its own activation marker) for > 14 days AND any of
# the legacy per-mechanism scheduled tasks (schedule-manifest.json's
# legacy_task_name entries) is STILL Enabled -- the stall-at-stage-2 trap
# the platform pre-mortem names (both substrates running forever). Non-
# Windows / schtasks-absent / nl-maintenance never activated -> WARN-free
# skip (nothing to compare yet), never a fabricated RED.
# ------------------------------------------------------------
check_maintenance_both_substrates_alive() {
  local live_home="$1" repo_root="$2"
  local manifest="${repo_root}/adapters/claude-code/config/schedule-manifest.json"
  local activation="${live_home}/state/nl-maintenance/activation-marker"

  if [[ ! -f "$activation" ]]; then
    # HR-F4 inverse direction (gated-pipeline T6, REQ-A4): the original check
    # covered both-alive only and returned SILENTLY here — which is the
    # estate's actual failure state (legacy Disabled, replacement never
    # registered, NO recurring maintenance at all, doctor GREEN-capable
    # throughout). Zero-substrate detection, data-driven per the HR-F7 rule:
    # the clock and threshold live in schedule-manifest.json .zero_substrate
    # {legacy_disabled_since: YYYY-MM-DD, red_after_days: N}; absent data =
    # absent check (never a prose-only flip).
    if [[ -f "$manifest" ]] && command -v jq >/dev/null 2>&1; then
      local zs_since zs_days zs_managed
      zs_since="$(jq -r '.zero_substrate.legacy_disabled_since // empty' "$manifest" 2>/dev/null | tr -d '\r')"
      zs_days="$(jq -r '.zero_substrate.red_after_days // empty' "$manifest" 2>/dev/null | tr -d '\r')"
      zs_managed="$(jq -r '[.mechanisms[] | select(.managed_by == "nl-maintenance")] | length' "$manifest" 2>/dev/null | tr -d '\r')"
      if [[ -n "$zs_since" && "$zs_days" =~ ^[0-9]+$ && "$zs_managed" =~ ^[0-9]+$ && "$zs_managed" -gt 0 ]]; then
        # A fresh daemon heartbeat (<2h) counts as a live substrate even
        # pre-marker (tick-mode trials); only marker-absent AND heartbeat-
        # stale AND no legacy task Enabled is truly zero-substrate.
        local zs_hb="${live_home}/state/nl-maintenance/daemon.heartbeat.json"
        local zs_hb_fresh=0 zs_now zs_hb_m
        zs_now="$(date +%s 2>/dev/null || echo 0)"
        if [[ -f "$zs_hb" ]]; then
          zs_hb_m="$(date -r "$zs_hb" +%s 2>/dev/null || stat -c %Y "$zs_hb" 2>/dev/null || echo 0)"
          [[ "$zs_hb_m" =~ ^[0-9]+$ && $(( zs_now - zs_hb_m )) -lt 7200 ]] && zs_hb_fresh=1
        fi
        local zs_legacy_enabled=""
        if [[ "$zs_hb_fresh" -eq 0 ]] && command -v schtasks >/dev/null 2>&1; then
          local zs_names zs_name zs_state
          zs_names="$(jq -r '.mechanisms[] | select(.legacy_task_name != null) | .legacy_task_name' "$manifest" 2>/dev/null | tr -d '\r')"
          while IFS= read -r zs_name; do
            [[ -z "$zs_name" ]] && continue
            zs_state="$(MSYS_NO_PATHCONV=1 schtasks /Query /TN "$zs_name" /FO LIST /V 2>/dev/null | tr -d '\r' | sed -nE 's/^Scheduled Task State:[[:space:]]*//p' | head -1)"
            [[ "$zs_state" == "Enabled" ]] && zs_legacy_enabled="yes" && break
          done <<< "$zs_names"
          if [[ -z "$zs_legacy_enabled" ]]; then
            local zs_since_epoch zs_age_days
            zs_since_epoch="$(date -d "$zs_since" +%s 2>/dev/null || echo 0)"
            zs_age_days=$(( (zs_now - zs_since_epoch) / 86400 ))
            if [[ "$zs_age_days" -ge "$zs_days" ]]; then
              _red "maintenance-zero-substrates" "ZERO maintenance substrates alive for ${zs_age_days}d (legacy tasks Disabled since ${zs_since}, NL-Maintenance never registered, no fresh heartbeat) -- ${zs_managed} managed_by=nl-maintenance mechanisms are running NOWHERE. Fix: complete DEC-4 ratification + register (docs/plans/gated-pipeline-master-2026-08.md T10), or re-enable a legacy task as a stopgap"
            else
              _warn "maintenance-zero-substrates" "zero maintenance substrates alive (legacy Disabled since ${zs_since}, replacement unregistered; RED at ${zs_days}d, now ${zs_age_days}d) -- T10 registration pending"
            fi
          fi
        fi
      fi
    fi
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi
  if ! command -v schtasks >/dev/null 2>&1; then
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi
  [[ -f "$manifest" ]] || { CHECKS_RUN=$((CHECKS_RUN + 1)); return 0; }

  local activated_epoch now age_days
  activated_epoch="$(cat "$activation" 2>/dev/null | tr -d '\r\n')"
  [[ "$activated_epoch" =~ ^[0-9]+$ ]] || { CHECKS_RUN=$((CHECKS_RUN + 1)); return 0; }
  now="$(date +%s 2>/dev/null || echo 0)"
  age_days=$(( (now - activated_epoch) / 86400 ))
  if [[ "$age_days" -lt 14 ]]; then
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi

  local names name state still_enabled=""
  if command -v jq >/dev/null 2>&1; then
    names="$(jq -r '.mechanisms[] | select(.legacy_task_name != null) | .legacy_task_name' "$manifest" 2>/dev/null | tr -d '\r')"
  else
    names=""
  fi
  while IFS= read -r name; do
    [[ -z "$name" ]] && continue
    state="$(MSYS_NO_PATHCONV=1 schtasks /Query /TN "$name" /FO LIST /V 2>/dev/null | tr -d '\r' | sed -nE 's/^Scheduled Task State:[[:space:]]*//p' | head -1)"
    if [[ "$state" == "Enabled" ]]; then
      still_enabled="${still_enabled}${still_enabled:+, }${name}"
    fi
  done <<< "$names"

  if [[ -n "$still_enabled" ]]; then
    _red "maintenance-both-substrates-alive" "nl-maintenance.sh core has been active ${age_days} days but legacy scheduled task(s) still Enabled: ${still_enabled} -- disable them (schtasks /Change /TN \"<name>\" /Disable) now that the core covers this mechanism, or delete via the +30-day Stage 4 pass if already past due"
  fi
  CHECKS_RUN=$((CHECKS_RUN + 1))
}

# ------------------------------------------------------------
# Check: stage2-admission-open (gated-pipeline-master-2026-08 T24, REQ-C6 /
# arch-M3): REQ-A8's completion (Task 8, doctor triage finishing at <=9
# survivor REDs) mechanically OPENS Stage-2 admission -- this WARN converts
# "next cycle" from a prose intention into a standing obligation that
# persists on every doctor run until a Stage-2 plan actually goes ACTIVE.
#
# DATA-FILE HOME: same idiom as maintenance-zero-substrates above (HR-F4,
# T6) -- the clock lives in schedule-manifest.json, never in this script's
# prose (the HR-F7 rule: every WARN-flip condition is a config-data date,
# no exceptions). Key: `.stage2_admission.opened_since` (string,
# YYYY-MM-DD) -- documented in full, alongside this comment, in the
# manifest's own `stage2_admission.note` field. Written ONLY by Task 8's
# completion, never by this check. Absent key, absent object, or explicit
# JSON null (`jq .opened_since // empty` collapses all three to the same
# empty string) all mean "admission not yet open" -- this check is then
# COMPLETELY SILENT: no WARN, no RED, no output line, CHECKS_RUN still
# increments. That tolerate-absent contract is deliberate and load-bearing
# (T24's own remit): T8 is still PARTIAL at the time this check lands, and
# it must never mis-fire before T8 writes the date.
#
# DETECTION MECHANISM for "a Stage-2 plan has gone ACTIVE" (T16 fidelity
# review finding F-6, the missing-mechanism gap this task resolves): a
# Stage-2 plan is any `docs/plans/*.md` file whose header block (first 30
# lines -- the same window check_budget_active_plans uses for its own
# `Status:` scan, so both checks agree on what "header" means) carries BOTH
#   Status: ACTIVE
#   stage-2-successor: gated-pipeline-master-2026-08
# -- the marker-line convention this comment is the canonical documentation
# of. A future Stage-2 plan's author adds that one header line (mirroring
# this plan's own `design-ref:` header field, itself a REQ-B5 precedent);
# no separate registration step, config edit, or generator run is needed.
#
# WARN only, never RED (arch-M3 names this a standing-obligation surfacer,
# not a hard-stop; the plan's own non-goals list Stage-2 as admission-
# triggered NEXT cycle, so a RED here would punish a state the design
# explicitly expects to persist for a while). Single-root scan (repo_root's
# own docs/plans/) -- deliberately simpler than check_budget_active_plans'
# multi-root/worktree-dedup machinery, since arch-M3 is a single-master-plan
# admission gate, not a cross-repo budget.
# ------------------------------------------------------------
check_stage2_admission_open() {
  local live_home="$1" repo_root="$2"
  local manifest="${repo_root}/adapters/claude-code/config/schedule-manifest.json"
  local marker_plan="gated-pipeline-master-2026-08"

  if [[ ! -f "$manifest" ]] || ! command -v jq >/dev/null 2>&1; then
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi

  local opened_since
  opened_since="$(jq -r '.stage2_admission.opened_since // empty' "$manifest" 2>/dev/null | tr -d '\r')"
  if [[ -z "$opened_since" ]]; then
    # T8 has not written the date yet (still PARTIAL) -- silent, by design.
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi

  if [[ -z "$repo_root" || ! -d "${repo_root}/docs/plans" ]]; then
    _warn "stage2-admission-open" "stage-2 admission open since ${opened_since} -- repo_root/docs/plans unresolved, cannot check for a Stage-2 successor plan"
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi

  local f hdr
  for f in "${repo_root}/docs/plans"/*.md; do
    [[ -f "$f" ]] || continue
    hdr="$(head -n 30 "$f" 2>/dev/null)"
    if printf '%s\n' "$hdr" | grep -qE '^Status:[[:space:]]*ACTIVE' \
       && printf '%s\n' "$hdr" | grep -qE "^stage-2-successor:[[:space:]]*${marker_plan}[[:space:]]*\$"; then
      # A matching ACTIVE Stage-2 plan exists -- admission fulfilled, clear.
      CHECKS_RUN=$((CHECKS_RUN + 1))
      return 0
    fi
  done

  _warn "stage2-admission-open" "stage-2 admission open since ${opened_since} -- no ACTIVE docs/plans/*.md carries 'stage-2-successor: ${marker_plan}' yet; register the Stage-2 plan (Status: ACTIVE + that header line) to clear this"
  CHECKS_RUN=$((CHECKS_RUN + 1))
}

# ------------------------------------------------------------
# Check: orphaned-worktree-work — the OUT-OF-SESSION complement to
# session-start-digest.sh's feed_stranded_work (same shared detector, two
# surfaces; constitution §5 "persist in the same response" + the
# understand-phase finding that mode (e) power-loss/reboot survives ONLY
# as on-disk residue — a SessionStart-only surface would never fire for a
# machine that stays down past the next session, so the doctor (run
# out-of-band, e.g. by a scheduled task or an unrelated session's own
# --quick pass) is the second, cause-independent observation point).
#
# Delegates entirely to worktree-hygiene-sweep.sh's `--stranded
# --porcelain` (never re-implements the git/heartbeat inspection —
# CANONICAL-COUNTERS-01 discipline: one detector, not a second drifting
# implementation of "is this worktree's owner alive"). Resolution order
# for the sweeper script mirrors check_manifest_wired's own
# repo-then-live-mirror fallback: ${repo_root}/adapters/claude-code/
# scripts/ first (the real production case — the doctor is normally run
# FROM the harness repo it is checking), then ${live_home}/scripts/ (the
# installed mirror) as fallback.
#
# WARN, never RED, per ORPHANED row (constitution §10 evidence bar —
# manifest.json's fp_expectation/retirement_condition for this entry name
# why): the mode-(b) standing-by/CONTINUING-grace boundary (member
# script's own false_positive_analysis) means an occasional premature flag
# is a real, accepted possibility, and this check must never fail an
# UNRELATED session's own doctor run over another session's own worktree
# — advisory-only, exactly like the digest's own line. Graceful WARN
# (fail toward visibility, not silent skip) when repo_root is unresolved,
# git is unavailable, or the sweeper script itself cannot be found —
# same posture as check_manifest_wired's checker-missing case.
# ------------------------------------------------------------
check_orphaned_worktree_work() {
  local live_home="$1" repo_root="$2"
  [[ -z "$repo_root" ]] && { _warn "orphaned-worktree-work" "repo root unresolved — skipped"; CHECKS_RUN=$((CHECKS_RUN + 1)); return 0; }
  command -v git >/dev/null 2>&1 || { _warn "orphaned-worktree-work" "git not available — skipped"; CHECKS_RUN=$((CHECKS_RUN + 1)); return 0; }

  local sweeper="${repo_root}/adapters/claude-code/scripts/worktree-hygiene-sweep.sh"
  [[ -f "$sweeper" ]] || sweeper="${live_home}/scripts/worktree-hygiene-sweep.sh"
  if [[ ! -f "$sweeper" ]]; then
    _warn "orphaned-worktree-work" "worktree-hygiene-sweep.sh not found (repo scripts/ or live scripts/) — cannot check for stranded agent-worktree work"
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi

  local out
  out="$(bash "$sweeper" --stranded --porcelain "$repo_root" 2>/dev/null || true)"
  if [[ -n "$out" ]]; then
    local tag path branch dirty unintegrated age liveness
    while IFS="$(printf '\t')" read -r tag path branch dirty unintegrated age liveness; do
      [[ -n "$path" ]] || continue
      local remove_hint="git worktree remove ${path}"
      # agent-crashed-locked (harness-review round-2 finding): the dispatch
      # mechanism locks an agent worktree for the dispatch's duration and
      # only unlocks on clean completion, so a crashed/SIGKILLed/OOM-killed
      # agent's worktree stays locked forever — `git worktree remove`
      # refuses on a locked worktree (a real git guard), so the salvage
      # hint must name the unlock step or the operator hits a confusing
      # refusal after already doing the git-status/commit/stash salvage.
      if [[ "$liveness" == "agent-crashed-locked" ]]; then
        remove_hint="git worktree unlock ${path} && git worktree remove ${path}  (verified: a single --force is NOT enough for a locked worktree — 'git worktree remove -f -f ${path}' [force TWICE] overrides without unlocking, instead)"
      fi
      _warn "orphaned-worktree-work" "worktree ${path} (branch ${branch}) holds dirty=${dirty}/unintegrated=${unintegrated} with no live owner (liveness=${liveness}) — salvage then remove: git -C ${path} status; ${remove_hint}"
    done <<< "$out"
  fi
  CHECKS_RUN=$((CHECKS_RUN + 1))
}

# ------------------------------------------------------------
# Check: new-gate-evidence-bar (Wave F, task F.1, specs-f §F.1 item 3 /
# ADR 059 D4 — the DOCTOR side; constitution §10's prose side is
# ORCHESTRATOR-ONLY and shipped separately). Any manifest entry with
# `added_after: 2026-07` (or any value >= "2026-07" lexicographically —
# the field is a YYYY-MM string) must carry golden_scenario,
# fp_expectation, retirement_condition, and (waiver_path OR
# honesty_rationale). RED otherwise. Graceful WARN when no manifest, no
# parser, or the manifest schema does not yet declare these fields (this
# doctor check does not itself require the schema/manifest to carry the
# fields — it degrades to "no added_after entries found" silently, since
# a manifest with zero added_after entries has nothing to validate).
#
# EVASION-BY-OMISSION CLOSE (harness-governance-batch-2026-07-15, task 5):
# the check above only ever inspected entries that ALREADY carry
# `added_after`. A new `blocking:true` gate that simply never sets the
# field skipped the whole bar silently — exactly how `model-pin` evaded
# it before 2026-07-14's fix. This is now a SECOND, independent assertion
# below the first: every `blocking:true` manifest entry, regardless of
# its added_after value or absence, MUST have a non-empty STRING
# `added_after` set to its TRUE git-history landing month. A missing (or
# non-string) field is itself a RED naming the entry id and the remedy.
#
# GRANDFATHER EXEMPT-LIST (fixup, harness-review REJECT on the first cut of
# this task): the first cut of this fix backfilled 5 entries that landed
# 2026-07-02..06 (session-honesty, stop-verdict-dispatcher, work-integrity,
# secret-scan-ci-backstop, synthetic-runner-ci) with an UNDER-DATED
# added_after (2026-06) so they would not need the full bar fields. REJECTED:
# under-dating teaches every future legacy entry to dodge the bar by picking
# an earlier month, which is worse than the hole it closes. Corrected: these
# 5 now carry their TRUE added_after ("2026-07", verified via `git log
# --diff-filter=A --follow`), and are instead exempted from the full-bar
# fields (golden_scenario/fp_expectation/retirement_condition) by the
# EXPLICIT, CLOSED `PRE_BAR_GRANDFATHERED` id list below — because they
# landed before the evidence-bar CONCEPT itself entered the manifest (first
# golden_scenario field 2026-07-05; model-pin/artifact-evidence-bar
# 2026-07-12+), i.e. pre-bar in substance though not by date. added_after
# presence is still REQUIRED for grandfathered ids — only the extra
# evidence fields are waived. RETIREMENT: shrink this list as each id gains
# real golden_scenario/fp_expectation/retirement_condition; it must reach
# empty. The list is a closed enumeration, not a date-range pattern — a
# NEW, non-listed 2026-07+ blocking entry without the bar fields still REDs.
#
# The 31 legacy `blocking:true` entries that predated this assertion were
# backfilled in the same commit that added it (see manifest.json diff) so
# this does not regress the doctor to RED on landing.
# ------------------------------------------------------------
check_new_gate_evidence_bar() {
  local live_home="$1" repo_root="$2"
  local manifest
  if ! manifest="$(resolve_manifest "$live_home" "$repo_root")"; then
    _warn "new-gate-evidence-bar" "no manifest.json found — skipped (pre-C.1 machine)"
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi
  if ! command -v node >/dev/null 2>&1 && ! command -v jq >/dev/null 2>&1; then
    _warn "new-gate-evidence-bar" "neither node nor jq available — skipped"
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi

  local out
  if command -v node >/dev/null 2>&1; then
    out="$(node -e '
const fs = require("fs");
const m = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));

// PRE_BAR_GRANDFATHERED: see the check header comment above for the full
// rationale. Closed enumeration — shrink it as each id gains real bar
// fields; never grow it by pattern-matching a date range.
const PRE_BAR_GRANDFATHERED = [
  "session-honesty",
  "stop-verdict-dispatcher",
  "work-integrity",
  "secret-scan-ci-backstop",
  "synthetic-runner-ci",
];

const problems = [];
for (const e of m.entries || []) {
  const addedAfter = e.added_after;
  const hasAddedAfter = typeof addedAfter === "string" && addedAfter.trim().length > 0;
  if (e.blocking === true && !hasAddedAfter) {
    problems.push(e.id + ": missing added_after (every blocking:true manifest entry must declare its TRUE git-landing YYYY-MM month — a missing field evades the evidence bar by omission; a genuinely pre-bar legacy gate is grandfathered via the PRE_BAR_GRANDFATHERED exempt-list, never by under-dating)");
    continue;
  }
  if (!hasAddedAfter) continue;
  if (addedAfter < "2026-07") continue;
  if (PRE_BAR_GRANDFATHERED.includes(e.id)) continue;
  const missing = [];
  if (typeof e.golden_scenario !== "string" || e.golden_scenario.trim().length === 0) missing.push("golden_scenario");
  if (typeof e.fp_expectation !== "string" || e.fp_expectation.trim().length === 0) missing.push("fp_expectation");
  if (typeof e.retirement_condition !== "string" || e.retirement_condition.trim().length === 0) missing.push("retirement_condition");
  const hasWaiverPath = typeof e.waiver_path === "string" && e.waiver_path.trim().length > 0;
  const hasHonestyRationale = typeof e.honesty_rationale === "string" && e.honesty_rationale.trim().length > 0;
  if (!hasWaiverPath && !hasHonestyRationale) missing.push("waiver_path-or-honesty_rationale");
  if (missing.length) problems.push(e.id + ": missing " + missing.join(", "));
}
for (const p of problems) console.log(p);
' "$manifest" 2>/dev/null)"
  else
    out="$(jq -r '
["session-honesty","stop-verdict-dispatcher","work-integrity","secret-scan-ci-backstop","synthetic-runner-ci"] as $prebar |
(.entries[] | select(.blocking == true) | select((.added_after|type) != "string" or (.added_after|length) == 0) |
  "\(.id): missing added_after (every blocking:true manifest entry must declare its TRUE git-landing YYYY-MM month — a missing field evades the evidence bar by omission; a genuinely pre-bar legacy gate is grandfathered via the PRE_BAR_GRANDFATHERED exempt-list, never by under-dating)"),
(.entries[] | select((.added_after // "") >= "2026-07") as $e |
 select(($prebar | index($e.id)) == null) |
(
  [ (if (($e.golden_scenario // "") | length) > 0 then empty else "golden_scenario" end),
    (if (($e.fp_expectation // "") | length) > 0 then empty else "fp_expectation" end),
    (if (($e.retirement_condition // "") | length) > 0 then empty else "retirement_condition" end),
    (if ((($e.waiver_path // "") | length) > 0) or ((($e.honesty_rationale // "") | length) > 0) then empty else "waiver_path-or-honesty_rationale" end)
  ] | select(length > 0)
) as $missing | select(($missing | length) > 0) | "\($e.id): missing \($missing | join(", "))")
' "$manifest" 2>/dev/null)"
  fi

  if [[ -n "$out" ]]; then
    local line
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      if [[ "$line" == *"missing added_after"* ]]; then
        _red "new-gate-evidence-bar" "${line}"
      else
        _red "new-gate-evidence-bar" "${line} (added_after >= 2026-07 requires the full evidence bar per ADR 059 D4)"
      fi
    done <<< "$out"
  fi
  CHECKS_RUN=$((CHECKS_RUN + 1))
}

# ------------------------------------------------------------
# Check: deterministic-process-proof (adapters/claude-code/doctrine/
# deterministic-process.md, operator directive 2026-07-30: "We should never
# need to review whether the reviewers fired. Make them a deterministic part
# of the process."). The proof obligation: every `blocking:true` manifest
# entry declares BOTH `chokepoint` (the firing event, in verifiable form)
# and `bypass_paths` (every known route around it, each CLOSED or
# NAMED-AND-ACCEPTED). An entry declaring NEITHER is exactly the golden case
# the doctrine names: review-record-commit-gate.sh was `blocking:true` at a
# convenient PreToolUse layer with an unauthenticated env-var override and a
# cherry-pick exemption — four live bypass paths that were never enumerated
# anywhere in the manifest, because nothing required it. This check is the
# mechanized version of that enumeration requirement, same shape as
# check_new_gate_evidence_bar immediately above (which this file mirrors
# deliberately — one generator pattern, not two that could drift). That
# "cannot drift" claim was FALSE as written and is now MECHANIZED instead of
# asserted: the two implementations DID drift. The jq fallback bound `.id`
# against the grandfather ARRAY rather than the entry, so jq errored, the
# `2>/dev/null` ate the message, `$out` came back empty, and the check was a
# SILENT NO-OP on every machine without `node` (harness-reviewer C1,
# 2026-07-30 — PROVEN end-to-end: `--quick` with node masked out of PATH
# emitted ZERO deterministic-process-proof lines while the node path RED'd).
# Both branches now fail LOUD on a parser error, and the self-test scenarios
# `dpp-jq-*` re-run the RED/GREEN/grandfather fixtures with `node` masked out
# of PATH so the fallback is EXERCISED on every run, never trusted to match
# by inspection.
#
# WHAT REDS — BOTH fields required (harness-reviewer M7, 2026-07-30). The
# original check fired only on "declares NEITHER", so a new blocking gate
# could discharge the whole obligation by writing `chokepoint: "pre-push"`
# and never enumerating a single bypass — while `bypass_paths` is the
# load-bearing half (C2 proved four unenumerated live routes around the one
# entry that DID populate it in good faith). New entries are authored
# deliberately, so the FP cost of requiring both is nil: measured 2026-07-30,
# exactly two non-grandfathered blocking:true entries exist and one already
# carries both fields.
#
# GRANDFATHER EXEMPT-LIST (dated, closed enumeration — same convention as
# check_new_gate_evidence_bar's PRE_BAR_GRANDFATHERED, NOT a date-range
# pattern): every `blocking:true` id that existed BEFORE this check landed
# and had neither field yet. RE-DERIVE THE COUNTS MECHANICALLY rather than
# quoting the constant a past reader measured — the previous version of this
# comment said "39 blocking:true entries" and was ALREADY STALE at landing
# (the true count was 40; the 40th, `intended-functionality-if-statement`,
# landed one commit earlier, appeared in NEITHER grandfather list, and RED'd
# the live doctor from the moment this check shipped — harness-reviewer M1):
#   jq '[.entries[]|select(.blocking==true)]|length' adapters/claude-code/manifest.json
#   jq -r '.entries[]|select(.blocking==true)|select((((.chokepoint//"")|length)==0) or (((.bypass_paths//[])|length)==0))|.id' adapters/claude-code/manifest.json
# review-record-commit-gate was demoted to blocking:false in the SAME commit
# that added this check, so it needs no grandfathering at all. Of the two
# entries that commit added: `review-record-push-gate` carries real
# chokepoint + bypass_paths; `authorize-review-record-push-override` is
# blocking:false and therefore OUT OF SCOPE for this check entirely — it
# declares NEITHER field and no added_after, and an earlier draft of this
# comment wrongly claimed both new entries "carry real chokepoint/
# bypass_paths" (harness-reviewer M4).
# RETIREMENT: shrink this list as each id gains real fields;
# it must reach empty. A NEW blocking:true entry landing after this check
# exists gets ZERO ID-BASED grandfather (harness-reviewer follow-up pass,
# 2026-07-30: an earlier draft of this comment claimed "ZERO grandfather...
# must declare both fields or RED" WITHOUT qualifying which mechanism —
# FALSE as written, since the added_after < '2026-07' exemption immediately
# below is a SECOND, independent escape a backdated field still claims).
# The id-list alone would require both fields; the date threshold does not.
#
# added_after < '2026-07' ALSO SKIPS (same threshold check_new_gate_
# evidence_bar already uses, reused deliberately rather than inventing a
# second cutover convention): this file's OWN self-test builds dozens of
# throwaway fixture manifests for OTHER checks (budget-blocking-gates,
# wave-f-f2-docs, manifest-check, claim-honesty, orphaned-worktree, ...),
# each declaring its own synthetic `blocking:true` entry under a made-up id
# ("wired-gate", "fixture-gate-N", "a", ...) that is obviously not in this
# check's id-based grandfather list. Every one of those pre-existing
# fixtures already sets `added_after: "2026-04"` specifically to predate the
# evidence-bar's own 2026-07 cutover; reusing that exact field+threshold
# means this NEW check inherits the same exemption for free instead of
# false-positiving across a huge swath of this file's unrelated self-test
# scenarios (PROVEN: without this threshold, 8+ unrelated pre-existing
# scenarios flipped RED the moment this check was wired in). An entry with
# added_after missing entirely is NOT exempted by this rule (only a present,
# pre-2026-07 value is) -- it still needs the id-based grandfather or the
# fields.
check_deterministic_process_proof() {
  local live_home="$1" repo_root="$2"
  local manifest
  if ! manifest="$(resolve_manifest "$live_home" "$repo_root")"; then
    _warn "deterministic-process-proof" "no manifest.json found — skipped (pre-C.1 machine)"
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi
  if ! command -v node >/dev/null 2>&1 && ! command -v jq >/dev/null 2>&1; then
    _warn "deterministic-process-proof" "neither node nor jq available — skipped"
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi

  # Parser errors are LOUD (harness-reviewer C1): the previous version sent
  # BOTH branches' stderr to /dev/null, so a broken expression was
  # indistinguishable from a clean manifest -- the exact silent-no-op shape
  # deterministic-process.md calls theatre. stderr is captured and surfaced
  # as a WARN that names, in plain words, that the check did NOT run.
  local out parse_rc parse_err
  parse_err="$(mktemp 2>/dev/null || printf '%s' "${TMPDIR:-/tmp}/dpp-parse-err.$$")"
  if command -v node >/dev/null 2>&1; then
    out="$(node -e '
const fs = require("fs");
const m = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));

// DETERMINISTIC_PROCESS_GRANDFATHERED: see the check header comment above.
// Closed enumeration, dated 2026-07-30 — shrink as each id gains real
// chokepoint/bypass_paths fields; never grow it by pattern-matching a date.
const DETERMINISTIC_PROCESS_GRANDFATHERED = [
  "agent-teams", "backlog-plan-atomicity", "bug-persistence",
  "claude-md-hygiene", "closure-outcome-declared", "concurrent-ownership-gate",
  "decisions-index", "deploy-automation-mode", "docs-freshness",
  "env-local-protection", "find-disk-scan-gate", "findings-ledger",
  "gh-merge-canonical", "harness-hygiene-scan", "local-edit-authorization",
  "migration-claude-md", "model-availability", "model-pin", "no-test-skip",
  "parallel-dev-migration-naming", "plan-deletion-protection",
  "plan-edit-validator", "plan-reviewer", "pre-commit-chain",
  "pre-push-divergence", "pre-push-test", "review-before-deploy",
  "review-finding-fix", "runtime-verification", "secret-hygiene-prepush",
  "secret-scan-ci-backstop", "session-honesty", "spec-freeze",
  "stop-verdict-dispatcher", "synthetic-runner-ci", "tdd-gate", "wire-check",
  "work-integrity",
  // "new-gate-complete" below is a SELF-TEST FIXTURE id (the new-gate-
  // evidence-bar-green scenario, elsewhere in this file), not a real
  // manifest id -- it deliberately sets added_after to 2026-07 to exercise
  // THAT other bar and predates chokepoint/bypass_paths entirely. Listed
  // here, not via date exemption, so the date-threshold logic above stays
  // meaningful for everything else (see the added_after < 2026-07 note).
  "new-gate-complete",
];

const problems = [];
for (const e of m.entries || []) {
  if (e.blocking !== true) continue;
  if (DETERMINISTIC_PROCESS_GRANDFATHERED.includes(e.id)) continue;
  // Same 2026-07 threshold check_new_gate_evidence_bar uses -- see header
  // comment above for why (the pre-existing self-test fixtures in this file
  // conventionally set added_after to 2026-04 for exactly this reason).
  const addedAfter = e.added_after;
  if (typeof addedAfter === "string" && addedAfter.trim().length > 0 && addedAfter < "2026-07") continue;
  const hasChoke = typeof e.chokepoint === "string" && e.chokepoint.trim().length > 0;
  const hasBypass = Array.isArray(e.bypass_paths) && e.bypass_paths.length > 0;
  // BOTH required (harness-reviewer M7): chokepoint alone discharges nothing
  // -- bypass_paths is the load-bearing half. Name WHICH half is missing so
  // the message is actionable rather than a generic re-statement.
  const missing = [];
  if (!hasChoke) missing.push("chokepoint");
  if (!hasBypass) missing.push("bypass_paths");
  if (missing.length) {
    problems.push(e.id + ": blocking:true does not declare " + missing.join(" or ") + " (deterministic-process.md proof obligation — name the firing event AND enumerate every known bypass, each CLOSED with how or NAMED-AND-ACCEPTED with why; an empty enumeration claims none exist and is a lie unless someone looked)");
  }
}
for (const p of problems) console.log(p);
' "$manifest" 2>"$parse_err")"
    parse_rc=$?
  else
    out="$(jq -r '
[
  "agent-teams","backlog-plan-atomicity","bug-persistence","claude-md-hygiene",
  "closure-outcome-declared","concurrent-ownership-gate","decisions-index",
  "deploy-automation-mode","docs-freshness","env-local-protection",
  "find-disk-scan-gate","findings-ledger","gh-merge-canonical",
  "harness-hygiene-scan","local-edit-authorization","migration-claude-md",
  "model-availability","model-pin","no-test-skip",
  "parallel-dev-migration-naming","plan-deletion-protection",
  "plan-edit-validator","plan-reviewer","pre-commit-chain",
  "pre-push-divergence","pre-push-test","review-before-deploy",
  "review-finding-fix","runtime-verification","secret-hygiene-prepush",
  "secret-scan-ci-backstop","session-honesty","spec-freeze",
  "stop-verdict-dispatcher","synthetic-runner-ci","tdd-gate","wire-check",
  "work-integrity","new-gate-complete"
] as $gf |
(.entries[] | select(.blocking == true) as $e |
  select(($gf | index($e.id)) == null) |
  select(((($e.added_after // "") | length) == 0) or (($e.added_after // "") >= "2026-07")) |
  ([ (if (($e.chokepoint // "") | length) > 0 then empty else "chokepoint" end),
     (if (($e.bypass_paths // []) | length) > 0 then empty else "bypass_paths" end)
   ] | select(length > 0)) as $missing |
  "\($e.id): blocking:true does not declare \($missing | join(" or ")) (deterministic-process.md proof obligation — name the firing event AND enumerate every known bypass, each CLOSED with how or NAMED-AND-ACCEPTED with why; an empty enumeration claims none exist and is a lie unless someone looked)")
' "$manifest" 2>"$parse_err")"
    parse_rc=$?
  fi

  # A parser failure is NOT "nothing to report" (harness-reviewer C1). Surface
  # it, name that the check did not run, and keep going -- a broken expression
  # must never masquerade as a clean manifest.
  if [[ "${parse_rc:-0}" -ne 0 ]]; then
    local perr; perr="$(tr '\n' ' ' < "$parse_err" 2>/dev/null | cut -c1-300)"
    _warn "deterministic-process-proof" "the manifest parser FAILED (rc=${parse_rc}) — this check did NOT run, so a missing chokepoint/bypass_paths declaration would go unreported: ${perr:-no stderr captured}"
    rm -f "$parse_err" 2>/dev/null
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi
  rm -f "$parse_err" 2>/dev/null

  if [[ -n "$out" ]]; then
    local line
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      _red "deterministic-process-proof" "${line}"
    done <<< "$out"
  fi
  CHECKS_RUN=$((CHECKS_RUN + 1))
}

# ------------------------------------------------------------
# Check: line-endings (NL-FINDING-038, Wave-F F.1 incident; live-mirror scan
# added for LIVE-MIRROR-CRLF-01). On Windows a file-edit can silently
# rewrite a whole tracked script LF -> CRLF: before .gitattributes landed
# that produced a ~2000-line spurious diff; with the eol=lf pin in force
# the clean filter NORMALIZES the comparison instead, so `git status` shows
# CLEAN while the on-disk bytes stay CRLF — invisible to git, but
# install.sh cp's those working-tree bytes live, Linux CI bash hard-fails
# on \r, and heredocs the script emits carry the pollution forward. This
# check is the primary detector for that masked state in the REPO working
# tree.
#
# The live mirror (~/.claude) is ALSO scanned now, but only ever WARNs
# (never REDs): a mirror built before the .gitattributes pin landed, or by
# an installer running on a stale core.autocrlf=true checkout, can carry
# CRLF forward via install.sh's `cp` fallback (no symlink support) even
# though the repo tree is clean today. That is stale-mirror drift, not an
# active break — MSYS bash tolerates CRLF at runtime — and install.sh's
# CRLF-normalization-on-copy (LIVE-MIRROR-CRLF-01) self-heals it on the next
# run, so RED would be a false alarm for a one-command fix. Distinguishing
# it from a real REPO regression (still RED) is exactly the fix this
# extension delivers — NL-FINDING-038's own residual-risk note flagged that
# the doctor "is the only detector" of masked CRLF yet never looked at the
# one place (the live mirror) that matters at runtime.
# Detection is pure-bash byte matching ([[ == *$'\r'* ]]) — NEVER grep/sed/
# awk, which silently strip \r on MSYS (NL-FINDING-030).
#   RED  : a tracked shell surface (*.sh, git-hooks/*) has CR bytes on disk
#          in the REPO working tree.
#   WARN : repo .gitattributes lacks the '*.sh text eol=lf' pin, OR the live
#          mirror (~/.claude/hooks, hooks/lib, scripts) carries CRLF while
#          the repo tree is clean (transition-period signal — run
#          install.sh to normalize; never RED for this half of the check).
# ------------------------------------------------------------
check_line_endings() {
  local live_home="$1" repo_root="$2"
  if [[ -z "$repo_root" ]]; then
    _warn "line-endings" "repo root unresolved — skipped"
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi

  local f content toplevel
  toplevel="$(git -C "$repo_root" rev-parse --show-toplevel 2>/dev/null)"
  if [[ -n "$toplevel" && "$toplevel" -ef "$repo_root" ]]; then
    # Real repo (repo_root IS the toplevel — an -ef inode compare, so a
    # fixture dir that merely sits INSIDE some repo still takes the glob
    # branch): enumerate every tracked shell surface.
    # process-substitution (not a trailing pipe) so _red's RED_COUNT
    # increment happens in THIS shell (same trap as lib-deps).
    while IFS= read -r -d '' f; do
      [[ -f "$repo_root/$f" && -s "$repo_root/$f" ]] || continue
      content="$(<"$repo_root/$f")"
      if [[ "$content" == *$'\r'* ]]; then
        _red "line-endings" "${f} has CR bytes in the working tree (the eol=lf clean filter masks this — git status shows clean) — fix: dos2unix '${f}' (NL-FINDING-038)"
      fi
    done < <(git -C "$repo_root" ls-files -z -- '*.sh' 'adapters/claude-code/git-hooks/*' 2>/dev/null)
  else
    # Non-git contexts (self-test fixtures): scan the adapter shell dirs.
    for f in "$repo_root"/adapters/claude-code/hooks/*.sh \
             "$repo_root"/adapters/claude-code/hooks/lib/*.sh \
             "$repo_root"/adapters/claude-code/scripts/*.sh \
             "$repo_root"/adapters/claude-code/git-hooks/*; do
      [[ -f "$f" && -s "$f" ]] || continue
      content="$(<"$f")"
      if [[ "$content" == *$'\r'* ]]; then
        _red "line-endings" "${f#"$repo_root"/} has CR bytes — fix: dos2unix (NL-FINDING-038)"
      fi
    done
  fi

  if [[ ! -f "$repo_root/.gitattributes" ]] \
     || ! grep -qE '^\*\.sh[[:space:]]+text[[:space:]]+eol=lf' "$repo_root/.gitattributes" 2>/dev/null; then
    _warn "line-endings" ".gitattributes is missing its '*.sh text eol=lf' pin — CRLF can enter the index on clones without a local autocrlf override (NL-FINDING-038)"
  fi

  # Live-mirror scan (LIVE-MIRROR-CRLF-01): WARN-only, transition-period
  # signal. Scans ${live_home}/hooks/*.sh, ${live_home}/hooks/lib/*.sh, and
  # ${live_home}/scripts/*.sh for CR bytes using the same pure-bash byte
  # match as the repo scan above (never grep — NL-FINDING-030). A single
  # WARN covers the whole mirror (not one per file) so a stale mirror
  # doesn't flood the doctor's output; the fix (re-run install.sh) is the
  # same regardless of how many files carry CRLF.
  if [[ -n "$live_home" && -d "$live_home" ]]; then
    local live_crlf_found=0
    for f in "$live_home"/hooks/*.sh \
             "$live_home"/hooks/lib/*.sh \
             "$live_home"/scripts/*.sh; do
      [[ -f "$f" && -s "$f" ]] || continue
      content="$(<"$f")"
      if [[ "$content" == *$'\r'* ]]; then
        live_crlf_found=1
        break
      fi
    done
    if [[ "$live_crlf_found" -eq 1 ]]; then
      _warn "line-endings" "live mirror carries pre-pin CRLF — run install.sh to normalize (${live_home}/hooks and/or scripts contain CR bytes; NL-FINDING-038 residual-risk gap, LIVE-MIRROR-CRLF-01)"
    fi
  fi
  CHECKS_RUN=$((CHECKS_RUN + 1))
}

# ------------------------------------------------------------
# Check 6: byte-budget
# ------------------------------------------------------------
check_byte_budget() {
  local live_home="$1"
  local rules_dir="${live_home}/rules"
  local budget_file="${live_home}/local/doctor-budget"
  local default_budget=1000000
  local budget="$default_budget"
  local strict=0

  if [[ -f "$budget_file" ]]; then
    local v
    v="$(tr -d '[:space:]' < "$budget_file" 2>/dev/null)"
    if [[ "$v" =~ ^[0-9]+$ ]]; then
      budget="$v"
      strict=1
    fi
  fi

  if [[ ! -d "$rules_dir" ]]; then
    _warn "byte-budget" "no live rules/ directory at ${rules_dir} — nothing to check"
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi

  local total
  total="$(cat "$rules_dir"/*.md 2>/dev/null | wc -c | tr -d '[:space:]')"
  total="${total:-0}"

  if [[ "$total" -gt "$budget" ]]; then
    if [[ "$strict" -eq 1 ]]; then
      _red "byte-budget" "${total} bytes across ~/.claude/rules/*.md exceeds the configured budget of ${budget}"
    else
      _warn "byte-budget" "${total} bytes across ~/.claude/rules/*.md exceeds the default warn-only budget of ${budget} (set ~/.claude/local/doctor-budget to make this strict)"
    fi
  fi
  CHECKS_RUN=$((CHECKS_RUN + 1))
}

# ------------------------------------------------------------
# Check 8: selftest-sweep (--full only)
# ------------------------------------------------------------
# ------------------------------------------------------------
# Check: master-drift-autocorrect (docs/plans/master-drift-autocorrection-
# 2026-07.md Task 4, constitution §10: the doctor arbitrates the mechanism
# claim). Quick predicates (structural, tolerate-absent like the E.6/E.7/
# E.8 sub-checks — a bare fixture repo simply hasn't installed this
# mechanism):
#   1. repo scripts/master-drift-autocorrect.sh exists (WARN when absent)
#      and carries a --self-test entrypoint (RED when present without one —
#      the manifest entry claims selftest).
#   2. hook wiring: when session-start-git-freshness.sh exists (repo side
#      preferred, live fallback) it must reference the corrector — a
#      freshness hook that never dispatches it is a silent no-op mechanism
#      (RED; same pattern as the E.8 nl-issue digest-wiring predicate).
# The "--self-test exits 0" half of the predicate runs in --full mode only
# (check_master_drift_selftest below), matching the doctor's quick<2s
# contract; the hooks selftest-sweep cannot cover it (scripts/ is not
# hooks/).
# ------------------------------------------------------------
check_master_drift_autocorrect() {
  local live_home="$1" repo_root="$2"

  local md_script=""
  [[ -n "$repo_root" && -f "${repo_root}/adapters/claude-code/scripts/master-drift-autocorrect.sh" ]] \
    && md_script="${repo_root}/adapters/claude-code/scripts/master-drift-autocorrect.sh"
  [[ -z "$md_script" && -f "${live_home}/scripts/master-drift-autocorrect.sh" ]] \
    && md_script="${live_home}/scripts/master-drift-autocorrect.sh"

  if [[ -z "$md_script" ]]; then
    _warn "master-drift-autocorrect" "master-drift-autocorrect.sh missing (repo scripts/ and live scripts/) — mechanism not yet installed on this machine/fixture"
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi
  if ! grep -q -- '--self-test' "$md_script" 2>/dev/null; then
    _red "master-drift-autocorrect" "master-drift-autocorrect.sh has no --self-test entrypoint despite its manifest selftest claim (${md_script})"
  fi

  local md_hook=""
  [[ -n "$repo_root" && -f "${repo_root}/adapters/claude-code/hooks/session-start-git-freshness.sh" ]] \
    && md_hook="${repo_root}/adapters/claude-code/hooks/session-start-git-freshness.sh"
  [[ -z "$md_hook" && -f "${live_home}/hooks/session-start-git-freshness.sh" ]] \
    && md_hook="${live_home}/hooks/session-start-git-freshness.sh"
  if [[ -n "$md_hook" ]]; then
    if ! grep -q "master-drift-autocorrect.sh" "$md_hook" 2>/dev/null; then
      _red "master-drift-autocorrect" "session-start-git-freshness.sh exists but never dispatches master-drift-autocorrect.sh (silent no-op mechanism) — ${md_hook}"
    fi
  fi
  CHECKS_RUN=$((CHECKS_RUN + 1))
}

# --full companion: the corrector's --self-test must exit 0 (sandboxed via
# HARNESS_SELFTEST=1, same timeout discipline as check_selftest_sweep).
# Absence-tolerant: quick's structural predicate already WARNed.
check_master_drift_selftest() {
  local live_home="$1" repo_root="$2"
  local md_script=""
  [[ -n "$repo_root" && -f "${repo_root}/adapters/claude-code/scripts/master-drift-autocorrect.sh" ]] \
    && md_script="${repo_root}/adapters/claude-code/scripts/master-drift-autocorrect.sh"
  [[ -z "$md_script" && -f "${live_home}/scripts/master-drift-autocorrect.sh" ]] \
    && md_script="${live_home}/scripts/master-drift-autocorrect.sh"
  if [[ -z "$md_script" ]]; then
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi
  local out rc last_line
  out="$(HARNESS_SELFTEST=1 nl_run_bounded "${DOCTOR_SELFTEST_TIMEOUT:-1500}" bash "$md_script" --self-test </dev/null 2>&1)"
  rc=$?
  if [[ "$rc" -eq 124 ]]; then
    _red "master-drift-autocorrect" "master-drift-autocorrect.sh --self-test exceeded the ${DOCTOR_SELFTEST_TIMEOUT:-1500}s bound and was killed"
  elif [[ "$rc" -ne 0 ]]; then
    last_line="$(printf '%s\n' "$out" | tail -n 1)"
    _red "master-drift-autocorrect" "master-drift-autocorrect.sh --self-test exited ${rc}: ${last_line}"
  fi
  CHECKS_RUN=$((CHECKS_RUN + 1))
}

# ------------------------------------------------------------
# Check: selftest-sweep-exclusions (docs/plans/macos-portability-2026-07.md
# M6). M6 disposed of the 3 residual attic/ self-test failures: one FIXED
# (attic/workstreams-state-gate.sh), two formally EXCLUDED via the ledger
# adapters/claude-code/config/selftest-sweep-exclusions.txt. M6's own wording
# is "silence is not" an acceptable outcome, and constitution §10 calls
# documented-enforcement-that-never-fires the cardinal harness defect — so the
# ledger gets a doctor predicate rather than a comment.
#
# QUICK half (here): zero-subprocess structural predicate only, matching the
# doctor's quick<2s contract and the fork-storm discipline of the 07-20
# lesson. It asserts the MECHANISM exists — a ledger with no reader is a
# ledger nothing enforces:
#   - ledger absent            -> silent (nothing excluded; also the bare
#                                 fixture-repo case, tolerate-absent like the
#                                 E.6/E.7/E.8 and master-drift predicates)
#   - ledger present, reader missing / no --self-test entrypoint -> RED
# The CONTENT predicates (C1 path exists / C2 reason states a root cause /
# C3 no live surface silenced) and C4 (each excluded script still fails) run
# in --full via check_selftest_exclusions_selftest below, because they need
# the reader's parser and, for C4, real child processes.
# ------------------------------------------------------------
check_selftest_exclusions_wiring() {
  local repo_root="$1"
  [[ -z "$repo_root" ]] && { CHECKS_RUN=$((CHECKS_RUN + 1)); return 0; }

  local ledger="${repo_root}/adapters/claude-code/config/selftest-sweep-exclusions.txt"
  local reader="${repo_root}/adapters/claude-code/scripts/selftest-sweep-exclusions.sh"

  if [[ ! -f "$ledger" ]]; then
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi
  if [[ ! -f "$reader" ]]; then
    _red "selftest-exclusions" "${ledger} exists but its reader scripts/selftest-sweep-exclusions.sh does not — the exclusion ledger is unenforced text"
  elif ! grep -q -- '--self-test' "$reader" 2>/dev/null; then
    _red "selftest-exclusions" "scripts/selftest-sweep-exclusions.sh has no --self-test entrypoint — its C1/C2/C3/C4 controls are unverified"
  fi
  CHECKS_RUN=$((CHECKS_RUN + 1))
}

# --full companion: run the reader's own controls. `--check` covers C1/C2/C3
# against the shipped ledger; `--self-test` re-runs those against RED/GREEN
# fixtures AND covers C4 (every excluded script still fails, the fixed one
# still passes) against the REAL scripts. Absence-tolerant; bounded exactly
# like check_selftest_sweep. Runs the child under THIS interpreter ("$BASH"),
# never a bare `bash` — a bare `bash` would silently report a verdict for
# whichever interpreter happens to be first on PATH.
check_selftest_exclusions_selftest() {
  local repo_root="$1"
  [[ -z "$repo_root" ]] && { CHECKS_RUN=$((CHECKS_RUN + 1)); return 0; }
  local reader="${repo_root}/adapters/claude-code/scripts/selftest-sweep-exclusions.sh"
  if [[ ! -f "$reader" ]]; then
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi

  local out rc last_line
  out="$(NL_REPO_ROOT="$repo_root" nl_run_bounded "${DOCTOR_SELFTEST_TIMEOUT:-1500}" "$BASH" "$reader" --check </dev/null 2>&1)"
  rc=$?
  if [[ "$rc" -ne 0 ]]; then
    last_line="$(printf '%s\n' "$out" | tail -n 1)"
    _red "selftest-exclusions" "selftest-sweep-exclusions.sh --check exited ${rc}: ${last_line}"
  fi

  out="$(HARNESS_SELFTEST=1 NL_REPO_ROOT="$repo_root" nl_run_bounded "${DOCTOR_SELFTEST_TIMEOUT:-1500}" "$BASH" "$reader" --self-test </dev/null 2>&1)"
  rc=$?
  if [[ "$rc" -eq 124 ]]; then
    _red "selftest-exclusions" "selftest-sweep-exclusions.sh --self-test exceeded the ${DOCTOR_SELFTEST_TIMEOUT:-1500}s bound and was killed"
  elif [[ "$rc" -ne 0 ]]; then
    last_line="$(printf '%s\n' "$out" | tail -n 1)"
    _red "selftest-exclusions" "selftest-sweep-exclusions.sh --self-test exited ${rc}: ${last_line}"
  fi
  CHECKS_RUN=$((CHECKS_RUN + 1))
}

# _agent_frontmatter_model <file> — echo the `model:` value from a file's
# FIRST YAML frontmatter block (first ---…--- fence). Empty if none. Pure
# bash + CRLF-safe (strips \r); fence-scoped so a body line starting `model:`
# does NOT count (never grep/awk for fence detection — MSYS mangles \r).
_agent_frontmatter_model() {
  local f="$1" in_fm=0 line
  [ -f "$f" ] || return 0
  while IFS= read -r line; do
    line="${line%$'\r'}"
    if [ "$line" = "---" ]; then
      if [ "$in_fm" -eq 0 ]; then in_fm=1; continue; else break; fi
    fi
    if [ "$in_fm" -eq 1 ]; then
      case "$line" in model:*) printf '%s' "${line#model:}" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'; return 0 ;; esac
    fi
  done < "$f"
  return 0
}

# ------------------------------------------------------------
# Check: model-pins -- every agents/*.md has ^model: and the value
# matches a model_id key in config/model-policy.json (operator
# directive 2026-07-14). Keeps agents pinned over time so the
# model-pin-gate.sh PreToolUse backstop is never the only line of
# defence against silent premium-tier (Fable) model-inherit.
# RED per unpinned or unknown-model agent. WARN (skip) when repo
# unresolved or no agents dir.
# ------------------------------------------------------------
check_model_pins() {
  local live_home="$1" repo_root="$2"
  [[ -z "$repo_root" ]] && { _warn "model-pins" "repo root unresolved -- skipped"; CHECKS_RUN=$((CHECKS_RUN + 1)); return 0; }

  local agents_dir="${repo_root}/adapters/claude-code/agents"
  [[ -d "$agents_dir" ]] || { _warn "model-pins" "no agents directory at ${agents_dir} -- skipped"; CHECKS_RUN=$((CHECKS_RUN + 1)); return 0; }

  local policy="${repo_root}/adapters/claude-code/config/model-policy.json"
  local valid_models=""
  if [[ -f "$policy" ]] && command -v jq >/dev/null 2>&1; then
    # tr -d '\r' FIRST: jq on Windows/git-bash emits CRLF, so each key
    # carries a trailing \r that would poison the alternation (fable\r
    # never matches fable). Strip CR before folding newlines to pipes.
    valid_models="$(jq -r '.model_ids | keys[]' "$policy" 2>/dev/null | tr -d '\r' | tr '\n' '|')"
    valid_models="${valid_models%|}"
  fi

  local agent_file model_val any_found=0
  for agent_file in "$agents_dir"/*.md; do
    [[ -f "$agent_file" ]] || continue
    any_found=1
    local basename_f
    basename_f="$(basename "$agent_file")"
    model_val="$(_agent_frontmatter_model "$agent_file")"
    if [[ -z "$model_val" ]]; then
      _red "model-pins" "${basename_f} has no model: frontmatter -- silent model-inherit risk (operator directive 2026-07-14)"
      continue
    fi
    if [[ -n "$valid_models" ]]; then
      if ! printf '%s' "$model_val" | grep -qE "^(${valid_models})$"; then
        _red "model-pins" "${basename_f} pins model: ${model_val} which is not in model-policy.json model_ids (valid: ${valid_models//|/, })"
      fi
    fi
  done

  [[ "$any_found" -eq 0 ]] && _warn "model-pins" "no *.md files found in ${agents_dir}"
  CHECKS_RUN=$((CHECKS_RUN + 1))
}

# ------------------------------------------------------------
# Check: review-surface-cross-check (harness-governance-batch-2026-07-15,
# task 2, Amendment A). The review-before-deploy gate's trigger surface is
# now a PATH-GLOB match (adapters/claude-code/{hooks/**/*.sh, scripts/**/*.sh,
# agents/*.md, config/**, manifest.json, settings.json.template, rules/**}),
# not manifest-derived -- but the manifest is a CROSS-CHECK against it: every
# basename in every manifest entry's hooks[] array must resolve to a real
# file under hooks/, hooks/lib/, or scripts/, AND that resolved path must
# itself be in-surface. manifest-check.sh's own "hooks-exist" check only
# disk-scans TOP-LEVEL hooks/*.sh (documented scope), so a hooks[] entry
# naming a file that only exists under hooks/lib/ or scripts/ would pass
# THAT check silently -- this check widens the resolution search to close
# exactly that gap.
#   RED  : a hooks[] basename resolves to nothing anywhere under hooks/,
#          hooks/lib/, or scripts/, OR resolves to a path outside the
#          trigger-surface glob (structurally shouldn't happen given the
#          glob's own breadth, but asserted rather than assumed).
#   WARN : manifest/lib prerequisites missing (pre-cutover checkout).
# ------------------------------------------------------------
check_review_surface_cross_check() {
  local live_home="$1" repo_root="$2"
  [[ -z "$repo_root" ]] && { _warn "review-surface-cross-check" "repo root unresolved -- skipped"; CHECKS_RUN=$((CHECKS_RUN + 1)); return 0; }

  local manifest
  if ! manifest="$(resolve_manifest "$live_home" "$repo_root")"; then
    _warn "review-surface-cross-check" "no manifest.json found -- skipped (pre-C.1 machine)"
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi
  command -v jq >/dev/null 2>&1 || { _warn "review-surface-cross-check" "jq unavailable -- skipped"; CHECKS_RUN=$((CHECKS_RUN + 1)); return 0; }

  local lib="${repo_root}/adapters/claude-code/hooks/lib/review-record-gate-lib.sh"
  if [[ ! -f "$lib" ]]; then
    _warn "review-surface-cross-check" "review-record-gate-lib.sh not present at ${lib} -- skipped (pre-cutover checkout)"
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi
  # shellcheck source=lib/review-record-gate-lib.sh
  source "$lib" 2>/dev/null
  if ! command -v rrg_in_surface >/dev/null 2>&1; then
    _warn "review-surface-cross-check" "could not source review-record-gate-lib.sh -- skipped"
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi

  local names name resolved
  # tr -d '\r' FIRST: jq on Windows/git-bash emits CRLF, so each name would
  # otherwise carry a trailing \r that can never match a real filename (the
  # same gotcha check_model_pins already works around).
  names=$(jq -r '.entries[] | .hooks[]?' "$manifest" 2>/dev/null | tr -d '\r' | sort -u)
  while IFS= read -r name; do
    [[ -z "$name" ]] && continue
    resolved=""
    if [[ "$name" == lib/*.sh ]]; then
      # manifest-check.sh's convention (its own schema + disk-coverage
      # check, "isLibRef"): a "lib/<name>.sh" hooks[] value is a SOURCED
      # LIBRARY reference, resolved hooks_dir-RELATIVE -- i.e.
      # "lib/sessionstart-singleflight.sh" means
      # adapters/claude-code/hooks/lib/sessionstart-singleflight.sh, NOT
      # adapters/claude-code/lib/sessionstart-singleflight.sh (harness-review
      # REFORMULATE fixup finding 5 -- this branch previously resolved the
      # normalized lib/<name>.sh form against the wrong base directory,
      # producing a false RED on every real doctor run against master).
      [[ -f "${repo_root}/adapters/claude-code/hooks/${name}" ]] && resolved="hooks/${name}"
    elif [[ "$name" == */* ]]; then
      # Any OTHER already-qualified sub-path a manifest entry might carry
      # (forward-compat with a convention not yet named) -- resolve it
      # directly relative to adapters/claude-code/.
      [[ -f "${repo_root}/adapters/claude-code/${name}" ]] && resolved="$name"
    elif [[ -f "${repo_root}/adapters/claude-code/hooks/${name}" ]]; then
      resolved="hooks/${name}"
    elif [[ -f "${repo_root}/adapters/claude-code/hooks/lib/${name}" ]]; then
      resolved="hooks/lib/${name}"
    elif [[ -f "${repo_root}/adapters/claude-code/scripts/${name}" ]]; then
      resolved="scripts/${name}"
    fi
    if [[ -z "$resolved" ]]; then
      _red "review-surface-cross-check" "manifest hooks[] entry '${name}' does not resolve to any file under hooks/, hooks/lib/, or scripts/ (Amendment A cross-check)"
      continue
    fi
    if ! rrg_in_surface "$resolved"; then
      _red "review-surface-cross-check" "manifest hooks[] entry '${name}' resolves to ${resolved}, which is OUT of the review-before-deploy trigger surface (Amendment A cross-check)"
    fi
  done <<< "$names"

  CHECKS_RUN=$((CHECKS_RUN + 1))
}

# ------------------------------------------------------------
# Check: review-index-consistency (harness-governance-batch-2026-07-15,
# task 2, Amendment D). docs/reviews/records/index.json is claimed to be a
# pure, faithful rebuild of the records directory (never hand-edited, never
# incrementally patched). This check re-derives the index from scratch via
# write-review-record.sh's own `rebuild-index --stdout` and byte-compares
# (order-independent, via jq -S) against the committed index.json.
#   RED  : the committed index disagrees with a fresh rebuild -- someone
#          hand-edited it, or a record was added/removed without refreshing
#          the index.
#   WARN : no records directory / index.json / writer script yet (pre-
#          bootstrap checkout) -- vacuously nothing to compare.
# ------------------------------------------------------------
check_review_index_consistency() {
  local live_home="$1" repo_root="$2"
  [[ -z "$repo_root" ]] && { _warn "review-index-consistency" "repo root unresolved -- skipped"; CHECKS_RUN=$((CHECKS_RUN + 1)); return 0; }

  local records_dir="${repo_root}/docs/reviews/records"
  if [[ ! -d "$records_dir" ]] || [[ ! -f "$records_dir/index.json" ]]; then
    _warn "review-index-consistency" "no docs/reviews/records/index.json yet -- skipped (pre-bootstrap checkout)"
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi
  local writer="${repo_root}/adapters/claude-code/scripts/write-review-record.sh"
  if [[ ! -f "$writer" ]]; then
    _warn "review-index-consistency" "write-review-record.sh not present -- skipped"
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi
  command -v jq >/dev/null 2>&1 || { _warn "review-index-consistency" "jq unavailable -- skipped"; CHECKS_RUN=$((CHECKS_RUN + 1)); return 0; }

  local committed rebuilt
  committed=$(jq -S . "$records_dir/index.json" 2>/dev/null)
  rebuilt=$(bash "$writer" rebuild-index --repo-root "$repo_root" --stdout 2>/dev/null | jq -S . 2>/dev/null)
  if [[ -z "$rebuilt" ]]; then
    _warn "review-index-consistency" "rebuild-index produced no output -- skipped"
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi
  if [[ "$committed" != "$rebuilt" ]]; then
    _red "review-index-consistency" "docs/reviews/records/index.json does not match a fresh rebuild of the records directory -- run 'bash adapters/claude-code/scripts/write-review-record.sh rebuild-index' and commit the result"
  fi
  CHECKS_RUN=$((CHECKS_RUN + 1))
}

# ------------------------------------------------------------
# Check: review-grandfather-integrity (harness-review REFORMULATE fixup,
# finding 3). The grandfather manifest and the records directory are TRUST
# ANCHORS -- content the deploy gate treats as "already covered, no PASS
# needed" purely because it existed at a recorded cutover point. Neither had
# any integrity check: a hand-edit (add an entry for content that was NEVER
# actually reviewed) or a silent re-bootstrap (quietly moving the cutover
# forward to grandfather something that should have required a real
# review) would be invisible. This check makes both detectable:
#
#   RED (absence-while-mechanism-present): the review-record-gate-lib
#   exists in this checkout (the mechanism has landed) but
#   docs/reviews/records/grandfather-manifest.json is MISSING -- a
#   bootstrapped-then-emptied checkout (or a records dir deleted without
#   re-bootstrapping) is a DEFECT, not the pre-cutover fail-open case (that
#   case is "the lib itself doesn't exist yet", handled by the graceful
#   WARN below).
#
#   RED (content divergence): grandfather-manifest.json's own recorded
#   cutover_ref is re-derived via `write-review-record.sh bootstrap-
#   grandfather --ref <cutover_ref> --stdout` and byte-compared (minus the
#   generated_at timestamp, which legitimately differs between runs)
#   against the committed file. A mismatch means the committed file is NOT
#   a faithful snapshot of what existed at its own claimed cutover point --
#   detectable via this check AND via git history (the grandfather file's
#   own commit history shows every edit).
#
#   WARN (graceful, pre-cutover): the lib itself is absent (mechanism not
#   yet landed on this checkout) -- nothing to verify.
# ------------------------------------------------------------
check_review_grandfather_integrity() {
  local live_home="$1" repo_root="$2"
  [[ -z "$repo_root" ]] && { _warn "review-grandfather-integrity" "repo root unresolved -- skipped"; CHECKS_RUN=$((CHECKS_RUN + 1)); return 0; }

  local lib="${repo_root}/adapters/claude-code/hooks/lib/review-record-gate-lib.sh"
  if [[ ! -f "$lib" ]]; then
    _warn "review-grandfather-integrity" "review-record-gate-lib.sh not present -- skipped (pre-cutover checkout)"
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi

  local records_dir="${repo_root}/docs/reviews/records"
  local gf="${records_dir}/grandfather-manifest.json"
  if [[ ! -d "$records_dir" ]] || [[ ! -f "$gf" ]]; then
    _red "review-grandfather-integrity" "the review-record-gate-lib exists but docs/reviews/records/grandfather-manifest.json is ABSENT -- a bootstrapped-then-emptied checkout (or a deleted-without-re-bootstrapping records dir) is a defect; run 'bash adapters/claude-code/scripts/write-review-record.sh bootstrap-grandfather'"
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi

  command -v jq >/dev/null 2>&1 || { _warn "review-grandfather-integrity" "jq unavailable -- skipped"; CHECKS_RUN=$((CHECKS_RUN + 1)); return 0; }
  command -v git >/dev/null 2>&1 || { _warn "review-grandfather-integrity" "git unavailable -- skipped"; CHECKS_RUN=$((CHECKS_RUN + 1)); return 0; }

  local cutover_ref
  cutover_ref=$(jq -r '.cutover_ref // empty' "$gf" 2>/dev/null)
  if [[ -z "$cutover_ref" ]]; then
    _red "review-grandfather-integrity" "docs/reviews/records/grandfather-manifest.json has no cutover_ref -- cannot verify integrity; regenerate via bootstrap-grandfather"
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi
  if ! git -C "$repo_root" cat-file -e "${cutover_ref}^{commit}" 2>/dev/null; then
    _red "review-grandfather-integrity" "docs/reviews/records/grandfather-manifest.json's cutover_ref (${cutover_ref}) does not resolve to a commit in this repo -- possibly hand-edited or corrupted"
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi

  local writer="${repo_root}/adapters/claude-code/scripts/write-review-record.sh"
  if [[ ! -f "$writer" ]]; then
    _warn "review-grandfather-integrity" "write-review-record.sh not present -- skipped"
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi

  local rederived committed
  rederived=$(bash "$writer" bootstrap-grandfather --repo-root "$repo_root" --ref "$cutover_ref" --stdout 2>/dev/null | jq -S 'del(.generated_at)' 2>/dev/null)
  committed=$(jq -S 'del(.generated_at)' "$gf" 2>/dev/null)
  if [[ -z "$rederived" ]]; then
    _warn "review-grandfather-integrity" "could not re-derive the grandfather manifest at cutover_ref ${cutover_ref} -- skipped"
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi
  if [[ "$committed" != "$rederived" ]]; then
    _red "review-grandfather-integrity" "docs/reviews/records/grandfather-manifest.json does not match a fresh re-derivation at its own recorded cutover_ref (${cutover_ref}) -- a hand-edit or silent re-bootstrap is detectable this way, and via the file's own git history; regenerate honestly via bootstrap-grandfather at a NEW cutover if content genuinely needs to change"
  fi
  CHECKS_RUN=$((CHECKS_RUN + 1))
}

# ------------------------------------------------------------
# Check: review-reviewer-independence (docs/plans/review-independence.md,
# RI3). A `harness-change-review` PASS record is a self-approval if the SAME
# git identity both authored the reviewed content AND authored the commit
# that added the record approving it -- the exact class this whole plan
# exists to structurally eliminate (an authoring session dispatching
# harness-reviewer and then writing its own PASS record).
#
# WHY GIT-COMMIT AUTHORSHIP, NOT THE JSON reviewer_principal FIELD: session
# ids and hostnames live in the (uncommitted, per-machine)
# ~/.claude/state/review-queue/ queue items, never in the repo -- a doctor
# check that scans committed history cannot see them after the fact, and
# post-pivot (docs/decisions/067-review-independence-same-session-pathway.
# md) same-hostname/same-account review is the EXPECTED case, not a
# violation, so comparing those JSON fields would false-positive on every
# normal same-machine review. Git commit authorship is the one signal that
# is BOTH durable (survives in history forever) AND per-content (not
# per-account) -- exactly the "unforgeable half" named in the operator's
# 2026-07-29 design-sharpening message.
#
# MECHANISM: for each `kind: harness-change-review`, `verdict: PASS` record,
# compare the git author email of `change_ref.commit_sha` (the reviewed
# commit, as recorded by write-review-record.sh at capture time) against
# the git author email of the commit that ADDED the record file itself
# (review-runner.sh's own commit, per RI2 -- the first, and by the
# append-only convention the ONLY, commit to add that path).
#
#   RED  : both emails resolve and are IDENTICAL, AND the record's own
#          introducing commit is at-or-after the CUTOVER commit below --
#          self-approval that happened after independent review was
#          actually available as a mechanism.
#   WARN : either commit is unresolvable (a missing change_ref, or the
#          record file was never committed) -- cannot verify, not a
#          violation; OR the self-approval shape is present but the
#          record PRE-DATES the cutover (grandfathered).
#
# CUTOVER (Amendment-E-style bootstrap, same "never brick a fresh/stale
# checkout" principle grandfather-manifest.json already established for
# review-before-deploy): a 2026-07-29 harness-change-review sweep, run
# under the operator's OWN direct authorization BEFORE review-queue.sh/
# review-runner.sh existed, wrote ~58+ self-authored PASS records as a
# deliberate, known stopgap -- not a silently-smuggled violation. Flagging
# all of them RED the instant this check ships would be a mechanically
# "correct" but operationally false signal (it reads as "58 NEW problems
# just appeared," when nothing changed about those records -- the
# MECHANISM to avoid self-approval simply did not exist yet when they were
# written). `_RRI_CUTOVER_COMMIT` pins the commit that introduced this
# check (RI3, docs/plans/review-independence.md) -- a record whose own
# introducing commit is NOT a descendant of that commit predates the
# mechanism and is grandfathered (WARN, not RED). This is a real design
# decision, documented in docs/plans/review-independence.md's Decisions
# Log, not silently applied.
# ------------------------------------------------------------
# CUTOVER REDESIGN (delta-sweep reviewer 2026-07-30, PROVEN dead arm): the
# original cutover was a pinned COMMIT SHA (b68e27cc...) tested via
# merge-base --is-ancestor. That SHA existed only on the builder worktree
# branch -- the RI3 work was rebased in as different SHAs -- so on master the
# ancestry test could never succeed and every future self-approval would
# read as grandfathered WARN forever: documented enforcement that cannot
# fire (constitution s10 theatre). Cutover is now an ISO-8601 DATE compared
# against the record's own created_at field: rebases and cherry-picks cannot
# invalidate a date, and records are append-only with created_at stamped by
# write-review-record.sh. Overridable for self-test fixtures.
_RRI_CUTOVER_ISO="${REVIEW_REVIEWER_INDEPENDENCE_CUTOVER_ISO:-2026-07-30T09:00:00Z}"

check_review_reviewer_independence() {
  local live_home="$1" repo_root="$2"
  [[ -z "$repo_root" ]] && { _warn "review-reviewer-independence" "repo root unresolved -- skipped"; CHECKS_RUN=$((CHECKS_RUN + 1)); return 0; }

  local records_dir="${repo_root}/docs/reviews/records"
  if [[ ! -d "$records_dir" ]]; then
    _warn "review-reviewer-independence" "no docs/reviews/records/ directory yet -- skipped (pre-bootstrap checkout)"
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi
  command -v jq >/dev/null 2>&1 || { _warn "review-reviewer-independence" "jq unavailable -- skipped"; CHECKS_RUN=$((CHECKS_RUN + 1)); return 0; }
  command -v git >/dev/null 2>&1 || { _warn "review-reviewer-independence" "git unavailable -- skipped"; CHECKS_RUN=$((CHECKS_RUN + 1)); return 0; }

  # QUICK-PATH COST (same review): two full-history git-log walks per PASS
  # record measured ~0.077s x 93 records in --quick (25.7s against its <2s
  # contract), growing linearly forever. The authorship walk now runs ONLY
  # in --full; --quick does the O(1) date classification and emits the
  # single grandfather summary below.
  local _rri_deep=0
  # RRI_FORCE_DEEP=1 is a TEST SEAM (self-test fixtures only — running every
  # fixture through a full multi-minute --full to reach this walk would be
  # absurd); production quick runs never set it.
  [[ "${MODE:-}" == "--full" || "${MODE:-}" == "full" || "${RRI_FORCE_DEEP:-0}" == "1" ]] && _rri_deep=1

  local f base kind verdict reviewed_commit record_relpath reviewed_author
  local record_commit_sha record_author post_cutover created_at
  local _rri_grandfathered=0
  shopt -s nullglob
  for f in "$records_dir"/*.json; do
    [[ -f "$f" ]] || continue
    base="$(basename "$f")"
    [[ "$base" == "index.json" || "$base" == "grandfather-manifest.json" ]] && continue

    kind=$(jq -r '.kind // empty' "$f" 2>/dev/null)
    verdict=$(jq -r '.verdict // empty' "$f" 2>/dev/null)
    [[ "$kind" == "harness-change-review" && "$verdict" == "PASS" ]] || continue

    reviewed_commit=$(jq -r '.change_ref.commit_sha // empty' "$f" 2>/dev/null)
    if [[ -z "$reviewed_commit" ]]; then
      _warn "review-reviewer-independence" "${base}: no change_ref.commit_sha recorded -- cannot verify independence, skipped"
      continue
    fi
    reviewed_author=$(git -C "$repo_root" log -1 --format=%ae "$reviewed_commit" -- 2>/dev/null)
    if [[ -z "$reviewed_author" ]]; then
      _warn "review-reviewer-independence" "${base}: reviewed commit ${reviewed_commit} does not resolve in this checkout -- cannot verify independence, skipped"
      continue
    fi

    created_at=$(jq -r '.created_at // empty' "$f" 2>/dev/null)
    post_cutover=0
    # ISO-8601 strings compare correctly as strings; empty created_at is
    # treated as post-cutover (a record missing its stamp should be LOOKED AT,
    # never silently amnestied).
    if [[ -z "$created_at" || ! "$created_at" < "$_RRI_CUTOVER_ISO" ]]; then
      post_cutover=1
    fi
    if [[ "$post_cutover" -eq 0 ]]; then
      _rri_grandfathered=$((_rri_grandfathered + 1))
      continue
    fi
    # Post-cutover: the expensive authorship walk, --full only.
    if [[ "$_rri_deep" -ne 1 ]]; then
      continue
    fi
    record_relpath="docs/reviews/records/${base}"
    record_commit_sha=$(git -C "$repo_root" log --diff-filter=A --format=%H -- "$record_relpath" 2>/dev/null | tail -n 1)
    record_author=$(git -C "$repo_root" log --diff-filter=A --format=%ae -- "$record_relpath" 2>/dev/null | tail -n 1)
    if [[ -z "$record_author" ]] || [[ -z "$record_commit_sha" ]]; then
      _warn "review-reviewer-independence" "${base}: post-cutover record never committed (or adding commit unresolvable) -- cannot verify independence"
      continue
    fi
    [[ "$reviewed_author" == "$record_author" ]] || continue
    _red "review-reviewer-independence" "${base}: SELF-APPROVAL -- the reviewed commit (${reviewed_commit}) and the commit that added this PASS record were both authored by ${reviewed_author}. A review-record must be committed by a genuinely different principal (docs/decisions/067-review-independence-same-session-pathway.md); route through review-queue.sh + review-runner.sh."
  done
  shopt -u nullglob
  # ONE summary line for the whole grandfathered population (was one WARN per
  # record: 94 WARNs drowning 10 real REDs in a single run).
  if [[ "$_rri_grandfathered" -gt 0 ]]; then
    _warn "review-reviewer-independence" "${_rri_grandfathered} pre-cutover record(s) grandfathered (created_at < ${_RRI_CUTOVER_ISO}) -- not enforced retroactively; post-cutover records are RED on self-approval (authorship walk runs in --full)"
  fi
  CHECKS_RUN=$((CHECKS_RUN + 1))
}

check_selftest_sweep() {
  local live_home="$1"
  # T2 origin guard (agent-efficiency-fixes-2026-07, docs/lessons/2026-07-20-
  # efficiency-recurrence-live-diagnosis.md): this is the CHOKE POINT that
  # fans a single `--full` invocation out into "every live hook's own
  # --self-test" (session-start-digest.sh --self-test among them — the
  # observed 07-20 recursion class). The outer reentry check (before mode
  # dispatch, further down this file) already suppresses automation-spawned/
  # reentrant invocations of the WHOLE script, including --full — this is
  # defense-in-depth so the guard travels with the function itself and does
  # not silently regress if a future refactor calls check_selftest_sweep from
  # anywhere else. Fail-open: missing lib -> sweep proceeds unchanged.
  if command -v hook_reentry_should_suppress >/dev/null 2>&1 && hook_reentry_should_suppress; then
    _warn "selftest-sweep" "reentrant/automation-spawned invocation — skipping the self-test sweep (NL-FINDING-040 guard)"
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi
  local hooks_dir="${live_home}/hooks"
  [[ -d "$hooks_dir" ]] || { _warn "selftest-sweep" "no live hooks directory — nothing to check"; CHECKS_RUN=$((CHECKS_RUN + 1)); return 0; }

  # SCOPE FIX (plan docs/plans/macos-portability-2026-07.md, task M5): this
  # loop used to glob ONLY "$hooks_dir"/*.sh. A top-level glob never matches a
  # subdirectory, so every hooks/lib/*.sh suite — 20 libraries, including the
  # ones that carry the harness's shared primitives (admission-lib,
  # git-command-parse, nl-paths, portable-time, portable-timeout, the
  # observability derivers) — was INVISIBLE to this sweep. Their assertions
  # existed and never ran here. Adding the lib glob makes the doctor's
  # "--full ran every live self-test" claim true instead of nearly true.
  local hook
  for hook in "$hooks_dir"/*.sh "$hooks_dir"/lib/*.sh; do
    [[ -f "$hook" ]] || continue
    grep -q -- '--self-test' "$hook" 2>/dev/null || continue
    local out rc
    # 120s killed passing-but-slow suites on Windows (git-heavy scenarios measured
    # 4-8 min; NL-FINDING-018-era doctor --full run), and 600s killed plan-reviewer
    # (green standalone at 987s, measured 2026-07-03). Default 1500 (~1.5x slowest
    # measured suite), env-overridable; per-hook budgets via manifest = E-wave.
    # NL_SELFTEST_SWEEP=1 marks this child as launched by the sanctioned sweep
    # entrypoint (provenance only — child scripts are not required to gate on
    # it; the reentry guard above is what actually blocks unsanctioned fan-out).
    out="$(HARNESS_SELFTEST=1 NL_SELFTEST_SWEEP=1 nl_run_bounded "${DOCTOR_SELFTEST_TIMEOUT:-1500}" bash "$hook" --self-test </dev/null 2>&1)"
    rc=$?
    # Label with the path relative to hooks/, not the bare basename: now that
    # lib/ is in scope a bare basename could name two different files.
    local label="${hook#$hooks_dir/}"
    if [[ "$rc" -eq 124 ]]; then
      _red "selftest-sweep" "${label} --self-test exceeded the ${DOCTOR_SELFTEST_TIMEOUT:-1500}s bound and was killed"
    elif [[ "$rc" -ne 0 ]]; then
      local last_line
      last_line="$(printf '%s\n' "$out" | tail -n 1)"
      _red "selftest-sweep" "${label} --self-test exited ${rc}: ${last_line}"
    fi
  done
  CHECKS_RUN=$((CHECKS_RUN + 1))
}

# ============================================================
# Check 9: portability-sweep  (--full and --portability only)
# ============================================================
# WHY (plan docs/plans/macos-portability-2026-07.md, task M5)
# ----------------------------------------------------------
# check_selftest_sweep above answers "do the live hooks' self-tests pass?"
# under whatever `bash` happens to be first on PATH. That is NOT the same
# question as "does this harness still work on a stock Mac", and the harness
# has already paid for the difference: authored on Windows (Git-bash, bash
# 5.x, GNU coreutils), it arrived on Apple's bash 3.2.57 + BSD userland with
# 14 of 52 self-test-capable scripts failing. The plan's M1-M4 fixed the
# named GNU-isms. Nothing stopped the next one.
#
# This check is that stop. It runs scripts/portability-sweep.sh against the
# REPO (not the live mirror — the repo is what an author edits, and the live
# mirror lags until install.sh runs) under an explicitly-named interpreter,
# and compares the failing set to a COMMITTED baseline file.
#
# THE RED CONDITION, exactly
# --------------------------
#   RED iff some discovered script's --self-test FAILS or TIMES OUT and that
#   script is NOT listed in docs/portability-baseline.txt.
#
# Consequences of stating it that way, all deliberate:
#   - A newly added script whose self-test FAILS -> RED (it is not in the
#     baseline). This is the authoring-time catch the plan asked for.
#   - A newly added script whose self-test PASSES -> not RED. Growth of the
#     harness is not a regression.
#   - A baseline entry that now passes -> not RED, but the sweep prints
#     "baseline STALE" and this check WARNs, so amnesty cannot quietly
#     outlive the bug it was granted for.
#   - Raising the bar means editing a committed text file, which shows up in
#     a diff and in review. There is no number in this script to nudge.
#
# Absence handling matches every other tolerant doctor predicate: no runner
# in the repo -> WARN and skip (a pre-M5 checkout or a bare self-test
# fixture). Runner present but baseline missing -> RED: a half-installed
# mechanism is worse than none, because it reads as protection.
#
# Recursion: the sweep runs harness-doctor.sh --self-test among its ~163
# suites, and that suite runs `--full` against fixture repos. The sweep
# exports NL_PORTABILITY_SWEEP_ACTIVE=1, and this check no-ops when it sees
# it, so the fan-out is hard-bounded at depth 1.
#
# ENV (all optional; defaults are what --full uses)
#   DOCTOR_PORTABILITY_INTERP        interpreter (default /bin/bash — the
#                                    stock system one is the portability-
#                                    relevant one; on Linux it is GNU bash
#                                    and the check simply reports fewer
#                                    failures, never a false RED)
#   DOCTOR_PORTABILITY_ROOTS         roots to sweep (default the runner's own)
#   DOCTOR_PORTABILITY_PER_TIMEOUT   per-suite bound (default 120)
#   DOCTOR_PORTABILITY_BUDGET        total bound (default 2400)
#   DOCTOR_PORTABILITY_BASELINE      baseline path override
# ============================================================
check_portability_sweep() {
  local live_home="$1" repo_root="$2"

  if [[ "${NL_PORTABILITY_SWEEP_ACTIVE:-0}" == "1" ]]; then
    _warn "portability-sweep" "already running inside a portability sweep — skipping (depth guard)"
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi
  if command -v hook_reentry_should_suppress >/dev/null 2>&1 && hook_reentry_should_suppress; then
    _warn "portability-sweep" "reentrant/automation-spawned invocation — skipping the portability sweep (NL-FINDING-040 guard)"
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi

  if [[ -z "${repo_root:-}" ]]; then
    _warn "portability-sweep" "no repo root resolved — the portability sweep needs the repo (it checks what an author edits, not the live mirror)"
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi

  local sweep="${repo_root}/adapters/claude-code/scripts/portability-sweep.sh"
  if [[ ! -f "$sweep" ]]; then
    _warn "portability-sweep" "scripts/portability-sweep.sh not present in ${repo_root} — mechanism not installed on this checkout/fixture"
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi

  local baseline="${DOCTOR_PORTABILITY_BASELINE:-${repo_root}/docs/portability-baseline.txt}"
  if [[ ! -f "$baseline" ]]; then
    _red "portability-sweep" "scripts/portability-sweep.sh exists but its baseline is missing (${baseline}) — the regression check cannot run, so the 'portability is protected' claim is currently false; regenerate with: bash adapters/claude-code/scripts/portability-sweep.sh --write-baseline docs/portability-baseline.txt"
    CHECKS_RUN=$((CHECKS_RUN + 1))
    return 0
  fi

  local interp="${DOCTOR_PORTABILITY_INTERP:-/bin/bash}"
  if [[ ! -x "$interp" ]]; then
    local fallback
    fallback="$(command -v bash 2>/dev/null)"
    if [[ -z "$fallback" ]]; then
      _warn "portability-sweep" "no usable interpreter (${interp} not executable, no bash on PATH) — skipped"
      CHECKS_RUN=$((CHECKS_RUN + 1))
      return 0
    fi
    _warn "portability-sweep" "${interp} is not executable here — falling back to ${fallback}; the sweep's interpreter claim is only as portable as that binary"
    interp="$fallback"
  fi

  local budget="${DOCTOR_PORTABILITY_BUDGET:-2400}"
  local per="${DOCTOR_PORTABILITY_PER_TIMEOUT:-120}"
  local out rc
  # The runner bounds itself; the outer bound is belt-and-braces against a
  # runner that wedges before its own budget logic engages.
  local roots_arg=()
  [[ -n "${DOCTOR_PORTABILITY_ROOTS:-}" ]] && roots_arg=(--roots "${DOCTOR_PORTABILITY_ROOTS}")
  out="$(nl_run_bounded $(( budget + 120 )) "$interp" "$sweep" \
           --repo-root "$repo_root" \
           --interpreter "$interp" \
           --baseline "$baseline" \
           --per-script-timeout "$per" \
           --total-budget "$budget" \
           ${roots_arg[@]+"${roots_arg[@]}"} </dev/null 2>&1)"
  rc=$?

  if [[ "$rc" -eq 124 ]]; then
    _red "portability-sweep" "the sweep itself exceeded $(( budget + 120 ))s and was killed — no portability signal from this run"
  elif [[ "$rc" -eq 1 ]]; then
    # Emit one RED per new failure so the operator sees WHAT regressed, not
    # just that something did.
    # Match ONLY the runner's dedicated REGRESSION marker.
    #
    # The first version of this loop matched '  FAIL  '* — which also matches
    # every row of the sweep's own report body (`  FAIL    hooks/x.sh  ...`),
    # so one genuine regression was reported as 54 REDs, 53 of them scripts
    # already in the baseline, with the real one last. Caught by running the
    # end-to-end injected-regression demo; a code read had missed it. The
    # marker is emitted by portability-sweep.sh's baseline-comparison section
    # and appears nowhere else in its output.
    local line emitted=0
    while IFS= read -r line; do
      case "$line" in
        '  REGRESSION '*)
          _red "portability-sweep" "NEW self-test failure under ${interp} (not in ${baseline##*/}): $(printf '%s' "$line" | sed -e 's/^  REGRESSION //')"
          emitted=$((emitted + 1))
          ;;
      esac
    done <<< "$out"
    if [[ "$emitted" -eq 0 ]]; then
      _red "portability-sweep" "the sweep reported new failures under ${interp} but no line could be parsed — full output: $(printf '%s' "$out" | tail -n 20 | tr '\n' ' ')"
    fi
  elif [[ "$rc" -ne 0 ]]; then
    _red "portability-sweep" "portability-sweep.sh exited ${rc} (setup error, not a test result): $(printf '%s\n' "$out" | grep -v '^[[:space:]]*$' | tail -n 3 | tr '\n' ' ')"
  fi

  # Partial coverage and stale amnesty are WARNs — real information, but not
  # a regression claim.
  local skipped
  skipped="$(printf '%s\n' "$out" | sed -n 's/.*skip=\([0-9][0-9]*\).*/\1/p' | tail -n 1)"
  if [[ -n "$skipped" && "$skipped" != "0" ]]; then
    _warn "portability-sweep" "${skipped} suite(s) never ran — the ${budget}s total budget was exhausted, so this run's coverage is partial (raise DOCTOR_PORTABILITY_BUDGET or fix the slow suites)"
  fi
  if printf '%s' "$out" | grep -q 'baseline STALE'; then
    _warn "portability-sweep" "the baseline lists script(s) that now PASS — remove them so the amnesty does not outlive the bug: $(printf '%s\n' "$out" | sed -n '/baseline STALE/,/^$/p' | grep '^  [a-z]' | tr '\n' ' ')"
  fi

  CHECKS_RUN=$((CHECKS_RUN + 1))
}

# ------------------------------------------------------------
# run_quick_checks — checks 1-7 against the given live_home/repo_root
# ------------------------------------------------------------
run_quick_checks() {
  local live_home="$1" repo_root="$2"
  check_wiring_resolves "$live_home" "$repo_root"
  check_lib_deps "$live_home"
  check_legacy_paths "$live_home"
  check_template_live_drift "$live_home" "$repo_root"
  check_claim_honesty "$live_home" "$repo_root"
  check_byte_budget "$live_home"
  check_manifest "$live_home" "$repo_root"
  check_manifest_freshness "$live_home" "$repo_root"
  check_wave_f_f2_docs "$live_home" "$repo_root"
  check_wave_e_surfaces "$live_home" "$repo_root"
  check_heartbeat_task "$live_home" "$repo_root"
  check_untracked_dirt_ignore_rule "$live_home" "$repo_root"
  # NL Observability Program Wave O, task O.6 (specs-o §O.6) — pipeline
  # health predicates, spliced batch 2.
  check_obs_writers_firing "$live_home" "$repo_root"
  check_obs_heartbeats_fresh "$live_home" "$repo_root"
  check_obs_scheduled_tasks "$live_home" "$repo_root"
  check_obs_consumer_map "$live_home" "$repo_root"
  check_obs_cockpit_fresh "$live_home" "$repo_root"
  check_obs_ask_capture_completeness "$live_home" "$repo_root"
  check_needs_you_headers "$live_home" "$repo_root"
  check_pin_f_waiver_purpose_clauses "$live_home" "$repo_root"
  check_limit_resume_watchdog "$live_home"
  check_line_endings "$live_home" "$repo_root"
  check_budget_chains "$live_home" "$repo_root"
  check_budget_blocking_gates "$live_home" "$repo_root"
  check_budget_always_loaded "$live_home" "$repo_root"
  check_budget_active_plans "$live_home" "$repo_root"
  check_budget_worktrees_branches "$live_home" "$repo_root"
  check_orphaned_worktree_work "$live_home" "$repo_root"
  check_new_gate_evidence_bar "$live_home" "$repo_root"
  check_deterministic_process_proof "$live_home" "$repo_root"
  check_master_drift_autocorrect "$live_home" "$repo_root"
  check_selftest_exclusions_wiring "$repo_root"
  check_model_pins "$live_home" "$repo_root"
  check_review_surface_cross_check "$live_home" "$repo_root"
  check_review_index_consistency "$live_home" "$repo_root"
  check_review_grandfather_integrity "$live_home" "$repo_root"
  check_review_reviewer_independence "$live_home" "$repo_root"
  # harness-execution-redesign-2026-08 Task 1 (Stage 0a, invariants 1/2)
  check_schedule_manifest_cadence "$live_home" "$repo_root"
  check_budget_bash_hooks "$live_home" "$repo_root"
  # harness-execution-redesign-2026-08 Task 3 (Stage 1, invariant 9)
  check_maintenance_both_substrates_alive "$live_home" "$repo_root"
  # gated-pipeline-master-2026-08 T24 (REQ-C6/arch-M3)
  check_stage2_admission_open "$live_home" "$repo_root"
}

# ============================================================
# --self-test handler
# ============================================================
if [[ "${1:-}" == "--self-test" ]]; then
  SELF_TEST_HOOK="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)/$(basename "${BASH_SOURCE[0]}")"
  if [[ ! -f "$SELF_TEST_HOOK" ]]; then
    echo "self-test: cannot resolve own path" >&2
    exit 2
  fi

  PASSED=0
  FAILED=0
  TMPROOT=$(mktemp -d 2>/dev/null || mktemp -d -t harness-doctor)
  if [[ -z "$TMPROOT" ]] || [[ ! -d "$TMPROOT" ]]; then
    echo "self-test: cannot create temp directory" >&2
    exit 2
  fi
  trap 'rm -rf "$TMPROOT"' EXIT

  # Helper: build a minimal fake "live home" + "repo root" pair and return
  # the exit code of a --quick invocation against them.
  #   $1 = scenario label
  #   $2 = "live" | "repo" | "both"  -> which fixture builder(s) to call
  # The scenario functions below populate $LIVE and $REPO directly.
  _scenario_dir() {
    local label="$1"
    local dir="$TMPROOT/$label"
    mkdir -p "$dir/live/hooks" "$dir/live/rules" "$dir/live/scripts" "$dir/live/local"
    mkdir -p "$dir/repo/adapters/claude-code/hooks" "$dir/repo/adapters/claude-code/scripts" \
             "$dir/repo/adapters/claude-code/rules" "$dir/repo/adapters/claude-code/schemas"
    # E.6 fixture stamp (NL-FINDING-039): check_wave_e_e6_needs_you REDs when
    # the repo-side needs-you.sh is missing / non-executable / lacking a
    # --self-test entrypoint. The NL-FINDING-035 round-2 fix added that
    # predicate without stamping the fixtures, breaking every rc-0 scenario
    # in this suite. Every fixture repo gets a conforming stub.
    printf '#!/bin/bash\n# fixture stub; the real script ships via install.sh\n[[ "${1:-}" == "--self-test" ]] && exit 0\nexit 0\n' \
      > "$dir/repo/adapters/claude-code/scripts/needs-you.sh"
    chmod +x "$dir/repo/adapters/claude-code/scripts/needs-you.sh" 2>/dev/null
    printf '%s\n' "$dir"
  }

  # Copies the real manifest-check.sh + manifest schema into a fixture repo
  # so the doctor's check 7 (manifest-check invocation) can run there.
  # Returns 1 (caller should SKIP manifest scenarios) when the real tooling
  # is not present next to this doctor (e.g. a partial install).
  _copy_manifest_tooling() {
    local dir="$1"
    local checker_src="$SCRIPT_DIR/../scripts/manifest-check.sh"
    local schema_src="$SCRIPT_DIR/../schemas/manifest.schema.json"
    [[ -f "$checker_src" && -f "$schema_src" ]] || return 1
    cp "$checker_src" "$dir/repo/adapters/claude-code/scripts/manifest-check.sh"
    cp "$schema_src" "$dir/repo/adapters/claude-code/schemas/manifest.schema.json"
    return 0
  }

  # Copies the real review-record-gate-lib.sh + write-review-record.sh into
  # a fixture repo so check_review_surface_cross_check / check_review_index_
  # consistency can exercise the REAL surface glob + rebuild logic rather
  # than a re-implemented stub. Returns 1 (caller should SKIP) when the real
  # files are not present next to this doctor (e.g. a partial install).
  _copy_review_gate_tooling() {
    local dir="$1"
    local lib_src="$SCRIPT_DIR/lib/review-record-gate-lib.sh"
    local writer_src="$SCRIPT_DIR/../scripts/write-review-record.sh"
    [[ -f "$lib_src" && -f "$writer_src" ]] || return 1
    mkdir -p "$dir/repo/adapters/claude-code/hooks/lib" "$dir/repo/adapters/claude-code/scripts"
    cp "$lib_src" "$dir/repo/adapters/claude-code/hooks/lib/review-record-gate-lib.sh"
    cp "$writer_src" "$dir/repo/adapters/claude-code/scripts/write-review-record.sh"
    return 0
  }

  # Copies the real worktree-hygiene-sweep.sh (+ the session-heartbeat-lib.sh
  # it sources for the liveness join) into a fixture repo so
  # check_orphaned_worktree_work's scenarios can invoke the REAL shared
  # detector — same non-duplication discipline as _copy_manifest_tooling
  # above. Returns 1 (caller should SKIP its orphaned-worktree-work
  # scenarios) when the real tooling is not present next to this doctor
  # (e.g. a partial install).
  _copy_sweeper_tooling() {
    local dir="$1"
    local sweeper_src="$SCRIPT_DIR/../scripts/worktree-hygiene-sweep.sh"
    local hb_lib_src="$SCRIPT_DIR/lib/session-heartbeat-lib.sh"
    [[ -f "$sweeper_src" ]] || return 1
    mkdir -p "$dir/repo/adapters/claude-code/scripts" "$dir/repo/adapters/claude-code/hooks/lib"
    cp "$sweeper_src" "$dir/repo/adapters/claude-code/scripts/worktree-hygiene-sweep.sh"
    chmod +x "$dir/repo/adapters/claude-code/scripts/worktree-hygiene-sweep.sh" 2>/dev/null
    [[ -f "$hb_lib_src" ]] && cp "$hb_lib_src" "$dir/repo/adapters/claude-code/hooks/lib/session-heartbeat-lib.sh"
    return 0
  }

  _write_settings() {
    local path="$1"; shift
    local body='{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":['
    local first=1
    local name
    for name in "$@"; do
      if [[ "$first" -eq 0 ]]; then body="${body},"; fi
      first=0
      body="${body}{\"type\":\"command\",\"command\":\"bash ~/.claude/hooks/${name}\"}"
    done
    body="${body}]}]}}"
    printf '%s' "$body" > "$path"
  }

  # Historical helper (pre-C.1 the claim-honesty check used an embedded
  # checklist that fixtures had to satisfy). Check 5 is manifest-driven now:
  # fixtures WITHOUT a manifest.json take the graceful-WARN path on both
  # check 5 and check 7, so unrelated scenarios need no stamping. Kept as a
  # no-op to keep the scenario bodies' shape stable.
  _stamp_claim_honesty_green() {
    :
  }

  _run_quick() {
    local dir="$1"
    HARNESS_DOCTOR_HOME="$dir/live" NL_REPO_ROOT="$dir/repo" bash "$SELF_TEST_HOOK" --quick "$dir/repo" 2>&1
  }

  # ------------------------------------------------------------
  # NODE-MASKED EXECUTION (harness-reviewer C1, 2026-07-30).
  #
  # Four checks in this file are dual-path: node preferred, jq fallback
  # (extract_manifest_gates -> claim-honesty; _count_chain_entries ->
  # budget-chains; new-gate-evidence-bar; deterministic-process-proof). Every
  # one of them ran ONLY its node branch in the self-test, because the machine
  # that runs the suite has node. The jq branches were therefore asserted to
  # match by INSPECTION -- and one of them did not: deterministic-process-
  # proof's jq expression indexed the grandfather ARRAY with `.id`, so jq
  # errored, `2>/dev/null` swallowed it, and the check was a silent no-op on
  # every node-less machine. The comment claiming "one generator pattern, not
  # two that could drift" was the only thing holding the two in sync.
  #
  # This helper makes the fallback EXECUTE: a PATH containing every tool the
  # doctor needs EXCEPT node. Built once, reused by every parity scenario.
  # ------------------------------------------------------------
  _NONODE_DIR=""
  _nonode_path() {
    if [[ -z "$_NONODE_DIR" ]]; then
      _NONODE_DIR="$(mktemp -d 2>/dev/null)" || return 1
      local _t _p
      for _t in jq git grep sed awk bash sh find sort uniq head tail cat wc tr \
                date mkdir rm cp mv chmod ls dirname basename realpath stat env \
                xargs comm diff touch tee cut expr mktemp readlink od printf \
                which id whoami uname; do
        _p="$(command -v "$_t" 2>/dev/null)"
        [[ -n "$_p" ]] && ln -sf "$_p" "$_NONODE_DIR/$_t" 2>/dev/null
      done
    fi
    printf '%s' "$_NONODE_DIR"
  }

  _run_quick_nonode() {
    local dir="$1" shim
    shim="$(_nonode_path)" || { printf 'NONODE-SHIM-UNAVAILABLE'; return 0; }
    HARNESS_DOCTOR_HOME="$dir/live" NL_REPO_ROOT="$dir/repo" PATH="$shim" \
      bash "$SELF_TEST_HOOK" --quick "$dir/repo" 2>&1
  }

  # _assert_node_jq_parity <label> <scenario-dir> <check-id> <want-nonempty:0|1>
  # Runs the SAME fixture through both branches and requires byte-identical
  # output for that check. want_nonempty=1 additionally requires the jq branch
  # to have produced SOMETHING -- without it, two silently-broken branches
  # would agree on emptiness and the parity assertion would pass vacuously,
  # which is exactly the failure being regression-tested.
  #
  # THE TWO FAILURE MODES ARE DISTINCT, AND THE ORDER BELOW DECIDES WHICH ONE
  # YOU SEE (recorded 2026-07-30 because a commit message got this wrong and
  # nothing in the tree contradicted it -- harness-reviewer MINOR):
  #   "branches DIVERGE"  -- the two branches BOTH reported, but differently.
  #                          This is what a reverted grandfather cutover_ref
  #                          binding produces: the check still emits a verdict,
  #                          just the wrong one.
  #   "produced NOTHING"  -- the jq branch emitted no line at all. This needs
  #                          the check to go SILENT, which for the fail-open
  #                          arms means reverting the loud-WARN too, not only
  #                          the binding.
  # The DIVERGE test runs first and want_nonempty only OVERWRITES `why` when
  # jq_out is genuinely empty, so a non-empty-but-different jq branch can never
  # report "produced NOTHING". Do not quote one failure mode as evidence for a
  # mutation that actually triggers the other.
  _assert_node_jq_parity() {
    local label="$1" dir="$2" check_id="$3" want_nonempty="${4:-0}"
    local node_out jq_out
    node_out="$(_run_quick "$dir" | grep -- "$check_id" | LC_ALL=C sort)"
    jq_out="$(_run_quick_nonode "$dir" | grep -- "$check_id" | LC_ALL=C sort)"
    local ok=1 why=""
    if [[ "$node_out" != "$jq_out" ]]; then ok=0; why="branches DIVERGE"; fi
    if [[ "$want_nonempty" == "1" && -z "$jq_out" ]]; then
      ok=0; why="jq branch produced NOTHING on a fixture that must report (silent no-op)"
    fi
    if [[ "$ok" -eq 1 ]]; then
      echo "self-test (${label}): PASS" >&2
      PASSED=$((PASSED + 1))
    else
      echo "self-test (${label}): FAIL (${why}) for check '${check_id}'" >&2
      echo "--- node branch ---" >&2; printf '%s\n' "$node_out" >&2
      echo "--- jq branch (node masked) ---" >&2; printf '%s\n' "$jq_out" >&2
      FAILED=$((FAILED + 1))
    fi
  }

  _assert() {
    local label="$1" want_rc="$2" got_rc="$3" grep_pattern="${4:-}" output="${5:-}"
    local ok=1
    if [[ "$got_rc" != "$want_rc" ]]; then ok=0; fi
    if [[ -n "$grep_pattern" ]] && ! printf '%s' "$output" | grep -q "$grep_pattern"; then ok=0; fi
    if [[ "$ok" -eq 1 ]]; then
      echo "self-test (${label}): PASS" >&2
      PASSED=$((PASSED + 1))
    else
      echo "self-test (${label}): FAIL (rc=${got_rc}, expected ${want_rc}, pattern='${grep_pattern}')" >&2
      echo "--- output ---" >&2
      printf '%s\n' "$output" >&2
      FAILED=$((FAILED + 1))
    fi
  }

  # ---- Check 1 (wiring-resolves): RED fixture — settings references a
  # missing hook ----
  D=$(_scenario_dir c1-red)
  _stamp_claim_honesty_green "$D"
  cat > "$D/live/settings.json" <<EOF
{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"bash ~/.claude/hooks/does-not-exist.sh"}]}]}}
EOF
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  OUT="$(_run_quick "$D")"; RC=$?
  _assert "1-wiring-resolves-red" 1 "$RC" "RED wiring-resolves" "$OUT"

  # ---- Check 1: GREEN fixture — the referenced hook exists ----
  D=$(_scenario_dir c1-green)
  _stamp_claim_honesty_green "$D"
  echo '#!/bin/bash' > "$D/live/hooks/present.sh"
  chmod +x "$D/live/hooks/present.sh"
  cat > "$D/live/settings.json" <<EOF
{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"bash ~/.claude/hooks/present.sh"}]}]}}
EOF
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  cp "$D/live/hooks/present.sh" "$D/repo/adapters/claude-code/hooks/present.sh"
  OUT="$(_run_quick "$D")"; RC=$?
  _assert "1-wiring-resolves-green" 0 "$RC" "" "$OUT"

  # ---- Check 2 (lib-deps): RED fixture — hook sources a missing lib file ----
  D=$(_scenario_dir c2-red)
  _stamp_claim_honesty_green "$D"
  cat > "$D/live/hooks/uses-lib.sh" <<'EOF'
#!/bin/bash
source "$(dirname "${BASH_SOURCE[0]}")/lib/missing-lib.sh"
EOF
  chmod +x "$D/live/hooks/uses-lib.sh"
  _write_settings "$D/live/settings.json" "uses-lib.sh"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  cp "$D/live/hooks/uses-lib.sh" "$D/repo/adapters/claude-code/hooks/uses-lib.sh"
  OUT="$(_run_quick "$D")"; RC=$?
  _assert "2-lib-deps-red" 1 "$RC" "RED lib-deps" "$OUT"

  # ---- Check 2: GREEN fixture — the sourced lib file exists ----
  D=$(_scenario_dir c2-green)
  _stamp_claim_honesty_green "$D"
  mkdir -p "$D/live/hooks/lib"
  echo '#!/bin/bash' > "$D/live/hooks/lib/present-lib.sh"
  cat > "$D/live/hooks/uses-lib-ok.sh" <<'EOF'
#!/bin/bash
source "$(dirname "${BASH_SOURCE[0]}")/lib/present-lib.sh"
EOF
  chmod +x "$D/live/hooks/uses-lib-ok.sh"
  _write_settings "$D/live/settings.json" "uses-lib-ok.sh"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  cp "$D/live/hooks/uses-lib-ok.sh" "$D/repo/adapters/claude-code/hooks/uses-lib-ok.sh"
  OUT="$(_run_quick "$D")"; RC=$?
  _assert "2-lib-deps-green" 0 "$RC" "" "$OUT"

  # ---- Check 3 (legacy-paths): RED fixture — a hook references the
  # retired path family ----
  D=$(_scenario_dir c3-red)
  _stamp_claim_honesty_green "$D"
  {
    printf '%s\n' '#!/bin/bash'
    printf 'SRC="$HOME/claude-projects/neural%s"\n' '-lace/adapters/claude-code'
  } > "$D/live/hooks/legacy.sh"
  chmod +x "$D/live/hooks/legacy.sh"
  _write_settings "$D/live/settings.json" "legacy.sh"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  cp "$D/live/hooks/legacy.sh" "$D/repo/adapters/claude-code/hooks/legacy.sh"
  OUT="$(_run_quick "$D")"; RC=$?
  _assert "3-legacy-paths-red" 1 "$RC" "RED legacy-paths" "$OUT"

  # ---- Check 3: GREEN fixture — no legacy references ----
  D=$(_scenario_dir c3-green)
  _stamp_claim_honesty_green "$D"
  cat > "$D/live/hooks/modern.sh" <<'EOF'
#!/bin/bash
echo "clean"
EOF
  chmod +x "$D/live/hooks/modern.sh"
  _write_settings "$D/live/settings.json" "modern.sh"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  cp "$D/live/hooks/modern.sh" "$D/repo/adapters/claude-code/hooks/modern.sh"
  OUT="$(_run_quick "$D")"; RC=$?
  _assert "3-legacy-paths-green" 0 "$RC" "" "$OUT"

  # ---- Check 4 (template-live-drift): RED fixture — live and template
  # wire different hook sets ----
  D=$(_scenario_dir c4-red)
  _stamp_claim_honesty_green "$D"
  echo '#!/bin/bash' > "$D/live/hooks/only-live.sh"
  echo '#!/bin/bash' > "$D/repo/adapters/claude-code/hooks/only-template.sh"
  _write_settings "$D/live/settings.json" "only-live.sh"
  _write_settings "$D/repo/adapters/claude-code/settings.json.template" "only-template.sh"
  OUT="$(_run_quick "$D")"; RC=$?
  _assert "4-template-live-drift-red" 1 "$RC" "RED template-live-drift" "$OUT"

  # ---- Check 4: GREEN fixture — identical wired sets ----
  D=$(_scenario_dir c4-green)
  _stamp_claim_honesty_green "$D"
  echo '#!/bin/bash' > "$D/live/hooks/shared.sh"
  echo '#!/bin/bash' > "$D/repo/adapters/claude-code/hooks/shared.sh"
  _write_settings "$D/live/settings.json" "shared.sh"
  _write_settings "$D/repo/adapters/claude-code/settings.json.template" "shared.sh"
  OUT="$(_run_quick "$D")"; RC=$?
  _assert "4-template-live-drift-green" 0 "$RC" "" "$OUT"

  # Manifest fixture writer for the check-5/check-7 scenarios.
  #   $1 = fixture dir, $2 = variant: "green" | "no-honest" | "ghost-hook"
  # green      : wired gate (hook on disk+template+live) + pending gate with
  #              honest_status — passes both claim-honesty and manifest-check.
  # no-honest  : the pending gate LACKS honest_status -> claim-honesty RED.
  # ghost-hook : manifest references a hook absent from disk (honest_status
  #              present, so claim-honesty passes) -> manifest-check RED.
  _write_manifest_fixture() {
    local dir="$1" variant="$2"
    local pending_hook="pending-gate.sh" honest_line
    printf '#!/bin/bash\nexit 0\n' > "$dir/repo/adapters/claude-code/hooks/wired-gate.sh"
    printf '#!/bin/bash\nexit 0\n' > "$dir/live/hooks/wired-gate.sh"
    if [[ "$variant" == "ghost-hook" ]]; then
      pending_hook="ghost.sh"   # deliberately NOT created on disk
    else
      printf '#!/bin/bash\nexit 0\n' > "$dir/repo/adapters/claude-code/hooks/pending-gate.sh"
    fi
    if [[ "$variant" == "no-honest" ]]; then
      honest_line=""
    else
      honest_line='      "honest_status": "invoked via a chain script; not directly wired",'
    fi
    cat > "$dir/repo/adapters/claude-code/manifest.json" <<MANIFEST_EOF
{
  "schema_version": 1,
  "entries": [
    {
      "id": "wired-gate",
      "kind": "gate",
      "doctrine_file": null,
      "hooks": ["wired-gate.sh"],
      "events": ["Stop"],
      "wired_template": true,
      "selftest": false,
      "jit_triggers": { "paths": [], "keywords": [] },
      "blocking": true,
      "honesty_rationale": "fixture: waiver-parity satisfied for this manifest-check/claim-honesty fixture",
      "budget_class": "stop",
      "added_after": "2026-04"
    },
    {
      "id": "pending-gate",
      "kind": "gate",
      "doctrine_file": null,
      "hooks": ["${pending_hook}"],
      "events": ["precommit"],
      "wired_template": false,
      "selftest": false,
      "jit_triggers": { "paths": [], "keywords": [] },
      "blocking": true,
      "waiver_path": "fixture-waiver-*.txt",
${honest_line}
      "budget_class": "none",
      "added_after": "2026-04"
    }
  ]
}
MANIFEST_EOF
    # no-honest variant leaves an empty line where honest_status was — strip
    # it so the JSON stays parseable.
    if [[ "$variant" == "no-honest" ]]; then
      grep -v '^$' "$dir/repo/adapters/claude-code/manifest.json" > "$dir/repo/adapters/claude-code/manifest.json.tmp" \
        && mv "$dir/repo/adapters/claude-code/manifest.json.tmp" "$dir/repo/adapters/claude-code/manifest.json"
    fi
    _write_settings "$dir/live/settings.json" "wired-gate.sh"
    cp "$dir/live/settings.json" "$dir/repo/adapters/claude-code/settings.json.template"
  }

  # ---- Check 5 (claim-honesty, manifest-driven): RED fixture — a manifest
  # gate has wired_template false and no honest_status ----
  D=$(_scenario_dir c5-red)
  if _copy_manifest_tooling "$D"; then :; fi
  _write_manifest_fixture "$D" no-honest
  OUT="$(_run_quick "$D")"; RC=$?
  _assert "5-claim-honesty-red" 1 "$RC" "RED claim-honesty" "$OUT"

  # ---- Check 5: GREEN fixture — every manifest gate is either live-wired
  # or carries an honest_status ----
  D=$(_scenario_dir c5-green)
  if _copy_manifest_tooling "$D"; then :; fi
  _write_manifest_fixture "$D" green
  OUT="$(_run_quick "$D")"; RC=$?
  _assert "5-claim-honesty-green" 0 "$RC" "" "$OUT"

  # ---- Check 7 (manifest-check invocation): RED fixture — the manifest
  # references a hook that does not exist on disk (claim-honesty itself is
  # satisfied via honest_status, so the RED must come from manifest-check) ----
  D=$(_scenario_dir c7m-red)
  if _copy_manifest_tooling "$D"; then
    _write_manifest_fixture "$D" ghost-hook
    OUT="$(_run_quick "$D")"; RC=$?
    _assert "7-manifest-check-red" 1 "$RC" "RED manifest-check" "$OUT"
  else
    echo "self-test (7-manifest-check-red): SKIP — manifest-check.sh not present next to this doctor" >&2
    PASSED=$((PASSED + 1))
  fi

  # ---- Check 7: GREEN fixture — a fully consistent manifest passes the
  # manifest-check invocation ----
  D=$(_scenario_dir c7m-green)
  if _copy_manifest_tooling "$D"; then
    _write_manifest_fixture "$D" green
    OUT="$(_run_quick "$D")"; RC=$?
    _assert "7-manifest-check-green" 0 "$RC" "" "$OUT"
  else
    echo "self-test (7-manifest-check-green): SKIP — manifest-check.sh not present next to this doctor" >&2
    PASSED=$((PASSED + 1))
  fi

  # ---- Check 6 (byte-budget): RED fixture — strict budget exceeded ----
  D=$(_scenario_dir c6-red)
  _stamp_claim_honesty_green "$D"
  head -c 200 /dev/zero | tr '\0' 'x' > "$D/live/rules/big.md"
  echo "100" > "$D/live/local/doctor-budget"
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  OUT="$(_run_quick "$D")"; RC=$?
  _assert "6-byte-budget-red" 1 "$RC" "RED byte-budget" "$OUT"

  # ---- Check 6: GREEN fixture — under budget ----
  D=$(_scenario_dir c6-green)
  _stamp_claim_honesty_green "$D"
  echo "small" > "$D/live/rules/small.md"
  echo "1000000" > "$D/live/local/doctor-budget"
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  OUT="$(_run_quick "$D")"; RC=$?
  _assert "6-byte-budget-green" 0 "$RC" "" "$OUT"

  # ---- Check: manifest-freshness (NL-FINDING-017, item 4). RED fixture —
  # live and repo manifest.json hash mismatch ----
  D=$(_scenario_dir mf-red)
  _stamp_claim_honesty_green "$D"
  echo '{"schema_version":1,"entries":[]}' > "$D/live/manifest.json"
  echo '{"schema_version":1,"entries":[],"drift":"repo-changed"}' > "$D/repo/adapters/claude-code/manifest.json"
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  OUT="$(_run_quick "$D")"; RC=$?
  _assert "manifest-freshness-red" 1 "$RC" "RED manifest-freshness" "$OUT"

  # ---- Check: manifest-freshness GREEN fixture — identical hashes ----
  D=$(_scenario_dir mf-green)
  _stamp_claim_honesty_green "$D"
  echo '{"schema_version":1,"entries":[]}' > "$D/live/manifest.json"
  cp "$D/live/manifest.json" "$D/repo/adapters/claude-code/manifest.json"
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  OUT="$(_run_quick "$D")"; RC=$?
  _assert "manifest-freshness-green" 0 "$RC" "" "$OUT"

  # ---- Check: wave-f-f2-docs Predicate 1 (harness-architecture.md drift).
  # RED fixture — a real gen-architecture-doc.sh copy + a hand-edited
  # committed doc that no longer matches a fresh regen from manifest.json. ----
  D=$(_scenario_dir f2p1-red)
  _stamp_claim_honesty_green "$D"
  mkdir -p "$D/repo/docs"
  cp "$SCRIPT_DIR/../scripts/gen-architecture-doc.sh" "$D/repo/adapters/claude-code/scripts/gen-architecture-doc.sh"
  cat > "$D/repo/adapters/claude-code/manifest.json" <<'F2MANIFEST_EOF'
{"schema_version":1,"entries":[{"id":"a","kind":"gate","hooks":["a.sh"],"events":["precommit"],"blocking":true,"selftest":true,"wired_template":true,"honest_status":"x","budget_class":"none","added_after":"2026-04"}]}
F2MANIFEST_EOF
  ( cd "$D/repo" && bash adapters/claude-code/scripts/gen-architecture-doc.sh >/dev/null 2>&1 )
  echo "hand-edited drift line" >> "$D/repo/docs/harness-architecture.md"
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  OUT="$(_run_quick "$D")"; RC=$?
  _assert "wave-f-f2-docs-predicate1-red" 1 "$RC" "RED wave-f-f2-docs.*harness-architecture" "$OUT"

  # ---- Check: wave-f-f2-docs Predicate 1 GREEN fixture — committed doc
  # freshly regenerated, byte-identical to a re-run ----
  D=$(_scenario_dir f2p1-green)
  _stamp_claim_honesty_green "$D"
  mkdir -p "$D/repo/docs"
  cp "$SCRIPT_DIR/../scripts/gen-architecture-doc.sh" "$D/repo/adapters/claude-code/scripts/gen-architecture-doc.sh"
  cat > "$D/repo/adapters/claude-code/manifest.json" <<'F2MANIFEST_EOF'
{"schema_version":1,"entries":[{"id":"a","kind":"gate","hooks":["a.sh"],"events":["precommit"],"blocking":true,"selftest":true,"wired_template":true,"honest_status":"x","budget_class":"none","added_after":"2026-04"}]}
F2MANIFEST_EOF
  ( cd "$D/repo" && bash adapters/claude-code/scripts/gen-architecture-doc.sh >/dev/null 2>&1 )
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  OUT="$(_run_quick "$D")"; RC=$?
  _assert "wave-f-f2-docs-predicate1-green" 0 "$RC" "" "$OUT"

  # ---- Check: wave-f-f2-docs Predicate 2 (README freshness anchors). RED
  # fixture — one of the five surfaces has a 100-day-old anchor, the rest
  # fresh (today). Uses backdated `date` arithmetic, not a hardcoded
  # calendar date, so this fixture never goes stale itself. ----
  D=$(_scenario_dir f2p2-red)
  _stamp_claim_honesty_green "$D"
  _f2_today="$(date +%Y-%m-%d)"
  _f2_stale_date="$(date -d '-100 days' +%Y-%m-%d 2>/dev/null || date -j -v-100d +%Y-%m-%d 2>/dev/null)"
  mkdir -p "$D/repo/adapters/claude-code/attic" "$D/repo/evals" "$D/repo/neural-lace/workstreams-ui"
  printf '# Repo\n<!-- last-verified: %s (doctor-checked) -->\n' "$_f2_today" > "$D/repo/README.md"
  printf '# Adapter\n<!-- last-verified: %s (doctor-checked) -->\n' "$_f2_today" > "$D/repo/adapters/claude-code/README.md"
  printf '# Attic\n<!-- last-verified: %s (doctor-checked) -->\n' "$_f2_stale_date" > "$D/repo/adapters/claude-code/attic/README.md"
  printf '# Evals\n<!-- last-verified: %s (doctor-checked) -->\n' "$_f2_today" > "$D/repo/evals/README.md"
  printf '# UI\n<!-- last-verified: %s (doctor-checked) -->\n' "$_f2_today" > "$D/repo/neural-lace/workstreams-ui/README.md"
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  OUT="$(_run_quick "$D")"; RC=$?
  _assert "wave-f-f2-docs-predicate2-stale-red" 1 "$RC" "RED wave-f-f2-docs.*STALE.*attic/README.md" "$OUT"

  # ---- Check: wave-f-f2-docs Predicate 2 RED fixture — one surface
  # missing its anchor entirely ----
  D=$(_scenario_dir f2p2-noanchor-red)
  _stamp_claim_honesty_green "$D"
  _f2_today2="$(date +%Y-%m-%d)"
  mkdir -p "$D/repo/adapters/claude-code/attic" "$D/repo/evals" "$D/repo/neural-lace/workstreams-ui"
  printf '# Repo\n<!-- last-verified: %s (doctor-checked) -->\n' "$_f2_today2" > "$D/repo/README.md"
  printf '# Adapter\n<!-- last-verified: %s (doctor-checked) -->\n' "$_f2_today2" > "$D/repo/adapters/claude-code/README.md"
  printf '# Attic (no anchor)\n' > "$D/repo/adapters/claude-code/attic/README.md"
  printf '# Evals\n<!-- last-verified: %s (doctor-checked) -->\n' "$_f2_today2" > "$D/repo/evals/README.md"
  printf '# UI\n<!-- last-verified: %s (doctor-checked) -->\n' "$_f2_today2" > "$D/repo/neural-lace/workstreams-ui/README.md"
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  OUT="$(_run_quick "$D")"; RC=$?
  _assert "wave-f-f2-docs-predicate2-noanchor-red" 1 "$RC" "RED wave-f-f2-docs.*NO-ANCHOR.*attic/README.md" "$OUT"

  # ---- Check: wave-f-f2-docs Predicate 2 GREEN fixture — all five anchors
  # present and fresh (today) ----
  D=$(_scenario_dir f2p2-green)
  _stamp_claim_honesty_green "$D"
  _f2_today3="$(date +%Y-%m-%d)"
  mkdir -p "$D/repo/adapters/claude-code/attic" "$D/repo/evals" "$D/repo/neural-lace/workstreams-ui"
  printf '# Repo\n<!-- last-verified: %s (doctor-checked) -->\n' "$_f2_today3" > "$D/repo/README.md"
  printf '# Adapter\n<!-- last-verified: %s (doctor-checked) -->\n' "$_f2_today3" > "$D/repo/adapters/claude-code/README.md"
  printf '# Attic\n<!-- last-verified: %s (doctor-checked) -->\n' "$_f2_today3" > "$D/repo/adapters/claude-code/attic/README.md"
  printf '# Evals\n<!-- last-verified: %s (doctor-checked) -->\n' "$_f2_today3" > "$D/repo/evals/README.md"
  printf '# UI\n<!-- last-verified: %s (doctor-checked) -->\n' "$_f2_today3" > "$D/repo/neural-lace/workstreams-ui/README.md"
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  OUT="$(_run_quick "$D")"; RC=$?
  _assert "wave-f-f2-docs-predicate2-green" 0 "$RC" "" "$OUT"

  # ---- Check: heartbeat-task (NL-FINDING-022, item 6). Only meaningfully
  # exercisable on a machine with schtasks (Windows); elsewhere it WARNs
  # (skip) and this scenario is a no-op pass either way — a machine with
  # NO 'NL-workstreams-heartbeat' task registered must not RED (WARN only). ----
  D=$(_scenario_dir hb-warn)
  _stamp_claim_honesty_green "$D"
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  OUT="$(_run_quick "$D")"; RC=$?
  _assert "heartbeat-task-unregistered-warns-not-red" 0 "$RC" "" "$OUT"

  # ---- Check: untracked-dirt-ignore-rule (NL-FINDING-026 class 2, item 9).
  # RED-equivalent (WARN) fixture — repo .gitignore does NOT ignore
  # .claude/state/ ----
  D=$(_scenario_dir udi-warn)
  _stamp_claim_honesty_green "$D"
  echo "node_modules/" > "$D/repo/.gitignore"
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  OUT="$(_run_quick "$D")"; RC=$?
  _assert "untracked-dirt-ignore-rule-missing-warns" 0 "$RC" "WARN untracked-dirt-ignore-rule" "$OUT"

  # ---- Check: untracked-dirt-ignore-rule GREEN fixture — .gitignore DOES
  # cover .claude/state/ ----
  D=$(_scenario_dir udi-green)
  _stamp_claim_honesty_green "$D"
  printf 'node_modules/\n.claude/state/\n' > "$D/repo/.gitignore"
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  OUT="$(_run_quick "$D")"; RC=$?
  _assert "untracked-dirt-ignore-rule-present-green" 0 "$RC" "" "$OUT"

  # ---- Check: pin-f-waiver-purpose-clauses (ADR 058 D5 pin f, item 2).
  # RED-equivalent (WARN) fixture — a repo hook reads a waiver with no
  # purpose-clause validator referenced ----
  D=$(_scenario_dir pf-warn)
  _stamp_claim_honesty_green "$D"
  cat > "$D/repo/adapters/claude-code/hooks/legacy-waiver-reader.sh" <<'EOF'
#!/bin/bash
# reads a waiver file with only an existence+freshness check
if find .claude/state -name 'foo-waiver-*.txt' -newermt '1 hour ago' | grep -q .; then
  exit 0
fi
EOF
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  OUT="$(_run_quick "$D")"; RC=$?
  _assert "pin-f-waiver-purpose-clauses-missing-warns" 0 "$RC" "WARN pin-f-waiver-purpose-clauses" "$OUT"

  # ---- Check: pin-f-waiver-purpose-clauses GREEN fixture — the hook
  # references the shared purpose-clause validator ----
  D=$(_scenario_dir pf-green)
  _stamp_claim_honesty_green "$D"
  cat > "$D/repo/adapters/claude-code/hooks/modern-waiver-reader.sh" <<'EOF'
#!/bin/bash
# reads a waiver file, routed through waiver_has_purpose_clauses
if waiver_has_purpose_clauses ".claude/state/foo-waiver-x.txt"; then
  exit 0
fi
EOF
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  OUT="$(_run_quick "$D")"; RC=$?
  _assert "pin-f-waiver-purpose-clauses-present-green" 0 "$RC" "" "$OUT"

  # ---- Check: budget-chains (Wave F, F.1). RED fixture — Stop chain has
  # 7 entries (budget <= 6) in BOTH live and template. Dummy hook FILES are
  # created on both the live and repo sides so the unrelated wiring-resolves
  # check (which RED-fires on any referenced-but-missing hook) stays quiet —
  # this fixture is scoped to budget-chains only. ----
  _write_chain_settings() {
    # $1 = D (scenario dir), $2 = event (Stop|SessionStart), $3 = count, $4 = name prefix
    local d="$1" event="$2" n="$3" prefix="$4"
    local body="{\"hooks\":{\"${event}\":[{\"matcher\":\"*\",\"hooks\":["
    local i first=1
    for ((i = 0; i < n; i++)); do
      if [[ "$first" -eq 0 ]]; then body="${body},"; fi
      first=0
      body="${body}{\"type\":\"command\",\"command\":\"bash ~/.claude/hooks/${prefix}-${i}.sh\"}"
      echo '#!/bin/bash' > "$d/live/hooks/${prefix}-${i}.sh"
      echo '#!/bin/bash' > "$d/repo/adapters/claude-code/hooks/${prefix}-${i}.sh"
    done
    body="${body}]}]}}"
    printf '%s' "$body" > "$d/live/settings.json"
    cp "$d/live/settings.json" "$d/repo/adapters/claude-code/settings.json.template"
  }
  D=$(_scenario_dir bc-stop-red)
  _stamp_claim_honesty_green "$D"
  _write_chain_settings "$D" "Stop" 7 "stop-dummy"
  OUT="$(_run_quick "$D")"; RC=$?
  _assert "budget-chains-stop-red" 1 "$RC" "RED budget-chains.*Stop chain has 7" "$OUT"

  # ---- Check: budget-chains GREEN fixture — Stop chain at 4 (within budget) ----
  D=$(_scenario_dir bc-stop-green)
  _stamp_claim_honesty_green "$D"
  _write_chain_settings "$D" "Stop" 4 "stop-dummy"
  OUT="$(_run_quick "$D")"; RC=$?
  _assert "budget-chains-stop-green" 0 "$RC" "" "$OUT"

  # ---- Check: budget-chains RED fixture — SessionStart chain has 9 entries
  # (budget <= 8) ----
  D=$(_scenario_dir bc-ss-red)
  _stamp_claim_honesty_green "$D"
  _write_chain_settings "$D" "SessionStart" 9 "ss-dummy"
  OUT="$(_run_quick "$D")"; RC=$?
  _assert "budget-chains-sessionstart-red" 1 "$RC" "RED budget-chains.*SessionStart chain has 9" "$OUT"

  # ---- Check: budget-bash-hooks (harness-execution-redesign-2026-08 Task
  # 1, R3.3). WARN fixture — 7 hooks wired to the "Bash" matcher (budget
  # <= 6); WARN-only at this stage, exit code stays 0. ----
  D=$(_scenario_dir bbh-warn)
  _stamp_claim_honesty_green "$D"
  _write_settings "$D/live/settings.json" bbh-a.sh bbh-b.sh bbh-c.sh bbh-d.sh bbh-e.sh bbh-f.sh bbh-g.sh
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  for _n in a b c d e f g; do
    echo '#!/bin/bash' > "$D/live/hooks/bbh-${_n}.sh"
    echo '#!/bin/bash' > "$D/repo/adapters/claude-code/hooks/bbh-${_n}.sh"
  done
  OUT="$(_run_quick "$D")"; RC=$?
  _assert "budget-bash-hooks-warn" 0 "$RC" "WARN budget-bash-hooks.*7 hook entries" "$OUT"

  # ---- Check: budget-bash-hooks GREEN fixture — 3 hooks (within budget),
  # silent on this check. ----
  D=$(_scenario_dir bbh-green)
  _stamp_claim_honesty_green "$D"
  _write_settings "$D/live/settings.json" bbh-a.sh bbh-b.sh bbh-c.sh
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  for _n in a b c; do
    echo '#!/bin/bash' > "$D/live/hooks/bbh-${_n}.sh"
    echo '#!/bin/bash' > "$D/repo/adapters/claude-code/hooks/bbh-${_n}.sh"
  done
  OUT="$(_run_quick "$D")"; RC=$?
  if printf '%s' "$OUT" | grep -q "budget-bash-hooks"; then
    echo "self-test (budget-bash-hooks-green-silent): FAIL (unexpected budget-bash-hooks line): $OUT" >&2
    FAILED=$((FAILED + 1))
  else
    echo "self-test (budget-bash-hooks-green-silent): PASS" >&2
    PASSED=$((PASSED + 1))
  fi

  # ---- Check: budget-bash-hooks RED fixture (HR-F7, gated-pipeline
  # T7/REQ-A5): red_after in the past -> the same over-budget count flips
  # from WARN to RED, exit code 1. ----
  D=$(_scenario_dir bbh-red-after-flip)
  _stamp_claim_honesty_green "$D"
  _write_settings "$D/live/settings.json" bbh-a.sh bbh-b.sh bbh-c.sh bbh-d.sh bbh-e.sh bbh-f.sh bbh-g.sh
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  for _n in a b c d e f g; do
    echo '#!/bin/bash' > "$D/live/hooks/bbh-${_n}.sh"
    echo '#!/bin/bash' > "$D/repo/adapters/claude-code/hooks/bbh-${_n}.sh"
  done
  mkdir -p "$D/repo/adapters/claude-code/config"
  printf '{"schema_version":3,"budget_check":{"red_after":"2020-01-01"},"mechanisms":[]}' \
    > "$D/repo/adapters/claude-code/config/schedule-manifest.json"
  OUT="$(_run_quick "$D")"; RC=$?
  _assert "budget-bash-hooks-red-after-flip" 1 "$RC" "RED budget-bash-hooks.*7 hook entries" "$OUT"

  # ---- Check: budget-bash-hooks stays WARN fixture — red_after in the
  # future -> still WARN, exit code 0. ----
  D=$(_scenario_dir bbh-warn-future-red-after)
  _stamp_claim_honesty_green "$D"
  _write_settings "$D/live/settings.json" bbh-a.sh bbh-b.sh bbh-c.sh bbh-d.sh bbh-e.sh bbh-f.sh bbh-g.sh
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  for _n in a b c d e f g; do
    echo '#!/bin/bash' > "$D/live/hooks/bbh-${_n}.sh"
    echo '#!/bin/bash' > "$D/repo/adapters/claude-code/hooks/bbh-${_n}.sh"
  done
  mkdir -p "$D/repo/adapters/claude-code/config"
  printf '{"schema_version":3,"budget_check":{"red_after":"2099-01-01"},"mechanisms":[]}' \
    > "$D/repo/adapters/claude-code/config/schedule-manifest.json"
  OUT="$(_run_quick "$D")"; RC=$?
  _assert "budget-bash-hooks-red-after-future-stays-warn" 0 "$RC" "WARN budget-bash-hooks.*7 hook entries" "$OUT"

  # ---- Check: schedule-manifest-cadence (harness-execution-redesign-
  # 2026-08 Task 1, invariant 2). WARN fixture — declared cadence (60s) is
  # under 2x the recorded cycle time (110s, needs >= 220s), naming the
  # entry; WARN-only at this stage (calibration week), exit code stays 0.
  # Mirrors this task's own real coord-sync entry in the shipped manifest,
  # so this fixture is representative, not synthetic-only. ----
  D=$(_scenario_dir smc-warn)
  _stamp_claim_honesty_green "$D"
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  mkdir -p "$D/repo/adapters/claude-code/config"
  cat > "$D/repo/adapters/claude-code/config/schedule-manifest.json" <<'EOF'
{"schema_version":1,"cadence_check":{"ratio_floor":2},"mechanisms":[
  {"id":"fixture-coord-sync","declared_cadence_seconds":60,"measured_cycle_seconds":110}
]}
EOF
  OUT="$(_run_quick "$D")"; RC=$?
  _assert "schedule-manifest-cadence-warn" 0 "$RC" "WARN schedule-manifest-cadence.*'fixture-coord-sync'" "$OUT"

  # ---- Check: schedule-manifest-cadence GREEN fixture — cadence comfortably
  # >= 2x cycle time, silent on this check. ----
  D=$(_scenario_dir smc-green)
  _stamp_claim_honesty_green "$D"
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  mkdir -p "$D/repo/adapters/claude-code/config"
  cat > "$D/repo/adapters/claude-code/config/schedule-manifest.json" <<'EOF'
{"schema_version":1,"cadence_check":{"ratio_floor":2},"mechanisms":[
  {"id":"fixture-healthy","declared_cadence_seconds":600,"measured_cycle_seconds":110}
]}
EOF
  OUT="$(_run_quick "$D")"; RC=$?
  if printf '%s' "$OUT" | grep -q "schedule-manifest-cadence"; then
    echo "self-test (schedule-manifest-cadence-green-silent): FAIL (unexpected schedule-manifest-cadence line): $OUT" >&2
    FAILED=$((FAILED + 1))
  else
    echo "self-test (schedule-manifest-cadence-green-silent): PASS" >&2
    PASSED=$((PASSED + 1))
  fi

  # ---- Check: schedule-manifest-cadence — missing manifest -> graceful
  # WARN (pre-Task-1 machine), never a crash. ----
  D=$(_scenario_dir smc-missing)
  _stamp_claim_honesty_green "$D"
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  OUT="$(_run_quick "$D")"; RC=$?
  _assert "schedule-manifest-cadence-missing-warn" 0 "$RC" "WARN schedule-manifest-cadence.*no adapters/claude-code/config/schedule-manifest.json found" "$OUT"

  # ---- Check: schedule-manifest-cadence RED fixture (HR-F7, gated-
  # pipeline T7/REQ-A5): red_after in the past -> the same violation flips
  # from WARN to RED, exit code 1. ----
  D=$(_scenario_dir smc-red-after-flip)
  _stamp_claim_honesty_green "$D"
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  mkdir -p "$D/repo/adapters/claude-code/config"
  cat > "$D/repo/adapters/claude-code/config/schedule-manifest.json" <<'EOF'
{"schema_version":3,"cadence_check":{"ratio_floor":2,"red_after":"2020-01-01"},"mechanisms":[
  {"id":"fixture-coord-sync-red","declared_cadence_seconds":60,"measured_cycle_seconds":110}
]}
EOF
  OUT="$(_run_quick "$D")"; RC=$?
  _assert "schedule-manifest-cadence-red-after-flip" 1 "$RC" "RED schedule-manifest-cadence.*'fixture-coord-sync-red'" "$OUT"

  # ---- Check: schedule-manifest-cadence stays WARN fixture — red_after in
  # the future -> still WARN, exit code 0. ----
  D=$(_scenario_dir smc-warn-future-red-after)
  _stamp_claim_honesty_green "$D"
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  mkdir -p "$D/repo/adapters/claude-code/config"
  cat > "$D/repo/adapters/claude-code/config/schedule-manifest.json" <<'EOF'
{"schema_version":3,"cadence_check":{"ratio_floor":2,"red_after":"2099-01-01"},"mechanisms":[
  {"id":"fixture-coord-sync-future","declared_cadence_seconds":60,"measured_cycle_seconds":110}
]}
EOF
  OUT="$(_run_quick "$D")"; RC=$?
  _assert "schedule-manifest-cadence-red-after-future-stays-warn" 0 "$RC" "WARN schedule-manifest-cadence.*'fixture-coord-sync-future'" "$OUT"

  # ---- Check: schedule-manifest-cadence managed_by=nl-maintenance +
  # activation marker present -> satisfied-by-construction, annotated
  # (NOTE), never warned/redded even with a past red_after (HR-F7's own
  # proven false positive: the prescribed remedy IS this state). ----
  D=$(_scenario_dir smc-managed-satisfied)
  _stamp_claim_honesty_green "$D"
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  mkdir -p "$D/repo/adapters/claude-code/config"
  cat > "$D/repo/adapters/claude-code/config/schedule-manifest.json" <<'EOF'
{"schema_version":3,"cadence_check":{"ratio_floor":2,"red_after":"2020-01-01"},"mechanisms":[
  {"id":"fixture-managed","declared_cadence_seconds":60,"measured_cycle_seconds":110,"managed_by":"nl-maintenance"}
]}
EOF
  mkdir -p "$D/live/state/nl-maintenance"
  { date +%s 2>/dev/null || echo 0; } > "$D/live/state/nl-maintenance/activation-marker"
  OUT="$(_run_quick "$D")"; RC=$?
  _assert "schedule-manifest-cadence-managed-satisfied-by-construction" 0 "$RC" "NOTE schedule-manifest-cadence.*'fixture-managed'.*satisfied-by-construction" "$OUT"
  if printf '%s' "$OUT" | grep -qE "(WARN|RED) schedule-manifest-cadence.*'fixture-managed'"; then
    echo "self-test (schedule-manifest-cadence-managed-never-warns-or-reds): FAIL (expected NO WARN/RED line for the managed_by=nl-maintenance entry): $OUT" >&2
    FAILED=$((FAILED + 1))
  else
    echo "self-test (schedule-manifest-cadence-managed-never-warns-or-reds): PASS" >&2
    PASSED=$((PASSED + 1))
  fi

  # ---- Check: limit-resume-watchdog. No state dir at all -> silent
  # (WARN-free), RC 0. ----
  D=$(_scenario_dir lr-clean)
  _stamp_claim_honesty_green "$D"
  OUT="$(_run_quick "$D")"; RC=$?
  if [[ "$RC" == "0" ]] && ! printf '%s' "$OUT" | grep -q "limit-resume"; then
    echo "self-test (limit-resume-watchdog-clean-silent): PASS" >&2
    PASSED=$((PASSED + 1))
  else
    echo "self-test (limit-resume-watchdog-clean-silent): FAIL (rc=${RC}, unexpected output)" >&2
    printf '%s\n' "$OUT" >&2
    FAILED=$((FAILED + 1))
  fi

  # ---- Check: limit-resume-watchdog. giveup sentinel present -> WARN
  # (never RED -- an operational fact, not a harness defect), RC still 0.
  # Per-session layout (F3 fix): armed/<key>.json + sibling <key>.giveup. ----
  D=$(_scenario_dir lr-giveup)
  _stamp_claim_honesty_green "$D"
  mkdir -p "$D/live/state/limit-resume/armed"
  echo 'gave up after 8 attempts at 2026-07-30T10:00:00Z' > "$D/live/state/limit-resume/armed/selftest-sid.giveup"
  printf '{"session_id":"selftest-sid","cwd":"/tmp/x","armed_at":"2026-07-30T10:00:00Z"}\n' > "$D/live/state/limit-resume/armed/selftest-sid.json"
  OUT="$(_run_quick "$D")"; RC=$?
  _assert "limit-resume-watchdog-giveup-warn" 0 "$RC" "WARN limit-resume-giveup.*selftest-sid" "$OUT"

  # ---- Check: limit-resume-watchdog. Armed, zero attempts, armed_at
  # 90 minutes ago (>= 70m stale threshold, comfortably past the
  # watchdog's own 30min initial-silence floor) -> stale-armed WARN, the
  # DEFECT-1-CLASS ("every tick fails silently") regression detector. ----
  D=$(_scenario_dir lr-stale-armed)
  _stamp_claim_honesty_green "$D"
  mkdir -p "$D/live/state/limit-resume/armed"
  STALE_TS="$(date -u -v-90M +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '-90 minutes' +%Y-%m-%dT%H:%M:%SZ)"
  printf '{"session_id":"stale-sid","cwd":"/tmp/x","armed_at":"%s"}\n' "$STALE_TS" > "$D/live/state/limit-resume/armed/stale-sid.json"
  OUT="$(_run_quick "$D")"; RC=$?
  _assert "limit-resume-watchdog-stale-armed-warn" 0 "$RC" "WARN limit-resume-stale-armed.*stale-sid" "$OUT"

  # ---- Check: limit-resume-watchdog. Armed, zero attempts, armed_at only
  # 5 minutes ago -> too fresh to be suspicious (well within the
  # watchdog's own 30min floor), no WARN. ----
  D=$(_scenario_dir lr-fresh-armed)
  _stamp_claim_honesty_green "$D"
  mkdir -p "$D/live/state/limit-resume/armed"
  FRESH_TS="$(date -u -v-5M +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '-5 minutes' +%Y-%m-%dT%H:%M:%SZ)"
  printf '{"session_id":"fresh-sid","cwd":"/tmp/x","armed_at":"%s"}\n' "$FRESH_TS" > "$D/live/state/limit-resume/armed/fresh-sid.json"
  OUT="$(_run_quick "$D")"; RC=$?
  if [[ "$RC" == "0" ]] && ! printf '%s' "$OUT" | grep -q "limit-resume"; then
    echo "self-test (limit-resume-watchdog-fresh-armed-silent): PASS" >&2
    PASSED=$((PASSED + 1))
  else
    echo "self-test (limit-resume-watchdog-fresh-armed-silent): FAIL (rc=${RC}, unexpected output)" >&2
    printf '%s\n' "$OUT" >&2
    FAILED=$((FAILED + 1))
  fi

  # ---- Check: limit-resume-watchdog. Per-session isolation (F3 fix): TWO
  # tracked sessions, only ONE has given up -> exactly one WARN, naming
  # the RIGHT session, and the healthy one's own id never appears in a
  # WARN line. ----
  D=$(_scenario_dir lr-two-sessions)
  _stamp_claim_honesty_green "$D"
  mkdir -p "$D/live/state/limit-resume/armed"
  echo 'gave up after 8 attempts at 2026-07-30T10:00:00Z' > "$D/live/state/limit-resume/armed/bad-sid.giveup"
  printf '{"session_id":"bad-sid","cwd":"/tmp/x","armed_at":"2026-07-30T10:00:00Z"}\n' > "$D/live/state/limit-resume/armed/bad-sid.json"
  FRESH_TS2="$(date -u -v-5M +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '-5 minutes' +%Y-%m-%dT%H:%M:%SZ)"
  printf '{"session_id":"healthy-sid","cwd":"/tmp/y","armed_at":"%s"}\n' "$FRESH_TS2" > "$D/live/state/limit-resume/armed/healthy-sid.json"
  OUT="$(_run_quick "$D")"; RC=$?
  if [[ "$RC" == "0" ]] && printf '%s' "$OUT" | grep -q "WARN limit-resume-giveup.*bad-sid" \
     && ! printf '%s' "$OUT" | grep -q "healthy-sid"; then
    echo "self-test (limit-resume-watchdog-two-session-isolation): PASS" >&2
    PASSED=$((PASSED + 1))
  else
    echo "self-test (limit-resume-watchdog-two-session-isolation): FAIL (rc=${RC})" >&2
    printf '%s\n' "$OUT" >&2
    FAILED=$((FAILED + 1))
  fi

  # ---- Check: budget-blocking-gates. Counting rule (specs-d §D.0.4, fixed
  # during Wave-F integration): blocking:true AND wired_template:true AND
  # wired to a live-session event, with same-class consolidation via
  # blocking-budget-check.js's UNIT_MAP — NOT a bare blocking:true count.
  # Fixture entries must be wired_template:true with a session event
  # (PreToolUse here) to be counted at all; each fixture id is distinct so
  # none of them hit the UNIT_MAP consolidation table (that table's own
  # behavior is exercised live against the real manifest, not re-tested
  # here — this fixture only needs to prove the RED/GREEN threshold at 14,
  # raised from 13 agent-efficiency batch 2026-07-23 (find-disk-scan-gate,
  # full §10 evidence bar; prior raise 12->13 harness-governance-batch
  # 2026-07-16: gh-merge-canonical + review-before-deploy; evidence-before-
  # fix is WARN-MODE, consumes no unit). 14 is the MEASURED integrated
  # count, not headroom; budget stays deliberately tight — raise only with
  # named gates. Fixture counts track the cap: RED = cap+1, GREEN = cap.
  _write_blocking_manifest_fixture() {
    local dir="$1" count="$2"
    local entries="" i
    for ((i = 0; i < count; i++)); do
      [[ -n "$entries" ]] && entries="${entries},"
      entries="${entries}{\"id\":\"fixture-gate-${i}\",\"kind\":\"gate\",\"doctrine_file\":null,\"hooks\":[],\"events\":[\"PreToolUse\"],\"wired_template\":true,\"selftest\":false,\"jit_triggers\":{\"paths\":[],\"keywords\":[]},\"blocking\":true,\"honest_status\":\"fixture stub\",\"budget_class\":\"pretool\",\"added_after\":\"2026-04\"}"
    done
    printf '{"schema_version":1,"entries":[%s]}' "$entries" > "$dir/repo/adapters/claude-code/manifest.json"
  }
  _copy_blocking_budget_tooling() {
    local dir="$1"
    local src="$SCRIPT_DIR/../scripts/blocking-budget-check.js"
    [[ -f "$src" ]] || return 1
    mkdir -p "$dir/repo/adapters/claude-code/scripts"
    cp "$src" "$dir/repo/adapters/claude-code/scripts/blocking-budget-check.js"
    return 0
  }
  D=$(_scenario_dir bbg-red)
  _stamp_claim_honesty_green "$D"
  _write_blocking_manifest_fixture "$D" 15
  _copy_blocking_budget_tooling "$D"
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  OUT="$(_run_quick "$D")"; RC=$?
  _assert "budget-blocking-gates-red" 1 "$RC" "RED budget-blocking-gates.*blocking session-event units: 15" "$OUT"

  # ---- Check: budget-blocking-gates GREEN fixture — 14 units (at budget) ----
  D=$(_scenario_dir bbg-green)
  _stamp_claim_honesty_green "$D"
  _write_blocking_manifest_fixture "$D" 14
  _copy_blocking_budget_tooling "$D"
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  OUT="$(_run_quick "$D")"; RC=$?
  _assert "budget-blocking-gates-green" 0 "$RC" "" "$OUT"

  # ---- Check: budget-blocking-gates — a blocking:true entry that is NOT
  # wired_template (a GAP entry) or fires only on a git-boundary event must
  # NOT count toward the budget (proves the fix: this used to inflate the
  # count under the old bare-blocking:true method). 13 non-counting entries
  # + the budget-class fixture at exactly 13 counting entries -> still GREEN.
  D=$(_scenario_dir bbg-noncounting-green)
  _stamp_claim_honesty_green "$D"
  _write_blocking_manifest_fixture "$D" 13
  node -e '
const fs = require("fs");
const p = process.argv[1];
const m = JSON.parse(fs.readFileSync(p, "utf8"));
for (let i = 0; i < 13; i++) {
  m.entries.push({ id: `fixture-noncounting-${i}`, kind: "gate", doctrine_file: null, hooks: [], events: ["precommit"], wired_template: false, selftest: false, jit_triggers: { paths: [], keywords: [] }, blocking: true, honest_status: "fixture: git-boundary, not wired live", budget_class: "none", added_after: "2026-04" });
}
fs.writeFileSync(p, JSON.stringify(m));
' "$D/repo/adapters/claude-code/manifest.json"
  _copy_blocking_budget_tooling "$D"
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  OUT="$(_run_quick "$D")"; RC=$?
  _assert "budget-blocking-gates-noncounting-entries-green" 0 "$RC" "" "$OUT"

  # ---- Check: budget-always-loaded. RED fixture — rules + CLAUDE.md exceed
  # 30000 bytes ----
  D=$(_scenario_dir bal-red)
  _stamp_claim_honesty_green "$D"
  head -c 31000 /dev/zero | tr '\0' 'x' > "$D/live/rules/big.md"
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  OUT="$(_run_quick "$D")"; RC=$?
  _assert "budget-always-loaded-red" 1 "$RC" "RED budget-always-loaded" "$OUT"

  # ---- Check: budget-always-loaded GREEN fixture — well under 30000 bytes ----
  D=$(_scenario_dir bal-green)
  _stamp_claim_honesty_green "$D"
  echo "small" > "$D/live/rules/small.md"
  echo "small claude.md" > "$D/live/CLAUDE.md"
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  OUT="$(_run_quick "$D")"; RC=$?
  _assert "budget-always-loaded-green" 0 "$RC" "" "$OUT"

  # ---- Check: budget-active-plans. RED fixture — 4 ACTIVE plans in the
  # repo root's docs/plans/ (budget <= 3). The fixture's live/local/ has no
  # nl-repo-path file, so (post-fix) only repo_root itself is walked —
  # this is the isolation the live_home-scoping fix above guarantees. ----
  D=$(_scenario_dir bap-red)
  _stamp_claim_honesty_green "$D"
  mkdir -p "$D/repo/docs/plans"
  for i in 1 2 3 4; do
    printf '# Plan %d\nStatus: ACTIVE\n' "$i" > "$D/repo/docs/plans/p${i}.md"
  done
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  OUT="$(_run_quick "$D")"; RC=$?
  _assert "budget-active-plans-red" 1 "$RC" "RED budget-active-plans.*4 plans" "$OUT"

  # ---- Check: budget-active-plans GREEN fixture — 3 ACTIVE plans (at budget) ----
  D=$(_scenario_dir bap-green)
  _stamp_claim_honesty_green "$D"
  mkdir -p "$D/repo/docs/plans"
  for i in 1 2 3; do
    printf '# Plan %d\nStatus: ACTIVE\n' "$i" > "$D/repo/docs/plans/p${i}.md"
  done
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  OUT="$(_run_quick "$D")"; RC=$?
  _assert "budget-active-plans-green" 0 "$RC" "" "$OUT"

  # ---- Check: budget-active-plans WORKTREE DOUBLE-COUNT fixture (verifier
  # live-probe finding: doctor run from a linked worktree double-counts
  # ACTIVE plans because repo_root and <live_home>/local/nl-repo-path
  # resolve to two different absolute paths for the same repository) — a
  # real git repo with a real LINKED WORKTREE of itself, registered via
  # `git worktree add`. repo_root is pointed at the worktree; live/local/
  # nl-repo-path points at the main repo — the exact shape a doctor run
  # FROM a linked worktree produces (resolve_repo_root() resolves the
  # worktree's own toplevel; nl-repo-path names the main checkout). Both
  # sides carry the SAME docs/plans/ (2 ACTIVE plans; committed to the repo
  # so the worktree checkout sees them too — `git worktree add` checks out
  # tracked files, it does not duplicate them on disk as separate content).
  # Pre-fix: naive path-string de-dup treats these as two distinct roots
  # and double-counts -> 4 total (over budget 3) -> false RED. Post-fix:
  # git-common-dir de-dup collapses them to ONE counted root -> 2 total
  # (under budget) -> GREEN. ----
  D=$(_scenario_dir bap-wt-dedup-green)
  _stamp_claim_honesty_green "$D"
  (
    cd "$D/repo" \
      && git init --quiet && git config core.hooksPath "" \
      && git config user.email t@example.com && git config user.name T \
      && mkdir -p docs/plans \
      && printf '# Plan 1\nStatus: ACTIVE\n' > docs/plans/p1.md \
      && printf '# Plan 2\nStatus: ACTIVE\n' > docs/plans/p2.md \
      && git add docs/plans && git commit --quiet -m "seed plans" \
      && git worktree add --quiet -b bap-wt-dedup-green-branch "$D/linked-worktree" >/dev/null 2>&1
  ) >/dev/null 2>&1
  mkdir -p "$D/live/local"
  printf '%s\n' "$D/repo" > "$D/live/local/nl-repo-path"
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  # Point repo_root (NL_REPO_ROOT / positional arg) at the LINKED worktree,
  # not $D/repo — this reproduces "doctor invoked from the worktree" while
  # nl-repo-path (above) still names the main checkout, matching the two
  # divergent-path, same-repo shape the fix targets.
  OUT="$(HARNESS_DOCTOR_HOME="$D/live" NL_REPO_ROOT="$D/linked-worktree" bash "$SELF_TEST_HOOK" --quick "$D/linked-worktree" 2>&1)"; RC=$?
  _assert "budget-active-plans-worktree-dedup-green" 0 "$RC" "" "$OUT"

  # ---- Check: budget-active-plans TWO GENUINELY DISTINCT REPOS still sum
  # correctly (proves the git-common-dir de-dup is not overly permissive —
  # it must NOT collapse two unrelated repos just because both happen to be
  # git repos). repo_root = repo-one (2 ACTIVE plans); nl-repo-path =
  # repo-two (2 ACTIVE plans, its own separate .git). True total = 4 (over
  # budget 3) across 2 distinct roots -> RED. ----
  D=$(_scenario_dir bap-2repos-red)
  _stamp_claim_honesty_green "$D"
  mkdir -p "$D/repo-two/docs/plans"
  (
    cd "$D/repo" && git init --quiet && git config core.hooksPath "" \
      && git config user.email t@example.com && git config user.name T
  ) >/dev/null 2>&1
  (
    cd "$D/repo-two" && git init --quiet && git config core.hooksPath "" \
      && git config user.email t@example.com && git config user.name T
  ) >/dev/null 2>&1
  mkdir -p "$D/repo/docs/plans"
  printf '# Plan 1\nStatus: ACTIVE\n' > "$D/repo/docs/plans/p1.md"
  printf '# Plan 2\nStatus: ACTIVE\n' > "$D/repo/docs/plans/p2.md"
  printf '# Plan 1\nStatus: ACTIVE\n' > "$D/repo-two/docs/plans/p1.md"
  printf '# Plan 2\nStatus: ACTIVE\n' > "$D/repo-two/docs/plans/p2.md"
  mkdir -p "$D/live/local"
  printf '%s\n' "$D/repo-two" > "$D/live/local/nl-repo-path"
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  OUT="$(_run_quick "$D")"; RC=$?
  _assert "budget-active-plans-two-distinct-repos-red" 1 "$RC" "RED budget-active-plans.*4 plans" "$OUT"

  # ---- Check: budget-worktrees-branches. RED fixture — a real throwaway
  # git repo with a stale (8-day-old, backdated commit) local branch with
  # no upstream. This fixture targets the branch-staleness half only; the
  # worktree-age half (a real `git worktree add` with a backdated HEAD) is
  # exercised separately by the bwb-age-red/bwb-age-green fixtures below —
  # this was a previously-admitted gap (see git history) now closed. ----
  D=$(_scenario_dir bwb-red)
  _stamp_claim_honesty_green "$D"
  # Epoch form ("@<unix-ts> +0000"), not "8 days ago" — GIT_AUTHOR_DATE/
  # GIT_COMMITTER_DATE do not accept git's free-form --date approxidate
  # syntax on every git build (confirmed non-parseable on this machine's
  # git 2.53; the epoch form is universally accepted).
  ( _bwb_stale_ts=$(( $(date -u +%s) - 8 * 86400 )) \
      && cd "$D/repo" \
      && git init --quiet && git config core.hooksPath "" \
      && git config user.email t@example.com && git config user.name T \
      && echo x > f && git add f && git commit --quiet -m init \
      && git checkout --quiet -b stale-no-upstream-branch \
      && echo y > g && git add g \
      && GIT_AUTHOR_DATE="@${_bwb_stale_ts} +0000" GIT_COMMITTER_DATE="@${_bwb_stale_ts} +0000" git commit --quiet -m stale \
      && { git checkout --quiet master 2>/dev/null || git checkout --quiet main 2>/dev/null || true; }
  ) >/dev/null 2>&1
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  OUT="$(_run_quick "$D")"; RC=$?
  _assert "budget-worktrees-branches-branch-red" 1 "$RC" "RED budget-worktrees-branches.*stale-no-upstream-branch" "$OUT"

  # ---- Check: budget-worktrees-branches GREEN fixture — a fresh branch
  # with a recent commit and no upstream (must NOT flag: <7d old) ----
  D=$(_scenario_dir bwb-green)
  _stamp_claim_honesty_green "$D"
  ( cd "$D/repo" \
      && git init --quiet && git config core.hooksPath "" \
      && git config user.email t@example.com && git config user.name T \
      && echo x > f && git add f && git commit --quiet -m init \
      && git checkout --quiet -b fresh-no-upstream-branch \
      && echo y > g && git add g && git commit --quiet -m fresh \
      && git checkout --quiet master 2>/dev/null || git checkout --quiet main 2>/dev/null || true
  ) >/dev/null 2>&1
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  OUT="$(_run_quick "$D")"; RC=$?
  _assert "budget-worktrees-branches-branch-green" 0 "$RC" "" "$OUT"

  # ---- Check: budget-worktrees-branches WORKTREE-AGE RED fixture — a real
  # git repo with a real LINKED WORKTREE (registered via `git worktree add`,
  # not just a branch) whose HEAD commit is backdated >=7d via
  # GIT_COMMITTER_DATE. This exercises the worktree age sub-check itself
  # (the wt_path/HEAD loop over `git worktree list --porcelain` in
  # check_budget_worktrees_branches), which the pre-existing bwb-red/
  # bwb-green fixtures above admit (in their own comment) they never
  # exercised — this fixture closes that gap. ----
  D=$(_scenario_dir bwb-age-red)
  _stamp_claim_honesty_green "$D"
  (
    _bwb_age_stale_ts=$(( $(date -u +%s) - 8 * 86400 )) \
      && cd "$D/repo" \
      && git init --quiet && git config core.hooksPath "" \
      && git config user.email t@example.com && git config user.name T \
      && echo x > f && git add f && git commit --quiet -m init \
      && git worktree add --quiet -b stale-worktree-branch "$D/stale-worktree" >/dev/null 2>&1 \
      && cd "$D/stale-worktree" \
      && git config core.hooksPath "" \
      && echo y > g && git add g \
      && GIT_AUTHOR_DATE="@${_bwb_age_stale_ts} +0000" GIT_COMMITTER_DATE="@${_bwb_age_stale_ts} +0000" git commit --quiet -m stale-worktree-commit
  ) >/dev/null 2>&1
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  OUT="$(_run_quick "$D")"; RC=$?
  _assert "budget-worktrees-branches-age-red" 1 "$RC" "RED budget-worktrees-branches.*stale-worktree.*no commit in [89][0-9]*d" "$OUT"

  # ---- Check: budget-worktrees-branches WORKTREE-AGE GREEN fixture — a
  # real linked worktree with a fresh (just-made) commit; must NOT flag ----
  D=$(_scenario_dir bwb-age-green)
  _stamp_claim_honesty_green "$D"
  (
    cd "$D/repo" \
      && git init --quiet && git config core.hooksPath "" \
      && git config user.email t@example.com && git config user.name T \
      && echo x > f && git add f && git commit --quiet -m init \
      && git worktree add --quiet -b fresh-worktree-branch "$D/fresh-worktree" >/dev/null 2>&1 \
      && cd "$D/fresh-worktree" \
      && git config core.hooksPath "" \
      && echo y > g && git add g && git commit --quiet -m fresh-worktree-commit
  ) >/dev/null 2>&1
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  OUT="$(_run_quick "$D")"; RC=$?
  _assert "budget-worktrees-branches-age-green" 0 "$RC" "" "$OUT"

  # ---- Check: orphaned-worktree-work. WARN fixture — a real secondary
  # worktree with an untracked file (dirty) and NO heartbeat/claim (both
  # sandboxed to dedicated empty fixture dirs so this scenario can never
  # read this machine's real heartbeat/claim state) -> the shared detector
  # (worktree-hygiene-sweep.sh --stranded --porcelain, copied in via
  # _copy_sweeper_tooling — never re-implemented here) classifies it
  # ORPHANED-HOLDS-CONTENT and the doctor WARNs (never RED — this check's
  # exit code stays 0 even when it fires; WARN_COUNT alone never fails
  # --quick). ----
  D=$(_scenario_dir oww-dirty-warn)
  _stamp_claim_honesty_green "$D"
  if _copy_sweeper_tooling "$D"; then
    (
      cd "$D/repo" \
        && git init --quiet && git config core.hooksPath "" \
        && git config user.email t@example.com && git config user.name T \
        && echo x > f && git add f && git commit --quiet -m init \
        && git worktree add --quiet -b oww-dirty-branch "$D/oww-dirty" >/dev/null 2>&1
    ) >/dev/null 2>&1
    echo scratch > "$D/oww-dirty/untracked.txt"
    mkdir -p "$D/hb-empty" "$D/claims-empty"
    _write_settings "$D/live/settings.json"
    cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
    OUT="$(HEARTBEAT_STATE_DIR="$D/hb-empty" COG_CLAIMS_DIR="$D/claims-empty" _run_quick "$D")"; RC=$?
    _assert "orphaned-worktree-work-dirty-warn" 0 "$RC" "WARN orphaned-worktree-work.*oww-dirty-branch" "$OUT"
  else
    echo "self-test (orphaned-worktree-work-dirty-warn): SKIP — worktree-hygiene-sweep.sh not present next to this doctor" >&2
  fi

  # ---- Check: orphaned-worktree-work. GREEN fixture (clean/merged) — a
  # secondary worktree at base tip, clean, old (>7d) -> SAFE-PRUNE, never
  # even enters the HOLDS-CONTENT liveness split -> no
  # orphaned-worktree-work WARN. ----
  D=$(_scenario_dir oww-clean-green)
  _stamp_claim_honesty_green "$D"
  if _copy_sweeper_tooling "$D"; then
    (
      _oww_old_ts=$(( $(date -u +%s) - 30 * 86400 )) \
        && cd "$D/repo" \
        && git init --quiet && git config core.hooksPath "" \
        && git config user.email t@example.com && git config user.name T \
        && echo x > f && git add f \
        && GIT_AUTHOR_DATE="@${_oww_old_ts} +0000" GIT_COMMITTER_DATE="@${_oww_old_ts} +0000" git commit --quiet -m init \
        && git worktree add --quiet -b oww-clean-branch "$D/oww-clean" >/dev/null 2>&1
    ) >/dev/null 2>&1
    mkdir -p "$D/hb-empty" "$D/claims-empty"
    _write_settings "$D/live/settings.json"
    cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
    OUT="$(HEARTBEAT_STATE_DIR="$D/hb-empty" COG_CLAIMS_DIR="$D/claims-empty" _run_quick "$D")"; RC=$?
    if printf '%s' "$OUT" | grep -q "orphaned-worktree-work"; then
      echo "self-test (orphaned-worktree-work-clean-green): FAIL (unexpected WARN for a clean/old/merged worktree)" >&2
      echo "--- output ---" >&2; printf '%s\n' "$OUT" >&2
      FAILED=$((FAILED + 1))
    else
      echo "self-test (orphaned-worktree-work-clean-green): PASS" >&2
      PASSED=$((PASSED + 1))
    fi
  else
    echo "self-test (orphaned-worktree-work-clean-green): SKIP — worktree-hygiene-sweep.sh not present next to this doctor" >&2
  fi

  # ---- Check: orphaned-worktree-work. GREEN fixture (live-owned) — a
  # dirty secondary worktree, but with a LIVE heartbeat (fresh ts, this
  # self-test process's own alive $$) naming its worktree_root -> LIVE-
  # OWNED-HOLDS-CONTENT, excluded from the ORPHANED set -> no WARN despite
  # being dirty (requirement 5.i: a running builder's dirty tree is not
  # stranded work). ----
  D=$(_scenario_dir oww-live-green)
  _stamp_claim_honesty_green "$D"
  if _copy_sweeper_tooling "$D"; then
    (
      cd "$D/repo" \
        && git init --quiet && git config core.hooksPath "" \
        && git config user.email t@example.com && git config user.name T \
        && echo x > f && git add f && git commit --quiet -m init \
        && git worktree add --quiet -b oww-live-branch "$D/oww-live" >/dev/null 2>&1
    ) >/dev/null 2>&1
    echo scratch > "$D/oww-live/untracked.txt"
    mkdir -p "$D/hb-live" "$D/claims-empty"
    cat > "$D/hb-live/sess-oww-live.json" <<EOF
{"schema":1,"session_id":"sess-oww-live","pid":$$,"cwd":"$D/oww-live","repo_root":"$D/oww-live","worktree_root":"$D/oww-live","branch":"oww-live-branch","model":"sonnet","last_activity_ts":"$(date -u '+%Y-%m-%dT%H:%M:%SZ')","last_event":"turn-end","marker_state":"none"}
EOF
    _write_settings "$D/live/settings.json"
    cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
    OUT="$(HEARTBEAT_STATE_DIR="$D/hb-live" COG_CLAIMS_DIR="$D/claims-empty" _run_quick "$D")"; RC=$?
    if printf '%s' "$OUT" | grep -q "orphaned-worktree-work"; then
      echo "self-test (orphaned-worktree-work-live-owned-green): FAIL (unexpected WARN for a live-owned dirty worktree)" >&2
      echo "--- output ---" >&2; printf '%s\n' "$OUT" >&2
      FAILED=$((FAILED + 1))
    else
      echo "self-test (orphaned-worktree-work-live-owned-green): PASS" >&2
      PASSED=$((PASSED + 1))
    fi
  else
    echo "self-test (orphaned-worktree-work-live-owned-green): SKIP — worktree-hygiene-sweep.sh not present next to this doctor" >&2
  fi

  # ---- Check: orphaned-worktree-work. GREEN fixture (agent-worktree,
  # subagent-transcript-mtime liveness — REFORMULATION fix,
  # docs/harness-improvements/orphaned-worktree-guard.md). A dirty
  # worktree named `agent-<id>` (the harness's own isolation:worktree
  # dispatch naming) with NO heartbeat coverage AT ALL (sandboxed EMPTY
  # heartbeat dir — exactly what a real dispatched subagent has, since it
  # writes no heartbeat of its own) but a FRESH transcript file at the
  # real nested subagents/ path -> LIVE-OWNED via the transcript-mtime
  # signal alone, never even reaching the heartbeat join -> no WARN
  # despite being dirty with zero heartbeat coverage. This is the exact
  # false positive the harness-review REFORMULATE verdict required fixed:
  # an actively-running dispatched builder must not be flagged stranded
  # on every parallel-build day. ----
  D=$(_scenario_dir oww-agent-live-green)
  _stamp_claim_honesty_green "$D"
  if _copy_sweeper_tooling "$D"; then
    (
      cd "$D/repo" \
        && git init --quiet && git config core.hooksPath "" \
        && git config user.email t@example.com && git config user.name T \
        && echo x > f && git add f && git commit --quiet -m init \
        && git worktree add --quiet -b oww-agent-live-branch "$D/agent-oww-fixture" >/dev/null 2>&1
    ) >/dev/null 2>&1
    echo scratch > "$D/agent-oww-fixture/untracked.txt"
    mkdir -p "$D/hb-empty" "$D/claims-empty" "$D/tx/proj/sess/subagents"
    printf '{"type":"assistant","message":{"usage":{"input_tokens":1,"output_tokens":1}}}\n' \
      > "$D/tx/proj/sess/subagents/agent-oww-fixture.jsonl"
    _write_settings "$D/live/settings.json"
    cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
    OUT="$(HEARTBEAT_STATE_DIR="$D/hb-empty" COG_CLAIMS_DIR="$D/claims-empty" OBS_TRANSCRIPTS_ROOT="$D/tx" _run_quick "$D")"; RC=$?
    if printf '%s' "$OUT" | grep -q "orphaned-worktree-work"; then
      echo "self-test (orphaned-worktree-work-agent-live-green): FAIL (unexpected WARN for an agent-<id> worktree with a fresh own-transcript and NO heartbeat coverage at all)" >&2
      echo "--- output ---" >&2; printf '%s\n' "$OUT" >&2
      FAILED=$((FAILED + 1))
    else
      echo "self-test (orphaned-worktree-work-agent-live-green): PASS" >&2
      PASSED=$((PASSED + 1))
    fi
  else
    echo "self-test (orphaned-worktree-work-agent-live-green): SKIP — worktree-hygiene-sweep.sh not present next to this doctor" >&2
  fi

  # ---- Check: new-gate-evidence-bar. RED fixture — an added_after >=
  # 2026-07 entry missing the full evidence bar ----
  D=$(_scenario_dir nge-red)
  _stamp_claim_honesty_green "$D"
  cat > "$D/repo/adapters/claude-code/manifest.json" <<'MANIFEST_EOF'
{
  "schema_version": 1,
  "entries": [
    {
      "id": "new-gate-incomplete",
      "kind": "gate",
      "doctrine_file": null,
      "hooks": [],
      "events": [],
      "wired_template": false,
      "selftest": false,
      "jit_triggers": { "paths": [], "keywords": [] },
      "blocking": true,
      "honest_status": "fixture stub",
      "added_after": "2026-07",
      "budget_class": "none"
    }
  ]
}
MANIFEST_EOF
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  OUT="$(_run_quick "$D")"; RC=$?
  _assert "new-gate-evidence-bar-red" 1 "$RC" "RED new-gate-evidence-bar.*new-gate-incomplete" "$OUT"

  # ---- Check: new-gate-evidence-bar GREEN fixture — the full evidence bar
  # is present ----
  D=$(_scenario_dir nge-green)
  _stamp_claim_honesty_green "$D"
  cat > "$D/repo/adapters/claude-code/manifest.json" <<'MANIFEST_EOF'
{
  "schema_version": 1,
  "entries": [
    {
      "id": "new-gate-complete",
      "kind": "gate",
      "doctrine_file": null,
      "hooks": [],
      "events": [],
      "wired_template": false,
      "selftest": false,
      "jit_triggers": { "paths": [], "keywords": [] },
      "blocking": true,
      "honest_status": "fixture stub",
      "added_after": "2026-07",
      "golden_scenario": "Downstream-product incident 2026-07-03 cross-repo write",
      "fp_expectation": "legitimate cross-repo harness sessions must not warn",
      "retirement_condition": "zero fires for 30 days post-GA",
      "waiver_path": "fixture-waiver-*.txt",
      "budget_class": "none"
    }
  ]
}
MANIFEST_EOF
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  OUT="$(_run_quick "$D")"; RC=$?
  _assert "new-gate-evidence-bar-green" 0 "$RC" "" "$OUT"

  # ---- Check: new-gate-evidence-bar EVASION-BY-OMISSION close (batch task 5,
  # harness-governance-batch-2026-07-15). RED fixture — a blocking:true entry
  # with NO added_after field at all (not merely a pre-2026-07 value; the
  # field is absent). This is the exact evasion class that let model-pin skip
  # the whole bar before it was fixed: the OLD check logic only ever
  # inspected entries that ALREADY carried added_after and silently
  # `continue`d past ones missing it, so this fixture would have passed
  # doctor GREEN before this task's assertion landed ----
  D=$(_scenario_dir nge-omit-red)
  _stamp_claim_honesty_green "$D"
  cat > "$D/repo/adapters/claude-code/manifest.json" <<'MANIFEST_EOF'
{
  "schema_version": 1,
  "entries": [
    {
      "id": "new-gate-no-added-after",
      "kind": "gate",
      "doctrine_file": null,
      "hooks": [],
      "events": [],
      "wired_template": false,
      "selftest": false,
      "jit_triggers": { "paths": [], "keywords": [] },
      "blocking": true,
      "honest_status": "fixture stub",
      "budget_class": "none"
    }
  ]
}
MANIFEST_EOF
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  OUT="$(_run_quick "$D")"; RC=$?
  _assert "new-gate-evidence-bar-omission-red" 1 "$RC" "RED new-gate-evidence-bar.*new-gate-no-added-after.*missing added_after" "$OUT"

  # ---- Check: new-gate-evidence-bar EVASION-BY-OMISSION GREEN fixture — same
  # entry, added_after now backfilled to a pre-bar month. A legacy entry does
  # NOT need golden_scenario/fp_expectation/retirement_condition — only that
  # the field exists and is present ----
  D=$(_scenario_dir nge-omit-green)
  _stamp_claim_honesty_green "$D"
  cat > "$D/repo/adapters/claude-code/manifest.json" <<'MANIFEST_EOF'
{
  "schema_version": 1,
  "entries": [
    {
      "id": "new-gate-no-added-after",
      "kind": "gate",
      "doctrine_file": null,
      "hooks": [],
      "events": [],
      "wired_template": false,
      "selftest": false,
      "jit_triggers": { "paths": [], "keywords": [] },
      "blocking": true,
      "honest_status": "fixture stub",
      "added_after": "2026-04",
      "budget_class": "none"
    }
  ]
}
MANIFEST_EOF
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  OUT="$(_run_quick "$D")"; RC=$?
  _assert "new-gate-evidence-bar-omission-green" 0 "$RC" "" "$OUT"

  # ---- Check: new-gate-evidence-bar GRANDFATHER exempt-list GREEN fixture
  # (fixup, harness-review REJECT findings 1-3). All 5 PRE_BAR_GRANDFATHERED
  # ids, each carrying their TRUE added_after "2026-07" and NO
  # golden_scenario/fp_expectation/retirement_condition/waiver_path — proves
  # the exempt-list actually exempts them from the full bar (they would
  # otherwise RED on every missing field, same as any other 2026-07+ entry) ----
  D=$(_scenario_dir nge-grandfather-green)
  _stamp_claim_honesty_green "$D"
  cat > "$D/repo/adapters/claude-code/manifest.json" <<'MANIFEST_EOF'
{
  "schema_version": 1,
  "entries": [
    { "id": "session-honesty", "kind": "gate", "doctrine_file": null, "hooks": [], "events": [], "wired_template": false, "selftest": false, "jit_triggers": { "paths": [], "keywords": [] }, "blocking": true, "honest_status": "fixture stub", "added_after": "2026-07", "budget_class": "none" },
    { "id": "stop-verdict-dispatcher", "kind": "gate", "doctrine_file": null, "hooks": [], "events": [], "wired_template": false, "selftest": false, "jit_triggers": { "paths": [], "keywords": [] }, "blocking": true, "honest_status": "fixture stub", "added_after": "2026-07", "budget_class": "none" },
    { "id": "work-integrity", "kind": "gate", "doctrine_file": null, "hooks": [], "events": [], "wired_template": false, "selftest": false, "jit_triggers": { "paths": [], "keywords": [] }, "blocking": true, "honest_status": "fixture stub", "added_after": "2026-07", "budget_class": "none" },
    { "id": "secret-scan-ci-backstop", "kind": "gate", "doctrine_file": null, "hooks": [], "events": [], "wired_template": false, "selftest": false, "jit_triggers": { "paths": [], "keywords": [] }, "blocking": true, "honest_status": "fixture stub", "added_after": "2026-07", "budget_class": "none" },
    { "id": "synthetic-runner-ci", "kind": "gate", "doctrine_file": null, "hooks": [], "events": [], "wired_template": false, "selftest": false, "jit_triggers": { "paths": [], "keywords": [] }, "blocking": true, "honest_status": "fixture stub", "added_after": "2026-07", "budget_class": "none" }
  ]
}
MANIFEST_EOF
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  OUT="$(_run_quick "$D")"; RC=$?
  _assert "new-gate-evidence-bar-grandfather-green" 0 "$RC" "" "$OUT"

  # ---- Check: new-gate-evidence-bar GRANDFATHER exempt-list is CLOSED, not
  # a date pattern. RED fixture — the same 5 grandfathered ids (still exempt,
  # must NOT appear in the RED output) PLUS one extra NON-listed id at the
  # same added_after "2026-07" with no bar fields — that sixth id must still
  # RED, proving a new 2026-07+ gate cannot piggyback on the grandfather list
  # just by sharing its month ----
  D=$(_scenario_dir nge-grandfather-leak-red)
  _stamp_claim_honesty_green "$D"
  cat > "$D/repo/adapters/claude-code/manifest.json" <<'MANIFEST_EOF'
{
  "schema_version": 1,
  "entries": [
    { "id": "session-honesty", "kind": "gate", "doctrine_file": null, "hooks": [], "events": [], "wired_template": false, "selftest": false, "jit_triggers": { "paths": [], "keywords": [] }, "blocking": true, "honest_status": "fixture stub", "added_after": "2026-07", "budget_class": "none" },
    { "id": "stop-verdict-dispatcher", "kind": "gate", "doctrine_file": null, "hooks": [], "events": [], "wired_template": false, "selftest": false, "jit_triggers": { "paths": [], "keywords": [] }, "blocking": true, "honest_status": "fixture stub", "added_after": "2026-07", "budget_class": "none" },
    { "id": "work-integrity", "kind": "gate", "doctrine_file": null, "hooks": [], "events": [], "wired_template": false, "selftest": false, "jit_triggers": { "paths": [], "keywords": [] }, "blocking": true, "honest_status": "fixture stub", "added_after": "2026-07", "budget_class": "none" },
    { "id": "secret-scan-ci-backstop", "kind": "gate", "doctrine_file": null, "hooks": [], "events": [], "wired_template": false, "selftest": false, "jit_triggers": { "paths": [], "keywords": [] }, "blocking": true, "honest_status": "fixture stub", "added_after": "2026-07", "budget_class": "none" },
    { "id": "synthetic-runner-ci", "kind": "gate", "doctrine_file": null, "hooks": [], "events": [], "wired_template": false, "selftest": false, "jit_triggers": { "paths": [], "keywords": [] }, "blocking": true, "honest_status": "fixture stub", "added_after": "2026-07", "budget_class": "none" },
    { "id": "new-gate-not-grandfathered", "kind": "gate", "doctrine_file": null, "hooks": [], "events": [], "wired_template": false, "selftest": false, "jit_triggers": { "paths": [], "keywords": [] }, "blocking": true, "honest_status": "fixture stub", "added_after": "2026-07", "budget_class": "none" }
  ]
}
MANIFEST_EOF
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  OUT="$(_run_quick "$D")"; RC=$?
  _assert "new-gate-evidence-bar-grandfather-leak-red" 1 "$RC" "RED new-gate-evidence-bar.*new-gate-not-grandfathered" "$OUT"
  if printf '%s' "$OUT" | grep -qE "new-gate-evidence-bar: (session-honesty|stop-verdict-dispatcher|work-integrity|secret-scan-ci-backstop|synthetic-runner-ci):"; then
    echo "self-test (new-gate-evidence-bar-grandfather-leak-no-false-red): FAIL (a grandfathered id RED'd — exempt-list leaked)" >&2
    FAILED=$((FAILED + 1))
  else
    echo "self-test (new-gate-evidence-bar-grandfather-leak-no-false-red): PASS" >&2
    PASSED=$((PASSED + 1))
  fi

  # ---- Check: deterministic-process-proof (adapters/claude-code/doctrine/
  # deterministic-process.md). RED fixture — a NON-grandfathered blocking:true
  # entry declaring NEITHER chokepoint nor bypass_paths ----
  D=$(_scenario_dir dpp-red)
  _stamp_claim_honesty_green "$D"
  cat > "$D/repo/adapters/claude-code/manifest.json" <<'MANIFEST_EOF'
{
  "schema_version": 1,
  "entries": [
    { "id": "new-blocking-gate-no-proof", "kind": "gate", "doctrine_file": null, "hooks": [], "events": [], "wired_template": false, "selftest": false, "jit_triggers": { "paths": [], "keywords": [] }, "blocking": true, "honest_status": "fixture stub", "budget_class": "none" }
  ]
}
MANIFEST_EOF
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  OUT="$(_run_quick "$D")"; RC=$?
  _assert "deterministic-process-proof-red" 1 "$RC" "RED deterministic-process-proof.*new-blocking-gate-no-proof" "$OUT"

  # ---- GREEN fixture — the SAME shape, but with real chokepoint AND
  # bypass_paths declared. Proves this check does not blanket-RED every
  # blocking:true entry, only ones missing BOTH fields ----
  D=$(_scenario_dir dpp-green)
  _stamp_claim_honesty_green "$D"
  cat > "$D/repo/adapters/claude-code/manifest.json" <<'MANIFEST_EOF'
{
  "schema_version": 1,
  "entries": [
    { "id": "new-blocking-gate-with-proof", "kind": "gate", "doctrine_file": null, "hooks": [], "events": [], "wired_template": false, "selftest": false, "jit_triggers": { "paths": [], "keywords": [] }, "blocking": true, "honest_status": "fixture stub", "budget_class": "none", "chokepoint": "pre-push", "bypass_paths": ["git push --no-verify -- NAMED-AND-ACCEPTED"], "added_after": "2026-07", "golden_scenario": "fixture", "fp_expectation": "fixture", "retirement_condition": "fixture", "honesty_rationale": "fixture" }
  ]
}
MANIFEST_EOF
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  OUT="$(_run_quick "$D")"; RC=$?
  _assert "deterministic-process-proof-green" 0 "$RC" "" "$OUT"

  # ---- GRANDFATHER exempt-list GREEN fixture — a legacy blocking:true id
  # (from the closed DETERMINISTIC_PROCESS_GRANDFATHERED list) with NEITHER
  # field is exempt, not RED ----
  D=$(_scenario_dir dpp-grandfather-green)
  _stamp_claim_honesty_green "$D"
  # added_after:"2026-07" on both -- present (avoids new-gate-evidence-bar's
  # unconditional missing-added_after RED) and these two ids are ALSO in
  # THAT check's own PRE_BAR_GRANDFATHERED list, so its full-bar fields
  # (golden_scenario et al.) are not required either.
  cat > "$D/repo/adapters/claude-code/manifest.json" <<'MANIFEST_EOF'
{
  "schema_version": 1,
  "entries": [
    { "id": "session-honesty", "kind": "gate", "doctrine_file": null, "hooks": [], "events": [], "wired_template": false, "selftest": false, "jit_triggers": { "paths": [], "keywords": [] }, "blocking": true, "honest_status": "fixture stub", "budget_class": "none", "added_after": "2026-07" },
    { "id": "work-integrity", "kind": "gate", "doctrine_file": null, "hooks": [], "events": [], "wired_template": false, "selftest": false, "jit_triggers": { "paths": [], "keywords": [] }, "blocking": true, "honest_status": "fixture stub", "budget_class": "none", "added_after": "2026-07" }
  ]
}
MANIFEST_EOF
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  OUT="$(_run_quick "$D")"; RC=$?
  _assert "deterministic-process-proof-grandfather-green" 0 "$RC" "" "$OUT"

  # ---- GRANDFATHER exempt-list is CLOSED, not a blanket allowance for every
  # blocking:true entry: grandfathered ids alongside ONE non-grandfathered id
  # missing both fields — only the non-grandfathered one REDs ----
  D=$(_scenario_dir dpp-grandfather-leak-red)
  _stamp_claim_honesty_green "$D"
  cat > "$D/repo/adapters/claude-code/manifest.json" <<'MANIFEST_EOF'
{
  "schema_version": 1,
  "entries": [
    { "id": "session-honesty", "kind": "gate", "doctrine_file": null, "hooks": [], "events": [], "wired_template": false, "selftest": false, "jit_triggers": { "paths": [], "keywords": [] }, "blocking": true, "honest_status": "fixture stub", "budget_class": "none" },
    { "id": "work-integrity", "kind": "gate", "doctrine_file": null, "hooks": [], "events": [], "wired_template": false, "selftest": false, "jit_triggers": { "paths": [], "keywords": [] }, "blocking": true, "honest_status": "fixture stub", "budget_class": "none" },
    { "id": "new-blocking-gate-not-grandfathered", "kind": "gate", "doctrine_file": null, "hooks": [], "events": [], "wired_template": false, "selftest": false, "jit_triggers": { "paths": [], "keywords": [] }, "blocking": true, "honest_status": "fixture stub", "budget_class": "none" }
  ]
}
MANIFEST_EOF
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  OUT="$(_run_quick "$D")"; RC=$?
  _assert "deterministic-process-proof-grandfather-leak-red" 1 "$RC" "RED deterministic-process-proof.*new-blocking-gate-not-grandfathered" "$OUT"
  if printf '%s' "$OUT" | grep -qE "deterministic-process-proof: (session-honesty|work-integrity):"; then
    echo "self-test (deterministic-process-proof-grandfather-leak-no-false-red): FAIL (a grandfathered id RED'd — exempt-list leaked)" >&2
    FAILED=$((FAILED + 1))
  else
    echo "self-test (deterministic-process-proof-grandfather-leak-no-false-red): PASS" >&2
    PASSED=$((PASSED + 1))
  fi

  # ---- (RETIRED 2026-07-30, harness-reviewer M7) The scenario that used to
  # sit here asserted that declaring ONLY `chokepoint` stays GREEN, on the
  # reasoning that the doctrine's RED condition was "declaring neither". That
  # reasoning mechanized only half the obligation: a new blocking gate could
  # discharge it by naming a firing event and never enumerating one bypass,
  # while `bypass_paths` is the load-bearing half. Both halves are now
  # required, and the inverted scenarios live below as
  # `deterministic-process-proof-chokepoint-only-red` and its bypass-only
  # mirror. ----

  # ---- blocking:false entries are never checked, regardless of fields ----
  D=$(_scenario_dir dpp-nonblocking-green)
  _stamp_claim_honesty_green "$D"
  cat > "$D/repo/adapters/claude-code/manifest.json" <<'MANIFEST_EOF'
{
  "schema_version": 1,
  "entries": [
    { "id": "advisory-only-gate", "kind": "gate", "doctrine_file": null, "hooks": [], "events": [], "wired_template": false, "selftest": false, "jit_triggers": { "paths": [], "keywords": [] }, "blocking": false, "honest_status": "fixture stub", "budget_class": "none" }
  ]
}
MANIFEST_EOF
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  OUT="$(_run_quick "$D")"; RC=$?
  _assert "deterministic-process-proof-nonblocking-not-checked" 0 "$RC" "" "$OUT"

  # ---- ESCAPE-CLAUSE FIXTURES (harness-reviewer M6): the
  # `added_after < "2026-07"` exemption had ZERO coverage, so a BACKDATED
  # field silently exempted a brand-new blocking gate and nothing would have
  # noticed. Both sides of the boundary are now pinned. ----

  # A pre-cutover date with NEITHER field stays GREEN. This DOCUMENTS the
  # escape rather than endorsing it: the exemption exists so this file's own
  # dozens of throwaway fixtures (which conventionally set added_after
  # "2026-04") do not all flip RED. If this scenario ever fails, the exemption
  # was removed and those fixtures need revisiting.
  D=$(_scenario_dir dpp-backdated-green)
  _stamp_claim_honesty_green "$D"
  cat > "$D/repo/adapters/claude-code/manifest.json" <<'MANIFEST_EOF'
{
  "schema_version": 1,
  "entries": [
    { "id": "backdated-blocking-gate", "kind": "gate", "doctrine_file": null, "hooks": [], "events": [], "wired_template": false, "selftest": false, "jit_triggers": { "paths": [], "keywords": [] }, "blocking": true, "honest_status": "fixture stub", "budget_class": "none", "added_after": "2026-04" }
  ]
}
MANIFEST_EOF
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  OUT="$(_run_quick "$D")"; RC=$?
  _assert "deterministic-process-proof-backdated-exempt-green" 0 "$RC" "" "$OUT"

  # The BOUNDARY: exactly "2026-07" (the cutover month itself) is NOT exempt
  # and must RED. The comparison is a string `<`, so this pins the off-by-one
  # that would otherwise let the whole cutover month through.
  D=$(_scenario_dir dpp-boundary-red)
  _stamp_claim_honesty_green "$D"
  cat > "$D/repo/adapters/claude-code/manifest.json" <<'MANIFEST_EOF'
{
  "schema_version": 1,
  "entries": [
    { "id": "boundary-blocking-gate", "kind": "gate", "doctrine_file": null, "hooks": [], "events": [], "wired_template": false, "selftest": false, "jit_triggers": { "paths": [], "keywords": [] }, "blocking": true, "honest_status": "fixture stub", "budget_class": "none", "added_after": "2026-07", "golden_scenario": "fixture", "fp_expectation": "fixture", "retirement_condition": "fixture", "honesty_rationale": "fixture" }
  ]
}
MANIFEST_EOF
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  OUT="$(_run_quick "$D")"; RC=$?
  _assert "deterministic-process-proof-boundary-2026-07-red" 1 "$RC" "RED deterministic-process-proof.*boundary-blocking-gate" "$OUT"

  # ---- BOTH-FIELDS-REQUIRED (harness-reviewer M7): declaring only
  # `chokepoint` and never enumerating a bypass no longer discharges the
  # obligation. This scenario was previously asserted GREEN
  # ("deterministic-process-proof-partial-fields-still-green"); the inversion
  # IS the fix. ----
  D=$(_scenario_dir dpp-chokepoint-only-red)
  _stamp_claim_honesty_green "$D"
  cat > "$D/repo/adapters/claude-code/manifest.json" <<'MANIFEST_EOF'
{
  "schema_version": 1,
  "entries": [
    { "id": "new-blocking-gate-chokepoint-only", "kind": "gate", "doctrine_file": null, "hooks": [], "events": [], "wired_template": false, "selftest": false, "jit_triggers": { "paths": [], "keywords": [] }, "blocking": true, "honest_status": "fixture stub", "budget_class": "none", "chokepoint": "pre-push", "added_after": "2026-07", "golden_scenario": "fixture", "fp_expectation": "fixture", "retirement_condition": "fixture", "honesty_rationale": "fixture" }
  ]
}
MANIFEST_EOF
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  OUT="$(_run_quick "$D")"; RC=$?
  _assert "deterministic-process-proof-chokepoint-only-red" 1 "$RC" "RED deterministic-process-proof.*chokepoint-only.*bypass_paths" "$OUT"

  # And the mirror: bypass_paths with no chokepoint also REDs, naming the
  # missing half. Without this the "both required" claim would only be half
  # tested, which is the same class of gap M7 itself reported.
  D=$(_scenario_dir dpp-bypass-only-red)
  _stamp_claim_honesty_green "$D"
  cat > "$D/repo/adapters/claude-code/manifest.json" <<'MANIFEST_EOF'
{
  "schema_version": 1,
  "entries": [
    { "id": "new-blocking-gate-bypass-only", "kind": "gate", "doctrine_file": null, "hooks": [], "events": [], "wired_template": false, "selftest": false, "jit_triggers": { "paths": [], "keywords": [] }, "blocking": true, "honest_status": "fixture stub", "budget_class": "none", "bypass_paths": ["git push --no-verify -- NAMED-AND-ACCEPTED"], "added_after": "2026-07", "golden_scenario": "fixture", "fp_expectation": "fixture", "retirement_condition": "fixture", "honesty_rationale": "fixture" }
  ]
}
MANIFEST_EOF
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  OUT="$(_run_quick "$D")"; RC=$?
  _assert "deterministic-process-proof-bypass-only-red" 1 "$RC" "RED deterministic-process-proof.*bypass-only.*chokepoint" "$OUT"

  # ---- NODE/JQ PARITY (harness-reviewer C1 generalization): every dual-path
  # check in this file is re-run with `node` masked out of PATH and required
  # to produce byte-identical output. This is the regression test for the
  # ACTUAL defect (a jq branch that errored into silence) and, more
  # importantly, for its CLASS -- the four checks below are the complete set
  # of node-preferred/jq-fallback checks in this file. ----
  D=$(_scenario_dir dpp-jq-red)
  _stamp_claim_honesty_green "$D"
  cat > "$D/repo/adapters/claude-code/manifest.json" <<'MANIFEST_EOF'
{
  "schema_version": 1,
  "entries": [
    { "id": "new-blocking-gate-no-proof", "kind": "gate", "doctrine_file": null, "hooks": [], "events": [], "wired_template": false, "selftest": false, "jit_triggers": { "paths": [], "keywords": [] }, "blocking": true, "honest_status": "fixture stub", "budget_class": "none" }
  ]
}
MANIFEST_EOF
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  # want_nonempty=1: this fixture MUST report. An empty jq branch here is
  # precisely the C1 silent no-op.
  _assert_node_jq_parity "dpp-jq-parity-red" "$D" "deterministic-process-proof" 1

  D=$(_scenario_dir dpp-jq-grandfather)
  _stamp_claim_honesty_green "$D"
  cat > "$D/repo/adapters/claude-code/manifest.json" <<'MANIFEST_EOF'
{
  "schema_version": 1,
  "entries": [
    { "id": "session-honesty", "kind": "gate", "doctrine_file": null, "hooks": [], "events": [], "wired_template": false, "selftest": false, "jit_triggers": { "paths": [], "keywords": [] }, "blocking": true, "honest_status": "fixture stub", "budget_class": "none" },
    { "id": "new-blocking-gate-not-grandfathered", "kind": "gate", "doctrine_file": null, "hooks": [], "events": [], "wired_template": false, "selftest": false, "jit_triggers": { "paths": [], "keywords": [] }, "blocking": true, "honest_status": "fixture stub", "budget_class": "none" }
  ]
}
MANIFEST_EOF
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  # Exercises the grandfather-list lookup itself -- the exact expression that
  # drifted (`$gf | index(.id)` vs `$gf | index($e.id)`).
  _assert_node_jq_parity "dpp-jq-parity-grandfather" "$D" "deterministic-process-proof" 1

  D=$(_scenario_dir ngeb-jq-red)
  _stamp_claim_honesty_green "$D"
  cat > "$D/repo/adapters/claude-code/manifest.json" <<'MANIFEST_EOF'
{
  "schema_version": 1,
  "entries": [
    { "id": "new-gate-incomplete", "kind": "gate", "doctrine_file": null, "hooks": [], "events": [], "wired_template": false, "selftest": false, "jit_triggers": { "paths": [], "keywords": [] }, "blocking": true, "honest_status": "fixture stub", "budget_class": "none", "added_after": "2026-07", "chokepoint": "pre-push", "bypass_paths": ["--no-verify -- NAMED-AND-ACCEPTED"] }
  ]
}
MANIFEST_EOF
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  _assert_node_jq_parity "ngeb-jq-parity-red" "$D" "new-gate-evidence-bar" 1

  D=$(_scenario_dir c5-jq-red)
  if _copy_manifest_tooling "$D"; then :; fi
  _write_manifest_fixture "$D" no-honest
  # extract_manifest_gates is the dual-path helper behind claim-honesty.
  _assert_node_jq_parity "claim-honesty-jq-parity-red" "$D" "claim-honesty" 1

  D=$(_scenario_dir bc-jq-red)
  _stamp_claim_honesty_green "$D"
  _write_chain_settings "$D" "Stop" 7 "stop-dummy"
  # _count_chain_entries is the dual-path helper behind budget-chains.
  _assert_node_jq_parity "budget-chains-jq-parity-red" "$D" "budget-chains" 1

  # ---- Check: line-endings (NL-FINDING-038). RED fixture — a repo shell
  # surface carries CRLF bytes (the Wave-F F.1 whole-file-conversion class).
  # CR bytes are generated via printf escapes so this self-test's own source
  # stays LF-clean. ----
  D=$(_scenario_dir le-red)
  _stamp_claim_honesty_green "$D"
  printf '#!/bin/bash\r\nexit 0\r\n' > "$D/repo/adapters/claude-code/scripts/crlf-script.sh"
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  OUT="$(_run_quick "$D")"; RC=$?
  _assert "line-endings-red" 1 "$RC" "RED line-endings" "$OUT"

  # ---- Check: line-endings WARN fixture — LF-clean scripts but no
  # .gitattributes eol pin ----
  D=$(_scenario_dir le-warn)
  _stamp_claim_honesty_green "$D"
  printf '#!/bin/bash\nexit 0\n' > "$D/repo/adapters/claude-code/scripts/lf-script.sh"
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  OUT="$(_run_quick "$D")"; RC=$?
  _assert "line-endings-missing-pin-warns" 0 "$RC" "WARN line-endings" "$OUT"

  # ---- Check: line-endings GREEN fixture — LF scripts + the eol=lf pin ----
  D=$(_scenario_dir le-green)
  _stamp_claim_honesty_green "$D"
  printf '#!/bin/bash\nexit 0\n' > "$D/repo/adapters/claude-code/scripts/lf-script.sh"
  printf '*.sh text eol=lf\n' > "$D/repo/.gitattributes"
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  OUT="$(_run_quick "$D")"; RC=$?
  _assert "line-endings-green" 0 "$RC" "" "$OUT"

  # ---- Check: line-endings git-branch RED fixture — exercises the
  # PRODUCTION code path (git ls-files enumeration + -ef toplevel guard +
  # process-substitution RED propagation), which the glob-branch scenarios
  # above cannot reach (their fixture repos are plain directories).
  # git-init'd per NL-FINDING-029: hooksPath cleared so global hooks never
  # fire; autocrlf pinned off so the CRLF bytes written are the bytes kept;
  # `git add` (not commit) suffices for ls-files enumeration — no identity
  # config, no hook cost. ----
  D=$(_scenario_dir le-git-red)
  _stamp_claim_honesty_green "$D"
  if command -v git >/dev/null 2>&1 && git -C "$D/repo" init --quiet >/dev/null 2>&1; then
    git -C "$D/repo" config core.hooksPath ""
    git -C "$D/repo" config core.autocrlf false
    printf '#!/bin/bash\r\nexit 0\r\n' > "$D/repo/adapters/claude-code/scripts/crlf-tracked.sh"
    git -C "$D/repo" add -A >/dev/null 2>&1
    _write_settings "$D/live/settings.json"
    cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
    OUT="$(_run_quick "$D")"; RC=$?
    _assert "line-endings-git-red" 1 "$RC" "CR bytes in the working tree" "$OUT"
  else
    echo "self-test (line-endings-git-red): SKIP — git unavailable" >&2
    PASSED=$((PASSED + 1))
  fi

  # ---- Check: line-endings LIVE-MIRROR WARN fixture (LIVE-MIRROR-CRLF-01)
  # — repo tree is fully clean (LF scripts + eol=lf pin, i.e. what would
  # otherwise be the all-GREEN scenario) but the LIVE mirror's hooks/
  # directory carries CRLF, simulating a mirror built before the
  # .gitattributes pin landed. Must WARN, never RED — this is stale-mirror
  # drift self-healed by re-running install.sh, not an active break. ----
  D=$(_scenario_dir le-live-warn)
  _stamp_claim_honesty_green "$D"
  printf '#!/bin/bash\nexit 0\n' > "$D/repo/adapters/claude-code/scripts/lf-script.sh"
  printf '*.sh text eol=lf\n' > "$D/repo/.gitattributes"
  printf '#!/bin/bash\r\nexit 0\r\n' > "$D/live/hooks/crlf-live-hook.sh"
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  OUT="$(_run_quick "$D")"; RC=$?
  _assert "line-endings-live-mirror-warns" 0 "$RC" "WARN line-endings.*live mirror carries pre-pin CRLF" "$OUT"

  # ---- Check: line-endings LIVE-MIRROR WARN fixture, hooks/lib/ variant —
  # same as above but the CRLF lives under hooks/lib/ instead of hooks/
  # directly, exercising the second scanned glob. ----
  D=$(_scenario_dir le-live-warn-lib)
  _stamp_claim_honesty_green "$D"
  printf '#!/bin/bash\nexit 0\n' > "$D/repo/adapters/claude-code/scripts/lf-script.sh"
  printf '*.sh text eol=lf\n' > "$D/repo/.gitattributes"
  mkdir -p "$D/live/hooks/lib"
  printf '#!/bin/bash\r\nexit 0\r\n' > "$D/live/hooks/lib/crlf-live-lib.sh"
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  OUT="$(_run_quick "$D")"; RC=$?
  _assert "line-endings-live-mirror-lib-warns" 0 "$RC" "WARN line-endings.*live mirror carries pre-pin CRLF" "$OUT"

  # ---- Check: line-endings LIVE-MIRROR GREEN fixture — repo clean AND live
  # mirror LF-clean (post-install.sh-normalization steady state). No WARN,
  # no RED. ----
  D=$(_scenario_dir le-live-green)
  _stamp_claim_honesty_green "$D"
  printf '#!/bin/bash\nexit 0\n' > "$D/repo/adapters/claude-code/scripts/lf-script.sh"
  printf '*.sh text eol=lf\n' > "$D/repo/.gitattributes"
  printf '#!/bin/bash\nexit 0\n' > "$D/live/hooks/lf-live-hook.sh"
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  OUT="$(_run_quick "$D")"; RC=$?
  _assert "line-endings-live-mirror-green" 0 "$RC" "" "$OUT"

  # ---- Check: line-endings LIVE-MIRROR CRLF must never RED, even when
  # combined with an otherwise-red-triggering repo scenario elsewhere in the
  # same run — verifies the live-mirror predicate is additive-WARN-only and
  # cannot itself flip RC to 1. Reuses the le-red repo-CRLF fixture's repo
  # side (which legitimately RC=1s on its own) is NOT what this asserts;
  # instead this scenario keeps the repo clean and only pollutes live, then
  # asserts RC=0 (no RED) while still asserting the WARN text fired. ----
  D=$(_scenario_dir le-live-warn-not-red)
  _stamp_claim_honesty_green "$D"
  printf '#!/bin/bash\nexit 0\n' > "$D/repo/adapters/claude-code/scripts/lf-script.sh"
  printf '*.sh text eol=lf\n' > "$D/repo/.gitattributes"
  printf '#!/bin/bash\r\nexit 0\r\n' > "$D/live/scripts/crlf-live-script.sh"
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  OUT="$(_run_quick "$D")"; RC=$?
  _assert "line-endings-live-mirror-never-red" 0 "$RC" "WARN line-endings" "$OUT"
  if printf '%s' "$OUT" | grep -q "RED line-endings"; then
    echo "self-test (line-endings-live-mirror-never-red-strict): FAIL (unexpected RED line-endings in output)" >&2
    FAILED=$((FAILED + 1))
  else
    echo "self-test (line-endings-live-mirror-never-red-strict): PASS" >&2
    PASSED=$((PASSED + 1))
  fi

  # ============================================================
  # NL Observability Program Wave O, task O.6 (specs-o §O.6) — RED/GREEN
  # self-test scenarios for the six pipeline-health predicates. Spliced
  # from tests/fixtures/wave-o/O.6/doctor-predicate.md (orchestrator
  # integration, batch 2).
  # ============================================================

  # ---- obs-writers-firing: RED — stamp claims MORE lines / LATER mtime
  # than the real file currently has (not-grown-since-last-check) ----
  D=$(_scenario_dir o6-writers-red)
  _stamp_claim_honesty_green "$D"
  mkdir -p "$D/live/state/doctor-cache"
  printf '{"gate":"x","event":"block","ts":"2026-01-01T00:00:00Z"}\n' > "$D/live/state/signal-ledger.jsonl"
  touch "$D/live/state/signal-ledger.jsonl"
  now_epoch=$(date -u +%s 2>/dev/null || echo 0)
  printf '%s %s\n' "$((now_epoch + 100))" "999" > "$D/live/state/doctor-cache/obs-ledger-stamp.txt"
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  OUT="$(_run_quick "$D")"; RC=$?
  _assert "o6-obs-writers-firing-red" 1 "$RC" "RED obs-writers-firing" "$OUT"

  # ---- obs-writers-firing: GREEN — no pre-existing stamp (first-run
  # seeds the baseline, does not fail) ----
  D=$(_scenario_dir o6-writers-green)
  _stamp_claim_honesty_green "$D"
  mkdir -p "$D/live/state"
  printf '{"gate":"x","event":"block","ts":"2026-01-01T00:00:00Z"}\n' > "$D/live/state/signal-ledger.jsonl"
  touch "$D/live/state/signal-ledger.jsonl"
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  OUT="$(_run_quick "$D")"; RC=$?
  if printf '%s' "$OUT" | grep -q "RED obs-writers-firing"; then
    echo "self-test (o6-obs-writers-firing-green): FAIL (unexpected RED)" >&2
    FAILED=$((FAILED + 1))
  else
    echo "self-test (o6-obs-writers-firing-green): PASS" >&2
    PASSED=$((PASSED + 1))
  fi

  # ---- obs-heartbeats-fresh: RED — a fresh transcript with a missing
  # heartbeat file, per-sid naming branch (heartbeats dir EXISTS but the
  # specific sid's file does not — distinct from the "no heartbeats dir
  # at all" branch, which has its own message and is covered by a
  # separate assertion below) ----
  D=$(_scenario_dir o6-hb-red)
  _stamp_claim_honesty_green "$D"
  mkdir -p "$D/transcripts/proj" "$D/live/state/heartbeats"
  printf '{}\n' > "$D/transcripts/proj/sess-live.jsonl"
  touch "$D/transcripts/proj/sess-live.jsonl"
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  OUT="$(OBS_TRANSCRIPTS_DIR="$D/transcripts" _run_quick "$D")"; RC=$?
  _assert "o6-obs-heartbeats-fresh-red" 1 "$RC" "RED obs-heartbeats-fresh" "$OUT"
  if ! printf '%s' "$OUT" | grep -q "sess-live:missing"; then
    echo "self-test (o6-obs-heartbeats-fresh-red-names-sid): FAIL (did not name sess-live:missing)" >&2
    FAILED=$((FAILED + 1))
  else
    echo "self-test (o6-obs-heartbeats-fresh-red-names-sid): PASS" >&2
    PASSED=$((PASSED + 1))
  fi

  # ---- obs-heartbeats-fresh: GREEN — a fresh transcript WITH a fresh
  # heartbeat file, plus the zero-live-sessions GREEN case ----
  D=$(_scenario_dir o6-hb-green)
  _stamp_claim_honesty_green "$D"
  mkdir -p "$D/transcripts/proj" "$D/live/state/heartbeats"
  printf '{}\n' > "$D/transcripts/proj/sess-live.jsonl"
  touch "$D/transcripts/proj/sess-live.jsonl"
  printf '{"schema":1,"session_id":"sess-live"}\n' > "$D/live/state/heartbeats/sess-live.json"
  touch "$D/live/state/heartbeats/sess-live.json"
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  OUT="$(OBS_TRANSCRIPTS_DIR="$D/transcripts" _run_quick "$D")"; RC=$?
  if printf '%s' "$OUT" | grep -q "RED obs-heartbeats-fresh"; then
    echo "self-test (o6-obs-heartbeats-fresh-green): FAIL (unexpected RED)" >&2
    FAILED=$((FAILED + 1))
  else
    echo "self-test (o6-obs-heartbeats-fresh-green): PASS" >&2
    PASSED=$((PASSED + 1))
  fi
  D=$(_scenario_dir o6-hb-green-idle)
  _stamp_claim_honesty_green "$D"
  mkdir -p "$D/transcripts"
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  OUT="$(OBS_TRANSCRIPTS_DIR="$D/transcripts" _run_quick "$D")"; RC=$?
  if printf '%s' "$OUT" | grep -q "RED obs-heartbeats-fresh"; then
    echo "self-test (o6-obs-heartbeats-fresh-green-idle): FAIL (unexpected RED on zero live sessions)" >&2
    FAILED=$((FAILED + 1))
  else
    echo "self-test (o6-obs-heartbeats-fresh-green-idle): PASS" >&2
    PASSED=$((PASSED + 1))
  fi

  # ---- obs-heartbeats-fresh: GREEN (RED-fixture-adjacent) — a fresh
  # SUBAGENT transcript (under <sid>/subagents/) and a fresh WORKFLOW
  # sub-transcript (under <sid>/workflows/), neither with any heartbeat
  # file anywhere, must stay GREEN. Subagent/workflow transcripts are not
  # independent sessions and never get their own heartbeat writer; before
  # this fix, this exact fixture false-REDed (verifier-round FAIL, O.6
  # conf 9) ----
  D=$(_scenario_dir o6-hb-green-subagent)
  _stamp_claim_honesty_green "$D"
  mkdir -p "$D/transcripts/proj/parent-sid/subagents" "$D/transcripts/proj/parent-sid/workflows"
  printf '{}\n' > "$D/transcripts/proj/parent-sid/subagents/sub-sid.jsonl"
  touch "$D/transcripts/proj/parent-sid/subagents/sub-sid.jsonl"
  printf '{}\n' > "$D/transcripts/proj/parent-sid/workflows/wf-sid.jsonl"
  touch "$D/transcripts/proj/parent-sid/workflows/wf-sid.jsonl"
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  OUT="$(OBS_TRANSCRIPTS_DIR="$D/transcripts" _run_quick "$D")"; RC=$?
  if printf '%s' "$OUT" | grep -q "RED obs-heartbeats-fresh"; then
    echo "self-test (o6-obs-heartbeats-fresh-green-subagent): FAIL (unexpected RED on subagent/workflow-only transcripts with no heartbeats)" >&2
    FAILED=$((FAILED + 1))
  else
    echo "self-test (o6-obs-heartbeats-fresh-green-subagent): PASS" >&2
    PASSED=$((PASSED + 1))
  fi

  # ---- obs-heartbeats-fresh: GREEN — CANONICAL-ORACLE FIX (O.6
  # re-verifier round, FAIL conf 9, duplicated-staleness-oracle / mid-turn
  # false-stall). A FRESH transcript (touched to now) whose matching
  # heartbeat file has a last_activity_ts 45 minutes old (stale by raw
  # mtime/JSON-timestamp math alone — simulates a long tool-heavy turn
  # with no Stop-time touch yet) and a pid that is genuinely alive (this
  # self-test process's own $$). Before this fix, the predicate computed
  # heartbeat staleness from the heartbeat file's own mtime/age alone and
  # would have false-REDed this exact shape ("sess-midturn:45min"). After
  # the fix (sourcing hooks/lib/session-heartbeat-lib.sh and calling
  # hb_classify, which joins against transcript mtime per contract C1),
  # this must classify `live` (not `missing`) and stay GREEN — proving a
  # long-running turn no longer false-stalls its own session. ----
  D=$(_scenario_dir o6-hb-green-midturn)
  _stamp_claim_honesty_green "$D"
  mkdir -p "$D/transcripts/proj" "$D/live/state/heartbeats"
  printf '{"type":"assistant","message":{"usage":{"input_tokens":1,"output_tokens":1}}}\n' > "$D/transcripts/proj/sess-midturn.jsonl"
  touch "$D/transcripts/proj/sess-midturn.jsonl"
  OLD_TS="$(date -u -d '45 minutes ago' '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u -v-45M '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || echo '2020-01-01T00:00:00Z')"
  cat > "$D/live/state/heartbeats/sess-midturn.json" <<EOF
{"schema":1,"session_id":"sess-midturn","pid":$$,"cwd":"/x","repo_root":"/x","worktree_root":"/x","branch":"main","model":"sonnet","last_activity_ts":"${OLD_TS}","last_event":"turn-end","marker_state":"none"}
EOF
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  OUT="$(OBS_TRANSCRIPTS_DIR="$D/transcripts" _run_quick "$D")"; RC=$?
  if printf '%s' "$OUT" | grep -q "RED obs-heartbeats-fresh"; then
    echo "self-test (o6-obs-heartbeats-fresh-green-midturn): FAIL (unexpected RED — a fresh transcript with a stale-by-mtime-but-present heartbeat must classify live via the canonical oracle's transcript join, not false-stall)" >&2
    FAILED=$((FAILED + 1))
  else
    echo "self-test (o6-obs-heartbeats-fresh-green-midturn): PASS" >&2
    PASSED=$((PASSED + 1))
  fi

  # ---- obs-scheduled-tasks: RED — SCHTASKS_CMD stub reports a bad Last
  # Result code.
  #
  # ORCHESTRATOR FIX: the fragment's own RED/GREEN fixture instructions
  # described SCHTASKS_CMD as a path to an executable stub printing
  # "name<TAB>code" lines. That does not match the REAL script
  # (scripts/scheduled-task-health.sh): SCHTASKS_CMD is `eval`'d as a full
  # shell COMMAND STRING (see _sth_query_output), and its expected output
  # is the RAW `schtasks /Query /V /FO LIST` block format (`TaskName:` /
  # `Last Result:` label lines, task name prefixed with a literal `\`),
  # which _sth_parse_and_filter then reduces to the tab-separated
  # name/code pairs. The original fixtures silently produced zero output
  # (found running this predicate's own scenarios) rather than failing
  # loudly — corrected to the real interface, matching the script's own
  # --self-test fixture shape exactly. ----
  D=$(_scenario_dir o6-sched-red)
  _stamp_claim_honesty_green "$D"
  mkdir -p "$D/repo/adapters/claude-code/scripts"
  cp "$SCRIPT_DIR/../scripts/scheduled-task-health.sh" "$D/repo/adapters/claude-code/scripts/scheduled-task-health.sh" 2>/dev/null
  if [[ -f "$D/repo/adapters/claude-code/scripts/scheduled-task-health.sh" ]]; then
    SCHED_FIXTURE_RED=$(cat <<'EOF'
Folder: \
TaskName:                             \NL-fixture-task
Last Result:                          -2147024894
EOF
)
    _write_settings "$D/live/settings.json"
    cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
    OUT="$(SCHTASKS_CMD="printf '%s\n' '${SCHED_FIXTURE_RED}'" _run_quick "$D")"; RC=$?
    _assert "o6-obs-scheduled-tasks-red" 1 "$RC" "RED obs-scheduled-tasks" "$OUT"
    if ! printf '%s' "$OUT" | grep -q "NL-fixture-task"; then
      echo "self-test (o6-obs-scheduled-tasks-red-names-task): FAIL (did not name NL-fixture-task)" >&2
      FAILED=$((FAILED + 1))
    else
      echo "self-test (o6-obs-scheduled-tasks-red-names-task): PASS" >&2
      PASSED=$((PASSED + 1))
    fi
  else
    echo "self-test (o6-obs-scheduled-tasks-red): SKIP (scheduled-task-health.sh not present next to this doctor)" >&2
  fi

  # ---- obs-scheduled-tasks: GREEN — Last Result=0, plus the
  # absent-script WARN-not-RED case ----
  D=$(_scenario_dir o6-sched-green)
  _stamp_claim_honesty_green "$D"
  mkdir -p "$D/repo/adapters/claude-code/scripts"
  cp "$SCRIPT_DIR/../scripts/scheduled-task-health.sh" "$D/repo/adapters/claude-code/scripts/scheduled-task-health.sh" 2>/dev/null
  if [[ -f "$D/repo/adapters/claude-code/scripts/scheduled-task-health.sh" ]]; then
    SCHED_FIXTURE_GREEN=$(cat <<'EOF'
Folder: \
TaskName:                             \NL-fixture-task
Last Result:                          0
EOF
)
    _write_settings "$D/live/settings.json"
    cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
    OUT="$(SCHTASKS_CMD="printf '%s\n' '${SCHED_FIXTURE_GREEN}'" _run_quick "$D")"; RC=$?
    if printf '%s' "$OUT" | grep -q "RED obs-scheduled-tasks"; then
      echo "self-test (o6-obs-scheduled-tasks-green): FAIL (unexpected RED)" >&2
      FAILED=$((FAILED + 1))
    else
      echo "self-test (o6-obs-scheduled-tasks-green): PASS" >&2
      PASSED=$((PASSED + 1))
    fi
  else
    echo "self-test (o6-obs-scheduled-tasks-green): SKIP (scheduled-task-health.sh not present next to this doctor)" >&2
  fi
  D=$(_scenario_dir o6-sched-absent)
  _stamp_claim_honesty_green "$D"
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  OUT="$(_run_quick "$D")"; RC=$?
  if printf '%s' "$OUT" | grep -q "RED obs-scheduled-tasks"; then
    echo "self-test (o6-obs-scheduled-tasks-absent-script-green): FAIL (unexpected RED when script absent)" >&2
    FAILED=$((FAILED + 1))
  else
    echo "self-test (o6-obs-scheduled-tasks-absent-script-green): PASS" >&2
    PASSED=$((PASSED + 1))
  fi

  # ---- obs-consumer-map: RED — map missing an event type + an entry
  # with zero consumers ----
  D=$(_scenario_dir o6-map-red)
  _stamp_claim_honesty_green "$D"
  cat > "$D/repo/adapters/claude-code/observability-consumer-map.json" <<'EOF'
{"schema":1,"event_types":{"block":{"consumers":["digest:x"]},"empty-one":{"consumers":[]}}}
EOF
  mkdir -p "$D/repo/adapters/claude-code/hooks"
  printf '#!/bin/bash\nledger_emit "my-gate" "warn" "detail"\n' > "$D/repo/adapters/claude-code/hooks/fixture-hook.sh"
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  if command -v jq >/dev/null 2>&1; then
    OUT="$(_run_quick "$D")"; RC=$?
    _assert "o6-obs-consumer-map-red" 1 "$RC" "RED obs-consumer-map" "$OUT"
    if ! printf '%s' "$OUT" | grep -q "warn"; then
      echo "self-test (o6-obs-consumer-map-red-names-warn): FAIL (did not name the unmapped 'warn' literal)" >&2
      FAILED=$((FAILED + 1))
    else
      echo "self-test (o6-obs-consumer-map-red-names-warn): PASS" >&2
      PASSED=$((PASSED + 1))
    fi
    if ! printf '%s' "$OUT" | grep -q "empty-one"; then
      echo "self-test (o6-obs-consumer-map-red-names-zero-consumer-entry): FAIL (did not name empty-one)" >&2
      FAILED=$((FAILED + 1))
    else
      echo "self-test (o6-obs-consumer-map-red-names-zero-consumer-entry): PASS" >&2
      PASSED=$((PASSED + 1))
    fi
  else
    echo "self-test (o6-obs-consumer-map-red): SKIP (jq unavailable)" >&2
  fi

  # ---- obs-consumer-map: GREEN — map covers every literal + every entry
  # has >=1 consumer ----
  D=$(_scenario_dir o6-map-green)
  _stamp_claim_honesty_green "$D"
  cat > "$D/repo/adapters/claude-code/observability-consumer-map.json" <<'EOF'
{"schema":1,"event_types":{"block":{"consumers":["digest:x"]},"warn":{"consumers":["digest:x"]}}}
EOF
  mkdir -p "$D/repo/adapters/claude-code/hooks"
  printf '#!/bin/bash\nledger_emit "my-gate" "warn" "detail"\n' > "$D/repo/adapters/claude-code/hooks/fixture-hook.sh"
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  if command -v jq >/dev/null 2>&1; then
    OUT="$(_run_quick "$D")"; RC=$?
    if printf '%s' "$OUT" | grep -q "RED obs-consumer-map"; then
      echo "self-test (o6-obs-consumer-map-green): FAIL (unexpected RED)" >&2
      FAILED=$((FAILED + 1))
    else
      echo "self-test (o6-obs-consumer-map-green): PASS" >&2
      PASSED=$((PASSED + 1))
    fi
  else
    echo "self-test (o6-obs-consumer-map-green): SKIP (jq unavailable)" >&2
  fi

  # ---- obs-cockpit-fresh fixtures. Shared shape: cockpit code present,
  # ensure-cockpit.sh installed, fresh heartbeat (sessions live), Windows
  # asserted via OBS_COCKPIT_UNAME_OVERRIDE (so this suite also runs on
  # Linux CI), curl PATH-stubbed to script the /api/health probe. ----
  _cockpit_fixture() {
    # $1 = scenario label; $2 = curl stub body (printf format, may be
    # empty); $3 = curl stub exit code.
    local d
    d=$(_scenario_dir "$1")
    mkdir -p "$d/repo/neural-lace/workstreams-ui/server" "$d/live/state/heartbeats" \
             "$d/live/scripts" "$d/fakebin"
    printf 'stub\n' > "$d/repo/neural-lace/workstreams-ui/server/server.js"
    printf '#!/bin/bash\n# fixture stub of ensure-cockpit.sh\n' > "$d/live/scripts/ensure-cockpit.sh"
    printf '{"schema":1}\n' > "$d/live/state/heartbeats/sess-x.json"
    touch "$d/live/state/heartbeats/sess-x.json"
    printf '#!/bin/bash\nprintf %%s '\''%s'\''\nexit %s\n' "$2" "$3" > "$d/fakebin/curl"
    chmod +x "$d/fakebin/curl"
    _write_settings "$d/live/settings.json"
    cp "$d/live/settings.json" "$d/repo/adapters/claude-code/settings.json.template"
    printf '%s\n' "$d"
  }

  # ---- obs-cockpit-fresh: WARN — cockpit down (curl stub exits 7 with
  # no body, curl's real connection-refused code) while sessions live.
  # Down is a WARN, never RED (the RED tier is reserved for the
  # lobotomized state below). The [56] naming-drift bug made this WARN
  # unreachable (schtask gate nothing registered; stamp file nothing
  # wrote) — prove it actually fires. ----
  D=$(_cockpit_fixture o6-cockpit-warn "" 7)
  OUT="$(PATH="$D/fakebin:$PATH" OBS_COCKPIT_UNAME_OVERRIDE=MINGW64_NT-fixture _run_quick "$D")"; RC=$?
  if printf '%s' "$OUT" | grep -q "RED obs-cockpit-fresh"; then
    echo "self-test (o6-obs-cockpit-fresh-down-not-red): FAIL (down must WARN, not RED)" >&2
    FAILED=$((FAILED + 1))
  else
    echo "self-test (o6-obs-cockpit-fresh-down-not-red): PASS" >&2
    PASSED=$((PASSED + 1))
  fi
  _assert "o6-obs-cockpit-fresh-warn-rc" 0 "$RC" "" "$OUT"
  if printf '%s' "$OUT" | grep -q "WARN obs-cockpit-fresh"; then
    echo "self-test (o6-obs-cockpit-fresh-warn-fires): PASS" >&2
    PASSED=$((PASSED + 1))
  else
    echo "self-test (o6-obs-cockpit-fresh-warn-fires): FAIL (mechanism installed + live session + probe down did not WARN)" >&2
    FAILED=$((FAILED + 1))
  fi

  # ---- obs-cockpit-fresh: RED — the golden scenario (2026-07-09
  # all-day-lobotomized cockpit with zero doctor signal): /api/health
  # answers 200 with "lobotomized":true -> must RED and fail --quick ----
  D=$(_cockpit_fixture o6-cockpit-red-lobotomized \
      '{"ok":true,"any_pane_failed":true,"lobotomized":true,"oldest_pane_age_ms":900000}' 0)
  OUT="$(PATH="$D/fakebin:$PATH" OBS_COCKPIT_UNAME_OVERRIDE=MINGW64_NT-fixture _run_quick "$D")"; RC=$?
  _assert "o6-obs-cockpit-fresh-red-lobotomized" 1 "$RC" "RED obs-cockpit-fresh" "$OUT"

  # ---- obs-cockpit-fresh: WARN — unrecognized responder (harness-review
  # Major 2026-07-09): something answers 200 on :7733 but the body lacks
  # the any_pane_failed health marker (foreign listener / proxy error
  # page / pre-O.4 build). Must WARN, never GREEN — grading an
  # unidentified responder healthy is the silent-GREEN class this check
  # exists to kill. ----
  D=$(_cockpit_fixture o6-cockpit-warn-unrecognized-responder \
      '<html>totally not a cockpit</html>' 0)
  OUT="$(PATH="$D/fakebin:$PATH" OBS_COCKPIT_UNAME_OVERRIDE=MINGW64_NT-fixture _run_quick "$D")"; RC=$?
  if printf '%s' "$OUT" | grep -q "WARN obs-cockpit-fresh.*unrecognized listener"; then
    echo "self-test (o6-obs-cockpit-fresh-unrecognized-warns): PASS" >&2
    PASSED=$((PASSED + 1))
  else
    echo "self-test (o6-obs-cockpit-fresh-unrecognized-warns): FAIL (non-cockpit responder must WARN as unrecognized, not pass silently)" >&2
    FAILED=$((FAILED + 1))
  fi
  if printf '%s' "$OUT" | grep -q "RED obs-cockpit-fresh"; then
    echo "self-test (o6-obs-cockpit-fresh-unrecognized-not-red): FAIL (unrecognized responder must cap at WARN)" >&2
    FAILED=$((FAILED + 1))
  else
    echo "self-test (o6-obs-cockpit-fresh-unrecognized-not-red): PASS" >&2
    PASSED=$((PASSED + 1))
  fi
  _assert "o6-obs-cockpit-fresh-unrecognized-rc" 0 "$RC" "" "$OUT"

  # ---- obs-cockpit-fresh: WARN — older server build (lobotomized field
  # ABSENT) with any_pane_failed:true -> WARN fallback, never RED ----
  D=$(_cockpit_fixture o6-cockpit-warn-legacy-panefail \
      '{"ok":true,"any_pane_failed":true,"oldest_pane_age_ms":900000}' 0)
  OUT="$(PATH="$D/fakebin:$PATH" OBS_COCKPIT_UNAME_OVERRIDE=MINGW64_NT-fixture _run_quick "$D")"; RC=$?
  if printf '%s' "$OUT" | grep -q "RED obs-cockpit-fresh"; then
    echo "self-test (o6-obs-cockpit-fresh-legacy-panefail-not-red): FAIL (lobotomized-absent must cap at WARN)" >&2
    FAILED=$((FAILED + 1))
  else
    echo "self-test (o6-obs-cockpit-fresh-legacy-panefail-not-red): PASS" >&2
    PASSED=$((PASSED + 1))
  fi
  _assert "o6-obs-cockpit-fresh-legacy-panefail-warn" 0 "$RC" "WARN obs-cockpit-fresh" "$OUT"

  # ---- obs-cockpit-fresh: GREEN — healthy cockpit (200, lobotomized
  # false, no pane failed): must NOT fire. This is the operator's normal
  # state — the false-positive guard for the probe design ----
  D=$(_cockpit_fixture o6-cockpit-green-up \
      '{"ok":true,"any_pane_failed":false,"lobotomized":false,"oldest_pane_age_ms":5000}' 0)
  OUT="$(PATH="$D/fakebin:$PATH" OBS_COCKPIT_UNAME_OVERRIDE=MINGW64_NT-fixture _run_quick "$D")"; RC=$?
  if printf '%s' "$OUT" | grep -qE "(RED|WARN) obs-cockpit-fresh"; then
    echo "self-test (o6-obs-cockpit-fresh-green-up): FAIL (fired although the cockpit is healthy)" >&2
    FAILED=$((FAILED + 1))
  else
    echo "self-test (o6-obs-cockpit-fresh-green-up): PASS" >&2
    PASSED=$((PASSED + 1))
  fi
  _assert "o6-obs-cockpit-fresh-green-up-rc" 0 "$RC" "" "$OUT"

  # ---- obs-cockpit-fresh: GREEN — transient pane failure on a NEW
  # server build (any_pane_failed:true but lobotomized PRESENT and
  # false): the server's uptime>120s judgment says transient -> silent.
  # This is the expected-false-positive guard from the gate-change
  # record. ----
  D=$(_cockpit_fixture o6-cockpit-green-transient \
      '{"ok":true,"any_pane_failed":true,"lobotomized":false,"oldest_pane_age_ms":5000}' 0)
  OUT="$(PATH="$D/fakebin:$PATH" OBS_COCKPIT_UNAME_OVERRIDE=MINGW64_NT-fixture _run_quick "$D")"; RC=$?
  if printf '%s' "$OUT" | grep -qE "(RED|WARN) obs-cockpit-fresh"; then
    echo "self-test (o6-obs-cockpit-fresh-green-transient): FAIL (fired on lobotomized:false transient)" >&2
    FAILED=$((FAILED + 1))
  else
    echo "self-test (o6-obs-cockpit-fresh-green-transient): PASS" >&2
    PASSED=$((PASSED + 1))
  fi
  _assert "o6-obs-cockpit-fresh-green-transient-rc" 0 "$RC" "" "$OUT"

  # ---- obs-cockpit-fresh: GREEN — operator kill-switch: RED-shaped
  # probe (lobotomized:true) but ${live}/local/cockpit-disabled present
  # -> deliberately off, must stay silent ----
  D=$(_cockpit_fixture o6-cockpit-green-killswitch \
      '{"ok":true,"any_pane_failed":true,"lobotomized":true}' 0)
  touch "$D/live/local/cockpit-disabled"
  OUT="$(PATH="$D/fakebin:$PATH" OBS_COCKPIT_UNAME_OVERRIDE=MINGW64_NT-fixture _run_quick "$D")"; RC=$?
  if printf '%s' "$OUT" | grep -qE "(RED|WARN) obs-cockpit-fresh"; then
    echo "self-test (o6-obs-cockpit-fresh-green-killswitch): FAIL (fired despite cockpit-disabled kill-switch)" >&2
    FAILED=$((FAILED + 1))
  else
    echo "self-test (o6-obs-cockpit-fresh-green-killswitch): PASS" >&2
    PASSED=$((PASSED + 1))
  fi
  _assert "o6-obs-cockpit-fresh-green-killswitch-rc" 0 "$RC" "" "$OUT"

  # ---- obs-cockpit-fresh: GREEN — non-Windows OS gate: RED-shaped
  # probe but uname says Linux -> cockpit cannot run there, must stay
  # silent ----
  D=$(_cockpit_fixture o6-cockpit-green-nonwindows \
      '{"ok":true,"any_pane_failed":true,"lobotomized":true}' 0)
  OUT="$(PATH="$D/fakebin:$PATH" OBS_COCKPIT_UNAME_OVERRIDE=Linux _run_quick "$D")"; RC=$?
  if printf '%s' "$OUT" | grep -qE "(RED|WARN) obs-cockpit-fresh"; then
    echo "self-test (o6-obs-cockpit-fresh-green-nonwindows): FAIL (fired on a non-Windows host)" >&2
    FAILED=$((FAILED + 1))
  else
    echo "self-test (o6-obs-cockpit-fresh-green-nonwindows): PASS" >&2
    PASSED=$((PASSED + 1))
  fi
  _assert "o6-obs-cockpit-fresh-green-nonwindows-rc" 0 "$RC" "" "$OUT"

  # ---- obs-cockpit-fresh: GREEN — mechanism-absent gate (nl-issue [56]
  # regression): cockpit dir present, sessions live, probe would fail,
  # but NO live scripts/ensure-cockpit.sh -> cockpit is not expected on
  # this machine; the check must stay silent ----
  D=$(_cockpit_fixture o6-cockpit-green-nomech "" 7)
  rm -f "$D/live/scripts/ensure-cockpit.sh"
  OUT="$(PATH="$D/fakebin:$PATH" OBS_COCKPIT_UNAME_OVERRIDE=MINGW64_NT-fixture _run_quick "$D")"; RC=$?
  if printf '%s' "$OUT" | grep -qE "(RED|WARN) obs-cockpit-fresh"; then
    echo "self-test (o6-obs-cockpit-fresh-green-nomech): FAIL (fired without ensure-cockpit.sh installed)" >&2
    FAILED=$((FAILED + 1))
  else
    echo "self-test (o6-obs-cockpit-fresh-green-nomech): PASS" >&2
    PASSED=$((PASSED + 1))
  fi
  _assert "o6-obs-cockpit-fresh-green-nomech-rc" 0 "$RC" "" "$OUT"

  # ---- obs-cockpit-fresh: GREEN — the common case (workstreams-ui not
  # installed at all) ----
  D=$(_scenario_dir o6-cockpit-green)
  _stamp_claim_honesty_green "$D"
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  OUT="$(_run_quick "$D")"; RC=$?
  if printf '%s' "$OUT" | grep -qE "(RED|WARN) obs-cockpit-fresh"; then
    echo "self-test (o6-obs-cockpit-fresh-green-absent): FAIL (unexpected RED/WARN when workstreams-ui/server absent)" >&2
    FAILED=$((FAILED + 1))
  else
    echo "self-test (o6-obs-cockpit-fresh-green-absent): PASS" >&2
    PASSED=$((PASSED + 1))
  fi

  # ==========================================================
  # ask-rooted-workstreams-p1 Task 17(a)/(b) — obs-cockpit-fresh EXTENSION
  # fixtures. Same _scenario_dir base + Windows-override + a MULTI-URL curl
  # stub answering /api/health (clean, so the else branch is reached),
  # /api/asks, and /api/diagnostics/drift independently. Predicates
  # fail-closed: a seeded schema-failure / reconciliation-mismatch -> RED
  # BEFORE the clean case is trusted GREEN (plan Testing Strategy §Doctor).
  # ==========================================================
  _cockpit_multi_fixture() {
    # $1=label $2=health_body $3=asks_body $4=drift_body (all clean-JSON,
    # no embedded single-quotes so the single-quote wrapping below is safe).
    local d
    d=$(_scenario_dir "$1")
    mkdir -p "$d/repo/neural-lace/workstreams-ui/server" "$d/live/state/heartbeats" \
             "$d/live/scripts" "$d/fakebin"
    printf 'stub\n' > "$d/repo/neural-lace/workstreams-ui/server/server.js"
    printf '#!/bin/bash\n# fixture stub of ensure-cockpit.sh\n' > "$d/live/scripts/ensure-cockpit.sh"
    printf '{"schema":1}\n' > "$d/live/state/heartbeats/sess-x.json"
    touch "$d/live/state/heartbeats/sess-x.json"
    {
      printf '#!/bin/bash\n'
      printf 'url="${@: -1}"\n'
      printf 'case "$url" in\n'
      printf "  *api/asks*) printf %%s '%s' ;;\n" "$3"
      printf "  *api/diagnostics/drift*) printf %%s '%s' ;;\n" "$4"
      printf "  *) printf %%s '%s' ;;\n" "$2"
      printf 'esac\n'
      printf 'exit 0\n'
    } > "$d/fakebin/curl"
    chmod +x "$d/fakebin/curl"
    _write_settings "$d/live/settings.json"
    cp "$d/live/settings.json" "$d/repo/adapters/claude-code/settings.json.template"
    printf '%s\n' "$d"
  }

  # Bare assignments (NOT `local`): this block is the top-level
  # `if [[ --self-test ]]` scope, not a function — `local` here is a
  # runtime error.
  CLEAN_HEALTH='{"ok":true,"any_pane_failed":false,"lobotomized":false,"oldest_pane_age_ms":5000}'
  CLEAN_ASKS='{"ok":true,"status_filter":"active","groups":[]}'
  CLEAN_DRIFT='{"ok":true,"count_reconciliation":{"mismatch":false,"ledger_open_count":1,"rendered_waiting_count":1}}'

  # ---- Task 17(a): GREEN — healthy cockpit + clean /api/asks schema +
  # clean reconciliation must NOT fire the extension (false-positive guard).
  D=$(_cockpit_multi_fixture o6-cockpit-t17-green "$CLEAN_HEALTH" "$CLEAN_ASKS" "$CLEAN_DRIFT")
  OUT="$(PATH="$D/fakebin:$PATH" OBS_COCKPIT_UNAME_OVERRIDE=MINGW64_NT-fixture _run_quick "$D")"; RC=$?
  if printf '%s' "$OUT" | grep -qE "(RED|WARN) obs-cockpit-fresh"; then
    echo "self-test (o6-cockpit-t17-extension-green): FAIL (extension fired on a clean cockpit/schema/reconciliation)" >&2
    FAILED=$((FAILED + 1))
  else
    echo "self-test (o6-cockpit-t17-extension-green): PASS" >&2
    PASSED=$((PASSED + 1))
  fi

  # ---- Task 17(a): RED — /api/asks returns the server's own
  # schema-validation-failure verdict (anti-noise/absolute-href) -> RED.
  D=$(_cockpit_multi_fixture o6-cockpit-t17-schema-red "$CLEAN_HEALTH" \
      '{"ok":false,"error":"payload schema validation failed","diagnostics":["field narrative_excerpt contains a gate/hook identifier"]}' "$CLEAN_DRIFT")
  OUT="$(PATH="$D/fakebin:$PATH" OBS_COCKPIT_UNAME_OVERRIDE=MINGW64_NT-fixture _run_quick "$D")"; RC=$?
  _assert "o6-cockpit-t17-schema-red" 1 "$RC" "RED obs-cockpit-fresh.*schema validation" "$OUT"

  # ---- Task 17(b): RED — /api/diagnostics/drift reports a
  # count_reconciliation mismatch (an open decision missing from the
  # landing) -> RED (the doctor-visible failure mode sketch §8-3 requires).
  D=$(_cockpit_multi_fixture o6-cockpit-t17-recon-red "$CLEAN_HEALTH" "$CLEAN_ASKS" \
      '{"ok":true,"count_reconciliation":{"ledger_open_count":2,"rendered_waiting_count":1,"mismatch":true,"unaccounted_needs_you_ids":["NY-orphan-1"]}}')
  OUT="$(PATH="$D/fakebin:$PATH" OBS_COCKPIT_UNAME_OVERRIDE=MINGW64_NT-fixture _run_quick "$D")"; RC=$?
  _assert "o6-cockpit-t17-recon-red" 1 "$RC" "RED obs-cockpit-fresh.*reconciliation MISMATCH" "$OUT"

  # ==========================================================
  # ask-rooted-workstreams-p1 Task 17(c) — obs-ask-capture-completeness
  # fixtures. POPULATION PARITY is the load-bearing property: the predicate
  # sources the REAL hooks/lib/progress-log-lib.sh and calls the SAME
  # pl_classify_session / pl_ask_id_for_session the Task 9 guard uses, so a
  # spawned/worktree session (cwd under .claude/worktrees/) is excluded BY
  # CONSTRUCTION and never false-REDs an orchestrated day.
  # ==========================================================
  PLLIB_ST="$SCRIPT_DIR/lib/progress-log-lib.sh"

  # ---- Task 17(c): RED — a trailing-24h OPERATOR session with NO
  # registered ask (the automatic-capture invariant broke).
  D=$(_scenario_dir o6-capture-red)
  _stamp_claim_honesty_green "$D"
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  mkdir -p "$D/live/state/heartbeats"
  printf '{"schema":1,"session_id":"sess-cap-missing","pid":1,"cwd":"%s/repo","last_activity_ts":"now"}\n' "$D" \
    > "$D/live/state/heartbeats/sess-cap-missing.json"
  touch "$D/live/state/heartbeats/sess-cap-missing.json"
  # (no ask-registry.jsonl at all -> the operator session has no registered ask)
  OUT="$(_run_quick "$D")"; RC=$?
  if printf '%s' "$OUT" | grep -q "RED obs-ask-capture-completeness"; then
    echo "self-test (o6-capture-red-fires): PASS" >&2
    PASSED=$((PASSED + 1))
  else
    echo "self-test (o6-capture-red-fires): FAIL (operator session with no registered ask did not RED)" >&2
    FAILED=$((FAILED + 1))
  fi

  # ---- Task 17(c): GREEN — the SAME operator session WITH its
  # deterministically-derived ask registered (pl_ask_id_for_session, the
  # exact derivation Task 9's capture splice uses).
  D=$(_scenario_dir o6-capture-green)
  _stamp_claim_honesty_green "$D"
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  mkdir -p "$D/live/state/heartbeats"
  printf '{"schema":1,"session_id":"sess-cap-ok","pid":1,"cwd":"%s/repo","last_activity_ts":"now"}\n' "$D" \
    > "$D/live/state/heartbeats/sess-cap-ok.json"
  touch "$D/live/state/heartbeats/sess-cap-ok.json"
  if [[ -f "$PLLIB_ST" ]]; then
    ASK_OK_ST="$(source "$PLLIB_ST"; pl_ask_id_for_session sess-cap-ok)"
    printf '{"ask_id":"%s","record_type":"created","ts":"2026-07-01T00:00:00Z"}\n' "$ASK_OK_ST" \
      > "$D/live/state/ask-registry.jsonl"
  fi
  OUT="$(_run_quick "$D")"; RC=$?
  if printf '%s' "$OUT" | grep -q "obs-ask-capture-completeness"; then
    echo "self-test (o6-capture-green-registered): FAIL (fired although the operator session has a registered ask)" >&2
    FAILED=$((FAILED + 1))
  else
    echo "self-test (o6-capture-green-registered): PASS" >&2
    PASSED=$((PASSED + 1))
  fi

  # ---- Task 17(c): POPULATION PARITY — a registered operator session PLUS
  # a SPAWNED session (cwd under .claude/worktrees/<slug>, UNregistered by
  # design) must stay GREEN, because pl_classify_session excludes the
  # spawned one from the audited population. This is the load-bearing
  # correctness property: without parity, every orchestrated day would
  # false-RED.
  D=$(_scenario_dir o6-capture-parity)
  _stamp_claim_honesty_green "$D"
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  mkdir -p "$D/live/state/heartbeats"
  printf '{"schema":1,"session_id":"sess-op-ok","pid":1,"cwd":"%s/repo","last_activity_ts":"now"}\n' "$D" \
    > "$D/live/state/heartbeats/sess-op-ok.json"
  printf '{"schema":1,"session_id":"sess-spawned","pid":2,"cwd":"%s/repo/.claude/worktrees/agent-child","last_activity_ts":"now"}\n' "$D" \
    > "$D/live/state/heartbeats/sess-spawned.json"
  touch "$D/live/state/heartbeats/sess-op-ok.json" "$D/live/state/heartbeats/sess-spawned.json"
  if [[ -f "$PLLIB_ST" ]]; then
    ASK_OP_ST="$(source "$PLLIB_ST"; pl_ask_id_for_session sess-op-ok)"
    # ONLY the operator session is registered; the spawned session is NOT
    # (it would attach to the dispatching ask, never register) — yet the
    # check must stay GREEN because parity excludes it.
    printf '{"ask_id":"%s","record_type":"created","ts":"2026-07-01T00:00:00Z"}\n' "$ASK_OP_ST" \
      > "$D/live/state/ask-registry.jsonl"
  fi
  OUT="$(_run_quick "$D")"; RC=$?
  if printf '%s' "$OUT" | grep -q "RED obs-ask-capture-completeness"; then
    echo "self-test (o6-capture-parity-spawned-excluded): FAIL (population parity broke — a spawned/worktree session false-RED'd the capture check)" >&2
    FAILED=$((FAILED + 1))
  else
    echo "self-test (o6-capture-parity-spawned-excluded): PASS" >&2
    PASSED=$((PASSED + 1))
  fi

  # ---- needs-you-headers: RED — open decision item + NEEDS-YOU.md
  # missing 2 of 4 canonical headers ----
  D=$(_scenario_dir o6-ny-red)
  _stamp_claim_honesty_green "$D"
  mkdir -p "$D/live/state/needs-you"
  cat > "$D/live/state/needs-you/ledger.json" <<'EOF'
{"schema_version":1,"items":[{"id":"NY-1","section":"decision","state":"open"}]}
EOF
  cat > "$D/repo/NEEDS-YOU.md" <<'EOF'
## Awaiting your decision
stuff

## In flight (sessions + waves)
stuff
EOF
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  if command -v jq >/dev/null 2>&1; then
    OUT="$(_run_quick "$D")"; RC=$?
    _assert "o6-needs-you-headers-red" 1 "$RC" "RED needs-you-headers" "$OUT"
    if ! printf '%s' "$OUT" | grep -q "Open questions"; then
      echo "self-test (o6-needs-you-headers-red-names-missing): FAIL (did not name a missing header)" >&2
      FAILED=$((FAILED + 1))
    else
      echo "self-test (o6-needs-you-headers-red-names-missing): PASS" >&2
      PASSED=$((PASSED + 1))
    fi
  else
    echo "self-test (o6-needs-you-headers-red): SKIP (jq unavailable)" >&2
  fi

  # ---- needs-you-headers: GREEN — all 4 headers present; plus the
  # gate-not-triggered GREEN (ny_open==0, headers all missing, still
  # GREEN) ----
  D=$(_scenario_dir o6-ny-green)
  _stamp_claim_honesty_green "$D"
  mkdir -p "$D/live/state/needs-you"
  cat > "$D/live/state/needs-you/ledger.json" <<'EOF'
{"schema_version":1,"items":[{"id":"NY-1","section":"decision","state":"open"}]}
EOF
  cat > "$D/repo/NEEDS-YOU.md" <<'EOF'
## Awaiting your decision
## Open questions
## In flight (sessions + waves)
## Recently decided for your §8 review
EOF
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  if command -v jq >/dev/null 2>&1; then
    OUT="$(_run_quick "$D")"; RC=$?
    if printf '%s' "$OUT" | grep -q "RED needs-you-headers"; then
      echo "self-test (o6-needs-you-headers-green): FAIL (unexpected RED)" >&2
      FAILED=$((FAILED + 1))
    else
      echo "self-test (o6-needs-you-headers-green): PASS" >&2
      PASSED=$((PASSED + 1))
    fi
  else
    echo "self-test (o6-needs-you-headers-green): SKIP (jq unavailable)" >&2
  fi
  D=$(_scenario_dir o6-ny-green-not-triggered)
  _stamp_claim_honesty_green "$D"
  mkdir -p "$D/live/state/needs-you"
  cat > "$D/live/state/needs-you/ledger.json" <<'EOF'
{"schema_version":1,"items":[]}
EOF
  cat > "$D/repo/NEEDS-YOU.md" <<'EOF'
(no headers at all)
EOF
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  if command -v jq >/dev/null 2>&1; then
    OUT="$(_run_quick "$D")"; RC=$?
    if printf '%s' "$OUT" | grep -q "RED needs-you-headers"; then
      echo "self-test (o6-needs-you-headers-green-gate-not-triggered): FAIL (predicate fired despite ny_open==0)" >&2
      FAILED=$((FAILED + 1))
    else
      echo "self-test (o6-needs-you-headers-green-gate-not-triggered): PASS" >&2
      PASSED=$((PASSED + 1))
    fi
  else
    echo "self-test (o6-needs-you-headers-green-gate-not-triggered): SKIP (jq unavailable)" >&2
  fi

  # ---- model-pins: RED fixture -- an agent with no model: frontmatter ----
  D=$(_scenario_dir model-pins-red)
  _stamp_claim_honesty_green "$D"
  mkdir -p "$D/repo/adapters/claude-code/agents"
  mkdir -p "$D/repo/adapters/claude-code/config"
  printf -- '---\nname: pinned-ok\nmodel: fable\n---\nbody\n' > "$D/repo/adapters/claude-code/agents/pinned-ok.md"
  printf -- '---\nname: unpinned-bad\ntools: Read\n---\nbody\n' > "$D/repo/adapters/claude-code/agents/unpinned-bad.md"
  printf '{"model_ids":{"fable":"f","opus":"o","sonnet":"s","haiku":"h"}}\n' > "$D/repo/adapters/claude-code/config/model-policy.json"
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  OUT="$(_run_quick "$D")"; RC=$?
  _assert "model-pins-red-missing" 1 "$RC" "RED model-pins" "$OUT"

  # ---- model-pins: RED fixture -- model value not in policy ----
  D=$(_scenario_dir model-pins-red-bad-val)
  _stamp_claim_honesty_green "$D"
  mkdir -p "$D/repo/adapters/claude-code/agents"
  mkdir -p "$D/repo/adapters/claude-code/config"
  printf -- '---\nname: bad-model\nmodel: gpt4\n---\nbody\n' > "$D/repo/adapters/claude-code/agents/bad-model.md"
  printf '{"model_ids":{"fable":"f","opus":"o","sonnet":"s","haiku":"h"}}\n' > "$D/repo/adapters/claude-code/config/model-policy.json"
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  OUT="$(_run_quick "$D")"; RC=$?
  _assert "model-pins-red-bad-value" 1 "$RC" "RED model-pins" "$OUT"

  # ---- model-pins: GREEN fixture -- all agents pinned with valid models ----
  D=$(_scenario_dir model-pins-green)
  _stamp_claim_honesty_green "$D"
  mkdir -p "$D/repo/adapters/claude-code/agents"
  mkdir -p "$D/repo/adapters/claude-code/config"
  printf -- '---\nname: agent-a\nmodel: fable\n---\nbody\n' > "$D/repo/adapters/claude-code/agents/agent-a.md"
  printf -- '---\nname: agent-b\nmodel: sonnet\n---\nbody\n' > "$D/repo/adapters/claude-code/agents/agent-b.md"
  printf '{"model_ids":{"fable":"f","opus":"o","sonnet":"s","haiku":"h"}}\n' > "$D/repo/adapters/claude-code/config/model-policy.json"
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  OUT="$(_run_quick "$D")"; RC=$?
  if printf '%s' "$OUT" | grep -q "RED model-pins"; then
    echo "self-test (model-pins-green): FAIL (unexpected RED)" >&2
    FAILED=$((FAILED + 1))
  else
    echo "self-test (model-pins-green): PASS" >&2
    PASSED=$((PASSED + 1))
  fi

  # ---- model-pins: RED fixture -- a body `model:` line is NOT frontmatter ----
  D=$(_scenario_dir model-pins-red-body-line)
  _stamp_claim_honesty_green "$D"
  mkdir -p "$D/repo/adapters/claude-code/agents"
  mkdir -p "$D/repo/adapters/claude-code/config"
  printf -- '---\nname: body-only\ntools: Read\n---\nmodel: not-in-frontmatter\n' > "$D/repo/adapters/claude-code/agents/body-only.md"
  printf '{"model_ids":{"fable":"f","opus":"o","sonnet":"s","haiku":"h"}}\n' > "$D/repo/adapters/claude-code/config/model-policy.json"
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  OUT="$(_run_quick "$D")"; RC=$?
  _assert "model-pins-red-body-line" 1 "$RC" "RED model-pins" "$OUT"

  # ---- review-surface-cross-check: RED fixture -- a manifest hooks[]
  # entry names a file that resolves nowhere under hooks/, hooks/lib/, or
  # scripts/ ----
  D=$(_scenario_dir review-surface-red)
  _stamp_claim_honesty_green "$D"
  if _copy_review_gate_tooling "$D"; then
    cat > "$D/repo/adapters/claude-code/manifest.json" <<'EOF'
{"schema_version": 1, "entries": [
  {"id": "ghost", "kind": "pattern", "hooks": ["ghost-hook-does-not-exist.sh"]}
]}
EOF
    _write_settings "$D/live/settings.json"
    cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
    OUT="$(_run_quick "$D")"; RC=$?
    _assert "review-surface-cross-check-red" 1 "$RC" "RED review-surface-cross-check" "$OUT"
  else
    echo "self-test (review-surface-cross-check-red): SKIP (real review-record-gate-lib.sh/write-review-record.sh not found next to doctor)" >&2
  fi

  # ---- review-surface-cross-check: GREEN fixture -- a manifest hooks[]
  # entry names a file that DOES exist under hooks/lib/ (exercises the
  # widened resolution search this check adds beyond top-level hooks/*.sh) ----
  D=$(_scenario_dir review-surface-green)
  _stamp_claim_honesty_green "$D"
  if _copy_review_gate_tooling "$D"; then
    mkdir -p "$D/repo/adapters/claude-code/hooks/lib"
    printf '#!/bin/bash\necho real-lib-hook\n' > "$D/repo/adapters/claude-code/hooks/lib/real-lib-hook.sh"
    cat > "$D/repo/adapters/claude-code/manifest.json" <<'EOF'
{"schema_version": 1, "entries": [
  {"id": "real", "kind": "pattern", "hooks": ["real-lib-hook.sh"]}
]}
EOF
    _write_settings "$D/live/settings.json"
    cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
    OUT="$(_run_quick "$D")"
    if printf '%s' "$OUT" | grep -q "RED review-surface-cross-check"; then
      echo "self-test (review-surface-cross-check-green): FAIL (unexpected RED)" >&2
      FAILED=$((FAILED + 1))
    else
      echo "self-test (review-surface-cross-check-green): PASS" >&2
      PASSED=$((PASSED + 1))
    fi
  else
    echo "self-test (review-surface-cross-check-green): SKIP (real tooling not found)" >&2
  fi

  # ---- review-surface-cross-check: GREEN fixture -- a manifest hooks[]
  # entry uses manifest-check's normalized "lib/<name>.sh" sourced-library
  # form (harness-review REFORMULATE fixup finding 5; mirrors manifest-
  # check.sh's own S11 fixture) -- must resolve hooks_dir-relative
  # (hooks/lib/<name>.sh), not adapters/claude-code/lib/<name>.sh ----
  D=$(_scenario_dir review-surface-libref-green)
  _stamp_claim_honesty_green "$D"
  if _copy_review_gate_tooling "$D"; then
    mkdir -p "$D/repo/adapters/claude-code/hooks/lib"
    printf '#!/bin/bash\n# sourced library, never wired directly\necho mylib\n' > "$D/repo/adapters/claude-code/hooks/lib/mylib.sh"
    cat > "$D/repo/adapters/claude-code/manifest.json" <<'EOF'
{"schema_version": 1, "entries": [
  {"id": "a-gate", "kind": "gate", "hooks": ["lib/mylib.sh"], "blocking": false, "honest_status": "test"}
]}
EOF
    _write_settings "$D/live/settings.json"
    cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
    OUT="$(_run_quick "$D")"
    if printf '%s' "$OUT" | grep -q "RED review-surface-cross-check"; then
      echo "self-test (review-surface-cross-check-libref-green): FAIL (unexpected RED: $OUT)" >&2
      FAILED=$((FAILED + 1))
    else
      echo "self-test (review-surface-cross-check-libref-green): PASS" >&2
      PASSED=$((PASSED + 1))
    fi
  else
    echo "self-test (review-surface-cross-check-libref-green): SKIP (real tooling not found)" >&2
  fi

  # ---- review-index-consistency: RED fixture -- committed index.json
  # disagrees with a fresh rebuild of the records directory ----
  D=$(_scenario_dir review-index-red)
  _stamp_claim_honesty_green "$D"
  if _copy_review_gate_tooling "$D"; then
    mkdir -p "$D/repo/docs/reviews/records"
    cat > "$D/repo/docs/reviews/records/2026-07-16-harness-change-review-fixture.json" <<'EOF'
{"schema_version":1,"kind":"harness-change-review","record_id":"hcr-fixture","created_at":"2026-07-16T00:00:00Z","verdict":"PASS","reviewer":"harness-reviewer","reviewer_model":"opus","plan_ref":"x","change_ref":{"commit_sha":"abc","branch":"master"},"covered_files":[{"path":"adapters/claude-code/hooks/real.sh","blob_sha":"deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"}],"dispatch_evidence":{"transcript_ref":"","verdict_quote":"PASS","findings_summary":""},"written_by":"test","payload":{}}
EOF
    # A STALE index.json that does NOT reflect the record file above.
    printf '{"schema_version":1,"entries":[]}\n' > "$D/repo/docs/reviews/records/index.json"
    _write_settings "$D/live/settings.json"
    cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
    OUT="$(_run_quick "$D")"; RC=$?
    _assert "review-index-consistency-red" 1 "$RC" "RED review-index-consistency" "$OUT"
  else
    echo "self-test (review-index-consistency-red): SKIP (real tooling not found)" >&2
  fi

  # ---- review-index-consistency: GREEN fixture -- index.json IS a faithful
  # rebuild of the one record file present ----
  D=$(_scenario_dir review-index-green)
  _stamp_claim_honesty_green "$D"
  if _copy_review_gate_tooling "$D"; then
    mkdir -p "$D/repo/docs/reviews/records"
    cat > "$D/repo/docs/reviews/records/2026-07-16-harness-change-review-fixture.json" <<'EOF'
{"schema_version":1,"kind":"harness-change-review","record_id":"hcr-fixture","created_at":"2026-07-16T00:00:00Z","verdict":"PASS","reviewer":"harness-reviewer","reviewer_model":"opus","plan_ref":"x","change_ref":{"commit_sha":"abc","branch":"master"},"covered_files":[{"path":"adapters/claude-code/hooks/real.sh","blob_sha":"deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"}],"dispatch_evidence":{"transcript_ref":"","verdict_quote":"PASS","findings_summary":""},"written_by":"test","payload":{}}
EOF
    bash "$D/repo/adapters/claude-code/scripts/write-review-record.sh" rebuild-index \
      --repo-root "$D/repo" >/dev/null 2>&1
    _write_settings "$D/live/settings.json"
    cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
    OUT="$(_run_quick "$D")"
    if printf '%s' "$OUT" | grep -q "RED review-index-consistency"; then
      echo "self-test (review-index-consistency-green): FAIL (unexpected RED: $OUT)" >&2
      FAILED=$((FAILED + 1))
    else
      echo "self-test (review-index-consistency-green): PASS" >&2
      PASSED=$((PASSED + 1))
    fi
  else
    echo "self-test (review-index-consistency-green): SKIP (real tooling not found)" >&2
  fi

  # ---- review-grandfather-integrity: RED fixture -- the lib exists but
  # docs/reviews/records/grandfather-manifest.json is ABSENT entirely
  # (bootstrapped-then-emptied class, harness-review REFORMULATE fixup
  # finding 3b) ----
  D=$(_scenario_dir review-grandfather-absent-red)
  _stamp_claim_honesty_green "$D"
  if _copy_review_gate_tooling "$D"; then
    _write_settings "$D/live/settings.json"
    cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
    OUT="$(_run_quick "$D")"; RC=$?
    _assert "review-grandfather-integrity-absent-red" 1 "$RC" "RED review-grandfather-integrity" "$OUT"
  else
    echo "self-test (review-grandfather-integrity-absent-red): SKIP (real tooling not found)" >&2
  fi

  # ---- review-grandfather-integrity: RED fixture -- grandfather-manifest.json
  # was hand-edited (or silently re-bootstrapped) -- its content does NOT
  # match a fresh re-derivation at its own recorded cutover_ref ----
  D=$(_scenario_dir review-grandfather-tamper-red)
  _stamp_claim_honesty_green "$D"
  if _copy_review_gate_tooling "$D"; then
    ( cd "$D/repo" && git init -q && git config user.email t@example.com && git config user.name T \
        && git add -A && git commit -q -m init )
    CUTOVER_SHA=$(git -C "$D/repo" rev-parse HEAD)
    mkdir -p "$D/repo/docs/reviews/records"
    cat > "$D/repo/docs/reviews/records/grandfather-manifest.json" <<EOF
{"schema_version":1,"cutover_ref":"${CUTOVER_SHA}","generated_at":"2026-07-16T00:00:00Z","entries":[{"path":"adapters/claude-code/hooks/nonexistent-hand-edited.sh","blob_sha":"deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"}]}
EOF
    printf '{"schema_version":1,"entries":[]}\n' > "$D/repo/docs/reviews/records/index.json"
    _write_settings "$D/live/settings.json"
    cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
    OUT="$(_run_quick "$D")"; RC=$?
    _assert "review-grandfather-integrity-tamper-red" 1 "$RC" "RED review-grandfather-integrity" "$OUT"
  else
    echo "self-test (review-grandfather-integrity-tamper-red): SKIP (real tooling not found)" >&2
  fi

  # ---- review-grandfather-integrity: GREEN fixture -- grandfather-manifest.json
  # IS a faithful bootstrap-grandfather snapshot at its own recorded
  # cutover_ref ----
  D=$(_scenario_dir review-grandfather-integrity-green)
  _stamp_claim_honesty_green "$D"
  if _copy_review_gate_tooling "$D"; then
    ( cd "$D/repo" && git init -q && git config user.email t@example.com && git config user.name T \
        && git add -A && git commit -q -m init )
    bash "$D/repo/adapters/claude-code/scripts/write-review-record.sh" bootstrap-grandfather \
      --repo-root "$D/repo" --ref HEAD >/dev/null 2>&1
    printf '{"schema_version":1,"entries":[]}\n' > "$D/repo/docs/reviews/records/index.json"
    _write_settings "$D/live/settings.json"
    cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
    OUT="$(_run_quick "$D")"
    if printf '%s' "$OUT" | grep -q "RED review-grandfather-integrity"; then
      echo "self-test (review-grandfather-integrity-green): FAIL (unexpected RED: $OUT)" >&2
      FAILED=$((FAILED + 1))
    else
      echo "self-test (review-grandfather-integrity-green): PASS" >&2
      PASSED=$((PASSED + 1))
    fi
  else
    echo "self-test (review-grandfather-integrity-green): SKIP (real tooling not found)" >&2
  fi

  # ---- review-reviewer-independence: RED fixture -- the SAME git author
  # wrote the reviewed commit AND committed the PASS record approving it
  # (docs/plans/review-independence.md RI3; self-approval, the class this
  # whole plan exists to eliminate) ----
  D=$(_scenario_dir review-reviewer-independence-red)
  _stamp_claim_honesty_green "$D"
  ( cd "$D/repo" && git init -q -b main )
  ( cd "$D/repo" && git config user.email "author@example.com" && git config user.name "Author Session" )
  mkdir -p "$D/repo/adapters/claude-code/hooks" "$D/repo/docs/reviews/records"
  printf '#!/bin/bash\necho v1\n' > "$D/repo/adapters/claude-code/hooks/real.sh"
  ( cd "$D/repo" && git add -A && git commit -q -m "author: add real.sh" )
  RI_REVIEWED_SHA=$(git -C "$D/repo" rev-parse HEAD)
  RI_BLOB_SHA=$(git -C "$D/repo" rev-parse "HEAD:adapters/claude-code/hooks/real.sh")
  cat > "$D/repo/docs/reviews/records/2026-07-30-harness-change-review-selfapproval.json" <<EOF
{"schema_version":1,"kind":"harness-change-review","record_id":"hcr-selfapproval","created_at":"2026-07-30T00:00:00Z","verdict":"PASS","reviewer":"harness-reviewer","reviewer_model":"opus","plan_ref":"x","change_ref":{"commit_sha":"${RI_REVIEWED_SHA}","branch":"main"},"covered_files":[{"path":"adapters/claude-code/hooks/real.sh","blob_sha":"${RI_BLOB_SHA}"}],"dispatch_evidence":{"transcript_ref":"","verdict_quote":"PASS","findings_summary":""},"written_by":"test","reviewer_principal":{"hostname":"h","account":"a","session_id":"same-session"},"independence":"pathway","payload":{}}
EOF
  printf '{"schema_version":1,"entries":[]}\n' > "$D/repo/docs/reviews/records/index.json"
  # SAME author (Author Session) commits the record -- this is the
  # self-approval shape.
  ( cd "$D/repo" && git add -A && git commit -q -m "author: self-approve real.sh" )
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  # FIXTURE DRIFT FIX (final-3 reviewer 2026-07-30, PROVEN dead three ways):
  # the old override exported the retired SHA-cutover var, the record's
  # created_at pre-dated the default ISO cutover, and _run_quick never runs
  # the authorship walk. Now: ISO cutover earlier than the record's
  # created_at (2026-07-30T00:00:00Z) + the RRI_FORCE_DEEP test seam so the
  # walk actually executes.
  export REVIEW_REVIEWER_INDEPENDENCE_CUTOVER_ISO="2026-01-01T00:00:00Z"
  export RRI_FORCE_DEEP=1
  OUT="$(_run_quick "$D")"; RC=$?
  unset REVIEW_REVIEWER_INDEPENDENCE_CUTOVER_ISO RRI_FORCE_DEEP
  _assert "review-reviewer-independence-red" 1 "$RC" "RED review-reviewer-independence" "$OUT"

  # ---- review-reviewer-independence: GREEN fixture -- a DIFFERENT git
  # author committed the PASS record than the one who authored the
  # reviewed commit ----
  D=$(_scenario_dir review-reviewer-independence-green)
  _stamp_claim_honesty_green "$D"
  ( cd "$D/repo" && git init -q -b main )
  ( cd "$D/repo" && git config user.email "author@example.com" && git config user.name "Author Session" )
  mkdir -p "$D/repo/adapters/claude-code/hooks" "$D/repo/docs/reviews/records"
  printf '#!/bin/bash\necho v1\n' > "$D/repo/adapters/claude-code/hooks/real.sh"
  ( cd "$D/repo" && git add -A && git commit -q -m "author: add real.sh" )
  RI_REVIEWED_SHA=$(git -C "$D/repo" rev-parse HEAD)
  RI_BLOB_SHA=$(git -C "$D/repo" rev-parse "HEAD:adapters/claude-code/hooks/real.sh")
  cat > "$D/repo/docs/reviews/records/2026-07-30-harness-change-review-independent.json" <<EOF
{"schema_version":1,"kind":"harness-change-review","record_id":"hcr-independent","created_at":"2026-07-30T00:00:00Z","verdict":"PASS","reviewer":"harness-reviewer","reviewer_model":"opus","plan_ref":"x","change_ref":{"commit_sha":"${RI_REVIEWED_SHA}","branch":"main"},"covered_files":[{"path":"adapters/claude-code/hooks/real.sh","blob_sha":"${RI_BLOB_SHA}"}],"dispatch_evidence":{"transcript_ref":"","verdict_quote":"PASS","findings_summary":""},"written_by":"test","reviewer_principal":{"hostname":"h","account":"a","session_id":"reviewer-session"},"independence":"pathway","payload":{}}
EOF
  printf '{"schema_version":1,"entries":[]}\n' > "$D/repo/docs/reviews/records/index.json"
  # DIFFERENT author (Runner Process) commits the record -- the genuine
  # independent-reviewer shape this plan builds toward.
  ( cd "$D/repo" && git config user.email "runner@example.com" && git config user.name "Runner Process" )
  ( cd "$D/repo" && git add -A && git commit -q -m "runner: PASS record for real.sh" )
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  # Same ISO+deep environment as the RED twin — without it this no-RED
  # assertion is vacuous (the walk never runs in quick mode).
  export REVIEW_REVIEWER_INDEPENDENCE_CUTOVER_ISO="2026-01-01T00:00:00Z"
  export RRI_FORCE_DEEP=1
  OUT="$(_run_quick "$D")"
  unset REVIEW_REVIEWER_INDEPENDENCE_CUTOVER_ISO RRI_FORCE_DEEP
  if printf '%s' "$OUT" | grep -q "RED review-reviewer-independence"; then
    echo "self-test (review-reviewer-independence-green): FAIL (unexpected RED: $OUT)" >&2
    FAILED=$((FAILED + 1))
  else
    echo "self-test (review-reviewer-independence-green): PASS" >&2
    PASSED=$((PASSED + 1))
  fi

  # ---- review-reviewer-independence: WARN-graceful fixture -- a record
  # with no change_ref.commit_sha (e.g. a hand-authored or pre-RI3 record)
  # never REDs; it is a "cannot verify," not a violation ----
  D=$(_scenario_dir review-reviewer-independence-unresolvable)
  _stamp_claim_honesty_green "$D"
  ( cd "$D/repo" && git init -q -b main )
  ( cd "$D/repo" && git config user.email "author@example.com" && git config user.name "Author Session" )
  mkdir -p "$D/repo/docs/reviews/records"
  cat > "$D/repo/docs/reviews/records/2026-07-30-harness-change-review-nocommitsha.json" <<'EOF'
{"schema_version":1,"kind":"harness-change-review","record_id":"hcr-nocommitsha","created_at":"2026-07-30T00:00:00Z","verdict":"PASS","reviewer":"harness-reviewer","reviewer_model":"opus","plan_ref":"x","change_ref":{"commit_sha":"","branch":"main"},"covered_files":[{"path":"adapters/claude-code/hooks/real.sh","blob_sha":"deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"}],"dispatch_evidence":{"transcript_ref":"","verdict_quote":"PASS","findings_summary":""},"written_by":"test","payload":{}}
EOF
  printf '{"schema_version":1,"entries":[]}\n' > "$D/repo/docs/reviews/records/index.json"
  ( cd "$D/repo" && git add -A && git commit -q -m "unresolvable fixture" )
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  OUT="$(_run_quick "$D")"
  if printf '%s' "$OUT" | grep -q "RED review-reviewer-independence"; then
    echo "self-test (review-reviewer-independence-unresolvable-not-red): FAIL (unexpected RED: $OUT)" >&2
    FAILED=$((FAILED + 1))
  else
    echo "self-test (review-reviewer-independence-unresolvable-not-red): PASS" >&2
    PASSED=$((PASSED + 1))
  fi

  # ---- review-reviewer-independence: PRE-CUTOVER GRANDFATHER fixture --
  # the exact self-approval shape (same author on both the reviewed commit
  # and the record's commit), but using the REAL production default
  # _RRI_CUTOVER_ISO (2026-07-30T09:00:00Z, no override -- unlike the RED/
  # GREEN twins above, which must override it since a from-scratch fixture
  # repo has no way to predate a real production timestamp otherwise). The
  # record's own `created_at` (2026-07-29T00:00:00Z, below) string-compares
  # as EARLIER than that default, so check_review_reviewer_independence's
  # ISO-date comparison classifies it PRE-cutover on its own -- no test-seam
  # override needed for this one. Must WARN, never RED: this is the
  # 2026-07-29 sweep's exact shape (docs/plans/review-independence.md
  # Decisions Log) -- a deliberate, operator-authorized stopgap predating
  # the mechanism, not a violation to flag retroactively. ----
  D=$(_scenario_dir review-reviewer-independence-pre-cutover-warn)
  _stamp_claim_honesty_green "$D"
  ( cd "$D/repo" && git init -q -b main )
  ( cd "$D/repo" && git config user.email "author@example.com" && git config user.name "Author Session" )
  mkdir -p "$D/repo/adapters/claude-code/hooks" "$D/repo/docs/reviews/records"
  printf '#!/bin/bash\necho v1\n' > "$D/repo/adapters/claude-code/hooks/real.sh"
  ( cd "$D/repo" && git add -A && git commit -q -m "author: add real.sh" )
  RI_REVIEWED_SHA=$(git -C "$D/repo" rev-parse HEAD)
  RI_BLOB_SHA=$(git -C "$D/repo" rev-parse "HEAD:adapters/claude-code/hooks/real.sh")
  cat > "$D/repo/docs/reviews/records/2026-07-30-harness-change-review-precutover.json" <<EOF
{"schema_version":1,"kind":"harness-change-review","record_id":"hcr-precutover","created_at":"2026-07-29T00:00:00Z","verdict":"PASS","reviewer":"harness-reviewer","reviewer_model":"opus","plan_ref":"x","change_ref":{"commit_sha":"${RI_REVIEWED_SHA}","branch":"main"},"covered_files":[{"path":"adapters/claude-code/hooks/real.sh","blob_sha":"${RI_BLOB_SHA}"}],"dispatch_evidence":{"transcript_ref":"","verdict_quote":"PASS","findings_summary":""},"written_by":"test","payload":{}}
EOF
  printf '{"schema_version":1,"entries":[]}\n' > "$D/repo/docs/reviews/records/index.json"
  ( cd "$D/repo" && git add -A && git commit -q -m "author: self-approve real.sh (pre-cutover sweep shape)" )
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  OUT="$(_run_quick "$D")"
  if printf '%s' "$OUT" | grep -q "RED review-reviewer-independence"; then
    echo "self-test (review-reviewer-independence-pre-cutover-warn): FAIL (unexpected RED -- pre-cutover content must be grandfathered: $OUT)" >&2
    FAILED=$((FAILED + 1))
  elif printf '%s' "$OUT" | grep -q "WARN review-reviewer-independence.*pre-cutover record(s) grandfathered"; then
    echo "self-test (review-reviewer-independence-pre-cutover-warn): PASS" >&2
    PASSED=$((PASSED + 1))
  else
    echo "self-test (review-reviewer-independence-pre-cutover-warn): FAIL (expected the grandfather WARN line, got: $OUT)" >&2
    FAILED=$((FAILED + 1))
  fi

  # ---- B3 (delta-sweep reviewer 2026-07-30): the RI deep-walk's PRODUCTION
  # trigger (`[[ "${MODE:-}" == "--full" || "${MODE:-}" == "full" ...`,
  # ~check_review_reviewer_independence) has zero fixture coverage above --
  # all four RI fixtures reach the walk via the RRI_FORCE_DEEP test seam,
  # never by actually setting MODE=full. A cheap structural (grep-shaped)
  # self-test is the pragmatic middle ground: proving MODE==full genuinely
  # drives the walk at runtime would mean running a real multi-minute
  # --full sweep per fixture, which the --quick-cost fix earlier in this
  # same check exists specifically to avoid paying on every self-test run.
  # This instead pins the SOURCE shape of the gating line itself, so a
  # future edit that silently drops the production MODE check (leaving only
  # the test seam) fails loudly here instead of only in an untested
  # production --full run. ----
  if grep -q '"\${MODE:-}" == "--full" || "\${MODE:-}" == "full" || "\${RRI_FORCE_DEEP:-0}" == "1"' "$SELF_TEST_HOOK"; then
    echo "self-test (review-reviewer-independence-mode-full-gating-present): PASS" >&2
    PASSED=$((PASSED + 1))
  else
    echo "self-test (review-reviewer-independence-mode-full-gating-present): FAIL (the RI deep-walk's _rri_deep gating line no longer matches the expected MODE==full || RRI_FORCE_DEEP shape -- verify the production trigger, not only the test seam, still gates the authorship walk)" >&2
    FAILED=$((FAILED + 1))
  fi

  # ---- Check 8 (--full only): RED fixture — a stub hook's --self-test fails ----
  D=$(_scenario_dir c7-red)
  _stamp_claim_honesty_green "$D"
  cat > "$D/live/hooks/failing.sh" <<'EOF'
#!/bin/bash
if [[ "${1:-}" == "--self-test" ]]; then
  echo "self-test: intentional failure" >&2
  exit 1
fi
exit 0
EOF
  chmod +x "$D/live/hooks/failing.sh"
  _write_settings "$D/live/settings.json" "failing.sh"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  cp "$D/live/hooks/failing.sh" "$D/repo/adapters/claude-code/hooks/failing.sh"
  OUT="$(HARNESS_DOCTOR_HOME="$D/live" NL_REPO_ROOT="$D/repo" bash "$SELF_TEST_HOOK" --full "$D/repo" 2>&1)"; RC=$?
  _assert "8-selftest-sweep-red" 1 "$RC" "RED selftest-sweep" "$OUT"

  # ---- Check 8 DEDUP (mode-dispatch tail, harness-review Major): the
  # dispatch tail previously called check_selftest_sweep AND
  # check_master_drift_selftest TWICE in --full mode (a mis-indented stray
  # `fi` split what should have been ONE MODE==full block into two
  # sequential ones), doubling --full's dominant runtime cost and
  # duplicating every sweep RED line. Presence-of-a-RED assertions (the one
  # right above, and P7/c8 elsewhere) cannot catch duplication -- they pass
  # whether the line appears once or twice. This counts it: ONE failing
  # fixture hook must yield EXACTLY ONE "RED selftest-sweep ... failing.sh"
  # line, never two. ----
  # (B1, delta-sweep reviewer 2026-07-30: this whole --self-test handler is
  # top-level script code guarded by `if [[ "${1:-}" == "--self-test" ]]`,
  # not a shell function -- `local` here errors "local: can only be used in
  # a function" on both interpreters, once per run. No `local` keyword.)
  dup_count=$(printf '%s\n' "$OUT" | grep -c "RED selftest-sweep.*failing\.sh")
  if [[ "$dup_count" -eq 1 ]]; then
    echo "self-test (8-selftest-sweep-not-duplicated): PASS" >&2
    PASSED=$((PASSED + 1))
  else
    echo "self-test (8-selftest-sweep-not-duplicated): FAIL (expected exactly 1 RED line for the one failing fixture hook, got ${dup_count} -- dispatch tail is calling check_selftest_sweep more than once in --full mode)" >&2
    FAILED=$((FAILED + 1))
  fi

  # ---- Check 8: GREEN fixture — a stub hook's --self-test passes ----
  D=$(_scenario_dir c7-green)
  _stamp_claim_honesty_green "$D"
  cat > "$D/live/hooks/passing.sh" <<'EOF'
#!/bin/bash
if [[ "${1:-}" == "--self-test" ]]; then
  echo "self-test: ok"
  exit 0
fi
exit 0
EOF
  chmod +x "$D/live/hooks/passing.sh"
  _write_settings "$D/live/settings.json" "passing.sh"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  cp "$D/live/hooks/passing.sh" "$D/repo/adapters/claude-code/hooks/passing.sh"
  OUT="$(HARNESS_DOCTOR_HOME="$D/live" NL_REPO_ROOT="$D/repo" bash "$SELF_TEST_HOOK" --full "$D/repo" 2>&1)"; RC=$?
  _assert "8-selftest-sweep-green" 0 "$RC" "" "$OUT"

  # ---- E.1 (T2 fix, THE dominant root cause -- agent-efficiency-fixes-
  # 2026-07): --quick must NEVER execute session-start-digest.sh --self-test
  # -- only check structural presence (exists/executable/declares the
  # entrypoint), mirroring the sibling E.7/E.8 predicates. This fixture's
  # --self-test body intentionally `exit 1`s; if --quick still executed it
  # (the pre-fix behavior -- a full multi-minute suite run inline on every
  # SessionStart/resume), this would RED with "exited non-zero". Absence of
  # ANY e1-digest finding proves the execution truly stopped, not merely
  # that the message text changed. Previously UNTESTED: no scenario in this
  # suite ever populated a real session-start-digest.sh into a fixture's
  # live/hooks/, so this predicate had zero self-test coverage before now.
  D=$(_scenario_dir c10-e1-no-exec)
  _stamp_claim_honesty_green "$D"
  cat > "$D/live/hooks/session-start-digest.sh" <<'EOF'
#!/bin/bash
if [[ "${1:-}" == "--self-test" ]]; then
  echo "self-test: intentional failure (must never be reached by --quick)" >&2
  exit 1
fi
exit 0
EOF
  chmod +x "$D/live/hooks/session-start-digest.sh"
  _write_settings "$D/live/settings.json" "session-start-digest.sh"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  cp "$D/live/hooks/session-start-digest.sh" "$D/repo/adapters/claude-code/hooks/session-start-digest.sh"
  OUT="$(_run_quick "$D")"
  if printf '%s' "$OUT" | grep -qi "e1-digest"; then
    echo "self-test (e1-quick-never-executes): FAIL (a wave-e-e1-digest finding leaked through -- --quick executed the stub's --self-test body): $OUT" >&2
    FAILED=$((FAILED + 1))
  else
    echo "self-test (e1-quick-never-executes): PASS" >&2
    PASSED=$((PASSED + 1))
  fi

  # ---- E.1 RED: hook present, executable, but declares no --self-test
  # entrypoint at all (structural, not behavioral -- grep only). ----
  D=$(_scenario_dir c10-e1-no-flag)
  _stamp_claim_honesty_green "$D"
  cat > "$D/live/hooks/session-start-digest.sh" <<'EOF'
#!/bin/bash
exit 0
EOF
  chmod +x "$D/live/hooks/session-start-digest.sh"
  _write_settings "$D/live/settings.json" "session-start-digest.sh"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  cp "$D/live/hooks/session-start-digest.sh" "$D/repo/adapters/claude-code/hooks/session-start-digest.sh"
  OUT="$(_run_quick "$D")"; RC=$?
  _assert "e1-no-selftest-entrypoint-red" 1 "$RC" "RED wave-e-e1-digest.*no --self-test entrypoint" "$OUT"

  # ---- Check 8 SCOPE (macos-portability-2026-07 M5): the sweep must reach
  # hooks/lib/*.sh.
  #
  # Before this fix the loop globbed only "$hooks_dir"/*.sh. A top-level glob
  # never matches a subdirectory, so all 20 live hooks/lib/*.sh suites — the
  # harness's shared primitives — were invisible to --full: their assertions
  # existed and never ran. Nothing in this suite noticed, because no fixture
  # had ever put a hook in lib/.
  #
  # This fixture's ONLY failing suite is in lib/. Delete the lib glob from
  # check_selftest_sweep and --full comes back rc 0, so this scenario fails —
  # which is what makes it a test of the scope rather than a restatement of
  # it. The expected RED text also pins the LABEL to the hooks-relative path
  # (lib/failing-lib.sh), since a bare basename can now collide between
  # hooks/x.sh and hooks/lib/x.sh.
  D=$(_scenario_dir c8-lib-scope)
  _stamp_claim_honesty_green "$D"
  mkdir -p "$D/live/hooks/lib"
  cat > "$D/live/hooks/lib/failing-lib.sh" <<'EOF'
#!/bin/bash
if [ "${BASH_SOURCE[0]:-$0}" = "${0}" ] && [ "${1:-}" = "--self-test" ]; then
  echo "self-test: intentional lib failure" >&2
  exit 1
fi
EOF
  chmod +x "$D/live/hooks/lib/failing-lib.sh"
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  OUT="$(HARNESS_DOCTOR_HOME="$D/live" NL_REPO_ROOT="$D/repo" bash "$SELF_TEST_HOOK" --full "$D/repo" 2>&1)"; RC=$?
  _assert "8-selftest-sweep-covers-hooks-lib" 1 "$RC" "RED selftest-sweep: lib/failing-lib.sh" "$OUT"

  # ---- Check 8 (T2, agent-efficiency-fixes-2026-07): a reentrant/
  # automation-spawned invocation of --full NEVER fans out into the
  # self-test sweep, even against a fixture hook whose --self-test would
  # otherwise RED (docs/lessons/2026-07-20-efficiency-recurrence-live-
  # diagnosis.md golden scenario). Reuses the c7-red failing.sh fixture.
  # This exercises the pre-existing NL-FINDING-040 top-level guard AND
  # check_selftest_sweep's own inner guard together (the inner one is
  # defense-in-depth for a future call site that might bypass the outer
  # one — not independently isolable via subprocess invocation since this
  # script has no source-guard around its main body). Previously UNTESTED:
  # NL_HOOK_REENTRY never appeared anywhere in this self-test suite before.
  D=$(_scenario_dir c8-reentry)
  _stamp_claim_honesty_green "$D"
  cat > "$D/live/hooks/failing.sh" <<'EOF'
#!/bin/bash
if [[ "${1:-}" == "--self-test" ]]; then
  echo "self-test: intentional failure" >&2
  exit 1
fi
exit 0
EOF
  chmod +x "$D/live/hooks/failing.sh"
  _write_settings "$D/live/settings.json" "failing.sh"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  cp "$D/live/hooks/failing.sh" "$D/repo/adapters/claude-code/hooks/failing.sh"
  OUT="$(HARNESS_DOCTOR_HOME="$D/live" NL_REPO_ROOT="$D/repo" NL_HOOK_REENTRY=1 bash "$SELF_TEST_HOOK" --full "$D/repo" 2>&1)"; RC=$?
  _assert "8-selftest-sweep-reentry-suppressed" 0 "$RC" "skipping checks" "$OUT"
  if printf '%s' "$OUT" | grep -q "RED selftest-sweep"; then
    echo "self-test (8-selftest-sweep-reentry-no-fanout): FAIL (a RED selftest-sweep line leaked through under NL_HOOK_REENTRY=1 -- the fan-out was NOT suppressed): $OUT" >&2
    FAILED=$((FAILED + 1))
  else
    echo "self-test (8-selftest-sweep-reentry-no-fanout): PASS" >&2
    PASSED=$((PASSED + 1))
  fi

  # ---- SESSIONSTART-SINGLEFLIGHT-01 (T3 extension): NL_SESSIONSTART_ORIGIN=1
  # + a FRESH sibling lock -> the quick check is skipped (rc 0, one-line
  # note), proving the debounce actually bites for the SessionStart-origin
  # path. A plain explicit invocation (no NL_SESSIONSTART_ORIGIN) against the
  # SAME held lock must NOT be single-flighted away -- explicit/manual
  # doctor runs are never suppressed by this mechanism.
  D=$(_scenario_dir c9-ssf)
  _stamp_claim_honesty_green "$D"
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  # NOTE 1: the doctor invocation below runs the REAL $SELF_TEST_HOOK from
  # its real on-disk location, so it sources the REAL lib/sessionstart-
  # singleflight.sh relative to its own SCRIPT_DIR — HARNESS_DOCTOR_HOME
  # only overrides resolve_live_home's return value (used as
  # SSF_STATE_DIR's base), not where the script/lib physically live.
  # Pre-claim the SessionStart-origin lock under that SAME state dir, as
  # if a sibling session already ran the quick check moments ago.
  # NOTE 2: `VAR=val source file` scopes VAR to the `source` command
  # ITSELF only — it does NOT persist for a later chained command (source
  # is a builtin, not a function call). `source` and the SSF_STATE_DIR-
  # bearing `ss_singleflight` call are therefore two SEPARATE statements,
  # with the env var attached directly to the function call — mirroring
  # session-start-auto-install.sh's own working pattern and the real gate
  # a few lines below.
  # NOTE 3: `source file` with NO explicit arguments inherits the CALLING
  # SCOPE's own positional parameters ($1, $2, ...) — and we are executing
  # this INLINE inside harness-doctor.sh's own top-level
  # `if [[ "${1:-}" == "--self-test" ]]` block (not a function body, so
  # there is no fresh $1), meaning $1 here is STILL this whole script's
  # own "--self-test". The sourced lib's OWN bottom-of-file
  # `if [[ "${1:-}" == "--self-test" ]]` block sees that SAME inherited
  # "--self-test" and runs ITS OWN 11-scenario suite, ending in `exit 0` —
  # which, being inside our `( )` subshell, terminates the subshell
  # BEFORE the `ss_singleflight doctor-quick` line below it ever runs,
  # silently defeating the whole pre-claim. Passing an explicit empty
  # argument to `source` overrides $1 for the sourced file's execution
  # (bash's documented `source file [arguments]` behavior), so the
  # library takes its normal (non-self-test) path and simply defines its
  # functions. (All three of these NOTEs were found via a manual
  # reproduction during this fix's own build — the original one-liner
  # here silently 1) wrote its pre-claim lock to the REAL machine's
  # $HOME/.claude/state/singleflight/ instead of the sandboxed fixture
  # path, AND, even after fixing that, 2) never actually created the lock
  # at all because of this exact $1 inheritance — confirmed by
  # instrumenting this block and observing the library's OWN self-test
  # summary line print instead of the intended pre-claim.)
  (
    source "$SCRIPT_DIR/lib/sessionstart-singleflight.sh" ""
    SSF_STATE_DIR="$D/live/state/singleflight" ss_singleflight doctor-quick 120
  ) >/dev/null 2>&1
  OUT="$(HARNESS_DOCTOR_HOME="$D/live" NL_REPO_ROOT="$D/repo" NL_SESSIONSTART_ORIGIN=1 bash "$SELF_TEST_HOOK" --quick "$D/repo" 2>&1)"; RC=$?
  _assert "9-ssf-sessionstart-origin-skips-on-held-lock" 0 "$RC" "SESSIONSTART-SINGLEFLIGHT-01" "$OUT"
  if printf '%s' "$OUT" | grep -q "GREEN\|FAILED"; then
    echo "self-test (9-ssf-skip-means-no-checks-ran): FAIL (expected a bare skip, but checks appear to have run): $OUT" >&2
    FAILED=$((FAILED + 1))
  else
    echo "self-test (9-ssf-skip-means-no-checks-ran): PASS" >&2
    PASSED=$((PASSED + 1))
  fi
  # Explicit invocation (no NL_SESSIONSTART_ORIGIN) against the SAME held
  # lock -> runs normally (not single-flighted away) by the OLD, marker-
  # gated ss_singleflight mechanism this scenario exists to validate.
  # SF_DISABLE=1: harness-execution-redesign-2026-08 Task 1 added a SECOND,
  # independent, UNCONDITIONAL guard (sf_guard, invariant 4) that
  # deliberately single-flights explicit reruns too (see its call site
  # comment a few lines above the SESSIONSTART-SINGLEFLIGHT-01 block) -- a
  # real, intentional, DIFFERENT behavior change from this pre-existing
  # scenario's assertion. Disabling it here isolates what THIS scenario
  # validates (the old mechanism, in isolation); the new guard's own
  # contract is exercised by the dedicated sf-guard-unconditional scenario
  # below.
  OUT="$(HARNESS_DOCTOR_HOME="$D/live" NL_REPO_ROOT="$D/repo" SF_DISABLE=1 bash "$SELF_TEST_HOOK" --quick "$D/repo" 2>&1)"; RC=$?
  # HR-F10 (2026-08-03 harness review, gated-pipeline T7/REQ-A5): renamed
  # with the -BY-SSF suffix -- "never suppressed" is true only of SSF
  # (sessionstart-singleflight.sh, the OLD marker-gated mechanism this
  # scenario isolates via SF_DISABLE=1 above), not of the system as a
  # whole: sf_guard, the NEW unconditional guard, DOES suppress explicit
  # reruns (see the 9b-sfguard scenarios below). The un-suffixed name
  # asserted a system-level guarantee that no longer holds.
  _assert "9-ssf-explicit-invocation-never-suppressed-BY-SSF" 0 "$RC" "GREEN" "$OUT"

  # ---- sf-guard-unconditional (harness-execution-redesign-2026-08 Task 1,
  # invariant 4): the NEW guard fires WITHOUT any NL_SESSIONSTART_ORIGIN
  # marker at all (the whole point -- it covers a resume-origin invocation
  # the marker itself might miss), and it recursion-guards a nested
  # subprocess invocation with zero filesystem I/O. Fresh scenario dir so
  # this is unconfounded by the SSF fixture above. ----
  D=$(_scenario_dir c9b-sfguard)
  _stamp_claim_honesty_green "$D"
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  # First explicit invocation (no marker) -> runs normally and claims the
  # new guard's lock.
  OUT="$(HARNESS_DOCTOR_HOME="$D/live" NL_REPO_ROOT="$D/repo" bash "$SELF_TEST_HOOK" --quick "$D/repo" 2>&1)"; RC=$?
  _assert "9b-sfguard-first-explicit-call-runs-normally" 0 "$RC" "GREEN" "$OUT"
  # Second explicit invocation, immediately after, SAME machine-global
  # lock, still no marker -> the NEW unconditional guard skips it.
  OUT="$(HARNESS_DOCTOR_HOME="$D/live" NL_REPO_ROOT="$D/repo" bash "$SELF_TEST_HOOK" --quick "$D/repo" 2>&1)"; RC=$?
  _assert "9b-sfguard-second-explicit-call-single-flighted" 0 "$RC" "single-flight" "$OUT"
  # gated-pipeline-master-2026-08 Task 4 (REQ-A2, fixing HR-F2+F5+F8): the
  # skip now SERVES call 1's cached GREEN verdict verbatim (single-writer
  # contract) instead of the old bare "no checks ran" skip -- GREEN is now
  # EXPECTED here, honestly traceable to call 1's real recompute a moment
  # ago, never fabricated. (The old bare `exit 0` this replaces is exactly
  # what let digest's now-removed cache writer corrupt the entry on a race
  # -- F2's proven casualty.)
  if printf '%s' "$OUT" | grep -q "\[doctor\] GREEN"; then
    echo "self-test (9b-sfguard-skip-serves-cached-verdict-honestly): PASS" >&2
    PASSED=$((PASSED + 1))
  else
    echo "self-test (9b-sfguard-skip-serves-cached-verdict-honestly): FAIL (expected the skip to serve call 1's cached GREEN verdict): $OUT" >&2
    FAILED=$((FAILED + 1))
  fi
  # Recursion guard: a nested invocation within the SAME process (env var
  # inherited by a subprocess) short-circuits with zero I/O, distinct
  # message from the cross-process single-flight path above.
  D=$(_scenario_dir c9c-sfguard-recursion)
  _stamp_claim_honesty_green "$D"
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  OUT="$(
    export HARNESS_DOCTOR_HOME="$D/live" NL_REPO_ROOT="$D/repo"
    source "$SCRIPT_DIR/lib/single-flight-lib.sh" ""
    # TTL justification (HR-F3 comment-discipline requirement, gated-
    # pipeline T7/REQ-A5): this call's TTL value is deliberately NOT tied
    # to the production 1200s figure below -- it exists only to claim the
    # recursion-guard env var + a fresh lock stamp so the NEXT line (a real
    # subprocess of THIS same shell) hits the zero-I/O recursion branch,
    # which is checked and returns BEFORE sf_guard ever consults the TTL
    # at all. Any positive integer here would produce the identical
    # recursion-path assertion below; 120 is kept only for readability
    # continuity with the rest of this file's fixtures.
    SF_STATE_DIR="${D}/live/state/single-flight" sf_guard "doctor-quick" 120 >/dev/null 2>&1
    SF_STATE_DIR="${D}/live/state/single-flight" bash "$SELF_TEST_HOOK" --quick "$D/repo" 2>&1
  )"; RC=$?
  # gated-pipeline-master-2026-08 Task 4 (REQ-A2): this is a FRESH scenario
  # dir (c9c) -- no prior real run means no cache exists yet, so the honest
  # outcome on this skip is exit 3 + a parseable SKIPPED line (never a
  # fabricated 0/GREEN just because there was nothing to serve).
  _assert "9c-sfguard-recursion-nested-invocation-short-circuits" 3 "$RC" "recursion" "$OUT"
  _assert "9c-sfguard-recursion-no-cache-exits-3-with-skipped-line" 3 "$RC" "SKIPPED" "$OUT"

  # ================================================================
  # Check 9 (portability-sweep) — macos-portability-2026-07 task M5
  # ================================================================
  # These scenarios run the REAL scripts/portability-sweep.sh (copied into a
  # fixture repo together with the real hooks/lib/portable-timeout.sh it
  # sources) against tiny stub suites. The runner is genuine; only the
  # scripts it grades are stubs, which is the only way to make "a NEW failing
  # script REDs / a NEW passing script does not" deterministic.
  #
  # NL_PORTABILITY_SWEEP_ACTIVE=0 is set explicitly on every invocation: this
  # whole suite is itself one of the ~163 scripts the real sweep runs, so
  # without the override these scenarios would silently take the depth-guard
  # skip path (and pass by default) whenever the doctor's own self-test was
  # launched from a sweep.
  _PORT_REAL_SWEEP="$(dirname "$SELF_TEST_HOOK")/../scripts/portability-sweep.sh"
  _PORT_REAL_TIMEOUT="$(dirname "$SELF_TEST_HOOK")/lib/portable-timeout.sh"
  if [[ -f "$_PORT_REAL_SWEEP" && -f "$_PORT_REAL_TIMEOUT" ]]; then
    _port_fixture() {
      local label="$1"
      local d
      d=$(_scenario_dir "$label")
      mkdir -p "$d/repo/adapters/claude-code/hooks/lib" "$d/repo/docs"
      cp "$_PORT_REAL_SWEEP" "$d/repo/adapters/claude-code/scripts/portability-sweep.sh"
      cp "$_PORT_REAL_TIMEOUT" "$d/repo/adapters/claude-code/hooks/lib/portable-timeout.sh"
      printf '#!/bin/bash\nif [[ "${1:-}" == "--self-test" ]]; then echo ok; exit 0; fi\nexit 0\n' \
        > "$d/repo/adapters/claude-code/hooks/pp-pass.sh"
      printf '#!/bin/bash\nif [[ "${1:-}" == "--self-test" ]]; then echo "summary: 0 passed, 1 failed" >&2; exit 1; fi\nexit 0\n' \
        > "$d/repo/adapters/claude-code/hooks/pp-known-fail.sh"
      chmod +x "$d/repo/adapters/claude-code/hooks"/*.sh
      printf 'FAIL\thooks/pp-known-fail.sh\n' > "$d/repo/docs/portability-baseline.txt"
      _write_settings "$d/live/settings.json"
      cp "$d/live/settings.json" "$d/repo/adapters/claude-code/settings.json.template"
      printf '%s' "$d"
    }
    _port_run() {
      local d="$1"; shift
      HARNESS_DOCTOR_HOME="$d/live" NL_REPO_ROOT="$d/repo" \
      NL_PORTABILITY_SWEEP_ACTIVE=0 \
      DOCTOR_PORTABILITY_ROOTS="hooks" \
      DOCTOR_PORTABILITY_PER_TIMEOUT=10 \
      DOCTOR_PORTABILITY_BUDGET=90 \
      "$@" bash "$SELF_TEST_HOOK" --portability "$d/repo" 2>&1
    }

    # P1 — a failing suite that IS in the baseline is NOT a regression.
    D=$(_port_fixture c11-port-baselined)
    OUT="$(_port_run "$D")"; RC=$?
    _assert "9c-portability-baselined-failure-is-green" 0 "$RC" "GREEN" "$OUT"

    # P2 — THE RED CONDITION. A newly added script whose --self-test fails and
    # which is absent from the baseline must RED, and must be NAMED.
    D=$(_port_fixture c11-port-new-fail)
    printf '#!/bin/bash\nif [[ "${1:-}" == "--self-test" ]]; then echo "boom" >&2; exit 1; fi\nexit 0\n' \
      > "$D/repo/adapters/claude-code/hooks/pp-new-fail.sh"
    chmod +x "$D/repo/adapters/claude-code/hooks/pp-new-fail.sh"
    OUT="$(_port_run "$D")"; RC=$?
    # The pattern names the REGRESSION branch specifically, not just
    # "RED portability-sweep". Mutation-verified during this task's build: an
    # earlier version matched the bare check id, and mutating the rc==1 arm
    # away still passed — the rc!=0 "setup error" arm emitted a RED with the
    # same id and echoed the sweep's tail (which contains the script name),
    # so BOTH this assertion and the naming assertion below passed while the
    # regression branch was dead. Pinning the branch's own wording is what
    # makes the mutation bite.
    _assert "9c-portability-new-failure-reds" 1 "$RC" "RED portability-sweep: NEW self-test failure" "$OUT"
    if printf '%s\n' "$OUT" | grep 'RED portability-sweep: NEW self-test failure' | grep -q "pp-new-fail.sh"; then
      echo "self-test (9c-portability-new-failure-is-named): PASS" >&2; PASSED=$((PASSED + 1))
    else
      echo "self-test (9c-portability-new-failure-is-named): FAIL (no NEW-failure RED line named the offending script): $OUT" >&2; FAILED=$((FAILED + 1))
    fi
    # EXACTLY ONE red. The fixture has three suites: one passing, one failing
    # AND baselined, one failing and NOT baselined — so precisely one thing
    # regressed. Asserting the COUNT (not just "a RED appeared") is what
    # catches an over-broad output parser: the first version of this check
    # matched the sweep's report body as well as its regression section and
    # turned one regression into 54 REDs, 53 of them already-baselined
    # scripts. Nothing in this suite noticed until the end-to-end injected-
    # regression demo was run by hand.
    _PORT_REDS="$(printf '%s\n' "$OUT" | grep -c 'RED portability-sweep')"
    if [ "${_PORT_REDS:-0}" -eq 1 ]; then
      echo "self-test (9c-portability-one-regression-yields-exactly-one-red): PASS" >&2; PASSED=$((PASSED + 1))
    else
      echo "self-test (9c-portability-one-regression-yields-exactly-one-red): FAIL (expected 1 RED, got ${_PORT_REDS} — the output parser is matching more than the regression section): $OUT" >&2; FAILED=$((FAILED + 1))
    fi

    # P3 — the symmetric half: a newly added script whose --self-test PASSES
    # must NOT RED. A check that reddened on any new script would be useless.
    D=$(_port_fixture c11-port-new-pass)
    printf '#!/bin/bash\nif [[ "${1:-}" == "--self-test" ]]; then echo fine; exit 0; fi\nexit 0\n' \
      > "$D/repo/adapters/claude-code/hooks/pp-new-pass.sh"
    chmod +x "$D/repo/adapters/claude-code/hooks/pp-new-pass.sh"
    OUT="$(_port_run "$D")"; RC=$?
    _assert "9c-portability-new-passing-script-is-green" 0 "$RC" "GREEN" "$OUT"

    # P4 — runner present, baseline absent: RED. A half-installed mechanism
    # reads as protection while providing none.
    D=$(_port_fixture c11-port-no-baseline)
    rm -f "$D/repo/docs/portability-baseline.txt"
    OUT="$(_port_run "$D")"; RC=$?
    _assert "9c-portability-missing-baseline-reds" 1 "$RC" "RED portability-sweep.*baseline is missing" "$OUT"

    # P5 — depth guard: inside a sweep, the check skips instead of recursing,
    # even when a real regression is present.
    D=$(_port_fixture c11-port-depth)
    printf '#!/bin/bash\nif [[ "${1:-}" == "--self-test" ]]; then exit 1; fi\nexit 0\n' \
      > "$D/repo/adapters/claude-code/hooks/pp-new-fail.sh"
    chmod +x "$D/repo/adapters/claude-code/hooks/pp-new-fail.sh"
    OUT="$(HARNESS_DOCTOR_HOME="$D/live" NL_REPO_ROOT="$D/repo" \
           NL_PORTABILITY_SWEEP_ACTIVE=1 DOCTOR_PORTABILITY_ROOTS="hooks" \
           bash "$SELF_TEST_HOOK" --portability "$D/repo" 2>&1)"; RC=$?
    _assert "9c-portability-depth-guard-skips" 0 "$RC" "WARN portability-sweep.*depth guard" "$OUT"

    # P6 — a baseline entry that now passes is WARNed (stale amnesty), never
    # REDded. Silence here would let an obsolete exemption live forever.
    D=$(_port_fixture c11-port-stale)
    printf 'FAIL\thooks/pp-known-fail.sh\nFAIL\thooks/pp-pass.sh\n' > "$D/repo/docs/portability-baseline.txt"
    OUT="$(_port_run "$D")"; RC=$?
    _assert "9c-portability-stale-baseline-warns-not-reds" 0 "$RC" "WARN portability-sweep.*now PASS" "$OUT"

    # P7 — the check is genuinely wired into --full, not only into the new
    # --portability mode. Asserted on OUTPUT (not rc) because --full also runs
    # every other check against a bare fixture.
    D=$(_port_fixture c11-port-full)
    printf '#!/bin/bash\nif [[ "${1:-}" == "--self-test" ]]; then echo "boom" >&2; exit 1; fi\nexit 0\n' \
      > "$D/repo/adapters/claude-code/hooks/pp-new-fail.sh"
    chmod +x "$D/repo/adapters/claude-code/hooks/pp-new-fail.sh"
    OUT="$(HARNESS_DOCTOR_HOME="$D/live" NL_REPO_ROOT="$D/repo" \
           NL_PORTABILITY_SWEEP_ACTIVE=0 DOCTOR_PORTABILITY_ROOTS="hooks" \
           DOCTOR_PORTABILITY_PER_TIMEOUT=10 DOCTOR_PORTABILITY_BUDGET=90 \
           bash "$SELF_TEST_HOOK" --full "$D/repo" 2>&1)"; RC=$?
    if printf '%s' "$OUT" | grep -q "RED portability-sweep"; then
      echo "self-test (9c-portability-wired-into-full): PASS" >&2; PASSED=$((PASSED + 1))
    else
      echo "self-test (9c-portability-wired-into-full): FAIL (--full did not run check 9): $OUT" >&2; FAILED=$((FAILED + 1))
    fi
  else
    echo "self-test (9c-portability): FAIL (scripts/portability-sweep.sh or hooks/lib/portable-timeout.sh not found next to this hook — check 9 went UNTESTED)" >&2
    FAILED=$((FAILED + 1))
  fi

  # ---- selftest-exclusions (macos-portability M6): the exclusion ledger must
  # never become unenforced text. Three scenarios; all use "$BASH" rather than
  # a bare `bash` so the verdict is for the interpreter actually under test.
  # RED: a ledger with no reader — the exact "comment a future sweep ignores"
  # failure M6 was written to prevent.
  D=$(_scenario_dir m6-excl-red)
  _stamp_claim_honesty_green "$D"
  mkdir -p "$D/repo/adapters/claude-code/config"
  printf '%s\n' "adapters/claude-code/attic/x.sh  a reason long enough to clear the minimum bar" \
    > "$D/repo/adapters/claude-code/config/selftest-sweep-exclusions.txt"
  OUT="$(HARNESS_DOCTOR_HOME="$D/live" NL_REPO_ROOT="$D/repo" "$BASH" "$SELF_TEST_HOOK" --quick "$D/repo" 2>&1)"; RC=$?
  _assert "m6-exclusions-ledger-without-reader-red" 1 "$RC" "RED selftest-exclusions" "$OUT"

  # RED: a reader that carries no --self-test entrypoint — its C1/C2/C3/C4
  # controls would be unverifiable, which is the same theater one level down.
  D=$(_scenario_dir m6-excl-red2)
  _stamp_claim_honesty_green "$D"
  mkdir -p "$D/repo/adapters/claude-code/config"
  printf '%s\n' "adapters/claude-code/attic/x.sh  a reason long enough to clear the minimum bar" \
    > "$D/repo/adapters/claude-code/config/selftest-sweep-exclusions.txt"
  printf '%s\n' '#!/bin/bash' 'exit 0' \
    > "$D/repo/adapters/claude-code/scripts/selftest-sweep-exclusions.sh"
  OUT="$(HARNESS_DOCTOR_HOME="$D/live" NL_REPO_ROOT="$D/repo" "$BASH" "$SELF_TEST_HOOK" --quick "$D/repo" 2>&1)"; RC=$?
  _assert "m6-exclusions-reader-without-selftest-red" 1 "$RC" "RED selftest-exclusions" "$OUT"

  # GREEN: ledger + reader declaring --self-test.
  D=$(_scenario_dir m6-excl-green)
  _stamp_claim_honesty_green "$D"
  mkdir -p "$D/repo/adapters/claude-code/config"
  printf '%s\n' "adapters/claude-code/attic/x.sh  a reason long enough to clear the minimum bar" \
    > "$D/repo/adapters/claude-code/config/selftest-sweep-exclusions.txt"
  printf '%s\n' '#!/bin/bash' 'case "${1:-}" in --self-test) exit 0 ;; esac' 'exit 0' \
    > "$D/repo/adapters/claude-code/scripts/selftest-sweep-exclusions.sh"
  OUT="$(HARNESS_DOCTOR_HOME="$D/live" NL_REPO_ROOT="$D/repo" "$BASH" "$SELF_TEST_HOOK" --quick "$D/repo" 2>&1)"; RC=$?
  _assert "m6-exclusions-wired-green" 0 "$RC" "" "$OUT"
  if printf '%s' "$OUT" | grep -q "selftest-exclusions"; then
    echo "self-test (m6-exclusions-green-is-silent): FAIL (green fixture still mentioned selftest-exclusions)" >&2
    FAILED=$((FAILED + 1))
  else
    echo "self-test (m6-exclusions-green-is-silent): PASS" >&2
    PASSED=$((PASSED + 1))
  fi

  # ---- stage2-admission-open (gated-pipeline-master-2026-08 T24, REQ-C6).
  # Key absent entirely -> completely silent. T8 (REQ-A8 triage) has not
  # landed the date yet, so this check must never fire before then. ----
  D=$(_scenario_dir s2a-absent-silent)
  _stamp_claim_honesty_green "$D"
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  mkdir -p "$D/repo/adapters/claude-code/config" "$D/repo/docs/plans"
  cat > "$D/repo/adapters/claude-code/config/schedule-manifest.json" <<'EOF'
{"schema_version":3,"cadence_check":{"ratio_floor":2}}
EOF
  OUT="$(_run_quick "$D")"; RC=$?
  if printf '%s' "$OUT" | grep -q "stage2-admission-open"; then
    echo "self-test (stage2-admission-key-absent-silent): FAIL (unexpected stage2-admission-open line): $OUT" >&2
    FAILED=$((FAILED + 1))
  else
    echo "self-test (stage2-admission-key-absent-silent): PASS" >&2
    PASSED=$((PASSED + 1))
  fi

  # ---- stage2-admission-open. Key present but explicit JSON null -> also
  # silent (the pre-T8 placeholder shape this task's own manifest edit
  # ships). ----
  D=$(_scenario_dir s2a-null-silent)
  _stamp_claim_honesty_green "$D"
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  mkdir -p "$D/repo/adapters/claude-code/config" "$D/repo/docs/plans"
  cat > "$D/repo/adapters/claude-code/config/schedule-manifest.json" <<'EOF'
{"schema_version":3,"stage2_admission":{"opened_since":null}}
EOF
  OUT="$(_run_quick "$D")"; RC=$?
  if printf '%s' "$OUT" | grep -q "stage2-admission-open"; then
    echo "self-test (stage2-admission-key-null-silent): FAIL (unexpected stage2-admission-open line): $OUT" >&2
    FAILED=$((FAILED + 1))
  else
    echo "self-test (stage2-admission-key-null-silent): PASS" >&2
    PASSED=$((PASSED + 1))
  fi

  # ---- TWO-STATE PROOF, state A (T24's load-bearing deliverable): date
  # set, no ACTIVE plan carries the stage-2-successor marker -> WARN
  # present, rc=0 (WARN-only check, never RED -- arch-M3). ----
  D=$(_scenario_dir s2a-warn-present)
  _stamp_claim_honesty_green "$D"
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  mkdir -p "$D/repo/adapters/claude-code/config" "$D/repo/docs/plans"
  cat > "$D/repo/adapters/claude-code/config/schedule-manifest.json" <<'EOF'
{"schema_version":3,"stage2_admission":{"opened_since":"2026-08-03"}}
EOF
  printf '# Plan: Unrelated\nStatus: ACTIVE\n' > "$D/repo/docs/plans/unrelated.md"
  OUT="$(_run_quick "$D")"; RC=$?
  _assert "stage2-admission-warn-present-no-successor-plan" 0 "$RC" "WARN stage2-admission-open.*stage-2 admission open since 2026-08-03" "$OUT"

  # ---- TWO-STATE PROOF, state B: SAME opened_since, but a fixture ACTIVE
  # plan now carries `stage-2-successor: gated-pipeline-master-2026-08` ->
  # the WARN CLEARS (silent), proving the detection mechanism actually
  # resolves the obligation rather than latching permanently. ----
  D=$(_scenario_dir s2a-warn-clears)
  _stamp_claim_honesty_green "$D"
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  mkdir -p "$D/repo/adapters/claude-code/config" "$D/repo/docs/plans"
  cat > "$D/repo/adapters/claude-code/config/schedule-manifest.json" <<'EOF'
{"schema_version":3,"stage2_admission":{"opened_since":"2026-08-03"}}
EOF
  printf '# Plan: Unrelated\nStatus: ACTIVE\n' > "$D/repo/docs/plans/unrelated.md"
  printf '# Plan: Stage 2 Stubs\nStatus: ACTIVE\nstage-2-successor: gated-pipeline-master-2026-08\n' \
    > "$D/repo/docs/plans/stage2-successor.md"
  OUT="$(_run_quick "$D")"; RC=$?
  if printf '%s' "$OUT" | grep -q "stage2-admission-open"; then
    echo "self-test (stage2-admission-warn-clears-with-matching-plan): FAIL (WARN still present with a matching ACTIVE Stage-2 plan): $OUT" >&2
    FAILED=$((FAILED + 1))
  else
    echo "self-test (stage2-admission-warn-clears-with-matching-plan): PASS" >&2
    PASSED=$((PASSED + 1))
  fi
  if [[ "$RC" -ne 0 ]]; then
    echo "self-test (stage2-admission-warn-clears-with-matching-plan-rc): FAIL (rc=${RC}, expected 0)" >&2
    FAILED=$((FAILED + 1))
  else
    echo "self-test (stage2-admission-warn-clears-with-matching-plan-rc): PASS" >&2
    PASSED=$((PASSED + 1))
  fi

  # ---- Edge: the marker line is present but the plan carrying it is NOT
  # ACTIVE (e.g. COMPLETED) -> does not satisfy admission; WARN stays. Guards
  # against matching the marker alone without also requiring Status: ACTIVE. ----
  D=$(_scenario_dir s2a-marker-not-active)
  _stamp_claim_honesty_green "$D"
  _write_settings "$D/live/settings.json"
  cp "$D/live/settings.json" "$D/repo/adapters/claude-code/settings.json.template"
  mkdir -p "$D/repo/adapters/claude-code/config" "$D/repo/docs/plans"
  cat > "$D/repo/adapters/claude-code/config/schedule-manifest.json" <<'EOF'
{"schema_version":3,"stage2_admission":{"opened_since":"2026-08-03"}}
EOF
  printf '# Plan: Stage 2 Stubs\nStatus: COMPLETED\nstage-2-successor: gated-pipeline-master-2026-08\n' \
    > "$D/repo/docs/plans/stage2-successor-completed.md"
  OUT="$(_run_quick "$D")"; RC=$?
  _assert "stage2-admission-marker-plan-not-active-still-warns" 0 "$RC" "WARN stage2-admission-open" "$OUT"

  echo "" >&2
  echo "self-test summary: ${PASSED} passed, ${FAILED} failed" >&2
  if [[ "$FAILED" -gt 0 ]]; then
    exit 1
  fi
  exit 0
fi

# ============================================================
# Normal (non-self-test) invocation
# ============================================================

# NL-FINDING-040 keystone guard: an automation-spawned/re-entrant
# invocation (NL_HOOK_REENTRY=1) exits fast here, BEFORE run_quick_checks
# (which does real filesystem/git scanning work across the live mirror +
# repo) ever runs. --self-test is UNAFFECTED (this check sits after the
# --self-test dispatch above, which already returned/exited). Exit 0 (not
# an error — doctor is advisory, never blocking; see header "DEPENDENCIES"
# note).
if command -v hook_reentry_should_suppress >/dev/null 2>&1 && hook_reentry_should_suppress; then
  hook_reentry_note "harness-doctor" 2>/dev/null || true
  echo "[doctor] reentrant/automation-spawned invocation — skipping checks (NL-FINDING-040 guard)"
  exit 0
fi

MODE="${1:-quick}"
case "$MODE" in
  --quick|quick) MODE="quick" ;;
  --full|full) MODE="full" ;;
  # --portability runs ONLY check 9. `--full` also runs it, but --full is a
  # multi-minute run of every live self-test; an author who just touched a
  # shell script wants the portability answer alone.
  --portability|portability) MODE="portability" ;;
  *) MODE="quick" ;;
esac

# Second positional arg (self-test-only usage) lets the self-test harness
# pass an explicit repo root without relying on git in the sandbox.
EXPLICIT_REPO_ROOT="${2:-}"

LIVE_HOME="$(resolve_live_home)"
if [[ -n "$EXPLICIT_REPO_ROOT" ]]; then
  REPO_ROOT="$EXPLICIT_REPO_ROOT"
else
  REPO_ROOT="$(resolve_repo_root)"
fi

if [[ -z "${REPO_ROOT:-}" ]]; then
  echo "[doctor] WARN repo-root: could not resolve repo root (git unavailable and NL_REPO_ROOT unset) — repo-relative checks will warn"
fi

# harness-execution-redesign-2026-08 Task 1 (Stage 0a, invariant 4):
# universal single-flight/recursion guard, called UNCONDITIONALLY — no
# wiring marker (NL_SESSIONSTART_ORIGIN, NL_HOOK_REENTRY) required from
# any caller anywhere in the chain. This is intentionally BROADER than the
# SESSIONSTART-SINGLEFLIGHT-01 block below: it also debounces/recursion-
# guards explicit/manual invocations, which is a deliberate behavior
# change (invariant 4: "wiring markers become belt, never braces" — this
# lib guard is now the PRIMARY, unconditional defense; the marker-gated
# block below stays as an additional, narrower layer, unchanged). An
# operator re-running `harness-doctor.sh --quick` twice within the TTL
# gets an honest one-line skip notice (SF_DISABLE=1 bypasses it).
# SF_STATE_DIR is scoped to the RESOLVED LIVE_HOME (not a bare $HOME
# default) for the same reason SSF_STATE_DIR is scoped below: this
# doctor's own --self-test sandboxes LIVE_HOME via HARNESS_DOCTOR_HOME, and
# an unscoped lock would make every fixture scenario in the self-test
# suite single-flight against every OTHER scenario's invocation instead of
# against the real machine's ~/.claude. See lib/single-flight-lib.sh
# header for the full recursion-vs-single-flight contract.
#
# gated-pipeline-master-2026-08 Task 4 (REQ-A2, fixing HR-F2+F5+F8): a skip
# here is NEVER a bare `exit 0` anymore -- that was indistinguishable from
# a real GREEN to every exit-code consumer (F8), and composed with digest's
# old cache writer to corrupt the cache on every skip (F2). sf_guard's own
# `echo ... >&2` above (HALT vs single-flight vs recursion) still fires
# normally on this call -- it is NOT captured/consumed here, so a caller
# combining stdout+stderr (2>&1, as every self-test scenario below does)
# still sees the specific reason. _doctor_serve_cache_or_skip then serves
# the cached verdict (fast path, matches the sf-skip's own spirit: the
# guard mostly exists because a real recompute was JUST done a moment ago)
# or exits 3 with a parseable line when no valid cache exists yet.
#
# TTL = 1200s (HR-F3, 2026-08-03 harness review, gated-pipeline T7/REQ-A5):
# the review measured a 552s cold `--quick` cycle; a fresh re-measurement
# during this fix (2026-08-03, SF_DISABLE=1 DOCTOR_VERDICT_CACHE_DISABLE=1
# bash harness-doctor.sh --quick, timed via epoch delta) got 421s and 425s
# on two separate runs -- the OLD 120s TTL was ~4x SHORTER than the work it
# guards, so the guard lapsed mid-run and concurrent doctors became
# possible again exactly when the estate is degraded and runs are longest
# (the brief's own cadence-< cycle pathology, reproduced inside the
# mechanism built to kill it). 1200s is >= 2x every measurement above with
# real margin. This is now belt-and-suspenders with `_sf_is_stale`'s
# owner-pid liveness check (single-flight-lib.sh, same finding): a live
# owner is never reclaimed regardless of TTL, so 1200s only matters for
# the case liveness can't cover (owner confirmed dead, or unrecorded).
if declare -F sf_guard >/dev/null 2>&1; then
  if ! SF_STATE_DIR="${LIVE_HOME}/state/single-flight" sf_guard "doctor-quick" 1200; then
    _doctor_serve_cache_or_skip "single-flight guard active"
  fi
fi

# ---- SESSIONSTART-SINGLEFLIGHT-01 (T3 extension, agent-efficiency-fixes-2026-07) ----
# settings.json.template's SessionStart wiring marks ITS OWN call with
# NL_SESSIONSTART_ORIGIN=1 (never set by an operator/agent typing
# `harness-doctor.sh --quick`/`--full` by hand, and never set by
# health-tick.sh's own refresh via session-start-digest.sh's
# --refresh-doctor-cache path) so we can debounce ONLY the SessionStart-
# origin call: when N sessions start within ~2 min, the FIRST one's quick
# check covers the rest. This doctor's checks are machine-GLOBAL — LIVE_HOME
# is the one shared ~/.claude, and REPO_ROOT resolves to the one canonical NL
# checkout regardless of which project directory a given session started in
# (see resolve_repo_root — it derives from SCRIPT_DIR, not $PWD) — so, unlike
# session-start-digest.sh's per-$PWD lock, NO repo-scoping is needed here;
# one lock name is correct, mirroring auto-install's exact pattern. Fail-
# open: any lib/lock failure falls through to a normal run (ss_singleflight's
# own contract) — a broken lock must never suppress a real health check.
if [[ "${NL_SESSIONSTART_ORIGIN:-0}" == "1" ]]; then
  # shellcheck source=lib/sessionstart-singleflight.sh
  source "$SCRIPT_DIR/lib/sessionstart-singleflight.sh" 2>/dev/null || true
  if declare -F ss_singleflight >/dev/null 2>&1; then
    if ! SSF_STATE_DIR="${LIVE_HOME}/state/singleflight" ss_singleflight "doctor-quick" 120; then
      echo "[doctor] another SessionStart-origin session ran the quick check within ~2 min — skipping (SESSIONSTART-SINGLEFLIGHT-01)"
      exit 0
    fi
  fi
fi

# ------------------------------------------------------------
# Doctor verdict cache — READ path (Task 3, invariant 3: "doctor --quick
# serves the cached verdict in <2s on a cache hit"). Only MODE=="quick"
# consults it (full/portability always recompute for real -- their own
# multi-minute cost is not what this TTL is pricing). NL_FORCE=1 or a
# literal --no-cache argument always bypasses AND is ledgered (invariant
# 7). See _doctor_verdict_cache_path's header comment above for the schema
# + why this reuses session-start-digest.sh's existing cache file.
# ------------------------------------------------------------
if [[ "$MODE" == "quick" && "${DOCTOR_VERDICT_CACHE_DISABLE:-0}" != "1" ]]; then
  _dvc_bypass=0
  [[ "${NL_FORCE:-0}" == "1" ]] && _dvc_bypass=1
  for _dvc_a in "$@"; do [[ "$_dvc_a" == "--no-cache" ]] && _dvc_bypass=1; done
  if [[ "$_dvc_bypass" == "1" ]]; then
    _doctor_ledger_bypass "$LIVE_HOME" "NL_FORCE=1 or --no-cache requested a real recompute"
  else
    _dvc_cache="$(_doctor_verdict_cache_path "$LIVE_HOME")"
    if [[ -f "$_dvc_cache" ]]; then
      _dvc_ts_epoch="$(sed -nE 's/.*"ts_epoch":([0-9]+).*/\1/p' "$_dvc_cache" 2>/dev/null | head -1)"
      _dvc_fp="$(sed -nE 's/.*"fingerprint":"([^"]*)".*/\1/p' "$_dvc_cache" 2>/dev/null | head -1)"
      _dvc_verdict="$(sed -nE 's/.*"verdict_line":"([^"]*)".*/\1/p' "$_dvc_cache" 2>/dev/null | head -1)"
      _dvc_exit="$(sed -nE 's/.*"exit_code":([0-9]+).*/\1/p' "$_dvc_cache" 2>/dev/null | head -1)"
      _dvc_ttl="${DOCTOR_VERDICT_CACHE_TTL_SECONDS:-1800}"
      # An entry with no fingerprint (e.g. one written by session-start-
      # digest.sh's own --refresh-doctor-cache, which does not compute one)
      # is honestly untrusted for the fast path -- falls through to a real
      # recompute below, which then writes a fully fingerprinted entry.
      if [[ -n "$_dvc_fp" && "$_dvc_ts_epoch" =~ ^[0-9]+$ ]]; then
        _dvc_now=$(date +%s 2>/dev/null || echo 0)
        _dvc_age=$(( _dvc_now - _dvc_ts_epoch ))
        _dvc_cur_fp="$(_doctor_compute_fingerprint "$LIVE_HOME" "$REPO_ROOT")"
        if [[ "$_dvc_age" -ge 0 && "$_dvc_age" -lt "$_dvc_ttl" && "$_dvc_fp" == "$_dvc_cur_fp" ]]; then
          echo "${_dvc_verdict} (cached verdict, ${_dvc_age}s old -- run with --no-cache or NL_FORCE=1 to force a real recompute)"
          [[ "$_dvc_exit" =~ ^[0-9]+$ ]] && exit "$_dvc_exit"
          exit 0
        fi
      fi
    fi
  fi
fi

if [[ "$MODE" == "portability" ]]; then
  check_portability_sweep "$LIVE_HOME" "$REPO_ROOT"
else
  run_quick_checks "$LIVE_HOME" "$REPO_ROOT"

  # SINGLE MODE==full block (harness-review Major, fixed): a mis-indented
  # stray `fi` previously split what should have been ONE full-mode block
  # into two sequential ones, so check_selftest_sweep and
  # check_master_drift_selftest each ran TWICE per --full invocation --
  # doubling --full's multi-minute dominant runtime cost and duplicating
  # every sweep RED line. All four full-mode-only checks now run from
  # exactly this one block, exactly once each. Self-test
  # "8-selftest-sweep-not-duplicated" counts the RED lines a single failing
  # fixture hook produces (must be exactly 1) so a future regression of
  # this exact shape fails loudly instead of merely costing time.
  if [[ "$MODE" == "full" ]]; then
    check_selftest_sweep "$LIVE_HOME"
    check_master_drift_selftest "$LIVE_HOME" "$REPO_ROOT"
    check_portability_sweep "$LIVE_HOME" "$REPO_ROOT"
    check_selftest_exclusions_selftest "$REPO_ROOT"
  fi
fi

if [[ "$RED_COUNT" -eq 0 ]]; then
  _dvc_verdict_line="[doctor] GREEN — ${CHECKS_RUN} checks passed"
  _dvc_exit_code=0
else
  _dvc_verdict_line="[doctor] FAILED — ${RED_COUNT} red, ${WARN_COUNT} warn, ${CHECKS_RUN} checks run"
  _dvc_exit_code=1
fi
echo "$_dvc_verdict_line"

# ------------------------------------------------------------
# Doctor verdict cache — WRITE path. Only after a REAL quick-mode
# computation (never for --full/--portability, whose cost this TTL is not
# pricing). gated-pipeline-master-2026-08 Task 4 (REQ-A2): this is now the
# cache file's ONLY writer in the entire codebase (single-writer contract
# fixing HR-F2). session-start-digest.sh's refresh_doctor_cache is
# invoke-and-read-only -- it forces a real recompute (SF_DISABLE=1
# DOCTOR_VERDICT_CACHE_DISABLE=1, which lands right here) and then reads
# back this exact record; it never printfs the file. ts_epoch + fingerprint
# so THIS reader (and only this reader) can serve a fast-path hit next time
# (invariant 8: the fingerprint is derived, not authored, from the declared
# inputs above).
# ------------------------------------------------------------
if [[ "$MODE" == "quick" ]]; then
  _dvc_write_cache="$(_doctor_verdict_cache_path "$LIVE_HOME")"
  mkdir -p "$(dirname "$_dvc_write_cache")" 2>/dev/null || true
  _dvc_write_ts="$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || echo unknown)"
  _dvc_write_epoch=$(date +%s 2>/dev/null || echo 0)
  _dvc_write_fp="$(_doctor_compute_fingerprint "$LIVE_HOME" "$REPO_ROOT")"
  _dvc_verdict_esc="${_dvc_verdict_line//\\/\\\\}"; _dvc_verdict_esc="${_dvc_verdict_esc//\"/\\\"}"
  _dvc_write_tmp="${_dvc_write_cache}.tmp.$$"
  printf '{"ts":"%s","ts_epoch":%s,"verdict_line":"%s","exit_code":%d,"fingerprint":"%s"}\n' \
    "$_dvc_write_ts" "$_dvc_write_epoch" "$_dvc_verdict_esc" "$_dvc_exit_code" "$_dvc_write_fp" \
    > "$_dvc_write_tmp" 2>/dev/null && mv -f "$_dvc_write_tmp" "$_dvc_write_cache" 2>/dev/null \
    || rm -f "$_dvc_write_tmp" 2>/dev/null
fi

exit "$_dvc_exit_code"
