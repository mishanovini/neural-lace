---
title: session-wrap.sh worktree-blind on SCRATCHPAD freshness
date: 2026-05-09
type: process
status: implemented
auto_applied: false
originating_context: ad-hoc cleanup session in worktree neural-lace/stupefied-brattain-94152b
decision_needed: n/a — user authorized recommendation A (hook falls back to parent repo when in worktree)
predicted_downstream:
  - adapters/claude-code/scripts/session-wrap.sh
  - adapters/claude-code/rules/orchestrator-pattern.md (worktree convention)
  - possibly templates/plan-template.md or a new template/scratchpad-pointer.md
---

## What was discovered

`session-wrap.sh` (Stop hook, ADR 027 Layer 5) checks
`<git-toplevel>/SCRATCHPAD.md` for mtime freshness. From inside a git
worktree, `git rev-parse --show-toplevel` returns the worktree's path,
not the parent repo's. Worktrees do not carry their own `SCRATCHPAD.md`
by convention (only the parent does), so the hook computes staleness
against a missing file and reports an absurd "1666666 min stale"
(~3.17 years), which is the script's `mtime_seconds_ago` returning a
sentinel for the missing file.

The hook fires every Stop event, blocking session-end with the same
signal. Refreshing the parent repo's SCRATCHPAD via
`cd <parent-repo> && session-wrap.sh refresh` does NOT clear it —
the next Stop fires from the worktree's perspective again.

Adjacent prior discovery
`2026-05-04-worktree-base-points-at-master-not-branch-head.md`
covered a different worktree-related issue (worktree HEAD vs branch
HEAD). The session-wrap blind-spot is a separate failure shape.

## Why it matters

Three immediate costs:

1. Every worktree session ends with a noisy false-stale signal that
   the user has to either ignore or work around.
2. The user cannot trust the freshness-signal output anymore — it
   cries wolf from worktrees, training the operator to ignore it,
   which weakens the signal for the case it was designed to catch
   (genuinely stale parent SCRATCHPADs in non-worktree sessions).
3. ADR 027 Layer 5's whole point is structural detection of stale
   handoff artifacts; the worktree blind-spot is a hole in the
   structure.

## Options

### A. Hook falls back to parent repo when in a worktree

Modify `session-wrap.sh`'s `find_repo_root` (or whatever returns the
SCRATCHPAD's directory) to detect worktree context via
`git rev-parse --git-common-dir` and use the parent of that when it
differs from `--show-toplevel`. Then check the parent's SCRATCHPAD.

- **Cost:** ~10 lines of bash; one new edge case in `find_repo_root`.
  Worktrees that genuinely should have their own SCRATCHPAD (rare,
  but possible) lose that capability.
- **Benefit:** zero convention change for users. Works retroactively
  for every existing worktree.
- **Reversibility:** trivial. Single-commit revert.

### B. Convention requires every worktree to carry its own SCRATCHPAD

Document that worktrees carry a thin "pointer" SCRATCHPAD that just
references the parent. The hook stays as-is.

- **Cost:** every new worktree needs ceremony (create + commit a
  pointer SCRATCHPAD); easy to forget, so we'd want a hook to auto-
  create on worktree creation. More mechanism, more surface.
- **Benefit:** worktrees that genuinely diverge (long-running
  feature branches with their own active plans) can have their own
  SCRATCHPAD legitimately.
- **Reversibility:** medium. Removing the convention later means
  cleaning up scattered pointer files.

### C. Hook silent-pass in worktrees

Detect worktree context and skip the SCRATCHPAD freshness signal
entirely (still run the other 5 signals).

- **Cost:** worktree sessions get NO SCRATCHPAD-staleness check —
  if a worktree session does meaningful harness work, the operator
  is on their own to keep the parent's SCRATCHPAD fresh.
- **Benefit:** zero false positives; minimal mechanism change.
- **Reversibility:** trivial.

## Recommendation

A — fall back to parent repo's SCRATCHPAD when in a worktree.

Principle: the rule that *should* hold (one SCRATCHPAD per repo, in the
parent) already does hold; the hook just doesn't honor it from
worktrees. Fixing the hook to match the existing rule keeps the
substrate consistent and adds zero ceremony for users. The "worktree
might want its own SCRATCHPAD" case (option B) is theoretical — the
orchestrator-pattern explicitly says worktrees are short-lived build
isolation, not branch lifetimes that warrant their own state. C is a
half-measure that loses the freshness signal exactly where it's
non-trivial to keep fresh manually.

## Decision

A — `session-wrap.sh`'s `find_repo_root` falls back to the parent repo's
toplevel when invoked from inside a worktree. Detection via
`git rev-parse --git-common-dir` ≠ `--git-dir`; parent toplevel is
`dirname` of the common .git directory. User authorized this option in
the 2026-05-09 session ("let's go with your recommendations") after
seeing options A/B/C with rationale.

Documented as ADR 028
(`docs/decisions/028-session-wrap-worktree-fallback.md`).

## Implementation log

- `~/.claude/scripts/session-wrap.sh` — `find_repo_root` extended to
  detect worktree context via `--git-common-dir` ≠ `--git-dir` and
  return `dirname` of the common .git when they differ; preserves
  prior behavior in primary-repo case (commit pending).
- `adapters/claude-code/scripts/session-wrap.sh` — synced from live
  copy; byte-identical (commit pending).
- Self-test extended with scenario S7 (worktree-fallback): creates a
  worktree against a synthetic repo, calls `find_repo_root` from
  inside, confirms it returns the parent's toplevel. All 7 scenarios
  pass.
- Verified end-to-end in this real worktree
  (`stupefied-brattain-94152b`): `session-wrap.sh verify` from the
  worktree now reports "all freshness signals PASS" against the
  parent repo's SCRATCHPAD.
- Worktree-local SCRATCHPAD created earlier as immediate workaround
  (at `stupefied-brattain-94152b/SCRATCHPAD.md`) deleted as part of
  this fix — redundant once the hook honors the parent's SCRATCHPAD.
- Cross-referenced in `~/.claude/rules/vaporware-prevention.md`
  enforcement map.
