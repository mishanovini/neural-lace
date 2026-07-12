# Plan: Concurrent-Ownership Gate — promote Practice 8 from Pattern to Mechanism
Status: ACTIVE
Execution Mode: direct
Mode: code
Backlog items absorbed: none
acceptance-exempt: true
acceptance-exempt-reason: harness-internal PreToolUse gate; --self-test is the demonstration
tier: 2
rung: 2
architecture: coding-harness
frozen: true
lifecycle-schema: v2
owner: operator
target-completion-date: 2026-07-12
prd-ref: n/a — harness-development

## Goal
Build the concurrent-ownership gate designed in
`docs/lessons/2026-07-11-bulk-shared-state-mutation-without-ownership-check.md`
(nl-issue [35]). The lesson's incident: a session under time pressure
bulk-flipped ALL `Status: ACTIVE` plans to DEFERRED and pushed to master —
including one plan being actively built right then by a concurrent session in
a separate same-machine worktree. The discipline that prevents this
(parallel-dev-discipline Practice 8, "claim before you build /
check-ownership-before-mutating-shared-state") exists only as a self-applied
Pattern, and the one coordination surface (`broadcast-active-session.sh`) is
per-hostname / other-machines-only — structurally blind to same-machine
worktrees. This plan makes the missing half a Mechanism: a PreToolUse gate
that BLOCKS shared-plan-state mutations whose target is owned by another live
session, plus the broadcast extension that makes same-machine ownership
visible.

## User-facing Outcome
n/a — harness-internal: the user is the maintainer. After this plan ships, a
session that attempts the lesson's golden scenario (bulk-defer of
`docs/plans/*.md` including a plan whose branch is checked out in another
worktree) is BLOCKED with a message naming the owning worktree path + branch
and the coordination path, instead of silently corrupting shared trunk state.
The `--self-test` of the gate passing IS the demonstration (constitution §4).

## Scope
- IN: new PreToolUse hook `adapters/claude-code/hooks/concurrent-ownership-gate.sh`
  (Bash|PowerShell command parsing + Edit/Write/MultiEdit payload parsing,
  ownership check via `git worktree list --porcelain` + fresh same-machine
  claims, structured <1h purpose-clause waiver escape hatch, ledger-logged,
  `--self-test` with sandboxing); extension of
  `adapters/claude-code/scripts/broadcast-active-session.sh` (same-machine
  worktree listing in state JSON + per-branch local claim/unclaim subcommands,
  backward compatible); registration in `adapters/claude-code/manifest.json`
  (golden_scenario / fp_expectation / retirement_condition per constitution
  §10); wiring in `adapters/claude-code/settings.json.template` (PreToolUse,
  both matcher groups).
- OUT: installing to `~/.claude/` (live install happens via install.sh after
  master merge — never hand-edited from a builder worktree); upstream
  launcher-written authoritative per-branch locks (named as the retirement
  condition, not built here); changes to `parallel-dev-discipline.md` prose;
  any push or PR creation (builder worktree commits only); cross-machine
  claim propagation (the existing per-hostname remote broadcast already
  covers other machines).

## Tasks

