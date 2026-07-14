# Cockpit v2 — push-materialized store (GUI reads the store, never the plan file)

Status: DRAFT
Mode: build
rung: 3
lifecycle-schema: v2
ask-id: <id | none — no linked ask>
prd-ref: none

## Why (operator directive, 2026-07-14)

> "The plan should always be considered the source of truth. But we need to make sure that plan
> file stays continuously updated as a living document. And the JSON store should simply be a
> consolidated overview of that data… as work gets done, the agent that checks off those
> checkboxes should always update the plan AND the JSON store (or a deterministic script does it
> automatically). This should be fully deterministic and always in PUSH form instead of pull so
> it's fully automated. The JSON store also has data and status from multiple plans. This
> architecture should allow the GUI to be very quick and responsive and always current because it
> only needs to reference the JSON store."

**What's built today (the gap):** the checkbox flip already PUSHES a `task_done` *event* into the
per-ask JSONL — but the GUI still **pulls** the task list + checkbox state from the plan markdown at
request time (`computePlanRows` → `countPlanTasks`, joined live with the events). So the store is
incomplete and the read path re-derives. This plan closes that: the store becomes a complete,
push-maintained projection; the GUI reads only the store.

**Architecture:** classic materialized read-model. Plan file = source of truth. A deterministic
projector, triggered by the SAME mechanism that edits the plan, writes the projection into a
consolidated multi-plan JSON store. GUI reads the store. The auditor drops to a safety-net backfill
(catch a missed push and re-project) — it is no longer on the read path. Because the projection is
pushed by the same deterministic action that mutates the plan, store and plan cannot drift.

## Tasks

- [ ] 1. [serial] **Store schema + projector.** New deterministic script
  `adapters/claude-code/scripts/plan-project.sh` — given a plan file, parse it and upsert that
  plan's projection into the consolidated store (`~/.claude/state/workstreams-store.json`, plus an
  in-repo mirror if the GUI needs it). Projection per plan: `{plan_slug, plan_doc, ask_id, status,
  tasks[{id, description, done, in_flight, evidence_link, updated_ts}], progress{done,in_flight,
  not_started,total}, last_projected_ts}`. `description` = the task's text from the plan (this is what
  makes the GUI's task list readable — operator item 3). `in_flight` is derived ONCE at projection
  time from the task_started/task_done events. Atomic write (tmp+rename). Idempotent. `--self-test`
  — Verification: mechanical
- [ ] 2. [serial] **Push triggers (the deterministic automation).** Call the projector from every
  mechanism that mutates a plan: the existing `plan-lifecycle.sh` PostToolUse splice on
  `docs/plans/*.md` (covers every checkbox flip + amendment), `start-plan.sh` (plan create), and
  `close-plan.sh` (plan close). Subshelled + `|| true` (constraint 5: never block the hook). This is
  the "push, not pull" core — a checkbox flip updates the plan AND the store in the same
  deterministic action — Verification: full
- [ ] 3. [serial] **Backfill + auditor demotion.** One-time backfill: project every existing plan into
  the store. Then repoint Task 12's auditor: it no longer feeds the read path — it becomes the
  SAFETY NET that periodically re-projects from the plan files, compares to the store, heals any
  divergence, and reports drift (a missed push = a bug to surface, not a silent correction) —
  Verification: full
- [ ] 4. [serial] **GUI reads the store only.** Repoint `server.js`'s `computePlanRows` /
  `aggregatePlanProgress` at the store; DELETE the request-time `countPlanTasks(planFile)` read. The
  `/api/asks` + `/api/ask/<id>` payloads are served from the store (fast, always current, spans all
  plans). Prove it: no plan-markdown read remains on any request path — Verification: full
- [ ] 5. [serial] **UI polish (operator items 1-4, + item 5 TBD).** (a) panes RESIZABLE and each
  independently SCROLLABLE; (b) backlog rows compact/collapsed by default, expandable — a tidy list,
  not a wall; (c) task list shows each task's DESCRIPTION (now in the store, task 1) and DROPS the
  repeated long plan-path link per row — the single "View live plan doc" button covers it; (d) REMOVE
  the Artifacts list (noise). [item 5: operator's message was cut off — fold in when supplied] —
  Verification: full

## Files to Modify/Create
- `adapters/claude-code/scripts/plan-project.sh` (new — the projector)
- `adapters/claude-code/hooks/plan-lifecycle.sh` (push trigger on plan edit)
- `adapters/claude-code/scripts/start-plan.sh`, `adapters/claude-code/scripts/close-plan.sh` (push on create/close)
- `neural-lace/workstreams-ui/server/server.js` (read the store; delete the plan-file read)
- `neural-lace/workstreams-ui/server/auditor.js` (demote to backfill/drift-reporter)
- `neural-lace/workstreams-ui/web/{app.css,asks.js,backlog.js,index.html}` (UI polish)

## Acceptance
1. Flip a checkbox in a plan → the store updates within the same action (no GUI refresh needed to
   re-derive); the GUI shows the new state on next load without reading the plan file.
2. `grep` proves no request path reads a plan `.md`.
3. The GUI's task list shows readable per-task descriptions; no repeated per-task plan link; no
   Artifacts section; panes resize + scroll; backlog rows collapse/expand.
4. Kill a push (simulate a missed hook) → the auditor's backfill detects the divergence, heals it,
   and REPORTS the drift (it must not hide a broken push).
