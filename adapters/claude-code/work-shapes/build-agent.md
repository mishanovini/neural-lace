---
shape_id: build-agent
category: agent
required_files:
  - "adapters/claude-code/agents/<name>.md"
  - "~/.claude/agents/<name>.md"
mechanical_checks:
  - "test -f adapters/claude-code/agents/<name>.md"
  - "grep -q '^name: ' adapters/claude-code/agents/<name>.md"
  - "grep -q '^description: ' adapters/claude-code/agents/<name>.md"
  - "grep -q -E '^(model|tools): ' adapters/claude-code/agents/<name>.md"
  - "diff -q adapters/claude-code/agents/<name>.md ~/.claude/agents/<name>.md"
worked_example: adapters/claude-code/agents/task-verifier.md
---

# Work Shape — Build Agent

## When to use

When the work creates or modifies a sub-agent prompt under `adapters/claude-code/agents/` — a reusable LLM persona dispatched via the `Task` (or `Agent`) tool to perform an adversarial review, a verification, a planning function, or a structured analysis. Agents are the LLM-judgment layer of the harness; they handle work that is too nuanced for regex but too narrow to require a fresh main-session prompt every time.

## Structure

A compliant agent produces two artifacts:

1. **The canonical agent file** at `adapters/claude-code/agents/<name>.md`. Required elements:
   - **YAML frontmatter** declaring `name`, `description`, `model` (or `tools`), and any allowed-tool restrictions.
   - **Body** structured as: persona declaration, scope, rubric / output format, examples (PASS / FAIL / INCOMPLETE).
   - **Output format requirements** that downstream consumers (other agents, hooks) can parse mechanically — a structured verdict line, a class-aware feedback block, etc.
   - **Cross-references** to the rules and hooks that invoke or compose with the agent.
2. **Live mirror** at `~/.claude/agents/<name>.md`, byte-identical.

## Common pitfalls

- **Vague rubric.** "Use your judgment" is not a rubric. State the specific signals that produce PASS, FAIL, INCOMPLETE.
- **Output unparseable by downstream hooks.** If a hook greps for `VERDICT: PASS`, the agent must emit that exact string, not "I conclude this is acceptable."
- **No examples.** PASS / FAIL examples lock in the agent's calibration. Without them, the agent drifts toward "looks fine" verdicts under context pressure.
- **Missing class-aware feedback (for adversarial reviewers).** The seven Gen-5 adversarial agents emit `Class:` + `Sweep query:` + `Required generalization:` blocks per `~/.claude/rules/diagnosis.md` "Fix the Class, Not the Instance." Verify the rubric prescribes this format.
- **Tool over-permission.** Granting `tools: *` when the agent only needs `Read` + `Grep` widens the blast radius of agent misbehavior. List tools explicitly.
- **Forgetting the live mirror.** Same trap as build-hook / build-rule.
- **Forgetting the persona-distinct opening.** Agents are read by other agents; a clear persona declaration ("You are an adversarial reviewer of...") establishes the role unambiguously.

## Worked example walk-through

`adapters/claude-code/agents/task-verifier.md` exemplifies the shape:

- YAML frontmatter declares `name: task-verifier`, model, and tool list.
- Persona established: the only agent permitted to flip task checkboxes; mandate documented in `~/.claude/rules/planning.md`.
- Rubric explicit: PASS / FAIL / INCOMPLETE verdict; preconditions for each (typecheck status, evidence-block format, runtime-verification correspondence).
- Output format: structured evidence block appended to the plan's `## Evidence Log` section with named fields (Task, Verdict, Files-modified, Verification-commands-run).
- Class-aware extension: at `rung >= 2`, invokes `comprehension-reviewer` and propagates its verdict.
- Cross-references: `pre-stop-verifier.sh`, `plan-edit-validator.sh`, `~/.claude/rules/planning.md` Verifier Mandate.
