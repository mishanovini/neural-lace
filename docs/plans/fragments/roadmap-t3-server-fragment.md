# Fragment: cockpit-roadmap-redesign Task 3 — server wiring for files owned by tasks 1/2

Task 3 (branch `build/roadmap-t3`) ships the navigation shell + Roadmap view without
directly editing any file tasks 1/2/7 own. This fragment carries the EXACT edits the
orchestrator applies to those files at merge, plus the two integration seams to
re-verify (the Wave-O contract-first precedent).

## 1. server/server.js — the ONE mount line (task 1 owns the file)

Add near the top of the module requires:

```js
// cockpit-roadmap-redesign Task 3 — Roadmap view routes (GET /api/roadmap,
// POST /api/roadmap/rank, POST /api/roadmap/title, GET /roadmap.js). A
// separate module so the roadmap surface and server.js could build in
// parallel; handle() returns true when it consumed the request.
const roadmapRoutes = require('./roadmap-routes.js');
```

Add as the FIRST line inside the `http.createServer((req, res) => { ... })` handler
body (before the static-file routes — roadmap-routes serves `/roadmap.js` itself):

```js
  if (roadmapRoutes.handle(req, res)) return;
```

Nothing else in server.js changes. `web/index.html` already loads `/roadmap.js`
after `app.js` — without the mount line the Roadmap tab renders its honest
pane-error state ("Could not derive the roadmap" + Retry), so an unmerged interim
state degrades loudly, never silently.

## 2. Task-1 seam — status derivation (server/derive-lib.js)

`server/roadmap-routes.js` marks its mechanical status derivation between
`STUB-STATUS-BEGIN` / `STUB-STATUS-END`. The pinned payload contract (six-value
enum, `status.{value,reason,reason_class,label,since}`, `roll_up` = one
`{count, exemplar}` entry PER attention class, `progress {done,total}|null`,
`completed_at`, `from_requests`) is documented in that file's header and pinned by
`server/roadmap-routes.selftest.js` (28 scenarios, real fixtures, real HTTP).

At merge, replace the stub internals with task 1's derive-lib exports (oracle-backed
complete, heartbeat-backed in-progress, stalled reasons + `status.unblock
{label, hash}` for the `#inbox/<id>` arrow). The renderer (`web/roadmap.js`) already
renders every stalled class, the unblock link, and `added_mid_build` — the stub
simply never emits stalled/added_mid_build, so task 1's data lights those paths up
without renderer changes. Re-run `node server/roadmap-routes.selftest.js` after the
swap; S4/S4d (unknown-on-input-failure, no default-guess) and S5 (no-signal renders
merged-unverified OUTSIDE complete) are the invariants that must survive.

## 3. Task-2 seams — ask-registry.sh verbs (task 2 owns the file)

`roadmap-routes.js` delegates writes to ask-registry.sh (one-writer discipline) with
these EXACT call shapes (pinned by selftest S11b/S12):

- Title edit: `ask-registry.sh set-title --ask-id <id> --title <text> --title-source operator --emitter operator-ui`
  → append `{record_type:"title_set", ask_id, title, title_source, ts, emitter}`.
  The roadmap fold already reads `title_set` (operator ALWAYS outranks auto,
  regardless of ts — A3) and `summary_updated` (auto slot). Until the verb exists,
  the endpoint returns a NAMED error (never a silent success, never a second title
  store) — the UI surfaces it in the aria-live feedback row.
- Rank: `ask-registry.sh set-rank --ask-id <id> --rank <n> --emitter operator-ui`
  → append `{record_type:"roadmap_rank", ask_id, rank, ts, emitter}` (last-wins per
  ask). INTERIM mechanism (works today): the endpoint materializes the full order
  into `<ask-registry-state-dir>/roadmap-rank-overlay.json` (a UI-state file, NOT
  the registry); registry `roadmap_rank` records take precedence per ask once the
  verb lands. Migration: once set-rank exists and records land, the overlay is
  dead weight and can be deleted — order reads registry-first by construction.

## 4. Integration points to re-verify at merge

- `curl http://127.0.0.1:7733/api/roadmap` → `ok:true`, items carry only the six
  enum values, roll-ups counted per class.
- `curl http://127.0.0.1:7733/roadmap.js` → HTTP 200, `text/javascript`.
- `node neural-lace/workstreams-ui/server/roadmap-routes.selftest.js` → rc 0.
- `node neural-lace/workstreams-ui/web/cockpit.selftest.js` → rc 0 (T3-* block).
- Browser: `#roadmap/<id>` / `#request/<id>` / `#inbox/<id>` land (switch + expand +
  scroll + highlight + focus + "← back"); a gone id renders the miss banner.
