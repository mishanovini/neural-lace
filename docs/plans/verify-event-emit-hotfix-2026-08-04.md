# Plan: verification-event emission — extend SE4's flip-verdict ledger row

Status: ACTIVE
Execution Mode: direct
Mode: code
frozen: true
lifecycle-schema: v2
tier: 1
rung: 1
architecture: coding-harness
owner: Misha
target-completion-date: 2026-08-04
prd-ref: n/a — harness-development
ask-id: none — no linked ask
acceptance-exempt: true
acceptance-exempt-reason: Harness-internal hook/ledger extension with no product user; the maintainer is the user (constitution §4). The demonstration is (a) plan-edit-validator.sh's --self-test (27/0, mutation-proven on the two new fix points), (b) verify-event-audit.sh's own --self-test (7/7, mutation-proven on three fix points), and (c) a live end-to-end run of the real (unmodified) hook against a real isolated ledger, proving the event lands before the checkbox does.

## Goal
Operator directive (2026-08-04, verbatim): "Wouldn't it be easier to just update the
task verifiers to check off the check boxes in two places (plan file and ledger)?
That way, they are still keeping track of their single source of truth within the
plan file like they normally do, and they additionally are updating the global status
at the same time. It's all deterministic."

Discovery during dispatch: this mechanism already exists — `status-event-ledger` plan
(docs/plans/deferred/status-event-ledger.md) SE4, built 2026-07-30, fires a
`flip-verdict` signal-ledger row inside `plan-edit-validator.sh`'s
`emit_flip_ledger_event`, on every AUTHORIZED checkbox flip. This plan is the
EXTENSION of that mechanism (field-contract addition + a read-only consumer), not a
new mechanism — see Decisions Log for why extending SE4 in place, rather than a
second task-verifier-invoked emitter, is the correct design.

## User-facing Outcome
n/a — harness-internal: the maintainer is the user. After this plan, the
`flip-verdict` ledger row (already emitted automatically, unconditionally, on every
authorized checkbox flip) also carries a bare plan slug and an evidence-file pointer,
and a new read-only script (`verify-event-audit.sh`) lets the maintainer ask "does
this checked task have a verification event on record?" and get an honest
HAS_EVENT_ON_RECORD / NO_VERIFICATION_EVENT_ON_RECORD answer for any plan task,
without opening the ledger by hand.

## Scope
- IN: `flip_ledger_fields`/`emit_flip_ledger_event` field-contract extension
  (`adapters/claude-code/hooks/plan-edit-validator.sh`); the comment-registry note in
  `adapters/claude-code/hooks/lib/signal-ledger.sh`; the new read-only consumer
  `adapters/claude-code/scripts/verify-event-audit.sh`; the corresponding
  documentation update in `adapters/claude-code/agents/task-verifier.md` Step 8; the
  HARNESS-GAP-62 backlog amendment recording the fuller (bare-numeric-id) finding; the
  `status-event-ledger.md` SE4 entry's own traceability note.
- OUT: fixing HARNESS-GAP-62 itself (the pre-existing TASK_ID regex gap that blocks
  bare-numeric and fused-letter ids from ever reaching the emit function) —
  authorization-path surgery, high blast radius, deliberately not bundled with this
  additive field change. Filed, not silently worked around. Reviving any of the
  status-event-ledger plan's own remaining UNBUILT/PARTIAL tasks (SE2, SE5, SE6, SE7,
  SE8, SE9) — that plan stays DEFERRED; this plan only extends the one already-BUILT
  mechanism (SE4) it documents.

## Tasks

- [ ] 1. Extend `flip_ledger_fields`/`emit_flip_ledger_event` (`adapters/claude-code/hooks/plan-edit-validator.sh`) with a bare plan-slug field and an `evidence=<file>#task=<id>` pointer; add self-test scenarios F25-F27; build the read-only consumer `adapters/claude-code/scripts/verify-event-audit.sh` (`--task`/`--plan`/`--sweep`/`--self-test`); document the automatic emission in `adapters/claude-code/agents/task-verifier.md` Step 8; amend `docs/backlog.md` HARNESS-GAP-62 and `docs/plans/deferred/status-event-ledger.md`'s SE4 entry with the bare-numeric-id finding — Verification: full — Docs impact: task-verifier.md Step 8 + status-event-ledger.md SE4 entry updated same commit

## Files to Modify/Create
- `adapters/claude-code/hooks/plan-edit-validator.sh` — SE4 extension: evidence pointer + bare plan slug in the `flip-verdict` detail; self-test F25-F27
- `adapters/claude-code/hooks/lib/signal-ledger.sh` — comment-registry note on the extended `flip-verdict` field contract (no functional change)
- `adapters/claude-code/scripts/verify-event-audit.sh` — new: read-only checked-box-vs-ledger-event cross-check (`--task`/`--plan`/`--sweep`/`--self-test`)
- `adapters/claude-code/agents/task-verifier.md` — Step 8: document the automatic ledger emission
- `docs/backlog.md` — HARNESS-GAP-62 amendment (bare-numeric-id finding + 0/926 production-row measurement)
- `docs/plans/deferred/status-event-ledger.md` — SE4 taxonomy row + task entry: 2026-08-04 extension note

