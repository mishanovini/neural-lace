# Plan: Remove the trust/keep-going instigators that let false-DONE ship
Status: ACTIVE
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
