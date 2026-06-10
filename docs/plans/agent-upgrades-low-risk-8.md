# Plan: agent-upgrades-low-risk-8 — apply the 8 APPLY-LOW-RISK agent-prompt upgrades
Status: ACTIVE
Execution Mode: orchestrator
Mode: code
Backlog items absorbed: none
acceptance-exempt: true
acceptance-exempt-reason: Harness-internal agent-prompt upgrades (sub-agent .md files only); no product UI or runtime to advocate for — the "user" is the maintainer dispatching these agents, and the verification is structural (frontmatter parses, headline changes present, golden evals green).
tier: 2
rung: 1
architecture: coding-harness
frozen: true
prd-ref: n/a — harness-development

## Goal
Apply the 8 agent-upgrade proposals risk-tiered as APPLY-LOW-RISK in `workstreams-coordination/AGENT-UPGRADE-DIGEST-2026-06-09.md`, per Misha's D3 approval on 2026-06-10 ("Apply the 8 low risk"). Each proposal at `docs/reviews/agent-upgrades/2026-06-05-<agent>.md` (main-checkout working tree) carries a drop-in agent file already reviewed for risk; this plan applies them EXACTLY as proposed — no re-design — preserving each agent's frontmatter/tool grants except where the proposal explicitly changes them (research +rg/git-blame/git-grep; code-reviewer +git-blame; test-writer +Bash).

## User-facing Outcome
The maintainer's 8 advisory agents (explorer, research, audience-content-reviewer, security-reviewer, ux-ia-auditor, functionality-auditor, code-reviewer, test-writer) carry named methodologies, calibration disciplines, and harness-convention conformance (PROVEN/HYPOTHESIZED, class-aware findings, Dispatch-conditional AskUserQuestion) on their next dispatch.

## Scope
- IN: the 8 agent prompt files under `adapters/claude-code/agents/` named in Files to Modify/Create; live-mirror sync to `~/.claude/agents/`; digest-row updates in the workstreams-coordination repo (separate repo, separate commit).
- OUT: the 12 APPLY-WITH-WATCH and 4 NEEDS-MISHA proposals (Misha reviews those himself — explicitly not touched); any hook, rule, template, or settings change; any re-design of proposal content.

## Tasks

- [ ] 1. Apply all 8 APPLY-LOW-RISK proposals to their agent files exactly as proposed; verify frontmatter integrity + headline-change greps + golden evals; note any minimal reconciliations. — Verification: mechanical

## Files to Modify/Create
- `adapters/claude-code/agents/explorer.md` — breadth→narrow→confirm methodology, tool ladder, FOUND/PARTIAL/NOT-FOUND calibration, output contract
- `adapters/claude-code/agents/research.md` — 5-phase methodology, effort ladder, source-reliability ranking, PROVEN/HYPOTHESIZED; +rg/git-blame/git-grep tools
- `adapters/claude-code/agents/audience-content-reviewer.md` — named rubrics (Federal PL, FK/Fog, NN/g), class-aware findings, Dispatch-conditional AskUserQuestion bug fix
- `adapters/claude-code/agents/security-reviewer.md` — OWASP/CWE/STRIDE anchoring, confirmation-bias defense, exploitability triage
- `adapters/claude-code/agents/ux-ia-auditor.md` — Morville four-systems IA canon incl. Search, foraging/scent, Nielsen 0–4, two gulfs
- `adapters/claude-code/agents/functionality-auditor.md` — soundness asymmetry, reachable-set model, DEAD-FLAG-BRANCH verdict, class sweeps, reversibility grading
- `adapters/claude-code/agents/code-reviewer.md` — Google D1–D9 priority ladder, OWASP expansion, hallucination guard, severity×confidence; +git-blame tool
- `adapters/claude-code/agents/test-writer.md` — +Bash grant (run-and-prove-it-can-fail), ECP/BVA/property/metamorphic, no-mock-the-SUT hardened
- `docs/plans/agent-upgrades-low-risk-8.md` — this plan

## In-flight scope updates
(no in-flight changes yet)

## Assumptions
- The digest's risk-clearance stands in for per-proposal re-review; proposals are applied verbatim per Misha's directive, with only minimal reconciliation where a proposal's internal references are inconsistent.
- No hook or gate greps these 8 agents' body text mechanically (verified: no hooks/evals reference "Counter-Incentive" or agent body strings; the hook-parsed contracts named in the digest's cross-cutting note belong to task-verifier / plan-evidence-reviewer / end-user-advocate — none of which are in this set).

## Edge Cases
- A proposal conflicting with a current file changed since 2026-06-05 → reconcile minimally and note it (occurred once: functionality-auditor's "Framework 0" internal reference had no matching section label; replaced with "the reachable-set model").
- Frontmatter format drift between proposal and current file (allowed-tools vs tools list) → preserve the current file's field style unless the proposal explicitly changes grants (did not occur; all 8 proposals matched current field styles).

## Acceptance Scenarios
- n/a — acceptance-exempt harness-internal work; structural verification is the acceptance artifact.

## Out-of-scope scenarios
- n/a — no product-user scenarios exist for agent prompt files.

## Testing Strategy
- Frontmatter integrity check per file (opening/closing `---`, `name:` present).
- Headline-change grep per agent (each proposal's signature addition present in the applied file).
- `evals/golden/rules-index-coverage.sh` green (no rules-side regression).
- Live-mirror sync verified byte-identical via `diff -q` per file after merge.

## Walking Skeleton
n/a — single mechanical task applying pre-reviewed drop-in files; no novel architecture.

## Decisions Log
- 2026-06-10: functionality-auditor proposal internally referenced "Framework 0" (a label it never assigns to its reachable-set section); applied with the two references reworded to "the reachable-set model". Tier 1 — trivially reversible, content-preserving.

## Definition of Done
- [ ] All 8 agent files updated + verified, merged to master, live mirror synced byte-identical, digest rows marked APPLIED with the merge SHA.
