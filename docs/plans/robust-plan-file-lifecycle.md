# Plan: Robust Plan File Lifecycle — Protection, Archival, and Lookup

Status: ACTIVE
Execution Mode: orchestrator
Backlog items absorbed: none

## Goal

Make plan files durable, self-organizing, and findable throughout their lifecycle — without relying on human discipline at any stage. Three mechanisms, one integrated system:

1. **Commit-on-creation protection** — when a new plan file is written, the harness surfaces a loud reminder that it must be committed immediately so concurrent sessions can't wipe it
2. **Auto-archival on status transition** — when a plan's Status field changes to terminal (COMPLETED, DEFERRED, ABANDONED, SUPERSEDED), the file is moved to `docs/plans/archive/` in the same edit cycle. Marking a plan complete and archiving it are one action, not two.
3. **Archive-aware lookup** — when any part of the harness (agents, hooks, Claude sessions) looks up a plan by name, it transparently resolves whether the plan is active or archived

### Why This Is One Plan, Not Three

Each mechanism depends on the others to be useful:

- Auto-archival is pointless if plans can be lost before reaching terminal status
- Archive-aware lookup is pointless if plans never actually get archived
- Commit-on-creation protection is pointless if the eventually-archived file can't be found later
- All three share the same infrastructure — a lookup helper, documentation in `planning.md`, and mirror-to-neural-lace work

Previous failures that motivate each:

- **A downstream-project plan was wiped** by a concurrent session's git operation because the plan file had been written but not committed → motivates commit-on-creation
- **This very plan was wiped** by a concurrent session on first authoring attempt, before I committed it — proving the hazard is real and recurring → motivates commit-on-creation (strongly)
- **13 terminal-status plans accumulated** in `docs/plans/` over weeks because no mechanism moved them when they completed → motivates auto-archival
- **Stale path references** in docs, memory, and git commit messages will fail to resolve once plans move → motivates archive-aware lookup

All these failures fit the same pattern: "mechanism requires human discipline that doesn't reliably happen." Hooks exist precisely to close those gaps.

## The Unified Lifecycle (Design)

### Stage 1: Creation
- Claude writes a new plan file at `docs/plans/<slug>.md`
- `plan-lifecycle.sh` PostToolUse hook detects the Write and surfaces: "⚠ Plan file `<slug>.md` was created but is not yet committed. Uncommitted plan files can be wiped by concurrent sessions. Commit now: `git add <path> && git commit -m 'plan: <slug>'`."
- Session is expected to commit within the same session. If the session ends with an uncommitted plan file, the pre-stop-verifier surfaces a final warning.

### Stage 2: In Progress
- Plan is committed, work proceeds on branch
- Normal mechanics apply: `task-verifier` agent flips checkboxes, evidence-first protocol enforced by `plan-edit-validator.sh`
- No lifecycle hook activity needed at this stage

### Stage 3: Status Transition to Terminal (the atomic archival)
- Session's final plan edits are: (a) append completion report if applicable, (b) flip `Status:` to terminal value
- Status transition IS the archival trigger — they are one action
- `plan-lifecycle.sh` detects the Status field change (non-terminal → terminal) in the edited plan file
- Hook executes `git mv docs/plans/<slug>.md docs/plans/archive/<slug>.md` immediately
- If `<slug>-evidence.md` exists, hook moves it too (same commit)
- Hook emits a system message: "📦 Plan `<slug>` transitioned to [STATUS] and was archived. Subsequent references should use: `docs/plans/archive/<slug>.md`"
- Session's next commit captures both the Status change AND the file rename in one atomic operation

### Stage 4: Post-Archival Lookup
- Any lookup of the plan by name uses archive-aware resolution
- Shared helper `find-plan-file.sh` resolves slug → full path (active preferred, archive as fallback)
- Agent prompts include fallback instructions for plan paths
- Claude sessions use `Glob docs/plans/**/*.md` for cross-directory search
- Hooks that need plan lookups use the shared helper

### Important Convention: Status is the Last Edit

Because the Status transition triggers an immediate file move, the Status field MUST be the **last edit** made to a plan file in its active life. Any completion report, final decisions log entries, or closing notes must be written BEFORE flipping Status. Otherwise:

