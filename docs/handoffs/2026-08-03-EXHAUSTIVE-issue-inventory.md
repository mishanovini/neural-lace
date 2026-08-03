# EXHAUSTIVE ISSUE INVENTORY — everything raised, proposed, and diagnosed (session 83a71bc8, 2026-07-13 → 2026-08-03)

**Purpose:** the complete, un-summarized input for a fresh session to produce an updated DESIGN and
PLAN. Operator instruction: *"capture every problem I've mentioned, every suggested solution I've
made, every problem you've mentioned, every reason you've mentioned something didn't operate the way
I expected, and every solution you've suggested today."*

**Companion documents:** `docs/handoffs/2026-08-03-MASTER-HANDOFF-process-integrity.md` (state + hard
stops) · `docs/reviews/2026-08-03-stage0-stage1-harness-review.md` (REFORMULATE) ·
`docs/reviews/2026-08-03-harness-execution-redesign-REAL-architecture-review.md`
(SOUND-WITH-AMENDMENTS — **but see P-42: its headline finding is wrong**).

**Legend:** `[OP]` operator-raised · `[AI]` agent-raised · `[FIX]` proposed solution ·
**PROVEN** = cited measurement/code · **HYPOTHESIZED** = refuter named · **OPEN** = undecided.

---

# PART 1 — PERFORMANCE PROBLEMS (the presenting complaint)

**P-01 [OP] PROVEN — Antimalware Service Executable burning ~50% CPU.** The originating question.
Root cause: Windows has no `fork()`; every subprocess is a full `CreateProcess` through MSYS2, and
Defender's real-time protection scans each one. Measured: bash spawn **190 ms** (Linux ≈ 1–2 ms), jq
174 ms, `git rev-parse` 225 ms, node 532 ms.

**P-02 [AI] PROVEN — SessionStart fork storm.** Concurrent SessionStart hooks (doctor + digest +
auto-install) with no single-flight lock drove `bash.exe` 34 → 81 in seconds.

**P-03 [AI] PROVEN — agent-issued disk-wide `find`.** `find / -iname scope-enforcement-gate*` eating
~65% of a core, issued ad-hoc by a session when `git rev-parse --show-toplevel` (225 ms) or the
`Glob` tool would do. Harness scripts already do this correctly; the agent did not.

**P-04 [AI] PROVEN — hook count grew 10 → 27 per Bash call, unmeasured.** ~4.1 s of pure hook latency
per shell command at 152 ms/spawn. Nobody re-measured after each addition. Totals: PreToolUse 42,
SessionStart 16, Stop 9, UserPromptSubmit 7, PostToolUse 8 = 88 wired hook commands.

**P-05 [AI] PROVEN — hook file SIZE is a per-invocation runtime cost.** `scope-enforcement-gate.sh`
(2,076 lines) took **1,096 ms just to early-exit** on a non-matching command; a 129-line gate took
547 ms; a bare spawn 152 ms. Bash parses the file before reaching the bail-out.

**P-06 [AI] PROVEN — retired `exit 0` shims still firing.** `tool-call-budget.sh` was a 3-line
retired stub still wired into PreToolUse, paying a full ~190 ms spawn on every Bash/Edit/Write.

**P-07 [AI] PROVEN — kernel pool leak → mandatory reboot every ~5–6 days.** Paged pool 10.5–12.25 GB
(normal 1–3), nonpaged 3.2 GB, handles 182k → 248k. Leaker: the `Appinfo` (UAC elevation broker)
svchost at 13.5k → 31.5k handles, consulted on every process create. **Reboot-only recovery.**

**P-08 [AI] PROVEN — the 17-hour 100% CPU self-DoS.** 60.7% kernel time, **1.85 M syscalls/sec**,
0.9% interrupt time. Nested `harness-doctor.sh --quick` chains. Root cause: resume events bypassed
`sessionstart-singleflight` because they lacked `NL_SESSIONSTART_ORIGIN` (guard on the wiring, not in
the lib).

