<!-- scaffold-created: 2026-07-17T12:57:41Z by start-plan.sh slug=orphaned-worktree-guard-reformulation -->
# Plan: Orphaned Worktree Guard Reformulation
Status: ACTIVE
Execution Mode: orchestrator
Mode: code
Backlog items absorbed: GUARD-REFORMULATE-01
acceptance-exempt: true
acceptance-exempt-reason: harness-development — the maintainer is the user; no product/UI surface. The self-test suite (worktree-hygiene-sweep.sh --self-test, harness-doctor.sh --self-test) is the demonstration.
tier: 2
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

rung: 2
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

frozen: false
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

owner: mishanovini
<!--
owner — who is accountable for this plan reaching a terminal state
(COMPLETED / ABANDONED / SUPERSEDED / DEFERRED). One accountable human.
Required (non-empty) on `Status: ACTIVE` plans that carry
`lifecycle-schema: v2`, per plan-reviewer.sh Check 14. Sub-decision
036-d. Pass via `start-plan.sh --owner <name>`.
-->

target-completion-date: 2026-07-17
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

ask-id: 
<!--
ask-id — the ask-registry entry (`~/.claude/state/ask-registry.jsonl`) this
plan serves. Plan headers record it, and plan creation back-links the
registry in the other direction (the registry entry's `plan_slugs[]` gains
this plan's slug) — see `adapters/claude-code/doctrine/planning.md`. Pass at
creation via `start-plan.sh --ask-id <id>`, which calls `ask-registry.sh
link-plan --ask-id <id> --plan-slug <slug>` for you; a plan with no
originating ask may state `ask-id: none — no linked ask`.

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
The orphaned-worktree-work guard (WIP `a4b6876`, harness-reviewed with verdict
REFORMULATE — see `docs/harness-improvements/orphaned-worktree-guard.md`)
detects git worktrees holding dirty/unintegrated content with no live owner,
so stranded builder work (crash, SIGKILL/OOM, reboot, standing-by) is
surfaced instead of silently rotting. The review found one headline defect:
the liveness join relied ONLY on session heartbeats, but a dispatched
`plan-phase-builder` subagent (isolation:worktree) writes NO heartbeat of its
own — so an ACTIVELY-RUNNING builder's dirty `agent-<id>` worktree would be
misclassified as stranded on every parallel-build day (a cry-wolf false
positive the review correctly blocked landing on). This plan reformulates the
liveness join to add a subagent-transcript-mtime signal — verified against
the REAL on-disk transcript layout, not assumed — as the PRIMARY liveness
signal for `agent-*`-named worktrees, leaving the existing heartbeat/claim
join unchanged as the only signal for non-agent (named) worktrees.

## User-facing Outcome
n/a — harness-internal: the user is the maintainer. The self-test suites
(`worktree-hygiene-sweep.sh --self-test` — 39/39 including 5 new
REFORMULATION assertions; `harness-doctor.sh --self-test` — the new
`oww-agent-live-green` scenario integration-tests the doctor → sweeper →
new-signal chain) are the demonstration, per `acceptance-exempt-reason` above.

## Scope
- IN: Rebase the salvaged WIP (`a4b6876`, cherry-picked cleanly onto current
  HEAD) and reformulate `worktree-hygiene-sweep.sh`'s `_live_owner` to add a
  bounded, cached subagent-transcript-mtime liveness signal for `agent-<id>`
  worktrees; extend the self-test suites; update `manifest.json`'s
  `stranded-worktree-work` evidence-bar text for the new two-signal design;
  regenerate `docs/harness-architecture.md` (manifest-derived, drifted both
  from this change's own text edit and from pre-existing unrelated entries);
  update the durable record at
  `docs/harness-improvements/orphaned-worktree-guard.md`.
- OUT: The durable P2 fix (a dispatch-time lease written by the builder-spawn
  path, replacing BOTH heuristic joins) — named in the WIP's own
  retirement_condition, not built here. Also OUT: wiring `agent-heartbeat.sh`
  (a separate, COOPERATIVE per-agent heartbeat shipped 2026-07-14 at `1d28e48`
  — requires the dispatching orchestrator's prompt to instruct the agent to
  call `emit`/`conclude`, and the agent to comply) as an alternative liveness
  signal — see Decisions Log: the transcript-mtime signal this plan ships is
  PASSIVE/structural (the harness writes the transcript automatically,
  independent of any dispatch-prompt convention or agent cooperation), which
  is why it was chosen over the cooperative heartbeat convention for this
  specific defect.

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

- [ ] 1. Rebase the salvaged WIP (`a4b6876`) onto current HEAD and reformulate
      `_live_owner` to add subagent-transcript-mtime liveness for `agent-<id>`
      worktrees (primary signal, checked before the heartbeat/claim join),
      bounded via a one-time-per-process cached `find` (`_build_agent_tx_cache`
      / `_agent_tx_fresh_min`); extend `worktree-hygiene-sweep.sh --self-test`
      with 5 new REFORMULATION assertions (fresh-agent-transcript exclusion,
      stale-agent-transcript flag with a distinguishing verdict, non-agent
      worktree unaffected); add a `harness-doctor.sh --self-test` integration
      fixture (`oww-agent-live-green`) proving the doctor → sweeper →
      new-signal chain; rewrite `manifest.json`'s `stranded-worktree-work`
      fp_expectation/golden_scenario/retirement_condition/honesty_rationale
      for the new design + residual; regenerate `docs/harness-architecture.md`
      via `gen-architecture-doc.sh` to clear both this change's own drift and
      pre-existing unrelated drift (agent-commit-gate/agent-design-gate/
      artifact-evidence-bar entries added by other work, never regenerated in);
      update `docs/harness-improvements/orphaned-worktree-guard.md`'s status.
      — Verification: mechanical (harness-internal detector/self-test work;
      the self-test suites ARE the demonstration per risk-tiered-verification
      doctrine — no product runtime surface to drive with a browser/curl).
      Docs impact: `docs/harness-improvements/orphaned-worktree-guard.md`
      status updated in the same commit; `docs/harness-architecture.md`
      regenerated in the same commit (manifest-derived, not hand-edited).

      Evidence for this task's mechanical verification (captured at build
      time, not yet re-verified by task-verifier — see Closure Contract):
      `worktree-hygiene-sweep.sh --self-test` → 39/39 (34 original WIP
      assertions + 5 new); `bash -n` clean on both modified hook/script
      files; `manifest-check.sh` → GREEN, 129 entries; `node -e
      "JSON.parse(...)"` → valid JSON on `manifest.json`;
      `gen-architecture-doc.sh --check` → confirmed no drift after
      regeneration (re-ran `harness-doctor.sh --quick` and observed the
      `wave-f-f2-docs` RED, present pre-fix, absent post-fix at the same
      point in the check sequence); `harness-doctor.sh --self-test`
      partial clean run reached 18/18 with 0 fails (not run to full
      completion in-session — see Known gap below) plus the targeted
      `oww-agent-live-green` scenario individually confirmed PASS.

- [ ] 2. ROUND 2 — fix the harness-reviewer re-pass's finding on task 1's own
      commit: locked agent worktrees never reached the liveness split (the
      pre-existing `*,locked,*` structural-skip in `classify_worktree`
      returned before `_live_owner` ever ran, for ANY locked worktree —
      proven on the review machine via three real dead-pid locked
      worktrees). A dispatched agent's worktree is `locked` by the
      isolation/dispatch mechanism for the FULL dispatch duration and only
      unlocks on clean completion, so a crashed/SIGKILLed/OOM-killed agent
      leaves it locked FOREVER — exactly the golden_scenario's own
      "crashes, is SIGKILLed/OOM-killed" claim, unreachable for this
      topology until this task. Fix: `classify_worktree` no longer lets
      `locked` preempt an `agent-*`-named worktree (falls through to the
      normal liveness split instead, with a new `is_locked` guard keeping
      it OUT of SAFE-PRUNE); `_live_owner` takes a third `is_locked` arg
      and reports the distinct verdict `agent-crashed-locked` for
      stale-and-locked; salvage/WARN text in both
      `worktree-hygiene-sweep.sh` and `harness-doctor.sh` now names the
      `git worktree unlock <path>` step (verified: a single `--force` on
      `git worktree remove` is NOT enough for a locked worktree — `-f -f`,
      force TWICE, or unlock first). Also bumped
      `_build_agent_tx_cache`'s `find -maxdepth 6` → `7` (measured: the
      Workflow-dispatch transcript variant sits at EXACTLY depth 6, zero
      slack) and reconciled `manifest.json`'s golden_scenario/
      fp_expectation and this durable doc's invariant text with what the
      code now actually reaches. — Verification: mechanical (same
      harness-internal class as task 1). Docs impact:
      `docs/harness-improvements/orphaned-worktree-guard.md` gets a
      "Round 2" section in the same commit.

      Evidence (captured at build time): `worktree-hygiene-sweep.sh
      --self-test` → 43/43 (task 1's 39 + 4 new: scenario (d) LOCKED +
      stale-transcript + content → `agent-crashed-locked` verdict + `git
      worktree unlock` salvage text present [3 assertions], scenario (e)
      LOCKED + FRESH transcript → stays LIVE-OWNED, unaffected by lock [1
      assertion]); `bash -n` clean; `manifest-check.sh` → GREEN, 129
      entries; `node -e "JSON.parse(...)"` → valid JSON (caught and fixed
      one literal-newline JSON syntax error introduced while editing the
      manifest text — parse re-verified clean after the fix);
      `git worktree lock`/`remove` behavior independently verified against
      real git (confirms the exact force-twice requirement cited in the
      salvage text, not assumed); `harness-doctor.sh --self-test` re-run
      in progress at commit time (see this task's own commit message for
      the final tally if it completed, or the Known gap note if it did
      not — same machine-slowness caveat as task 1).

