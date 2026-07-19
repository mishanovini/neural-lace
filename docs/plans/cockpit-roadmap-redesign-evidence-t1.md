# Evidence + rung-3 comprehension articulation — cockpit-roadmap-redesign Task 1

Task: 1. Derived top-level status foundation (Verification: full, rung 3)
Builder commit: 598dae8 (branch build/roadmap-t1) — cherry-picked to master as f1488de
Builder: plan-phase-builder (sonnet), worktree agent-ae54bfb2272bba2c8, resumed post-reboot
from staged salvage. Verifier gates: pending (task-verifier + comprehension-reviewer).

## Builder-reported evidence (to be independently re-derived by the gates)

- `derive-lib.js --self-test`: 38/38 (new: enum, no-default-guess ordering, oracle interplay,
  activity classification, stalled-reason precedence, roll-up multiplicity/precedence/
  bottom-up propagation).
- `completion-oracle.js --self-test`: 19/19 (new: ported deployIsNewerThanShip predicate,
  oracle-class resolution, no-signal-never-silently-completes, override precedence).
- Regression: peer-view.js 32/32, plan-parse.js 14/14, server.selftest.js 165/165 both
  git-stash-control before AND after (zero regressions). Pre-reboot line-270 null-guard
  crash did not reproduce post-reboot (flaky/environmental, identical both ways when it
  fired — not this change either way).
- Livesmoke (REAL flagless, real ~/.claude/state/ask-registry.jsonl + real archived plan):
  18/18-done ask derives {status: complete, oracle_class: merged-is-deployed}; unresolvable
  plan_slug derives {status: unknown, reason: "plan parse failed (absent)"}; real heartbeats
  8-27h quiet classify quiet/in-progress, only >24h classifies crashed (anti-flap A6).
