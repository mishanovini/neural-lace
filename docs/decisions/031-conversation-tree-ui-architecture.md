# ADR 031 — Conversation Tree Management UI: Architecture

**Date:** 2026-05-15
**Status:** Proposed — pending stakeholder (Misha) decision
**Stakeholders:** Misha (decision authority — per the Tier-5 work-sizing rubric the architecture choice is non-delegable and AI participates as sounding-board only); future build-session orchestrators (downstream consumers of the decided design).

**Revision r2 (2026-05-15):** hardened after `systems-designer` Phase-3 FAIL (4 findings). Changes were honest restatement of what Option 4 delivered in v1, not a re-decision. (Superseded by r3 — see below. The r2 Phase-3 hardening section is retained near the end as a historical audit record; its Option-4-specific per-scenario table is obsolete.)

**Revision r4 (2026-05-16) — ALL THREE OPTIONS GENUINELY LIVE; r3 LEAN DOWNGRADED.** During Stage C Misha pushed back on r3's framing: he disagreed that "GUI as an overlay / abstraction layer on top of Dispatch" disqualifies or pre-orders the options, and stated Option 1 is back in full contention. r4 therefore **downgrades the r3 Option-1 recommendation from "recommended-pending" to "leading candidate, not settled"** and restores Options 1, 2, 3 as **equally live pending the fresh `systems-designer` pass** (still deferred to post-Stage-F). The r3 analysis is retained below as input, but its "why not 2 or 3" section is explicitly **no longer a settled conclusion** — Misha's overlay framing (*"an abstraction layer on top of dispatch … although I also see dispatch already as an abstraction layer on top of Claude code"*) means an overlay/observer posture is NOT inherently disqualifying, which reopens 2 and 3 on their merits. No option is eliminated at r4; the decision stays open for the post-Stage-F architecture pass.

**Revision r3 (2026-05-15) — STAKEHOLDER STRUCK OPTION 4.** During the interactive PRD intake (Stage B convergence) Misha directed verbatim: *"let's remove (ADR-031): Option 4."* Option 4 is removed from the option space entirely. The architecture choice is now strictly **Option 1 vs Option 2 vs Option 3**. Misha also supplied a new hard input verbatim: *"I'm picturing this in my mind as an abstraction layer on top of dispatch … ideally this UI would essentially just be built into dispatch. but I'm also open to reconsidering if there might be a better way to do this."* r3 reworks Decision / Alternatives / Consequences around the surviving three options + this ideal, and folds in the Stage-A/B PRD scope expansion (backlog manager + partial-answer parallelization) and the NFR-11 persistence hard constraint as binding inputs. r3 changes the recommendation; a fresh `systems-designer` Phase-3 pass on r3 is required before this ADR can be considered adopted (deferred to the post-Stage-F reconciliation, since the PRD intake is still in progress — this ADR remains parked/provisional until then).

> **Tier-5 framing.** Per `build-doctrine/doctrine/03-work-sizing.md`, introducing an architectural pattern not in canon is Tier-5 work whose deliverable is *this decision + record*, not code. The decision is gated by stakeholder acceptance, not mechanical checks. Implementation decomposes into Tier 1–4 work against the decided design (the Phase 4 plan). This ADR **proposes** a recommendation; Misha decides.

## Context

The Conversation Tree Management UI (PRD: `docs/prd.md`, passed Phase-2 substance review at 8b1453e; materially expanded during the interactive Stage-A/B intake to also be a **backlog/to-do surface for not-yet-started Claude-Code work** and to require **partial-answer parallelization** and **NFR-11 persistence/continuity** as a hard constraint) is an optional harness module that makes the Misha↔Dispatch conversation *tree* — and the backlog feeding it — durable, visible, and navigable. The load-bearing open question (PRD OQ-8) is the architecture. r1/r2 considered four options and recommended Option 4; **r3 records the stakeholder striking Option 4**, leaving Option 1 / 2 / 3, weighed against a new stakeholder-supplied ideal (below). Evidence base: two read-only research agents, 2026-05-15 (Agent SDK capability profile + desktop/Dispatch external-bridge investigation).

### Hard constraint that drives the decision

**Misha drives work through Dispatch — cloud/remote Claude Code sessions monitored from a phone/web, not local terminal sessions.** The desktop-bridge research is decisive here:

