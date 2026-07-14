# Cockpit v2 — push-projected, staleness-detecting plan store

Status: DRAFT (v2 — RESHAPED after a 5-lens adversarial plan review returned 5/5 FAIL)
Mode: build
rung: 3
lifecycle-schema: v2
ask-id: <id | none — no linked ask>
prd-ref: none

## The operator's requirement (2026-07-14)
Plan file = source of truth, kept as a living document. A deterministic mechanism pushes its state into
a JSON store as work happens (push, not pull). The GUI reads the store → fast, responsive, current,
spanning many plans. Detected problems must feed back automatically as **fixes to Neural Lace itself**.

## What the adversarial review killed (and what replaces it)
A 5-lens plan review (`docs/reviews/2026-07-14-cockpit-v2-plan-review.md`) failed the naive design 5/5.
The load-bearing corrections:

1. **"Push ⇒ cannot drift" is FALSE.** `plan-lifecycle.sh` is registered on `Edit|Write` (not
   `MultiEdit`), and **no git operation fires a PostToolUse hook at all** — cherry-pick (this harness's
   default orchestrator flow), pull, merge, checkout, `close-plan.sh`'s own `git mv`. This harness
   already learned this once (`docs/discoveries/2026-05-04-sed-status-flip-bypasses-plan-lifecycle.md`).
   ⇒ **We do not claim no-drift. We guarantee drift is always DETECTED, healed, and reported.**
2. **A missing store must never render as `0/0`.** Deleting the plan-file read made absence
   indistinguishable from "a real plan with no work done" — a confident lie. ⇒ **Explicit
   unknown/stale/damaged states; the GUI renders honesty, never a plausible zero.**
3. **`in_flight` came from EVENTS, not plan edits.** `task_started` fires on builder *dispatch*, which
   edits no plan file — a plan-edit-only trigger would show **zero in-flight while three builders run**.
   ⇒ **Two trigger sources: plan edits AND event emissions.**
4. **One machine-global JSON blob = lost updates.** Read-modify-write across 59 worktrees + a second
   machine; `tmp+rename` makes a *write* atomic, not an *update*. ⇒ **One projection FILE PER PLAN.**
5. **Unmerged worktree flips would render as "done".** ⇒ **Only the main checkout's plans project;**
   worktree edits never overwrite the operator's view.
6. **Fork storms.** ~160ms of spawns per edit vs the ≤50ms splice budget; a 246-plan sweep reincarnates
   the confirmed fork-per-file defect. ⇒ **Bounded work: one plan per push; staleness by `stat`, not
   re-parse; no `jq` on the write path.**
7. **Three divergent plan parsers already exist** (server/auditor accept numeric ids only; 176
   lettered-id tasks are invisible to them). ⇒ **ONE parser — the projector. Node never parses plan
   markdown again; the auditor re-projects by CALLING the projector.**
8. **Task descriptions would be REJECTED by the payload anti-noise denylist** (it scans every string for
   `.sh`, `posttooluse`, `plan-lifecycle` — which plan text legitimately contains). ⇒ **Explicit
   carve-out**, mirroring the precedent already set for the backlog pane.
9. **No in-repo mirror** — a per-second-mutating derived blob committed into a repo with 59 worktrees
   (and a public mirror) is a landmine. ⇒ **Projections live only in `~/.claude/state/`. Never committed.**

## Architecture (v2)
- **Truth:** the plan markdown, in the MAIN checkout.
- **Projection:** one file per plan — `~/.claude/state/plan-projections/<repo-key>__<plan-slug>.json` —
  written atomically (tmp+rename). Carries `schema_version`, `source_path`, `source_mtime`,
  `source_size`, `last_projected_ts`, `status`, `tasks[{id, description, done, in_flight,
  evidence_link, drift_badges}]`, `progress{done,in_flight,not_started,total}`.
- **Push (fast path, bounded):** the mechanisms that change a plan's state re-project **that one plan** —
  plan edit (`Edit|Write|MultiEdit`), `task_started` emission (in-flight), start-plan, close-plan.
- **Staleness detection (the honesty guarantee, cheap):** a reader compares the plan file's CURRENT
  mtime/size to the projection's recorded `source_mtime`/`source_size`. A mismatch = the projection is
  STALE (a git op or unhooked write happened). This is a `stat`, not a parse — O(1) per plan. Stale ⇒
  re-project that one plan on the spot (cheap) and **report the drift**. **Drift becomes impossible to
  hide, even though it is impossible to prevent.**
- **Honest states:** `fresh` · `stale-healed` · `unknown` (never projected) · `damaged` (unparseable /
  schema-skew). The GUI renders each distinctly. **A missing projection NEVER renders as 0/0.**
- **Auditor = safety net + the auto-healing loop** (below). Never a second parser, never a second writer.

## Tasks

- [ ] 1. [serial] **The projector (the ONE parser) + projection schema.** New
  `adapters/claude-code/scripts/plan-project.sh <plan-file>` — parse ONE plan, write ONE projection file
  atomically. It is the **only** plan-markdown parser in the system. Must handle what the existing three
  divergent parsers do not: **lettered task ids** (176 exist today), continuation lines, the `[serial]`
  prefix, the `— Verification: X` suffix, and **correct JSON escaping** (a description containing a `"`
  must not corrupt the store). No `jq` on the write path (harness convention); bounded to one plan.
  Records `source_mtime`/`source_size` for staleness detection. `--self-test` covering: numeric+lettered
  ids, quotes/backslashes/newlines in descriptions, an empty plan, a malformed plan (→ `damaged`, never
  a silent zero) — Verification: mechanical
