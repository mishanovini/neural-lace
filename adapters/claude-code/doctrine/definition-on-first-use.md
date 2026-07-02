# Definition-on-first-use — compact
> Enforcement: definition-on-first-use-gate.sh (precommit, blocks undefined acronyms).
> Applies: commits touching `build-doctrine/` doctrine docs.

- Acronyms detected by regex `\b[A-Z]{2,6}\b`, minus a stopword allowlist (OK, OR, JSON, API, UI, ID, PR, etc.).
- Scope: fires only when a staged file matches `neural-lace/build-doctrine/**/*.md`; no-op otherwise.
- Every acronym must resolve one of two ways in the same diff: (a) defined in the glossary at `~/claude-projects/Build Doctrine/outputs/glossary.md` (`**TERM**`, `## TERM`, or `| TERM |` form), or (b) defined in-context via a parenthetical within ~30 chars of first use containing ≥2 words (e.g., `XYZ (cross-system Y zone)`).
- Path A (glossary) preferred for terms used across multiple docs; Path B (in-context) for one-off terms.
- Single-word parentheticals (aliases, not definitions) do NOT satisfy the gate.
- Missing glossary file -> gate warns and allows (graceful degradation, not a lockout).
