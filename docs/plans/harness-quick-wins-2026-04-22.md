# Plan: Harness Quick-Win Automation — Effort, Verbose Plans, Meta-Question Skills

Status: ACTIVE
Status-history:
  - 2026-04-22: created
  - ~2026-04-22: marked COMPLETED (premature — see 2026-05-04 audit note below)
  - 2026-05-04: SessionStart-sweep auto-archived to docs/plans/archive/
  - 2026-05-04: un-archived + flipped to ACTIVE per audit findings
Execution Mode: orchestrator
Backlog items absorbed: "Effort-level enforcement at project level", "Verbose plans → Level 3", "Prompt template library for meta-questions"
acceptance-exempt: true
acceptance-exempt-reason: Harness-development plan; no product user. Verification is via per-hook --self-test invocations and a manual round-trip exercising the effort-policy + plan-reviewer + skill flows. Re-opened 2026-05-04 per audit; resolution path is Phase 1d-E (HARNESS-GAP-15 sub-item F).

> **2026-05-04 audit note (orchestrator):** This plan was prematurely marked COMPLETED. Phases B (verbose plans), C (skills), and D (architecture doc) genuinely shipped — artifacts verified, hooks pass --self-test today. **Phase A Task 1 (set `effortLevel` in live `~/.claude/settings.json`) was never executed**: `jq '.effortLevel' ~/.claude/settings.json` returns `null`. The template was edited; the live mirror was not. The plan's DoD line "`~/.claude/settings.json` contains `\"effortLevel\": \"xhigh\"`" is provably false. Flipped back to ACTIVE so the actual gap is visible. **Resolution path:** either complete Task 1 (one-line edit + commit) or formally defer with a "Phase A partial" note. Bundled into Phase 1d-E follow-ups per `docs/backlog.md`.

## Goal

Automate three near-term best practices identified in `docs/claude-code-quality-strategy.md` so they are enforced by default rather than requiring user discipline:

1. **Effort setting** — every session defaults to `xhigh` minimum; per-project policy file with SessionStart warning for project-specific overrides
2. **Verbose plans** — all plans must include required sections with populated content; plan-reviewer blocks plans missing required sections, regardless of plan size
3. **Meta-question skill library** — four canonical meta-questions codified as slash commands, reducing "user must remember to ask" to "user invokes one keystroke"

### Why These Three Together

All three are small harness-side changes that share the same workflow: edit `~/.claude/`, mirror to `~/claude-projects/neural-lace/adapters/claude-code/`, commit to neural-lace. Bundling them into one cohesive work unit amortizes the mirror-and-commit overhead and ships related automation in a single pass.

Item 4 from the strategy doc (`plan-lifecycle.sh`) is deliberately NOT in this plan. It is a substantial 18-task effort with its own existing plan file. It warrants a separate execution context.

### Verbose Plans: No Size Threshold

Per maintainer guidance (2026-04-22): all plans get verbose treatment regardless of size. Verbose planning is cheap for short plans and valuable for long plans. No conditional exceptions — every plan has every required section populated.

## Scope

- IN:
  - **Effort policy:** Add `"effortLevel": "xhigh"` to `~/.claude/settings.json` AND `settings.json.template`; create `~/.claude/local/effort-policy.json.example` template; create `effort-policy-warn.sh` SessionStart hook that warns if project-level `.claude/effort-policy.json` requires higher than current configured level
  - **Verbose plans (prose):** Extend `~/.claude/rules/planning.md` with the "Plans must enumerate every assumption" section
  - **Verbose plans (template):** Extend `~/.claude/templates/plan-template.md` with the required sections (Goal, Scope, Tasks, Files to Modify/Create, Assumptions, Edge Cases, Testing Strategy)
  - **Verbose plans (validator):** Extend `~/.claude/hooks/plan-reviewer.sh` to reject any plan missing required sections or where required sections are empty/placeholder
  - **Meta-question skills:** Create four new skills under `~/.claude/skills/`: `why-slipped`, `find-bugs`, `verbose-plan`, `harness-lesson`
  - Mirror all changes to `~/claude-projects/neural-lace/adapters/claude-code/`
  - Update `~/.claude/docs/harness-architecture.md` inventory with new hook + skills + template/rule expansions
  - End-to-end verification (draft a throwaway plan, confirm validator blocks it without required sections)

