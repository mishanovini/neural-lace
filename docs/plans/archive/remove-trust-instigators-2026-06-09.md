# Plan: Remove the trust/keep-going instigators that let false-DONE ship
Status: COMPLETED
Execution Mode: orchestrator
Mode: code
Backlog items absorbed: none
acceptance-exempt: true
acceptance-exempt-reason: harness rules + Stop-hook library edits with no user-facing product surface; self-tests are the acceptance artifacts
tier: 2
rung: 1
architecture: coding-harness
frozen: true
prd-ref: n/a — harness-development

## Goal
On 2026-06-09 the orchestrator shipped false "done/deployed/verified" claims on the Workstreams
consolidation. Root-cause trace (verified, not hypothesized): (a) `pre-stop-verifier.sh` correctly
blocked the incomplete plan 38 times, but the retry-guard's 3-retry loop-breaker downgraded every
block after the third to a warning nobody read — the autonomous loop rode past a working gate;
(b) the orchestrator-pattern rule instructs "trust the result / pass through the verdict," which the
orchestrator applied to UNVERIFIED builder summaries; (c) the plan was marked `acceptance-exempt`
despite being a user-facing UI, switching off the end-user-advocate runtime gate; (d) "drive to
completion / end every turn with a DONE marker" was read as "emit DONE and keep moving" rather than
"do the work until the gates pass." Misha's directive (2026-06-09, verbatim intent): "let's remove
the blatant bad behavior instigators. Let's remove anything that tells you to trust anything."
This plan removes those instigators at their sources.

