# ADR 046 — Workstreams Phase 3: lifecycle emit + backfill + hook-filename rename

- **Date:** 2026-06-01
- **Status:** Accepted — shipped to master (Phase 3 + Phase 4 views + Task 2b)
- **Stakeholders:** Misha (sole operator + user of the work tracker)
- **Relates to:** ADR-045 (Workstreams reframe — the schema additives + renderer this builds the behavioral wiring on top of); ADR-031/032 (the unchanged substrate); plan `docs/plans/workstreams-phase-3.md`; design `workstreams-design-v2-2026-05-30.md` §6 (Phase 3/4).

## Context

ADR-045 (Phase 1+2) landed the *schema* (`item-committed`/`item-shipped`/`item-blocked` event types + optional `tier`/`serves_item_id` on `branch-opened` + `session-bound`) and the four-tier *renderer*. What it did not do is *emit* those lifecycle events from the Dispatch-side writer, nor assign lifecycle states to the ~62 pre-existing items. Without emission the new states are inert — every spawn still only wrote `branch-opened`/`concluded`, so the Session→WorkItem link and the shipped transition never populated. This ADR records the Phase-3 behavioral wiring + the deferred Task-2b hook-filename rename.

## Decision

### 1. Emit the Session→WorkItem link from `--on-spawn`

The emit hook now parses an optional `Work-item:` sentinel in the spawn prompt (same line-prefix family as `Instructions:`/`Report-back:`):

- `Work-item: <id>` — the session serves an existing WorkItem. The child `branch-opened` carries `serves_item_id: <id>` and a `session-bound` event links the session to the child node.
- `Work-item: new — <kind>:<text>` (kind ∈ action|decision|question, default action) — the hook creates the item on the child branch (the matching kind event), sets `serves_item_id` to a deterministic new id, and emits `session-bound`.

A spawn **without** the sentinel is unchanged (backward-compat — branch-opened only); that item-less spawn is the candidate orphan the Phase-4 orphan filter surfaces.

### 2. Emit `item-shipped` from `--on-stop` on commit detection (best-effort)

The spawn/session-start ledger records the base commit SHA. At Stop, if `git rev-parse HEAD` moved since that base for a ledger entry carrying a `serves_item_id`, the hook emits `item-shipped` (evidence = HEAD SHA), ordered **before** `concluded` so FR-7 (no conclude with an unchecked item) lets a new-item branch conclude. Git-unavailable / unchanged-HEAD / no-serves ⇒ conclude only — never a false ship. The owning node of the served item is resolved from the snapshot (falls back to the child node; a reducer mismatch is a logged no-op, never a false mutation — NFR-2).

### 3. Backfill stamps `committed` only; in-flight/proposed stay render-derived

`scripts/lifecycle-backfill.js` classifies every existing work item into the four design buckets but **emits an event only for the `committed` bucket** (unchecked + no bound session). Rationale:

- The renderer already derives `shipped` (checked), `in-flight` (default for unchecked), and `blocked` (contested). The schema has events only for committed/shipped/blocked — there is no `item-in-flight`/`item-proposed` event. Storing what the renderer derives would be redundant; the honest, non-redundant job is to refine the default by stamping `committed` on parked items.
- `shipped` is deliberately **not** stamped for legacy checked items: emitting `item-shipped` would set `shipped_ts = now`, falsely surfacing every old item under "Recently shipped (7d)". Legacy checked items render as shipped via the renderer's derivation and are correctly excluded from the recent window.
- `session-bound` is new in Phase 3, so no legacy item has a bound session — bucket-2 (in-flight) is empty for existing data and bucket-3 (committed) absorbs all unchecked items. That is correct: nothing has a live session bound yet; the emit machinery populates in-flight going forward. Applied to live state: 62 `item-committed` events, attestation intact.

### 4. Hook-filename rename via shims, not symlinks (Task 2b)

The six hooks (`conversation-tree-*.sh` + `conv-tree-emit-reconciler.sh`) were `git mv`'d to `workstreams-*.sh`. Backward-compat is via **delegating shim scripts** at the old names (`exec bash .../workstreams-X.sh "$@"`), not symlinks — symlinks are unreliable on Windows (admin/developer-mode required). The shims keep the load-bearing Dispatch gates working even if a cached `settings.json` still references old names, which de-risks the settings rewrite the prior session deferred as highest-blast-radius. Runtime state paths (`.claude/state/conversation-tree/`, the emit log/ledger dirs) are intentionally unchanged — only FILENAMES renamed. Shims deletable 2026-06-30.

## Alternatives Considered

- **Add `item-in-flight` / `item-proposed` event types** so the backfill stamps all four states explicitly — rejected: additive churn for states the renderer already derives correctly; violates derive-don't-store (ADR-045 §2 "state is derived, not stored").
- **Stamp `item-shipped` for legacy checked items** — rejected: pollutes "Recently shipped (7d)" with a false now-ts; the renderer already shows them shipped.
- **Symlinks for backward-compat** — rejected: Windows-unreliable; delegating shims are robust and equally cheap.
- **Rewrite live `settings.json` as the load-bearing step** — unnecessary given shims; the shims make the settings rewrite non-urgent cleanup (done anyway, validated as JSON).
- **Agent-View reconciler (`agent-view-reconciler.js`, in the v2 Phase-3 list)** — deferred out of this session's primary work list.

## Consequences

- Spawns that declare a work item now populate the Session→WorkItem provenance link; concluding sessions that committed mark their served item shipped (best-effort, reliable child-side where HEAD reflects the worktree's commits).
- The dashboard's "In flight" filter now means "has a live bound session" rather than "any unchecked item"; parked work reads as `committed`. The dry-run + review gate (run before apply) is the safety on the one-time reset.
- Enables the Phase-4 orphan/shipped views to operate on real lifecycle data; the hard-block orphan gate (deferred) is the next teeth-bearing phase.
- The hook rename is non-breaking (verified: self-tests pass via both new names and old shims); the personal-mirror sync of all this is **deferred, blocked on the fork-reconciliation Misha-decision** (`docs/discoveries/2026-05-27-neural-lace-fork-deep-dive-and-sync-strategy.md`).

## Refutation criterion

The "no false ship" claim (item-shipped only on real commit movement) would be REFUTED by an `item-shipped` event appearing for a session that made no commit — covered by self-test ST36 (no commit → 0 item-shipped). The "rename is non-breaking" claim would be REFUTED by a gate self-test failing via the old shim path — covered by the dual-path self-test run (emit/state-gate/stop-gate all green via both names).
