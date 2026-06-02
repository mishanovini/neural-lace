# Task 4 / B10-FU-1 — Comprehension Articulation (builder-authored)

**Branch:** `worker-b10fu1-fix` (off `origin/feat/decision-context-gate-2026-05-29` HEAD `dc7af21`)
**Scope:** focused-scope fix for B10-FU-1 production-correctness defect in
`adapters/claude-code/hooks/decision-context-gate.sh` (Stop hook emission
path) plus the Walking Skeleton script that masked the bug.

## Spec meaning

The orchestrator-assigned spec is B10-FU-1: the gate's `decision-raised`
emit path generates fresh per-decision node-ids (`dc-decision-<id>`,
`dc-question-<id>`, etc.). Per ADR-032 §3 (FR-2 cardinality) items live ON
a node — multiple items on one node form one branch. The reducer's
`decision-raised` arm requires the `node_id` to resolve via `findNode`
against existing `snapshot.nodes[]`; fresh ids never resolve, so the
reducer silently drops the item from `snapshot.nodes[]` even though the
event persists in `events[]`. The fix is to emit against the **session-root
node** (the project/global root that `conversation-tree-emit.sh
--on-session-start` seeds), defensively emit `branch-opened` for the root
first (idempotent on event_id per ADR-032 §2 so re-emission is safe), and
keep the per-decision `item_id` so items[] stays multi-valued. The Walking
Skeleton (which previously preseeded the WS-1 branch — masking the bug
exactly) is re-run *without* manual preseed and instead uses
`conversation-tree-emit.sh --on-session-start` to mimic the production
session-start path.

## Edge cases covered

- **`--on-session-start` did not fire before the gate.** Self-tests and
  replay-from-`fallback.jsonl` invocations bypass session-start. Covered
  by the gate's *defensive* root `branch-opened` (emit JS, lines 461-470
  of `adapters/claude-code/hooks/decision-context-gate.sh`): event_id is
  `dc-bo-<sha1(root_id)>` (deterministic, content-addressed), so on a
  session that DID see session-start, the facade dedupes the re-emit per
  ADR-032 §2 idempotency contract. Verified by `ST12` self-test PASS
  (no prior session-start in the test).
- **Multiple decisions in one session.** All four fence categories attach
  to the same root (`ROOT_ID`); each gets a distinct `item_id` (`item-<id>`),
  so `root_node.items[]` grows by one per fence. Verified by ST11 self-test:
  all four event types (`decision-raised`, `question-raised`, `action-added`,
  `autonomous-action-logged`) emitted against the same root produce 4
  distinct items in events[]. (ST11 explicitly counts event types; the new
  ST12 + WS round-trip together prove the snapshot.nodes[] projection.)
- **Cwd outside any `claude-projects/<slug>/` path.** `_project_root`
  returns `global\tglobal` per the gate's existing logic (line 203-205);
  the defensive branch-opened then targets `node_id="global"` and the
  item lands there. Verified implicitly by the gate self-test which runs
  from `/tmp/...` (no `claude-projects/` ancestor) — items land under
  `global` and ST12 finds `item-db-choice` in `snapshot.nodes[].items[]`.
- **`fallback.jsonl` replay path** (`NOENV` branch). The stub event
  previously emitted with `node_id="dc-unparsed"` which would also have
  been dropped on replay. Fix: stub now uses `$ROOT_ID` so on replay the
  branch-note-add lands on the session-root that downstream tooling can
  resolve.
- **Worktree vs main-repo cwd.** The WS uses `_resolve_live_state` to find
  the main-repo `tree-state.json`; `_project_root` in the gate uses `$PWD`
  which, when the gate runs from a worktree as a Stop hook, still hits the
  `claude-projects/<slug>` prefix match (`PWD` in a worktree starts with
  `claude-projects/neural-lace/.claude/worktrees/...`), so the project slug
  is correctly derived. Confirmed by WS run from main-repo cwd: root_id is
  `proj-neural-lace`.

## Edge cases NOT covered

- **Reducer changing item-id collision semantics.** The fix assumes
  `item_id` collisions across multiple fence emissions with the same id
  are caught by the reducer's `findItem(node, ev.item_id)` early-return
  (reducer.js line 91 — `'item_id already exists on node'`). I did not
  change this contract; if a session re-emits a fence with the same id,
  the second event is silently rejected. Out of scope for B10-FU-1 (the
  primary-event `event_id` is also deterministic per `(category, id)`,
  so the facade ALSO dedupes by event_id before the reducer sees the
  duplicate — defense in depth).
- **Stop-hook firing after a session that NEVER ran session-start in the
  current state file.** The defensive root branch-opened covers this, but
  if `_project_root` returns a different slug across runs (e.g., a
  rebooted laptop with different `$PWD`), each variant creates its own
  root node. Acceptable: the user sees both roots in the GUI and can
  archive the stale one manually. Not a correctness defect.
