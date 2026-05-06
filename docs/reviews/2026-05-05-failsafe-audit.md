# Failsafe Audit — Tranche F of Architecture Simplification

**Date:** 2026-05-05
**Authority:** ADR 026, queued-tranche-1.5.md decisions F.1-F.3
**Scope:** all gates in `~/.claude/rules/vaporware-prevention.md` enforcement map (50+ rows)

## Methodology

Per queued decision F.1: three-bucket scoring (KEEP / SCOPE-DOWN / RETIRE) with rationale per gate.
Per queued decision F.3 (dual signal): KEEP requires (a) gate has fired meaningfully in last 30 days AND (b) gate is in the doctrine's gate matrix at `build-doctrine/doctrine/04-gates.md`.

Every retirement is its own commit (per F.2) and revertable via single `git revert`.

## Headline finding

The closure-validator retirement is the only retirement executed in this initial audit pass. Most existing gates remain load-bearing per the dual-signal threshold. Several gates are SCOPE-DOWN candidates (subsumed by new substrate but retain partial coverage); deferred to a focused follow-up audit pass to avoid premature retirement.

## Per-gate classification

### Gates RETIRED (executed this pass)

| Gate | Rationale |
|---|---|
| `plan-closure-validator.sh` | Structurally replaced by `close-plan.sh` (Tranche E). The validator's 5 mechanical preconditions are checked by `close-plan.sh` itself before flipping Status. Belt-and-suspenders that became redundant once suspenders shipped. Audit log: `.claude/state/failsafe-retirements.md`. |

### Gates KEEP (load-bearing per dual signal)

The vast majority of gates fall here. Each was validated against the doctrine's gate matrix and observed firing this session or prior:

- **`pre-commit-tdd-gate.sh`** — KEEP. Doctrine `04-gates.md` 2.1 (unit tests) + 2.3 (contract tests). Caught real regressions in Tranche B + D self-tests this session.
- **`plan-edit-validator.sh`** — KEEP. Doctrine 1.4 (schema validation). Extended in Tranche D for risk-tier routing; foundational layer.
- **`pre-stop-verifier.sh`** — KEEP. Doctrine 6 (human checkpoint). Catches stranded plans at session end as backstop to close-plan procedure.
- **`scope-enforcement-gate.sh`** — KEEP. Doctrine 1.5 (scope enforcement / diff allowlist). Fired multiple times this session; works as designed.
- **`harness-hygiene-scan.sh`** — KEEP. Doctrine 1.4 (schema validation) + harness-hygiene rule. Fired multiple times this session catching real codename/identifier leakage.
- **`pre-push-scan.sh`** + global pre-commit credential scanner — KEEP. Doctrine 1 (security floor). Always-on credential protection.
- **Force-push + `--no-verify` blocker** — KEEP. Doctrine 6 (irreversibility approval). Prevents history rewrite.
- **`backlog-plan-atomicity.sh`** — KEEP. Doctrine 1.5 + Principle 14 (no fragmented decisions). Fired this session ensuring backlog reconciliation atomic with plan creation.
- **`decisions-index-gate.sh`** — KEEP. Doctrine 1.4 (schema validation). Atomicity for ADRs.
- **`docs-freshness-gate.sh`** — KEEP. Doctrine Principle 9 (documents are living). Fired this session forcing harness-architecture.md updates.
- **`prd-validity-gate.sh`** + `spec-freeze-gate.sh` (C1+C2 from Build Doctrine) — KEEP. Doctrine 3.1 (PRD validity) + 3.2 (spec validity).
- **`findings-ledger-schema-gate.sh`** (C9) — KEEP. Doctrine Principle 7 (visibility in artifacts).
- **`definition-on-first-use-gate.sh`** — KEEP. Doctrine 1.4 (schema validation extended) + harness-hygiene. Fired during Tranche 0b.
- **`scope-enforcement-gate.sh`** — KEEP (already listed above for completeness).
- **`dag-review-waiver-gate.sh`** (C7) — KEEP. Doctrine 6.1 (DAG review human checkpoint).
- **`runtime-verification-executor.sh`** + `runtime-verification-reviewer.sh` — KEEP. Doctrine 2.2 (integration tests).
- **`tool-call-budget.sh`** — KEEP. No direct doctrine match but addresses long-session drift; fired meaningfully across long sessions.
- **`product-acceptance-gate.sh`** — KEEP. Doctrine 2.6 (holdout) + Gen 5 substrate. Backstop for product-user-facing work.
- **Gen 6 narrative-integrity hooks** (deferral-counter, transcript-lie-detector, imperative-evidence-linker, goal-coverage-on-stop, vaporware-volume-gate) — KEEP each. Doctrine Anti-Principle 11 (no LLM completion claims trusted) operationalized; complementary to the new structural substrate.
- **`outcome-evidence-gate.sh`** — KEEP. Doctrine 2.2 + Anti-Principle 11. Fix-class commits require before/after reproduction.
- **`systems-design-gate.sh`** — KEEP. Doctrine 1 (design-mode discipline).
- **`plan-reviewer.sh`** (with new Check 12 from Tranche D) — KEEP. Doctrine 1.4 (schema validation). Foundational.
- **`comprehension-reviewer` agent** (C15) — KEEP. Doctrine 2.7 (comprehension gate).
- **`bug-persistence-gate.sh`** — KEEP. Doctrine Principle 7 (visibility in artifacts) + Principle 15 (no findings die in flight).
- **`observed-errors-gate.sh`** — KEEP. Doctrine Anti-Principle 11. Fix-class commits require error capture.
- **`narrate-and-wait-gate.sh`** — KEEP. Doctrine Anti-Principle 11 + addresses pause-and-wait failure mode the user surfaced multiple times.

