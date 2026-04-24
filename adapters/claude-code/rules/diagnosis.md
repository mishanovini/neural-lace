# Diagnosis Before Fixing

**Before proposing any fix, read the full stack that influences the symptom.**

**Exhaustive by default.** When the user reports any problem, trace the entire chain: user action → frontend → API → backend → external services → response. Check every step. Report ALL issues in a single diagnosis. Assume multiple problems until proven otherwise.

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