## Files to Modify/Create
<!--
Every file this plan touches, grouped into Create vs Modify when useful.
Include a one-line reason per file so a reader can see the shape of the
change without opening each one.
-->
- `adapters/claude-code/scripts/worktree-hygiene-sweep.sh` — core reformulation:
  `_agent_tx_root`/`_build_agent_tx_cache`/`_agent_tx_fresh_min` helpers,
  `_live_owner` primary-signal branch + final-verdict fallback for
  `agent-<id>` worktrees, `_emit_stranded` verdict-label formatting, and 5 new
  `--self-test` REFORMULATION scenarios (plus the cherry-picked WIP base:
  `--stranded[--porcelain]` mode, `_live_owner`, already-merged exclusion).
- `adapters/claude-code/hooks/harness-doctor.sh` — cherry-picked WIP's
  `check_orphaned_worktree_work` (WARN-only) + its 3 self-test fixtures,
  trivially reconciled with a same-commit unrelated addition
  (`_copy_review_gate_tooling`) at the same insertion point; plus this
  reformulation's new `oww-agent-live-green` self-test fixture and a
  `heartbeat=` → `liveness=` WARN-message wording fix (no test depended on
  the old string; verified via grep).
- `adapters/claude-code/hooks/session-start-digest.sh` — cherry-picked WIP's
  `feed_stranded_work` (delegates entirely to the sweeper; unmodified by this
  reformulation beyond the cherry-pick).
