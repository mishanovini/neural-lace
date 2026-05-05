# Plan: HARNESS-GAP-16 — Plan-Closure Validation Gate + `/close-plan` Skill

Status: ACTIVE
Execution Mode: orchestrator
Mode: code
tier: 1
rung: 1
architecture: dialogue-only
frozen: true
prd-ref: n/a — harness-development
Backlog items absorbed: HARNESS-GAP-16
acceptance-exempt: true
acceptance-exempt-reason: Harness-development plan with no product-user surface — purely adds an enforcement gate to the harness's plan-lifecycle hook and a skill that automates closure. The maintainer exercises the harness in subsequent sessions; correct gate + skill behavior is the verification.

## Goal

Close the plan-closure-discipline gap surfaced by the 2026-05-05 stranding incident (the pre-submission-audit-mechanical-enforcement plan sat ACTIVE since 2026-05-03 with all 5 task checkboxes empty despite all 5 tasks shipped on master). Two layers ship together:

1. **Layer 1 — Closure-validation gate.** Refuse the irreversible `Status: ACTIVE → COMPLETED` transition on plan files until closure work is mechanically complete: all task checkboxes flipped, evidence blocks present with `Verdict: PASS`, completion report populated, backlog reconciled, SCRATCHPAD fresh.
2. **Layer 2 — `/close-plan <slug>` skill.** Walks the orchestrator through closure mechanically — surfaces gaps, writes the completion report from the template, updates SCRATCHPAD + backlog, flips Status (which triggers Layer 1 + auto-archive), commits and offers to push. Makes the right path easier than the wrong path.

The gate is a deterministic pre-condition — it runs BEFORE the irreversible action (Status flip + auto-archive). It refuses forward progress until closure work is satisfied. Same shape as `pre-commit-tdd-gate.sh` (refuses bad commits).

## Scope

