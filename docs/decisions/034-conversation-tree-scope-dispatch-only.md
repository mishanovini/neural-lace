# ADR 034 — Conversation-Tree Gates Are Scoped to Dispatch Spawn Tools Only (Sub-Agent Task/Agent Out of Scope)

**Date:** 2026-05-19
**Status:** Active (amends ADR-031 r7 Pin 1 → r8)
**Stakeholders:** Misha (decision authority — the conversation tree is his personal tracking surface; what belongs in it is his call); future build-session orchestrators and any session that dispatches sub-agents (downstream beneficiaries — the friction this removes hit them daily).

## Context

ADR-031 r7 "Plan-safety Pin 1" widened the three conversation-tree hooks (`conversation-tree-state-gate.sh` PreToolUse, `conversation-tree-stop-gate.sh` Stop, `conversation-tree-emit.sh --on-spawn` PreToolUse) and the two `settings.json.template` PreToolUse matchers to a **four-tool** enumerated set:

```
mcp__ccd_session__spawn_task | mcp__ccd_session_mgmt__start_code_task | Task | Agent
```

The r7 reasoning for including `Task`/`Agent`: they are "the common branch-creating paths and must not be a silent gap."

Operation falsified that reasoning *for the conversation tree's purpose*. The conversation-tree GUI exists so Misha can keep track of the conversations he is having **with AI via Dispatch** and the items still waiting on **him**. Sub-agent `Task`/`Agent` invocations — `code-reviewer`, `task-verifier`, `ux-designer`, `comprehension-reviewer`, `harness-reviewer`, parallel `plan-phase-builder` dispatch, etc. — are **AI-internal mechanics**. A Claude Code session deciding it needs a peer review is not opening a branch of Misha's conversation; and anything that session genuinely needs from him is already surfaced to him *through Dispatch*. So the r7 four-tool set produced two concrete harms:

1. **Tree pollution.** `conversation-tree-emit.sh --on-spawn` emitted a `branch-opened` node for every sub-agent dispatch, filling the operator's tree with AI-internal workflow noise that has no place in it.
2. **Spurious gate friction.** The PreToolUse `conversation-tree-state-gate.sh` blocked sub-agent `Task`/`Agent` dispatches whenever no `branch-opened` state existed for the (internal) sub-agent, forcing per-session waivers on routine internal work. Observed live in a single day: 3-of-4 parallel reviewers blocked in a customer-facing-docs session; 3-of-4 parallel reviewers blocked in a roles+permissions session; verification Task spawns blocked in a diff-investigation session; a plan-reviewer Task blocked in Conv-Tree Phase B. Every one is AI-internal sub-agent work; none belong in the tree.

The accepted `Bash(claude…)` / `/schedule` gap and every other r7/ADR-032 §8 r2.1 property (attestation primitive, Pin-2 error partition, branch-name-as-required-key, fail-closed discipline, waiver release valves) are unaffected by this decision.

## Decision

**Narrow the conversation-tree enumerated spawn set from four tools to the two Dispatch orchestrator spawn tools:**

```
mcp__ccd_session__spawn_task | mcp__ccd_session_mgmt__start_code_task
```

`Task` and `Agent` are **deliberately out of scope** — not gated, not emitted, not detected by the Stop-gate transcript scan. This is a *scoping decision*, not an "accepted gap": sub-agent dispatch is AI-internal mechanics and is correctly invisible to a surface that models the user↔AI conversation. The narrowing is applied identically and symmetrically across:

- `adapters/claude-code/hooks/conversation-tree-state-gate.sh` — PreToolUse matcher (`case "$TOOL_NAME"`).
- `adapters/claude-code/hooks/conversation-tree-stop-gate.sh` — transcript-scan `case "$nm"`.
- `adapters/claude-code/hooks/conversation-tree-emit.sh` — `--on-spawn` `case "$tool"` (so no node is emitted for sub-agents).
- `adapters/claude-code/settings.json.template` — the two conversation-tree PreToolUse `matcher` strings (the unrelated `teammate-spawn-validator` `Task|Agent` matcher is left untouched).

