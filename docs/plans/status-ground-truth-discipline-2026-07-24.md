# Plan — Status-Grounding Discipline (report from ground truth, not stale artifacts)

Status: ACTIVE
Mode: docs
Owner: interactive session (2026-07-24)
Backlog items absorbed: none
acceptance-exempt: yes (harness-internal knowledge doc + a review-gated doctrine/claim-reviewer follow-up; demonstrated by the lesson on master and, for the follow-up, by `doctrine-jit.sh --self-test` once built)

## Why
A session reported two materially-wrong statuses to the operator (a feature claimed missing that
already existed; plans claimed "waiting on design" that were design-complete), each of which would
have caused large wasted work. Root cause: status reported from stale intermediate artifacts
(prior-turn claims, SCRATCHPAD, audit labels, memory) instead of the authoritative source at report
time. This plan lands the durable lesson and tracks the review-gated mechanism to enforce it.

## Files to Modify/Create
- `docs/plans/status-ground-truth-discipline-2026-07-24.md` — this plan
- `docs/lessons/2026-07-24-report-status-from-ground-truth-not-stale-artifacts.md` — the lesson

## Tasks
- [x] Author the lesson (ground-truth-before-status rule + absence-claim-needs-cited-empty-search +
  plan-status-≠-work-status + the source-of-truth table). — done, this commit.
- [ ] FOLLOW-UP (review-gated, separate PR): a status-grounding doctrine JIT-injected on
  operator-facing-status surfaces, and a narrowed `claim-reviewer` trigger on uncited
  absence/"waiting-on" claims; route through `harness-reviewer`; file via `nl-issue.sh`.

## Notes
Companion to the same-session Fable model-facts lesson. This plan touches no always-loaded or JIT
surface; the enforcement follow-up is deliberately separate and reviewed.
