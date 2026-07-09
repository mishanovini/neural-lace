# Session Handoff — Spawn-Cascade Incident + Continuation (2026-07-09)

**Why this doc exists:** the original session ran on one Claude account; work continues on a
different (Fable-enabled) account. This is a cold-start handoff — read it first, verify the
state yourself, then continue. It is self-contained: you should not need the prior transcript.

---

## 1. What was accomplished (DONE — merged, verify by SHA)

**Incident:** a runaway bash/hook spawn cascade exhausted memory and crashed the machine on
2026-07-08. **Contained** by disabling both NL scheduled tasks (`NL-session-resumer`,
`NL-workstreams-heartbeat`) — both still `Disabled`.

**Root cause (PROVEN engine / HYPOTHESIZED ignition):**
- No reentrancy guard anywhere → an automation-spawned `claude` child inherits the full live hook suite.
- TWO Stop-side fan-outs fork ~10 subprocesses per Stop (`stop-verdict-dispatcher` member gates +
  `workstreams-stop-writer` members); a Stop-block re-fire loop multiplies it with **no `claude` needed**.
- PROVEN amplifier: `workstreams-ui/server/derive-cache.js` polls `nl.sh` for 6 subcommands every 30s
  via `setInterval`, dedup is per-process → N concurrent worktree cockpit instances each poll → "dozens
  of `nl.sh`, different parent PIDs."
- The **exact historical ignition sequence** is HYPOTHESIZED, not proven (can't reconstruct from
  process names alone). Honestly labeled as such in the finding.
- One sighting UNRESOLVED, not fabricated: `needs-you.sh --self-test` in production — no production
  trigger found; it self-sandboxes, so not a state-corruption vector.

**Guards built, independently verified, and MERGED** — PR #91,
squashed to master (originally `a3223652`, now an ancestor of current master). Both remotes synced
(work repo + public mirror). Guards: reentrancy-guard lib wired into heavy hooks; `session-resumer.sh`
hardening (hard spawn breaker, per-session cooldown, **shadow-until-armed** default); **automation-scoped**
Stop-refire ceiling; generic `nl.sh` spawn breaker. Deploy to live `~/.claude` via `session-start-auto-install`.

**Verification that mattered (not builder self-report):** functional self-tests re-run independently
(dispatcher 51/51, resumer 39/39); an adversarial code review confirmed a **human** session's ADR-059
DONE-refusal honesty invariant is **untouched** (only automation sessions are ceiling-bounded). A
first-round over-claim (nonexistent refire tests) and a broken-on-Windows process probe were caught
and fixed before merge. CI green including both hygiene/publish gates.

**Full incident record:** `docs/findings.md` → NL-FINDING-040; `docs/failure-modes.md` → FM-037.

---

## 2. Current state (verified vs. claimed)

