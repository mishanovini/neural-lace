#!/bin/bash
# concurrent-ownership-gate.sh — PreToolUse gate: block shared-plan-state
# mutations whose target is OWNED by another live session.
#
# Origin: docs/lessons/2026-07-11-bulk-shared-state-mutation-without-ownership-check.md
# (nl-issue [35]). A session under pressure bulk-flipped every ACTIVE plan to
# DEFERRED and pushed to master — including a plan being actively built right
# then by a concurrent same-machine worktree session. The prevention
# discipline (parallel-dev-discipline Practice 8: claim-before-touch /
# check-ownership-before-mutating-shared-state) existed only as a self-applied
# Pattern; this gate promotes it to a Mechanism.
#
# Constitution §10 evidence (mirrored in manifest.json):
#   golden_scenario      — a session bulk-defers docs/plans/*.md including a
#                          plan whose branch is checked out in another
#                          worktree; the gate blocks the Status flip / git mv
#                          and NAMES the owning worktree.
#   fp_expectation       — low: fires only on plan-Status / bulk / branch-
#                          delete / worktree-remove operations, and only when
#                          a live other-worktree checkout or a fresh (<2h)
#                          competing claim exists. Own-plan mutation (slug
#                          matches the current worktree's branch) never fires.
#   retirement_condition — if worktree-per-session claiming is enforced
#                          upstream (launcher writes an authoritative
#                          per-branch lock), the `git worktree list` heuristic
#                          simplifies to a lock read.
#
# Trigger:
#   PreToolUse on tool_name in {Bash, PowerShell}  — command-string parsing
#     (settings matcher "Bash|PowerShell"; splits on && / ;, tracks cd /
#     Set-Location and `git -C` per scope-enforcement-gate.sh's pattern).
#   PreToolUse on tool_name in {Edit, Write, MultiEdit} — payload parsing
#     (settings matcher "Edit|Write|MultiEdit"; file_path + new content).
#
# BLOCKS (exit 2, stderr explanation, {"decision":"block"} on stdout) when:
#   (a) an edit/redirect flips a top-level docs/plans/*.md `Status:` line to a
#       terminal state (DEFERRED/COMPLETED/ABANDONED/SUPERSEDED), or an
#       mv / git mv moves a file in/out of docs/plans/, AND the plan's slug is
#       owned by another live session;
#   (b) a BULK plan mutation (loop / xargs / find / docs/plans/* glob combined
#       with a mutation indicator) — the concrete target list is unknowable
#       from the command string, so ALL on-disk ACTIVE plans are checked and
#       ANY owned member blocks the whole command;
#   (c) `git branch -D/-d` of a branch checked out in another worktree or
#       freshly claimed, or `git worktree remove` of a worktree covered by a
#       fresh other-session claim (mere worktree existence does NOT block a
#       removal — a worktree is by definition "checked out"; the claim is the
#       live-session signal, else every legitimate prune would false-fire).
#
# OWNERSHIP (block if either is true; "another" = not this repo root / branch):
#   1. `git worktree list --porcelain` — the target branch is checked out in
#      ANOTHER worktree on this machine (the check the lesson's incident was
#      missing; cheapest, most reliable signal).
#   2. A fresh (<COG_CLAIM_FRESH_SECONDS, default 7200s by file mtime) claim
#      file from another session in $COG_CLAIMS_DIR (written by
#      broadcast-active-session.sh `claim` / `write`). Claims are REPO-scoped
#      (harness-review round 1): the claims dir is machine-global, so each
#      claim carries a "repo" identity field (origin push URL, else absolute
#      git common dir) and _load_fresh_claims SKIPS claims whose identity
#      differs from the current repo's — a claim on repo A never blocks
#      same-named branches/plans in repo B.
#
# Slug↔branch matching: plan slug minus its trailing -YYYY-MM-DD date suffix
# ("slug core") is substring-matched against candidate branch names (harness
# convention: plan foo-bar-2026-07-11.md ↔ branch feat/foo-bar). Slug cores
# shorter than 4 chars are never matched (fail-open, keeps FP low).
#
# WAIVER (structured escape hatch, house pattern per harness-hygiene-scan.sh
# / ADR 059 D4): a fresh (<1h) file at
#   <repo>/.claude/state/concurrent-ownership-waiver-*.txt
# naming BOTH purpose clauses (lib/waiver-purpose-clause.sh) AND containing
# the blocked target string (slug or branch — a "Target: <x>" line is the
# convention). Every waiver use is ledger-logged (lib/signal-ledger.sh).
# Fails closed: missing/stale/clause-less/wrong-target waivers do not unlock.
#
# KNOWN LIMITS (documented, accepted):
#   - A single-file in-place edit through a shell VARIABLE path with no loop
#     (`sed -i ... "$plan"`) is not extractable from the command string and
#     passes; the loop/glob forms (the lesson's actual shape) are caught.
#   - In-place-edit detection requires the string `Status` AND a terminal-
#     state token (DEFERRED|COMPLETED|ABANDONED|SUPERSEDED) in the command
#     (the gate guards terminal Status flips, not prose edits — a sed over
#     '## Status quo' passes); mv/git mv of a plan file needs no Status
#     marker — the move itself is the mutation.
#   - PowerShell-NATIVE mutations (Set-Content / Move-Item / Rename-Item /
#     Out-File over docs/plans/) are NOT parsed — only bash-idiom command
#     strings (sed/mv/git/redirects) are recognized, whichever tool carries
#     them. A PowerShell-cmdlet rewrite of a plan passes unexamined.
#   - Script-wrapped mutations (`bash foo.sh` where foo.sh flips plan Status)
#     pass unexamined — the gate sees only the command string, not what the
#     script does.
#   - Claims lacking the "repo" identity field (pre-repo-scoping schema) are
#     SKIPPED with a stderr note (fail-open): a missing field on a fresh
#     same-machine claim is ambiguous, and reviewer intent is that foreign-
#     repo claims must never block; the live owning session re-scopes its
#     claim at its next SessionStart write / Stop refresh.
#   - Claim lifecycle: claims are written at SessionStart and refreshed at
#     each Stop, but there is NO session-end unclaim hook yet — claims
#     persist up to 2h (COG_CLAIM_FRESH_SECONDS) past a session's last turn.
#     Expect stale-claim blocks in that window; the structured waiver is the
#     valve. Lifecycle wiring is queued in docs/backlog.md
#     (CLAIM-LIFECYCLE-01).
#
# Env knobs:
#   COG_CLAIMS_DIR            claims directory (default
#                             ~/.claude/state/active-session-broadcast/claims;
#                             sandboxed under HARNESS_SELFTEST=1)
#   COG_CLAIM_FRESH_SECONDS   claim freshness window (default 7200)
#
# Exit codes:
#   0 — allowed / not applicable
#   2 — blocked (stderr explains; {"decision":"block"} on stdout)
#   (--check pre-flight mode: 0 would-pass / 1 would-block — see
#   lib/gate-contract-lib.sh)
#
# ============================================================
# THIN DISPATCHER (Gate Philosophy Law retrofit, R3.4, harness-execution-
# redesign-2026-08 Task 2). Full mechanism — setup helpers, --self-test,
# main hook logic, the _block() structured-fields emitter — lives in
# concurrent-ownership-gate-body.sh, SOURCED only when relevant. This file
# owns exactly: --self-test/--check dispatch, and a cheap pure-bash
# relevance pre-filter so the overwhelmingly common case (a tool call this
# gate does not apply to at all — most Bash/PowerShell/Edit/Write/MultiEdit
# events touch neither docs/plans/ nor a branch/worktree operation) exits
# WITHOUT ever sourcing the body, without a single jq/grep subprocess spawn.
# ============================================================

