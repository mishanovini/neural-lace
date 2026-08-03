# Operator-requirement ledger — compact

> Enforcement: PATTERN (agent-invoked) over a MECHANISM (the store + the check
> command). No hook fires it. See manifest `operator-requirement-ledger`.
> Full: `operator-requirement-ledger-full.md` (complete step-by-step CLI detail).
> Applies: when the operator states a requirement you are about to build to.

Every verifier in this harness checks work against a PLAN. Nothing checked it against the
operator's actual words. The plan is your interpretation, so verifiers faithfully verify the
interpretation — including its losses.

## The failure this exists to stop

You treat a requirement as a GOAL TO DISCHARGE rather than a SPECIFICATION WITH INVARIANTS.
Once something satisfies the verb, you stop reading the rest of the sentence.

- "Fable is supposed to always fail back to Opus." → a gate BLOCKED the dispatch and told the
  caller to use Opus. Satisfied "use Opus"; destroyed "automatically".
- "I don't want the agents to pin Opus. Opus is a fallback, not the primary option." → 21
  agents were permanently repinned to Opus. Satisfied "Opus as fallback"; destroyed "Fable is
  primary".

One sentence, two invariants, one preserved. Both passed plan-based review.

## The discipline

1. **Store the sentence verbatim.** Never a paraphrase — the paraphrase IS the lossy step.
   `record-requirement --ask-id <id> --verbatim '<exact words>'`. Use the id it prints.
2. **Decompose into separately checkable invariants.** Ask of every clause: *what would still
   be true if I built this right?* Each answer is one `declare-invariant --requirement-id <id>
   --text '<statement>'`. Negative/implicit clauses count — "not the primary option", "always".
   One invariant from a sentence is a smell — look for the sibling.
3. **Return a verdict per invariant, with a citation.** `invariant-verdict --requirement-id <r>
   --invariant-id <i> --verdict holds|violated|unverifiable --evidence <file:line|path|SHA>`.
   An unevidenced `holds` is refused. `violated`/`unverifiable` need no evidence.
4. **Check before claiming done.** `invariant-check --plan-slug <slug>`. Exit 0 = all hold;
   1 = violated/unverifiable/unverified; **3 = nothing registered; 4 = cannot evaluate** — 3
   and 4 are NOT passes; a degraded read is never green.

Storage is `ask-registry.sh` — no new store. Verdicts fold last-wins; absence folds to
`unverified`, never to a pass.

## Honest limits

Nothing forces you to record a requirement — no hook watches the prompt stream. An unenrolled
ask returns exit 3, so the ledger is silent until used. Verdict staleness is not modelled: a
`holds` recorded against one commit is not invalidated by later commits — cite a SHA and
re-verify.
