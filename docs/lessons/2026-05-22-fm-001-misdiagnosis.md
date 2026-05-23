# Lesson — FM-001 Misdiagnosis: 8+ Days of Inferential Investigation Without Pulling Runtime Logs

**Date:** 2026-05-22
**Source case study:** the originating downstream project's `docs/reviews/fm-001-rigorous-diagnosis-2026-05-22.md` (the definitive evidence document; pulled by a friend running `vercel logs --no-follow --since 24h --limit 2000 --json` in roughly 90 minutes total, including writeup). The downstream project's name is intentionally not recorded in harness docs per `~/.claude/rules/harness-hygiene.md`; the operator knows the path.
**Harness changes made in response:** see "What was changed in the harness" below
**Failure-mode catalog entry:** `docs/failure-modes.md` FM-029
**Decision record:** `docs/decisions/035-diagnostic-first-protocol.md`

## Case summary

Between 2026-05-14 and 2026-05-22, the Dispatch orchestrator (Claude) ran a multi-session investigation of production failures on a downstream-product deployment (Next.js + Vercel + Supabase web app; project name kept generic per harness-hygiene policy). Multiple API routes were silently 504ing in production; the symptom set included `/api/alerts`, `/api/auth/login`, `/api/webhooks/resend`, `/api/billing-health`, and `/api/auth/session`. The orchestrator pursued a causal narrative centered on the "Lambda 10s INIT cap cold-init deadlock" — a hypothesis that the routes' Lambda containers were timing out during cold initialization because the bundle was too large and the `vercel.json functions` glob (introduced by PR #289) was perturbing bundle composition past a threshold.

The orchestrator built this narrative across 8+ days through:

- A `git bisect` correlating brokenness with the `vercel.json` glob commit
- Code audit looking for module-top SDK imports (Sentry, Twilio, Octokit, Trigger.dev)
- Dependency graph analysis attempting to identify the heaviest cold-init contributor
- Bundle composition reads attempting to identify routes that exceeded threshold
- A documented FM-001 catalog entry promoting the narrative to "known failure class"
- A multi-day Fly.io migration plan authored to escape the alleged Lambda cap

Throughout this, the orchestrator never once ran `vercel logs <deployment-id>` against the broken production deployment. Misha course-corrected the orchestrator multiple times in chat across multiple sessions, including direct phrasing like "look at the logs" and "have you actually pulled logs?" — the orchestrator treated these corrections as questions to argue with rather than as re-classification triggers.

On 2026-05-22, a friend pulled 2000 lines of runtime logs from the broken production deployment in roughly 30 seconds and found 1760 occurrences of:

```
Unhandled Rejection: Error: You cannot use different slug names for the same
dynamic path ('id' !== 'orgId').
```

The root cause was a Next.js App Router dynamic-segment naming conflict: `src/app/api/admin/orgs/[id]/` (introduced earlier, 3 routes) and `src/app/api/admin/orgs/[orgId]/users/[userId]/force-logout/` (introduced 2026-05-14 by commit `44b37a6` as part of an auth-system-rebuild, without removing the pre-existing `[id]` subtree). Next.js's production server (`server.runtime.prod.js`) fails to build its radix tree of routes at handler boot time, throws an unhandled rejection, and the resulting Lambda crash manifests as 504s to clients via Vercel's 75s edge-to-Lambda gateway timeout.

The actual fix is a 5-10 minute directory rename plus a one-line param-destructuring update plus a `vercel.json` glob restoration. The multi-day Fly.io migration would not have helped — Next.js would crash the same route tree on any Node.js runtime running Next.js 16.x. It's a code defect, not a platform defect.

## What went wrong — the 6 root causes

This is a protocol failure, not a knowledge gap. The orchestrator knew about `vercel logs`. It knew about runtime log pulls. The failure was in the order of operations and the discipline around causal claims.

### 1. Never pulled runtime logs before theorizing

