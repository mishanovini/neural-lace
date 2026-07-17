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