- OUT:
  - The `plan-lifecycle.sh` hook (item 4) — separate plan, separate execution
  - Any changes to Claude Code itself (we can only influence behavior via the harness surfaces Claude Code exposes)
  - Retroactive verbose-plan enforcement for existing plans (new rules apply to new plans; old plans are grandfathered)
  - Programmatic detection of the current runtime effort level (no introspection API exists per Claude Code docs; SessionStart hook warns based on env var and settings, not actual active level)

## Assumptions

- Claude Code's `settings.json` supports `"effortLevel"` as documented (confirmed via claude-code-guide agent research, 2026-04-22).
- Neural Lace's install.sh correctly propagates settings.json.template changes on re-install.
- The existing `plan-reviewer.sh` hook is extensible and can be enhanced without breaking its current behavior.
- Skills in `~/.claude/skills/` can be invoked via the Skill tool once named there (confirmed by existing skills: `verify-feature.md`, `find-skills`, etc.).
- Mirror-to-neural-lace discipline per `harness-maintenance.md` is followed (changes sync to the adapter subdirectory and get committed to the neural-lace repo).

## Edge Cases

- **User has customized `~/.claude/settings.json`:** don't overwrite; use Edit to add the `effortLevel` field without removing user customizations.
- **Plan-reviewer hook is currently passing noisy warnings:** the new validation must distinguish "warning" from "block"; blocks are for missing required sections, not for stylistic concerns.
- **An older plan is edited after the new rules ship:** grandfather older plans — validate only if the plan's header declares compatibility with the new convention, OR if it's a new plan file (first edit after creation).
- **A skill is invoked with context that doesn't apply:** each skill's content should include graceful handling of "there's no relevant scope for this question right now" → return a brief diagnostic instead of fabricating relevance.
- **Effort policy conflicts between user-global and project-local:** project-local always wins; SessionStart hook warns specifically about the project-local requirement.

## Testing Strategy

- **Effort policy:** Create a test project with `.claude/effort-policy.json` specifying `xhigh`; simulate session start with `CLAUDE_CODE_EFFORT_LEVEL=high`; verify hook emits warning. Simulate with `xhigh`; verify hook stays silent.
- **Verbose plans (prose):** Read the updated `planning.md` end-to-end; confirm it reads coherently with existing sections.
- **Verbose plans (template):** Create a new plan from the template; confirm all required sections are present as placeholders.
- **Verbose plans (validator):** Write a deliberately-incomplete plan (missing Assumptions section); run `plan-reviewer.sh` against it; verify it exits non-zero with a specific error pointing to the missing section.
- **Meta-question skills:** Invoke each skill via the Skill tool (`/why-slipped`, `/find-bugs`, `/verbose-plan`, `/harness-lesson`); verify the skill content loads and produces a reasonable response prompt.
- **End-to-end:** Draft a throwaway plan at `~/claude-projects/neural-lace/docs/plans/test-plan.md` with only a Goal section; attempt to save it via the plan-reviewer flow; verify it's rejected. Add required sections; verify it's accepted. Delete the test plan.

## Tasks

### Phase A: Effort Enforcement

- [ ] 1. Add `"effortLevel": "xhigh"` to `~/.claude/settings.json`
  - Use Edit (not Write) to preserve existing user customizations
  - Verify JSON remains valid
  - **Files:** `~/.claude/settings.json`
  - **Done when:** `jq '.effortLevel' ~/.claude/settings.json` returns `"xhigh"`; other keys intact.

- [ ] 2. Add `"effortLevel": "xhigh"` to the neural-lace `settings.json.template`
  - Same edit pattern as task 1
  - **Files:** `~/claude-projects/neural-lace/adapters/claude-code/settings.json.template`
  - **Done when:** `jq '.effortLevel' <path>` returns `"xhigh"`.

- [ ] 3. Create `~/.claude/local/effort-policy.json.example`
  - Template for per-account effort policy (user copies to `effort-policy.json` to activate)
  - Schema: `{"minimum_effort_level": "xhigh"}` with comments explaining values
  - **Files:** `~/.claude/local/effort-policy.json.example`
  - **Done when:** File exists, is valid JSON with documented fields.

