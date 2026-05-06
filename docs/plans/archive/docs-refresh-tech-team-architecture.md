<!-- scaffold-created: 2026-05-06T09:59:37Z by start-plan.sh slug=docs-refresh-tech-team-architecture -->
# Plan: Docs Refresh — Tech-Team Architecture Narrative

Status: COMPLETED
Execution Mode: orchestrator
Mode: code
Backlog items absorbed: none
acceptance-exempt: true
acceptance-exempt-reason: Documentation-only plan; no product user. Verification is via doc-substance review against the principles authored in Task 1, plus link-validity and freshness markers.
tier: 1
rung: 1
architecture: coding-harness
frozen: false
prd-ref: n/a — harness-development

## Goal

Refresh the user-facing documentation to (a) reflect the architectural state after Generation 4-6 + Build Doctrine integration + Tranche 1.5 architecture-simplification, and (b) make the harness's structure intelligible to a fresh reader. Three deliverables:

1. **`docs/doc-writing-patterns.md`** — codified substrate. The 10 principles (audience layering, single source of truth, examples-first, update-on-ship, staleness markers, cold-test, index→detail, scope honesty, reader-question organization, load-bearing visuals) plus concrete examples drawn from this repo. Becomes the doctrine doc that any future doc work follows.

2. **README rewrite** — full restructure. Compressed forms of the team-role analogy + layered architectures + end-to-end flow surface at the front-door level. Architecture and Directory Structure sections updated for current scripts/agents/hooks. New scripts (`close-plan.sh`, `state-summary.sh`, `session-wrap.sh`, `start-plan.sh`, `write-evidence.sh`) and `~/.claude/work-shapes/` shown.

3. **`docs/architecture-overview.md`** — full unified narrative for the deep reader. All 19 agents mapped to tech-team roles; three layer systems (L0/L1/L2/L3 + Generation 1-6 + ADR-027 Layer 1-5) cross-walked; end-to-end product-delivery flow expanded with per-step agent invocations and gating hooks; filesystem map.

User-observable outcome: a fresh reader hitting the GitHub repo can grasp the architectural shape in 5 minutes via README, then ramp to the deep architectural understanding in 15 minutes via architecture-overview.md, with the substrate doc explaining the patterns those refreshes follow.

## Scope

- IN:
  - New file: `docs/doc-writing-patterns.md` (~250-350 lines, doctrine-doc shape)
  - Full rewrite: `README.md` (target ~280-350 lines; current is ~265 lines but restructured)
  - New file: `docs/architecture-overview.md` (~500-700 lines, the unified narrative)
  - Update: `docs/harness-architecture.md` "Last updated" sticky note + cross-link to architecture-overview.md
  - Update: `docs/harness-strategy.md` cross-link to architecture-overview.md (the Layer Model section becomes one of the cross-walked layer systems)
- OUT:
  - Rewriting `docs/best-practices.md`, `docs/agent-incentive-map.md`, `docs/build-doctrine-roadmap.md` — those are catalog docs; they get linked from the architecture-overview but not restructured
  - Per-agent prompt rewrites (the agent files themselves) — separate concern
  - New visual assets (PNG diagrams) — Markdown ASCII / table visuals only for v1
  - Doc-update integration into `close-plan.sh` (mentioned as a follow-up; not built here)
  - `/refresh-readme` skill (mentioned as a follow-up; not built here)
  - A "tech writer" agent — explicitly rejected per harness-tier-F retirement spirit; the patterns doc is the substrate instead

## Tasks

