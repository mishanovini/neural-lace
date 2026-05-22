# Decision 035 — Diagnostic-First Protocol + Hypothesis-vs-Proof Labeling + Refutation-Criteria Requirement

**Date:** 2026-05-22
**Status:** Active
**Stakeholders:** Misha (operator); the Dispatch orchestrator (Claude) as the primary in-scope agent; all sub-sessions spawned via `mcp__ccd_session__spawn_task` / `mcp__ccd_session_mgmt__start_code_task` / in-process `Task`-tool dispatch as in-scope downstream consumers.
**Cross-references:** `~/.claude/rules/diagnosis.md` (DIAGNOSTIC-FIRST PROTOCOL section), `~/.claude/rules/claims.md`, `~/.claude/agents/plan-phase-builder.md` (Investigation-work mandate), `docs/failure-modes.md` FM-029, `docs/lessons/2026-05-22-fm-001-misdiagnosis.md`, `docs/decisions/033-failure-mode-catalog-cross-project-convention.md` (the FM-catalog reflex this decision composes with), `docs/plans/diagnostic-first-protocol-enforcement.md` (the plan that landed this decision).

## Context

On 2026-05-14 a downstream-product project (a Next.js + Vercel + Supabase web app, kept anonymous here per harness-hygiene policy) had its production deployment begin silently 504ing on multiple API routes. Over the following 8 days the Dispatch orchestrator (Claude) ran a multi-session investigation that produced:

- A "Lambda 10s INIT cap cold-init deadlock" causal narrative built from bisect correlation against the `vercel.json functions` glob, code audit of static SDK imports, dependency graph analysis, bundle composition reads, and module-top instantiation greps.
- A documented FM-001 catalog entry promoting the narrative to "known failure class."
- A multi-day Fly.io migration plan authored on top of the narrative.
- Repeated chat-level Misha corrections ("look at the logs," "have you actually pulled logs?") that the orchestrator treated as something to argue with rather than as a re-classification trigger.

On 2026-05-22 a friend running `vercel logs dpl_EhrE5SC8kPNM94cVTvy5DPyvEh7P --no-follow --since 24h --limit 2000 --json` against the broken deployment found the actual error in ~30 seconds:

```
Unhandled Rejection: Error: You cannot use different slug names for the same
dynamic path ('id' !== 'orgId').
```

The error appeared 1760 times in 2000 log lines on the broken deployment. The root cause was a Next.js App Router dynamic-segment naming conflict (`src/app/api/admin/orgs/[id]/` vs sibling `src/app/api/admin/orgs/[orgId]/`) introduced 2026-05-14 by commit `44b37a6` without removing the pre-existing `[id]` subtree. The fix is a 5-10 minute directory rename. The Fly.io migration would NOT have helped — Next.js would crash the same route tree on any Node.js runtime.

The full case study is at `docs/lessons/2026-05-22-fm-001-misdiagnosis.md`, and the failure class is catalogued as `FM-029` ("Investigation proceeds from inferential evidence without first capturing runtime/error logs from the affected system").

Root-cause-of-the-root-cause analysis: the misdiagnosis was a PROTOCOL failure, not a knowledge gap. The orchestrator knew about `vercel logs`. It knew about runtime log pulls. What it did not have was a durable rule, applied by default in every session, that says: pull the logs FIRST. Chat-level corrections from Misha across multiple sessions did not persist because chat is not the harness's durable rule layer — only files under `~/.claude/rules/` are loaded into every session contextually.

## Decision

Three protocols, all encoded as Pattern-class rules under `~/.claude/rules/`, with discoverability via `~/.claude/CLAUDE.md`'s "Detailed Protocols" list, and operational reinforcement in the `plan-phase-builder` agent prompt:

1. **DIAGNOSTIC-FIRST PROTOCOL** (`~/.claude/rules/diagnosis.md`, new top-section). The FIRST tool call of any production-failure investigation MUST be retrieval of runtime / error logs from the affected system. Inferential evidence (probe behavior, code reading, git history, bisects, dependency analysis, schema reads, configuration diffs) is permitted ONLY AFTER logs have been examined OR after explicit acknowledgment in the response of "logs are inaccessible because X" with a concrete reason. Confidence-sounding diagnoses ("X is caused by Y") without log evidence are prohibited. Per-platform guidance lives in the rule body (Vercel, Fly/Railway/Render/Cloud Run, Sentry/Datadog/Honeycomb, Supabase/RDS, Twilio/Stripe/SendGrid webhooks, Trigger.dev/Inngest queues, self-hosted).

