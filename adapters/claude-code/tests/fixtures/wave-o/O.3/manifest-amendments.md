# O.3 manifest amendments (for the orchestrator integration pass)

Per specs-o §O.0.1, `manifest.json` is ORCHESTRATOR-ONLY. This fragment
lists the entries O.3's work makes true, for the orchestrator to fold in.
Schema-valid against `schemas/manifest.schema.json` (v1). Insertion points
verified via `jq -r '.entries[].id' manifest.json | LC_ALL=C sort` against
the live `claude/wave-o-integration` tree at the time this fragment was
authored (batch-1 merged, `observability-consumer-map` already present from
O.1): sorted neighbors are `...needs-you-ledger, nl-issue-capture-loop,
no-test-skip, ntfy-push, observability-consumer-map,
observed-errors-first...`.

## NEW entry 1 — `nl-cli` (insert between `nl-issue-capture-loop` and
`no-test-skip`; `"nl-cli"` < `"no-test-skip"` since `l` < `o`, and
`"nl-cli"` > `"nl-issue-capture-loop"` since `c` < `i`... verify precisely:
`nl-cli` vs `nl-issue-capture-loop` — compare char-by-char: `nl-` common,
then `c` vs `i` — `c` < `i`, so `nl-cli` sorts BEFORE
`nl-issue-capture-loop`. Corrected insertion point: immediately AFTER
`needs-you-ledger` and BEFORE `nl-issue-capture-loop`.)

```json
{
  "id": "nl-cli",
  "kind": "surfacer",
  "doctrine_file": "doctrine/observability.md",
  "hooks": [],
  "events": [],
  "wired_template": false,
  "selftest": true,
  "jit_triggers": {
    "paths": [
      "adapters/claude-code/scripts/nl.sh",
      "adapters/claude-code/hooks/lib/observability-derive.sh"
    ],
    "keywords": []
  },
  "blocking": false,
  "budget_class": "none",
  "honest_status": "scripts/nl.sh (C5 dispatcher) + hooks/lib/observability-derive.sh (C4 pure-read derivation lib: od_sessions/od_needs_me/od_shipped_since/od_harness_health/od_costs/od_backlog_health/od_why) — the six-question observability CLI (specs-o §O.3). Read-only, zero state writes; not event-wired (invoked on demand by the operator or by the future §O.4 cockpit server shelling out to `nl <sub> --json`)."
}
```

Field-by-field rationale:

- `id: "nl-cli"` — kebab-case; distinct from the pre-existing
  `nl-issue-capture-loop` (a different Wave-E mechanism, `scripts/nl-issue.sh`).
- `kind: "surfacer"` — read-only informational output at operator request,
  never blocks or refuses anything (matches `ntfy-push`'s `surfacer`
  classification for the same "never blocks" reasoning, though `nl` has no
  push side effect at all — pure read).
- `doctrine_file: "doctrine/observability.md"` — the compact this task ships
  (NEW entry 3 below); full detail in `doctrine/observability-full.md` (not
  independently registered — same convention as `estate-coordination`'s
  compact/full split, where only the compact file is a manifest
  `doctrine_file`).
- `hooks: []` — both files live in `scripts/` and `hooks/lib/`
  respectively, neither is a top-level `hooks/*.sh` file, so per the
  verified live precedent (`needs-you-ledger`, `session-heartbeat`) they do
  NOT appear in `hooks[]` — that array's coverage sweep only scans
  `hooks/` excluding `lib/`.
- `events: []`, `wired_template: false` — no settings.json entry; on-demand
  invocation only (§O.0.1-8 budget: zero new hook entries this task).
- `selftest: true` — both `scripts/nl.sh --self-test` (10/10 passing) and
  `hooks/lib/observability-derive.sh --self-test` (30/30 passing) exist and
  pass (see report-back for exact counts). Schema note: `selftest` requires
  EVERY hook in `hooks[]` to have `--self-test` — since `hooks[]` is empty
  here, per the schema's own field description ("False when hooks is empty
  ... hook-derived field; no hooks means nothing is wired") the strict
  reading would be `false`; however the LIVE precedent entries
  `needs-you-ledger` and `nl-issue-capture-loop` (both `hooks: []`) are
  recorded `selftest: true` in the current manifest, naming their
  `scripts/*.sh` self-tests despite the empty hooks array — this fragment
  follows that established precedent rather than the schema description's
  strict literal reading. Flagging as an ORCHESTRATOR TODO / contract
  concern below in case the precedent itself should be corrected repo-wide
  (out of this task's scope to fix retroactively).
- `blocking: false`, `budget_class: "none"` — never blocks, not registered
  in any settings.json chain.

## NEW entry 2 — `nl-issue-capture-loop`, `needs-you-ledger`, etc: UNCHANGED

No edits to any existing entry other than the one noted in "orchestrator
TODO" below (`observability-consumer-map`'s `doctrine_file` field).

## NEW entry 3 — `observability` (doctrine compact; insert between
`no-test-skip` and `ntfy-push`? Verify: `"observability"` vs
`"observability-consumer-map"` — `observability` is a PREFIX of
`observability-consumer-map`, and per standard lexicographic ordering a
prefix sorts BEFORE any string it is a prefix of. So insertion point is
immediately BEFORE `observability-consumer-map` (and after `ntfy-push`,
since `"o" > "n"`).)

