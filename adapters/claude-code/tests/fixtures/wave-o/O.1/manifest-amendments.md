# O.1 manifest amendments (for the orchestrator's serial integration)

Per specs-o §O.0.1 rule 1, the O.1 builder does not edit
`adapters/claude-code/manifest.json` directly. This fragment lists the
new entry + `honest_status` amendments this task's work requires, for
the orchestrator to fold in at batch-1 integration.

## 1. NEW entry — `observability-consumer-map` (contract C3 governed artifact)

`observability-consumer-map.json` (new, top-level under
`adapters/claude-code/`) is a governed data artifact, not a hook —
closest existing precedent in this manifest is a `surfacer`-kind entry
with `hooks: []` for a hook-less unit is NOT valid per the schema
(`kind` enum requires one of gate/writer/surfacer/pattern/convention, and
`hooks` may be empty only for pattern/convention kinds per the schema
description: "Empty for pattern/convention units"). Recommend `kind:
"convention"` (a per-surface data contract every O.1+ emit call site
adheres to, enforced downstream by O.6's doctor predicate rather than by
a hook of its own):

```json
{
  "id": "observability-consumer-map",
  "kind": "convention",
  "doctrine_file": "doctrine/observability.md",
  "hooks": [],
  "events": [],
  "wired_template": false,
  "selftest": false,
  "jit_triggers": {
    "paths": ["observability-consumer-map.json"],
    "keywords": []
  },
  "blocking": false,
  "budget_class": "none",
  "honest_status": "Data contract (specs-o §O.0.3 contract C3): every signal-ledger event type observed in the ledger or emitted anywhere in the repo MUST have >=1 named entry here (law 2). Seeded by O.1 (batch 1) with all 18 known types (8 pre-existing + 10 Wave-O new); enforced by O.6's check_obs_consumer_map doctor predicate (not yet landed as of O.1 — batch 2). doctrine/observability.md is O.3's deliverable (not yet landed as of O.1) — until it lands, doctrine_file above is a forward reference; if the orchestrator integrates O.1 before O.3, either land this entry with doctrine_file: null for now and fix it up when O.3 merges, or hold this specific field edit until both are in."
}
```

NOTE: if O.3 has not yet merged when the orchestrator integrates O.1,
set `doctrine_file: null` here instead (schema allows null) and revisit
once `doctrine/observability.md` exists — do not point at a file that
does not exist yet on the merged tree.

## 2. `signal-ledger` — NEW entry recommended (no existing entry found)

Grep of the current manifest (`node -e "require('./manifest.json').entries.find(e=>e.id==='signal-ledger')"`)
returns nothing — `hooks/lib/signal-ledger.sh` has never had its own
manifest entry (it's a shared lib, covered by the `hooks/lib/` sync-as-
a-unit convention per the E.10 precedent: "libraries are not
independently manifest-entried ... since hooks/lib/ is synced as a unit
by install.sh and covered by check_lib_deps"). O.1 does NOT add a new
lib file here (it extends the existing `signal-ledger.sh` with
`ledger_emit_typed` + a comment registry) — no new manifest entry
required for this reason. Recommend NO CHANGE for this file.

## 3. `stop-verdict-dispatcher` — honest_status unaffected

Current entry's `honest_status` describes E.11 aggregation behavior
(3 member gates, replaces 3 blocking Stop entries). O.1's edits (member
timing + turn-trace/session-stop emission) are additive observability,
not a change to the gate's blocking/aggregation contract — no
`honest_status` correction required. Recommend NO CHANGE.

## 4. `workstreams-stop-writer` — honest_status unaffected

Same reasoning: O.1 added member timing + a turn-trace emit to the
existing writer loop; the writer's never-blocks contract and member list
are unchanged. Recommend NO CHANGE.

## 5. `session-start-digest` — honest_status unaffected

O.1 added one marked `session-start` emit call at the top of
`run_digest()`; the digest's 16-feed structure and 15-line cap are
unchanged. Recommend NO CHANGE.

## 6. `pre-compact-continuity` — honest_status unaffected

O.1 added one marked `session-compact` emit call inside
`_run_precompact()`; the six-category instruction mechanism and its
PROVEN/HYPOTHESIZED channel status (per that file's own MECHANISM PIN)
are unchanged. Recommend NO CHANGE.

## 7. `workstreams-emitters` — honest_status unaffected

O.1 added `spawn-dispatched`/`spawn-concluded`/`bg-task-started` emit
lines to `workstreams-emit.sh`'s existing `--on-spawn`/`--on-stop`/
`--on-builder-dispatch` modes. The entry's existing `honest_status`
("workstreams-emit.sh wired directly ... Stop-side members dispatched
via workstreams-stop-writer.sh since D.5") remains accurate — no
wiring change, only additive ledger emission inside already-wired call
paths. Recommend NO CHANGE.

## 8. `session-resumer` — honest_status unaffected

O.1 normalized this script's ledger event names to contract C2
(session-resume/throttle-detected), preserving the original vocabulary
verbatim in ledger detail text and leaving the digest-feed side (its own
separate, pre-existing consumer) completely unchanged. The entry's
existing `honest_status` (OS-scheduled watchdog, schtasks registration
is an orchestrator step) is accurate and unaffected by this event-name
normalization. Recommend NO CHANGE.
