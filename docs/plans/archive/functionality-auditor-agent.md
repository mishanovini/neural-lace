# Plan: functionality-auditor agent

Status: COMPLETED
Execution Mode: orchestrator
Mode: code
Backlog items absorbed: none
acceptance-exempt: true
acceptance-exempt-reason: harness-internal work — a new sub-agent prompt + arch-doc row; the agent has no user-observable runtime surface. Its acceptance artifact is the three-case validation run against a live codebase (DRY catch, drift candidate, Chesterton's-fence true-negative), reported in the PR body and the orchestrator-prime outbox.
tier: 1
rung: 0
architecture: coding-harness
frozen: true
prd-ref: n/a — harness-development

## Goal
Add a best-in-class `functionality-auditor` sub-agent to the harness — an expert that judges whether a page/feature actually WORKS and STILL MAKES SENSE, complementing `ux-ia-auditor` (which owns navigation/IA/layout). The agent reasons from named disciplines (functionality-over-components, def-use/dataflow analysis, architecture-drift detection, Chesterton's Fence, DRY/divergence, PROVEN/HYPOTHESIZED calibration) rather than vague instructions, so it behaves like a true expert.

## User-facing Outcome
The maintainer can dispatch `functionality-auditor` against any shipped surface and receive a per-element table classifying every config field/control as LIVE / DEAD / STALE / NONSENSICAL-GIVEN-CURRENT-ARCHITECTURE / REDUNDANT / INTENTIONAL-LOOKS-DEAD-BUT-ISNT, each with a consumer `file:line` (or proven absence), an old-vs-new drift contrast where relevant, and a removal recommendation gated by Chesterton's-fence reasoning — catching silent-no-op settings that no test suite and no UX audit surfaces.

## Scope
- IN: the agent prompt file (canonical + `~/.claude/` mirror); the `docs/harness-architecture.md` agent-table row; this plan file.
- OUT: any change to other agents, hooks, rules, or settings wiring; any audit of an actual product surface (validation is performed read-only, not committed here); the live `~/.claude/settings.json` (agents need no settings wiring).

## Tasks
- [x] 1. Author `functionality-auditor.md` grounded in the 7 frameworks + 6-verdict taxonomy + 8-phase methodology + per-element output + worked example; mirror to `~/.claude/agents/`; add the arch-doc row; validate against a live codebase (3 cases). — Verification: mechanical

## Files to Modify/Create
- `adapters/claude-code/agents/functionality-auditor.md` — new sub-agent prompt (canonical).
- `docs/harness-architecture.md` — add the functionality-auditor row to the agent table.
- `docs/plans/functionality-auditor-agent.md` — this plan.

## In-flight scope updates
(none)

## Assumptions
- The `~/.claude/agents/` mirror is kept byte-identical to the canonical via `cp` (Windows install copies, not symlinks).
- Sub-agents inherit the harness's default model; no `model:` frontmatter is needed.
- Agent-prompt changes have no executable runtime; "acceptance" for harness agents is the validation trace, not a browser run.

## Edge Cases
- Naive grep-based "unused" detection produces false positives (dynamic dispatch, config-object access, cross-repo consumers); the agent's Chesterton's-fence pass + indirect-consumption checklist exist specifically to prevent recommending removal of live functionality.
- A field can be LIVE yet still wrong to keep (architecture drift); the agent separates "has a consumer" from "still fits the current model."
- Partial drift (live for legacy code paths, inert for migrated ones) must be reported as partial, not as fully-dead.

## Testing Strategy
Validate the agent's expertise against a live codebase (read-only) with three cases, each PROVEN by direct reads per `claims.md`: (a) catches a DRY/divergence pair (same config in two stores kept in sync only by app-level mirror code); (b) identifies an AI-config element redundant/nonsensical given the current conversation/state-card architecture, with explicit old-vs-new; (c) correctly does NOT flag a live-but-indirectly-consumed setting as dead, citing the indirect consumer. Results reported in the PR body + outbox JSON.

## Walking Skeleton
The thinnest end-to-end slice: a single agent markdown file whose frontmatter `name` matches its filename, mirrored byte-identically, discoverable in the arch-doc agent table — i.e. the agent is dispatchable via the Task tool and its methodology survives a real three-case validation. No partial scaffolding; the agent is complete on first landing.

## Decisions Log
- Validation cases chosen for distinctness (three different fields, three different verdicts) so the proof exercises DRY-detection, drift-detection, and Chesterton's-fence calibration independently. The richest drift example (a free-text guidance field bypassed by the new template path for migrated states) is used as the agent's internal worked example, genericized to avoid shipping a downstream product's identifiers (harness-hygiene).

## Pre-Submission Audit
- S1 (Entry-Point Surfacing): n/a — single-task harness-infra plan.
- S2 (Existing-Code-Claim Verification): all three validation citations PROVEN by direct reads (grep + file reads), not from memory or a sub-agent's unverified report.
- S3 (Cross-Section Consistency): n/a — single artifact.
- S4 (Numeric-Parameter Sweep): n/a — no numeric parameters.
- S5 (Scope-vs-Analysis Check): swept — every IN item is a harness-kit path; no product-code prescriptions.

## Definition of Done
- [ ] Agent file authored + mirrored byte-identical + clean of project identifiers (harness-hygiene).
- [ ] Arch-doc agent row added.
- [ ] Three-case validation PROVEN and reported.
- [x] Committed to neural-lace via PR (merge-on-green); outbox JSON written.

## Completion Report

### 1. Implementation Summary
Task 1 shipped in full: `adapters/claude-code/agents/functionality-auditor.md` authored (239 lines, grounded in the 7 named frameworks), mirrored byte-identical to `~/.claude/agents/`, arch-doc agent row added. Shipped via PR #56, merged to master (merge sha `21c6424`). No backlog items absorbed.

### 2. Design Decisions & Plan Deviations
None from the approved scope. The richest architecture-drift example discovered during validation (a free-text guidance field bypassed by the new template path for migrated states) was genericized into the agent's internal worked example rather than shipped with the source product's identifiers (harness-hygiene). The bootstrap plan itself was created to satisfy `scope-enforcement-gate` (three unrelated plans were ACTIVE); per gate Option 2 (genuinely-separate work → new plan).

### 3. Known Issues & Gotchas
The agent is a prompt artifact with no executable runtime; its "acceptance" is the validation trace, not a browser run (hence `acceptance-exempt`). No hook enforces the agent's own methodology at runtime — it is invoked on demand via the Task tool, like its sibling `ux-ia-auditor`.

### 4. Manual Steps Required
None. Live `~/.claude/agents/` mirror already synced byte-identical; agents need no `settings.json` wiring.

### 5. Testing Performed & Recommended
Three validation cases, each PROVEN by direct reads against a live codebase (read-only): (a) DRY/divergence caught, (b) architecture-drift candidate found with old-vs-new, (c) Chesterton's-fence true-negative correctly kept (indirect consumer cited). `harness-hygiene-scan` clean; canonical↔mirror byte-identical; all 11 CI checks green pre-merge. Recommended next: dispatch the agent on a real product surface for a full audit once Misha has reviewed the agent prompt.

### 6. Cost Estimates
None — a documentation/prompt artifact; no new services, APIs, or recurring costs.
