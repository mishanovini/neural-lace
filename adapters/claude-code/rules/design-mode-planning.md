# Design-Mode Planning Protocol

**Classification:** Hybrid. The 10-section analysis is a Pattern (self-applied discipline when writing a plan). The "can't edit design-mode files without a valid plan" constraint is a Mechanism (`systems-design-gate.sh` PreToolUse hook). The "plan must be reviewed by systems-designer before implementation" is also Mechanism-adjacent — the `plan-reviewer.sh` hook enforces section presence, and the `systems-designer` agent enforces section substance.

## When design-mode applies

Not every plan needs the full systems-engineering treatment. **Mode: code** (the default) is correct for:
- Bug fixes isolated to one or two files
- UI component tweaks
- Refactors that preserve behavior
- Test additions
- Documentation changes
- Copy/text edits

**Mode: design** is required when ANY of these are true:
- The plan creates or modifies a CI/CD workflow (`.github/workflows/*.yml`)
- The plan creates or modifies a database migration (`supabase/migrations/*.sql`, `prisma/migrations/*`, etc.)
- The plan creates or modifies infrastructure config (`vercel.json`, `railway.toml`, `fly.toml`, `Dockerfile`, `docker-compose.yml`, `terraform/**`)
- The plan creates or modifies deployment/ops scripts (`scripts/deploy.*`, `scripts/migrate.*`)
- The plan integrates a third-party tool you haven't used before in this project
- The plan crosses multiple service boundaries (e.g., frontend + backend + queue + external API)
- The plan has more than 3 state transitions in its flow
- Each iteration takes > 5 minutes or costs real money (CI builds, API calls, deployment)
- Other teams/systems will depend on the output

**When in doubt, use design.** The overhead of writing 10 sections is small; the cost of design-mode work gone wrong is enormous (see the 2026-04-19 kanban automation debugging session — hours burned on failures that the 10-section analysis would have caught upfront).

## The 10 sections — what each requires

Each section must have **substantive, task-specific content**. "TBD", "see below", single-line placeholders, or content that would read the same for any project will fail systems-designer review.

### 1. Outcome (measurable user outcome, not output)

What does success look like from the user's perspective, in measurable terms? Include the time-to-outcome expectation.

**Good:** "Within 30 minutes of the user moving an issue from Backlog to Planning, the fix is deployed and visible at `<your-app-url>`, OR the issue has a comment explaining what's blocked with a clear next action for the user."

**Bad:** "The build queue works." (Not measurable. What does 'works' mean? To whom? By when?)

### 2. End-to-end trace with a concrete example

Walk ONE real example through the system step-by-step, with actual values. This is the single highest-leverage section — writing it forces every invisible state change to become visible.

**Good:** "At T=0, user moves Issue #NNN (title: '<example issue title>', body length: 180 chars, 1 image attached) to Planning. At T=0:05 the next cron fires. Workflow reads project `<project-id>`, sees 1 item in Planning. Orchestrator: creates plan file at `docs/plans/kanban-NNN-<slug>.md`, commits to master (auth: PROJECT_TOKEN with contents:write scope), moves card to Next. ..." (continue for every step)

**Bad:** "The orchestrator reads the board and dispatches builds." (No concrete values, no state changes, no boundaries named.)

If writing this trace surfaces a "how does this actually happen?" question, that's a gap to close before implementation — not a detail to figure out later.

### 3. Interface contracts between components

For every component boundary, document the contract. Each contract is "X promises Y that Z, in format F, within time T."

**Good table:**
| Producer | Consumer | Contract |
|---|---|---|
| Orchestrator | Build matrix | Outputs a JSON array of `{issue_num, item_id, title, model}`, ≤ 3 items, within 90s of cron fire. Via `$GITHUB_OUTPUT`, which has a 1MB limit — individual items must stay under ~10KB. |
| Runner | Claude Code CLI | Working directory IS the repo checkout (verified by `pwd`). Env vars include CLAUDE_CODE_OAUTH_TOKEN, GH_TOKEN, MODEL, ISSUE_NUM. Claude Code writes to `$(pwd)`. |