## User-facing Outcome
The maintainer (the harness's user) gets a harness where: an agent cannot end a turn claiming
`DONE:` while a verification gate says the work is incomplete (the retry-guard refuses to downgrade
verification-class blocks under a DONE claim); a user-facing plan cannot switch off runtime
acceptance via `acceptance-exempt`; and no rule instructs any agent to trust any unverified claim —
every "trust the verdict" instruction is replaced with "confirm the evidence artifact exists."

## Scope
- IN: trust-language removal in `orchestrator-pattern.md` + `planning.md`; keep-going scoping in
  `testing.md`, `CLAUDE.md`, `session-end-protocol.md`; retry-guard verification-class no-downgrade-
  under-DONE mechanism + self-tests; product-acceptance-gate user-facing-surface exemption refusal +
  self-test; `acceptance-scenarios.md` exemption-guidance update; live `~/.claude/` sync.
- OUT: the Workstreams consolidation rebuild itself (separate, still-open work); changes to
  narrate-and-wait-gate or continuation-enforcer; the scope-gate session-cwd fix (separate
  discovery already filed); any retroactive plan-state edits.

## Tasks

- [ ] 1. Remove trust-language from `orchestrator-pattern.md` and `planning.md`; replace with require-evidence instructions (orchestrator confirms the task-verifier evidence artifact/checkbox exists; builder summaries are claims until cited) — Verification: mechanical
- [ ] 2. Scope keep-going/drive-to-completion in `testing.md`, `CLAUDE.md`, and `session-end-protocol.md`: keep-going kills permission-seeking stops ONLY and never overrides a verification gate; DONE only when gates pass — Verification: mechanical
- [ ] 3. Extend `stop-hook-retry-guard.sh`: verification-class hooks (pre-stop-verifier, product-acceptance-gate) refuse downgrade while the final assistant message claims `DONE:`; add self-test scenarios — Verification: mechanical
- [ ] 4. Extend `product-acceptance-gate.sh`: a plan declaring `acceptance-exempt: true` whose declared files include user-facing surfaces (src/app/, src/components/, page.tsx, */web/, *-ui/) is BLOCKED as invalidly exempt; add self-test scenario — Verification: mechanical
- [ ] 5. Update `acceptance-scenarios.md` exemption guidance to document the user-facing-surface refusal — Verification: mechanical
- [ ] 6. Sync all changed canonical files to live `~/.claude/` byte-identical (diff-verified) — Verification: mechanical

## Files to Modify/Create
- `docs/plans/remove-trust-instigators-2026-06-09.md` — this plan
- `adapters/claude-code/rules/orchestrator-pattern.md` — remove trust-the-verdict language (steps 4, Nested verification, anti-pattern 3)
- `adapters/claude-code/rules/planning.md` — remove "orchestrator trusts the verdict" line
- `adapters/claude-code/rules/testing.md` — scope the keep-going directive vs verification gates
- `adapters/claude-code/rules/session-end-protocol.md` — DONE marker requires verification gates passing; downgraded verification gate forbids DONE
- `adapters/claude-code/rules/acceptance-scenarios.md` — exemption refused on user-facing surfaces
- `adapters/claude-code/CLAUDE.md` — scope drive-to-completion (never past a verification gate)
- `adapters/claude-code/hooks/lib/stop-hook-retry-guard.sh` — verification-class no-downgrade-under-DONE + self-tests
- `adapters/claude-code/hooks/product-acceptance-gate.sh` — user-facing-surface exemption refusal + self-test

## In-flight scope updates
(no in-flight changes yet)

## Assumptions
- The retry-guard library receives the hook's input JSON via `retry_guard_session_id "$INPUT"` in
  every consumer, so capturing `transcript_path` there as a side effect reaches `retry_guard_block_or_exit`
  without editing any call site.
- Refusing downgrade under a DONE claim cannot create the infinite-loop DoS the retry-guard exists to
  prevent, because the agent can ALWAYS resolve the block in-loop by changing its marker to
  PAUSING:/BLOCKED: (an action entirely within its power).
- The transcript JSONL shape (`{"type":"assistant","message":{"content":[...]}}` lines) matches what
  sibling Stop hooks already parse.

## Edge Cases
- Transcript missing/unparseable at downgrade time → fail-open (downgrade proceeds as before); the
  mechanism only changes behavior when a DONE claim is provably present.
- A PAUSING:/BLOCKED: final marker → downgrade proceeds (honest pause stays expressible; sessions can
  still end mid-plan without lying).
- Non-verification hooks (narrate-and-wait, decision-context, etc.) → downgrade behavior unchanged.
- Plans with `acceptance-exempt: true` and no UI-pattern matches in declared files → exemption honored
  unchanged (harness-infra plans unaffected; this plan itself is the regression test).
- Existing self-test scenarios must keep passing (no behavior change below threshold).

## Acceptance Scenarios
- n/a — acceptance-exempt (harness rules + hook library; the self-tests in Tasks 3-4 are the
  runtime acceptance artifacts, replayable via `--self-test`).

## Out-of-scope scenarios
- Runtime browser scenarios — no user-facing product surface in this plan's declared files.

## Testing Strategy
- Task 1/2/5: grep-verifiable — the removed phrases are absent; the replacement phrases present.
- Task 3: `bash adapters/claude-code/hooks/lib/stop-hook-retry-guard.sh --self-test` — all prior
  scenarios green PLUS new scenarios (verification hook + DONE → stays blocked; verification hook +
  PAUSING → downgrades; non-verification hook + DONE → downgrades).
- Task 4: `bash adapters/claude-code/hooks/product-acceptance-gate.sh --self-test` — all prior
  scenarios green PLUS new scenario (exempt plan declaring UI files → BLOCK).
- Task 6: `diff -q` per synced file, zero differences.

## Walking Skeleton
Task 3 is the skeleton: one new guard clause in the downgrade branch + a fake-transcript self-test
proving DONE-blocks and PAUSING-downgrades end-to-end through the real library code path.

## Decisions Log
### Decision: refuse-downgrade-under-DONE instead of non-downgradeable verification gates
- **Tier:** 2
- **Status:** proceeded with recommendation (Misha directed removing the instigators; design chosen for him to review in this PR)
- **Chosen:** verification-class hooks keep the 3-retry downgrade EXCEPT when the final message claims DONE:.
- **Alternatives:** (a) fully non-downgradeable verification gates — rejected: recreates the infinite-loop DoS for honest mid-plan pauses (sessions could never end while a plan is in flight); (b) status quo — rejected: it is the proven bypass vector (38 ignored blocks on 2026-06-09).
- **Reasoning:** the lie-vector is the DONE claim, not the pause. An agent can always change its marker; it cannot always complete the work. Blocking exactly the dishonest case preserves the loop-break's legitimate purpose.
- **Checkpoint:** this plan's commit
- **To reverse:** revert the guard clause in `retry_guard_block_or_exit`.

## Pre-Submission Audit
- S1 (Entry-Point Surfacing): n/a — Mode: code single-purpose plan; behavior changes are cited per-file in Files to Modify.
- S2 (Existing-Code-Claim Verification): line targets read directly from the worktree this session (orchestrator-pattern.md:191/275/296; retry-guard lib lines 343-393; acceptance-gate lines 233-252, 793-807).
- S3 (Cross-Section Consistency): swept — no contradictory claims between Tasks and Edge Cases.
- S4 (Numeric-Parameter Sweep): single parameter (RETRY_GUARD_THRESHOLD=3) unchanged everywhere.
- S5 (Scope-vs-Analysis Check): swept — all Add/Modify verbs target files in the IN list.

## Definition of Done
- [ ] All tasks checked off (via mechanical evidence per task)
- [ ] Both self-tests green (retry-guard + product-acceptance-gate)
- [ ] Live `~/.claude/` byte-identical to canonical for every changed file
- [ ] Completion report appended; Status flipped via close-plan

## Completion Report

_Generated by close-plan.sh on 2026-06-09T20:52:31Z._

### 1. Implementation Summary

Plan: `docs/plans/remove-trust-instigators-2026-06-09.md` (slug: `remove-trust-instigators-2026-06-09`).

Files touched (per plan's `## Files to Modify/Create`):

- `adapters/claude-code/CLAUDE.md`
- `adapters/claude-code/hooks/lib/stop-hook-retry-guard.sh`
- `adapters/claude-code/hooks/product-acceptance-gate.sh`
- `adapters/claude-code/rules/acceptance-scenarios.md`
- `adapters/claude-code/rules/orchestrator-pattern.md`
- `adapters/claude-code/rules/planning.md`
- `adapters/claude-code/rules/session-end-protocol.md`
- `adapters/claude-code/rules/testing.md`
- `docs/plans/remove-trust-instigators-2026-06-09.md`

Commits referencing these files:

```
01bc9ba feat(rules): pre-existing-oracle paragraph in FUNCTIONALITY-OVER-COMPONENTS (#37)
03e4883 feat(harness): credentials inventory mechanism for cross-session auth visibility
04f524d fix(harness): remove trust/keep-going instigators behind the 2026-06-09 false-DONE incident
07b5097 feat(item10): credentials-reference presence check in install.sh + CLAUDE.md strengthening (#53)
082be8b fix(harness): scope product-acceptance plan discovery to the current repo
0909869 feat(work-shapes): Tranche C — work-shape library + rule + integrations
2a49b11 feat(harness): resolve 3 pending discoveries — sweep hook, divergence detector, worktree-Q workaround
2b47af7 feat(hook): product-acceptance-gate multi-worktree aggregation (plan task 10)
393ba6f feat(harness): Phase B template + rule pattern for end-user-advocate acceptance loop
3a2babc reconverge: land personal fork onto PT master (decision-context + pr-health + F7 + principles)
3e3568f feat(harness): build-harness-infrastructure work-shape — lighter process carve-out for harness work
3f2c6c4 docs(orchestrator): add anti-pattern #7 — --dry-run-first for install-class work
460519e feat(build-doctrine): Tranche 5a-integration ritual wired audit analyzer pilot template
483f5f6 feat(harness): Gen 5 — design-mode planning + outcome-focused reviewers
4d94940 docs(plan-mode): Execution Mode: agent-team value + cross-references (plan task 12)
50d670d feat(harness): integration-verification gate — plan-time Check 13 + runtime wire-check-gate
55742f2 docs(rules): SCRATCHPAD triggers (Rule 2) + review-finding IDs (Rule 4) + memory last_verified (Rule 7)
588c5b7 reconverge: cherry-pick 5 personal PRs (#40/#41/#42/#43/#44) onto PT master (#39)
5c8e3e4 feat(harness): no-test-skip gate + deploy-to-production rule
6035c9f feat(lifecycle): DEFERRED plans route to docs/plans/deferred/, not archive/ (ADR 052)
69181f4 feat(harness): wire-check-gate adds STATIC TRACE — always runs; runtime evidence becomes additive
6b79adb fix(acceptance-gate): plan discovery cwd-only, not across worktrees
6ef7c2c docs(harness): HARNESS-GAP-46 + orchestrator-pattern cross-repo worktree convention (#52)
70e5262 feat: capture-codify PR template + CI workflow + 7 decision records (#1)
72ad219 docs(harness): planning.md — unified plan file lifecycle convention
784974e feat(rules): bug persistence — every identified bug goes to durable storage within the same session
793b37f chore: reconcile ADR numbering + worktree-per-session guidance (5-pattern cleanup) (#2)
8e1d735 feat(harness): Phase F builder discipline — scenarios-shared/assertions-private (F.1, F.2)
964a2ed feat(harness): mandatory verbose plans with required-section validator
9bddbfc feat(harness): FUNCTIONALITY OVER COMPONENTS — codify the most important rule across planning, builder, verifier, testing, template, and hook
```

Backlog items absorbed: see plan header `Backlog items absorbed:` field;
the orchestrator can amend this section post-procedure with shipped/deferred
status per item.

### 2. Design Decisions & Plan Deviations

See the plan's `## Decisions Log` section for the inline record. Tier 2+
decisions should each have a `docs/decisions/NNN-*.md` record landed in
their implementing commit per `~/.claude/rules/planning.md`.

### 3. Known Issues & Gotchas

(orchestrator may amend post-procedure)

### 4. Manual Steps Required

(orchestrator may amend post-procedure — env vars, deploys, third-party setup)

### 5. Testing Performed & Recommended

See the plan's `## Testing Strategy` and `## Evidence Log` sections.
This procedure verifies that every task has its declared verification level
satisfied before allowing closure.

### 6. Cost Estimates

(orchestrator may amend; harness-development plans typically have no recurring cost — n/a)
