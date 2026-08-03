# Plan-Fidelity Review (bootstrap): gated-pipeline-master-2026-08

**Reviewer:** harness-reviewer acting as plan-fidelity-reviewer (role: plan-fidelity, bootstrap — per design §8.1; model: fable, dispatched by session 4a470c8c)
**Reviewed:** docs/plans/gated-pipeline-master-2026-08.md @ e9d0cf9d against docs/designs/gated-pipeline-master-2026-08-03.md (r3) @ e9d0cf9d
**One job:** is this plan a faithful, complete, buildable projection of the reviewed design?
**Reviewed at:** 2026-08-03

## Verdict: REFORMULATE

Scoped tightly: the plan's task content is a complete, substantively faithful projection of r3 — every MUST REQ maps to a task whose text implements it, the bootstrap ordering is carried, no task contradicts a design decision, and the hard stops are honored. One Major (the plan anchors and cites the superseded r2 revision while its tasks implement r3 — the exact anchor-drift class this pipeline polices) plus four Minors. The Major's fix is self-prescribed by the plan's own Assumptions clause; a scoped confirmation of the named edits suffices, no full re-round.

## MUST-REQ coverage (verified substantively, not string-matched)

| REQ | Task | Substance check |
|---|---|---|
| A0 | T2 | ✓ merge-commit reconcile, both mirrors, 0/0 verify, stash-protect |
| A1 | T3 | ✓ full REQ text carried incl. identity-verified kill + log-and-skip, S11 mask deletion, ≥2-real-ticks; prove-it step 3 exercises the bogus-pid case live |
| A2 | T4 | ✓ single-writer form, exit 3 + SKIPPED, both env flags, fingerprint widening, single-writer self-test, grep proof; adds the exit-3 consumer sweep the REQ implies |
| A3 | T5 | ✓ verbatim incl. end-to-end `gc_escape_used` → pane row; cites the 4 live call sites |
| A4 | T6 | ✓ entries + zero-substrate WARN with dates-in-data + `--gen-index` |
| A5 | T7a–e | ✓ decomposed per-target; HR-F3 both branches, F10 renames, F11 canonical HALT, INV-F10 |
| A6 | T9 | ✓ task-verifier first, then SUPERSEDED |
| A8 | T8a–e | ✓ baseline captured, per-RED disposition table, retire-rationale rows, ≤9-RED re-measure, done-bar rule carried |
| B1+B4 | T11 | ✓ canonical JSON + generator + ONE parser + seeding + ADR lint + same-commit derive-cache sweep (see F-2 on the manifest-entry leg) |
| B2/B3 | T12/T13 | ✓ incl. P-32 golden-case fixture and anti-rubber-stamp step |
| B5+B7 | T14 | ✓ Checks 20–22 incl. anchor-at-HEAD; surface-trigger fire-rate measured BEFORE flip |
| B6 | T1 | ✓ all EIGHT r3 fixtures enumerated verbatim; walking skeleton proves lib→gate end-to-end |
| B8 | T17 | ✓ three demo variants verbatim + grandfather WARN test + non-build pass test |
| B9 | T18 | ✓ class config, postures, exemption, same-push honoring tested |
| B10 | T19 | ✓ narrowed pattern + archive exclusion + 5 verbatim negative fixtures + golden executed on the brief |
| B11 | T20 | ✓ merged single-emission walk with the both-match raw-stdout assertion (the C-1 load-bearing test) |
| B13 | T16 | ✓ after T13/14/15, record committed, chain entry appended, gates T17 |
| B14 | T15 | ✓ completion-side, artifact_ref, ledger-landing date, quirk fix, shared-fixture round-trip with T1 |
| C2/C3/C4/C6 | T21/T22/T22/T24 | ✓ T21 after T17 (grandfather retirement), T24's date written by T8's completion |

SHOULDs (A7→T10, B12→T20, C5→T23) also covered. Bootstrap ordering **T15 → T16 → T17** carried in task text and dependency notes. §2 hard stops: no WSL, no hardware, no force-push (merge-commit reconcile), triage-before-Stage-2 honored via T8 + T24.

## Findings

