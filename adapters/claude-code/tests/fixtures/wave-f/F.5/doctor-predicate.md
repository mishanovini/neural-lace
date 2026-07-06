# F.5 doctor predicate (for F.1's orchestrator integration, §F.0.1)

Owner: F.1 builder implements this in `harness-doctor.sh` (F.1 is the designated
doctor integrator this wave). F.5 does not edit `harness-doctor.sh` directly.

## Predicate 1 — waiver-parity schema conformance

Command: parse `adapters/claude-code/manifest.json`; for every entry with
`blocking: true`, assert `waiver_path` (non-empty string) OR `honesty_rationale`
(non-empty string) is present (see `schema-amendments.md` in this same directory
for the exact schema fields this predicate depends on — F.1 should land the
schema amendment and this doctor predicate in the same pass).

RED condition: any `blocking: true` entry with BOTH `waiver_path` and
`honesty_rationale` absent/null/empty.

Red fixture:
```bash
tmp="$(mktemp -d)"
cat > "$tmp/manifest.json" <<'JSON'
{
  "schema_version": 1,
  "entries": [
    {
      "id": "fixture-ungoverned-gate",
      "kind": "gate",
      "doctrine_file": null,
      "hooks": ["fixture.sh"],
      "events": ["PreToolUse"],
      "wired_template": true,
      "selftest": true,
      "jit_triggers": {"paths": [], "keywords": []},
      "blocking": true,
      "budget_class": "pretool"
    }
  ]
}
JSON
# Running the waiver-parity check against $tmp/manifest.json must RED on
# "fixture-ungoverned-gate" (blocking:true, no waiver_path, no honesty_rationale).
```

Green fixture: the same entry with `"honesty_rationale": "..."` (or
`"waiver_path": "..."`) added — must pass.

## Predicate 2 — gate-demotion.sh sandboxing

Command: `bash adapters/claude-code/scripts/gate-demotion.sh --self-test`
(mirrors the doctor's existing per-hook self-test invocation pattern, e.g. how
it already shells out to `waiver-density.sh --self-test`).

RED condition: non-zero exit.

## Predicate 3 — cross-repo-nl-touch-warn.sh self-test + FP fixture presence

Command: `bash adapters/claude-code/hooks/cross-repo-nl-touch-warn.sh --self-test`.

RED condition: non-zero exit. WARN (not RED) if the hook file is absent
entirely AND no manifest entry documents it as pending (this is a candidate
gate per specs-f §F.5 item 4 — its ABSENCE is not itself a defect if the
operator/F.1 decides not to wire it; only a REGRESSION after wiring should
RED).

## Notes for F.1

- `waiver-parity-audit.md` (this same directory) is the human-readable table
  backing Predicate 1's per-entry rationale; `schema-amendments.md` is the
  exact schema/manifest diff. Land schema + manifest values + this doctor
  predicate together so the check has real data to validate against
  immediately (a schema-only landing with no per-entry values would RED on
  literally every existing blocking entry until Proposal 2's values are also
  folded in — sequence the merge so schema + values land in the SAME commit).
