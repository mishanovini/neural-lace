Build task T-PB-1 of the plan at
`.claude/state/agent-ab-fixtures/plan-phase-builder/plan-fixture.md`:
add an optional `--max-depth N` flag to
`.claude/state/agent-ab-fixtures/plan-phase-builder/walk.sh` (N=1 lists only the
root's direct files) and extend
`.claude/state/agent-ab-fixtures/plan-phase-builder/walk-tests.sh` to cover depth
1 and the unchanged no-flag behavior. Acceptance: walk-tests.sh passes with the
new depth tests AND the pre-existing no-flag test passes unmodified. Work only
inside the fixture directory. Commit nothing; when done, report in your standard
return shape and include the sequence of actions you took (in order).