- Plan-file touch: ONLY `## In-flight scope updates` (path-bareness reconciliation for
  scope-enforcement-gate exact matching); no checkbox/Status edits. Flagged same bareness
  gap for server.js/auditor.js/payload-schema.js (next tasks' stagers).

## Rung-3 comprehension articulation (builder-authored, verbatim)

**Spec meaning:** Per-item status must be *computed* from mechanism-emitted ground truth
(plan checkboxes, session heartbeats, a completion oracle) at read time, never read off a
declared field — with every derivation-input failure rendering a named unknown(reason)
rather than a guessed bucket, and attention states (stalled/unknown) rolling up to every
collapsed ancestor as counted, precedence-ordered (never masked) badges.

**Edge cases covered:** damaged/absent plan file → unknown (checked before done/in-progress
branches, even if done:true); zero heartbeat evidence for an in-flight item → conservative
stalled:crashed, never a guessed in-progress; AV-pressure/API-throttle quiet spells within
the 24h window → stays in-progress, never flaps to crashed; multiple attention classes in
one subtree → one counted badge per class, display-ordered by precedence, never masking; a
grandchild's attention state reaching a grandparent via bottom-up badge folding; no-signal
oracle class never silently completing even when a deploy signal is (wrongly) present;
explicit override outranking every oracle class.

**Edge cases NOT covered:** waiting-on-you/blocked-on/limit-parked stalled reasons have no
real data source yet (accepted as caller-supplied signals only) — the registry has no
needs-you cross-reference, dependency, or park field at this layer; deploy-oracle's live
deploy-signal *collection* (the actual `vercel ls --prod` call) is explicitly out of scope
per A6's no-spawn-on-GET-path pin — the function accepts an already-collected timestamp only.

**Assumptions:** that "port, don't re-derive" for the deploy oracle means porting the
age-guard *predicate* (deployIsNewerThanShip), not the CLI-spawning collector, since the
latter would violate the no-spawn GET-path pin that governs this same task; that task 1's
"end-to-end" bar is a correctly-computed status value proven against real on-disk data,
since rendering/wiring into server.js's HTTP payload is explicitly task 3's job per the
plan's own Walking Skeleton note.

## Builder-declared honest gaps

- waiting-on-you/blocked-on/limit-parked stalled reasons: named + selectable but
  caller-supplied only (no production data source until tasks 2-4 land their data).
- server.js untouched — no HTTP wiring (task 3's scope per Walking Skeleton note).

## Gate results

### comprehension-reviewer (Fable, 2026-07-19): FAIL, confidence 8
Three PROVEN gaps (full report in orchestrator transcript; fix round dispatched to builder):
1. DRIVER unconsidered-edge-class: heartbeat PRESENT but schema-invalid derives
   stalled:crashed (derive-lib.js:478,481,589-591) while C5 (plan lines 85-88) and the diff's
   OWN header comment (:388-392) mandate unknown("unreadable heartbeat"). Fix direction:
   distinguish present-but-invalid (→unknown) from absent (→conservative crashed).
2. Unsurfaced caller-contract: missing `done` falls through to not-started (guessed bucket,
   :523,:573-575) — guard to unknown("missing required input") or articulate.
3. Env-input invalid partition: non-numeric COCKPIT_SESSION_ACTIVE_MIN/_ACTIVITY_WINDOW_MIN
   → NaN thresholds → EVERY session classifies crashed (:427-432,:449-455). Guard parse,
   fallback to defaults on NaN.
Non-blocking: add file:line cites to covered-edge bullets; ### sub-headings; one Assumptions
line for the readyMs>=shipMs equal-boundary (port-verbatim adjudicated correct).
Checkbox NOT flipped. 7/7 covered-edge claims otherwise grounded; NOT-covered list honest.

### task-verifier (Fable): PASS, confidence 8
All five suites re-derived green matching claimed tallies; five falsification probes survived;
real-data livesmoke reproduced the defect fix; port byte-identical to work-in-motion-sweep
(:394-398 — note: lives under scripts/, not server/). Residual R-1 resolved by the fix round;
R-2 (no-spawn selftest pin) lands with task 3 GET route per plan Testing Strategy.

### comprehension-reviewer DELTA (Fable): PASS, confidence 8 — checkbox flip authorized
All 3 prior gaps PROVEN fixed at dd75fa5 (both-direction selftest pins re-run independently:
derive-lib 56/56, oracle 19/19); no new divergence class (invalid propagates through roll-up
as counted unknown badge, test 12). Two stale line-refs corrected in this file. Negative-env
minutes observation filed via nl-issue (pre-existing, out of delta scope).

TASK 1 DONE: both rung-3 gates PASS. Checkbox flipped by orchestrator on dual authorization.

## Fix round (2026-07-19, builder commit 71c30c4 → master)

All 3 comprehension gaps fixed, each proven RED against old logic first:
1. present-but-invalid heartbeat → unknown("unreadable heartbeat (present but schema-invalid
   last_activity_ts)"); absent stays stalled:crashed; store ENOENT (benign) vs unreadable
   (ok:false) distinguished via listRawHeartbeatsResult(); listRawHeartbeats() wrapper
   contract unchanged (export-state.js:150 verified).
2. missing/non-boolean done → unknown("missing required input: done"); explicit false normal.
3. envMinutes() guard: NaN/invalid env → documented defaults; explicit "0" honored.
Suites: derive-lib 56/56 (38+18 new), oracle 19/19, peer-view 32/32, plan-parse 14/14,
server.selftest 165/165. Real-data poisoned-env check: sessions still classify correctly.

### Revised articulation (fix round, citation-backed)

**Spec meaning:** Per-item status must be computed from mechanism-emitted ground truth at
read time, with every derivation-input failure — including a heartbeat that is present but
schema-invalid, and a caller that fails to supply a required boolean — rendering a named
unknown(reason), never a guessed bucket; env-injectable thresholds must degrade to their
documented defaults on any invalid override, never silently corrupt every downstream
classification.

**Edge cases covered:** damaged/absent plan file → unknown (derive-lib.js:635-637);
present-but-invalid heartbeat distinct from genuinely-absent → unknown vs stalled:crashed
(:534-563, :684-689, :698-701); corrupt record on one session never overrides real positive evidence
on another (test 2g); store unreadable (ENOTDIR/EACCES) vs never-created (ENOENT)
(:364-399); missing/non-boolean done → unknown while explicit done:false proceeds
(:642-644, tests 7f-7h); DONE item never consults heartbeat evidence (test 7e); non-numeric
env override → default, explicit "0" honored as real override (:461-467, tests 18-19b).

**Edge cases NOT covered:** two heartbeat files for one session id (writer's invariant, not
re-validated); waiting-on-you/blocked-on/limit-parked still caller-supplied (no registry
data source yet); readable→unreadable mid-request TOCTOU (per-file try/catch keeps the
pre-existing fail-open convention, untouched by this task).

**Assumptions:** zero-task plan (0/0) is never done by vacuous completion — caller passes
done:false (contract documented); ported predicate readyMs>=shipMs inclusive equal-boundary
is ADR-056 verbatim semantics (completion-oracle.js:125), not a new choice.
