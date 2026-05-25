# Weekly harness-evaluator scheduling — wiring placeholders

The plan (`docs/plans/drift-backlog-and-harness-evaluator.md` Task 6)
deferred actual scheduled-task registration to Misha's review-cadence
preference. This file documents the wire-up options so a future session
(or Misha directly) can register the schedule in one step.

## Option A — `/schedule` Routine (Claude-native, preferred)

From any Claude Code session in the neural-lace repo:

```
/schedule "Run weekly harness self-eval: refresh drift backlog + produce review packet"
  --cron "0 8 * * MON"
```

The Routine's body should run:

```bash
cd ~/claude-projects/neural-lace
bash adapters/claude-code/scripts/mine-misha-asked.sh \
  --recent-days 60 --project-filter neural-lace
bash adapters/claude-code/scripts/harness-evaluator.sh
git add docs/reviews/$(date -u +%Y-%m-%d)-harness-self-eval.md
git commit -m "weekly: harness self-eval packet $(date -u +%Y-%m-%d)"
git push
```

Counts against weekly cloud quota (~5/15/25 per Pro/Max/Team per
`rules/automation-modes.md`).

## Option B — Local cron (Windows Task Scheduler / launchd)

For machines that prefer local execution:

**Windows Task Scheduler:**
```
schtasks /Create /SC WEEKLY /D MON /ST 08:00 \
  /TN "harness-self-eval" \
  /TR "C:\Program Files\Git\bin\bash.exe -c 'cd ~/claude-projects/neural-lace && bash adapters/claude-code/scripts/mine-misha-asked.sh --recent-days 60 --project-filter neural-lace && bash adapters/claude-code/scripts/harness-evaluator.sh'"
```

**macOS / Linux cron:**
```cron
0 8 * * MON cd ~/claude-projects/neural-lace && bash adapters/claude-code/scripts/mine-misha-asked.sh --recent-days 60 --project-filter neural-lace && bash adapters/claude-code/scripts/harness-evaluator.sh >> ~/.claude/logs/harness-eval.log 2>&1
```

## Option C — Manual + reminder

If automation feels premature, just run it manually when Misha sits
down for a review session:

```bash
cd ~/claude-projects/neural-lace
bash adapters/claude-code/scripts/mine-misha-asked.sh --recent-days 60 --project-filter neural-lace
bash adapters/claude-code/scripts/harness-evaluator.sh
# Read docs/reviews/$(date -u +%Y-%m-%d)-harness-self-eval.md
# Triage findings; file HARNESS-GAP entries or fixes as warranted
```

## Cadence recommendation

Per the plan's Walking Skeleton + the 14-day drift threshold:

- **Weekly cadence** (recommended): keeps drift signal fresh; one cycle
  of "Misha review → next packet" matches the 14d threshold's
  resolution-window assumption.
- **Bi-weekly cadence**: lower noise; risk that drift items linger past
  one Misha-review-cycle without surfacing.
- **On-demand only**: lowest cost; risk that the meta-failure ("not
  everything I tell you to do actually gets done") returns through the
  side door of "not running the evaluator either".

**Misha decides cadence.** This file documents the options.
