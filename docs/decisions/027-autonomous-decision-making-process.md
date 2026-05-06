# ADR 027 — Autonomous Decision-Making Process

**Date:** 2026-05-05
**Status:** Active
**Stakeholders:** Maintainer (decision authority); orchestrator agents (operational executor); future-session orchestrators (downstream consumers).

## Context

The user's working pattern is asynchronous review of substantial autonomous work. The orchestrator agent runs continuously through long arcs (e.g., Tranche 1.5's ~14-22 day critical path); the user reviews at session boundaries. Stopping mid-arc to ask questions blocks progress against an asynchronously-available decider.

User directive 2026-05-05: "What I don't want is you stopping to wait for me to answer questions. If you have any way to continue working while I review and answer questions, I want you to do that."

Two complementary needs surfaced:

1. **Pre-emptive identification of decisions** — when a plan is kicked off, enumerate every decision that will need to be made during its execution. Surface them all as a decision queue at plan-creation time, so the user can review and answer asynchronously while building proceeds.

2. **Mid-execution autonomous decisions** — when a decision arises during execution that wasn't anticipated AND is reversible, present options + tradeoffs + recommendation, then PROCEED with the recommendation. Document the decision in `docs/decisions/`. Surface the decision in the final summary so the user can review it asynchronously.

Both directly extend the existing Tier 1 / 2 / 3 mid-build decision protocol from `~/.claude/rules/planning.md`. The novelty is the **pre-emptive surfacing at plan-kickoff time** + the **mandatory documentation in `docs/decisions/`** + the **mandatory final-summary roundup** that ensures the user can review all autonomous decisions made during the work.

## Decision

Adopt a four-layer autonomous decision-making process:

### Layer 1 — Pre-emptive identification at plan kickoff

When authoring any non-trivial plan (Mode: code at R2+ OR Mode: design OR any plan with >5 tasks), the planner enumerates the decisions the orchestrator and builders will face during execution. Each surfaced decision includes:

