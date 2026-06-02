# Task 10 — Walking Skeleton Evidence (builder-authored)

Plan: docs/plans/decision-context-gate-2026-05-29.md
Task: 10 — Walking Skeleton: live end-to-end fence → tree → reply → resolved round-trip
Branch: worker-10-walking-skel (from origin/feat/decision-context-gate-2026-05-29 @ dc7af21)
Rung: 2 (comprehension articulation required)

## Artifacts shipped

- `neural-lace/conversation-tree-ui/state/walking-skeleton-decision-context.sh` — replayable script (executable, idempotent, cleanup-on-failure via `trap EXIT`).
- Evidence captures (sibling to live `state.js`; retained for review):
  - `tree-state.before-ws.json` — pre-run snapshot of live state.
  - `walking-skeleton-final-state.json` — post-round-trip snapshot showing the 5 WS-1 events in `events[]` AND the WS-1 node in `snapshot.nodes[]`.
  - `walking-skeleton-api-state.json` — GUI `/api/state` response captured while WS-1 was visible (timing window: between stage 4 snapshot and stage 5 restore).

## Run output (clean run, two consecutive invocations)

Both runs printed:

```
WALKING SKELETON: PASS — WS-1 decision-raised + item-details-set + answered events confirmed in state file at .../neural-lace/conversation-tree-ui/state/tree-state.json
  events: decision-raised=1  item-details-set=1  answered=1
  item_id:            item-WS-1
  GUI /api/state:     ... (CONFIRMED (WS-1 visible in /api/state nodes[]))
```

Live `tree-state.json` is `diff -q`-identical to `tree-state.before-ws.json` after both runs (cleanup-trap-driven restore works).

## WS-1 round-trip in the final-state snapshot

```
branch-opened     event_id=01KSYCT83NDZV4X8X7EKS39YKD  node_id=dc-decision-WS-1
decision-raised   event_id=dc-dr-WS-1                  item_id=item-WS-1  node_id=dc-decision-WS-1
item-details-set  event_id=dc-ids-WS-1                 item_id=item-WS-1  node_id=dc-decision-WS-1
answered          event_id=dcre-an-2b52c524244c009dfe36966a  item_id=item-WS-1  node_id=dc-decision-WS-1
item-details-set  event_id=dcre-ds-2e721faed7524c0e8f5f31fa  item_id=item-WS-1  node_id=dc-decision-WS-1
```

`snapshot.nodes[]` contains node `dc-decision-WS-1` with `item-WS-1` flagged `checked: true`.

## In-flight scope updates surfaced

The Walking Skeleton uncovered an orchestration gap in `decision-context-gate.sh`: when the gate validates a fence with a fresh `id`, it emits `decision-raised` with `node_id="dc-decision-<id>"` but does NOT first emit `branch-opened` for that node. The reducer's `decision-raised` arm requires `findNode(snap, ev.node_id)` to resolve, so it silently rejects the item from `snapshot.nodes[]`. The event persists in `events[]` (which is what the gate's own ST2/ST11 self-tests count), but the snapshot has no item, so the reply hook (which reads `snapshot.nodes`) sees nothing to match.

**Surface, not fix.** The Walking Skeleton works around this by pre-seeding the WS-1 branch via the `state.js` facade (`appendBranchOpened`) in stage 1.5 before invoking the gate. The underlying gate behavior is a separate concern — flagged here as a candidate for `docs/backlog.md` (proposal: gate emits a `branch-opened` for any new `node_id` prefix it owns, OR the orchestration moves to a sibling hook). Per orchestrator-pattern rules I did not amend the gate from this builder dispatch.

## Pre-flight setup performed in worktree

The worktree at agent-a984454780921eb76 lacked `node_modules/zod` (gitignored, not propagated from main repo on worktree checkout). `npm install --no-audit --no-fund` from `neural-lace/conversation-tree-ui/` resolved this in 2s. Without zod, the gate falls back to NOENV branch and the schema is bypassed — masking exactly the bug above. This installation is per-worktree machine state, not committed; future runs from a fresh worktree will need the same step (a documentation gap for the parent plan to address if Walking Skeleton is to run in CI / fresh worktrees).

## Task 10 — Comprehension Articulation (builder-authored)

### Spec meaning

Build a self-contained, idempotent, replayable script demonstrating that the entire decision-context substrate works end-to-end LIVE against the same `tree-state.json` the GUI reads. "Works" means: a fenced `::: decision id=WS-1 …` block in a synthetic transcript, passed through `decision-context-gate.sh` as a Stop-event payload, produces a `decision-raised` + `item-details-set` event that lands in the live state and is visible to the GUI; a subsequent UserPromptSubmit-shaped invocation of `decision-context-reply-emit.sh` carrying the fence's `reply_with` phrase produces an `answered` event for the same item; and after capturing evidence, the live state is restored bit-identical to its pre-run bytes so the GUI's observable state is unchanged. Walking Skeleton (Task 10) is the proof-of-life — Wave 4 cannot start until this PASSes.

