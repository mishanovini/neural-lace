# Plan: TaskCreate/TaskList ↔ Workstreams Binding

Status: ACTIVE
Execution Mode: orchestrator
Mode: code
tier: 2
rung: 2
architecture: coding-harness
frozen: true
prd-ref: n/a — harness-development
acceptance-exempt: true
acceptance-exempt-reason: Harness-internal — binds the Cowork TaskCreate/TaskList tool suite to the durable Workstreams event-sourced substrate so the orchestrator is structurally nudged to use the harness-native task list. The "user" is the orchestrator (and Misha viewing his work tracker). Acceptance = the new hook's --self-test passes every scenario (zero-task block, task-created pass, completed pass, trivial-session pass; bridge emits action-added/session-bound/action-done/item-backlogged; SessionStart surfaces pending Workstreams items; message-gate warns on un-recorded commitments). build-harness-infrastructure work-shape — every file under adapters/claude-code/; self-tests are the acceptance artifact.
Backlog items absorbed: none

## Goal

Make the orchestrator structurally use the harness-native **TaskCreate/TaskList** task tracker, and bridge that lightweight in-conversation surface into the durable **Workstreams** event-sourced substrate (ADR-032), so that:

- **TaskCreate/TaskList** = the lightweight write surface (user-visible widget; ephemeral, per-conversation).
- **Workstreams** = the durable cross-session state (the event log the GUI renders).
- Every in-conversation commitment the orchestrator tracks in TaskList **automatically mirrors into Workstreams events**, and pending Workstreams items **surface back** at the next session start.

Misha's framing: "How do we keep you always using [the task list]? How can we build it into what we are currently building?" The answer is three reinforcing hooks + a bridge, none of which require a new event type (zero collision with Component B, which is concurrently editing `reducer.js`/`schema.js` in `.claude/worktrees/component-b/`).

## Scope

- IN:
  - **Mechanism 1 — Stop hook** (`--on-stop`): if a session made > N tool calls (default 5) but created/updated ZERO tasks, surface an injection telling the agent to record its work in a task. ALSO **bridge** every Task* call this session into Workstreams events (this is the same single transcript scan).
  - **Mechanism 2 — SessionStart hook** (`--on-session-start`): read the durable Workstreams event log and surface this project's still-active items ("active commitments") so the agent has visibility without transcript scrolling.
  - **Mechanism 3 — PreToolUse hook** (`--on-message`) on the Dispatch message surface: scan the outgoing message for commitment patterns; if a commitment is detected with no corresponding TaskCreate in the recent transcript, **warn** (default) the agent to record it first.
  - **The bridge** (`lib/workstreams-task-bridge.js`): the node helper the Stop hook calls to parse the transcript, correlate Task* calls, and emit `action-added` / `session-bound` / `action-done` / `item-backlogged` via the frozen `appendEvent` facade.
  - settings.json.template wiring for all three; live `~/.claude/` sync.