- `adapters/claude-code/manifest.json` — cherry-picked WIP's
  `stranded-worktree-work` entry, then this reformulation's rewrite of its
  golden_scenario/fp_expectation/retirement_condition/honesty_rationale for
  the two-signal design + named residual.
- `docs/harness-architecture.md` — regenerated (manifest-derived generated
  file; never hand-edited) to clear drift from both this change's manifest
  text edit and pre-existing unrelated drift.
- `docs/harness-improvements/orphaned-worktree-guard.md` — durable record
  updated from REFORMULATE (blocking) to REFORMULATED pending
  harness-reviewer re-pass, with the verified real transcript-path layout
  correcting an earlier guess.
- `docs/backlog.md` — `GUARD-REFORMULATE-01` removed (absorbed by this plan);
  see Decisions Log for why the agent-heartbeat.sh path it mentioned was not
  taken instead.

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
- The dispatched agent worktree's OWN directory basename ("agent-<hex>") is
  always identical to that agent's transcript filename stem
  (`<session>/subagents/agent-<hex>.jsonl`), because the harness derives both
  from the same per-dispatch id at spawn time. Verified empirically for THIS
  session's own agent (`agent-a67cc3af91e88e7fc`); not verified across every
  historical dispatch-path version.
- `AGENT_TX_FRESH_MIN` defaulting to `OBS_STALE_MIN` (30 min) is a reasonable
  parity choice (same "how long is silence still normal" answer the
  session-level heartbeat join already uses) rather than a bespoke measured
  value — a judgment call, not a derived optimum (see Decisions Log).
