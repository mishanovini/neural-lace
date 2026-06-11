# Plan: Agent-upgrade batch 2 — A/B staging + evaluation program (16 agents)
Status: ACTIVE
Execution Mode: orchestrator
Mode: code
Backlog items absorbed: none
acceptance-exempt: true
acceptance-exempt-reason: harness-internal agent-prompt staging; deliverables are staged prompt files + A/B fixtures with no product user; fixture self-checks are the acceptance artifact
tier: 2
rung: 1
architecture: coding-harness
frozen: true
prd-ref: n/a — harness-development
owner: orchestrator (A/B runs + apply decisions); T1-prep subagent (staging + fixtures)
target-completion-date: 2026-06-17

## Goal
Stage the 16 remaining agent-prompt upgrades from the 2026-06-05 proposal batch
(12 APPLY-WITH-WATCH + 4 NEEDS-MISHA per
`~/claude-projects/workstreams-coordination/AGENT-UPGRADE-DIGEST-2026-06-09.md`)
on a branch, and ship one discriminating A/B test fixture per agent so the
orchestrator can exercise each upgraded prompt against a real representative
task, compare behavior vs the current prompt, and apply (or present results for)
each agent individually. Per Misha's decided protocol: apply each on a branch,
exercise against a REAL representative task, compare, present per-agent results;
the 4 NEEDS-MISHA agents get results only — no apply.

## User-facing Outcome
The maintainer can run a per-agent A/B (same fixture prompt, current vs staged
agent definition), score both transcripts against a written expected-delta
rubric, and make an evidence-based apply/reject decision per agent instead of
applying 16 prompt rewrites on faith.

## Scope
- IN: `adapters/claude-code/agents-staged/*.md` (16 staged upgrade files);
  `.claude/state/agent-ab-fixtures/**` (16 fixtures + MANIFEST.md + generator);
  this plan file.
- OUT: any change to `adapters/claude-code/agents/` (live agent files), the
  `~/.claude/` live mirror, master merges, hook/rule/template changes, and the
  A/B apply decisions themselves (orchestrator + Misha own those).

## Tasks
- [ ] 1. Stage the 16 upgraded agent files in `agents-staged/` (proposal section
  C content, drift-reconciled) — Verification: mechanical
- [ ] 2. Author 16 discriminating fixtures + expected-delta rubrics + MANIFEST —
  Verification: mechanical
- [ ] 3. Orchestrator: run the 16 A/B exercises per MANIFEST.md and record
  per-agent results — Verification: mechanical
- [ ] 4. Orchestrator: apply WATCH-tier upgrades per-agent on rubric PASS
  (gap-analyzer + harness-reviewer as a pair); present NEEDS-MISHA results to
  Misha with no apply — Verification: mechanical

## Files to Modify/Create
- `adapters/claude-code/agents-staged/*.md` — the 16 staged upgrade files
- `.claude/state/agent-ab-fixtures/**` — fixtures, rubrics, MANIFEST.md, generator
- `docs/plans/agent-upgrades-batch2-ab-staging.md` — this plan file
- `adapters/claude-code/agents/*.md` — Task 4 only: per-agent apply after A/B
  PASS (WATCH tier only; NEEDS-MISHA agents are excluded until Misha decides)

## In-flight scope updates
(no in-flight changes yet)

## Assumptions
- The 2026-06-05 proposals' section (C) blocks are the authoritative upgraded
  prompts; zero drift on master since 2026-06-05 was verified per-agent via git
  log before staging.
- The orchestrator can dispatch a fixture prompt under an arbitrary agent
  definition (current vs staged) for the A/B runs.
- `.claude/state/` is gitignored; fixtures are force-added so the branch carries
  them.

## Edge Cases
- Pair-coupled agents (enforcement-gap-analyzer + harness-reviewer) must be
  applied in the same commit or not at all — fixtures and MANIFEST encode this.
- Hook-parsed output contracts (task-verifier evidence block, plan-evidence-
  reviewer sentinels, end-user-advocate artifact JSON, advocate scenario format)
  are regression-checked by the rubrics' contract checks; any drift is an
  auto-reject for that agent's apply.
- A fixture that fails to discriminate (both runs identical) is a no-evidence
  outcome: the agent stays unapplied and the fixture is redesigned.

## Acceptance Scenarios
- n/a — acceptance-exempt (harness-internal staging; see exemption reason).

## Out-of-scope scenarios
- n/a — acceptance-exempt.

## Testing Strategy
- Task 1: diff staged files against proposal section-C extraction (14 byte-exact
  + 2 documented reconciliations); frontmatter name/tools sanity scan;
  hook-contract string greps (sentinels, Runtime verification formats,
  plan_commit_sha/verdict fields).
- Task 2: runnable fixtures executed at authoring time (greet.sh self-test +
  planted empty-input bug; slugify original suite 6/6 vs original, 3/6 vs v2;
  builder suite 4/4; walk suite 1/1); MANIFEST regenerated from fixture files by
  `gen-manifest.sh` so embedded prompts/rubrics cannot drift from the per-fixture
  files.
- Tasks 3-4: per-agent rubric scoring by the orchestrator; contract-check
  violations in the upgraded run are auto-rejects.

## Walking Skeleton
n/a — staging + fixtures only; no new mechanism is built by this plan.

## Decisions Log
- 2026-06-10: ux-end-user-tester staged file adds 7 browser-MCP tools to
  frontmatter (digest-mandated reconciliation of the proposal's tools-vs-prose
  mismatch). Tier 1 — reversible one-line frontmatter change, documented in
  MANIFEST.
- 2026-06-10: harness-reviewer staged file accepts BOTH legacy and renamed
  analyzer section headers in Steps 5.1/5.3 (digest-mandated pair-coupling
  reconciliation). Tier 1 — reversible, documented in MANIFEST.

## Pre-Submission Audit
- n/a — single-purpose staging plan (Mode: code), no class-sweep needed.

## Definition of Done
- [ ] All tasks checked off (Tasks 3-4 by the orchestrator after A/B runs)
- [ ] WATCH-tier agents applied or rejected per-agent with rubric citations
- [ ] NEEDS-MISHA results presented; this plan flipped to COMPLETED and archived
