# Existing-Project Gap-Audit Runbook

**Purpose:** sequenced, mechanical checklist for running a thorough gap audit on an existing application using the Build Doctrine substrate. The runbook surfaces structural gaps (convention drift, missing canon, undocumented contracts), functional gaps (broken flows, unimplemented features), and UX gaps (jargon, dead ends, accessibility) — and routes each finding to the correct fix-substrate (findings ledger / discoveries / ADRs / plans).

**When to use:** when a real product needs a thorough audit before declaring it "fully functional," or when adopting the doctrine on a project that already has code + history.

**When NOT to use:** brand-new projects (use Stage 0 bootstrap directly per `08-project-bootstrapping.md`); pure-prototype throwaway code (the audit overhead exceeds the value); projects whose readiness checklist (Phase 0 below) doesn't pass.

**Precondition:** the Build Doctrine substrate is shipped. Specifically: `build-doctrine/doctrine/`, `build-doctrine-templates/`, `build-doctrine/template-schemas/`, the propagation engine (`adapters/claude-code/hooks/propagation-trigger-router.sh`), the audit-log analyzer (`adapters/claude-code/scripts/analyze-propagation-audit-log.sh`), the pilot-friction template (`adapters/claude-code/templates/pilot-friction.md`), and `/harness-review` Check 13. As of 2026-05-06, all of these are landed.

**Estimated total time:** 8-15 hours for a mid-sized project, spread across multiple sessions. Not a single-session run.

**Where to run:** in the project's working directory (NOT the harness repo). All commits and findings land in the project's repo. Cross-references back to the harness repo where the substrate lives.

---

## Phase 0 — Pre-flight (before starting)

### Step 0.1 — Pilot-readiness check (≤ 30 min)

Answer the 10-question checklist from [`docs/build-doctrine-roadmap.md`](../build-doctrine-roadmap.md) "How to determine pilot readiness" (or `~/.claude/CLAUDE.md` cross-reference). Pattern reading:

- 9-10 yes → GO
- 6-8 yes → review the no's; proceed if no hard blocker
- 3-5 yes → WAIT 1-3 months
- 0-2 yes → WRONG project

Hard blockers (any one = WAIT regardless of count): no real users, no person-week of bandwidth, impending crisis competing for time.

**Output artifact:** `docs/sessions/<YYYY-MM-DD>-pilot-readiness.md` in the project repo. Check answers + verdict + named blockers if any.

**Done when:** verdict is GO, or runbook is paused with a named resumption trigger.

### Step 0.2 — Session setup

```bash
# In the project's working directory:
cd <project-root>

# Verify the harness is available:
ls ~/.claude/scripts/analyze-propagation-audit-log.sh   # should exist
ls ~/.claude/templates/pilot-friction.md                # should exist
ls ~/.claude/skills/harness-review.md                   # should exist

# Verify the doctrine is reachable:
ls ~/claude-projects/neural-lace/build-doctrine/        # should exist

# Confirm git state is clean (uncommitted work makes this audit messy):
git status
```

**Done when:** all four checks pass + working tree is clean.

### Step 0.3 — Open the audit plan

Use `~/.claude/scripts/start-plan.sh` to scaffold the audit plan in the project's repo:

```bash
~/.claude/scripts/start-plan.sh start project-gap-audit-<YYYY-MM-DD> \
  "Thorough gap audit per existing-project runbook. Phases A-F. Outputs canon artifacts + findings ledger entries + per-fix plans." \
  --tier 3 --rung 2 --architecture orchestration
```

The plan's tasks correspond to the phases below.

**Output artifact:** `docs/plans/project-gap-audit-<YYYY-MM-DD>.md` in the project repo.

---

## Phase A — Extraction (~ 2-4 hours)

The doctrine's "Adopting doctrine on existing projects" protocol step 2: read the codebase + infer current state. The output is the *current-state snapshot* — knowing what exists is the precondition for knowing what's missing.

