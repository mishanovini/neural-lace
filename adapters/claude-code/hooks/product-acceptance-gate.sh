#!/bin/bash
# product-acceptance-gate.sh — Stop hook (Generation 5, Phase D of
# docs/plans/end-user-advocate-acceptance-loop.md)
#
# ============================================================
# WHAT THIS HOOK DOES
# ============================================================
#
# This is the production runtime acceptance gate for the end-user-advocate
# loop. It runs as a Stop hook AFTER the existing Stop chain (see
# "INSERTION POINT" below) and BLOCKS session termination if any ACTIVE
# plan in docs/plans/ has not been satisfied by a runtime acceptance
# artifact for the current plan_commit_sha.
#
# In one sentence: a session cannot end with an ACTIVE plan's product
# in a user-broken state, because this hook checks that the
# end-user-advocate has actually run the acceptance scenarios against
# the live app (or the plan has declared itself acceptance-exempt with
# a substantive reason).
#
# The walking-skeleton equivalent lives in pre-stop-verifier.sh
# Check 0 (Phase A.4) — that one only LOGS recognition. THIS hook is
# the production blocker (Phase D of the parent plan).
#
# ============================================================
# INSERTION POINT IN THE STOP HOOK CHAIN
# ============================================================
#
# Position: 4 (last) in the Stop array of ~/.claude/settings.json and
# adapters/claude-code/settings.json.template.
#
# Current Stop hook chain order:
#   1. pre-stop-verifier.sh      — plan-integrity (unchecked tasks,
#                                    evidence blocks, runtime verification)
#   2. bug-persistence-gate.sh   — user-process (bugs persisted to backlog)
#   3. narrate-and-wait-gate.sh  — user-process (don't trail off with
#                                    permission-seeking phrases)
#   4. product-acceptance-gate.sh (THIS HOOK) — product-outcome
#                                    (acceptance scenarios PASS at runtime)
#
# Rationale for being LAST: the product-outcome check should see a
# clean session that hasn't already been blocked elsewhere. If the plan
# is broken (Check 1) or bugs weren't persisted (Check 2) or the
# session is wait-narrating (Check 3), surfacing those issues first is
# more actionable than "your acceptance scenarios haven't been run"
# stacked on top of more fundamental problems. Also: product-acceptance
# is the most expensive check to satisfy (run a browser, take
# screenshots, etc.), so checking the cheap mechanical things first is
# the right ordering.
#
# Future hooks added to the Stop chain should consider this principle
# — gates with cheaper "fix me" actions go earlier; gates that require
# a full runtime exercise go later.
#
# ============================================================
# ARTIFACT SCHEMA
# ============================================================
#
# Each runtime acceptance run writes a JSON artifact at:
#   .claude/state/acceptance/<plan-slug>/<session-id>-<ISO-timestamp>.json
#
# Required fields:
#   - session_id              (string) — the Claude Code session that ran the advocate
#   - plan_slug               (string) — basename of the plan file without .md
#   - plan_commit_sha         (string) — git SHA of the plan file at run time
#   - mode                    (string) — typically "runtime"
#   - started_at              (string, ISO 8601)
#   - ended_at                (string, ISO 8601)
#   - scenarios               (array)
#       - id                  (string) — scenario slug from the plan
#       - verdict             (string) — "PASS" | "FAIL" | "ENVIRONMENT_UNAVAILABLE"
#       - artifacts           (object) — paths to screenshot/network/console logs
#       - assertions_met      (array of strings) — checks that passed
#       - failure_reason      (string|null)
#
# Optional fields:
#   - runtime_environment     (object) — browser MCP info, fallback notes
#   - assertion_fidelity      (string) — "full" | "partial" + explanation
#
# Sibling files in the same directory: <slug>-screenshot.png,
# <slug>-network.log, <slug>-console.log. (Walking-skeleton runs may
# substitute placeholder filenames like *-screenshot-omitted.txt.)
#
# A plan is SATISFIED when:
#   1. At least one artifact JSON exists in
#      .claude/state/acceptance/<plan-slug>/
#   2. That artifact's plan_commit_sha matches the current plan file's
#      git SHA (no staleness)
#   3. ALL scenarios in the artifact have verdict == "PASS"
#
# ============================================================
# MULTI-WORKTREE ARTIFACT DISCOVERY (Task 10 of agent-teams-integration)
# ============================================================
#
# Searches .claude/state/acceptance/<plan-slug>/ in the current worktree
# AND in every other worktree of the current repo (per `git worktree
# list`). A scenario PASS in any worktree's state dir satisfies the
# gate, provided plan_commit_sha matches the plan file's HEAD SHA.
#
# Rationale: in agent-team / parallel-worktree workflows, a teammate in
# a separate worktree may be the one who actually ran the runtime
# advocate and wrote the PASS artifact. The lead's worktree never sees
# that artifact under its own .claude/state/. Without aggregation, the
# lead's gate would block session end despite the team having satisfied
# the scenarios. Aggregating across worktrees closes that gap.
#
# Safety: if `git worktree list` fails (cwd is not a git repo, git is
# not installed, or any other failure), discovery degrades gracefully
# to cwd-only search — the gate retains its pre-multiworktree behavior.
#
# ============================================================
# WAIVER MECHANISM
# ============================================================
#
# Per-session escape hatch: write
#   .claude/state/acceptance-waiver-<plan-slug>-<timestamp>.txt
# with a one-line non-empty justification. Present + recent (younger
# than 1 hour, mirroring bug-persistence-gate.sh) → allow stop. Waivers
# are per-session (timestamp-gated) so a leftover waiver from yesterday
# does NOT silently authorize today's session.
#
# ============================================================
# EXEMPTION MECHANISM (D.6)
# ============================================================
#
# Plan-header field: `acceptance-exempt: true` + `acceptance-exempt-reason: <text>`.
# - Both fields present, reason >= 20 non-whitespace chars → plan is exempt; allow.
# - acceptance-exempt: true present but reason missing or < 20 chars → BLOCK
#   with a clear "missing reason" message.
# - acceptance-exempt: false (or absent) → normal artifact check applies.
#
# ============================================================
# EXIT CODES
# ============================================================
#
#   0 — session may terminate
#   2 — session is blocked; stderr explains why
#
# Bash 3.2 portability: avoid `declare -A`, `mapfile`, `${var,,}`,
# `&>>`, BASH_REMATCH of unbounded length. Stick to POSIX-ish constructs
# so this runs on macOS's stock bash 3.2.
#
# ============================================================
# CLAUDE CODE CONTRACT
# ============================================================
#
# Stop hooks receive JSON on stdin. We read transcript_path from it
# (matching bug-persistence-gate.sh's parsing). On block, we print
# JSON to stdout with decision: "block" and a reason message; exit
# code 2 signals blocking.