2. **HYPOTHESIS-VS-PROOF LABELING** (`~/.claude/rules/claims.md`, new file). Every causal claim in a status update, report, or session output must be tagged PROVEN (with cited evidence — log line, test result, measurement, file:line citation) or HYPOTHESIZED (with stated refutation criterion). Naked confident phrasing is prohibited. When in doubt, default to HYPOTHESIZED — a wrongly-PROVEN claim poisons subsequent investigation sessions; a wrongly-HYPOTHESIZED claim is harmlessly promotable.

3. **REFUTATION-CRITERIA REQUIREMENT** (`~/.claude/rules/claims.md`, same file). Before authoring an implementation plan on top of a hypothesis, explicitly write the refutation criterion ("Hypothesis Z would be REFUTED by observing [specific observable evidence]") AND look for refuting evidence before committing engineering resources. If no refutation criterion can be identified, declare the diagnosis non-falsifiable and recommend AGAINST the structural fix until additional evidence grounds the causal model.

The three protocols are operationally reinforced by an "Investigation-work mandate" section in `~/.claude/agents/plan-phase-builder.md` that requires dispatched investigation sessions to embed all three clauses in their workflow — first tool call = log pull (or explicit acknowledgment); every claim tagged; structural-fix recommendations carry refutation criteria.

FM-029 (`docs/failure-modes.md`) catalogues the failure class so future sessions grep the catalog with symptom keywords and find the entry. The case study is at `docs/lessons/2026-05-22-fm-001-misdiagnosis.md`.

## Alternatives considered

### Alternative A — Add a PreToolUse hook that detects "investigation session" and forces log-pull as first tool call (rejected)

**Mechanical enforcement.** A PreToolUse hook would intercept the session's first tool call after SessionStart and assert it is a log-retrieval command (vercel logs, Sentry query, etc.). If not, BLOCK and inject "pull logs first" guidance.

**Rejected because:**

- Detection of "this session is investigating a production failure" requires the agent to self-classify the session type from the user prompt. That self-classification is exactly the failure mode chat-level enforcement has: the agent says "this isn't a production-failure investigation, this is a routine task" and the hook lets it proceed without log discipline.
- Even with reliable detection, the SET of legitimate first tool calls is broad (reading SCRATCHPAD, reading the active plan, reading the failing code file to understand structure before pulling logs). A hook that rigidly requires `vercel logs` first would false-positive constantly.
- The mechanism would create exactly the kind of friction `gate-respect.md` worries about — operators reaching for the override, accumulated bypasses eroding the gate.

Pattern enforcement with the operator's interrupt authority as backstop is the correct shape for now. An ADR (this one) locks the choice; if a stable detection signal emerges later (e.g., a SessionStart hook that injects "this is an investigation session" classification at spawn time), a future mechanism can land as an extension.

### Alternative B — Add a Stop hook that scans the transcript for unlabeled causal claims (rejected for v1)

**Mechanical enforcement.** A Stop hook would parse the assistant's final message (and possibly prior messages) for sentences matching a regex of causal-claim shapes ("X is caused by Y," "Y leads to X," "the root cause is Z") and block session-end unless each such claim is followed by PROVEN/HYPOTHESIZED tag within N characters.

**Rejected because:**

- Distinguishing "causal claim" from "descriptive statement" is non-trivial for a regex. False positives would proliferate (the agent describing what it read, the agent quoting a source, the agent summarizing an existing decision).
- The regex would need to handle inline-parenthetical-style ("the slow login is caused by an N+1 (PROVEN: …)") and tagged-block-style ("PROVEN: …") tag placements. Detecting either style mechanically is error-prone.
- Stop hooks already form a saturated chain (8 positions per current settings); adding another reduces signal-to-noise.

The discipline is documented as Pattern. The downstream `claim-reviewer` agent (already in the harness) reviews feature claims in prose before user-facing output ships; it can be extended in a future iteration to enforce PROVEN/HYPOTHESIZED tags. The user's interrupt authority covers the remaining gap.

### Alternative C — Document only, no new rule files (rejected)

The user could be told to ask Claude to "pull logs first" in every investigation session. Rejected because: the case study explicitly documents that Misha gave this corrective input across multiple sessions and it didn't persist. The whole purpose of `~/.claude/rules/` is to make the standing instruction durable. Documentation-only fails the originating use case.

### Alternative D — Put everything in diagnosis.md, no new claims.md (rejected)

Extend diagnosis.md with all three protocols. Rejected because:

- diagnosis.md governs WHEN and WHERE to investigate (full-chain tracing, FM-catalog reflex, "Fix the Class, Not the Instance"). It already covers a wide surface; adding hypothesis-labeling and refutation criteria would dilute its focus.
- claims.md is about HOW TO WRITE about findings — orthogonal to the investigation discipline diagnosis.md governs.
- Separation keeps each rule cohesive and discoverable in the CLAUDE.md Detailed Protocols list as a distinct line.

