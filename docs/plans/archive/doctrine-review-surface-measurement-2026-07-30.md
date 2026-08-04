# Plan: Measure the doctrine review-record surface question (operator decision 069)
Status: COMPLETED
Execution Mode: direct
Mode: design
Backlog items absorbed: none
acceptance-exempt: true
acceptance-exempt-reason: Measurement-and-decision work with no product user; the operator is the user (constitution §4). The demonstration is that every number in `docs/decisions/069-doctrine-review-record-surface.md` re-executes at HEAD on BOTH `/bin/bash` 3.2.57 and `/opt/homebrew/bin/bash` 5.3.15 and agrees, and that the operator can answer the decision cold from `NEEDS-YOU.md` entry `NY-1785468489-b4eb`. No mechanism was built, so there is nothing to self-test.
tier: 1
rung: 1
architecture: coding-harness
frozen: true
lifecycle-schema: v2
owner: Misha
target-completion-date: 2026-07-30
prd-ref: n/a — harness-development
ask-id: none — no linked ask

## Goal

Give the operator the real numbers behind one deferred call: should
`adapters/claude-code/doctrine/` (89 tracked files) join the review-record
surface? That arm was deliberately deferred as the only genuinely large one, and
the operator holds the decision. The deliverable is a measured decision block —
**not** a surface change. Landing any change to `rrg_in_surface` was explicitly
out of scope.

This plan exists because `scope-enforcement-gate.sh` correctly blocked the commit:
20 plans are ACTIVE on this branch and this work belongs to none of them. Per the
gate's own option 2 ("genuinely separate work gets its own plan") and the precedent
set by `docs/plans/archive/anti-vaporware-config-controls-generalization.md`, it
gets a single-task plan rather than being wedged into an unrelated one. The work
was complete before the plan was written; the plan is the scope declaration, and
this note records that honestly rather than implying a plan-first sequence.

## User-facing Outcome

The operator can answer "gate doctrine, or not?" from a single block with zero
session context: what the choice is, the measured cost of each option in
commits-per-week of added friction, the measured harm of not doing it, and a
recommendation with its reason. Delivered as
`docs/decisions/069-doctrine-review-record-surface.md`, indexed in
`docs/DECISIONS.md`, and surfaced as `NEEDS-YOU.md` entry `NY-1785468489-b4eb`
(passed all three cold-reader lint checks — `lint_warnings: []`).

## Files to Modify/Create

