# MASTER HANDOFF — process integrity + execution redesign (2026-08-03)

**Start a fresh session with this file. It is the single entry point.** Read this, then
`docs/plans/harness-execution-redesign-2026-08.md`, then the two reviews named below.
Prior handoff (still valid for machine state): `docs/handoffs/2026-08-02-stage0-pending-integration.md`.

---

## 0. HARD STOPS — read before doing anything

1. **DO NOT register `NL-Maintenance` on any machine.** Two PROVEN Criticals (F1/F2 below) sit in
   the activation path. They are dormant ONLY because the task was never registered. Verified
   2026-08-03: no `NL-Maintenance` task exists; the five legacy `NL-*` tasks are **Disabled**.
2. **NO WSL dependency** — binding operator decision (2026-08-02c).
3. **No new hardware** — fix-on-Windows; must run on all machines (2 Windows + 1 Mac).
4. The machine is currently calm (~7% CPU) **partly because maintenance is OFF**. That is a truce,
   not a fix. Do not read it as success.

---

## 1. WHERE THE WORK STANDS

**Merged + independently verified** (orchestrator re-ran every self-test; builder claims were not
trusted): Stage 0a `e9c5bc0f` (single-flight lib, SessionStart `startup|clear` narrowing, HALT/drain,
schedule-manifest + cadence check, per-Bash hook budget) · Stage 0b `ce7cca52`+`46826022` (Gate
Philosophy Law on 5 gates via `gate-contract-lib.sh`, `--check` modes, `-body.sh` splits;
concurrent-ownership −68%, scope-enforcement −24%) · `ed32a7b4` (context-watermark: no percentage
when the window is unknown) · `0110fdae` (plan-edit-validator + `workaround-sensor-lib.sh`) ·
`f7f1da33` (escape-hatch sensor call sites wired) · `e5432f3c` Stage 1 (`nl-maintenance.sh`,
both platform installers, **doctor verdict cache: 9m12s → 1.557s**) · `0808f2d9` (cockpit
push conversion: **idle spawns 6-per-30s → 0**; timer demoted to a 5-min anti-entropy floor).

**Live on this machine:** `~/.claude/settings.json` SessionStart reconciled 16 → 8 hooks (duplicate
blocks removed; backup at `settings.json.bak-20260802-reconcile`). Other machines still need this —
the repo→live sync is **additive-only** and cannot remove or narrow.

**Task checkboxes 1 & 2 are NOT flipped** — task-verifier returned INCOMPLETE, correctly. Task 1's
comprehension articulation now exists in the evidence file; Task 2 is genuinely partial.

---

## 2. THE TWO REVIEWS (the load-bearing reading)

- `docs/reviews/2026-08-03-stage0-stage1-harness-review.md` — **REFORMULATE**
- `docs/reviews/2026-08-03-harness-execution-redesign-REAL-architecture-review.md` —
  **SOUND-WITH-AMENDMENTS** (supersedes the earlier *derived* record, which was never a real review)

**F1 (Critical, PROVEN) — the self-DoS reborn inside its own fix.** `run_daemon` calls `run_tick`
in-process; pass 1 sets `_SF_ACTIVE_nl_maintenance_tick=1` and the lib has **no release API**, so
every later pass hits the recursion branch and skips. The daemon ticks ONCE per process lifetime, its
heartbeat permanently stales, and `run_watchdog` (schtasks, 300s) relaunches a NEW daemon **without
killing the old** (`daemon.pid` is written, never read) → unbounded resident-bash accumulation.
Masked because the daemon self-test runs under `SF_DISABLE=1`.

**F2 (Critical, PROVEN) — verdict-cache corruption on the arbiter of truth.** Doctor's sf-skip
`exit 0` emits no verdict; `refresh_doctor_cache` writes `verdict unavailable (exit 0)` over the
fingerprinted entry; on a cache HIT it re-stamps `ts=now` (**staleness laundering** — a wrong GREEN
outliving its TTL) and strips the fingerprint, killing the 1.557s fast path. Two writers, one file,
no schema contract.

**Majors:** F3 sf_guard TTL 120s < doctor's own 9m12s cycle · F4 zero-substrate interim (legacy
disabled, replacement never registered, and the both-substrates check is silent when the activation
marker is absent) · F5 fingerprint covers only 4 mtimes + HEAD (live `~/.claude/hooks/*.sh` drift and
uncommitted edits serve stale verdicts) · **F6 friction-ledger writer/consumer point past each other**
(`workaround-sensor.jsonl`/`bypass_kind` vs `gate-friction/ledger.jsonl`/`event`) — the call-site
builder has since landed, so this is live · F7 both WARN checks have prose-only RED-flip conditions
and the cadence WARN's own remedy cannot clear it · F8 skip/HALT exit-0 aliased to GREEN · F9 Stage-1
mechanisms on master with no `manifest.json` entries.