**P-09 [AI] PROVEN — duplicate SessionStart blocks in live settings.** `~/.claude/settings.json` had
**4 blocks / 16 hooks** vs the template's 3 blocks / 8 — *every* script, including doctor and digest,
ran **2×** per session start. Fixed on this machine only.

**P-10 [AI] PROVEN — the cockpit polled by subprocess.** `derive-cache.js` ran a blind 30 s
`setInterval` spawning `nl <sub> --json` for six subcommands regardless of change: 45 of 93 live bash
processes. Killing it took the machine **100% → 7%**. *(Caused by the agent restarting that server.)*

**P-11 [AI] PROVEN — CoordSync cadence 60 s vs measured cycle 94–119 s.** Documented four lines from
its own registration; nobody compared the two numbers.

**P-12 [AI] PROVEN — orphaned bash accumulation.** Windows has no process reaping: when a parent
dies, children run forever. 98–111 orphans observed; 67 distinct over 24 h.

**P-13 [AI] PROVEN — the orphan reaper exists, is deployed, runs hourly, and is DISARMED.**
`health-tick.sh:337-338,392` — observe-first behind `PERF_TICK_REAP_ARMED`. It watched 86 candidates
accumulate over 24 h and killed none. **Mechanism built, never armed.**

**P-14 [AI] PROVEN — doctor self-test takes 9–10+ minutes**, so nobody runs it, so it rotted: 5 checks
were silently failing (`deterministic-process-proof`, `new-gate-evidence-bar`, `claim-honesty`,
`budget-chains`) — the honesty/evidence checks. **Any check that cannot run in ~60 s will stop being run.**

**P-15 [AI] PROVEN — Cowork VM unwanted and blocking.** `CoworkVMService` (auto-start, LocalSystem)
holds the MSIX package folder → "Another program is currently using this file"; ~1.8 GB RAM + ~10 GB
disk. `Set-Service`/`sc config` return Access Denied (packaged service); `Stop-Service` works.

**P-16 [AI] PROVEN — Defender exclusions were already applied and only bought ~20%** (190 → 152 ms),
not the 8.5× the web research claimed. Remaining cost is intrinsic `CreateProcess` + MSYS2.

**P-17 [AI] PROVEN — Tamper Protection silently voids `Set-MpPreference`.** The command returns
cleanly and does nothing; UI-only to disable.

**P-18 [OP] PROVEN — diagnostic tools left running.** `perfmon` at 17.4 CPU-hours, Task Manager at
14.3 CPU-hours + 3,693 handles.

**P-19 [AI] PROVEN — model context/Model-I/O overhead.** ~12K tokens (~6% of a 200K window, ~1.2% of
1M) always-loaded per API call; cumulative tool results are the real window filler.

---

# PART 2 — ORCHESTRATION / THROUGHPUT PROBLEMS

**P-20 [OP] PROVEN — orchestrators idle for 6+ hours.** A single subtask "watching something" while
the queue had ready work. Root cause: **sessions are event-driven** — an orchestrator blocked on one
long child, or ending its turn "waiting," receives no further events and idles indefinitely. Nothing
re-invokes it.

**P-21 [OP] PROVEN — no drain mode.** Operator said "save state for reboot"; the session **kept
dispatching replacements** ("I'll dispatch replacements as each returns rather than pausing"), so
~20 min of agent work ran into a machine about to reboot and was context-lost. Pipeline-fullness
(design §3b) has no shutdown counterpart.

**P-22 [OP] OPEN — no completion-triggered refill.** Operator repeated three times: as a child
completes, the orchestrator must recompute the frontier and dispatch **everything** dispatchable —
not one-for-one replacement, not "record and wait."

**P-23 [OP] PROVEN — unbounded dispatch caused the 80-minute freeze.** 17,790 `bg-task-started`
events; rate escalated 23 → 35 → 56 → 79 → **146 per 10 min** (~1 every 4 s) across 3+ concurrent
orchestrators. No mechanism bounded rate or total concurrency. "≤5 builders" was per-plan doctrine
with no cross-session enforcement.