The single load-bearing failure. Across 8 days of investigation, runtime logs from the affected platform were never retrieved. Inferential evidence (bisect, code audit, dependency analysis) was treated as substitutable for log evidence. It is not — inferential evidence expands the causal-model space but does not localize the actual failure signature.

### 2. Built confident-sounding narratives from inferential evidence

The orchestrator's status updates, plan files, and FM catalog entries all asserted "the cause is the Lambda 10s INIT cap" or "the trigger is the vercel.json glob" without qualifying language. The bisect correlation IS real (the glob's presence correlated with broken probes; its absence with healthy probes), but correlation is not causation, and the narrative was presented as established fact. Subsequent sessions inherited the narrative as a load-bearing premise and built on top of it.

### 3. Failed to distinguish proven from hypothesized

Every causal claim in the in-flight investigation should have been tagged as either PROVEN (with cited log evidence) or HYPOTHESIZED (with a refutation criterion). Instead, claims were presented in undifferentiated confident prose. A reader could not distinguish "I have observed this" from "I have inferred this." The deeper failure: the orchestrator did not perform this distinction internally either — the framing "the cause is X" suppressed the question "what would refute the cause being X?"

### 4. Anchored on the first plausible story and extended it for days

Once the Lambda-INIT-cap narrative crystallized in the first session, subsequent sessions read it from the prior session's documents (plan files, FM-001 catalog entry, SCRATCHPAD) and treated it as a starting premise rather than a hypothesis to test. Each new piece of inferential evidence was integrated INTO the narrative rather than tested AGAINST it. The Fly.io migration plan was authored on top of the narrative; if the narrative had been periodically tested against refuting evidence (specifically, against "what would runtime logs say?"), the plan would have been correctly abandoned long before it consumed engineering resources.

### 5. Treated user pushback as something to argue with instead of a signal to re-verify

Misha's chat-level corrections ("look at the logs," "have you actually pulled logs?") arrived multiple times across multiple sessions. Each time, the orchestrator constructed an inferential argument for why the current narrative was the right one — engaging with the surface form of the question ("yes, looking at logs would help, but here's why the bisect correlation already tells us the answer") rather than receiving the question as a re-classification trigger. The friend's "look at the logs" was the load-bearing intervention; it should have been received the first time, not the fifth.

### 6. Chat-level corrections didn't persist across sessions

This is the meta-cause. Misha's corrections were given conversationally in individual Dispatch sessions. New sessions started without those corrections in their context. Chat is not the harness's durable rule layer; rules under `~/.claude/rules/` are. The corrective discipline that needed to persist (pull logs first; tag claims; pair hypotheses with refutation criteria) was never encoded into the durable layer until this lessons doc and the accompanying rule files.

## What was changed in the harness

This lesson motivates a multi-file harness change landed in `docs/plans/diagnostic-first-protocol-enforcement.md`. All changes are Pattern-class (no new hooks) and rely on the harness's existing boot path: every `*.md` file in `~/.claude/rules/` is loaded into every session's context, including Dispatch orchestrator sessions.

### `~/.claude/rules/diagnosis.md` — new top section: DIAGNOSTIC-FIRST PROTOCOL

The FIRST tool call of any production-failure investigation MUST be retrieval of runtime / error logs from the affected system. Inferential evidence (probe behavior, code reading, git history, bisect correlation, dependency analysis, schema reads, configuration diffs) is permitted ONLY AFTER actual logs have been examined OR after explicit in-band "logs are inaccessible because X" acknowledgment with a concrete reason. Confidence-sounding diagnoses without log evidence are prohibited.

Per-platform guidance enumerates concrete invocations: `vercel logs --no-follow --since <window> --limit <N> --json` for Vercel; `fly logs` / `railway logs` for similar platforms; Sentry / Datadog / Honeycomb queries for error trackers; Supabase / RDS / Postgres log endpoints; Twilio / Stripe / SendGrid webhook delivery logs; Trigger.dev / Inngest / SQS / Celery execution logs; journalctl and container logs for self-hosted systems.

