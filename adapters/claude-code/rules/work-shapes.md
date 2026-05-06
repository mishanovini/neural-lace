# Work Shapes — When to Use, How to Add, How to Escalate

**Classification:** Pattern (self-applied catalog). The shape inventory at `adapters/claude-code/work-shapes/` is documentation; the mechanical-compliance checks declared in each shape's frontmatter are bash one-liners that builders and verifiers run by hand or invoke from task-verifier in v1. Future iteration may add a hook that auto-asserts shape compliance at commit time (deferred per Tranche C scope per the parent simplification plan).

**Ships with:** the work-shapes library introduced in Tranche C of the architecture-simplification plan, operationalizing Build Doctrine Principle 2 (engineering catalog) for harness-dev work.

## Why this rule exists

Build Doctrine Principle 2 names the engineering catalog: recurring task classes get cataloged so builders fill in known shapes rather than re-deriving structure each time. Without a catalog, every harness-dev task starts from a blank plan template; structural mistakes recur across tasks because each builder rediscovers the conventions; verification rubrics drift because each task-verifier invocation invents its checks fresh.

The work-shapes library is the catalog applied to harness-dev itself. Six v1 shapes cover the most common harness-dev work classes. Each shape provides a canonical structure, a worked example, and mechanical-compliance checks that become the verification rubric.

## When to use a shape

**Before starting any harness-dev task**, scan `adapters/claude-code/work-shapes/` for a shape whose `category` and `required_files` match the work. Six v1 shapes:

- `build-hook` — creating or modifying a Claude Code hook script under `adapters/claude-code/hooks/`.
- `build-rule` — creating or modifying a doctrine file under `adapters/claude-code/rules/`.
- `build-agent` — creating or modifying a sub-agent prompt under `adapters/claude-code/agents/`.
- `author-ADR` — recording a Tier 2+ architectural / process decision under `docs/decisions/NNN-<slug>.md` plus an index row in `docs/DECISIONS.md`.
- `write-self-test` — adding a `--self-test` block to a bash mechanism (composes inline with `build-hook`).
- `doc-migration` — moving doctrine or canonical-reference content between locations with byte-identical or explicit-anonymization-only diff.

If a shape applies, the plan file's task description cites the shape by `shape_id`. The mechanical checks declared in the shape's frontmatter become the verification rubric — task-verifier (or the builder, in self-verification contexts) runs each check; PASS on every check is shape compliance; any FAIL surfaces a specific gap.

## How to add a new shape

When a new task class recurs three or more times across harness-dev plans, propose a new shape. Procedure:

1. **Identify the recurrence.** Three is the minimum; below that the pattern hasn't proven durable. Cite the three examples.
2. **Pick a canonical worked example** — the most complete, idiomatic instance of the shape that already exists in the harness.
3. **Write the shape file** at `adapters/claude-code/work-shapes/<shape-id>.md`. Follow the format from existing shapes:
   - YAML frontmatter: `shape_id`, `category`, `required_files`, `mechanical_checks`, `worked_example`.
   - Body: `## When to use`, `## Structure`, `## Common pitfalls`, `## Worked example walk-through`.
4. **Update the README** at `adapters/claude-code/work-shapes/README.md` to add the new shape to the v1 (or v2, if numbering bumps) inventory.
5. **Sync to live mirror** at `~/.claude/work-shapes/`.
6. **Reference the new shape** from any task description in active plans where it applies.

A new shape is a Pattern-level addition; no ADR is required unless the shape changes the catalog's architectural footprint (e.g., introducing a new category dimension that requires updates to the README structure or downstream tooling).

## Mechanical-compliance check pattern

Each shape's frontmatter declares mechanical checks as bash one-liners. Conventions:

- **Each check is independently runnable.** No multi-line scripts, no shared state between checks.
- **Each check exits 0 on PASS, non-zero on FAIL.** Some use `grep -q`, some use `test -f`, some pipe to `wc -l` and compare. The compliance verifier runs each in sequence; any non-zero exit is a FAIL.
- **Checks reference `<name>` placeholders** that the verifier replaces with the actual instance's name (e.g., `<name>.sh` becomes `harness-hygiene-scan.sh`).
- **Worked-example checks are concrete.** When citing a worked example, use the actual file path, not a placeholder — the checks against the worked example must pass today.

In v1, mechanical checks run by hand or invoked from task-verifier as part of the evidence block. Future iteration may add a `work-shape-compliance-gate.sh` PreToolUse hook that runs the checks automatically at commit time, but that work is explicitly out of Tranche C scope per the parent simplification plan.

## Escalation when work doesn't fit a shape

Real work occasionally fails to match any of the six v1 shapes — that is expected for novel work. The escalation path:

1. **Confirm it's novel, not a misread.** Re-scan the README; check whether two shapes compose (e.g., `build-hook` + `write-self-test`).
2. **Use the plan template's `## Walking Skeleton` discipline.** Author the plan with the standard structure; the Walking Skeleton section is exactly the place to articulate "this work doesn't fit a known shape; here is the smallest end-to-end vertical slice that proves the structure works."
3. **If the pattern recurs, propose a new shape** per the "How to add a new shape" procedure above.

Escalation is cheap; novel work is legitimate. The catalog grows in response to real recurrence, not anticipated recurrence.

## Cross-references

- `adapters/claude-code/work-shapes/` — the library directory; the README is the entry point.
- `adapters/claude-code/work-shapes/README.md` — format spec and v1 inventory.
- `adapters/claude-code/rules/orchestrator-pattern.md` — references the library when dispatching work to builders.
- `adapters/claude-code/rules/vaporware-prevention.md` — enforcement-map row pointing at this rule.
- Build Doctrine Principle 2 (engineering catalog) — the upstream principle this library operationalizes.
- `~/.claude/templates/plan-template.md` — `## Walking Skeleton` section is the escalation venue for novel work.

## Scope

This rule applies to harness-dev work in any project whose Claude Code installation has the `work-shapes/` directory present (canonical at `adapters/claude-code/work-shapes/`, live mirror at `~/.claude/work-shapes/`). Downstream projects using the harness for their own product work do NOT need to apply the work-shapes catalog — the catalog is harness-specific. Project-level adoption is implicit: the install script copies the directory; downstream projects that don't run harness-dev simply ignore it.

## Enforcement

| Layer | What it enforces | File | Status |
|---|---|---|---|
| Library | The 6 v1 shape files with format + mechanical checks + worked example | `adapters/claude-code/work-shapes/*.md` | landed (Tranche C) |
| Rule (this doc) | When to use a shape, how to add one, escalation path | `adapters/claude-code/rules/work-shapes.md` | landed (Tranche C) |
| Compliance gate (future) | Mechanical assertion of shape compliance at commit time | (deferred per Tranche C scope) | not landed |

The library is documentation; the compliance check is currently a discipline (run the checks, verify PASS) rather than a hook-enforced gate. The deferral is intentional — the catalog must mature before mechanical enforcement is appropriate.
