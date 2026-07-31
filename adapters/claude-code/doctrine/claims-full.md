# Claims — Hypothesis-vs-Proof Labeling and Refutation Criteria

**Classification:** Pattern (self-applied claim discipline). No hook mechanically classifies a sentence as "causal claim" vs "descriptive statement" — that distinction is a Pattern the agent applies. The Stop-chain narrative-integrity hooks (`transcript-lie-detector.sh`, `imperative-evidence-linker.sh`, `goal-coverage-on-stop.sh`) close adjacent gaps (deferred-work narration, imperative-coverage, first-message goal coverage) but do NOT enforce the per-claim PROVEN/HYPOTHESIZED tag. This rule binds the agent and is backed by the operator's interrupt authority.

**Originating context.** `docs/lessons/2026-05-22-fm-001-misdiagnosis.md` — 8+ days of confident-sounding causal claims about a "Lambda 10s INIT cap" deadlock built on bisect correlation, never labeled as hypotheses, never paired with refutation criteria. The actual error message was in runtime logs the whole time. The corollary rule on pulling logs first lives in `~/.claude/rules/diagnosis.md` (DIAGNOSTIC-FIRST PROTOCOL); this file is the per-claim labeling and refutation discipline that pairs with it.

## HYPOTHESIS-VS-PROOF LABELING

**Every causal claim in a status update, report, or session output must be tagged as either:**

- **PROVEN** — cite the specific evidence (log line, test result, measurement, response body, query output, screenshot, file:line citation, etc.). Example: "auth/session is hanging (PROVEN: 5/5 curl probes returned 000 after 30s timeout, runtime logs show route-init crash with stack trace at `node_modules/next/dist/.../server.runtime.prod.js:24:11422` — full body in `/tmp/diag/logs.jsonl:1142`)".
- **HYPOTHESIZED** — state the assumption AND the refutation criterion. Example: "this MAY be the Lambda 10s INIT cap (HYPOTHESIZED: bisect correlates with vercel.json glob addition; would be REFUTED by absence of `INIT_REPORT` lines in runtime logs over the failure window)".

**Naked confident phrasing without the tag is PROHIBITED.** If you don't know whether something is proven or hypothesized, default to HYPOTHESIZED + cite the gap.

This applies to:

- Reports written by code sessions (completion reports, session summaries, evidence blocks, plan Decisions Log entries, FM-catalog Recovery fields).
- Messages the orchestrator sends to the user (status updates, mid-session check-ins, conclusion-of-work summaries, the `Decision`/`Implementation log` sections of discovery files).
- Sub-agent return summaries to the orchestrator (especially `plan-phase-builder` builder verdicts, `task-verifier` verdicts, `plan-evidence-reviewer` findings).
- Any communication where a future reader could mistake a guess for a confirmed fact.

### What counts as a causal claim

A causal claim is any statement asserting that one thing happened BECAUSE OF another, or that one thing WILL happen because of another. Phrases that signal a causal claim:

- "The X is caused by Y" / "Y causes X"
- "X happened because Y"
- "Y leads to X" / "Y produces X"
- "The reason X is broken is Y"
- "If we fix Y, X will work"
- "X is failing due to Y"
- "The root cause is Y"
- "Y is responsible for X"
- Naked completed-state assertions when describing system behavior: "X works because of Y" / "X handles Y" / "Y prevents X"
- Recommendations whose justification is a causal model: "we should do Y because X depends on it"

### What is NOT a causal claim (descriptive statements that don't need tags)

Descriptive statements about what was done or what was read do NOT need tags:

- "I read `src/app/api/auth/route.ts` and confirmed the handler signature is unchanged" — descriptive, no causal claim.
- "I ran `npm run typecheck` and it returned exit 0" — descriptive, no causal claim.
- "The plan declares `Status: ACTIVE`" — descriptive.

The rule binds claims about WHY things happen, not claims about WHAT was observed.

### How to tag in a status update

Two styles, both valid. Pick whichever fits the surrounding prose.

**Inline-parenthetical style** (for compact updates):

```
The 504 on /api/alerts is the Next.js route-tree-build crash (PROVEN: runtime
logs from dpl_EhrE5SC8kPNM94cVTvy5DPyvEh7P show 1760 `Unhandled Rejection:
... slug names ...` lines per 2000-line window; same error appears on every
deployment back to the 2026-05-14 commit that introduced [orgId]). The
remaining 200s on /api/health are not yet explained (HYPOTHESIZED: the
/api/health route lands in a Lambda partition that excludes the conflicting
subtree, masking the crash; REFUTED by /api/health logs showing the same
slug-conflict trace).
```

