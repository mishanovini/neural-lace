# O.3 install-sync fragment

None. `scripts/nl.sh` and `hooks/lib/observability-derive.sh` are both
already covered by install.sh's existing glob passes over `scripts/*.sh`
and `hooks/lib/*.sh` (per §O.0.1-1: "most tasks need NO install fragment;
say 'none' explicitly"). `doctrine/observability.md` and
`doctrine/observability-full.md` are likewise covered by the existing
`doctrine/*.md` glob sync. No new top-level directory or file class is
introduced by this task.
