## Task 7 — Comprehension Articulation (builder-authored)

### Spec meaning

Task 7 extends `adapters/claude-code/hooks/conversation-tree-emit.sh` so that when the Dispatch orchestrator spawns a child session, the emit hook detects `::: <category> id=… … :::` fenced blocks in the spawn prompt body and emits the matching ADR-032 §2 rich event combo (`decision-raised` / `question-raised` / `action-added` / `autonomous-action-logged` plus `item-details-set`) against the spawn's child node. The fence path COEXISTS with the pre-existing line-prefix sentinel path (`Instructions:` / `Recommendation:` / `Links:`) — both can fire for the same spawn. Failure isolation is preserved: any error in fence parsing, validation, or schema-module load silently falls back to sentinel-only behavior; the hook never blocks a spawn (writer, not gate).

### Edge cases covered

- Well-formed `decision` fence -> primary `decision-raised` event + sibling `item-details-set` event on the spawn's `sp-<hash>` child node. Asserted by ST32 (verifies counts: decision-raised=1, item-details-set=1).
- Legacy sentinel-only spawn (no fence): existing behavior unchanged; no decision-raised emitted. Asserted by ST33 (verifies decision-raised=0, branch-opened=2 = root+child).
- Malformed fence (decision missing required `options[]`): Zod validator rejects; fence-emit logs `NOEMITS` with the error; spawn branch-opened events still fire; exit 0 (writer isolation). Asserted by ST34.
- Multiple fences in one prompt (decision + autonomous_action): BOTH parsed and emitted; item-details-set fires for both categories (per gate-path parity). Asserted by ST35 (verifies decision-raised=1, autonomous-action-logged=1, item-details-set=2).
- Schema module unavailable (DECISION_CONTEXT_SCHEMA points at a missing file): fence path silently no-ops, legacy sentinel WARN about absent sentinels still fires, spawn branch-opened still fires, exit 0. Asserted by ST36.
- Cheap pre-check via `grep -qE '^:::[[:space:]]+\S'` short-circuits the node subprocess when no fence opener appears in the prompt, keeping the hot path fast for the common case (no zod load, no node fork).
- Idempotency: deterministic `event_id` is derived from `_hash16(nodeId + "|" + data.id)`, so a hook re-fire on the same spawn (same session_id, same hour bucket -> same child_id) produces byte-identical event_ids -> the state-library facade dedupes per-file (ADR-032 §2).
- All emissions route through `_emit_dual` -> `state.js appendEvent` — no parallel write path.

### Edge cases NOT covered

- Fence inside a fence (nested `:::` openers without an intervening closer) — the outer parser closes on the first plain `:::` line, so a malformed nested case treats the inner opener as part of the outer body. Tolerated; the schema validator will reject the malformed payload and the NOEMITS path applies. Worth a follow-up note but not in scope for Task 7.
- Streaming/partial prompts — the hook reads the full tool_input.prompt synchronously. Streaming spawn prompts are not on the current Dispatch surface, so no streaming path is required.
- Fence-emit for sub-agent `Task`/`Agent` spawns — explicitly out of scope per ADR-034 (sub-agents are AI-internal mechanics, not conversation branches). The hook's existing `_run_on_spawn` case statement already filters; the fence-emit only runs for Dispatch spawn surfaces.
- Cross-fence reference resolution (e.g., `connects_to: ["other-fence-id"]`) — the schema accepts the string array, but no consistency check between fences in the same prompt is performed. Acceptable: GUI does the cross-reference rendering.

### Assumptions

- Zod is available in `neural-lace/conversation-tree-ui/node_modules/zod` (installed at the conversation-tree-ui package root); the schema module requires it. Installed during Task 7 build via `npm install` in that package directory.
- The state-library `state.js` exports `appendEvent({statePath})` and the facade dedupes by `event_id` per ADR-032 §2 — the same assumption every other emit path in this hook makes.
- The spawn's child node_id `sp-<hash>` is derived from `_sha1(sid|title|hourbucket)` -> 12-char hex; re-fires within the same hour produce the same id. The fence-emit attaches events to that same `sp-<hash>`, so a re-fire is idempotent at both the spawn and fence layers.
- `_resolve_decision_schema()` mirrors `decision-context-gate.sh`'s `_resolve_schema_module()` resolution order, so writer and gate agree on the schema path.
- The `parseFenceBlock` parser and `safeValidateFence` dispatcher are the SOLE NORMATIVE entry points (Task 2 of the parent plan); no shell re-implementation.
