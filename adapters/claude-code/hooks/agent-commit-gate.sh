#!/usr/bin/env bash
# agent-commit-gate.sh — SubagentStop gate: a worktree-isolated subagent may not
# END its run with uncommitted work. (GATE 3 of the evidence-bar enforcement.)
#
# WHY (golden scenario, recurred 4x in one session, 2026-07-13/14): builders
# repeatedly ended "standing by" (or were mid-work at a process exit) with their
# fix UNCOMMITTED in the worktree. Recovery worked only because a human-driven
# orchestrator noticed and reconciled — a memory-rung control. doctrine/
# reap-what-you-spawn.md names the class; this gate is its Mechanism for the
# one exit path a hook CAN see: the subagent's own clean stop.
#
# HONEST COVERAGE (manifest honest_status mirrors this):
#   COVERED: a subagent that voluntarily ends its turn with a dirty isolated
#            worktree → blocked once, told exactly how to preserve (commit /
#            stash / waiver), then allowed through on the retry.
#   NOT COVERED (fires no hook, by platform reality): crash, SIGKILL, machine
#            reboot, TaskStop teardown. Those need the detection layer
#            (orphaned-worktree-guard, REFORMULATE'd — separate work).
#   NOT COVERED: post-stop writes by children the agent backgrounded (the
#            gate cannot see the future — reap-what-you-spawn owns that).
#
# FALSE-POSITIVE DESIGN (the cry-wolf lesson from orphaned-worktree-guard):
#   - Fires ONLY when the stopping agent's cwd is inside a `.claude/worktrees/`
#     pool entry. Reviewers / explorers / main-checkout agents → structurally
#     silent (their dirt, if any, is the orchestrator's tree, not theirs).
#   - Fires ONLY on actual dirt (`git status --porcelain` non-empty, which
#     includes untracked files — the Task-15 near-loss was untracked backlog.js).
#   - BOUNDED: honors stop_hook_active (the platform's own re-entry flag) so a
#     blocked agent that cannot commit (e.g. another gate blocks its commit) is
#     never looped — one block, with `git stash push -u` named as the escape
#     that ALWAYS succeeds, then pass-through.
#   - Fail-open on everything unexpected (no stdin, no jq, no git, cwd gone):
#     a gate that errors closed on its own plumbing is worse than no gate.
#
# PROBE (first-live-fire contract confirmation): SubagentStop's exact input
# fields are documented but not yet observed in this harness; every invocation
# appends one line of field-availability metadata (never content) to
# ~/.claude/state/agent-commit-gate-probe.jsonl so the first real firing
# confirms the contract empirically. Remove the probe once confirmed.

set -u

STATE_DIR="${HOME}/.claude/state"
PROBE="${STATE_DIR}/agent-commit-gate-probe.jsonl"

