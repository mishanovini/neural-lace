# Planning & Decision Protocol

## When to Plan
For tasks involving architectural decisions, non-obvious multi-file interactions, or work > ~15 minutes: enter plan mode. For simple single-file changes, bug fixes with obvious solutions, or docs: proceed directly.

## Two modes of plan: `code` vs `design`

Every plan declares a **Mode** in its header:

- **`Mode: code`** (default). Code-level work: bug fixes, UI changes, refactors, test additions, isolated feature work. Iteration cost is low, iterate-and-observe is appropriate. The standard plan template (Goal, Scope, Tasks, etc.) is sufficient.

- **`Mode: design`**. System-design work where iteration cost is high and failures compound. Required for CI/CD workflows, database migrations, infrastructure config, deployment systems, multi-service integrations. Design-mode plans MUST include a "Systems Engineering Analysis" section with 10 sub-sections (Outcome, End-to-end trace, Interface contracts, Environment, Authentication, Observability, Failure modes, Idempotency, Load/capacity, Decision records & runbook).

**How to decide:** if any of these are true, use `Mode: design`:
- Editing `.github/workflows/*.yml`, migrations, `vercel.json`, `Dockerfile`, or similar infra files
- Integrating a third-party tool you haven't used before in this project
- Plan has more than 3 state transitions in its flow
- Iteration costs > 5 minutes or real money (CI builds, API calls, deployment)
- Other systems/teams will depend on the output

See `~/.claude/rules/design-mode-planning.md` for the full protocol, the 10 required sections, and what each requires.

**Enforcement (hook-backed):**
- `plan-reviewer.sh` enforces section presence and substance for `Mode: design` plans.
- `systems-designer` agent MUST pass the plan before implementation (parallel to how `ux-designer` gates UI plans).
- `systems-design-gate.sh` PreToolUse hook blocks edits to design-mode files (workflows, migrations, etc.) unless an active `Mode: design` plan exists.
- Escape hatch: `Mode: design-skip` with a short justification allows trivial edits (version bumps, typo fixes) without the full 10-section treatment, while leaving an auditable record.

## Verbose Plans Are Mandatory

**Every plan file must include all seven required sections, populated with substantive, plan-specific content.** The required sections are:

1. `## Goal` — what we're building and why
2. `## Scope` — explicit IN and OUT clauses
3. `## Tasks` — the task list (checkboxes)
4. `## Files to Modify/Create` — every file this plan touches, with a brief reason
5. `## Assumptions` — every premise this plan relies on, made explicit rather than implied
6. `## Edge Cases` — the corner cases and failure modes this plan must handle
7. `## Testing Strategy` — how each task will be verified (unit, integration, runtime)

**No size threshold.** Verbose planning is cheap for small plans and essential for large ones. A 50-line plan that fills every section thoughtfully is better than a 300-line plan that pads content for its own sake. Do not skip sections because a plan "feels small" — the cost of populating Assumptions on a trivial plan is one minute; the benefit of forcing assumptions to be explicit upfront prevents the builder from filling them in badly at build time.

**The Assumptions section is required even for trivial plans.** This is the most frequently-skipped section and the most valuable one. If you genuinely cannot think of an assumption, write "Assumes the existing X API behaves as documented" — but do not omit the section. Forcing explicit assumptions upfront surfaces the hidden premises that cause builds to fail.

**Empty or placeholder-only required sections are blocked.** `plan-reviewer.sh` enforces both presence (the heading must exist) and substance (the section must contain at least 20 non-whitespace characters of non-placeholder content). Sections consisting solely of `[populate me]`, `[TODO]`, `TODO`, `...`, or literal template placeholder text are rejected. Fill the sections with real, plan-specific content before marking the plan ACTIVE.

**Cross-references:**
- Template: `~/.claude/templates/plan-template.md` includes all seven required sections with placeholder prompts explaining what each should contain.
- Validator: `~/.claude/hooks/plan-reviewer.sh` performs the mechanical check at plan-edit time. Run with `--self-test` to exercise pass/fail scenarios.

## How multi-task plans execute: orchestrator pattern

**For any plan with more than one task, the main session orchestrates and dispatches build work to `plan-phase-builder` sub-agents — it does NOT do the build work itself.** This keeps the main session's context from accumulating 200+ tool uses of raw build detail across a long plan, which is a quality-of-life improvement for extended autonomous work. (Historical note: the 2026-04-14 vaporware failures were caused by self-enforcement gaps in verification, not by context accumulation — those are addressed by the hook-enforced Gen 4 mechanisms. The orchestrator pattern is a separate improvement.)

