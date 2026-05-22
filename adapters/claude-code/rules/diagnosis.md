# Diagnosis Before Fixing

**Before proposing any fix, read the full stack that influences the symptom.**

**Exhaustive by default.** When the user reports any problem, trace the entire chain: user action → frontend → API → backend → external services → response. Check every step. Report ALL issues in a single diagnosis. Assume multiple problems until proven otherwise.

## DIAGNOSTIC-FIRST PROTOCOL — Pull Runtime Logs Before Theorizing

**This is the FIRST tool call of any production-failure investigation. It is upstream of every other diagnostic step in this rule, including the failure-mode catalog grep below.**

When investigating a production failure (anything where a deployed system is misbehaving — a 504/5xx, a hang, a silent failure, a wrong output, a regression that customers can observe), the FIRST tool call MUST be retrieval of runtime / error logs from the affected system. Concretely, by class:

- **Web app on Vercel:** `vercel logs <deployment-id> --no-follow --since <window> --limit <N> --json` (or `vercel logs <project>` for the current production deployment). Pull at least 1000–2000 lines covering the time window of the reported failure.
- **Web app on Fly.io / Railway / Render / Cloud Run / Lambda:** the platform's runtime/function log API (`fly logs`, `railway logs`, etc.).
- **API or service with Sentry / Datadog / Honeycomb:** query the error-tracker for actual error messages, stack traces, and event volumes in the failure window. Don't trust the dashboard summary — open the full error body.
- **Database (Postgres / Supabase / RDS):** the platform's slow-query log, error log, or audit log. For Supabase: `supabase logs --project-ref <ref> --type postgres` or the dashboard logs page.
- **External integration (Twilio / Stripe / SendGrid / GitHub webhook / OAuth provider):** the provider's webhook delivery log, event log, or audit log. These are usually accessible via the provider's dashboard or API.
- **Background job / queue (Trigger.dev / Inngest / SQS / Celery):** the job runner's execution log including failed-task error bodies.
- **Self-hosted / on-prem:** journalctl, container logs, application log files at their canonical paths.

**Inferential evidence is PERMITTED ONLY AFTER actual logs have been examined OR after explicit acknowledgment in the response of "logs are inaccessible because X" with a concrete reason.** "Logs are hard to access" is not a concrete reason. Concrete reasons look like: "the deployment ID is unknown and the project's run history is gated behind SSO I don't have," "the platform's log retention is 1h and the failure was 6h ago," "the production environment uses a self-hosted log shipper that requires VPN access not available in this session."

Inferential evidence includes: probe behavior (curl returning 504 with no body), code reading, git history, bisect correlation, dependency graph analysis, build manifest inspection, schema reads, configuration diffs. All of these are useful. None of them is a substitute for the actual error message the system emitted at the moment of failure.

**Confidence-sounding diagnoses ("the X is caused by Y") without log evidence are PROHIBITED.** They create false certainty that propagates through subsequent investigation sessions. Even when the inferential evidence looks overwhelming, treat the diagnosis as `HYPOTHESIZED` per `~/.claude/rules/claims.md` until logs corroborate. The labeling discipline is in claims.md; the upstream pull-logs-first discipline is here.

**Case study — the originating downstream project's `docs/reviews/fm-001-rigorous-diagnosis-2026-05-22.md`** (and the harness-side recap at `docs/lessons/2026-05-22-fm-001-misdiagnosis.md`) documents 8+ days of misdiagnosis caused by violating this rule. The orchestrator chased a "Lambda 10s INIT cap cold-init deadlock" hypothesis through bisect + code reading + dependency analysis — building a multi-day Fly.io migration plan on top — without ever pulling Vercel runtime logs. The actual error (`You cannot use different slug names for the same dynamic path ('id' !== 'orgId')`) was sitting in `vercel logs` the whole time, appearing 1760 times in 2000 lines on the broken deployment. A friend running `vercel logs --no-follow --since 24h --limit 2000 --json` found it in ~30 seconds. The class is catalogued at FM-029.

**Concrete examples — the same failure shape across contexts:**

- **Web app reporting 5xx.** Don't bisect commits, don't theorize about middleware. First call: pull the function's runtime logs at the failure window. Read the actual exception body.
- **API returning wrong data.** Don't trace the code path from memory. First call: query Sentry / the equivalent error-tracker for any error in the handler's recent window. Then read the SQL log if a DB is involved.
- **Customer reports "the feature stopped working yesterday."** Don't read PRs from yesterday looking for the regression. First call: pull error-tracker events for the route from the failure window; if zero errors are recorded, pull request logs and look at the response shape; only THEN start theorizing about what changed.
- **Webhook from third-party seems to drop events.** Don't audit your own handler first. First call: the provider's webhook delivery dashboard — it will say "delivery failed, response was 504 in 5.2s" and you immediately know whether the problem is your handler timing out vs the provider not sending.
- **Cron job didn't fire.** Don't audit the cron-schedule code. First call: the platform's scheduled-task execution log — it will say whether the job was triggered, whether it ran, what its exit code was.

