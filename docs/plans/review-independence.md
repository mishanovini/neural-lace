<!-- scaffold-created: 2026-07-30T00:05:09Z by start-plan.sh slug=review-independence -->
# Plan: Review Independence
Status: ACTIVE
Execution Mode: orchestrator
Mode: code
Backlog items absorbed: none
acceptance-exempt: true
acceptance-exempt-reason: Harness-internal governance mechanism (review queue + doctor check + doctrine); no product user-facing surface, maintainer is the user per constitution section 4.
tier: 3
<!--
tier values (Build Doctrine `03-work-sizing.md`):
  1  Contained        Single file or small isolated change; no schema or
                      contract impact; reversible in minutes.
  2  Schema-Bound     Touches a schema or persistent shape; revertible
                      via migration; contained blast radius.
  3  Cross-Module     Spans modules / services; integration testing
                      required; revertible via coordinated change.
  4  Contract         Modifies a public API, external interface, or
                      cross-team contract; requires architecture review.
  5  Novel            New architectural pattern, new external dependency,
                      irreversible production data effects, or research
                      work without prior precedent.

Required by `plan-reviewer.sh` Check 10 on `Status: ACTIVE` plans.
See `~/.claude/doctrine/planning.md` and Decision 017.
-->

rung: 5
<!--
rung values (autonomy / sophistication tier):
  0  read-only-context        Plan informs other plans; produces no
                              executable artifacts.
  1  knowledge-integrator     Plan integrates known patterns; minimal
                              novel design.
  2  early-stage              Plan introduces a small new mechanism in
                              a well-understood area.
  3  formalized               Plan formalizes a behavior with explicit
                              contracts; requires `## Behavioral
                              Contracts` section (C16, plan-reviewer
                              Check 11).
  4  autonomous               Plan ships a mechanism that operates
                              autonomously after deploy; requires
                              behavioral contracts + runbook.
  5  meta                     Plan modifies the harness's own
                              meta-rules or governance.

Required by `plan-reviewer.sh` Check 10. At `rung: 3+`, Check 11
requires `## Behavioral Contracts` with four sub-entries
(idempotency, performance budget, retry semantics, failure modes).
-->

architecture: coding-harness
<!--
architecture values (Build Doctrine §9 Q4-A):
  coding-harness    Work targets the coding-harness family (Claude Code
                    rules, hooks, agents, templates).
  dark-factory      Work targets the dark-factory family (autonomous
                    background workflows operating without interactive
                    steering).
  auto-research     Work targets the auto-research family (research and
                    knowledge-integration pipelines).
  orchestration     Work targets the orchestration layer (plan
                    dispatch, multi-agent coordination, lifecycle
                    management).
  hybrid            Work spans two or more families; cite which in the
                    plan body.

Required by `plan-reviewer.sh` Check 10.
-->

frozen: true
<!--
frozen values (spec-freeze gate, Decision 016):
  false   Default for new plans. Spec is still being authored. The
          plan cannot govern edits yet — spec-freeze-gate.sh BLOCKS
          edits to files declared in `## Files to Modify/Create`
          while frozen is false.
  true    Spec is settled; declared scope is committed. The gate
          ALLOWS edits to declared files. To amend a frozen spec,
          flip back to false, record a Decisions Log entry naming
          the amendment + rationale, make the amendment, then
          re-flip true.

Required by `plan-reviewer.sh` Check 10.
See `~/.claude/doctrine/spec-freeze.md` for the freeze-thaw protocol.
-->

