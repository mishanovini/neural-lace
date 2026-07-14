# RESUME HERE — cross-machine handoff (updated 2026-07-14)

## ⭐ LATEST STATE (end of session, 2026-07-14) — read this first
- **ask-rooted-workstreams-p1 is COMPLETE: 18/18**, deployed live on `:7733`. Done.
- **Process-explosion crisis FIXED (was the recurring machine-killer / 3 reboots).** Root cause: a
  timeout-without-kill leak in `neural-lace/workstreams-ui/server/auditor.js` `runCli()` — the timeout
  resolved the promise but never killed the bash tree. Fixed with `killTree()` (Windows needs
  `taskkill /T`, not `child.kill()`). Landed `01e2045`, deployed, verified bounded in production.
  Lesson encoded as `doctrine/reap-what-you-spawn.md`. **Follow-up (filed, non-urgent):** the
  merge-scan backfill still exceeds its 60s timeout each cycle (killed, so no leak, but the backfill
  lane is non-functional) — make `scan-repo` INCREMENTAL (persist a last-scanned-SHA cursor).
- **The "world-class / evidence bar" standard landed:** `doctrine/artifact-evidence-bar.md` (+full) —
  no artifact ships without evidence it beats naive; gates need a golden scenario, AGENTS need a GOLDEN
  CASE, DESIGNS need an architecture review before build. Plus a new **`architecture-reviewer` agent**
  (`agents/architecture-reviewer.md`) — a 6-phase adversarial protocol that attacks the SHAPE of a
  design; on its first run it killed the cockpit-v2 design with a measurement (3.5ms vs 87ms).
- **⚠ ENFORCEMENT for the evidence bar is BUILT-BUT-UNVERIFIED on branch
  `wip/evidence-bar-enforcement-gates` (commit `4b175ff`).** Two gates (architecture-review-before-build
  in `plan-reviewer.sh`; agent golden-case gate `agent-design-gate.sh` + settings wiring). The builder
  ended before its self-tests completed, so it is UNVERIFIED. TO FINISH: run each gate's self-test
  (fires-on-bad / silent-on-good), resolve INDEX.md + manifest.json conflicts vs master (both changed on
  master via `7511ce8`), flip the `artifact-evidence-bar` manifest `honest_status` from "NOT WIRED" to
  wired, then land. Until this lands, the standard is a PATTERN (documented) not a MECHANISM (enforced).
- **cockpit-v2 is the next BUILD.** `docs/plans/cockpit-v2-push-materialized-store.md` is v3 (operator
  chose STORE because cross-machine is a CURRENT requirement) — planned AND architecture-reviewed
  (`docs/reviews/2026-07-14-cockpit-v2-architecture-review.md`), all mandatory corrections applied. Ready
  to build. CRITICAL correction baked in: the store must sync via a dedicated git ref (like
  `broadcast-active-session.sh`), NOT a machine-local file, or it delivers zero cross-machine.
- There is NO item 5 (operator confirmed the earlier UI list was 4 items).


**You are picking up the ask-rooted Workstreams cockpit work on a fresh machine/session.**
`SCRATCHPAD.md` is gitignored and did NOT travel — this file is the durable record. Everything
below is on `origin/master`.

---

## 1. Read these first (in order)
1. `docs/plans/cockpit-v2-push-materialized-store.md` — **THE ACTIVE PLAN.** This is the work.
2. `docs/reviews/2026-07-14-ask-splice-review-panel.md` — the splice review + its 7 confirmed defects.
3. `docs/plans/ask-rooted-workstreams-p1.md` — the shipped P1 plan (17/18; see §3 below).

## 2. The architecture (operator directive, 2026-07-14 — this is the point of cockpit-v2)
- **The plan markdown file is the SOURCE OF TRUTH**, and must stay a continuously-updated living document.
- A **deterministic projector** (a script, not model memory) **PUSHES** the plan's projected state —
  task list, **descriptions**, checkbox state, progress — into a **consolidated multi-plan JSON store**
  at the moment the plan is edited (the same hook that already fires on a checkbox flip).
- **The GUI reads ONLY the store.** No plan-markdown read on any request path. Fast, always current.
- The auditor is **demoted to a safety net**: it re-projects periodically, heals a missed push, and
  **reports the drift** (a missed push is a bug to surface, never silently papered over).
- Because the same deterministic action that flips the checkbox also updates the store, **they cannot drift**.

**What exists today (the gap cockpit-v2 closes):** the checkbox flip already pushes a `task_done`
*event* to a per-ask JSONL, but `server.js`'s `computePlanRows` still **pulls** the task list +
checkbox state from the plan markdown at request time (`countPlanTasks`). That read-time join is what
gets deleted.

