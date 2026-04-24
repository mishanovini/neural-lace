# Acceptance Scenarios — Adversarial Observation of the Running Product

**Classification:** Hybrid. The plan-time authoring discipline, scenarios-shared/assertions-private rule, and gap-analyzer convergence loop are Patterns the planner and orchestrator self-apply. The runtime acceptance gate is a Mechanism (`product-acceptance-gate.sh` Stop hook, Phase D of `docs/plans/end-user-advocate-acceptance-loop.md`) that mechanically blocks session end when an ACTIVE non-exempt plan lacks a PASS artifact for the current `plan_commit_sha`. The plan-template section presence (`## Acceptance Scenarios` for user-facing plans) is Mechanism-enforced by `plan-reviewer.sh`. The exemption mechanism (`acceptance-exempt: true` plan-header field with required `acceptance-exempt-reason:`) is honored by both the reviewer and the gate.

## Why this rule exists

Every Gen 4 enforcement mechanism except `pre-stop-verifier.sh` and `tool-call-budget.sh` gates on something the BUILDER produces — a plan file, an evidence block, a test assertion, a self-report claim. The builder is the agent that fails at completeness, so self-certification (even via `task-verifier` running the same model) tends to converge on "the builder thinks it's done." The harness had no mechanism for **adversarial observation** of the running product from the user's perspective, which is why incomplete builds shipped despite a growing stack of enforcement.

The acceptance loop closes that gap with a single agent (`end-user-advocate`) invoked in two modes — plan-time (paper review) and runtime (browser automation against the live app) — backed by a Stop-hook gate that prevents session end when a non-exempt plan has no PASS artifact for the current plan commit. A supporting `enforcement-gap-analyzer` agent runs on every acceptance failure, reads the session transcript + plan + hooks that fired, and produces a concrete harness improvement proposal. Every user-visible gap becomes a harness improvement over time.

## The full loop

### Stage 1 — Plan-time authoring

When a plan reaches a stable shape (Goal / Scope / Edge Cases populated), the planner invokes `end-user-advocate` in plan-time mode via the Task tool with the plan path. The advocate:

1. Reads the plan's `## Goal`, `## Scope`, `## Edge Cases`, and any UI / behavior sections.
2. Identifies the user-observable behaviors the plan claims it will produce. One behavior = one scenario.
3. Authors each scenario into the plan's `## Acceptance Scenarios` section (template-introduced; see `templates/plan-template.md`). Replaces `[populate me]` placeholders; does not append duplicates.
4. Flags any place the plan is too thin to write a scenario for — Goal under-specifies, Scope is vague, an Edge Case has no observable success criterion. Returns those gaps as a structured `Plan-Time Advocate Feedback:` block to the calling session.
5. On re-invocation after the planner closes the gaps, confirms no remaining feedback (or surfaces what's left).

The advocate also moves rejected-but-still-real scenarios to `## Out-of-scope scenarios` with a per-entry rationale. This prevents "acceptance must pass" from becoming unbounded and blocking every plan.

**Plan cannot proceed to implementation until the advocate's plan-time feedback is closed.** The rule is the same shape as the existing `ux-designer` and `systems-designer` mandates: plan-time review by a peer planner agent before build begins.

### Stage 2 — Build (scenarios shared, assertions private)

When the orchestrator dispatches build work to `plan-phase-builder` sub-agents, the dispatch prompt includes the plan's `## Acceptance Scenarios` (motivation, user flow, success criteria) but does NOT include the advocate's internal assertion list. The builder builds toward the user's observable outcome, not toward a string the test will grep for.

This is the **scenarios-shared, assertions-private** discipline — load-bearing because LLM builders teach-to-the-test extremely easily. If the builder sees "the page must contain `Order #1234`," they hardcode the string. If they see "the order detail view must show the user the order number they just created," they have to actually wire the data path. See `rules/orchestrator-pattern.md`'s "Scenarios-shared, assertions-private" sub-section for the dispatch-prompt template.

### Stage 3 — Runtime execution

After build, before session end, the advocate is invoked again in runtime mode. The advocate:

1. Parses `## Acceptance Scenarios` from the plan file. Extracts each scenario's slug, user-flow steps, and success criteria.
2. For each scenario:
   - Pre-flight: `curl -s <base-url>/<some-cheap-path>` to confirm the app is reachable. If not, writes a FAIL artifact with `failure_reason: "<app-url> not reachable"` and stops.
   - Opens a browser via `mcp__Claude_in_Chrome__navigate` (or `mcp__Claude_Preview__preview_start` fallback).
   - Executes the user-flow steps against the live app. Uses `get_page_text` / `read_page` to extract rendered text. Uses `read_console_messages` and `read_network_requests` for artifacts.
   - Asserts against success criteria with adversarial framing: "what would a user reasonably try that I haven't tried? Does it still hold?"
   - Captures screenshot, network log, console log as sibling files.
3. Writes a JSON artifact at `.claude/state/acceptance/<plan-slug>/<session-id>-<ISO-timestamp>.json` with the schema documented in `agents/end-user-advocate.md`. The artifact records `plan_commit_sha` so the gate can detect staleness.
4. Returns a one-paragraph summary citing the artifact path.

### Stage 4 — Stop-hook gate

`product-acceptance-gate.sh` (Phase D of the parent plan) runs in the Stop-hook chain after `pre-stop-verifier.sh`. It:

1. Iterates over all plans in `docs/plans/*.md` with `Status: ACTIVE`.
2. For each:
   - If `acceptance-exempt: true` is declared with a substantive `acceptance-exempt-reason:` (>= 20 chars), allow stop for this plan and emit `[acceptance-gate] plan <slug> is acceptance-exempt; reason: <...>`.
   - Otherwise, look for a JSON artifact under `.claude/state/acceptance/<slug>/` whose `plan_commit_sha` matches the current plan file's HEAD SHA AND whose verdict is PASS for every in-scope scenario.
   - If found, allow stop. If missing, FAIL, or stale, BLOCK with stderr message naming the missing scenarios and pointing at the runtime advocate invocation command.
3. If any ACTIVE plan blocks, blocks session end. If all pass (or all are exempt or absent), allow stop.

The walking-skeleton form of this gate already lives in `pre-stop-verifier.sh` Check 0 (Phase A). Production hardening lands in Phase D.

### Stage 5 — Gap-analysis on FAIL

When a runtime advocate run produces a FAIL, `enforcement-gap-analyzer` (Phase E) is auto-invoked with the session transcript + plan + failing scenario + list of hooks that fired. The analyzer:

1. Reviews EXISTING rules / hooks first. If an existing mechanism should have caught this and didn't, the proposal AMENDS that mechanism (not adds a new one).
2. Produces a structured proposal under `docs/harness-improvements/<NNN>-<slug>.md` with required fields: Title, Date, `Class of failure:`, `Existing rules/hooks that should have caught this:`, `Why current mechanisms missed this:`, Proposed change (concrete diff or file creation), Testing strategy.
3. Hands the proposal to the extended `harness-reviewer` (Phase E), which verdicts PASS / REFORMULATE / REJECT against an explicit generalization check: too narrow? overlaps existing rule? `Class of failure` substantive?

Every user-visible gap becomes a harness improvement over time, not a one-off fix — the harness becomes self-improving from its own observed failures.

## Convergence criteria

A plan reaches "acceptance complete" when:

1. All `## Acceptance Scenarios` have a runtime PASS in the artifact for the current `plan_commit_sha`, AND
2. All advocate plan-time feedback gaps have been resolved (closed in the plan or moved to `## Out-of-scope scenarios` with rationale), AND
3. The Stop-hook gate allows session end without a waiver.

If a scenario keeps failing after multiple build iterations, the loop is a signal — fix the code, narrow the scenario, or move it to `## Out-of-scope scenarios` with explicit rationale (e.g., "feature requires manual auth setup the test environment cannot provide; deferred to manual QA"). Silent skipping is not an option; the test-skip ban (`no-test-skip-gate.sh`) and the bug-persistence rule (`testing.md`) extend to acceptance scenarios.

## Scenario file format specification (the human-authored, machine-extractable contract)

Scenarios live as structured Markdown inside the plan file's `## Acceptance Scenarios` section. The format is human-authorable (a planner or the advocate writes them by hand) AND machine-extractable (the runtime mode parses them deterministically). Both properties are load-bearing — humans need to author / review, the runtime needs to execute.

### Per-scenario structure

Each scenario is a `###`-level sub-section under `## Acceptance Scenarios`. The exact shape:

```
### <slug> — <one-line description>

**Slug:** `<slug>`

**User flow:**
1. <step 1 — imperative, user-perspective>
2. <step 2>
...

**Success criteria (prose):** <what must be observably true after the flow completes>.

**Artifacts to capture:** <screenshot description, network log expectation, console log expectation>.

**Edge variations (optional):**
- <variation 1>
- <variation 2>
```

### Field rules

| Field | Required | Rule |
|---|---|---|
| Heading `### <slug> — <description>` | Yes | One per scenario. Slug appears both in heading and in the `**Slug:**` line — the line is the authoritative parse target. |
| `**Slug:** \`<slug>\`` | Yes | Kebab-case, ASCII only, ≤ 60 chars, unique within the plan, stable across plan revisions. The runtime mode keys artifacts by slug; renaming a slug breaks artifact correlation. |
| `**User flow:**` numbered list | Yes | Numbered `1.`, `2.`, … with no skipped numbers. Steps are imperative ("Click Save", "Type 'foo' into the Name field"), USER-PERSPECTIVE. Never IMPLEMENTATION-PERSPECTIVE ("the component re-renders"). |
| `**Success criteria (prose):**` paragraph | Yes | Prose, one paragraph. Describes what the USER OBSERVABLY SEES after the flow. Prose is intentional — exact strings and selectors live in the advocate's PRIVATE assertions, not here (Goodhart prevention). |
| `**Artifacts to capture:**` line or list | Yes | Three things: what screenshot to take, what network requests to expect, what console output to expect (or "no console errors"). |
| `**Edge variations (optional):**` list | No | Use ONLY when one flow has multiple branches sharing most steps. Otherwise write a separate scenario. |
| `**Target URL (optional):** <url>` | No | Per-scenario URL override. Defaults to caller-provided base URL or `http://localhost:3000`. |

### Caps

- **Soft cap:** 20 scenarios per plan. Above 20, the advocate groups variants under parent scenarios or moves minor cases to `## Out-of-scope scenarios`.
- **Hard cap:** 50 scenarios per plan. The advocate refuses to author more and surfaces "the plan is too broad; split it" as a Critical gap in plan-time feedback.

### What the runtime parser extracts

The runtime mode parses this section by:

1. Locating the `## Acceptance Scenarios` heading.
2. Reading every `### ` heading until the next `## ` heading (typically `## Out-of-scope scenarios`).
3. For each scenario, extracting the slug (from the `**Slug:**` line — authoritative), user flow (from the numbered list under `**User flow:**`), success criteria prose, and artifact expectations.
4. If the section is missing, empty, or contains only `[populate me]`, the runtime aborts with `[acceptance] no scenarios in plan; invoke plan-time mode first`.

This is the contract the runtime mode depends on. Hand-authored scenarios that don't match the format will fail to parse — and the runtime will surface that failure rather than silently skipping scenarios.

### Scenarios-shared, assertions-private — the format is the discipline

The format above is what's SHARED with builders. The advocate's PRIVATE assertions (exact strings, selectors, regex patterns, JSON paths, computed values) live only in its runtime-mode head, never in the plan file. If a scenario's success criterion drifts from prose ("the user sees their order ID") to a literal assertion string ("the page contains `Order #1234`"), the planner has eroded the discipline. Catch this in plan-time review.

## Exemption mechanism: `acceptance-exempt: true`

Some plans have NO product user. Skipping the acceptance loop for these plans is legitimate; running browser automation against a Dockerfile change is theatre. The exemption mechanism is a plan-header field plus required justification:

```
acceptance-exempt: true
acceptance-exempt-reason: <one-sentence substantive justification (>= 20 chars)>
```

Both `plan-reviewer.sh` (skips the `## Acceptance Scenarios` requirement) and `product-acceptance-gate.sh` (treats exempt plans as no-artifact-needed) honor the exemption. The reason field is required: an unjustified `acceptance-exempt: true` is BLOCKED by the same hook with a clear message naming the missing reason.

### When to use the exemption

**Yes — exemption is appropriate:**

- **Harness-development plans.** Plans whose entire scope is improving the harness itself (new agent, new hook, new rule, new template). The "user" is the maintainer, who exercises the harness in subsequent sessions. Example: `docs/plans/end-user-advocate-acceptance-loop.md` (the bootstrap plan for this very rule) is exempt because the loop doesn't exist yet to apply to itself.
- **Pure-infrastructure plans.** Dockerfile changes, CI workflow tweaks, dependency bumps with no user-facing surface. Example: a plan to bump Node 18 → 20 in `.github/workflows/ci.yml` has no user-observable behavior change.
- **Migration-only plans without UI implications.** A backfill of a database column the user never sees. Example: re-encoding a stored hash format internally.

**No — exemption is NOT appropriate:**

- Backend-only changes that affect any user-observable response. The user observes through the UI; if a field appears differently, the loop applies.
- "Just a small UI tweak." Small UI changes are exactly the bucket where silent regressions accumulate; the loop is cheap (one scenario, ≤ 30s) and worth running.
- "Tests pass without it." The tests passing is necessary but not sufficient; the loop validates user-observable outcome which tests cannot.
- "I'm in a hurry." Speed pressure is the highest-risk moment for skipping verification; the loop exists for exactly this case.

**Audit:** `harness-reviewer` may review exemption rationale during routine harness-dev review. Chronic exemption use without substantive reason is itself a signal — surface it in the weekly `/harness-review`.

## Cross-references

- **Plan template:** `templates/plan-template.md` introduces `## Acceptance Scenarios` and `## Out-of-scope scenarios` between `## Edge Cases` and `## Testing Strategy`. The template's HTML-comment guidance points at this rule.
- **Agent:** `agents/end-user-advocate.md` — production-hardened in Phase C of the parent plan. Documents both modes (plan-time paper review with class-aware feedback; runtime browser automation with adversarial probes), the scenario format spec, the artifact schema, the browser MCP fallback chain, and the scenarios-shared / assertions-private discipline.
- **Hook:** `hooks/product-acceptance-gate.sh` (Phase D — production gate). Today's walking-skeleton equivalent lives in `hooks/pre-stop-verifier.sh` Check 0.
- **Plan-reviewer:** `hooks/plan-reviewer.sh` enforces `## Acceptance Scenarios` presence on user-facing plans (Phase B.1 / 2.1 of the parent plan extends this; check current state).
- **Gap-analyzer:** `agents/enforcement-gap-analyzer.md` (Phase E) — proposes harness improvements from runtime FAILs.
- **harness-reviewer:** `agents/harness-reviewer.md` (Phase E) — extended remit to review enforcement-gap proposals with a generalization check.
- **Orchestrator pattern:** `rules/orchestrator-pattern.md` (Phase F) — codifies scenarios-shared / assertions-private in builder dispatch.
- **Parent plan:** `docs/plans/end-user-advocate-acceptance-loop.md` — full design and phasing, including Generation 5 framing.

## Failure modes (and how the loop handles them)

- **Plan-time advocate proposes scenarios the plan can't reasonably cover.** Use `## Out-of-scope scenarios` — advocate proposes, planner accepts/rejects each with rationale.
- **Runtime scenarios obsoleted as code evolves.** Scenarios are versioned with the plan via `plan_commit_sha` in the artifact. Stale artifacts are ignored by the gate; the user re-runs the advocate against current HEAD.
- **Browser automation flakiness causes false FAILs.** Retry policy: 2 retries per scenario with fresh browser context. Persistent FAIL (3 attempts) counts as FAIL. Transient FAIL (1-2 retries then PASS) is logged but doesn't block.
- **Builder sees assertions via tool-call inspection.** The orchestrator pattern explicitly excludes assertion content from dispatch prompts. The advocate's runtime mode runs in a separate sub-agent session; its internal state does not propagate to the builder.
- **Waiver abuse — user writes waivers rather than fixing bugs.** Every waiver is logged in the commit that exits the session. Weekly `/harness-review` surfaces waiver frequency; chronic waivers trigger a review of the underlying bug or the gate itself.
- **Multiple plans ACTIVE simultaneously, each with its own acceptance artifact.** Hook iterates over ALL ACTIVE plans; each must have a satisfying artifact (or exemption). Session end blocks if any lacks one.
- **Plan has zero user-facing changes.** Use `acceptance-exempt: true` with substantive reason. Plan may include the `## Acceptance Scenarios` section with a single "n/a" entry for auditability, but it is not required.
- **Dev server not running during runtime invocation.** Runtime agent first checks reachability via curl. If unreachable, writes FAIL artifact with reason "dev server not running" rather than producing spurious scenario failures.

## Enforcement summary

| Layer | What it enforces | File |
|---|---|---|
| Template | Shape of `## Acceptance Scenarios` and `## Out-of-scope scenarios` sections | `templates/plan-template.md` |
| Rule (this doc) | When to use the loop, scenarios-shared discipline, exemption guidance | `rules/acceptance-scenarios.md` |
| Plan-reviewer | Presence of `## Acceptance Scenarios` on non-exempt user-facing plans (Phase B.1 extends) | `hooks/plan-reviewer.sh` |
| Plan-time advocate | Scenarios are substantive and cover the plan's stated outcomes | `agents/end-user-advocate.md` (Mode: plan-time) |
| Runtime advocate | Scenarios actually pass against the running app | `agents/end-user-advocate.md` (Mode: runtime) |
| Acceptance gate | Session end blocked when ACTIVE non-exempt plan has no PASS artifact | `hooks/product-acceptance-gate.sh` (Phase D) — walking-skeleton form in `hooks/pre-stop-verifier.sh` Check 0 |
| Gap-analyzer | Every runtime FAIL produces a generalized harness-improvement proposal | `agents/enforcement-gap-analyzer.md` (Phase E) |
| harness-reviewer (extended) | Gap proposals survive a generalization check before commit | `agents/harness-reviewer.md` (Phase E) |

The first two are documentation (Pattern-level). The middle four are mechanisms or agents enforced at specific points in the lifecycle. The last two close the self-improvement loop. Together they make the user the final verifier — even when the user is not in the loop in person, the advocate is their proxy.