**Bad:** "Components pass data to each other." (No specifics.)

### 4. Environment & execution context

What does the runtime environment provide? What's the working directory? What env vars? What tools? What's ephemeral vs. persistent?

**Good:** "Ubuntu-latest GitHub Actions runner. Working directory: `$GITHUB_WORKSPACE` which is the repo checkout. Pre-installed: Node 20, git, gh CLI, jq. NOT pre-installed: Claude Code CLI, the neural-lace harness. VM destroyed at job end — `~/.claude/` is lost unless committed to the repo. Available secrets: PROJECT_TOKEN, CLAUDE_CODE_OAUTH_TOKEN, ANTHROPIC_API_KEY."

**Bad:** "Runs on GitHub Actions." (Doesn't name what's provided.)

### 5. Authentication & authorization map

Every external boundary has an auth story. For each: credential format, which key/token, what permissions it needs, what tier/quota applies, rate limits.

**Good:** "Three auth boundaries: (a) GitHub API via `PROJECT_TOKEN` (fine-grained PAT, contents:write + pull-requests:write + project:write on `<your-org>`, ~5000 req/hr). (b) Anthropic API via `CLAUDE_CODE_OAUTH_TOKEN` (long-lived subscription token, counts against Max plan's 5-hour rolling window, ~30K input tokens/min burst tolerance). (c) Vercel via GitHub integration (no token needed, triggers on push to master)."

**Bad:** "Uses the GH token and the Claude token." (No tier, no limits, no permissions named.)

### 6. Observability plan (built before the feature)

Every step emits what signal? Where do logs go? How would I reconstruct what happened from logs alone if everything fails?

**Good:** "Each orchestrator step prints: `[step-name] processing item <id>, current status <status>`. Each Claude invocation prints on completion: `model=X turns=N duration=Ys cost=$Z`. Each build step posts a checkpoint comment on the issue: build started / PR created / merged / deployed. Workflow run URL is in every Build Started comment so the user can follow live logs."

**Bad:** "We use standard GitHub Actions logging." (Doesn't say what's logged or when.)

### 7. Failure-mode analysis per step

Table: step, failure mode, observable symptom, recovery/retry policy, escalation criteria.

**Good:** a table with 15+ rows covering every step × every realistic failure. This is usually the longest section.

**Bad:** "If something fails, it retries." (No specifics.)

### 8. Idempotency & restart semantics

What happens if each step runs twice? If a step partially completes? What's the restart procedure from every possible intermediate state?

**Good:** "Orchestrator moves items to Doing atomically — safe to re-run (GraphQL mutation is idempotent). Build step may have partial state: Claude could have made commits but not pushed (`git push` would be retried), or pushed but not created PR (check `gh pr list --head <branch>` before attempting create). Merge step: `gh pr merge` is idempotent — already-merged PR returns cleanly. Deploy polling: safe to re-enter, polls same SHA."