- [ ] 2. [serial] **Push triggers — BOTH sources.** (a) plan-edit: `plan-lifecycle.sh` on
  `Edit|Write|**MultiEdit**` (the missing matcher is a real hole — fix it) → project that plan; (b)
  **event: `task_started` emission → re-project that plan so `in_flight` is live** (without this the
  cockpit shows zero in-flight while builders run — the review's #1 finding); (c) start-plan (create),
  close-plan (terminal/prune). Subshelled + non-fatal (constraint 5) **AND time-boxed** (`|| true` bounds
  errors, not runtime — add an explicit timeout). Only the MAIN checkout projects; a worktree edit must
  never overwrite the operator's view — Verification: full
- [ ] 3. [serial] **Staleness detection + honest states.** The read path compares live plan
  mtime/size to the projection's recorded values. Mismatch ⇒ stale ⇒ re-project that one plan + report.
  Implement the four states (`fresh`/`stale-healed`/`unknown`/`damaged`) end to end. **Acceptance: a
  `git checkout` of a plan (which fires NO hook) must be DETECTED, healed, and reported — not silently
  wrong, and not silently right either** — Verification: full
- [ ] 4. [serial] **The auto-healing feedback loop (operator directive — SILENT HEALING IS FORBIDDEN).**
  A divergence means *the push mechanism is broken*: some write path mutated a plan without triggering
  the projector. Healing the data while saying nothing fixes the symptom forever and never the cause.
  Every detected divergence does four things: (1) **HEAL** — re-project so the GUI is never wrong for
  long; (2) **CLASSIFY THE CAUSE** — not "drift happened" but *which write path bypassed the projector*:
  `git-checkout|git-pull|git-merge|cherry-pick|multiedit|external-editor|script-write|hook-not-fired|
  other-machine|unknown` (from plan mtime vs `last_projected_ts`, git reflog, whether the hook's marker
  fired); an unclassifiable drift is reported as `unknown`, never swallowed; (3) **AUTO-FILE THE FIX** —
  emit a cause-classified defect via `nl-issue.sh` into the machine-wide improvement ledger (→ weekly
  triage → build-ready backlog row): **the system's own detected divergence becomes a queued fix to
  Neural Lace itself**; (4) **ESCALATE ON RECURRENCE** — the same cause-class ≥3 times is a real hole in
  the push mechanism: auto-promote to a build-ready backlog row with evidence. Dedup so one recurring
  cause files one escalating item. Expose `heals_this_cycle` in diagnostics so a rising heal rate is
  visible as a mechanism regression — Verification: full
- [ ] 5. [serial] **GUI reads the store only.** Repoint `server.js` at the projections; **DELETE
  `countPlanTasks`** and every request-time plan-markdown parse (node must never parse a plan again).
  Preserve `drift_badges` (currently assembled per-task from the auditor — the naive schema dropped
  them). Render the honest states from task 3. Backfill all existing plans once (batched, NOT
  fork-per-plan). Prune projections for archived/renamed/deleted plans — Verification: full
- [ ] 6. [serial] **Payload contract for descriptions.** `description` must be added to
  `DETAIL_ALLOWED_KEYS`, and plan-derived description text must be **exempted from
  `GATE_HOOK_DENYLIST_PATTERNS`** — the anti-noise law is scoped to the ask-tree *narrative*, not to plan
  *content* (plan text legitimately says "plan-lifecycle.sh"). Precedent: the backlog pane already carries
  exactly this carve-out. Without this, task descriptions are rejected outright — Verification: full
- [ ] 7. [serial] **UI polish (operator items).** (a) panes RESIZABLE + each independently SCROLLABLE
  (must not reintroduce the shipped clipping bug where panes inherited `overflow:hidden` and flex-shrink
  starved the To-Do pane at >1200px); (b) backlog rows compact/collapsed by default, EXPANDABLE; (c) task
  list shows each task's DESCRIPTION (from the projection) and DROPS the repeated per-row plan-path link —
  the single "View live plan doc" button covers it; (d) REMOVE the Artifacts list. [operator's item 5 —
  their message was cut off; fold in when supplied] — Verification: full

## Acceptance
1. Flip a checkbox → projection updates in the same action; GUI reflects it with no plan-markdown read.
2. **Dispatch 3 builders → the cockpit shows 3 in-flight** (the regression the review caught).
3. **`git checkout` a plan behind the hook's back → drift is DETECTED, healed, cause-classified, and an
   nl-issue is auto-filed.** Do it 3× → it auto-escalates to a build-ready backlog row.
4. **Delete/corrupt a projection → the GUI shows `unknown`/`damaged`, never `0/0`.**
5. A worktree's unmerged checkbox flip does NOT render as "done" in the cockpit.
6. `grep` proves no request path parses plan markdown.
7. Long/quoted/multiline descriptions render safely and keep the list scannable.
8. Per-edit projector cost stays within the splice budget; the backfill does not fork-per-plan.
