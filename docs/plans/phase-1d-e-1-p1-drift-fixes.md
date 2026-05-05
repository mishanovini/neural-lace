# Plan: Phase 1d-E-1 — P1 drift fixes

Status: ACTIVE
Execution Mode: orchestrator
Mode: code
Backlog items absorbed: HARNESS-DRIFT-01, HARNESS-DRIFT-02, HARNESS-GAP-09
acceptance-exempt: true
acceptance-exempt-reason: Harness-development plan; no product-user surface to verify at runtime. Verification is per-hook `--self-test` invocations + manual round-trip exercising the SessionStart account-switching hook against a synthetic config + plan-reviewer self-test PASS for the new regex narrowing.
tier: 2
rung: 1
architecture: coding-harness
frozen: false
prd-ref: n/a — harness-development

## Context

Phase 1d-E is the "harness cleanup" follow-up to the eight Build Doctrine §6 first-pass mechanism phases (1d-C-1 through 1d-C-4, all shipped). 1d-E-1 is the smallest sub-batch: three quick-win drift / false-positive fixes that have been documented in the backlog but not yet addressed.

**HARNESS-DRIFT-01 — Six Gen-6 hooks not wired in settings.json (P1).** Per the 2026-04-27 audit, six Gen-6 hooks (`goal-extraction-on-prompt`, `goal-coverage-on-stop`, `imperative-evidence-linker`, `transcript-lie-detector`, `vaporware-volume-gate`, `automation-mode-gate`) existed on disk but were not referenced from settings.json. Audit at plan-creation time confirms five of six are now wired in both template and live (likely landed in interim sessions); the remaining gap is `automation-mode-gate.sh`, which is in the template (line 101) but missing from the live `~/.claude/settings.json`. This sub-task is largely a verification + close-out — the heavy work was done elsewhere; we just need to confirm closure and document residual items.

**HARNESS-DRIFT-02 — SessionStart account-switching hook is hardcoded (P1).** Per `docs/backlog.md`, the SessionStart hook at `settings.json:273-279` (and the push-time variant at line 178) is hardcoded against a literal directory substring. Per `docs/harness-architecture.md:81` and the documented contract, the hook should call `~/.claude/scripts/read-local-config.sh accounts` (or the sourced equivalent `nl_accounts_match_dir`), which reads the user's `~/.claude/local/accounts.config.json` and returns the matched account. The script already exists and has a working `match-dir` mode. The fix is to replace the hardcoded inline body with a call to the script.

**HARNESS-GAP-09 — `plan-reviewer.sh` Check 1 + Check 5 false-positives on meta-plans (P3).** Two narrow regex tightenings:
- Check 1 (undecomposed sweep) trips on "all" / "every" inside `## Definition of Done` sections, which are not task lists. Fix: skip Check 1 on lines under non-Tasks sections.
- Check 5 (runtime task without test spec) trips on the word `column` (matched by the runtime-keyword regex) when documentation says "Markdown table column" rather than "database column". Fix: context-aware regex that requires database-context tokens nearby.

These false-positives have been worked around by rephrasing plan files multiple times; the plan reviewer agent caught itself dodging the noise during Phase 1d-C-4 plan authoring (see Task 1 conversation in this session). Fixing the regex once eliminates the workaround.

## Goal

Three small mechanism / wiring fixes ship in one coherent unit:

1. **`plan-reviewer.sh` Check 1 + Check 5 narrowed.** Section-aware filter for Check 1 (sweep language only flagged under `## Tasks` or other task-list sections; Definition of Done / Pre-Submission Audit / Out-of-scope sections are skipped). Context-aware filter for Check 5 (the runtime-keyword regex requires adjacency to database-context tokens like `migration`, `INSERT`, `SELECT`, `column type`, `table schema`; documentation tokens like `Markdown table`, `template column`, `enforcement column` are skipped).
2. **HARNESS-DRIFT-02 replacement.** SessionStart account-switching hook in `settings.json.template` and live `settings.json` reads from `~/.claude/local/accounts.config.json` via the existing `read-local-config.sh match-dir` script, replacing the inline hardcoded substring match. Accounts not configured fall back gracefully (no auth switch).
3. **HARNESS-DRIFT-01 audit close.** Verify all 6 named hooks are wired (template + live); add the one residual missing wiring (`automation-mode-gate` in live); document the close-out in the backlog.