**Tagged-block style** (for longer reports or evidence sections):

```
PROVEN
- /api/alerts 504s are the Next.js slug-conflict crash. Evidence:
  vercel logs dpl_EhrE5... shows 1760/2000 lines with `Unhandled Rejection: ...`
- The conflict has been in master since 2026-05-14. Evidence: git blame on
  src/app/api/admin/orgs/[orgId]/ shows commit 44b37a6.

HYPOTHESIZED
- The vercel.json glob acts as a band-aid by changing Lambda partitioning.
  Refutation criterion: testing a deployment with the glob removed AND a
  curl against /api/alerts would either still 504 (refutes — partitioning
  isn't the masking mechanism) or succeed (corroborates — the partition
  shifts the conflict away from probed routes).
```

### When the agent forgets to tag

If you catch yourself writing "X is caused by Y" without a tag, stop and add one. If you cannot decide PROVEN vs HYPOTHESIZED, default to HYPOTHESIZED with a refutation criterion — that is the safer fallback. A claim wrongly tagged HYPOTHESIZED can be promoted to PROVEN on the next evidence pass; a claim wrongly tagged PROVEN poisons every downstream session that reads it.

If the user pushes back on an untagged claim ("are you sure?" / "what's your evidence?" / "look at the logs"), that is the highest-signal moment. The correct response is to re-classify the claim immediately, not to defend the original phrasing. Friend-saying-"look at the logs" was the load-bearing intervention in the FM-001 case; the orchestrator's job is to receive that signal as a re-classification trigger, not to argue with it.

## REFUTATION-CRITERIA REQUIREMENT

**Before authoring an implementation plan on top of a hypothesis** (e.g., "fix X by doing Y because we believe Z is the cause"), **you must explicitly write the refutation criterion:**

> Hypothesis Z would be REFUTED by observing [specific observable evidence].

**Then you must look for that refuting evidence BEFORE committing engineering resources to the plan.**

If you cannot identify a refutation criterion, the hypothesis is not falsifiable and the plan is built on speculation. The required action is to:

1. Surface the unfalsifiability honestly: the plan's Decisions Log carries a line `Refutation criterion: none identified — plan is speculative-prior-to-evidence`.
2. EITHER pause and search for additional evidence that could ground the hypothesis, OR proceed with explicit acknowledgment that the plan may be wasted work.
3. If proceeding, declare a maximum cost ceiling (hours, $, lines of code) past which the plan must produce confirming evidence or be abandoned.

### What a good refutation criterion looks like

- **Specific.** Names a particular observable thing — a log line, a status code, a file path, a measurement, a query result, a feature flag value.
- **Closeable in less time than the plan itself.** A refutation check that takes longer than the plan defeats the discipline; pick a cheaper check.
- **Causally tight to the hypothesis.** If the hypothesis is "X is caused by Y," the refutation must invalidate the causal link — not merely show that Y exists or that X exists. Both can be true while not being causally linked.
- **Observable by the agent before plan execution begins.** A refutation that requires data only available after the plan ships is not a pre-plan refutation.

### Examples

**Good:**

> Hypothesis: the slow login is caused by an N+1 query in the org-membership lookup. REFUTED by: enabling SQL log on staging, performing one login, and observing fewer than 5 queries against the `org_members` table per login attempt.

**Bad (too vague):**

> Hypothesis: the slow login is caused by a database issue. REFUTED by: investigating the database. (No specific observable; "investigating" is not a check.)

**Bad (too expensive):**

> Hypothesis: the cold-init bundle is too large for Lambda. REFUTED by: implementing the full bundle-size reduction plan and measuring whether init time decreases. (The refutation requires executing the plan — defeats the discipline.)

**Good (replacement for the bad-too-expensive case):**

> Hypothesis: the cold-init bundle is too large for Lambda. REFUTED by: pulling `vercel logs` for the affected deployment and either (a) observing zero `INIT_REPORT` lines with status=timeout (refutes — the bundle size is not the bottleneck), or (b) observing the timeouts but with init durations under the documented 10s cap (refutes — the cap is not the trigger).

### When refutation evidence contradicts the hypothesis

If the refutation criterion produces refuting evidence, the hypothesis is wrong. Do NOT:

- Quietly adjust the hypothesis to dodge the refutation ("well, the criterion fired, but actually I meant a slightly different version of the hypothesis...").
- Continue with the plan and hope the refutation was noise.
- Defer the refutation indefinitely as "interesting, will investigate later."

Do:

