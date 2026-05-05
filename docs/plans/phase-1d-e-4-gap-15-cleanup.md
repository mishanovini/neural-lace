# Plan: Phase 1d-E-4 — GAP-15 cleanup + un-archived plans resolution

Status: ACTIVE
Execution Mode: orchestrator
Mode: code
Backlog items absorbed: HARNESS-GAP-15
acceptance-exempt: true
acceptance-exempt-reason: Harness-development plan; no product-user surface to verify at runtime. Verification is per-task task-verifier PASS + the harness-hygiene-scan --self-test invocation + the un-archived plans being correctly flipped to COMPLETED.
tier: 2
rung: 1
architecture: coding-harness
frozen: true
prd-ref: n/a — harness-development

## Context

HARNESS-GAP-15 (added 2026-05-04) aggregates 6 sub-items from the stale-plan audit and related Phase 1d-E cleanup work. Two plans (`harness-quick-wins-2026-04-22.md` and `public-release-hardening.md`) were prematurely marked COMPLETED in earlier sessions and were un-archived for proper resolution.

This phase closes the GAP-15 sub-items. Sub-item C (codename scrub at next merge) is deferred to merge time. Sub-item G (planning rollup) is already done — Phase 1d-E split into 1d-E-1, 1d-E-2, 1d-F, and now 1d-E-4.

## Goal

Close 5 of 6 GAP-15 sub-items in one coherent batch:

1. **Sub-item A — Scanner self-test repair (P1).** Fix `harness-hygiene-scan.sh --self-test` so it passes against current exemption logic.
2. **Sub-item B — Scanner exemption logic reconciliation (P1).** Tighten scanner exemption to match the gitignore allow-list. Run full-tree scan; fix any newly-surfaced findings.
3. **Sub-item D — Missing schema file (P3).** Author `adapters/claude-code/schemas/automation-mode.schema.json` OR remove from public-release-hardening.md's claimed scope.
4. **Sub-item E — Close out public-release-hardening.md unchecked tasks (P3).** Bookkeeping: either complete tasks 1.2 / 4.2 / 5.3 / 6.1 or document explicit deferral. Then flip Status: COMPLETED with a corrected completion report.
5. **Sub-item F — Close out harness-quick-wins-2026-04-22 Phase A Task 1 (P2).** Either ship the `effortLevel` field edit or document deferral. Flip Status: COMPLETED.

Sub-item C (codename scrub) is OUT of this plan's scope (deferred to next master merge).

## Scope

**IN:**
- `adapters/claude-code/hooks/harness-hygiene-scan.sh` — EDIT (Sub-items A + B)
- `~/.claude/hooks/harness-hygiene-scan.sh` — sync target
- `adapters/claude-code/schemas/automation-mode.schema.json` — NEW or scope-removal in plan B (Sub-item D)
- `docs/plans/harness-quick-wins-2026-04-22.md` — EDIT (Sub-item F: complete or defer Phase A Task 1; flip Status: COMPLETED)
- `docs/plans/public-release-hardening.md` — EDIT (Sub-item E: close unchecked tasks; flip Status: COMPLETED)
- `~/.claude/settings.json` — EDIT (Sub-item F: add effortLevel field if completing)
- `docs/backlog.md` — EDIT (mark GAP-15 sub-items A/B/D/E/F IMPLEMENTED in Recently Implemented section)
- `docs/decisions/024-*.md` — NEW if any structural decision arises (e.g., schema removal vs creation)
- `docs/DECISIONS.md` — EDIT if 024 lands

**OUT:**
- Sub-item C — codename scrub before master merge. Deferred to next merge per backlog. Right-sized: P3 distribution-readiness, not security.
- Sub-item G — already completed by Phase 1d-E split.
- HARNESS-GAP-14 — separate plan (Phase 1d-E-3).

## Tasks

- [ ] **1. Fix harness-hygiene-scan.sh self-test (Sub-item A).** Read existing self-test scaffold. Identify the failing exemption assertion (referencing `docs/plans/foo.md`). Update the assertion to match current exemption logic. Run `bash harness-hygiene-scan.sh --self-test` until PASS. Sync to live. Single commit.

- [ ] **2. Tighten scanner exemption + reconcile with gitignore (Sub-item B).** EDIT scanner so directory-level exemptions for `docs/decisions/`, `docs/reviews/`, `docs/sessions/` only apply to gitignored paths within those directories — NOT to committed (allow-listed) files. Re-run full-tree scan after fix. If new findings surface, address them in the SAME commit (sanitize identifiers in committed decision/review/session files). Sync to live. Single commit.

- [ ] **3. Schema file decision + creation/removal (Sub-item D).** Read `docs/plans/public-release-hardening.md` Task 6.1 to confirm the schema reference. Decide: (a) author the schema file, OR (b) remove from plan's claimed scope (the example.json + gate hook are sufficient without strict schema validation). Document the choice. Single commit.

- [ ] **4. Close public-release-hardening.md (Sub-item E).** Per unchecked task (1.2, 4.2, 5.3, 6.1 per backlog), either complete OR document explicit deferral with rationale. Flip Status: COMPLETED with a corrected completion report stating actual scope honestly. Auto-archive. Single commit.

