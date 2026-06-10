---
title: Dispatch↔Code coordination debug — 5 root causes, 2 brief premises refuted
date: 2026-05-25
type: process
status: pending
auto_applied: false
originating_context: Pattern-5 (Dispatch coordination) design session of the plan-lifecycle redesign initiative; live diagnostic pass on this machine (Claude Code 2.1.146, claude-desktop entrypoint) before authoring docs/plans/dispatch-coordination-redesign.md
decision_needed: "(sharpened 2026-06-10) Greenlight — or descope/supersede — docs/plans/dispatch-coordination-redesign.md (still Status: DRAFT) + ADRs 039/041/042 (all still Proposed). Since this discovery was written, OTHER routes shipped parts of the design: RC2b's cwd-divergent state path is fixed (shared canonical-state-path resolver, 0291279, Workstreams consolidation); RC1's topology is reframed by orchestrator-prime (ADR 050 + live skill: the orchestrator polls/wakes itself, Dispatch relays per rules/dispatch-relay-protocol.md); a partial RC5 exists (scripts/check-cross-repo-drift.sh has an optional ntfy alert per the ADR-042 contract). Still unbuilt: RC3 dispatch-mode autodetect (ADR 041; dispatch-mode.json is still a manual flip), the general RC5 Notification/Stop ntfy path, RC4 duplicate-spawn detection, and the RC1 upstream issue filing. The decision is whether to greenlight a SLIMMED build phase covering the remaining RCs, fold them into orchestrator-prime's program backlog and supersede the plan, or defer."
predicted_downstream:
  - docs/plans/dispatch-coordination-redesign.md
  - docs/decisions/041-dispatch-mode-autodetect-signal.md
  - docs/decisions/042-ntfy-out-of-band-notification.md
  - docs/decisions/039-conv-tree-reconciliation-over-interception.md
  - docs/proposals/anthropics-claude-code-parent-wake-issue.md
---

## What was discovered

A live diagnostic pass (diagnostic-first per `~/.claude/rules/diagnosis.md`) on this
machine, before designing anything, surfaced concrete evidence on all five reported
root causes — and **refuted two of the brief's specific premises**. All claims below
are tagged PROVEN (evidence cited) or HYPOTHESIZED (refutation criterion named) per
`~/.claude/rules/claims.md`.

### RC1 — No parent-wake on child turn-end (PROVEN; Anthropic-blocked)
The available tool surface in a Dispatch-orchestrator session has **no inter-session
message-delivery primitive**. The harness already ships the only viable channel — the
`spawn-task-report-back.md` convention (child writes a result JSON; parent surfaces it
at *its next SessionStart*). That is parent-**pull-on-next-start**, not parent-**wake**.
Nothing in `~/.claude/` can wake a sleeping parent on a child's turn-end.
PROVEN: the harness's own `spawn-task-report-back.md` rule states "the orchestrator has
no mechanical callback into a spawned child," which is exactly why the report-back
convention binds the orchestrator at *its* spawn-time and Stop, not the child.
Consequence: the relay genuinely hangs until something else (a human, a poll, a new
session start) advances state.

### RC2 — emit hook never fires (PROVEN; **brief's `mcp__dispatch__*` premise REFUTED**)
The brief hypothesized the matcher `mcp__ccd_session__spawn_task|mcp__ccd_session_mgmt__start_code_task`
fails to match because Dispatch calls `mcp__dispatch__*`. **Refuted.**
- PROVEN: `mcp__ccd_session__spawn_task` is a *real, live tool in this session's own
  toolset* (it is one of my top-level tools). The namespace is `ccd_session` /
  `ccd_session_mgmt`, **not** `dispatch`. The matcher names the correct namespace.
- PROVEN: `~/.claude/logs/conversation-tree-emit.log` contains **only `--self-test`
  fixtures** (`/tmp/tmp.*/st-27.json`, titles "ST27 Root", timestamps from a self-test
  run). **Zero real `--on-spawn` events have ever been logged.** The hook is wired and
  passes self-test, but has never fired on a real branch creation.

