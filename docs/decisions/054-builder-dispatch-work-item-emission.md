# 054 — Builder-Dispatch Work-Item Emission + Tracking-Substrate Gate (amends ADR-034's scoping for orchestrator sessions)

- **Date:** 2026-06-10
- **Status:** Active
- **Stakeholders:** Misha (directive), harness maintainers, every orchestrator session
- **Amends:** ADR-034 (Conversation-tree gates scoped to Dispatch spawn tools only) — for the WORK-ITEM tier only; ADR-034's conversation-BRANCH scoping stands unchanged.

## Context

Misha's directive (2026-06-10, verbatim intent): *"we need a mechanism to force
you to actually do what it is you're supposed to do... track everything in the
Workstreams UI... built into our process so that it always happens
automatically, even when you don't want to listen to me."*

ADR-034 (2026-05-19) scoped the conversation-tree emit/gate surface to the two
Dispatch spawn tools and deliberately excluded sub-agent `Task`/`Agent` — they
are AI-internal mechanics, not branches of the user↔AI conversation, and
emitting BRANCH NODES for them polluted the operator's tree (3-of-4 parallel
reviewers forcing spurious waivers in one day was the originating cost).

That scoping was correct for the BRANCH tier and remains so. But it left the
orchestrator's builder dispatches (`Task` / `Agent` / `Workflow`) with ZERO
Workstreams visibility: a session could dispatch ten builders and the UI's
In-flight pane showed nothing in motion. The work-in-motion tier the R7 sweep
introduced (`wim-*` nodes from ground truth: plans / branches / PRs) covers
repo-observable effort, not live dispatch activity. Tracking by agent
discipline ("remember to emit") is exactly the kind of Pattern that drifts
under context pressure — the directive demands a Mechanism.

## Decision

Builder dispatches auto-emit **WORK-ITEMS, not conversation branches**, with a
thin fail-closed substrate gate behind the writer (forcing-first, gate-second):

1. **`workstreams-emit.sh --on-builder-dispatch`** (PreToolUse on
   `Task|Agent|Workflow`): emits — via the sole-normative `state.js` facade
   `appendEvent`, canonical path via the shared resolver — an idempotent
   creation batch on the session's own `ss-*` node: `branch-opened` (root +
   session node, same deterministic event ids `--on-session-start` uses, so
   no duplication) + `action-added` (item_id `wi-bd-<sha1(sid|tool|title)>`,
   title from `.description // .meta.name // .name // .title // first prompt
   line`) + `item-details-set` (`_category: "builder-dispatch"`, tool,
   subagent_type, background flag). A correlation ledger line lands at
   `~/.claude/state/conversation-tree-emit/builder-<sid>.jsonl`.
   **No branch node is created for the dispatch** — ADR-034's tree-pollution
   rationale is honored; this is the work-item tier.
2. **`workstreams-emit.sh --on-builder-complete`** (PostToolUse on the same
   matcher): re-derives the same deterministic ids; emits the creation batch
   (covers a missed PreToolUse fire) plus `action-done` — but ONLY for
   foreground dispatches. Background dispatches (`Workflow`, or
   `run_in_background: true`) get the creation batch only.
3. **`workstreams-emit-reconciler.sh` builder sweep** (existing Stop wiring):
   re-derives every builder `tool_use` from the agent-uneditable transcript;
   catch-up-fires `--on-builder-dispatch` for each, and
   `--on-builder-complete` for each whose `tool_result` is present
   (idempotent event ids make re-fires no-ops; background discrimination
   stays in the emit hook — one implementation).
4. **`workstreams-state-gate.sh --builder-tracking`** (PreToolUse on
   `Task|Agent|Workflow`, wired AFTER the emit): THIN fail-closed gate —
   BLOCKS the dispatch when tracking is possible (node + state library
   present) but the canonical state file is missing or unwritable; degrades
   OPEN when the subsystem itself is absent (bootstrap rule — a machine
   without Workstreams must not be bricked). Escape hatches: fresh
   substantive `.claude/state/builder-tracking-waiver-*.txt` (<1h) and
   `WORKSTREAMS_BUILDER_GATE_DISABLE=1` (harness-dev), both surfaced in the
   block message.

