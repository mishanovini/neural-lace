# Plan: HARNESS-GAP-13 — Expand harness-hygiene-scan to detect more project-specific shapes

Status: ACTIVE
Execution Mode: orchestrator
Mode: code
Backlog items absorbed: HARNESS-GAP-13
acceptance-exempt: true
acceptance-exempt-reason: Harness-development plan; no product user. Verification is via hook/script --self-test invocations covering both denylist additions and new heuristic detection layer, plus a manual full-tree scan against the current repo confirming zero false-positive matches and clean exit.
tier: 1
rung: 1
architecture: coding-harness
frozen: false
prd-ref: n/a — harness-development

## Goal

Close HARNESS-GAP-13 by expanding `harness-hygiene-scan.sh` from a denylist-only literal scanner to a four-layer detector (per user decision 2026-05-05 — full original scope):

1. **Denylist additions (Layer 1)** — high-signal additional patterns for credential and infrastructure-identity shapes commonly observed leaking from downstream projects (cloud-bucket URL prefixes, OAuth client-id shapes, additional service-key shapes, database connection-string patterns). Conservative — high-signal-only, no generic tech terms (avoiding false-positive bloat).
2. **Heuristic detection layer (Layer 2)** — pattern-based detection of project-specific content shapes the literal denylist can't catch: project-internal file paths (`app/api/v\d+/[\w-]+/`, `src/components/[A-Z][\w]+\.tsx`, `supabase/migrations/\d{14}_[\w-]+\.sql`), repeated capitalized term clusters not in NL vocabulary. BLOCKS on match (per user decision 2026-05-05 — consistent with current scanner; override remains via `git commit --no-verify`).
3. **Periodic full-tree audit (Layer 3)** — `/harness-review` skill extension that runs `harness-hygiene-scan.sh --full-tree` and reports findings with denylist-class vs heuristic-class labels. Catches accumulated drift the staged-diff scanner missed.
4. **Sanitization helper (Layer 4)** — new script `harness-hygiene-sanitize.sh` that proposes replacements for detected matches; emits a unified diff suggesting `<your-project>`-style placeholders. Propose-only; user reviews and applies via `git apply`.

Outcome: harness-hygiene-scan stops being purely reactive. The structural defense the harness-hygiene rule promises is realized in code.

## Scope

- IN:
  - `adapters/claude-code/patterns/harness-denylist.txt` — extended (Layer 1)
  - `adapters/claude-code/hooks/harness-hygiene-scan.sh` — extended with heuristic detection (Layer 2). New sub-function `check_heuristics()` invoked alongside the existing denylist match. BLOCKS on heuristic match (exit 1) with stderr labeled `[heuristic]` distinct from `[denylist]`.
  - `adapters/claude-code/skills/harness-review.md` — extended with new check section that runs `harness-hygiene-scan.sh --full-tree` and includes findings in the weekly review (Layer 3).
  - `adapters/claude-code/scripts/harness-hygiene-sanitize.sh` — NEW (Layer 4); proposes replacements for detected matches, emits unified diff.
  - Self-test extensions in `harness-hygiene-scan.sh --self-test` covering Layer 1 (new denylist patterns match) + Layer 2 (heuristic patterns match positive cases AND don't false-positive on NL's own content like `~/.claude/...` paths).
  - Self-test for `harness-hygiene-sanitize.sh` covering replacement-proposal correctness across each replacement class.
  - Sync to `~/.claude/` per Windows manual-sync rule (hooks/scripts/skills/patterns/rules).
  - Documentation: `adapters/claude-code/rules/harness-hygiene.md` extended with a "Layer 2 heuristic detection" section briefly explaining what the heuristics catch and how to add false-positive exemptions.
- OUT:
  - LLM-driven detection (the heuristic layer is regex-only).
  - Auto-applying sanitization replacements (helper PROPOSES; user reviews and applies via `git apply`).
  - Cross-repo scanning (single-repo only).
  - Substantive rewrite of `harness-review.md` skill beyond adding the new check section.
  - Promoting GAP-13 layers to project-level plan templates or rules for downstream consumers (out of scope — internal NL improvement only).

## Tasks