lifecycle-schema: v2
loe-class: harness-mechanism
<!--
loe-class — LOE reference class for calibration (accountable-estate T7).
Pick the closest class; plan-reviewer Check 18 surfaces the mined P50/P90
bands for it from docs/loe/loe-calibration.json (WARN-only, never blocks).
Class list MUST stay in sync with loe-backfill.sh's lb_classify. An
unsubstituted placeholder here draws Check 18's invalid-value nudge —
that nudge IS the reminder to pick.
-->
<!--
lifecycle-schema marks a plan as governed by the mechanical-closure
redesign (ADR 036). Its PRESENCE is the grandfather signal: pre-redesign
plans lack the field, so plan-reviewer.sh Check 14 (owner +
target-completion-date) and Check 15 (## Closure Contract) SKIP them.
A plan created from this template carries `lifecycle-schema: v2` and is
therefore enforced. This is sub-decision 036-d (D2 option iii — enforce
on the ACTIVE transition only; never retroactively block already-ACTIVE
pre-redesign plans). Backfilling the field into a legacy plan opts that
plan into the new gates. Do not remove it from a new plan to dodge the
gates — that is the same anti-pattern as deleting a test to make a build
pass. See ~/.claude/doctrine/planning-full.md (Plan File Lifecycle) and Decision 036.
-->

owner: misha
<!--
owner — who is accountable for this plan reaching a terminal state
(COMPLETED / ABANDONED / SUPERSEDED / DEFERRED). One accountable human.
Required (non-empty) on `Status: ACTIVE` plans that carry
`lifecycle-schema: v2`, per plan-reviewer.sh Check 14. Sub-decision
036-d. Pass via `start-plan.sh --owner <name>`.
-->

target-completion-date: 2026-08-05
<!--
target-completion-date — the date by which the owner commits this plan
will reach a terminal state, in YYYY-MM-DD form. A falsifiable
structural commitment, not a wish. Required + well-formed on
`Status: ACTIVE` v2 plans, per plan-reviewer.sh Check 14. The staleness
commitment-breach gate (R5, future) reads this field. Pass via
`start-plan.sh --target-date <YYYY-MM-DD>`.
-->

prd-ref: n/a — harness-development
<!--
prd-ref values (PRD-validity gate, Decision 015):
  <slug>                          Refers to a feature documented in
                                  the project's `docs/prd.md`. The
                                  prd-validity-gate.sh hook resolves
                                  the reference to docs/prd.md and
                                  verifies all 7 required sections
                                  (problem, scenarios, functional,
                                  non-functional, success metrics,
                                  out-of-scope, open-questions) are
                                  present and substantive.
  n/a — harness-development      Carve-out for plans whose work
                                  product IS the harness itself
                                  (rules, hooks, agents, templates,
                                  decision records). Bypasses C1
                                  entirely. Exact phrasing required
                                  (em-dash). Auditable via grep.

Required by `plan-reviewer.sh` Check 10.
See `~/.claude/doctrine/prd-validity.md` and `adapters/claude-code/templates/prd-template.md`.
-->

ask-id: none
<!--
ask-id — the ask-registry entry (`~/.claude/state/ask-registry.jsonl`) this
plan serves. Plan headers record it, and plan creation back-links the
registry in the other direction (the registry entry's `plan_slugs[]` gains
this plan's slug) — see `adapters/claude-code/doctrine/planning.md`. Pass at
creation via `start-plan.sh --ask-id <id>`, which calls `ask-registry.sh
link-plan --ask-id <id> --plan-slug <slug>` for you; a plan with no
originating ask may state `ask-id: none — no linked ask`.

SENTINEL COUPLING (2026-07-28): the literal token `none` and any `<`-prefixed
token on this line are RESERVED sentinels, never real ask-ids. Every ask-id
extractor resolves both to "no linked ask": `hooks/plan-lifecycle.sh`,
`hooks/workstreams-emit.sh`, `hooks/lib/merge-scan-lib.sh`,
`scripts/close-plan.sh`, `scripts/remap-placeholder-ask-events.sh`; the
writer-side map lives in `hooks/lib/progress-log-lib.sh` (`pl_path_for`:
placeholder-shapes quarantine to unattributed.jsonl, `none`/empty route to
unlinked.jsonl). If the ask-id default spelling just above ever changes, extend the
sentinel class at ALL of those sites in the SAME commit — a new spelling that
the extractors don't recognize recreates the 2026-07-27 misfiled-events bug
(1,140 events under `_id.jsonl` + 141 under `none.jsonl`).

`plan-reviewer.sh` WARNS (never blocks) when an ACTIVE `lifecycle-schema: v2`
plan lacks a populated value here — advisory only, since grandfathered plans
predate this field and not every plan is asked for through a captured
session prompt. See docs/decisions/062-ask-rooted-workstreams-p1.md.
-->

<!--
acceptance-exempt values:
  false   Default. The plan undergoes end-user-advocate review at plan-time
          (scenarios authored into `## Acceptance Scenarios`) AND runtime
          (browser-automation execution before session end). Required for
          any plan that affects user-observable product behavior.
  true    Skip the acceptance loop. Reserved for plans with NO product
          user — harness-development plans, pure-infrastructure plans
          (e.g., a Dockerfile change with no user-facing surface), and
          migration-only plans without UI implications. When `true`, the
          companion field `acceptance-exempt-reason:` MUST contain a
          one-sentence substantive justification (>= 20 chars). The
          `product-acceptance-gate.sh` Stop hook honors the exemption;
          `harness-reviewer` may audit the rationale.

See `~/.claude/doctrine/acceptance-scenarios.md` for the full plan-time →
runtime → gap-analysis loop and explicit when-to-use guidance for the
exemption.

Execution Mode values:
  orchestrator  Default for multi-task plans. The main session reads this plan,
                dispatches each task to a `plan-phase-builder` sub-agent via the
                Task tool, and collects results. The main session does NOT do the
                build work itself — it stays lean as an orchestrator. See
                ~/.claude/doctrine/orchestrator-pattern.md for the full protocol.
  direct        Single-task quick fixes (one file, < 15 min). The main session
                does the work directly. No sub-agent dispatch overhead.
  agent-team    Uses Anthropic's experimental Agent Teams feature
                (CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1) for peer-to-peer
                teammate coordination with a shared task list. Gated by
                `enabled: true` in ~/.claude/local/agent-teams.config.json
                (default false). See ~/.claude/doctrine/agent-teams.md for the
                full protocol, the upstream-bug list, and when to prefer this
                over orchestrator. Decision record:
                docs/decisions/012-agent-teams-integration.md.

If unsure, use orchestrator. The overhead of dispatching is small; the cost of
running a multi-phase plan in one context is large (context accumulates 200+
tool uses, quality degrades). agent-team is reserved for plans whose work fits
the peer-to-peer messaging model and where the user has explicitly enabled the
Agent Teams flag.

Backlog items absorbed — required. Declares which `docs/backlog.md` open items
this plan claims. The hook `backlog-plan-atomicity.sh` enforces that absorbed
items are deleted from the backlog's open sections in the same commit as the
plan file creation.

  Backlog items absorbed: none
      Use when the plan addresses a fresh user request not previously tracked
      in the backlog (single-task quick fixes, ad-hoc bug reports, new feature
      requests). The plan creates no obligation against the backlog.

  Backlog items absorbed: add-link-validation, dark-mode-contrast-audit
      Use when the plan claims two existing backlog items. Those exact entries
      must be deleted from the backlog's open sections in the same commit. On
      plan COMPLETION the items ship archived inside the completion report. On
      ABANDONMENT or DEFERRAL the items return to the backlog with a
      `(deferred from <plan-path>)` note.

See ~/.claude/doctrine/planning.md, "Backlog absorption at plan creation".

Mode values:
  code    Default. Code-level work — bug fixes, UI changes, refactors,
          test additions, isolated feature work. Iteration cost is low
          (seconds to minutes), failures are cheap, iterate-and-observe
          works. No systems-engineering sections required.

  design  System-design work where iteration cost is high and failures
          compound. Required for: CI/CD workflows, database migrations,
          infrastructure config (vercel.json, Dockerfile, etc.),
          deployment systems, multi-component features that cross
          service boundaries, anything where tools-I-haven't-used-before
          enter the pipeline. When Mode: design, the "Systems
          Engineering Analysis" section at the bottom of this template
          is REQUIRED and enforced by plan-reviewer.sh. The
          systems-designer agent MUST review the plan before
          implementation begins.

See ~/.claude/doctrine/design-mode-planning.md for the full protocol on
design-mode tasks.
-->

<!--
Required sections (enforced by plan-reviewer.sh):
  Goal, Scope, Tasks, Files to Modify/Create, Assumptions, Edge Cases,
  Testing Strategy

Every required section must contain substantive, plan-specific content —
not placeholder text. See ~/.claude/doctrine/planning.md, "Verbose Plans Are
Mandatory", for the full rule. Verbose planning is mandatory regardless
of plan size.
-->

## Goal
**Continues/absorbs the open thread from `docs/plans/verification-dispatch-directive.md`'s V6**
("the commit-time carrier gate ... its own §10 evidence bar" — V6 itself landed
2026-07-29 as `review-record-commit-gate.sh`; that plan's Status stays ACTIVE and this
plan does not touch its file list). V6 made "whether a review happens" mechanical
(commit-time block on uncovered in-surface content). It could not make WHO reviews
independent of WHO authored — nothing stopped the authoring session from dispatching
`harness-reviewer` itself and writing its own PASS record via
`write-review-record.sh`. That gap is exactly what stopped this session mid-build: the
safety classifier refused to let this session dispatch a reviewer subagent and then
author the PASS record for its OWN prior commits — correctly recognizing self-approval.
`doctrine/review-before-deploy.md`'s own honesty_rationale already names the residual
("cannot verify the quoted verdict is genuine ... NOT anti-fabrication",
`REVIEW-RECORD-ANTI-FABRICATION-ANCHOR-01` in `docs/backlog.md`).

This plan builds the structural fix: separate the reviewing principal from the
authoring principal, mechanically, so no session-level convention or self-restraint is
load-bearing. Per the operator's binding design direction mid-build (2026-07-29,
quoted in full in the Decisions Log), the fix rests on three deterministic points —
WHETHER a review happens (a mechanical trigger, never a session's choice), WHAT the
reviewer sees (a fixed template + the real diff, never enqueuer-supplied prose), and
WHAT the verdict becomes (written AND committed by the reviewing process itself, never
handed back to the author) — and on the pivot the operator drove after reviewing the
first draft: independence is about the PATHWAY (a genuinely different session/process
reviewing, using the harness's EXISTING adversarial reviewer agents), not about
physical machine locality (`docs/decisions/067-review-independence-same-session-
pathway.md`).

## User-facing Outcome
n/a — harness-internal: the "user" is the maintainer operating this harness. The
deliverable outcome is that (1) a harness change touching an uncovered in-surface file
can no longer be reviewed-and-approved by the same Claude Code session that authored
it — mechanically refused, not merely discouraged — and (2) `harness-doctor.sh` REDs
if a `harness-change-review` PASS record's own committing identity matches the
identity that authored the reviewed content. Demonstrated by each new script's
`--self-test` (both `/bin/bash` and `/opt/homebrew/bin/bash`) and by the doctor's new
RED/GREEN fixture scenarios — see Closure Contract.
<!--
REQUIRED. Operationalizes FUNCTIONALITY OVER COMPONENTS — the harness's
most important rule (~/.claude/doctrine/planning.md).

State concretely what a user can DO after this plan ships that they
could not do before. Not what code exists; what action becomes possible.

Bad (component-shaped):
  - "The state card schema exists and the migration has run."
  - "The /api/campaigns/launch endpoint returns 200."
  - "The detectConflict helper passes unit tests."

Good (functionality-shaped):
  - "When a customer sends a message, an AI response is generated that
    references a populated state card and stays within the rules the
    card encodes."
  - "A logged-in Manager clicking Launch on a campaign causes messages
    to be sent to every listed contact within 60 seconds; the Manager
    sees a 'sent N messages' confirmation."
  - "A user creating a rule that conflicts with an existing rule sees
    a visible warning in the UI before they can save, naming which
    existing rule it conflicts with."

The test for completion is always: can a user do the thing? If you
cannot demonstrate the user-facing outcome end-to-end against the
running system, the plan is not done — regardless of how clean the
code looks or how green the unit tests are.

Per-task user-facing outcomes live in each task's `**Prove it works:**`
sub-block (see Tasks section below). This section captures the
plan-level commitment: what does the whole plan deliver to the user?

If this plan genuinely has no user-facing outcome (acceptance-exempt:
true plans — harness-internal work, pure-infrastructure changes), say
so explicitly with a one-line justification:
    "n/a — harness-internal: the user is the maintainer; the
     `--self-test` of the new hook is the deliverable outcome."
-->
[What a user can do after this plan ships that they could not before.
Concrete, observable, demonstrable.]

## Scope
- IN: `review-queue.sh` (enqueue/list/get/claim/complete/mark-stale over a
  per-machine, optionally coord-repo-synced, state dir); the auto-enqueue mechanism
  that makes "attempting to commit uncovered content" mechanically trigger enqueue
  (a standalone library, `review-queue-auto-enqueue-lib.sh`, spliced into
  `review-record-commit-gate.sh` once a mid-build rebase reconciled this worktree's
  branch — see RI1b's Edge Case below); `review-runner.sh` (claim →
  prepare → finalize, run by a genuinely different session/process than the
  author's, using the harness's existing adversarial reviewer agents); the fixed
  `config/review-instructions.md` template; `write-review-record.sh`'s schema
  extension (`reviewer_principal`, `independence`); `harness-doctor.sh`'s
  `check_review_reviewer_independence`; the merge-time integration contract fragment
  for the (separately in-flight) estate-merge program; doctrine amendments to
  `review-before-deploy.md` and `verification-dispatch.md`.
- OUT: rewriting or gating `review-record-commit-gate.sh` itself (absent from this
  worktree's branch base — see Decisions Log; the splice is documented, not applied,
  here); a dedicated always-on desktop-runner daemon (explicitly rejected —
  `docs/decisions/067-review-independence-same-session-pathway.md`); a new reviewer
  agent definition (the plan reuses `harness-reviewer` et al., unchanged); building
  new cross-machine sync transport (the pre-existing `coord-sync.sh` cadence already
  covers a `REVIEW_QUEUE_STATE_DIR` pointed at its clone — optional hardening, not
  built here); a real anti-fabrication capture hook for `dispatch_evidence.verdict_quote`
  (that is `REVIEW-RECORD-ANTI-FABRICATION-ANCHOR-01`, still open — this plan
  addresses the SEPARATE self-approval gap, not the unrelated quote-forgery residual).

## Tasks

<!--
Mark tasks that CAN run in parallel with siblings using `[parallel]` or
group them under a batch header. Default is serial. Examples:

  [parallel] tasks that touch disjoint files and have no data dependency
  [serial]   tasks that share a file, depend on a previous task's commit,
             or compete for the same migration number / port / resource

The orchestrator reads these markers to decide dispatch batching. When in
doubt, leave unmarked (serial). See ~/.claude/doctrine/orchestrator-pattern.md
for the full safety rules on parallelization.

Per-task `Verification:` declaration (Tranche D of architecture-simplification,
2026-05-05). Each task description MAY end with `Verification: <level>`
where <level> is one of:

  mechanical   Deterministic bash check OR a structured `.evidence.json`
               artifact authored via `write-evidence.sh capture` (Tranche B).
               Use for: file edits, hook updates, prompt updates, schema
               authoring, sync-to-mirror, doc-only changes — anything where
               the verification is exists/grep/diff/typecheck/run-self-test.
               No agent dispatch needed.

  contract     Golden-file comparison or schema-validation match. Use for:
               schema work where output must conform to a locked shape, or
               where a reference fixture is the truth-target.

  full         Existing prose-evidence + task-verifier mandate. Use for:
               novel runtime work, UI / API / webhook / migration changes,
               anything where mechanical or contract checks cannot fully
               attest the user-observable outcome. This is the DEFAULT for
               unmarked tasks (backward compatibility).

If the field is omitted, `full` applies. The plan-edit-validator routes
checkbox-flip authorization per level. See
~/.claude/doctrine/risk-tiered-verification.md for the full protocol and
when to use each level.

Format examples:

  - [ ] 1. Author the new hook file at hooks/foo.sh — Verification: mechanical
  - [ ] 2. Migrate the doctrine docs to canonical glossary — Verification: contract
  - [ ] 3. Implement the runtime feature end-to-end — Verification: full
  - [ ] 4. Legacy task without declaration   (defaults to full)

REQUIRED per-task `Docs impact:` field (§F.2b, Wave F task F.2 — operator
directive 2026-07-04: docs are produced INSIDE the build loop, not tail-gated
onto session end). Every task declares the doc/README/runbook delta it
causes, or the literal word `none` with a one-clause reason:

  - [ ] 5. Add scripts/foo.sh generator — Verification: mechanical — Docs impact: adds a runbook stub at docs/runbooks/foo.md
  - [ ] 6. Refactor internal helper, no behavior change — Verification: mechanical — Docs impact: none — pure refactor, no doc surface
  - [ ] 7. Ship a new operator-facing capability — Verification: full — Docs impact: README section + harness-changelog.jsonl entry + digest line

`plan-edit-validator.sh` WARNS (never blocks) when a NEWLY-introduced task
line lacks a `Docs impact:` annotation — editing an existing task's wording
never triggers the warning, only brand-new task lines do. `task-verifier`
treats a non-`none` Docs-impact claim as part of that task's Done-when: if
the task claims a doc delta but the commit shows no corresponding doc/README/
runbook change, the verifier refuses to flip the checkbox (see
`agents/task-verifier.md`, Step 3 task-type-specific checks, "Documentation").
Prefer EXTENDING A GENERATOR over hand-editing a doc where one exists
(`scripts/gen-architecture-doc.sh`, `scripts/manifest-check.sh --gen-index`)
— generation beats maintenance.

INTEGRATION VERIFICATION — REQUIRED FOR EVERY `Verification: full` TASK
(or unmarked task, which defaults to full).

Every full-level task MUST include three sub-blocks immediately under the
task line, each populated with substantive task-specific content. The
plan-reviewer.sh Check 13 enforces presence + substance; the
wire-check-gate.sh PreToolUse hook blocks checkbox flip unless the
session's evidence file shows the "Prove it works" scenario was actually
executed.

  - [ ] 1. Build the campaign duplicate flow end-to-end — Verification: full
    **Prove it works:**
    1. Open /campaigns in the browser as a logged-in Manager
    2. Click the Duplicate button on the first campaign row
    3. Confirm a new row appears at the top with suffix "(Copy)"
    4. Confirm the original campaign is unchanged
    5. Reload the page and confirm the duplicate persists
    **Wire checks:**
    - `src/components/CampaignList.tsx` `Duplicate` button → `POST /api/campaigns/duplicate`
    - `src/app/api/campaigns/duplicate/route.ts` → imports `duplicateCampaign` from `src/lib/campaigns.ts`
    - `src/lib/campaigns.ts` `duplicateCampaign` function → `INSERT INTO campaigns` SQL
    - `src/app/api/campaigns/duplicate/route.ts` JSON response → `src/components/CampaignList.tsx` calls `setCampaigns`
    **Integration points:**
    - /api/campaigns/duplicate endpoint (Task 2 prerequisite) — verify with `curl -X POST /api/campaigns/duplicate -d '{"id":<existing>}'` returns 200 + JSON `{id, name}`
    - campaigns table schema — verify `name` column accepts suffix without unique-constraint violation
    - If the task is standalone (no integration dependencies), state explicitly: "Integration points: n/a — standalone task with no cross-component coupling."

WIRE CHECKS FORMAT — load-bearing for static trace verification.

Each `→` arrow line in the Wire checks block declares ONE link in the
code-level chain (UI → API → business logic → DB → response → UI). The
wire-check-gate runs a STATIC TRACE on every task completion: it
parses each arrow, extracts backtick-quoted file paths and other
identifiers, verifies the files exist, and grep-verifies each non-file
token appears in at least one of the linked files. This catches the
"built but not wired" failure mode (renamed function, moved endpoint,
deleted import) without running the app.

Format rules:
- Each arrow line MUST contain at least one backtick-quoted file path
  that exists relative to the repo root.
- Additional backtick-quoted tokens (function names, SQL fragments,
  string literals, API routes) are cross-checked: each must appear
  via `grep -F` in at least one of the file paths on the SAME arrow.
- An identifier appearing only in prose between arrows is decorative —
  only backtick-quoted tokens are checked.
- Minimum 2 statically-verifiable arrow lines per task. Below that,
  the chain is too thin to detect breakage.

Carve-out (use sparingly — only for tasks with genuinely no code chain
to trace, e.g., a pure-config change to vercel.json, a comment-only
docs update promoted to full for runtime-significance reasons):

  **Wire checks:**
  - n/a — <one-sentence justification ≥ 30 chars explaining why no
    UI→DB chain applies to this task>

The static trace runs every time — that is the point. Even if no live
server is available to exercise the "Prove it works" scenario at task
completion, the gate still verifies the chain exists at the source level.
A future commit that breaks a chain link (renames a function, moves an
endpoint, deletes an import) is caught at the NEXT task completion
because the broken arrow grep-misses.

Runtime evidence (an actually-executed "Prove it works" scenario captured
in the evidence file or structured `.evidence.json` artifact) is
ADDITIVE: when present, the gate logs it as a stronger proof, but does
NOT require it. Static trace is the mandatory baseline; runtime is the
bonus when a running instance is available.

Each sub-block is mandatory; an empty or placeholder-only sub-block FAILS
Check 13. For tasks with `Verification: mechanical` or
`Verification: contract` (deterministic structural work — file edits,
schema authoring, doc migrations), the sub-blocks may be omitted.

If the work genuinely has no integration surface (pure refactor that
preserves all behavior, doc-only change marked Verification: mechanical,
etc.), promote the task to mechanical/contract level rather than
papering over the integration verification with placeholders.

See ~/.claude/doctrine/planning.md "Integration Verification — Every
Full-Level Task Must Prove It Works" for the full rule and the
~/.claude/hooks/wire-check-gate.sh self-test for worked PASS/FAIL
fixtures.
-->

- [ ] RI1. The review queue: `review-queue.sh` (enqueue/list/get/claim/complete/
      mark-stale, content-keyed dedup, self-claim refusal) + `review-queue-auto-
      enqueue-lib.sh` (the "committing IS enqueueing" mechanism, standalone per
      the Edge Case below) + importing `scripts/lib/state-json-init.sh` (this
      worktree's branch base predates it). Verification: mechanical — self-test
      is the oracle (`review-queue.sh --self-test`,
      `review-queue-auto-enqueue-lib.sh --self-test`). Docs impact: this plan
      file + the script's own header comment is the documentation; no separate
      runbook.
- [ ] RI2. The reviewer runner: `review-runner.sh` (claim → prepare → finalize,
      staleness re-verified at both claim and finalize) + the fixed
      `config/review-instructions.md` template (itself in-surface, reviewed like
      any other harness content). Verification: mechanical — self-test is the
      oracle (`review-runner.sh --self-test`). Docs impact: `config/review-
      instructions.md` IS the doc surface this task adds.
- [ ] RI3. Reviewer identity + the author-ne-reviewer doctor check:
      `write-review-record.sh`'s `reviewer_principal`/`independence` schema
      extension (additive, backward-compatible) + `harness-doctor.sh`'s
      `check_review_reviewer_independence` (RED on git-commit-authorship
      self-approval) + the merge-time integration fragment for the estate-merge
      program. Verification: mechanical — self-test is the oracle
      (`write-review-record.sh --self-test`, `harness-doctor.sh --self-test`
      scenarios `review-reviewer-independence-{red,green,unresolvable}`). Docs
      impact: `docs/plans/fragments/review-independence-merge-fragment.md` (new).
- [ ] RI4. Doctrine amendment: `doctrine/review-before-deploy.md`'s residual
      paragraph updated from "cannot verify" to name the new mechanism (kept
      honest about what remains unsolved); `doctrine/verification-dispatch.md`
      gets the enqueue-never-review pointer. Verification: mechanical —
      `evals/golden/rules-index-coverage.sh` byte-cap check + manual re-read
      for honesty. Docs impact: the doctrine files ARE the doc delta.

## Files to Modify/Create
<!--
Every file this plan touches, grouped into Create vs Modify when useful.
Include a one-line reason per file so a reader can see the shape of the
change without opening each one.
-->
- `adapters/claude-code/scripts/review-queue.sh` — CREATE (RI1): the queue.
- `adapters/claude-code/hooks/lib/review-queue-auto-enqueue-lib.sh` — CREATE (RI1b):
  the mechanical enqueue trigger, standalone (see Edge Cases). Also gained the
  `HARNESS_SELFTEST` state-dir sandbox fix (see Decisions Log D6).
- `adapters/claude-code/hooks/review-record-commit-gate.sh` — MODIFY (RI1b, applied
  after the mid-build rebase reconciled this worktree's branch — see Edge Cases):
  the 3-line splice + a new self-test Scenario 23.
- `adapters/claude-code/scripts/lib/state-json-init.sh` — CREATE (RI1): imported,
  absent from this worktree's branch base at build start; byte-identical to the
  real one (superseded by the real file once the mid-build rebase landed).
- `adapters/claude-code/scripts/review-runner.sh` — CREATE (RI2): claim/prepare/finalize.
- `adapters/claude-code/config/review-instructions.md` — CREATE (RI2): fixed reviewer template.
- `adapters/claude-code/scripts/write-review-record.sh` — MODIFY (RI3, + an unrelated
  pre-existing bash-3.2 bugfix found while editing — see Decisions Log): adds
  `--reviewer-principal`/`--independence` to `capture`; also fixes a pre-existing
  `${var,,}` bash-4-only expansion that broke this script's OWN self-test via its
  shebang self-invocation on this repo's bash-3.2 floor.
- `adapters/claude-code/hooks/harness-doctor.sh` — MODIFY (RI3): adds
  `check_review_reviewer_independence` + registration + 3 self-test scenarios.
- `docs/plans/fragments/review-independence-merge-fragment.md` — CREATE (RI3): the
  estate-merge integration contract (read-only handoff; does not edit estate-merge.sh).
- `adapters/claude-code/doctrine/review-before-deploy.md` — MODIFY (RI4).
- `adapters/claude-code/doctrine/verification-dispatch.md` — MODIFY (RI4).
- `docs/decisions/067-review-independence-same-session-pathway.md` — CREATE: the
  mid-build pivot decision record (Tier 1, reversible).
- `docs/backlog.md` — MODIFY (RI4): note that this plan is the structural fix the
  `REVIEW-RECORD-ANTI-FABRICATION-ANCHOR-01` entry's Fix section pointed toward
  (for the self-approval class specifically — the quote-forgery residual stays open).

## In-flight scope updates
<!--
Plans aren't omniscient predictions of the future. When something
unexpected surfaces during execution that requires touching files not
listed in `## Files to Modify/Create` above, document it here rather
than writing a waiver against the scope-enforcement-gate.

Format: `- <YYYY-MM-DD>: <file path> — <one-line reason>`

If the in-flight change represents an architectural learning (not just
"I forgot to list this file"), ALSO write a discovery file at
`docs/discoveries/<YYYY-MM-DD>-<slug>.md` so the insight propagates
beyond this plan. Cross-reference here.

This section is checked by `scope-enforcement-gate.sh` alongside
`## Files to Modify/Create`. Updating this section (with a substantive
reason) is the structurally-correct response to an out-of-scope file
surfacing during execution; waivers are reserved for genuinely
cross-plan work.

If no in-flight changes have occurred, leave empty or state `n/a` —
empty is fine and common.
-->
(no in-flight changes yet)

## Assumptions
- `CLAUDE_SESSION_ID` is a stable, distinct-per-session environment value across a
  session's tool calls (existing harness convention, used by `end-user-advocate.md`,
  `tool-call-budget.sh`, agent-teams) — the self-claim refusal in `review-queue.sh
  claim` depends on it being genuinely different between the authoring session and
  the reviewing one, and genuinely stable within one session.
- `review-record-gate-lib.sh`'s `rrg_in_surface`/`rrg_is_covered` API is stable
  (verified byte-identical between this worktree and `wip/harness-hardening-
  2026-07-29` at build time) — the auto-enqueue library depends on it unchanged.
- Git commit author identity (name+email) is a reasonable, if not cryptographically
  unforgeable, proxy for "who authored this content" within this single-operator
  harness — the doctor's self-approval check uses it because it is the only durable
  signal available in committed history (session ids live only in the ephemeral,
  uncommitted `~/.claude/state/review-queue/`).
- `docs/reviews/records/*.json` stays append-only, one file per record (pre-existing
  convention this plan does not change) — the doctor check's "first commit that
  added this path" lookup depends on that.

## Edge Cases
- **RI1b's auto-enqueue was initially built standalone, not spliced into
  `review-record-commit-gate.sh`, because that file was entirely absent from this
  worktree's git history at build start** (`git merge-base --is-ancestor HEAD
  wip/harness-hardening-2026-07-29` — false in both directions at the time; this
  worktree's HEAD predated that branch's V6 landing by several commits). Splicing
  an edit into a file this worktree could not see would have meant authoring a
  diff against content this session never actually read — the Chesterton's-Fence
  violation the build protocol prohibits. **The branches were reconciled in this
  same session** (`git rebase` onto `wip/harness-hardening-2026-07-29`'s tip, after
  all four RI1-RI4 commits had already landed on the original base) and the
  splice IS NOW APPLIED — the exact 3 lines from `review-queue-auto-enqueue-lib.sh`'s
  header, inserted at the documented point. Mutation-proven, not merely present:
  `review-record-commit-gate.sh --self-test` Scenario 23 stages an uncovered file,
  commits, and asserts a `review-queue.sh` item was written; temporarily deleting
  the splice drives Scenario 23 (and only Scenario 23, of 62) to FAIL — full
  61-then-62-then-61-then-62 transcript in the Decisions Log D3.
  **A real bug surfaced and was fixed during this integration:** the splice's first
  version wrote real fixture-derived queue items into the operator's actual
  `~/.claude/state/review-queue/` on every self-test run (no `HARNESS_SELFTEST`
  sandbox), discovered by inspecting that directory after running the gate's
  suite twice. Fixed at the source (`review-queue.sh`'s own state-dir resolver now
  honors `HARNESS_SELFTEST=1` exactly like `hooks/lib/signal-ledger.sh` already
  does), and the 8 polluting fixture files were deleted after confirming by content
  (`account: t@example.com`, the fixture's own git identity) that none were real
  operator data.
- **A commit that is overridden via `REVIEW_RECORD_GATE_OVERRIDE` still needs
  independent review just as much as one that is blocked** — the auto-enqueue call
  site is documented to run BEFORE the override check, unconditionally, so
  "committing IS enqueueing" does not depend on which exit path the gate takes.
- **Staleness (the false-green class):** content can change between `claim` and
  `finalize` (a concurrent push, a later commit). Both `review-runner.sh claim` and
  `finalize` re-verify every covered file's blob_sha against the CURRENT branch tip
  and refuse (rc=3, `review-queue.sh mark-stale`) rather than reviewing content that
  already moved on — self-test scenario S8 in `review-runner.sh` reproduces this.
- **Re-review after REJECT/REFORMULATE:** `review-queue.sh enqueue`'s content-key
  dedup only suppresses duplicates while an item is OPEN (queued/claimed); a
  completed item (any verdict) allows a fresh enqueue for the same content —
  self-test scenario S10.
- **A record with no resolvable `change_ref.commit_sha`** (a hand-authored,
  grandfathered, or pre-RI3 record) never REDs the doctor check — "cannot verify"
  is not "violation" (self-test scenario `review-reviewer-independence-unresolvable`).

## Acceptance Scenarios
<!--
The end-user advocate authors this section in plan-time mode. Each
scenario is a `###`-level sub-section with a stable kebab-case slug,
numbered user-flow steps (what the USER does, not what the code does),
prose success criteria (what must be observably true after the flow),
and a short list of artifacts the runtime mode will capture.

Format per scenario:

  ### <slug> — <one-line description>

  **Slug:** `<slug>`

  **User flow:**
  1. <step 1 — imperative, user-perspective>
  2. <step 2>
  ...

  **Success criteria (prose):** <what must be observably true>.

  **Artifacts to capture:** <screenshot description, network log
  expectation, console log expectation>.

The runtime mode parses this section, executes each scenario via
browser automation, and writes a JSON artifact at
`.claude/state/acceptance/<plan-slug>/<session-id>-<timestamp>.json`
with sibling screenshot/network/console files. Soft cap 20 scenarios
per plan; hard cap 50.

Scenarios are SHARED with builders (motivation + what must work).
Runtime assertions are PRIVATE to the advocate (Goodhart prevention).
Builders see the user flow and success criteria; they do not see the
exact assertions the advocate runs. Build for the actual user, not for
the assertion text.

If `acceptance-exempt: true` is declared in the header, this section
may contain a single line explaining the exemption (e.g., "n/a —
harness-dev plan, no product user; see acceptance-exempt-reason
above").

See `~/.claude/doctrine/acceptance-scenarios.md` for the full protocol.
-->
n/a — `acceptance-exempt: true` (harness-internal governance mechanism; no product
user-facing surface, see `acceptance-exempt-reason` in the header). The maintainer is
the user; the demonstrated outcome is each script's `--self-test` PASS plus the
doctor's fixture RED/GREEN/WARN scenarios (see Closure Contract).

## Out-of-scope scenarios
<!--
The end-user advocate proposes scenarios from the plan's Goal / Scope.
Some proposed scenarios may not be reasonable to cover in this plan
(adjacent flows, future work, deliberate exclusions). Move them HERE
with a one-line rationale per entry, so the planner's accept/reject
decision is documented rather than silent.

Format per entry:

  - <one-line scenario description> — <rationale for exclusion>

This prevents "acceptance must pass" from becoming unbounded and
blocking every plan. Rejected scenarios become documented exclusions,
not silent omissions; future plans can pick them up explicitly.

If no scenarios were proposed and rejected, state that explicitly:
"None — all advocate-proposed scenarios are in scope above."
-->
None — `acceptance-exempt: true`, no scenarios were proposed (harness-internal, no
product user).

## Closure Contract
<!--
REQUIRED + substantive on `Status: ACTIVE` plans carrying
`lifecycle-schema: v2` (plan-reviewer.sh Check 15). Sub-decision 036-b:
the PASS-artifact contract is DEFINED AT CREATION, before any work
starts — "we know we're done when…" written before work begins, not
re-litigated at session end when context is thinnest. This is the
pre-agreed target that auto-closure (plan-auto-closure.sh, R4) reads.

Declare four things concretely:

  - **Commands that run** to verify completion (acceptance-scenario
    runtime commands for product plans; the `--self-test` invocations
    for harness plans).
  - **Expected outputs** — the PASS criteria (e.g. "exit 0",
    "13/13 PASS", "scenario `foo` verdict PASS").
  - **On-disk artifact location** — where the PASS artifact lands:
    `.claude/state/acceptance/<plan-slug>/...` for product plans;
    the structured `<plan-slug>-evidence/<task-id>.evidence.json` set
    for acceptance-exempt harness plans.
  - **Done when** — one sentence: "this plan is DONE when all tasks are
    task-verifier PASS AND the artifact at <location> exists with
    <verdict>."

For an `acceptance-exempt: true` plan the contract is the self-test PASS
(the exemption shifts the closure target to self-tests; it does not
remove the target). The substance bar is the same as Check 6b — ≥ 20
non-whitespace chars of non-placeholder content. See
~/.claude/doctrine/planning-full.md (Plan File Lifecycle) and Decision 036-b.
-->
- **Commands that run:** `bash adapters/claude-code/scripts/review-queue.sh
  --self-test`; `bash adapters/claude-code/hooks/lib/review-queue-auto-enqueue-lib.sh
  --self-test`; `bash adapters/claude-code/scripts/review-runner.sh --self-test`;
  `bash adapters/claude-code/scripts/write-review-record.sh --self-test`; `bash
  adapters/claude-code/hooks/harness-doctor.sh --self-test`; `bash
  adapters/claude-code/hooks/review-record-commit-gate.sh --self-test` — each run
  under BOTH `/bin/bash` and `/opt/homebrew/bin/bash` by absolute path.
- **Expected outputs:** review-queue.sh 13/13 PASS; review-queue-auto-enqueue-lib.sh
  7/7 PASS; review-runner.sh 8/8 PASS; write-review-record.sh 20/20 PASS;
  harness-doctor.sh's three new scenarios (`review-reviewer-independence-red`,
  `-green`, `-unresolvable-not-red`) PASS within its full suite;
  review-record-commit-gate.sh 62/62 PASS (61 pre-existing + new Scenario 23).
- **On-disk artifact location:** this plan file's own completion report (appended at
  close, per Definition of Done) plus the builder's structured evidence citing each
  suite's counts; acceptance-exempt so no `.claude/state/acceptance/` artifact applies.
- **Done when:** all four tasks are `task-verifier` PASS AND every command above
  exits 0 with the stated PASS counts on both interpreters.

## Testing Strategy
<!--
How each task will be verified — unit tests, integration tests, runtime
verification commands. Prefer concrete command lines ("run
`npm run test:links`") or file paths ("new Playwright test at
tests/e2e/foo.spec.ts") over vague statements ("test manually"). See
~/.claude/doctrine/vaporware-prevention.md.

AI-output features (any feature whose user-observable behavior is determined
by an LLM's generated text — chatbot replies, AI-drafted summaries, AI
suggestions shown to a user) MUST include LIVE-MODEL evidence, not just
mock-test evidence. Mock tests verify the pipeline plumbs values into the
right places; they cannot verify the AI's generated text obeys product
rules (no scarcity, no jumping from symptom to solution, calm tone,
single question per turn, etc).

For any AI-output task, the `Prove it works:` block MUST cite a live-model
run: project-specific scripts under `scripts/` (e.g.
`live-conversation-test.<ext>` in your project) that send scripted inputs
through the real LLM and evaluate the actual response against the rules.
Real API tokens — cheap insurance against the mock-tests-green-but-prod-
broken failure mode. See the project's own .claude/rules/ for the live-test
conventions specific to this codebase.
-->
- RI1: `review-queue.sh --self-test` (13 scenarios: create/idempotent-dedup/list/
  claim-success/self-claim-refused/already-claimed-refused/complete/complete-
  without-claim-refused/mark-stale/re-enqueue-after-completed/shared-state-dir/
  get-nonexistent) + `review-queue-auto-enqueue-lib.sh --self-test` (7 scenarios:
  uncovered-enqueues/fields-correct/idempotent/out-of-surface-noop/grandfathered-
  noop/nothing-staged-noop/missing-review-queue-sh-degrades).
- RI2: `review-runner.sh --self-test` (8 scenarios covering claim, self-claim
  delegation, prepare's banner+diff, not-claimed refusal, finalize's commit-under-
  own-identity + queue completion, record field verification, already-completed
  refusal, and the staleness-refusal path with a REAL second commit changing the
  content mid-review).
- RI3: `write-review-record.sh --self-test` (20 scenarios, 4 new: principal/
  independence carried into the record, carried into the index, omitted fields
  render null, invalid independence value rejected) + `harness-doctor.sh
  --self-test`'s 3 new fixture scenarios (RED self-approval via matching git
  authorship; GREEN genuine independent authorship; graceful non-RED when
  unresolvable).
- RI4: `evals/golden/rules-index-coverage.sh` (byte-cap check on the compact
  doctrine file) + manual re-read confirming the residual paragraph states the new
  mechanism honestly (still names what remains unsolved: quote-forgery,
  `REVIEW-RECORD-ANTI-FABRICATION-ANCHOR-01`).
- RI1b (post-rebase integration): `review-record-commit-gate.sh --self-test` — 61
  pre-existing scenarios (0 regressions from the splice) + new Scenario 23
  (stages an uncovered file, commits, asserts a `review-queue.sh` item was
  written), 62/62 total on both interpreters.
- Mutation-tested (not just green-by-default): each self-test's core assertions were
  verified RED against the pre-fix/broken shape before being made GREEN (e.g.
  write-review-record.sh's `${reviewer,,}` bug reproduced verbatim on `/bin/bash`
  before the `tr`-based fix; the doctor's self-approval RED fixture confirmed to
  trip before the GREEN fixture's differing-author commit was added; Scenario 23
  temporarily neutered via a one-line mutation and confirmed to fail — exactly
  Scenario 23, 61/62 — then restored to 62/62).

## Walking Skeleton
The thinnest end-to-end slice is: an uncovered file gets enqueued (RI1) → a
DIFFERENT session claims it, refusing if it were the same session (RI1/RI2) → that
session computes the diff itself and reads the fixed instructions template (RI2) →
it writes AND commits the PASS record under its own identity, closing the queue item
(RI2) → the doctor detects (and REDs) the degenerate case where that separation was
violated (RI3). This full loop is exercised end-to-end by
`review-runner.sh --self-test` scenarios S1, S3, S5, S6 in one connected fixture (one
git repo, one queue dir, enqueue → claim → prepare → finalize → verify the committed
record), before RI3's doctor check or RI4's doctrine text were added.

First task: RI1 (the queue must exist before RI2 has anything to claim).
<!--
Thinnest end-to-end slice that touches every architectural layer the
plan will ultimately affect (e.g., UI → API → worker → DB → back to UI).
Build this FIRST, before adding features. Prevents the integration-
vaporware pattern where pieces are built in isolation and the wires
between them never get connected.

Format: one paragraph naming the slice, followed by "First task:" with
the task number from your task list that implements it. The first task
MUST be the skeleton, not individual layers.

To opt out for legitimate cases (pure refactor, pure docs, no new
user-facing flow), replace this entire block with a single line:
    Walking Skeleton: n/a — <one-sentence justification>
-->

## Decisions Log

**D1 — Three deterministic points (operator-directed, binding, verbatim).** The
dispatch that created this plan itself embeds the operator's framing directly:
build the fix around three deterministic points — WHETHER a review happens (a
mechanical trigger, e.g. the commit-time gate, never a session's own choice), WHAT
the reviewer sees (a fixed template + the real diff the runner derives itself, never
enqueuer-supplied free text), and WHAT the verdict becomes (written AND committed by
the reviewing process itself, never handed back to the authoring session). All three
are load-bearing across RI1/RI1b (point 1), RI2/RI4's `config/review-
instructions.md` (point 2), and RI2's `finalize` (point 3). Not a Tier-2+ decision
(it is the operator's own scoping of the task, not a builder judgment call) — no
separate decision record.

**D2 — Independence is the pathway, not the machine (operator-directed, binding,
verbatim, mid-build pivot).** Partway through the build the operator challenged the
original cross-machine framing directly: *"I don't see how a different machine would
change anything. It's all the same claude, agents, harness, etc. We have several
adversarial review agents already. Why can't you utilize those to review what you're
building in the short term? Can't that be your principal?"* Full rationale, options
considered, and consequences: `docs/decisions/067-review-independence-same-session-
pathway.md` (Tier 1, reversible — landed before anything under the old framing had
shipped). Concretely: `independence: pathway` (a genuinely different session/process,
same or different machine) replaces `context-only` as the default/expected tier;
`independence: cross-machine` survives only as optional additional hardening; no
dedicated desktop-runner daemon is built; the doctor's WARN-on-context-only-for-
constitution-tier-paths check is dropped (nothing left to warn about); the single
surviving RED compares git-commit authorship (the "unforgeable half"), not ephemeral
session/account fields.

**D3 — RI1b built as a standalone library first, then spliced in once the branches
reconciled (builder decision, Tier 1, reversible).** At build start
`review-record-commit-gate.sh` was absent from this worktree's git history entirely
(confirmed: `git merge-base --is-ancestor HEAD wip/harness-hardening-2026-07-29` was
false in both directions — a worktree-provisioning mismatch, not a design choice).
Splicing an edit into a file this session could not read would have violated
Chesterton's Fence, so the mechanism was built standalone first. **Mid-build, the
coordinator directed a rebase onto `wip/harness-hardening-2026-07-29`'s current tip**
(after all four RI1-RI4 commits had already landed on the original base) — the
rebase succeeded with one expected add/add conflict (`state-json-init.sh`, resolved
by dropping this plan's now-redundant provenance comment and keeping the real file)
and one INDEX.md content conflict (resolved by re-running the documented generator).
Once `review-record-commit-gate.sh` existed in this worktree, the exact 3-line
splice from `review-queue-auto-enqueue-lib.sh`'s header was applied for real,
verified against the gate's own 61 pre-existing self-test scenarios (0 regressions)
plus a new Scenario 23 proving the integration, mutation-tested (deleting the
splice drives Scenario 23, and only Scenario 23, to FAIL). See Edge Cases for the
real state-pollution bug this integration surfaced and fixed.

**D4 — Fixed a pre-existing, unrelated bug in `write-review-record.sh` while editing
it (builder decision, Tier 1, reversible).** `${reviewer,,}` (bash 4+-only lowercase
expansion) broke this script's OWN `--self-test` on this repo's bash-3.2 floor,
because the self-test invokes itself via its shebang (`"$SELF_PATH"`, not
`bash "$SELF_PATH"`), which always resolves to `/bin/bash` (3.2.57) regardless of
which interpreter launched the outer `--self-test` — so the bug fired on every run on
this machine, not only under an explicit bash-3.2 invocation. In scope to fix per the
build protocol's "obvious defect in a file you're modifying" allowance, and required
in practice: RI3's new self-test scenarios could not run at all until this was fixed.
Replaced with a portable `tr '[:upper:]' '[:lower:]'` call. Verified 16/16 (pre-fix
baseline once `chmod +x` was also applied — see below) → 20/20 (post RI3 additions).

**D5 — `chmod +x` on three pre-existing/imported scripts (builder decision, Tier 1,
reversible, mechanical).** `write-review-record.sh` was tracked as mode `100644`
(non-executable) in this worktree, which — combined with its self-test's shebang
self-invocation convention — made every self-test run fail with "Permission denied"
before any of the actual logic ran. Fixed alongside D4 (same file, same session).
`review-queue.sh`/`review-runner.sh`/`review-queue-auto-enqueue-lib.sh` were created
executable from the start.

**D6 — Fixed a REAL state-pollution bug discovered while applying the RI1b splice
for real (builder decision, Tier 1, reversible; found via direct inspection, not
inferred).** The first application of the splice into the REAL
`review-record-commit-gate.sh` wrote actual fixture-derived queue items into the
operator's real `~/.claude/state/review-queue/` on every self-test run, because
`review-queue.sh`'s state-dir default had no sandbox awareness and the gate's own
self-test does not override `REVIEW_QUEUE_STATE_DIR`. Discovered by directly
inspecting that directory after running the gate's suite twice (`ls
~/.claude/state/review-queue/` showed 8 files with fixture-identifying content —
`account: t@example.com`, the self-test's own git identity). Fixed at the source:
`review-queue.sh`'s `_rq_state_dir_default` now honors `HARNESS_SELFTEST=1` exactly
like `hooks/lib/signal-ledger.sh`'s pre-existing `_signal_ledger_path` convention
(sandboxes under `$TMPDIR` when set and no explicit override is given) — the gate's
own self-test already exports `HARNESS_SELFTEST=1` globally, so no change was
needed in the gate itself. The 8 polluting files were deleted after confirming by
content they were fixture garbage, not real operator data. Re-verified: both
self-test runs post-fix leave `~/.claude/state/review-queue/` empty.

**D7 — `check_review_reviewer_independence` gets an Amendment-E-style cutover, added
after discovering it REDs 58 real, pre-existing records (builder decision, Tier 1,
reversible — a doctor-check gating change, no data mutation).** Running the check
against this repo's REAL `docs/reviews/records/` (not a fixture) after RI3 landed
showed 58 `RED review-reviewer-independence` lines — every record from the 2026-07-29
harness-change-review sweep the operator ran directly (mentioned by the coordinator
mid-build: "the review sweep RAN under the operator's direct authorization and wrote
~91+ records"; this checkout shows 58 `harness-change-review` records tripping the
self-approval predicate specifically, out of more records overall). Those records are
a deliberate, operator-authorized stopgap that predates `review-queue.sh`/
`review-runner.sh` existing at all — flagging them RED the instant this check ships
would read as "58 NEW problems just appeared" when nothing about them changed. This
is the SAME class of problem `grandfather-manifest.json`'s Amendment E already solved
for `review-before-deploy` ("never brick a fresh/stale machine" — enforcement applies
only to content that postdates a cutover). Applied the same principle here: a fixed
constant `_RRI_CUTOVER_COMMIT` (pinned to the commit that introduced this check,
overridable via `REVIEW_REVIEWER_INDEPENDENCE_CUTOVER` for self-test fixtures, which
obviously cannot contain a real production SHA in their own from-scratch history) —
a self-approved record whose OWN introducing commit is NOT a descendant of the
cutover WARNs (grandfathered) instead of REDing. Re-verified against the real repo
post-fix: 0 RED, 58 WARN (all naming the grandfather reason explicitly), confirmed by
a new dedicated self-test scenario (`review-reviewer-independence-pre-cutover-warn`,
alongside the pre-existing RED/GREEN/unresolvable scenarios, now 4 total, updated to
pass a fixture-local cutover override so the RED scenario still genuinely tests RED).
**Answers the coordinator's backfill question directly: the sweep's records stand
AS-IS** (grandfathered, not retroactively re-reviewed or backfilled into the queue
model — the queue has no retroactive role once a record already exists and covers
content, since coverage-checking (`rrg_is_covered`) reads `index.json` directly and
was never queue-aware) — **this plan's pipeline governs commits from the cutover
commit forward, not before it.**

Also refreshed the committed `docs/reviews/records/index.json` via
`write-review-record.sh rebuild-index` (a direct, mechanical consequence of RI3's own
schema extension — the committed index was built by the pre-RI3 writer and lacked the
two new fields entirely on every row, which is exactly the divergence
`review-index-consistency` exists to catch; confirmed RED before the rebuild, GREEN
after).

## Behavioral Contracts
<!-- rung: 5 requires this section per plan-reviewer.sh Check 11. -->
- **Idempotency:** `review-queue.sh enqueue` is idempotent for identical
  `{path,blob_sha}` content while an item is OPEN (queued/claimed) — a retried
  commit attempt over the same uncovered content never creates a duplicate item
  (content-key dedup, self-test S2). `claim`/`complete`/`mark-stale` are each
  single-transition operations guarded by the item's current `status` — calling any
  of them on an item not in the expected prior state is refused (rc 2), not silently
  re-applied.
- **Performance budget:** every operation is a handful of `git`/`jq` calls against a
  small (single-digit-to-low-hundreds-of-items) local directory — sub-second in
  practice, no network calls on the primary (non-coord-repo) path. The auto-enqueue
  splice runs BACKGROUNDED in production (`RQ_AUTO_ENQUEUE_MODE=background`,
  default) specifically so it can never add measurable latency to `git commit`; only
  `--self-test` forces `RQ_AUTO_ENQUEUE_MODE=sync` for determinism.
- **Retry semantics:** no automatic retries anywhere in this pipeline — every
  refusal (self-claim, wrong status, stale content) is a terminal rc for that
  invocation; the caller (a fresh session dispatch) re-attempts explicitly by
  re-running `claim`/`enqueue` with corrected inputs. Staleness is re-checked at BOTH
  `claim` and `finalize` (not just once) precisely because time passes between them
  and content can move.
- **Failure modes:** fail-open on infrastructure absence (missing `jq`/`git`,
  missing `review-queue.sh` from the auto-enqueue lib's perspective) — never blocks
  a commit, never crashes a caller; degrades to a logged no-op. Fail-CLOSED
  (mechanical refusal, rc 2/3, no override flag) on the three integrity violations
  this plan exists to prevent: self-claim, claim/finalize on the wrong status, and
  stale content. The doctor check fails toward WARN (cannot verify) rather than RED
  whenever the git history needed for the self-approval comparison is unresolvable.

## Definition of Done
- [ ] All tasks checked off
- [ ] All tests pass
- [ ] Linting/formatting clean
- [ ] SCRATCHPAD.md updated with final state
- [ ] Completion report appended to this plan file

