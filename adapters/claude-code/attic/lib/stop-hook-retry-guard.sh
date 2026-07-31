#!/usr/bin/env bash
# attic/lib shim — Wave D.5 moved retired gates to attic/ but not their lib/
# directory, so their `source "${BASH_SOURCE[0]%/*}/lib/..."` lines broke.
# Re-source the live library instead of copying it, so the archived gates stay
# runnable (e.g. --self-test forensics) without a second copy that can drift.
# shellcheck disable=SC1091
source "${BASH_SOURCE[0]%/*}/../../hooks/lib/stop-hook-retry-guard.sh"
