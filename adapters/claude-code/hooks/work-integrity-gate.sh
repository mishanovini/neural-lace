#!/bin/bash
# work-integrity-gate.sh — Stop hook (NL Overhaul Wave D, task D.2).
#
# ============================================================
# WHAT THIS HOOK DOES
# ============================================================
#
# Merges three existing Stop-hook checks into ONE blocking gate, each
# SCOPED to the plans/files THIS SESSION actually touched (transcript-
# derived), rather than every ACTIVE plan in the repo:
#
#   (a) pre-stop-verifier's per-task evidence check — unchecked tasks +
#       missing/malformed evidence blocks — but ONLY for plans this
#       session edited (per its own tool_use history in the transcript).
#   (b) product-acceptance-gate's acceptance-artifact check — ONLY for
#       plans this session edited; honors `acceptance-exempt: true`
#       (+ substantive reason) and the per-session waiver file.
#   (c) worktree-teardown-gate's uncommitted-work check — this is
#       WORKTREE-scoped, not plan-scoped: a dirty linked worktree at
#       Stop blocks with exact rescue commands (preserve-first, never
#       toward --force deletion).
#
# WHY SCOPING MATTERS (the waiver-tax this replaces)
# ===================================================
# The three predecessor hooks each independently discovered "the most
# recently modified plan" or "every ACTIVE plan in docs/plans/", which
# means a session that touches ONE plan gets blocked on the state of
# EVERY OTHER ACTIVE plan in the repo — plans it never opened, may not
# even know exist. That forces waivers/exemptions on unrelated plans
# just to end an unrelated session ("waiver-tax"). This gate fixes that
# structurally: it parses ITS OWN session's transcript for tool_use
# entries whose file_path lands under a docs/plans/ directory, and only
# gates on THOSE plans. An orthogonal ACTIVE plan with unchecked tasks
# must NOT block a session that never touched it (self-test: "orthogonal
# ACTIVE plan does NOT block").
#
# ============================================================
# REMEDIATION POLICY (§D.0.9 pin — non-negotiable)
# ============================================================
# Every block message below points at an ARTIFACT fix: check a box,
# write an evidence block, run the runtime advocate, commit/stash/waive
# the worktree. NONE of them ask the final assistant message to restate
# or re-summarize anything. This hook must never be the requires-
# content-in-final-message anti-pattern.
#
# ============================================================
# LEDGER + RETRY-GUARD
# ============================================================
# Every block/warn/downgrade calls ledger_emit (signal-ledger.sh, D.1).
# Blocks route through retry_guard_block_or_exit so a session cannot be
# looped forever on a gate it cannot resolve in-loop — EXCEPT this hook
# is registered in RETRY_GUARD_VERIFICATION_HOOKS (stop-hook-retry-
# guard.sh default, edited by this same task), so a downgrade is
# REFUSED while the final assistant message claims `DONE:` (verification-
# gate integrity — see stop-hook-retry-guard.sh's 2026-06-09 note).
#
# ============================================================
# SANDBOXING
# ============================================================
# HARNESS_SELFTEST=1 is honored transitively by signal-ledger.sh (every
# ledger_emit call routes to a sandboxed path) and directly by this
# hook's own --self-test harness, which builds synthetic repos under a
# tempdir and never touches real repo/ledger state.
#
# ============================================================
# EXIT CODES
# ============================================================
#   0 — session may terminate
#   2 — session is blocked; stderr explains why, stdout carries
#       {"decision":"block", ...} JSON (Claude Code Stop-hook contract)

set -u

SCRIPT_NAME="work-integrity-gate.sh"

# ============================================================
# --self-test: see bottom-of-file block for the >=12 scenarios.
# Declared as a function so production sourcing order (libs first) is
# unaffected; invoked at the very end of the file.
# ============================================================

# Shared libs. Signal ledger first (best-effort; retry-guard also
# sources it, but we call ledger_emit directly for warns that never
# reach retry-guard, so we source it ourselves too — source-guarded,
# so double-sourcing is a no-op).
# NOTE: ${BASH_SOURCE[0]%/*} breaks when the script is invoked slashless from its
# own directory (`bash work-integrity-gate.sh` → "work-integrity-gate.sh/lib/…"),
# silently skipping both libs. Resolve the directory robustly instead.
_WIG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$_WIG_DIR/lib/signal-ledger.sh"
# shellcheck disable=SC1091
source "$_WIG_DIR/lib/stop-hook-retry-guard.sh"

# ----------------------------------------------------------------------
# _wig_ledger <event> <detail>  — best-effort, never fails the hook.
# ----------------------------------------------------------------------
_wig_ledger() {
  local event="$1" detail="$2"
  if command -v ledger_emit >/dev/null 2>&1; then
    ledger_emit "work-integrity-gate" "$event" "$detail"
  fi
}

# ----------------------------------------------------------------------
# _wig_block <check> <sig> <err_msg> <block_json>
#   Wraps retry_guard_block_or_exit; logs to the ledger first. Never
#   returns.
# ----------------------------------------------------------------------
_wig_block() {
  local check="$1" sig="$2" err_msg="$3" block_json="$4"
  _wig_ledger "block" "${check}: ${err_msg}"
  retry_guard_block_or_exit \
    "work-integrity-gate" \
    "$RG_SESSION_ID" \
    "work-integrity:${check}:${sig}" \
    "$err_msg" \
    "$block_json" \
    2
}

