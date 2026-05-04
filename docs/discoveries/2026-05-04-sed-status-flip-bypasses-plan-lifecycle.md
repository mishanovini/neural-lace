---
title: Bash sed-based Status flips bypass plan-lifecycle.sh auto-archive
date: 2026-05-04
type: process
status: decided
auto_applied: true
originating_context: Phase 1d-C-3 completion — flipped Status: ACTIVE → COMPLETED via Bash heredoc + sed -i; plan-lifecycle.sh did not fire; manual git mv required
decision_needed: n/a — option D applied 2026-05-04 (document convention + SessionStart safety-net sweep)
predicted_downstream:
  - hooks/plan-lifecycle.sh
  - hooks/plan-status-archival-sweep.sh (NEW SessionStart hook landing 2026-05-04)
  - rules/planning.md (Plan File Lifecycle section — Stage 3.5 added)
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

**Option D applied 2026-05-04 (document + SessionStart sweep).** User accepted the recommendation as auto-applyable per discovery-protocol's reversibility test.

**Reasoning principle:** `plan-lifecycle.sh` is a Mechanism. Its post-condition (terminal-status plans live in `docs/plans/archive/`) should hold regardless of HOW the flip happened. Documentation alone is fragile (this very session forgot the convention); a SessionStart sweep restores the invariant for every Status-flip path — Edit, Write, Bash sed, future automation.

**Auto-applied: yes.** Reversible — one revert removes the new hook + the doc note.

**Tradeoff acknowledgment:** archival now happens at NEXT session start, not at flip time. A COMPLETED plan can sit in `docs/plans/` for the rest of the current session. Acceptable because archival is housekeeping; the Edit-tool path (recommended convention) keeps zero-latency archival via `plan-lifecycle.sh`, and the sweep is the safety net for everything else.

## Implementation log

- 2026-05-04 — `hooks/plan-status-archival-sweep.sh` shipped (5 self-test scenarios PASS). SessionStart hook scans `docs/plans/*.md` for terminal-Status (COMPLETED / DEFERRED / ABANDONED / SUPERSEDED), `git mv`s matches into `docs/plans/archive/` (plus sibling `<slug>-evidence.md`).
- 2026-05-04 — `rules/planning.md` Plan File Lifecycle section extended with Stage 3.5 documenting the safety-net + the "use Edit/Write not Bash sed" convention reminder.
- 2026-05-04 — Hook wired into both `~/.claude/settings.json` AND `adapters/claude-code/settings.json.template`.
- 2026-05-04 — Live-fired the new hook against 3 stranded plans from prior sessions: `document-freshness-system.md`, `harness-quick-wins-2026-04-22.md`, `public-release-hardening.md` (and their evidence siblings) all now in archive/. Verified `git mv` rename tracking for the one tracked plan (harness-quick-wins).
- 2026-05-04 — Hook bug discovered + fixed during real-world archival: original `git -C "$plans_dir/.."` resolved to `docs/`, not the repo root, so `git mv` always silently fell through to plain `mv` (losing rename history). Fixed to use `git -C "$plans_dir" rev-parse --show-toplevel` for correct repo-root resolution. Self-test scenario 3 extended to assert `git diff --cached --name-status` reports `R<num>` so this bug can't regress silently.
