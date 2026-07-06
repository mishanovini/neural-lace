# Runbook: pre-compaction continuity (context-watermark + PreCompact backstop)

<!-- last-verified: 2026-07-05 (doctor-checked) -->

**What it is.** Two-stage pre-compaction continuity (Wave E task E.9, two
sub-tasks E.9a/E.9b) so a context-window compaction event does not silently
drop in-flight execution state:

- **E.9a — `context-watermark.sh`** (PostToolUse, early warning): a
  transcript-size-proxy watermark (70%/85% thresholds) that injects a
  reminder to write durable state WHILE there is still room left to act,
  before compaction is imminent.
- **E.9b — `pre-compact-continuity.sh`** (PreCompact hook, auto + manual
  matchers): the zero-token BACKSTOP for when compaction is happening RIGHT
  NOW despite the early warning. Runs a mechanical, zero-token
  session-snapshot script so exact execution state survives regardless of
  what the LLM summarizer keeps, and emits summarizer instructions naming
  all six normative preserve-list categories explicitly, in priority order.

**The commands (fire automatically at their respective hook points — these
are the manual-invocation shapes for testing/inspection):**

```bash
bash adapters/claude-code/hooks/context-watermark.sh          # PostToolUse — check current watermark state
bash adapters/claude-code/hooks/pre-compact-continuity.sh     # PreCompact — snapshot + summarizer instructions
```

**Where its output lands.** The mechanical session-snapshot artifact (see
`scripts/session-snapshot.sh`) plus a SessionStart "compact-echo" surfacer
that re-presents the snapshot at the start of the next session — this is the
PROVEN fallback path; the PreCompact `additionalContext` channel reaching the
summarizer directly is HYPOTHESIZED-not-yet-confirmed on this Claude Code
version (constitution §1 — no unverified mechanism claims), so the honest
architecture treats the snapshot-file + SessionStart echo as the load-bearing
path, with any direct `additionalContext` delivery as a bonus if the platform
supports it.

**Self-test:**

```bash
bash adapters/claude-code/hooks/context-watermark.sh --self-test
bash adapters/claude-code/hooks/pre-compact-continuity.sh --self-test
```