See `~/.claude/rules/orchestrator-pattern.md` for the full protocol: when to use it, the dispatch contract, the builder output contract, and anti-patterns.

Plan files should declare `Execution Mode: orchestrator` in their header (default for multi-task plans). The template at `~/.claude/templates/plan-template.md` includes this.

The `task-verifier` mandate (only task-verifier can flip checkboxes) is unchanged — builders invoke task-verifier, orchestrator trusts the verdict. The anti-vaporware rule, runtime verification requirements, evidence block format, and tool-call-budget all still apply; they now apply to the builder's scope rather than the main session's.

## Philosophy
**Planning is where human judgment matters most. Building is where autonomy matters most.** Invest heavily in planning so implementation runs autonomously.

### Completeness over speed — always

Never prioritize speed over completeness. When a user asks for autonomous execution, they are authorizing you to work without pausing — they are NOT authorizing you to cut scope to finish faster. "Finish the plan" means every task in every phase, not "the critical path to a stopping point I pick."

**Completeness INCLUDES runtime verification.** A task is not complete when the code exists — it is complete when the user-observable outcome has been verified at runtime. See `~/.claude/rules/vaporware-prevention.md` for the full anti-vaporware rule, including:
- Dependency trace requirement (chain from user action to observable outcome, every arrow verified)
- Runtime verification is mandatory for UI / API / webhook / cron / migration features
- Never claim a feature exists when asked without citing file:line
- Never answer "yes it works" to a user question without exercising it in the current session
- Integration tests (Playwright/Vitest) are mandatory, not optional, for runtime features

Vaporware shipping is the #1 source of user trust loss. Every feature must be end-to-end tested before marking done.

**Scope is mechanical, not interpretive.** Scope = whatever is in the plan file's explicit task list. Check the list. If a task is `- [ ]` in the plan, it is in scope. If it is not in the plan, it is not in scope. You do not get to decide mid-execution that a planned task is "polish" or "stretch goal" or "minimum viable done without it." There is no "genuinely out of scope" vs "out of scope" — scope is a grep.

**Deferral is only legitimate in these cases:**
- **Dependency-blocked**: the task in the plan requires something that doesn't exist yet (user input, an external service, a prerequisite task in a later phase that also isn't done). Must be a hard dependency, not a preference.
- **User explicitly deferred it mid-execution**: the user said "skip X" or "defer X" in so many words during the current session. Not a prior conversation, not an inferred preference.
- **Never was in the plan**: the task doesn't appear in the plan's task list at all. If you're about to work on something not in the plan, stop and either add it to the backlog or surface it to the user — don't build off-plan work just because it seems related.

**Deferral is NOT legitimate for any of these reasons:**
- "I want to finish faster"
- "This is polish, not blocking"
- "The minimum viable version is enough"
- "I'll come back to this later if there's time"
- "The user will probably prioritize X over Y" (don't assume — ask or build everything in the plan)
- "This is a UI tweak and the backend is working"
- "The tests pass without this"
- "A follow-up session can pick it up"

If you catch yourself writing "deferred to backlog" during autonomous execution, stop. Check the plan file. If the task is there, build it. The user's autonomous-execution grant explicitly said "through every phase" — every sub-task listed in the plan is in scope until the user interrupts and defers it.

**Mandatory pre-commit check:** before marking a phase as complete in the plan file, scan the tasks list. If any task is unchecked AND is not explicitly deferred-by-user-request, the phase is NOT complete. Keep building.

**Mandatory pre-session-end check:** before writing a completion report, re-read the original plan's task list and verify every task that wasn't explicitly deferred by the user has been built. Incomplete work dressed up as "~75% done + follow-up items" is how plans get silently abandoned.

**If you're genuinely stuck on a task** (hit a dependency you didn't anticipate, or the task is larger than it looked), the correct action is to STOP and report the blocker to the user, not to drop the task and move on to the next phase.

### Strategy Before Planning (for substantial features)
For new features, page redesigns, or workflow changes that affect the user experience: **define the strategy before writing the plan.** The sequence is: understand the domain → define what success looks like → design how to get there → build.

