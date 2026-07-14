# Plan: Background-agent heartbeat + watchdog (interim Pattern)

Status: ACTIVE
Mode: code
lifecycle-schema: v2
acceptance-exempt: true  # harness-internal mechanism; no user-facing product surface
Backlog items absorbed: none

## Goal
Fix the class the 2026-07-14 lesson documents: a background agent hung and the orchestrator,
polling its 0-byte `tasks/<id>.output`, could not tell "wedged" from "busy" — idling ~5 hours.
Root cause: subagent builders emit NO liveness signal, and the orchestrator's only proxy
(output presence) cannot distinguish a hung agent from a quiet-but-working one.

Design (from the exploration — EXTEND, do not duplicate):
- A mature per-session heartbeat system already exists (`session-heartbeat.sh` writer +
  `session-heartbeat-lib.sh` `hb_classify` oracle, consumed by 4 watchdogs). The ONLY gap is
  that dispatched subagents never write a heartbeat (`harness-doctor.sh:1033-1043` excludes
  `*/subagents/*`). So build a small AGENT-scoped writer + a watchdog that reuses the staleness
  concept, in a dedicated `heartbeats/agents/` namespace so it does NOT pollute the session
  board (`od_sessions`/`nl status`) or make the session-resumer try to `claude --resume` a subagent.
- HONESTY: the true fix (runtime auto-heartbeat inside Anthropic's Agent/Workflow runtime) is
  NOT in this repo and NOT buildable here. This ships the INTERIM PATTERN (dispatch-prompt
  convention + helper + watchdog). Detection is made as Mechanism-grade as possible via an
  mtime fallback so it fires even when an agent does not cooperate; the push-heartbeat is the
  precision enhancement. This directly unblocks GUARD-REFORMULATE-01 (orphaned-worktree-guard,
  whose `_live_owner` join was REFORMULATE'd for exactly this missing subagent-liveness signal).

## Files to Modify/Create
- `docs/lessons/2026-07-14-background-agent-heartbeat-watchdog.md` — the lesson (commit the staged, uncommitted file).
- `adapters/claude-code/scripts/agent-heartbeat.sh` — new: `emit` (push) + `watch` (detect, mtime-fallback) + `reap` + `--self-test`.
- `adapters/claude-code/doctrine/background-work-tracking.md` — add the agent-heartbeat convention + honest Pattern/residual note (or a new compact if size demands).
- `adapters/claude-code/hooks/stalled-work-surfacer.sh` — fold the agent-watchdog scan into the existing SessionStart stalled-work surfacer.
- `adapters/claude-code/manifest.json` — register agent-heartbeat.sh.
- `docs/plans/agent-heartbeat-watchdog-2026-07-14.md` — this plan.

## Tasks
- [ ] 1. Commit the lesson; build `agent-heartbeat.sh` (emit/watch/reap, dedicated agents/ namespace, generous step-aware threshold, mtime fallback) with `--self-test`; register in manifest. Verification: mechanical
- [ ] 2. Add the dispatch-prompt heartbeat convention to doctrine (honest Pattern/residual label) and wire `agent-heartbeat.sh watch` into `stalled-work-surfacer.sh` so stalled agents surface at SessionStart. Verification: mechanical
- [ ] 3. harness-review the mechanism (Mechanism/Pattern classification, FP/cry-wolf risk, board-pollution check); address findings. Verification: mechanical

## Non-goals / follow-ups (filed, not in this plan)
- The runtime auto-heartbeat primitive (Anthropic Agent/Workflow runtime) — out of repo reach; nl-issue.
- Wiring the agent heartbeat into the orphaned-worktree-guard `_live_owner` join (GUARD-REFORMULATE-01) — that guard is on a WIP branch off master; sequenced after this lands.

## Closure Contract
- **Commands that run:** `bash adapters/claude-code/scripts/agent-heartbeat.sh --self-test`; `bash adapters/claude-code/hooks/stalled-work-surfacer.sh --self-test` (if present); `git show --stat HEAD` shows the lesson committed.
- **Expected outputs:** agent-heartbeat self-test all-pass (emit writes to agents/ namespace, watch flags a stale agent + passes a fresh one + mtime fallback fires with no heartbeat, reap prunes old); surfacer still green; lesson in git history.
- **On-disk artifact location:** `adapters/claude-code/scripts/agent-heartbeat.sh`; heartbeats under `~/.claude/state/heartbeats/agents/`; evidence in this plan's `## Evidence Log`.
- **Done when:** the mechanism is on master (both remotes), live-synced, self-tests green, harness-reviewer PASS (or CONDITIONAL-PASS with findings fixed).

## Evidence Log
- Task 1 — `agent-heartbeat.sh` (emit/conclude/watch/reap) built in the dedicated
  `heartbeats/agents/` namespace; `--self-test` 19/19 (emit→agents namespace not session board,
  fresh-not-flagged, stale-flagged, `--long` 3x grace, `.ack` suppression, corrupt-ts mtime
  fallback, conclude self-removal, 20m boundary 19m/21m, path-traversal sanitization, reap, no-op
  on missing --agent). Registered in manifest.json. commit: 3cb9f3b (+ review fixes ba7ac46).
- Task 2 — dispatch-prompt heartbeat+conclude convention added to
  `doctrine/background-work-tracking.md` (2621B, under 3000 cap) with the honest Pattern/residual
  label; `agent-heartbeat.sh watch` + `reap` spliced into `stalled-work-surfacer.sh run()`;
  surfacer `--self-test` 6/6 incl. new T6 (stalled agent surfaces through the surfacer). commit: 3cb9f3b.
- Task 3 — harness-reviewer verdict CONDITIONAL-PASS (Pattern classification agreed; board-namespace
  isolation + path resolution + graceful degradation all PROVEN). All findings fixed in ba7ac46:
  Major-1 completion-blind cry-wolf → `conclude` terminal beat + mandate + tests; Major-2 dead reap
  → wired into the surfacer SessionStart tick; Minor-1 boundary+traversal self-tests; Minor-2 softened
  the "5h hang" overclaim. Post-fix self-tests green (19/19, 6/6). commit: ba7ac46.
- Follow-ups filed (non-goals): runtime auto-heartbeat primitive (out of repo reach) + wiring the
  agent heartbeat into the orphaned-worktree-guard `_live_owner` join (GUARD-REFORMULATE-01).
