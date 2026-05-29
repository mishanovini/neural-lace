# Plan: Harness Hygiene v2 — Information Architecture + Discoverability + Hygiene Gate

Status: ACTIVE
Mode: code
Execution Mode: orchestrator
tier: 1
rung: 1
architecture: harness-only
frozen: false
prd-ref: n/a — harness-development
acceptance-exempt: true
acceptance-exempt-reason: harness-internal work — the "user" is the maintainer; self-tests and CI golden checks are the acceptance artifact
Backlog items absorbed: none

## Goal

Close the content-architecture layer of the harness. The mechanism layer (40+ hooks) is well-developed; the *where each kind of content belongs* layer was missing. Two recurring failure modes drove the need: (1) CLAUDE.md bloat (content accumulating in the most-loaded context, duplicating canonical files), and (2) orphaned content (the agent asking for credentials/personas/details that were already documented at a known canonical path).

Ship as 3 atomic PRs in dependency order, all against `pt/master` then cherry-picked to personal via the existing `sync-pt-to-personal.sh` script. Components 1+6 (PR 1) land the doctrine foundation; Components 3+4 (PR 2) add in-band signals at session boundaries; Components 2+5 (PR 3) add the CLAUDE.md hygiene gate + weekly cadence.

## Scope

- IN:
  - New rule at `adapters/claude-code/rules/information-architecture.md` (Component 1)
  - New SessionStart hook `session-start-discovery-cheatsheet.sh` (Component 4)
  - Extension to `principles-compliance-gate.sh` adding CRED (credential-asking) detection class (Component 3)
  - New pre-commit hook `claude-md-hygiene-gate.sh` (Component 2, lands in PR 3)
  - New scheduled task installer `install-weekly-hygiene-task.ps1` (Component 5, lands in PR 3)
  - Wiring in `adapters/claude-code/settings.json.template` for new SessionStart and PreToolUse hooks
  - INDEX.md row for the new rule
  - Verification that `evals/golden/rules-index-coverage.sh` golden test enforces sync (Component 6 — already satisfied; this PR verifies the new row joins the CI enforcement)
  - Live-mirror sync at `~/.claude/{rules,hooks}/`
