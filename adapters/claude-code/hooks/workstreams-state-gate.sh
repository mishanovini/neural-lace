#!/bin/bash
# workstreams-state-gate.sh — RETIRED (NL Observability Program Wave O, task
# O.4, trust-path retirement, specs-o §O.4 deliverable 4 / decision D-O4).
#
# This PreToolUse gate's only protected consumer was workstreams-ui reading
# tree-state.json as truth. The cockpit rebuild (O.4) replaced that read with
# derived-truth reads (`nl <sub> --json`), so per law 2
# (EVERY-SIGNAL-HAS-A-CONSUMER) the gate has nothing left to protect. Both
# settings.json.template entries that invoked this script were removed in
# the same integration commit (see
# adapters/claude-code/tests/fixtures/wave-o/O.4/template-wiring.md). This
# closes NL-FINDING-024 at the root: the spawn writer -> gate PreToolUse race
# that finding describes cannot recur because the gate it raced against no
# longer runs.
#
# The full retired implementation (Pin-2 partition logic, self-test suite,
# waiver semantics) is preserved for history at
# adapters/claude-code/attic/workstreams-state-gate.sh — salvage-before-reset,
# never deleted. This thin exit-0 shim remains at the original hooks/ path
# ONLY because manifest-check.sh's hooks[] <-> disk coverage contract
# requires every manifest-referenced hook basename to resolve on disk
# (attic/ is a sibling directory and is never scanned); it is not wired in
# settings.json.template and carries no self-test (manifest entry
# workstreams-spawn-gate: wired_template=false, selftest=false,
# honest_status names this retirement).
exit 0
