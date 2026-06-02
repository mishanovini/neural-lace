# Plan: Orchestrator Reconciler — Component B v1 (single-machine)
Status: DEFERRED
Deferred: 2026-06-01 — build complete + verified + pushed to PT origin (feat/orchestrator-reconciler-component-b @ ac684f4); master-merge blocked on parallel Phase-3/4/2b landing first (re-engage trigger in the Decisions Log + docs/discoveries/2026-06-01-component-b-merge-ordering-blocked-on-parallel-phase3.md).
Execution Mode: orchestrator
Mode: code
tier: 2
rung: 2
architecture: reconciler-as-node-module (pure fn) + wake-queue (thin Stop-hook trigger) + scheduled/Stop-hook runner; reads Workstreams ADR-032 event log via state.js; surface-first, auto-spawn gated behind config flag (default off)
frozen: true
prd-ref: n/a — harness-development
acceptance-exempt: true
acceptance-exempt-reason: harness-internal orchestration substrate; the user is the maintainer and `reconciler.selftest.js` + a live dry-run against real state are the acceptance artifacts (no product user-facing runtime to advocate for).
Backlog items absorbed: none
Work-shape: build-harness-infrastructure (every file under neural-lace/workstreams-ui/ or adapters/claude-code/)

## Goal
Implement **Component B** of the orchestration architecture (`orchestration-architecture-2026-05-30.md` §3): an event-driven **reconciler** that, on every wake, reads the entire Workstreams work-tracker state, computes cascades (items blocked-on a just-shipped thing become unblocked), inventories live sessions to detect stalls, fills free orchestrator slots from prioritized spawnable work, surfaces Misha-attention items, and emits the resulting state-transition events. The reconciler is a **pure idempotent function** of `(snapshot, events, liveSessions, claims, config)` — running it twice is harmless. It is `conversation-tree-emit.sh --heartbeat` "grown a brain".

