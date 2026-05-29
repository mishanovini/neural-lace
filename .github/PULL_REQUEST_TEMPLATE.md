## Summary

<replace this bracketed text with content>

## What changed and why

<replace this bracketed text with content>

## What mechanism would have caught this?

This PR must answer this question. The capture-codify cycle (every failure is a harness opportunity — encode the prevention) requires identifying, for any fix or change, whether an existing or new mechanism would have caught the underlying issue.

Pick exactly one of the three answer forms (a) / (b) / (c). Two writing styles are accepted:

- **Strict scaffold form (preferred for humans filling the template).** Fill in the chosen `### a)` / `### b)` / `### c)` sub-heading below; delete the bracketed placeholder under it. Leave the other two sub-headings present with their placeholders intact (they document the option set).
- **Prose form (typical for AI-spawned PRs).** Replace the three `###` sub-heading scaffolds with a paragraph that starts with `(a)`, `(b)`, or `(c)` — optionally bold-wrapped as `**(b) New catalog entry proposed.**` — followed by the substantive answer. Either form satisfies the validator.

### a) Existing catalog entry

<mechanism answer — replace this bracketed text>

### b) New catalog entry proposed

<mechanism answer — replace this bracketed text>

### c) No mechanism — accepted residual risk

<mechanism answer — replace this bracketed text>

## Primary evidence (required for any sweep / class-fix / refactor PR)

Required if this PR's title contains `fix:`, `sweep`, `class-sweep`, or `refactor` (case-insensitive) — i.e., if the PR claims to fix a recurring class. See [`~/.claude/rules/diagnosis.md`](../adapters/claude-code/rules/diagnosis.md) DIAGNOSTIC-FIRST PROTOCOL + [`~/.claude/rules/claims.md`](../adapters/claude-code/rules/claims.md) HYPOTHESIS-VS-PROOF LABELING for why this section exists.

Fill in all four sub-sections. If this PR genuinely does not need primary evidence (e.g., it's a docs typo with a `fix:` prefix), add the opt-out marker anywhere in this PR body: `[evidence-exempt: <substantive reason ≥ 20 chars>]`. The opt-out is audit-trail-preserved — every exempt PR is greppable later.

### What runtime/log evidence did you pull?

<replace this bracketed text — name the specific log source (vercel logs, Sentry, supabase logs, browser console, integration-test output, etc.), the time window, and the command/URL used to retrieve it>

### What did the evidence show?

<replace this bracketed text — paste the actual error message, stack trace, status-code distribution, or other primary signal. Inferential summaries ("things looked broken") are not evidence; the verbatim signal is>

### What hypothesis did you test BEFORE writing the fix?

<replace this bracketed text — state the causal claim you tested, tagged PROVEN or HYPOTHESIZED per claims.md>

### What refutation criteria would have shown the hypothesis was wrong?

<replace this bracketed text — what observable evidence would have invalidated the hypothesis? If you cannot name one, the diagnosis is not falsifiable and the fix may be misdirected>

## Testing performed

<replace this bracketed text with content>
