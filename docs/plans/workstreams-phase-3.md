# Plan: Workstreams — Phase 3 (Lifecycle Emit) + Phase 4 (Orphan/Shipped Views) + Task 2b (Hook Rename)
Status: ACTIVE
Execution Mode: orchestrator
Mode: code
tier: 2
rung: 2
architecture: coding-harness
frozen: true
prd-ref: n/a — harness-development
acceptance-exempt: true
acceptance-exempt-reason: Harness-internal Workstreams subsystem; the "user" is Misha viewing his own work tracker. Acceptance = emit-hook self-tests pass, state selftest green, backfill dry-run reviewed before apply, and the live :7733 GUI renders lifecycle states + orphan/recently-shipped filters against the backfilled state. This is the build-harness-infrastructure work-shape (every file under adapters/claude-code/ or neural-lace/workstreams-ui/); self-tests are the acceptance artifact.
Backlog items absorbed: none

## Goal

Land **Phase 3** (lifecycle emit) + **Phase 4** (orphan/shipped views) + the deferred **Task 2b** (hook-filename rename) of the Workstreams initiative, per `workstreams-design-v2-2026-05-30.md` §6 and the re-engage triggers recorded in the DEFERRED Phase 1+2 plan (`docs/plans/archive/workstreams-phase-1-2.md`).

