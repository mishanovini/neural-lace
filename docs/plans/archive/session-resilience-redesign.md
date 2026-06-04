# Plan: Session-Resilience Redesign — Survive (or Recover From) Terminal Death
Status: DEFERRED
<!-- DEFERRED 2026-06-04 by stale-ACTIVE-plan cleanup. Design phase shipped (plan PR #12, ADR 040 + terminal-death discovery on HEAD). The entire R1–R7 implementation roadmap is unbuilt (dispatch-preflight-gate.sh, handoff-heartbeat.sh, transcript-ceiling-gate.sh, topic-shift-surfacer.sh all absent), no commits in 9 days. RE-ENGAGE TRIGGER: when session-resilience implementation is scheduled — flip back to ACTIVE, restore from archive. Reversible. -->
Execution Mode: orchestrator
Mode: design
Backlog items absorbed: none
acceptance-exempt: true
acceptance-exempt-reason: Harness-development plan; the "user" is the maintainer and each shipped component's `--self-test` PASS is its acceptance artifact. No product UI surface exists.
tier: 3
rung: 2
architecture: coding-harness
frozen: false
prd-ref: n/a — harness-development
owner: Misha
target-completion-date: 2026-07-31

<!-- `owner:` / `target-completion-date:` model the ADR-036 schema (Pattern 1),
     dogfooded here; today's plan-reviewer.sh does not yet check them. -->

## Goal

Make Claude Code sessions **survive the conditions that kill them, or recover
from death with bounded loss** — eliminating, at the structural root, the four
terminal-death classes catalogued in
`docs/discoveries/2026-05-25-session-resilience-terminal-death-catalog.md`
(FM-030 mega-session prompt-too-long; FM-031 oversized subagent dispatch;
FM-032 transport-level transient death with no resumable handoff; FM-033 no
transcript-size ceiling). Today the harness has **zero** in-session resilience
machinery: every Gen 4–6 mechanism gates *correctness*, none gates *survival*.

The redesign is purely **mechanical** (no advisory "remember to /clear" rules)
and purely **curative** (it fixes the death conditions, not their symptoms) —
and it is built on an explicit **three-layer curability model** (ADR 040-a) that
keeps it honest: each layer gets the strongest mechanism that layer permits, and
the boundary of harness power (API-transport retry is platform-owned, NOT
hook-reachable) is *stated*, not papered over with a wrapper that would silently
not work. That honesty is the "no false promises" constraint made structural.

**This plan is design-only.** Its deliverable is the design + ADR + discovery +
roadmap. Implementation happens in subsequent sessions (R1–R7 in `## Tasks`),
each gated on Misha's authorization and each small enough to ship without
prompt-too-long risk (the plan is itself an exercise in the discipline it
designs).

## Scope

- IN: Design of the four mechanisms — (1) `dispatch-preflight-gate.sh` Layer-1
  PreToolUse `Task|Agent` size guard; (2) `handoff-heartbeat.sh` PostToolUse
  always-fresh-handoff writer + the resume protocol; (3) `transcript-ceiling-gate.sh`
  Layer-2 SessionStart+PostToolUse byte-ceiling enforce; (4) `retry-with-backoff.sh`
  Layer-1 Bash-subprocess transient-retry wrapper with irreversible-op denylist;
  (5) `topic-shift-surfacer.sh` Layer-2 UserPromptSubmit advisory. The
  spawnable-mode auto-respawn + the interactive surface-and-resume path. The
  10-section Systems Engineering Analysis. The self-test design (esp. the
  no-false-positive suites). The ordered implementation roadmap. The
  `rules/session-resilience.md` rule (R7).
- IN: The three-layer curability model as the design's organizing spine (ADR 040).
- OUT: Any implementation (hooks, scripts, rule files, settings wiring). The only
  files THIS session writes are documentation: this plan, ADR 040, the discovery,
  and the DECISIONS.md index row.
- OUT: Editing `docs/failure-modes.md` to add FM-030..033. The discovery authors
  the proposed entries; promotion into the canonical catalog is roadmap R7.
- OUT: Any change to Claude Code's own API-transport retry behavior (Layer 3 is
  platform-owned per ADR 040-a / 040-c). The harness mitigates Layer-3 death
  frequency (load reduction) and bounds its loss (handoff), but does not — and
  cannot — retry the dead connection from inside.
