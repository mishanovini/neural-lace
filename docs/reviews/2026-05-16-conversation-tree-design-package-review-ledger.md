# Review Ledger — Conversation Tree Management UI design package (2026-05-15 → 2026-05-16)

**Purpose.** Durable audit trail of every gate / adversarial-review / research pass run during the interactive design of the Conversation Tree Management UI module. The *resolutions* live in `docs/prd.md` and `docs/decisions/031-conversation-tree-ui-architecture.md`; this file is the *record that the reviews happened, what they returned, and where each finding was resolved* — persisted per `~/.claude/CLAUDE.md` "Testing results (docs/reviews/)" + `testing.md` (adversarial-review/audit results MUST be persisted to `docs/reviews/`, not left only in agent transcripts + downstream prose).

**Process demonstrated:** Build Doctrine guided design flow (Phase 0 process-ID → Phase 1–2 PRD intake Stages A–F → Phase 3 ADR → mandatory adversarial gates → architecture-pick complete). Ran interactively with Misha as the actual respondent after a course-correction (the initial run proxy-synthesized his answers; caught at Phase 4; protocol re-run from Stage A).

## Gate / review passes

| # | Pass | Artifact @ SHA | Verdict | Resolution / where folded |
|---|---|---|---|---|
| 1 | `prd-validity-gate.sh` (mechanical) | plan write | ALLOW (after Decision-A → `docs/prd.md`) | OQ-9 resolved; gate fired & passed (the demo's "mechanism genuinely fires" point) |
| 2 | `prd-validity-reviewer` (substance) | `docs/prd.md` @ 8b1453e | **PASS** | 1 non-blocking nit (FR-2 multi-divergent cardinality) → resolved in plan Decisions Log |
| 3 | `systems-designer` Tier-5 — ADR-031 r1 | ADR @ 54aac98 | **FAIL** (4 findings, 2 blocking) | r2 honest-restatement fixes; independent re-review **PASS** |
| 4 | `systems-designer` Tier-5 — ADR-031 r2 re-review | ADR @ 2fa15d8 | **PASS** | all 4 r1 findings verified closed, no new holes |
| 5 | `systems-designer` Mode:design — plan SEA | `docs/plans/conversation-tree-ui.md` @ adee136 | **PASS** | 10-section analysis substantive (plan since superseded — Option 4 struck) |
| 6 | `ux-designer` — plan UI surface | plan @ adee136 | 3 Critical + 4 Important + 1 nice | folded as binding `## UX Design Review` commitments (plan now to be re-authored) |
| 7 | `end-user-advocate` plan-time | — | **NOT DISPATCHABLE** (`Agent type not found`) | HARNESS-GAP-34 + discovery filed; checklist self-applied + cross-checked (no silent skip) |
| 8 | `systems-designer` Tier-5 — ADR-031 r7 (accepted) | ADR @ b1b4653 | **FAIL** (3 pin-the-property findings) | 3 plan-safety pins folded into `## Adopted decision (r7)` @ 8275d31; accepted option stood |
| 9 | Research pass — Agent SDK + desktop bridge | 2026-05-15 | findings | shaped ADR r3 option space |
| 10 | Research pass — can external app launch Dispatch | 2026-05-16 | RULED OUT (launch) / VIABLE (SDK own-children) | ADR r5: struck unbuildable variant, added Option 1b, corrected cloud premise |
| 11 | Research pass — local readability of session types | 2026-05-16 | Dispatch locally readable (verified on machine); cloud-only = blind spot | ADR r6/r7: Option 2 viable; cloud blind spot accepted |
| 12 | Research pass — do hooks bind the Dispatch orchestrator | 2026-05-16 | hooks DO fire on local Dispatch | ADR r7 enforcement design (spawn + Stop gates) |

## Adversarial-review findings index (for class-sweep / future reference)

- **systems-designer r1 (ADR):** convention-reuse-claim-without-contract-match; scenario-shape-asserted-in-aggregate; upgrade-path-cost-understated; contract-deferral-when-architecture-depends-on-contract. All resolved r2.
- **systems-designer r7 (ADR, accepted):** (F1) enforcement-matcher-undercovers-the-action-class; (F2) fail-closed-without-bounded-recovery-and-without-defined-error-partition; (F3) architecture-viability-property-deferred-to-downstream-contract-ADR. All folded as r7 Plan-safety pins (8275d31). Probes that PASSed recorded in the ADR.
- **prd-validity-reviewer:** acceptance-criterion-undertested-on-cardinality (FR-2) — non-blocking, resolved in plan.
- **ux-designer:** unspecified-resolution-affordance-for-bidirectional-state; silent-state-transition-on-the-anti-silent-loss-product; missing-information-hierarchy-on-multi-surface-landing; +Important set. Folded into the (now-to-be-re-authored) plan's UX commitments.

## Process-fidelity incidents (cross-ref)

- Proxy-synthesis of PRD intake → course-corrected; discovery `2026-05-15-demonstration-tasks-need-real-touchpoints-not-proxy-synthesis.md` (superseded by master's `interactive-process-fidelity.md` rule + HARNESS-GAP-33).
- `end-user-advocate` not dispatchable in Dispatch env → HARNESS-GAP-34 + discovery.
- bug-persistence gate false-fires on interactive-intake surface-and-wait turns → discovery `2026-05-16-bug-persistence-gate-false-fires-on-interactive-intake-surface-turns.md` (this ledger entry is itself the legitimate-fire case: an audit result that genuinely needed persisting).

## Status

Architecture-pick phase **COMPLETE**. PRD signed off; ADR-031 r7 ACCEPTED + Tier-5-hardened (plan-safe). Plan-and-build is a separate phase gated on Misha's explicit greenlight. No open review findings outstanding — all verdicts above are either PASS or FAIL-then-folded.
