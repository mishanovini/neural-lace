# Rules-vs-hooks audit (NL-self-review)

**Date:** 2026-05-04
**Triggered by:** Phase 1d-E-2 Task 4 (audit gap from sub-gap F of the build-doctrine audit)
**Source files audited:** every `.md` file in `~/.claude/rules/` except already-stub `vaporware-prevention.md`

## Methodology

For each rule file, I read top-to-bottom (or skimmed major sections for files >500 lines) and asked, per major section: "Is this section's content enforced by a hook in `~/.claude/hooks/`?" — meaning a `.sh` file there fires a mechanical block, warning, or audit on the behavior the section prescribes.

Hook-enforcement evidence:
- A hook name + matcher event referenced inline in the rule file (load-bearing — explicit cross-reference).
- A hook whose script body matches the rule's prescribed behavior (verified by reading the hook).
- An "Enforcement summary" or "Enforcement map" table inside the rule body that names the hook.

Rule sections that are **principles, philosophy, or self-applied workflow** (without a corresponding hook) count as Pattern-only — non-hook-enforced.

**Percentage estimation:** I counted major sections (top-level `##` headings) and estimated what fraction of each rule's prose is hook-enforced. Estimates are coarse — within ±15% — but the intra-rule ratio is what drives the recommendation, so precision past that doesn't matter.

**Recommendation thresholds:**
- **Convert to stub** (mirror `vaporware-prevention.md`): >70% hook-enforced AND the rule's value is mostly the enforcement map, not the narrative.
- **Split into stub + extension**: 40-70% hook-enforced AND the non-mechanism content is substantive enough to warrant its own document.
- **Keep verbose**: <40% hook-enforced OR the rule is primarily Pattern (workflow / principles) where prose IS the value.

## Per-rule audit

