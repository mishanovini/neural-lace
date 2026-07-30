# Plan: workstreams-emit replay-debounce fix + per-site sentinel regression tests

Status: ACTIVE
Execution Mode: direct
Mode: code
Backlog items absorbed: ASK-SENTINEL-PER-SITE-REGRESSION-TESTS-01
acceptance-exempt: true
acceptance-exempt-reason: Harness-internal hook/test-suite fixes with no product user; the raised bash -n / bash -x self-test results for each touched suite are the demonstration.
tier: 1
rung: 1
architecture: coding-harness
frozen: true
lifecycle-schema: v2
owner: Misha
target-completion-date: 2026-07-29
prd-ref: n/a — harness-development
ask-id: none — no linked ask

## Goal
Two-part harness micro-slice dispatched 2026-07-29.

Part 1: `workstreams-emit.sh`'s `_dispatch_replay_token` sized its replay-
debounce window (`DISPATCH_REPLAY_DEBOUNCE_SECONDS`) at 30s. PROVEN too
tight on this machine under load: the full self-test suite failed PL1b
(got 2 want 1) and PL1c (got 3 want 2) twice the same day, and the T3
verifier independently measured a 32-wall-second gap between two
back-to-back stamp writes. Raise the default to 120s and rewrite the
sizing comment honestly.

