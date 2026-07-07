# O.8 manifest amendments (for the orchestrator integration pass)

Per specs-o §O.0.1, `manifest.json` is ORCHESTRATOR-ONLY. This fragment lists
the one entry O.8's work makes true, for the orchestrator to fold in.

## NEW entry — `estate-coordination`

Pure docs + skill unit (no hooks, no events, no blocking behavior) — same
class as the existing `pattern`-kind doctrine-only entries (e.g.
`orchestrator-pattern`, `claims`, `diagnosis`), but WITH `jit_triggers`
populated per specs-o §O.8 deliverable 2 (paths: SCRATCHPAD.md; keywords:
freeze, coordinate sessions, stand down):

```json
{
  "id": "estate-coordination",
  "kind": "pattern",
  "doctrine_file": "doctrine/estate-coordination.md",
  "hooks": [],
  "events": [],
  "wired_template": false,
  "selftest": false,
  "jit_triggers": {
    "paths": ["SCRATCHPAD.md"],
    "keywords": ["freeze", "coordinate sessions", "stand down"]
  },
  "blocking": false,
  "budget_class": "none",
  "honest_status": "docs+skill unit only (skills/coordinate-estate.md + doctrine/estate-coordination.md); no hook, no wiring; jit_triggers fire doctrine-jit.sh's paths-match on any edit whose file_path contains SCRATCHPAD.md (keywords reserved for v2 per schema, not yet matched)."
}
```

## No schema change required elsewhere

This task edits no existing manifest entry, adds no hook file, adds no
settings.json.template entry (§O.0.1-8: SessionStart/Stop/blocking-gate
budgets are all untouched by O.8 — it is fragments + skill + doctrine + a
drill fixture only). No `doctor-predicate.md` fragment: O.8 is not a doctor
check (its "done-when" is a drill fixture, not a live pipeline-health
predicate — see `drill-fixture.md` / `run-drill.sh` in this same directory).
No `template-wiring.md`, no `install-sync.md` ("none" per §O.0.1-1: skills/
and doctrine/ are already glob-synced by install.sh's existing directory
passes — no new top-level dir/file class is introduced).
