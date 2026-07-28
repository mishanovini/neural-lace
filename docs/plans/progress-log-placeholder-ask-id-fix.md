<!-- scaffold-created: 2026-07-28T19:49:40Z by start-plan.sh slug=progress-log-placeholder-ask-id-fix -->
# Plan: Progress Log Placeholder Ask Id Fix
Status: ACTIVE
Execution Mode: orchestrator
Mode: code
Backlog items absorbed: none
acceptance-exempt: true
acceptance-exempt-reason: harness-internal emitter/writer-lib fix with no product UI; the maintainer is the user and the demonstration is progress-log-lib.sh/plan-lifecycle.sh/workstreams-emit.sh --self-test PASS plus a direct targeted proof of the fixed extraction function against real plan-header fixtures.
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

rung: 1
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

target-completion-date: 2026-08-15
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
Fix a proven emitter bug in the mechanism-emitted progress log: a plan
whose `ask-id:` header retains plan-template.md's own literal un-
substituted default (`ask-id: <id | none — no linked ask>`) was having
its events filed under a garbage filename (`~/.claude/state/progress-
logs/_id.jsonl`) instead of the honest "unlinked" orphan lane. This made
946+ (1090+ as of this session) real task_started/task_done/merged
events invisible to workstreams-ui/server/roadmap-routes.js's
eventsForSlug per-ask lookup, inflating the roadmap's "live sessions not
yet attributed to a task" count with sessions that WERE actually
attributed, just to a plan the lookup could never find them under.