The real causes are two, neither a matcher typo:
- **(a) Structural blind spot (PROVEN).** A PreToolUse hook only fires when a
  *hook-loading* Claude session *calls the tool*. Branch creation that originates in
  the Dispatch app UI (human taps "new task" on phone/desktop) or in a cloud
  orchestrator (which inherits only project `.claude/`, per Decision 011 — not
  `~/.claude/`) makes **no tool call any local hook can observe**. This is the exact
  "passive observer / cloud blind spot" ADR-031 r7 accepted — now reproduced concretely.
- **(b) Sink/source path divergence (PROVEN).** `~/.claude/logs/conv-tree-read.log`
  (updated *today*, 2026-05-25) repeatedly reports
  `state file absent (…/neural-lace/neural-lace/conversation-tree-ui/state/tree-state.json) — no-op`,
  flipping between two roots: `~/claude-projects/neural-lace/…` and
  `~/dev/<work-org>/neural-lace/…`. The GUI server (per
  `conv-tree-launcher.log`) runs from
  `~/dev/<work-org>/neural-lace/neural-lace/conversation-tree-ui`
  (note the doubled `neural-lace\neural-lace` — a nested checkout). The emit/read hooks
  resolve the state path **relative to each session's cwd**, so a session running from
  `claude-projects` writes/reads a *different* state file than the one the GUI watches.
  Even when the emit hook *does* fire, its event can land in a file the GUI never reads.

### RC3 — No auto-detect of dispatch-mode (PROVEN; **brief's signal HALF-REFUTED**)
The brief's proposed signal was `CLAUDE_CODE_ENTRYPOINT=claude-desktop` +
`CLAUDE_CODE_PROVIDER_MANAGED_BY_HOST=1`.
- PROVEN present: `CLAUDE_CODE_ENTRYPOINT=claude-desktop`.
- PROVEN **absent**: `CLAUDE_CODE_PROVIDER_MANAGED_BY_HOST` is **not set** in this
  session (Claude Code 2.1.146). `env | grep PROVIDER_MANAGED` returns nothing. The
  second half of the proposed signal does not exist on this build.
- Available corroborating signals that DO exist: `AI_AGENT=claude-code_2-1-146_agent`,
  `CLAUDE_AGENT_SDK_VERSION=0.3.146`, `CLAUDE_CODE_SDK_HAS_HOST_AUTH_REFRESH=1`,
  `CLAUDE_CODE_SDK_HAS_OAUTH_REFRESH=1`, `CLAUDECODE=1`, `CLAUDE_CODE_SESSION_ID`.
- PROVEN: `~/.claude/local/dispatch-mode.json` currently has
  `"running_under_dispatch": true` — i.e. it was **manually flipped** (matches the
  reported "requires manual flip" pain). The file still carries the example `_comment`.

### RC4 — No idempotency on Dispatch task-spawn (HYPOTHESIZED at Dispatch side)
Reported: today a personal-project session double-spawned (two sibling sessions
~1 min apart, same brief) — a timeout-induced duplicate spawn.
- HYPOTHESIZED (Dispatch-internal, not directly observable from here): a Dispatch
  spawn RPC timed out client-side, the spawn actually succeeded server-side, and the
  client retried → two sessions. REFUTED if Dispatch logs show two distinct
  user-initiated spawn intents rather than one intent + one retry.
- PROVEN (harness-side): the emit hook *already* dedupes on a deterministic `event_id`
  (ADR-032 idempotency), so the conv-tree would not double-render *if both spawns went
  through the hook* — but per RC2 they don't, so the tree can't even detect the dup
  today. Dispatch is closed-source from our vantage; harness cannot *prevent* the
  double-spawn, only *detect* it after the fact.

### RC5 — No phone/external notification path (PROVEN gap)
When Dispatch is asleep and a child needs input, there is no out-of-band path to the
human. PROVEN: no `ntfy`/push hook exists in `~/.claude/hooks/`; the `Notification`
hook chain in `settings.json.template` does not POST anywhere external. The realistic
workaround (hook → ntfy.sh → phone push) is unbuilt.

## Why it matters

The relay between Dispatch (event-driven, sleeps) and child Code sessions (go idle
awaiting a directive) silently hangs, and the conversation-tree GUI — the operator's
one surface for "what's waiting on me" — shows nothing, because the writer hook never
fires on real branches AND writes to a cwd-divergent file. The combination means a
branch can be open, waiting on Misha, completely invisible. That is precisely the
FR-24 failure ("100% of open branches surface-able a minute or a month later") the
whole conversation-tree system exists to prevent.

