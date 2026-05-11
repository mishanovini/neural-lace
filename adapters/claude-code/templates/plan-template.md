# Plan: [Task Title]
Status: ACTIVE
Execution Mode: orchestrator
Mode: code
Backlog items absorbed: [none | slug-1, slug-2]
acceptance-exempt: false
acceptance-exempt-reason:
tier: <1-5>
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
See `~/.claude/rules/planning.md` and Decision 017.
-->

rung: <0-5>
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

architecture: <coding-harness | dark-factory | auto-research | orchestration | hybrid>
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
See `~/.claude/rules/spec-freeze.md` for the freeze-thaw protocol.
-->

prd-ref: <slug | n/a — harness-development>
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
See `~/.claude/rules/prd-validity.md` and `adapters/claude-code/templates/prd-template.md`.
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

See `~/.claude/rules/acceptance-scenarios.md` for the full plan-time →
runtime → gap-analysis loop and explicit when-to-use guidance for the
exemption.

Execution Mode values:
  orchestrator  Default for multi-task plans. The main session reads this plan,
                dispatches each task to a `plan-phase-builder` sub-agent via the
                Task tool, and collects results. The main session does NOT do the
                build work itself — it stays lean as an orchestrator. See
                ~/.claude/rules/orchestrator-pattern.md for the full protocol.
  direct        Single-task quick fixes (one file, < 15 min). The main session
                does the work directly. No sub-agent dispatch overhead.
  agent-team    Uses Anthropic's experimental Agent Teams feature
                (CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1) for peer-to-peer
                teammate coordination with a shared task list. Gated by
                `enabled: true` in ~/.claude/local/agent-teams.config.json
                (default false). See ~/.claude/rules/agent-teams.md for the
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

See ~/.claude/rules/planning.md, "Backlog absorption at plan creation".

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

See ~/.claude/rules/design-mode-planning.md for the full protocol on
design-mode tasks.
-->

<!--
Required sections (enforced by plan-reviewer.sh):
  Goal, Scope, Tasks, Files to Modify/Create, Assumptions, Edge Cases,
  Testing Strategy

Every required section must contain substantive, plan-specific content —
not placeholder text. See ~/.claude/rules/planning.md, "Verbose Plans Are
Mandatory", for the full rule. Verbose planning is mandatory regardless
of plan size.
-->

## Goal
[What we're building/changing and why. One or two paragraphs. State the
user-observable outcome this plan produces, not just the mechanism.]

## User-facing Outcome
<!--
REQUIRED. Operationalizes FUNCTIONALITY OVER COMPONENTS — the harness's
most important rule (~/.claude/rules/planning.md).

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
- IN: [what's included — be explicit about every file, feature, or change
  this plan covers]
- OUT: [what's explicitly excluded — anything adjacent that a reader
  might expect but is NOT in this plan]

## Tasks

<!--
Mark tasks that CAN run in parallel with siblings using `[parallel]` or
group them under a batch header. Default is serial. Examples:

  [parallel] tasks that touch disjoint files and have no data dependency
  [serial]   tasks that share a file, depend on a previous task's commit,
             or compete for the same migration number / port / resource

The orchestrator reads these markers to decide dispatch batching. When in
doubt, leave unmarked (serial). See ~/.claude/rules/orchestrator-pattern.md
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
~/.claude/rules/risk-tiered-verification.md for the full protocol and
when to use each level.

Format examples:

  - [ ] 1. Author the new hook file at hooks/foo.sh — Verification: mechanical
  - [ ] 2. Migrate the doctrine docs to canonical glossary — Verification: contract
  - [ ] 3. Implement the runtime feature end-to-end — Verification: full
  - [ ] 4. Legacy task without declaration   (defaults to full)

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

See ~/.claude/rules/planning.md "Integration Verification — Every
Full-Level Task Must Prove It Works" for the full rule and the
~/.claude/hooks/wire-check-gate.sh self-test for worked PASS/FAIL
fixtures.
-->

- [ ] 1. [First task — specific enough to verify completion]
- [ ] 2. [Second task]