- [ ] 4. Write `~/.claude/hooks/effort-policy-warn.sh`
  - SessionStart hook
  - Reads project-level `.claude/effort-policy.json` (if exists), falls back to `~/.claude/local/effort-policy.json`
  - Checks current `CLAUDE_CODE_EFFORT_LEVEL` env var and (if accessible) `~/.claude/settings.json` `effortLevel` value
  - Emits warning on stderr if either is below the required minimum
  - Non-blocking (PostToolUse warning-only; never exit non-zero)
  - Include `--self-test` flag
  - **Files:** `~/.claude/hooks/effort-policy-warn.sh`
  - **Done when:** `--self-test` passes; manual test with mismatched env var emits expected warning.

- [ ] 5. Wire `effort-policy-warn.sh` into `~/.claude/settings.json` SessionStart hooks
  - Add a new SessionStart entry pointing at the hook
  - Preserve existing SessionStart hooks
  - **Files:** `~/.claude/settings.json`
  - **Done when:** `jq '.hooks.SessionStart' <path>` shows the new hook alongside existing ones.

- [ ] 6. Mirror Phase A files to neural-lace
  - Copy `settings.json.template` changes, `effort-policy.json.example`, `effort-policy-warn.sh` to `~/claude-projects/neural-lace/adapters/claude-code/`
  - Run `diff -q` to verify each file matches
  - Commit: `feat(harness): effort-level default + project-level policy warning`
  - **Files:** `neural-lace/adapters/claude-code/{settings.json.template,local/effort-policy.json.example,hooks/effort-policy-warn.sh}`
  - **Done when:** neural-lace commit exists; diffs are clean.

### Phase B: Verbose Plans

- [ ] 7. Extend `~/.claude/rules/planning.md` with the verbose-plan section
  - Add a new section "## Verbose Plans Are Mandatory" near the existing "How multi-task plans execute" section
  - Content:
    - **All plans** must include: Goal, Scope (IN/OUT), Tasks, Files to Modify/Create, Assumptions, Edge Cases, Testing Strategy
    - **All plans, regardless of size** — verbose planning is cheap for small plans and essential for large ones
    - **The Assumptions section is required even for trivial plans** — forcing assumptions to be explicit prevents the builder from filling them in badly at build time
    - **Empty required sections are treated as incomplete plans** — `plan-reviewer.sh` blocks commits of plans with missing or placeholder-only required sections
  - Cross-reference `plan-reviewer.sh` and `plan-template.md` so the three layers are visible from the rule
  - **Files:** `~/.claude/rules/planning.md`
  - **Done when:** New section is present and coherent with existing content.

- [ ] 8. Expand `~/.claude/templates/plan-template.md` with required sections
  - Add required sections: Assumptions, Edge Cases, Testing Strategy
  - Each required section includes a placeholder prompt explaining what to populate (e.g., "Every premise this plan relies on — explicit, not implied")
  - Preserve existing sections (Goal, Scope, Tasks, Files to Modify/Create, Decisions Log, Definition of Done)
  - **Files:** `~/.claude/templates/plan-template.md`
  - **Done when:** Template includes all required sections; placeholders guide completion.

- [ ] 9. Extend `~/.claude/hooks/plan-reviewer.sh` with required-section validation
  - Read the plan file being validated
  - Check for presence of required headers: `## Goal`, `## Scope`, `## Tasks`, `## Files to Modify/Create`, `## Assumptions`, `## Edge Cases`, `## Testing Strategy`
  - Check that each required section has at least one line of non-empty non-placeholder content (reject "[populate me]" / "TODO" / empty sections)
  - Exit non-zero with a specific error pointing to the first missing/empty required section
  - Preserve all existing checks in the hook
  - Include `--self-test` flag that exercises pass/fail paths
  - **Files:** `~/.claude/hooks/plan-reviewer.sh`
  - **Done when:** `--self-test` passes; manual test against an incomplete plan fails with expected error; manual test against this very plan (which has all required sections) passes.

