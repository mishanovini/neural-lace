# Neural Lace — Harness Backlog

Last updated: 2026-05-04 v18: Phase 1d-G shipped — HARNESS-GAP-14 sub-item C (codename scrub of 5 committed files) + HARNESS-GAP-14-followups (4 SessionStart/UserPromptSubmit divergences) + observed-errors-first.md stub conversion all IMPLEMENTED. Three substantive deferrals explicitly recorded for the next focused session: HARNESS-GAP-08 (spawn_task report-back, ~4-6 hr substantive new mechanism design), HARNESS-GAP-13 (harness-hygiene-scan expansion, ~6-10 hr substantive new mechanism design), and 4 remaining rules-vs-hooks splits (acceptance-scenarios, agent-teams, design-mode-planning, testing — each is substantial restructuring). See "Recently implemented" section below for commit SHAs and "Phase 1d-G deferrals" section near the top of the open backlog. Earlier 2026-05-04 v17: HARNESS-GAP-14 IMPLEMENTED via Phase 1d-E-3 (`docs/plans/archive/phase-1d-e-3-gap-14-reconciliation.md`); template-vs-live `settings.json` reconciliation complete via per-hook orchestrator-driven research. Six REVERSIBLE verdicts auto-applied: 5 hooks added to template (`outcome-evidence-gate`, `systems-design-gate`, `no-test-skip-gate`, force-push/--no-verify blocker, `check-harness-sync` composition), public-repo blocker upgraded in live to elaborate `read-local-config.sh` form, tool-call-budget matcher tightened. Decision 024 records the verdicts. New backlog entry HARNESS-GAP-14-followups tracks remaining out-of-scope SessionStart/UserPromptSubmit divergences (P3). See "Recently implemented" section below for commit SHAs. Earlier 2026-05-04 v16: audit gap sub-items A, B, D, E, F IMPLEMENTED via Phase 1d-E-4 (`docs/plans/archive/phase-1d-e-4-gap-15-cleanup.md`); scanner self-test repaired, exemption tightened to scan allow-listed committed files, automation-mode schema authored, two un-archived plans properly closed with honest deferral annotations. Sub-item C (codename scrub) remains deferred to next master merge. See "Recently implemented" section below for commit SHAs. Earlier 2026-05-04 v15: HARNESS-GAP-10 sub-gap G IMPLEMENTED via Phase 1d-F (`docs/plans/phase-1d-f-definition-on-first-use.md`); definition-on-first-use enforcement live via new pre-commit hook + Decision 023 + new rule. See "Recently implemented" section below for commit SHAs. Earlier 2026-05-04 v14: HARNESS-GAP-10 sub-gaps A, B, C, F, H IMPLEMENTED via Phase 1d-E-2 (`docs/plans/phase-1d-e-2-audit-cleanup.md`); see "Recently implemented" section below for commit SHAs and audit document paths. Decision 022 records the structural choice (pipeline-agents.md deleted from global rules). Earlier 2026-05-04 v13: HARNESS-GAP-10 sub-gaps A, B, C, F, H absorbed into `docs/plans/phase-1d-e-2-audit-cleanup.md`. Earlier 2026-05-04 v12: HARNESS-GAP-09, HARNESS-DRIFT-01, HARNESS-DRIFT-02 IMPLEMENTED via Phase 1d-E-1 (`docs/plans/phase-1d-e-1-p1-drift-fixes.md`); see "Recently implemented" section below for commit SHAs. Earlier 2026-05-04 v11: HARNESS-GAP-09, HARNESS-DRIFT-01, HARNESS-DRIFT-02 absorbed into `docs/plans/phase-1d-e-1-p1-drift-fixes.md`. Earlier 2026-05-04 v10: HARNESS-GAP-15 added — Phase 1d-E public-release-hardening + harness-quick-wins audit-cleanup (5 sub-items). Plans 2 + 3 from the 2026-05-04 stale-plan audit un-archived and flipped to ACTIVE; Phase 1d-E now covers their resolution paths plus the codename scrub before next master merge. Earlier 2026-05-04 v9: HARNESS-GAP-14 added — template-vs-live settings.json reconciliation pass deferred from discovery `2026-05-04-template-vs-live-divergence-across-other-hooks`; detector half (B) ships in this session, reconciliation half (A) deferred to Phase 1d-E with orchestrator-driven research methodology specified per user direction. Earlier 2026-05-04 v8: HARNESS-GAP-10 sub-gap D PARTIALLY absorbed into `docs/plans/phase-1d-c-3-findings-ledger.md` — C9 ships the findings-ledger substrate that telemetry will populate; the manual-write path is operational while telemetry remains a 2026-08 target. Earlier 2026-05-04 v7: HARNESS-GAP-10 sub-gap E absorbed into `docs/plans/phase-1d-c-2-prd-validity-and-spec-freeze.md` (C16 behavioral-contracts validator implementation includes the concrete-invariants requirement). Earlier 2026-05-04 v6: HARNESS-GAP-12 IMPLEMENTED via SSH multi-push config; HARNESS-GAP-13 added — harness-hygiene-scan expansion (D5 reframe). Earlier 2026-05-03 v5: HARNESS-GAP-12 added — neural-lace dual-remote sync requires manual gh-auth dance; multi-push remote config proposed. Earlier 2026-05-03 v4: Discovery Protocol shipped — `docs/discoveries/` directory live; `bug-persistence-gate.sh` accepts discoveries; new `discovery-surfacer.sh` SessionStart hook. Earlier 2026-05-03 v3: HARNESS-GAP-11 added — reviewer accountability one-way gap surfaced during incentive-map analysis. Earlier 2026-05-03: HARNESS-GAP-10 added — Build Doctrine integration analysis surfaced 7 sub-gaps; see entry below. Earlier 2026-05-03: HARNESS-AUDIT-EXT-01 + HARNESS-AUDIT-EXT-02 absorbed into `docs/plans/pre-submission-audit-mechanical-enforcement.md` and removed from the open list per backlog-plan-atomicity rule. Earlier 2026-04-29: two mechanism-extension items added for Pre-Submission Class-Sweep Audit work. Earlier 2026-04-27: two pre-existing harness-drift items absorbed into `docs/plans/agent-teams-integration.md`; remaining two harness-drift items stay open. Earlier 2026-04-27: four harness-drift items added — see `docs/reviews/2026-04-27-agent-teams-conflict-analysis.md`. Earlier 2026-04-24: HARNESS-GAP-01..07; concurrent ACTIVE plans need acceptance-exempt declaration; capture-codify P2 entries.

Outstanding improvements to the Claude Code harness (rules, agents, hooks, skills). Project-level backlogs live in individual project repos; this file tracks harness-level work.

Strategy context and reasoning for many entries below lives in [`docs/claude-code-quality-strategy.md`](./claude-code-quality-strategy.md).

## Recently implemented (2026-05-04)

These items shipped in Phase 1d-E-1 (`docs/plans/phase-1d-e-1-p1-drift-fixes.md`):

- **HARNESS-GAP-09** — `plan-reviewer.sh` Check 1 + Check 5 false-positives narrowed via section-awareness (Check 1 only flags sweep language under `## Tasks` headings) + Tier A/B context-awareness (Check 5 runtime-keyword regex requires adjacency to database-context tokens). 4 new self-test scenarios added (commit b3951ba); 26-scenario self-test suite PASS.
- **HARNESS-DRIFT-01** — Six Gen-6 hooks confirmed wired in both template and live. `automation-mode-gate.sh` was the residual missing wiring; added to live (commit b973cf5). Other settings template-vs-live divergence remains in HARNESS-GAP-14's scope.
- **HARNESS-DRIFT-02** — SessionStart + push-time account-switching hooks replaced with config-driven `read-local-config.sh match-dir` calls (commits f2d812a template + 430365c evidence + live mirror). Decision 021 records the rationale: literal-substring approach rejected per its brittleness (identity leakage, single-org assumption, code-edit-to-add-account, false-positive fall-through).

These items shipped in Phase 1d-E-2 (`docs/plans/archive/phase-1d-e-2-audit-cleanup.md`):

- **Sub-gap A of the Build Doctrine integration audit batch** — Stop-hook orthogonality audit shipped (commit fd9f663). All 5 hooks (narrate-and-wait-gate, transcript-lie-detector, goal-coverage-on-stop, imperative-evidence-linker, deferral-counter) confirmed orthogonal; 2 pairs flagged CLARIFY BOUNDARY for documentation follow-up. Audit lives at `docs/reviews/2026-05-04-stop-hook-orthogonality.md`.
- **Sub-gap B of the audit batch** — `pipeline-agents.md` deleted from global rules (commit d8b30f3). Wholly project-specific; orchestrator pattern superseded the role framing. See Decision 022 for the alternatives considered and the rationale for deletion vs. relocation/generalization.
- **Sub-gap C of the audit batch** — `claim-reviewer` post-Gen6 reassessment shipped (commit d8b30f3). Verdict: KEEP as-is. Gen 6 hooks don't fully supersede; `claim-reviewer` remains the residual mitigation for verbal vaporware until Anthropic ships a PostMessage hook event. Reassess if/when that arrives. Audit lives at `docs/reviews/2026-05-04-claim-reviewer-reassessment.md`.
- **Sub-gap F of the audit batch** — Rules-vs-hooks audit shipped (commit d8b30f3). 24 rules audited; recommendations: 1 convert-to-stub, 4 split-into-stub-plus-extension, 19 keep verbose. Restructuring is OUT-OF-SCOPE for this plan; tracked via the audit document. Audit lives at `docs/reviews/2026-05-04-rules-vs-hooks-audit.md`.
- **Sub-gap H of the audit batch** — `docs/reviews/` gitignore convention documented (commit 7abe23e). Existing `.gitignore` was already correctly designed via date-prefix allowlist (`2026-*` → tracked). Documented the convention in `harness-hygiene.md` and added a sentinel comment in `.gitignore` itself.

