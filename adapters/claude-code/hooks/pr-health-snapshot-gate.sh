#!/bin/bash
# pr-health-snapshot-gate.sh — Stop hook (PR-health-at-session-close gate)
#
# Misha's directive (2026-06-01): a session must surface a PR-health snapshot
# covering all of his active repos before it is allowed to call its work
# complete. This is a HARD REQUIREMENT, not a soft memory rule — the gate
# blocks session wrap (block-mode, the default) when the snapshot is absent.
#
# WHY THIS EXISTS
# ===============
# Cross-repo PR rot (CI-red master, open PRs with failing checks, stale
# green-mergeable PRs) was invisible to the orchestrator: the
# dispatch-session-monitor scheduled task detects it but delivers via
# SendUserMessage to ephemeral sessions the operator never reads. The fix is
# to make PR-health a PULL the agent must emit at every session close, where
# the operator actually sees it — and to enforce that emission mechanically
# rather than hope a memory rule is honored. See HARNESS-GAP-42 (the failure
# that surfaced this) and rules/pr-health-snapshot.md.
#
# DESIGN (mirrors goal-coverage-on-stop.sh + principles-compliance-gate.sh)
# =========================================================================
# 1. Read JSON from stdin. Resolve transcript_path + session_id.
# 2. Defensive no-ops (exit 0): no transcript, no jq, empty transcript,
#    PR_HEALTH_GATE_DISABLE=1.
# 3. Resolve the active-repo list: ~/.claude/config/active-repos.txt
#    (one repo per line, `#` comments), else the hardcoded DEFAULT_REPOS.
#    Self-test override: PR_HEALTH_REPOS_OVERRIDE (space/comma list).
# 4. Extract the LAST assistant message text from $TRANSCRIPT_PATH.
# 5. Classify:
#      - No `## PR Health Snapshot` heading            -> MISSING
#      - Heading present + every repo name covered      -> COMPLETE
#      - Heading present + >=1 repo name uncovered       -> INCOMPLETE
#    "Covered" = the repo name appears in the snapshot, boundary-matched so a
#    short repo name does not match inside a longer one (e.g. "web" must not
#    match inside "web-admin").
# 6. Verdict:
#      - COMPLETE      -> exit 0 (allow).
#      - INCOMPLETE    -> exit 0 + stderr WARNING naming missing repos
#                         ("malformed -> fail-with-warning"; the agent clearly
#                         tried, so don't hard-block on partial coverage).
#      - MISSING, block-mode -> block via retry-guard (exit 2 + JSON decision).
#      - MISSING, warn-mode  -> exit 0 + stderr warning.
#
# ESCAPE HATCH
# ============
# PR_HEALTH_GATE_DISABLE=1 — suppresses all enforcement (for harness-dev
# sessions editing this gate / its repo list, which would self-trigger).
#
# MODE
# ====
# Resolution order: PR_HEALTH_GATE_MODE env  >  ~/.claude/local/pr-health-gate-mode file  >  "block".
# Per Misha's "hard requirement" directive the default is `block` (unlike
# doc-gate's warn-default). Flip to warn per-machine by writing "warn" to the
# local file or exporting PR_HEALTH_GATE_MODE=warn.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ============================================================
# Hardcoded fallback repo list. INTENTIONALLY EMPTY in the shipped kit:
# per harness-hygiene.md the kit must not carry business/org/product repo
# identifiers. Populate the per-machine config at ~/.claude/config/active-repos.txt
# (one repo per line; see examples/active-repos.example.txt). When the list
# resolves empty (no config + empty default + no override) the gate no-ops —
# there is nothing to enforce until the operator declares their active repos.
# ============================================================
DEFAULT_REPOS=""

REQUIRED_HEADING='## PR Health Snapshot'

# ------------------------------------------------------------
# resolve_repo_list — echoes the active repo list (space-separated)
# ------------------------------------------------------------
resolve_repo_list() {
  if [[ -n "${PR_HEALTH_REPOS_OVERRIDE:-}" ]]; then
    # Self-test / per-invocation override. Accept comma OR whitespace separated.
    printf '%s' "$PR_HEALTH_REPOS_OVERRIDE" | tr ',' ' '
    return 0
  fi
  local cfg="${PR_HEALTH_REPOS_CONFIG:-$HOME/.claude/config/active-repos.txt}"
  if [[ -f "$cfg" ]]; then
    # One repo per line; strip comments (#...) and blank lines.
    local list
    list=$(sed -E 's/#.*$//' "$cfg" 2>/dev/null | tr -d '\r' | awk 'NF{print $1}' | tr '\n' ' ')
    if [[ -n "${list// /}" ]]; then
      printf '%s' "$list"
      return 0
    fi
  fi
  printf '%s' "$DEFAULT_REPOS"
}

