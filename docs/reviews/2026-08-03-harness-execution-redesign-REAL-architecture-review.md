# REAL architecture review — harness execution-layer redesign (2026-08)

**Date:** 2026-08-03 · **Reviewer:** architecture-reviewer (fresh dispatch — the first on this design)
**Supersedes:** `docs/reviews/2026-08-02-harness-execution-redesign-architecture-review.md` (an honestly
self-labeled DERIVED record; its provenance section is accurate and its verdict is *mostly* upheld —
but it never ran an independent measurement, never checked the plan's internal consistency, and
never examined the carriage question. Those are exactly where the findings below live.)
**Under review:** `docs/designs/harness-execution-redesign-considerations-2026-08-02.md` (brief +
Addendum + Round 3) · `docs/plans/harness-execution-redesign-2026-08.md` (Tasks 1–3 BUILT and merged:
`e9c5bc0f`, `ce7cca52`, `e5432f3c`) · `docs/designs/accountable-estate-2026-07-27.md` §3b/§6b/§6c ·
`~/.claude/state/nl-issues.jsonl` (binding 2026-08-02a–e entries) ·
`docs/plans/harness-execution-redesign-2026-08-evidence.md` · the built artifacts themselves.

---

VERDICT: **SOUND-WITH-AMENDMENTS** (the shipped Stage 0–1 architecture and the design of record) —
with **NEEDS-RESHAPING verdicts on three specific parts**: (a) the carriage mechanism, which does
not exist and whose absence is the proven root cause of the operator's recurring pain; (b) the
plan's sequencing of the estate drain (last) against its own doctor-is-the-arbiter testing
strategy; (c) Stage 3's scope as specified.

THE ONE THING: **Build the operator-directives register — WITH SUPERSESSION SEMANTICS — and make
its carriage mechanical at three points (plan task text, dispatch prompt, in-session JIT).** The
push-vs-pull violation was not a builder ignoring a directive; the builder was following a
*still-standing contrary law the repo itself teaches* (`neural-lace/workstreams-ui/server/derive-cache.js:7-11`
cites "Law 1 DERIVE-DON'T-MAINTAIN" from `docs/reviews/2026-07-04-observability-design-sketch.md`).
A register without supersession will not fix this. The co-critical second finding: resequence the
estate drain before Stage 2 — the arbiter is currently 71-red and unreadable (F2).

---

## PHASE 0 — Independent derivation (written before reading the proposal in detail)

**Real problem.** Four compounding mechanisms burned the machine for 17 h: guards attached to
wiring not work (resume bypassed `NL_SESSIONSTART_ORIGIN` → 16 nested doctors); O(mess) recompute
on hot paths (doctor `--quick` in minutes when the estate is degraded); cadence < measured cycle
(CoordSync 60 s vs 94–119 s, documented in the same file, never checked); and subprocess-per-poll
UI pull (45 of 93 bash procs). Plus the meta-problem: operator directives live in chat and a
scattered ledger, and are not mechanically present at plan-writing, dispatch, or review — PROVEN
twice in one hour (pull cockpit, then a TTL-cache "fix" that was still pull).

**Forces.** Windows spawn tax 132–190 ms (PROVEN); machine shared with the operator; 2 Windows +
1 Mac, no WSL, no new hardware (binding); anti-bloat binding (inventory DOWN); degraded estate
makes any O(mess) computation expensive; the harness self-modifies, so claims must be
runtime-verified (doctor); mechanism > pattern > memory.

**Invariant (one sentence).** The harness's own upkeep must consume a bounded, budgeted, measured
slice of every machine — with every guard attached to the work itself, every cadence exceeding its
measured cycle, and every binding operator directive mechanically present at the point where a
builder acts — so the machine belongs to the operator by construction, not by discipline.

