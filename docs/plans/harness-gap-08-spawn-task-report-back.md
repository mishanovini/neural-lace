# Plan: HARNESS-GAP-08 — spawn_task report-back convention

Status: ACTIVE
Execution Mode: orchestrator
Mode: code
Backlog items absorbed: HARNESS-GAP-08
acceptance-exempt: true
acceptance-exempt-reason: Harness-development plan; no product user. Verification is via hook --self-test invocations and a manual round-trip of an example spawn-with-report-back convention through the new surfacer.
tier: 1
rung: 1
architecture: coding-harness
frozen: false
prd-ref: n/a — harness-development

## Goal

Close HARNESS-GAP-08 by shipping a CONVENTION-based callback channel for `mcp__ccd_session__spawn_task`. The MCP tool itself is third-party with a fixed `{title, prompt, tldr}` interface and cannot be modified. The harness layer adds the callback as a convention: orchestrator includes a `Report-back: task-id=<X>` sentinel in the spawn prompt; spawned session writes a JSON result file at `.claude/state/spawned-task-results/<X>.json` before its Stop hook fires; a SessionStart surfacer hook in the orchestrator scans for unread results and surfaces them. Acknowledgment is explicit via a sibling `.acked` marker file (per user decision 2026-05-05 — no result is ever silently lost).

Outcome: orchestrator-coordinated punchlist work via spawn_task no longer requires user mediation. The orchestrator dispatches → does other work → next session start surfaces completed task results → orchestrator cherry-picks/verifies/plans next fix.

Pattern parallels: this hook mirrors `discovery-surfacer.sh` exactly in shape (SessionStart, working-directory-scoped scan of a state subdir, silent-when-empty, system-reminder block). The lifecycle (write result → surface → ack via sibling marker) is a different state shape than discoveries (`Status: pending → decided → implemented`) because the result file is data not a decision.

## Scope

- IN:
  - New rule: `adapters/claude-code/rules/spawn-task-report-back.md` (with `~/.claude/` mirror) — documents convention, JSON schema, lifecycle, ack mechanism, worked example
  - New hook: `adapters/claude-code/hooks/spawned-task-result-surfacer.sh` SessionStart hook (mirrors `discovery-surfacer.sh` exactly in shape)
  - Wiring: add hook to `adapters/claude-code/settings.json.template` SessionStart chain (after `discovery-surfacer.sh`); mirror to `~/.claude/settings.json`
  - Result file format: JSON at `.claude/state/spawned-task-results/<task-id>.json`. Schema per backlog: `{task_id, started_at, ended_at, branch, pr_url, exit_status, summary, commits, artifacts}`. Sibling `<task-id>.json.acked` indicates orchestrator has acted on the result.
  - Self-test: 5 scenarios in the new hook (no directory, empty dir, all-acked, has-unread, malformed-json-skipped)
  - Documentation update in `adapters/claude-code/rules/vaporware-prevention.md` enforcement map
- OUT:
  - Skill wrapper `/spawn-with-report-back` (deferred per user decision 2026-05-05; convention-only first; revisit if convention proves cumbersome)
  - Stop hook in spawned session enforcing the result-write — convention-only via prompt instruction. If the spawned session ignores instructions, that's vaporware in the spawned-session's behavior, not the harness's problem (mirrors how scenarios-shared/assertions-private discipline relies on prompt content, not hooks)
  - Auto-cleanup beyond the .acked-based filtering (no age-based prune in v1; can add later if results accumulate)
  - Modifying the MCP tool itself (third-party, not modifiable)

## Tasks

- [x] 1. Write `adapters/claude-code/rules/spawn-task-report-back.md` (~150-220 lines): Classification (Hybrid — Pattern + Mechanism), Why this rule exists, JSON schema, lifecycle (orchestrator generates task-id → includes sentinel in prompt → spawned session writes result → surfacer surfaces → orchestrator acts → orchestrator writes .acked marker), worked example with sample prompt + sample result JSON, ack semantics, edge cases, cross-references to discovery-protocol.md and orchestrator-pattern.md.
- [x] 2. Write `adapters/claude-code/hooks/spawned-task-result-surfacer.sh` (~150-200 lines mirroring discovery-surfacer.sh): SessionStart hook that scans `.claude/state/spawned-task-results/*.json`, filters out files with sibling `.acked`, surfaces unread results with task_id, summary, branch, commits as a system-reminder block. Self-test with 5 scenarios using temp-dir fixtures.
- [x] 3. Wire the new hook into `adapters/claude-code/settings.json.template` SessionStart chain (immediately after the existing `discovery-surfacer.sh` line at line 373). Mirror the change to `~/.claude/settings.json`.
- [x] 4. Update `adapters/claude-code/rules/vaporware-prevention.md` enforcement map with one new row: "Spawn_task results surfaced at session start" → `spawned-task-result-surfacer.sh` SessionStart hook + `spawn-task-report-back.md` rule.
- [ ] 5. Sync `adapters/claude-code/{rules,hooks}/` files to `~/.claude/{rules,hooks}/`. Run `--self-test` on both copies. Verify with the diff loop from `harness-maintenance.md`.
- [ ] 6. Commit on feature branch `feat/gap-08-spawn-task-report-back`. Push to origin (multi-push covers both remotes per HARNESS-GAP-12 resolution).

