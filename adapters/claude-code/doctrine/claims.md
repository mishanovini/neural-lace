# Claims — compact
> Enforcement: Pattern — self-applied. Full: doctrine/claims-full.md
> Applies: every causal claim in a status update, report, evidence block, or ADR

Tag every causal claim ("X is caused by Y", "the root cause is Y", "Y prevents X")
as one of:

- **PROVEN** — cite the specific evidence (log line, test output, file:line,
  response body). Example: "auth is hanging (PROVEN: 5/5 probes timeout at 30s,
  runtime logs show the crash trace at `server.js:24:11422`)".
- **HYPOTHESIZED** — state the assumption AND what would REFUTE it. Example:
  "may be the Lambda cold-init cap (HYPOTHESIZED: REFUTED by absence of
  `INIT_REPORT` lines in the runtime logs over the failure window)".

Naked confident phrasing without a tag is prohibited. If unsure, default to
HYPOTHESIZED — a claim wrongly tagged HYPOTHESIZED can be promoted later; a claim
wrongly tagged PROVEN poisons every downstream session that reads it.

Descriptive statements ("I read X and confirmed Y", "the test returned exit 0")
need no tag — the rule binds claims about WHY, not claims about WHAT was observed.

**Before building a plan on a hypothesis**, write the refutation criterion
explicitly: "Hypothesis Z would be REFUTED by observing [specific, cheap-to-check,
causally-tight evidence]." Then look for that refuting evidence BEFORE spending
engineering effort. If no refutation criterion exists, the hypothesis is not
falsifiable — say so plainly and either find more evidence or declare the plan
speculative with a cost ceiling.

If refutation evidence appears, the hypothesis is wrong — update the decisions
log, downgrade the claim, and pull more runtime evidence. Do not quietly adjust
the hypothesis to dodge the refutation.

When the operator pushes back ("are you sure?", "look at the logs") — that is the
signal to re-classify the claim immediately, not to defend the original phrasing.

## Status vocabulary lock (status-event-ledger plan SE10, 2026-07-30)

Chat reports, sign-offs, and session-end markers use EXACTLY the cockpit's status vocabulary —
never a synonym, hedge, or ad-hoc phrasing: the six-state status enum (not-started |
in-progress | running | complete | stalled(reason) | unknown(reason)), and the fused
`<PlanKey><TaskId>` token (`SE3`, `T9`) for task/plan references — never a bare number. Full
doctrine has the parse-level lesson (a vocabulary convention isn't real until every consumer's
grammar accepts it — a real parser gap this surfaced) and the enforcement detail
(`stop-verdict-dispatcher.sh`'s WARN-only vocabulary-lock check).
