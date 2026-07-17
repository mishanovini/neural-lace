# Cockpit-v2 cross-machine EXPORT — architecture review of v4 (convergence re-review)

Reviewer: `architecture-reviewer` (Fable). Target: `docs/plans/cockpit-v2-push-materialized-store.md`
(DRAFT v4). Predecessor: `docs/reviews/2026-07-17-cockpit-v2-architecture-review-v3.md`
(NEEDS-RESHAPING with a written convergence condition). Method: finding-by-finding verification of
the convergence condition against plan text AND live code; full protocol on everything new in v4.

```
VERDICT: SOUND-WITH-AMENDMENTS

THE ONE THING: v4's architecture is the converged design — but its honesty layer is written
against a transport that does not behave as the plan claims. coord-push.sh exits 0 on EVERY
failure path (including SSH auth death), stamps its throttle file anyway, and its no-op gate
NEVER retries an unpushed local commit until the next content change; meanwhile the hash-gate
means an idle machine publishes nothing, so "peer unreachable" and "peer idle" are the same
pixel. Together these make the plan's headline promise — "never a silent stale render" — theater
at the transport layer, and its own edge-case text ("git+SSH fails LOUDLY (non-zero)") is
PROVEN false at coord-push.sh:181-198,233-238. Fix the wiring contract (amendments A1-A5);
the architecture itself needs no reshaping.
```

## Convergence verification (v3's condition, finding-by-finding)
- **F1** in-flight/session snapshot in export — **YES** (join real + file-based, server.js:826-878;
  heartbeat classification real, server.js:1085-1150), with A3c: sessions must export RAW
  `last_heartbeat_at` — never a baked classification (age-based truth cannot survive transport).
- **F2** staleness contract — **PARTIAL**: numbers written but inconsistent with both named wirings
  (A1); unreachable-vs-idle has no distinguishing mechanism (A3).
- **F3+F8** coord git+SSH binding + owned wiring — **YES** on binding/ownership (invoked-by-nothing
  confirmed by repo-wide grep); **NO** on the loudness claim (A2).
- **F4** single exporter / provenance schema / unmerged-never-done / same-slug rule — **YES**
  (no-overlap enforcement folded into A1).
- **F5** local GUI stays on the parse — **YES**: audited tasks 1-8; no task routes any local read
  through the export.
- **F6** no hook-push; drift machinery deleted not deferred — **YES** (Decisions Log explicit).
- **F7** shared fixture corpus, not a fourth grammar — **YES** (A6 scope refinement).
- **F9** retirement decay clause; Circuit P1 unblocked — **YES**.
- MultiEdit matcher hole re-verified still open (settings.json.template:407). C3b's divergence
  class real (auditor.js:521).

## Binding amendments (before ACTIVE)
- **A1 MAJOR (PROVEN health-tick.sh:12-13)** — health-tick is HOURLY: the ≤600s cadence needs a
  dedicated scheduled task (`NL-coord-sync`, 600s) running exporter → coord-push → coord-pull;
  restate the contract (export+publish ≤600s, pull ≤600s ⇒ ~20min worst); delete the vestigial
  "≤60s after change" claim; state the no-overlap policy (ignore-new-instance + a cheap exporter
  lock — login-shell bash spawns measured 94-119s here); this task being the exporter's ONLY
  invoker IS the single-writer-per-machine enforcement.
- **A2 MAJOR (PROVEN coord-push.sh:160-198,233-238)** — coord-push is WARN+exit-0 on every failure
  and its no-op gate never retries an unpushed commit on a quiet estate (unbounded contract
  breach). Task 3 must: fix the ahead-of-origin path (push whenever HEAD is ahead, not only on new
  staged changes); consume coord-push's outcome via a status file (`pushed|local-commit|noop`+ts);
  raise the existing health-tick alert path on persistent `local-commit`; rewrite the plan's false
  "fails LOUDLY" edge case honestly (writer side is exit-0-tolerant by design; detection =
  reader-side states + this writer-side status surface).
- **A3 MAJOR (mechanics PROVEN coord-push.sh:139-151)** — unreachable vs idle: give each state a
  mechanism — (i) reader-side "my coord view last refreshed Xm ago" (from last successful pull);
  (ii) bounded keepalive: refresh `exported_at` at least every 60min even when hash-unchanged
  (caps idle churn at 24 commits/day/machine); (iii) "estate unchanged since <ts>" distinct from
  unreachable. Sessions: export raw timestamps; the READER classifies by age.
- **A4 MAJOR (PROVEN server.js:1822-1844)** — the exporter MUST NOT require server.js (module load
  runs listen(); EADDRINUSE → process.exit(0) SILENTLY). Task 2 explicitly includes factoring
  `computePlanRows`/`aggregatePlanProgress`/`countPlanTasks`/`resolvePlanAbsPath`/
  `classifySessions` into a requireable `server/derive-lib.js`, with server.js repointed.
- **A5 MINOR (PROVEN coord-push.sh:86-90)** — the single-machine acceptance sim needs an
  `EXPORT_HOSTNAME` override (coord keys peers by hostname; both sim "machines" share one) and
  env-injectable peer-state thresholds (precedent: coord-push's own TEST_HOST).
- **A6 MINOR (PROVEN by re-count)** — v3's "208 lettered-id lines" did not reproduce: 1,947
  checkbox lines under docs/plans/**, 699 match the numeric grammar, and the ~1,248 invisible
  remainder are mostly UNNUMBERED CHECKLIST BULLETS, not tasks. The fixture corpus must pin
  NEGATIVE cases (checklist bullets are deliberately not tasks) or a widened grammar silently
  inflates every progress bar.
- **A7 note** — coord-pull refreshes via `reset --hard`; the reader inherits skip-bad-record
  tolerance for mid-checkout partial files (one line in Testing Strategy).

## Pre-mortem (condensed)
SSH key rotates → coord-push exits 0 daily → after a quiet weekend even local commits stop (no-op
gate never retries) → peer renders "aging", which the operators learned to ignore because idle
nights false-fire it → three in-flight builders invisible at a stand-up → the same plan dispatched
twice. Every root cause is A1-A3.

## Steelman / crossover
Rendering peers from coord's existing tree-state fails (the cockpit's own reconciler exists to
distrust it — reconciler.js:9-15 — and it carries no derived plan state). The design wins while
~20min glance-freshness satisfies the consumer; it loses the day a cross-machine CONTROL LOOP
needs sub-minute peer state (a different transport class — correctly out of scope).

## What would change the verdict
To SOUND: A1-A5 folded into the plan text (A6/A7 as task-level notes). To NEEDS-RESHAPING:
evidence the private coord repo cannot carry the export files, or a real sub-minute consumer now.

**Convergence answer for Check 17:** v4 genuinely IS the v3 Phase-0 candidate — all nine
convergence items structurally present; three supporting wiring-layer claims were false against
the code and are corrected by the binding amendments. VERDICT: SOUND-WITH-AMENDMENTS.
