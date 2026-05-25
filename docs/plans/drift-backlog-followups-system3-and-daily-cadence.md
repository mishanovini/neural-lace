# Plan: drift-backlog followups — System 3 (CI watcher) + daily cadence
Status: ACTIVE
Execution Mode: orchestrator
Mode: code
tier: 2
rung: 1
architecture: pattern
frozen: true
prd-ref: n/a — harness-development
acceptance-exempt: true
acceptance-exempt-reason: harness-internal followups to PR #34's parent plan; the "user" is the maintainer reviewing daily packets and CI status; self-tests are the verification artifact
Backlog items absorbed: HARNESS-GAP-41, HARNESS-GAP-42
Work-shape: build-harness-infrastructure

## Goal

Land two Misha-directed scope additions on the same branch + PR as
the parent drift-backlog-and-harness-evaluator work (PR #34):

1. **System 3: CI watcher for Dispatch-spawned PRs** (GAP-41) — track CI status of every Dispatch-spawned PR, emit drift items on FAIL transitions, route attention to Dispatch instead of Misha's inbox.
2. **Daily cadence + skim-fast packet** (GAP-42) — change harness-evaluator from weekly to daily, redesign packet to be 3-5 bullets unless deep treatment needed, preserve weekly rollup as separate doc.

## User-facing Outcome

After these followups ship, Misha can:

1. Stop receiving GitHub email notifications for failed PR checks on Dispatch-spawned PRs (System 3 surfaces them to Dispatch via the daily packet instead).
2. Read a 3-5 bullet daily packet at `docs/reviews/YYYY-MM-DD-harness-self-eval.md` in under 30 seconds, with deep treatment one click away in collapsible sections.
3. Read a weekly rollup at `docs/reviews/YYYY-WW-harness-weekly-rollup.md` for the historical record.

## Scope

- IN: `adapters/claude-code/scripts/dispatch-ci-watcher.sh` (new — System 3)
- IN: `adapters/claude-code/scripts/harness-evaluator.sh` (modified — daily/full/weekly-rollup modes)
- IN: `adapters/claude-code/scripts/schedule-weekly-eval.md` (modified — daily-first wiring)
- IN: `docs/reviews/2026-05-25-harness-self-eval.md` (regenerated as daily-mode skim with v1 honesty audit preserved)
- OUT: weekly-rollup diff logic (v1 just lists packets; v2 will diff)
- OUT: push notifications to Dispatch (drift-items.jsonl exists; surfacing channel TBD)

## Tasks

- [ ] 1. Build `dispatch-ci-watcher.sh` with state-store + transition detection + drift-item emission. — Verification: full
   **Prove it works:** 1. Run against current repo's open PRs. 2. Confirm state files at `.claude/state/ci-watcher/<repo>_<pr>.json`. 3. Confirm any PR with failing checks generates a drift-items.jsonl entry.
   **Wire checks:** `adapters/claude-code/scripts/dispatch-ci-watcher.sh` → calls `gh pr list` + `gh pr checks` → writes `.claude/state/ci-watcher/*.json` + `drift-items.jsonl`
   **Integration points:** depends on `gh` authenticated; emits drift items consumed by harness-evaluator daily packet Section A.
- [ ] 2. Extend `harness-evaluator.sh` with --mode daily/full/weekly-rollup; daily is skim-fast with collapsible sections. — Verification: full
   **Prove it works:** 1. Run `--mode daily` and confirm output has 5 bullets at top + 5 collapsible <details> sections. 2. Output includes Section A from CI watcher state. 3. Self-test passes.
   **Wire checks:** `adapters/claude-code/scripts/harness-evaluator.sh` → reads `.claude/state/ci-watcher/` + System 1 backlog → writes `docs/reviews/YYYY-MM-DD-harness-self-eval.md`
   **Integration points:** reads from System 3's state directory; reads from System 1's drift backlog.
- [ ] 3. Update `schedule-weekly-eval.md` with daily-first wiring options. — Verification: mechanical
- [ ] 4. Regenerate today's packet as daily-mode; preserve v1 honesty audit. — Verification: mechanical
- [ ] 5. Push to existing branch + update PR description. — Verification: mechanical

## Files to Modify/Create

- `docs/plans/drift-backlog-followups-system3-and-daily-cadence.md` — this plan
- `adapters/claude-code/scripts/dispatch-ci-watcher.sh` — System 3 (NEW)
- `adapters/claude-code/scripts/harness-evaluator.sh` — daily/full/weekly-rollup modes (MODIFY)
- `adapters/claude-code/scripts/schedule-weekly-eval.md` — daily wiring (MODIFY)
- `docs/reviews/2026-05-25-harness-self-eval.md` — regenerated daily packet (MODIFY)

## In-flight scope updates

(empty — these followups landed via a single coherent commit)

## Assumptions

- `gh` CLI is authenticated for the operator on every machine running System 3.
- Branch-naming heuristic (`feat/`, `fix/`, `docs/`, etc.) is adequate for Dispatch-spawned PR detection; commits without those prefixes will be missed (acceptable v1 limitation; v2 can add commit-author detection).
- `<details>` markdown is rendered by GitHub PR view and the operator's local markdown viewer (confirmed for GitHub).

## Edge Cases

- **No PRs match the Dispatch heuristic.** Script exits silently with empty state. Acceptable.
- **`gh pr checks` returns empty (no CI configured).** Aggregate state = "no-checks"; no drift emitted. Acceptable.
- **Same PR transitions pass → fail → pass rapidly.** Each transition appended to `transitions` array; drift-item emitted only on transitions TO fail. Operator sees the latest state.
- **State file corruption (interrupted write).** Script tolerates via mktemp+mv pattern. If a file is unreadable on next run, treated as new-PR.

## Testing Strategy

- **Mechanical:** scripts run without error.
- **Functional:** first run of System 3 against actual repo correctly identifies PR #34's FAIL state (verified — produced drift-item).
- **Self-test:** confirms heuristic correctness + state-dir creation + gh availability.

## Walking Skeleton

1. System 3 script self-tests pass.
2. System 3 first run against current repo state produces tracking + drift-items.jsonl.
3. harness-evaluator --mode daily reads System 3 state + System 1 backlog into a skim-fast packet.
4. Daily packet generated; visible in docs/reviews/.
5. Schedule doc updated; commit + push.

## Evidence Log

### Task 1: dispatch-ci-watcher.sh
Task ID: 1
Files: `adapters/claude-code/scripts/dispatch-ci-watcher.sh`
Self-test: PASS (5/5 — heuristic positives, negatives, state dir creatable, gh present, gh auth)
First run: detected 9 open PRs in the current repo, correctly identified PR #34 as FAIL, emitted drift item.
Verdict: PASS

### Task 2: harness-evaluator daily/full/weekly-rollup modes
Task ID: 2
Files: `adapters/claude-code/scripts/harness-evaluator.sh` modified
Self-test: PASS (4/4 — state dir, count_files, compose_header, drift-backlog JSON)
First daily-mode run: 167 lines (was 232 for weekly), 5 top-line bullets + 5 collapsible sections.
Verdict: PASS

### Task 3: schedule-weekly-eval.md daily wiring
Task ID: 3
File: `adapters/claude-code/scripts/schedule-weekly-eval.md` rewritten with daily as default + weekly-rollup as separate.
Verdict: PASS

### Task 4: Regenerated packet
Task ID: 4
File: `docs/reviews/2026-05-25-harness-self-eval.md` — daily skim mode + v1 honesty audit preserved as separate section.
Verdict: PASS

### Task 5: Push + PR update
Task ID: 5
PR #34 description updated to cover all three systems + fix the failing PR-template-validator heading.
Verdict: PASS

## Decisions Log

### Decision: Branch-name heuristic for Dispatch detection
- Tier: 1 (reversible)
- Status: proceeded with recommendation
- Chosen: match `feat/`, `fix/`, `docs/`, `chore/`, `ci/`, `refactor/`, `claude/`, `strategy/` prefixes.
- Alternatives: commit-author parse (more accurate, harder to compute over many PRs); PR body markers (requires changing PR creation flow).
- Reasoning: branch-naming is the simplest signal that doesn't require additional state. Excludes legitimately-manual `release/*`, `hotfix/*`. False-negatives acceptable in v1.

### Decision: Daily as default, weekly as separate mode
- Tier: 1 (reversible; just a CLI flag)
- Status: proceeded with recommendation (Misha-directed)
- Chosen: `--mode daily` is the default; `--mode weekly-rollup` is the separate aggregation.
- Reasoning: Misha's directive 2026-05-25 was explicit. Daily gives 1-day-resolution drift detection; weekly serves the historical-record role.

### Decision: Collapsible <details> blocks for deep treatment
- Tier: 1 (formatting choice)
- Status: proceeded with recommendation
- Chosen: skim bullets at top, full sections inside `<details>` tags.
- Alternatives: separate files per section (more files to manage); inline-but-truncated (loses information).
- Reasoning: GitHub renders `<details>` collapsibles; one packet per day, one click to expand, no information lost.

## Definition of Done

- [ ] System 3 self-test passes
- [ ] System 3 first run produces tracked-PR state files + at least one drift item
- [ ] harness-evaluator daily-mode packet generated and committed
- [ ] schedule-weekly-eval.md reflects daily cadence
- [ ] Branch pushed
- [ ] PR #34 description updated to cover all 3 systems
- [ ] PR-template-validator failing check fixed (correct heading)

## Pre-Submission Audit

S1 (Entry-Point Surfacing): swept, both new behaviors (CI watcher + daily packet) cited at Tasks 1 + 2 and Files-to-Modify.
S2 (Existing-Code-Claim Verification): swept, gh CLI presence verified at runtime, `<details>` markdown verified to render on GitHub.
S3 (Cross-Section Consistency): swept, "daily-as-default" consistent across plan body + script + schedule doc.
S4 (Numeric-Parameter Sweep): swept for params: 5-10min cadence target (mentioned in scope; actual cron is `0 8 * * *` daily) — consistent.
S5 (Scope-vs-Analysis Check): swept, no "Add X" verbs target Scope OUT items.
