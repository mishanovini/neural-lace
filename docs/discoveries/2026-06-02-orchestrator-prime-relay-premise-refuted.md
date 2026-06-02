---
title: orchestrator-prime relay premise refuted; redesign already exists
date: 2026-06-02
type: architectural-learning
status: pending
auto_applied: false
originating_context: A Dispatch-orchestrator session spawned a Code session with a multi-part brief to "build orchestrator-prime" — a long-lived harness-native Code session that Dispatch pokes via a transcript-read relay to replace Dispatch's orchestration role. Diagnostic-first investigation before building.
decision_needed: Build orchestrator-prime as specified (REFUTED mechanism), OR greenlight the already-authored dispatch-coordination-redesign.md (honest mechanism, pending Misha since 2026-05-25), OR build the salvageable sound core (stateless harness-native orchestrator re-hydrated per Dispatch turn) as a new Mode:design plan?
predicted_downstream:
  - docs/plans/dispatch-coordination-redesign.md
  - docs/decisions/039-conv-tree-reconciliation-over-interception.md
  - docs/decisions/041-dispatch-mode-autodetect-signal.md
  - docs/decisions/042-ntfy-out-of-band-notification.md
  - .claude/state/spawned-task-results/ (report-back to the dispatching orchestrator)
---

## What was discovered

A Dispatch-orchestrator session dispatched a 5-part brief (Parts A–E) to build
**orchestrator-prime**: a long-lived, harness-native Claude Code session that Dispatch
demotes itself to relay for. The spec's central mechanism (Part B, "Pick (c)"): Dispatch
calls `send_message` to inject Misha's text into orchestrator-prime, then reads
orchestrator-prime's transcript and forwards the latest message back to Misha.

Diagnostic-first investigation (per `~/.claude/rules/diagnosis.md`) — reading the prior
art **before** writing any code — found the core mechanism is already **PROVEN-refuted**
on this exact machine, and that a better-aligned design already exists.

### Finding 1 — the relay/parent-wake premise is refuted (PROVEN)

`docs/discoveries/2026-05-25-dispatch-coordination-debug.md` RC1 (PROVEN): *"The available
tool surface in a Dispatch-orchestrator session has no inter-session message-delivery
primitive... Nothing in `~/.claude/` can wake a sleeping parent on a child's turn-end...
the relay genuinely hangs until something else (a human, a poll, a new session start)
advances state."*

The orchestrator-prime spec depends on exactly the missing primitive:

- **PROVEN:** Reading a session's transcript is *passive*. It does not cause that session
  to **process** a new message and produce a fresh response. For orchestrator-prime to
  "process Misha's message and respond," the message must be injected AND orchestrator-prime
  must **wake and take a turn** — the precise capability RC1 proved is Anthropic-blocked,
  not harness-buildable.
- **Corroborating (self-admitted in the brief):** the spec's own Part B Option (b) says
  the wake mechanism *"requires a harness mechanism — probably a hook or a custom MCP
  server"* — i.e., the brief concedes the primitive does not exist yet.
- **Corroborating:** `docs/plans/dispatch-coordination-redesign.md` (the honest design for
  this exact problem) contains **zero** uses of a `send_message`/`read_transcript`/
  `start_code_task` relay (grep: 0 matches) — precisely because that relay is the refuted
  approach.

Refutation criterion for *my* claim ("the relay can't work as specified"): it would be
REFUTED by the existence of a tool that wakes an idle Code session on demand and makes it
take a turn on an injected message. Prior investigation checked the live tool surface
(Claude Code 2.1.146, this machine) and found none; this Code session's own toolset also
exposes no such primitive. Criterion not met → claim stands.

### Finding 2 — a better-aligned, more-honest design already exists (PROVEN)