- OUT: Pattern 1 (plan-lifecycle) and Pattern 3 (file-lifecycle) scope. This is
  Pattern 4; it composes with them but ships independently.

## Tasks

The tasks below ARE the implementation roadmap. Each is a self-contained future
session. THIS design session checks off NONE of them. They are ordered by
dependency and leverage; each ships its component with a `--self-test`
(harness-internal → `Verification: mechanical`).

- [ ] R1. Dispatch pre-flight guard (Layer 1; highest leverage, fully independent). Build `dispatch-preflight-gate.sh` (PreToolUse `Task|Agent`): measure `tool_input.prompt` byte size against a configurable budget (`~/.claude/local/resilience.config.json`, with a default); BLOCK over-budget with a split/trim remediation message (ADR 040-b — never auto-trim). Wire in `settings.json.template`; arch-doc; self-test. Resolve §D1 (byte budget) at build time. Verification: mechanical
- [ ] R2. Heartbeat handoff writer (the Layer-3 recovery floor everything leans on). Build `handoff-heartbeat.sh` (PostToolUse, counter-keyed by `CLAUDE_SESSION_ID` mirroring `tool-call-budget.sh`): once per N tool-calls, write/refresh the handoff (SCRATCHPAD + a `.claude/state/resume-<session>.md` resume pointer) so it is fresh regardless of death mode. Define the resume-pointer format. Reuse `session-wrap.sh refresh` machinery; do NOT duplicate archival. Resolve §D4 (interval N). Verification: mechanical
- [ ] R3. Transcript-size ceiling gate (Layer 2 mechanical hard enforce). Build `transcript-ceiling-gate.sh` (SessionStart + PostToolUse heartbeat): `wc -c $TRANSCRIPT_PATH`; soft threshold → ensure R2 handoff fresh + warn; hard threshold (below platform limit) → force handoff-write + emit stop/`/clear`-and-resume directive. Integrates with R2. Resolve §D2 (thresholds). Verification: mechanical
- [ ] R4. Bash retry-with-backoff wrapper (Layer-1 subprocess transient errors). Build `retry-with-backoff.sh` (script the agent invokes): exp backoff, 3 attempts, transient-vs-terminal classification, irreversible-op denylist (ADR 040-c — refuse retry on `git commit|push`, `gh pr merge|create`, migrations; default-deny on uncertain). Author the companion discipline in `rules/session-resilience.md`. Resolve §D3 (is PreToolUse input-modification supported → can it ever auto-wrap, or invocation-discipline only). Verification: mechanical
- [ ] R5. Topic-shift advisory surfacer (Layer 2 advisory). Build `topic-shift-surfacer.sh` (UserPromptSubmit): on the measurable proxy (transcript past soft threshold AND new prompt shares no file/plan-slug/scope token with recent window), inject an `additionalContext` `/clear` recommendation. Advisory only — never blocks (ADR 040-d). Low false-positive tuning; self-test the proxy heuristic. Verification: mechanical
- [ ] R6. Resume protocol + spawnable-mode auto-respawn ("the bootstrap mechanism"). Define the resume protocol a fresh session runs (read `.claude/state/resume-<session>.md` → reconstruct context). For spawnable modes (Dispatch/scheduled/remote), wire ceiling-triggered auto-spawn handing the fresh session the handoff path; for interactive, the mechanical surface-and-`/clear` directive (ADR 040-e — no false promise of auto-spawning a terminal). Depends on R2+R3. Verification: mechanical
- [ ] R7. Integration test + rule/catalog finalization. End-to-end: oversized-dispatch-blocked (R1) → growth → heartbeat-handoff-fresh (R2) → ceiling-forces-handoff (R3) → simulated-death → fresh-session-resumes-with-bounded-loss (R6); plus retry-wrapper denylist (R4) and topic advisory (R5). Promote FM-030..033 into `docs/failure-modes.md`. Finalize `rules/session-resilience.md`; arch-doc; sync live mirror. Verification: mechanical

## Files to Modify/Create

(Future-session targets — each roadmap session has a frozen file set. THIS
session writes only the documentation files marked ✎.)

