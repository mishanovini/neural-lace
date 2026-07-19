# Continuous-operation (24/7 factory) design sit-down — round 1, 2026-07-19

Operator-initiated design conversation, mid-build of cockpit-roadmap-redesign. This doc is
the durable record (cockpit-ux-design-input.md precedent): operator words verbatim, then the
orchestrator's response + open questions. Outcome seeds a follow-on program plan
(working name: continuous-operation; NOT yet created).

## Operator round 1 (verbatim, 2026-07-19)

> I want to have a system that is always working, building, and making progress 24/7 without
> stopping. It allows me to come in several times a day and provide more guidance, answer
> questions, provide more steering, and keep things continuing to move forward. But what's
> important is that the system never stops making progress. I would like to do some
> collaborative thinking together with you to think about how we modify our current Neural
> Lace system in order to accomplish that. What do we need to improve? What questions do you
> have for me? What challenges do we have that are keeping us from getting there? What
> nuances do we need to consider? I also need to understand what is the best way to manage
> the orchestration of all of that. Is it better to work with one single session that
> orchestrates all the work and all the plans? To what extent can we have multiple plans
> running in parallel? And how do we manage running a whole bunch of things in parallel or
> to maximize the throughput of everything we're building? Could we orchestrate and automate
> the process so that when completing a plan and running into having additional bandwidth
> available, the system could automatically pull new plans from the backlog and start
> working on those? And I also want to make sure we have good observability into everything
> that's happening at the same time. I want to have a good, easy way to see what's currently
> being built, any issues that are coming up, what progress is being made, what's next on
> the list, what all the items are on the road map within the backlog, any questions that
> are waiting on me, what work streams are slowing down or needing anything from me, all
> that fun stuff.
>
> We've had problems many times with build work not getting deployed and getting forgotten
> about and turning into orphaned branches or worktrees. There's been tons of clutter on my
> system because a lot of this stuff is not well tracked. I want to streamline the process
> so that we can build as much as possible in parallel and maximize the progress we're
> making, while also still keeping things cleanly orchestrated and always moving forward and
> never allowing workstreams to fall by the wayside.

Same message, tiering clarification: Fable where actually valuable (design/review/hard
verification), not as a default builder. Recorded in memory
feedback_fable_only_when_real_value (2026-07-19 refinement).

## Orchestrator response — round 1

### The design thesis: the orchestrator is a FILE, not a session

Sessions are mortal — proven three times in the last 48h on this exact program: the NL
Observability session died of context exhaustion mid-integration (work stranded in
worktrees, found only because the operator asked); a reboot killed four builders and a
review batch mid-flight; the "dead" session later REVIVED and raced the replacement
orchestrator (duplicate delta reviews, preserve-commit collisions). Every recovery worked
only because state was on disk (plan files, worktrees, ledger, SCRATCHPAD) — and every
recovery cost 15-30 min of forensic archaeology.

Therefore: continuous operation ≠ a session that never dies. It is (1) durable orchestration
state any fresh session can animate in under a minute, plus (2) a supervisor that guarantees
some session is always animating it, plus (3) work units that survive their owner's death.

### The six components (gap analysis vs what exists)

1. **Orchestrator state manifest** (NEW). One machine-readable file: active plans + wave
   state, in-flight dispatches (agent/branch/worktree/task/TTL), master-integration queue,
   next-up queue, standing directives (tiering, caps). Any fresh session resumes the ROLE
   from it cold. Today this knowledge lives across SCRATCHPAD prose + dispatch markers +
   session memory — this weekend's pickups each took ~20+ min of git forensics.
