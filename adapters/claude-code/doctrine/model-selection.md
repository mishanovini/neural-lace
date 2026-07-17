# Model selection — compact
> Enforcement: model-pin-gate.sh (PreToolUse Task|Agent — blocks silent-inherit) + a harness-doctor check (every agents/*.md pinned). Source of truth: config/model-policy.json. Full: model-selection-full.md.
> Applies: every subagent/session spawn.

**The rule (operator directive 2026-07-14):** every subagent is EXPLICITLY assigned a
model at initiation. An omitted `model` does NOT mean "let NL choose" — it means INHERIT
THE CALLER'S model. **Fable is never reached by inherit/default — only by explicit pin.**
Incident that prompted this rule: full doc.

**Policy (config/model-policy.json — chains are primary→fallback):**
| Category | Chain | Agents |
|---|---|---|
| review / verify | `fable → opus` | code/security/harness/claim/prd/plan-evidence/comprehension-reviewer, task-verifier, functionality-*/harness-evaluator, enforcement-gap-analyzer, documentation-auditor, audience-content-reviewer, *-tester, end-user-advocate |
| design / planning | `fable → opus` | systems-designer, ux-designer, ux-ia-auditor |
| build | `sonnet` | plan-phase-builder, test-writer |
| read-only / cheap | `haiku → sonnet` | explorer, research |
| interactive main / orchestrator | operator's launch choice | — |
| spawn_task / cron / cloud | explicit per-task | — |

`agents/*.md` frontmatter pins the PRIMARY (chain[0]); runtime applies the fallback if
the primary is unavailable. Fallback mechanics: full doc.

**How to spawn:** pass an explicit `model` on every Agent/Workflow spawn, OR rely on the
target agent's pinned frontmatter. Cheap search → `explorer`/`research` (haiku). Real code
build → `plan-phase-builder` (sonnet). Adversarial review → the reviewers (fable/opus).
The `fork` subagent_type is EXEMPT — it always inherits the parent model by design and
takes no `model` override. Gate agent-matching detail: full doc.

**Why BLOCK not auto-assign (decision 063):** PreToolUse hooks cannot rewrite subagent
spawns (`updatedInput` excludes Task/Agent per Claude Code docs) and `SubagentStart` has
no decision control, so deny is the only deterministic lever for this surface. Full
rationale: full doc.

**HONEST RESIDUAL (§10 — NOT hard-gated).** The gate only inspects the Task/Agent tool
surface. It CANNOT reach Workflow-inline `agent({model})`, `spawn_task`, `CronCreate`/
scheduled-tasks/RemoteTrigger, or the workstreams-ui reconciler headless spawn. For those:
when authoring a Workflow, set `model:`/`effort:` on every agent() call explicitly; when
you spawn_task or schedule, name the model in-prompt. No runtime layer-1 default exists
for these paths today — full doc for detail.
