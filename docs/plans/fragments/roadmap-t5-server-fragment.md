# Fragment: cockpit-roadmap-redesign Task 5 — server wiring for files owned by tasks 1/2

Task 5 (branch `build/roadmap-t5`) ships the Requests ledger view's server
surface as a NEW file (`server/requests-routes.js`) without directly editing
`server.js` (task 1) or `ask-registry.sh` (task 2, concurrently in flight) —
same discipline task 3's `roadmap-t3-server-fragment.md` established. This
fragment carries the exact edits the orchestrator applies to those files at
merge, plus the seams to re-verify.

## 1. server/server.js — the ONE mount line (task 1 owns the file)

Add near the existing `roadmapRoutes` require:

```js
// cockpit-roadmap-redesign Task 5 — Requests ledger view routes
// (GET /api/requests, POST /api/requests/title, POST
// /api/requests/amend/detach, GET /requests.js). A separate module so the
// requests surface could build in parallel with tasks 1/2/3/7; handle()
// returns true when it consumed the request.
const requestsRoutes = require('./requests-routes.js');
```

Add alongside the existing `roadmapRoutes.handle(req, res)` line inside the
`http.createServer((req, res) => { ... })` handler body (order between the
two doesn't matter — their URL spaces are disjoint):

```js
  if (roadmapRoutes.handle(req, res)) return;
  if (requestsRoutes.handle(req, res)) return;
```

Without the mount line, the Requests tab's new ledger section renders its
honest pane-error state ("Could not load requests" + Retry) — an unmerged
interim state degrades loudly, never silently (same law as the task-3
fragment's roadmap mount line).

## 2. Task-2 seam — ask-registry.sh verbs (task 2 owns the file)

`requests-routes.js` delegates BOTH its writes to ask-registry.sh
(one-writer discipline), pinned by `server/requests-routes.selftest.js`
S8/S8b/S9/S9b:

- Title edit: reuses the EXACT verb roadmap-routes.js already pins (task-3
  fragment §3) — `ask-registry.sh set-title --ask-id <id> --title <text>
  --title-source operator --emitter operator-ui`. No new shape; both views
  write the same registry field via the same verb (A3 one-writer
  discipline — title is ONE field, edited from two views).
- Amendment detach (I6, NEW verb this task pins):
  `ask-registry.sh detach-amendment --ask-id <id> --event-ts <ts> --emitter
  operator-ui` → append `{record_type:"amendment_detached", ask_id, ts,
  detach_ref:<the candidate's own ts>, emitter}`. Until the verb exists, the
  endpoint returns a NAMED error (never a silent success) — the UI surfaces
  it in the timeline row's aria-live feedback.

The requests-routes.js reader also folds a forward-compatible
`{record_type:"amendment_candidate", ask_id, ts, verbatim_ref,
classification:""|"amendment"|"noise"}` shape for task 2's capture +
classification lane (I6 timeline anatomy renders a detachable entry the
moment such records appear — see requests-routes.js's own header for the
full documented STUB contract and the honest limitation it ships with:
NO real `amendment_candidate` records are produced by anything today, since
task 2's capture splice is itself still in flight). Reconcile at task-2
merge: if the landed shape differs from this pin (field names, an
`amendment_classified` record type instead of an inline `classification`
field, etc.), update `requests-routes.js`'s `foldRegistryForRequests()`
fold and re-run `node server/requests-routes.selftest.js` (S7/S7b/S7c pin
the fold's observable behavior, not its internal shape).

## 3. Integration points to re-verify at merge

- `curl http://127.0.0.1:7733/api/requests` → `ok:true`, items carry
  `state`, `closed_reason`, `became`, and an oldest-first `timeline[]`.
- `curl http://127.0.0.1:7733/requests.js` → HTTP 200, `text/javascript`.
- `node neural-lace/workstreams-ui/server/requests-routes.selftest.js` → rc 0.
- `node neural-lace/workstreams-ui/web/cockpit.selftest.js` → rc 0 (T5-* block).
