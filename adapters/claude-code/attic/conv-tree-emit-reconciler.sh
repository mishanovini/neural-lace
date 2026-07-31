#!/bin/bash
# Backward-compat shim (Workstreams rename, Task 2b — docs/plans/workstreams-phase-3.md, 2026-06-01).
# Renamed conv-tree-emit-reconciler.sh -> workstreams-emit-reconciler.sh. Deletable 2026-06-30.
exec bash "$(dirname "${BASH_SOURCE[0]}")/workstreams-emit-reconciler.sh" "$@"
