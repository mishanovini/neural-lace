# Pattern: Session Lifecycle Hooks

## When This Pattern Applies

At session start and session end, the harness should verify system health and prevent work from being lost.

## Session Start

1. **Account verification**: Ensure the correct credentials are active for the current project context (supports multi-account development)
2. **Context recovery**: Check for existing working memory (scratchpad, active plans, backlog) and load it
3. **Freshness check**: Warn if working memory is stale (outdated dates, active plans with no recent activity)
4. **Harness health**: Verify all declared hooks exist and are executable, settings are valid, no config drift
5. **Telemetry initialization**: Start session event, record loaded components

## Session End

1. **Plan verification**: If an active plan exists, verify all checked tasks have corresponding evidence. Block termination if tasks are marked complete without verification.
2. **Working memory update**: Ensure scratchpad and plan files reflect the current state
3. **Uncommitted work check**: Warn if there are uncommitted changes
4. **Telemetry finalization**: End session event with summary stats (actions, blocks, duration)

## Behavior

- Session start checks are non-blocking warnings (except account switching, which is automated)
- Session end checks can block termination to prevent work loss
- User can override end-of-session blocks by setting plan status to ABANDONED or DEFERRED
