# O.4 install-sync fragment

None. `workstreams-ui/**` is not part of the `adapters/claude-code/` sync
glob (it is a sibling app directory synced/deployed independently of the
harness install pass); no new top-level `hooks/*.sh`, `scripts/*.sh`, or
`schemas/*.json` file class was introduced by this task — the three attic
moves (`workstreams-state-gate.sh`, `workstreams-extract-pending.sh`,
`workstreams-turn-emit.sh`, all applied by the orchestrator per
`attic-move-list.md`) move files WITHIN the already-synced `hooks/`
directory, which install.sh's existing glob already covers.