# Path resolution is DEFERRED past this point on purpose: `dirname`/
# `basename` are external binaries (a fork each on this platform), and
# `${BASH_SOURCE[0]}` is only needed once we know we're actually sourcing
# the body. The common fast-pass path below (no docs/plans|branch|worktree
# substring) computes NONE of this — see the resolution site above each
# `source` call.
_COG_ARGV1="${1:-}"

case "$_COG_ARGV1" in
  --self-test|--check)
    # Parameter-expansion path split (no dirname/basename fork).
    _COG_ENTRY_DIR="$(cd -- "${BASH_SOURCE[0]%/*}" 2>/dev/null && pwd)"
    _COG_ENTRY_PATH="$_COG_ENTRY_DIR/${BASH_SOURCE[0]##*/}"
    # shellcheck source=concurrent-ownership-gate-body.sh
    source "$_COG_ENTRY_DIR/concurrent-ownership-gate-body.sh"
    exit $?
    ;;
esac

# --- Cheap relevance pre-filter (perf; behavior-preserving) -----------------
# Every code path this gate guards requires one of these literal substrings
# in the raw tool-input payload: "docs/plans" (Edit/Write/MultiEdit file_path
# match, and the Bash/PowerShell command-string plan-mention check), "branch"
# or "worktree" (the git branch-delete / worktree-remove command paths). This
# is a deliberate OVER-approximation of the body's own (tighter, per-path)
# checks — false positives just source the body, which then concludes
# "not applicable" on its own; a false negative here would be a silent
# bypass, which is why the filter is a strict superset, not a rewrite, of
# every existing internal check it now runs ahead of. Pure-bash substring
# test — no jq/grep spawn — so the common non-matching event never pays for
# any subprocess, let alone parsing the ~950-line body. Consume the input
# ONCE (env var else stdin) and re-export it so the body's own read is
# unaffected — same pattern as scope-enforcement-gate.sh.
_COG_PF="${CLAUDE_TOOL_INPUT:-}"
if [[ -z "$_COG_PF" ]] && [[ ! -t 0 ]]; then
  _COG_PF=$(cat 2>/dev/null || echo "")
fi
export CLAUDE_TOOL_INPUT="$_COG_PF"
case "$_COG_PF" in
  *docs/plans*|*branch*|*worktree*) : ;;   # possibly relevant — source the body
  *) exit 0 ;;      # guaranteed irrelevant — done, zero path-resolution forks paid
esac

_COG_ENTRY_DIR="$(cd -- "${BASH_SOURCE[0]%/*}" 2>/dev/null && pwd)"
# shellcheck source=concurrent-ownership-gate-body.sh
source "$_COG_ENTRY_DIR/concurrent-ownership-gate-body.sh"
exit $?