## Assumptions
- The event/projection framing (ledger row = fact, plan-file checkbox = human-
  reviewable rendering of that fact) is the correct mental model for this mechanism,
  per the operator's own "single source of truth within the plan file... additionally
  updating the global status" framing — divergence (checked box, no event) is a
  feature to surface, never silently reconciled or fabricated away.
- `plan-edit-validator.sh` remains the sole checkbox-flip chokepoint; extending its
  existing emit call is preferred over adding a second, task-verifier-invoked emitter,
  because the former is mechanically enforced (every authorized flip passes through
  this exact function) while the latter would only be protocol-required (task-verifier
  would have to remember an extra step).

## Edge Cases
- A checked box with no matching event is NOT necessarily a problem — it may predate
  SE4 (2026-07-30), or use a task-id convention the authorizer's own TASK_ID regex
  cannot parse (HARNESS-GAP-62). `verify-event-audit.sh` reports the honest absence,
  never a verdict on whether the absence is concerning.
- A dotted task id (e.g. "3.2") must never false-match a differently-shaped id via
  regex-dot-as-wildcard — `verify-event-audit.sh` uses fixed-string matching
  specifically to close this; F-mutation-tested (see evidence).
- jq-unavailable environments degrade to a raw-line grep fallback in both the emitter
  (pre-existing, unchanged) and the new consumer — never crashes, never blocks.

## Testing Strategy
- `plan-edit-validator.sh --self-test`: full suite, all 27 scenarios (was 24), F25-F27
  are new; each new/changed assertion mutation-tested (fix point reverted, exact
  expected-vs-actual failure shown, then restored to green).
- `verify-event-audit.sh --self-test`: 7 scenarios covering match/no-match/backfill-
  sweep/recursion/missing-ledger/dot-as-wildcard-safety/trailing-dot extraction; 3 of
  the 7 fix points independently mutation-tested.
- Live end-to-end proof (not just self-test): a real `Edit` payload through the
  UNMODIFIED hook, against a real isolated `SIGNAL_LEDGER_PATH`, shows the ledger row
  exists while the plan file is still `- [ ]` on disk; only after the Edit is
  separately applied does `verify-event-audit.sh --task` report
  `HAS_EVENT_ON_RECORD` — demonstrating the write-order (event, then checkbox) claim
  directly rather than by assertion.
- Real backfill measurement: `verify-event-audit.sh --sweep docs/plans` against this
  repo's actual `docs/plans/` tree (254 files, active + archive/ + deferred/) —
  926 currently-checked tasks, 0 with a matching event (see Assumptions/Decisions Log
  for why, and `docs/backlog.md` HARNESS-GAP-62 for the full finding).

Walking Skeleton: n/a — an additive field extension to an existing, already-wired
emit call plus one new read-only script; no new architectural layers.

## Decisions Log
- 2026-08-04 (decide-and-go, constitution §8 — reversible): discovered mid-dispatch
  that the requested mechanism already exists as SE4
  (docs/plans/deferred/status-event-ledger.md, built 2026-07-30) and extended it in
  place rather than building a parallel, task-verifier-invoked emitter — the existing
  mechanism is MECHANICALLY enforced (lives inside the sole checkbox-flip gate) while
  a task-verifier-invoked call would only be protocol-required; extending the stronger
  existing mechanism is strictly better and avoids a second, competing ledger-write
  path for the same fact.
- 2026-08-04 (decide-and-go, reversible): opened this plan file AFTER the code was
  already built and self-tested, mirroring the hotfix flow the scope-enforcement-gate
  itself sanctions (see `docs/plans/archive/workstreams-debounce-and-sentinel-tests-hotfix-2026-07-29.md`'s
  own Decisions Log precedent, `frozen: true` at birth) — needed only to satisfy the
  gate's active-plan requirement for this otherwise plan-free direct dispatch
  (NL-ATTRIBUTION: plan=none task=none role=builder).
- 2026-08-04 (decide-and-go, reversible): did NOT attempt to fix HARNESS-GAP-62 (the
  TASK_ID regex gap, now proven to also block bare-numeric ids) in this same change —
  authorization-path surgery is high blast radius and the dispatch scope was
  explicitly the ledger-event addition; filed the fuller finding to the existing
  backlog row instead of silently expanding this plan's diff.
- 2026-08-04 (decide-and-go, reversible): left this plan's own Task 1 checkbox
  unflipped — per this dispatch's explicit instruction not to invoke task-verifier
  (the change touches task-verifier.md itself), the checkbox flip is left for the
  orchestrator's own subsequent task-verifier pass, not self-certified here.

## Definition of Done
- [ ] Task 1 checked off (by task-verifier, not this session)
- [x] plan-edit-validator.sh self-test 27/0
- [x] verify-event-audit.sh self-test 7/7
- [x] Live end-to-end proof captured (real hook + real isolated ledger + real read-side check)
- [x] SCRATCHPAD.md updated with final state
