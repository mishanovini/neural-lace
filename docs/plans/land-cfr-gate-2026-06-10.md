# Plan: Land the salvaged customer-facing-review gate
Status: ACTIVE
Execution Mode: orchestrator
Mode: code
Backlog items absorbed: none
acceptance-exempt: true
acceptance-exempt-reason: harness-internal Stop-hook mechanism; no product user or runtime UI — the gate's --self-test suite is the acceptance artifact per the build-harness-infrastructure work-shape
tier: 1
rung: 1
architecture: coding-harness
frozen: true
prd-ref: n/a — harness-development

## Goal
Land the salvaged customer-facing-review gate (built 2026-06-02, preserved on
`origin/feat/customer-facing-review-gate-2026-06-01` @ 59c28ab) onto master.
The gate is a Stop hook that blocks session wrap when a session SPAWNED
customer-facing build work but never invoked BOTH a UX-family agent AND the
customer-advocate agent (`end-user-advocate`). The originating failure: on
2026-06-02 the Dispatch orchestrator spawned four customer-facing sessions
with zero UX/CX agent review — the requirement was social, not mechanical.
This plan makes it mechanical on master, resolving drift vs current master
(ADR renumber 046→053; Stop-chain wiring position; INDEX row).

## User-facing Outcome
The maintainer's harness blocks session wrap (block-mode default) whenever a
session spawned customer-facing work without UX + customer-advocate review.
The gate's `--self-test` passes (8 named scenarios + disable bonus), the rule
is discoverable via `rules/INDEX.md`, and the live `~/.claude/` mirror is
byte-identical to the canonical files.

## Scope
- IN: cherry-pick of salvage commit 59c28ab content; ADR renumber 046→053
  (master took 046 for workstreams-lifecycle-emit; 051 reserved; 052 taken);
  Stop-chain wiring in `settings.json.template` (after
  `pr-health-snapshot-gate.sh`, before `session-wrap.sh refresh`); INDEX.md
  row; vaporware-prevention enforcement-map row; DECISIONS.md row;
  harness-architecture.md row; live-sync to `~/.claude/`.
- OUT: any change to the gate's classifier logic or agent-family lists; the
  companion completion-criteria-gate criterion (already shipped separately);
  the main checkout's staged batch (another session's work — untouched);
  extending the gate to direct (non-spawned) customer-facing edits (known
  limitation documented in the rule).

## Tasks

- [ ] 1. Cherry-pick salvage content onto worktree branch; resolve drift vs master (ADR 046→053 renumber, shared-file rows re-applied onto current master content) — Verification: mechanical
- [ ] 2. Run `customer-facing-review-gate.sh --self-test` — all scenarios must pass — Verification: mechanical
- [ ] 3. Verify Stop-chain wiring in `settings.json.template` (gate after pr-health-snapshot-gate.sh, before session-wrap.sh refresh) + INDEX row + golden test `evals/golden/rules-index-coverage.sh` — Verification: mechanical
- [ ] 4. Hygiene scan staged diff; commit; merge to master; live-sync hook + rule + live settings.json Stop chain — Verification: mechanical

## Files to Modify/Create
- `docs/plans/land-cfr-gate-2026-06-10.md` — this plan
- `adapters/claude-code/hooks/customer-facing-review-gate.sh` — the salvaged Stop-hook gate (new)
- `adapters/claude-code/rules/customer-facing-review.md` — the salvaged rule stub (new; ADR ref renumbered to 053)
- `adapters/claude-code/rules/INDEX.md` — +1 row for customer-facing-review.md
- `adapters/claude-code/rules/vaporware-prevention.md` — +1 enforcement-map row
- `adapters/claude-code/settings.json.template` — +4 lines Stop-chain wiring
- `docs/decisions/053-customer-facing-review-gate.md` — salvaged ADR, renumbered from 046 (046 taken on master; 051 reserved; 052 taken)
- `docs/DECISIONS.md` — +1 index row (053)
- `docs/harness-architecture.md` — Stop-chain table row + last-updated note

## In-flight scope updates
- 2026-06-10: `docs/backlog.md` — filed HARNESS-GAP-47 (UX/CX criterion never folded into completion-criteria-gate), discovered while fixing the rule/ADR's stale "in-flight" coordination claims during the landing

