# O.6 manifest amendment — scheduled-task-health writer entry

Status: FOR ORCHESTRATOR SPLICE ONLY (manifest.json is orchestrator-only
per specs-o §O.0.1). Schema-valid against `schemas/manifest.schema.json`
(v1). Mirrors the exact `kind: "writer"` / `blocking: false` /
`budget_class: "none"` pattern already live for `needs-you-ledger` and
`session-heartbeat` (both verified by reading the real, current
`manifest.json` directly, not a fixture copy) — a standalone reporting
script that never blocks a caller and is not registered as its own
settings.json hook entry.

Add this object to `manifest.json`'s `entries` array (array is sorted by
`id`, LC_ALL=C order, per the schema's own ordering note). Verified
insertion point (`jq -r '.entries[].id' manifest.json | LC_ALL=C sort`):
immediately after `runtime-verification` and before
`secret-hygiene-prepush` (`"scheduled-task-health"` sorts between them —
verified with `printf 'runtime-verification\nscheduled-task-health\nsecret-hygiene-prepush\n' | LC_ALL=C sort`):

```json
{
  "id": "scheduled-task-health",
  "kind": "writer",
  "doctrine_file": null,
  "hooks": [],
  "events": [],
  "wired_template": false,
  "selftest": true,
  "jit_triggers": {
    "paths": [
      "scripts/scheduled-task-health.sh"
    ],
    "keywords": [
      "scheduled task",
      "schtasks",
      "Last Result"
    ]
  },
  "blocking": false,
  "budget_class": "none",
  "honest_status": "scripts/scheduled-task-health.sh — one-line-per-task Last-Result report for every NL-owned (NL-*) Windows scheduled task (O.6); called by harness-doctor.sh's check_obs_scheduled_tasks predicate, not event-wired as its own settings.json entry. Reports raw values only; makes no pass/fail judgment itself."
}
```

Field-by-field rationale (delta from the `session-heartbeat` precedent
this fragment otherwise copies verbatim):

- `id: "scheduled-task-health"` — kebab-case, unique, mirrors the file's
  own basename.
- `kind: "writer"` — the script only queries and reports; it never
  blocks, refuses, or judges (the judgment — RED/WARN/GREEN — lives in
  `check_obs_scheduled_tasks`, the doctor predicate this task also ships
  as a fragment, per specs-o §O.0.1's builder/orchestrator split).
- `doctrine_file: null` — no doctrine compact for this task; `nl`/
  observability doctrine lives in `doctrine/observability.md`, owned by
  §O.3 — no double-claim.
- `hooks: []` — same precedent as `session-heartbeat`/`needs-you-ledger`:
  `scripts/*.sh` files are out of `manifest-check.sh`'s hooks-coverage
  scan (that scan is scoped to `adapters/claude-code/hooks/`, excluding
  `lib/`); the real path is instead named in free-text `honest_status`.
- `events: []` — no Claude Code lifecycle event invokes this script
  directly; it is shelled out to from `harness-doctor.sh`'s own check
  function, not registered as a settings.json hook.
- `wired_template: false` — correct; no schema-conditional extra field
  required (the schema only hard-requires `honest_status` when
  `kind == "gate"` AND `wired_template == false"`; supplied anyway here to
  name the real file, matching precedent).
- `selftest: true` — `scripts/scheduled-task-health.sh --self-test` exists
  and passes 9/9 scenarios (see report-back for the full count and
  livesmoke evidence).
- `jit_triggers.paths` — touching the script should JIT-inject relevant
  observability-pipeline-health context.
- `jit_triggers.keywords` — surfaced when a session's prompt mentions
  scheduled-task health/failure investigation, mirroring the keyword
  style already used elsewhere in the manifest (free-text phrase match,
  not a strict enum).
- `blocking: false`, `budget_class: "none"` — never blocks anything, not
  registered in any settings.json chain.

No `template-wiring.md` or `install-sync.md` fragment is shipped for O.6:
no new settings.json entries (the script is invoked from inside
`harness-doctor.sh`'s own check function, not registered as its own hook);
`scripts/*.sh` is already covered by the existing install glob sync (per
§O.0.1 rule 1's own note: "most tasks need NO install fragment; say 'none'
explicitly"). The six `check_*` doctor-predicate function bodies
themselves need NO separate manifest entries — they are new code inside
the already-manifested `harness-doctor.sh` file, not new standalone units
(see `doctor-predicate.md`'s own "Manifest note" section in this same
directory).
