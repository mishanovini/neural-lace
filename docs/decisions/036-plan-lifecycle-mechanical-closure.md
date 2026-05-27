# 036 — Plan Lifecycle: Mechanical Closure Machine Attached at Creation

- **Date:** 2026-05-25
- **Status:** Proposed (design-only; implementation gated on Misha's authorization)
- **Stakeholders:** Misha (owner/authorizer), harness maintainers, every future Claude Code session that creates or closes a plan
- **Supersedes / amends:** does not supersede; extends the plan-lifecycle substrate (`plan-lifecycle.sh`, `close-plan.sh`, `plan-reviewer.sh`, `product-acceptance-gate.sh`, `start-plan.sh`, `task-verifier`). Builds on the "What Done Means" reframing (2026-05-05) and Tranches B/D/E of the architecture-simplification arc.
- **Originating diagnosis:** `docs/discoveries/2026-05-25-plan-staleness-root-cause-chain.md`
- **Design plan:** `docs/plans/plan-lifecycle-redesign.md`

## Context

The harness has a manual, closure-time-defined plan lifecycle. A plan is created
with `Status: ACTIVE`, worked on, and then — if anyone remembers — manually
closed. Two symptoms result (full causal chain in the originating discovery):

1. **Mass acceptance-gate waivers.** `product-acceptance-gate.sh` demands a PASS
   artifact for every ACTIVE non-exempt plan at session end. Acceptance scenarios
   are a rule-required heading whose *substance* is optional and routinely
   skipped, so the demanded artifact is frequently unproducible. Sessions write
   per-session waivers as the default escape. Loud is not rare.

2. **Stale ACTIVE plans**, via three sub-causes: (a) work shipped but Status never
   flipped; (b) plan filed but never worked; (c) plan started then stalled.

The single root cause: **the plan's closure machine is defined (if at all) at
closure time, and closure is manual.** Misha's governing principle for the fix:
*the right answer is mechanical, not advisory* ("we should remember to flip
Status" loses to "the system auto-flips Status"), and *palliative solutions are
off the table* (auto-defer and nag-surfacers are rejected; only root-cause
structural prevention is acceptable).

This ADR locks four interlocking sub-decisions. Each converts a missing
creation-time commitment into a mandatory, mechanically-enforced artifact, and
makes closure automatic.

## Decision

Attach a plan's full **closure machine** at creation, and make closure
**automatic**. Four locked sub-decisions:

### 036-a — Acceptance scenarios are MANDATORY and POPULATED before `Status: ACTIVE` (non-exempt plans)

A non-`acceptance-exempt` plan cannot reach `Status: ACTIVE` unless its
`## Acceptance Scenarios` section is populated with **concrete steps and expected
outputs** — not just a present heading, not placeholder text. Enforced by a
mechanical gate (extension of `plan-reviewer.sh`; see 036-e). The friction that
caused scenarios to be skipped is removed by a generator (the
`acceptance-scenario-designer` script + agent pair) that reads the plan's Goal /
Scope / Files-to-Modify and produces a populated draft the orchestrator/user
edits. **Gate makes it mandatory; generator makes satisfying the gate cheap.**
Both are mechanical.

`acceptance-exempt: true` plans (harness-development, pure-infra) are NOT required
to write acceptance scenarios — but they ARE required to declare their PASS-
artifact contract in self-test terms (036-b). The exemption is preserved exactly
as it exists today; it shifts the closure target from "acceptance scenarios" to
"self-test PASS," it does not remove the target.

### 036-b — The PASS-artifact contract is DEFINED at creation, before any work starts

Every ACTIVE plan ships a `## Closure Contract` section declaring, concretely:

- **Commands that run** to verify completion (the acceptance-scenario runtime
  commands for product plans; the `--self-test` invocations for harness plans).
- **Expected outputs** (the PASS criteria — e.g., "exit 0", "13/13 PASS",
  "scenario `foo` verdict PASS").
- **On-disk artifact location** where the PASS artifact lands
  (`.claude/state/acceptance/<slug>/...` for product; the structured
  `<slug>-evidence/<task-id>.evidence.json` set for harness).
- **The closure contract sentence** — "this plan is DONE when: all tasks are
  task-verifier PASS AND the artifact at `<location>` exists with `<verdict>`."

This is "we know we're done when…" written before work begins. It is the
pre-agreed target that auto-closure (036-c) reads. Defining it at creation — not
re-litigating "are we done?" at session end when context is thinnest — is the
structural cure for the waiver flood.

### 036-c — Closure is AUTOMATIC: auto-flip + archive when the last task verifies AND the contract artifact exists

When `task-verifier` flips the final task checkbox to `[x]` AND the predefined
Closure Contract artifact exists and matches (verdict + `plan_commit_sha`), the
plan **auto-flips to `Status: COMPLETED` and archives** — no manual Status flip,
no manual `close-plan.sh` invocation. Mechanism: a new PostToolUse hook
(`plan-auto-closure.sh`) fires on the plan-file checkbox-flip edit, detects the
all-tasks-done + contract-satisfied condition, and invokes the deterministic
closure machinery (reusing `close-plan.sh`'s report-generation + Status-flip +
archival, which already exist and are audited).

`close-plan.sh` ceases to be the routine path. It becomes the explicit path for
**abandonment / deferral / supersession** and for manual recovery. For a healthy
plan, closure is routine and invisible. The auto-closure hook is held to a strict
no-false-positive bar (036, Consequences + the self-test design in the plan): it
must NEVER close a plan with an unchecked task, a missing/stale/FAIL artifact, or
a partial verifier verdict.

### 036-d — Staleness is prevented by OWNER ACCOUNTABILITY commitments at creation — NOT auto-defer

Two new mandatory plan-header fields, gate-enforced on `Status: ACTIVE` like the
existing 5-field schema:

- `owner:` — who is accountable for this plan reaching a terminal state.
- `target-completion-date:` — the date by which the owner commits the plan will
  be closed (`YYYY-MM-DD`).

These are structural commitments. Each stale sub-cause is then prevented at root:

- **(a) shipped-not-flipped** — eliminated by 036-c (auto-closure). The plan
  cannot linger ACTIVE after the work verifies.
- **(b) filed-never-worked** — a plan past `target-completion-date` with **zero
  in-scope commits** is a **breached commitment**. It triggers an explicit
  **decision moment** for the owner: renew (new target), abandon, or convert to a
  backlog item. NOT auto-defer — the system never silently buries the work; it
  forces the owner's decision and will not let the breach persist invisibly.
- **(c) started-then-stalled** — a plan past target WITH in-scope commits is
  in-progress-but-overdue; the owner is pinged to continue or surface the blocker
  (the blocker, once surfaced, is itself a decision moment).

The commitment-breach mechanism is deliberately **narrow** (fires only on
target-passed AND, for sub-cause b, zero-in-scope-commits) so it does not become
a new always-firing gate that breeds its own waivers. It enforces a contract the
owner signed, not generic drift-nagging — the distinction that separates it from
the rejected palliative surfacer.

## Alternatives considered

- **A — Palliative: SessionStart surfacer listing stale plans + faster manual
  closing.** Rejected by Misha. Treats the symptom; adds nagging; does not stop
  accumulation. A surfacer that fires every session is the waiver problem in a
  different shape.
- **B — Auto-defer stale plans.** Rejected by Misha. Auto-defer masks the broken
  commitment and silently buries work. "NOT auto-defer" is an explicit
  constraint.
- **C — Loosen / advisory acceptance gate, or exempt more plans.** Rejected. Weakens
  the harness's core anti-vaporware guarantee to paper over a creation-time gap.
  Wrong layer — the gate is correct; the plans were never structured to satisfy it.
- **D — Keep closure manual but add a stronger Stop-hook nag to flip Status.**
  Rejected. Still advisory ("remember to flip"); fails Misha's mechanical-not-
  advisory principle.
- **E (SELECTED) — Mechanical structural redesign: closure machine attached at
  creation + automatic closure + owner-accountability commitments.** Every stale
  state prevented by a creation-time commitment enforced by code.

## Consequences

**Enables:**
- Plans no longer accumulate in ACTIVE: healthy plans auto-close the moment they
  verify; unworked plans are forced to a decision at their target date. The set of
  ACTIVE plans at any session end is small and each has a known, producible
  contract — which dissolves the mass-waiver scenario at root.
- "Are we done?" is answered by a pre-agreed contract, mechanically, not
  re-litigated at session end.
- The acceptance gate's PASS artifact becomes *producible by construction*
  (036-a), so the gate stops being a waiver-generator.

**Costs / risks (named honestly — open risks for Misha's review):**
- **R1 — Auto-closure false positives.** Closing an unfinished plan is the worst
  failure. Mitigated by the strict no-false-positive self-test suite (see plan
  §self-test design); the hook closes ONLY on all-checkboxes-`[x]` + artifact
  present + verdict PASS + `plan_commit_sha` match. Residual risk: a plan with a
  too-thin task list could "complete" prematurely — partially mitigated because
  036-a/b force a real closure contract that must also be satisfied.
- **R2 — The acceptance-scenario generator is a script + LLM-agent pair; the
  script can only scaffold structure and infer surfaces, not author semantically
  correct scenarios.** The concrete-step authoring is the agent's; substance is
  reviewer-validated. If the agent is skipped, the ACTIVE-gate blocks (mandatory
  populated scenarios) — so the failure mode is "can't go ACTIVE," not "ships
  empty scenarios." Acceptable.
- **R3 — The commitment-breach decision moment is still a session interaction.**
  If scoped too broadly it could become waiver-bait (the very problem we're
  fixing). Mitigated by narrowness (target-passed + zero-in-scope-commits) and by
  scoping to the owner. Open question for Misha: should it block at session end,
  or surface-without-blocking? (Plan §10 carries the open decision.)
- **R4 — Migration of existing ACTIVE plans.** Plans created before this redesign
  lack `owner`, `target-completion-date`, and `## Closure Contract`. The gates
  must grandfather pre-existing plans (apply only to plans created after the
  redesign lands, OR provide a one-time backfill). Open question for Misha.
- **R5 — Interaction with `product-acceptance-gate.sh` and the waiver-removal
  cleanup (Part B).** This ADR's mechanisms must land BEFORE the accumulated
  waivers are removed (Part B), and Part B is also gated on "Part A" (acceptance-
  gate session-relevance) from the prior waiver root-cause session. Sequencing is
  in the roadmap; Part A's details need confirmation from Misha.

**Blocks / forecloses:**
- Auto-defer as a staleness response (explicitly foreclosed by 036-d).
- Closure-time-only definition of the PASS contract (foreclosed by 036-b).

## Refutation criterion (per `~/.claude/rules/claims.md`)

The central causal claim — "stale ACTIVE plans and mass waivers are both caused by
the closure machine being defined at closure time + manual closure" (HYPOTHESIZED)
— would be REFUTED if, after 036-a/b/c/d ship, ACTIVE plans still accumulate and
waivers still fire at the pre-redesign rate. The measurable check post-
implementation: count of ACTIVE plans at session end and count of fresh
acceptance-waiver files written per week, before vs. after. If neither drops, the
diagnosis was wrong and the redesign should be reconsidered rather than extended.