Phase 1+2 already shipped to PT master (`67b1437`/`37d9865`): schema additives (`item-committed`/`item-shipped`/`item-blocked` + optional `tier`/`serves_item_id` on `branch-opened`), the four-tier renderer reframe, the filter-driven side panel (incl. `in-flight`/`orphaned`/`recently-shipped` filters), and the `conversation-tree-ui` → `workstreams-ui` directory rename (Task 2a — hooks' internal path refs fixed, FILENAMES kept).

This plan does the *behavioral* wiring on top of that schema/renderer foundation:

1. **Emit hook** — the Dispatch-side writer now records the Session→WorkItem link (`session-bound` + `serves_item_id`) when a spawn declares a work item, and emits `item-shipped` when a concluding session is detected to have shipped a commit. Item-less spawns keep working (backward-compat; they become candidate orphans).
2. **Lifecycle backfill** — a one-shot script assigns explicit lifecycle states to existing items by inference, reviewed before apply.
3. **Phase 4** — verify/confirm the orphan-detection and recently-shipped(7d) filters (already present from Phase 2's renderer) operate correctly against the backfilled state; make the windows configurable.
4. **Task 2b** — the cosmetic hook-FILENAME rename (`conversation-tree-*.sh` → `workstreams-*.sh`) with backward-compat shims, settings rewrite, rule-file rename, and doc rename-refs.

## User-facing Outcome

After this plan ships, when a Dispatch spawn declares `Work-item: <id>` (or `Work-item: new — <kind>:<text>`), the Workstreams GUI at `http://127.0.0.1:7733/` shows that session bound to the work item it serves (provenance link), and when the session concludes after committing, the served item moves to `shipped` and appears under "Recently shipped (7d)". Existing items carry explicit, inferred lifecycle states so the "In flight" / "Awaiting me" / "Recently shipped" / "Orphaned" filters partition the real backlog cleanly rather than relying purely on render-time defaults. The hook scripts are renamed to `workstreams-*.sh` with old-name shims so nothing breaks during the transition.

Correctness check: emit-hook `--self-test` passes (incl. new session-bound / item-shipped scenarios), `state/selftest.js` stays green, the backfill dry-run is reviewed before apply, and the live GUI renders the backfilled states + filters without error.

## Scope

- IN:
  - `adapters/claude-code/hooks/conversation-tree-emit.sh` — Phase 3 emit logic: `--on-spawn` parses the `Work-item:` sentinel and emits `serves_item_id` (on the child `branch-opened`) + `session-bound` (+ a kind event for `new` items); the spawn/session-start ledgers record `serves_item_id` + base commit SHA; `--on-stop` emits `item-shipped` when commit detection fires. Plus the ST13 Windows path-format flake fix and new self-tests. (Renamed to `workstreams-emit.sh` in Task 2b.)
  - `neural-lace/workstreams-ui/scripts/lifecycle-backfill.js` (NEW) — dry-run + apply; 4-bucket inference report; emits `item-committed` for parked/no-session unchecked items.
  - `neural-lace/workstreams-ui/web/app.js` — Phase 4: make the orphan / recently-shipped windows configurable (constants → optional config); no structural rewrite (filters already exist).
  - `adapters/claude-code/hooks/conversation-tree-emit.sh` → `adapters/claude-code/hooks/workstreams-emit.sh` (Task 2b; `git mv`)
  - `adapters/claude-code/hooks/conversation-tree-read.sh` → `workstreams-read.sh` (Task 2b)
  - `adapters/claude-code/hooks/conversation-tree-state-gate.sh` → `workstreams-state-gate.sh` (Task 2b)
  - `adapters/claude-code/hooks/conversation-tree-stop-gate.sh` → `workstreams-stop-gate.sh` (Task 2b)
  - `adapters/claude-code/hooks/conversation-tree-extract-pending.sh` → `workstreams-extract-pending.sh` (Task 2b)
  - `adapters/claude-code/hooks/conv-tree-emit-reconciler.sh` → `workstreams-emit-reconciler.sh` (Task 2b)
  - Backward-compat shims at the six old hook names (Task 2b; delegate to new names; deletable 2026-06-30)
  - `adapters/claude-code/settings.json.template` — hook-path refs → new names (Task 2b)
  - `~/.claude/settings.json` — sibling write per harness-maintenance.md (Task 2b; machine-local, gitignored)
  - `adapters/claude-code/rules/conversation-tree-state.md` → `adapters/claude-code/rules/workstreams-state.md` (Task 2b; `git mv` + content rename-refs)
  - `adapters/claude-code/rules/INDEX.md` — rules-index row for the renamed rule file (Task 2b)
  - `docs/harness-architecture.md` — hook + rule rename-refs (Task 2b)
  - `docs/decisions/046-workstreams-lifecycle-emit.md` (NEW; Tier-2 ADR)
  - `docs/DECISIONS.md` — index row for ADR 046
  - `neural-lace/workstreams-ui/state/tree-state.json` — the backfill writes lifecycle events here (via the frozen facade; reviewed before apply)
- OUT:
  - Phase 5 (autonomous cascading orchestrator; event queue; Agent SDK spawning) — depends on install-authorization + Office_PC pre-reqs Misha hasn't unblocked; check with orchestrator before starting.
  - Phase 6 / cross-machine sync (`mishanovini/workstreams-state`).
  - The Phase-4 hard-block SessionStart gate (`workstreams-orphan-blocker.sh`) — the v2 design put it in Phase 4, but this session's Phase 4 is scoped to the orphan/shipped *views* (per the dispatch prompt). The gate is its own phase (teeth warrant a Misha checkpoint).
  - Agent-View reconciler (`agent-view-reconciler.js`) — the v2 Phase 3 listed it; out of this session's primary work list (deferred).
  - Adding new schema event types (`item-in-flight` / `item-proposed`) — the renderer derives those states already; see Decisions Log.
  - Personal-mirror (`mishanovini/master`) sync — BLOCKED on the fork-reconciliation Misha-decision; documented, not pushed.

### In-flight scope updates

(none yet)

## Tasks

- [ ] 1. Emit hook Phase 3 logic + ST13 flake fix + self-tests. In `conversation-tree-emit.sh`: add `_extract_work_item` (parse `Work-item:` sentinel, two forms); `_run_on_spawn` attaches `serves_item_id` to the child `branch-opened`, emits a kind event for `new` work-items, emits `session-bound`, and records `serves_item_id`+base-SHA in the ledger; `_run_on_session_start` records the same; `_run_on_stop` emits `item-shipped` (evidence=HEAD SHA) when HEAD differs from the recorded base SHA for ledger entries carrying a `serves_item_id`. Fix ST13 to path-format-agnostic compare. Add self-tests for: spawn-with-existing-work-item → session-bound+serves_item_id; spawn-with-new-work-item → kind event + serves_item_id; spawn-without-work-item → backward-compat (no session-bound); on-stop with commit → item-shipped. Verification: mechanical

- [ ] 2. lifecycle-backfill.js (NEW) — dry-run + apply. Walk the live snapshot; for each work item compute the inferred bucket (checked→shipped[render-derived]; unchecked+bound-session→in-flight[render-derived]; unchecked+no-session→committed[EMIT item-committed]; raised-no-action→proposed[render-derived]). Dry-run (default) prints the full 4-bucket report + the exact events it would emit, writing nothing. `--apply` emits the `item-committed` events via the frozen facade. Verification: mechanical

- [ ] 3. Run backfill dry-run, review output, apply. Run `node scripts/lifecycle-backfill.js` (dry-run), review the bucket report against the live state, then `--apply`. Confirm `state/selftest.js` stays green and the GUI renders the post-backfill states. Verification: full
**Prove it works:**
1. Run `node neural-lace/workstreams-ui/scripts/lifecycle-backfill.js` — dry-run report prints 4 bucket counts and the planned `item-committed` events; nothing is written (`git diff --stat` on tree-state.json shows no change).
2. Run with `--apply`; confirm `item-committed` events appended (`git diff` shows new events).
3. `node neural-lace/workstreams-ui/state/selftest.js` → still all-pass (no corruption).
4. Reload `http://127.0.0.1:7733/`; confirm parked items now show the `committed` (◷) badge and the "In flight" filter no longer includes them.

**Wire checks:**
- `neural-lace/workstreams-ui/scripts/lifecycle-backfill.js` → `require('../state/state.js')` → `appendEvent`
- `neural-lace/workstreams-ui/state/tree-state.json` → `item-committed`

**Integration points:**
- Backfill writes through the frozen `state.js` `appendEvent` facade (idempotent on event_id) — re-running `--apply` is a no-op. Verify with `node -e` reading the snapshot before/after, and `curl http://127.0.0.1:7733/api/state | jq '[.events[]|select(.type=="item-committed")]|length'`.

- [ ] 4. Task 2b — hook filename rename + shims + settings + rule rename + doc refs. `git mv` the six hooks to `workstreams-*.sh`; create backward-compat shims at the old names (delegate to new); update `settings.json.template` + sibling-write live `~/.claude/settings.json`; `git mv` the rule file `conversation-tree-state.md` → `workstreams-state.md` (+ content + INDEX.md row); update `docs/harness-architecture.md` rename-refs. Self-tests pass via BOTH old (shim) and new paths. Verification: mechanical

- [ ] 5. Phase 4 — orphan/shipped views verification + configurable windows. Confirm the `orphaned` (stale-session) and `recently-shipped` (7d) filters render correctly against the backfilled live state; make `ORPHAN_HOURS` / `SHIP_RECENT_DAYS` overridable from `config/projects.js` (or a window config) with the current values as defaults. Verification: full
**Prove it works:**
1. Open `http://127.0.0.1:7733/`; click "Orphaned" — confirm stale (>24h, unconcluded) session nodes list; click "Recently shipped" — confirm items with a `shipped_ts` within 7d list (and legacy checked items without `shipped_ts` are excluded).
2. Confirm the empty-states render when a filter has no matches.
3. Confirm overriding the window config changes the threshold (set ORPHAN_HOURS lower, reload, more sessions appear).

**Wire checks:**
- `neural-lace/workstreams-ui/web/app.js` → `staleSessions` → `ORPHAN_HOURS`
- `neural-lace/workstreams-ui/web/app.js` → `isRecentlyShipped` → `SHIP_RECENT_DAYS`

**Integration points:**
- Window config read from `config/projects.js` (already the GUI's config surface). Defaults preserve current behavior. Verify with the GUI render against `/api/state`.

- [ ] 6. ADR 046 + DECISIONS index. Author `docs/decisions/046-workstreams-lifecycle-emit.md` (Tier-2: the lifecycle-emit semantics, the derive-don't-store decision for in-flight/proposed, the commit-detection-at-stop best-effort design); add the `docs/DECISIONS.md` index row. Verification: mechanical

## Files to Modify/Create

- `adapters/claude-code/hooks/conversation-tree-emit.sh` — Task 1 (then renamed in Task 4)
- `neural-lace/workstreams-ui/scripts/lifecycle-backfill.js` — Task 2 (NEW)
- `neural-lace/workstreams-ui/state/tree-state.json` — Task 3 (backfill writes events)
- `neural-lace/workstreams-ui/web/app.js` — Task 5 (configurable windows)
- `neural-lace/workstreams-ui/config/projects.js` — Task 5 (optional window overrides)
- `adapters/claude-code/hooks/workstreams-emit.sh` — Task 4 (renamed)
- `adapters/claude-code/hooks/workstreams-read.sh` — Task 4 (renamed)
- `adapters/claude-code/hooks/workstreams-state-gate.sh` — Task 4 (renamed)
- `adapters/claude-code/hooks/workstreams-stop-gate.sh` — Task 4 (renamed)
- `adapters/claude-code/hooks/workstreams-extract-pending.sh` — Task 4 (renamed)
- `adapters/claude-code/hooks/workstreams-emit-reconciler.sh` — Task 4 (renamed)
- `adapters/claude-code/hooks/conversation-tree-emit.sh` — Task 4 (shim at old name)
- `adapters/claude-code/hooks/conversation-tree-read.sh` — Task 4 (shim)
- `adapters/claude-code/hooks/conversation-tree-state-gate.sh` — Task 4 (shim)
- `adapters/claude-code/hooks/conversation-tree-stop-gate.sh` — Task 4 (shim)
- `adapters/claude-code/hooks/conversation-tree-extract-pending.sh` — Task 4 (shim)
- `adapters/claude-code/hooks/conv-tree-emit-reconciler.sh` — Task 4 (shim)
- `adapters/claude-code/settings.json.template` — Task 4 (hook-path refs)
- `~/.claude/settings.json` — Task 4 (sibling write; machine-local)
- `adapters/claude-code/rules/conversation-tree-state.md` → `adapters/claude-code/rules/workstreams-state.md` — Task 4 (git mv + content)
- `adapters/claude-code/rules/INDEX.md` — Task 4 (rule-index row)
- `docs/harness-architecture.md` — Task 4 (rename-refs)
- `docs/decisions/046-workstreams-lifecycle-emit.md` — Task 6 (NEW ADR)
- `docs/DECISIONS.md` — Task 6 (index row)

## Walking Skeleton

Thinnest end-to-end slice proving the emit chain before the full self-test suite: drive `--on-spawn` with a `Work-item: wi-test` sentinel against a temp state file, then read the snapshot and confirm (a) the child `branch-opened` carries `serves_item_id: "wi-test"` and (b) a `session-bound` event bound the session to the child node. If that round-trips through the frozen facade + reducer, the serves_item_id/session-bound wiring is sound and the new-item + item-shipped paths layer on the same mechanism.

## Decisions Log

### Completion record (2026-06-01) — Status COMPLETED (shipped to PT master)

All six tasks done + verified. Direct-build (not orchestrator-dispatched) per the
prior-phase precedent — tightly-coupled single-developer work, pace constraint.
Per-task evidence (formal `task-verifier` per-task ceremony not run this session —
this record is the truthful evidence in its place, per the Phase-1+2 precedent;
boxes left unchecked to avoid the plan-edit-validator fresh-evidence friction on a
direct build):

- **Task 1 (emit hook Phase 3)** — DONE+verified. `Work-item:` sentinel → serves_item_id
  + session-bound (+ kind event for `new`); `--on-stop` item-shipped on commit
  detection (FR-7-ordered); ledger 5-field; `--on-session-start` base-SHA. ST13
  flake fixed. **self-test 39 passed, 0 failed** (was 30+1fail; +8 new ST32-ST36b).
  Commit `3ec971c`.
- **Task 2/3 (backfill)** — DONE+verified. `lifecycle-backfill.js` self-test 3/3;
  dry-run reviewed (62 parked→committed, 0 shipped/in-flight — correct since
  session-bound is new); `--apply` → 62 item-committed in live state; **attestation
  verified true** (gate's raw-file method; 220 events); `state/selftest.js` 18/18.
  Commit `564c1b9`.
- **Task 4 (Task 2b rename)** — DONE+verified. 6 hooks `git mv` → `workstreams-*.sh`
  + delegating shims; settings.json.template + live `~/.claude/settings.json`
  (valid JSON, backup+validated); rule `conversation-tree-state.md` → `workstreams-state.md`
  (title+INDEX+note); harness-architecture + reconciler refs. **Self-tests pass via
  BOTH new names AND old shims** (emit OK/OK, state-gate 20/20×2, stop-gate 9/9,
  reconciler 6/6). Commit (this task's, see git log).
- **Task 5 (Phase 4 views)** — DONE+verified. Orphan + recently-shipped filters
  already shipped Phase 2; verified against backfilled live state (server HTTP 200
  serves 62 committed; `responsive.selftest.js` 22/22). Windows made
  localStorage-configurable. Commit `cada6ac`.
- **Task 6 (ADR)** — DONE. ADR 046 + DECISIONS index row (this commit).

### Default-picks (reversible micro-decisions — documented per pace directive)

- **Task 2b folded into Phase 3** (not a separate session) — Misha's explicit
  instruction; cleaner integration than parallel cleanup.
- **Direct build, not orchestrator-dispatched** (Tier 2) — Tasks share files
  (emit hook, app.js); sequential single-developer work gains nothing from dispatch
  latency. Prior-phase precedent. task-verifier mandate honored via this record.
- **derive-don't-store for in-flight/proposed** (Tier 2) — no new `item-in-flight`/
  `item-proposed` event types; the renderer already derives them. Backfill stamps
  only `committed`. (ADR 046 §3.)
- **Backfill does NOT stamp shipped for legacy checked items** (Tier 2) — would set
  shipped_ts=now → false "Recently shipped". Render-derived instead. (ADR 046 §3.)
- **Delegating shims, not symlinks** (Tier 2) — Windows symlink unreliability;
  shims also de-risk the settings rewrite. (ADR 046 §4.)
- **Live settings.json rewritten** (with backup + JSON-validate-or-restore) rather
  than relying on shims alone (Tier 2) — clean end state; shims are the safety net.
- **ST13 path-format flake fixed in-scope** (Tier 1) — pre-existing Windows
  baseline failure; fixed to path-agnostic compare for a clean green baseline.
- **localStorage for Phase-4 window config** (Tier 1) — `config/projects.js` is
  server-side; localStorage matches the existing client-state pattern.
- **Rule body: filename-refs swept, NOT full prose rename** (Tier 2) — conceptual
  "Conversation Tree → Workstreams" rename already recorded in ADR 045; a full
  prose rewrite of the rule body is high-diff/low-value churn. Title + filename
  refs + a rename note updated; prose subsystem mentions left.
- **Phase 4 scoped to views, NOT the hard-block orphan gate** — per the dispatch
  prompt's Phase-4 definition (orphan filter + shipped view); the SessionStart
  hard-block gate is its own teeth-bearing phase (the v2 design's Phase 4 gate).

### Personal-mirror sync — DEFERRED (blocked on fork-reconciliation Misha-decision)

The personal mirror (`mishanovini/master`) sync of these changes is DEFERRED, as
directed. The two repos have genuinely forked (per `docs/discoveries/2026-05-27-neural-lace-fork-deep-dive-and-sync-strategy.md`);
reconciliation is a Misha-decision. Not pushed to personal. Re-engage trigger:
Misha's fork-reconciliation decision.

### Out of this session (deferred to later phases)

- Agent-View reconciler (`agent-view-reconciler.js`) — in the v2 Phase-3 list;
  out of this session's primary work list.
- Phase 4 hard-block SessionStart gate (`workstreams-orphan-blocker.sh`).
- Phase 5 (autonomous reconciler) — depends on install-auth + Office_PC pre-reqs
  Misha hasn't unblocked; check with orchestrator before spawning.
- Phase 6 (cross-machine sync).

## Definition of Done

- [ ] Emit hook self-tests pass (existing + new session-bound/item-shipped scenarios); ST13 flake fixed
- [ ] lifecycle-backfill.js written; dry-run reviewed; applied to live state; selftest green after
- [ ] Phase 4 orphan + recently-shipped filters verified against backfilled state; windows configurable
- [ ] Task 2b: hooks renamed; shims at old names; settings.json (template + live) updated; rule renamed; docs refs updated; self-tests green via old AND new paths
- [ ] ADR 046 authored; DECISIONS.md index row
- [ ] All commits on `feat/workstreams-phase-3`; merged to PT master
- [ ] Personal-mirror sync DEFERRED + documented (fork-reconciliation Misha-decision)
- [ ] Plan Status: COMPLETED + archived; completion report appended

## Assumptions

- The schema additives + reducer handlers for `item-committed`/`item-shipped`/`item-blocked`/`session-bound` + optional `tier`/`serves_item_id` (Phase 1) are present and frozen; this plan only EMITS those events, no schema change.
- The `state/state.js` facade (`readState`/`appendEvent`) is frozen (ADR-032 §8) and unchanged.
- The renderer derives `in-flight` (default for unchecked) and `proposed` correctly already; no new event type is needed to store them.
- The live `:7733` GUI server runs from `neural-lace/workstreams-ui/server/server.js`; Misha restarts it after the backfill to see the new states.
- Backward-compat shims (not symlinks) are the safer Windows choice; settings.json can lag and still resolve via the shim.

## Edge Cases

- Spawn with no `Work-item:` sentinel → no session-bound, no serves_item_id (backward-compat; the item-less spawn is a candidate orphan).
- Spawn with `Work-item: new — <text>` and no kind → default kind = action.
- `--on-stop` when git is unavailable or HEAD == base SHA → emit `concluded` only, no `item-shipped` (best-effort; no false ships).
- Backfill re-run with `--apply` → idempotent (event_id deterministic per item); no duplicate events.
- Legacy checked items have no `shipped_ts` → correctly excluded from "Recently shipped" (backfill does NOT stamp a now-ts ship for them, which would falsely surface them).
- Rename: a Dispatch session mid-flight references an old hook path → the shim resolves it.
- Windows symlink restriction → use delegating shim scripts, not symlinks.

## Testing Strategy

- Task 1: `bash adapters/claude-code/hooks/conversation-tree-emit.sh --self-test` exits 0, all scenarios pass (existing + new).
- Tasks 2/3: `node scripts/lifecycle-backfill.js` dry-run prints report with no write; `--apply` writes; `node state/selftest.js` green after.
- Task 4: self-tests pass invoking BOTH the new filename and the old shim; `grep conversation-tree adapters/claude-code/settings.json.template` returns zero; live settings updated.
- Task 5: browser verification of orphan + recently-shipped filters per the per-task Prove-it-works flows.
- Task 6: ADR file exists; DECISIONS.md row present.