# ============================================================
# Transcript-derived scoping: which plans did THIS SESSION touch?
# ============================================================
#
# Technique mirrors pre-stop-verifier / goal-coverage-on-stop / transcript-
# lie-detector: read the Stop event's JSON off stdin, pull transcript_path,
# and jq the JSONL for assistant tool_use entries. We only need Edit/Write/
# Read file_path values (the paths that show the session actually opened
# or modified a file) — a plan is "session-touched" if ANY such path
# resolves under a discovered docs/plans/ directory and ends in .md.
#
# Fails open: no transcript / no jq / unparseable => empty touched-set =>
# checks (a) and (b) below are no-ops (nothing to scope them to). Check
# (c), the worktree check, does not depend on scoping and still runs.
_wig_touched_plan_paths() {
  local transcript_path="$1"
  [[ -n "$transcript_path" && -f "$transcript_path" ]] || return 0
  command -v jq >/dev/null 2>&1 || return 0

  jq -r '
    if (.role == "assistant" or .message.role == "assistant") then
      ((.content // .message.content // empty)
       | if type == "array" then
           [ .[]
             | select(type == "object" and .type == "tool_use")
             | select(.name == "Edit" or .name == "Write" or .name == "Read")
             | (.input.file_path // "")
           ] | .[]
         else empty end)
    else empty end
  ' "$transcript_path" 2>/dev/null | grep -E '(^|[/\\])docs[/\\]plans[/\\][^/\\]+\.md$' | sort -u
}

# Given the raw touched-path list (possibly Windows- or POSIX-separated,
# possibly relative to a worktree other than cwd), reduce to a set of
# plan SLUGS (basename without .md), and separately resolve each to a
# real on-disk path under the CURRENT cwd's discovered plan dirs (the
# only ones this hook's other checks can actually read). A path whose
# slug doesn't exist under any discovered dir here is dropped — most
# commonly this means the session touched a plan in a different
# worktree/repo, which is out of scope for this session's Stop gate.
_wig_resolve_touched_plans() {
  local raw="$1"
  shift
  local -a plan_dirs=("$@")
  local line slug found dir cand
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    # Normalize backslashes to forward slashes for basename purposes.
    line="${line//\\//}"
    slug="$(basename "$line" .md)"
    [[ -z "$slug" ]] && continue
    found=""
    for dir in "${plan_dirs[@]}"; do
      cand="$dir/$slug.md"
      if [[ -f "$cand" ]]; then
        found="$cand"
        break
      fi
    done
    [[ -n "$found" ]] && printf '%s\n' "$found"
  done <<< "$raw" | sort -u
}

# ============================================================
# Check (a): per-task evidence (pre-stop-verifier subset)
#
# For a single plan file, blocks (via _wig_block, never returns) if:
#   - the plan is ACTIVE or COMPLETED and has unchecked "- [ ]" tasks
#   - any checked task lacks a matching evidence block (companion file
#     or in-plan ## Evidence Log)
# Skips (no-op) plans that are ABANDONED/DEFERRED.
# ============================================================
_wig_check_evidence() {
  local plan="$1"
  local evidence_file="${plan%.md}-evidence.md"

  grep -qiE '^Status:\s*(ABANDONED|DEFERRED)' "$plan" 2>/dev/null && return 0

  local is_completed=0
  grep -qiE '^Status:\s*COMPLETED' "$plan" 2>/dev/null && is_completed=1

  local pending
  pending=$(grep -c '^- \[ \]' "$plan" 2>/dev/null || echo "0")
  pending=$(echo "$pending" | tr -d '[:space:]')

  if [[ "${pending:-0}" -gt 0 ]] && [[ "$is_completed" -eq 0 ]]; then
    # Escape hatch (ADR 058 D5 pin d + ADR 059 D4 waiver parity —
    # NL-FINDING-019/020): a fresh (<1h) non-empty per-session waiver
    # acknowledging the open tasks. Intended use: long-running multi-session
    # program plans (Execution Mode: orchestrator) whose remaining tasks
    # continue in OTHER sessions by design, and sessions whose only plan
    # touch was incidental (e.g., the in-flight scope-update line the
    # scope-enforcement gate itself mandates) — without this valve, check (a)
    # deadlocks the session end (observed live 2026-07-03: four Stop cycles
    # to end a session whose deliverable was already merged).
    # ADR 059 D4 scoping rule: the waiver clears ONLY this world-state
    # assertion (unchecked tasks on an ACTIVE plan). Session-honesty
    # assertions — checked-box-without-evidence below, and the
    # COMPLETED-but-unchecked contradiction (is_completed guard above) —
    # are resolvable by the session that created them and get no valve.
    # Every use is ledger-logged so the E.3/E.5 waiver-density telemetry
    # counts it.
    local slug wbase waiver_a
    slug=$(basename "${plan%.md}")
    wbase=$(dirname "$(git rev-parse --git-common-dir 2>/dev/null || echo .git)")
    waiver_a=$(_wig_check_waiver "$slug" "work-integrity-waiver" ".claude/state" "${wbase}/.claude/state")
    case "$waiver_a" in
      VALID_WAIVER:*)
        echo "[work-integrity] unchecked-tasks waived for ${slug} (fresh per-session waiver at ${waiver_a#VALID_WAIVER:}; open tasks continue in other sessions). Evidence checks for checked boxes still apply." >&2
        _wig_ledger "waiver" "check-a waived: ${slug} (${pending} unchecked; ${waiver_a#VALID_WAIVER:})"
        pending=0
        ;;
      EMPTY_WAIVER)
        echo "[work-integrity] a fresh work-integrity-waiver for ${slug} exists but is EMPTY — not honored (>=1 substantive line required; falling through to the block)." >&2
        ;;
    esac
  fi

  if [[ "${pending:-0}" -gt 0 ]]; then
    local msg
    if [[ "$is_completed" -eq 1 ]]; then
      msg="Session-touched plan $plan has Status: COMPLETED but $pending task(s) are still unchecked. A plan cannot be marked COMPLETED while any task remains unchecked. Check the box after actually completing the task, or set Status: ACTIVE/ABANDONED to reflect reality."
    else
      msg="Session-touched plan $plan has $pending unchecked task(s) remaining. Complete and check them; or set Status: ABANDONED with a reason; or — for a multi-session program plan whose tasks continue elsewhere by design — write a fresh waiver: .claude/state/work-integrity-waiver-<plan-slug>-<ts>.txt (>=1 substantive line naming WHY the open tasks are legitimately in flight; expires in 1h). Note: this block prevented only session-end — no other part of your command ran or was lost."
    fi
    echo "" >&2
    echo "================================================================" >&2
    echo "WORK-INTEGRITY GATE — BLOCKED (check a: unchecked tasks)" >&2
    echo "================================================================" >&2
    echo "$msg" >&2
    echo "" >&2
    _wig_block "check-a-pending" "${plan}:${pending}" "$msg" \
      "{\"decision\": \"block\", \"reason\": \"$msg\"}"
  fi

  local checked_ids
  checked_ids=$(grep -oE '^- \[x\] [A-Z]+\.[0-9]+(\.[0-9]+)*' "$plan" 2>/dev/null | sed 's/^- \[x\] //' | sort -u)
  [[ -z "$checked_ids" ]] && return 0

  local has_evidence_file=0 has_evidence_section=0
  [[ -f "$evidence_file" ]] && has_evidence_file=1
  grep -q '^## Evidence Log' "$plan" 2>/dev/null && has_evidence_section=1

  if [[ "$has_evidence_file" -eq 0 && "$has_evidence_section" -eq 0 ]]; then
    local msg="Session-touched plan $plan has checked tasks but no evidence found (expected $evidence_file or an ## Evidence Log section). Run the task-verifier agent on each checked task to generate an evidence block."
    echo "" >&2
    echo "================================================================" >&2
    echo "WORK-INTEGRITY GATE — BLOCKED (check a: no evidence)" >&2
    echo "================================================================" >&2
    echo "$msg" >&2
    echo "" >&2
    _wig_block "check-a-no-evidence" "${plan}:${checked_ids}" "$msg" \
      "{\"decision\": \"block\", \"reason\": \"$msg\"}"
  fi

  local missing_evidence="" missing_count=0
  while IFS= read -r id; do
    [[ -z "$id" ]] && continue
    local found=0
    if [[ "$has_evidence_file" -eq 1 ]] && grep -qE "^Task ID:[[:space:]]*$id([[:space:]]|$)" "$evidence_file" 2>/dev/null; then
      found=1
    fi
    if [[ "$found" -eq 0 ]] && grep -qE "^Task ID:[[:space:]]*$id([[:space:]]|$)" "$plan" 2>/dev/null; then
      found=1
    fi
    if [[ "$found" -eq 0 ]]; then
      missing_evidence+="  - $id"$'\n'
      missing_count=$((missing_count + 1))
    fi
  done <<< "$checked_ids"

  if [[ "$missing_count" -gt 0 ]]; then
    local msg="Session-touched plan $plan has $missing_count checked task(s) without matching evidence blocks. Every completed task needs a task-verifier evidence block; self-checking without verification is not allowed."
    echo "" >&2
    echo "================================================================" >&2
    echo "WORK-INTEGRITY GATE — BLOCKED (check a: missing task evidence)" >&2
    echo "================================================================" >&2
    echo "$msg" >&2
    echo "" >&2
    echo "Tasks missing evidence blocks:" >&2
    echo "$missing_evidence" >&2
    echo "To resolve: invoke the task-verifier agent for each task above; it appends an evidence block to $evidence_file. If a task was checked by mistake, uncheck it manually." >&2
    echo "" >&2
    _wig_block "check-a-missing-task-evidence" "${plan}:${missing_evidence}" "$msg" \
      "{\"decision\": \"block\", \"reason\": \"$msg\"}"
  fi

  return 0
}

