#!/bin/bash
# Backward-compat shim (Workstreams rename, Task 2b — docs/plans/workstreams-phase-3.md, 2026-06-01).
# This hook was renamed conversation-tree-emit.sh -> workstreams-emit.sh
# (cosmetic). The shim preserves the old name for any cached settings.json or
# in-flight Dispatch session during the transition. Deletable after 2026-06-30
# once every live settings.json references the new name.
exec bash "$(dirname "${BASH_SOURCE[0]}")/workstreams-emit.sh" "$@"
