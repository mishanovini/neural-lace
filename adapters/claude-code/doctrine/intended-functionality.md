# Intended Functionality — the IF statement

> Enforcement: `plan-reviewer.sh` Check 19, fires via `pre-commit-gate.sh` on staged
> `docs/plans/*.md`. SCOPED, deliberately: BLOCKS a plan that is not already ACTIVE in
> HEAD (i.e. new work, and DRAFT->ACTIVE flips); WARNs on plans already ACTIVE in HEAD;
> SKIPs plans whose `Status:` is not ACTIVE and any plan outside a repository. An
> UNDECIDABLE verdict currently WARNs rather than blocks (warn-mode cycle).
> Decision logic: `scripts/if-statement-check.sh`.
> Stage 0 of `docs/designs/end-to-end-process.md`.
> Operator directive 2026-07-30: *"'the watchdog script exists and runs' is not a
> functionality."*

## Why this exists

Every downstream reviewer in this harness validates delivered work against the plan's
stated intent. So if the intent is stated at the component level, every later gate
passes component-level work and reports success. **The failure recurses one level up:
garbage in, garbage out.** Fixing the verifiers cannot fix this; only fixing the
statement they validate against can.

An IF statement is the contract. It has five required fields and it is required on
every plan.

## The five fields

| Field | What it must contain |
|---|---|
| **Outcome (operator's terms)** | What becomes true for them. Names an observable surface AND a state change. In their words, not the implementer's. |
| **Observation** | How anyone tells it happened, without reading code. |
| **Deterministic pass/fail** | The rule that decides, with no judgement call. Needs a threshold, count, or comparator. |
| **Explicitly NOT included** | What this does not promise. |
| **Human dependencies** | Every human action the outcome requires, each marked INTENDED or DEFECT. |

**Any dependency marked DEFECT fails stage 0 immediately.** An unintended human step
means the outcome is not actually delivered — it means a person is holding the system
together. The watchdog's answer was "the operator must arm the marker": DEFECT, and it
fails at stage 0 rather than being discovered after the build.

## The anti-restatement rule

A statement that names only artifacts is REJECTED. The test:

> **Could this sentence be true while the operator's situation is unchanged?**

If yes, it is a component description. "The script exists", "the gate is wired", "the
field renders", "the endpoint returns 200", "the migration ran", "the suite passes" —
every one of these can be true while the operator's day is exactly as bad as it was.

**If you cannot write a statement that passes, ASK THE OPERATOR.** Do not invent one to
clear the gate. Ambiguity at stage 0 is surfaced, never resolved by assumption — that is
why this stage has a human in it. The gate's UNDECIDABLE verdict exists precisely to
route you there rather than let you guess.

## The five seeded cases — real defects of 2026-07-30

Each pairs the WRONG statement (which a component-level review would have passed) with
the statement that would have caught the defect at plan time. The wrong versions are the
RED fixtures in `tests/if-statement-check/`.

### 1. The watchdog that was never armed

Marker consumed by a script, written by nobody (`deterministic-process.md` rule 3).

- **WRONG:** *"The watchdog script exists and runs."*
  → REJECT: artifact subject (`script`) + existence predicate (`exists`).
- **RIGHT:** *"After a usage limit resets, my work continues without me touching
  anything."*
  - Observation: the session resumes on its own; the transcript shows activity
    timestamped after the reset.
  - Deterministic pass/fail: resumption happened within 5 minutes of the reset with
    zero human actions recorded in between.
  - Human dependencies: *operator must arm the marker* — **DEFECT**. Fails stage 0.
    That is the whole finding, available before a line was written.

### 2. The shape-only test that passed while the feature was broken

`cockpit.selftest.js` R17-DRAG-2 asserted behavior with a regex over source text
(commit `9fb634d`).

- **WRONG:** *"The self-test passes with 499 assertions."*
  → REJECT: artifact subject (`self-test`) + existence predicate (`passes`).
- **RIGHT:** *"When I break a behaviour the suite claims to cover, the suite goes red
  and I see the failure."*
  - Deterministic pass/fail: for each claimed behavior, mutating the implementation
    turns at least 1 assertion red.

### 3. The drag that was a silent no-op

`performDrop` resolved both rows to the same group, so `insertBefore` never ran
(commit `b66f7e1`).

- **WRONG:** *"The drag handler is wired to performDrop."*
  → REJECT: artifact subject (`handler`) + existence predicate (`wired`).
- **RIGHT:** *"When I drag a plan row onto another group, the row appears in that group
  and stays there after I reload."*
  - Deterministic pass/fail: after drop + reload, the row's parent group id equals the
    drop target's group id.

### 4. The running signal that meant nothing

Green chips meant "a session that once touched this is alive" (commit `ebc9a12`).

- **WRONG:** *"The running chip renders green when a session is attached."*
  → REJECT: artifact subject (`chip`) + existence predicate (`renders`).
- **RIGHT:** *"A green running chip means work is progressing for me right now, and it
  turns grey within a minute of that work stopping."*
  - Deterministic pass/fail: every green chip corresponds to a task with activity in
    the last 5 minutes; zero green chips without one.
  - *(Note the phrasing: an earlier draft, "When I see a green running chip, a task is
    genuinely working for me right now", leans on a perception verb and names no state
    change — it is UNDECIDABLE, not ACCEPT. Stating what CHANGES, and when, is what
    makes an outcome checkable.)*

### 5. The self-learning machinery that never triggered

`/calibrate` — zero entries, ever (`deterministic-process.md` rule 3).

- **WRONG:** *"The calibration command is registered and documented."*
  → REJECT: artifact subject (`command`) + existence predicate (`registered`).
- **RIGHT:** *"When I correct the same mistake twice, I stop seeing it a third time
  without filing anything."*
  - Deterministic pass/fail: a correction repeated twice produces at least 1 durable
    entry with zero operator actions beyond the correction itself.

## What the checker can and cannot decide

`scripts/if-statement-check.sh` returns **three** verdicts, not two — because pretending
to a binary answer it cannot support is how a gate becomes theatre.

| Verdict | Exit | Meaning |
|---|---|---|
| ACCEPT | 0 | Positive evidence of functionality; no restatement signal. |
| REJECT | 1 | A hard signal fired: artifact-subject restatement, leading delivery imperative, missing/unpopulated field, DEFECT human dependency, or a non-deterministic pass/fail rule. |
| UNDECIDABLE | 2 | **Not a pass.** The checker cannot decide. A human must clarify. |

**It catches** the shape the operator named — an artifact noun in subject position
carrying an existence/wiring predicate with no state change anywhere in the sentence —
and sentences that open by commanding a build ("Build v1 of the UI", "Seed the
templates"). That coverage is **bounded by its vocabularies**: a restatement built from
nouns or verbs absent from those lists is not caught. It is a floor, not a guarantee.

Two worked examples of the bound, both real escapes found by adversarial review:

**Escape 1 — the prefix, CLOSED.** `"I see the watchdog script exists and runs."`
ACCEPTed in the first draft, because naming a person vetoed the restatement rule — the
gate passed its own declared counter-example. Fixed by making the veto turn on the
absence of a STATE CHANGE rather than the absence of a person, and by excluding
perception verbs ("see", "notice") from the change vocabulary. Both the sentence and a
mutation that re-opens the hole are now fixtures.

**Escape 2 — the suffix, OPEN and NOT CLOSED.** Appending one clause about what the
artifact *does* satisfies the state-change test and vetoes the restatement rule:

```
"The gate is wired into pre-commit and blocks bad commits for the team."   -> ACCEPT
"The hook is registered in settings.json and starts on every user session." -> ACCEPT
```

Both open with WRONG examples from this very page. **The reword costs one appended
clause** — not sophistication, not determination. This is not closed, and the closure
that suggests itself (requiring the change verb's subject to BE the human referent)
was rejected because it false-blocks legitimate outcomes whose subject is a thing:
*"my work continues without me touching anything"* has the subject "work", not a person.

So: **a mechanical vocabulary matcher cannot decide this class, and this one does not
pretend to.** It raises the floor — you cannot state a bare component description — but
an author who wants to dress one up can. That is precisely why `functionality-verifier`
STEP ZERO challenges the statement with judgement, and why stage 0 keeps a human in it.

**It cannot decide** whether a well-formed sentence is TRUE, whether the surface it names
really exists, or whether fluent outcome vocabulary is hiding a component description. It
matches vocabulary and word order; it does not parse grammar and it does not know your
domain. Those cases return UNDECIDABLE and belong to a human — which is the design, not a
shortfall to be quietly patched with more keywords.

**Measured false-positive behavior.** Reproduce with:

```
bash adapters/claude-code/scripts/if-statement-check.sh --corpus docs/plans docs/plans/archive
```

Measured 2026-07-30 on branch `wip/harness-hardening-2026-07-29`: 193 plan files, 171
measured, 22 skipped for no usable `## Goal` — **ACCEPT 24 · REJECT 39 · UNDECIDABLE
108**. The denominator grows as plans are added, so re-run rather than trusting the
number. **Caveat, stated plainly: a `## Goal` sentence is NOT an IF statement**, so this
measures behavior on prose never written to this contract — it is not a precision figure
for real IF statements, of which none existed when it was taken.

Three calibration passes were driven by that corpus and by adversarial review, each
recorded at its site in the script:
1. `work` / `run` / `pass` / `fire` removed from the predicate vocabulary (noun-dominant
   in real prose — they alone caused 9 of 34 false rejections).
2. Human referents matched WITHOUT hyphen-splitting, so compound adjectives
   ("user-facing", "end-user", "customer-facing") stop counting as references to a
   person — that one was producing false ACCEPTs, the dangerous direction.
3. `ship` / `file` / `land` / `write` / `produce` / `port` / `update` removed from the
   delivery-imperative vocabulary — all common sentence-initial NOUNS ("Ship dates stop
   slipping"), and the rule matches the literal first word.

## Cross-references

- `docs/designs/end-to-end-process.md` — stage 0 and the handoff contracts.
- `doctrine/deterministic-process.md` — the three rules; Check 19 enforces at the
  pre-commit funnel every staged plan traverses (rule 1).
- `agents/functionality-verifier.md` — adversarially challenges the IF statement on
  clarity, determinism, and delivery, and can FAIL a build on the statement alone.
- `templates/plan-template.md` — the `## Intended Functionality` section.
