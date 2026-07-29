# Operator-requirement ledger — compact
> Enforcement: PATTERN (agent-invoked) over a MECHANISM (the store + the check
> command). No hook fires it. See manifest `operator-requirement-ledger`.
> Applies: when the operator states a requirement you are about to build to.

Every verifier in this harness checks work against a PLAN. Nothing checked it
against the operator's actual words. The plan is your interpretation, so the
verifiers faithfully verify the interpretation — including its losses.

## The failure this exists to stop

You treat a requirement as a GOAL TO DISCHARGE rather than a SPECIFICATION
WITH INVARIANTS. Once something satisfies the verb, you stop reading the rest
of the sentence, then write a confident rationale for why that was right.

- "Fable is supposed to always fail back to Opus." → a gate was built that
  BLOCKED the dispatch and told the caller to use Opus. Satisfied "use Opus";
  destroyed "automatically".
- "I don't want the agents to pin Opus. Opus is a fallback, not the primary
  option." → 21 agents were permanently repinned to Opus. Satisfied "Opus as
  fallback"; destroyed "Fable is primary".

One sentence, two invariants, one preserved. Both passed plan-based review.

## The discipline

1. **Store the sentence verbatim.** Never a paraphrase — the paraphrase IS the
   lossy step. `record-requirement --ask-id <id> --verbatim '<exact words>'`.
2. **Decompose it into separately checkable invariants.** Ask of every clause:
   *what would still be true if I built this right?* Each answer is one
   `declare-invariant --requirement-id <id> --text '<statement>'`. Negative and
   implicit clauses count: "not the primary option" and "always" are invariants.
   A sentence yielding only one invariant is a smell — look again for the sibling.
3. **Return a verdict per invariant, with a citation.**
   `invariant-verdict --requirement-id <r> --invariant-id <i> --verdict
   holds|violated|unverifiable --evidence <file:line|command|SHA>`.
   `holds` without `--evidence` is refused: an unevidenced pass is the defect.
4. **Check before claiming done.** `invariant-check --plan-slug <slug>`
   (or `--ask-id` / `--requirement-id`). Exit 0 = all hold; 1 = something is
   violated/unverifiable/unverified; **3 = nothing registered; 4 = cannot
   evaluate.** 3 and 4 are NOT passes — a degraded read is never green.

Storage is `ask-registry.sh` (records `requirement_recorded`,
`invariant_declared`, `invariant_verdict`) — no new store, per the ≤3-store
consolidation goal. `invariants` prints the TSV. Verdicts fold last-wins;
absence folds to `unverified`, never to a pass.

## Honest limits

Nothing forces you to record a requirement — no hook watches the prompt stream
(automatic extraction is the retired goal-coverage class, ADR 058 D5). An
unenrolled ask returns exit 3, so the ledger is silent until used. Verdict
staleness is not modelled: a `holds` recorded against one commit is not
invalidated by later commits — cite a SHA in `--evidence` and re-verify.
