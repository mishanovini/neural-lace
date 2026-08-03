# Evidence — cockpit-orphan-treekill-hotfix-2026-08-03

## Task 1 — killTree in derive-cache.js (Verification: full)

Verdict: PASS

- Fix commit: 64001586 (worktree branch), cherry-picked to master as
  5bc0594f ("fix(workstreams-ui): timeout-kill the whole child TREE"),
  pushed to origin (1456cdd1..5bc0594f).
- Livetest oracle (production-shaped fork tree: Git bin-bash launcher →
  script bash → multi-command `$(...)` subshell; spawn via the module's
  exported `bashBin()`/`spawnEnv()`, kill via exported `killTree`):
  output `{"survivors":[],"pass":true}` — every ParentProcessId-reachable
  member dead after killTree; scenario run 2026-08-03 ~08:50 local.
- Module selftests after edit: state-watch.selftest.js `25 passed, 0
  failed`; maintenance-pane.selftest.js `9 passed, 0 failed`;
  `node --check` clean on derive-cache.js and server.js.
  (server.selftest.js line-893 crash reproduced IDENTICALLY on unmodified
  master — pre-existing, filed to nl-issues.jsonl 2026-08-03.)
- End-to-end functional demonstration (the user path): pinned-checkout
  server restarted on :7733 at 09:09:48; 10-minute observation window
  09:10:42–09:20:54 (11 samples, 60s cadence) — full table in the
  completion report. Incident metrics: live `nl.sh` process count flat at
  3–5 and drained to 0 by the final sample (pre-fix behavior: one immortal
  3–4-process orphan chain added per 5-min anti-entropy tick); oldest
  nl.sh age a sawtooth capped at 2.9 min — every 180s status timeout
  reaped its whole tree (pre-fix: orphans measured living ~20 min, e.g.
  the 08:12:53 chain still burning CPU at 08:28). No bash-count monotone
  growth (transient 09:19 spike attributed to other sessions' self-test
  forks: composition check at 09:22 showed 15 self-test + 27 misc-hook
  bash, only 4 nl.sh, total already self-drained 130→48).

## Task 2 — runAskRegistryCli timeout tree-kill (Verification: contract)

Verdict: PASS

- Contract: neural-lace/workstreams-ui/server/server.js (runAskRegistryCli
  — the 180s timeout now calls derive-cache's exported killTree before
  resolving; previously it resolved WITHOUT killing, leaking the whole
  child tree on every timeout).
- Evidence: commit 64001586 / master 5bc0594f; `node --check` clean;
  killTree export verified (`typeof dc.killTree === 'function'` smoke);
  the same killTree implementation Task 1's livetest proved kills the
  production-shaped tree. The 180s path is impractical to drive
  synthetically in-session (it requires a real 3-minute ask-registry
  hang); the shared implementation + the observation window covering the
  identical spawn shape (bashBin + '-lc' via spawnEnv) is the accepted
  contract-level demonstration per the plan's Testing Strategy.

## Task 1 — task-verifier re-derivation (independent)

EVIDENCE BLOCK
==============
Task ID: 1
Task description: Add killTree() to derive-cache.js and call it from spawnAsync's timeout (replacing bare child.kill()); export it; document the MSYS exec-shim residual honestly — Verification: full
Verified at: 2026-08-03T09:37:11-07:00
Verifier: task-verifier agent

Oracle: specified (plan User-facing Outcome: tree-kill oracle, survivors=[]) + derived-preexisting (pre-fix behavior at 5bc0594f^ as the differential baseline)

Comprehension-gate: not applicable (rung < 2; plan rung: 1)

Operator invariants: none registered (exit 3)

Checks run:
1. killTree structure on master
   Command: grep -n 'function killTree|killTree(child)|module.exports' derive-cache.js
   Output: :217 function killTree; :244 killTree(child) inside spawnAsync setTimeout (rc=124 path); :594 exported; MSYS exec-shim KNOWN RESIDUAL documented :211-216
   Result: PASS
2. Syntax + export smoke
   Command: node --check derive-cache.js; node -e "typeof require(...).killTree==='function'"
   Output: both exit 0
   Result: PASS
3. Commit provenance
   Command: git show --stat 5bc0594f; git branch --contains 5bc0594f
   Output: derive-cache.js +39 lines in 5bc0594f (2026-08-03 09:11 -0700); commit on master; handoff doc docs/handoffs/2026-08-03-cockpit-nl-recursion-rootcause.md (109 lines) landed same commit (Docs impact satisfied)
   Result: PASS
4. Module selftests
   Command: node state-watch.selftest.js; node maintenance-pane.selftest.js
   Output: 25 passed, 0 failed; 9 passed, 0 failed
   Result: PASS
