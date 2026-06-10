---
title: No event-sourced text-repair path — mojibake frozen into canonical workstreams state
date: 2026-06-09
type: failure-mode
status: pending
auto_applied: false
originating_context: R5 builder (wf_6e2aa9d7-be2) mojibake diagnosis. 30 U+FFFD chars on node circuit-launch-sprint-2026-05-29 (10 items × text/background/the_ask). Corruption is upstream of canonical — the audit log carries EF BF BD at ingest (the 2026-06-09T07:23 migration read already-lossy text, likely em-dashes mangled by an earlier encoding hop).
decision_needed: Add an additive event type for text repair (item-text-set ['node_id','item_id','text'] + optionally branch-retitled ['node_id','title']) per ADR-032 §1 (additive within major 1, no bump)?
predicted_downstream:
  - neural-lace/workstreams-ui/state/schema.js (EVENT_TYPES + EVENT_REQUIRED_FIELDS)
  - neural-lace/workstreams-ui/state/reducer.js (new cases)
  - then emit corrections for the 10 affected items (details fields can ride the existing item-details-set)
---

## What was discovered
`EVENT_TYPES` (37 types) has NO title-update / item-text-update event, and the reducer rejects a
re-emitted `branch-opened` on an existing node_id (`reducer.js:73`). Consequence: a node title or item
text, once written, can never be corrected through the event-sourced facade — any ingest-time
corruption (here: 30 U+FFFD replacement chars, user-visible as "COORD � Cody") is permanently frozen.
Hand-editing the JSON is forbidden (attestation + sole-normative-writer design), so there is currently
NO legitimate repair path at all.

## Why it matters
The tracker's whole purpose is operator-readable truth; visibly-corrupted item text erodes trust in
the pane, and the class (no text-repair path) bites again on every future typo/encoding slip.

## Options
A. Add `item-text-set` (+ optionally `branch-retitled`) as additive event types per ADR-032 §1; emit
   corrections for the 10 affected items.
B. Accept frozen mojibake; fix only the details fields via existing `item-details-set`.

## Recommendation
A — small additive schema change, closes the class, ADR-032 explicitly permits additive types without
a major bump. The 10 corrections' source text is recoverable from the originating Dispatch transcript
or re-authorable from the circuit launch-sprint docs.

## Decision
(pending)

## Implementation log
(pending)
