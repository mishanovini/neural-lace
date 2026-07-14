# Plan: Model-Assignment Enforcement at Session/Subagent Initiation

Status: ACTIVE
Mode: code
lifecycle-schema: v2
acceptance-exempt: true  # harness-internal enforcement; no user-facing product surface
Backlog items absorbed: none

## Goal
Kill silent model-inheritance. Operator directive: "every session and sub-agent must ALWAYS be
assigned an appropriate model at initiation, without exception — enforce, don't inherit by default."
EVIDENCE (workflow wf_5331f63a-8ff): omitting `model` = inherit the main-loop model; on a Fable
session every un-pinned spawn runs Fable (2026-07-11 incident: ~1.7M tokens). 22 of 24 `agents/*.md`
omit `model:`. The "already designed" mechanism was only an unbuilt proposal
(`docs/harness-improvements/model-pin-mandatory-gate.md`). No gate inspects a spawn's model today.

## Category → model policy (OPERATOR-SET 2026-07-14; Fable = premium tier; chains = primary→fallback)
- Adversarial reviewers / verifiers → **fable, opus**
- Design / planning → **fable, opus**
- Explore / research / cheap-mechanical → **haiku, sonnet**
- plan-phase-builder / build → **sonnet**
- Interactive main / orchestrator → operator launch choice (explicit; never auto-downgraded)
- spawn_task / cron / cloud → explicit per-task (no gate reaches these — convention + lint)
RULE: explicit always; **Fable never reached by inherit/default — only explicit pin.**

## Files to Modify/Create
- `adapters/claude-code/config/model-policy.json` — NEW: the single source of truth (agent-name → ordered model chain + category defaults).
- `adapters/claude-code/agents/*.md` (24 files) — add `model:` frontmatter mirroring the policy (currently 22 omit it).
- `adapters/claude-code/hooks/model-pin-gate.sh` — NEW: PreToolUse on Task|Agent; block a spawn whose resolved model is empty AND whose subagent_type has no policy entry (force explicit / policy default; never inherit). `--self-test`.
- `adapters/claude-code/work-shapes/build-agent.md` — tighten the authoring check from `^(model|tools):` to require `^model:`.
- `adapters/claude-code/scripts/harness-doctor.sh` — add a check: FAIL if any agents/*.md lacks `model:` or names a model absent from the policy.
- `adapters/claude-code/doctrine/model-selection.md` — NEW compact: the policy + the honest residual (Workflow-inline agent() / spawn_task / cron can't be hard-gated → convention + lint).
- `adapters/claude-code/settings.json.template` — wire model-pin-gate.sh on PreToolUse Task|Agent.
- `adapters/claude-code/manifest.json` — register the gate + doctor check.
- `docs/plans/model-enforcement-2026-07-14.md` — this plan.

## Tasks
- [ ] 1. Author `model-policy.json` (source of truth) + `model-selection.md` doctrine (policy + honest residual). Verification: mechanical
- [ ] 2. Add `model:` frontmatter to all 24 `agents/*.md` per the policy; tighten `build-agent.md` check to require `^model:`. Verification: mechanical
- [ ] 3. Build `model-pin-gate.sh` (PreToolUse Task|Agent; blocks silent-inherit; reads subagent_type+model against the policy) with `--self-test`; wire in settings template; register in manifest. Verification: mechanical
- [ ] 4. Add the harness-doctor check (every agent pinned + model ∈ policy); register. Verification: mechanical
- [ ] 5. harness-review the whole mechanism (Mechanism/Pattern split; FP risk; honest residual on ungate-able paths); address findings. Verification: mechanical

## Non-goals / follow-ups
- The runtime layer-1 policy default for Workflow-inline `agent()` / spawn_task / cron (no repo control point) — doctrine convention + lint only; nl-issue if a runtime hook becomes available.
- The evidence-before-fix commit gate (Directive 1) — SEPARATE plan `evidence-before-fix-gate-2026-07-14.md`.

## Closure Contract
- **Commands that run:** `bash adapters/claude-code/hooks/model-pin-gate.sh --self-test`; `bash adapters/claude-code/scripts/harness-doctor.sh --check model-pins` (or the quick doctor); `jq -r '.agents' adapters/claude-code/config/model-policy.json`; `grep -L '^model:' adapters/claude-code/agents/*.md` (must be empty).
- **Expected outputs:** gate self-test all-pass (blocks a no-model unknown-type spawn; allows a pinned spawn; allows an explicit-model spawn); every agents/*.md has `model:`; doctor check green.
- **On-disk artifact location:** `config/model-policy.json`, `hooks/model-pin-gate.sh`, the 24 agent files; evidence in this plan's `## Evidence Log`.
- **Done when:** the gate + frontmatter + doctor check are on master (both remotes), live-synced, self-tests green, harness-reviewer PASS/CONDITIONAL-PASS with findings fixed.

## Evidence Log
- (filled at close)