- [ ] **5. Close harness-quick-wins-2026-04-22.md (Sub-item F).** Phase A Task 1 needs `effortLevel` field in settings.json. Either add it (one-line edit + verification) OR defer with rationale citing per-project effort-policy-warn.sh covers most of the value. Flip Status: COMPLETED. Auto-archive. Single commit.

- [ ] **6. Backlog cleanup + GAP-15 closure.** Mark sub-items A/B/D/E/F IMPLEMENTED in `docs/backlog.md` "Recently implemented" section with commit SHAs. Note Sub-item C deferred (still tracked). Update front-matter Last updated. Single commit.

## Files to Modify/Create

- `adapters/claude-code/hooks/harness-hygiene-scan.sh` — EDIT.
- `~/.claude/hooks/harness-hygiene-scan.sh` — sync.
- `adapters/claude-code/schemas/automation-mode.schema.json` — NEW or removed-from-claims.
- `docs/plans/harness-quick-wins-2026-04-22.md` — EDIT (Status flip + Task 1 close-out).
- `docs/plans/public-release-hardening.md` — EDIT (Status flip + unchecked-task close-out).
- `~/.claude/settings.json` — EDIT if Sub-item F completes.
- `docs/backlog.md` — EDIT.
- `docs/decisions/024-*.md` — NEW if Sub-item D ships a decision.
- `docs/DECISIONS.md` — EDIT if 024 lands.

## In-flight scope updates

(none yet)

## Assumptions

- harness-hygiene-scan.sh's self-test scaffold is documented in the hook's header comment.
- The gitignore allow-list patterns (per Sub-gap H from 1d-E-2) are now in place: `!docs/decisions/[0-9][0-9][0-9]-*.md` etc.
- public-release-hardening.md's unchecked tasks 1.2 / 4.2 / 5.3 / 6.1 have clear context in the plan file describing what they were meant to do.
- harness-quick-wins-2026-04-22.md's Phase A Task 1 references the `effortLevel` setting in settings.json which is documented in Anthropic's settings reference.
- The two un-archived plans are acceptance-exempt: true (verified at session start), so they don't block the acceptance gate.

## Edge Cases

- **Scanner finds new committed files with codenames after Sub-item B's tightening.** Address in same commit by sanitizing identifiers OR adding deliberate exemptions in the denylist with justification.
- **public-release-hardening.md's unchecked tasks reference work that's already been done in interim sessions.** Mark complete with citations to the relevant commits; flip box to [x].
- **harness-quick-wins-2026-04-22.md's effortLevel edit conflicts with existing user settings.** Defer with rationale rather than override user state.
- **Schema file (Sub-item D) is genuinely useful for future features.** Prefer authoring it over scope-removal.
- **Sub-item B's full-tree scan surfaces dozens of new findings.** Bundle into "address in this commit" if achievable, OR open a separate plan for the remediation.

## Acceptance Scenarios

(none — `acceptance-exempt: true`. Verification is per-task task-verifier PASS + scanner self-test PASS + un-archived plans flipped COMPLETED.)

## Out-of-scope scenarios

- Sub-item C codename scrub.
- HARNESS-GAP-14 reconciliation (Phase 1d-E-3).

## Testing Strategy

Each task task-verified. Specific testing:

1. Task 1: `bash harness-hygiene-scan.sh --self-test` returns exit 0 with all scenarios PASS.
2. Task 2: full-tree scan after the edit returns exit 0 OR all surfaced findings are addressed in the same commit.
3. Task 3: if schema authored, JSON validity check.
4. Tasks 4 + 5: plans now have Status: COMPLETED and are auto-archived; Definition of Done sections are checked off honestly.
5. Task 6: backlog reflects sub-items A/B/D/E/F as IMPLEMENTED with SHAs; Sub-item C noted as deferred.

## Walking Skeleton

Sub-item A (scanner self-test repair) is the smallest unit and unblocks Sub-item B. Start there.

## Decisions Log

(populated during implementation)

## Pre-Submission Audit

- S1 (Entry-Point Surfacing): swept, 0 stranded.
- S2 (Existing-Code-Claim Verification): swept, 5 claims (scanner self-test scaffold; gitignore allow-list patterns; public-release-hardening task IDs 1.2/4.2/5.3/6.1; harness-quick-wins effortLevel field; schema file path) — all 5 verified.
- S3 (Cross-Section Consistency): swept, 0 contradictions.
- S4 (Numeric-Parameter Sweep): swept for [5 sub-items in scope, 6 tasks, 4 unchecked tasks in public-release-hardening] — values consistent.
- S5 (Scope-vs-Analysis Check): swept, 0 contradictions.

## Definition of Done

- [ ] All 6 tasks task-verified PASS.
- [ ] harness-hygiene-scan --self-test PASS.
- [ ] Both un-archived plans flipped to COMPLETED + auto-archived.
- [ ] Backlog reflects GAP-15 sub-items A/B/D/E/F as IMPLEMENTED.
- [ ] Plan archived (Status: COMPLETED → auto-archive).
