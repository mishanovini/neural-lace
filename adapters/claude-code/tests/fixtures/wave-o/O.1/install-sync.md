# O.1 install-sync fragment (for the orchestrator's serial integration)

Per specs-o §O.0.1 rule 1, the O.1 builder does not edit `install.sh`
directly. `observability-consumer-map.json` is a NEW top-level file
under `adapters/claude-code/` (per contract C3) and is NOT covered by
any existing glob-sync (hooks/*.sh, scripts/*.sh, schemas/*.json) —
it needs its own explicit sync line, same pattern as `manifest.json`'s
own single-file sync (NL-FINDING-017 precedent: "the manifest MUST ship
with the hooks it describes" — this governed data artifact has the same
requirement, since O.6's doctor predicate reads it from the LIVE
`~/.claude/` mirror, not just the repo).

## Recommended addition to `install.sh`

Insert immediately after the existing `manifest.json` sync block
(`adapters/claude-code/install.sh`, the block reading
`if [ -f "$ADAPTER_DIR/manifest.json" ]; then sync_file ...`):

```bash
# observability-consumer-map.json (NL Observability Program Wave O, task
# O.1, specs-o §O.0.3 contract C3): the doctor's check_obs_consumer_map
# predicate (O.6) reads this from the LIVE ~/.claude/ mirror, so it needs
# the same single-file sync treatment as manifest.json above — a fresh
# event type added to the repo copy must reach the live copy the doctor
# actually checks, or the doctor is validating a stale artifact.
if [ -f "$ADAPTER_DIR/observability-consumer-map.json" ]; then
  sync_file "$ADAPTER_DIR/observability-consumer-map.json" "$CLAUDE_DIR/observability-consumer-map.json" "observability-consumer-map.json"
fi
```

No other install.sh change is required by O.1 — every hook/script this
task edited (`hooks/lib/signal-ledger.sh`, `hooks/stop-verdict-
dispatcher.sh`, `hooks/workstreams-stop-writer.sh`, `hooks/session-
start-digest.sh`, `hooks/pre-compact-continuity.sh`,
`hooks/workstreams-emit.sh`, `scripts/session-resumer.sh`) already lives
under an existing globbed sync (`hooks/*.sh`, `hooks/lib/*.sh`,
`scripts/*.sh`) and needs no new sync line.