set -u

SCRIPT_NAME="product-acceptance-gate.sh"

# ---------- helpers ----------------------------------------------------

# Find all ACTIVE plan files (top level only, NOT archive/).
# Echoes one path per line.
find_active_plans() {
  local dir
  for dir in docs/plans */docs/plans */*/docs/plans; do
    [[ -d "$dir" ]] || continue
    # Iterate top-level *.md only; skip archive subdir and -evidence files
    for f in "$dir"/*.md; do
      [[ -f "$f" ]] || continue
      # Skip evidence companions
      case "$f" in
        *-evidence.md) continue ;;
      esac
      if grep -qiE '^Status:[[:space:]]*ACTIVE' "$f" 2>/dev/null; then
        echo "$f"
      fi
    done
  done
}

# Get the current plan_commit_sha for a plan file.
# Uses the most recent commit that touched the file. If the file is
# uncommitted, returns "UNCOMMITTED" (which will never match an
# artifact's recorded sha — surfacing the uncommitted-plan problem).
get_plan_sha() {
  local plan="$1"
  local sha
  if command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    sha=$(git log -n 1 --pretty=format:'%H' -- "$plan" 2>/dev/null || echo "")
    if [[ -n "$sha" ]]; then
      echo "$sha"
      return
    fi
  fi
  echo "UNCOMMITTED"
}

# Check whether a plan has acceptance-exempt: true with a substantive reason.
# Echoes one of:
#   "EXEMPT_OK"            — exempt with valid reason
#   "EXEMPT_NO_REASON"     — exempt: true but reason missing/short
#   "NOT_EXEMPT"           — not exempt
check_exemption() {
  local plan="$1"
  if ! grep -qiE '^acceptance-exempt:[[:space:]]*true' "$plan" 2>/dev/null; then
    echo "NOT_EXEMPT"
    return
  fi
  # exempt: true is present — find the reason
  local reason
  reason=$(grep -iE '^acceptance-exempt-reason:' "$plan" 2>/dev/null | head -1 | sed 's/^[Aa]cceptance-exempt-reason:[[:space:]]*//')
  # Strip leading/trailing whitespace via parameter expansion
  reason=$(echo "$reason" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  # Substantive = >= 20 non-whitespace chars
  local stripped
  stripped=$(echo "$reason" | tr -d '[:space:]')
  if [[ ${#stripped} -ge 20 ]]; then
    echo "EXEMPT_OK"
  else
    echo "EXEMPT_NO_REASON"
  fi
}

# Discover all acceptance artifacts for a plan slug across the current
# worktree AND every other worktree of the current repo.
#
# Echoes one absolute path per line, or nothing if no artifacts found.
#
# Search order:
#   1. .claude/state/acceptance/<slug>/ in $PWD (the current worktree)
#   2. <wt>/.claude/state/acceptance/<slug>/ for every other worktree
#      reported by `git worktree list --porcelain`
#
# Degrades gracefully: if `git worktree list` fails or returns nothing
# beyond the primary, only the cwd-relative path is searched.
discover_acceptance_artifacts() {
  local plan_slug="$1"
  local primary=".claude/state/acceptance/${plan_slug}"
  if [[ -d "$primary" ]]; then
    find "$primary" -maxdepth 1 -type f -name '*.json' 2>/dev/null
  fi

  # Enumerate other worktrees of the current repo. Best-effort:
  # if git is missing or we're not in a repo, this is a no-op and
  # the cwd-only search above is the only signal.
  if ! command -v git >/dev/null 2>&1; then
    return
  fi
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    return
  fi

  local wt_list
  wt_list=$(git worktree list --porcelain 2>/dev/null)
  if [[ -z "$wt_list" ]]; then
    return
  fi

  # Parse `worktree <path>` lines. The primary worktree is always the
  # FIRST `worktree` entry in porcelain output, so we skip it (we already
  # searched cwd-relative above). Skipping by ordinal avoids the
  # path-form comparison pitfall when running under msys/cygwin where
  # `pwd` returns POSIX form (/tmp/...) but `git worktree list` returns
  # Windows form (C:/...).
  local wt seen_primary=0
  while IFS= read -r line; do
    case "$line" in
      "worktree "*)
        wt="${line#worktree }"
        if [[ $seen_primary -eq 0 ]]; then
          seen_primary=1
          continue
        fi
        local wt_state="${wt}/.claude/state/acceptance/${plan_slug}"
        if [[ -d "$wt_state" ]]; then
          find "$wt_state" -maxdepth 1 -type f -name '*.json' 2>/dev/null
        fi
        ;;
    esac
  done <<< "$wt_list"
}

# Check whether a plan has any satisfying acceptance artifact.
# Echoes one of:
#   "SATISFIED"            — at least one artifact with matching plan_commit_sha
#                            and all scenarios PASS
#   "NO_DIRECTORY"         — .claude/state/acceptance/<slug>/ does not exist
#                            in any worktree
#   "NO_ARTIFACTS"         — directory exists somewhere but contains no JSON files
#   "STALE"                — artifacts exist but none match current plan_commit_sha
#   "FAIL"                 — most recent matching-sha artifact has at least one FAIL
#
# Aggregates across worktrees per discover_acceptance_artifacts.
check_artifact() {
  local plan="$1"
  local slug
  slug=$(basename "$plan" .md)
  local primary_dir=".claude/state/acceptance/${slug}"

  # List JSON artifacts across all worktrees of the current repo.
  local artifacts
  artifacts=$(discover_acceptance_artifacts "$slug")

  # Disambiguate "no directory anywhere" from "directory exists but
  # has no JSON". Existence of the cwd dir is the cheap proxy; if the
  # cwd dir doesn't exist but another worktree's does, we still treat
  # that as "directory present" (artifacts non-empty case is handled
  # below; only NO_DIRECTORY vs NO_ARTIFACTS messaging differs).
  if [[ -z "$artifacts" ]]; then
    if [[ ! -d "$primary_dir" ]]; then
      # Also no other-worktree dir held artifacts (already inlined above).
      echo "NO_DIRECTORY"
      return
    fi
    echo "NO_ARTIFACTS"
    return
  fi

  local current_sha
  current_sha=$(get_plan_sha "$plan")

  # Iterate artifacts; find any whose recorded plan_commit_sha matches current_sha.
  # Among those, find any whose all scenarios are PASS.
  local found_matching_sha=0
  local found_all_pass=0
  local artifact
  while IFS= read -r artifact; do
    [[ -z "$artifact" ]] && continue
    [[ -f "$artifact" ]] || continue
    local artifact_sha
    artifact_sha=$(grep -oE '"plan_commit_sha"[[:space:]]*:[[:space:]]*"[^"]+"' "$artifact" 2>/dev/null | head -1 | sed -E 's/.*"plan_commit_sha"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/')
    if [[ "$artifact_sha" == "$current_sha" ]]; then
      found_matching_sha=1
      # Check all scenarios PASS: count "verdict": "PASS" vs "verdict": "FAIL" vs "verdict": "ENVIRONMENT_UNAVAILABLE"
      local verdict_lines
      verdict_lines=$(grep -oE '"verdict"[[:space:]]*:[[:space:]]*"[^"]+"' "$artifact" 2>/dev/null)
      # Skip blank artifacts
      [[ -z "$verdict_lines" ]] && continue
      # If any verdict is non-PASS, this artifact does not satisfy
      local has_non_pass
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

# Check whether a per-session waiver exists for a plan.
# A waiver is .claude/state/acceptance-waiver-<slug>-*.txt that is:
#   - non-empty (has at least one non-whitespace character on first line)
#   - newer than 1 hour ago (per-session ephemeral, mirrors bug-persistence-gate.sh)
check_waiver() {
  local slug="$1"
  local waiver_dir=".claude/state"
  [[ -d "$waiver_dir" ]] || { echo "NO_WAIVER"; return; }
  local recent
  recent=$(find "$waiver_dir" -maxdepth 1 -type f -name "acceptance-waiver-${slug}-*.txt" -newermt '1 hour ago' 2>/dev/null | head -1)
  if [[ -z "$recent" ]]; then
    echo "NO_WAIVER"
    return
  fi
  # Verify file has substantive content (non-empty first line stripped of whitespace)
  local first_line_stripped
  first_line_stripped=$(head -1 "$recent" 2>/dev/null | tr -d '[:space:]')
  if [[ -z "$first_line_stripped" ]]; then
    echo "EMPTY_WAIVER"
  else
    echo "VALID_WAIVER:${recent}"
  fi
}

# ============================================================
# --self-test: 10 scenarios
#   (8 from parent plan D.4 + D.6, plus 2 multi-worktree scenarios
#    added in agent-teams-integration plan, Task 10)
# ============================================================
#
# Scenarios:
#   (a)  no active plan                                    → PASS (allow stop)
#   (b)  active plan with valid PASS artifact              → PASS
#   (c)  active plan with FAIL artifact                    → BLOCK
#   (d)  active plan with no artifact                      → BLOCK
#   (e)  active plan with stale artifact (wrong sha)       → BLOCK
#   (f)  active plan with valid waiver                     → PASS
#   (g)  active plan with acceptance-exempt: true + reason → PASS
#   (h)  active plan with acceptance-exempt: true, no reason → BLOCK
#   (W1) PASS artifact ONLY in secondary worktree          → PASS
#   (W2) FAIL in primary + PASS in secondary worktree      → PASS
#
# W1 and W2 exercise multi-worktree artifact aggregation: the gate
# must enumerate all of the current repo's worktrees and treat a
# PASS artifact in any of them (with matching plan_commit_sha) as
# satisfying.
#
# Exits 0 only if every scenario matched its expected outcome.

if [[ "${1:-}" == "--self-test" ]]; then
  TMPDIR_SELFTEST=$(mktemp -d 2>/dev/null || mktemp -d -t paacceptance)
  if [[ -z "$TMPDIR_SELFTEST" ]] || [[ ! -d "$TMPDIR_SELFTEST" ]]; then
    echo "self-test: cannot create temp directory" >&2
    exit 2
  fi
  trap 'rm -rf "$TMPDIR_SELFTEST"' EXIT

  SCRIPT_PATH="${BASH_SOURCE[0]}"
  # Resolve to absolute path (the test cd's into TMPDIR). Handle both
  # POSIX absolute paths (/foo/bar) and Windows-style (C:/foo or C:\foo).
  case "$SCRIPT_PATH" in
    /*) ;;
    [A-Za-z]:[/\\]*) ;;
    *) SCRIPT_PATH="$(pwd)/$SCRIPT_PATH" ;;
  esac

  FAILED=0
  PASSED=0

  # Set up a synthetic git repo + plan/state structure inside TMPDIR
  cd "$TMPDIR_SELFTEST" || { echo "self-test: cd failed" >&2; exit 2; }
  git init -q . 2>/dev/null
  git config user.email "selftest@example.com"
  git config user.name  "selftest"
  mkdir -p docs/plans
  mkdir -p .claude/state/acceptance

  # Helper: write a synthetic plan file
  write_plan() {
    # $1 = slug, $2 = include_active (1 if Status: ACTIVE), $3 = include_exempt (true|false|noreason|absent)
    local slug="$1"
    local active="$2"
    local exempt="$3"
    local status_line="Status: ACTIVE"
    [[ "$active" == "0" ]] && status_line="Status: COMPLETED"
    {
      echo "# Plan: $slug"
      echo "$status_line"
      echo "Mode: code"
      case "$exempt" in
        true)
          echo "acceptance-exempt: true"
          echo "acceptance-exempt-reason: This is a synthetic self-test fixture used to validate the acceptance gate's exemption recognition path."
          ;;
        noreason)
          echo "acceptance-exempt: true"
          echo "acceptance-exempt-reason:"
          ;;
        false)
          echo "acceptance-exempt: false"
          ;;
        absent) ;;
      esac
      echo
      echo "## Goal"
      echo "Self-test fixture exercising product-acceptance-gate.sh."
    } > "docs/plans/${slug}.md"
    # Stage all current plan-file state (including deletions of prior
    # scenarios' plans from reset_repo's rm -rf) so the resulting commit
    # cleanly reflects only this scenario's plan. Without -A, the commit
    # accumulates plans across scenarios and the secondary worktree
    # carries stale plans into its working tree.
    git add -A docs/plans 2>/dev/null
    git commit -q -m "selftest: $slug" 2>/dev/null
  }

  # Helper: write an artifact
  write_artifact() {
    # $1 = slug, $2 = sha (or "current" to read current), $3 = verdicts (e.g. "PASS PASS" or "PASS FAIL")
    local slug="$1"
    local sha="$2"
    local verdicts="$3"
    local dir=".claude/state/acceptance/${slug}"
    mkdir -p "$dir"
    if [[ "$sha" == "current" ]]; then
      sha=$(git log -n 1 --pretty=format:'%H' -- "docs/plans/${slug}.md" 2>/dev/null)
    fi
    local artifact_path="${dir}/sess-test-$(date +%s%N).json"
    {
      echo "{"
      echo "  \"session_id\": \"sess-test\","
      echo "  \"plan_slug\": \"${slug}\","
      echo "  \"plan_commit_sha\": \"${sha}\","
      echo "  \"mode\": \"runtime\","
      echo "  \"started_at\": \"2026-04-24T00:00:00Z\","
      echo "  \"ended_at\": \"2026-04-24T00:00:01Z\","
      echo "  \"scenarios\": ["
      local i=0
      for v in $verdicts; do
        [[ $i -gt 0 ]] && echo "    ,"
        echo "    {"
        echo "      \"id\": \"sc-${i}\","
        echo "      \"verdict\": \"${v}\","
        echo "      \"artifacts\": {},"
        echo "      \"assertions_met\": [\"synthetic\"],"
        echo "      \"failure_reason\": null"
        echo "    }"
        i=$((i+1))
      done
      echo "  ]"
      echo "}"
    } > "$artifact_path"
  }

  # Helper: run the script against this temp repo, capture exit code.
  # Set SELFTEST_DEBUG=1 to surface the gate's stderr/stdout for
  # troubleshooting (otherwise quiet by default to keep the summary
  # readable).
  run_gate() {
    if [[ "${SELFTEST_DEBUG:-}" == "1" ]]; then
      bash "$SCRIPT_PATH" </dev/null
    else
      bash "$SCRIPT_PATH" </dev/null >/dev/null 2>&1
    fi
    echo $?
  }

  expect_exit() {
    # $1 = scenario letter, $2 = expected_exit (0 or 2), $3 = description
    local scenario="$1"
    local expected="$2"
    local desc="$3"
    local actual
    actual=$(run_gate)
    if [[ "$actual" == "$expected" ]]; then
      echo "self-test ($scenario) ${desc}: PASS (expected exit ${expected}, got ${actual})" >&2
      PASSED=$((PASSED+1))
    else
      echo "self-test ($scenario) ${desc}: FAIL (expected exit ${expected}, got ${actual})" >&2
      FAILED=$((FAILED+1))
    fi
  }

  # Reset working repo state between scenarios
  reset_repo() {
    rm -rf docs/plans/*.md .claude/state/acceptance/* .claude/state/acceptance-waiver-*.txt 2>/dev/null || true
    # Tear down any leftover worktrees from prior W-scenarios.
    # `git worktree list --porcelain` lists the primary worktree first;
    # we skip the first `worktree` entry and remove the rest. This avoids
    # path-form comparison pitfalls (POSIX `/tmp/...` vs Windows `C:/...`)
    # when running under msys/cygwin.
    if command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      local _line _wt _seen_primary=0
      git worktree list --porcelain 2>/dev/null | while IFS= read -r _line; do
        case "$_line" in
          "worktree "*)
            _wt="${_line#worktree }"
            if [[ $_seen_primary -eq 0 ]]; then
              _seen_primary=1  # skip the primary (always first in porcelain)
            else
              git worktree remove --force "$_wt" 2>/dev/null || true
            fi
            ;;
        esac
      done
      git worktree prune 2>/dev/null || true
    fi
  }

  # Helper: create a secondary worktree of the test repo at <wt-path>
  # and write a synthetic acceptance artifact under its
  # .claude/state/acceptance/<slug>/ directory. Used by W1/W2.
  #   $1 = secondary worktree path (relative to primary)
  #   $2 = slug
  #   $3 = sha (or "current" to read current)
  #   $4 = verdicts (e.g. "PASS PASS")
  write_artifact_in_worktree() {
    local wt_path="$1"
    local slug="$2"
    local sha="$3"
    local verdicts="$4"
    # Create a secondary worktree on a fresh detached branch so we don't
    # collide with the primary's HEAD ref.
    local branch="selftest-wt-$(date +%s%N)"
    git worktree add -q -b "$branch" "$wt_path" 2>/dev/null || {
      # If branch already exists (rare under date+nano collision), retry
      # with detached HEAD.
      git worktree add -q --detach "$wt_path" 2>/dev/null || return 1
    }
    if [[ "$sha" == "current" ]]; then
      sha=$(git log -n 1 --pretty=format:'%H' -- "docs/plans/${slug}.md" 2>/dev/null)
    fi
    local dir="${wt_path}/.claude/state/acceptance/${slug}"
    mkdir -p "$dir"
    local artifact_path="${dir}/sess-test-wt-$(date +%s%N).json"
    {
      echo "{"
      echo "  \"session_id\": \"sess-test-wt\","
      echo "  \"plan_slug\": \"${slug}\","
      echo "  \"plan_commit_sha\": \"${sha}\","
      echo "  \"mode\": \"runtime\","
      echo "  \"started_at\": \"2026-04-27T00:00:00Z\","
      echo "  \"ended_at\": \"2026-04-27T00:00:01Z\","
      echo "  \"scenarios\": ["
      local i=0
      for v in $verdicts; do
        [[ $i -gt 0 ]] && echo "    ,"
        echo "    {"
        echo "      \"id\": \"sc-${i}\","
        echo "      \"verdict\": \"${v}\","
        echo "      \"artifacts\": {},"
        echo "      \"assertions_met\": [\"synthetic-wt\"],"
        echo "      \"failure_reason\": null"
        echo "    }"
        i=$((i+1))
      done
      echo "  ]"
      echo "}"
    } > "$artifact_path"
  }

  # ---- (a) no active plan -> PASS ----
  reset_repo
  write_plan "scenario-a" 0 absent  # COMPLETED status, not ACTIVE
  expect_exit "a" 0 "no-active-plan"

  # ---- (b) active plan with valid PASS artifact -> PASS ----
  reset_repo
  write_plan "scenario-b" 1 false
  write_artifact "scenario-b" "current" "PASS PASS"
  expect_exit "b" 0 "valid-pass-artifact"

  # ---- (c) active plan with FAIL artifact -> BLOCK ----
  reset_repo
  write_plan "scenario-c" 1 false
  write_artifact "scenario-c" "current" "PASS FAIL"
  expect_exit "c" 2 "fail-artifact"

  # ---- (d) active plan with no artifact -> BLOCK ----
  reset_repo
  write_plan "scenario-d" 1 false
  expect_exit "d" 2 "no-artifact"

  # ---- (e) active plan with stale artifact -> BLOCK ----
  reset_repo
  write_plan "scenario-e" 1 false
  write_artifact "scenario-e" "abcdef0000000000000000000000000000000000" "PASS PASS"
  expect_exit "e" 2 "stale-artifact"

  # ---- (f) active plan with valid waiver -> PASS ----
  reset_repo
  write_plan "scenario-f" 1 false
  echo "Waived for self-test scenario f — valid one-line justification text" \
    > ".claude/state/acceptance-waiver-scenario-f-$(date +%s).txt"
  expect_exit "f" 0 "valid-waiver"

  # ---- (g) active plan with acceptance-exempt: true + reason -> PASS ----
  reset_repo
  write_plan "scenario-g" 1 true
  expect_exit "g" 0 "exempt-with-reason"

  # ---- (h) active plan with exempt: true but no reason -> BLOCK ----
  reset_repo
  write_plan "scenario-h" 1 noreason
  expect_exit "h" 2 "exempt-without-reason"

  # ---- (W1) PASS artifact ONLY in secondary worktree -> PASS ----
  # Lead's worktree has no artifact; teammate's worktree wrote a PASS.
  # The gate must aggregate across worktrees and see it.
  reset_repo
  write_plan "scenario-w1" 1 false
  WT1_PATH="${TMPDIR_SELFTEST}/wt-w1"
  if write_artifact_in_worktree "$WT1_PATH" "scenario-w1" "current" "PASS PASS"; then
    expect_exit "W1" 0 "aggregates-across-worktrees"
  else
    echo "self-test (W1) aggregates-across-worktrees: FAIL (could not create secondary worktree)" >&2
    FAILED=$((FAILED+1))
  fi

  # ---- (W2) FAIL artifact in primary, PASS artifact in secondary -> PASS ----
  # Demonstrates that ANY worktree's PASS artifact (matching plan_commit_sha)
  # satisfies the gate, not just the primary's.
  reset_repo
  write_plan "scenario-w2" 1 false
  # Primary worktree: write a FAIL artifact at the matching SHA.
  write_artifact "scenario-w2" "current" "PASS FAIL"
  # Secondary worktree: write a PASS artifact at the same SHA.
  WT2_PATH="${TMPDIR_SELFTEST}/wt-w2"
  if write_artifact_in_worktree "$WT2_PATH" "scenario-w2" "current" "PASS PASS"; then
    expect_exit "W2" 0 "returns-PASS-when-any-worktree-has-valid-artifact"
  else
    echo "self-test (W2) returns-PASS-when-any-worktree-has-valid-artifact: FAIL (could not create secondary worktree)" >&2
    FAILED=$((FAILED+1))
  fi

  # Cleanup any worktrees we left behind so the EXIT trap's rm -rf of
  # TMPDIR_SELFTEST doesn't trip on git's worktree refs.
  reset_repo

  echo "" >&2
  echo "self-test summary: $PASSED passed, $FAILED failed (of 10 scenarios)" >&2
  if [[ $FAILED -eq 0 ]]; then
    exit 0
  else
    exit 1
  fi
fi

# ============================================================
# Main: production execution
# ============================================================

# Read stdin (Claude Code provides JSON). We don't currently need
# anything from it but consume it to avoid SIGPIPE on the producer.
if [[ ! -t 0 ]]; then
  cat >/dev/null 2>&1 || true
fi

# Find ACTIVE plans.
ACTIVE_PLANS=$(find_active_plans)

# No ACTIVE plans → nothing to gate, allow stop.
if [[ -z "$ACTIVE_PLANS" ]]; then
  exit 0
fi

# Walk every active plan; collect blockers.
# Dedupe by slug across worktrees: in a multi-worktree repo,
# `find_active_plans`'s glob may return the same plan via the primary's
# `docs/plans/<slug>.md` AND via a sibling worktree's
# `<wt>/docs/plans/<slug>.md`. Both refer to the same logical plan;
# processing twice would erroneously block on the secondary path
# (where `git log -- <secondary>/docs/plans/<slug>.md` returns no SHA).
BLOCKERS=""
ALLOWS=""
SEEN_SLUGS=" "

while IFS= read -r plan; do
  [[ -z "$plan" ]] && continue
  slug=$(basename "$plan" .md)
  case "$SEEN_SLUGS" in
    *" $slug "*) continue ;;
  esac
  SEEN_SLUGS="${SEEN_SLUGS}${slug} "

  # 1. Exemption check
  exempt_status=$(check_exemption "$plan")
  case "$exempt_status" in
    EXEMPT_OK)
      reason=$(grep -iE '^acceptance-exempt-reason:' "$plan" 2>/dev/null | head -1 | sed 's/^[Aa]cceptance-exempt-reason:[[:space:]]*//')
      echo "[acceptance-gate] plan ${slug} is acceptance-exempt; reason: ${reason}" >&2
      ALLOWS="${ALLOWS}  - ${slug}: exempt (${reason})"$'\n'
      continue
      ;;
    EXEMPT_NO_REASON)
      BLOCKERS="${BLOCKERS}  - ${plan}: declares acceptance-exempt: true but acceptance-exempt-reason is missing or shorter than 20 non-whitespace chars. Add a substantive one-sentence reason or remove the exemption."$'\n'
      continue
      ;;
    NOT_EXEMPT) ;;
  esac

  # 2. Per-session waiver check
  waiver=$(check_waiver "$slug")
  case "$waiver" in
    VALID_WAIVER:*)
      waiver_path="${waiver#VALID_WAIVER:}"
      echo "[acceptance-gate] plan ${slug} has a per-session waiver at ${waiver_path}; allowing stop." >&2
      ALLOWS="${ALLOWS}  - ${slug}: waived (${waiver_path})"$'\n'
      continue
      ;;
    EMPTY_WAIVER)
      BLOCKERS="${BLOCKERS}  - ${slug}: a waiver file exists but is empty. Waivers must contain at least one non-whitespace line of justification."$'\n'
      continue
      ;;
    NO_WAIVER) ;;
  esac

  # 3. Artifact check
  artifact_status=$(check_artifact "$plan")
  case "$artifact_status" in
    SATISFIED)
      echo "[acceptance-gate] plan ${slug}: PASS artifact found matching current plan_commit_sha." >&2
      ALLOWS="${ALLOWS}  - ${slug}: satisfied"$'\n'
      ;;
    NO_DIRECTORY)
      BLOCKERS="${BLOCKERS}  - ${slug}: no acceptance directory at .claude/state/acceptance/${slug}. Run end-user-advocate in runtime mode against this plan, or declare acceptance-exempt: true with a substantive reason."$'\n'
      ;;
    NO_ARTIFACTS)
      BLOCKERS="${BLOCKERS}  - ${slug}: directory exists but contains no JSON artifacts. Run end-user-advocate in runtime mode."$'\n'
      ;;
    STALE)
      current_sha=$(get_plan_sha "$plan")
      BLOCKERS="${BLOCKERS}  - ${slug}: artifacts exist but none match current plan_commit_sha (${current_sha}). Re-run end-user-advocate against the current HEAD of this plan file."$'\n'
      ;;
    FAIL)
      BLOCKERS="${BLOCKERS}  - ${slug}: most recent acceptance artifact for current plan_commit_sha has at least one FAIL scenario. Address the failure(s), then re-run end-user-advocate."$'\n'
      ;;
  esac