- [ ] 1. Author `docs/doc-writing-patterns.md` (~250-350 lines). Codifies the 10 principles plus concrete examples drawn from this repo's existing docs (good and bad cases). Becomes the substrate Tasks 2 and 3 follow. — Verification: mechanical
- [ ] 2. Rewrite `README.md`. Restructure following the patterns. New sections: top-level "How the harness is structured" (compressed team-role table + layered-architectures-as-shape + end-to-end flow). Updated sections: Architecture diagram, Directory Structure (new scripts + work-shapes), Best Practices (link to deep doc instead of inline), How It Works (refreshed for current state). Targets fresh-reader and skimming-collaborator audiences. — Verification: full
- [ ] 3. Author `docs/architecture-overview.md` (~500-700 lines). Sections: I. Team-role analogy (full mapping of 19 agents + orchestrator + key hooks to tech-team roles), II. End-to-end product-delivery flow (a feature shipping through the team, per-step expanded), III. Layered architectures cross-walked (L0/L1/L2/L3 + Generation 1-6 + ADR-027 Layer 1-5 shown together with each system's question), IV. Where everything lives (filesystem map). — Verification: full
- [ ] 4. Update `docs/harness-architecture.md` and `docs/harness-strategy.md` cross-links. Update the harness-architecture.md "Last updated" sticky note to today's date with a one-line summary. Both docs gain a "See also: docs/architecture-overview.md for the unified narrative" pointer. — Verification: mechanical
- [ ] 5. Cold-test the README. Have a subagent (research subagent) walk through the README and architecture-overview as a fresh reader, surface confusion points, fix any gaps. — Verification: full

## Files to Modify/Create

- `docs/doc-writing-patterns.md` — NEW (~250-350 lines)
- `README.md` — REWRITE (current ~265 lines → ~280-350 lines, restructured)
- `docs/architecture-overview.md` — NEW (~500-700 lines)
- `docs/harness-architecture.md` — MODIFY (sticky note refresh + cross-link, ~5 lines changed)
- `docs/harness-strategy.md` — MODIFY (cross-link addition, ~3 lines changed)

## In-flight scope updates

- 2026-05-06: `docs/decisions/queued-docs-refresh-tech-team-architecture.md` — auto-created by `start-plan.sh` alongside the plan file; bookkeeping artifact for queued decisions awaiting user override.

## Assumptions

- The user's audience is "you + collaborators + fresh adopters" (assumed from the harness's two-layer-config + hygiene-scanner shape). If this is wrong, the README compression level should be revisited.
- The 19 agents in `adapters/claude-code/agents/` are the current set (verified 2026-05-06 via `ls`); no agent files added or removed during this work.
- The Layer Model in `harness-strategy.md` is the canonical L0/L1/L2/L3 statement; we link to it rather than re-author.
- The ADR-027 Layer 1-5 model is documented in `docs/decisions/027-*` (or similar); we cross-reference from architecture-overview.md.
- The Generation 1-6 enforcement evolution is documented in `harness-architecture.md` and `vaporware-prevention.md`; we summarize for cross-walk in architecture-overview.md, not re-enumerate.

## Edge Cases

- **Patterns doc disagrees with existing best-practices.md.** If a principle in the new patterns doc contradicts something in `docs/best-practices.md`, the patterns doc is for doc-writing specifically while best-practices.md covers everything; both can coexist. Cross-reference where they touch.
- **README ends up too long anyway.** If the rewritten README pushes past ~400 lines, ruthlessly compress and push more depth to architecture-overview.md. Don't let "everything in one place" win over "front door is short."
- **Architecture-overview.md duplicates harness-architecture.md content.** Risk of two docs covering the same ground. Mitigation: harness-architecture.md is the catalog (Hooks list, Agents list, Rules list, exhaustive); architecture-overview.md is the narrative (team-role map, end-to-end flow, layered cross-walk). Different scopes; explicit "you are here" pointers prevent overlap.
- **Cold-test finds substantive gaps.** If Task 5 surfaces real confusion points that require structural changes, log via discovery file rather than silently rewriting; surface for user input.

## Acceptance Scenarios

n/a — `acceptance-exempt: true` (documentation-only plan with no product user; no runtime browser verification possible).

## Out-of-scope scenarios

n/a

## Testing Strategy

