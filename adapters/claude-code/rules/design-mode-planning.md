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

## Pre-Submission Class-Sweep Audit (mandatory before invoking systems-designer)

**Classification:** Pattern (planner self-applied discipline). Hook-backed presence check planned but not yet implemented — see "Enforcement summary" below for current state.

An eight-round `systems-designer` review effort on a Mode: design plan (an OAuth + IMAP auth-refactor, reviewed 2026-04-28) surfaced 11 distinct failure classes; 6 of them shared a single root cause: **the plan author didn't perform a class-sweep before submitting to the reviewer.** The reviewer ended up finding sibling instances of the same class one round at a time over 4-8 rounds. One thorough upfront sweep would have collapsed the iteration to 1-2 rounds.

This rule is the upfront sweep. **Before invoking `systems-designer` (or any adversarial plan-reviewer agent), the plan author MUST perform a class-sweep audit covering five dimensions, document the result inline in a new `## Pre-Submission Audit` section, and fix all gaps found.** The reviewer is a safety net, not the primary discovery mechanism.

### The five sweeps

For each sweep below, run the `Sweep query`, triage every match, document the count, fix the gaps. Document one line per sweep in the `## Pre-Submission Audit` section of the plan.

#### S1. Entry-Point Surfacing

**Goal:** every behavior change documented in Sections 1-10 (analysis sections) must be cited at the corresponding implementation entry points (Task description + Files-to-Modify entry for each affected file). A builder reading just the entry points should see every change without scanning all 10 sections.

**Sweep query:** `rg -n 'add|emit|log|retry|fall back|skip|replace|advance|store|cap|new behavior|changes from' <plan-file>`

**Triage:** for each match in Sections 1-10, find the corresponding citation in the Tasks section AND the Files-to-Modify entry for the file the change lives in. If absent, ADD the citation (one sentence per behavior change in each entry point, with a back-reference to the section).

**Why it matters:** without this, builders reading just `Tasks` + `Files to Modify/Create` (the natural entry points for execution) will skip behavior changes documented elsewhere. Failure class: `behavior-change-stranded-in-analysis-section` (FM-007).

#### S2. Existing-Code-Claim Verification

**Goal:** every reference to existing code (line numbers, function signatures, current behaviors) must be re-verified against the actual file at audit time. No claims from memory.

**Sweep query:** `rg -n 'line ?\d+|existing.*function|existing.*connector|existing.*at\s+\d+|currently\s+(does|has|returns|reads|writes)' <plan-file>`

**Triage:** for each match, open the cited file at the cited location and confirm the claim. If wrong, fix the claim.

**Why it matters:** plans authored from memory of an earlier exploration drift from the codebase. Builders following stale claims build the wrong thing. Failure class: `stale-existing-code-claim` (FM-008).

#### S3. Cross-Section Consistency

**Goal:** every claim about the same code element across multiple sections must agree.

**Sweep query:** `rg -n 'reliable|unchanged|preserved|stays|protects|catches' <plan-file>`

**Triage:** for each match, check Edge Cases / Failure-mode analysis / Idempotency for any contradictory caveat about the same element. If contradictory, reconcile: pick the more accurate view, update the other section, or commit to a third option that both sections agree on.

**Why it matters:** Sections written at different times by different mental models contradict each other silently. Builders implement one view, the other view fails at runtime. Failure class: `cross-section-contradiction` (FM-009).

#### S4. Numeric-Parameter Sweep

**Goal:** every numeric parameter (caps, batch sizes, timeouts, costs, RPM/TPM limits) must have ONE consistent value across the entire plan.

**Sweep query:** for each numeric parameter the plan defines (e.g., `max_threads_per_sync`, `BATCH_SIZE`, timeout values), run BOTH:
- Literal-number: `rg -n '\b<value>\b' <plan-file>` (finds every occurrence of the literal number)
- Prose-context: `rg -n '<parameter-name>|max|cap|limit|threads|batch' <plan-file>` (finds every place the parameter is named)

**Triage:** every match must show the same value. If a parameter changed during plan revision, sweep both queries before declaring the revision complete.

**Why it matters:** numeric parameters get changed in the section that surfaced an issue, but sibling references in unrelated sections retain old values. Cold-start path with old cap blows the rate-limit budget; capacity model with old cap claims false headroom. Failure class: `numeric-parameter-change-not-fully-swept` (FM-015).

