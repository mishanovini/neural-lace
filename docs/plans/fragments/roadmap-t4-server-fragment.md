# Fragment: cockpit-roadmap-redesign Task 4 — server wiring for server.js (task 1 owns the file)

Task 4 (branch `build/roadmap-t4`) ships the Inbox view's server surface as
a NEW file (`server/inbox-routes.js`) without directly editing `server.js`
(task 1) — same discipline task 3/5's own server fragments established
(`roadmap-t3-server-fragment.md`, `roadmap-t5-server-fragment.md`). This
fragment carries the exact edit the orchestrator applies to `server.js` at
merge, plus the seams to re-verify.

## 1. server/server.js — the ONE mount line

Add near the existing `requestsRoutes`/`roadmapRoutes` requires:

```js
// cockpit-roadmap-redesign Task 4 — Inbox view routes (GET /api/inbox,
// POST /api/inbox/dismiss, GET /inbox.js). A separate module, same
// discipline as roadmap-routes.js/requests-routes.js; handle() returns
// true when it consumed the request.
const inboxRoutes = require('./inbox-routes.js');
```

Add alongside the existing `roadmapRoutes.handle(req, res)` /
`requestsRoutes.handle(req, res)` lines inside the
`http.createServer((req, res) => { ... })` handler body (order among the
three doesn't matter — their URL spaces are disjoint):

```js
  if (roadmapRoutes.handle(req, res)) return;
  if (requestsRoutes.handle(req, res)) return;
  if (inboxRoutes.handle(req, res)) return;
```

Without the mount line, the Inbox tab's view degrades to whatever static
markup index.html carries with no data behind it (a loud, honest
"Could not read what is waiting on you" pane-error + Retry once inbox.js's
own fetch fails against a 404 — never a silent partial merge, same law as
the task-3/5 fragments' mount lines).

## 2. No task-2 seam this time (unlike task 5)

Unlike requests-routes.js, inbox-routes.js's ONE write path
(`POST /api/inbox/dismiss`) delegates to `needs-you.sh resolve <id>` —
a verb that ALREADY EXISTS and is unchanged by this task (task 4 only added
the `--mechanical` flag to `add`, not `resolve`). No ask-registry.sh seam,
no reconciliation needed at merge.

## 3. Reused NEEDS-YOU-ledger-quarantine state — auditor.js (task 4 also owns this file)

`server/auditor.js`'s `runCycle()` now ALSO calls the new
`fileNeedsYouQuarantineDefects()` (A8 auto-defect filing) every cycle,
reading `NEEDS_YOU_STATE_DIR`'s `ledger.json` directly (a small,
deliberately duplicated reader — mirrors `inbox-routes.js`'s own identical
reader per this codebase's established "small duplicated reader"
convention, see auditor.js's file-header "WHY THE READERS BELOW ARE
DUPLICATED"). Both files are owned and committed together by task 4 in the
SAME branch (`build/roadmap-t4`) — no fragment needed for this seam since
there is no concurrent task racing on auditor.js.

## 4. Integration points to re-verify at merge

- `curl http://127.0.0.1:7733/api/inbox` → `ok:true`, `answerable[]` +
  `quarantined[]` arrays; a well-formed §3 decision item's `title`/
  `context`/`options`/`my_pick`/`reply_with` all parse; a lint-flagged
  decision lands in `quarantined`, excluded from `answerable`.
- `curl http://127.0.0.1:7733/inbox.js` → HTTP 200, `text/javascript`.
- `curl -X POST http://127.0.0.1:7733/api/inbox/dismiss -d '{"id":"<real NY- id>"}'`
  → `ok:true` once the real `needs-you.sh` CLI resolves it; the item then
  disappears from the NEXT `/api/inbox` fetch.
- `node neural-lace/workstreams-ui/server/inbox-routes.selftest.js` → rc 0.
- `node neural-lace/workstreams-ui/server/auditor.js --self-test` → rc 0
  (Scenario 9: the quarantine auto-defect files exactly once per item,
  recurrence-escalates at 3 distinct ids; Scenario 10: title-fold parity).
- `node neural-lace/workstreams-ui/web/cockpit.selftest.js` → rc 0 (T4-* block).

## 5. Known pre-existing defect discovered adjacent to this task (NOT fixed here — flagged for the shell-fragment application step)

While auditing `web/index.html`'s existing script-tag wiring (to place
task 4's own `/inbox.js` line correctly), the PREVIOUSLY-APPLIED task-5
splice (commit `40414d0`) was found to have landed
`<script src="/requests.js"></script>` INSIDE an HTML comment block (the
"TAB 1 — Roadmap" doc-comment near the top of the file, between its
opening `<!--` and closing `-->`) rather than at the bottom of the file
next to the other script tags, per `roadmap-t5-shell-fragment.md`'s own
explicit instructions. A commented-out `<script>` tag never executes — the
Requests ledger view's client module (`requests.js`) is therefore NOT
currently loaded by the live page at all, and the entire Task-5 Requests
ledger feature is inert in production despite its server route, self-tests,
and `cockpit.selftest.js` T5 suite all being green (none of those exercise
the ACTUAL served `index.html`'s script tags at the DOM level). See
`docs/plans/fragments/roadmap-t4-shell-fragment.md` §2 for the corrective
diff (moves the misplaced line to the correct location) bundled alongside
this task's own new `/inbox.js` line, since whoever applies fragments to
`index.html` is editing that file anyway. An `nl-issue.sh` note has also
been filed for the harness-level gap (a splice landed content in the wrong
location with nothing catching it).