- `find "$(_agent_tx_root)" -maxdepth 6 ...` is deep enough for the real
  layout (verified at depth 4, `projects/<slug>/<session>/subagents/<file>`)
  with slack for minor future nesting changes, without being unbounded.
- Regenerating `docs/harness-architecture.md` is safe and in-scope: it is a
  pure function of `manifest.json` (never hand-edited per its own header),
  so resyncing it whenever `manifest.json` changes is expected maintenance,
  not scope creep.

## Edge Cases
- Agent worktree with a FRESH transcript → LIVE-OWNED, not stranded
  (self-test scenario (a)).
- Agent worktree with a STALE transcript (past `AGENT_TX_FRESH_MIN`) →
  ORPHANED, with a distinguishing `agent-transcript-stale` verdict rather
  than the generic `no heartbeat/claim` (self-test scenario (b)).
- Non-agent (named) worktree, even with an UNRELATED `agent-*.jsonl`
  transcript present elsewhere in the cache → unaffected, still classified
  purely via the heartbeat/claim join (self-test scenario (c), 2 assertions).
- Agent worktree with NO transcript found at all → falls through to the
  heartbeat/claim join (which will also find nothing for a real dispatched
  subagent) → generic `no heartbeat/claim`, never a crash.
- SELF exclusion (pre-existing) is still checked in `classify_worktree`
  BEFORE `_live_owner` (and therefore before the new agent-transcript path)
  is ever reached.
- RESIDUAL, not eliminated (named explicitly in manifest.json's
  fp_expectation): an agent silent for longer than `AGENT_TX_FRESH_MIN`
  while GENUINELY still working (one very long reasoning/tool call with no
  intermediate transcript flush) could still false-fire past the window.
  Accepted for a WARN-only, never-auto-pruning surfacer.

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
n/a — harness-development plan, no product user; see acceptance-exempt-reason
in the header.

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
None — acceptance-exempt (harness-development, no product user); no
scenarios were proposed.

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
- **Commands that run:** `bash adapters/claude-code/scripts/worktree-hygiene-sweep.sh --self-test`;
  `bash adapters/claude-code/hooks/harness-doctor.sh --self-test`;
  `bash adapters/claude-code/scripts/manifest-check.sh`;
  `bash adapters/claude-code/scripts/gen-architecture-doc.sh --check`.
- **Expected outputs:** sweep self-test `N passed, 0 failed` (N ≥ 39);
  doctor self-test full run with 0 FAIL; manifest-check `GREEN`;
  gen-architecture-doc `--check` exit 0 (no drift).
- **On-disk artifact location:** no `.claude/state/acceptance/` artifact
  (acceptance-exempt); the self-test stdout captured in this session's
  transcript and in the commit message is the evidence record for a
  harness-development plan.
- **Done when:** the four commands above all pass AND a harness-reviewer
  re-pass (per `docs/harness-improvements/orphaned-worktree-guard.md`)
  clears the FP finding — this plan is NOT auto-closed by
  `plan-auto-closure.sh`'s mechanical criteria alone; Status flips to
  COMPLETED only after that re-pass, tracked via the same durable doc.