- **Strategy** = what are we trying to achieve and why? Who is the user? What's their workflow? What does "done" look like from their perspective?
- **Plan** = how do we build it? What files, what order, what tests?

Without the strategy step, plans can be technically correct but solve the wrong problem. Strategy alignment with the user prevents rework.

### UX During Design, Not Just Testing
For any user-facing feature, apply the UX checklist (`~/.claude/docs/ux-checklist.md`) **during the design phase**, not just after building. Plan files for UI work should reference specific checklist items: which empty states need handling, which forms need required indicators, what dark mode considerations exist. Catching UX issues at design time is 10x cheaper than catching them in testing.

### Mandatory: ux-designer review for new UI surfaces

Before any plan task that creates a **new route, new top-level page, new dashboard section, new modal flow, or any substantial user-facing component** is marked as "ready to build," invoke the `ux-designer` agent on the plan's UI section. This is a hard requirement.

**Triggers that require a ux-designer pre-build review:**
- New Next.js route (new directory under `src/app/`)
- New top-level page (a new nav item in the sidebar)
- New tab or sub-section on an existing page
- New modal flow with more than one step
- New form with more than 3 fields
- Redesign of an existing page's primary layout

**Triggers that do NOT require a review:**
- Bug fix that changes no layout
- Adding a single button/field to an existing form
- Wiring an existing component into a new location (if it was already reviewed)
- Backend-only changes

**How to invoke:**
1. Draft the UI section of the plan (entry points, layout, states, flow)
2. Invoke ux-designer via the Task tool with the plan path + the UI section
3. Read the review. Every "Critical" gap must be addressed in the plan before building. "Important" gaps should be addressed unless there's a good reason not to. "Nice-to-haves" are optional.
4. Paste the ux-designer's "Summary for the plan file" into the plan under a `### UX Design Review` heading so the design decisions are locked in.
5. THEN start building.

**Why this is strict:** UX gaps found in planning take 10 minutes to fix. UX gaps found in testing take 10 hours. UX gaps found in production take 10 days of user complaints. A new UI page that lacks an entry point, or has no empty state, or dead-ends the user, will ship as planned and then be silently abandoned. See the 2026-04-14 AI Conversations page incident: I built a dedicated page with no "start a new conversation" button, so the user had no way to initiate one. The ux-designer agent would have caught this at plan time.

### Mandatory: end-user-advocate review for every plan (skip via `acceptance-exempt: true`)

Every plan undergoes `end-user-advocate` review at plan-time AND at runtime by default. The advocate is the harness's adversarial observer of the running product from the user's perspective — the one agent that does NOT trust what the builder produced. See `~/.claude/rules/acceptance-scenarios.md` for the full plan-time → runtime → gap-analysis loop.

**Plan-time mode (peer planner, parallel to ux-designer and systems-designer):**

1. Draft the plan to a stable shape (Goal / Scope / Edge Cases populated).
2. Invoke `end-user-advocate` via the Task tool with `mode=plan-time` and the plan path.
3. Read the advocate's `Plan-Time Advocate Feedback:` block. Every flagged gap must be closed in the plan (resolved in scope, or moved to `## Out-of-scope scenarios` with rationale) before build begins.
4. The advocate's authored scenarios live in the plan's `## Acceptance Scenarios` section (template-introduced; see `templates/plan-template.md`).
5. THEN start building.

**Runtime mode (Stop-hook gated):**

After build, before session end, the advocate is invoked again in runtime mode against the live app. It writes a PASS/FAIL JSON artifact to `.claude/state/acceptance/<plan-slug>/`. The Stop-hook gate (walking-skeleton form lives in `pre-stop-verifier.sh` Check 0; production form is `product-acceptance-gate.sh`, Phase D of `docs/plans/end-user-advocate-acceptance-loop.md`) blocks session end when an ACTIVE non-exempt plan lacks a PASS artifact for the current `plan_commit_sha`.

**Skip with justification — `acceptance-exempt: true`:**

Some plans have NO product user (harness-development plans, pure-infrastructure plans, migration-only plans without UI implications). For these:

```
acceptance-exempt: true
acceptance-exempt-reason: <one-sentence substantive justification (>= 20 chars)>
```

Both `plan-reviewer.sh` (skips the `## Acceptance Scenarios` requirement) and the Stop-hook gate (treats exempt plans as no-artifact-needed) honor the exemption. The reason field is required: an unjustified `acceptance-exempt: true` is BLOCKED by the gate.