## Files to Modify/Create

- `adapters/claude-code/rules/spawn-task-report-back.md` — NEW (~150-220 lines, Hybrid classification)
- `adapters/claude-code/hooks/spawned-task-result-surfacer.sh` — NEW (~150-200 lines mirroring discovery-surfacer.sh)
- `adapters/claude-code/settings.json.template` — MODIFY (one SessionStart entry added after discovery-surfacer)
- `adapters/claude-code/rules/vaporware-prevention.md` — MODIFY (one row added to enforcement map table)
- `~/.claude/rules/spawn-task-report-back.md` — NEW (sync from adapter)
- `~/.claude/hooks/spawned-task-result-surfacer.sh` — NEW (sync from adapter)
- `~/.claude/settings.json` — MODIFY (mirror of template change)

## In-flight scope updates

- 2026-05-05: `docs/discoveries/2026-05-05-multi-active-plan-stranding.md` — process discovery surfaced during this plan's authoring, captured per discovery-protocol. Not part of GAP-08's deliverables but bundled with this plan's commits as related session-context.
- 2026-05-05: `docs/backlog.md` — atomicity-driven update: HARNESS-GAP-08 absorbed (entry removed from open sections per backlog-plan-atomicity rule), and HARNESS-GAP-16 (plan-closure validation gate + /close-plan skill) added as next-after-GAP-13 per user sequencing decision 2026-05-05.
- 2026-05-05: `docs/plans/harness-gap-08-spawn-task-report-back.md` — plan file itself (task-verifier-flipped checkboxes for Tasks 1, 2, 4).
- 2026-05-05: `docs/plans/harness-gap-08-spawn-task-report-back-evidence.md` — evidence file (task-verifier evidence blocks for Tasks 1, 2, 4).
- 2026-05-05: `docs/harness-architecture.md` — one-line entries forced by `docs-freshness-gate.sh` Rule 8 when Tasks 1 and 2 created new rule + new hook files; mandatory ancillary edit per harness-maintenance.md.

## Assumptions

- `mcp__ccd_session__spawn_task` is a third-party MCP tool with a stable `{title, prompt, tldr}` interface. We can include arbitrary text in the `prompt` field, including a sentinel that instructs the spawned session.
- Spawned sessions inherit the harness (via project `.claude/` per Decision 011 Approach A, OR via `~/.claude/` for sessions launched on the same machine) so they can read the rule file `spawn-task-report-back.md` to know what to write.
- The state directory `.claude/state/` already exists in projects that have run the harness (autonomous-done markers, scope-waivers, acceptance artifacts, user-goals all live there). Creating `spawned-task-results/` subdir on first write is idempotent (`mkdir -p`).
- The discovery-surfacer.sh pattern is the right shape for the new surfacer (silent-when-empty, clean stdout, exit 0). Reusing the pattern keeps surface-area predictable for maintainers.
- Spawned sessions don't have a reliable way to detect "I am a spawned session for task X" without an environment variable or explicit marker, so the convention relies on the prompt-instruction pattern. The orchestrator embeds the task-id in the prompt; the spawned session reads its own prompt and writes the result file accordingly.

## Edge Cases

