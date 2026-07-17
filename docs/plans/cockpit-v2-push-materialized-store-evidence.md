# Evidence Log — Cockpit v2 — cross-machine plan store (push-projected, staleness-detecting)

## Task 1 — The ONE parser + the ONE resolver (shared module)

EVIDENCE BLOCK
==============
Task ID: 1
Task description: [serial] **The ONE parser + the ONE resolver (shared module).** Build one parser + one resolver, used by every consumer. Handles: numeric AND lettered ids, continuation lines, the [serial] prefix, the Verification suffix, correct JSON escaping; --self-test incl. malformed plan -> damaged, never a silent zero. — Verification: mechanical
Verified at: 2026-07-17T11:49:18Z
Verifier: task-verifier agent (Verification: mechanical — full re-derivation; no prior evidence artifact existed)
Commit: fbb58a7dfe1dd0ad0fdee326dd4f5dece4b7a0db

Oracle: derived (pre-existing) — plan-lifecycle.sh's extract_all_task_line_ids grammar (the pre-existing lettered-id oracle) + the pre-existing server/auditor/cockpit self-test suites (139+18+84 tests green before this change) + the real docs/plans/** corpus.
Verification level: mechanical
Comprehension-gate: not applicable (Verification: mechanical — Step 0 routing exempts mechanical tasks from the R2+ comprehension-gate)

Checks run:
1. Self-test: shared module
   Command: node neural-lace/workstreams-ui/server/plan-parse.js --self-test
   Output: "plan-parse self-test summary: 14 passed, 0 failed" (incl. "loadPlanFile reports damaged (present but unreadable)" — the malformed-plan->damaged case, exercised via a directory at a .md path)
   Result: PASS
2. Self-test: auditor (spawn-heavy, real git/bash CLIs)
   Command: node neural-lace/workstreams-ui/server/auditor.js --self-test
   Output: "self-test summary: 18 passed, 0 failed" (exit 0) — full parity, no regression from the repoint
   Result: PASS
3. Self-test: server suite incl. new S60-S63
   Command: node neural-lace/workstreams-ui/server/server.selftest.js
   Output: "self-test summary: 148 passed, 0 failed" — S60 numeric regression, S60b lettered ids, S60c quote/newline JSON round-trip, S61b archive resolution, S61c honest null, S62/S62b live GET /api/ask/<id> counts lettered tasks, S63 live GET resolves archive-only plan
   Result: PASS
4. Self-test: cockpit web regression (untouched surface)
   Command: node neural-lace/workstreams-ui/web/cockpit.selftest.js
   Output: "self-test summary: 84 passed, 0 failed"
   Result: PASS
5. Grammar port fidelity (verbatim)
   Command: sed -n '335,360p' adapters/claude-code/hooks/plan-lifecycle.sh vs plan-parse.js:103
   Output: awk grammar ^([A-Za-z]+\.)?[0-9]+[A-Za-z]?(\.[0-9]+[A-Za-z]?)* is character-identical to TASK_ID_TOKEN_RE; line anchor ^- \[[ xX]\][ \t]+ identical to TASK_LINE_START_RE (plan-parse.js:95)
   Result: PASS
6. Resolver checks archive/
   Output: plan-parse.js:215-218 — candidates are docs/plans/<slug>.md THEN docs/plans/archive/<slug>.md; honest null at :224
   Result: PASS
7. absent vs damaged distinction
   Output: plan-parse.js:242-246 — ENOENT -> {reason:'absent', error:null}; ANY other read failure -> {reason:'damaged', error:<message>}; never a silent zero
   Result: PASS
8. Old private implementations GONE (deleted, not shadowed)
   Output: git show fbb58a7 shows deleted TASK_LINE_RE = /^- \[([ xX])\][ \t]*([0-9]+(?:\.[0-9]+)?)\./ + STATUS_LINE_RE from BOTH server.js and auditor.js; grep confirms remaining checkbox regexes in both files are unrelated surfaces (OPERATOR_TODO_ITEM_RE server.js:271, AUTO_POINTER_RE server.js:280, POINTER_RE auditor.js:294, self-test assertions). Call-sites now route through require('./plan-parse.js'): server.js:38,779,792,795; auditor.js:122,233,244,247
   Result: PASS
9. plan-lifecycle.sh untouched (explicitly forbidden by the task)
   Output: git show --stat fbb58a7 lists exactly 5 files, plan-lifecycle.sh absent; git status --porcelain for the file is clean; last commit touching it is 9fe4aba (pre-existing)
   Result: PASS
