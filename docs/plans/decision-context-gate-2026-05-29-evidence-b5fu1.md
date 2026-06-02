# B5-FU-1 — Comprehension Articulation (builder-authored)

## Spec meaning

The Task 4 gate emits two events per validated fence block: a primary
event (decision-raised / question-raised / action-added /
autonomous-action-logged) and a sibling `item-details-set` carrying the
full payload. The Task 5 pending-surfacer (SessionStart hook) reads the
state and surfaces items where `details.surfaced_by ===
"decision-context-gate"`. Pre-fix, the gate never set that field — so
in production the surfacer would surface nothing, defeating Task 5's
purpose. The fix stamps `surfaced_by: "decision-context-gate"` on the
shared `details` object that flows into both emitted events.

## Edge cases covered

- All four fence categories (decision / question / action_item_for_user /
  autonomous_action) inherit the stamp because the stamp is added to the
  single `details` variable built at line 495 of
  `adapters/claude-code/hooks/decision-context-gate.sh`, BEFORE the
  per-category branch and BEFORE both `events.push` calls.
- Idempotent on Stop re-fire: the facade dedupes by `event_id`, and the
  stamped field is deterministic, so re-fires are no-ops.
- Walking Skeleton's WS-1 round-trip carries the stamp (verified via jq
  on `walking-skeleton-final-state.json`).
- ST28 self-test locks the contract: `item-details-set.details.surfaced_by
  === "decision-context-gate"` for the most-recent IDS event after a
  Tier-1 valid-fence transcript.

## Edge cases NOT covered

- Legacy `item-details-set` events written before this fix (e.g., prior
  WS runs in the live state file) retain `surfaced_by: null`. The Task 5
  surfacer correctly skips them (strict equality requires the stamp).
  Acceptable: legacy events were never intended to be surfaced via Task 5
  and the strict-equality check is the intentional gating.
- Fallback-replay path (`fallback.jsonl` drain in Task 8) — the fix
  applies because the same `details` object is what gets serialized into
  the fallback line, but the drain path wasn't separately exercised in
  this fix. Acceptable per scope; Task 8's own tests cover replay shape.
- Other emitters (`conversation-tree-emit.sh --on-spawn` etc.) do NOT
  stamp `surfaced_by` — out of scope; Task 5's surfacer is decision-
  context-specific by design and would not surface those anyway.

## Assumptions

- The `Object.assign({}, data, { _category: cat, surfaced_by: "..." })`
  pattern produces a stable JSON object that the schema's
  `safeValidateFence` does not reject (the stamp is an additive sibling
  field outside the validated payload structure; `_category` is the
  prior precedent for additive sibling fields).
- The Task 5 surfacer's strict-equality check on `surfaced_by` ===
  `"decision-context-gate"` is the exact contract — case-sensitive, no
  trailing whitespace, no alternate spellings. Verified by reading the
  surfacer source at lines 184-185 per the dispatch prompt.
- The state library's `readState` returns events in append order, so
  `idsEvents[idsEvents.length - 1]` is the most-recent
  `item-details-set` event for ST28's single-fence transcript. Verified
  empirically — `count=1` when ST28's transcript contains one fence
  block.