### Step A.1 — Architecture extraction

Read `src/` (or equivalent). Produce an extracted view of:

- **Module boundaries.** What's the high-level structure? Frontend / API / worker / DB layers?
- **External boundaries.** What services does the app call? Payment, email, auth providers, third-party APIs.
- **Data flow.** A handful of representative request flows from user action to persistence and back.
- **State management.** Where does state live? React state, Redux/Zustand/Jotai, server-side, in URLs?
- **Async patterns.** Queues, schedulers, durable workflows, event-driven, polling?

**Output artifact:** `docs/extracted-state.md` in the project repo. This is a snapshot — not committed to as canon, but used as input to Phase B.

**Done when:** a reader who's never seen the project can describe its high-level architecture from this doc.

### Step A.2 — Convention extraction

Walk the existing code looking for de-facto conventions:

- File naming (kebab vs camel vs snake)
- Component file naming (PascalCase vs kebab)
- Test file naming (`*.test.ts` vs `tests/*` vs co-located)
- Import style (absolute via `@/` vs relative)
- Error-handling pattern (typed classes vs sentinel values vs exceptions)
- Logging library + format
- Auth pattern (token, session, cookies, third-party IdP)
- Branch + commit conventions

**Output artifact:** Extract into a draft `docs/conventions.md` (Phase B will normalize this against `build-doctrine-templates/conventions/` defaults).

**Done when:** every category in the 11 universal floors has either a stated convention from the codebase OR an explicit "no convention observed" entry.

### Step A.3 — Existing-doc inventory

Catalog what already exists in the project's `docs/` (or equivalent):

- READMEs (root + per-package)
- ADRs / decision records
- Plan files
- Reviews
- Sessions
- Architecture/strategy docs
- Operational runbooks

**Output artifact:** `docs/inventory.md` listing everything with one-line summaries.

**Done when:** the inventory is exhaustive enough that nobody can point at an existing doc and say "you missed this."

---

## Phase B — Generate canon artifacts (~ 2-4 hours)

The doctrine's 7 canon artifacts. Generate each from the extracted current state + the templates at `build-doctrine-templates/`. Schema-validate each against `build-doctrine/template-schemas/`.

### Step B.1 — PRD

Generate `docs/prd.md`. Required sections per `prd.schema.yaml`:
1. Problem
2. Scenarios
3. Functional requirements (numbered FR-N)
4. Non-functional requirements (numbered NFR-N, each with numeric target)
5. Success metrics (numbered SM-N, each with numeric target + measurement method)
6. Out-of-scope (with rationale per entry)
7. Open questions (numbered OQ-N, current direction + decision process)

Then invoke `prd-validity-reviewer` agent against it. The reviewer is *adversarial about substance* — placeholder content, hand-waving NFRs, unmeasurable success metrics will be flagged.

**Output artifact:** `docs/prd.md` (committed) + reviewer-feedback notes in `docs/reviews/<date>-prd-validity.md` (committed).

**Done when:** reviewer returns PASS or every flagged gap has either a fix or a documented "deferred to vN" decision.

**Gaps surfaced this step:** missing-product-clarity, missing-success-metrics, missing-out-of-scope (the most common product-level failure modes).

### Step B.2 — ADR ledger reconstruction

For non-trivial historical decisions that exist in the code but lack ADRs, write retroactive ADRs. Format per `adr.schema.yaml`. Naming: `docs/decisions/NNN-<slug>.md`.

Don't try to write 50 ADRs in one pass. Instead: list the top 10 architectural decisions that would surprise a new engineer, write ADRs for those, then move on. The list itself is captured in `docs/decisions/000-adr-backlog.md` for future passes.

**Output artifact:** `docs/decisions/NNN-*.md` files + `docs/DECISIONS.md` index updated atomically (`decisions-index-gate.sh` enforces).

**Done when:** the top 10 surprising decisions are documented; backlog of remainder is captured.

