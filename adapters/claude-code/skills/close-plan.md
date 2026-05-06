---
name: close-plan
description: Deterministic close-plan procedure (Tranche E, 2026-05-05). Closes a plan in seconds with zero agent dispatches by routing each task per its declared `Verification:` level (mechanical | contract | full), generating the completion report from commit log + plan files-to-modify, updating SCRATCHPAD, verifying backlog reconciliation, flipping `Status: ACTIVE → COMPLETED` (which triggers the existing plan-lifecycle.sh archival), and auto-pushing per the user's full-auto preference. Use whenever a plan's build work is finished. Replaces the previous heavy-stack coordinator with a thin wrapper around `adapters/claude-code/scripts/close-plan.sh`.
---

# close-plan (deterministic)

Thin slash-command wrapper around `adapters/claude-code/scripts/close-plan.sh`. The script owns the procedure; this skill exists to provide the `/close-plan <slug>` invocation surface and document the contract.

## When to use

Invoke `/close-plan <slug>` when:

- A plan's build work has shipped (last task complete, evidence captured)
- You're ready to flip `Status: COMPLETED` and want closure work done atomically
- The user says "close out the plan" or "wrap up plan X" or "mark plan complete"

## How to invoke

- With argument: `/close-plan <slug>` — operate on `docs/plans/<slug>.md` (or `docs/plans/archive/<slug>.md` if already moved).
- Without argument: read SCRATCHPAD.md's "Active Plan" pointer; if exactly one ACTIVE plan exists in `docs/plans/`, operate on it. Otherwise ask the user which plan to close.

## What the procedure does (in order)

The bash script `adapters/claude-code/scripts/close-plan.sh` performs all closure work mechanically. The skill's job is to invoke the script and surface its output. The procedure:

1. **Locate the plan file** at `docs/plans/<slug>.md` (active first, then archive).
2. **Verify Status is ACTIVE.** Refuses to close non-ACTIVE plans (DEFERRED / ABANDONED / COMPLETED don't need this skill).
3. **Per-task verification routing** (per Tranche D's `Verification:` field):
   - `Verification: mechanical` → bash check: structured `.evidence.json` (per Tranche B's schema) with `verdict==PASS`, OR a one-line evidence-block in the prose evidence file with a commit-SHA citation.
   - `Verification: contract` → bash check: a referenced `Contract:` path exists, OR fall through to mechanical-style evidence acceptance.
   - `Verification: full` (default) → existing prose-evidence path: `Verdict: PASS` block in evidence file or plan's `## Evidence Log` section.
4. **Verify backlog reconciliation.** Every `Backlog items absorbed:` slug must NOT appear in an open backlog section without a `(deferred from`, `(absorbed into`, `ABSORBED`, "Recently implemented", "Completed", or "Resolved" marker.
5. **Block on any failure** unless `--force` is passed (audit-logged to `.claude/state/close-plan-force-overrides.log`).
6. **Generate completion report** from:
   - The plan's `## Files to Modify/Create` section
   - `git log` for commits touching those files
   - Six standard sub-sections (Implementation Summary, Design Decisions, Known Issues, Manual Steps Required, Testing Performed, Cost Estimates)
7. **Update SCRATCHPAD.md** with a "Plan closed: \<slug\>" marker.
8. **Flip `Status: ACTIVE → COMPLETED`** in the plan file. The existing `plan-lifecycle.sh` PostToolUse hook fires and `git mv`s the plan + sibling `<slug>-evidence.md` to `docs/plans/archive/`. (When the script runs outside a Claude Code session, it performs the move itself for idempotency.)
9. **Auto-push** per the user's full-auto preference (`feedback_full_auto_deploy.md`). Skip with `--no-push`.

## Flags

- `--no-push` — Commit changes locally only. The user pushes manually.
- `--force` — Bypass mechanical-check failures. Audit-logged. Use only for emergency override (e.g., the closure-validator hook is being retired in Tranche F and a transition-period bypass is needed).

## Performance contract

The procedure runs in **seconds, not minutes**. A synthetic 3-task plan closes in ~3 seconds (no agent dispatches). The pre-redesign baseline was ~13 dispatches and ~65K tokens. This is the highest-leverage payoff of Tranche 1.5 — closure cost reduced by 10-100×.

## Counter-incentives this skill resists

The orchestrator's bias is to flip `Status: COMPLETED` first and worry about closure work later. The script blocks this — every failure is named in stderr, the procedure refuses to proceed without `--force`, and `--force` is audit-logged. The right path (closure work first, then flip) is the path of least resistance.

If the procedure blocks and the orchestrator is tempted to bypass via direct file edit (manually editing Status, manually `git mv`-ing to archive), STOP. The procedure's checks exist because plans have stranded ACTIVE-but-shipped before. Use `--force` with a documented reason, OR remediate the named failures.

## Cross-references

- `adapters/claude-code/scripts/close-plan.sh` — the script this skill wraps. Self-test: `close-plan.sh --self-test` runs 10 scenarios.
- `adapters/claude-code/hooks/plan-lifecycle.sh` — the PostToolUse hook that auto-archives once Status flips.
- `adapters/claude-code/hooks/plan-closure-validator.sh` — the existing closure-validator (tagged for retirement during Tranche F; the deterministic procedure produces evidence that satisfies it during the transition).
- `~/.claude/templates/completion-report.md` — the template the procedure mirrors.
- `~/.claude/rules/planning.md` — Verifier Mandate, plan-file lifecycle, backlog absorption rules.
- `~/.claude/rules/vaporware-prevention.md` — enforcement-map row for closure-validation.
- `docs/plans/architecture-simplification-tranche-e-deterministic-close-plan.md` — the originating plan.
- `docs/plans/architecture-simplification-tranche-b-mechanical-evidence.md` — the structured-evidence substrate this procedure consumes.
- `docs/plans/architecture-simplification-tranche-d-risk-tiered-verification.md` — the risk-tiered verification routing this procedure honors.
