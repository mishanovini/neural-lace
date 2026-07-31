# Runbook: session-start digest

<!-- last-verified: 2026-07-05 (doctor-checked) -->

**What it is.** ONE consolidated SessionStart block, hard-capped at 15 output
lines, replacing 12+ separate surfacer blocks (Wave E task E.1). Feeds:
pending discoveries, stale ACTIVE plans, external-monitor alerts, spawned-task
results, pending decisions, git freshness, worktree advice, `doctor --quick`
verdict, ledger 24h summary, nl-issues untriaged count, waiver-density alarm,
unresolved-gaps entries, NEEDS-YOU.md open-item count. A quiet harness
produces a 2-line digest: doctor verdict + "all quiet".

**The one command (fires automatically every SessionStart — this is how to
run it manually to preview what a fresh session will see):**

```bash
bash adapters/claude-code/hooks/session-start-digest.sh
```

**Where its output lands.** Printed directly to the session's SessionStart
context (`additionalContext` channel) — nothing is written to disk by this
hook itself beyond the dedup/expiry state it reads from the individual
feeds' own state files (each named in the hook's own header comment).

**Dedup / auto-expiry / auto-ack.** Repeated identical items across sessions
are deduplicated; stale items auto-expire; some feeds (decision-context,
external-monitor) support an ack path so a consumed item does not re-surface
every session. See the hook's own header for the exact per-feed rules.