- [x] 1. Author `adapters/claude-code/hooks/concurrent-ownership-gate.sh` —
  PreToolUse gate with command-segment parsing (cd/Set-Location tracking +
  `git -C` composition per scope-enforcement-gate.sh's pattern), Edit/Write
  payload handling, ownership check (other-worktree checkout via
  `git worktree list --porcelain`, fresh other-session claim), block message
  naming owning worktree + branch + coordination path, structured waiver
  (fresh <1h, purpose clauses via `lib/waiver-purpose-clause.sh`, target-
  scoped, ledger-logged via `lib/signal-ledger.sh`), and a sandboxed
  `--self-test` covering the golden scenario + clean pass + waiver honored —
  Verification: mechanical — Docs impact: none — gate header comment is the doc; manifest entry carries the §10 evidence fields
- [x] 2. Extend `adapters/claude-code/scripts/broadcast-active-session.sh`
  with same-machine worktree visibility (`worktrees` array in state JSON,
  additive) and local per-branch claims (`claim` / `unclaim` subcommands +
  claims surfaced by `check`), keeping existing state.json consumers
  compatible (field-extraction via sed tolerates added fields; verified: the
  only consumers are this script's own `check` and the SessionStart template
  invocation) — Verification: mechanical — Docs impact: none — usage text inside the script is updated in the same change
- [x] 3. Register the gate in `adapters/claude-code/manifest.json` (kind:
  gate, blocking: true, golden_scenario / fp_expectation /
  retirement_condition from the lesson) and wire it in
  `adapters/claude-code/settings.json.template` under PreToolUse for both
  `Bash|PowerShell` and `Edit|Write|MultiEdit` matchers — Verification: mechanical — Docs impact: none — manifest IS the enforcement inventory doc
- [x] 4. Run `bash adapters/claude-code/hooks/concurrent-ownership-gate.sh
  --self-test` and `bash adapters/claude-code/scripts/broadcast-active-session.sh
  --self-test`; both must exit 0 with all scenarios PASS — Verification: mechanical — Docs impact: none — evidence is the pasted summary lines in the builder report

## Files to Modify/Create
- `docs/plans/concurrent-ownership-gate-2026-07-12.md` — this plan (committed first)
- `adapters/claude-code/hooks/concurrent-ownership-gate.sh` — NEW: the PreToolUse gate + self-test
- `adapters/claude-code/scripts/broadcast-active-session.sh` — extend: same-machine worktrees + per-branch claims + self-test scenarios
- `adapters/claude-code/manifest.json` — register the gate (constitution §10 evidence fields)
- `adapters/claude-code/settings.json.template` — wire the gate under PreToolUse (both matcher groups)

## In-flight scope updates
- 2026-07-12: `docs/harness-architecture.md` — docs-freshness gate (Rule 8) requires the architecture doc in the same commit as a new hook; regenerated via `scripts/gen-architecture-doc.sh` from the manifest (generation, not hand-edit)

## Assumptions
- `git worktree list --porcelain` output is stable across the git versions in
  use (paths on `worktree ` lines, branches on `branch refs/heads/...` lines)
  — the cheapest, most reliable same-machine ownership signal per the lesson.
- Plan slugs relate to branch names by substring after stripping the
  `-YYYY-MM-DD` date suffix and any `<type>/` branch prefix (the observed
  harness convention: plan `foo-bar-2026-07-11.md` ↔ branch `feat/foo-bar`).
  A slug too short to match reliably (< 4 chars after stripping) is never
  ownership-matched (fail-open, keeps FP low).
- `jq` is available in hook context (same dependency posture as
  scope-enforcement-gate.sh and spec-freeze-gate.sh; the gate passes through
  without it, erring toward allow).
- Local claims live under `~/.claude/state/active-session-broadcast/claims/`
  (same-machine coordination is filesystem-local; cross-machine remains the
  existing remote broadcast). File mtime is the freshness clock.
- The live session's hooks come from `~/.claude/` — nothing in this worktree
  fires until merged + installed, so building the gate cannot block this
  builder session itself.

## Edge Cases
- **Own-plan mutation must pass:** the flip/move of a plan whose slug matches
  the CURRENT worktree's checked-out branch is the normal close-plan flow —
  ownership is defined as another worktree/claim, so self-mutation never
  blocks.
- **Bulk mutation with a glob/loop:** the concrete file list is unknowable
  from the command string, so the gate evaluates ALL top-level
  `docs/plans/*.md` ACTIVE plans; if ANY is owned elsewhere the whole bulk
  command blocks (that is exactly the golden scenario's shape).
- **Read-only bulk commands** (`grep -l 'Status: ACTIVE' docs/plans/*.md`,
  `cat`, `ls`) must NOT block — the gate requires a mutation indicator
  (in-place edit flag, redirect, or mv) in the same command.
- **`git branch -D` of a branch checked out elsewhere:** git itself would
  refuse, but the gate blocks first with the coordination message naming the
  owning worktree (better remediation than git's error).
- **`git worktree remove`:** a worktree is by definition "checked out", so
  blocking every removal would be pure FP; the gate blocks only when a fresh
  other-session claim covers that worktree/branch.
- **Stale claims:** claims older than the freshness window (default 2h by
  mtime) are ignored — no explicit cleanup needed, mirroring the remote
  broadcast's staleness design.
- **Detached-HEAD worktrees / missing branch lines:** porcelain entries
  without a `branch` line are skipped (nothing to own by branch name).
- **Repos without `docs/plans/`:** plan-mutation checks are vacuous; branch/
  worktree checks still apply (they are repo-shape-independent).
- **Self-test sandboxing:** `HARNESS_SELFTEST=1` + explicit
  `COG_CLAIMS_DIR` / `SIGNAL_LEDGER_PATH` overrides route every read/write to
  tempdirs; the self-test never touches real state (the signal-ledger lib
  additionally auto-sandboxes under HARNESS_SELFTEST).

## Acceptance Scenarios
n/a — harness-dev plan, no product user; see acceptance-exempt-reason above.
The gate's `--self-test` scenarios are the acceptance surface.

## Out-of-scope scenarios
None — all coverage lives in the self-tests; no product-user scenarios apply.

## Closure Contract
- **Commands that run:** `bash adapters/claude-code/hooks/concurrent-ownership-gate.sh --self-test` and `bash adapters/claude-code/scripts/broadcast-active-session.sh --self-test`
- **Expected outputs:** both exit 0; gate self-test reports all scenarios PASS including golden-bulk-block, clean-pass, waiver-honored; broadcast self-test reports all scenarios PASS including the new claim/worktree scenarios.
- **On-disk artifact location:** self-test summary lines pasted in the builder completion report for this plan (acceptance-exempt harness plan; the self-test PASS is the closure target).
- **Done when:** this plan is DONE when all tasks are task-verifier PASS AND both self-tests exit 0 with their summary lines captured in the report.

## Testing Strategy
- Gate `--self-test` (sandboxed, tmp fixture repos with a real
  `git worktree add`): (1) GOLDEN — bulk `for f in docs/plans/*.md; do sed -i
  's/^Status: ACTIVE/Status: DEFERRED/'` in a repo where one plan's branch is
  checked out in a second worktree → exit 2 AND stderr names the owning
  worktree path + branch; (2) CLEAN PASS — single-file Status flip of an
  unowned plan → exit 0; (3) WAIVER HONORED — fresh <1h purpose-clause waiver
  naming the target → exit 0 + ledger entry in the sandboxed ledger;
  (4) stale (>1h) waiver → exit 2; (5) Edit-tool payload Status flip of the
  owned plan → exit 2; (6) Edit of one's OWN plan from its owning worktree →
  exit 0; (7) `git branch -D` of the other-worktree branch → exit 2;
  (8) `git worktree remove` under a fresh other-session claim → exit 2;
  (9) claim-based (no worktree) ownership → exit 2; (10) non-plan command →
  exit 0; (11) read-only bulk grep → exit 0; (12) PowerShell tool_name parses
  identically → exit 2.
- Broadcast `--self-test`: existing S1–S6 stay green; new scenarios cover
  claim-file schema, worktrees-array presence in state JSON, and unclaim
  removal — all against a sandboxed `BROADCAST_STATE_DIR`.
- Manual wiring check: `grep concurrent-ownership-gate
  adapters/claude-code/settings.json.template adapters/claude-code/manifest.json`
  shows both registrations.

## Walking Skeleton
Walking Skeleton: n/a — single-hook harness change; the gate's golden-scenario
self-test is itself the end-to-end slice (stdin JSON → parse → ownership check
→ block decision).

## Decisions Log
- 2026-07-12: `frozen: true` at creation — the spec is the already-reviewed
  design in the 2026-07-11 lesson (golden scenario, FP expectation, retirement
  condition all pre-specified); freezing at creation lets the declared files
  be edited under this plan without a spec-freeze waiver. Reversible (flip to
  false) if review reopens the design.
- 2026-07-12: `git worktree remove` blocks only on a fresh other-session
  claim (not on mere worktree existence) — a worktree is always "checked
  out", so existence-blocking would false-fire on every legitimate prune;
  the claim is the live-session signal. Matches the lesson's "low FP" bar.
- 2026-07-12: bulk mutations evaluate ALL on-disk ACTIVE plans because the
  command string's glob/loop makes the concrete target list unknowable
  pre-execution; blocking on ANY owned member is the conservative reading of
  the golden scenario. Reversible by narrowing the bulk heuristic.
- 2026-07-12: claims are local files under
  `~/.claude/state/active-session-broadcast/claims/` keyed by sanitized
  branch name, freshness by mtime (2h default) — same staleness-not-cleanup
  design as the remote broadcast; the gate and the broadcast script share the
  directory so ownership has one home.

## Definition of Done
- [ ] All tasks checked off
- [ ] All tests pass
- [ ] Linting/formatting clean
- [ ] SCRATCHPAD.md updated with final state
- [ ] Completion report appended to this plan file
