# ADR 031 — Conversation Tree Management UI: Architecture

**Date:** 2026-05-15
**Status:** Proposed — pending stakeholder (Misha) decision
**Stakeholders:** Misha (decision authority — per the Tier-5 work-sizing rubric the architecture choice is non-delegable and AI participates as sounding-board only); future build-session orchestrators (downstream consumers of the decided design).

> **Tier-5 framing.** Per `build-doctrine/doctrine/03-work-sizing.md`, introducing an architectural pattern not in canon is Tier-5 work whose deliverable is *this decision + record*, not code. The decision is gated by stakeholder acceptance, not mechanical checks. Implementation decomposes into Tier 1–4 work against the decided design (the Phase 4 plan). This ADR **proposes** a recommendation; Misha decides.

## Context

The Conversation Tree Management UI (PRD: `docs/prd-conversation-tree.md`, passed Phase-2 substance review at 8b1453e) is an optional harness module that makes the Misha↔Dispatch conversation *tree* durable, visible, and navigable. The load-bearing open question (PRD OQ-8) is the architecture: the GUI ultimately wants to *be* the chat surface, because "click a node and continue" only works cleanly if the chat lives where the tree lives. Three options were posed; evidence-based research (two read-only research agents, 2026-05-15) re-shaped the option space and produced a fourth.

### Hard constraint that drives the decision

**Misha drives work through Dispatch — cloud/remote Claude Code sessions monitored from a phone/web, not local terminal sessions.** The desktop-bridge research is decisive here:

- An external GUI **can** observe a *local / Remote-Control* desktop session (tail the session JSONL transcript at `~/.claude/projects/<slug>/<uuid>.jsonl`; production tools already do this) and **can** inject input via **Channels** — a *documented, supported* MCP-broker mechanism (Claude Code v2.1.80+, research preview) where an MCP server binds a localhost port and forwards external POSTs into the running session. Source: `https://code.claude.com/docs/en/channels-reference`.
- An external GUI **cannot** observe or control a true **cloud / Dispatch** session. Remote Control is API-relayed with **no inbound port and no documented third-party API**; cloud sessions **cannot load MCP/plugins**, so the Channels bridge does not apply. The Managed-Agents Sessions API (`POST /v1/sessions`) is a *different product* (your own API-key cloud sessions), not a handle on the user's existing Dispatch conversation. Sources: `https://code.claude.com/docs/en/remote-control`, `https://code.claude.com/docs/en/desktop`, `https://platform.claude.com/docs/en/managed-agents/sessions`. GitHub: external-inject requests #53049 (closed-duplicate) and #35072 (open, no Anthropic resolution).

So any architecture that depends on *live observation/control of a running cloud Dispatch session from an external GUI is ruled out on current evidence.* This single fact eliminates the naive form of two of the three original options for Misha's actual usage pattern.

### Agent SDK research (the Option-1 substrate)

The Claude Agent SDK (Python + TS) provides every orchestration primitive first-class: the autonomous tool-use loop, sub-agents, ~18 lifecycle hooks, MCP, session resume/fork, streaming-input with `interrupt()`, and a `SessionStore` adapter that is a clean near-real-time event tap for an external observer. Official prior art exists (`anthropics/claude-agent-sdk-demos`: a ~27 KB React/WS chat UI; a Python multi-agent orchestrator). **But:** building on the SDK means re-implementing the product shell (chat UI, permission UX, durable persistence) and — critically — **Dispatch is not in the SDK at all** (the phone↔desktop remote-orchestration layer is a desktop/Cowork product feature). Commercial: from 2026-06-15, SDK usage draws a **separate metered Agent SDK credit** and **claude.ai-login auth is not permitted for third-party agents — API-key only** (`https://code.claude.com/docs/en/agent-sdk/overview`). Building on the SDK therefore changes Misha's billing and auth model and forfeits the Dispatch UX he relies on. There is **no out-of-process mid-run control channel**: to steer an SDK agent the GUI must *be* the `query()` host process.

## Decision (proposed)

