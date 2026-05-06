---
shape_id: build-rule
category: rule
required_files:
  - "adapters/claude-code/rules/<name>.md"
  - "~/.claude/rules/<name>.md"
mechanical_checks:
  - "test -f adapters/claude-code/rules/<name>.md"
  - "grep -q '^**Classification:**' adapters/claude-code/rules/<name>.md"
  - "grep -q '^## Scope' adapters/claude-code/rules/<name>.md"
  - "grep -q '^## Cross-references' adapters/claude-code/rules/<name>.md || grep -q 'Cross-reference' adapters/claude-code/rules/<name>.md"
  - "diff -q adapters/claude-code/rules/<name>.md ~/.claude/rules/<name>.md"
worked_example: adapters/claude-code/rules/harness-hygiene.md
---

# Work Shape — Build Rule

## When to use

When the work creates or modifies a doctrine file under `adapters/claude-code/rules/` — Pattern-class (self-applied discipline) or Mechanism-class (hook-enforced) guidance the agent reads contextually. Rules are the durable narrative layer; hooks are the mechanical layer; agents are the LLM-judgment layer. A new rule is appropriate when a reusable principle needs to be cited from multiple places and is too prose-heavy to live inside a hook header comment.

## Structure

A compliant rule produces two artifacts:

1. **The canonical rule file** at `adapters/claude-code/rules/<name>.md`. Required structural elements:
   - **`**Classification:**`** line at top: `Pattern`, `Mechanism`, or `Hybrid` (with a one-sentence note on which parts are which).
   - **Why this rule exists** section: the failure mode the rule prevents, ideally with a concrete incident citation.
   - **Body sections** explaining the discipline / mechanism. Use H2 / H3 hierarchy; tables for enforcement maps.
   - **Cross-references** section: links to sibling rules, hooks, agents, ADRs, and templates.
   - **Scope** section: when the rule applies (every project / harness only / Mode: design plans only / etc.).
2. **Live mirror** at `~/.claude/rules/<name>.md`, byte-identical.

## Common pitfalls

- **Mechanism described but no hook backs it.** A rule that says "X is enforced by hook Y" while Y doesn't exist is theater. Cross-check the enforcement-map row against the actual file.
- **Pattern with no failure-mode citation.** Patterns drift under context pressure unless the cost of forgetting is named concretely. Cite a real incident or a `FM-NNN` failure-mode entry.
- **Skipping Classification.** Without `Pattern` / `Mechanism` / `Hybrid` declared, readers cannot tell whether the rule is mechanically enforced or relies on agent discipline.
- **Forgetting the live mirror.** Same trap as build-hook — edit both, verify byte-identical.
- **Acronyms used without definition.** If the rule lives under `neural-lace/build-doctrine/`, the `definition-on-first-use-gate.sh` will block. Otherwise, define on first use as a courtesy.
- **No Scope section.** Without scope, a rule meant for harness-only work gets applied to downstream projects, or vice versa.

## Worked example walk-through

`adapters/claude-code/rules/harness-hygiene.md` exemplifies the shape:

- `**Classification:** Hybrid` with one-sentence breakdown of Pattern vs Mechanism parts.
- `Purpose` section names the failure: a harness that leaks identity stops being a kit.
- Body sections enumerate concrete bans (no real emails, no absolute paths with usernames, no codenames).
- Two-layer-config architecture documented inline so the rule is self-contained.
- `Enforcement` section names the hook (`harness-hygiene-scan.sh`), the agent (`harness-reviewer`), and the planned future mechanism (`/harness-review` skill).
- `Scope` section: applies to NL itself, all `adapters/`, all `principles/` — explicitly NOT to downstream projects using the harness.