- OUT:
  - **No new event types.** The bridge maps onto the existing ADR-032 enum only (no `reducer.js`/`schema.js` edit → no collision with Component B).
  - **No personal-mirror sync** (DEFERRED, blocked on Misha's reconverge decision — separate task #8).
  - **No changes to the Workstreams GUI / state library** (frozen A2 facade is called, never modified).
  - Block-mode for Mechanism 1 hard-loops, and Mechanism 3 block-mode, are NOT defaults — env-gated, calibration-first.

## Tasks

- [ ] 1. Author this plan (build-harness-infrastructure shape). — Verification: mechanical
- [ ] 2. Build `lib/workstreams-task-bridge.js` — transcript→Workstreams bridge + counts. — Verification: mechanical
- [ ] 3. Build `workstreams-task-binding.sh` — three modes + `--self-test`. — Verification: mechanical
- [ ] 4. Wire all three hooks in `settings.json.template`; sync to `~/.claude`; verify byte-identical. — Verification: mechanical
- [ ] 5. Run `--self-test` (all scenarios green); close plan; ship to PT master. — Verification: mechanical

## Files to Modify/Create

- `adapters/claude-code/hooks/lib/workstreams-task-bridge.js` — NEW. Node helper: parse transcript JSONL, correlate `TaskCreate`/`TaskUpdate`/`TaskList` (by Cowork taskId), emit the four bridge events idempotently via the resolved state-lib `appendEvent`, print a JSON summary `{toolCalls, taskCalls, taskCreates, taskUpdates, emitted}`.
- `adapters/claude-code/hooks/workstreams-task-binding.sh` — NEW. Multi-mode bash hook (`--on-stop` / `--on-session-start` / `--on-message` / `--self-test`). Mirrors `conversation-tree-emit.sh` structure (failure isolation, `_resolve_state_lib`/`_resolve_gui_state_path` reuse, `stop-hook-retry-guard.sh` for loop safety).
- `adapters/claude-code/settings.json.template` — wire M1 into Stop chain (after `conversation-tree-emit.sh --on-stop`, before `deferral-counter.sh`), M2 into SessionStart (after `conversation-tree-emit.sh --on-session-start`), M3 into PreToolUse (matcher `SendUserMessage`).
- `~/.claude/hooks/workstreams-task-binding.sh`, `~/.claude/hooks/lib/workstreams-task-bridge.js`, `~/.claude/settings.json` — live-mirror sync (two-layer config).

## Assumptions

- The Cowork **TaskCreate/TaskList/TaskUpdate** tools have no project-file persistence; the only hook-readable signal is the transcript JSONL (confirmed: `tool_use`/`tool_result` blocks in `~/.claude/projects/*/*.jsonl`) and the Workstreams event log.
- The Workstreams state-library `appendEvent` facade and the ADR-032 event enum (`action-added`/`session-bound`/`action-done`/`item-backlogged` all present, each requiring only `node_id`+`item_id`[+`text`/`session_id`]) are stable and frozen (verified against `schema.js`).
- Stop and SessionStart hooks receive `transcript_path`/`cwd`/`session_id` on stdin (verified against the existing `conversation-tree-emit.sh` modes).
- The Dispatch message tool is named `SendUserMessage` (per `orchestration-architecture-2026-05-30.md`). If the live name differs, M3's PreToolUse matcher simply never fires — no false enforcement (Rule 7). This is the single calibration point.
- `node` and `jq` are available (same dependency baseline as `conversation-tree-emit.sh`).
- Component B (`.claude/worktrees/component-b/`) touches `reducer.js`/`schema.js`/plan files only — NOT `settings.json.template` nor any hook this plan creates. Coordination check: this plan adds no event type and edits no shared file.

## Edge Cases

- **Re-fired Stop / re-run bridge** → idempotent on deterministic `event_id`; a second run is a per-file no-op.
- **Session that legitimately did no trackable work** (≤ N tool calls) → M1 passes without requiring a task (trivial/lookup-session carve-out).
- **Hard-loop risk on M1 block** → `stop-hook-retry-guard.sh` downgrades to warn after 3 identical failures; a fresh `.claude/state/workstreams-task-waiver-*.txt` (<1h, ≥1 substantive line) is the gate-respect escape hatch.
- **Bridge targets a node that doesn't exist** → the bridge emits a `branch-opened` for the session node first (idempotent, same id scheme as the emit hook); the reducer rejects-not-applies any residual mismatch (no false mutation).
- **TaskCreate result id unparseable** → fall back to a later TaskList result (which carries id+subject+status for every task) to recover the correlation; if still unknown, derive item_id from subject so `action-added` still emits.
- **No Workstreams state file yet** (M2) → silent no-op.
- **Message tool absent / different name** (M3) → matcher never fires; no-op; documented calibration point.
- **`node` unavailable** → bridge no-ops; M1 falls back to a jq-only tool-call count so the enforcement still works without the bridge.

## Testing Strategy

`workstreams-task-binding.sh --self-test` exercises, against temp state + synthetic transcripts:
- M1: (a) >N tool calls + zero Task* → BLOCK signal; (b) Task created → PASS; (c) Task updated→completed → PASS; (d) trivial ≤N-tool-call session → PASS without task.
- Bridge: TaskCreate→`action-added`; TaskUpdate in_progress→`session-bound`; completed→`action-done`; deleted→`item-backlogged`; idempotency (re-run → no new events).
- M2: pending Workstreams item in the project root → surfaced; no items → silent; item in another project → not surfaced.
- M3: commitment-shaped message + a TaskCreate present → PASS; commitment-shaped message + no TaskCreate → WARN; non-commitment message → PASS without check.
Prints `self-test: OK` / `self-test: FAIL`, exit 0/1. This is the acceptance artifact (build-harness-infrastructure shape).

## Walking Skeleton

The thinnest end-to-end slice: a synthetic transcript containing one `TaskCreate` (subject "demo") fed to `--on-stop` against a temp state file produces exactly one `action-added` event in that state file, and `--on-session-start` against the same state surfaces "demo" as an active commitment. That slice exercises every layer (transcript parse → correlate → appendEvent → reduce → surface) and is the first self-test scenario.

## Decisions Log

All decisions below were reversible micro-decisions, default-picked and recorded per the pace constraint. The two **load-bearing** ones (thresholds/modes) are surfaced to Misha in the completion summary.

### Decision: No new event types — bridge maps onto the existing ADR-032 enum
- **Tier:** 1
- **Chosen:** `TaskCreate→action-added`, `TaskUpdate in_progress→session-bound`, `completed→action-done`, `deleted→item-backlogged`. All four already exist in `schema.js` EVENT_TYPES.
- **Reasoning:** Component B is concurrently editing `reducer.js`/`schema.js` in `.claude/worktrees/component-b/`. Adding an event type would collide. The existing enum covers the task's named mappings exactly (the spec's `action-done` for "completed" is a real event type; `item-backlogged` is the honest "parked, NOT shipped" closure for "deleted"). Zero shared-file edit ⇒ zero collision (coordination check satisfied).
- **To reverse:** Re-map in `lib/workstreams-task-bridge.js` `buildEvents()`.