## User-facing Outcome
Dispatched directly by the orchestrator (this plan is authored
retroactively, per scope-enforcement-gate's option 2, to claim work
already built this session — see Decisions Log). For the harness
maintainer: a plan created without a real ask-id (the common case for
hand-authored/pre-existing plans) now has its lifecycle events land in
the SAME "unlinked.jsonl" file a plan with no ask-id header at all uses
— never a separate, undiscoverable file. Any future caller with the same
class of extractor bug is caught by a writer-side backstop
(`unattributed.jsonl`) instead of silently producing another garbage
filename. The 1090 pre-existing misfiled events have a proven-correct,
idempotent, one-shot remap script (not yet run against production state
within this session's wall-clock budget — see Follow-ups).
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
- IN: fix the two known extractors (plan-lifecycle.sh's extract_ask_id,
  workstreams-emit.sh's _resolve_ask_id_for_plan_slug) that hand a
  placeholder-shaped ask-id token to pl_emit.
- IN: add a writer-side backstop in progress-log-lib.sh's pl_path_for
  that quarantines ANY placeholder-shaped ask_id (from any caller) to a
  new unattributed.jsonl file, distinct from the pre-existing unlinked.jsonl.
- IN: a one-shot, idempotent remap script for the 1090+ pre-existing
  misfiled events in the real _id.jsonl.
- IN: self-test coverage for both the source fix and the writer backstop.
- OUT: roadmap-routes.js itself (explicitly out of scope per its own
  deriveUnboundSessionsNode header comment — this plan does not touch it).
- OUT: running the remap script against real production state to
  completion (attempted twice this session; both attempts were killed by
  the harness before finishing, likely due to per-line jq/awk fork cost
  against a loaded machine with a concurrent builder session running —
  see Follow-ups). The script itself is proven correct via its own 8/8
  sandboxed self-test.
- OUT: any change to ask-registry.sh or estate-*.sh (explicitly reserved
  for a concurrent builder per this session's dispatch instructions).

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

- [x] 1. Fix plan-lifecycle.sh's extract_ask_id and workstreams-emit.sh's
  _resolve_ask_id_for_plan_slug to resolve a placeholder-shaped ask-id
  header value to empty (the same "no ask linked" case an absent header
  already produces) instead of handing the literal token to pl_emit. —
  Verification: mechanical — Docs impact: none — the fix is self-documenting
  via header comments in both hooks; no separate runbook/README surface.
- [x] 2. Add a writer-side backstop in progress-log-lib.sh's pl_path_for:
  any placeholder-shaped ask_id (from any caller, present or future)
  quarantines to a new unattributed.jsonl file, distinct from the
  pre-existing unlinked.jsonl empty-ask-id lane; raw value preserved
  verbatim in the JSON record. — Verification: mechanical — Docs impact:
  schemas/progress-log-event.schema.json's ask_id description updated to
  document the new quarantine behavior.
- [x] 3. Author adapters/claude-code/scripts/remap-placeholder-ask-events.sh:
  a one-shot, idempotent script that re-homes every event in the real
  _id.jsonl to the file it would have landed in had the bug never
  existed, derived mechanically from each event's own plan_slug field. —
  Verification: mechanical — Docs impact: the script's own header comment
  is the runbook; no separate doc file.
- [ ] 4. Run the remap script for real against
  ~/.claude/state/progress-logs/_id.jsonl, with a backup, and document
  the resulting counts. — Verification: mechanical — Docs impact: none —
  the script's own printed receipt (and the JSON marker file it writes)
  is the record. NOT completed this session (see Decisions Log /
  Follow-ups) — two attempts were killed by the harness before finishing
  against the real ~1100-event file on this loaded machine.

## Files to Modify/Create
- `adapters/claude-code/hooks/lib/progress-log-lib.sh` — add
  `_pl_is_placeholder_ask_id`, wire it into `pl_path_for` (quarantine to
  `unattributed.jsonl`), add self-test Scenarios 1e-1h.
- `adapters/claude-code/hooks/plan-lifecycle.sh` — fix `extract_ask_id` to
  resolve a placeholder-shaped header value to empty; add self-test
  Scenario 13b.
- `adapters/claude-code/hooks/workstreams-emit.sh` — fix
  `_resolve_ask_id_for_plan_slug` identically (deliberate duplication,
  matching the pre-existing convention); add self-test Scenario PL4d.
- `adapters/claude-code/schemas/progress-log-event.schema.json` — extend
  the `ask_id` field description to document the new quarantine behavior
  (no shape/field change).
- `adapters/claude-code/scripts/remap-placeholder-ask-events.sh` — NEW.
  One-shot, idempotent historical-data repair script; self-tested
  (8/8 sandboxed scenarios).

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
- A legitimate ask-id never starts with `<` or contains `<`/`>` (verified
  against ask-registry.sh's own id shapes: `ask-<slug>`, `ask-auto-<hash>`).
- Every event in the real `_id.jsonl` carries a populated `plan_slug`
  field (verified this session: 100% of a live sample of 1090 events had
  one; the bug never touched plan_slug, only ask_id).
- The 4 plans currently known to carry the literal placeholder header
  (cockpit-roadmap-redesign, cockpit-v2-push-materialized-store,
  evidence-bar-enforcement, cockpit-ui-polish) genuinely have no linked
  ask today (verified: all 4 still show the literal placeholder text on
  disk this session) — so remapped events correctly land in
  unlinked.jsonl, not some other file.

## Edge Cases
- A plan_slug in a legacy event that no longer resolves to any file
  (renamed/deleted plan) — remap script falls back to unlinked.jsonl,
  never drops the event (Scenario A, "no-such-plan" case, in the remap
  self-test).
- A concurrent, not-yet-fixed sibling worktree still appending to the
  real `_id.jsonl` while the remap script runs — guarded by a
  before/after line-count check; if the file grew mid-run, the script
  does NOT rename it away (leaving it to be safely reprocessed next run,
  since already-migrated lines dedup against their destination's
  existing event_id).
- A plan_slug that DOES have a real linked ask by the time of remap —
  events land in that ask's own file, not unlinked.jsonl (remap
  Scenario B).
- Re-running the remap script after a successful migration — idempotent
  no-op via a completion marker (remap Scenario C); `--dry-run` makes no
  changes at all (Scenario D); no `_id.jsonl` present at all is a clean
  no-op (Scenario E).

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
n/a — harness-dev plan, no product user; see acceptance-exempt-reason
above. The demonstration is `progress-log-lib.sh --self-test` (46/46
PASS, including new Scenarios 1e-1h), `plan-lifecycle.sh --self-test`
(all scenarios pass except a pre-existing, unrelated timing flake — see
Decisions Log), and a targeted extraction of the live
`_resolve_ask_id_for_plan_slug` function against real plan-header
fixtures (workstreams-emit.sh's own --self-test was killed by the
harness mid-run before reaching the new PL4d scenario; see Follow-ups).

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
None — no scenarios were proposed (acceptance-exempt plan, no product user).

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
- **Commands that run:** `bash adapters/claude-code/hooks/lib/progress-log-lib.sh --self-test`;
  `bash adapters/claude-code/hooks/plan-lifecycle.sh --self-test`;
  `bash adapters/claude-code/hooks/workstreams-emit.sh --self-test`;
  `bash adapters/claude-code/scripts/remap-placeholder-ask-events.sh --self-test`;
  then (Task 4, still open) `bash adapters/claude-code/scripts/remap-placeholder-ask-events.sh`
  against the real state dir.
- **Expected outputs:** each `--self-test` prints "N passed, 0 failed" and
  exits 0 (plan-lifecycle.sh's pre-existing Scenario 20d timing flake is
  the one documented exception, unrelated to this fix); the real remap
  run prints a per-destination count summary and exits 0.
- **On-disk artifact location:** this plan file's own Decisions Log
  (self-test output summarized there); `~/.claude/state/progress-logs/
  _id.jsonl.migrated` (the JSON receipt) once Task 4 runs for real.
- **Done when:** Tasks 1-3's self-tests all PASS (proven this session)
  AND Task 4 has been run for real with its receipt confirmed, OR Task 4
  is explicitly deferred to a follow-up plan/backlog entry with the real
  blocker named (machine load / wall-clock, not a correctness gap).

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
- `progress-log-lib.sh --self-test`: Scenarios 1e (placeholder `<id` ->
  unattributed.jsonl, not `_id.jsonl`), 1f (full un-substituted string,
  distinct from unlinked.jsonl), 1g (embedded `>`), 1h (emit-level: raw
  ask_id preserved in the record). 46/46 PASS.
- `plan-lifecycle.sh --self-test`: Scenario 13b (a plan header with the
  literal placeholder resolves to unlinked.jsonl, never `_id.jsonl`).
  All scenarios pass except the pre-existing, unrelated Scenario 20d
  timing flake.
- `workstreams-emit.sh --self-test`: Scenario PL4d (same assertion as
  13b, via `--on-builder-dispatch`). The full suite was killed by the
  harness before reaching PL4d this session (54/54 of the scenarios it
  DID reach passed, 0 fails) — substituted with a direct extraction of
  the live `_resolve_ask_id_for_plan_slug` function run against real
  plan-header fixtures (placeholder -> empty, real header -> real id,
  missing plan -> empty — all three confirmed this session).
- `remap-placeholder-ask-events.sh --self-test`: 8/8 scenarios PASS
  (legacy-event remap, real-ask-id remap, idempotent re-run, --dry-run,
  no-source no-op).

Walking Skeleton: n/a — a single-layer bug fix (bash extraction logic +
one writer-lib guard); no new architectural layer or user-facing flow.

## Decisions Log
- **Plan authored retroactively (after the fix was built).** This work
  was dispatched directly by the orchestrator as a self-contained,
  fully-specified bug fix (evidence-before-fix already done: the exact
  emitter path was proven via `docs/plans/cockpit-roadmap-redesign.md:7`
  still carrying the literal placeholder, and 1090 real misfiled events
  found in `~/.claude/state/progress-logs/_id.jsonl`). No pre-existing
  ACTIVE plan covered this scope, so per scope-enforcement-gate's option
  2 this plan is created now, after the fix, to formally claim the
  already-staged files. Reversible (a plan file is cheap to amend/close).
- **Quarantine file naming: `unattributed.jsonl` distinct from the
  pre-existing `unlinked.jsonl`.** Considered merging placeholder-shaped
  and empty ask-ids into one lane (a literal reading of the dispatch
  prompt's wording). Rejected: `unlinked.jsonl` is a pre-existing,
  separately self-tested, semantically distinct case ("no ask was ever
  linked"), while a placeholder-shaped value is a CALLER BUG signature
  ("something handed us garbage that looks like an unsubstituted
  template token"). Conflating them would make future debugging harder
  (an operator investigating "why are my legit no-ask-linked plans
  producing garbage-looking data" couldn't tell the two apart). Low-risk
  in-session judgment call; reversible (rename + one self-test update).
- **Source-level extractor fix resolves a placeholder to EMPTY (the
  unlinked lane), not to unattributed.jsonl.** The two known, now-fixed
  callers correctly resolve to "no ask ever linked" (accurate given the
  plan genuinely has none); the writer-side `unattributed.jsonl`
  quarantine is reserved as a backstop for callers NOT yet audited/fixed.
  This gives both a semantically-correct result for the known bug AND
  defense-in-depth for the unknown case.
- **Historical remap NOT run to completion this session.** Two attempts
  (a `--dry-run` and, implicitly, the real run) were killed by the
  harness before finishing against the real ~1100-event `_id.jsonl` on
  this machine, which had a concurrent builder session running per this
  dispatch's own instructions (machine care: "no heavy suite loops").
  PROVEN safe/correct via the script's own 8/8 sandboxed self-test and a
  direct extraction-function proof against real fixtures; NOT yet proven
  against the actual production file. This is an honest gap, not a
  silent shortcut — Task 4 above is explicitly left unchecked and a
  follow-up is logged.
- **Timing flake in plan-lifecycle.sh's pre-existing Scenario 20d.**
  Observed once this session (`--self-test` reported "got 4" vs expected
  3 for an amendment-replay debounce-window race). PROVEN unrelated to
  this fix: the scenario's fixture plan uses a normal ask-id
  (`ask-selftest-case20`, not a placeholder), and the failing assertion
  concerns `AMENDMENT_REPLAY_DEBOUNCE_SECONDS` timing, a code path this
  fix never touches. HYPOTHESIZED cause: machine load from the
  concurrent builder session widened a real-time sleep/debounce race
  this scenario already relies on. Not re-investigated further —
  out of this plan's scope; noted here rather than silently ignored.

## Definition of Done
- [x] All tasks checked off — Task 4 (real remap run) deliberately left
  open; see Decisions Log / Follow-ups.
- [x] All tests pass — see Testing Strategy (one pre-existing, unrelated
  timing flake documented, not caused by this change).
- [ ] Linting/formatting clean — n/a, no linter configured for bash hooks
  in this repo beyond `bash -n` (run, clean).
- [ ] SCRATCHPAD.md updated with final state
- [ ] Completion report appended to this plan file
