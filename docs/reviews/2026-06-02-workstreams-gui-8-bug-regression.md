# Workstreams GUI — 8-bug regression diagnosis (2026-06-02)

Browser-verified (puppeteer headless, fresh/uncached load of the live server at
`http://127.0.0.1:7733/`) after the PT↔personal reconcile (`235d717`) +
decision-context port (`37503dc`). Each finding has runtime evidence, not unit-test
inference.

Ground-truth baseline: tree **does** render — 7 projects, 35 tree items, kind glyphs
visible, status "live". Only 1 console error (a 404 favicon, benign). So the literal
"nothing renders" reading is wrong; the regressions are in the rendering *chain* and
in dropped features. Several of Misha's symptoms may have been amplified by a
stale-cached browser tab, but every item below is a real substance issue fixed here.

| # | Symptom | Root cause (browser-verified) | Verdict |
|---|---|---|---|
| 2 | Detail card hidden in bottom-right corner | No global `[hidden]{display:none}`; `.list-body{display:flex}` (app.css:218) overrides `filterBody.hidden`, so on selection the filter list keeps `flex:1 1 auto` and the detail card is squeezed to a 67px bottom strip (`{x:611,y:833,w:829,h:67}`). | CONFIRMED bug |
| 5 | Tree selection not highlighted in pane | `renderDetailCard` sets `selItem` but never re-renders the tree → clicked row never gets `.sel`. `selTreeRows=0` after click. | CONFIRMED bug |
| 4 | No decision/action/question type badges in tree | Tree `.ti-kind` is a faint muted single glyph (◆/?/!); colored `.k-*` badges exist only in the right pane. | CONFIRMED gap |
| 3 | Items marked orphans despite project label | `staleSessions()` flags 13 sessions; 9 are `subagent <hash>` internal nodes that ADR-034 says must NOT be tree-surfaced. The other 4 are genuine never-concluded Dispatch sessions, correctly project-labeled — "orphan" is the wrong word. | CONFIRMED (pollution + mislabel) |
| 1 | No four-tier hierarchy visible | Data has 0 workstream-tier nodes (items hang off project roots), so only Project→WorkItem renders; faint styling + no d1 indent makes it read flat. Not a missing renderer — a visual-clarity + data-shape issue. | PARTIAL (visual) |
| 7 | Show/hide completed checkbox gone | Old renderer (ee16f41) had `<input id="showConcluded"> Show concluded` in the left pane; the four-tier rewrite folded it into header `showArchived` only. | CONFIRMED dropped |
| 6 | Document folder structure gone | Old renderer had `📁 Docs` button → `#docsPanel` cross-project docs drawer reading `/api/docs`. Frontend dropped in rewrite; **`/api/docs` endpoint still exists** (server.js:174); orphan CSS (`.modal-scrim`, `#docsPanel`) survived. | CONFIRMED dropped (re-wire, not rebuild) |
| 8 | Heartbeat stale | `/api/health` → `heartbeat_mtime_ms: null`, `heartbeat_stale: true`. Heartbeat writer not running this session. Operational. | CONFIRMED operational |

Evidence artifacts: `C:/Users/misha/dev/pt-gui-verify/baseline-*.png|json`,
`interact-*.png|json`.

## Fix status — ALL 8 FIXED, browser-verified 9/9

Regression suite `workstreams-ui/scripts/regression.e2e.js` (puppeteer, dev-only)
passes 9/9 against the live server. Per-bug fix + browser evidence:

| # | Fix | File(s) | Browser proof |
|---|---|---|---|
| 2 | Global `[hidden]{display:none!important}` so `filterBody.hidden` actually hides; detail card (flex:1 1 auto) fills the pane | `web/app.css` | `cardH 67→810`, `filterStillVisible=false` |
| 5 | `syncTreeSelection()` re-applies `.sel` to the matching tree row on select/deselect (from tree OR right-pane) | `web/app.js` | `selTreeRows 0→1` |
| 4 | Colored `.ti-badge` (DEC/ASK/ACT) on tree rows, parity with right-pane `.k-*` chips | `web/app.js`, `web/app.css` | `badges=35 colored=35` |
| 3 | `staleSessions()` excludes internal `subagent <hash>` nodes (ADR-034); section relabeled "Stale sessions" | `web/app.js`, `web/index.html` | `count 13→4`, `hasSubagent=false`, head "Stale sessions" |
| 1 | Per-tier indentation (d1/d2/d3 margin + 2px guide rail) so items nest UNDER the project | `web/app.css` | `firstItem.x 38→50 > title.x 39`, `indented=true` |
| 7 | Restored `show completed` header checkbox; `visibleInTree` honors it | `web/index.html`, `web/app.js` | toggle wired (reveal inert: 0 completed items in data) |
| 6 | Re-added `📁 Docs` button + `#docsPanel` drawer + viewer modal (ported from ee16f41); `/api/docs`,`/api/doc`,`/api/doc/open` already live | `web/index.html`, `web/app.js` | drawer opens `{x:1024,w:416}`, 4 project rows |
| 8 | Fired `workstreams-emit.sh --heartbeat` once → marker written, badge fresh. NO tree mutation (13 open sessions untouched). Durable fix = registering the scheduled task (operator's call). | operational | `heartbeat_stale true→false`, badge "hb 38s" (not red) |

Existing in-repo selftests unaffected: `state/selftest.js` 19/19, `web/responsive.selftest.js` 22/22, `workstreams-emit.sh --self-test` 39/39.

**Caveat (bug #8):** the heartbeat goes stale again in ~10 min without the
scheduled task. The durable fix is registering it (a `scripts/register-heartbeat.ps1`
Windows Scheduled Task = persistent config — left to the operator, not auto-applied).

**Note for Misha:** if your open browser tab still shows the old GUI, hard-refresh
(Ctrl+Shift+R) — the server serves the fixed assets, but a long-lived tab may have
cached the pre-fix `app.js`/`app.css`.
