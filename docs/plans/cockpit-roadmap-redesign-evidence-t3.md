# Evidence + rung-3 articulation — cockpit-roadmap-redesign Task 3 (+ integration splice)

Task: 3. Roadmap tree view + navigation shell (Verification: full, rung 3)
Builder: plan-phase-builder (Fable), commit 75aab40 (build/roadmap-t3) → master d50f6fc.
Integration splice: separate sonnet dispatch, commit aae558a (build/roadmap-t3-int) →
master cf91268 (fragment §1 server.js mount + §2 stub→derive-lib swap).
DEPLOYED LIVE: :7733 restarted at the composed state; /api/roadmap 200 with real derived
items; /roadmap.js 200. Gates: pending.

## Builder-reported evidence (gates re-derive)
- T3 build: cockpit.selftest 133/0 (40 new T3-*, RED confirmed pre-build);
  roadmap-routes.selftest 28/0 (NEW, real fixtures, real HTTP; RED = MODULE_NOT_FOUND);
  server.selftest 165/0, plan-parse 14/0 (no regressions).
- T3 livesmoke (real browser, fixture server): DOM probes {landedFound, highlighted,
  focused, ancestorsOpen, returnAffordance} ALL TRUE for #roadmap/ask-alpha/demo-plan/2;
  kanban columns ["Not started (0)","In progress (1)","Stalled (0)","Merged — deploy
  unverified (1)","Status unknown (1)","Complete (1)"]; rank move reordered; #inbox/ny-1
  landed focused, count (1) excluded lint-quarantined; Back restored expansion; zero
  console errors. Live-caught bug fixed red→green: all-children-unknown intent rendered
  confident "not started" → now unknown(reason) (S4d).
- Splice: four suites rc=0 composed (28/133/165/56); real live server curl proof;
  statusObj wraps real deriveItemStatus at every decision point EXCEPT task-level done
  (unconditional checkbox→complete — oracle applies at plan/intent granularity per pinned
  contract); task-level not-done now heartbeat-classified (sessions threaded from
  task_started session_id; heartbeats read once per request via listRawHeartbeatsResult);
  plan/intent all-done → real completion-oracle; mapDerivedValue() isolates the naming
  translation merged-deploy-unverified→merged-unverified; added_mid_build left false
  (no derive-lib export — honest gap, not invented).
- Fixture extension (not weakened assertion): HEARTBEAT_STATE_DIR sandboxing + fresh
  heartbeat fixture for sess-op-1 (real derive-lib requires heartbeat evidence where the
  stub trusted a bare task_started).

## Rung-3 articulation (T3 builder, condensed; splice paragraph above = the integration
articulation)
**Spec meaning:** one registry/three views; every cross-view arrow ships
address/landed/return/miss; statuses render derived truth only.
**Edge cases covered:** unknown-never-confident (incl. all-children-unknown);
merged-unverified OUTSIDE Complete with labeled override; filtered-vs-true empty;
win-only-on-success (interim inbox); STALE-no-DOM-wipe; edge-rank no-op; kanban
nested-target switches to tree.
**NOT covered:** stalled reasons/heartbeat in-progress/oracle classes/added_mid_build
(t1's derive-lib — renderer + roll-up plumbing ready; SPLICE CLOSED most of this — gates
verify the composed state); title persistence (t2's set-title landed after — endpoint
delegation live via t3-int; UI surfaces named error if verb absent); full Inbox/Requests
anatomies (tasks 4/5 register via WorkstreamsShell.registerView).
**Assumptions:** t1 replaces STUB-STATUS honoring the pinned contract (HAPPENED — splice);
rank overlay interim until registry roadmap_rank records exist (precedence registry-first
by construction).

## Gate results
### task-verifier (Fable): verification axis PASS conf 8, OVERALL FAIL pending the comprehension fix round — all 4 suites re-derived green rc=0 (28/146/168/56); live :7733 probes clean (payload 14.8ms, six-value enum 0 violations, generated_at present; 18/18 ground truth renders complete — defect inverted); falsification probes C7/C2/A6 survived on the paths exercised + C9 assertions quoted; BOTH comprehension residuals independently code-confirmed (CG-1 open-unfocused editor wiped by tick — activeElement-only capture, roadmap.js:692-702; CG-2 decode-without-encode, roadmap.js:301 vs app.js:1156). Provisional checkbox flip REVERTED per Decision 020d (comprehension FAIL = no flip). Re-verify after build/roadmap-t3-fix lands = suites + the two targeted checks; full block + amendment in cockpit-roadmap-redesign-evidence.md.
### comprehension-reviewer (Fable): FAIL conf 6 — 2 narrow PROVEN residuals, CODE-direction fixes dispatched (sonnet build/roadmap-t3-fix): (1) open-but-unfocused title editor wiped by 30s tick (capture predicate → querySelector, not activeElement); (2) hash id decode-without-encode asymmetry (% URIError; encode at 3 generation sites). All heavyweight probes ruled FAITHFUL (task-done oracle granularity, mapDerivedValue seam, added_mid_build). 5 non-blocking notes in reviewer transcript.
