# Harness improvement proposal: model-pin-mandatory gate

Status: PROPOSED (2026-07-11). Author: orchestrator session. Trigger: operator
directive after the entire Fable budget was exhausted mid-build by un-pinned spawns
despite an explicit two-time instruction to tier models per sub-agent. nl-issue filed
same day. Review before landing: `harness-reviewer` (this is a new Mechanism/gate —
Rule 10 requires a golden scenario + expected-FP rate + retirement condition, all below).

## The gap (operator, verbatim)

"Neural Lace is supposed to manage the model that's used for every task. It's clearly
not doing it." Model selection today depends on the **agent remembering to pass
`model:`** on each `Agent`/`Workflow` spawn. An omitted `model:` does NOT mean "let NL
choose" — it means "inherit the main-loop model." On a Fable session, every un-pinned
spawn therefore runs on Fable, the one metered model. This is the exact
cooperative-self-reporting failure class NL exists to eliminate, applied to model
selection: reliance-on-memory where a mechanism is required.

## Golden scenario (what this must catch)

2026-07-11: a Fable main-loop session dispatched a plan-draft+review workflow (~588k
subagent tokens), two adversarial review workflows (~381k + ~120k), a plan audit
(~310k), and two general-purpose amendment agents (~277k) — ALL without an explicit
`model:` — so all ran on Fable and drained the monthly budget before the build finished.
A gate that refuses an un-pinned write/spend-capable spawn would have blocked every one.

## Proposed mechanism (two layers — policy first, gate as backstop)

1. **Policy default (the real fix — NL owns the choice):** a task/agent-type → model
   map NL applies automatically so the correct model is selected WITHOUT the caller
   specifying it. Concretely: a default `model` per `subagent_type` in the agent
   registry (`.claude/agents/*.md` frontmatter gains an optional `default_model:`), and
   a workflow default. `plan-phase-builder` → sonnet; verifiers/reviewers → opus;
   explorer/mechanical → haiku. When a spawn omits `model:`, NL resolves the policy
   default for that agent-type instead of blindly inheriting the main-loop model.
2. **PreToolUse gate (backstop, mirrors `teammate-spawn-validator.sh`):** a new flag
   `model_pin_mandatory: true` in `~/.claude/local/agent-teams.config.json`. When set,
   `teammate-spawn-validator.sh` (already a PreToolUse hook on `Agent`) rejects an
   `Agent` spawn whose `tool_input.model` is absent AND whose agent-type has no registry
   default — exit 2 with a message naming the omission, exactly as the isolation check
   already does for `isolation: worktree`. Escape hatch: pass `model:` explicitly, or set
   a registry default, or flip the flag off.

## Workflow caveat (honest limitation)

The `Workflow` tool sets model per `agent()` call INSIDE the script string, which a
PreToolUse hook cannot statically inspect. Layer-2's gate therefore covers `Agent`
spawns cleanly but not per-agent Workflow calls. Mitigation: the workflow runtime
applies the layer-1 policy default to any `agent()` lacking `model:`, and (optional) a
lint warns when a Workflow script contains an `agent(` call with no `model:` token.
This means layer 1 (policy default) is load-bearing; the gate is the visible backstop.

## Expected false-positive rate

Near zero for the gate: the only "false positive" is a deliberate inherit-the-main-loop
spawn, which is exactly the behavior that caused the incident — so blocking it is
correct, not a false fire. The escape hatch (explicit `model:`) is one field.

## Retirement condition

Retire the gate if/when layer-1 policy defaults cover 100% of spawn paths (Agent +
Workflow) such that an un-pinned spawn can never resolve to the main-loop model — at
that point the gate is redundant with the policy and can be dropped.

## Enforcement inventory note

If landed, add a `manifest.json` entry (kind: gate, wired via `teammate-spawn-validator`)
so the doctor tracks it — do not repeat the spliced-script-without-manifest-entry class
this estate has hit before.
