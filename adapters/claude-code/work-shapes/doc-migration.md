---
shape_id: doc-migration
category: migration
required_files:
  - "<source-path> in source repo or location"
  - "<dest-path> in neural-lace or destination location"
mechanical_checks:
  - "test -f <dest-path>"
  - "diff -r <source-path> <dest-path> | grep -E '^(>|<|Only in)' | wc -l : 0  # OR explicit-anonymization-only diff (sweep allowed identifier replacements)"
  - "git log --diff-filter=A -- <dest-path> | head -1  # confirms dest was added in a real commit"
worked_example: build-doctrine Tranche 0b migration (canonical-doc moves into neural-lace/build-doctrine/)
---

# Work Shape — Doc Migration

## When to use

When the work moves a doctrine document, canonical reference, or specification from one location to another — typically into `neural-lace/build-doctrine/` from a private staging repo, or between sub-trees of the harness as the architecture evolves. Doc migrations are high-stakes for two reasons: (1) the source-of-truth pointer shifts, breaking inbound links if the migration is incomplete; (2) the diff between source and destination must be either byte-identical or explicitly anonymization-only (per `~/.claude/rules/harness-hygiene.md`) — silent edits during migration drop content or introduce identity leakage.

## Structure

A compliant migration produces:

1. **The destination file** at `<dest-path>`, with content matching the source under one of two acceptable transformations:
   - **Byte-identical:** content matches source exactly. Use when no identity / scope adjustment is needed.
   - **Explicit-anonymization-only:** content matches source EXCEPT for documented identifier swaps (real org name → `<your-org>`, real codename → generic noun, real path → relative). Every diff line falls into the explicit-allowlist; no semantic edits.
2. **A migration record** — typically a commit message naming the source path, the destination path, and the transformation type ("byte-identical" or "anonymization-only with N replacements"). For larger migrations, an entry in `docs/discoveries/YYYY-MM-DD-<slug>.md` or a `## Decisions Log` entry in the active plan.
3. **No orphaned references in the source.** If the source repo is also under harness control, the source file is either deleted in the same commit (with a redirect note) or marked superseded with a pointer to the destination.

## Common pitfalls

- **Silent content edits during migration.** "Just cleaning up while I'm in the file" introduces semantic drift between source and destination. The diff should be empty or fully accounted-for in the anonymization log.
- **Identifier leakage at the destination.** Migrations FROM private staging repos must run through the `harness-hygiene-scan.sh` denylist before commit. The destination repo's hygiene rules apply, not the source's.
- **Inbound links not updated.** If other harness files reference the source path, those references break on migration. Sweep with `rg "<source-path>"` and update each match in the same commit.
- **`docs/discoveries/` capture missing.** Migrations are exactly the kind of architectural learning the discovery protocol exists to capture. If the migration's rationale is not obvious from the commit message, write a discovery file.
- **Mid-migration interrupt.** If the migration is interrupted, the source and destination disagree silently. Recovery: `diff -r <source> <dest>` — every difference is either expected (anonymization) or a mid-migration fragment to reconcile.

## Worked example walk-through

The build-doctrine Tranche 0b migration exemplifies the shape: canonical doctrine documents from a private staging repo were moved into `neural-lace/build-doctrine/` with explicit anonymization swaps for real org names, codenames, and absolute paths. The destination was scanned by `harness-hygiene-scan.sh` before commit. Inbound references in `~/.claude/rules/`, `~/.claude/CLAUDE.md`, and active plans were updated in the same commit set. The migration record lives in the Tranche 0b plan's `## Decisions Log` and in companion `docs/discoveries/` entries documenting per-document rationale.
