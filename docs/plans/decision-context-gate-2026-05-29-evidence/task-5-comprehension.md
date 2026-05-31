# Task 5 — Pending-surfacer hook evidence

## Task 5 — Comprehension Articulation (builder-authored)

### Spec meaning

Task 5 ships a SessionStart hook that scans the attestation-aware conversation-tree state for unresolved items emitted by the decision-context-gate (stamped by `details.surfaced_by == "decision-context-gate"`), and on each session start emits one system-reminder per item whose current revision differs from the per-session "seen" marker. The hook ALSO drains Tier-2 follow-up markers at `~/.claude/state/decision-context-followup-*.txt` (fresh = under 24h) emitting a single "previous-turn weak signal" reminder per drain. The mirror at `~/.claude/hooks/` is byte-identical. The hook is a non-blocking WRITER (always exits 0); failures isolate to the audit log at `~/.claude/logs/decision-context-pending-surfacer.log`.

### Edge cases covered

- **ST1 no state file** — silent exit 0; surfacer must not noise on fresh projects (lines 264-270, the `[[ ! -f "$lib" ]] || [[ ! -f "$sink" ]]` short-circuit).
- **ST2 zero pending + zero markers** — silent (lines 281-301, the `items_tsv` empty + no marker emit branch).
- **ST7 archived nodes** — items NOT surfaced; the node-iterator skips `node.state === "archived"` inside the node-side `_list_pending_items` filter.
- **ST9 facade-down (broken `CONV_TREE_STATE_LIB`)** — silent exit 0; the node `try { require(libPath); } catch` path logs LIBERR and exits 0 inside the subprocess, with caller treating empty output as "no items."
- **Corrupted seen-file** — JSON.parse failure inside `_read_seen_file` swallows the error; the empty associative array means every item gets re-surfaced (safe rebuild, no stale-suppression).
- **Stale follow-up marker (>24h old)** — silently deleted without emitting a reminder (`_drain_followup_markers` `(( age > max_age_s ))` branch).
- **Empty snapshot read (transient/zero items)** — leaves existing seen-file alone (line 303 `if [[ -n "$new_seen_tsv" ]]`); we do not clobber prior seen-state on an empty read.
- **Snapshot verification posture** — production state today returns `verified: false, reason: "no-attestation"` because `snapshot-committed` events aren't yet live-emitted; the surfacer is informational (not a gate) so it only refuses on `torn`/`tampered`/`hash-mismatch` reasons, passing `no-attestation` through. This is the explicit deviation from the conv-tree-state-gate/stop-gate posture — documented inline at lines 144-152.

### Edge cases NOT covered

- **Task 4's gate does not yet stamp `details.surfaced_by == "decision-context-gate"`.** This surfacer's filter is keyed on that exact stamp. If Task 4 ships without emitting an `item-details-set` event carrying `surfaced_by: "decision-context-gate"` (and an optional `reply_with`), this surfacer will silently surface zero items in production despite working perfectly in self-test. **Dependency assumed; surface to orchestrator for cross-task coordination.** If Task 4 has already landed with a different stamp value (e.g. `source: "decision-context-gate"`), this surfacer needs a one-line filter update at the node-side `surfaced_by !== "decision-context-gate"` check.
- **Tree-view URL base** — hardcoded to `http://127.0.0.1:7733/#node=<id>` per orchestrator instruction. If the operator runs the GUI on a different port, that link will 404 — override via `DCPS_TREE_VIEW_BASE` env var, but there's no auto-detect.
- **Per-session seen-file growth** — never pruned. A long-lived session that surfaces hundreds of decision-context items accumulates a multi-KB JSON file. Acceptable for v1; pruning when items become checked is a future enhancement.
- **Multi-machine sync** — seen-files are per-machine, not shared. Two machines surfacing the same plan would re-surface independently. Out of scope for this hook.

### Assumptions

- **Task 4's stamp value.** This hook depends on Task 4's decision-context-gate emitting `item-details-set` events whose `details.surfaced_by` field equals the literal string `"decision-context-gate"`. The plan's Task 5 brief instructs this assumption be documented; if Task 4 uses a different convention, a one-line edit at the node `if (surfaced_by !== "decision-context-gate") continue` line aligns the filter.
- **State.js facade `verifySnapshotAttested` returns `{ verified, reason }` with `reason ∈ { "no-attestation", "torn", "tampered", "hash-mismatch:<details>", ... }`.** Verified empirically against production state file (`no-attestation` is the live return today). The hook treats only `torn`/`tampered`/`hash-mismatch` as refuse-triggering; everything else passes through. Confirmed by reading `state.js` exports lines 83-85 and noting it delegates to `store.verifySnapshotAttested`.
- **Items have stable `item_id` across `item-details-set` updates.** The reducer's `findItem(node, ev.item_id)` lookup confirms this — re-emitting `item-details-set` for the same `item_id` updates `it.details` in place (last-writer-wins per reducer line 321). The seen-file's revision tracking keys on the LATEST `event_id` for any event with a matching `item_id`, so any modification (item-details-set, item-unchecked, action-responded) bumps the rev and re-surfaces.
- **Tier-2 follow-up markers are plain text files** with the path pattern `~/.claude/state/decision-context-followup-*.txt`. Their format is unspecified beyond "first non-empty line is human-readable context"; the surfacer reads at most 200 chars of the first non-empty line for the reminder.
- **`node` is available in PATH.** The hook degrades silently when `node` is missing (`_have node || return 0` guards every facade call); production rollout assumes a working Node install (consistent with all other conv-tree hooks).

## Self-test result

```
self-test: 15 passed, 0 failed
self-test: OK 15/15
```

Scenarios: ST1 (no state file), ST2 (zero pending + zero markers), ST3 (one item + missing seen-file, 4 assertions), ST4 (re-invocation unchanged), ST5 (item-details-set bumps rev), ST6 (follow-up marker drained, 2 assertions), ST7 (archived node), ST8 (multiple items, 3 assertions), ST9 (broken facade).

## Mirror

Byte-identical: `diff -q adapters/claude-code/hooks/decision-context-pending-surfacer.sh $HOME/.claude/hooks/decision-context-pending-surfacer.sh` returned no output.

## Harness-hygiene

`harness-hygiene-scan.sh` exit 0 against the new hook.
