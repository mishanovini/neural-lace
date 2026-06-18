# Plan: Exact-Ask Rule (encode "when waiting, state exactly what you need")
Status: COMPLETED
Execution Mode: orchestrator
Mode: code
Backlog items absorbed: none
acceptance-exempt: true
acceptance-exempt-reason: harness-internal rule addition; no product surface; the decision-context-gate already provides the mechanical enforcement.
tier: 2
rung: 0
architecture: coding-harness
frozen: true
prd-ref: n/a — harness-development

## Goal
Encode Misha's 2026-06-14 directive: "No more waiting. If you're waiting on me for something, finish your turn by telling me exactly what you need from me. Encode that." Make it a durable contract, not a promise.

## User-facing Outcome
Every turn that ends waiting on Misha now carries an explicit, fenced, actionable ask (what he needs to provide, why it's his, what unblocks) — he can act without a clarifying follow-up — rather than a vague "let me know."

## Scope
- IN: a sharp clause in `rules/session-end-protocol.md` binding the PAUSING/waiting state to a required fenced Decision-Context ask; the architecture-doc changelog entry.
- OUT: a new hook (the existing `decision-context-gate.sh` already mechanically enforces the fence); changing the marker vocabulary.

## Tasks
- [x] 1. Add the "Exact-Ask Rule" clause to `rules/session-end-protocol.md` PAUSING section. — Verification: mechanical
- [x] 2. Architecture-doc changelog entry; sync rule to live `~/.claude`. — Verification: mechanical

## Files to Modify/Create
- `adapters/claude-code/rules/session-end-protocol.md` — the Exact-Ask Rule clause.
- `docs/harness-architecture.md` — changelog entry.

## In-flight scope updates
(no in-flight changes yet)

## Assumptions
- The existing `decision-context-gate.sh` Stop hook is the mechanical enforcement (decision-soliciting final message without a fence BLOCKS); this rule documents the binding it enforces.
- `session-end-protocol.md` is already in `rules/INDEX.md` (no new index row needed for an edit).

## Edge Cases
- Turn that needs nothing from the user → no ask, no fence; drive autonomously (keep-going).
- Turn genuinely BLOCKED on environment → BLOCKED marker names the resource (existing rule).

## Acceptance Scenarios
n/a — acceptance-exempt (harness-internal rule edit; enforcement is the existing decision-context-gate).

## Out-of-scope scenarios
- Browser/runtime acceptance: not applicable.

## Testing Strategy
- Rule edit is documentation; the mechanical enforcement (`decision-context-gate.sh`) is unchanged and already self-tested.
- Verify live `~/.claude/rules/session-end-protocol.md` is byte-identical to canonical.

## Walking Skeleton
The clause + the existing gate together ARE the end-to-end slice: a waiting turn without a fenced ask is already blocked by `decision-context-gate.sh`; this rule makes the PAUSING-must-carry-the-exact-ask binding explicit.

## Decisions Log
- Encoded as a clause in the existing session-end-protocol rule (its natural home — governs PAUSING) rather than a new rule file, to avoid a redundant INDEX row and because the mechanical enforcement already exists in decision-context-gate.sh.

## Pre-Submission Audit
- S1–S5: n/a — single-clause rule edit, Mode: code harness-infrastructure.

## Definition of Done
- [x] Clause added to session-end-protocol.md
- [x] Architecture-doc updated; rule synced live byte-identical

## Completion Report (2026-06-17 — triage)

Verified shipped on `origin/master`:

- **Task 1** (Exact-Ask Rule clause in `rules/session-end-protocol.md` PAUSING section) — SHIPPED via commit **bd08119** ("feat(rules): Exact-Ask Rule — waiting turns must state exactly what's needed", 2026-06-14). The clause is present at `adapters/claude-code/rules/session-end-protocol.md:34`; the live `~/.claude/rules/session-end-protocol.md` is byte-identical to canonical (`diff -q` clean) — satisfying the Task-2 live-sync sub-deliverable too.
- **Task 2** (architecture-doc changelog entry + live sync) — live-sync sub-deliverable shipped via bd08119 (byte-identical, confirmed). The architecture-doc changelog sub-deliverable was MISSED by bd08119 (which touched only `session-end-protocol.md`, +2 lines) and is closed here in the triage commit: the `session-end-protocol.md` row in `docs/harness-architecture.md` now carries the "Extended 2026-06-14 (Exact-Ask Rule, commit bd08119)" note.

The load-bearing deliverable — the rule clause + its mechanical enforcement (`decision-context-gate.sh`, unchanged and already self-tested) — is genuinely on master. acceptance-exempt (harness-internal rule edit; enforcement is the existing decision-context-gate). All tasks confirmed shipped → COMPLETED.

Note: this plan file was never committed in its originating session — it lived only staged in the main checkout's working tree. The triage commit lands it (with this report) so the audit trail is durable.
