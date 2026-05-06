# Floor 8 — Documentation in code — Standard

## Default
JSDoc/TSDoc/docstrings on every exported public API. README at repo root + per-package. ADRs for non-trivial decisions (in `docs/decisions/NNN-<slug>.md`). Inline comments explain WHY (constraints, hidden invariants), not WHAT.

## Alternatives
- **Fully literate code** (extensive prose docs alongside source) — overkill for most projects; appropriate for math-heavy or research code.
- **No docstrings; rely on type signatures** — fine for tiny internal libs; insufficient for public APIs or team handoffs.
- **External docs only** (Confluence, Notion) — drifts immediately. Discouraged as the only source.

## When to deviate
- Internal-only / single-developer projects: doc public APIs but skip per-package READMEs (the repo README is enough).
- Standards-compliant codebases (FAA, medical) may require traceable comment-to-requirement mapping; adopt the standard's templates.

## Cross-references
- ADR triggers per `~/.claude/rules/planning.md`: every Tier 2+ decision gets an ADR in the same commit.
- Floor 7 (testing) — test descriptions are documentation; pair with comment discipline.