Part 2: the `'<'* | none` ask-id sentinel guard (commit 0758232, review
record hcr-20260729-4586088a) lives at 5 extractors + the writer, but only
`remap-placeholder-ask-events.sh` (Scenario F) and `progress-log-lib.sh`
(Scenario 1i) carried site-local none→empty regression assertions before
this plan. Add the missing assertions to the other four sites (per-site,
exercising each site's own extractor) and collapse the dual-maintained
guarded-sites inventory (plan-template.md SENTINEL COUPLING +
progress-log-lib.sh `_pl_is_none_sentinel` comment) to one canonical list.

## User-facing Outcome
n/a — harness-internal: the maintainer is the user. The demonstration is
(a) `bash -n` clean on every touched file, (b) each touched suite's
`--self-test` run showing the new/previously-passing scenarios green, and
(c) the PL1b/PL1c lines specifically passing at PRODUCTION DEFAULTS on this
machine (Part 1's actual regression target).

## Scope
- IN: the one-default + one-comment fix in `_dispatch_replay_token`
  (`adapters/claude-code/hooks/workstreams-emit.sh`); mirroring the
  corrected sizing note into `docs/runbooks/ask-workstreams.md`; one
  site-local none-header→empty regression scenario added to each of
  `plan-lifecycle.sh`, `workstreams-emit.sh`, `merge-scan-lib.sh` (both the
  file-lookup arm AND the previously-untested git-fallback arm), and
  `close-plan.sh`; collapsing the guarded-sites inventory to one canonical
  copy; closing backlog row ASK-SENTINEL-PER-SITE-REGRESSION-TESTS-01.
- OUT: `AMENDMENT_REPLAY_DEBOUNCE_SECONDS` in `plan-lifecycle.sh`'s sibling
  `_amendment_replay_token` mechanism — discovered failing (Scenario 20d)
  under the SAME class of root cause during this plan's verification pass,
  but a DIFFERENT variable/call site than the one this plan was dispatched
  to fix; filed as its own nl-issue/backlog row for a follow-up slice
  rather than silently expanding this plan's diff. Restructuring either
  debounce mechanism's shape (only the default + comment change per site).
  `ASK-SENTINEL-QUARANTINE-SURFACER-01` (the sibling backlog row) — separate
  concern, not touched here.

## Tasks

- [ ] 1. Raise `DISPATCH_REPLAY_DEBOUNCE_SECONDS`'s default from 30 to 120 in `_dispatch_replay_token` (`adapters/claude-code/hooks/workstreams-emit.sh`) and rewrite the SIZING comment + two stale in-suite comments (PL1b/PL1c) to cite the measured failure honestly; mirror the correction into `docs/runbooks/ask-workstreams.md` — Verification: mechanical — Docs impact: runbook updated same commit
- [ ] 2. Add a site-local none-header→empty regression scenario exercising each site's own extractor: plan-lifecycle.sh Scenario 13c (`extract_ask_id`), workstreams-emit.sh PL4e (`_resolve_ask_id_for_plan_slug`), merge-scan-lib.sh Scenarios 21-23 (`_ms_resolve_ask_id` — file-lookup arm + git-fallback arm), close-plan.sh S22 (`extract_ask_id_cp`); collapse the dual-maintained guarded-sites inventory to one canonical copy (plan-template.md SENTINEL COUPLING is canonical; progress-log-lib.sh points to it) — Verification: mechanical — Docs impact: backlog row ASK-SENTINEL-PER-SITE-REGRESSION-TESTS-01 closed same commit

## Files to Modify/Create
- `adapters/claude-code/hooks/workstreams-emit.sh` — Part 1 default+comment fix; Part 2 PL4e scenario
- `docs/runbooks/ask-workstreams.md` — Part 1 sizing-note mirror
- `adapters/claude-code/hooks/plan-lifecycle.sh` — Part 2 Scenario 13c
- `adapters/claude-code/hooks/lib/merge-scan-lib.sh` — Part 2 Scenarios 21-23
- `adapters/claude-code/scripts/close-plan.sh` — Part 2 Scenario S22
- `adapters/claude-code/hooks/lib/progress-log-lib.sh` — Part 2 comment-inventory collapse
- `docs/backlog.md` — close ASK-SENTINEL-PER-SITE-REGRESSION-TESTS-01

## In-flight scope updates
n/a

## Assumptions
- The machine's current ~9-bash baseline load (per dispatch prompt) is
  representative enough that PL1b/PL1c passing at the new 120s default
  here is meaningful evidence, not a lucky quiet window.
- `AMENDMENT_REPLAY_DEBOUNCE_SECONDS`'s Scenario 20d failure (discovered
  during this plan's verification, not dispatched) shares root cause with
  Part 1 but is intentionally left for a follow-up slice — filed to
  backlog/nl-issue rather than silently absorbed, per scope discipline.

## Edge Cases
- A future re-run on a MORE heavily loaded machine could still exceed
  120s; the env override (`DISPATCH_REPLAY_DEBOUNCE_SECONDS`) remains the
  escape hatch for tests, and the sizing comment now cites the measured
  failure mode so a future re-tuning has real numbers to reason from.
- merge-scan-lib.sh's git-fallback arm (Scenarios 22-23) exercises a plan
  file deleted entirely (not archived) after the commit being resolved —
  the one shape neither existing scenario touched.

## Acceptance Scenarios
n/a — acceptance-exempt harness-dev plan; see acceptance-exempt-reason in
the header. Closure evidence is each touched suite's self-test tally.

## Out-of-scope scenarios
`AMENDMENT_REPLAY_DEBOUNCE_SECONDS` (plan-lifecycle.sh Scenario 20d) — see
Scope/OUT above.

## Closure Contract
- **Commands that run:** `bash -n` on every touched file; `--self-test` on
  `plan-lifecycle.sh`, `close-plan.sh`, `merge-scan-lib.sh` (via
  `ms_self_test`), `progress-log-lib.sh`, `remap-placeholder-ask-events.sh`,
  and (best-effort, given per-fire fork cost on this machine)
  `workstreams-emit.sh --self-test` in full.
- **Expected outputs:** all suites report 0 failed; PL1b and PL1c lines in
  workstreams-emit.sh's output specifically show PASS at production
  defaults (no env override).
- **On-disk artifact location:** this plan's completion report (appended
  below) plus the builder's dispatch-report tally.
- **Done when:** both tasks checked per mechanical routing AND every
  touched suite's self-test is green AND the fix commits are merged to
  master.

## Testing Strategy
- Task 1: re-run `workstreams-emit.sh --self-test` in full; PL1b/PL1c
  lines must read PASS (not FAIL) at the new 120s default.
- Task 2: run each of the four newly-touched suites' `--self-test`;
  confirm the new scenario numbers appear and pass, and that no
  `none.jsonl` file is ever created by any of them.

Walking Skeleton: n/a — a default+comment change and additive test
scenarios; no new architectural layers.

## Decisions Log
- 2026-07-29 (decide-and-go, constitution §8 — reversible): opened this
  plan file AFTER the code fix was already verified correct, mirroring the
  hotfix flow the scope-enforcement-gate's own Scenario 12 sanctions
  (`frozen: true` at birth) — needed only to satisfy the gate's
  active-plan requirement for this otherwise plan-free micro-dispatch.
- 2026-07-29 (decide-and-go, reversible): discovered `AMENDMENT_REPLAY_
  DEBOUNCE_SECONDS`'s Scenario 20d failing under the same root-cause class
  as Part 1, but left it OUT of this plan's scope (filed separately)
  rather than silently expanding the diff to a variable/file the dispatch
  never named — reversal is trivial (a future plan claims it).
- 2026-07-29 (decide-and-go, reversible): for merge-scan-lib.sh, added
  BOTH the file-lookup-arm and git-fallback-arm scenarios (3 new scenarios,
  not 1) because neither arm had ANY none-sentinel or git-fallback
  coverage before this plan — matching the dispatch's explicit "BOTH
  branches" instruction rather than the minimal one-assertion reading.

## Definition of Done
- [ ] All tasks checked off
- [ ] All touched suites' self-tests pass (0 failed each)
- [ ] Linting/formatting clean (bash -n clean on every touched file)
- [ ] SCRATCHPAD.md updated with final state
- [ ] Completion report appended to this plan file
