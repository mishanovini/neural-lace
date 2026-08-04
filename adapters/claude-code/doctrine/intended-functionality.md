# Intended Functionality — compact (the IF statement)

> Enforcement: `plan-reviewer.sh` Check 19, via `pre-commit-gate.sh` on staged `docs/plans/*.md`.
> BLOCKS a plan not already ACTIVE in HEAD; WARNs if already ACTIVE; SKIPs non-ACTIVE/non-repo.
> UNDECIDABLE currently WARNs (warn-mode cycle). Logic: `scripts/if-statement-check.sh`. Stage 0
> of `docs/designs/end-to-end-process.md`. Full: `intended-functionality-full.md` (five worked
> defect cases, calibration history, two adversarial-review escapes). Operator directive
> 2026-07-30: *"'the watchdog script exists and runs' is not a functionality."*

## Why this exists

Every downstream reviewer validates delivered work against the plan's stated intent. If intent
is stated at the component level, every later gate passes component-level work — **garbage in,
garbage out.** Fixing the verifiers cannot fix this; only fixing the statement they validate
against can. An IF statement is the contract — five required fields.

## The five fields

| Field | What it must contain |
|---|---|
| **Outcome (operator's terms)** | What becomes true for them — observable surface + state change, their words. |
| **Observation** | How anyone tells it happened, without reading code. |
| **Deterministic pass/fail** | No judgement call — a threshold, count, or comparator. |
| **Explicitly NOT included** | What this does not promise. |
| **Human dependencies** | Every human action required, each marked INTENDED or DEFECT. |

**A dependency marked DEFECT fails stage 0 immediately** — a person is holding the system
together, not the system.

## The anti-restatement rule

A statement naming only artifacts is REJECTED. The test:

> **Could this sentence be true while the operator's situation is unchanged?**

If yes, it's a component description — "the script exists", "the gate is wired", "the migration
ran" can all be true while the operator's day is exactly as bad as it was. **If you cannot write
a statement that passes, ASK THE OPERATOR** — do not invent one to clear the gate.

## Verdicts (three, not two)

| Verdict | Exit | Meaning |
|---|---|---|
| ACCEPT | 0 | Positive evidence of functionality; no restatement signal. |
| REJECT | 1 | Restatement, delivery imperative, missing field, DEFECT dependency, or non-deterministic rule. |
| UNDECIDABLE | 2 | **Not a pass.** The checker cannot decide — a human must clarify. |

**It catches** an artifact noun in subject position with an existence/wiring predicate and no
state change, plus delivery-imperative openers. Coverage is bounded by its vocabularies (full
doctrine: two known escapes) — by design: `functionality-verifier` STEP ZERO is the judgement
layer; UNDECIDABLE keeps a human in stage 0 instead of guessing.

## Cross-references

`docs/designs/end-to-end-process.md` (stage 0) · `doctrine/deterministic-process.md` (Check 19,
rule 1) · `agents/functionality-verifier.md` · `templates/plan-template.md`'s `## Intended
Functionality` section.
