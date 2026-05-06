# Orchestrator Pattern — Delegate Build Work to Sub-Agents

**Classification:** Pattern (documented convention), not Mechanism (hook-enforced). The `task-verifier` mandate still applies mechanically — builders invoke it, orchestrator trusts the verdict. What's documented here (dispatch discipline, parallelism protocol, cherry-pick flow) is self-applied convention that the main session is expected to follow. No hook detects "you built directly instead of dispatching." The listed backstops (tool-call-budget, pre-stop-verifier) enforce task completion correctness, not orchestration discipline — so they apply identically whether the main session or a sub-agent does the work.

**The rule in one sentence:** for any plan with more than one task, the main session orchestrates — it dispatches each task to a fresh `plan-phase-builder` sub-agent, collects the result, and moves on. The main session does NOT do the build work itself.

This pattern exists to manage context accumulation in long sessions. The main session's context grows with every tool call it makes; across a multi-phase plan that runs 200+ tool uses, that context gets large (hundreds of thousands of tokens) and slow, and subtle quality degradation becomes plausible: drift on early instructions, false memories of work not done, small hallucinations. Sub-agents get fresh context per dispatch — the builder of Phase 3 starts clean, not on top of everything Phase 1 and 2 accumulated. The orchestrator's context only grows by the dispatch call + the builder's concise summary, never by the raw tool output.

The orchestrator pattern is a quality-of-life improvement for long-plan workflows — it reduces context size, which is generally good but is independent of the hook-enforced anti-vaporware mechanisms. Those hooks (pre-commit-tdd-gate, runtime-verification-executor, plan-edit-validator) address verification self-enforcement gaps; this pattern addresses context hygiene.

## When to use orchestrator mode

**Default for any multi-task plan.** Specifically:
- Plans with ≥ 2 tasks in the task list
- Plans with a `Phase 1 / Phase 2 / ...` structure
- Plans expected to exceed ~15 minutes of build time
- Any plan with an explicit `Execution Mode: orchestrator` in its header

**NOT needed for:**
- Single-task quick fixes (e.g., "rename this function", "fix this typo")
- Doc-only edits (e.g., updating README)
- Bug reports where the user wants the main session to investigate interactively

If unsure, default to orchestrator mode. The overhead of dispatching is small; the cost of doing a multi-phase plan in one context is large.

### What "done" means for the orchestrator (incentive redesign)

**The orchestrator's reward signal is plan closure, not dispatch completion.** A plan is not "shipped" until it is `Status: COMPLETED` and archived. Code on master without a closed plan is incomplete work — the orchestrator's deliverable is the closed plan, not the commits.

Dispatching is the first part of the work; closure is the last part of the same work, not a separate phase. The orchestrator that says "all builders returned DONE, plan is shipped" while the parent plan still has unchecked boxes, no completion report, and `Status: ACTIVE` has not finished its job — it has finished the easy part. The natural LLM completion signal ("the last builder returned a verdict") is wrong here; closure is the only completion signal that matters.

This reframing is load-bearing because every other agent in the harness inherits its meaning of "done" from what the orchestrator considers done. A builder thinks "I'm done when task-verifier flips my checkbox" partly because the orchestrator that dispatches it treats checkbox-flipped as task-complete. The orchestrator's frame propagates downward.

## Parallelism — default to parallel dispatch when tasks are independent

**Parallel building is the preferred mode.** The orchestrator dispatches multiple builder sub-agents simultaneously (multiple Task tool calls in a single response) whenever the next batch of tasks is independent. Sequential dispatch is the fallback for genuinely dependent tasks, not the default.