- **Decision label** (short identifier, e.g., `D.1`, `D.2` per tranche)
- **Question** (one sentence, specific)
- **Options** (at least 2, ideally 3-4, each with cost/benefit summary)
- **Recommendation** (with one-sentence justification — usually a principle: reversibility, blast radius, alignment with prior decisions, cost/benefit ratio)
- **Reversibility classification** (REVERSIBLE — orchestrator may proceed with recommendation if user hasn't responded; IRREVERSIBLE — orchestrator MUST pause and wait for user)

The decision queue lives at `docs/decisions/queued-<plan-slug>.md` (or `docs/decisions/queued-<arc-name>.md` for multi-plan arcs like Tranche 1.5). User reviews asynchronously and amends the queue file with their answers. Orchestrator reads the queue file before each substantive decision point during execution.

### Layer 2 — Mid-execution autonomous decisions (reversible only)

When a decision arises mid-execution that wasn't in the queue:

1. **Identify whether it's reversible.** Reversible = a single revert + minor cleanup undoes it. Irreversible = schema migration, public API change, credential change, production deploy, cross-repo contract break, anything matching Tier 3 of the existing planning.md mid-build protocol.
2. **If REVERSIBLE:** present options + tradeoffs + recommendation in working memory (commit message OR completion report OR session summary). PROCEED with the recommendation. Document the decision in a new `docs/decisions/NNN-<short-slug>.md` file. The decision is reversible by design; user can override after-the-fact.
3. **If IRREVERSIBLE:** pause and wait for user authorization. Same as Tier 3 of the existing protocol.

### Layer 3 — Mandatory documentation in `docs/decisions/`

Every Layer 2 autonomous decision lands in `docs/decisions/NNN-<short-slug>.md` per the existing ADR convention. Each gets a sequential number; each gets a row in `docs/DECISIONS.md` (atomicity per the decisions-index-gate).

The ADR captures: Context, Options Considered, Recommendation, Decision, Reversibility, How to Reverse, Cross-references. This makes the autonomous decision auditable; user can review, amend, or revert.

For lightweight decisions (Tier 1 — strictly local, near-zero blast radius), a short Decisions Log entry in the active plan file suffices. The threshold: if the decision could reasonably be questioned by a future session OR a future maintainer, it gets a dedicated ADR.

### Layer 4 — Final summary surfacing

Every session-ending summary (the response Claude provides after autonomous work completes) MUST include a "Decisions made autonomously" section listing:

- Each ADR number + title (one line per decision)
- A pointer to the queued-decisions file if applicable
- A pointer to the final summary's "what's left for user review" section

This ensures the user sees the decision trail without having to dig through commits or files. The user can amend or revert any decision at next-session start.

## Alternatives Considered

### Alternative A — Always pause and wait

The current default. Pros: zero risk of unwanted decisions landing. Cons: blocks all progress against an asynchronously-available decider; produces the friction the user is explicitly trying to eliminate.

**Rejected because:** the user has explicitly directed against this pattern and authorized autonomous proceed for reversible decisions.

### Alternative B — Always proceed (no documentation requirement)

Maximal velocity. Pros: never stops. Cons: no audit trail; user can't review what was decided autonomously; reversal becomes hard because the decision is invisible.

**Rejected because:** the user explicitly asked for documentation in `docs/decisions/` and final-summary surfacing. Velocity-without-traceability is the failure mode.

### Alternative C — Layer 1 + Layer 2 only (no separate documentation)

Surface decisions pre-emptively in queues, proceed autonomously on reversible mid-execution decisions, but rely on commit messages + completion reports for the audit trail rather than dedicated ADR files.

**Partially adopted.** Lightweight Tier-1 decisions land in plan-file Decisions Log (per existing convention). Substantive Tier-2 decisions get dedicated ADRs (this layer). The split matches what the existing planning.md protocol already does for Tier 2+ decisions; the novelty is Tier-2 ADRs being authored DURING autonomous work, not after a pause for user authorization.

### Alternative D — Asynchronous question pinning

Use a notification system (push notification, GitHub issue, chat message) to alert the user when a decision is needed; orchestrator doesn't proceed until ack. Cleaner than pause-and-wait because the user can answer asynchronously without an active session.

**Rejected (for now) because:** the harness has no built-in pinning mechanism; building one is itself substantial work; the user's stated alternative (proceed-with-recommendation + documentation + final-summary) is structurally simpler and accomplishes the same async-review property.

## Consequences

### Positive

- **Velocity preserved.** Orchestrator never stops mid-arc on reversible decisions. Tranche 1.5's ~14-22 day critical path stays on schedule.
- **User retains authority.** All autonomous decisions are reversible by definition; user can amend or revert at next-session start.
- **Audit trail intact.** Every decision lives in `docs/decisions/`; every session-end summary lists them; commit messages reference them.
- **Decision identification gets better with practice.** Layer 1's pre-emptive surfacing forces the planner to think through the decision space before execution. Over time, more decisions land in queues (anticipated) rather than mid-execution (unanticipated).
- **Pattern matches the user's stated working style.** Asynchronous review with high-trust autonomous execution. This ADR formalizes what was implicit.

### Negative

- **Some autonomous decisions will be wrong.** Reversal cost (revert + minor cleanup) is non-zero, and frequent reversals erode trust. Mitigation: high bar on the recommendation; principles cited; reversibility classification done conservatively (when in doubt, classify as IRREVERSIBLE and pause).
- **The queue file can grow unwieldy on long arcs.** Mitigation: per-tranche queue files for multi-tranche arcs (e.g., `queued-tranche-c.md`, `queued-tranche-d.md`); orchestrator references the relevant queue at each tranche start.
- **The mandatory ADR-per-decision can produce ADR sprawl.** Mitigation: only Tier 2+ decisions get ADRs; Tier 1 stays in plan files. The threshold is "could a future session reasonably question this?"

### Neutral

- **Pre-emptive identification is bounded by the planner's foresight.** Some decisions are genuinely unforeseeable. Layer 2's mid-execution path covers them. The two layers compose.
- **The user's "I will not be readily available" assumption is a default, not a constraint.** If the user IS available and replies in-session to a Layer 2 decision, the orchestrator takes the user's input and may revise the recommendation accordingly — without losing autonomy semantics.

### Open

- Whether the "Decisions made autonomously" final-summary section should also appear in PR descriptions when the work crosses a PR boundary. Lean toward yes for traceability; deferred until the first natural PR within Tranche 1.5.
- How this composes with the existing `claim-reviewer` agent (which is supposed to question feature claims). Lean toward orthogonal — claim-reviewer still operates on factual claims; ADR 027 governs how decisions get made and recorded. Reassess if friction surfaces.

## How to Reverse

Single-line reverse: flip Status to ABANDONED on this ADR, update the index in DECISIONS.md, return to the prior pause-and-wait pattern. Cost of reversal scales with how many autonomous decisions have been documented at the time of reversal — those decisions remain valid (the work happened) but the process governing them stops.

For partial reversal (e.g., "I want pre-emptive queues but not Layer 2 autonomous proceed"): scope-down this ADR by editing it, document the scope-down in a follow-up ADR. Same single-revert cost; more nuanced outcome.

## Implementation

Operationalized starting immediately by:

1. **`docs/decisions/queued-tranche-1.5.md`** — the inaugural decision queue, surfacing all pre-emptively-identified decisions for Tranches C, D, E, F, G.
2. **`docs/decisions/NNN-*.md`** — Layer 2 ADRs authored as mid-execution decisions arise.
3. **Final-summary template** — every session summary going forward includes the "Decisions made autonomously" section (this very response will be the first instance once the dispatch round closes).
4. **Updates to `~/.claude/rules/planning.md`** — extend the Tier 1/2/3 mid-build protocol with the explicit "proceed-with-recommendation" path for reversible decisions and the mandatory documentation requirement. Lands in Tranche A's incentive-redesign work or as an in-flight scope update of Tranche 1.5.

## Cross-references

- **Existing protocol this extends:** `~/.claude/rules/planning.md` Tier 1 / 2 / 3 mid-build decision framework
- **Working pattern context:** user's full-auto + minimize-friction directives shipped 2026-05-03 (memory: `feedback_full_auto_deploy.md`)
- **Companion to:** ADR 026 (harness catches up to doctrine) — same session, same architectural-redesign arc; ADR 026 establishes the structural precedent, ADR 027 establishes the procedural one
- **Operationalized first by:** `docs/decisions/queued-tranche-1.5.md` (decision queue for Tranches C-G)
- **Final-summary discipline:** every Claude response that wraps an autonomous-work block includes the "Decisions made autonomously" section per Layer 4
