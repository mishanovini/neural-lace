# Plan: Harness Build Queue Reorganization — 2026-04-23

Status: COMPLETED
Execution Mode: orchestrator
Mode: code
Backlog items absorbed: none
acceptance-exempt: true
acceptance-exempt-reason: Reorganization meta-plan that orchestrates other plans. No product user; deliverable is an execution sequence + a record of the queue's outcome.

> **This is a reorganization proposal, not an execution plan.** Status is `PROPOSED` to distinguish it from plans awaiting build. On user approval of the sequence below, individual plans transition to execution per their own `Status: ACTIVE` headers; this document is then marked `COMPLETED` and archived. No hook-enforced section is missing — the required sections are present but adapted to the reorg context.

## Goal

Two streams of harness planning converged this week: (a) five plans drafted by a parallel planning session addressing plan-file durability, failure-capture infrastructure, session-mode decision tree, and product-acceptance; (b) one plan just drafted in the current session — `end-user-advocate-acceptance-loop` — addressing adversarial observation of the running product. All six plans are now ACTIVE. Multiple plans touch the same files; several share the same underlying goal via different mechanisms.

Without reconciliation, executing these in arbitrary order will produce merge conflicts, redundant work, and — worse — incomplete coverage where two plans assumed the other would handle a shared concern. The goal of this document is one coherent execution queue, with overlaps, conflicts, dependencies, and obsolescence surfaced explicitly before any build work begins. The deliverable for the user is a single numbered sequence they can approve or revise; the deliverable for future Claude sessions is a durable record of why the sequence is what it is, so future work doesn't re-derive it.

## Scope

### IN

- Complete inventory of all six currently-ACTIVE plans across neural-lace and a downstream project
- Explicit mapping of overlaps, conflicts, dependencies, and obsolescence candidates
- A single proposed execution sequence with rationale and estimated durations
- Delta against `docs/backlog.md` based on insights surfaced during reorganization
- Immediate commit (commit-on-creation discipline; protects this reorg document from concurrent-session wipe)

### OUT

- Re-planning the contents of individual plans (their plan files already carry their own scope decisions; this doc only reorders them)
- Executing any of the listed plans (user-approval gate before execution per prompt)
- Reconciling plans outside the six listed (no other ACTIVE plans exist at reorganization time)
- Changes to `CONTRIBUTING.md`, `harness-maintenance.md`, or other governance docs (out of scope unless execution surfaces conflicts)

## 1. Full Inventory

| # | Plan File | Stream | Repo | Tasks | Status | Absorbed backlog |
|---|---|---|---|---|---|---|
| 1 | [plan-deletion-protection.md](docs/plans/plan-deletion-protection.md) | Parallel | neural-lace | 11 | ACTIVE | Plan file deletion protection |
| 2 | [failure-mode-catalog.md](docs/plans/failure-mode-catalog.md) | Parallel | neural-lace | 9 | ACTIVE | Failure mode catalog as a first-class artifact |
| 3 | [capture-codify-pr-template.md](docs/plans/capture-codify-pr-template.md) | Parallel | neural-lace | 8 | ACTIVE | Capture-codify cycle at PR level |
| 4 | [claude-remote-adoption.md](docs/plans/claude-remote-adoption.md) | Parallel | neural-lace | 10 | ACTIVE | Adopt claude --remote; Harness portability to cloud sessions |
| 5 | robust-plan-file-lifecycle.md | Parallel | **a downstream project** | 18 | ACTIVE | none |
| 6 | [end-user-advocate-acceptance-loop.md](docs/plans/end-user-advocate-acceptance-loop.md) | Current session | neural-lace | ~27 across 7 phases | ACTIVE | Adversarial pre-mortem pattern for plans |

**Stream attribution**: plans 1-5 were committed to master between commits `60205e9`, `61b711f`, `30fc0c7` (neural-lace) plus the downstream-project-side commit (parallel-session work). Plan 6 was just committed in the current session as commit `3adb281`. Per the user's prompt, the parallel planning session was running in a separate session on the same filesystem while this session was drafting plan 6.

