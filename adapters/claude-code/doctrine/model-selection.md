# Model selection — compact
> Enforcement: model-pin-gate.sh (PreToolUse Task|Agent — blocks silent-inherit) + a harness-doctor check (every agents/*.md pinned). Source of truth: config/model-policy.json. Full: this file.
> Applies: every subagent/session spawn.

**The rule (operator directive 2026-07-14):** every subagent is EXPLICITLY assigned a
model at initiation. An omitted `model` does NOT mean "let NL choose" — it means INHERIT
THE CALLER'S model. On a Fable main-loop that silently ran ~1.7M tokens of un-pinned
subagents on the premium Fable tier and drained the budget. **Fable is never reached by
inherit/default — only by explicit pin.**

**Policy (config/model-policy.json — chains are primary→fallback):**
| Category | Chain | Agents |
|---|---|---|
| review / verify | `fable → opus` | code/security/harness/claim/prd/plan-evidence/comprehension-reviewer, task-verifier, functionality-*/harness-evaluator, enforcement-gap-analyzer, documentation-auditor, audience-content-reviewer, *-tester, end-user-advocate |
| design / planning | `fable → opus` | systems-designer, ux-designer, ux-ia-auditor |
| build | `sonnet` | plan-phase-builder, test-writer |
| read-only / cheap | `haiku → sonnet` | explorer, research |
| interactive main / orchestrator | operator's launch choice | — |
| spawn_task / cron / cloud | explicit per-task | — |

`agents/*.md` frontmatter pins the PRIMARY (chain[0]); the fallback is a documented
preference (the frontmatter `model:` field holds one value; the runtime/orchestrator
applies the fallback if the primary is unavailable).

**How to spawn:** pass an explicit `model` on every Agent/Workflow spawn, OR rely on the
target agent's pinned frontmatter. Cheap search → `explorer`/`research` (haiku). Real code
build → `plan-phase-builder` (sonnet). Adversarial review → the reviewers (fable/opus).

**HONEST RESIDUAL (§10 — NOT hard-gated).** A PreToolUse hook can only inspect the Task/Agent
tool surface. It CANNOT reach: Workflow-inline `agent({model})` (model lives inside the script
string), `spawn_task` (no model param), `CronCreate`/scheduled-tasks/RemoteTrigger (no model
param), or the workstreams-ui reconciler headless spawn. Those are covered by THIS convention +
review only — when you author a Workflow, set `model:`/`effort:` on every agent() call
explicitly; when you spawn_task or schedule, name the model in-prompt. There is no runtime
layer-1 policy default (out of repo reach) — if one becomes available, promote emit to auto.