**When to parallelize (default YES):**
- Sweep tasks where each sub-task operates on a different file (e.g., "refactor 13 dashboard pages" — dispatch all 13 at once)
- Tasks with disjoint `Files to Modify/Create` sets (Task A touches files X/Y, Task B touches Z/W → parallel)
- Independent features in the same phase (e.g., Phase 3's notify-managers + review-with-context button touch different files)
- Tasks explicitly marked `Parallelizable: yes` in the plan's task list

**When to serialize (explicit NO):**
- Tasks that share a file (merge conflicts on parallel commits)
- Tasks with explicit data dependencies (Task B's test needs Task A's migration applied)
- Tasks that compete for the same resource (same migration number, same API route path, same component name)
- Tasks that both need the dev server (port conflict on `npm run dev`)
- Tasks the plan marks `Serial: yes` or `Depends on: <task-id>`

**When in doubt: serialize.** The cost of a false-positive parallelization (hitting a merge conflict mid-run) is higher than the cost of a false-negative (running sequentially when parallel would have worked). The orchestrator can always up-shift later tasks to parallel once the dependency pattern is clear.

### Isolating parallel builders

Parallel builders MUST run in isolated git worktrees. Use the Task tool's `isolation: "worktree"` parameter on each parallel dispatch.

**Verification this parameter exists:** it is defined on the `Agent` tool schema in the Claude Code runtime system prompt (not in `~/.claude/` config files — reviewers who grep only `~/.claude/` will miss it). The parameter's docstring reads: "Isolation mode. \"worktree\" creates a temporary git worktree so the agent works on an isolated copy of the repo." With `isolation: "worktree"` set, the worktree is automatically cleaned up if the agent makes no changes; otherwise the path and branch are returned in the result.

**Empirical verification of parallel dispatch:** on 2026-04-16 at 04:58 UTC, two trivial Agent calls were dispatched in a single response, each returning its Bash `date` timestamp as the first action. Agent A returned `04:58:14.754`; Agent B returned `04:58:15.283`. Delta: 529ms. Serial execution would have produced a delta of ~5+ seconds (Agent A's full duration before Agent B started). This confirms multiple Agent invocations in one response run concurrently. Citation: see also the Claude Code runtime system prompt's tool-use guidance, which states: *"If the user specifies that they want you to run agents 'in parallel', you MUST send a single message with multiple Agent tool use content blocks."*

**Why worktrees:** git branch state is a shared resource. Two builders trying to `git commit` on the same working directory at the same time will race and produce a corrupted history. Worktrees give each builder its own working directory pointing at the same `.git` — commits are safe, file-level operations are isolated.

The Task tool auto-cleans up worktrees that made no changes. Worktrees that DID make commits persist until the orchestrator merges them back.

### Worktree base is master HEAD — builders MUST switch to feature branch first

**Empirically confirmed 2026-05-04:** the Agent tool's `isolation: "worktree"` creates each worktree rooted at **master HEAD**, not the orchestrator's current branch HEAD. On feature branches with commits ahead of master (the common case), this means the worktree's working directory does NOT contain the orchestrator's recent commits — including, critically, the active plan file in many cases. Without correction, `scope-enforcement-gate.sh` blocks the builder's commit because no ACTIVE plan claiming the modified files is visible inside the worktree.

**The correction is mandatory: every parallel-mode dispatch prompt MUST include a first-action instruction for the builder to checkout a worker branch from the orchestrator's feature branch.** The feature branch ref IS visible inside the worktree (worktrees share `.git/refs` with the parent repo); the builder just needs to land HEAD there.

Concrete first-action instruction to embed in the dispatch prompt:

```
Before doing any work, run this command first to land your worktree on the orchestrator's
feature branch:

    git checkout -b worker-<task-id> <feature-branch-name>

Replace <task-id> with the task you're building (e.g., "worker-3.2") and
<feature-branch-name> with the orchestrator's branch (e.g., "build-doctrine-integration").

After this command, your worktree HEAD is at the feature branch tip; all plan files,
recent commits, and uncommitted-but-tracked work are visible. Confirm by running
`git log --oneline -3` and verifying the latest commit matches what the orchestrator
told you in this prompt.

Then proceed with your task. Your work commits land on `worker-<task-id>`. The
orchestrator will cherry-pick them back onto the feature branch in Phase B.
```

**Why this works:** worktrees share `.git/objects` and `.git/refs` with the parent repo. The feature branch ref is therefore in the worktree's view. The worktree just initializes its working directory at master HEAD; `git checkout -b <worker-id> <feature-branch>` creates a NEW branch from the feature branch's tip (no conflict with the parent's checkout) and updates the working directory accordingly.

**What this does NOT solve:** if the orchestrator's feature branch has truly uncommitted changes (i.e., not yet committed at the time of dispatch), the worker branch will not see them. Mitigation: the orchestrator MUST commit any plan-file edits, evidence blocks, or other state needed by parallel builders BEFORE dispatching them. This is the discipline already in place (commit at every milestone) — the worktree-base behavior just makes it strictly required for parallel dispatch.

**Auto-cleanup interaction:** worktrees that made commits persist until the orchestrator cleans them up (per the cherry-pick protocol below). The worker branch (`worker-<task-id>`) and the worktree-internal branch (`worktree-agent-<id>`) are both deleted in step e of the cherry-pick protocol.

### Build-in-parallel, verify-sequentially

This is the critical discipline. Parallel builders can race on build work (tests, file edits, commits in their own worktrees). But the **plan file + evidence file** are shared resources that CANNOT be updated in parallel safely:

- Two `task-verifier` invocations flipping different checkboxes at the same time can race on the plan file's text
- Two evidence block writes can interleave or overwrite each other
- The `plan-edit-validator` hook's 120-second window doesn't handle concurrent writes cleanly

So the protocol is:

1. **Phase A (parallel):** dispatch N builders, all with `isolation: "worktree"`. They build in parallel in their own worktrees, commit there, and return `{verdict, worktree_path, commit_shas, summary}`. Builders DO NOT invoke task-verifier in this phase — they just build and commit.

2. **Phase B (sequential):** the orchestrator processes each returned result in sequence using this concrete cherry-pick protocol:

   For each returned builder result, processed **in plan-task-ID order** (deterministic — ensures evidence-block ordering matches task numbering across re-runs):

   a. **Identify the commits to import:** the builder's return includes `Commits: <SHA1> [<SHA2> ...]`. These are in worktree-local branch HEAD order (oldest first). If the builder used multiple commits, apply them in that order.

   b. **Cherry-pick onto the feature branch:**
      ```bash
      git cherry-pick <SHA1> [<SHA2> ...]
      ```
      Run once per commit, from the feature branch's working directory (NOT the worktree).

   c. **Handle conflicts:** if cherry-pick hits a conflict, something is wrong with the parallelism assumption (the task touched a file another task also touched). In that case:
      - Abort: `git cherry-pick --abort`
      - Mark this task's result as BLOCKED with the conflict file(s) listed
      - Do NOT force-resolve the conflict — the orchestrator dispatched two tasks that shouldn't have run in parallel. Surface this to the user, serialize future dispatches more carefully.

   d. **Invoke `task-verifier`** for that specific task (evidence block + checkbox flip).

   e. **Tear down the worktree:**
      ```bash
      git worktree remove <worktree_path>
      git branch -D <worktree_branch>
      ```
      If `--force` is needed because of uncommitted state, abort instead and surface the anomaly — the builder should not have left uncommitted state in its worktree.

   f. **Move to next result.** If any step c-e failed, stop processing further results until the user resolves the blocker.

   **Recovery from orphaned worktrees:** if the orchestrator dies (session ends, crash, user interrupt) between a builder's commit and step b's cherry-pick, the worktree persists with unmerged commits. Recovery: `git worktree list` to find the orphan, manually cherry-pick its branch HEAD onto the feature branch, then `git worktree remove <path>` and `git branch -D <branch>` as in step e. The builder's original evidence — if any — is also stranded and must be manually re-invoked via task-verifier after the cherry-pick.

This makes the build work truly parallel (the expensive part, where most tool calls happen) while keeping the evidence-file + plan-file writes safe. The cherry-pick-then-verify-sequentially discipline is what makes the parallelism correct; skipping it invites concurrent writes to the plan file.

### Parallelism ceiling

Don't dispatch more than ~5 parallel builders at once, even when all tasks look independent. Reasons:
- Disk/IO contention with `npm test` or `npx tsc` running concurrently
- Supabase rate limits on shared test DB
- The orchestrator's summary-collection cost scales with N (each return adds to orchestrator context)
- If a builder BLOCKS, the orchestrator has to decide what to do with N-1 in-flight results

For sweep tasks with > 5 sub-tasks: batch them in groups of 3-5. Dispatch 5 in parallel, wait, process their results, dispatch the next 5.

## The dispatch protocol

**Plan header owns backlog metadata, not builder output.** The plan file's header declares `Backlog items absorbed: [...]` (see `planning.md` → "Backlog absorption at plan creation"). The orchestrator reads this header at task-verifier time to mark those items as shipped in the backlog's Completed section on plan completion. **Builders are NOT asked to report backlog mapping in their return shape** — metadata lives where it was authored (in the plan header), not duplicated in builder output. Do NOT ask builders for a `backlog_items_addressed` field or any other backlog mapping in their returns; the builder return contract below is the complete set of fields expected.

For each batch of tasks (one if serial, up to 5 if parallel):

1. **Pick the next batch of tasks** from the plan. For parallel batches: group tasks whose `Files to Modify/Create` sets are disjoint, up to 5. For serial batches: one task. One builder per task is the default granularity within a batch. You MAY bundle tightly-coupled tasks (e.g., "2.1 + 2.2 + 2.3 are one coherent change") into a single builder dispatch IF they're in the same commit anyway, but never bundle across phases.

2. **Invoke `plan-phase-builder` via the Task tool** with a self-contained prompt. For parallel batches: invoke N Agents in a single response (multiple tool calls in one message block) each with `isolation: "worktree"`. For serial: one Agent call (worktree optional — bare main-branch commit is fine for sequential execution).

   Each prompt MUST include:
   - Plan file absolute path
   - Task ID(s) in scope (e.g., `3.2` or `3.2, 3.3, 3.4`)
   - One-line task description (what to build)
   - Branch name + current HEAD commit
   - Key ENV vars the builder needs (e.g., `E2E_PLATFORM_ADMIN_EMAIL must be in .env.local`)
   - Explicit "do NOT start the next task" instruction
   - Reference to the acceptance criteria in the plan ("see Done when: section under Task 3.2")
   - **The plan's `## Acceptance Scenarios` section verbatim** (when the plan has one) — see "Scenarios-shared, assertions-private" below for the discipline
   - For parallel dispatch: "DO NOT invoke task-verifier. Build, commit in your worktree, and return verdict. The orchestrator will run task-verifier sequentially after collecting all parallel results."
   - For serial dispatch: "Invoke task-verifier yourself; it will flip the checkbox and write evidence."

3. **Collect the builder's return.** Expected shape:
   ```
   Verdict: DONE | BLOCKED | PARTIAL | FAIL
   Summary: <one-to-three sentences describing what shipped>
   Commits: <list of commit SHAs on the feature branch>
   Task-verifier verdict: PASS | FAIL | INCOMPLETE (the builder must have invoked task-verifier)
   Blockers (if any): <specific thing that stopped progress, with enough detail that the user or a future dispatch can unblock it>
   Follow-ups (if any): <items the builder identified but deferred, belonging in docs/backlog.md>
   ```

4. **Update SCRATCHPAD** with the commit SHA and move to the next task. The main session does NOT re-verify — task-verifier already did. If the builder returned PASS and task-verifier returned PASS, trust the result.

5. **On BLOCKED or FAIL:** stop dispatching. Report the blocker to the user with the builder's specific detail. Do not try to route around the block by dispatching the next task — that was the exact "drop this task and move on" failure mode `planning.md` explicitly prohibits.

6. **On PARTIAL:** decide whether to re-dispatch with scope narrowed, or treat as BLOCKED and stop. If the PARTIAL is a known limitation (e.g., "test coverage is incomplete because a testing library isn't installed"), mark the task DONE with the limitation logged in the evidence block, AND add the limitation to `docs/backlog.md`.

7. **On plan completion:** **closure is the orchestrator's primary deliverable.** Dispatching is the first part of the work; closure is the last part of the same work, not a separate phase. The orchestrator writes the completion report using `~/.claude/templates/completion-report.md`, flips the parent plan's task checkboxes (under the lightweight-evidence pattern when applicable), updates SCRATCHPAD, transitions `Status:` to `COMPLETED` (which auto-archives the plan via `plan-lifecycle.sh`), and reports to the user. Until all of that has happened, the plan is in flight — "all builders returned DONE" is not a completion signal; the closed-and-archived plan is.

## Scenarios-shared, assertions-private

**The discipline:** when a plan has a `## Acceptance Scenarios` section authored by the `end-user-advocate` (see `rules/acceptance-scenarios.md`), the orchestrator's dispatch prompt to each builder MUST include those scenarios verbatim — but MUST NOT include the advocate's internal runtime assertion list. Scenarios are shared with the builder so the builder is aligned on the user-observable outcome the build must produce. Assertions are private to the advocate so the builder cannot teach to the test.

**What counts as a scenario (shared with builder):**
- The numbered user-flow steps a real user would take (e.g., "1. Open campaigns list. 2. Click Duplicate on a campaign. 3. Confirm a copy appears with name suffix '(Copy)' and the original is unchanged.")
- The prose success criteria (what the user expects to be true when the flow completes)
- Optional edge variations the plan-time advocate flagged as in-scope
- Authentication / state preconditions (e.g., "scenario assumes a logged-in user with Manager role")

**What counts as an assertion (private to the advocate):**
- The exact selectors, DOM queries, network-request URLs, or text fragments the runtime advocate uses to verify a step
- The semantic checks the advocate runs against the live page (e.g., "after click, the order-total cell equals the sum of the input rows")
- Any internal heuristics the advocate uses to decide PASS vs FAIL (timing thresholds, retry counts, screenshot diffs)
- Any failure-class taxonomy the advocate maintains internally for routing FAILs to the gap-analyzer

**The Goodhart rationale.** LLM builders are exceptionally good at teaching-to-the-test. If the builder sees the exact assertion strings ("the page contains the text 'Saved successfully'"), the builder optimizes for the assertion text, not the outcome — it will hardcode the literal string into the page even when the underlying state is wrong. Goodhart's law in its sharpest form: when a measure becomes a target, it ceases to be a good measure. The harness mitigates this by keeping the runtime measure (assertions) out of the builder's optimization surface. Builders see the user-observable scenario; the advocate keeps the verifying assertions private and runs them against the actual user-facing surface.

**Why scenarios are shared anyway.** The complementary failure mode — assertions-private AND scenarios-private — produces a different failure: the builder underspecifies because it doesn't know what the user must accomplish. A builder told only "implement the Duplicate Campaign feature" will produce a button that fires `console.log('duplicate')` and call it done; the runtime advocate will FAIL it; iteration costs are then inflated. Sharing the scenarios closes that gap: the builder knows exactly what user flow must succeed, but does not know which DOM-level checks the advocate will use to verify the success.

**Mechanics in the dispatch prompt.** When constructing the builder's prompt, the orchestrator copies the entire `## Acceptance Scenarios` section from the plan file verbatim into the prompt. The orchestrator does NOT invoke the end-user-advocate to extract the assertion list — the assertion list lives only in the advocate's runtime invocation, in a fresh sub-agent session that the builder cannot inspect. If the plan has no `## Acceptance Scenarios` section (acceptance-exempt plans, pure-docs plans), this clause is a no-op.

**What the builder sees in its prompt** (illustrative excerpt):

```
## Acceptance Scenarios (verbatim from the plan — these flows must work for the user)

### Scenario 1.1 — duplicate-campaign-happy-path
1. Logged-in Manager opens the Campaigns list page.
2. Clicks the Duplicate button on the first listed campaign.
3. Sees a new row appear at the top of the list, with name suffix "(Copy)".
4. The original campaign's row is unchanged.
Success criteria: the new row has the same fields as the original except for name suffix and a cleared scheduled time.

[... additional scenarios ...]

DO NOT attempt to enumerate the runtime assertions the end-user-advocate will use.
The advocate will execute these scenarios against the running app in a fresh sub-agent
session before the harness allows session end. Build such that the user flow above
actually works for a real user, not such that any specific assertion string is satisfied.
```

**What the builder does NOT see:** the advocate's planning-time draft of "I will check that `[data-testid="campaign-row"]` count increased by 1 within 2s, and that the first row's `[data-testid="campaign-name"]` text matches the regex `.*\(Copy\)$`." Those internal checks live only in the advocate's runtime sub-agent and never enter the builder's prompt or reasoning surface.

**Cross-task signal mode.** If the orchestrator notices a scenario applies to multiple tasks in the same phase (e.g., scenario 1.1 covers both Task 3.2's UI button AND Task 3.3's API endpoint), the orchestrator includes the scenario in BOTH dispatch prompts. Builders may overlap on shared scenarios; the assertion-privacy property is preserved because neither builder sees the assertions regardless.

**Failure mode this discipline addresses.** Without it, builders that know they will be acceptance-tested either (a) under-build because they don't know what success looks like, or (b) over-fit to the test surface because they DO know. Sharing scenarios fixes (a); withholding assertions fixes (b). The two together produce the right alignment: builder optimizes for the user-observable outcome, advocate independently verifies the outcome.

## Output contract for `plan-phase-builder` sub-agents

Builder sub-agents should aim for under 500 tokens in their return. This is guidance, not a hook-enforced limit — the main session will still accept longer returns, but a builder consistently producing 5K-token reports is consuming orchestrator context unnecessarily. They MUST NOT return:
- Full file contents they edited
- Raw tool transcripts
- Verbose reasoning about decisions (those go in the commit message + decision records)
- Speculative follow-up ideas unrelated to the task

They MUST return:
- The verdict shape above
- Enough detail that the orchestrator can update SCRATCHPAD without reading anything else

If a builder returns a 10K-token report, that's a bug in the builder's discipline. The orchestrator should push back ("your summary is too long; return just the verdict block") rather than swallow the full report.

## The main session is lean, not idle

The orchestrator's job is NOT just dispatching — it's also:
- **Reading the plan first** to understand scope and dependencies
- **Deciding dispatch granularity** (one task vs. a coherent cluster)
- **Watching for cross-task signals** — if Task 3.2 introduces a pattern that Task 3.3 should follow, the orchestrator surfaces it in 3.3's dispatch prompt
- **Updating SCRATCHPAD between dispatches** so any session-end handoff is clean
- **Invoking `plan-evidence-reviewer` periodically** at phase boundaries or when tool-call-budget fires — these reviewer calls STAY in the orchestrator, they don't get delegated
- **Answering user questions** during the build (humans may interrupt with questions; those go to the orchestrator, not a builder)

The orchestrator is NOT a passive dispatcher. It's the persistent quality layer.

## Nested verification

Builders invoke `task-verifier` themselves, per the existing `task-verifier` mandate. The orchestrator does NOT re-verify a builder's work — task-verifier already did. The orchestrator trusts the `task-verifier` PASS/FAIL verdict as the authoritative signal.

This matters because: re-verifying would mean the orchestrator reads the builder's commits and runs checks itself, which dumps build detail back into the orchestrator's context. The whole point is to keep that detail OUT.

If the orchestrator has reason to doubt a builder's claim (builder returned DONE but the commit SHA doesn't exist, builder returned PASS but no task-verifier invocation is evident in its summary), the orchestrator dispatches `plan-evidence-reviewer` to independently check — that agent is the "audit" role, distinct from task-verifier.

## When the orchestrator itself should hand off

Rare, but possible: very large plans (15+ tasks) where even the orchestrator's lean context grows meaningful. Signs:
- SCRATCHPAD has accumulated > 5 phase transitions
- Orchestrator has been running > 2 hours
- Tool-call-budget has fired 3+ times

At that point, the orchestrator writes a detailed continuation prompt, commits it, and reports to the user. A fresh session reads the plan + SCRATCHPAD + continuation prompt and becomes the new orchestrator. Sub-agents are stateless dispatches, so no handoff state is lost there.

## Anti-patterns (do NOT do these)

1. **"I'll just do this one task myself, it's small."** No. That's how the main session accumulates context. Dispatch it.

2. **"I'll dispatch but also read all the files myself so I can guide the builder."** No. The builder reads what it needs. If you've already read a file that's relevant, reference it in the dispatch prompt by file path — don't paste the contents.

3. **"I'll re-verify the builder's work after task-verifier passed."** No. Pass through the verdict.

4. **"I'll bundle Phases 1, 2, and 3 into one builder because they're related."** No. One builder per task by default. Bundle only when tasks land in a single commit AND are in the same phase.

5. **"The builder returned a long report, I should summarize it for SCRATCHPAD."** No. The builder should have returned a short report. Push back and have the builder return the correct shape.

6. **"I'm already deep in context so there's no point dispatching now."** No. The moment you realize you're deep is the moment to stop directly building and start dispatching. Your next dispatches still benefit from your existing context staying stable — you're not going to do BETTER by piling on.

7. **Dispatching install-class work without a `--dry-run-first` clause in the prompt.** When a builder's scope includes modifying a script that mutates shared state (`install.sh`, deploy scripts, migration runners, settings-config writers, or any tool whose invocation changes files under `~/.claude/`, remote repos, databases, or other users' workspaces), the dispatch prompt MUST instruct the builder to run the tool with `--dry-run` first (or its equivalent) and report the output before executing the real command. Worktrees are convention-level isolation; a path typo in a Write call silently writes to the wrong directory, and the only signal is indirect (a later test reads stale content). A `--dry-run` invocation produces a visible-outcome delta *before* any mutation, turning a class of silent failures into visible errors. This rule exists because on 2026-04-18 a builder modifying `install.sh` accidentally ran a full install against the main repo path while testing `--help`; the mistake was detected only because a subsequent test read the pre-edit file. A `--dry-run-first` discipline would have caught the path error before any filesystem mutation.

## Enforcement status (honest)

This is a Pattern-class harness rule, not a Mechanism. It is NOT hook-enforced and there is no mechanical gate that detects "main session is building directly instead of dispatching." The rule is self-applied.

**What DOES still apply mechanically, independent of this pattern:**
- `task-verifier` still gates checkbox flips on plan files. Whether the builder is a sub-agent or the main session, task-verifier must be invoked and its verdict is authoritative.
- `tool-call-budget.sh` fires every 30 Edit/Write/Bash calls in the main session and forces a plan-evidence-reviewer audit before proceeding. This provides indirect pressure toward dispatching (because dispatches are single Task tool calls, not counted by the budget hook) but is not a discipline check.
- `pre-stop-verifier.sh` validates evidence blocks at session end. Identical behavior whether main session or sub-agent produced them.
- `plan-edit-validator.sh` enforces the evidence-first protocol on plan file edits. This is what makes "parallel builders must not invoke task-verifier" safe in practice — if two concurrent task-verifiers try to edit the plan file, the validator's 120s-freshness check will let one succeed and the other fail. The serialized verify-after-parallel-build discipline is therefore belt-and-suspenders, not strictly required for correctness, but strongly recommended to avoid confusing failure modes.

**What is NOT enforced:**
- Whether the main session chooses to dispatch vs. build directly
- Whether a parallel-mode builder sticks to PARALLEL mode discipline
- Whether a builder returns a concise summary or a sprawling one

**Known mechanical enforcement gaps (future work, listed in neural-lace backlog):**
- A PostToolUse hook that detects "main session has made 20+ consecutive Edit/Write calls on a multi-task plan without a Task invocation" and surfaces a reminder (not a hard block — this pattern has legitimate exceptions)
- A PreToolUse hook on Task invocations that parses the prompt for "Dispatch mode: PARALLEL" and marks the sub-agent session with an env var; the builder's task-verifier invocation attempt is then blocked if the env var says PARALLEL
- A concurrency guard on `plan-edit-validator.sh` that rejects overlapping plan-file edit attempts within N seconds

These are welcome additions. Until they exist, this pattern works on discipline + the existing task-verifier mandate.

## Agent Teams pairing

The orchestrator pattern (`Execution Mode: orchestrator`) and Agent Teams (`Execution Mode: agent-team`) are TWO COEXISTING execution modes for multi-task plans. They are not alternatives that replace each other; a downstream session picks one based on the work's coordination shape, and the harness supports both.

**`Execution Mode: orchestrator` (default).** Everything in this rule applies. The main session reads the plan, dispatches each task to a `plan-phase-builder` sub-agent via the Task tool, collects the result, and moves on. Verification is sequential: `task-verifier` is invoked after the build commit lands, flips the checkbox, and writes the evidence block. Parallel dispatch goes through worktree-isolated builders; the orchestrator cherry-picks back and verifies sequentially. This is the more thoroughly battle-tested mode and is the right choice for ~95% of multi-task plans.

**`Execution Mode: agent-team`.** A lead session uses Anthropic's experimental Agent Teams feature (gated by `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` AND `enabled: true` in `~/.claude/local/agent-teams.config.json`). Teammates spawn into a team, message each other directly, and pull from a shared task list rather than receiving pre-assigned dispatches. The harness gates that protect the orchestrator's flow (`plan-edit-validator.sh` flock, `tool-call-budget.sh` team-aware mode, `task-created-validator.sh`, `task-completed-evidence-gate.sh`, multi-worktree acceptance aggregation) extend into `agent-team` mode, but the coordination shape is fundamentally different — teammate-to-teammate, not lead-to-builder. Documented end-to-end in `~/.claude/rules/agent-teams.md`.

### When BOTH could apply, prefer orchestrator

If the work could be done in either mode (e.g., a multi-task plan where teammates COULD coordinate via shared-task-list but ALSO could be dispatched in parallel), pick orchestrator. Reasons:

- Orchestrator is the more thoroughly battle-tested mode. Every Gen 4 / Gen 5 anti-vaporware mechanism (`pre-commit-tdd-gate.sh`, `runtime-verification-executor.sh`, `plan-edit-validator.sh`, `pre-stop-verifier.sh`, `product-acceptance-gate.sh`) has been validated against orchestrator's lead-dispatch flow. The same gates apply in `agent-team` mode but with a wider failure surface (more teammates, more shared state, upstream-bug exposure).
- The orchestrator pattern's parallel-builder discipline (`isolation: "worktree"`, build-in-parallel + verify-sequentially via cherry-pick) already covers the common "we have multiple independent tasks" case without the upstream-bug surface that Agent Teams carries (#50779 inbox-deferral, #24175 macOS+tmux event drops, #43736, #24073, #24307).
- Reach for `agent-team` only when the work genuinely needs continuous teammate-to-teammate coordination, task negotiation between teammates, or maintainer-driven evaluation of the Agent Teams integration itself. See `~/.claude/rules/planning.md` "When to use `Execution Mode: agent-team`" for the full decision tree.

### Anti-pattern — don't mix modes within a single plan

A single plan declares ONE `Execution Mode` in its header. Do not start a plan in `orchestrator` mode and switch to `agent-team` mid-build, or vice-versa. Reasons:

- The plan-time advocate scenarios, evidence-block conventions, task-verifier invocations, and acceptance artifacts are all keyed to the plan's declared execution shape. Switching modes mid-plan invalidates the audit trail and confuses every downstream gate.
- Mixed-mode plans force the maintainer to mentally context-switch between two coordination shapes, which is exactly the failure mode the "one mode per plan" rule prevents.
- If you genuinely need to switch (e.g., the plan turned out to need continuous coordination that orchestrator can't express), the correct action is to mark the current plan `Status: DEFERRED` with a one-line reason, then create a new plan with the right `Execution Mode` from the start. The deferred plan returns to the backlog if it had absorbed items, and the new plan picks up where the old one left off with the right coordination shape declared from line 1.

### Cross-references

- `~/.claude/rules/agent-teams.md` — full Agent Teams mechanics, upstream-bug list, configuration knobs, and the Spawn-Before-Delegate pattern.
- `~/.claude/rules/planning.md` "When to use `Execution Mode: agent-team`" — the decision tree for choosing between modes.
- `docs/decisions/012-agent-teams-integration.md` — the design rationale: per-team tool-call-budget scope, `force_in_process: true` default, worktree-mandatory-for-write, TaskCreated/TaskCompleted enforcement, lead-aggregate acceptance, feature-flag gating.

## How this pattern interacts with existing rules

- `planning.md`: unchanged. Orchestrator reads + writes plan files the same way, just dispatches the build.
- `vaporware-prevention.md`: unchanged. Runtime verification, evidence blocks, anti-vaporware all still apply — the builder owns them for its scope, same as main-session builds used to.
- `task-verifier` mandate: unchanged. Only task-verifier flips checkboxes. Builders invoke it, orchestrator doesn't.
- `tool-call-budget.sh`: unchanged. The BUILDER's tool calls count against ITS OWN budget (separate process). The orchestrator's tool calls count against the main-session budget, which stays low because dispatches are a few calls each.