- Update the Decisions Log: "Hypothesis Z refuted by [evidence]; plan paused; investigation reopens."
- Surface the refutation to the user with the original confidence-sounding claim CLEARLY downgraded.
- Pull more runtime evidence per the upstream diagnostic-first protocol (`~/.claude/rules/diagnosis.md`).

### Where refutation criteria appear in artifacts

- **Plan files** with `Mode: design` should carry a `Refutation criteria` field per hypothesis in Section 10 (Decision records & runbook). Plans in `Mode: code` should carry refutation criteria inline in their Decisions Log entries where applicable.
- **ADRs** (`docs/decisions/NNN-*.md`) should include a Refutation Criterion field when the decision rests on a causal model that could be wrong.
- **Discovery files** (`docs/discoveries/YYYY-MM-DD-*.md`) of type `architectural-learning`, `performance`, or `failure-mode` should include the refutation criterion in their Decision section.
- **Session-level recommendations** (status updates to the user) should include refutation criteria when proposing a plan over 1 hour of work or any irreversible operation.

## Composition with the rest of the harness

This rule pairs with `~/.claude/rules/diagnosis.md` (DIAGNOSTIC-FIRST PROTOCOL — pull runtime logs before theorizing). The diagnostic-first protocol governs WHERE evidence comes from; this rule governs HOW claims about that evidence are written.

The rule also composes with:

- `~/.claude/rules/friction-reflexion.md` — when the agent's own approach is producing untagged confident-sounding claims, that is friction the agent should surface as a discussion item.
- `~/.claude/rules/interactive-process-fidelity.md` — when the user pushes back on an untagged claim, that pushback is an authority touchpoint, not a structural detail; the agent must reclassify the claim, not defend the original phrasing.
- `~/.claude/rules/discovery-protocol.md` — when a refutation surfaces a new realization, that goes through the discovery-protocol's auto-apply-if-reversible vs pause-if-irreversible flow.
- `~/.claude/agents/claim-reviewer.md` — the residual-risk agent that adversarially checks feature claims in prose before they reach the user. The PROVEN/HYPOTHESIZED tags are what claim-reviewer reads to determine whether a claim is supported.

## Cross-references

- `~/.claude/rules/diagnosis.md` — DIAGNOSTIC-FIRST PROTOCOL: pull runtime logs before theorizing.
- `~/.claude/rules/friction-reflexion.md` — surface friction (including the friction of catching oneself writing untagged claims) as a discussion item.
- `~/.claude/rules/interactive-process-fidelity.md` — user pushback on an untagged claim is an authority touchpoint.
- `~/.claude/agents/claim-reviewer.md` — adversarial review of feature claims in prose.
- `~/.claude/agents/plan-phase-builder.md` — builder agents inherit the labeling discipline in their return summaries.
- `docs/decisions/035-diagnostic-first-protocol.md` — ADR locking both diagnostic-first and claims-labeling.
- `docs/failure-modes.md` FM-029 — "Investigation proceeds from inferential evidence without first capturing runtime/error logs."
- `docs/lessons/2026-05-22-fm-001-misdiagnosis.md` — the originating case study.

## Enforcement

| Layer | What it enforces | File |
|---|---|---|
| Rule (this doc) | Every causal claim tagged PROVEN/HYPOTHESIZED; every hypothesis backed by a refutation criterion; plans on hypotheses look for refuting evidence first | `adapters/claude-code/rules/claims.md` |
| Sibling rule (Mechanism, partial) | `claim-reviewer` agent reads claims and verifies citations before user-facing prose ships | `~/.claude/agents/claim-reviewer.md` (self-invoked; residual gap acknowledged in vaporware-prevention.md) |
| Sibling Stop hooks (Mechanism, partial) | `transcript-lie-detector.sh` + `imperative-evidence-linker.sh` + `goal-coverage-on-stop.sh` catch adjacent narrative-integrity failures | various, listed in `~/.claude/rules/vaporware-prevention.md` |
| User authority | The operator retains interrupt authority when an untagged causal claim slips through | (Pattern) |

The rule is Pattern-class. Mechanical detection of "this sentence is an untagged causal claim" would require an LLM-grade pass over every assistant message at runtime, which is not currently part of the harness boot path. The discipline relies on the agent self-applying and the user catching slips.

## Scope

This rule applies in every project whose Claude Code installation has this rule file present at `~/.claude/rules/claims.md`. The rule is loaded contextually by the harness; no opt-in or hook wiring is required to make the rule active. The labeling discipline binds every agent in every session mode — interactive local, parallel local, cloud-remote / Dispatch orchestrator, scheduled, and agent-team — because untagged causal claims surface in all of them and the case study that motivated this rule was authored by the Dispatch orchestrator specifically.
