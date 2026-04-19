# Diagnosis Protocol

## What this principle covers
How to investigate problems before fixing them: tracing full chains, finding hidden errors, learning from failures, responding to corrections, and knowing when to trust observed behavior over source code.

---

## Map the Full Chain Before Fixing

When a problem is reported, trace the entire chain that influences the symptom: user action, frontend, API, backend, external services, response. Check every step. Report all issues in a single diagnosis.

Assume multiple problems until proven otherwise. The first error you find is rarely the only one.

**Process:**
1. Map the full chain. "Save fails" means: read the form, the API route, and the response consumer together.
2. Trace a concrete example end-to-end. Walk a real value through each layer.
3. Check what hides behind the first error. "If I fix this, what does the next step do?"
4. List all bugs across the full chain. Fix them all in one pass.

---

## Exhaustive by Default

Do not stop at the first plausible explanation. The question is not "what could cause this?" but "what does cause this, and what else is broken?"

- A symptom at Layer N often has a root cause at Layer N-2.
- Fixing the symptom without finding the root cause creates a new, subtler bug.
- TypeScript compiling is not validation. Code that type-checks can still produce wrong results. Trace the full chain with a concrete value, or run the code and observe the outcome.

---

## When Tools or Commands Fail

Apply the same exhaustive principle to operational failures (auth errors, push failures, API timeouts):

1. **Read the error message.** Diagnose the root cause before retrying blindly.
2. **Try at least 2 alternative approaches** before accepting failure. But only reversible, non-destructive ones (switch accounts, fix a URL, refresh a token).
3. **Stop and report if any of these apply:**
   - The fix would require a destructive or irreversible operation.
   - You have tried 3 approaches and all failed.
   - The failure is outside your authorized scope.
4. **Never say "not blocking" and move on.** If something failed, either fix it, explain why it is genuinely not needed, or create a follow-up task. Silent acceptance of failure is how work gets lost.

---

## After Every Failure, Encode the Fix

When a failure occurs and you identify the root cause, do not just fix it and narrate a lesson learned. Ask: **can this class of failure be prevented for all future sessions?**

- If it is a behavioral pattern (e.g., "I should verify after syncing"), propose adding it to the relevant rule file.
- If it is a mechanical check (e.g., "force push should be blocked"), propose an automated guard.
- If it is a user preference (e.g., "the user wants terse responses"), save it to persistent memory.

Do not wait for the user to ask "how do we prevent this?" That question is your job. Every failure that repeats is a missing rule.

**Generalize at encoding time.** When writing a new rule, ask: "What is the general category of this failure?" Write the rule for the category, not just the specific instance. "Verify after syncing files" is a specific instance of "verify after any multi-step operation where you assume completeness." Encode the broader principle.

---

## When the User Corrects You

A user correction is the highest-signal moment for improvement. Respond to every correction with:

1. **Fix the immediate issue.**
2. **Identify whether it is a one-off mistake or a pattern.** If the same type of correction has happened before, it is a pattern.
3. **Propose a rule.** "To prevent this in future sessions, I would add [specific rule] to [specific file]. Should I do that?" Do not just apologize and move on.

---

## Trust Observable Output Over Source Code

When the user reports something looks wrong (a screenshot, the live application, rendered output), trust what is visible over what the code says.

Correct class names do not mean correct rendering. The pipeline from source to screen can break silently: build caching, stale assets, CSS specificity conflicts, server-side vs. client-side rendering mismatches. Investigate the rendering chain, not just the source files.

---

## Do Not Overwrite What You Are Uncertain About

When updating information (memory entries, documentation, data), do not overwrite existing content based on assumptions. If two sources conflict, verify with the user or the authoritative source before changing.

"I think X replaced Y" is not sufficient justification to delete Y. Ask first. This applies to memory entries, documentation, configuration, and any factual claims about the user's systems.
