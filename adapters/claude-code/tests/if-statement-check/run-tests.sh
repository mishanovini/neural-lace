#!/bin/bash
# run-tests.sh — behavioural + MUTATION test suite for the anti-restatement checker.
#
# The point of this file is the mutation proof. A green assertion suite proves
# nothing unless breaking the thing under test turns it RED — that is the exact
# defect class (shape-only assertions, commit 9fb634d) this whole workstream exists
# to close, so this suite is not permitted to exhibit it.
#
# Phase 1 — behavioural: run the real checker as a subprocess, assert real exit codes.
# Phase 2 — MUTATION:    break the checker in a specific, targeted way; re-run the
#                        SAME fixture; require it to flip. A mutant that survives is
#                        reported as a FAILURE, because it means the assertion was
#                        not actually testing the logic it claims to test.
#
# Usage: bash run-tests.sh
# Portability floor: /bin/bash 3.2.57.

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
CHECKER="$HERE/../../scripts/if-statement-check.sh"

PASSED=0
FAILED=0

if [[ ! -f "$CHECKER" ]]; then
  echo "FATAL: checker not found at $CHECKER" >&2
  exit 2
fi

# --------------------------------------------------------------------------
# Phase 1 — behavioural assertions (each EXECUTES the checker)
# --------------------------------------------------------------------------
assert_outcome() {
  local name="$1" want="$2" text="$3" out rc
  out="$(bash "$CHECKER" --outcome "$text" 2>&1)"; rc=$?
  if [[ "$rc" == "$want" ]]; then
    echo "  PASS  $name" >&2; PASSED=$((PASSED+1))
  else
    echo "  FAIL  $name — want exit $want, got $rc ($out)" >&2; FAILED=$((FAILED+1))
  fi
}

echo "== Phase 1: behavioural ==" >&2

# THE OPERATOR'S OWN COUNTER-EXAMPLE. This is the load-bearing fixture.
assert_outcome "RED-fixture: operator counter-example must REJECT" 1 \
  "The watchdog script exists and runs."

# The five real 2026-07-30 defects, stated WRONG (component-level). All must REJECT.
assert_outcome "RED: shape-only test"    1 "The self-test passes with 499 assertions."
assert_outcome "RED: drag handler"       1 "The drag handler is wired to performDrop."
assert_outcome "RED: running chip"       1 "The running chip renders green when a session is attached."
assert_outcome "RED: calibrate command"  1 "The calibration command is registered and documented."

# C1 REGRESSION (harness-reviewer, 2026-07-30). The golden scenario with the block
# message's own advice applied as a three-word framing clause. Naming a person must NOT
# rescue a restatement, and PERCEPTION ("I see...") is not a state change. This shape
# ACCEPTed before the fix, i.e. the gate passed its own declared counter-example.
assert_outcome "RED: framing-clause evasion of the golden scenario" 1 \
  "I see the watchdog script exists and runs."
assert_outcome "RED: framing-clause evasion, third person" 1 \
  "When I check, the operator sees the gate is wired."

# M7 REGRESSION: a sentence-initial NOUN that also appears in the delivery-imperative
# vocabulary must not be read as a build instruction.
assert_outcome "GREEN: noun-initial 'Ship dates' is not a delivery imperative" 0 \
  "Ship dates stop slipping and I get the new estimate."

# The same five, stated correctly. All must ACCEPT.
assert_outcome "GREEN: watchdog"  0 \
  "After a usage limit resets, my work continues without me touching anything."
assert_outcome "GREEN: shape-only" 0 \
  "When I break a behaviour the suite claims to cover, the suite goes red and I see the failure."
assert_outcome "GREEN: drag" 0 \
  "When I drag a plan row onto another group, the row appears in that group and stays there after I reload."
assert_outcome "GREEN: running chip" 0 \
  "A green running chip means work is progressing for me right now, and it turns grey within a minute of that work stopping."
assert_outcome "GREEN: calibrate" 0 \
  "When I correct the same mistake twice, I stop seeing it a third time without filing anything."

# Undecidable — must be neither ACCEPT nor REJECT, so it routes to the operator.
assert_outcome "UNDECIDABLE: no human referent" 2 "Latency improves across the estate."

# CORPUS-DRIVEN REGRESSION FIXTURES. Both are real sentences (or real shapes) from the
# 2026-07-30 corpus run that exposed a calibration defect. Each is mutation-proved in
# Phase 2 below, so re-introducing the defect turns these red.
#
# (a) "work" as a NOUN must not read as an existence predicate. Real corpus sentence;
#     with `work` in the predicate vocabulary this REJECTed as
#     artifact-subject='harness'+existence-predicate='work' — one of 9 such false rejects.
assert_outcome "corpus-regression(a): noun 'work' must not fire R1" 2 \
  "Every verifier in this harness checks delivered work against a plan."

# (b) A compound ADJECTIVE containing a human noun must not read as a human referent.
#     Hyphen-splitting made "user-facing" match "user", producing a FALSE ACCEPT —
#     the dangerous direction, since it lets a restatement through the gate.
assert_outcome "corpus-regression(b): 'user-facing' is not a human referent" 2 \
  "The user-facing documentation reflects the current architecture."

# --------------------------------------------------------------------------
# Phase 2 — MUTATION proof
# --------------------------------------------------------------------------
# Each mutant disables ONE mechanism, then re-runs the fixture that mechanism is
# supposed to catch. If the fixture still returns the same verdict, the mutant
# SURVIVED and the corresponding Phase-1 assertion is not load-bearing.
echo "== Phase 2: mutation proof ==" >&2