1. Session writes Status: COMPLETED
2. Hook moves file to archive
3. Session tries to append completion report at the old path → fails (file moved)
4. Session has to recover using the new path

This convention is documented in `planning.md` as part of the completion workflow.

### Recovery From Premature Archival

If a session accidentally writes `Status: COMPLETED` (typo, mistaken state, etc.) and the hook archives:

1. `git mv docs/plans/archive/<slug>.md docs/plans/<slug>.md` to restore
2. Edit Status back to the correct value
3. Hook does NOT fire on archive → active transitions (only on terminal transitions)

The cost of the rare mistake is one extra `git mv`. The benefit of automatic archival for the common case is large. This tradeoff is intentional.

## Scope

- IN:
  - `plan-lifecycle.sh` PostToolUse hook (handles both creation warning and status-transition archival)
  - Wire hook into `~/.claude/settings.json`
  - `find-plan-file.sh` shared lookup helper
  - Update `~/.claude/rules/planning.md` with the full lifecycle convention (creation → in-progress → archival → lookup)
  - Update `~/.claude/agents/task-verifier.md`, `plan-evidence-reviewer.md`, `ux-designer.md` with archive-aware path resolution
  - Update `~/.claude/hooks/post-tool-task-verifier-reminder.sh` to use shared helper for fallback resolution
  - Update `~/.claude/hooks/runtime-verification-reviewer.sh` to exclude archive subdirectory from modified-file analysis
  - Update `~/.claude/hooks/pre-stop-verifier.sh` to surface a warning (not block) when the session ends with an uncommitted plan file
  - Update `~/.claude/docs/harness-architecture.md` to reflect the new hook, helper, and convention
  - Mirror every change to `~/claude-projects/neural-lace/adapters/claude-code/` per `harness-maintenance.md`
  - End-to-end verification with a real plan going through the full lifecycle

- OUT:
  - Hooks that correctly limit themselves to active-work enforcement (pre-commit-gate, backlog-plan-atomicity, harness-hygiene-scan, plan-edit-validator) — these should NOT look at archive by design; archived plans are terminal and archive-aware behavior would break their semantics
  - Renaming any existing plan files
  - Nested archive structure by date/quarter — archive remains flat for now
  - Auto-commit of the status-change + rename pair — the hook stages the rename via `git mv` but the session handles commit (preserves user review)
  - Retroactive archival of plans that are already in terminal status but still in the active directory — the manual archival already completed handled those

## Tasks

### Phase A: Lifecycle Hook (the core infrastructure)