**When to use the exemption** (full guidance in `acceptance-scenarios.md`):
- YES: harness-dev plans, pure-infrastructure (Dockerfile, CI workflow), migration-only without UI.
- NO: backend changes that affect any user-observable response, "small UI tweaks," "tests pass without it," "I'm in a hurry."

**Scenarios-shared, assertions-private — the load-bearing builder discipline:**

When the orchestrator dispatches build work (per `rules/orchestrator-pattern.md`), the dispatch prompt INCLUDES the plan's `## Acceptance Scenarios` (motivation, user flow, success criteria) but does NOT include the advocate's internal assertion list. LLM builders teach-to-the-test extremely easily; sharing the assertions causes the builder to hardcode the string instead of wiring the data path. Build for the user's actual outcome, not for the assertion text. The orchestrator pattern's "Scenarios-shared, assertions-private" sub-section codifies this in the dispatch-prompt template.

**Why this is strict:** every Gen 4 enforcement mechanism except `pre-stop-verifier.sh` and `tool-call-budget.sh` gates on something the BUILDER produces — a plan, an evidence block, a self-report. The builder is the agent that fails at completeness. The end-user advocate is the harness's only adversarial-observer agent; it closes the structural gap that lets incomplete builds ship despite a stack of self-certifying mechanisms. See `acceptance-scenarios.md` for the full motivation.

During planning:
- Do not rush to start building — thorough > fast
- Surface all architectural decisions with options, tradeoffs, and your recommendation
- Identify edge cases and potential problems before they become surprises
- Ask clarifying questions grouped in a single message
- The plan should be detailed enough that implementation is mechanical
- Don't suggest starting implementation until all ambiguities are resolved

### Reusable Component Rule

When a plan includes building a reusable component, guard, utility, modal, banner, or any pattern that solves a general problem:

1. **Ask: "Where else does this problem exist?"** The component solves a problem (e.g., "user loses data on navigation"). That problem is not unique to the page you're building — it exists everywhere the same pattern applies. Grep the codebase for all locations.

2. **The plan MUST include a separate task: "Wire [component] into all applicable locations."** List every location explicitly — do not leave it as "wire into other pages later." If you built an `UnsavedChangesGuard`, the plan must list every form page. If you built an `UnhappyCustomerBanner`, the plan must list every page it should appear on.

3. **The verifier checks coverage, not just existence.** When verifying a reusable component task, the verifier should grep for all places the component SHOULD be used and confirm it IS used in each one. A component that exists but is only wired into one page is an incomplete task.

Failure mode this prevents: Building a reusable guard/modal/banner for one page and forgetting to apply it to the 5 other pages where the same problem exists. This has happened in practice — `UnsavedChangesGuard` was built for the Automation page but never wired into campaigns, templates, or settings forms.

### Sweep Task Decomposition

When a plan task is worded as "wire X into all the forms" or "fix Y across the codebase" or "add Z to every page", it is **not a task — it's a category**. Categories cannot be verified as complete because there's no objective definition of "all". This is how partial fixes happen: the plan says "wire RequiredLabel into all forms", 11 of 14 get done, the box gets checked, and 3 forms silently never get fixed.

**Mandatory rule:** Sweep tasks must be decomposed per-target before starting:

1. **Grep the codebase** for every file that needs the change. Save the file list.
2. **Write the file list into the plan** as one sub-task per file (or as an explicit checklist within one task).
3. **The task is not complete until every file in the list is verified.** The task-verifier checks every file individually, not the existence of the change in any one file.
4. **If you discover additional files mid-task**, add them to the list and verify those too.

A task that says "wire RequiredLabel into all 14 forms" must list those 14 forms by path. A task that says "add try/catch to all server pages" must list every server page by path. The decomposition step is non-negotiable — without it, the task is uncheckable.

### Pivoting Between Plans

If you start work on a new plan while another plan is `Status: ACTIVE`, you MUST first reconcile the original plan:

1. **If the original plan is mostly done** (>80% complete and the unbuilt tasks are no longer in scope) → set `Status: COMPLETED` with a one-line note explaining what was abandoned. Move any unbuilt-but-still-needed tasks to `docs/backlog.md` as standalone items.
2. **If the original plan is partially done and the rest still matters** → set `Status: DEFERRED` with the date and a one-line reason. The unbuilt tasks remain in the plan file for resumption later.
3. **If the original plan is being abandoned entirely** → set `Status: ABANDONED` with a reason.