These items shipped in Phase 1d-F (`docs/plans/archive/phase-1d-f-definition-on-first-use.md`):

- **HARNESS-GAP-10 sub-gap G** — Definition-on-first-use enforcement shipped (commits 7f24907 + this commit). Pre-commit hook scans *.md under build-doctrine/ for first-use acronyms; blocks if undefined in glossary or in-context. See Decision 023.

These items shipped in Phase 1d-E-4 (`docs/plans/archive/phase-1d-e-4-gap-15-cleanup.md`):

- **Audit gap sub-item A — scanner self-test repair.** `harness-hygiene-scan.sh --self-test` previously asserted an exemption for `docs/plans/foo.md` that had been deliberately removed. Self-test updated to assert the opposite (exit 1 on plan files); two new assertions added for the allow-list behavior. Commit f112226.
- **Audit gap sub-item B — scanner exemption logic tightened.** Directory-level exemption for `docs/decisions/`, `docs/reviews/`, `docs/sessions/` now applies ONLY to non-allow-listed paths within those directories. Allow-listed files (`NNN-*.md`, `YYYY-MM-DD-*.md`) ARE scanned. Full-tree scan after the fix surfaces 15 codename hits in committed decision/review files — these are the pre-existing leakage tracked separately as audit gap sub-item C. Commit f112226.
- **Audit gap sub-item D — automation-mode JSON schema authored.** `adapters/claude-code/schemas/automation-mode.schema.json` was claimed in `public-release-hardening.md` Task 6.1 but never authored at v1.0 publication. Schema now live with `{version, mode, deploy_matchers}`, version: 1 sentinel matching the existing four schemas. Commit 22c0e65.
- **Audit gap sub-item E — `public-release-hardening.md` properly closed.** Plan flipped to COMPLETED with honest annotations on the four previously-unchecked tasks: Task 1.2 scoped down per Option A; Task 4.2 shipped via HARNESS-DRIFT-02; Task 5.3 deferred with rationale; Task 6.1 shipped in commit 22c0e65. Auto-archived. Plan file is gitignored (would leak codenames if committed).
- **Audit gap sub-item F — `harness-quick-wins-2026-04-22.md` properly closed.** Plan flipped to COMPLETED. Phase A Task 1 (set `effortLevel: "xhigh"` in live `~/.claude/settings.json`) deferred with rationale: per-project `effort-policy-warn.sh` covers most of the value; global default flip is a personal-cost change best done interactively. 17 of 18 tasks remain shipped. Auto-archived. Commit ff5717d.

**Audit gap sub-item C — codename scrub before next master merge.** Still deferred per the right-sized P3 remediation plan. The scanner now reports the leakage (15 hits across 5 decision/review files), so the cleanup work has a verifier when it lands.

These items shipped in Phase 1d-E-3 (`docs/plans/archive/phase-1d-e-3-gap-14-reconciliation.md`):

- **HARNESS-GAP-14** — Template-vs-live `settings.json` reconciliation shipped (commits 84a0c61 audit + 9d3c2f0 reconciliation + this commit). Six per-hook proposals authored with originating-commit + plan + architecture-doc citations; all REVERSIBLE; auto-applied per discovery-protocol decide-and-apply. Five hooks added to template (`outcome-evidence-gate`, `systems-design-gate`, `no-test-skip-gate`, force-push/`--no-verify` blocker, `check-harness-sync` composition into pre-commit-gate); one hook upgraded in live (`public-repo` blocker to elaborate `read-local-config.sh public-blocked` form). Tool-call-budget matcher tightened to `Edit|Write|Bash` to match documented form. Post-reconciliation: `settings-divergence-detector.sh` PreToolUse counts equal between template and live (template=23, live=23). Out-of-scope SessionStart + UserPromptSubmit divergences (4-6 items) flagged in audit doc as follow-up; new backlog item to track. See Decision 024. Audit lives at `docs/reviews/2026-05-04-gap-14-reconciliation-proposals.md`.

These items shipped in Phase 1d-G (`docs/plans/phase-1d-g-final-cleanup.md`):

- **HARNESS-GAP-14 sub-item C — codename scrub before next master merge.** 15 hits across 5 committed decision/review files sanitized to generic placeholders (e.g., `<personal-account>`, `<work-org-codename>`, `<product-codename-X>`). Audit-trail readability preserved; substantive content unchanged. Full-tree scanner reports zero matches after scrub. DECISIONS.md gained a footnote acknowledging the in-place scrub of records 001, 002, 013 (no status or substance changes). Commit 6881712.
- **HARNESS-GAP-14-followups** — Four out-of-scope SessionStart/UserPromptSubmit divergences reconciled. Template was canonical for all four; live `~/.claude/settings.json` was updated to match: (1) compact-recovery hook stripped of hardcoded per-project subdirectory paths, (2) automation-mode initializer SessionStart block added, (3) legacy `claude-config` harness-sync hook removed (referenced pre-rename path), (4) UserPromptSubmit title-bar upgraded from basename-only to automation-mode-aware form. Verification: `jq -S '.hooks'` of live and template byte-identical; remaining file-level divergence is confined to the per-machine `permissions` array (intentional). Commit b27ab7e.
- **Rules-vs-hooks restructuring (observed-errors-first.md convert)** — Per Phase 1d-E-2 audit's recommendation, `observed-errors-first.md` was ~80% hook-enforced; converted to stub mirroring `vaporware-prevention.md`'s pattern (short opening + classification + enforcement-map table + cross-references). 25 lines (was 74). Synced to `~/.claude/rules/` (gitignored mirror). Commit ffff6e6.

Older closed items live in plan completion reports under `docs/plans/archive/`.

## Phase 1d-G deferrals (2026-05-04)

Phase 1d-G shipped three deliverables but explicitly deferred three substantive items to a fresh future session. Each deferral has clear rationale and is sized with an effort estimate so a future session can pick the right item to attempt.

- **HARNESS-GAP-08 — `spawn_task` optional report-back (deferred to fresh session 2026-05-X+).** Substantive new mechanism design (~4-6 hr). The full `Why this is a gap` discussion lives in the HARNESS-GAP-08 entry below. Warrants fresh-session attention because the design space (callback channel shape, integration with existing fire-and-forget contract, harness-vs-orchestrator-coordinator-pattern boundary) is non-trivial and benefits from an uncluttered context.
- **HARNESS-GAP-13 — harness-hygiene-scan expansion (deferred to fresh session 2026-05-X+).** Substantive new mechanism design (~6-10 hr). The full discussion lives in the HARNESS-GAP-13 entry below. Warrants fresh-session attention because the pattern-detection scope (project-specific shapes beyond the current denylist; e.g., schema-fingerprint patterns, OAuth client-id shapes, cloud-bucket names) requires careful design to avoid false positives.
- **Rules-vs-hooks restructuring — 4 remaining splits (deferred to focused future sessions).** The Phase 1d-E-2 rules-vs-hooks audit recommended 4 split-into-stub-plus-extension restructurings beyond the observed-errors-first.md convert that shipped in Phase 1d-G: `acceptance-scenarios.md`, `agent-teams.md`, `design-mode-planning.md`, `testing.md`. Each is substantial restructuring per rule (each rule is large, and each split requires designing the stub-vs-extension boundary carefully without losing prose context). Deferred to per-rule focused sessions; the audit document at `docs/reviews/2026-05-04-rules-vs-hooks-audit.md` tracks the recommendations and remains the source of truth for which rules need work.

## HARNESS-GAP-08 — `spawn_task` should support optional report-back (added 2026-04-30)

**Observation.** `mcp__ccd_session__spawn_task` is documented as fire-and-forget — the orchestrator session spawns a task, the spawned session runs independently with its own full harness, and there is no callback channel. The orchestrator only learns the result by either (a) reading git artifacts the spawned session committed, or (b) the user manually telling the orchestrator the spawned task is done.

