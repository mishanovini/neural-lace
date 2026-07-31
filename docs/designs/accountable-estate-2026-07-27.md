# Design — The Accountable Estate: one obligation store, pull-based work, calibrated cost

**Date:** 2026-07-27
**Status:** REVIEWED 2026-07-27 — **SOUND-WITH-AMENDMENTS**
(docs/reviews/2026-07-27-accountable-estate-architecture-review.md). Build ONLY per the amended
form: admission = derived-lineage LIB in every dispatcher (never the gate alone — F2/F4); P0
observe-first, calibrate ≥7 days before enforcing (F1 — proposed caps were contradicted by measured
legitimate load); janitor = accountability authority only, NEW task, not a health-tick extension
(F3); consolidation target ≤3 with signal-ledger kept as a dumb flight recorder (F5); sequencing
views-first per the review's slice plan (F6); LOE v1 per-PLAN not per-task (F11). Companion mechanism doc: docs/designs/estate-performance-governor-2026-07-27.md (P0's brake).
**Operator asks driving this:** "observability just as clear to me as to the AI" · "accountability
transparent and obvious" · "nothing waits on me and gets forgotten" · "the system doesn't follow the
damn processes despite ridiculous enforcement effort" · "measure real build cost (LOE) and surface it
at plan time so I can decide what's worth the investment."

## 1. Why the system doesn't follow processes (the structural answer)

Enforcement today has two substrates: in-context rules (patterns — skipped under load; that's the
07-11 lesson) and per-tool-call gates (mechanisms — they check ONE moment in ONE session). But most
process obligations SPAN TIME AND SESSIONS: "close this when done," "re-check in a week," "this asks
waits on Misha," "prune that worktree after merge." **Sessions are ephemeral; obligations are
durable. There is no durable actor whose job is making obligations converge.** So obligations decay
the moment their session ends, and no amount of additional per-moment gating fixes a spanning-time
problem — which is why years of added enforcement produced bloat AND non-compliance simultaneously.

Corollary — why Workstreams UI has struggled: it was built as a *view over emitted events* from
uncontrolled sessions (emit/reconciler/read hook family, endlessly patched). A view over entropy
displays entropy. Observability cannot be bolted onto an uncontrolled process; it falls out for free
from a controlled one. **Invert it: build the control plane first; the UI becomes a thin view.**

## 2. The spine: ONE obligation store + one enforcer

**Store.** A single authoritative estate ledger (substrate decision — SQLite vs JSONL vs the existing
workstreams-coordination state repo for cross-machine — goes to architecture review). Typed records:
- `work-item` — anything autonomous. Lifecycle: proposed → authorized → queued → running(heartbeat)
  → verifying → done(outcome-evidence link) | killed. **No done without an outcome link.**