## Assumptions
- The salvage commit 59c28ab is the reviewed, anonymized, canonical content
  (byte-identical to the other session's staged copies — verified before
  cherry-pick), so no content rework is needed beyond the ADR renumber and
  drift resolution on shared files.
- Master's Stop chain in `settings.json.template` still has
  `pr-health-snapshot-gate.sh` immediately before `session-wrap.sh refresh`,
  so the salvaged 4-line wiring hunk applies at the same anchor.
- The gate's self-test is gh-free per the hook's own conventions (mirrors
  `pr-health-snapshot-gate.sh`), so it passes cold in CI without a
  `KNOWN_FAILING_HOOKS` entry.

## Edge Cases
- ADR-number collision (the catalogued ADR-collision class): salvage says 046;
  master's 046 is workstreams-lifecycle-emit; 051 is reserved by
  cross-machine-coordination per ADR 052's note; 052 taken → renumber to 053
  and sweep every 046 reference in the landed files (rule, ADR body,
  DECISIONS.md row, harness-architecture row).
- The main checkout has ANOTHER session's staged copies of the same hook +
  rule (referencing ADR 046). Those are not touched; the divergence
  (046 vs 053 ADR reference) is reported honestly — the staged copies become
  redundant once this lands.
- Main-checkout ff-sync after merge could clobber the other session's staged
  paths — if so, leave the main checkout unsynced and report it.
- Live `~/.claude/settings.json` is per-machine: wiring applied as a surgical
  jq-validated insertion, not a full rewrite.

## Acceptance Scenarios
- n/a — acceptance-exempt: harness-internal Stop-hook mechanism with no
  product user; the hook's `--self-test` suite (8 named scenarios + disable
  bonus) is the acceptance artifact.

## Out-of-scope scenarios
- Direct (non-spawned) customer-facing edits bypassing the gate — documented
  known limitation in the rule; candidate follow-up, not this plan.

## Testing Strategy
- Task 1: `git diff` review of resolved content vs salvage commit; grep sweep
  for remaining `046-customer-facing` references (must be zero).
- Task 2: `bash adapters/claude-code/hooks/customer-facing-review-gate.sh
  --self-test` exits 0 with all scenarios passing.
- Task 3: `jq` parse of settings.json.template confirms gate position;
  `evals/golden/rules-index-coverage.sh` exits 0.
- Task 4: `harness-hygiene-scan.sh` on staged diff clean; `diff -q` live
  mirror vs canonical for hook + rule; `jq empty` on live settings.json after
  surgical edit.

## Walking Skeleton
n/a — salvage landing of an already-built mechanism; the self-test is the
end-to-end slice.

## Decisions Log

### Decision: Renumber salvaged ADR 046 → 053
- **Tier:** 1
- **Status:** proceeded with recommendation
- **Chosen:** land the ADR as `docs/decisions/053-customer-facing-review-gate.md`
- **Alternatives:** keep 046 (collides with master's workstreams-lifecycle-emit);
  use 051 (explicitly reserved by cross-machine-coordination per ADR 052 note)
- **Reasoning:** 053 is the next genuinely free number; the ADR-collision
  class (`principles.md` Decision Principle 7) mandates checking siblings
  before grabbing "the next number"
- **Checkpoint:** N/A
- **To reverse:** rename file + index row before merge

## Pre-Submission Audit
- S1 (Entry-Point Surfacing): n/a — Mode: code salvage-landing plan, no class-sweep needed
- S2 (Existing-Code-Claim Verification): n/a — Mode: code salvage-landing plan
- S3 (Cross-Section Consistency): n/a — Mode: code salvage-landing plan
- S4 (Numeric-Parameter Sweep): n/a — Mode: code salvage-landing plan
- S5 (Scope-vs-Analysis Check): n/a — Mode: code salvage-landing plan

## Definition of Done
- [ ] All tasks checked off
- [ ] Gate self-test passes (all scenarios)
- [ ] Golden test rules-index-coverage.sh passes
- [ ] Merged to master; live mirror byte-identical
- [ ] Completion report appended to this plan file
