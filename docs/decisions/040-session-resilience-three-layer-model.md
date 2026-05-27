# ADR 040 — Session Resilience: Three-Layer Curability Model + Four Locked Sub-Decisions

- **Date:** 2026-05-25
- **Status:** Proposed (design session; awaiting Misha's greenlight before implementation per the design plan)
- **Stakeholders:** Misha (owner), the harness maintainer (the "user")
- **Supersedes / amends:** none. Composes with ADR 027 (handoff-freshness Layer 5 / `session-wrap.sh`) and the orchestrator-pattern dispatch discipline.
- **Plan:** `docs/plans/session-resilience-redesign.md`
- **Discovery:** `docs/discoveries/2026-05-25-session-resilience-terminal-death-catalog.md`
- **Initiative:** Pattern 4 of 5 in the plan-lifecycle-redesign arc (Pattern 1 = `docs/plans/plan-lifecycle-redesign.md` / ADR 036; Pattern 3 = file-lifecycle, parallel).

## Context

Four sessions died terminally with no resilience machinery anywhere in the
harness (full catalog: the discovery above). Every Gen 4–6 mechanism gates
*correctness*; none gates *survival*. Misha authorized a Mode:design plan with
the constraints **mechanical not advisory, curative not palliative, no false
promises.** The "no false promises" constraint is load-bearing here because the
naive framing ("add a retry/backoff wrapper around tool calls") would claim to
fix transport-level deaths that a hook structurally cannot touch.

The four deaths do not live at one layer. The decision below first locks the
layer model (040-a), then four design choices it forces (040-b..040-e).

## Decision

### 040-a — The three-layer curability model is the design's spine

A session can die at three layers, and the harness's power differs at each:

- **Layer 1 — Tool-input.** PreToolUse hooks see `tool_input` *before* the call.
  Oversized subagent-dispatch prompts (FM-031) live here. **Fully curable** —
  block the over-budget dispatch before it is sent.
- **Layer 2 — In-session context growth.** `$TRANSCRIPT_PATH` is a file whose
  byte size is measurable on every PostToolUse / SessionStart; the session is
  still alive, so a hook can measure and the agent can act. Mega-session growth
  (FM-030) and the missing hard ceiling (FM-033) live here. **Curable** by
  measurement + forced action.
- **Layer 3 — API-transport.** Socket disconnect / rate-limit kill the whole
  session between Claude Code and the API; the Stop hook does **not** fire on a
  non-clean death. Transient-death (FM-032) lives here. **Not directly curable
  from inside a hook.** Only two honest responses: (3a) prevention by load
  reduction (Layer-1/2 fixes shrink requests), and (3b) recovery by
  always-fresh handoff (bounded-loss resume). API-transport retry itself is
  platform-owned.

This model is the refutation criterion for the whole design: *any proposed
mechanism that claims to act at Layer 3 from inside a hook is, by this model,
making a false promise and must be rejected or relocated.*

### 040-b — Dispatch pre-flight guard BLOCKS oversized prompts; it never auto-trims

A PreToolUse `Task|Agent` guard measures `tool_input.prompt` byte size against a
configurable budget and **blocks** (exit 2 + remediation message) when over.

- **Rejected: auto-trim.** Silently truncating a dispatch prompt corrupts the
  builder's intent (the builder builds against a half-spec) — a false promise of
  "handled" that ships the wrong work. Auto-trim also depends on PreToolUse
  input-modification, which is not a confirmed capability in the installed
  Claude Code version (flagged as a research item in the plan).
- **Chosen: block.** Blocking is fully mechanical, safe, version-independent, and
  forces the orchestrator to split/trim *deliberately*. It directly cures
  FM-031 (`bold-albattani` 4/4) at Layer 1.

### 040-c — Bash retry wrapper retries idempotent commands only; irreversible ops are denylisted; API-transport retry is out of scope

A centralized wrapper **script** (`retry-with-backoff.sh`), invoked per-command,
provides exponential backoff (3 attempts) for **Layer-1 Bash-subprocess**
transient failures (flaky network `curl`, DNS hiccup, a `429` from a third-party
API the agent calls). It is a script, not a hook, because PreToolUse cannot
reliably rewrite Bash commands to auto-wrap them.

- **Retry is HARMFUL for non-idempotent / irreversible commands** — `git commit`,
  `git push`, `gh pr merge`, `gh pr create`, migration runners, any
  state-mutating op. Retrying a half-succeeded mutation double-commits or
  double-pushes. The wrapper carries an **irreversible-op denylist** and
  **refuses to retry** a matching command (it runs it once, no retry), and
  **default-denies retry on uncertainty** (unknown command → run once).
- **Transient vs terminal classification.** The wrapper retries only on
  transient signatures (network/socket errors, `429`, timeout exit codes); a
  deterministic non-zero exit (compile error, assertion failure) is terminal —
  fail loudly, do not retry.
- **API-transport retry (Layer 3) is explicitly OUT.** The wrapper does NOT and
  cannot retry the Claude-Code↔API connection. That is platform-owned. The honest
  cure for FM-032 is 040-e's handoff, not this wrapper.

### 040-d — Topic-shift detection is advisory-surface; the transcript-size ceiling is the mechanical hard enforce

Two Layer-2 mechanisms, deliberately split by **signal reliability**:

- **Topic-shift = advisory.** A purely-mechanical bash hook cannot reliably judge
  "unrelated topics"; it can only key on measurable PROXIES (transcript grown
  past a soft threshold AND the new user prompt shares no file path / no plan
  slug / no scope token with the recent window). Because this is a heuristic, a
  HARD block on it would halt legitimate work on a false positive (the FM-025
  false-fire harm). So topic-shift **surfaces** a strong `/clear` recommendation
  (UserPromptSubmit `additionalContext` the agent sees) and does **not** block.
- **Transcript-size ceiling = mechanical enforce.** Byte count is a *reliable*
  signal, so the hard line goes here: at the hard threshold (set below the
  platform context limit) the mechanism forces the handoff-write + a stop/`/clear`
  directive before the crash.
- **Principle (the reason for the split):** *hard-enforce only where the signal
  is reliable; advise where the signal is heuristic.* This satisfies "mechanical
  not advisory" by putting the mechanical floor on the trustworthy signal (bytes)
  and reserving advisory for the untrustworthy one (topic), rather than
  hard-blocking on a guess.

### 040-e — Handoff WRITE is always automatic (heartbeat); RESPAWN is auto in spawnable modes and surface-and-resume in interactive

- **Handoff write = always automatic.** A PostToolUse **heartbeat** keeps the
  handoff (SCRATCHPAD + a resume pointer) continuously fresh every N tool calls —
  not only at clean Stop. This is just a file write; claiming it is mechanical is
  no false promise. It bounds the loss of ANY death (including Layer-3) to the
  last N tool calls. This is the "bootstrap mechanism left unbuilt" for
  `busy-elgamal`: the cure is not in-session retry (impossible) but
  always-resumable handoff.
- **Respawn = mode-dependent (the honest boundary).**
  - **Spawnable modes (Dispatch / scheduled / remote):** the harness CAN
    auto-spawn a fresh session via the spawn tool, handing it the handoff path.
    True auto-handoff applies here.
  - **Interactive local:** the harness CANNOT spawn a replacement terminal for
    the human. Claiming it could is a false promise. At the hard ceiling it
    mechanically (1) writes the fully-fresh handoff and (2) surfaces a strong
    `/clear`-and-resume directive. The respawn is the human's `/clear` (or the
    agent's next action), reading the guaranteed-fresh handoff.

## Alternatives Considered

- **One ADR per sub-decision (040–044).** Rejected — the five decisions are one
  tightly-coupled resilience redesign (the layer model determines all four
  others). Matches the repo's bundled-sub-decision precedent (ADR 015, 020, 036).
- **"Add retry/backoff around all tool calls" as a single fix.** Rejected as the
  central false-promise trap (see 040-a / 040-c): a hook cannot retry a dead
  Layer-3 socket.
- **Hard-enforcing topic-shift detector (refuse next tool until `/clear`).**
  Rejected (040-d) — false positives on a heuristic halt real work; the
  reliable mechanical floor belongs on byte count, not topic guessing.
- **Auto-trim oversized dispatch prompts.** Rejected (040-b) — silent
  truncation ships the wrong work; depends on unconfirmed input-modification.
- **External-supervisor-only recovery.** Partial (folded into R6 spawnable path)
  — does nothing for interactive local and does not reduce death frequency.

## Consequences

- **Enables:** FM-031 fully cured at dispatch (R1); FM-030/FM-033 mechanically
  bounded at Layer 2 (R3); FM-032 made *recoverable with bounded loss* via
  always-fresh handoff (R2) and *less frequent* via load reduction; a clear,
  honest boundary on what the harness can and cannot do about transport deaths.
- **Costs:** a PostToolUse heartbeat adds a small per-tool-call write (mirrors
  `tool-call-budget.sh`'s proven counter pattern — sub-millisecond);
  byte-threshold and dispatch-budget values must be **calibrated** (the plan
  flags this — the `bold-albattani` 4/4 and `d0a8d31f` 5.5MB give starting data
  points but exact thresholds need measurement).
- **Blocks nothing that the harness already does.** All mechanisms default to
  ALLOW on hook-bug/ambiguity (the established harness convention).
- **Refutation criterion (whole design):** if, after implementation, terminal
  deaths persist at the same rate AND post-death handoffs are still stale, then
  either the heartbeat interval N is too coarse (loss not actually bounded) or
  the deaths are dominated by a Layer-3 mode the load-reduction did not touch —
  both are measurable post-pilot and would reopen the design.

## Open decisions deferred to the relevant roadmap session

- **§D1 (R1):** the exact dispatch-prompt byte budget. Needs calibration against
  the actual `bold-albattani` prompt sizes (not available this session).
- **§D2 (R3):** the soft and hard transcript-byte thresholds, set below the
  platform context limit with margin. Needs the platform limit value + the
  `d0a8d31f` 5.5 MB data point.
- **§D3 (R4):** confirm whether PreToolUse input-modification is supported in the
  installed Claude Code version (decides whether the Bash retry wrapper can ever
  be auto-applied vs. invocation-discipline only).
- **§D4 (R2):** the heartbeat interval N (tool calls between handoff writes) —
  the loss-bound knob. Smaller N = tighter loss bound, more writes.