- `operator-ask` — anything waiting on Misha. Fields: what, why, deadline, **default-action** (what
  happens/doesn't if unanswered), SLA state. Hard cap ≤5 open; re-surfaced every brief until closed;
  breaching SLA escalates visually, never silently expires. Deadman semantics = forgetting is
  structurally impossible without nagging chaos.
- `issue` — today's nl-issues, absorbed.

Consolidation target (subtraction applied to STATE): today ~8 overlapping stores (backlog.md,
NEEDS-YOU.md, nl-issues.jsonl, operator-todo.md, ask-registry, workstreams state, signal-ledger,
plans' own status fields). End state ≤2: the estate ledger + docs/plans as spec detail. Everything
else becomes a generated view or is retired.

**Enforcer.** One scheduled janitor tick (extends existing health-tick — no new daemon):
unregistered running work → flag then stop; heartbeat-dead items → blocked/reaped; merged branches →
worktrees pruned; done-without-outcome → reopened; ask SLAs advanced; ledgers rotated. Runs
regardless of any session's cooperation. **The governor (P0) checks the store at dispatch time:**
no slot without a registered, authorized item. Registration stops being a convention and becomes
the admission ticket.

**Sessions interact through ONE lib call** (`estate.sh register|transition|heartbeat`), replacing the
emit/reconciler family over time (P3 subtraction target).

## 3. Push → pull: the operating-model change that prevents the mess

Today orchestrators PUSH work into existence (fan-out storms, orphan mess). Instead: a single
priority QUEUE (view of the store) that the operator curates; orchestrators PULL the next authorized
item only when the governor grants a slot. WIP limits per project. Fan-out becomes structurally
impossible; priorities become visible; "what is Claude doing and why" is answerable because nothing
runs that didn't come through the queue. (Kanban/WIP-limit logic — the standard cure for exactly
this failure shape.)

## 3b. DAG scheduling amendment (operator directive 2026-07-27c — max-throughput orchestration)

- **Dependencies are declared once, at plan time, not re-derived by an LLM per dispatch.** Plan
  template gains `depends-on:` per task (plan-reviewer checks acyclicity); `Files to Modify` is
  already per-task. Parallelizability then becomes COMPUTABLE, not judged:
  `dispatchable := deps-done ∧ file-disjoint-with-in-flight ∧ admission-headroom`.
  The deterministic queue layer computes the ready frontier; orchestrators just pull from it.
- **Completion-triggered advance:** the closer's done-event recomputes the frontier and dispatches
  the next item(s) automatically — event-driven, no polling, no idle gap between tasks.
- **Objective function (binding): verified completions per day — NOT CPU utilization.** Little's
  law guard: WIP beyond verify+merge capacity produces latency and rework, not throughput; the
  pile-up just moves to integration. Verify/merge slots are FIRST-CLASS capacity alongside build
  slots; the queue keeps them balanced (a verify backlog pauses new builds before the ladder does).
- **Amdahl expectation, stated honestly:** harness-core tasks couple on shared state
  (settings/manifest/install/doctrine) and are largely SERIAL by nature — that is why this program
  runs WIP=1 on itself. Width pays on file-disjoint product work; the speedup ceiling comes from
  the dependency structure, not ambition.
- **Presence-aware headroom:** interactive-core reservation only matters while the operator is
  active. Idle detection (no input ≥30 min / overnight) widens the ladder automatically — the
  day's unused CPU seconds get used when they are genuinely free, and narrow again on return.
- **Cloud offload is the true 24/7 multiplier:** local CPU-seconds are bounded; parallelizable
  build slices can run in cloud/scheduled sessions with local reserved for verify+merge (which
  must stay near the canonical checkout anyway).
- **Model routing:** mechanical task classes route to cheaper/faster models — more parallel work
  per rate-limit unit; the LOE class annotation (T7) doubles as the routing key.
- *(Optional, later)* speculative prep: when capacity idles and the frontier is empty, pre-run the
  read/research phase of nearly-ready tasks; discard-tolerant by design.

### 3b.1 Orchestrator liveness (the observed 6-hour-idle failure, 2026-07-28 operator report)
Mechanics of the failure: sessions are EVENT-driven — they act only on a user message, a returning
tool result, or a task notification. An orchestrator that blocked on one long synchronous child
(e.g. a "watcher"), or ended its turn waiting, receives no further events and idles indefinitely
with a non-empty frontier. Nothing re-invokes it. Three binding rules:
1. **Never block on a single child.** Dispatch background-first; immediately continue draining the
   frontier. A synchronous wait on one subtask while dispatchable work exists is an anti-pattern.
2. **Watcher-type work is never a builder session.** Watching/polling is Monitor/tick territory
   (deterministic, cheap); an LLM session burning a context window to watch something is waste AND
   it wedges its parent.
3. **Keep-moving watchdog (janitor rule):** registered orchestrator ∧ frontier non-empty ∧ no
   dispatch/completion event ≥N min ∧ no live children → nudge via the resumer channel ("frontier
   has K ready items, headroom exists — dispatch or record why not"). Idleness becomes a detected
   anomaly, not a silent state.
4. **Child-completion = a mandatory REFILL moment (operator directive, repeated 2026-07-28).**
   Every child-completion notification obliges the orchestrator to recompute the frontier and
   dispatch EVERYTHING dispatchable under current headroom — never a one-for-one replacement, and
   never just recording the result and waiting. A completion event both frees a slot AND may
   unblock dependent tasks, so the correct response is a full refill pass. Ending the turn while
   dispatchable items + headroom exist requires an explicit recorded reason; the watchdog (rule 3)
   treats an unexplained gap as the idle anomaly. Enforcement: the completion notification itself
   carries the refill prompt (frontier count + free slots injected by the janitor/queue layer), so
   the obligation arrives WITH the wake event rather than relying on the orchestrator's memory.

### 3b.2 Model routing — why it gets ignored today, and the mechanical fix
Today model choice is an LLM judgment at dispatch time, guided by doctrine (pattern-rung → skipped
under load), and the default (omit = inherit the parent's top-tier model) makes the expensive path
the path of least resistance. Fix: **remove the choice from the moment of dispatch.** The queue
item CARRIES its routing key (task class → model via one config table, annotated at plan time);
the dispatch path applies it mechanically. effort-policy-warn observes mismatches (observe-first);
the brief reports routing-compliance %. Ignoring becomes visible, then impossible.

### 3b.3 Presence implementation note
Janitor tick captures last-input idle time (Win32 GetLastInputInfo via one PowerShell call) →
`presence.json`; the admission lib reads it to widen (idle ≥30 min / overnight) or narrow (active)
the ladder. No new process; two file operations.

## 4. Observability: same substrate for human and AI

- **Daily brief** (generated artifact, ≤1 screen): running now / completed yesterday with outcome
  links / queued next / **your ≤5 asks with deadlines** / cost+throughput counters.
- **Workstreams UI is kept, not rebuilt** — re-pointed at the estate ledger as its only data source.
  Its historical struggle was the data layer, not the rendering.
- Agents read the SAME store (a file/db read at session start) — no divergence between what you see
  and what sessions believe.

## 5. LOE: calibrated cost estimation at plan time (reference-class forecasting)

**Why time estimates fail:** an LLM has no reliable clock sense, and wall-time depends on load,
model, and interruptions — wrong unit. The harness already records the RIGHT units in transcripts,
signal-ledger, and plan evidence: tokens (≈ dollars), tool calls, builder-sessions, review round-trips.

Method (named canon: Flyvbjerg/Kahneman reference-class forecasting; story-point calibration):
1. **Backfill actuals:** mine archived plans + evidence + transcripts → per-task actuals (tokens,
   tool calls, builder-sessions, rework loops). ~100+ archived plans exist; nobody has mined them.
2. **Task classes:** e.g. new-hook+self-test · gate-change · UI-surface · migration-sweep · docs ·
   schema-change. Each class gets an empirical distribution.
3. **Plan-time surfacing (extends plan-reviewer, already a hook):** every task annotated with class
   + **P50/P90 cost in tokens, dollars, and builder-sessions** (bands, never points) + concentration
   flags: "task 4 is ~60% of projected plan cost — worth it?" High class-VARIANCE itself surfaces as
   a risk flag (wide band = poorly understood work).
4. **Close the loop:** at plan close, actuals append to the calibration table; estimates improve
   with every plan. Estimate-vs-actual drift is itself a Loop-3 metric.
Cold-start honesty: first estimates ride on backfill quality; bands start wide and narrow with data.

**Live demonstration on this very program** (class-based, from comparable shipped artifacts):
- P0 brake: class = new-hook+lib (comparable: sessionstart-singleflight, shipped in ~1 builder
  session) → SMALL, low variance.
- P1 store+janitor: class = state-schema + multi-consumer migration (comparable: the workstreams
  emit/reconciler saga — many sessions, repeated rework) → **LARGE, HIGH variance. This is the risky
  bet in the program and exactly the thing the operator should explicitly green-light.**

## 6. Fold into the program (amended build order)
P0 brake (+HALT) → **P1 = this spine** (store + janitor + governor-integration) → P1.5 pull queue →
P2 outcome-gated closure reads the store → P2.5 LOE backfill + plan-reviewer surfacing → P3
subtraction (retire emit-family, absorb the 8 stores, hook diet) → P4 views (brief + re-pointed UI).

## 6b. Operator directives + edge-case register (2026-07-27, post-review dialogue)

**Directives (binding):**
- **Pipeline-fullness is a goal, not a risk:** the governor is cruise control — the same pressure
  signal that throttles storms tells orchestrators "headroom available, pull the next item." Target
  operating loop: `while headroom && queue non-empty: dispatch`; reviews overlap builds; serial
  wait-on-one-review is an anti-pattern to eliminate.
- **Pressure-based admission, NOT count caps.** Admission keys on measured strain (CPU/RAM/spawn-rate
  headroom); cheap sessions sail through. Count threshold survives only as an absurd-level backstop
  (~50), effectively never hit. (Supersedes the governor doc's fixed 4/min-cap framing; consistent
  with review F1.)
- **Graceful stop ladder, never kill live work:** deny-new → drain flag checked by the dispatch lib
  at safe unit boundaries (never mid-git-op) → force-kill only for provably-orphaned processes
  (dead parent / empty cmdline). The drain flag must be honored by session-resumer too (see edge 1).
- **Nothing scheduled is ever an LLM.** Event-driven capture (hooks at start/milestone/complete) is
  the status mechanism; the ONLY scheduled work is deterministic bash for absence detection (dead
  things emit no events — only time notices silence) + reduction to snapshot/brief. The brief is a
  rendering for the operator's reading moment, not a scheduled agent effort.
- **Telemetry law: no capture without a named consumer at birth** (anti writer-without-consumer,
  per the acknowledged P1/P2 gap). Every capture ships with its rotation policy.

**Capture additions (each with consumer):** builder OUTCOME events for background dispatches
(consumer: janitor slot-release + LOE) · token/cost per work-item+session and 429/529 events
(consumer: LOE + remote-pool dashboard) · dispatch lineage session→agent→work-item→ask (consumer:
inventory + attribution) · stage timings queued→started→first-commit→verified→done (consumer: LOE)
· estimate-vs-actual at plan close (consumer: calibration table) · denial/would-block ledger
(consumer: governor calibration + F7 alarm) · compaction events + context-fill rate (consumer:
Model-I/O pool view) · same-file re-edit churn (consumer: rework flag in brief).

**Edge-case register:**
1. **Janitor-vs-resumer fight** — janitor stops a session, resumer resurrects it; drain flag must be
   shared substrate honored by every automation (same lib, every actor — F2 principle).
2. **Session identity across resume/compaction** — session_ids change; lineage must chain across
   resume or attribution silently breaks.
3. **Calibration pollution** — observe-mode baseline recorded during the chronic-storm period; tag
   protected-orchestrator traffic so "normal" isn't learned from pathology.
4. **Hygiene leakage** — telemetry captures cmdlines/titles containing product names; machine-wide
   ledgers trip the hygiene gate (occurred 2× this week). Scrub-at-write required.
5. **Clock skew cross-machine** — hostname-scoped files fix writes, not ordering; record monotonic
   + wall time.
6. **Ledger as hot-path tax** — dispatch-time access must be spawn-free bash builtins
   (singleflight idiom) or the fix becomes its own overhead.
7. **LOE skew from model/mode changes** — actuals must record model+mode (Fable/Sonnet/fast/
   Ultracode shift cost distributions) or reference classes go stale silently.
8. **Workstreams-UI history, honest disposition** — the capture half was built and works (18k
   events); the authority half (enforced lifecycle, single write path, absence detection,
   outcome-gated closure) was never specified or built. This program IS that missing half; the UI
   is kept and re-pointed, not rebuilt.

## 6c. Deterministic closure, merge serialization, self-learning (operator directives 2026-07-27b)

**Deterministic self-closure — "work closes itself out" (repeated operator directive, now central):**
- **Closure is a phase of the work, not cleanup afterwards.** Every work-item type gets a
  deterministic CLOSER script (the close-plan.sh pattern generalized — seconds, no agent
  discretion): builder items close via verify → merge (through the merge lock below) → worktree
  remove → branch delete (or explicit preserve+reason) → ledger transition to done(outcome-link) →
  done event. A work item without a closer receipt cannot reach `done`.
- **Closure gates new work (the enforcement that needs no memory):** the admission lib refuses a
  session's NEXT pull/dispatch while its open-item count exceeds its WIP limit. Closing work is the
  path to more work — incentive-aligned, deterministic, no reliance on discipline or janitors.
- **No-orphan invariant:** branches/worktrees are REGISTERED at creation (spawn-worktree gains a
  ledger link to its work item) and de-registered by the closer. Anything existing without a ledger
  link is definitionally unattributable → janitor flags it. Creation registers; closure
  de-registers; the diff is always visible. Janitor remains backstop only (absence detection),
  never the mechanism.

**Merge/deploy serialization (operator asked "was the single deployment agent implemented?"):**
- **Status: NOT implemented.** PROVEN by inspection 2026-07-27: orchestrator-prime exists only in
  doctrine/Decision-050 text (grep hits in doctrine files only, no script/agent); coord-push/
  coord-sync serialize cross-machine STATE snapshots, not code merges. Adjacent protections that DO
  exist: concurrent-ownership-gate (live), Decision-064 single-canonical-master + FF-only
  autocorrect, pre-push-divergence-check.
- **Realization here: a lock, not an agent.** A long-lived "deployment agent" would itself be an
  unmanaged actor (heartbeat/resume/authority problems). Instead: merge-to-master becomes a
  critical section — estate-wide mkdir-atomic merge lock (the coord-sync single-writer idiom,
  proven in-repo) + ONE deterministic merge script (acquire → rebase/FF per git doctrine → push
  both remotes per 064 → release). No two sessions can merge concurrently; clean merges by
  construction. The closer (above) calls it; nothing else merges.

**Self-learning loop (wire EXISTING parts; no scheduled LLMs; no silent self-modification):**
- Pipeline on the ledger: **detect** (medium-loop anomaly rules over telemetry: dispatch-curve
  spikes, denial storms, churn, repeated gate false-fires, doctor RED transitions) → **capture**
  (auto-file an incident work-item WITH forensic snapshot at detection time — today's incident cost
  an hour of manual forensics; capture is free at the moment it happens) → **diagnose**
  (enforcement-gap-analyzer / why-slipped, dispatched as a NORMAL queued work item to a live
  session — never a cron agent) → **propose** (harness change, evidence bar applies) → **review**
  (harness-reviewer, exists) → **ship** → **outcome-track** (P2: metric + re-check date,
  auto-reopen on recurrence).
- Consumption fix for the 40-untriaged rot: learning items carry SLAs like every other ledger item
  and are pulled through the same queue — triage is work, not a cron job.
- Boundary (binding): self-learning = self-detecting + self-proposing. Shipping a change always
  passes review and lands operator-visible. A system that silently rewrites its own controls is the
  adaptive-wall failure mode; excluded by construction.

## 7. Known residual risks (for the architecture review)
- **Coverage gap, decision-064 class:** cloud/scheduled sessions (no PreToolUse) can bypass the
  governor gate — the janitor's stop-unregistered-work sweep is the backstop; is that enough?
- Storage substrate + cross-machine sync (laptop + cloud + this box).
- Single-writer contention on the store under concurrent sessions (today's ledger shows bursts).
- Migration sequencing: 8 stores → 2 without losing in-flight obligations.