## Files to Modify/Create
<!--
Every file this plan touches, grouped into Create vs Modify when useful.
Include a one-line reason per file so a reader can see the shape of the
change without opening each one.
-->
- `path/to/file` — [what changes and why]

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
<!--
Every premise this plan relies on — explicit, not implied. If you can't
think of any, write assumptions about the existing code or environment
("assumes the /api/foo route returns JSON in the shape it currently
returns") rather than omitting the section. Required even for trivial
plans — forcing assumptions to be explicit prevents silent
build-time failures.
-->
- [First explicit premise this plan depends on]

## Edge Cases
<!--
Corner cases, failure modes, and unusual inputs this plan must handle.
Examples: empty inputs, concurrent edits, stale caches, missing
permissions, partial rollouts, first-time user vs. returning user.
If no edge cases apply, state that explicitly with a one-line
justification.
-->
- [First edge case and how this plan handles it]

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

See `~/.claude/rules/acceptance-scenarios.md` for the full protocol.
-->
- [populate me — end-user advocate writes scenarios here in plan-time mode]

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
- [populate me — accepted-as-out-of-scope scenarios live here, with rationale]

## Testing Strategy
<!--
How each task will be verified — unit tests, integration tests, runtime
verification commands. Prefer concrete command lines ("run
`npm run test:links`") or file paths ("new Playwright test at
tests/e2e/foo.spec.ts") over vague statements ("test manually"). See
~/.claude/rules/vaporware-prevention.md.
-->
- [How each task will be verified]

## Walking Skeleton
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
[Populated during implementation — see Mid-Build Decision Protocol.
Plan-time decisions with interface impact: surface to user via
AskUserQuestion BEFORE recording — see ~/.claude/rules/planning.md
"Plan-Time Decisions With Interface Impact — Surface To User".
Each Tier-2+ decision must also have a docs/decisions/NNN-slug.md
record landed in the same commit.]

## Pre-Submission Audit
<!--
REQUIRED for Mode: design plans before invoking systems-designer.
DELETE this section if Mode: code or Mode: design-skip.

Run the five class-sweeps from ~/.claude/rules/design-mode-planning.md
"Pre-Submission Class-Sweep Audit". Document one line per sweep with
the count and result. Fix all gaps found BEFORE submitting to
systems-designer.

Format:
  S1 (Entry-Point Surfacing): swept, N matches across Sections 6-9, M cited correctly, K added to Tasks/Files
  S2 (Existing-Code-Claim Verification): swept, N matches, M verified against file, K corrected
  S3 (Cross-Section Consistency): swept, N "reliable/unchanged" claims, M reconciled, 0 contradictions remaining
  S4 (Numeric-Parameter Sweep): swept for params [<list>], all values consistent
  S5 (Scope-vs-Analysis Check): swept, N "Add/Modify" verbs, all checked against Scope OUT, 0 contradictions

If a sweep returns zero matches, write "swept, 0 matches" — don't omit
the line. Trivial single-task plans may write "n/a — single-task plan,
no class-sweep needed" for each line.

Why this exists: prevents the multi-round sibling-instance dance with
systems-designer that an originating 2026-04-28 review effort (an
auth-refactor plan, eight rounds to converge) surfaced 11 distinct
failure classes from. The reviewer is a safety net, not the primary
discovery mechanism. See ~/.claude/rules/design-mode-planning.md and
~/.claude/docs/failure-modes.md FM-007 through FM-017 for the
underlying failure classes.
-->
- S1 (Entry-Point Surfacing): [populate me]
- S2 (Existing-Code-Claim Verification): [populate me]
- S3 (Cross-Section Consistency): [populate me]
- S4 (Numeric-Parameter Sweep): [populate me]
- S5 (Scope-vs-Analysis Check): [populate me]

## Definition of Done
- [ ] All tasks checked off
- [ ] All tests pass
- [ ] Linting/formatting clean
- [ ] SCRATCHPAD.md updated with final state
- [ ] Completion report appended to this plan file

<!--
================================================================
Systems Engineering Analysis — REQUIRED when Mode: design
================================================================

If this plan has Mode: design in the header, the 10 sections below
are mandatory. Each section must have substantive content specific
to this task (not placeholder text). The plan-reviewer.sh hook
enforces this at plan-creation time. The systems-designer agent
reviews the sections for substance before implementation begins.

If Mode: code, you may DELETE everything below this HTML comment
before saving the plan. The sections are only required for
system-design work.

Theme: make the invisible visible. Every section makes one
normally-implicit aspect of the system explicit and checkable.

See ~/.claude/rules/design-mode-planning.md for guidance on what
belongs in each section and why.
-->

## Systems Engineering Analysis

### 1. Outcome (measurable user outcome, not output)
[What does success look like from the user's perspective, in measurable
terms? Include the time-to-outcome expectation. Example:
"Within 30 min of X happening, Y is observably true at URL Z, OR the
user receives a clear notification explaining what's blocked." NOT
"the system is built."]

### 2. End-to-end trace with a concrete example
[Walk ONE real example through the system step by step, with actual
values, IDs, sizes. Name every state change at every boundary. This is
where invisible state changes become visible. If writing the trace
surfaces "I don't know how this happens" moments, those are gaps to
close BEFORE implementation.]

### 3. Interface contracts between components
[For every component boundary, document the contract: data format,
size limits, timing expectations, failure modes, who validates what.
Components don't break — interfaces break. Each contract should read
as "X promises Y that...".]

### 4. Environment & execution context
[What does the runtime environment provide? What's the working
directory? What env vars are set? What tools are pre-installed?
What's ephemeral vs. persistent? What happens across restarts?]

### 5. Authentication & authorization map
[Every external boundary has an auth story. For each: what credential
format, which key/token, what permissions it needs, what tier/quota
applies. Note rate limits explicitly.]

### 6. Observability plan (built before the feature)
[Every step emits what signal? Where do logs go? How would I
reconstruct what happened from logs alone if everything fails? Every
major state transition should emit a visible checkpoint.]

### 7. Failure-mode analysis per step
[Table: for each step, what can fail, what's the observable symptom,
what's the recovery/retry policy, when does it escalate to a human?
This should be the longest section — failure modes are the bulk of
real-world system behavior.]

### 8. Idempotency & restart semantics
[What happens if each step runs twice? If a step partially completes?
What's the restart procedure from every possible intermediate state?
Systems that can't restart cleanly become corrupted systems.]

### 9. Load / capacity model
[What's the throughput limit? What's the bottleneck resource (API
rate limit, runner concurrency, DB connections, memory)? What happens
at saturation — graceful degradation or catastrophic failure?]

### 10. Decision records & runbook
[Non-trivial choices with alternatives considered (for the decisions
log). Plus: for each known failure mode, a runbook entry of symptom
→ diagnostic steps → fix or escalation. Written before production,
not after first incident.]
