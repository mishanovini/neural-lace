# workstreams-ui

<!-- last-verified: 2026-07-07 (doctor-checked) -->

The Workstreams cockpit — a localhost, READ-ONLY operator dashboard answering
the NL Observability Program's six operator questions (design sketch:
`docs/reviews/2026-07-04-observability-design-sketch.md`; binding spec:
`docs/plans/nl-observability-program-2026-08-specs-o.md` §O.4). It is a THIN
VIEW over the derivation lib (`adapters/claude-code/hooks/lib/
observability-derive.sh`, contract C4) via the `nl` CLI (contract C5) —
DERIVE, DON'T MAINTAIN (law 1). It NEVER renders the legacy event-sourced
tree-state as truth and ships NO write affordances: this app cannot spawn,
steer, or answer for you. Answering "what needs me" happens in your
sessions/chat; this cockpit only tells you WHAT needs an answer and WHERE.

This replaces the pre-O.4 three-pane tree/accordion GUI (retired — see
`attic/README.md`), whose event-sourced `tree-state.json` truth model
repeatedly drifted from reality (WORKSTREAMS-UI-PURPOSE-AUDIT-01, operator
verdict "failed completely"; NL-FINDING-024).

## The six questions (+ backlog health)

| # | Question | Pane | Oracle |
|---|---|---|---|
| 1 | What's running | session board | `nl status` / `od_sessions` |
| 2 | What needs me | needs-me list | `nl needs-me` / `od_needs_me` |
| 3 | What happened since I last looked | diff-since-last-look | `nl shipped` / `od_shipped_since` |
| 4 | Is the harness working | health strip | `nl status`'s doctor header / `od_harness_health` |
| 5 | What's it costing | costs strip | `nl costs` / `od_costs` |
| 6 | Why did X happen (on demand) | why-drawer | `nl why <session>` / `od_why` |
| — | Backlog health | backlog strip | `nl backlog` / `od_backlog_health` |

Every pane's `derived_at` timestamp, `rc`, and `stderr_tail` are carried
straight from the CLI invocation the server made (`server/derive-cache.js`)
— a failed derivation renders a named ERROR state with the exact failing
command line, never a blank pane (see the acceptance scenarios below).

## Ask-rooted workstreams API (ask-rooted-workstreams-p1, Task 11)

The read surface for the ask-tree landing page (Task 13 builds the UI over
this; see `docs/plans/ask-rooted-workstreams-p1.md`). Every payload here is
validated against `server/payload-schema.js`'s ALLOWLIST before it reaches
the wire — a validation failure degrades to `{ok:false, diagnostics:[...]}`
at HTTP 500, never a leaking payload. Two laws are mechanically enforced on
every field: **no gate/hook identifier ever appears** (anti-noise law) and
**every href/path is absolute**, except the `plan_doc: {project, path}`
shape, which is a resolver argument for the EXISTING `/api/doc` +
`/api/doc/open` handlers (ux-review amendment 6: "no new link handling"),
not a rendered href.