**Do NOT start a new plan with the previous one still ACTIVE.** The pre-stop hook will block session termination, and worse, the unbuilt tasks from the previous plan will be invisible to future sessions because the new plan becomes the source of truth in SCRATCHPAD. This has happened: a 30-task plan was left ACTIVE while a consistency overhaul ran, and 7 unbuilt tasks were lost until a sweep agent found them.

### Backlog absorption at plan creation

When a new plan is created that addresses one or more items currently listed in `docs/backlog.md`, those items MUST be **absorbed into the plan** — meaning deleted from the backlog's open sections in the same commit that creates the plan file. This is enforced by `adapters/claude-code/hooks/backlog-plan-atomicity.sh`.

**The contract:**

1. **Plan header declares what it absorbed.** Every plan file MUST include a header field `Backlog items absorbed: [none | list of slugs]` between `Status:` and `## Goal`. Examples:
   - `Backlog items absorbed: none` — the plan addresses a fresh user request or a need that was not tracked in the backlog.
   - `Backlog items absorbed: slug-1, slug-2` — the plan absorbs two specific backlog entries.

2. **Absorbed items are deleted from the backlog's open sections.** In the same commit as the plan file creation, the corresponding entries are removed from the backlog (not marked "in progress" — deleted). The backlog represents **items not yet claimed by any plan**; once a plan owns an item, it leaves the backlog.

3. **On plan COMPLETION:** the completion report's "Implementation Summary" lists each absorbed item with its shipped status (built, with commit SHA). The items do NOT return to the backlog — they are archived inside the plan's completion report.

4. **On plan ABANDONMENT or DEFERRAL:** absorbed items RETURN to the backlog's open section with a note `(deferred from <plan-path>)`. This restores the "not yet claimed" state so a future plan can pick them up.

**Rationale:** backlog = "not yet claimed by any plan"; plan = "actively being built." A single source of truth per item prevents the "built but forgot to update backlog" staleness that is common in long-running projects, and prevents duplicate work where two plans both claim the same backlog entry. The enforcing hook makes the deletion-on-absorption atomic with the plan file creation commit, so no plan can exist with absorbed items still listed in the open backlog.

## Plan File Lifecycle (Creation, Archival, Lookup)

Plan files have a four-stage lifecycle. Each stage has a mechanical hook backing it so the lifecycle does not depend on human discipline at any point. The mechanism that holds it together is `~/.claude/hooks/plan-lifecycle.sh` (PostToolUse on Edit/Write under `docs/plans/`).

### Stage 1: Creation — commit immediately

When you write a new plan file at `docs/plans/<slug>.md`, **commit it within the same session** — ideally within minutes of writing it. Uncommitted plan files are vulnerable to being wiped by concurrent sessions performing git operations on the same working tree.

The `plan-lifecycle.sh` hook surfaces a warning every time it sees an edit to an uncommitted plan file, of the form:

> ⚠ Plan file `<slug>.md` was created but is not yet committed. Uncommitted plan files can be wiped by concurrent sessions. Commit now: `git add <path> && git commit -m 'plan: <slug>'`.

If you reach session end with an uncommitted plan file, `pre-stop-verifier.sh` surfaces a final non-blocking warning. Commit before stopping.

### Stage 2: In-progress — normal mechanics apply

Once committed, the plan proceeds through normal build mechanics:
- The `task-verifier` agent flips checkboxes (per the Verifier Mandate above)
- Evidence-first protocol is enforced by `plan-edit-validator.sh`
- Multi-task plans are dispatched to `plan-phase-builder` sub-agents per the orchestrator pattern

No lifecycle hook activity is needed at this stage.

### Stage 3: Status is the last edit (auto-archival)

**The Status field MUST be the final edit made to a plan file in its active life.** Completion reports, final decisions log entries, and any closing notes are written BEFORE flipping `Status:` to a terminal value (COMPLETED, DEFERRED, ABANDONED, SUPERSEDED).

Why: when `Status:` transitions to terminal, `plan-lifecycle.sh` immediately executes `git mv docs/plans/<slug>.md docs/plans/archive/<slug>.md` in the same edit cycle. If a `<slug>-evidence.md` companion exists, it moves with the plan. If you try to append to the plan after flipping Status, the path is already gone and you have to recover.

**The Status change and the file rename land in the same commit.** Marking a plan complete and archiving it are one action, not two — there is no separate "archive this plan" step to remember.