The chosen split is: diagnosis.md gets the diagnostic-first protocol (where to look first); claims.md gets the labeling + refutation discipline (how to write about findings). The plan-phase-builder Investigation-work mandate references both.

## Consequences

**Enables:**

- Future investigation sessions, by default, pull runtime logs before theorizing. The case study's 8-day misdiagnosis becomes a sub-hour investigation.
- Causal claims in status updates, plan decisions, ADRs, FM entries, and sub-agent returns are mechanically distinguishable as PROVEN vs HYPOTHESIZED. Reviewers (human or agent) can spot unsupported claims at a glance.
- Plans authored on top of hypotheses carry explicit refutation criteria, forcing the agent to do a sub-hour refutation check before committing to multi-day engineering work.
- The `plan-phase-builder` agent treats investigation work as a distinct task class with three named requirements; the orchestrator's dispatch prompts for investigation work can reference the mandate.

**Costs:**

- Adds friction to every status update: the agent must distinguish causal claims from descriptive statements and tag the causal ones. The friction is intentional — it forces explicit reasoning about evidence — but it slows the early phase of investigation.
- Pattern enforcement means the agent can still skip the discipline. The case study itself demonstrates that chat-level corrections did not persist. The user's interrupt authority remains load-bearing. The mitigation is broad: three reinforcing rule files (diagnosis.md, claims.md, plan-phase-builder.md), discoverability in CLAUDE.md's Detailed Protocols, and FM-029 catalog reflex via the existing `grep -in '<symptom>' docs/failure-modes.md` discipline.
- Tagging discipline can become performative — an agent might tag everything PROVEN to satisfy the rule. The defense is that PROVEN requires citation; an unsupported PROVEN claim is detectable by reading the cited evidence.

**Blocks:**

- The unfalsifiable-diagnosis plan pattern: an agent can no longer author a multi-day migration plan on top of a hypothesis without explicitly declaring the refutation criterion and acknowledging that no refuting evidence was sought.
- The naked-confident-claim pattern: every causal claim either cites evidence or carries a refutation criterion.
- The implicit-investigation-skipping pattern: every dispatched investigation session has the mandate visible in its agent prompt; an investigation that skips the log pull is a flagged deviation from the agent's own documented contract.

## Refutation Criterion (this decision)

This decision rests on a causal model: "encoding the protocols in `~/.claude/rules/` files makes future sessions apply them by default." The refutation criterion:

> Decision 035 would be REFUTED by observing a session, AFTER this ADR lands, where the user runs a production-failure investigation and the agent's first tool call is NOT a log pull (and is NOT an acknowledgment of log inaccessibility), AND the agent's claim about root cause is not tagged PROVEN/HYPOTHESIZED, AND the agent does not honor course-correction from the user. If that happens, the rule files are not being loaded, or the agent is overriding them, and the mitigation is mechanical enforcement (Alternative A or B revisited) rather than additional documentation.

The refutation check is run by observing the next 3-5 production-failure investigation sessions and recording whether the protocols held. If the protocols hold across 5+ sessions without user correction, Decision 035 is CONFIRMED at the operator level. If they fail in 1+ sessions, Decision 035 is partially refuted and Alternative A/B is reopened.

This refutation criterion is intentionally observable by the operator without instrumentation. The KIT-6 propagation-engine audit log infrastructure (per `build-doctrine/doctrine/07-knowledge-integration.md`) could eventually formalize this check, but for v1 the operator's direct observation is the primary signal.

## Implementation log

- 2026-05-22: ADR authored as part of `docs/plans/diagnostic-first-protocol-enforcement.md`.
- 2026-05-22: Rule files landed at `adapters/claude-code/rules/diagnosis.md` (extension), `adapters/claude-code/rules/claims.md` (new), `adapters/claude-code/agents/plan-phase-builder.md` (Investigation-work mandate), `adapters/claude-code/CLAUDE.md` (Detailed Protocols entries refreshed).
- 2026-05-22: FM-029 catalogued in `docs/failure-modes.md`.
- 2026-05-22: Lessons doc at `docs/lessons/2026-05-22-fm-001-misdiagnosis.md`.
- 2026-05-22: Synced to live mirror at `~/.claude/`; verified byte-identical via `diff -q`.
- 2026-05-22: Merged to master per pre-customer auto-merge directive.

Subsequent refutation-check entries (after observing real-world investigation sessions) will be appended below this line.
