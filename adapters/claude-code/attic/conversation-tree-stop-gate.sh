#!/bin/bash
# Backward-compat shim (Workstreams rename, Task 2b — docs/plans/workstreams-phase-3.md, 2026-06-01).
# Renamed conversation-tree-stop-gate.sh -> workstreams-stop-gate.sh. Deletable 2026-06-30.
exec bash "$(dirname "${BASH_SOURCE[0]}")/workstreams-stop-gate.sh" "$@"
