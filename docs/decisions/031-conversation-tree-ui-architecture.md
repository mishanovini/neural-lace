# ADR 031 — Conversation Tree Management UI: Architecture

**Date:** 2026-05-15
**Status:** Proposed — pending stakeholder (Misha) decision
**Stakeholders:** Misha (decision authority — per the Tier-5 work-sizing rubric the architecture choice is non-delegable and AI participates as sounding-board only); future build-session orchestrators (downstream consumers of the decided design).

**Revision r2 (2026-05-15):** hardened after `systems-designer` Phase-3 FAIL (4 findings). Changes are honest restatement of what Option 4 delivers in v1, not a re-decision — the Option-4 recommendation is unchanged. See `## Phase-3 review hardening` near the end.

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
- **It preserves an upgrade path (cost corrected r2, Finding 3 — not free).** If Misha later runs local/Remote-Control sessions, the documented Channels bridge can be layered on for true live "focus node X" control (Option 3). This is **a transport change PLUS a snapshot→real-time state-layer upgrade** — it re-opens PRD OQ-1 (per-field conflict unit), OQ-2 (snapshot→real-time, which v1 deliberately resolves to *snapshot*), and NFR-4 (the 1 s snapshot budget becomes the 250 ms real-time budget). The JSON-state *schema* is reused; the *concurrency model* is rebuilt. The upgrade is contained (one option's worth of work, not a rewrite) but it is not "transport-only," and the Phase-4 plan must not assume it is.

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
- **Why not v1, why the upgrade path:** Ruled out for Misha's current cloud-Dispatch usage. **This is the recommended v1→v2 upgrade target**: if Misha moves to local/Remote-Control sessions, Option 3 layers onto Option 4's state *schema* — but as a snapshot→real-time concurrency-model rebuild (re-opening OQ-1/OQ-2/NFR-4), not a transport-only swap (corrected r2, Finding 3).

### Option 4 — Tree-as-durable-state + fire-and-forget Dispatch (recommended)
- **What:** The GUI is the durable tree/decision/action state layer, not a live control surface. Dispatch sessions read/write the JSON tree state via the existing `spawn-task-report-back.md` convention (sentinel + JSON result + SessionStart surfacer). "Continue at a node" spawns a *new* Dispatch session bound to that node; questions from running sessions surface as child nodes via the report-back surfacer.
- **Pro:** Survives the hard constraint (no live cloud control needed); reuses an existing harness convention *for the Dispatch→GUI direction*; minimally coupled and genuinely optional; upgrade path to Option 3 (cost honestly stated below — it is not free).
- **Con (corrected r2, Finding 1 — directionality):** `spawn-task-report-back.md` is **one-directional** (spawned session → orchestrator, via a result JSON + `.acked` marker). It satisfies **only the Dispatch→GUI half of PRD FR-11**. The **GUI→Dispatch half** (Misha edits the JSON; a running Dispatch session picks it up) is **NOT provided by the convention and is NOT a new live mechanism in v1** — a running *cloud* Dispatch session cannot read a mid-run external file write (no inbound port, no MCP). In v1, Misha's GUI edits to the tree state are **reconciled at the next session spawn**: the edited state becomes part of the next bound session's context/prompt, not consumed by an in-flight session. **PRD FR-11's "bidirectional, concurrent" property, Scenario 8 (concurrent same-file co-edit by a *running* session), and NFR-2's live "Dispatch also changed this" notice are explicitly scoped OUT of v1** and must be re-stated as v1-deferred in the Phase-4 plan (this is the FR-2-style finding the plan must resolve). Co-edit safety in v1 reduces to: GUI is the only live writer; Dispatch writes only at its own session boundaries (report-back); the two never write the same file concurrently because they are never live at the same time against it.
- **Con (Finding 2 — Scenario 3):** "continue at a node" is *spawn a fresh bound session*, not *inject into a live one*. Per-scenario behavior is tabulated in `## Phase-3 review hardening` below; the one scenario this degrades is **Scenario 3 when a Dispatch session is already live elsewhere** — clicking a cold branch then spawns a *concurrent* bound session rather than focus-switching the running one. Misha must accept this v1 limitation knowingly; it is the direct, unavoidable consequence of the cloud-Dispatch hard constraint, not an implementation shortcut.

## Consequences

- **Enables:** A v1 that works with Misha's actual (cloud Dispatch) workflow without a billing/auth/UX regression. The Phase-4 plan decomposes Option 4 into Tier 1–4 units: JSON state schema (Tier 4 — it is a contract; resolves PRD OQ-1/OQ-4), the tree GUI (Tier 3, new UI surface → `ux-designer` review), the Dispatch report-back integration (Tier 3, reuses `spawn-task-report-back.md`), the optional enable/disable seam (Tier 2, PRD FR-16/SM-5).
- **Costs:** No live mid-session control in v1 (accepted, by the hard constraint). The session-JSONL transcript format, if Option 3 is later adopted, is undocumented/unversioned — that drift risk is *deferred*, not incurred, in v1.
- **Blocks / sequencing:** The JSON-state-schema decision (PRD OQ-1 conflict unit, OQ-4 action-item typing) is itself a contract → it gets its own ADR (proposed ADR-032) authored alongside the Phase-4 plan, OR is folded into this ADR's adopted form if Misha prefers one record. Flagged as Phase-0 Decision B; recommendation: separate ADR-032, since the state schema is independently load-bearing and consumed by every component.
- **Non-negotiable constraint ADR-032 must honor (added r2, Finding 4):** Option 4's recommendation rests on **one** schema property even though the full schema is deferred — the tree state must have **independently-addressable, per-field-mergeable nodes** (each node's mutable fields — checked-state, parent-ref, tags, deferral-condition — addressable and last-write-wins-mergeable without rewriting a parent subtree). If ADR-032 lands a per-subtree or whole-document conflict unit instead, Option 4's "GUI is the only live writer, reconcile at next spawn" co-edit story degrades (a next-spawn reconciliation that must merge whole subtrees is materially harder than merging fields). ADR-032 may decide everything else freely; this one property is a fixed input from this ADR, not an open question. The architecture decision is separable from the schema only with this property pinned.
- **One-PRD-convention deviation (PRD OQ-9 / Phase-0 Decision A):** This module's PRD lives at `docs/prd-conversation-tree.md`, not `docs/prd.md`. Recorded here as a deliberate, reversible deviation: neural-lace is a harness repo whose own work uses the `prd-ref: n/a — harness-development` carve-out and has no single product PRD; an optional module warrants honest artifact naming over gaming the one-PRD path so the shape-gate auto-fires. Substance review was performed by the `prd-validity-reviewer` agent (the load-bearing gate). Reversible: Misha may redirect to `docs/prd.md`.