```json
{
  "id": "observability",
  "kind": "pattern",
  "doctrine_file": "doctrine/observability.md",
  "hooks": [],
  "events": [],
  "wired_template": false,
  "selftest": false,
  "jit_triggers": {
    "paths": [
      "adapters/claude-code/scripts/nl.sh",
      "adapters/claude-code/hooks/lib/observability-derive.sh"
    ],
    "keywords": [
      "estate count",
      "nl status"
    ]
  },
  "blocking": false,
  "budget_class": "none",
  "honest_status": "CANONICAL-COUNTERS-01 rule + the six operator questions + nl usage (specs-o §O.3 deliverable 1). doctrine/observability.md (compact) + doctrine/observability-full.md (detail, per the estate-coordination.md compact/full split precedent). No hook; the rule is self-applied discipline (per Pattern kind), same class as `estate-coordination`."
}
```

**IMPORTANT — this entry and `nl-cli` (entry 1) BOTH claim
`doctrine_file`/`jit_triggers.paths` overlapping the same two files
(`scripts/nl.sh`, `hooks/lib/observability-derive.sh`).** This is
intentional but worth the orchestrator's explicit attention: `nl-cli` is
the MECHANISM entry (what the CLI/lib do — kind: surfacer, tracks
selftest), `observability` is the DOCTRINE entry (the CANONICAL-COUNTERS-01
rule + six-question map — kind: pattern, no selftest). Both legitimately
point their `jit_triggers.paths` at the same two files because editing
either file is relevant context for BOTH "how does the CLI work" and "am I
about to violate CANONICAL-COUNTERS-01" — this mirrors how
`observability-consumer-map`'s own entry works alongside the ledger-writer
entries it constrains. If `manifest-check.sh` enforces one-file-one-entry
uniqueness for `jit_triggers.paths` (unclear from the schema alone — it
constrains hooks[] to one entry per file, not jit_triggers.paths), the
orchestrator should either drop `nl-cli`'s doctrine_file cross-reference or
consult `plan-reviewer`/`harness-reviewer` on which entry should own the
paths list solely. Flagged, not silently resolved, per builder-forbidden
rule (§O.0.1-2).

## ORCHESTRATOR TODO — `observability-consumer-map` doctrine_file backfill

O.1's own `observability-consumer-map` entry (already live in
`manifest.json`) has `doctrine_file: null` with an explicit comment in its
`honest_status`: "doctrine_file is null until O.3 (doctrine/observability.md)
merges — orchestrator TODO: set doctrine_file to
\"doctrine/observability.md\" once that file lands." That file now exists
(this task). Orchestrator should update that EXISTING entry's
`doctrine_file` field from `null` to `"doctrine/observability.md"` in the
same integration pass as adding the two new entries above (not this
builder's job — editing an entry O.1 authored is a cross-task edit, per
§O.0.1-2 "editing other tasks' files = STOP and report back").

## No template/install/doctor fragments

No `template-wiring.md`: zero new settings.json entries (§O.0.1-8 budget
untouched — `nl` is on-demand CLI only). No `install-sync.md`: `scripts/*.sh`
and `hooks/lib/*.sh` are already glob-synced by install.sh's existing
passes ("most tasks need NO install fragment" per §O.0.1-1). No
`doctor-predicate.md`: O.3 is not itself a doctor check (O.6 owns doctor
predicates that may eventually call into `od_*` functions, e.g.
`check_obs_heartbeats_fresh` could source this lib rather than
re-implementing staleness math — noted as an opportunity for O.6's
integration, not built here since O.3 owns no doctor-predicate deliverable
per the dispatch map).