- **Task 1 (patterns doc):** Verification: mechanical. Check (a) file exists at `docs/doc-writing-patterns.md`, (b) length within 250-350 lines, (c) all 10 principles named (grep), (d) cross-references to existing docs are link-valid (no 404s within repo).
- **Task 2 (README rewrite):** Verification: full. Check (a) all required README sections present, (b) team-role analogy and layered-architecture-as-shape visible at top level, (c) directory structure updated for current scripts (close-plan, state-summary, session-wrap, start-plan, write-evidence + work-shapes/), (d) link to architecture-overview.md present, (e) link-validity (no 404s), (f) line count ≤ 400.
- **Task 3 (architecture-overview):** Verification: full. Check (a) all four sections present (team-role, end-to-end flow, layered cross-walk, filesystem map), (b) all 19 current agents mapped to roles, (c) all three layer systems shown together with each system's question, (d) end-to-end flow walks at least one concrete example, (e) link-validity.
- **Task 4 (cross-links):** Verification: mechanical. grep that both `harness-architecture.md` and `harness-strategy.md` reference `architecture-overview.md`.
- **Task 5 (cold test):** Verification: full. Subagent reports specific confusion points; each gets a doc-fix or a surfaced discovery.

## Walking Skeleton

n/a — pure documentation work; no runtime layers to slice through.

## Decisions Log

### Decision: Separated structure (compressed README + dedicated architecture-overview.md)
- **Tier:** 1 (reversible — content can be folded into README later if separation proves over-engineered)
- **Surfaced to user:** 2026-05-06 in this conversation
- **Status:** chosen by orchestrator based on stated reasoning
- **Chosen:** Compressed forms of team-role analogy / layered architectures / end-to-end flow at README level; full mapping + deep cross-walk + per-step expansion in architecture-overview.md. Strong README→architecture-overview link.
- **Alternatives:** Fold everything into README (~600+ line README); skip architecture-overview entirely.
- **Reasoning:** README has to serve four audiences (skim-reader / first-time installer / fresh adopter / maintainer). Folding the deep architecture doc in crowds out install/quick-start/security and forces all audiences to wade. Separated structure lets each audience tier get what it needs. Per principle #1 (audience layering / progressive disclosure) and principle #2 (single source of truth — README is index) of the patterns doc landing in Task 1.
- **To reverse:** delete `docs/architecture-overview.md`; merge its content into README. Cost: ~30-60 minutes.

### Decision: No new "tech writer" agent for v1 — patterns doc as substrate, agent reversibly deferred
- **Tier:** 1 (reversible — agent can be added later if patterns prove insufficient)
- **Surfaced to user:** 2026-05-06 in this conversation
- **Status:** chosen by orchestrator based on revised reasoning after user correction
- **Chosen:** Build `docs/doc-writing-patterns.md` as the universal substrate. Use it via carefully-crafted dispatch prompts (or inline writing) to produce the README + architecture-overview. No new agent in v1.
- **Alternatives:** Build a `tech-writer` agent that bakes in the substrate + audience perspective; dispatch it for doc work.
- **Reasoning (corrected):** my earlier reasoning conflated "failsafe" (a mechanism that backstops missing discipline) with "job" (a role producing primary work). User correctly pointed out the Tranche F retirement spirit applies to failsafes, not jobs. A tech-writer agent IS a job — it produces docs when dispatched, not when the orchestrator forgets something. So the Tranche F objection doesn't apply. The current decision to defer the agent is now based on a different argument: the patterns doc + careful prompts should suffice for v1; if the resulting docs read as generic-AI prose despite the substrate, the agent becomes necessary in v2. Build the lighter thing first; graduate based on evidence.
- **Public-repo context:** repo is now public (user, 2026-05-06). Audience tier mapping is firm: Tier 1 README serves public GitHub readers (highest quality bar). Tier 2-3 docs serve adopters and developers wanting depth. The quality bar for the README in particular argues for careful writing regardless of substrate; agent-vs-no-agent is about reusability for future doc work, not about whether the v1 docs need to be high-craft (they do).
- **To reverse:** create `adapters/claude-code/agents/tech-writer.md` that references `docs/doc-writing-patterns.md` and bakes in audience-tier perspective. Estimated cost: ~30-45 min for the agent file + dispatch wiring.

## Pre-Submission Audit

n/a — Mode: code plan, class-sweep audit not required (per design-mode-planning.md "When the audit doesn't apply").

## Definition of Done