## Phase-3 review hardening

`systems-designer` returned **FAIL** on r1 with 4 class-aware findings (2 blocking, 2 hardening). Per the Tier-5 rubric the review hardens the option analysis before adoption; the Option-4 recommendation was found sound and is unchanged. Resolution:

| Finding | Class | Resolution in r2 |
|---|---|---|
| 1 (BLOCKING) | `convention-reuse-claim-without-contract-match` | Option-4 entry rewritten: report-back satisfies **only** FR-11's Dispatch→GUI half; GUI→Dispatch is **next-spawn-reconciled, not live**; FR-11-bidirectional / Scenario-8-concurrent / NFR-2-live-notice explicitly **scoped OUT of v1** and handed to the Phase-4 plan to re-state as v1-deferred. |
| 2 (BLOCKING) | `scenario-shape-asserted-in-aggregate-not-per-scenario` | Per-scenario table added (below). The blanket "scenarios are boundary-shaped" claim is removed; Scenario 3's degraded v1 behavior is stated explicitly for Misha to accept knowingly. |
| 3 | `upgrade-path-cost-understated-by-ignoring-deferred-OQs` | Upgrade path restated as transport change **plus** snapshot→real-time concurrency-model rebuild (re-opens OQ-1/OQ-2/NFR-4). No longer sold as "transport-only." |
| 4 | `contract-deferral-when-architecture-depends-on-the-contract` | One pinned constraint added to Consequences: ADR-032's schema **must** provide independently-addressable per-field-mergeable nodes. Everything else in the schema stays deferred. |

### Per-scenario behavior under Option 4 v1 (Finding 2 required fix)

| PRD scenario | Boundary-shaped? | Needs live control? | Option-4 v1 behavior |
|---|---|---|---|
| S1 — request branches, branches persist | Yes | No | Dispatch report-back writes branches at session end; GUI shows them next open. ✅ full |
| S2 — "what's waiting on me?" decision list | Yes | No | List built from durable tree state; answering writes GUI-side, folded into next bound spawn. ✅ full |
| S3 — click cold branch & continue | **Mixed** | **Yes IF a session is live elsewhere** | If no session live: spawn a fresh session bound to the node — clean. **If a session IS live elsewhere: a concurrent bound session is spawned, NOT a focus-switch of the running one.** ⚠️ degraded — Misha must accept knowingly. |
| S4 — branch auto-collapse on complete | Yes | No | Checklist state in durable tree; collapse is pure GUI. ✅ full |
| S5 — agree/disagree on check-off | Yes | No | Contested state stored in tree; Dispatch's side written at report-back, Misha's live in GUI; reconciled at next spawn. ✅ full (contested-state surfaced; not live cross-talk) |
| S6 — conclude branch, kick off session | Yes | No | This IS the Option-4 native path (spawn bound session from gathered decisions). ✅ full, native |
| S7 — defer my action with condition | Yes | No | Pure GUI/tree-state operation; no Dispatch involvement. ✅ full |
| S8 — Dispatch writes while Misha edits | **N/A in v1** | — | Explicitly OUT of v1 (Finding 1): GUI and a *running cloud* session are never live writers to the same file simultaneously, so the concurrent-co-edit case does not arise. v2 (Option 3) re-introduces it. |

Net: 6 of 8 scenarios fully delivered in v1; S3 degraded (concurrent-spawn, stated); S8 deferred by construction (stated). Misha's decision is now informed about exactly what v1 delivers.

## Cross-references

- PRD: `docs/prd-conversation-tree.md` (OQ-8 = this decision; OQ-1/OQ-4 → proposed ADR-032; OQ-9 = the deviation recorded above).
- Convention reused by Option 4: `~/.claude/rules/spawn-task-report-back.md`.
- Research provenance: two read-only research agents, 2026-05-15 — Agent SDK capability profile + desktop/Dispatch external-bridge investigation. Key external sources cited inline (`code.claude.com/docs/en/channels-reference`, `/remote-control`, `/desktop`, `/agent-sdk/overview`; `platform.claude.com/docs/en/managed-agents/sessions`; GitHub anthropics/claude-code #53049, #35072, #17188).
- Work-sizing basis: `build-doctrine/doctrine/03-work-sizing.md` (Tier-5: ADR is the deliverable; decision gated by stakeholder acceptance).
- Phase-3 gate: `systems-designer` adversarial review of this option space before adoption (pending).