**Bad:** "The pipeline handles restarts." (Doesn't say how.)

### 9. Load / capacity model

What's the throughput limit? What's the bottleneck? What happens at saturation?

**Good:** "Max 3 concurrent builds (self-imposed). Bottleneck: Claude Max concurrent session limit (4 active sessions typical). Second bottleneck: GH Actions runners (20 concurrent on free tier, unlimited on paid). At saturation: orchestrator sees Doing=3, outputs empty matrix, items stay in Next until slot opens. Explicit backpressure; no queue overflow."

**Bad:** "Uses parallel builds." (Doesn't name the limit.)

### 10. Decision records & runbook

Non-trivial choices (with alternatives considered and why rejected) + for each known failure mode, a runbook entry.

**Good decision:** "Squash merge vs. merge commit: chose squash. Alternative rejected: merge commit preserves full branch history, but creates noise in master log since Claude's WIP commits don't need archival. Squash gives one-commit-per-issue which matches the kanban model."

**Good runbook:** "Symptom: builds not starting. Diagnostics: (1) check Actions tab for workflow status, (2) if cron hasn't fired in 20+ min, check GH status page, (3) check orchestrator logs for JSON parse errors. Fix: manually trigger via `gh workflow run kanban-engine.yml`. Escalation: if fails to trigger, the workflow YAML may have a parse error — check linter."

**Bad:** "Chose squash merge." / "Debug by checking logs." (No alternatives, no specific diagnostic steps.)

## The gate: `systems-design-gate.sh`

The PreToolUse hook blocks Edit/Write operations on design-mode files unless an active plan with `Mode: design` exists and has passed `plan-reviewer.sh`.

Design-mode files are matched by pattern (configurable):
- `.github/workflows/*.yml`
- `**/vercel.json`, `**/railway.toml`, `**/fly.toml`
- `**/*/migrations/*.sql`
- `**/Dockerfile`, `**/docker-compose.yml`
- `**/terraform/*.tf`
- `**/scripts/deploy*.*`, `**/scripts/migrate*.*`

When the hook fires, it:
1. Checks if the target file matches a design-mode pattern
2. Looks for an active plan file in `docs/plans/` with `Mode: design` AND `Status: ACTIVE`
3. Checks that the plan has passed plan-reviewer.sh (all 10 sections present with non-placeholder content)
4. If all conditions met, allows the edit
5. Otherwise, blocks with a message pointing the user to write/complete the plan first

## Escape hatch: `Mode: design-skip`

Occasionally a one-line change to a design-mode file is genuinely not system design work (e.g., bumping a Node version in a workflow, fixing a typo in a Dockerfile comment). For these:

Create a minimal plan file with `Mode: design-skip` and a one-sentence justification. The gate accepts this as proof that thoughtful consideration was given — the plan is recorded, auditable, and forces pausing before the edit.

`Mode: design-skip` plans don't require the 10 sections. They MUST have:
- `Mode: design-skip` in the header
- A `## Why design-skip` section with a 1-2 sentence justification specific to this change
- A single task description naming what's being changed

The intent: preserve the forcing function (stop, write something, think) without requiring the full treatment for trivial changes.

## The agent: `systems-designer`

Parallels `ux-designer` (which reviews UI plans). MUST be invoked on any plan with `Mode: design` before implementation begins.

Invocation via Task tool:
```
Invoke systems-designer with: plan file path, the 10 section contents
```

The agent reviews each section for substance (not just presence), verifies claims made in the plan (e.g., "rate limit is 30K/min" — is that checked?), and returns PASS/FAIL with specific gaps.

**Plan cannot move to implementation until systems-designer returns PASS.** Implementation attempts without PASS are caught by the `systems-design-gate.sh` hook at file-edit time.

## Integration with existing rules

- **`planning.md`** — the general planning protocol. Design-mode extends it, doesn't replace it. When Mode: design, also apply design-mode-planning.md.
- **`orchestrator-pattern.md`** — still applies. Design-mode plans are built by the orchestrator dispatching to builders, same as any multi-task plan.
- **`vaporware-prevention.md`** — still applies. Design-mode adds systems-level enforcement; task-level verification (runtime evidence, reproduction) is still required per task.
- **`task-verifier` agent** — still the only entity that flips checkboxes. For design-mode plans, each task must pass task-verifier AFTER systems-designer has passed the plan.

## Enforcement summary

| Layer | What it enforces | File |
|---|---|---|
| Template | Shape of a correct design-mode plan | `templates/plan-template.md` |
| Rule (this doc) | When to use design-mode, what each section requires | `rules/design-mode-planning.md` |
| plan-reviewer.sh | 10 sections present, non-empty, no placeholder text | `hooks/plan-reviewer.sh` |
| systems-designer agent | 10 sections are substantive and task-specific | `agents/systems-designer.md` |
| systems-design-gate.sh | No design-mode file edits without a valid plan | `hooks/systems-design-gate.sh` |

The first two are documentation (pattern-level). The last three are mechanisms (hook-enforced + agent-enforced). Together they close the loop: can't write a bad plan (reviewer), can't approve a shallow plan (agent), can't implement without a plan (gate).