# ============================================================
# Check (b): acceptance-artifact check (product-acceptance-gate subset)
#
# Blocks (via _wig_block) unless the plan is:
#   - not ACTIVE (no-op — acceptance only applies to ACTIVE plans), or
#   - validly exempt (acceptance-exempt: true + reason >=20 non-ws chars,
#     and does NOT declare a user-facing UI surface), or
#   - covered by a fresh (<1h) non-empty per-session waiver, or
#   - satisfied by an artifact matching the current plan_commit_sha with
#     every scenario verdict == PASS.
# ============================================================
_wig_check_exemption() {
  local plan="$1"
  if ! grep -qiE '^acceptance-exempt:[[:space:]]*true' "$plan" 2>/dev/null; then
    echo "NOT_EXEMPT"
    return
  fi
  local reason stripped
  reason=$(grep -iE '^acceptance-exempt-reason:' "$plan" 2>/dev/null | head -1 | sed 's/^[Aa]cceptance-exempt-reason:[[:space:]]*//')
  reason=$(echo "$reason" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  stripped=$(echo "$reason" | tr -d '[:space:]')
  if [[ ${#stripped} -ge 20 ]]; then
    echo "EXEMPT_OK"
  else
    echo "EXEMPT_NO_REASON"
  fi
}

_wig_plan_declares_ui_surface() {
  local plan="$1" sections
  sections=$(awk '/^## (Files to Modify\/Create|In-flight scope updates)/{f=1;next} /^## /{f=0} f' "$plan" 2>/dev/null)
  [[ -z "$sections" ]] && return 1
  printf '%s' "$sections" | grep -qE 'src/app/|src/components/|page\.tsx|[a-zA-Z0-9_-]+-ui/|/web/' && return 0
  return 1
}

_wig_get_plan_sha() {
  local plan="$1" sha
  if command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    sha=$(git log -n 1 --pretty=format:'%H' -- "$plan" 2>/dev/null || echo "")
    if [[ -n "$sha" ]]; then
      echo "$sha"
      return
    fi
  fi
  echo "UNCOMMITTED"
}

# Shared waiver validation for every waiver family this hook honors
# (ADR 059 D4 "same shape everywhere": fresh <1h + substantive first line).
# Args: <slug> [prefix=acceptance-waiver] [dir ...=.claude/state]
# Echoes NO_WAIVER | EMPTY_WAIVER | VALID_WAIVER:<path>. The first
# directory containing a fresh match decides; an empty match is reported
# as EMPTY_WAIVER (harness-reviewer 2026-07-03 Finding 1: an existence-only
# check would clear a blocking gate for a stray `touch`).
_wig_check_waiver() {
  local slug="$1" prefix="${2:-acceptance-waiver}"
  local dirs=("${@:3}")
  [[ ${#dirs[@]} -eq 0 ]] && dirs=(".claude/state")
  local waiver_dir recent first_line_stripped
  for waiver_dir in "${dirs[@]}"; do
    [[ -d "$waiver_dir" ]] || continue
    recent=$(find "$waiver_dir" -maxdepth 1 -type f -name "${prefix}-${slug}-*.txt" -newermt '1 hour ago' 2>/dev/null | head -1)
    [[ -z "$recent" ]] && continue
    first_line_stripped=$(head -1 "$recent" 2>/dev/null | tr -d '[:space:]')
    if [[ -z "$first_line_stripped" ]]; then
      echo "EMPTY_WAIVER"
    else
      echo "VALID_WAIVER:${recent}"
    fi
    return
  done
  echo "NO_WAIVER"
}

# Artifact check: cwd-local only (this merged gate does not aggregate
# across worktrees — a deliberate minimal-delta scope trim from
# product-acceptance-gate's multi-worktree search; the per-session
# waiver valve remains the escape hatch for the teammate-wrote-the-
# artifact-elsewhere case). Echoes SATISFIED | NO_DIRECTORY |
# NO_ARTIFACTS | STALE | FAIL.
_wig_check_artifact() {
  local plan="$1" slug dir artifacts current_sha
  slug=$(basename "$plan" .md)
  dir=".claude/state/acceptance/${slug}"
  if [[ ! -d "$dir" ]]; then
    echo "NO_DIRECTORY"
    return
  fi
  artifacts=$(find "$dir" -maxdepth 1 -type f -name '*.json' 2>/dev/null)
  if [[ -z "$artifacts" ]]; then
    echo "NO_ARTIFACTS"
    return
  fi
  current_sha=$(_wig_get_plan_sha "$plan")
  local found_matching_sha=0 found_all_pass=0 artifact artifact_sha verdict_lines has_non_pass
  while IFS= read -r artifact; do
    [[ -z "$artifact" ]] && continue
    [[ -f "$artifact" ]] || continue
    artifact_sha=$(grep -oE '"plan_commit_sha"[[:space:]]*:[[:space:]]*"[^"]+"' "$artifact" 2>/dev/null | head -1 | sed -E 's/.*"plan_commit_sha"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/')
    if [[ "$artifact_sha" == "$current_sha" ]]; then
      found_matching_sha=1
      verdict_lines=$(grep -oE '"verdict"[[:space:]]*:[[:space:]]*"[^"]+"' "$artifact" 2>/dev/null)
      [[ -z "$verdict_lines" ]] && continue
      has_non_pass=$(echo "$verdict_lines" | grep -vE '"verdict"[[:space:]]*:[[:space:]]*"PASS"' | head -1)
      if [[ -z "$has_non_pass" ]]; then
        found_all_pass=1
        break
      fi
    fi
  done <<< "$artifacts"

  if [[ "$found_all_pass" -eq 1 ]]; then
    echo "SATISFIED"
  elif [[ "$found_matching_sha" -eq 1 ]]; then
    echo "FAIL"
  else
    echo "STALE"
  fi
}

_wig_check_acceptance() {
  local plan="$1" slug
  slug=$(basename "$plan" .md)

  # Acceptance only applies to ACTIVE plans (COMPLETED/ABANDONED/DEFERRED
  # are out of scope for the runtime-acceptance question).
  grep -qiE '^Status:[[:space:]]*ACTIVE' "$plan" 2>/dev/null || return 0

  local exempt_status refused_msg=""
  exempt_status=$(_wig_check_exemption "$plan")
  case "$exempt_status" in
    EXEMPT_OK)
      if _wig_plan_declares_ui_surface "$plan"; then
        refused_msg="Plan ${slug} declares acceptance-exempt: true but its declared files include user-facing surfaces (src/app/, src/components/, page.tsx, *-ui/, /web/). User-facing plans may NOT be acceptance-exempt — remove the exemption, author Acceptance Scenarios, and run end-user-advocate in runtime mode."
      else
        local reason
        reason=$(grep -iE '^acceptance-exempt-reason:' "$plan" 2>/dev/null | head -1 | sed 's/^[Aa]cceptance-exempt-reason:[[:space:]]*//')
        echo "[work-integrity-gate] plan ${slug} is acceptance-exempt; reason: ${reason}" >&2
        _wig_ledger "skip" "check-b acceptance-exempt: ${slug}"
        return 0
      fi
      ;;
    EXEMPT_NO_REASON)
      local msg="Plan ${slug} declares acceptance-exempt: true but acceptance-exempt-reason is missing or shorter than 20 non-whitespace chars. Add a substantive one-sentence reason or remove the exemption."
      echo "" >&2
      echo "================================================================" >&2
      echo "WORK-INTEGRITY GATE — BLOCKED (check b: exempt without reason)" >&2
      echo "================================================================" >&2
      echo "$msg" >&2
      echo "" >&2
      _wig_block "check-b-exempt-no-reason" "$plan" "$msg" "{\"decision\": \"block\", \"reason\": \"$msg\"}"
      ;;
    NOT_EXEMPT) ;;
  esac

  # Per-session waiver valve — checked whether or not the exemption was
  # refused (a refused exemption must not skip the waiver escape hatch).
  local waiver
  waiver=$(_wig_check_waiver "$slug")
  case "$waiver" in
    VALID_WAIVER:*)
      local waiver_path="${waiver#VALID_WAIVER:}"
      if [[ -n "$refused_msg" ]]; then
        echo "[work-integrity-gate] plan ${slug}: exemption refused (UI surface) but valid waiver present at ${waiver_path}; allowing." >&2
        _wig_ledger "waiver" "check-b refused-exemption-but-waived: ${slug} (${waiver_path})"
      else
        echo "[work-integrity-gate] plan ${slug} has a per-session waiver at ${waiver_path}; allowing." >&2
        _wig_ledger "waiver" "check-b waived: ${slug} (${waiver_path})"
      fi
      return 0
      ;;
    EMPTY_WAIVER)
      local msg="${refused_msg:+${refused_msg} }Plan ${slug}: a waiver file exists but is empty. Waivers must contain at least one non-whitespace line of justification."
      echo "" >&2
      echo "================================================================" >&2
      echo "WORK-INTEGRITY GATE — BLOCKED (check b: empty waiver)" >&2
      echo "================================================================" >&2
      echo "$msg" >&2
      echo "" >&2
      _wig_block "check-b-empty-waiver" "$plan" "$msg" "{\"decision\": \"block\", \"reason\": \"$msg\"}"
      ;;
    NO_WAIVER)
      if [[ -n "$refused_msg" ]]; then
        echo "" >&2
        echo "================================================================" >&2
        echo "WORK-INTEGRITY GATE — BLOCKED (check b: exemption refused, UI surface)" >&2
        echo "================================================================" >&2
        echo "$refused_msg" >&2
        echo "" >&2
        _wig_block "check-b-exempt-refused-ui" "$plan" "$refused_msg" "{\"decision\": \"block\", \"reason\": \"$refused_msg\"}"
      fi
      ;;
  esac

  local artifact_status msg
  artifact_status=$(_wig_check_artifact "$plan")
  case "$artifact_status" in
    SATISFIED)
      echo "[work-integrity-gate] plan ${slug}: PASS artifact found matching current plan_commit_sha." >&2
      return 0
      ;;
    NO_DIRECTORY)
      msg="Session-touched ACTIVE plan ${slug} has no acceptance directory at .claude/state/acceptance/${slug}. Run end-user-advocate in runtime mode against this plan, or declare acceptance-exempt: true with a substantive reason."
      ;;
    NO_ARTIFACTS)
      msg="Session-touched ACTIVE plan ${slug}: acceptance directory exists but contains no JSON artifacts. Run end-user-advocate in runtime mode."
      ;;
    STALE)
      local current_sha
      current_sha=$(_wig_get_plan_sha "$plan")
      msg="Session-touched ACTIVE plan ${slug}: artifacts exist but none match current plan_commit_sha (${current_sha}). Re-run end-user-advocate against the current HEAD of this plan file."
      ;;
    FAIL)
      msg="Session-touched ACTIVE plan ${slug}: most recent acceptance artifact for current plan_commit_sha has at least one FAIL scenario. Address the failure(s), then re-run end-user-advocate."
      ;;
  esac
  echo "" >&2
  echo "================================================================" >&2
  echo "WORK-INTEGRITY GATE — BLOCKED (check b: acceptance artifact)" >&2
  echo "================================================================" >&2
  echo "$msg" >&2
  echo "" >&2
  echo "To unblock: run the end-user-advocate (Task tool, mode=runtime, plan=${plan}), or declare acceptance-exempt: true with a substantive reason, or write a fresh per-session waiver at .claude/state/acceptance-waiver-${slug}-\$(date +%s).txt" >&2
  echo "" >&2
  _wig_block "check-b-${artifact_status}" "$plan" "$msg" "{\"decision\": \"block\", \"reason\": \"$msg\"}"
}