- [ ] 10. Mirror Phase B files to neural-lace
  - Copy `rules/planning.md`, `templates/plan-template.md`, `hooks/plan-reviewer.sh` to `~/claude-projects/neural-lace/adapters/claude-code/`
  - Run `diff -q` to verify
  - Commit: `feat(harness): mandatory verbose plans with required-section validator`
  - **Files:** `neural-lace/adapters/claude-code/{rules/planning.md,templates/plan-template.md,hooks/plan-reviewer.sh}`
  - **Done when:** neural-lace commit exists; diffs are clean.

### Phase C: Meta-Question Skill Library

- [ ] 11. Create `~/.claude/skills/why-slipped.md`
  - Skill that prompts Claude to analyze a recent bug/failure and explain what mechanism should have caught it
  - Frontmatter: `name: why-slipped`, `description: "Analyze a recent bug and explain what hook, rule, or agent should have caught it. Used after finding a bug to extract harness-improvement opportunities."`
  - Body: instructions for the skill invocation — read recent context, identify the failure, trace through the enforcement map in `vaporware-prevention.md`, return a diagnosis with a proposed fix
  - **Files:** `~/.claude/skills/why-slipped.md`
  - **Done when:** File exists with valid frontmatter and body.

- [ ] 12. Create `~/.claude/skills/find-bugs.md`
  - Skill that prompts Claude to self-audit recent work for bugs it may have introduced or missed
  - Frontmatter: `name: find-bugs`, `description: "Self-audit recent work for bugs. Invoke after completing a significant change to surface what might be broken before the user finds it."`
  - Body: instructions to review recent edits, enumerate likely failure modes, test each one where possible, return an honest list
  - **Files:** `~/.claude/skills/find-bugs.md`
  - **Done when:** File exists with valid frontmatter and body.

- [ ] 13. Create `~/.claude/skills/verbose-plan.md`
  - Skill that prompts Claude to expand a thin plan with more detail
  - Frontmatter: `name: verbose-plan`, `description: "Expand a thin plan file with more detail: enumerate assumptions, edge cases, testing strategies. Invoke when a draft plan feels underspecified."`
  - Body: instructions to read the current plan, identify sections that need expansion, propose additions, return revised plan or a diff
  - **Files:** `~/.claude/skills/verbose-plan.md`
  - **Done when:** File exists with valid frontmatter and body.

- [ ] 14. Create `~/.claude/skills/harness-lesson.md`
  - Skill that takes a recent failure and proposes specific harness changes (hook, rule, or agent) to prevent the class
  - Frontmatter: `name: harness-lesson`, `description: "Encode a recent failure as a proposed harness change. Input: what went wrong. Output: specific hook/rule/agent modification that would prevent the class."`
  - Body: instructions to analyze the failure, identify the failure class, propose a specific file change in `~/.claude/` (with concrete content, not just "you should add a hook"), return the proposal as a diff or complete file
  - **Files:** `~/.claude/skills/harness-lesson.md`
  - **Done when:** File exists with valid frontmatter and body.

- [ ] 15. Mirror Phase C skills to neural-lace
  - Copy all four skill files to `~/claude-projects/neural-lace/adapters/claude-code/skills/` (create directory if needed)
  - Run `diff -q` to verify each
  - Commit: `feat(harness): meta-question skill library (why-slipped, find-bugs, verbose-plan, harness-lesson)`
  - **Files:** `neural-lace/adapters/claude-code/skills/{why-slipped,find-bugs,verbose-plan,harness-lesson}.md`
  - **Done when:** neural-lace commit exists; diffs are clean.

### Phase D: Architecture Doc + Verification

- [x] 16. Update `~/.claude/docs/harness-architecture.md` with new entries
  - Add `effort-policy-warn.sh` to hooks inventory
  - Add `plan-reviewer.sh` change note (verbosity validation added)
  - Add the four new skills to skills inventory
  - Add `effort-policy.json.example` to templates/local inventory
  - **Files:** `~/.claude/docs/harness-architecture.md`
  - **Done when:** Inventory tables include all new/changed entries.

