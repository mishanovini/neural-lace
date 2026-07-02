# Harness Development — compact
> Enforcement: harness-hygiene-scan.sh (precommit, Layer 1 denylist + Layer 2 heuristics). Full: doctrine/harness-hygiene-full.md
> Applies: any edit under adapters/claude-code/ or ~/.claude/ (the harness kit itself).

## Hygiene — what never ships (harness-hygiene-scan.sh)
- **no sensitive data** in harness code: no passwords/tokens/keys, no real emails (use `example.com`/`test@example.com`), no real domains, no personal names outside an `Owner:` field, no absolute paths with a username (use `$HOME`/`~/`), no company/org/product-codenames, no incident details tied to a real product, no real user data in fixtures.
- Two-layer config: harness layer (committed, generic) + `~/.claude/local/` (gitignored, per-machine); harness code reads local via safe fallbacks, never crashes when local is absent.
- Templates use obviously-placeholder defaults (`<your-username>`, not a real one).
- Downstream-project plans/decisions/reviews do NOT ship in the harness repo; harness-dev-about-itself artifacts DO (date/number-prefixed top-level names are tracked; non-conforming names are gitignored).
- Installation is idempotent and lossless: re-running install.sh never destroys `~/.claude/local/` or user-edited settings; conflicting overwrites get a `.example` suffix instead.

## Maintenance (harness-maintenance.md)
- **global by default**: new agents/rules/hooks/docs/templates go in `~/.claude/`, not a project's `.claude/rules/`, unless genuinely project-specific. Never duplicate a global rule into a project dir.
- After editing `~/.claude/`, **sync to the neural-lace repo** (Windows copies, doesn't symlink) and verify with a **diff** across agents/rules/docs/hooks/templates — don't trust memory of what changed.
- Update `~/.claude/docs/harness-architecture.md` when a file is added/removed/renamed, or its scope changes significantly.
- Never leave stale project-level copies of global rules; delete on discovery.

## Content routing (information-architecture.md)
- `rules/` (now `doctrine/`) = operating rules/doctrine; `docs/decisions/` = ADRs; `docs/discoveries/` = mid-process learnings; `docs/reviews/` = audit passes; `docs/findings.md` = class-aware ledger; `docs/failure-modes.md` = named catalog; `docs/backlog.md` = open work; `SCRATCHPAD.md` = ephemeral (gitignored, ≤30 lines); `~/.claude/local/*` = machine-local config; `.claude/state/` = operational state.
- **CLAUDE.md routes, it does not store.** ≤200 lines soft target: the `@`-reference to canon, the short-form principle list, standing directives with pointers, a `## Detailed Protocols` index. No multi-paragraph rule bodies, no examples/edge-cases, no decision rationale, no duplicated content — extract to doctrine/ and leave a one-line pointer.
- Routing one-liner: rules/ constitution-only; doctrine/ everything else; decisions docs/decisions/. New content kind → pick location + lifetime + discoverability before writing.