**Why this is a gap.** For genuinely independent work (CI migration, code audits, one-shot doc generation), fire-and-forget is correct — that's the whole point of context hygiene. But for **sequenced fix work** where the orchestrator drives a punchlist (e.g., "fix P0-1 → assess result → fix P0-2 → ..."), the orchestrator must coordinate. Currently the user mediates: they tell the orchestrator "the spawned task completed," and the orchestrator manually fetches the resulting branch via git. This:
- Adds friction every time the orchestrator wants to chain fixes through spawn_task
- Pushes orchestrators toward Agent-tool-only patterns (which keep all build context in the orchestrator's window) when spawn_task would otherwise be a better fit
- Has no mechanical signal at all if the user forgets to tell the orchestrator (or tells the wrong session)

**Proposed mechanism.** `spawn_task` accepts an optional `report_back: true` param. When set:
1. The spawned session, on stop, writes a structured JSON file at `.claude/state/spawned-task-results/<task-id>.json` with: `{task_id, started_at, ended_at, branch, pr_url, exit_status, summary, commits: [<sha>], artifacts: [<path>]}`.
2. The orchestrator's `SessionStart`-equivalent hook (or a per-turn check) scans `.claude/state/spawned-task-results/` for new entries since its last turn and surfaces them in the system reminder.
3. The orchestrator can then act on the result on its very next turn — cherry-pick, run task-verifier, plan the next fix — without user mediation.

**Cleanup semantics.** Result files older than 7 days get pruned by the same hook. Or move them to `archive/` after the orchestrator acknowledges them (mirroring `plan-lifecycle.sh`'s archive pattern).

**Fallback.** Spawn_task without `report_back: true` keeps current fire-and-forget behavior. Backward compatible.

**Originating context.** Surfaced 2026-04-30 during a downstream-project session arc that chained multiple `spawn_task` invocations as a fix punchlist. The user asked: "Shouldn't each of these spawned tasks send their data back to you when they're done so you can review and know when to kick off the following tasks?" The orchestrator (correctly) had to acknowledge that no callback exists today and manual user mediation was the workaround. This pattern recurred multiple times across the session arc.

**Effort estimate.** S-M (~4-6 hr). One JSON-write helper, one hook to scan and surface. Tests for: result file written on terminal exit, multiple spawned tasks don't collide, hook surfaces only unread results, archive on acknowledgment.

**Class.** `harness-coordination-channel-missing` — orchestrator-to-spawned-task lacks a return path; user becomes the channel.

---

## HARNESS-GAP-10 — Seven gaps surfaced during Build Doctrine integration analysis (added 2026-05-03)

**Source.** Build Doctrine + Neural Lace deep comparative review (plan `~/.claude/plans/build-doctrine-cheerful-hearth.md`, completed 2026-05-03). Full evidence in `docs/reviews/2026-05-03-build-doctrine-integration-gaps.md` (gitignored — content is local-only; this entry is the public pointer). Seven sub-gaps named below; each is a candidate for Phase 1d-E (harness cleanup) per the unified methodology recommendation at `~/claude-projects/Build Doctrine/outputs/unified-methodology-recommendation.md`.

**Sub-gap A — ABSORBED 2026-05-04 into `docs/plans/phase-1d-e-2-audit-cleanup.md`** (Stop-hook overlap analysis).

**Sub-gap B — ABSORBED 2026-05-04 into `docs/plans/phase-1d-e-2-audit-cleanup.md`** (`pipeline-agents.md` relocation/restructure).

**Sub-gap C — ABSORBED 2026-05-04 into `docs/plans/phase-1d-e-2-audit-cleanup.md`** (`claim-reviewer` post-Gen6 reassessment).

**Sub-gap D — PARTIALLY ABSORBED 2026-05-04 into `docs/plans/phase-1d-c-3-findings-ledger.md`.** C9 ships the findings-ledger substrate (`docs/findings.md` + schema gate + bug-persistence extension) that telemetry will eventually populate. The MANUAL-WRITE path is operational starting Phase 1d-C-3 — agents/gates write findings explicitly. The AUTOMATED-EXTRACTION path (LLM-assisted finding extraction from session transcripts) remains gated on telemetry's 2026-08 target. C13 (promotion/demotion) and Phase 1d-G (calibration-mimicry, deferred) can both proceed against the manual ledger; if telemetry slips, only the automation slips.

**Sub-gap E — ABSORBED 2026-05-04 into `docs/plans/phase-1d-c-2-prd-validity-and-spec-freeze.md`.** C16 behavioral-contracts validator implementation includes the concrete-invariants requirement (idempotency / performance budget / retry semantics / failure modes each ≥ 30 non-ws chars + no placeholder-only content). Vacuous-filler rejection is partial in 1d-C-2 (mechanical substance check); deeper semantic validation (e.g., "idempotency must reference a specific input→output mapping") deferred to a future plan if substance check proves insufficient.

**Sub-gap F — ABSORBED 2026-05-04 into `docs/plans/phase-1d-e-2-audit-cleanup.md`** (Rules-superseded-by-hooks audit).

**Sub-gap G — ABSORBED 2026-05-04 into `docs/plans/phase-1d-f-definition-on-first-use.md`** (Definition-on-first-use enforcement).

**Sub-gap H — ABSORBED 2026-05-04 into `docs/plans/phase-1d-e-2-audit-cleanup.md`** (`docs/reviews/` gitignore refinement).

**Cross-references.**
- Full review (gitignored, local-only): `docs/reviews/2026-05-03-build-doctrine-integration-gaps.md`
- Originating analysis: `~/claude-projects/Build Doctrine/outputs/analysis/03-comparative-analysis.md`
- Methodology recommendation: `~/claude-projects/Build Doctrine/outputs/unified-methodology-recommendation.md`
- Recovery point for the integration: tag `pre-build-doctrine-integration` at NL master HEAD, branch `build-doctrine-integration` for Phase 1d work.

---

## HARNESS-GAP-11 — Reviewer accountability is one-way (added 2026-05-03)

**Source.** Surfaced during agent-incentive-map work (`docs/agent-incentive-map.md`, plan `docs/plans/agent-incentive-map.md`). Identified as a structural weakness in NL's adversarial-pairing architecture: when a reviewer agent (code-reviewer, task-verifier, end-user-advocate, harness-reviewer, systems-designer, ux-designer, claim-reviewer, plan-evidence-reviewer) PASSes work that subsequently fails at runtime acceptance OR fails in the next session OR fails in production, no signal flows back to the agent (or to a meta-tracker) for calibration.

**Why this is a gap.** Each reviewer's incentive to be careful is purely intrinsic — there is no consequence to PASSing too easily. Over time this creates calibration drift: reviewers pass borderline work because no penalty arrives when borderline work later fails. The user observed this pattern explicitly: "I don't trust the builder agents because they seem the most willing to find workarounds in order to call their work done." The same dynamic applies to reviewers — they have a structural incentive to take builders at their word because doing so is faster and friction-free.

This is the reviewer-side analogue of the documented `claim-reviewer` self-invocation gap in `~/.claude/rules/vaporware-prevention.md` ("the single unclosed gap from Generation 4"). Both are unaccountability gaps; both reduce the harness's actual quality below its nominal quality.

**Proposed mechanism.** Reviewer-calibration tracker — a new mechanism that:

1. Records every reviewer PASS verdict to `.claude/state/reviewer-passes/<reviewer-name>-<task-id>-<timestamp>.json` with: reviewer agent name, task ID, plan path, verdict, claimed-substance summary, file:line citations made.
2. When `enforcement-gap-analyzer` fires on a runtime acceptance FAIL OR `bug-persistence-gate` fires on a session-end with bug observations OR a future production-failure signal lands, it cross-references the reviewer-passes log to identify which reviewer last said PASS on the now-failed work. Surfaces the (reviewer, failed-work) pair to a per-reviewer calibration log at `.claude/state/reviewer-calibration-<reviewer-name>.md`.
3. Periodic audit: `/harness-review` weekly self-audit (a new check) reads each reviewer's calibration log and surfaces patterns: which reviewer's PASS verdicts most often precede later failures? That reviewer's prompt or rubric needs sharpening.

**Why this is a meaty mechanism (not first-pass).** Three implementation gates:

1. The mechanism depends on `enforcement-gap-analyzer` being able to attribute the failure to specific prior reviewer verdicts. That attribution requires Phase 1d-D telemetry (see HARNESS-GAP-10 sub-gap D — telemetry not yet shipped, blocks dependent mechanisms).
2. The mechanism depends on `findings-ledger schema` (C9) shipping so that "later failure" has a structured comparable form to the PASS verdict.
3. The mechanism's value compounds with TIME — a single PASS-then-FAIL pair is noise; a pattern of N PASS-then-FAIL pairs is signal. So the mechanism needs to ship and run for weeks before the audit produces actionable findings.

**Effort estimate.** L (~12-20 hours). One JSON-write helper for reviewer-pass logging, extension to `enforcement-gap-analyzer` for cross-reference, calibration-log format design, `/harness-review` audit extension, self-test scenarios.

**Why P2 (not P1).** Calibration drift is a slow-moving structural risk; it doesn't cause individual session failures. The first-pass C-mechanisms (C10 scope-enforcement, C22 quantitative-claims, C7-DAG-waiver — already shipped) catch immediate failure modes. C1/C2/C9/C15/C16 catch upstream failure modes. The reviewer-calibration mechanism catches drift across many sessions, which only matters once the harness is running stably enough to accumulate the pattern data. Sequence after Phase 1d-C-4 (C15 ships).

**Originating context.** The user posed (2026-05-03): "Show me the incentive and I'll show you the outcome — applied to AI agents." The agent-incentive-map document catalogued each agent's stray-from patterns; this gap is the most consequential unaddressed weakness across the catalogue.

---

## HARNESS-GAP-13 — Expand harness-hygiene-scan to detect more project-specific shapes (added 2026-05-04)

**Source.** D5 of the D1-D5 educational re-do dialogue (2026-05-03/04). User raised the structural question: with builders working in their own project's directory (`~/claude-projects/<project>/`), project-specific decisions/reviews automatically end up in the project's repo, not in NL's. The gitignore protecting `docs/decisions/` etc. was a belt-and-suspenders against an unlikely failure mode. The primary defense is `harness-hygiene-scan.sh` checking against a denylist of project-specific terms.

**Why this is a gap.** The current denylist catches specific terms (project codenames, internal jargon, customer/business names). Each pattern is a known-bad shape. But the denylist is reactive — it grows as new project-specific shapes are observed. There's no periodic full-tree audit that surfaces new project-specific content the denylist hasn't yet learned to detect. Plus the denylist's pattern-matching is literal — it doesn't catch project-specific content that uses unusual terminology or paraphrases known terms.

User question (D5): "Should we expand harness-hygiene-scan to also check for any project-specific details that might be trying to make their way into the harness documents?"

**Proposed mechanism — multi-layer expansion:**

1. **Denylist additions for common tech-stack identifiers** that frequently leak in: third-party service names commonly used by downstream projects, common database technologies, framework-specific terms.
2. **Heuristic detection layer** for content shapes that suggest project-specific origin: file paths matching project-internal patterns (e.g., `app/api/v\d+/[\w-]+/`, `src/components/[A-Z][\w]+\.tsx`), repeated capitalized terms that don't appear in NL's own vocabulary, customer/business-specific term clusters.
3. **Periodic full-tree audit** as part of `/harness-review` weekly skill: scan ALL committed files (not just staged diff) against denylist + heuristics. Surface candidates for denylist addition or content sanitization.
4. **Sanitization helper** that proposes replacements for detected matches (e.g., "this file references `<project-name>` 8 times — suggest sanitizing to `<your-project>`").

**Why this matters.** Without expansion, project-specific content slowly accumulates in NL through paths the current scanner doesn't detect. The harness-hygiene rule is supposed to be the structural defense; if the scanner has blind spots, the rule's protection is illusory. The user's reframe in D5 is correct: directory separation does most of the work, but harness-hygiene-scan is the explicit defense and should match its claim.

**Effort estimate.** M (~6-10 hours). Denylist additions are quick (~1 hour); heuristic detection is the bulk (~4-6 hours including pattern design + self-tests); full-tree audit + sanitization helper add another ~2-3 hours.

**Why P3 (not P1).** The current scanner caught 4 leaks this session correctly. The expansion adds layered protection but the current floor is functioning. Schedule for Phase 1d-E alongside HARNESS-GAP-10 sub-gaps. Would land alongside the discovery-protocol gate-redesign and other harness-cleanup work.

**Originating context.** User's D5 framing (2026-05-04): "Building of everything [is] performed within that repo's own directory... PT decisions automatically [are] contained within that project's directory, keeping the Neural Lace project from absorbing it... Should we expand harness-hygiene-scan?" Affirmed: the directory separation does most of the work; harness-hygiene-scan is the explicit defense and benefits from expansion to match its claim.

---

## HARNESS-GAP-12 — Neural-lace dual-remote sync requires manual gh-auth dance (added 2026-05-03; STATUS: IMPLEMENTED 2026-05-04)

**Resolution.** Closed 2026-05-04 via SSH multi-push configuration on origin remote. See `docs/discoveries/2026-05-04-multi-push-ssh-config-implemented.md` for the full implementation log. `git push origin <branch>` now pushes to BOTH GitHub accounts atomically via per-Host SSH keys; auth-switch hook is irrelevant for neural-lace pushes.



**Source.** Surfaced 2026-05-03 during autonomous-delivery work. The harness's `git push` PreToolUse hook in `settings.json.template` calls `read-local-config.sh match-dir "$PWD"` and switches the active gh account based on directory pattern matching. For neural-lace specifically (dual-hosted: `origin = <personal-account>/neural-lace`, `pt = <work-org>/neural-lace`), the pattern matching switches to the wrong account on push, producing 403 errors. This recurred 2+ times in the same session.

**Why this is a gap.** Neural Lace is dual-hosted by design — pushes should reach BOTH GitHub accounts so the harness stays in sync across personal and work-org. The current setup has TWO distinct problems:

1. **Auth-switch fires wrong for neural-lace.** The local config's directory→account mapping doesn't have a tiebreaker for the dual-hosted case; the matcher picks one account, but if the push targets the other account's URL, it 403s.
2. **No automated dual-sync.** Even when one push succeeds, the OTHER remote isn't updated. The maintainer must remember to manually push to both, or accept that one remote drifts.

User stated requirement (2026-05-03): "Neural Lace needs to always be kept up to date in both GH accounts. They need to stay in sync. What's the best solution that automates this and keeps us from continuing to run into this issue?"

**Proposed mechanism.** Multi-push remote configuration plus per-host credential differentiation:

1. Configure `origin` as a multi-push remote: `git remote set-url --add --push origin <pt-url>` so a single `git push origin` sends to BOTH URLs.
2. Use SSH for one URL (typically the work-org), HTTPS for the other. SSH key auth bypasses the gh-active-account dependency entirely; HTTPS auth uses gh credentials for whichever active account.
3. The auth-switch hook becomes irrelevant for neural-lace pushes (both URLs auth independently).

Alternative simpler approach: explicit `neural-lace/` → `<personal-account>` mapping in `~/.claude/local/accounts.config.json` to fix the auth-switch. Doesn't solve dual-sync; manual `git push <work-org-remote>` still needed.

**Why this matters now.** Three commits this session hit the auth-switch failure, requiring manual `gh auth switch --user <personal-account>` + retry. This is recurring friction that should be fixed structurally rather than worked around.

**Effort estimate.** S (~30-60 minutes for multi-push + SSH config). Or XS (~5 minutes) for the local-config-only patch.

**Why P2.** Friction is meaningful but not a correctness threat — pushes still happen, just with extra steps. Schedule for Phase 1d-E (harness cleanup) alongside HARNESS-GAP-10 sub-gaps.

**Originating context.** Recurred during D4-discussion of the D1-D5 educational re-do (2026-05-03). The user pushed back on the recurrence: "I thought we set things up so that you're always aware of which account to use for each repo." The setup was correct for single-hosted projects; neural-lace's dual-hosting wasn't accounted for.

---

## HARNESS-GAP-14 — IMPLEMENTED 2026-05-04 via Phase 1d-E-3 (`docs/plans/archive/phase-1d-e-3-gap-14-reconciliation.md`)

See "Recently implemented" section above for commit SHAs + Decision 024. Follow-up entry below covers out-of-scope SessionStart / UserPromptSubmit divergences.

## HARNESS-GAP-14-followups — IMPLEMENTED 2026-05-04 via Phase 1d-G (`docs/plans/phase-1d-g-final-cleanup.md`)

See "Recently implemented" section above for commit SHA (b27ab7e). All four out-of-scope SessionStart/UserPromptSubmit divergences reconciled. Audit doc updated with the Phase 1d-G addendum at `docs/reviews/2026-05-04-gap-14-reconciliation-proposals.md`.

(Historical entry preserved below.)

## HARNESS-GAP-14-followups — Out-of-scope settings divergences from GAP-14 audit (added 2026-05-04)

**Source.** Audit `docs/reviews/2026-05-04-gap-14-reconciliation-proposals.md` "Out-of-scope divergences" section. Phase 1d-E-3 reconciled the named PreToolUse hooks; the divergence-detector still surfaces remaining items in SessionStart and UserPromptSubmit hook chains.

**The remaining divergences:**
1. SessionStart compact-recovery hook — live has hardcoded per-project subdirectory paths in its backlog/plan-glob lists; template canonical (per-project paths shouldn't live in the global hook).
2. SessionStart automation-mode initializer — present in template, NOT in live; template canonical (live missed update when automation-mode shipped).
3. SessionStart legacy `claude-config` harness-sync warn hook — present in template referencing `~/claude-projects/claude-config` (predates rename to `neural-lace`). Live correctly omits; template needs path correction or removal.
4. UserPromptSubmit title-bar hook — template version reads `automation-mode` from local config and includes it in the title; live is older form (just basename). Template canonical.

**Effort estimate.** S (~30-60 min when taken up). Apply the verdicts; verify divergence-detector reports clean output.

**Why P3.** Real divergence but the in-scope reconciliation closed the higher-impact PreToolUse drift. Each remaining item is a single-line fix with an obvious canonical side.

**Originating context.** Surfaced during Phase 1d-E-3 audit as out-of-scope drift not covered by the plan's named four hooks.

---

## Pre-existing harness drift surfaced 2026-04-27 (during agent-teams conflict analysis)

Items found while doing the Phase 1 ground-truth inventory for Agent Teams integration. Two items (P2-class) were absorbed into `docs/plans/agent-teams-integration.md` on plan creation; HARNESS-DRIFT-01 and HARNESS-DRIFT-02 were absorbed into `docs/plans/phase-1d-e-1-p1-drift-fixes.md` on 2026-05-04.

## Known gaps in current enforcement (from strategy doc, 2026-04-22)

These are residual risks in the Gen 4+ harness. Each is documented honestly rather than left hidden.

### P1 — Verbal vaporware in conversation is not mechanically blocked

Claude Code has no PostMessage hook. `claim-reviewer` is self-invoked and can be skipped. When the agent makes a feature claim in conversation without citing file:line, no mechanism catches it. Current mitigation: user reflex to ask for citations. Closing requires either a PostMessage hook in Claude Code itself or an adversarial post-response review agent that fires on every Nth response.

### P1 — Tool-call-budget `--ack` attestation is bypassable

The `tool-call-budget.sh` hook looks for sentinel lines in `~/.claude/state/reviews/`. A builder agent could Write that file directly without actually invoking `plan-evidence-reviewer`. Friction is raised but not cryptographically closed. Closing requires either per-session HMAC signing or architectural support for observing Task tool invocations.

### P1 — Concurrent-session state collisions (plan-wipe incidents)

Multiple Claude Code sessions on the same machine share `~/.claude/` state and the git working tree. Uncommitted plan files have been lost to concurrent-session `git stash`/`clean` operations on multiple documented occasions (2026-04-19, 2026-04-20). A project-level plan addressing commit-on-creation is in flight, but cross-session state coordination (shared `~/.claude/` directory) is still unresolved.

### P2 — `plan-lifecycle.sh` archival staging misses content change

Surfaced 2026-04-23 (during plan #5's own self-archival, commit 93ef15d). When the Status field is edited, the hook stages a `git mv` to archive but does NOT stage the actual Status text change. Resulting commit captures the rename only; the content change sits unstaged in the working tree at the new path, requiring a manual follow-up `git add <new-path> && git commit`.

**Fix candidates:**
- (a) Hook also runs `git add <new-path>` after the `git mv` so the content change is staged together with the rename. Risk: if the new path doesn't exist yet (race condition with the rename being staged but not committed), `git add` may fail.
- (b) Hook emits a clear warning message reminding the user to `git add <new-path>` before committing. Pattern enforcement, not mechanism.
- (c) Hook moves the file via `mv` (filesystem rename) BEFORE the Edit tool's content change reaches disk, then user does `git add -A` which captures both as a single staged change. Requires hook re-architecture.

Workaround pattern (used 2026-04-23): commit twice — first commit captures the rename (zero-content change), second commit captures the Status text update. See plan #5's archival commits 93ef15d + 6f4c057.

### P1 — Concurrent ACTIVE plans need acceptance-exempt declaration before next session-end (2026-04-24)

After Phase D of `docs/plans/end-user-advocate-acceptance-loop.md` registered `product-acceptance-gate.sh` as Stop-hook position 4, two concurrent ACTIVE plans will block session end on the next session unless reconciled:

- `docs/plans/claude-remote-adoption.md`
- `docs/plans/class-aware-review-feedback-smoke-test-plan.md`

Both are harness-dev plans without a product-user surface. Per `rules/acceptance-scenarios.md`'s exemption guidance, each should declare `acceptance-exempt: true` with a substantive `acceptance-exempt-reason:` (>= 20 chars). The third concurrent plan, `end-user-advocate-acceptance-loop.md` itself, has already been declared exempt in Phase D (bootstrap meta-plan rationale).

**Fix path:** in the next session, edit each plan file's header to add the two fields. Example for `claude-remote-adoption.md`:
```
acceptance-exempt: true
acceptance-exempt-reason: Harness-development plan (Claude Code remote-mode adoption); no product-user surface to verify at runtime — the maintainer exercises the harness in subsequent sessions.
```

Until done, sessions ending while these plans are ACTIVE will hit a BLOCK with a clear remediation message from `product-acceptance-gate.sh`. Per-session waiver is also available as a fallback (`echo "..." > .claude/state/acceptance-waiver-<slug>-$(date +%s).txt`).

### P1 — `plan-phase-builder` sub-agent dispatched without Task tool — cannot invoke `task-verifier` (2026-04-23)

**Flagged for harness-reviewer 2026-04-27:** the agent-teams integration session re-encountered this gap (commits f993a83, ed42e8b, ff28441, 6cca4b8 — Phase 5 Tasks 1-4 of `docs/plans/agent-teams-integration.md`). The evidence-first fallback worked end-to-end across four builders, providing additional empirical confirmation that path (b) below is viable. Next `/harness-review` skill run should evaluate which fix to commit to.

When the orchestrator dispatches a `plan-phase-builder` sub-agent (the dispatch type used while building Phase A of `docs/plans/archive/robust-plan-file-lifecycle.md`), the sub-agent's tool surface does NOT include the Task tool — it is not in the top-level tool list and is also not surfaced via ToolSearch (`select:Task` returns no results). Consequence: the sub-agent cannot invoke `task-verifier` as instructed by both the orchestrator-pattern rule and the dispatch prompt. The builder must fall back to writing evidence blocks directly under the evidence-first protocol enforced by `plan-edit-validator.sh` + `runtime-verification-executor.sh` — which works (the harness was specifically designed to allow this path), but it conflicts with the rule's "only `task-verifier` flips checkboxes" framing. Two possible fixes: (a) ensure dispatched `plan-phase-builder` sub-agents inherit the Task tool so they can invoke `task-verifier`; (b) update `~/.claude/rules/orchestrator-pattern.md` and the dispatch-prompt boilerplate to explicitly authorize the evidence-first fallback when Task is unavailable, with a written rationale. Either way, the current mismatch between the rule and the runtime tool surface should be reconciled. Reference instances: original Phase A build (commits d2d1494 + 4cc9c2a on `feat/robust-plan-file-lifecycle`); agent-teams integration Phase 5 Tasks 1-4 (commits f993a83, ed42e8b, ff28441, 6cca4b8 on master, 2026-04-27).

## Improvements surfaced by a downstream plan-staleness sweep (2026-04-24)

Seven structural gaps that allowed ~22 ACTIVE plans to accumulate across two sibling project repos without any enforcement firing. Each entry is named HARNESS-GAP-NN for cross-reference. Surfaced during a Q&A session that hit the `product-acceptance-gate.sh` Stop hook in storm — the gate fired, the user asked "why are so many plans considered done without everything checked off?", and these are the answers.

### HARNESS-GAP-01 — `pre-stop-verifier.sh` doesn't block terminal-Status flips with unverified tasks

`pre-stop-verifier.sh` blocks "checked tasks without evidence blocks" AND "unchecked tasks AND `Status: ACTIVE`." It does NOT block "terminal Status (`COMPLETED` / `DEFERRED` / `ABANDONED` / `SUPERSEDED`) AND unchecked tasks AND no evidence block names them shipped." Consequence: the cleanup move (flip Status to clear the gate) silently legitimizes whatever checkbox state is in the file — the precise pattern that produced a downstream plan-staleness sweep. Proposed fix: add Check 4d to `pre-stop-verifier.sh` that requires every unchecked task in a terminal-Status plan to either (a) have an evidence block claiming it shipped, or (b) appear in an explicit "Tasks deferred to Phase 2 / out of scope" section in the closing note.

### HARNESS-GAP-02 — No git-log → plan-checkbox correlation

A commit that touches files in a task's `Files to Modify/Create` list could plausibly satisfy that task, but no hook reads the diff, finds the matching task, and surfaces "this commit may satisfy Task X.Y in plan Z — invoke task-verifier?" Sync is one-way: builder must remember. If the builder errors, exits, or work goes through any non-orchestrator path (manual fix, hotfix, kanban-engine direct commit), the link is never formed. Proposed fix: PostToolUse hook on Git commits that scans the commit's diff against `docs/plans/*.md` ACTIVE plans' file lists and emits a non-blocking surface message naming the candidate tasks. User or next session can act on it.

### HARNESS-GAP-03 — Auto-generated kanban plans bypass task-checkbox enforcement

Plans created by `kanban-engine.yml` from GitHub Issues have task lists that read "(The build agent will investigate, diagnose, and implement autonomously.)" — i.e., 0 checkboxes by design. The verification model assumes plans have task lists. Kanban plans don't, so `pre-stop-verifier`'s "unchecked tasks" check is vacuously satisfied — but there's also no positive signal that the work shipped. The kanban plan can sit at `Status: ACTIVE` indefinitely while the underlying GitHub Issue is closed. Proposed fix (two parts): (a) `Status: ISSUE-TRACKED` sentinel that exempts kanban plans from task-checkbox enforcement and treats issue-close as the verification, (b) periodic Routine that scans kanban plans whose source issue is CLOSED and auto-flips Status: COMPLETED.

### HARNESS-GAP-04 — Reactive audit, not preventive

a downstream plan-staleness sweep exists in the backlog because the `product-acceptance-gate.sh` Stop hook started failing loudly enough that someone noticed 22 stale plans. There's no scheduled "weekly plan-audit" Routine that surfaces stale plans before they accumulate. By the time you see drift, you have 22 plans to triage, the sweep takes hours instead of minutes, and the user's confidence in the gate erodes. Proposed fix: weekly `/schedule` Routine that lists every plan with `Status: ACTIVE` for >14 days where the most recent commit touching `docs/plans/<slug>` is >7 days old. Output goes to `docs/reviews/YYYY-MM-DD-plan-staleness-audit.md` so it's actionable at human scale.

### HARNESS-GAP-05 — Status-audit sub-agents conflate "code shipped" with "feature works"

When a research / status-audit sub-agent reports on a plan (e.g., "the roadmap is functionally complete"), the agent typically correlates checkbox state with git log — both static signals. It does NOT exercise the feature at runtime. The `end-user-advocate` exists for runtime verification but is not invoked by status-audit agents by default. Result: a plan can be reported "done" based on artifacts that exist on disk, without anyone ever confirming a real user can use the feature. Proposed fix: either (a) extend `task-verifier`'s verdict shape to distinguish `evidence: artifact-only` from `evidence: runtime-PASS` and require runtime evidence for any task whose `Done when:` criterion involves user-observable behavior, OR (b) add a rule that any agent reporting "this plan is done" must call out which checks were performed and which were skipped, in a structured `## Verification Coverage` block.

### HARNESS-GAP-06 — No first-class `Status: PENDING-REVIEW` for "code shipped, human QA pending"

The current terminal Status taxonomy (`COMPLETED`, `DEFERRED`, `ABANDONED`, `SUPERSEDED`) lacks an honest label for the very common state "the engineering work shipped but the user hasn't yet exercised it to confirm the build matches their expectation." Sessions are forced to choose: leave Status: ACTIVE (gates fire forever) or flip COMPLETED (loses the "I haven't actually tried this yet" signal). Workaround in the surfacing project: pair `Status: COMPLETED` with `MANUAL-QA-<plan-slug>` backlog items.

Proposed fix: real `Status: PENDING-REVIEW` sentinel honored by the harness — plan auto-archives like other terminal statuses, but session-end gate emits a non-blocking reminder listing pending-review plans the user should triage. The sub-status `PENDING-REVIEW` ages out into `COMPLETED` after explicit user sign-off (or `DEFERRED` if QA found regressions).

**User-supplied requirements (refined 2026-04-24):**

1. **MUST NOT block continued progress.** A plan in `PENDING-REVIEW` does NOT trigger acceptance gates, does NOT gate session end, does NOT gate dispatch of new builders, does NOT block other plans from being created or worked. The only signal is informational. Specifically: `product-acceptance-gate.sh` must treat `PENDING-REVIEW` as equivalent to `acceptance-exempt` for blocking purposes; `pre-stop-verifier.sh` must treat `PENDING-REVIEW` as a terminal status for completion-check purposes.

2. **Persistent roadmap-level + plan-level overview.** A dashboard (or session-start surface) that shows what's pending review at both levels:
   - **Plan level:** within a plan file, individual tasks could carry per-task review state (`- [x] Task 1 (PENDING-REVIEW)` vs `- [x] Task 1 (REVIEWED 2026-04-25 by user)`). Lets the user know which specific tasks within a plan they've actually verified.
   - **Roadmap level:** a Routine or skill that scans all plans (active + archived) and produces a dashboard at `docs/reviews/<date>-pending-review-dashboard.md` (or surfaces in SCRATCHPAD on session start). Lists every plan currently in `PENDING-REVIEW` with a one-line summary of what's awaiting verification and how long it's been waiting. Roadmap docs (like `an active project roadmap doc`) should be able to query this state inline.

3. **Sign-off discipline.** The transition `PENDING-REVIEW` → `COMPLETED` requires an explicit user-attributed reviewed-by/reviewed-on annotation in the plan or a companion review file. Prevents the agent from silently flipping it on the user's behalf.

4. **Roadmap-aware archival.** Plans that are owned by an active roadmap (e.g., `an active project roadmap doc`) should not auto-archive on `PENDING-REVIEW` — they stay reachable from the roadmap until the user signs them off and the roadmap itself updates the link. Otherwise the user loses the "where are we on the roadmap" overview that the roadmap doc is supposed to provide.

These requirements push HARNESS-GAP-06 from a small Status sentinel to a small subsystem (status semantics + dashboard generator + review annotations + roadmap-awareness). Scope it as a multi-phase plan when picking up. P1.

### HARNESS-GAP-07 — `plan-lifecycle.sh` doesn't recognize YAML frontmatter Status

Surfaced 2026-04-24 during a downstream plan-staleness sweep Phase 1 closures. The hook's awk pattern `/^Status:[[:space:]]*[A-Za-z][A-Za-z0-9_-]*/` matches only the standard `Status: ACTIVE` line at the top of a plan. It does NOT match YAML frontmatter format where the field is `status: ACTIVE` (lowercase) inside a `---` block. Reference instance: a kanban-engine-generated plan in a downstream project had to be manually `git mv`'d to archive because flipping its YAML frontmatter `status:` to `COMPLETED` did not trigger the hook. Two fix options: (a) extend the hook's awk pattern to also recognize YAML frontmatter `status:` lines (case-insensitive), OR (b) add a pre-commit hook (`plan-format-normalizer.sh`) that detects YAML frontmatter plans and either rewrites them to standard format or refuses the commit with a message pointing at the standard. Option (a) is non-invasive but legitimizes two formats; option (b) forces consistency. Light P2 — rare format outside the kanban-engine pipeline, but the inconsistency surprises operators when archives don't auto-fire.

## Improvements surfaced by 2026-04-22 strategy review

Prioritized order of leverage. Full reasoning in `docs/claude-code-quality-strategy.md` section "Additional Suggestions for Improvement."

### P0 — Harness-tests-itself: synthetic session runner

Build a tool that runs synthetic Claude Code sessions against known-bad scenarios and measures whether hooks catch them (unauthorized checkbox flip, mocked integration test, uncited feature claim, budget exhaustion without audit). Runs on demand or weekly via `/schedule`. Produces a report showing which enforcement mechanisms have regressed. This catches silent enforcement regressions — currently invisible.

### P2 — Claude Code doesn't dynamically load new agents OR hooks added mid-session

Surfaced 2026-04-23. Two confirmed instances of the same root cause:

- **Agents:** the `plan-phase-builder` agent file exists at both `~/.claude/agents/plan-phase-builder.md` and `adapters/claude-code/agents/plan-phase-builder.md`, but a session that started before the file was added returns "Agent type 'plan-phase-builder' not found" when invoked via the Task tool. Workaround: use `general-purpose` agent with orchestrator-pattern discipline inlined in the prompt.
- **Hooks:** the `plan-deletion-protection.sh` hook was registered via `jq` into `~/.claude/settings.json`'s PreToolUse Bash matcher mid-session. A subsequent `rm docs/plans/dpc-test.md` (which the hook should BLOCK per its self-test scenario 1) was NOT blocked — the file was deleted with exit code 0. The hook's `--self-test` passes 14/14 in a fresh subprocess invocation, proving the hook logic is correct. The session simply isn't aware of the new hook registration. Workaround: end and re-start the session (or rely on next-session activation, which is acceptable for non-urgent enforcement additions).

Mitigation candidates:
- (a) Document the limitation in `harness-maintenance.md` so future Claude sessions know to restart after adding new agents.
- (b) SessionStart hook that re-scans `~/.claude/agents/` and writes a "missing agents" warning if any expected agent isn't loaded — surface staleness without forcing a restart.
- (c) Investigate whether Claude Code has an agent-reload command; if so, document it.

Low priority because the workaround (general-purpose dispatch with inlined discipline) is functional and the issue resolves on next session start.

### P1 — Class-aware reviewer feedback Mod 2: pre-commit class-sweep attestation hook

Deferred from the original bundled "Class-aware reviewer feedback (narrow-fix bias mitigation)" entry on 2026-04-23. Mods 1 + 3 of that entry are absorbed by the `class-aware-review-feedback` plan. Mod 2 stays in the backlog pending evidence that Mods 1+3 alone don't fully close the narrow-fix-bias pattern.

**Pattern this would address:** adversarial reviewers identify named instances; LLM builders fix the named instances; sibling instances of the same defect class slip; next pass surfaces a sibling; loop. Surfaced across 5 `systems-designer` iterations on the `capture-codify-pr-template` plan (2026-04-23). Affects every adversarial-review loop in the harness.

**Proposal:** New PreToolUse hook `class-sweep-attestation.sh` (matching `git commit`) that detects fix-commits — message contains "amend" / "fix" / "address review" AND a prior reviewer FAIL exists in `~/.claude/state/reviews/`. Requires the commit message to include a `Class-sweep: <pattern> — N matches, M fixed` line. Blocks commit otherwise. Estimated effort: ~6 hrs (with self-test); existing `bug-persistence-gate.sh` is a good template.

**Trigger to revive:** if after `class-aware-review-feedback` ships, an adversarial-review loop still produces 3+ rounds of FAIL where each round surfaces a sibling instance of a defect class the prior round was supposed to address, that's the signal to ship Mod 2. Until then, the prose-layer interventions (Mod 1 + Mod 3) are believed sufficient.

### P1 — Verify class-aware reviewer feedback in next session (live agent invocation) (2026-04-23)

The `class-aware-review-feedback` plan completed Task A.10 with the smoke-test fixture at `docs/plans/class-aware-review-feedback-smoke-test-plan.md` and a sweep-query verification (9 matches against the seeded class), but could NOT live-invoke the modified `systems-designer` agent because (a) sub-agents dispatched as `plan-phase-builder` lack the Task tool (P1 above), and (b) agent definitions are loaded at session start, so in-session prompt edits don't activate until the next session (P2 below). Next-session work: invoke the modified `systems-designer` agent on the smoke-test fixture (or a fresh equivalent) and verify the agent output contains the six-field block structure (`Line(s):`, `Defect:`, `Class:`, `Sweep query:`, `Required fix:`, `Required generalization:`) for at least the seeded `generic-placeholder-section` defect class. Compare the agent's emitted sweep query against the expected sweep query in the evidence file's section C. If the agent does NOT reliably emit the six-field structure, that's the signal to either tighten the prompt language or escalate to Mod 2 (the pre-commit `class-sweep-attestation.sh` hook above). After verification, the throwaway smoke-test fixture file can be deleted.

### P1 — Prompt template library for meta-questions

Codify canonical meta-questions as slash commands or skills: `/why-did-this-bug-slip`, `/find-my-bugs`, `/make-this-plan-verbose`, `/harness-this-lesson`. Currently these patterns live in individual memory; codifying makes them reusable and consistent.

### P1 — Delegability classification on plan tasks

Every plan task declares: fully-delegable / review-at-phase / interactive. Shapes dispatch automatically — fully-delegable auto-dispatches to background sessions, review-at-phase produces PRs at phase boundaries, interactive stays in foreground. Replaces per-task manual routing decisions.

### P1 — Explicit interactive vs autonomous session mode

Session-start directive declaring interactive (human watching; more permissive) or autonomous (human not watching; stricter gates, auto-commit plans, harder enforcement). Same cadence shouldn't apply to both modes.

### P2 — Effort-level enforcement at project level

`.claude/minimum-effort.json` in project root declares minimum effort level. SessionStart hook warns if effort is below project minimum. Eliminates "forgot to set max" errors on quality-critical projects.

### P2 — Multi-model routing strategy

Codify model assignment per task type: Opus for planning/adversarial review/judgment; Sonnet for implementation; Haiku for mechanical operations. Partially done via individual agent frontmatter; could be more systematic via a central routing config.

### P2 — Scheduled retrospectives via `/schedule`

Weekly scheduled agent that reads the week's completed plans, decisions, and failure-mode entries; proposes harness improvements based on patterns; drafts `docs/retrospectives/YYYY-WW.md`. Turns ad-hoc "half my time on the harness" into systematic weekly attention.

### P2 — Session observability dashboard

Lightweight `claude-status` command aggregating active sessions (local + `--remote`), active plans, tool-call budget consumption, recent hook firings, uncommitted work at risk of wipe. Aggregates existing state files — no new infrastructure needed.

### P2 — Harness version contracts

Each project declares `harness-version: >=N` in its CLAUDE.md. Breaking harness changes bump the version. SessionStart warns if project version predates current harness. Prevents silent regressions as harness evolves beyond what older projects expected.

### P2 — Validate Decision 011 Approach A end-to-end via real `claude --remote` session (2026-04-23)

Plan #4 (`docs/plans/claude-remote-adoption.md`) Phase B set up Approach A on a reference downstream project (a small work-account demo repo on GitHub) — `.claude/` directory exists in that project's working tree with the harness committed-copy form per Decision 011, but the `git commit` and `git push` were deferred because the reference repo had no configured user identity and the builder did not have authority to set it.

Required user action:
1. From the reference project's directory: confirm the appropriate git identity is set (one-time per-machine), then `git add .claude/ && git commit -m "chore: adopt Neural Lace harness via project .claude/ (Decision 011 Approach A)" && git push`.
2. Launch `claude --remote "list every rule loaded for this session and confirm any one hook fires"` against the reference project's pushed branch.
3. Confirm: (a) cloud session enumerates the rules in `.claude/rules/` matching the local set, (b) at least one hook from `.claude/settings.json` fires during the session, (c) `task-verifier` agent is dispatchable from the cloud session.
4. If any of (a)/(b)/(c) fails, file the failure mode against Decision 011 — Approach A may need refinement (e.g., symlink fallback, settings.json adjustments for cloud).

This is the integration test referenced in Decision 011's Test Plan section, and the empirical validation deferred from Phase A.



### P1 — Mysterious `effortLevel` wipe during session (2026-04-22/23)

Observed: `~/.claude/settings.json` started the session with `effortLevel: "max"`. Partway through, a subsequent `jq -r '.effortLevel'` returned `null` (key removed or value nulled). No task in the executing plan intentionally touched this field. Neither the main session nor any dispatched builder agent reported editing it.

Plausible causes:
- A PreToolUse or PostToolUse hook silently normalizing settings.json (e.g., a JSON rewriter that drops unknown keys)
- A concurrent session on the same machine overwriting settings.json with an older version (the concurrent-session state collision pattern we already have logged)
- An `install.sh` re-run during the session restoring from a template that had the key but was processed incorrectly
- A tool call with a full-file Write to settings.json that didn't preserve the effortLevel field

Remediation needed:
- Audit every hook that reads/writes `~/.claude/settings.json` for normalization that could drop top-level keys
- Consider adding a SessionStart hook that snapshots `settings.json` to `~/.claude/state/settings-snapshot.json` and, on next SessionStart, diffs against the current file to surface silent mutations
- Document the root cause once identified, then add a test/guard

Until fixed: users should periodically check `jq -r '.effortLevel' ~/.claude/settings.json` is not `null`. The existing `effort-policy-warn.sh` hook catches this indirectly (will warn if env var is unset and settings is missing the key AND policy requires non-low).

### P1 — Harness-work plans have no tracked home

Per `harness-hygiene.md`, the harness repo adds `docs/plans/` to `.gitignore` (harness repos don't ship instance artifacts). But harness-dev work DOES produce plan files, and those plans have no naturally-tracked home:

- `neural-lace/docs/plans/` — gitignored; plans there survive locally but aren't protected from `git clean`
- `~/.claude/plans/` — outside any git repo; plans there survive git operations anywhere but aren't version-controlled or shareable

Encountered 2026-04-22: wrote `harness-quick-wins-2026-04-22.md` to `neural-lace/docs/plans/`, hit the `.gitignore` at commit time, moved to `~/.claude/plans/` which is outside any repo.

Options to resolve:
- **Separate harness-dev repo:** e.g., `neural-lace-dev` or similar, tracking only the working plans/decisions/sessions for harness evolution. Isolates instance artifacts from shareable harness code.
- **Carve-out within neural-lace:** a `docs/internal-plans/` (not gitignored) specifically for harness-dev plans. Weakens the hygiene guarantee (contributors may leak identifiers), requires reviewer vigilance.
- **Accept `~/.claude/plans/`:** formalize this as THE location for harness-dev plans. Add a README there explaining the convention. Plans are local-only by design; cross-machine collaboration requires explicit git init + separate repo setup by the contributor.

Recommendation pending: option 3 (accept local-only) is cheapest and matches actual practice. Options 1-2 are correct for a growing contributor base.

### P2 — Bug-persistence gate should recognize cross-repo persistence

The `bug-persistence-gate.sh` hook scopes its check to the current project's `docs/backlog.md` or `docs/reviews/`. When trigger phrases reference harness-level concerns and persistence legitimately happens in the neural-lace repo, the hook still fires against the project cwd.

Two possible fixes:
- **Harness-aware scoping:** check both the current project's `docs/` AND `~/claude-projects/neural-lace/docs/backlog.md` when trigger phrases reference harness concerns (would require classifying trigger phrases as project-level vs harness-level)
- **Cross-repo persistence attestation:** explicit sentinel file (e.g., `.claude/state/persisted-elsewhere-<hash>.txt`) carrying the commit SHA of the cross-repo persistence; similar to the existing `--ack` pattern

Workaround pattern (used 2026-04-22): write a dated review file in the current project's `docs/reviews/` that points at the authoritative persistence location. Works but requires the agent to remember to do it.

### P2 — Pre-existing harness-mirror drift between `~/.claude/` and `adapters/claude-code/` (surfaced 2026-04-24)

While building the failure-mode catalog plan (`docs/plans/failure-mode-catalog.md`), the harness-maintenance diff loop surfaced 25 pre-existing files that DIFFER between `~/.claude/` and `adapters/claude-code/`, plus 4 files MISSING from the repo. The drift is unrelated to the catalog plan and was already present at branch base. Affected categories: 7 agents, 11 rules, 7 hooks/skills/templates. Until reconciled, the harness-maintenance diff loop produces a noisy baseline that masks new drift.

**Fix:** dedicated reconciliation pass — for each DIFFERS file, decide which side is canonical (the live `~/.claude/` typically reflects the most recent thinking) and re-mirror. For the 4 MISSING files (`templates/completion-report.md`, `templates/decision-log-entry.md`, `skills/pt-implement.md`, `skills/pt-test.md`), copy to the repo. Then the diff loop returns clean and any future drift is immediately visible.

### P2 — capture-codify: detect FM-NNN-cited-but-doesn't-exist (2026-04-23)

Surfaced during planning of `docs/plans/capture-codify-pr-template.md` Section 6 ("Observability gaps"). Currently when a PR's mechanism field selects answer form (a) "Existing catalog entry" and cites `FM-NNN`, neither the CI workflow nor the local pre-push hook checks whether `FM-NNN` actually exists in `docs/failure-modes.md` at PR open time. A typo (`FM-001` vs `FM-100`) or a stale citation slips through silently — the PR passes the validator but the cite is dangling.

**Proposal:** extend the validator library (`.github/scripts/validate-pr-template.sh`) to optionally cross-reference any `FM-\d+` substring in the (a) section against `docs/failure-modes.md` headings (`^## FM-\d+`). On miss, emit a soft warning (`[pr-template] WARN: cited FM-NNN not found in catalog`) without failing the check — reviewer responsibility for now, but the warning makes the gap visible. Hard-fail later if false-positive rate is low.

**Effort:** ~1 hour (single regex addition, self-test cases for hit/miss/no-cite). Existing validator structure makes this trivial.

### P2 — capture-codify: answer-form distribution telemetry (2026-04-23)

Surfaced during planning of `docs/plans/capture-codify-pr-template.md` Section 6. The mechanism field has three answer forms (a / b / c). Tracking the distribution over time would surface meaningful patterns: a sudden spike in (c) "no mechanism" answers signals discipline drift; a steady stream of (b) "new entry proposed" with no follow-up catalog growth signals a broken capture-codify cycle.

**Proposal:** extend `adapters/claude-code/scripts/audit-merged-prs.sh` to count (a/b/c) selections per PR and emit a distribution summary alongside the per-PR PASS/FAIL output. Optionally feed the counts into the weekly `/harness-review` skill's compliance section.

**Effort:** ~2 hours. The validator library already detects answer-form selection in `detect_answer_form()`; surfacing it from the audit script is a single counter loop.

### P2 — capture-codify: pre-commit atomicity gate for template ↔ validator edits (2026-04-23)

Surfaced during planning of `docs/plans/capture-codify-pr-template.md` Section 7 (failure-mode row "Accidental template-file edit"). The validator library expects specific section headings and placeholder text in `.github/PULL_REQUEST_TEMPLATE.md`. If a maintainer edits the template (e.g., changes wording while editing nearby files) without updating the validator's regex constants, the validator silently breaks — the next PR after the edit fails CI unexpectedly with a confusing message.

**Proposal:** new pre-commit hook `template-validator-atomicity-gate.sh` that detects when `.github/PULL_REQUEST_TEMPLATE.md` is staged AND `.github/scripts/validate-pr-template.sh` is NOT staged in the same commit; blocks with a stderr message naming the rule. Mirror of the existing `decisions-index-gate.sh` atomicity pattern.

**Effort:** ~3 hours. Existing atomicity gate (`decisions-index-gate.sh`) is a direct template; copy + adapt regex + write self-test.

## Existing entries

## ✅ DELIVERED 2026-04-20 — Mechanical enforcement of bug-persistence rule

Shipped in commit `0090d4b`: `hooks/bug-persistence-gate.sh` Stop hook wired into `settings.json.template`. Scans session transcript for trigger phrases, checks `docs/backlog.md` + `docs/reviews/` for persistence, blocks session end if bugs mentioned without being recorded. Attestation escape hatch via `.claude/state/bugs-attested-*.txt`. Documented in `docs/harness-architecture.md`.

## P1 — Consolidated findings rollup on session end

Related to the bug-persistence hook: a skill or helper that, at session end, reads all `docs/reviews/YYYY-MM-DD-*.md` files + recent git log for `docs/backlog.md` changes, and produces a single `docs/sessions/YYYY-MM-DD-session-summary.md` cataloging every finding + its disposition (fixed in commit X / deferred to backlog entry Y / invalid).

## P1 — Hardening of existing self-applied rules

Several rules in `~/.claude/rules/` are Pattern-level (no hook enforcement) and depend on agent discipline. Audit them for which ones are violated most often in practice, and propose Mechanism-level enforcement (hook / schema / assertion) for the top offenders. Candidates from observation:

- `planning.md`'s "Identifying a gap = writing a backlog entry, in the same response" — violated on 2026-04-20
- `orchestrator-pattern.md`'s "Main session dispatches, doesn't build directly" — violated when main session is tempted by small edits
- `testing.md`'s "E2E testing after system-boundary commit" — often skipped when under time pressure

## P0 — Stop hook for "narrate-and-wait" pattern (new 2026-04-21)

Counterpart to bug-persistence-gate: catch the pattern where the agent
completes a unit of work, narrates a summary, and implicitly stops
waiting for user confirmation. Specifically blocks session termination
when the last N assistant turns contain trigger phrases like "next up
is", "ready to continue", "want me to proceed", "after merge", "then
I'll" — indicating the agent has queued up work it could be doing now
but is pausing to announce.

Scope ~3 hrs: Stop hook script, transcript regex, allowlist for genuine
end-of-session summaries (e.g., "done for tonight", explicit /clear
requests, explicit "stop" from user).

This was added after the maintainer repeatedly observed the agent
stopping mid-execution on 2026-04-21 and asking rhetorical "are you
still working?" questions.

---

## HARNESS-GAP-15 — ABSORBED 2026-05-04 into `docs/plans/phase-1d-e-4-gap-15-cleanup.md` (sub-items A/B/D/E/F; sub-item C deferred to next master merge)

(Historical entry preserved below for context.)

## HARNESS-GAP-15 — Phase 1d-E public-release-hardening + harness-quick-wins audit-cleanup (added 2026-05-04)

**Source.** 2026-05-04 stale-plan audit. Three plans were marked COMPLETED but two had falsely-complete state (the third — `document-freshness-system.md` — verified ACTUALLY COMPLETE and stays archived). The two that were prematurely marked are now flipped back to ACTIVE; this gap aggregates their resolution paths with related Phase 1d-E hygiene work into a single rollup so they ship as one focused phase.

**Sub-items (P2 unless noted):**

**A — IMPLEMENTED 2026-05-04 via Phase 1d-E-4** (commit f112226). Scanner self-test repaired; assertion flipped to exit 1 on `docs/plans/foo.md`; two new assertions added for the allow-list behavior. Self-test PASS today.

**B — IMPLEMENTED 2026-05-04 via Phase 1d-E-4** (commit f112226). Scanner exemption tightened: directory-level exemption applies ONLY to non-allow-listed paths within `docs/decisions/`, `docs/reviews/`, `docs/sessions/`. Committed allow-listed files (`NNN-*.md`, `YYYY-MM-DD-*.md`) ARE scanned. Full-tree scan after the fix correctly reports 15 codename hits in committed decision/review files — these are the pre-existing leakage tracked in sub-item C below.

**C — Codename scrub from feature-branch commits before next master merge (P2, deferred).** Public feature branches currently contain identifying codenames + the maintainers GitHub usernames in tracked decision/review files. Specific identifiers redacted from this entry per the hygiene-scan denylist; see the 2026-05-04 audit conversation transcript for the actual strings. **Right-sized severity: P3 distribution-readiness/hygiene concern, NOT a security incident** — no credentials/tokens/secrets in the leak; identity-correlation already trivially derivable from public commit author fields. Cleanup approach: at next master-merge time, scrub the merging diff of identifiers OR rebase the merging branch through orphan-commit (Phase 8 pattern). Force-pushing the public feature branch is rejected per the right-sized threat model — unnecessary urgency. Effort: ~1 hr per merge; integrates with normal merge workflow.

**D — IMPLEMENTED 2026-05-04 via Phase 1d-E-4** (commit 22c0e65). Schema authored at `adapters/claude-code/schemas/automation-mode.schema.json` per the original Task 6.1 spec — `{version, mode, deploy_matchers}` with version: 1 sentinel matching the existing four schemas. Validates against the example.json that already shipped.

**E — IMPLEMENTED 2026-05-04 via Phase 1d-E-4.** `public-release-hardening.md` flipped to COMPLETED; auto-archived. Honest annotations on the four previously-unchecked tasks: 1.2 scoped down per Option A; 4.2 shipped via HARNESS-DRIFT-02; 5.3 deferred with rationale; 6.1 shipped in commit 22c0e65. Plan file is gitignored, but the audit closure section is preserved in working tree.

**F — IMPLEMENTED 2026-05-04 via Phase 1d-E-4** (commit ff5717d). `harness-quick-wins-2026-04-22.md` flipped to COMPLETED; auto-archived. Phase A Task 1 deferred with rationale: per-project `effort-policy-warn.sh` covers most of the value; global default flip is a personal-cost change that should happen interactively. 17 of 18 tasks remain shipped.

**G — Phase 1d-E rollup (HARNESS-GAP-14 + HARNESS-GAP-15 + HARNESS-GAP-10 sub-gaps A/B/C/F/G/H + HARNESS-GAP-13).** When Phase 1d-E is planned, bundle these into a single coherent plan so the audit-cleanup work ships as one phase with one shared verification pass.

**Effort estimate.** S-M for A/D/F individually; M for B (depends on what new findings the tightened scanner surfaces); incremental cost for C (zero now, ~1 hr at next merge); A+B+D+E+F together: ~4-6 hr of focused work. G is the planning step, ~30 min.

**Class.** `falsely-marked-complete-plan` (sub-class of `stale-state-claim`). The 2026-05-04 audit caught the pattern; the resolution path here closes the specific instances + restores the post-conditions the plans claimed.

**Cross-references.**
- Audit findings: this session's transcript (2026-05-04 conversation about stale plans)
- The two un-archived plans: `docs/plans/harness-quick-wins-2026-04-22.md`, `docs/plans/public-release-hardening.md`
- The third plan (verified complete, stays archived): `docs/plans/archive/document-freshness-system.md`
- Companion gaps: HARNESS-GAP-14, HARNESS-GAP-13, HARNESS-GAP-10 sub-gaps A/B/C/F/G/H