**My candidate design (3 lines).** (1) One per-machine maintenance actor (single-flight in the
work, HALT, completion-anchored cadence) computing doctor/digest/pressure once per TTL into
snapshot files; all reads O(1). (2) Kill O(mess) at the source: drain the estate FIRST and bound
every checker's cost, doctor-enforced. (3) A one-file directives register, surface-tagged,
mechanically injected at dispatch and at surface-touch, because the proven failure was carriage.
**Sacrifices:** bounded snapshot staleness (must render as stale, never as fresh); a resident
actor needs a watchdog; per-machine reconcile burden.

**DIVERGENCE FROM THE PROPOSAL.** The brief converges with this derivation almost exactly — the
design is substantially RIGHT. Three divergences, and in each the proposal is the one that's wrong:
(1) the plan sequences the drain LAST (task 6) while my derivation and the brief's own §6 Stage 0
("C0 estate drain") put it first — Round 3's restaging silently moved it; (2) the proposal has no
carriage mechanism at all, though its own history is two carriage failures; (3) Stage 3 specifies
a four-mechanism event-integrity suite where the measured evidence supports one class.

---

## LOAD-BEARING PREMISES (tested against the real system)

For this design to be right, ALL of the following must be true:

1. *"The maintenance layer was the load."* → **TRUE** (PROVEN: kill/disable took the machine
   99.9% → ~11%; 45/93 bash procs were pollers; 16 nested doctors).
2. *"Completion-anchored scheduling makes overlap impossible by construction."* → **TRUE** for
   nl-maintenance-managed jobs (`nl-maintenance.sh` re-arms only after `bash <script>` returns;
   schedule-manifest schema v2 documents it) — but only for jobs it manages; `managed_by:
   "external"` entries keep their own risk.
3. *"Doctor cost is O(mess), so the Stage-4 drain makes the cold path fast (<2 s)."* → **FALSE.**
   PROVEN by the Task-3 builder's own measurement: cold `--quick` = **9 m 12 s against a CLEAN
   sandboxed live_home** (evidence file, Task 3). The cold cost is dominated by O(repo) scans,
   not live-estate mess. The closure contract's "doctor `--quick` < 2 s cold post-drain" is a
   target the program's own evidence already disproves. (F2b)
4. *"Doctor GREEN is part of every task's done-bar"* (plan, Testing Strategy). → **FALSE today:**
   the same measured run reports **71 red / 24 warn**. Every task since has shipped against a red
   arbiter; new REDs (cadence, budget, both-substrates) are invisible in a 71-red pile. This is
   the 1,193-unacked-alerts failure — mandatory writes, voluntary reads — reproduced *inside the
   arbiter itself*. (F2a)
