# Fragment: cockpit-roadmap-redesign Task 5 — shell wiring for web/index.html

Task 5 (branch `build/roadmap-t5`) ships the Requests ledger view
(`web/requests.js`) as a wholly new, self-mounting module — it inserts its
own DOM subtree into the ALREADY-EXISTING `#tabRequestsPanel` container at
runtime (no static markup needed for the ledger itself: toolbar, body, rows,
timeline, and age-groups are all built via `document.createElement`). The
builder's dispatch explicitly excluded direct edits to `web/index.html` (a
shared shell file), so this is the ONE line that ships as a fragment instead
of a direct commit — mirroring task 3's `roadmap-t3-server-fragment.md` §1
precedent exactly. (The server.js mount line + the task-2 ask-registry.sh
seams are a SEPARATE fragment: `roadmap-t5-server-fragment.md`.)

## web/index.html — the ONE script-tag line

Add, immediately after the existing `roadmap.js` script tag (so it loads
AFTER `app.js` — `requests.js` reads `window.WorkstreamsShell`, which app.js
defines — same load-order requirement `roadmap.js` already documents):

```html
  <script src="/asks.js"></script>
  <script src="/todo.js"></script>
  <script src="/backlog.js"></script>
  <script src="/app.js"></script>
  <!-- roadmap.js loads AFTER app.js: it registers into the shell API
       (window.WorkstreamsShell) app.js defines. Served by
       server/roadmap-routes.js (the one-line server.js mount). -->
  <script src="/roadmap.js"></script>
  <!-- requests.js loads AFTER app.js/roadmap.js for the same reason: it
       registers 'requests' into window.WorkstreamsShell, REPLACING app.js's
       interim placeholder adapter (last registerView() call for a given
       name wins — see app.js's registerView). Served by
       server/requests-routes.js (the one-line server.js mount — see
       roadmap-t5-server-fragment.md). -->
  <script src="/requests.js"></script>
</body>
</html>
```

(i.e. one new line — `<script src="/requests.js"></script>` — inserted
right after the existing `<script src="/roadmap.js"></script>` tag, before
the closing `</body>`.)

Nothing else in `index.html` changes. `requests.js` mounts its own wrapper
(`#requestsLedgerSection`) as the FIRST child of the already-existing
`#tabRequestsPanel` (line ~69 of the current file) — the pre-existing
ask-tree (`#askTreeSection` + the sidebar) is left completely untouched
below it (a documented, scoped decision — see this task's build report:
consolidating/hiding the legacy ask-tree is out of this task's remit, filed
as a follow-up for task 8's UI-polish pass). Without this line, the
Requests tab degrades to exactly what task 3 shipped (the interim ask-tree
+ app.js's placeholder 'requests' adapter) — a loud, honest interim state,
never a silent partial merge.

## Integration points to re-verify at merge

- Browser: Requests tab shows the ledger above the legacy ask-tree;
  `#request/<id>` lands (switch + expand + scroll + highlight + focus +
  "← back"); a gone id renders the miss banner; the filter box narrows
  both the open list and the closed age-groups; a closed request's row
  reads "became → &lt;plan&gt;" and its "open on the Roadmap" button
  navigates to `#roadmap/<id>`.
- `node neural-lace/workstreams-ui/web/cockpit.selftest.js` → rc 0 (T5-* block).