- `docs/plans/session-resilience-redesign.md` — ✎ this design plan (this session)
- `docs/decisions/040-session-resilience-three-layer-model.md` — ✎ ADR (this session)
- `docs/DECISIONS.md` — ✎ index row for ADR 040 (this session)
- `docs/discoveries/2026-05-25-session-resilience-terminal-death-catalog.md` — ✎ catalog discovery (this session)
- `adapters/claude-code/hooks/dispatch-preflight-gate.sh` — R1: NEW PreToolUse `Task|Agent` guard
- `adapters/claude-code/hooks/handoff-heartbeat.sh` — R2: NEW PostToolUse heartbeat handoff writer
- `adapters/claude-code/hooks/transcript-ceiling-gate.sh` — R3: NEW SessionStart+PostToolUse ceiling gate
- `adapters/claude-code/scripts/retry-with-backoff.sh` — R4: NEW Bash retry wrapper
- `adapters/claude-code/hooks/topic-shift-surfacer.sh` — R5: NEW UserPromptSubmit advisory
- `adapters/claude-code/scripts/session-wrap.sh` — R2: reuse refresh machinery for the heartbeat (extend, do not duplicate)
- `adapters/claude-code/examples/resilience.config.example.json` — R1/R2/R3: NEW thresholds config (byte budget, ceiling, interval N)
- `adapters/claude-code/settings.json.template` — R1/R2/R3/R5: wire new hooks
- `adapters/claude-code/rules/session-resilience.md` — R4/R7: NEW rule (retry discipline + resume protocol + the layer model)
- `docs/failure-modes.md` — R7: promote FM-030..033 from the discovery
- `docs/harness-architecture.md` — R1–R7: inventory updates per `harness-maintenance.md`

## Assumptions

- A PreToolUse `Task|Agent` hook can read `tool_input.prompt` before dispatch
  (confirmed — `teammate-spawn-validator.sh` already reads `tool_input` fields on
  this exact matcher).
- `$TRANSCRIPT_PATH` is available to PostToolUse / SessionStart / Stop hooks and
  points at the JSONL transcript whose byte size is a usable growth proxy
  (confirmed — 9 Stop hooks read it; `wc -c` on it is cheap).
- A PostToolUse counter keyed by `CLAUDE_SESSION_ID` with `flock` is a proven
  pattern for "on an N-tool-call interval" (confirmed — `tool-call-budget.sh` does
  exactly this).
- `session-wrap.sh refresh` is the existing handoff writer (ADR 027 Layer 5) and
  fires only at clean Stop; the heartbeat (R2) generalizes its freshness to
  every-N-calls so sudden deaths leave a fresh handoff (confirmed by reading
  `session-wrap.sh` this session).
- Whether PreToolUse can MODIFY `tool_input` (to auto-trim / auto-wrap) is NOT
  confirmed for the installed version — R1 (block-not-trim) and R4
  (invocation-discipline wrapper) are designed to NOT depend on it; §D3 confirms
  the capability before any auto-wrap is attempted.
- The platform context limit (the byte ceiling R3 must stay below) and the exact
  `bold-albattani` dispatch-prompt sizes are NOT available this session — §D1/§D2
  calibrate them at build time against real measurements.
- Layer-3 transport deaths skip the Stop hook (no clean stop) — so the heartbeat,
  not the Stop hook, is the only mechanism that can keep a handoff fresh through
  them (the core FM-032 reasoning).

## Edge Cases

- **Dispatch prompt exactly at budget** → allow (block only strictly over); the
  budget is set with margin below the real prompt-too-long ceiling.
- **Legitimately large dispatch prompt** (a genuinely big task spec) → blocked;
  remediation is split-the-dispatch, not raise-the-budget-silently. Raising the
  budget is a deliberate config edit, surfaced.
- **Heartbeat fires mid-irreversible-op** → heartbeat only WRITES a handoff file
  (idempotent, no side effects on the work); safe to fire any time.
- **Transcript ceiling hit during a single long tool call** → caught on the next
  PostToolUse heartbeat; the in-call growth is bounded by one tool result.
- **Topic-shift proxy false-positive** (new prompt legitimately continues prior
  work but shares no literal token) → advisory only, costs the agent one ignored
  suggestion; never blocks (the explicit reason topic-shift is advisory not
  enforcing, ADR 040-d).
- **Retry wrapper wraps an irreversible command** → denylist refuses retry, runs
  once; default-deny on unrecognized commands.
- **Retry wrapper on a deterministically-failing command** (compile error) →
  terminal signature, fail loudly, no retry (do not mask real failures as
  transient).
- **Death between heartbeat writes** → loss bounded to ≤ N tool calls (the
  heartbeat interval); this is the designed loss bound, not zero.