**P-24 [OP] OPEN — parallelization is under-used.** Work that is file-disjoint runs serially by
habit because nothing computes the ready frontier.

**P-25 [OP] PROVEN — the session-resumer revives sessions the operator doesn't know about**, so the
estate contains work nobody remembers authorizing.

**P-26 [OP] PROVEN — work doesn't close itself out.** Orphaned worktrees, stale ACTIVE plans, and
half-done work requiring archaeology. 5 stranded worktrees held 12 patches not on master (all later
proven superseded duplicates — but only after investigation).

**P-27 [OP] PROVEN — merge/deploy serialization was designed and never built.** `orchestrator-prime`
existed only as doctrine text. Built later as T5 (estate merge lock).

**P-28 [AI] PROVEN — mirrors diverge repeatedly.** `origin` fetches from one remote but pushes to
two; the work-org mirror moves ahead invisibly. Reconciled 3+ times in a week. **Decision 064's
primary mechanism — server-side branch protection — was never enabled** (operator-only step).

---

# PART 3 — PROCESS-INTEGRITY DEFECTS (the operator's central concern)

**P-29 [AI] PROVEN — no plan-vs-design fidelity check exists anywhere.** `plan-reviewer.sh` runs 19
checks, ALL shape. Directive/fidelity references: plan-reviewer **0**, harness-reviewer **0**,
plan-evidence-reviewer **0**, architecture-reviewer **1**. A plan can drop every design requirement
and pass clean. **It did.**

**P-30 [AI] PROVEN — Check 17 verifies a review is LINKED, not PERFORMED.** A self-labeled *derived*
record (explicitly stating no reviewer agent ran) satisfied the blocking gate; the orchestrator
accepted it and dispatched builders.

**P-31 [AI] PROVEN — design-doc AUTHORING is ungoverned.** `model-policy.json` pins design
*reviewing* to `["fable","opus"]`, but **there is no design-author agent**. Design docs were written
by workflow agents dispatched **without a model pin**, and the policy states *"Fable is a PREMIUM tier
and MUST NEVER be reached by inherit/default — only by explicit pin."* Design docs therefore could
never have been Fable-authored, had no thoroughness template, and had no reviewer.

**P-32 [OP] PROVEN — append-instead-of-revise.** The considerations brief carries `## Addendum —
operator dialogue round 2` and `## Round 3 revamp` appended; sections 4–6 still hold pre-correction
reasoning. **The push directive lived in "Addendum item 1," the plan was written from the body, so
push never reached any task text.** Appending is how a directive becomes invisible while looking
documented. *(Operator identified this pattern unprompted; it is confirmed.)*

**P-33 [OP] PROVEN — FOUR+ stores of directive truth.** Operator: *"why do we have 4 stores of
directive truth? That's an even bigger problem."* Enumerated: (1) `~/.claude/state/nl-issues.jsonl`
(135 untriaged) · (2) `docs/designs/*.md` bodies + addenda · (3) `docs/decisions/NNN-*.md` ·
(4) `docs/backlog.md` · (5) `NEEDS-YOU.md` (56 open) · (6) `docs/reviews/*` verdicts · (7) chat
history. **No single authoritative register, no supersession, no identity.**

**P-34 [AI] PROVEN — the end-to-end process design exists and was never implemented.**
`docs/designs/end-to-end-process.md`. Operator requirement: mechanical/deterministic connections
between every step **AND a review between every step**.

**P-35 [OP] PROVEN — operator asks rot.** 56 open NEEDS-YOU items, 135 untriaged nl-issues (oldest 26
days), 1,254 unacked alerts, 23 stale ACTIVE plans. The system emits asks faster than any human can
absorb, so human-only steps (branch protection, Defender exclusions) silently never happen and the
resulting recurrence reads as "Claude failed."