- `docs/decisions/069-doctrine-review-record-surface.md` — CREATE: the measured decision block (4 options, costs, harm, recommendation, refutation criteria)
- `docs/DECISIONS.md` — MODIFY: add the `069` index row (record↔index atomicity, enforced by `decisions-index-gate.sh`)
- `docs/backlog.md` — MODIFY: persist the 4 findings surfaced by the measurement
- `docs/plans/doctrine-review-surface-measurement-2026-07-30.md` — CREATE: this plan (scope declaration per the gate's option 2)

Explicitly NOT modified: anything under `adapters/claude-code/`. No surface change.

## Tasks

- [ ] 1. Measure the doctrine review-surface question over the real git history and
  write the operator decision block. `Verification: contract`
  **Prove it works:** the operator opens `NEEDS-YOU.md`, finds `NY-1785468489-b4eb`,
  and can answer `A`/`B`/`C`/`D` without opening another file; each option states
  what happens if chosen and what it costs per week.
  **Wire checks:** `docs/decisions/069-doctrine-review-record-surface.md` →
  indexed as row `069` in `docs/DECISIONS.md` → surfaced as `NY-1785468489-b4eb`
  in `~/.claude/state/needs-you/ledger.json` with `lint_warnings: []`.
  **Integration points:** `jq -r '.items[] | select(.id=="NY-1785468489-b4eb")'
  ~/.claude/state/needs-you/ledger.json` returns the entry with an empty
  `lint_warnings` array; `grep -n '^| 069' docs/DECISIONS.md` returns the row;
  `git status --short` shows no file under `adapters/claude-code/`.

## Assumptions

- The 90-day window (`--since=2026-05-01`, `--no-merges`, measured to `3caaeff`)
  is representative of doctrine churn. It spans the Wave C doctrine build-out, so
  if anything it OVER-states steady-state friction — the compact/`-full` split
  itself happened inside this window and generated much of the cap-trim traffic.
- `rrg_in_surface` sourced from the real lib is the authority on what is
  in-surface. Every surface count executes it rather than reimplementing its globs.
- Commit counts are the right friction unit for "new review round-trips". The
  per-file-blob figure (188 distinct `(path, blob_sha)` pairs) is reported as a
  supporting number, not as the headline, because one review run covers many files.

## Edge Cases

- **Records are keyed per FILE, not per commit.** A commit touching doctrine plus
  an in-surface `.sh` gets a record covering only the `.sh` — the doctrine change
  rides along unreviewed. This is why the added-friction count is 15 (commits with
  NO in-surface file) rather than 9 (commits touching ONLY doctrine); the naive
  "only doctrine" metric undercounts by a third.
- **A dead probe reports zero hits and looks like a clean result.** The first JIT
  probe returned "0 injections" because its payload omitted `tool_name`, which the
  hook requires. Every probe therefore carries a control assertion that fails loudly
  if the harness is dead; the reported 0 is only trustworthy because the control passed.
- **Committer dates are rewritten by rebase.** The divergence window for incident 1
  was computed from AUTHOR dates; committer dates all collapsed to the rebase time.

## Testing Strategy

No mechanism was built, so there is no `--self-test`. The verification is
reproducibility: every quoted figure was produced by a script executed at the
commit being made, on both `/bin/bash` 3.2.57 and `/opt/homebrew/bin/bash` 5.3.15,
sequentially and by absolute path, with both outputs compared. Surface counts
additionally compare the full in-surface FILE LISTS between interpreters (`cmp`),
not just the counts. Behavioural claims execute the real hook against the real
manifest — no regex over source text stands behind any behavioural assertion.

## Decisions Log

- **2026-07-30: report the 311 premise as false rather than working around it.**
  The dispatch stated the surface was extended today to 311 files. Executing
  `rrg_in_surface` at the branch tip yields 283, and the archived plan lists the
  extension under OUT-of-scope verbatim. Recorded as a correction in the decision
  block and as `REVIEW-SURFACE-COUNT-311-IS-FALSE-01`, because a decision costed
  against a phantom baseline is worthless.
- **2026-07-30: measure and REJECT the cheap control rather than recommend it.**
  The dispatch proposed gating only the JIT-delivered compacts. Measured at 23
  files / 0.70 per week — genuinely cheaper — but it misses BOTH proven incidents,
  so it is recommended against with the evidence rather than presented as a
  balanced option (constitution §3: no false framings).
- **2026-07-30: report 15 as the friction number, not the 9 that was asked for.**
  "Commits touching ONLY doctrine" was the requested metric; it undercounts because
  records are per-file. Both numbers are reported, with 15 as the headline and the
  reason stated.
- **2026-07-30: recommend against exempting "mechanical" doctrine commits.** 7 of
  the 15 are cap trims / INDEX regeneration and look exempt-worthy. Inspecting them
  showed they are the commits that rewrite delivered compacts most heavily, so the
  obvious cost-saving carve-out would exempt exactly the wrong ones.

## Completion Report (drain disposition — gated-pipeline-master-2026-08 Task 21, REQ-C2, 2026-08-03)

Found landed-but-unflipped during the REQ-C2 estate drain: this plan's sole deliverable
`docs/decisions/069-doctrine-review-record-surface.md` confirmed on master via `49fba9e7`,
indexed at `docs/DECISIONS.md` row 069. The plan's own scope was "measure and write the
decision block," which is satisfied even though the decision itself remains open pending the
operator. Status flipped ACTIVE -> COMPLETED.