- [ ] All 5 tasks task-verified PASS
- [ ] All link-validity checks pass (no 404s within repo)
- [ ] README ≤ 400 lines, all required sections present
- [ ] All 19 current agents (verified by `ls adapters/claude-code/agents/` at close time) mapped in architecture-overview.md
- [ ] All three layer systems shown together in architecture-overview.md
- [ ] Cross-links from harness-architecture.md and harness-strategy.md present
- [ ] SCRATCHPAD.md updated to reflect closure
- [ ] Plan flipped to Status: COMPLETED via `close-plan.sh` (auto-archives via plan-lifecycle.sh)
- [ ] Completion report appended per `~/.claude/templates/completion-report.md`

## Completion Report

_Generated by close-plan.sh on 2026-05-06T10:40:14Z._

### 1. Implementation Summary

Plan: `docs/plans/docs-refresh-tech-team-architecture.md` (slug: `docs-refresh-tech-team-architecture`).

Files touched (per plan's `## Files to Modify/Create`):

- `README.md`
- `docs/architecture-overview.md`
- `docs/doc-writing-patterns.md`
- `docs/harness-architecture.md`
- `docs/harness-strategy.md`

Commits referencing these files:

```
0090d4b feat(hook): bug-persistence-gate.sh — mechanical enforcement of testing.md rule
0909869 feat(work-shapes): Tranche C — work-shape library + rule + integrations
099d4e2 feat(phase-1d-c-2): Task 9 — wire prd-validity-gate + spec-freeze-gate into settings.json (template + live)
0be6526 feat(hook): A1 — independent goal extraction (UserPromptSubmit + Stop)
0cf6358 feat(build-doctrine): Tranche 5a-integration ritual wired audit analyzer pilot template
0e2c3a6 fix(harness-architecture): restore 8 regressed Phase 1d-C-2/1d-C-3 doc rows + Task 1-3 evidence
0f34109 feat(phase-1d-c-3): Tasks 1+2+6 — Decision 019 + findings-template + findings-ledger rule + docs/findings.md bootstrap
120593c feat(harness): plan-closure-validator gate + /close-plan skill (HARNESS-GAP-16, Phase 1d-H)
167a188 feat(harness): class-aware reviewer feedback contract (Mods 1+3)
17db609 docs(1d-E-1): Decision 021 + backlog cleanup + inventory (Phase 1d-E-1 Task 4)
18d3911 feat(incentive-map): proactive shift — catalog agent incentives + counter-incentive prompts
1a878a5 feat(harness): comprehension-gate rule (Phase 1d-C-4 Task 2)
1e6310c feat(hook): A7 — imperative-evidence linker
228c7fa feat(docs): architecture-overview.md — unified narrative (team-role + 3 layer systems + flow + filesystem)
2371e97 feat(scripts): harness-hygiene-sanitize helper (GAP-13 Task 4 / Layer 4)
25465b6 feat(phase-1d-c-3): Tasks 5+7 — wire findings-ledger-schema-gate + FM-022 + vaporware-prevention enforcement-map
2a49b11 feat(harness): resolve 3 pending discoveries — sweep hook, divergence detector, worktree-Q workaround
35ee3df feat(harness): mechanical evidence substrate (Tranche B)
393ba6f feat(harness): Phase B template + rule pattern for end-user-advocate acceptance loop
3afa037 feat(phase-1d-c-3): Tasks 3+4 — findings-ledger-schema-gate.sh hook + bug-persistence-gate.sh extension
3f3b2e9 feat(harness): Tranche G — calibration loop bootstrap
440a2d9 feat(rules): spawn-task-report-back convention rule (GAP-08 Task 1)
46616ba feat(build-doctrine): Tranche 6a — propagation engine framework + 8 starter rules + audit log
479d5bc feat(docs): README rewrite — front-door restructure for public-repo audience
483f5f6 feat(harness): Gen 5 — design-mode planning + outcome-focused reviewers
57cf357 feat(harness): plan-lifecycle hook for commit-on-creation + auto-archival
5870575 feat(hook): A5 — deferral-counter Stop hook
5938a69 feat(tranche-e): deterministic close-plan procedure
5c8e3e4 feat(harness): no-test-skip gate + deploy-to-production rule
5fdc217 feat(harness): meta-question skill library (why-slipped, find-bugs, verbose-plan, harness-lesson)
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
