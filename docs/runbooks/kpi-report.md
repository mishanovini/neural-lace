# Runbook: harness-kpis (weekly KPI report)

<!-- last-verified: 2026-07-05 (doctor-checked) -->

**What it is.** The consumption layer for the signal ledger the gates emit
into (Wave E task E.5). Before this existed, the 2026-07-01 effectiveness
audit found ZERO consumption of the recorded block/warn/waiver/downgrade/skip
event stream — gates fired, events were logged, and nobody ever read them.
This script turns that ledger into a weekly report: per-gate waiver +
downgrade counts/rates over 7d and 30d windows, doctor drift count,
failure-mode recurrence, waiver-density summary, and untriaged nl-issue
triage status.

**The one command:**

```bash
bash adapters/claude-code/scripts/harness-kpis.sh
```

**Where its output lands.** `docs/reviews/harness-kpis-<YYYY-MM-DD>.md` at
the repo root that resolves as the canonical checkout (via
`hooks/lib/nl-paths.sh`'s `nl_main_checkout_root()` — so running this from a
worktree still writes to the MAIN checkout's `docs/reviews/`, not the
worktree's). `docs/reviews/*` is gitignored except dated decision-shaped
files, so this report is a local, disposable-but-useful artifact, not
something that needs a commit.

**Scheduled registration** (documented here; actual `schtasks` registration
is an operator step):

```bash
schtasks /Create /TN "NL-harness-kpis" /TR "bash ~/.claude/scripts/harness-kpis.sh" /SC WEEKLY /D MON /ST 08:00
```

**Companion:** `scripts/waiver-density.sh --report` feeds one section of this
report; it can also be run standalone (`--digest-line` for the one-line form
the SessionStart digest consumes).