- **Interactive-local session hits hard ceiling** → handoff written + `/clear`
  directive surfaced; NO auto-spawn (the harness cannot open a terminal — ADR
  040-e); the bound is honest.
- **Spawnable-mode session hits hard ceiling** → handoff written + auto-spawn of
  a fresh session with the handoff path (R6).
- **`$TRANSCRIPT_PATH` unset / unreadable** → ceiling gate no-ops (allow); never
  block on a missing measurement substrate (harness convention).

## Acceptance Scenarios

(This plan is `acceptance-exempt: true` — harness-development. Closure target is
self-test PASS per component, recorded in `## Closure Contract`. No product
runtime scenarios apply.)

- n/a — harness-development; each roadmap component's `--self-test` is its
  acceptance artifact. The integration test (R7) is the end-to-end equivalent,
  including a simulated-death → resume-with-bounded-loss exercise.

## Closure Contract

- **Commands that run (per component, at R-session close):**
  `bash adapters/claude-code/hooks/dispatch-preflight-gate.sh --self-test` (R1),
  `bash adapters/claude-code/hooks/handoff-heartbeat.sh --self-test` (R2),
  `bash adapters/claude-code/hooks/transcript-ceiling-gate.sh --self-test` (R3),
  `bash adapters/claude-code/scripts/retry-with-backoff.sh --self-test` (R4),
  `bash adapters/claude-code/hooks/topic-shift-surfacer.sh --self-test` (R5),
  plus the R7 integration test script.
- **Expected outputs:** each `--self-test` exits 0 with "N passed, 0 failed".
- **On-disk artifact location:** structured evidence at
  `docs/plans/session-resilience-redesign-evidence/<R-task-id>.evidence.json`
  (verdict PASS) per the Tranche B mechanical-evidence substrate.
- **Done when:** all of R1–R7 are task-verifier PASS AND every component's
  `--self-test` exits 0 AND the R7 integration test passes the simulated-death →
  bounded-loss-resume path end-to-end. (THIS plan, design-only, is "done for the
  design phase" when the design docs land and systems-designer PASSes; it stays
  ACTIVE through implementation.)

## Testing Strategy

Per-component `--self-test` is the verification idiom. The load-bearing suites:

**R1 dispatch guard:** under-budget `Task` → ALLOW; over-budget `Task` → BLOCK;
over-budget `Agent` → BLOCK; non-dispatch tool (Edit) → ALLOW; missing
`tool_input.prompt` → ALLOW (no measurement); config-absent → default budget
applied.

**R2 heartbeat (no-loss-on-death suite):** N-1 calls → no write yet; Nth call →
handoff written + resume pointer fresh; resume pointer parseable by a fresh
session; idempotent re-fire → no corruption; fires safely during any tool class.

**R3 ceiling (no-false-positive + no-miss suite):** under soft → silent; between
soft and hard → warn + handoff-fresh, no stop; over hard → force handoff + stop
directive; `$TRANSCRIPT_PATH` unset → no-op ALLOW; SessionStart over-hard (a
resumed-too-large session) → directive at start.

**R4 retry wrapper:** transient signature (simulated `429`/socket) → retries
then succeeds; deterministic failure → fails once, no retry; `git commit` →
runs once, retry REFUSED; `git push` → refused; unknown command → default-deny
retry (runs once); transient then permanent → 3 attempts then fail loudly.

**R5 topic advisory:** proxy-positive (grown + no shared token) → advisory
injected; proxy-negative (shared file path) → silent; small transcript → silent;
advisory never returns a blocking exit code.

**R7 integration:** create → oversized dispatch BLOCKED → trimmed dispatch ALLOWED
→ work loop grows transcript → heartbeat keeps handoff fresh → ceiling forces
handoff → kill the session (simulate) → fresh session reads resume pointer and
reconstructs with ≤ N-calls loss. The simulated-death → bounded-loss-resume leg
is the proof that FM-032 is recoverable.

## Walking Skeleton

The thinnest end-to-end slice that proves the architecture: a session that (1)
attempts an oversized `Task` dispatch and is BLOCKED by R1; (2) re-dispatches
trimmed and proceeds; (3) the R2 heartbeat writes a resume pointer at call N; (4)
the session is killed (kill -9 / simulated transport drop) BEFORE a clean Stop;
(5) a fresh session reads `.claude/state/resume-<session>.md` and continues with
loss bounded to ≤ N calls. This slice touches every layer (Layer-1 block, the
heartbeat handoff, the death, the resume) with minimal content and is the R7
integration test's core path. It is also the single most important proof,
because it demonstrates the one thing the naive "add retries" framing cannot:
recovery from a death the harness cannot prevent.

