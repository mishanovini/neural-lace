# directives-register fixtures (gated-pipeline-master-2026-08 Task 11)

Fixtures for `hooks/lib/directives-register-lib.sh --self-test`. This IS the
shared round-trip contract Task 20 (`scripts/dispatch-directives.sh` +
`doctrine-jit.sh`'s register walk) reuses — per plan Task 11's "Integration
points" note: *"Task 20 consumes this lib — schema agreed HERE via the shared
fixture (the HR-F6 lesson, executed)."* Do not fork a second copy of this
fixture for Task 20; read these two files.

- `fixture-register.json` — a 4-entry register (NOT the real
  `adapters/claude-code/config/operator-directives.json`) covering every
  branch `dr_entries_for_files` must get right:
  - `OD-901` — BINDING, surface `adapters/claude-code/hooks/*gate*.sh`
    matches `fixture-files.txt` → MUST be returned. Also carries a well-formed
    `elaboration` object (Task: directives-elaboration-layer, operator
    proposal 2026-08-04) — the shared fixture for elaboration-carriage
    round-trip coverage (`dr_has_elaboration`, `dr_get_elaboration_field`,
    `dr_register_walk_bash`'s compact intent/requirements/anti_patterns
    block, and `dispatch-directives.sh`'s printed elaboration section).
    OD-902/903/904 deliberately carry NO elaboration field, proving the
    optional-field contract in both directions (present vs. absent).
  - `OD-902` — BINDING, surface `docs/designs/**` does not match → MUST NOT
    be returned.
  - `OD-903` — SUPERSEDED, surface identical to OD-901's (would match) → MUST
    NOT be returned (status excludes it, never a surface question).
  - `OD-904` — BINDING + `operator_only: true`, empty `surfaces` array → MUST
    NOT be returned for any input (no code surface to carry a directive
    citation into).
- `fixture-files.txt` — a fixture task's "Files to Modify" list (one path per
  line): `adapters/claude-code/hooks/dispatch-chain-gate.sh` +
  `adapters/claude-code/scripts/nl-maintenance.sh`.

**Expected round-trip result:** `dr_entries_for_files fixture-register.json
$(cat fixture-files.txt)` → exactly `OD-901`, nothing else.

**Surface-glob matching semantics (documented simplification):** matching is
plain bash pattern matching (`[[ "$path" == $glob ]]`), not a full
picomatch/globstar implementation — a bare `*` already matches across `/`
boundaries in this context, so `*` and `**` behave identically here. Every
glob in the real register and in this fixture is written with that in mind.