| Rule file | Lines | ~ % hook-enforced | Notes | Recommendation |
|---|---|---|---|---|
| `acceptance-scenarios.md` | 87 sections, ~200 lines of substance | ~60% | Plan-time advocate review (Pattern), runtime advocate (`product-acceptance-gate.sh` Stop hook position 4 — Mechanism), exemption mechanism (`plan-reviewer.sh` + the gate honor `acceptance-exempt: true` — Mechanism), gap-analyzer convergence loop (Pattern). The "Enforcement summary" table at the bottom names 5 mechanism rows + 2 pattern rows. | **split** — the runtime gate + exemption mechanism could become a stub; the plan-time discipline + scenarios-shared-assertions-private + scenario format spec are substantive Pattern content. |
| `agent-teams.md` | ~250 lines | ~50% | Hook-enforced: `teammate-spawn-validator.sh`, `task-created-validator.sh`, `task-completed-evidence-gate.sh`, team-aware `tool-call-budget.sh`, `plan-edit-validator.sh` flock, `product-acceptance-gate.sh` multi-worktree. Pattern-only: when-to-use decision tree, Spawn-Before-Delegate workaround, in-process vs pane-based tradeoffs, inbox-deferral guidance. The five upstream Anthropic bug workarounds are inherently Pattern. | **split** — hook table → stub; bug-workaround narrative + decision tree → extension. |
| `api-routes.md` | 11 lines | ~0% | Six numbered mid-build self-applied checks for API route changes. None hook-enforced (no API-route-specific hooks exist). Pure Pattern. | **keep verbose** (already terse). |
| `automation-modes.md` | ~330 lines | ~5% | Decision tree for picking among 5 session modes. None of the modes themselves are hook-enforced — the rule is purely about choosing where a session runs. The only hook-adjacent content is a per-mode "Setup prerequisites" table that references which hooks fire in which mode (not "this rule is enforced by hook X"). | **keep verbose** (entirely Pattern; high prose value). |
| `database-migrations.md` | 24 lines | ~0% | Six numbered checks (count rows, NOT NULL handling, RLS, verification, enum-check). None hook-enforced. Project-specific Supabase CLI commands. | **keep verbose** (already terse). |
| `deploy-to-production.md` | 51 lines | ~0% | "Always deploy to production unless asked otherwise." Pattern only — explicitly stated as such in the "Enforcement" section ("This is a Pattern rule, not hook-backed."). | **keep verbose** (already terse, explicit Pattern). |
| `design-mode-planning.md` | ~360 lines | ~50% | Mechanism: `plan-reviewer.sh` enforces section presence + Check 8A audit-section structure; `systems-design-gate.sh` PreToolUse blocks design-mode file edits without an active Mode: design plan; `systems-designer` agent reviews substance. Pattern-only: 10-section content guide (what each section requires), pre-submission audit S1-S5 sweep methodology, quantitative-claims discipline, cold-start inheritance, ID precision, "stays identical" enumeration. The Enforcement Summary table names the split explicitly. | **split** — hook list + reviewer-agent gate → stub; 10-section guide + audit methodology → extension. |
| `diagnosis.md` | 71 lines | ~0% | "Read the full stack before fixing." Process steps, "After Every Failure: Encode the Fix" loop, class-sweep procedure, user-correction handling. Pattern only — there's no diagnosis-enforcement hook. The class-sweep discipline is referenced by adversarial-review agents but the rule itself isn't hook-enforced. | **keep verbose** (entirely Pattern). |
| `discovery-protocol.md` | ~270 lines | ~30% | Mechanism: extended `bug-persistence-gate.sh` accepts `docs/discoveries/`; `discovery-surfacer.sh` SessionStart hook surfaces pending discoveries. Pattern: the typology, the file format, the propagation-target table, the decide-and-apply discipline, the educational format for surfacing decisions, the lifecycle. Heavy on Pattern; the two hooks are infrastructure that supports the protocol but don't enforce its core (typology, decide-and-apply, propagation). | **keep verbose** — the Pattern content is the load-bearing part. |
| `documentation.md` | 11 lines | ~0% | Seven brief checks for doc comments, API documentation, .env.example. None hook-enforced (no doc-comment hooks). | **keep verbose** (already terse). |
| `git.md` | 11 lines | ~50% | Hook-enforced: pre-push scanner blocks dangerous patterns, scope-enforcement-gate blocks force-push to master, no `--no-verify` (inline PreToolUse Bash blockers per `vaporware-prevention.md` table). Pattern-only: commit-cadence discipline, customer-tier branching, PR description content, no-uncommitted-at-session-end. | **keep verbose** (already terse — both Pattern and Mechanism content fit in 11 lines). |
| `harness-hygiene.md` | ~150 lines | ~40% | Mechanism: `harness-hygiene-scan.sh` denylist-pattern pre-commit scan; `harness-reviewer` agent. Pattern-only: what counts as sensitive, two-layer config conventions, downstream-vs-harness instance distinction, idempotent install, functional placeholders, faker fixtures. The denylist scan is *narrow* (specific patterns); the discipline is wide. | **keep verbose** — Pattern content (what to never ship, why, how) is the load-bearing guidance; the hook only enforces a specific subset (denylist matches). |
| `harness-maintenance.md` | 50 lines | ~10% | "Default to global, commit to neural-lace, sync verification." `check-harness-sync.sh` SessionStart warning is the only hook-adjacent piece. Mostly process narrative. | **keep verbose** (already terse). |
| `observed-errors-first.md` | 45 lines | ~80% | `observed-errors-gate.sh` PreToolUse on `git commit` is the entire enforcement story. The rule's narrative is the *why* (the 2026-04-25 incident, the friction-of-formatted-error logic), the file format, the override env var. The hook does the work. | **convert to stub** — rule is "fix-class commits require an entry in `.claude/state/observed-errors.md` from this session; hook enforces. See `hooks/observed-errors-gate.sh`." Plus a brief format spec. The narrative origin story is valuable but could move to an ADR. |
| `orchestrator-pattern.md` | ~510 lines | ~10% | Section "Enforcement status (honest)" explicitly states this is "a Pattern-class harness rule, not a Mechanism. It is NOT hook-enforced and there is no mechanical gate that detects 'main session is building directly instead of dispatching.'" The mechanisms named (`task-verifier`, `tool-call-budget.sh`, `pre-stop-verifier.sh`, `plan-edit-validator.sh`) all fire identically whether main session or sub-agent does the work. The rule is fundamentally about coordination shape, not gate behavior. | **keep verbose** (Pattern by design; explicitly declared so in the rule itself). |
| `planning.md` | ~1100 lines | ~35% | Mixed bag. Hook-enforced: `plan-reviewer.sh` (section presence + substance), `plan-edit-validator.sh` (evidence-first checkbox), `task-verifier` mandate, `plan-lifecycle.sh` (auto-archive), `plan-status-archival-sweep.sh` (session-start safety net), `backlog-plan-atomicity.sh`, `decisions-index-gate.sh`, `pre-stop-verifier.sh`. Pattern-only: when-to-plan judgment, philosophy ("Completeness over speed"), strategy-before-planning, mid-build decision tiers (Tier 1/2/3), agent-team vs orchestrator decision tree, completion report structure, capture-codify at PR time (Mechanism via `validate-pr-template.sh`), session retrospective. The rule is the central planning narrative; ~65% is workflow guidance that no hook captures. | **keep verbose** — central rule, prose is load-bearing. Already has explicit "Enforcement summary" tables for the hook-enforced sub-rules (e.g., "Stage 3.5: Session-start safety-net sweep" names the sweep hook). |
| `react.md` | 7 lines | ~0% | Five terse React/Next.js rules. No hooks. | **keep verbose** (already terse). |
| `security.md` | 35 lines | ~30% | Mechanism: `pre-push-scan.sh` enforces credential patterns. Pattern-only: software install discipline, public repo ban, credential rules. The pre-push scanner covers credential patterns; everything else is Pattern. | **keep verbose** (already terse; Pattern content is load-bearing). |
| `testing.md` | 162 lines | ~50% | Mechanism: `narrate-and-wait-gate.sh` (keep-going), `bug-persistence-gate.sh` (durable storage), `no-test-skip-gate.sh` (test skips), `pre-commit-tdd-gate.sh` (test discipline), `review-finding-fix-gate.sh` (review-finding ↔ fix-commit). Pattern-only: E2E discipline, pre-commit code-reviewer dispatch, UX validation 3-agent dispatch, link/consistency/Playwright audit commands (project-specific scripts), deployment validation, purpose validation. The four MANDATORY sections at the top are all hook-backed. The bottom half is process / project-specific commands. | **split** — the four MANDATORY sections (each with explicit "Enforcement: hook X") could become a stub; the E2E + UX validation + project-specific audit commands are substantive Pattern that should keep the verbose form. |
| `typescript.md` | 7 lines | ~0% | Seven TypeScript rules. No TypeScript-specific hooks. | **keep verbose** (already terse). |
| `ui-components.md` | 22 lines | ~0% | Five numbered checks for UI prop tracing, conditional rendering, click handlers, dynamic styles. No hooks. | **keep verbose** (already terse). |
| `url-conventions.md` | ~80 lines | ~0% | Project-style URL convention (contractor-flat / `/admin/` / `/admin/orgs/[orgId]/`). Explicitly stated as Pattern-only in "Classification" line. No hooks. | **keep verbose** — explicitly Pattern. (Sidenote: this rule is project-specific to a particular dual-org product. May warrant separate audit re: harness-hygiene.) |
| `ux-design.md` | 11 lines | ~0% | Seven UX principles. No hooks. | **keep verbose** (already terse). |
| `ux-standards.md` | 102 lines | ~0% | Color rules, contrast mandates, state handling, AI features. No hooks (no UI-component scanner). | **keep verbose** (entirely Pattern; visual-design guidance). |

