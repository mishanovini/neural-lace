---
title: Compacted workstreams state file is not self-contained (audit-log sidecar required)
date: 2026-06-09
type: failure-mode
status: pending
auto_applied: false
originating_context: R2 builder (wf_a6b13224-de6) copying the canonical tree-state.json to a test port — the copy rendered an EMPTY tree (647 nodes → 0) despite verifySnapshotAttested returning true.
decision_needed: Should store.readState trust an attested snapshot whose covers_through_event_id matches the last embedded event, without requiring the .audit.log sidecar? Or should copy/backup tooling be required to carry the sidecar?
predicted_downstream:
  - neural-lace/workstreams-ui/state/store.js (readState snapshot-trust path)
  - any backup/copy/migration tooling touching tree-state.json
---

## What was discovered
After compaction (events reduced to one snapshot-committed entry), `store.readState` only trusts the
embedded snapshot when `covers_through_event_id` matches the last DOMAIN event — which, for a
compacted file, lives in the `tree-state.json.audit.log` sidecar. Copying the JSON alone (without the
sidecar) replays to an EMPTY tree even though the snapshot is attestation-valid. Verified live by the
R2 builder on 2026-06-09.

## Why it matters
Backups, cross-machine copies, and test fixtures that grab only `tree-state.json` silently lose the
entire tree. The file LOOKS valid (attestation passes) — the worst failure shape.

## Options
A. readState falls back to trusting an attestation-valid snapshot when no audit log exists.
B. Document + enforce "the sidecar travels with the file" in every copy path (backup script, docs).
C. Compaction embeds enough event context to make the JSON self-contained.

## Recommendation
A or C (make the artifact self-contained); B alone leaves the silent-empty failure live.

## Decision
(pending)

## Implementation log
(pending)
