---
title: Session-resilience terminal-death catalog + three-layer curability model
date: 2026-05-25
type: failure-mode
status: decided
auto_applied: false
originating_context: Pattern 4 of the plan-lifecycle-redesign initiative (2026-05-25); Misha authorized a Mode:design plan after four named sessions died terminally (d0a8d31f prompt-too-long mega-session; bold-albattani 4/4 subagents prompt-too-long; busy-elgamal socket disconnect; xenodochial-clarke rate-limit) with no in-session resilience anywhere
decision_needed: n/a — decided; design captured in docs/plans/session-resilience-redesign.md + docs/decisions/040-session-resilience-three-layer-model.md
predicted_downstream:
  - docs/plans/session-resilience-redesign.md
  - docs/decisions/040-session-resilience-three-layer-model.md
  - adapters/claude-code/hooks/dispatch-preflight-gate.sh (new — roadmap R1)
  - adapters/claude-code/hooks/handoff-heartbeat.sh (new — roadmap R2)
  - adapters/claude-code/hooks/transcript-ceiling-gate.sh (new — roadmap R3)
  - adapters/claude-code/scripts/retry-with-backoff.sh (new — roadmap R4)
  - adapters/claude-code/hooks/topic-shift-surfacer.sh (new — roadmap R5)
  - docs/failure-modes.md (FM-030..FM-033 promotion — roadmap R7)
---

## What was discovered

Four sessions died **terminally** — not "stopped early," but crashed with no
clean Stop, no handoff written, and work lost — and the four deaths share the
same negative space: **the harness has zero in-session resilience machinery.**
Every Gen 4–6 mechanism gates *correctness* (did the work happen, is it
verified). None gates *survival* (will the session live long enough to finish).

The four deaths, with their distinct triggers:

1. **`d0a8d31f` — multi-topic mega-session prompt-too-long.** One context ran
   four unrelated topics serially with no `/clear`, growing to ~5.5 MB / 1756
   transcript lines, then the next request exceeded the model context window and
   the session died. Nothing measured the growth; nothing forced a `/clear`;
   nothing wrote a handoff before the crash.

2. **`bold-albattani` — 4/4 subagent dispatches prompt-too-long.** The
   orchestrator dispatched four subagents whose prompts were oversized; all four
   failed `prompt-too-long` at dispatch. The oversized prompt was visible in the
   `Task`/`Agent` `tool_input.prompt` **before** each call — but no pre-flight
   guard inspected it. A 4/4 failure rate means a systematic over-budget pattern,
   not a one-off.

3. **`busy-elgamal` — socket disconnect mid-implementation.** A transport-level
   socket disconnect between Claude Code and the Anthropic API killed the session
   mid-work. The originating note records the intended recovery as a "bootstrap
   mechanism left unbuilt" — i.e. there was a known design intent for a
   self-resuming session, never built. Loss was unbounded because no handoff was
   fresh at death time.

4. **`xenodochial-clarke` — rate-limit terminal death.** "Server is temporarily
   limiting" — a transport-level rate-limit — terminated the session. Same shape
   as `busy-elgamal`: a transient, recoverable condition became a terminal death
   because nothing absorbed it and nothing guaranteed a resumable handoff.

## Why it matters — the three-layer curability model

The load-bearing realization (and the thing that keeps the fix honest) is that
these four deaths do **not** live at one layer, and the harness's power to act
is **different at each layer**. Conflating them produces false promises — e.g.
"add a retry wrapper around tool calls" sounds like it would have saved
`busy-elgamal`, but a hook cannot retry a socket that is already dead, because
when the API transport dies, **no hook fires at all.**

```
LAYER 1 — TOOL-INPUT (PreToolUse hooks CAN act, before the call)
   The oversized Task/Agent prompt is in tool_input BEFORE dispatch.
   → bold-albattani (death #2) lives here. FULLY CURABLE: block the
     oversized dispatch before it is sent.

LAYER 2 — IN-SESSION CONTEXT GROWTH (hooks CAN measure; agent CAN act while alive)
   The transcript is a file on disk ($TRANSCRIPT_PATH); its byte size is
   measurable on every PostToolUse / SessionStart. The session is still
   ALIVE, so a hook can measure and surface/enforce an action.
   → d0a8d31f (death #1) and the no-ceiling gap (FM-033) live here.
     CURABLE by measurement + forced action (handoff + /clear), bounded by
     whether a spawn capability exists in the session's mode.

LAYER 3 — API-TRANSPORT (the connection dies; NO hook fires)
   Socket disconnect and rate-limit terminate the whole session between
   Claude Code and the API. The Stop hook does NOT run on a non-clean death.
   NO in-session mechanism can catch it. The harness CANNOT retry a dead
   session from inside.
   → busy-elgamal (death #3) and xenodochial-clarke (death #4) live here.
     NOT directly curable from inside a hook. Two honest responses only:
       (3a) PREVENTION by load reduction — Layer-1 + Layer-2 fixes shrink
            request size → fewer giant requests → fewer transport deaths.
            Indirect but real.
       (3b) RECOVERY by always-fresh handoff — the harness cannot prevent
            the death but CAN guarantee a fresh session resumes with BOUNDED
            loss, IF the handoff is heartbeat-fresh (written continuously,
            not only at clean Stop). This is the "bootstrap mechanism left
            unbuilt."
   What the harness genuinely CANNOT do: transparently retry the dead API
   socket from inside a hook. API-transport retry is platform-owned
   (Claude Code's own connection layer). Claiming a harness "retry/backoff
   wrapper" survives a session-killing disconnect would be a false promise.
```