# ---- self-test ---------------------------------------------------------------
# Sandboxed (mktemp; NL-FINDING-029: neuter hooksPath in fixtures). Each scenario
# drives THIS script with synthetic SubagentStop stdin and asserts the exit code.
if [ "${1:-}" = "--self-test" ]; then
  SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
  T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
  PASS=0; FAIL=0
  mk_repo() { # $1=path  -> git repo with one commit
    mkdir -p "$1" && git -C "$1" init -q && git -C "$1" config core.hooksPath "" \
      && git -C "$1" config user.email t@example.com && git -C "$1" config user.name t \
      && echo base > "$1/base.txt" && git -C "$1" add -A && git -C "$1" commit -qm base
  }
  run() { # $1=name $2=cwd $3=stop_active $4=expected_rc $5=enforce(0|1) [$6=raw_stdin] [$7=session_id]
    local rc=0 in
    if [ -n "${6:-}" ]; then in="$6"; else in="{\"cwd\":\"$2\",\"stop_hook_active\":$3,\"session_id\":\"${7:-sess-selftest}\"}"; fi
    printf '%s' "$in" | HOME="$T/home" AGENT_COMMIT_GATE_ENFORCE="$5" bash "$SELF" >/dev/null 2>&1 || rc=$?
    if [ "$rc" = "$4" ]; then echo "self-test ($1): PASS" >&2; PASS=$((PASS+1))
    else echo "self-test ($1): FAIL (rc=$rc expected=$4)" >&2; FAIL=$((FAIL+1)); fi
  }
  mkdir -p "$T/home/.claude/state"
  POOL="$T/proj/.claude/worktrees/agent-t1"; mk_repo "$POOL"
  # S1 ENFORCE: dirty (tracked edit) pool worktree -> BLOCK (2)
  echo dirty >> "$POOL/base.txt"
  run "S1-dirty-pool-blocks" "$POOL" false 2 1 "" sess-s1
  # S9 ENFORCE: same session again, fresh block-marker -> PASS-THROUGH (0)
  #    [defense-in-depth loop bound that holds even if stop_hook_active is never set]
  run "S9-marker-bounds-loop" "$POOL" false 0 1 "" sess-s1
  # S6 ENFORCE: untracked-only dirt -> BLOCK (2)  [Task-15 near-loss was an untracked file]
  git -C "$POOL" checkout -q -- base.txt; echo new > "$POOL/untracked.js"
  run "S6-untracked-only-blocks" "$POOL" false 2 1 "" sess-s6
  # S8 OBSERVE (default): dirty pool -> exit 0 AND the probe records the would-block verdict
  run "S8-observe-default-passes" "$POOL" false 0 0 "" sess-s8
  if grep -q '"would_block":true,"outcome":"observed-would-block"' "$T/home/.claude/state/agent-commit-gate-probe.jsonl" 2>/dev/null; then
    echo "self-test (S8b-observe-probe-records-verdict): PASS" >&2; PASS=$((PASS+1))
  else
    echo "self-test (S8b-observe-probe-records-verdict): FAIL (probe lacks observed would_block)" >&2; FAIL=$((FAIL+1))
  fi
  # S4 ENFORCE: stop_hook_active=true + dirty -> PASS-THROUGH (0)  [platform retry flag]
  run "S4-stop-active-passes" "$POOL" true 0 1 "" sess-s4
  # S7 ENFORCE: fresh waiver with Purpose:/Because: -> allowed (0)
  mkdir -p "$POOL/.claude/state"
  printf 'Purpose: staged handoff\nBecause: intentional WIP for review\n' \
    > "$POOL/.claude/state/worktree-teardown-waiver-t.txt"
  run "S7-fresh-waiver-allows" "$POOL" false 0 1 "" sess-s7
  rm -f "$POOL/.claude/state/worktree-teardown-waiver-t.txt"
  # S2 clean pool worktree -> silent (0)
  rm -f "$POOL/untracked.js"
  run "S2-clean-pool-silent" "$POOL" false 0 1 "" sess-s2
  # S3 dirty NON-pool repo (main checkout shape) -> silent (0)  [no false positive]
  MAIN="$T/proj-main"; mk_repo "$MAIN"; echo dirty >> "$MAIN/base.txt"
  run "S3-dirty-nonpool-silent" "$MAIN" false 0 1 "" sess-s3
  # S5 garbage stdin -> fail-open (0). Passes because of the NO-pwd-fallback design:
  # with unparseable input there is no cwd to act on, even though this test process's
  # own cwd may itself be a dirty pool worktree.
  run "S5-garbage-stdin-failopen" "" false 0 1 'not-json-at-all{{{'
  echo "" >&2
  echo "self-test summary: $PASS passed, $FAIL failed (of $((PASS+FAIL)) scenarios)" >&2
  [ "$FAIL" = 0 ] && exit 0 || exit 1
fi

_norm() { printf '%s' "$1" | tr '\\' '/' | tr '[:upper:]' '[:lower:]' | sed 's|//*|/|g'; }

# ---- read the SubagentStop event off stdin (fail-open) ----------------------
INPUT="$(cat 2>/dev/null || true)"
CWD=""; STOP_ACTIVE=""; SID=""
if command -v jq >/dev/null 2>&1 && [ -n "$INPUT" ]; then
  CWD="$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)"
  STOP_ACTIVE="$(printf '%s' "$INPUT" | jq -r '.stop_hook_active // empty' 2>/dev/null || true)"
  SID="$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)"
fi
# NO pwd fallback — deliberately. The hook process may run in the MAIN session's
# cwd (which in parallel-worktree mode is itself a pool worktree); guessing would
# block innocent subagents on the orchestrator's dirt (self-test S5 proves the
# no-fallback design: garbage stdin stays silent even when the PROCESS cwd is a
# dirty pool worktree).
# If the event carries no cwd, stay silent; the probe log records the gap.

# ---- rollout posture (harness-review 2026-07-17: observe-first) -------------
# Default = OBSERVE: compute the verdict, record it in the probe, exit 0.
# Enforce (exit 2) ONLY when AGENT_COMMIT_GATE_ENFORCE=1, and only AFTER the
# probe has confirmed the SubagentStop contract on real fires:
#   (1) cwd identifies the STOPPING agent's OWN worktree (agent-<its-id>), never
#       a parent's; (2) stop_hook_active is actually set on the blocked retry
#       (correlate block->retry pairs by session_id). Until then, blocking on an
#       unconfirmed contract risks the reviewed data-loss tail: a false-blocked
#       subagent stashing the ORCHESTRATOR's live WIP.
ENFORCE="${AGENT_COMMIT_GATE_ENFORCE:-0}"