- **Spawned session crashes before writing result.** No result file appears. Surfacer is silent. The orchestrator finds out via the absence of expected git artifacts (the spawned branch was created or wasn't). Acceptable — this is the same fallback as today's fire-and-forget mode; the convention adds value without removing the existing recovery path.
- **Spawned session writes malformed JSON.** Surfacer detects non-parsing JSON and emits a warning to stderr but doesn't block session start (mirrors discovery-surfacer's no-frontmatter handling). The orchestrator can manually fix the file and re-trigger.
- **Multiple results stack up unread.** Surfacer surfaces ALL unread results in date-then-name order, not just one. Orchestrator processes them in any order it chooses.
- **Same task-id used twice.** Convention requires monotonic task-ids (timestamp-suffixed: `<YYYY-MM-DDTHH-MM-SS>-<short-slug>`). Rule documents this; second write to the same task-id overwrites the first. Discouraged but not blocked at hook-level (would require parsing JSON to check; conservative path is convention-only).
- **Orchestrator forgets to write `.acked`.** Result re-surfaces every session. Annoying but recoverable. The repeated mention is itself a signal that the orchestrator hasn't completed the loop on a prior task.
- **Surfacer runs in a project that hasn't adopted the convention.** `.claude/state/spawned-task-results/` doesn't exist; surfacer exits 0 silently (mirrors discovery-surfacer's "directory doesn't exist" path).
- **Result file written but the orchestrator's session is terminated before next surface.** No data lost — the result file persists across session boundaries and surfaces on the next session start.

## Acceptance Scenarios

n/a — `acceptance-exempt: true` (harness-development plan with no product user).

## Out-of-scope scenarios

n/a

## Testing Strategy

- **Layer 1 (hook self-test):** `spawned-task-result-surfacer.sh --self-test` exercises 5 scenarios using temp-dir fixtures: (1) no `.claude/state/spawned-task-results/` directory at all → silent; (2) directory exists but empty → silent; (3) all results have `.acked` siblings → silent; (4) one result without `.acked` → surfaces with title in output; (5) malformed JSON file → skipped with stderr warning, surfacer still emits other valid results. Must PASS all 5.
- **Layer 2 (round-trip manual test):** in a side directory, write a sample valid result JSON without `.acked` → run surfacer → confirm output names the task-id and summary. Then `touch <result>.json.acked` → run surfacer → confirm silence.
- **Layer 3 (sync verification):** after sync to `~/.claude/`, run `bash ~/.claude/hooks/spawned-task-result-surfacer.sh --self-test` and confirm PASS. Run `diff -q adapters/claude-code/hooks/spawned-task-result-surfacer.sh ~/.claude/hooks/spawned-task-result-surfacer.sh` → no output.
- **Layer 4 (settings wiring verification):** start a fresh session in a project with at least one unread result file → confirm the hook fires (surfaces the result) before the user's first prompt. Best-effort — the SessionStart firing is implicit in the harness; if the file doesn't surface, the wiring is wrong.

## Walking Skeleton

n/a — single-phase code change with no separate skeleton-vs-full-build distinction. Tasks 1+2+4 are independent (parallel-dispatchable); Task 3 (wiring) waits for Task 2 (hook exists); Task 5 (sync) waits for all preceding tasks; Task 6 (commit) is final.

## Decisions Log

(Decisions surfaced via AskUserQuestion 2026-05-05)

### Decision: Acknowledgment mechanism — explicit `.acked` marker
- **Tier:** 1 (reversible — can change to auto-archive or age-based-prune later by editing the surfacer)
- **Surfaced to user:** 2026-05-05 via AskUserQuestion
- **Status:** chosen by user
- **Chosen:** Explicit ack via sibling `.acked` marker file
- **Alternatives:** auto-archive on first surface (simplest but lossy), age-based prune (re-surfaces for 7 days, noisy)
- **Reasoning:** most careful — no result is ever silently lost. Adds one orchestrator-side action per task (touch the marker) which is acceptable cost for the safety guarantee.
- **To reverse:** edit `spawned-task-result-surfacer.sh` to use a different acknowledgment criterion; keep the rule file in sync.

### Decision: Skill wrapper deferred — convention-only v1
- **Tier:** 1 (reversible — skill can be added in a follow-up plan)
- **Surfaced to user:** 2026-05-05 via AskUserQuestion
- **Status:** chosen by user
- **Chosen:** Convention-only, no `/spawn-with-report-back` skill in this plan
- **Alternatives:** include skill wrapper (~+1 hr scope)
- **Reasoning:** ship the smallest correct thing first. If the convention proves cumbersome (orchestrator forgets the sentinel format, generates colliding task-ids), a skill wrapper is a 30-minute follow-up.
- **To reverse:** add a follow-up plan with the skill file.

## Pre-Submission Audit

n/a — `Mode: code` plan; class-sweep audit applies to `Mode: design` plans only (per design-mode-planning.md Check 8A).

## Definition of Done

- [ ] All 6 tasks task-verified
- [ ] All hook self-tests PASS (5/5 scenarios)
- [ ] Synced files diff-clean against adapter source (per harness-maintenance.md diff loop)
- [ ] Plan flipped to Status: COMPLETED (auto-archives via plan-lifecycle.sh)
- [ ] backlog.md updated: HARNESS-GAP-08 moved from "Open work" to "Recently implemented" with commit SHA
- [ ] SCRATCHPAD.md updated to reflect new state
