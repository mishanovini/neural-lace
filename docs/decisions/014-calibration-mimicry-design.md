# Decision 014 — Calibration mimicry design (G-1 through G-4)

**Date:** 2026-05-03
**Status:** Active
**Stakeholders:** Misha (sole maintainer)
**Related plan:** `docs/plans/archive/phase-1d-g-calibration-mimicry.md` (Status: DEFERRED — depends on telemetry + findings-ledger)
**Related backlog:** HARNESS-GAP-11 (reviewer accountability one-way) — this decision package operationalizes the gap's proposed mechanism

## Context

The harness has a structural reviewer-accountability gap (HARNESS-GAP-11): when a reviewer agent (`task-verifier`, `harness-reviewer`, `end-user-advocate`, etc.) PASSes work that subsequently fails at runtime or in production, no signal flows back to the reviewer for calibration. Each reviewer's incentive to be careful is purely intrinsic; over time this creates calibration drift.

The user surfaced (2026-05-03) the meta-architectural question: "Show me the incentive and I'll show you the outcome — applied to AI agents." The reactive `diagnosis.md` "After Every Failure: Encode the Fix" loop catches strays one at a time. A proactive layer would pre-empt them.

True RL-shaped feedback (weight updates from a reward signal) requires fine-tuning, which the user explicitly rejected. The alternative: external feedback loop that tracks each agent's calibration, injects the calibration profile into the agent's prompt at invocation time, and applies structural consequences (auto-downgrade, replacement) when calibration drifts. Not RL, but RL-shaped behavior via prompt conditioning.

## Decisions

### G-1 — Approximation acceptable; no fine-tuning

**Decision.** Implement calibration mimicry via prompt conditioning + external feedback loop. No fine-tuning of any model. The mechanism produces calibration adjustment via injected prompts plus structural consequences (auto-downgrade), NOT via weight updates.

**Reasoning.** Cheaper, faster iteration; no API-level fine-tuning dependency; works on Claude Code's existing inference surface. The approximation is meaningfully different from RL (no consequence-fear; only context-conditioning) but produces RL-shaped outcomes empirically — well-calibrated prompts produce better-calibrated outputs.

**Confirmed by user 2026-05-03:** "I'm not going to fine-tune any models."

### G-2 — Scope: high-stakes agents first

**Decision.** Initial agents under calibration tracking: `task-verifier`, `harness-reviewer`, `end-user-advocate` (runtime mode). Expansion based on empirical drift evidence. Lower-stakes agents (`explorer`, `research`) deferred indefinitely unless evidence justifies.

**Reasoning.** Lowest-risk-highest-leverage start. The three named agents make verdicts that gate work landing or shipping; their calibration matters most. Expanding to 17 agents from day one would dilute attention and produce noisy calibration data on agents whose verdicts don't materially affect outcomes.

**Confirmed by user 2026-05-03:** agreement with recommendation.

### G-3 — Visibility: all three channels

**Decision.** Three channels: (a) internal-to-NL state at `~/.claude/state/agent-calibration/<agent-name>.jsonl`; (b) agents-see-it via injected calibration profiles in their prompts at invocation time; (c) public visibility via `docs/agent-calibration.md` regenerated weekly.

**Reasoning.** Each channel serves a distinct purpose. Internal state is the durable data substrate; agents-see-it is the load-bearing channel for calibration to actually influence behavior (this is what mimics RL); public visibility lets the user observe drift and amend mechanism design. Removing any channel breaks the loop — without internal state there's nothing to inject; without agents-see-it the calibration data never affects behavior; without public visibility drift goes undetected.

**Confirmed by user 2026-05-03:** "Agreed. All three."

### G-4 — Dashboard surface (eventual expansion)

**Decision.** A dashboard surface for harness calibration AND additional harness-stats per project is desired by the user. Specific format/tooling deferred. Sub-phase 1d-G-3 includes a static-HTML MVP at `docs/dashboard.html`; full expansion (interactive, real-time, per-project breakdown) is its own future phase.

**Reasoning.** Captures forward-looking scope without locking implementation details. A static HTML page generated from state files is the cheapest viable form; that ships in 1d-G-3. Full dashboard work is its own substantial effort that warrants its own plan once we have empirical data on what stats matter.

**Confirmed by user 2026-05-03:** "I'll probably want a dashboard for easy visibility that will eventually expand to provide additional stats about the harness in each project."

## Alternatives considered (and rejected)

- **Fine-tuning specialized models per agent role.** Rejected by G-1. Heavyweight, requires API support for fine-tuning, ongoing data-collection and re-training overhead. The prompt-conditioning approximation captures most of the benefit at a fraction of the cost.
- **Track all 17 agents from day one.** Rejected by G-2. Dilutes attention; calibration thresholds would need per-agent tuning that we can't do without empirical data we don't have yet.
- **Internal-state only, no agents-see-it.** Rejected by G-3. Would produce a measurement-without-feedback system. The agents-see-it channel is what makes the calibration data influence behavior — without it the system is observability without effect.
- **Skip the dashboard.** Rejected by G-4. The user explicitly wants the visibility surface.

## Consequences

**Enables:**
- Reviewer accountability mechanism that doesn't require human review of every reviewer verdict.
- Cross-session calibration data accumulating per agent — empirical evidence for future mechanism design.
- Dashboard expansion path (sub-phase 1d-G-3 ships MVP; full dashboard is its own phase).

**Costs:**
- Latency overhead per agent invocation (the calibration injector reads state and constructs prompt; ~50-200ms typical).
- Storage: JSONL files at `~/.claude/state/agent-calibration/` will grow over time; need periodic archival (weekly rolling window).
- Auto-downgrade may produce false-negatives — an agent's verdict mechanically downgraded when the verdict was actually correct. Mitigation: per-agent override file; recalibration via 3 consecutive agreed verdicts.

**Blocks:**
- The calibration-mimicry plan (Phase 1d-G) cannot execute until telemetry (HARNESS-GAP-10 sub-gap D, 2026-08 target) AND findings-ledger schema gate (C9, Phase 1d-C-3) ship.

## Implementation status

Plan deferred. Decision record committed today as the durable artifact. When dependencies ship, the plan transitions from `Status: DEFERRED` → `Status: ACTIVE` and execution begins per its sub-phase breakdown (1d-G-1 tracking → 1d-G-2 injector → 1d-G-3 scoreboard + dashboard MVP).

## Cross-references

- `docs/plans/archive/phase-1d-g-calibration-mimicry.md` — full plan with task-level breakdown
- `docs/agent-incentive-map.md` — the proactive layer this decision builds on
- `docs/backlog.md` HARNESS-GAP-11 — the gap this decision package addresses
- `docs/discoveries/2026-05-03-agent-incentive-map-as-proactive-layer.md` — the originating architectural learning