**THE ONE THING (architecture review):** build the **operator-directives register WITH SUPERSESSION
SEMANTICS**. Load-bearing discovery: the pull cockpit and the TTL-cache dispatch were **not
directive-ignoring — they were compliant with a still-standing contrary law the repo teaches**:
`neural-lace/workstreams-ui/server/derive-cache.js:7–11` cites *"Law 1 DERIVE-DON'T-MAINTAIN"* from
the 2026-07-04 observability review, **never rescinded** when the operator's doctrine flipped to push
on 2026-08-02. Two actors made the "same mistake" in one hour because **in the repo's frame it was not
a mistake**. A register without supersession becomes the fifth store of directive truth and fixes
nothing.

**Overengineering verdict:** shipped core = NOT overengineered (every piece traces to a measurement).
Planned tail = YES. Cut/defer: Stage 3's sequence numbers, universal write-ahead intent, bracket-age
invariant, weekly aggregation ("one proven loss class ≠ a four-mechanism suite"; sequence numbers
violate the estate's own no-capture-without-consumer law); JIT pre-warnings; invariant-6's
fail-open→fail-closed auto-flip; invariant-8's full per-check declared-input machinery.
**Honest scorecard: net +≈14 artifacts, 0 deletions, hooks-per-Bash still 25→25. Anti-bloat has not
started. Stage 2 is the load-bearing stage for it.**

**Also flagged:** the closure target "cold doctor <2s post-drain" is **disproven** by the program's own
9m12s clean-sandbox measurement (cold cost is O(repo), not O(mess)) · the doctor sits at **71 red**, so
every task's "doctor GREEN done-bar" is false today · drain is sequenced last and must move earlier ·
`--daemon` is a resident daemon shipped under a name the operator's Round-3 rejected — needs one-line
ratification · R3.5 friction telemetry never wired (`gate_friction.available:false`).

---

## 3. PROCESS-INTEGRITY DEFECTS (the operator's central concern — diagnosed with evidence)

**D1 — No plan-vs-design fidelity check anywhere.** `plan-reviewer.sh` runs 19 checks, ALL shape
(sections present, no placeholders, 5-field header, behavioral contracts, walking skeleton). It
references `docs/designs` in 2 places and has **zero** content-fidelity checks. Directive/fidelity
references across reviewers: plan-reviewer **0** · harness-reviewer **0** · plan-evidence-reviewer **0**
· architecture-reviewer **1**. A plan can drop every design requirement and pass clean. It did.

**D2 — Check 17 verifies a review is LINKED, not PERFORMED.** A self-labeled *derived* record
(assembled from pre-mortems, explicitly stating no reviewer agent ran) satisfied the blocking gate,
and the orchestrator accepted it and dispatched builders. Same class as outcome-blind closure.

**D3 — Design-doc AUTHORING is ungoverned.** `config/model-policy.json` pins design *reviewing* to
`["fable","opus"]` (architecture-reviewer, systems-designer, ux-designer), but there is **no
design-author agent**. Design docs were written by workflow agents dispatched **without a model pin**,
and the policy states *"Fable is a PREMIUM tier and MUST NEVER be reached by inherit/default — only by
explicit pin."* So design docs could never have been Fable-authored, had no thoroughness template, and
had no reviewer. **This is why the design read as assembled notes rather than a specification.**

**D4 — Append-instead-of-revise.** The considerations brief carries `## Addendum — operator dialogue
round 2` and `## Round 3 revamp` appended to the end; sections 4–6 still hold pre-correction
reasoning. The push directive lived in **"Addendum item 1"**, the plan was written from the body, so
push never reached any task text. **Appending is how a directive becomes invisible while looking
documented.**

**D5 — Directives have no durable identity or supersession** (see THE ONE THING).

---

## 4. THE MASTER PLAN THE OPERATOR ASKED FOR (fold these into ONE plan next session)

Operator explicitly asked: *"Should we just combine all these needs into a single updated master
plan?"* — **Yes.** Consolidate, in this order (process work BEFORE more building — the operator's own
sequencing correction):

**Phase A — unblock + stop the bleeding**
- A1. Fix **F1** (sf_guard release API + watchdog must read/kill `daemon.pid`; delete the
  `SF_DISABLE=1` mask from the daemon self-test so the bug can never hide again).
- A2. Fix **F2** (single writer + schema contract for the verdict cache; no `ts` re-stamping; never
  alias skip/HALT exit-0 to GREEN) and **F5** (widen the fingerprint to live hooks + dirty tree).
- A3. Fix **F6** (reconcile friction-ledger writer/consumer schemas — live defect today).
- A4. Then and only then: register `NL-Maintenance`, re-enable the maintenance layer, measure.