**Total task surface**: 83 tasks across 6 plans. At a rough 30-60 minute average per harness task (historical rate), this is ~40-80 hours of build work — roughly 1-2 weeks at normal pace.

## 2. Overlaps

### Overlap A — Plan-file durability (plans #1 + #5)

**Shared problem:** plan files getting wiped or lost between concurrent sessions.

- **Plan #5 (`robust-plan-file-lifecycle`)** closes the **creation window** (commit-on-creation warning; uncommitted plans are vulnerable) and adds **auto-archival** on terminal status transition plus **archive-aware lookup**.
- **Plan #1 (`plan-deletion-protection`)** closes the **destructive-command window** (blocks `rm`, `git clean`, `git stash -u`, `git checkout .`, `mv` against `docs/plans/*`).

**Verdict: complementary, not duplicative.** Plan #1's own description explicitly calls itself "a defense-in-depth companion to the commit-on-creation protection (in the `robust-plan-file-lifecycle` plan)." Both are needed for comprehensive protection: plan #5 closes the uncommitted window; plan #1 closes destructive-command edges even on committed files. Keep both.

**Proposed ordering:** plan #5 **first** because it establishes the `docs/plans/archive/` convention that plan #1 needs to whitelist. Plan #1 second so the archive directory exists before the deletion-protection hook defines allowed destinations.

### Overlap B — Failure-to-mechanism capture (plans #2, #3, and #6's Phase 5)

**Shared problem:** turning observed failures into durable harness improvements (the core feedback loop from `claude-code-quality-strategy.md`).

- **Plan #2 (`failure-mode-catalog`)**: creates the CATALOG — the registry where failure classes live (`docs/failure-modes.md` with schema: Symptom, Root cause, Detection, Prevention, Example). Seeds 4-6 entries.
- **Plan #3 (`capture-codify-pr-template`)**: creates the MANUAL CAPTURE FLOW — every PR must answer "what mechanism would have caught this?" CI-enforced.
- **Plan #6 Phase 5 (`enforcement-gap-analyzer` agent)**: creates the AUTOMATED CAPTURE FLOW — when runtime acceptance fails, an agent produces a proposal (same shape as a catalog entry).

**Verdict: three layers of the same system, each necessary.**
- Catalog is the backing store.
- PR template catches issues that HUMANS identify during PR review.
- Gap-analyzer catches issues that OCCUR AT RUNTIME during acceptance testing.

These hit different discovery channels. None is obsolete. But they share infrastructure:
- All three reference `docs/failure-modes.md` and `FM-NNN` IDs
- Plans #3 and #6 both use `harness-reviewer` as a gate on proposed rule changes
- Plans #3 and #6 both edit `rules/planning.md` (different sections)

**Proposed ordering:** **plan #2 first** (builds the catalog — foundation both consumers depend on). Plans #3 and #6 can run in parallel after #2 because they edit largely disjoint files and consume the catalog independently.

### Overlap C — Stop-hook chain extensions (plan #5 + plan #6)

Both plans extend `pre-stop-verifier.sh` with new behavior:
- Plan #5 adds a warning for uncommitted plan files at session end
- Plan #6 chains to a new `product-acceptance-gate.sh` that blocks session end when acceptance artifacts are missing

**Verdict: non-conflicting additive changes.** Serial execution avoids merge conflicts. Both extensions are additive to separate code paths.

**Proposed ordering:** plan #5 lands its `pre-stop-verifier.sh` change first; plan #6's change rebases cleanly on top.

### Overlap D — Agent remits touching `task-verifier.md`

Three plans modify `adapters/claude-code/agents/task-verifier.md`:
- Plan #2: adds "consult the catalog" step for known-bad patterns
- Plan #5: adds archive-aware path resolution
- Plan #6: bootstrap-excluded (doesn't directly modify task-verifier, but relies on it as the checkbox-flip authority)

**Verdict: non-conflicting additive changes.** Different sections of the prompt.

**Proposed ordering:** serial commits; each plan lands its change in sequence. No special handling needed.

### Overlap E — `rules/planning.md` edits