| Item | State |
|---|---|
| Machine safety / containment | **VERIFIED** — both scheduled tasks Disabled; no cascade |
| Guards + finding | **MERGED**, both remotes (verify: `git log --oneline` for the #91 squash + NL-FINDING-040) |
| Resumer | **DISABLED** — NOT armed; `~/.claude/local/resumer-armed.txt` absent |
| Root cause | engine **PROVEN**; exact ignition **HYPOTHESIZED** |
| Observability program | master `f727fe5` marks it **COMPLETED** (verify the plan file) |

---

## 3. What remains

**Incident follow-ups (tracked in NL-FINDING-040 residual + an nl-issue):**
- [ ] **Resumer arming — OPERATOR-GATED decision.** Needs: the new Windows live-process probe verified on
      a live machine + a kill-drill + explicit operator opt-in. Until then it stays DISABLED (shadow default).
- [ ] **O.6 pipeline-health scheduled-task check — UNBUILT.** It is literally the check that would have
      caught the resumer hang (Last-Result monitoring for `NL-session-resumer` + `NL-workstreams-heartbeat`).
- [ ] **Hygiene denylist narrowing (nl-issued).** A short project-codename pattern in
      `patterns/harness-denylist.txt` matches case-insensitively as a substring of an unrelated generic
      engineering term, so it false-blocked PR #91 until the guards were renamed to "spawn breaker".
      Narrow it to a word-boundary/case-aware match — via harness-reviewer.
- [ ] **Automation-child DONE bypass is prompt-level only** (RESUME_NUDGE tells children to end
      `CONTINUING:`/`PAUSING:`, not `DONE:`). Consider mechanical enforcement.

**Broader NL work (see plan files):**
- Overhaul program `docs/plans/nl-overhaul-program-2026-07.md`: E.7 resumer rework (route dead-session
  detection onto O.2 heartbeat data instead of its own transcript scan — the hang class), F.4 retro
  (~2026-07-24), program completion report.
- Observability program `docs/plans/nl-observability-program-2026-08.md`: master says COMPLETED —
  **verify** the plan status + any residual verifier FAILs before assuming closure.

**Estate cleanup (housekeeping, non-urgent):**
- [ ] Idle orphaned survey subagent still shows "running" in the OLD session's Background-tasks panel —
      Clear it via the panel (harmless; work already merged; unreachable via task handles).
- [ ] Builder worktree `.claude/worktrees/agent-a88e2af4ec85b2ceb` + remote branch `fix/spawn-cascade-guard`
      — prune after confirming the squash landed (the worktree currently blocks branch deletion).
- [ ] This handoff worktree (`fable-continue`) + the stale `modest-satoshi-150d97` worktree — prune when done.

---

## 3.5 Operator's priority for THIS session — design task (a strong Fable fit)

The operator explicitly wants this session to take on **the auto-resume watchdog and a better way to keep
sessions moving forward and survive stalls / API-limit pauses.** Treat this as the headline task.

- **Watchdog status now:** `scripts/session-resumer.sh` (the auto-resume watchdog) is **DISABLED**. It hung
  in production (exited 124 on a hard timeout over the huge real transcript set) — part of what precipitated
  the incident. This change hardened it (hard spawn breaker, per-session cooldown, shadow-until-armed
  default) but it stays disabled until armed (operator opt-in + kill-drill + the new Windows live-process
  probe verified on a live machine).
- **Narrow follow-up already scoped (E.7):** re-point dead-session detection at the O.2 **heartbeat** data
  (ground-truth liveness) instead of the resumer's own expensive transcript scan — derive-don't-maintain —
  and add a live-scale self-test so the hang class cannot recur.
- **The broader question to design (this is the ask):** the best overall mechanism to keep sessions
  progressing and gracefully handle (a) stalls / stuck sessions, (b) API-limit and spend-limit pauses (e.g.
  the Fable monthly-limit and weekly-usage-limit pauses seen this week), and (c) orphaned idle agents
  blocked waiting on peer messages. Consider heartbeat-driven liveness, a bounded supervisor with hard
  ceilings (like the guards just added), resume aligned to limit-reset windows, and **file-based**
  coordination (agent-to-agent `send_message` is unreliable — O.8). Deliverable: a design proposal
  (`docs/decisions/` ADR or a plan), reviewed by `harness-reviewer` before implementation; respect the
  safety invariants (no auto-arming without opt-in).

---

## 4. How to continue (new-account session)

**Launch here:** this worktree — repo-relative path `.claude/worktrees/fable-continue`
(branch `claude/fable-continue`, off current `origin/master`, has the merged guards + this doc). The
originating session provides the full absolute path to open in the Desktop app.

**GitHub accounts are unchanged** — they are separate from the Claude account and auto-switch by
directory (the work repo and the public mirror each use their own GitHub account, selected
automatically by a SessionStart hook). Switching your Claude Desktop account for Fable does not
affect git/gh auth.

**Read first (cold-start):** (1) this doc; (2) `docs/findings.md` NL-FINDING-040 + `docs/failure-modes.md`
FM-037; (3) `SCRATCHPAD.md` (repo root); (4) the two plan files above; (5) memory index at
`~/.claude/projects/…/memory/MEMORY.md` (esp. the Fable entry).

**Fable usage (the reason for the switch):** Fable is the **strongest** model for planning/design/coding
but expensive. Use it for the **highest-value hard reasoning/design/code**, value-gated — NOT for
mechanical breadth (Sonnet/Haiku) and NOT speculatively. (Memory: `feedback_fable_only_when_real_value`.)

**Safety invariants to carry forward:**
- Do NOT arm the resumer without explicit operator opt-in + a kill-drill.
- Personal mirror is PUBLIC by design — never flip visibility, never force-push, never rewrite pushed
  history; the hygiene denylist + secret CI backstop are the publication gate.
- No `claude`/`schtasks`/`install.sh` from builder agents during any incident-shaped work.

**Suggested first prompt (copy-paste into the new session):**

> Continue the Neural Lace work handed off from a prior session (on a different Claude account). FIRST read
> `docs/handoffs/2026-07-09-spawn-cascade-handoff.md` in this worktree, then NL-FINDING-040 in
> `docs/findings.md` and `SCRATCHPAD.md`. Independently verify the current state (incident contained, guards
> merged, resumer still DISABLED). Then take on my priority: **design a better way to keep sessions moving
> forward and survive stalls + API-limit pauses** (the handoff doc's "3.5 Operator's priority" section — the
> auto-resume watchdog is disabled and needs a rethink). Produce a design proposal (an ADR or plan reviewed
> by harness-reviewer), not a rushed implementation. Also surface the other follow-ups from "What remains".
> Use Fable for the hard design work, value-gated. Do NOT arm the resumer without my explicit opt-in.

---

*Authored by the originating session (Opus 4.8) on 2026-07-09. Incident fix is merged and verified;
this hands off the follow-ups + program work.*

---

## Corrections (2026-07-09, continuation session — evidence-checked)

1. **"O.6 pipeline-health scheduled-task check — UNBUILT" is WRONG.** `scripts/scheduled-task-health.sh`
   + the doctor predicate `check_obs_scheduled_tasks` are built, wired (`harness-doctor.sh:1110-1149`),
   self-tested (78/78), verified PASS conf 9 (`docs/plans/nl-observability-program-2026-08-evidence/O.6.evidence.md`),
   and already RED the disabled `NL-session-resumer` task. The real gap is narrower: the doctor runs only at
   SessionStart/manual, so nothing notices a RED while no session is open — addressed by ADR-061 D6.
2. **The "exited 124 on a hard timeout" hang mechanism is asserted-not-corroborated.** No timeout construct
   exists in `session-resumer.sh` or its registration, and no independent record of that exit code was found.
   The PROVEN defect is the unbounded per-pass scan (no time budget, no candidate ceiling) — ADR-061 D1.
3. Estate cleanup partially done already: builder worktree `agent-a88e2af4ec85b2ceb` and remote branch
   `fix/spawn-cascade-guard` no longer exist (verified via `git worktree list` + empty `ls-remote`).