#### S5. Scope-vs-Analysis Check

**Goal:** every "Add X" / "Modify Y" / "Replace Z" verb in Sections 1-10 must be checked against the Scope OUT list for contradiction.

**Sweep query:** `rg -n '^[-*]\s+(Add|Insert|Modify|Replace|Emit|Log)\b|prescribes|requires.*to|connector must' <plan-file>`

**Triage:** for each match, check the file/component the change targets against the Scope OUT list. If the target is OUT, EITHER move it IN (and update the analysis to acknowledge the new scope) OR remove the prescription (and replace with a non-code alternative — e.g., "operator records X in SCRATCHPAD instead").

**Why it matters:** Scope is set early; analysis sections evolve later without revisiting Scope. Plans ship with prescriptions for files the plan explicitly excludes. Builders either skip the prescription (intent lost) or violate scope (new bugs). Failure class: `scope-vs-analysis-contradiction` (FM-016).

### The `## Pre-Submission Audit` section

Add this section to the plan between `## Decisions Log` and `## Definition of Done`. Format:

```markdown
## Pre-Submission Audit

S1 (Entry-Point Surfacing): swept, N matches across Sections 6-9, M cited correctly, K added to Tasks/Files
S2 (Existing-Code-Claim Verification): swept, N matches, M verified against file, K corrected
S3 (Cross-Section Consistency): swept, N "reliable/unchanged" claims, M reconciled, 0 contradictions remaining
S4 (Numeric-Parameter Sweep): swept for params [<list>], all values consistent
S5 (Scope-vs-Analysis Check): swept, N "Add/Modify" verbs, all checked against Scope OUT, 0 contradictions
```

If a sweep returns zero matches, write "swept, 0 matches" — don't omit the line.

### When the audit doesn't apply

`Mode: code` plans don't require this audit. Trivial plans (single-task, single-file) may write "n/a — single-task plan, no class-sweep needed" for each line.

`Mode: design-skip` plans skip the audit (per existing escape-hatch rules).

`Mode: design` plans MUST run the audit. The plan-reviewer.sh hook (when extended — see Enforcement summary) will block submission to systems-designer without it.

## Quantitative Claims Must Be Validated, Not Asserted

**Classification:** Hybrid. Pattern in this rule (planner self-applied discipline). Mechanism extension via `plan-reviewer.sh` flagging comparative phrases without inline numerics — planned, not yet implemented; see "Enforcement summary" table at the bottom of this file for current status.

Every quantitative claim in a plan ("under X RPM", "exceeds Y bytes", "costs Z dollars per call", "fits within W timeout", "30% margin") MUST satisfy ALL of:

1. **Inline arithmetic in the same paragraph as the claim.** Show the multiplication, the comparison, the result. Not "60 calls, within tier limits" but "60 calls (15 threads × 2 calls × 2 batches × 1 sync) ÷ 60s sliding window = 60 calls/min < 50 RPM tier limit." Wait — that math is wrong. That's the point: arithmetic shown is arithmetic checked.

2. **Re-validated by the planner before submission.** Do the math by hand, OR — preferred — commit a small re-derivation script (Deno one-liner, bash + bc, etc.) to the plan or evidence file. The script becomes runtime-replayable evidence.

3. **No self-contradicting hedges.** Sentences like "comfortably under X (slight over)" are forbidden. The parenthetical wins, not the comparative phrase. If the math shows the design is over a limit, write the disclosure honestly and pick a mitigation (lower the cap, accept rate-limit retries, upgrade tier). Don't narrate around the math.

4. **Honest "I don't know" acknowledgement when estimates are unmeasured.** If a per-call token estimate is a guess ("~1.5K input tokens average"), say so explicitly and name the mitigation if real averages run higher ("if real averages exceed 2K, lower the cap to 12 to fit ITPM").

**Why it matters:** the originating 2026-04-28 review effort caught Section 9 of the auth-refactor plan saying "60 calls within tier limits" against a 50 RPM cap — false by 20%. Caught again in round 3 saying "comfortably under 50K ITPM (slight over)" — self-contradicting. The math wasn't checked because the comparative phrase was written before the multiplication. Failure classes: `capacity-claim-without-arithmetic-check` (FM-013) + `capacity-claim-contradicts-its-own-math` (FM-014).