## Decisions Log

### Decision: One bundled ADR (040) with five sub-decisions vs. five separate ADRs
- **Tier:** 2
- **Status:** proceeded with recommendation
- **Chosen:** One ADR (040) with five locked sub-decisions (layer model + four design choices).
- **Alternatives:** Five ADRs (040–044). Rejected — the layer model (040-a) determines all four other decisions; splitting fragments one coherent rationale. Matches the repo's bundled pattern (ADR 015, 020, 036; Pattern 1 chose the same).
- **Reasoning:** Coherence; the layer model is the single refutation criterion; one reviewable artifact.
- **Checkpoint:** N/A (design session)
- **To reverse:** Split 040 into per-decision ADRs; low cost (docs only).

### Decision: Tasks section = implementation roadmap (R1–R7), not this session's deliverables
- **Tier:** 1
- **Status:** proceeded with recommendation
- **Chosen:** The plan's `## Tasks` are the future implementation sessions; THIS session checks off none.
- **Reasoning:** Mirrors Pattern 1's design-plan shape; Misha asked for "an ordered implementation roadmap — small enough sessions to ship cleanly."

### Decision: Honest Layer-3 boundary over a comforting-but-false "retry wrapper around everything"
- **Tier:** 2
- **Status:** proceeded with recommendation
- **Chosen:** Scope API-transport retry OUT (platform-owned); cure Layer 3 via load reduction + always-fresh handoff (ADR 040-a/c/e).
- **Alternatives:** A "retry/backoff wrapper around MCP tool calls" that implies it survives transport death. Rejected — a hook cannot retry a dead socket; the Stop hook does not even fire. Claiming otherwise violates "no false promises."
- **Reasoning:** Curative-not-palliative requires fixing the real recoverable thing (bounded-loss resume), not simulating a fix at a layer the harness cannot reach.
- **To reverse:** If Claude Code later exposes a transport-retry hook surface, add it; until then the boundary stands.

## Definition of Done

- [ ] (design phase) ADR 040 authored + indexed; discovery authored; this plan authored + passes plan-reviewer; the layer model is the explicit spine.
- [ ] (design phase) systems-designer returns PASS on the 10-section analysis (gate before implementation).
- [ ] (design phase) Misha reviews + authorizes the roadmap + resolves §D1–§D4 inputs (or defers them to build-time calibration).
- [ ] (implementation) R1–R7 each task-verifier PASS with `--self-test` green.
- [ ] (implementation) R7 integration test passes the simulated-death → bounded-loss-resume path end-to-end.
- [ ] SCRATCHPAD updated.

## Systems Engineering Analysis

### 1. Outcome (measurable user outcome, not output)

Success, measured post-implementation: (1) zero subagent-dispatch prompt-too-long
failures (R1 blocks them at Layer 1 before the call — the `bold-albattani` 4/4
class goes to 0/4); (2) every terminal death (any layer, including transport)
leaves a handoff no older than N tool calls, so a fresh session always resumes
with bounded loss (the `busy-elgamal` / `xenodochial-clarke` unbounded-loss class
goes to ≤-N-loss); (3) no session crashes at the platform context limit with no
warning — the R3 hard ceiling fires below it (the `d0a8d31f` class is caught);
(4) the maintainer observes: oversized dispatches are refused with a clear
split-instruction, long sessions self-warn and keep a fresh resume pointer, and a
killed session is always resumable. The honest non-goal: transport deaths still
*happen* — they are made *recoverable and less frequent*, not impossible.

### 2. End-to-end trace with a concrete example

