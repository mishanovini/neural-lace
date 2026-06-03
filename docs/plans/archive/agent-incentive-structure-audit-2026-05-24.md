# Plan: Agent-Incentive-Structure Audit 2026-05-24
Status: COMPLETED
Execution Mode: orchestrator
Mode: code
Backlog items absorbed: none
acceptance-exempt: true
acceptance-exempt-reason: docs-only audit; no product runtime to advocate for; READ-ONLY against the harness; deliverable is the audit document plus coordination notes
prd-ref: n/a — harness-development
tier: 1
rung: 0
architecture: docs
frozen: true

## Goal

Produce a one-time systematic audit of agent incentive structure across the full
Neural Lace harness enforcement substrate (60+ hooks/rules/validators), complementing
the daily `harness-evaluator` (System 2) with a baseline incentive-gap scoring pass.
Surface the prioritized fix list for the daily evaluator to track over time and
propose the top 3 items to the Decision Queue for triage.

## User-facing Outcome

Misha (the only user of the audit) has a single document at
`docs/reviews/2026-05-24-agent-incentive-structure-audit.md` covering:
- Inventory summary (84 enforcement artifacts catalogued)
- Per-rule incentive-gap scoring (0-5 rubric)
- Cross-cutting pattern smells
- 10-item prioritized fix list with effort/impact/coupling
- Coordination notes for the harness-evaluator and Decision Queue substrates
- Honest "what surprised me" + limitations section

## Scope

- IN: docs/reviews/2026-05-24-agent-incentive-structure-audit.md (the audit document itself)
- IN: docs/plans/agent-incentive-structure-audit-2026-05-24.md (this plan file)
- OUT: any hook/rule/agent modifications (the audit is READ-ONLY per charter)
- OUT: writes to .claude/state/decision-queue/ (the queue lives on a separate branch; coordination is via message, not unilateral write)
- OUT: changes to the harness-evaluator (any integration is a follow-up plan)

## Tasks

- [x] 1. Run three parallel read-only research agents: inventory enforcement substrate, forensic bypass-pattern sweep, in-flight evaluator/queue context — Verification: mechanical

- [x] 2. Synthesize the audit document with score-distribution per rule, pattern smells, prioritized fix list, coordination notes, and honesty section — Verification: mechanical

## Files to Modify/Create

- `docs/reviews/2026-05-24-agent-incentive-structure-audit.md` — the audit document
- `docs/plans/agent-incentive-structure-audit-2026-05-24.md` — this plan file (self-claim)

## In-flight scope updates

(none)

## Assumptions

- The daily `harness-evaluator` script exists at `adapters/claude-code/scripts/harness-evaluator.sh` and writes packets to `.claude/state/harness-eval/` (confirmed by research agent C).
- The Decision Queue substrate lives on `feat/decision-queue` branch (confirmed; `decision-queue.sh` not yet on master).
- The Neural Lace repo's bypass numbers are the authoritative substrate; downstream-project counts come from HARNESS-GAP-29/30/31 filing notes and are cited as such.

## Edge Cases

- Two parallel sessions on the same repo: confirmed (`docs/cross-machine-context-handoff-2026-05-24` branch appeared concurrently). The audit branch is named distinctly to avoid collision.
- Worktree-gitlink ignores: the scope-enforcement-gate's trailing-slash fix (commit bf89a75) is on a sibling branch; the audit branch is created from master so the fix may not be present, but the audit doesn't trigger that gate path.

## Testing Strategy

- Mechanical verification: the audit document exists, has all required sections (TL;DR, Method, Inventory, Scoring, Pattern Smells, Fix List, Coordination, Surprises, Limitations), and the scoring section has 53 rules totaled.
- Coordination verification: messages to local_bb36c9bf and local_eb88629f drafted in Section 6 of the audit document with concrete `decision-queue.sh add` invocations.

## Walking Skeleton

The thinnest end-to-end slice: a single audit document is produced, committed, pushed, and a PR is opened (not merged). That IS the deliverable.

## Decisions Log

### Decision: docs-only branch off master (not off the current parent branch)
- **Tier:** 1
- **Status:** proceeded with recommendation
- **Chosen:** branch from master at `bf89a75` (the trailing-slash fix is on parent; not needed for audit work which doesn't touch gitlinks)
- **Alternatives:** branch from the parent feature branch (would couple audit to that PR's review cycle)
- **Reasoning:** audit is genuinely orthogonal; branching from master keeps it independent

### Decision: rename audit file to date-prefixed convention
- **Tier:** 1
- **Status:** proceeded with recommendation
- **Chosen:** `2026-05-24-agent-incentive-structure-audit.md` (date prefix per `harness-hygiene.md` reviews convention)
- **Alternatives:** force-add with `git add -f` (rejected — would bypass the gitignore convention)
- **Reasoning:** the gitignore allowlist `[0-9]{4}-[0-9]{2}-[0-9]{2}-*.md` exists precisely so NL-self audits are tracked while downstream-project artifacts stay ignored. Renaming is the right path.

### Decision: create this minimal plan to satisfy scope-enforcement-gate
- **Tier:** 1
- **Status:** proceeded with recommendation
- **Chosen:** open a new plan (Option 2 per scope-gate's three structural options)
- **Alternatives:** add to `## In-flight scope updates` on an ACTIVE plan (rejected — audit is orthogonal); `--no-verify` (forbidden by harness rules)
- **Reasoning:** the gate is correct; the audit IS its own work. Creating a minimal plan is the substantive path. This is itself a friction-reflexion moment (audit work requires a plan to ship), but the discipline is correct.

## Definition of Done

- [x] All tasks checked off
- [x] Audit document complete with all 8 sections
- [x] Plan file populated with substantive content (this file)
- [x] Commit lands without `--no-verify`
- [x] PR opened (NOT merged per charter)
- [x] Coordination notes drafted for local_bb36c9bf + local_eb88629f