# ============================================================
# Check (c): worktree uncommitted-work at Stop (worktree-teardown-gate
# subset). WORKTREE-scoped, not plan-scoped — runs unconditionally.
# ============================================================
_wig_check_worktree() {
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0   # not a git repo

  local gd cd_
  gd="$(git rev-parse --git-dir 2>/dev/null)"
  cd_="$(git rev-parse --git-common-dir 2>/dev/null)"
  # main checkout (git-dir == git-common-dir) is never gated here.
  [[ -n "$gd" && -n "$cd_" && "$gd" != "$cd_" ]] || return 0

  local gd_abs
  gd_abs="$(git rev-parse --absolute-git-dir 2>/dev/null || echo "$gd")"
  [[ -f "$gd_abs/locked" ]] && return 0   # locked worktree: intentionally persistent

  local dirty=0
  if ! git diff --quiet 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then dirty=1; fi
  if [[ -n "$(git ls-files --others --exclude-standard 2>/dev/null)" ]]; then dirty=1; fi

  local branch
  branch="$(git symbolic-ref --short -q HEAD 2>/dev/null || echo "")"

  local unpushed=0 cnt
  if git rev-parse --verify --quiet '@{upstream}' >/dev/null 2>&1; then
    cnt="$(git rev-list --count '@{upstream}..HEAD' 2>/dev/null || echo 0)"
    [[ "${cnt:-0}" -gt 0 ]] && unpushed="$cnt"
  elif git rev-parse --verify --quiet origin/master >/dev/null 2>&1; then
    cnt="$(git rev-list --count origin/master..HEAD 2>/dev/null || echo 0)"
    [[ "${cnt:-0}" -gt 0 ]] && unpushed="$cnt"
  fi

  # fresh-waiver escape hatch
  if [[ -d .claude/state ]]; then
    if find .claude/state -type f -name 'worktree-teardown-waiver-*.txt' -newermt '1 hour ago' 2>/dev/null | grep -q .; then
      _wig_ledger "waiver" "check-c worktree-teardown-waiver honored"
      return 0
    fi
  fi

  if [[ "$dirty" -eq 0 && "${unpushed:-0}" -eq 0 ]]; then
    return 0   # clean + fully preserved
  fi

  if [[ "$dirty" -eq 0 ]]; then
    # clean but unpushed → advise only, non-blocking
    _wig_ledger "warn" "check-c unpushed commits (${unpushed}) on ${branch:-HEAD}"
    cat >&2 <<MSG
[work-integrity-gate] This worktree has ${unpushed} unpushed commit(s) on '${branch:-HEAD}'.
They survive 'git worktree remove' but are lost if the branch is later deleted.
To preserve durably before cleanup:  git push -u origin ${branch:-<branch>}
(Advisory only — not blocking session end.)
MSG
    return 0
  fi

  # dirty → block toward preserve-first, with EXACT rescue commands.
  local wt_path
  wt_path="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  cat >&2 <<MSG
================================================================
WORK-INTEGRITY GATE — BLOCKED (check c: dirty worktree)
================================================================

This session is ending INSIDE a linked worktree that has UNCOMMITTED
changes. Uncommitted work in a worktree is destroyed by a later
'git worktree remove --force' or 'git clean' — exactly the silent loss
the "incomplete != abandoned" principle forbids.

  worktree: $wt_path
  branch:   ${branch:-<detached>}

PRESERVE the work before ending (do NOT reach for 'git worktree remove
--force' — that deletes it). Any ONE of:

  1. Commit it, then push the branch:
       git add -A && git commit -m "<msg>" && git push -u origin ${branch:-<branch>}
  2. Stash it (survives worktree removal):
       git stash push -u -m "wip-\$(date -u +%Y%m%dT%H%M%SZ)"
  3. If this WIP is intentionally left to resume later, waive:
       mkdir -p .claude/state
       echo "<why this WIP is intentionally persistent>" > \\
         .claude/state/worktree-teardown-waiver-\$(date -u +%Y%m%dT%H%M%SZ).txt

See ~/.claude/doctrine/worktree-isolation.md (teardown gate / B1).
================================================================
MSG

  local err_msg="Work-integrity gate (check c): session ending in worktree '${wt_path}' with uncommitted changes; preserve (commit/stash/push) before stop."
  _wig_block "check-c-dirty" "${wt_path}" "$err_msg" \
    "{\"decision\": \"block\", \"reason\": \"${err_msg} See stderr for exact rescue commands.\"}"
}

# ============================================================
# Main (production execution) — skipped entirely under --self-test,
# which is dispatched from the bottom-of-file trailer instead.
# ============================================================
_wig_main() {
  local input=""
  if [[ ! -t 0 ]]; then
    input=$(cat 2>/dev/null || echo "")
  fi
  RG_SESSION_ID=$(retry_guard_session_id "$input")

  local transcript_path=""
  if [[ -n "$input" ]] && command -v jq >/dev/null 2>&1; then
    transcript_path=$(echo "$input" | jq -r '.transcript_path // .session.transcript_path // empty' 2>/dev/null || echo "")
  fi
  # Self-test / manual override.
  if [[ -n "${WORK_INTEGRITY_GATE_TRANSCRIPT:-}" ]]; then
    transcript_path="$WORK_INTEGRITY_GATE_TRANSCRIPT"
  fi

  # Discover plan directories exactly as pre-stop-verifier does (top-level
  # + up to 2 levels deep), used both for path resolution and so check (c)
  # never depends on check (a)/(b) having found anything.
  local -a plan_dirs=()
  [[ -d "docs/plans" ]] && plan_dirs+=("docs/plans")
  local subdir
  for subdir in */docs/plans; do
    [[ -d "$subdir" ]] && plan_dirs+=("$subdir")
  done
  for subdir in */*/docs/plans; do
    [[ -d "$subdir" ]] && plan_dirs+=("$subdir")
  done

  if [[ ${#plan_dirs[@]} -gt 0 ]]; then
    local raw_touched touched_plans
    raw_touched=$(_wig_touched_plan_paths "$transcript_path")
    if [[ -n "$raw_touched" ]]; then
      touched_plans=$(_wig_resolve_touched_plans "$raw_touched" "${plan_dirs[@]}")
      if [[ -n "$touched_plans" ]]; then
        while IFS= read -r plan; do
          [[ -z "$plan" ]] && continue
          _wig_check_evidence "$plan"
          _wig_check_acceptance "$plan"
        done <<< "$touched_plans"
      fi
    fi
  fi

  # Check (c) always runs — worktree-scoped, not plan-scoped.
  _wig_check_worktree

  exit 0
}

# ============================================================
# --self-test: >=12 scenarios (see MANDATED list in the plan spec)
# ============================================================
_wig_self_test() {
  local script_path="${BASH_SOURCE[0]}"
  case "$script_path" in
    /*) ;;
    [A-Za-z]:[/\\]*) ;;
    *) script_path="$(pwd)/$script_path" ;;
  esac

  export HARNESS_SELFTEST=1
  local tmproot
  tmproot=$(mktemp -d 2>/dev/null || mktemp -d -t wigst)
  [[ -n "$tmproot" && -d "$tmproot" ]] || { echo "self-test: cannot create tempdir" >&2; exit 2; }
  # Trap bodies registered inside a function are NOT function-scoped in
  # bash — this trap still fires at the SCRIPT's real exit, by which
  # point _wig_self_test has already returned and its `local tmproot`
  # has gone out of scope. Under `set -u` that produces a harmless but
  # noisy "tmproot: unbound variable" on the way out. Guard with
  # ${tmproot:-} so cleanup is still best-effort without tripping -u.
  trap 'rm -rf "${tmproot:-}"' EXIT
  export SIGNAL_LEDGER_PATH="$tmproot/ledger.jsonl"

  # ---- per-scenario isolation (NL-FINDING-025 remediation) -------
  # Each scenario gets its own tempdir for retry-guard state and ledger to
  # prevent cross-scenario leakage. Called before each _build_repo invocation.
  _setup_scenario() {
    local scenario_name="$1"
    local scenario_tmpdir="$tmproot/tmpdir-$scenario_name"
    mkdir -p "$scenario_tmpdir"
    export TMPDIR="$scenario_tmpdir"
    export SIGNAL_LEDGER_PATH="$scenario_tmpdir/ledger.jsonl"
    export RETRY_GUARD_STATE_DIR="$scenario_tmpdir"
  }

  local passed=0 failed=0

  # ---- repo builder -----------------------------------------------
  # Builds a synthetic repo at $tmproot/<name>, seeds docs/plans/, and
  # returns the repo path. A bare origin + push is EXPENSIVE (measured
  # ~10s wall-clock per repo in this environment, dominated by process-
  # spawn overhead rather than CPU) and is only needed by scenarios that
  # actually exercise the "clean but unpushed" advisory or push a
  # worktree branch — so it is OPT-IN via $2 ("with-origin"), keeping
  # the common case (most scenarios never touch check-c's unpushed math)
  # fast.
  _build_repo() {
    local name="$1"
    local with_origin="${2:-}"
    local repo="$tmproot/$name"
    mkdir -p "$repo/docs/plans"
    (
      cd "$repo" || exit 99
      git init -q -b master 2>/dev/null || { git init -q; git checkout -q -b master 2>/dev/null; }
      git config core.hooksPath ""  # don't fire machine-global harness git hooks in fixtures
      git config user.email "t@example.com"; git config user.name "T"; git config commit.gpgsign false
      git config core.autocrlf false; git config core.safecrlf false
      echo seed > seed.txt
      mkdir -p docs/plans
      echo placeholder > docs/plans/.gitkeep
      git add -A; git commit -q -m seed
      if [[ "$with_origin" == "with-origin" ]]; then
        git init -q --bare "$tmproot/$name-origin.git" 2>/dev/null
        git remote add origin "$tmproot/$name-origin.git"
        git push -q -u origin master 2>/dev/null
      fi
    )
    echo "$repo"
  }

  # Writes a plan file at docs/plans/<slug>.md inside $1 (repo dir).
  # $2 = status (ACTIVE|COMPLETED|ABANDONED), $3 = "checked"|"unchecked"|"none",
  # $4 = "with-evidence"|"no-evidence", $5 = extra header lines (optional,
  # newline-joined; e.g. acceptance-exempt fields).
  _write_plan() {
    local repo="$1" slug="$2" status="$3" tasks="$4" evidence="$5" extra="${6:-}"
    {
      echo "# Plan: $slug"
      echo "Status: $status"
      [[ -n "$extra" ]] && printf '%s\n' "$extra"
      echo
      echo "## Goal"
      echo "Self-test fixture."
      echo
      echo "## Tasks"
      case "$tasks" in
        checked) echo "- [x] A.1 do the thing" ;;
        unchecked) echo "- [ ] A.1 do the thing" ;;
        none) ;;
      esac
      if [[ "$evidence" == "with-evidence" ]]; then
        echo
        echo "## Evidence Log"
        echo "EVIDENCE BLOCK"
        echo "Task ID: A.1"
        echo "Verified at: 2026-07-03T00:00:00Z"
        echo "Verdict: PASS"
      fi
    } > "$repo/docs/plans/${slug}.md"
    ( cd "$repo" && git add -A docs/plans && git commit -q -m "selftest: $slug" 2>/dev/null )
  }

  # Builds a synthetic Stop-event transcript JSONL naming the given plan
  # path(s) as Edit-tool file_path targets (i.e. "session touched this
  # plan"). Echoes the transcript path.
  _write_transcript() {
    local repo="$1"; shift
    local tfile="$tmproot/transcript-$$-$RANDOM.jsonl"
    : > "$tfile"
    local p
    for p in "$@"; do
      printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Edit","input":{"file_path":"%s"}}]}}\n' "$p" >> "$tfile"
    done
    printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"work summary"}]}}\n' >> "$tfile"
    echo "$tfile"
  }

  # Runs the gate against $1 (cwd) with WORK_INTEGRITY_GATE_TRANSCRIPT=$2
  # (may be empty). Echoes exit code.
  _run_gate() {
    local dir="$1" transcript="${2:-}"
    (
      cd "$dir" || exit 99
      export WORK_INTEGRITY_GATE_TRANSCRIPT="$transcript"
      printf '{"session_id":"selftest-%s"}' "$(basename "$dir")" | bash "$script_path" >"$tmproot/last-stdout.txt" 2>"$tmproot/last-stderr.txt"
      echo $?
    )
  }

  _expect() {
    local label="$1" actual="$2" expected="$3"
    if [[ "$actual" == "$expected" ]]; then
      echo "self-test ($label): PASS (exit $actual)" >&2
      passed=$((passed+1))
    else
      # Dump BOTH streams + the raw rc so an empty-stderr failure (the
      # environmental-flake signature, harness-reviewer 2026-07-03
      # Finding 5) is diagnosable from its artifact instead of
      # unreproducible.
      echo "self-test ($label): FAIL (expected exit $expected, got $actual)" >&2
      echo "--- last-stderr ---" >&2
      cat "$tmproot/last-stderr.txt" 2>/dev/null >&2
      echo "--- last-stdout ---" >&2
      cat "$tmproot/last-stdout.txt" 2>/dev/null >&2
      echo "--- end capture (rc=$actual) ---" >&2
      failed=$((failed+1))
    fi
  }

  # ================================================================
  # Scenario 1 (MANDATED): orthogonal ACTIVE plan does NOT block.
  # An ACTIVE plan with unchecked tasks exists in the repo, but the
  # session's transcript never touched it → must pass.
  # ================================================================
  _setup_scenario s1
  R=$(_build_repo s1)
  _write_plan "$R" "orthogonal-plan" "ACTIVE" "unchecked" "no-evidence"
  T=$(_write_transcript "$R")   # touches nothing
  RC=$(_run_gate "$R" "$T")
  _expect "orthogonal-ACTIVE-plan-does-NOT-block" "$RC" "0"

  # ================================================================
  # Scenario 2 (MANDATED): session-touched plan with unchecked tasks
  # DOES block.
  # ================================================================
  _setup_scenario s2
  R=$(_build_repo s2)
  _write_plan "$R" "touched-plan" "ACTIVE" "unchecked" "no-evidence"
  T=$(_write_transcript "$R" "$R/docs/plans/touched-plan.md")
  RC=$(_run_gate "$R" "$T")
  _expect "session-touched-plan-unchecked-tasks-DOES-block" "$RC" "2"

  # ================================================================
  # Scenario 2b (NL-FINDING-019 / ADR 059 D4): session-touched ACTIVE
  # plan with unchecked tasks + fresh per-session waiver → passes.
  # The waiver-parity valve for check (a)'s world-state assertion.
  # ================================================================
  _setup_scenario s2b
  R=$(_build_repo s2b)
  _write_plan "$R" "waived-unchecked" "ACTIVE" "unchecked" "no-evidence" \
    "acceptance-exempt: true"$'\n'"acceptance-exempt-reason: Harness-dev self-test fixture with no user-facing product surface."
  mkdir -p "$R/.claude/state"
  echo "Incidental touch only: this session appended an in-flight scope line; plan belongs to the program orchestrator." \
    > "$R/.claude/state/work-integrity-waiver-waived-unchecked-$(date +%s).txt"
  T=$(_write_transcript "$R" "$R/docs/plans/waived-unchecked.md")
  RC=$(_run_gate "$R" "$T")
  _expect "unchecked-tasks-with-fresh-waiver-passes" "$RC" "0"

  # ================================================================
  # Scenario 2c (ADR 059 D4 scoping rule): a waiver clears WORLD-STATE
  # assertions only. Mixed plan: unchecked tasks AND a checked box with
  # NO evidence, plus a fresh waiver — the valve clears the unchecked-
  # tasks block but the missing-evidence SESSION-HONESTY check must
  # still fire.
  # ================================================================
  _setup_scenario s2c
  R=$(_build_repo s2c)
  _write_plan "$R" "waived-mixed" "ACTIVE" "checked" "no-evidence" \
    "acceptance-exempt: true"$'\n'"acceptance-exempt-reason: Harness-dev self-test fixture with no user-facing product surface."
  echo "- [ ] X.9 an open task that the waiver legitimately covers" >> "$R/docs/plans/waived-mixed.md"
  mkdir -p "$R/.claude/state"
  echo "Waiver covers the open task; it must not clear the missing-evidence honesty check for the checked box." \
    > "$R/.claude/state/work-integrity-waiver-waived-mixed-$(date +%s).txt"
  T=$(_write_transcript "$R" "$R/docs/plans/waived-mixed.md")
  RC=$(_run_gate "$R" "$T")
  _expect "waiver-does-NOT-clear-missing-evidence" "$RC" "2"

  # ================================================================
  # Scenario 2d (ADR 059 D4 scoping rule): COMPLETED-but-unchecked is
  # an honesty contradiction, not a world-state fact — a fresh waiver
  # must NOT clear it.
  # ================================================================
  _setup_scenario s2d
  R=$(_build_repo s2d)
  _write_plan "$R" "waived-completed" "COMPLETED" "unchecked" "no-evidence"
  mkdir -p "$R/.claude/state"
  echo "Waiver present but must not clear the COMPLETED-with-unchecked-tasks contradiction." \
    > "$R/.claude/state/work-integrity-waiver-waived-completed-$(date +%s).txt"
  T=$(_write_transcript "$R" "$R/docs/plans/waived-completed.md")
  RC=$(_run_gate "$R" "$T")
  _expect "waiver-does-NOT-clear-completed-unchecked" "$RC" "2"

  # ================================================================
  # Scenario 2e (harness-reviewer 2026-07-03 Finding 1): an EMPTY
  # waiver file (stray touch / failed echo) must NOT clear the block —
  # the message's ">=1 substantive line" claim is enforced, not theater.
  # ================================================================
  _setup_scenario s2e
  R=$(_build_repo s2e)
  _write_plan "$R" "waived-empty" "ACTIVE" "unchecked" "no-evidence" \
    "acceptance-exempt: true"$'\n'"acceptance-exempt-reason: Harness-dev self-test fixture with no user-facing product surface."
  mkdir -p "$R/.claude/state"
  : > "$R/.claude/state/work-integrity-waiver-waived-empty-$(date +%s).txt"
  T=$(_write_transcript "$R" "$R/docs/plans/waived-empty.md")
  RC=$(_run_gate "$R" "$T")
  _expect "EMPTY-waiver-does-NOT-clear-unchecked-tasks" "$RC" "2"

  # ================================================================
  # Scenario 3: session-touched plan with checked task + evidence + no
  # acceptance artifact requirement issue avoided via acceptance-exempt
  # → passes cleanly.
  # ================================================================
  _setup_scenario s3
  R=$(_build_repo s3)
  _write_plan "$R" "clean-plan" "ACTIVE" "checked" "with-evidence" \
    "acceptance-exempt: true"$'\n'"acceptance-exempt-reason: Harness-dev self-test fixture with no user-facing product surface."
  T=$(_write_transcript "$R" "$R/docs/plans/clean-plan.md")
  RC=$(_run_gate "$R" "$T")
  _expect "clean-session-passes" "$RC" "0"

  # ================================================================
  # Scenario 4: session-touched plan with checked task but NO evidence
  # → blocks (check a, missing evidence entirely).
  # ================================================================
  _setup_scenario s4
  R=$(_build_repo s4)
  _write_plan "$R" "no-evidence-plan" "ACTIVE" "checked" "no-evidence" \
    "acceptance-exempt: true"$'\n'"acceptance-exempt-reason: Harness-dev self-test fixture with no user-facing product surface."
  T=$(_write_transcript "$R" "$R/docs/plans/no-evidence-plan.md")
  RC=$(_run_gate "$R" "$T")
  _expect "checked-task-no-evidence-blocks" "$RC" "2"

  # ================================================================
  # Scenario 5: COMPLETED plan (session-touched) with unchecked tasks
  # → blocks (stricter COMPLETED path).
  # ================================================================
  _setup_scenario s5
  R=$(_build_repo s5)
  _write_plan "$R" "completed-unchecked" "COMPLETED" "unchecked" "no-evidence"
  T=$(_write_transcript "$R" "$R/docs/plans/completed-unchecked.md")
  RC=$(_run_gate "$R" "$T")
  _expect "completed-plan-unchecked-task-blocks" "$RC" "2"

  # ================================================================
  # Scenario 6: ABANDONED plan (session-touched) with unchecked tasks
  # → no-op, passes.
  # ================================================================
  _setup_scenario s6
  R=$(_build_repo s6)
  _write_plan "$R" "abandoned-plan" "ABANDONED" "unchecked" "no-evidence"
  T=$(_write_transcript "$R" "$R/docs/plans/abandoned-plan.md")
  RC=$(_run_gate "$R" "$T")
  _expect "abandoned-plan-noop-passes" "$RC" "0"

  # ================================================================
  # Scenario 7: ACTIVE plan, checked+evidence, NOT exempt, no acceptance
  # artifact directory → blocks (check b).
  # ================================================================
  _setup_scenario s7
  R=$(_build_repo s7)
  _write_plan "$R" "needs-acceptance" "ACTIVE" "checked" "with-evidence"
  T=$(_write_transcript "$R" "$R/docs/plans/needs-acceptance.md")
  RC=$(_run_gate "$R" "$T")
  _expect "no-acceptance-artifact-blocks" "$RC" "2"

  # ================================================================
  # Scenario 8: ACTIVE plan with a valid PASS acceptance artifact at the
  # current plan_commit_sha → passes.
  # ================================================================
  _setup_scenario s8
  R=$(_build_repo s8)
  _write_plan "$R" "pass-acceptance" "ACTIVE" "checked" "with-evidence"
  SHA=$(cd "$R" && git log -n 1 --pretty=format:'%H' -- docs/plans/pass-acceptance.md)
  mkdir -p "$R/.claude/state/acceptance/pass-acceptance"
  cat > "$R/.claude/state/acceptance/pass-acceptance/art.json" <<EOF
{"session_id":"s","plan_slug":"pass-acceptance","plan_commit_sha":"$SHA","mode":"runtime","scenarios":[{"id":"sc-0","verdict":"PASS"}]}
EOF
  T=$(_write_transcript "$R" "$R/docs/plans/pass-acceptance.md")
  RC=$(_run_gate "$R" "$T")
  _expect "valid-pass-artifact-passes" "$RC" "0"

  # ================================================================
  # Scenario 9: acceptance-exempt: true but reason too short → blocks.
  # ================================================================
  _setup_scenario s9
  R=$(_build_repo s9)
  _write_plan "$R" "exempt-no-reason" "ACTIVE" "checked" "with-evidence" \
    "acceptance-exempt: true"$'\n'"acceptance-exempt-reason: short"
  T=$(_write_transcript "$R" "$R/docs/plans/exempt-no-reason.md")
  RC=$(_run_gate "$R" "$T")
  _expect "exempt-without-substantive-reason-blocks" "$RC" "2"

  # ================================================================
  # Scenario 10: acceptance waiver present and fresh → passes despite no
  # artifact.
  # ================================================================
  _setup_scenario s10
  R=$(_build_repo s10)
  _write_plan "$R" "waived-plan" "ACTIVE" "checked" "with-evidence"
  mkdir -p "$R/.claude/state"
  echo "Waived for self-test — valid one-line justification text" \
    > "$R/.claude/state/acceptance-waiver-waived-plan-$(date +%s).txt"
  T=$(_write_transcript "$R" "$R/docs/plans/waived-plan.md")
  RC=$(_run_gate "$R" "$T")
  _expect "fresh-acceptance-waiver-passes" "$RC" "0"

  # ================================================================
  # Scenario 11 (MANDATED): dirty worktree blocks with rescue text.
  # ================================================================
  _setup_scenario s11
  R=$(_build_repo s11)
  WT="$tmproot/s11-wt"
  ( cd "$R" && git worktree add -q "$WT" -b s11-feat master >/dev/null 2>&1 )
  ( cd "$WT" && mkdir -p docs/plans && echo dirty >> seed.txt )
  RC=$(_run_gate "$WT" "")
  _expect "dirty-worktree-blocks" "$RC" "2"
  if grep -q "git stash push -u -m" "$tmproot/last-stderr.txt" 2>/dev/null && \
     grep -q "git add -A && git commit" "$tmproot/last-stderr.txt" 2>/dev/null; then
    echo "self-test (dirty-worktree-rescue-text-present): PASS" >&2
    passed=$((passed+1))
  else
    echo "self-test (dirty-worktree-rescue-text-present): FAIL (rescue commands not found on stderr)" >&2
    failed=$((failed+1))
  fi

  # ================================================================
  # Scenario 12 (MANDATED): clean session passes (clean worktree, main
  # checkout, no touched plans at all).
  # ================================================================
  _setup_scenario s12
  R=$(_build_repo s12)
  RC=$(_run_gate "$R" "")
  _expect "clean-session-main-checkout-passes" "$RC" "0"

  # ================================================================
  # Scenario 13: clean linked worktree (no dirt, nothing unpushed) →
  # passes. Uses with-origin so the push is real (meaningfully exercises
  # the "nothing unpushed" branch rather than degrading to "no upstream
  # configured at all").
  # ================================================================
  _setup_scenario s13
  R=$(_build_repo s13 with-origin)
  WT="$tmproot/s13-wt"
  ( cd "$R" && git worktree add -q "$WT" -b s13-feat master >/dev/null 2>&1 )
  ( cd "$WT" && git push -q -u origin s13-feat 2>/dev/null )
  RC=$(_run_gate "$WT" "")
  _expect "clean-linked-worktree-passes" "$RC" "0"

  # ================================================================
  # Scenario 14: locked worktree, dirty → no-op (exempt).
  # ================================================================
  _setup_scenario s14
  R=$(_build_repo s14)
  WT="$tmproot/s14-wt"
  ( cd "$R" && git worktree add -q "$WT" -b s14-feat master >/dev/null 2>&1 && git worktree lock "$WT" 2>/dev/null )
  ( cd "$WT" && echo dirty >> seed.txt )
  RC=$(_run_gate "$WT" "")
  _expect "locked-worktree-exempt-even-if-dirty" "$RC" "0"

  # ================================================================
  # Scenario 15: dirty worktree WITH a fresh teardown waiver → passes.
  # ================================================================
  _setup_scenario s15
  R=$(_build_repo s15)
  WT="$tmproot/s15-wt"
  ( cd "$R" && git worktree add -q "$WT" -b s15-feat master >/dev/null 2>&1 )
  ( cd "$WT" && echo dirty >> seed.txt && mkdir -p .claude/state && \
    echo "intentionally leaving WIP; will resume" > ".claude/state/worktree-teardown-waiver-$(date -u +%Y%m%dT%H%M%SZ).txt" )
  RC=$(_run_gate "$WT" "")
  _expect "dirty-worktree-with-waiver-passes" "$RC" "0"

  # ================================================================
  # Scenario 16 (MANDATED): DONE-claimed + this gate blocking is NOT
  # downgraded by retry-guard. Assert RETRY_GUARD_VERIFICATION_HOOKS
  # (the lib default this task edits) includes work-integrity-gate, and
  # that a DONE-claiming transcript causes the retry-guard to REFUSE the
  # downgrade at threshold (stays blocked, exit 2) rather than exit 0.
  # ================================================================
  if printf '%s' "$RETRY_GUARD_VERIFICATION_HOOKS" | grep -qw "work-integrity-gate"; then
    echo "self-test (retry-guard-lib-lists-work-integrity-gate): PASS" >&2
    passed=$((passed+1))
  else
    echo "self-test (retry-guard-lib-lists-work-integrity-gate): FAIL (RETRY_GUARD_VERIFICATION_HOOKS='$RETRY_GUARD_VERIFICATION_HOOKS' does not list work-integrity-gate)" >&2
    failed=$((failed+1))
  fi

  _setup_scenario s16
  R=$(_build_repo s16)
  ( cd "$R" &&
    export RETRY_GUARD_STATE_DIR=".claude/state"
    export RETRY_GUARD_THRESHOLD=3
    export CLAUDE_SESSION_ID="wig-done-sess"
    printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"text","text":"work summary\n\nDONE: shipped everything abc1234"}]}}' > done-transcript.jsonl
    export RETRY_GUARD_TRANSCRIPT="$PWD/done-transcript.jsonl"
    # shellcheck disable=SC1090
    source "$(dirname "$script_path")/lib/stop-hook-retry-guard.sh"
    _=$(retry_guard_record "work-integrity-gate" "wig-done-sess" "incomplete")
    _=$(retry_guard_record "work-integrity-gate" "wig-done-sess" "incomplete")
    set +e
    ( retry_guard_block_or_exit "work-integrity-gate" "wig-done-sess" "incomplete" \
        "plan has unchecked tasks" \
        '{"decision":"block"}' 2 ) >/tmp/wig-rg-out 2>/tmp/wig-rg-err
    rc=$?
    set -e
    exit "$rc"
  )
  RC=$?
  _expect "DONE-claimed-gate-blocking-NOT-downgraded" "$RC" "2"
  if grep -q "downgrade REFUSED" /tmp/wig-rg-err 2>/dev/null; then
    echo "self-test (retry-guard-refusal-names-work-integrity-gate): PASS" >&2
    passed=$((passed+1))
  else
    echo "self-test (retry-guard-refusal-names-work-integrity-gate): FAIL" >&2
    failed=$((failed+1))
  fi

  # ================================================================
  # Scenario 17: multiple session-touched plans — one orthogonal-clean,
  # one broken — only the broken one blocks (proves per-plan scoping,
  # not "first plan found wins").
  # ================================================================
  _setup_scenario s17
  R=$(_build_repo s17)
  _write_plan "$R" "multi-clean" "ACTIVE" "checked" "with-evidence" \
    "acceptance-exempt: true"$'\n'"acceptance-exempt-reason: Harness-dev self-test fixture with no user-facing product surface."
  _write_plan "$R" "multi-broken" "ACTIVE" "unchecked" "no-evidence"
  T=$(_write_transcript "$R" "$R/docs/plans/multi-clean.md" "$R/docs/plans/multi-broken.md")
  RC=$(_run_gate "$R" "$T")
  _expect "multi-touched-plans-only-broken-one-blocks" "$RC" "2"

  echo "" >&2
  echo "self-test summary: $passed passed, $failed failed" >&2
  if [[ "$failed" -eq 0 ]]; then
    return 0
  else
    return 1
  fi
}

# ============================================================
# Entry point
# ============================================================
if [[ "${1:-}" == "--self-test" ]]; then
  _wig_self_test
  exit $?
fi

_wig_main
