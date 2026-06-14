# Plan: Register-Driven-Session Enforcement (the anti-babysitting mechanism)
Status: ACTIVE
Execution Mode: orchestrator
Mode: code
Backlog items absorbed: none
acceptance-exempt: true
acceptance-exempt-reason: harness-internal work; the two hooks' --self-test suites are the acceptance artifact; there is no product user-facing surface.
tier: 2
rung: 1
architecture: coding-harness
frozen: true
prd-ref: n/a — harness-development

## Goal
Make "the orchestrator owns the cross-machine INCOMPLETE-WORK register and drives
it down, rather than re-emitting 'awaiting Misha' lists as if they were progress"
STRUCTURAL rather than discipline-only. Misha's directive (2026-06-13): the proof
must be the mechanism existing and firing, not a verbal commitment to ownership.

## User-facing Outcome
The harness operator (Misha) gets two guarantees with zero reliance on agent
memory: (1) the INCOMPLETE-WORK register is surfaced at every session start, so no
session can be blind to what still needs building; (2) a working session cannot
end by treating an "awaiting Misha" list as progress — it must either advance a
register item (with completion evidence) or name a specific genuine blocker.

## Scope
- IN: two new hooks (`register-surfacer.sh` SessionStart, `register-progress-gate.sh`
  Stop), their wiring in `settings.json.template`, a `config/register-path.example`
  pointer-convention example, and the `docs/harness-architecture.md` inventory update.
- OUT: changes to product code; changes to the register's content (the register lives
  in the separate cross-machine `workstreams-coordination` repo); a scheduled
  re-census hook (future RWR follow-up); per-item RWR-ID schema enforcement.

## Tasks
- [x] 1. `register-surfacer.sh` SessionStart hook — resolve + extract LIST 1, capped, silent-on-missing. — Verification: mechanical
- [x] 2. `register-progress-gate.sh` Stop hook — block working-session awaiting-list-with-no-progress. — Verification: mechanical
- [x] 3. Wire both into `settings.json.template` (and live `~/.claude/settings.json`) + ship `config/register-path.example` + update `docs/harness-architecture.md`. — Verification: mechanical

## Files to Modify/Create
- `adapters/claude-code/hooks/register-surfacer.sh` — new SessionStart surfacer.
- `adapters/claude-code/hooks/register-progress-gate.sh` — new Stop gate.
- `adapters/claude-code/settings.json.template` — wire both hooks into the SessionStart + Stop chains.
- `adapters/claude-code/config/register-path.example` — pointer-convention example for the coordination-repo path.
- `docs/harness-architecture.md` — changelog header + 2 inventory rows.

## In-flight scope updates
(no in-flight changes yet)

## Assumptions
- The cross-machine register lives at `<coordination-root>/INCOMPLETE-WORK-REGISTER-*.md`
  and is resolvable via `~/.claude/config/register-path` on each machine.
- The Stop transcript exposes `tool_use` records with a `name`/`tool_name` field and the
  final assistant message as a `text` field (the same shape sibling Stop hooks read).
- `lib/stop-hook-retry-guard.sh` exposes `retry_guard_session_id` + `retry_guard_block_or_exit`.

## Edge Cases
- No register resolvable on this machine → surfacer exits 0 silently (never blocks session start).
- Conversational (non-working) session ending with an awaiting-list → gate exits 0 (not subject).
- Genuinely-blocked working session → operator writes `.claude/state/register-blocker-<ts>.txt` naming
  the specific item → gate allows.
- Retry loop the agent cannot resolve → 3-retry downgrade-to-warn via the shared retry-guard.

## Acceptance Scenarios
n/a — acceptance-exempt (harness-internal). The two hooks' `--self-test` suites
(surfacer 4/4, gate 7/7) are the acceptance artifact.

## Out-of-scope scenarios
- Browser/runtime acceptance: not applicable; no product surface.

## Testing Strategy
- `register-surfacer.sh --self-test` (4 scenarios) + end-to-end run against the live register.
- `register-progress-gate.sh --self-test` (7 scenarios: BLOCK on babysitting; ALLOW on evidence /
  no-awaiting / conversational / named-blocker / disable / warn-mode).
- Live-wiring verified: both hooks present in template AND live `~/.claude/settings.json`; both JSON valid.

## Walking Skeleton
The thinnest end-to-end slice IS each hook's self-test: a synthetic transcript +
synthetic register exercise the full resolve → extract (surfacer) and the full
working-session → awaiting-signature → no-evidence → block (gate) path. Self-test
passing == the harness's user-facing outcome (the harness user is the maintainer).

## Decisions Log
- Gate keyed on the FINAL assistant message (not whole transcript) + a WORKING-session
  precondition (tool_use present), to avoid false-firing on conversational turns. Block-mode
  default (mirrors `pr-health-snapshot-gate.sh` / `completion-criteria-gate.sh`), because the
  whole point is a hard structural floor, not advisory. Tier 2 / rung 1: single-purpose hook
  pair, no behavioral contract surface.

## Pre-Submission Audit
- S1 (Entry-Point Surfacing): n/a — Mode: code harness-infrastructure plan, single coherent change.
- S2 (Existing-Code-Claim Verification): swept — `lib/stop-hook-retry-guard.sh` fn signatures confirmed by read.
- S3 (Cross-Section Consistency): swept — Scope IN/OUT consistent with Files + Tasks.
- S4 (Numeric-Parameter Sweep): swept — `REGISTER_SURFACE_MAX` default 12, retry threshold 3, blocker TTL 3600s — all single-valued.
- S5 (Scope-vs-Analysis Check): swept — every "new"/"wire" verb targets a file listed IN scope.

## Definition of Done
- [x] All tasks checked off
- [x] Both hooks' --self-test pass (surfacer 4/4, gate 7/7)
- [x] Wired in template + live settings.json (both JSON valid)
- [x] harness-architecture.md updated
- [x] Register item RWR-00 recorded