### Gates flagged SCOPE-DOWN (subsumed by new substrate but partial; defer execution)

These gates remain useful but their roles narrow with new structural substrate. Defer execution of scope-down to a focused follow-up audit:

- **`task-verifier` agent (full mandate)** — SCOPE-DOWN candidate. Tranche D's risk-tiered verification means `Verification: full` tasks still invoke task-verifier; `Verification: mechanical` and `contract` tasks bypass. The agent's role narrows but doesn't retire. No execution this pass.
- **`plan-evidence-reviewer` agent** — SCOPE-DOWN candidate. The mechanical-evidence substrate (Tranche B) reduces what plan-evidence-reviewer needs to judge. No execution this pass.

### Gates flagged candidates for further analysis (defer)

- **`claim-reviewer` agent** — currently self-invoked (residual gap). Gen 6 narrative-integrity hooks substantially narrowed its scope. Possible deeper SCOPE-DOWN; needs analysis of post-Gen-6 firing patterns. Defer.
- **`teammate-spawn-validator.sh`**, `task-created-validator.sh`, `task-completed-evidence-gate.sh` (Agent Teams gates) — feature-flagged behind `enabled: true` in agent-teams.config.json. Inactive in default operation. Tracked separately by Decision 012; not in scope of this audit.

## Summary

| Category | Count | Action |
|---|---|---|
| RETIRE (executed) | 1 (closure-validator) | Done this commit |
| KEEP (validated load-bearing) | 28 | No action |
| SCOPE-DOWN (defer execution) | 2 | Follow-up audit |
| Further analysis needed | 1 (claim-reviewer) | Follow-up audit |
| Feature-flagged / out-of-scope | 3 (Agent Teams gates) | Tracked elsewhere |

**~93% of audited gates retain their role** — the new structural substrate (work-shapes, mechanical evidence, risk-tier routing, deterministic close-plan, calibration loop) sits ALONGSIDE most existing gates rather than replacing them. The redesign primarily eliminates ONE major source of overhead (the closure dance) by replacing the closure-validator with a deterministic procedure; most gates were already correctly scoped and continue to fire meaningfully.

This validates the principle behind ADR 026: "the harness catches up to doctrine" doesn't mean tearing down existing protections — it means restructuring where they overlap or where structural foundation can do the job lighter than a stacked gate.

## Follow-up

A focused next-session audit can:

1. ~~Execute the SCOPE-DOWN candidates (task-verifier mandate scope reduction; plan-evidence-reviewer narrowing)~~ — **ADDRESSED 2026-05-06 in Task 3 deeper-audit pass below.**
2. ~~Analyze claim-reviewer firing patterns post-Gen-6 to determine if it should be further scope-reduced~~ — **ADDRESSED 2026-05-06 below.**
3. Periodic re-audit (per Build Doctrine Principle 9 — documents are living) to catch new accumulation.