5. *"No bespoke resident daemon"* (R3.1; repeated in `nl-maintenance.sh`'s own header). →
   **FALSE as built:** `nl-maintenance.sh --daemon` is a resident 20 s loop, kept alive by a
   schtasks watchdog every 300 s (`install-maintenance-task.ps1:5-8,171-206`). Defensible
   engineering — but it is a resident daemon shipped under a rejected name. (F3)
6. *"Directives reach builders."* → **FALSE** (PROVEN 2×+1: pull cockpit; TTL-cache dispatch;
   and R3.5's "gate-friction telemetry from the first task onward" which Task 1 did not ship —
   `gate_friction.available:false` in the live snapshot, `ws_record` never call-site-wired). (F1, F5)
7. *"Invariant 8: fingerprints derived from per-check declared inputs; doctor REDs a check with
   no declared inputs."* → **PARTIALLY FALSE as built:** `harness-doctor.sh:283-296` says
   "FIRST-APPROXIMATION fingerprint, not true per-check declared-input" — self-flagged, but the
   derived review's own clause ("any invariant waived during build = NEEDS-RESHAPING for that
   stage") is now silently triggered. (F4)

---

## THE OPERATOR'S THREE QUESTIONS

### Q1 — Design, or carriage? **Carriage — and specifically carriage-with-supersession. The design does not need revisiting.**

The push-materialize doctrine the cockpit violated is IN the design of record (brief Addendum
item 1: "push-materialize when reads >> changes") and in the operator's ledger entries. The
design cannot be the defect: it states the rule the build broke.

Where the defect actually lives — traced, in order of causal weight:

1. **A standing contrary law the repo actively teaches** [PROVEN —
   `derive-cache.js:7-11` cites "Law 1 (DERIVE-DON'T-MAINTAIN,
   docs/reviews/2026-07-04-observability-design-sketch.md): the cockpit must never render
   MAINTAINED state as truth"]. The pull cockpit and the TTL-cache dispatch were both *compliant*
   with this July 4 law, which was never rescinded when the operator's doctrine evolved on
   2026-08-02. A builder who greps before building finds the OLD law, cited as law, in the very
   file it would modify. This is why two different actors made the "same mistake" within one
   hour: it was not a mistake in their frame — it was the repo's frame. **Directive supersession,
   not directive existence, is the missing mechanism.**
2. **Plan task text as the carrier** — the plan is what dispatch prompts get built from, and no
   plan task carried "cockpit updates must be push." A directive not in the task text does not
   reach the prompt; a directive not in the prompt does not exist (operator's own formulation,
   2026-08-02e — correct).
3. **Dispatch-prompt construction** — secondary: the orchestrator writing the TTL-cache prompt is
   instance #2 of the same class, not a separate class.
4. **Review gates** — plan-reviewer's Check 17 verified a review RECORD existed; nothing checks
   plan/task text against registered directives.

**The specific artifacts that must change** (this is the Q1 answer, concretely):
- **CREATE `docs/operator-directives.md`** — the register (see the dedicated assessment below for
  its required shape).
- **`~/.claude/templates/plan-template.md`** — a mandatory per-task `Directives:` line (register
  IDs applicable to that task's Files-to-Modify), plan-reviewer-checked.
- **The orchestrator dispatch path** (orchestrator-pattern doctrine + a dispatch lib, not prose) —
  mechanical inlining of the tagged entries' full text into every dispatch prompt.
- **`doctrine-jit.sh` surface matchers** — the session-side belt: register entries injected when a
  builder TOUCHES the tagged surface, which works even when the dispatcher forgot (this is
  invariant 4's own logic — guard in the lib, not the wiring — applied to directives).
- **A one-time supersession sweep**: update `derive-cache.js`'s Law-1 header and mark the
  2026-07-04 review's Law 1 as superseded-for-hot-paths, in the same commit that creates the
  register. Otherwise the repo keeps teaching the violation.

### Q2 — Overengineered? **The shipped core: no. The planned tail: yes. Verdict piece by piece:**

**EARNED against a measured failure (keep, all PROVEN):**
| Mechanism | The measurement that earns it |
|---|---|
| single-flight/recursion lib (Task 1) | 16 concurrent nested doctors; resume bypass |
| cadence ≥ 2× cycle + schedule manifest | CoordSync 60 s declared vs 94–119 s measured |
| per-Bash hook-count budget check | 25 hooks × ~152 ms ≈ 4.1 s per shell command |
| HALT/drain | operator hand-disabled 5 tasks in an emergency |
| SessionStart matcher narrowing | resume fired the full 16-hook chain |
| nl-maintenance consolidation (6 tasks → 1) | six 24/7 wscript→cmd→bash trees (C1) |
| doctor verdict cache | 9 m 12 s cold → 1.56 s hit, measured 355× |
| retire-before-extend + both-substrates RED | exit-0 shims stayed wired for weeks |
| outcome-gated closure + 30-day re-check | 07-24 "shipped" → 07-27 freeze recurrence |
| gate structured messages + `--check` (R3.4, operator GO) | also measured wins: concurrent-ownership 0.551→0.176 s, scope 0.249→0.189 s |
| workaround-as-sensor (operator law) | keep — but wire the call sites; a sensor with no wiring is theater |

**SPECULATIVE WEIGHT — cut or defer (recommendations, each reversible):**
1. **Invariant 8's full form** (per-check declared-input tracking + doctor REDs undeclared
   checks): ~40 checks' input graphs maintained by hand, guarding against a staleness window the
   30-min TTL + output-freshness health already bound. The shipped coarse fingerprint is the
   right call — **amend the invariant text to match it** (explicit, operator-visible descope),
   don't build the full machinery.
2. **JIT pre-warnings (R3.4 item 5)**: adds PostToolUse work to the exact hot path Stage 2 exists
   to thin, keyed to friction telemetry that doesn't exist yet. Defer until post-Stage-2 data
   names the two highest-friction gates.
3. **Stage 3's spec — the center of the overengineering** (see F6): per-emitter sequence numbers
   (no named reader — violates the estate's own telemetry law, §6b "no capture without a named
   consumer at birth"), universal write-ahead intent, bracket-age doctor invariant, and the
   weekly aggregation loops, all deployed against **one** proven loss class. Descope to: lease/ack
   on the proven workstreams launch-ack/done pair + death-certificate fields in nl-maintenance's
   handle-wait (nearly free — the core already waits on its jobs) + cleanup-as-sensor fields on
   the existing janitor log. Defer the rest until a **second measured loss class** exists.
   Saves ~1–1.5 bs and, more importantly, ~600 lines of event-contract lib that every future
   toucher of `workstreams-emit.sh` would have to understand.
4. **Time-boxed fail-open → fail-closed auto-flip (invariant 6, second half)**: introduces a NEW
   surprise-blocking class with no measured incident behind it. Keep the degradation banner
   (earned by the 1,193-unacked proof); drop the auto-flip until observe data justifies it.
5. **Death-certificate weekly "top killer" aggregation + cleanup-trend dashboard surfaces**:
   capture the fields (cheap), skip the reporting machinery until one month of manual reads
   proves anyone consumes it. The 40-untriaged-rot pattern says unread aggregation is self-DoS
   of the improvement loop.

**The honest anti-bloat scorecard today** (R3.3 says success = inventory DOWN): the program so far
is **net +≈14 artifacts, 0 deletions** (2 libs, 2 gate-body splits, sensor lib, core + 2
installers, manifest, runbook, pane + selftest, 2 handoffs; the 5 legacy tasks are disabled, not
deleted — correctly, per rollback policy). Hooks-per-Bash: 25 → 25. SessionStart spawns: 16 → 8.
The DOWN metric rides entirely on Stage 2 landing and the +30-day deletions. That is legitimate
staging — but it means **Stage 2 is the anti-bloat load-bearing stage**, and if it stalls (the
platform pre-mortem's own trap), this program ends net-additive, having built a daemon the
operator rejected by name. Surface the net-artifact delta on the dashboard now so the trend is
checkable, not asserted at close.

### Q3 — What did the missing reviews cost? **~Zero in rebuild; five live landmines, all still cheap.**

Tasks 1–3 are architecturally sound — the builders were unusually honest (self-flagged gaps,
scope-narrowing on the mischaracterized plan-edit-validator dispatch). What a real pre-build
review would have caught, and the fix status:

| # | Defect a review would have caught | Cost if left | Fix now |
|---|---|---|---|
| 1 | Closure target "doctor cold < 2 s post-drain" is disproven by a measurement the plan never took (9 m 12 s on a CLEAN sandbox — cold cost is O(repo), not O(mess)) | Stage 4 fails its own gate forever, or the gate is waived → outcome-gate theater | CHEAP: re-scope the target (cached < 2 s stands; cold target set after profiling the top-N checks) + add a check-cost profiling line to task 6 |
| 2 | Drain sequenced LAST while "doctor GREEN is part of every task's done-bar" — with the doctor at 71-red, every new RED is invisible and every done-bar claim is already false | All Stage 2–3 verification rides an unreadable arbiter; the both-substrates RED and cadence RED will fire unseen | CHEAP: split task 6 — move the drain + doctor-red triage BEFORE Stage 2 |
| 3 | The resident daemon vs R3.1's "no bespoke resident daemon" — never surfaced as a decision; shipped under the euphemism "central management logic" while the file's own header claims R3.1 compliance | Operator discovers a daemon he rejected by name; or a future review flags NEEDS-RESHAPING on the letter of R3.1 | CHEAP: one §3 compact decision block asking ratification (the engineering is defensible: not UI-cohabited, freshness-supervised, avoids a per-minute spawn tree — recommend ratify) |
| 4 | Invariant-8 descope drift (first-approximation fingerprint) — self-flagged by the builder but never ratified as an amendment | The derived review's own terms make Stage 1 NEEDS-RESHAPING; a false mechanism claim stands in the invariant list (§10: theater is the cardinal defect) | CHEAP: amend invariant 8's text to the shipped form + TTL bound |
| 5 | R3.5 "friction telemetry from the first task onward" not in Task 1's deliverables; Task 2's JIT hints depend on data that was never wired (`gate_friction.available:false`) | Stage 2 tunes on intuition, the directive stays violated inside the very plan that carries it — carriage-failure instance #3 | CHEAP: wire `gc_escape_used` call sites + block-event rows before Stage 2 |

Also found in passing, pre-existing: live `~/.claude/settings.json` has two overlapping
empty-matcher SessionStart blocks (filed in nl-issues 2026-08-02T23:25); Task 1's primary outcome
metric (resume ≤ 2 spawns, measured) remains unmeasured and structurally unmet today — a resume
fires the 5-hook empty-matcher SessionStart block (template count verified this review); the live
estate currently has **zero scheduled maintenance at all** (5 legacy tasks disabled AND
`NL-Maintenance` not yet registered) — the current calm partly measures maintenance-off, not
redesign-efficiency, and cross-machine coord-sync is not running. Register the new task promptly
or the anti-entropy floor stays absent.

---

## THE OPERATOR-DIRECTIVES REGISTER — assessment (required item)

**Is one file of id'd directives, mechanically inlined into dispatch prompts and checked at
review, the right minimal mechanism?** Yes — it is the correct mechanism class (a materialized,
single-source register beats chat + scattered ledger entries + brief sections with override
chains, which is today's FOUR stores of one truth). But as proposed it under-specifies four
things, and one of them is the difference between fixing and not fixing the golden case:

1. **Supersession is mandatory, not optional.** The golden case was caused by a never-retired
   contrary law, not a missing statement of the new one (`derive-cache.js` Law-1 header, PROVEN
   above). Each register entry must carry `supersedes:` (register IDs, or named in-repo laws),
   and registering a superseding entry obliges a same-commit sweep of the superseded law's
   in-repo citations. Without this, the register becomes the FIFTH store of directive truth.
2. **Surface tags make applicability computable, not judged.** Each entry carries glob patterns
   (e.g. `workstreams-ui/**`, `hooks/**`, `scripts/*tick*`). Inlining *every* directive into
   *every* prompt reproduces the pattern-rung failure (prose skipped under load); inlining the
   3–5 whose tags match the task's Files-to-Modify is cheap and load-bearing. The tag match is a
   lib computation, not an LLM judgment.
3. **Two injection channels from the one file, belt-and-suspenders per the harness's own
   invariant 4:** dispatch-prompt inlining (covers cloud/hookless sessions, Decision 011) AND
   `doctrine-jit.sh` surface-touch injection (covers the case where the dispatcher is the one who
   forgot — which was instance #2 of the golden case; the orchestrator itself violated the
   directive, so a dispatcher-side-only mechanism guards the wrong entry point).
4. **Entries are complete instructions, not labels** (constitution §2's cold-reader bar, which
   the operator has already extended to asks): each entry ≤ 5 lines = the rule + the golden case
   + the named anti-pattern + the sanctioned alternative. "PUSH not PULL" as a bare label would
   not have stopped the TTL-cache dispatch; "reads ≫ changes ⇒ the writer materializes a
   snapshot at write-time; a timer that re-derives via subprocess is still pull (golden case:
   2026-08-02 cockpit storm)" would have.

**Anti-bloat compliance:** the register must DISPLACE, not add — it absorbs the BINDING entries
in `nl-issues.jsonl` (they get `triage_ref` → register IDs), replaces the brief's round-override
archaeology as the citation target, and retires NEEDS-YOU/ledger duplication of standing
directives. Gate posture: WARN-only (a plan touching a tagged surface without citing the entry),
per §10 — it has its golden scenario (this incident), an expected FP rate to calibrate, and a
retirement condition (zero carriage violations across N plans → demote to review-checklist).

**Simpler alternative considered and rejected:** put directives in the constitution/CLAUDE.md —
fails the always-loaded byte cap and most directives are surface-specific. **Stronger alternative
considered:** a blocking gate — rejected for v1; observe-first is this estate's own proven rule.

---

## PRE-MORTEM — the remaining stages, six months later (written as the incident report)

**Stage 2 (thin stubs).** The cutover shipped 3 of 5 categories, then lost every sprint to other
work. The laptop and the Mac were never reconciled — the additive-only settings sync cannot
propagate REMOVALS (Edge Case 5, known), and the manual reconcile was a runbook step nobody was
forced through. The both-substrates-alive RED fired on day 15 — into a doctor that was still
carrying 60+ reds, where nobody saw it (the drain having been scheduled after Stage 2). The
7-day would-block diff log was written faithfully and read never; a wrong-loose stub shipped, and
the first sign was a scope violation sailing through three weeks later. Per-Bash latency on the
desktop hit 0.4 s; on the laptop it stayed 4.1 s, and the closure claim quietly said "measured on
the primary machine." — **What must change now:** drain/triage the doctor BEFORE Stage 2 (F2);
make the per-machine reconcile a doctor check (live-vs-template hook-count per machine — the
edge-profile check is planned; make it per-machine, not this-machine); give the would-block diff
a named daily surfacing (a dashboard count, not a ledger file); the fallback path ("stubs source
gate scripts in-process") must run each gate's self-test in sourced mode before it is trusted —
sourcing 2,400-line bodies changes set-u/trap/exit semantics.

**Stage 3 (lost-event stack).** As specified: the lib ships four mechanisms; one gets a consumer.
Sequence numbers are written by one emitter and read by nothing (the estate's own telemetry law
violated in its name). The bracket-age doctor invariant fires on every legitimately-long builder
session and joins the red pile. prevention_gap fields get populated with "unknown" boilerplate
because the deterministic janitor cannot actually diagnose which prevention failed. Six months
later event-contract-lib.sh is the scariest file in hooks/lib/ and the weekly taxonomy report
has never once changed anyone's behavior. — **What must change now:** descope per Q2 item 3;
every kept mechanism names its consumer at birth and displaces a named thing (handle-wait
replaces process-table polling — a real deletion).

**Stage 4 (drain + closure).** The drain runs, alerts drop to 50 — and the cold doctor still
takes 8 minutes, because the cost was O(repo) all along (PROVEN in advance, Task-3 evidence). The
soak is run; the pressure snapshot says 9% CPU; the operator's Task Manager says 22% — the
methodology dispute (nl-issues 2026-08-03T03:38, verbatim operator question) was never resolved,
so the closure claim reads as a lie even if it isn't one. The +30-day re-check lands during a
busy week; plan-recheck-sweep.sh reopens the plan; the reopen lands in the unread pile. —
**What must change now:** re-scope the cold-doctor target (F2b); validate the pressure-snapshot
CPU counter side-by-side against Task Manager ONCE, document counter + interval, BEFORE the soak
(F10); the +30-day reopen must land in the guaranteed-read channel (SessionStart digest), not
only the ledger.

---

## FINDINGS (ranked; severity = blast-radius × likelihood × irreversibility)

**F1 [CRITICAL] [premise-testing + second-source-of-truth] [PROVEN — derive-cache.js:7-11,
285, 445; nl-issues 2026-08-02e; R3.5 vs Task-1 evidence]**
Defect: no carriage mechanism for binding directives, AND no supersession mechanism for retired
doctrine — four stores of directive truth (chat, nl-issues, brief round-overrides, plan
assumptions), zero mechanical injection, and the repo still teaching the superseded law in code
comments. Failure scenario: a Stage-2/3 builder greps, finds Law 1 or nothing, violates
push-materialize or anti-bloat a fourth time; the operator catches it again by hand. Silent until
operator-caught; the system does not know. Required change: the register as amended above
(supersession + surface tags + dual-channel injection + complete-instruction entries), plus the
plan-template Directives field and the Law-1 citation sweep — one small plan, ~1 bs.

**F2 [CRITICAL] [Phase-1 measurement + failure-mode-first] [PROVEN — evidence file Task 3: 71 red
/ 24 warn and 9 m 12 s cold on a CLEAN sandbox; plan Testing Strategy line "doctor GREEN is part
of every task's done-bar"]**
(a) The arbiter is unreadable and the plan defers its fix to last — the 1,193-unacked-alerts
failure reproduced inside the doctor; every new invariant RED is invisible; the per-task GREEN
done-bar is false today. (b) The closure target "cold < 2 s post-drain" is disproven by
measurement — the cold path is O(repo). Loud or silent? Silent-by-saturation — the worst kind:
the signal exists and cannot be seen. Required change: split task 6; drain + doctor-red triage
BEFORE Stage 2; re-scope the cold target after profiling; keep cached-under-2s as the standing
contract.

**F3 [HIGH] [reverse-Chesterton + honesty-s1] [PROVEN — nl-maintenance.sh modes header;
install-maintenance-task.ps1:5-8; R3.1 text; the file's own header claiming "no bespoke resident
daemon"]**
Defect: a resident daemon shipped under a rejected name, without the operator decision it
required. The engineering is defensible (standalone bash, not UI-cohabited, freshness-supervised,
avoids per-minute spawn trees) — the process is the defect. Also: NOTHING is currently registered
(legacy disabled, NL-Maintenance not installed) — the estate is running with no anti-entropy
floor at all, and the current calm partly measures maintenance-off. Required change: one compact
decision block: "R3.1 said no resident daemon; the Windows-native fallback needs one because
schtasks cannot fire sub-minute without a spawn tree per fire; ratify the standalone
watchdog-kept bash daemon, or direct pure tick-per-5-min (cost: 60 s-cadence jobs degrade to
5 min)." Then register the task.

**F4 [HIGH] [premise-testing + constitution-10 theater rule] [PROVEN — harness-doctor.sh:283-296]**
Invariant 8 shipped as a first-approximation while the invariant text and the derived review
still claim the full form; by the derived review's own clause this is silent NEEDS-RESHAPING for
Stage 1. Required change: amend the invariant to the shipped mechanism + TTL bound (recommended —
the full form is overweight, Q2 item 1), as an explicit operator-visible amendment.

**F5 [HIGH] [directive-compliance, instance 3] [PROVEN — gate_friction.available:false in the
live snapshot; ws_record un-wired; plan task 2 text depending on task-1 telemetry]**
R3.5's "friction telemetry from the first task onward" did not happen; Stage 2's JIT-hint scope
depends on data that doesn't exist. Required change: wire the call sites before Stage 2; drop
the JIT hints from Stage 2 scope (Q2 item 2).

**F6 [MEDIUM-HIGH] [essential-vs-accidental + telemetry law] [PROVEN class count: one measured
loss class vs four planned mechanisms]**
Stage 3 as specified is the program's speculative-weight center. Required change: descope per Q2
item 3; sequence numbers and universal write-ahead intent wait for a second measured class.

**F7 [MEDIUM] [hot-path cost model] [PROVEN — derive-cache.js:285 (OBS_REFRESH_MS 30 s),
:445 (setInterval refreshAll), server.js:1132]**
The cockpit still re-derives ALL panes via nl.sh subprocesses every 30 s, 24/7, viewers or
none — resident pull load on the named golden-case surface, unaddressed by any task in this plan.
Required change: fold cockpit data production into nl-maintenance snapshots (one materializer per
scope — the brief's own 4.1 rule) or at minimum presence-gate the timer; register entry
push-materialize cites this file as its golden case.

**F8 [MEDIUM] [outcome honesty] [PROVEN — template SessionStart blocks: empty-matcher block = 5
hooks fires on resume; live snapshot sessionstart_spawns = 8; evidence known-gap 1]**
Task 1's primary outcome metric (resume max-2 spawns, measured) is unmeasured and structurally
unmet today. Required change: measure at Stage-2 exit; until then the claim stays open in the
evidence file (it does — keep it that way).

**F9 [MEDIUM] [anti-bloat scorecard] [PROVEN — artifact count this review]**
Net +14 artifacts, 0 deletions so far; hooks-per-Bash 25 to 25. Legal staging, but the DOWN
metric must be live-surfaced (add net-artifact delta to the dashboard) and Stage 2 must be
treated as the program's load-bearing stage, protected from the lose-every-sprint trap.

**F10 [MEDIUM] [operator-trust] [PROVEN — operator-verbatim nl-issues 2026-08-03T03:38]**
The CPU measurement methodology is already disputed; the closure gate rides on it. Required
change: one side-by-side validation of the pressure-snapshot counter vs Task Manager, documented,
before the soak.

**F11 [LOW] [failure-mode-first] [HYPOTHESIZED — refuter: each gate's self-test passing in
sourced mode]**
Stage 2's in-process fallback (sourcing 2,400-line gate bodies) changes exit/trap/set-u
semantics. Required change: sourced-mode self-test runs are part of the fallback's admission.

---

## Steelman

**The cheapest alternative** (Stage 0 alone + leave tasks disabled): the machine stays calm — but
the anti-entropy floor stays off, cross-machine sync stays dead, entropy compounds (the 84-behind
divergence class), and the 4.1 s hook tax remains. Insufficient; rejected on evidence.
**Doing nothing:** disproven by 17 hours at 99.9% CPU. The problem is real and measured.
**The design itself (strongest case):** every stage keys to a PROVEN mechanism from the RCA;
observe-first flips everywhere; disabled-not-deleted rollback; outcome-gated closure with a
recurrence check; builders that self-flag their own gaps. This is — carriage aside — the
best-evidenced harness plan in the repo. My findings are amendments and sequencing, not shape.
**THE CROSSOVER:** the program wins iff Stage 2 lands (inventory actually DOWN) and the arbiter
becomes readable (drain early). If Stage 2 stalls, the program ends net-additive with an
unratified daemon — the platform pre-mortem's stall-at-stage-2 trap, applied to itself. That is
what the resequencing buys down.

## What the current design gets right (and must not lose)

Guard-in-the-lib (unconditional sourcing — the single highest-value fix); completion-anchored
scheduling by construction; observe-first WARN weeks before any RED flip; disabled-not-deleted
rollback with the +30-day gate; atomic tmp+rename snapshots; portable core + thin platform
adapters (the darwin twin tested against a fake launchctl); the evidence file's honesty culture —
builders recording "NOT demonstrated" and "first-approximation" against their own work is the
constitution's rule 1 working as intended, and any process change that discourages it is a
regression.

## WHAT WOULD CHANGE MY VERDICT

- To **SOUND**: register built with supersession + drain resequenced + daemon ratified + invariant-8
  text amended + F5 wiring done. All five are at most ~2 bs combined.
- To **NEEDS-RESHAPING (whole program)**: a fourth carriage violation after the register ships
  (would prove the mechanism class wrong, not just missing); or Stage 2 stalling past one more
  target date with the inventory still net-up (would prove the program is additive in practice
  regardless of law); or the operator rejecting the resident daemon (would reopen Stage 1's
  substrate — pure-tick redesign, ~1–2 bs).
- Evidence that would kill specific findings: a post-drain cold doctor run under 60 s kills F2b's
  profiling half; a second measured lost-event class restores Stage 3's full stack against F6;
  sourced-mode self-tests passing kills F11.