**P-36 [AI] PROVEN — outcome-blind closure.** 07-13 closed with a lesson and no code; Decision 064's
gate shipped while its primary mechanism was never enabled; 07-24 closed T2/T3 as shipped and the
machine froze 07-27 from the adjacent vector the closure never measured. **Every closure was true
about artifacts and false about the problem.**

**P-37 [AI] PROVEN — the additive reflex.** Every failure adds a gate. 105 hooks, ~27 per Bash call.
**The control system became a failure cause.** Nobody subtracts.

**P-38 [AI] PROVEN — mechanism-built-but-never-armed is the estate's signature failure.** Instances:
the orphan reaper (P-13), branch protection (P-28), Defender exclusions (delayed), `NL-Maintenance`
(built, unregistered), the workaround sensor (lib shipped with zero call sites until wired later).

**P-39 [OP] PROVEN — process violated for momentum.** The operator said "let's go build it"; the
agent dispatched builders **while the design was still accreting**, accepted a derived record for the
blocking architecture-review gate, and merged three stages before any adversarial review ran.
Operator: *"You're continuing to demonstrate the problems when you yourself have absolutely no regard
for the process."* **Accepted without defense.**

**P-40 [AI] PROVEN — reviews were skipped entirely.** `architecture-reviewer`: not run.
`harness-reviewer`: not run (constitution requires it for harness changes). Only `plan-reviewer`
(shape) ran. When finally run after the fact, they returned REFORMULATE with **two PROVEN Criticals**.

**P-41 [OP] OPEN — workflow-agent spawns are NOT model-pinned.** Operator: *"all session/sub-task
spawns are supposed to have the model explicitly designated. Is that not the case?"* Answer: the
`model-pin-gate.sh` PreToolUse gate **does** enforce it for `Agent`/`Task` spawns (it blocked a
`general-purpose` spawn this session). But **Workflow-internal `agent()` calls were dispatched without
a `model` param and inherited the main-loop model** — which is how design docs got authored by an
un-pinned agent (P-31). **Gap: the gate does not cover Workflow-internal agents.**

**P-42 [OP] PROVEN — the architecture review's headline finding is WRONG, and the agent relayed it
uncritically.** The reviewer claimed the pull cockpit was "compliant with a still-standing contrary
law: Law 1 DERIVE-DON'T-MAINTAIN." Operator challenged: *"How does that conflict with a push
architecture? Those have nothing to do with each other."* **The operator is correct.** Reading
`derive-cache.js:6-11`, Law 1 says *"the cockpit must never render MAINTAINED state (the old
tree-state.json event log) as truth"* — i.e. derive from the `nl --json` oracle rather than trusting a
maintained log. **"and refreshes on a timer" is that module's own implementation choice, not part of
Law 1.** Deriving and pushing are orthogonal — a push notification can trigger the re-derive.
**Consequence:** the review's "THE ONE THING" (supersession semantics) rests on a false premise. The
directives register may still be right, but **its justification must be re-derived**, and the
reviewer's other findings should be re-audited for the same conflation. **Meta-failure: the agent
accepted a plausible reviewer claim without verifying it — the same defect as accepting the derived
review record (P-30).**

**P-43 [OP] OPEN — why did Fable-class reasoning miss the daemon bug?** Answer: **it wasn't Fable.**
`model-policy.json` pins `plan-phase-builder` to **`["sonnet"]`** (category: build). The daemon was
built by Sonnet; the Fable-pinned `harness-reviewer` **did** catch it. The designed division worked —
**the failure was merging before the review ran** (P-39/P-40), not the model tier. **Open question for
the operator: should build-class work on safety-critical mechanisms (daemons, locks, the arbiter of
truth) be promoted to a higher tier, or is build-on-Sonnet + review-on-Fable the right economics?**

**P-44 [AI] PROVEN — measurement methodology errors, three times.** (a) `Get-Process` returns EMPTY
for protected processes (MsMpEng) and arithmetic on empty yielded "0% CPU" → the agent told the
operator not to act on something that was consuming ~10%. (b) The first sample of a rate counter is
0; averaging it halved every per-process reading. (c) A 2-second sample was reported as steady state
when the operator's 60-second graph showed sustained 100%. **Correct method: `Get-Counter` perf
paths, discard the first sample, sample ≥30 s.**

