# ADR 050 — orchestrator-prime: the always-on harness-native orchestrator (/loop architecture)

**Date:** 2026-06-02
**Status:** Proposed (build started feat/orchestrator-prime; full-autonomy launch gated on systems-designer PASS + seam smoke test + Misha ack)
**Stakeholders:** Misha (decision authority); the conversation-tree GUI (passive observer, ADR-031 r7); future Dispatch sessions (demoted to relay); the harness maintainer.
**Cross-reference:** the originating brief referred to this as "ADR-068"; the correct sequential number in this repo is 050 (highest prior = 049).

## Context

Dispatch (the current orchestrator) runs **sandbox-blind**: it cannot see `~/.claude/` or the
repos, so it cannot invoke specialist agents, run hooks, or honor most harness rules — and it
re-specifies fixes for problems the harness already solved (it authored a build brief for a
relay that `docs/discoveries/2026-05-25-dispatch-coordination-debug.md` RC1 already PROVED is
impossible). Misha's goal: make the orchestrator **harness-native** (a Code session with full
access) and **self-driving** (keeps work moving without him poking each session).

The first proposed mechanism — a long-lived Code session that Dispatch "pokes" via
transcript-read — is **refuted**: reading a transcript is passive; it cannot make a session
*process* a message and respond; and no inter-session parent-wake primitive exists (RC1, and
re-confirmed by tool-surface inspection this session: only `list_sessions` /
`search_session_transcripts` / `archive_session` exist — no send/resume/read_transcript).

Misha's course-correction — **use `/loop`** — is sound: it makes the session wake *itself* on a
timer (ScheduleWakeup, clamped 60–3600s), so Dispatch never has to wake it. Combined with a
**file-mediated inbox/outbox**, the relay sidesteps RC1 entirely: Dispatch drops a file, the
next self-wake reads it.

## Decision

Adopt the **/loop + file-mediated inbox/outbox** architecture for orchestrator-prime, built
strictly to the **verified** Code-session tool surface:

1. **orchestrator-prime is a Claude Code session running a self-scheduling loop.** At each
   cycle's end it calls `ScheduleWakeup` (or `CronCreate --durable` for survival across session
   death) to schedule the next cycle. Always-on without external poking.

2. **Inbound/outbound is file-mediated.** Dispatch writes `~/.claude/orchestrator-prime/inbox/<turn_id>.json`;
   orchestrator-prime polls it each cycle and writes `outbox/<turn_id>.json`; Dispatch reads the
   outbox and `SendUserMessage`s Misha. The orchestrator-prime side is sound; the cross-process
   delivery is **Dispatch-side and UNVERIFIED** (closed-source) — smoke-tested before launch;
   fallback on a dead seam is the conv-tree GUI + ntfy (`dispatch-coordination-redesign.md`).

3. **"Revive rate-limited children" = DETECT + SURFACE + respawn-with-ack** — NOT message-revive.
   There is no send primitive (PROVEN). orchestrator-prime detects via `list_sessions` +
   `search_session_transcripts`, surfaces to the outbox, and respawns only with Misha's ack and a
   dedup guard (RC4 double-spawn protection). The SKILL forbids attempting the impossible
   message-send (which would just error and stall).

4. **First cycle is report-only; customer-repo merges are surfaced, not auto-merged.** Launching
   an always-on agent that auto-merges to customer-facing prod and autonomously respawns is
   irreversible blast radius — the first cycle only reports inherited state, and per-repo
   `automation-mode.json` decides merge authority (review-before-deploy repos are surfaced).

5. **Everything emits a conversation-tree event** (ADR-032 facade) — the durable, seam-independent
   visibility path. The GUI populates even if the outbox relay is down.

6. **Dispatch is demoted to a thin relay** (`dispatch-relay-protocol.md` + a memory entry):
   forward Misha's message into the inbox, surface the outbox, make NO orchestration decisions.

## Alternatives considered

- **A — Long-lived session poked via transcript-read relay (the original brief).** Rejected:
  RC1-refuted; passive read can't make a session process a message; no parent-wake primitive.
- **B — Message-based child revival.** Rejected: no send/resume primitive exists (PROVEN).
- **C — Just greenlight `dispatch-coordination-redesign.md`.** Complementary, not exclusive:
  that plan fixes visibility + human-wake honestly and is orchestrator-prime's fallback for the
  seam; it does not deliver the harness-native orchestrator. Adopt both (this ADR composes with it).
- **D — Blanket auto-merge across all active repos.** Rejected: violates git.md customer-tier
  policy for customer-facing repos with real users — surfaced instead, gated by automation-mode.

## Consequences

- **Enables:** a self-driving, harness-native orchestrator that survives Dispatch boundaries,
  with full agent/hook/rule access — the sound half of the brief.
- **Honest residuals (named, not faked):** (a) the Dispatch↔inbox/outbox seam is unverified until
  smoke-tested; fallback is GUI+ntfy. (b) Prompt cross-session message delivery remains
  Anthropic-blocked (RC1) — the loop polls; it does not get instant delivery. (c) Child revival is
  detect+surface+respawn, never message-revive.
- **Cost:** an always-on session consuming periodic cycles; a durable cron for crash recovery;
  per-cycle `list_sessions` + `gh pr list`×7 (negligible).
- **Composes with:** ADR-039/041/042 (visibility + dispatch-mode + ntfy), ADR-031/032 (tree),
  ADR-034 (matcher), git.md customer-tier policy.

## Cross-references
- Plan: `docs/plans/orchestrator-prime.md`.
- Discoveries: `docs/discoveries/2026-06-02-orchestrator-prime-relay-premise-refuted.md` (the refutation), `docs/discoveries/2026-05-25-dispatch-coordination-debug.md` (RC1).
- SKILL: `adapters/claude-code/skills/orchestrator-prime.md`.
- Sibling design: `docs/plans/dispatch-coordination-redesign.md` (the honest fallback for the seam).
