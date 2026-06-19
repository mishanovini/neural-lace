# Rules INDEX

Canonical inventory of every rule file under `adapters/claude-code/rules/`. The INDEX is intentionally short — one line per rule, full content lives in the per-rule file. Use this to discover what rules exist, what type of enforcement each provides, and when each fires.

**Enforcement types** (matching the convention in each rule's `**Classification:**` line and in `docs/best-practices.md`):

- **Mechanism** — hook- or schema-enforced. The rule's contract is mechanically checked at a specific tool-call or lifecycle boundary; bypassing requires `--no-verify` or an explicit override marker (and is itself caught by the server-side enforcement workflow once branch-protection is wired).
- **Pattern** — self-applied discipline. No hook detects violations; the rule lives in the agent's behavior and the user's interrupt authority. Often documented because the trigger (e.g., "the agent noticed friction") is not machine-observable.
- **Hybrid** — has both Mechanism and Pattern layers. The mechanical layer enforces shape/freshness/presence; the pattern layer carries the semantic correctness the mechanism cannot reach.
- **Convention** — short project-rule file (no `**Classification:**` line). Typically scoped to a specific surface — UI components, API routes, migrations, language standards. Enforcement is via developer / agent self-application plus surrounding hooks (e.g., the testing rule + `pre-commit-tdd-gate.sh`).

**Triggers** are summarized as one of:

- *Always* — applies to every session regardless of context.
- *Plan-time / Build-time / Stop-time* — fires at a specific session lifecycle stage.
- *Tool-scoped* — fires on a specific tool call (e.g., `git commit`, `Edit` of `docs/plans/*`, `gh repo create`).
- *Surface-scoped* — applies when the session is working on a specific surface (UI, API, migrations, harness-dev).

| Filename | Title | Type | Trigger | Last updated |
|---|---|---|---|---|
| `acceptance-scenarios.md` | Acceptance Scenarios — Adversarial Observation of the Running Product | Hybrid | Plan-time authoring + Stop-time runtime gate (`product-acceptance-gate.sh`) for non-exempt user-facing plans | 2026-04-27 |
| `agent-teams.md` | Agent Teams Integration | Hybrid | Surface-scoped — when `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` AND `~/.claude/local/agent-teams.config.json` `enabled: true` | 2026-05-09 |
| `api-routes.md` | Rules for API route changes (src/app/api/**) | Convention | Surface-scoped — editing `src/app/api/**` | 2026-04-18 |
| `automation-modes.md` | Automation Modes — Choosing Where a Claude Code Session Runs | Pattern | Plan-time / session-start — selecting interactive vs parallel vs cloud-remote vs scheduled vs agent-team | 2026-04-29 |
| `background-work-tracking.md` | Background-Work Tracking — A Launched Background Task Is a Tracked Obligation Until Its Result Is Consumed | Hybrid | Session-start (`stalled-work-surfacer.sh` surfaces stalled Workflow runs) + always (verify-before-claiming-running discipline) | 2026-06-13 |
| `calibration-loop.md` | Calibration Loop — Manual Bootstrap of the Knowledge Integrator Role | Hybrid | Operator-invoked via `/calibrate <agent-name> <observation-class> <details>`; roll-up via `/harness-review` Check 12 | 2026-05-05 |
| `claims.md` | Claims — Hypothesis-vs-Proof Labeling and Refutation Criteria | Pattern | Always — every causal claim in status updates, reports, evidence, ADRs must carry a PROVEN or HYPOTHESIZED tag | 2026-05-22 |
| `completion-criteria.md` | Feature-Completion Criteria — "Shipped" Means All Eight, Not Just Merged | Hybrid | Stop-time (`completion-criteria-gate.sh` fires on feature-shipment phrasing — requires a `## Completion Criteria` section accounting for all 8 criteria) + post-fact audit (`feature-completion-audit.sh`) | 2026-06-01 |
| `comprehension-gate.md` | Comprehension Gate — Builders Articulate Their Mental Model Before Commit at R2+ | Hybrid | Build-time (`task-verifier` invokes `comprehension-reviewer` when plan declares `rung: 2+`) | 2026-05-04 |
| `consolidation-discipline.md` | Consolidation Discipline — When Successive Turns Layer Corrections, Emit a Canonical Artifact | Pattern | Always — when agent guidance on one artifact has been revised across 2+ successive turns, emit a consolidated paste/action-ready version that supersedes prior guidance; self-throttle for noise; never silent | 2026-06-08 |
| `conv-tree-orchestrator-emit.md` | Conversation Tree — Orchestrator Auto-Emit (Four-Layer Enforcement) | Hybrid | Tool-scoped — every Dispatch spawn / conclude / cross-branch send (Layer A PreToolUse + SessionStart + Stop emits; Layer B reconciliation; Layer C heartbeat; Layer D agent self-application for cloud Dispatch out of local-hook reach) | 2026-05-23 |
| `workstreams-state.md` | Workstreams State — Write the Semantically True Tree, Not Just Any Well-Shaped Tree | Hybrid | Tool-scoped — `mcp__ccd_session__spawn_task` + `mcp__ccd_session_mgmt__start_code_task` spawn (Dispatch-only) | 2026-06-01 |
| `customer-facing-review.md` | Customer-Facing Review Gate (Stub — enforcement is in the hook) | Mechanism | Stop-time — `customer-facing-review-gate.sh` blocks session wrap when a customer-facing spawn was made without BOTH a UX-family agent AND `end-user-advocate` | 2026-06-02 |
| `database-migrations.md` | Rules for database migrations (supabase/migrations/**) | Convention | Surface-scoped — editing `supabase/migrations/**` | 2026-04-18 |
| `decision-context.md` | Decision-Context — Fence Grammar For Every Decision-Soliciting / Question-Asking / Action-Item-Assigning / Autonomous-Action-Logging Surface | Hybrid | Stop-time (`decision-context-gate.sh` Tier-1 hard-block) + UserPromptSubmit (`decision-context-reply-emit.sh` reply detection) + SessionStart (`decision-context-pending-surfacer.sh` + `decision-context-replay.sh`); Pattern at message-author time | 2026-05-29 |
| `definition-on-first-use.md` | Definition-on-first-use — Acronyms in Doctrine Docs Must Be Defined Before They're Used | Mechanism | Tool-scoped — `git commit` on a file under `neural-lace/build-doctrine/**/*.md` | 2026-05-04 |
| `deploy-to-production.md` | Deploy to Production — Default Behavior | Convention | Tool-scoped — `git push`, `gh pr merge`, `vercel deploy` etc. gated by `automation-mode-gate.sh` | 2026-05-14 |
| `design-mode-planning.md` | Design-Mode Planning Protocol | Hybrid | Plan-time (10-section analysis for `Mode: design`) + tool-scoped (`systems-design-gate.sh` blocks edits to design-mode files without a valid plan) | 2026-05-04 |
| `diagnosis.md` | Diagnosis Before Fixing | Convention | Always — investigation sessions; defines the DIAGNOSTIC-FIRST PROTOCOL (pull runtime/error logs as first tool call on any production-failure investigation) | 2026-05-22 |
| `discovery-protocol.md` | Discovery Protocol — Capture Mid-Process Learnings, Surface for Decision, Apply-and-Track | Hybrid | Session-start surfacer + Stop-time durable-capture (`bug-persistence-gate.sh` extension) | 2026-05-14 |
| `dispatch-relay-protocol.md` | Dispatch Relay Protocol — Dispatch Forwards, orchestrator-prime Orchestrates | Pattern | Surface-scoped — Dispatch sessions, once orchestrator-prime is live (forward to inbox / surface outbox; make no orchestration decisions) | 2026-06-02 |
| `documentation.md` | Rules for documentation (all files) | Convention | Always — applies to JSDoc/TSDoc, API doc shape, env.example, deprecated annotations | 2026-04-18 |
| `findings-ledger.md` | Findings Ledger — Class-Aware Observations Land in `docs/findings.md` | Hybrid | Tool-scoped — `git commit` modifying `docs/findings.md` (schema gate) + Stop-time durable-capture extension | 2026-05-04 |
| `friction-reflexion.md` | Friction-Reflexion — Notice Friction As It Arises, Surface It Immediately As a Suggestion For Discussion, Never Silently Act On It | Pattern | Always — every agent surfaces friction encountered in the natural course of work as plain-text discussion, never silent | 2026-05-15 |
| `gate-respect.md` | Gate-respect — Diagnose, Don't Bypass | Pattern | Always — every time a gate/hook/classifier blocks, the protocol is diagnose → apply structural fix → bypass only with explicit per-occurrence user authorization | 2026-05-14 |
| `git-discipline.md` | Git Discipline — Force-Push Prohibition, Post-Merge Sync, Stop-Hook Waivers, Staged-Set Verification | Hybrid | Tool-scoped — `git push --force` / `--force-with-lease` / `-f` (Pattern, no current hook); post-merge sync (Pattern); Stop-hook waiver discipline (`stop-hook-retry-guard.sh` backstop); staged-set verification before commit (Rule 4, Pattern) | 2026-06-10 |
| `git.md` | Git Standards | Convention | Always — commit messages, branch strategy, customer-tier branching, safe push methods | 2026-05-14 |
| `branch-hygiene.md` | Branch Hygiene — WIP-Branch Naming, Stash Lifetimes, Stale-Branch Policy | Hybrid | Item 8 of git-best-practices 9-item initiative. WIP-branch prefix list (Pattern), stash-lifetime discipline (Pattern), stale-branch decision tree (Pattern); Mechanism via `session-start-git-freshness.sh` (item 1) honoring the prefix list + `stale-active-plan-surfacer.sh` extended `surface_stale_branches()` (item 8) | 2026-05-29 |
| `parallel-dev-discipline.md` | Parallel-Dev Discipline — Trunk-Based CI/CD Defaults for Multi-Machine, Multi-Session Work | Hybrid | Always — 7 trunk-based practices (short-lived branches, one authoritative remote, pull-before-work/push-before-switch, PR-even-solo, branch protection, merge queue, never-a-shared-counter→timestamps) + one-item=one-branch=one-machine. Mechanism: `migration-naming-gate.sh` (PreToolUse Bash on `git commit`) blocks bare-integer-prefixed migrations; Practices 5–6 are operator-executed-once via documented `gh` commands; rest Pattern. | 2026-06-14 |
| `harness-hygiene.md` | Harness Hygiene — What Never Ships | Hybrid | Tool-scoped — `git commit` (Layer 1 denylist + Layer 2 heuristics via `harness-hygiene-scan.sh`) | 2026-05-05 |
| `harness-maintenance.md` | Harness Maintenance Rules | Convention | Always — editing any file under `~/.claude/` (global-first, sync-to-repo, update architecture doc) | 2026-04-18 |
| `information-architecture.md` | Information Architecture — Where Each Kind of Harness Content Belongs | Hybrid | Always — routing decision when authoring new content (rule body / decision / discovery / review / state); sibling mechanisms enforce CLAUDE.md size + rules-INDEX sync + session-start discoverability | 2026-05-29 |
| `interactive-process-fidelity.md` | Interactive-Process Fidelity — Carry-Forward Context Is Briefing, Not a Substitute for the User's Authority Touchpoints | Pattern | Surface-scoped — multi-stage interactive protocols (PRD intake Stages A–F, plan-time interface-impact decisions, discovery-protocol irreversible dispositions) | 2026-05-15 |
| `local-edit-authorization.md` | Local-edit Authorization (Stub — enforcement is in the hook) | Mechanism | Tool-scoped — `Edit`/`Write`/`MultiEdit` on `~/.claude/local/**` requires fresh marker authored by `/grant-local-edit <filename>` | 2026-05-09 |
| `mechanical-evidence.md` | Mechanical Evidence Substrate — Structured Artifacts Replace Prose Narration | Hybrid | Build-time — `task-verifier` reads `Verification:` level + `plan-edit-validator.sh` recognizes both `<task-id>.evidence.json` and legacy prose blocks | 2026-05-05 |
| `merge-completed-work.md` | Merge completed work — standing rule | Pattern | Always — every session that opens a PR merges it before reporting DONE, unless product-review / failing-CI / conflict-class exceptions apply | 2026-05-27 |
| `observed-errors-first.md` | Observed Errors First (Stub — enforcement is in the hook) | Mechanism | Tool-scoped — `git commit` of fix-class commits (`fix:` prefix etc.) requires fresh `.claude/state/observed-errors.md` entry with recognizable error syntax | 2026-05-04 |
| `orchestrator-pattern.md` | Orchestrator Pattern — Delegate Build Work to Sub-Agents | Hybrid | Plan-time — multi-task plans (≥2 tasks). Main session orchestrates and dispatches to `plan-phase-builder` sub-agents, does NOT do build work itself | 2026-06-03 |
| `planning.md` | Planning & Decision Protocol | Hybrid | Plan-time — task planning, mid-build decisions, completion reports, decision records, session history. The most-load-bearing rule file in the harness | 2026-05-21 |
| `pr-health-snapshot.md` | PR-Health Snapshot at Session Close (Stub — enforcement is in the hook) | Mechanism | Stop-time — `pr-health-snapshot-gate.sh` blocks session wrap (block-mode default) unless the final message has a `## PR Health Snapshot` section covering all active repos (`~/.claude/config/active-repos.txt`) | 2026-06-01 |
| `prd-validity.md` | PRD Validity — Every Plan With a Product Claim Resolves to a Substantive PRD | Hybrid | Tool-scoped — `Write` on `docs/plans/*.md` (`prd-validity-gate.sh`); substance review by `prd-validity-reviewer` agent before implementation | 2026-05-04 |
| `principles.md` | Principles — The Canonical Reference for Making Decisions Without Misha | Hybrid | Always — Operating Rules 0–7 + Decision Principles + Design Philosophy. Companion mechanism `principles-compliance-gate.sh` (Stop hook) scans final assistant message for Rule 3/4/5/7 anti-patterns | 2026-05-27 |
| `react.md` | React / Next.js Standards | Convention | Surface-scoped — editing React/Next.js source | 2026-04-18 |
| `risk-tiered-verification.md` | Risk-Tiered Verification — Verify Proportionate to Risk | Hybrid | Build-time — per-task `Verification: mechanical \| full \| contract` declaration routes evidence checks + task-verifier dispatch | 2026-05-05 |
| `secret-hygiene.md` | Secret Hygiene — Three-Layer Defense Against Credential Leaks | Pattern (Hybrid with sibling Mechanism layers) | Tool-scoped — global gitignore (Layer 1), pre-push scanner (Layer 2 — `pre-push-scan.sh`), remote secret scanning (Layer 3 — GHAS / partner-integrated) | 2026-05-14 |
| `security.md` | Security Rules | Convention | Always — credentials, destructive ops, public-repo prohibition, software-install safety | 2026-04-18 |
| `session-end-protocol.md` | Session-End Protocol — Every Turn Ends With Exactly One DONE / PAUSING / BLOCKED Marker | Hybrid | Stop-time — `continuation-enforcer.sh` Stop hook blocks session end without exactly one valid marker on the last line | 2026-05-17 |
| `spawn-task-report-back.md` | Spawn-Task Report-Back — Convention-Based Callback Channel for `mcp__ccd_session__spawn_task` | Hybrid | Session-start — `spawned-task-result-surfacer.sh` surfaces unread results from `.claude/state/spawned-task-results/*.json` | 2026-05-05 |
| `spec-freeze.md` | Spec Freeze — Declared Files Cannot Be Edited Until the Plan's Spec Is Frozen | Hybrid | Tool-scoped — `Edit`/`Write` on files declared in an ACTIVE plan's `## Files to Modify/Create` (`spec-freeze-gate.sh`) | 2026-05-04 |
| `teaching-moments.md` | Teaching Moments — Capture User Pushbacks That Shifted Claude's Position | Pattern | Always — opt-in per project (presence of `docs/teaching-examples/` directory); captures substantive user-pushback moments where Claude's revised position is better | 2026-05-06 |
| `testing.md` | Testing & Verification Standards | Convention | Always — encodes the FUNCTIONALITY-OVER-COMPONENTS principle, the bug-persistence rule, no-test-skip discipline, E2E system-boundary rule | 2026-05-11 |
| `typescript.md` | TypeScript Standards | Convention | Surface-scoped — editing `*.ts` / `*.tsx` | 2026-04-18 |
| `ui-components.md` | Rules for UI component changes (src/components/** and src/app/**/page.tsx) | Convention | Surface-scoped — editing UI components / page files | 2026-04-18 |
| `ux-design.md` | UX Design Principles | Convention | Surface-scoped — UI work (error messages, empty states, loading states, destructive actions) | 2026-04-18 |
| `ux-standards.md` | UX Standards for UI Development (src/components/** and src/app/**/page.tsx) | Convention | Surface-scoped — UI work (color semantics, contrast, accessibility, AI feature treatment) | 2026-04-18 |
| `vaporware-prevention.md` | Anti-Vaporware Rule (Stub — enforcement is in hooks) | Mechanism (by reference) | Always — points at the enforcement-map of every hook/agent that prevents vaporware shipping | 2026-05-22 |
| `verification-pipeline.md` | Verification Pipeline — Four-Agent Sequence Before Task Completion | Hybrid | Build-time + Stop-time — `functionality-verifier` per-task, `end-user-advocate` at session end (`product-acceptance-gate.sh`), `claim-reviewer` before prose summary, `domain-expert-tester` after substantial UI builds | 2026-05-11 |
| `work-shapes.md` | Work Shapes — When to Use, How to Add, How to Escalate | Pattern | Plan-time — scan `adapters/claude-code/work-shapes/` for a canonical task shape that matches; cite `shape_id` in dispatch prompts | 2026-05-05 |
| `workstream-memory-ecology.md` | Workstream-Memory Ecology — Match Capture To Tier; Don't Pollute Workstreams With Each Other's Context | Pattern | Always — at fact-observation time, judge which tier (project SCRATCHPAD / cross-workstream vault / user auto-memory) the fact belongs to and route accordingly | 2026-05-23 |

## Maintenance

When you add a rule file under `adapters/claude-code/rules/`, you MUST add a row to this table in the same commit. CI enforces this via `evals/golden/rules-index-coverage.sh` — the test fails if any `*.md` under the rules directory lacks an INDEX entry (and vice versa: an INDEX entry pointing at a non-existent file also fails).

The five fields per row:

- **Filename** — backtick-quoted, matches the actual file basename.
- **Title** — copied from the `# ` heading of the rule file. If the title changes, update both.
- **Type** — Mechanism / Pattern / Hybrid / Convention, matching the rule's `**Classification:**` line (or "Convention" if the rule has no classification line).
- **Trigger** — one short sentence naming when the rule fires (Always / Plan-time / Build-time / Stop-time / Tool-scoped / Surface-scoped + the specific tool or surface).
- **Last updated** — date of the most recent commit that touched the file (`git log -1 --format=%ad --date=short -- <path>`). Optional — the CI enforcement only checks filename + presence, not last-updated freshness.

## Why this exists

The expert review of 2026-05-23 surfaced that the rules system is sprawling (45 rule files as of this commit) and that there is no canonical entry point for "what rules apply to this session, in what order, with what enforcement?" Each rule is well-written and individually navigable, but discoverability across the set required reading every file. The INDEX is the navigation aid — short enough to skim, complete enough to point at every rule, and CI-enforced so a new rule cannot land without showing up here.

For the full catalog of best-practices the harness encodes (with rationale per practice), see [`docs/best-practices.md`](../../../docs/best-practices.md). The INDEX is the structural inventory; `best-practices.md` is the narrative explanation.
