# Wave O retro — NL Observability Program vs pre-registered success metrics

Task O.7. Author: orchestrator (Opus 4.8, strongest available — full program context).
Date: 2026-07-08. Program: `docs/plans/nl-observability-program-2026-08.md` (all
build/verify tasks complete; this retro is the final task). Normative metrics:
`docs/reviews/2026-07-04-observability-design-sketch.md` §"Pre-registered success
metrics". Program landed at master `887b266` (both remotes tree-synced).

## Verdict

The program met its two mechanically-measurable pre-registered metrics and delivered
the third (operator trust) as a live, accepted surface whose trust is now the
operator's to confirm through use. All 10 tasks (O.0–O.9) are verified by an
adversarial task-verifier — every checkbox earned, none self-reported. The
verification gate caught a genuine "built-but-not-done" defect on **every** re-verify
round it ran (end-manifest, O.3 ×4, O.6 ×2, O.9 ×2) — that catch-rate is the
overhaul's core value working live, not a sign of sloppy building.

## Pre-registered metric 1 — median time-to-answer Q1–Q6 < 10s (measured by drill)

Measured live against the real estate (923 all-time transcripts / 339 <24h / 36 live
sessions — a large historical surface), via `nl <sub>` steady-state, 2026-07-08:

| Operator question | CLI | Measured | <10s |
|---|---|---|---|
| Q1 What's running | `nl status` | 3.8s (3828–4404ms ×4) | ✓ |
| Q2 What needs me | `nl needs-me` | 0.45s | ✓ |
| Q3 What happened | `nl shipped` | 0.77s | ✓ |
| Q4 Is the harness working | `nl status` doctor header / `nl health` | in-status; cached | ✓ |
| Q5 What's it costing | `nl costs` | 6.5–7.0s warm | ✓ |
| Q6 Why did X happen | `nl why <sid> --last-block` | 1.9s | ✓ |

**Metric 1: ACHIEVED.** Median ≈ 1.3s; every question < 10s. Caveat (honest): one
non-reproducible 11.2s cold-OS-first-touch on `nl costs` (the session's very first `nl`
invocation across 923 files with a cold Defender/OS filesystem cache); a controlled
cold-app-cache rebuild measured 9.6s (under bar) and all subsequent runs 6.5–7.0s. The
< 10s bar holds in steady-state and controlled-cold; a genuine first-touch-after-reboot
may momentarily exceed it. Getting here took four profile-driven perf iterations on
`nl status` alone (55s → 15s → 3.8s) — see Deviations.

## Pre-registered metric 2 — zero ledger event types without a mapped consumer (doctor-audited)

Live audit 2026-07-08: the set of event types observed in the ledger (last 1000 lines)
minus the consumer-map keys = **∅ (empty)**. `observability-consumer-map.json` maps 27
event types, each with ≥1 named consumer; `check_obs_consumer_map` (O.6) enforces this
two-sided (ledger-observed ⊆ map, and repo-emitted `ledger_emit` literals ⊆ map) and is
GREEN. **Metric 2: ACHIEVED.** The anti-RC4 invariant (every signal has a named
consumer or it doesn't ship) is now a live doctor gate, not a documented aspiration.
Note: this metric was momentarily RED mid-wave when `work-integrity-gate` emitted an
`info` event the map lacked — the check TRUTHFULLY caught a real law-2 gap (not a false
positive), and `info` + `reap` were added at integration to close it.

## Pre-registered metric 3 — operator trusts the cockpit enough to stop asking sessions for status

This is the qualitative inversion of the Workstreams failure ("has failed completely").
Status: the cockpit is **rebuilt on derived truth and live at http://localhost:7733**,
and passed a 10/10 adversarial acceptance run (end-user-advocate, all six questions
exercised in the browser with derived-vs-displayed equality against `nl <sub> --json`,
honest error states, drift badge, keyboard pass). The two design laws are mechanically
enforced: derive-don't-maintain (every pane recomputes from ground truth; the old
event-sourced trust path — both workstreams gates + item-extraction writers — was
retired to attic/, closing NL-FINDING-024 at the root), and every-signal-has-a-consumer
(metric 2). **Metric 3: DELIVERED as a trustworthy surface; trust-in-use is now the
operator's to confirm.** The honest test — does the operator consult the cockpit instead
of asking sessions — can only be answered by the operator over the coming weeks; this
retro cannot self-certify it. Recommend revisiting at the next estate checkpoint.

## Task outcomes (all verified)

