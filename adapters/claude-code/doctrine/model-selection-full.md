# Model selection — full

Detail companion to `model-selection.md` (the compact). The compact carries every
imperative rule; this file carries the elaboration, rationale, and incident narrative
that motivated it.

## The incident that prompted the rule (operator directive 2026-07-14)

A Fable main-loop silently ran ~1.7M tokens of un-pinned subagents on the premium Fable
tier and drained the budget. The root cause: an omitted `model` field on a subagent spawn
does not mean "let NL choose the cheapest reasonable model" — it means the subagent
INHERITS THE CALLER'S model. Because the main loop itself was running on Fable, every
un-pinned subagent it spawned silently inherited Fable too, at Fable's cost, for tasks
that only needed haiku or sonnet. This is why the rule is stated as absolute: Fable must
never be reached by inherit/default, only by an explicit pin in `agents/*.md` frontmatter
or an explicit `model` argument on the spawn call.

## Fallback mechanics

`agents/*.md` frontmatter pins the PRIMARY model (chain[0] in `config/model-policy.json`).
The fallback (chain[1]) is a documented preference, not a second frontmatter field — the
frontmatter `model:` key holds exactly one value (the primary). The runtime/orchestrator
is responsible for applying the fallback chain if the primary model is unavailable
(rate-limited, down, etc). This means the frontmatter alone does not encode the full
policy — `config/model-policy.json` is the actual source of truth for the chain, and the
frontmatter is a derived/pinned snapshot of chain[0].

## Gate agent-matching detail

`model-pin-gate.sh` resolves the agent definition being spawned by filename slug OR by
display `name:` in that agent's frontmatter — so a `subagent_type` value of "Domain
Expert Tester" (a display name) still correctly matches and resolves to
`domain-expert-tester.md` (the filename slug). This matters because Task/Agent spawns
can supply either form as `subagent_type`, and a naive filename-only match would
false-positive on any spawn using the display-name form.

The `fork` subagent_type is EXEMPT from the pin requirement: it always inherits the
parent session's model by design (that is the entire point of `fork` — a continuation of
the same reasoning context, including its model) and takes no `model` override at all.
Blocking `fork` spawns for lacking a `model` field would therefore be an
un-remediable false-positive — there is no correct value an author could supply, since
supplying one would contradict what `fork` is for. The gate special-cases this
subagent_type rather than requiring authors to work around it.

## Why BLOCK not auto-assign (decision 063) — full rationale

PreToolUse hooks CAN rewrite tool input via `hookSpecificOutput.updatedInput` in general.
However, the Claude Code documentation explicitly excludes subagent spawns from this
mechanism: "`updatedInput` does not apply to Task and Agent tool calls." Additionally,
`SubagentStart` (the lifecycle hook that fires once the subagent is already spawned) has
no decision-control capability — it cannot veto or rewrite the spawn, only observe it.

Given both of these, deny (block-and-require-retry) is the ONLY deterministic enforcement
lever available on this surface today. An auto-assign hook — one that silently injects a
sensible default `model` when the author omitted one — is not buildable with the current
Claude Code hook API. Consequently, the policy commits to human responsibility: model
assignment is the author's job at write-time, and the gate's role is purely to enforce
that the author did their job, not to do it for them. If a future Claude Code release
adds `updatedInput` support for Task/Agent, this decision should be revisited.

## HONEST RESIDUAL (§10) — full detail on gate blind spots

A PreToolUse hook can only inspect the Task/Agent tool call surface as invoked through
the standard tool-call path. It structurally CANNOT reach:

- **Workflow-inline `agent({model})` calls** — in a Workflow script, the model lives
  inside the script string passed to the workflow engine, not as a distinct tool-call
  parameter the hook can inspect independently.
- **`spawn_task`** — this tool has no `model` parameter at all in its schema, so there is
  nothing for a hook to check or enforce.
- **`CronCreate` / scheduled-tasks / `RemoteTrigger`** — same issue: no `model` parameter
  on these tool schemas for a hook to gate on.
- **The workstreams-ui reconciler's headless spawn path** — this spawns sessions outside
  the normal tool-call flow entirely, so no PreToolUse hook fires for it at all.

These four paths are covered by convention and human review only, not by a hard gate.
The practical guidance: when authoring a Workflow, set `model:`/`effort:` explicitly on
every `agent()` call in the script; when using `spawn_task` or scheduling a cron/remote
task, name the intended model in the prompt text itself so a reviewer (or the operator)
can catch a missing/wrong choice.

There is no runtime layer-1 policy default reachable from outside the repo for these
paths today. If the Claude Code platform ever exposes one (e.g., a schema-level default
model parameter on `spawn_task`/`CronCreate`/`RemoteTrigger`), this residual should be
promoted from "convention + review" to an actual hard-gated enforcement, matching the
Task/Agent surface.
