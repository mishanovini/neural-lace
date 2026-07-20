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

## Task 2 — [serial] Work-item layer

EVIDENCE BLOCK
==============
Task ID: 2
Task description: [serial] Work-item layer. Titles (A3): auto-distilled, always operator-editable, title_source auto|operator; fold rule operator ALWAYS outranks auto regardless of timestamp; UI title edit delegates to ask-registry.sh. Amendment capture (A2) three layers: mechanical UserPromptSubmit candidate splice, async classification, operator correction + `amend` verb. Amendment correction (I6): detach affordance. Merge/split of asks into items. Verification: full
Verified at: 2026-07-19T22:10:00Z
Verifier: task-verifier agent (NARROW DELTA RE-VERIFY of the prior FAIL conf 9 defect D1 — amendment-label-as-title fold; everything else from the prior run stands verified per caller scope)

Oracle: derived-preexisting + derived-metamorphic — the pinning selftest suites (derive-lib #21, roadmap-routes S13/S13b, server T2-A3a/b/c, ask-registry Scenario V) AS the fold contract, PLUS a fresh independent A2 metamorphic probe (monotonicity/inclusion: appending a NEWER non-title-bearing record carrying an amendment LABEL in `summary` MUST NOT change the folded title) run by the verifier against BOTH fold paths, differentially RED against the pre-fix code (cdafdc9^) and GREEN against current master.

Comprehension-gate: PASS (delta) — rung 3; comprehension side already authorized on record (delta PASS conf 8), per caller scope; this narrow re-verify addresses the functionality defect D1 only.

Checks run:
1. FOLD CONTRACT header names the title-bearing types
   Command: read adapters/claude-code/scripts/ask-registry.sh:167-178
   Output: "TITLE-BEARING RECORD TYPES ... applies ONLY to `record_type == \"created\"` ... and `record_type == \"summary_updated\"` ... candidate_classified and amended ... is NOT title-bearing and MUST NOT be read into the folded title"
   Result: PASS
2. derive-lib.js foldAskRegistry restricts the fold (line 134): `if (rec.summary && (rec.record_type === 'created' || rec.record_type === 'summary_updated'))` with operator-beats-auto precedence (lines 135-139)
   Result: PASS
3. roadmap-routes.js foldRegistryForRoadmap: generic summary fold restricted identically (line 152); summary_updated routed to operator_title/auto_title by title_source (lines 184-187); title_set kept back-compat only (no writer produces it)
   Result: PASS
4. INDEPENDENT A2 falsification probe — GREEN (current master)
   Command: node scratchpad/probe-a2.js (fresh mkdtemp sandbox; created/auto title t0 + candidate_classified label t2 + amended label t3, both title_source empty)
   Output: derive-lib folded title == "Original auto title", title_source == "auto"; roadmap-routes summary == "Original auto title", auto_title == "Original auto title", operator_title empty. ALL PROBES PASSED, rc=0
   Result: PASS
5. SAME probe — RED (pre-fix code cdafdc9^, extracted to temp, requires resolved in-place)
   Command: node scratchpad/probe-red.js
   Output: PRE-FIX derive-lib folded title == "LABEL: rename the widget"; PRE-FIX roadmap summary == "LABEL: rename the widget" — the amendment label clobbered the real title. RED demonstrated: derive-lib=true roadmap=true, rc=0
   Result: PASS (probe discriminates; the fix is not a no-op)
6. derive-lib --self-test: 57 passed, 0 failed, rc=0 (pins #21 classified-amendment-does-not-retitle)
   Result: PASS
7. roadmap-routes.selftest: 30 passed, 0 failed, rc=0 (pins S13 operator-survives-newer-auto + title_source:operator, S13b label-never-retitles)
   Result: PASS
8. ask-registry --self-test: 45 passed, 0 failed, exit=0 (Scenario V production-shape title+timeline pipeline: created/auto -> set-title/operator -> candidate/pending -> detached -> amended)
   Result: PASS
9. server.selftest single run: 168 passed, 0 failed, rc=0 (pins T2-A3a operator survives newer auto, T2-A3b title_source labeled operator, T2-A3c auto-only keeps last-non-empty-wins)
   Result: PASS

Runtime verification: test neural-lace/workstreams-ui/server/derive-lib.js::--self-test (57/0, #21 classified-amendment-does-not-retitle)
Runtime verification: test neural-lace/workstreams-ui/server/roadmap-routes.selftest.js::S13,S13b (30/0)
Runtime verification: test adapters/claude-code/scripts/ask-registry.sh::--self-test (45/0, Scenario V title+timeline pipeline)
Runtime verification: test neural-lace/workstreams-ui/server/server.selftest.js::T2-A3a,T2-A3b,T2-A3c (168/0)
Runtime verification: file adapters/claude-code/scripts/ask-registry.sh::TITLE-BEARING RECORD TYPES

DEPENDENCY TRACE
================
Step 1: an ask is registered with an auto-distilled title, then an amendment is classified (label stamped into `summary`, title_source empty)
  v Verified at: probe-a2.js sandbox registry (created + candidate_classified + amended records)
Step 2: a reader folds the registry to the ask's CURRENT title
  v Verified at: derive-lib.js foldAskRegistry:134 + roadmap-routes.js foldRegistryForRoadmap:152 (title-bearing types only)
Step 3: the folded title the user sees is the real title, NOT the amendment label
  v Verified at: probe-a2.js GREEN (both paths return "Original auto title"); probe-red.js proves pre-fix returned the label (differential)

Git evidence:
  Fix landed at cdafdc9 fix(cockpit-roadmap-redesign t2): title-fold restricted to title-bearing record types (D1/D2)
    - neural-lace/workstreams-ui/server/derive-lib.js (foldAskRegistry guard + operator-beats-auto)
    - neural-lace/workstreams-ui/server/roadmap-routes.js (foldRegistryForRoadmap guard + title_source routing)
    - neural-lace/workstreams-ui/server/roadmap-routes.selftest.js (S13/S13b added, 28->30)
    - adapters/claude-code/scripts/ask-registry.sh (FOLD CONTRACT header names created/summary_updated)

Verdict: PASS
Confidence: 9
Reason: PROVEN: the prior FAIL's sole defect D1 (any-non-empty-summary fold let an amendment label replace the ask's title) is fixed in BOTH fold paths; the verifier's own fresh A2 probe returns the original title against current master AND was proven to return the amendment label against the pre-fix code (cdafdc9^) — a differential test against the pre-fix oracle, not a self-referential green. The FOLD CONTRACT header names the two title-bearing record types (created/summary_updated). All four pinning suites green at expected counts with direct rc (derive-lib 57, roadmap-routes 30, ask-registry 45, server 168). D2 was routed to task 3 per the prior run and is out of this delta's scope. Comprehension side already authorized (delta PASS conf 8 on record).

## Task 6 — [serial] Badge law + badge-storm fix
EVIDENCE BLOCK
==============
Task ID: 6
Task description: Badge law + badge-storm fix: renderer caps telemetry to ONE counted, labeled chip per belief-changing class (bookkeeping classes → Harness Health only); auditor's unmatched_dispatch oracle age-bounded to the marker-retention horizon.
Verified at: 2026-07-19T15:10:00-07:00
Verifier: task-verifier agent (NARROW RE-VERIFY of the fix round 3c45d62; prior-run badge-storm-cap + auditor age-bound PROVEN conf 9 stand)

Oracle: specified (Acceptance Scenario 4 + proposal §5: bookkeeping classes render NOWHERE on the board, their counted summary in Harness Health; belief-changing classes → ONE counted labeled chip) + derived-metamorphic (RED: pre-fix code → 170/9 failing on exactly the new scenarios; GREEN restored → 179/0). The oracle was exercised directly by extracting the REAL render blocks (BADGE-LAW-RENDER + BOOKKEEPING-DIAG) and running them in a vm sandbox against adversarial fixtures — behavior, not source-regex.

Comprehension-gate: delta re-review dispatched IN PARALLEL by the orchestrator (prior run's comprehension-reviewer FAIL conf 5 — eager 718-div drill-down / "invulnerable by construction" overclaim — addressed by the DRILL_DOWN_LINE_CAP(50)+"+K more" CODE fix in 3c45d62). This narrow functionality re-verify does NOT re-run the comprehension gate; per the orchestrator's explicit instruction the commit is HELD until BOTH this verdict and the comprehension delta land. Checkbox flip here represents the functionality axis only; the orchestrator's commit-hold is the compensating control.

Checks run:
1. cockpit.selftest.js composed suite (re-run, direct rc)
   Command: node neural-lace/workstreams-ui/web/cockpit.selftest.js
   Output: self-test summary: 186 passed, 0 failed
   Result: PASS (matches the 186 composed expected)
2. server.selftest.js single-run (re-run, direct rc)
   Command: node neural-lace/workstreams-ui/server/server.selftest.js
   Output: self-test summary: 168 passed, 0 failed
   Result: PASS (matches the 168 single-run expected)
3. INDEPENDENT falsification harness (verifier-authored, NOT builder's suite) — extracts the real
   BADGE-LAW-RENDER block from asks.js + the BOOKKEEPING-DIAG block from app.js verbatim into a
   vm sandbox with a fake DOM, exercises the delta scenarios directly:
   Command: node <scratchpad>/verify-t6.js
   Output: 16 passed, 0 failed —
     (a)  700 pure unmatched_dispatch (Scenario 4's shape) → renderDriftBadges returns null → ZERO board chips (suppression, NOT cap)
     (a2) 700 across all 3 bookkeeping classes → null (ZERO chips)
     (b)  mixed 700 bookkeeping + 12 belief-changing → exactly ONE chip "log_ahead_task_not_flipped ×12" (only the belief-changing class)
     (c)  100-member belief-changing drill-down → ONE chip ×100, drill-down body exactly 51 elements (50 lines + "+50 more"), last line = "+50 more" (the comprehension-gate gap)
     (d)  one-chip law holds: 718 identical belief-changing → ONE chip ×718, drill-down still capped at 51 (no unbounded 718-div storm)
     (e)  unranked/future class defaults VISIBLE (safe direction, never silently hidden)
     (f)  classless legacy badge → visible under "drift ×2" (never silently dropped)
     (g)  3 belief-changing classes → 3 chips, ranked-first then stable-alpha (precedence orders, never masks)
     (h)  asks.js BOOKKEEPING set = the auditor bookkeeping trio exactly
     (H1) Harness Health half: 700 suppressed → bookkeepingDivergenceSummary = {total:700, classCount:1}
     (H2) aggregate across asks, belief-changing excluded: 3+2 → {total:5, classCount:2}
     (H3) app.js and asks.js BOOKKEEPING_DIVERGENCE_CLASSES literals identical
   Result: PASS
4. Harness Health count render wiring (code-read + T6H-*)
   Command: file asks.js:990-991 (null-safe append) + auditor.js:1158 (badges_by_ask exposed) + app.js:990-995 (bookkeepingRow)
   Output: renderDriftBadges → null on all-suppressed → statusRow never gets an empty container (asks.js:991); auditor exposes state.badgesByAsk as badges_by_ask via getDiagnostics (auditor.js:1158); renderDiagnostics reads d.badges_by_ask → bookkeepingDivergenceSummary → appends "progress-log bookkeeping divergences: N (K class(es))" (app.js:990-995)
   Result: PASS
5. Belief-changing one-chip law (prior run) — re-confirmed by check 3(d)/(g); Result: PASS
6. Auditor unmatched_dispatch age-bound to marker-retention horizon — PROVEN conf 9 in the prior run (S7/S7c/S7d/S7e green); OUT of this narrow delta's scope, stands.

Runtime verification: test neural-lace/workstreams-ui/web/cockpit.selftest.js::T6-1 (700 bookkeeping → ZERO board chips, suppressed not capped)
Runtime verification: test neural-lace/workstreams-ui/web/cockpit.selftest.js::T6-2 (mixed bookkeeping+belief-changing → only the belief-changing chip)
Runtime verification: test neural-lace/workstreams-ui/web/cockpit.selftest.js::T6-6 (drill-down body capped at 51, not 718)
Runtime verification: test neural-lace/workstreams-ui/web/cockpit.selftest.js::T6H-2 (Harness Health half: 700-bookkeeping fixture → {total:700, classCount:1})
Runtime verification: test neural-lace/workstreams-ui/server/server.selftest.js::S7d (unmatched_dispatch beyond retention horizon → NO badge)

DEPENDENCY TRACE
================
Step 1: a card accumulates N drift badges (700 bookkeeping / mixed)
  ↓ Verified at: asks.js:990 renderDriftBadges(ask.drift_badges)
Step 2: bookkeeping classes filtered out BEFORE grouping; zero survivors → null
  ↓ Verified at: asks.js:303-307 (BOOKKEEPING_DIVERGENCE_CLASSES filter) + independent harness (a)/(a2)
Step 3: user-visible board shows ZERO chips for all-bookkeeping; ONE counted labeled chip per surviving belief-changing class; drill-down ≤ 51 elements
  ↓ Verified at: asks.js:991 null-safe append + independent harness (b)/(c)/(d) asserting rendered summary.textContent + body child count
Step 4: the suppressed count surfaces in Harness Health
  ↓ Verified at: auditor.js:1158 badges_by_ask → app.js:990-995 bookkeepingRow + independent harness (H1)/(H2) + T6H-2/T6H-3/T6H-5

Git evidence:
  Fix landed at 3c45d62 fix(cockpit-roadmap-redesign t6): bookkeeping suppression + drill-down cap (fix round)
    - neural-lace/workstreams-ui/web/asks.js (renderDriftBadges: bookkeeping suppression + DRILL_DOWN_LINE_CAP)
    - neural-lace/workstreams-ui/web/app.js (BOOKKEEPING-DIAG block + bookkeepingRow in renderDiagnostics)
    - neural-lace/workstreams-ui/web/cockpit.selftest.js (T6-1..T6-6c revised + T6H-1..T6H-5 new)
    - docs/plans/cockpit-roadmap-redesign.md (in-flight entry for the app.js diagnostics-pane touch)

Verdict: PASS
Confidence: 9
Reason: PROVEN: the prior run's sole FAIL basis (Acceptance Scenario 4's bookkeeping board-suppression unbuilt — the first pass CAPPED to one chip rather than SUPPRESSING to zero) is fixed at 3c45d62 and independently falsified. The verifier extracted the REAL render blocks verbatim and ran them in a vm sandbox against Scenario 4's exact 700-bookkeeping shape → ZERO board chips (null wrap, null-safe at the call site so no empty container), mixed → only the belief-changing chip, the comprehension-gate's 718-div drill-down storm → capped at 51 (50 + "+50 more"), and the Harness Health count → {total:700, classCount:1} from the same suppressed data. Multiple adversarial probes (unranked/future class, classless legacy, precedence ordering) failed to break the one-chip-per-belief-changing-class law or leak a suppressed class onto the board. Composed cockpit.selftest 186/0 + server.selftest 168/0 at the mandated counts with direct rc. HYPOTHESIZED-only residual (out of this delta's scope, orchestrator-held): the comprehension delta re-review — the orchestrator holds the commit until it lands (REFUTED if that re-review returns FAIL, in which case this checkbox flip is premature and the orchestrator's hold prevents the bad commit).

---

## Task 5 — Requests ledger view — NARROW RE-VERIFY (delta after dca80ed splice fix)

EVIDENCE BLOCK
==============
Task ID: 5
Task description: Requests ledger view (timeline anatomy I6, became→ #roadmap/<id> arrow, C8 findability filter + age-grouped closed, I1 recency, C4 four-states, C9 a11y) — Verification: full, rung 3
Verified at: 2026-07-19T22:27:24Z
Verifier: task-verifier agent (narrow re-verify — prior run FAILed on ONE defect; server surface 25/0 + falsification probes a-d STAND from that run)

Oracle: specified — the plan's User-facing Outcome §1 (Requests view) + the four-spec cross-view arrow law (target/landed/return/miss); exercised as a live browser render against the running cockpit on :7733.

Comprehension-gate: PASS (confidence 8) — on record from the prior run (rung 3); not re-invoked for this render-only delta (no source-logic change since — dca80ed moved one <script> line only).

Checks run:
1. index.html tag position + not-inside-comment (delta 1)
   Command: read neural-lace/workstreams-ui/web/index.html lines 40-50, 283-291 + grep requests.js
   Output: ONLY occurrence at line 289 = <script src="/requests.js"></script>, immediately after <script src="/roadmap.js"></script> (line 288), before </body> (line 290). Comment block (lines 41-46) no longer contains the tag. git show dca80ed confirms: tag removed from inside the comment, re-added after roadmap.js (1 insertion / 1 deletion).
   Result: PASS
2. Real browser render (headless Chrome via puppeteer-core) against http://127.0.0.1:7733/#requests (delta 2)
   Command: node scratchpad/probe.js (executablePath=C:/Program Files/Google/Chrome/Application/chrome.exe)
   Output: document.scripts = [asks, todo, backlog, app, roadmap, requests].js IN ORDER (requests.js is now a LIVE PARSED script — prior FAIL had it absent); ledgerMounted=true (#requestsLedgerSection present — prior FAIL had it absent); filterPresent=true; section heads = ["Open (3)","Closed (1)"] (2 heads); state chips = 4; rows = 4.
   Result: PASS
3. Filter narrows on a typed term (wired≠reached≠behaving — output changes across states)
   Command: type "reboot" into #requestsFilter (dispatch input) → observe; then clear
   Output: rowsAfterFilter=1, sectionHeadsAfterFilter=["Open (1)"] (Closed head gone), filteredRowTitle=["The computer rebooted."]; clear → rowsAfterClear=4. Rendered output observably DIFFERENT across filter states.
   Result: PASS
4. Miss behavior on a gone id (C3 — four-spec arrow law)
   Command: set location.hash=#request/ask-nonexistent-gone-999 → observe #requestsMissBanner
   Output: missBannerVisible=true, text="This request is no longer in the ledger — it may have been merged, cleared, or never existed." (requests.js's own missInfo — confirms its registerView replaced app.js's placeholder). Never blank/404.
   Result: PASS
5. Composed selftest, direct rc (delta 3)
   Command: node neural-lace/workstreams-ui/web/cockpit.selftest.js ; echo rc=$?
   Output: "self-test summary: 205 passed, 0 failed" rc=0. (Count is 205 not the prompt's 186 because concurrent T6/T8 blocks landed in the shared file since — growth, not regression; 0 failed.) Task-5's own T5-1..T5-24 block = 24/24 PASS, incl. T5-1 pinning the exact <script src="/requests.js"> ordered after app.js/roadmap.js. The 3 "FAIL"-substring lines (R22/R24/R25) are PASS-line descriptions naming historical bugs, not failures.
   Result: PASS
6. Out-of-scope observation (surfaced, non-blocking): one 500 in the console — GET /api/todo (the standalone My-To-Do pane, task 4/8 territory), NOT /api/requests (which returns 200). Does not touch the Requests ledger, which rendered fully. Outside task-5 delta scope.

Runtime verification: file neural-lace/workstreams-ui/web/index.html::<script src="/requests.js">
Runtime verification: curl http://127.0.0.1:7733/api/requests
Runtime verification: test neural-lace/workstreams-ui/web/cockpit.selftest.js::T5-1
Runtime verification: functionality-verifier 5::PASS (live-browser render on :7733 — ledger mounts, Open/Closed heads, filter narrows, gone-id miss banner; prior run's server 25/0 + probes a-d STAND)

DEPENDENCY TRACE
================
Step 1: operator opens the cockpit Requests tab (http://127.0.0.1:7733/#requests)
  ↓ Verified at: probe.js — document.scripts includes /requests.js after /roadmap.js (index.html:289)
Step 2: requests.js self-mounts + registers the 'requests' view adapter, fetches /api/requests
  ↓ Verified at: probe.js — #requestsLedgerSection present, 4 rows rendered from live payload; requests.js:124 insertBefore, :571 registerView
Step 3: operator sees Open/Closed sections, filters, and follows a stale link
  ↓ Verified at: probe.js — Open(3)/Closed(1) heads; "reboot" narrows to 1 row; #request/gone → honest miss banner (requests.js:480/491 heads, :146 itemMatches, :580 missInfo → app.js:1135 showMissBanner)

Git evidence:
  Files modified in recent history:
    - neural-lace/workstreams-ui/web/index.html  (fix commit: dca80ed, 2026-07-19 — the splice-position correction this delta re-verifies)

Verdict: PASS
Confidence: 9
Reason: PROVEN: the prior run's sole FAIL basis (the <script src="/requests.js"> tag was spliced INSIDE index.html's comment block, so the view never mounted in a real browser — document.scripts lacked requests.js, #requestsLedgerSection was absent) is fixed at dca80ed and INDEPENDENTLY re-derived here in a real headless-Chrome render against the running :7733 server: requests.js is now a live parsed script in correct order, the ledger mounts, Open(3)/Closed(1) heads render, the filter narrows the rendered rows across states, and a gone-id shows the honest miss banner (never blank/404). Composed cockpit.selftest 205/0 with direct rc=0 (T5 block 24/24). The prior run's server-surface 25/0 + live curl + falsification probes a-d STAND. Two adversarial probes this run (filter narrowing showing output change; gone-id miss banner) were attempted and did not break. Out-of-scope residual (non-blocking): a 500 on /api/todo (My-To-Do pane, task 4/8), not /api/requests (200) — does not affect the Requests ledger.

---

## Task 4 — Inbox view + context contract enforcement

EVIDENCE BLOCK
==============
Task ID: 4
Task description: Inbox view + context contract enforcement (A1/A8/A10/C3/C4/I4/I5 + delta residuals).
Verified at: 2026-07-19T18:05:00-07:00
Verifier: task-verifier agent

Oracle: specified — the deployed live cockpit at http://127.0.0.1:7733 (#inbox rendered DOM) is the user-facing source of truth; derived — the pre-existing needs-you.sh cold-reader lint field (lint_warnings) and the auditor filed-once state are the classifier oracles. Verification against current master HEAD (62bb460 core + 362f471 splice + a9f0cdf comprehension gate + 7cc793a My-items/pane-retirement + 0913cf0 backlog), which is what is deployed on :7733.

Comprehension-gate: PASS (confidence 8) — recorded separately on commit a9f0cdf ("gate(cockpit-roadmap-redesign t4): comprehension PASS conf 8 — flip awaits verifier only"); orchestrator runs the comprehension gate as a distinct gate and holds the commit until both pass. This verdict covers functional verification.

Checks run:
1. Suite re-runs (all re-executed by verifier, not trusted from builder claim):
   - inbox-routes.selftest.js: 23 passed, 0 failed (rc=0)
   - cockpit.selftest.js: 242 passed, 0 failed (rc=0)
   - server.selftest.js single-run: 173 passed, 0 failed (rc=0)
   - HARNESS_SELFTEST=1 needs-you.sh --self-test: 45 passed, 0 failed (rc=0) — incl. T24b (interactive add BLOCKS), T24c (blocked add writes NOTHING, count unchanged), T24 (mechanical never blocks)
   - auditor.js --self-test: 44 passed, 0 failed (rc=0, completed WITHOUT the prior env-hang) — S9a-i quarantine/filed-once suite
   - session-honesty-gate.sh --self-test: 40 passed, 0 failed (Scenario 21: PAUSING marker -> needs-you.sh add actually called) — the load-bearing --section decision mechanical caller
   - session-resumer.sh --self-test: 69 passed, 0 failed
   - stop-verdict-dispatcher.sh --self-test: 73 passed, 0 failed (env-slow on git fixtures, completed)
   Result: PASS
2. LIVE curl http://127.0.0.1:7733/api/inbox: ok:true, ledger_present:true, answerable:3, quarantined:1. answerable[0] carries full §3 anatomy (title/context/options via reply_with/my_pick/reply_channel); quarantined item carries lint_warnings ["no-context"], humanized lint_reasons, defect_filed:true; resolved items absent (buildInboxPayload excludes state!==open). Result: PASS
3. Browser render (headless Chrome / puppeteer-core, deployed :7733 #inbox): tabCount "(3)" = answerable only; section heads = ["Awaiting your answer (3)", "1 arrived without context — defects filed against the producing sessions", "My items (1 open)"]; 3 answerable rows, 1 quarantine row; SYSTEM-failure framing "The system could not classify this as answerable — it arrived without enough context."; defect line "A defect has been filed against the producing session." (matches auditor real filed state, never claimed early); win state absent (answerable non-empty); no JS errors. Count EXCLUDES both the 1 quarantined and the 1 My-item. Result: PASS

Falsifications attempted (verifier's own, all survived):
  (a) A1 interactive-block vs mechanical-quarantine — sandboxed NEEDS_YOU_STATE_DIR: interactive anchorless add ("Ship tonight? My pick: yes." no --mechanical) -> exit 1, BLOCKED, 0 items written; identical text --mechanical -> exit 0, stored with lint_warnings ["no-context","no-anchor","no-outcomes"]. All three mechanical callers grep-confirmed passing --mechanical at the correct call sites (session-honesty-gate.sh:496 --section decision [load-bearing]; stop-verdict-dispatcher.sh:1195-1197 --section inflight; session-resumer.sh:957-959 --section inflight) + one self-test scenario each. SURVIVED.
  (b) A8 filed-once — auditor S9f: a SECOND cycle over the SAME still-open quarantined items does NOT re-file (once per item lifetime, keyed by 'quarantine-<ledger id>'); S9d/S9e legacy no-producer item keys against the ledger id; S9g/S9i recurrence escalates once then does NOT re-escalate. SURVIVED.
  (c) C3 stale-link — missInfo renders "resolved earlier — no longer waiting on you (answered or cleared in the ledger)." NEVER blank/404. NOTED DEGRADATION (non-blocking): the specific "<when> — <outcome>" is not populated because resolved items leave the inbox payload; declared as an honest limit in inbox.js:32-36 and consistent with the identical generic-fallback pattern shipped in task 5 (requests.js, verified PASS conf 9). Safety-critical never-blank property holds. SURVIVED.
  (d) I4 — quarantine framed as SYSTEM failure, rendered below answerable, EXCLUDED from the (N)=3 count. PROVEN at render (setTabCount(answerable.length), inbox.js:434). SURVIVED.

§10 compliance (A1 new blocking gate): golden scenario (2026-07-18 bare-token sign-off incident) + expected FP rate (<~5% interactive adds) + retirement condition present in BOTH needs-you.sh header (lines 70-80) AND plan A1 bullet (lines 226-231). Result: PASS

DEPENDENCY TRACE
================
Step 1: operator opens #inbox on the deployed cockpit
  ↓ Verified at: headless-Chrome render, #inbox mounts, tabCount "(3)"
Step 2: inbox.js fetches /api/inbox -> inbox-routes.js buildInboxPayload() splits answerable/quarantined by lint_warnings, excludes state!==open
  ↓ Verified at: live curl (answerable:3, quarantined:1) + inbox-routes.js:290-316
Step 3: answerable render §3 anatomy + count = answerable.length; quarantine renders SYSTEM-failure framing + honest defect line; win-state only when answerable empty AND ok:true
  ↓ Verified at: render (section heads, framing, defect line) + inbox.js:428-460, 734-750
Step 4: A1 lint promotion — interactive decision add BLOCKS (nothing written); mechanical callers quarantine (lint_warnings stamped)
  ↓ Verified at: verifier sandbox probe (exit 1 / exit 0) + needs-you.sh:596-609 + 3 caller call-sites
Step 5: auditor cycle files ONE quarantine defect per ledger-item lifetime, keyed by ledger id
  ↓ Verified at: auditor.js:976-1020 + auditor --self-test S9b/S9d/S9e/S9f/S9g/S9i

Git evidence:
  Files modified in recent history:
    - neural-lace/workstreams-ui/server/inbox-routes.js  (NEW, 62bb460, 2026-07-19)
    - neural-lace/workstreams-ui/web/inbox.js  (NEW 62bb460; My-items section added 7cc793a)
    - neural-lace/workstreams-ui/server/auditor.js  (quarantine auto-defect, 62bb460)
    - adapters/claude-code/scripts/needs-you.sh  (A1 lint block + --mechanical, 62bb460)
    - adapters/claude-code/hooks/session-honesty-gate.sh / stop-verdict-dispatcher.sh / adapters/claude-code/scripts/session-resumer.sh  (--mechanical, 62bb460)
    - neural-lace/workstreams-ui/server/server.js + web/index.html  (mount + script tag, splice 362f471)

Runtime verification: curl http://127.0.0.1:7733/api/inbox
Runtime verification: test server/inbox-routes.selftest.js::inbox-routes self-test (23 passed, 0 failed)
Runtime verification: test web/cockpit.selftest.js::self-test summary (242 passed, 0 failed)
Runtime verification: test server/server.selftest.js::self-test summary (173 passed, 0 failed)
Runtime verification: test adapters/claude-code/scripts/needs-you.sh::--self-test (45 passed, 0 failed; T24b/T24c interactive-block)
Runtime verification: test neural-lace/workstreams-ui/server/auditor.js::--self-test (44 passed, 0 failed; S9f filed-once re-run)
Runtime verification: file neural-lace/workstreams-ui/web/inbox.js::setTabCount(answerable.length)
Runtime verification: file adapters/claude-code/hooks/session-honesty-gate.sh::--mechanical >/dev/null 2>&1

Verdict: PASS
Confidence: 9
Reason: PROVEN: the user-facing outcome was exercised against the live deployed :7733 surface via headless-Chrome render — the Inbox mounts, the (N)=3 headline count is derived from answerable items ONLY and excludes both the quarantined item and the My-items section (A10/I4), quarantine renders as a framed SYSTEM failure with an honest "defect has been filed" line matching the auditor's real state (A8), and the win state correctly does NOT render while answerable items exist (C4). Adversarial falsification probes SURVIVED: the A1 interactive anchorless add BLOCKS with nothing written while the identical text --mechanical stores + quarantines with lint_warnings (verifier's own sandbox probe); the auditor files exactly ONE quarantine defect per ledger-item lifetime and does not re-file on a second cycle (S9f); all three mechanical callers pass --mechanical at the correct sites. §10 golden-scenario/FP-rate/retirement text is present in both needs-you.sh's header and the plan. One NON-BLOCKING documented residual: the C3 stale-link banner renders the honest generic "resolved earlier — ..." (never blank/404) but does not populate the specific "<when> — <outcome>" because resolved items leave the payload — declared as an honest limit and identical to the generic-fallback pattern already shipped and PASSED in task 5.
