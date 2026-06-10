# Evidence Log — Workstreams Consolidation (single source of truth + harvest + redesign)

Plan: docs/plans/workstreams-consolidation-2026-06-08.md (rung: 2, Mode: design, Verification: full default)
Verifier: task-verifier agent, 2026-06-10

## Comprehension Articulation
(Orchestrator-supplied via dispatch prompt, transcribed and structured by task-verifier with full attribution;
the comprehension-reviewer agent could not be dispatched in this environment — no Task tool available — so
task-verifier applied the three-stage rubric inline. Deviation from Decision 020e's builder-authored-block
convention is flagged in the verifier's final report.)

### Spec meaning
The plan consolidates the Workstreams subsystem: ONE canonical state file
(workstreams-coordination/state/tree-state.json) resolved identically by every emit hook, gate, and the UI
server; harvest of stranded pt/ redesign branches into the live workstreams-ui (retiring the
conversation-tree-ui husk); full-content self-contained items (background + options + recommendation +
links) with a turn-emit fragment guard; modal detail overlay with context-appropriate action buttons;
an all-work-in-motion model tracking plans/branches/PRs through merged-to-deployed; and merge/supersession
of feat/deterministic-workstreams-turn-emit plus durable commit of the 21 uncommitted consumer-repo audit docs
with corrupted-filename dupes deleted. Work shipped across builder rounds R1-R8 this session; the R8
end-user-advocate runtime artifact (4/4 scenarios PASS at plan_commit_sha 2b91389) is the user-facing
outcome evidence.

### Edge cases covered
- Fragment/garbage emission: _isCleanItem() FRAGMENT GUARD in workstreams-turn-emit.sh (~/.claude/hooks/workstreams-turn-emit.sh:403,486); R8 no-garbage-items scenario PASS (0 Turn-NNNN, 0 fragments, 0 fixtures across 210 item rows).
- Duplicate ingestion during migration: dedupe by node_id; R7 sweeper is idempotent (selftest 37/37, replayed by verifier).
- Boilerplate "INCOMPLETE METADATA" stubs: R6 backfill (coordination commit 63d761e); verifier node-count over canonical file = 0 boilerplate items.
- Legacy machines without the path config: resolver lib falls back to per-project path (graceful degradation, workstreams-state-resolver.sh read-order 1-3).
- Corrupted-filename consumer-repo dupes (invisible U+F00D before .md): 8 deleted in consumer-repo commit 408272f3; verifier confirmed 0 non-ASCII filenames remain in consumer-repo/docs/reviews.

### Edge cases NOT covered
- U+FFFD replacement chars in 10 item texts (ingestion em-dash mangle, in state DATA, noted by R8 advocate as side defect beyond scenario scope) — not fixed in this plan.
- "Awaiting me" vs "In flight" filters both count 209 in current data (non-discriminating partitions; neither false — R8 note).
- Cross-machine concurrent-write merge strategy (plan Edge Case 1) exercised only single-machine this session.
- <consumer-product> audit docs are committed+pushed on chore/close-bh-simplify-plan but NOT yet merged to consumer-repo master (follow-up per merge-completed-work.md).

### Assumptions
- The R8 advocate artifact + per-task replayable commands are treated as the runtime-verification entries (orchestrator directive in dispatch prompt).
- pt/ branch content equivalence per the R2 audit (equal/evolved form on master) — independently spot-checked by verifier (toast handling x20, modal x4, reconciler + topology on master, turn-emit master superset of branch).
- The git-backed coordination-repo file is acceptable as the live store the UI server reads (plan Assumption 2).
- plan_commit_sha for the uncommitted plan file resolves to repo HEAD (2b91389), which the R8 artifact matches.

---

EVIDENCE BLOCK
==============
Task ID: 1
Task description: Decide + implement the single state path (workstreams-coordination/state/tree-state.json); point emit + gates + UI server at it; one-time migrate all 9 files' open items in.
Verified at: 2026-06-10T03:08:30Z
Verifier: task-verifier agent

Comprehension-gate: PASS-with-deviation (rung 2; comprehension-reviewer agent unavailable in this environment — inline three-stage rubric applied by task-verifier against the orchestrator-supplied articulation transcribed at the top of this file; diff-correspondence verified directly against repos)

Checks run:
1. state.js STATE_FILE resolution
   Command: node -e "console.log(require(HOME+'/claude-projects/workstreams-ui-server/neural-lace/workstreams-ui/state/state.js').STATE_FILE)"
   Output: ~/claude-projects/workstreams-coordination/state/tree-state.json
   Result: PASS
2. Live UI server health reports same state_file
   Command: curl -s http://127.0.0.1:7733/api/health
   Output: {"ok":true,...,"state_file":"~/claude-projects/workstreams-coordination/state/tree-state.json","heartbeat_stale":false,...}
   Result: PASS
3. Shared resolver lib exists and resolves the canonical path
   Command: source ~/.claude/hooks/lib/workstreams-state-resolver.sh; resolve_workstreams_state_path "/tmp/legacy-fallback.json"
   Output: ~/claude-projects/workstreams-coordination/state/tree-state.json (config: ~/.claude/workstreams-state-path.txt)
   Result: PASS
4. All three writer hooks reference the resolver/canonical path
   Command: grep -l "workstreams-state-resolver|workstreams-coordination" workstreams-emit.sh workstreams-turn-emit.sh decision-context-gate.sh
   Output: all three matched
   Result: PASS
5. Migration commits in coordination repo
   Command: git -C ~/claude-projects/workstreams-coordination log --oneline
   Output: bc51dca (Phase B - recover 37 orphaned open nodes + 46 items), 32414d6 (Phase C - backfill Background on 37 open items), 4d61cd8 (r1: archive fixtures + enrich onboarding items), 5641358 (land canonical state file + cleanup inventory)
   Result: PASS

DEPENDENCY TRACE
================
Step 1: Hook fires (emit/turn-emit/gate)
  ↓ Verified at: ~/.claude/hooks/workstreams-emit.sh, workstreams-turn-emit.sh, decision-context-gate.sh (all source the resolver)
Step 2: Resolver reads ~/.claude/workstreams-state-path.txt
  ↓ Verified at: ~/.claude/hooks/lib/workstreams-state-resolver.sh (resolve_workstreams_state_path, replayed → canonical path)
Step 3: UI server reads the SAME file
  ↓ Verified at: state.js STATE_FILE + live /api/health state_file field (identical path)
Step 4: Migrated items present in the one file
  ↓ Verified at: coordination commits bc51dca/32414d6/4d61cd8; live /api/state = 947 nodes

Git evidence:
  - workstreams-coordination: bc51dca, 32414d6, 5641358, 4d61cd8 (migration); HEAD cc7d1ef
  - resolver lib mirror: ~/.claude/hooks/lib/workstreams-state-resolver.sh (mtime Jun 8 23:48)

Runtime verification: curl -s http://127.0.0.1:7733/api/health
Runtime verification: file ~/.claude/hooks/lib/workstreams-state-resolver.sh::resolve_workstreams_state_path
Runtime verification: file ~/.claude/workstreams-state-path.txt::workstreams-coordination/state/tree-state.json
Runtime verification: functionality demonstration — R8 end-user-advocate runtime artifact (.claude/state/acceptance/workstreams-consolidation-2026-06-08/r8-advocate-2026-06-10T02-52-35Z.json) exercised the live UI reading this state file; 4/4 scenarios PASS at plan_commit_sha 2b91389 (= repo HEAD)

Verdict: PASS
Confidence: 9
Reason: One canonical state path proven end-to-end — resolver lib + config + all three writer hooks + UI server resolve the identical file, and the 9-file migration commits are in the coordination repo log; live server is serving from it now.

EVIDENCE BLOCK
==============
Task ID: 2
Task description: Harvest the stranded pt/ redesign branches (v2 vertical, v3 accordion, toast, topology) into the live workstreams-ui; retire conversation-tree-ui husk.
Verified at: 2026-06-10T03:09:30Z
Verifier: task-verifier agent

Comprehension-gate: PASS-with-deviation (see plan-level articulation at top of this file; inline rubric applied)

Checks run:
1. R2 harvest commits merged to master
   Command: git -C neural-lace log --oneline master
   Output: cbee009 "Merge R2: lockfile name sync + stale-tab auto-reload fix" merging 687e1cf + 29b4048; branch feat/workstreams-r2-harvest-2026-06-09 has EMPTY diff vs master (fully merged)
   Result: PASS
2. detailModal count on master app.js
   Command: git grep -c detailModal master -- neural-lace/workstreams-ui/web/app.js
   Output: 4 (matches claimed replay)
   Result: PASS
3. Husk retired from master
   Command: git cat-file -e master:neural-lace/conversation-tree-ui
   Output: "exists on disk, but not in 'master'" — husk gone from master tree
   Result: PASS
4. Per-branch supersession spot-checks (R2 audit claim: every pt branch content on master in equal/evolved form)
   - toast-stacking: git grep -ci toast master -- web/app.js = 20 (toast handling present)
   - vertical/accordion panel redesigns: superseded by modal design (detailScrim/buildActionButtons x9 on master)
   - auto-emit-enforcement (Layer B reconciler): master:adapters/claude-code/hooks/conv-tree-emit-reconciler.sh AND workstreams-emit-reconciler.sh both exist
   - project-root topology: project-root logic present in master:adapters/claude-code/hooks/workstreams-emit.sh; topology plan archived (docs/plans/archive/conv-tree-project-root-topology.md)
   Result: PASS
5. Stranded branches still reachable (nothing deleted before harvest)
   Output: all five pt/ branches + feat/deterministic-workstreams-turn-emit listed in branch -a
   Result: PASS

Gap noted (non-blocking): the per-branch audit table artifact "wf_a6b13224-de6" cited by the orchestrator could not be located on disk; the substantive supersession claims were instead independently verified per check 4 above.

Git evidence:
  - master: cbee009 (merge), 687e1cf, 29b4048; husk absent from master ls-tree (only neural-lace/workstreams-ui remains)

Runtime verification: file ~/claude-projects/workstreams-ui-server/neural-lace/workstreams-ui/web/app.js::detailModal
Runtime verification: file ~/.claude/hooks/workstreams-emit.sh::workstreams-state-resolver
Runtime verification: functionality demonstration — R8 advocate artifact modal-detail scenario PASS (the harvested/evolved UI rendering live on 127.0.0.1:7733)

Verdict: PASS
Confidence: 8
Reason: Harvest-by-supersession verified — R2 commits merged (cbee009), husk gone from master, and every named pt/ branch's content independently spot-checked as present or evolved on master (toast x20, modal supersedes panel redesigns, reconciler + topology landed); branches remain reachable so nothing was lost.

EVIDENCE BLOCK
==============
Task ID: 3
Task description: Full-content item schema + emit (background + options + recommendation + links); fix turn-emit fragment-capture.
Verified at: 2026-06-10T03:10:30Z
Verifier: task-verifier agent

Comprehension-gate: PASS-with-deviation (see plan-level articulation at top of this file; inline rubric applied)

Checks run:
1. Phase C schema on master
   Command: git grep -c "ItemDetailsContentSchema|assembleItemDetails" master -- neural-lace/workstreams-ui/state/decision-context-schema.js
   Output: 15 matches
   Result: PASS
2. Turn-emit fragment guard (live mirror)
   Command: grep -n isCleanItem ~/.claude/hooks/workstreams-turn-emit.sh
   Output: 3 matches incl. line 403 "function isCleanItem(s)" and line 486 "if (!isCleanItem(txt)) return;  // FRAGMENT GUARD"
   Result: PASS
3. R6 backfill — zero boilerplate items in canonical state
   Command: node walk over ~/claude-projects/workstreams-coordination/state/tree-state.json counting /INCOMPLETE METADATA|populate me|[TODO]/ matches across all node items
   Output: 221 items walked, boilerplate: 0, items with substantive (>30 char) background: 41
   Result: PASS
4. R6 commit in coordination repo
   Output: 63d761e "R6: enrich 30 boilerplate open items with sourced context + add _category to 4 onboarding items" (30 + 4 = the claimed 34 enriched)
   Result: PASS
5. Live confirmation of no-garbage outcome
   Output: R8 advocate no-garbage-items scenario PASS (0 Turn-NNNN nodes, 0 fragments, 0 fixtures across 210 item rows + 158 node titles + whole-page sweep)
   Result: PASS

Git evidence:
  - neural-lace master: 0ef4527 "feat(workstreams): Phase C — self-contained items, no fragments/turn-noise"
  - workstreams-coordination: 63d761e (R6 enrichment), 32414d6 (Phase C backfill)

Runtime verification: file ~/.claude/hooks/workstreams-turn-emit.sh::isCleanItem
Runtime verification: file ~/claude-projects/workstreams-ui-server/neural-lace/workstreams-ui/state/decision-context-schema.js::ItemDetailsContentSchema
Runtime verification: curl -s http://127.0.0.1:7733/api/state
Runtime verification: functionality demonstration — R8 advocate scenarios no-garbage-items PASS + onboarding-items-enriched PASS (Backgrounds 369-692 chars with concrete asks, options, recommendations rendered live)

Verdict: PASS
Confidence: 9
Reason: Schema + fragment guard verified in code (master + live mirror), zero boilerplate items confirmed by direct count over the canonical file, and the live UI renders the enriched full-content items per the R8 advocate's onboarding + no-garbage scenario PASSes.

EVIDENCE BLOCK
==============
Task ID: 4
Task description: Modal detail overlay; context-appropriate buttons (approve/decline/submit/respond).
Verified at: 2026-06-10T03:11:30Z
Verifier: task-verifier agent

Comprehension-gate: PASS-with-deviation (see plan-level articulation at top of this file; inline rubric applied)

Checks run:
1. Modal + buttons code on master
   Command: git grep -c "detailScrim|buildActionButtons" master -- neural-lace/workstreams-ui/web/app.js
   Output: 9 matches (detailModal x4 separately); live server checkout has detailModal x4, buildActionButtons x5
   Result: PASS
2. R5 render fix merged
   Output: c4a2d55 "Merge R5: render fence-grammar content on field presence (drop _category gate) — R4 scenario-3 root-cause fix, selftests 79/79" on master
   Result: PASS
3. R8 advocate runtime artifact — modal-detail scenario
   Command: read .claude/state/acceptance/workstreams-consolidation-2026-06-08/r8-advocate-2026-06-10T02-52-35Z.json
   Output: scenario modal-detail verdict PASS; assertions: modal overlay (#detailScrim z-59 fixed + #detailModal z-60 centered 680x619, NOT a right panel), Background re-triggers memory, options x8 with what-it-does/risk/cost, recommendation rendered, context buttons swap by kind (decision → "Approve recommendation"/"Submit a decision…"; action → "Mark done"), Escape AND click-outside dismiss cleanly; 6 awaiting-me modals sampled
   Result: PASS
4. Artifact freshness
   Output: plan_commit_sha 2b9138950a97... = current repo HEAD; sibling r8-console.log / r8-network.log / DOM-dump evidence file present in the artifact directory
   Result: PASS

DEPENDENCY TRACE
================
Step 1: User clicks an awaiting-me item in the live UI
  ↓ Verified at: R8 advocate user-flow execution (live state via :7733, read-only twin at exact live commit 433f164, node-parity 947=947)
Step 2: detailModal/detailScrim open in front of the tree
  ↓ Verified at: web/app.js (detailModal x4, detailScrim) + R8 DOM computed-style assertions
Step 3: Context-appropriate buttons render per item kind
  ↓ Verified at: buildActionButtons in app.js + R8 assertion (decision vs action button sets)
Step 4: Escape/click-outside dismiss
  ↓ Verified at: R8 assertions (#detailModal.hidden=true both paths)

Git evidence:
  - master: 347cdd8 (Phase D modal + buttons), c4a2d55 (R5 render fix merge), 2bdc33a

Runtime verification: file ~/claude-projects/workstreams-ui-server/neural-lace/workstreams-ui/web/app.js::buildActionButtons
Runtime verification: file ~/claude-projects/neural-lace/.claude/state/acceptance/workstreams-consolidation-2026-06-08/r8-advocate-2026-06-10T02-52-35Z.json::"modal-detail"
Runtime verification: curl -s http://127.0.0.1:7733/api/health
Runtime verification: functionality demonstration — R8 advocate modal-detail scenario PASS (full user flow: open UI → filter Awaiting me → click item → modal w/ Background+options+recommendation+context buttons → Escape dismisses)

Verdict: PASS
Confidence: 9
Reason: Modal + context-button code is on master and on the live checkout, and the R8 runtime advocate adversarially exercised the exact plan scenario (modal overlay, not panel; kind-appropriate buttons; both dismissal paths) with PASS at the current plan SHA.

EVIDENCE BLOCK
==============
Task ID: 5
Task description: All-work-in-motion model: track build sessions + PRs + migrations through merged->deployed; surface un-deployed efforts.
Verified at: 2026-06-10T03:12:30Z
Verifier: task-verifier agent

Comprehension-gate: PASS-with-deviation (see plan-level articulation at top of this file; inline rubric applied)

Checks run:
1. R7 sweeper on master
   Output: master:neural-lace/workstreams-ui/scripts/work-in-motion-sweep.js exists; merge 433f164 "Merge R7: work-in-motion sweeper (idempotent plan/branch/PR ingestion) — selftest 37/37" is master HEAD
   Result: PASS
2. Selftest replay (verifier-executed)
   Command: node ~/claude-projects/workstreams-ui-server/neural-lace/workstreams-ui/scripts/work-in-motion-sweep.selftest.js
   Output: "work-in-motion-sweep selftest: 37 passed, 0 failed"
   Result: PASS
3. Canonical state carries the ingested work-in-motion nodes
   Command: curl -s http://127.0.0.1:7733/api/state | node count of node_id startsWith "wim-"
   Output: wim nodes: 176, total nodes: 947 (matches claimed 176: 21 ACTIVE plans + 154 branches + 1 PR)
   Result: PASS
4. Truthfulness of tracked state (R8 advocate real-work-in-motion scenario)
   Output: PASS — 21 ACTIVE plans on disk map 1:1 to 21 wim PLAN nodes; branch unshipped-counts patch-id-accurate (spot-checked +2/+4/+2); PR #482 OPEN with exact title; "Shipped-not-deployed" filter surfaces 1 un-deployed effort; "Deployed" honest empty state
   Result: PASS

Git evidence:
  - master: 433f164 (R7 merge), ae24845 (sweeper + selftest)
  - workstreams-coordination: cc7d1ef "r7: ingest work-in-motion (176 efforts...) via idempotent sweeper"

Runtime verification: file ~/claude-projects/workstreams-ui-server/neural-lace/workstreams-ui/scripts/work-in-motion-sweep.js::collectBranches
Runtime verification: curl -s http://127.0.0.1:7733/api/state
Runtime verification: functionality demonstration — R8 advocate real-work-in-motion scenario PASS (filters compared against actual git/plan/PR state; verifier re-ran the 37/37 selftest and re-counted 176 wim-* nodes live)

Verdict: PASS
Confidence: 9
Reason: Sweeper merged to master with the 37/37 selftest replayed green by the verifier, 176 wim-* nodes live in the canonical state via the running server, and the R8 advocate verified the tracked lifecycle states against actual plans/branches/PRs including the un-deployed-effort surfacing.

EVIDENCE BLOCK
==============
Task ID: 6
Task description: Merge feat/deterministic-workstreams-turn-emit; commit consumer-repo audits + delete corrupted-filename dupes.
Verified at: 2026-06-10T03:13:30Z
Verifier: task-verifier agent

Comprehension-gate: PASS-with-deviation (see plan-level articulation at top of this file; inline rubric applied)

Checks run:
1. Turn-emit hook on master (supersession path)
   Command: git -C neural-lace cat-file -e master:adapters/claude-code/hooks/workstreams-turn-emit.sh
   Output: blob EXISTS on master
   Result: PASS
2. Master version is the EVOLVED superset of the branch (supersession verified, not assumed)
   Command: git grep -c isCleanItem <ref> -- adapters/claude-code/hooks/workstreams-turn-emit.sh
   Output: master = 3 matches; feat/deterministic-workstreams-turn-emit = file/pattern ABSENT (branch predates the fragment guard) — master strictly supersedes the branch content; R2 audit verdict "branch superseded by evolved master version" confirmed
   Result: PASS
3. <consumer-product> audit docs committed
   Command: git -C <consumer-repo> log -1 408272f3
   Output: 408272f3 "docs(reviews): land UX/IA + cluster + deepdive audit reports" — 13 audit reports + "Deleted 8 empty corrupted-filename duplicates (invisible U+F00D before .md)" (13 + 8 = the 21 previously-uncommitted files)
   Result: PASS
4. Corrupted dupes actually gone from working tree
   Command: ls consumer-repo/docs/reviews/ | grep non-ASCII filenames; git status --porcelain docs/reviews/
   Output: 0 non-ASCII filenames; docs/reviews/ clean (no untracked leftovers)
   Result: PASS
5. Durability of the consumer-repo commit
   Command: git -C consumer-repo branch -a --contains 408272f3
   Output: chore/close-bh-simplify-plan + remotes/origin/chore/close-bh-simplify-plan (committed AND pushed)
   Result: PASS

Gap flagged (non-blocking for this task's verb "commit", but a required follow-up): 408272f3 is NOT yet on consumer-repo master — the audit docs live only on chore/close-bh-simplify-plan. Per merge-completed-work.md (docs-class PRs auto-merge when green), the orchestrator should merge or cherry-pick this branch to consumer-repo master; until then the audits are durable but not on the mainline.

Git evidence:
  - neural-lace master: workstreams-turn-emit.sh blob present (evolved, with FRAGMENT GUARD); branch feat/deterministic-workstreams-turn-emit (4407935) preserved, content superseded
  - consumer-repo: 408272f3 on chore/close-bh-simplify-plan + origin

Runtime verification: file ~/.claude/hooks/workstreams-turn-emit.sh::FRAGMENT GUARD
Runtime verification: file ~/.claude/hooks/workstreams-turn-emit.sh::isCleanItem
Runtime verification: functionality demonstration — the live turn-emit mirror is the merged/evolved hook; its output quality is exercised by the R8 no-garbage-items scenario PASS (0 fragments/turn-noise in the live UI)

Verdict: PASS
Confidence: 8
Reason: Turn-emit content is on master in strictly-evolved form (master has the fragment guard the branch lacks — supersession proven by direct ref comparison); the 21 consumer-repo files are resolved as 13 audits committed+pushed (408272f3) plus 8 corrupted dupes deleted and confirmed absent from the working tree. Follow-up flagged: land 408272f3 on consumer-repo master.