A real session, R1–R6 active. The orchestrator builds a `Task` dispatch whose
prompt is 48 KB (over the 32 KB budget in `resilience.config.json`).
`dispatch-preflight-gate.sh` (PreToolUse) measures 48 KB > 32 KB → BLOCK, stderr:
"dispatch prompt 48 KB exceeds 32 KB budget; split into 2 dispatches or move
context to a referenced file." The orchestrator splits into two 24 KB dispatches;
both ALLOW. Work proceeds. At tool call #20 (interval N=20), `handoff-heartbeat.sh`
(PostToolUse) writes `.claude/state/resume-<session>.md` (current plan, last
commit SHA, in-flight task, next action) and touches SCRATCHPAD freshness. At
call #58 the transcript hits the 7 MB soft threshold: `transcript-ceiling-gate.sh`
emits a warn and confirms the handoff is fresh. At call #74 the transcript hits
the 9 MB hard threshold (below the platform limit): the gate forces a fresh
handoff write and emits "transcript at hard ceiling; /clear and resume from
.claude/state/resume-<session>.md." Before the agent acts, a rate-limit kills the
session (Layer 3 — no Stop hook fires). The maintainer (or, in Dispatch mode, the
supervisor) starts a fresh session; the resume protocol (R6) reads the resume
pointer written at call #74 → reconstructs context → continues. Loss: ≤ the
handful of calls since #74's write (in practice 0, since the ceiling just
wrote it). No work lost; no prompt-too-long; no unbounded-loss death.

### 3. Interface contracts between components

| Producer | Consumer | Contract |
|---|---|---|
| `dispatch-preflight-gate.sh` | `Task`/`Agent` dispatch | Reads `tool_input.prompt`; if byte size > budget, exit 2 + split/trim message; else exit 0 (silent). Never modifies the prompt. |
| `resilience.config.json` | R1/R2/R3 hooks | Provides `dispatch_budget_bytes`, `transcript_soft_bytes`, `transcript_hard_bytes`, `heartbeat_interval_n`. Hooks apply hard-coded defaults if absent. |
| `handoff-heartbeat.sh` | `.claude/state/resume-<session>.md` + SCRATCHPAD | On an N-tool-call interval, writes the resume pointer (plan path, last commit SHA, in-flight task id, next action) + refreshes SCRATCHPAD via `session-wrap.sh refresh`. Idempotent. |
| `transcript-ceiling-gate.sh` | session (stderr/additionalContext) | `wc -c $TRANSCRIPT_PATH`; soft→warn+ensure-handoff; hard→force-handoff+stop/`/clear` directive. Read-only on the transcript. |
| `retry-with-backoff.sh` | the wrapped Bash command | Runs the command; on transient signature retries (exp backoff, ≤3); on irreversible-op denylist match runs ONCE (no retry); on terminal signature fails loudly. |
| `topic-shift-surfacer.sh` | UserPromptSubmit additionalContext | On proxy-positive, injects a `/clear` recommendation string. Never blocks. |
| resume protocol (R6) | fresh session | A fresh session reads `.claude/state/resume-<session>.md` and reconstructs: which plan, where in it, what's next. |
| ceiling/supervisor | spawn tool (spawnable modes) | On hard ceiling in a spawnable mode, auto-spawn a fresh session passing the resume-pointer path. |

### 4. Environment & execution context

All components run inside Claude Code sessions on the maintainer's machine (Git
Bash on Windows; also Linux/macOS). Hooks fire from `~/.claude/hooks/` (live
mirror of `adapters/claude-code/hooks/`). `dispatch-preflight-gate.sh` is
PreToolUse `Task|Agent`. `handoff-heartbeat.sh` + `transcript-ceiling-gate.sh`
are PostToolUse (heartbeat counter keyed by `CLAUDE_SESSION_ID`, `flock`-guarded,
mirroring `tool-call-budget.sh`); the ceiling gate is ALSO SessionStart.
`topic-shift-surfacer.sh` is UserPromptSubmit. `retry-with-backoff.sh` is a
`scripts/` wrapper the agent invokes around a Bash command. All have `jq`
available (degraded no-jq fallback per convention). Ephemeral state:
`.claude/state/resume-<session>.md` and the heartbeat counter (both regenerated;
the resume pointer is the only one that must survive a death — it is a committed-
tree-adjacent file under `.claude/state/`, which persists across the death since
it is written before the death). Two-layer config discipline applies.

### 5. Authentication & authorization map

No external auth boundaries. The only authorization-adjacent surfaces are
internal: (1) `dispatch-preflight-gate.sh` adds a new BLOCK authority on `Task`/
`Agent` (composes with `teammate-spawn-validator.sh` + `dag-review-waiver-gate.sh`
on the same matcher — all three independently gate; any can block); (2) the
spawnable-mode auto-respawn (R6) uses the spawn tool the session already has, no
new credential. No tokens, quotas, or rate limits introduced (the design exists
partly to *reduce* the rate-limit deaths the harness already hits).