## Cold-Start Paths Inherit Steady-State Constraints

**Classification:** Pattern (planner self-applied discipline).

When a steady-state design parameter (cap, batch size, timeout budget, rate-limit envelope) is constrained in the plan, **the cold-start, reset, fallback, and recovery code paths MUST inherit the same constraint UNLESS the capacity model explicitly acknowledges the cold-start path as a separate rate-limit event with its own mitigation.**

Concrete patterns:

- If `max_threads_per_sync = 15` for steady-state syncs, the "wipe state and re-scan from scratch" path also caps at 15 (inherits config), not the original hardcoded 50.
- If a batch size is constrained to fit within a 50s timeout, the "retry after partial failure" path also obeys the same batch size, not "process all remaining items at once to catch up."
- If an initial-sync cap exists for the user-driven first run, the "reset state and re-initialize" path obeys the same cap.

**Why it matters:** authors think of "the happy path" as where the cap applies and forget that recovery paths execute the same code under the same rate limits. A 50-thread cold-start fallback after `last_synced_uid` reset bursts 100 LLM calls (2× the rate-limit cap) on first sync after the reset, even though the steady-state cap was lowered to 15. Failure class: `cold-start-path-violates-steady-state-envelope` (FM-017).

**How to verify in the plan:** Section 8 (idempotency & restart semantics) explicitly states which constraint each cold-start / reset / fallback path inherits, and Section 9 (capacity) confirms the inherited value is within budget. If a cold-start path needs a HIGHER cap than steady-state (legitimate use case: catching up after extended outage), Section 9 must model it as a separate rate-limit event with its own rate-shaping mitigation (e.g., "first sync after reset throttles batches over multiple syncs").

## Numeric-Precision Spec for ID Encoders

**Classification:** Pattern (planner self-applied discipline applied during plan authoring).

Any plan that introduces or modifies an ID encoder/decoder (source_ref encoding, dedup key computation, content-addressed hashing, any function that converts integer or string IDs between formats) MUST address numeric precision explicitly:

1. **State whether inputs may exceed `Number.MAX_SAFE_INTEGER` (2^53 ≈ 9×10^15).** Many real-world IDs do — Gmail X-GM-THRID is 64-bit unsigned (up to 2^64), Twitter snowflake IDs, Discord snowflake IDs, UUID v7 timestamps. If yes, specify BigInt parsing AND BigInt rendering end-to-end. Naive `parseInt(...).toString(16)` silently produces wrong output for any value above 2^53 — no exception thrown, just wrong output.

2. **Acceptance test required.** The plan's Tasks section MUST include an acceptance test that:
   - (a) Round-trips a known existing value through the encoder and confirms byte-identical output
   - (b) Demonstrates the precision trap exists if naive Number-based encoding is used (an `assertNotEquals(naiveEncoder(input), correctOutput)` style assertion that locks the trap closed)
   - (c) Confirms the helper accepts both string AND bigint inputs (matching the source format from APIs that deliver IDs as base-10 strings)

3. **Public API rejects raw `number` inputs to prevent reintroduction.** The encoder's TypeScript signature should be `string | bigint` — never `number`. This prevents future callers from passing a JS Number that lost precision before the encoder is called.

**Why it matters:** the auth-refactor plan's ID-encoder decision originally specified `xGmThridInt.toString(16).padStart(16, "0")` without BigInt for a 64-bit Gmail X-GM-THRID value. The example threadId `19d08d90e074b50a` decodes to decimal `1860142299484566794`, which is ~207× `Number.MAX_SAFE_INTEGER`. Without BigInt, the resulting hex would have been wrong by the last digit, silently breaking dedup against all 56 existing entities. Failure class: `numeric-precision-spec-incomplete` (FM-011).

## "Stays Identical" Must Enumerate

**Classification:** Pattern (planner self-applied discipline).

Any task description claiming a function's internals "stay identical" / "preserved" / "unchanged" MUST list **specifically** what's preserved AND **specifically** what changes per other sections. Blanket claims are forbidden.

**Bad:** "Internal logic of `processThread` stays identical." (But Section 8 requires changes inside `processThread`. Builder follows the task description literally and skips the changes. Bug.)

**Good:** "`processThread` internals: subject/from/to/date extraction, body extraction, summarize+classify+embed+upsert calls all UNCHANGED. CHANGED inside processThread (see Section 8): line-74 `message_count` early-exit replaced with UID-set subset check; upsert payload at lines 117-134 adds `message_uids` field."

