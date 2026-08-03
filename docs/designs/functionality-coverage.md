# Functionality coverage — one IF statement per functionality

Status: DESIGN. Nothing in §6 is built yet; §7 is the honest scorecard.
Supersedes nothing. Extends `docs/designs/end-to-end-process.md` stage 0.
Operator directive, 2026-07-31 (verbatim):

> "most designs should have far more than a single IF statement. We do not need to
> enforce a certain number of IF statements in a design because there's no reasonable
> way to do that, but we should guide the designer to ensure that every functionality
> within the design needs to have its own IF statement. […] the designer reviewer agent
> needs to be designed specifically to look for any functionalities that do not have an
> IF statement. In fact, I imagine there could be scenarios where a design is created
> without any functionalities, in which case the design reviewer's job is to validate
> that it in fact does not."

## 1. The defect this fixes

Stage 0 shipped and is blocking: `plan-reviewer.sh` Check 19 refuses a new ACTIVE plan
whose `## Intended Functionality` section fails `scripts/if-statement-check.sh`.

It validates **one statement per plan**. `if_extract_section` (`if-statement-check.sh:374`)
prints the body of a single `## Intended Functionality` heading, and `:436-440` pull exactly
five scalar fields out of it. So a plan delivering eight functionalities satisfies the gate
with one sentence about one of them. **The remaining seven are unexamined** — and those are
exactly the unspecified components the operator keeps receiving.

The count is not the property. **Coverage is.** Enforcing "≥ N statements" is both
unmeasurable and gameable; enforcing "every functionality has one" is neither, provided
"a functionality" is defined. §2 defines it.

## 2. The unit — the independent-failure test

Without a unit, the rule is free to game: the cheapest evasion is one compound sentence
joined by "and", and the cheapest padding is splitting one outcome into its own steps.

> **Two claimed outcomes are ONE functionality if neither can fail while the other
> succeeds. They are TWO if either can fail alone AND the operator would notice that
> failure by itself.**

Both directions fall out of it:

- *"The gate blocks bad pushes and logs them."* Logging can fail while blocking succeeds,
  and the operator would notice a missing log. → **two** functionalities, two IF statements.
- *"The parser opens the file"* + *"the parser returns a list."* The second cannot succeed
  if the first fails, and neither is observable alone. → **one** functionality.

The test is deliberately observer-relative: it asks what the operator can distinguish, not
what the implementation separates. A distinction no one can observe is not a functionality.

## 3. What the designer does

Every functionality gets its own block, with the five fields stage 0 already defines:

```
### IF-1: <short name>
**Outcome (operator's terms):** …
**Observation:** …
**Deterministic pass/fail:** …
**Explicitly NOT included:** …
**Human dependencies:** …
```

**Backward compatibility is load-bearing.** 193 plan files exist and 171 are scored today.
A single unlabelled block stays valid and means "one functionality." No existing plan
becomes invalid on the day this lands; if it did, the mechanism would be abandoned within
a week, which is the trust-erosion shape that turns a Mechanism into an override habit.

## 4. What the design-coverage reviewer does

The reviewer's job is **finding what is absent**, which is a different task from checking
what is present, and it fails in a specific way if the phases are ordered wrongly.

**Phase 1 — independent enumeration, BEFORE reading any IF statement.** The reviewer reads
the design with the `## Intended Functionality` section withheld, and writes its own list of
functionalities using §2's test. This phase is the whole design. A reviewer that reads the
author's list first is anchored to it and can only validate what is there — it becomes
*structurally incapable* of finding the omission it exists to find. `architecture-reviewer`
already runs mandatory anti-anchoring for the same reason; this is that discipline applied
to coverage.

**Phase 2 — read the declared statements.**

**Phase 3 — set-difference, both directions.**
- *Derived but not declared* → the target defect: a functionality with no IF statement.
- *Declared but not derived* → over-declaration: an IF statement for something the design
  does not actually build. This is vaporware caught at design time, and it is worth as much
  as the first direction.

**Phase 4 — the zero-IF case, where the burden of proof inverts.** When a design declares no
functionalities, the reviewer's job is to *disprove* that claim, not to accept it. Known
traps in this repo, each of which has actually occurred:
- `doctrine/*.md` looks like pure prose but is injected into agents at runtime by
  `doctrine-jit.sh` — editing it **is** a behavior change.