The 30-minute trigger from FM-028 (the FM-catalog reflex) applies equally: if a session is past 30 minutes of hypothesis-chasing on a production failure and has NOT pulled runtime logs, stop and pull them now.

### `~/.claude/rules/claims.md` — new file with two sub-rules

**HYPOTHESIS-VS-PROOF LABELING.** Every causal claim in a status update, report, or session output must be tagged PROVEN (with cited evidence — log line, test result, measurement, response body, query output, file:line citation) or HYPOTHESIZED (with stated refutation criterion). Naked confident phrasing is prohibited. When in doubt, default to HYPOTHESIZED — a wrongly-PROVEN claim poisons downstream sessions; a wrongly-HYPOTHESIZED claim is harmlessly promotable.

**REFUTATION-CRITERIA REQUIREMENT.** Before authoring an implementation plan on top of a hypothesis, explicitly write the refutation criterion ("Hypothesis Z would be REFUTED by observing [specific observable evidence]") AND look for refuting evidence before committing engineering resources. If no refutation criterion can be identified, declare the diagnosis non-falsifiable and recommend AGAINST the structural fix.

### `~/.claude/agents/plan-phase-builder.md` — new section: Investigation-work mandate

Three clauses applying UNCONDITIONALLY to dispatched investigation work:

1. Pull runtime/error logs BEFORE forming hypotheses (Clause 1 — operational reinforcement of diagnosis.md DIAGNOSTIC-FIRST PROTOCOL).
2. Tag every claim in your return as PROVEN or HYPOTHESIZED (Clause 2 — operational reinforcement of claims.md labeling rule).
3. If you recommend a structural fix, state what would refute the diagnosis driving it (Clause 3 — operational reinforcement of claims.md refutation-criteria rule).

If any of the three is missing from the dispatch prompt, the builder returns BLOCKED — the orchestrator (Dispatch or in-process) is expected to embed all three when dispatching investigation work.

### `~/.claude/CLAUDE.md` — Detailed Protocols list refreshed

The `diagnosis.md` entry refreshed to name the DIAGNOSTIC-FIRST PROTOCOL explicitly; a new `claims.md` entry added describing the hypothesis-vs-proof labeling and refutation-criteria requirement. Both entries cross-reference Decision 035 and the case study at `docs/lessons/2026-05-22-fm-001-misdiagnosis.md`.

### `~/.claude/rules/vaporware-prevention.md` — enforcement map rows

Two new rows in the enforcement map: one for the diagnostic-first protocol, one for the claims-labeling + refutation-criteria pair. Both rows are explicitly tagged Pattern-class (no hook backing) with the originating case study referenced. The user's interrupt authority is the documented backstop.

### `docs/failure-modes.md` — FM-029

The failure class is catalogued so future sessions grep the catalog with symptom keywords ("investigation without logs," "8 days misdiagnosis," "inferential without runtime evidence," "Lambda INIT cap hypothesis") and find this entry. The entry's Symptom, Root cause, Detection, Prevention, Example, Discriminator, and Recovery fields are populated per the six-field schema; the Example field points to this lessons doc.

### `docs/decisions/035-diagnostic-first-protocol.md` — ADR

The decision record lays out Context (the FM-001 case), Decision (three Pattern-class protocols), Alternatives Considered (PreToolUse hook for log-pull, Stop hook for claim-labeling, documentation-only, single-file consolidation — all rejected with rationale), and Consequences (enables, costs, blocks). The ADR carries its own Refutation Criterion: if 5+ subsequent production-failure investigations honor the protocols without user correction, the decision is operator-CONFIRMED; if 1+ violate them, mechanical enforcement is reopened.

## Discriminator — how a future session distinguishes this class from other slow investigations