**Gaps surfaced:** undocumented-architectural-rationale, hidden-coupling, "everyone-knows-but-nobody-wrote-it-down" (the latter is the most common — and the one new engineers ask about).

### Step B.3 — Conventions doc

Take the draft from Step A.2 and normalize against `build-doctrine-templates/conventions/`:

- For each of the 11 universal floors: state the project's convention. If it matches the template default, cite the default ("Per `~/.claude/templates/conventions/universal-floors/01-logging/standard.md`"). If it deviates, document the deviation + rationale (deliberate choice → ADR; deviation-without-rationale → finding).
- Per-language naming: cite `build-doctrine-templates/conventions/naming/<lang>.md` if matching defaults; document deviations.
- Branching/commits: cite `build-doctrine-templates/conventions/branching-and-commits.md` if matching.

**Output artifact:** `docs/conventions.md` validating against `conventions.schema.yaml`.

**Done when:** every floor has either a "matches default" pointer or a "deviates because X" rationale + ADR.

**Gaps surfaced:** convention-drift (different patterns in different parts of the codebase), under-specification (no convention at all for a floor that should have one), over-specification (conventions that the codebase doesn't actually follow).

### Step B.4 — Design system (UI projects)

Skip if not a UI project. For UI projects: extract design tokens (color, spacing, typography, motion), components, states, patterns. Schema: `design-system.schema.yaml`.

**Output artifact:** `docs/design-system.md`.

**Done when:** every component referenced in source has a catalog entry + every token used has a definition.

**Gaps surfaced:** color-rule violations (red-not-error, missing dark variants, outline-only-buttons), missing-states (loading/error/empty/success), accessibility-tier gaps.

### Step B.5 — Engineering catalog

For each work-shape that's recurred 3+ times in the project's history (`add-api-endpoint`, `add-react-component`, `add-migration`, etc.), write a canonical work-shape entry per `engineering-catalog.schema.yaml`.

Use `git log` + commit-message clustering to find recurrences. Tools like `git log --pretty=format:"%s" | sort | uniq -c | sort -rn` give a rough start.

**Output artifact:** `docs/engineering-catalog.md`.

**Done when:** every recurring work-shape has a canonical entry; one-off work has no entry (don't over-canonicalize).

**Gaps surfaced:** repeated-mistakes-in-similar-work (e.g., API endpoints that consistently miss validation), missing-mechanical-checks for shapes that should have them.

### Step B.6 — Observability doc

Document what the app emits today (logs / metrics / traces / dashboards / alerts / runbook). Schema: `observability.schema.yaml`. The 4 golden signals (latency / traffic / errors / saturation) per service should be the minimum.

**Output artifact:** `docs/observability.md`.

**Done when:** every public-facing endpoint or critical workflow has signals declared + an alert defined for user-impacting failure.

**Gaps surfaced:** missing-observability (can't reconstruct what happened from logs), alerting-on-noise (alerts that don't trigger action), missing-runbook (alerts without remediation steps).

### Step B.7 — Bootstrap state

`.bootstrap/state.yaml` captures which floors were applied, which were deferred, which were overridden. This is the audit trail for the next bootstrap iteration.

**Output artifact:** `.bootstrap/state.yaml` in the project repo.

**Done when:** every entry in floors / canon-artifacts / conventions has a status (applied / deferred / overridden) + rationale.

---

## Phase C — Run gap-finders systematically (~ 3-5 hours)

The audits below produce findings (`docs/findings.md` entries) or discoveries (`docs/discoveries/<date>-*.md` files). Each finding has six fields per `findings-ledger.md` schema (ID / Severity / Scope / Source / Location / Status).

### Step C.1 — Acceptance scenarios (end-user advocate, plan-time mode)

For each major user flow in the PRD's Scenarios section, invoke the `end-user-advocate` agent in plan-time mode to author acceptance scenarios.

```
Invoke end-user-advocate via Task tool:
  mode: plan-time
  plan: docs/plans/project-gap-audit-<date>.md
  scope: existing application audit; extract user flows from PRD
```

The advocate produces `## Acceptance Scenarios` content with user flows, success criteria, expected artifacts.

**Output artifact:** `## Acceptance Scenarios` populated in the audit plan.

**Done when:** every major user flow has at least one scenario; advocate has no remaining feedback.

**Gaps surfaced:** unspecified-success-criteria, ambiguous-flows, hidden-preconditions.

### Step C.2 — Acceptance scenarios (runtime mode against live app)

Spin up the dev server. Invoke the advocate in runtime mode against the live app. The advocate executes each scenario, captures screenshots / network logs / console logs.

**Output artifact:** `.claude/state/acceptance/<plan-slug>/<session-id>-<timestamp>.json` + sibling artifact files.

**Done when:** every scenario has a PASS or FAIL verdict against the running app.

**Gaps surfaced:** broken-user-flows, undefined-error-states, dead-ends, missing-empty-states (this is the layer where most "essentially complete" apps have silent gaps).

### Step C.3 — UX testers (3 agents)

Run all three UX testing agents per `~/.claude/rules/testing.md` "UX Validation":

1. **UX End-User Tester** — generic non-technical user walkthrough
2. **Domain Expert Tester** — becomes the project's target persona (defined at `.claude/audience.md`)
3. **Audience Content Reviewer** — reads all user-facing text for jargon, placeholders, empty content

**Output artifact:** `docs/reviews/<date>-ux-end-user-tester.md`, `<date>-domain-expert-tester.md`, `<date>-audience-content-reviewer.md`. P0/P1 findings → `docs/findings.md` entries; P2 → backlog.

**Done when:** all P0 and P1 findings are either fixed or have plan-shaped fix work scheduled.

**Gaps surfaced:** UX-broken-flows, jargon-for-target-audience, missing-affordances, accessibility-violations, content-placeholder-leaks.

### Step C.4 — Floor-by-floor audit

For each of the 11 universal floors, ask: "what does the project's current implementation look like vs. the convention?" Findings go to `docs/findings.md`.

For each floor:
- Open the convention statement (from `docs/conventions.md` Step B.3)
- Walk the codebase looking for deviations from the stated convention
- Each deviation = finding entry

**Output artifact:** ~10-30 findings ledger entries (typical for a mid-sized project).

**Done when:** all 11 floors have been audited; deviations are captured as findings.

**Gaps surfaced:** convention-drift instances; the *cumulative* drift report informs whether the project's conventions doc needs revision (sometimes the conventions are wrong, not the code).

### Step C.5 — Code-reviewer audit on a representative sample

Invoke `code-reviewer` agent against a representative sample of recent commits + a sample of the most-frequently-touched files. The agent looks for the standard quality issues (auth gaps, error handling, integration mistakes, edge cases).

**Output artifact:** `docs/reviews/<date>-code-reviewer-sample.md`.

**Done when:** the sample has been reviewed; findings logged.

**Gaps surfaced:** quality issues at the line level — auth/authz drift, missing error paths, silent failure modes, edge-case neglect.

### Step C.6 — Security review

Invoke `security-reviewer` agent on the codebase. Focus on auth flows, data handling, third-party API calls, input validation.

**Output artifact:** `docs/reviews/<date>-security-review.md`.

**Done when:** the review surfaces zero P0 findings or all P0 findings have planned mitigations.

**Gaps surfaced:** auth/authz vulnerabilities, leaky data, injection-class issues, supply-chain risks.

### Step C.7 — Propagation-engine wiring + audit-log first run

Wire the propagation engine into the project's PostToolUse / Stop chain. Then run typical work-flow events through it for a session and look at the audit log:

```bash
# Sample event invocations:
~/.claude/hooks/propagation-trigger-router.sh evaluate plan-status-flip --path docs/plans/foo.md --meta status_to=COMPLETED
~/.claude/hooks/propagation-trigger-router.sh evaluate decision-record-created --path docs/decisions/042-foo.md
~/.claude/hooks/propagation-trigger-router.sh evaluate doctrine-doc-modified --path build-doctrine/doctrine/04-gates.md

# Then read the audit log:
~/.claude/scripts/analyze-propagation-audit-log.sh summary
~/.claude/scripts/analyze-propagation-audit-log.sh cadence
~/.claude/scripts/analyze-propagation-audit-log.sh unmatched
~/.claude/scripts/analyze-propagation-audit-log.sh slow
```

The `unmatched` subcommand specifically surfaces "events nobody's policing" — candidates for new rules.

**Output artifact:** `docs/reviews/<date>-propagation-audit-first-run.md` capturing summary + unmatched events + interpretation.

**Done when:** the analyzer has run; findings about unmatched events have been triaged.

**Gaps surfaced:** propagation-rule-coverage gaps; events that *should* fan out but don't.

### Step C.8 — `/harness-review` Check 13 — KIT-1..KIT-7 sweep

Invoke `/harness-review` skill. Check 13 surfaces:
- KIT-1 calibration patterns (per-agent observation log)
- KIT-2 findings patterns (counts in `docs/findings.md`)
- KIT-3 discovery accumulation
- KIT-4 ADR-cross-reference staleness
- KIT-5 itself (this run)
- KIT-6 propagation audit log
- KIT-7 drift signal (no-op until 5c)

**Output artifact:** `docs/reviews/<date>-harness-review.md` includes the Check 13 KIT sweep section.

**Done when:** every KIT trigger has either a "no signal yet" or a structured summary.

**Gaps surfaced:** patterns the operator hasn't noticed across calibration / findings / discoveries / ADRs.

---

## Phase D — Capture friction (~ ongoing during Phases A-C)

While Phases A-C run, capture friction in real time using the pilot-friction template at `~/.claude/templates/pilot-friction.md`.

**Output artifact:** `docs/sessions/<date>-pilot-friction-run-<N>.md` (one per major work-item-run-through-doctrine).

**Done when:** every floor exercised + every canon artifact generated has at least one friction-or-no-friction entry.

**Why:** without structured capture, friction becomes operator memory rather than counted observations. Tranches 5b / 6b / 7 in the harness consume this.

**Cross-link back to harness:** copy the friction notes (or summarize them) at `~/claude-projects/neural-lace/docs/reviews/<date>-pilot-<run-N>-friction.md` so the harness arc consumes them.

---

## Phase E — Plan the fixes (~ 1-2 hours per fix-bundle)

Findings from Phases A-D become plans. Tier-routed per `~/.claude/rules/planning.md`:

| Finding tier | Approach |
|---|---|
| **Tier 1** (single-file, < 15 min) | Fix inline; commit per the harness's anti-vaporware substrate. Findings entry status → Fixed: `<commit>`. |
| **Tier 2** (schema-bound, multi-file, < 1 day) | Plan via `start-plan.sh`; verify per task-verifier mandate; close via `close-plan.sh`. |
| **Tier 3+** (cross-module, contract change, novel) | Plan with full Behavioral Contracts section; require ADR; verify each task. |

**Don't attempt to fix everything in one session.** Stage by severity:
1. P0 (production-affecting, security, data-loss risk) — fix immediately
2. P1 (user-impacting, broken flows) — fix in the next 1-2 sessions
3. P2 (polish, convention drift, doc gaps) — accumulate, fix in batches

**Output artifact:** plans + commits + findings ledger updates (status: Fixed / In Progress / Deferred).

**Done when:** P0 + P1 findings have plans or completed fixes; P2 backlog is named.

---

## Phase F — Iterate via runtime exercise (~ ongoing)

After fixes land, re-run the gap-finders. Specifically:

- C.2 (runtime acceptance) on the fixed flows
- C.7 (audit log) once enough events have accumulated
- C.8 (`/harness-review` Check 13) at the cadence the 5a doctrine doc declares (monthly default — itself a hypothesis, refined per pilot evidence)

**Output artifact:** `docs/reviews/<date>-iteration-<N>.md` capturing what's still gappy.

**Done when:** P0 + P1 findings are at zero; the project's KIT-2 (findings pattern) trigger no longer surfaces concentrations.

---

## What success looks like

After running this runbook to completion (likely 3-5 sessions, days to a week of focused work):

- The 7 canon artifacts exist in the project repo + validate against the schemas.
- `docs/findings.md` has a structured backlog of remaining gaps with severity + scope.
- P0 + P1 findings are fixed or planned.
- The propagation audit log is accumulating evidence that informs Tranches 5b / 6b / 7 in the harness.
- The pilot-friction notes provide structured input for those harness tranches.
- The project has a clear "this is what's broken, this is what's not, this is what's deliberately deferred" map.

**What "fully functional" means:** P0 = 0; P1 has a plan; P2 is captured. Beyond that is iterative refinement, not a binary state.

---

## Caveats + honest limitations

- **The audit surfaces; the agent fixes.** This runbook is the *map of where to look*; the looking + fixing is real work that happens via the harness's plan / commit / verify / close substrate.
- **Some gaps need empirical signal the audit can't synthesize.** Performance bottlenecks under real load, race conditions under real concurrency, accessibility issues real users hit — those need actual exercise. The runbook accelerates discovery but doesn't replace running the app at scale.
- **The project's audience definition matters.** If `.claude/audience.md` is missing or generic, the UX testers (C.3) will be less useful. Define audience first.
- **The runbook is generic.** Per-project tuning is expected. Some phases may not apply (B.4 design system for non-UI projects); some may need expansion (security-heavy projects deserve a deeper Phase C.6).
- **Cross-project pattern detection is gated.** Cross-project patterns surface via Tranche 5c + HARNESS-GAP-11 telemetry (2026-08). Within a single project, single-project patterns surface via the local audit log + findings ledger.

---

## Cross-references

- **Doctrine ritual** (consumes the audit findings): [`build-doctrine/doctrine/07-knowledge-integration.md`](../../build-doctrine/doctrine/07-knowledge-integration.md)
- **Bootstrap protocol**: [`build-doctrine/doctrine/08-project-bootstrapping.md`](../../build-doctrine/doctrine/08-project-bootstrapping.md) "Adopting doctrine on existing projects" section
- **Pilot-friction template**: `~/.claude/templates/pilot-friction.md`
- **Audit-log analyzer**: `~/.claude/scripts/analyze-propagation-audit-log.sh`
- **Findings ledger schema + rule**: `~/.claude/rules/findings-ledger.md`
- **`/harness-review` Check 13** (KIT sweep): `~/.claude/skills/harness-review.md`
- **Schemas for canon artifacts**: `build-doctrine/template-schemas/{prd,adr,spec,design-system,engineering-catalog,conventions,observability}.schema.yaml`
- **Templates for canon-artifact content**: `build-doctrine-templates/conventions/`

## What this runbook is + isn't

**It is:** a sequenced operational checklist to run an existing-project gap audit using the substrate the harness ships. Each step has an output artifact + done-when criterion, so it's resumable across sessions.

**It is not:** a guarantee of "fully functional." It surfaces a structured view of gaps. Fixing them is the project's actual development work — accelerated by the substrate, not replaced by it.

**It is not:** the canonical Tranche 4 plan for the harness arc. It can BECOME that — if the project running this runbook is the canonical pilot, the friction notes feed Tranches 5b / 6b / 7 directly. But the runbook itself is project-agnostic.

---

**Last updated:** 2026-05-06 (initial draft, generic for any existing project)