Three plans modify `adapters/claude-code/rules/planning.md`:
- Plan #3: adds "Capture-codify at PR time" section
- Plan #5: adds "Plan File Lifecycle" section (creation → archival → lookup)
- Plan #6: adds reference to `rules/acceptance-scenarios.md` and updates the plan-template requirement

**Verdict: non-conflicting, all additive.** Serial commits.

## 3. Conflicts

**None detected.** All six plans propose additive changes with no conflicting mechanism choices. The closest thing to a conflict:

- Plan #5 says "Status is the last edit to a plan" (because Status terminal triggers auto-archival). Plan #6 says nothing about Status edit ordering but adds a `Status: DEFERRED/ABANDONED` escape path for acceptance-failing plans. These are compatible: plan #5's convention applies to the Status flip itself; plan #6 can still flip Status after writing its completion report.

- Plan #3 establishes a PR template that references the catalog; plan #6's enforcement-gap-analyzer produces proposals that should also reference the catalog. Neither constrains the other's proposal format; they share infrastructure but don't overlap in output shape.

No user decision is needed on compatibility of approaches. The plans are independently designed but compose cleanly.

## 4. Dependencies

Concrete blocking reasons for each edge:

| Dep | Plan | Blocks | Reason | Strength |
|---|---|---|---|---|
| D1 | #5 (lifecycle) | #1 (deletion-protection) | Archive directory `docs/plans/archive/` must exist and be a known convention before #1 whitelists it as an allowed `mv` destination | Medium (can pre-declare archive) |
| D2 | #2 (catalog) | #3 (PR template) | PR template references `FM-NNN` catalog IDs; without the catalog, the IDs have nothing to point at. Plan #3 includes a stub creation (task 6) as a workaround, but real catalog is cleaner | Soft (stub unblocks) |
| D3 | #2 (catalog) | #6 (gap-analyzer in Phase 5) | Gap-analyzer produces proposals that become catalog entries; without the catalog, proposals have no destination | Soft (stub unblocks) |
| D4 | #5 (lifecycle) | #6 | Both extend `pre-stop-verifier.sh`; landing #5 first avoids merge friction | Soft (mergeable either order) |
| D5 | #6 (acceptance loop) | *no downstream blocker* | Plan #6 institutes a new enforcement layer; subsequent plans will be reviewed through it, but no current plan depends on it being live | None |
| D6 | #4 (claude-remote) | *no downstream blocker* | Plan #4 adds a session-mode decision tree; other plans work in any session mode, so #4 is decoupled | None |

**Strongest blocking edges** (must respect sequence):
- D1: plan #5 before plan #1 (archive convention)
- D4: plan #5 before plan #6 (pre-stop-verifier ordering)

**Soft edges** (preferred sequence, not strict):
- D2, D3: plan #2 before plans #3 and #6

## 5. Obsolescence

**No plan is made obsolete by another.** Every plan solves a distinct problem.

The closest candidate: plan #3's manual PR-template flow partially overlaps with plan #6's automated gap-analyzer flow (both ask "what mechanism would have caught this?"). One could argue the automated flow supersedes the manual one. **Verdict: they are complementary.**
- PR template fires on PRs authored with human involvement
- Gap-analyzer fires on runtime acceptance failures within autonomous sessions

Different failure-discovery channels. Keeping both is correct.

**Plan concurrency note:** SCRATCHPAD says "None active" but all six plans have `Status: ACTIVE`. The planning.md rule "do not start a new plan while another is ACTIVE" has drifted — not because of any one plan's fault, but because plan-creation has outpaced plan-reconciliation for 7+ days. Post-reorganization, the queue is accepted as concurrent-by-approval. Individual plans transition to `COMPLETED` as they ship, clearing the queue naturally.

## 6. Proposed Sequence

**Guiding principles (in order of importance):**
1. **Protect the work first.** Durability of plans before building more on top. The concurrent-session-wipe pattern has bitten twice; fixing it is the highest-leverage protection.
2. **Build foundations before consumers.** Artifacts that other plans reference (the catalog) must exist first.
3. **Sequence file contention.** Plans that edit the same file go serial.
4. **Parallelize where safe.** Independent plans can run concurrently — but only after plan-durability mechanisms are in place, because concurrent local sessions without those mechanisms is what caused the wipes.