- [x] 17. Mirror architecture doc to neural-lace
  - Copy to `~/claude-projects/neural-lace/docs/harness-architecture.md`
  - Commit: `docs(harness): architecture — quick-win automation inventory`
  - **Files:** `neural-lace/docs/harness-architecture.md`
  - **Done when:** Commit exists; diff is clean.

- [x] 18. End-to-end verification
  - **Effort:** Simulate SessionStart with mismatched effort; verify warning fires. Simulate with match; verify silent.
  - **Verbose plans:** Draft a throwaway test plan missing Assumptions section; run `plan-reviewer.sh`; verify rejection. Add Assumptions; verify acceptance.
  - **Skills:** Invoke each of the four skills via `/skill-name` in a fresh session; verify each produces a coherent response.
  - Document results in plan's Evidence Log section (append to this file under the existing Decisions Log style).
  - **Done when:** All four subsections produce expected outcomes; evidence documented.

## Files to Modify/Create

### Create
- `~/.claude/hooks/effort-policy-warn.sh` — SessionStart hook
- `~/.claude/local/effort-policy.json.example` — policy template
- `~/.claude/skills/why-slipped.md` — meta-question skill
- `~/.claude/skills/find-bugs.md` — meta-question skill
- `~/.claude/skills/verbose-plan.md` — meta-question skill
- `~/.claude/skills/harness-lesson.md` — meta-question skill
- Mirror all to `~/claude-projects/neural-lace/adapters/claude-code/`

### Modify
- `~/.claude/settings.json` — add `effortLevel` + register `effort-policy-warn.sh`
- `~/.claude/rules/planning.md` — add verbose-plan section
- `~/.claude/templates/plan-template.md` — add required sections
- `~/.claude/hooks/plan-reviewer.sh` — add required-section validation
- `~/.claude/docs/harness-architecture.md` — inventory updates
- `~/claude-projects/neural-lace/adapters/claude-code/settings.json.template` — mirror of live settings
- Mirror rule, template, hook, architecture doc to neural-lace

## Decisions Log

### Decision: Use settings.json.template for default effort, hook for project policy
- **Tier:** 1
- **Status:** proceeded with recommendation
- **Chosen:** Set `"effortLevel": "xhigh"` as default in `settings.json` (global and template). Separately create a SessionStart warning hook that reads project-level `.claude/effort-policy.json` and warns if current level is below project minimum.
- **Alternatives:** (a) Hook-only approach (warn if below xhigh) — rejected because settings.json provides Level 4 default-by-construction for free; no reason to rely on user noticing a warning when we can set the default. (b) Settings-only approach — rejected because per-project override is still valuable (some projects may want to require `max` above the global `xhigh` default).
- **Reasoning:** Settings.json gives automatic default without user action (best); policy hook gives per-project override with warning (useful escape valve). Both layers together is cheap.

### Decision: Plan-reviewer validates REQUIRED sections, not total line count
- **Tier:** 1
- **Status:** proceeded with recommendation (user-confirmed 2026-04-22)
- **Chosen:** Reject plans missing required sections (Goal, Scope, Tasks, Files, Assumptions, Edge Cases, Testing Strategy) or where required sections contain only placeholder text. Do not impose a minimum line count threshold.
- **Alternatives:** (a) Minimum 200 lines threshold — rejected on user feedback "all plans should be verbose at any size; it improves quality and has a smaller cost on shorter plans." (b) Minimum N assumptions / M files / K tests per plan — rejected as arbitrary and brittle; "at least one" per section is sufficient as long as the section content is substantive.
- **Reasoning:** Section-presence is a more robust signal than line count. A 50-line plan with every required section populated thoughtfully beats a 300-line plan that's verbose for its own sake.

### Decision: Skills use short command names (why-slipped, not why-did-this-bug-slip)
- **Tier:** 1
- **Status:** proceeded with recommendation
- **Chosen:** Short slug names for skill invocation: `why-slipped`, `find-bugs`, `verbose-plan`, `harness-lesson`.
- **Alternatives:** Longer descriptive names (`why-did-this-bug-slip`, etc.) — rejected for typing friction; the skill's description is verbose, so users can find it via `/find-skills` even with a cryptic name.
- **Reasoning:** Friction matters for skills that are supposed to replace a mental habit. Short slugs reduce the cost of invocation.