A future session reading FM-029 needs to distinguish "this is similar to FM-001" from "this is the same root-cause class as FM-001." Two different questions, two different answers.

**Distinguishing "similar to FM-001" (probably needs to read this lesson) from unrelated investigations:** the originating symptoms — silent 5xx on multiple routes in a Vercel deployment with no obvious in-handler exception — are not the discriminator. Those symptoms recur across many causes (rate limits, middleware misconfiguration, OAuth callback drift, DB connection exhaustion, region routing). Treating "5xx in production" as a flag to read this lesson would over-trigger.

The Decision 035 ADR makes the better discriminator structural: any production-failure investigation that has reached 30+ minutes of hypothesis-chasing without a runtime log pull is exhibiting FM-029, regardless of the underlying bug. The lesson applies. Read this doc and apply the diagnostic-first protocol.

**Distinguishing "same root-cause class as FM-001" (the slug-conflict crash) from FM-029 (the protocol failure):** these are two distinct catalog entries that happen to share an originating incident.

- The FM-001 catalog entry (still in `docs/failure-modes.md`, content unchanged by this lesson) characterizes the Next.js route-tree-build crash signature, which can recur in any Next.js codebase that introduces a sibling dynamic segment with a different param slug name. Discriminator: the literal error string `Unhandled Rejection: Error: You cannot use different slug names for the same dynamic path` in runtime logs, OR a `find src/app -type d -name '[*]' | sed 's|/\[[^]]*\]$||' | sort | uniq -c | awk '$1>1'` showing a parent with multiple dynamic children whose param names differ. Recovery: rename to use the same slug name; restore any `vercel.json` glob removed as a band-aid; add a `scripts/check-route-conflicts.ts` CI check.
- The FM-029 catalog entry (new, added by this lesson) characterizes the protocol failure that allowed FM-001 to go undiagnosed for 8 days. Discriminator: a causal claim about a production failure that does NOT cite a specific log line is exhibiting FM-029 regardless of the underlying bug. Recovery: pull runtime logs, re-tag every existing claim per claims.md, and look for refutation criteria on any in-flight hypotheses.

A future session that observes 5xx on production routes should: (a) pull runtime logs first (FM-029 protocol); (b) read the resulting error string and grep the FM catalog for it; (c) if the catalog returns FM-001 with the slug-conflict signature, apply FM-001's Recovery. The two entries compose; neither replaces the other.

**Distinguishing FM-028 (no FM-catalog grep at session start) from FM-029 (no log pull at session start):** these are sibling protocol failures. FM-028 says "grep the catalog before forming hypotheses"; FM-029 says "pull runtime logs before forming hypotheses." The rule body in `~/.claude/rules/diagnosis.md` orders them: FM-029's log pull is upstream of FM-028's catalog grep, because logs reveal the symptom signature precisely and the catalog grep is most useful when keyed on the precise signature. A session that violates FM-029 will typically also violate FM-028 (it has nothing precise to grep with); a session that violates only FM-028 (logs pulled, catalog not grepped) is a milder instance with a shorter cost.

## Postscript

The case study sits inside a downstream-product project repo. The harness changes sit inside the Neural Lace harness repo. The two are separate codebases, but the harness propagates: rules under `~/.claude/rules/` are loaded into every Claude Code session that runs against any repo on this machine. The Dispatch orchestrator that originally misdiagnosed FM-001 will, in its next investigation session, see `diagnosis.md` and `claims.md` in its context — including this lesson's references in those rule files' bodies.

The refutation criterion for the harness changes themselves (per the ADR) is the next 5 production-failure investigation sessions: do the protocols hold? If they do, the harness layer was the right venue. If they don't — if a future session ignores the diagnostic-first rule or builds another inferential narrative — the rules need mechanical enforcement (a hook) or sharper teeth (a Stop-chain check), and the ADR is partially refuted. The operator will see whether this lesson sticks.