- IN: New PreToolUse Edit/Write hook fragment that fires on `docs/plans/<slug>.md` Status edits, validates closure preconditions for ACTIVE→COMPLETED transitions, blocks via exit 2 when unmet. New `/close-plan <slug>` skill that automates the closure path. Self-test scenarios for both. Sync to live `~/.claude/`.
- OUT: Migration of the existing `plan-lifecycle.sh` PostToolUse hook (it stays — handles the auto-archive AFTER the gate allows). Closure-validation behavior for terminal statuses other than COMPLETED (DEFERRED / ABANDONED / SUPERSEDED have different semantics — they explicitly admit incomplete work; not gated by this plan). Auto-flip of Status when closure work is complete (skill makes it easy; doesn't auto-fire). Any change to `pre-stop-verifier.sh` (it remains the catch-net for missed-by-gate cases).

## Tasks

- [ ] 1. Author `adapters/claude-code/hooks/plan-closure-validator.sh` as a new PreToolUse hook on `Edit|Write` matching plan files. Detect `Status: ACTIVE → COMPLETED` transitions specifically (not other terminal flips). For matching transitions, run mechanical closure checks: (a) every `- [ ]` in `## Tasks` is now `- [x]`; (b) every task ID has an evidence block in `## Evidence Log` (or sibling `<slug>-evidence.md`) with `Verdict: PASS`; (c) `## Completion Report` section exists with non-empty `Implementation Summary`, `Design Decisions`, `Known Issues` sub-sections; (d) every `Backlog items absorbed:` entry is reconciled in `docs/backlog.md` (item not in open sections OR has explicit deferred-from notation); (e) `SCRATCHPAD.md` mtime within last 60 minutes AND mentions plan slug. Exit 2 with structured stderr + JSON `{"decision": "block", ...}` when any check fails, naming each unmet item. Exit 0 when all pass. Allow non-COMPLETED terminal flips (DEFERRED / ABANDONED / SUPERSEDED) without these checks. ~150-220 lines plus self-test.
- [ ] 2. Wire the new hook into `adapters/claude-code/settings.json.template` PreToolUse Edit|Write chain. Mirror to `~/.claude/settings.json`.
- [ ] 3. Author `adapters/claude-code/skills/close-plan.md` (NEW). Skill walks the orchestrator through plan closure mechanically: validates which Layer 1 checks currently pass, surfaces gaps with specific actions (`invoke task-verifier on Task 3`, `update SCRATCHPAD`), writes the completion report from `~/.claude/templates/completion-report.md`, updates SCRATCHPAD + backlog, flips Status (which triggers Layer 1 + auto-archive), commits, offers to push. ~100-150 lines.
- [ ] 4. Add self-test scenarios for the hook (~10 scenarios): all-checks-pass-allows, missing-checkbox-blocks, missing-evidence-blocks, missing-completion-report-blocks, unreconciled-backlog-blocks, stale-scratchpad-blocks, transition-to-DEFERRED-allows, transition-to-ABANDONED-allows, transition-to-SUPERSEDED-allows, non-Status-edit-passes-through.
- [ ] 5. Update `adapters/claude-code/rules/vaporware-prevention.md` enforcement map with one new row: "Plan-closure validation gate" → `plan-closure-validator.sh` PreToolUse + `close-plan` skill (Phase 1d-H, 2026-05-05).
- [ ] 6. Sync `adapters/claude-code/{hooks,skills}/` files to `~/.claude/{hooks,skills}/`. Run `--self-test` on both copies. Verify with the diff loop from `harness-maintenance.md`.
- [ ] 7. Update `docs/build-doctrine-roadmap.md` Quick status table: GAP-16 row from NOT STARTED → DONE (after this plan completes). Add a Recent Updates entry naming the closure-validator + close-plan skill ship date.

## Files to Modify/Create

- `adapters/claude-code/hooks/plan-closure-validator.sh` — NEW (~150-220 lines + self-test)
- `adapters/claude-code/skills/close-plan.md` — NEW (~100-150 lines)
- `adapters/claude-code/settings.json.template` — MODIFY (one PreToolUse Edit|Write entry added)
- `adapters/claude-code/rules/vaporware-prevention.md` — MODIFY (one row added to enforcement map)
- `~/.claude/hooks/plan-closure-validator.sh` — NEW (sync from adapter)
- `~/.claude/skills/close-plan.md` — NEW (sync from adapter)
- `~/.claude/settings.json` — MODIFY (mirror of template change)
- `docs/build-doctrine-roadmap.md` — MODIFY (Quick status row + Recent updates entry; happens at plan completion, not during build)

## In-flight scope updates

(none yet)

## Assumptions

- `plan-lifecycle.sh` continues to handle the PostToolUse auto-archive on Status: terminal transitions. The new pre-validator runs BEFORE plan-lifecycle and gates the Status edit itself.
- The closure-validation checks are mechanical (file-system / regex level) — no LLM-assisted substance review. Substance review of completion reports is out of scope; if an Implementation Summary is "stub", that's acceptable for this gate; reviewers catch substance issues separately.
- The gate fires on Edit/Write directly to `docs/plans/<slug>.md`. It does NOT fire on `git mv` operations during archival (archive operations move the file, they don't edit it).
- The skill's auto-population of completion reports relies on the template at `~/.claude/templates/completion-report.md` being current. The skill reads the template, fills sections it can fill mechanically (commit SHAs, file lists from the plan's `## Files to Modify/Create`), and prompts the orchestrator for sections that require judgment (Design Decisions, Known Issues).
- The 60-minute SCRATCHPAD freshness window is consistent with `bug-persistence-gate.sh`'s waiver-file freshness window.

## Edge Cases

- **Plan transitions ACTIVE → DEFERRED → COMPLETED.** The intermediate DEFERRED step is allowed without closure checks (DEFERRED admits incomplete work). The subsequent DEFERRED → COMPLETED transition is gated like ACTIVE → COMPLETED is — same closure preconditions.
- **Multiple Status fields in the same file.** Plan files have exactly one top-level `Status:` line per the template. The validator reads the FIRST `Status:` line found in the first 50 lines of the file. If the file has two (e.g., a quoted Status: line in a code block as documentation), the validator may misread. Guard: read only lines outside fenced code blocks.
- **Orchestrator runs `/close-plan` then immediately the validator fires on the Status flip.** Skill writes completion report + reconciles backlog + updates SCRATCHPAD + flips Status. Validator runs on the Status flip. All preconditions are now satisfied; gate allows. Round-trip latency: ~1-2 seconds, well within the 60-min freshness window.
- **Backlog reconciliation ambiguity.** "Item not in open sections" requires defining open sections. The validator checks for the presence of the absorbed-item slug under any heading containing "Recently implemented" / "Completed" / "Resolved" / "(deferred from" — multiple match patterns to handle backlog format variations.
- **Plan with `Backlog items absorbed: none`.** Skip the backlog-reconciliation check entirely.
- **Race condition: orchestrator commits closure work then immediately Edit-flips Status.** SCRATCHPAD mtime check requires mtime within last 60 min — the work was just done so SCRATCHPAD is fresh, gate allows.

## Acceptance Scenarios

(plan is acceptance-exempt — see header `acceptance-exempt-reason`)

## Out-of-scope scenarios

(none — acceptance-exempt)

## Testing Strategy

`--self-test` flag exercises 10 scenarios per Task 4 above. Manual verification: after the hook ships, attempt to flip Status on a plan with unfilled tasks → gate should block with specific list of unmet items. Then complete the items → gate should allow. Run on the GAP-16 plan itself once it's complete (eat-our-own-dogfood verification).

## Walking Skeleton

(n/a)

## Decisions Log

(populated during build)

## Pre-Submission Audit

S1 (Entry-Point Surfacing): swept — every behavior change in Goal/Scope is cited at task entry points
S2 (Existing-Code-Claim Verification): swept — `plan-lifecycle.sh` PostToolUse behavior verified; `pre-stop-verifier.sh` Check 4d (HARNESS-GAP-01) noted as related-but-different mechanism (different timing, different scope)
S3 (Cross-Section Consistency): swept — Goal, Scope, Tasks, Files-to-Modify all agree on the two-layer scope
S4 (Numeric-Parameter Sweep): swept — 60-min SCRATCHPAD freshness consistent with bug-persistence-gate; ~150-220 / ~100-150 / ~10 line and scenario estimates internally consistent
S5 (Scope-vs-Analysis Check): swept — every "Add/Modify" verb in Goal/Scope is matched by a Files-to-Modify entry; OUT clause correctly excludes pre-stop-verifier and DEFERRED/ABANDONED/SUPERSEDED gating

## Definition of Done

- [ ] All 7 tasks task-verifier-flipped to `[x]`
- [ ] Each task has an evidence block with `Verdict: PASS` in the companion `-evidence.md` file
- [ ] `--self-test` flag exercises 10 scenarios and exits 0
- [ ] Live `~/.claude/{hooks,skills}/` synced
- [ ] `docs/build-doctrine-roadmap.md` Quick status row updated to DONE
- [ ] Status: ACTIVE → COMPLETED transition triggers auto-archive (and proves the gate fires correctly when invoked on this very plan)

## Evidence Log

(populated by task-verifier in the closure phase)

## Completion Report

(populated by orchestrator at closure)
