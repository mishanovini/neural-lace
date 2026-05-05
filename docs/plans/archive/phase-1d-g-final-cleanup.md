# Plan: Phase 1d-G — Final cleanup + master merge prep

Status: COMPLETED
Execution Mode: orchestrator
Mode: code
Backlog items absorbed: HARNESS-GAP-14 sub-item C, HARNESS-GAP-14-followups, rules-vs-hooks restructuring (observed-errors-first.md convert)
acceptance-exempt: true
acceptance-exempt-reason: Harness-development plan; no product-user surface to verify at runtime. Verification is per-task task-verifier PASS + harness-hygiene-scan clean output (full-tree) + settings-divergence-detector clean output.
tier: 2
rung: 1
architecture: coding-harness
frozen: true
prd-ref: n/a — harness-development

## Context

Final cleanup batch before master merge. Three items combined:

1. **HARNESS-GAP-14 sub-item C** — Codename scrub. 15 hits in 5 committed decision/review files surfaced when Phase 1d-E-4 tightened the scanner exemption logic. Files: 001-public-release-strategy.md, 002-attribution-only-anonymization.md, 013-default-push-policy.md, 2026-04-27-agent-teams-conflict-analysis.md, 2026-05-03-build-doctrine-integration-gaps.md. Right-sized P3 distribution-readiness, NOT security. Scrub-in-place chosen over orphan-commit history rewrite.

2. **HARNESS-GAP-14-followups** — 4 P3 SessionStart/UserPromptSubmit divergences from the GAP-14 audit's out-of-scope set: SessionStart compact-recovery per-project paths; automation-mode initializer missing in live; legacy claude-config path in template; UserPromptSubmit title-bar automation-mode awareness.

3. **Rules-vs-hooks restructuring (observed-errors-first.md convert)** — Per Phase 1d-E-2 audit, observed-errors-first.md is ~80% hook-enforced. Convert to stub-style restructuring mirroring vaporware-prevention.md.

The 4 rules-split candidates (acceptance-scenarios, agent-teams, design-mode-planning, testing) and the substantive new mechanisms (GAP-08 spawn_task report-back, GAP-13 hygiene-scan expansion) are deferred to a future session — too large for one focused phase.

## Goal

Three deliverables ship in one coherent batch:

1. Scrub the 15 codename hits from 5 committed files; full-tree scanner reports zero matches.
2. Address the 4 GAP-14-followups as either fix-or-defer with rationale; settings-divergence-detector reports clean (or only intentional, documented divergence).
3. Convert observed-errors-first.md to a stub mirroring vaporware-prevention.md.
4. Update backlog noting truly-deferred items (GAP-08, GAP-13, 4 rule splits) with explicit rationale.

After this phase ships, the branch is master-merge-ready.

## Scope

**IN:**
- `docs/decisions/001-public-release-strategy.md` — EDIT (sanitize identifiers)
- `docs/decisions/002-attribution-only-anonymization.md` — EDIT (sanitize identifiers)
- `docs/decisions/013-default-push-policy.md` — EDIT (sanitize identifiers)
- `docs/reviews/2026-04-27-agent-teams-conflict-analysis.md` — EDIT (sanitize identifiers)
- `docs/reviews/2026-05-03-build-doctrine-integration-gaps.md` — EDIT (sanitize identifiers)
- `adapters/claude-code/settings.json.template` — EDIT (GAP-14-followups items)
- `~/.claude/settings.json` — EDIT (GAP-14-followups; gitignored mirror)
- `adapters/claude-code/rules/observed-errors-first.md` — REWRITE as stub
- `~/.claude/rules/observed-errors-first.md` — sync target
- `docs/backlog.md` — EDIT (mark items closed; explicit deferral notes for GAP-08/GAP-13/4-rule-splits)
- `docs/decisions/025-*.md` — NEW if any structural decision

**OUT:**
- HARNESS-GAP-08 spawn_task report-back — substantial new mechanism design, deferred to fresh session
- HARNESS-GAP-13 hygiene-scan expansion — substantial new mechanism design, deferred to fresh session
- 4 remaining rules-vs-hooks splits (acceptance-scenarios, agent-teams, design-mode-planning, testing) — substantial restructuring per rule, deferred to fresh session

## Tasks

- [x] **1. Codename scrub of 5 committed files.** Sanitize identifiers per harness-hygiene-scan denylist patterns. Replace specific business codenames + GitHub usernames + product codenames with generic placeholders (e.g., `<personal-account>`, `<work-org>`, `<product-codename-A>`). Preserve audit-trail context — the documents stay readable. Run full-tree scan after; expect zero matches. Single commit.

- [x] **2. GAP-14-followups — investigate and fix-or-defer 4 items.** Per item: audit current state, decide fix-vs-defer, apply or document. If any are quick fixes, apply. If any need substantive work, defer with explicit rationale. Document in commit message. Run settings-divergence-detector after to confirm the followups are addressed (or remaining divergences are intentional). Single commit.

