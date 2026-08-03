# Plan: code-trace methodology — adversarially test the "biased reader" thesis against a 14-defect corpus
Status: ACTIVE
Execution Mode: direct
Mode: code
Backlog items absorbed: none
acceptance-exempt: true
acceptance-exempt-reason: Design-only deliverable. This plan ships ONE markdown document under `docs/designs/` plus one `docs/backlog.md` entry; no executable code, no hook, no gate, no UI. There is no runtime surface to accept. The demonstration required by constitution §4's harness-work carve-out is that every claim in the document is backed by a trace that was ACTUALLY RUN (bash traces on both `/bin/bash` 3.2.57 and `/opt/homebrew/bin/bash` 5.3.15 by absolute path, sequentially; node traces on `/opt/homebrew/bin/node`), with the command output pasted into the document — which is exactly what the Testing Strategy below verifies.
tier: 1
rung: 0
architecture: coding-harness
frozen: true
lifecycle-schema: v2
loe-class: design-only
owner: Misha
target-completion-date: 2026-07-30
prd-ref: n/a — harness-development
ask-id: none — no linked ask (operator directive, quoted verbatim in Goal below)

## Intended Functionality

**Outcome (operator's terms):** The maintainer can answer "would a static trace
have caught this defect?" for any of the 14 shipped 2026-07-30/31 defects by
reading one table row, instead of re-deriving it, and gets a per-defect
YES/PARTIAL/NO verdict with the exact command that finds it.

**Observation:** Open `docs/designs/code-trace-methodology.md` and count the
rows in §a. There are 14, each with a verdict, a `file:line`, and — for the
rows marked EXECUTED — pasted output from a command that was actually run.
§b states a single number ("12 of 14") that a reader can check by tallying the
verdict column themselves.

**Deterministic pass/fail:** PASS iff (1) §a contains exactly 14 defect rows;
(2) every row carries a verdict from the closed set {YES, PARTIAL, NO}; (3)
every row marked EXECUTED contains pasted command output, not a paraphrase;
(4) the count asserted in §b equals the count of YES verdicts in §a; (5) each
of §c's protocol moves names at least one corpus defect number it catches; (6)
each residual class in §d carries exactly one resolving command. Any of the six
false ⟹ FAIL.

**Explicitly NOT included:** This does not fix any of the 14 defects, does not
build a gate or agent from the protocol, does not edit any doctrine file, and
does not claim the protocol is invoked by anything — nothing invokes it, which
the deliverable states about itself.

**Human dependencies:**
- A human (or dispatched agent) must choose to apply the protocol during a review; nothing fires it automatically — INTENDED for this plan's scope, and named in §c/Systems Engineering Analysis as the residual. Converting it into a mechanism is a separate, operator-owned decision.
- Reading or checking the deliverable requires no human action beyond opening the file; all six pass/fail conditions above are mechanical — INTENDED

## Goal
Operator, verbatim (2026-07-31): "This is not a failure of reading code; it is
a failure of a biased reader. Those are 2 different things, and that is the
whole point of using adversarial agents. A diligent review agent should be
perfectly capable of catching these problems by tracing the code and
determining exactly what would happen in every circumstance… trace the code all
the way through to determine exactly what it would do in every condition and
failure case. It is only in the cases where there is code that is not ours
where we cannot determine everything we need."

TEST THAT THESIS ADVERSARIALLY — not agree with it. For each of 14 real
defects shipped 2026-07-30/31, reach the pre-fix state via git history and
determine BY ACTUALLY DOING IT whether a pure static trace with NO runtime
observation would have found it.

## User-facing Outcome
The maintainer (this harness's user, per constitution §4) gains an executable
operating procedure for failure-mode review: nine named mechanical moves, each
a command plus a question, derived from the corpus rather than invented — and
a calibrated, measured answer to "how much of this could reading have caught",
so future review dispatches stop substituting a live probe for a trace.

## Scope
IN: one design document at `docs/designs/code-trace-methodology.md`; one new
`docs/backlog.md` entry for a defect the methodology surfaced while being
built. OUT: fixing any of the 14 defects (13 are already fixed; the one live
residual is filed to backlog, not fixed here — see Out-of-scope scenarios);
building any gate or agent from the protocol; editing any doctrine file.

## Tasks

- [ ] T1 — `docs/designs/code-trace-methodology.md` §a: the per-defect table. Verification: contract

  **Prove it works:** 1. Open `docs/designs/code-trace-methodology.md`. 2. Count the rows under `## (a) Per-defect table` — there are 14. 3. Each carries a `file:line`, a pre-fix commit where one exists in git, and a verdict from {YES, PARTIAL, NO}. 4. Each row marked EXECUTED pastes real command output.

  **Wire checks:** operator thesis → `docs/designs/code-trace-methodology.md` (`The thesis under test`) → `docs/designs/code-trace-methodology.md` (`Per-defect table`).

  **Integration points:** `adapters/claude-code/doctrine/deterministic-process.md` — rows 4 and 9 must cite Rule 3's existing golden cases rather than invent vocabulary: `grep -n "limit-resume watchdog's marker" adapters/claude-code/doctrine/deterministic-process.md`.

- [ ] T2 — `docs/designs/code-trace-methodology.md` §b: the measured tally. Verification: contract

  **Prove it works:** 1. Read `## (b) The honest tally`. 2. The headline count equals the number of YES verdicts in §a. 3. The section states plainly where the thesis is stronger than credited AND where two defects genuinely resist a pure trace — neither softened.

  **Wire checks:** `docs/designs/code-trace-methodology.md` (`Per-defect table`) → `docs/designs/code-trace-methodology.md` (`The honest tally`).

  **Integration points:** none — this section is derived arithmetic over §a, with no external consumer.

- [ ] T3 — `docs/designs/code-trace-methodology.md` §c: the 9-move trace protocol. Verification: contract

  **Prove it works:** 1. Read `## (c) The generalized trace protocol`. 2. Each move carries a runnable command and names the corpus defect numbers it catches. 3. Run Move 1's command (`git grep -n "file://" -- neural-lace/workstreams-ui/web`) and confirm it reproduces the row-6 finding.

  **Wire checks:** `docs/designs/code-trace-methodology.md` (`Per-defect table`) → `docs/designs/code-trace-methodology.md` (`The generalized trace protocol`).

  **Integration points:** `adapters/claude-code/scripts/config-control-producer-scan.sh` — Move 1 must cite the existing mechanization rather than propose a new one: `ls adapters/claude-code/scripts/config-control-producer-scan.sh`.

- [ ] T4 — `docs/designs/code-trace-methodology.md` §d + the surfaced-defect backlog entry. Verification: contract

  **Prove it works:** 1. Read `## (d) The irreducible residual`. 2. Each residual class names exactly one resolving command. 3. `grep -c "COCKPIT-DEAD-FILE-HREF-RESIDUAL-01" docs/backlog.md` returns 1.

  **Wire checks:** `docs/designs/code-trace-methodology.md` (`The irreducible residual`) → `docs/backlog.md` (`COCKPIT-DEAD-FILE-HREF-RESIDUAL-01`).

  **Integration points:** `docs/backlog.md` — the entry must be greppable and must carry the executed evidence: `grep -c "COCKPIT-DEAD-FILE-HREF-RESIDUAL-01" docs/backlog.md`.

## Files to Modify/Create
- `docs/designs/code-trace-methodology.md` — CREATE. The deliverable: per-defect table, measured tally, 9-move protocol, irreducible residual.
- `docs/backlog.md` — MODIFY. Two entries: `COCKPIT-DEAD-FILE-HREF-RESIDUAL-01` (the live defect Move 1 surfaced) and `SCOPE-GATE-HEADER-CLAIMS-INTERSECTION-IMPLEMENTS-UNION-01` (Move 9 applied to the gate that blocked this commit).
- `docs/plans/code-trace-methodology-2026-07-30.md` — CREATE. This plan (opened per scope-enforcement-gate option 2 — see Decisions Log D1).

## In-flight scope updates
- 2026-07-30: `docs/plans/code-trace-methodology-2026-07-30.md` — this plan file itself, staged alongside the work per the gate's option-2 instruction.

## Assumptions
- The 14 corpus defects are reachable at their pre-fix state via this repo's git history. VERIFIED for 12; defects 4 and 5 concern machine-local artifacts (`~/.claude/state/limit-resume/resume.sh`, a LaunchAgent plist) never version-controlled — the document says so explicitly rather than pretending otherwise.
- `/bin/bash` 3.2.57 is the portability floor and both interpreters are present at the absolute paths given.
- Extracting a function body from a historical blob and executing it in isolation is a faithful test of that function. Holds where the function is pure or depends only on injected collaborators; every extraction in the document names what it stubbed.

## Edge Cases
- A defect whose artifact is not in the repo (4, 5) — handled by naming the scope precondition rather than claiming a repo-only trace would find it.
- A defect whose cause is third-party behaviour (5, 7) — handled by splitting "symptom, statically provable" from "cause, needs one external fact", and giving the command for the latter.
- A trace that would have found the defect *only because a previous fix recorded the fact* (6) — handled by stating that dependency explicitly, since it is the document's most load-bearing finding.
- The corpus contains a defect that is still LIVE (6's siblings). Handled by filing to backlog, not by silently fixing it inside a design task.

## Acceptance Scenarios
1. **A reviewer applies the protocol cold.** Given only `docs/designs/code-trace-methodology.md` and this repo, a reviewer runs Move 1's command (`git grep -n "file://" -- neural-lace/workstreams-ui/web`) and reaches the same conclusion the document reports: the fact is recorded in `roadmap.js`, and `asks.js`/`backlog.js` still emit dead hrefs.
2. **The tally is reproducible.** A reader re-runs the §a row-8 enumeration and gets 28 IN / 54 OUT, and re-runs the row-14 measurement and gets 40 blocking / 38 grandfathered / 2 in scope.

## Out-of-scope scenarios
- Fixing `asks.js` / `backlog.js`'s dead `file://` hrefs. Deliberately deferred: this is a design task, and a cockpit code fix inside it would be exactly the scope drift the harness's own anti-patterns forbid. Filed as `COCKPIT-DEAD-FILE-HREF-RESIDUAL-01`.
- Correcting `deterministic-process.md`'s now-stale Enforcement header. Already owned by the open task "Shrink grandfather list + restore deterministic-process.md header honestly".
- Building a gate or agent from the 9-move protocol. The protocol is the input to that decision, not the decision.

## Closure Contract
This plan closes when `docs/designs/code-trace-methodology.md` exists on the
branch with all four required sections (a/b/c/d) populated from executed
traces, and `docs/backlog.md` carries the surfaced-defect entry. No runtime
deployment, no doctor check, no suite is gated on it.

## Testing Strategy
Design-only; the "test" is that every claim is backed by a command that was
run and whose output is pasted in. Verification performed:
- `node web/cockpit.selftest.js` → **513 passed, 0 failed**
- `node server/roadmap-routes.selftest.js` → **120 passed, 0 failed**
- `review-record-push-gate.sh --self-test` → **23 passed, 0 failed** on `/bin/bash` 3.2.57 AND **23 passed, 0 failed** on `/opt/homebrew/bin/bash` 5.3.15
- Every bash trace harness run on both interpreters by absolute path, sequentially; outputs pasted into the document.
No executable code is changed by this plan, so no suite can regress from it.

## Walking Skeleton
Not applicable in the usual sense (single-document deliverable, no layers).
The equivalent thin slice was: trace ONE defect (defect 1) end-to-end —
git-show the pre-fix blob, extract the helper, execute it, confirm the no-op —
before writing any of the other 13 rows. That proved the extract-and-execute
method worked before it was invested in 13 more times.

## Decisions Log
- **D1 (2026-07-30) — Open a new plan rather than attach to an existing one.** `scope-enforcement-gate` blocked the commit and offered three options. Option 1 (append to an active plan's `## In-flight scope updates`) was available and would have been faster; `docs/plans/cockpit-review-surface-and-verification-gaps.md` is a close thematic match — same operator question, and it already absorbs `SHAPE-ONLY-ASSERTIONS-FALSE-GREEN-01`. **Rejected as scope-laundering:** only ~5 of the 14 corpus defects are cockpit; the rest span launchd, limit-resume, `workstreams-emit.sh`, the push/commit gates, and manifest doctrine. Filing this under a cockpit-scoped plan would misrepresent both. Option 2 is what the gate itself prescribes for "genuinely separate work". Reversible in one revert.
- **D2 (2026-07-30) — No gate bypass used anywhere.** No `REVIEW_RECORD_GATE_OVERRIDE`, no `--no-verify`, no disable env. `docs/designs/**` is not in `rrg_in_surface` (verified by executing the predicate), so no review record is owed for this path.
- **D3 (2026-07-30) — Report the measured number, not the flattering one.** The tally (12 of 14) is what the traces produced. Where the thesis is stronger than the orchestrator credited, §b says so; where two defects genuinely resist a pure trace, §b and §d say that too, without softening.

## Pre-Submission Audit
- Every `file:line` in the deliverable was re-checked against the actual blob; two off-by-one citations in the defect-1 row and one miscount ("eight guards" → eleven) were corrected before commit.
- No claim of traceability is asserted without a demonstrated trace; the two PARTIAL rows are labelled PARTIAL, not YES.
- The one still-live defect surfaced during the work was filed to `docs/backlog.md` in the same response that surfaced it (constitution §5), not deferred to the report.

## Definition of Done
`docs/designs/code-trace-methodology.md` and the `docs/backlog.md` entry are
committed on this branch with a SHA. Per constitution §1 this plan is not
"shipped" until merged to master; the builder's obligation ends at the commit
plus an honest report of what is and is not closed.

## Systems Engineering Analysis
The corpus exhibits one dominant failure mode: a cheap mechanical check
(usually a single `git grep`) existed and was not run, and a live probe was
substituted for it *after* the operator reported the symptom. The systemic
risk this creates is asymmetric — a live probe finds the reported instance and
leaves siblings, which is precisely how defect 6's residual survived two
separate cures. The protocol in §c is therefore ordered by yield rather than
by elegance, and Move 1 carries an explicit non-negotiable corollary: when you
fix one instance, re-run the grep and dispose of every hit. The residual risk
this plan does NOT close is that the protocol is a document, not a mechanism —
nothing invokes it, which is defect 9's and Rule 3's own failure class. That
is named here deliberately rather than hidden: converting the protocol into a
failure-mode agent's operating procedure, or a gate, is a separate decision
that needs the operator, and it is stated as such in the deliverable's own
framing rather than claimed as delivered.
