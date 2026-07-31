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

Chat reports, sign-offs, and session-end markers use EXACTLY the cockpit's status
vocabulary — never a synonym, hedge, or ad-hoc phrasing:

- **Status enum** (one of six): not-started | in-progress | running | complete |
  stalled(reason) | unknown(reason). "In flight", "wrapping up", "done-ish",
  "basically complete" are not in the enum — a reader cannot tell which of the
  six states they actually mean.
- **Task/plan references**: the fused `<PlanKey><TaskId>` token (e.g. `SE3`,
  `T9`) — never a bare number ("task 9"), never key and number split across
  words. A bare task id names no plan.

PARSE-LEVEL LESSON (2026-07-30): a vocabulary convention isn't real until every
consumer's grammar accepts it. SE/RI fused ids parsed to ZERO tasks in the
cockpit until `plan-parse`'s token regex widened to `[A-Z]{0,3}` fused prefixes
(commit a8b114c) — and, discovered while building SE4, `plan-edit-validator.sh`'s
OWN checkbox-flip `TASK_ID` regex is STILL the pre-fix dotted-only pattern
(`[A-Z]+\.[0-9]+`), so a real flip of `SE3`/`RI1`-style tasks is refused today
(PROVEN: `grep -oE` against that exact pattern empty-matches `SE3`/`RI1`, tested
2026-07-30; docs/backlog.md tracks the fix). Any FUTURE `<Key><TaskId>` format
change must land in EVERY parser that reads it, plus a discriminating test
proving the new shape parses, in the same commit — not just the cockpit's.

Enforcement: `stop-verdict-dispatcher.sh`'s vocabulary-lock check (Stop,
WARN-only — teaches, never blocks) scans the final assistant message for
off-vocabulary status phrasing; see its own header for the golden scenario, FP
estimate, and retirement condition.