# ------------------------------------------------------------
# repo_covered <repo> <text> — returns 0 if <repo> appears in <text> as a
# boundary-delimited token (not a prefix of a longer repo name). Case-sensitive
# (configured names may carry distinct casing, and a short name must not match
# inside a longer one, e.g. "web" vs "web-admin").
# ------------------------------------------------------------
repo_covered() {
  local repo="$1" text="$2"
  # Escape regex-significant chars in the repo name.
  local esc
  esc=$(printf '%s' "$repo" | sed -E 's/[][(){}.^$*+?|\\]/\\&/g')
  printf '%s' "$text" | LC_ALL=C grep -E -q "(^|[^A-Za-z0-9-])${esc}([^A-Za-z0-9-]|$)" 2>/dev/null
}

# ============================================================
# --self-test (gh-free; fixture transcripts generated inline)
# ============================================================
if [[ "${1:-}" == "--self-test" ]]; then
  PASS=0
  FAIL=0
  TEST_REPOS="repo-a repo-b repo-c"

  make_transcript() {
    # $1 = path; $2 = last-assistant-message body
    local path="$1" body="$2"
    # Minimal Stop-style JSONL: one user line + one assistant line.
    {
      printf '{"role":"user","content":"do the work"}\n'
      jq -n --arg t "$body" '{role:"assistant",content:[{type:"text",text:$t}]}'
    } > "$path"
  }

  run_case() {
    local name="$1" expected_exit="$2" body="$3" mode="${4:-block}"
    local tdir tfile actual
    tdir=$(mktemp -d 2>/dev/null || mktemp -d -t prhg)
    tfile="$tdir/transcript.jsonl"
    make_transcript "$tfile" "$body"
    PR_HEALTH_TRANSCRIPT="$tfile" \
    PR_HEALTH_SESSION_ID="st-$name" \
    PR_HEALTH_REPOS_OVERRIDE="$TEST_REPOS" \
    PR_HEALTH_GATE_MODE="$mode" \
    RETRY_GUARD_STATE_DIR="$tdir/state" \
      bash "${BASH_SOURCE[0]}" < /dev/null > /dev/null 2>&1
    actual=$?
    rm -rf "$tdir"
    if [[ "$actual" -eq "$expected_exit" ]]; then
      echo "PASS  $name (exit $actual)"
      PASS=$((PASS+1))
    else
      echo "FAIL  $name (expected exit $expected_exit, got $actual)"
      FAIL=$((FAIL+1))
    fi
  }

  COMPLETE_BODY=$'Wrapping up.\n\n## PR Health Snapshot\n\n| Repo | Master | Open PRs | Notes |\n|---|---|---|---|\n| repo-a | green | 0 | clean |\n| repo-b | green | 1 | PR #5 mergeable |\n| repo-c | green | 0 | clean |\n\nDONE: shipped.'
  MISSING_BODY=$'All done. No snapshot here.\n\nDONE: shipped.'
  INCOMPLETE_BODY=$'## PR Health Snapshot\n\n| Repo | Master |\n|---|---|\n| repo-a | green |\n| repo-b | green |\n\n(repo-c not covered)\n\nDONE: shipped.'

  # ST1 — PR data present (all repos covered) -> pass (allow)
  run_case "present-all-repos-allows"          0 "$COMPLETE_BODY"   block
  # ST2 — PR data missing (no heading), block-mode -> block (exit 2)
  run_case "missing-blocks-in-block-mode"      2 "$MISSING_BODY"    block
  # ST3 — malformed (heading present, repo-c missing) -> fail-with-warning (allow + warn)
  run_case "incomplete-warns-and-allows"       0 "$INCOMPLETE_BODY" block
  # ST4 — missing in warn-mode -> allow + warn (exit 0)
  run_case "missing-warn-mode-allows"          0 "$MISSING_BODY"    warn

  # ST5 — disable env -> allow regardless of missing snapshot
  TDIR5=$(mktemp -d 2>/dev/null || mktemp -d -t prhg5)
  make_transcript "$TDIR5/t.jsonl" "$MISSING_BODY"
  PR_HEALTH_TRANSCRIPT="$TDIR5/t.jsonl" PR_HEALTH_SESSION_ID="st-disable" \
  PR_HEALTH_REPOS_OVERRIDE="$TEST_REPOS" PR_HEALTH_GATE_DISABLE=1 \
    bash "${BASH_SOURCE[0]}" < /dev/null > /dev/null 2>&1
  if [[ $? -eq 0 ]]; then echo "PASS  disable-env-allows (exit 0)"; PASS=$((PASS+1)); else echo "FAIL  disable-env-allows"; FAIL=$((FAIL+1)); fi
  rm -rf "$TDIR5"

  # ST6 — no transcript file -> defensive no-op (exit 0)
  PR_HEALTH_TRANSCRIPT="/nonexistent/path/xyz.jsonl" PR_HEALTH_SESSION_ID="st-notx" \
  PR_HEALTH_REPOS_OVERRIDE="$TEST_REPOS" PR_HEALTH_GATE_MODE="block" \
    bash "${BASH_SOURCE[0]}" < /dev/null > /dev/null 2>&1
  if [[ $? -eq 0 ]]; then echo "PASS  no-transcript-noop (exit 0)"; PASS=$((PASS+1)); else echo "FAIL  no-transcript-noop"; FAIL=$((FAIL+1)); fi

  # ST7 — empty repo list (no config + empty default) -> no-op (exit 0), even with
  # a MISSING snapshot in block-mode. Locks the hygiene-clean empty-kit behavior.
  TDIR7=$(mktemp -d 2>/dev/null || mktemp -d -t prhg7)
  make_transcript "$TDIR7/t.jsonl" "$MISSING_BODY"
  PR_HEALTH_TRANSCRIPT="$TDIR7/t.jsonl" PR_HEALTH_SESSION_ID="st-norepos" \
  PR_HEALTH_REPOS_OVERRIDE="" PR_HEALTH_REPOS_CONFIG="/nonexistent/active-repos.txt" \
  PR_HEALTH_GATE_MODE="block" RETRY_GUARD_STATE_DIR="$TDIR7/state" \
    bash "${BASH_SOURCE[0]}" < /dev/null > /dev/null 2>&1
  if [[ $? -eq 0 ]]; then echo "PASS  empty-repo-list-noop (exit 0)"; PASS=$((PASS+1)); else echo "FAIL  empty-repo-list-noop"; FAIL=$((FAIL+1)); fi
  rm -rf "$TDIR7"

  echo ""
  echo "self-test: $PASS pass, $FAIL fail"
  if [[ "$FAIL" -gt 0 ]]; then echo "self-test: FAIL"; exit 1; fi
  echo "self-test: OK $PASS/$PASS"
  exit 0