Each hook's `--self-test` is extended with regression coverage proving sub-agent `Task`/`Agent` is NOT gated/emitted, including a 4-parallel-Task regression (the exact friction shape above) and a bare-Agent-no-identifier no-op (the previous "could not extract any branch identifier" → BLOCK path that forced a waiver).

ADR-031 r7 Pin 1 sub-decision (b) is amended (r8); its historical text is retained verbatim under the Tier-5 option-history discipline and read as superseded. ADR-032 §8's branch-name-as-required-key bar is unchanged — it simply applies to a smaller, Dispatch-only matcher.

## Alternatives Considered

- **Keep the four-tool set, suppress the friction with a standing waiver / allowlist for known sub-agent types.** Rejected: it treats a scoping error as an exception to be papered over. The tree would still be polluted with sub-agent nodes (the emit harm is untouched by a gate waiver), and an allowlist of agent names is brittle drift-bait that re-introduces the silent-gap risk Pin 1 worried about — in the wrong direction.
- **Narrow only the two gates, leave `conversation-tree-emit.sh` on the four-tool set.** Rejected: incoherent and half-finished. Gates would stop blocking sub-agent dispatch but the emitter would still create `branch-opened` nodes for every reviewer/verifier — the operator's tree stays polluted, which is the larger of the two harms. Option A is only coherent if all three hooks narrow together.
- **Make sub-agent nodes visible but visually de-emphasized in the GUI (a "workflow" lane).** Rejected (for now): adds GUI scope for zero stakeholder value — Misha's stated need is the *opposite* (fewer things in the tracker, only Dispatch conversations). Revisitable if a future need to observe sub-agent topology emerges; it would be a new ADR, not a silent widening.
- **Add a `mcp__dispatch__send_message`-style surface to the matcher (as the originating task brief loosely suggested).** Rejected: no such tool exists in the enumerated set or the runtime; ADR-031 r7 Pin 1 / ADR-032 are explicit that the matcher is an enumerated set re-decided only via ADR, and inventing a matcher entry for a non-existent tool would be vaporware. The brief's intent (Option A: Dispatch spawn tools stay gated, sub-agent Task/Agent do not) is implemented with the real tool names.

## Consequences

**Enables / fixes:**
- A Code session can run parallel sub-agent reviewers/verifiers without any conversation-tree gate block and without writing per-session waivers — the daily friction Misha identified is removed at the root.
- The conversation tree contains only Dispatch conversation branches: the operator's "what's waiting on me" view is no longer diluted by AI-internal workflow nodes (the FR-24 "100% of open branches surface-able" property is *strengthened* — fewer false nodes competing for attention).
- The three hooks and the two settings matchers are now consistent with what the tree is *for*; the rule `conversation-tree-state.md` reframes Task/Agent from "enforced" to "deliberately out of scope."

**Costs / accepted:**
- Sub-agent dispatch is now entirely invisible to the conversation-tree mechanical layer. This is intended: a sub-agent is not a conversation branch. If a future workflow genuinely needs sub-agent topology tracked, that is a *new* decision requiring re-enumeration here (ADR-031 r7's symmetric "any change to the enumerated set requires re-enumeration" discipline applies to removals as well as additions — this ADR is that re-enumeration).
- `Bash(claude…)` / `/schedule` remain an accepted gap exactly as before — out of scope of this change.

**Verification:** `conversation-tree-state-gate.sh --self-test` 20/20 (incl. `r1-4x-parallel-Task-not-gated`, `r2-bare-Agent-no-identifier-noop`, `m3-Task-noop`, `m4-Agent-noop`, `h3-Task-noop-even-with-good-state`); `conversation-tree-stop-gate.sh --self-test` 9/9 (incl. `s9-taskonly-no-spawn-ALLOW`); `conversation-tree-emit.sh --self-test` 17/17 (incl. `ST3 sub-agent Task → no-op`, `ST4 sub-agent Agent → no-op`). `settings.json.template` validated as well-formed JSON; the two conversation-tree matchers are Dispatch-only, the unrelated `teammate-spawn-validator` `Task|Agent` matcher untouched.
