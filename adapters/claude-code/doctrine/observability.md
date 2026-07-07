# Observability (`nl`) — compact
> Enforcement: Pattern (CANONICAL-COUNTERS-01) + a read-only CLI. No blocking hook.
> Full: doctrine/observability-full.md
> Applies: answering "what is the estate doing" (any of the six questions
> below) — before hand-writing an ad-hoc `grep`/`jq` estate query, check
> whether `nl` already answers it.

Wave O's derivation layer (`hooks/lib/observability-derive.sh`, contract C4)
+ CLI (`scripts/nl.sh`, contract C5) answer six standing operator questions
by READING ground truth (heartbeats, the signal ledger, the NEEDS-YOU ledger,
transcripts, the backlog) — never a maintained side-state file that can drift
(law 1, DERIVE-DON'T-MAINTAIN; see
`docs/reviews/2026-07-04-observability-design-sketch.md`).

## CANONICAL-COUNTERS-01 (the rule)

**Never report an estate count from an ad-hoc query when a canonical oracle
exists; if none exists yet, name the definition you used inline.** Every
count `nl` prints carries `(oracle: <definition-id>)` — e.g. `3 open row(s)
(oracle: od_backlog_health)`. `grep oracle: <output>` finds the provenance of
every number. Before hand-writing a query that recomputes a count `nl`
already derives (sessions, needs-you items, backlog rows, shipped commits,
harness-health gate counts, token costs), use `nl` instead.

## The six questions -> `nl` subcommands

| # | Question | Subcommand |
|---|----------|-----------|
| Q1 | What is every session doing? | `nl status` |
| Q2 | What needs MY decision? | `nl needs-me` |
| Q3 | What shipped since I last looked? | `nl shipped [--since <ts>]` |
| Q4 | Is the harness healthy? | `nl status` (header line) |
| Q5 | What did this cost? | `nl costs [<session>]` |
| Q6 | Why did session X do that? | `nl why <session> [--last-block]` |

Plus `nl backlog` (the backlog oracle — BACKLOG-LOOP-01's digest/KPI/plan-
edit-validator consumers all read this one definition). Every subcommand
accepts `--json`. Full field/state semantics (session states, the `nl why`
causal-chain format, backlog disposition words, the C1-C5 frozen contracts,
per-question read sources): doctrine/observability-full.md.
