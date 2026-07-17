# Plan: Cockpit v2 — cross-machine state EXPORT (local truth stays local)

Status: DRAFT (v4 — reshaped per docs/reviews/2026-07-17-cockpit-v2-architecture-review-v3.md;
v4 implements that review's own Phase-0 candidate design)
Mode: build
rung: 3
lifecycle-schema: v2
ask-id: <id | none — no linked ask>
prd-ref: none
Architecture-review: docs/reviews/2026-07-17-cockpit-v2-architecture-review-v3.md (v3 verdict
NEEDS-RESHAPING → v4 is the prescribed reshape; re-review required before ACTIVE)

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

- [ ] 1. [parallel] **ONE parser + ONE resolver** (`server/plan-parse.js`; server.js + auditor.js
  repointed; lettered ids — 208 lines currently invisible — now parse; archive/ in the resolver
  union). ALREADY DISPATCHED (shape-invariant). Bash consumers conform via a SHARED fixture corpus
  both grammars must pass in --self-test (F7) — plan-lifecycle.sh gains the fixture check, not a
  rewrite — Verification: mechanical
- [ ] 2. [serial] **The exporter** — a small Node CLI (`server/export-state.js`): re-derives from
  local disk at export time using the shared parser + the SAME event-log join the server uses
  (`in_flight` computed at export = the join RESULT snapshot, F1), plus session liveness (heartbeat
  classification). Emits per-(machine, repo, slug) records + a sessions block, stamped `hostname`,
  `branch`, `head_sha`, `dirty`, `exported_at`, `schema_version` (F4). Hash-gated: unchanged estate
  ⇒ no write. Server-independent (spawnable with the server down). Atomic writes. `--self-test`
  incl. quotes/newlines in descriptions and a zero-plan estate — Verification: mechanical
- [ ] 3. [serial] **Transport = the coordination repo** (F3, F8 binding constraint: the PRIVATE
  `workstreams-coordination` repo via git+SSH — never a mirrored remote, never the working tree,
  never the gh Contents API). Wire the cadence THIS plan owns: exporter + `coord-push.sh` invoked
  on an existing scheduled surface (health-tick or a dedicated scheduled task, ≥600s throttle
  honored); `coord-pull.sh` on the same cadence for the reader side. Numbers in writing (staleness
  contract, F2): export ≤60s after change (hash check), publish ≤600s throttle, pull ≤600s ⇒
  peer view ≤ ~20min worst-case behind the peer's disk, and ALWAYS labeled — Verification: full
- [ ] 4. [serial] **Peer view in the cockpit** — the server reads the LOCAL coord clone (no fork,
  no network on the request path — the clone is a directory); renders peer rows with provenance +
  age from receive-time (never the peer's wall clock alone, F2): "as of Xm ago on <host>
  (<branch>, unmerged)"; named states: `fresh-ish (≤20m)` / `aging (>20m)` / `peer unreachable
  since <ts>` / `no data yet`; a peer's UNMERGED state never renders as plain done (F4, §1).
  Local cards stay 100% on local truth; same-slug peer copies are labeled provenance rows, never
  substituted — Verification: full
- [ ] 5. [serial] **plan-lifecycle MultiEdit matcher fix** (independent real hole, P8): settings
  matcher `Edit|Write` → `Edit|Write|MultiEdit`; regression scenario in its self-test —
  Verification: mechanical
- [ ] 6. [serial] **Payload contract**: `description` into `DETAIL_ALLOWED_KEYS` + a
  `DENYLIST_EXEMPT_KEYS` set with a length cap (by KEY, as HREF_KEYS does — m1), stated plainly as
  a knowing widening of the anti-noise constraint scoped to plan content — Verification: mechanical
- [ ] 7. [serial] **C3b — wire the auditor's REAL divergences** (log_ahead_task_not_flipped et al.)
  into `nl-issue.sh` with dedup + recurrence escalation (the operator's actual auto-healing intent;
  self-inflicted-drift reporting died with the projector) — Verification: full
- [ ] 8. [serial] **Acceptance (end-user-advocate runtime)** — two-machine simulation acceptable
  (a second clone standing in for machine B): flip a checkbox + start a builder on "A" → within
  the written cadence, "B"'s cockpit shows the new done state AND the in-flight row, age-labeled;
  kill the export loop → "B" degrades to "peer unreachable", never a silent stale render —
  Verification: full

## Files to Modify/Create
- `neural-lace/workstreams-ui/server/plan-parse.js` (task 1, in flight), `server/export-state.js`
  (new), `server/server.js` (peer-view read + payload carve-out), `server/payload-schema.js`,
  `server/auditor.js` (C3b), `web/asks.js`/`web/app.css` (peer rows)
- `adapters/claude-code/scripts/coord-push.sh`/`coord-pull.sh` (cadence wiring only),
  scheduled-task installer or health-tick splice, `adapters/claude-code/settings.json.template`
  (MultiEdit matcher), `adapters/claude-code/hooks/plan-lifecycle.sh` (shared fixture corpus check)
- `adapters/claude-code/manifest.json` (exporter/wiring entries with §10 fields)

## In-flight scope updates
(none yet)

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
- Coord push auth failure → git+SSH fails LOUDLY (non-zero), surfaced by the wiring's existing
  alert path — the silent-freeze class (F3 pre-mortem) is structurally excluded.
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
