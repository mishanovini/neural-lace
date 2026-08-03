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

### Task 1 — Comprehension Articulation (builder-authored, per Decision 020d; diff: 6bff352d+942b156f+60e4a3a2)

#### Spec meaning

Task 1 (docs/plans/gated-pipeline-master-2026-08.md) asks for the walking skeleton of THE GATED
PIPELINE: a single parser/validator library (`hooks/lib/review-chain-lib.sh`, REQ-B6)
implementing the THREE validity rules from design §4 exactly — (1) record parse: the `record:`
file exists, its LAST `## Verdict:`/`## Delta Verdict:` heading matches the chain's declared
verdict, and its `**Reviewer:**` line names the same agent; (2) three-way anchor match:
chain-declared blob == the blob the record's own `**Reviewed:** <path> @ <blob>` header attests
== `git hash-object` of the artifact at HEAD, with plan-side bytes CANONICALIZED (chain +
in-flight sections excluded, both comparison sides computed identically) and a separate WARN-only
`inflight-blob:` visibility check; (3) dispatch-ledger cross-check: a completion row matching
reviewer type + artifact_ref + a `[first-commit, record-commit]` ts window, with a pre-ledger
exemption keyed on the record's own `git log --follow` first-commit time. Paired with this is a
`--check`-only skeleton of the G2 gate (`hooks/dispatch-chain-gate.sh`) proving lib→gate wiring
end-to-end on real fixtures, with NO PreToolUse enforcement wiring yet (that's Task 17).

#### Edge cases covered

- Amendment-round records that open one verdict and close another (the real gated-pipeline
  plan-fidelity record does this: REFORMULATE → PASS) — rule 1 takes the LAST matching heading,
  not the first (`rc_record_verdict`, review-chain-lib.sh:150-156, `tail -1`).
- Author re-anchoring the chain's blob hex to match edited bytes without a fresh record —
  three-way match fails because the OLD record still attests the OLD blob (self-test scenario 3,
  review-chain-lib.sh:690-709; validated by `rc_rule2`, lines 375-407).
- Content drifting after a legitimate review with the chain never touched (a distinct failure
  shape — chain==record-attested but HEAD has moved) — same `rc_rule2` mismatch path,
  WARN-during-calibration vs FAIL-post-calibration flip on `RC_ANCHOR_CALIBRATION_END_DATE`
  (lines 397-403; self-test scenario 6, lines 742-756, calibration forced to a past date in the
  self-test setup so it exercises the FAIL branch, not WARN).
- Records predating the dispatch ledger's existence (Task 15 hasn't landed) — pre-ledger
  exemption keyed on `git log --follow --format=%ct` first-commit time, never a self-declared
  header date (rule 3, lines 409-449; self-test scenario 5, lines 728-737, backdated via
  `GIT_AUTHOR_DATE`/`GIT_COMMITTER_DATE`).
- Rename-detection false-positives across near-identical templated fixture files: `--follow`'s
  default similarity threshold mis-traced one fixture's history into an unrelated file's earlier
  commit during my own debugging, caught by running the debug script standalone vs. in the full
  suite and comparing outputs — fixed with `--find-renames=100%` (line 178).
- In-flight-only edits (the section deliberately excluded from the anchor) — produce a WARN,
  never a FAIL, and never block `--check`'s exit code (rule aggregation, `rc_validate_chain`
  lines 548-557 and 559-569; self-test scenario 7, lines 762-789).
- Empty `artifact_ref` in a ledger row — the "degraded" type-only match, distinguished in output
  text from a full match (rule 3, lines ~432-441).
- A plan with no `## Review Chain` section at all (the P-39 shape) — `dispatch-chain-gate.sh`
  emits all four gc_block fields and exits 1 (`_dcg_check`, dispatch-chain-gate.sh:56-100;
  self-test asserts all four `[GATE:*]` markers present).

#### Edge cases NOT covered

- The design-role anchor path (`rc_blob_of ... design`, plain `git hash-object`, no
  canonicalization) is exercised only by the static `tests/fixtures/review-chain/valid-chain-design.md`
  pair, not by the lib's own 8-scenario `--self-test`, which uses plan-role fixtures throughout
  for construction simplicity. Lower risk since design-role is strictly simpler (no
  section-stripping), but genuinely untested by the executable suite.
- `never-dispatched-plan.md`/`never-dispatched-record.md` and `derived-record.md` under
  `tests/fixtures/review-chain/` are built and manually verified (ran `rc_validate_chain` against
  `never-dispatched-plan.md` interactively: rule1/rule2 PASS, rule3 FAIL) but are NOT wired into
  any executable self-test in this commit — staged material for Task 17's three-variant D-15
  demo, not proven by an assertion here.
- `dispatch-chain-gate.sh` has no PreToolUse wiring, no `subagent_type` trigger logic, and no
  grandfather-slug handling — all explicitly deferred to Task 17 per the plan text; this diff
  only proves `--check` decides correctly.
- No test exercises TWO simultaneous design-reviews entries or multiple reviewers on one role —
  the parser (`rc_chain_entries`, lines 251-269) supports a list but only single-entry-per-role
  fixtures were built.

