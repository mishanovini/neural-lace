# Work Shapes — compact
> Enforcement: Pattern — self-applied catalog scan before dispatching harness-dev builder work.
> Applies: any harness-dev task (hooks, rules, agents, ADRs, self-tests, doc migrations).

- Catalog at `adapters/claude-code/work-shapes/`. Six v1 shapes: `build-hook`, `build-rule`, `build-agent`, `author-ADR`, `write-self-test`, `doc-migration`.
- Before starting harness-dev work, scan the library for a matching `category`/`required_files` shape; cite its `shape_id` in the plan task description. The shape's `mechanical_checks` frontmatter becomes the verification rubric.
- New shape only after 3+ recurrences of a task class; pick the most idiomatic existing instance as the worked example; follow the existing frontmatter + body format (`## When to use`, `## Structure`, `## Common pitfalls`, `## Worked example walk-through`).
- No matching shape -> the work is novel: use the plan template's `## Walking Skeleton` section to articulate the smallest end-to-end slice; propose a new shape only if the pattern recurs.
- Mechanical checks in v1 run by hand or via task-verifier evidence — not yet an automatic commit-time gate.