- [x] 1. **Layer 1 — Denylist additions.** Add to `adapters/claude-code/patterns/harness-denylist.txt`:
    - Cloud-bucket-URL-with-project-fragment patterns: `s3://[a-z0-9-]+-(prod|dev|staging)/`, `gs://[a-z0-9-]+-(prod|dev|staging)/`
    - Additional OAuth client-id shapes: Google `\d{12}-[a-z0-9]{32}\.apps\.googleusercontent\.com`, GitHub OAuth app `Iv1\.[a-f0-9]{16}`
    - Database connection strings with embedded credentials: `(postgres|mysql|mongodb)(\+srv)?://[^/\s]+:[^@\s]+@`
    - SendGrid: `SG\.[A-Za-z0-9_-]{22,}\.[A-Za-z0-9_-]{43,}`
    - Stripe restricted keys: `rk_(live|test)_[A-Za-z0-9]{20,}`
    - NO generic tech terms (PostgreSQL-as-word, React-as-word, etc.). Each addition must be high-signal — false-positive risk near zero on prose mentions.
- [x] 2. **Layer 2 — Heuristic detection in `harness-hygiene-scan.sh`.** New sub-function `check_heuristics()`:
    - Scans for project-internal file-path shapes: `app/api/v\d+/[\w-]+/`, `src/components/[A-Z][\w]+\.tsx`, `supabase/migrations/\d{14}_[\w-]+\.sql`
    - Scans for repeated capitalized term clusters: 3+ occurrences of the same `[A-Z][a-z]{4,15}` token within a single file, excluding NL vocabulary allowlist (`Neural`, `Lace`, `Claude`, `Anthropic`, `Build`, `Doctrine`, `Generation`, `Pattern`, `Mechanism`, `Status`, `Mode`, etc.)
    - Excludes NL's own paths from path-shape detection: `~/.claude/`, `adapters/`, `docs/plans/archive/` paths are not flagged
    - BLOCKS on match (exit 1) with stderr labeled `[heuristic]` (denylist matches stay labeled `[denylist]`)
    - Self-test scenarios: 4-6 new — positive heuristic match (file with `app/api/v1/` path), positive cluster match (file mentioning a fake project name 3+ times), negative case (NL's own `~/.claude/hooks/...` path NOT flagged), negative case (vocabulary allowlist tokens NOT flagged)
- [x] 3. **Layer 3 — `/harness-review` skill extension.** Add a new check section to `adapters/claude-code/skills/harness-review.md` that:
    - Runs `bash adapters/claude-code/hooks/harness-hygiene-scan.sh --full-tree`
    - Reports total match count
    - Lists each match with file path + line + matched pattern
    - Labels each match as `[denylist]` or `[heuristic]`
    - PASS if zero matches; FAIL otherwise (with the matches as findings)
- [x] 4. **Layer 4 — Sanitization helper.** Write `adapters/claude-code/scripts/harness-hygiene-sanitize.sh` (~80-150 lines):
    - Reads scanner output (parsing the standard `<file>:<line>:<text>` format)
    - For each match, proposes a replacement based on pattern class:
        - Project codename → `<your-project>`
        - Customer/business name → `<customer>`
        - Project-internal file path → `<example-path>`
        - Cloud bucket → `<your-bucket>`
        - OAuth client-id → `<your-client-id>`
    - Emits a unified diff to stdout showing proposed changes (does NOT apply them)
    - User reviews and applies via `git apply` workflow
    - Self-test with 4-5 scenarios covering each replacement class
- [x] 5. **Documentation.** Extend `adapters/claude-code/rules/harness-hygiene.md` with a new "Layer 2 heuristic detection" section briefly explaining what the heuristics catch and how to add false-positive exemptions (e.g., add to the NL vocabulary allowlist in the hook).
- [x] 6. **Sync.** Copy changed files from `adapters/claude-code/` to `~/.claude/` per Windows manual-sync rule. Verify with the diff loop. Files: `hooks/harness-hygiene-scan.sh`, `scripts/harness-hygiene-sanitize.sh`, `patterns/harness-denylist.txt`, `rules/harness-hygiene.md`, `skills/harness-review.md`.
- [x] 7. **Manual full-tree scan.** After all changes land, run `bash adapters/claude-code/hooks/harness-hygiene-scan.sh --full-tree` against the current repo. Expected: ZERO matches (the codename scrub from Phase 1d-G left the tree clean per HARNESS-GAP-15 sub-item C). If matches surface, classify as legitimate findings (sanitize) OR false-positives (add allowlist exemption), then re-scan until clean.
- [ ] 8. **Commit on feature branch + push.** Commit on a fresh branch `feat/gap-13-hygiene-scan-expansion`. Push to origin (multi-push covers both remotes per HARNESS-GAP-12 resolution).

## Files to Modify/Create

- `adapters/claude-code/patterns/harness-denylist.txt` — MODIFY (Layer 1: ~6-8 new pattern lines)
- `adapters/claude-code/hooks/harness-hygiene-scan.sh` — MODIFY (Layer 2: new `check_heuristics()` function ~80-120 lines, self-test extensions ~50 lines)
- `adapters/claude-code/skills/harness-review.md` — MODIFY (Layer 3: ~30-50 added lines for new check section)
- `adapters/claude-code/scripts/harness-hygiene-sanitize.sh` — NEW (Layer 4: ~100-150 lines plus ~50-line self-test)
- `adapters/claude-code/rules/harness-hygiene.md` — MODIFY (Layer 2 documentation: ~20-30 added lines)
- `~/.claude/patterns/harness-denylist.txt` — sync (mirror)
- `~/.claude/hooks/harness-hygiene-scan.sh` — sync (mirror)
- `~/.claude/scripts/harness-hygiene-sanitize.sh` — sync (mirror)
- `~/.claude/rules/harness-hygiene.md` — sync (mirror)
- `~/.claude/skills/harness-review.md` — sync (mirror)

## In-flight scope updates

- 2026-05-05: `docs/backlog.md` — atomicity-driven update: HARNESS-GAP-13 absorbed (full historical entry removed from open sections per backlog-plan-atomicity rule). Pointer added to plan path.
- 2026-05-05: `docs/plans/harness-gap-13-hygiene-scan-expansion.md` — plan file itself (task-verifier-flipped checkboxes for Tasks 1, 2).
- 2026-05-05: `docs/plans/harness-gap-13-hygiene-scan-expansion-evidence.md` — evidence file (task-verifier evidence blocks for Tasks 1, 2).

## Assumptions

- The current `harness-hygiene-scan.sh`'s `--self-test` and `--full-tree` modes work correctly (Phase 1d-E-4 confirmed the self-test in commit `f112226`; Phase 1d-G confirmed full-tree shows zero matches after codename scrub in commit `6881712`).
- The heuristic patterns are regex-implementable via POSIX ERE (no negative lookahead, since current scanner uses `grep -iE`). NL-vocabulary allowlist is implemented via a literal grep -iv pass after primary match.
- The harness-review.md skill already runs bash-style checks (Phase 1d-E-4 added the existing structure); adding a new check section follows that established pattern.
- The user's choice to BLOCK on heuristic match (rather than warn) is operative from day one. Any false positives surface as commit-time blocks; first-week tuning may add allowlist entries to lower noise. Override via `git commit --no-verify` is the documented escape hatch.
- `~/.claude/` and `adapters/claude-code/` are kept in sync per the harness-maintenance Windows manual-sync rule.
- The repo is currently clean of harness-hygiene violations after the Phase 1d-G codename scrub (commit `6881712`); Layer 2's manual full-tree scan should produce zero matches at the end of this plan's work.

## Edge Cases

- **Heuristic false-positive on NL's own content.** NL's harness code mentions paths like `~/.claude/hooks/...` and `adapters/...` which are structurally similar to flagged project-internal patterns. Mitigation: heuristic regex explicitly excludes `~/.claude/`, `adapters/`, `docs/plans/archive/` prefix paths via a pre-filter. Self-test covers this.
- **Sanitization helper proposes wrong replacement.** User reviews the unified diff before applying via `git apply`. The helper is propose-only — never auto-applies. Worst case: user discards the proposal.
- **Denylist additions match in new false-positive ways.** Mitigation: only add high-signal patterns (cloud-bucket URLs with environment fragments, OAuth client-id shapes, connection strings with embedded credentials — all have very low false-positive risk on prose). Self-test covers each addition.
- **`/harness-review` weekly run takes too long with full-tree scan.** Current full-tree scan is fast (~2 seconds on this repo). If repo size grows substantially, may need to scope the audit (e.g., skip `node_modules/` more aggressively). Not a blocker today.
- **Sanitization helper called on a file with mixed legitimate + leak content.** Helper reports each match independently; user picks which to accept via diff editing before `git apply`.
- **Repeated-capitalized-term cluster heuristic false-positives on technical terms.** Tokens like `Promise`, `Object`, `Array`, `String`, `Boolean` would match the `[A-Z][a-z]{4,15}` pattern with 3+ occurrences in code-heavy files. Mitigation: vocabulary allowlist includes common JavaScript/TypeScript built-ins; heuristic only fires when ALL occurrences are outside the allowlist.
- **Layer 3 weekly audit surfaces matches that aren't actually leaks** (e.g., legitimate references in old archived content). Mitigation: Layer 3 is reporting-only via `/harness-review`; matches don't block anything; user decides whether to sanitize, allowlist, or accept.
- **Sync drift after this plan ships.** New denylist patterns might land in `adapters/...` but not get synced to `~/.claude/`. Mitigation: Layer 3's weekly full-tree audit will surface this since it runs from the repo. The existing `settings-divergence-detector.sh` SessionStart hook also catches related drift.

## Acceptance Scenarios

n/a — `acceptance-exempt: true` (harness-development plan with no product user).

## Out-of-scope scenarios

n/a

## Testing Strategy

- **Layer 1 (denylist):** `harness-hygiene-scan.sh --self-test` extended with one PASS scenario per new pattern (file containing the pattern → blocked) and one negative scenario per pattern class (file with similar-but-non-matching text → not blocked).
- **Layer 2 (heuristics):** 4-6 new self-test scenarios — positive path-shape match, positive cluster match, negative NL-path-not-flagged, negative vocabulary-token-not-flagged.
- **Layer 3 (full-tree audit):** Manual run of `bash harness-hygiene-scan.sh --full-tree` after all changes land. Expected: ZERO matches against the current repo state (per assumptions).
- **Layer 4 (sanitize helper):** `harness-hygiene-sanitize.sh --self-test` with 4-5 scenarios covering each replacement class (codename, customer, file path, cloud bucket, OAuth client-id). Each scenario exercises a synthetic file → scanner output → expected unified diff.
- **Sync verification:** after Task 6, `diff -q` between adapter source and `~/.claude/` mirror produces no output for each of the 5 files.

## Walking Skeleton

n/a — multi-layer plan; tasks 1-5 are largely independent and can dispatch in parallel (per orchestrator-pattern). Task 6 (sync) waits for 1-5 to complete; Task 7 (manual full-tree scan) waits for sync; Task 8 (commit + push) is final.

## Decisions Log

(Decisions surfaced via AskUserQuestion 2026-05-05)

### Decision: Layer scope — full original (4 layers, ~9-10 hr)
- **Tier:** 1 (reversible — layers can be removed if false-positive rate proves problematic)
- **Surfaced to user:** 2026-05-05 via AskUserQuestion
- **Status:** chosen by user
- **Chosen:** All four layers (denylist + heuristic + full-tree audit + sanitization helper)
- **Alternatives:** Layer 1 only (~1-2 hr), Layers 1+2 (~5-6 hr), Layers 1+2+3 (~7-9 hr)
- **Reasoning:** user matched the original 6-10 hr backlog estimate; Layer 4's sanitization helper, while a nice-to-have, completes the full structural defense the rule promises.
- **To reverse:** any unused layer can be removed in a follow-up commit; each layer is self-contained.

### Decision: Heuristic action — BLOCK on match (consistent with current scanner)
- **Tier:** 2 (affects every commit going forward; partial reversibility — first-week tuning required)
- **Surfaced to user:** 2026-05-05 via AskUserQuestion
- **Status:** chosen by user
- **Chosen:** Block on heuristic match (exit 1, like denylist matches). Override via `git commit --no-verify`.
- **Alternatives:** Warn-only initially (exit 0 with stderr label), promote to block once false-positive rate drops to zero
- **Reasoning:** consistency with current scanner — denylist matches block, heuristic matches block. WARN-on-prose-regex has explicit precedent in the harness (Check 4b) of being ignored. User chose to accept first-week tuning friction in exchange for immediate structural protection.
- **To reverse:** if false-positive rate proves unmanageable in week 1, edit `harness-hygiene-scan.sh` to demote heuristic exit from 1 to 0 (or split into a `--strict` flag that gates blocking). Cost ~10 minutes; the heuristic logic stays.

## Pre-Submission Audit

n/a — Mode: code plan, no class-sweep needed (per `rules/design-mode-planning.md` "When the audit doesn't apply").

## Definition of Done

- [ ] All 8 tasks task-verified PASS
- [ ] All hook + script self-tests PASS (existing scenarios + new Layer 1 + new Layer 2 + new Layer 4)
- [ ] Manual full-tree scan returns ZERO matches against current repo
- [ ] Synced files diff-clean against adapter source (5 files)
- [ ] Plan flipped to Status: COMPLETED (auto-archives via plan-lifecycle.sh)
- [ ] backlog.md updated: HARNESS-GAP-13 moved from "Open work" to "Recently implemented" with commit SHA(s)
- [ ] SCRATCHPAD.md updated to reflect new state
- [ ] Completion report appended to this plan file per `~/.claude/templates/completion-report.md`