MUTDIR="$(mktemp -d 2>/dev/null || echo "/tmp/ifmut.$$")"
mkdir -p "$MUTDIR"
trap 'rm -rf "$MUTDIR"' EXIT

assert_mutant_dies() {
  # name, sed-expression (the break), fixture text, original-exit, mutant-must-not-equal
  local name="$1" mutation="$2" text="$3" orig_rc="$4"
  local mutant="$MUTDIR/mutant.sh" out rc

  sed "$mutation" "$CHECKER" > "$mutant"

  # A sed pattern that no longer matches produces a byte-identical "mutant", which
  # would then read as a SURVIVING mutant and be reported as a checker defect. That
  # is a false signal about the wrong file — the stale pattern is the bug. Verify the
  # mutation actually applied before drawing any conclusion from its result.
  if cmp -s "$mutant" "$CHECKER"; then
    echo "  FAIL  $name — MUTATION DID NOT APPLY (stale sed pattern; fix the test, not the checker)" >&2
    FAILED=$((FAILED+1))
    return
  fi

  out="$(bash "$mutant" --outcome "$text" 2>&1)"; rc=$?

  if [[ "$rc" == "$orig_rc" ]]; then
    echo "  FAIL  $name — MUTANT SURVIVED (still exit $rc; the assertion is not testing this logic)" >&2
    FAILED=$((FAILED+1))
  else
    echo "  PASS  $name — mutant died (exit $orig_rc -> $rc)" >&2
    PASSED=$((PASSED+1))
  fi
}

# Mutant 1: empty the artifact-noun vocabulary. The operator's counter-example
# relies on "script" being recognised as an artifact noun; without it, R1 cannot fire.
assert_mutant_dies "mutation: gut artifact nouns -> counter-example must stop REJECTing" \
  's|^IF_ARTIFACT_NOUNS=.*|IF_ARTIFACT_NOUNS="zzznotanoun"|' \
  "The watchdog script exists and runs." 1

# Mutant 2: empty the existence-predicate vocabulary. Same fixture, other half of R1.
assert_mutant_dies "mutation: gut existence predicates -> counter-example must stop REJECTing" \
  's|^IF_EXISTENCE_PREDICATES=.*|IF_EXISTENCE_PREDICATES="zzznotaverb"|' \
  "The watchdog script exists and runs." 1

# Mutant 3: neuter the R1 rule itself at its assignment site (force r1 = 0).
assert_mutant_dies "mutation: force R1 off -> counter-example must stop REJECTing" \
  's|      r1 = 1; p_off = pa_off; p_tok = pa_tok|      r1 = 0; p_off = pa_off; p_tok = pa_tok|' \
  "The watchdog script exists and runs." 1

# Mutant 4: gut the human-referent vocabulary. A correct statement can no longer
# prove it names a person, so it must fall out of ACCEPT.
assert_mutant_dies "mutation: gut human referents -> correct statement must stop ACCEPTing" \
  's|^IF_HUMAN_REFERENTS=.*|IF_HUMAN_REFERENTS="zzznobody"|' \
  "After a usage limit resets, my work continues without me touching anything." 0

# Mutant 5: gut the change-verb AND connector vocabularies — a correct statement can
# no longer prove it names a state change.
assert_mutant_dies "mutation: gut change vocabulary -> correct statement must stop ACCEPTing" \
  's|^IF_CHANGE_VERBS=.*|IF_CHANGE_VERBS="zzznochange"|; s|^IF_CHANGE_CONNECTORS=.*|IF_CHANGE_CONNECTORS="zzznoconnector"|' \
  "After a usage limit resets, my work continues without me touching anything." 0

# Mutant 6: gut the delivery-imperative list — a build instruction must stop REJECTing.
assert_mutant_dies "mutation: gut delivery imperatives -> build instruction must stop REJECTing" \
  's|^IF_DELIVERY_IMPERATIVES=.*|IF_DELIVERY_IMPERATIVES="zzznotaverb"|' \
  "Build v1 of the Conversation Tree Management UI." 1

# Mutant 7a: re-introduce the C1 defect — put perception verbs back into the CHANGE
# vocabulary, so "I see ..." again counts as an observable state change and vetoes R1.
# The golden-scenario evasion must go back to ACCEPTing.
assert_mutant_dies "mutation: perception counts as change -> framing-clause evasion falsely ACCEPTs" \
  's|^IF_CHANGE_VERBS="becomes become|IF_CHANGE_VERBS="see sees becomes become|' \
  "I see the watchdog script exists and runs." 1

# Mutant 7: re-introduce corpus defect (a) — put the NOUN "work" back in the predicate
# vocabulary. The corpus sentence must go from UNDECIDABLE back to a false REJECT.
assert_mutant_dies "mutation: restore noun 'work' as predicate -> corpus sentence falsely REJECTs" \
  's|^IF_EXISTENCE_PREDICATES="exists exist existed present runs ran running|IF_EXISTENCE_PREDICATES="exists exist existed present runs ran running work|' \
  "Every verifier in this harness checks delivered work against a plan." 2

# Mutant 8: re-introduce corpus defect (b) — look up human referents in hyphen-split
# word-mode. "user-facing" must go from UNDECIDABLE back to a FALSE ACCEPT.
assert_mutant_dies "mutation: hyphen-split human lookup -> 'user-facing' falsely ACCEPTs" \
  's|h_off = first_hit(sp, humans)|h_off = first_hit(sw, humans)|' \
  "The user-facing documentation reflects the current architecture." 2

# --------------------------------------------------------------------------
echo "" >&2
echo "if-statement-check tests: $PASSED passed, $FAILED failed" >&2
if [[ "$FAILED" -eq 0 ]]; then
  echo "self-test: OK" >&2
  exit 0
fi
exit 1