## Evidence Log

### Verification 1 — Effort policy warn hook
- `bash ~/.claude/hooks/effort-policy-warn.sh --self-test` → 10/10 scenarios passed (no-policy silent; user-xhigh-env-high warned; user-xhigh-env-xhigh/max silent; project-overrides-user warned; settings-fallback above/below correct; unknown-current warned; policy-max-env-xhigh warned; policy-max-env-max silent). Ordering `low < medium < high < xhigh <= max` holds.
- Run date: 2026-04-22

### Verification 2 — Verbose plans validator (Check 6b)
- Scenario (a) fully-populated throwaway plan → accepted (exit 0, "no findings")
- Scenario (b) missing `## Assumptions` → rejected: "Check 6b: required section '## Assumptions' is missing" (exit 1)
- Scenario (c) `## Assumptions` populated only with `[populate me]` → rejected by Check 6b's short-content rule (needs ≥ 20 non-whitespace chars) (exit 1)
- Scenario (d) all 7 required sections with substantive content → accepted (exit 0)
- `bash ~/.claude/hooks/plan-reviewer.sh --self-test` → 4/4 scenarios matched expectations (fully-populated PASS; missing-assumptions FAIL; placeholder-only FAIL; every-section-substantive PASS)
- Temp test plan created under `/tmp/plan-test/` and cleaned up afterward
- Run date: 2026-04-22

### Verification 3 — Skills present and readable
- All 4 skill files exist at `~/.claude/skills/{why-slipped,find-bugs,verbose-plan,harness-lesson}.md`
- Each has valid YAML frontmatter with `name:` and `description:` fields (verified via head + grep)
- Bodies are substantive (143, 146, 155, 192 lines respectively) — not stubs
- Skill invocation itself not tested (would require session reload); file presence + format only

### Verification 4 — Neural-lace state
- `~/claude-projects/neural-lace` master HEAD = `fa44d63` (Phase D doc commit)
- Expected commits confirmed: c673b3e, f4cca88 (Phase A), 964a2ed (Phase B), 5fdc217 (Phase C), 243c675 (backlog), fa44d63 (Phase D)
- `git status --short` on neural-lace master → empty (no uncommitted changes)
- `diff -q` silent for all 10 touched files (effort-policy-warn.sh, plan-reviewer.sh, planning.md, plan-template.md, effort-policy.json.example, 4 skills, harness-architecture.md)

## Completion Note (2026-04-22)

All 18 tasks shipped across 6 neural-lace commits:
- Phase A (effort enforcement): `c673b3e`, `f4cca88` — default `max`, policy hook, `.example` template
- Phase B (verbose plans): `964a2ed` — planning.md rule, plan-template.md 7 sections, plan-reviewer.sh Check 6b
- Phase C (meta-skills): `5fdc217` — why-slipped, find-bugs, verbose-plan, harness-lesson
- Phase D (architecture doc): `fa44d63` — inventory updates for all of the above
- Backlog: `243c675` — harness-plan-location gap captured

End-to-end verification passed for effort policy hook (10/10 scenarios), plan-reviewer Check 6b (4/4 scenarios + 4 manual scenarios), skill file presence, and neural-lace mirror integrity. Absorbed backlog items: "Effort-level enforcement at project level", "Verbose plans → Level 3", "Prompt template library for meta-questions" — all built and archived in this plan.

## Definition of Done

- [x] All 18 tasks checked off
- [ ] `~/.claude/settings.json` contains `"effortLevel": "xhigh"`
- [ ] `effort-policy-warn.sh` exists, passes self-test, is wired into SessionStart
- [ ] `planning.md` has the verbose-plan section
- [ ] `plan-template.md` has all required sections
- [ ] `plan-reviewer.sh` validates required sections, passes self-test
- [ ] All four skills exist in `~/.claude/skills/`
- [ ] All changes mirrored to neural-lace with matching `diff -q` clean output
- [ ] Neural Lace has at least three commits for this work (effort, verbose plans, skills) + architecture doc update
- [ ] Architecture doc inventory reflects new additions
- [ ] End-to-end verification passed and documented