2. **Supervisor / wake layer** (REDESIGN of session-resumer, disabled by ADR 061 after the
   2026-07-08 spawn cascade). OS scheduled task (reboot-proof) checks every N min: is an
   orchestrator alive AND progressing (state-file mtime, not session existence — a wedged
   context-full session must count as dead)? If not: launch fresh with the standing resume
   prompt. MUST have: single-flight lock (this weekend's two-orchestrator race is the
   golden scenario), spawn-rate limiter + cascade breaker (ADR 061's lesson), and
   context-lifecycle awareness (planned handoff BEFORE exhaustion: rewrite state manifest,
   end session, let supervisor respawn — death on schedule instead of death by surprise).
3. **Mortality-aware work units + the REAPER** (half exists). Every dispatch already gets
   worktree + branch + provenance marker. Missing: the lifecycle end — marker TTL expiry
   triggers auto-triage: unintegrated commits → Inbox item ("orphan work: rehome or
   discard?") or auto-cherry-pick when patch-clean; clean/integrated → purge worktree +
   branch. This deletes the 83-worktree/90-branch pile CLASS (today: 127 of 164 doctor
   reds, plus doctor-runtime blowout that blinded health-tick for 2.5 days). Sweep exists
   (worktree-hygiene-sweep.sh) but is report-only and — irony — is one of the 9 files stuck
   undeployed behind the review-record gate.
4. **Single-writer master integration** (practiced, not enforced). Only the orchestrator
   role merges/pushes master; builders never do. Needs to become a gate, not a habit.
   Deploy-verify belongs to the same leg: "merged" ≠ done until auto-install/install has
   actually shipped it and doctor confirms (today's deploy-theater: 9 merged files silently
   stale-live for 3 days). The redesign's completion oracle (task 1, built today) is the
   render-side of this; the integration leg must consume it.
5. **Backlog auto-pull** (half exists). Backlog digest already tiers rows and escalates
   build-ready ones (7 currently). Missing: the promotion mechanism — when active-plan
   slots < cap and the orchestrator has bandwidth: top build-ready row → plan template →
   autonomous gates (arch/UX review, already autonomous) → build; the promotion lands in
   the Inbox as a VETO-window notification, not a pre-approval (for whichever work classes
   the operator authorizes — Q1 below).
6. **Observability** (IS the active build). The cockpit-roadmap-redesign's three views are
   precisely the asked-for surface: Roadmap (what's being built / progress / what's next /
   backlog), Inbox (questions waiting on operator, context contract), Requests (steering
   ledger), statuses incl. STALLED(why + what-unblocks). One addition to fold in: a
   "factory strip" — orchestrator liveness, active builder count, throughput (tasks landed
   24h), next-up, and the supervisor's last-check stamp — the is-the-factory-running glance.

### Honest challenges (the things that will actually hurt)

- **Verification is the throughput ceiling.** Two-gate rung-3 verify cost ≈ 2-3× build cost
  (correct for foundations — today comprehension-FAIL caught a real spec divergence the
  verifier PASSed). Sustainable 24/7 = risk-tiered verification (rung system exists) +
  pipelined gates (verify N while building N+1 — already practiced today).
- **Windows machine limits.** Process-explosion history (3 reboots); realistic cap ~4-6
  heavy concurrent builders per machine. Throughput scaling beyond that = second machine /
  cloud sessions (coord-sync exists; cloud has restricted .claude per Decision 011).
- **Platform limits.** Usage throttles (429s), Fable quotas, context windows. Pacing policy
  needed: park+scheduled-resume vs model-downgrade-and-continue (Q2).
- **The app itself is a single point of failure.** CCD crashed 2026-07-14; a scheduled-task
  supervisor can relaunch, but this must be designed, not assumed.
- **Operator-attention economy.** Decisions pile up between check-ins; every default must be
  safe-to-proceed + cheap-to-reverse, with the Inbox as the review surface (decide-and-go
  is already constitutional; the Inbox makes the review loop real).
- **Gate ergonomics under autonomy.** Gates that swallow stderr or block whole compound
  commands cost the autonomous loop real time (two examples today); gate UX for
  machine-operators is its own small workstream.

### Orchestration model recommendation (Q4 confirms)

ONE orchestrator role per machine, animated by disposable sessions (supervisor-respawned),
managing MULTIPLE plans: parallelism WITHIN a plan via file-disjoint waves + fragments
(proven today), ACROSS plans when surfaces/repos are disjoint (NL redesign + Circuit P1 can
run concurrently). One master-integration queue per repo. Multiple peer orchestrators only
when a second machine joins (coord-sync makes them visible to each other).

## Open questions for the operator (round 2)

Q1 AUTONOMY ENVELOPE: which work classes may auto-promote from backlog with only a
veto-window Inbox notice, vs requiring your pre-approval? (e.g. harness hygiene/mechanical =
auto; NL features = auto with veto; Circuit/product-facing = pre-approve?)
Q2 THROTTLE POLICY: when limits hit mid-build — park and self-resume later (slower, full
quality) or downgrade model and keep moving (faster, weaker)? Default proposal: park for
builders, downgrade only for mechanical sweeps.
Q3 CHECK-IN CONTRACT: should anything HOLD for your daily windows (e.g. product-visible
deploys), or truly never wait? Default proposal: never wait; everything reversible ships,
the Inbox carries the review trail.
Q4 SCOPE: one machine first (this one), or design the supervisor for desktop+laptop+cloud
from day one? Default proposal: single-machine skeleton first, coord-sync peers next.
Q5 SUPERVISOR REVIVAL: ADR 061 disabled session-resumer after the spawn cascade. OK to
supersede 061 with the redesigned supervisor (single-flight + rate-limited + progress-based
liveness), or does 061 stand as a harder constraint? 

## Disposition

Next: operator answers fold here as round 2 → program plan drafted (Fable) → arch review →
build. The redesign build continues in parallel throughout; nothing here blocks it.
