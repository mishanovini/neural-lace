---
title: Workstreams UI shows empty despite healthy data pipeline
date: 2026-06-03
type: failure-mode
status: decided
auto_applied: true
originating_context: Office_PC session — Misha asked "why is there still no data in the Workstreams UI?"
decision_needed: n/a — root-caused; no-cache fix auto-applied (reversible), reducer fix deferred to a plan
predicted_downstream:
  - neural-lace/workstreams-ui/server/server.js (no-cache headers — fixed this session)
  - neural-lace/workstreams-ui/state/state.js + hooks/workstreams-emit.sh (reducer upsert — follow-up)
---

## What was discovered

The Workstreams GUI renders empty even though the data pipeline is healthy. Diagnostic-first evidence (not inference):

- State file `neural-lace/workstreams-ui/state/tree-state.json`: **187 nodes / 372 events**, updated 95s before inspection (emit hook IS writing).
- `/api/health`: server reads the **correct, fresh** state file (`state_age_seconds: 95`).
- `/api/state`: **serves all 187 nodes** (returns a `nodes` array — an earlier diagnosis "(none)" was a parse-shape mistake, since corrected).
- Served `app.js` md5 == disk md5 (server serves the **current** post-`ebc0453` frontend, read fresh-from-disk per request).

So data presence + service are NOT the problem. Two real root causes, both browser/render-side:

### Cause 1 (PROVEN): static server sends no cache headers
`serveStatic()` in `server/server.js` sets only `Content-Type` — **no `Cache-Control` / `ETag` / `Last-Modified`** on `/app.js`. Browsers heuristically cache uncontrolled assets, so a browser opened before the Jun-3 `ebc0453` tier-rendering fix keeps running the **stale broken-rendering `app.js`**. `curl -I /app.js` confirmed: only `Content-Type` returned.

### Cause 2 (PROVEN): emit/reducer appends duplicate nodes instead of upserting
The state file carries **28 duplicate "neural-lace" + 34 duplicate "misha" nodes** — the emit hook / `state.js` reducer creates a new person/session node per session instead of upserting by a stable `node_id`. `ebc0453` fixed only `web/app.js` (frontend), not this data model. Result: even with fresh frontend code, the tree is polluted.

### Contributing factor: filter tab
GUI tabs are `awaiting-me / in-flight / blocked / recently-shipped`. Most nodes are `state: "concluded"` (shipped work), so the `in-flight` tab is legitimately empty — work shows under `recently-shipped`.

## Why it matters

The operator's "is anything waiting on me?" view is structurally untrustworthy when (a) the browser silently runs months-stale frontend code, and (b) the tree is polluted with dozens of duplicate roots/persons. FR-24 ("100% of open branches surface-able") fails in practice.

## Decision

- **Cause 1: FIX NOW (reversible, auto-applied).** Add `Cache-Control: no-cache` (+ revalidation) to `serveStatic` so the browser can never serve a stale `app.js`. Restart the server to apply. One-line change, trivially reversible.
- **Cause 2: DEFER to a plan.** The reducer upsert-by-stable-id + state-file regeneration is a real change to `state.js` + `workstreams-emit.sh` that needs its own plan + state migration. Not a blind edit.

## Implementation log

- `neural-lace/workstreams-ui/server/server.js` — no-cache headers added to `serveStatic` (this session)
- Reducer upsert fix — OPEN follow-up (needs a plan; the prior `workstreams-emit-fix` workflow design is the starting point)
