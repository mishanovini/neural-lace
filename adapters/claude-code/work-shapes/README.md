# Work Shapes — Engineering Catalog

The recurring task classes in harness-dev work, with canonical structures and mechanical-compliance checks. Per Build Doctrine Principle 2 (engineering catalog), recurring work patterns get cataloged so builders fill in known shapes rather than re-deriving structure each time.

## Format

Each shape is a Markdown file with YAML frontmatter declaring:

- `shape_id` — kebab-case identifier (e.g., `build-hook`).
- `category` — coarse grouping (`hook`, `rule`, `agent`, `decision`, `test`, `migration`).
- `required_files` — the artifacts a compliant instance produces.
- `mechanical_checks` — bash one-liners verifying compliance (regex/grep patterns for v1).
- `worked_example` — pointer to an existing harness file that exemplifies the shape.

The body documents when to use the shape, structural pattern, and common pitfalls.

## How to use

1. **Before starting harness-dev work**, scan the catalog. If the work matches an existing shape, copy its structure.
2. **The plan file's task description** cites the shape by `shape_id` (e.g., "Verification: build-hook shape compliance"). The mechanical checks become the verification rubric.
3. **If no shape fits**, the work is novel — escalate via the plan template's `## Walking Skeleton` discipline. If the pattern recurs, propose a new shape via the path documented in `rules/work-shapes.md`.

## v1 shape inventory (6)

- `build-hook.md` — PreToolUse / PostToolUse / Stop / SessionStart hook scripts in `adapters/claude-code/hooks/`.
- `build-rule.md` — Pattern-class or Mechanism-class doctrine in `adapters/claude-code/rules/`.
- `build-agent.md` — Adversarial / verifier / planner agent prompts in `adapters/claude-code/agents/`.
- `author-ADR.md` — Architecture decision records in `docs/decisions/NNN-<slug>.md`.
- `write-self-test.md` — `--self-test` block convention for hooks and bash mechanisms.
- `doc-migration.md` — Doctrine / canonical-doc moves between repos with byte-identical or anonymization-only diff.

## Cross-references

- `adapters/claude-code/rules/work-shapes.md` — the rule documenting when to use a shape, how to add one, and the escalation path for novel work.
- Build Doctrine Principle 2 (engineering catalog) — the upstream principle this library operationalizes for harness-dev.
- `adapters/claude-code/rules/orchestrator-pattern.md` — references the library when dispatching work to builders.