In every case, the inferential evidence is downstream of the log evidence. Build the inferential picture WITH the log message in hand; do not build it BEFORE.

**Distinguish this rule from the FM-catalog reflex below.** Logs reveal the symptom signature precisely. The FM-catalog grep then keys on that precise signature. The two compose in this order:

1. Pull runtime logs → observe the actual error string / status code distribution / timing pattern (THIS rule).
2. Grep `docs/failure-modes.md` with the precise keywords from the observed log signature (the next section below).
3. If a `Discriminator` confirms a match, apply the `Recovery`. If no match, proceed to "## Process" with logs in hand.

Running step 2 before step 1 means grepping with approximations of the symptom rather than the symptom itself — and approximations miss matches. The 30-min trigger encoded in the FM-catalog reflex below ("when you notice you are more than ~30 minutes into hypothesis-chasing and have NOT run this grep, stop and run it now") applies equally to this rule: if you are more than 30 minutes into hypothesis-chasing on a production failure and you have NOT pulled runtime logs, stop and pull them now. The case-study session burned 8 days exactly because this trigger was never honored.

**Cross-references:** `~/.claude/rules/claims.md` (hypothesis-vs-proof labeling + refutation criteria — the per-claim discipline that pairs with this per-investigation discipline); `docs/lessons/2026-05-22-fm-001-misdiagnosis.md` (the full case study including the 6 root causes the orchestrator exhibited); `docs/decisions/035-diagnostic-first-protocol.md` (the ADR locking the protocol).

## Check the Failure-Mode Catalog Before Forming a Hypothesis

**This is the FIRST step of any investigation / debug / root-cause session — before mapping the chain, before forming a single hypothesis.**

