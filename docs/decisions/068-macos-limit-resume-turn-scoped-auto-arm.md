# 068 — limit-resume watchdog: turn-scoped auto-arm, reconciled against FM-037/ADR-061

**Date:** 2026-07-30
**Status:** DECIDED and BUILT, POST-REVIEW REVISED. `harness-reviewer` returned REJECT
on the first build (3 Critical + 4 Major findings, all PROVEN via independent probes —
see "Post-review revision" below); every finding is fixed in the version this decision
now describes. A second `harness-reviewer` pass is the current verdict of record (see
the session's completion report for its outcome).
**Tier:** 1 (reversible — `rm ~/Library/LaunchAgents/local.neurallace.limit-resume.plist`
+ `launchctl bootout gui/$UID/local.neurallace.limit-resume` + revert the hook splices;
no data surgery, no third parties, no unrecoverable spend)
**Operator directive (verbatim, 2026-07-30):** "I'm guessing you're still not
retriggering yourself after the limits reset. How do we make that actually work?"

## Problem (cold-read context)

The machine-local, hand-made predecessor
(`~/.claude/state/limit-resume/resume.sh` + a LaunchAgent, never committed to this
repo) had three diagnosed defects: (1) launchd's PATH lacked Homebrew so `env node`
failed on every tick — patched, but unproven in production (the log's last failure
timestamp predates the fix by timezone, not by having actually re-run since); (2)
arming required a manual `touch` — the moment a usage limit actually kills a session
is exactly the moment nobody is present to arm it, so the watchdog had structurally
never been able to fire on its own; (3) a hardcoded session id and a stale workflow
id baked into the resume prompt, usable for exactly one session ever.

Fixing (2) means the marker must arm itself automatically. That is a genuine
departure from two pieces of prior art already in this repo, and this decision
exists to reconcile it with both, on the record, rather than silently drifting past
them.

## Prior art this must be reconciled against

1. **FM-037** (`docs/failure-modes.md`) — the spawn-cascade incident that crashed
   the operator's machine. Its prevention item 3: "Any such spawning script should
   default to inert/shadow/dry-run behavior until an explicit, durable,
   file-presence-based opt-in marker exists — 'the script runs live the moment
   something calls it' is the wrong default for anything that can spawn further
   automation."
2. **ADR-061** (`docs/decisions/061-session-continuity-supervision.md`) —
   `scripts/session-resumer.sh`, the existing (Windows-only, `claude`-spawning)
   session-continuity supervisor. Its safety invariant #2, verbatim: "No
   auto-arming: the armed-marker gate, its shadow default, and the operator-opt-in +
   kill-drill requirement are unchanged; this ADR ships nothing armed." That
   supervisor remains deliberately, permanently unarmed pending a Phase 2 the
   operator has not authorized.

Building an auto-arming mechanism the same week ADR-061 recorded "no auto-arming"
as a hard-won safety lesson is exactly the kind of drift this file exists to make
visible rather than silent.

## Why this mechanism is not a violation of that lesson

`session-resumer.sh` is a **multi-session heartbeat sweep**: one pass can examine
every session on the machine and (bounded, but still) spawn a resume for whichever
ones look stale. FM-037's actual failure was unbounded classification work plus an
unanchored death-signature regex, not "arming" in the abstract — but the ADR's
authors chose the more conservative invariant (no auto-arm at all) precisely because
a sweep's blast radius is hard to reason about tightly.

`scripts/limit-resume.sh` is structurally different in the ways that matter for that
same reasoning:

| Property | session-resumer.sh (ADR-061) | limit-resume.sh (this decision, POST-REVIEW) |
|---|---|---|
| Scope | every session on the machine | exactly one session per tracked marker — state keyed per session id under `armed/<key>.*`, never a machine-global slot (F3 fix) |
| Liveness discriminator before spawning | `hb_classify` (heartbeat + transcript-mtime-aware; a mid-turn session reads as `live` even though its own heartbeat looks stale) | **REUSES THE SAME `hb_classify`** — sourced from `hooks/lib/session-heartbeat-lib.sh`, identical call. A `live` verdict blocks the attempt (F1 fix) |
| Initial cooldown floor (never race the CLI's own retry) | 30-minute floor, D4 | **SAME NUMBER, same reasoning** — `LIMIT_RESUME_MIN_SILENCE_SECONDS` defaults to 1800s (F6 fix) |
| Concurrency | a per-tick live-spawn ceiling of 1, across a sweep | mkdir lock; at most one real spawn per tick even with multiple tracked sessions (unchanged, always correct) |
| Machine-wide live-process breaker (FM-037 prevention item 2) | yes (`RESUMER_MAX_LIVE_PROCESSES`) | NOT separately implemented — the single global mkdir lock already caps this mechanism's OWN concurrent spawns at 1, which is the property item 2 actually requires ("an independent hard spawn breaker... bounding concurrent/windowed spawns"); accepted as sufficient for a single-session-scope mechanism rather than reimplemented, since there is no sweep for a separate breaker to bound |
| Arming | none — Phase 2 operator gate, unbuilt | auto, but the "opt-in" FM-037 asks for is the one-time LaunchAgent install (`install-limit-resume.sh ensure`), not a per-crisis manual touch |
| Cross-session safety | N/A (its whole job is cross-session) | `arm`/`disarm` are no-ops from any cwd that is not the main checkout (self-tested S2/S8) AND per-session keying means even a machine running TWO main-checkout sessions in different repos cannot clobber each other (self-tested S14, F3 fix) |
| Reentrancy | exports `NL_HOOK_REENTRY=1` | same — the resumed child cannot recursively re-trigger this or any other spawning hook |
| Backoff / hard stop | deferral ladder, park after 24h | exponential backoff (900s/1800s/3600s, capped 7200s) AFTER the initial floor, hard stop at 8 attempts, giveup sentinel makes the stuck state visible (doctor check) instead of silent |

Given that, the two mechanisms now share their PER-SPAWN safety controls (liveness
oracle, cooldown floor, reentrancy contract) and differ only in selection breadth
(one tracked session, never a sweep) and in the auto-arm choice itself — which is
where the genuine, deliberate departure from ADR-061 remains, justified by the
narrower scope and by the pre-existing heartbeat coverage the same hook splices this
build touches already establish. The FIRST draft of this table compared only scope
and claimed the mechanisms were "structurally incomparable" without checking whether
the per-spawn controls actually matched — `harness-reviewer` correctly REJECTed that
as an unsupported conclusion (finding F4): scope-narrowness alone does not justify
dropping a prior mechanism's specific safety controls, and this revision no longer
drops any of them.

## Turn-scoped arming (the actual novel design point)

Claude Code's `Stop` hook fires at the end of **every assistant turn**, not once at
the true end of a session — `workstreams-stop-writer.sh`'s own per-turn
heartbeat/turn-trace bookkeeping already depends on that fact, independent of this
change. A naive "arm once at SessionStart, disarm once at Stop" design would
therefore protect only the FIRST turn of a session: turn 2 onward would run with the
marker already disarmed and nothing re-arming it, since SessionStart does not fire
again until an actual new session (or compact/resume) begins.

**Decision:** arm at SessionStart (the operator's literal ask, covering the sliver
before the first prompt) AND at the start of every subsequent turn
(`UserPromptSubmit`); disarm at the end of every turn (`Stop`). Net effect: the
marker is armed for exactly as long as a turn is actively in flight — the only
window a usage-limit kill can land in — and disarmed while genuinely idle between
turns. This is a *smaller* blast-radius window than session-scoped arming, which is
the right direction per FM-037's own logic (shortest span that still does the job).

## Options considered

| Option | What happens | Cost / risk |
|---|---|---|
| A. Session-scoped arm (SessionStart only) / disarm (Stop) | Simple, matches the operator's literal wording | Broken as built: only protects turn 1, since Stop fires per-turn and nothing re-arms after it |
| B. Turn-scoped arm (SessionStart + UserPromptSubmit) / disarm (Stop) | Protects every turn for the session's whole lifetime; smallest correct window | One genuinely new `UserPromptSubmit` hooks[] entry (that event has no doctor-enforced budget today, unlike Stop/SessionStart) |
| C. Rearm session-resumer.sh's supervisor instead | Reuses existing, more thoroughly reviewed machinery | Directly contradicts ADR-061's explicit, deliberate, still-standing "no auto-arming" invariant for that specific mechanism; Windows-only; wrong shape (sweep, not single-session) |

**Decision: B.** A is silently broken past turn 1 (Prime Directive: a component
that only protects the first turn of a multi-hour session is not the functionality
the operator asked for). C would require overturning a standing, deliberate,
operator-approved safety invariant on a DIFFERENT, broader mechanism — not this
task's call to make, and structurally the wrong tool (single-session vs. sweep)
regardless.

## Why this is mine to decide (and what would reverse it)

Reversible in a few commands (see Tier above): uninstall the LaunchAgent, revert
three hook edits and one settings.json.template entry. The operator's own directive
names the outcome ("make that actually work") without prescribing the exact hook
wiring, and the turn-scoped design is the only one of the three options that
actually delivers a working mechanism across a whole session — this is a "can I
defend one answer from principles + evidence" call (constitution §3), not a
business-intent or subjective-taste call. Reversal trigger: if the operator ever
wants NO auto-resume on this Mac, `LIMIT_RESUME_DISABLE=1` or
`~/.claude/local/limit-resume-disabled` (installer kill-switch) plus removing the
armed marker covers it without touching this decision or any hook wiring.

## Consequences

- One genuinely new `settings.json.template` `UserPromptSubmit` hooks[] entry
  (backgrounded, `limit-resume.sh arm`) — that event has 3 pre-existing entries and
  no doctor-enforced budget (`budget-chains` only covers `Stop<=6`/`SessionStart<=8`).
  If a future budget is added for `UserPromptSubmit`, this entry counts against it.
- `session-start-digest.sh` and `workstreams-stop-writer.sh` each gain a new spliced
  callsite (not new hooks[] entries — both events are already at or discouraged from
  growing their array count). Both splices are protected for free by their host
  hook's existing `NL_HOOK_REENTRY` early-exit.
- A new always-on macOS LaunchAgent (`local.neurallace.limit-resume`, 900s
  StartInterval) exists on this machine once installed. Any future audit of "what
  runs unattended on this Mac" must account for it, same as decision 065's cockpit
  LaunchAgent.
- `docs/backlog.md` carries the Windows-equivalent gap: `install-limit-resume-task.ps1`
  is written to the established `install-*-task.ps1` pattern but is UNTESTED (no
  Windows box available this session).

## Post-review revision (2026-07-30, same day)

`harness-reviewer` (opus, independent probes against the running code — not a
code-read-only review) returned **REJECT** on the first build. Every finding was
PROVEN by the reviewer's own reproduction, not asserted:

- **F1 (Critical)** — no liveness discriminator; a tick moments after arm spawns
  `claude -p --resume` against a live, mid-turn session and then deletes the marker
  on success. **Fixed**: `hb_classify` liveness gate + `MIN_SILENCE_SECONDS` floor
  (see the revised comparison table above); self-tests S11/S12/S13 are standing
  regressions reproducing the reviewer's own probe.
- **F2 (Critical)** — the installer's script-path resolution fell back to a
  worktree-relative path whenever the main-checkout candidate file was absent (true
  on every pre-merge run), and the reviewer found a LaunchAgent ALREADY LOADED on
  this machine pointing at this very build's own throwaway worktree. **Fixed**:
  `_lir_resolve_script_path` now fails closed (logs a refusal, installs nothing) when
  the only candidate is inside a linked worktree; the live misregistered LaunchAgent
  was bootout+rm'd immediately; self-test S7 is a standing regression.
- **F3 (Critical)** — a single machine-global marker meant two concurrent sessions in
  different (non-worktree) repos would silently clobber each other's tracked state.
  **Fixed**: state is now keyed per session id; self-test S14.
- **F4 (Major)** — the original comparison table claimed the two mechanisms were
  "structurally incomparable" by scope alone while silently omitting that this one
  lacked ADR-061's liveness gate and cooldown floor. **Fixed**: see the revised table
  above, which now reuses both controls and states the one remaining honest gap
  (no separate machine-wide process breaker — reasoned as unnecessary given the
  single global lock already bounds this mechanism's own concurrency to 1).
- **F5 (Major)** — self-tests S2/S8 (worktree cross-session safety) passed vacuously
  if `git worktree add` itself failed silently. **Fixed**: both now assert the
  worktree exists before trusting the negative assertion.
- **F6 (Major)** — no initial floor before the first attempt, racing the CLI's own
  internal retry. **Fixed**: folded into the F1 fix (same floor).
- **F7 (Major, HYPOTHESIZED by the reviewer)** — backgrounded `arm` vs. synchronous
  `disarm` have no ordering barrier. Addressed by construction: the F1/F6 gates make
  an orphaned armed marker harmless (it cannot trigger a spawn until stale/crashed
  AND past the floor), so the ordering no longer matters for safety, even though it
  was not separately re-verified with a >=100-turn instrumentation run.
- **F8 (Major)** — the only real (non-stub) demonstration used an invalid-UUID
  session id, so a genuine SUCCESS path was never observed. **Partially addressed**:
  the real launchd + real `claude` binary + clean-failure chain was re-verified after
  the rewrite (still no PATH/env error — DEFECT 1 remains fixed), AND the same
  `hb_classify` oracle was independently confirmed against a REAL dead session on
  this machine (confirmed dead pid, 14h-stale heartbeat, classified `crashed`). A
  literal observed SUCCESS was not captured: the auto-mode classifier blocked
  further manipulation of that real session's identifiable state mid-demonstration,
  and this was not circumvented. Logged as a residual, named gap — not fabricated.
- **F9/F10 (Minor)** — `cd ... ; NL_HOOK_REENTRY=1 ...` (semicolon, not `&&`) could
  silently proceed in the wrong directory on a missing recorded cwd; `status`'s
  numeric fields lacked the sanitization `tick` already applied. **Fixed**: both.

## Round 2 (harness-reviewer REJECT again, same day, on the round-1 fixes)

The round-1 fixes above were re-reviewed by a fresh `harness-reviewer` dispatch, which
independently re-probed all 8 prior findings (confirming 6 genuinely closed) and found
**2 new Critical defects introduced by, or surviving through, the round-1 fixes
themselves** — both PROVEN via real reproduction, not asserted:

- **Critical-1** — `cmd_disarm` unconditionally `rmdir`'d the GLOBAL spawn lock. Since
  `disarm` fires on every turn's `Stop`, for every tracked session, this let ANY
  session's turn-end release a DIFFERENT session's tick's lock while that tick was
  actively mid-spawn. The reviewer's probe measured two concurrent `claude` children
  against the same session — a direct violation of safety-contract item 1 ("at most
  one live spawn per tick, machine-wide"), and the exact class FM-037 exists to
  prevent. **Fixed**: the lock is now released ONLY by its owning tick's own `EXIT`
  trap, or reclaimed by a new `_lr_reclaim_stale_lock` (age-based: a lock dir older
  than `TIMEOUT_SECONDS+120s` can only be an abandoned leftover from a tick that
  crashed before its trap ran) — never by an unrelated `disarm` call. Self-tests
  S16 (disarm cannot release another session's held lock) / S17 (a genuinely
  abandoned lock IS still reclaimed, so the mechanism cannot wedge shut forever).
- **Critical-2** — the liveness gate (this decision's own F1 fix) was a DENY-list:
  "proceed unless `hb_classify` says `live`." The reviewer proved this spawns on
  `throttled` — ADR-061 D4's own explicit **never-spawn** class (an alive process
  whose API traffic is erroring, i.e. precisely a limit-paused session already being
  retried by the CLI's own internal loop) — and on `stale` (a perfectly healthy
  session whose operator has simply been idle past the 30-minute floor, alive pid).
  This directly falsified the revised comparison table's "the two mechanisms now
  share their per-spawn safety controls" claim. **Fixed**: inverted to an ALLOWLIST —
  proceed ONLY when `hb_classify` returns `crashed` (stale timing AND the recorded
  pid confirmed dead — the one class that unambiguously means the process is gone,
  which is exactly what a usage-limit kill produces and exactly what needs an
  external `claude -p --resume` to recreate). `missing`/`live`/`throttled`/`stale`
  all now skip, mirroring `session-resumer.sh`'s own "cannot see clearly -> skip,
  never resume" discipline exactly rather than a narrower version of it. Self-test
  S15 (a stale-but-alive fixture must never resume).
- Also fixed in the same pass: the floor check used to fail OPEN (silently skip the
  floor entirely) when `armed_at` failed to parse; it now fails CLOSED.

With both fixes, the comparison table's claim now holds without qualification: the
allowlist reuses `hb_classify` exactly as `session-resumer.sh` does, restricted (not
loosened) to the single class both mechanisms agree is safe to act on.

## Round 3 (harness-reviewer REJECT a third time, on the round-2 fixes)

A fourth-invocation `harness-reviewer` re-verified rounds 1 and 2 with its own fresh
probes (confirmed all genuinely closed — the allowlist, the lock-ownership fix, the
floor, the fail-closed timestamp handling) and found **one new Critical defect, in
the same family as both prior rounds**, plus corrections to this ADR's own honesty:

- **Critical** — `limit-resume.sh` carries no reentry guard of its own: `cmd_arm`
  and `cmd_tick` only ever SET `NL_HOOK_REENTRY=1` for the child they spawn, never
  CHECK it for themselves. Two of the three hook chokepoints are protected only
  because their HOST hook (`session-start-digest.sh`, `workstreams-stop-writer.sh`)
  already has its own top-level reentry check that early-exits before ever reaching
  the splice — but the new `UserPromptSubmit` entry calls `limit-resume.sh arm`
  DIRECTLY, with no such host-level guard. The reviewer proved by probe that an
  automation-resumed child (which inherits `NL_HOOK_REENTRY=1` in its own
  environment) would re-arm through that entry, and — because `arm` also clears
  `.giveup`/`.attempts` — a successful automation resume would silently reset its
  own hard-stop counter, falsifying safety-contract item 3's bound. **Fixed**:
  `cmd_arm` and `cmd_tick` both now check `NL_HOOK_REENTRY` as their first statement
  and no-op if set — matching every other spawning hook's own top-of-function
  convention, rather than inheriting protection accidentally from a host. Self-tests
  S18 (arm under `NL_HOOK_REENTRY=1` writes no marker) and S19 (a reentrant arm
  cannot reset an existing giveup/attempts — the actual amplification risk named).
- **Major (asymmetric-unknown-handling)** — the liveness gate's fallback, when
  `session-heartbeat-lib.sh` fails to source entirely, used to degrade to
  floor-only ("proceed"), which is LESS conservative than the sibling branch (oracle
  available but this session's own heartbeat file is `missing`), which correctly
  skips. **Fixed**: both unknowns now fail equally closed (`skip-no-oracle`).
- **Major (golden_scenario overclaim)** — the manifest entry's `golden_scenario`
  and this ADR's own prose implied the mechanism covers usage-limit events broadly;
  the allowlist (this decision's own round-2 fix) actually covers only the subset
  where the process is confirmed DEAD (`crashed`) — an alive-but-throttled session
  (ADR-061 D4's own explicit never-spawn class) has no live coverage anywhere in
  this repo. **Fixed**: the manifest's `golden_scenario` now states this boundary
  explicitly rather than implying broader coverage.
- **Major (evidence-count-drift)** — this ADR's Evidence section previously
  asserted "153/154 pass, one pre-existing failure"; the reviewer's own independent
  run of the same suite reported 151/154 with three pre-existing failures. Both
  counts are confirmed pre-existing and unrelated (this build's diff to
  `harness-doctor.sh` is purely additive, 146 insertions/0 deletions, touching
  neither the orphan check nor the scheduled-task check) — but the exact tally is
  genuinely environment-sensitive (plausibly SKIP-vs-FAIL depending on whether
  `scheduled-task-health.sh` resolves in a given shell) and is now stated as such,
  rather than as one fixed number.
- **Minor (S9 half-property-test)** — S9 proved the resumed child RECEIVES
  `NL_HOOK_REENTRY=1`, never that `arm` HONORS it — the same shape as round-1's F5.
  Closed by S18/S19 above.
- **Minor (check-then-act lock reclaim)** — `_lr_reclaim_stale_lock`'s age check
  and removal were two separate steps, so two ticks could theoretically both
  observe a stale lock and both proceed. **Fixed**: the reclaim now renames the
  lock dir (atomic on the same filesystem) and only the renamer that succeeds
  treats the lock as free; a loser falls through to the normal `mkdir`, which then
  correctly fails.

## Round 4 (harness-reviewer REJECT a fourth time, on the round-2/3 fixes)

A fifth-invocation `harness-reviewer` independently re-verified rounds 1–3 clean
(re-ran every suite itself, re-probed the reentry guard and the no-oracle branch)
and found **one new Critical defect, in the same family as round 2**, plus two Major
findings:

- **Critical** — round 2 fixed `cmd_disarm` releasing a lock it did not own, but did
  not generalize the fix to the other two lock-touching code paths.
  `_lr_reclaim_stale_lock` reclaimed on AGE ALONE; the reviewer proved this
  insufficient by direct measurement (`timeout 2s bash -c 'trap "" TERM; sleep 12'`
  returned rc=124 only after the full 12s — a GNU `timeout` without `-k` sends only
  SIGTERM, so a child that traps/ignores it can genuinely outlive
  `TIMEOUT_SECONDS` while its owning tick is still alive and legitimately waiting).
  An age-only reclaim could therefore steal the lock from a still-live owner — and
  the EXIT trap was a bare `rmdir "$LOCK_DIR"`, removing whatever sat at that path
  regardless of who created it, so the tick whose lock was stolen would then delete
  the RECLAIMER's fresh lock on its own exit. The reviewer measured 2 concurrent
  `claude` children this way. **Fixed**: every lock acquirer now writes its own pid
  into `$LOCK_DIR/owner` immediately after `mkdir`; release
  (`_lr_release_own_lock`) checks that token before removing anything; reclaim
  additionally requires `kill -0 <owner_pid>` to fail (confirmed death, not merely
  age) before treating a lock as abandoned. Self-tests S20 (a confirmed-alive
  owner's lock — backed by a REAL background process — is never reclaimed however
  old) and S21 (the EXIT trap never removes a lock whose owner no longer matches,
  simulated deterministically via a stub that rewrites the owner file mid-spawn).
- **Major (silent unbounded shim)** — the fallback for a missing
  `portable-timeout.sh` ran the `claude` child fully UNBOUNDED with no
  announcement; every sibling caller of the same shim convention in this repo
  (`harness-doctor.sh`, `ensure-cockpit.sh`, etc.) emits a loud WARN. **Fixed**:
  matches the sibling convention.
- **Major (absolute-claim-on-unverified-premise)** — this ADR and the manifest
  both phrased the single-concurrent-spawn property as an unqualified absolute
  resting on the (false) premise that `nl_run_bounded` alone guarantees the child
  dies within `TIMEOUT_SECONDS`. **Fixed**: restated everywhere in terms of the
  ownership + confirmed-liveness check that actually makes the property true.

## Evidence (this session, this machine)

- `scripts/limit-resume.sh --self-test`: 21/21 scenarios (up from 10 — S11-S14 are
  round-1 regressions for F1/F3/F6; S15-S17 are round-2 regressions for the
  allowlist inversion and the lock-ownership fix; S18/S19 are round-3 regressions
  for the reentry-guard fix; S20/S21 are round-4 regressions for the
  ownership-token lock fix), including a mutation-proof hard-stop (pins the
  stub-call count at `MAX_RETRIES` across further ticks) and cross-worktree/
  cross-session safety proofs. Run clean on both `/bin/bash` (3.2.57) and
  `/opt/homebrew/bin/bash` (5.3.15).
- `scripts/install-limit-resume.sh --self-test`: 7/7 scenarios (up from 6 — S7 is the
  new fail-closed-from-worktree regression for F2). Both interpreters.
- `harness-doctor.sh --self-test`: this session's own runs consistently report
  153/154 pass (one pre-existing, unrelated failure — `orphaned-worktree-work-live-
  owned-green` — confirmed by diff to touch zero files this session changed;
  tracked separately on the `m6-selftest-sweep-flake` branch already in this repo).
  An independent harness-reviewer run of the identical suite in the same worktree
  reported 151/154 (three pre-existing failures — the other two in the Windows-only
  `obs-scheduled-tasks-red` family, plausibly SKIP-vs-FAIL depending on whether
  `scheduled-task-health.sh` resolves in a given shell). Both counts agree the
  failures are pre-existing and unrelated to this build (`git diff --stat` against
  `harness-doctor.sh` is purely additive, 146 insertions/0 deletions, touching
  neither the orphan check nor the scheduled-task check) — the exact tally is
  genuinely environment-sensitive and is reported as a range here rather than a
  single asserted number (round-3 finding: the ADR previously stated only this
  session's count as if it were universal). The 5 `limit-resume-watchdog-*`
  scenarios (including the per-session-isolation test) pass in every run.
- `manifest-check.sh check`: GREEN, 150 entries, 0 warn.
- Real (non-self-test) end-to-end demonstration, TWICE (before and after the
  review-driven rewrite): real `install-limit-resume.sh install` -> real
  `launchctl bootstrap` -> `launchctl list`/`print` confirms loaded -> armed
  manually -> real `launchctl kickstart -k` forces an immediate tick -> the real
  `claude` binary resolves and runs under real launchd's minimal inherited
  environment (no PATH/env error) -> a clean, informative CLI-level failure (fake
  session id, never a resume against anything live) -> logged -> disarmed. The
  SECOND run additionally verified the F2 fix directly: with the corrected scripts
  placed at the real main-checkout path (temporarily, to satisfy the resolver
  honestly rather than bypass it), the installed plist's `ProgramArguments` resolved
  to that main-checkout path, not a worktree — confirmed via `launchctl print`.
  All temporary files and the temporary LaunchAgent were removed at the end of the
  demo; see the session's completion report for the literal log lines.