- [x] A.1 Write `~/.claude/hooks/plan-lifecycle.sh`
  - PostToolUse hook triggered on Write or Edit tool calls
  - Activates only when `file_path` is under `docs/plans/` (top-level — not archive, since archive edits are rare and don't need lifecycle logic)
  - Two responsibilities:
    - **On Write (new file creation):** Check if the file is newly-tracked vs. existing. If the previous file state was "did not exist," emit the uncommitted-plan warning.
    - **On any edit where `Status:` field changed to terminal (COMPLETED/DEFERRED/ABANDONED/SUPERSEDED):** execute `git mv docs/plans/<slug>.md docs/plans/archive/<slug>.md`. If `<slug>-evidence.md` exists, move that too. Emit the archival system message.
  - Detection of status transition: before the edit, read the pre-edit content from the tool call input (the `old_string` of an Edit, or compare against `git show HEAD:<path>`). After the edit, read the new content. Compare `Status:` lines.
  - Handle Write tool (not just Edit): if it's a full file overwrite, the Status detection must compare HEAD vs. new content.
  - Include `--self-test` flag that creates a temp dir, writes a fake plan, simulates status transition, verifies the move
  - Exit codes: 0 on success, non-zero only on unexpected errors (do not use non-zero to block the tool call — PostToolUse hooks shouldn't block retroactively)
  - **Files:** `~/.claude/hooks/plan-lifecycle.sh`
  - **Done when:** `--self-test` passes. Manual test: create a dummy plan in a test dir, edit it to `Status: COMPLETED`, verify the file is moved and `git status` shows the rename as staged.

- [x] A.2 Wire the hook into `~/.claude/settings.json`
  - Add `plan-lifecycle.sh` as a PostToolUse hook matching Write and Edit tools
  - Verify settings.json remains valid JSON after the edit
  - **Files:** `~/.claude/settings.json`
  - **Done when:** Settings edit is valid; a dry-run session fires the hook on plan file edits.

- [x] A.3 Mirror hook and settings to neural-lace
  - Copy `~/.claude/hooks/plan-lifecycle.sh` to `~/claude-projects/neural-lace/adapters/claude-code/hooks/plan-lifecycle.sh`
  - Update neural-lace's `settings.json` template to include the new hook registration
  - `diff -q` verification on both files
  - Commit: `feat(harness): plan-lifecycle hook for commit-on-creation + auto-archival`
  - **Files:** `neural-lace/adapters/claude-code/hooks/plan-lifecycle.sh`, `neural-lace/adapters/claude-code/settings.json` (or the template equivalent)
  - **Done when:** neural-lace commit exists; diff is clean.

### Phase B: Lookup Helper

- [x] B.1 Write `~/.claude/scripts/find-plan-file.sh`
  - Accepts a plan slug (with or without `.md` extension) and prints the full relative path to the plan file
  - Resolution order: `docs/plans/<slug>.md` → `docs/plans/archive/<slug>.md`
  - Exits 0 with path on stdout if found; exits 1 with no stdout if not found
  - Stderr diagnostic on archive resolution: "resolved from archive: <path>"
  - Supports glob patterns too: `find-plan-file.sh "*release*"` returns all matching paths
  - `--self-test` flag validates resolution order, not-found behavior, and glob support
  - **Files:** `~/.claude/scripts/find-plan-file.sh`
  - **Done when:** Self-test passes; manual test on a project repo with a known active plan and a known archived plan resolves both correctly.

- [x] B.2 Mirror lookup helper to neural-lace
  - Copy to `~/claude-projects/neural-lace/adapters/claude-code/scripts/find-plan-file.sh`
  - `diff -q` verification
  - Commit: `feat(harness): find-plan-file.sh archive-aware plan lookup`
  - **Files:** `neural-lace/adapters/claude-code/scripts/find-plan-file.sh`
  - **Done when:** Commit exists; diff is clean.

### Phase C: Documentation — the Unified Convention

- [x] C.1 Update `~/.claude/rules/planning.md` with the full lifecycle convention
  - Add a new section: "## Plan File Lifecycle (Creation, Archival, Lookup)"
  - Content:
    - **Creation:** "Commit new plan files immediately. Uncommitted plans are vulnerable to being wiped by concurrent sessions. The plan-lifecycle hook will surface a warning until a plan is committed."
    - **In-progress:** (existing content about task-verifier, evidence-first protocol)
    - **Status is the last edit:** Document the rule that Status changes to terminal trigger auto-archival, and therefore must be the final edit made to a plan. Completion reports, final notes, and decision entries should be written BEFORE flipping Status.
    - **Auto-archival:** "When Status transitions to COMPLETED/DEFERRED/ABANDONED/SUPERSEDED, the plan-lifecycle hook moves the file to `docs/plans/archive/` automatically. Evidence companions (`<slug>-evidence.md`) move together. The status change and file rename land in the same commit."
    - **Lookup:** "To find a plan by name, use `~/.claude/scripts/find-plan-file.sh <slug>` (Bash contexts) or `Glob docs/plans/**/<pattern>.md` (Claude tool calls). Archive is searched transparently."
    - **Recovery from premature archival:** Document the `git mv` restoration path.
  - Remove any outdated language that implies manual archival or that Status changes are free-form
  - **Files:** `~/.claude/rules/planning.md`
  - **Done when:** New section exists, is clear, covers all four stages, and existing sections are reconciled (no conflicting instructions).

- [x] C.2 Mirror `planning.md` to neural-lace
  - Copy + `diff -q` verify
  - Commit: `docs(harness): planning.md — unified plan file lifecycle convention`
  - **Files:** `neural-lace/adapters/claude-code/rules/planning.md`
  - **Done when:** Commit exists; diff is clean.

### Phase D: Agent Prompt Updates

- [x] D.1 Update `~/.claude/agents/task-verifier.md` with archive-aware path resolution
  - Add to the input-handling section: "If the plan path provided does not resolve, check `docs/plans/archive/<slug>.md` as a fallback. Plan files in archive are historical records — treat any verdict-changing edits there with extra skepticism (archived plans should not normally be under active verification)."
  - **Files:** `~/.claude/agents/task-verifier.md`
  - **Done when:** Instruction is present and integrated cleanly.

- [x] D.2 Update `~/.claude/agents/plan-evidence-reviewer.md` with archive-aware path resolution
  - Same pattern as task-verifier
  - **Files:** `~/.claude/agents/plan-evidence-reviewer.md`
  - **Done when:** Instruction is present.

- [x] D.3 Update `~/.claude/agents/ux-designer.md` with archive-aware path resolution
  - Same pattern
  - **Files:** `~/.claude/agents/ux-designer.md`
  - **Done when:** Instruction is present.

- [x] D.4 Mirror all three agent files to neural-lace
  - Copy each + `diff -q` verify
  - Single commit: `docs(harness): agents — archive-aware plan path resolution`
  - **Files:** `neural-lace/adapters/claude-code/agents/{task-verifier,plan-evidence-reviewer,ux-designer}.md`
  - **Done when:** All three match; commit exists.

### Phase E: Targeted Hook Updates

- [ ] E.1 Update `~/.claude/hooks/post-tool-task-verifier-reminder.sh` to use shared helper
  - Where the hook currently sets `PLAN_DIR="docs/plans"` and finds the most-recently-modified plan, prefer active-dir lookup but fall back to archive when no active match correlates with the edited source file
  - Source via `~/.claude/scripts/find-plan-file.sh` where applicable
  - Keep default behavior (prefer active) — archive is fallback, not primary
  - **Files:** `~/.claude/hooks/post-tool-task-verifier-reminder.sh`
  - **Done when:** Hook passes its self-test (if one exists); manual verification that active plans still take priority.

- [ ] E.2 Update `~/.claude/hooks/runtime-verification-reviewer.sh` to exclude archive from modified-file analysis
  - Change the grep exclusion pattern from `docs/plans` to `docs/plans(/archive)?` (or equivalent) so edits to archived plans aren't treated as runtime-relevant
  - Small polish affecting only the rare case of editing an archived plan
  - **Files:** `~/.claude/hooks/runtime-verification-reviewer.sh`
  - **Done when:** Pattern updated; grep behavior verified.

- [ ] E.3 Update `~/.claude/hooks/pre-stop-verifier.sh` to warn (not block) on uncommitted plan files
  - Before session-end block logic, add a non-blocking check: if `docs/plans/*.md` has uncommitted files, surface a prominent warning that plans should be committed to survive future sessions
  - Do NOT block session exit — this is a reminder, not a gate
  - **Files:** `~/.claude/hooks/pre-stop-verifier.sh`
  - **Done when:** Warning is surfaced on uncommitted plan files; session exit still succeeds.

- [ ] E.4 Mirror hook updates to neural-lace
  - Copy all three updated hooks + `diff -q` verify each
  - Single commit: `feat(harness): hooks — archive awareness + uncommitted-plan warning`
  - **Files:** `neural-lace/adapters/claude-code/hooks/{post-tool-task-verifier-reminder,runtime-verification-reviewer,pre-stop-verifier}.sh`
  - **Done when:** All three match; commit exists.

### Phase F: Architecture Doc + Verification

- [ ] F.1 Update `~/.claude/docs/harness-architecture.md` to reflect the new hook, helper, and convention
  - Add `hooks/plan-lifecycle.sh` to the hooks inventory table
  - Add `scripts/find-plan-file.sh` to the scripts inventory
  - Add a paragraph under the planning section explaining the four-stage lifecycle (creation, in-progress, archival, lookup) and the "Status is the last edit" rule
  - Update any inventory entries for the hooks modified in Phase E
  - **Files:** `~/.claude/docs/harness-architecture.md`
  - **Done when:** Inventory tables include all new/changed entries; lifecycle paragraph reads clearly.

- [ ] F.2 Mirror architecture doc to neural-lace
  - Copy + `diff -q` verify
  - Commit: `docs(harness): architecture — plan file lifecycle documented`
  - **Files:** `neural-lace/adapters/claude-code/docs/harness-architecture.md`
  - **Done when:** Commit exists; diff is clean.

- [ ] F.3 End-to-end verification: complete lifecycle test
  - In a fresh Claude session:
    1. Create a throwaway plan file at `docs/plans/lifecycle-test.md` with `Status: ACTIVE`
    2. Observe the creation warning fires
    3. Commit the plan
    4. Edit the plan to `Status: COMPLETED`
    5. Observe the auto-archival fires (file moves to `docs/plans/archive/lifecycle-test.md`)
    6. Commit the status change + move as one atomic commit
    7. Ask the session to "summarize the lifecycle-test plan" — verify session resolves it via archive-aware lookup
    8. Delete the test plan (`git rm docs/plans/archive/lifecycle-test.md`) to clean up
  - Document the test results in the plan's evidence log
  - **Done when:** All 7 steps produce the expected outcomes; evidence block records the full run.

## Files to Modify/Create

### Create (in `~/.claude/` AND mirrored to neural-lace)
- `hooks/plan-lifecycle.sh` — the unified lifecycle hook
- `scripts/find-plan-file.sh` — archive-aware resolver

### Modify (in `~/.claude/` AND mirrored to neural-lace)
- `settings.json` (or template) — register the new hook
- `rules/planning.md` — full lifecycle convention
- `agents/task-verifier.md` — archive-aware path resolution
- `agents/plan-evidence-reviewer.md` — same
- `agents/ux-designer.md` — same
- `hooks/post-tool-task-verifier-reminder.sh` — use shared helper
- `hooks/runtime-verification-reviewer.sh` — exclude archive subdirectory
- `hooks/pre-stop-verifier.sh` — warn on uncommitted plans
- `docs/harness-architecture.md` — inventory + lifecycle paragraph

### Explicitly NOT Modified
- `hooks/backlog-plan-atomicity.sh` — correctly scoped to new plan creation only
- `hooks/harness-hygiene-scan.sh` — harness-repo concern
- `hooks/plan-edit-validator.sh` — regex already matches archive paths, which is desirable
- `hooks/pre-commit-gate.sh` — correctly scoped to active-work commits

## Testing Strategy

### Unit-level
- `plan-lifecycle.sh --self-test` verifies creation warning + status-transition detection + git mv execution + evidence companion move
- `find-plan-file.sh --self-test` verifies resolution order, not-found behavior, glob support
- Each modified hook preserves its existing self-tests if any

### Integration-level
- Manual verification on a downstream-project repo (real plans, real archive):
  - `find-plan-file.sh <known-active-plan-slug>.md` → active path
  - `find-plan-file.sh <known-archived-plan-slug>.md` → archive path with stderr note
  - `find-plan-file.sh nonexistent-plan` → exit 1
- Dry-run the lifecycle hook against a sample plan edit to verify git mv fires correctly

### End-to-end
- Task F.3's complete lifecycle test in a fresh session

### What we're NOT testing
- Retroactive fix of historical git commit messages (impossible; those paths are frozen)
- Cross-project usage (harness-level change applies everywhere automatically)
- Behavior under concurrent sessions (out of scope; worktree isolation is the answer there)

## Decisions Log

### Decision: One hook handles both creation and status transitions, not two separate hooks
- **Tier:** 1
- **Status:** proceeded with recommendation (user-confirmed)
- **Chosen:** Single `plan-lifecycle.sh` PostToolUse hook handles both the creation warning (on Write of a new plan file) and the auto-archival (on Status transition to terminal).
- **Alternatives:** Two separate hooks (`plan-creation-reminder.sh` and `plan-archival.sh`) — rejected; user explicitly said "no point in making a separate hook" and the two concerns share the same trigger (edits to plan files) so bundling them is simpler.
- **Reasoning:** User framing: "Moving a plan to archive should have exactly the same effect as marking the plan complete. This should be a single activity." Applying the same logic to the broader mechanism — one hook, one file, one mental model.
- **To reverse:** Split into two hooks if the unified hook grows too complex to reason about. Low-cost refactor.

### Decision: Status transition IS the archival trigger (no separate command)
- **Tier:** 2
- **Status:** proceeded with recommendation (user-confirmed)
- **Chosen:** The edit to `Status: COMPLETED` (or other terminal) automatically triggers `git mv` in the same edit cycle. No separate `/archive-plan` command or manual step.
- **Alternatives:** (a) Reminder-only mode (hook surfaces a reminder, user runs `git mv` manually) — rejected; relies on discipline that has already failed. (b) Explicit command (`/archive-plan <slug>`) — rejected; adds a step to an action that should be atomic.
- **Reasoning:** User: "Moving a plan to archive should have exactly the same effect as marking the plan complete. This should be a single activity." The cost of the rare accidental terminal-status typo is one `git mv` to recover; the benefit of automatic archival for the common case is eliminating an entire class of "forgot to archive" failures.
- **To reverse:** Change the hook to emit a reminder instead of executing `git mv`. Low-cost; preserves all other lifecycle infrastructure.

### Decision: Status is the last edit in a plan's active life
- **Tier:** 2
- **Status:** proceeded with recommendation
- **Chosen:** Document in `planning.md` that Status transition to terminal must be the final edit to a plan file. Completion reports, final decisions log entries, and closing notes are written BEFORE the Status flip.
- **Alternatives:** (a) Delay the archival move until session end — rejected; breaks the "Status change = archival" atomicity. (b) Allow post-archival edits by auto-resolving the new path — rejected; makes the hook more complex and surprises the session.
- **Reasoning:** Flowing this convention means the session's natural workflow (finish work → write summary → mark complete) aligns with the hook's behavior. No special handling needed for completion reports.
- **To reverse:** Document the opposite convention + have the hook delay moves until pre-stop. More complex, accepts looser coupling.

### Decision: Commit-on-creation is a warning, not a block
- **Tier:** 1
- **Status:** proceeded with recommendation
- **Chosen:** New plan file detection surfaces a warning. Session exit is NOT blocked if the plan is uncommitted (pre-stop-verifier warns but doesn't block). The session is expected to commit promptly but isn't forced to.
- **Alternatives:** (a) Block the next tool call until plan is committed — too aggressive; a session might legitimately want to edit a plan further before committing. (b) Auto-commit on creation — too magical; users should review what's being committed.
- **Reasoning:** The risk we're mitigating is concurrent-session wipeout, which is rare. A warning plus user discipline is sufficient for most cases. Blocking would impede legitimate workflows (e.g., creating a plan and immediately editing it multiple times before committing).
- **To reverse:** Change the warning to a block. Easy; just change the hook exit code.

## Evidence Log

Per-task evidence blocks live in the companion file `robust-plan-file-lifecycle-evidence.md`. The session-end pre-stop-verifier validates each block by re-executing its Runtime verification command. Evidence must be written there BEFORE the corresponding checkbox is flipped (enforced by `~/.claude/hooks/plan-edit-validator.sh`).

## Definition of Done

- [ ] All 18 tasks checked off
- [ ] `plan-lifecycle.sh` passes self-test and fires correctly on real plan edits
- [ ] `find-plan-file.sh` passes self-test and resolves both active and archived plans
- [ ] `planning.md` has the unified lifecycle section in both `~/.claude/` and neural-lace
- [ ] All three agent files have archive-aware resolution instructions
- [ ] All hook changes (lifecycle hook + 3 existing hooks) synced to neural-lace
- [ ] `harness-architecture.md` inventory includes new hook + helper
- [ ] End-to-end verification (task F.3) passes
- [ ] neural-lace has commits for each phase's changes
- [ ] SCRATCHPAD.md updated with final state
- [ ] Completion report appended to this plan file
- [ ] **Self-consistency check:** flipping THIS plan's Status to COMPLETED should trigger the auto-archival hook and move it to `docs/plans/archive/robust-plan-file-lifecycle.md` — the plan eats its own dogfood at completion time