_probe() { # $1=would_block  $2=outcome
  ( mkdir -p "$STATE_DIR" 2>/dev/null || exit 0
    # rotation: keep the file bounded (~200KB) — tail-keep the newest half
    if [ -f "$PROBE" ] && [ "$(wc -c < "$PROBE" 2>/dev/null || echo 0)" -gt 200000 ]; then
      tail -n 500 "$PROBE" > "$PROBE.tmp" 2>/dev/null && mv "$PROBE.tmp" "$PROBE" 2>/dev/null
    fi
    printf '{"ts":"%s","cwd":"%s","session_id":"%s","stop_active":"%s","cwd_is_pool":%s,"would_block":%s,"outcome":"%s","enforce":%s}\n' \
      "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      "$(printf '%s' "$CWD" | tr '"\\' "''" )" \
      "$(printf '%s' "$SID" | tr '"\\' "''" )" \
      "${STOP_ACTIVE:-unset}" \
      "$(case "$(_norm "$CWD")" in */.claude/worktrees/*) echo true;; *) echo false;; esac)" \
      "$1" "$2" "$ENFORCE" >> "$PROBE" 2>/dev/null ) || true
}

# ---- bounded retry, two independent layers ----------------------------------
# Layer 1: the platform's own re-entry flag.
if [ "$STOP_ACTIVE" = "true" ]; then _probe false retry-passthrough; exit 0; fi
# Layer 2 (defense-in-depth; stop_hook_active is an UNCONFIRMED contract): a
# fresh per-session marker from a prior block forces pass-through even if the
# platform never sets the flag — no agent can be blocked twice in 10 minutes.
MARKER="${STATE_DIR}/agent-commit-gate-block-$(printf '%s' "${SID:-nosid}" | tr -cd 'a-zA-Z0-9-' | cut -c1-64)"
if [ -f "$MARKER" ] && [ -n "$(find "$MARKER" -mmin -10 2>/dev/null)" ]; then
  _probe false marker-passthrough; exit 0
fi

# ---- scope: only isolated agent worktrees ------------------------------------
case "$(_norm "$CWD")" in
  */.claude/worktrees/*) : ;;
  *) _probe false skip-non-pool; exit 0 ;;
esac
[ -d "$CWD" ] || { _probe false skip-no-dir; exit 0; }
git -C "$CWD" rev-parse --git-dir >/dev/null 2>&1 || { _probe false skip-no-git; exit 0; }

# ---- waiver escape hatch (same convention as work-integrity check-c) --------
# a fresh (<30min) worktree-teardown-waiver with a Purpose:/Because: pair
for w in "$CWD"/.claude/state/worktree-teardown-waiver-*.txt; do
  [ -f "$w" ] || continue
  if [ -n "$(find "$w" -mmin -30 2>/dev/null)" ] \
     && grep -qi '^Purpose:' "$w" 2>/dev/null && grep -qi '^Because:' "$w" 2>/dev/null; then
    _probe false waiver; exit 0
  fi
done

# ---- the check: any uncommitted work (tracked or untracked)? ----------------
DIRT="$(git -C "$CWD" status --porcelain 2>/dev/null | head -20 || true)"
[ -z "$DIRT" ] && { _probe false clean; exit 0; }

# would-block verdict reached. OBSERVE (default): record and pass through.
if [ "$ENFORCE" != "1" ]; then
  _probe true observed-would-block
  exit 0
fi

# ENFORCE: block once (marker caps it even if stop_hook_active never arrives).
( mkdir -p "$STATE_DIR" 2>/dev/null && touch "$MARKER" 2>/dev/null ) || true
_probe true blocked
COUNT="$(printf '%s\n' "$DIRT" | grep -c . || true)"
{
  echo "[agent-commit-gate] BLOCKED: you are ending this agent run with ${COUNT}+ uncommitted change(s) in your isolated worktree:"
  printf '%s\n' "$DIRT" | sed 's/^/    /'
  echo ""
  echo "Uncommitted work in an agent worktree is how work gets orphaned (doctrine/reap-what-you-spawn.md)."
  echo "Preserve it NOW, then end your turn again — pick ONE:"
  echo "  1) COMMIT (if this is deliverable work): git add -A && git commit -m '<what you built>'"
  echo "  2) STASH (always succeeds, even if a commit gate blocks you — and the right choice for"
  echo "     throwaway scratch/analysis files if you are a read-only agent):"
  echo "     git stash push -u -m 'wip-$(date -u +%Y%m%dT%H%M%SZ)'"
  echo "  3) WAIVER (only for intentional WIP): write .claude/state/worktree-teardown-waiver-<ts>.txt"
  echo "     in this worktree naming 'Purpose:' and 'Because:'."
  echo "This gate will not fire twice for the same stop."
} >&2
exit 2
