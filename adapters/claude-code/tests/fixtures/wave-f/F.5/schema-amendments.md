# F.5 schema amendments (for F.1's orchestrator merge)

Per §F.0.1, `adapters/claude-code/schemas/manifest.schema.json` and
`adapters/claude-code/manifest.json` are ORCHESTRATOR-ONLY (F.1 integrates). This
fragment is the exact diff F.1 should apply, derived from
`waiver-parity-audit.md`'s Proposal 1/2 in this same directory.

## 1. Schema: add `waiver_path` + `honesty_rationale`, require one when `blocking: true`

In `schemas/manifest.schema.json`, inside `properties.entries.items.properties`,
add two new properties (siblings of the existing `honest_status`):

```json
"waiver_path": {
  "type": ["string", "null"],
  "minLength": 1,
  "description": "Path/glob (relative to ~/.claude/state/ or the repo) of the structured waiver file this blocking gate honors, typically validated by hooks/lib/waiver-purpose-clause.sh. Null or omitted when honesty_rationale explains why no waiver is offered."
},
"honesty_rationale": {
  "type": ["string", "null"],
  "minLength": 1,
  "description": "REQUIRED (non-null) when blocking is true AND waiver_path is null/absent: names why this gate's block is session-honesty-class (resolvable by the session that created the gap, e.g. fix the commit content) rather than a world-state assertion needing a waiver, per ADR 059 D4 scoping. Enforced by manifest-check.sh's waiver-parity check."
}
```

Add both to the `allOf` array (after the existing `honest_status` conditional,
same file, around line 150-178):

```json
{
  "if": {
    "properties": { "blocking": { "const": true } },
    "required": ["blocking"]
  },
  "then": {
    "anyOf": [
      {
        "required": ["waiver_path"],
        "properties": { "waiver_path": { "type": "string", "minLength": 1 } }
      },
      {
        "required": ["honesty_rationale"],
        "properties": { "honesty_rationale": { "type": "string", "minLength": 1 } }
      }
    ]
  }
}
```

Also add `"waiver_path"` and `"honesty_rationale"` to the entry-level
`additionalProperties: false` object's implicit allowed-keys set (i.e., just
declaring them in `properties` is sufficient given the schema's existing
`additionalProperties: false` — no separate edit needed there, noting it so F.1
doesn't miss that these two keys need to appear in `properties`, not bolted on
elsewhere).

## 2. `scripts/manifest-check.sh` — new waiver-parity check

Add a check function (name suggestion: `check_waiver_parity`) alongside the
existing coverage/doctrine-target checks: for every entry with `blocking: true`,
assert `waiver_path` (non-empty) OR `honesty_rationale` (non-empty) is present.
RED on any blocking entry with neither. This is the schema-level enforcement of
Proposal 1 for entries the schema's own `allOf` conditional might not catch if
manifest-check.sh validates with a looser/cached schema — belt-and-suspenders,
matching the existing pattern where `manifest-check.sh` re-asserts conditions the
schema itself also encodes (see its `honest_status` check (e), referenced by the
schema's own description field at line 136).

## 3. `manifest.json` — per-entry values to fold in

See `waiver-parity-audit.md`'s "Proposal 2" section in this same directory for
the exact `honesty_rationale`/`waiver_path` value recommended per entry (23
entries get a value now; 5 GAP entries — `agent-teams` [task-validator half],
`harness-hygiene-scan`, `plan-deletion-protection`, `wire-check`, `spec-freeze`
[spec-freeze-gate.sh half] — need the code fix in Proposal 3 first, or an
explicit operator/harness-reviewer call on spec-freeze's case, before a value can
be honestly assigned).

## 4. F.1's new-gate evidence bar (specs-f §F.1 item 3) — same fields, forward-looking

specs-f §F.1 already requires `added_after: 2026-07` entries to name
`golden_scenario`, `fp_expectation`, `retirement_condition`, and (per ADR 059 D4)
`waiver_path` or `honesty_rationale` — schema-validated, RED otherwise. Item 1/2
above are the RETROACTIVE half of that same bar (applying `waiver_path`/
`honesty_rationale` to entries that predate the `added_after` convention). F.1
should implement both in the same schema pass so there is one `allOf` conditional
family, not two overlapping ones — recommend the `added_after`-gated fields
(`golden_scenario`, `fp_expectation`, `retirement_condition`) and the
always-required-when-blocking fields (`waiver_path`/`honesty_rationale`) as
separate `allOf` entries in the schema, since their trigger conditions differ
(one keys on `added_after` presence, the other on `blocking: true` alone).
