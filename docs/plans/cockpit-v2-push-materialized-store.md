# Plan: Cockpit v2 — cross-machine state EXPORT (local truth stays local)

Status: ACTIVE
Mode: build
rung: 3
lifecycle-schema: v2
ask-id: <id | none — no linked ask>
prd-ref: none
Architecture-review: docs/reviews/2026-07-17-cockpit-v2-architecture-review-v4.md (VERDICT:
SOUND-WITH-AMENDMENTS — binding amendments A1-A7 folded into the task text below; lineage:
v3 review docs/reviews/2026-07-17-cockpit-v2-architecture-review-v3.md NEEDS-RESHAPING → v4
is its Phase-0 candidate, convergence verified finding-by-finding)

## Goal

Give machine B's cockpit an honest view of machine A's working state — plan progress, IN-FLIGHT
work, session liveness — without regressing the local surface (correct-by-construction read-time
parse) and without inventing a drift class. Operator-settled: cross-machine is a CURRENT
requirement (two users, two machines; Circuit's Team tab consumes this).

## User-facing Outcome

Either operator opens their cockpit and sees, alongside their exact local state: the peer
machine's plans with done/in-flight per task and session liveness, each row labeled "as of Xm ago
on <host> (<branch>, unmerged/merged)" — and a loud named state when the peer hasn't been seen
("peer unreachable since <ts>"), never a silent stale snapshot.

## Scope

IN: the per-machine EXPORT (Node CLI exporter using the shared parser + the server's derive
logic), coord-repo transport wiring (cadence — coord-push/coord-pull are currently invoked by
NOTHING; this plan owns wiring them), the peer-view UI (age-labeled rows, named absence states),
the plan-lifecycle MultiEdit matcher fix, the payload `description` carve-out, C3b (auditor's
REAL divergences → nl-issue), Task 1's shared parser/resolver (already building — shape-invariant).
OUT: any local-GUI store consumption (local reads stay on the parse); any hook-push projector or
drift/heal/classifier machinery (deleted by design); Circuit P1 (does NOT depend on this plan —
review F9); the Team-tab full merge (Circuit P2 consumes this plan's export).

## Tasks

- [x] 1. [parallel] **ONE parser + ONE resolver** (`server/plan-parse.js`; server.js + auditor.js
  repointed; lettered ids — 208 lines currently invisible — now parse; archive/ in the resolver
  union). ALREADY DISPATCHED (shape-invariant). Bash consumers conform via a SHARED fixture corpus
  both grammars must pass in --self-test (F7) — plan-lifecycle.sh gains the fixture check, not a
  rewrite. **A6 (binding): the corpus pins NEGATIVE cases as first-class fixtures — unnumbered
  checklist bullets (~1,248 of the 1,947 checkbox lines in docs/plans/** are checklist items, NOT
  tasks) must stay invisible, or a widened grammar silently inflates every progress bar** —
  Verification: mechanical
- [x] 2. [serial] **The exporter** — a small Node CLI (`server/export-state.js`): re-derives from
  local disk at export time using the shared parser + the SAME event-log join the server uses
  (`in_flight` computed at export = the join RESULT snapshot, F1). **A4 (binding): the exporter
  MUST NOT `require('server.js')`** (module load runs `listen()`; with the server up, EADDRINUSE →
  `process.exit(0)` SILENTLY exporting nothing) — this task explicitly includes factoring
  `computePlanRows`/`aggregatePlanProgress`/`countPlanTasks`/`resolvePlanAbsPath`/
  `classifySessions` into a requireable `server/derive-lib.js` with server.js repointed at it.
  **A3c: sessions export RAW `last_heartbeat_at` timestamps — never a baked live/stale
  classification** (age-truth cannot survive transport; the READER classifies by age). Emits
  per-(machine, repo, slug) records + a sessions block, stamped `hostname`, `branch`, `head_sha`,
  `dirty`, `exported_at`, `schema_version` (F4). Hash-gated with **A3ii's bounded keepalive:
  refresh `exported_at` at least every 60min even when hash-unchanged** (distinguishes idle from
  dead; caps idle churn at 24 commits/day/machine). Atomic writes; `EXPORT_HOSTNAME` override for
  test simulation (A5). `--self-test` incl. quotes/newlines in descriptions and a zero-plan
  estate — Verification: mechanical
- [x] 3. [serial] **Transport = the coordination repo** (F3, F8 binding constraint: the PRIVATE
  `workstreams-coordination` repo via git+SSH — never a mirrored remote, never the working tree,
  never the gh Contents API). **A1 (binding): wire a DEDICATED scheduled task `NL-coord-sync`
  (600s cadence; ignore-new-instance + a cheap exporter lock as the no-overlap policy — bash
  spawns have measured 94-119s here)** running exporter → coord-push → coord-pull; this task
  being the exporter's ONLY invoker IS the single-writer-per-machine enforcement (F4).
  **Staleness contract (A1): export+publish ≤600s, pull ≤600s ⇒ peer view ≤ ~20min worst-case
  behind the peer's disk, ALWAYS labeled.** (health-tick is HOURLY — it cannot host this cadence.)
  **A2 (binding): coord-push is WARN+exit-0 on every failure path BY DESIGN** — this task must
  (a) fix its ahead-of-origin path (attempt push whenever HEAD is ahead of origin, not only on
  new staged changes — today one transient failure + a quiet estate defers publication
  indefinitely); (b) have the wiring consume coord-push's outcome via a status file
  (`pushed|local-commit|noop` + ts); (c) raise the existing health-tick alert path on persistent
  `local-commit` — Verification: full
- [x] 4. [serial] **Peer view in the cockpit** — the server reads the LOCAL coord clone (no fork,
  no network on the request path — the clone is a directory; inherits skip-bad-record tolerance
  for mid-`reset --hard` partial files, A7); renders peer rows with provenance + age from
  RECEIVE-time (never the peer's wall clock alone, F2): "as of Xm ago on <host> (<branch>,
  unmerged)". **Named states with REAL mechanisms (A3): `fresh-ish (≤20m)` / `estate unchanged
  since <ts>` (content-age, distinct from liveness) / `peer unreachable since <ts>` (keepalive
  missing — the A3ii mechanism makes this distinguishable from idle) / `no data yet`; plus the
  reader's OWN transport health: "my coord view last refreshed Xm ago" from the last successful
  coord-pull.** Peer-state thresholds env-injectable (A5). A peer's UNMERGED state never renders
  as plain done (F4, §1). Local cards stay 100% on local truth; same-slug peer copies are labeled
  provenance rows, never substituted — Verification: full
- [x] 5. [serial] **plan-lifecycle MultiEdit matcher fix** (independent real hole, P8): settings
  matcher `Edit|Write` → `Edit|Write|MultiEdit`; regression scenario in its self-test —
  Verification: mechanical
- [x] 6. [serial] **Payload contract**: `description` into `DETAIL_ALLOWED_KEYS` + a
  `DENYLIST_EXEMPT_KEYS` set with a length cap (by KEY, as HREF_KEYS does — m1), stated plainly as
  a knowing widening of the anti-noise constraint scoped to plan content — Verification: mechanical
- [x] 7. [serial] **C3b — wire the auditor's REAL divergences** (log_ahead_task_not_flipped et al.)
  into `nl-issue.sh` with dedup + recurrence escalation (the operator's actual auto-healing intent;
  self-inflicted-drift reporting died with the projector) — Verification: full
- [ ] 8. [serial] **Acceptance (end-user-advocate runtime)** — two-machine simulation acceptable
  (a second clone standing in for machine B, **using the `EXPORT_HOSTNAME` override — coord keys
  peers by hostname and both sim "machines" share one — and env-injected state thresholds so the
  degradation leg is runnable, A5**): flip a checkbox + start a builder on "A" → within the
  written cadence, "B"'s cockpit shows the new done state AND the in-flight row, age-labeled;
  kill the export loop → "B" degrades to "peer unreachable" (via the missing keepalive), never a
  silent stale render — Verification: full

## Files to Modify/Create
- `docs/plans/cockpit-v2-push-materialized-store-evidence.md` — the plan's own evidence log,
  appended once per verified task (already carries Tasks 1-2's blocks); every task in this plan
  writes here, so it is declared as in-scope up front rather than needing an in-flight fix at
  every task boundary.
- `neural-lace/workstreams-ui/server/*.js` — every file this plan touches lives directly in this
  one directory: `plan-parse.js` (task 1, in flight), `export-state.js` (new), `derive-lib.js`
  (new — task 2's A4 refactor: the requireable local-disk derivation library server.js is
  repointed at, so the exporter never requires server.js), `peer-view.js` (new — task 4: the
  no-fork/no-network read of the local coord clone), `server.js` (peer-view read + payload
  carve-out), `payload-schema.js` (LANDING_ALLOWED_KEYS extension), `auditor.js` (C3b),
  `server.selftest.js` (task 4's S64-S69 wiring proof). Full-path glob used deliberately (a
  same-directory-shorthand bullet like `server/server.js` does not match the scope-enforcement-
  gate's repo-root-relative staged paths — fixed here after task 2 tripped on it).
- `neural-lace/workstreams-ui/web/*.js`, `neural-lace/workstreams-ui/web/app.css` — peer rows
  (`asks.js`, `app.css`) + `cockpit.selftest.js`'s own structural extension (the task text's own
  Prove-it-works clause: "web/cockpit.selftest.js must stay 84/84 or grow"). Glob used for the
  same reason the server/ bullet above already documents (repo-root-relative staged-path match).
- `adapters/claude-code/scripts/coord-push.sh` — A2 ahead-of-origin retry + outcome status file
- `adapters/claude-code/scripts/coord-pull.sh` — read only; task 3 wires it, does not change it
- `adapters/claude-code/scripts/coord-sync.sh` — new; task 3's dedicated cadence (A1), the
  exporter's sole invoker: exporter -> coord-push -> coord-pull, its own mkdir lock, A2c alert
- `adapters/claude-code/scripts/install-coord-sync-task.ps1` — new; the NL-CoordSync scheduled-
  task installer, a SIBLING to install-weekly-hygiene-task.ps1 (a sub-10min repeating trigger is
  a structurally different trigger shape than that script's -Weekly/-Checkin triggers)
- `adapters/claude-code/settings.json.template` (MultiEdit matcher)
- `adapters/claude-code/hooks/plan-lifecycle.sh` (shared fixture corpus check)
- `adapters/claude-code/manifest.json` (exporter/wiring entries with §10 fields — NOT touched by
  task 3: coord-push.sh/coord-pull.sh/health-tick.sh, the closest precedents, all predate this
  plan with no manifest entries of their own either; registration is deferred to whichever later
  task in this plan first requires it, tracked in docs/backlog.md rather than added speculatively)

## In-flight scope updates
- 2026-07-17: `neural-lace/workstreams-ui/server/derive-lib.js` — task 2's own text (amendment
  A4) explicitly mandated creating this file (factoring computePlanRows/aggregatePlanProgress/
  countPlanTasks/resolvePlanAbsPath/classifySessions + their direct dependencies out of
  server.js), but the Files to Modify/Create table above omitted it; added to both sections in
  the same commit as the task-2 build per scope-enforcement-gate's "update the plan" path. Also
  rewrote the section's server/* bullets from directory-shorthand to full repo-root-relative
  paths/globs — the shorthand form doesn't match the gate's staged-path comparison at all,
  which would have blocked every future task in this plan touching those files, not just task 2.
- 2026-07-17: `adapters/claude-code/scripts/coord-sync.sh` — named explicitly in the Files table
  above (previously only "scheduled-task installer or health-tick splice", a placeholder task 3's
  own body text already resolved by naming this exact file). Design choice made in the un-pinned
  space that text left open: the exporter's per-host file lives under the coord clone's
  `plan-export/` subdirectory, schema-distinct from coord-push.sh's own `tree-state/` envelope
  (task 4 reads both).
- 2026-07-17: `adapters/claude-code/scripts/install-coord-sync-task.ps1` — named explicitly in the
  Files table above, same placeholder-resolution as the coord-sync.sh entry immediately above.
  Design choice: a sibling installer (task 3's own text offered this as an explicit alternative to
  a third mode on install-weekly-hygiene-task.ps1), because a sub-10-minute repeating cadence is a
  structurally different `New-ScheduledTaskTrigger` shape than that script's existing
  -Weekly/-Checkin triggers. NOTE (found in passing, out of scope for this task, spawned
  separately): install-weekly-hygiene-task.ps1 itself has a latent bug of the identical class — a
  real em-dash character inside a double-quoted string breaks Windows PowerShell 5.1's parser when
  the file has no BOM (confirmed via `[System.Management.Automation.Language.Parser]::ParseFile`);
  the whole file fails to parse. This new installer inherited the same pattern while drafting and
  was fixed here; the precedent file was left untouched.
- 2026-07-17: `docs/plans/cockpit-v2-push-materialized-store-evidence.md` — added to the Files
  table above. The evidence log has been written to since Task 1 (it isn't a `Status: ACTIVE`
  plan file itself, so it doesn't qualify for the gate's self-claiming-plan exemption, and it was
  never previously declared), which the live `scope-enforcement-gate.sh` now enforces strictly
  enough to block a commit appending Task 4's own evidence block without this entry. Declared
  once, up front, for every remaining task in this plan rather than re-discovering the same gap
  at each task boundary.
- 2026-07-17: `neural-lace/workstreams-ui/server/peer-view.js` (new) and
  `neural-lace/workstreams-ui/server/server.selftest.js` named explicitly in the Files table above
  (both already matched by the pre-existing `server/*.js` glob, but named in prose for clarity —
  same treatment `derive-lib.js` got at task 2). Also widened the `web/` bullet from an explicit
  two-file list to a `web/*.js` glob + `web/app.css`, to cover `web/cockpit.selftest.js`'s own
  structural-test extension — the task 4 text's own Prove-it-works clause ("web/cockpit.selftest.js
  must stay 84/84 or grow") already required touching this file; the original Files table simply
  didn't enumerate it.

## Assumptions
- The private coordination repo exists and both machines hold SSH access (coord-push.sh header
  verified; ADR 051). If absent on a machine, the exporter no-ops loudly (named state on the peer).
- The event-log join and heartbeat classification are reusable as libs from the server modules
  without the HTTP server running (verify at task 2; if not, factor them — that refactor is in
  scope).
- ≤20min worst-case peer staleness satisfies the consumer (Circuit's own sketch accepts ~10min
  transport; the Team tab is a glance surface, not a control loop).

## Edge Cases
- Peer clock skew → age from local receive-time (F2). Absent peer data → named state, never empty.
- Same slug on both machines → labeled provenance rows; local truth drives the local card (F4).
- Exporter runs during a builder's plan edit → hash-gate re-runs next cadence; export is atomic.
- Coord push auth failure → **coord-push is WARN+exit-0 BY DESIGN (A2 corrected the earlier false
  "fails loudly" claim)**: detection is two-sided — writer-side, the wiring reads coord-push's
  outcome status file and alerts on persistent `local-commit`; reader-side, the peer's missing
  keepalive drives "peer unreachable". The silent-freeze class is excluded by MECHANISM, not by
  the transport's exit code.
- Dirty/unmerged peer branch state → `dirty`+`branch` fields render "unmerged"; never plain done.

## Acceptance Scenarios
(see task 8 — the two-machine flip/in-flight/unreachable triple is the §4 demonstration)

## Out-of-scope scenarios
- Sub-minute cross-machine freshness (would need a different transport class entirely — named in
  the review's crossover analysis; not the requirement).
- Multi-user identity/authz (Circuit P2's Team tab owns that).

## Closure Contract
Closes when: tasks 1-8 verified (task-verifier + rung-3 comprehension), the two-machine acceptance
demonstrated, manifest GREEN, and the retirement note recorded: **retire the export if
cross-machine ceases to be a requirement — exercisable cheaply only until Circuit P2 consumes the
export; after that, retirement is a Circuit change too (F9 decay clause).**

## Testing Strategy
Exporter + parser self-tests (sandboxed fixtures); the shared grammar fixture corpus run by BOTH
the Node parser and plan-lifecycle.sh's checker; server.selftest.js extended for the peer-view
read (fixture coord clone); the acceptance simulation per task 8. No new test infrastructure.

## Walking Skeleton
Task 2's exporter run once by hand producing one export file consumed by task 4's reader from a
fixture clone — end-to-end thinnest slice before any cadence wiring.

## Decisions Log
- (2026-07-17) v4 adopts the v3 review's Phase-0 candidate wholesale: local-reads-truth,
  single-exporter per machine, snapshot-with-age, coord transport. The projector/store/drift
  machinery from v2/v3 is DELETED, not deferred — an export re-derived at export time has no drift
  class to manage. Reversible: the export artifact and reader are additive; nothing local changes
  shape.
