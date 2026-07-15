# 063 — model-pin-gate BLOCKS rather than auto-assigns a model

**Date:** 2026-07-15
**Status:** Accepted
**Tier:** 2 (architectural; reversible only by a platform capability change)
**Context plan:** docs/plans/archive/model-enforcement-2026-07-14.md

## Decision

The `model-pin-gate.sh` PreToolUse hook, on a Task/Agent spawn with no explicit `model`
and an unpinned/unknown agent type, **denies** the spawn (exit 2) and instructs the author
to pass a model or pin the agent. It does **not** auto-inject a policy-default model.

## Why not auto-assign (the question that will otherwise recur)

"Blocking is not the only lever a deterministic hook has" is **correct in general** —
Claude Code PreToolUse hooks CAN rewrite a tool's input via
`hookSpecificOutput.updatedInput` (a documented field:
https://code.claude.com/docs/en/hooks, "PreToolUse decision control"). So for most tools
a hook could deterministically fix the input instead of refusing it.

**But the docs explicitly carve out subagent spawns.** Verbatim: *"`updatedInput` does not
apply to Task and Agent (subagent-spawn) tool calls."* Adjacent events don't help either:
`SubagentStart` has *"No blocking or decision control"* (text-nudge `additionalContext`
only), and no hook event exposes a settable `model` on a Task `tool_input` (there is no
`$CLAUDE_MODEL` env var; `model` appears only on `SessionStart` *input*, received not
injectable). Verified 2026-07-15 by a `claude-code-guide` pass citing the official hook docs.

**Therefore, for the Task/Agent surface specifically, deny/ask is the only mechanism the
platform exposes.** Auto-assign is not buildable as a deterministic hook today. The prior
doctrine line ("the gate can only allow/block, it can't inject a model") reached the right
conclusion for the wrong reason — it assumed a general limit that does not exist; the real
reason is a platform carve-out for this one tool.

## Consequences

- The block-on-missing-model design is the correct implementation **given the constraint**,
  not a lesser stand-in. Model assignment is the author's job (pass `model:` on the spawn,
  or spawn a pinned agent); the gate enforces that it happened.
- `ask` (interactive prompt) was rejected as the decision: it wedges unattended automation
  sessions. `deny` is automation-safe.
- Built-in types (Explore/Plan/general-purpose/claude) that can't be pinned are blocked
  until an explicit `model:` is passed — this is the enforcement, not a false-positive (see
  the archived plan's built-in-strictness note; operator default: strict).

## Revisit when

Claude Code adds `updatedInput` support (or any `model`-injection path) for Task/Agent
spawns, or natively requires an explicit model on every subagent spawn. Tracked upstream via
nl-issue (no subagent-model-injection capability). At that point, redesign block→auto-assign.