The hook emits a system message after the move:

> 📦 Plan `<slug>` transitioned to [STATUS] and was archived. Subsequent references should use: `docs/plans/archive/<slug>.md`

### Stage 4: Lookup — archive-aware by default

Once a plan is archived, references to it must resolve across both `docs/plans/` and `docs/plans/archive/`. Use one of the following depending on context:

- **Bash contexts (hooks, scripts, manual invocation):** `~/.claude/scripts/find-plan-file.sh <slug>` resolves the slug to a full path. Resolution order is active-first (`docs/plans/<slug>.md`), then archive (`docs/plans/archive/<slug>.md`). Exit 0 with path on stdout if found; exit 1 with no stdout if not found. Stderr emits a `resolved from archive: <path>` note when the archive fallback is used. Glob patterns supported (e.g., `find-plan-file.sh "*release*"`).
- **Claude tool calls:** use `Glob docs/plans/**/<pattern>.md` to search both directories transparently.
- **Agent prompts:** the `task-verifier`, `plan-evidence-reviewer`, and `ux-designer` agent files include archive-aware fallback instructions for the plan path argument.

The active directory is searched first by design — archived plans are historical records and should not normally be under active modification.

### Recovery from premature archival

If a session accidentally writes `Status: COMPLETED` (typo, mistaken state, mid-edit confusion) and the hook archives the file:

1. `git mv docs/plans/archive/<slug>.md docs/plans/<slug>.md` to restore the active path
2. If a companion evidence file moved too: `git mv docs/plans/archive/<slug>-evidence.md docs/plans/<slug>-evidence.md`
3. Edit `Status:` back to the correct value (e.g., `ACTIVE`)
4. The hook does NOT fire on archive → active transitions (only terminal transitions trigger archival), so the recovery is safe

The cost of the rare accidental terminal-status flip is one `git mv`. The benefit of automatic archival in the common case (plans never accumulate in `docs/plans/` past their completion) is large. This tradeoff is intentional.

### Hooks NOT involved in archive-awareness (by design)

A few existing hooks are deliberately scoped to the active `docs/plans/` directory only and do NOT search the archive:

- `backlog-plan-atomicity.sh` — only fires on new plan creation
- `harness-hygiene-scan.sh` — harness-repo-wide, not plan-specific
- `plan-edit-validator.sh` — its regex matches archive paths too, which is the desired behavior (evidence-first protocol still applies if you edit an archived plan)
- `pre-commit-gate.sh` — correctly scoped to active-work commits

Edits to archived plans are rare. When they happen (correcting a historical typo, adding a postmortem note), you must use the explicit `docs/plans/archive/<slug>.md` path — the archive is not auto-resolved by hooks that scope themselves to active work.

## Process
1. **Explore first.** Read relevant files, understand architecture, identify conventions.
2. **Surface decisions.** Present choices with pros/cons. Get alignment.
3. **Write the plan.** Persist to `docs/plans/<descriptive-slug>.md` using @~/.claude/templates/plan-template.md
4. **Create a feature branch.** `feat/<plan-slug>` or `fix/<plan-slug>` from current branch.
5. **Implement autonomously.** After completing each task, invoke the `task-verifier` agent to check the task — **do NOT check the task's box yourself.** Update SCRATCHPAD.md after each verified task.
6. **If deviating:** Update plan file with deviation and reasoning BEFORE implementing.

After compaction, read plan file + SCRATCHPAD.md to resume. To stop early, set `Status: ABANDONED` or `Status: DEFERRED` — note that this triggers auto-archival (see "Plan File Lifecycle" above), so write any final notes BEFORE flipping Status.

## Task Completion — Verifier Mandate

**As of 2026-04-09, task checkboxes in plan files may only be marked complete (`- [x]`) by the `task-verifier` agent.** Self-reporting is forbidden because it has failed in practice — it is too easy to edit checkboxes without doing the work.

### How it works

1. When you finish building a task, do NOT edit the plan file yourself to check the box.
2. Instead, invoke the `task-verifier` agent via the Task tool with:
   - Plan file path
   - Task ID
   - Task description
   - Files you modified
   - Any acceptance criteria you want checked
