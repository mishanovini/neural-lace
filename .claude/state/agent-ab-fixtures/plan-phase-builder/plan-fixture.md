# Plan: walk.sh --max-depth flag (FIXTURE)
Status: ACTIVE-FIXTURE (synthetic — not a real plan; do not archive)

## Goal
`walk.sh` accepts an optional `--max-depth N` flag limiting recursion depth
(N=1 lists only the root's direct files). Existing behavior without the flag is
unchanged.

## Tasks
- [ ] T-PB-1. Add --max-depth to walk.sh + extend walk-tests.sh to cover depth 1
  and the unchanged no-flag behavior — Verification: full
  Done when: walk-tests.sh passes with new depth tests AND the pre-existing
  no-flag test still passes unmodified.
