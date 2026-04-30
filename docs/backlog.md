# Neural Lace — Harness Backlog

Last updated: 2026-04-29 (two new mechanism-extension items added below for the Pre-Submission Class-Sweep Audit work. Earlier 2026-04-27: two pre-existing harness-drift items absorbed into `docs/plans/agent-teams-integration.md` per backlog-plan-atomicity rule; the remaining two harness-drift items stay open below. Earlier 2026-04-27: four harness-drift items added — pre-existing drift surfaced during agent-teams conflict analysis. See `docs/reviews/2026-04-27-agent-teams-conflict-analysis.md` for full context. Earlier 2026-04-24: HARNESS-GAP-01..07; concurrent ACTIVE plans need acceptance-exempt declaration; capture-codify P2 entries.)

Outstanding improvements to the Claude Code harness (rules, agents, hooks, skills). Project-level backlogs live in individual project repos; this file tracks harness-level work.

Strategy context and reasoning for many entries below lives in [`docs/claude-code-quality-strategy.md`](./claude-code-quality-strategy.md).

## HARNESS-GAP-08 — `spawn_task` should support optional report-back (added 2026-04-30)

**Observation.** `mcp__ccd_session__spawn_task` is documented as fire-and-forget — the orchestrator session spawns a task, the spawned session runs independently with its own full harness, and there is no callback channel. The orchestrator only learns the result by either (a) reading git artifacts the spawned session committed, or (b) the user manually telling the orchestrator the spawned task is done.