```
F-1  Severity: Major   Confidence: PROVEN (plan lines 20, 30, 32-33, 69, 282, 413-416)
Defect: The plan anchors and cites the SUPERSEDED r2 revision while its tasks implement r3:
header `design-ref: …@r2`, chain `design-ref: …@a4cd03f5` (r2's commit — and a commit sha where
the r3 format specifies a blob sha), Goal "Implement …(r2…)", T16 "against design r2", and the
Assumption "design r2 survives both delta re-reviews without structural change" — falsified by
r3's own existence. Under the three-way anchor rule this plan builds in T1, its own chain fails
rule 2 the moment the parser exists. The design-reviews entries also carry non-PASS-equivalent
verdicts ("REFORMULATE→(delta pending)") now that both deltas are discharged.
Required fix (the plan's own Assumptions clause mandates this BEFORE affected tasks dispatch):
re-anchor design-ref to r3 (blob sha of the design), sweep r2→r3 in Goal/T16/Assumptions, and
update the design-reviews entries to the delta-final verdicts citing the delta records.
```

```
F-2  Severity: Minor   Confidence: PROVEN (Tasks preamble; REQ-B1/B6/B8/B9/B14 "same-commit" lines)
Defect: The design requires manifest entries "same-commit"; the plan's builder-locked model
defers them to orchestrator integration "at merge." Precedented and workable, but it is a
deviation from the REQ letter and the HR-F9 class lives exactly here.
Required fix: name the deviation in the plan and bind it — manifest deltas land in the SAME
merge train as their mechanism, verified before any push (one sentence in the Tasks preamble).
```

```
F-3  Severity: Minor   Confidence: PROVEN (T10 text; master handoff §0 hard stop "fixed AND re-reviewed")
Defect: The hard stop requires HR-F1/F2 re-REVIEWED before registration; T10 sequences only the
fixes. The existing review-record push gate forces harness-surface records at push, which
supplies the re-review leg mechanically — but T10's operator ask could surface before those
records exist, inviting a YES that violates the hard stop.
Required fix: T10's DEC-4 ask block cites the T3/T4 review-record SHAs as a precondition of
surfacing it (one dependency line).
```

```
F-4  Severity: Minor   Confidence: PROVEN (T17 grandfather-list generation "from extant plan slugs")
Defect: THIS plan's slug will be extant at install, so the pipeline's own plan rides the
grandfather WARN path instead of its earned valid chain (T16) — harmless but self-undermining,
and it weakens the live demo's honesty.
Required fix: gate validates the chain FIRST and applies grandfather only when no chain parses
(or exclude this plan's slug from the generated list); one line in T17.
```

```
F-5  Severity: Minor   Confidence: HYPOTHESIZED (refuted if the walk is pure-bash; jq spawn ≈174 ms on this platform, P-01)
Defect: The Behavioral Contract's "< 50 ms, no new spawns" for the JIT register walk is asserted
but unmeasured — one jq invocation alone would breach it.
Required fix: T20's prove-it gains the timing measurement (and the lib avoids per-event jq, e.g.
pre-parsed cache or bash parse), with the number in the evidence file.
```

## Weakest mapping (anti-rubber-stamp, named even though coverage is complete)

**REQ-C3 → T22.** The honest scorecard is the D-07 accountability surface for the whole program, yet T22 is a two-line contract task with no prove-it block and no stated method for computing "net-artifact delta" (counted against what baseline, by what enumeration?). It will pass task-verifier on a rendered pane whose numbers nobody can independently recompute. Recommend T22 name the counting method (e.g., `git diff --stat` file census between the two tagged SHAs + the §7 ledger rows) and assert one recomputable number in evidence. Runner-up: REQ-B1's manifest-entry leg (F-2).

---

**Amendment confirmation (a4176686):** All findings F-1…F-5 and the weakest-mapping fix (T22 counting method) verified resolved on disk by the reviewer — including an independent `git hash-object` check that the plan's design-ref anchors the true r3 blob (`53fd8f27…`). The plan is a faithful, complete, buildable projection of design r3. Bootstrap plan-fidelity verdict: **PASS**. This bootstrap record is superseded for future revisions by the `plan-fidelity-reviewer` agent once Task 13 lands (T16 re-reviews formally).

## Verdict: PASS