### Edge cases covered

- **Script run from a worktree where `tree-state.json` is gitignored.** `_resolve_live_state` uses `git rev-parse --git-common-dir` (parent of `.git/worktrees/<wt>`) to find the main repo's checkout, then prefers `neural-lace/conversation-tree-ui/state/tree-state.json` (nested) over the flat fallback. Mirrors `conversation-tree-emit.sh`'s `_resolve_gui_state_path` logic.
- **Mid-script failure leaves live state mutated.** A `trap _cleanup EXIT INT TERM` always runs the restore (`cp $BACKUP_FILE $LIVE_STATE`) regardless of which stage failed. The restore is gated on `RESTORE_NEEDED=1` so an early pre-flight failure (before backup) doesn't try to restore from a non-existent backup.
- **GUI is not reachable.** The GUI check uses `curl -sf -m 2` against `/api/health`; on connection failure or timeout the script records `GUI_RESULT="NOT-REACHABLE"` and continues to the snapshot stage. The PASS summary's GUI line then reads `NOT-REACHABLE` and the API state file is not written. The PASS verdict does NOT depend on GUI reachability.
- **State file corruption mid-demo.** The backup is JSON-validated immediately after copy (`node -e 'JSON.parse(...)'`). If the live state was already corrupt at start, the script aborts BEFORE setting `RESTORE_NEEDED=1`, so the script never restores garbage over good state. If corruption happens after stage 1 (e.g., facade write race), the restore copies the verified-valid backup back — repairing the corruption as a side effect.
- **Idempotent re-runs.** Each invocation creates a fresh `mktemp -d` for synthetic transcripts. Event IDs the gate emits are deterministic per (category, id) so a re-fire against the same backup state produces the same events (facade dedupes per-file on `event_id`). The script's verification accepts `>= 1` for each event count, not `== 1`, so a second run that sees the same idempotent events still PASSes. Confirmed by running back-to-back.
- **Zod missing in the worktree.** Pre-flight does not explicitly check for zod; instead the gate's emit log surfaces it (`schema-require:Cannot find module 'zod'`) and the script's verification step catches the consequence (`decision-raised: 0` because the gate fell back to NOENV path and didn't emit). The first script run hit this and FAILed loudly with a clear diagnostic in the gate log; fixing it required only `npm install` in the worktree.

### Edge cases NOT covered

- **Concurrent runs against the live state.** Two parallel invocations would race on the backup/restore pair; the second could restore the first's stale backup. The script assumes serial execution and does not take a lock. Acceptable for a manual walking-skeleton demo; production CI would need a `flock` on the live state directory.
- **Reducer-rejection invisibility.** The script DETECTED the reducer-rejection bug (via the reply-hook FAIL) and worked around it with a preseed, but did not fix the underlying gate. A future fence with a fresh `id` not seeded by an external orchestrator will still silently lose its item from `snapshot.nodes[]`. Flagged for backlog above.
- **Multi-category coverage.** Only the `decision` category is exercised. `question`, `action_item_for_user`, `autonomous_action` follow the same code path and the gate's own ST11 self-test covers all four categories, but the Walking Skeleton's LIVE round-trip evidence is decision-only. Extending to all four is straightforward (loop the fence-emit stage) but out of scope for the proof-of-life acceptance.
- **GUI WebSocket / SSE event delivery.** The script confirms WS-1 appears in `/api/state` (HTTP poll) but does not assert that the GUI's live event stream delivers it. The GUI's reactive update is a separate concern and not in Task 10's scope per the plan.

### Assumptions

- The user's main checkout is at `~/claude-projects/neural-lace` and `git rev-parse --git-common-dir` from the worktree returns its `.git` correctly. If the user has a non-standard layout (e.g., multiple parallel checkouts of neural-lace), the resolver may pick the wrong one; the script does not currently warn on this.
- The live `tree-state.json` is writable by the script's user. Both the Walking Skeleton's preseed and the gate's `appendEvent` go through `state.js`'s atomic `writeFileSync(tmp, ...) + rename` publish. Permission errors would surface as a `_die "preseed failed"` or a gate exit-2 with a clear node stack in stderr.
- `node` and `jq` are on PATH (pre-flight asserts this and `_die`s otherwise).
- The hooks at `~/.claude/hooks/decision-context-gate.sh` and `~/.claude/hooks/decision-context-reply-emit.sh` are the current versions matching the worktree's schema module. If the user has stale hooks installed from before Wave 2/3 wiring, the script's behavior is undefined; pre-flight does not version-check them.
- The reply hook's `reply_with` phrase matching is case-insensitive substring; the chosen phrase `"go with option A"` is unambiguous within the live state's existing prompts (no other open item has a similar `reply_with`). The deterministic preseed of `dc-decision-WS-1` ensures the matched item is always the Walking Skeleton's own — not an accidental hit on an unrelated existing decision.
