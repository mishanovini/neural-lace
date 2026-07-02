# Plan: Register-Driven-Session Enforcement (the anti-babysitting mechanism)
Status: COMPLETED
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
- 2026-06-13: `adapters/claude-code/hooks/register-progress-gate.sh` — re-opened from COMPLETED after Misha extended scope ("build this, but think about edge cases"). Edge-case hardening EC-1 (transcript-commit allow) + EC-2 (precise jq last-assistant extraction); self-test 7→10. The plan was not actually done when first closed; this is its real completion.

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

## Evidence Log
- Task 1 (register-surfacer.sh) — Verification: mechanical. `register-surfacer.sh --self-test` → 4/4 PASS. End-to-end run against the live cross-machine register surfaced LIST 1 correctly. Commit 6ce9f22 (on origin/master, PROVEN ancestor).
- Task 2 (register-progress-gate.sh) — Verification: mechanical. `register-progress-gate.sh --self-test` → 10/10 PASS (BLOCK on babysitting; ALLOW on evidence / no-awaiting / conversational / named-blocker / disable / warn-mode; + EC-1 transcript-commit allow [T8]; + EC-2 precise-extraction-ignores-tool_result [T9] + babysitting-still-blocks regression [T10]). Commit 6ce9f22; edge-case hardening (EC-1 + EC-2) added 2026-06-13 per Misha.
- Task 3 (wiring + config + arch doc) — Verification: mechanical. Both hooks present in `settings.json.template` AND live `~/.claude/settings.json` (both JSON valid via `node JSON.parse`). `config/register-path.example` shipped; `~/.claude/config/register-path` pointer written on this machine. `docs/harness-architecture.md` updated (changelog header + 2 inventory rows), re-applied cleanly on origin/master after the 64-commit rebase. Commit 6ce9f22.

## Completion Report

### 1. Implementation Summary
Shipped both hooks of the register-driven-session enforcement mechanism (RWR-00) — the structural answer to Misha's directive that ownership of the INCOMPLETE-WORK register be enforced, not promised. `register-surfacer.sh` (SessionStart) + `register-progress-gate.sh` (Stop), both block-mode, both self-tested, wired template + live, on origin/master at 6ce9f22. Backlog items absorbed: none.

### 2. Design Decisions & Plan Deviations
Gate keyed on the FINAL assistant message + a WORKING-session precondition (avoids false-firing on conversational turns). Block-mode default mirrors `pr-health-snapshot-gate.sh` / `completion-criteria-gate.sh`. No deviations from plan scope. The 64-commit rebase onto origin/master required re-applying the `harness-architecture.md` changelog + table rows on origin's newer base (settings.json.template auto-merged cleanly).

### 3. Known Issues & Gotchas — Edge-Case Audit (per Misha 2026-06-13)

Adversarial pass over both hooks. Two were HARDENED in this session (gate self-test 7→10); the rest are accepted-residual with rationale.

**HARDENED:**
- **EC-1 — false-positive blocking a session that DID work but reported poorly.** A session that committed/pushed real work but ended with an awaiting phrase and no evidence *token* in the final message would have been wrongly blocked. Block-mode false-positives are the dangerous failure (they train bypass). Fix: `session_advanced_in_transcript()` — if the transcript has a real `git commit`/`git push` tool_use, the session advanced → ALLOW + stderr nudge to cite it. (self-test T8.) jq-only by design (reads `tool_use.input.command`, not loose prose); without jq it falls back to the stricter final-message-only logic (safe direction).
- **EC-2 — imprecise final-message extraction.** The original `tail -400 | grep "text"` could match a `tool_result`'s text, causing both false-pos (an awaiting phrase quoted in a tool result) and false-neg. Fix: precise jq extraction of the LAST *assistant-role* message (the proven `pr-health-snapshot-gate.sh` pattern), grep fallback only when jq absent. (self-test T9 + T10 regression.)

**ACCEPTED-RESIDUAL (with rationale):**
- **EC-3 — Goodhart / fake evidence tokens.** An agent could append "DONE: / merged / RWR-01" to pass without working. The gate is a FLOOR, not a proof — backed by NO-TRUST verification (the cited SHA must actually resolve, checked downstream by the orchestrator/Misha). EC-1's transcript-scan lets the honest case pass without gaming; the dishonest case is caught at NO-TRUST. Same residual every evidence-gate has (vaporware-prevention.md "verbal vaporware" gap).
- **EC-4 — false-negative: working-session detection misses an unusual tool shape.** Then a real working session reads as "conversational" → gate no-ops. This is the *safe* failure direction (never blocks a legitimate session); EC-1's commit-scan widens coverage.
- **EC-5 — cloud/Dispatch sessions don't load `~/.claude/` hooks.** Genuine cloud sessions run neither hook (the documented cloud blind spot, same as every Stop hook). Not fixable at this layer; the operator's desktop+Dispatch workflow is local and covered.
- **EC-6 — surfacer picks the wrong register if multiple `INCOMPLETE-WORK-REGISTER-*.md` exist (newest-by-mtime).** The operator maintains one register; `ls -t` could pick a touched-but-old file. Low impact (surfacer only informs, never blocks). Candidate follow-up: sort by filename-date instead of mtime.
- **EC-7 — surfacer silently surfaces nothing if the pointer is misconfigured.** Deliberate (never disrupt session start). Trade-off: a broken pointer is invisible. Acceptable — non-catastrophic, and the load-bearing gate is independent of the surfacer.
- **EC-8 — `base64 --decode` is GNU/GitBash syntax (macOS needs `-D`).** Consistent with sibling gates already in the harness; on failure the `|| printf ''` fallback returns empty → gate exits 0 (never blocks blind). Safe degradation.

The retry-guard's 3-retry downgrade-to-warn remains the loop-break for any case the agent genuinely cannot satisfy.

### 4. Manual Steps Required
On each additional machine: write `~/.claude/config/register-path` (one line: the coordination-repo path) so the surfacer resolves the register. `install.sh` propagates the live `settings.json` wiring per the HARNESS-GAP-14 template-vs-live split.

### 5. Testing Performed & Recommended
Performed: surfacer 4/4 + gate 7/7 self-tests (on both the canonical and rebased trees); end-to-end surfacer run against the live register; live `~/.claude/settings.json` JSON validity. Recommended: observe the gate's real-session behavior over the next several sessions; tune the awaiting/evidence regexes if false-fires appear.

### 6. Cost Estimates
Zero recurring cost — two local bash hooks firing at SessionStart / Stop (sub-second each).