### Decision: Build in an isolated worktree off master, ship additively
- **Tier:** 2
- **Chosen:** New branch `feat/taskcreate-workstreams-binding` from `master` (37d9865) in `.claude/worktrees/task-binding/`. Purely additive (2 new files + 3 settings entries).
- **Reasoning:** The current `feat/workstreams-phase-3` branch carries in-flight Phase-3 + Task-2b (hook rename) work; shipping this binding from there would drag that unrelated work to master. Master has the workstreams-ui state lib (Phase 1+2) this needs. Isolation keeps the change shippable alone.
- **To reverse:** `git worktree remove`.

### Decision (LOAD-BEARING): M1 default = block; M3 default = warn
- **Tier:** 2
- **Chosen:** `WS_TASK_STOP_MODE=block` (M1, the "did you track ANY work" gate), `WS_TASK_MESSAGE_MODE=warn` (M3, the "you committed without a task" gate). Both env-tunable (`block|warn|off`).
- **Reasoning:** Honors the spec's explicit asymmetry — Misha specified Exit-Code-2 for M1 and "default to warn-only initially; flip to block after calibration" for M3 (the most intrusive). M1's block is made safe (gate-respect.md) by: a tool-call threshold carve-out (trivial sessions pass), `stop-hook-retry-guard` (downgrades to warn after 3 identical failures — can't hard-loop), and a `.claude/state/workstreams-task-waiver-*.txt` escape hatch.
- **To reverse:** Set the env vars; or change the `${WS_TASK_*_MODE:-...}` defaults.

### Decision (LOAD-BEARING): M1 threshold = 5 tool calls
- **Tier:** 1
- **Chosen:** `WS_TASK_MIN_TOOLCALLS=5` — block only when `toolCalls > 5` AND zero task mutations.
- **Reasoning:** A session with ≤5 tool calls is plausibly a lookup/trivial session that shouldn't be forced to create a task (spec scenario d). 6+ tool calls with no task is "real work went untracked."
- **To reverse:** Set `WS_TASK_MIN_TOOLCALLS`.

### Decision: M2 surfaces from Workstreams (not TaskList); scoped to project root
- **Tier:** 1
- **Chosen:** SessionStart reads the durable Workstreams event log and surfaces active `kind=action && !checked && !deferred` items under the cwd's project root subtree.
- **Reasoning:** TaskList has NO hook-readable state file (it's a Cowork runtime tool). The Workstreams log IS a readable file, and the bridge populated it from prior sessions' TaskCreates — so surfacing from Workstreams is the only workable design AND is exactly the intended binding (TaskList→durable→next-session visibility). "This session's workspace" maps to the project root via the SAME cwd→root mapping the emit hook uses.
- **To reverse:** Adjust the `--on-session-start` node query.

### Decision: M3 PreToolUse matcher = `SendUserMessage` (calibration point)
- **Tier:** 1
- **Chosen:** Matcher `SendUserMessage` (the Dispatch message-surface tool named in `orchestration-architecture-2026-05-30.md`).
- **Reasoning:** `SendUserMessage` is not in a standalone session's tool registry — it is the Dispatch orchestrator's message surface, which is exactly the target ("keep the orchestrator using the task list"). If the live tool name differs, the matcher simply never fires (no false enforcement — Rule 7). This is the single piece needing live calibration.
- **To reverse:** Change the matcher string in `settings.json.template` (+ live `~/.claude/settings.json`).

## Definition of Done

- [ ] `workstreams-task-binding.sh --self-test` prints `self-test: OK`, exit 0.
- [ ] Bridge emits the four mapped events; idempotent on re-run.
- [ ] Three hooks wired in `settings.json.template`; live `~/.claude/` byte-identical (`diff -q`).
- [ ] Plan Status: COMPLETED; archived.
- [ ] Shipped to PT master (no personal-sync); Decisions Log captures the defaults chosen.