done <<< "$ACTIVE_PLANS"

if [[ -z "$BLOCKERS" ]]; then
  exit 0
fi

# Block with detailed message.
cat >&2 <<MSG
================================================================
PRODUCT-ACCEPTANCE GATE — BLOCKED
================================================================

This session has ACTIVE plan(s) whose product has not been verified
at runtime by the end-user-advocate. Per Generation 5 enforcement
(see ~/.claude/rules/acceptance-scenarios.md), a session cannot end
with the product in a user-broken state.

Blocking reasons:

${BLOCKERS}
$(if [[ -n "$ALLOWS" ]]; then echo "Plans that ARE satisfied:"; echo ""; echo "$ALLOWS"; fi)
To unblock, do ONE of:

  1. Run the end-user-advocate in runtime mode against the failing plan(s):
       Task tool: end-user-advocate, mode=runtime, plan=docs/plans/<slug>.md
     The advocate executes the plan's Acceptance Scenarios via browser
     automation and writes a PASS/FAIL artifact to
     .claude/state/acceptance/<slug>/.

  2. Address the failing scenario(s), then re-run the advocate.

  3. If the plan is a harness-dev / pure-infrastructure / migration-only
     plan with no user-facing surface, declare exemption in the plan header:
       acceptance-exempt: true
       acceptance-exempt-reason: <one-sentence substantive justification>
     The reason must be at least 20 non-whitespace characters.

  4. Per-session waiver (use sparingly, audited weekly):
       echo "<one-line justification>" \\
         > .claude/state/acceptance-waiver-<plan-slug>-\$(date +%s).txt
     Waivers are timestamp-gated and expire after 1 hour. Chronic waiver
     use will surface in the weekly /harness-review.

See also:
  - ~/.claude/rules/acceptance-scenarios.md (full loop documentation)
  - ~/.claude/agents/end-user-advocate.md (agent invocation)
  - docs/plans/end-user-advocate-acceptance-loop.md (parent plan)

================================================================
MSG

cat <<'JSON'
{"decision": "block", "reason": "Product-acceptance gate: one or more ACTIVE plans lack a PASS runtime acceptance artifact for the current plan_commit_sha. See stderr for per-plan details and remediation paths."}
JSON

exit 2