Two of the brief's stated mechanical fixes were aimed at the wrong target (matcher
namespace; a non-existent env var). Building those as specified would have shipped
non-fixes. Diagnostic-first caught it.

## Options

Full design is in `docs/plans/dispatch-coordination-redesign.md`. Decision-bearing
choices are split into three ADRs (041 auto-detect signal, 042 ntfy contract, 039
reconciliation-over-interception). High-level option shape per root cause:

- RC1: (A) accept Anthropic-blocked + file issue + bounded parent-side poll as a
  *named palliative*; (B) pretend the report-back convention closes it (rejected —
  false promise). → A.
- RC2: (A) keep matcher (it's correct) + add a `list_sessions` reconciler as the
  primary visibility mechanism + pin a cwd-independent canonical state path; (B) widen
  the matcher to `mcp__dispatch__*` (rejected — that namespace doesn't exist). → A.
- RC3: (A) detect on `CLAUDE_CODE_ENTRYPOINT` + agent-SDK corroboration, respecting an
  explicit `CLAUDE_CODE_DISPATCH` override and a manual lock; (B) wait for
  `PROVIDER_MANAGED_BY_HOST` to exist (rejected — may never). → A.
- RC4: (A) harness-side detector via the same reconciler + Dispatch-side idempotency-key
  *recommendation* we file upstream; (B) claim a harness-side prevention (rejected —
  Dispatch is closed). → A.
- RC5: (A) opt-in ntfy.sh POST from `Notification`/`Stop` hooks, config gitignored. → A.

## Recommendation

Confirm the diagnosis as written (the two refutations are the load-bearing part), then
greenlight ADRs 039/041/042 and the Mode:design plan for a **separate build phase**.
Reversibility: this discovery records observations only; auto_applied:false because the
downstream is a multi-ADR design that warrants Misha's explicit greenlight (not a
single-revert reversible change).

## Current state (re-verified 2026-06-10, pending-discoveries triage)

The diagnosis itself has held — both refutations stand, and later work built on them.
What changed since 2026-05-25:

- **RC2b FIXED by another route.** The cwd-divergent state-path scatter was converged by
  the Workstreams consolidation's shared canonical-state-path resolver (commit `0291279`,
  "converge 9-file scatter onto one file"; `~/.claude/workstreams-state-path.txt` is the
  live pin). The nested dev checkout that hosted the doubled path was removed entirely
  (see 2026-05-27 checkout-divergence discovery, now implemented).
- **RC1 reframed by orchestrator-prime.** ADR 050 + the live `orchestrator-prime` skill
  invert the topology: the harness-native orchestrator wakes itself (loop/scheduled task),
  polls inbox/tree/sessions, and surfaces to Misha via spawn_task chips — Dispatch relays
  per `rules/dispatch-relay-protocol.md`. The "parent-wake" Anthropic gap remains real but
  is no longer the load-bearing path; the upstream issue
  (`docs/proposals/anthropics-claude-code-parent-wake-issue.md`) remains unfiled.
- **RC5 partially built.** `scripts/check-cross-repo-drift.sh` carries an optional
  drift-only ntfy POST per the ADR-042 contract; the general Notification/Stop → ntfy
  human-wake path is still unbuilt.
- **RC3 unbuilt.** ADR 041 still Proposed; `~/.claude/local/dispatch-mode.json` is still a
  manual flip.
- **RC4 unchanged** (Dispatch-side; harness can only detect, and the detection reconciler
  shape now naturally belongs to orchestrator-prime's cycle).
- The plan (`docs/plans/dispatch-coordination-redesign.md`) is still `Status: DRAFT`;
  ADRs 039/041/042 still `Proposed (gated on Misha's greenlight)`.

## Decision

(Pending Misha — see the sharpened decision_needed above: greenlight a slimmed build of
the remaining RC3/RC5/RC4/upstream-filing slice, fold those into orchestrator-prime's
program backlog and supersede the plan, or defer. Kept pending in the 2026-06-10 triage
because greenlighting a Tier-3 multi-ADR build phase is genuinely Misha's call.)

## Implementation log

(Empty — design-only session, no code changes, no commits.)