### 6. Observability plan (built before the feature)

- `dispatch-preflight-gate.sh` on BLOCK: `[dispatch-preflight] prompt <N>B >
  budget <B>B → BLOCK (split/trim)`. On ALLOW it is silent.
- `handoff-heartbeat.sh` on each write: `[handoff-heartbeat] call <n>: resume
  pointer + SCRATCHPAD refreshed`.
- `transcript-ceiling-gate.sh`: `[transcript-ceiling] <N>B vs soft <S>B/hard
  <H>B → <SILENT|WARN|FORCE-HANDOFF>`.
- `retry-with-backoff.sh`: `[retry] attempt <k>/3 (transient: <signature>)` /
  `[retry] irreversible-op → no retry` / `[retry] terminal failure → fail`.
- `topic-shift-surfacer.sh`: `[topic-shift] proxy <positive|negative>; advisory
  <injected|silent>`.
- Reconstruct-from-logs test: from stderr alone, for any session, one can
  determine every dispatch that was blocked and why, every heartbeat write, the
  ceiling state at each measurement, and every retry decision. A post-death
  forensic answers "when was the last handoff fresh?" from the resume-pointer
  mtime.

### 7. Failure-mode analysis per step

| Step | Failure mode | Observable symptom | Recovery / policy | Escalation |
|---|---|---|---|---|
| Dispatch guard | Blocks a legitimately-large dispatch | dispatch refused | split per remediation, OR deliberate config budget raise (surfaced) | budget §D1 recalibration |
| Dispatch guard | Budget too high → still allows a death-sized prompt | prompt-too-long persists | lower budget (§D1) with margin below real ceiling | revisit if FM-031 recurs |
| Heartbeat | Interval N too coarse → loss > intended | post-death loss larger than expected | lower N (§D4); more frequent writes | revisit if resume loses material work |
| Heartbeat | Writes during irreversible op | none (handoff write has no work side effect) | safe by design (idempotent file write) | n/a |
| Ceiling gate | Hard threshold ≥ platform limit → crash before fire | crash with no handoff | set hard well below platform limit (§D2) | block ship if self-test "over-hard→FORCE" red |
| Ceiling gate | `$TRANSCRIPT_PATH` unreadable | gate silent | no-op ALLOW (never block on missing measurement) | n/a |
| Retry wrapper | Retries an irreversible op | double-commit/push | denylist refuses retry; default-deny on unknown | block ship if denylist self-test red |
| Retry wrapper | Misclassifies terminal as transient | masks a real failure as a flake | conservative transient signature list; terminal = any deterministic non-zero | tighten signatures |
| Topic advisory | False-positive proxy | one ignored suggestion | advisory only, never blocks (the whole reason it is advisory) | tune proxy if noisy |
| Resume (R6) | Resume pointer stale at death | loss up to last-write | bounded by N; heartbeat guarantees freshness | lower N |
| Auto-respawn | Runaway self-spawn loop (spawnable modes) | repeated spawns | respawn only at hard ceiling + once per ceiling-hit; interactive never auto-spawns | cap respawns/session |

### 8. Idempotency & restart semantics

- `dispatch-preflight-gate.sh`: pure validator, no state mutation, restart-safe.
- `handoff-heartbeat.sh`: idempotent write — re-firing overwrites the resume
  pointer with current state; no accumulation, no corruption. If interrupted
  mid-write, the temp-then-rename pattern (to be used) leaves either the old or
  the new pointer, never a torn file.
- `transcript-ceiling-gate.sh`: read-only measurement + a handoff write (delegated
  to the idempotent heartbeat path); re-firing re-measures. Safe.
- `retry-with-backoff.sh`: the wrapper itself is restart-safe; the RETRY of a
  non-idempotent command is the danger the denylist exists to prevent (040-c).
- Resume (R6): a fresh session reading a resume pointer is idempotent — reading it
  twice reconstructs the same state. The auto-respawn fires once per ceiling-hit
  (a per-ceiling-hit marker prevents a respawn loop).

### 9. Load / capacity model

Bottleneck: the PostToolUse heartbeat + ceiling measurement run on every tool
call. Both are cheap: a `flock`-guarded counter increment (proven sub-ms in
`tool-call-budget.sh`) and a `wc -c` on one file. The handoff WRITE fires only
every N calls (not every call), so its cost amortizes to (one small file write)/N
per call. The dispatch guard fires only on `Task`/`Agent` (rare). No saturation
concern at realistic tool-call rates. The byte ceiling is intrinsically the
thing that bounds the worst case — that is the point. No new external calls, no
rate-limit pressure added (the design reduces it).