3. The verifier runs its own checks (reads files, runs typecheck, greps for expected patterns, queries APIs if applicable).
4. If the verifier returns PASS, **it** checks the box and appends an evidence block to the plan's `## Evidence Log` section.
5. If the verifier returns FAIL or INCOMPLETE, it explains the gaps. Address them and re-invoke the verifier.

### Enforcement

The `pre-stop-verifier.sh` Stop hook blocks session termination if:
- The active plan has checked tasks without corresponding evidence blocks
- Any evidence block is malformed or missing required fields
- Any evidence block has a FAIL or INCOMPLETE verdict
- The plan has unchecked tasks and its status is not ABANDONED/DEFERRED/COMPLETED

If you need to stop early without completing the plan, set `Status: ABANDONED` or `Status: DEFERRED` at the top of the plan file.

### What NOT to do

- ❌ Do not edit `- [ ]` → `- [x]` in any plan file manually.
- ❌ Do not write your own evidence blocks in the Evidence Log. Only the task-verifier agent may do this.
- ❌ Do not skip verification for "obvious" tasks. The point of the system is that no task is exempt.
- ❌ Do not try to trick the verifier with vague or misleading inputs. It's instructed to err toward FAIL, and it cross-checks against the actual repo state.

### Why this exists

Previous plans have had tasks marked complete that weren't actually done — up to 9 of 41 in one case — because the builder (self-report) was trusted to be honest about their own work. The verifier agent is a second set of eyes that doesn't trust the builder's claims without checking them. This protects the end user from shipping something half-built.

## Mid-Build Decisions

Assess reversibility:

**Tier 1 — Continue + Document:** Isolated, trivially reversible. Log in plan + SCRATCHPAD.
**Tier 2 — Continue + Checkpoint:** Multi-file but revertible. Commit first. Log with SHA.
**Tier 3 — Pause + Wait:** DB schema, public API, auth, production data. Stop. Document tradeoffs. Wait for approval.

Use format at @~/.claude/templates/decision-log-entry.md

## Completion Report
After all tasks complete, append handoff report using @~/.claude/templates/completion-report.md

The completion report's "Implementation Summary" (section 1) MUST list each `Backlog items absorbed` entry from the plan header with its completion status (built with commit SHA, or deferred/abandoned with reason). Items marked built are archived inside the plan and do NOT return to `docs/backlog.md`; items marked deferred/abandoned return to the backlog's open section with a `(deferred from <plan-path>)` note.

## Decision Records & Session History

Maintain traceable records in the repo:

**Decision Records** (`docs/decisions/NNN-slug.md`): Create when a product/architecture direction is chosen, external input changes the plan, or a significant "either way works" choice is made. Format: Title, Date, Status, Stakeholders, Context, Decision, Alternatives, Consequences. Index at `docs/DECISIONS.md`.

**Session Summaries** (`docs/sessions/YYYY-MM-DD-slug.md`): Write at end of every significant session. Include: what was built, decisions made, bugs found, key artifacts, what's left.

**Plan Files** (`docs/plans/<slug>.md`): Permanent records. Never delete. Include final status + completion report. On terminal status, auto-archived to `docs/plans/archive/<slug>.md` (see "Plan File Lifecycle" above).

### Mandatory: every Tier 2+ decision gets a decision record in the same commit

Writing a `Decision:` entry in a plan file's Decisions Log is **not sufficient**. That's the short-form local note. Any Tier 2 or Tier 3 decision (by the reversibility classification above) ALSO requires a standalone `docs/decisions/NNN-slug.md` file committed with the same change that implements the decision.

**Triggers that require a decision record:**
- New schema (table, column, enum, RLS policy)
- New cross-file architecture pattern (auth guard pattern, token system, alert system, etc.)
- Choice between two or more valid implementations where the user approved one
- Scope shape decisions (single-phase vs split, bundled vs separate commits, what belongs in vs out of scope)
- Process conventions (naming, timeout rules, commit cadence, retention policies)
- Anything the user explicitly asks about ("which approach?", "α or β?", "do we need...")

**Workflow:**
1. Make the choice (with user input if needed).
2. Write the decision record as `docs/decisions/NNN-slug.md` where NNN is the next number in `docs/DECISIONS.md`.
3. Add one row to `docs/DECISIONS.md` pointing at the new file.
4. Reference the decision record from the plan file's Decisions Log (short form) AND from the implementing commit message.
5. Stage the decision record file along with the implementation files so they land in the same commit.