| Task | Outcome | Verifier confidence |
|---|---|---|
| O.0 Wave-spec | specs-o + dispatch map + frozen contracts | PASS 9 |
| O.1 Emit + consumer-map | 10 new event types + turn-traces + map | PASS 9 |
| O.2 Heartbeat | per-session liveness; kill-drill (crashed in 9s) | PASS 9 |
| O.3 Derivation lib + `nl` CLI | Q1–Q5 <10s (4 perf iterations); `nl why` 024 | PASS 8 |
| O.4 Cockpit rebuild | six-question UI on derived truth; 10/10 acceptance | PASS 9 |
| O.5 Push (ntfy) | **descoped by operator** (no phone observability) | closed |
| O.6 Pipeline-health doctor | 6 checks, red-fixtures; live findings caught real debt | PASS 9 |
| O.7 Retro | this document | — |
| O.8 Estate-coordination | skill + doctrine + drill (10/10) | PASS 8 |
| O.9 Backlog loop | age-tiers + escalation + dispositioned-in-flight | PASS 9 |

## Deviations log (decide-and-go, for operator §8 review)

- **Blocking-budget framing correction (CANONICAL-COUNTERS-01 in action):** Decision
  060 claimed the tree-gate retirement drops blocking budget 10→8. The canonical
  D-wave unit oracle (`blocking-budget-check.js`) says 10/12 UNCHANGED — the retired
  spawn-gate was already folded into the `agent-teams` unit; only raw manifest entries
  dropped (15→14). The canonical oracle wins; 060's "10→8" was the raw framing.
- **O.3 took four perf iterations** (od_sessions transcript-index → hb_classify
  find-elimination → fork-batching + heartbeat-reaping). Each was justified by a proven
  profile, not a guess; the root cause was Windows/MSYS ~0.3s-per-subprocess-fork ×
  session-count, not algorithmic complexity. Reaping dead heartbeats (>24h) both fixed
  the timing and closed an estate-hygiene gap (stale heartbeats accumulated unbounded).
- **Mid-program process crash** (plausibly a spawn-cascade, guarded independently by
  PR #91 / NL-FINDING-040 which landed on master during the wave): killed all in-flight
  subagents. Recovery cost nothing durable — verified work was safe on master, partial
  builder work was salvaged to branches and continued, and every re-dispatched agent got
  a **pinned model** (the crash also exposed that verification agents inherit the parent
  model and die when the parent's account/limit fails — filed for agent-model-floor
  frontmatter).
- **Three operator directives absorbed mid-wave:** (1) O.5 ntfy descoped permanently
  (no mobile interaction path; Dispatch app incompatible); (2) cold-reader decision-lint
  built (constitution §3 "cold-reader bar" — every operator ask must be answerable with
  zero session context; this program's own re-nag of a bare-ID decision was its golden
  scenario); (3) gh-account auto-switch built (the operator loses hours when a wrong-
  account 403 stops the agent — the exact bug hit the orchestrator repeatedly during
  this wave's own pushes).

## Findings / follow-ups (all filed; none block program completion)

- `cold-reader-lint` `_svd_message_has_decision_block` false-fires on negation ("no
  decision needed here") — WARN-only, pre-existing on its branch, nl-issued; tighten
  the regex.
- `session-start-digest` S2 self-test reads live `unresolved-gaps.jsonl` unsandboxed
  (fixture-isolation leak; feed orthogonal to any wave task) — nl-issue.
- `NL-session-resumer` scheduled task disabled / Last Result -1 (E.7 / overhaul-program
  territory; `check_obs_scheduled_tasks` correctly REDs it) — ops decision for the
  operator on re-arming.
- `gh-account-autoswitch` hook is present + templated but not wired into the live
  `settings.json` (hooks-block is a surgical live step) — future sessions get it on the
  next settings sync; wire now if the auth-stuck friction recurs.
- `session-heartbeat.sh reap` has no scheduled call-site yet (HARNESS-PERF-O3-HB /
  backlog) — wire a periodic invocation so heartbeats stay bounded without a manual run.
- `HARNESS-PERF-O3-HB`: `nl status` residual per-session cost could drop further by
  threading pre-resolved session_id/last_activity through hb_is_stale (not needed for
  the <10s bar; optional).

## What worked (process)

The D9 pattern (strong-model spec → sonnet builders → adversarial task-verifier) held
under a crash, a model-limit switch (Fable→Opus), and a large estate. The load-bearing
discipline was **one oracle per truth** (CANONICAL-COUNTERS-01): every FAIL this wave was
the same class — a second source of truth drifting from the canonical one (end-manifest
write-vs-validate; O.3 summary-vs-contract backlog schema; O.6 raw-mtime-vs-hb_classify;
O.9 SCHEDULED-invisible-to-oracle). Naming that class turned scattered bugs into one
predictable failure mode the verifier could hunt.
