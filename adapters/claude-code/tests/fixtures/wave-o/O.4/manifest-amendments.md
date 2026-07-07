# O.4 manifest-amendments fragment — trust-path retirement (specs-o §O.4 deliverable 4)

Builder: build/wave-o-o4. Orchestrator-applied — this builder NEVER edits
`manifest.json` directly (§O.0.1-1). Schema: `schemas/manifest.schema.json`.

## Entry 1 — `workstreams-spawn-gate` (id, current manifest.json ~line 1935-1956): RETIRE

Current entry (verified live on this branch's O.3 baseline):

```json
    {
      "id": "workstreams-spawn-gate",
      "kind": "gate",
      "doctrine_file": "doctrine/workstreams-state.md",
      "hooks": [
        "workstreams-state-gate.sh"
      ],
      "events": [
        "PreToolUse"
      ],
      "wired_template": true,
      "selftest": true,
      "jit_triggers": {
        "paths": [
          "workstreams-ui/"
        ],
        "keywords": []
      },
      "blocking": true,
      "budget_class": "pretool",
      "waiver_path": "conv-tree-spawn-waiver-*.txt, fresh <1h, purpose-clause validated (lib/waiver-purpose-clause.sh) — explicitly modeled on bug-persistence-gate.sh."
    },
```

Replace with (mirrors the `workstreams-stop-gate` entry's own "retired, attic
+ shim" honest_status pattern already live in this same manifest at
id=workstreams-stop-gate):

```json
    {
      "id": "workstreams-spawn-gate",
      "kind": "gate",
      "doctrine_file": "doctrine/workstreams-state.md",
      "hooks": [
        "workstreams-state-gate.sh"
      ],
      "events": [
        "PreToolUse"
      ],
      "wired_template": false,
      "selftest": true,
      "jit_triggers": {
        "paths": [],
        "keywords": []
      },
      "blocking": false,
      "budget_class": "none",
      "honest_status": "retired at O.4 cutover (attic + exit-0 shim, per template-wiring.md fragment adapters/claude-code/tests/fixtures/wave-o/O.4/template-wiring.md) — the ONLY protected consumer (workstreams-ui's tree-state read) was replaced by derived-truth reads (nl <sub> --json); law 2 (EVERY-SIGNAL-HAS-A-CONSUMER) has no consumer left to protect. Closes NL-FINDING-024 at the root (the spawn writer -> gate PreToolUse race this finding describes can no longer fire). Blocking-gate budget 10/12 -> 8/12."
    },
```

Move `hooks/workstreams-state-gate.sh` to `attic/workstreams-state-gate.sh`
(exit-0 shim left at the original path if any other harness code still
`bash ~/.claude/hooks/workstreams-state-gate.sh`s it directly outside the
settings.json.template wiring being removed — grep-verify at integration
time before assuming a bare move is safe; the O.4 builder's own repo-search
found NO other direct callers beyond the two settings.json.template entries
this fragment's sibling `template-wiring.md` removes).

## Entry 2 — `workstreams-emitters` (id, current manifest.json ~line 1908-1933): member list update

The `workstreams-extract-pending.sh` member is superseded by `needs-you.sh`
(per that file's own header comment) and is retired to attic. It is invoked
from INSIDE `hooks/workstreams-stop-writer.sh`'s `MEMBERS` array (not its own
settings.json.template entry), so this is a manifest hooks-list edit +
a companion code change to `workstreams-stop-writer.sh` (below), not a
template-wiring change.

Current `hooks` array:
```json
      "hooks": [
        "workstreams-emit-reconciler.sh",
        "workstreams-emit.sh",
        "workstreams-extract-pending.sh",
        "workstreams-orchestrator-queue.sh",
        "workstreams-read.sh"
      ],
```

Replace with:
```json
      "hooks": [
        "workstreams-emit-reconciler.sh",
        "workstreams-emit.sh",
        "workstreams-orchestrator-queue.sh",
        "workstreams-read.sh"
      ],
```

Append to `honest_status` (currently: "workstreams-emit.sh wired directly
(SessionStart + spawn PreToolUse); Stop-side members dispatched via
workstreams-stop-writer.sh since D.5."):
```
 workstreams-extract-pending.sh retired to attic at O.4 cutover (superseded
 by needs-you.sh per its own header; item-extraction from Stop-time
 transcript scanning is no longer the mechanism — needs-you.sh add is the
 live sink). Removed from workstreams-stop-writer.sh's MEMBERS array in the
 same commit (see the companion code diff below).
```

### Companion code diff (NOT a manifest/template file — a hook-file edit
the orchestrator applies directly to `hooks/workstreams-stop-writer.sh`,
since this builder's fragment scope is manifest/template/doctor/install
only, and this is a change to the writer hook's own logic):

In `hooks/workstreams-stop-writer.sh`'s `MEMBERS` array (currently 6
entries), remove the `"workstreams-extract-pending.sh"` line:

```bash
MEMBERS=(
  "workstreams-stop-gate.sh"
  "workstreams-emit.sh --on-stop"
  "workstreams-task-binding.sh --on-stop"
  "workstreams-extract-pending.sh"        # <-- REMOVE this line
  "workstreams-emit-reconciler.sh"
  "workstreams-orchestrator-queue.sh"
)
```

And the matching self-test fixture list (same file, `--self-test` block,
the `_wsw_member_spec` loop) drops the `"workstreams-extract-pending.sh:silent"`
entry. `workstreams-stop-gate.sh` STAYS in this MEMBERS array unchanged —
it is already a D.5 exit-0 shim (per its own manifest honest_status), not
a live gate; O.4 does not touch it further.

## Entry 3 (informational, no manifest id exists yet) — `workstreams-turn-emit.sh`: attic move, no manifest edit required

`workstreams-turn-emit.sh`'s manifest entry (id: workstreams-turn-emit,
~line 2018-2034) ALREADY carries `wired_template: false` and
`honest_status: "pending wiring — ... not wired in settings.json.template"`
— it was never live. Move `hooks/workstreams-turn-emit.sh` to
`attic/workstreams-turn-emit.sh` and update ONLY that entry's
`honest_status` to:
```
"retired to attic at O.4 cutover, unwired — item-extraction is superseded
by needs-you.sh; this deterministic every-turn writer was built but never
connected to settings.json.template and is no longer needed now that
tree-state.json is not the cockpit's truth source."
```

## Fragments NOT included (per §O.0.1-1 "say 'none' explicitly")

- `doctor-predicate.md`: none — O.6 owns doctor predicates. The two doctor
  checks that referenced tree-state freshness (if any existed) are O.6's
  concern to retire/update, not this fragment's.
- `install-sync.md`: none — no new top-level dir/file class; `workstreams-ui/**`
  is not part of the `adapters/claude-code/` sync glob at all (it is a
  separate app directory), and no new `hooks/*.sh`/`scripts/*.sh`/
  `schemas/*.json` were added by this task (only edits + one attic move
  inside `adapters/claude-code/hooks/`).