The existing handoff substrate (`session-wrap.sh refresh`, ADR 027 Layer 5)
refreshes SCRATCHPAD **only at clean Stop**. Every one of the four deaths
**skipped Stop** — so the handoff was stale or absent at death. That is the
precise, shared root cause of unbounded loss across all four: *the handoff is
guaranteed fresh only on the one exit path none of the deaths took.*

## Proposed failure-mode catalog entries (promote to docs/failure-modes.md at roadmap R7)

These are authored here as the catalog deliverable; R7 promotes them into the
canonical `docs/failure-modes.md` (this design session does not edit the
canonical catalog — design-only).

- **FM-030 — Multi-topic mega-session grows unbounded to prompt-too-long death.**
  Symptom: one context runs N unrelated topics serially with no `/clear`,
  transcript grows past the model context window, next request dies
  prompt-too-long. Root cause: no mechanism measures transcript growth or forces
  topic-boundary `/clear`. Detection: `wc -c $TRANSCRIPT_PATH` past a ceiling.
  Prevention: Layer-2 transcript-ceiling gate (R3) + topic-shift advisory (R5).
  Example: `d0a8d31f` (~5.5 MB / 1756 lines, four topics).

- **FM-031 — Oversized subagent dispatch prompt → prompt-too-long at dispatch.**
  Symptom: `Task`/`Agent` dispatch fails prompt-too-long; in the worst case all
  parallel dispatches fail (4/4). Root cause: the orchestrator builds an
  over-budget prompt and no pre-flight guard inspects `tool_input.prompt` size
  before the call. Detection: PreToolUse byte-size measurement of the dispatch
  prompt. Prevention: Layer-1 dispatch pre-flight guard (R1) — block, never
  silently truncate. Example: `bold-albattani` 4/4.

- **FM-032 — Transient API-transport error becomes a terminal session death with
  no resumable handoff.** Symptom: socket disconnect or rate-limit ("Server is
  temporarily limiting") kills the session; work since the last clean Stop is
  lost. Root cause: (i) the transport death skips the Stop hook so no in-session
  mechanism fires, AND (ii) the handoff was only ever guaranteed fresh at clean
  Stop, so loss is unbounded. Detection: not in-session (the session is dead);
  detectable only by a fresh session finding a stale/absent handoff, or by an
  external supervisor observing liveness. Prevention: NOT in-session retry
  (impossible) — instead heartbeat-fresh handoff (R2) for bounded-loss recovery
  + load reduction (R1/R3/R5) to lower transport-death frequency + a resume
  protocol (R6). Example: `busy-elgamal` (socket), `xenodochial-clarke`
  (rate-limit).

- **FM-033 — No transcript-size hard ceiling; sessions grow until the platform
  limit crashes them with no handoff.** Symptom: a long-lived session crashes at
  the platform context limit with no warning and no handoff. Root cause: nothing
  enforces a hard ceiling below the platform limit at which the session writes a
  handoff and stops/`/clear`s before the crash. Detection: `wc -c
  $TRANSCRIPT_PATH` past a hard threshold on the PostToolUse heartbeat.
  Prevention: Layer-2 transcript-ceiling gate (R3) with a hard threshold set
  below the platform limit + always-fresh handoff (R2). Distinct from FM-030:
  FM-030 is the multi-topic *behavior*; FM-033 is the missing *mechanical floor*.

## Options considered

- **A. Treat all four deaths as one "add retries" fix.** Rejected — it conflates
  the three layers and produces the false promise that a hook can retry a dead
  socket (Layer 3 is below the hook layer). This is exactly the
  curative-not-palliative / no-false-promises line Misha drew.
- **B. Layer-stratified design (chosen).** Cure Layer 1 fully (dispatch guard);
  cure Layer 2 mechanically (transcript ceiling + heartbeat handoff) with an
  advisory layer for the heuristic topic signal; treat Layer 3 honestly
  (prevention-by-load-reduction + always-fresh-handoff recovery, NOT in-session
  retry).
- **C. External supervisor only (respawn dead sessions from outside).** Partial
  — works for spawnable modes (Dispatch/scheduled) but does nothing for the most
  common mode (interactive local) and does not reduce death frequency. Folded in
  as R6's spawnable-mode path, not adopted as the whole answer.

## Recommendation

B (layer-stratified). It is the only framing that is both mechanical and honest:
each layer gets the strongest mechanism that layer actually permits, and the
boundary of harness power (Layer-3 transport retry is platform-owned) is stated
rather than papered over with a wrapper that would silently not work.

## Decision

B, captured in `docs/decisions/040-session-resilience-three-layer-model.md` and
the design plan `docs/plans/session-resilience-redesign.md`. Five sub-decisions
locked in ADR 040 (layer model; block-not-trim; idempotent-only retry; advisory
topic / mechanical ceiling; auto-handoff-write / mode-dependent respawn).

## Implementation log

(empty — design session; the roadmap R1–R7 in the design plan implements this.)
