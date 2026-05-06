# Architecture Simplification — Selective Gate-Relaxation Policy

**Date:** 2026-05-05
**Parent plan:** `docs/plans/archive/architecture-simplification.md` (Tranche 1.5 of the Build Doctrine roadmap — closed 2026-05-05)
**Status:** SUPERSEDED — parent plan closed 2026-05-05; relaxation expired with it.

## Status note (2026-05-05)

This policy was scoped to Tranche 1.5 work. With the parent plan closed
(commits `03f2a8e` for Tranches A-G + parent + GAP-17, then `33d2c54` for
Tranche F), the relaxation no longer applies — there is no longer in-flight
work matching the policy's scope-prefix criteria.

Standard gate behavior is restored automatically via the path-prefix checks
each gate performs; no harness change is required. The policy is preserved
here for future reference: if a similar architecture-redesign tranche is
opened later, this document is the template for selectively relaxing
disproportionate gates.

## Why this policy exists

Tranche 1.5 is the harness redesign. The redesign builds the structural foundation that will let verification become lightweight. While the redesign itself is in progress, the harness's existing heavy verification stack would slow the redesign work — exactly the over-engineered behavior the redesign is eliminating. Without selective relaxation, we are trying to build the simpler future from inside the over-engineered present, paying the full overhead on every commit.

This policy specifies which gates STAY ON during Tranche 1.5 and which TEMPORARILY EXEMPT for work landing under architecture-simplification slugs.

## Scope of relaxation

Relaxation applies to commits whose staged file paths fall under any of:

- `docs/plans/architecture-simplification*` (the parent plan + all sub-tranche child plans + their evidence files)
- `docs/decisions/026-harness-catches-up-to-doctrine.md` (the establishing ADR)
- Any file modified by a sub-tranche of Tranche 1.5 (per the sub-tranche's own `## Files to Modify/Create` declaration)

Relaxation does NOT apply to:

- Any other harness-dev plan work
- Any product-application code
- Any commit that does not have a Tranche 1.5 plan-file slug in scope

In other words: relaxation is keyed off the active plan's slug, not a global toggle.

## Gates that STAY ON (load-bearing)

These gates protect against real damage and continue to fire on Tranche 1.5 work without exemption. They are the floor below which we do not relax:

| Gate | Why it stays |
|---|---|
| `pre-commit-tdd-gate.sh` (5 layers) | Catches actual code regressions: missing tests, mock-bans, trivial-assertion-bans, silent-skip detection. Not redundant with the redesign; orthogonal protection. |
| `harness-hygiene-scan.sh` | Prevents codename / credential / personal-identifier leakage. Mechanical denylist + heuristic-cluster check. The redesign does not produce content that would legitimately violate hygiene; if a Tranche 1.5 commit triggers this, fix the content, not the gate. |
| Pre-push credential scanner | Last-line defense against credential exposure. Always on. |
| Force-push + `--no-verify` blocker | Prevents history rewrite + hook bypass. Always on. |
| `plan-edit-validator.sh` | Lightweight evidence-file freshness check on plan-file edits. Already mechanical (no LLM); minimal overhead; protects against unauthorized checkbox flips. |
| `pre-stop-verifier.sh` | Catches plans stranded ACTIVE at session end. Cheap; protects against the exact failure mode Tranche 1.5 is preventing structurally. |
| `scope-enforcement-gate.sh` | Ensures Tranche 1.5 commits stay in scope of their plans. Without this, scope drift erases the audit trail. The plan's `## Files to Modify/Create` and `## In-flight scope updates` sections cover legitimate work; out-of-scope work is genuinely a problem. |
| `decisions-index-gate.sh` | Atomicity check on ADR + index landings. ADR 026 already shipped; subsequent Tranche 1.5 ADRs benefit from this. |
| `backlog-plan-atomicity.sh` | Ensures backlog reconciliation at plan creation. Tranche 1.5 sub-tranches absorb no backlog items (per parent plan header), so this is a no-op for most sub-tranches. |
| `prd-validity-gate.sh` + `spec-freeze-gate.sh` | The Tranche 1.5 plan declares `prd-ref: docs/build-doctrine-roadmap.md` (the PRD-equivalent for harness-dev work) and `frozen: true`. These gates fire normally and confirm the spec discipline. |

## Gates that TEMPORARILY EXEMPT for Tranche 1.5 work

These gates would otherwise add overhead disproportionate to Tranche 1.5's pure-structural-redesign work. Each is exempted only for commits whose scope is Tranche 1.5; for other harness work they continue to fire. Each exemption is auditable via the path-prefix check the gate performs.

### Closure-validator (`plan-closure-validator.sh`, shipped today)

**Relaxation:** for `docs/plans/architecture-simplification*` plans, the closure-validator's 5-precondition check is **advisory rather than blocking**. The validator still emits its check output to stderr, but exits 0 on Tranche 1.5 plan closures even if some preconditions are unmet.

**Why:** the closure-validator is itself tagged-for-retirement during Tranche F. Its preconditions are designed for the heavy-verification regime; under Tranche 1.5's lighter regime (mechanical evidence, single deterministic procedure), some preconditions become obsolete (e.g., per-task evidence blocks with `Verdict: PASS` are replaced by single mechanical-evidence blocks per plan). Forcing the obsolete preconditions on the redesign that's eliminating them is circular friction.

**Implementation:** the validator already supports path-shape exemption patterns (per the `is_path_shape_exempt()` we extended for build-doctrine). Tranche A or E will add the architecture-simplification path prefix to the exemption list. Until then, manual `--no-verify` is authorized for Tranche 1.5 plan closures with explicit rationale logged in commit messages — but ONLY for Tranche 1.5 work, and ONLY when the closure-validator is the specific blocker.

### task-verifier mandate for `Verification: mechanical` tasks

**Relaxation:** when Tranche D ships (`Verification: mechanical | full | contract` per-task field in plan template), tasks with `Verification: mechanical` skip the full task-verifier agent dispatch. They run a deterministic bash check instead. Until Tranche D ships, Tranche 1.5 sub-tranche tasks default to lightweight evidence (mechanical citation per task: commit SHA, files modified, self-test result if applicable).

**Why:** the task-verifier full mandate is the largest single source of closure overhead. Most Tranche 1.5 tasks are mechanical (file edits, hook updates, prompt updates) and don't need adversarial LLM verification. Forcing the full mandate on these tasks IS the over-engineering being eliminated.

### Comprehension gate (R2+ articulation)

**Relaxation:** Tranche 1.5 sub-tranche plans declare `rung: 1` where appropriate (most are mechanical work and don't need R2+ comprehension articulation). The parent plan declares `rung: 3` because it spans multi-component coordination, but its closure happens via the deterministic procedure (Tranche E) that doesn't trigger the comprehension gate.

**Why:** comprehension gate is for builder mental-model verification on R2+ tasks. Most Tranche 1.5 work is mechanical-rung; sub-tranches that genuinely involve R2+ judgment (e.g., the work-shape library design choices) include the articulation discipline naturally.

### Adversarial-review agents (claim-reviewer, end-user-advocate, code-reviewer for harness-dev)

**Relaxation:** harness-dev plans are `acceptance-exempt: true` already, so end-user-advocate is a no-op. claim-reviewer is self-invoked and remains a discipline. code-reviewer remains available on demand for sub-tranches that touch substantive code (e.g., Tranche E's deterministic close-plan procedure). Default: do NOT spawn adversarial reviewers for routine mechanical sub-tranches.

**Why:** adversarial review is calibrated for product-user-facing work where "what would a user reasonably try?" is the load-bearing question. For pure-harness mechanical refactors, the adversarial dimension is low.

## How exemptions are recorded

Every commit that uses an exemption from this policy:

1. Lists the exemption used in the commit message (one line, e.g., `Closure-validator advisory mode used for Tranche 1.5 plan closure`).
2. References this policy doc (so audit trails can find the rationale).
3. Stays within the Tranche 1.5 scope (path-prefix check on staged files).

Logged exemption usage feeds into Tranche F's failsafe audit. If a gate is consistently exempted across many Tranche 1.5 commits without observable harm, that's strong evidence for the gate's RETIRE candidacy.

## When relaxation expires

Relaxation expires automatically when Tranche 1.5's parent plan flips to Status: COMPLETED. After that, the harness operates under the new structure (lightweight default + heavy on risk per Tranche D's classification, deterministic close-plan per Tranche E, retired failsafes per Tranche F). The relaxation policy is no longer needed because the underlying overhead is gone.

If Tranche 1.5 is DEFERRED or ABANDONED, the relaxation also expires. Sub-tranches in flight at the time inherit the expiration.

## Accountability

The selective relaxation is a deliberate tradeoff: short-term flexibility on a defined scope to enable a redesign that eliminates the long-term overhead. It is NOT:

- A general loosening of harness discipline
- A permission slip for unrelated harness-dev work
- An indefinite escape hatch
- A tool to dodge legitimate gate findings

If a Tranche 1.5 commit triggers a gate that turns out to surface a real issue (not the over-engineering pattern), the appropriate response is to fix the underlying issue, not exempt further. The exemptions exist to remove circular friction, not to remove protection.

## Cross-references

- **Parent plan:** `docs/plans/architecture-simplification.md` — Tranche 1.5 of the Build Doctrine roadmap
- **Establishing ADR:** `docs/decisions/026-harness-catches-up-to-doctrine.md`
- **Discovery:** `docs/discoveries/2026-05-05-verification-overhead-vs-structural-foundation.md`
- **Integration review:** `docs/reviews/2026-05-05-discovery-vs-build-doctrine-integration.md`
- **Roadmap:** `docs/build-doctrine-roadmap.md` — Tranche 1.5 row
- **Existing exemption pattern:** `adapters/claude-code/hooks/harness-hygiene-scan.sh` `is_path_shape_exempt()` — same shape this policy uses, just keyed off plan-slug rather than path-shape