fi

# ============================================================
# Normal path
# ============================================================

# Shared retry-guard library (3-retry downgrade-to-warn loop-break).
# shellcheck disable=SC1091
source "${BASH_SOURCE[0]%/*}/lib/stop-hook-retry-guard.sh"

INPUT=""
if [[ ! -t 0 ]]; then
  INPUT=$(cat 2>/dev/null || echo "")
fi

TRANSCRIPT_PATH=""
SESSION_ID=""
if [[ -n "$INPUT" ]]; then
  TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // .session.transcript_path // empty' 2>/dev/null || echo "")
  SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // .session.id // empty' 2>/dev/null || echo "")
fi

# Self-test / direct overrides.
[[ -n "${PR_HEALTH_TRANSCRIPT:-}" ]] && TRANSCRIPT_PATH="$PR_HEALTH_TRANSCRIPT"
[[ -n "${PR_HEALTH_SESSION_ID:-}" ]] && SESSION_ID="$PR_HEALTH_SESSION_ID"

# Defensive no-ops (parallel to the sibling Stop gates).
if [[ "${PR_HEALTH_GATE_DISABLE:-0}" = "1" ]]; then exit 0; fi
if [[ -z "$TRANSCRIPT_PATH" ]] || [[ ! -f "$TRANSCRIPT_PATH" ]]; then exit 0; fi
if ! command -v jq >/dev/null 2>&1; then exit 0; fi

# Mode resolution: env > local file > "warn" (default; set "block" in env/file to hard-block).
# 2026-06-20: default flipped block->warn. A Stop hook that blocks the turn-end to force
# a re-pasted section verifies that text was pasted, not that work finished — and it loops.
# Warn surfaces once and never blocks; honest completion is governed by the DONE/PAUSING/
# BLOCKED marker (continuation-enforcer), which leaves pause/ask first-class.
MODE="${PR_HEALTH_GATE_MODE:-}"
if [[ -z "$MODE" ]] && [[ -f "$HOME/.claude/local/pr-health-gate-mode" ]]; then
  MODE=$(tr -d '[:space:]' < "$HOME/.claude/local/pr-health-gate-mode" 2>/dev/null || echo "")
fi
[[ -z "$MODE" ]] && MODE="warn"
[[ "$MODE" != "block" ]] && MODE="warn"

