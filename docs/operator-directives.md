# Operator Directives Register

<!-- GENERATED FILE — do not hand-edit. Regenerate with:
       bash adapters/claude-code/scripts/gen-directives-view.sh
     Source of truth: adapters/claude-code/config/operator-directives.json.
     Consumed at runtime by hooks/lib/directives-register-lib.sh (Check 21,
     scripts/dispatch-directives.sh, doctrine-jit.sh's register walk). This
     file is the human-readable view only — never the canonical store. -->

Canonical store for standing BINDING operator directives (DEC-3,
docs/designs/gated-pipeline-master-2026-08-03.md §4). New standing rules
enter here with a fresh `OD-NNN` id, never by appending to this file
directly — the no-addendum rule (REQ-B10) applies to the JSON source, and
this view is regenerated, not edited.

## Summary

| Metric | Count |
|---|---|
| Total entries | 23 |
| BINDING | 23 |
| SUPERSEDED | 0 |
| Operator-only (no code surface) | 2 |

## Entries

### OD-001 — no-wsl-dependency

**Status:** BINDING

**Surfaces:**
- `adapters/claude-code/scripts/nl-maintenance.sh`
- `adapters/claude-code/scripts/install-maintenance-task*.ps1`
- `adapters/claude-code/scripts/*maintenance*`
- `docs/designs/**`
- `docs/plans/**`

**Instruction:**

> Rule: no WSL2 dependency anywhere in the harness/maintenance layer; WSL2 remains only a possible FUTURE builder-host experiment, never a dependency.
> Golden case: 2026-08-02c -- WSL2 systemd offload was under consideration for Stage-1 maintenance and was ruled out.
> Anti-pattern: a mechanism whose only viable host is WSL2 (e.g. requiring systemd unit files).
> Sanctioned alternative: Windows-native central management -- portable bash + thin per-platform adapters (schtasks/launchd), IgnoreNew+single-flight+cadence>=2x-cycle timers.

*Source: nl-issue:153 (2026-08-02c)*

### OD-002 — anti-bloat-modify-not-add

**Status:** BINDING

**Surfaces:**
- `adapters/claude-code/hooks/**`
- `adapters/claude-code/scripts/**`
- `adapters/claude-code/agents/**`
- `docs/plans/**`
- `docs/designs/**`

**Instruction:**

> Rule: every addition must MODIFY/REPLACE/DELETE an existing thing, not just add; success = inventory counts DOWN (hooks-per-Bash, scheduled tasks, SessionStart spawns).
> Golden case: 2026-08-02c targets (25->~5, 6->1-2, 16->1-2); honest scorecard at the time showed net +~14 artifacts, 0 deletions.
> Anti-pattern: shipping a new gate/hook/script without naming what it displaces or retires.
> Sanctioned alternative: name the displaced mechanism in the same commit (anti-bloat ledger, design SS7 precedent); retire-before-extend.

*Source: nl-issue:153 (2026-08-02c)*

### OD-003 — no-new-hardware

**Status:** BINDING

**Surfaces:**
- `adapters/claude-code/scripts/*maintenance*`
- `adapters/claude-code/scripts/install-*`
- `docs/designs/**`
- `docs/plans/**`

**Instruction:**

> Rule: no new hardware; fix-on-Windows is the bet; every mechanism must run well on ALL current machines (2 Windows + 1 Mac).
> Golden case: 2026-08-02d round-3 GO.
> Anti-pattern: a mechanism that only works on one machine's OS/hardware profile.
> Sanctioned alternative: portable bash + thin per-platform adapters (schtasks/launchd; ensure-cockpit darwin pattern is the precedent); every mechanism carries per-platform cost lines.

*Source: nl-issue:154 (2026-08-02d)*

### OD-004 — gate-philosophy-complete-instruction

**Status:** BINDING

**Surfaces:**
- `adapters/claude-code/hooks/*gate*.sh`
- `adapters/claude-code/hooks/lib/gate-contract-lib.sh`

**Instruction:**

> Rule: gates never block silently. Every block message is a complete instruction: WHAT fired, WHY, exact FIX command/path, sanctioned ESCAPE with cost. Gates gain --check pre-flight modes.
> Golden case: 2026-08-02d; scope-enforcement-gate's four-field message is the gold standard.
> Anti-pattern: a bare exit-nonzero with no fields, or a warning an agent must reverse-engineer.
> Sanctioned alternative: gate-contract-lib.sh's {WHAT/WHY/FIX/ESCAPE} emission + --check mode (shipped Stage 0b); gate quality metric = blocks/day x workaround-rate.

*Source: nl-issue:154 (2026-08-02d)*

### OD-005 — workaround-as-sensor

**Status:** BINDING

**Surfaces:**
- `adapters/claude-code/hooks/*gate*.sh`
- `adapters/claude-code/hooks/lib/workaround-sensor-lib.sh`

**Instruction:**

> Rule: every bypass/workaround/escape attempt is ledgered. A gate that generates workarounds is itself a defective gate, auto-filed for redesign.
> Golden case: 2026-08-02d.
> Anti-pattern: an escape hatch (--no-verify, env override) used silently with no record.
> Sanctioned alternative: workaround-sensor-lib.sh call sites (ws_record / gc_escape_used) at every escape path.

*Source: nl-issue:154 (2026-08-02d)*

### OD-006 — push-over-pull-push-materialize

**Status:** BINDING

**Surfaces:**
- `neural-lace/workstreams-ui/**`
- `adapters/claude-code/scripts/nl-maintenance.sh`
- `docs/designs/**`

**Supersedes:**
- the 2026-07-04 observability review's (docs/reviews/2026-07-04-observability-design-sketch.md) 'refreshes on a timer' reading as applied to hot paths -- named in-repo law, hot-path scope ONLY; Law 1 (derive-from-oracle, same document lines 6-11) is UNCHANGED and stays law -- deriving and pushing are orthogonal (P-42)

**Instruction:**

> Rule: push over pull wherever practical -- push-materialize when reads >> changes; pull-on-demand only when changes >> reads (pull stays a valid anti-entropy floor, never the default on a hot path).
> Golden case: 2026-08-02e -- the cockpit rebuilt pull-based (subprocess polling) caused the 100%-CPU storm; the first FIX proposal (a TTL cache) was STILL pull, corrected mid-flight twice in one hour.
> Anti-pattern: a 'refreshes on a timer' / shorter-interval-polling fix presented as the solution to a push-vs-pull defect -- same defect, slower.
> Sanctioned alternative: fs-watch + debounce (S-12 precedent) or an explicit push notification triggering a re-derive from the oracle (Law 1 unaffected).

*Source: nl-issue:158 (2026-08-02e)*

### OD-007 — cleanup-and-prevention-as-sensor

**Status:** BINDING

**Surfaces:**
- `adapters/claude-code/scripts/nl-maintenance.sh`
- `adapters/claude-code/hooks/**`

**Instruction:**

> Rule: prevention over cleanup as standing posture; when cleanup is still needed, every cleanup logs {what, why it existed, which prevention failed} -- a cleanup without a learning record is itself a defect.
> Golden case: repeated orphan/zombie cleanups (P-12/P-13) with no learning record.
> Anti-pattern: killing orphaned processes / deleting stale files with no record of why they existed or what should have prevented them.
> Sanctioned alternative: cleanup-as-sensor fields at the janitor log's write site (REQ-C5 minimal form); weekly aggregation once a second measured loss class justifies it (DEC-8).

*Source: docs/handoffs/2026-08-03-EXHAUSTIVE-issue-inventory.md Part 4*

### OD-008 — concurrency-pressure-based-admission

**Status:** BINDING

**Surfaces:**
- `adapters/claude-code/doctrine/orchestrator-pattern.md`
- `docs/plans/**`

**Instruction:**

> Rule: prefer pressure-based admission over fixed hard concurrency caps; never handicap productive work just to bound counts.
> Golden case: the 80-minute freeze (P-23) was UNBOUNDED dispatch, not parallelism itself.
> Anti-pattern: an arbitrary fixed concurrency ceiling that throttles genuinely ready, file-disjoint work.
> Sanctioned alternative: capacity/pressure-based admission (headroom, ready-frontier computation) bounding rate and total concurrency, not a static per-plan cap.

*Source: docs/handoffs/2026-08-03-EXHAUSTIVE-issue-inventory.md Part 4*

### OD-009 — graceful-stop-drain

**Status:** BINDING

**Surfaces:**
- `adapters/claude-code/hooks/lib/single-flight-lib.sh`
- `adapters/claude-code/scripts/nl-maintenance.sh`

**Instruction:**

> Rule: stopping/blocking/killing must be graceful and must never impede real progress: deny-new -> drain flag at safe boundaries -> force-kill only provably-orphaned processes.
> Golden case: P-21 -- no drain mode; a reboot warning still let ~20 min of new work get dispatched into it.
> Anti-pattern: hard-killing live work to satisfy a stop request, or dispatching new work after a stop signal.
> Sanctioned alternative: the HALT/drain flag (S-03) checked at dispatch boundaries; force-kill reserved for the reaper's allowlisted, two-strike, provably-orphaned population.

*Source: docs/handoffs/2026-08-03-EXHAUSTIVE-issue-inventory.md Part 4*

### OD-010 — disposition-everything

**Status:** BINDING

**Surfaces:**
- `docs/backlog.md`
- `NEEDS-YOU.md`
- `docs/plans/**`

**Instruction:**

> Rule: ignored != unimportant. Every backlog/issue/plan item gets an explicit disposition (fix/retire/waiver/supersede); nothing is silently discarded for age.
> Golden case: P-35 -- 56 open NEEDS-YOU, 135 untriaged nl-issues, 1,254 unacked alerts, 23 stale ACTIVE plans.
> Anti-pattern: closing a session and leaving an old item to age out unmentioned.
> Sanctioned alternative: the estate-drain disposition sweep (REQ-C2); one disposition line per item, never silent removal.

*Source: docs/handoffs/2026-08-03-EXHAUSTIVE-issue-inventory.md Part 4*

### OD-011 — agent-world-class-standard

**Status:** BINDING

**Surfaces:**
- `adapters/claude-code/agents/**`

**Instruction:**

> Rule: every agent must be explicitly designed to be world-class at its ONE job; a generalist spread across multiple transitions is not acceptable.
> Golden case: D-15.2 / D-16; this design's own two new agents (design-author, plan-fidelity-reviewer) each get a single-transition remit and a GOLDEN CASE fixture.
> Anti-pattern: widening an existing reviewer's remit to cover a new transition 'since it's already there' instead of scoping a dedicated reviewer.
> Sanctioned alternative: harness-reviewer is instructed, in each agent file's own header, to enforce the one-job sentence on any edit to that agent.

*Source: docs/handoffs/2026-08-03-EXHAUSTIVE-issue-inventory.md Part 4*

### OD-012 — standing-autonomy-reversible-work

**Status:** BINDING

**Surfaces:**
- `docs/plans/**`

**Instruction:**

> Rule: standing autonomy on reversible work is granted; stop asking permission on it -- surface only genuinely irreversible or business-judgment calls.
> Golden case: D-17; already codified as ~/.claude/rules/constitution.md SS8 (Keep Going Is The Default) -- this entry is the register's pointer to that binding text, not a competing copy.
> Anti-pattern: a permission-seeking pause ('shall I continue?') on a one-revert-away decision.
> Sanctioned alternative: decide-and-go with a Decisions Log trail (constitution SS8); pause only for the irreversibility bar named there.

*Source: docs/handoffs/2026-08-03-EXHAUSTIVE-issue-inventory.md Part 4*

### OD-013 — maximize-parallelization

**Status:** BINDING

**Surfaces:**
- `adapters/claude-code/doctrine/orchestrator-pattern.md`
- `docs/plans/**`

**Instruction:**

> Rule: maximize parallelization of dispatchable work without overburdening compute; keep the pipeline full.
> Golden case: P-24 -- file-disjoint work run serially by habit because nothing computed the ready frontier.
> Anti-pattern: dispatching one task at a time 'to be safe' when multiple are file-disjoint and dispatchable now.
> Sanctioned alternative: compute the ready frontier (deps-done AND file-disjoint AND headroom) and dispatch it in full, bounded by OD-008's admission posture.

*Source: docs/handoffs/2026-08-03-EXHAUSTIVE-issue-inventory.md Part 4*

### OD-014 — sessions-247-with-headroom

**Status:** BINDING

**Surfaces:**
- `adapters/claude-code/doctrine/automation-modes.md`

**Instruction:**

> Rule: sessions should run 24/7 with headroom preserved for interactive use.
> Golden case: D-19.
> Anti-pattern: saturating all compute with background dispatch such that an interactive session stalls.
> Sanctioned alternative: headroom-aware admission (ties to OD-008); presence-aware widening overnight (S-25, not yet built, named residual).

*Source: docs/handoffs/2026-08-03-EXHAUSTIVE-issue-inventory.md Part 4*

### OD-015 — measure-real-loe-at-plan-time

**Status:** BINDING

**Surfaces:**
- `adapters/claude-code/templates/plan-template.md`
- `docs/plans/**`

**Instruction:**

> Rule: measure real build cost (LOE) and surface it at plan time; flag tasks whose effort is disproportionate.
> Golden case: D-20; reference-class forecasting shipped (163 plans mined, prior cycle T7).
> Anti-pattern: a plan task with no LOE estimate, or an estimate never checked against the mined reference class.
> Sanctioned alternative: the reference-class LOE tool at plan-authoring time; flag outliers before dispatch, not after.

*Source: docs/handoffs/2026-08-03-EXHAUSTIVE-issue-inventory.md Part 4*

### OD-016 — observability-equal-clarity

**Status:** BINDING

**Surfaces:**
- `NEEDS-YOU.md`
- `adapters/claude-code/scripts/nl-maintenance.sh`

**Instruction:**

> Rule: observability must be equally clear to human and AI; accountability transparent; nothing waits on the operator and gets silently forgotten.
> Golden case: D-21; P-35's ask-rot (56 open NEEDS-YOU items).
> Anti-pattern: a blocker visible only in an agent's private reasoning/context, never surfaced to a durable, human-readable location.
> Sanctioned alternative: NEEDS-YOU.md as the awaiting-operator ledger (constitution SS2/SS3); the dashboard friction pane (REQ-A3) as the machine-observable counterpart.

*Source: docs/handoffs/2026-08-03-EXHAUSTIVE-issue-inventory.md Part 4*

### OD-017 — self-learning-closed-loop

**Status:** BINDING

**Surfaces:**
- `docs/reviews/**`
- `docs/lessons/**`

**Instruction:**

> Rule: identify problems as they occur, root-cause them, then design -> document -> fix -- the closed loop, not just the diff.
> Golden case: D-23; P-36 -- outcome-blind closure (closures true about artifacts, false about whether the problem was solved).
> Anti-pattern: closing a task on 'the code changed' without checking whether the originating problem is actually gone.
> Sanctioned alternative: the harness-lesson / why-slipped skills; a closure names the mechanism preventing recurrence, not just the diff.

*Source: docs/handoffs/2026-08-03-EXHAUSTIVE-issue-inventory.md Part 4*

### OD-018 — incentive-by-design-cheapest-path

**Status:** BINDING

**Surfaces:**
- `adapters/claude-code/hooks/**`

**Instruction:**

> Rule: make the right way the cheapest way -- the compliant path must cost less than the workaround, not more.
> Golden case: 2026-08-02d; Read/Grep/Glob's zero-hook precedent (no PreToolUse cost) is the model to extend to batched commands + pre-declared scope.
> Anti-pattern: a compliant path that is slower/costlier than bypassing the gate, which manufactures the workaround OD-005 exists to catch.
> Sanctioned alternative: price every new gate's compliant path against its bypass cost before shipping; --check pre-flight modes lower the compliant-path cost directly.

*Source: nl-issue:154 (2026-08-02d, 'INCENTIVE-BY-DESIGN' clause -- no Part-4 D-id, sourced directly from the nl-issue)*

### OD-019 — branch-protection-work-org-mirror (OPERATOR-ONLY)

**Status:** BINDING

**Surfaces:** none (operator-only — no code surface an agent can act on)

**Instruction:**

> Rule: server-side branch protection on the work-org mirror is an operator-only step; no agent mechanism substitutes for it.
> Golden case: S-34; Decision 064's primary mechanism was never enabled; mirrors have diverged 3+ times (P-28).
> Anti-pattern: an agent 'fixing' mirror divergence with more merge automation instead of the operator enabling protection.
> Sanctioned alternative: operator enables branch protection on the work-org remote directly; this entry stands as the tracked register item until done.

*Source: docs/handoffs/2026-08-03-EXHAUSTIVE-issue-inventory.md Part 5 (S-34)*

### OD-020 — cowork-policy-registry-key (OPERATOR-ONLY)

**Status:** BINDING

**Surfaces:** none (operator-only — no code surface an agent can act on)

**Instruction:**

> Rule: the Cowork VM policy registry key (HKLM\SOFTWARE\Policies\Claude -> secureVmFeaturesEnabled=0) is an operator-only step; no agent can set HKLM policy keys.
> Golden case: S-35; CoworkVMService (P-15) holds MSIX package files and costs ~1.8GB RAM + ~10GB disk while unwanted.
> Anti-pattern: an agent attempting Set-Service/sc config on the packaged service (returns Access Denied) instead of flagging the registry-key step.
> Sanctioned alternative: operator sets the policy key directly (elevated); Stop-Service remains the agent-safe interim mitigation.

*Source: docs/handoffs/2026-08-03-EXHAUSTIVE-issue-inventory.md Part 5 (S-35)*

### OD-021 — ci-is-read-mandatory

**Status:** BINDING

**Surfaces:**
- `.github/workflows/*`
- `adapters/claude-code/doctrine/git*`
- `adapters/claude-code/doctrine/orchestrator-pattern*`

**Instruction:**

> Every push is followed by a CI-result check for the pushed SHA (gh run list / gh run watch); red CI on the default branch is stop-and-fix, never background noise. Golden case: 2026-08-03, two workflows red on ~23 consecutive master pushes while sessions kept pushing (25+ unread failure emails). Anti-pattern: logging Required-status-check output as trivia. Sanctioned alternative: a genuinely environment-bound red goes into the workflow allowlist WITH a tracking reference (KNOWN_FAILING_HOOKS convention), never a silent skip.

*Source: operator directive 2026-08-03 (session 4a470c8c) + backlog CI-RESULT-CONSUMPTION-GAP-2026-08-03-01*

### OD-022 — merge-verify-mechanization

**Status:** BINDING

**Surfaces:**
- `adapters/claude-code/hooks/dispatch-chain-gate.sh`
- `adapters/claude-code/hooks/workstreams-emit.sh`
- `adapters/claude-code/hooks/stop-verdict-dispatcher.sh`
- `adapters/claude-code/hooks/lib/review-chain-lib.sh`
- `docs/plans/*.md`

**Instruction:**

> Rule: operator, verbatim (2026-08-03): "You were given explicit direction to mechanize verification of every build. ... I do not want you deciding that it's OK to tolerate so many build processes just sitting unverified. We need to clean up the mess as we go. We want the system to be continuously getting cleaner as it builds, not messier." The build->verified transition is mechanical and present-moment: an obligation is open when a builder-complete ledger row has no matching verifier-complete row for that task.
> Golden case: this plan's own build -- 11 tasks merged, 0 verified for hours, operator flagged the accumulation twice (cockpit chips) before issuing this directive.
> Anti-pattern: an orchestrator or builder session treating "I'll verify later" or "the queue will clear eventually" as an acceptable steady state instead of a temporary backlog that must actively shrink.
> Sanctioned alternative: dispatch task-verifier for each open obligation before dispatching more builders on the same plan, or name every open obligation explicitly in the session's terminal marker; a ledgered waiver with a named reason is the only other escape.

*Source: docs/plans/gated-pipeline-master-2026-08.md Task 25 (operator directive 2026-08-03, session 4a470c8c) + backlog AUTO-VERIFY-DISPATCH-2026-08-03 (absorbed, row deleted same commit)*

### OD-023 — task-id-determinism

**Status:** BINDING

**Surfaces:**
- `adapters/claude-code/hooks/workstreams-emit.sh`
- `adapters/claude-code/hooks/lib/review-chain-lib.sh`
- `adapters/claude-code/hooks/lib/directives-register-lib.sh`
- `docs/plans/*.md`

**Instruction:**

> Rule: operator, verbatim (2026-08-03): "Management of task IDs and everything here regarding standard processes that are supposed to be practiced all the time need to be deterministic as much as reasonably possible. We do not want to provide any more opportunity than is absolutely necessary for any Claude agent to either make mistakes or not follow the process. Claude should never have to wonder what the right thing to call something is or have any difficulty identifying something."
> Golden case: the 2026-08-03 attribution incident -- an orchestrator hand-typed task=T7-style ids into an NL-ATTRIBUTION header while the plan's own task ids are numeric, so the cockpit could not attribute the live work.
> Anti-pattern: a naming/id convention documented only in prose, left for each dispatching session to reconstruct from memory or free-text scraping.
> Sanctioned alternative: a mechanical check that validates the id against the one real source of truth (the plan's own task list) at the moment it is recorded, loud on mismatch, never silently guessing or normalizing away the mistake at the write site (normalization is a READER-side defense, per rc_open_verify_obligations -- the WRITE site's job is to say so, not to fix it quietly).

*Source: operator directive 2026-08-03 (session 4a470c8c, mid-build on docs/plans/gated-pipeline-master-2026-08.md Task 25)*