10. Numeric-fact re-derivation: "176 lettered-id task lines"
   Command: grep -rEh "^- \[[ xX]\][ \t]+[A-Za-z]+\.[0-9]" docs/plans --include="*.md" | wc -l
   Output: 176 (exactly the plan's cited number; +2 trailing-letter 20R-style lines)
   Result: PASS
11. Adversarial probe against the real corpus
   Command: node -e "require('./plan-parse.js').loadPlanFile(...)" on the live plan + a real archived lettered plan
   Output: cockpit plan -> ok=true, status=ACTIVE, 7 tasks, ids 1..7, task 1 done=false; capture-codify-pr-template.md (archive-only) -> resolved via archive/, 15 lettered tasks (sample id A.1). Falsification attempt on suffix-stripping FAILED correctly: task 1's mid-description QUOTED mention of the Verification suffix is preserved while its real trailing "— Verification: mechanical" suffix is stripped (description tail = "never a silent zero")
   Result: PASS

Runtime verification: test neural-lace/workstreams-ui/server/plan-parse.js::--self-test
Runtime verification: test neural-lace/workstreams-ui/server/auditor.js::--self-test
Runtime verification: test neural-lace/workstreams-ui/server/server.selftest.js::S60-S63
Runtime verification: test neural-lace/workstreams-ui/web/cockpit.selftest.js::regression
Runtime verification: file neural-lace/workstreams-ui/server/plan-parse.js::TASK_ID_TOKEN_RE
Runtime verification: file adapters/claude-code/hooks/plan-lifecycle.sh::extract_all_task_line_ids

DEPENDENCY TRACE
================
Step 1: GET /api/ask/<id> (or auditor cycle) needs a plan's tasks/status
  v Verified at: server.js:855 (countPlanTasks call-site), auditor.js:676-677
Step 2: slug -> absolute path via the ONE resolver (docs/plans/ then archive/)
  v Verified at: server.js:792,795 + auditor.js:244,247 -> planParse.resolvePlanAbsPath (plan-parse.js:213-225); S61b/S63 green
Step 3: path -> honest read (ok | absent | damaged) via the ONE loader
  v Verified at: plan-parse.js:237-254; self-test cases absent/damaged/ok all green
Step 4: markdown -> tasks via the ONE grammar (numeric + lettered + prefix/suffix/continuations)
  v Verified at: plan-parse.js:95-190; S60/S60b/S60c green
Step 5: user-observable outcome — the API now counts ALL tasks incl. lettered ids and archive-only plans
  v Verified at: server.selftest.js S62 ("counts ALL THREE tasks (2 lettered + 1 numeric)") and S63 (archive-only plan resolves) — both green in the 148/148 run

Git evidence:
  Files modified in commit fbb58a7 (2026-07-17):
    - neural-lace/workstreams-ui/server/plan-parse.js (NEW, 411 lines)
    - neural-lace/workstreams-ui/server/server.js
    - neural-lace/workstreams-ui/server/auditor.js
    - neural-lace/workstreams-ui/server/server.selftest.js
    - docs/plans/cockpit-v2-push-materialized-store.md (Status DRAFT->ACTIVE + Files-to-Modify section + Decisions Log entry, documented inline)

Verdict: PASS
Confidence: 9
Reason: PROVEN: all four suites re-executed by the verifier (14/14, 18/18, 148/148, 84/84 — outputs observed, not trusted); grammar is a character-identical port of the pre-existing plan-lifecycle.sh oracle; the "176 lettered lines" numeric claim independently re-derived at exactly 176; old private grammars shown DELETED in the diff with call-sites re-routed through plan-parse.js; plan-lifecycle.sh untouched; an adversarial suffix-stripping falsification attempt failed correctly.

## Task 2 — The exporter (Node CLI + A4 derive-lib refactor)

EVIDENCE BLOCK
==============
Task ID: 2
Task description: [serial] **The exporter** — a small Node CLI (`server/export-state.js`): re-derives from local disk at export time using the shared parser + the SAME event-log join the server uses. A4: MUST NOT require('server.js') — factor computePlanRows/aggregatePlanProgress/countPlanTasks/resolvePlanAbsPath/classifySessions into a requireable server/derive-lib.js. A3c: sessions export RAW last_heartbeat_at (never a baked live/stale classification). Emits per-(machine,repo,slug) records + a sessions block, stamped hostname/branch/head_sha/dirty/exported_at/schema_version (F4). Hash-gated with A3ii bounded keepalive (refresh exported_at ≥ every 60min even when hash-unchanged). Atomic writes; EXPORT_HOSTNAME override (A5). --self-test incl. quotes/newlines in descriptions and a zero-plan estate. — Verification: mechanical
Verified at: 2026-07-17T14:02:00Z
Verifier: task-verifier agent (Verification: mechanical — full re-derivation of every binding amendment; no reliance on builder claims)
Commit (build): a82ebf31c005bc861b438341dc362ee7fef99b23
Commit (integration fixup): ecc52a2b284d2609636e3bd52280756b4134212f
Tree verified at HEAD: 72ea153ae194173e45c8829ff1992174b3cb0383 (== origin/master)

Oracle: derived (pre-existing) — server.selftest.js's full black-box HTTP suite (148/0, the behavior-identity oracle for the A4 refactor) + web/cockpit.selftest.js (84/84, untouched surface); specified — export-state.js --self-test (11/11, the mechanical oracle for the new exporter behaviors incl. the Scenario-8 A4 live-port trap); metamorphic (inclusion/round-trip) — a real fixture export artifact re-derived by the verifier (lettered-id inclusion, raw-timestamp inclusion, EXPORT_HOSTNAME round-trip).
Verification level: mechanical
Comprehension-gate: not applicable (Verification: mechanical — Step 0 routing exempts mechanical tasks from the R2+ comprehension-gate; same routing as Task 1)

Checks run:
1. A4 — exporter never requires server.js (require-graph re-derived)
   Command: grep -nE "require\(" export-state.js  +  transitive-dep grep across derive-lib.js / config/projects.js / plan-parse.js / derive-cache.js
   Output: export-state.js requires ONLY fs, os, path, crypto, child_process, ./derive-lib.js — NO require('./server.js'). The server.js references in the file are (a) A4-explaining comments and (b) a path.join(__dirname,'server.js') that is SPAWNED (not required) as the Scenario-8 live child. No transitive dep of derive-lib.js requires server.js (only a comment mentions it).
   Result: PASS
2. A4 — trap proven closed via live self-test (Scenario 8 binds a real server on the port alongside the exporter)
   Command: node export-state.js --self-test
   Output: "11 passed, 0 failed" (exit 0), incl. "8. (A4 trap) exporter succeeds and writes a real export while a LIVE cockpit server holds the port — proves no require(./server.js), no EADDRINUSE interference". Post-run Win32_Process check: NO leftover node.exe running server.js (confirms the ecc52a2 Windows-safe taskkill /T /F teardown works — the fixup's whole purpose).
   Result: PASS
3. A3c — sessions carry RAW last_heartbeat_at, no baked classification (code + real artifact)
   Command: read deriveSessionsBlock() (export-state.js:140-162) + listRawHeartbeats() (derive-lib.js:356-369) + inspect a real fixture export
   Output: deriveSessionsBlock() enriches from listRawHeartbeats() which is a plain fs read of heartbeat JSON with NO hb_classify call / NO live|stale|crashed label. Real fixture artifact: session sess-z carries last_heartbeat_at="2026-07-17T13:57:59.213Z" (byte-identical to the raw ts written) and ('state' in session)===false. classifySessions() (with hb_classify) remains the server's LOCAL-render-only path, unchanged.
   Result: PASS
4. A3ii — bounded keepalive (unchanged content + last export ≥60min ⇒ rewritten exported_at)
   Command: read runExport() (export-state.js:215-235, KEEPALIVE_MS=60*60*1000) + self-test Scenario 5
   Output: prev.content_hash===hash && age<KEEPALIVE_MS ⇒ {written:false,reason:'unchanged'} (no write); age>=KEEPALIVE_MS ⇒ atomic rewrite with fresh exported_at, SAME content_hash, reason:'keepalive'. Self-test Scenario 5 ("unchanged content + stale (>=60min) exported_at -> rewritten with a fresh exported_at, same content_hash") PASS.
   Result: PASS
5. A5 — EXPORT_HOSTNAME override honored (code + real artifact round-trip)
   Command: read hostname() (export-state.js:55) + real fixture export with EXPORT_HOSTNAME=peer-sim-host
   Output: hostname()=process.env.EXPORT_HOSTNAME||os.hostname(). Real artifact: file name = "peer-sim-host.json" AND provenance.hostname = "peer-sim-host" (override honored in BOTH the file name and the provenance stamp). Self-test Scenario 6 PASS.
   Result: PASS
6. Provenance fields present in a real export artifact
   Command: inspect the fixture export artifact JSON
   Output: artifact carries schema_version:1, provenance.{hostname,branch:"worktree-agent-a87a7cb5a461f2b11",head_sha:"72ea153…",dirty:false}, content_hash:"b24ff1b4…", exported_at:"2026-07-17T13:57:59.317Z". ALL SIX named fields (hostname/branch/head_sha/dirty/exported_at/schema_version) present.
   Result: PASS
7. Behavior-identical refactor — pre-existing oracle passes unchanged
   Command: node server.selftest.js  ;  node ../web/cockpit.selftest.js
   Output: server.selftest.js = "148 passed, 0 failed" (Task 1's S60-S63 included) ; cockpit.selftest.js = "84 passed, 0 failed". server.js dropped 373 lines in a82ebf3 and is now a pure consumer of deriveLib.* (require('./derive-lib.js') at server.js:45; every derivation call routes through deriveLib.<name>). The black-box HTTP suite is the pre-existing oracle and is GREEN unchanged.
   Result: PASS
8. Seam closure (ecc52a2 + Task-1 integration) — no third grammar, lettered ids flow into exports
   Command: grep -nE "TASK_LINE_RE|inline grammar" derive-lib.js  +  read countPlanTasks/resolvePlanAbsPath (derive-lib.js:184-204)  +  real fixture export of a plan with a lettered task
   Output: NO inline TASK_LINE_RE remains in derive-lib.js (the only match is a comment noting the numeric-only regex "is gone — a THIRD grammar never ships"). countPlanTasks delegates to planParse.loadPlanFile; resolvePlanAbsPath delegates to planParse.resolvePlanAbsPath. Real fixture: a plan with lettered tasks A.1/A.2 + numeric 3 + a checklist bullet exported → tasks=["A.1","A.2","3"] (lettered ids FLOW THROUGH; in_flight snapshot correct: A.1 done, A.2 in-flight, 3 not-started) and the checklist bullet stayed INVISIBLE (3 tasks, not 4 — A6 negative case holds via the shared grammar).
   Result: PASS

Runtime verification: test neural-lace/workstreams-ui/server/export-state.js::--self-test
Runtime verification: test neural-lace/workstreams-ui/server/server.selftest.js::S60-S63
Runtime verification: test neural-lace/workstreams-ui/web/cockpit.selftest.js::regression
Runtime verification: file neural-lace/workstreams-ui/server/export-state.js::require-graph-no-server.js
Runtime verification: file neural-lace/workstreams-ui/server/derive-lib.js::countPlanTasks-delegates-planParse

DEPENDENCY TRACE
================
Step 1: a per-machine timer (task 3) invokes the exporter CLI
  ↓ Verified at: export-state.js runExport() (module.exports:237-241) — a requireable + CLI-runnable entry, no HTTP server needed
Step 2: exporter re-derives plan rows + sessions from local disk via derive-lib (NOT server.js)
  ↓ Verified at: export-state.js:41 require('./derive-lib.js') only; A4-trap Scenario 8 PASS (live server on the port, exporter still writes)
Step 3: derive-lib delegates plan grammar to the ONE parser (plan-parse.js) — lettered ids included
  ↓ Verified at: derive-lib.js:184-204 (countPlanTasks/resolvePlanAbsPath → planParse.*); fixture artifact tasks=["A.1","A.2","3"]
Step 4: exporter writes an atomic per-hostname JSON with provenance + raw heartbeats
  ↓ Verified at: real fixture artifact peer-sim-host.json — 6 provenance fields present, sessions carry raw last_heartbeat_at (no state field)
Step 5: observable outcome — a peer machine can consume this artifact (task 4 reader) with age-truth intact
  ↓ Verified at: A3c raw-timestamp inclusion (reader classifies by receive-time age) + A3ii keepalive (idle vs dead distinguishable) — self-test Scenarios 5/1b PASS

Git evidence:
  Files modified in the Task-2 build (a82ebf3, 2026-07-17):
    - neural-lace/workstreams-ui/server/derive-lib.js (NEW, 397 lines — the A4 requireable derivation lib)
    - neural-lace/workstreams-ui/server/export-state.js (NEW, +522 lines at build; 532 after fixup)
    - neural-lace/workstreams-ui/server/server.js (−373 net — repointed at derive-lib.js, behavior-identical)
    - docs/plans/cockpit-v2-push-materialized-store.md (In-flight scope update: derive-lib.js added to Files-to-Modify + path-shorthand→full-path fix)
  Integration fixup (ecc52a2, 2026-07-17):
    - neural-lace/workstreams-ui/server/export-state.js (+11 — Windows-safe taskkill /T /F teardown for Scenario 8)

Verdict: PASS
Confidence: 9
Reason: PROVEN: every binding amendment re-derived, not trusted. A4 — export-state.js require-graph (and its transitive deps) contains no require('./server.js'), and the live-port trap self-test (Scenario 8) writes a real export with a server bound on the port (11/11, exit 0; no leftover node.exe post-run). A3c/A5/provenance — a real fixture export artifact re-derived by the verifier shows raw last_heartbeat_at (no state field), EXPORT_HOSTNAME honored in filename+provenance, and all 6 provenance fields. A3ii keepalive — runExport()'s KEEPALIVE_MS branch + Scenario 5 green. Behavior-identical refactor — the pre-existing black-box HTTP oracle (server.selftest.js) is 148/0 unchanged and cockpit.selftest.js is 84/84, with server.js reduced to a pure deriveLib consumer. Seam closure — no inline TASK_LINE_RE remains in derive-lib.js (delegates to plan-parse.js), and a fixture export of a lettered-task plan carries A.1/A.2 through while the checklist-bullet negative case stays invisible. Verification: mechanical ⇒ comprehension-gate exempt (Step-0 routing).
## Task 3 — Transport (coord-sync cadence + coord-push A2 fixes) (builder commit d96bbbe)

Substance verified independently (task-verifier): coord-push.sh self-test 12/12 (5 new A2
scenarios), coord-sync.sh self-test 11/11, coord-pull.sh self-test 6/6 (unchanged, sanity
re-run); A2a proven differentially against pre-fix code (`.claude/state/observed-errors.md`
carries the verbatim repro); the verifier's own falsification probe on the A2c dedup guard
(disabling it and re-running) confirmed the "exactly ONE alert" assertion goes FAIL without it.

### Spec meaning

Task 3's "transport" bundles three binding amendments. A2 fixes two real defects in
coord-push.sh under its own WARN+exit-0-BY-DESIGN contract (which must NOT change): the
no-op gate must retry an existing unpushed local commit even when there is nothing NEW
staged (A2a — otherwise one transient push/rebase failure on a quiet estate defers
publication forever), and every invocation must expose its outcome via a status file
(pushed|local-commit|noop + ts) for a caller to consume (A2b) without ever touching the exit
code. A1 wires a DEDICATED 600s-cadence scheduled task (NL-coord-sync) that is the exporter's
ONLY invoker — that exclusivity IS the single-writer-per-machine enforcement (F4) — running
exporter -> coord-push -> coord-pull in that literal order, with a no-overlap policy (OS-level
ignore-new-instance + a script-level lock, since bash spawns here measure 94-119s). A2c closes
the loop: that same cadence watches coord-push's new status file and raises the EXISTING
health-tick alert path on a persistent (>3 consecutive) local-commit streak, so a genuinely
stuck writer surfaces loudly instead of exit-0ing into silence indefinitely.

### Edge cases covered

- Ahead-of-origin with NO new staged changes: `_ahead_of_origin` (coord-push.sh) compares HEAD
  against the clone's cached `origin/<branch>` ref (no fetch) and triggers a retry-push even
  when `git diff --cached --quiet` is clean. Proven differentially: reproduced the OLD bug
  against pre-fix code first (verbatim "no changes to push" while a real unpushed commit sat
  there, logged in `.claude/state/observed-errors.md`), then re-ran the identical repro against
  the fixed code and confirmed origin advanced to the local commit.
- Genuine unresolvable rebase conflict (add/add on the same path, `claims.json`): coord-push.sh
  self-test scenario 9 forces a real conflict, proving `_commit_and_push`'s local-commit outcome
  is reached via the rebase-then-abort path AND that origin is never force-pushed over
  (`git --git-dir=$bare rev-parse main` still equals the peer's SHA after the attempt).
- `_write_status_file` fires on EVERY exit path of `_run_push`, not just the three
  case-statement outcomes — including the throttled-skip and no-clone-resolved early returns —
  so a consumer never sees a stale/missing file just because a cycle degraded early.
- Overlapping coord-sync invocations: `_main` takes the STATE_DIR/coord-sync.lock mkdir lock
  BEFORE calling `_run_cycle`. Self-test scenario 2 pre-creates the lock, confirms none of
  exporter/push/pull ran, releases it, confirms the next invocation runs all three normally, and
  confirms the lock directory is gone afterward (`trap _release_lock EXIT`).
- Persistent local-commit alerting is deduped PER EPISODE, not per run: `_track_local_commit_streak`
  writes `ALERT_ACTIVE_FILE` the first time the streak exceeds threshold and suppresses further
  alerts while that marker exists. Self-test scenario 3 ran 5 consecutive local-commit cycles
  (exactly 1 alert file), then broke the streak with one `pushed` cycle and ran 4 more
  local-commit cycles (a SECOND alert file — dedup is per-stuck-episode, not permanent).
- Exporter must never write into a non-git COORD_CLONE_DIR: `_run_cycle` calls
  `_ensure_clone_bootstrap` BEFORE invoking the exporter step, specifically because
  coord-push.sh's own `_ensure_clone` refuses to `git clone` into a non-empty directory — if the
  exporter ran first and created plain directories there, coord-push's later bootstrap would break.
- No coord repo configured at all: `_ensure_clone_bootstrap` returns 1 (WARN, named-state
  degradation) and `_run_cycle` logs a `skipped-no-coord-repo` cycle line rather than crashing or
  silently doing nothing unlogged (self-test scenario 4).
- Installer never mutates the real Task Scheduler under test: `install-coord-sync-task.ps1`'s
  `[CmdletBinding(SupportsShouldProcess=$true)]` + `-WhatIf`, verified LIVE (not just read) via a
  real `-WhatIf` invocation plus `Get-ScheduledTask -TaskName 'NL-CoordSync'` returning nothing
  both before and after. `-MultipleInstances IgnoreNew` is the settings block's OS-level
  no-overlap backstop, paired with the script-level mkdir lock as defense in depth.

### Edge cases NOT covered

- coord-sync.sh's REAL scheduled-task registration was never exercised end-to-end — only
  `-WhatIf`. The task's own text is explicit that live registration is deploy-time and
  operator-run, never from a builder/self-test session, so this is a deliberate scope boundary,
  not an oversight.
- Real SSH-auth death against the actual private coord repo was never tested. The "persistent
  local-commit" scenario (coord-sync.sh self-test 3) simulates a dead remote via a stubbed
  `COORD_SYNC_PUSH_CMD` that writes the status file directly, not a genuine repeated git push
  failure. coord-push.sh's own self-test (scenario 9) DOES exercise a real git-level failure (an
  add/add conflict), but that path and coord-sync's alert logic were never combined in one
  end-to-end run.
- Two REAL machines running coord-sync.sh concurrently against the SAME shared coord repo (the
  actual deployed topology) was never exercised — the lock self-test proves same-machine mutual
  exclusion only. Cross-machine near-simultaneous pushes are covered by coord-push.sh's existing
  pull-rebase retry logic (its own scenario 5), not by anything added in this task.
- `-MultipleInstances IgnoreNew` was never actually triggered (would require two real overlapping
  Task Scheduler firings) — I'm relying on it being a documented, standard Task Scheduler setting
  rather than having observed it fire.
- The `EXPORT_HOSTNAME`-simulated two-"machine" acceptance (task 8's own explicit design) was not
  run here — that's task 8's job. My coord-sync self-test's full-cycle scenario proves ONE real
  machine's export reaches origin, not that a peer subsequently reads it back distinctly.

### Assumptions

- coord-push.sh's remote-tracking ref (`origin/<branch>`) is updated by a normal `git push`, so
  `_ahead_of_origin`'s no-fetch comparison reflects reality without its own network round trip; a
  genuinely stale cached ref just costs one wasted push attempt (still WARN+exit-0-safe), never a
  false negative that skips a real retry.
- coord-push.sh's existing WARN+exit-0 exit-code contract is permanent and load-bearing for
  callers outside this plan; this task never changed it, only added the status-file side channel.
- The `plan-export/` subdirectory name chosen for the exporter's per-host file inside the coord
  clone is not pinned anywhere else in the codebase yet (task 4, which reads it, does not exist
  yet) — assumed acceptable and schema-distinct from coord-push's own `tree-state/`; if task 4
  needs a different name it is a one-line change in `_run_cycle` and this plan's Files table note.
- `git rebase --abort` always fully restores the pre-rebase HEAD (relied on by both coord-push.sh's
  pre-existing logic and my new conflict scenario) — a standard git guarantee, not independently
  re-verified beyond the passing self-test.
- Windows PowerShell 5.1's script-file parser defaults to a non-UTF-8 codepage when no BOM is
  present (the root cause of the em-dash parse bug found and fixed in the new installer) — treated
  as a durable platform fact going forward (plain ASCII in real code lines), not something needing
  a BOM added; the sibling precedent file exhibits the identical symptom, confirmed via the same
  `[System.Management.Automation.Language.Parser]::ParseFile` check.

## Task 4 — Peer view in the cockpit (server read of the local coord clone)

EVIDENCE BLOCK
==============
Task ID: 4
Task description: [serial] Peer view in the cockpit — the server reads the LOCAL coord clone (no fork, no network on the request path — the clone is a directory; inherits skip-bad-record tolerance for mid-`reset --hard` partial files, A7); renders peer rows with provenance + age from RECEIVE-time (never the peer's wall clock alone, F2). Named states with REAL mechanisms (A3): fresh-ish/estate-unchanged/peer-unreachable/no-data-yet; plus the reader's OWN transport health. Peer-state thresholds env-injectable (A5). A peer's UNMERGED state never renders as plain done (F4). Local cards stay 100% on local truth; same-slug peer copies are labeled provenance rows, never substituted — Verification: full
Built at: 2026-07-17 (builder session, worktree agent-ace19d4a1edcb2958)
Files: neural-lace/workstreams-ui/server/peer-view.js (NEW), server.js, payload-schema.js, server.selftest.js, web/asks.js, web/app.css, web/cockpit.selftest.js, docs/plans/cockpit-v2-push-materialized-store.md (Files-to-Modify + In-flight scope update)

Checks run:
1. Unit self-test: server/peer-view.js --self-test — 32/32 PASS (boundary conditions for all 3 named states, A5 env-threshold overrides, stateLabel/provenanceLabel copy, isUnmerged incl. missing-branch honest-unknown case, classifySessionAge incl. unknown, A7 corrupt/vanished-file tolerance, no-clone/self-only "no data yet", myCoordRefresh FETCH_HEAD-primary + cycles.log-fallback + never-refreshed, EXPORT_HOSTNAME self-filter both explicit and implicit).
2. Integration/wiring proof over REAL HTTP: server/server.selftest.js S64-S69 (added to the existing suite, now 160/0 total) — a fixture coord clone (fresh peer + 2h-stale/unreachable peer + a truncated-JSON third file + this machine's own file) driven through a REAL running server instance's GET /api/asks: fresh peer renders `fresh-ish (Xm ago)` + an unmerged provenance_label naming host+branch; the stale peer renders `peer unreachable since <ts>`; the corrupt file is silently skipped (request still 200); self is filtered out; the local ask-fix-1 card's plan_progress is BYTE-IDENTICAL to its pre-peers value (S68); a real `.git/FETCH_HEAD` fixture (5m old) drives "my coord view last refreshed 5m ago" (S67); a missing-coord-clone case renders has_data:false, never a crash (S69).
3. Structural self-test: web/cockpit.selftest.js — 93/0 (84 pre-existing + 9 new PV-1..PV-9), asserting: the Peers `<details>` is ALWAYS rendered (both the normal and fully-empty landing paths) and collapses via `details.open = !!peers.has_data`; every peer plan row unconditionally sets `prov.textContent = p.provenance_label`; the unmerged CSS hook exists in both JS and CSS; every color-bearing peer chip (peer-state, peer-session) sets real textContent (never color-only); the plan-doc link reuses the EXISTING `openPlanDocModal` (no second doc-viewer).
4. Sibling suites unaffected: server/plan-parse.js --self-test 14/0, server/auditor.js --self-test 18/0, server/export-state.js --self-test 11/0 — all unchanged, proving the peer-view addition is purely additive.
5. Manual runtime livesmoke (beyond the self-tests): a real server.js instance launched on a sandbox port (18844) against a hand-built fixture estate (local ask+plan, coord clone with 4 peer-export files incl. a corrupt one), hit via `curl http://127.0.0.1:18844/api/asks` — JSON payload confirmed has_data:true, correct per-peer states/labels/provenance, self+corrupt excluded; the SAME server was then loaded in the Claude Browser pane at the real URL and the rendered DOM text was extracted (`get_page_text`), confirming the "Peers (2)" section, the fresh peer's "fresh-ish (1m ago)" + "as of 1m ago on winbox-two (build/peer-feature, unmerged)" labels, the stale peer's "peer unreachable since <ts>" label, "my coord view last refreshed 6m ago", and the local ask card's UNCHANGED plan-progress line, all rendering correctly with zero console errors. Server process torn down afterward (Stop-Process); browser preview closed.
6. Payload contract: server/payload-schema.js's LANDING_ALLOWED_KEYS extended by literal KEY addition (peers/has_data/my_coord_refresh/entries/host/state/state_label/age_minutes/received_at/branch/dirty/head_sha/unmerged/plans/plan_doc/tasks/id/provenance_label/sessions/session_id/role/last_heartbeat_at/label/last_refreshed_at/source) — mirrors the DETAIL_ALLOWED_KEYS precedent exactly (reusing plan_doc/tasks/id/session_id/role/state verbatim rather than inventing parallel names); `plan_doc` stays exempt from the absolute-href check via the SAME HREF_KEYS-omission mechanism already documented for local rows (no new code needed).

Runtime verification: test neural-lace/workstreams-ui/server/peer-view.js::--self-test (32/32)
Runtime verification: test neural-lace/workstreams-ui/server/server.selftest.js::S64-S69 (160/160 total)
Runtime verification: test neural-lace/workstreams-ui/web/cockpit.selftest.js::PV-1..PV-9 (93/93 total)
Runtime verification: manual curl + browser DOM extraction against a live server.js instance on port 18844

## Comprehension Articulation — Task 4

### Spec meaning
Every one of the task's 9 numbered load-bearing requirements maps to a specific function: (1) no-fork/no-network + A7 skip-bad-record -> `readPeerExportFiles()` (plain fs.readdirSync/statSync/readFileSync; a vanished-mid-read or corrupt/partial file is caught per-file and skipped, never thrown, never crashing the whole read). (2) self-filter via the exporter's own `EXPORT_HOSTNAME` override -> `selfHostname()` + `computePeerView()`'s `files.filter((f) => f.host !== self)`. (3) age from RECEIVE-time, never the peer's wall clock alone (F2) -> the file's own `fs.statSync(...).mtime` is used as `receivedAt`/`received_at` throughout — never `payload.exported_at` for age math; clock-skew immunity comes from both ends of the age subtraction being THIS machine's own clock. (4/5) named states + the reader's own transport health -> `classifyPeerState()` (fresh-ish/estate-unchanged/peer-unreachable) + `stateLabel()` for the literal copy, and `myCoordRefresh()` (FETCH_HEAD-primary, cycles.log-fallback, "never refreshed" honest floor). (6) A5 env-injectable thresholds -> `thresholds()` reads `COCKPIT_PEER_FRESH_MIN`/`COCKPIT_PEER_KEEPALIVE_MIN`/`COCKPIT_PEER_TRANSPORT_MARGIN_MIN`/`OBS_STALE_MIN`. (7) A3c session age classification from RAW `last_heartbeat_at` -> `classifySessionAge()`, called per-session inside `computePeerView()`, never trusting any baked classification (export-state.js's own A3c already guarantees none exists to trust). (8) local cards untouched, peer rows always labeled -> `server.js`'s `buildAsksLandingPayload()` adds a SEPARATE `peers` key alongside the pre-existing `groups`/`completed` (zero local-card code touched), and every peer plan row unconditionally carries `provenance_label` (`provenanceLabel()`) which `asks.js`'s `renderPeerPlanRow()` always renders — verified both structurally (cockpit.selftest.js PV-3) and at runtime (server.selftest.js S65b; the live browser DOM: "as of 1m ago on winbox-two (build/peer-feature, unmerged)"). (9) UI + anti-noise/absolute-links + payload allowlist by KEY -> `asks.js`'s `renderPeersSection()`/`renderPeerEntry()`/`renderPeerPlanRow()`/`renderPeerSessionRow()`; `payload-schema.js`'s `LANDING_ALLOWED_KEYS` extended by literal KEY addition, reusing `plan_doc`/`tasks`/`id`/`session_id`/`role`/`state` verbatim from the existing DETAIL vocabulary rather than inventing parallel names.

### Edge cases covered
Corrupt/partial peer file skipped silently, request still succeeds (server.selftest.js S64e; peer-view.js self-test #6). Self's own file present in `plan-export/` but never appears as a peer (S64d; self-test #8 and #15b — the latter via the IMPLICIT `EXPORT_HOSTNAME` env read, not just an explicit `selfHost` arg, proving `computePeerView()` doesn't require the caller to pass identity explicitly). Zero peer files / no coord clone at all -> `has_data:false`, "no data yet" (S69; self-test #9). Only self's file exists, no real peer ever -> also `has_data:false` (self-test #10 — a case the HTTP suite doesn't separately exercise but the unit suite does). Exact threshold boundaries (20min and 80min, both inclusive-fresh/inclusive-estate-unchanged) (self-test #1-#1d). Unmerged detection across non-master branch, dirty-but-master, AND a missing/blank branch field (treated as unmerged — an honest "don't know it's merged" rather than defaulting to merged) (self-test #4-#4e). Session heartbeat classification: fresh, 45-min-stale against a 30-min threshold, and a missing timestamp (-> `unknown`, never a crash or a guess) (self-test #5-#5c). "My coord view" transport health across all three source states (FETCH_HEAD present, FETCH_HEAD absent + cycles.log present, neither present) (self-test #12-#14; S67 + the live browser DOM confirms the FETCH_HEAD-primary path concretely). A5 threshold env-injection at a compressed timescale, matching what Task 8's acceptance drill will actually need (self-test #2/#2b). The Peers section renders on BOTH the normal landing path and the fully-empty (zero-asks-yet) landing path (cockpit.selftest.js PV-1's second assertion). Payload-schema validation itself doesn't trip under real fixture branch/host strings flowing through the new keys (S64 asserts HTTP 200, not a 500 diagnostics response).

### Edge cases NOT covered (honest gaps)
A real peer branch name that happens to contain a denylisted substring (e.g. a branch literally named `fix/ask-registry-thing`) would 500 the WHOLE landing payload via `GATE_HOOK_DENYLIST_PATTERNS` — this is a pre-existing design tension the denylist already carries for local `summary`/`narrative_excerpt` prose, and this task deliberately does NOT add a branch-name exemption (doing so would weaken the very check meant to catch a mechanism name leaking through content), so this is flagged rather than fixed. Task 8's own two-machine acceptance drill (kill the export loop -> "peer unreachable" within the WRITTEN 600s cadence) is not exercised here — this task proves the READ side renders each named state correctly given a fixture file at the right age, not the live cadence end-to-end. The A7 tolerance is proven against the SYMPTOM (a static corrupt/truncated fixture file), not a live concurrent `git reset --hard` race — reproducing that race deterministically would need real concurrent processes, out of this task's scope (coord-pull.sh's own self-test already separately covers the dirty-tree/stash-preserving path on the WRITE side of that same race). A peer's `plan_doc` is rendered as a "View live plan doc" link assuming this machine's OWN project registration resolves the same `{project,path}` pair the peer's export carries; if the peer's project alias differs, the button exists but the docs-modal fetch degrades to the EXISTING `/api/doc` error path (no peer-specific mismatch check was added). Session role/plan_slug/task_id enrichment on a peer session is trusted verbatim (shape-checked only) once it arrives — this reader does not re-derive or cross-check that lineage against anything on this machine, the same trust boundary the local DETAIL payload already extends to its own sessions.

### Assumptions
"master" is hardcoded as this codebase's stable main-branch name in `isUnmerged()` (matching this repo's own documented convention) rather than read from any config; a peer machine whose OWN project uses a different default branch name would show every row as unmerged even when genuinely merged into ITS default branch — accepted as a fair simplification since the plan's stated scope is this one estate, not a general multi-convention peer. The `.git/FETCH_HEAD` mtime is trusted as a reliable "last successful fetch" signal on every platform coord-sync.sh runs on, per git's own documented write behavior — this task's tests prove the READ side of that logic against a hand-written fixture file (`fs.utimesSync`), not against a live `git fetch` invocation. The default thresholds (20min fresh / 60min keepalive / 20min margin => 80min unreachable) are taken directly from the plan's own literal amendment text (A1's staleness contract; export-state.js's existing `KEEPALIVE_MS`), not independently re-derived from separate empirical measurement. `plan_doc`'s HREF_KEYS-exemption-by-omission was read as applying identically regardless of which machine (local or peer) produced the `{project,path}` object — no new special-casing was added, relying on the pre-existing mechanism's scope being "any `plan_doc`-shaped object," not "only a locally-produced one."

## Task 4 — VERIFICATION (task-verifier, independent re-derivation)

EVIDENCE BLOCK
==============
Task ID: 4
Task description: [serial] Peer view in the cockpit — server reads the LOCAL coord clone (no fork/no network on the request path; A7 skip-bad-record), renders peer rows with provenance + age from RECEIVE-time (F2), named states with real mechanisms (A3), env-injectable thresholds (A5), unmerged never renders plain done (F4), local cards stay 100% local truth — Verification: full
Verified at: 2026-07-17 (task-verifier agent, worktree agent-af89de92d44275474)
Verifier: task-verifier agent

Oracle: specified — plan User-facing Outcome + Task 4's 9 numbered requirements + amendments A3/A5/A7/F2/F4; PLUS derived-metamorphic — a verifier adversarial probe holding "a lying future exported_at must NOT relax computed age" and "a done-on-non-master peer must ADD the unmerged constraint". Functional signal: server.selftest.js S64-S69 drive a REAL running server GET /api/asks over real HTTP asserting user-observable rendered payload fields.

Comprehension-gate: articulation IS filed (evidence file "## Comprehension Articulation — Task 4", 4 substantive sub-sections). rung-3 + Verification: full. Per orchestrator instruction the comprehension-reviewer runs IN PARALLEL (dispatched by the orchestrator, not nest-spawned by this verifier); NOT marked INCOMPLETE — the orchestrator holds the checkbox flip until BOTH gates return.

Checks run:
1. Unit self-test — Command: node server/peer-view.js --self-test — Output: "32 passed, 0 failed" — Result: PASS (expected 32/0).
2. Wiring proof over REAL HTTP — Command: node server/server.selftest.js — Output: "160 passed, 0 failed"; S64-S69 all PASS (S64 GET /api/asks 200 + payload-schema validation passes; S64c exactly 2 peers, self+corrupt excluded; S64e corrupt file skipped without throwing; S65b unmerged provenance_label; S66 "peer unreachable since <ts>"; S67 FETCH_HEAD ~5m; S68 local card byte-identical; S69 no-clone -> has_data:false, 200) — Result: PASS (expected 160/0 incl S64-S69).
3. Structural UI self-test — Command: node web/cockpit.selftest.js — Output: "93 passed, 0 failed"; PV-1..PV-9 all PASS — Result: PASS (expected 93/0 incl PV-1..9).
4. No-fork/no-network discipline — grep of server/peer-view.js for child_process/exec/spawn/http/fetch — only a RegExp .exec() match (not child_process.exec) — Result: PASS.
5. Age uses receive-time mtime, never exported_at — grep for exported_at in server/peer-view.js returns none; age math reads f.receivedAt = fs.statSync().mtime only (L147/L271) — Result: PASS.
6. Load-bearing function spot-check vs requirements — readPeerExportFiles (fs-only, per-file try/catch skip; L134-150) / selfHostname (EXPORT_HOSTNAME; L108-110) / classifyPeerState (fresh-ish<=freshMs, estate-unchanged<=keepaliveMs+marginMs, else peer-unreachable; env-injectable thresholds L115-122) / myCoordRefresh (FETCH_HEAD statSync primary, cycles.log fallback, honest "never refreshed"; L223-253) / isUnmerged+provenanceLabel (dirty||branch not master; label always carries merged|unmerged; L179-192) / classifySessionAge (Date.now()-Date.parse(raw last_heartbeat_at); L202-207) — Result: PASS.
7. server.js wiring — buildAsksLandingPayload adds a SEPARATE peers key alongside groups/completed (local cards untouched), fail-open buildPeersBlock (L954-968) — Result: PASS (requirement 8: never substituted).
8. UI rendered-output rule — asks.js renderPeerPlanRow sets prov.textContent = p.provenance_label (L916), renderPeerEntry sets chip.textContent = e.state_label (L951), renderPeersSection sets coordHealth.textContent = my_coord_refresh.label (L986); renderPeersSection called on BOTH landing paths (L1057, L1073) — Result: PASS (visible DOM text, not an intermediate value).
9. Payload allowlist by KEY — payload-schema.js LANDING_ALLOWED_KEYS extended by literal KEY addition (25 keys incl peers/has_data/my_coord_refresh/state_label/provenance_label/unmerged/branch/received_at); reuses DETAIL vocab; plan_doc HREF-exempt by omission — S64 proves real-HTTP validation passes (200, not 500) — Result: PASS.

Adversarial probe (task-verifier authored, executed against the live module):
  Scenario: a peer export claiming ALL tasks done on a NON-master branch (build/sneaky-feature), shipping a LYING exported_at 2h in the FUTURE, with file mtime set 90min in the past; plus a corrupt sibling file.
  Observed: unmerged flag=true; provenance_label = "as of 90m ago on evil-peer (build/sneaky-feature, unmerged)"; state = peer-unreachable (age from mtime=90m; the future exported_at is IGNORED); state_label = "peer unreachable since <ts>"; corrupt sibling skipped, healthy peer still present, no throw.
  Result: ADVERSARIAL PROBE SURVIVED — F4 (unmerged never plain done), F2 (clock-skew immunity via receive-time mtime), A7 (skip-bad-record) all hold under adversarial input.

Runtime verification: test neural-lace/workstreams-ui/server/peer-view.js::--self-test (32/32, re-run by verifier)
Runtime verification: test neural-lace/workstreams-ui/server/server.selftest.js::S64-S69 (160/160 total, real-HTTP GET /api/asks, re-run by verifier)
Runtime verification: test neural-lace/workstreams-ui/web/cockpit.selftest.js::PV-1..PV-9 (93/93 total, re-run by verifier)
Runtime verification: test task-verifier adversarial probe (done-on-non-master + lying future exported_at + corrupt sibling) — all assertions PASS against server/peer-view.js#computePeerView

Note on functionality-verifier: not separately nest-dispatched in this orchestrated split. The functional axis is satisfied directly — server.selftest.js S64-S69 exercise the user-shaped GET /api/asks path against a REAL running server and assert the user-shaped rendered payload; the verifier's own adversarial probe drove the live computePeerView; the builder additionally captured a live browser DOM extraction (evidence check #5).

Honest gap (disclosed, not blocking): PEER-VIEW-DENYLIST-COLLISION-01 — a peer branch/host name containing a GATE_HOOK_DENYLIST_PATTERNS substring would 500 the whole landing payload (degrades safely, no leak). Deliberately unfixed; persisted to docs/backlog.md L196. Outside Task 4's 9-requirement contract.

DEPENDENCY TRACE
================
Step 1: operator opens cockpit -> GET /api/asks
  Verified at: server.js buildAsksLandingPayload L954 (peers: buildPeersBlock())
Step 2: server reads LOCAL coord clone plan-export/<host>.json (no fork/no network)
  Verified at: peer-view.js readPeerExportFiles L134-150 (fs-only) + computePeerView L260-313; grep check 4
Step 3: per-peer named state + provenance from receive-time mtime; self filtered; corrupt skipped
  Verified at: server.selftest.js S64-S69 (real HTTP) + verifier adversarial probe
Step 4: peer rows render to visible DOM with provenance_label / state_label / coord-refresh label
  Verified at: asks.js L916/L951/L986 (textContent) + cockpit.selftest.js PV-3/PV-5/PV-7

Git evidence:
  Files modified in b3ba920 (build cockpit-v2 task4):
    - server/peer-view.js (NEW, 541 lines), server.js (+24), payload-schema.js (+15),
      server.selftest.js (+119), web/asks.js (+156), web/app.css (+44),
      cockpit.selftest.js (+41), plan + evidence docs. HEAD = 79e2b47 (== origin/master).

Verdict: PASS
Confidence: 9
Reason: PROVEN — all three self-tests re-run at exact expected counts (32/0, 160/0 incl S64-S69, 93/0 incl PV-1..9); every load-bearing function spot-checked against its requirement + amendment; no-fork/no-network and receive-time-mtime disciplines verified by source inspection; a verifier-authored adversarial probe (done-on-non-master + lying future exported_at + corrupt sibling) exercised the live module and F4/F2/A7 all held; the user-facing outcome is demonstrated over real HTTP (S64-S69) and reaches visible DOM textContent (asks.js). Checkbox intentionally NOT flipped — orchestrator flips on both this gate and the parallel comprehension gate.
## Task 5 — plan-lifecycle MultiEdit matcher fix

EVIDENCE BLOCK
==============
Task ID: 5
Task description: [serial] plan-lifecycle MultiEdit matcher fix (independent real hole, P8): settings matcher `Edit|Write` -> `Edit|Write|MultiEdit`; regression scenario in its self-test — Verification: mechanical
Built at: 2026-07-17 (builder session, worktree agent-a22a9a4ee6ce39659)
Files: adapters/claude-code/settings.json.template, adapters/claude-code/hooks/plan-lifecycle.sh

Checks run:
1. `adapters/claude-code/settings.json.template`'s plan-lifecycle.sh PostToolUse matcher (was `Edit|Write` at ~line 407) changed to `Edit|Write|MultiEdit`.
2. Real hole found on comprehension, not just the settings matcher: `plan-lifecycle.sh`'s OWN main-path dispatch (the code the fixed matcher actually invokes) had an INDEPENDENT `case "$TOOL_NAME" in Edit|Write) ;; *) exit 0 ;; esac` gate that would have silently no-op'd a MultiEdit event even with the matcher fixed — both gates changed to `Edit|Write|MultiEdit` in the same commit (settings.json.template + plan-lifecycle.sh's main path).
3. New self-test Scenario 21 added, structurally different from every prior scenario: all 20 prior scenarios call `process_lifecycle_event()` directly, bypassing the jq-based `tool_name`/`file_path` extraction entirely. Scenario 21 drives the hook as its OWN subprocess (`CLAUDE_TOOL_INPUT=<MultiEdit-shaped JSON> bash plan-lifecycle.sh`), exercising the REAL end-to-end dispatch — proven to be the only scenario that would have caught the actual hole (pre-fix, `MultiEdit` hits the dispatch's `*) exit 0` branch silently).
4. `bash adapters/claude-code/hooks/plan-lifecycle.sh --self-test` — PASS ("OK (plan-lifecycle.sh --self-test)"), all 21 scenarios including the new one.
5. `cat adapters/claude-code/settings.json.template | jq .` — valid JSON confirmed.
6. `bash adapters/claude-code/scripts/manifest-check.sh` — `[manifest-check] GREEN — 129 entries, 110 hooks covered, 0 warn` (no manifest entries needed; no new file created).

Runtime verification: test adapters/claude-code/hooks/plan-lifecycle.sh::--self-test (21/21, incl. new Scenario 21)
Runtime verification: mechanical adapters/claude-code/settings.json.template::jq-valid-json

## Comprehension Articulation — Task 5

### Spec meaning
The task names ONE symptom (a MultiEdit to a plan file "fires NO plan-lifecycle splice") and ONE named fix (the settings matcher `Edit|Write` -> `Edit|Write|MultiEdit`). Reading the actual mechanism end to end (not just the symptom line) surfaced that the fix has to land in TWO places to be genuine, not cosmetic: `settings.json.template`'s PostToolUse matcher (line 407, `"matcher": "Edit|Write"`) decides WHETHER Claude Code invokes the hook process at all for a given tool call; `plan-lifecycle.sh`'s own main-path `case "$TOOL_NAME" in Edit|Write) ;; *) exit 0 ;; esac` (bottom of the file, after the `--self-test` early-exit block) decides what the ALREADY-INVOKED hook process does with a `tool_name` it doesn't recognize. Fixing only the matcher would have been the classic "built but not wired" trap in miniature: the hook would now get CALLED for a MultiEdit, immediately hit its own `*) exit 0` branch, and still silently no-op — exactly the same user-observable symptom (no archival, no creation-warning, no progress-log emission) as before the fix, but now hidden one layer deeper where a shallow "did the matcher change land" check would have missed it entirely. Both case statements had to widen together for a MultiEdit to a plan file to actually trigger the SAME lifecycle behavior (creation warning / auto-archival / task_done + plan_amended progress-log emission) an Edit or Write already does — the hook's internal logic never branches on `tool_name` beyond that one initial gate (the `tool_name` parameter passed into `process_lifecycle_event()` is ONLY consulted later for the Write-only creation-warning check, which MultiEdit correctly can't trigger since MultiEdit — like Edit — requires a pre-existing file).

### Edge cases covered
The literal symptom scenario: a MultiEdit-shaped PostToolUse event (`{"tool_name":"MultiEdit","tool_input":{"file_path":...,"edits":[...]}}`) driving a real ACTIVE -> COMPLETED transition through the hook's OWN subprocess dispatch (jq extraction of `tool_name`/`tool_input.file_path`, `resolve_file_repo_root`, `pre_edit_content` via `git show HEAD:...`, post-edit content via a plain disk read) — Scenario 21 proves archival actually happens (`docs/plans/archive/case21.md` exists, source gone, "auto-archived" in stderr), not merely that `process_lifecycle_event()` can be called with `tool_name="MultiEdit"` as a bare argument (which every scenario already implicitly allowed, since that function never gated on tool_name except the Write-only creation-warning branch — the REAL gate that needed fixing was one layer up, in the dispatch code Scenario 21 is the first to actually exercise). Confirmed the settings.json.template edit doesn't break JSON validity (`jq .` round-trip). Confirmed `tool_name` is genuinely irrelevant to every OTHER branch of `process_lifecycle_event()` (status-transition archival, progress-log emission) by inspection — MultiEdit and Edit hit identical downstream behavior once past the initial gate, so no MultiEdit-specific logic branch was needed or added.

### Edge cases NOT covered
MultiEdit's own `tool_input.edits` array (the list of old_string/new_string replacements) is never read by this hook and this fix does not change that — pre/post content is always derived from git HEAD and a fresh disk read, regardless of which tool produced the edit, so a MultiEdit that touches a plan file via many small hunks is handled identically to a single Edit or a full Write; this was verified by inspection (no code path in `process_lifecycle_event` or its callees references `tool_input.edits`), not by a dedicated multi-hunk fixture, since the hook's own design makes that fixture redundant (the edits array literally cannot matter to logic that never reads it). The companion sibling hook `post-tool-task-verifier-reminder.sh` sitting at the SAME settings.json.template `Edit|Write` matcher (line ~398, immediately above the fixed one) was deliberately left untouched — the task's scope is "the plan-lifecycle.sh matcher," and that sibling hook is a distinct, independently-scoped mechanism; whether it has the identical class of gap was not investigated here (flagged, not fixed, to avoid unauthorized scope expansion).

### Assumptions
`jq` is available in the hook's runtime environment for the main-path `tool_name`/`file_path` extraction (already an existing, unchanged assumption of this hook prior to this task — confirmed present in this dev environment via `jq --version` (jq-1.7.1), consistent with every sibling hook in this codebase (`local-edit-gate.sh`, `agent-design-gate.sh`, `doctrine-jit.sh`, etc.) that already gates on the identical `Edit|Write|MultiEdit` case pattern this fix now matches). The fix is read as purely additive (widening a case arm) with zero risk to the Edit/Write paths, since `Edit|Write|MultiEdit)` still falls through to the exact same `;;` no-op branch as the prior `Edit|Write)` for those two tool names — verified by the 20 pre-existing scenarios (all Edit/Write-only) staying green unchanged alongside the new Scenario 21.

## Task 6 — Payload `description` carve-out

EVIDENCE BLOCK
==============
Task ID: 6
Task description: [serial] Payload contract: `description` into `DETAIL_ALLOWED_KEYS` + a `DENYLIST_EXEMPT_KEYS` set with a length cap (by KEY, as HREF_KEYS does — m1), stated plainly as a knowing widening of the anti-noise constraint scoped to plan content — Verification: mechanical
Built at: 2026-07-17 (builder session, worktree agent-a22a9a4ee6ce39659)
Files: neural-lace/workstreams-ui/server/payload-schema.js, neural-lace/workstreams-ui/server/server.selftest.js

Checks run:
1. `payload-schema.js`: `description` added to `DETAIL_ALLOWED_KEYS`; `DENYLIST_EXEMPT_KEYS = new Set(['description'])` + `DENYLIST_EXEMPT_MAX_LEN = 2000` added, with a block comment stating plainly that this is a KNOWING widening of the anti-noise constraint (hard constraint 1), scoped to plan-content prose.
2. `walk()` modified: for a key in `DENYLIST_EXEMPT_KEYS`, the gate/hook-identifier denylist scan (`containsDenylistedIdentifier`) is SKIPPED and replaced with a raw length-cap check (over-cap = a validation error pushed to `errors`, never a silent truncation); every other key is unaffected (still runs the denylist scan exactly as before). The `HREF_KEYS` absolute-href check runs independently/unconditionally, unaffected by the new exemption — mirrors the file's own existing "two independent checks" design.
3. `DENYLIST_EXEMPT_KEYS`/`DENYLIST_EXEMPT_MAX_LEN` added to `module.exports` (mirrors the existing `HREF_KEYS` export).
4. Self-test scenarios S70-S70d added to `server.selftest.js` (the next free block after S69, in the same "DELIBERATELY SELF-CONTAINED on payload-schema.js" style as the pre-existing S27/S50 blocks — no live server/fixture needed):
   - S70: a `description` containing `plan-lifecycle.sh` PASSES `validateAskDetail`.
   - S70a NEGATIVE FIXTURE: the IDENTICAL string in `summary` (not `description`) still FAILS — proves the exemption is scoped BY KEY, not by content.
   - S70b NEGATIVE FIXTURE: a hook-lifecycle-name string (`posttooluse`) in `narrative[].summary` (not `description`) still FAILS.
   - S70c NEGATIVE FIXTURE: a `description` one character over the 2000-char cap FAILS with an "exceeds max length" error.
   - S70d: a `description` at EXACTLY 2000 chars PASSES (boundary check — the cap is inclusive).
5. `node server/server.selftest.js` — 165/0 total (160 pre-existing + 5 new S70-series), full run, no regressions.

Runtime verification: test neural-lace/workstreams-ui/server/server.selftest.js::S70-S70d (165/165 total)

## Comprehension Articulation — Task 6

### Spec meaning
The task is a single, precisely-scoped schema carve-out with three literal parts, each mapped directly: (1) "`description` into `DETAIL_ALLOWED_KEYS`" -> the field name literally added to that `Set` in `payload-schema.js`, so a `description` key anywhere inside an ask-detail payload no longer fails the "unknown field (not in allowlist)" check `walk()` raises for any key absent from the relevant allowlist. (2) "a `DENYLIST_EXEMPT_KEYS` set... by KEY, as HREF_KEYS does" -> a NEW `Set` (`DENYLIST_EXEMPT_KEYS`), checked inside `walk()` via `DENYLIST_EXEMPT_KEYS.has(key)` — the EXACT same shape as the pre-existing `HREF_KEYS.has(key)` check immediately below it (both are per-key-name membership tests independent of the field's nesting depth or the payload's overall shape), rather than e.g. a value-pattern allowlist or a per-payload-type flag. (3) "a length cap... stated plainly as a knowing widening" -> `DENYLIST_EXEMPT_MAX_LEN = 2000`, enforced ONLY for exempt keys (a compensating constraint for the constraint being removed), with an explicit block comment at the constant's definition explaining WHY plan-content prose legitimately needs to name the very mechanisms (`plan-lifecycle.sh`, `posttooluse`, etc.) the denylist otherwise exists to keep out of rendered UI copy — satisfying "stated plainly" as an actual code comment, not just this evidence file.

### Edge cases covered
The exemption is proven to be scoped BY KEY, not by content or by "this payload happens to contain a description field somewhere" — S70a and S70b each inject the IDENTICAL denylisted string into a DIFFERENT field (`summary`, then `narrative[].summary`) on the SAME payload shape that passes when the string sits under `description`, and both still fail with a "gate/hook identifier" error, proving `walk()`'s per-key branch (not some payload-wide flag) is what's doing the work. The length cap is checked at BOTH boundary values: S70c (2001 chars, one over) fails, S70d (exactly 2000) passes — proving the cap is inclusive (`> DENYLIST_EXEMPT_MAX_LEN`, not `>=`) rather than off-by-one in either direction. The cap failure is a distinct, non-overlapping error path (`/exceeds max length/`) from the denylist-scan error path (`/gate\/hook identifier/`), so a future reader of `errors` can distinguish "this description is too long" from "this ISN'T a description field and shouldn't have gotten past the scan" — they can never both fire for the same string on the same key, since exempt keys skip the scan entirely. The `HREF_KEYS` absolute-href check is confirmed to still run independently of the new exemption — a `description` field is not in `HREF_KEYS`, so it was never subject to that check either way, and the two independent-checks design documented in the file's own header comment is unchanged by this task.

### Edge cases NOT covered
This task adds the SCHEMA carve-out only — it does not wire an actual `description` field into `server.js`'s `buildAskDetailPayload()` (no plan-content excerpt is currently rendered through this key by any producer). This is consistent with `Verification: mechanical` (a schema/contract-level change, not a runtime user-observable feature) and with the plan's own task text, which describes only the schema addition — but it means there is currently no REAL producer-side exercise of this carve-out end-to-end (only the schema module's own direct validation calls, S70-series). A future task that actually surfaces plan-content prose through this key will be the first to prove the carve-out against a REAL payload rather than a hand-built fixture. `DENYLIST_EXEMPT_KEYS` is a `Set` (supports adding more exempt keys later) but this task adds exactly one member (`description`) per the plan's literal text — a second exempt key was neither requested nor added speculatively. The 2000-char cap is an arbitrary-but-documented choice (the plan's own task text suggests "e.g. 2000 chars" as an example, not a hard number) — no attempt was made to derive it from an actual observed plan-task-description length distribution.

### Assumptions
The cap is enforced as a hard validation ERROR (payload fails validation entirely) rather than any softer behavior, per the task's explicit instruction ("over-cap = validation error, not truncation") — read literally, so `server.js`'s existing "validation failure = 500 with diagnostics detail, not a leaking payload" contract (documented in this file's own header) is the enforcement backstop for an over-cap description, exactly as it already is for every other validation failure this module raises; no new error-handling path was added on the `server.js` side since none was needed. `DENYLIST_EXEMPT_KEYS` was designed to compose with `HREF_KEYS` (a key COULD theoretically be in both sets) even though no current key needs both — the two checks are structured as independent `if` blocks specifically so a future key needing exemption from ONE constraint but not the other is representable without restructuring `walk()` again.

## Task 7 — C3b: wire the auditor's REAL divergences into nl-issue

EVIDENCE BLOCK
==============
Task ID: 7
Task description: [serial] C3b — wire the auditor's REAL divergences (log_ahead_task_not_flipped et al.) into `nl-issue.sh` with dedup + recurrence escalation (the operator's actual auto-healing intent; self-inflicted-drift reporting died with the projector) — Verification: full
Built at: 2026-07-17 (builder session, worktree agent-a22a9a4ee6ce39659)
Files: neural-lace/workstreams-ui/server/auditor.js

Checks run:
1. `NL_ISSUE_BADGE_CLASSES` (a `Set`) added, naming the FOUR real log-ahead badge classes this file's own divergence-class-table header documents by ROW DESCRIPTION, resolved to their LITERAL `divergence_class` string constants (which differ from the plan task's own paraphrased prose names — see Comprehension below): `log_ahead_task_not_flipped`, `unmatched_dispatch`, `orphaned_waiting_item`, `unknown_provenance`.
2. `nlIssueCliPath()` / `auditorNlIssueStatePath()` path resolvers added, mirroring `progressLogCliPath()`/`askRegistryCliPath()`'s exact env-override-else-repo-relative-default shape (nl-issue.sh) and `progressLogStateDir()`'s exact env-override-else-$HOME/.claude/state shape (the auditor's OWN dedup/recurrence state file, distinct from nl-issue.sh's own internal ledger).
3. `fileNlIssueDivergences(newBadgesByAsk, opts)` added: iterates every ask's badges, files a real `nl-issue.sh <text>` call (via the pre-existing `runCli()` — same `bashBin()`/`spawnEnv()` + killTree-on-timeout convention as `backfillTaskDone`/`backfillAskDone`/`scanRepoForMerges`) for each badge whose `divergence_class` is in `NL_ISSUE_BADGE_CLASSES` and whose `detail_ref` has never been filed before (persisted dedup state, keyed by `detail_ref`); then computes, from the PERSISTED filed-state's timestamps, the count of distinct ids per `divergence_class` within a rolling 7-day window, and files ONE additional escalation summary per class the FIRST time that count reaches 3 (never repeated for that class again).
4. Sandbox gate `isNlIssueSandboxed()`: true when `HARNESS_SELFTEST==='1'` OR `AUDITOR_DISABLED==='1'` — the two env vars ALREADY set (by auditor.js's own `--self-test` and by server.selftest.js's ENTIRE run, respectively) rather than a newly-introduced flag; kill-switch `AUDITOR_NL_ISSUE_DISABLED=1` checked first, independent of sandbox state.
5. Wired into `runCycle()`: `await fileNlIssueDivergences(newBadgesByAsk, {...})` called once per cycle, after the merge-scan loop and before the §8-3 count-reconciliation block (i.e., once every badge for the cycle is final), wrapped in try/catch so a failure never wedges the cycle.
6. `auditor.js --self-test`: 12 new scenarios (S2e, S2e2, S2f, S2g, 2x S2h-setup, S2h2, S2h3, S2h4, S2h5, S2i, S2j) added immediately after the pre-existing S2d (which already proves the `log_ahead_task_not_flipped` badge for ask-a/task-2 persists across cycles) — reusing that live fixture rather than building a new one. Result: 30/0 total (18 pre-existing + 12 new).
   - S2e/S2e2: un-sandboxed, the persistent badge files EXACTLY ONE real `nl-issue.sh` ledger entry (verified via a REAL `nl-issue.sh` invocation with `NL_ISSUES_PATH` sandboxed to a fixture ledger — not a stub), and the auditor's own state file records the id as filed.
   - S2f: a second cycle over the SAME still-open badge does NOT re-file (ledger stays at 1 line).
   - S2g: sandbox mode (`HARNESS_SELFTEST=1`) files NOTHING even with the same real eligible badge present.
   - S2h (x2 setup) + S2h2-S2h5: two more tasks (3, 4) added to the same fixture plan, each with a real `progress-log.sh emit`, checkbox left unflipped -> 3 distinct ids for `log_ahead_task_not_flipped` (tasks 2, 3, 4) under a FRESH state file -> exactly 4 ledger lines (3 individual + 1 escalation, asserted by regex on the escalation text naming the class + "3"), and the state file marks the class permanently escalated.
   - S2i: a second cycle over the same 3 badges does NOT re-escalate (still 4 lines, not 5).
   - S2j: the `AUDITOR_NL_ISSUE_DISABLED=1` kill-switch files nothing even when un-sandboxed with real eligible badges present.
7. `node server/server.selftest.js` re-run in full AFTER the auditor.js changes — still 165/0 (no regression; confirms `AUDITOR_DISABLED='1'` — set for that file's entire run — correctly suppresses filing during its Scenario 28 direct `auditor.runCycle()` call, since that file never sets `HARNESS_SELFTEST` at all). Confirmed by direct filesystem check: `~/.claude/state/auditor-nl-issue-state.json` does not exist on this machine (never created by any of today's test runs) and `~/.claude/state/nl-issues.jsonl`'s mtime is unchanged since before this session's test runs — no real ledger pollution from either self-test suite.
8. `bash adapters/claude-code/scripts/manifest-check.sh` — GREEN (129 entries, 110 hooks covered, 0 warn); no manifest changes needed (no new files created).

Runtime verification: test neural-lace/workstreams-ui/server/auditor.js::--self-test (30/30, incl. 12 new C3b scenarios)
Runtime verification: test neural-lace/workstreams-ui/server/server.selftest.js::full-suite-no-regression (165/165)
Runtime verification: filesystem check confirming zero real-ledger pollution (~/.claude/state/auditor-nl-issue-state.json absent; ~/.claude/state/nl-issues.jsonl mtime unchanged)

## Comprehension Articulation — Task 7

### Spec meaning
The task names four divergence classes in prose form (`log_ahead_task_not_flipped`, `task_started_no_dispatch`, `waiting_no_ground_truth`, `provenance_unknown`) and explicitly instructs "read the divergence-class table in the header" rather than treating those four strings as literal code identifiers to grep for. Reading that table (lines ~23-45 of `auditor.js`, unchanged by this task) against the ACTUAL `badges.push({divergence_class: ...})` call sites in `auditAsk()` shows the table's row descriptions map to DIFFERENT literal constants than the task's prose paraphrase: "task_started with no matching dispatch record" -> `unmatched_dispatch` (not `task_started_no_dispatch`); "waiting_on_operator with no ground truth anywhere" -> `orphaned_waiting_item` (not `waiting_no_ground_truth`); "event with provenance:unknown emitter" -> `unknown_provenance` (not `provenance_unknown`); only the first, `log_ahead_task_not_flipped`, matches verbatim. `NL_ISSUE_BADGE_CLASSES` is built from the REAL constants, not the task's prose — a literal-string implementation would have silently filed NOTHING for three of the four classes (a class-level false-negative that would only surface once a real `unmatched_dispatch`/`orphaned_waiting_item`/`unknown_provenance` badge occurred in production and nothing ever got filed for it). DEDUP -> a persisted `filed` map keyed by `badge.detail_ref` (already a stable, globally-unique per-divergence id every construction site sets). RECURRENCE ESCALATION -> read as "exactly one escalated filing, ever, per class" (not a re-escalating-every-N-more-ids design), computed from the PERSISTED state's timestamps within a 7-day rolling window, not just one cycle's badge snapshot (a badge for an already-resolved divergence stops appearing in `newBadgesByAsk` but its filed-timestamp must still count toward the window). Env kill-switch -> `AUDITOR_NL_ISSUE_DISABLED`, checked first and independently of the sandbox gate. Sandbox-awareness -> `isNlIssueSandboxed()` deliberately checks TWO existing env vars, not one, because the two self-test entry points that can produce a real badge each set a DIFFERENT one of them (see Edge cases below) — gating on only `HARNESS_SELFTEST` would have left server.selftest.js's own Scenario 28 (a direct `auditor.runCycle()` call producing a real `log_ahead_task_not_flipped` badge) able to file into the REAL operator ledger during every future run of that suite, the exact leak the task's sandbox-awareness clause exists to prevent.

### Edge cases covered
The TWO independent self-test entry points that can produce a real eligible badge without any nl-issue-specific fixture wiring were BOTH audited for their sandbox signal, not assumed: `auditor.js`'s own `--self-test` sets `HARNESS_SELFTEST='1'` globally at its top (verified by reading the file, not assumed) but never touches `AUDITOR_DISABLED`; `server.selftest.js` sets `AUDITOR_DISABLED='1'` for its ENTIRE run (to keep the auditor's autostart timer from firing before its sandbox env vars are in place) but NEVER sets `HARNESS_SELFTEST` at all (also verified by grep, not assumed) — a single-flag gate would have left exactly one of these two suites unprotected; `isNlIssueSandboxed()`'s OR of both flags covers both, confirmed by S2g (auditor.js's own suite, gated on `HARNESS_SELFTEST`) and by the full server.selftest.js re-run staying 165/0 with no new `~/.claude/state` files created (gated on `AUDITOR_DISABLED`). The "one filing per divergence lifetime, not per cycle" dedup was proven against a genuinely PERSISTENT badge (S2d already established, independent of this task, that the log-ahead badge survives across cycles) rather than a synthetic one-shot fixture — S2f's second cycle is a real repeat of the SAME badge computation, not a mocked repeat. The escalation threshold boundary (exactly 3, not "3 or more eventually") was exercised precisely: the fixture is built so the state file has EXACTLY 3 distinct ids under a FRESH state path at the moment escalation should first fire (S2h2 confirms all 3 badges exist before checking the ledger), and S2i confirms the SAME 3 badges on a second cycle do not produce a 5th line (permanence, not a re-escalating window). The four classes' shared plumbing (all four flow through the SAME `fileNlIssueDivergences` loop and the SAME dedup/escalation logic, keyed only by `divergence_class` as a string) means the one concretely-exercised class (`log_ahead_task_not_flipped`, via the pre-existing S2 fixture) is a structurally faithful proxy for the other three — nothing in the filing/dedup/escalation code branches on WHICH of the four classes it's handling.

### Edge cases NOT covered
The other three classes (`unmatched_dispatch`, `orphaned_waiting_item`, `unknown_provenance`) were NOT individually exercised end-to-end through `fileNlIssueDivergences` with a real badge of THAT specific class (only `log_ahead_task_not_flipped` was, via the reused S2 fixture) — covered instead by the structural argument above (shared code path, class-agnostic logic) rather than four separate live fixtures; a class-specific bug in `nlIssueMessageForBadge()`'s handling of a field one of those three classes' badges lacks (e.g. `unknown_provenance`'s badges have no `plan_slug`/`task_id`, only `de_emphasize`) was checked by READING the function (the `badge.plan_slug ? ... : ''` guard degrades gracefully to an empty `where` string) but not by a dedicated runtime scenario. The recurrence window's UPPER boundary (an id filed exactly 7 days + 1ms ago should NOT count toward the window) was not exercised with a real elapsed-time fixture — only verified by reading `fileNlIssueDivergences`'s `ageMs > NL_ISSUE_RECURRENCE_WINDOW_MS` comparison, not by constructing a state file with a pre-aged timestamp near that exact boundary (S2h's 3 ids are all filed within the same test run, well inside the window, so the boundary itself is unexercised at runtime). Whether `nl-issue.sh`'s OWN internal 24h text-dedup could ever collide with (suppress) one of THIS module's filings was not tested — in practice the two filing texts always differ (each embeds a distinct `detail_ref`), so a same-text collision is structurally impossible given the message format, but this was reasoned through rather than probed with an adversarial fixture. The interaction between this task and Task 4's peer-view feature (whether a PEER machine's divergences should also be filed, or only this machine's own) was not considered — `fileNlIssueDivergences` only ever sees `newBadgesByAsk`, which is entirely LOCAL-ask-derived (badges are never computed for peer data), so this is a non-issue by construction, not an oversight, but it was not explicitly named in the task text either way.

### Assumptions
"Fire-and-forget" in the task's phrasing is interpreted as "the auditor never retries, never propagates an nl-issue failure into `backfill_errors`/diagnostics, and never lets nl-issue's outcome affect the cycle's own success" — NOT as "literally unawaited" — `fileNlIssueDivergences` is `await`ed sequentially inside `runCycle()` (matching this file's own documented house convention, "sequential, never parallel-fan-out bash spawns," already applied to `backfillTaskDone`/`backfillAskDone`/`scanRepoForMerges`), bounded by the SAME `runCli()` killTree-on-timeout reaping used everywhere else in this file. This was a deliberate judgment call over a literal "spawn and don't await" reading, made because an un-awaited spawn would make the self-test's own assertions racy (the ledger write might not have landed by the time `await auditor.runCycle()` resolves) without any compensating benefit, since the auditor already runs on a relaxed, off-request-path cadence where a bounded synchronous nl-issue.sh call (a fast file-append script) costs nothing observable. `detail_ref` is assumed to be a permanently-stable identity for "the same divergence" for as long as its underlying cause remains unresolved (e.g. `'drift-' + askId + '-log-ahead-' + slug + '-' + t.id` never changes shape for the same ask/plan/task triple) — if a future change to `auditAsk()` ever altered a `detail_ref` construction pattern, this task's dedup would treat the new id as a "new" divergence and re-file it once, which is the same re-identification behavior every other `detail_ref` consumer (the UI's click-through, Task 13) already implicitly depends on. The escalation message's inclusion of the raw sorted id list is assumed acceptable content for nl-issue.sh's ledger (an internal operator-facing triage surface, NOT the ask-tree UI payload governed by `payload-schema.js`'s anti-noise law) — mentioning `auditor`/mechanism names/detail_ref strings in this text is fine specifically because nl-issue.sh's ledger is a different, internal-tooling surface than the one `GATE_HOOK_DENYLIST_PATTERNS` protects.
