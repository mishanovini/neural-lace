---
title: Bash sed-based Status flips bypass plan-lifecycle.sh auto-archive
date: 2026-05-04
type: process
status: pending
auto_applied: false
originating_context: Phase 1d-C-3 completion — flipped Status: ACTIVE → COMPLETED via Bash heredoc + sed -i; plan-lifecycle.sh did not fire; manual git mv required
decision_needed: Whether to extend plan-lifecycle.sh to also react on PostToolUse Bash sed patterns, OR document the convention that Status flips MUST use Edit/Write tools
predicted_downstream:
  - hooks/plan-lifecycle.sh
  - rules/planning.md (Plan File Lifecycle section)
  - any future automation that flips plan Status programmatically
---

## What was discovered

`plan-lifecycle.sh` is a PostToolUse hook on the Edit and Write tools. When a plan's `Status:` field flips to a terminal value (COMPLETED / DEFERRED / ABANDONED / SUPERSEDED), it auto-archives the plan + its evidence sibling to `docs/plans/archive/`.

But Claude Code only emits PostToolUse Edit/Write events for **Edit/Write tool calls**, not for Bash. When Phase 1d-C-3's completion was finalized via:

```bash
sed -i 's/^Status: ACTIVE$/Status: COMPLETED/' docs/plans/phase-1d-c-3-findings-ledger.md
```

The file was modified, the Status field flipped, but `plan-lifecycle.sh` did NOT fire. Recovery required manual `git mv` to archive/. Phase 1d-C-2's archival worked correctly because the Status flip used the Edit tool, not Bash sed.

## Why it matters

Plan archival is supposed to be automatic ("Status: COMPLETED auto-archives"). When it isn't, the plan accumulates in `docs/plans/` past completion, eventually triggering `scope-enforcement-gate.sh` false-claims (the plan is COMPLETED but still appears as ACTIVE-or-claimable to gates that scan top-level `docs/plans/`). That contradicts the lifecycle invariant that COMPLETED plans live in archive/.

This bug is silent — the operation appears to succeed (sed doesn't error), but the post-condition (plan in archive/) doesn't hold. A maintainer who flips Status via sed and moves on without checking archive/ would leave the plan stranded.

Also relevant: any future automation that programmatically flips Status (e.g., a `/complete-plan <slug>` skill, or a session-end hook that auto-completes plans whose tasks are all checked) would hit this if implemented via Bash rather than via tool calls.

## Options

A. **Document the convention.** Add to `rules/planning.md` Plan File Lifecycle section: "Status flips MUST use Edit/Write tools (not Bash sed) so plan-lifecycle.sh fires." Cheap; relies on memory; the failure mode is silent.

B. **Extend plan-lifecycle.sh to also fire on PostToolUse Bash.** Match Bash commands containing `sed.*Status:.*COMPLETED` (or similar patterns). False-positive risk: any unrelated Bash command mentioning these strings would trip the hook. Mitigation: tight regex + specific-file filter.

C. **A polling fallback.** Add a SessionStart sweep that scans `docs/plans/*.md` for terminal-Status plans and archives any it finds. Catches both Edit and Bash paths. Latency cost: archival happens at next session start, not at flip time. Acceptable if the alternative is silent strandedness.

D. **Hybrid.** A (document) + C (SessionStart sweep). Doc + safety net.

## Recommendation

D. Documentation alone is fragile (this very session forgot it); a SessionStart sweep is a cheap belt-and-suspenders that handles both Edit-tool and Bash paths AND any future automation that programmatically flips Status. The latency cost (one session-start delay) is irrelevant — archival is housekeeping.

**Reasoning principle:** `plan-lifecycle.sh` is a Mechanism. Its post-condition (terminal-Status plans live in archive/) should hold regardless of HOW the flip happened. A SessionStart sweep restores that invariant.

## Decision

Pending. Surface to user at next SessionStart.

## Implementation log

(Empty until decided.)