**What the record must contain:**
- **Title**, **Date**, **Status** (Active / Implemented / Deferred / Reverted), **Stakeholders**
- **Context** — what problem drove the decision
- **Decision** — what was chosen
- **Alternatives Considered** — the other options, with a 1-2 line "why rejected" each
- **Consequences** — what this enables, what it costs, what it blocks

**Enforcement:** The plan file's Decisions Log section is audited before every session end. Any Tier 2+ entry without a matching `docs/decisions/NNN-*.md` file blocks `Status: COMPLETED` on the plan.

**Why this is strict:** decision records are how future sessions (and future humans) understand *why* the codebase looks the way it does. A short entry in a plan file disappears from context once the plan is completed and archived. A decision record lives forever in `docs/decisions/` as a permanent artifact. Without this, every future session has to re-derive the reasoning from git history and code reading, and often gets it wrong.

## Capture-codify at PR time

Every PR opened against a harness-equipped repo MUST answer the question **"What mechanism would have caught this?"** in its description. This is the structural enforcement of the diagnosis-rule discipline ("After Every Failure: Encode the Fix") — the verbal version is forgotten under time pressure, skipped on small bug-fix PRs, and invisible to reviewers. The PR-template requirement makes the capture-codify analysis happen at the moment of fix shipping, not "when I remember to come back to it later."

**Three answer forms are accepted** (one per PR; pick the first that fits):

- **a) Existing catalog entry.** Cite the `FM-NNN` ID from `docs/failure-modes.md` that names this failure class. Add a one-sentence note explaining how the entry maps to this specific bug. Use this when the failure is already a known class — extend the catalog's `Example` list in the same PR rather than create a new entry.
- **b) New catalog entry proposed.** When this is a previously-unobserved failure class, propose a new `FM-NNN` entry in `docs/failure-modes.md` (in the same PR) using the six-field schema (ID, Symptom, Root cause, Detection, Prevention, Example). Reference the new entry's ID from the PR body.
- **c) No mechanism — accepted residual risk.** Use sparingly, only when no realistic mechanism would catch the class without unacceptable false positives (typo fixes in prose, one-off cleanups, rollbacks where the analysis belongs on the rolled-back PR). Requires ≥40 chars of substantive rationale explaining *why* mechanization is not worth it for this class.

**The template lives at** `.github/PULL_REQUEST_TEMPLATE.md` in the neural-lace repo (and downstream repos that have run the rollout script). When you open a PR via `gh pr create` or the GitHub UI, the body is auto-populated with the four required sections (Summary, What changed and why, **What mechanism would have caught this?**, Testing performed). Replace the bracketed placeholder text in the section corresponding to your chosen answer form. The other answer-form sub-headings can stay as placeholders (they document the option set).

**Local pre-push convention.** If your repo has installed the local pre-push hook (`pre-push-pr-template.sh`), the validator runs against either a `.pr-description.md` file in the repo root (preferred — write your PR body locally before push, then `gh pr create --body-file .pr-description.md` to upload), or against the latest commit message body. WIP branches matching `wip-*` or containing `scratch` are auto-skipped; bypass with `git push --no-verify` for non-PR pushes.

**Enforcement (CI-side):** the `.github/workflows/pr-template-check.yml` workflow runs on `pull_request` events (`opened`, `edited`, `synchronize`, `reopened`) and emits a check named `PR Template Check / validate`. The check fails if the mechanism section is missing, still contains placeholder text, has no answer form selected, or selects (c) with under 40 chars of rationale. Branch protection is configured to require this check before merge to master, so the field cannot be skipped.

**Validator library:** the regex patterns and canonical stderr messages live at `.github/scripts/validate-pr-template.sh` (sourced by both the workflow and the local hook) so CI and local feedback are byte-for-byte identical.

## Session Retrospective

At the end of a significant session (before the user runs `/clear` or the session ends naturally), review the conversation for improvement signals:

1. **User corrections** — did the user correct your approach, judgment, or output at any point? Each correction is a candidate for a new rule. Propose: "Based on [correction], should I add a rule to [file] to prevent this in future sessions?"
2. **Repeated patterns** — did you do the same type of work 3+ times manually? That's a candidate for a reusable component, helper, or automation.
3. **Feedback memories** — check if any existing feedback memories are now broadly applicable enough to graduate to a rule. A feedback entry that's been validated across multiple sessions should become a rule.

This is not a blocker — don't prevent the session from ending. Surface all actionable improvements, not just a subset.
