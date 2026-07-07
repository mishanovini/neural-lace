#!/bin/bash
# workstreams-turn-emit.sh — RETIRED (NL Observability Program Wave O, task
# O.4, trust-path retirement, specs-o §O.4 deliverable 4 / decision D-O4).
#
# This deterministic every-turn writer existed with green self-tests but was
# never wired in settings.json.template (it predates O.4 as a pending-wiring
# item). Item-extraction is superseded by needs-you.sh, and it is no longer
# needed now that tree-state.json is not the cockpit's truth source.
#
# The full retired implementation is preserved for history at
# adapters/claude-code/attic/workstreams-turn-emit.sh — salvage-before-reset,
# never deleted. This thin exit-0 shim remains at the original hooks/ path
# ONLY because manifest-check.sh's hooks[] <-> disk coverage contract
# requires every manifest-referenced hook basename to resolve on disk
# (attic/ is a sibling directory and is never scanned); it is not wired in
# settings.json.template and carries no self-test (manifest entry
# workstreams-turn-emit: wired_template=false, selftest=false,
# honest_status names this retirement).
exit 0
