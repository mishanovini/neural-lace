# Workstreams UI diagnosis + sync plan (2026-06-18)

## Root cause (PROVEN)
Running server `ws-ui-server-stable` (PID 17912, :7733, checkout at
~/claude-projects/workstreams-ui-server, a neural-lace worktree) is 54 commits
behind master and missing the workstreams fixes. THREE concrete failures:

1. EPERM data loss (HIGHEST — active). store.js renameSync fails with EPERM when
   the live server's fs.watch holds the state dir; events silently lost.
   EVIDENCE: 10 orphaned tree-state.json.tmp.* in workstreams-coordination/state/
   (Jun 17-18). Fix `89479e5` (renameWithRetry+cleanupStaleTemps) is on pt/master,
   NOT origin/master, NOT running HEAD.
2. Deploy=0 / 209 stale shipped-not-deployed (#61 ac29415). Confirmed via live
   render sim: deployed=35, shipped-not-deployed=209 (the unfixed numbers).
3. [ACTIVE] items wrongly shown shipped + not hidden by show-completed (#62 d4ce1f3).

## Fork state
- app.js + work-in-motion-sweep.js are BYTE-IDENTICAL between origin/master and
  pt/master (forks reconverged on content; #61/#62 live in BOTH via different SHAs).
- ONLY store.js diverges: EPERM fix is pt-exclusive.
- Therefore: merging pt/master ALONE brings everything (EPERM fix + deploy/ACTIVE
  fixes via shared app.js + #63). Merging BOTH masters BREAKS P22 self-test
  (sweptAtZero=false) due to the diverged store.js merge — do NOT merge both.

## Verified safe fix: merge pt/master into ws-ui-server-stable
Tested in throwaway worktree off running HEAD f205a56:
- `git merge --no-ff pt/master` → conflict-free.
- self-tests: state/selftest.js 23/23, state/filter-status.selftest.js 18/18.
- server starts, /api/state 200, 5258 nodes render.
- gitignored operator config (config/projects.json, config/wim-repos.json) and the
  state file (separate workstreams-coordination repo) are untouched by the merge.

## Exact commands (operator to run — touches LIVE instance)
    cd ~/claude-projects/workstreams-ui-server
    git fetch pt
    git merge --no-ff pt/master          # conflict-free; brings EPERM+#61+#62+#63
    # restart the live server so it loads the fixed store.js (in-memory until restart):
    #   stop PID on :7733, then: CTREE_PORT unset -> node server/server.js (or the
    #   launch-gui.ps1 / autostart task the operator uses)
    # the synced cleanupStaleTemps() will auto-sweep the 10 orphaned .tmp.* on next write
NO force-push. NO --no-verify. Hooks (workstreams-emit.sh etc.) pick up the fixed
store.js immediately on next invocation; the SERVER's own POST /api/event path needs
the restart.
