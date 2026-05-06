---
title: Verification overhead is a symptom of weak structural foundation
date: 2026-05-05
type: architectural-learning
status: pending
auto_applied: false
originating_context: Closing the GAP-16 (closure-validation gate) + Tranche 0b (Build Doctrine Phase 0 migration) parallel build session. After shipping both tranches' code, the orchestrator faced a 13-task-verifier-dispatch closure dance estimated at ~65K tokens. User pushed back: "Why do you call closing a plan a 'dance'? Have we over-engineered this?" Conversation deepened into "show me the incentive and I'll show you the outcome" framing recall + structural critique of why verification is so heavy.
decision_needed: Should we treat verification overhead as the primary harness-architecture problem and pause new failsafe work in favor of a multi-tranche structural redesign? Specifically: (a) freeze additions to the gate stack, (b) open a multi-tranche `architecture-simplification` plan, (c) start with the work-shape library as the highest-leverage missing piece, (d) revise the existing closure mechanisms (task-verifier mandate, plan-edit-validator, plan-closure-validator) once the structural layer is in place rather than as another patch.
predicted_downstream:
  - docs/plans/architecture-simplification.md (NEW parent plan, multi-tranche)
  - adapters/claude-code/rules/orchestrator-pattern.md (definition of "done" reframed)
  - adapters/claude-code/rules/planning.md (work-sizing tier discipline applied to harness-dev)
  - adapters/claude-code/agents/{plan-phase-builder,task-verifier,code-reviewer,end-user-advocate}.md (incentive redesign extending Counter-Incentive Discipline)
  - adapters/claude-code/hooks/plan-closure-validator.sh (candidate for retirement or scope reduction)
  - adapters/claude-code/hooks/plan-edit-validator.sh (candidate for risk-tiered behavior)
  - adapters/claude-code/templates/work-shapes/* (NEW directory — work-shape library)
  - adapters/claude-code/templates/plan-template.md (extended with risk tiers, work-shape references)
  - docs/decisions/NNN-architecture-simplification-direction.md (new ADR)
  - build-doctrine/ (significant cross-references; integration mapping needed — see follow-up review)
---

# Verification overhead is a symptom of weak structural foundation

## What was discovered

Two months of harness development (Generations 4 → 5 → 6 → Build Doctrine integration) added a stack of failsafe mechanisms in response to specific failures. Each was correct as a response. Cumulatively they have produced a closure ritual that costs more than the work it gates: closing a 7-task harness-dev plan today requires ~13 sub-agent dispatches and ~65K tokens. The user identified this as over-engineering and asked what's missing structurally.

The deeper insight: **verification gets heavy when the agent has too much discretion. Discretion gets large when the structure is loose. We have been adding verification because the structure underneath isn't doing its job.** The failsafe stack exists because the foundation can't support lighter verification. Adding more failsafes does not fix the foundation; it papers over the fact that the foundation is missing key pieces.

The user's framing — "show me the incentive and I'll show you the outcome" — applies but is necessary-not-sufficient. Single-goal incentive redesign (e.g., reframing the orchestrator's "done" from "code shipped" to "plan closed") helps, but it does not address the underlying structural shortfalls that make verification heavy in the first place.

This discovery captures everything surfaced in the 2026-05-05 conversation about why the harness needs structural redesign rather than additional reactive enforcement.

### The reactive-enforcement pattern

| Mechanism | Added | Failure it solved |
|---|---|---|
| `task-verifier` mandate | 2026-04-09 | Self-reported "done" tasks that weren't done (vaporware shipping) |
| `plan-edit-validator` | 2026-04-15 | Self-flipped checkboxes without evidence |
| Evidence-first protocol | 2026-04-15 | Stale or fabricated evidence |
| `pre-stop-verifier` | 2026-04-15 | Sessions ending with unverified plans |
| `runtime-verification-executor` + reviewer | 2026-04-15 | Code shipped without runtime exercise |
| `tool-call-budget` | 2026-04-15 | Drift across long sessions without audit |
| Class-aware reviewer feedback (7 agents) | 2026-04-24 | Narrow-fix bias on adversarial review |
| `product-acceptance-gate` (Gen 5) | 2026-04-24 | Plans completed without product user observation |
| Gen 6 narrative-integrity hooks (A1, A3, A5, A7, A8) | 2026-04-26 | Agent claims contradicted by transcript evidence |
| `scope-enforcement-gate` | 2026-05-03 | Builder commits drifting beyond declared plan scope |
| `dag-review-waiver-gate` | 2026-05-03 | Tier 3+ plans dispatched without DAG approval |
| `prd-validity-gate` + `spec-freeze-gate` | 2026-05-04 | Plans built against missing-or-incomplete PRDs |
| `findings-ledger-schema-gate` | 2026-05-04 | Findings scattered across artifacts without schema |
| `comprehension-gate` (R2+) | 2026-05-04 | Builders shipping syntactically-correct work with model-mismatch |
| `definition-on-first-use-gate` | 2026-05-04 | Doctrine docs introducing undefined acronyms |
| `plan-closure-validator` | 2026-05-05 | Plans stranded ACTIVE despite shipped code |

Each mechanism solved a real failure. None of them changed the underlying agent incentive structure or the structural foundation that lets the failure happen in the first place. The result: each failure mode now has a gate that catches it after the agent attempts the bad behavior, but the agent's tendency toward the bad behavior is unchanged.

### The pattern this produces

When a new failure surfaces:

1. The agent does the bad thing (because the incentive points there).
2. A gate or reviewer catches it (sometimes; sometimes the gap exists for weeks).
3. We diagnose, build a new gate, ship the gate.
4. The agent's incentive is unchanged. It still wants to do the bad thing.
5. The agent finds a different path to the same bad outcome OR the gate has a blind spot.
6. New failure mode surfaces. Loop.

The closure-stranding incident (2026-05-05) is a textbook instance. Plans were stranding ACTIVE despite shipped code. We diagnosed it as "no mechanism prevents Status: COMPLETED transitions without closure work." We built `plan-closure-validator`. The validator catches the failure if the agent ATTEMPTS to flip Status without closure. But the agent's incentive — "I shipped code, my work is done, closure is bookkeeping" — is unchanged. The agent will still NOT flip Status (avoid the gate by simply leaving the plan ACTIVE). The new gate catches one shape of the failure; the underlying tendency produces a different shape.

## Why it matters

Verification overhead has reached the point where the cost of running closure exceeds the cost of the work that closure gates. For a 7-task harness-dev plan:

- Build cost: ~30 minutes of focused work, real commits, real test runs
- Closure cost: ~13 task-verifier dispatches, ~65K tokens, multiple agent rounds

When closure costs more than the work, closure gets skipped. When closure gets skipped, plans strand. When plans strand, we add another gate. The system is in a feedback loop where each iteration makes verification heavier and incentivizes more skipping.

Beyond the cost: the heaviness signals to the operator (the user, or a future maintainer) that the harness is friction-laden, that the cost-benefit of using it is degrading. Even when the failsafes catch real failures, the felt experience is "the harness is in my way." Subjective trust in the system erodes. The system's intended self-improving learning loop slows.

There is no path to a self-improving harness through more reactive enforcement. Every additional gate is technical debt the harness will carry forward. The compound interest on this debt is what produced the current overhead.

The user's question — "Have we over-engineered this?" — is the right question, asked at the right moment.

## What's structurally missing (the inventory)

Ten distinct structural gaps surfaced in the conversation. Each contributes to verification heaviness; addressing each would reduce verification load proportionately. Listed in rough order of leverage.

### 1. Specs are prose, not contracts

Plans are markdown. Builders interpret prose. Interpretation drift is the single largest source of build-vs-spec divergence — the plan says "implement X" and the builder ships a plausible-but-wrong X because the prose admitted multiple interpretations.

What's missing: machine-checkable specs. A spec that says "this function takes `(string, number) → boolean` and these 5 input/output pairs must pass" is mechanically verifiable. A spec that says "implement the rate limiter" is not.

The harness has started this with `## Behavioral Contracts` at R3+ (idempotency / performance budget / retry semantics / failure modes), but the contracts are still prose. Real contracts would be tests, types, schemas, golden files — not paragraphs.

### 2. Evidence is prose, not artifacts

Builders write evidence blocks describing what they did. Verifiers read the prose and judge whether the work happened. This is symmetrical with the prose-spec problem: prose evidence can be plausibly fabricated, and verifying its truthfulness requires LLM judgment.

What's missing: mechanical evidence. Test pass output captured verbatim. Diff stats showing the change shape. Commit SHA matched against the plan's `## Files to Modify/Create` list. Schema-validation passes. File-existence checks. These are bash-script-cheap and mechanically verifiable. LLM-judgment evidence becomes an escalation path, not the primary substrate.

### 3. No standard shapes for common work

When a builder receives "implement a new hook," there is no canonical shape they MUST follow. Each hook ends up slightly different — different test conventions, different stderr formats, different self-test patterns. Each rule ends up slightly different. Each migration ends up slightly different. Verification is heavy because every output is bespoke.

What's missing: a work-shape library. Every recurring task class (build a hook, build a rule, migrate a doc, add an API route, refactor a component, author a decision record, write a self-test, etc.) has:

- A canonical file structure
- A canonical test shape
- A canonical pattern of imports / exports / stderr
- A worked example to copy from
- Mechanical checks that verify shape compliance

Builders pick a shape, fill in the variables, mechanical checks verify shape compliance. LLM judgment is needed only when the work doesn't fit any existing shape (escalation path). For shaped work, ~80% of verification becomes "did the output conform to the shape?"

### 4. Builders have too much scope per task

A task like "build the closure-validation gate" is huge. It encompasses: design the gate, write the hook, write the self-test, write the rule doc, wire settings, sync to live, update enforcement map. Seven decisions in one task. Verification of a 7-decision task is necessarily heavy — there are seven places to drift. The closure of a plan that has 7 such tasks is verifying 49 decisions.

What's missing: work-sizing discipline applied to harness-dev work. The Build Doctrine's T1-T5 tier rubric exists; the harness has not applied it to its own work. A T1 task is "edit one line of a hook." A T2 task is "add one self-test scenario." Each has its own canonical shape and verification weight. A "build the gate" plan would decompose into 12 T1/T2 tasks instead of 1 T3 task. Smaller atomic units = mechanical verification per unit becomes feasible. Plans with smaller tasks close faster, fail more visibly when they fail, and produce smaller commits that are easier to revert.

### 5. Contracts at boundaries are weak

When component A talks to component B, the boundary is rarely typed or contracted explicitly. The hook chain in `settings.json` has matchers and commands but no schema for hook input. Plan files have a header but only a partial schema (the 5-field schema we just shipped is one of the few enforced contracts). Evidence blocks have a loose format. Agent return shapes are documented in prose, not enforced.

What's missing: enforced contracts at every component boundary. JSON schemas, TypeScript types, structured-log formats, machine-readable plan headers, machine-readable agent return shapes. Drift between components is currently caught (sometimes) by reviewers; it should be caught at commit time by mechanical contract validation. Every boundary that survives without a contract is a place where drift can hide indefinitely.

### 6. Tests are not the primary verification substrate

Outside AI, the standard verification stack is: types compile → lints pass → unit tests pass → integration tests pass → CI is green. That stack is mostly mechanical. Human review is a thin escalation layer on top.

In our harness, this is inverted. The `task-verifier` agent (LLM judgment) is the PRIMARY verifier. Tests are a small contributor. That's why verification is heavy — we are doing manual labor at every step that the test suite should be doing automatically.

What's missing: richer test infrastructure. Every hook should have a `--self-test` that runs as part of the closure-precondition (most do, not all). Every rule should have a fixture-based reference set. Every agent should have a regression suite testing its prompt outputs against golden files. Every plan-completion should run the full test suite as a closure precondition. With this stack, the LLM verifier shrinks to "this looks weird, escalate" rather than "verify everything."

### 7. No proportionate verification model

Today every task gets the full task-verifier mandate regardless of risk. A 5-line typo fix gets the same treatment as a runtime feature. Verification cost = `N × full-treatment` instead of `lightweight-default + heavy-on-risk`.

What's missing: risk-tiered verification declared at the task level. Each task in a plan declares one of:

- `Verification: mechanical` — bash check (file exists in commit, self-test passes, diff matches plan). No agent dispatch. Closure trivial.
- `Verification: full` — current task-verifier mandate. Reserved for runtime / multi-file / novel work.
- `Verification: contract` — golden-file or schema-validation comparison. No agent.

Most harness-dev tasks fall into mechanical. Runtime / API / migration tasks fall into full. Schema / config tasks fall into contract. The cost of closing a typical plan drops by 80%+ without losing the ability to do heavy verification where it actually matters.

### 8. Builder failures aren't fed back into the system

When a builder ships wrong work, the failure is caught (sometimes), fixed (sometimes), and forgotten. The builder agent isn't updated. The next build, the next builder makes the same mistake. We add a failsafe to catch it — but the underlying agent's tendency to make the mistake hasn't changed.

What's missing: a calibration loop. Each builder failure should feed into:

- The builder's prompt corpus (this failure mode is now primed against)
- The work-shape library (the relevant shape gets a defensive check)
- The test fixtures (a regression case)
- The prompt of any reviewer that should have caught it

Each failure becomes a permanent immunity rather than a temporary patch. Without this loop, every failure stays an open wound that the gate has to keep bandaging — and gates accumulate even when the underlying agent could be fixed.

This is partially what HARNESS-GAP-11 (reviewer-accountability tracker) addresses for reviewers, but it's gated on telemetry. The same principle applies to builders. The same principle applies to orchestrators. None of these calibration loops exist today.

### 9. Process steps aren't deterministic

"Close a plan" today is: maybe write evidence, maybe update SCRATCHPAD, maybe write completion report, maybe flip Status, maybe push. Each step has discretion in how it's done. Each time the orchestrator does this, it does it slightly differently. Discretion = drift = need for verification of the closure procedure itself.

What's missing: a single deterministic close-plan procedure that branches mechanically, not by judgment. Like a unix shell script:

```
1. Run test suite for files modified in plan. If FAIL → block. (mechanical)
2. Compute evidence: commit SHA + diff stats + test output → write to evidence file. (mechanical)
3. Generate completion report from template + commit log → write to plan. (mechanical)
4. Update SCRATCHPAD with timestamp + plan slug → write. (mechanical)
5. Verify backlog reconciliation. (mechanical)
6. Flip Status. (mechanical)
7. Archive moves automatically. (mechanical)
```

No "verifier dispatches." No "judgment calls." The script either runs to completion or fails at a specific step with a specific error. The user fixes the step and re-runs. The closure procedure becomes a single tool invocation, not a multi-agent ritual.

### 10. We're not honoring the Pareto split of LLM-judgment vs mechanical

LLM judgment is incredible at: reading natural-language requirements, generating draft code, surfacing edge cases the human did not think of, explaining tradeoffs, writing prose, classifying ambiguous inputs. LLM judgment is poor at: counting, applying rules consistently, remembering state across long sessions, refusing to take shortcuts under context pressure, catching its own contradictions.

Our harness uses LLM judgment for both. We have LLMs counting tasks (task-verifier does this), applying mechanical rules (gate-style hooks could do this), remembering state (closure validator). We're using a high-discretion tool for low-discretion problems.

What's missing: clear separation of mechanical from judgment work at the architectural level. Every gate, hook, validator answers: "is this work mechanical (deterministic procedure) or judgment (LLM agent)?" Right now too many are ambiguously both. Drawing the line cleanly removes ~50% of the LLM-as-rule-applier work.

## The architecture this points at

The redesign is a four-layer model where each layer handles a different class of work and the LLM is reserved for what it's actually good at.

```
Layer 1 — Deterministic procedures (NO LLM, mechanical scripts)
  Plan creation: structured authoring against a schema
  Build: builder fills in templated work-shapes
  Test: full suite runs mechanically, output captured as evidence
  Evidence: artifacts (test logs, diffs, SHAs), not prose
  Closure: single deterministic script, not 13 dispatches

Layer 2 — Mechanical contracts (NO LLM, schema + type validation)
  Plan headers (5-field schema, locked) ✓ shipped
  Behavioral contracts at R3+ ✓ shipped (still prose, should be schemas)
  Component shapes (work-shape library) ✗ missing
  Evidence schema ✗ missing
  Settings schema ✓ partially shipped
  Hook input/output schemas ✗ missing
  Agent return-shape schemas ✗ missing

Layer 3 — LLM judgment (escalation only — when Layers 1-2 say "I don't know")
  Specs that don't fit work-shapes (genuinely novel)
  Risk-tiered verification (Verification: full)
  Adversarial review at PR boundaries
  Failure analysis when mechanical layer fails
  Spec authorship (PRD generation, plan drafting)
  Cross-cutting design decisions (architecture, mid-build tier 3)

Layer 4 — Calibration (loops back into Layers 1-3)
  Builder failures → work-shape library updates
  Reviewer mistakes → reviewer prompt updates
  New failure modes → new mechanical checks (after attempting incentive redesign first)
  Aging of mechanisms whose underlying failure no longer recurs
  Telemetry-driven harness self-improvement
```

Each layer is supposed to handle a different class of work. Right now Layer 3 carries an estimated 70% of the verification load when it should be ~10%. Layers 1 + 2 are partial (especially Layer 1's deterministic procedures and Layer 2's missing schemas). Layer 4 doesn't exist yet (HARNESS-GAP-11 is gated on telemetry; calibration generally is paper-only).

This is the architecture the user asked for: "a few deterministic processes and a lightweight validation."

## What this means for the closure problem specifically

Closing a plan should look like:

```
$ /close-plan harness-gap-16-closure-validation

Running test suite for changed files... PASS (10/10 self-test scenarios)
Verifying commits in plan's files-to-modify... 1 commit (120593c) covers 6 files ✓
Generating completion report from template + commit log... done
Updating SCRATCHPAD... done
Verifying backlog reconciliation... HARNESS-GAP-16 absorbed ✓
Flipping Status to COMPLETED... done
Plan archived to docs/plans/archive/

Total: 4 seconds. No agent dispatches.
```

That's the target. Today it's 13 dispatches and 65K tokens. The gap between target and reality is precisely where the structural foundation is missing.

## Options

A. **Continue the current path: stack more failsafes.** Each new failure gets a new gate. Verification overhead continues to grow. Plans continue to strand. Closure dance gets longer. Trust in the harness erodes. Eventually the friction becomes greater than the value the harness provides and it gets bypassed.

B. **Apply incentive redesign only.** Reframe orchestrator's "done" from "code shipped" to "plan closed and archived." Update CLAUDE.md, orchestrator-pattern.md, plan-phase-builder.md, task-verifier.md to embed this. Necessary but not sufficient — addresses behavior at the agent level but not the structural drag underneath.

C. **Apply structural redesign only.** Build the work-shape library, ship the deterministic close-plan procedure, replace prose evidence with mechanical artifacts, etc. — but leave incentives unchanged. Risk: builders find new ways to skip the structure if their incentives still point away from following it.

D. **Apply both — full architecture redesign.** Open a multi-tranche `architecture-simplification` plan that addresses both incentive design AND structural foundation. Pause new failsafe work. Build the missing layers. Retire or scope-down failsafes that the new structure makes redundant. ~3-5 weeks of focused work.

E. **Apply both, sequentially.** Start with incentive redesign (cheap, days), see how much it solves, then layer structural redesign on what remains. Risk: incentive redesign on its own doesn't change the cost of closure (the structure is still missing), so the user still feels the friction; the redesign benefits don't materialize until the structural layer lands.

## Recommendation

**Option D — full architecture redesign as a multi-tranche plan, paused on failsafe work.** The user's framing (incentive design + structural critique together) is the correct shape. Halfway redesigns leave half the failure modes intact and erode trust in the redesign itself.

Concrete shape of the redesign plan:

1. **Tranche A — Incentive redesign at the prompt layer.** ~3-5 days. Update CLAUDE.md, orchestrator-pattern.md, planning.md, plan-phase-builder.md, task-verifier.md, code-reviewer.md, end-user-advocate.md. Reframe "done" definitions. Extend Counter-Incentive Discipline sections with concrete behavior changes (not just "be aware of the bias"). Add calibration-loop language even before the loop is built.

2. **Tranche B — Mechanical evidence substrate.** ~5-7 days. Replace prose evidence blocks with structured-artifact evidence (test output capture, diff-stats summary, commit-SHA + files-modified linkage). Schema for evidence files. Bash-level evidence-write helpers. Backward compat with existing evidence blocks during transition.

3. **Tranche C — Work-shape library.** ~7-10 days. Catalog the recurring task classes in harness-dev (build hook, build rule, migrate doc, add agent, etc.). For each, author a canonical shape (file structure, test shape, stderr format, self-test pattern). Worked example per shape. Mechanical shape-compliance check (does the new file follow the shape?). Replaces the "every output is a snowflake" problem.

4. **Tranche D — Risk-tiered verification.** ~3-5 days. Plan-template extended with `Verification: mechanical | full | contract` field per task. Rewrite task-verifier mandate: only `Verification: full` invokes the agent; `Verification: mechanical` runs a bash check; `Verification: contract` runs schema or golden-file comparison. Update plan-edit-validator to honor the per-task verification level.

5. **Tranche E — Deterministic close-plan procedure.** ~3-5 days. The existing `/close-plan` skill (just shipped today) gets rewritten as a deterministic script that batches all closure work into mechanical steps. No agent dispatches in the closure path. The skill becomes the closure procedure, not a wrapper around the existing dance.

6. **Tranche F — Audit existing failsafes for retirement.** ~2-3 days. Walk every gate in the enforcement map (50 rows in `vaporware-prevention.md`). Mark each as: KEEP (still load-bearing after redesign), SCOPE-DOWN (subsumed by new mechanism but partial), RETIRE (redundant with new substrate). The new `plan-closure-validator` (today) is a strong RETIRE candidate. The `task-verifier` mandate is a strong SCOPE-DOWN candidate.

7. **Tranche G — Calibration loop bootstrap.** ~5-10 days. Even before telemetry lands, manual calibration: every builder failure produces a work-shape-library update, a regression test addition, a defensive prompt extension. Document this as a discipline; mechanize as telemetry comes online.

Total: ~28-45 days of focused work. Substantially smaller than the cumulative cost of continuing to build failsafes (which has consumed ~2 months and produced the current overhead).

**Critical sequencing constraint:** Tranches A, B, C, D, E can run in parallel after the redesign plan is approved. Tranche F (failsafe audit) must come after at least A + C + E land. Tranche G can start in parallel with all others.

**What this means for current state:**

- GAP-16 + Tranche 0b plans stay `Status: ACTIVE` for now. Closing them via the 13-dispatch dance is exactly the over-engineered behavior the redesign would eliminate. Better to leave them ACTIVE briefly, ship the deterministic close-plan procedure (Tranche E), and use IT to close them — both as a real-world test of the new procedure AND as the symbolic moment the redesign demonstrates value.
- Today's `plan-closure-validator` ships into a tagged-for-retirement state. It still fires; it still works; but the redesign plan documents that it is a candidate for removal once the deterministic close-plan procedure lands.
- No new gates land between this discovery and the redesign plan's approval. Hard freeze on reactive enforcement.

## Anti-recommendations (what NOT to do)

- **Do not rush the redesign by skipping the prompt-level incentive layer (Tranche A).** Structure without incentive change leaves builders looking for shortcuts around the structure.
- **Do not start with Tranche F (failsafe audit) before Tranches A-E land.** Auditing-for-retirement before knowing what the new structure looks like produces premature retirement decisions.
- **Do not treat this as a one-week effort.** The accumulated debt is real and substantial. Cutting it down requires proportionate investment.
- **Do not bypass the user on the redesign approval.** This is a tier-3 architectural decision (irreversible-in-spirit; once we commit to it, walking back means re-stacking failsafes from scratch). User approval before Tranche A starts.

## The deeper principle

Every time we add a gate, the question we should ask is: **what incentive AND what structure would make the agent NOT need this gate?** If the answer is "we can't change the agent's incentives or the structural substrate" — the gate is justified. If the answer is "we can change either" — the gate is technical debt accumulating.

For nearly every gate we have shipped in the last two months, at least one of the two paths (incentive or structure) has been changeable. We have not done it. The redesign starts the work of doing it.

**Failsafes after incentive design AND structural foundation, not before.**

## Decision

(populated once user reviews and approves a path forward)

## Implementation log

(empty until decision is made and Tranches begin)

## Cross-references

- Originating conversation: 2026-05-05 session covering GAP-16 + Tranche 0b parallel build → closure overhead → "show me the incentive" recall → 10 missing structural pieces
- `docs/build-doctrine-roadmap.md` — current Build Doctrine integration tracker; the redesign substantially overlaps with the doctrine's intent (TODO: dedicated comparison review per user request — "compare it to the Build Doctrine that we're supposed to be building right now")
- `docs/agent-incentive-map.md` — earlier work on Counter-Incentive Discipline; this discovery extends the framing from "warn each agent about its bias" to "redesign the agent's reward structure so the bias does not fire"
- `docs/decisions/020-comprehension-gate-semantics.md` — comprehension gate at R2+ as a partial step toward the work-shape concept (articulate the spec model in a structured way)
- `docs/decisions/015-prd-validity-gate-c1.md`, `016-spec-freeze-gate-c2.md`, `017-plan-header-schema-locked.md` — partial steps toward Layer 2 mechanical contracts
- `~/.claude/rules/vaporware-prevention.md` — the 50-row enforcement-map that Tranche F will audit
- `~/claude-projects/Build Doctrine/outputs/unified-methodology-recommendation.md` — T4's reliability-spine framing; significant overlap with the four-layer architecture proposed here
- HARNESS-GAP-11 (reviewer-accountability tracker) — telemetry-gated; same Tranche-G calibration-loop concept applied to reviewers specifically
- HARNESS-GAP-16 (today's closure-validation gate) — strong retirement candidate after Tranche E ships
