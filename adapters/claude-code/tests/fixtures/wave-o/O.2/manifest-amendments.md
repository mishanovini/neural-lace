# O.2 manifest amendment — session-heartbeat writer entry

Status: FOR ORCHESTRATOR SPLICE ONLY (manifest.json is orchestrator-only
per specs-o §O.0.1). Schema-valid against `schemas/manifest.schema.json`
(v1). Mirrors the **actual live** `needs-you-ledger` writer entry in
`manifest.json` (verified by reading it directly, not just the
`tests/fixtures/wave-e/E.6/manifest-entry.json` fixture copy — the two
differ: the live entry adds `honest_status` naming the `scripts/` file,
with `"hooks": []`) — same `kind: "writer"`, `blocking: false`,
`budget_class: "none"` pattern (a liveness tick is observability, never
enforcement — no waiver_path/honesty_rationale required since `blocking`
is false).

Add this object to `manifest.json`'s `entries` array (keep the array
sorted by `id`, LC_ALL=C order, per the schema's own ordering note).
Verified insertion point (via `jq -r '.entries[].id' manifest.json |
LC_ALL=C sort`): immediately after `secret-scan-ci-backstop` and before
`session-honesty` (`"session-heartbeat"` < `"session-honesty"` since
`e` < `o` at the first differing character):

```json
{
  "id": "session-heartbeat",
  "kind": "writer",
  "doctrine_file": null,
  "hooks": [],
  "events": [],
  "wired_template": false,
  "selftest": true,
  "jit_triggers": {
    "paths": [
      "scripts/session-heartbeat.sh",
      "hooks/lib/session-heartbeat-lib.sh"
    ],
    "keywords": []
  },
  "blocking": false,
  "budget_class": "none",
  "honest_status": "scripts/session-heartbeat.sh (touch/sweep) + hooks/lib/session-heartbeat-lib.sh (hb_path_for/hb_write/hb_is_stale/hb_classify, the shared C1 read-side implementation) — per-session liveness file (O.2); called by one-line splices in session-start-digest.sh / workstreams-stop-writer.sh / pre-compact-continuity.sh, not event-wired as its own settings.json entry."
}
```

Field-by-field rationale:

- `id: "session-heartbeat"` — kebab-case, unique, mirrors the file's own
  name (same convention as `needs-you-ledger` naming after
  `needs-you.sh`).
- `kind: "writer"` — the script only ever writes a liveness file / reports
  a read-only sweep; it never blocks or refuses a tool call or session end.
- `doctrine_file: null` — no doctrine compact for this task; `nl`
  usage/CANONICAL-COUNTERS-01 documentation lives in
  `doctrine/observability.md`, owned by §O.3 (that file's own manifest
  fragment will carry its own `jit_triggers`; this entry's paths are
  scoped to ITS OWN two files only — no double-claim).
- `hooks: []` — **verified against the live manifest.json entry for
  `needs-you-ledger`**: scripts/*.sh files (as opposed to hooks/*.sh files)
  are NOT listed in `hooks[]` — that array's coverage sweep in
  `manifest-check.sh` scans `adapters/claude-code/hooks/` (excluding
  `lib/`) for orphaned files, and a `scripts/` file is out of that scan's
  scope entirely. The live precedent instead names the script's real path
  in free-text `honest_status`. This fragment follows that exact
  precedent rather than the (incorrect) fixture-only guess of listing
  `"session-heartbeat.sh"` in `hooks[]`.
- `events: []` — no Claude Code lifecycle event directly invokes this
  script (it's invoked via one-line calls FROM other hooks' bodies, not
  registered as its own settings.json entry) — matches `needs-you-ledger`'s
  precedent.
- `wired_template: false` — correct and requires no schema-conditional
  extra field since `kind` is `"writer"`, not `"gate"` (the schema's
  conditional-required rule for `honest_status` only hard-requires it when
  `kind == "gate"` AND `wired_template == false`; here `honest_status` is
  supplied anyway, voluntarily, to name the real file location — same
  choice `needs-you-ledger` made).
- `selftest: true` — both `scripts/session-heartbeat.sh --self-test` and
  `hooks/lib/session-heartbeat-lib.sh --self-test` exist and pass (see
  report-back for counts).
- `jit_triggers.paths` — touching either new file should JIT-inject
  relevant doctrine context; kept to this task's OWN two files (not
  `doctrine/observability.md`'s paths, which are §O.3's to declare).
- `blocking: false`, `budget_class: "none"` — never blocks anything, not
  registered in any settings.json chain (called via one-line splices from
  within other hooks' bodies, not as its own hook entry) — matches
  `needs-you-ledger`'s exact values.

No `template-wiring.md`, `doctor-predicate.md`, or `install-sync.md`
fragment is shipped for O.2: no new settings.json entries (the three
call-sites are one-line splices INSIDE existing hook bodies owned by O.1,
not new top-level hook registrations); doctor freshness checks for
heartbeats are §O.6's task; `scripts/*.sh` and `hooks/lib/*.sh` are already
covered by the existing install glob sync (per §O.0.1 rule 1's own note:
"most tasks need NO install fragment; say 'none' explicitly").
