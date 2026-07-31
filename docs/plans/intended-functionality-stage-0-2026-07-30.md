# Plan: Intended-Functionality statement + anti-restatement gate (stage 0)
Status: ACTIVE
Execution Mode: orchestrator
Mode: code
Backlog items absorbed: none
acceptance-exempt: true
acceptance-exempt-reason: harness-internal; the maintainer is the user and the
  demonstration is the gate firing on real plan files plus the self-test suites,
  per constitution §4's harness clause. No product UI surface exists.
tier: 2
rung: 4
architecture: coding-harness
frozen: true
prd-ref: n/a — harness-development

## Intended Functionality

**Outcome (operator's terms):** When I ask for something and a plan is written for
it, I no longer get back work that satisfies the plan while leaving my situation
exactly as it was — because the plan cannot become ACTIVE until it says, in my own
words, what changes for me.

**Observation:** Committing a new plan whose stated intent names only an artifact
("the watchdog script exists and runs") is refused, and the refusal quotes the
offending noun and verb back to me. A plan that states an outcome in my terms commits
without comment.

**Deterministic pass/fail:** For a new plan file, `plan-reviewer.sh` exits non-zero
with a Check 19 finding when its Outcome is artifact-shaped, and exits with zero
Check 19 findings when it is outcome-shaped. Pre-existing plans emit exactly 0
blocking findings from Check 19.

**Explicitly NOT included:** Does not promise the statement is TRUE, that the named
surface exists, or that fluent outcome vocabulary hiding a component description is
caught — those return UNDECIDABLE and go to the operator. Does not retroactively
require the section of the 46 pre-existing plans the status guard covers.

**Human dependencies:**
- Operator answers a clarification request when the checker returns UNDECIDABLE — INTENDED
  (this is the stage-0 design: ambiguity is surfaced, never resolved by assumption)

## Goal

Build stage 0 of `docs/designs/end-to-end-process.md`: a required Intended-Functionality
statement on every plan, a mechanical anti-restatement check with an honestly-measured
false-positive rate, a plan-time gate wired where validation actually fires, and an
adversarial challenge remit for the agent that verifies functionality.

The operator's diagnosis: every downstream reviewer validates delivered work against
the plan's stated intent, so a component-level intent makes every later gate pass
component-level work. The failure recurses one level up.

## User-facing Outcome

The maintainer (the user, for harness work) can no longer author a plan whose stated
purpose is "a thing exists" and have the harness treat that as a specification.

## Scope

IN: the plan-template section; the checker script; `plan-reviewer.sh` Check 19; the
`functionality-verifier` adversarial remit; the doctrine file with five seeded real
cases; the test suite; the manifest entry; one backlog finding.

OUT: extending `manifest.schema.json` for `chokepoint`/`bypass_paths` (filed to backlog
— schema plus a 40-unit backfill is an operator-owned scope call); the
`functionality-verifier` trigger-scope and `--self-test` carve-out defects (already
fixed by a sibling session in commit `9b32b4b`); any change to the 46 pre-existing
plans.

## Walking skeleton

The thinnest end-to-end slice built first: `--outcome "<sentence>"` returning an exit
code, exercised against the operator's own counter-example, before any section parsing,
plan-file mode, or gate wiring existed. Every later layer (five-field extraction,
Check 19, the agent remit) hung off that proven core.

## Tasks

- [x] 1.1 `scripts/if-statement-check.sh` — three-verdict anti-restatement checker with
  `--outcome`, plan-file, `--corpus`, and `--self-test` modes. Verification: full
  **Prove it works:** 1. Run `bash adapters/claude-code/scripts/if-statement-check.sh
  --outcome "The watchdog script exists and runs."` → prints REJECT naming
  `artifact-subject='script'+existence-predicate='exists'`, exit 1. 2. Run it with
  "After a usage limit resets, my work continues without me touching anything." →
  prints ACCEPT, exit 0. 3. Run `--self-test` → 22/22, `self-test: OK`.
  **Wire checks:** `adapters/claude-code/scripts/if-statement-check.sh`
  (`if_check_outcome`) → `if_anti_restatement` → `adapters/claude-code/hooks/plan-reviewer.sh`
  (`IF_CHECKER`)
  **Integration points:** consumed by `plan-reviewer.sh` Check 19 — verify with
  `bash adapters/claude-code/hooks/plan-reviewer.sh <new-plan> 2>&1 | grep 'Check 19'`.

- [x] 1.2 Corpus measurement + two calibration fixes driven by it. Verification: full
  **Prove it works:**
  1. Run `bash adapters/claude-code/scripts/if-statement-check.sh --corpus docs/plans
     docs/plans/archive` → prints `corpus: total=193 measured=171 skipped-no-goal=22
     ACCEPT=24 REJECT=39 UNDECIDABLE=108` (denominator grows with the corpus; re-run
     rather than trusting the figure).
  2. Run `IF_CORPUS_DETAIL=1` with the same arguments → one tab-separated row per plan
     carrying the verdict, the plan basename, the sentence, and the firing reason.
  3. Confirm calibration fix (a) with a real corpus sentence: `--outcome "Every verifier
     in this harness checks delivered work against a plan."` → UNDECIDABLE. Reverting
     `work` into `IF_EXISTENCE_PREDICATES` turns the same sentence into
     `REJECT restatement:artifact-subject='harness'+existence-predicate='work'`
     (verified by reverting the vocabulary in a temp copy, 2026-07-30).
  4. Confirm calibration fix (b): `--outcome "The user-facing documentation reflects the
     current architecture."` → `UNDECIDABLE missing:human-referent`. Reverting the human
     lookup to hyphen-split word-mode turns the same sentence into
     `ACCEPT state-change+human-referent` — a FALSE ACCEPT, the dangerous direction
     (verified by reverting `first_hit(sp, humans)` to `first_hit(sw, humans)` in a temp
     copy, 2026-07-30).
  **Wire checks:** `adapters/claude-code/scripts/if-statement-check.sh` (`if_corpus`)
  → `adapters/claude-code/scripts/if-statement-check.sh` (`if_check_outcome`)
  → `adapters/claude-code/scripts/if-statement-check.sh` (`if_anti_restatement`)
  **Integration points:** reads real plan files under `docs/plans/` and
  `docs/plans/archive/` — verify the corpus is non-empty with
  `ls docs/plans/*.md docs/plans/archive/*.md | wc -l` (expect 287).

- [x] 1.3 `templates/plan-template.md` — required `## Intended Functionality` section
  with the five stage-0 fields. Verification: mechanical

- [x] 1.4 `hooks/plan-reviewer.sh` Check 19 — blocks a NEW plan from ACTIVE on a failing
  statement; WARNs on pre-existing; SKIPs outside a repo. Verification: full
  **Prove it works:** 1. Author a new plan under `docs/plans/` whose Outcome is "The
  watchdog script exists and runs." 2. Run `bash adapters/claude-code/hooks/plan-reviewer.sh
  <that file>` → a Check 19 REJECT finding naming the artifact subject. 3. Replace the
  Outcome with an operator-terms statement → 0 Check 19 findings. 4. Run against
  `docs/plans/accountable-estate-program-2026-07.md` (present in HEAD) → a WARN line
  only, no finding.
  **Wire checks:** `adapters/claude-code/hooks/pre-commit-gate.sh` (`PLAN_REVIEWER`)
  → `adapters/claude-code/hooks/plan-reviewer.sh` (`Check 19`) →
  `adapters/claude-code/scripts/if-statement-check.sh`
  **Integration points:** fires via `pre-commit-gate.sh` on staged `docs/plans/*.md` —
  verify with `grep -n 'PLAN_REVIEWER' adapters/claude-code/hooks/pre-commit-gate.sh`.

- [x] 1.5 `agents/functionality-verifier.md` — STEP ZERO adversarial challenge on the
  operator's three axes; may FAIL a build on the statement alone. Verification: contract

- [x] 1.6 `doctrine/intended-functionality.md` — the format, the anti-restatement rule,
  the five real 2026-07-30 defects as RED/GREEN worked examples, and an honest
  can/cannot-decide section. Verification: mechanical

- [x] 1.7 `tests/if-statement-check/run-tests.sh` — 16 behavioural + 9 mutation
  scenarios. Verification: full
  **Prove it works:** Run `bash adapters/claude-code/tests/if-statement-check/run-tests.sh`
  → 25/25 and `self-test: OK`; every mutation line reports "mutant died".
  **Wire checks:** `adapters/claude-code/tests/if-statement-check/run-tests.sh`
  (`CHECKER`) → `adapters/claude-code/scripts/if-statement-check.sh`
  **Integration points:** executes the real checker as a subprocess — verify with
  `bash adapters/claude-code/tests/if-statement-check/run-tests.sh 2>&1 | grep 'mutant died'`.

- [x] 1.8 `manifest.json` entry + `docs/backlog.md` finding on the doctrine-vs-schema
  contradiction. Verification: mechanical

## Files to Modify/Create

- `adapters/claude-code/scripts/if-statement-check.sh` — CREATE, the three-verdict checker
- `adapters/claude-code/tests/if-statement-check/run-tests.sh` — CREATE, behavioural + mutation suite
- `adapters/claude-code/doctrine/intended-functionality.md` — CREATE, format + five seeded real cases
- `adapters/claude-code/templates/plan-template.md` — MODIFY, add the required `## Intended Functionality` section
- `adapters/claude-code/hooks/plan-reviewer.sh` — MODIFY, add Check 19
- `adapters/claude-code/agents/functionality-verifier.md` — MODIFY, add the STEP ZERO adversarial remit
- `adapters/claude-code/manifest.json` — MODIFY, new gate entry
- `docs/backlog.md` — MODIFY, the doctrine-vs-schema contradiction finding
- `docs/plans/intended-functionality-stage-0-2026-07-30.md` — CREATE, this plan

## Assumptions

- `pre-commit-gate.sh` remains the invoker of `plan-reviewer.sh` for staged plan files;
  if that chain is rewired, Check 19 moves with it (it holds no independent trigger).
- A plan's presence in `HEAD` is a sound proxy for "pre-existing", because plan files
  are only created through the repo. A plan created and committed in the same session
  is correctly treated as new.
- The five required fields are stable as specified in `end-to-end-process.md` stage 0;
  the checker's field extraction keys on their `**Label:**` form.
- Vocabulary-and-word-order matching is a floor, not a ceiling: `functionality-verifier`
  supplies the judgement layer. This assumption is load-bearing for the whole design and
  is stated in the script header, the doctrine, and the manifest entry.

## Edge Cases

- Long multi-clause sentences: "artifact before predicate" degrades to chance, so R1 is
  bounded to an 8-word subject window (found by the corpus run).
- Adjectival predicates before the subject noun ("The running chip renders…"): the
  globally-first predicate is not the main verb, so the predicate search starts after
  the artifact subject.
- Compound nouns vs compound adjectives: matched asymmetrically on purpose —
  artifacts hyphen-split (so "self-test" is a test), humans do not (so "user-facing"
  names no user).
- Unfilled template: bracketed placeholder text must not read as a populated field, and
  must not trip the DEFECT check on the template's own instruction line.
- Checker missing at runtime: fails OPEN with a WARN — a harness-side fault must not
  block every plan edit.
- Plan outside a git repository: SKIP, since new-vs-pre-existing is undecidable there.

## Testing Strategy

Two executing suites, both run sequentially on `/bin/bash` 3.2.57 AND
`/opt/homebrew/bin/bash` 5.3.15 by absolute path:

1. `if-statement-check.sh --self-test` — 22 scenarios: the operator's counter-example
   and four sibling restatements must REJECT; the five real defects stated correctly
   must ACCEPT; two must return UNDECIDABLE; six plan-file scenarios cover missing
   section, restatement, DEFECT dependency, non-deterministic rule, and unfilled
   template.
2. `tests/if-statement-check/run-tests.sh` — 16 behavioural assertions that execute the
   checker as a subprocess, plus 9 MUTATION scenarios that break the checker and require
   the fixture to flip. The suite verifies each mutation actually applied (`cmp`), so a
   stale pattern reports as a test bug rather than a surviving mutant.

Plus: `manifest-check.sh` GREEN; `plan-reviewer.sh --self-test` compared against the
unmodified HEAD baseline to prove no regression; and the gate exercised against real
plan files for all four paths (new+restatement, new+missing, new+correct, pre-existing).

## Definition of Done

- A new plan whose Outcome is artifact-shaped cannot be committed without a Check 19
  finding, and the finding names the offending noun and verb.
- A new plan whose Outcome is operator-shaped commits with zero Check 19 findings.
- No pre-existing ACTIVE plan is blocked.
- Both suites green on both bash builds; `manifest-check.sh` GREEN; `plan-reviewer.sh`
  self-test no worse than the HEAD baseline.
- The checker's limits are stated in the artifact, the doctrine, and the manifest, and
  the corpus measurement is reported with its caveat rather than as a precision claim.

## Behavioral Contracts

### Idempotency
Check 19 is a pure read: it parses the staged plan file and shells out to a checker
that writes nothing. Running it N times on the same plan yields the same verdict and
mutates no state — no ledger row, no marker, no cache. Re-running `plan-reviewer.sh`
after a failed commit is therefore always safe, and a plan that passes once passes
again unless its own bytes change. The corpus mode is likewise read-only.

### Performance budget
The checker is one `awk` process per field plus one per outcome sentence — measured at
well under 100ms for a single plan, against a `pretool` budget class where the whole
pre-commit chain targets a few seconds. Check 19 adds one subprocess per staged plan
file, and plans are staged one or two at a time. The `--corpus` mode over 170 real
plans is the heavy path (a few seconds) and is never on the commit path — it is a
manual measurement tool only.

### Retry semantics
There is no retry and none is needed: the check is deterministic and offline, with no
network, no lock, and no external service. A failure is a verdict, not a transient
fault, so retrying without editing the plan is guaranteed to produce the same result.
The one non-verdict outcome — checker not found on disk — deliberately fails OPEN with
a WARN rather than retrying or blocking, because a missing harness dependency is
unsatisfiable from the layer that hit it.

### Failure modes
(1) Checker missing → WARN, plan allowed, requirement not validated; loud on stderr.
(2) Plan outside a git repository → SKIP, since new-vs-pre-existing cannot be decided.
(3) UNDECIDABLE verdict → blocks a NEW plan with a message instructing operator
clarification, never rewording; this is the designed escalation, not an error.
(4) False ACCEPT on component-shaped prose using outcome vocabulary → the known
residual (~2 per 20 measured); `functionality-verifier` STEP ZERO is the compensating
judgement layer. (5) `awk` absent → the checker errors and Check 19 surfaces a
non-zero verdict; acceptable, as every other harness gate already depends on `awk`.

## Decisions Log

- **Three verdicts, not two.** UNDECIDABLE routes to the operator instead of guessing.
  A binary checker would have to guess on exactly the cases the operator said need a
  human, which reproduces the defect.
- **Gate at the pre-commit funnel, not the editor.** `plan-edit-validator.sh` is the
  convenient early layer; `pre-commit-gate.sh → plan-reviewer.sh` is the funnel every
  plan traverses (deterministic-process rule 1). No new unwired gate was invented.
- **Grandfather by HEAD-presence.** Blocking all 53 legacy ACTIVE plans would have made
  the gate's first act 53 false blocks — the documented path by which a Mechanism gets
  overridden into a Pattern.
- **Schema contradiction filed, not fixed.** `chokepoint`/`bypass_paths` are mandated by
  doctrine and forbidden by the schema; fixing it touches 40 units and is an
  operator-owned call. Content preserved inline in `honest_status`.
- **Additive edits to `functionality-verifier.md`.** A sibling session (`9b32b4b`) had
  already fixed the two known defects; edits were kept out of the regions it rewrote so
  the commits do not conflict.
