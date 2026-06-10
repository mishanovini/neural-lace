---
title: Silent doc-truncation + session-wrap/hygiene backlog-commit harness bugs
date: 2026-06-08
type: failure-mode
status: pending
auto_applied: false
originating_context: orchestrator-prime loop session 2026-06-08; surfaced while trying to satisfy the recurring session-wrap "backlog stale" signal
decision_needed: Approve the three fixes below (truncation guard; backlog hygiene/scope exemption; session-wrap non-mutating warn-only)?
predicted_downstream:
  - adapters/claude-code/hooks/ (new or amended guard against silent doc truncation)
  - adapters/claude-code/patterns/harness-denylist.txt OR scope-enforcement-gate.sh (backlog exemption)
  - adapters/claude-code/scripts/session-wrap.sh (warn-only + non-mutating for backlog)
  - docs/failure-modes.md (new FM entry for silent strip-and-reappend truncation)
---

## What was discovered

Three related defects observed in a single orchestrator-prime loop session:

### 1. `awk '/header/{exit}'` strip-and-reappend silently truncated docs/backlog.md (~190 lines lost)
While trying to strip-and-reappend a `## Open` section, `awk '/^## Open — orchestrator-prime/{exit} {print}'`
matched a **pre-existing** header earlier in the file and cut everything after it — `docs/backlog.md`
went 829 → 639 lines with NO error. Caught only by noticing the `195 deletions` in the commit summary;
restored from `HEAD~1`. The general failure CLASS: any script that strip-and-reappends a section by
matching a header is unsafe if that header is non-unique or appears before the intended cut point —
it silently truncates. A second truncation (working tree → 637) also occurred this session from an
unconfirmed source (see #3).

**Proposed guard:** any strip-and-reappend (or any scripted doc rewrite) must assert a before/after
line-count delta within expected bounds and abort otherwise. OR a pre-commit guard that BLOCKS a commit
deleting more than N lines from a `docs/**` file unless the message carries an explicit
`[large-deletion: <reason>]` acknowledgment. The cost of a false block is one annotation; the cost of a
silent miss is destroyed content.

### 2. session-wrap "backlog stale" is UNSATISFIABLE in orchestrator-loop sessions (two gates conflict)
`session-wrap.sh` flags `docs/backlog.md` as stale and wants a fresh COMMIT. But committing the
neural-lace backlog is blocked by TWO gates:
- **harness-hygiene denylist** — the backlog legitimately references the downstream product, which the
  denylist flags as a project-identifier leak.
- **scope-enforcement-gate** — no active plan scopes `docs/backlog.md`.
So a long-running loop literally cannot satisfy the staleness signal, and it re-fires every Stop,
re-invoking the agent indefinitely (the minute-count in the message changes each fire, which may also
defeat the stop-hook retry-guard's identical-signature downgrade).

**Proposed fix:** exempt `docs/backlog.md` from the hygiene denylist (it is the operator's working
backlog, not shipped kit) AND/OR make session-wrap's backlog-staleness check **warn-only** (never block /
re-invoke). Also confirm the retry-guard keys on a signature that ignores the changing minute count.

### 3. Working-tree backlog truncated to 637 without explicit agent action (UNCONFIRMED source)
After a clean 829-line restore was committed, the working tree later showed 637 lines (the truncated
version) staged, without an explicit edit by the agent in between. HYPOTHESIZED source: `session-wrap.sh
refresh` mode ("applies mechanical updates to stale artifacts") may be mutating/truncating the backlog,
OR a residual staged state from the earlier failed commit. REFUTATION/verify: run `session-wrap.sh refresh`
against a known-good 829-line backlog in isolation and check the resulting line count. If refresh truncates,
that is a data-loss bug in the hook and is higher priority than #1.

## Why it matters
Two silent-truncation incidents in one session on the same file. The harness's whole anti-vaporware /
integrity posture is undermined if its OWN hooks (session-wrap refresh) or common scripted edits can
silently destroy committed-class content. The session-wrap re-invocation loop also wastes a long-running
orchestrator session's context on an unsatisfiable signal.

## Recommendation
Fix all three. Priority: (3) confirm/deny session-wrap-refresh truncation first (potential active
data-loss bug), then (1) the generic truncation guard, then (2) the backlog hygiene/scope exemption +
warn-only staleness. Each is a small, reversible harness change.