### Proposed execution order

**Batch 1 — Plan durability (serial; closes the wipe failure class)**

1. **Plan #5 — `robust-plan-file-lifecycle`** (downstream-project repo, 18 tasks, est. 8-12 hrs)
   - Rationale: protects UNCOMMITTED plans (commit-on-creation) and establishes archive directory.
   - Blocks: plans #1 and #6 (soft to medium).
   - Success signal: `plan-lifecycle.sh` passes self-test; end-to-end verification in Task 18 passes.

2. **Plan #1 — `plan-deletion-protection`** (neural-lace, 11 tasks, est. 4-8 hrs)
   - Rationale: protects COMMITTED plans from destructive commands. Whitelists archive directory established by #5.
   - Blocks: nothing downstream.
   - Success signal: `plan-deletion-protection.sh` passes 14 self-test scenarios; live verification against throwaway plan.

**Batch 2 — Failure-capture foundation (serial)**

3. **Plan #2 — `failure-mode-catalog`** (neural-lace, 9 tasks, est. 4-6 hrs)
   - Rationale: creates the shared artifact that plans #3 and #6 both reference.
   - Blocks: plans #3 and #6 (soft — both could run with a stub, but catalog first is cleaner).
   - Success signal: `docs/failure-modes.md` exists with 4-6 seed entries; referenced in `diagnosis.md`, `harness-lesson.md`, `why-slipped.md`, `claim-reviewer.md`, `task-verifier.md`.

**Batch 2.5 — Reviewer-discipline upgrade (serial; just-in-time for Batch 3)**

3.5. **Plan #7 — `class-aware-review-feedback`** (neural-lace, 10 tasks, est. 2-3 hrs) — INSERTED 2026-04-23 PM
   - Rationale: addresses the narrow-fix-bias pattern observed across 6 `systems-designer` iterations on plan #3. Modifies all adversarial-review agents (Mod 1) + adds "Fix the Class, Not the Instance" sub-rule to `diagnosis.md` (Mod 3). Mod 2 (mechanical hook) deferred to backlog.
   - Blocks: Plan #6's systems-designer review (RUN THIS BEFORE plan #6's review starts so the agent emits class-aware feedback from the first pass — saves the 5-iteration loop seen on plan #3).
   - Success signal: smoke test on a synthetic flawed plan returns reviewer output including `Class:` + `Sweep query:` + `Required generalization:` fields.

**Batch 3 — Parallel build (parallel dispatch via worktrees OR sequential if local)**

4a. **Plan #3 — `capture-codify-pr-template`** (neural-lace, 8 tasks, est. 4-8 hrs)
   - Rationale: human-driven failure-capture at PR review time.
   - Independent of #4b except both extend `harness-reviewer` remit and both edit `planning.md`. Serial commits if running locally; parallel worktrees OK.

4b. **Plan #6 — `end-user-advocate-acceptance-loop`** (neural-lace, ~27 tasks across 7 phases, est. 24-40 hrs — LARGEST)
   - Rationale: agent-driven failure-capture at runtime + the broader product-acceptance infrastructure.
   - REQUIRED: `systems-designer` PASS review before implementation begins (design-mode protocol).
   - Most substantial single plan; own walking-skeleton phase (Phase 1) mitigates risk.

**Batch 4 — Session-mode decision tree (can run anywhere, ideally LAST)**

5. **Plan #4 — `claude-remote-adoption`** (neural-lace, 10 tasks, est. 6-10 hrs)
   - Rationale: produces the decision tree for when to use which session mode. Independent of other plans.
   - **Why last:** the decision is informed by what the other plans built. E.g., if plan #6's acceptance loop requires browser automation, does cloud sessions support browser MCP? The answer shapes the decision tree's "autonomous cloud work" branch.
   - Phase A (investigation tasks 1-4) could run in parallel with any batch; Phase B (tasks 5-10) should wait.

### Parallelism safety notes

