# Cross-Machine Context Handoff — 2026-05-24

**Author:** Dispatch orchestrator session on Misha's primary machine
**Audience:** Misha (or the orchestrator he spawns) starting work on a different computer
**Generated:** 2026-05-26 (commits & PR state as of this date)
**Branch:** `docs/cross-machine-context-handoff-2026-05-24` (this doc lives only on this branch until merged)

This is a comprehensive snapshot of everything in flight across the harness + downstream-project repos. Read top-to-bottom on first sit-down; index back to specific sections later. Intentionally dense — every file path, commit SHA, PR number, and decision is recorded verbatim rather than paraphrased. If the answer to "what was that thing we were doing?" isn't here, treat it as a gap and surface it.

## Quick-jump

1. [What we've shipped (last ~2 weeks)](#1-what-weve-shipped-last-2-weeks)
2. [Concepts + principles we've established](#2-concepts--principles-weve-established)
3. [Currently in-flight work](#3-currently-in-flight-work)
4. [Plans that started but never completed — drift inventory](#4-plans-that-started-but-never-completed--drift-inventory)
5. [Current state of each major project](#5-current-state-of-each-major-project)
6. [How to pick this up on another machine](#6-how-to-pick-this-up-on-another-machine)
7. [Decisions waiting on Misha — consolidated](#7-decisions-waiting-on-misha--consolidated)
8. [Open HARNESS-GAPs](#8-open-harness-gaps)
9. [Things that didn't ship as designed — honest section](#9-things-that-didnt-ship-as-designed--honest-section)

---

## 1. What we've shipped (last ~2 weeks)

Window: 2026-05-12 → 2026-05-26. Activity is dominated by neural-lace harness work (~26 merged PRs in the window) and circuit incident response (~100 commits including FM-001 root-cause + Vault triage).

### 1.1 neural-lace — shipped to master

**Recent merge commits on master:**

| SHA | Date | One-liner |
|---|---|---|
| `dbc1354` | 2026-05-23 | Merge PR #25 — close conv-tree-auto-current plan |
| `1910fd9` | 2026-05-23 | chore(plan): close conv-tree-auto-current (Status: COMPLETED → auto-archive) |
| `02f3ad9` | 2026-05-23 | Merge PR #24 — conv-tree auto-current (heartbeat + session-start emit) |
| `fff2de3` | 2026-05-22 | chore(plan): close session-state-refresh-2026-05-22 |
| `6e5955b` | 2026-05-22 | chore(state): refresh backlog v44 + open session-state-refresh plan |
| `b4fdf3b` | 2026-05-22 | plan: conv-tree-auto-current — P1 fix for stale tree state |
| `fe1ccc2` | 2026-05-22 | Merge PR #23 — diagnostic-first protocol enforcement closure |
| `70b76ab` | 2026-05-22 | chore(plan): close diagnostic-first-protocol-enforcement |
| `ec46fcf` | 2026-05-22 | rules: diagnostic-first protocol + hypothesis-vs-proof labeling + refutation criteria |
| `e859b5f` | 2026-05-22 | chore(plan): close pr-template-validator-accept-ai-prose |
| `f70e1e6` | 2026-05-22 | Merge PR #21 — PR template validator AI prose fix |
| `e1f471e` | 2026-05-22 | fix(pr-template-validator): accept AI-natural prose answer form |
| `7311480` | 2026-05-21 | Merge PR #20 — conv-tree orchestrator-emit modes |
| `4a25348` | 2026-05-21 | chore(plan): close conv-tree-orchestrator-emit |
| `e21ad16` | 2026-05-21 | feat(conv-tree): orchestrator-emit modes for raising decisions/questions/actions |
| `5d2a7ad` | 2026-05-21 | docs(backlog): record v42 — external-monitor alert-surfacer hook shipped |
| `205a012` | 2026-05-21 | Merge PR #19 — circuit-prod-health-monitor (probe + generic surfacer + runbook) |
| `501a917` | 2026-05-21 | chore(circuit-prod-health-monitor): close plan + auto-archive |
| `a73b41f` | 2026-05-21 | feat(circuit-prod-health-monitor): probe + generic surfacer + runbook |
| `8551a81` | 2026-05-21 | Merge PR #18 — docs(discoveries): cross-branch stash + git add scope failure mode |
| `e4a2f1d` | 2026-05-21 | docs(discoveries): cross-branch stash + git add scope failure mode |
| `3c37680` | 2026-05-20 | Merge PR #17 — conv-tree-ui v1.1.4 item 41 (detail-pane inline + rich-details enrichment) |
| `7be8ff2` | 2026-05-20 | feat(conv-tree-ui v1.1.4 item 41): detail-pane inline layout + rich-details enrichment |
| `4193c27` | 2026-05-20 | Merge PR #16 — conv-tree-ui v1.1.4 item 40 (actionable detail-pane) |
| `c2485f3` | 2026-05-20 | feat(conv-tree-ui v1.1.4 item 40): actionable detail-pane |
| `0094c0b` | 2026-05-19 | Merge PR #12 — conv-tree-ui v1.1.2 polish |

**Thematic grouping of merged work:**

- **Conversation Tree UI v1.1.4 (items 40-41)** — actionable detail-pane (PR #16), inline layout + rich-details enrichment (PR #17), orchestrator-emit modes for raising decisions/questions/actions (PR #20). Commits `c2485f3` `7be8ff2` `e21ad16`.
- **Conv Tree auto-current fix (P1 stale-state bug)** — session-start self-registration + 5-minute Windows scheduled heartbeat (`ConversationTreeUI-Heartbeat`). PR #24 (`02f3ad9`) + closure PR #25 (`dbc1354`). New surface: `--on-session-start` + `--heartbeat` modes in `conversation-tree-emit.sh`, `/api/health` endpoint, GUI freshness badge.
- **Diagnostic-first protocol + hypothesis-vs-proof labeling** — three Pattern-class rules now load into every session via the harness boot path: `rules/diagnosis.md` (DIAGNOSTIC-FIRST PROTOCOL top section), new `rules/claims.md` (PROVEN/HYPOTHESIZED labeling + refutation criteria), plus operational reinforcement in `agents/plan-phase-builder.md`. PR #22 (`ec46fcf` + `81aca0d`) + closure PR #23 (`70b76ab` + `fe1ccc2`). ADR-035 + FM-029 catalog entry + case-study lessons doc `docs/lessons/2026-05-22-fm-001-misdiagnosis.md`.
- **Circuit prod health monitor** — probe + generic surfacer + runbook. PR #19 (`205a012`). Polls Circuit production health, surfaces alerts to a generic surfacer (the same surfacer all external-monitor alerts now route through).
- **PR template validator accepts AI-natural prose** — `.github/scripts/validate-pr-template.sh` extended to recognize prose-form answers to the "What mechanism would have caught this?" section, not just the strict-scaffold form. PR #21 (`e1f471e`).
- **Discovery captures** — cross-branch stash + git-add scope failure mode (`e4a2f1d`); five other discoveries open (see Section 4).

### 1.2 neural-lace — open PRs (state on 2026-05-25)

Twelve open PRs, all 1-day-old (created 2026-05-24/25). Plus a handful of older ones (14+ days) that have been pending review for longer.

| PR # | Title | Branch | Draft? |
|---|---|---|---|
| 37 | fix(scope-enforcement-gate): trailing-slash patterns match bare gitlink paths (HARNESS-GAP-41) | `fix/scope-enforcement-gate-trailing-slash-parser-2026-05-24` | no |
| 36 | feat(decision-queue): Decision Queue substrate (ADR-036) | `feat/decision-queue` | no |
| 35 | fix(harness): close HARNESS-GAP-43 — validate inline PR bodies against template | `fix/pr-template-inline-gate-2026-05-24` | no |
| 34 | feat: drift backlog + self-reflective harness evaluator (Systems 1 + 2) | `feat/drift-backlog-and-harness-evaluator` | no |
| 33 | feat(conv-tree): auto-emit enforcement — Layer B reconciler + Layer D rule | `feat/conv-tree-auto-emit-enforcement-2026-05-23` | no |
| 32 | feat(conv-tree-ui): v2 layout — narrow tree + tabbed side panel + modals + context-as-textarea | `feat/conv-tree-ui-vertical-redesign-2026-05-23` | no |
| 31 | docs(strategy): test strategy 2026-05-23 — four-tier model + phased plan | `strategy/test-design-2026-05-23` | no |
| 30 | docs(harness): rules INDEX + diagnostic-evidence PR-template extension | `docs/rules-index-and-diagnostic-evidence-template-2026-05-23` | **draft** |
| 29 | ci(harness): server-side mirror of the local hook chain (close --no-verify bypass) | `ci/server-side-enforcement-2026-05-23` | **draft** |
| 28 | ci(harness): wire evals + hook self-tests on every PR (eat own cooking) | `ci/eats-own-cooking-2026-05-23` | **draft** |
| 27 | fix(conv-tree-ui): toast stacking — auto-dismiss, cap-3, group-by-parent | `fix/conv-tree-toast-stacking-2026-05-23` | no |
| 26 | docs: file HARNESS-GAP-39 — cloud-orchestrator hook-detector lint | `docs/harness-gap-cloud-orchestrator-hook-detector-2026-05-23` | no |

**Critical observations:**

- **PR #34 (drift backlog + harness-evaluator)** **already merged** to master per SCRATCHPAD ("plan COMPLETED + auto-archive") but the PR shows open in GH because re-runs/follow-ups got pushed; verify state before acting.
- **PR #36 (Decision Queue substrate, ADR-036)** is the canonical substrate for the "Decision Queue" concept described in Section 2.11. Important: if you continue work on this machine assuming Decision Queue is shipped, check master — at time of writing, the substrate lives on `feat/decision-queue` branch only.
- **PR #29 (server-side hook mirror)** is `draft` and incomplete. The "eats own cooking" PR #28 is also `draft` with golden test bugs being worked through.
- **PR #35 (HARNESS-GAP-43)** + **PR #37 (HARNESS-GAP-41)** are the two harness-gap fixes from 2026-05-24 session.

### 1.3 neural-lace — branches with shipped commits but unmerged to master

| Branch | Last commit date | Status |
|---|---|---|
| `origin/ci/eats-own-cooking-2026-05-23` (`731add1`) | 2026-05-24 | draft PR #28 — golden test bugs + known-failing allowlists |
| `origin/ci/server-side-enforcement-2026-05-23` (`840de16`) | 2026-05-24 | draft PR #29 — Layer 2 friction wrapper added |
| `origin/feat/decision-queue` (`e004396`) | 2026-05-24 | PR #36 — substrate + schema + storage + bridge + Conv Tree panel spec |
| `origin/feat/drift-backlog-and-harness-evaluator` (`130d3a2`) | 2026-05-24 | PR #34 — CI re-run trigger; main work already merged |
| `origin/feat/conv-tree-auto-emit-enforcement-2026-05-23` (`7755b14`) | 2026-05-24 | PR #33 — Layer B + Layer D enforcement |
| `origin/feat/conv-tree-ui-vertical-redesign-2026-05-23` (`0b527ec`) | 2026-05-24 | PR #32 — v2 narrow-tree layout |
| `origin/docs/harness-gap-cloud-orchestrator-hook-detector-2026-05-23` | 2026-05-24 | PR #26 |
| `origin/docs/rules-index-and-diagnostic-evidence-template-2026-05-23` | 2026-05-24 | draft PR #30 |
| `origin/strategy/test-design-2026-05-23` | 2026-05-24 | PR #31 — four-tier test strategy |
| `origin/fix/conv-tree-toast-stacking-2026-05-23` | 2026-05-24 | PR #27 |
| `origin/fix/pr-template-inline-gate-2026-05-24` | 2026-05-24 | PR #35 |
| `origin/fix/scope-enforcement-gate-trailing-slash-parser-2026-05-24` | 2026-05-24 | PR #37 |
| `origin/claude/serene-turing-0b131e` | 2026-05-21 | **never opened as PR** — carries `docs/reviews/2026-05-21-harness-deploy-verification-audit.md` + `docs/proposals/harness-reliability-improvements-2026-05-21.md` (the 6-mechanism proposal A-F) |
| `origin/conv-tree-ui-v1.1.2-polish` | 2026-05-19 | Older plan branch — collision-blocked with PR #13 (see Section 9) |

Plus 16 older branches dating to early May; most are claude-spawned worker branches whose work landed on master via other paths and which are safe to delete during cleanup.

### 1.4 Conversation-Tree UI work — version state

- **v1.1.2** (items 25-28; merged 2026-05-19 via PR #12, commit `0094c0b`) — basic polish layer.
- **v1.1.3** (items 14-23; merged 2026-05-18) — type palette, icon-jump, hide-concluded, bidirectional highlight, toast/flash.
- **v1.1.4** items 40-41 (merged 2026-05-20 via PR #16 + #17, commits `c2485f3` `7be8ff2`) — actionable detail-pane + rich-details enrichment.
- **v1.1.4 orchestrator-emit modes** (merged 2026-05-21 via PR #20, commit `e21ad16`) — new `--emit-branch`, `--emit-decision`, `--emit-question`, `--emit-action` modes on `conversation-tree-emit.sh`.
- **v1.1.4 auto-current fix** (merged 2026-05-23 via PR #24, commit `02f3ad9`) — `--on-session-start` + `--heartbeat` modes; Windows scheduled task `ConversationTreeUI-Heartbeat`.
- **v2 (UNRELEASED)** on PR #32 — narrow tree + tabbed side panel + modal overlays + context-as-textarea. Sits on `feat/conv-tree-ui-vertical-redesign-2026-05-23`.

### 1.5 Pocket-Technician / circuit — shipped recently

100+ commits in the window. Major arcs:

- **FM-001 cold-init hang resolution** (Vercel platform-side defect at deployment build level, not app code). ~20 commits. Pinned prod to known-good build `b78178e` (Node-22, 2026-05-17). Lazy-load Sentry (`Option α'`), lazy-load RBAC (`Path C`), isolation triplets on auth/session/webhook routes. The Lambda-INIT-cap theory was REFUTED (per the originating case study lessons doc — see Section 2.1).
- **RBAC framework (Phase 1-6)** — full permission registry + defaults + overrides + CI drift detector + admin matrix page + migration 138.
- **Sentry + Axiom event pipeline + alerting** — PR #304, commit `a306c0f`.
- **Onboarding bug-completeness sweep** — F1-F5 customer-journey hardening, JOURNEY-003/005/006/007/008/010-013/015/016/018/019/020/021/025/027/028 all Fixed.
- **UX audit + primitives lift (M1-M11)** — buttons, tooltips, form primitives, modal, datatable, kpi, skeleton; semantic color allowlist (ADR-060); 70 native `title→Tooltip` codemod.
- **Auth system rebuild** — login + recovery + lockout + logout-all + Playwright E2E suite (PR #192, commit `f1bc98a`).
- **Audit campaign 2026-05-22** — 8 audit-pack PRs (#311-318) + dashboard PR (#310) opened. Dependabot consolidated PR (#319) bumps 8 packages closing 1 critical + 28 high alerts (84 → 21 vulns). 5 ACTIVE plans flipped to COMPLETED + auto-archived.
- **A2P 10DLC campaign hardening**, **Twilio TWLO-001/006/007 fixes**.

Master HEAD as of 2026-05-24: `cdc23ca` (docs/reviews onboarding action plan amendment).

### 1.6 Pocket-Technician / pt-leads — shipped recently

Quiet — only 1 commit in the 2-week window (`6eed529` 2026-05-09 architecture snapshot merge). 8 dirty files on `main` branch. Multiple stale unmerged feature branches dating back to April: `feat/session-context-extraction`, `feat/persist-conversation-messages`, `feat/persist-realtime-events`, `feat/dashboard-show-conversation-data`.

### 1.7 Pocket-Technician / admin — shipped recently

Lightweight repo. Only 2 commits in window — most recent `e21afdb` (2026-05-19) `fix(api): add FM-001 isolation triplet to auth/session route + CI audit (#13)`. Clean working tree on `main`.

### 1.8 Pocket-Technician / marketing — shipped recently

1 commit in window: `18743c7` (2026-05-17) `feat: A2P 10DLC campaign resubmission hardening (#11)`. Four FM-001 backport branches pending merge (`fix/fm-001-batch-2-newsletter`, `fix/fm-001-isolation-triplet`, `chore/close-fm-001-plan`, `fix/fm-001-audit-script`). 3 files dirty on `main`.

### 1.9 Personal / Foresight — shipped recently

54 commits in window. Major arcs:

- **FM-001 isolation-triplet sweep** — 50 batches merged 2026-05-11 → 2026-05-20. CI gate at `.github/workflows/fm-001-gate.yml`.
- **Rules-rebuild Phases 0-4** — landed via separate commits; Phases 5 prep complete.
- **Phase 5 pre-staging** (PR #62, merged 2026-05-21 at `33299c6` + archival `1bad7da` + backlog refresh `9b42e7e`). Helper scripts: `scripts/export-answer-key.ts`, `scripts/reset-categorization.ts`, `scripts/phase5-metrics.ts`, `scripts/diff-against-answer-key.ts`. Runbook: `docs/operations/foresight-phase5-runbook-2026-05-21.md`.
- **Lazy-import performance sweep** — backported from Circuit's FM-001 fix work.

Two open PRs awaiting Misha review:
- **PR #64** (2026-05-25) — `feat(foresight pass 1): noise inventory + processor channels + data preservation (NOT applied)` — branch `feat/foresight-pass1-normalization-processor-preservation-2026-05-23`. 13 decisions D-1 through D-13 surfaced.
- **PR #63** (2026-05-23) — `strategy: Foresight data + rules cleanup strategy (Path B recommended)` — branch `strategy/data-rules-cleanup-2026-05-22`.

Current branch checked out locally: `feat/foresight-pass1-normalization-processor-preservation-2026-05-23` with 17 staged files. Master HEAD: `2d4507e` (2026-05-24).

---

## 2. Concepts + principles we've established

Each concept gets: (a) one-paragraph definition, (b) where enforced, (c) Mechanism / Pattern / Hybrid classification, (d) known limitations.

### 2.1 Diagnostic-first protocol

**What it is.** On any production-failure investigation, the FIRST tool call must retrieve runtime/error logs from the affected system — Vercel logs, Sentry, Datadog, Supabase logs, webhook delivery logs, job-runner execution logs, or journalctl for self-hosted. Inferential evidence (probe behavior, code reading, git history, bisect correlation, dependency analysis, schema reads, configuration diffs) is permitted ONLY AFTER actual logs have been examined OR after explicit in-band "logs are inaccessible because X" acknowledgment with a concrete reason. Confidence-sounding diagnoses without log evidence are prohibited.

**Where enforced.**
- `~/.claude/rules/diagnosis.md` — top-level "DIAGNOSTIC-FIRST PROTOCOL" section (upstream of every other diagnostic step, including the FM-catalog grep below it)
- `~/.claude/agents/plan-phase-builder.md` — "Investigation-work mandate" clauses 1-3 (operational reinforcement for dispatched investigation work)
- `docs/decisions/035-diagnostic-first-protocol.md` — ADR with refutation criterion ("operator-CONFIRMED if 5+ future investigations honor the protocols; mechanical enforcement reopened if 1+ violate")
- `docs/lessons/2026-05-22-fm-001-misdiagnosis.md` — originating case study: 8+ days of FM-001 misdiagnosis on inferential narrative; runtime logs would have revealed the actual error in ~30 seconds
- `docs/failure-modes.md` — **FM-029** ("Investigation proceeds from inferential evidence without first capturing runtime/error logs from the affected system")

**Classification.** **Pattern.** No PreToolUse hook detects "this is an investigation session" — detection would require unreliable agent self-classification. The user retains interrupt authority.

**Known limitations.** The 30-minute trigger ("if you are >~30 min into hypothesis-chasing and have NOT pulled runtime logs, stop and pull them now") is self-applied; there is no automatic alert. The rule composes with claims.md — together they form a discipline pair. Without the labeling discipline, a session could honor diagnostic-first while still producing untagged confident-sounding claims downstream.

### 2.2 Hypothesis-vs-proof labeling + refutation criteria

**What it is.** Every causal claim in a status update, report, or session output is tagged as either **PROVEN** (cite the specific evidence: log line, test result, measurement, response body, query output, screenshot, file:line citation) or **HYPOTHESIZED** (state the assumption AND the refutation criterion — a specific observable that, if found, would invalidate the claim). Naked confident phrasing without either tag is prohibited. Before authoring an implementation plan on top of a hypothesis, explicitly write the refutation criterion AND look for refuting evidence before committing engineering resources. If no refutation criterion can be identified, declare the diagnosis non-falsifiable.

**Where enforced.**
- `~/.claude/rules/claims.md` — full rule (inline-parenthetical vs tagged-block styles, refutation-criteria requirement)
- `~/.claude/agents/claim-reviewer.md` — agent that adversarially checks feature claims in prose before they reach the user (self-invoked; residual gap acknowledged in `vaporware-prevention.md`)
- `~/.claude/agents/plan-phase-builder.md` — builder agents inherit the labeling discipline in their return summaries (Investigation-work mandate clauses 2-3)
- `docs/decisions/035-diagnostic-first-protocol.md` — ADR locking both diagnostic-first AND claims-labeling

**Classification.** **Hybrid.** Per-claim labeling is Pattern (self-applied). The `claim-reviewer` agent provides a Mechanism backstop but is self-invoked and can be skipped (residual gap).

**Known limitations.** Verbal vaporware in conversation is not mechanically blocked — Claude Code has no PostMessage hook. The user retains interrupt authority when seeing an uncited claim. Sibling Stop hooks (`transcript-lie-detector.sh`, `imperative-evidence-linker.sh`, `goal-coverage-on-stop.sh`) catch adjacent narrative-integrity failures but do NOT enforce the per-claim tag.

### 2.3 Path-of-least-resistance principle ("loud is not rare")

**What it is.** LLM agents under context pressure or time constraints will "loudly" reach for options that appear easy and non-alarming relative to other routine actions (even if those options are destructive). "Loud is not rare" — an option existing in the tool set + the option's name not sounding alarming relative to other commands the agent runs constantly = the agent reaching for it the moment normal paths fail. This principle justifies **absolute bans** on destructive patterns (e.g., `git push --force` is never correct, no exceptions) in place of nuanced "call me first" rules that require restraint at decision time.

**Where referenced.**
- `~/.claude/rules/git-discipline.md` — Rule 1 (force-push prohibition) explains the principle in its "Why this is absolute" sub-section
- Memory entry: `~/.claude/projects/.../memory/feedback_loud_is_not_rare.md` (loaded into every session)
- `~/.claude/rules/gate-respect.md` — operationalizes the principle via "diagnose before bypass" protocol

**Classification.** **Pattern** (it's a behavioral principle that justifies strict enforcement elsewhere). The principle itself is documented; the enforcement (absolute bans, mechanical gates) is the Mechanism it underwrites.

**Known limitations.** The principle is empirical, derived from repeated agent failures observed in practice. It is impossible to "prove" the principle is correct mechanically — the harness honors it by baking absolute bans where the principle predicts the LLM will slip.

### 2.4 Mechanical vs Pattern distinction

**What it is.** The harness classifies every rule as either **Mechanism** (a hook, agent, or script that physically rejects or gates the wrong action — friction requires deliberate effort to bypass), **Pattern** (a documented convention where the agent is expected to follow it; no hook detects deviation), or **Hybrid** (a Pattern main body with Mechanism-backed specific sub-rules). The distinction is metadata that lets readers calibrate trust and friction per rule.

**Where documented.**
- `docs/best-practices.md` — section "The harness distinguishes between two kinds of enforcement"
- Every rule file's header carries `**Classification:**` as its first non-title line
- `~/.claude/rules/vaporware-prevention.md` — "Enforcement map" table explicitly names each row's enforcement file and whether it is Mechanism/Pattern/Hybrid

**Classification.** Meta-classification (not itself a rule).

**Known limitations.** The distinction is advisory metadata, not mechanically enforced. A contributor authoring a new rule can ignore it; the distinction matters only to readers' mental models and to the orchestrator's dispatch decisions. The user surfaces drift between "rule says Mechanism" and "no hook actually exists" via the drift-backlog (Section 2.8) — there is no auto-detector.

### 2.5 Acceptance-scenarios gating + per-session waivers

**What it is.** User-facing plans declare `## Acceptance Scenarios` modeling the observable behaviors the plan claims it will produce. The `end-user-advocate` agent reviews scenarios at plan-time (paper review of Goal/Scope/Edge Cases for incompleteness) and at runtime (browser automation against the live app to verify each scenario passes). The Stop-hook gate `product-acceptance-gate.sh` (position 4 of the Stop chain) blocks session end when a non-exempt ACTIVE plan lacks a PASS artifact for the current `plan_commit_sha`. Plans can be exempted via `acceptance-exempt: true` + a substantive `acceptance-exempt-reason:` (≥20 chars), or a per-session waiver at `.claude/state/acceptance-waiver-<slug>-<ts>.txt` (≥1 substantive line, <1h old) allows Stop.

**Where enforced.**
- `~/.claude/rules/acceptance-scenarios.md` — full rule with Stages 1-5 loop, scenario file format, artifact schema, multi-worktree aggregation
- `~/.claude/hooks/product-acceptance-gate.sh` — Stop hook position 4
- `~/.claude/agents/end-user-advocate.md` — two modes (plan-time, runtime)
- `~/.claude/agents/enforcement-gap-analyzer.md` — auto-invoked on FAIL to propose harness improvements
- `~/.claude/rules/git-discipline.md` Rule 3 — when the Stop hook fires on an unrelated plan, write a per-session waiver rather than let the retry-guard absorb the failure

**Classification.** **Hybrid.** Plan-time authoring discipline + gap-analyzer convergence loop = Patterns. Runtime acceptance gate = Mechanism. Plan-template section presence = Mechanism (enforced by `plan-reviewer.sh`).

**Known limitations.** Plan-time advocate feedback is self-applied (planner authors gaps). No mechanical check that the planner closed the feedback before moving to build. Runtime advocate depends on the app being reachable; auth-only-via-SSO or environment-specific setup are harder to test. Chronic per-session waiver use is itself a signal — surfacing it as a forcing function is HARNESS-GAP-31 (waiver-density-alarm).

### 2.6 Conversation-Tree state file + 5-minute heartbeat

**What it is.** The Dispatch orchestrator writes branch-lifecycle events (branch-opened, concluded, branch-note-add, decision-raised, question-raised, action-raised) to a conversation-tree state file as it works, making the conversation graph durable and observable in the standalone GUI. The state file lives per-project under `~/.claude/state/conversation-tree/` (or per-global root); a 5-minute Windows scheduled task `ConversationTreeUI-Heartbeat` scans `~/.claude/projects/*/*.jsonl` for stale sessions and concludes their branches. The GUI's `/api/health` endpoint exposes `last_heartbeat` so a freshness badge ("tree Xm • hb Ym") goes red when the heartbeat itself stops firing.

**Where enforced.**
- `~/.claude/rules/conv-tree-orchestrator-emit.md` — full four-layer rule (see Section 2.7 for the layers)
- `~/.claude/hooks/conversation-tree-emit.sh` — modes: `--on-spawn`, `--on-stop`, `--on-session-start`, `--heartbeat`, plus the `--emit-*` modes for raising items
- `~/.claude/hooks/conversation-tree-state-gate.sh` + `conversation-tree-stop-gate.sh` — refuse-on-mismatch gates
- `neural-lace/conversation-tree-ui/scripts/register-heartbeat.ps1` — Windows Task Scheduler registration
- `docs/decisions/031-conversation-tree-ui-architecture.md` r8 (Dispatch-only narrowing)
- `docs/decisions/032-conversation-tree-state-schema.md` (snapshot attestation)
- `docs/decisions/034-conversation-tree-scope-dispatch-only.md` (sub-agent Task/Agent explicitly OUT of scope)
- `neural-lace/conversation-tree-ui/state/schema.js` — event types

**Classification.** **Hybrid.** Layers A-C (tool-wrap emit, pre-stop reconciler, heartbeat) are Mechanism. Layer D (agent self-discipline for genuine cloud Dispatch where local hooks don't reach) is Pattern.

**Known limitations.**
- **Cloud blind spot:** genuine cloud Dispatch (claude.ai/code, `--remote`, unattended Routines) does not load `~/.claude/` hooks. Only Layer D applies — agent self-discipline writing via the GUI's `POST /api/event` endpoint.
- **Sub-agent Task/Agent explicitly out of scope** (ADR-034). They are AI-internal mechanics, not branches of the user↔AI conversation the tree tracks.
- **`Bash(claude …)` + `/schedule`** are accepted gaps.

### 2.7 Auto-emit enforcement (four-layer defense)

**What it is.** A specific enforcement chain implementing the conv-tree state-file discipline:

- **Layer A (Mechanism):** per-tool side-effect emit hook (`conversation-tree-emit.sh`) wired at every Dispatch tool surface — PreToolUse on spawn, SessionStart, Stop. Emits `branch-opened` / `concluded` / `branch-note-add` events directly from the local hook chain.
- **Layer B (Mechanism):** pre-stop reconciliation (`conv-tree-emit-reconciler.sh`) — scans the agent-uneditable `$TRANSCRIPT_PATH` JSONL at Stop time for spawn-class tool calls, compares against the emit ledger, and auto-fills synthetic catch-up events for any spawn the writer missed.
- **Layer C (Mechanism):** 5-minute heartbeat scheduled task — touches live-markers for active sessions, concludes orphaned branches once their transcript-staleness exceeds the threshold, writes `heartbeat.last`.
- **Layer D (Pattern):** orchestrator-self-applied discipline for genuine cloud Dispatch — when local hooks can't reach the cloud orchestrator, the agent emits via the GUI's REST endpoint.

**Where enforced.** Same files as Section 2.6, plus `~/.claude/hooks/conv-tree-emit-reconciler.sh` (Layer B), shipping in PR #33.

**Classification.** **Hybrid.** Layers A-C are Mechanism. Layer D is Pattern with user-interrupt-authority as backstop.

**Known limitations.** PR #33 (Layer B reconciler + Layer D rule) is **unmerged** at time of writing. On master, only Layers A + C are live.

### 2.8 Drift backlog ("Misha-asked-for")

**What it is.** A residual work log tracking discrepancies between the harness's intended state (architecture described in ADRs, doctrine, rules) and its implemented state (what hooks/agents/scripts actually enforce). Example items: "the Gen-4 enforcement map documents 14 specific rule↔hook bindings, but 3 hooks are not yet wired into settings.json" or "the rule says Mechanism but no hook exists yet; enforcement is only Pattern." System 1 of the drift-backlog-and-harness-evaluator work (PR #34) ships a **transcript miner + drift detector** that scans recent transcripts for "Misha asked us to X" / "next session" / "follow-up needed" phrases and surfaces them as candidate drift items.

**Where enforced.**
- PR #34 (`feat/drift-backlog-and-harness-evaluator` — already merged per SCRATCHPAD) — System 1 transcript miner + drift detector at `adapters/claude-code/skills/drift-backlog.md` and supporting scripts
- `~/.claude/rules/vaporware-prevention.md` — "Enforcement map" header carries the principle: "Every row below points at an artifact that exists on disk. If you notice a row whose File column doesn't resolve, STOP."
- `docs/reviews/2026-05-25-harness-self-eval.md` Section 8 — the F1-F8 followups that became HARNESS-GAP-40

**Classification.** **Hybrid.** The detector is Mechanism (script that mines transcripts deterministically). The "this is a drift item" classification is Pattern (the agent or user judges whether the surfaced phrase is real drift or noise).

**Known limitations.** The transcript miner's recall is bounded by phrase patterns; a deferred commitment phrased atypically ("I'll get to that") may not match. HARNESS-GAP-40 tracks the F1-F8 followups (v2 polish on the miner).

### 2.9 Daily harness evaluator agent

**What it is.** System 2 of the drift-backlog work (PR #34) — a self-reflective harness evaluator that runs across the harness state, surfaces drift, out-of-date documentation, missing enforcement, and stale ADRs. Companion piece: System 3 (PR's follow-on commit `2ba5db1`) wires a **CI watcher** for Dispatch-spawned PRs plus a **daily cadence + skim-fast packet** that surfaces "what's worth Misha's attention today" in a compact form. The `/harness-review` skill (separate, pre-existing) runs an on-demand multi-check audit (13 checks including the Knowledge Integration Ritual KIT-1..KIT-7 triggers).

**Where enforced.**
- `~/.claude/skills/harness-review.md` — manual `/harness-review` invocation
- PR #34 + the follow-on commit `2ba5db1` — System 2 self-reflective evaluator + System 3 CI watcher + daily cadence
- `~/.claude/scripts/analyze-propagation-audit-log.sh` — consumes `build-doctrine/telemetry/propagation.jsonl` (KIT-6)
- `build-doctrine/doctrine/07-knowledge-integration.md` — defines the 7-trigger taxonomy

**Classification.** **Mechanism** (scheduled task or skill-invoked script) + **Pattern** (the orchestrator interprets the output).

**Known limitations.** Daily cadence requires a Windows scheduled task; not automatically registered on fresh installs. The skim-fast packet's "what's worth attention today" classification is heuristic and can surface noise. HARNESS-GAP-40 covers v2 polish.

### 2.10 CI watcher for Dispatch-spawned PRs

**What it is.** A monitor that watches PRs created by Dispatch-spawned sessions (identified by branch naming convention, PR body markers, or metadata) and surfaces CI/check failures back to the originating orchestrator session or as decision-queue items. Prevents the failure mode where a sub-agent successfully merges code but downstream CI checks failed — work that looks complete but is actually broken.

**Where enforced.** PR #34 follow-on commit `2ba5db1` (`feat(ci-watcher+daily): System 3 + daily cadence + skim-fast packet`). Sits on `feat/drift-backlog-and-harness-evaluator`.

**Classification.** **Mechanism** (script-based watcher).

**Known limitations.** CI runs are async — a watcher running at scheduled cadence may miss in-flight checks. The current implementation polls; webhook-based detection (proposed in `docs/proposals/harness-reliability-improvements-2026-05-21.md` mechanism E — "GH Actions webhook") is the more robust long-term solution but is not yet implemented.

### 2.11 Decision Queue (ADR-036)

**What it is.** When a plan is kicked off, the orchestrator enumerates every decision the team will face during execution. Each decision carries: question, options with cost/benefit, recommendation with justification, reversibility classification (REVERSIBLE → orchestrator may proceed if user hasn't answered; IRREVERSIBLE → pause and wait). The queue lives at `docs/decisions/queued-<plan-slug>.md` (or `queued-<arc-name>.md` for multi-plan arcs). User reviews asynchronously; orchestrator reads the queue before each decision point. Mid-execution decisions not in the queue follow Layer 2: reversible → proceed with recommendation + new ADR; irreversible → pause for user authorization.

**Where enforced.**
- `docs/decisions/027-autonomous-decision-making-process.md` — ADR locking the four/five-layer process
- `docs/decisions/queued-tranche-1.5.md` — the inaugural decision queue with 15 unanswered decisions across Tranches C/D/E/F/G
- Plus six other queued-* files: `queued-build-doctrine-5a-integration-and-audit-analyzer.md`, `queued-build-doctrine-tranche-2-template-schemas.md`, `queued-build-doctrine-tranche-3-template-content.md`, `queued-build-doctrine-tranche-6-orchestrator-scaffolding.md`, `queued-build-doctrine-tranche-6a-propagation-engine-framework.md`, `queued-docs-refresh-tech-team-architecture.md`
- **PR #36 (open, unmerged)** — formal substrate + schema + storage + bridge + Conv Tree panel spec (ADR-036)
- `~/.claude/rules/planning.md` Tier 1/2/3 framework — extends the queue
- `~/.claude/agents/plan-phase-builder.md` — orchestrator reads queue before each decision point

**Classification.** **Pattern** (queue authoring is convention) + **Mechanism** (the formal substrate from PR #36 once merged).

**Known limitations.** Pre-emptive identification is bounded by what the planner can anticipate. No mechanical check that user answers are reflected in the queue before the orchestrator reads it. Queue files grow unwieldy on long arcs (mitigation: per-tranche files).

### 2.12 Server-side validators (credential scanner, plan-edit, diagnostic-evidence)

**What they are.** A suite of validators running pre-commit/pre-push to catch violations before they land:

- **Credential scanner** (`pre-push-scan.sh`): blocks pushes containing strings matching credential patterns (AWS key prefixes, API-token formats, private-key headers, plus personal/team patterns from `~/.claude/sensitive-patterns.local` and `~/.claude/business-patterns.d/*.txt`).
- **Plan-edit validator** (`plan-edit-validator.sh` PreToolUse): blocks edits flipping a checkbox without a fresh evidence block within a 120-second window; routes per-task evidence checks per `Verification:` level.
- **Diagnostic-evidence checker**: part of `plan-reviewer.sh` Check 7 + `runtime-verification-reviewer.sh` Stop hook — verifies runtime-verification entries correspond to the feature described, and that commands are replayable (not plain-text "checked in browser").

**Where enforced.**
- `~/.claude/hooks/pre-push-scan.sh` (credential scanner; wired via `core.hooksPath` to `<neural-lace>/adapters/claude-code/git-hooks/`)
- `~/.claude/hooks/plan-edit-validator.sh` (PreToolUse Edit/Write blocker on plan files)
- `~/.claude/hooks/runtime-verification-executor.sh` (Stop hook running each `Runtime verification:` entry)
- `~/.claude/hooks/runtime-verification-reviewer.sh` (Stop hook cross-checking correspondence)
- `~/.claude/rules/secret-hygiene.md` (three-layer defense: gitignore + pre-push scanner + remote secret-scanning)
- **PR #29 (draft, unmerged)** — `ci/server-side-enforcement-2026-05-23` — mirrors the local hook chain in CI to close the `--no-verify` bypass. Not yet shipped.

**Classification.** **Mechanism** (hooks reject invalid edits/commits/pushes).

**Known limitations.** The credential scanner's pattern list is finite — false negatives (real secrets matching no pattern) and false positives (legitimate values matching a credential pattern) are both possible. The plan-edit validator's 120-second window is a heuristic. **The `--no-verify` bypass is the biggest hole** — it skips every local pre-commit/pre-push hook. PR #29 is the planned closure (server-side CI mirror); until it merges, the perimeter is local-only.

### 2.13 PR template inline gate (HARNESS-GAP-43, formerly tracked as HARNESS-GAP-40)

**What it is.** A PR-template validator extension that validates **inline PR bodies** (where the body is in the PR itself, not in a `.pr-description.md` file) against the template's required sections. Fixes the case where an AI-spawned PR opens with just `gh pr create --body "..."` and the inline body skips the "What mechanism would have caught this?" section.

**Where enforced.** PR #35 (open) — `fix/pr-template-inline-gate-2026-05-24` — extends `.github/scripts/validate-pr-template.sh` and the `vaporware-volume-gate.sh` to validate inline bodies. Closes HARNESS-GAP-43 (filed during the 2026-05-24 session).

**Classification.** **Mechanism** (CI gate at `.github/workflows/pr-template-check.yml`).

**Known limitations.** The fix is unmerged. Until it lands, an AI session opening a PR with an inline body that lacks the section won't be blocked by CI.

### 2.14 Scope-enforcement gate trailing-slash parser (HARNESS-GAP-41)

**What it is.** A bug fix to `scope-enforcement-gate.sh`'s glob-pattern parser. The hook parses a plan's `## Files to Modify/Create` section to extract the allowed-files list for a commit. Previously, a bullet ending in `/` (e.g., `- adapters/claude-code/agents/`) didn't match bare files under that directory; the fix makes trailing-slash patterns match directory contents as if `**` were appended.

**Where enforced.** PR #37 (open) — `fix/scope-enforcement-gate-trailing-slash-parser-2026-05-24`. Modifies `~/.claude/hooks/scope-enforcement-gate.sh`.

**Classification.** **Mechanism** (PreToolUse Bash blocker on `git commit`).

**Known limitations.** Fix is unmerged. Until it lands, scope-enforcement is overly strict for plans declaring scope by directory prefix — operators have to use `**/*` patterns or list every file individually.

### 2.15 HARNESS-GAP catalog

**What it is.** A versioned catalog of acknowledged gaps, deferred work, and known-incomplete implementations in the harness. Each gap has an ID (HARNESS-GAP-NNN), a short title, an explanation, when it was discovered, and (usually) a proposed solution and estimated effort. The catalog is tracked informally — entries live as bullets in `docs/backlog.md`, referenced from rule headers, and cited in commit messages.

**Where tracked.**
- `~/claude-projects/neural-lace/docs/backlog.md` — primary index. As of v44 (2026-05-22): gaps 19 through 43 active or recently-closed (see Section 8 below for the full list).
- `~/.claude/rules/vaporware-prevention.md` — enforcement-map rows cite HARNESS-GAP IDs where relevant
- Recent additions tracked in commit messages (e.g., `b20bb9a` "file GAP-40/41/42 for drift-backlog v2 + System 3 + daily-cadence")

**Classification.** **Meta-documentation.** Not itself a rule — a transparent inventory of "things we know are not done yet."

**Known limitations.** No locked schema for HARNESS-GAP entries. Some gaps are old and may have been partially addressed without the catalog entry being updated. The catalog is not centrally indexed; cross-referencing requires `grep HARNESS-GAP- docs/backlog.md`.

### 2.16 Failure-Mode (FM) catalog

**What it is.** A canonical, sanitized catalog of known harness and product failure classes, with required fields: ID (FM-NNN), Symptom (what an operator observes), Root cause (what in the system produced it), Detection (where this class can be caught), Prevention (what stops it), Example (one sanitized instance). Optional fields added by Decision 033: Discriminator (the single observation distinguishing this FM from look-alikes) and Recovery (immediate human steps to get unstuck right now, distinct from Prevention which is mechanism-facing). Every project carries its own `docs/failure-modes.md`; consulting it at investigation-start is a Pattern rule.

**Where tracked.**
- `docs/failure-modes.md` (per project) — most recent additions: FM-029 (diagnostic-first inversion), FM-028 (same root cause re-diagnosed each session)
- `docs/conventions/failure-mode-catalogs.md` — cross-project convention standard (Decision 033)
- `~/.claude/rules/diagnosis.md` — "Check the Failure-Mode Catalog Before Forming a Hypothesis" section + "After Every Failure: Encode the Fix"

**Classification.** **Meta-documentation + Pattern.** Catalog itself is durable record. The "check it first" behavior is a Pattern rule.

**Known limitations.** Updates are manual. Sanitization of incident names/dates/identifiers is manual; a contributor could accidentally include identifiable information. Older entries pre-date Discriminator + Recovery fields and lack them.

### 2.17 Audit packs + cross-project runs

**What they are.** Standardized audits (comprehensive reviews of specific harness subsystems or project states) that can be run across multiple projects or at different points in time, producing comparable results. Recent runs:

- `docs/reviews/2026-05-17-dispatch-worktree-accumulation.md` — Dispatch worktree-accumulation audit
- `docs/reviews/2026-05-16-conversation-tree-design-package-review-ledger.md` — conv-tree design-package review
- `docs/reviews/2026-05-06-readme-architecture-cold-test.md` — README cold-test (does a fresh reader understand the architecture?)
- `docs/reviews/2026-05-05-failsafe-audit.md` — Failsafe audit (Tranche F)
- `docs/reviews/2026-05-04-rules-vs-hooks-audit.md` — rules-vs-hooks audit
- `docs/reviews/2026-05-25-harness-self-eval.md` (per SCRATCHPAD reference) — self-eval driving HARNESS-GAP-40 F1-F8 followups

**Where tracked.** `~/claude-projects/neural-lace/docs/reviews/` directory + cross-project equivalents (e.g., `circuit/docs/reviews/`).

**Classification.** Hybrid — the audit scripts where they exist are Mechanism; the cross-project running pattern is Pattern.

**Known limitations.** Audit packs are not yet formalized as a reusable component. The `/harness-review` skill is the closest thing to a parameterized audit; generalizing it cross-project is a future item.

---

## 3. Currently in-flight work

This section captures what's running RIGHT NOW (active sessions, recent work in progress) plus any branches with uncommitted state on this machine. **By construction this section will be stale soon — the moment is the value.**

### 3.1 This session

- **Session purpose:** generate this handoff doc
- **Branch:** `docs/cross-machine-context-handoff-2026-05-24` (this branch — created at the start of this session)
- **What I'm building:** this file at `docs/handoffs/cross-machine-context-2026-05-24.md`
- **When done:** commit + push + open PR for Misha to review on the other machine
- **No blocking issues.**

### 3.2 Recent (likely-now-stale) sessions per SCRATCHPAD

From neural-lace SCRATCHPAD (last updated 2026-05-25):
- Recent commits within the last 4 hours of SCRATCHPAD-generation time included `130d3a2` (CI re-run trigger), `76a8116` (close drift-backlog-followups System 3), `2ba5db1` (System 3 + daily cadence + skim-fast packet), `b20bb9a` (GAP-40/41/42 filed), `04b2b5e` + `a478dc4` (drift-backlog + harness-evaluator close-out)
- Active plans in SCRATCHPAD at that time:
  - `ci-server-side-enforcement-2026-05-23` — Plan: ci/server-side-enforcement — mirror the local hook chain in CI so `--no-verify` cannot bypass the perimeter (0/5 tasks)
  - `conv-tree-ui-v1.1.2-polish` — Plan: Conversation Tree UI v1.1.2 — polish (items 25-28) (10/10 tasks; collision-blocked, see Section 9)
  - `misha-decision-batch-handoff-2026-05-20` — Plan: cross-project decision-batch handoff doc + cross-branch stash discovery (2/8 tasks)
- Plans archived in the prior 4 hours: `drift-backlog-and-harness-evaluator`, `drift-backlog-followups-system3-and-daily-cadence`

### 3.3 Open PRs awaiting review/merge — see Section 1.2

12 PRs open in neural-lace; 2 in Foresight (PR #63, PR #64); some FM-001 backport branches unmerged in pocket-technician-marketing.

### 3.4 Branches with local-only state on this machine

From `git status` at session start:
- **`.claude/launch.json`** untracked — likely a per-machine launch config
- Plus the 10 worktree directories prefixed with adjectives (`charming-wescoff-358c9f`, `infallible-heisenberg-9c2e06`, etc.) showing modifications/untracked — these are sibling worktrees from `git worktree add` commands; their state is local to this machine and won't migrate cleanly

### 3.5 Standing things to remember

- **Drift-backlog System 1+2** already merged to master (per SCRATCHPAD). System 3 (CI watcher + daily cadence) shipped in follow-on commit `2ba5db1`. PR #34 may show open in GH; verify via `gh pr view 34 --json state` if confused.
- **Decision-queue substrate** is still on a feature branch (PR #36, ADR-036). The concept is in use (15 unanswered decisions in `queued-tranche-1.5.md` etc.), but the formal substrate (schema, storage, bridge to Conv Tree panel) is not on master yet.
- **Server-side CI mirror** (PR #29) is draft — the `--no-verify` bypass is still open until that lands.

---

## 4. Plans that started but never completed — drift inventory

The biggest section. Classification key: **BIG-ARCH** (architectural work deferred), **CROSS-REFACTOR** (partial sweep), **PROCESS** (said-and-skipped commitment), **DECISION** (awaiting Misha decision), **FINDING** (open audit finding), **OTHER**.

### 4.1 neural-lace — ACTIVE plans not touched in 7+ days

| Plan | Last touched | Days stale | Status | Class |
|---|---|---|---|---|
| `conv-tree-ui-v1.1.2-polish.md` | 2026-05-20 14:08Z | 6 | ACTIVE, 10/10 tasks; **collision-blocked** with PR #13 (see Section 9) | OTHER |
| `misha-decision-batch-handoff-2026-05-20.md` | 2026-05-21 07:25Z | 5 | ACTIVE, 2/8 tasks; blocked on cross-branch stash discovery | PROCESS |
| `conv-tree-ui-v1.1.2-polish-evidence.md` | 2026-05-19 | 6 | archived evidence companion | OTHER |
| `tranche-4-canonical-pilot-handoff.md` | 2026-05-06 | 20 | no Status field; 20 days untouched | BIG-ARCH |

`ci-server-side-enforcement-2026-05-23` is also ACTIVE per SCRATCHPAD (0/5 tasks); PR #29 is draft.

### 4.2 neural-lace — DRAFT plans awaiting ratification

None in primary `docs/plans/` (only archive contains drafts).

### 4.3 neural-lace — open findings

From `docs/findings.md` (top entries, by recency):

| ID | Severity | Title | Status | Notes |
|---|---|---|---|---|
| NL-FINDING-002 | warn | Sub-agent background tasks leak past completion | **open** | OS-level zombie polling loops + stale task-tracker entries; 21+ ghost tasks observed |
| NL-FINDING-010 | warn | conversation-tree-state-gate blocks bare Task/Agent dispatches | **dispositioned-defer** | Per ADR-034: sub-agent Task/Agent intentionally out of scope; workaround = per-dispatch waiver |
| NL-FINDING-011 | info | v1.2: Dispatch-side state-file reader | **open** | Out of v1.1 scope; auto-surface GUI inline-response events in Dispatch chat |
| NL-FINDING-012 | warn | PR #11 merged with failing backfill self-test B15 | **open** | B15 environment-dependent (requires seeded fixture doc); flag for re-verify |
| NL-FINDING-013 | error | "v1.1.2" version/plan-slug collision | **open** | Parallel sessions used same label; PR #12 vs PR #13; master COMPLETED #13 version; Misha decision on versioning/merge order pending |

### 4.4 neural-lace — PR branches with shipped commits but unmerged

13 branches with active code awaiting merge or carrying decisions:

- `origin/ci/eats-own-cooking-2026-05-23` — PR #28 draft; golden test bugs
- `origin/ci/server-side-enforcement-2026-05-23` — PR #29 draft; Layer 2 friction wrapper
- `origin/feat/decision-queue` — PR #36; substrate + schema + storage + bridge + Conv Tree panel spec
- `origin/feat/conv-tree-auto-emit-enforcement-2026-05-23` — PR #33; Layer B reconciler + Layer D rule
- `origin/feat/conv-tree-ui-vertical-redesign-2026-05-23` — PR #32; v2 narrow-tree layout
- `origin/docs/harness-gap-cloud-orchestrator-hook-detector-2026-05-23` — PR #26
- `origin/docs/rules-index-and-diagnostic-evidence-template-2026-05-23` — PR #30 draft
- `origin/strategy/test-design-2026-05-23` — PR #31; four-tier test strategy
- `origin/fix/conv-tree-toast-stacking-2026-05-23` — PR #27
- `origin/fix/pr-template-inline-gate-2026-05-24` — PR #35; HARNESS-GAP-43 fix
- `origin/fix/scope-enforcement-gate-trailing-slash-parser-2026-05-24` — PR #37; HARNESS-GAP-41 fix
- `origin/claude/serene-turing-0b131e` — **never opened as PR**; carries `docs/reviews/2026-05-21-harness-deploy-verification-audit.md` + `docs/proposals/harness-reliability-improvements-2026-05-21.md` (6-mechanism A-F proposal, 6 Misha-decision asks in §7)
- `origin/conv-tree-ui-v1.1.2-polish` — older plan branch, collision-blocked

**Class: CROSS-REFACTOR / PROCESS** (most are clean shipped code; merge decisions outstanding).

### 4.5 neural-lace — pending discoveries (5 open)

These were re-surfaced at this session's start by `discovery-surfacer.sh`. Each has a Status: pending awaiting decision.

| File | Type | Date |
|---|---|---|
| `docs/discoveries/2026-05-11-close-plan-verification-field-parser-greedy.md` | failure-mode | 2026-05-11 |
| `docs/discoveries/2026-05-15-demonstration-tasks-need-real-touchpoints-not-proxy-synthesis.md` | process | 2026-05-15 |
| `docs/discoveries/2026-05-16-bug-persistence-gate-false-fires-on-interactive-intake-surface-turns.md` | process | 2026-05-16 |
| `docs/discoveries/2026-05-17-session-wrap-signal3-transitive-false-fire.md` | process | 2026-05-17 |
| `docs/discoveries/2026-05-21-stash-push-single-file-leaves-unstashed-deletions-stageable.md` | process | 2026-05-21 |

Each discovery's recommended action is in its file under the `Recommendation` heading. All 5 are reversible per the discovery-protocol; orchestrator could auto-apply if Misha doesn't object. They have been pending for 5-15 days.

### 4.6 neural-lace — queued decisions awaiting Misha override

Seven queue files exist:

- `docs/decisions/queued-tranche-1.5.md` — 15 unanswered decisions across Tranches C/D/E/F/G (work-shape library, risk-tiered verification, deterministic close-plan, failsafe audit, calibration loop)
- `docs/decisions/queued-build-doctrine-5a-integration-and-audit-analyzer.md`
- `docs/decisions/queued-build-doctrine-tranche-2-template-schemas.md`
- `docs/decisions/queued-build-doctrine-tranche-3-template-content.md`
- `docs/decisions/queued-build-doctrine-tranche-6-orchestrator-scaffolding.md`
- `docs/decisions/queued-build-doctrine-tranche-6a-propagation-engine-framework.md`
- `docs/decisions/queued-docs-refresh-tech-team-architecture.md`

All carry recommendations the orchestrator could autonomously apply per ADR-027 (reversible auto-apply). Misha override is welcome but not blocking.

**Class: BIG-ARCH-QUEUED.**

### 4.7 circuit — ACTIVE plans not touched >7 days (most are stale)

Per SCRATCHPAD (2026-05-23) and `docs/plans/` listing:

| Plan | Days stale | Status | Class |
|---|---|---|---|
| `ai-writing-assist-7-surface-sweep.md` | 9 | ACTIVE, 0/7 tasks; carve from PRD v1.1, ~3,400 lines | CROSS-REFACTOR |
| `ci-coverage-restoration.md` | — | ACTIVE | CROSS-REFACTOR |
| `circuit-comprehensive-rebuild.md` | — | ACTIVE | BIG-ARCH |
| `circuit-vercel-supabase-egress-debug.md` | 6 | ACTIVE, frozen, acceptance-exempt | FINDING |
| `conversation-pipeline-rewrite.md` | — | ACTIVE | BIG-ARCH |
| `funnel-objection-enter-arrow-routing.md` | 2 | ACTIVE; 12 Playwright specs + 1 new geometry-lock spec | OTHER |
| `impersonation-bug-class-sweep.md` | 2 | ACTIVE | CROSS-REFACTOR |
| `kanban-pipeline-multiline-title-and-master-push-fix.md` | — | ACTIVE | OTHER |
| `master-deploy-emergency-fix.md` | 2 | ACTIVE | PROCESS |
| `merge-master-into-ux-audit-branch.md` | 2 | ACTIVE | PROCESS |
| `sentry-axiom-push-monitoring.md` | 4 | ACTIVE | CROSS-REFACTOR |
| `service-areas-county-confirm-impersonation-fix.md` | 2 | ACTIVE | OTHER |
| `technicians-page-fixes-2026-05-13.md` | 12 | ACTIVE | OTHER |

Note: SCRATCHPAD says "5 ACTIVE plans flipped to COMPLETED with retroactive completion reports + auto-archival" (service-areas-county-confirm-impersonation-fix, funnel-objection-enter-arrow-routing, impersonation-bug-class-sweep, master-deploy-emergency-fix, merge-master-into-ux-audit-branch). Verify which are still ACTIVE before acting.

### 4.8 circuit — DRAFT plans awaiting ratification

- `2026-04-20-a2p-10dlc-multi-channel-consent.md` — DRAFT, 36 days old. **Class: DECISION.**
- `conversation-state-card-design.md` — DRAFT. **Class: BIG-ARCH.**
- `phase-6-preventive-controls.md` — DRAFT, 13 days; hard dependency on PR #249 (Phase-5 audit PRs not yet merged). **Class: BIG-ARCH.**
- `voice-integration-pt-csr-circuit.md` — DRAFT. **Class: BIG-ARCH.**
- `nepq-integration-strategy.md` — PROPOSAL (not yet ACTIVE). **Class: BIG-ARCH.**

### 4.9 circuit — open audit-pack PRs (#310-319)

Nine PRs opened in the 2026-05-22 audit campaign carrying decisions-needed for Misha. **None merged.**

- PR #310 — dashboard
- PR #311-318 — eight audit packs (code-reviewer-sample, dashboard, decision-record-completeness, diagnosis-protocol, documentation-completeness, fm-catalog-completeness, kit-sweep-propagation, stale-plans-findings-triage)
- PR #319 — Dependabot consolidated bump (8 packages closing 1 critical + 28 high alerts; picomatch 2→4 excluded as breaking-major)

Plus three unmerged branches sitting from prior sessions:
- `docs/dr-runbook-first-draft-2026-05-22` — DR runbook PR
- `chore/walkthrough-doc-disposition-2026-05-22` — walkthrough doc disposition PR
- `docs/fm-001-postmortem-2026-05-22` — FM-001 post-mortem PR

**Class: AUDIT-UNMERGED, DECISION** (each has decisions-needed sections).

### 4.10 circuit — critical blockers

**(a) Vault breakage in prod** — Twilio `auth_token` and ServiceTitan `client_secret` are silently broken across all 351 customer orgs since the Vault v0.3.x upgrade; zero rows in `vault.secrets` table. **Customer-impacting.** Misha decision on remediation path (a/b/c per finding write-up) needed. **Class: FINDING (severe), DECISION.**

**(b) Migration 137 push blocked** — Vault crypto-grant emergency fix; push attempted in prior session was blocked by auto-mode classifier. Needs Misha re-attempt or override. **Class: PROCESS, DECISION.**

**(c) Picomatch 2.3.1 high CVE residual** — breaking-major; tracked for separate PR. **Class: FINDING.**

**(d) Onboarding action-plan dashboard amendment** — append 2026-05-23 amendment section reflecting that session's work. **Class: PROCESS.**

### 4.11 pt-leads — dormant

| Plan | Last touched | Days | Status | Class |
|---|---|---|---|---|
| `2026-04-20-build-failure-monitor-phase-a.md` | 2026-04-20 | 36 | ACTIVE | BIG-ARCH |
| `2026-04-20-kanban-engine-quoting-fix.md` | 2026-04-20 | 36 | ACTIVE | OTHER |
| `session-context-extraction.md` | 2026-05-09 | 16 | ACTIVE | CROSS-REFACTOR |

Repo as a whole appears in maintenance mode. 8 dirty files on `main` branch (uncommitted local changes). Multiple stale feature branches dating back to April.

### 4.12 pocket-technician-marketing — FM-001 backport drift

Four FM-001 backport branches pending merge:
- `fix/fm-001-batch-2-newsletter`
- `fix/fm-001-isolation-triplet`
- `chore/close-fm-001-plan`
- `fix/fm-001-audit-script`

Plus `feat/a2p-campaign-resubmission` from 2026-05-04. **Class: CROSS-REFACTOR, FINDING (closed but un-shipped).**

Active plan: `2026-04-23-a2p-campaign-resubmission.md` — 33 days old, 19/42 tasks; Twilio approval is the external blocker. **Class: DECISION (external — Twilio).**

3 files dirty on `main`.

### 4.13 pocket-technician-admin — lightweight

No active plans. 1/1 route handler un-triplet was the only open finding (FM-001 P2 hygiene) and was closed via `e21afdb` (FM-001 isolation triplet backport). Clean working tree.

### 4.14 Foresight — active

| Plan | Last touched | Status |
|---|---|---|
| `foresight-pass1-normalization-processor-preservation-2026-05-23.md` | 2026-05-24 | ACTIVE; PR #64 awaiting Misha review (13 decisions D-1 through D-13) |
| `pipeline-override-remediation.md` | 2026-05-20 | ACTIVE; Phase 1 re-verify gate unstarted; Phase 5 acceptance waiver written for this session |

Plus three stale-shape plans flagged for archival in backlog:
- `cleanup-rule-workflow.md`
- `reconciliation-and-review-workflow.md`
- `rules-bulk-edit-review-fixes.md`

**Class: DECISION** (PR #64 has 13 decisions awaiting; Phase 5 execution requires operator-driven QIF source selection + answer-key disposition + sequencing call).

### 4.15 Big architectural asks deferred

From `docs/proposals/`, ADR future-work sections, and queued decisions:

- **Risk-engine runtime** — mentioned in expert review docs. Architecture exists; runtime never built. **Class: BIG-ARCH.**
- **Self-learning loop** — the architecture exists; the loop itself was never built. Currently a marketing label rather than a working system. **Class: BIG-ARCH.** (Honest call-out — see Section 9.2.)
- **Per-repo install path** — `install.sh` currently has machine-wide assumptions; per-repo install is a deferred ask. **Class: BIG-ARCH.**
- **Scenario-test framework** — proposed in `docs/strategy/test-design-2026-05-23` (PR #31, unmerged). Four-tier model: unit / hook-self-test / scenario / E2E. **Class: BIG-ARCH-QUEUED.**
- **Six harness-reliability mechanisms (A-F)** in `docs/proposals/harness-reliability-improvements-2026-05-21.md` (on unmerged `claude/serene-turing-0b131e` branch). Misha-decision asks in §7. Estimated ~14-19h harness work + ~30min per project config. **Class: BIG-ARCH, DECISION.**
- **ADR-031 Pin 1 amendment (ADR-034)** — sub-agent Task/Agent intentionally out of conv-tree scope. Not drift; decision; documented for awareness.

### 4.16 Cross-cutting refactors partially done

- **Making every rule mechanical** — many rules are Pattern-class; the drift backlog tracks "rule says Mechanism but no hook exists" gaps. HARNESS-GAP-29/30/31 (plan-staleness-surfacer, ready-to-close detector, waiver-density-alarm) are the systemic class. **Class: CROSS-REFACTOR.**
- **Server-side enforcement** (partial) — PR #29 (draft) closes the `--no-verify` bypass for the local hook chain. Until it lands, the perimeter is local-only.
- **CI test wiring** (partial) — PR #28 (draft) "eats own cooking" wires evals + hook self-tests on every PR. Golden test bugs in progress.
- **Mechanical evidence substrate (Tranche B)** — schema + helper script + plan-edit-validator extension landed earlier in May. Plans pre-dating it still use prose evidence; closure path is backward-compatible.

### 4.17 Process commitments said-and-skipped

- **Auto-emit to Conv Tree from Dispatch** — was a Pattern-class rule before the mechanical fix (Layers A-C + Layer D in PR #24 + #33). Layer D for genuine cloud Dispatch still relies on orchestrator self-discipline.
- **"After every merge to master, sync user's main checkout"** (`~/.claude/rules/git.md`) — Pattern-only; no hook detects "merged but did not sync."
- **"Drive to completion" / DONE-PAUSING-BLOCKED marker** (`session-end-protocol.md`) — Mechanism-backed via `continuation-enforcer.sh`, but the *honesty* of the marker (is it really DONE?) is Pattern.
- **"Identifying a gap = writing a backlog entry in the same response"** — Pattern from `planning.md`; relies on agent diligence + user catching slips.

### 4.18 Long-standing decisions never made

- **TCPA A/B/C** — pricing/legal compliance decision long-pending. Surfaced in circuit context (campaign launch + outbound voice TCPA bypass finding CIRCUIT-FINDING-042 closed via code but policy-level A/B/C still pending). **Class: DECISION.**
- **Pricing structure** — referenced in misha-decision-batch-handoff-2026-05-20.md and elsewhere. **Class: DECISION.**
- **Five account signups** — Sentry, Axiom, Google Chat webhook, BetterStack, spending caps. **Class: DECISION** (external — requires Misha login + account creation).

### 4.19 Audit findings open + unworked

From 2026-05-22 audit dashboard (circuit):
- 15 audit P0s
- 21 audit decisions

Status: PRs #310-319 opened but none merged. Each carries its own decisions-needed.

In Foresight:
- 13 decisions D-1 through D-13 in PR #64 awaiting Misha
- 3 Tier-1 Phase-5-execution decisions

### 4.20 Top-level drift classification summary

| Class | Approximate count | Highest-priority items |
|---|---|---|
| **ACTIVE-STALE** | 19 (circuit 13 + leads 3 + nl 3) | Circuit `ai-writing-assist-7-surface-sweep`, `technicians-page-fixes` (12d); pt-leads `build-failure-monitor-phase-a` (36d) |
| **UNMERGED-SHIPPED** | 13 neural-lace branches | PR #36 (decision-queue); PR #33 (auto-emit enforcement); PR #32 (conv-tree v2) |
| **AUDIT-UNMERGED** | 9 circuit PRs (#310-319) | All carrying decisions-needed; Misha triage |
| **PROPOSAL/DRAFT** | 5 circuit | `phase-6-preventive-controls` (stale 13d, blocked by PR #249) |
| **BIG-ARCH-QUEUED** | 15+ decisions in `queued-tranche-1.5.md` + 6 other queue files | Reversible per ADR-027 |
| **DISCOVERY-OPEN** | 5 neural-lace | Mostly process class; reversible |
| **VAULT-PROD-CRITICAL** | 1 (circuit) | 351 orgs silently broken |
| **MIGRATION-BLOCKED** | 1 (circuit Migration 137) | Auto-mode classifier block |
| **COLLISION** | 1 (neural-lace v1.1.2 slug) | PR #12 vs PR #13; needs Misha versioning call |

---

## 5. Current state of each major project

One-paragraph snapshot per repo. Pair with Sections 1 and 4 for evidence.

### 5.1 neural-lace

**Master HEAD:** `dbc1354` (2026-05-23) — merge of PR #25 closing conv-tree-auto-current plan. Local branch on this machine: `docs/cross-machine-context-handoff-2026-05-24` (this session). On another machine: clone from `git@github.com:mishanovini/neural-lace.git` master; expect 12 open PRs awaiting review/merge (notably PR #36 decision-queue, PR #33 conv-tree auto-emit enforcement, PR #32 conv-tree-ui v2, PR #29 server-side CI mirror draft). The most important pending change in flight is **PR #36 (decision-queue substrate)** — it's the formal home for the 15+ unanswered decisions in `queued-tranche-1.5.md` and various build-doctrine queue files. Without it merged, decisions live in scattered markdown files. Secondary priority: **PR #34 (drift-backlog + harness-evaluator System 1+2+3)** — per SCRATCHPAD it's been merged but the GH PR may show open from CI re-runs; verify and close out. Local-machine-only state: 10 worktree directories visible in `git status` (adjective-prefixed names) carrying various sessions' uncommitted local work — these don't migrate.

**Conv Tree UI:** v1.1.4 is live on master (items 40-41 shipped). v1.1.2 polish (items 25-28) on PR #12 collides with PR #13 (older repackaging of items 14-23) — open versioning question. v2 (vertical-redesign) on PR #32 is the next-major.

**Doctrine:** diagnostic-first protocol + claims labeling shipped (PR #22, master `ec46fcf`). ADR-035 + FM-029 + lessons doc form the canon for this discipline. Pattern-class; user retains interrupt authority on slips.

### 5.2 Circuit (Pocket-Technician)

**Master HEAD:** `cdc23ca` (2026-05-24) docs/reviews onboarding action plan amendment. **Local branch:** `docs/onboarding-action-plan-2026-05-22` (per the recent inventory; not on master). Per circuit's SCRATCHPAD (2026-05-23): branch `chore/stale-plans-cleanup-2026-05-22`. **Prod alias `circuit.pocket-technician.com`** is pinned to `d1f55fa` (FM-001 fix shipped) but master has moved since — verify deploy status. Migrations 132-136 applied to prod; **Migration 137 NOT pushed** (Vault crypto-grant; auto-mode classifier block; CRITICAL).

**Health:** STABLE on the pinned build (FM-001 root-cause resolved; `/api/health` returns 200 in 0.24-0.55s). **Blocking emergencies:** (1) Vault breakage — 351 orgs' Twilio/ServiceTitan secrets silently broken; (2) Migration 137 push blocked; (3) 9 audit-pack PRs (#310-319) unmerged with decisions-needed.

**Most important pending change:** resolve Vault breakage. Customer-impacting; surfacing path documented in `docs/findings.md` Vault entry (this session's).

### 5.3 pocket-technician / pt-leads

**Master HEAD:** `6eed529` (2026-05-09) architecture snapshot merge. **Dormant** — no activity in 17+ days; 8 dirty files on `main`; multiple stale feature branches. If picking this up, start by cleaning the working tree (`git status`) before any new work.

### 5.4 pocket-technician / admin

**Master HEAD:** `e21afdb` (2026-05-19) FM-001 isolation triplet. **Clean working tree.** No active plans. Treat as maintenance-only.

### 5.5 pocket-technician / marketing

**Master HEAD:** `18743c7` (2026-05-17) A2P 10DLC campaign resubmission hardening. **Active plan:** `2026-04-23-a2p-campaign-resubmission.md` (19/42 tasks; external Twilio block). 3 files dirty on `main`. Four FM-001 backport branches pending merge.

### 5.6 Foresight (Personal)

**Master HEAD:** `2d4507e` (2026-05-24). **Local branch:** `feat/foresight-pass1-normalization-processor-preservation-2026-05-23` with 17 staged files (Pass 1 work for PR #64). **Most recent strategy doc:** `docs/strategy/foresight-data-rules-cleanup-strategy-2026-05-22.md` (Path B recommended). **Phase 5 prep COMPLETE** — runbook + helper scripts shipped, awaiting operator execution of the destructive 36K Quicken re-import test. **Two open PRs awaiting review:** PR #63 (cleanup strategy, 2026-05-23) and PR #64 (Pass 1, 2026-05-25 with 13 decisions D-1 through D-13).

**Most important pending change:** the four decisions Misha just made (from the user's prompt) — gitignore, Phase 5 first, metric-based picks, plus the FM-001 sequence. Document the answers in PR #64's decision log to unblock merge.

**Note on directory duplication:** there are two locations — `/Personal/Foresight/` is the active git repo on this machine; `/Foresight/` (top-level) is NOT a git repo — it contains orphaned worktree directories from past sessions. On another machine, only `~/claude-projects/Personal/Foresight/` matters.

### 5.7 Build Doctrine

Lives at `~/claude-projects/Build Doctrine/`. Outputs feed the harness via tranches (Tranches 1-7 reflected in `~/.claude/CLAUDE.md` "Build Doctrine Integration" section). Six queued-build-doctrine-* decision files exist; their tranches are paused pending those decisions. No active build-doctrine work in flight at this moment.

---

## 6. How to pick this up on another machine

### 6.1 Clone state required

These six repos should be available locally on the other machine, in this directory layout (matches the orchestrator's expectations and the `automation-modes.md` rule):

```
~/claude-projects/
├── neural-lace/                     # the harness itself
├── Pocket-Technician/
│   ├── circuit/
│   ├── pt-leads/
│   ├── pocket-technician-admin/
│   └── pocket-technician-marketing/
└── Personal/
    └── Foresight/
```

Plus optionally:
- `~/claude-projects/Build Doctrine/` — outputs feed harness tranches
- `~/claude-projects/_archived/` — historical reference only

### 6.2 Where the harness lives

`~/.claude/` is the standard location. On Windows, `install.sh` from `neural-lace/adapters/claude-code/` **copies** files (no symlinks) into `~/.claude/`. The canonical source of truth is the neural-lace repo; the `~/.claude/` directory is the live mirror. Per `~/.claude/rules/harness-maintenance.md`: changes to `~/.claude/` must be synced back to `neural-lace/adapters/claude-code/` and committed.

The SessionStart hook warns when files in `~/.claude/` don't exist in the repo (template-vs-live divergence). The reminder shown at the start of this very session (`[settings-divergence] PreToolUse: template=28, live=29`) is an instance of this.

### 6.3 First files to read on the new machine, in this order

1. **This handoff doc** (you're reading it).
2. **`~/claude-projects/neural-lace/SCRATCHPAD.md`** — current ACTIVE plans, pending discoveries, queued decisions, latest milestone.
3. **`~/claude-projects/neural-lace/docs/backlog.md`** — HARNESS-GAP catalog + recent backlog entries (v44 + later).
4. **Most recent strategy/plan docs:**
   - `docs/strategy/test-design-2026-05-23.md` (in PR #31; on `strategy/test-design-2026-05-23` branch — fetch the branch to read)
   - `docs/proposals/harness-reliability-improvements-2026-05-21.md` (on unmerged `claude/serene-turing-0b131e` — fetch to read)
   - `docs/decisions/queued-tranche-1.5.md` — 15 unanswered decisions
5. **Active rules in `~/.claude/rules/`** — at minimum, skim these in order:
   - `diagnosis.md` (DIAGNOSTIC-FIRST PROTOCOL — first tool call must be runtime logs)
   - `claims.md` (PROVEN / HYPOTHESIZED labeling)
   - `acceptance-scenarios.md` (Stop-hook gate + waivers)
   - `git-discipline.md` (force-push prohibition + post-merge sync + Stop-hook waivers)
   - `gate-respect.md` (diagnose before bypass)
   - `friction-reflexion.md` (surface friction as discussion, never silent)
   - `session-end-protocol.md` (DONE / PAUSING / BLOCKED markers)
6. **Current PR queue:** `gh pr list --repo mishanovini/neural-lace --state open --limit 30` — see Section 1.2.
7. **Discoveries:** `ls ~/claude-projects/neural-lace/docs/discoveries/*.md` — surfacer auto-runs at session start; 5 pending as of this session.

### 6.4 Common commands to orient

```bash
# Where am I? What's clean?
git status --short ; git branch --show-current ; git log --oneline -5

# What's currently active in neural-lace?
grep -l 'Status: ACTIVE' ~/claude-projects/neural-lace/docs/plans/*.md
ls -lt ~/claude-projects/neural-lace/docs/plans/*.md | head -10

# What's been shipped recently?
git -C ~/claude-projects/neural-lace log --oneline --since="3 days ago"
git -C ~/claude-projects/Pocket-Technician/circuit log --oneline --since="3 days ago"

# What's open across all repos?
for r in neural-lace Pocket-Technician/circuit Pocket-Technician/pt-leads \
         Pocket-Technician/pocket-technician-admin \
         Pocket-Technician/pocket-technician-marketing \
         Personal/Foresight; do
  echo "=== $r ==="
  gh pr list --repo $(git -C ~/claude-projects/$r remote get-url origin | sed 's|.*github.com[/:]||;s|\.git$||') \
             --state open --limit 5 2>/dev/null
done

# What gaps are open?
grep -n 'HARNESS-GAP-' ~/claude-projects/neural-lace/docs/backlog.md | head -30

# Pending discoveries (the session-start hook auto-runs this)
ls ~/claude-projects/neural-lace/docs/discoveries/*.md | head -20

# Queued decisions
ls ~/claude-projects/neural-lace/docs/decisions/queued-*.md

# Check that the Conv Tree heartbeat is registered (Windows)
schtasks /query /tn "ConversationTreeUI-Heartbeat" 2>&1 | head -5

# Verify ~/.claude is in sync with neural-lace
diff -rq ~/.claude/rules ~/claude-projects/neural-lace/adapters/claude-code/rules | head -10
diff -rq ~/.claude/hooks ~/claude-projects/neural-lace/adapters/claude-code/hooks | head -10
```

### 6.5 Machine-specific gotchas

- **Windows path conventions:** the harness uses Git Bash style (`~/...`). PowerShell syntax differs (`$env:VAR` not `$VAR`, `$null` not `/dev/null`). Hooks are bash scripts; they run under Git Bash invoked by Claude Code.
- **Scheduled tasks (Windows):**
  - `ConversationTreeUI-Heartbeat` — every 5 minutes; runs `conversation-tree-emit.sh --heartbeat`. Register via `neural-lace/conversation-tree-ui/scripts/register-heartbeat.ps1` if not present on the other machine.
  - Any daily-harness-evaluator scheduled task from PR #34's System 3 — verify it's registered if you expect the daily skim-fast packet.
- **`~/.claude/local/` is per-machine and gitignored** — copy these files manually if needed:
  - `~/.claude/local/credentials-reference.md` — pointer to CLI auth conventions on this machine
  - `~/.claude/local/agent-teams.config.json` — Agent Teams config (likely `enabled: false`)
  - `~/.claude/local/dispatch-mode.json` — Dispatch-mode detection
  - `~/.claude/local/automation-mode.config.json` — user-global automation-mode default
  - Any `~/.claude/local/accounts.config.json`, `personal.config.json`, `projects.config.json`
- **Global git hooks** — `core.hooksPath` should point to `~/claude-projects/neural-lace/adapters/claude-code/git-hooks/` so the pre-push credential scanner fires from every repo. Verify with `git config --global core.hooksPath`.
- **The settings-divergence reminder** (seen at session start) is normal during active development — template (`adapters/claude-code/settings.json.template`) and live (`~/.claude/settings.json`) drift while changes are in flight. HARNESS-GAP-14 tracks the per-hook reconciliation methodology. To inspect: `diff -u <(jq -S . ~/claude-projects/neural-lace/adapters/claude-code/settings.json.template) <(jq -S . ~/.claude/settings.json)`.
- **Foresight directory duplication** — only `~/claude-projects/Personal/Foresight/` is the active repo; `~/claude-projects/Foresight/` (top-level) is NOT a git repo (orphaned worktrees from past sessions).

### 6.6 Sanity checks to run on first session

After cloning + harness install + machine-specific configs:

```bash
# 1. Self-tests pass
bash ~/.claude/hooks/scope-enforcement-gate.sh --self-test 2>&1 | tail -5
bash ~/.claude/hooks/plan-edit-validator.sh --self-test 2>&1 | tail -5
bash ~/.claude/hooks/conversation-tree-emit.sh --self-test 2>&1 | tail -5
bash ~/.claude/hooks/product-acceptance-gate.sh --self-test 2>&1 | tail -5

# 2. Credentials scanner reachable
bash ~/claude-projects/neural-lace/adapters/claude-code/hooks/pre-push-scan.sh --self-test 2>&1 | tail -5

# 3. GitHub auth works for each repo
for r in mishanovini/neural-lace; do gh repo view $r --json name 2>&1 | head -2; done

# 4. Discovery surfacer runs
bash ~/.claude/hooks/discovery-surfacer.sh 2>&1 | head -20
```

---

## 7. Decisions waiting on Misha — consolidated

This consolidates every Misha-decision-needed item across all repos. Some are CHOICES (Misha picks an option); some are ACTIONS (Misha logs into something or signs up); some are RATIFICATIONS (Misha approves a draft).

### 7.1 Account signups (5 items — ACTION)

These have been in the queue. They require Misha logging into external services.

1. **Sentry** — error-tracking service for Circuit + downstream apps. Most error-tracking integrations in code are already wired; account signup is the external dependency.
2. **Axiom** — event pipeline + alerting. Wired in Circuit (PR #304, commit `a306c0f`).
3. **Google Chat webhook** — alert sink for external-monitor-alert-surfacer.
4. **BetterStack** — uptime monitor.
5. **Spending caps on all signed-up services** — required guardrail; Misha decision.

### 7.2 Foresight observability decisions — ANSWERED

From the user prompt: "14 obs decisions → ALL ANSWERED (locked, but document the answers)" and "4 Foresight decisions → ANSWERED (document the answers, including the just-made gitignore + Phase 5 first + metric-based picks)".

**The four Foresight decisions Misha made this period (capture verbatim for the audit trail):**

1. **`pass1-canonicalization-map.json` — commit or gitignore?** → **gitignore** (Misha's call, contradicts the recommendation in the strategy doc which said "commit for audit trail"; Misha's reasoning prevails). Update PR #64 to gitignore the file.
2. **Phase 5 before or after `pipeline-override-remediation` Phase 1?** → **Phase 5 first**. The reset substrate is cleaner if Phase 5 runs first.
3. **D-1 / merchant-key picks** → **metric-based** (token-bounded matching fix per recommendation; ~20 LOC).
4. **FM-001 sequence** — confirmed status (sweep complete; CI gate live; next true test fires on the next new-API-route PR).

**The 14 observability decisions** referenced in the prompt — these were the obs decisions that came up in the harness-reliability-improvements proposal (`docs/proposals/harness-reliability-improvements-2026-05-21.md` 6 mechanisms A-F + supporting decisions) plus account-signup follow-ons. Since the user said "ALL ANSWERED (locked)" but didn't provide the answers in the prompt, the answers themselves need to be captured by Misha on the other machine in `docs/decisions/` ADRs. **Action for the other machine:** capture the 14 answers in formal ADRs before they evaporate.

### 7.3 TCPA A/B/C — DECISION pending

Pricing/legal compliance decision long-pending. Surfaces in Circuit (campaign launch + outbound voice TCPA bypass — CIRCUIT-FINDING-042 closed via code but the A/B/C policy decision still pending). Affects:
- Outbound voice product behavior
- Marketing copy + customer onboarding flow
- Compliance documentation

**Status:** No documented decision date. Has been "pending" across multiple sessions.

### 7.4 Pricing structure — DECISION pending

Referenced in `misha-decision-batch-handoff-2026-05-20.md` (active plan, 2/8 tasks, blocked). Likely covers Circuit pricing tiers + Foresight tiers + bundling. Misha's call.

### 7.5 Tranche 1.5 queued decisions (15 items — Tranches C/D/E/F/G)

All are REVERSIBLE per ADR-027 (the orchestrator may proceed with recommendations if Misha doesn't override). Full file: `docs/decisions/queued-tranche-1.5.md`.

**Tranche C — Work-Shape Library:**
- **C.1** — How many work-shape categories to seed initially? **Recommendation: A (seed 6)**.
- **C.2** — Where to store shape templates? **Recommendation: A (`adapters/claude-code/work-shapes/`)**.
- **C.3** — Format: Markdown with YAML frontmatter or pure JSON? Recommendation in file.
- **C.4** — Mechanical compliance check format. Recommendation in file.

**Tranche D — Risk-Tiered Verification:**
- **D.1** — Three tiers (mechanical/full/contract) or more granular? **Recommendation: A (3 tiers)**.
- **D.2** — Default verification level when not specified? **Recommendation: full** (preserves existing semantics; backward-compatible).
- **D.3** — Where does `Verification:` declaration live in plan task syntax? **Recommendation: end-of-line on the checkbox line**.

**Tranche E — Deterministic Close-Plan Procedure:**
- **E.1** — Implementation language: bash, python, or slash-command-wrapping-bash?
- **E.2** — Should close-plan auto-push, or commit only?
- **E.3** — Closure-check failure behavior: block, or surface and offer to skip?

**Tranche F — Failsafe Audit (for retirement):**
- **F.1** — Per-gate scoring: KEEP / SCOPE-DOWN / RETIRE classification?
- **F.2** — Retire all classified gates in one commit, or one-at-a-time?
- **F.3** — Threshold for "still load-bearing"?

**Tranche G — Calibration Loop Bootstrap:**
- **G.1** — Where do calibration entries live?
- **G.2** — Manual calibration cadence vs telemetry-gated?

### 7.6 Other queued decision files (six more)

- `queued-build-doctrine-5a-integration-and-audit-analyzer.md`
- `queued-build-doctrine-tranche-2-template-schemas.md`
- `queued-build-doctrine-tranche-3-template-content.md`
- `queued-build-doctrine-tranche-6-orchestrator-scaffolding.md`
- `queued-build-doctrine-tranche-6a-propagation-engine-framework.md`
- `queued-docs-refresh-tech-team-architecture.md`

All are awaiting Misha review per ADR-027. Some tranches likely already shipped (per SCRATCHPAD: "Tranches 2, 3, 5, 6-scaffolding, 6a, 5a-integration shipped"); verify which queues are now historical vs still-pending before acting.

### 7.7 6-mechanism harness-reliability proposal (A-F) — 6 decisions

From `docs/proposals/harness-reliability-improvements-2026-05-21.md` (on unmerged branch `claude/serene-turing-0b131e`). Six mechanisms with Misha-decision asks in §7:
- **A** — Post-push CI watcher
- **B** — Post-merge prod-smoke probe
- **C** — Multi-repo PR-status SessionStart digest
- **D** — Scheduled heartbeat
- **E** — GitHub Actions webhook
- **F** — Vercel webhook

Ranking matrix recommends A+B+C now (~14-19h harness work + ~30min per project config).

### 7.8 Circuit-specific decisions awaiting

1. **Vault breakage remediation path (a/b/c)** — CRITICAL, customer-impacting. See `docs/findings.md` Vault entry.
2. **Migration 137 push approach** — auto-mode classifier block; Misha re-attempt OR override.
3. **9 audit-pack PRs (#310-319)** — each carries its own decisions-needed.
4. **DR runbook merge** — branch `docs/dr-runbook-first-draft-2026-05-22` unmerged.
5. **FM-001 post-mortem merge** — branch `docs/fm-001-postmortem-2026-05-22` unmerged.
6. **Onboarding action-plan dashboard amendment** — append 2026-05-23 amendment.

### 7.9 Foresight-specific decisions awaiting

Per the Foresight inventory:

**Tier 1 — blocks Phase 5 execution:**
- Which 36K Quicken QIF file to use for re-import test? (Location not pinned in runbook.)
- Commit or gitignore answer-key file? (See 7.2 above — Misha said gitignore.)
- Phase 5 before or after `pipeline-override-remediation` Phase 1? (See 7.2 — Misha said Phase 5 first.)

**Tier 2 — blocks PR #64 merge:**
- D-1: Fix `thd` false-positive in merchantKey (~20 LOC; recommendation: yes).
- D-9: CASCADE DELETE vs SetNull on history table (recommendation: SetNull).
- D-12: Commit or gitignore `pass1-canonicalization-map.json` (see 7.2 — Misha said gitignore).
- D-13: Land Pass 1 migration before Phase 5 (recommendation: yes).

**Tier 3 — P2 housekeeping:**
- Archive 3 stale-shape plans.
- Verify Vercel Production deploy is current (master tip 6 commits ahead).
- Confirm FM-001 CI gate fires correctly on next new-API-route PR.

### 7.10 Conversation-Tree v1.1.2 versioning collision

PR #12 (items 25-28) and PR #13 (items 14-23 repackaged) both claim "v1.1.2". Master COMPLETED the #13 version; #12 needs versioning/merge-order call.

### 7.11 Neural-lace open PR triage

12 open PRs (mostly 1-day-old). Misha decides which merge first; rough priority order:
1. **PR #37** (HARNESS-GAP-41 trailing-slash) — small fix, unblocks scope-enforcement edge cases
2. **PR #35** (HARNESS-GAP-43 inline PR template gate) — small fix
3. **PR #36** (decision-queue substrate, ADR-036) — formal substrate; needs review
4. **PR #33** (auto-emit enforcement Layer B + D) — closes a conv-tree gap
5. **PR #29** (server-side CI mirror) — draft; closes the `--no-verify` bypass
6. **PR #28** (eats own cooking) — draft; CI for harness
7. **PR #32** (conv-tree v2) — bigger change, more review needed
8. **PR #31** (test strategy doc) — strategy ratification
9. **PR #30** (rules INDEX + diagnostic-evidence template) — draft
10. **PR #27** (conv-tree toast stacking) — small fix
11. **PR #26** (HARNESS-GAP-39 cloud-orchestrator hook-detector) — doc-only
12. **PR #34** — verify state (per SCRATCHPAD: already merged via squash; PR may show open from re-runs)

### 7.12 The `claude/serene-turing-0b131e` branch

**Never opened as PR.** Carries valuable docs:
- `docs/reviews/2026-05-21-harness-deploy-verification-audit.md`
- `docs/proposals/harness-reliability-improvements-2026-05-21.md`

Misha decision: open as PR, or commit-by-commit cherry-pick into a fresh branch, or abandon and re-author content on master? **Class: PROCESS, DECISION.**

---

## 8. Open HARNESS-GAPs

The HARNESS-GAP catalog lives as bullets in `docs/backlog.md`. As of v44 (2026-05-22), gaps 1-38 are tracked; gaps 40, 41, 42, 43 were added in the 2026-05-24/25 session (per SCRATCHPAD); gap 39 is the cloud-orchestrator hook-detector (PR #26).

### 8.1 Recently resolved (last 2 weeks)

| ID | Title | Status | Resolution |
|---|---|---|---|
| **HARNESS-GAP-37** | `automation-mode-gate.sh` blind to project config from worktrees branched pre-config | **IMPLEMENTED 2026-05-17** | Parent-checkout fallback via `git-common-dir`; 5/5 self-test |
| **HARNESS-GAP-38** | `session-wrap.sh` tracked-file freshness signals unclearable from a worktree | **IMPLEMENTED 2026-05-17** | Worktree-toplevel freshness read; ADR 028; 10/10 self-test |
| **HARNESS-GAP-36** | Chronic per-session acceptance waivers on stale unstarted ACTIVE plans (downstream-project instance) | **dispositioned-act** | Dedicated downstream build session spawned to drive a stuck plan to COMPLETED |
| **HARNESS-GAP-27** option (a) | `scope-enforcement-gate.sh` blind to merge-commit semantics — lightweight migration-allowlist | **SHIPPED 2026-05-14** | When `$GIT_DIR/MERGE_HEAD` exists, commit-numbered migrations exempt |

### 8.2 Open (in-flight or proposed; not yet shipped)

| ID | Title | Status | Notes |
|---|---|---|---|
| **HARNESS-GAP-43** | PR template inline gate (validate inline PR bodies against template) | **IN PR #35** (open, 2026-05-24) | Unmerged |
| **HARNESS-GAP-42** | (filed 2026-05-25 per commit `b20bb9a` "file GAP-40/41/42 for drift-backlog v2 + System 3 + daily-cadence") | filed | Likely System 3 + daily-cadence companion gap |
| **HARNESS-GAP-41** | `scope-enforcement-gate.sh` trailing-slash patterns match bare gitlink paths | **IN PR #37** (open, 2026-05-24) | Unmerged |
| **HARNESS-GAP-40** | drift-backlog + harness-evaluator v2 followups (F1-F8 from `docs/reviews/2026-05-25-harness-self-eval.md` §8) | **filed 2026-05-25** | v1 shipped in PR #34; v2 polish queued |
| **HARNESS-GAP-39** | Cloud-orchestrator hook-detector lint | **IN PR #26** (open, 2026-05-24) | Doc-only filing |
| **HARNESS-GAP-34** | `end-user-advocate` agent not dispatchable in the Dispatch environment | filed 2026-05-15 | (Renumbered from 33 at the 2026-05-16 merge — master's v36 had independently shipped a different GAP-33) |
| **HARNESS-GAP-33** | `prd-validity-reviewer` cannot detect AI-synthesized convergence signals in an interactive-protocol artifact (provenance blind spot) | filed 2026-05-15 | Surfaced from the 2026-05-15 PRD-intake incident |
| **HARNESS-GAP-32** | `close-plan.sh` retroactive friction on legacy plans whose evidence-of-completion lives in prose + git history, not `.evidence.json` artifacts | filed 2026-05-15 | Sibling to GAP-29/30 — the gate's retroactive friction itself contributes to staleness |
| **HARNESS-GAP-31** | `waiver-density-alarm.sh` SessionStart hook converting silent acceptance-waiver accumulation into a forcing function | filed 2026-05-14 | Plan-staleness class |
| **HARNESS-GAP-30** | Extend `pre-stop-verifier.sh` with "ready-to-close" detector (Status: ACTIVE + all task boxes + all DoD boxes checked) | filed 2026-05-14 | Companion to GAP-29 |
| **HARNESS-GAP-29** | `plan-staleness-surfacer.sh` SessionStart hook surfacing the three plan-staleness archetypes | filed 2026-05-14 | The systemic class |
| **HARNESS-GAP-28** | Dispatch spawner should set `CLAUDE_CODE_DISPATCH=1` env var so sessions can detect remote-Dispatch client mode | filed 2026-05-14 | Anthropic-side request |
| **HARNESS-GAP-27** option (b) | Union-of-plans-active-on-either-side-of-merge | **deferred** per ADR 030 | Trigger criteria documented |
| **HARNESS-GAP-26** | Build ADR cross-reference staleness analyzer for KIT-4 | filed | 45 ADRs × 5 canon artifacts = manual sweep impractical |
| **HARNESS-GAP-25** | Profile + optimize slow `git log`-based propagation rules | filed | Both exceed 1s wall time; blocks promotion to blocking action |
| **HARNESS-GAP-24** | Wire propagation engine into PostToolUse to surface real-time events | filed | Companion to GAP-19 |
| **HARNESS-GAP-22** | Sweep harness for other `--force` / `--no-verify` / OVERRIDE-style escape hatches | filed 2026-05-06 | Remove or convert to friction-the-agent-cannot-satisfy |
| **HARNESS-GAP-19** | Wire `session-wrap.sh` into Stop chain | **shipped 2026-05-24** | Script built (321 lines, 5/5 self-tests PASS); ADR 027 v2 Layer 5 |
| **HARNESS-GAP-17** | User-facing narrative docs stale post-integration | Part A IMPLEMENTED 2026-05-05 (5 narrative docs updated); Part B (docs-freshness-gate narrative-doc extension) **deferred** | |
| **HARNESS-GAP-16** | Closure-validation gate | **IMPLEMENTED in Tranche 1.5 E**; **tagged-for-retirement** per Tranche F | Retired 2026-05-05 per failsafe-retirements audit |
| **HARNESS-GAP-15** | (gap exists in backlog; details on a deeper read) | open | |
| **HARNESS-GAP-14** | Template-vs-live `settings.json` reconciliation | **IMPLEMENTED 2026-05-04** | 6 per-hook proposals + 5 hooks added to template; tool-call-budget matcher tightened; post-reconciliation: template=23, live=23 |
| **HARNESS-GAP-13** | hygiene-scan 4-layer expansion | **IMPLEMENTED** | |
| **HARNESS-GAP-12** | (open) | | |
| **HARNESS-GAP-11** | (telemetry mechanization gated on 2026-08) | deferred to 2026-08 | The telemetry substrate for calibration-loop mechanization |
| **HARNESS-GAP-10** | (open) | | |
| **HARNESS-GAP-08** | Spawn_task report-back | **IMPLEMENTED** | Absorbed into `docs/plans/harness-gap-08-spawn-task-report-back.md`; convention with sentinel + JSON schema + ack marker |
| **HARNESS-GAP-01..09** | Various older gaps | mostly resolved per backlog version history; spot-check before assuming | |

**Note:** ID 18 is unused. ID 23 is also unused per the grep above. Sequential numbering is not strictly enforced.

### 8.3 Open gaps grouped by theme

**Plan-staleness class (GAP-29/30/31):** the trio that addresses the systemic issue of plans sitting ACTIVE forever, waiver accumulation, and the missing aggregation signal. Highest leverage on operator productivity if all three ship.

**Conv-Tree / Dispatch gaps (GAP-28/33/34/39):** Dispatch-side blind spots and AI-only provenance detection. Most require Anthropic-side changes; the harness ships what it can on its own side (e.g., the rule `interactive-process-fidelity.md`).

**Propagation engine / telemetry (GAP-11/24/25/26):** mostly waiting on the propagation engine to land in real-time hooks (currently audit-log only) and on 2026-08 telemetry mechanization.

**Escape-hatch sweep (GAP-22):** remove or harden remaining `--force` / `--no-verify` / OVERRIDE-style escapes per the "loud is not rare" principle.

**Harness-portability (GAP-17 Part B):** narrative-doc freshness gate.

---

## 9. The "things that didn't ship as designed" honest section

The meta-honesty layer. Things I (Dispatch) recognize as having shipped incompletely, or as having been process theater, or as being marketing rather than working systems. Anything else the other-computer harness work needs to know I'm honest about.

### 9.1 Diagnostic-evidence PR-template extension was process theater

The diagnostic-evidence PR-template extension (proposed as a follow-up to ADR-035 / diagnostic-first protocol) was process theater. The extension would have required PR bodies to include a "diagnostic evidence" section. But that section is just another place to *describe* evidence, not a mechanism that *demands* evidence. A session that didn't pull logs can still write a confident-sounding prose summary for the diagnostic-evidence section. The PR template gate (which validates the section's presence and substance) can be satisfied with text that looks like evidence without actual log artifacts.

The honest framing: the diagnostic-first protocol is **Pattern-class** (and rightly so per ADR-035 — no PreToolUse hook can detect "this is an investigation session" without unreliable agent self-classification). Adding a PR-template section gives the illusion of mechanical enforcement when it really still relies on agent discipline. Decision: surface the section as **advisory only**, with the gate validating presence + substance but NOT certifying truth. Misha and the orchestrator agreed this was process theater after a short discussion; the section in `docs/rules-index-and-diagnostic-evidence-template-2026-05-23` (PR #30, draft) reflects the advisory-only framing.

### 9.2 Self-learning label is marketing until the loop ships

The "self-learning harness" framing in some recent docs is **marketing, not a working system**. The architecture for a self-learning loop exists:
- Calibration loop bootstrap (Tranche G of architecture-simplification) ships the manual capture surface (`/calibrate` skill) + `.claude/state/calibration/<agent-name>.md` per-machine entries
- `/harness-review` Check 12 rolls up calibration entries to surface patterns
- The Knowledge Integration Ritual (`build-doctrine/doctrine/07-knowledge-integration.md`) defines 7 triggers (KIT-1..KIT-7) for doctrine evolution
- The propagation engine (Tranche 6a) ships 8 starter rules + JSONL audit log

**But the loop itself — observed-failure → calibration-entry → roll-up-detection → prompt-update or gate-amendment — has never closed end-to-end autonomously.** Every cycle to date has been operator-driven (Misha noticing drift, surfacing it, the orchestrator filing a HARNESS-GAP, a future session implementing the fix). The mechanical signal carriers exist but the closing of the loop (auto-detect → auto-propose) is gated on:
- 2026-08 telemetry (HARNESS-GAP-11)
- Pilot evidence (Tranche 4 — canonical pilot)
- Cross-machine value (calibration entries are per-machine v1; promotion to durable storage gated per ADR-027 G.1)

Until the loop closes autonomously, "self-learning" is the architecture's *trajectory*, not its current state. The other machine should see this for what it is.

### 9.3 Cloud-side conv-tree emit hook is structurally unreachable

Per the conv-tree-auto-current fix (PR #24) closure notes: the orchestrator's PreToolUse hook on `mcp__ccd_session_mgmt__start_code_task` is wired in `~/.claude/settings.json`, but **only fires locally**. The cloud-side Dispatch orchestrator never reaches it, so production spawns from cloud were invisible to the emit hook. The fix routes around the gap by emitting from the **child's** SessionStart (always local) + a scheduled heartbeat. **The cloud-side PreToolUse wiring remains in place but is structurally unreachable** — it's dead code that looks live.

This is HARNESS-GAP-39 (`docs/harness-gap-cloud-orchestrator-hook-detector-2026-05-23`, PR #26): build a `harness-review` lint that catches the "wired but never fires" log signature (audit-log of self-tests all-PASS, zero production entries). Until that lint ships, similar "wired but cloud-unreachable" hooks could be living elsewhere and we wouldn't catch them.

### 9.4 "Drift backlog System 1" recall is bounded

The drift-backlog transcript miner (PR #34 System 1) scans transcripts for "Misha asked us to X" / "next session" / "follow-up needed" phrases. **Its recall is bounded by phrase patterns.** A deferred commitment phrased atypically — "I'll get to that later", "circle back on", "we should also" buried mid-paragraph, "let me park this", or any phrasing the miner's regex set doesn't match — will not be captured. HARNESS-GAP-40 (F1-F8 followups) tracks v2 polish that would address some of this; the miner is shipped but it is not complete.

### 9.5 The 5 pending discoveries have been pending for 5-15 days

These discoveries surfaced auto-applied recommendations:

| Date | Title | Days pending |
|---|---|---|
| 2026-05-11 | close-plan.sh Verification-field parser is greedy | 15 days |
| 2026-05-15 | Demonstration-of-interactive-process tasks must not proxy-synthesize human touchpoints | 11 days |
| 2026-05-16 | bug-persistence Stop gate structurally false-fires on interactive-intake surface-and-wait turns | 10 days |
| 2026-05-17 | session-wrap Signal 3 transitively false-fires on cross-session merges | 9 days |
| 2026-05-21 | git stash push of a single file leaves unstashed deletions stageable on branch-switch | 5 days |

All are reversible per the discovery-protocol — the orchestrator could auto-apply the recommendation in each file. They haven't because the discovery-protocol's "decide-and-apply for reversible" path requires the orchestrator to be working on a related task at the time. They're surfacing every session start but no session has been on a related-enough task to absorb them.

**Honest framing:** the discovery substrate ships, but the auto-apply pathway is functioning more as "surface forever until someone explicitly closes" than "auto-applied silently." This is a soft drift the next session could address by spending 15 minutes triaging all 5 inline.

### 9.6 Server-side CI mirror is incomplete

PR #29 (`ci/server-side-enforcement-2026-05-23`) is draft. Until it merges, the `--no-verify` bypass on `git push` skips every local pre-push hook (credential scanner, harness-hygiene scan). The server-side mirror would catch what `--no-verify` skips. Layer 2 (local friction wrapper, commit `840de16` on the same branch) raises friction but doesn't close the bypass. **The current perimeter is local-only.** A motivated operator (or a slip-up) using `--no-verify` would push uncaught credentials. Misha is aware; the fix is in flight; the gap is acknowledged but unclosed.

### 9.7 Conversation Tree v1.1.2 slug collision (PR #12 vs PR #13)

PR #12 opens with "Conversation Tree UI v1.1.2 polish (items 25-28)". PR #13 — also opened in parallel session — claims "Conversation Tree UI v1.1.2 (items 14-23 repackaged)". Master merged PR #13's version of "v1.1.2". PR #12 is now redundantly-named — its actual content (items 25-28) is real, but the slug collides.

This is **NL-FINDING-013 (error severity, open)**. Misha's call on versioning/merge order — rename items 25-28 to v1.1.3 or close PR #12 and re-open the items 25-28 work on a new branch with non-colliding slug.

### 9.8 Foresight directory duplication is partial cleanup

There are two Foresight locations on this machine:
- `~/claude-projects/Personal/Foresight/` — **the active git repo**
- `~/claude-projects/Foresight/` — **NOT a git repo** (contains orphaned worktree directories from past sessions)

The orphaned directory has been there for some time. It's harmless (no git surfaces touch it) but it's confusing — a fresh sit-down session could `cd` into the wrong directory and wonder why nothing works. Cleanup is one `rm -rf` away but hasn't been done because the orphaned worktrees may have salvageable uncommitted content.

**Honest call-out:** if the other-machine Misha sees a similar duplicate (unlikely if it's a fresh clone), don't be surprised.

### 9.9 `claude/serene-turing-0b131e` branch carries real proposals nobody opened

That branch carries `docs/reviews/2026-05-21-harness-deploy-verification-audit.md` + `docs/proposals/harness-reliability-improvements-2026-05-21.md` (the 6-mechanism A-F proposal). Real, substantive work. Never opened as PR. The proposal's 6 Misha-decision asks (§7) have been sitting unaddressed for ~5 days.

**Honest framing:** the cycle "investigation → audit doc → proposal doc → PR → review → decision → ship" stalled at the PR-opening step. Someone has to remember to open it. The drift-backlog transcript miner may catch this on its next run (the branch was mentioned with a "follow-up needed" phrasing in some session), but it's an open process-skip.

### 9.10 The HARNESS-GAP catalog has no locked schema

The catalog tracks entries as free-form bullets in `docs/backlog.md`. There's no schema saying "every entry must have: ID, Title, Date, Status, Resolution-path, Closing-commit." Some entries are exhaustive; others are one-liners. ID sequencing has gaps (18, 23 are unused). Status updates are manual — a gap marked "open" might have been shipped under a different ID without a back-link.

**Honest framing:** the catalog works as a transparent index but it isn't queryable. Generating Section 8's table above required grep + manual cross-reference + spot-reading; an automated "list open HARNESS-GAPs" tool doesn't exist. HARNESS-GAP-29's plan-staleness-surfacer concept could be extended to HARNESS-GAP-catalog-surfacer, but isn't.

### 9.11 The settings-divergence warning is normal but ignored

Every session start surfaces `[settings-divergence] template and live ~/.claude/settings.json differ`. This is normal during active development (HARNESS-GAP-14 tracks the per-hook reconciliation methodology). But "normal" can train sessions to ignore the signal. If the divergence ever crossed from "expected churn" to "actual structural mismatch", we'd miss it because we'd already be ignoring the warning.

**Honest framing:** noise in a signal-channel erodes the signal. The right move is either (a) make the reconciliation automatic (so the warning rarely fires) or (b) make the warning richer (so when it fires, it's actionable). Neither is done. The session-start hook surfaces a `diff -u` command suggestion but doesn't run it.

### 9.12 Several "all answered" claims from the user prompt weren't documented

The user prompt says "14 obs decisions → ALL ANSWERED (locked, but document the answers)" and "4 Foresight decisions → ANSWERED (document the answers, including the just-made gitignore + Phase 5 first + metric-based picks)". I've captured the 4 Foresight answers I could identify from the prompt and the SCRATCHPAD; I have NOT been able to enumerate the 14 obs decisions because they're not in any of the queue files I read (the 6 queued-build-doctrine-* files cover Build Doctrine tranches, not observability). The user may have answered them in a session whose transcript I haven't read.

**Honest framing:** Section 7.2 is incomplete. On the other machine, Misha should be able to point at where the 14 obs answers live or capture them fresh.

### 9.13 The 1500-3000 line target is approximately met

This doc was authored from agent research output + supplementary command runs + synthesis. The lines are dense (tables + bullets + minimal prose padding); the value-per-line is intentionally high. If a section reads thin, it's because the underlying inventory was thin, not because effort was skipped.

---

## Closing

This handoff is dense by design. The other-machine Misha (or the orchestrator he spawns) should be able to read top-to-bottom in ~30-45 minutes and have a working model of the harness state across all repos. The recommended cold-start order:

1. **Read this doc (you're done if you're here).**
2. **Open `~/claude-projects/neural-lace/SCRATCHPAD.md`** — verify the "Active Plans" + "Recent Commits" + "Latest Milestone" match the picture this doc paints.
3. **Run `gh pr list --repo mishanovini/neural-lace --state open`** — verify the 12 PRs are still open or note which have been resolved since this doc was written.
4. **Check the 5 pending discoveries** — triage inline (~15 min).
5. **Pick a starting target:** options ranked by "what would Misha most like to see done":
   - **(High):** Resolve Vault breakage in Circuit (customer-impacting).
   - **(High):** Push Migration 137 (Vault crypto-grant emergency).
   - **(High):** Merge PR #37 + PR #35 (small HARNESS-GAP fixes; quick wins).
   - **(Medium):** Open the `claude/serene-turing-0b131e` branch as a PR or cherry-pick the proposals onto a fresh branch.
   - **(Medium):** Triage neural-lace open PRs in priority order (Section 7.11).
   - **(Medium):** Document the 14 obs decision answers (Section 9.12).
   - **(Lower):** Address the 5 pending discoveries.
   - **(Lower):** Sweep the HARNESS-GAP catalog for already-resolved-but-not-closed entries.

`DONE: cross-machine handoff doc shipped` is what this session's marker will say. Anything that surprised me during this inventory: the sheer volume of unmerged PRs (13 in neural-lace alone), all 1-day-old — Misha had been running parallel sessions opening PRs faster than they could be reviewed. The drift backlog's diagnostic value is real: making the unmerged-state visible IS the value, even before any of them merge.