- **Concurrent session-start and gate emission racing on the same root.**
  The facade's atomic publish (per ADR-032 §2) plus deterministic
  event_id make this a no-op for correctness (both writes produce
  byte-identical event objects). Performance impact (duplicate facade
  call) is negligible.

## Assumptions

- The reducer's `decision-raised` arm continues to require `findNode`
  resolution and reject events whose `node_id` does not exist in
  `snapshot.nodes[]` (verified at reducer.js line 89-90). If this contract
  changes, the fix becomes dead code but does not regress.
- `appendEvent` in `state.js` (facade entry-point) deduplicates by
  `event_id` per ADR-032 §2 atomic publish. Verified by inspection: the
  `_emit_to_sink` node bridge calls `s.appendEvent(evs[i], ...)` which
  delegates to `store.appendEvent` with idempotency-on-event_id.
- `conversation-tree-emit.sh --on-session-start` is wired in
  `settings.json` for production sessions (Wave 3 wiring at commit 66ef445
  on this branch). Sessions without the wiring are the bypass case the
  defensive branch-opened covers.
- The gate's pre-existing `_project_root` helper (lines 189-206) returns
  the same `proj-<slug>\t<title>` shape as
  `conversation-tree-emit.sh::_project_root`. Verified by side-by-side
  reading; both copy the same logic.
- The `node -e '...'` heredoc is single-quoted, so JS comments cannot
  contain apostrophes. Fix applied: rewrote comments to use ASCII
  alternatives (`sec.2`, "node items[] array").

## Mechanical-check log

| Check | Result |
|---|---|
| `bash adapters/claude-code/hooks/decision-context-gate.sh --self-test` | **27/27 PASS** (was 25/25; +ST12 scenario adds 2 assertions: exit 0 + item-in-snapshot) |
| `bash neural-lace/conversation-tree-ui/state/walking-skeleton-decision-context.sh` | **PASS** — round-trip via `--on-session-start` seed (no manual preseed); decision-raised=1, item-details-set=1, answered=1; `snapshot.nodes[].items[].item_id="item-WS-1"` present, `checked=false` pre-reply → `checked=true` post-reply; GUI `/api/state` CONFIRMED |
| `diff -q adapters/claude-code/hooks/decision-context-gate.sh $HOME/.claude/hooks/decision-context-gate.sh` | identical |
| Live state restored on WS exit | verified — restore-on-trap fires; GUI observable state unchanged |
| Branch | `worker-b10fu1-fix` off `origin/feat/decision-context-gate-2026-05-29` (HEAD `dc7af21`) |

## Files modified

- `adapters/claude-code/hooks/decision-context-gate.sh`
  - `_parse_validate_emit_events_file` now takes `root_id` + `root_title`
    args; node-bridge prepends defensive `branch-opened` for the root;
    per-block primary events use `nodeId = rootId` (was
    `"dc-" + cat + "-" + data.id`); `item_id` unchanged (per-decision).
  - `_run_gate` computes `ROOT_ID` / `ROOT_TITLE` from `_project_root`
    and passes them to the emit function.
  - Fallback stub event now uses `$ROOT_ID` (was `"dc-unparsed"`) so
    replay lands on a resolvable node.
  - Added ST12 to `_self_test`: emits a fence and asserts the item
    appears in `snapshot.nodes[].items[]` (the exact reducer projection
    that the bug skipped).
- `neural-lace/conversation-tree-ui/state/walking-skeleton-decision-context.sh`
  - **New file on this branch** (was originally on a different worker
    branch `worker-10-walking-skel`; the WS is in B10-FU-1's scope per
    the in-flight addition because B10-FU-1 fixes the bug it masks).
  - Stage 1.5 rewritten: removes the manual `appendBranchOpened` preseed;
    invokes `~/.claude/hooks/conversation-tree-emit.sh --on-session-start`
    with a synthetic session-start event to mimic the production path.
  - Stage 2 verification extended: asserts `snapshot.nodes[].items[]`
    contains `item-WS-1` with `checked=false` (LOAD-BEARING — the check
    the bug would have failed).
  - Stage 3 verification extended: asserts `checked=true` in the snapshot
    after the reply-emit hook fires.

## In-flight scope notes

- The Walking Skeleton script (`walking-skeleton-decision-context.sh`)
  did not previously exist on `origin/feat/decision-context-gate-2026-05-29`
  (HEAD `dc7af21`); it lived on a separate worker branch. Adding it here
  is the appropriate place because B10-FU-1 fixes the masking bug it
  exhibited. The orchestrator should add this to the plan's
  `## In-flight scope updates` section before Wave 4.