Run `grep -in '<keywords from the reported symptom>' docs/failure-modes.md` (the project's Failure-Mode catalog — `FM` = Failure Mode). For each match, read its `Symptom`, `Discriminator`, and `Recovery` fields:

- **If a `Discriminator` confirms the match:** you have likely identified a *known class*. Apply its `Recovery` steps. You may have just turned a multi-hour investigation into a multi-minute one — this is the entire reason the catalog exists.
- **If matches exist but their `Discriminator`s rule them out:** note which known classes you have *excluded* (that is itself diagnostic signal) and proceed to "## Process".
- **If no matches, or `docs/failure-modes.md` does not exist in this project:** proceed to "## Process". When you find the root cause, the "## After Every Failure: Encode the Fix" step below requires you to add the new class so the *next* session pays one cost, not N. (If the project has no catalog at all, bootstrapping one is itself the encode-the-fix step — see `docs/conventions/failure-mode-catalogs.md`.)

This is the investigation-first reflex. The catalog was historically consulted only at *encode* time; consulting it *first* is what closes the failure class where the same root cause is re-diagnosed from scratch at full cost in session after session (catalogued as FM-028 in the harness's own `docs/failure-modes.md`). Doctrine-that-relies-on-memory drifts under exactly the context pressure — a long, frustrating investigation — where this reflex matters most: when you notice you are more than ~30 minutes into hypothesis-chasing and have NOT run this grep, stop and run it now. The cross-project standard this implements is `docs/conventions/failure-mode-catalogs.md` (Decision 033); a SessionStart hook to surface candidate matches automatically is proposed at `docs/proposals/fm-catalog-auto-search-harness-integration.md`.

## Process
1. **Map the full chain.** "Save fails" → read form + API route + response consumer together.
2. **Trace a concrete example end-to-end.** Walk a real value through each layer.
3. **Check what's hiding behind the first error.** "If I fix this, what does the next step do?"
4. **List all bugs across the full chain**, fix them all in one commit.

**Validation:** TypeScript compiling is NOT validation. Trace the full chain with a concrete value, OR run the code and observe the correct outcome.

## When a Tool or Command Fails

Apply the same exhaustive principle to operational failures (auth errors, push failures, API timeouts):

1. **Read the error message.** Diagnose root cause before retrying blindly.
2. **Try at least 2 alternative approaches** before accepting failure — but only reversible, non-destructive ones (switch accounts, fix a URL, refresh a token).
3. **Stop and report if ANY of these apply:**
   - The fix would require a destructive or irreversible operation
   - You've tried 3 approaches and all failed
   - The failure is outside your authorized scope
4. **Never say "not blocking" and move on.** If something failed, either fix it, OR explain why it's genuinely not needed, OR create a follow-up task. Silent acceptance of failure is how work gets lost.

## After Every Failure: Encode the Fix

When a failure occurs and you identify the root cause, don't just fix it and narrate "lesson learned." Ask: **can this class of failure be prevented for all future sessions?**

1. **If it's a behavioral pattern** (e.g., "I should verify after syncing") → propose adding it to the relevant rule file
2. **If it's a mechanical check** (e.g., "force push should be blocked") → propose a PreToolUse hook
3. **If it's a user preference** (e.g., "user wants terse responses") → save to auto-memory

Don't wait for the user to ask "how do we prevent this?" — that question is your job. Every failure that repeats is a missing rule.

**Generalize at encoding time.** When writing a new rule, ask: "what's the general category of this failure?" Write the rule for the category, not just the specific instance. "Verify after syncing harness files" is a specific instance of "verify after any multi-step operation where you assume completeness." Encode the broader principle.

**Fix the Class, Not the Instance.** When a reviewer (or any feedback source — adversarial agent, user correction, test failure, lint error) flags a defect at a specific location, the fix is not done until you have searched the entire artifact for sibling instances of the same defect class. Document the search in the fix commit (e.g., `Class-sweep: <grep pattern> — N matches, M fixed`). The named instance is one example of the class; the class is what gets fixed.

This rule exists because adversarial reviewers and LLM builders interact in a narrow-fix-bias loop: the reviewer names a specific defect at file:line, the builder fixes that one instance, the reviewer's next pass surfaces a sibling instance of the same class, the builder fixes that one, the next pass surfaces another sibling, and so on. Each pass closes a real gap, but each pass also leaves siblings intact — review loops fail to converge in 5+ iterations when one class-sweep would have closed all instances in the first pass.

**Procedure when feedback arrives:**

1. **Read the feedback's `Class:` field** if the source provides one (the seven adversarial-review agents — `systems-designer`, `harness-reviewer`, `code-reviewer`, `security-reviewer`, `ux-designer`, `claim-reviewer`, `plan-evidence-reviewer` — emit class-aware feedback per their Output Format Requirements). If the feedback names a class explicitly, use it. If it doesn't, infer the class yourself before editing anything.
2. **Run the `Sweep query:` field** if the source provides one. Otherwise, write your own grep / ripgrep / structural search that surfaces every sibling of the named instance across the artifact (the plan file, the source tree, the doc tree — whichever scope the class lives in).
3. **Triage every match.** Each match is either (a) an actual sibling that needs the same fix, or (b) a false positive (the pattern matched but the context exempts it). Document the count: "N total matches, M needed fixing, N-M were exempt because <reason>."
4. **Fix all M actual siblings in the same commit** as the named instance. If the fixes naturally split into multiple commits (e.g., siblings in different files belong to different conceptual changes), each commit's message must reference the class-sweep so the audit trail is intact.
5. **Document the sweep in the fix commit message.** Format: `Class-sweep: <pattern> — N matches, M fixed, N-M exempt (<reason>)`. This makes the class-level discipline visible in git history and lets a reviewer's next pass confirm the sweep happened.

**Why this is not optional:** "I fixed the named instance and the reviewer can flag siblings on the next pass" is the precise pattern this rule prevents. Sibling instances are the same defect by definition — the reviewer named one at random. The cost of one sweep is small; the cost of 5+ review iterations to surface siblings one at a time is large (and erodes user trust as the loop drags on).

**Escape hatch:** if the reviewer's `Class:` field is `instance-only`, the defect is genuinely unique and no sweep is needed. Default assumption is that defects have siblings; treat `instance-only` as the rare case requiring justification, not the default.

**Update the failure mode catalog.** Once the root cause is identified, open `docs/failure-modes.md` and either (a) extend an existing entry whose Symptom matches the phenotype you observed (add to its Example list, refine Detection or Prevention if the new instance reveals something new), or (b) append a new `FM-NNN` entry if the root cause is a new class. If you decide it is NOT a new class, briefly justify the decision in the diagnosis notes — do not skip the catalog step silently. The catalog is the durable, version-controlled record of every known failure class; a session that diagnoses a root cause and does not update the catalog has discovered something the next session will have to rediscover. The `harness-lesson` and `why-slipped` skills check the catalog first when proposing a new mechanism, so a missing entry weakens both skills' starting context.

## When the User Corrects You

A user correction ("no, don't do that", "why didn't you do X", "that's not what I asked for") is the highest-signal moment for improvement. Respond to every correction with:

1. **Fix the immediate issue**
2. **Identify whether it's a one-off mistake or a pattern** — if the same type of correction has happened before (in this session or in feedback memories), it's a pattern
3. **Propose a rule** — "To prevent this in future sessions, I'd add [specific rule] to [specific file]. Want me to do that?" Don't just apologize and move on.

## Trust Observable Output Over Source Code

When the user reports something looks wrong (screenshot, live app, rendered output), trust what's visible over what the code says. Correct class names don't mean correct rendering — the pipeline from source to screen can break silently. Investigate the rendering chain, not just the source files.

## Don't Overwrite What You're Uncertain About

When updating information (memory entries, documentation, data), don't overwrite existing content based on assumptions. If two sources conflict, verify with the user or the authoritative source before changing. "I think X replaced Y" is not sufficient justification to delete Y — ask first. This applies to memory entries, documentation, and any factual claims about the user's systems.