## 3. State of the world
- **Cockpit is DEPLOYED and LIVE** at `http://127.0.0.1:7733/` (ask-rooted landing: ask tree + To-Do +
  Backlog sidebar; the six old panes are behind a "Harness Health" tab). Restart with
  `adapters/claude-code/scripts/ensure-cockpit.sh` from the MAIN checkout.
- **ask-rooted-workstreams-p1: 17/18 tasks done.** Only **Task 7** is unflipped. Its remaining half =
  fix the 7 splice defects found by the review panel. The plan flips `Status: COMPLETED` only at 18/18.
- **Two fix builders were IN FLIGHT when the machine was rebooted.** Their work may be uncommitted in
  their worktrees — **RECONCILE GIT/DISK BEFORE ASSUMING ANYTHING**:
  - `.claude/worktrees/agent-ad5e3ba46bd6a3b3f` — splice findings 1-4 (progress-log-lib.sh,
    workstreams-emit.sh, dispatch-provenance.sh, plan-lifecycle.sh)
  - `.claude/worktrees/agent-a515ac5b3f57b54fc` — splice findings 5-7 (merge-scan-lib.sh)
  - Check `git -C <worktree> status --short` and `git log --oneline -1`. If uncommitted, finish +
    commit their fixes per the review doc (§1.2), cherry-pick, then flip Task 7 → 18/18.

## 4. Operator's outstanding UI asks (fold into cockpit-v2 task 5)
1. Panes **resizable**, and each independently **scrollable**.
2. Backlog rows are too tall — make them **compact/collapsed by default, expandable**.
3. The task list shows "task 1, task 2…" with **no description** — show each task's description (this
   is why the projector must capture it), and **drop the repeated long plan-path link on every row**
   (one "View live plan doc" button covers it).
4. **Remove the Artifacts list** — noise.
5. *(operator's item 5 — their message was cut off; ask them for it)*

## 5. HARD-WON GOTCHAS — read before spawning anything
- ⚠️ **PROCESS EXPLOSION IS THE #1 HAZARD.** Over-spawning agents has bogged this machine to a halt
  and forced **three reboots** (once with "literally hundreds of bash + Git-for-Windows processes").
  Windows Git-Bash forks heavily; **timed-out git commands leave orphan processes holding refs locks**,
  which wedges git itself (even `git rev-parse` hangs). **Hold to ≤2 concurrent heavy agents.** Prefer
  read-only reviewers over builders running self-test suites. Do NOT run 15-agent fan-outs.
- **Model tiering:** builders = **Sonnet** (you MUST pin `model: sonnet` — un-pinned spawns inherit the
  main-loop model). Reviews/verification/orchestration = **Opus**. **Fable is exhausted and cancelled**
  (no longer subsidized; not worth regular API rate). Weekly usage was at ~90% on 2026-07-14.
- **A concurrent autonomous process races `master`.** On a non-fast-forward push:
  `git fetch origin && git rebase origin/master && git push`. Its files are usually disjoint from ours.
- **After ANY restart: reconcile git/disk FIRST.** Agents reported as "stopped / no completion record"
  may have ALREADY landed their commit — verify against git before re-doing work.
- **isolation:worktree agents lose untracked files on cleanup.** Acceptance artifacts written inside a
  worktree's `.claude/state/` were destroyed when the worktree was pruned — write durable artifacts to a
  shared location.

## 6. Review methodology (operator-endorsed, use this)
**Diverse-lens panel + adversarial verify beats one deep pass.** Run several reviewers, each with a
DIFFERENT lens, then have an independent skeptic try to REFUTE every finding (default: refuted). Proven
here: the comprehension-reviewer caught a model-vs-code mismatch, the harness-reviewer caught a
false-positive rate, the end-user-advocate caught a runtime UX defect, and a 7-lens panel caught 7 real
splice bugs — no single reviewer catches all of those.

**Known gap:** every reviewer we have tests *correctness-against-spec*; **none attacks the SHAPE of the
architecture.** That's why the read-time-join shipped. An adversarial architecture-review lens is needed
(filed via `nl-issue.sh`).

## 7. Next actions
1. Reconcile the two fix worktrees (§3) → land the splice fixes → flip Task 7 → **18/18** → close P1.
2. Adversarially review the cockpit-v2 plan (small panel — see §5!), fold findings in.
3. Build cockpit-v2: projector → push triggers → backfill/auditor-demotion → GUI-reads-store-only → UI polish.
4. Push to `origin/master` frequently — the operator may switch machines at any time.