**Recommend Option 4 — Tree-as-durable-state + fire-and-forget Dispatch via the existing report-back convention — for v1, with a documented upgrade path to Option 3 (Channels live-control) gated on Misha adopting local/Remote-Control sessions.**

Rationale, by principle:

- **It is the only option that survives the hard constraint.** Misha uses cloud Dispatch; Options 2 and 3 are ruled out there, and Option 1 forces abandoning Dispatch + a billing/auth regression. Option 4 does not require live control of a running cloud session — it does not exist to inject into a live session at all.
- **It reuses an existing harness convention rather than inventing one.** The harness already ships `~/.claude/rules/spawn-task-report-back.md`: a sentinel + JSON-result + SessionStart-surfacer convention by which a spawned session reports structured results back to an orchestrator. The tree's JSON state file becomes the durable substrate; Dispatch sessions read/write it via this convention. "Click node to continue" = the GUI composes a prompt from the node's gathered decisions and **spawns a new Dispatch session bound to that node** (PRD FR-14/FR-19), not "inject into a live session."
- **It honors the PRD's optionality and counterbalancing metrics.** Option 4 introduces no required hook in the core chains and no always-on friction (PRD SM-5/SM-6, NFR-8); it is genuinely disable-able.
- **It preserves a clean upgrade path.** If Misha later runs local/Remote-Control sessions, the documented Channels bridge can be layered on for true live "focus node X" control (Option 3) **without rearchitecting the state layer** — the JSON-state substrate is identical; only the transport changes from spawn-a-session to inject-into-session.

Option 1 (own-the-orchestrator) is the long-horizon "perfect integration" play and is explicitly **not rejected forever** — it is deferred as a potential v2+ once the tree-state model has proven itself, because it is a materially larger separate project with a billing/auth/UX cost the PRD's counterbalancing metrics argue against for v1.

**This recommendation is proposed, not adopted. Misha decides.** If he prefers Option 1's perfect integration and accepts the Dispatch/billing/auth cost, or wants to move to local sessions to unlock Option 3 live-control in v1, the plan (Phase 4) is authored against his decision, not this recommendation.

## Alternatives considered

### Option 1 — Custom GUI = full chat replacement on the Claude Agent SDK
- **What:** Build the chat+tree GUI as a custom orchestrator hosting `query()`. The GUI *is* the agent host, so the tree is authored from inside your own loop — perfect, lossless integration.
- **Pro:** Highest integration payoff; the tree model and the agent loop are one program; live "click node to continue" is trivially native because there is no external process to bridge to.
- **Con (research-grounded):** Re-implements the entire product shell (UI, permission UX, durable persistence via a hand-written `SessionStore` + DB). **Loses Dispatch entirely** (not in the SDK — the phone/remote orchestration Misha relies on does not exist here). **Changes billing + auth** (metered Agent SDK credit from 2026-06-15; API-key auth, not the claude.ai subscription). Largest build; an ongoing maintenance liability (a Dispatch replacement, forever).
- **Why not now:** Disproportionate for v1 against PRD SM-5/SM-6 (optionality, no-new-friction). Deferred as a possible v2+, not rejected.

### Option 2 — Custom GUI = parallel observer alongside the desktop app
- **What:** GUI observes by tailing session JSONL; relays follow-ups via a Channels MCP server. Two loosely-coupled interfaces.
- **Research verdict:** **VIABLE for local / Remote-Control desktop sessions only; RULED OUT for cloud Dispatch** (no inbound port, no third-party API, no MCP in cloud sessions). Transcript format is undocumented/unversioned (drift risk).
- **Why not:** Misha drives via cloud Dispatch, where this is ruled out. Only viable if Misha abandons cloud Dispatch for local sessions — a UX regression the PRD does not ask for.

