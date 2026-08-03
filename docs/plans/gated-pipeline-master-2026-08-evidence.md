# Evidence — gated-pipeline-master-2026-08

Orchestrator: main session 4a470c8c (Fable). Convention: every builder claim below was
independently re-verified by the orchestrator before merge (self-tests re-run from the main
checkout, key sites read); "orchestrator-verified" lines cite what was actually re-run.

## Task 2 — Estate reconcile (REQ-A0) — Verification: mechanical

- What ran: `git stash push -- docs/backlog.md` → `git fetch origin && git fetch pt` →
  `git merge origin/master --no-edit` (merge commit, DEC-10 — rebase forbidden: local SHAs are
  chain-anchored in committed records) → `git push origin master` (origin carries both push URLs)
  → re-fetch both → stash resolution.
- Observed: incoming delta was docs/backlog.md only (+102) plus the two duplicate-content review
  commits (05c0cd58/da3838c8 ≙ local abfec199/11ac00b3); merge clean ("ort"); push accepted
  `3a3994e2..298f988d`.
- PASS check: `git rev-list --left-right --count master...origin/master` → `0 0` AND
  `master...pt/master` → `0 0` (both verified post-push, post-fetch). Convergence SHA `298f988d`.
- Notes: (a) the personal mirror announced `Required status check "validate" is expected` —
  partial branch protection exists there; recorded for the S-34 register entry. (b) the stash pop
  conflicted with the merged backlog (UU); resolved by taking the merge result (backlog
  auto-regenerates), stash dropped. (c) mid-reconcile the other machine pushed (pt moved
  6e28a82c→3a3994e2), so the reconcile handled live 5/5 divergence, not the planned 7/2 — same
  method, verified same outcome.

## Task 1 — Walking skeleton: review-chain-lib + dispatch-chain-gate --check (REQ-B6 core, REQ-B8 skeleton) — Verification: full

- Builder: plan-phase-builder (sonnet), worktree `gated-pipeline-task1`, commits
  `6bff352d` + `942b156f` (fixtures, two-batch split so rule 3's ledger window is a real range)
  + `60e4a3a2` (lib + gate + harness-guide row forced by docs-freshness-gate — fixed, not waived).
  Merged to master via fast-forward (task-order position 1).
- Prove-it (builder-run, then **orchestrator re-run on merged master**):
  `review-chain-lib.sh --self-test` → **10 passed, 0 failed** — all eight r3 fixture scenarios:
  honest-derived record FAILS rule 1 · never-dispatched reviewer FAILS rule 3 ·
  author-re-anchored-no-fresh-record FAILS rule 2 · wrong-artifact-ref row FAILS rule 3 ·
  pre-ledger-dated record PASSES 1-2 exempt from 3 · stale anchor FAILS post-calibration ·
  inflight change WARNs and passes · valid chain PASSES · (+ chainless-plan FAILS).
  `dispatch-chain-gate.sh --self-test` → **6 passed, 0 failed** (chainless plan blocks with all
  four gate-contract fields incl. [GATE:ESCAPE]; valid chain exits 0).
- The two binding arch-r3 constraints are implemented: plan-side attestation compares
  CANONICALIZED blobs on both sides; pre-ledger exemption keys on the record file's first-commit
  time (`git log --follow --format=%ct | tail -1`).
- Manifest: entries `review-chain-lib` (pattern, honest_status: --check-only consumer today) and
  `dispatch-chain-gate` (gate, wired_template:false, events:[], full §10 evidence fields:
  golden_scenario=P-39, fp_expectation modeled, retirement/demotion in data, honest_status naming
  T17 as the wiring task) — integrated by the orchestrator in the same merge train;
  `manifest-check` adds ZERO new REDs (3 remaining are pre-existing, owned by T8);
  `--gen-index` regenerated.
- Honest gaps (builder-declared, orchestrator-accepted): design-role (non-canonicalized) path is
  fixture-exercised but not in the 8-scenario self-test (strictly simpler path); the
  derived-record and never-dispatched fixtures are staged for T17's live three-variant demo, not
  wired to an executable check yet (T17's scope).
- Incident log: the builder's FIRST run returned **BLOCKED** — its worktree was created at a
  stale base (05c0cd58) predating the plan/design commits, and it refused to build from the
  prompt's paraphrase (correct behavior; the anti-fabrication discipline working). Second
  incident: the auto-cleaned worktree meant the resumed agent landed in the main checkout — it
  refused to commit there and created a fresh worktree via `spawn-worktree.sh`. Both filed as
  harness issues (worktree base ref; auto-clean resume footgun) in nl-issues 2026-08-03.

## Task 3 — HR-F1 daemon fix (REQ-A1) — Verification: full

- Builder: plan-phase-builder (sonnet), worktree `agent-a86f8de6c36c3ad1f`, final commit
  `6f5d1b22` (supersedes 9d3afbb9/a2085259). Merged to master at `dc9f2299`.
- What shipped: `sf_release` API in single-flight-lib.sh (idempotent; header states the
  run-to-exit assumption + resident-loop pairing rule); `run_daemon` releases per pass;
  `run_watchdog` reads daemon.pid and kills ONLY after cmdline identity verification
  (`/proc/<pid>/cmdline` → `ps -fp` fallback; mismatch ⇒ log-and-skip, never kill); S11 mask
  DELETED; runbook gains the sf_release contract + daemon-lifecycle paragraph.
- RED/GREEN (builder-run, evidence in commit message `## Root cause (evidenced)`):
  pre-fix code under the real guard → exactly 1 heartbeat + 2 recursion-skip messages across 3
  passes (the HR-F1 wedge, reproduced); post-fix → 3 distinct heartbeat epochs, 0 recursion
  messages. Live watchdog bogus-pid demo: planted foreign PID, watchdog printed "NOT killing
  (log-and-skip; PIDs are reused)", the foreign process survived (`kill -0` after), new daemon
  launched (pid file 10725→10838).
- **Orchestrator catch + fix cycle (recorded per §1):** first submission's rewritten S11 still ran
  the daemon under the suite-global `SF_DISABLE=1` (nl-maintenance.sh:746) with no override —
  the regression test would have passed WITHOUT the fix (the exact Q4/HR-F1 masking class).
  Sent back; builder added `SF_DISABLE=0` at the S11 invocation (with a required-not-optional
  comment) and produced the RED proof through the test itself: with sf_release disabled, S11
  FAILS with the original symptom (1 distinct epoch, recursion-skip messages, "29 passed, 2
  failed"). Orchestrator independently confirmed `SF_DISABLE=0` at line ~902 and re-ran both
  suites.
- Self-tests (**orchestrator re-run on merged master**): `single-flight-lib.sh --self-test` →
  **34 passed, 0 failed** (S14-S16 cover release/idempotency/ownership-safety);
  `nl-maintenance.sh --self-test` → **31 passed, 0 failed**.
- Honest gaps (builder-declared): a genuinely concurrent different-process holder of the tick
  lock still causes one skipped pass without a heartbeat (rare, orthogonal to HR-F1);
  `install-maintenance-task.ps1` untouched (WhatIf-verified contract unchanged).

## Post-merge integration state (this train)

- master: `298f988d` → T1 ff (`60e4a3a2`) → T3 merge (`dc9f2299`) → manifest+INDEX integration
  commit (this train's tip; SHA in the commit log).
- All four affected self-test suites re-run green on merged master by the orchestrator:
  10/10 · 6/6 · 34/34 · 31/31.
- NOT yet pushed at the time of this entry (push follows the integration commit; G3's
  review-record push gate applies).