# Extract the LAST assistant message (full text; base64 to survive newlines).
LAST_B64=$(jq -r '
  select(.role == "assistant" or .message.role == "assistant")
  | (.content // .text // .message.content // empty)
  | (if type == "string" then .
     elif type == "array" then ([.[] | select(type=="object" and (.type//"")=="text") | (.text // "")] | join("\n"))
     else (. | tostring) end)
  | select(. != "")
  | @base64
' "$TRANSCRIPT_PATH" 2>/dev/null | tail -n 1)

# No assistant message yet — defer to other gates.
if [[ -z "$LAST_B64" ]]; then exit 0; fi
LAST_ASSISTANT=$(printf '%s' "$LAST_B64" | base64 --decode 2>/dev/null || printf '')

REPOS=$(resolve_repo_list)

# No active repos declared (empty kit fallback + no per-machine config) — nothing
# to enforce. No-op so the shipped kit is inert until the operator populates
# ~/.claude/config/active-repos.txt.
if [[ -z "${REPOS// /}" ]]; then exit 0; fi

# ============================================================
# Classify snapshot presence / coverage
# ============================================================
HAS_HEADING=0
if printf '%s' "$LAST_ASSISTANT" | LC_ALL=C grep -F -q "$REQUIRED_HEADING" 2>/dev/null; then
  HAS_HEADING=1
fi

MISSING_REPOS=""
COVERED_COUNT=0
TOTAL_COUNT=0
for repo in $REPOS; do
  [[ -z "$repo" ]] && continue
  TOTAL_COUNT=$((TOTAL_COUNT+1))
  if [[ "$HAS_HEADING" -eq 1 ]] && repo_covered "$repo" "$LAST_ASSISTANT"; then
    COVERED_COUNT=$((COVERED_COUNT+1))
  else
    MISSING_REPOS="${MISSING_REPOS}${repo} "
  fi
done
MISSING_REPOS="${MISSING_REPOS% }"

# COMPLETE — heading present and every repo covered. Allow silently.
if [[ "$HAS_HEADING" -eq 1 ]] && [[ -z "$MISSING_REPOS" ]] && [[ "$TOTAL_COUNT" -gt 0 ]]; then
  exit 0
fi

# INCOMPLETE — heading present but >=1 repo uncovered. "malformed -> fail-with-warning":
# the agent clearly emitted a snapshot; don't hard-block on partial coverage. Warn + allow.
if [[ "$HAS_HEADING" -eq 1 ]]; then
  echo "" >&2
  echo "[pr-health-gate] WARNING: PR Health Snapshot present but INCOMPLETE — covered ${COVERED_COUNT}/${TOTAL_COUNT} repos. Missing: ${MISSING_REPOS}. Include every active repo (one row per repo) so cross-repo PR rot can't hide. Allowing session wrap (warn) — re-emit a complete snapshot next turn." >&2
  echo "" >&2
  exit 0
fi

# MISSING — no snapshot heading at all.
GH_TEMPLATE="for r in ${REPOS}; do gh pr list --repo <owner>/\$r --state open --json number,title,statusCheckRollup,mergeable,headRefName,updatedAt; done"
BLOCKER_MSG="PR Health Snapshot MISSING. This session is wrapping but its final message contains no '${REQUIRED_HEADING}' section covering Misha's active repos (${REPOS}). Emitting a PR-health snapshot at session close is a hard requirement (rules/pr-health-snapshot.md): cross-repo PR rot (CI-red master, open PRs with failing checks, stale green-mergeable PRs) is otherwise invisible. To clear: run a per-repo PR query, classify CI-failure / merge-conflict / stale-green-mergeable(>=1h), and emit a '${REQUIRED_HEADING}' markdown table (one row per repo) in your final message, then re-attempt Stop. Query template: ${GH_TEMPLATE}"

if [[ "$MODE" = "warn" ]]; then
  echo "" >&2
  echo "[pr-health-gate] WARNING (warn-mode): ${BLOCKER_MSG}" >&2
  echo "" >&2
  exit 0
fi

# block-mode: route through the retry-guard (3-retry downgrade-to-warn).
echo "" >&2
echo "================================================================" >&2
echo "PR-HEALTH-SNAPSHOT GATE: SESSION BLOCKED" >&2
echo "================================================================" >&2
echo "$BLOCKER_MSG" >&2
echo "" >&2
echo "Emit a table shaped like:" >&2
echo "" >&2
echo "    ${REQUIRED_HEADING}" >&2
echo "    " >&2
echo "    | Repo | Master CI | Open PRs (failing/conflict/stale-green) | Action |" >&2
echo "    |---|---|---|---|" >&2
echo "    | <repo> | green/red | #N failing-ci / #M conflict / #K stale-green | <merge/fix/none> |" >&2
echo "" >&2

RG_SESSION_ID=$(retry_guard_session_id "$INPUT")
[[ -z "$RG_SESSION_ID" ]] && RG_SESSION_ID="${SESSION_ID:-pr-health-nosid}"
retry_guard_block_or_exit \
  "pr-health-snapshot-gate" \
  "$RG_SESSION_ID" \
  "pr-health-missing:${TOTAL_COUNT}" \
  "$BLOCKER_MSG" \
  "{\"decision\": \"block\", \"reason\": \"PR Health Snapshot missing — emit a '${REQUIRED_HEADING}' section covering all active repos before wrapping.\"}" \
  2