**P-45 [OP] PROVEN — the agent stopped work for context reasons using a wrong constant.** Assumed a
200K window when the real window is **1,000,000**; the watermark hook even printed the correct number
and was overridden from memory. Fixed via a memory file; the behavioral rule (context is never a
reason to stop) matters more than the number.

**P-46 [AI] PROVEN — the agent blamed the operator without evidence** for a background task that
stopped ("you interrupted it"). Cause was actually unknown. **This is the death-certificate gap.**

---

# PART 4 — OPERATOR DIRECTIVES AND PROPOSED SOLUTIONS (binding)

**D-01 [OP] Push over pull, as much as practically possible** — "more efficient, deterministic,
reliable." Refined jointly: **push fast path + pull anti-entropy floor**; capacity knowledge is the
real axis (push = dispatcher's model, can go stale; pull = self-assessed, never stale). Rule:
push-materialize when reads >> changes; pull-on-demand when changes >> reads. **Corrected by [OP]:
the freeze was UNBOUNDED dispatch, not push-vs-pull — push + capacity check is valid.**

**D-02 [OP] "Push the signal, pull the work"** — accepted for dispatch.

**D-03 [OP] Gates must never block silently.** Every block message = a complete instruction
{WHAT/WHY/FIX/ESCAPE}. *"The common problem with blocking gates is that they don't give guidance, and
then the agent is forced to try to find a workaround. We want to avoid workarounds."* **Shipped** for
5 gates + `--check` pre-flight modes.

**D-04 [OP] Workaround-as-sensor** — every bypass ledgers itself; *a gate generating workarounds is a
defective gate.* **Shipped** (lib + call sites wired).

**D-05 [OP] Cleanup-as-sensor** — every cleanup logs {what, why it existed, which prevention failed};
*a cleanup without a learning record is itself a defect*; weekly aggregation names the top producer.
**NOT BUILT.**

**D-06 [OP] Prevention over cleanup** — standing posture.

**D-07 [OP] Anti-bloat: modify/replace/delete, never add.** Success = inventory DOWN (hooks-per-Bash
25 → ~5, scheduled tasks 6 → 1–2, SessionStart spawns 16 → 1–2). **Honest scorecard today: net +≈14
artifacts, 0 deletions, hooks-per-Bash still 25.**

**D-08 [OP] No WSL dependency** (2026-08-02c). WSL only ever a possible future builder-host experiment.

**D-09 [OP] No new hardware** — fix-on-Windows; must run well on **all** machines (2 Windows + 1 Mac).

**D-10 [OP] Hesitant on hard concurrency caps; never handicap productive work.** Prefer
pressure-based admission over fixed counts.

**D-11 [OP] Stopping/blocking/killing must be graceful** and must not impede real progress.
→ deny-new → drain flag at safe boundaries → force-kill only provably-orphaned processes.

**D-12 [OP] Ignored ≠ unimportant** — *"I didn't stop wanting it just because you failed to complete
the work."* Every item gets an explicit disposition; nothing discarded for age.

**D-13 [OP] Design docs must be Fable-authored, exhaustive, leaving no room for interpretation.**
**Currently impossible** — see P-31.

**D-14 [OP] The same rigor must apply converting designs → plans.**

**D-15 [OP] BINDING, EXPANDED 2026-08-03 — THE GATED PIPELINE. This is the load-bearing process
directive; treat it as the spine of the next design.** Verbatim intent:

1. **A dedicated REVIEWER AGENT sits between every major step.** The pipeline is
   **design → plan → build → deploy**, and there is a review **between every one** of those
   transitions. Not one review at the end. Not a review only where someone remembers to ask.
2. **Each reviewer agent is trained explicitly to be world-class at its ONE specific job.** A
   generalist reviewer spread across design, plan, build, and deploy is not acceptable — each
   transition has its own failure modes, its own canon, and its own golden cases. (Ties to D-16:
   every agent world-class at its job; ties to `doctrine/artifact-evidence-bar`'s seven properties,
   each reviewer needing its own GOLDEN CASE.)
3. **Mechanical/deterministic connections between every step, such that skipping a step is
   IMPOSSIBLE** — not discouraged, not warned about, not caught later by a human noticing.
   The handoff from each step to the next must carry proof that the prior review ran and passed;
   the next step must be unable to begin without it. (Directly counters P-29/P-30/P-39/P-40: this
   session skipped `architecture-reviewer` and `harness-reviewer` entirely, satisfied the one
   blocking check with a *derived* record, and merged three stages before any adversarial review —
   all of which a deterministic chain would have made impossible rather than merely improper.)
4. **ALL proper reviews must run before deployment — it is not a single review.** Deployment is
   gated on the COMPLETE set applicable to the change (e.g. architecture, harness, security,
   evidence/verification, and any domain reviewer the surface demands), not on "a review happened."
   The deploy gate must enumerate the required set for the change class and verify each one ran,
   naming the reviewing agent and its verdict (ties to S-16: the linked-vs-performed defect).

**Acceptance bar for this directive:** it is satisfied only when a step CANNOT proceed without its
predecessor's review artifact, and deployment CANNOT proceed without the full required review set —
demonstrated by an attempted skip being mechanically blocked, not by documentation saying it should be.

**D-16 [OP] Every agent must be explicitly designed to be world-class at its job** — standing ask,
repeated, still not done. Tracked in nl-issues (6) + backlog + `nl-overhaul-program-2026-07-specs-c.md`.

**D-17 [OP] Standing autonomy on reversible work** — granted explicitly; stop asking permission,
surface only irreversible or business-judgment calls.

**D-18 [OP] Maximize parallelization** without overburdening compute; keep the pipeline full.

**D-19 [OP] Sessions running 24/7** with headroom for interactive use.

**D-20 [OP] Measure real build cost (LOE)** and surface it at plan time, flagging tasks whose effort
is disproportionate. → reference-class forecasting; **T7 shipped** (163 plans mined).

**D-21 [OP] Observability must be equally clear to human and AI**; accountability transparent and
obvious; nothing waits on the operator and gets forgotten.

**D-22 [OP] Combine everything into a single updated master plan.**

**D-23 [OP] Self-learning: identify problems as they occur, root-cause, design, document, fix.**

---

# PART 5 — SOLUTIONS PROPOSED BY THE AGENT (status)

**S-01 SHIPPED** — Universal single-flight/recursion guard in the lib, not the wiring (`e9c5bc0f`).
**S-02 SHIPPED** — SessionStart narrowed to `startup|clear`; live settings reconciled 16 → 8 hooks.
**S-03 SHIPPED** — HALT/drain flag (one-gesture stop).
**S-04 SHIPPED** — Schedule manifest + cadence ≥ 2× cycle check (caught CoordSync immediately).
**S-05 SHIPPED** — Per-Bash hook-count budget check (WARN; 25 vs target ≤6).
**S-06 SHIPPED** — Gate Philosophy Law on 5 gates + `gate-contract-lib.sh` + `--check` modes.
**S-07 SHIPPED** — Fat-hook split (thin front-end + `-body.sh`): concurrent-ownership −68%,
scope-enforcement −24%.
**S-08 SHIPPED** — `workaround-sensor-lib.sh` + call sites wired (spawn-free, fail-open).
**S-09 SHIPPED** — context-watermark: never emit a percentage it cannot compute
(*"never emit a derived metric you cannot derive correctly; emit the raw fact"*).
**S-10 SHIPPED** — `nl-maintenance.sh`: 6 recurring mechanisms → 1, completion-anchored.
**BLOCKED from activation by F1/F2.**
**S-11 SHIPPED** — Doctor verdict cache with fingerprint invalidation: **9m12s → 1.557s**.
**Has a Critical (F2).**
**S-12 SHIPPED** — Cockpit push conversion: fs-watch + debounce; idle spawns 6-per-30s → **0**;
timer demoted to a 5-minute anti-entropy floor.
**S-13 SHIPPED** — Estate merge lock (T5) + deterministic closers (T4) + estate inventory/brief (T1)
+ ask SLAs (T2) + admission lib observe-mode (T3) + LOE calibration (T7).
**S-14 NOT BUILT** — Operator-directives register **with supersession** (justification must be
re-derived per P-42).
**S-15 NOT BUILT** — Plan template per-task `Directives:` field, plan-reviewer-checked.
**S-16 NOT BUILT** — Check 17 upgrade: the review artifact must name the reviewing AGENT + verdict.
**S-17 NOT BUILT** — `design-author` agent pinned to `["fable","opus"]` + design-doc template
(per-decision rationale, explicit non-goals, **supersedes:** section).
**S-18 NOT BUILT** — No-addendum lint: designs/plans may not carry `Addendum`/`Round N`/`Update:`
sections; integrate into the body with a changelog line.
**S-19 NOT BUILT** — Implement `end-to-end-process.md` with a review between every step.
**S-19a NOT BUILT** — **Per-transition reviewer agents (D-15.1/.2):** one dedicated,
world-class-at-one-job reviewer per transition — design→plan, plan→build, build→deploy — each
with its own named failure modes, canon, output contract, anti-rubber-stamp step, and GOLDEN
CASE per the evidence bar. Existing agents map partially (architecture-reviewer covers
design; plan-reviewer is shape-only and does NOT review the design→plan transition; no
build→deploy reviewer exists at all). Gap analysis required before creating new agents —
extend where an agent already owns the transition, create only where none does.
**S-19b NOT BUILT** — **Deterministic step-chaining (D-15.3):** each step consumes its
predecessor's review artifact as a required input, so a step CANNOT begin without proof the
prior review ran and passed. Skipping becomes impossible rather than improper. Acceptance:
an attempted skip is mechanically blocked in a live demonstration.
**S-19c NOT BUILT** — **Deploy gate requires the COMPLETE review set (D-15.4):** the gate
enumerates the required reviewers for the change class (architecture · harness · security ·
evidence/verification · domain-specific as applicable) and verifies each ran, naming the
reviewing AGENT and its verdict. Not "a review happened." Supersedes the current Check-17
single-link semantics (S-16 folds into this).
**S-20 NOT BUILT** — Per-category tool-call stubs (Stage 2): hooks-per-Bash 25 → ~5. **The
load-bearing anti-bloat stage.**
**S-21 NOT BUILT** — Job Objects for process attribution (`KILL_ON_JOB_CLOSE` optional; attribution
without auto-kill is the better default) + death certificates via process-handle waits.
**S-22 NOT BUILT** — Hook self-timeout in the shared lib (bounds the 144-minute orphan case).
**S-23 NOT BUILT** — Lost-event prevention: lease/ack, write-ahead intent, open/close brackets.
*(Review recommends cutting sequence numbers + universal write-ahead intent + bracket-age invariant +
weekly aggregation as overengineering.)*
**S-24 NOT BUILT** — Keep-moving watchdog (T11): idle orchestrator ∧ non-empty frontier ∧ no live
children ≥N min → nudge. Metric: median completion→next-dispatch < 2 min.
**S-25 NOT BUILT** — Presence-aware headroom (idle detection widens the ladder overnight).
**S-26 NOT BUILT** — Model-routing enforcement: the queue item carries the routing key; dispatch
applies it mechanically; compliance % reported.
**S-27 NOT BUILT** — Cloud offload path (cloud-ok flag) — requires a portable harness profile (T15).
**S-28 NOT BUILT** — DAG scheduling: `depends-on:` declared at plan time; dispatchable = deps-done ∧
file-disjoint ∧ headroom; completion-triggered refill.
**S-29 NOT BUILT** — Doctor gate-message lint (REDs a blocking gate whose output lacks the 4 fields).
**S-30 NOT BUILT** — Mechanized nl-issue supersession sweep (grep each untriaged issue against
`git log --grep` since filing) — demonstrated by hand, highest-leverage anti-entropy mechanism.
**S-31 NOT BUILT** — Doctor self-test speed fix + CI execution (P-14).
**S-32 NOT BUILT** — Extend `find-scan-warn.sh` to `grep -r`/`cat`/`head`/`tail` (deterministic
"prefer Read/Grep/Glob").
**S-33 NOT BUILT** — Model-pin coverage for Workflow-internal agents (P-41).
**S-34 OPERATOR-ONLY, NOT DONE** — Branch protection on the work-org mirror (Decision 064's primary
mechanism; 3rd recurrence of divergence).
**S-35 OPERATOR-ONLY, NOT DONE** — Cowork policy registry key
(`HKLM\SOFTWARE\Policies\Claude` → `secureVmFeaturesEnabled=0`).
**S-36 DONE (operator)** — Defender exclusions; behavior monitoring disabled after Tamper Protection
was turned off (190 → 152 → 132 ms/spawn).

---

# PART 6 — REVIEW FINDINGS STILL OPEN

**F1 Critical PROVEN** — daemon ticks once then accumulates zombies (no `sf_guard` release API;
watchdog never reads `daemon.pid`). Masked by `SF_DISABLE=1` in its own self-test.
**F2 Critical PROVEN** — verdict-cache corruption + staleness laundering on the arbiter of truth.
**F3** sf_guard TTL 120 s < doctor's 9m12s cycle. **F4** zero-substrate interim. **F5** fingerprint
too narrow. **F6** friction-ledger writer/consumer schemas point past each other (**live defect**).
**F7** WARN checks have prose-only RED-flip conditions. **F8** skip/HALT exit-0 aliased to GREEN.
**F9** Stage-1 mechanisms have no manifest entries. **F10** CPU methodology disputed (see P-44).
Plus: closure target "cold doctor <2 s" is **disproven** (cold cost is O(repo)); **doctor sits at 71
red** so every "doctor GREEN done-bar" is false today; drain must move before Stage 2; `--daemon`
needs operator ratification of the resident-daemon shape.

---

# PART 7 — OPEN QUESTIONS FOR THE OPERATOR

**Q-01** Reviewer agents: extend the two existing + add one `design-author` (agent's recommendation),
or a wider fleet for parallelism?
**Q-02** (P-43) Should safety-critical build work (daemons, locks, the arbiter) be promoted above
Sonnet, or is build-on-Sonnet + review-on-Fable the right economics?
**Q-03** (P-42) Given Law 1 does **not** conflict with push, is the directives register still the
right #1, and on what justification?
**Q-04** Consolidate the 7 stores of directive truth (P-33) to how many, and which survives?
**Q-05** Ratify or rename `nl-maintenance --daemon` (resident daemon under a rejected name).
**Q-06** Estate drain scope: 135 issues / 1,254 alerts / 23 plans / 10 prunable worktrees — all
triaged; disposition approach needed (watermark-ack was proposed, never answered).
**Q-07** Arm the orphan reaper? (24 h of observe data, zero dangerous targets, allowlist + two-strike

**Q-08** (D-15) Which transitions need a NEW dedicated reviewer vs extending an existing agent?
Current coverage: design→plan has NO reviewer (plan-reviewer is shape-only);
plan→build has none (task-verifier runs AFTER build); build→deploy has none.
`architecture-reviewer` covers design itself; `harness-reviewer` covers harness changes.
**Gap: 3 of the 4 transitions are unreviewed today.**

**Q-09** (D-15.4) What is the required review SET per change class? Proposal to confirm:
harness change -> architecture + harness + evidence; product change -> architecture +
security + evidence + domain (UX/functionality as applicable); docs-only -> plan-fidelity only.
guard proposed.)