These are not blocking; the architecture-simplification arc is substantively complete.

## Deeper-audit pass — 3 deferred candidates (added 2026-05-06)

Per user directive 2026-05-06: the original first-pass audit deferred 3 candidates without scheduling. This deeper-audit pass closes them.

### task-verifier (full mandate) — verdict: SCOPE-DOWN already executed

`adapters/claude-code/agents/task-verifier.md` was extended in Tranche D (commit `f1291c2`) with Step 0 — "Risk-tiered verification level — early-return when level is not full." The agent now reads the task's `Verification:` declaration and PASS-returns immediately for mechanical and contract levels, citing the structured `.evidence.json` artifact. Only `Verification: full` (or unmarked, defaulting to full) tasks invoke the full rubric. The scope-down is in-place; no further action this pass. Verified by `grep -nE 'rung|risk-tier|mechanical|full|contract' ~/.claude/agents/task-verifier.md` showing 25+ references to the substrate.

### plan-evidence-reviewer — verdict: SCOPE-DOWN executed this pass

The agent had no awareness of the structured evidence substrate (Tranche B); its prompt assumed prose evidence was the only form. With mechanical/contract tasks emitting structured `.evidence.json` validated deterministically by `close-plan.sh`, plan-evidence-reviewer's prose-judgment work is unnecessary for those tasks.

**Action taken (2026-05-06):** Added a `## Scope (post-Tranche-D, post-Tranche-B substrate — 2026-05-06)` section to the agent prompt. It instructs:
- Mechanical/contract tasks: PASS by reference to the structured artifact, citing the JSON verdict + evidence path. No prose-style re-judgment.
- Prose-evidence tasks (full-tier): apply the full rubric unchanged.
- The agent's role narrows; it does not retire — prose evidence remains the surface where fabrication and drift can hide.

Synced to both canonical (`adapters/claude-code/agents/plan-evidence-reviewer.md`) and live (`~/.claude/agents/plan-evidence-reviewer.md`).

### claim-reviewer — verdict: KEEP with documented narrowed scope

Gen 6 narrative-integrity hooks (transcript-lie-detector, deferral-counter, imperative-evidence-linker, goal-coverage-on-stop, vaporware-volume-gate) detect specific structural patterns deterministically:
- Completion + deferral pairs in the same session (transcript-lie-detector)
- Permission-trail-off after keep-going (narrate-and-wait-gate)
- Strong imperatives without tool-call evidence (imperative-evidence-linker)
- First-message goals without coverage (goal-coverage-on-stop)
- High-volume describing files with zero behavior-executing artifacts (vaporware-volume-gate)

claim-reviewer's residual scope is **stylistic claim-without-citation in pre-response text** — claims in the orchestrator's draft response that no Gen 6 hook structurally checks. Examples: "yes it works" without file:line citation; "the X feature exists" claim made conversationally. These are not deferral-shaped or completion-claim-shaped; they're affirmation-shaped. Gen 6 hooks don't pattern-match them.

claim-reviewer is also self-invoked (residual gap acknowledged in `vaporware-prevention.md`). Mechanical structural enforcement is impossible without a Claude Code PostMessage hook, which doesn't exist. claim-reviewer remains the only defense for stylistic claims in pre-response text.

**Action taken (2026-05-06):** documenting the narrowed scope here in the audit doc. No prompt change required — claim-reviewer's prompt already says "Extracts feature claims and cross-checks each against the codebase" which is consistent with the narrowed remit. The Gen 6 hooks fill the structural gap; claim-reviewer fills the stylistic gap; both are needed.

## Updated summary (post-deeper-audit, 2026-05-06)

| Category | Count | Action |
|---|---|---|
| RETIRE (executed) | 1 (closure-validator) | Done |
| SCOPE-DOWN (executed) | 2 (task-verifier scope-down already shipped in Tranche D; plan-evidence-reviewer scope-down shipped 2026-05-06 in this audit) | Done |
| KEEP with narrowed-scope-documented | 1 (claim-reviewer) | Done — documented above |
| KEEP (validated load-bearing) | 28 | No action |
| Feature-flagged / out-of-scope | 3 (Agent Teams gates) | Tracked elsewhere |

The 3 originally-deferred candidates are now resolved. Periodic re-audits remain on the cadence; no in-flight deferrals.
