# Harness execution-layer redesign — considerations brief

**Date:** 2026-08-02 · **For:** operator · **Scope:** execution layer only — rules and block semantics unchanged under every posture considered here.
**Inputs:** mechanism RCA + design-process RCA (both verified against live `settings.json`, `harness-doctor.sh`, `coord-sync.sh`, Task Scheduler, `nl-issues.jsonl` this session), three candidate designs, three adversarial pre-mortems. Evidence markers: PROVEN = cited measurement; HYPOTHESIZED = refuter named.
**Changelog:** 2026-08-03 (`docs/plans/gated-pipeline-master-2026-08.md` Task 19, REQ-B10 no-addendum lint): the two trailing sections (`## Addendum — operator dialogue round 2` and `## Round 3 revamp`) folded into the body in place — §2 (invariant 10 extended, invariants 13-18 added), §3 (status note), §4.1, §4.2, §5 (D1/D2/D4 resolutions), §6 (restaged per the operator's Round-3 GO) all revised in place. Every contradicted statement is marked CORRECTED/SUPERSEDED/RESOLVED inline citing 2026-08-02; no content was dropped, only relocated to the section it corrects or extends. **2026-08-03** (`docs/plans/gated-pipeline-master-2026-08.md` Task 22, REQ-C4, carrying DEC-6/DEC-7 from `docs/designs/gated-pipeline-master-2026-08-03.md` §3): §2 invariant 8 AMENDED to its shipped coarse-fingerprint form (DEC-6); §5 D5 amended with the cold-doctor target re-scope (DEC-7, PROVEN 9 m 12 s clean-sandbox cold measurement). Both revised in place at the section they amend, no addendum heading, per the same no-addendum lint Task 19 established.

---

## 1. Root causes

Two chains. The mechanism chain explains why the machine burned; the process chain explains why a review-gated harness shipped it anyway. Any design that fixes only the first chain will regrow the problem.

### 1.1 Mechanism chain (what burned)

| # | Root cause | Evidence |
|---|-----------|----------|
| A1 | **Per-event bash spawn on Windows.** Every rule = a standalone script spawned per event; Windows has no `fork()` — each spawn is a full `CreateProcess` through MSYS2, Defender behavior-scan, Appinfo broker. Spawn tax 132–190 ms vs WSL2 <0.15 ms: a **>1000× gap** on the identical operation. Designs were priced with Linux intuition and deployed here. | PROVEN: 190 ms (07-13 lesson §2), 152 ms (nl-issues L13), 132 ms post-tuning; WSL2 <0.15 ms (2026-07-31 WSL2 review, L5) |
| A2 | **Kernel amplifier.** Process churn bloats kernel objects: paged pool 12.25 GB (normal 1–3 GB), 13.5k Appinfo handles → reboot every ~5–6 days. During the incident: 60.7% kernel time, 1.85 M syscalls/s — every unit of work paid ~double. | PROVEN: pool/handles (L1), kernel time (L18). HYPOTHESIZED: spawn churn *causes* the leak — refuter: pool still bloats after migration |
| B1 | **Additive growth, no subtraction.** Per-Bash-call hooks grew 10 → 27 (21 `Bash` + 4 `Bash\|PowerShell` + 2 PostToolUse matchers, confirmed live). At 152 ms/spawn ≈ **4.1 s pure hook latency per shell command**. Retired `exit 0` shims stayed wired weeks after being flagged. Nobody re-measured after any addition. | PROVEN: L13, live jq count; 07-13 lesson §3 (shims), §8b (retirement DEFERRED) |
| B2 | **No cost ledger anywhere.** Constitution §10 caps always-loaded *prose bytes* but nothing caps hook *count or CPU*. The §10 evidence bar for a new gate (golden scenario / FP rate / retirement condition) has **no cost line**. Doctor verifies wired == claimed (presence), never cost ≤ budget. | PROVEN: §10 text; L19 names the missing cost line as a design-process failure |
| C1 | **Maintenance layer is resident 24/7 load.** Six scheduled tasks spawn wscript→cmd→bash trees round the clock: CoordSync PT1M, SupervisorTick PT5M, workstreams-heartbeat PT5M, session-resumer PT10M, health-tick PT1H, downstream-product-health-monitor PT30M. | PROVEN: live Task Scheduler query this session |
| C2 | **Cadence < cycle time = perpetual overlap.** CoordSync fires every 60 s while its own header records 94–119 s per cycle (`coord-sync.sh:4,42`). It can structurally never drain; every fire lands on a running cycle (lock makes overlaps no-ops that still cost the full spawn chain). The script's self-test mechanizes a *different* cross-file invariant (`coord-sync.sh:115-122`) — the wrong invariant got mechanized. | PROVEN: file text + installer PT1M + live action chain |
| C3 | **Checker cost is O(mess).** Doctor `--quick` scans alerts/plans/issues; at 24 reds / 36 warns / 1,193 unacked alerts / 127 untriaged nl-issues / 18 stale plans it takes **minutes**, not the documented "<2s" (`harness-doctor.sh:13,22` — prose contract, zero enforcement). Monitoring cost coupled to the disease it measures. This is a **recurrence**: the 07-20 incident (`harness-doctor.sh:746-771`) was the same shape; the fix pinned the instance, never the invariant ("quick has a hard time budget"), so the class returned through a different door. | PROVEN: L18; doctor source |
| Trigger | **Resume-event bypass.** SessionStart *resume* events don't set `NL_SESSIONSTART_ORIGIN`, so the single-flight lock guards the wrong entry point; resumes fire the full 16-hook chain including doctor+digest. Result: 16 concurrent nested doctor chains, each O(mess) → the 17 h self-DoS at ~90% of the machine. | PROVEN: 08-02 root cause #2; `harness-doctor.sh:6372` |

**Compound reading:** A1 is the multiplier (100–1000× vs design intuition), B1/B2 grew the multiplicand unchecked, C1–C3 made the *maintenance* layer the dominant load, and the resume bypass was merely the spark. Fixing the spark alone (the minimal reading) leaves the powder.

### 1.2 Process chain (why review didn't catch it)

One sentence: every piece passed a genuinely rigorous review, but review is **unit-scoped, correctness-scoped, forward-looking**, while the failure was **aggregate-scoped, cost-scoped, installed-base-scoped** — and the meta-rules that would have caught it existed only as prose, the rung the harness itself proves gets skipped under load.

Five structural blind spots (each verified against the 07-27 architecture review, which was otherwise excellent — F1–F10 caught calibration, races, lib-vs-gate, derived-vs-declared):

1. **No cost budgets in the review checklist.** A hook can pass §10's bar while costing 1,096 ms to decide it has nothing to do (`scope-enforcement-gate.sh`, measured 07-13). Reviews ask "does it fire correctly," never "cost × fire-rate."
2. **No platform pricing.** No review artifact contains a "spawns × platform spawn cost × fire rate = CPU-s/day" table. CoordSync's 94–119 s cycle would cost ~1–2 s on Linux.
3. **No cadence-vs-cycle or degraded-state check.** Costs were priced at the healthy baseline; a maintenance layer runs hottest when the estate is sickest — a positive feedback loop no review examined.
4. **No aggregate artifact.** The review unit is the diff; nothing represents the sum. The maintenance layer never got an architecture review because it was never a design — it accreted below the review-triggering threshold. **The layer that ate 90% of the machine is the one layer that grew review-free.**
5. **No retroactive sweep.** The 07-27 review's F2 finding (enumerate all entry points) was applied to the new design only; the identical defect (resume bypass) sat live in the installed base. No regression sweep re-tests old mechanisms against newly learned failure classes.

**Meta-failure:** the 07-27 lesson's standing rules (outcome metric at close; no new blocking hook without a named replacement; asks ≤5) would have prevented most of this — and they shipped as prose in a lesson file. Hooks went 10→27 *after* that rule existed on paper. Companion defect: the warning pipeline had **mandatory writes, voluntary reads** — 1,193 unacked alerts is a channel, not a mechanism.

---

## 2. Invariants any design must enforce

These are posture-independent. A design that lacks one of these will re-derive this incident regardless of architecture. Each is stated as a mechanized check, not a norm — prose rules are the proven-skipped rung (§1.2).

1. **Cost budget, doctor-enforced.** Every recurring mechanism declares cost × fire-rate; doctor REDs above budget. §10's gate bar gains a mandatory cost line. (Counters B1/B2 — the additive reflex gets its first mechanical opponent.)
2. **Cadence ≥ 2× measured cycle time** for every scheduled task, from a central schedule manifest; doctor-enforced. Completion-anchored timers (next run scheduled only after the previous completes) satisfy it by construction and are preferred. (Counters C2.)
3. **Heavy state computed once per TTL per machine, never per session/event.** Doctor/digest/pressure are materialized snapshots; sessions read O(1). (Counters C3 amortization + the nested-chain class.)
4. **Guard in the lib, not the wiring.** Single-flight/recursion guards sit unconditionally at top-of-script; wiring markers (`NL_SESSIONSTART_ORIGIN`) are belt, never braces. (Counters the resume-bypass class; review F2 principle.)
5. **Health = output freshness, not loop liveness.** Any supervisor REDs on `generated_at` > TTL or breaker-open > 1 h — a fresh heartbeat from a process whose jobs are dead is a lie. (From daemon pre-mortem 1.)
6. **Fail-open escalates into a guaranteed-read channel.** Degraded enforcement injects a banner into every session's context via the SessionStart path; logs and alert files are not the mechanism (1,193 unacked proves it). Storm-capable categories time-box fail-open → fail-closed.
7. **Escape hatches are ledgered.** Every `NL_FORCE`/`--no-cache`/bypass use is logged; doctor WARNs above a rate threshold. Recorded lesson: "loud is not rare — env-var overrides are theater."
8. **Derived, never authored.** Cache fingerprints are computed from per-check declared inputs (doctor REDs a check with no declared inputs); state = fold(event ledger) + a ground-truth reconciliation floor that wins on conflict. (From minimal pre-mortem 1 + review F4; heals the lost-push class.) **AMENDED 2026-08-03** (predecessor build's own architecture review, `docs/reviews/2026-08-03-harness-execution-redesign-REAL-architecture-review.md` load-bearing premise 7 (F4) + Q2 item 1 + Q3 row 4 — arithmetic: per-check declared-input tracking for ~40 checks means ~40 hand-maintained input graphs, guarding against a staleness window the 30-min TTL (D5 below) plus output-freshness health (invariant 5) already bound): the SHIPPED form of this invariant is a coarse first-approximation fingerprint, not true per-check declared inputs — `harness-doctor.sh`'s `_doctor_compute_fingerprint` hashes the mtimes of live+template `settings.json`, `manifest.json`, `schedule-manifest.json`, the newest mtime anywhere under the live hooks mirror, the repo's HEAD commit, and a working-tree-dirty bit. That coarse fingerprint is now this invariant's text, not a deviation from it — it busts the cache on any edit to the highest-traffic input classes, with the TTL bound covering everything else. Full per-check declared-input machinery is REJECTED (DEC-6, `docs/designs/gated-pipeline-master-2026-08-03.md` §3) until a measured staleness incident the coarse fingerprint + TTL bound fails to catch; reversal is cheap — reinstate the full-machinery text as this invariant's target form.
9. **Retire-before-extend, mechanized.** A migration stage is not done until the old counterpart is deleted in the same plan, task-verifier-checked; doctor REDs "both substrates alive > 14 days." (From platform pre-mortem 1 — the stall-at-stage-2 trap.)
10. **Platform-priced review.** Any new recurring mechanism's review includes the spawns × platform-cost × fire-rate table for the machine it will run on, at the *degraded* estate baseline, not the healthy one. **Extended 2026-08-02 (Round 3 operator GO, R3.2):** the table must cover EVERY machine class in the estate (2 Windows + 1 Mac), not just the one it launches on first.
11. **One-gesture stop.** A HALT/drain flag honored by every tick wrapper and dispatch path — the emergency "disable 5 tasks by hand" becomes a supported mode.
12. **Outcome-gated closure.** The redesign closes on a measured outcome (24 h idle soak, all tasks enabled, <15% CPU), re-checked +30 days; recurrence auto-reopens. This is the direct counter to the outcome-blind-closure lesson (07-24 "shipped" → 07-27 freeze).

**Invariants 13-18 (added 2026-08-02, Round 3 operator GO, R3.4 "THE GATE PHILOSOPHY LAW" — gates never block silently):**

13. **Structured block messages (R3.4.1).** Every block message is a complete instruction with structured fields — WHAT fired, WHY, the exact FIX command/path, and the sanctioned ESCAPE with its cost — and the doctor lints gate sources for the fields' presence. The scope-enforcement gate's three-options message is the retrofit standard.
14. **`--check` pre-flight modes (R3.4.2).** Gates gain a consult-before-acting entry point so agents can ask "would this pass?" before doing the work — the gate as guide, not wall.
15. **Workaround-as-sensor (R3.4.3).** Every bypass/workaround attempt is ledgered; a gate that generates workarounds is a DEFECTIVE gate and gets auto-filed for redesign. Extends invariant 7 from escape hatches to all workaround behavior.
16. **Incentive-by-design (R3.4.4).** The right way is the cheapest way — the read-only zero-hook precedent, extended to batched commands and pre-declared scope.
17. **JIT pre-warnings (R3.4.5).** Requirements surface BEFORE the blocked attempt (hints at approach time), so first contact with a rule is guidance, not a wall.
18. **Gate-friction metric (R3.4.6).** Gate quality = blocks/day × workaround-rate, per gate, surfaced on the cost-budget dashboard. A gate trending hot is a defect to fix, not a fact of life.

---

## 3. The three postures compared

All three keep rules and block semantics unchanged; they differ only in where and how often the execution layer does heavy work.

| | **MINIMAL-CHANGE** (fix the six pathologies in place) | **CENTRAL DAEMON** (resident node service, state/management plane only) | **PLATFORM SHIFT** (thin Windows edge + WSL2/Linux execution plane) |
|---|---|---|---|
| **Fixes** | Idle self-DoS class (all four measured mechanisms); doctor O(1) repeat via verdict cache; resume bypass; ~2–3× per-Bash tax cut; one-gesture stop; the two missing invariants (budget, cadence) | Self-DoS (doctor/digest once per TTL, nested chains impossible); resume bypass (nothing heavy left on the path); cadence inversion by construction; per-Bash 25→~3 spawns; 6 tasks → 2; push fragility (fold+floor); the missing cost ledger, applied to the new center first | Spawn tax at source (4.1 s → ~4 ms in-plane, >1000×); the ~90%-CPU maintenance load leaves the interactive host permanently; resume storms; Defender per-spawn scan; orphan class dissolved natively (cgroups+PDEATHSIG); suspended-hook bug exposure for plane workloads |
| **Leaves broken** | Windows spawn floor (~21 spawns/call remain); kernel-pool reboot cycle (HYPOTHESIZED slower only); estate-entropy *production*; no central execution management; per-machine Task Scheduler wiring repeats on every future machine | Windows spawn floor for remaining stubs (<5 ms unreachable natively); O(mess) wherever doctor runs (cleanup still required); hookless-session bypass (Decision 011); RAM ceiling; performs no rule subtraction | Doctor O(mess) on any platform; additive reflex — Linux makes hook growth *painless again*, removing the felt pain that exposed it (budget invariant still mandatory); 64 GB RAM ceiling (WSL2 caps ~48 GB — dedicated Linux box is the real fleet destination); operator-surface overload |
| **Cost (builder-sessions)** | P50 7, band 5–11; every component independently shippable | P50 ~10, band 8–13 (P90 driven by Stage-4 stub rework) | P50 ~11, band 9–14; **stages 1–2 alone (2–4 bs) lock in the ~90% CPU win** |
| **Riskiest assumption** | The pathology list is complete AND stationary — entropy regenerates, cadence floors go stale, the class can recur off the fixed list (same shape as 07-24 close → 07-27 freeze) | 4–5 fail-open snapshot stubs preserve ~40 gates' exact block semantics while cutting spawns 25→3; wrong-strict replays governor-disabled-in-frustration, wrong-loose readmits storms | WSL2 sessions don't hit the #41649/#22855 thinking-phase regression (1–6 min delays; bot-closed, never confirmed fixed). Contained: maintenance offload makes zero model calls, ships first, captures the CPU win regardless; builder hosting is pilot-gated with an abort path to native-Unix hardware |
| **Pre-mortem verdict** | **Conditional pass.** Kill-shot: the authored fingerprint is blind to runtime phenomena — all four burn mechanisms produce a fingerprint MATCH, so the doctor serves cached green while CPU burns; bypass becomes boilerplate. Survivable only with invariant 8 (derived fingerprints) + invariant 7 (bypass ledger) | **Conditional pass.** Kill-shot: breaker + heartbeat + fail-open compose into a stable "green but not enforcing" state for a quarter — loop-liveness health lies while jobs are dead. Survivable only with invariants 5 + 6. Second class: UI cohabitation + Job-Object handle lifetime makes routine UI deploys kill sessions | **Conditional pass.** Kill-shot: stages 1–2 remove the felt pain, remaining stages lose every sprint, both substrates run forever (coord-sync ping-pong, two janitors). Survivable only with invariant 9 (retire-in-same-stage, both-substrates RED) + resequencing the operator-felt edge relief early. Second class: additive live-sync re-fattens the thin edge — template-generated profiles must be doctor-verified |

**Cross-cutting observations the table can't hold:**

- The postures are **not mutually exclusive**. Minimal's C0/C2/C3 (drain, universal single-flight, cadence floors) are prerequisites under every posture. The daemon's load-bearing ideas (completion-anchored timers, once-per-TTL snapshots, output-freshness health) are exactly what **systemd gives you for free** on a Linux plane — the daemon posture hand-builds on Windows what the platform posture inherits. This is the strongest argument against building the bespoke daemon: it is ~8–13 bs of re-implementing a supervisor that the plane substrate ships with, hosted inside a UI server whose deploy cadence then restarts the maintenance plane.
- Minimal is the only posture that leaves the incident's *substrate* (per-event Windows spawn) fully intact — its own cost analysis concedes ~60% of the outcome for ~70% of the daemon's cost.
- Platform shift is the only posture where the riskiest assumption has a **decomposed blast radius**: the unknown (#41649) gates only builder hosting, not the CPU win.

**Status note (2026-08-02, Round 3 operator GO):** the operator resolved D1 to **hybrid, WITHOUT WSL2** (R3.1, §5) and D4 to **closed, no new hardware** (R3.2, §5). The WSL2/platform-shift-specific costs in this table and in §4.4 below are retained as the ANALYSIS that led to the decision — still accurate comparative rationale — but the DECISION itself, and the staging that executes it, live in §5 (D1/D4) and §6, both revised in place.

---

## 4. Trade-off deep-dives

### 4.1 Push vs pull, per plane — the lost-event vs self-healing tension

**The tension.** Push (event on change) is cheap and fresh but fragile: a lost event is a permanent lie — PROVEN class: builders push launch-ack but never done, leaving phantom obligations. Pull (recompute from ground truth) is self-healing but expensive — and on this substrate, recompute cost is O(mess) × spawn tax, which is the exact mechanism of C3. Pure push lies; pure pull burns.

**Correction (2026-08-02, operator round-2 dialogue):** the freeze this analysis is grounded in was actually caused by UNBOUNDED dispatch, not by the push-vs-pull choice itself — push+capacity-check is valid. The real axis is where CAPACITY knowledge lives: push means the dispatcher's own model of capacity, which can go stale; pull means capacity is self-assessed at pull time, so it is never stale. Rule of thumb: push-materialize when reads far outnumber changes; pull-on-demand when changes far outnumber reads. Pull is retained regardless for: work acquisition, the anti-entropy floor below, trust facts, and cold-boot state.

**Resolution (all three designs converge on it, differing only in cadence):** push as fast path, pull as **anti-entropy floor** — state = fold(append-only ledger), plus a reconciliation sweep every 5–30 min that re-derives from ground truth (process table, `git worktree list`, heartbeats) and wins on conflict. Lost pushes self-heal within one floor interval; the floor's cost is bounded by invariant 2 (cadence ≥ 2× its own cycle time).

**Per plane:**
- *Within-machine:* hooks append one-line JSON to per-writer O_APPEND spools (works with the consumer down — no loss window); the consumer folds via file-watch. Obligation: spool rotation with a named consumer at birth, or telemetry becomes its own perf problem again.
- *Cross-machine:* the coordination repo stays the hub — snapshot-only commits (review F10), push-on-change debounced, pull floor at minutes not seconds. Raised floor cadence costs ~5 min cross-machine staleness vs 1 — acceptable because push remains the fast path and the floor only covers lost events.
- *Failure mode to price:* if two writers push the same derived snapshot (the dual-substrate trap, §3 platform pre-mortem), push-on-change becomes ping-pong. Derived state must have exactly one materializer per scope — enforced, not assumed.
- **Lost-event prevention (added 2026-08-02, operator round-2 dialogue — corrects the cleanup-oriented framing above to a PREVENTION stack):** lease/ack required on every pushed obligation; write-ahead intent (the emitter logs before acting, not after); open/close brackets as an incremental ledger invariant (every opened obligation must close, checkable without a full replay); per-emitter sequence numbers for gap detection. This layer sits ahead of the anti-entropy floor above — the floor now catches only what still gets lost after prevention, it is no longer the primary defense.

### 4.2 Supervision of any resident process

If any posture keeps a resident component (daemon, or plane units), its supervision contract is the whole game — the pre-mortems show the failure is never the crash, it's the **half-death**:

- **Liveness lies.** Heartbeat-from-the-main-loop stays green while child jobs are dead behind an open circuit breaker. Health must be *output freshness*: RED on any snapshot `generated_at` > TTL or any breaker open > 1 h (invariant 5).
- **Fail-open decays silently.** Stubs falling back to static caps "with loud logging" log into the channel already carrying 1,193 unacked alerts. Every observable *improves* (sessions faster, watchdog green) while enforcement is gone. The counter is context injection (invariant 6): a degradation banner in every session, plus time-boxed fail-open → fail-closed for storm-capable categories (dispatch admission) after 24 h.
- **Watchdog design.** Exactly one recurring scheduled task remains per machine: a deterministic (no-bash) watchdog checking freshness + `/api/health`, kill-and-relaunch on failure. Crash-only process discipline (uncaughtException → flush → exit; RSS watermark self-restart) makes restarts cheap; spool buffering + replay makes them lossless.
- **Cohabitation risk.** Hosting the maintenance plane inside the UI server means UI deploys restart the plane, and Job-Object handle lifetime (KILL_ON_JOB_CLOSE) can turn a routine restart into session kills. If a resident component exists on Windows, it should hold *accounting* Job Objects only for survivable session types. On the Linux plane this whole class dissolves: systemd units + cgroups are the supervisor, per-unit, with none of it hand-built.
- **Cleanup-as-sensor law (added 2026-08-02, operator round-2 dialogue).** Every cleanup logs `{what, why-it-existed, which-prevention-failed}`; a cleanup without a learning record is itself a defect. Weekly aggregation names the top producer for a proactive fix. Cleanup volume trending flat (not falling to zero) is an alarm, not a steady state to accept.
- **Death certificates (added 2026-08-02, operator round-2 dialogue).** The supervisor waits on process handles (kernel-pushed death + exit code) and combines that with write-ahead intent so every death carries a who/what/why; the taxonomy accumulates and the top killer is fixed per cycle. Death causes ranked at synthesis time: self-DoS resource exhaustion (now relieved) > watchdog TERM-kills > operator close/reboot > API cascades > suspended-forever.

### 4.3 Single center vs per-category — where concentration is acceptable

The operator already rejected a mega-dispatcher for **enforcement** (single point of failure in the blocking path). The defensible line, consistent across all three designs:

- **Enforcement stays distributed and fail-open:** 4–5 independent per-category stubs (bash-policy, file-write-policy, dispatch-admission, session-lifecycle, telemetry-emit). One stub's death degrades one category; none can block all work.
- **State/management may concentrate** because its death degrades *freshness*, never blocks: snapshots go stale, edges fall back, work continues. This is the only reason the daemon posture is admissible at all.
- The honest cost of concentration even so: one process hosting six functions fails six at once where six tasks failed one; event-loop discipline (heavy work in timed children) becomes load-bearing and needs a doctor check, not a convention. Per-category systemd units on the plane get the amortization *without* the concentration — a strict dominance unless the plane itself is rejected.

### 4.4 Windows vs WSL2 vs other hardware

| Dimension | Native Windows | WSL2 on desktop | Mac mini / dedicated Linux box |
|---|---|---|---|
| Spawn cost | 132–190 ms (PROVEN) | <0.15 ms (PROVEN) | native-Unix, ~free |
| Defender / Appinfo tax | per-spawn, partially mitigable (exclusions measured 8.5×) | avoided with ext4.vhdx + vmmemWSL exclusions (WSL#8995) | none / different quirks |
| Kernel-pool reboot cycle | active (12.25 GB pool, 5–6-day reboots) | HYPOTHESIZED fixed — refuter retained: pool still bloats post-migration means cause was elsewhere | not applicable |
| Suspended-hook bug #77078 (1.2–5% failure) | exposed | avoided for plane workloads | avoided |
| Thinking-phase latency #41649/#22855 | n/a | **unknown** — bot-closed, never confirmed; gates builder hosting only | instant on native Linux (reported) |
| RAM for fleet width | 64 GB shared | ~48 GB cap of the same box | Linux box is the real destination for 20–30 builders (~4 GB/agent) |
| Ops burden | Task Scheduler wiring repeats per machine | new duty: VHDX one-way disk ratchet (sparseVhd corruption-linked; Optimize-VHD has fresh 2026-07 corruption reports), `wsl --export` backups, Docker Desktop shares the utility-VM budget, OAuth class #20756/#44136 (native client kept as fallback) | launchd vs systemd port, BSD/GNU shims — real but modest |
| Filesystem | shared with edge | **not shared** — every same-machine assumption (worktree salvage, reaper cross-checks, temp handoffs) must be found and re-homed; likeliest overrun source | same, plus network |

**Net:** WSL2 is the cheap 90% for maintenance offload; the dedicated Linux box is the honest destination for builder-fleet width; the Windows edge never gets below ~132 ms/stub, which is why the edge must stay thin (4–5 stubs) regardless of everything else.

---

## 5. Decision points for the operator

These five are genuinely yours (spend, irreversibility, risk appetite, your own ledger). Everything else in §6 I will decide-and-go with a trail per §8.

---

**D1 — Which posture (the shape of the next ~10 builder-sessions).**
Context: three designs above; they are combinable (§3 cross-cutting). "Builder-session" (bs) = one dispatched agent work unit. The hybrid = minimal's invariant fixes + platform's maintenance offload, with the bespoke daemon dropped because systemd provides its mechanisms for free; daemon becomes the fallback if WSL2 is rejected. Full staging in §6.

| Option | What happens | Cost / risk |
|---|---|---|
| minimal | Fix six pathologies in place; substrate untouched | 5–11 bs; ~60% of outcome; class can recur off the fixed list |
| daemon | Resident node service absorbs maintenance; Windows stays the substrate | 8–13 bs; hand-builds supervision; concentration + cohabitation risk |
| platform | Full 3-tier migration incl. builder hosting | 9–14 bs; stall-at-stage-2 risk; #41649 unknown on builder path |
| **hybrid** | §6 path: invariants first, WSL2 maintenance offload second, thin edge third, builder hosting pilot-gated | ~10–13 bs total but stages 0–1 (~4–6 bs) capture the ~90% CPU win; unknowns quarantined |

My pick: **hybrid** — it takes each posture's proven part and gates each unknown behind its own cheap test.
Reply with: `hybrid` (I start §6 stage 0 immediately) · `minimal` / `daemon` / `platform` (I re-plan to that posture) · `discuss` (name the concern).

**RESOLVED 2026-08-02 (Round 3 operator GO, R3.1; build plan `docs/plans/harness-execution-redesign-2026-08.md`):** hybrid, confirmed — WITH zero WSL2 dependency. Honest record: no prior no-WSL decision existed before this date (the pilot had been on-hold pending research, and the research above recommended a gated pilot) — the operator's 2026-08-02c statement decided it outright. Stage 1's maintenance offload uses Windows-native central management (a portable maintenance core with non-overlapping timers by construction, TTL-materialized snapshots, and the platform-neutral doctor verdict cache — scheduled via thin platform adapters, `schtasks` on Windows / `launchd` on darwin, per R3.2) instead of the WSL2/systemd path costed in §3/§4.4/§6; WSL2 remains at most a possible future builder-host experiment, never a harness-mechanism dependency. Full disposition in §6 (restaged).

---

**D2 — Arming the orphan reaper (irreversible kills).**
Context: 98 orphan bash processes accumulated in 136 h (PROVEN); the reaper has run observe-only for weeks. On 2026-08-01 the *worktree* reaper killed an ACTIVE agent's worktree mid-verification — the class has proven teeth. Arming means real `kill` on matched processes; a false positive destroys running work, which is why this is yours.

| Option | What happens | Cost / risk |
|---|---|---|
| arm-conservative | Audit the observe ledger, then arm dead-parent + empty-cmdline classes only, with a liveness/lease check | Small FP risk remains; orphans die within an hour |
| observe-longer | 2 more weeks observe-only, then re-ask | Orphans keep accumulating; near-zero risk |
| never-arm | Rely on plane cgroups/PDEATHSIG once stage 1 ships; Windows-edge orphans reaped manually | Windows edge keeps leaking until stage 2 |

My pick: **arm-conservative** — the ledger audit is the safeguard the worktree incident lacked.
Reply with: `arm` · `observe` · `never`.

(Unaffected by the 2026-08-02 Round 3 directives — R3.6 in §6 reconfirms reaper arming stays gated on this decision, separate from the redesign program.)

---

**D3 — Estate drain scope (your ledger, your asks).**
Context: 1,193 unacked alerts, 127 untriaged nl-issues, 24 doctor reds, 18 stale plans make every doctor pass O(mess) (§1.1 C3). The drain (C0) is a precondition for cheap caching. Bulk-acking risks discarding items that were genuine asks to you; only you know which channels you actually read.

| Option | What happens | Cost / risk |
|---|---|---|
| watermark-ack | Bulk-ack everything before a date watermark; triage only post-watermark items; stale plans get dispositions | ~1–2 bs mechanical; small risk an old genuine ask dies unread |
| full-triage | Every alert/issue individually triaged | Operator-paced, weeks; blocks stage 0 exit |
| ack-all | Zero the ledgers outright | Fastest; guaranteed to eat any live asks |

My pick: **watermark-ack** with watermark = 2026-07-27 (the freeze — everything before it is superseded by this redesign).
Reply with: `watermark` (optionally a different date) · `triage` · `ackall`.

---

**D4 — Builder-hosting pilot abort threshold + hardware trajectory (unrecoverable spend).**
Context: builder sessions moving into WSL2 ride on #41649 (thinking-phase delays, status unknown, §4.4). The pilot A/Bs one workstream for a week instrumenting time-to-first-token (TTFT). The abort path re-homes builders to native-Unix hardware — the Mac mini now, or a dedicated Linux box (a purchase, hence yours).

| Option | What happens | Cost / risk |
|---|---|---|
| pilot-then-decide | Run the pilot; abort if P90 TTFT > 2× native baseline; hardware decision deferred until pilot data | 1 bs + a week calendar; no spend yet |
| skip-to-mac | Skip the WSL2 builder pilot; builders go to the Mac mini directly | Avoids the unknown; pays the launchd port (1–2 bs) sooner; desktop CPU headroom unused |
| buy-box-now | Order the Linux box in parallel with the pilot | Fastest to fleet width; spend before evidence |

My pick: **pilot-then-decide**, threshold P90 TTFT > 2× native → abort. Confirm or reset the threshold — it is the tripwire that spends your money's alternative.
Reply with: `pilot` (optionally your threshold) · `mac` · `buy`.

**CLOSED 2026-08-02 (Round 3 operator GO, R3.1/R3.2):** moot — the builder-hosting pilot this decision gated is cut from the program entirely (R3.1's third bullet: "§6's old stage 4 leaves this program"), and R3.2 takes `buy-box-now` and `skip-to-mac` off the table outright: no new hardware, and darwin support is folded into stage 1 as a portability requirement rather than a later stage or pilot. The TTFT pilot described above never runs under this program.

---

**D5 — Doctor freshness contract (staleness you'll tolerate on the arbiter).**
Context: under every posture, doctor verdicts become cached/materialized (TTL 30 min proposed). A real regression is invisible for up to one TTL; config/wiring changes bust the cache immediately via derived fingerprints (invariant 8), so only slow environmental drift waits. `--no-cache`/`NL_FORCE=1` always forces, and is ledgered (invariant 7). "Keep the doctor GREEN" now means "green as of ≤TTL ago" — your call because the doctor is your constitution-designated arbiter.

| Option | What happens | Cost / risk |
|---|---|---|
| ttl-30m | 30-min TTL, derived fingerprint, bypass ledger | Standard proposal; up to 30-min blind spot on environmental drift |
| ttl-10m | Tighter freshness | 3× cache-miss recompute frequency (cheap only after D3's drain) |
| per-event | Event-invalidated only, no wall-clock TTL | Freshest; any un-declared input becomes a permanent blind spot |

My pick: **ttl-30m** — the fingerprint covers the highest-signal inputs; the ledger keeps the escape hatch honest.
Reply with: `30m` · `10m` · `event`.

**RESOLVED 2026-08-02** as `ttl-30m`, carried into the build plan's closure target; **cold-target re-scoped 2026-08-03** (predecessor build's own architecture review, `docs/reviews/2026-08-03-harness-execution-redesign-REAL-architecture-review.md` Q3 row 1 + F2b — PROVEN: doctor `--quick` measured **9 m 12 s on a clean sandbox**, i.e. the COLD cost is O(repo) — the full ~40-check suite walking every file it touches — not O(mess) as the downstream build plan's original "doctor cold < 2 s post-drain" closure target implicitly assumed by pricing cold cost as if it scaled with the alert/plan backlog D3's drain clears). The freshness contract this decision governs is the CACHED path only, and stands unchanged at `ttl-30m`/<2s-on-a-hit. The COLD path is a separate, previously-unstated target and is RE-SCOPED (DEC-7, `docs/designs/gated-pipeline-master-2026-08-03.md` §3): cached < 2 s remains the closure bar; no fixed cold-path number ships until the top-N slowest `check_*` functions are profiled and a realistic cold target is set from that measurement, not from assumption. Reversal is cheap — reinstate a fixed cold-<2s target if later profiling shows the 9 m 12 s floor was a one-off (e.g. a since-fixed pathological check) rather than structural O(repo) cost.

---

## 6. Recommended staged path

Hybrid, WITHOUT WSL2 (RESOLVED 2026-08-02, Round 3 operator GO — see §5 D1). Every stage independently shippable; every stage's definition-of-done includes deleting its Windows counterpart (invariant 9); rollback at any stage = `Enable-ScheduledTask` (tasks are disabled, never deleted, until the +30-day re-check passes). Closure of the whole effort is outcome-gated (invariant 12): **24 h idle soak, all functions enabled, <15% CPU — measured at close and re-checked +30 days; recurrence auto-reopens the plan.** The build plan implementing this staging is `docs/plans/harness-execution-redesign-2026-08.md`; build proceeds per the orchestrator pattern.

**Success metric (R3.3, added 2026-08-02, Round 3 operator GO):** the redesign's success metric is the inventory counting DOWN, doctor-verifiable — anti-bloat re-affirmed: MODIFY/REPLACE/DELETE, never add.

| Inventory | Now (PROVEN) | Target |
|---|---|---|
| Hooks per Bash call | 25 (21 `Bash` + 4 `Bash\|PowerShell`) | ~5 per-category stubs |
| Scheduled tasks per machine | 6 | 1–2 |
| SessionStart spawns | 16 | 1–2 |
| Total hook budget | uncapped | doctor-enforced cap |

Every new capability must displace a NAMED old one (invariant 9 generalized from stages to every capability). A stage that adds without deleting is not done.

**Stage-0 scope additions (R3.5, added 2026-08-02, Round 3 operator GO):** Stage 0 includes the guidance-contract retrofit of the top-5 blocking gates — scope-enforcement, pre-commit, harness-hygiene, plan-header (plan-edit-validator), concurrent-ownership — structured block messages + `--check` modes, doctor-linted (invariants 13-14, §2); a cost-budget dashboard in the workstreams-ui cockpit (per-mechanism cost × fire-rate vs budget, the inventory counts above live, and the gate-friction metric); and gate-friction telemetry ledgered from the first task onward, so later stages are tuned on data, not intuition.

| Stage | Content | LOE (bs) | Observe-first / exit criterion |
|---|---|---|---|
| **0 — Stop the bleeding + invariants + gate guidance retrofit** | C0 estate drain (per D3) · universal single-flight + doctor recursion guard (in-lib, invariant 4 — kills nested chains today) · SessionStart heavy hooks narrowed to `startup\|clear` matchers · schedule manifest + cadence ≥ 2× cycle check (WARN) · per-Bash hook-count budget (WARN) · HALT/drain wrapper on all ticks · **top-5 gate guidance-contract retrofit + cost-budget dashboard + gate-friction telemetry (R3.5, folded in above)** | 2.5–4 (R3.5 additions carry no revised LOE from the operator — tracked, not yet re-estimated) | Invariant checks run WARN for 1 week before flipping RED (calibration window). Exit: zero nested doctor chains in a 48 h window; CoordSync at PT5M floor with no overlap events. Note: the full derived-fingerprint verdict cache is deliberately NOT built here — stage 1 obsoletes it; only the recursion guard + in-flight short-circuit ship (bloat avoidance) |
| **1 — Windows-native central maintenance** (CORRECTED 2026-08-02, Round 3 operator GO, R3.1 — was "Maintenance offload to the plane" via WSL2/systemd; no-WSL is final, see §5 D1) | A portable maintenance core in bash with non-overlapping timers by construction (IgnoreNew + universal single-flight + cadence ≥ 2× measured cycle, i.e. completion-anchored scheduling) · the 6 tasks become the same core's scheduled units, wired via thin platform adapters (`schtasks` on Windows, `launchd` on darwin — `adapters/claude-code/scripts/ensure-cockpit.sh`'s darwin pattern is the in-repo precedent; darwin support is this stage's portability requirement, not a later stage, per R3.2) · snapshot-builder computes doctor/digest/pressure once per TTL (per D5) into materialized snapshots · output-freshness health (invariant 5) · ONE remaining always-on Windows task: deterministic watchdog · both-substrates-alive doctor RED (invariant 9) | 2–3 (LOE as originally costed for the plane posture; not re-estimated for the Windows-native path by the operator) | 1-week parallel observe; exit: 24 h idle soak <15% CPU with all Windows-native units enabled on every estate machine class (2 Windows + 1 Mac, invariant 10 extended) — **this stage alone still captures the ~90% CPU win; the "immune to #41649" framing is now moot rather than a virtue, since #41649 (a WSL2/builder-hosting risk) no longer applies to any part of this program** |
| **2 — Thin Windows edge** | 4–5 per-category stubs generated from shared templates (edge profile == template, doctor-verified — counters the re-fattening pre-mortem) · SessionStart/resume → one snapshot-cat stub · degradation banner via context injection (invariant 6) · same-commit removal of replaced hooks · exit-0 shim retirement in the same freeze window (coordinate-estate skill) | 2–3 | 7-day observe-first: stubs log would-block vs live gate decisions; any wrong-block on protected-orchestrator traffic or golden-scenario divergence → fallback: stubs source existing gate scripts as in-process functions (keeps most of the spawn win). Exit: per-Bash ~4.1 s → ≤0.5 s measured; block-semantics diff = zero |
| **3 — Lost-event prevention + death certificates + cleanup-as-sensor** (CORRECTED 2026-08-02, Round 3 operator GO, R3.6 — was "Attribution + reaper" via plane cgroups/PDEATHSIG; that mechanism was specific to the now-rejected WSL2 plane) | The prevention stack from §4.1 (lease/ack on every pushed obligation, write-ahead intent, open/close-bracket ledger invariant, per-emitter sequence numbers) · death certificates from §4.2 (process-handle wait + write-ahead intent, ranked death-cause taxonomy, top-killer-fixed-per-cycle) · cleanup-as-sensor law from §4.2 (every cleanup logs {what, why-it-existed, which-prevention-failed}; weekly aggregation names the top producer) | 1–2 (carried from the original stage-3 estimate; the content changed, the LOE band did not get a fresh operator estimate) | Exit: zero un-logged cleanups in a 7-day window; death-certificate taxonomy has ≥1 fixed top-killer per cycle. **Orphan reaper arming is explicitly NOT part of this stage — it stays gated on D2 separately (R3.6), unaffected by this restaging** |
| **4 — Estate-state cleanup + outcome-gated closure** (CORRECTED 2026-08-02, Round 3 operator GO, R3.1/R3.2/R3.6 — replaces the original stages 4 "Builder hosting" and 5 "Second plane," both CUT: the builder-hosting pilot leaves the program entirely per R3.1, and darwin support is absorbed into stage 1 per R3.2 rather than a later stage) | Remaining estate-state cleanup items surfaced by stages 0–3 · the outcome-gate measurement itself: 24 h idle soak, all functions enabled, <15% CPU | 1–2 (unestimated by the operator at Round 3; carried forward from the nearest prior band as a placeholder) | Hard gate: closure requires the measured outcome, re-checked +30 days; recurrence auto-reopens the plan (invariant 12) |

**Total: the LOE bands above are the pre-Round-3 estimates carried forward where a stage's shape survived, and flagged as unestimated where Round 3 replaced the stage's content outright (stages 1, 3, 4) — the operator has not re-priced the corrected staging; re-estimating LOE for stages 1/3/4 under the Windows-native, no-plane shape is an open follow-up, not done here.** The process-chain fixes (§1.2) still ride along structurally: the schedule manifest is the aggregate artifact that never existed (blind spot 4); the budget + cadence checks put the meta-rules on the mechanized rung (the meta-failure); the stage-2 observe-first sweep doubles as the first retroactive regression sweep of the installed base (blind spot 5); and §2's invariant 10 amends the review checklist itself (blind spots 1–3).

**What this path deliberately does not do (CORRECTED 2026-08-02, Round 3 operator GO):** build the bespoke daemon (still rejected, §4.2/§4.3 concentration + cohabitation risk — no longer "systemd supersedes it," since systemd is off the table too; the daemon has no admissible landing zone under this program); use WSL2 anywhere, as a dependency of any harness mechanism, or as anything beyond a possible standalone future exploration (R3.1, final); migrate builders to any non-native-Windows host (the pilot this used to gate, D4, is closed); touch any rule's semantics; or claim the kernel-pool leak is fixed — that stays HYPOTHESIZED with its refuter standing (pool measured before/after stage 1 lands in the pressure snapshot as an early-warning field either way).

**Contingency (CUT 2026-08-02, Round 3 operator GO, R3.1):** the original contingency row ("hidden same-filesystem assumptions — worktree salvage, reaper cross-checks, temp handoffs — surfacing during stages 1–2") is moot now that WSL2 is dropped: there is no edge/plane filesystem split left to hide cross-boundary assumptions across, since stage 1 is Windows-native throughout. No replacement contingency line is proposed here; if Windows-native central management surfaces its own class of hidden assumptions, that is a fresh finding for whoever builds stage 1, not a carry-forward of this one.

**Provenance of the Round-3 corrections above:** the operator's build authorization plus final directives, sourced from the two BINDING entries in `~/.claude/state/nl-issues.jsonl` dated 2026-08-02 ("OPERATOR DECISION 2026-08-02c" and "REDESIGN ROUND 3 — OPERATOR GO 2026-08-02d") and the two REDESIGN-INPUT entries in the same ledger (the round-2 operator dialogue integrated into §4.1/§4.2 above). Where the two rounds were in tension, Round 3 overrides Round 2, which overrides the original synthesis — each override is marked at its point of application above, not narrated separately here.
