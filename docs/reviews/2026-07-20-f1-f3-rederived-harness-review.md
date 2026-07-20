# Harness Review — F1/F2/F3 re-derived (2026-07-20)

Reviewer: harness-reviewer (opus). Context: the 2026-07-19 batch review (commit aeaf9d8)
returned REFORMULATE on coord-sync.sh (F1) / harness-doctor.sh (F2) / session-start-digest.sh
(F3) but the session died before persisting the findings (§5 failure; only the 6 PASS records
survived). This review re-derived all three from the current origin/master blobs (abfa93d).
The prior fix wave (build/harness-reform-f123) never landed — branch empty vs origin/master.

## Verdicts

| File | Master blob | Control | Verdict |
|---|---|---|---|
| `adapters/claude-code/scripts/coord-sync.sh` | `4e427338` | pre-T7 blob `14568b2` (never covered) | **REFORMULATE (confirmed)** — Critical, PROVEN |
| `adapters/claude-code/hooks/harness-doctor.sh` | `7a28c56` | covered/live `4b152d5` | **PASS (re-derived)** — 1 Minor advisory |
| `adapters/claude-code/hooks/session-start-digest.sh` | `62ae96a` | covered/live `757d77d` | **PASS (re-derived)** — 1 Minor advisory |

## F1 — the Critical (PROVEN), class: caller-defeats-callee-guard-composition

coord-sync.sh:432 calls `coord-push.sh push` WITHOUT `--force`; coord-push.sh:71 defaults
`COORD_PUSH_THROTTLE_SECONDS=600` and :283-291 early-returns `outcome=noop` inside the window.
Consequences: (1) A5 defeated — event publishes <600s after a prior push reach origin only when
the throttle expires (up to 600s latency, the exact pre-T7 latency the redesign removes);
(2) A2c starved — coord-sync.sh:310-313 treats `noop` as streak-broken, so the dead-remote
local-commit streak never reaches threshold and the alert never fires; (3) masked — the
self-test sets `COORD_PUSH_THROTTLE_SECONDS=0` at coord-sync.sh:518,663,681, so the composition
was never exercised with the guard ACTIVE. Header/manifest/runbook claims ("publish within
~1 min", A2c alert) are false at production config — constitution §10 theater.

Original F1 wording survived at `docs/plans/cockpit-roadmap-redesign-evidence-t7.md:64` and
matches this re-derivation.

### F1 REQUIRED-FIX (buildable as-is)
1. coord-sync.sh:432 → `bash "$COORD_PUSH_SH" push --force` (coord-sync's own debounce is the
   single per-machine rate limiter: ≤1/60s events, ≤1/600s floor).
2. coord-push.sh:290 → distinct outcome word `throttled` (not `noop`); coord-sync
   `_track_local_commit_streak` (294-315) treats `throttled` as no-signal (does NOT reset).
3. Self-test: remove/parallel the THROTTLE=0 masking (518/663/681); add assertions —
   (a) event cycle <600s after prior push STILL advances origin (proves --force);
   (b) dead remote + default throttle → streak reaches threshold, exactly one A2c alert.
4. Reconcile header lines 4 vs 80 + `docs/runbooks/coord-sync.md` with fixed behavior.

Generalization: any script driving a throttled/debounced sub-tool on a NEW event cadence must
bypass the sub-tool's guard or move the rate limit up to the driver; its self-test must run the
guard ACTIVE.

### F1 secondary (Minor, HYPOTHESIZED): invariant-scoped-to-one-caller
The 900s stale-lock-reclaim safety proof holds only for the scheduled path (ExecutionTimeLimit
5min, install-coord-sync-task.ps1:166; S9 pins 900>300). A manual/--force cycle is unbounded;
if it hangs >900s the next scheduled fire reclaims + double-runs (breaks single-writer F4).
Fix options: bounded git timeout on the manual path, or pid-alive check in _acquire_lock, or
narrow the header claim.

## F2 — PASS rationale
Delta = `check_orphaned_worktree_work` only: WARN-only (never RED/blocks), 7-field porcelain
contract matches `_emit_stranded` exactly, detector deployed + blob-matched (`730b073d`),
4 fixtures incl. the cry-wolf FP guard, graceful degradation on every missing dependency, runs
on the cached doctor cadence (no SessionStart latency). Prior REFORMULATE moot: the sweep was
deployed 51 min AFTER the 07-19 review — a deploy-ORDERING blocker then, resolved now.
Minor advisory: timeout-wrap the sweep fork (unbounded-subprocess class).

## F3 — PASS rationale
Delta = `feed_stranded_work` only: advisory, silent common case, human-format contract matches
emitter, layer-correct path resolution, S18a/S18c negative guards. Double-sweep concern
REFUTED (feed_doctor reads doctor-cache.json; the doctor check does not run on SessionStart).
Minor advisory: timeout + optional cache-parity with feed_doctor
(uncached-cost-on-session-start-hot-path class).

## Disposition
F2 + F3 PASS records registered (this commit) → deploy on next auto-install sync.
F1 fix builder dispatched with the REQUIRED-FIX list; on land → re-review the fixed blob →
record → deploy → task 7 verifier + checkbox (held ONLY on F1). Three Minor advisories filed
via nl-issue (F1-lock-scope, F2-timeout, F3-cache) for the triage loop.