- **Local parallel sessions are UNSAFE** until Batch 1 ships. Concurrent `git stash`/`git clean` against `docs/plans/` has wiped work twice. Don't run Batch 1 itself in parallel; serialize those two.
- **Post-Batch-1 parallelism is SAFER** — destructive commands are blocked, plans are commit-on-creation protected. Worktrees or `claude --remote` become viable for #3 and #6 in parallel.
- **Batch 3's two plans share `planning.md` and `harness-reviewer.md`.** If running in parallel, either use worktrees (cherry-pick per orchestrator-pattern.md Phase B protocol) OR serialize the shared-file commits while parallelizing other work. Simplest: run serially end-to-end, accept the ~2-3 day delay.

### Estimated total duration

**Serial execution:** ~50-80 hours across all six plans (1-2 weeks at normal pace).

**With Batch 3 parallelized:** ~35-60 hours (saves 10-20 hours by overlapping #3 and #6).

**With Plan #4 investigation in background from Day 1:** additional ~5 hours saved.

**Realistic estimate with all parallelism safe to use:** ~30-50 hours (~5-8 working days).

## 7. Backlog Delta

After the absorptions performed at plan creation, `docs/backlog.md` has these open entries. Proposed changes based on reorganization insights:

### Entries already absorbed (no action)
- "Plan file deletion protection" — absorbed by #1
- "Failure mode catalog as a first-class artifact" — absorbed by #2
- "Capture-codify cycle at PR level" — absorbed by #3
- "Adopt claude --remote + dotfiles sync" — absorbed by #4
- "Harness portability to claude --remote cloud sessions" — absorbed by #4
- "Adversarial pre-mortem pattern for plans" — absorbed by #6

### Candidate for closure
- **P1 — "Harness-work plans have no tracked home"** (entry dated 2026-04-22). **Proposed: close.** The 2026-04-23 update to `CONTRIBUTING.md` — moving `docs/plans/` from gitignored to "committed but scanned" — resolved this. The entry's own text says "Recommendation pending: option 3 (accept local-only) is cheapest and matches actual practice" but the repo chose a different path (option 2: committed, scanned, not shipped). Close the entry with a note pointing at `CONTRIBUTING.md` lines 26-33.

### Entries not affected by current plan set
- **P1 — Verbal vaporware in conversation** — remains open. Plan #6 partially addresses at PRODUCT level but not CONVERSATION level. Needs a PostMessage hook that Claude Code doesn't support yet.
- **P1 — Tool-call-budget --ack bypass** — remains open. Neither reorg plan addresses it.
- **P1 — Concurrent-session state collisions** — **will be materially reduced** by Batch 1 shipping. After Batch 1, reclassify as P2 or close with a pointer to the shipped mitigations. For now, leave as-is until Batch 1 actually ships.
- **P0 — Harness-tests-itself: synthetic session runner** — remains open. Plan #6 Phase 7.1 creates a synthetic test specifically for the acceptance loop; that's one instance, not the general-purpose runner the backlog entry describes. Consider whether the pattern from Phase 7.1 generalizes.
- **P1 — Prompt template library for meta-questions** — per SCRATCHPAD, shipped in the harness-quick-wins plan. **Proposed: close** (may already be closed; verify during Batch 1 execution).
- **P1 — Hardening of existing self-applied rules** — remains open. Partially addressed by plan #6's enforcement-gap-analyzer (which will propose hooks for self-applied rule violations over time), but that's ongoing work, not a one-shot.
- **P1 — Delegability classification on plan tasks** — remains open.
- **P1 — Explicit interactive vs autonomous session mode** — remains open. Plan #4's `automation-modes.md` comes close but the rule decision tree isn't the same as per-session mode enforcement.
- **P2 — Effort-level enforcement at project level** — per SCRATCHPAD, shipped in harness-quick-wins. **Proposed: close** (verify).
- **P2 — Multi-model routing strategy** — remains open.
- **P2 — Scheduled retrospectives via `/schedule`** — remains open.
- **P2 — Session observability dashboard** — remains open.
- **P2 — Harness version contracts** — remains open.
- **P1 — Mysterious `effortLevel` wipe (2026-04-22/23)** — remains open (investigation ticket).
- **P2 — Bug-persistence gate cross-repo persistence** — remains open.

### New backlog candidates surfaced by this reorganization

- **P2 — Mass plan-status reconciliation audit.** Multiple plans drifted to concurrent `ACTIVE` over 7 days. Consider a hook or weekly check that surfaces "N plans ACTIVE for M days — reconcile?" Pattern, not mechanism, until staleness recurs empirically.
- **P2 — Reorg-style documents as a standing mechanism.** This doc is the first of its kind. If queue-reorganization happens more than once, consider adding a template + skill (`/reorganize-plans`) instead of re-deriving the format each time.

## Tasks

- [ ] 1. User reviews reorganization; approves, revises, or rejects the proposed sequence.
- [ ] 2. If approved: execute Batch 1 — `robust-plan-file-lifecycle` first, then `plan-deletion-protection`.
- [ ] 3. Execute Batch 2 — `failure-mode-catalog`.
- [ ] 4. Execute Batch 3 in parallel if Batch 1 shipped safely: `capture-codify-pr-template` + `end-user-advocate-acceptance-loop`. Plan #6 gated on `systems-designer` PASS.
- [ ] 5. Execute Batch 4 — `claude-remote-adoption` (Phase A investigation can run earlier in parallel).
- [ ] 6. Backlog delta: close confirmed-shipped entries; reclassify concurrent-session-collision entry after Batch 1; consider new backlog candidates surfaced above.
- [ ] 7. Mark this reorganization plan `Status: COMPLETED` at queue completion; archive to `docs/plans/archive/`.

## Files to Modify/Create

### Create

- `docs/plans/reorganization-2026-04-23.md` (this file)

### Modify (during execution of individual plans — tracked in each plan's own Files section)

- `docs/backlog.md` — remove confirmed-shipped items (tasks 6 above); add new candidate entries if approved

## Assumptions

- The user's four ACTIVE plans from the parallel session were created in good faith and the code/hooks they propose are correct. This reorg does not re-review those plans' internal design decisions — it only reorders them.
- Plan #6 (`end-user-advocate-acceptance-loop`) will pass `systems-designer` review with at most minor revisions. If systems-designer returns FAIL with substantive gaps, Batch 3 might need to be split into "execute #3, hold #6 pending revisions."
- "Task count" is a rough complexity proxy. Tasks vary widely; the 30-60 minute average assumes harness-style hook/agent/rule work similar to prior completed plans (document-freshness-system, harness-quick-wins, public-release-hardening).
- The downstream-project-side plan #5 can be executed from the current Claude session even though it lives in a separate repo. If the current session is anchored to neural-lace, plan #5 may need to be dispatched via a separate session or worktree. Clarify on approval.
- `claude --remote` is not adopted yet (that's plan #4's deliverable). During execution of Batches 1-3, parallelism options are local worktrees only. Worktree isolation protects git state but not `~/.claude/` state (shared across local sessions).
- The user's prompt implied this reorganization should run NOW, before any build work. That premise is accepted; no plan starts building until approval.

## Edge Cases

- **A seventh ACTIVE plan appears during reorganization.** Integrate into the sequence before approval, or flag as a late arrival and let user decide whether to re-open the reorg.
- **`systems-designer` fails plan #6 with substantive gaps.** Split Batch 3: execute #3, queue #6 for revision. Revisit the overall sequence if gaps are large.
- **Batch 1 reveals an unexpected blocker** (e.g., `plan-lifecycle.sh` can't detect status transitions reliably in the current Claude Code hook contract). Block Batch 1; escalate to user. Do NOT proceed to Batch 2 until plan durability is established.
- **Plan task counts grow during execution** (expanded scope, additional subtasks discovered). Reforecast the duration and surface to the user, but don't silently reorder.
- **One plan in Batch 3 hits an unforeseen dependency on the other.** Stop parallel execution; serialize. The cherry-pick-then-verify protocol in `orchestrator-pattern.md` Phase B should handle this cleanly.
- **User rejects the sequence and proposes a different order.** Accept the revision; update this document's tasks list to reflect the approved order; re-commit.
- **Mid-sequence the user surfaces a new urgent task.** Treat as an interrupt: pause the current batch at the nearest clean stopping point, handle the urgent work, resume.
- **`docs/backlog.md` gets edited by another session during the reorg.** Merge on commit; the backlog-plan-atomicity hook treats absorbed items correctly on individual plan creation, but free-form backlog edits during reorg don't have a hook. Manual merge if conflict.

## Testing Strategy

This document is a proposal, not a build. Validation is:

- **Inventory completeness:** every ACTIVE plan in `docs/plans/*.md` (neural-lace) and the downstream project's `docs/plans/*.md` is listed in Section 1. Verified by `git ls-files docs/plans/ | grep -v archive` and visual diff against Section 1's table.
- **Overlap analysis correctness:** for each identified overlap, both plans' files are cited with specific task numbers or file references. Reader should be able to open both plan files and confirm the overlap described matches reality.
- **Dependency edges justified:** every dependency has a named blocking reason pointing at a specific mechanism (file path, artifact name, rule name). No hand-wavy "they seem related."
- **Sequence feasibility:** no plan is sequenced ahead of its hard dependencies. Verify by reading the dependency table (Section 4) and the sequence (Section 6) together.
- **Backlog delta accuracy:** each closure recommendation cites a specific commit or document that justifies closure. Each "remains open" entry has an explicit reason it's not addressed by any queued plan.

On user approval, the `Status: PROPOSED` flips to `Status: COMPLETED` and this doc archives. If the proposal is rejected, the rejection reason is recorded here before archival, and a replacement reorg is drafted.

## Decisions Log

*This document is a proposal; substantive decisions will be recorded during user review. Any sequence change approved by the user will be recorded here with rationale.*

## Definition of Done

- [ ] User reviews the proposed sequence in Section 6
- [ ] User approves, revises, or rejects the sequence
- [ ] If approved: the Tasks section above reflects the approved order; subsequent execution tracks against it
- [ ] If revised: the revision is recorded in Decisions Log; Section 6 is updated; re-commit
- [ ] On completion of all queued plans: `Status: COMPLETED`, archived to `docs/plans/archive/`
- [ ] Backlog delta (Section 7) applied to `docs/backlog.md` in a separate commit during or after Batch 1

## Completion Report

**All 7 queued plans shipped + merged + pushed to both remotes (personal + work-account). 100 tasks total.**

### Plans shipped (in approved sequence)

| # | Plan | Tasks | Status | Final commit on master |
|---|---|---|---|---|
| 1 | `robust-plan-file-lifecycle` | 18 (A.1-F.3) | COMPLETED + auto-archived | (Batch 1 first) |
| 2 | `plan-deletion-protection` | 11 (A.1-C.2) + atomicity-gate fix bonus | COMPLETED + auto-archived | (Batch 1 second) |
| 3 | `failure-mode-catalog` | 9 (A.1-A.9) | COMPLETED + auto-archived | (Batch 2) |
| 4 | `class-aware-review-feedback` | 10 (A.1-A.10) | COMPLETED + auto-archived | (Batch 2.5, inserted) |
| 5 | `capture-codify-pr-template` | 15 (A.1-A.15) | COMPLETED + auto-archived; PR #1 merged + branch protection LIVE | (Batch 3 first) |
| 6 | `end-user-advocate-acceptance-loop` | 27 (A.1-G.5, 7 phases) | COMPLETED + auto-archived; systems-designer PASS-with-nits | (Batch 3 second, sequential) |
| 7 | `claude-remote-adoption` | 10 (A.1-A.10) | COMPLETED + auto-archived; Decision 011 records hybrid approach | (Batch 4) |

### Sequence adherence

The actual execution order matched the proposed sequence with one insertion:
- **Batch 1:** plan #5 (robust-plan-file-lifecycle) → plan #1 (plan-deletion-protection) ✓
- **Batch 2:** plan #2 (failure-mode-catalog) ✓
- **Batch 2.5 (inserted during execution per user request):** plan #7 (class-aware-review-feedback) — inserted between Batch 2 and Batch 3 to give plan #6's systems-designer review the benefit of class-aware reviewer feedback
- **Batch 3:** plan #3 (capture-codify-pr-template) → plan #6 (end-user-advocate-acceptance-loop) — executed sequentially rather than parallel to manage context size + because plan #3 was already PASS-with-nits while plan #6 still needed systems-designer review
- **Batch 4:** plan #4 (claude-remote-adoption) ✓ executed last as planned

### Backlog delta applied

- 7 backlog entries absorbed by individual plans (deleted from open sections atomically with each plan creation)
- 5+ new backlog entries added during execution (P2 dynamic-load gap for hooks/agents, P2 archival-staging gap, P0 class-aware reviewer feedback before plan #7 absorption, P2 atomicity-gate archival false-positive, P2 cloud-session integration test, etc.)
- Several P0/P1 entries materially closed by shipped plans:
  - "Plan file deletion protection" → closed (plan #1)
  - "Failure mode catalog as a first-class artifact" → closed (plan #2)
  - "Adversarial pre-mortem pattern for plans" → closed (plan #6)
  - "Capture-codify cycle at PR level" → closed (plan #3)
  - "Adopt claude --remote + dotfiles sync" → closed (plan #4 Decision 011)
  - "Harness portability to claude --remote cloud sessions" → closed (plan #4 Decision 011)
  - "Class-aware reviewer feedback (Mods 1+3)" → closed (plan #7); Mod 2 remains as standalone P1 backlog entry

### Major mechanisms shipped this session (cross-plan summary)

- **`plan-lifecycle.sh`** — auto-archives plans on Status terminal flip (plan #5)
- **`plan-deletion-protection.sh`** — blocks destructive ops on plan files (plan #1)
- **`docs/failure-modes.md`** — 6-entry seed catalog of known failure classes (plan #2)
- **Class-aware reviewer feedback format** — 7 reviewer agents now require `Class:` + `Sweep query:` + `Required generalization:` per gap (plan #7)
- **`.github/workflows/pr-template-check.yml` + branch protection** — every PR to neural-lace master now requires "What mechanism would have caught this?" (plan #3)
- **`product-acceptance-gate.sh` + `end-user-advocate` agent + `enforcement-gap-analyzer` agent** — adversarial-observation gate at session end + automated harness improvement loop (plan #6)
- **`rules/automation-modes.md` + Decision 011** — formal session-mode decision tree + Approach A harness portability for cloud sessions (plan #4)

All shipped to master across ~50+ commits. Both remotes (both remote-repo names) up to date.

### Activates at next session start (dynamic-load gap, P2 backlog)

- Permission allowlist for harness paths (no more per-file prompts)
- All 7 reviewer agents emit class-aware feedback per default
- `plan-deletion-protection.sh` blocks `rm`/`git clean -f`/`git stash -u`/`git checkout .`/`mv` against plan files
- `product-acceptance-gate.sh` enforces acceptance scenarios at session end (or honors `acceptance-exempt: true`)
- New agents `end-user-advocate` and `enforcement-gap-analyzer` available via Task tool
- New rule `acceptance-scenarios.md` consulted by planning workflows
- Updated `harness-reviewer.md` (Step 5 generalization checks) gates new enforcement-gap proposals

### Known residual issues (deferred to backlog)

- Live empirical validation of `claude --remote` Approach A (P2 — user runs first cloud session in reference project)
- Live integration test of end-user-advocate runtime mode against a real product (P2 — first downstream-project plan with user-facing acceptance scenarios)
- Pre-existing harness-mirror drift (25 DIFFERS + 4 MISSING between `~/.claude/` and `adapters/claude-code/`) — separate reconciliation pass needed
- Class-aware-review-feedback-smoke-test-plan.md leftover fixture from plan #7 — acceptance-exempt declaration needed OR cleanup
- Pre-existing untracked file `adapters/claude-code/rules/url-conventions.md` from a prior phase — needs commit OR delete
- A.7 multi-state + fork-PR smoke test for capture-codify (P2 — only PASS state empirically validated)

This reorganization closes successfully. All 7 plans complete, ~100 tasks shipped end-to-end with merges + pushes.