5. Livetest oracle REPLAYED with verifier-authored script (not builder's)
   Command: node scratchpad/killdiff.js tree — production-shaped tree via module's own bashBin()/spawnEnv(): Git-bin-bash launcher -> login shell -> script bash -> $() subshell, busy pure-builtin loop
   Output: {"mode":"tree","treeBefore":[4 bash.exe],"survivors":[]}
   Result: PASS
6. Live cockpit corroboration
   Command: curl http://127.0.0.1:7733/ ; Get-CimInstance Win32_Process count of 'nl.sh (status|costs|...)'
   Output: HTTP 200; nl.sh subprocess count = 0 (expected band 0-8; incident signature was dozens of immortal chains)
   Result: PASS

Runtime verification (before): node scratchpad/killdiff.js bare — same tree, kill method verbatim from pre-fix code
  Commit: 5bc0594f^ (line 211: try { child.kill(); } catch (_) {})
  Expected: FAIL — bare kill should orphan the descendants (the incident bug)
  Observed: launcher 35900 died; ALL 3 descendants (36828, 26812, 26700, bash.exe) survived as orphans — bug reproduced live

Runtime verification (after): node scratchpad/killdiff.js tree — identical tree, killTree(child)
  Commit: 5bc0594f (master)
  Expected: PASS — whole tree dead
  Observed: survivors=[] — all 4 members dead

Runtime verification: file neural-lace/workstreams-ui/server/derive-cache.js::function killTree
Runtime verification: file neural-lace/workstreams-ui/server/derive-cache.js::killTree(child)
Runtime verification: test neural-lace/workstreams-ui/server/state-watch.selftest.js::self-test summary: 25 passed, 0 failed
Runtime verification: test neural-lace/workstreams-ui/server/maintenance-pane.selftest.js::self-test summary: 9 passed, 0 failed
Runtime verification: curl http://127.0.0.1:7733/
Runtime verification: functionality-verifier 1::SKIP (rationale: agent unavailable in this verifier environment; oracle replayed directly by verifier — killdiff differential: bare-kill survivors=3/3 descendants, killTree survivors=0)

Note: verifier's FIRST replay used a stdin-blocked tree and bare kill did NOT orphan it (node's pipe teardown EOF'd the read-blocked descendants — they self-drained). Handoff doc explains production orphans were busy deriving, not reading stdin; the busy-tree differential above is the faithful reproduction. Recorded 10-min observation window (evidence file, builder-authored) accepted as recorded observation per dispatch; independently corroborated by check 6 hours later (0 accumulated nl.sh orphans, server live).

Git evidence:
  Files modified: neural-lace/workstreams-ui/server/derive-cache.js (5bc0594f, 2026-08-03)

Verdict: PASS
Confidence: 9
Reason: PROVEN: pre-fix kill method reproduced the orphan bug live (3 surviving descendants) and post-fix killTree on the identical tree left survivors=[]; structure, export, residual doc, selftests, syntax, commit provenance, and live-system corroboration all re-derived independently.

## Task 2 — task-verifier re-derivation (independent)

EVIDENCE BLOCK
==============
Task ID: 2
Task description: server.js runAskRegistryCli: kill the child tree on timeout (previously resolved without killing — pure leak) — Verification: contract
Verified at: 2026-08-03T09:40:40-07:00
Verifier: task-verifier agent

Oracle: contract — the locked shape is the auditor.js/derive-cache killTree pattern applied at runAskRegistryCli's 180s timeout; differential baseline is the pre-fix line at 5bc0594f^:1169

Comprehension-gate: not applicable (rung < 2; plan rung: 1)

Operator invariants: none registered (exit 3)

Checks run:
1. Contract shape on master
   Command: grep -n 'killTree' server.js + read runAskRegistryCli (server.js:1147-1174)
   Output: :1151-1155 killTree imported from ./derive-cache.js with unavailability guard; :1172 setTimeout(() => { killTree(child); done({ ok:false, error:'ask-registry.sh call timed out (child tree killed)' }); }, 180000) — kill precedes resolve, inside runAskRegistryCli
   Result: PASS
2. Pre-fix differential (the leak)
   Command: git show 5bc0594f^:.../server.js | grep -n 'timed out'
   Output: :1169 setTimeout(() => done({ ok:false, error:'ask-registry.sh call timed out' }), 180000) — resolved WITHOUT killing; fix is not a no-op
   Result: PASS
3. Syntax
   Command: node --check server.js
   Output: exit 0
   Result: PASS
4. Commit provenance
   Command: git show --stat 5bc0594f; git branch --contains 5bc0594f
   Output: server.js changed (+9/-) in 5bc0594f; on master. Docs impact 'none beyond shared handoff doc' — handoff doc landed same commit
   Result: PASS
5. Shared-implementation functional proof
   Command: (Task 1's replayed differential) node killdiff.js bare|tree on the identical spawn shape (bashBin() + spawnEnv(), the exact shape runAskRegistryCli spawns at :1160)
   Output: bare kill orphans 3/3 descendants; killTree survivors=[]
   Result: PASS

Runtime verification: file neural-lace/workstreams-ui/server/server.js::killTree(child)
Runtime verification: file neural-lace/workstreams-ui/server/server.js::ask-registry.sh call timed out (child tree killed)
Runtime verification: file neural-lace/workstreams-ui/server/derive-cache.js::function killTree

DEPENDENCY TRACE
================
Step 1: ask-registry CLI call exceeds 180s (runAskRegistryCli timeout fires)
  ↓ Verified at: server.js:1172 (setTimeout 180000)
Step 2: killTree(child) invoked before resolving
  ↓ Verified at: server.js:1172 (kill precedes done()); import guard server.js:1151-1155
Step 3: whole child tree terminated (taskkill /T /F on win32)
  ↓ Verified at: derive-cache.js:217-227 + replayed killdiff differential (survivors=[])

Verdict: PASS
Confidence: 9
Reason: PROVEN: master server.js:1172 calls killTree(child) inside runAskRegistryCli's 180s timeout before resolving, where 5bc0594f^:1169 resolved without killing; node --check clean; commit 5bc0594f touches server.js on master; the shared killTree implementation was functionally proven by the replayed differential on the identical spawn shape. Contract level per plan Testing Strategy (the 180s path itself is impractical to drive synthetically; accepted as declared).
