# Draft response (builder is about to send this to the user)

Here's the summary of where the harness stands after this session:

1. The scope-enforcement-gate skips its entire scope check during a rebase or merge
   (`adapters/claude-code/hooks/scope-enforcement-gate.sh` detects `MERGE_HEAD` /
   `rebase-apply` and full-skips), so merge commits no longer false-positive.

2. `adapters/claude-code/scripts/session-wrap.sh` validates that the final message
   contains the PR Health Snapshot section before allowing session wrap.

3. `adapters/claude-code/hooks/workstreams-emit.sh` emits a `branch-opened` event on
   every Dispatch spawn and retries failed emissions with exponential backoff.

4. The harness has no hook that fires on the UserPromptSubmit event — that surface
   is currently unused.

5. The late conclusion of stale branches MAY be caused by the heartbeat's 60-minute
   staleness threshold rather than the 5-minute sweep cadence (HYPOTHESIZED: the
   sweep runs every 5 min but only concludes markers older than
   CONV_TREE_HEARTBEAT_STALE_MIN=60; would be REFUTED by observing a branch concluded
   less than 60 minutes after its last transcript activity).
