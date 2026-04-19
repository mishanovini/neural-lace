---
name: verify-feature
description: Ripgrep-based lookup that returns file:line citations for a feature name. Use before claiming a feature exists in conversation. Input is a feature name or function name; output is a list of locations where the feature is defined or referenced. Default to invoking this when answering any "does X work" / "how is Y implemented" / "is Z wired up" question.
---

# verify-feature

Ripgrep wrapper that returns citations for a feature. Used to ground claims before answering product questions.

## When to use

Use this skill EVERY time the user asks:
- "Does X work?"
- "Is Y wired up?"
- "How does Z handle W?"
- "Can the system do A?"
- "What happens when B?"
- "Do we have C?"
- "Is D implemented?"

Any question whose answer is a claim about a feature's existence or behavior.

## How to use

Run this skill with the feature name or likely symbol name as the argument. The skill greps the codebase for:

1. **Definitions** — where the symbol/feature is declared
2. **Call sites** — where the symbol/feature is used
3. **Related tests** — tests that reference the symbol
4. **Database migrations** — migrations that mention the feature (for column/table claims)
5. **Plan / backlog references** — whether the feature is planned or described

Output format: a list of `file:line: matched content` results, grouped by category.

## Execution

```bash
#!/bin/bash
# This is the skill's ripgrep pipeline. The harness runs this when the
# skill is invoked. The query is the feature name.

QUERY="$1"
if [[ -z "$QUERY" ]]; then
  echo "verify-feature: missing query argument"
  echo "Usage: /verify-feature <feature-name>"
  exit 1
fi

echo "=== verify-feature: searching for '$QUERY' ==="
echo ""

echo "--- Definitions in src/ ---"
rg -n --no-heading -t ts -t tsx "(function|const|class|export)\s+\w*${QUERY}" src/ 2>/dev/null | head -20
echo ""

echo "--- Call sites in src/ ---"
rg -n --no-heading -t ts -t tsx "\b${QUERY}\b" src/ 2>/dev/null | head -30
echo ""

echo "--- Tests referencing ${QUERY} ---"
rg -n --no-heading "${QUERY}" tests/ 2>/dev/null | head -20
echo ""

echo "--- Migrations mentioning ${QUERY} ---"
rg -n --no-heading "${QUERY}" supabase/migrations/ 2>/dev/null | head -10
echo ""

echo "--- Docs / plans / backlog mentions ---"
rg -n --no-heading "${QUERY}" docs/ 2>/dev/null | head -20
echo ""

echo "=== end verify-feature ==="
```

## Interpretation rules

After running the skill, interpret the output as follows:

1. **Zero matches in src/ → the feature does not exist in the codebase.** Your response to the user must be "I don't find any evidence of [feature] in the codebase. It may not be implemented."

2. **Matches only in docs/ or plans/ → the feature is planned but not built.** Your response must distinguish "described in the plan at <path>" from "implemented at <path>".

3. **Matches in src/ but zero in tests/ → the feature exists but is not tested.** Your response should note this explicitly so the user knows the runtime behavior is unverified.

4. **Matches in src/ and tests/ → the feature exists and has test coverage.** Your response can cite the file:line and the test that covers it.

5. **Matches in migrations but not in src/ → the schema change exists but no code uses it yet.** Your response should distinguish the two layers.

## After invocation

When you use the output of this skill, cite specific file:line references in your response to the user. The citation format is:

`<src/path/to/file.ts:42>`

Not:

`the foo.ts file around line 42 somewhere`

**Every functional claim in your response must have an accompanying citation.** If `verify-feature` returned zero matches, your response must say so and not claim the feature exists.

## Honest limitation

This skill uses simple ripgrep. It does not understand:
- Renames (if the symbol was renamed, the old name won't match)
- Import aliases (`import { foo as bar }`)
- String-interpolated identifiers
- Dynamic references (e.g., `obj['handle' + method]`)

If the skill returns zero matches but you suspect the feature exists under a different name, invoke it again with synonyms. Do not default to "the feature exists anyway" without a citation.

## Integration with claim-reviewer

If you are answering a product Q&A question, the recommended flow is:

1. Invoke `verify-feature` with the feature name
2. Draft your response using the citations
3. (Optional but encouraged) invoke the `claim-reviewer` agent on the draft
4. Send the response only after `claim-reviewer` returns PASS

This is the single best mitigation for verbal vaporware.