**Phase B — process integrity (the deterministic pipeline)**
- B1. **Operator-directives register with supersession** — `docs/operator-directives.md`,
  surface-tagged, id'd, ≤5-line complete-instruction entries, each able to supersede a prior law.
  One-time sweep of `derive-cache.js`'s Law-1 header. Injected at THREE points: plan task text ·
  dispatch prompt (a dispatch lib inlines tag-matched entries) · `doctrine-jit.sh` at surface-touch.
- B2. **Plan template gains a per-task `Directives:` field**, plan-reviewer-checked (D1).
- B3. **Check 17 upgrade**: the review artifact must name the reviewing AGENT and its verdict, not
  merely exist (D2).
- B4. **`design-author` agent pinned to `["fable","opus"]`** + a design-doc template mandating
  per-decision rationale, explicit non-goals, and a **supersedes:** section (D3).
- B5. **No-addendum lint**: design/plan docs may not carry `Addendum`/`Round N`/`Update:` sections;
  new input must be integrated into the body with a changelog line (D4). **Then integrate the
  existing addenda into the considerations brief's body.**
- B6. **Implement `docs/designs/end-to-end-process.md`** — the operator's step-by-step process audit,
  which "still needs implemented." Requirement from the operator: mechanical/deterministic
  connections between every step **AND a review between every step**. B2/B3 are its first two links.

**Phase C — the anti-bloat stage (makes inventory go DOWN)**
- C1. Stage 2: per-category tool-call stubs — hooks-per-Bash **25 → ~5**.
- C2. Retire what Stage 1 replaced (actually remove the legacy tasks, not merely Disabled).
- C3. Apply the review's cut-list (Stage 3 descope; drop JIT pre-warnings; drop invariant-6 auto-flip).
- C4. Move the **drain + 71-red doctor triage BEFORE** Stage 2 (review's co-critical finding).

**Phase D — the standing operator asks (tracked, not forgotten)**
- D1. **Audit every registered agent for world-class quality** — operator has asked repeatedly.
  Tracked in nl-issues (6 entries) + `docs/backlog.md` + `docs/plans/nl-overhaul-program-2026-07-specs-c.md`.
  Apply the seven-properties bar from `doctrine/artifact-evidence-bar` to each agent; every agent needs
  a GOLDEN CASE. **This is a first-class item, not a someday.**
- D2. Reviewer-agent coverage decision (operator asked; recommendation below).
- D3. Estate drain: 135 nl-issues / 1,254 alerts / 23 stale plans / 10 prunable worktrees — all
  triaged with dispositions in `docs/reviews/2026-08-02-estate-entropy-triage.md`. **All 10 worktrees
  verified safe to prune (zero work at risk).** One downstream-product route fix clears 36% of alerts.

---

## 5. RECOMMENDATION ON REVIEWER AGENTS (operator asked; answer for the record)

**Extend the existing reviewers; add exactly ONE new agent.**

- **Extend `plan-reviewer`** (mechanical, cheap) with the fidelity checks: per-task `Directives:`
  present, cited design's directives referenced, Check-17 names a reviewing agent.
- **Extend `architecture-reviewer`'s remit** to explicitly include "does this design honor every
  applicable registered directive, and does it declare what it supersedes."
- **ADD ONE: `design-author`** (not a reviewer — the missing *authoring* role, D3).

Rationale: the parallelism argument favors many agents, but the failures today were **not** capacity
failures — they were *absent checks* and *absent authorship*. Adding reviewers would not have caught
the push miss; a fidelity check in the reviewer that already runs would have. Fewer, sharper agents
with explicit remits beats a wider fleet — and it matches the anti-bloat directive. Revisit only if
review latency becomes the bottleneck, which it currently is not.

---

## 6. MACHINE / SESSION NOTES

- Context window is **1,000,000 tokens**, not 200K. Context is **never** a reason to stop or hand off
  (memory: `reference_context_window_is_1m_not_200k.md`).
- Mirrors diverge constantly (another machine pushes concurrently). Reconcile with
  `git fetch pt master && git rebase FETCH_HEAD && git push origin master`; `origin` carries TWO push
  URLs. Both reviews are on the work-org mirror at `abfec199`; the personal mirror may lag — re-push to converge.
- `docs/backlog.md` regenerates auto-churn constantly; `git stash push -- docs/backlog.md` before pulls.
- Kernel-pool leak forces a reboot every ~5–6 days (paged pool >10 GB, handles >200k). A reboot before
  the next session is reasonable and loses nothing — all work is committed and pushed.
- Safe orphan sweep (never touches live sessions): kill `bash.exe` whose parent is dead or whose
  command line is empty, age >30s.