**Sweep query during pre-submission audit (S6, optional):** `rg -n 'stays identical|unchanged|preserved|same as today|no changes? to' <plan-file>` — for each match, verify the surrounding text enumerates BOTH preserved and changed parts.

**Why it matters:** the auth-refactor plan's round-2 review caught a Task description saying "internal logic of `processThread` stays identical" while Section 8 of the same plan prescribed three specific changes inside that function. Builder following only the task description would have shipped the wrong implementation. Failure class: `task-acceptance-criteria-incomplete-vs-section` (FM-012).

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

| Layer | What it enforces | File | Status |
|---|---|---|---|
| Template | Shape of a correct design-mode plan | `templates/plan-template.md` | landed |
| Rule (this doc) | When to use design-mode, what each section requires, pre-submission audit, math validation, cold-start inheritance, ID precision, "stays identical" enumeration | `rules/design-mode-planning.md` | landed |
| plan-reviewer.sh | 10 sections present, non-empty, no placeholder text | `hooks/plan-reviewer.sh` | landed |
| plan-reviewer.sh extension (Check 8A) | `## Pre-Submission Audit` section presence + structure on Mode: design plans (FAIL when missing OR when body has neither the canonical full-sentence carve-out nor 5 distinct sweep tokens S1/S2/S3/S4/S5) | `hooks/plan-reviewer.sh` | **landed** — gates S1 mechanically; via `docs/plans/pre-submission-audit-mechanical-enforcement.md` |
| plan-reviewer.sh extension (Checks 8B/8C/8D/8E/8F) | "Either/or" detection in Decisions Log (8B), "stays identical" without enumeration (8C), comparative phrases without inline numerics (8D), Scope-OUT cross-check (8E), numeric-parameter sweep manifest (8F) | `hooks/plan-reviewer.sh` | **deferred** — see `docs/plans/pre-submission-audit-mechanical-enforcement.md` Decisions Log D-1 (8B/8C/8D rejected as cheap-evasion / WARN-on-prose-regex) and D-3 (8E/8F deferred until upstream format-enforcement gates land) |
| systems-designer agent | 10 sections are substantive and task-specific (sweeps S2/S3 partially covered via per-section adversarial review) | `agents/systems-designer.md` | substance-check landed; audit-section-required precondition deferred per D-1 (ceremony-not-mechanism without independent sweep verification) |
| systems-design-gate.sh | No design-mode file edits without a valid plan | `hooks/systems-design-gate.sh` | landed |
| plan-reviewer.sh extension (Check 11) | C16 `## Behavioral Contracts` schema check on `rung: 3+` plans — section presence + four named sub-entries (`### Idempotency`, `### Performance budget`, `### Retry semantics`, `### Failure modes`), each ≥ 30 non-ws chars and non-placeholder | `hooks/plan-reviewer.sh` | **landing in Phase 1d-C-2** (Task 6 of `docs/plans/phase-1d-c-2-prd-validity-and-spec-freeze.md`) — gates the contract surface mechanically; substance still relies on planner discipline + systems-designer per-section review |

The first two are documentation (pattern-level). The mechanism stack (`plan-reviewer.sh` with Check 8A + Check 6b + Check 7, `systems-designer`, `systems-design-gate.sh`) is hook-and-agent-enforced. Together they close the loop: can't write a bad plan (reviewer), can't bypass the audit declaration (Check 8A), can't approve a shallow plan (agent), can't implement without a plan (gate).

**Mechanization status by sweep:**
- **S1 (Entry-Point Surfacing):** mechanized at structure level via Check 8A — section must exist with the S1 token; substance still relies on planner discipline + systems-designer's per-section review.
- **S2 (Existing-Code-Claim Verification):** Pattern-only — needs LLM-grade reading or an explicit `file:line` citation discipline upstream.
- **S3 (Cross-Section Consistency):** Pattern-only — same reason.
- **S4 (Numeric-Parameter Sweep):** Pattern-only — Check 8F deferred until audit S4 format is tightened to `name=value` pairs (D-3).
- **S5 (Scope-vs-Analysis Check):** Pattern-only — Check 8E deferred until Scope OUT bullet format is tightened to backtick-delimited paths (D-3).