- A changed default value is a functionality change with no new code.
- A rename changes what a string-keyed consumer resolves.
- **Deletion is a functionality.** Removing behavior needs its own IF ("the operator no
  longer sees X"). Otherwise silent regressions pass as "no new functionality" — the
  cheapest way to break something while giving the reviewer nothing to look at.
A design that survives this check is genuinely functionality-free and passes. Most do not.

**Phase 5 — per-functionality, not per-design:**
- *Failure branch.* Every IF states what happens when its condition cannot be evaluated —
  fail-open or fail-closed, named. All three CRITICALs closed on 2026-07-30 were the same
  shape: degraded diff range → allowed; C-quoted path → out of surface; `chmod -x` → no hook
  ran. Every one silent, every one fail-open. An IF stating only its success outcome
  reproduces that class exactly.
- *Human dependency.* Declared per functionality. A design can be 90% automatic with one
  human step hidden inside an aggregate statement — and per the operator's standing rule, a
  human dependency in something intended to be automatic is a FAIL, not a caveat.

**Phase 6 — interaction.** N individually-correct functionalities can still be wrong in
combination, where A disables B. Per-functionality statements cannot see this by
construction, so it is one explicit cross-cutting question, not an emergent property.

**Phase 7 — ONE aggregated escalation.** Measured today: 108 of 171 scored plans return
UNDECIDABLE, and UNDECIDABLE routes to the operator by design. Multiplied by N
functionalities per design, a naive implementation becomes a machine whose output is
operator interrupts — against an operator who has already said the nudging is burdensome.
The reviewer emits **one** block per design listing every unresolved statement, never one
per statement. This is a hard requirement, not a preference.

## 5. This document's own functionalities (dogfooding §2)

### IF-1: a plan can declare more than one functionality
**Outcome:** When I write a design that does five things, the harness checks all five instead
of the one I happened to write down first.
**Observation:** `if-statement-check.sh` on a five-block plan reports five verdicts; today it
reports one.
**Deterministic pass/fail:** Block count returned == block count present in the file.
**Explicitly NOT included:** Any minimum count. There is no reasonable way to enforce one.
**Human dependencies:** None — extraction is mechanical.

### IF-2: a functionality with no IF statement is named
**Outcome:** A reviewer tells me which parts of my design nobody specified an outcome for,
before it is built.
**Observation:** The review names a functionality present in the design body and absent from
the declared set.
**Deterministic pass/fail:** Non-empty derived-minus-declared set ⇒ finding.
**Explicitly NOT included:** Judging whether a declared outcome is TRUE. That is stage 0's
anti-restatement rule plus a human, and remains so.
**Human dependencies:** Phase 1 enumeration is LLM judgement, not mechanical. Declared, not
hidden — this is a Pattern layered over a Mechanism, and §7 labels it that way.

### IF-3: a zero-functionality design is validated, not assumed
**Outcome:** When I claim a change does nothing observable, someone actively tries to prove
me wrong before it lands.
**Observation:** The review cites the specific consumer that would turn the change into
behavior, or states that it ruled out each trap in Phase 4 by name.
**Deterministic pass/fail:** Zero declared ⇒ Phase 4 must be present and enumerate each trap.
**Explicitly NOT included:** Proving a universal negative. The reviewer rules out the *known*
classes and says so; it does not claim exhaustiveness.
**Human dependencies:** Same as IF-2.

## 6. Chokepoint

The mechanical half needs no new wiring: `if-statement-check.sh` is already invoked by
`plan-reviewer.sh` Check 19 off `pre-commit-gate.sh`, so multi-block extraction inherits an
existing chokepoint that every new ACTIVE plan crosses.

**The reviewer half has no invoker, and this document does not claim one.** Per
`doctrine/deterministic-process.md` rule 3, a step nothing invokes is not part of the
process. Until an invoker exists, Phases 1-7 are a Pattern — real when run, skippable when
not. The candidate chokepoint is the same Check 19 path, requiring a coverage record for
plans declaring more than one functionality; that is a separate change with its own §10
obligations (golden scenario, expected false-positive rate, retirement condition) and is
NOT part of this design.

## 7. Honest scorecard

| Piece | State |
|---|---|
| Single-IF checking, blocking | **BUILT** — Check 19, manifest entry with 7 enumerated bypasses |
| §2 decomposition unit | **DESIGN ONLY** |
| Multi-block extraction in the checker | **NOT BUILT** |
| Multi-block plan template | **NOT BUILT** |
| Design-coverage reviewer (Phases 1-7) | **NOT BUILT** |
| An invoker for the reviewer | **NOT BUILT, NOT DESIGNED** — §6 |

No part of §4 fires today. This table is the claim; anything else in this file describing
the reviewer is describing intent.
