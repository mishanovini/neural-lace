# Harness-evaluator scheduling — wiring placeholders

**Cadence: daily, not weekly** (per Misha 2026-05-25). The plan
originally called for weekly; daily gives more current signal +
faster feedback when a rule's bypass rate spikes. Daily reports are
**skim-fast (3-5 bullets unless something needs deep treatment)**.
Weekly aggregations still exist as a separate "what changed this
week" rollup, but the working cadence is daily.

## Why daily

- 14-day drift threshold means a daily packet shows new drift items
  within 1 day of crossing the threshold (vs. up to 7 days with weekly).
- CI watcher (System 3) emits drift items on FAIL transitions; a daily
  cadence ensures Misha doesn't have a stale view of "what's broken".
- Cost of a daily packet is bounded: generation is ~5 seconds, packet
  size is 3-5 bullets unless something explodes.

## Output formats

The harness-evaluator script writes TWO formats now:

1. **Daily packet** at `docs/reviews/YYYY-MM-DD-harness-self-eval.md` —
   skim-fast 3-5 bullet summary with collapsible deep-treatment sections
   for anything that warrants more space.
2. **Weekly rollup** at `docs/reviews/YYYY-WW-harness-weekly-rollup.md`
   (ISO week numbering) — diffs the last 7 daily packets; surfaces
   what's NEW vs ongoing; serves as the historical record.

Pass `--mode daily` (default) or `--mode weekly-rollup` to the script.

## Option A — `/schedule` Routine (Claude-native, preferred)

Daily scan + packet:

```
/schedule "Daily harness self-eval + CI watcher tick"
  --cron "0 8 * * *"
```

Routine body:

```bash
cd ~/claude-projects/neural-lace
bash adapters/claude-code/scripts/dispatch-ci-watcher.sh
bash adapters/claude-code/scripts/mine-misha-asked.sh --recent-days 30 --project-filter neural-lace
bash adapters/claude-code/scripts/harness-evaluator.sh --mode daily
git add docs/reviews/$(date -u +%Y-%m-%d)-harness-self-eval.md
git commit -m "daily: harness self-eval $(date -u +%Y-%m-%d)"
git push
```

Weekly rollup (one extra cron):

```
/schedule "Weekly harness rollup"
  --cron "0 9 * * MON"
```

Routine body:

```bash
cd ~/claude-projects/neural-lace
bash adapters/claude-code/scripts/harness-evaluator.sh --mode weekly-rollup
git add docs/reviews/$(date -u +%Y-W%V)-harness-weekly-rollup.md
git commit -m "weekly: harness rollup $(date -u +%Y-W%V)"
git push
```

Counts against weekly cloud quota: 7 daily + 1 weekly = 8 / week
(within Pro tier's ~5-15 daily allocation).

## Option B — Local cron / Task Scheduler

**Windows Task Scheduler (daily):**

```
schtasks /Create /SC DAILY /ST 08:00 \
  /TN "harness-self-eval-daily" \
  /TR "C:\Program Files\Git\bin\bash.exe -c 'cd ~/claude-projects/neural-lace && bash adapters/claude-code/scripts/dispatch-ci-watcher.sh && bash adapters/claude-code/scripts/mine-misha-asked.sh --recent-days 30 --project-filter neural-lace && bash adapters/claude-code/scripts/harness-evaluator.sh --mode daily'"
```

**Windows Task Scheduler (weekly rollup, Monday):**

```
schtasks /Create /SC WEEKLY /D MON /ST 09:00 \
  /TN "harness-weekly-rollup" \
  /TR "C:\Program Files\Git\bin\bash.exe -c 'cd ~/claude-projects/neural-lace && bash adapters/claude-code/scripts/harness-evaluator.sh --mode weekly-rollup'"
```

**Cron (Linux / macOS):**

```cron
# Daily 08:00 — CI watcher + drift refresh + daily packet
0 8 * * * cd ~/claude-projects/neural-lace && bash adapters/claude-code/scripts/dispatch-ci-watcher.sh && bash adapters/claude-code/scripts/mine-misha-asked.sh --recent-days 30 --project-filter neural-lace && bash adapters/claude-code/scripts/harness-evaluator.sh --mode daily >> ~/.claude/logs/harness-eval.log 2>&1

# Weekly Monday 09:00 — rollup
0 9 * * MON cd ~/claude-projects/neural-lace && bash adapters/claude-code/scripts/harness-evaluator.sh --mode weekly-rollup >> ~/.claude/logs/harness-eval.log 2>&1
```

## Option C — Manual + reminder

If automation feels premature, just run when Misha sits down:

```bash
cd ~/claude-projects/neural-lace
bash adapters/claude-code/scripts/dispatch-ci-watcher.sh
bash adapters/claude-code/scripts/mine-misha-asked.sh --recent-days 30 --project-filter neural-lace
bash adapters/claude-code/scripts/harness-evaluator.sh --mode daily
# Read docs/reviews/$(date -u +%Y-%m-%d)-harness-self-eval.md
```

## Cadence recommendation summary

- **Daily packet** (recommended, Misha-directed): keeps drift signal +
  CI health current; skim-fast 3-5 bullets.
- **Weekly rollup** (separate cadence): diffs last 7 days; serves as
  the historical record.

**Misha decides whether to opt into push notifications on high-severity
drift items.** The daily packet is the passive surface; push is opt-in.