| Endpoint | Method | Purpose |
|---|---|---|
| `/api/asks` | GET | Landing payload: `groups` (project → ask cards, filtered by `?status=`, default `active`) + `completed` (done/dismissed/merged asks, always present, independent of the filter, for the UI's collapsed group). |
| `/api/ask/<id>` | GET | Full detail: chronological `narrative`, per-plan `plan_rows` (per-task done/in-flight/not-started rows crossed against the real plan file's checkboxes), `waiting_items` (a real §3 context block, or the never-terminal defect form when the underlying NEEDS-YOU.md entry is missing/thin), `artifacts` (merge SHAs), `sessions` (dispatch lineage + heartbeat-classified state). |
| `/api/ask/<id>/lifecycle` | POST | The operator-override exit path (constraint 7): `{"action":"done"\|"dismiss"\|"reopen"}` or `{"action":"merge","into":"<target-ask-id>"}`. Delegates to the UNCHANGED `ask-registry.sh set-status`/`merge` CLI (Task 8) — never writes the registry file directly. |

Ask card shape (`/api/asks`):

```json
{
  "ask_id": "ask-20260710-workstreams-rebuild",
  "summary": "Rebuild the workstreams view",
  "project": "neural-lace",
  "repo": "C:\\Users\\...\\neural-lace",
  "status": "active",
  "activity_ts": "2026-07-10T12:00:00Z",
  "plan_progress": { "done": 8, "in_flight": 1, "not_started": 9, "total": 18 },
  "waiting_count": 1,
  "drift_badges": [],
  "narrative_excerpt": "task 8 verified done"
}
```

`drift_badges` is always `[]` until Task 12 (the background auditor) lands —
the field ships now so the schema/UI contract doesn't need a later
migration. `waiting_count` counts only needs-you.sh entries currently OPEN
under "Awaiting your decision" (best-effort: if NEEDS-YOU.md itself can't be
read, every referencing event counts, so a real waiting item is never
silently hidden by a parse gap).

Waiting-item shapes (`/api/ask/<id>`'s `waiting_items[]`) — exactly one of:

```json
{ "needs_you_id": "NY-...", "defect": false, "title": "...", "body": "...", "links": ["https://..."], "session_id": "sess-...", "added": "2026-07-10" }
```
```json
{ "needs_you_id": "NY-...", "defect": true, "message": "context missing — session violated §3", "raw_link": "C:\\...\\NEEDS-YOU.md", "session_id": "sess-..." }
```

The defect form is NEVER terminal: it always carries the violation notice,
an absolute link to the raw NEEDS-YOU.md file, and the source session id
(the UI, Task 13, adds the copy affordance + resume microcopy).

## Ask-tree landing (ask-rooted-workstreams-p1, Task 13)

The PRIMARY view when you open `/` (User-facing Outcome: "the operator can
cold-start ANY active ask ... in under 60 seconds"). Built by `web/asks.js`
over the Task 11 read surface above. The six-question cockpit is demoted to
a **Harness Health** tab (Task 16 — see below); it is never part of the
landing DOM.

- **Project sections** (collapsible, expanded by default) group ask cards
  by `config/projects.js` project, newest activity first.
- **Ask cards** are shallow-first: summary, a one-click "Verbatim" reveal
  (currently shows the capture reference — transcript path + prompt offset —
  since no server read surface resolves that pointer into the original
  prompt text yet; a real follow-up, not routed around), a progress
  narrative excerpt, an aggregate plan-progress bar (summed across every
  linked plan when `plan_slugs[]` has more than one entry — MULTI-PLAN
  CARDS, review round 2), a waiting-on-you count naming its destination,
  and drift-badge slots (`drift_badges` renders `[]` until Task 12's
  auditor lands; the click-through affordance is built now).
- **Plan drill-down** is an explicit control beside the bar (never the bar
  alone — review round 1) — a native `<details>`/`<summary>` (chevron +
  "N tasks") that lazily fetches `GET /api/ask/<id>` on first expand and
  renders per-plan blocks (one live-doc link per plan via the EXISTING
  `/api/doc` viewer modal, per-task done/in-flight/not-started rows with
  evidence links), the ask's waiting items (a real §3 block or the
  never-terminal defect form), and its sessions with spawn-lineage edges
  where a Task 3 dispatch-provenance marker resolves one (flat grouping
  otherwise — no session is ever dropped for lacking provenance).
- **Lifecycle affordances** — Done / Dismiss / Merge-into (operator exit
  path, constraint 7) call `POST /api/ask/<id>/lifecycle`; every action
  shows inline success feedback with an ~8s Undo (`reopen`) before the ask
  moves to the collapsed **Completed** group (header: `Completed (N ·
  newest <age>)`, hidden entirely when empty — never an expanded empty
  shell).
- Every session id anywhere on this surface carries a copy button with the
  microcopy `copy session id — resume with \`claude --resume <id>\``.
- **Desktop-app deep-link spike (Task 13, timeboxed):** a `claude://`
  protocol IS registered on this machine (`HKEY_CLASSES_ROOT\claude` →
  the Claude Desktop app), but its accepted URL grammar for resuming a
  specific CLI session by id is undocumented and unverified — firing it
  live to probe behavior was judged an unnecessary side effect on the
  operator's desktop for a non-committal spike. The UI therefore ships
  ONLY the guaranteed copy-button fallback, per the plan ("guaranteed
  fallback ... is IN"); a verified deep link is a future increment, not
  a false affordance shipped today.

## Tab shell + Harness Health demotion (ask-rooted-workstreams-p1, Task 16)

`web/index.html` is a two-tab shell: **Asks** (the landing tab, default) and
**Harness Health**. The six wave-O panes + the reconciler badge + the
interrupt-priority strip + the why-drawer + a new **Diagnostics** section
(auditor cadence/cycle stats, healed-backfill/backfill-error counts, the
waiting-on-you count-reconciliation result, and the drift-badge count —
`GET /api/diagnostics/drift`) all moved VERBATIM into
`<template id="harnessHealthTemplate">`. A native `<template>`'s content is
inert — not parsed into the live document, not in the accessibility tree,
not matched by `document.getElementById` — until `app.js`'s
`initHarnessHealthTab()` clones it into `#tabHealthPanel` the first time the
operator opens that tab, so the landing DOM carries ZERO pane-family
identifiers (anti-noise law, mechanically checked in `cockpit.selftest.js`).
No Team tab ships in P1 (review round 1 — no empty shell surfaces): there is
no nav entry and no markup for it anywhere.

A pre-existing DOM-id collision was fixed in passing: the six-pane cockpit's
own "Backlog health" strip previously shared `id="backlogBody"` with the
Task 15 sidebar's Backlog pane (`document.getElementById` always resolves
the first match in document order, so the two features were silently
racing for the same node). The six-pane strip now has its own id
(`backlogHealthBody`).

## Layout

| Path | Contents |
|---|---|
| `server/server.js` | Node HTTP server: static asset serving, the six `/api/pane/*` endpoints, `/api/reconciler`, `/api/diagnostics/drift`, `/api/refresh`, SSE push, the KEPT docs browser (`/api/docs`, `/api/doc`, `/api/doc/open`), and the ask-rooted-workstreams read + lifecycle-write surface (`/api/asks`, `/api/ask/<id>`, `/api/ask/<id>/lifecycle` — see above). No legacy write endpoint — `POST /api/event` is RETIRED. |
| `server/derive-cache.js` | The server-side derived-JSON cache: shells `nl <sub> --json` (NL_BIN overridable), batch-refreshes every 30s, keeps last-known-good data alongside the latest rc/stderr for honest error rendering. |
| `server/reconciler.js` | The divergence reconciler (specs-o §O.4 deliverable 3): compares any REMAINING legacy tree-state session/branch claims against derived truth and flags mismatches — comparison-only, never a data source for a pane. |
| `server/payload-schema.js` | The ask-tree payload allowlist (Task 11): anti-noise + absolute-href enforcement, at serve time and in the self-test. |
| `web/` | `index.html` (the tab shell — Asks landing + Harness Health template, see above), `app.js` (the ask-tree's shared docs-viewer wiring, global tab router, and the six-pane/reconciler/diagnostics render logic — unchanged from the six-question-cockpit build, just lazily bound), `app.css`, `web/asks.js`/`web/todo.js`/`web/backlog.js` (the ask-tree landing + sidebar panes). ONE link-resolver component (`resolveLink`) backs every Harness Health pane's links; `asks.js`/`todo.js`/`backlog.js` are fully independent modules sharing only the docs-viewer modal DOM with `app.js`. |
| `state/` | The (mostly legacy) event-sourced state library. Still used ONLY by `reconciler.js`'s comparison read while any tree-state consumer remains elsewhere in the harness; no longer the cockpit's data source. |
| `scripts/` | Launcher/autostart PowerShell scripts. The Node state-population scripts here (`add-pending-items.js`, `backfill-from-sessions.js`, etc.) targeted the retired write path and are no longer relevant to this app's day-to-day operation. |
| `config/` | Runtime configuration (topology/project-root mapping) — still used by the docs browser and the ask-tree's project grouping. |
| `attic/` | Retired pre-O.4 test files, kept per salvage-before-reset. See `attic/README.md`. |

## Running it

```bash
cd neural-lace/workstreams-ui
node server/server.js          # starts on http://127.0.0.1:7733 by default (CTREE_PORT overrides)
                                # NL_BIN overrides the `nl` CLI path (tests point this at a fixture stub)
```

Or, on Windows, the one-click path:

```powershell
neural-lace/workstreams-ui/scripts/launch-gui.ps1   # starts the server (if not already up) and opens the browser
```

`scripts/register-autostart.ps1` registers a scheduled task that starts the
server (no browser) at logon (per the runbook's wrapper-cmd registration
pattern — see `docs/runbooks/session-resumer.md` §Registration pattern).

## Self-tests

```bash
node server/server.selftest.js   # server wiring: pane endpoints, error-state rendering, reconciler
node web/cockpit.selftest.js     # DOM-free structural self-test: six-question layout + ask-tree landing
```

## Where the enforcement side lives

The legacy Claude Code hook wiring that wrote to and gated the OLD
event-sourced tree (`workstreams-emit.sh`, `workstreams-state-gate.sh`,
`workstreams-stop-writer.sh`) is documented in `adapters/claude-code/
manifest.json` and `adapters/claude-code/doctrine/workstreams-state.md`.
NL Observability Program Wave O, task O.4 retires the two gates whose ONLY
protected consumer was this UI's old tree read (`workstreams-state-gate.sh`,
`workstreams-stop-gate.sh` — the latter already attic'd at D.5) once this
cockpit stops reading `tree-state.json` as truth — see the retirement
fragments under `adapters/claude-code/tests/fixtures/wave-o/O.4/` for the
exact `template-wiring.md` / `manifest-amendments.md` diffs the orchestrator
applies. `workstreams-emit.sh`'s spawn/stop paths are KEPT as ledger
emitters (O.1) — the signal ledger, not the tree, is the spine going
forward.
