# Observed Errors First

**Classification:** Mechanism. Hook-enforced via `hooks/observed-errors-gate.sh` (PreToolUse on `git commit`). When the commit looks like a fix (commit message matches `(fix|fixed|fixes|bug|broken|regression|repair|resolve|hotfix)\b`) AND the commit modifies files under non-doc-only paths, the gate requires `.claude/state/observed-errors.md` to have a fresh non-trivial entry from the current session. Otherwise blocks.

## Why this rule exists

In a representative incident, the agent saw an HTTP `500` returned from a test five times in a row before reading the response body. The body contained the actual root cause — a pre-existing schema/enum mismatch unrelated to the agent's work. The cost of NOT reading the body: ~150-200k wasted tokens iterating on the wrong hypothesis. The cost of reading the body: 30 seconds.

The agent had `rules/diagnosis.md` saying "trace the full chain" and "exhaustive by default." That rule is correct in principle but didn't fire because the agent never recognized the situation as one where it applied. The lesson is that **rules depending on the agent's self-classification are weak.** This rule, by contrast, triggers on an observable artifact (commit shape) and demands a different observable artifact (a recorded verbatim error).

The forcing function isn't the artifact's content — it's the act of pasting an actual error message into a file. A perfunctory "I observed an error" entry is hard to write because the agent has to pretend to remember a status code, body, and stack frame. The friction of producing fake evidence is comparable to producing real evidence — and the agent's been trained to prefer real over fake.

## What the rule requires

When committing a fix, before the commit can land:

1. **The error you're fixing must be in `.claude/state/observed-errors.md`** (append-only file at the project root's `.claude/state/` directory).
2. **The entry must be from the current session** (mtime within the last 60 minutes).
3. **The entry must be a real error**, recognizable by at least one of:
   - An HTTP status code (`4xx` or `5xx`) plus a response body excerpt
   - An exception type (e.g., `TypeError`, `AssertionError`, `Error:`) plus at least one stack frame line
   - A test failure with the expected-vs-received diff verbatim
   - A console error / warning verbatim with file:line if available

The hook checks for these patterns. It can't tell faked from real, but the friction of pasting recognizable error syntax is the discipline.

## Format

`.claude/state/observed-errors.md` is plaintext, append-only, single file per project. One entry per observed error. Simple structure:

```markdown
# Observed errors

## YYYY-MM-DD HH:MM — POST /api/<resource> returns 500
Reproduction: `<command that triggers the error>`
Status: 500
Body: `{"error":"Failed to ..."}`
Underlying (from DB driver / dependency error): `<verbatim error string>`
Hypothesis: <inferred cause grounded in the verbatim error above>

## YYYY-MM-DD HH:MM — <feature> intermittent failure (~80% pass rate)
Reproduction: `<command that runs the feature N times>`
Run 1: ✓
Run 2: ✗ — <distinguishing trait, e.g. response empty + escalation_reason quote>
Run 3: ✓
Pattern: <category of failure, e.g. "rate-limit, not flakiness in the underlying service">.
```

Each entry should include:
- Timestamp + 1-line description
- Reproduction command (so the next session can re-trigger)
- The verbatim error (status, body, stack — whichever applies)
- Optional: hypothesis derived from this observation

## When the gate skips

The gate does NOT fire when:
- The commit only modifies docs (`*.md` files at any depth)
- The commit message starts with `chore:`, `style:`, `refactor:` (no fix-class keyword)
- The commit is a merge commit (parent count > 1)

The gate DOES fire when:
- Any code file changed AND the message contains fix-class keywords (the common case)
- Any test file changed AND the message contains fix-class keywords (a fix that changes tests too)

## Override

If the rule legitimately doesn't apply (e.g., a fix discovered by code review with no runtime symptom), set the env var `OBSERVED_ERRORS_OVERRIDE=<short-reason>` for the duration of the commit. The hook logs the override to `.claude/state/observed-errors-overrides.log` for periodic review. Chronic override use is itself a signal — the harness review checks the log.

## Cross-references

- `rules/diagnosis.md` — the broader exhaustive-diagnosis discipline. This rule operationalizes its first principle ("read the full stack") for the specific moment of "I'm about to commit a fix."
- `hooks/observed-errors-gate.sh` — the PreToolUse hook that enforces this rule.
- `docs/harness-review-audit-questions.md` — the five lenses to evaluate this rule against. Specifically applied here: triggers on observable commit shape (not self-classification), narrow remedy (one file), low cheap-evasion paths (rename keyword in commit message → user reads it; paste fake error → still does the discipline of formatting an error).