Plus enabling work:
- Decision 021 (DRIFT-02 resolution: account-switch reads from config, not hardcoded; documents the fallback behavior when config is absent).
- Updates to `docs/backlog.md` marking HARNESS-GAP-09 and HARNESS-DRIFT-01/02 as IMPLEMENTED.
- Updates to `docs/harness-architecture.md` if any inventory rows need adjustment.
- Re-run `plan-reviewer.sh --self-test` to confirm no regressions; add new self-test scenarios that exercise the section-aware + context-aware filters.

## Scope

**IN:**
- `adapters/claude-code/hooks/plan-reviewer.sh` — EDIT (Check 1 section-awareness + Check 5 context-awareness + 4 new self-test scenarios).
- `~/.claude/hooks/plan-reviewer.sh` — EDIT (live mirror).
- `adapters/claude-code/settings.json.template` — EDIT (replace hardcoded SessionStart hook with config-driven; ensure `automation-mode-gate.sh` wiring is consistent with live).
- `~/.claude/settings.json` — EDIT (live mirror; add `automation-mode-gate` if missing; replace hardcoded SessionStart hook).
- `docs/decisions/021-drift-02-account-switch-config-driven.md` — NEW.
- `docs/DECISIONS.md` — EDIT (add row for 021).
- `docs/backlog.md` — EDIT (move HARNESS-GAP-09, HARNESS-DRIFT-01, HARNESS-DRIFT-02 to Closed/Implemented section with commit-SHA citations).
- `docs/harness-architecture.md` — EDIT (any inventory annotations triggered by the changes).

**OUT:**
- HARNESS-GAP-14 template-vs-live reconciliation (the broader 5-hook divergence beyond DRIFT-01) — separate plan (Phase 1d-E-2).
- HARNESS-GAP-08 spawn_task report-back — separate plan (Phase 1d-E-2 candidate).
- HARNESS-GAP-10 sub-gaps A/B/C/F/H — separate plan (Phase 1d-E-2).
- HARNESS-GAP-13 hygiene-scan expansion — separate plan (Phase 1d-E-2).
- HARNESS-GAP-15 un-archived plans + codename scrub — separate plan (Phase 1d-E-3).
- HARNESS-GAP-10 sub-gap G definition-on-first-use — separate plan (Phase 1d-F).
- Reviewer-calibration tracker (HARNESS-GAP-11) — gated on telemetry; deferred.

## Tasks

- [ ] **1. plan-reviewer.sh Check 1 + Check 5 narrowing.** EDIT `adapters/claude-code/hooks/plan-reviewer.sh` to add: (a) Check 1 section-awareness — track current `## ` heading as we scan; only flag sweep language when the line is under the `## Tasks` heading (or any heading containing "Task"); (b) Check 5 context-awareness — the runtime-keyword regex narrowed so the documentation-context tokens only match when adjacent (within the same line or the next line) to database-context tokens. Add 4 new self-test scenarios. Test:/Runtime verification: run `bash plan-reviewer.sh --self-test` after each edit; the 4 new scenarios must PASS and existing scenarios must not regress. Mirror to `~/.claude/hooks/`. Single commit.

- [ ] **2. HARNESS-DRIFT-02 — SessionStart account-switch reads from config.** EDIT `adapters/claude-code/settings.json.template` to replace the hardcoded SessionStart hook body with a config-driven version: source `read-local-config.sh`, call `nl_accounts_match_dir "$PWD"` (or the equivalent `bash read-local-config.sh match-dir "$PWD"`), parse the account-tag + username, run `gh auth switch --user <name>`. Falls back to no-op when config is absent or no match. Same edit applied to the push-time variant if present. Mirror to live `~/.claude/settings.json`. Single commit.