## Recommendations summary

**Convert to stub (>70% hook-enforced, narrative is mostly the enforcement map):**
- `observed-errors-first.md` — single-hook rule with prose explaining why; stub + format spec is sufficient.

**Split into stub + extension (40-70% hook-enforced, both halves substantive):**
- `acceptance-scenarios.md` — runtime gate + exemption → stub; plan-time advocate + scenario format → extension.
- `agent-teams.md` — hook table → stub; bug workarounds + decision tree → extension.
- `design-mode-planning.md` — hook + reviewer gate → stub; 10-section guide + audit methodology → extension.
- `testing.md` — MANDATORY sections (each hook-backed) → stub; E2E + UX validation + project audit commands → extension.

**Keep verbose (Pattern-heavy or already terse):**
- `api-routes.md`, `automation-modes.md`, `database-migrations.md`, `deploy-to-production.md`, `diagnosis.md`, `discovery-protocol.md`, `documentation.md`, `git.md`, `harness-hygiene.md`, `harness-maintenance.md`, `orchestrator-pattern.md`, `planning.md`, `react.md`, `security.md`, `typescript.md`, `ui-components.md`, `url-conventions.md`, `ux-design.md`, `ux-standards.md`.

## Notes on the recommendations

**The stub-style format borrows from `vaporware-prevention.md`.** That file is the reference template: brief intro, enforcement-map table with one row per hook, residual-gap acknowledgment, anti-patterns. The conversion target is rules where the prose value is mostly an enumeration of "rule X is enforced by hook Y" — those rules become indexes into the hook layer rather than free-standing narratives.

**The split-into-stub-plus-extension format is heavier.** Two files: `<rule>.md` (the stub, with the hook map) and `<rule>-extension.md` (the Pattern content). The hook layer is the spine; the extension is the reference material a planner consults during plan-time work. This costs file-count and cross-reference complexity, so it's only worth it when the extension content is genuinely substantive and unlikely to merge into adjacent rule files.

**The conversion work itself is non-trivial and is OUT OF SCOPE for this audit.** This document declares which rules are candidates and what the recommended shape is. The actual restructuring (Edit each rule, write each stub, update cross-references in CLAUDE.md and harness-architecture.md and harness-guide.md, verify all hook references still resolve) is a follow-up plan. Conservatively: 5 rules × 2-4 hours each = 10-20 hours of restructuring work.

**Whether to actually restructure is a judgment call deferred to the user.** Stubs reduce duplication and make the hook layer the source of truth; verbose rules are better for at-a-glance reading and onboarding. The audit's recommendation is "these 5 rules are candidates" — not "restructure them now." A future session can take the recommendations as input to a prioritized restructuring plan.

## What didn't get audited (out of scope)

- **Project-level rules** (`<project>/.claude/rules/*.md`). This audit only covered global rules under `~/.claude/rules/`. Project-level rules are by definition project-specific and don't share the harness's hook layer.
- **The `comprehension-gate.md` rule** that was added 2026-05-04 — present in `~/.claude/rules/` but new enough that I treat its hook coverage as TBD pending Phase 1d-C-4 task completion.
- **Whether each declared "hook" actually exists.** Cross-referenced existence against `ls ~/.claude/hooks/` for the most commonly-named hooks; didn't verify every reference exhaustively. A future audit could catch any hallucinated hook names.
- **Whether the hook-enforcement is *correct*.** Audit is scope-shape only — does the hook fire on the prescribed behavior. Whether the hook actually catches what the rule wants is a separate quality question (Phase 1d-E-2 sub-gap A's orthogonality matrix is the closest existing instance).