This fixes "Dispatch doesn't keep tracking things" structurally: every session Stop drops a wake file; the runner reconciles on each wake; the system keeps itself moving (or, in v1's safe default, keeps **surfacing** what should move next).

## Scope
- IN:
  - `reconciler.js` — pure reconciliation core (steps 2–7,9 of §3). The brain.
  - `sessions.js` — live-session liveness via the **verified** transcript-mtime scan (NOT `claude agents`, which lists agent *definitions* not running sessions — see Decisions).
  - `reconciler-run.js` — the runner: read state → scan liveness → reconcile → emit events → write surface → optionally auto-spawn (headless-local only, gated).
  - `reconciler-config.js` — defaults (MAX_CONCURRENT, autoSpawn, stall/fresh windows, retryMax, runnerKindMap, priorityOrder).
  - `workstreams-orchestrator-queue.sh` — thin Stop hook that drops a wake-trigger file. (Separate hook, NOT an edit to the parallel-build's `conversation-tree-emit.sh`.)
  - Additive optional `blocked_on` field on `item-blocked` (reducer captures `it.blocked_on`) — the data substrate the cascade needs.
  - `reconciler.selftest.js` — the 5 named DoD scenarios + idempotency + spawn-command construction.
  - Wiring: Stop hook into `settings.json.template` + live `~/.claude/settings.json`; runner schedule registration.
- OUT (per task brief — explicitly Component C / single-machine v1):
  - Cross-machine awareness, claim-lease, multi-remote broadcast (Component C — separate ship). v1 uses a **local claims stub** (always empty / local-file) so the reconciler's claim-aware code path exists and is testable, but no GitHub state repo.
  - Goal-completion verification (Component A `/goal` Stop hook — parallel ship).
  - Live auto-launching of Code/Cowork/Routine tasks (architecturally impossible from a subprocess — see Decisions; only Dispatch's agent loop can, by reading the surface). v1 ships the **surface**; headless-local `claude -p` is the only runner-executable auto-spawn and is gated `autoSpawn:false` by default.
  - Phase-3 lifecycle-event emission (the parallel build `local_55828ae9`). B consumes those events; it does not produce them.

## Tasks

- [ ] 1. Add optional `blocked_on` to `item-blocked` (reducer + schema comment); the cascade reads `it.blocked_on`. — Verification: full
- [ ] 2. `sessions.js` — `liveSessions({projectsDir, freshMin, now})` via transcript-mtime; also read heartbeat live-markers. — Verification: full
- [ ] 3. `reconciler.js` — pure `reconcile(input) → result`; cascades, stalls/orphans, slots, spawnable, pendingMisha, emittedEvents, spawnPlan. Idempotent. — Verification: full
- [ ] 4. `reconciler-config.js` defaults + `reconciler-run.js` runner (read→reconcile→emit→surface→gated spawn) + local claims stub. — Verification: full
- [ ] 5. `workstreams-orchestrator-queue.sh` Stop hook (drops wake file; exit 0 always; `--self-test`). — Verification: full
- [ ] 6. `reconciler.selftest.js` — 5 DoD scenarios + idempotency + spawn-command construction; all green. — Verification: full
- [ ] 7. Wire Stop hook into `settings.json.template` + live settings; register runner schedule; live dry-run against real state. — Verification: full

## Files to Modify/Create
- `neural-lace/workstreams-ui/state/reconciler.js` — NEW. Pure reconciliation core.
- `neural-lace/workstreams-ui/state/sessions.js` — NEW. Liveness adapter.
- `neural-lace/workstreams-ui/state/reconciler-run.js` — NEW. Runner entrypoint.
- `neural-lace/workstreams-ui/state/reconciler-config.js` — NEW. Config defaults.
- `neural-lace/workstreams-ui/state/reconciler.selftest.js` — NEW. Selftests.
- `neural-lace/workstreams-ui/state/reducer.js` — MODIFY. Capture optional `it.blocked_on` on `item-blocked` (additive).
- `neural-lace/workstreams-ui/state/schema.js` — MODIFY. Comment documenting the additive optional `blocked_on` (no required-field change, no major bump).
- `adapters/claude-code/hooks/workstreams-orchestrator-queue.sh` — NEW. Thin wake-file Stop hook.
- `adapters/claude-code/settings.json.template` — MODIFY. Wire the new Stop hook into the Stop chain.
- `~/.claude/settings.json` — MODIFY (live mirror). Same wiring.
- `neural-lace/workstreams-ui/scripts/register-reconciler.ps1` — NEW. Scheduled-task registration for the runner (sibling to register-heartbeat.ps1).

## Assumptions
- The Workstreams ADR-032 schema (Phase 1) is shipped: `item-committed`/`item-shipped`/`item-blocked` events + reducer handlers exist (verified — schema.js/reducer.js). `it.state` is set by these events.
- The runner reads/writes the same `tree-state.json` the GUI uses, via `state.js` (`STATE_FILE = workstreams-ui/state/tree-state.json`).
- node ≥ 18 available (verified v24.14.1).
- Lifecycle events are NOT yet flowing in production (Phase 3 in flight) — so the reconciler correctly NO-OPs against today's real state (0 lifecycle events). This is expected; B is the consumer, Phase 3 the producer.
- `~/.claude/projects/*/*.jsonl` is Claude Code's per-session transcript dir (the liveness substrate the heartbeat already uses).
- Single-machine: claims are a local stub (Component C OUT). Duplicate-spawn risk across two machines is accepted per the task brief until C lands.

## Edge Cases
- **No lifecycle events present** → cascade/spawnable empty; reconciler emits nothing; idempotent no-op. (Today's real state.)
- **`blocked_on` absent on a blocked item** → that item is blocked but has no declared dependency; it never auto-unblocks via cascade (correct — nothing to key off). Surfaced as blocked, not spawnable.
- **Stale snapshot / torn state** → `store.readState` already discards + replays (ADR-032 §7a). Reconciler trusts `readState`'s output.
- **A live session is bound to an item but its transcript mtime is stale (> stallMinutes)** → orphan candidate; release its (local) claim; item becomes re-spawnable. But never auto-kill the session (we can't).
- **More spawnable items than free slots** → spawn/surface only `freeSlots` items, highest-priority first; the rest stay spawnable for the next pass. Log the truncation (no silent cap).
- **runner_kind = code-task/cowork/routine** → cannot auto-launch from the runner; surfaced for Dispatch. Only `headless-local` is runner-executable, and only if `autoSpawn:true`.
- **Concurrent runner passes** → `flock` on a lock file serializes; idempotency makes overlap harmless.
- **Spawn failure** → increment `retry_count`; `< retryMax` re-spawnable next pass; `≥ retryMax` → surfaced as blocked-on-user with failure_reason (never silent infinite re-spawn).
- **Queue dir missing** → runner reconciles full state anyway (queue is only a wake trigger; losing it costs latency, not correctness).

## Testing Strategy
- `reconciler.selftest.js` (node, no deps) exercises the pure core against synthetic snapshots:
  - **S1 completion cascade → spawnable**: item B `blocked_on:A`; A ships → B becomes committed (cascade event emitted) AND appears in spawnable; with a free slot the spawnPlan contains B with the right runner_kind + DoD-carrying prompt.
  - **S2 stall detection**: in-flight item, bound session transcript stale > stallMinutes → orphan emitted, claim released.
  - **S3 slot management**: 6 spawnable, MAX_CONCURRENT 4, 2 live → freeSlots 2 → exactly 2 in spawnPlan, 4 remain spawnable.
  - **S4 pending-Misha surfacing**: a `blocked-on-user`/decision item is NOT spawned; appears in pendingMisha.
  - **S5 idempotency**: running reconcile twice on the same input emits the cascade once (second pass sees B already committed → no new event).
  - **S6 spawn-command construction**: spawnPlan entry → `claude -p` command string contains the item DoD + verification text (the cloud-carries-the-audit-inline composition point with Component A).
- Live dry-run: `node reconciler-run.js --dry-run` against the real `tree-state.json` → prints the reconciliation report (expected: empty/no-op today since 0 lifecycle events) without mutating state.
- Stop hook `--self-test`: drops a wake file, asserts it lands and is well-formed JSON.

## Walking Skeleton
The thinnest end-to-end slice: a Stop hook drops a wake file → `reconciler-run.js --dry-run` reads real state via `state.js`, scans transcript-mtime liveness, runs `reconcile()`, prints `{cascades, orphans, freeSlots, spawnable, pendingMisha}` and the surface JSON — all without mutating state or launching anything. Every architectural layer (queue → runner → liveness → pure core → surface) is exercised by that one command. Auto-spawn and event-emission are additive on top of the skeleton.

## Decisions Log

### Decision: `claude agents --json` is NOT a running-session inventory — use transcript-mtime liveness
- **Tier:** 1
- **Status:** proceeded with recommendation (evidence-forced)
- **Chosen:** Reuse the heartbeat's verified transcript-mtime scan (`~/.claude/projects/*/*.jsonl` mtime + live-markers) for session inventory + stall detection.
- **Alternatives:** `claude agents --json` (the task brief's premise). REJECTED — verified empirically: `claude agents` returns 22 configured agent *definitions* (task-verifier, explorer, …), NOT running sessions; there is no `--json` session-list and no CLI command that enumerates live sessions. This is exactly spike S-2's anticipated failure; the design doc named transcript-mtime as the verified fallback.
- **Reasoning:** Honesty (Rule 0): wiring `claude agents` would have been vaporware stall-detection. The transcript-mtime substrate is already proven in `--heartbeat`.

### Decision: Auto-launch of Code/Cowork/Routine tasks is impossible from a subprocess — ship the surface, gate headless-local spawn
- **Tier:** 2
- **Status:** proceeded with recommendation
- **Chosen:** The runner always computes + writes the **spawn surface** (`spawnable` + `pendingMisha` + spawnPlan). The only runner-executable auto-spawn is `claude -p` (headless local), gated behind `config.autoSpawn` (default **false**). Code/Cowork/Routine spawns are surfaced for Dispatch's agent loop to execute (it alone can call the MCP spawn tools).
- **Alternatives:** (a) Have the Stop hook call `mcp__ccd_session_mgmt__start_code_task` — IMPOSSIBLE: MCP tools are agent-loop-only; a hook/runner has no MCP surface (ADR-031 r5 "external software cannot launch a Dispatch session"). (b) Auto-launch everything via `claude -p` — would only ever produce headless-local sessions, not the Code/Cowork/Routine surfaces the design names, and is unsafe without Component A (trust) + C (claim-lease).
- **Reasoning:** Both design docs (orchestration-arch §8, workstreams-v2 §8/§10) sequence auto-spawn LAST, after A+C, and recommend B-lite (surface-only) first — for exactly the "spawns can collide and lie about being done" reason. `autoSpawn:false` IS B-lite; flipping it to true arms the (built + tested) headless-local path. Recommend keeping it OFF until A+C land.
- **To reverse:** set `autoSpawn:false` (default); delete the runner. Reversible.

### Decision: Add additive optional `blocked_on` to `item-blocked` so the cascade has a data substrate
- **Tier:** 2
- **Status:** proceeded with recommendation
- **Chosen:** `item-blocked` gains an OPTIONAL `blocked_on` field (the WorkItem id this item is blocked on); reducer captures `it.blocked_on`. The cascade keys off `it.blocked_on === <just-shipped item_id>`.
- **Alternatives:** (a) Parse free-text `block_reason` for item references — REJECTED (fragile, dishonest). (b) Reuse node-level `cross-links` with a `blocked-on:` tag — REJECTED (cross-links are node-level, cascade is item-level; semantic mismatch). (c) No substrate — REJECTED: the cascade would be a permanent no-op (vaporware headline feature).
- **Reasoning:** Additive (no required-field change, no major bump — same shape as the existing optional `evidence`/`reason`). Without it, "items blocked-on X unblock when X ships" cannot work. Scope-creep doctrine (Decision Principle 3): the right implementation needs this; it's additive within the same repo (no boundary crossing).
- **To reverse:** drop the reducer line; field becomes inert. Reversible.

### Decision: Reconciler is a node module + scheduled/Stop-hook-triggered runner, NOT the GUI server, NOT a bash hook
- **Tier:** 2
- **Status:** proceeded with recommendation
- **Chosen:** Pure `reconciler.js` core + standalone `reconciler-run.js` runner. Triggered by (a) the existing scheduled heartbeat cadence [backbone] and (b) a thin Stop-hook wake file [low-latency icing]. The runner does not require the GUI server to be up.
- **Alternatives:** (a) Reconciler inside the GUI server via `fs.watch` (workstreams-v2 §7) — couples reconciliation to the server being alive; orchestration-arch §3 prefers the scheduled runner for robustness. (b) Bash Stop hook does the reconciliation — bash can't cleanly do the graph computation and can't spawn. Rejected both.
- **Reasoning:** Matches orchestration-arch §3 ("scheduled runner is the trustworthy backbone; Stop hook is the icing"). The standalone runner survives a GUI-server-down state. Pure core is fully unit-testable.

### Decision: Session-1 completion state — built + pushed; master-merge DEFERRED on parallel-build ordering
- **Tier:** 2
- **Status:** built + verified + branch-pushed; master-merge deferred (coordination blocker)
- **What shipped (branch `feat/orchestrator-reconciler-component-b` @ ac684f4, pushed to PT origin):**
  - Tasks 1–6 fully built + verified IN-SESSION: `blocked_on` additive (reducer+schema); `sessions.js` liveness (transcript-mtime); `reconciler.js` pure core; `reconciler-config.js` + `reconciler-run.js` runner; `workstreams-orchestrator-queue.sh` Stop hook; `reconciler.selftest.js`.
  - Task 7 partial: queue hook wired into `settings.json.template` Stop chain; `register-reconciler.ps1` authored. The master-MERGE + live-settings sync + scheduled-task registration are blocked (below).
- **Verification evidence (this session):**
  - `reconciler.selftest.js` → 33/33 (S1 cascade→spawnable, S2 stall, S3 slots, S4 pending-Misha incl. committed-decision regression, S5 idempotency, S6 spawn-cmd, S7 no-op).
  - `workstreams-orchestrator-queue.sh --self-test` → 3/3.
  - Existing `selftest.js` (Phase-1 lifecycle) → 18/18 — NO regression from the `blocked_on` additive.
  - Live `--dry-run` against REAL state: 38 spawnable (actions) + 24 pendingMisha (decisions/questions), disjoint; `live=N` proves transcript-mtime liveness reads real sessions; no mutation.
  - Real cascade integration (temp copy of real state): A shipped + B `blocked_on:A` → `item-committed` emitted for B (real `appendEvent`) → B committed/unblocked/spawnable; second pass idempotent (0 new cascades).
  - `settings.json.template` JSON valid after wiring.
- **Master-merge blocker (re-engage trigger in `docs/discoveries/2026-06-01-component-b-merge-ordering-blocked-on-parallel-phase3.md`):** the parallel build `local_55828ae9` (Phase 3+4 + Task 2b) is actively mid-rename in the shared main checkout (`conversation-tree-*.sh` → `workstreams-*.sh`, incl. the hook my settings entry anchors on) with its own `settings.json.template` edit. Correct ordering = parallel-build-first, then Component B rebases onto the renamed master + re-anchors the one settings entry. Forcing my merge first would race an active session and risk a broken master / dropped wiring. Pushed-not-merged is the honest, collision-safe maximum this session.
- **Reversibility:** the branch is on PT origin; nothing on master changed; the scheduled task is not registered. Fully reversible.
- **Personal-mirror sync:** DEFERRED (fork-reconciliation pending — same as Phase 1+2).

## Definition of Done
- [ ] All tasks checked off (task-verifier)
- [ ] `reconciler.selftest.js` green (6 scenarios)
- [ ] Stop hook `--self-test` green
- [ ] Live `--dry-run` against real state prints a coherent (no-op-today) report without mutation
- [ ] Stop hook wired in template + live settings; runner schedule registered
- [ ] Merged to PT master (cite SHA); plan archived
- [ ] Findings surfaced to Misha; personal-mirror sync DEFERRED (fork-reconciliation pending)
