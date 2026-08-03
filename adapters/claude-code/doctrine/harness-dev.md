# Harness Development — compact
> Enforcement: harness-hygiene-scan.sh (precommit, Layer 1 denylist + Layer 2 heuristics). Full: doctrine/harness-hygiene-full.md
> Applies: any edit under adapters/claude-code/ or ~/.claude/ (the harness kit itself).

## Hygiene — what never ships (harness-hygiene-scan.sh)
- **no sensitive data**: no passwords/tokens/keys, no real emails/domains, no personal names
  outside `Owner:`, no absolute paths with a username (`$HOME`/`~/`), no company/product
  codenames, no incident details tied to a real product, no real user data in fixtures.
- Two-layer config: harness (committed, generic) + `~/.claude/local/` (gitignored,
  per-machine); harness code reads local via safe fallbacks, never crashes when absent.
- Templates use obviously-placeholder defaults (`<your-username>`, not a real one).
- Downstream-project plans/decisions/reviews do NOT ship in the harness repo; harness-dev-
  about-itself artifacts DO (date/number-prefixed names tracked; else gitignored).
- Installation is idempotent and lossless: re-running install.sh never destroys `local/` or
  user-edited settings; conflicting overwrites get a `.example` suffix instead.

## Maintenance (harness-maintenance.md)
- **global by default**: new agents/rules/hooks/docs/templates go in `~/.claude/`, not a
  project's `.claude/rules/`, unless genuinely project-specific. Never duplicate a rule.
- After editing `~/.claude/`, **sync to the neural-lace repo** and verify with a **diff** —
  don't trust memory of what changed.
- Update `~/.claude/docs/harness-architecture.md` on add/remove/rename or scope change.
- Never leave stale project-level copies of global rules; delete on discovery.

## Content routing (information-architecture.md)
- `doctrine/` = operating rules; `docs/decisions/` = ADRs; `docs/discoveries/` = mid-process
  learnings; `docs/reviews/` = audit passes; `docs/findings.md` = class-aware ledger;
  `docs/failure-modes.md` = named catalog; `docs/backlog.md` = open work; `SCRATCHPAD.md` =
  ephemeral (gitignored, ≤30 lines); `~/.claude/local/*` = machine-local state.
- **CLAUDE.md routes, it does not store.** ≤200 lines: `@`-reference to canon, principle
  list, standing directives with pointers, a `## Detailed Protocols` index. No multi-
  paragraph rule bodies, no rationale, no duplicated content — extract + pointer.
- Routing one-liner: rules/ constitution-only; doctrine/ everything else. New content kind →
  pick location + lifetime + discoverability first.

## Execution-layer invariants (single-flight-halt-runbook.md)
- Every heavy entry point sources `hooks/lib/single-flight-lib.sh` UNCONDITIONALLY, checks
  `sf_guard`/`sf_halt_active` first — wiring markers are belt, never braces.
- HALT the maintenance layer with one gesture: write a reason to
  `~/.claude/state/single-flight/HALT`; clear by deleting it. Drain, not kill.
- `config/schedule-manifest.json` declares cadence + measured cycle; doctor WARNs when
  cadence < 2x cycle.
