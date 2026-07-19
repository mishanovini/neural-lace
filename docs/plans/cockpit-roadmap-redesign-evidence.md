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

## Task 3 — [serial] Roadmap tree view + the navigation shell

EVIDENCE BLOCK
==============
Task ID: 3
Task description: [serial] Roadmap tree view + the navigation shell. (Shell C2 / Tree per Outcome 2 / Build order A7+R2 / Roadmap-to-Request C6 / Recency I1 / Completed aging + markers I2 / Kanban I3+R5 / Harness-chore exclusion A9 / Four UI states C4 / Refresh model C7 / A11y C9.) Verification: full
Verified at: 2026-07-19T20:47:00Z
Verifier: task-verifier agent (adversarial re-derivation; builder claims in cockpit-roadmap-redesign-evidence-t3.md treated as UNVERIFIED and independently re-run; implementation = master d50f6fc build + cf91268 derive-lib splice)

Oracle: specified — plan task-3 text (C1/C2/C4/C6/C7/C9/A7/A9/I1-I3 + R1-R6 folded) + derived-preexisting — server.selftest.js (168) and derive-lib --self-test (56) as zero-regression oracles + implicit — the LIVE deployed surface on http://127.0.0.1:7733 exercised directly (real registry data, real derived statuses).

Comprehension-gate: articulation present and substantive (rung-3 articulation in cockpit-roadmap-redesign-evidence-t3.md: spec meaning / covered / NOT covered / assumptions); comprehension-reviewer runs as the orchestrator's SEPARATE gate per the dispatch — checkbox flip is PROVISIONAL on it. Rung: 3.