**Why this is a gap.** For genuinely independent work (CI migration, code audits, one-shot doc generation), fire-and-forget is correct — that's the whole point of context hygiene. But for **sequenced fix work** where the orchestrator drives a punchlist (e.g., "fix P0-1 → assess result → fix P0-2 → ..."), the orchestrator must coordinate. Currently the user mediates: they tell the orchestrator "the spawned task completed," and the orchestrator manually fetches the resulting branch via git. This:
- Adds friction every time the orchestrator wants to chain fixes through spawn_task
- Pushes orchestrators toward Agent-tool-only patterns (which keep all build context in the orchestrator's window) when spawn_task would otherwise be a better fit
- Has no mechanical signal at all if the user forgets to tell the orchestrator (or tells the wrong session)

**Proposed mechanism.** `spawn_task` accepts an optional `report_back: true` param. When set:
1. The spawned session, on stop, writes a structured JSON file at `.claude/state/spawned-task-results/<task-id>.json` with: `{task_id, started_at, ended_at, branch, pr_url, exit_status, summary, commits: [<sha>], artifacts: [<path>]}`.
2. The orchestrator's `SessionStart`-equivalent hook (or a per-turn check) scans `.claude/state/spawned-task-results/` for new entries since its last turn and surfaces them in the system reminder.
3. The orchestrator can then act on the result on its very next turn — cherry-pick, run task-verifier, plan the next fix — without user mediation.

**Cleanup semantics.** Result files older than 7 days get pruned by the same hook. Or move them to `archive/` after the orchestrator acknowledges them (mirroring `plan-lifecycle.sh`'s archive pattern).

**Fallback.** Spawn_task without `report_back: true` keeps current fire-and-forget behavior. Backward compatible.

**Originating context.** Surfaced 2026-04-30 during a downstream-project session arc that chained multiple `spawn_task` invocations as a fix punchlist. The user asked: "Shouldn't each of these spawned tasks send their data back to you when they're done so you can review and know when to kick off the following tasks?" The orchestrator (correctly) had to acknowledge that no callback exists today and manual user mediation was the workaround. This pattern recurred multiple times across the session arc.

**Effort estimate.** S-M (~4-6 hr). One JSON-write helper, one hook to scan and surface. Tests for: result file written on terminal exit, multiple spawned tasks don't collide, hook surfaces only unread results, archive on acknowledgment.

**Class.** `harness-coordination-channel-missing` — orchestrator-to-spawned-task lacks a return path; user becomes the channel.

---

## Mechanism extensions for the Pre-Submission Class-Sweep Audit (added 2026-04-29)

Companion to the Pattern-level rules landed 2026-04-29 in `adapters/claude-code/rules/design-mode-planning.md`, `rules/planning.md`, `templates/plan-template.md`, and `docs/failure-modes.md`. Those rules document the discipline; the items below mechanize the parts that should be hook-enforced rather than self-applied. Source data: an originating 2026-04-28 design-mode review effort (an OAuth+IMAP auth-refactor plan, eight-round `systems-designer` review) surfaced 11 distinct failure classes (FM-007 through FM-017 in `docs/failure-modes.md`); 6+ of them shared a single root cause (`stranded-behavior-change-against-implementation-entry-points`) that the planner could have caught upfront with a class-sweep instead of having the reviewer find sibling instances over multiple rounds.

### HARNESS-AUDIT-EXT-01 — Extend `plan-reviewer.sh` with five Pre-Submission Audit mechanical checks (P1)

The Pre-Submission Class-Sweep Audit rule (`design-mode-planning.md`) currently relies on the planner self-applying five sweep queries (S1 Entry-Point Surfacing, S2 Existing-Code-Claim Verification, S3 Cross-Section Consistency, S4 Numeric-Parameter Sweep, S5 Scope-vs-Analysis Check). Pattern enforcement only — no mechanical backstop today.

**Extension scope:**
- (A) `## Pre-Submission Audit` section presence check on `Mode: design` plans (FAIL if missing or contains only `[populate me]` placeholder text). Mirrors existing required-section checks.
- (B) "Either/or" / "TODO" / "decide later" / "OR:" pattern detection in Decisions Log entries — FAIL unless preceded by a `Surfaced to user:` annotation per `rules/planning.md` "Plan-Time Decisions With Interface Impact — Surface To User" (FM-010 prevention).
- (C) "Stays identical" / "preserved" / "unchanged" claims in Tasks section — WARN unless followed by an enumerated whitelist of what's preserved AND what changes per other sections (FM-012 prevention).
- (D) Comparative phrases ("under X RPM", "well below Y", "comfortably under Z") in Section 9 (Load/capacity) — WARN unless inline numerics are present in the same paragraph (FM-013 + FM-014 prevention).
- (E) "Add X" / "Modify Y" / "Replace Z" verbs in Sections 1-10 — cross-check against Scope OUT bullets, FAIL if a target is in Scope OUT but a verb prescribes changing it (FM-016 prevention).

**Acceptance criteria:**
- All five checks have unit-test fixtures (sample plan files exercising each pass/fail case)
- Existing `plan-reviewer.sh --self-test` is extended with new test cases
- Hook invocation latency stays under 1s for typical-size plans (~300 lines)
- WARN-level checks do not block plan creation; FAIL-level checks do

**Effort:** ~4-6 hours including fixtures + self-test extensions. Bash + grep/ripgrep; no new tools needed.

**Why P1:** without this, the Pre-Submission Audit discipline is purely Pattern-enforced — relies on planner remembering to run the sweeps. The 2026-04-28 review effort happened precisely because the planner skipped the sweep. Mechanical enforcement closes the same gap that produced 8 review rounds.

**Related:** `adapters/claude-code/hooks/plan-reviewer.sh` (existing hook to extend), `adapters/claude-code/rules/design-mode-planning.md` ("Pre-Submission Class-Sweep Audit" section), `docs/failure-modes.md` (FM-007 through FM-017 — the prevention column for each cites this hook extension as the mechanical backstop).

### HARNESS-AUDIT-EXT-02 — Extend `systems-designer` agent to FAIL when `## Pre-Submission Audit` section is missing or sweeps not documented (P1)

The `systems-designer` agent currently reviews plan substance but doesn't gate on the planner having performed the Pre-Submission Audit. With HARNESS-AUDIT-EXT-01 alone, the audit section presence is checked at plan-creation time but a planner could land an empty audit section, then submit to systems-designer, and the agent would still spend rounds finding sibling-class instances the planner should have swept upfront.

**Extension scope:** add an explicit precondition check in `agents/systems-designer.md`:

> Before reviewing the 10 SEA sections, verify the plan's `## Pre-Submission Audit` section contains substantive content for each of the 5 sweeps (S1-S5) — not just placeholder text. If any sweep line is empty, says "TODO", says "skipped", or matches `\[populate me\]`, return FAIL immediately with a clear message: "Pre-Submission Audit not performed — run the 5 class-sweeps before re-submitting. See `~/.claude/rules/design-mode-planning.md` for the sweep queries."

**Acceptance criteria:**
- The agent's prompt-time precondition check covers S1-S5 individually
- The agent's failure message names the specific sweep(s) that weren't documented
- A planner can satisfy the precondition with "n/a — single-task plan, no class-sweep needed" per the rule's carve-out for trivial plans
- Mode: code plans skip this check entirely

**Effort:** ~1 hour — single agent file edit + manual test against the rules document.

**Why P1:** dependent on HARNESS-AUDIT-EXT-01 for the audit-section template existence at plan-creation time. With both items landed, the discipline becomes mechanical end-to-end (planner can't skip the sweeps without being blocked twice — once at plan creation, once at systems-designer submission).

**Related:** `adapters/claude-code/agents/systems-designer.md`, the new "Pre-Submission Audit" section in `templates/plan-template.md` and `rules/design-mode-planning.md`.

## Pre-existing harness drift surfaced 2026-04-27 (during agent-teams conflict analysis)

Items found while doing the Phase 1 ground-truth inventory for Agent Teams integration. These are independent of Agent Teams — they are real drift between documented enforcement and actual settings.json wiring or filesystem state. Full evidence in `docs/reviews/2026-04-27-agent-teams-conflict-analysis.md`. Two items (P2-class) were absorbed into `docs/plans/agent-teams-integration.md` on plan creation; the two remaining items below are out of scope for that plan.

### HARNESS-DRIFT-01 — Six Gen-6 hooks not wired in settings.json (P1)

The following hooks exist on disk at `adapters/claude-code/hooks/` but are not referenced from any `settings.json` callsite (in either the adapter copy or the live `~/.claude/settings.json`):

- `goal-extraction-on-prompt.sh` (UserPromptSubmit, A1 mechanism — captures imperative verbs from user's first prompt)
- `goal-coverage-on-stop.sh` (Stop, A1 mechanism — verifies goal coverage at session end)
- `imperative-evidence-linker.sh` (A7 mechanism)
- `transcript-lie-detector.sh` (A3 mechanism — self-contradiction class)
- `vaporware-volume-gate.sh` (A8 mechanism — blocks PRs with high docs/config volume but zero execution evidence)
- `automation-mode-gate.sh` (PreToolUse — was supposed to enforce automation-mode policy)

Recent commits (`0be6526`, `fe64587`, `1e6310c`, `fca7e52`, `d639aae`) reference these as "shipped" but they're inert until wired. Likely cause: the hooks were authored and committed but the corresponding edits to `adapters/claude-code/settings.json` were never made or were reverted.

**Fix path:** audit each hook against its design doc (likely `docs/plans/adversarial-validation-mechanisms.md`), confirm the intended event + matcher, and wire them into the adapter `settings.json`. Sync via `install.sh` to `~/.claude/settings.json`. Verify each by triggering the relevant condition in a fresh test session.

### HARNESS-DRIFT-02 — SessionStart account-switching hook is hardcoded against a literal directory substring (P1)

The deployed SessionStart hook at `adapters/claude-code/settings.json:273-279` reads (paraphrased — actual identifiers redacted from this backlog per harness hygiene; see live `~/.claude/settings.json` for verbatim form):

```bash
if echo "$PWD" | grep -q '<work-org-substring>'; then
  gh auth switch --user <work-username> 2>/dev/null
  ...
else
  gh auth switch --user <personal-username> 2>/dev/null
  ...
fi
```

This is drift from the documented contract. Per `docs/harness-architecture.md:81` and `examples/accounts.config.example.json`, the hook is supposed to read account `dir_triggers` from `~/.claude/local/accounts.config.json`. The hardcoded substring is brittle:

- A working directory not containing the literal hardcoded substring falls into `else` (personal account) — including any worktree, clone, or fork under a different parent path.
- The push-time variant at `settings.json:178` mirrors the same hardcoded substring against the remote URL.
- Adding new accounts to the user's setup is silently ignored (not in the conditional).

**Fix path:** replace the inline hook body with a call to `~/.claude/scripts/read-local-config.sh accounts` (script already exists in the harness) and pattern-match the result against `$PWD`. The schema and example already exist; only the hook body needs rewriting.

## Known gaps in current enforcement (from strategy doc, 2026-04-22)

These are residual risks in the Gen 4+ harness. Each is documented honestly rather than left hidden.

### P1 — Verbal vaporware in conversation is not mechanically blocked

Claude Code has no PostMessage hook. `claim-reviewer` is self-invoked and can be skipped. When the agent makes a feature claim in conversation without citing file:line, no mechanism catches it. Current mitigation: user reflex to ask for citations. Closing requires either a PostMessage hook in Claude Code itself or an adversarial post-response review agent that fires on every Nth response.

### P1 — Tool-call-budget `--ack` attestation is bypassable

The `tool-call-budget.sh` hook looks for sentinel lines in `~/.claude/state/reviews/`. A builder agent could Write that file directly without actually invoking `plan-evidence-reviewer`. Friction is raised but not cryptographically closed. Closing requires either per-session HMAC signing or architectural support for observing Task tool invocations.

### P1 — Concurrent-session state collisions (plan-wipe incidents)

Multiple Claude Code sessions on the same machine share `~/.claude/` state and the git working tree. Uncommitted plan files have been lost to concurrent-session `git stash`/`clean` operations on multiple documented occasions (2026-04-19, 2026-04-20). A project-level plan addressing commit-on-creation is in flight, but cross-session state coordination (shared `~/.claude/` directory) is still unresolved.

### P2 — `plan-lifecycle.sh` archival staging misses content change

Surfaced 2026-04-23 (during plan #5's own self-archival, commit 93ef15d). When the Status field is edited, the hook stages a `git mv` to archive but does NOT stage the actual Status text change. Resulting commit captures the rename only; the content change sits unstaged in the working tree at the new path, requiring a manual follow-up `git add <new-path> && git commit`.

**Fix candidates:**
- (a) Hook also runs `git add <new-path>` after the `git mv` so the content change is staged together with the rename. Risk: if the new path doesn't exist yet (race condition with the rename being staged but not committed), `git add` may fail.
- (b) Hook emits a clear warning message reminding the user to `git add <new-path>` before committing. Pattern enforcement, not mechanism.
- (c) Hook moves the file via `mv` (filesystem rename) BEFORE the Edit tool's content change reaches disk, then user does `git add -A` which captures both as a single staged change. Requires hook re-architecture.

Workaround pattern (used 2026-04-23): commit twice — first commit captures the rename (zero-content change), second commit captures the Status text update. See plan #5's archival commits 93ef15d + 6f4c057.

### P1 — Concurrent ACTIVE plans need acceptance-exempt declaration before next session-end (2026-04-24)

After Phase D of `docs/plans/end-user-advocate-acceptance-loop.md` registered `product-acceptance-gate.sh` as Stop-hook position 4, two concurrent ACTIVE plans will block session end on the next session unless reconciled:

- `docs/plans/claude-remote-adoption.md`
- `docs/plans/class-aware-review-feedback-smoke-test-plan.md`

Both are harness-dev plans without a product-user surface. Per `rules/acceptance-scenarios.md`'s exemption guidance, each should declare `acceptance-exempt: true` with a substantive `acceptance-exempt-reason:` (>= 20 chars). The third concurrent plan, `end-user-advocate-acceptance-loop.md` itself, has already been declared exempt in Phase D (bootstrap meta-plan rationale).

**Fix path:** in the next session, edit each plan file's header to add the two fields. Example for `claude-remote-adoption.md`:
```
acceptance-exempt: true
acceptance-exempt-reason: Harness-development plan (Claude Code remote-mode adoption); no product-user surface to verify at runtime — the maintainer exercises the harness in subsequent sessions.
```

Until done, sessions ending while these plans are ACTIVE will hit a BLOCK with a clear remediation message from `product-acceptance-gate.sh`. Per-session waiver is also available as a fallback (`echo "..." > .claude/state/acceptance-waiver-<slug>-$(date +%s).txt`).

### P1 — `plan-phase-builder` sub-agent dispatched without Task tool — cannot invoke `task-verifier` (2026-04-23)

**Flagged for harness-reviewer 2026-04-27:** the agent-teams integration session re-encountered this gap (commits f993a83, ed42e8b, ff28441, 6cca4b8 — Phase 5 Tasks 1-4 of `docs/plans/agent-teams-integration.md`). The evidence-first fallback worked end-to-end across four builders, providing additional empirical confirmation that path (b) below is viable. Next `/harness-review` skill run should evaluate which fix to commit to.

When the orchestrator dispatches a `plan-phase-builder` sub-agent (the dispatch type used while building Phase A of `docs/plans/archive/robust-plan-file-lifecycle.md`), the sub-agent's tool surface does NOT include the Task tool — it is not in the top-level tool list and is also not surfaced via ToolSearch (`select:Task` returns no results). Consequence: the sub-agent cannot invoke `task-verifier` as instructed by both the orchestrator-pattern rule and the dispatch prompt. The builder must fall back to writing evidence blocks directly under the evidence-first protocol enforced by `plan-edit-validator.sh` + `runtime-verification-executor.sh` — which works (the harness was specifically designed to allow this path), but it conflicts with the rule's "only `task-verifier` flips checkboxes" framing. Two possible fixes: (a) ensure dispatched `plan-phase-builder` sub-agents inherit the Task tool so they can invoke `task-verifier`; (b) update `~/.claude/rules/orchestrator-pattern.md` and the dispatch-prompt boilerplate to explicitly authorize the evidence-first fallback when Task is unavailable, with a written rationale. Either way, the current mismatch between the rule and the runtime tool surface should be reconciled. Reference instances: original Phase A build (commits d2d1494 + 4cc9c2a on `feat/robust-plan-file-lifecycle`); agent-teams integration Phase 5 Tasks 1-4 (commits f993a83, ed42e8b, ff28441, 6cca4b8 on master, 2026-04-27).

## Improvements surfaced by a downstream plan-staleness sweep (2026-04-24)

Seven structural gaps that allowed ~22 ACTIVE plans to accumulate across two sibling project repos without any enforcement firing. Each entry is named HARNESS-GAP-NN for cross-reference. Surfaced during a Q&A session that hit the `product-acceptance-gate.sh` Stop hook in storm — the gate fired, the user asked "why are so many plans considered done without everything checked off?", and these are the answers.

### HARNESS-GAP-01 — `pre-stop-verifier.sh` doesn't block terminal-Status flips with unverified tasks

`pre-stop-verifier.sh` blocks "checked tasks without evidence blocks" AND "unchecked tasks AND `Status: ACTIVE`." It does NOT block "terminal Status (`COMPLETED` / `DEFERRED` / `ABANDONED` / `SUPERSEDED`) AND unchecked tasks AND no evidence block names them shipped." Consequence: the cleanup move (flip Status to clear the gate) silently legitimizes whatever checkbox state is in the file — the precise pattern that produced a downstream plan-staleness sweep. Proposed fix: add Check 4d to `pre-stop-verifier.sh` that requires every unchecked task in a terminal-Status plan to either (a) have an evidence block claiming it shipped, or (b) appear in an explicit "Tasks deferred to Phase 2 / out of scope" section in the closing note.

### HARNESS-GAP-02 — No git-log → plan-checkbox correlation

A commit that touches files in a task's `Files to Modify/Create` list could plausibly satisfy that task, but no hook reads the diff, finds the matching task, and surfaces "this commit may satisfy Task X.Y in plan Z — invoke task-verifier?" Sync is one-way: builder must remember. If the builder errors, exits, or work goes through any non-orchestrator path (manual fix, hotfix, kanban-engine direct commit), the link is never formed. Proposed fix: PostToolUse hook on Git commits that scans the commit's diff against `docs/plans/*.md` ACTIVE plans' file lists and emits a non-blocking surface message naming the candidate tasks. User or next session can act on it.

### HARNESS-GAP-03 — Auto-generated kanban plans bypass task-checkbox enforcement

Plans created by `kanban-engine.yml` from GitHub Issues have task lists that read "(The build agent will investigate, diagnose, and implement autonomously.)" — i.e., 0 checkboxes by design. The verification model assumes plans have task lists. Kanban plans don't, so `pre-stop-verifier`'s "unchecked tasks" check is vacuously satisfied — but there's also no positive signal that the work shipped. The kanban plan can sit at `Status: ACTIVE` indefinitely while the underlying GitHub Issue is closed. Proposed fix (two parts): (a) `Status: ISSUE-TRACKED` sentinel that exempts kanban plans from task-checkbox enforcement and treats issue-close as the verification, (b) periodic Routine that scans kanban plans whose source issue is CLOSED and auto-flips Status: COMPLETED.

### HARNESS-GAP-04 — Reactive audit, not preventive

a downstream plan-staleness sweep exists in the backlog because the `product-acceptance-gate.sh` Stop hook started failing loudly enough that someone noticed 22 stale plans. There's no scheduled "weekly plan-audit" Routine that surfaces stale plans before they accumulate. By the time you see drift, you have 22 plans to triage, the sweep takes hours instead of minutes, and the user's confidence in the gate erodes. Proposed fix: weekly `/schedule` Routine that lists every plan with `Status: ACTIVE` for >14 days where the most recent commit touching `docs/plans/<slug>` is >7 days old. Output goes to `docs/reviews/YYYY-MM-DD-plan-staleness-audit.md` so it's actionable at human scale.

### HARNESS-GAP-05 — Status-audit sub-agents conflate "code shipped" with "feature works"

When a research / status-audit sub-agent reports on a plan (e.g., "the roadmap is functionally complete"), the agent typically correlates checkbox state with git log — both static signals. It does NOT exercise the feature at runtime. The `end-user-advocate` exists for runtime verification but is not invoked by status-audit agents by default. Result: a plan can be reported "done" based on artifacts that exist on disk, without anyone ever confirming a real user can use the feature. Proposed fix: either (a) extend `task-verifier`'s verdict shape to distinguish `evidence: artifact-only` from `evidence: runtime-PASS` and require runtime evidence for any task whose `Done when:` criterion involves user-observable behavior, OR (b) add a rule that any agent reporting "this plan is done" must call out which checks were performed and which were skipped, in a structured `## Verification Coverage` block.

### HARNESS-GAP-06 — No first-class `Status: PENDING-REVIEW` for "code shipped, human QA pending"

The current terminal Status taxonomy (`COMPLETED`, `DEFERRED`, `ABANDONED`, `SUPERSEDED`) lacks an honest label for the very common state "the engineering work shipped but the user hasn't yet exercised it to confirm the build matches their expectation." Sessions are forced to choose: leave Status: ACTIVE (gates fire forever) or flip COMPLETED (loses the "I haven't actually tried this yet" signal). Workaround in the surfacing project: pair `Status: COMPLETED` with `MANUAL-QA-<plan-slug>` backlog items.

Proposed fix: real `Status: PENDING-REVIEW` sentinel honored by the harness — plan auto-archives like other terminal statuses, but session-end gate emits a non-blocking reminder listing pending-review plans the user should triage. The sub-status `PENDING-REVIEW` ages out into `COMPLETED` after explicit user sign-off (or `DEFERRED` if QA found regressions).

**User-supplied requirements (refined 2026-04-24):**

1. **MUST NOT block continued progress.** A plan in `PENDING-REVIEW` does NOT trigger acceptance gates, does NOT gate session end, does NOT gate dispatch of new builders, does NOT block other plans from being created or worked. The only signal is informational. Specifically: `product-acceptance-gate.sh` must treat `PENDING-REVIEW` as equivalent to `acceptance-exempt` for blocking purposes; `pre-stop-verifier.sh` must treat `PENDING-REVIEW` as a terminal status for completion-check purposes.

2. **Persistent roadmap-level + plan-level overview.** A dashboard (or session-start surface) that shows what's pending review at both levels:
   - **Plan level:** within a plan file, individual tasks could carry per-task review state (`- [x] Task 1 (PENDING-REVIEW)` vs `- [x] Task 1 (REVIEWED 2026-04-25 by user)`). Lets the user know which specific tasks within a plan they've actually verified.
   - **Roadmap level:** a Routine or skill that scans all plans (active + archived) and produces a dashboard at `docs/reviews/<date>-pending-review-dashboard.md` (or surfaces in SCRATCHPAD on session start). Lists every plan currently in `PENDING-REVIEW` with a one-line summary of what's awaiting verification and how long it's been waiting. Roadmap docs (like `an active project roadmap doc`) should be able to query this state inline.

3. **Sign-off discipline.** The transition `PENDING-REVIEW` → `COMPLETED` requires an explicit user-attributed reviewed-by/reviewed-on annotation in the plan or a companion review file. Prevents the agent from silently flipping it on the user's behalf.

4. **Roadmap-aware archival.** Plans that are owned by an active roadmap (e.g., `an active project roadmap doc`) should not auto-archive on `PENDING-REVIEW` — they stay reachable from the roadmap until the user signs them off and the roadmap itself updates the link. Otherwise the user loses the "where are we on the roadmap" overview that the roadmap doc is supposed to provide.

These requirements push HARNESS-GAP-06 from a small Status sentinel to a small subsystem (status semantics + dashboard generator + review annotations + roadmap-awareness). Scope it as a multi-phase plan when picking up. P1.

### HARNESS-GAP-07 — `plan-lifecycle.sh` doesn't recognize YAML frontmatter Status

Surfaced 2026-04-24 during a downstream plan-staleness sweep Phase 1 closures. The hook's awk pattern `/^Status:[[:space:]]*[A-Za-z][A-Za-z0-9_-]*/` matches only the standard `Status: ACTIVE` line at the top of a plan. It does NOT match YAML frontmatter format where the field is `status: ACTIVE` (lowercase) inside a `---` block. Reference instance: a kanban-engine-generated plan in a downstream project had to be manually `git mv`'d to archive because flipping its YAML frontmatter `status:` to `COMPLETED` did not trigger the hook. Two fix options: (a) extend the hook's awk pattern to also recognize YAML frontmatter `status:` lines (case-insensitive), OR (b) add a pre-commit hook (`plan-format-normalizer.sh`) that detects YAML frontmatter plans and either rewrites them to standard format or refuses the commit with a message pointing at the standard. Option (a) is non-invasive but legitimizes two formats; option (b) forces consistency. Light P2 — rare format outside the kanban-engine pipeline, but the inconsistency surprises operators when archives don't auto-fire.

## Improvements surfaced by 2026-04-22 strategy review

Prioritized order of leverage. Full reasoning in `docs/claude-code-quality-strategy.md` section "Additional Suggestions for Improvement."

### P0 — Harness-tests-itself: synthetic session runner

Build a tool that runs synthetic Claude Code sessions against known-bad scenarios and measures whether hooks catch them (unauthorized checkbox flip, mocked integration test, uncited feature claim, budget exhaustion without audit). Runs on demand or weekly via `/schedule`. Produces a report showing which enforcement mechanisms have regressed. This catches silent enforcement regressions — currently invisible.

### P2 — Claude Code doesn't dynamically load new agents OR hooks added mid-session

Surfaced 2026-04-23. Two confirmed instances of the same root cause:

- **Agents:** the `plan-phase-builder` agent file exists at both `~/.claude/agents/plan-phase-builder.md` and `adapters/claude-code/agents/plan-phase-builder.md`, but a session that started before the file was added returns "Agent type 'plan-phase-builder' not found" when invoked via the Task tool. Workaround: use `general-purpose` agent with orchestrator-pattern discipline inlined in the prompt.
- **Hooks:** the `plan-deletion-protection.sh` hook was registered via `jq` into `~/.claude/settings.json`'s PreToolUse Bash matcher mid-session. A subsequent `rm docs/plans/dpc-test.md` (which the hook should BLOCK per its self-test scenario 1) was NOT blocked — the file was deleted with exit code 0. The hook's `--self-test` passes 14/14 in a fresh subprocess invocation, proving the hook logic is correct. The session simply isn't aware of the new hook registration. Workaround: end and re-start the session (or rely on next-session activation, which is acceptable for non-urgent enforcement additions).

Mitigation candidates:
- (a) Document the limitation in `harness-maintenance.md` so future Claude sessions know to restart after adding new agents.
- (b) SessionStart hook that re-scans `~/.claude/agents/` and writes a "missing agents" warning if any expected agent isn't loaded — surface staleness without forcing a restart.
- (c) Investigate whether Claude Code has an agent-reload command; if so, document it.

Low priority because the workaround (general-purpose dispatch with inlined discipline) is functional and the issue resolves on next session start.

### P1 — Class-aware reviewer feedback Mod 2: pre-commit class-sweep attestation hook

Deferred from the original bundled "Class-aware reviewer feedback (narrow-fix bias mitigation)" entry on 2026-04-23. Mods 1 + 3 of that entry are absorbed by the `class-aware-review-feedback` plan. Mod 2 stays in the backlog pending evidence that Mods 1+3 alone don't fully close the narrow-fix-bias pattern.

**Pattern this would address:** adversarial reviewers identify named instances; LLM builders fix the named instances; sibling instances of the same defect class slip; next pass surfaces a sibling; loop. Surfaced across 5 `systems-designer` iterations on the `capture-codify-pr-template` plan (2026-04-23). Affects every adversarial-review loop in the harness.

**Proposal:** New PreToolUse hook `class-sweep-attestation.sh` (matching `git commit`) that detects fix-commits — message contains "amend" / "fix" / "address review" AND a prior reviewer FAIL exists in `~/.claude/state/reviews/`. Requires the commit message to include a `Class-sweep: <pattern> — N matches, M fixed` line. Blocks commit otherwise. Estimated effort: ~6 hrs (with self-test); existing `bug-persistence-gate.sh` is a good template.

**Trigger to revive:** if after `class-aware-review-feedback` ships, an adversarial-review loop still produces 3+ rounds of FAIL where each round surfaces a sibling instance of a defect class the prior round was supposed to address, that's the signal to ship Mod 2. Until then, the prose-layer interventions (Mod 1 + Mod 3) are believed sufficient.

### P1 — Verify class-aware reviewer feedback in next session (live agent invocation) (2026-04-23)

The `class-aware-review-feedback` plan completed Task A.10 with the smoke-test fixture at `docs/plans/class-aware-review-feedback-smoke-test-plan.md` and a sweep-query verification (9 matches against the seeded class), but could NOT live-invoke the modified `systems-designer` agent because (a) sub-agents dispatched as `plan-phase-builder` lack the Task tool (P1 above), and (b) agent definitions are loaded at session start, so in-session prompt edits don't activate until the next session (P2 below). Next-session work: invoke the modified `systems-designer` agent on the smoke-test fixture (or a fresh equivalent) and verify the agent output contains the six-field block structure (`Line(s):`, `Defect:`, `Class:`, `Sweep query:`, `Required fix:`, `Required generalization:`) for at least the seeded `generic-placeholder-section` defect class. Compare the agent's emitted sweep query against the expected sweep query in the evidence file's section C. If the agent does NOT reliably emit the six-field structure, that's the signal to either tighten the prompt language or escalate to Mod 2 (the pre-commit `class-sweep-attestation.sh` hook above). After verification, the throwaway smoke-test fixture file can be deleted.

### P1 — Prompt template library for meta-questions

Codify canonical meta-questions as slash commands or skills: `/why-did-this-bug-slip`, `/find-my-bugs`, `/make-this-plan-verbose`, `/harness-this-lesson`. Currently these patterns live in individual memory; codifying makes them reusable and consistent.

### P1 — Delegability classification on plan tasks

Every plan task declares: fully-delegable / review-at-phase / interactive. Shapes dispatch automatically — fully-delegable auto-dispatches to background sessions, review-at-phase produces PRs at phase boundaries, interactive stays in foreground. Replaces per-task manual routing decisions.

### P1 — Explicit interactive vs autonomous session mode

Session-start directive declaring interactive (human watching; more permissive) or autonomous (human not watching; stricter gates, auto-commit plans, harder enforcement). Same cadence shouldn't apply to both modes.

### P2 — Effort-level enforcement at project level

`.claude/minimum-effort.json` in project root declares minimum effort level. SessionStart hook warns if effort is below project minimum. Eliminates "forgot to set max" errors on quality-critical projects.

### P2 — Multi-model routing strategy

Codify model assignment per task type: Opus for planning/adversarial review/judgment; Sonnet for implementation; Haiku for mechanical operations. Partially done via individual agent frontmatter; could be more systematic via a central routing config.

### P2 — Scheduled retrospectives via `/schedule`

Weekly scheduled agent that reads the week's completed plans, decisions, and failure-mode entries; proposes harness improvements based on patterns; drafts `docs/retrospectives/YYYY-WW.md`. Turns ad-hoc "half my time on the harness" into systematic weekly attention.

### P2 — Session observability dashboard

Lightweight `claude-status` command aggregating active sessions (local + `--remote`), active plans, tool-call budget consumption, recent hook firings, uncommitted work at risk of wipe. Aggregates existing state files — no new infrastructure needed.

### P2 — Harness version contracts

Each project declares `harness-version: >=N` in its CLAUDE.md. Breaking harness changes bump the version. SessionStart warns if project version predates current harness. Prevents silent regressions as harness evolves beyond what older projects expected.

### P2 — Validate Decision 011 Approach A end-to-end via real `claude --remote` session (2026-04-23)

Plan #4 (`docs/plans/claude-remote-adoption.md`) Phase B set up Approach A on a reference downstream project (a small work-account demo repo on GitHub) — `.claude/` directory exists in that project's working tree with the harness committed-copy form per Decision 011, but the `git commit` and `git push` were deferred because the reference repo had no configured user identity and the builder did not have authority to set it.

Required user action:
1. From the reference project's directory: confirm the appropriate git identity is set (one-time per-machine), then `git add .claude/ && git commit -m "chore: adopt Neural Lace harness via project .claude/ (Decision 011 Approach A)" && git push`.
2. Launch `claude --remote "list every rule loaded for this session and confirm any one hook fires"` against the reference project's pushed branch.
3. Confirm: (a) cloud session enumerates the rules in `.claude/rules/` matching the local set, (b) at least one hook from `.claude/settings.json` fires during the session, (c) `task-verifier` agent is dispatchable from the cloud session.
4. If any of (a)/(b)/(c) fails, file the failure mode against Decision 011 — Approach A may need refinement (e.g., symlink fallback, settings.json adjustments for cloud).

This is the integration test referenced in Decision 011's Test Plan section, and the empirical validation deferred from Phase A.



### P1 — Mysterious `effortLevel` wipe during session (2026-04-22/23)

Observed: `~/.claude/settings.json` started the session with `effortLevel: "max"`. Partway through, a subsequent `jq -r '.effortLevel'` returned `null` (key removed or value nulled). No task in the executing plan intentionally touched this field. Neither the main session nor any dispatched builder agent reported editing it.

Plausible causes:
- A PreToolUse or PostToolUse hook silently normalizing settings.json (e.g., a JSON rewriter that drops unknown keys)
- A concurrent session on the same machine overwriting settings.json with an older version (the concurrent-session state collision pattern we already have logged)
- An `install.sh` re-run during the session restoring from a template that had the key but was processed incorrectly
- A tool call with a full-file Write to settings.json that didn't preserve the effortLevel field

Remediation needed:
- Audit every hook that reads/writes `~/.claude/settings.json` for normalization that could drop top-level keys
- Consider adding a SessionStart hook that snapshots `settings.json` to `~/.claude/state/settings-snapshot.json` and, on next SessionStart, diffs against the current file to surface silent mutations
- Document the root cause once identified, then add a test/guard

Until fixed: users should periodically check `jq -r '.effortLevel' ~/.claude/settings.json` is not `null`. The existing `effort-policy-warn.sh` hook catches this indirectly (will warn if env var is unset and settings is missing the key AND policy requires non-low).

### P1 — Harness-work plans have no tracked home

Per `harness-hygiene.md`, the harness repo adds `docs/plans/` to `.gitignore` (harness repos don't ship instance artifacts). But harness-dev work DOES produce plan files, and those plans have no naturally-tracked home:

- `neural-lace/docs/plans/` — gitignored; plans there survive locally but aren't protected from `git clean`
- `~/.claude/plans/` — outside any git repo; plans there survive git operations anywhere but aren't version-controlled or shareable

Encountered 2026-04-22: wrote `harness-quick-wins-2026-04-22.md` to `neural-lace/docs/plans/`, hit the `.gitignore` at commit time, moved to `~/.claude/plans/` which is outside any repo.

Options to resolve:
- **Separate harness-dev repo:** e.g., `neural-lace-dev` or similar, tracking only the working plans/decisions/sessions for harness evolution. Isolates instance artifacts from shareable harness code.
- **Carve-out within neural-lace:** a `docs/internal-plans/` (not gitignored) specifically for harness-dev plans. Weakens the hygiene guarantee (contributors may leak identifiers), requires reviewer vigilance.
- **Accept `~/.claude/plans/`:** formalize this as THE location for harness-dev plans. Add a README there explaining the convention. Plans are local-only by design; cross-machine collaboration requires explicit git init + separate repo setup by the contributor.

Recommendation pending: option 3 (accept local-only) is cheapest and matches actual practice. Options 1-2 are correct for a growing contributor base.

### P2 — Bug-persistence gate should recognize cross-repo persistence

The `bug-persistence-gate.sh` hook scopes its check to the current project's `docs/backlog.md` or `docs/reviews/`. When trigger phrases reference harness-level concerns and persistence legitimately happens in the neural-lace repo, the hook still fires against the project cwd.

Two possible fixes:
- **Harness-aware scoping:** check both the current project's `docs/` AND `~/claude-projects/neural-lace/docs/backlog.md` when trigger phrases reference harness concerns (would require classifying trigger phrases as project-level vs harness-level)
- **Cross-repo persistence attestation:** explicit sentinel file (e.g., `.claude/state/persisted-elsewhere-<hash>.txt`) carrying the commit SHA of the cross-repo persistence; similar to the existing `--ack` pattern

Workaround pattern (used 2026-04-22): write a dated review file in the current project's `docs/reviews/` that points at the authoritative persistence location. Works but requires the agent to remember to do it.

### P2 — Pre-existing harness-mirror drift between `~/.claude/` and `adapters/claude-code/` (surfaced 2026-04-24)

While building the failure-mode catalog plan (`docs/plans/failure-mode-catalog.md`), the harness-maintenance diff loop surfaced 25 pre-existing files that DIFFER between `~/.claude/` and `adapters/claude-code/`, plus 4 files MISSING from the repo. The drift is unrelated to the catalog plan and was already present at branch base. Affected categories: 7 agents, 11 rules, 7 hooks/skills/templates. Until reconciled, the harness-maintenance diff loop produces a noisy baseline that masks new drift.

**Fix:** dedicated reconciliation pass — for each DIFFERS file, decide which side is canonical (the live `~/.claude/` typically reflects the most recent thinking) and re-mirror. For the 4 MISSING files (`templates/completion-report.md`, `templates/decision-log-entry.md`, `skills/pt-implement.md`, `skills/pt-test.md`), copy to the repo. Then the diff loop returns clean and any future drift is immediately visible.

### P2 — capture-codify: detect FM-NNN-cited-but-doesn't-exist (2026-04-23)

Surfaced during planning of `docs/plans/capture-codify-pr-template.md` Section 6 ("Observability gaps"). Currently when a PR's mechanism field selects answer form (a) "Existing catalog entry" and cites `FM-NNN`, neither the CI workflow nor the local pre-push hook checks whether `FM-NNN` actually exists in `docs/failure-modes.md` at PR open time. A typo (`FM-001` vs `FM-100`) or a stale citation slips through silently — the PR passes the validator but the cite is dangling.

**Proposal:** extend the validator library (`.github/scripts/validate-pr-template.sh`) to optionally cross-reference any `FM-\d+` substring in the (a) section against `docs/failure-modes.md` headings (`^## FM-\d+`). On miss, emit a soft warning (`[pr-template] WARN: cited FM-NNN not found in catalog`) without failing the check — reviewer responsibility for now, but the warning makes the gap visible. Hard-fail later if false-positive rate is low.

**Effort:** ~1 hour (single regex addition, self-test cases for hit/miss/no-cite). Existing validator structure makes this trivial.

### P2 — capture-codify: answer-form distribution telemetry (2026-04-23)

Surfaced during planning of `docs/plans/capture-codify-pr-template.md` Section 6. The mechanism field has three answer forms (a / b / c). Tracking the distribution over time would surface meaningful patterns: a sudden spike in (c) "no mechanism" answers signals discipline drift; a steady stream of (b) "new entry proposed" with no follow-up catalog growth signals a broken capture-codify cycle.

**Proposal:** extend `adapters/claude-code/scripts/audit-merged-prs.sh` to count (a/b/c) selections per PR and emit a distribution summary alongside the per-PR PASS/FAIL output. Optionally feed the counts into the weekly `/harness-review` skill's compliance section.

**Effort:** ~2 hours. The validator library already detects answer-form selection in `detect_answer_form()`; surfacing it from the audit script is a single counter loop.

### P2 — capture-codify: pre-commit atomicity gate for template ↔ validator edits (2026-04-23)

Surfaced during planning of `docs/plans/capture-codify-pr-template.md` Section 7 (failure-mode row "Accidental template-file edit"). The validator library expects specific section headings and placeholder text in `.github/PULL_REQUEST_TEMPLATE.md`. If a maintainer edits the template (e.g., changes wording while editing nearby files) without updating the validator's regex constants, the validator silently breaks — the next PR after the edit fails CI unexpectedly with a confusing message.

**Proposal:** new pre-commit hook `template-validator-atomicity-gate.sh` that detects when `.github/PULL_REQUEST_TEMPLATE.md` is staged AND `.github/scripts/validate-pr-template.sh` is NOT staged in the same commit; blocks with a stderr message naming the rule. Mirror of the existing `decisions-index-gate.sh` atomicity pattern.

**Effort:** ~3 hours. Existing atomicity gate (`decisions-index-gate.sh`) is a direct template; copy + adapt regex + write self-test.

## Existing entries

## ✅ DELIVERED 2026-04-20 — Mechanical enforcement of bug-persistence rule

Shipped in commit `0090d4b`: `hooks/bug-persistence-gate.sh` Stop hook wired into `settings.json.template`. Scans session transcript for trigger phrases, checks `docs/backlog.md` + `docs/reviews/` for persistence, blocks session end if bugs mentioned without being recorded. Attestation escape hatch via `.claude/state/bugs-attested-*.txt`. Documented in `docs/harness-architecture.md`.

## P1 — Consolidated findings rollup on session end

Related to the bug-persistence hook: a skill or helper that, at session end, reads all `docs/reviews/YYYY-MM-DD-*.md` files + recent git log for `docs/backlog.md` changes, and produces a single `docs/sessions/YYYY-MM-DD-session-summary.md` cataloging every finding + its disposition (fixed in commit X / deferred to backlog entry Y / invalid).

## P1 — Hardening of existing self-applied rules

Several rules in `~/.claude/rules/` are Pattern-level (no hook enforcement) and depend on agent discipline. Audit them for which ones are violated most often in practice, and propose Mechanism-level enforcement (hook / schema / assertion) for the top offenders. Candidates from observation:

- `planning.md`'s "Identifying a gap = writing a backlog entry, in the same response" — violated on 2026-04-20
- `orchestrator-pattern.md`'s "Main session dispatches, doesn't build directly" — violated when main session is tempted by small edits
- `testing.md`'s "E2E testing after system-boundary commit" — often skipped when under time pressure

## P0 — Stop hook for "narrate-and-wait" pattern (new 2026-04-21)

Counterpart to bug-persistence-gate: catch the pattern where the agent
completes a unit of work, narrates a summary, and implicitly stops
waiting for user confirmation. Specifically blocks session termination
when the last N assistant turns contain trigger phrases like "next up
is", "ready to continue", "want me to proceed", "after merge", "then
I'll" — indicating the agent has queued up work it could be doing now
but is pausing to announce.

Scope ~3 hrs: Stop hook script, transcript regex, allowlist for genuine
end-of-session summaries (e.g., "done for tonight", explicit /clear
requests, explicit "stop" from user).

This was added after the maintainer repeatedly observed the agent
stopping mid-execution on 2026-04-21 and asking rhetorical "are you
still working?" questions.
