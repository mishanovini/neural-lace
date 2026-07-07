# workstreams-ui/attic

Retired workstreams-ui test files, kept (not deleted) per the harness's
salvage-before-reset discipline.

- `responsive.selftest.js.retired` — DOM-free structural self-test for the
  PRE-O.4 tree/accordion UI (filter chips, adjustable divider, detail modal
  over the event-sourced tree). Retired by NL Observability Program Wave O,
  task O.4 (specs-o §O.4): the UI it asserted against — the four-tier
  Project→Workstream→WorkItem→Sub-task tree, the filter bar, the write
  affordances — no longer exists. Superseded by
  `web/cockpit.selftest.js` (asserts the new six-question cockpit's
  structure instead).
- `regression.e2e.js.retired` — puppeteer headless-browser regression suite
  locking the pre-O.4 cockpit/drill/waiting design's DOM. Same retirement
  reason. A live-browser regression suite for the NEW cockpit is a
  reasonable future increment (not built here — O.4's own acceptance bar is
  the end-user-advocate's runtime scenario run, not a maintained e2e suite).

Both files still reference the OLD server (`node server/server.js` on the
OLD tree-state contract) and OLD DOM ids — do not run them against the
current `workstreams-ui/` without expecting every assertion to fail; that
failure would be correct, not a regression, since the surface they tested
was retired.
