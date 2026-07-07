# O.5 install-sync fragment

**None.** `scripts/ntfy-push.sh` is a new file under `adapters/claude-code/scripts/`,
which is already glob-synced by `install.sh` (per §O.0.1 rule 1: "hooks/*.sh,
scripts/*.sh, schemas/*.json are already glob-synced — most tasks need NO install
fragment"). `scripts/needs-you.sh`'s one-line edit (the O.5 CALL POINT) is a change
to an existing already-synced file, not a new top-level path. No `install.sh` change
needed.