- [ ] **3. HARNESS-DRIFT-01 audit close.** Verify each of the six DRIFT-01 hooks is wired in BOTH template AND live: `goal-extraction-on-prompt`, `goal-coverage-on-stop`, `imperative-evidence-linker`, `transcript-lie-detector`, `vaporware-volume-gate`, `automation-mode-gate`. For any missing wiring (specifically `automation-mode-gate` in live, per audit at plan-creation), add the wiring. Use `settings-divergence-detector.sh` to confirm the divergence is closed for these hooks (or document any that remain — those become HARNESS-GAP-14's scope). Single commit.

- [ ] **4. Decision 021 + DECISIONS index + backlog cleanup + inventory updates.** Land Decision 021 (DRIFT-02 resolution: SessionStart account-switching hook is config-driven, falls back to no-op when config is absent or no match; the literal-substring approach is rejected per its brittleness). Update `docs/DECISIONS.md` with the row. Move HARNESS-GAP-09, HARNESS-DRIFT-01, HARNESS-DRIFT-02 in `docs/backlog.md` to a "Recently implemented" section with their resolution commit SHAs. Update `docs/harness-architecture.md` inventory if any rows need adjustment. Single commit.

## Files to Modify/Create

- `adapters/claude-code/hooks/plan-reviewer.sh` — EDIT.
- `~/.claude/hooks/plan-reviewer.sh` — EDIT (gitignored mirror; not committed).
- `adapters/claude-code/settings.json.template` — EDIT.
- `~/.claude/settings.json` — EDIT (gitignored; not committed).
- `docs/decisions/021-drift-02-account-switch-config-driven.md` — NEW.
- `docs/DECISIONS.md` — EDIT.
- `docs/backlog.md` — EDIT.
- `docs/harness-architecture.md` — EDIT.

## In-flight scope updates

(none yet — orchestrator may add the evidence file companion as in 1d-C-4)

## Assumptions

- `read-local-config.sh` and its `nl_accounts_match_dir` function (or `match-dir` mode) are stable and tested. The script's self-test scenarios already cover the work-org / personal / no-match cases.
- The `~/.claude/local/accounts.config.json` schema is documented in `examples/accounts.config.example.json`. Users who haven't created the file get the no-op fallback (the literal-substring case is no longer hardcoded; the absence of config means no auth switch happens).
- Plan-reviewer `--self-test` is the canonical regression check; passing it confirms no behavioral regressions on the 20+ existing scenarios.
- HARNESS-DRIFT-01 has been mostly resolved already (5 of 6 hooks wired in both layers as of audit); only `automation-mode-gate` in live needs attention. If the audit reveals more gaps, surface them in the in-flight scope updates rather than expanding scope mid-build.
- The settings.json.template edit can land alongside the live edit in the same commit; the live file is gitignored so only the template + the commit message are visible in git history.

## Edge Cases

- **User has no `~/.claude/local/accounts.config.json`.** The replaced SessionStart hook degrades to no-op (no `gh auth switch` runs). The user keeps whichever account `gh` is currently logged into. No error, no surprising behavior.
- **`accounts.config.json` exists but the working directory matches no account.** Same as above — no-op. The user can `gh auth switch` manually if needed.
- **Plan-reviewer regex narrowing accidentally allows real sweep language to slip through.** The 4 new self-test scenarios cover both directions: PASS scenarios with documentation-context that should NOT trip; FAIL scenarios with real sweeps under `## Tasks` that SHOULD still trip. Running `--self-test` after every edit confirms.
- **Live `~/.claude/settings.json` has divergence beyond DRIFT-01's six hooks.** That's HARNESS-GAP-14's scope — out of this plan. The settings-divergence-detector hook will surface the residual divergence at next session start.
- **Multiple matches in `accounts.config.json` for one directory pattern.** The `nl_accounts_match_dir` script's existing logic returns the first match; the SessionStart hook honors that. If the user has overlapping patterns, they fix the config; the hook is not responsible for arbitrating.
- **`gh` is not installed or `gh auth switch` fails.** The replaced hook captures stderr and degrades gracefully (no session-start abort). Mirrors the existing fallback behavior.

## Acceptance Scenarios

(none — `acceptance-exempt: true`. Verification is via per-hook `--self-test` invocations + manual round-trip exercising the new SessionStart hook against a synthetic config + plan-reviewer self-test PASS.)

## Out-of-scope scenarios

- HARNESS-GAP-14 broader template-vs-live reconciliation — Phase 1d-E-2.
- Cross-account credential safety beyond the `gh auth switch` invocation — out of scope; that lives in `security.md`.

## Testing Strategy

Each task is verified by `task-verifier`. Specific testing per task:

1. **Task 1 (Check 1 + Check 5):** run `bash plan-reviewer.sh --self-test` after the edit. The 4 new scenarios must PASS; all existing scenarios must continue to PASS. As an end-to-end sanity check, run `bash plan-reviewer.sh` against the just-archived `phase-1d-c-4-comprehension-gate.md` plan file and confirm no false-positive findings. Run against this plan file (1d-E-1) and confirm clean.
2. **Task 2 (DRIFT-02):** create a temporary synthetic `~/.claude/local/accounts.config.json` with two test accounts mapped to two test dir patterns. cd into one of the patterns, source the SessionStart hook, confirm it switches to the right account. cd into a non-matching path, confirm no switch. Document the round-trip in the evidence block.
3. **Task 3 (DRIFT-01 close):** run `settings-divergence-detector.sh` after the edit. Confirm the 6 named hooks no longer appear in the divergence report (anything remaining is HARNESS-GAP-14's scope, not 1d-E-1's).
4. **Task 4 (decisions + backlog cleanup):** plan-reviewer runs cleanly on the plan file. Decision 021 file structure matches harness convention. backlog.md shows the three items in a closed/implemented section with commit SHAs.

## Walking Skeleton

The minimum viable shape: Task 1 alone (the plan-reviewer false-positive fix) ships a measurable improvement to plan authoring ergonomics. Tasks 2-3 are independent of Task 1 and can be deferred without losing the value of Task 1. Task 4 is documentation cleanup. So the skeleton is Task 1 → confirm value → continue.

## Decisions Log

(populated during implementation per Mid-Build Decision Protocol; Decision 021 is landed by Task 4 as a Tier 2 ADR documenting the DRIFT-02 resolution.)

## Pre-Submission Audit

- S1 (Entry-Point Surfacing): swept, 0 matches outside Sections 1-10; tasks 1-4 cite each behavior change at the corresponding entry point (Files-to-Modify + Tasks).
- S2 (Existing-Code-Claim Verification): swept, 5 claims (read-local-config.sh exists; nl_accounts_match_dir function; plan-reviewer.sh Check 1 + Check 5 regex; settings-divergence-detector.sh; settings.json.template line numbers for SessionStart hook) — all 5 verified at audit time against the actual files.
- S3 (Cross-Section Consistency): swept, 0 contradictions — the 6-hook DRIFT-01 list, the 4-task decomposition, and the file paths are stated consistently across Goal / Tasks / Edge Cases.
- S4 (Numeric-Parameter Sweep): swept for [4 self-test scenarios, 6 hooks audited, 3 backlog items absorbed] — all values consistent throughout.
- S5 (Scope-vs-Analysis Check): swept, 0 contradictions — every `Add` / `Modify` verb in the analysis sections targets a file in `## Files to Modify/Create`; Scope OUT items (GAP-14, GAP-08, GAP-10 sub-gaps, GAP-13, GAP-15, sub-gap G) are not contradicted by any prescription in the analysis.

## Definition of Done

- [ ] All 4 tasks task-verified PASS.
- [ ] plan-reviewer self-test PASS with new scenarios added.
- [ ] settings-divergence-detector reports no DRIFT-01 hook divergence.
- [ ] HARNESS-DRIFT-02 fix exercised end-to-end against a synthetic config.
- [ ] Decision 021 landed and indexed.
- [ ] Backlog reflects HARNESS-GAP-09, HARNESS-DRIFT-01, HARNESS-DRIFT-02 as IMPLEMENTED with commit SHAs.
- [ ] Plan archived (Status: COMPLETED → auto-archive).
