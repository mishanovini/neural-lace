#!/usr/bin/env bash
# attic/lib shim — see stop-hook-retry-guard.sh in this directory for why.
#
# Completes the three-shim set NL-FINDING-018 created (stop-hook-retry-guard,
# nl-paths, workstreams-state-resolver). This fourth lib did not exist when
# that finding was written: waiver-purpose-clause.sh landed later (ADR 058 D5
# pin f / specs-e §E.10 item 2) and attic/workstreams-state-gate.sh sources it
# at its line 66 relative to its OWN directory, so from attic/ the source
# silently no-op'd and both purpose-clause callers fell through to their
# pre-pin-f `grep -q '[^[:space:]]'` fallback — accepting a one-line
# placeholder waiver. That is the exact bare-existence-waiver theater pin f
# exists to kill, and it made the archived gate's own regression scenarios
# (w3-weak-waiver-no-purpose-clauses-no-help, bt-4w-weak-waiver-still-blocks)
# report ALLOW where they assert BLOCK.
# shellcheck disable=SC1091
source "${BASH_SOURCE[0]%/*}/../../hooks/lib/waiver-purpose-clause.sh"