#### Assumptions

- `git hash-object` and `git log --follow` behave consistently under MSYS2/Git-Bash on Windows
  (this repo's actual runtime) — verified directly rather than assumed, since the
  rename-mis-attribution bug surfaced exactly this platform's `--follow` default behavior during
  self-test debugging.
- The dispatch-ledger row schema `{subagent_type, model, ts, session_id, artifact_ref}` (quoted
  in review-chain-lib.sh's header, lines ~55-59, and in `tests/fixtures/review-chain/README.md`)
  is fixed and will not change shape when Task 15 implements the real writer in
  `workstreams-emit.sh` — no code from that task to verify against, only the design/plan text's
  own quoted schema.
- `jq` is available in the execution environment for rule 3's ledger-row parsing (`rc_rule3`,
  lines ~424-436) — confirmed present in this session (jq-1.8.1) but not defensively
  fallback-coded if absent, matching the pattern of other harness scripts (e.g. doctrine-jit.sh)
  that also assume `jq`.
- Abbreviated (prefix) SHA citations in review records are a legitimate real-world form
  (`rc__sha_eq`, lines 239-246, prefix-tolerant) based on observing the real gated-pipeline
  review records use 8-char commit-style prefixes in their `**Reviewed:**` headers — an
  inference from the existing corpus, not confirmed against a written spec clause.

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

### Task 3 — Comprehension Articulation (builder-authored, per Decision 020d; diff: 6f5d1b22)

#### Spec meaning

REQ-A1 (plan Task 3, HR-F1) asks for three coupled fixes to `nl-maintenance.sh`'s
`--daemon`/`--watchdog` pair, plus a regression test that actually exercises them. First,
`single-flight-lib.sh` needs an `sf_release` API because its recursion guard is an env-var
set-once, never-cleared primitive — a correct assumption for a run-to-exit caller but a silent,
permanent wedge for a resident loop that re-enters the same guard every pass (the daemon ticked
once, then skipped forever). Second, `run_watchdog` must stop relaunching daemons blindly on top
of old ones: it has to read `daemon.pid`, and before ever killing the process it names, verify —
not assume — that the process is actually an `nl-maintenance --daemon`, because Windows PID reuse
makes an unverified kill capable of terminating an unrelated process. Third, the daemon self-test
(S11) has to prove both fixes under the REAL guard, not a `SF_DISABLE=1`-masked stand-in — a
masked test would pass whether or not the fix exists, which is no test at all.

#### Edge cases covered

- **Idempotent/ownership-safe release**: `sf_release()` (`single-flight-lib.sh:312-320`) only
  clears the recursion var + lock when the var is still `1` for THIS process — a second call, or
  a call for a name never acquired here, is a no-op (early return at :318), and it can never
  remove a lock a *different* process currently holds. Documented as the binding contract in the
  new header section "THE RUN-TO-EXIT ASSUMPTION" (`single-flight-lib.sh:74` onward): any
  `sf_guard` call site inside a resident loop MUST pair with `sf_release`.
- **Per-pass release in the daemon loop**: `run_daemon` now does guard → work → release every
  iteration (`nl-maintenance.sh:520-535`), calling `sf_release "nl-maintenance-tick"` after
  `run_tick` returns, guarded by `declare -F` tolerate-absent.
- **Identity-verified kill with platform fallback**: `_nm_pid_cmdline` (`nl-maintenance.sh:560-575`)
  tries `/proc/$pid/cmdline` first (MSYS2/Linux), falls back to `ps -fp` (:569) for macOS/BSD or
  when `/proc` is absent — `-f` specifically because a bare `ps -p` on this repo's MSYS2 `ps`
  prints only the executable path, never args. `_nm_pid_is_daemon` (:586-591) requires BOTH
  `nl-maintenance` and `--daemon` substrings; the watchdog (:637-648) kills only on match and
  always logs+skips on mismatch, then relaunches regardless.
- **S11 unmasking, and why `SF_DISABLE=0` at the invocation is required, not optional**: the
  self-test's setup exports `SF_DISABLE=1` globally for every OTHER scenario's isolation (:746);
  a backgrounded `bash ... --daemon` subprocess inherits that exported var, so without an
  explicit override the daemon under test runs with `sf_guard` fully bypassed — the scenario
  would pass identically whether or not `sf_release` exists. :902 now prefixes `SF_DISABLE=0`
  (S7's pattern, not S6's — S11 goes through `run_daemon → run_tick`, which scopes `SF_STATE_DIR`
  internally, so no separate override is needed the way S6's direct `_nm_tick_body` bypass
  requires). Verified empirically: temporarily disabling `sf_release` with the fix in place
  produced a genuine FAIL (1 distinct heartbeat epoch, 2 recursion-detected messages) — proof
  the test has teeth, not just proof it passes.

#### Edge cases NOT covered

- **A genuinely concurrent, different-process holder of `nl-maintenance-tick`**: a legitimate
  cross-process lock holder at the moment a pass's `sf_guard` fires means that pass returns 1 and
  writes no heartbeat — an inherent, rare race orthogonal to HR-F1, not exercised by S11 or the
  live demos. Bounded (next pass recovers) but not tested.
- **A true positive-match kill in the automated suite**: the self-test and live demos only
  exercise the identity-MISMATCH (log-and-skip) branch. The match → actually-kill branch was
  code-read but never driven end-to-end against a real running daemon (doing so live risks
  killing a real daemon on the test machine).
- **`ps -fp` fallback on a platform without `/proc`** (true macOS/BSD): reasoned and
  flag-confirmed, not executed on such a platform this session.
- **Both identity-check paths failing simultaneously**: `_nm_pid_is_daemon` treats empty/failed
  cmdline reads as non-match (fail-closed, never kill) by construction, but no scenario forces
  both paths to fail at once to prove it explicitly.

#### Assumptions

- **`/proc/<pid>/cmdline` availability under MSYS2/Git-Bash**: empirically probed this session
  (`cat /proc/$$/cmdline`) before writing the primary path — not taken on faith.
- **PID-reuse hazard model**: Windows recycles PIDs quickly, so `daemon.pid` can name a
  live-but-unrelated process; the fail-closed identity design (unknown/mismatched → never kill)
  treats this as a real hazard, per the task's own unbounded-harm framing.
- **Second-resolution `_nm_now`**: `date +%s` is 1-second granular; S11 uses `--interval 1`
  because at zero interval multiple passes complete within one wall-clock second, making
  distinct-heartbeat assertions unobservable regardless of the bug's presence.
- **Single resident daemon per machine as steady state**: the watchdog's kill-then-relaunch
  corrects transient violations (a wedged old daemon), not arbitration among multiple legitimate
  daemons.
- **`sf_release`'s ownership check is process-scoped by bash export semantics**: a child
  inheriting the recursion var is the same logical holder (mirrors `sf_guard`'s own recursion
  semantics rather than introducing a new trust boundary).

## Post-merge integration state (this train)

- master: `298f988d` → T1 ff (`60e4a3a2`) → T3 merge (`dc9f2299`) → manifest+INDEX integration
  commit (this train's tip; SHA in the commit log).
- All four affected self-test suites re-run green on merged master by the orchestrator:
  10/10 · 6/6 · 34/34 · 31/31.
- NOT yet pushed at the time of this entry (push follows the integration commit; G3's
  review-record push gate applies).

## Task 2 — Verifier verdict (task-verifier)

EVIDENCE BLOCK
==============
Task ID: 2
Task description: [parallel] Estate reconcile: stash docs/backlog.md churn; merge origin/master into local master via merge commit; push both mirrors; verify git rev-list --left-right --count = 0/0 against both — Verification: mechanical — Implements: REQ-A0
Verified at: 2026-08-03T10:44:04Z
Verifier: task-verifier agent

Oracle: derived (mechanical) — the git object database + both remote refs, re-fetched read-only and re-observed directly; the evidence file's word was not taken for any claim.

Comprehension-gate: not applicable (Verification: mechanical — Step-0 early-return class; no diff to articulate, git-state operation)
Operator invariants: none registered (exit 3) — `ask-registry.sh invariant-check --plan-slug gated-pipeline-master-2026-08`

Checks run (all re-executed by the verifier 2026-08-03, post `git fetch origin && git fetch pt`):
1. Merge-commit shape: `git log --format="%h parents:%p" -1 298f988d` → parents `b4e1cdbd 3a3994e2` — a true two-parent merge (DEC-10 merge-not-rebase honored). PASS
2. Both mirrors converged at the claimed SHA: `git rev-parse origin/master pt/master` → both exactly `298f988d943bbada31b206ad816be254130fe785`. PASS
3. Duplicate-content commits exist with subjects identical to local abfec199/11ac00b3: `git log --oneline -1 05c0cd58` / `da3838c8`. PASS
4. Nothing on either mirror is missing locally: `git rev-list --left-right --count master...origin/master` → `7 0` (and pt/master → `7 0`) — the 7 ahead are solely the subsequent unpushed T1/T3 train, outside T2's scope; 0 behind both. PASS

Runtime verification: command git rev-list --left-right --count 298f988d...origin/master   # → 0 0 (re-run post-fetch)
Runtime verification: command git rev-list --left-right --count 298f988d...pt/master       # → 0 0 (re-run post-fetch)
Runtime verification: command git merge-base --is-ancestor 298f988d origin/master          # → exit 0
Runtime verification: command git merge-base --is-ancestor 298f988d pt/master              # → exit 0

Verdict: PASS
Confidence: 9
Reason: PROVEN: every convergence fact re-observed directly against freshly-fetched remote refs — 298f988d is a two-parent merge commit present as the exact tip of both origin/master and pt/master, 0/0 at the reconcile point, 0-behind both mirrors now; duplicate-content review commits confirmed present. Re-ran everything; accepted nothing on faith (stash-handling narrative in notes is unverifiable post-drop but is not part of the Done criterion).
