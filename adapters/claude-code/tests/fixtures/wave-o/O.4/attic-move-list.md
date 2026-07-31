# O.4 attic move list (specs-o §O.4 deliverable 4 — salvage-before-reset)

Builder: build/wave-o-o4. Orchestrator-applied (this builder's fragment
scope excludes `attic/` moves under `adapters/claude-code/` — those are
harness-hook files this builder does not own; `workstreams-ui/**` attic
moves listed separately below WERE made directly by this builder, since
`workstreams-ui/**` is this task's owned surface per the dispatch map).

## adapters/claude-code/ moves (orchestrator applies)

| From | To | Reason |
|---|---|---|
| `hooks/workstreams-state-gate.sh` | `attic/workstreams-state-gate.sh` | Retired gate; ONLY consumer (workstreams-ui tree-state read) replaced by derived-truth reads. See manifest-amendments.md Entry 1. |
| `hooks/workstreams-extract-pending.sh` | `attic/workstreams-extract-pending.sh` | Superseded by needs-you.sh (per its own header). See manifest-amendments.md Entry 2. |
| `hooks/workstreams-turn-emit.sh` | `attic/workstreams-turn-emit.sh` | Never wired to settings.json.template; item-extraction superseded by needs-you.sh. See manifest-amendments.md Entry 3. |

Verify no OTHER file still shells these three directly before moving (grep
`workstreams-state-gate\.sh\|workstreams-extract-pending\.sh\|workstreams-turn-emit\.sh`
across `adapters/claude-code/` excluding the manifest/template entries this
fragment set already accounts for). This builder's own repo-wide grep at
authoring time found:
- `workstreams-state-gate.sh`: only the two settings.json.template entries
  (template-wiring.md removes both) + the manifest.json entry
  (manifest-amendments.md Entry 1).
- `workstreams-extract-pending.sh`: only `workstreams-stop-writer.sh`'s
  MEMBERS array (manifest-amendments.md Entry 2 companion diff) + the
  manifest.json hooks list (Entry 2).
- `workstreams-turn-emit.sh`: its own manifest.json entry (Entry 3,
  metadata-only update, no removal needed since it was never wired) +
  two DOC-COMMENT mentions (`hooks/lib/workstreams-state-resolver.sh`,
  `hooks/workstreams-emit.sh` — prose references, not code that invokes it;
  safe to leave as historical context or update opportunistically).

Re-run this grep at integration time (a Wave-O batch could have added a new
caller since this builder's snapshot) before executing the moves.

## workstreams-ui/ moves (ALREADY DONE by this builder — workstreams-ui/**
is this task's owned surface, not orchestrator-only)

| From | To | Reason |
|---|---|---|
| `workstreams-ui/web/responsive.selftest.js` | `workstreams-ui/attic/responsive.selftest.js.retired` | Asserted the pre-O.4 tree/accordion DOM structure, entirely replaced. See `workstreams-ui/attic/README.md`. |
| `workstreams-ui/scripts/regression.e2e.js` | `workstreams-ui/attic/regression.e2e.js.retired` | Puppeteer suite locking the pre-O.4 cockpit/drill/waiting DOM, entirely replaced. See `workstreams-ui/attic/README.md`. |

Nothing else under `workstreams-ui/` was deleted. `workstreams-ui/state/**`
(the event-sourced library: reducer.js, schema.js, store.js,
decision-context-schema.js, the backfill/migration one-off scripts) is
UNTOUCHED — it remains on disk, still used by `server/reconciler.js`'s
comparison-only read (`state/state.js`'s `readState`), and is NOT deleted or
attic'd, since the reconciler needs SOME tree-state reader for as long as
any tree-state file might still exist on an operator's machine. If a future
task fully removes the tree-state file from existence, `state/**`'s
retirement is that task's decision, not this one's.
