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
- **pt/master reconcile (deferred to a focused session).** pt/master is behind-14/ahead-5 of local; its 14 commits include a NEW `architecture-reviewer` agent whose `.md` is UNPINNED. When that merge happens it MUST pin `architecture-reviewer.md` `model: fable` (category: design) AND add it to `config/model-policy.json`, or `check_model_pins` REDs and the gate blocks its no-model spawns. Blocker: `git fetch github-pt` currently fails on access rights (work-account SSH).
- **Built-in-type strictness = operator decision (default: strict).** The gate blocks no-model spawns of Claude Code built-ins (`Explore`/`Plan`/`general-purpose`/`claude`) — they have no `.md` to pin, remedy = pass `model:`. Kept strict per the directive; operator may relax (see NEEDS-YOU).
- **Evidence-bar evasion-by-omission (nl-issue filed).** `check_new_gate_evidence_bar` skips manifest entries lacking `added_after`; 32 legacy blocking gates lack it → a future gate could evade the §10 bar. Needs a backfill + its own review.

## Closure Contract
- **Commands that run:** `bash adapters/claude-code/hooks/model-pin-gate.sh --self-test`; `bash adapters/claude-code/scripts/harness-doctor.sh --check model-pins` (or the quick doctor); `jq -r '.agents' adapters/claude-code/config/model-policy.json`; `grep -L '^model:' adapters/claude-code/agents/*.md` (must be empty).
- **Expected outputs:** gate self-test all-pass (blocks a no-model unknown-type spawn; allows a pinned spawn; allows an explicit-model spawn); every agents/*.md has `model:`; doctor check green.
- **On-disk artifact location:** `config/model-policy.json`, `hooks/model-pin-gate.sh`, the 24 agent files; evidence in this plan's `## Evidence Log`.
- **Done when:** the gate + frontmatter + doctor check are on master (both remotes), live-synced, self-tests green, harness-reviewer PASS/CONDITIONAL-PASS with findings fixed.

## Evidence Log

### Build (Tasks 1–4)
- Tasks 1–3 built + merged to master @ `f97bfb8` (policy `fb762b9`, frontmatter `c5041eb`, gate+wiring `1d80926`). Gate self-test 9/9; all 24 agents pinned.
- Task 4 (`check_model_pins` in harness-doctor.sh) built this session. Bug caught by its own GREEN self-test fixture: Windows `jq` emits policy keys with trailing `\r`, so every valid model was flagged invalid — fixed with `tr -d '\r'`. Doctor self-test 104/104.

### harness-review (Task 5) — verdict REJECT → all findings resolved
Reviewer ran on **opus** (fable hit its monthly spend limit mid-review — the `fable → opus` reviewer chain executing as designed). Verdict REJECT with 3 Critical/Major + 2 lesser. Resolutions:

| # | Sev | Finding (PROVEN unless noted) | Resolution | Verified |
|---|-----|-------------------------------|------------|----------|
| C1 | Critical | manifest `model-pin` entry lacked `added_after`+3 §10 fields; `check_new_gate_evidence_bar` `continue`s past entries with no `added_after` → newest blocking gate structurally EVADED the §10 check | Added `added_after:2026-07` + golden_scenario + fp_expectation + retirement_condition to the manifest entry | node evidence-bar check: all fields present ✓ |
| C1-gen | — | class: any new blocking gate can evade by omitting `added_after` (32 legacy blocking entries lack it → can't assert presence without a backfill) | Filed nl-issue (separate plan — needs backfill + own review); NOT bundled | nl-issue recorded |
| C3 | Critical (HYPOTHESIZED) | claimed the Task/Agent `model` spawn-param may not exist → remedy #1 inert, built-in types deadlock | **REFUTED**: Agent-tool schema documents `model`; used in-session (reviewer dispatched with `model:opus`). Real edge kept: `fork` can't be pinned/overridden → **exempted** in the gate | gate self-test: fork → allow ✓ |
| M1 | Major | gate resolved agent by filename only; `domain-expert-tester`/`ux-end-user-tester`/`audience-content-reviewer` are spawned by DISPLAY name → 3 pinned fable agents wrongly BLOCKED | gate now resolves by filename slug OR `name:` frontmatter (`_resolve_agent_def`) | gate self-test: "Display Agent" → allow ✓ |
| Minor | Minor | `^model:` matched anywhere (body line = false pin) in both gate + doctor | both now fence-scoped to the first `---…---` block (pure-bash, CRLF-safe) | gate + doctor self-test: body-`model:` → BLOCK/RED ✓ |
| Major | Major | gate self-test missed the real FP surface (display-name, fork, fence) | added 3 gate scenarios + 1 doctor scenario | gate 12/12; doctor sweep green |

- **Confirmed-good by reviewer (no change):** input-shape parsing (matches sibling gates), fail-open scoped to internal limits only, honest residual documented honestly in doctrine+manifest+policy, live `~/.claude/agents` resolves (24 pinned).
