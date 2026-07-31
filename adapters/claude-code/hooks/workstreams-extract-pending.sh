#!/bin/bash
# workstreams-extract-pending.sh — RETIRED (NL Observability Program Wave O,
# task O.4, trust-path retirement, specs-o §O.4 deliverable 4 / decision D-O4).
#
# Superseded by needs-you.sh (per that file's own header): item-extraction
# from Stop-time transcript scanning is no longer the mechanism — needs-you.sh
# add is the live sink. Removed from workstreams-stop-writer.sh's MEMBERS
# array in the same integration commit.
#
# The full retired implementation is preserved for history at
# adapters/claude-code/attic/workstreams-extract-pending.sh —
# salvage-before-reset, never deleted. This thin exit-0 shim remains at the
# original hooks/ path ONLY because manifest-check.sh's hooks[] <-> disk
# coverage contract requires every manifest-referenced hook basename to
# resolve on disk (attic/ is a sibling directory and is never scanned); it is
# no longer invoked from workstreams-stop-writer.sh's MEMBERS array and
# carries no self-test. It remains listed in the workstreams-emitters
# manifest entry's honest_status note describing this retirement.
exit 0