- OUT:
  - Block-mode for the new CRED detection (initially warn-only; flip after calibration data)
  - Block-mode for the new CLAUDE.md hygiene gate (initially warn-only; flip after calibration data)
  - Backfilling CLAUDE.md content extraction (CLAUDE.md is already at 188 lines per PR #48 cleanup; this initiative defends the floor, doesn't re-extract)
  - Downstream-project propagation (Neural Lace canonical lands first; downstream projects opt in separately)

## Tasks

- [x] 1. PR 1 — Create `rules/information-architecture.md` + INDEX.md row; verify `evals/golden/rules-index-coverage.sh` passes — **Verification: mechanical** — `evals/golden/rules-index-coverage.sh` PASS; landed in #51 (PT master `38a6ea9`, personal `b237cc8`)
- [ ] 2. PR 2 — Create `session-start-discovery-cheatsheet.sh` (5-scenario self-test) + extend `principles-compliance-gate.sh` with CRED detection (6 new self-test scenarios, 16 total PASS) + wire cheatsheet hook in `settings.json.template` — **Verification: mechanical** — both hooks' `--self-test` PASS; live mirror byte-identical
- [ ] 3. PR 3 — Create `claude-md-hygiene-gate.sh` pre-commit (warn-mode initially; size + rule-body-shape + duplication detection; ≥ 5 self-test scenarios) + create `install-weekly-hygiene-task.ps1` + wire hygiene gate in `settings.json.template` PreToolUse Bash chain — **Verification: mechanical** — hook `--self-test` PASS; weekly task installer dry-runs cleanly

## Files to Modify/Create

- `adapters/claude-code/rules/information-architecture.md` — NEW (PR 1, shipped)
- `adapters/claude-code/rules/INDEX.md` — MODIFY (PR 1, shipped) — add row for information-architecture
- `adapters/claude-code/hooks/session-start-discovery-cheatsheet.sh` — NEW (PR 2)
- `adapters/claude-code/hooks/principles-compliance-gate.sh` — MODIFY (PR 2) — add CRED detection class (warn-only) + 6 self-test scenarios
- `adapters/claude-code/hooks/claude-md-hygiene-gate.sh` — NEW (PR 3)
- `adapters/claude-code/scripts/install-weekly-hygiene-task.ps1` — NEW (PR 3)
- `adapters/claude-code/settings.json.template` — MODIFY (PR 2 + PR 3) — wire SessionStart cheatsheet + PreToolUse hygiene gate
- `docs/plans/harness-hygiene-2-2026-05-29.md` — THIS plan file (lands inline with PR 2 commit per scope-enforcement-gate option "open a new plan")

## Assumptions

- The CLAUDE.md cleanup PR #48 already merged (188 lines, under the 200-line ceiling), so PR 3's gate will not false-fire on the current state.
- The 9-item git-bestpractices initiative has shipped (PRs #43-#49 all merged); no open PRs interfere.
- `sync-pt-to-personal.sh` from PR #44 continues to work for cross-fork cherry-picking with tree-equivalence verification.
- The `evals/golden/rules-index-coverage.sh` golden test (already wired in `evals.yml`) bidirectionally enforces the rule-file ↔ INDEX row relationship; Component 6 is therefore already satisfied, and PR 1's verification work was to confirm the new row joined the CI enforcement.
- Credentials-reference doc at `~/.claude/local/credentials-reference.md` exists per the established convention (per CLAUDE.md `## Credentials Reference` section); the CRED guard's stderr reminder points at this canonical path.
- Misha's "PT canonical, personal synced via cherry-pick + non-force direct push" posture continues; no force-push, no `--no-verify` shortcuts.

## Edge Cases

- **Concurrent session interference.** During PR 2 work, a separate session was performing 9-item-initiative closure work on `close/git-bestpractices-9-item-initiative` branch; the harness's branch-switching surfaced this. Recovery via clean re-checkout + re-application of edits.
- **Scope-enforcement-gate firing on legitimate harness-dev work.** The hygiene-2 initiative is itself the kind of harness-improvement work the gate is designed to guard. This plan file resolves the gate by declaring the initiative's scope explicitly.
- **CRED detection false-positive on documentation prose.** The carve-out (mentions of credentials-reference, .env.local, gh auth, canonical-source patterns) exempts messages that are *documenting* the convention rather than asking. Self-test scenario "cred ai-feature mention not flagged" locks this in.
- **Cheatsheet emitting on every session start.** Cost is one short stdout block per session start; benefit is the routing map being in the loaded context BEFORE any orphan-content failure mode can fire. Tradeoff resolved in favor of always-emit (no debounce).
- **Live mirror divergence on `~/.claude/settings.json`.** The live settings.json on each machine may have local customizations beyond the template. This plan does NOT modify the live `~/.claude/settings.json` automatically — the template change propagates on next `install.sh` run, and manual sync of the new SessionStart wire-in is documented.

## Testing Strategy

- **PR 1:** `evals/golden/rules-index-coverage.sh` golden test (PASS — 51 rules in sync). Manual verification that the rule is ≤ 200 lines (110 actual).
- **PR 2:** `principles-compliance-gate.sh --self-test` (16 scenarios PASS, including 6 new CRED scenarios with one regex hardening required and applied). `session-start-discovery-cheatsheet.sh --self-test` (5 scenarios PASS — live-mirror-present, credentials-line-present, info-arch-line-present, repo-subtree-fallback, no-index-anywhere). JSON validity of `settings.json.template` via `jq empty`. Live mirror byte-identical verification via `diff -q`.
- **PR 3:** `claude-md-hygiene-gate.sh --self-test` (≥ 5 scenarios — clean / size-warn / rule-body-shape / duplicate-found / under-threshold). `install-weekly-hygiene-task.ps1` dry-run output sanity-check.
- **All PRs:** CI workflow `evals.yml` runs all golden tests on every PR. CI workflow `hooks-selftest.yml` runs `--self-test` on every modified hook.

## Decisions Log

### Decision: warn-only initial mode for CRED detection
- **Tier:** 1
- **Status:** proceeded with recommendation
- **Chosen:** CRED detection class is warn-only (never blocks), with in-band stderr reminder pointing at `~/.claude/local/credentials-reference.md`.
- **Alternatives:** (a) Block-mode from day 1. (b) Separate hook for credential-asking (not part of principles-compliance-gate).
- **Reasoning:** Per the user's spec — "Mode: WARN initially (logged + surfaced); after 24 hours, decide whether to BLOCK." Heuristic detection of credential-asking phrases is high-confidence but the carve-out logic (sentence is documenting the convention vs asking for a credential) is heuristic. Block-mode without calibration would erode trust in the gate per Decision Principle 6. The principles-compliance-gate is the right home because it already has the Stop-hook infrastructure (transcript-reading, warn/block modes, retry-guard, logging) and the credential-asking shape is conceptually a small Rule-0 (honesty) instance (asking for a credential you don't actually need to ask for).
- **Checkpoint:** N/A
- **To reverse:** flip CRED to block-eligible in `detect_violations()` and update the BLOCK_ELIGIBLE computation; one commit.

### Decision: SessionStart cheatsheet is hand-maintained, not auto-derived from INDEX.md
- **Tier:** 1
- **Status:** proceeded with recommendation
- **Chosen:** The cheatsheet's 14 entries are hand-maintained in the hook script.
- **Alternatives:** Auto-derive entirely from INDEX.md.
- **Reasoning:** Auto-derivation would emit 50+ lines and defeat the purpose. The cheatsheet is meant to be SHORT (skimmed in 5 seconds). The 14 hand-curated entries are stable (the meta-categories don't change frequently); when a new content kind emerges, the information-architecture rule itself documents the addition path, and the cheatsheet is updated in the same change. The cheatsheet trades comprehensiveness for skim-ability.
- **Checkpoint:** N/A
- **To reverse:** replace the hand-maintained block with awk/sed extraction from INDEX.md.

## Definition of Done

- [ ] All 3 PRs merged to PT master with tree-equivalent commits on personal/master
- [ ] All hook `--self-test` invocations PASS
- [ ] CI golden tests PASS on every PR (including PR-template-check)
- [ ] CLAUDE.md hygiene gate is warn-mode initially (calibration deferred)
- [ ] Live mirror at `~/.claude/` byte-identical to repo for every modified hook
- [ ] SCRATCHPAD.md updated with final state
- [ ] Status: COMPLETED set on this plan file (triggers auto-archival via plan-lifecycle.sh)
