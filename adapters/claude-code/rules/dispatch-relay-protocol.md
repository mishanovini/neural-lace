# Dispatch Relay Protocol — Dispatch Forwards, orchestrator-prime Orchestrates

**Classification:** Pattern (self-applied by Dispatch sessions). There is no mechanism that
forces a Dispatch session to relay rather than orchestrate — Dispatch is closed-source and does
not reliably load `~/.claude/` hooks (RC2(a), Decision 011). This rule binds Dispatch sessions
that DO load harness rules, and is the convention the `feedback-dispatch-relay-only.md` memory
reinforces. Honesty note: the inbox/outbox file seam this rule depends on is UNVERIFIED until the
orchestrator-prime plan's Task 5 smoke test passes.

**Ships with:** ADR 050 (`docs/decisions/050-orchestrator-prime-loop-architecture.md`).

## The rule

Once orchestrator-prime is live, a Dispatch session makes **NO orchestration decisions**. Its
entire job is to relay between Misha and orchestrator-prime via the file-mediated seam:

1. **Inbound — Misha → orchestrator-prime.** When Misha sends a message, write it to
   `~/.claude/orchestrator-prime/inbox/<turn_id>.json` (a JSON object: `{turn_id, from:"misha",
   text, ts}`). Do NOT act on the message's content yourself — orchestrator-prime owns the work.
2. **Outbound — orchestrator-prime → Misha.** Poll `~/.claude/orchestrator-prime/outbox/` for new
   `<turn_id>.json` files; for each unseen one, `SendUserMessage` its `text` to Misha, then mark
   it seen (rename to `.surfaced` or track in a seen-set). Do not editorialize — surface verbatim.
3. **Do NOT spawn build sessions, make architecture calls, or decide what work happens.** That is
   orchestrator-prime's job (it has full harness access; you do not). If orchestrator-prime is not
   yet live, fall back to the pre-orchestrator-prime behavior.

## Why

A Dispatch session is sandbox-blind: it cannot see `~/.claude/`, invoke specialist agents, run
hooks, or honor most harness rules. Orchestration decisions made there are made without the
harness — which is how a refuted relay got specified (see
`docs/discoveries/2026-06-02-orchestrator-prime-relay-premise-refuted.md`). orchestrator-prime IS
the harness; routing all orchestration through it is the fix.

## Honest limitations

- The inbox/outbox file seam assumes a Dispatch session can read/write `~/.claude/orchestrator-prime/`.
  This is UNVERIFIED (Dispatch is closed-source) — smoke-tested in the orchestrator-prime plan
  Task 5. If a Dispatch session cannot reach the file seam, the fallback visibility path is the
  conversation-tree GUI + ntfy push (`dispatch-coordination-redesign.md`), which orchestrator-prime
  populates via tree events regardless.
- This rule does not bind genuine cloud / app-UI Dispatch actions that load no `~/.claude/` rules.

## Cross-references
- ADR 050 (`docs/decisions/050-orchestrator-prime-loop-architecture.md`).
- SKILL: `adapters/claude-code/skills/orchestrator-prime.md`.
- `docs/plans/orchestrator-prime.md` Task 5 (seam smoke test).
- `docs/plans/dispatch-coordination-redesign.md` (the fallback visibility path).