### Option 3 — Hybrid: GUI as control surface for Dispatch via a bridge
- **What:** Tree + lists in the GUI; chat input still in the desktop app; GUI sends "focus node X" to the running session through the **Channels** documented bridge.
- **Research verdict:** **VIABLE — and a documented first-class pattern, not a hack — for local / Remote-Control desktop sessions; RULED OUT for cloud Dispatch** (same reason as Option 2). Caveats: Channels is research-preview; custom channels need `--dangerously-load-development-channels` or marketplace approval; injected input enters as a queued turn, not a true mid-turn interrupt (#35072 still open).
- **Why not v1, why the upgrade path:** Ruled out for Misha's current cloud-Dispatch usage. **This is the recommended v1→v2 upgrade target**: if Misha moves to local/Remote-Control sessions, Option 3 layers onto Option 4's state substrate with only a transport change.

### Option 4 — Tree-as-durable-state + fire-and-forget Dispatch (recommended)
- **What:** The GUI is the durable tree/decision/action state layer, not a live control surface. Dispatch sessions read/write the JSON tree state via the existing `spawn-task-report-back.md` convention (sentinel + JSON result + SessionStart surfacer). "Continue at a node" spawns a *new* Dispatch session bound to that node; questions from running sessions surface as child nodes via the report-back surfacer.
- **Pro:** Survives the hard constraint (no live cloud control needed); reuses an existing harness convention; minimally coupled and genuinely optional; clean upgrade path to Option 3.
- **Con:** No live mid-session steering — "continue at a node" is *spawn a fresh bound session*, not *inject into the live one*. Latency/observation is at session boundaries (PRD OQ-2 leans snapshot for exactly this reason). Acceptable for v1 by construction; the PRD's scenarios are session-boundary-shaped, not live-injection-shaped.

## Consequences

- **Enables:** A v1 that works with Misha's actual (cloud Dispatch) workflow without a billing/auth/UX regression. The Phase-4 plan decomposes Option 4 into Tier 1–4 units: JSON state schema (Tier 4 — it is a contract; resolves PRD OQ-1/OQ-4), the tree GUI (Tier 3, new UI surface → `ux-designer` review), the Dispatch report-back integration (Tier 3, reuses `spawn-task-report-back.md`), the optional enable/disable seam (Tier 2, PRD FR-16/SM-5).
- **Costs:** No live mid-session control in v1 (accepted, by the hard constraint). The session-JSONL transcript format, if Option 3 is later adopted, is undocumented/unversioned — that drift risk is *deferred*, not incurred, in v1.
- **Blocks / sequencing:** The JSON-state-schema decision (PRD OQ-1 conflict unit, OQ-4 action-item typing) is itself a contract → it gets its own ADR (proposed ADR-032) authored alongside the Phase-4 plan, OR is folded into this ADR's adopted form if Misha prefers one record. Flagged as Phase-0 Decision B; recommendation: separate ADR-032, since the state schema is independently load-bearing and consumed by every component.
- **One-PRD-convention deviation (PRD OQ-9 / Phase-0 Decision A):** This module's PRD lives at `docs/prd-conversation-tree.md`, not `docs/prd.md`. Recorded here as a deliberate, reversible deviation: neural-lace is a harness repo whose own work uses the `prd-ref: n/a — harness-development` carve-out and has no single product PRD; an optional module warrants honest artifact naming over gaming the one-PRD path so the shape-gate auto-fires. Substance review was performed by the `prd-validity-reviewer` agent (the load-bearing gate). Reversible: Misha may redirect to `docs/prd.md`.

## Cross-references

- PRD: `docs/prd-conversation-tree.md` (OQ-8 = this decision; OQ-1/OQ-4 → proposed ADR-032; OQ-9 = the deviation recorded above).
- Convention reused by Option 4: `~/.claude/rules/spawn-task-report-back.md`.
- Research provenance: two read-only research agents, 2026-05-15 — Agent SDK capability profile + desktop/Dispatch external-bridge investigation. Key external sources cited inline (`code.claude.com/docs/en/channels-reference`, `/remote-control`, `/desktop`, `/agent-sdk/overview`; `platform.claude.com/docs/en/managed-agents/sessions`; GitHub anthropics/claude-code #53049, #35072, #17188).
- Work-sizing basis: `build-doctrine/doctrine/03-work-sizing.md` (Tier-5: ADR is the deliverable; decision gated by stakeholder acceptance).
- Phase-3 gate: `systems-designer` adversarial review of this option space before adoption (pending).