### Noise control (why this cannot pollute Awaiting-me)

Items carry `kind: action` + `details._category: "builder-dispatch"` — not in
the GUI's `MISHA_ASK_CATEGORIES` set, so `isAwaitingMe` is false by
construction. Unchecked + no explicit state derives `in-flight` (`itemState`
default) → exactly the In-flight chip, the work-in-motion tier. Completion
checks the item, removing it from In-flight.

### The honest completion-signal ceiling (Rule 7)

Investigated surfaces (2026-06-10):

- **Foreground `Task`/`Agent`** (the orchestrator-pattern's normal builders,
  including parallel dispatches): PostToolUse fires at tool RETURN, which IS
  sub-agent completion. `action-done` is mechanical and solid. (SubagentStop
  was considered and rejected: same firing moment, but no `tool_input` to
  recompute the deterministic item id — correlation would be guesswork.)
- **Background dispatches** (`Workflow` launches; `run_in_background: true`):
  PostToolUse fires at LAUNCH-return — emitting done there would be a FALSE
  completion claim, so the hook does not. There is **no stable local hook
  event or documented transcript contract for background-dispatch
  completion** (no per-workflow completion hook event; the wake/notification
  message shape is undocumented and not a contract). The item therefore
  honestly stays in-flight; FR-7 keeps its session node un-concludable —
  intentionally visible in the orphan/staleness surface rather than papered
  over. Resolution paths: a later turn's explicit `--resolve-item`, the
  operator in the GUI, or an upstream hook surface if Anthropic ships one.
  **This is a named gap, not a solved problem.**
- **Missed hook fires**: the Stop-time reconciler sweep is the catch-up; its
  ceiling is the same as above for background completion.

## Alternatives considered

- **Emit branch nodes per dispatch (revert ADR-034):** rejected — re-creates
  the exact operator-tree pollution ADR-034 removed; the work-item tier gives
  visibility without nodes.
- **SubagentStop as the completion surface:** rejected — fires at the same
  moment PostToolUse returns for foreground dispatches but lacks the
  tool_input needed to recompute the deterministic item id.
- **Stop-time "mark everything done":** rejected — false completion claims
  for killed/in-flight background work (Rule 0/7 violation).
- **Per-dispatch ledger verification in the gate:** rejected — any transient
  emit flake would false-positive-block every subsequent dispatch
  (harness-DoS); the thin substrate-presence check forces tracking
  availability while the reconciler handles individual misses.
- **Pattern-only (rule telling the orchestrator to emit):** rejected — the
  directive's entire point is that discipline drifts; this must be a
  Mechanism.

## Consequences

- Every builder dispatch from a local session is visible in the Workstreams
  UI as in-flight work the moment it is dispatched, and resolves
  automatically on foreground completion — zero orchestrator discipline
  required.
- A dispatch CANNOT proceed untracked when tracking is possible: the thin
  gate blocks (exit 2, `{"decision":"block"}`) until the substrate is fixed
  or a substantive waiver is authored. Degrade-open keeps fresh machines and
  non-Workstreams environments unaffected.
- Background-dispatch completion remains untracked (documented ceiling);
  those items accumulate as open in-flight work until explicitly resolved —
  surfaced, not hidden.
- Cloud sessions that load no `~/.claude/` hooks remain out of reach (the
  ADR-031 r7 accepted cloud blind spot, unchanged).
- Self-test coverage: emit 52 checks, state-gate 27 checks (7 new BT),
  reconciler 9 checks (3 new builder scenarios).

## Refutation criterion

This mechanism's premise — PostToolUse return == foreground sub-agent
completion — would be REFUTED by observing a foreground `Task`/`Agent`
PostToolUse fire while the sub-agent demonstrably continues running
(e.g., its tool calls appearing in the transcript after the PostToolUse
event). No such behavior was observed; if observed, the completion emit
must move to SubagentStop with a correlation redesign.
