# Plan: Canonical plan-status enum — schema, template, doctrine (Agent 1)
Status: ACTIVE
Execution Mode: direct
Mode: code
Backlog items absorbed: none
acceptance-exempt: true
acceptance-exempt-reason: harness-internal — schema/doctrine/hook infrastructure change with no product UI surface in this increment; the maintainer is the user per constitution §4, and the self-test suites cited in Testing Strategy are the demonstration. Cockpit-facing wiring (roadmap-routes.js) and the actual plan-file migration across repos are explicitly out of scope, tracked as follow-up work for other agents in this same orchestrated initiative.
tier: 2
rung: 2
architecture: coding-harness
frozen: true
lifecycle-schema: v2
loe-class: schema-migration
owner: Misha
target-completion-date: 2026-08-04
prd-ref: n/a — harness-development
ask-id: none — no linked ask
design-ref: n/a — direct operator-directed class fix dispatched inline by the orchestrating session (2026-08-04, "I want to get all these unknown states rectified"); no separate docs/designs/ doc was authored for this scoped schema+doctrine task, and the scope is narrow enough (one new schema file + doc/hook updates) that a full design doc would be disproportionate.

## Intended Functionality

**Outcome (operator's terms):** A harness maintainer who edits `adapters/claude-code/schemas/plan-status.schema.json`'s lifecycle data now changes `plan-lifecycle.sh`'s and `plan-status-archival-sweep.sh`'s actual archival routing behavior directly, without touching either hook's code — verified live by mutation-testing the schema and observing both hooks' behavior change accordingly. Separately, a plan-author writing `Status: DRAFT`, `Status: PROPOSED`, or `Status: REFERENCE` (previously freelanced, unrecognized prose) now has those exact tokens as part of a real, documented enum with defined archival behavior, instead of undocumented "nothing happens to match" fallthrough.

**Observation:** Run `bash adapters/claude-code/hooks/plan-lifecycle.sh --self-test` and `bash adapters/claude-code/hooks/plan-status-archival-sweep.sh --self-test` — both report full PASS including scenarios that temporarily point the hooks at a fixture schema with deliberately mutated lifecycle data and assert the hooks' behavior follows the fixture, not their hardcoded fallback. `jq -r '.statuses[].token' adapters/claude-code/schemas/plan-status.schema.json` lists all 8 canonical tokens.

**Deterministic pass/fail:** PASS iff (1) `plan-lifecycle.sh --self-test` exits 0 with `OK (plan-lifecycle.sh --self-test)` on stdout, (2) `plan-status-archival-sweep.sh --self-test` exits 0 with `All 7 self-test scenarios PASSED`, (3) `jq empty adapters/claude-code/schemas/plan-status.schema.json` exits 0, (4) `bash evals/golden/rules-index-coverage.sh` exits 0 (doctrine files stay within the 3000-byte compact cap), (5) `bash adapters/claude-code/scripts/manifest-check.sh` reports GREEN. Any non-zero exit or FAIL line is fail.

**Explicitly NOT included:** Wiring `neural-lace/workstreams-ui/server/roadmap-routes.js` to actually consume this schema (it still carries its own `KNOWN_PLAN_STATUS_TOKENS`/`PLAN_STATUS_EXCLUDE_RE`) — that is a separate follow-up task against the cockpit. Migrating the ~11 affected plans on a sibling project and this repo's REFERENCE/NORMATIVE-prose plans to the bare canonical tokens — that is a separate migration task. Any change to `close-plan.sh` — audited (Task 6) and found to carry no hardcoded status *list* (only single-literal `ACTIVE`/`COMPLETED` checks, both unchanged tokens), so deliberately left untouched.

**Human dependencies:**
- The orchestrating session (or its dispatched `task-verifier`) reviews this plan's tasks against the commit and flips checkboxes / `Status: COMPLETED` — INTENDED (this builder subagent was explicitly instructed not to invoke `task-verifier` itself; multi-agent orchestrator pattern per `~/.claude/doctrine/orchestrator-pattern.md`).
- A follow-up agent wires the cockpit and migrates plan files — INTENDED (named explicitly as out-of-scope above, not a silently-dropped dependency).

## Goal

Replace the freelanced, per-repo `Status:` prose on `docs/plans/*.md` plan files (measured 2026-08-04 census: this repo 13x DEFERRED, 3x ACTIVE, 5x "REFERENCE (spec appendix...)", 1x "NORMATIVE for Wave O builders (...)", 1x "DEFERRED (operator ...)"; a sibling project on this machine 20x ACTIVE, 6x DRAFT, 1x PROPOSED, 2x PROPOSAL, 2x "DRAFT -- <prose>") with ONE canonical, machine-readable 8-value enum (DRAFT, PROPOSED, ACTIVE, COMPLETED, SUPERSEDED, DEFERRED, ABANDONED, REFERENCE) plus an optional `Status-note:` line for the qualifying prose that used to live inside `Status:` itself. This plan is Agent 1 of a multi-agent initiative: it builds the schema (a single canonical, statically-authored data file — no runtime writer, no cache, no sync mechanism), documents it in the template + doctrine, and points the two harness hooks that already branch on the status set (`plan-lifecycle.sh`, `plan-status-archival-sweep.sh`) at the schema instead of their own hardcoded copies.

## User-facing Outcome

n/a — harness-internal: the user is the maintainer. Before this plan, changing which statuses trigger archival (or where they archive to) required editing 2-3 separate hardcoded lists across `plan-lifecycle.sh` and `plan-status-archival-sweep.sh` and hoping they stayed in sync (the `close-plan.sh` audit in Task 6 confirms that file at least never needed a third copy). After this plan, a maintainer edits ONE file (`adapters/claude-code/schemas/plan-status.schema.json`) and both hooks pick it up — proven by two live mutation tests (Testing Strategy) that would fail if either hook silently ignored the schema.

## Scope
- IN: `adapters/claude-code/schemas/plan-status.schema.json` (new); `adapters/claude-code/templates/plan-template.md`; `adapters/claude-code/doctrine/planning.md` + `planning-full.md`; `adapters/claude-code/hooks/plan-lifecycle.sh` + `plan-status-archival-sweep.sh` (schema-driven lookup with hardcoded fallback + new self-test scenarios); auditing `adapters/claude-code/scripts/close-plan.sh` for hardcoded status lists; correcting a pre-existing ADR 051→052 citation typo (no `docs/decisions/051-*.md` exists) everywhere the DEFERRED destination-split is cited in the files this plan touches.
- OUT: `neural-lace/workstreams-ui/server/roadmap-routes.js` cockpit wiring (KNOWN_PLAN_STATUS_TOKENS / PLAN_STATUS_EXCLUDE_RE) — follow-up agent. Migrating existing plan files (this repo's REFERENCE/NORMATIVE-prose plans, a sibling project's DRAFT/PROPOSAL-prose plans) to the bare canonical tokens — follow-up agent/task. `plan-reviewer.sh`, `concurrent-ownership-gate-body.sh`, `scope-enforcement-gate.sh`, `work-integrity-gate.sh`, `stale-active-plan-surfacer.sh` — spot-checked (Task 6/Decisions Log) and found to reference the status set in comments/messages or (for `concurrent-ownership-gate-body.sh` specifically) TWO genuine hardcoded regex checks equivalent to `is_terminal_status()` — left untouched as a named residual gap, not silently dropped. `adapters/claude-code/scripts/close-plan.sh` itself — audited, no change needed (see Decisions Log).

## Tasks

- [ ] 1. Author `adapters/claude-code/schemas/plan-status.schema.json`: the 8 canonical values (DRAFT, PROPOSED, ACTIVE, COMPLETED, SUPERSEDED, DEFERRED, ABANDONED, REFERENCE), each with `description`/`phase`/`cockpit_render`/`lifecycle` (`triggers_archival`+`archive_subdir`), plus the `status_note` contract (optional free prose, never parsed for state) — Verification: mechanical — Docs impact: none, the schema file is self-documenting via its own top-level `description` field (the dual bash-tooling/cockpit consumption contract).
- [ ] 2. Update `adapters/claude-code/templates/plan-template.md` to document `Status:` + optional `Status-note:` inline with the full 8-value enum — Verification: mechanical — Docs impact: this task IS the doc-surface addition (the template itself).
- [ ] 3. Update `adapters/claude-code/doctrine/planning.md` (one compact bullet, trimming five existing bullets to stay within the 3000-byte cap — 2971/3000 measured) and `adapters/claude-code/doctrine/planning-full.md` (new "Stage 0: The Status enum + Status-note" subsection with the full table, under "Plan File Lifecycle") — Verification: mechanical — Docs impact: this task IS the doc delta.
- [ ] 4. Point `plan-lifecycle.sh`'s `is_terminal_status()` and a new `archive_subdir_for_status()` at the schema via `jq` (with a hardcoded fallback byte-identical to prior behavior when `jq`/the schema are unavailable); add self-test Scenarios 22a/22b/22c using a test-only `PLAN_STATUS_SCHEMA_OVERRIDE` env var (matching this codebase's `_OVERRIDE` convention) to mutation-prove the schema is actually consulted, not merely coincidentally matched — Verification: mechanical — Docs impact: none, fully covered by the hook's own header comments + self-test.
- [ ] 5. Point `plan-status-archival-sweep.sh`'s destination lookup at the same schema via `jq` (same fallback discipline); add self-test Scenarios 6/6b (fixture-schema override + restore) proving the same thing for this hook — Verification: mechanical — Docs impact: none, same as Task 4.
- [ ] 6. Audit `plan-lifecycle.sh` and `close-plan.sh` for hardcoded status lists per the originating task brief. Finding: `close-plan.sh` carries no hardcoded status *list* — only two single-literal checks (`current_status != ACTIVE` precondition at line ~1540, `sed` flip to `COMPLETED` at line ~1734), both unchanged tokens in the new enum — left untouched, decision recorded below. Also swept `plan-status-archival-sweep.sh` (same class of duplicate, found while auditing `plan-lifecycle.sh`'s sibling files) and fixed it under Task 5 rather than leaving a known-duplicate unaddressed — Verification: mechanical — Docs impact: none, the audit finding is recorded in this plan's Decisions Log + the commit message.

## Files to Modify/Create
- `adapters/claude-code/schemas/plan-status.schema.json` — new: the canonical enum + lifecycle data + Status-note contract.
- `adapters/claude-code/templates/plan-template.md` — documents Status + Status-note inline with the enum.
- `adapters/claude-code/doctrine/planning.md` — one compact bullet (byte-cap-preserving trims to five existing bullets).
- `adapters/claude-code/doctrine/planning-full.md` — new "Stage 0" subsection with the full enum table.
- `adapters/claude-code/hooks/plan-lifecycle.sh` — `is_terminal_status()`/new `archive_subdir_for_status()` read the schema via `jq`; new self-test Scenarios 22a/22b/22c; ADR 051→052 citation fix.
- `adapters/claude-code/hooks/plan-status-archival-sweep.sh` — destination lookup reads the schema via `jq`; new self-test Scenarios 6/6b; ADR 051→052 citation fix.

## In-flight scope updates
(no in-flight changes — full scope declared above at plan creation, since the work was already complete when this plan was authored to satisfy `scope-enforcement-gate.sh`)

## Assumptions
- `jq` is a soft dependency in both hooks (guarded by `command -v jq`), not a hard one — verified by the fact both hooks already used `jq` for nothing before this change is false (they didn't), but the CODEBASE-WIDE convention of guarding `jq` calls with `command -v jq` is established and followed (dozens of existing call sites grepped).
- The three plans ACTIVE in this repo at the time of authoring (`accountable-estate-program-2026-07`, `cockpit-roadmap-redesign`, `gated-pipeline-master-2026-08`) do not already cover this scope — verified via `scope-enforcement-gate.sh --check`, which listed all three as rejecting the staged files.
- Downstream cockpit wiring and plan-file migration are follow-up work by other agents in this same orchestrated initiative (the originating task brief named this session "Agent 1" of a larger effort), not silently dropped scope.

## Edge Cases
- `jq` unavailable in the environment → both hooks fall back to their pre-schema hardcoded logic, byte-identical to prior behavior — this is the DEFAULT path in any environment without `jq`, not a rare corner case, so it is exercised by every self-test scenario that predates this change (all still pass).
- Schema file missing, moved, or corrupted (invalid JSON) → `jq` calls fail/return empty, both hooks degrade to the same hardcoded fallback — no crash, no wrong archival move.
- A plan carries a genuinely unrecognized `Status:` token (typo, or pre-migration freelanced prose not yet cleaned up by the follow-up migration task) → both hooks' fallback case statements only recognize the pre-migration terminal set (COMPLETED/DEFERRED/ABANDONED/SUPERSEDED), matching prior behavior exactly — no regression, no new false-archival of a plan the old code would have left alone.
- REFERENCE-status plans (5 live examples in this repo: `docs/plans/nl-overhaul-program-2026-07-specs-{b,c,d,e,f}.md`) must NEVER be auto-archived, since they are permanent reference material living in `docs/plans/` — verified: schema's `REFERENCE.lifecycle.triggers_archival` is `false`, cross-checked against these files' real on-disk location (`docs/plans/`, not `archive/`) before authoring the schema.

## Acceptance Scenarios
n/a — acceptance-exempt (see header); no product user in this increment, no advocate review cycle applies.

## Out-of-scope scenarios
n/a — acceptance-exempt plan, no scenarios were proposed to reject.

## Closure Contract
- **Commands that run:** `bash adapters/claude-code/hooks/plan-lifecycle.sh --self-test`; `bash adapters/claude-code/hooks/plan-status-archival-sweep.sh --self-test`; `jq empty adapters/claude-code/schemas/plan-status.schema.json`; `bash evals/golden/rules-index-coverage.sh`; `bash adapters/claude-code/scripts/manifest-check.sh`.
- **Expected outputs:** `OK (plan-lifecycle.sh --self-test)` exit 0; `All 7 self-test scenarios PASSED` exit 0; `jq empty` exit 0 (valid JSON); `PASS: rules/ holds only constitution.md; doctrine/INDEX.md covers every compact within the 3000-byte cap`; `[manifest-check] GREEN`.
- **On-disk artifact location:** this plan file's own commit (SHA recorded in the completion report below) plus the verbatim command transcripts in that report — acceptance-exempt harness plans have no `.claude/state/acceptance/` artifact; the self-test transcripts ARE the evidence, per constitution §4's harness-plan carve-out.
- **Done when:** all six tasks above show verified mechanical evidence in the completion report AND the orchestrating session confirms the commit lands (cherry-pick / merge / task-verifier dispatch is the orchestrator's job, per the multi-agent orchestrator pattern this builder subagent operates under).

## Testing Strategy
- `bash adapters/claude-code/hooks/plan-lifecycle.sh --self-test` — all scenarios including new 22a/22b/22c (schema-driven archival + destination + no-override-restores-real-schema), measured `OK (plan-lifecycle.sh --self-test)`.
- `bash adapters/claude-code/hooks/plan-status-archival-sweep.sh --self-test` — measured `All 7 self-test scenarios PASSED` (5 original + new 6/6b).
- `jq empty adapters/claude-code/schemas/plan-status.schema.json` — valid JSON, measured exit 0.
- `bash evals/golden/rules-index-coverage.sh` — measured `PASS: rules/ holds only constitution.md; doctrine/INDEX.md covers every compact within the 3000-byte cap` (planning.md measured 2971 bytes).
- `bash adapters/claude-code/scripts/manifest-check.sh` — measured `[manifest-check] GREEN — 165 entries, 127 hooks covered, 0 warn`.
- Live mutation test (manual, run BEFORE writing the permanent fixture-based self-test scenarios): temporarily flipped the REAL production schema's `DEFERRED.archive_subdir` from `"deferred"` to `"archive"`, re-ran both hooks' self-tests, confirmed the EXPECTED scenario failures (plan-lifecycle Scenario 5b, archival-sweep Scenario 4), then restored the schema and re-verified both suites green — proves the new code paths are load-bearing, not vacuous, before the permanent fixture-based regression scenarios (22a/22b/22c, 6/6b) were written to lock this in without ever touching the production file again.

## Walking Skeleton
Walking Skeleton: n/a — pure infrastructure/documentation change (a new schema file + two hook internals + doc updates); no new user-facing flow crosses architectural layers.

## Decisions Log
- **jq-direct vs. generated bash include (Tier 2 — schema-bound):** chose to point `plan-lifecycle.sh`/`plan-status-archival-sweep.sh` at the schema via `jq` directly, guarded by `command -v jq` with a hardcoded fallback, rather than generating a bash include with an out-of-date check. Rationale: `jq` is already a pervasive dependency across this codebase's hooks (dozens of existing `command -v jq` call sites grepped); a generated include adds a SECOND artifact that must be regenerated on every schema edit plus an out-of-date-detection gate whose own false-negative would be a brand-new failure class. One canonical file beats a derived copy that can silently drift. No `docs/decisions/NNN-*.md` filed — this is a scoped implementation choice within a single plan's tasks, not a cross-cutting architectural decision (constitution §3: "can I defend one answer from principles + evidence? If yes, take it, record it, move on").
- **Scope expansion to `plan-status-archival-sweep.sh` (reversible, decide-and-go):** the originating task brief named only `plan-lifecycle.sh` and `close-plan.sh` for the hardcoded-list audit. While auditing `plan-lifecycle.sh`'s sibling files, found `plan-status-archival-sweep.sh` carries an independent, near-identical hardcoded case statement for the exact same DEFERRED-vs-archive decision. Fixed it under the same schema-driven pattern rather than leaving a freshly-discovered duplicate unaddressed (constitution §8: "if correct scope is larger than planned scope, expand and finish"). Low risk: same file family, same pattern, full self-test coverage before and after (5/5 → 7/7).
- **REFERENCE: `phase: terminal` but `lifecycle.triggers_archival: false`:** the schema's `phase` field (pre-build/building/terminal) is a PLANNING-lifecycle concept, deliberately distinct from `lifecycle.triggers_archival` (an ARCHIVAL-mechanics concept). REFERENCE plans are terminal in the sense that they never move to ACTIVE, but must never be auto-archived (they are permanent reference material living in `docs/plans/` — 5 live examples cross-checked). Documented explicitly in the schema's `phase` field description to prevent a future reader conflating the two axes.
- **ADR 051→052 citation fix (out of the originally-named files, in-scope-adjacent):** `plan-lifecycle.sh`'s pre-existing "ADR 051" comment (3 occurrences) and `plan-status-archival-sweep.sh`'s (1 occurrence) both cited a non-existent `docs/decisions/051-*.md` — the real record for the DEFERRED destination-split is `052-deferred-plans-not-archived.md` (dated 2026-06-04, matching the cited date). Fixed inline since I was already editing the exact lines carrying the wrong citation; `coord-pull.sh`/`coord-push.sh` ALSO cite "ADR 051" but for a genuinely different, unrelated topic (gh-account-blindness) — left untouched, out of scope, flagged in the completion report for the orchestrator's awareness rather than silently fixed or silently ignored.
- **`close-plan.sh`: no change (Task 6 finding):** grepped for every one of the other 6 non-ACTIVE/COMPLETED tokens (DEFERRED, ABANDONED, SUPERSEDED, DRAFT, PROPOSED, REFERENCE) — zero matches anywhere in the file. The only status-adjacent logic is a single-literal `current_status != ACTIVE` precondition and a `sed` flip to `COMPLETED`, both unchanged tokens. No schema-pointing needed; documented rather than silently skipped.
- **Residual, explicitly not fixed:** `concurrent-ownership-gate-body.sh` carries two genuine hardcoded regex checks (`grep -qE 'Status:[[:space:]]*(DEFERRED|COMPLETED|ABANDONED|SUPERSEDED)'` and `grep -qE 'DEFERRED|COMPLETED|ABANDONED|SUPERSEDED'`) equivalent in spirit to `is_terminal_status()`. Named here rather than fixed: it is a DIFFERENT gate class (concurrent-ownership, not archival routing) with its own large self-test suite, and expanding into it was judged disproportionate to this plan's scope without a dedicated review. Flagged for the orchestrator to route to a follow-up task if desired.

## Definition of Done
- [ ] All tasks checked off
- [ ] All tests pass (self-test suites cited in Testing Strategy)
- [ ] Linting/formatting clean (n/a — no linter configured for bash/JSON/markdown in this repo beyond the self-tests and golden evals already run)
- [ ] SCRATCHPAD.md updated with final state (orchestrator's responsibility — this builder subagent operates in an isolated worktree without the interactive session's SCRATCHPAD.md)
- [ ] Completion report appended to this plan file (by the orchestrating session, using this plan's Testing Strategy output + the commit SHA)