Checks run:
1. roadmap-routes.selftest.js re-run: 28 passed, 0 failed, rc=0 (S1-S13: real HTTP fixtures; corrupt-registry degrades to empty-but-ok never 500; operator-done labeled override; provenance classification; rank overlay + delegation). PASS
2. cockpit.selftest.js re-run: 146 passed, 0 failed, rc=0 (composed count incl. the T3-* block). PASS
3. server.selftest.js re-run SINGLE CLEAN RUN (the caller-pinned oracle for the known parallel-pressure flake): 168 passed, 0 failed, rc=0. PASS
4. derive-lib.js --self-test re-run: 56 passed, 0 failed, rc=0. PASS
5. LIVE GET /api/roadmap: HTTP 200 application/json in 14.8ms; ok:true; generated_at=2026-07-19T20:31:26.337Z; 23 items walked recursively — every status.value inside the six-value enum (complete:20, not-started:3), zero enum/shape violations; roll_up arrays well-formed (empty live — no attention states in current data; counted-class law pinned by T3-15/16/17). PASS
6. LIVE GET /roadmap.js: HTTP 200 text/javascript; charset=utf-8, 39748 bytes; GET / 200. PASS
7. Ground-truth probe (the plan's originating defect, inverted): ask-20260710-workstreams-rebuild (the archived 18/18 rebuild) renders status.value=complete, progress 18/18 — never ACTIVE; ask-level label honestly reads "complete (operator override)" (registry carries an operator done status — the labeled-override law); the plan-level child ask-rooted-workstreams-p1 derives complete through the real completion-oracle at plan granularity (neural-lace default merged-is-deployed per server/completion-oracle.js), NOT merged-unverified, NOT a no-signal fallback. PASS
8. Falsification probe C7 (state-preserving refresh): payload carries generated_at (live, check 5); web/roadmap.js renderAll() wraps EVERY re-render in captureUiState()/restoreUiState() (roadmap.js:744-760): details-open via live-maintained openSet (127, 439-441, roll-up groups 485-517), scroll scrollY+bodyScrollTop (691, 709-710), focus via data-focus-key re-query (605, 692-695, 725-731), uncommitted title edits INCLUDING selection range re-opened via openTitleEditor (696-702, 711-723), landing highlight re-applied (733-736); failure path sets lastFetchFailed, labels "derived <age> — STALE (last refresh failed)" (157) and keeps last-good DOM (renderErrorState only when !lastPayload, 770-791). Pinned by T3-26/T3-27. PASS
9. Falsification probe C2 (four-spec law, the C6 roadmap-to-request arrow): (i) target address — roadmap.js:295-301 "from your request(s): " links shell.navigate to hash request/<id>; (ii) landed state — app.js routeFromHash 1139-1161 snapshots the leaving tab (1158), activateTab + landOn, applyLanding 1066-1085 (highlight 1070, scrollIntoView 1081, tabindex -1 + focus 1082-1083), requests adapter landOn expands to the entry (1337+); (iii) return path — explicit back affordance injected on the landed item driving history.back() (1071-1079) AND browser Back via hashchange (1178) restoring expansion + scroll from viewSnapshots (1147-1153); (iv) miss behavior — landOn fallback 1131-1136, showMissBanner 1090-1114 (role=status + focus), requests-specific copy "resolved earlier — this request is no longer listed (completed, dismissed, or merged into another request)" (1353), never blank/404. Pinned by T3-4/5/6/7/8b. PASS
10. Falsification probe A6 (no spawn on GET): exactly TWO child_process sites in the composed chain — derive-lib.js:336 inside classifySessions (sole caller: server.js:991, the detail path; deriveItemStatus body contains NO spawn/classifySessions reference — only a comment) and roadmap-routes.js:532 inside runAskRegistryCli (sole callers: POST /api/roadmap/rank at 613 and POST /api/roadmap/title at 633). The GET /api/roadmap chain (handle:576, buildRoadmapPayload, readAskRegistry/deriveItemStatus/resolvePlanAbsPath/listRawHeartbeatsResult/readAskEvents) is pure fs-read/compute. Live corroboration: 14.8ms response (spawns measured 87ms-119s). PASS
11. A11y bindings C9: T3-14 asserts createElement('details') + createElement('summary') (native keyboard disclosure); T3-11 asserts status chips render TEXT from the label map via /STATUS_LABEL/ + /textContent/ (text + color, never color-only); T3-30 asserts the single btn() factory creates real button elements (>=10 uses, never click-on-bare-div); app.css button base rules carry min-height: 24px (app.css:71,105,109,116,136 — the chip floor real buttons inherit); T3-28b aria-live edit feedback; T3-29 keyboard move up/down real buttons (R2); T3-22/23b aria-pressed persisted toggles. PASS
12. RED evidence: roadmap.js/roadmap-routes.js did not exist before d50f6fc (git log: files created there) — the T3-* source assertions and roadmap-routes.selftest necessarily failed RED pre-build (builder-reported MODULE_NOT_FOUND; from-absent stated-reason accepted). Splice cf91268 extended fixtures, never weakened an assertion (HEARTBEAT_STATE_DIR sandbox + heartbeat fixture added). PASS
13. Server mount: server.js:50 require('./roadmap-routes.js') + server.js:1072 first-line dispatch "if (roadmapRoutes.handle(req, res)) return;" — the ONE mount line per fragment. Git: d50f6fc + cf91268 on master touching exactly the claimed files. PASS

Runtime verification: test neural-lace/workstreams-ui/server/roadmap-routes.selftest.js::full-suite
Runtime verification: test neural-lace/workstreams-ui/web/cockpit.selftest.js::full-suite
Runtime verification: test neural-lace/workstreams-ui/server/server.selftest.js::full-suite
Runtime verification: test neural-lace/workstreams-ui/server/derive-lib.js::self-test
Runtime verification: curl curl -s http://127.0.0.1:7733/api/roadmap
Runtime verification: curl curl -s -o /dev/null -w "%{http_code} %{content_type}" http://127.0.0.1:7733/roadmap.js
Runtime verification: file neural-lace/workstreams-ui/web/roadmap.js::captureUiState
Runtime verification: file neural-lace/workstreams-ui/web/app.js::applyLanding
Runtime verification: functionality-verifier 3::SKIP (rationale: agent not invocable from this verifier thread (no Task tool); the caller-directed LIVE deployed-surface probes (checks 5-7: real payload, real derived statuses, ground-truth 18/18 item) plus the builder's real-browser livesmoke (DOM probes landedFound/highlighted/focused/ancestorsOpen/returnAffordance all true, zero console errors) stand in as the user-shaped exercise; task-9 advocate pass remains the plan-level runtime acceptance)

DEPENDENCY TRACE
================
Step 1: user opens http://127.0.0.1:7733 — shell renders four tabs, Roadmap lands
  Verified at: live GET / 200 (check 6); T3-1/T3-2
Step 2: roadmap.js fetches /api/roadmap on load + 30s tick
  Verified at: roadmap.js load() 770-791; live 200 ok:true (check 5)
Step 3: server.js:1072 dispatches to roadmap-routes.handle, buildRoadmapPayload runs
  Verified at: check 13 (mount line); check 5 (payload served)
Step 4: buildRoadmapPayload calls derive-lib deriveItemStatus + completion-oracle (spawn-free)
  Verified at: checks 7 + 10 (real derived statuses; pure-read chain)
Step 5: tree renders six-value chips + roll-up badges + drill-downs; cross-view arrows land/return/miss
  Verified at: checks 8, 9, 11 (code-cited + selftest-pinned); builder livesmoke DOM probes

Git evidence:
  Files modified in recent history:
    - neural-lace/workstreams-ui/web/roadmap.js (created d50f6fc)
    - neural-lace/workstreams-ui/server/roadmap-routes.js (d50f6fc, spliced cf91268)
    - neural-lace/workstreams-ui/server/roadmap-routes.selftest.js (d50f6fc, spliced cf91268)
    - neural-lace/workstreams-ui/server/server.js (mount line, cf91268)
    - neural-lace/workstreams-ui/web/app.js, index.html, app.css, cockpit.selftest.js (d50f6fc)

Verdict: PASS
Confidence: 8
Reason: PROVEN: all four suites re-derived green rc=0 (28/146/168/56); the live deployed surface serves a clean six-value-enum payload with generated_at in 14.8ms; the originating 18/18-renders-ACTIVE defect is demonstrably inverted on real data; three adversarial falsification probes (C7 state-preservation, C2 four-spec arrow, A6 spawn-free GET) survived with code citations; C9 a11y assertions located and quoted. Confidence 8 not 9: no verifier-driven browser session this thread (builder's real-browser livesmoke + the task-9 advocate pass cover the interactive layer), and the comprehension gate is still pending.

Residuals (non-blocking, for the orchestrator):
  - R-t3-1: added_mid_build is always false in the live payload — task 1 shipped no insertion-marker derivation source; the T3-21 renderer + aging knob are built but can never fire live until a derive-lib export exists. Honestly declared by the builder (never invented). Needs a fold-in point (task-2 fragment lane or a backlog row) before task-9 acceptance.
  - R-t3-2: roll_up counted-class rendering exercised only via selftest fixtures — live data currently has zero attention states (verified: all 23 items complete/not-started). Acceptance scenario 6 (task 9) is the live exercise.

AMENDMENT (2026-07-19T20:55:00Z, same verifier thread, supersedes the Verdict above):
==============
Mid-verification the t3 gate-results file was concurrently updated: comprehension-reviewer
returned FAIL conf 6 with 2 PROVEN residuals (fix dispatch build/roadmap-t3-fix NOT yet on
master — verified: no fix commit after cf91268; branch absent locally). Per Decision 020d
(comprehension-gate FAIL propagates: no flip), the provisional checkbox flip executed minutes
earlier under the dispatch's "flip is provisional on it" clause is REVERTED in the same thread.
Both reviewer residuals independently CONFIRMED in master code by this verifier:
  - CG-1 (falsifies part of check 8's C7 claim): captureUiState captures the uncommitted title
    edit ONLY when the editor input is document.activeElement (roadmap.js:692-702); pendingEdit
    is set nowhere else (only restoreUiState:712, cleared:403). An OPEN-but-UNFOCUSED editor is
    wiped by renderAll's body.innerHTML='' on the 30s tick — the C7 law ("uncommitted title
    edits survive") is violated in that state. Check 8 verified the focused-editor path only.
  - CG-2 (narrows check 9's C2 claim): hash generation is unencoded (roadmap.js:301
    '#request/' + r.id; sibling generation sites likewise) while routeFromHash decodes
    (app.js:1156 decodeURIComponent) — an id containing % throws URIError and breaks routing.
    No live id currently contains % (23-item payload checked), so this is latent, but the
    four-spec law is a law.

Verdict: FAIL (supersedes the PASS above)
Confidence: 8
Reason: PROVEN: comprehension-gate FAIL with two code-confirmed gaps against binding C7/C2 laws;
the fix round is dispatched but not landed on master, so the composed master state does not yet
satisfy the task text. The verification-axis results above STAND (all four suites green rc=0;
live payload clean; ground-truth 18/18 inverted; A6 spawn-free GET; C9 pinned) — the re-verify
after the fix lands only needs: (a) re-run cockpit.selftest + roadmap-routes.selftest,
(b) confirm CG-1: an open-unfocused editor survives a tick (capture predicate by querySelector,
not activeElement), (c) confirm CG-2: encodeURIComponent at the hash generation sites paired
with the existing decode, (d) re-flip via a fresh evidence entry.
Checkbox state: reverted to unchecked in this thread; NOT flipped.

RE-VERIFY (2026-07-19T21:40:00Z, NARROW — the fix has landed on master)
==============
Task ID: 3
Task description: [serial] Roadmap tree view + the navigation shell. (Shell C2 / Tree per Outcome 2 / Build order A7+R2 / Roadmap-to-Request C6 / Recency I1 / Completed aging + markers I2 / Kanban I3+R5 / Harness-chore exclusion A9 / Four UI states C4 / Refresh model C7 / A11y C9.) Verification: full
Verified at: 2026-07-19T21:40:00Z
Verifier: task-verifier agent (narrow re-verify after the comprehension-fix landed; prior verification-axis PASS conf 8 STANDS per the AMENDMENT above and is not re-derived; this run closes the two comprehension gaps in composed master code + the D2 title-fold routing routed to task 3)

Oracle: derived-preexisting — cockpit.selftest.js (177) + roadmap-routes.selftest.js (30) re-run rc=0, both EXECUTING the real extracted source (not reimplementations); specified — task-2 title-precedence law ("operator ALWAYS outranks auto regardless of timestamp") exercised over a real HTTP GET /api/roadmap (S13); the comprehension-reviewer's own code-fix remediation as the closure oracle for the two FAIL gaps.

Comprehension-gate: PASS (remediation satisfied) — the prior comprehension-reviewer FAIL (conf 6, 2 PROVEN gaps) named code-fix as sufficient remediation; both gaps are now closed IN COMPOSED MASTER CODE and pinned by executing (RED-capable) tests: CG-1 (roadmap.js:705 captureUiState presence-gate) pinned by T3-27c/d/e; CG-2 (roadmap.js:304 + app.js:1231 encodeURIComponent, decode symmetry app.js:1201) pinned by T3-4b/c. Fixes on master c874421 (d81c4c1 lineage). No new articulation gap surfaced by the fix diff.

Checks run:
1. cockpit.selftest.js re-run (node web/cockpit.selftest.js): 177 passed, 0 failed — matches expected 177. PASS
2. roadmap-routes.selftest.js re-run (node server/roadmap-routes.selftest.js): 30 passed, 0 failed — matches expected 30. PASS
3. CG-1 fix in code + RED differential: captureUiState now captures the uncommitted title edit by PRESENCE — document.querySelector('.rm-title-input') (roadmap.js:705), independent of document.activeElement. Diff (c874421) confirms the pre-fix predicate was ae.classList.contains('rm-title-input') on document.activeElement, so a focus-on-Save-button state returned edit:null. T3-27c/d/e EXECUTE the real extracted CAPTURE-UI-STATE source in a vm sandbox: 27c (activeElement=Save button, input present) captures item-42 + value — RED against pre-fix; 27d (activeElement null, input present) captures — RED against pre-fix; 27e (no input) stays null (no false-positive). PASS
4. CG-2 fix in code + RED differential: both in-scope hash-generation sites encode the interpolated segment — roadmap.js:304 '#request/' + encodeURIComponent(r.id), app.js:1231 '#' + encodeURIComponent(t); decode symmetry preserved at app.js:1201 decodeURIComponent(m[2]). T3-4b builds a new Function from the REAL extracted navigate-arg source + REAL app.js ITEM_HASH_RE and round-trips an id containing '%25','#','/': lands as the exact original id without throwing — RED against the pre-fix raw-concat shape (which mis-decodes '%25' and throws URIError on a bare '%'). Third site roadmap.js:319 (shell.navigate(st.unblock.hash)) deliberately NOT wrapped — it passes an already-complete server hash string; encoding would double-encode the '#'/'/'delimiters. Documented in-code (roadmap.js:301-303 comment) + commit message. PASS
5. D2 (routed here by the task-2 verifier) — title-fold routes summary_updated by title_source: foldRegistryForRoadmap (roadmap-routes.js:184-187) routes a summary_updated with title_source:'operator' into operator_title, else auto_title; the served title prefers operator (roadmap-routes.js:399 reg.operator_title || reg.auto_title || ...) and reports title_source:'operator' when an operator title exists (roadmap-routes.js:406). So a later auto summary_updated (distiller re-run) only ever overwrites auto_title — operator outranks auto regardless of timestamp by slot construction. PASS
6. D2 end-to-end HTTP exercise (S13): the selftest appends an operator set-title (summary_updated + title_source:'operator', ts 07-15) then a NEWER auto summary_updated (title_source:'auto', ts 07-16, "distiller re-run, should be ignored"), then GET /api/roadmap over the real mounted route — asserts title === 'Alpha feature (operator title)' AND title_source === 'operator'. Green. Pre-fix routed every summary_updated into auto_title -> RED (title would be the distiller re-run, title_source 'auto'). S13b confirms a candidate_classified amendment label never retitles. PASS
7. Fixes present on master: git show confirms c874421 (t3: captureUiState presence-gate + hash encode symmetry) and cdafdc9 (t2: title-fold restricted + D2 summary_updated routing) on the current branch; d81c4c1 is the same-subject lineage. Working tree clean; files read = committed master. PASS

Runtime verification: test neural-lace/workstreams-ui/web/cockpit.selftest.js::full-suite (177/0)
Runtime verification: test neural-lace/workstreams-ui/server/roadmap-routes.selftest.js::full-suite (30/0)
Runtime verification: test neural-lace/workstreams-ui/web/cockpit.selftest.js::T3-27c-open-unfocused-editor-captured
Runtime verification: test neural-lace/workstreams-ui/web/cockpit.selftest.js::T3-4b-hash-encode-decode-round-trip
Runtime verification: test neural-lace/workstreams-ui/server/roadmap-routes.selftest.js::S13-operator-title-survives-newer-auto
Runtime verification: file neural-lace/workstreams-ui/web/roadmap.js::var openInput = document.querySelector('.rm-title-input')
Runtime verification: file neural-lace/workstreams-ui/web/app.js::navigate('#' + encodeURIComponent(t))
Runtime verification: file neural-lace/workstreams-ui/server/roadmap-routes.js::if (rec.title_source === 'operator') cur.operator_title = rec.summary

Verdict: PASS
Confidence: 9
Reason: PROVEN: both oracle suites re-run green at the expected composed counts (cockpit 177/0, roadmap-routes 30/0); the two comprehension-gate FAIL gaps are closed in composed master code and each pinned by a test that EXECUTES the real extracted source and is RED-capable against the pre-fix shape (CG-1 T3-27c/d/e vm-run captureUiState; CG-2 T3-4b new-Function round-trip of the real navigate-arg + real ITEM_HASH_RE); the D2 title-fold routing is correct in code (roadmap-routes.js:184-187/399/406) and exercised end-to-end over a real HTTP GET (S13) with a proven RED against the pre-fix shape. The prior verification-axis PASS (four suites green, live payload clean, ground-truth 18/18 inverted, A6 spawn-free GET, C9 pinned) STANDS unchanged. Confidence 9: oracle suites re-run + the fixed behaviors exercised via executing tests + the RED differential provable from the fix diff.
Checkbox state: FLIPPED to [x] in this thread — fresh evidence entry authorizes exactly this one flip.

## Task 7 — [serial] Event-triggered publish + person grouping

EVIDENCE BLOCK
==============
Task ID: 7
Task description: [serial] Event-triggered publish + person grouping (round 5, mechanics bound per A5): dirty marker at the WRITER-LIB seam; debounced publisher <=~1/min; floor runs the FULL cycle (exporter+push+pull) at <=600s REGARDLESS of marker; marker cleared BEFORE export; 900s lock-stale verified at 60s cadence; hostname->person map with named unassigned/map-error states. Verification: full
Verified at: 2026-07-19T21:25:00Z
Verifier: task-verifier agent (adversarial re-derivation; builder claims in cockpit-roadmap-redesign-evidence-t7.md treated as UNVERIFIED and independently re-run)

Oracle: specified — plan task-7 text (A5 i-iv absorbed, lines 283-306) + derived-preexisting — export-state.js suite 11/0 (file PROVEN unchanged by 133b8f4: git diff 133b8f4^ 133b8f4 -- export-state.js = 0 lines) and the REAL external-monitor-alert-surfacer.sh as coord-sync S3's oracle + differential — pre-T7 (65587d4) vs post-T7 (e6c6f86) vs composed-master (1232c20) pinned worktrees.

Comprehension-gate: rung 3; articulation present (all four canonical sub-sections in cockpit-roadmap-redesign-evidence-t7.md, gap-1/gap-2 amendments folded at cec3cb2); comprehension-reviewer runs as the orchestrator's SEPARATE gate per dispatch — this flip is PROVISIONAL on it; orchestrator holds the commit until both gates pass.

Checks run (all in PINNED worktrees at e6c6f86 [t7-iso] / 1232c20 [composed] / 65587d4 [pre-T7 baseline] — the shared main checkout was racing a concurrent session's t2/t3-int/t6 cherry-picks mid-run and is NOT a valid suite substrate; see Finding below):
1. Suite re-derivation, t7-iso (e6c6f86): progress-log-lib 41/0 rc=0 · ask-registry 26/0 rc=0 · coord-sync 21/0 rc=0 · peer-view 38/0 rc=0 · export-state 11/0 rc=0 · cockpit 139/0 rc=0 · server.selftest 165/0 x3, rc=0 each. Result: PASS
2. Composed master (1232c20): server.selftest 168/0 x3 · cockpit 146/0 (count growth = t2/t6 scenarios landed by the concurrent session). Result: PASS
3. A5(a) floor falsification — code trace: coord-sync.sh _main (:459-487) has exactly four action triggers (forced/event+floor/event/floor); the ONLY skip is clean AND floor_age<FLOOR_SECONDS; _run_cycle (:393-456) runs exporter+push+pull unconditionally (sole exporter-less path = documented skipped-no-coord-repo named degradation). PLUS mutation re-derivation: verifier applied a "naive if-clean-exit-0" mutant to _main and re-ran --self-test: S1 full-cycle + S6 floor scenarios FAIL (8 FAILs). The suite demonstrably catches the exact A5 failure mode (RED proven by verifier, not builder claim). Result: PASS
4. A5(b) clear-before-export: rm -f of DIRTY_MARKER_FILE at coord-sync.sh:412 precedes the step-1 exporter at :414-424; S7 stub re-dirties mid-export and asserts the NEXT fire republishes (lost-update prevention), green in re-run. Result: PASS
5. A5(c) keepalive-only-when-exporter-runs: export-state.js UNCHANGED by 133b8f4 (diff = 0 lines); exported_at keepalive rewrite lives inside runExport (export-state.js:215-235, KEEPALIVE_MS=60min) — only written when the exporter runs; peer-view classifyPeerState 80min unreachable boundary pinned by peer-view S1c/S1d. Floor 600s + 60min keepalive stays inside the 80min window. Result: PASS
6. A5(d) never-block direct probe: pl_emit with COORD_DIRTY_MARKER_FILE routed under a REGULAR FILE (un-creatable dir) -> emit_rc=0 AND the event landed in the sandboxed state jsonl; ask-registry override-project (a no-progress-event verb, the exact class hook-only placement would miss) with the same blocked marker -> rc=0, record appended; positive control with a creatable path -> marker created, content "ask-registry:project_override". Marker write path is pure fs, every failure swallowed (progress-log-lib.sh:387-398). Result: PASS
7. Livesmoke, REAL server.js on 127.0.0.1:7799 (CTREE_PORT override), fixture coord clone (3 peer exports: desktop/laptop/mystery-box) + fixture people.json {desktop:Misha,laptop:Misha}: GET /api/asks -> 200, peers.people_map_error="" and peers.persons=[{Misha:[desktop,laptop]},{unassigned:[mystery-box]}]. Then people.json OVERWRITTEN with broken JSON (no restart — per-request load): GET /api/asks -> 200, people_map_error="person map parse failed (people.json): Unexpected token..." (NAMES the failing component), all hosts under the named "unassigned" group, server survives repeated hits. Test server killed after (port verified down). Result: PASS
8. Rendered-output layer: cockpit PV-10..PV-15 pin renderPeerPersonGroups — the literal person + ": " + hosts-joined-" + " shape, unassigned group, visible map-error text, per-person localStorage persistence (I3), CSS classes — green in re-run (139/0 iso, 146/0 composed). Result: PASS
9. Scheduled-task path: install-coord-sync-task.ps1 -WhatIf ONLY (not registered): would register NL-CoordSync at 60s RepetitionInterval, MultipleInstances=IgnoreNew, ExecutionTimeLimit=5min, hidden-window vbs wrapper -> space-free .cmd -> coord-sync.sh at the real repo path. 900s LOCK_STALE > 300s ExecutionTimeLimit cross-file invariant pinned mechanically by coord-sync S9 (green). Result: PASS
10. No spawn on GET paths: grep of the full 133b8f4 workstreams-ui diff for spawn/spawnSync/exec/execSync/execFile/child_process/fork additions -> zero matches (rc=1). /api/asks peers block is a pure-read of the local clone (peer-view.js header contract). Result: PASS
11. Docs obligation (spec bullet "Coord-repo access for the second account documented"): docs/runbooks/coord-sync.md section "Second-account (second person's) coord-repo access" present in 133b8f4. Plan predates the Docs-impact field convention (0 occurrences in plan) — grandfathered. Result: PASS
12. FM catalog: FM-006 countered by this independent re-derivation; FM-023 is the pending comprehension gate's surface. Result: PASS

Runtime verification: test adapters/claude-code/hooks/lib/progress-log-lib.sh::--self-test (41/0)
Runtime verification: test adapters/claude-code/scripts/ask-registry.sh::--self-test (26/0)
Runtime verification: test adapters/claude-code/scripts/coord-sync.sh::--self-test (21/0)
Runtime verification: test neural-lace/workstreams-ui/server/peer-view.js::--self-test (38/0)
Runtime verification: test neural-lace/workstreams-ui/server/export-state.js::--self-test (11/0, unchanged-file regression oracle)
Runtime verification: test neural-lace/workstreams-ui/web/cockpit.selftest.js::PV-10..PV-15 (139/0 iso; 146/0 composed)
Runtime verification: test neural-lace/workstreams-ui/server/server.selftest.js::all (165/0 x3 iso; 168/0 x3 composed)
Runtime verification: curl -s http://127.0.0.1:7799/api/asks (real server.js, CTREE_PORT=7799 COORD_CLONE_DIR=fixture COCKPIT_PEOPLE_FILE=fixture; asserts peers.persons grouping + peers.people_map_error both healthy and malformed)
Runtime verification: file adapters/claude-code/scripts/coord-sync.sh::rm -f "$DIRTY_MARKER_FILE" (line 412, BEFORE the exporter at 414)
Runtime verification: file docs/runbooks/coord-sync.md::Second-account

DEPENDENCY TRACE
================
Step 1: any writer appends (pl_emit fresh append / _ar_append_record any verb)
  v Verified at: probe 6 positive control (marker created, tag ask-registry:project_override); progress-log-lib S17, ask-registry SQ
Step 2: dirty marker at ~/.claude/state/coord-sync/dirty (shared default with coord-sync.sh; COORD_DIRTY_MARKER_FILE overrides both ends)
  v Verified at: coord-sync.sh:162-166 + progress-log-lib.sh:370-381 (same path, PROVEN by read)
Step 3: next 60s fire -> trigger=event -> FULL cycle (exporter -> coord-push -> coord-pull)
  v Verified at: coord-sync S5b (REAL exporter/push/pull, no stubs, trigger=event logged, marker consumed)
Step 4: export lands in coord clone plan-export/<host>.json, reaches origin
  v Verified at: coord-sync S1 (file present + origin HEAD advanced)
Step 5: peer machine's server reads clone -> peer-view persons grouping -> GET /api/asks
  v Verified at: livesmoke (check 7) over real HTTP
Step 6: asks.js renderPeerPersonGroups renders "Misha: desktop + laptop" cards
  v Verified at: cockpit PV-10..15 (render-path pins, green)

Git evidence:
  133b8f4 build(roadmap-t7) on master (13 files, +979/-107): progress-log-lib.sh, ask-registry.sh, coord-sync.sh, install-coord-sync-task.ps1, docs/runbooks/coord-sync.md, config/{.gitignore,people.example.json,people.js}, server/{payload-schema.js,peer-view.js}, web/{app.css,asks.js,cockpit.selftest.js}
  Articulation amendments folded at cec3cb2 (comprehension gap-1 reword + gap-2 nl-issue row).

Finding (not a Task-7 gap, for the orchestrator): suite runs in the SHARED main checkout flaked (server 162/3, 164/4, 167/1 — S23d/S25c/S25d/S68, plan_progress fixture scenarios) while a concurrent session cherry-picked t2/t3-int/t6 into the same working tree; the same suite is 5/5 green at pinned 65587d4, 3/3 green at pinned e6c6f86, and green at 1232c20. PROVEN environment artifact (mid-checkout file states + selftest sandbox-port contention), not a regression. Verifiers/builders should pin a worktree when the checkout is shared.

Verdict: PASS
Confidence: 9
Reason: PROVEN: every suite re-derived green in pinned worktrees with direct rc; A5 i-iv each verified by code trace + executed probe (verifier-built if-clean-exit-0 mutant FAILS the suite; blocked-marker emit rc=0 with event landed; clear-before-export at :412; export-state.js diff empty with keepalive inside runExport); the user-shaped outcome (persons grouping + named map-error over live HTTP from the real server) observed both healthy and degraded. Checkbox flip PROVISIONAL on the orchestrator's separate comprehension gate.

Verdict: FAIL (supersedes the PASS above — harness-review F1, independently re-confirmed by this verifier)
Confidence: 9
Reason: PROVEN: mid-verification, the t7 companion recorded harness-review F1 (checkbox HELD directive, commit b652323); this verifier re-derived it against live master code rather than trusting the record: coord-push.sh:71 defaults COORD_PUSH_THROTTLE_SECONDS=600; coord-push.sh:288-290 skips the push and writes outcome=noop inside the window; coord-sync.sh:432 invokes plain `push` with no --force/override; coord-sync --self-test S1/S5b MASK the interaction by exporting COORD_PUSH_THROTTLE_SECONDS=0 (coord-sync.sh:518,663,681 — teaching-to-the-test on the exact composition that breaks). Consequence at production defaults: a second real status change within 600s of the last push is exported to the LOCAL clone but NOT published to origin until the throttle window expires — the round-5 heart ("publish within ~1min of a real status change"; acceptance scenario 5's "peer view on B updates within ~2 min") degrades to up to ~600s for consecutive events. Also starves A2c: throttled cycles write outcome=noop, resetting the local-commit streak during a genuinely-stuck episode. Fix dispatched (build/harness-reform-f123: coord-push push --force in _run_cycle + throttle-ACTIVE scenarios + distinct `throttled` outcome word) but NOT merged to master — done = merged with a SHA.
Every verification-axis result above STANDS (suites green in pinned worktrees; A5 i-iv probes; livesmoke; -WhatIf; no-spawn; mutant kill). Re-verify after F1 lands only needs: (a) confirm _run_cycle's push leg bypasses/overrides the throttle on event-triggered cycles, (b) confirm at least one coord-sync scenario runs with the throttle ACTIVE (no THROTTLE=0 mask) and asserts the event publish reaches origin within one fire, (c) confirm the throttled outcome word no longer resets the A2c streak, (d) re-run coord-sync + server suites, (e) re-flip via a fresh evidence entry.
Checkbox state: flip REVERTED to unchecked in this thread (flipped provisionally at 21:2x, reverted on F1 confirmation).
Gaps:
  - F1 composition defect (Class: teaching-to-the-test / composed-system functionality gap; Sweep query: grep -rn "COORD_PUSH_THROTTLE_SECONDS=0" adapters/claude-code/scripts/ — every selftest override of a sibling's production default is a mask candidate; Required generalization: E2E scenarios must run at least one leg with ALL sibling defaults active, or pin the composed latency contract mechanically.)