- [x] **3. observed-errors-first.md stub conversion.** REWRITE the rule mirroring vaporware-prevention.md's stub format: short opening + enforcement-map table pointing at the relevant hook. Per Phase 1d-E-2 audit, the rule is ~80% hook-enforced. Single commit.

- [x] **4. Backlog cleanup with deferral rationale.** Mark Phase 1d-G items as IMPLEMENTED in backlog "Recently implemented" section. Add explicit rationale entries for truly-deferred items: GAP-08 (substantive new mechanism warrants fresh-session attention), GAP-13 (same), 4 remaining rule splits (each is substantial restructuring). Bump Last updated to v18. Single commit.

## Files to Modify/Create

- `docs/decisions/001-public-release-strategy.md` — EDIT
- `docs/decisions/002-attribution-only-anonymization.md` — EDIT
- `docs/decisions/013-default-push-policy.md` — EDIT
- `docs/reviews/2026-04-27-agent-teams-conflict-analysis.md` — EDIT
- `docs/reviews/2026-05-03-build-doctrine-integration-gaps.md` — EDIT
- `adapters/claude-code/settings.json.template` — EDIT (GAP-14-followups)
- `~/.claude/settings.json` — EDIT (gitignored mirror)
- `adapters/claude-code/rules/observed-errors-first.md` — REWRITE
- `~/.claude/rules/observed-errors-first.md` — sync
- `docs/backlog.md` — EDIT
- `docs/decisions/025-*.md` — NEW if applicable

## In-flight scope updates

- 2026-05-04 (Task 2): `docs/reviews/2026-05-04-gap-14-reconciliation-proposals.md` — EDIT. Added Phase 1d-G addendum documenting that the four out-of-scope SessionStart/UserPromptSubmit divergences from the original audit were resolved in this phase. Audit doc is the natural home for the resolution record.
- 2026-05-04 (Task 1): `docs/DECISIONS.md` — EDIT (footnote). Decisions-index gate requires the index to be staged in the same commit when decision records are modified; added a footnote acknowledging the in-place codename scrub of records 001, 002, 013 (no status or substance changes).

## Assumptions

- Codename scrubs preserve audit-trail readability; the substantive content of decisions/reviews stays intact, only identifiers sanitized.
- The 4 GAP-14-followups have clear current state in `docs/reviews/2026-05-04-gap-14-reconciliation-proposals.md`.
- observed-errors-first.md's hook backing is `observed-errors-gate.sh` per the rule's existing cross-reference.
- Stub conversion mirrors vaporware-prevention.md's pattern: short prose + enforcement-map table.

## Edge Cases

- **A codename appears in legitimate verbatim quotes from prior PRs / commits.** Sanitize in-place; the audit trail through git log + commit messages still preserves the original wording for archaeological purposes.
- **A GAP-14-followup is non-trivial to fix.** Defer with explicit rationale rather than half-ship.
- **observed-errors-first.md's stub conversion produces a stub <30 lines.** Acceptable; the enforcement is in the hook.

## Acceptance Scenarios

(none — `acceptance-exempt: true`. Verification is per-task task-verifier PASS + harness-hygiene-scan --full-tree zero matches + settings-divergence-detector clean.)

## Out-of-scope scenarios

- Substantive new mechanism design (GAP-08, GAP-13) — deferred.
- 4 remaining rule splits — deferred per rule.

## Testing Strategy

1. Task 1: `bash harness-hygiene-scan.sh --full-tree` returns "FULL TREE — 0 MATCHES".
2. Task 2: settings-divergence-detector shows clean PreToolUse/SessionStart/UserPromptSubmit (or only intentional, documented).
3. Task 3: stub file is <50 lines; references the hook + decision record.
4. Task 4: backlog reflects deferral status honestly.

## Walking Skeleton

Codename scrub (Task 1) is the most independent and unblocks master merge. Start there.

## Decisions Log

(populated during implementation)

## Pre-Submission Audit

- S1: swept, 0 stranded.
- S2: swept, 4 claims (15 hits in 5 files; observed-errors-first.md ~80% hook-enforced; vaporware-prevention.md is current stub example; 4 GAP-14-followups documented in reconciliation proposals doc) — verified.
- S3: swept, 0 contradictions.
- S4: swept for [15 hits, 5 files, 4 followups] — consistent.
- S5: swept, 0 contradictions.

## Definition of Done

- [x] All 4 tasks task-verified PASS.
- [x] Full-tree scanner returns zero matches.
- [x] settings-divergence-detector reports clean output.
- [x] observed-errors-first.md stub-converted.
- [x] Backlog reflects deferred items with explicit rationale.
- [ ] Plan archived (Status: COMPLETED → auto-archive).
- [ ] Master merge prep validated (post-archive: branch ready for merge).
