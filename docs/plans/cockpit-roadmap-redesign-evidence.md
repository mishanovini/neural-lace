# Evidence Log — Cockpit roadmap redesign: one registry, three views

## Task 1 — [serial] Derived top-level status foundation

EVIDENCE BLOCK
==============
Task ID: 1
Task description: [serial] Derived top-level status foundation. Per-item status computed, never declared. Fixes the done-renders-ACTIVE defect. (Enum C5 / Complete oracle A4 / in-progress A6 / Stalled reasons / Roll-up law C1+R4.) Verification: full
Verified at: 2026-07-19T20:05:00Z
Verifier: task-verifier agent (adversarial re-derivation; builder claims in cockpit-roadmap-redesign-evidence-t1.md treated as UNVERIFIED and independently re-run)

Oracle: specified — plan task-1 text (C5/A4/A6/C1/R4, binding amendments folded) + derived-preexisting — server.selftest.js 165-test suite as the zero-regression oracle, work-in-motion-sweep.js:394-398 as the port oracle, and real on-disk state (ask-registry.jsonl + the archived ask-rooted-workstreams-p1 plan) for the livesmoke.

Comprehension-gate: articulation present and substantive (all four canonical sub-sections in cockpit-roadmap-redesign-evidence-t1.md); comprehension-reviewer runs as the orchestrator's SEPARATE pending gate per the dispatch and that file's header — not invocable from this verifier thread (no Task tool). Rung: 3.

Checks run:
1. derive-lib.js --self-test re-run: node server/derive-lib.js --self-test -> 38 passed, 0 failed, rc=0 (matches claimed 38/38). PASS
2. completion-oracle.js --self-test re-run: node server/completion-oracle.js --self-test -> 19 passed, 0 failed, rc=0 (matches claimed 19/19). PASS
3. Regression suites re-run (pre-existing oracles): server.selftest.js 165/165 rc=0; plan-parse.js 14/14 rc=0; peer-view.js 32/32 rc=0 — all match claims, zero regressions. PASS
4. Six-value enum + no-default-guess falsification probes (verifier-authored): damaged plan (dir-as-.md) derives unknown("plan parse failed (damaged)") EVEN with done:true + overrideComplete:true; bogus slug derives unknown("plan parse failed (absent)") even with done:true; every probe result lands inside the frozen six-value STATUS_VALUES enum. PASS
5. Roll-up law probe (crafted 3-level fixture): 4 attention classes at root — waiting-on-you:2, crashed:1, limit-parked:1, unknown:1 — counted, precedence-ordered, none masked (R4 multiplicity); grandchild-to-grandparent bottom-up propagation confirmed. PASS
6. Oracle three-class probe: no-signal with a (wrong) deploy signal present renders merged-deploy-unverified, never complete; override renders complete + overridden:true label, outranks every class; deploy-oracle age-guard boundaries verified. PASS
7. A6 no-spawn inspection: completion-oracle.js has zero child_process; derive-lib.js only spawns inside pre-existing classifySessions (lazy require, detail-path-only, untouched); the entire new Task-1 derivation section is pure fs-read/pure-compute. PASS (see Residual R-2)
8. Port fidelity: deployIsNewerThanShip at completion-oracle.js:125-129 is byte-identical to scripts/work-in-motion-sweep.js:394-398; the CLI-spawning collector correctly EXCLUDED per A6 — predicate ported, not re-derived. PASS
9. Livesmoke (real flagless derivation): ask-20260710-workstreams-rebuild / slug ask-rooted-workstreams-p1 resolves via the archive-aware resolver, parses 18/18 done, derives status complete + oracle_class merged-is-deployed + overridden false; bogus slug derives unknown. PASS
10. Git + plan hygiene: f1488de contains exactly the four claimed files plus plan In-flight scope updates; NO checkbox/Status/rung edits in the commit plan diff; config two-layer convention followed. PASS

Runtime verification: test neural-lace/workstreams-ui/server/derive-lib.js::self-test
Runtime verification: test neural-lace/workstreams-ui/server/completion-oracle.js::self-test
Runtime verification: test neural-lace/workstreams-ui/server/server.selftest.js::full-suite
Runtime verification: test neural-lace/workstreams-ui/server/plan-parse.js::self-test
Runtime verification: test neural-lace/workstreams-ui/server/peer-view.js::self-test
Runtime verification: file neural-lace/workstreams-ui/server/completion-oracle.js::deployIsNewerThanShip
Runtime verification: functionality-verifier 1::SKIP (rationale: library-layer foundation with no user-observable HTTP/UI surface until task 3 per the plan Walking Skeleton allocation; maintainer-facing self-test + real-data livesmoke executed directly by this verifier)

DEPENDENCY TRACE
================
Step 1: reader calls foldAskRegistry() on the real ask-registry.jsonl
  Verified at: check 9 (ask-20260710-workstreams-rebuild folded, plan_slugs contains ask-rooted-workstreams-p1)
Step 2: resolvePlanAbsPath then plan-parse.js loadPlanFile (archive-aware)
  Verified at: check 9 (docs/plans/archive/ask-rooted-workstreams-p1.md, ok:true, 18/18)
Step 3: deriveItemStatus checks planLoad failure FIRST, then done routes to completion-oracle
  Verified at: derive-lib selftest 4/4b + probe F-A (unknown wins even over done + override)
Step 4: completion-oracle resolves class (override file > checked-in default > no-signal) and evaluates
  Verified at: oracle selftest 2-11 re-run + livesmoke complete/merged-is-deployed
Step 5: attention states fold upward via rollUpAttentionBadges (bottom-up, counted, per-class, precedence-ordered)
  Verified at: derive-lib selftest 14-17 + crafted 3-level probes F-D/F-E

Residual findings (non-blocking, for the orchestrator + the task-3 stager):
- R-1 (spec-literal divergence, declared): heartbeat-side input failures (corrupt last_activity_ts, unreadable heartbeat store) land in stalled:crashed, NOT unknown(reason) — C5 literally lists "unreadable heartbeat" as an unknown trigger. Deviation is deliberate (the rung-3 articulation names it), selftest-pinned (2f/7b), and fails toward ALARM (crashed outranks unknown in attention precedence — louder, never masked). Comprehension-reviewer (pending) is the designated arbiter; if strict C5 is enforced, task 3 wiring should distinguish store-unreadable (readdir throw) from store-empty.
- R-2 (missing pin): the A6 "no spawn — selftest-pinned" claim is half-true: the PROPERTY is verified (check 7) but no suite pins it against future regression. The plan Testing Strategy allocates "the no-spawn-on-GET pin" to server.selftest.js — must land with task 3 when the GET route exists.
- R-3 (trivial): builder evidence says the defect ask registry field stays "active" forever; the real folded field is "done" — either way deriveItemStatus provably ignores the declared field (check 9).

Verdict: PASS
Confidence: 8
Reason: PROVEN: all five suites independently re-run green with rc=0 matching claimed tallies (38/38, 19/19, 165/165, 32/32, 14/14); five adversarial falsification probes survived (damaged-plan-with-override, bogus-slug-with-done, future-timestamp, corrupt-heartbeat, roll-up mask attempts); real-data livesmoke derives the 18/18 archived ask complete/merged-is-deployed and a bogus slug unknown(absent); port byte-identical to the pre-existing oracle. Confidence capped at 8 (not 9) by residuals R-1/R-2 pending the comprehension-reviewer gate and the task-3 pin.