## Testing Strategy
Self-test-driven (harness-internal, no product runtime surface):
`worktree-hygiene-sweep.sh --self-test` is the authoritative test for the
changed liveness-join logic — extended with 5 new REFORMULATION scenarios
covering the exact fresh/stale/unaffected-non-agent cases named in Edge
Cases above (all passed cleanly, 39/39, in an uncontaminated run).
`harness-doctor.sh --self-test` integration-tests the doctor →
`worktree-hygiene-sweep.sh --stranded --porcelain` delegation chain end to
end via a new `oww-agent-live-green` fixture (a dirty `agent-<id>` worktree
with ZERO heartbeat coverage — the real dispatched-subagent shape — plus a
fresh transcript; confirmed no WARN, i.e. correctly LIVE-OWNED). Baseline-diff
via two full `harness-doctor.sh --quick` runs (pre/post) confirmed the ONE
new RED this change's manifest.json text edit surfaced
(`wave-f-f2-docs`, drifted generated doc) was fixed by regenerating the doc
and is absent from a subsequent full run; the remaining 7 RED categories
present in both runs (`budget-chains`, `budget-worktrees-branches`,
`manifest-freshness`, `new-gate-evidence-bar`, `obs-ask-capture-completeness`,
`obs-scheduled-tasks`, `template-live-drift`) are pre-existing/environmental
(live `~/.claude` install lag, legacy manifest entries missing
`added_after`, this machine's scheduled-task/ask-capture state), unrelated to
this change, and `stranded-worktree-work` itself is not flagged by any of
them.

## Walking Skeleton
Walking Skeleton: n/a — pure reformulation of an existing detector's
internal liveness-join logic (no new user-facing flow, no new architectural
layer); the "skeleton" here is the pre-existing WIP's already-integrated
`--stranded`/digest/doctor chain, which this plan extends in place.

## Decisions Log
- 2026-07-17 — **Transcript-mtime vs agent-heartbeat.sh for agent-worktree
  liveness** (reversible, Tier-1: a config/logic swap in one function,
  revertible by a single commit revert). `docs/backlog.md`'s
  `GUARD-REFORMULATE-01` entry (absorbed by this plan) suggested keying
  `_live_owner` on `agent-heartbeat.sh`'s per-agent heartbeat
  (`heartbeats/agents/<id>.json`, shipped 2026-07-14 `1d28e48`) instead.
  Investigated and NOT taken: `agent-heartbeat.sh`'s own header states it is
  an "INTERIM PATTERN" that "relies on the dispatched agent calling
  `emit`/`conclude`" per a dispatch-prompt convention — i.e. it requires the
  DISPATCHING orchestrator's prompt to include that instruction AND the
  agent to comply; neither is guaranteed (this task's own dispatch prompt,
  for instance, did not). The subagent-transcript-mtime signal this plan
  ships is PASSIVE: the harness writes the transcript file automatically
  for every dispatched agent regardless of any prompt convention, so it
  covers 100% of dispatched agents, not only ones whose orchestrator
  remembered the emit/conclude convention. Decided and proceeded without
  pausing — reversible, and the task's own prompt had already specified the
  transcript-mtime approach with a verified real-layout investigation.
- 2026-07-17 — **AGENT_TX_FRESH_MIN default = OBS_STALE_MIN (30 min)**
  (reversible, Tier-1: an env-overridable constant). Chosen for parity with
  the existing session-level heartbeat-staleness window rather than a
  bespoke measured value, so the harness has one consistent "how long is
  silence still normal" answer across both liveness paths. No data exists
  yet on real agent silent-but-working durations to derive a measured
  optimum; independently overridable via `AGENT_TX_FRESH_MIN` if this proves
  wrong in practice.
- 2026-07-17 — **Route LOCKED agent worktrees through the liveness split
  instead of exempting them from SAFE-PRUNE only** (reversible, Tier-1: a
  control-flow change in one function, revertible by commit revert).
  Harness-reviewer round-2 finding: the pre-existing `*,locked,*`
  structural-skip in `classify_worktree` returned before `_live_owner` ever
  ran for ANY locked worktree, making the crash/SIGKILL/OOM class this
  entry's own golden_scenario claims to catch unreachable for a locked
  agent worktree specifically (proven: 3 real dead-pid locked worktrees on
  the review machine, none reaching the liveness logic). Considered and
  rejected: leaving the structural-skip in place and instead relying SOLELY
  on the digest/doctor's own dirty-worktree-count budgets to surface a
  stuck locked worktree indirectly — rejected because that gives no
  liveness verdict, no salvage command, and no distinction from a
  legitimately-locked non-agent worktree (e.g. on removable media); it
  would have been a weaker, more heuristic signal than reusing the
  transcript-mtime join already built for exactly this purpose. Took the
  reviewer's proposed fix directly (route agent-locked worktrees through
  the existing split, add the `is_locked` parameter, add the
  `agent-crashed-locked` verdict) since it reuses the already-verified
  signal rather than inventing a new one.

## Definition of Done
- [ ] All tasks checked off (task-verifier, or a documented equivalent
      for this harness-development plan — see Closure Contract)
- [ ] All self-tests pass (`worktree-hygiene-sweep.sh --self-test`,
      `harness-doctor.sh --self-test`)
- [ ] `manifest-check.sh` GREEN
- [ ] `gen-architecture-doc.sh --check` clean (no drift)
- [ ] Harness-reviewer re-pass clears the FP finding (per
      `docs/harness-improvements/orphaned-worktree-guard.md`)
- [ ] Completion report appended to this plan file