### 10. Decision records & runbook

**Open decisions to resolve before the relevant R-session builds (= ADR 040
§D1–§D4):**

- **§D1 (R1): dispatch-prompt byte budget.** Calibrate against the real
  `bold-albattani` dispatch sizes (not available this session) and the subagent
  context window. *Recommendation:* start conservative (e.g. 32 KB) with a clear
  config knob; measure and adjust. **Needs build-time measurement.**
- **§D2 (R3): soft/hard transcript thresholds.** Set the hard threshold below the
  platform context limit with margin; soft at ~75% of hard. Needs the platform
  limit + the `d0a8d31f` 5.5 MB data point. **Needs build-time measurement.**
- **§D3 (R4): PreToolUse input-modification support.** Confirm whether the
  installed Claude Code version lets a PreToolUse hook rewrite `tool_input`. If
  yes, the Bash retry wrapper *could* later be auto-applied; if no,
  invocation-discipline (the agent calls the wrapper) is the only path.
  *Recommendation:* ship invocation-discipline first regardless; treat auto-wrap
  as a follow-up only if the capability exists. **Needs research.**
- **§D4 (R2): heartbeat interval N.** The loss-bound knob (loss ≤ N tool calls).
  *Recommendation:* start N=20; lower if post-death resume loses material work.
  **Needs Misha's loss-tolerance preference.**

**Runbook (post-implementation):**
- *Symptom: a dispatch was blocked unexpectedly.* Read the `[dispatch-preflight]`
  stderr for the size vs budget; split the dispatch or (deliberately) raise the
  budget in `resilience.config.json`.
- *Symptom: a session died and the resume lost work.* Check the resume-pointer
  mtime vs the death time; if the gap > N calls, lower N (§D4). If the pointer is
  absent, the death preceded the first heartbeat — lower N or check the heartbeat
  wiring.
- *Symptom: the ceiling never fired before a crash.* The hard threshold is ≥ the
  platform limit — lower it (§D2).
- *Symptom: a retry double-committed.* The denylist missed a command — a P0
  harness bug; add the command to the irreversible-op denylist and file a finding.

## Pre-Submission Audit

S1 (Entry-Point Surfacing): swept — every behavior change in §1–§10 is cited in a
`## Tasks` R-entry AND a `## Files to Modify/Create` line (R1↔dispatch guard,
R2↔heartbeat, R3↔ceiling, R4↔retry wrapper, R5↔topic advisory, R6↔resume/respawn,
R7↔integration+catalog); 0 stranded.
S2 (Existing-Code-Claim Verification): swept — claims about
`teammate-spawn-validator.sh` (PreToolUse `Task|Agent` reads `tool_input`),
`tool-call-budget.sh` (per-session `flock` counter), `session-wrap.sh` (Stop-hook
handoff refresh, ADR 027 Layer 5), the 9 Stop hooks reading `$TRANSCRIPT_PATH`,
and the settings.json.template event-type set were each verified against files
read this session; all confirmed accurate.
S3 (Cross-Section Consistency): swept — "Layer 3 is not hook-curable / handoff is
the recovery, not retry" consistent across Goal/Scope-OUT/§1/§7/Decisions Log and
ADR 040-a/c/e; "block not auto-trim" consistent across Scope/R1/Edge Cases/ADR
040-b; "advisory topic / mechanical ceiling" consistent across R5/§7/ADR 040-d; 0
contradictions.
S4 (Numeric-Parameter Sweep): swept for params [N heartbeat interval (rec 20),
dispatch budget (rec 32 KB), soft/hard transcript thresholds (rec ~7 MB/9 MB,
build-calibrated), 3 retry attempts, R1–R7 roadmap, FM-030..033]; all values
consistent across §2/§9/Testing Strategy/Tasks and flagged as build-calibrated
where exact values are unavailable this session.
S5 (Scope-vs-Analysis Check): swept — every "Build/Add/Wire/Force" verb in §1–§10
targets a file in `## Files to Modify/Create`; no prescription targets a
Scope-OUT file (Layer-3 transport retry is OUT and is prescribed NOWHERE;
failure-modes.md edits are R7-in-scope, not OUT; no code shipped this session per
Scope OUT).