`docs/plans/dispatch-coordination-redesign.md` (Mode: design, tier 3, rung 3, **Status:
DRAFT**, committed PR #16, **pending Misha's explicit greenlight since 2026-05-25**)
addresses the *same problem* — make the Dispatch↔Code relay reliable and make the
operator's "what's waiting on me" surface (the conversation-tree GUI) actually populate.
Its verdict on the parent-wake gap (RC1) is to **name it honestly as Anthropic-blocked and
route around it**: a `list_sessions` reconciler for visibility, an opt-in `ntfy` push to
wake the **human** when the parent is asleep, a bounded poll palliative so the relay never
hangs *forever*, and a filed upstream issue as the actual cure. ADRs 039/041/042 back it.

The orchestrator-prime brief, by contrast, would **pretend the transcript-read relay closes
the parent-wake gap** — the exact "false promise" the redesign's Decisions Log explicitly
rejected.

### Finding 3 — the irony is load-bearing (the cause of the bad spec)

The Dispatch orchestrator that authored the orchestrator-prime brief **could not see** the
prior `dispatch-coordination-redesign.md` work — because it runs sandboxed without
`~/.claude/` / repo visibility. That sandbox-blindness is the *very problem* the brief is
trying to solve, and it is *why* the brief re-specified a refuted relay. A harness-visible
orchestrator would have hit RC1 first. (This is genuine signal for Finding 2's motivation,
not against it — see "Why it matters.")

## Why it matters

The *motivation* behind orchestrator-prime is sound and worth pursuing; the *mechanism* it
specifies is refuted. Separating the two:

- **SOUND (Claim 1):** "The orchestrator should be a harness-native Code session with full
  filesystem / agent / hook / rule access, not a sandboxed Dispatch session that can't see
  the harness." A Code session genuinely *does* have all of that. Finding 3 is concrete
  evidence *for* this claim.
- **REFUTED (Claim 2):** "...realized as a long-lived persistent session that Dispatch
  pokes via a transcript-read relay, with messages reliably round-tripping." This is the
  part RC1 refutes.

This is a classic "right problem, wrong mechanism" — the same shape the 2026-05-25
investigation caught in the original brief's two refuted fixes. Building Claim 2 as
specified would burn a multi-part build (worktree, relay protocol, ADR-068, memory entry,
round-trip test) on a relay that cannot round-trip, then ship a non-fix and erode trust —
the exact anti-vaporware failure the harness exists to prevent. It is also a tier-3
Mode:design change to harness infrastructure that `systems-design-gate.sh` would block
without a `systems-designer` PASS regardless of the "do not pause, build it" directive
(per `~/.claude/rules/gate-respect.md`: diagnose, don't bypass).

## Options

- **A — Build orchestrator-prime as specified.** REJECTED. Core relay mechanism is
  PROVEN-refuted (Finding 1); ships a non-fix; would also need to clear the Mode:design
  gate it currently has no plan for.
- **B — Greenlight the existing `dispatch-coordination-redesign.md`.** It already solves
  the operator-facing outcome (visibility + human-wake when parent is asleep + named
  upstream cure) honestly, is authored, reviewed-shaped, and waiting on Misha. Cost: it
  does NOT make the orchestrator harness-native — it improves the *current* Dispatch→Code
  topology rather than replacing Dispatch's orchestration role (Claim 1 unaddressed).
- **C — Build the salvageable SOUND core as a new Mode:design plan: a stateless,
  harness-native orchestrator re-hydrated per Dispatch turn.** Instead of a long-lived
  poked session, each Dispatch turn *spawns* a Code session that hydrates from a canonical
  state file + the conversation tree, orchestrates, writes state back, and ends. This
  delivers Claim 1 (harness-native orchestrator with full agent/hook/rule access) WITHOUT
  depending on the refuted parent-wake primitive — it uses the spawn/report-back path that
  already works. Compose with B for visibility + human-wake. Cost: a new Mode:design plan +
  systems-designer PASS; some latency per turn (cold hydrate); the conversation-tree GUI is
  still the operator surface.
- **D — Defer; do nothing until Misha picks.** Capture only (this file), surface, wait.

## Recommendation

**C, composed with B, gated behind B's greenlight.** Reasoning by principle (reversibility
+ blast radius + honesty):

- It preserves the *sound* half of the brief (harness-native orchestrator — Claim 1) while
  dropping the *refuted* half (the long-lived transcript-read relay — Claim 2).
- It reuses an existing, working primitive (spawn + `spawn-task-report-back` + canonical
  state) rather than a primitive RC1 proved does not exist.
- B is the cheapest honest win for the operator-visibility pain and is already authored and
  waiting — greenlighting it is low-risk and independently valuable.
- It does not *pretend* to close the Anthropic-blocked parent-wake gap; it routes around it
  the same honest way the existing design does.

This is a Tier-3 / irreversible architectural decision (material change to load-bearing
harness orchestration topology; not a single-revert). Per `~/.claude/rules/discovery-protocol.md`
and `~/.claude/rules/planning.md` Tier-3, it is surfaced to Misha and **NOT auto-applied**.

## Decision

(Pending Misha.)

## Implementation log

(Empty — diagnostic-only. No worktree created, no relay built, no ADR-068 authored: an ADR
records a *made* decision, and this decision is Misha's and unmade. No code changes.)