- An external GUI **can** observe a *local / Remote-Control* desktop session (tail the session JSONL transcript at `~/.claude/projects/<slug>/<uuid>.jsonl`; production tools already do this) and **can** inject input via **Channels** — a *documented, supported* MCP-broker mechanism (Claude Code v2.1.80+, research preview) where an MCP server binds a localhost port and forwards external POSTs into the running session. Source: `https://code.claude.com/docs/en/channels-reference`.
- An external GUI **cannot** observe or control a true **cloud / Dispatch** session. Remote Control is API-relayed with **no inbound port and no documented third-party API**; cloud sessions **cannot load MCP/plugins**, so the Channels bridge does not apply. The Managed-Agents Sessions API (`POST /v1/sessions`) is a *different product* (your own API-key cloud sessions), not a handle on the user's existing Dispatch conversation. Sources: `https://code.claude.com/docs/en/remote-control`, `https://code.claude.com/docs/en/desktop`, `https://platform.claude.com/docs/en/managed-agents/sessions`. GitHub: external-inject requests #53049 (closed-duplicate) and #35072 (open, no Anthropic resolution).

So any architecture that depends on *live observation/control of a running cloud Dispatch session from an external GUI is ruled out on current evidence.* **In r3 this finding cuts directly against Options 2 and 3** (both depend on observing/controlling a running Dispatch session — ruled out for Misha's cloud usage), and is neutral-to-favorable for Option 1 (which does not observe Dispatch — it *replaces* the orchestrator, so there is no external session to bridge to).

### Stakeholder-supplied ideal (r3 hard input) — "built into Dispatch"

Misha's stated ideal, verbatim: *"I'm picturing this in my mind as an abstraction layer on top of dispatch. although I also see dispatch already as an abstraction layer on top of Claude code. ideally this UI would essentially just be built into dispatch. but I'm also open to reconsidering if there might be a better way to do this."*

**Honest constraint: "built into Dispatch" is not buildable by us.** Dispatch is an Anthropic-owned product surface; we cannot modify it, embed into it, or ship a native Dispatch feature. So the literal ideal is unreachable, and the ADR must say so plainly rather than imply otherwise. The decision therefore becomes: **which of Options 1/2/3 most closely *approximates* "the tree management is just part of how I drive Claude Code," and at what cost?** Two evaluation axes follow from his framing:

- **Approximation of "built-in":** does the option make the tree feel like an intrinsic part of the driving surface (one place), or a separate bolted-on tool (two places)?
- **What it loses vs. desktop Dispatch's existing features**, and **what it gains in built-in tree/backlog management** — weighed explicitly per option below.

NFR-11 (persistence/continuity — no user-visible session boundary, seamless continuation) is the sharpest test of "approximation of built-in": an option that cannot make session boundaries invisible cannot feel built-in, by construction.

### Agent SDK research (the Option-1 substrate)

The Claude Agent SDK (Python + TS) provides every orchestration primitive first-class: the autonomous tool-use loop, sub-agents, ~18 lifecycle hooks, MCP, session resume/fork, streaming-input with `interrupt()`, and a `SessionStore` adapter that is a clean near-real-time event tap for an external observer. Official prior art exists (`anthropics/claude-agent-sdk-demos`: a ~27 KB React/WS chat UI; a Python multi-agent orchestrator). **But:** building on the SDK means re-implementing the product shell (chat UI, permission UX, durable persistence) and — critically — **Dispatch is not in the SDK at all** (the phone↔desktop remote-orchestration layer is a desktop/Cowork product feature). Commercial: from 2026-06-15, SDK usage draws a **separate metered Agent SDK credit** and **claude.ai-login auth is not permitted for third-party agents — API-key only** (`https://code.claude.com/docs/en/agent-sdk/overview`). Building on the SDK therefore changes Misha's billing and auth model and forfeits the Dispatch UX he relies on. There is **no out-of-process mid-run control channel**: to steer an SDK agent the GUI must *be* the `query()` host process.

## Decision (open — r4 supersedes the r3 lean)

> **r4 status:** No option is recommended-settled. Options 1, 2, 3 are all genuinely live. The text below is the **r3 analysis, retained as input but downgraded** — Option 1 is a *leading candidate, not the decision*. Misha explicitly reopened 2 and 3 by rejecting the premise that an overlay/observer posture disqualifies them (he frames the whole product as "an abstraction layer on top of Dispatch," and notes Dispatch is itself an abstraction layer on top of Claude Code — so layering is the model, not a disqualifier). The architecture is decided at the post-Stage-F pass with a fresh `systems-designer` review, against the *fully expanded* PRD (backlog manager, multi-project + global tree, partial-answer parallelization, FR-24 persistence, symmetric interface).

**r3 analysis (retained, downgraded): Option 1 — a custom orchestrator built on the Claude Agent SDK that becomes Misha's "Dispatch++" for this work — is the closest *buildable* approximation of his "built into Dispatch" ideal.** It is a leading candidate, not a settled recommendation (r4).

The reasoning is forced by the combination of three r3 inputs that did not all exist when Option 4 was recommended:

1. **Option 4 is struck** (stakeholder directive) — it is no longer in the space.
2. **NFR-11 (persistence/continuity) is now a hard constraint.** No user-visible session boundary; seamless continuation; clicking a node to continue must not surface session-lifecycle UI or perceptible startup. An option that only *observes or bolts onto* a surface it does not own cannot make that surface's session boundaries invisible — it can hide its own UI but not the underlying app's. **Only the option that *owns the surface* can satisfy NFR-11.** Among 1/2/3, only Option 1 owns the surface.
3. **The "built into Dispatch" ideal** — unreachable literally (Anthropic owns Dispatch), but its *intent* is "one place, not a bolted-on second tool." Option 1 is the only one that is *one place*: the tree, the backlog, and the conversation live in the same program Misha drives. Options 2 and 3 are structurally *two places* (the tree tool beside the desktop app), which is the opposite of "built in."

The honest cost of Option 1 (unchanged from r1/r2, not minimized): it re-implements the product shell (chat UI, permission UX, durable persistence); it **forfeits desktop Dispatch's existing features** that are not re-built (phone/remote orchestration, the Cowork surface, push notifications, scheduled tasks, IDE integration); and it **changes the billing/auth model** (metered Agent SDK credit from 2026-06-15, API-key auth not the claude.ai subscription — `code.claude.com/docs/en/agent-sdk/overview`). r1/r2 treated these costs as disqualifying for v1; r3 does not, because Misha's own stated ideal is precisely "this *is* my Dispatch for this work," which means the Dispatch features Option 1 forfeits are largely the ones he is choosing to leave behind for this workflow, and the billing/auth change is a known consequence of that choice rather than an unaccepted side effect. That reframing is the stakeholder's to confirm — it is exactly the kind of cost the Tier-5 rubric says only the human can accept.

**Why not 2 or 3 (r3):** both depend on observing/controlling a *running* Dispatch session — research-ruled-out for Misha's cloud usage (no inbound port, no MCP/Channels in cloud sessions). Even setting cloud aside, both are structurally two-places and cannot satisfy NFR-11 for the surface they don't own. They remain the lower-build-cost options but they cannot deliver the thing Misha actually asked for ("built in," seamless, one place).

**This is proposed, not adopted (Tier-5 — Misha decides), and r3 has not yet been adversarially re-reviewed.** Concrete decisions r3 still needs from Misha, surfaced honestly rather than assumed: (a) does he accept the billing/auth change and the loss of desktop-Dispatch features (phone-driving, Cowork, scheduled tasks) as the price of "one place"? (b) is "open to reconsidering if there might be a better way" an invitation to surface a *fifth* framing (e.g., not a chat replacement at all, but the tree/backlog as the primary surface that *launches* Dispatch sessions for the heavy work and only mirrors their outcomes — a narrower Option-1 variant that keeps Dispatch for execution while owning the tree/continuity layer)? r3 flags (b) as the most promising thing to explore before locking, because it may approximate "built in" without fully forfeiting Dispatch. This is not decided here.

## Alternatives considered

> **Option 4 — Tree-as-durable-state + fire-and-forget Dispatch — STRUCK by stakeholder directive at r3** (*"let's remove (ADR-031): Option 4"*). It is no longer in the option space. The r1/r2 analysis of Option 4, the Phase-3 hardening findings against it, and the Option-4 per-scenario table are retained only as a historical audit record in `## Phase-3 review hardening (HISTORICAL — r2, Option 4 struck)` below; none of it is load-bearing for the r3 decision.

The surviving option space is 1/2/3, each weighed against the "built into Dispatch" ideal (approximation of one-place) and NFR-11 (can session boundaries be made invisible?), with "what it loses vs desktop Dispatch" and "what it gains in built-in tree/backlog management" called out explicitly.

### Option 1 — Custom orchestrator on the Claude Agent SDK ("Dispatch++") — recommended r3
- **What:** Build the chat + tree + backlog as one program hosting the Agent SDK `query()` loop. The GUI *is* the orchestrator; the tree/backlog are authored from inside the loop. There is no external surface to bridge to.
- **Approximation of "built in": highest of the three.** One place — tree, backlog, conversation, continuity all in the program Misha drives. This is the only option that is not structurally "a second tool beside Dispatch."
- **NFR-11: satisfiable.** Because it owns the surface, it can make session boundaries invisible (no "resume," no perceptible startup, seamless continuation) — the only option that can.
- **Loses vs desktop Dispatch:** phone/remote driving, the Cowork surface, push notifications, scheduled tasks/Routines, IDE integration — anything Dispatch ships that Option 1 does not re-build. Plus skills/CLAUDE.md/MCP carry over (SDK loads `.claude/`), but the *product* shell does not.
- **Gains in built-in tree/backlog:** total — the tree model and the agent loop are the same program; partial-answer parallelization, backlog→session activation, and persistence are native, not bridged.
- **Cost (not minimized):** largest build (product shell + durable persistence + permission UX); a standing maintenance liability; **billing/auth change** (metered Agent SDK credit 2026-06-15, API-key auth not subscription). r3's stance: these costs are the stakeholder's to accept, and his stated ideal implies he may; r1/r2's "disqualifying for v1" judgment is explicitly revised, not silently dropped.

### Option 2 — Parallel observer alongside the desktop app
- **What:** GUI tails session JSONL to observe; relays follow-ups via a Channels MCP server. Two loosely-coupled interfaces.
- **Approximation of "built in": low.** Structurally two places — a tree tool beside Dispatch. The opposite of Misha's "one place" intent.
- **NFR-11: cannot satisfy.** It does not own Dispatch's surface, so it cannot hide Dispatch's session boundaries; "seamless continuation" is impossible when continuation happens in a different app it only observes.
- **Research verdict:** VIABLE for *local/Remote-Control* desktop sessions only; **RULED OUT for cloud Dispatch** (no inbound port, no MCP/Channels in cloud sessions) — i.e., ruled out for Misha's actual usage. Transcript format undocumented/unversioned (drift risk).
- **Loses vs desktop Dispatch:** nothing (Dispatch keeps running) — but **gains** only a read-mostly mirror + a relay; the tree is never the place work actually happens, so the "built-in" gain is minimal.

### Option 3 — Hybrid: GUI as control surface for Dispatch via a bridge
- **What:** Tree + backlog in the GUI; chat still in the desktop app; GUI sends "focus node X" via the Channels bridge.
- **Approximation of "built in": low-to-medium.** Still two places; the bridge makes it feel slightly more connected than Option 2 but the conversation surface is not owned.
- **NFR-11: cannot satisfy** for the same structural reason as Option 2 (does not own the surface where continuation happens).
- **Research verdict:** VIABLE as a *documented first-class pattern* for local/Remote-Control sessions; **RULED OUT for cloud Dispatch** (same reason). Channels is research-preview; injected input is a queued turn, not a true mid-turn interrupt (#35072 open).
- **Loses vs desktop Dispatch:** nothing; **gains** GUI-driven node-focus on a surface it doesn't own — better than Option 2's relay, still not "built in," still cloud-ruled-out for Misha.

## Consequences

- **Enables (if Option 1 is adopted):** the only buildable approximation of "one place" — tree + backlog + conversation + persistence in the program Misha drives; NFR-11 satisfiable; partial-answer parallelization and backlog→session activation native. The Phase-4 plan (currently parked, written against the struck Option 4) must be **re-authored against the adopted option**, not edited — it is now materially divergent (it assumed fire-and-forget report-back; Option 1 is an owned orchestrator with a fundamentally different state/continuity model).
- **Costs (if Option 1 is adopted, not minimized):** full product-shell rebuild + durable persistence + permission UX; forfeits desktop-Dispatch features not re-built (phone/Cowork/Routines/IDE); billing/auth model change (metered Agent SDK credit 2026-06-15, API-key auth). These are the costs the Tier-5 rubric reserves for the stakeholder to accept.
- **Open before adoption (r3):** the "narrower Option-1 variant" flagged in the Decision section (tree/backlog as the primary surface that *launches* Dispatch for heavy execution while owning only the tree/continuity layer) is unevaluated and may dominate full Option 1 on the cost axis while still approximating "built in." It should be explored before this ADR locks. Misha's *"open to reconsidering if there might be a better way"* explicitly invites this.
- **Blocks / sequencing:** ADR-032 (JSON-state schema; PRD OQ-1 conflict unit / OQ-4 action-item typing) is still a separate downstream contract ADR. **The r2 "non-negotiable per-field-mergeable" pin was Option-4-specific** (it existed because Option 4 had two independent live writers reconciling at spawn). Under Option 1 the orchestrator owns all writes, so the concurrency rationale changes; the per-field-mergeable property may still be desirable for GUI/loop interleaving but is **no longer a fixed cross-architecture input** — it is reopened and decided in ADR-032 against the adopted architecture. Recorded so the obsolete r2 pin is not silently carried forward.
- **Stale Phase-4 plan flagged (not acted on):** `docs/plans/conversation-tree-ui.md` decomposes the struck Option 4 and is now obsolete in its core; it remains parked and will be re-authored, not patched, at post-Stage-F reconciliation against the adopted option. No edit made now (PRD intake still in progress).
- **One-PRD convention (PRD OQ-9 / Phase-0 Decision A) — RESOLVED to option (a), `docs/prd.md`, r2 2026-05-15.** Phase-0 initially leaned to `docs/prd-conversation-tree.md` (honest naming over gaming the path). The lean reversed when `prd-validity-gate.sh` became mechanically live at plan-write time: it resolves any non-carve-out `prd-ref:` to `docs/prd.md`; the `n/a — harness-development` carve-out would be a FALSE claim for a user-facing product (prd-validity.md flags this exact misuse); and `gate-respect.md` forbids both gaming the carve-out and `--no-verify` bypass. Conforming to the single-PRD-per-project convention is the gate's own named remediation **and** is what makes the mechanism genuinely fire — the explicit point of this design-process demonstration. The PRD now lives at `docs/prd.md` (`git mv`, history preserved); substance was reviewed by `prd-validity-reviewer` at 8b1453e. The "harness repo has one product PRD = the conversation-tree module" framing is accepted as the cost. Still reversible (one `git mv`) but no longer recommended to reverse — the gate's contract is the harness's single-PRD convention.

## Phase-3 review hardening (HISTORICAL — r2, Option 4 struck)

> **This section is a historical audit record only.** It documents the r1 `systems-designer` FAIL and the r2 hardening of **Option 4**, which the stakeholder struck at r3. None of the findings, the per-scenario table, or the "what v1 delivers" conclusion below is load-bearing for the r3 decision (Option 1 vs 2 vs 3). It is retained, not deleted, because deleting a completed adversarial-review record would break the audit trail. r3 requires its own fresh `systems-designer` pass (deferred to post-Stage-F reconciliation).

`systems-designer` returned **FAIL** on r1 with 4 class-aware findings (2 blocking, 2 hardening). Per the Tier-5 rubric the review hardened the (then-recommended) Option-4 option analysis before adoption. Resolution (all against the now-struck Option 4):

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

- PRD: `docs/prd.md` (OQ-8 = this decision; OQ-1/OQ-4 → ADR-032 reopened per r3; the Stage-A/B scope expansion + NFR-11 are binding r3 inputs).
- `~/.claude/rules/spawn-task-report-back.md` — was the Option-4 substrate; **no longer load-bearing** (Option 4 struck). Listed only so the historical Phase-3 section's references resolve.
- Research provenance: two read-only research agents, 2026-05-15 — Agent SDK capability profile + desktop/Dispatch external-bridge investigation. Key external sources cited inline (`code.claude.com/docs/en/channels-reference`, `/remote-control`, `/desktop`, `/agent-sdk/overview`; `platform.claude.com/docs/en/managed-agents/sessions`; GitHub anthropics/claude-code #53049, #35072, #17188).
- Work-sizing basis: `build-doctrine/doctrine/03-work-sizing.md` (Tier-5: ADR is the deliverable; decision gated by stakeholder acceptance).
- Phase-3 gate: `systems-designer` adversarial review of this option space before adoption (pending).
