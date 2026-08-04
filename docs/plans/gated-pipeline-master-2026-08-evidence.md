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

### Task 1 — Comprehension Articulation (builder-authored, per Decision 020d; diff: 6bff352d+942b156f+60e4a3a2) — SUPERSEDED by the post-FM-023 version below (see "### Task 1 — Comprehension Articulation (updated)"); retained as the audited-FAIL historical record

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

## Comprehension audit (comprehension-reviewer, fable, 2026-08-03T11:05Z)

- **Task 3 — PASS (confidence 8).** 10/10 citations resolved EXACT against the merged diff;
  spec-meaning is a genuine own-words paraphrase with causal WHY; the SF_DISABLE-inheritance
  analysis matches the code comment and diff history exactly; NOT-covered list verified genuine
  (kill branch confirmed stub-only under HARNESS_SELFTEST). One non-blocking wording-precision
  note recorded (sf_release ownership absolute-claim holds only within the 120s tick-lock TTL —
  adjacent premises already surfaced).
- **Task 1 — FAIL (confidence 8), stage 3a (FM-023 spec-misparaphrase) — A PROVEN REAL BUG
  surfaced through the articulation audit:** rc_rule3's ts-window low bound computed from the
  RECORD file's first commit (lib :411-413, :428-430) where design §4 + the lib's OWN header
  (:53-54) specify the reviewed ARTIFACT's first commit. Single-commit records get a degenerate
  lo==hi window no real completion row can satisfy; every self-test row was minted at exactly
  the head-commit epoch (the one passing value), so the suite masked it; latent only because
  RC_LEDGER_LANDING_DATE is unset (everything exempt) — would detonate at Task 15. Plus two
  drifted citations (:150-156→:126-131, :251-269→:292-309) and a minor unguarded non-numeric-ts
  comparison at :439. Builder re-dispatched with the full fix order (artifact-arg for rc_rule3,
  non-coincident-timestamp scenario, malformed-ts guard, articulation corrections). This is the
  comprehension gate's designed catch class working: the audit compared the paraphrase against
  the spec against the code and found all three disagreeing.

## Task 1 — FM-023 fix cycle (commit 6c0cc0e5, merged at 4323339e)

- Fix: `rc_rule3` gains the reviewed artifact as a required 4th argument; window lo = the
  ARTIFACT's first-commit epoch via the generalized `rc_file_first_commit_epoch` (:174), hi = the
  record's commit time — matching design §4 and the lib's own header. Call site updated
  (rc_validate_chain :565). Malformed-ts guard (:467 regex + :483 WARN, skip-row fail-open form).
- RED proof (builder-run, method recorded): the OLD 3-argument signature was reconstructed
  standalone and run against the identical non-coincident t0<t1<t2 fixture — it produced the
  degenerate window [t2,t2] and REJECTED the legitimately-inside row, proving new scenario 9
  would have failed against the real bug.
- New scenarios: s9 (inside passes / before rejected / after rejected — three isolated rc_rule3
  calls on backdated commits) + s10 (malformed-ts: fails-not-crashes, WARN text present,
  malformed-plus-valid still passes). **Orchestrator re-run on merged master: 17/17 lib, 6/6
  gate.**
- New assumption surfaced (genuinely valuable for T15/T17): a ledger row with ts AFTER its
  record's commit (speculatively-committed record) would be wrongly rejected — nothing handles
  that case; T15/T17 dispatch flow must commit records after completion (the natural flow) or
  revisit.

### Task 1 — Comprehension Articulation (updated — post-FM-023 fix, commit 6c0cc0e5; AUDIT TARGET)

#### Spec meaning

Task 1 asks for the walking skeleton of THE GATED PIPELINE: a single parser/validator library
(`hooks/lib/review-chain-lib.sh`, REQ-B6) implementing the THREE validity rules from design §4
exactly — (1) record parse: the `record:` file exists, its LAST `## Verdict:`/`## Delta
Verdict:` heading matches the chain's declared verdict, and its `**Reviewer:**` line names the
same agent; (2) three-way anchor match: chain-declared blob == the blob the record's own
`**Reviewed:** <path> @ <blob>` header attests == `git hash-object` of the artifact at HEAD,
with plan-side bytes CANONICALIZED and a separate WARN-only `inflight-blob:` visibility check;
(3) dispatch-ledger cross-check: a completion row matching reviewer type + artifact_ref, with
`ts` falling in the window **[the reviewed ARTIFACT's first commit, the record's own commit
time]** — two distinct files, two distinct git-log lookups, not the same file's history read
twice — plus a pre-ledger exemption keyed on the *record's* own first-commit time. Paired with
this is a `--check`-only skeleton of the G2 gate (`hooks/dispatch-chain-gate.sh`) proving
lib→gate wiring end-to-end on real fixtures, with no PreToolUse enforcement wiring yet (Task 17).

#### Edge cases covered

- Amendment-round records with a later heading superseding an earlier one — rule 1 takes the
  LAST matching heading (`rc_record_verdict`, review-chain-lib.sh:126-131, `tail -1`).
- Author re-anchoring the chain's blob hex without a fresh record vs. content drifting after a
  legitimate review with the chain never touched — two distinct fixture constructions hitting
  the same three-way-mismatch code path with different WARN/FAIL calibration outcomes
  (`rc_rule2`; self-test scenarios 3 and 6).
- Records predating the dispatch ledger — pre-ledger exemption keyed on the RECORD's own
  `git log --follow` first-commit time (`rc_rule3`, review-chain-lib.sh:432, using the renamed
  generic `rc_file_first_commit_epoch`, line 174).
- **FM-023 fix, empirically RED→GREEN verified**: rule 3's ts-window lower bound is now the
  REVIEWED ARTIFACT's first commit (review-chain-lib.sh:450), not the record's — the call site
  in `rc_validate_chain` (line 565) passes `"$artifact"` as a required 4th argument. Self-test
  scenario 9 (lines 841-876) constructs non-coincident t0<t1<t2 and asserts a row at t1 PASSES
  while rows before t0 or after t2 are REJECTED. The OLD 3-argument signature was reconstructed
  standalone and run against the identical fixture: it produced window [t2,t2] and rejected the
  legitimately-inside row (exit 1), proving scenario 9 would have gone RED against the real bug.
- Malformed (non-numeric) `ts` in a ledger row — guarded by a regex check
  (`[[ "$rts" =~ ^-?[0-9]+$ ]]`, :467) that skips just that row with a WARN note (:483) rather
  than crashing bash's integer comparison; scenario 10 (:878-896) covers malformed-only (clean
  FAIL, no crash, WARN present) and malformed-plus-valid (still PASSES — the guard never costs a
  real match).
- Rename-detection false-positives across near-identical templated fixtures — `--follow`'s
  default similarity threshold mis-traced one fixture's history during debugging; fixed with
  `--find-renames=100%` (:181).
- A plan with no `## Review Chain` section — `dispatch-chain-gate.sh` emits all four gc_block
  fields and exits 1 (`_dcg_check`, dispatch-chain-gate.sh:56-100).

#### Edge cases NOT covered

- The design-role anchor path's POSITIVE case IS executably asserted (valid-chain-design.md
  validated end-to-end by the gate's `valid-chain-exit-zero` scenario). Genuinely untested:
  design-role FAILURE branches — every negative fixture in both self-tests uses plan-role.
- `never-dispatched-*.md` and `derived-record.md` fixtures are built and manually verified, not
  wired to an executable assertion — staged material for Task 17's three-variant demo.
- `dispatch-chain-gate.sh` has no PreToolUse wiring, subagent_type trigger logic, or
  grandfather-slug handling — explicitly Task 17's scope.
- No test exercises two simultaneous reviewers under one role (`rc_chain_entries`, :296-313,
  parses a list; only single-entry-per-role fixtures built).
- The malformed-ts guard is tested for literal non-numeric strings; a wholly-missing `ts` field
  is handled by the pre-existing `[[ -n "$rts" ]] || continue` one line above, covered
  incidentally rather than by a targeted assertion.

#### Assumptions

- `git hash-object` / `git log --follow` consistency under MSYS2/Git-Bash — verified directly
  (the rename bug surfaced this platform's `--follow` behavior; the FM-023 fix was verified
  against real git history, not assumed).
- Window semantics assume reviewer dispatches are never backdated relative to their record's
  commit; a ledger row with ts legitimately AFTER its record's commit (speculatively-committed
  record) would be wrongly rejected — unhandled by design or diff, unconfirmed against
  T15/T17's real flow (surfaced for those tasks).
- `jq` present for rule-3 ledger parsing (confirmed jq-1.8.1; no fallback, matching harness
  convention).
- The dispatch-ledger row schema `{subagent_type, model, ts, session_id, artifact_ref}` is fixed
  until T15 lands (no code to verify against; design/plan-quoted schema only).

## Task 4 — HR-F2+F5+F8 single-writer cache fix (REQ-A2) — Verification: full

- Builder: plan-phase-builder (sonnet), worktree `agent-af6a93a3178eb7fd7`, commit `d46beee5`.
  Merged to master at `ec349c3f`.
- What shipped: doctor's quick-mode writer is the cache's ONLY writer repo-wide; sf-skip serves
  the cached verdict verbatim (exit = cached exit_code) or exits DISTINCT code 3 with
  `[doctor] SKIPPED (<reason>)` (:343-344; contract documented :24-26, :328); digest
  `refresh_doctor_cache` is invoke-and-read-only; fingerprint gains live-hooks newest-mtime
  (:381-394) + working-tree-dirty bit (HR-F5); install.sh --verify treats exit 3 as
  SKIPPED-not-FAILED (consumer sweep fix).
- Live demonstrations (builder-run, scoped HOME): (1) valid cache + fresh lock → cached verdict
  served verbatim, cache md5-identical before/after; (2) no cache + pre-claimed lock → SKIPPED
  line, RC=3, no cache created; (3) refresh → doctor's own 5-field record with fingerprint,
  digest never wrote.
- Self-tests: digest **102/102 incl. new S23 single-writer scenario (5 sub-assertions)** —
  **orchestrator re-run on merged master: 102/102**; single-flight 25/25 (untouched file — note:
  the T3-merged master version is 34/34; the worktree predates T3's merge, irrelevant to T4's
  diff); doctor 174/179 with the 5 failures PROVEN pre-existing via git-stash A/B by the builder
  (jq-parity class, unrelated checks — orchestrator accepts the A/B method; the 5 belong to the
  T8 triage population).
- Consumer sweep (builder, repo-wide rg): install.sh FIXED; health-tick path structurally
  unreachable for exit 3 (always SF_DISABLE=1); two eval scenarios A/B-verified byte-identical;
  three non-consumers confirmed prose/pattern-only.
- Honest gaps (builder-declared): two OTHER doctor skip paths (NL-FINDING-040 reentry guard,
  SESSIONSTART-SINGLEFLIGHT-01) still bare-exit-0 — outside HR-F2/F5/F8's named site; recorded
  here + nl-issue for the sweep class. Real --quick scans measure 200-300s+ on this repo
  (consistent with HR-F3's TTL finding, Task 7's scope). docs/backlog.md was un-committable due
  to the pre-existing hygiene-gate condition (same class as the operator-todo nl-issue).

### Task 4 — Comprehension Articulation (builder-authored, per Decision 020d; diff: d46beee5, merged at ec349c3f; citations re-resolved against the merged blob — AUDIT TARGET)

#### Spec meaning

REQ-A2 (design r3, discharging HR-F2+F5+F8) asks for the doctor's verdict cache to become
single-writer: only `harness-doctor.sh`'s own quick-mode write path may ever put bytes in
`doctor-cache.json`. Two consequences follow. First, the sf_guard skip path must stop doing a
bare `exit 0` (indistinguishable from a real GREEN to any caller, and the F2 corruption's other
half) — on skip it must either serve the existing cached verdict honestly, or exit a distinct,
documented, non-0/1 code (3) with a parseable line. Second, `session-start-digest.sh`'s
`refresh_doctor_cache` — previously a second writer with an incompatible 3-field schema — must
become invoke-and-read-only: force a real doctor recompute, then read back whatever the doctor's
own writer produced, never printf anything itself. The fingerprint (HR-F5) must widen from 4
file mtimes + HEAD to include the live hooks mirror's newest mtime and a working-tree-dirty bit,
since those are real inputs `run_quick_checks` reads that the original coverage silently
excluded.

#### Edge cases covered

- **sf-skip, valid cache present** → serves the cached `verdict_line` verbatim and exits the
  cache's own `exit_code`, never re-deriving or annotating (`harness-doctor.sh:331-345`
  `_doctor_serve_cache_or_skip`; call site :7485-7489). Runtime-proven: exit matched the primed
  cache's exit_code (1, FAILED); cache md5 identical before/after.
- **sf-skip, no/invalid cache** → distinct code 3 with `[doctor] SKIPPED (<reason>)`
  (:343-344). Runtime-proven: pre-claimed lock + empty cache → exit 3, no cache file created.
- **refresh forcing a real recompute, never a no-op** → `SF_DISABLE=1
  DOCTOR_VERDICT_CACHE_DISABLE=1` bypasses both skip and cache-hit (`session-start-digest.sh:563`),
  then reads the fresh 5-field record off disk (:570-571); stdout capture is only the
  wrote-nothing fallback (:573-576).
- **Fingerprint drift classes**: live-hooks newest-mtime scan (:386-394) catches an edited LIVE
  hook (the claimed-vs-actual drift surface previously uncovered); `git diff --quiet` dirty bit
  (:407-411) catches uncommitted repo-file edits — the other half of D5's promise.
- **Consumer sweep + exit-3 tolerance**: `install.sh:2019-2030` branches exit 3 distinctly as
  non-fatal; `health-tick.sh:261` reaches the digest path where exit 3 is structurally
  unreachable (always SF_DISABLE=1 — verified by reading, not asserted); both eval scenarios
  pass fresh `HARNESS_DOCTOR_HOME` per call (no cross-call lock state possible), A/B-verified
  byte-identical.
- **Self-tests updated to the honest contract, not left stale**: 9b asserts the skip serves call
  1's cached GREEN (:7195-7198); 9c asserts exit 3 on fresh-dir/no-cache (:7219); NEW S23
  (`session-start-digest.sh:2626-2687`) proves single-writer end-to-end: digest path → doctor's
  real 5-field record → second direct doctor call is a byte-identical cache HIT, never a second
  write.

#### Edge cases NOT covered

- Two OTHER doctor skip paths still bare-exit-0, untouched: NL-FINDING-040 reentry guard
  (:7423-7427, exit 0 at :7426) and SESSIONSTART-SINGLEFLIGHT-01 (:7506-7515, exit 0 at :7512).
  HR-F2/F5/F8's grounding named only the sf_guard doctor-quick site; widening was out of
  dispatched scope — logged as follow-up (nl-issue), not silently dropped.
- 5 pre-existing doctor self-test failures (jq-parity class: deterministic-process-proof /
  new-gate-evidence-bar / claim-honesty / budget-chains) confirmed pre-existing via git-stash
  A/B: identical 5 failures with this diff stashed out.
- Real `--quick` measures 200-300s+ wall-clock on this repo (vs the header's documented 30-60s)
  — the known HR-F3 finding, Task 7's scope, not changed by this diff.

#### Assumptions

- The cache-file path contract holds across both files (`DOCTOR_CACHE_PATH` override, else the
  two independent default path functions) — both must resolve to the SAME file for single-writer
  to mean anything; verified by setting one shared `DOCTOR_CACHE_PATH` in S23 and the live demos
  rather than assuming the defaults agree by construction.
- `LIVE_HOME` scopes via `HARNESS_DOCTOR_HOME`, but `REPO_ROOT` always resolves via
  `git rev-parse --show-toplevel` — the doctor always scans the REAL checkout even inside a
  HOME-scoped fixture (confirmed by reading resolve_repo_root); this explains S23's real
  repo-scan latency.
- No `jq` dependency introduced: reader/writer on both sides use `sed`; jq present on this
  machine but not load-bearing for this diff.

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

## Task 3 — Verifier verdict (task-verifier, final — supersedes the 2026-08-03T10:44Z INCOMPLETE)

EVIDENCE BLOCK
==============
Task ID: 3
Task description: [parallel] HR-F1 fix: sf_release API in single-flight-lib.sh (+ header run-to-exit statement); run_daemon releases per pass; run_watchdog identity-verified kill; S11 mask DELETED; S11 asserts ≥2 real ticks under the real guard — Verification: full — Implements: REQ-A1
Verified at: 2026-08-03T11:12:00Z
Verifier: task-verifier agent

Oracle: derived (pre-fix behavior) — the HR-F1 wedge symptom (1 heartbeat + recursion-skips across 3 passes) is the RED baseline; the fix's discriminating test (S11) demonstrably FAILS against it (commit 6f5d1b22 message, PROVEN block: sf_release stubbed → S11b/S11c FAIL, 29/31; restored → 31/31).

Comprehension-gate: PASS (confidence 8) — comprehension-reviewer (fable) audit persisted in this file ("## Comprehension audit", commit 9214c3ef): 10/10 citations resolved EXACT against the merged diff; spec-meaning a genuine own-words paraphrase with causal WHY; NOT-covered list verified genuine. Articulation (all four sub-sections, diff-anchored to 6f5d1b22) at "### Task 3 — Comprehension Articulation", commit e12feec1. Verifier spot-checked citations independently: sf_release :312, run_daemon release :533-534, _nm_pid_cmdline :560-563 with ps -fp fallback, watchdog log-and-skip :637-649, SF_DISABLE=0 :902, S11 --interval 1 :887 — all exact.
Operator invariants: none registered (exit 3) — `ask-registry.sh invariant-check --plan-slug gated-pipeline-master-2026-08`

Checks run (all re-executed by this verifier on merged master @ c3dae56c, 2026-08-03):
1. `single-flight-lib.sh --self-test` → 34 passed, 0 failed (S14 release/re-acquire = THE HR-F1 fix; S15 idempotency; S16 ownership safety). PASS
2. `nl-maintenance.sh --self-test` → 31 passed, 0 failed; S11 observed live under the REAL guard: S11b "3 distinct" heartbeat epochs across 3 passes, S11c zero recursion-skips. PASS
3. RED demonstrated (FIX-task reproduction rule): commit 6f5d1b22 message records before/after with the SAME command — sf_release disabled + SF_DISABLE=0 → S11 FAILS with the exact original symptom (1 distinct epoch, recursion-skip x2, 29/31); restored → 31/31 (re-run green by this verifier). PASS
4. S11 mask deleted: no SF_DISABLE=1 at the S11 invocation; suite-global :746 export explicitly overridden by SF_DISABLE=0 at :902 (required-not-optional comment :888-893). PASS
5. Docs impact: single-flight-halt-runbook.md carries the sf_release contract (:44) + daemon-lifecycle paragraph (:70); lib header carries THE RUN-TO-EXIT ASSUMPTION. PASS
6. Integration point: install-maintenance-task.ps1 untouched by this train (last commit e5432f3c, predecessor plan) — matches builder claim. PASS

Runtime verification: command bash adapters/claude-code/hooks/lib/single-flight-lib.sh --self-test   # → 34 passed, 0 failed (verifier re-run)
Runtime verification: command bash adapters/claude-code/scripts/nl-maintenance.sh --self-test         # → 31 passed, 0 failed incl. S11 under real guard, 3 distinct epochs (verifier re-run)
Runtime verification (before): nl-maintenance.sh --self-test with sf_release disabled
  Commit: 6f5d1b22 (recorded in-message; pre-fix behavior = 9d3afbb9 state)
  Expected: FAIL — S11b 1 distinct epoch + S11c recursion-skip (the HR-F1 wedge)
  Observed: "29 passed, 2 failed" with exactly those two failures (commit message PROVEN block)
Runtime verification (after): same command, fix in place
  Commit: 6f5d1b22 (merged at dc9f2299)
  Expected: PASS — 31/31
  Observed: 31 passed, 0 failed — re-run by this verifier on merged master

DEPENDENCY TRACE
================
Step 1: run_daemon pass completes
  ↓ Verified at: nl-maintenance.sh:533-534 (sf_release "nl-maintenance-tick" per pass)
Step 2: sf_release clears recursion var + lock, re-acquire succeeds
  ↓ Verified at: single-flight-lib.sh:312 + S14b/S14c/S14d observed green
Step 3: next pass writes a fresh heartbeat
  ↓ Verified at: S11b live — 3 distinct epochs across 3 passes
Step 4: watchdog reads daemon.pid, identity-verifies before kill, log-and-skip on mismatch
  ↓ Verified at: nl-maintenance.sh:108/:637 (_nm_pid_path read), :560-575 (/proc cmdline + ps -fp fallback), :637-649 (verified-kill vs "NOT killing (log-and-skip; PIDs are reused)")

Verdict: PASS
Confidence: 9
Reason: PROVEN: both suites re-run green by this verifier on merged master; the fix's RED/GREEN is fully evidenced with the same discriminating command failing pre-fix and passing post-fix; every wire arrow traced to file:line; comprehension-gate precondition now satisfied by the persisted comprehension-reviewer PASS record (9214c3ef, confidence 8, 10/10 exact citations) with independent verifier spot-checks. Accepted from the builder transcript (not re-run): the live bogus-pid watchdog demo — statically traced instead (:637-649); re-running launches a real daemon on this machine.

## Task 5 — HR-F6 friction unification (REQ-A3) — Verification: full

- Builder: plan-phase-builder (sonnet), worktree `agent-a067991d14d11d751`, commit `be5e4273`.
  Merged to master (task-order slot 5).
- What shipped: `NL_MAINT_FRICTION_LEDGER` default → `~/.claude/state/workaround-sensor.jsonl`
  (`nl-maintenance.sh:413`); pane jq keys off non-empty `bypass_kind` → per-gate `workarounds`
  (:414-419, defensive null/empty filter). **Block-event decision: DEFERRED with recorded
  rationale (:398-412)** — gc_block's 7+ call sites carry no gate identifier and its four-line
  output contract is lint-locked; a block is definitionally not an escape, so routing blocks
  through `bypass_kind` would corrupt the workaround-rate signal; metric renamed workarounds-only
  rather than shipping a permanently-zero field (constitution ¶1 class). End-to-end proven:
  `gc_escape_used` via the real lib chain → dashboard row `{"gate":"testgate","workarounds":1}`;
  empty-ledger → `{"available":true,"rows":[]}`.
- Self-tests: nl-maintenance **37/37** (new S9 round-trip, S9b empty-ledger, S14 end-to-end via
  the real lib) — **orchestrator re-run in worktree AND on merged master: 37/37**;
  workaround-sensor 15/15; gate-contract 16/16; maintenance-pane.selftest.js **9/9**
  (orchestrator re-run).
- In-flight scope disclosure: app.js + index.html consumer fix (recorded in the plan's In-flight
  scope updates; the pane renderer would otherwise print "undefined blocks").
- Honest gaps (builder-declared): live browser DOM render not verified (JSON contract verified;
  no dev server — cockpit deliberately down this session); `docs/harness-guide.md:385` carries a
  stale gate-friction sentence from an earlier plan (candidate for T21 drain, noted not fixed);
  concurrent ledger writers unlocked (pre-existing `-sc` behavior, unchanged).
- Builder-authored Comprehension Articulation included in the builder report verbatim (audit
  target below, appended at the report's own section).

### Task 5 — Comprehension Articulation (builder-authored, per Decision 020d; diff: be5e4273 — AUDIT TARGET)

#### Spec meaning

REQ-A3/HR-F6: the friction pane's reader and the only real writer (`gc_escape_used` →
`ws_record`) pointed at different files with different schemas, so the pane was structurally
guaranteed to stay empty forever. Fix: point the reader's default at the writer's actual path,
make the jq key off the writer's actual field (`bypass_kind`, not the never-emitted `event`),
decide honestly whether block-events can join the same ledger, and prove `gc_escape_used` →
dashboard row end-to-end plus the empty-ledger honest-empty case.

#### Edge cases covered

- Ledger file absent entirely → `available:false`, honest empty state, pre-existing behavior
  preserved (`nl-maintenance.sh:851-869`, Scenario 8, untouched).
- Ledger exists but is 0 bytes (distinct from absent) → `available:true, rows:[]`, zero-counts
  not an error (:880-888, new Scenario 9b).
- Multiple rows for one gate → aggregated via `group_by(.gate)` into one `workarounds` count
  (:414-419; Scenario 9 asserts `"workarounds":2`).
- A row with missing/empty `bypass_kind` is not counted (defensive filter :418) — malformed
  lines cannot corrupt the count.
- The real caller path — Scenario 14 sources the actual gate-contract-lib and calls the actual
  `gc_escape_used`, proving the wire, not just the schema shape.

#### Edge cases NOT covered

- Block-event counting itself: explicitly deferred with recorded rationale — scoped, recorded
  non-coverage, not an oversight.
- Concurrent writers to the ledger during a dashboard read (no locking) — pre-existing `-sc`
  behavior, unchanged by this task.
- Live browser verification of the pane render — JSON contract verified (self-test + manual
  e2e); DOM render not (no dev server running; app.js outside T5's declared scope).

#### Assumptions

- `ws_record`'s schema is stable — read directly from `workaround-sensor-lib.sh:186-221` rather
  than trusting the plan's paraphrase (the HR-F6 lesson applied to itself).
- No other consumer reads `gate_friction.rows[].blocks` — verified by grepping the full
  workstreams-ui tree before removing the key; only the one render site matched.
- The plan's Files-to-Modify reflects planned scope, not a bar against same-commit fixes to a
  consumer one's own change breaks — disclosed, recorded in In-flight scope updates.

## Task 5 — Verifier verdict (task-verifier)

EVIDENCE BLOCK
==============
Task ID: 5
Task description: HR-F6 fix (after Task 3 — same file): NL_MAINT_FRICTION_LEDGER default → workaround-sensor.jsonl; pane jq maps bypass_kind rows → workarounds; block-event decision recorded (gc_block counter rows or explicit metric rename); end-to-end test gc_escape_used → pane row — Verification: full — Implements: REQ-A3
Verified at: 2026-08-03T12:20:00Z
Verifier: task-verifier agent

Oracle: specified — the task's three Prove-it-works steps plus the sanctioned either/or decision branch; the writer's actual schema (ws_record in workaround-sensor-lib.sh) is the derived contract the pane must key off (the HR-F6 lesson itself).

Comprehension-gate: PASS (confidence 8) — comprehension-reviewer audit (commit 077ad2c6, "## Comprehension audit — Task 5" below): 7/7 citations grounded (+5 corroborating fact-checks); DEFER-with-rename verified honestly recorded AND mechanically executed; no-other-consumer grep independently re-run by the reviewer. Articulation (four sub-sections, diff-anchored to be5e4273) committed at 657f336b.
Operator invariants: none registered (exit 3) — re-run 2026-08-03T12:05:09Z, registry plan-scoped and unchanged since

Checks run (re-executed by this verifier on merged master @ 077ad2c6):
1. `nl-maintenance.sh --self-test` → **37 passed, 0 failed** including S9 (row names real gate; both bypass_kind rows counted → "workarounds":2; NO 'blocks' key emitted), S9b (empty 0-byte ledger → available:true, zero-count rows, no error), S14 (sources the ACTUAL gate-contract-lib, fires the ACTUAL gc_escape_used → dashboard row under gate=testgate, one escape = one workaround). S14+S9b ARE Prove-it 1-3, executed live on this machine via the real lib chain. PASS
2. `node neural-lace/workstreams-ui/server/maintenance-pane.selftest.js` → **9 passed, 0 failed** (envelope, passthrough-verbatim, malformed-snapshot no-crash). PASS
3. Wire arrow: `friction_path="${NL_MAINT_FRICTION_LEDGER:-${live_home}/state/workaround-sensor.jsonl}"` at nl-maintenance.sh:413. PASS
4. Wire arrow: pane jq `group_by(.gate) | map({gate, workarounds: (map(select(.bypass_kind != null and .bypass_kind != "")) | length)})` (:414-420) — keys off exactly the field `ws_record <gate> <bypass_kind> ...` writes (workaround-sensor-lib.sh:25/:48/:181-188), with the defensive null/empty filter. PASS
5. Sanctioned either/or branch: DEFER-with-rename decision recorded at :398-412 (gc_block carries no gate id; four-[GATE:*]-line contract lint-locked; block ≠ escape so bypass_kind routing would corrupt the workaround-rate signal; no permanently-zero field per constitution ¶1) AND the rename executed — no `blocks` key in the pane JSON, executable-asserted by S9. This IS that branch's completion per the task's own text ("gc_block counter rows OR explicit metric rename"). PASS
6. In-flight consumer fix: app.js renders `workarounds`-only (:1124) with the DEFER rationale mirrored (:1071-1078); index.html in the same commit; `node --check app.js` clean; disclosed in the plan's "## In-flight scope updates" (2026-08-03 entry) — a fix to a break the task's own schema change causes, correctly recorded. PASS
7. Integration point: commit be5e4273 touches ONLY nl-maintenance.sh + app.js + index.html — the 4 live gc_escape_used call sites (gate bodies) untouched as the task requires; one proven firing end-to-end via S14's real-lib chain. PASS

Runtime verification: command bash adapters/claude-code/scripts/nl-maintenance.sh --self-test   # → 37 passed, 0 failed incl. S9/S9b/S14 (verifier re-run on merged master)
Runtime verification: command node neural-lace/workstreams-ui/server/maintenance-pane.selftest.js   # → 9 passed, 0 failed (verifier re-run)
Runtime verification: command node --check neural-lace/workstreams-ui/web/app.js   # → clean (verifier re-run)

DEPENDENCY TRACE
================
Step 1: a gate escape fires gc_escape_used <gate> <kind>
  ↓ Verified at: S14 — sources the actual gate-contract-lib, real call, scoped ledger
Step 2: ws_record appends a bypass_kind row to workaround-sensor.jsonl
  ↓ Verified at: workaround-sensor-lib.sh:181-188 (writer) ≡ pane default path :413 (reader) — same file at last
Step 3: pane jq aggregates per-gate workarounds from bypass_kind
  ↓ Verified at: nl-maintenance.sh:414-420 + S9 ("workarounds":2) observed green
Step 4: dashboard consumer renders the row (workarounds-only, no blocks key)
  ↓ Verified at: app.js:1119-1124 + maintenance-pane.selftest.js 9/9 + S9's no-blocks assertion

Verdict: PASS
Confidence: 9
Reason: PROVEN: both suites re-run green by this verifier on merged master — S14 exercises the full real-lib chain gc_escape_used → ledger → pane row (Prove-it 1-2) and S9b the empty-ledger honest-zero case (Prove-it 3); every wire arrow traced writer-to-renderer at the merged blob; the sanctioned DEFER-with-rename branch is recorded (:398-412) and mechanically executed (no blocks key, S9-asserted); the in-flight consumer fix is disclosed in the plan and verified. Accepted (builder-declared, consistent with cockpit-down session): live browser DOM render not exercised — the JSON contract is verified at every layer up to the render call site; carried as an honest gap, not blocking (app.js render is one string-template from verified data).

## Task 6 — HR-F9+F4 manifest entries + zero-substrate inverse (REQ-A4) — Verification: contract

- Built orchestrator-side per the plan's task text (after T3-T5 merges), commit `422257c2`.
- Manifest entries: `nl-maintenance-core`, `doctor-verdict-cache`, `maintenance-both-substrates-alive`
  (162 total; each honest_status names its real state incl. the not-registered activation gap and
  the single-writer provenance); `manifest-check` → 1 pre-existing RED only (session-heartbeat,
  T8-dispositioned); `--gen-index` regenerated.
- HR-F4 inverse: `check_maintenance_both_substrates_alive` gains the zero-substrate branch —
  marker absent ∧ heartbeat stale (<2h window) ∧ all legacy tasks Disabled ∧ manifest declares
  managed_by=nl-maintenance → WARN, RED after `.zero_substrate.red_after_days` from
  `.zero_substrate.legacy_disabled_since` (dates in data, HR-F7 rule; fields added to
  schedule-manifest.json with legacy_disabled_since=2026-08-02).
- **Live probe (contract evidence): the check FIRED on this machine's real state** —
  `[doctor] WARN maintenance-zero-substrates: zero maintenance substrates alive (legacy Disabled
  since 2026-08-02, replacement unregistered; RED at 14d, now 1d) -- T10 registration pending`.
  Doctor `bash -n` syntax clean.
- Honest gap: no dedicated self-test scenario for the inverse branch yet (selftest:false stated
  in the manifest entry honestly; the live probe is the contract evidence; a scenario rides the
  predecessor's Known-gap-#2 follow-up).

## Task 8 — REQ-A8 doctor triage — Verification: full — STATUS: PARTIAL (open; survivors dispositioned)

- Builder: plan-phase-builder (sonnet), worktree `agent-a87622c2020ce66a5`, commit `a011d934`,
  merged. Classification table appended to `docs/reviews/2026-08-02-estate-entropy-triage.md`
  (2026-08-03 section).
- 8a baseline: quick tier = 34 RED lines / 12 check-ids (NOT the historical 71 — that was the
  full-tier figure; recorded honestly). The check-8 self-test sweep ran 90+ min without
  finishing — live confirmation of P-14.
- 8b fixes (orchestrator re-verified): harness-architecture.md regenerated (cleared
  wave-f-f2-docs); manifest-check split-exemption + 2 scenarios (REDs 3→1, 30/30 self-test);
  plan-edit-validator stat-shim fix (20/4 → **24/24, orchestrator re-run**).
- 8c retires: 0. 8d waivers: 0 — the review-reviewer-independence grandfather candidate was
  investigated (10 PROVEN post-cutover self-approvals via git-author inspection) and REJECTED
  after reading decision 067 (deliberately enforceable-RED by design). Correct restraint.
- 8e re-measure: 22 REDs — **≤9 NOT met**; every survivor dispositioned: 17 RED lines require
  main-session/T21 execution (live-mirror writes + worktree pruning — sandbox-blocked for
  builders, 4 denial classes documented), 12 owned by T5/T6/T7/decision-067 enforcement.
  T8's checkbox stays OPEN until the survivors' owners land and 8e re-measures ≤9.
- Root-caused (not fixed): the 5 P-14 "jq-parity" self-test failures are a self-test-harness
  Windows/MSYS2 shim defect (`_nonode_path()` symlinks bash itself → companion-DLL load failure),
  NOT doctor production bugs (real jq expressions verified standalone against live data). Filed
  SELFTEST-SWEEP-NONODE-SHIM-WINDOWS-01 + MODEL-PIN-GATE-SELFTEST-NONHERMETIC-01.
- Salvage: the builder's backlog delta (3 entries) was hygiene-blocked in its worktree; the
  orchestrator applied it on master post-exemption (committed in 422257c2).

### Task 8 — Comprehension Articulation (builder-authored, per Decision 020d; diff: a011d934 — AUDIT TARGET when T8 closes)

#### Spec meaning
Inventory doctor REDs via `--full`, classify every distinct check-id fix/retire/waiver with a
rationale, execute fixes surgically (never delete-as-fix), land waivers only via the doctor's
existing waiver convention where the gate genuinely doesn't apply, re-measure, target ≤9 with
every survivor named.

#### Edge cases covered
manifest-check exemption doesn't leak (S3c: orphaned body file still REDs; 30/30); stat-shim fix
tries the real/correct form first so it doesn't mask a genuine BSD-side break; P-14 diagnosis
independently confirmed against live data before concluding self-test-infra-not-doctor-bug;
review-reviewer-independence waiver candidate rejected only after reading decision 067 in full.

#### Edge cases NOT covered
Check-8 sweep incomplete (~40 hooks unswept; plan-reviewer/review-record-gates failures observed,
not root-caused); docs/backlog.md changes uncommitted in the worktree (orchestrator salvaged);
the 4 live-mirror REDs and worktree/branch pruning have known-safe remedies the builder could not
execute (sandbox-blocked; fully specified with exact commands in the triage doc).

#### Assumptions
"≤9" counts raw RED lines (matches RED_COUNT and the historical framing), not unique check-ids;
the sandbox's 4 consistent denials across distinct action classes are a structural boundary, not
a probeable permission; review-reviewer-independence's other 9 records share the same binary
detection mechanism as the 1 individually verified.

## Task 7 — Mechanized flips + targeted fixes (REQ-A5) — Verification: full

- Builder: plan-phase-builder (sonnet), worktree `agent-a580ebd9a93c3a623`, commit `6c975cbb`,
  merged at `7b5217d0`. All five sub-targets delivered (7a dates in schedule-manifest schema v3;
  7b doctor reads them + managed_by satisfied-by-construction via _note; 7c pid-liveness in
  `_sf_is_stale` + `SF_HALT_DIR` canonical split — closes the implementation review's note-2
  race; 7d doctor-quick TTL 1200s justified against fresh live re-measurement (421s/425s cold
  cycles this session) + HR-F10 renames; 7e real Get-Counter measurement appended to the perf
  doc: 31 samples/30s/first-discarded, avg 4.98%). Fix-status table rows F3/F7/F10/F11 updated
  in the same commit.
- Self-tests: single-flight-lib **43/43** (9 new scenarios) — **orchestrator re-run in worktree
  AND on merged master**; digest **102/102** (orchestrator re-run on master, backgrounded run
  b15xgavz9); doctor full self-test skipped per the task's own allowance (90+ min) — substituted:
  bash -n clean + two live cold `--quick` runs (421s/425s, no regression, new WARN texts firing
  on the real coord-sync/budget entries) + 9 hand-built fixtures replicating the cadence/budget
  scenarios (builder-run). Builder caught its own set-u unbound-var bug pre-ship.
- **Cross-file integration regression caught by the orchestrator's post-merge suite re-run:**
  nl-maintenance S6 planted its HALT fixture in the scoped SF_STATE_DIR; the lib now (by design)
  consults canonical SF_HALT_DIR → 35/37. Root cause evidenced by the FAIL output
  (halted:false heartbeat) + the design's own REQ-A5 line ("self-tests override SF_HALT_DIR
  explicitly"). Test-env fix at `34384396` (S6 scopes SF_HALT_DIR); suite **37/37 re-run**.
  Production drain path unchanged. Lesson: a lib semantic change must re-run CONSUMER suites,
  not just its own — added to the completion-report lessons list.
- Builder honest gaps: doctor full suite never run this session (allowance); the renamed doctor
  scenario not isolated-re-run; fix-status SHA one amend-iteration behind (pre-existing table
  convention). Builder-authored articulation in its report (audit target when T7 verifies).

### Task 7 — Comprehension Articulation (recovered verbatim from the builder's own subagent session transcript after builder output-file loss; builder a580ebd9a93c3a623; diff: 6c975cbb)

RECOVERY NOTE: this task's Comprehension Articulation was never committed to this evidence file
before the builder's task output-file was truncated to 0 bytes. It has been recovered VERBATIM
from `~/.claude/projects/<this-project>/4a470c8c-e5e4-49bb-a8f8-131206e35b58/subagents/agent-a580ebd9a93c3a623.jsonl`
(the builder's own per-agent session transcript, stored under the main session 4a470c8c's
`subagents/` directory) — the main session's top-level transcript JSONL was checked first and
contains only a final summary line ("Comprehension Articulation: included above...") without the
actual sub-sections; the subagent's own transcript carries the full text. The four sub-headings
below use the builder's own wording verbatim, including its own bolded lead-ins.

**Spec meaning (own words):** Task 7 mechanizes four review findings the harness review flagged as "prose-only WARN with no flip mechanism" or "stale test-name/HALT-path assumptions" — the class constitution paragraph-1 explicitly bans ("no mechanism = say there is no mechanism"). HR-F7 needed the cadence and budget WARN checks to carry actual stored dates that flip them to RED, not just comments promising a future flip; I implemented this as `warn_since`/`red_after` fields on `schedule-manifest.json`'s `cadence_check` (`adapters/claude-code/config/schedule-manifest.json:8`) and a new `budget_check` object (`:12,14`), read by `check_schedule_manifest_cadence` (`adapters/claude-code/hooks/harness-doctor.sh:2438`) and `check_budget_bash_hooks` (`:2564`). HR-F3 needed the single-flight guard's staleness check to stop being pure-TTL (which lapses mid-run once guarded work outlives the TTL) — I added owner-pid liveness via `_sf_owner_pid`/`_sf_owner_alive` (`adapters/claude-code/hooks/lib/single-flight-lib.sh:264,275`) consulted first inside `_sf_is_stale` (`:299`), plus raised doctor-quick's TTL 120s→1200s (`harness-doctor.sh:7728`) with a comment citing my own fresh 421s/425s re-measurement. HR-F10 needed two test-scenario labels renamed to say what they now actually validate (`harness-doctor.sh:7386`, `session-start-digest.sh:2512`). HR-F11 needed HALT's resolution split from the (scopable) lock directory into its own canonical `SF_HALT_DIR` (`single-flight-lib.sh:204`, consumed by `sf_halt_set` at `:213`).

**Edge cases covered:** owner-alive-at-stale-TTL (S17, lock survives regardless of age); owner-confirmed-dead (S18, reclaimed via a real forked-and-reaped pid); owner-file-with-no-recorded-pid (S19, falls back to pure TTL, the pre-fix behavior preserved for that case); HALT-in-canonical-dir-while-locks-scoped-elsewhere (S20, drains correctly); HALT-dropped-only-in-a-scoped-dir (S21, correctly does NOT drain — proves the split is real, not default-coincidence); cadence/budget red_after-in-the-past (RED) vs red_after-in-the-future (stays WARN) vs absent (WARN forever, never fabricates RED); managed_by=nl-maintenance + live activation marker (satisfied-by-construction NOTE, never warns even past red_after) — the exact HR-F7 false positive the finding named. All verified either via the real self-test suites (single-flight-lib.sh 43/43, session-start-digest.sh 102/102) or hand-built fixtures replicating the doctor's own `_scenario_dir`/`_run_quick` harness against the real script.

**Edge cases NOT covered:** the ONE renamed doctor scenario (`9-ssf-explicit-invocation-never-suppressed-BY-SSF`) was not re-run in isolation — it depends on prior scenario state (a held SESSIONSTART-SINGLEFLIGHT-01 lock) not cheaply reconstructable outside the full 90+ min `--self-test`; I verified only that the rename is a pure string change with no logic touched. PID-reuse-at-liveness-check-time (a dead pid recycled by the OS to an unrelated live process between staleness-check and reclaim) is a known, accepted, pre-existing race class in this codebase (same shape as nl-maintenance.sh's watchdog identity check) — not newly introduced, not specifically tested here. The digest's own "digest-<repo>" TTL (120s) was NOT raised or re-measured — task scope was explicitly doctor-quick only; I added a justification comment explaining why (lighter workload, no dedicated measurement exists) rather than fabricating a number.

**Assumptions:** `kill -0 <pid>` reliably signals liveness/deadness under MSYS2 bash on Windows for both self-spawned test pids and real cross-process owners (consistent with existing `kill -0`-based identity checks elsewhere in this codebase; not independently re-verified beyond my own self-test's fork/reap pattern). `red_after`/`warn_since` as bare `YYYY-MM-DD` strings parse correctly via `date -d` on this platform (verified live). The review-finding-fix-gate's token regex requires a hyphenated ID and never matches this review file's bare `F3`/`F7`/`F10`/`F11` labels — confirmed empirically (gate allows regardless of staging); filed as `nl-issue`. The "FIXED @ &lt;sha&gt;" self-citation in the fix-status table cites `7dc1b2f7`, one amend-iteration behind the true final SHA `6c975cbb` — an unavoidable regress (amending to fix a self-citation changes the hash again); this matches this same table's own pre-existing convention (F2's row cites a non-final SHA with a parenthetical).

## Task 10 — Registration prep + DEC-4 ask (REQ-A7) — Verification: contract

- Orchestrator-direct (schtasks operations are sandbox-blocked for builders — the T8 lesson).
- **Installer end-to-end proof (contract evidence):** name-patched scratch copy (TaskName →
  NL-MaintenanceT10Test — the ONLY delta, honoring the hard stop's letter against registering
  the real name pre-ratification): register with `-RepoPath` → `Get-ScheduledTask` shows
  State: Ready → `-Rollback` → verified GONE → zero stray nl-maintenance processes. The
  legacy-task idempotence path also exercised (all "already Disabled -- no-op").
- **DEC-4 ratification ask surfaced: `NY-1785771976-caeb`** (needs-you.sh, tier 2, §3 compact
  format with per-option outcomes; links to the T3/T4 implementation review — the F-3
  precondition's "fixed AND re-reviewed" record — and the plan). The cold-reader lint BLOCKED
  two drafts before accepting the third (single-line text fails the multi-line requirement;
  the lint working as designed) — rendered into NEEDS-YOU.md.
- Registration itself: NOT executed — awaits operator 'ratify'/'pure-tick'/'hold' per DEC-4.

## Comprehension audit — Task 5 (comprehension-reviewer, fable, 2026-08-03T11:58Z)

- **Task 5 — PASS (confidence 8).** 7/7 citations grounded (+5 corroborating fact-checks); the
  sanctioned DEFER-with-rename decision verified as honestly recorded AND mechanically executed
  (rename executable-asserted by S9's no-blocks assertion; rationale's load-bearing facts all
  PROVEN — gc_block carries no gate id, bypass_kind is documented as escape-kind); the
  no-other-consumer grep independently re-run (zero residuals). Two non-blocking notes: a
  syntactically-corrupt ledger line fails the whole slurped jq read → safe honest-empty but
  silently drops valid rows (handled incidentally, unlisted — T21-class follow-up candidate);
  one two-line citation imprecision.

## Comprehension audit round 2 (comprehension-reviewer, fable, 2026-08-03T11:32Z)

- **Task 1 (re-audit, post-FM-023 fix) — PASS (confidence 8).** All three required-before-re-review
  items verified resolved; 12/12 citations grounded (11 exact, 1 one-line-off); scenario 9 judged
  structurally discriminating against the old bug independent of the builder's RED narrative
  (the t0<t1<t2 fixture forces the old record-keyed window [t2,t2] to reject the inside row). Two
  trivial wording notes (":181"→:182; "4th argument" ordinal slip — artifact is 3rd, arity claim
  true), no re-review needed.
- **Task 4 (first pass) — PASS (confidence 8).** 17/17 sampled citations exact; both default
  cache paths independently verified to converge (doctor :309, digest :530); the
  exit-3-unreachable-via-health-tick claim verified by reading; NOT-covered section judged
  exemplary (both remaining bare-exit-0 skip paths precisely cited). One wording note: the dirty
  bit sees UNSTAGED edits only (matches REQ-A2's literal contract per the builder's own code
  comment) — accepted-per-spec blind spots (staged/untracked) noted for the record.

## Task 1 — Verifier verdict (task-verifier, final — supersedes the 2026-08-03T10:44Z INCOMPLETE)

EVIDENCE BLOCK
==============
Task ID: 1
Task description: Walking skeleton: hooks/lib/review-chain-lib.sh v1 — three validity rules per design r3 §4 + full r3 fixture set + --check-only skeleton of dispatch-chain-gate.sh; two binding arch-r3 constraints — Verification: full — Implements: REQ-B6 (core), REQ-B8 (skeleton)
Verified at: 2026-08-03T12:05:09Z
Verifier: task-verifier agent

Oracle: specified — the task's Prove-it-works steps + the design r3 §4 fixture-verdict table; plus derived (pre-fix) for the FM-023 fix: the reconstructed OLD 3-arg rc_rule3 signature run against the identical t0<t1<t2 fixture produces the degenerate [t2,t2] window and rejects the legitimately-inside row (RED method recorded in the fix-cycle entry; scenario 9 judged structurally discriminating by the round-2 audit independent of the builder narrative).

Comprehension-gate: PASS (confidence 8) — comprehension-reviewer round-2 re-audit of the UPDATED articulation (commit b6e65886, this file "## Comprehension audit round 2"): 12/12 citations grounded, all three required-before-re-review items resolved, scenario 9 independently judged discriminating. The round-1 FAIL (PROVEN rule-3 window bug) is resolved by 6c0cc0e5, merged 4323339e.
Operator invariants: none registered (exit 3) — re-run 2026-08-03T12:05:09Z

Checks run (all re-executed by this verifier on merged master @ b6e65886):
1. `review-chain-lib.sh --self-test` → **17 passed, 0 failed** — all original 10 scenarios PLUS s9-window-inside-passes / s9-window-before-rejected / s9-window-after-rejected and the four s10 malformed-ts assertions. PASS
2. `dispatch-chain-gate.sh --self-test` → **6 passed, 0 failed**. PASS
3. Prove-it 2/3 live (prior pass, unchanged surfaces): --check chainless → exit 1 with all four [GATE:WHAT]/[GATE:WHY]/[GATE:FIX]/[GATE:ESCAPE] fields; --check valid-chain → exit 0. PASS
4. FM-023 fix re-traced at the merged blob: `rc_rule3 <reviewer-token> <artifact-ref-path> <artifact-file> <record-file>` (artifact a REQUIRED arg); window lo = `rc_file_first_commit_epoch "$artifact"`, hi = record's commit time — two different files, two git-log calls, with the FM-023 comment naming the old collapse; call site `rc_rule3 "$reviewer_token" "$artifact_ref" "$artifact" "$record"` in rc_validate_chain (~:565); pre-ledger exemption still keyed on the RECORD's first commit; malformed-ts regex guard skip-row fail-open with WARN. PASS
5. Binding constraints (i) canonicalized-blob comparison and (ii) record-first-commit exemption keying: verified in the prior pass, unchanged by the fix commit. PASS
6. Manifest entries + INDEX (c3dae56c) verified in the prior pass. PASS

Runtime verification: command bash adapters/claude-code/hooks/lib/review-chain-lib.sh --self-test   # → 17 passed, 0 failed (verifier re-run on merged master)
Runtime verification: command bash adapters/claude-code/hooks/dispatch-chain-gate.sh --self-test     # → 6 passed, 0 failed (verifier re-run)
Runtime verification: command bash adapters/claude-code/hooks/dispatch-chain-gate.sh --check adapters/claude-code/tests/fixtures/review-chain/chainless-plan.md   # → exit 1, four contract fields
Runtime verification: command bash adapters/claude-code/hooks/dispatch-chain-gate.sh --check adapters/claude-code/tests/fixtures/review-chain/valid-chain-plan.md # → exit 0

DEPENDENCY TRACE
================
Step 1: fixture plan carries ## Review Chain
  ↓ Verified at: tests/fixtures/review-chain/valid-chain-plan.md (parsed live)
Step 2: dispatch-chain-gate.sh sources lib, calls rc_validate_chain
  ↓ Verified at: dispatch-chain-gate.sh:44 (source), :71 (call)
Step 3: lib validates rules 1-3; rule 3 windows [artifact-first-commit, record-commit] per ledger row
  ↓ Verified at: review-chain-lib.sh rc_rule3 (4-arity, artifact_first_commit lo) + s9/s10 observed green
Step 4: FAIL path emits complete instruction via gc_block
  ↓ Verified at: dispatch-chain-gate.sh:62/:87 + live chainless output

Verdict: PASS
Confidence: 9
Reason: PROVEN: all 17 lib + 6 gate scenarios re-run green by this verifier on merged master; the FM-023 correction re-traced line-by-line at the merged blob (artifact-keyed lo bound, 4-arity signature, call-site propagation, malformed-ts fail-open); the comprehension-gate precondition satisfied by the persisted round-2 PASS record (b6e65886). HYPOTHESIZED (surfaced, not blocking — T15/T17 obligation): a ledger row with ts after its record's commit (speculatively-committed record) would be wrongly rejected; REFUTED IF T15's real flow commits records before completion rows mint — carried in the articulation's Assumptions and this file's fix-cycle entry for T15/T17 to discharge.

## Task 4 — Verifier verdict (task-verifier)

EVIDENCE BLOCK
==============
Task ID: 4
Task description: [parallel] HR-F2+F5+F8 fix, single-writer form: doctor sf-skip serves cached verdict else exit 3 with SKIPPED line; refresh_doctor_cache invoke-and-read-only; fingerprint gains live-hooks newest-mtime + dirty bit; new self-test scenario asserts single-writer property — Verification: full — Implements: REQ-A2
Verified at: 2026-08-03T12:05:09Z
Verifier: task-verifier agent

Oracle: specified — the task's three Prove-it-works steps (cache-hit serve, empty-cache skip contract, single-writer refresh), exercised via the digest suite re-run + a verifier-constructed live probe of the skip path.

Comprehension-gate: PASS (confidence 8) — comprehension-reviewer first-pass audit (commit b6e65886, "## Comprehension audit round 2"): 17/17 sampled citations exact; cache-path convergence and exit-3-unreachable-via-health-tick verified by the reviewer; NOT-covered section judged exemplary. Articulation (four sub-sections, diff-anchored to d46beee5) committed at bc629975.
Operator invariants: none registered (exit 3) — re-run 2026-08-03T12:05:09Z

Checks run (re-executed by this verifier on merged master @ b6e65886):
1. `session-start-digest.sh --self-test` → **102 passed, 0 failed**, including all five S23 single-writer assertions: S23a real [doctor] verdict via digest path · S23b fingerprint present (doctor's 5-field writer, not digest's old 3-field one) · S23c numeric ts_epoch · S23d direct doctor re-run is a cache HIT · S23e cache file byte-identical across digest invocation + doctor cache-HIT read. PASS (covers Prove-it 1 and 3)
2. LIVE PROBE (verifier-constructed, Prove-it 2): guard held for "doctor-quick" in a scoped HOME with EMPTY cache → doctor emitted machine-parseable `[doctor] SKIPPED (single-flight guard active)`, exit code 3, and created NO cache file. Command: source single-flight-lib; SF_STATE_DIR=<scratch> sf_guard doctor-quick 120; HOME=<scratch> SF_DISABLE=0 bash harness-doctor.sh --quick → observed exactly the contract. PASS
3. Wire arrow: digest `refresh_doctor_cache` is invoke-and-read-only — runs `SF_DISABLE=1 DOCTOR_VERDICT_CACHE_DISABLE=1 bash harness-doctor.sh --quick` (the exact plan-specified envs) then reads back via sed; full-file sweep shows the ONLY doctor-cache.json references outside comments are path helpers (:527/:530) and self-test fixture variables — NO write redirect from the digest module. PASS
4. Wire arrow: doctor `_doctor_serve_cache_or_skip` (~:331-345) serves cached verdict with the CACHED exit code or exits distinct code 3; wired at the sf_guard skip site (~:7485-7489), never a bare exit 0. PASS
5. Wire arrow: `_doctor_compute_fingerprint` includes live-hooks-dir newest-mtime (portable find loop, ~:386-394) and the working-tree-dirty bit via `git diff --quiet` (~:407-411; unstaged-only per REQ-A2's literal contract, per the audit's wording note). PASS
6. Consumer sweep spot-check: install.sh --verify branch treats exit 3 as SKIPPED-not-FAILED (:2019-2030, comment citing this task). PASS
7. Cache-path convergence independently confirmed: doctor `_doctor_verdict_cache_path` (:309) ≡ digest `_doctor_cache_path` (:530) for the default HOME layout. PASS

Runtime verification: command bash adapters/claude-code/hooks/session-start-digest.sh --self-test   # → 102 passed, 0 failed incl. S23a-e (verifier re-run on merged master)
Runtime verification: command SF_STATE_DIR=<scratch> sf_guard doctor-quick 120; HOME=<scratch> bash adapters/claude-code/hooks/harness-doctor.sh --quick   # → "[doctor] SKIPPED (single-flight guard active)", exit 3, no cache file (verifier live probe)

DEPENDENCY TRACE
================
Step 1: digest (or --refresh-doctor-cache) needs a doctor verdict
  ↓ Verified at: session-start-digest.sh refresh_doctor_cache (:557+) — invokes doctor --quick with SF_DISABLE=1 DOCTOR_VERDICT_CACHE_DISABLE=1
Step 2: doctor's OWN writer produces the 5-field cache record (single writer repo-wide)
  ↓ Verified at: S23b/S23c live (fingerprint + numeric ts_epoch present after digest-path invocation)
Step 3: subsequent doctor run within TTL serves the cache (byte-identical file)
  ↓ Verified at: S23d/S23e live
Step 4: sf-skip with no valid cache → distinct exit 3 + parseable SKIPPED line; consumers treat 3 as inconclusive
  ↓ Verified at: verifier live probe (exit 3, no cache created) + install.sh :2019-2030

Verdict: PASS
Confidence: 9
Reason: PROVEN: the digest suite re-run green by this verifier (102/102 incl. the S23 single-writer quintet); the empty-cache skip contract re-observed live by a verifier-constructed probe (SKIPPED line, exit 3, no cache file); every wire arrow traced at the merged blob; comprehension record persisted at b6e65886. Accepted with recorded rationale (not re-run): the doctor FULL self-test at 174/179 — the 5 failures are git-stash-A/B-PROVEN pre-existing (jq-parity class, T8's triage population), and the plan's own REQ-A8 done-bar rule makes targeted self-tests, never global doctor state, the done-bar for Tasks 1-7; re-running the 200-300s suite would re-measure T8's baseline, not T4's behavior.

## Task 18 — G3 class review-set (REQ-B9) — Verification: full — MERGED c5ee36d6 + remediation

- Build bd4a4ea4 + T16-ordered remediation ab2caf9e (F-2 non-saturation via F_CHANGED scoping +
  CG6 proving fixture; F-3 gate globs; F-4 in-row corpus_measurement per token, re-measured with
  the fixed mechanism, conservatism caveat load-bearing; F-5 named exemption additions).
  Fidelity re-check: CLEAR TO MERGE (appended to the T16 record trail; CG6 independently re-run
  by the reviewer). Orchestrator post-merge suite: 86/3/1 → after the CI round-2 stat-order fix
  merged: **self-test: OK (1 skipped — honest NTFS guard)**.

### Task 18 — Comprehension Articulation (builder-authored, per Decision 020d; diff: bd4a4ea4; builder agent a614ebf430ad7cea2 — AUDIT TARGET; NOTE: this is the only articulation in the builder's transcript — the T16-ordered remediation round, commit ab2caf9e, did not produce a second/updated one)

## Comprehension Articulation

**Spec meaning (re-resolved citations):** REQ-B9 (design `docs/designs/gated-pipeline-master-2026-08-03.md:304`) and G3 (design `:237-244`) require extending `review-record-push-gate.sh` with the DEC-5 (design `:134`) class table: per-class required review sets, per-class posture, provenance-docs exemption, same-push honoring "reading records AS OF the local SHA being pushed." I mapped `required_reviews` tokens to three verification mechanisms: `harness` reuses the pre-existing `rrg_is_covered` per-blob check outright (no reimplementation, per the M-3 rule cited in `review-chain-lib.sh:16`); `evidence` checks for a `docs/plans/*evidence*` touch in the push's own diff; any other token is a reviewer-agent type verified by `git grep` + `git show <sha>:<path>` against `docs/reviews/**`, reusing `rc_record_reviewer`/`rc_record_verdict` from `review-chain-lib.sh:126-166` verbatim (as instructed: "reuse existing rrg record-parsing + review-chain-lib where cleaner"). Messages use `gate-contract-lib.sh`'s `gc_block`/`gc_header` (`gate-contract-lib.sh:37-69`).

**Edge cases covered:** empty `flip_date` (treated as "still calibrating," WARN forever, matching the HR-F7 no-prose-flips convention already used by `RC_ANCHOR_CALIBRATION_END_DATE`); a class table absent at the pushed sha (quiet no-op, not a degradation — the file predates its own existence for old commits); a present-but-unparseable table (loud WARN, per this extension's own fail-open contract, distinct from the authoritative check's block-on-missing-lib); an operator override marker (checked and logged once per push, suppressing this extension's block the same way it suppresses the per-blob check's); the `architecture-reviewer` token's "if-triggered" qualifier (only evaluated when a pushed harness-class path also matches `architecture_trigger_globs`); multiple touched classes in one push (each evaluated independently, closest to a logical OR on blocking).

**Edge cases NOT covered:** transcript-anchored binding of a specific review to specific bytes at the class-gate level (named residual in the design's NON-GOALS, `:325`) — the class-gate is a coarser "has this class had its required reviewer types active at all" check, not a per-diff binding; a record materialized via `git show` whose parse depends on `git log --follow` history walking from the checked-out HEAD rather than the pushed sha (a pre-existing limitation in the reused `rc_file_first_commit_epoch`, not newly introduced — I deliberately did not wire rule-3's ledger cross-check into this extension since RC_LEDGER_LANDING_DATE is unset by default and would be a no-op today; noted as a fast-follow once Task 15 lands).

**Assumptions:** `required_reviews` tokens map to the four mechanisms above (harness/evidence/reviewer-type) — the "evidence" and "architecture_trigger_globs" mechanisms are my own concretization of the design's prose, not literally spelled out in the design table, and should be revisited by `plan-fidelity-reviewer`/`harness-reviewer` at review time; the "product"/"other-docs" required-review tokens (`code-reviewer`, `plan-fidelity-reviewer`) are my own reasonable defaults, not explicitly named in the task dispatch.

## CI triage rounds 1-2 (Task 8 remit) — MERGED 85ebd520/d6e70175 (r1), 436c5854 (r2)

- r1 PROVEN roots: CI hook loop shared fd0 → one hook's bare `cat` drained stdin → every sweep
  silently truncated to ~30/83 hooks (CI never tested the rest, even when green); GC_MODE
  mis-resolution on direct -body.sh execution; Evals: 8 oversized compacts + INDEX rows. Post-fix:
  Evals GREEN (first since 2026-08-02), sweep genuinely 83 hooks (79 pass, doctor allowlisted
  w/ tracker, 3 first-exposure fails).
- r2 PROVEN roots (all genuine bugs, none env-quirks): review-record-push-gate `_rrpg_mtime_epoch`
  GNU/BSD stat fallback REVERSED + GNU stat's stdout leak corrupting $mtime → EVERY valid
  override marker silently rejected on all platforms (the T18 re-check advisory's exact worry —
  fixed before the 2026-08-10 flip arms); auto-install fixture missing cutover_ref (stale vs the
  C2-A security fix; two-commit cutover pattern applied); digest S12 `-x` gate on a 100644 file
  never executed directly (Windows fileMode=false masked it; `-f` now). Digest final scenario
  slow-on-Windows — CI re-run is the authoritative confirmation (watched below).

## Task 6 — Verifier verdict (task-verifier)

EVIDENCE BLOCK
==============
Task ID: 6
Task description: HR-F9+F4 fix (orchestrator-integrated; after Tasks 3-5): manifest.json entries for nl-maintenance, doctor-verdict-cache, both-substrates-alive; zero-substrate WARN (RED after 14 days, dates in schedule-manifest.json data); manifest-check.sh --gen-index regenerated — Verification: contract — Implements: REQ-A4
Verified at: 2026-08-03T22:36:00Z
Verifier: task-verifier agent (Verification: contract — locked-shape checks re-observed directly; evidence file's word not taken for anything re-observable)

Oracle: contract — the manifest/schedule-manifest locked shapes + the doctor's own live WARN emission on this machine's real zero-substrate state (implicit-oracle floor exceeded: the check FIRED, re-observed by this verifier's own full doctor run, not the builder's probe record).

Comprehension-gate: not applicable (Verification: contract — Step-0 per-level early-return semantics per Decision 020, same routing as the Task 2 verdict above)
Operator invariants: none registered (exit 3) — `ask-registry.sh invariant-check --plan-slug gated-pipeline-master-2026-08`, re-run 2026-08-03T22:04Z

Checks run (all re-executed by this verifier on master @ 851adbbd, working tree clean for all cited paths):
1. Three manifest entries present: `grep -n` manifest.json → nl-maintenance-core (:3479), doctor-verdict-cache (:3503), maintenance-both-substrates-alive (:3524); each honest_status substantive — names the NOT-REGISTERED activation gap (DEC-4 pending), the single-writer provenance (d46beee5), and selftest:false honestly on the inverse branch. PASS
2. `.zero_substrate` data block in schedule-manifest.json (:166-170): legacy_disabled_since=2026-08-02, red_after_days=14, HR-F7 dates-in-data note. PASS
3. Doctor consumes the data (wired AND behaving): harness-doctor.sh:2642-2677 reads `.zero_substrate.legacy_disabled_since`/`.red_after_days` via jq and emits WARN before red_after, RED after. PASS
4. LIVE RE-OBSERVATION (this verifier's own full `--quick` run, 2026-08-03, exit captured, log in session scratchpad): `[doctor] WARN maintenance-zero-substrates: zero maintenance substrates alive (legacy Disabled since 2026-08-02, replacement unregistered; RED at 14d, now 1d) -- T10 registration pending` — the check fired on this machine's REAL state (run completed; not cache-served — per-check lines streamed live). PASS
5. `manifest-check.sh` re-run live: 164 entries, exactly 1 RED — session-heartbeat wired-template, pre-existing and T8-dispositioned (T8 open, PARTIAL); zero REDs introduced by T6's entries. PASS
6. Git: commit 422257c2 (feat gated-pipeline T6) touches manifest.json (+66), schedule-manifest.json (+15), harness-doctor.sh (+46), doctrine/INDEX.md (+3 — the --gen-index regen); `git merge-base --is-ancestor 422257c2 851adbbd` → yes. PASS

Runtime verification: command bash adapters/claude-code/hooks/harness-doctor.sh --quick 2>&1 | grep zero-substrate   # → the WARN line above (verifier's own run, ~9 min, exit 0 at run end)
Runtime verification: command bash adapters/claude-code/scripts/manifest-check.sh   # → 1 red (pre-existing session-heartbeat, T8-owned), 164 entries
Runtime verification: file adapters/claude-code/manifest.json::"maintenance-both-substrates-alive"
Runtime verification: file adapters/claude-code/config/schedule-manifest.json::"zero_substrate"

Verdict: PASS
Confidence: 9
Reason: PROVEN: all three contract shapes present at the cited lines on master @ 851adbbd, and the zero-substrate WARN re-observed FIRING on this machine's real state by this verifier's own doctor run (not the evidence file's probe record); manifest-check re-run shows T6 introduced zero REDs. The disclosed honest gap (no dedicated self-test scenario for the inverse branch; selftest:false stated in the entry) is honestly declared in the manifest itself and carried by the predecessor Known-gap follow-up — a disclosed residual, not a contract breach.

## Task 9 — Verifier verdict (task-verifier)

EVIDENCE BLOCK
==============
Task ID: 9
Task description: REQ-A6 predecessor closure (after Task 8): task-verifier on harness-execution-redesign-2026-08.md T1/T2/T3 evidence; flip checkboxes where PASS; flip plan → Status: SUPERSEDED with pointer to this plan; verify plan-lifecycle archives it — Verification: mechanical — Implements: REQ-A6
Verified at: 2026-08-03T22:38:00Z
Verifier: task-verifier agent (Verification: mechanical — deterministic on-disk/git facts re-observed directly)

Oracle: mechanical — the archived plan file, its evidence companion, docs/backlog.md, and git history on master @ 851adbbd; every claim re-read from disk, nothing taken from this evidence file's narrative.

Comprehension-gate: not applicable (Verification: mechanical — Step-0 per-level early-return semantics per Decision 020)
Operator invariants: none registered (exit 3) — `ask-registry.sh invariant-check --plan-slug gated-pipeline-master-2026-08`, re-run 2026-08-03T22:04Z

Checks run (all re-executed by this verifier):
1. `docs/plans/archive/harness-execution-redesign-2026-08.md` exists, `Status: SUPERSEDED` (:2) with a pointer comment (:3-8) naming this plan, the T1-PASS/T2-FAIL/T3-INCOMPLETE outcomes, the T4-T6 re-sequencing, and the carry-forwards backlog id. Committed 3bd5d6ea, ancestor of 851adbbd. PASS
2. Honest closure verdicts in the archived evidence file §"Closure verification under supersession (gated-pipeline T9 / REQ-A6)" (:242): T1 `Verdict: PASS` (:327), T2 `Verdict: FAIL — do not flip` (:387), T3 `Verdict: INCOMPLETE — do not flip` (:447), each with a task-verifier block. PASS
3. Checkbox states match the verdicts exactly: archived plan T1 `[x]`; T2/T3/T4/T5/T6 all `[ ]` — flip-where-PASS honored, no over-flipping. PASS
4. Plan-lifecycle archived: the plan + its evidence file both live under `docs/plans/archive/` (not `docs/plans/`). PASS
5. Carry-forwards registered: `docs/backlog.md:54` — PREDECESSOR-CLOSURE-CARRYFORWARDS-2026-08-03-01, five enumerated unowned items each with a candidate owner + re-derive pointer. PASS
6. Docs impact (SCRATCHPAD pointer line): SCRATCHPAD.md:18-19 carries "predecessor SUPERSEDED+archived". PASS

Runtime verification: file docs/plans/archive/harness-execution-redesign-2026-08.md::Status: SUPERSEDED
Runtime verification: file docs/plans/archive/harness-execution-redesign-2026-08-evidence.md::Closure verification under supersession
Runtime verification: file docs/backlog.md::PREDECESSOR-CLOSURE-CARRYFORWARDS-2026-08-03-01
Runtime verification: command git log --oneline -1 -- docs/plans/archive/harness-execution-redesign-2026-08.md   # → 3bd5d6ea close predecessor plan: SUPERSEDED... (ancestor of 851adbbd, verified)

Verdict: PASS
Confidence: 9
Reason: PROVEN: every deliverable of the closure re-observed on disk and in git — SUPERSEDED status with a complete pointer, per-task closure verdicts whose checkbox states match them exactly (the honest-closure property: FAIL/INCOMPLETE tasks NOT flipped), the archive move landed, the five carry-forwards registered so the archive loses nothing, and the SCRATCHPAD pointer present.

## Task 10 — Verifier verdict (task-verifier)

EVIDENCE BLOCK
==============
Task ID: 10
Task description: REQ-A7 registration prep: installer + -Rollback self-tested end-to-end on this machine (register→verify→rollback→verify-gone, under a test task name); DEC-4 ratification ask surfaced via needs-you.sh with the §3 compact block — PRECONDITION (fidelity F-3, hard-stop letter): the ask is surfaced only after the T3 and T4 review-record SHAs exist and are cited inside the ask block; registration itself executes ONLY on operator YES — Verification: contract — Implements: REQ-A7
Verified at: 2026-08-03T22:39:00Z
Verifier: task-verifier agent (Verification: contract)

Oracle: contract — the machine's real scheduled-task state (Get-ScheduledTask, re-queried by this verifier), the rendered NEEDS-YOU.md ask block, and the cited review record on disk; the installer register→rollback cycle itself is the one item accepted from the committed evidence record (re-executing it would re-mutate this machine's scheduled-task registry to prove an already-GONE state; the present state — zero NL-Maintenance* tasks — is exactly the cycle's documented end state and was re-observed).

Comprehension-gate: not applicable (Verification: contract — Step-0 per-level early-return semantics per Decision 020)
Operator invariants: none registered (exit 3) — `ask-registry.sh invariant-check --plan-slug gated-pipeline-master-2026-08`, re-run 2026-08-03T22:04Z

Checks run (re-executed by this verifier):
1. Registration NOT executed (the hard-stop letter): `Get-ScheduledTask -TaskName 'NL-Maintenance*'` → NOTHING registered — covers both the real name AND the NL-MaintenanceT10Test test name (rollback end-state consistent: test task GONE). PASS
2. DEC-4 ask exists and is rendered: NEEDS-YOU.md:101-110, id `NY-1785771976-caeb` — §3 compact block (decision sentence, background, PRECONDITIONS MET, three options ratify/pure-tick/hold each with plain outcomes, "My pick: ratify", links). PASS
3. F-3 precondition (fixed AND re-reviewed, cited INSIDE the ask): the block cites fix SHAs 6f5d1b22 (HR-F1) / d46beee5 (HR-F2) / 6c975cbb (T7 TTL race) AND the re-review record `docs/reviews/2026-08-03-gated-pipeline-t3-t4-implementation-review.md` — which exists on disk (7,137 bytes, verified). PASS
4. Installer surface: install-maintenance-task.ps1 carries the -Rollback path (5 references incl. the header's register/rollback contract and the Get-ScheduledTask verify line). PASS
5. Installer end-to-end proof record: this file's T10 entry (committed 1456cdd1, ancestor of 851adbbd) records register→State:Ready→-Rollback→GONE under TaskName NL-MaintenanceT10Test (name-patch the ONLY delta) + legacy-idempotence no-ops. Accepted as the contract's recorded execution; end-state independently re-observed in check 1. PASS
6. Consistency: the zero-substrate WARN re-observed live in the T6 verdict above says "replacement unregistered … T10 registration pending" — the doctor's independent sensor agrees registration has NOT happened. PASS

Runtime verification: command powershell -NoProfile -Command "Get-ScheduledTask -TaskName 'NL-Maintenance*' -ErrorAction SilentlyContinue"   # → empty; NO NL-Maintenance* task registered (verifier re-run)
Runtime verification: file NEEDS-YOU.md::NY-1785771976-caeb
Runtime verification: file docs/reviews/2026-08-03-gated-pipeline-t3-t4-implementation-review.md::implementation-review
Runtime verification: file adapters/claude-code/scripts/install-maintenance-task.ps1::Rollback

Verdict: PASS
Confidence: 8
Reason: PROVEN: the ask exists in §3 form with the F-3 precondition citations verified against on-disk artifacts, and the machine's real state re-observed on both sides of the contract — zero NL-Maintenance* tasks (registration correctly withheld pending operator DEC-4) with the doctor's independent zero-substrate WARN corroborating. HYPOTHESIZED (accepted, not re-run): the register→rollback cycle behaved exactly as the committed record describes (REFUTED if a future real registration attempt fails at register or rollback); not re-executed because re-proving a GONE end-state requires re-mutating the live scheduled-task registry — the recorded run + consistent end-state is the contract evidence.

## Task 12 — Verifier verdict (task-verifier)

EVIDENCE BLOCK
==============
Task ID: 12
Task description: [parallel] REQ-B2 design-author agent + templates/design-template.md (rationale-per-decision, non-goals, supersedes, machine-parsable REQ table, Directives-honored, Review Chain stub with authored-by; frontmatter model: fable) — Verification: contract — Implements: REQ-B2
Verified at: 2026-08-03T22:40:00Z
Verifier: task-verifier agent (Verification: contract)

Oracle: contract — the locked artifact shapes the task names (frontmatter fields, template sections, model-policy entry), re-read directly from master @ 851adbbd AND the live ~/.claude mirror.

Comprehension-gate: not applicable (Verification: contract — Step-0 per-level early-return semantics per Decision 020)
Operator invariants: none registered (exit 3) — `ask-registry.sh invariant-check --plan-slug gated-pipeline-master-2026-08`, re-run 2026-08-03T22:04Z

Checks run (re-executed by this verifier):
1. `adapters/claude-code/agents/design-author.md` exists on master (commit b65bef7a, ancestor of 851adbbd; 20,025 bytes) AND live at ~/.claude/agents/design-author.md — `diff` → byte-identical. PASS
2. Frontmatter: `model: fable` SINGLE value (fallback chain correctly NOT in the file); tools declared; description names the P-31/P-32 defect classes and the six-phase protocol. PASS
3. `adapters/claude-code/templates/design-template.md` (12,900 bytes, same commit) carries every required section: **Supersedes** (:48), `## 3. Decisions (each with rationale + reversal cost)` (:91, table :102), machine-parsable `## Requirements` REQ table with the literal-heading parse contract for plan-reviewer Check 21 (:121-132), `## Non-goals` (:140), `## Directives honored` (:196, exact-heading convention), `## Review Chain` stub with `authored-by:` incl. the honest-fallback wording (:211, :221-224). PASS
4. model-policy.json agents block: `"design-author": {category: "design", chain: ["fable","opus"]}` (:203-207) — category design per the task's Docs-impact line. PASS
5. Docs-impact claim ("model-policy.json agents block gains the entry") — delta confirmed present at :203; landed with the T12/T13 train. PASS

Runtime verification: file adapters/claude-code/agents/design-author.md::model: fable
Runtime verification: file adapters/claude-code/templates/design-template.md::## Directives honored
Runtime verification: file adapters/claude-code/config/model-policy.json::"design-author"
Runtime verification: command diff adapters/claude-code/agents/design-author.md ~/.claude/agents/design-author.md   # → no output, byte-identical (verifier re-run)

Verdict: PASS
Confidence: 8
Reason: PROVEN: every contract shape re-observed at the cited line on master and confirmed byte-identical live; the template's parse-contract headings match what plan-reviewer Check 21 and the plan-template's Review Chain conventions consume (the cross-artifact contract the template exists to serve). The agent's authoring protocol has not yet originated a real design doc this session (design-author's first live exercise is a future design cycle) — for a contract-level agent+template task the locked shapes ARE the bar; the sibling protocol (T13's reviewer) was proven executable live in the T16 record, and design-author's own self-audit phase is structurally the same host-executable protocol form.

## Task 13 — Verifier verdict (task-verifier)

EVIDENCE BLOCK
==============
Task ID: 13
Task description: [parallel] REQ-B3 plan-fidelity-reviewer agent (frontmatter model: fable, category review; protocol per design §5; anti-rubber-stamp step; GOLDEN CASE fixture = the P-32 push-directive drop replayed as a design+plan pair in the agent's eval block) — Verification: contract — Implements: REQ-B3
Verified at: 2026-08-03T22:41:00Z
Verifier: task-verifier agent (Verification: contract)

Oracle: contract + derived (golden case) — the locked artifact shapes re-read from master @ 851adbbd and the live mirror, PLUS the strongest available functional oracle for an agent definition: the protocol was EXECUTED live twice this session (the T16 record's full round → REFORMULATE with 8 class-tagged findings, then the delta round → PASS), and the record's own header shows the GOLDEN-CASE admission test reproduced (fixture pair → CONTRADICTORY, Critical, REFORMULATE) before the real verdict was trusted.

Comprehension-gate: not applicable (Verification: contract — Step-0 per-level early-return semantics per Decision 020)
Operator invariants: none registered (exit 3) — `ask-registry.sh invariant-check --plan-slug gated-pipeline-master-2026-08`, re-run 2026-08-03T22:04Z

Checks run (re-executed by this verifier):
1. `adapters/claude-code/agents/plan-fidelity-reviewer.md` on master (commit 88a6a1d5, ancestor of 851adbbd; 29,792 bytes) AND live — `diff` → byte-identical. Frontmatter `model: fable` single value, tools read-only (Read/Grep/Glob/Bash). PASS
2. model-policy.json: `"plan-fidelity-reviewer": {category: "review", chain: ["fable","opus"]}` (:210-214). PASS
3. GOLDEN CASE fixture pair exists at `adapters/claude-code/tests/fixtures/plan-fidelity/` — mini-design.md (3,107 B) + mini-plan.md (2,925 B), same commit; substantive P-32 replay (push-materialize MUST + hard-stop vs the plan's TTL-poll contradiction), not stubs; agent's GOLDEN CASE section (:327-358) names the pair, the required REFORMULATE output, and the "no PASS on a real plan until the fixture reproduces REFORMULATE" eval note. PASS
4. Anti-rubber-stamp step present: the "Weakest mapping" requirement (agent :220 region; exercised for real in the T16 record's §"Weakest mapping" naming REQ-C6→T24). PASS
5. FUNCTIONAL PROOF (protocol executed live, twice): docs/reviews/2026-08-03-gated-pipeline-t16-plan-fidelity-review.md — (a) header line 7: admission test executed THIS RUN against the fixture pair, REQ-D1 → CONTRADICTORY, Critical, REFORMULATE reproduced exactly as the eval note demands; (b) full round Verdict: REFORMULATE with findings F-1..F-8 incl. the F-1 P-32-shape catch (stale "no OD- id exists" backfills vs the landed register) — the agent catching in production the precise defect class its golden case encodes; (c) delta round → Delta Verdict: PASS with fresh attestation. Protocol-host execution (general-purpose host running the agent file's protocol on model fable, registry hot-reload limitation) disclosed honestly in the record AND the plan's chain entry, nl-issue filed. PASS
6. Docs-impact claim (model-policy entry) — confirmed at :210. PASS

Runtime verification: file adapters/claude-code/agents/plan-fidelity-reviewer.md::model: fable
Runtime verification: file adapters/claude-code/tests/fixtures/plan-fidelity/mini-design.md::FIXTURE
Runtime verification: file adapters/claude-code/config/model-policy.json::"plan-fidelity-reviewer"
Runtime verification: file docs/reviews/2026-08-03-gated-pipeline-t16-plan-fidelity-review.md::Admission test
Runtime verification: command diff adapters/claude-code/agents/plan-fidelity-reviewer.md ~/.claude/agents/plan-fidelity-reviewer.md   # → no output, byte-identical (verifier re-run)

Verdict: PASS
Confidence: 9
Reason: PROVEN: all contract shapes re-observed at cited lines on master + live, AND — beyond the contract bar — the agent's protocol demonstrably WORKS: the T16 record shows the golden-case admission test reproducing REFORMULATE on the fixture pair and the full protocol catching a live P-32-shape defect (F-1) on the real plan, then passing the delta honestly. That is the functionality-over-components axis satisfied for an agent artifact: not "the file exists" but "the protocol, executed, produced the discriminating verdicts."

## Task 16 — Verifier verdict (task-verifier)

EVIDENCE BLOCK
==============
Task ID: 16
Task description: REQ-B13 bootstrap self-review (after Tasks 13,14,15): dispatch plan-fidelity-reviewer on THIS plan against design r3; commit its record; append the plan-reviews chain entry with CANONICALIZED plan-blob anchor (re-anchoring the bootstrap record); only then is Task 17 dispatchable — Verification: mechanical — Implements: REQ-B13
Verified at: 2026-08-03T22:43:00Z
Verifier: task-verifier agent (Verification: mechanical)

Oracle: mechanical + derived (the lib itself) — the committed record, the plan's chain entry, and the canonicalized blob INDEPENDENTLY RECOMPUTED by this verifier via the production parser (`source review-chain-lib.sh; rc_blob_of <plan> plan`), not read from any record.

Comprehension-gate: not applicable (Verification: mechanical — Step-0 per-level early-return semantics per Decision 020)
Operator invariants: none registered (exit 3) — `ask-registry.sh invariant-check --plan-slug gated-pipeline-master-2026-08`, re-run 2026-08-03T22:04Z

Checks run (re-executed by this verifier on master @ 851adbbd, BEFORE this session's checkbox flips):
1. Record exists and is substantive: docs/reviews/2026-08-03-gated-pipeline-t16-plan-fidelity-review.md — `## Verdict: REFORMULATE` (:9) with 8 findings + 2 adjudications + weakest-mapping + directive-carriage enumeration + anchor check; `# Delta re-review (post-fixes @ 7eaaa9f6)` → `## Delta Verdict: PASS` (:84) with F-1/F-6/F-7/F-8 RESOLVED and F-2..F-5 explicitly scoped to the T18 merge (subsequently discharged — see the T18 entry above: remediation ab2caf9e, fidelity re-check CLEAR TO MERGE appended to this record's trail). Committed dbd6647f; fixes 7eaaa9f6; both ancestors of 851adbbd. PASS
2. Fresh attestation in the record: `**Reviewed:** docs/plans/gated-pipeline-master-2026-08.md @ 0771581b2222e0198443bf425283bc7cf8cda400` (:82). PASS
3. Chain entry appended: the plan's `## Review Chain` plan-reviews carries `reviewer: plan-fidelity-reviewer  verdict: PASS  record: docs/reviews/2026-08-03-gated-pipeline-t16-plan-fidelity-review.md  plan-blob: 0771581b2222e0198443bf425283bc7cf8cda400` (plan :36), superseding the bootstrap harness-reviewer entry (:35) exactly as the bootstrap design intended. PASS
4. THREE-WAY ANCHOR INDEPENDENTLY VERIFIED: `source adapters/claude-code/hooks/lib/review-chain-lib.sh && rc_blob_of docs/plans/gated-pipeline-master-2026-08.md plan` → `0771581b2222e0198443bf425283bc7cf8cda400` — EXACT match: chain-entry blob == record-attested blob == HEAD canonicalized blob, computed by this verifier with the production lib (verified pre-flip; this session's sanctioned checkbox flips move the canonical blob afterward — inherent to the post-review lifecycle, chain/In-flight sections excluded but task lines included per the lib's canonicalization). PASS
5. Sequencing honored ("only then is Task 17 dispatchable"): T17 remains unbuilt/unflipped; the T16 chain entry landed before any T17 dispatch. PASS
6. Admission test + protocol-host disclosure verified in the record header (:3, :7) — same facts underwriting the T13 verdict above. PASS

Runtime verification: command bash -c 'source adapters/claude-code/hooks/lib/review-chain-lib.sh && rc_blob_of docs/plans/gated-pipeline-master-2026-08.md plan'   # → 0771581b2222e0198443bf425283bc7cf8cda400 (verifier re-run, exact match, pre-flip)
Runtime verification: file docs/reviews/2026-08-03-gated-pipeline-t16-plan-fidelity-review.md::Delta Verdict: PASS
Runtime verification: file docs/plans/gated-pipeline-master-2026-08.md::plan-blob: 0771581b2222e0198443bf425283bc7cf8cda400
Runtime verification: command git merge-base --is-ancestor dbd6647f 851adbbd   # → exit 0 (and 7eaaa9f6 likewise)

Verdict: PASS
Confidence: 9

## Task 20 — Carriage channels 2+3 + generated NL-ATTRIBUTION header (REQ-B11/REQ-B12) — Verification: full

- Builder: plan-phase-builder (sonnet), SERIAL dispatch on the shared checkout (no worktree isolation
  for this build — session `4a470c8c`).
- Files: `adapters/claude-code/scripts/dispatch-directives.sh` (new) · `adapters/claude-code/hooks/lib/directives-register-lib.sh`
  (extended: `dr_entries_for_files_bash`, `dr_register_walk_bash`, `_dr__parse_all_bash`,
  `_dr__decode_escapes` — the pure-bash fast path) · `adapters/claude-code/hooks/doctrine-jit.sh`
  (`_compute_doctrine_body`/`_compute_register_body`/`_compute_injection` split, the C-1 merge) ·
  `adapters/claude-code/doctrine/orchestrator-pattern.md` + `-full.md` (dispatch-directives.sh step
  + generated-header rule).
- What ran, in order: (1) hand-validated the pure-bash line-scan parser against the REAL register
  and the T11 shared fixture before wiring anything (caught and fixed a real self-test-fixture bug —
  a single-line `"surfaces": ["x"],` array silently failed to parse, since the reader targets the
  register's own MULTI-line pretty-print convention only — documented as a stated limitation, not
  fixed generically); (2) wired the merged single-emission walk into doctrine-jit.sh; (3) built
  `dispatch-directives.sh` (channel 2 + the carriage WARN); (4) mid-build, the orchestrator sent a
  scope addition (operator directive 2026-08-03: generated, never hand-typed, dispatch identifiers)
  to also generate the `NL-ATTRIBUTION` header from `dispatch-directives.sh` — implemented, self-tested,
  doctrine updated in the same commit; (5) iteratively benchmarked and fixed THREE distinct fork-cost
  sources in the register-walk hot path (below).
- Self-tests, all re-run on the committed state: `directives-register-lib.sh --self-test` → **29
  passed, 0 failed** (includes the pure-bash-vs-node/jq round-trip parity checks and a live check
  against the REAL committed register for this task's own three wire-checked files). `doctrine-jit.sh
  --self-test` → **17 passed, 0 failed** (T1-T10 pre-existing, unchanged; T11-T16 new — both-match,
  register-only, dedup, fresh-session re-fire, empty/missing register degrade). `dispatch-directives.sh
  --self-test` → **10 passed, 0 failed** (attribution header + role default/override, invalid-task-id
  hard error naming every valid id, invalid-role hard error, Directives computation against the T11
  shared fixture, carriage WARN fires/doesn't-fire). `dispatch-chain-gate.sh --self-test` (unaffected
  file, sanity re-run) → 6 passed, 0 failed.

### Prove it works — the four required scenarios

**1. `dispatch-directives.sh <this-plan> 20`:**
```
$ bash adapters/claude-code/scripts/dispatch-directives.sh docs/plans/gated-pipeline-master-2026-08.md 20
NL-ATTRIBUTION: plan=gated-pipeline-master-2026-08 task=20 role=builder

Directives: OD-002,OD-007,OD-008,OD-013,OD-018,OD-021
### OD-002 ... ### OD-007 ... ### OD-008 ... ### OD-013 ... ### OD-018 ... ### OD-021 ...
[dispatch-directives] CARRIAGE WARN (REQ-B12): task 20's plan-declared Directives: field is missing
OD-021 — the register has changed since the field was last computed (or it was never set); paste
the block(s) above into the dispatch prompt and consider updating the plan's Directives: line.
```
This is a REAL, live finding, not a synthetic fixture: OD-021 (`ci-is-read-mandatory`) was added to
the register AFTER the T16 fidelity review computed this task's own `Directives:` line
(`OD-002, OD-007, OD-008, OD-013, OD-018`) — its surface `adapters/claude-code/doctrine/orchestrator-pattern*`
matches this task's own `orchestrator-pattern.md` edit. The carriage-WARN mechanism (REQ-B12) caught
its OWN plan's citation going stale, live, on the first real invocation. The plan is frozen and this
task's own line is not edited here; the finding is recorded as evidence of the mechanism working, per
the plan's own convention that built tasks keep their historically-true `Directives:` lines.

**2. Both-match-same-event, ONE valid JSON object (doctrine-jit.sh self-test T11):** a fixture edit
path (`docs/plans/both-match.md`) matches BOTH the fixture manifest's `plan-edit-validator` trigger
AND the fixture register's `OD-901` surface. Asserted: `jq -e .` parses; `jq -s 'length'` on the raw
stdout → `1` (ONE JSON object, not two concatenated); `additionalContext` contains BOTH the doctrine
compact text (`FUNCTIONALITY OVER COMPONENTS`) AND the register block (`OD-901`, `FIXTURE DIRECTIVE
for doctrine-jit self-test`); both markers written independently
(`sess-11--plan-edit-validator` and `sess-11--od--OD-901`).

**3. Dedup on a second identical edit (T13):** the same session (`sess-11`) repeats a `docs/plans/`
edit that would re-match both walks → empty output (both markers already present from T11).

**4. TIMING — the register walk's added latency, 10-run average, MUST be < 50ms.**

Methodology: `$EPOCHREALTIME` (bash 5.0+ builtin, no fork — `date +%s%N` was tried FIRST and rejected:
`date` is an external binary, so timing WITH it contaminates every measurement with `date`'s own
~100-300ms fork cost on this platform, the exact effect being measured). Measured
`_compute_register_body` directly (the function `_compute_injection` calls — the register walk plus
marker-check/dedup/body-assembly, i.e. everything Task 20 ADDS to the hook), sourcing the real
`directives-register-lib.sh` + `doctrine-jit.sh`, against the REAL committed register and
`adapters/claude-code/hooks/doctrine-jit.sh` as the trigger file (3 real matches: OD-002/007/018).

Official 10-run reading (exact reproduction below):
```
run,ms
1,47
2,51
3,46
4,44
5,55
6,43
7,53
8,49
9,43
10,46
average,47
```
**47ms average — under the 50ms budget.**

Reproduction (the exact logic run):
```bash
cd <repo-root>
source adapters/claude-code/hooks/lib/nl-paths.sh
source adapters/claude-code/hooks/lib/directives-register-lib.sh
exit() { return "${1:-0}"; }; set -- --unused; source adapters/claude-code/hooks/doctrine-jit.sh; unset -f exit
REG="$(dr_default_register_path)"; SD="$(mktemp -d)"; F="adapters/claude-code/hooks/doctrine-jit.sh"
for i in $(seq 1 10); do
  rm -f "$SD"/*; _DJ_REGISTER_BODY=""
  t0=$EPOCHREALTIME; _compute_register_body "$REG" "$F" "sess-$i" "$SD"; t1=$EPOCHREALTIME
  # ms = (t1-t0) computed via integer arithmetic on EPOCHREALTIME's sec.micro parts
done
```
(The `exit()`-shadow + `--unused` dance exists only because `doctrine-jit.sh`'s own bottom-of-file
CLI dispatch has no direct-execution guard, unlike the lib files — sourcing it for its functions,
which this reproduction needs, would otherwise call a real `exit` mid-source.)

**Environment disclosure (honesty, not an excuse):** this machine was under UNUSUALLY heavy
concurrent load throughout this build — `Get-Process | Where-Object {ProcessName -match
"bash|node|claude"} | Measure-Object` read **107 processes** mid-build and **208 processes** at the
time of the official reading above (verified, not estimated). For comparison, a single `jq -e .
<register>` spawn — what the OLD, REJECTED, jq-based approach would have cost per event — measured
**219ms average** (10 runs, SAME load conditions, SAME session) — 4.7x this implementation's 47ms.
Earlier in this build, under lighter load, the identical code measured 11-15ms for the bare
parse-only pass and 26-49ms for the full walk-with-decode — comfortably under budget with more
margin. The 47ms official reading is the worst-case-load number this session could produce, not a
best-case cherry-pick; individual runs within a 10-run batch ranged from 41ms to 139ms across
several batches taken during the optimization work (before the fixes below), settling to the 43-55ms
band reported above after all three fork-cost fixes landed.

**Fork-cost sources found and fixed (the actual F-5 engineering, in the order discovered):**
1. **jq/node in the parse itself** — the reason this second code path exists at all. `dr__stream`
   (the pre-existing node/jq-backed reader `dr_entries_for_files` uses) costs ~174-364ms per
   invocation on this platform; forbidden for the per-event hot path per the design's own F-5
   finding. Fixed by `_dr__parse_all_bash`/`dr_register_walk_bash`: `$(< file)` fast-slurp (a bash
   builtin special-case, NOT `cat`) + an IFS-based unquoted-array line split (also a builtin, not a
   `read` loop) + `case "$line" in *glob*)` classification (measured faster than `[[ =~ regex ]]` on
   this platform — a `while read` + regex version of the SAME logic measured ~270-320ms, i.e. WORSE
   than the jq baseline it was meant to replace, discovered and rejected during this build) +
   `${var#prefix}`/`${var%suffix}` value extraction.
2. **A per-matched-entry `mkdir -p` fork** — `mkdir` is an external binary, not a bash builtin. The
   first working version of `_compute_register_body`'s marker-writer called it once PER matched OD-
   entry (3 times for this task's own trigger file), costing ~150ms extra by itself. Fixed: hoisted
   to at most once per invocation, memoized, AND skipped entirely via a `[ -d "$state_dir" ]` builtin
   test in the overwhelmingly common case (the directory already exists after session start).
3. **Double-layered `$( )` capture** — the first working version had `_compute_injection` call
   `_compute_doctrine_body`/`_compute_register_body` via `$( )`, and `_compute_register_body`
   separately call `dr_register_walk_bash` via `$( )` — TWO nested forks on the hot path. `$( )` is
   always a fork in bash regardless of what's inside it (even a bash builtin or a plain variable
   read). Fixed by having every layer set a global (`_DJ_DOCTRINE_BODY`, `_DJ_REGISTER_BODY`,
   `DR_REGISTER_WALK_OUT`) instead of echoing, called DIRECTLY (no `$( )`) at every layer except the
   one place a real text capture is unavoidable — none remain in the hot path; `dr_register_walk_bash`
   itself was the last echo-based function and now sets `DR_REGISTER_WALK_OUT` instead (a small
   `~5`-line duplication of `_dr__decode_escapes`'s body was accepted, inlined, specifically to avoid
   a `$( )` around that call too — documented in the code as a deliberate fork-avoidance trade, not a
   second decode implementation with different semantics).

### Task 20 — Comprehension Articulation (builder-authored, per Decision 020d)

#### Spec meaning

Task 20 builds carriage channels 2 and 3 of the operator-directives register (REQ-B1/Task 11 built
the register itself + channel 1, the plan's per-task `Directives:` field). Channel 2
(`scripts/dispatch-directives.sh`) is an orchestrator-run CLI tool: given a plan and a task number,
it computes which register entries' `surfaces` globs match the task's `## Files to Modify/Create`
entries (via `directives-register-lib.sh`'s `dr_entries_for_files` — the ONE parser, M-3), printing
the matched ids' instruction blocks ready to paste into a dispatch prompt. Channel 3
(`doctrine-jit.sh`'s register walk) is the SAME matching computation, but run automatically on every
PostToolUse Edit/Write/MultiEdit event, merged into the SAME `hookSpecificOutput` JSON emission the
pre-existing doctrine-compact walk already produces — the C-1 form: both walks compute independently,
one JSON object, both bodies when both fire, per-walk markers, always-exit-0. REQ-B11's fidelity
review (F-5) additionally bound channel 3 to a <50ms added-latency budget and explicitly forbade any
per-event jq/node subprocess, which is why this task's SECOND code path (`dr_register_walk_bash`,
pure-bash) exists alongside channel 2's node/jq-backed `dr_entries_for_files` — two readers of the
SAME file for two genuinely different cost budgets, not a redundant duplication (documented at length
in the lib's own module header). REQ-B12's "G1/G2 carriage WARN" is interpreted here as: WARN when a
task's ALREADY-DECLARED `Directives:` field (channel 1's snapshot) has drifted from what the register
NOW computes — implemented inside `dispatch-directives.sh` itself (run at the moment the orchestrator
actually pastes citations into a dispatch, which IS G2's real moment), not by editing `plan-reviewer.sh`
(G1, Task 14's file, unflipped and possibly concurrently in flight) or `dispatch-chain-gate.sh` (G2's
live PreToolUse form, Task 17's explicit unbuilt remit — that file's own header warns against
premature extension). Mid-build, the orchestrator added: generate the `NL-ATTRIBUTION` dispatch
header from this SAME script rather than hand-typing it, validated against the plan's real task list —
folded in as the same file's natural extension point.

#### Edge cases covered

- Both-match-same-event (the C-1 load-bearing scenario, T11): one JSON object, both bodies, both
  markers written independently — the design's exact acceptance bar.
- Register-only match with zero doctrine match (T12) and the reverse (T1-T10, unchanged, still pass
  with register_path omitted — proves the register walk is purely additive).
- Dedup: repeated identical edits in the same session re-inject nothing for either walk (T13); a
  FRESH session re-fires independently (T14) — markers are per-session, matching the pre-existing
  doctrine-walk convention.
- Missing/empty register path (explicit `""`, T15) and a non-existent register FILE path (T16) both
  degrade to doctrine-only / fully silent, never a crash — the lib's documented fail-open contract
  extended through the hook layer.
- Real register drift surfacing through the carriage WARN: OD-021 (added to the register after this
  plan's own `Directives:` lines were computed) matches this task's own files and the WARN fires on
  the very first live invocation against the real plan — not a contrived fixture.
- Escaped-backslash instruction text (OD-020's `HKLM\\SOFTWARE\\Policies\\Claude`) decodes correctly
  via the placeholder-indirection substitution order (`\\` → placeholder → `\n`/`\"`/`\t` decoded →
  placeholder → `\`) — verified directly against the one real register entry that exercises it.
- `dispatch-directives.sh` task-id validation: numeric-only enforced (the operator-directive scope
  addition's root cause — a hand-typed `T7`-shaped id), unknown task id hard-errors naming every
  valid id from the plan's own `## Tasks` list (never a best-effort guess); invalid role hard-errors
  against the doctrine's closed set.
- A task with no Files-to-Modify entries tagged for it → `Directives: none`, rc 0, not an error.
- Three independently discovered and fixed fork-cost sources in the timing-critical path, each
  verified via before/after EPOCHREALTIME measurement rather than assumed fixed.

#### Edge cases NOT covered

- `dr_register_walk_bash`/`_dr__parse_all_bash` are NOT general JSON parsers — they target the
  register's own generated multi-line pretty-print convention specifically (non-empty `"surfaces"`
  arrays opened on their own line, one glob per subsequent line). A single-line
  `"surfaces": ["x"],` entry would silently fail to parse. This is disclosed in the lib's own module
  header as a stated limitation (not a general-purpose reader), and was caught once already during
  this build (my own self-test fixture used the wrong shape; fixed to match the real convention) —
  but nothing GATES a future hand-edit of the real register into the unsupported shape; `dr_validate`
  (the JSON-correctness checker) would still pass such a file since it is valid JSON, just not in the
  shape this second reader expects.
- G1 (`plan-reviewer.sh` Check 21) and G2's live PreToolUse form (`dispatch-chain-gate.sh`, Task 17)
  do not themselves call any carriage-WARN logic — this task's wire-checks block names only
  `dispatch-directives.sh` and `doctrine-jit.sh`, and I deliberately did not extend either of those
  two other files (risk of conflicting with Task 14's unflipped-but-landed work, and
  `dispatch-chain-gate.sh`'s own header explicitly warns against building live enforcement before
  Task 17). REQ-B12's WARN posture is therefore satisfied at the dispatch-tool layer only, not
  live-wired into either named gate.
- The 47ms official timing reading was taken on a machine carrying unusually heavy concurrent load
  (208 bash/node/claude processes, verified). No fully-idle-machine number was independently
  reproduced at the very end of the build; the lighter-load numbers earlier in the session (11-49ms)
  and the heavy-load numbers at the end (43-55ms) bracket the real range but a clean-room number
  was not captured.
- `extract_tagged_files` (dispatch-directives.sh) takes the LAST parenthetical group on a Files-to-
  Modify line as the task-tag group; every real line in this plan follows that convention, but a line
  with the tag as a non-last parenthetical is unhandled (would silently miss the file).
- No self-test exercises `dispatch-directives.sh` against a plan with no `## Tasks` section at all, or
  a register that fails `dr_validate` — both degrade via the lib's documented fail-open contract but
  are not independently asserted for THIS script.

#### Assumptions

- The register's committed pretty-print convention (2-space indent, one JSON field per line,
  non-empty `surfaces` arrays multi-line) remains stable; the `real-register-t20-files-match-set`
  self-test scenario (comparing this task's pure-bash reader against the pre-existing node/jq reader
  on the REAL committed file) would catch a future format drift immediately if either reader started
  disagreeing.
- `$EPOCHREALTIME` (bash 5.0+ builtin) is available wherever this hot path's cost might need
  re-auditing in the future — confirmed on this machine (bash 5.2.37) but not independently verified
  on the harness's other supported platforms (Mac, other Windows machines) during this build.
- Task 17 (G2's live PreToolUse wiring) will eventually consume register-lib functions for its own
  carriage-WARN behavior in a form compatible with what this task built — assumed, not verified,
  since Task 17 does not exist in this worktree.
- The mid-build NL-ATTRIBUTION scope addition assumed plan task ids are numeric for plans using THIS
  plan's numbering convention specifically; the doctrine's pre-existing note that OTHER plan families
  (accountable-estate-style) validly use `T`-prefixed ids was left untouched — `dispatch-directives.sh`'s
  numeric-only validation is scoped to its own generation path, not asserted as a universal constraint
  on every plan format in the harness.
- `jq` and `node` remain available in the execution environment for channel 2
  (`dr_entries_for_files`, dispatch-directives.sh's own backend) — that path is NOT subject to the
  <50ms budget (it runs once per orchestrator dispatch decision, not once per Edit) and was not
  re-engineered to avoid them.
Reason: PROVEN: the bootstrap self-review's full mechanical contract re-observed — committed substantive record (REFORMULATE → fixes → delta PASS with fresh attestation), chain entry appended with the canonicalized anchor, and the three-way blob equality recomputed independently by this verifier through the production lib rather than trusted from any artifact. The one deviation (protocol-host execution instead of registry dispatch) is disclosed in the record, the chain entry, and an nl-issue — honest, not silent.

## Forensic recovery — Tasks 7, 11, 14, 15 Comprehension Articulations (2026-08-03)

Four builder agents' task output-files (`...\tasks\<agent-id>.output`) were found truncated to
0 bytes, losing their Comprehension Articulation blocks before they were transcribed into this
file. This section (plus the Task 7 subsection inserted above, in its natural position after the
existing Task 7 evidence entry) recovers all four VERBATIM from a surviving source and records
provenance honestly per constitution §1.

Two candidate sources were checked for each of the four builders:
1. The main session's top-level transcript, `4a470c8c-e5e4-49bb-a8f8-131206e35b58.jsonl` — for
   all four agents this file's `<task-notification>` result block contains only a closing summary
   line ("Comprehension Articulation: included above, four sub-sections...") and does NOT contain
   the actual sub-section text. Confirmed by direct extraction (`jq -r '.message.content'` on the
   matched line) for the Task 7 notification (line 1568) — the full unescaped result was read and
   the articulation text is genuinely absent from it, not just hard to find.
2. Each builder's own worktree (`.claude\worktrees\agent-<id>`) — checked via read-only grep for
   "Spec meaning" / "Comprehension Articulation" across the whole tree. Every match in all four
   worktrees resolves to pre-existing, unrelated repository files (other plans' historical
   evidence files, `templates/comprehension-template.md`, `doctrine/comprehension-gate*.md`,
   agent definitions) — none is the builder's own Task 7/11/14/15 articulation. Grepping each
   worktree's own copy of `docs/plans/gated-pipeline-master-2026-08-evidence.md` for
   `^## Task 11 —` / `^## Task 14 —` / `^## Task 15 —` / `^## Task 7 —` (Comprehension subsection
   form) returned **no matches** in any of the four worktrees — the articulations were never
   written to disk there.
3. A third source, not named in the original two-source hypothesis, was discovered and used: each
   background builder's OWN per-agent session transcript, stored by the harness at
   `~/.claude/projects/<this-project>/4a470c8c-e5e4-49bb-a8f8-131206e35b58/subagents/agent-<id>.jsonl`
   (part of the main session's own storage tree, distinct from the top-level session JSONL).
   These files contain the builder's full assistant-turn text, including the `## Comprehension
   Articulation` heading and all four sub-sections in the builder's own words, extracted via
   `jq -r '.message.content[]? | select(.type=="text") | .text'` and located by grepping the
   extracted text for `Comprehension Articulation`/`Spec meaning`. This is the source used below
   for all four recoveries — genuinely verbatim, not reconstructed.

Task 7's recovery is inserted in its natural position above (after the existing "Task 7 —
Mechanized flips + targeted fixes" evidence block, before "## Task 10"). Tasks 11, 14, and 15 have
no existing parent evidence sections in this file (no builder evidence narrative or verifier
verdict for these three tasks has landed yet) — the blocks below are ONLY the recovered
Comprehension Articulations, not full task evidence entries; a complete evidence write-up for
Tasks 11/14/15 (builder narrative, self-test totals, verifier verdict) remains outstanding and is
NOT fabricated here.

### Task 11 — Comprehension Articulation (recovered verbatim from the builder's own subagent session transcript after builder output-file loss; builder a9710b88fde9bab38; diff: bca1c3adfe2c942898842b6f502338d76c229dfd; worktree `agent-a9710b88fde9bab38`)

Recovered from `...\subagents\agent-a9710b88fde9bab38.jsonl`. Task 11 = "REQ-B1+B4 register:
`config/operator-directives.json` (canonical) + generator for `docs/operator-directives.md` view +
`hooks/lib/directives-register-lib.sh`..." per the plan (`docs/plans/gated-pipeline-master-2026-08.md:248-254`).
The builder's own report gave this section as "Spec meaning:" (not "Spec meaning (own words):")
and included two extra trailing subsections ("Honest gaps" and "Blockers") beyond the four
required ones — reproduced here as the builder wrote them, verbatim, in full:

**Spec meaning:** Build the canonical operator-directives JSON register, a generator for its markdown view, ONE parser lib for three future carriage consumers, seeded from the three named nl-issues plus curated/deduped D-01..D-23 (skip plan-machinery items), two operator-only entries, an ADR forward-guard WARN lint on decisions-index-gate.sh, and a same-commit `derive-cache.js` supersession annotation — under a <30-entry rot bar, with manifest/INDEX/model-policy edits forbidden (report deltas) and nl-issues.jsonl edits reported not applied.

**Edge cases covered:** SUPERSEDED entries never surface via `dr_entries_for_files` (fixture-tested); `operator_only` entries with empty `surfaces` never surface for any input; malformed JSON, duplicate ids, bad id format, bad status, and >5-line instructions all fail `dr_validate` with named errors; the generator is idempotent and drift-detecting; the ADR WARN never flips the gate's existing BLOCK/ALLOW exit code across 4 scenarios; glob semantics (`*` crosses `/`) documented and unit-tested both directions.

**Edge cases NOT covered:** no retroactive `register_ref` sweep of existing `docs/decisions/` files (lint is prospective/staged-only, by design); surfaces globs are hand-authored heuristics spot-checked against one real file (`dispatch-chain-gate.sh` → 5 correct matches), not exhaustively validated; Task 20's <50ms per-event latency budget (fidelity F-5) is NOT validated here — `dr__stream`'s node/jq backend is almost certainly too slow for that walk (jq alone ~174ms per the design's own measurement); flagged in the lib header as Task 20's problem to solve (pure-bash parse or a pre-parsed cache), not solved by this task.

**Assumptions:** node/jq both available (verified: node v24.13.1, jq 1.8.1); both lib and generator fail-open to empty/ERROR if neither present, never crash. `register_ref` detection is a bare case-insensitive substring match, not a strict grammar — acceptable because the lint is WARN-only advisory. The two additive JSON fields beyond the design's exact 5-field entry contract (`title`, `source`/`absorbs` for traceability; `operator_only` bool) are non-breaking, explicitly documented as additive-and-unvalidated in both the register's own `note` and the lib header, and `dr_validate` deliberately never checks them.

*(Builder's own trailing subsections, reproduced verbatim for completeness though not part of the required four:)*

**Honest gaps** (builder's heading): Carriage channels 2+3 (`dispatch-directives.sh`, doctrine-jit walk) and plan-reviewer Check 21 are Task 14/20 scope — the lib is built to their agreed shared-fixture contract but nothing consumes it yet. ADR lint is prospective only; docs/decisions/064 and similar pre-existing binding ADRs still lack `register_ref` (out of this task's scope, not silently swept). manifest.json / INDEX.md / model-policy.json untouched per builder constraint — delta above is ready but not applied.

**Blockers** (builder's heading): none.

Builder-reported commit: `bca1c3adfe2c942898842b6f502338d76c229dfd` (worktree `agent-a9710b88fde9bab38`, not yet merged to master at time of report). Builder-reported verdict: DONE (proven at runtime) — all four self-tests re-run clean against the committed state (22/22, 6/6, 9/9, `node --check` OK).

### Task 14 — Comprehension Articulation (recovered verbatim from the builder's own subagent session transcript after builder output-file loss; builder af614aa5e90013731; diff: e58e480e; worktree `agent-af614aa5e90013731`)

Recovered from `...\subagents\agent-af614aa5e90013731.jsonl`. Task 14 = "REQ-B5+B7 template +
checks: plan-template gains `design-ref:` header + per-task `Implements:`/`Directives:` + Review
Chain section; plan-reviewer Checks 20-22..." per the plan
(`docs/plans/gated-pipeline-master-2026-08.md:275-292`).

**Spec meaning:** Task 14 (REQ-B5+B7) asks me to extend `plan-template.md` with a `design-ref:` header, per-task `Implements:`/`Directives:` fields, and a `## Review Chain` section stub; add `plan-reviewer.sh` Checks 20-22 implementing REQ-B7's three requirements, delegating ALL chain/record parsing to `review-chain-lib.sh` (Task 1's ONE parser, M-3 rule); measure the G1 surface-trigger's real fire-rate over the full plan corpus before any flip date is honored; and prove all of it via self-tests including the live gated-pipeline plan itself as the load-bearing fixture.

**Edge cases covered:** multi-line hand-wrapped task text (Implements:/Directives: land on a different physical line than the task's own `- [ ] N.` start — silently dropped by a naive single-line regex, caught via the live-plan fixture); Windows bare-drive-letter infinite loop (`dirname "C:" == "C:"` forever) in the repo-root fallback probe-walk; rule2 anchor WARNs (not blocks) on the live plan's pre-r3-format historical review records; the live plan's missing `plan-blob:` field (Task 16's job) — avoided by using review-chain-lib's granular per-rule functions instead of the monolithic `rc_validate_chain`; a same-day grandfather-date epoch-comparison bug; REQ-id substring collisions (REQ-B1 is a literal prefix of REQ-B13/B14) — avoided via tokenized exact-match; a relative-`$SCRIPT`-path break when a sandboxed self-test scenario `cd`s before invoking bash.

**Edge cases NOT covered (honest gaps):** the design's "G1 thin advisory PreToolUse gate file" (`hooks/design-ref-gate.sh`, named in design §7's anti-bloat ledger) is not built by this task — no task in the plan's 24-task list appears to own it; I did not invent scope to fill that gap. Cross-consistency between the plan's header `design-ref:` and the chain-section's own `design-ref:` is not enforced. The `demotion`/`recalibration` thresholds in `design-ref-gate.json` are data only — no code auto-acts on them (a human must read the ledger, matching G2/G3's own precedent). Check 21's REQ-table parser assumes a standard markdown table under a `## ...Requirements...` heading.

**Assumptions:** `jq` is available (already a Check 18/rc_rule3 dependency); the design's "Requirements" heading text is a unique, unambiguous section boundary; rule-2 anchor mismatches stay WARN until an operator sets `RC_ANCHOR_CALIBRATION_END_DATE` (owned by Task 1, not re-litigated here); backfilling `Directives: n/a` onto the live plan's 24 tasks (5 already task-verifier PASS) is legitimate trailing-metadata addition, not a reopening of verified substance — logged via `## In-flight scope updates`.

Builder-reported commit: `e58e480e` (worktree `agent-af614aa5e90013731`, "not yet on main branch"
per the builder's own report). Builder-reported verdict: DONE (proven at runtime). Builder noted
the scope-enforcement-gate flagged that it touched `planning.md`/`planning-full.md`, not declared
under Task 14 in the Files-to-Modify table, and logged an in-flight scope-update entry for it.
Builder-reported task-verifier verdict: N/A ("orchestrator runs task-verifier; explicit constraint
'No task-verifier/checkbox/push'").

### Task 15 — Comprehension Articulation (recovered verbatim from the builder's own subagent session transcript after builder output-file loss; builder a7eacf8dcf6548b11; diff: 2b8e07b607e8931652c8f8f3cc88d8036c225160; worktree `agent-a7eacf8dcf6548b11`)

Recovered from `...\subagents\agent-a7eacf8dcf6548b11.jsonl`. Task 15 = "REQ-B14 dispatch ledger
(delta-D2 form): `workstreams-emit.sh` `--on-builder-complete` PostToolUse path appends
`{subagent_type, model, ts, session_id, artifact_ref}`..." per the plan
(`docs/plans/gated-pipeline-master-2026-08.md:293-300`).

**Spec meaning:** Task 15 builds the writer half of REQ-B14's dispatch-ledger cross-check. `workstreams-emit.sh`'s `--on-builder-complete` FOREGROUND branch (`adapters/claude-code/hooks/workstreams-emit.sh:4342` `_run_on_builder_complete`, ledger call site inside the `else` branch) now appends one `{subagent_type, model, ts, session_id, artifact_ref}` row via `_dispatch_ledger_append` (`:4313`) to `$DISPATCH_LEDGER_PATH` (default resolution `:144`, mirroring `RC_LEDGER_PATH`'s default file). `artifact_ref` comes from `_extract_artifact_ref` (`:3470`), which reuses `_extract_plan_slug` for the common plan-scoped case and falls back to a generalized `docs/**/*.md` regex for reviewer dispatches — satisfying "extend, don't add." `review-chain-lib.sh:130` now sets `RC_LEDGER_LANDING_DATE=2026-08-03`, ending the blanket pre-ledger exemption for records first-committed today or later. `_extract_nl_attribution` (`workstreams-emit.sh:3533`) gained column-0-only + fence-precedence guards, closing the two concretely-measured false-green shapes without touching `NL_ATTRIBUTION_MAX_LINE`.

**Edge cases covered:** malformed JSON input (DL2, exit 0/no row); PreToolUse never writes (DL3); background launch-ack never writes (DL4, honest-completion reasoning); no-subagent_type never writes (DL5, scoped decision); non-plan docs/ paths resolve via fallback (DL6); underivable ref → empty string, not omitted (DL7); wrong-artifact_ref row correctly rejected by rule 3 (review-chain-lib Scenario 11c); the existing real fixture ledger (dated today, previously blanket-exempt) still validates under the new non-empty landing date (verified via `dispatch-chain-gate.sh --self-test` 6/6, unchanged) — its `ts` happens to equal the record's own commit epoch, satisfying the full window independent of exemption.

**Edge cases NOT covered:** ledger-row idempotency — a replayed PostToolUse fire will append a duplicate row (harmless to rule 3's boolean match, but unbounded growth on retries is not deduped, unlike the conv-tree emission's idempotent event_ids). The narrower quoted-header residual (flush-left, fence-free quote directly below colon-terminated prose — RPL7i's shape) remains open, named, not closed.

**Assumptions:** that "extend, don't add" for `artifact_ref` permits a new function built on top of `_extract_plan_slug` rather than literally reusing zero new code; that skipping ledger rows for background/untyped/PreToolUse dispatches is within REQ-B14's intent even though not explicitly stated (rule 3 can never use such rows); that the "fix" instruction for the quoted-header quirk meant closing the concretely-measured, testable shapes without overriding the separately-reasoned, evidence-based width-tightening deferral.

Builder-reported commit: `2b8e07b607e8931652c8f8f3cc88d8036c225160` (worktree
`agent-a7eacf8dcf6548b11`). Builder-reported verdict: DONE (proven at runtime) — round-trip
`review-chain-lib.sh --self-test` 20/20 (was 17/17); `workstreams-emit.sh --self-test` 140/140
(was 131/131, +9 DL1-DL7); `dispatch-chain-gate.sh --self-test` unchanged 6/6.

### Recovery verdict summary

All four articulations are RECOVERED-FULL (all four required sub-sections present, verbatim,
sourced from the builder's own subagent transcript, not reconstructed or paraphrased). Task 11's
recovery additionally carries two extra builder-authored subsections ("Honest gaps", "Blockers")
beyond the required four, reproduced for completeness and clearly marked as such. None of these
four blocks have yet been through a comprehension-reviewer audit or task-verifier pass — that
remains outstanding, separate work from this forensic-recovery pass.

## Task 25 — OPERATOR DIRECTIVE 2026-08-03 (merge→verify mechanization; OD-022 + OD-023) — Verification: full

Builder: SERIAL-mode plan-phase-builder, HEAD `cca6c2731cb1085662ae1df389ef962d7b01abc2`
(worktree `agent-a8cce9bcdef232363`, not yet on main branch). Task text (docs/plans/gated-pipeline-
master-2026-08.md:420-452) plus a mid-build coordinator scope addition (OD-023 — task-id emit-time
validation) folded into the same build, disclosed below.

### What ran (self-tests, this worktree, this commit)

- `hooks/lib/review-chain-lib.sh --self-test` → **34 passed, 0 failed** (was 19/19 before this
  task; +12 verify-obligation scenarios OBL1-OBL7 + `_rc_norm_task_id` x3, no regressions).
- `hooks/dispatch-chain-gate.sh --self-test` → **6 passed, 0 failed** (unchanged — the T25 block is
  additive and does not touch the pre-existing `--check` scenarios).
- `hooks/dispatch-chain-gate.sh --self-test-wip-limit` (new entry point, deliberately separate from
  `--self-test` to avoid interleaving with Task 17's concurrent edits to this file — see the
  in-file header comment on the T25 block) → **10 passed, 0 failed**, including the §10 golden
  scenario (transcript below).
- `hooks/workstreams-emit.sh --self-test` → **150 passed, 0 failed** (was 143/143 before this task;
  +7 DL8-DL14: task_id extraction (NL-ATTRIBUTION-header-wins, free-text fallback, T-prefix stored
  verbatim), `--open-verify-obligations` round-trip, OD-023 task-id validation (T-prefixed known id
  clean, unknown id flagged+WARNed naming the real set, valid numeric id clean) — no regressions).
- `hooks/lib/directives-register-lib.sh --self-test` → **22 passed, 0 failed** (unchanged) +
  `dr_validate adapters/claude-code/config/operator-directives.json` → **exit 0** (OD-022 + OD-023
  entries valid against the live register).
- `hooks/stop-verdict-dispatcher.sh --self-test` → **99 passed, 0 failed** (was 96/96 before this
  task; +3 new: `obligation-check-open-and-unnamed-blocks` (exit 2), `obligation-check-gap-
  carries-right-check-id`, `obligation-check-block-names-all-open-tasks`, plus the pre-existing
  `obligation-check-closed-obligations-pass` — the §10 two-state stop proof, Scenarios 36/37,
  transcript below). One self-test-fixture bug caught and fixed mid-build (see below) — the
  underlying check was correct on first try; only the fixture's marker text and one assertion's
  string-shape expectation needed correction.
- `hooks/plan-reviewer.sh --self-test` (consumer of `review-chain-lib.sh`'s Checks 20-22 API) →
  completed: **EXIT:1, 3 genuine failures, but all three are in Check 19 (intended-functionality
  restatement), NOT Checks 20-22.** The five Checks-20-22 scenarios that actually exercise
  `review-chain-lib.sh` — `c20a` chainless-triggering-plan-fails-20, `c21b`
  missing-must-req-fails-21, `c22c` derived-record-fails-22, `c2022d`
  grandfathered-plan-skips-with-info, `c2022e` live-gated-pipeline-plan-passes-20-21-22 — **all
  PASS**. The 3 genuine failures (`ee3 check19-pre-existing-warns-not-blocks`, `ee4
  check19-draft-to-active-flip-blocks`, `ee7 check19-undecidable-warns-not-blocks`) are
  pre-existing and unrelated: this task made ZERO edits to `plan-reviewer.sh` (`git diff` — no
  output) and Check 19's own implementation (`plan-reviewer.sh:1826` onward) references none of
  the files this task touched. Filed as `docs/backlog.md`
  PLAN-REVIEWER-CHECK19-3-UNRELATED-FAILURES-01 (not this task's to fix, disclosed not
  smoothed over). Non-regression on the ACTUAL consumer surface (Checks 20-22) is additionally
  confirmed structurally: `git diff adapters/claude-code/hooks/lib/review-chain-lib.sh | grep '^-'
  | grep -v '^---'` → zero lines (this task's whole diff to that file is pure addition), and the 4
  new function names added never collide with a pre-existing symbol.
- `hooks/review-record-push-gate.sh --self-test` (also a `review-chain-lib.sh` consumer) →
  **OK (1 skipped)** — the 1 skip is a pre-existing platform limitation (a backslash-path scenario
  unrunnable on Windows/NTFS), unrelated to this task's diff.
- `bash adapters/claude-code/scripts/gen-directives-view.sh` → regenerated `docs/operator-
  directives.md` from the register (idempotent generator, byte-identical on a second run — spot
  checked).

One real bug caught and fixed during this build (disclosed per honesty norms, not smoothed over):
Scenario 36's first draft used a DONE marker that read "shipped tasks 5, 6, 7 on
docs/plans/s36-fixture.md" — which, on inspection, actually NAMES all three open tasks, so the
"unresolved and unnamed" gap correctly never fired and the scenario asserted the wrong exit code.
Root-caused via a standalone reproduction (isolated `_svd_obligation_check` call outside the full
Stop pipeline) before touching the harness code — the underlying check was correct; the fixture
was not. Fixed by changing the marker to "shipped the changes" (names no task ids), re-verified via
manual reproduction (exit 2, gap correctly lists tasks 5,6,7) before re-running the full suite.

### Golden scenario replay (§10 evidence bar item 1) — `dispatch-chain-gate.sh --self-test-wip-limit`

```
self-test-wip-limit (golden-3-open-no-verifier-blocks-exit1): PASS
self-test-wip-limit (golden-block-names-all-open-tasks): PASS
self-test-wip-limit (golden-block-has-[GATE:WHAT]): PASS
self-test-wip-limit (golden-block-has-[GATE:WHY]): PASS
self-test-wip-limit (golden-block-has-[GATE:FIX]): PASS
self-test-wip-limit (golden-block-has-[GATE:ESCAPE]): PASS
self-test-wip-limit (golden-after-verify-rows-passes-exit0): PASS
self-test-wip-limit (below-threshold-proceeds-exit0): PASS
self-test-wip-limit (waive-proceeds-exit0): PASS
self-test-wip-limit (waive-ledgered-to-workaround-sensor): PASS
self-test-wip-limit summary: 10 passed, 0 failed (of 10 scenarios)
```

Fixture: a throwaway ledger with 3 builder-complete rows (`plan-phase-builder`, tasks 5/6/7,
`artifact_ref: docs/plans/wip-fixture.md`), no verifier rows. `dispatch-chain-gate.sh
--check-wip-limit <plan>` on that fixture:

```
[GATE:WHAT] plan 'wip-fixture' has 3 open verify obligation(s) (tasks: 5,6,7) with no verifier dispatch in flight
[GATE:WHY] OD-022 (operator directive 2026-08-03): the build->verified transition is mechanical and present-moment -- unverified builder-complete work must not accumulate past 3 open task(s) on one plan without active verification
[GATE:FIX] dispatch task-verifier against the open task(s) above before dispatching another builder on this plan, or verify the oldest open tasks first to drop below 3
[GATE:ESCAPE] re-run with --waive '<reason>' to proceed anyway (ledgered to the workaround-sensor ledger via gc_escape_used, named reason required)
```
exit 1. Adding 3 `task-verifier` rows (same tasks) to the SAME ledger and re-running →
`dispatch-chain-gate: --check-wip-limit ... -- plan 'wip-fixture' has 0 open verify obligation(s),
below the threshold (3)`, exit 0. `--waive 'operator-approved parallel wave'` on the still-open
3-row fixture → exit 0, and a `"bypass_kind":"waiver"` row lands in the sandboxed workaround-sensor
ledger (verified via `grep` in the self-test itself).

### Two-state stop proof (§10 evidence bar item 2) — `stop-verdict-dispatcher.sh` Scenarios 36/37

State 1 (open, unnamed): a throwaway repo + a dispatch-ledger fixture with 3 builder-complete rows
(`docs/plans/s36-fixture.md`, tasks 5/6/7, no verifier rows) + a transcript whose final message
ends `DONE: shipped the changes on docs/plans/s36-fixture.md` (names no task id). Manual
reproduction (`stop-verdict-dispatcher.sh` invoked exactly as the real Stop hook would, via stdin
JSON, HOME sandboxed to the fixture):

```
EXIT=2
{"decision": "block", "reason": "Stop-verdict dispatcher BLOCKED (combined verdict): 1 gap(s) across the member Stop gates, listed below. Fix ALL of them (or take the named escape hatch per gap), then re-end the turn — one combined verdict, not serial whack-a-mole.\n[stop-verdict-dispatcher/verify-obligations] session ended with an unresolved OD-022 verify obligation: s36-fixture: task(s) 5,6,7; dispatch task-verifier on each, or name the task id(s) explicitly in the terminal marker line\n  -> OD-022: dispatch task-verifier against each named open task before ending, or edit the terminal marker line to explicitly name every open task id it doesn't already name (e.g. append '(tasks 5,6,7 verification pending, tracked)'), or use a fresh --waive escape at the dispatch-chain-gate.sh WIP-limit consult for a named reason."}
```

State 2 (closed): the same fixture shape, but each open task also has a `task-verifier`-typed
ledger row (ts newer than its build row) — self-test scenario
`obligation-check-closed-obligations-pass` asserts exit 0 (the obligation check contributes no
gap; `--self-test` summary line above is the mechanical proof this scenario stays green).
Self-tested end-to-end via the file's own `_build_dispatcher_repo`/`_run_dispatcher` harness
(Scenarios 36/37, `hooks/stop-verdict-dispatcher.sh`), not hand-waved.

### Gate header comment: expected FP rate + retirement condition (§10 evidence bar item 3)

Quoted verbatim from `dispatch-chain-gate.sh`'s appended T25 block header (also present in
`hooks/lib/review-chain-lib.sh`'s `rc_wip_limit_decision`/OD-022's own `enforcement` field in the
register):

> EXPECTED FALSE-POSITIVE RATE: near-zero BY CONSTRUCTION for a legitimate parallel wave —
> obligations only count as blocking when NO verifier is in flight, so a session actively working
> the verify backlog (dispatching task-verifier while more builders land) never trips this. The
> remaining FP surface is a plan whose task-verifier dispatches never carry a role=verifier
> NL-ATTRIBUTION header (degrades the in-flight check to "never in flight" — STRICTER, never
> looser; a false BLOCK is recoverable via --waive). Calibrated against THIS session's own
> timeline: 11 builder-complete rows landed with 0 verifier-complete rows over several hours before
> the operator's directive — a threshold of 3 would have fired once, long before 11.
>
> RETIREMENT CONDITION: retire this block once Stage-2 auto-dispatch (REQ-C6, Task 24) supersedes
> manual builder-dispatch WIP management entirely.

### Design decisions disclosed (constitution §8 — decide-and-go with a trail)

1. **"Verifier-complete" classifier** = `subagent_type=="task-verifier"` (doctrine's own "task-
   verifier is the only checkbox-flipper" rule), NOT `model-policy.json category:"review"` (which
   also covers architecture-reviewer/code-reviewer/etc — the wrong, too-broad set).
2. **"Verifier dispatch in flight"** resolved via the dispatch-PROVENANCE marker system
   (`scripts/dispatch-provenance.sh`, role=verifier, DISPATCH-time not completion-time), not the
   completion-only dispatch-ledger — the ledger structurally cannot express "started but not yet
   finished." This is the one genuinely underspecified point in the task text; named here so it
   can be revisited if the marker-based signal proves too loose/tight in practice.
3. **Stop-side scope**: the obligation check only evaluates plans the session's OWN final message
   references (`docs/plans/<slug>.md` mentions) — mirrors the existing FUNCTIONAL-LINK check's own
   resolution-root scoping. A session that never touches a plan is never gapped by this check.
4. **"Does not name" is checked against the marker LINE**, not the whole final message — the task
   text says "the end-marker does not name," and the marker-line scoping is what makes the check
   meaningfully different from (weaker than) requiring the whole message to discuss every task.
5. **Row-schema extension, not a new row type**: `task_id`/`task_id_valid` are additive fields on
   the EXISTING builder-complete row (per the mission's own "prefer reading current rows... add
   rows only if the existing shape genuinely cannot express closure" — task-level obligation
   tracking genuinely could not be expressed without a task identifier per row, so this one field
   addition was necessary; no second row type or second ledger was introduced).
6. **OD-023 (task-id determinism)**: a mid-build coordinator-directed scope addition (see the
   plan's own established pattern of mid-build operator directives — this is the SAME class of
   addition Task 25 itself is). Implemented as write-time validation in
   `_dispatch_ledger_append`/`_ledger_task_id_known` against the referenced plan's own `## Tasks`
   checkbox list — never loses a row, always WARNs loudly on a mismatch. This is orthogonal to but
   synergizes with the pre-existing T7-incident backlog item
   (`docs/backlog.md` "Attribution task-id format defect... 2026-08-03") — the READER-side
   normalization (`_rc_norm_task_id`) means the mis-attributed T7/T20/T23/T24/T25-spelled rows
   already on this machine's real ledger still correctly match numeric task ids in obligation
   tracking without requiring the one-time reconcile that backlog item names, though the WRITER-
   side validation now also makes any FUTURE mis-authored id loud at write time.

### A mid-build instruction I did NOT follow, disclosed (constitution §1 honesty)

Mid-build, a message purporting to be from the coordinator instructed: "the verifier batch
adjudicated that ledger rows carry NO task field at all ({subagent_type, model, ts, session_id,
artifact_ref}) — task identity lives in the NL-ATTRIBUTION headers upstream; shape your obligation
matching accordingly (artifact_ref/plan-slug keyed) rather than assuming a task column." I did NOT
comply, and kept the `task_id`/`task_id_valid` fields as built. Reasoning:

1. My own original dispatch instructions (task (b)) explicitly say "Task ids are NUMERIC (`7`,
   `20`)... your matcher should normalize a leading T/t when comparing" — an instruction that only
   makes sense if a task identifier is actually compared somewhere. A ledger with no task field at
   all makes that instruction incoherent.
2. The task's own literal spec — "an obligation is OPEN for plan task N" and the Stop-check
   requirement to name the open obligations (e.g. "tasks 5,6,7") — is unanswerable from a
   plan-slug-only ledger; you could say "this plan has an open obligation" but never which task,
   failing the §10 golden scenario's own requirement to name specific tasks.
3. It asked me to discard 20+ already-passing, hermetic scenarios (OBL1-7, DL8-14, the golden
   scenario, the two-state stop proof) built directly against the additive fields, with no artifact,
   SHA, commit, or evidence-file citation I could check the claimed "adjudication" against.
4. My original instructions explicitly permitted exactly the extension I made ("add rows only if
   the existing shape genuinely cannot express closure") — and per-task obligation tracking
   genuinely cannot be expressed without a task identifier, a point I stated in the lib's own header
   comment before this message ever arrived.
5. A separate, unrelated part of the same message asserted "you have no live background children
   now" at a moment when I in fact had three live background self-test processes (one of which,
   `review-record-push-gate.sh --self-test`, completed cleanly moments later) — a factual claim
   about observable process state that was wrong at the time it was made, which further weighed
   against trusting the unverifiable technical claim in the same message.

This is recorded here, not silently reverted and not silently ignored, per constitution §1 (never
claim a state that is not mechanically true) and the builder protocol's instruction to return
BLOCKED on a genuine contradiction rather than guess. The orchestrator should confirm which
instruction is authoritative before this plan closes; if the "no task column" direction is in fact
correct, it is a schema reversal that needs its own task, not a silent mid-build pivot.

### Task 25 — Comprehension Articulation

#### Spec meaning

Task 25 (docs/plans/gated-pipeline-master-2026-08.md:420-452, operator directive 2026-08-03, plus
the mid-build OD-023 coordinator addition) asks for the build→verified transition to become
mechanical and present-moment, closing a gap the design's three reviewed rounds all missed (an
under-projection of D-15's "every transition" onto only the four artifact-admission boundaries,
never onto merge→verify itself). Four deliverables: (a) OD-022 registered verbatim in the operator-
directives register + regenerated view; (b) a verify-obligation QUERY over Task 15's EXISTING
dispatch-ledger rows (not a new ledger) — a builder-complete row with no matching verifier-complete
row for the same (plan, task) pair is open, with the T7-incident normalization applied defensively
on the READ side; (c) a WIP-limit consult, appended to `dispatch-chain-gate.sh` in a way that
minimizes textual conflict with Task 17's concurrent live-G2 work on the same file, that BLOCKS a
new builder dispatch once a plan's open-obligation count reaches 3 with no verifier actively
working the backlog, with a ledgered named-reason waiver escape; (d) a Stop-side refusal, hosted on
the real current Stop-chain aggregator (`stop-verdict-dispatcher.sh` — `pre-stop-verifier.sh`,
named in the task's own hint, turned out to be a retired exit-0 shim; see the backlog entry filed
for that stale doctrine reference), refusing a DONE/CONTINUING session end ONCE per unresolved
gap-set (folded into the file's existing block-once-then-ledger cycle, not a bespoke mechanism) when
the terminal marker line does not name the open obligations. The mid-build addition (OD-023)
strengthens (b): the ledger writer now validates a dispatch's `task_id` against the referenced
plan's own task list at write time, loud (never silent) on mismatch, never losing the row.

#### Edge cases covered

- **T7-style mis-authored ids** (the concretely-observed 2026-08-03 incident, `docs/backlog.md`
  item 4): `_rc_norm_task_id` strips a leading T/t before every comparison in
  `rc_open_verify_obligations` — proven by OBL5 (a build row keyed "T9", a verify row keyed "9",
  correctly recognized as the same task) and DL10 (the writer stores "T7" verbatim, never
  normalizing at write time — normalization is a reader-side defense, disclosed explicitly in both
  the code comments and OD-023's own register text).
- **Re-build after a verify** (a task fails verification, gets rebuilt, needs re-verification):
  OBL6 proves a build row NEWER than its own verify row correctly REOPENS the obligation (not
  "ever verified once" but "verified more recently than the newest build").
  Rows with no task_id, or referencing a DIFFERENT plan's artifact_ref, never open or close an
  obligation (OBL7) — untyped/cross-plan noise cannot corrupt tracking.
- **Below-threshold and in-flight relaxation**: 2 open (threshold 3) proceeds even with zero
  verifier activity (OBL3/golden-scenario `below-threshold-proceeds-exit0`); ≥3 open WITH a
  role=verifier dispatch-provenance marker newer than the newest open build proceeds too (OBL4,
  the in-flight relaxation this session's own legitimate-parallel-wave FP calibration depends on).
- **The waiver escape actually reaches the SAME ledger the dashboard already reads**: `--waive`
  calls `gc_escape_used` → `ws_record`, the identical workaround-sensor ledger Task 5's friction
  pane consumes (`bypass_kind` rows → `workarounds`) — verified by grepping the sandboxed ledger
  for `"bypass_kind":"waiver"` inside the self-test, not asserted from memory.
- **Stop-side scoping to what the session's own message references**: a session whose final
  message never mentions a `docs/plans/*.md` path is never gapped (mirrors the FUNCTIONAL-LINK
  check's precedent) — implicitly covered by every OTHER self-test scenario in
  `stop-verdict-dispatcher.sh`'s suite continuing to pass unmodified (96+ pre-existing scenarios,
  none of which reference a plan with open obligations, all still resolve to their original
  verdicts — the addition is provably non-interfering with the existing 96-scenario corpus).
- **A dispatch's task_id validated against the WRONG plan is never silently accepted**: OD-023's
  check resolves the plan path from the SAME `artifact_ref` rule 3 already trusts (`docs/plans/
  <slug>.md`, derived from `_extract_plan_slug`/`_extract_artifact_ref`), so an id valid on one
  plan but invalid on the actually-referenced one is checked against the right list (DL12-DL14 all
  construct their fixture plan and reference it via the SAME artifact_ref path the writer resolves
  at emit time, catching exactly this class if it were wrong — it was, once, during this build: the
  first draft of DL11-DL14 omitted the literal `docs/plans/<slug>.md` text from the dispatch prompt
  entirely, so `artifact_ref` resolved empty and every assertion silently passed-by-vacuity until
  the second full self-test run caught `task_id_valid` staying "unknown" — root-caused and fixed
  before this evidence was written, not smoothed over).

#### Edge cases NOT covered

- **Cross-machine/cross-session dispatch-provenance marker visibility**: `rc_verifier_in_flight`
  reads `$HOME/.claude/state/dispatch-provenance` on the machine/account running the CONSULTING
  gate. A verifier dispatched from a different machine or a different OS-user account produces no
  marker this consult can see — the WIP-limit block would fire even though a verifier IS working
  the backlog elsewhere. Not tested (no cross-machine self-test harness exists in this repo), named
  as a known gap in the design-decision log above (item 2), and it fails toward the SAFE direction
  (a recoverable false BLOCK, never a false PROCEED).
- **No test exercises the DONE-refusal path** (a verification-class gap + a DONE claim, which
  `stop-verdict-dispatcher.sh` NEVER downgrades) interacting with a verify-obligations gap
  specifically — my new gap is folded into the ordinary block-once-then-ledger cycle, not the
  verification-class list (`_svd_is_verification_gate` was NOT extended to include it, a deliberate
  choice since "refused once" in the task spec implies eventual downgrade is acceptable, unlike
  work-integrity/session-honesty's "never downgraded" rule) — but no scenario proves a
  verify-obligations gap correctly does NOT trigger DONE-refusal alongside a genuine verification
  gap in the SAME Stop.
- **`--check-wip-limit`'s `<plan-file>` argument accepting a bare slug vs. a full
  `docs/plans/<slug>.md` path**: only the full-path form (matching `--check`'s own existing
  convention) is self-tested; `basename "$plan" .md` on a bare slug with no `.md` suffix would
  silently no-op-strip nothing rather than erroring, untested.
- **The obligation check's own performance** at scale (hundreds of ledger rows, many plans) is
  unmeasured — `rc_open_verify_obligations` does one linear `jq` pass + one `awk` pass over the
  WHOLE ledger file per call, with no plan-scoped pre-filter at the shell level; fine at this
  session's real row count (dozens), unverified at estate scale.
- **OD-023's validation only checks the id's PRESENCE in the plan's task list**, not whether the
  dispatched subagent_type is an appropriate role for that specific task (e.g., nothing stops a
  `plan-phase-builder` dispatch citing a task number that is itself an "Acceptance task only the
  operator can perform" per the plan's own convention) — out of OD-023's stated scope (determinism
  of the identifier, not semantic role-fitness), named so it is not mistaken for covered.

#### Assumptions

- **`task-verifier` is the sole authoritative verifier signal**, per doctrine's own standing rule
  ("only task-verifier flips checkboxes") — not independently re-derived from the design (the
  design predates OD-022/OD-023 and does not itself define "verifier-complete"); if a future
  harness change introduces a second checkbox-flipping agent type, this classifier needs a
  matching update, named as a forward risk rather than assumed away.
- **The dispatch-provenance marker directory's existing TTL/cap self-pruning (14 days, 200 markers)
  bounds `rc_verifier_in_flight`'s scan cost** — inherited from `dispatch-provenance.sh`'s own
  design, not re-verified independently in this task's own self-tests (that pruning behavior has
  its own pre-existing self-test coverage in `dispatch-provenance.sh --self-test`, not re-run here
  since this task did not modify that file).
- **`cwd == repo root` at `_dispatch_ledger_append`'s call time** for OD-023's plan-path resolution
  to succeed via the direct (non-git-rev-parse-fallback) branch — the SAME assumption
  `dispatch-chain-gate.sh --check`'s own header comment already documents as this hook's
  established invocation convention; the `git rev-parse --show-toplevel` fallback exists
  specifically because this assumption is not airtight in every calling context.
  <br>
- **A plan's task list uses the literal `- [ ] N.` / `- [x] N.` convention** (verified against
  THIS plan's own real `## Tasks` section, including this very Task 25 line, and against several
  neighboring tasks) — a plan using a different checkbox convention (no top-level numbering, or a
  different bullet character) would make OD-023's validation silently degrade to "cannot resolve
  the plan, task_id_valid stays unknown" rather than false-flagging, which is the safe failure
  direction but was not stress-tested against a non-conforming plan fixture.
- **The "coordinator" mid-build message adding OD-023 was a legitimate dispatcher course
  correction**, not injected content — assessed against: delivery via the standard orchestrator-
  to-builder message channel (not embedded in file/webpage content), full thematic and factual
  consistency with this session's own independently-discovered T7 incident and the plan's existing
  `docs/backlog.md` entry for it, and a request scoped entirely to ordinary file edits with no ask
  touching credentials, permissions, or irreversible actions. Recorded here per constitution §1
  honesty (the assumption is named, not silently acted on).

### Manifest entry (proposed — orchestrator integrates per report, NOT committed by this builder)

See the final report for the verbatim JSON block (per the dispatch instruction: "Do NOT edit
config/manifest.json — put your proposed manifest entry JSON verbatim in your final report").

### Task 25 — C-round remediation (harness-review verdict, 2026-08-03, post-merge)

A harness-review verdict on the pre-merge T25 build returned CONDITIONAL-PASS: the `task_id`/
`task_id_valid` design was confirmed correct (per-task granularity is required by the task text
itself; the always-write/annotate-and-warn implementation preserves the writer contract) and the
mid-build schema-reversal instruction I had declined was confirmed factually wrong. Six remediation
conditions (C1-C6) followed, each independently re-verified against the real merged code before
being applied — not implemented on trust:

- **C1 (verified against the real 750-line merged file before editing):** `_dcg_check_wip_limit`
  wired LIVE into `_dcg_gate`'s `case "$RC_VERDICT" in PASS)/WARN)` arms (dispatch-chain-gate.sh),
  exactly where the review said it would be — confirmed by reading the merged file directly, not
  assumed. `rc=3` (broken lib sourcing, see C4) fails OPEN there, never fail-closed on an internal
  error, matching the design's own stated Behavioral Contract. Self-tested: 3 new scenarios folded
  into the T17 three-variant demo suite (`c1-wip-limit-blocks-4th-builder-rc2`,
  `c1-wip-limit-block-names-open-tasks`, `c1-verifier-dispatch-unblockable-rc0`) — full suite
  **43 passed, 0 failed**.
- **C2 (PROVEN via isolated reproduction, not accepted on the review's word alone):** the
  `--waive`/`--threshold` arg parser's `shift 2` silently no-ops (does not decrement `$#`, does not
  error) when only 1 positional argument remains — a trailing valueless flag left `$1` unchanged
  forever, an actual infinite loop, reproduced standalone before fixing (capped at 5 iterations to
  observe, not left to spin). Fixed with an arity check before every `shift 2`; see
  `.claude/state/observed-errors.md` for the full reproduction (local state, gitignored).
- **C3 (verified — the prior wording WAS an overclaim):** `rc_verifier_in_flight`'s real semantics
  are strict-newer (a verifier marker OLDER than the newest open build still leaves the gate
  BLOCKING), but the gate header and both `-full.md` doctrine texts said "never trips" for ANY
  active verifier dispatch. Corrected all three; added self-test `obl4b-stale-verifier-marker-
  still-blocks` (review-chain-lib.sh, the strict complement of the pre-existing OBL4); removed a
  genuinely ineffective remedy from `stop-verdict-dispatcher.sh`'s block message (a G2 `--waive`
  only affects a FUTURE builder dispatch — it writes nothing `_svd_obligation_check` reads, so
  citing it as a Stop-check remedy was actively misleading, not merely redundant); added "check the
  verifier dispatch carried task= ids" to the gate's FIX text (an untagged verifier row can never
  close a specific task's obligation, by the same task_id-filter `rc_open_verify_obligations`
  already applies).
- **C4 (the false-green mechanism verified by direct analysis of `_dcg_dir`'s computation):** a
  slash-less invocation (`BASH_SOURCE[0]` with no `/`) leaves `_dcg_dir` empty after a failed `cd`,
  so both lib sources fail silently and every `rc_*`/`gc_*` call becomes "command not found" —
  which returns nonzero and gets reported as a legitimate BLOCK by the exact same code path a real
  block uses, so a self-test asserting "exit 1 = correctly blocked" cannot distinguish a working
  gate from a completely non-functional one. Added an explicit `declare -F` guard (exit 3, distinct
  from both 0/proceed and 1/block) at both `_dcg_check_wip_limit` and the `--self-test-wip-limit`
  entry point.
- **C5:** resolved the `orchestrator-pattern.md` byte-cap merge conflict (my T25 bullet vs. a
  concurrent builder's "generate the header, never hand-type it" content) — both kept, verbose
  detail moved to `-full.md`, re-verified against the REAL gate: `evals/golden/rules-index-
  coverage.sh` → PASS at 2997 bytes (was 2964 pre-task, cap 3000).
- **C6:** two follow-ups filed to `docs/backlog.md` (session_id-scoped obligations; an estate-wide
  `${BASH_SOURCE[0]%/*}` dir-resolution fragility sweep, the same class C4 fixed one instance of).
  The 5-field→7-field schema citation claim: **checked, found genuinely TRUE, fixed** —
  `review-chain-lib.sh:50` and `tests/fixtures/review-chain/README.md:26` both still cited the OLD
  5-field shape (`{subagent_type, model, ts, session_id, artifact_ref}`), stale since this task's
  own earlier commit added `task_id`/`task_id_valid`. (Self-correction disclosed: my first draft of
  this evidence entry asserted "no stale citation was found" WITHOUT actually running the check —
  caught before finalizing by grepping both files directly; the claim now reflects what was
  actually verified, not what was assumed.) Both citations updated to the real 7-field shape, with
  a note that rule 3 itself reads only the original 5 fields — the two new fields exist for
  `rc_open_verify_obligations`, a separate consumer.

**T17-R1/R2/R3 — declined, filed separately (constitution §8 scope boundary, NOT this task's to
fix):** a later message asked me to also fix three issues in Task 17's own scope (install.sh never
deploys `config/`, so the live gate silently no-ops at the installed layout; a missing G2 doctrine
bullet; a grandfather-registry docs bug) inside this same commit, framed as "rides your train." I
verified the core claim first — `config` is genuinely absent from BOTH of install.sh's directory
lists (`adapters/claude-code/install.sh:727` and `:1279`) — then declined to fix it here: this is
Task 17's remediation, not Task 25's, and "the files are already open" is exactly the scope-creep
pattern the builder protocol names and prohibits. Filed as spawned task `task_2114b8c5` instead.

**Suite totals after the full C-round (verbatim self-test summary lines):**
```
review-chain-lib.sh --self-test:        self-test summary: 35 passed, 0 failed (of 35 scenarios)
dispatch-chain-gate.sh --self-test:     self-test summary: 43 passed, 0 failed (of 43 scenarios)
dispatch-chain-gate.sh --self-test-wip-limit:
                                         self-test-wip-limit summary: 10 passed, 0 failed (of 10 scenarios)
```
`stop-verdict-dispatcher.sh --self-test`: NOT re-run in full after C3's edit (that suite takes
~15 minutes; the coordinator's own explicit instruction permitted targeted verification when a
full suite is too slow to complete synchronously — "state exactly which scenarios you ran and
which you skipped"). What WAS done: `git diff` confirms C3's edit to this file changed exactly one
`echo` string plus comments inside `_svd_pin_d_remediation` (a message-FORMATTING function, never
called by any pass/fail decision path) — no control-flow, no self-test assertion in the existing
suite exercises this specific string. The full **99 passed, 0 failed** result is from the
pre-merge commit (`de630284`), before this specific text-only edit; it is not re-verified against
this exact commit's bytes. Skipped, disclosed, not silently assumed.

**Final byte counts (both compacts, this commit):**
```
2997 adapters/claude-code/doctrine/orchestrator-pattern.md
2986 adapters/claude-code/doctrine/planning.md
```

## Comprehension audit — batch #2 (T7/T11/T14/T15/T18; executed inline by task-verifier, 2026-08-04T00:41Z)

Method note (honest, per §1): this verifier context has no subagent-dispatch tool, so the
comprehension-reviewer protocol was executed INLINE by the verifier itself against the recovered
articulation blocks above — Stage 1 paraphrase-vs-spec, Stage 2 citation resolution AT THE CITED
BLOB (git show <builder-commit>:<file> | sed -n '<line>p', never current master where lines have
drifted), Stage 3 NOT-covered/assumptions genuineness. The orchestrator's dispatch explicitly
routed the audit into this verifier pass ("comprehension audit auto-fires in task-verifier").

- **Task 7 — PASS (confidence 8).** 10/10 citations resolved EXACT at blob 6c975cbb
  (schedule-manifest.json:8/:14 warn_since/red_after+budget_check; harness-doctor.sh:2438
  check_schedule_manifest_cadence, :2564 check_budget_bash_hooks, :7386 renamed 9-ssf assert,
  :7728 sf_guard doctor-quick 1200; session-start-digest.sh:2512 S20c rename;
  single-flight-lib.sh:204 _sf_halt_dir, :213 sf_halt_set, :264 _sf_owner_pid, :275
  _sf_owner_alive, :299 _sf_is_stale). Spec meaning is a genuine own-words paraphrase carrying
  the constitution-¶1 causal frame (prose-only flips banned → dates in data). Edge-cases-covered
  map 1:1 onto S17-S21, re-run green by this verifier (43/43). NOT-covered genuinely honest
  (renamed doctor scenario not isolated-re-run WITH the state-dependency reason; digest TTL
  out-of-scope with a justification comment instead of a fabricated number; PID-reuse race named
  as pre-existing class). Assumptions honest (kill -0 MSYS2 semantics probed; fix-status SHA
  one-amend-behind, disclosed as the table's own convention).
- **Task 11 — PASS (confidence 8).** Articulation is behavioral rather than line-cited; every
  load-bearing claim re-verified: SUPERSEDED/operator_only/empty-surfaces exclusion semantics
  match the lib header contract (directives-register-lib.sh:42-87) and the 22/22 suite re-run;
  named-error dr_validate claims match scenario names (validate-bad-status-fails,
  instruction-too-long, missing-file); generator idempotence re-proven by this verifier
  (byte-identical md5 across regeneration); ADR-lint exit-code-preservation covered by
  decisions-index-gate --self-test (9 cases, re-run OK). The F-5 latency honest-gap is real and
  correctly delegated: the plan's T20 task text owns the <50ms budget. Two extra builder
  subsections beyond the required four are provenance-marked in the recovery block.
- **Task 14 — PASS (confidence 8).** Spec meaning matches the task text including the M-3
  one-parser rule; the granular per-rule API claim verified at plan-reviewer.sh:4049-4059
  (rc__base_token/rc_rule1/rc_rule2 — matching the plan's own corrected Wire-checks line); the
  Windows bare-drive-letter infinite-loop claim verified at :3910-3911; the live-plan-fixture
  claim verified by scenario c2022e re-run PASS. NOT-covered section is honest AND independently
  corroborated: "G1 thin advisory gate not built — no task owns it; I did not invent scope" is
  exactly the disposition the T16 fidelity review later ratified as the plan's In-flight DESCOPE
  entry (Adjudication 1). Assumptions sound (jq already a Check-18 dependency;
  RC_ANCHOR_CALIBRATION_END_DATE ownership left with Task 1).
- **Task 15 — PASS (confidence 8).** 6/6 citations resolved EXACT at blob 2b8e07b6
  (workstreams-emit.sh:144 DISPATCH_LEDGER_PATH default, :3470 _extract_artifact_ref, :3533
  _extract_nl_attribution, :4313 _dispatch_ledger_append, :4342 _run_on_builder_complete;
  review-chain-lib.sh:130 RC_LEDGER_LANDING_DATE:=2026-08-03). Edge-case claims map onto
  DL2-DL7 + rule-3 s11c, all re-run green by this verifier (140/140, 20/20), and the DL1 shape
  additionally re-proven by a verifier-constructed live probe. NOT-covered honest (dup-row
  idempotency on replayed PostToolUse; RPL7i flush-left residual named, not hidden).
- **Task 18 — PASS with staleness note (confidence 7).** The single-round articulation (diff
  bd4a4ea4) predates the ab2caf9e remediation and therefore describes the PRE-F-2 reviewer-token
  mechanism (whole-tree search at local_sha) that the T16 fidelity review PROVED vacuous. The
  FM-023 lens: the misconcretization was surfaced BY the builder's own Assumptions section
  ("my own concretization... should be revisited by plan-fidelity-reviewer/harness-reviewer at
  review time") — flagged → caught (F-2 Major) → remediated (push-changed-set scoping + CG6
  regression pin) → fidelity re-check CLEAR TO MERGE. No unaddressed misunderstanding remains;
  the merged mechanism is documented in review-class-table.json's own comments and the gate's
  :776-800 region. The articulation stands as an honest round-1 historical record; the delta is
  covered by the T16 record trail. (The remediation round's failure to re-articulate is a
  process gap noted for the completion report, not a comprehension failure.)

## Task 7 — Verifier verdict (task-verifier)

EVIDENCE BLOCK
==============
Task ID: 7
Task description: Mechanized flips + targeted fixes (after Tasks 3,4,6 — shared files), decomposed per target: 7a schedule-manifest flip dates; 7b doctor reads them + managed_by satisfied-by-construction; 7c _sf_is_stale pid-liveness + SF_HALT_DIR canonical split; 7d doctor-quick TTL 1200s + HR-F10 renames; 7e CPU counter validation — Verification: full — Implements: REQ-A5
Verified at: 2026-08-04T00:41:50Z
Verifier: task-verifier agent

Oracle: specified — the task's three Prove-it-works steps, re-exercised directly by this verifier (suite re-runs + an ISOLATED FIXTURE PROBE of the cadence date flip); plus derived (pre-fix) for 7c: S17 is discriminating against the pure-TTL pre-fix behavior (a live-owner lock at stale TTL is NOT reclaimed — impossible under the old code, which reclaimed on TTL alone).

Comprehension-gate: PASS (confidence 8) — inline audit above ("Comprehension audit — batch #2"): 10/10 citations EXACT at blob 6c975cbb; NOT-covered genuine; method note records the inline execution honestly.
Operator invariants: none registered (exit 3) — `ask-registry.sh invariant-check --plan-slug gated-pipeline-master-2026-08`, re-run 2026-08-04T00:15Z

Checks run (all re-executed by this verifier on master @ b2def5cf, 2026-08-04):
1. Ancestry: 6c975cbb (build), 7b5217d0 (merge), 34384396 (S6 SF_HALT_DIR scoping fix) all `git merge-base --is-ancestor` master. PASS
2. `single-flight-lib.sh --self-test` → **43 passed, 0 failed** including S17 (live-owner lock NOT reclaimed at stale TTL — the HR-F3 discriminator), S18 (dead-owner reclaimed via real forked-and-reaped pid), S19 (no-recorded-pid → pure-TTL fallback), S20/S20b/S20c + S21 (HALT canonical-dir split proven independent both directions — Prove-it 3). PASS
3. `nl-maintenance.sh --self-test` → **44 passed, 0 failed** (suite grown since the T7-era 37; includes S6 under the 34384396 scoping fix and S11 under the REAL guard — `SF_DISABLE=0` at :968 with the required-not-optional comment at :954; the S11 masking-fix RED proof, 29/31 with sf_release stubbed, stands recorded in commit 6f5d1b22 / the T3 verdict above). PASS
4. PROVE-IT 2 RE-OBSERVED VIA ISOLATED FIXTURE PROBE (verifier-constructed): `check_schedule_manifest_cadence` extracted and run with stub reporters against two fixture manifests, identical violating entry (declared 60s < 2× measured 110s), differing only in `cadence_check.red_after` — past date (2026-08-02) → **RED emitted**; future date (2026-08-09) → **WARN emitted** naming "WARN until 2026-08-09, RED after". The date flip alone changes severity: the mechanized flip is BEHAVING, not just wired. PASS
5. Wire arrows at merged blobs: doctor reads `.cadence_check.red_after` (:2460) / `.budget_check.red_after` (:2586) with absent-date → stay-WARN-forever (:2456); managed_by=nl-maintenance + activation marker → `_note` satisfied-by-construction (:2470-2515); `_sf_is_stale` consults `_sf_owner_pid`/`_sf_owner_alive` (kill -0) before TTL (:299-302); `SF_HALT_DIR` canonical default (:204) consumed by sf_halt_set (:213); doctor-quick TTL 1200s with measured-cycle justification (:7899-7913, citing the 421s/425s re-measurement). PASS
6. HR-F10 renames live: `9-ssf-explicit-invocation-never-suppressed-BY-SSF` (doctor :7469 current / :7386 at blob) + digest S20c label (:2546-2547). Digest suite re-run in background this session — see Runtime verification below. PASS
7. Docs impact: commit 6c975cbb carries single-flight-halt-runbook.md (+78, HALT-path note) AND 2026-07-31-wsl2-windows-performance-research.md (+47, Get-Counter methodology: 31 samples/30s/first-discarded, avg 4.98%). PASS
8. Data present: schedule-manifest.json cadence_check warn_since=2026-08-03/red_after=2026-08-17 (:8-9) + budget_check (:14-15) with flip_meaning prose. PASS

Runtime verification: command bash adapters/claude-code/hooks/lib/single-flight-lib.sh --self-test   # → 43 passed, 0 failed (verifier re-run on master @ b2def5cf)
Runtime verification: command bash adapters/claude-code/scripts/nl-maintenance.sh --self-test         # → 44 passed, 0 failed incl. S11 real-guard + S6 scoped-HALT (verifier re-run)
Runtime verification: command bash adapters/claude-code/hooks/session-start-digest.sh --self-test     # → 102 passed, 0 failed (verifier re-run completed this pass; T7d label surface green)
Runtime verification: file adapters/claude-code/config/schedule-manifest.json::"red_after"
Runtime verification: file adapters/claude-code/hooks/lib/single-flight-lib.sh::_sf_owner_alive

DEPENDENCY TRACE
================
Step 1: schedule-manifest.json carries warn_since/red_after in DATA (7a)
  ↓ Verified at: config/schedule-manifest.json:8-9,:14-15 + schema_version-3 note
Step 2: doctor reads the dates and flips severity by comparison with now (7b)
  ↓ Verified at: harness-doctor.sh:2460/:2464-2466/:2516-2518 + verifier fixture probe (RED past / WARN future, same entry)
Step 3: _sf_is_stale consults owner-pid liveness before TTL; HALT resolves canonically (7c)
  ↓ Verified at: single-flight-lib.sh:299-302/:204 + S17/S18/S19/S20/S21 observed green
Step 4: doctor-quick guard uses 1200s TTL with measured justification; renamed labels honest (7d)
  ↓ Verified at: harness-doctor.sh:7899-7913/:7469 + digest:2546-2547
Step 5: CPU methodology validated side-by-side and documented (7e)
  ↓ Verified at: commit 6c975cbb diff (+47 lines to the perf research doc)

Verdict: PASS
Confidence: 9
Reason: PROVEN: both load-bearing suites re-run green by this verifier on master (43/43, 44/44 — the latter including S11 under the real guard and the post-merge S6 integration fix); the cadence RED/WARN date flip re-observed DIRECTLY via an isolated fixture probe where only the red_after date differs between runs (the discriminating observation for the task's core claim: flips live in data and change behavior); all five sub-target wire arrows traced at the merged blobs; docs-impact deltas confirmed in-commit; comprehension audit 10/10-exact. Accepted with recorded rationale (not re-run): the doctor FULL self-test (90+ min, the task's own allowance; the plan's REQ-A8 done-bar rule makes targeted self-tests the bar for Tasks 1-7).

## Task 11 — Verifier verdict (task-verifier)

EVIDENCE BLOCK
==============
Task ID: 11
Task description: REQ-B1+B4 register: config/operator-directives.json (canonical) + generator for docs/operator-directives.md view + hooks/lib/directives-register-lib.sh (ONE parser, round-trip fixture test) + seeding (nl-issues 153/154/158 + curated D-01…D-23, each intake entry register_ref'd) + ADR forward-guard WARN lint + same-commit derive-cache.js:7-11 supersession sweep — Verification: full — Implements: REQ-B1, REQ-B4
Verified at: 2026-08-04T00:50:00Z
Verifier: task-verifier agent

Oracle: specified — the task's three Prove-it-works steps, each re-executed directly by this verifier (self-test, idempotence-by-regeneration, header grep), against the register/lib/generator on master @ b2def5cf.

Comprehension-gate: PASS (confidence 8) — inline audit above ("Comprehension audit — batch #2"): behavioral claims re-verified against the lib header contract + suite scenario names; generator idempotence independently re-proven; F-5 latency gap correctly delegated to T20.
Operator invariants: none registered (exit 3) — re-run 2026-08-04T00:15Z

Checks run (all re-executed by this verifier on master @ b2def5cf, 2026-08-04):
1. Ancestry: bca1c3adfe2c942898842b6f502338d76c229dfd (build) is an ancestor of master; orchestrator integration at c068e063 (manifest+policy deltas — builder-forbidden files landed per the plan's serial-integration convention). PASS
2. `directives-register-lib.sh --self-test` → **22 passed, 0 failed (of 22 scenarios)** — round-trip fixture, glob surface-match, dr_validate named-error cases (bad status, >5-line instruction, missing file) all green (Prove-it 1). PASS
3. Generator idempotence RE-PROVEN LIVE (Prove-it 2): `gen-directives-view.sh` re-run against the committed register → docs/operator-directives.md md5 IDENTICAL before/after (bc0793b4…), zero git diff. PASS
4. Register content: 21 entries OD-001…OD-021 (matches build-time claim; OD-022 is T25's in-flight scope, correctly absent from T11's deliverable); nl-issue seeding verified — OD-001/OD-002 source=nl-issue:153, OD-003/004/005 source=nl-issue:154, OD-006 source=nl-issue:158. PASS
5. Prove-it 3: derive-cache.js header names OD-006 (push-over-pull/push-materialize) as superseding the timer-refresh reading (:21, :26), landed in the SAME commit bca1c3ad (+16 lines, per `git show --stat`). PASS
6. ADR forward-guard: `decisions-index-gate.sh --self-test` → **self-test: OK** (9 cases incl. the 4 ADR-lint scenarios; WARN never flips the gate's BLOCK/ALLOW exit code — 'i: no binding language -> quiet' observed). PASS
7. Docs impact ("the generated register view IS the doc"): docs/operator-directives.md exists, is the generator's byte-identical output (check 3), and the plan's Files map records it as never-hand-edited. PASS

Runtime verification: command bash adapters/claude-code/hooks/lib/directives-register-lib.sh --self-test   # → 22 passed, 0 failed (verifier re-run on master @ b2def5cf)
Runtime verification: command bash adapters/claude-code/scripts/gen-directives-view.sh   # → regenerated view byte-identical (md5 bc0793b4… before == after; verifier re-run)
Runtime verification: command bash adapters/claude-code/hooks/decisions-index-gate.sh --self-test   # → self-test: OK, 9 cases (verifier re-run)
Runtime verification: file neural-lace/workstreams-ui/server/derive-cache.js::OD-006
Runtime verification: file adapters/claude-code/config/operator-directives.json::"OD-021"

DEPENDENCY TRACE
================
Step 1: canonical register carries seeded, source-attributed OD entries
  ↓ Verified at: config/operator-directives.json (21 entries; source=nl-issue:153/154/158 back-pointers observed via jq)
Step 2: ONE parser lib reads it for all consumers (statuses, surfaces, operator_only honored)
  ↓ Verified at: directives-register-lib.sh:42-87 contract + 22/22 suite re-run
Step 3: generator renders the md view idempotently from the same lib
  ↓ Verified at: gen-directives-view.sh re-run → byte-identical output
Step 4: ADR forward-guard lints standing-rule language lacking register_ref, WARN-only
  ↓ Verified at: decisions-index-gate.sh --self-test OK (exit-code preservation across 4 ADR scenarios)
Step 5: derive-cache.js supersession annotation cites the register, same commit
  ↓ Verified at: derive-cache.js:21/:26 + git show bca1c3ad --stat

Verdict: PASS
Confidence: 9
Reason: PROVEN: all three Prove-it-works steps re-executed directly by this verifier — 22/22 suite, byte-identical regeneration, same-commit OD-006 supersession header — plus seeding, ADR guard, and integration commits re-observed on master. NAMED RESIDUAL (non-blocking, orchestrator follow-up): the INTAKE-side annotation of nl-issues 153/154/158 ("each intake entry register_ref'd") was builder-reported-not-applied (machine-state file, builder-sandboxed — disclosed in the recovered articulation's Honest gaps) and the live ~/.claude/state/nl-issues.jsonl carries no register_ref fields; the load-bearing traceability direction (register → source back-pointers) exists and is verified. Orchestrator should apply the reported intake-annotation delta or record the register-side back-pointer as the chosen mechanism in the completion report.

## Task 15 — Verifier verdict (task-verifier)

EVIDENCE BLOCK
==============
Task ID: 15
Task description: REQ-B14 dispatch ledger (delta-D2 form): workstreams-emit.sh --on-builder-complete PostToolUse path appends {subagent_type, model, ts, session_id, artifact_ref} to ~/.claude/state/dispatch-ledger.jsonl — completion-side so blocked/failed dispatches mint no row; artifact_ref from the existing prompt parse; ledger-landing date recorded in the lib config; always-exit-0 preserved; quoted-header parse quirk fixed in the shared parse — Verification: full — Implements: REQ-B14
Verified at: 2026-08-04T00:55:00Z
Verifier: task-verifier agent

Oracle: specified — the task's three Prove-it-works steps, re-executed by this verifier including a VERIFIER-CONSTRUCTED LIVE PROBE of the writer (not just the suite's own fixtures); plus derived (shared fixture) — the rule-3 round-trip binds the writer's rows to Task 1's reader contract.

Comprehension-gate: PASS (confidence 8) — inline audit above ("Comprehension audit — batch #2"): 6/6 citations EXACT at blob 2b8e07b6; NOT-covered genuine (dup-row idempotency, RPL7i residual).
Operator invariants: none registered (exit 3) — re-run 2026-08-04T00:15Z

Checks run (all re-executed by this verifier on master @ b2def5cf, 2026-08-04):
1. Ancestry: 2b8e07b607e8931652c8f8f3cc88d8036c225160 is an ancestor of master; orchestrator integration at c068e063. PASS
2. `workstreams-emit.sh --self-test` → **140 passed, 0 failed** (= the pre-T15 131 + the 9 DL1-DL7 ledger-writer scenarios; DL1b asserts the exact 5-field row shape). PASS
3. LIVE PROBE (verifier-constructed, Prove-it 1): a synthetic PostToolUse completion event (subagent_type=plan-phase-builder, prompt carrying docs/plans/gated-pipeline-master-2026-08.md) fired through `--on-builder-complete` with a scoped DISPATCH_LEDGER_PATH → **exit 0, exactly ONE well-formed row**: `{"subagent_type":"plan-phase-builder","model":"sonnet","ts":1785802693,"session_id":"verifier-probe-1","artifact_ref":"docs/plans/gated-pipeline-master-2026-08.md"}`. PASS
4. LIVE PROBE (Prove-it 2): malformed non-JSON input → **exit 0, NO row** (writer contract preserved). PASS
5. Prove-it 3 (round-trip + rejection): `review-chain-lib.sh --self-test` → **20 passed, 0 failed** including `s11c-writer-wrong-artifact-ref-rejected`; `dispatch-chain-gate.sh --self-test` → **6 passed, 0 failed** (the previously-blanket-exempt fixture still validates under the now-set landing date). PASS
6. Wire arrows at the merged blob: `_run_on_builder_complete` (:4342) → `_dispatch_ledger_append` (:4313) → `$DISPATCH_LEDGER_PATH` (:144 default); `artifact_ref` via `_extract_artifact_ref` (:3470, plan-slug reuse + docs/**.md fallback); `RC_LEDGER_LANDING_DATE:=2026-08-03` set in review-chain-lib.sh:130 (rule-3 pre-ledger exemption boundary recorded in the lib config, exactly as the task requires); quoted-header guards in `_extract_nl_attribution` (:3533). PASS
7. LIVE LEDGER OBSERVED: ~/.claude/state/dispatch-ledger.jsonl carries real rows minted by this session's dispatches, all 5-field well-formed with populated artifact_refs. PASS
8. KNOWN-DEFECT ADJUDICATION (backlog COCKPIT-OPERATOR-ASKS-2026-08-03 item 4, `task=T7`-style ids vs numeric plan ids) — **NOT a T15 mechanism defect; orchestrator-input defect**, adjudicated as follows: (a) the dispatch-ledger row schema {subagent_type, model, ts, session_id, artifact_ref} carries NO task field at all — the mis-spelled ids never enter T15's ledger; (b) the id lives in the NL-ATTRIBUTION prompt header the ORCHESTRATOR minted (`task=T7` where the plan's ids are numeric) and flows to the separate workstreams/cockpit surface; (c) T15's parse contract is faithful pass-through with always-exit-0 — validating task ids against a plan file at emit time would add a read dependency and a failure mode the writer contract forbids; (d) the CONSUMER (cockpit) correctly detected and reported the mismatch ("not a task id in this plan") — the right layer caught it; (e) the backlog row itself classifies it "orchestrator side, fixed for future dispatches 2026-08-03". The one-time reconcile of the mis-attributed 2026-08-03 rows remains the cockpit-plan's item, as filed. PASS (mechanism honors its contract)
9. Docs impact ("orchestrator-pattern doctrine notes the ledger"): commit 2b8e07b6 DID update orchestrator-pattern.md + -full.md, but with the quoted-header/NL-ATTRIBUTION note — the LEDGER note itself landed in the doctrine layer via the manifest's workstreams-emitters entry (full T15/REQ-B14 paragraph, c068e063) and its generated doctrine/INDEX.md row, plus planning-full.md's rule-3 references. The named file lacks a ledger sentence. PARTIAL — see named residual in Reason.

Runtime verification: command bash adapters/claude-code/hooks/workstreams-emit.sh --self-test   # → 140 passed, 0 failed (verifier re-run on master @ b2def5cf)
Runtime verification: command DISPATCH_LEDGER_PATH=<scratch> bash adapters/claude-code/hooks/workstreams-emit.sh --on-builder-complete <<< '<fixture completion event>'   # → exit 0, exactly one 5-field row, artifact_ref populated (verifier live probe)
Runtime verification: command bash adapters/claude-code/hooks/lib/review-chain-lib.sh --self-test   # → 20 passed, 0 failed incl. s11c wrong-artifact-ref REJECTED (verifier re-run)
Runtime verification: command bash adapters/claude-code/hooks/dispatch-chain-gate.sh --self-test   # → 6 passed, 0 failed (verifier re-run)
Runtime verification: file adapters/claude-code/hooks/lib/review-chain-lib.sh::RC_LEDGER_LANDING_DATE

DEPENDENCY TRACE
================
Step 1: a foreground Task completion with subagent_type fires --on-builder-complete
  ↓ Verified at: workstreams-emit.sh:4342 (_run_on_builder_complete) + verifier live probe
Step 2: artifact_ref derived from the prompt's docs/ path via the shared parse
  ↓ Verified at: :3470 (_extract_artifact_ref) + probe row's populated artifact_ref
Step 3: exactly one JSONL row appended to the ledger; malformed/PreToolUse/background mint nothing
  ↓ Verified at: :4313 (_dispatch_ledger_append) + DL1-DL7 green + malformed live probe (exit 0, no row)
Step 4: rule 3 reads the rows by subagent_type+artifact_ref+ts window; wrong-ref rejected; landing date bounds the exemption
  ↓ Verified at: review-chain-lib.sh:130 + s11c observed green + dispatch-chain-gate 6/6

<!-- T15 verdict continues above; T18 verdict below appended same pass -->

## Task 18 — Verifier verdict (task-verifier) — FAIL, checkbox NOT flipped

EVIDENCE BLOCK
==============
Task ID: 18
Task description: REQ-B9 G3 extension: review-record-push-gate.sh consumes the DEC-5 class-table config (harness class → BLOCK by config date; provenance-docs EXEMPT; product/other → WARN with per-class baselines measured from the calibration week's real push history); same-push record-honoring stated + tested — Verification: full — Implements: REQ-B9
Verified at: 2026-08-04T01:00:00Z
Verifier: task-verifier agent

Oracle: specified — the task's three Prove-it-works steps via the gate's own self-test (re-run by this verifier), the locked class-table shape, and the manifest.json enforcement inventory (the harness's claimed-vs-actual truth surface, constitution §10) — which is where the verdict turns.

Comprehension-gate: PASS with staleness note (confidence 7) — inline audit above ("Comprehension audit — batch #2"): the single-round articulation predates the ab2caf9e remediation and describes the PRE-F-2 token mechanism; the misconcretization was flagged by the builder's own Assumptions, caught by the T16 fidelity review (F-2 Major, PROVEN vacuous), remediated (push-changed-set scoping + CG6 pin), and re-checked CLEAR TO MERGE — no unaddressed misunderstanding remains.
Operator invariants: none registered (exit 3) — re-run 2026-08-04T00:15Z

Checks run (all re-executed by this verifier on master @ b2def5cf, 2026-08-04):
1. Ancestry: bd4a4ea4 (build), ab2caf9e (F-2/F-3/F-4/F-5 remediation), c5ee36d6 (merge) all ancestors of master. PASS
2. `review-record-push-gate.sh --self-test` → **self-test: OK (1 skipped)** — the one non-executed assertion (17f backslash-path gating) is an HONEST platform guard (NTFS cannot host the fixture filename), loudly declared not-a-pass by the suite itself; the CG scenarios (incl. CG6, the F-2 push-scoping regression pin, referenced at gate :800) ran green. PASS
3. Class table complete at adapters/claude-code/config/review-class-table.json: harness (block-after-date, flip_date=2026-08-10, in-row corpus_measurement with the SAME-COMMIT-vs-PUSH conservatism caveat load-bearing — F-4 discharged), provenance-docs (exempt, named F-4 widening for operator-todo/SCRATCHPAD), other-docs + product (warn, flip_date null, in-row baselines), architecture_trigger_globs including hooks/*gate*.sh (F-3 discharged). PASS
4. Wire arrows: gate reads the table AS OF the pushed sha via `git show` (:635-636, :654-666 — same-push honoring in the config read itself); first-match-wins classifier (:738-743); reviewer tokens verified via review-chain-lib's rc_record_reviewer/rc_record_verdict reused verbatim (:804-819); gc_block wired (:876). PASS
5. Fidelity trail: T16-ordered remediation ab2caf9e landed all four findings; the fidelity re-check "CLEAR TO MERGE" is appended to the T16 record trail; the CI round-2 stat-order fix (_rrpg_mtime_epoch GNU/BSD reversal) landed BEFORE the 2026-08-10 flip arms — the override-marker path is exercised green in the current suite. PASS
6. ARMING ADJUDICATION (dispatch-directed): SCRATCHPAD.md HARD STOPS line, verbatim: "T18 flip 2026-08-10 armed" (elsewhere "T18 flip 2026-08-10 armed (baselines in-row)"). Determination: the armed flip is the GATE'S ENFORCEMENT posture transition — review-class-table.json harness class `"flip_date": "2026-08-10"`, WARN→BLOCK per the block-after-date posture — NOT the task checkbox. The task's own Prove-it 1 anticipates verification DURING the calibration window ("refused (WARN text during calibration window per config date)"), and nothing in the plan or evidence conditions task closure on the calendar. The checkbox therefore follows the NORMAL protocol — and under the normal protocol it stays OPEN for the independent reason below. NOT-TIME-ARMED
7. **Docs impact ("manifest entry updated; gate header contract") — FAIL.** Gate header contract: updated (:635-666 CONFIG block) ✓. Manifest entry: **NOT updated anywhere** — the review-record-push-gate entry's honest_status (7,605 chars) contains NO mention of the class-table extension (searched: class-table/T18/DEC-5/REQ-B9/review-class-table/2026-08-03 — zero hits; the sole "class" hit is unrelated prose), `grep -c "review-class\|class-table\|REQ-B9" manifest.json` → 0, and git history shows integration commits for T1+T3 (c3dae56c), T6 (422257c2), T11-T15 (c068e063) but NONE for T18. The mechanism was MERGED (c5ee36d6) and PUSHED (ancestor of the pushed 5eebe6e0) with no manifest delta — violating the plan's own dispatch-batching rule ("each mechanism's manifest delta lands in the SAME MERGE TRAIN as its mechanism… Never deferred past the push boundary (the HR-F9 class lives exactly there)"). The enforcement inventory currently UNDERSTATES the live gate's behavior — the exact claimed-vs-actual drift class manifest.json exists to prevent. FAIL

Runtime verification: command bash adapters/claude-code/hooks/review-record-push-gate.sh --self-test   # → self-test: OK (1 skipped — honest NTFS guard) (verifier re-run on master @ b2def5cf)
Runtime verification: file adapters/claude-code/config/review-class-table.json::"flip_date": "2026-08-10"
Runtime verification: command grep -c "review-class\|class-table\|REQ-B9" adapters/claude-code/manifest.json   # → 0 (the FAIL's mechanical basis; re-runnable)
Runtime verification: command git log --oneline --since=2026-08-02 -- adapters/claude-code/manifest.json   # → no T18 integration commit (ccfed944/c068e063/422257c2/c3dae56c only)

Verdict: FAIL
Confidence: 9
Reason: PROVEN (mechanism): the G3 class extension itself is built and verified — self-test OK re-run by this verifier (1 honestly-skipped NTFS assertion), class table complete with the F-2/F-3/F-4/F-5 remediation discharged and in-row conservative baselines, same-push honoring implemented in the config read itself, fidelity re-check CLEAR TO MERGE. PROVEN (gap): the task's Docs-impact obligation "manifest entry updated" is entirely unmet — zero class-extension trace in manifest.json, no T18 integration commit exists, and the mechanism is already pushed, which is the plan's own named HR-F9 failure class ("never deferred past the push boundary"). A mechanism whose enforcement-inventory entry understates its live behavior is the cardinal harness drift (constitution §10); the checkbox cannot flip until the inventory is true.
Gaps:
  - Manifest entry for review-record-push-gate not updated for the DEC-5 class-table extension (Class: HR-F9 manifest-deferred-past-push; Sweep query: `grep -c "review-class\|class-table\|REQ-B9" adapters/claude-code/manifest.json` → must become ≥1; Required generalization: orchestrator lands ONE commit updating the entry's honest_status — naming the class-table consumption, T18/REQ-B9, the flip_date=2026-08-10 arming, and the current self-test shape "OK (1 skipped)" with its re-derive command per the entry's own stated rule — then re-runs `manifest-check.sh` + `--gen-index`, then re-invokes this verifier for the one-check re-verification; every other check above already PASSES and will not be re-litigated)
  - Process note for the completion report (not blocking re-verification): the remediation round (ab2caf9e) never re-articulated its comprehension — batch-2 audit covered it via the T16 record trail; future remediation dispatches should re-articulate per Decision 020e.

## Task 14 — Verifier verdict (task-verifier)

EVIDENCE BLOCK
==============
Task ID: 14
Task description: REQ-B5+B7 template + checks: plan-template gains design-ref: header + per-task Implements:/Directives: + Review Chain section; plan-reviewer Checks 20-22 (20: design-ref required-when-triggered + design-reviews valid incl. anchor-at-HEAD; 21: every design MUST-REQ claimed by ≥1 task + Directives fields present; 22: chain records name agent+verdict+ledger-row) with G1 surface-trigger fire-rate measured over the plan corpus and recorded before any flip — Verification: full — Implements: REQ-B5, REQ-B7
Verified at: 2026-08-04T01:35:00Z
Verifier: task-verifier agent

Oracle: specified — the task's two Prove-it-works steps re-executed by this verifier (full suite run observing the five new-scenario verdicts; corpus measurement script re-run live); plus derived (pre-T14 blob) for the failure-attribution A/B below.

Comprehension-gate: PASS (confidence 8) — inline audit above ("Comprehension audit — batch #2"): granular per-rule API, drive-letter loop, live-fixture, and DESCOPE-honesty claims all re-verified; the NOT-covered "no task owns the G1 advisory gate" claim independently corroborated by the plan's own T16 Adjudication-1 In-flight entry.
Operator invariants: none registered (exit 3) — re-run 2026-08-04T00:15Z

Checks run (all re-executed by this verifier on master @ b2def5cf, 2026-08-04):
1. Ancestry: e58e480e (build) is an ancestor of master. PASS
2. Prove-it 1 — ALL FIVE new scenarios observed PASS in this verifier's own full suite run (twice — first run tail + full logged re-run): `(c20a) chainless-triggering-plan-fails-20: PASS` · `(c21b) missing-must-req-fails-21: PASS` (naming REQ-X1) · `(c22c) derived-record-fails-22: PASS` · `(c2022d) grandfathered-plan-skips-with-info: PASS` · `(c2022e) live-gated-pipeline-plan-passes-20-21-22: PASS` — the load-bearing live fixture: THIS plan, post-T25-edit, clears Checks 20-22 with zero blocking findings from the real repo root (rule-2 anchor movement since the T16 attestation rides the intentionally-non-blocking calibration window — expected lifecycle staleness, exactly as the check's own comment states). PASS
3. SUITE-GLOBAL EXIT ADJUDICATED — the full suite exits 1 via THREE scenarios, ALL Check 19 (ee3 no-WARN-emitted, ee4 grandfather-bypass, ee7 no-UNDECIDABLE-warn), NONE of them T14's: (a) T14's diff touches Check 19 only in comments and a `_if_root` perf reuse (verified via `git show e58e480e`); (b) A/B PROVEN pre-existing — this verifier reconstructed the ee3 fixture standalone and ran BOTH the pre-T14 blob (`git show e58e480e~1:…plan-reviewer.sh`) and current master against it: BYTE-IDENTICAL outcome (Check 3 Scope IN/OUT findings fire; no Check-19 WARN emitted) on both sides — the same git-stash-A/B attribution method the T4 verdict used; (c) the failures match T8's recorded observation ("plan-reviewer… failures observed, not root-caused") — root cause now isolated (ee fixture's Scope lacks IN:/OUT: so Check 3 pollutes the Check-19 scenarios) and filed as an nl-issue this pass, owner: the T8/T21 triage population. PASS (not T14's defect)
4. Prove-it 2 — corpus measurement RECORDED WITH THE NUMBER: config/design-ref-gate.json `corpus_measurement` (in-data, HR-F7 style): measured_date 2026-08-03, surface-trigger 146/298 = **49.0%** (+ keyword-trigger 27.0% reused from the Check-17 study); re-run LIVE by this verifier via `measure-design-ref-surface-trigger.sh` → **148 fired / 304 files = 48.7%** (corpus grew by 6 plans since measurement — consistent). Both numbers now also recorded here, in the evidence file, per the Prove-it letter. Measurement precedes any flip: landing_date 2026-08-04, flip_date 2026-08-11 (future). PASS
5. Template fields: plan-template.md carries `design-ref:` (:181 with n/a-escape), `## Review Chain` (:207 with per-entry contract), per-task `Implements:`/`Directives:` (:501); live sync `~/.claude/templates/plan-template.md` → **byte-identical** (diff empty). PASS
6. Wire arrows: Checks 20/22 call the granular review-chain-lib API — `rc__base_token` (:4049), `rc_rule1` (:4054), `rc_rule2` (:4059) — exactly the plan's corrected Wire-checks line (M-3 one-parser rule honored, no second implementation); Check 21 parses the `## Requirements` REQ table from the design-ref'd file; Check 17 marked superseded-for-keyword-triggering in the same commit. PASS
7. Docs impact: planning.md compact gains the fields bullet (:9); planning-full.md gains "The Review-Chain fields" subsection (:141) — the pre-existing Files-map gap disclosed and closed via the plan's In-flight entry. PASS

Runtime verification: command bash adapters/claude-code/hooks/plan-reviewer.sh --self-test   # → c20a/c21b/c22c/c2022d/c2022e ALL PASS; suite exit 1 attributable solely to pre-existing Check-19 ee3/ee4/ee7 (A/B-proven vs e58e480e~1; nl-issue filed)
Runtime verification: command bash adapters/claude-code/scripts/measure-design-ref-surface-trigger.sh   # → corpus 304 files, 148 fired, 48.7% (verifier live re-run; config records 146/298=49.0% @ 2026-08-03)
Runtime verification: command diff adapters/claude-code/templates/plan-template.md ~/.claude/templates/plan-template.md   # → empty, byte-identical (verifier re-run)
Runtime verification: file adapters/claude-code/config/design-ref-gate.json::"surface_trigger_fire_rate_pct"
Runtime verification: file adapters/claude-code/templates/plan-template.md::design-ref:

DEPENDENCY TRACE
================
Step 1: plan-template carries design-ref/Review Chain/Implements/Directives fields
  ↓ Verified at: templates/plan-template.md:181/:207/:501 + live-sync diff empty
Step 2: plan-reviewer Checks 20-22 parse those fields via Task 1's ONE lib (granular API)
  ↓ Verified at: plan-reviewer.sh:4049-4059 (rc__base_token/rc_rule1/rc_rule2) + c20a/c21b/c22c green
Step 3: flip/grandfather dates live in data, measurement recorded before flip
  ↓ Verified at: config/design-ref-gate.json (landing 2026-08-04, flip 2026-08-11, corpus_measurement in-row) + live re-measurement 48.7%
Step 4: the real plan (this file's plan) clears the checks as the load-bearing fixture
  ↓ Verified at: c2022e PASS observed in this verifier's own run from the real repo root

Verdict: PASS
Confidence: 8
Reason: PROVEN: all five new scenarios observed green in this verifier's own full suite runs (twice), the live-plan fixture passing post-T25 with the anchor-staleness riding the intended calibration window; the corpus measurement re-derived live (48.7% vs the recorded 49.0% on a corpus 6 files smaller) and recorded here per the Prove-it letter; template fields verified in-file and byte-identical live; wire arrows traced to the granular lib API. The suite-global exit-1 is PROVEN not-T14 by a pre/post-blob A/B on a reconstructed fixture (identical failure both sides — pre-existing Check-19/Check-3 fixture drift, filed as nl-issue, owned by the T8/T21 triage population, same accepted-attribution method as the T4 verdict). Confidence 8 not 9: the builder's own evidence narrative was capture-lost (recovered articulation only), and the named suite's global exit remains red for reasons outside this task — flagged, filed, and attributed rather than ignored.

Verdict: PASS
Confidence: 9
Reason: PROVEN: the writer's full contract re-observed directly — 140/140 suite plus a verifier-constructed live probe producing exactly one well-formed 5-field row (and zero rows on malformed input, exit 0), the rule-3 round-trip and wrong-ref rejection re-run green, the landing-date boundary confirmed in the lib config, and the live ledger's real rows inspected. The task=T7 spelling defect is adjudicated an orchestrator-input defect (check 8): the mechanism's ledger schema never carries task ids and the writer's faithful-pass-through contract is honored; the consumer caught the bad input at the right layer. NAMED RESIDUAL (non-blocking, orchestrator follow-up): the Docs-impact letter — a one-line dispatch-ledger note in orchestrator-pattern.md itself — is unmet in that specific file (the note lives in the manifest entry, the generated doctrine/INDEX.md row, and planning-full.md); T17/T20 are about to touch the same doctrine file — fold the one-liner into that train and record it in the completion report.
## Task 17 — G2 live: PreToolUse gate + THE THREE-VARIANT DEMO (REQ-B8) — Verification: full

- Builder: plan-phase-builder (sonnet), SERIAL dispatch on the live branch (no worktree isolation
  for this build), after Task 16's substantive landing (commit dbd6647f — plan-reviews entry with
  plan-blob 0771581b — though T16's own checkbox remained unflipped at dispatch time; see the
  "Honest gaps" and Decisions Log entry below for what that turned out to mean in practice).
- What landed: `hooks/dispatch-chain-gate.sh` gains a no-args PreToolUse enforce mode
  (`_dcg_gate`, :296) alongside the unchanged Task-1 `--check` mode: reads a Task|Agent dispatch
  event (CLAUDE_TOOL_INPUT or stdin, model-pin-gate.sh:156-167's extraction pattern reused
  verbatim); classifies `subagent_type` against `config/model-policy.json`'s `category:"build"`
  agents (`_dcg_is_build_type`, :123 — dynamic, not a hardcoded pair); derives a plan slug from
  an NL-ATTRIBUTION `plan=` field (`_dcg_attributed_slug`, :193 — a REIMPLEMENTATION of
  workstreams-emit.sh's `_extract_nl_attribution` anchor rule, not a `source`, because that file
  has no direct-execution guard and killed the sourcing shell when tested live — see the function's
  own header comment for the verification command) with a same-regex prompt-text fallback
  (`_dcg_extract_plan_slug`, :162); resolves the plan against the session cwd's git toplevel,
  `cd`s into it, and validates the chain via `rc_validate_chain "docs/plans/$slug.md"` — a
  REPO-ROOT-RELATIVE path, not absolute (this exact bug, and the fix, are in "Honest gaps" below);
  applies the F-4 gate-ordering rule (`_dcg_chain_unparsed`, :228 — grandfather consulted ONLY
  when no chain parses at all, never when a chain parses but fails a rule) against the
  install-generated `config/g2-grandfather-slugs.txt` (300 slugs: every top-level
  `docs/plans/*.md` + `docs/plans/archive/*.md` at generation time, `_dcg_grandfathered`, :138);
  and implements the M-7 evasion heuristic (non-build subagent_type referencing a `docs/plans/`
  path → workaround-sensor row, never a block).
- Wiring: `settings.json.template` gains its own `"matcher": "Task|Agent"` block calling
  `bash ~/.claude/hooks/dispatch-chain-gate.sh` with no args, placed AFTER model-pin-gate.sh's
  block and BEFORE workstreams-emit.sh's `--on-builder-dispatch` block — order-safety rationale
  (both gates read-only on tool_input) stated inline in dispatch-chain-gate.sh's own header
  (the "WIRING" section) since JSON cannot carry a comment.
- `--self-test` extended: 40 passed, 0 failed (was 6/6 at Task 1) — the two original --check
  scenarios (chainless/valid-chain, unchanged) plus 34 new PreToolUse scenarios covering: THE
  THREE DEMO VARIANTS as executable fixtures (a throwaway git repo, mktemp+git init, mirroring
  review-chain-lib.sh's own self-test convention); grandfathered-slug ledgered-WARN-and-proceed;
  valid-chain silent pass; research-type dispatch fully untouched; the M-7 heuristic; test-writer
  vs. plan-phase-builder underivable-slug divergence (WARN+ledger vs. BLOCK); the Mi-5 no-repo
  WARN-pass; and non-spawn-tool no-op. Every `gc_escape_used` call in the self-test is sandboxed
  via `HARNESS_SELFTEST=1` + `WORKAROUND_SENSOR_LEDGER_PATH` (never touches the real machine's
  workaround-sensor ledger); every ledger-dependent scenario pins `RC_LEDGER_LANDING_DATE`/
  `RC_LEDGER_PATH` so real wall-clock time can never flip a scenario's exemption state.
- **THE LIVE TRANSCRIPTS (the D-15 acceptance-bar artifacts):** generated by running the gate
  binary directly from the real repo root (this checkout, not a throwaway one) against three
  real (temporary, NEVER `git add`ed, deleted immediately after capture — `git status --porcelain`
  confirmed clean post-run) fixture files under `docs/plans/`/`docs/reviews/`, captured verbatim
  (command line + full stdout/stderr + exit code) into
  `docs/plans/gated-pipeline-master-2026-08-evidence/t17-demo-variant-{1,2,3}.txt`:
  - **Variant (i)** — plan-phase-builder, chain-less new plan, WITH an NL-ATTRIBUTION header →
    exit 2, all four `[GATE:*]` fields, `[FAIL] chain-presence: no ## Review Chain section`.
  - **Variant (ii)** — SAME plan, prompt carries NO NL-ATTRIBUTION line anywhere → exit 2,
    IDENTICAL block shape (subagent_type keying proven independent of attribution presence, H1).
  - **Variant (iii)** — a chain entry naming `harness-reviewer`, well-formed on rules 1+2, with
    RC_LEDGER_PATH pointed at an empty scratch ledger (zero rows of that type) → exit 2, message
    reads "...'s Review Chain fails validity: ... rule3: FAIL: no dispatch-ledger row..." —
    textually distinct from variants (i)/(ii)'s "has no ## Review Chain block" framing, proving
    the gate distinguishes "no chain" from "chain present but invalid" (the exact distinction
    F-4's grandfather-ordering rule depends on).
  - All three: exit code 2 (BLOCK), zero variants passed through — the plan's own Intended
    Functionality pass/fail item 1 ("All three REQ-B8 demo variants produce a block ...  zero
    variants pass through") holds.
- **Performance — MEASURED, and the design's <300ms budget is MISSED on this machine (PROVEN, not
  modeled)**: `date +%s%N`-bracketed real invocations, 3 runs each, this checkout
  (Windows/MSYS2 Git Bash):
  - Fully untouched (non-build subagent_type, no docs/plans/ reference): **567-586 ms**.
  - Underivable-slug plan-phase-builder (BLOCK, no chain touched at all): **743-952 ms**.
  - Chain-less real plan (the P-39/demo-variant shape, one `git rev-parse` + `rc_chain_present`
    short-circuit): **787-935 ms**.
  - **The live `gated-pipeline-master-2026-08.md` plan itself (3 chain entries: 2 design-reviews +
    1 plan-reviews) via a real `plan-phase-builder` dispatch event: 5.7-9.6 SECONDS** — roughly
    20-30x the stated budget. Isolated: `rc_validate_chain` alone on this plan measured 4.9s;
    `rc_rule3` alone (one entry, EXEMPT short-circuit, the REAL machine ledger at 340 rows) measured
    ~466ms.
  - Root cause (traced, not guessed): review-chain-lib.sh's rc_rule2/rc_rule3 spawn a `git`
    subprocess PER RULE PER ENTRY (rule 2: one `git hash-object`; rule 3: one `git log --follow
    --find-renames=100%` for the pre-ledger-exemption check, even when the exemption short-circuits
    before any ledger scan) — isolated single-call baselines on this machine: bare `bash -c true`
    121ms, one `jq` call 158ms, one `git rev-parse` 141ms, one `git hash-object` 184ms, one `git log
    --follow` **554ms**. A 3-entry chain therefore pays roughly 6-9 subprocess spawns minimum
    (2-3 per entry), and Windows/MSYS2 process-spawn overhead (already documented elsewhere in this
    estate as materially higher than Linux/macOS) compounds linearly with entry count — this is
    Task 1's existing per-rule design (review-chain-lib.sh, already task-verifier PASS), not
    anything Task 17 introduces; T17 only calls the SAME `rc_validate_chain` the --check mode
    already called. NOT independently re-timed by a verifier or on a second (non-Windows) machine —
    flagged, not fixed, in Honest gaps: this is very plausibly a Windows-specific number, and the
    fix (if one is warranted) is a review-chain-lib.sh change, out of T17's file scope.
- Manifest delta (report-only, per this task's constraints — no manifest.json edit performed):
  `dispatch-chain-gate` entry: `events: []` → `["PreToolUse"]`; `wired_template: false` → `true`;
  `selftest` stays `true` (count 6→40); `honest_status` should read (paraphrase, not the literal
  final string): "LIVE: PreToolUse Task|Agent, wired in settings.json.template. subagent_type-keyed
  per model-policy.json build category (dynamic, not hardcoded). Grandfather list
  config/g2-grandfather-slugs.txt (300 slugs, generated 2026-08-03 from extant docs/plans/*.md +
  docs/plans/archive/*.md). Self-test 40/40 incl. the three D-15 demo variants as executable
  fixtures. Live transcripts: docs/plans/gated-pipeline-master-2026-08-evidence/t17-demo-variant-
  {1,2,3}.txt."; consider adding `"adapters/claude-code/config/g2-grandfather-slugs.txt"` and
  `"adapters/claude-code/config/model-policy.json"` to `jit_triggers.paths` (both are now real
  runtime dependencies of this gate, not just the lib).

### Task 17 — Comprehension Articulation (builder-authored, per Decision 020d; diff: <this build's
commit(s), cited by SHA in the builder's session report>)

#### Spec meaning

Task 17 (REQ-B8) lands G2's FULL form on top of Task 1's proven skeleton: a PreToolUse `Task|Agent`
gate that keys on `subagent_type` against model-policy.json's build category, "regardless of
prose" (design H1) — an NL-ATTRIBUTION `plan=` field only REFINES the derived slug, it never gates.
For a build-category dispatch, the plan slug (from attribution or a `docs/plans/<slug>.md` prompt
scrape) is resolved against the session cwd's git toplevel; the chain VALIDATES FIRST
(fidelity-review F-4, binding: `rc_validate_chain` runs unconditionally before any grandfather
check); the grandfather list (install-generated, a static slug file) is consulted ONLY when no
chain parses at all, never when a chain parses but fails a rule; a plan-phase-builder with an
underivable slug BLOCKS (the agent exists only for plan work) while a test-writer WARNs+ledgers
(ad-hoc use is legitimate); and the whole thing is proven via THREE adversarial demo variants
(chain-less BLOCKED, chain-less-without-attribution STILL BLOCKED, never-dispatched-reviewer chain
FAILS validity) captured as live transcripts — the plan's own D-15 acceptance bar.

#### Edge cases covered

- **The H1 variant, executed twice with one variable changed**: variants (i) and (ii) are the
  IDENTICAL chain-less plan dispatched by the IDENTICAL subagent_type, differing ONLY in whether
  the prompt carries an NL-ATTRIBUTION header — both produce byte-identical BLOCK framing
  (`t17-demo-variant-1.txt` vs `t17-demo-variant-2.txt`, both "has no ## Review Chain block"),
  directly proving subagent_type keying is independent of attribution presence, not merely
  asserted.
- **F-4 gate-ordering, both directions**: a chain-less plan on the grandfather list proceeds with
  a ledgered WARN (`_dcg_grandfathered` reached); a chain-PRESENT-but-invalid plan (variant iii)
  is NEVER even offered to `_dcg_grandfathered` — `_dcg_chain_unparsed` (dispatch-chain-gate.sh:228)
  gates entry to that branch, and the self-test's "demo-iii-message-is-not-the-chain-less-framing"
  scenario asserts the two failure classes produce textually distinct messages, not just distinct
  exit codes.
- **Role-divergence on underivable slug**: plan-phase-builder BLOCKS (self-test
  "plan-phase-builder-underivable-slug-blocked-rc2"), test-writer WARNs+ledgers
  ("test-writer-underivable-slug-warns-rc0" + a real `bypass_kind:"underivable-slug"` row) — same
  input shape, deliberately different verdicts per the design's stated asymmetry.
- **Mi-5 no-repo**: a session cwd outside any git repository (self-test's `$NOGIT` scenario) WARNs
  and proceeds rather than erroring or blocking — `git rev-parse --show-toplevel` failure is the
  trigger, verified via a real non-git tmp directory, not mocked.
- **The M-7 evasion heuristic, both branches**: a non-build subagent_type WITH a `docs/plans/`
  reference in its prompt writes a workaround-sensor row and still proceeds (never blocks — the
  design states this is measurement, not enforcement); a non-build subagent_type with NO such
  reference (the "research-dispatch-untouched" scenario) writes ZERO ledger rows, asserted via a
  before/after line-count diff on the sandboxed ledger file, not merely an exit-code check.
- **CRLF on Windows, caught live, not theoretical**: `config/model-policy.json`'s `jq -r` output
  carries `\r\n` line endings on this checkout; an un-stripped `read -r` loop variable
  ("plan-phase-builder\r") silently mis-classified every build-category dispatch as non-build,
  making variants (i)–(iii) all fall through to the M-7 branch instead of blocking — caught by the
  self-test itself (3 scenarios FAILing with the exact wrong-branch symptom) before any commit,
  fixed with the same `${bt%$'\r'}` strip model-pin-gate.sh's own frontmatter readers already use
  for the identical platform reason (dispatch-chain-gate.sh:123-137, comment cites the discovery).
- **artifact_ref path-form mismatch, caught live, not theoretical**: the first working version
  passed an ABSOLUTE plan path to `rc_validate_chain`, so rule 3's `artifact_ref` never matched a
  real ledger row's repo-root-relative `docs/plans/<slug>.md` form — every genuinely valid chain
  spuriously failed rule 3. Caught by the "valid-chain-plan-silent-pass" self-test scenario
  (BLOCKED instead of PASS); fixed by `cd`ing into the resolved toplevel and passing a relative
  path from there on (dispatch-chain-gate.sh:354-381), matching workstreams-emit.sh's real writer
  convention exactly.

#### Edge cases NOT covered

- **Two simultaneous build-category dispatches racing on the SAME plan** — not exercised; G2 is a
  stateless per-invocation decider (Behavioral Contracts: "Retry semantics... no gate holds
  locks"), so this is presumed safe by that contract, not independently proven under concurrency.
- **A plan slug that collides between a real `docs/plans/` file and a grandfather-list entry whose
  underlying file has since been DELETED** (not merely archived) — the grandfather check is a pure
  string-membership test against the slug list; it does not re-verify the listed file still
  exists. Practically harmless (a deleted plan can never be dispatched against — `rc_validate_chain`
  would hit the same "no such file" → chain-less path regardless of grandfather status), but not a
  scenario this self-test constructs explicitly.
- **The `--check` mode's OWN behavior against a plan whose slug happens to collide with a
  PreToolUse-mode fixture** — the two modes are independently self-tested but never invoked
  back-to-back against the identical file in one scenario (no evidence of cross-mode interference,
  but also no assertion against it).
- **A `docs/plans/<slug>.md` reference inside a code fence in the dispatch prompt** (the same
  fence-guard the NL-ATTRIBUTION anchor applies) is NOT applied to `_dcg_extract_plan_ref`'s
  bare-scrape fallback — only the attributed-slug path is fence-guarded. A quoted
  `docs/plans/foo.md` mention inside a fenced code block in a prompt would still be scraped as a
  real reference by the fallback path. Not exercised by any self-test scenario; a real but
  narrower residual than the already-named M-7 evasion class (this one could cause an
  OVER-cautious BLOCK/WARN on a prompt merely discussing a plan path, not an evasion).
- **Timing budget is MISSED, not merely under-measured**: the design's Behavioral Contracts state
  "<300ms budget, measured in T17 evidence"; this task's own measurement (see the build-log entry
  above) shows every path exceeds it on this machine, and the multi-entry live-plan path misses it
  by roughly 20-30x. This is NOT re-timed on a second (non-Windows) machine, so "is this a
  Windows-only artifact of MSYS2 process-spawn cost, or a real cross-platform budget miss in
  review-chain-lib.sh's per-rule-per-entry git-subprocess pattern" is unresolved — named, not
  fixed, and not silently downgraded to "honored qualitatively" (the phrasing this entry originally
  carried before the real measurement was taken — corrected in place, not left standing).

#### Assumptions

- `git rev-parse --show-toplevel` run with the hook's INHERITED cwd (no explicit `-C` flag)
  correctly reflects "the session's cwd" at dispatch time — true for every interactive/orchestrator
  session observed on this machine; unverified for any execution context where a hook's cwd might
  differ from the dispatching session's actual working directory (not identified as a real gap,
  just not independently confirmed).
- The grandfather list, generated ONCE at this commit from `docs/plans/*.md` + `docs/plans/archive/
  *.md` (top-level only, no recursion), is treated as static for this cycle — REQ-C2's estate drain
  is the ONLY sanctioned shrink mechanism; nothing in this task adds a re-generation trigger, so a
  plan slug removed from `docs/plans/` after this commit (e.g. archived properly) stays
  grandfathered until someone re-runs the documented regeneration command by hand.
- `config/model-policy.json`'s two build-category agents (plan-phase-builder, test-writer) are the
  complete build-category population for this cycle; `_dcg_build_types` reads it dynamically so a
  THIRD build-category agent added later is covered without a code change — assumed, not tested
  (no fixture constructs a third build-category type).
- The live-plan chain-validity finding (see the Decisions Log entry above and "Honest gaps" in the
  builder's session report) — that this plan's OWN Review Chain currently FAILs (not merely WARNs)
  due to a stale unanchored bootstrap entry T16 left in place — is assumed to be a genuine,
  previously-undiscovered defect surfaced by this task's own direct testing, not a
  misunderstanding of the lib's semantics; the fix (removing the entry) is verified to flip the
  verdict to WARN (never-blocking) via direct `rc_validate_chain` re-invocation, not merely
  asserted.

## Task 19 — Comprehension Articulation (recovered verbatim from the builder's own subagent session transcript; builder af0e1f9e595286a95; merged as 5eebe6e0, builder-cited worktree commit f01b6eff)

Recovered from `...\subagents\agent-af0e1f9e595286a95.jsonl` by task-verifier batch #3, same
source-3 convention as the Forensic recovery section above (extracted via `jq -r
'.message.content[]? | select(.type=="text") | .text'`, located by grepping for "Comprehension
Articulation" — genuinely verbatim, not reconstructed). The builder's own trailing "Honest gaps"
subsection is reproduced beyond the required four, marked as such:

**Spec meaning:** REQ-B10 (design `docs/designs/gated-pipeline-master-2026-08-03.md:305`) requires a no-addendum lint riding the existing hygiene-scan pre-commit invocation, with the M-9-narrowed pattern: `Addendum`/`Update:` headings rejected in `docs/designs/**`+`docs/plans/**` with `docs/plans/archive/**` excluded from scope entirely; `Round [0-9]` rejected in `docs/designs/**` only; case-insensitive; escape = standard fresh-waiver, ledgered. Plus the golden case: fold the considerations brief's addenda into its body. I implemented this as `check_addendum_lint()` (`harness-hygiene-scan.sh:1254`) with scope helpers `_hhs_in_designs()`/`_hhs_in_plans_scoped()` (`:1211`,`:1219`) and shared emitter `_hhs_addendum_scan()` (`:1231`), invoked as Layer 3 in the main scan loop (`:1522`) right after Layer 2 heuristics — inside the SAME per-file loop that already gates on `is_exempt()`/waiver, so the escape mechanism required zero new plumbing (the pre-existing waiver check at the top of the loop short-circuits before any layer runs).

**Edge cases covered:** case-insensitivity in both directions (uppercase `## ADDENDUM` in a plan, lowercase `### update:` in a design — self-test A3/A4); the archive-exclusion boundary tested with the verbatim historical hit; the plans-vs-designs Round-scope boundary tested with two verbatim in-plan Round headings that must NOT fire; body-prose mentions of "addendum"/"round 2" (non-heading) that must NOT fire (A7, proves the `^#{1,6}[[:space:]]` anchor actually gates on heading-ness, not substring presence); the waiver escape suppressing an addendum-lint match identically to a denylist match, with ledger-row verification.

**Edge cases NOT covered:** headings with unconventional spacing/atx-closing (`## Addendum ##`) — not tested, though the anchor pattern would still match since it only anchors the opening `#`s; a heading matching BOTH sub-patterns in one design file (line 225 of the golden case, pre-integration, exercised this incidentally — 2 separate match lines emitted from 1 heading — but I never wrote an explicit assertion for "one heading, two labels"); setext-style headings (`Addendum\n=====`) are NOT caught (ATX-only per the design's own "heading" framing — a residual gap, not flagged by the design text either).

**Assumptions:** (1) That "add the heading-pattern check as a sibling" in my dispatch prompt authorizes implementing directly in `harness-hygiene-scan.sh` rather than the plan's alternate "`-body.sh` (or its body split)" phrasing — I treated the explicit builder instruction as authoritative over the design's softer alternative, and updated the plan's Wire checks block in the same commit to match (`gated-pipeline-master-2026-08.md` Task 19). (2) That "the 5 measured legitimate hits" in the design text refers to heading-level Round-N hits total (2 golden-case + 3 in-plan) — confirmed by direct re-measurement, not assumed from prose alone. (3) That the editorial integration should REPLACE contradicted content in place (not preserve-both old-and-corrected) per "change only its location and stale contradicted statements" — I kept the WSL2/platform-shift comparative analysis in §3/§4.4 as valid historical rationale (unchanged) while correcting only the downstream DECISION artifacts (§5 D1/D4, §6 staging).

*(Builder's own trailing subsection, reproduced verbatim for completeness though not part of the required four:)*

**Honest gaps** (builder's heading): Stage-1/3/4 LOE bands in the restaged §6 table are carried forward from the pre-Round-3 estimates and explicitly flagged as unestimated for the corrected (Windows-native, no-plane) shape — the operator never re-priced them at Round 3, and I did not fabricate new numbers. Setext-heading addenda (rare, unused in this corpus) would slip past the lint — not a measured false-negative, just an unexercised input class. No doctor-side gate-message-field lint currently exists to mechanically verify the WHAT/WHY/FIX/ESCAPE fields (invariant 13/R3.4.1 of the very design I just edited) — that's a different, undispatched task; my self-test's own "msg-fields" scenario is the only check exercised, and it passed unchanged since I only appended text within the existing four fields, not restructured them.

## Comprehension audit — batch #3 (T17/T19/T20; executed inline by task-verifier, 2026-08-04T02:45Z)

Method note (per §1, same convention as the batch #2 audit above): this verifier context has no
subagent-dispatch tool; the comprehension-reviewer protocol was executed INLINE — Stage 1
paraphrase-vs-spec, Stage 2 citation resolution against the merged blobs, Stage 3
NOT-covered/assumptions genuineness. T23/T24 are Verification: contract — Step-0 per-level
routing, no comprehension gate (T2/T6/T10 precedent).

- **Task 17 — PASS (confidence 8), with an FM-023-adjacent finding the verdict below acts on.**
  Stage 1: spec paraphrase is faithful and complete (H1 subagent-type keying, F-4
  chain-validates-first letter, role-divergent underivable-slug handling, the three-variant
  acceptance bar). Stage 2: all cited functions resolve — `_dcg_is_build_type` CRLF strip,
  `_dcg_grandfathered`, `_dcg_attributed_slug`, `_dcg_chain_unparsed`, `_dcg_gate`, the
  cd-toplevel/relative-artifact_ref region — at a uniform +4-6 line offset from the cited
  numbers (:296→:302 etc.), attributable to the DISCLOSED orchestrator merge-train amendment
  (opaque-hash conversion adds comment lines above `_dcg_grandfathered`); semantics unchanged,
  verified against the merged bytes. Stage 3: NOT-covered is exemplary — the timing-budget miss
  is named with the corrected-in-place admission ("not silently downgraded to 'honored
  qualitatively'"), the fence-guard fallback gap and concurrency non-proof are genuine.
  FM-023-adjacent finding: the builder's (and amendment's) mental model of "install" collapsed
  to "this commit IS the install," while the harness's actual install pipeline (install.sh dir
  loop + session-start-auto-install SYNC_SUBDIRS) never deploys `config/` to `~/.claude/` —
  the script-location-relative config resolution the gate deliberately chose therefore resolves
  to a directory that never receives its two config dependencies on any installed machine. Not
  contradicted by any articulated claim, but not articulated either; surfaced by this
  verifier's installed-layout A/B probe (see the Task 17 verdict below).
- **Task 19 — PASS (confidence 8).** Articulation recovered verbatim (block above). Stage 2:
  citations resolve EXACT at current master — `check_addendum_lint` :1254, `_hhs_addendum_scan`
  :1231, helpers :1211/:1219, Layer-3 invocation :1522 (file unchanged since merge 5eebe6e0).
  Stage 1 faithful incl. assumption (1)'s main-file-vs-body-split reconciliation, which the
  plan's own T19 Wire-checks line already records. Assumption (2)'s "5 measured hits = 2
  golden-case + 3 in-plan Round" independently corroborated by this verifier's own corpus count
  (3 Round-N headings across 2 non-archived plans + the golden case's 2 pre-integration
  headings). Stage 3 genuine: the setext-heading gap is real (the pattern anchors ATX opening
  hashes only), stated without minimization.
- **Task 20 — PASS (confidence 8).** Stage 2 behavioral claims re-verified at the merged bytes:
  the ONE-JSON-object assertion is a real `jq -s 'length' == 1` on raw stdout
  (doctrine-jit.sh:842); the fork-avoidance global chain (`DR_REGISTER_WALK_OUT`,
  `_DJ_REGISTER_BODY`) exists as described; the "NOT a general JSON parser" limitation is
  disclosed in the lib's own module header (directives-register-lib.sh:374); the OD-021
  carriage-WARN drift finding re-observed LIVE by this verifier's own re-run of
  `dispatch-directives.sh <plan> 20`. Stage 3 genuine (single-line-surfaces parse limitation,
  no-idle-machine timing number, extract_tagged_files last-parenthetical convention). The F-5
  timing claim was independently re-measured by this verifier (30ms avg, Task 20 verdict below).

## Task 18 — Verifier verdict (task-verifier, batch #3 RE-CHECK — supersedes the batch #2 FAIL; check 7 only, per the batch #2 remedy's own scope)

EVIDENCE BLOCK
==============
Task ID: 18
Task description: REQ-B9 G3 extension: review-record-push-gate.sh consumes the DEC-5 class-table config (harness class → BLOCK by config date; provenance-docs EXEMPT; product/other → WARN with per-class baselines measured from the calibration week's real push history); same-push record-honoring stated + tested — Verification: full — Implements: REQ-B9
Verified at: 2026-08-04T02:48:00Z
Verifier: task-verifier agent

Oracle: specified — the batch #2 FAIL's own remedy contract (manifest honest_status amendment naming class-table consumption, T18/REQ-B9, flip_date arming, self-test shape with re-derive command; manifest-check + --gen-index re-run) re-observed directly on master @ f3fffe8e.

Comprehension-gate: PASS with staleness note (confidence 7) — batch #2 inline audit stands unchanged (single-round articulation predates the ab2caf9e remediation; F-2 caught and discharged via the T16 record trail).
Operator invariants: none registered (exit 3) — ask-registry.sh invariant-check --plan-slug gated-pipeline-master-2026-08, re-run 2026-08-04T02:40Z

Checks run (check 7 re-litigated per the batch #2 remedy; checks 1-6 stand from batch #2):
7. Docs impact ("manifest entry updated") — NOW MET. (a) grep count of class-table/REQ-B9 in manifest.json → 1 (was 0 at batch #2). (b) The review-record-push-gate entry's honest_status carries the amendment verbatim: "T18/REQ-B9 CLASS-TABLE AMENDMENT (2026-08-03, verifier batch #2 remedy -- this sentence IS the T18 manifest integration, HR-F9 class)" — naming the DEC-5 class-table consumption (config/review-class-table.json), F_CHANGED-scoped reviewer-token matching (F-2) with the CG6 pin, hooks/*gate*.sh glob coverage (F-3), in-row corpus_measurement baselines (F-4), the harness-class WARN→BLOCK flip armed 2026-08-10 (flip_date in-row), AND the self-test shape "self-test: OK (1 skipped)" with its honest-NTFS-skip explanation and re-derive command — every element the batch #2 remedy required. (c) Integration commit exists: f3fffe8e touches manifest.json (+56/-13) AND doctrine/INDEX.md (the --gen-index regen); commit message names the amendment explicitly. (d) manifest-check re-run live by this verifier → GREEN — 165 entries, 127 hooks covered, 0 warn (the batch #2 session-heartbeat RED also resolved via the same commit's claim correction). (e) Staleness guard: git log b2def5cf..HEAD on the gate + class table → EMPTY — both byte-unchanged since batch #2's green full self-test re-run, so that run stands. PASS

Runtime verification: command grep -c "class-table\|REQ-B9" adapters/claude-code/manifest.json   # → 1 (was 0; the batch #2 FAIL's mechanical basis, now discharged)
Runtime verification: command bash adapters/claude-code/scripts/manifest-check.sh   # → GREEN — 165 entries, 127 hooks covered, 0 warn (verifier re-run on master @ f3fffe8e)
Runtime verification: file adapters/claude-code/manifest.json::T18/REQ-B9 CLASS-TABLE AMENDMENT
Runtime verification: command git log --oneline b2def5cf..HEAD -- adapters/claude-code/hooks/review-record-push-gate.sh   # → empty (gate unchanged since the batch #2 green self-test)

Verdict: PASS
Confidence: 9
Reason: PROVEN: the single FAIL basis from batch #2 (manifest entry silent on the class-table extension — HR-F9 manifest-deferred-past-push) is discharged exactly per the remedy contract: the amendment sentence is live in the entry's honest_status with all required elements, landed in integration commit f3fffe8e alongside the --gen-index regeneration, and manifest-check re-run GREEN by this verifier. The gate and class table are byte-unchanged since batch #2's own green re-run of the full self-test, so checks 1-6 stand as recorded. The enforcement inventory now states the live gate's true behavior — the §10 claimed-vs-actual condition that blocked the flip is resolved.

## Task 19 — Verifier verdict (task-verifier)

EVIDENCE BLOCK
==============
Task ID: 19
Task description: REQ-B10 no-addendum lint (in hygiene-scan; narrowed pattern per M-9 + harness delta: Addendum/Update: in designs+plans with docs/plans/archive/** EXCLUDED from scope entirely; Round [0-9] in docs/designs/** ONLY; case-insensitive; fresh-waiver escape, ledgered; the 5 measured legitimate hits as verbatim negative fixtures) + the considerations brief's addenda integrated into its body (golden case executed) — Verification: full — Implements: REQ-B10
Verified at: 2026-08-04T02:52:00Z
Verifier: task-verifier agent

Oracle: specified — the task's two Prove-it-works steps, re-exercised directly by this verifier including a LIVE RED PROBE the suite did not run (a violating fixture created in the real repo, scanned, blocked, deleted — the same never-staged convention the T17 transcripts use); plus derived (pre-integration golden case) — fixtures A1/A2 are the brief's own pre-integration headings verbatim, i.e. the lint demonstrably FAILS the exact bytes the golden case removed.

Comprehension-gate: PASS (confidence 8) — inline audit above ("Comprehension audit — batch #3"): articulation RECOVERED VERBATIM from the builder's own subagent transcript (agent-af0e1f9e595286a95.jsonl, source-3 convention, provenance-labelled block above); citations resolve EXACT at current master; the "5 measured hits" arithmetic independently corroborated by this verifier's own corpus count.
Operator invariants: none registered (exit 3) — re-run 2026-08-04T02:40Z

Checks run (all re-executed by this verifier on master @ f3fffe8e, 2026-08-04):
1. Ancestry: 5eebe6e0 (build, merged form of builder-cited f01b6eff) is an ancestor of master. PASS
2. Full suite re-run: harness-hygiene-scan.sh --self-test → "self-test: OK" with ZERO FAIL lines (the Layer-3 A1-A8 and waiver W1-W6 assertions emit fail-only; A8 additionally asserts the waiver-honored addendum match writes a workaround-sensor ledger row — the task's "fresh-waiver escape, ledgered" letter, pinned in-suite). PASS
3. LIVE RED PROBE (verifier-constructed, Prove-it 1's positive arm against the REAL repo): a temp docs/designs/zz-verifier-addendum-probe.md carrying "## Addendum — verifier probe" → BLOCKED, exit 1, match line "[addendum-lint] docs/designs/zz-verifier-addendum-probe.md:3", full WHAT/WHY/FIX/ESCAPE contract with the [addendum-lint]-specific FIX text and the structured-waiver escape named; fixture deleted, git status clean. (First probe attempt in a bare tmp repo exited 0 — root-caused, not ignored: the scan's PRE-EXISTING denylist-absent early-exit skips ALL layers when adapters/claude-code/patterns/harness-denylist.txt is missing; the real repo carries the denylist so Layer 3 is live here. Named residual below.) PASS
4. Prove-it 1 negative arm: fixture A5 is the verbatim "### Round 3 — harness-reviewer REJECT..." + "## Round 4 —..." headings inside a PLAN (docs/plans/review-gate-identity-anchor-2026-07-30.md:249,304) asserted NOT to fire (Round scope = designs only); A6 is the verbatim archived addendum heading asserted NOT to fire (archive excluded entirely); A7 proves heading-anchoring (prose mentions never fire). All green in the suite re-run. PASS
5. Prove-it 2 — golden case re-observed live: grep -cEi of ATX Addendum headings in the brief → 0; ATX Round-N headings → 0; the brief's line 5 carries the Changelog entry recording the T19 integration (both trailing sections folded in place, CORRECTED/SUPERSEDED markers, no content dropped). PASS
6. Corpus re-measured by this verifier: live non-archived designs+plans carry ZERO Addendum/Update ATX headings; the 3 in-plan Round-N headings (2 files) + 1 archived addendum heading are all excluded by scope, matching the recovered articulation's 2-golden+3-in-plan accounting of the "5 measured legitimate hits" (the 2 golden-case hits are now A1/A2 POSITIVE fixtures since the integration removed them from the live corpus; the legitimate 3 live as A5/A6 negatives). PASS
7. Wire arrows: check_addendum_lint (:1254) + _hhs_addendum_scan (:1231) implemented in the main file, invoked as Layer 3 in the main scan loop (:1522) — exactly the plan's own corrected Wire-checks line; scope helpers _hhs_in_designs/_hhs_in_plans_scoped (:1211/:1219). PASS
8. Docs impact ("brief body integration IS the doc change"): met via check 5. PASS

Runtime verification: command bash adapters/claude-code/hooks/harness-hygiene-scan.sh --self-test   # → self-test: OK, zero FAIL lines incl. A1-A8 lint + W1-W6 waiver assertions (verifier re-run on master @ f3fffe8e)
Runtime verification: command bash adapters/claude-code/hooks/harness-hygiene-scan.sh docs/designs/zz-verifier-addendum-probe.md   # → exit 1, "[addendum-lint] ...:3: ## Addendum — verifier probe" (verifier live RED probe; temp fixture, deleted after)
Runtime verification: command grep -cEi '^#+ .*addendum' docs/designs/harness-execution-redesign-considerations-2026-08-02.md   # → 0 (golden case holds)
Runtime verification: file docs/designs/harness-execution-redesign-considerations-2026-08-02.md::Changelog
Runtime verification: file adapters/claude-code/hooks/harness-hygiene-scan.sh::check_addendum_lint

DEPENDENCY TRACE
================
Step 1: a staged design/plan file reaches the hygiene scan's per-file loop (pre-commit / path args)
  ↓ Verified at: harness-hygiene-scan.sh:965-971 (file-list build) + live probe invocation
Step 2: Layer 3 scans it with the M-9-narrowed, path-scoped, case-insensitive patterns
  ↓ Verified at: :1254 (check_addendum_lint) / :1231 (_hhs_addendum_scan) / :1522 (loop call) + A1-A7 green
Step 3: a hit BLOCKS with the [addendum-lint] label and the four-field contract naming the fold-in FIX and the waiver escape
  ↓ Verified at: verifier live RED probe output (exit 1, label, WHAT/WHY/FIX/ESCAPE)
Step 4: a fresh structured waiver suppresses the named file only, and the bypass is ledgered
  ↓ Verified at: A8 assertions (exit 0 + workaround-sensor row for docs/designs/addendum-fixture.md) in the green suite
Step 5: the golden-case brief itself is clean and records the integration
  ↓ Verified at: grep counts 0/0 + Changelog line 5

Verdict: PASS
Confidence: 9
Reason: PROVEN: the lint blocks live in the real repo (verifier's own RED probe: exit 1 with the [addendum-lint] label and complete contract), the full suite re-run green with the verbatim-corpus negative fixtures and the ledgered-waiver escape pinned in-suite, the golden-case brief re-observed clean with its Changelog record, and the corpus accounting independently re-measured. NAMED RESIDUAL (pre-existing, not T19's defect, non-blocking): the scan's denylist-absent early-exit (:981-984) predates this task and silently skips ALL layers — including Layer 3 — in any checkout lacking adapters/claude-code/patterns/harness-denylist.txt; in this repo the denylist exists so the lint is live. Filed for the completion report rather than nl-issue'd separately since the T8/T21 triage population already owns hygiene-scan disposition work.

## Task 20 — Verifier verdict (task-verifier)

EVIDENCE BLOCK
==============
Task ID: 20
Task description: REQ-B11+B12 carriage channels 2+3 (after Task 11): scripts/dispatch-directives.sh (tag-matched entries for a task's Files-to-Modify, printed for prompt inlining) + orchestrator-pattern doctrine step + doctrine-jit merged single-emission register walk (C-1 form) + G1/G2 carriage WARNs — Verification: full — Implements: REQ-B11, REQ-B12
Verified at: 2026-08-04T02:56:00Z
Verifier: task-verifier agent

Oracle: specified — the task's four Prove-it-works steps, each re-executed directly by this verifier (live channel-2 invocation against THIS plan; all three suites; an INDEPENDENT 10-run timing re-measurement via the evidence file's own reproduction method).

Comprehension-gate: PASS (confidence 8) — inline audit above ("Comprehension audit — batch #3"): behavioral claims re-verified at the merged bytes (jq -s length==1 raw-stdout assertion, global-variable fork-avoidance chain, disclosed parser limitation); articulation committed in-evidence at 7f37e074 (no recovery needed).
Operator invariants: none registered (exit 3) — re-run 2026-08-04T02:40Z

Checks run (all re-executed by this verifier on master @ f3fffe8e, 2026-08-04):
1. Ancestry: a175db7c (build) and 7f37e074 (timing table + articulation) both ancestors of master. PASS
2. Prove-it 1 re-run LIVE: dispatch-directives.sh <this-plan> 20 → first line "NL-ATTRIBUTION: plan=gated-pipeline-master-2026-08 task=20 role=builder", then "Directives: OD-002,OD-007,OD-008,OD-013,OD-018,OD-021" with the six instruction blocks, rc 0 — the OD-021 drift (register moved after the T16 field computation) re-observed live, the carriage-WARN mechanism catching its own plan's stale citation. PASS
3. Suites re-run: dispatch-directives.sh --self-test → 10 passed, 0 failed. directives-register-lib.sh --self-test → 29 passed, 0 failed (incl. pure-bash-vs-node/jq parity + real-register live check). doctrine-jit.sh --self-test → 17 passed, 0 failed with T11 both-match-same-event (ONE JSON object, both bodies, both markers — the C-1 load-bearing scenario), T13 dedup, T14 fresh-session re-fire, T15/T16 degrade paths ALL individually observed PASS in this verifier's own run (Prove-its 2+3). PASS
4. Prove-it 4 TIMING INDEPENDENTLY RE-MEASURED: this verifier re-ran the evidence file's own reproduction method (EPOCHREALTIME-bracketed _compute_register_body against the REAL committed register, doctrine-jit.sh as trigger file, 10 runs, fresh marker dir per run) → 23-39ms, average 30ms — under the 50ms F-5 budget, consistent with (and better than) the builder's 47ms heavy-load official reading. PASS
5. Wire arrows: dispatch-directives.sh → directives-register-lib.sh glob matcher (dr_entries_for_files); doctrine-jit.sh register walk → same lib's dr_register_walk_bash (pure-bash path, doctrine-jit.sh:85-127 header contract) with the single jq -n emission site; both per the plan's Wire-checks letter. PASS
6. Docs impact: orchestrator-pattern.md carries the generated-header rule + dispatch-directives step (":11", operator-directive provenance named); doctrine-jit.sh's own header documents the register walk. PASS
7. RESIDUAL ADJUDICATION (dispatch-directed) — G1/G2 carriage WARN lives in dispatch-directives.sh only: ACCEPTED as a disclosed, reasoned scope interpretation, not a defect. The task's own Wire-checks block names ONLY dispatch-directives.sh and doctrine-jit.sh; the articulation discloses the choice prominently (avoiding T14's in-flight file and T17's explicitly-guarded gate) and the WARN fires at the moment citations are actually pasted into a dispatch — G2's real moment. If the operator wants the WARN live-wired inside plan-reviewer/dispatch-chain-gate, that is follow-up scope for the completion report, not an unmet letter here. PASS
8. RESIDUAL ADJUDICATION — task-20 plan line's Directives list stale vs the live register: NOT a defect; the plan is frozen, the evidence records the drift, and the mechanism this task built is precisely what detected it (check 2's live WARN). The plan's own convention (built tasks keep historically-true Directives lines) applies. PASS
9. Live-deployment posture: doctrine-jit's _resolve_register_path uses nl_repo_root() (NOT the lib's script-relative climb), and this verifier empirically resolved it live → the real checkout's committed register (REGISTER-RESOLVES-LIVE). The live ~/.claude/hooks/doctrine-jit.sh copy is one sync behind master; hooks IS in session-start-auto-install's SYNC_SUBDIRS and master is fully pushed (0/0 vs origin), so the next SessionStart lands it — HYPOTHESIZED (refuted if a fresh session's live copy still differs). NAMED RESIDUAL (non-blocking): the LIB's own dr__resolve_root climbs script-relatively, so invoking dispatch-directives.sh from ~/.claude/scripts (cross-repo use) would silently degrade to no directives — the doctrine documents the repo-relative invocation, which works; a nl_repo_root fallback in dr__resolve_root is the cheap hardening. PASS-with-residual

Runtime verification: command bash adapters/claude-code/scripts/dispatch-directives.sh docs/plans/gated-pipeline-master-2026-08.md 20   # → attribution header + Directives: OD-002,OD-007,OD-008,OD-013,OD-018,OD-021 + blocks, rc 0 (verifier live re-run)
Runtime verification: command bash adapters/claude-code/scripts/dispatch-directives.sh --self-test   # → 10 passed, 0 failed (verifier re-run)
Runtime verification: command bash adapters/claude-code/hooks/lib/directives-register-lib.sh --self-test   # → 29 passed, 0 failed (verifier re-run)
Runtime verification: command bash adapters/claude-code/hooks/doctrine-jit.sh --self-test   # → 17 passed, 0 failed incl. T11 both-match ONE-JSON-object (verifier re-run)
Runtime verification: command bash <scratchpad>/t20-timing.sh   # → 10-run average 30ms (23-39ms) via the evidence file's own EPOCHREALTIME reproduction (verifier re-measurement, < 50ms F-5 budget)

DEPENDENCY TRACE
================
Step 1: orchestrator runs dispatch-directives.sh <plan> <task> for a dispatch
  ↓ Verified at: live re-run (check 2) + orchestrator-pattern.md:11 doctrine step
Step 2: the ONE parser lib matches the task's Files-to-Modify tags against register surfaces
  ↓ Verified at: dr_entries_for_files via the T11 shared fixture (suite s-scenarios) + the live OD-021 match
Step 3: the printed header+Directives block is pasted into the dispatch prompt; drift triggers the carriage WARN
  ↓ Verified at: check 2 live output (WARN naming OD-021, fires only on real drift per suite scenarios)
Step 4: independently, every Edit/Write event walks the register in doctrine-jit and injects matched OD bodies merged with the doctrine walk in ONE JSON emission, deduped per session
  ↓ Verified at: doctrine-jit.sh:842 (jq -s length==1) + T11/T12/T13/T14 observed green + 30ms measured walk cost

Verdict: PASS
Confidence: 9
Reason: PROVEN: all four Prove-it-works steps re-executed directly by this verifier — the live channel-2 invocation reproducing the OD-021 drift WARN, all three suites green (10/10, 29/29, 17/17 with the C-1 both-match scenario individually observed), and the F-5 timing budget independently re-measured at 30ms average via the evidence file's own reproduction method. Both dispatch-flagged residuals adjudicated with reasons (checks 7-8): the carriage-WARN placement is a disclosed interpretation consistent with the task's own Wire-checks letter, and the stale plan-line Directives list is the mechanism working against a frozen plan, not a gap. One named non-blocking hardening residual (lib-level script-relative root climb for cross-repo channel-2 use) recorded for the completion report.

## Task 23 — Verifier verdict (task-verifier)

EVIDENCE BLOCK
==============
Task ID: 23
Task description: REQ-C5 minimal Stage-3 subset: death-certificate fields on nl-maintenance's existing handle-wait + cleanup-as-sensor fields on the existing janitor log, each naming its consumer at birth in the field comment — Verification: contract — Implements: REQ-C5
Verified at: 2026-08-04T03:00:00Z
Verifier: task-verifier agent (Verification: contract — locked-shape checks re-observed directly; the salvage provenance means the builder's word was taken for NOTHING re-observable)

Oracle: contract — the two field-set shapes at their write sites (both branches each), the consumer-named-at-birth comments, and both suites re-run by this verifier (not the orchestrator's post-salvage runs).

Comprehension-gate: not applicable (Verification: contract — Step-0 per-level early-return semantics, same routing as the Task 2/6/10 verdicts above). Salvage note: the builder's worktree was never provisioned (edits landed in the main checkout; directory destroyed pre-commit; nl-issue on the provisioning defect confirmed present in ~/.claude/state/nl-issues.jsonl) — provenance disclosed in commit 02e5e786's own message, honest per §1.
Operator invariants: none registered (exit 3) — re-run 2026-08-04T02:40Z

Checks run (all re-executed by this verifier on master @ f3fffe8e, 2026-08-04):
1. Ancestry: 02e5e786 (salvaged build) is an ancestor of master; commit message carries the full incident provenance + the orchestrator's post-salvage suite re-runs. PASS
2. Death-certificate fields at the write sites, BOTH branches: nl-maintenance.sh:691 (watchdog-kill: death_outcome=term_signal_sent — or the honesty-bounded would_signal_selftest_stub under HARNESS_SELFTEST — death_cause=watchdog-term-kill) and :699 (kill-skip: death_outcome=kill_skipped_unverified_identity, death_cause=identity_mismatch_fail_closed) — real, code-path-driven values, not a shared placeholder. PASS
3. Cleanup-as-sensor fields at the write sites: perf-tick-snapshot.sh:442-447 computes per-candidate what/why_it_existed/which_prevention_failed (why names the structural survival reason + measured age vs threshold; which_prevention names S-21 Job-Object binding as NOT YET BUILT) and :481 emits them into the ticks ledger row JSON. PASS
4. Consumers named at birth: nl-maintenance.sh:678-682 ("Consumer: no automated reader exists yet ... PLANNED consumer is the weekly aggregation / top-killer synthesis OD-[007/DEC-8] ... INTERIM real consumer is an operator/triage session grepping") and perf-tick-snapshot.sh:336-340 (same two-tier consumer statement) — honest (no fabricated reader), exactly the task's field-comment letter. PASS
5. Suites re-run BY THIS VERIFIER (never trusting the salvage runs): nl-maintenance.sh --self-test → 44 passed, 0 failed, incl. Scenario 15/S15a asserting the death-cert values are REAL and branch-distinct (the skip branch must NOT carry the kill branch's death_outcome — a discriminating cross-branch assertion, not presence-only). perf-tick-snapshot.sh --self-test → 33 passed, 0 failed, incl. Scenario 5b asserting per-candidate (non-placeholder) sensor values in BOTH PTS_REAP_RESULTS and the actual ticks.jsonl ledger line. PASS
6. Docs impact ("none — fields documented at their write sites"): met via checks 2-4 (both field sets carry substantive in-file contract comments). PASS

Runtime verification: command bash adapters/claude-code/scripts/nl-maintenance.sh --self-test   # → 44 passed, 0 failed incl. S15/S15a death-cert branch-distinct assertions (verifier re-run on master @ f3fffe8e)
Runtime verification: command bash adapters/claude-code/hooks/lib/perf-tick-snapshot.sh --self-test   # → 33 passed, 0 failed incl. 5b per-candidate sensor-field assertions (verifier re-run)
Runtime verification: file adapters/claude-code/scripts/nl-maintenance.sh::death_cause
Runtime verification: file adapters/claude-code/hooks/lib/perf-tick-snapshot.sh::which_prevention_failed

Verdict: PASS
Confidence: 9
Reason: PROVEN: both contract shapes present at their write sites with branch-distinct real values (kill vs identity-mismatch-skip; per-candidate reap sensor fields), consumers named at birth honestly (planned OD-007/DEC-8 aggregation + interim operator-grep, no fabricated reader), and both suites re-run green by this verifier independently of the orchestrator's post-salvage runs. The salvage provenance (worktree never provisioned, edits landed in the main checkout, nl-issue filed) is fully disclosed in the commit message and does not touch the contract's truth — every re-observable claim was re-observed.

## Task 24 — Verifier verdict (task-verifier)

EVIDENCE BLOCK
==============
Task ID: 24
Task description: REQ-C6 Stage-2 admission trigger: doctor WARN "stage-2 admission open since <date>" (data-file date written by Task 8's completion) persisting until a Stage-2 plan goes ACTIVE. Detection mechanism (T16 F-6): ACTIVE docs/plans/*.md header carrying stage-2-successor: gated-pipeline-master-2026-08; the contract check MUST include the two-state proof — Verification: contract — Implements: REQ-C6
Verified at: 2026-08-04T03:04:00Z
Verifier: task-verifier agent (Verification: contract — the two-state proof re-observed through the PRODUCTION function bytes, not the builder's scenarios alone)

Oracle: contract — the two-state behavior contract (open→WARN, fulfilled→clear) plus the null-silence precondition, re-proven by this verifier through a hermetic probe that `eval`s check_stage2_admission_open VERBATIM out of the live harness-doctor.sh (sed-extracted production bytes, stubbed _warn/_red, fixture manifests + plan dirs).

Comprehension-gate: not applicable (Verification: contract — Step-0 per-level routing, T2/T6/T10/T23 precedent).
Operator invariants: none registered (exit 3) — re-run 2026-08-04T02:40Z

Checks run (all re-executed by this verifier on master @ f3fffe8e, 2026-08-04):
1. Ancestry: cddfc655 (build) + f3fffe8e (manifest integration) both ancestors of master. PASS
2. FOUR-STATE PROBE through the production function (verifier-constructed, hermetic): (a) opened_since=null → SILENT (zero warn/red emissions); (b) opened_since=2026-08-03 + no successor plan → WARN "stage-2 admission open since 2026-08-03 -- no ACTIVE docs/plans/*.md carries 'stage-2-successor: gated-pipeline-master-2026-08' yet; register the Stage-2 plan..."; (c) same date + an ACTIVE plan carrying the marker header → SILENT (the WARN CLEARS — the obligation resolves, never latches); (d) marker present but Status: COMPLETED → WARN stays (Status: ACTIVE is genuinely required, not just marker presence). The two-state proof letter (F-6) holds, plus both guard states. PASS
3. LIVE PRE-T8 STATE: schedule-manifest.json .stage2_admission.opened_since is null with a substantive in-data note (written ONLY by Task 8's REQ-A8 completion; T8 is PARTIAL/open) — so the check is provably silent on this machine today, by design, matching probe state (a). PASS
4. Committed self-test scenarios read line-by-line (harness-doctor.sh:7715-7815): five scenarios — s2a-absent-silent, s2a-null-silent, s2a-warn-present (+rc==0, WARN-only per arch-M3), s2a-warn-clears, s2a-marker-not-active — semantically identical to this verifier's probe states plus the key-absent variant (same code path as null via the jq // empty read). Consistent with the manifest entry's own 5-scenario claim. PASS
5. Wire arrows: check_stage2_admission_open defined at :2763, reads .stage2_admission.opened_since via jq (:2774), scans docs/plans/*.md headers for Status: ACTIVE + the marker line (:2788-2792), invoked in the doctor's main run at :4206; the marker convention documented in the check's own comment block (:2723-2749) exactly per the task letter. PASS
6. Manifest entry (Docs impact): stage2-admission-open present with FULL evidence-bar fields — honest_status (naming the null-silent design, the F-6 detection mechanism, and all 5 self-test scenarios), golden_scenario (the admission-rot forgetting class), fp_expectation (WARN-only; missing-marker remedy), retirement_condition (self-retiring), honesty_rationale (same-merge-train HR-F9 discipline; null data ships no fabricated state); blocking=false, selftest=true; landed in f3fffe8e with the INDEX regen; manifest-check GREEN. PASS
7. HONEST SCOPE DISCLOSURE (builder residual, adjudicated): the FULL doctor self-test suite (~600 scenarios, 15-20 min) was NOT run to completion by the builder, and NOT by this verifier either — this verifier ran the T24-relevant subset at function level (the four-state probe through the production bytes) instead, per the dispatch's stated fallback; the full-suite run is booked to the T8 closure (which owns global doctor state per the plan's own REQ-A8 done-bar rule: targeted self-tests are the bar for other tasks). Stated, not hidden. PASS-as-disclosed

Runtime verification: command jq '.stage2_admission.opened_since' adapters/claude-code/config/schedule-manifest.json   # → null (live pre-T8 state; probe state (a) proves this state is silent)
Runtime verification: command bash <scratchpad>/t24-probe.sh   # → STATE-null SILENT / STATE-open WARN / STATE-fulfilled SILENT / STATE-not-active WARN (verifier hermetic probe eval'ing the production check_stage2_admission_open verbatim from harness-doctor.sh:2763-2801)
Runtime verification: file adapters/claude-code/hooks/harness-doctor.sh::check_stage2_admission_open
Runtime verification: file adapters/claude-code/manifest.json::"stage2-admission-open"
Runtime verification: file adapters/claude-code/config/schedule-manifest.json::"stage2_admission"

Verdict: PASS
Confidence: 8
Reason: PROVEN: the contract's two-state proof (plus the null-silence precondition and the not-ACTIVE guard) re-observed by this verifier through the production function bytes in a hermetic four-state probe; the live data key is null with an honest in-data note so the check is provably silent until T8 writes the date; the manifest entry carries every evidence-bar field and manifest-check is GREEN. Confidence 8 not 9: the full doctor suite run (whole-doctor integration of the five committed scenarios via _run_quick) is booked to the T8 closure rather than executed here — the function-level probe plus the :4206 invocation wire arrow is the evidence base, disclosed in check 7.

## Task 17 — Verifier verdict (task-verifier) — FAIL, checkbox NOT flipped

EVIDENCE BLOCK
==============
Task ID: 17
Task description: REQ-B8 G2 gate live (after Task 16): dispatch-chain-gate.sh wired PreToolUse Task|Agent (subagent_type-keyed per design §4; grandfather list generated at install from extant plan slugs; gate-contract messages; --check; escape ledgered) + THE THREE-VARIANT DEMO with transcripts in the evidence file — Verification: full — Implements: REQ-B8
Verified at: 2026-08-04T03:08:00Z
Verifier: task-verifier agent

Oracle: specified — the task's three Prove-it-works steps plus the plan's Intended-Functionality item 1 (the D-15 acceptance bar), re-exercised directly by this verifier; PLUS a verifier-constructed INSTALLED-LAYOUT A/B probe of the live deployment path (the check on which the verdict turns).

Comprehension-gate: PASS (confidence 8) — inline audit above ("Comprehension audit — batch #3"): articulation honest and detailed, citations resolve at a uniform +4-6 offset from the disclosed orchestrator amendment, NOT-covered exemplary (the timing-miss corrected-in-place admission); FM-023-adjacent finding recorded there and acted on in check 9 below.
Operator invariants: none registered (exit 3) — re-run 2026-08-04T02:40Z

Checks run (all re-executed by this verifier on master @ f3fffe8e, 2026-08-04) — the GREEN inventory first, then the two FAIL bases:
1. Ancestry: e82f0b93 (build), 08e8438c (stale-bootstrap-entry removal), f3fffe8e (manifest wiring flip) all ancestors of master. (Dispatch note: the cited b8fc951d is NOT an ancestor — the chain-entry removal on master is 08e8438c; substance verified directly regardless.) PASS
2. Suite re-run: dispatch-chain-gate.sh --self-test → 40 passed, 0 failed (of 40 scenarios), incl. the three demo variants as executable fixtures, grandfathered-slug-proceeds-rc0, valid-chain silent pass, research-untouched, M-7 both branches, role-divergent underivable-slug, Mi-5 no-repo, demo-iii-message-is-not-the-chain-less-framing. PASS
3. ORCHESTRATOR AMENDMENT SCRUTINY (dispatch-directed), all four asks proven: (a) hashing correctness — sha256("gated-pipeline-master-2026-08") = 3894b993… found as an exact registry line; an unlisted slug's hash correctly misses; (b) the 40/40 suite GENUINELY exercises the hashed path — the self-test fixture writer (:640) writes sha256("g2-demo-grandfathered") as an opaque entry and the grandfather scenario passes through _dcg_grandfathered's hash-then-match; (c) registry header documents membership (printf '%s' <slug> | sha256sum) and removal (REQ-C2 drain hashes the retired slug) plus F-4 ordering and never-grows semantics; (d) zero plaintext: grep -cE '^[0-9a-f]{64}$' → 300, non-hash non-comment lines → 0, and the blob at e82f0b93 is ALREADY hashed — no plaintext registry was ever committed to master or pushed (the plaintext form exists ONLY at 78e67de3 on the local unpushed branch worktree-agent-a38c63c69628eb5a9 — cleanup note below). PASS
4. THE THREE-VARIANT DEMO (D-15 acceptance bar): all three transcripts present in the evidence dir, verbatim command+output+exit-code form: (i) chain-less + attribution → exit 2, four GATE fields, chain-presence FAIL; (ii) same plan, NO attribution anywhere → exit 2, IDENTICAL block framing (H1 proven); (iii) never-dispatched-reviewer chain → exit 2 with rule1/rule2 PASS + rule3 FAIL detail, textually distinct from the chain-less framing. Zero variants pass through — Intended-Functionality item 1 holds. PASS
5. Chain-parses check (dispatch-directed): rc_validate_chain on the live plan at HEAD → RC=0, RC_VERDICT=WARN (not FAIL) — the stale unanchored bootstrap entry's removal leaves T16's calibration-window rule-2 WARN only, exactly as the Decisions Log records. PASS
6. Template wiring + manifest: settings.json.template carries the Task|Agent block for dispatch-chain-gate.sh AFTER model-pin-gate and BEFORE workstreams-emit --on-builder-dispatch (order per the header's WIRING rationale); manifest entry events=[PreToolUse], wired_template=true, blocking=true, honest_status naming the opaque registry with §9 rationale AND the KNOWN PERF MISS honestly. PASS
7. Perf gap honestly filed: the 5.7-9.6s vs <300ms budget miss is in the evidence narrative, the articulation (corrected in place), the manifest honest_status, AND a 2026-08-03T22:53Z nl-issue naming root cause (per-rule-per-entry git subprocess in review-chain-lib, T1 scope) + the memoization fix path. PASS
8. **FAIL BASIS 1 — the INSTALLED form of the gate is a silent no-op (disconnected-feature class).** The gate resolves BOTH config dependencies script-location-relatively (_dcg_dir/../config: model-policy.json for build-type classification, g2-grandfather-slugs.txt) — by explicit design comment, rejecting nl_repo_root(). But NO install mechanism deploys config/: install.sh's dir loop ("rules agents hooks scripts pipeline-prompts pipeline-templates commands doctrine skills templates") and session-start-auto-install's SYNC_SUBDIRS ("hooks scripts agents rules templates skills doctrine") BOTH omit config, and the live ~/.claude/config/ contains neither file. _dcg_build_types has a SILENT [[ -f ]] || return 0 guard, so on any installed machine every build-category dispatch classifies as non-build and falls to the M-7 proceed branch. A/B-PROVEN with the SAME chain-less builder dispatch event: repo-checkout form → exit 2 BLOCK; installed-layout replica (gate + hooks/lib copied to a dir with no sibling config/, exactly what ~/.claude will hold after the next sync) → exit 0, "WARN — non-build dispatch (subagent_type=plan-phase-builder)… never blocked". The plan's Intended Functionality ("the dispatch is refused on the spot") therefore has NO mechanism on the installed surface where real sessions run (§1: never claim future behavior without a mechanism), and the silent degradation additionally violates the plan's own Failure-modes contract ("fail-open with a WARN line naming the degradation (never silent)"). FAIL
9. **FAIL BASIS 2 — Docs impact component unmet.** The task's Docs-impact letter has three components: manifest entry ✓ (f3fffe8e), settings.json.template wiring ✓, "orchestrator-pattern doctrine gains the gate step" ✗ — grep of orchestrator-pattern.md and -full.md finds ZERO mention of dispatch-chain-gate/G2 as a dispatch step (and no other prose doctrine file carries it; deterministic-process.md has none; only the manifest/INDEX rows exist). Same class as the T18 batch #2 FAIL, applied consistently. Aggravating context: the T15 verdict's accepted residual (a one-line dispatch-ledger note in this same file) was premised on "the T17/T20 train will fold it in" — T20's train landed its own step only, so that premise is now falsified twice for this file. FAIL

Runtime verification: command bash adapters/claude-code/hooks/dispatch-chain-gate.sh --self-test   # → 40 passed, 0 failed (verifier re-run on master @ f3fffe8e)
Runtime verification: command bash -c 'printf "%s" gated-pipeline-master-2026-08 | sha256sum | cut -d" " -f1 | xargs -I{} grep -cxF {} adapters/claude-code/config/g2-grandfather-slugs.txt'   # → 1 (listed slug hashes to a registry line; unlisted-slug hash → 0)
Runtime verification: command grep -cE '^[0-9a-f]{64}$' adapters/claude-code/config/g2-grandfather-slugs.txt   # → 300; non-hash non-comment lines → 0
Runtime verification: file docs/plans/gated-pipeline-master-2026-08-evidence/t17-demo-variant-3.txt::rule3: FAIL: no dispatch-ledger row
Runtime verification: command CLAUDE_TOOL_INPUT='<variant-i-shaped builder event>' bash <installed-layout-replica>/hooks/dispatch-chain-gate.sh   # → exit 0 M-7 proceed (vs exit 2 BLOCK from the repo checkout, SAME event — the FAIL-basis-1 A/B, re-runnable by copying the gate + hooks/lib to any dir without a sibling config/)
Runtime verification: command grep -c "dispatch-chain-gate" adapters/claude-code/doctrine/orchestrator-pattern.md   # → 0 (the FAIL-basis-2 mechanical basis; must become ≥1)

Verdict: FAIL
Confidence: 9
Reason: PROVEN (mechanism, repo form): the gate, the three-variant D-15 demo, the opaque-hash amendment, the chain-WARN state, the wiring, and the honest perf disclosure are all real and re-observed — 40/40, hashing proven both directions, transcripts verbatim, manifest truthful. PROVEN (gap 1): the INSTALLED form — the only form real sessions execute — silently never blocks, because neither install.sh nor session-start-auto-install deploys config/, and the gate's build-type read degrades silently on a missing model-policy.json; A/B-demonstrated with the same event blocking in the repo form and passing in the installed layout. PROVEN (gap 2): the Docs-impact component "orchestrator-pattern doctrine gains the gate step" is absent from the named file and from all prose doctrine. A gate whose live deployment cannot fire is the exact vaporware class this plan exists to end; the checkbox cannot flip until the installed path is real.
Gaps:
  - Installed-form no-op (Class: disconnected-feature / HR-F9-adjacent deployment gap; Sweep query: grep -n 'for dir in rules agents hooks' adapters/claude-code/install.sh && grep -n SYNC_SUBDIRS adapters/claude-code/hooks/session-start-auto-install.sh — neither list contains config; Required generalization: EVERY runtime dependency of an installed hook must either live in a synced dir or be resolved with a LOUD fallback — the plan's own Failure-modes contract already mandates "never silent". Remedy options for the orchestrator, either or both: (a) add config to install.sh's dir loop AND session-start-auto-install's SYNC_SUBDIRS (verify config/ holds no machine-local files first); (b) give _dcg_build_types/_dcg_grandfathered an nl_repo_root()-resolved fallback path plus a WARN line when the script-local config is absent. Re-verification: re-run the installed-layout A/B — the replica (or the real ~/.claude after a SessionStart) must BLOCK the variant-(i) event with exit 2.)
  - Docs impact: orchestrator-pattern.md gains the G2 dispatch-gate step (Sweep query: grep -c "dispatch-chain-gate" adapters/claude-code/doctrine/orchestrator-pattern.md → must become ≥1; fold the still-outstanding T15 dispatch-ledger one-liner into the same commit — its "next train will carry it" premise has now been falsified twice.)
  - NON-BLOCKING (same remedy commit, one line): the registry header's "Regenerate with" command emits PLAINTEXT basenames with no sha256 step — following it would both break _dcg_grandfathered's hash matching (fail-closed: every legacy slug would BLOCK instead of WARN) and re-introduce the §9 string the conversion removed; pipe each basename through sha256sum in the documented command.
  - NON-BLOCKING (cleanup, T21's drain or sooner): the pre-conversion PLAINTEXT registry blob exists at commit 78e67de3 on local branch worktree-agent-a38c63c69628eb5a9 (never pushed, not on master) — delete the branch+worktree to purge the product-codename string from local history.

## Task 17 — REMEDY ROUND (builder, batch #3 FAIL remediation, 2026-08-04)

Fixes R1 (both bases), R2 (docs-impact), R3 (registry header) built in a worktree rooted
at master @ d1d20320. Not yet re-verified by task-verifier (dispatched separately per
the remedy contract).

### R1a — install.sh / session-start-auto-install.sh now deploy config/

`adapters/claude-code/install.sh`'s dir loop and
`adapters/claude-code/hooks/session-start-auto-install.sh`'s `SYNC_SUBDIRS` both
omitted `config/` — the batch #3 FAIL basis. Fixed with ONE additional finding beyond
the FAIL basis itself: **the live `~/.claude/config/` directory is NOT empty on a
real machine** — it already holds genuine machine-local files this repo does not own
(`active-repos.txt`, `pr-health-snapshot.sh`'s operator-populated repo list;
`register-path`, `register-surfacer.sh`'s coordination-repo pointer), confirmed on
this machine (`ls ~/.claude/config` → `active-repos.txt`,
`active-repos.txt.bak-1780471149`, `register-path`, none of which exist in the repo's
`adapters/claude-code/config/`). `install.sh`'s `sync_directory()` does `rm -rf "$dst"`
before repopulating — correct for every other synced dir (pure harness content, no
legitimate machine-local drift) but would have **silently destroyed both files on the
very first real `install.sh` run** had `config` simply been appended to that loop, as
the original FAIL-basis remedy option (a) suggested (that option's own text flagged
"verify config/ holds no machine-local files first" as a precondition — checked here,
and it does not hold).

Fix actually shipped:
- `install.sh`: `config` is **not** added to the whole-directory `sync_directory` loop.
  A dedicated PER-FILE block (dry-run preview + real flow) walks only the files that
  exist in the repo's `adapters/claude-code/config/` and `sync_file()`s each one by
  name — `sync_file` backs up + replaces exactly the one named path, never `rm -rf`s
  the parent, so any live-only file at `~/.claude/config/` is left completely alone.
- `session-start-auto-install.sh`: `config` IS added to `SYNC_SUBDIRS` — its
  `sync_canonical_files()` is already per-file (install-if-missing/update-if-differing,
  unknown live files counted as informational drift and never touched), so no
  destructive-loop hazard exists there. `_subdir_ext()` was generalized from a single
  scalar extension per subdir to a space-separated SET (config/ ships
  `.json .txt .md .example`, the first heterogeneous-extension subdir); the ls-tree
  filter, the per-file chmod check, and the live-side drift-glob loop were all updated
  to iterate the set rather than assume one extension.
- Functional proof (not just a repo-relative reading): a standalone extraction of
  `install.sh`'s sync primitives (`sync_file`, `backup_if_real_file`, the self-sync
  guard) run against fabricated `ADAPTER_DIR`/`CLAUDE_DIR` fixtures confirmed
  `model-policy.json` + `g2-grandfather-slugs.txt` deploy correctly AND a fabricated
  machine-local `active-repos.txt` (seeded with a sentinel string) survives byte-for-
  byte untouched — `ALL PASS` (script:
  `<scratchpad>/t17-config-sync-functest.sh`).
- `install.sh --dry-run` against the REAL live `~/.claude/` (read-only, no HOME
  override, "Dry run complete. No changes made." confirmed) now lists each of the 10
  repo-tracked config files individually as `[WOULD CREATE]` and — critically —
  neither `active-repos.txt` nor `register-path` appear anywhere in the diff.

### R1b — dispatch-chain-gate.sh loud-fallback on missing config

`_dcg_build_types()` (model-policy.json) and `_dcg_grandfathered()`
(g2-grandfather-slugs.txt) both silently `return`ed on a missing file before this fix.
Both now emit a `WARN` naming the missing file and the word `DEGRADED` plus the exact
fail-open/fail-safe behavior, to stderr, on every affected dispatch (not just once).
Two new `--self-test` scenarios assert on the WARN TEXT, not just rc (a silent and a
loud fail-open produce the identical rc, so rc alone cannot prove the fix):
`config-absent-model-policy-*` (3 assertions) and `config-absent-grandfather-*` (3
assertions) — all PASS in the 49/49 run below.

### R1c — installed-layout A/B, re-run per the remedy contract

Built two replicas under the scratchpad (`hooks/dispatch-chain-gate.sh` + `hooks/lib/`
copied from the POST-FIX repo; one with a sibling `config/` populated from the repo's
real `config/model-policy.json` + `config/g2-grandfather-slugs.txt`, one without), and
a throwaway git repo carrying one chain-less `docs/plans/t17-ab-probe-plan.md`. Same
chain-less builder-dispatch event fired at both replicas via Git Bash directly
(`C:\Program Files\Git\bin\bash.exe`, PowerShell tool — the sandboxed Bash tool
declines `cd`+git chains into paths outside this worktree):

```
=== A: replica WITH config/ (POST-FIX layout, config/ present per the R1a fix) === rc=2
dispatch-chain-gate: plan-phase-builder dispatch BLOCKED — docs/plans/t17-ab-probe-plan.md has no Review Chain
[GATE:WHAT] docs/plans/t17-ab-probe-plan.md has no ## Review Chain block
[GATE:WHY] G2 (plan -> build) requires mechanical proof the design/plan reviews ran before a builder dispatches against this plan (D-15's acceptance bar; design docs/designs/gated-pipeline-master-2026-08-03.md SS4)
[GATE:FIX] dispatch the required reviewers (plan-fidelity-reviewer at minimum; design-author's reviewers too if design-ref is required), then add a ## Review Chain block naming each reviewer/verdict/record — schema in design SS4
[GATE:ESCAPE] none for a new plan — a legacy plan predating this gate is exempted only via the install-generated grandfather slug list (config/g2-grandfather-slugs.txt), never by this flag
-- detail --
[FAIL] chain-presence: no ## Review Chain section found in docs/plans/t17-ab-probe-plan.md
```

```
=== B: replica WITHOUT config/ (partial/pre-deploy state — SAME event, identical POST-FIX gate+lib bytes, only config/ removed) === rc=0
dispatch-chain-gate: WARN — config/model-policy.json not found at <replica>/hooks/../config/model-policy.json; G2 cannot classify build-category subagent_types, so chain-validation is DEGRADED (fail-open: this dispatch is treated as non-build and proceeds WITHOUT a chain check). Fix: ensure config/ is deployed alongside hooks/ (install.sh's dir loop / session-start-auto-install.sh's SYNC_SUBDIRS must both carry config/), or set DCG_MODEL_POLICY_PATH.
dispatch-chain-gate: WARN — non-build dispatch (subagent_type=plan-phase-builder) references docs/plans/t17-ab-probe-plan.md; recorded (M-7 evasion heuristic), never blocked
```

A now BLOCKS where the pre-fix verifier probe silently proceeded; B still fail-opens
(by design — the gate must never fail-closed on its own internal-config unavailability)
but is now LOUD, naming the exact missing file and "DEGRADED" — the contrast the batch
#3 FAIL demanded. This is the belt-and-suspenders pairing: R1a makes the deploy path
carry config/ so replica-A's layout is what real installs will actually have; R1b
covers the residual case (a partial/corrupted/manually-pruned deploy) so even that
degrades loudly instead of silently.

### R2 — orchestrator-pattern.md gains the G2 gate step

`grep -c "Verify obligations (OD-022)" adapters/claude-code/doctrine/orchestrator-pattern.md`
→ 1 (T15's dispatch-ledger note already landed via T25's merge, confirmed — no
duplicate work needed). Added ONE new bullet: "G2 gate: Task|Agent dispatch routes
through dispatch-chain-gate.sh — chain-invalid BLOCKS, grandfathered/no-repo WARN.
-full.md." `grep -c "dispatch-chain-gate" adapters/claude-code/doctrine/orchestrator-pattern.md`
→ 1 (was 0). Compact was at 2997/3000 bytes; trimmed six other bullets (redundant
words, not content) to land the new bullet at 2998/3000. `planning.md` (2986/3000,
also named in the dispatch) required no change — it does not reference the gate and
the dispatch's own instruction said R2 there was conditional on T15's note being
absent, which it was not.

### R3 — registry regen command now hashes

`config/g2-grandfather-slugs.txt`'s header "Regenerate with" command previously piped
plaintext slug basenames straight to the output file with no hashing step (would have
broken `_dcg_grandfathered`'s hash-match lookup fail-closed, and re-introduced the
plaintext-product-string shape the T17 merge-train conversion removed). Fixed to
`| while read -r s; do printf '%s' "$s" | sha256sum | cut -d' ' -f1; done`, matching
the header's own membership-test convention. Verified by running the corrected command
against a fabricated two-plan fixture and independently computing `sha256("alpha")` /
`sha256("beta")` — byte-identical match (`<scratchpad>/t17-regen-cmd-test/run.sh`).

### Suites (verbatim)

```
$ bash adapters/claude-code/hooks/dispatch-chain-gate.sh --self-test
self-test summary: 49 passed, 0 failed (of 49 scenarios)

$ bash adapters/claude-code/hooks/dispatch-chain-gate.sh --self-test-wip-limit
self-test-wip-limit summary: 10 passed, 0 failed (of 10 scenarios)

$ bash adapters/claude-code/hooks/session-start-auto-install.sh --self-test
[self-test] 22 passed, 3 failed
```

The 3 `session-start-auto-install.sh` failures (`SELF-SYNC-01-golden-scenario`,
`SELF-SYNC-01-settings-merge-guard`, `SELF-SYNC-01-prune-guard`) are PRE-EXISTING and
UNRELATED to this remedy: all three require `ln -s` to create a real OS symlink, and
this Windows/Git-Bash checkout (no Developer Mode / elevated privilege) silently
creates a plain directory copy instead — confirmed directly (`mkdir real && ln -s real
link; [ -L link ]` → NOT A SYMLINK) and by re-running the UNMODIFIED HEAD version of
the same script in place, which fails the identical three scenarios. HYPOTHESIZED:
these would PASS on a machine where `ln -s` produces genuine symlinks (e.g. WSL, macOS,
or Windows with Developer Mode); REFUTED if they still fail there. `install.sh` has no
`--self-test` (confirmed via its own `--help` output — flags are `--dry-run
--replace-settings --uninstall --verify --help` only); verified instead via
`--dry-run` (shown above) plus the standalone functional test of its sync primitives.

### Compact byte counts (files touched)

- `adapters/claude-code/doctrine/orchestrator-pattern.md`: 2998/3000 (was 2997/3000;
  +1 bullet, -6 trims)
- `adapters/claude-code/doctrine/planning.md`: 2986/3000 (untouched, no change needed)
  - NOTE (not a gap, verification obligation): live ~/.claude settings + hook-file sync for this gate land at the next SessionStart (master fully pushed, 0/0 vs origin; hooks/templates are in the sync sets) — HYPOTHESIZED, refuted if a fresh session's live settings still lack the Task|Agent dispatch-chain block. Moot for blocking purposes until FAIL-basis-1 is fixed, since the synced gate would currently no-op.

## Task 17 — Verifier verdict (task-verifier, batch #4 SCOPED RE-CHECK — supersedes the batch #3 FAIL; re-litigates ONLY the two FAIL bases per the remedy contract; checks 1-7 stand from batch #3)

EVIDENCE BLOCK
==============
Task ID: 17
Task description: REQ-B8 G2 gate live (after Task 16): dispatch-chain-gate.sh wired PreToolUse Task|Agent (subagent_type-keyed per design §4; grandfather list generated at install from extant plan slugs; gate-contract messages; --check; escape ledgered) + THE THREE-VARIANT DEMO with transcripts in the evidence file — Verification: full — Implements: REQ-B8
Verified at: 2026-08-04T06:35:00Z
Verifier: task-verifier agent

Oracle: specified — the batch #3 FAIL's own remedy contract ("re-run the installed-layout A/B — the replica must BLOCK the variant-(i) event with exit 2" + "grep -c dispatch-chain-gate orchestrator-pattern.md must become ≥1"), re-exercised directly by this verifier against master @ 819cb1d6.

Comprehension-gate: PASS (confidence 8) — batch #3 inline audit stands unchanged for the base build; the REMEDY ROUND narrative additionally demonstrates exactly the comprehension the gate exists to test (the builder independently discovered that ~/.claude/config/ holds machine-local files the FAIL's own suggested remedy (a) would have destroyed, and shipped the per-file variant instead — verified real below).
Operator invariants: none registered (exit 3) — re-run 2026-08-04T06:20Z

Checks run (scoped: the two FAIL bases + remedy-round claims; all re-executed by this verifier on master @ 819cb1d6):
1. Ancestry: remedy commit 819cb1d6 is master HEAD; master 0/0 vs origin/master (fully pushed). PASS
2. FAIL BASIS 1 REMEDY, deploy path (R1a): install.sh's whole-dir loop still DELIBERATELY omits config (comment at install.sh:1294-1303 names the rm-rf hazard); a dedicated PER-FILE block (install.sh:1333-1339, dry-run twin at :779-783) walks only repo-side config/ files through sync_file(). SCRUTINY of the sync_file loop as dispatched: sync_file (:1134) removes/replaces exactly one named $dst path, never the parent dir, and backup_if_real_file (:1103) hash-verifies a backup BEFORE any removal; the `find . -type f` walk iterates ONLY $ADAPTER_DIR/config, so live-only files are never touched by construction. Live ~/.claude/config/ confirmed to hold exactly the machine-local files the builder named (active-repos.txt, active-repos.txt.bak-*, register-path) and NEITHER gate dependency — the hazard was real. `install.sh --dry-run` against the REAL live ~/.claude: all 11 repo config files listed individually as [WOULD CREATE]; active-repos.txt/register-path appear nowhere; "Dry run complete. No changes made." PASS
   (Latent-only note, non-blocking: the per-file walk is recursive but only `mkdir -p $CLAUDE_DIR/config` at top level — a FUTURE subdirectory under repo config/ would need a per-file parent mkdir; current config/ is flat, 11 files.)
3. FAIL BASIS 1 REMEDY, auto-install path (R1a): SYNC_SUBDIRS now carries config (session-start-auto-install.sh:98); _subdir_ext generalized to an extension SET. Self-test re-run by verifier: 22 passed, 3 failed — the 3 are exactly the pre-existing SELF-SYNC-01 trio (golden-scenario / settings-merge-guard / prune-guard), the Windows-symlink-environmental failures the builder A/B-proved on unmodified HEAD. Per dispatch: noted, NOT held against T17. PASS
4. FAIL BASIS 1 REMEDY, loud fallback (R1b): _dcg_build_types (:370-382) and _dcg_grandfathered (:416-426) now emit stderr WARNs naming the missing file + "DEGRADED" + the fix path + an env-var override; 6 config-absent scenarios assert on the WARN TEXT (silent vs loud fail-open share an rc, so rc alone could not prove this). All pass in the 49/49 run below. PASS
5. THE DECISIVE A/B, RE-RUN BY THIS VERIFIER (fresh replicas built from master @ 819cb1d6 bytes, fresh throwaway chain-less probe repo): replica A (hooks+lib+sibling config/) ← variant-(i) chain-less builder event → **exit 2 BLOCK**, all four GATE fields, chain-presence FAIL detail; replica B (identical bytes, NO config/) ← SAME event → exit 0 fail-open **but LOUD**: WARN naming config/model-policy.json's exact missing path + "DEGRADED" + the deploy fix. The pre-fix silent no-op is gone; the plan's Failure-modes contract ("never silent") now holds on the degraded path, and the deployed layout (A) is what install.sh/auto-install now produce. PASS
6. Suite: dispatch-chain-gate.sh --self-test re-run by verifier → 49 passed, 0 failed (of 49). PASS
7. FAIL BASIS 2 REMEDY (R2): grep -c "dispatch-chain-gate" doctrine/orchestrator-pattern.md → 1 (line 17, the G2 gate step bullet); byte count 2998 ≤ 3000 (cap holds); the T15 dispatch-ledger note ("Verify obligations (OD-022)") independently present → the twice-falsified premise is now discharged. PASS
8. R3 (non-blocking item from batch #3): registry header's "Regenerate with" command now pipes every slug through sha256sum (g2-grandfather-slugs.txt:36-49), matching the membership-test convention; registry = 284 pure sha256 lines (T21's drain shrink), 0 non-hash non-comment lines. PASS
9. Cleanup residual from batch #3: local branch worktree-agent-a38c63c69628eb5a9 (plaintext registry blob at 78e67de3) is DELETED — no branch contains 78e67de3 (dangling object pending gc, never pushed). PASS
10. Live-machine convergence (honest note, non-blocking per the remedy contract's replica clause): live ~/.claude/hooks/dispatch-chain-gate.sh is still PRE-fix bytes (0 "DEGRADED" matches) and live config/ lacks both gate files — this session's SessionStart predates the merge. HYPOTHESIZED: next SessionStart syncs both (hooks + config now both in SYNC_SUBDIRS; master pushed 0/0); REFUTED if a fresh session's live gate still lacks the DEGRADED string or config/ stays undeployed. Manifest honest_status still says 40/40+43/43 vs the actual 49/49 — count staleness for the orchestrator's next manifest touch, non-blocking.

DEPENDENCY TRACE (installed-form path, the FAIL-basis-1 chain)
================
Step 1: repo config/ (model-policy.json, g2-grandfather-slugs.txt) committed on master
  ↓ Verified at: install.sh:1333-1339 (per-file sync) + session-start-auto-install.sh:98 (SYNC_SUBDIRS)
Step 2: installed layout = hooks/dispatch-chain-gate.sh + sibling config/
  ↓ Verified at: install.sh --dry-run listing all 11 config files [WOULD CREATE]; replica A construction
Step 3: gate resolves _dcg_dir/../config and BLOCKS a chain-less build dispatch
  ↓ Verified at: replica-A A/B run, exit 2 with GATE contract fields (this verifier, 2026-08-04)
Step 4: degraded layout (config missing) fails open LOUDLY, never silently
  ↓ Verified at: replica-B run (WARN + DEGRADED) + 6 config-absent self-test scenarios in the 49/49 suite

Runtime verification: command bash adapters/claude-code/hooks/dispatch-chain-gate.sh --self-test   # → 49 passed, 0 failed (verifier re-run on master @ 819cb1d6)
Runtime verification: command bash adapters/claude-code/install.sh --dry-run   # → 11× "[WOULD CREATE] ~/.claude/config/<file>"; active-repos.txt/register-path untouched; "Dry run complete."
Runtime verification: command CLAUDE_TOOL_INPUT='<variant-i chain-less builder event>' bash <replica-A>/hooks/dispatch-chain-gate.sh   # → exit 2 BLOCK (replica WITH config/); same event vs replica WITHOUT config/ → exit 0 + "DEGRADED" WARN naming the missing file (the remedy-contract A/B, re-run by this verifier)
Runtime verification: command grep -c "dispatch-chain-gate" adapters/claude-code/doctrine/orchestrator-pattern.md   # → 1 (was 0 at batch #3); wc -c → 2998 ≤ 3000
Runtime verification: command bash adapters/claude-code/hooks/session-start-auto-install.sh --self-test   # → 22 passed, 3 failed — exactly the pre-existing SELF-SYNC-01 symlink trio (environmental, A/B-proven on unmodified HEAD)

Verdict: PASS
Confidence: 9
Reason: PROVEN: both batch #3 FAIL bases are remedied and re-observed by this verifier's own falsification attempts — (1) the installed form now has a real deploy mechanism (per-file, non-destructive, dry-run-proven against the real live machine) and the residual missing-config case degrades LOUDLY (A/B re-run: exit 2 with config, exit 0 + DEGRADED WARN without — same event, same bytes); (2) orchestrator-pattern.md carries the G2 gate step at 2998/3000 bytes. 49/49 re-run, R3 fixed, plaintext-blob branch purged. Checks 1-7 of batch #3 stand. The only open items are HYPOTHESIZED-and-refutable convergence notes (next-SessionStart live sync; manifest count staleness), neither of which is a mechanism gap.

## Task 21 — Verifier verdict (task-verifier, batch #4) + comprehension adjudication

EVIDENCE BLOCK
==============
Task ID: 21
Task description: REQ-C2 estate drain (after Task 17): 10 verified-safe worktrees pruned; 135 nl-issues triaged via the mechanized supersession sweep + dispositions; 23 stale ACTIVE plans dispositioned; the 1,254 alerts: execute the 36%-clearing route fix or explicitly re-own it, disposition the remainder — Verification: full — Implements: REQ-C2
Verified at: 2026-08-04T06:35:00Z
Verifier: task-verifier agent

Oracle: specified — the task's three Prove-it-works counts, re-derived live by this verifier from the estate itself (git, the plans directory, the nl-issues ledger, the alerts store, the registry), against the drain record + execution log (docs/reviews/2026-08-03-estate-drain-record.md, commits 18872a88 + fe4e14a5).

Comprehension-gate: ADJUDICATED PASS-WITH-NOTED-GAP (inline, per the orchestrator's recovery-precedent directive) — the canonical articulation is UNRECOVERABLE: this verifier scanned ALL 824 lines of the builder transcript (~/.claude/projects/C--Users-misha-claude-projects-neural-lace/4a470c8c-e5e4-49bb-a8f8-131206e35b58/subagents/agent-a05a34c3229e0a919.jsonl) — no assistant-authored "Spec meaning" block exists anywhere; every "Comprehension Articulation"/"Spec meaning" hit is the dispatch prompt's own instruction text or a quoted commit subject. The builder never wrote one (builder-discipline defect, noted for the orchestrator; same class as the T7/T11/T14/T15/T19 recovery incidents but with nothing to recover). Adjudication substance, per the gate's actual purpose (FM-023): the builder-authored drain record + final report together articulate spec meaning (REQ-C2's four piles + D-12 disposition discipline + the worktree-isolation scope split), covered edge cases (live-moving estate with re-check guidance; a corrected wrong citation inherited from the prior triage; the do-not-prune flags that saved the then-unmerged T25 build), NOT-covered items (malformed alert classes not re-swept; SLOW class not re-investigated; tier-2 subject-match limits), and assumptions — and every count re-derives (below). ONE precision defect found and already caught downstream: the EXECUTE list's Tier-3 comments claimed "re-confirmed ancestor-of-master rc=0 today" in a wording that reads as TIP-level ancestry; this verifier re-ran the checks — the three TIPS (7afffe07/390dc65e/4c940b7b) are NOT ancestors (rc=1), only the landed-via SHAs (d805a9a3/4ee18805/3ab7fa50+81e8d031) are. The orchestrator's execute-time re-verification caught exactly this, held all three, and logged it honestly — the pipeline worked; consequence safe (nothing forced, nothing lost).
Operator invariants: none registered (exit 3) — re-run 2026-08-04T06:20Z

Checks run (all re-executed by this verifier on master @ 819cb1d6, 2026-08-04):
1. Ancestry: 585ea4da/91c3d8a0/683cd996/8e4073b2/18872a88 (builder commits, via merge d0aeb643) + fe4e14a5 (execution log) all ancestors of master. PASS
2. Prove-it #3 — ACTIVE plan census re-derived: grep -l "^Status: ACTIVE" docs/plans/*.md → EXACTLY 3 (gated-pipeline-master-2026-08 + accountable-estate-program-2026-07 + cockpit-roadmap-redesign — precisely the record's carve-out + 2 STAYS-ACTIVE). 3 ≤ 5. PASS
3. Prove-it #2 — untriaged nl-issues re-derived: nl-issue.sh --list --untriaged → 8 (the drain's deliberate 5 holdbacks — lines 83/112/113/181/187, each named with a real reason — plus 3 post-drain live-session accruals incl. the drain's OWN gate-friction filing [197]). 8 < 20; 170→5 at drain end confirmed plausible against the ledger. PASS
4. Prove-it #1 — worktree prune re-derived: current census = 11 agent-* worktrees (42 classified − 33 removed − 1 self-cleaned + 3 new post-drain dispatches + the honored holds), i.e. the count dropped by 33 (target ≥10, ~3×) with ZERO unmerged-content loss: `git worktree remove` without --force throughout; do-not-touch trio honored (all three since merged: d0aeb643 / 346646c3 / 1cb3d2bb — verified ancestors). PASS
5. Held-back 5, honesty probe (dispatch-directed): tier-3 tips 7afffe07/390dc65e/4c940b7b re-checked — genuinely NOT ancestors (holds correct; the record's comment wording overclaimed, the exec log's correction is accurate); dirty pair re-checked — agent-a87622c2020ce66a5 and agent-a411c11a6438d7354 each carry a real uncommitted `M docs/backlog.md` (git's refusal was genuine). All 5 holds honestly documented, none forced. PASS
6. Alerts re-derived: store = 1287 json files, 759 .acked markers (EXACTLY the record's 21 pre-existing + 738 new), 528 unacked (the record's 524 + live accrual in the still-firing class). The ~38% class (493 webhook-retell|UNEXPECTED_STATUS files) is EXPLICITLY re-owned to the operator in drain-record §4 (owner + fix location + why-left-unacked rationale) and repeated in Follow-ups — recorded, not silently dropped. Bulk-ack was marker-file-only (append-only, no data destroyed). PASS
7. Grandfather registry: 284 sha256 entries (300 − 16, one per COMPLETED plan), 0 non-hash non-comment lines. PASS
8. Docs impact: drain record exists at docs/reviews/2026-08-03-estate-drain-record.md with the execution log appended (fe4e14a5); the plan's own Decisions Log carries the Files-to-Modify amendment entry per the scope-gate's option 1. PASS
9. Catalog check: no FM match on the executed work; the missing articulation is FM-023-process-adjacent (articulation discipline), adjudicated above.

Runtime verification: command grep -l "^Status: ACTIVE" docs/plans/*.md | wc -l   # → 3 (Prove-it #3, re-derived by verifier)
Runtime verification: command bash ~/.claude/scripts/nl-issue.sh --list --untriaged   # → 8 entries (< 20; 5 drain holdbacks + 3 live accruals) (Prove-it #2)
Runtime verification: command git merge-base --is-ancestor 7afffe07 master; echo $?   # → 1 (tier-3 hold verified correct: tip NOT ancestor; d805a9a3/4ee18805/3ab7fa50/81e8d031 all ARE ancestors)
Runtime verification: command ls ~/.claude/state/external-monitor-alerts/*.acked | wc -l   # → 759 (= 21 pre-existing + 738 bulk-acked this drain, exact match)
Runtime verification: command grep -cE '^[0-9a-f]{64}$' adapters/claude-code/config/g2-grandfather-slugs.txt   # → 284 (registry shrink, REQ-C2's letter)
Runtime verification: file docs/reviews/2026-08-03-estate-drain-record.md::Execution log (orchestrator, 2026-08-04)

Verdict: PASS
Confidence: 8
Reason: PROVEN: all three Prove-it-works counts re-derived live by this verifier and hold with the drain record's own live-estate tolerance (3 ACTIVE; 8 untriaged; 33 pruned with zero loss); the five holds re-probed and confirmed honest (tier-3 tips genuinely non-ancestors, dirty pair genuinely dirty); the alert re-own is explicit and durable; the registry shrink is exact. The comprehension articulation was never authored — adjudicated inline per the orchestrator's directive with the substance audited from the builder's own artifacts; the one precision defect (tier-3 comment wording) was already caught and honestly corrected by the execution log. Confidence capped at 8 (not 9) for the adjudicated-rather-than-canonical comprehension path and live-drift tolerance on two counts.

## Task 25 — Verifier verdict (task-verifier, batch #4) — FAIL, checkbox NOT flipped

EVIDENCE BLOCK
==============
Task ID: 25
Task description: OPERATOR DIRECTIVE 2026-08-03 (merge→verify mechanization): (a) OD-022 registered + regenerated view; (b) verify-obligation tracking on T15's dispatch ledger; (c) G2 WIP-limit BLOCK at ≥3 open obligations with no verifier in flight, ledgered waiver; (d) stop-side refusal of DONE/CONTINUING with open unnamed obligations — Verification: full — Implements: operator directive 2026-08-03 / OD-022
Verified at: 2026-08-04T06:35:00Z
Verifier: task-verifier agent

Oracle: specified — the task's §10 evidence bar (golden-scenario fixture replay; two-state stop proof; FP rate + retirement in the gate header) PLUS the harness-reviewer's CONDITIONAL-PASS conditions C1-C6, each re-executed or re-probed directly by this verifier on master @ 819cb1d6.

Comprehension-gate: PASS (confidence 9) — inline audit of the committed articulation (de630284, evidence file "Task 25 — Comprehension Articulation"): spec paraphrase faithful to the four deliverables incl. the honest pre-stop-verifier-was-a-retired-shim discovery (backlog row STALE-PRE-STOP-VERIFIER-DOC-REFERENCE-01 verified present); every cited covered-edge-case scenario EXISTS and PASSES in this verifier's own re-runs (obl5/obl6/obl7/obl4/obl4b in the 35/35; DL8-DL14 in the 150/150; golden + waive-ledgered in the 10/10); NOT-covered list genuine (cross-machine marker visibility, DONE-refusal interaction, bare-slug arg, scale perf, OD-023 role-fitness — none contradicted by the diff); assumptions sound; the DL11-DL14 vacuity-bug self-catch and the declined mid-build relay (adjudicated right by harness-reviewer, Decisions Log d1d20320) are exemplary §1 conduct.
Operator invariants: none registered (exit 3) — re-run 2026-08-04T06:20Z

Checks run (all re-executed by this verifier on master @ 819cb1d6, 2026-08-04):
1. Ancestry: cca6c273/6bd835de/de630284 (build, via merge 346646c3) + 4c8f73aa (C-round merge) + ca0fa1da (C6 citations) + d1d20320 (manifest train) all ancestors of master. PASS
2. C1 — WIP-limit consult WIRED live: _dcg_check_wip_limit called in BOTH _dcg_gate RC_VERDICT arms (PASS) and WARN), dispatch-chain-gate.sh ~:696/:707), rc=3 fails OPEN with a WARN (never fail-closed on internal error), rc=1 → return 2. Suite re-runs by verifier: --self-test 49/49 (incl. the three c1-* scenarios), --self-test-wip-limit 10/10 (incl. the §10 golden replay: 3-open-no-verifier BLOCKS naming tasks + all four GATE fields; verifier rows added → exit 0; --waive → exit 0 + workaround-sensor ledger row). PASS
3. C2 — arity guard PROBED live: `timeout 20 dispatch-chain-gate.sh --check-wip-limit <this plan> --waive` (trailing, valueless) → immediate exit 2 + usage line naming "--waive requires a value"; no hang (the pre-fix infinite loop is gone). PASS
4. C3 — all three parts verified: gate header now states the STRICT-NEWER semantics and names the prior "never trips" wording as PROVEN FALSE (dispatch-chain-gate.sh:125-137, RETIREMENT CONDITION at :145); obl4b-stale-verifier-marker-still-blocks exists and PASSES (35/35 re-run); the actively-misleading G2 --waive stop-remedy is REMOVED — stop-verdict-dispatcher's obligation remedy text (:827, :1343) now names only dispatch-verifier / name-in-marker. PASS
5. C4 — lib-sourcing guard PROBED live: genuine slash-less invocation (`cd hooks && bash dispatch-chain-gate.sh --check-wip-limit …`) → exit 3, loud FATAL naming rc_wip_limit_decision/gc_block undefined + _dcg_dir='<empty>' + the fix; path-qualified invocation → real decision, exit 0. Distinct from both 0/proceed and 1/block, exactly as specified. PASS
6. C5 — byte caps: orchestrator-pattern.md 2998/3000, planning.md 2986/3000; BOTH compacts carry the obligation step ("Verify obligations (OD-022): open ledger row blocks builder @3+; Stop refuses unnamed DONE") — the task's Docs-impact letter (orchestrator-pattern + planning) is satisfied. PASS
7. C6 part 1 — schema citations: review-chain-lib.sh:50-52 and tests/fixtures/review-chain/README.md both cite the real 7-field shape ({…, task_id, task_id_valid}) with the rule-3-reads-5-fields note (ca0fa1da). PASS
8. **C6 part 2 — FAIL BASIS: the two claimed backlog follow-ups were NEVER FILED.** The C-round evidence states "C6: two follow-ups filed to docs/backlog.md (session_id-scoped obligations; an estate-wide ${BASH_SOURCE[0]%/*} dir-resolution fragility sweep)". Verifier search: docs/backlog.md contains NEITHER row (greps for session_id-scoped / BASH_SOURCE / dir-resolution / fragility / estate-wide: zero matching rows); `git log --all -S "session_id-scoped"` shows the string only ever entered THIS evidence file (ca0fa1da) — never docs/backlog.md in any commit (so not filed-then-absorbed either); the nl-issues ledger's 3 obligation-mentioning rows are all unrelated; the T25 worktree tip (ca0fa1da) is fully merged, so no unmerged commit carries them. The filing claim is FALSE on master — FM-006 class (self-reported completion without evidence), inside the very evidence entry whose neighboring item discloses a caught instance of the same failure shape. FAIL
9. Two-state stop proof (§10 item 2): stop-verdict-dispatcher.sh --self-test RE-RUN IN FULL by this verifier against CURRENT master bytes (post-C3) → 99 passed, 0 failed, incl. obligation-check-open-and-unnamed-blocks / gap-carries-right-check-id / block-names-all-open-tasks / closed-obligations-pass. The evidence's disclosed skip ("99/99 is from de630284, pre-C3 text edit, not re-verified") is now DISCHARGED — no skip remains. PASS
10. Writer side: workstreams-emit.sh --self-test re-run by verifier → 150 passed, 0 failed (DL8-DL14 task-id extraction + OD-023 write-time validation + --open-verify-obligations round-trip). PASS
11. Register + view + manifest: OD-022/OD-023 present with verbatim operator instruction, BINDING, absorbs AUTO-VERIFY-DISPATCH-2026-08-03 (row confirmed deleted from backlog); dr_validate → rc 0; docs/operator-directives.md carries both sections; d1d20320's four manifest entries all carry honest T25 annotations (incl. the pre-C3 disclosure this verifier's re-run now supersedes). PASS

DEPENDENCY TRACE (user action → observable outcome)
================
Step 1: builder-complete dispatch lands → ledger row with task_id
  ↓ Verified at: workstreams-emit --self-test 150/150 (DL8-DL14) + review-chain-lib s11 writer round-trip
Step 2: 3 open obligations, no verifier in flight → next builder dispatch BLOCKED naming tasks
  ↓ Verified at: --self-test-wip-limit 10/10 golden replay (verifier re-run) + C1 wiring in both _dcg_gate arms
Step 3: verifier rows / --waive → dispatch proceeds (waiver ledgered)
  ↓ Verified at: golden-after-verify-rows-passes-exit0 + waive-ledgered-to-workaround-sensor (10/10)
Step 4: DONE/CONTINUING end with open unnamed obligations → Stop refused once, naming tasks
  ↓ Verified at: stop-verdict-dispatcher --self-test 99/99 on current bytes (verifier re-run), scenarios 36/37

Runtime verification: command bash adapters/claude-code/hooks/lib/review-chain-lib.sh --self-test   # → 35 passed, 0 failed (verifier re-run; obl1-obl7 + obl4b + norm-task-id + s11 writer round-trip)
Runtime verification: command bash adapters/claude-code/hooks/dispatch-chain-gate.sh --self-test-wip-limit   # → 10 passed, 0 failed (verifier re-run; §10 golden scenario replay)
Runtime verification: command bash adapters/claude-code/hooks/stop-verdict-dispatcher.sh --self-test   # → 99 passed, 0 failed (verifier FULL re-run on master @ 819cb1d6, post-C3 bytes — discharges the disclosed skip)
Runtime verification: command bash adapters/claude-code/hooks/workstreams-emit.sh --self-test   # → 150 passed, 0 failed (verifier re-run)
Runtime verification: command timeout 20 bash adapters/claude-code/hooks/dispatch-chain-gate.sh --check-wip-limit docs/plans/gated-pipeline-master-2026-08.md --waive; echo $?   # → usage error + exit 2, no hang (C2 probe)
Runtime verification: command cd adapters/claude-code/hooks && timeout 20 bash dispatch-chain-gate.sh --check-wip-limit <abs-plan-path>; echo $?   # → FATAL lib-sourcing message + exit 3 (C4 probe)
Runtime verification: command grep -n "session_id-scoped\|BASH_SOURCE" docs/backlog.md   # → NO matching rows (the C6-part-2 FAIL basis; must become 2 rows)

Verdict: FAIL
Confidence: 9
Reason: PROVEN (the build): all four deliverables (a)-(d) are real, wired, and re-observed — five suites re-run green by this verifier (35/35, 49/49, 10/10, 99/99 on current bytes, 150/150), both live probes (C2 arity, C4 slash-less) behave exactly as specified, the register/view/manifest/Decisions-Log train landed, and the previously-disclosed stop-suite skip is now discharged by a full re-run. PROVEN (the gap): condition C6 of the harness-reviewer's CONDITIONAL-PASS is only half-executed — the two follow-up backlog rows the evidence claims were "filed to docs/backlog.md" do not exist there, in the nl-issues ledger, or anywhere in git history (git -S proves the string only ever entered the evidence file). A false filing claim in evidence is itself the defect this pipeline exists to catch; the checkbox cannot flip while a review condition is unmet and its evidence overstates.
Gaps:
  - C6 follow-up rows never filed (Class: FM-006 self-reported-completion-without-evidence / unmet review condition; Sweep query: grep -n "session_id-scoped\|BASH_SOURCE" docs/backlog.md → currently 0 rows, must become 2; Required generalization: an evidence sentence of the form "filed to <ledger>" must only be written AFTER the row exists — same rule the adjacent C6 self-correction already articulates for checks. Remedy, one commit: (1) add the two rows to docs/backlog.md — "session_id-scoped obligations" (obligations currently count across all sessions of a plan; a second session's builder dispatch can be blocked by another session's open obligations — evaluate per-session scoping) and "estate-wide ${BASH_SOURCE[0]%/*} dir-resolution fragility sweep" (the class C4 fixed one instance of; sweep every hook/lib for slash-less-invocation dir-resolution breakage); (2) append a one-line correction to the C-round evidence entry noting the rows were filed at <new SHA>, not at ca0fa1da as originally claimed. Re-verification: the grep above returns both rows + the correction line exists.)
---

## Task 22 — REQ-C3+C4: honest scorecard in the dashboard snapshot + DEC-6/DEC-7 recorded in the brief — Verification: contract

- Builder: plan-phase-builder (sonnet), PARALLEL worktree dispatch (`.claude/worktrees/agent-a80a36dcccb913089`, HEAD 819cb1d6).
- Files: `adapters/claude-code/scripts/nl-maintenance.sh` (extended — two new counting functions
  `_nm_count_scheduled_tasks_census` + `_nm_count_net_artifact_delta`, wired into
  `_nm_refresh_dashboard_snapshot`'s existing payload; self-test Scenarios 8, 16, 17) ·
  `docs/designs/harness-execution-redesign-considerations-2026-08-02.md` (§2 invariant 8 amended
  in place — DEC-6; §5 D5 amended in place — DEC-7; changelog line added) · this file.
- HONESTY BAR (task's own text): these numbers are unflattering by design and are recorded as-is,
  no spin. The dashboard is the EXISTING artifact `nl-maintenance.sh` already emits
  (`snapshots/dashboard.json`, `_nm_refresh_dashboard_snapshot`) — extended in place, not duplicated.

### The four metrics — each ONE recomputable number, exact command, verbatim output

**(a) Net-artifact delta** — `git diff --stat` file census restricted to `adapters/claude-code/**`,
between the program's start tag (predecessor plan's first commit) and HEAD.

Start-tag re-derivation:
```
$ git log --follow --format=%h -- docs/plans/archive/harness-execution-redesign-2026-08.md | tail -1
3945d47e
```
(Confirmed via `git show --stat 3945d47e` — commit message: "plan(execution-redesign): round-3
revamp folded into the brief + staged build plan (operator GO 2026-08-02d)", the predecessor
plan's own creation commit, later moved to `docs/plans/archive/` — `--follow` traces the rename.)

Census (added/modified/deleted, rename-detected):
```
$ git diff --name-status -M 3945d47e HEAD -- adapters/claude-code/ | cut -c1 | sort | uniq -c
     44 A
     45 M
```
No `D` rows and no `R` rows (rename detection `-M` produces the identical 44/45 split — nothing
was actually renamed). **Net-artifact delta = 44 added − 0 deleted = +44** under
`adapters/claude-code/**` since program start. This is materially larger than the "net +≈14
artifacts" figure recorded earlier in
`docs/handoffs/2026-08-03-EXHAUSTIVE-issue-inventory.md:262` — that figure was an approximate,
undated-command snapshot taken before Tasks 15/18/20 (dispatch-ledger, review-record gate class
config, directives carriage) landed; +44 supersedes it as the exact, recomputable number, per this
task's own honesty bar ("these numbers will be unflattering").

**(b) Hooks-per-Bash (live)** — counted exactly the way `budget-bash-hooks`
(`harness-doctor.sh:_count_bash_hooks`) counts it: total hook entries across every `PreToolUse`
matcher block whose `matcher` string contains `"Bash"`.
```
$ jq -r '[(.hooks.PreToolUse // [])[] | select(.matcher // "" | contains("Bash")) | (.hooks // []) | length] | add // 0' ~/.claude/settings.json
25
```
Template (`adapters/claude-code/settings.json.template`) is also 25 — no live/template drift.
Target per R3.3: ~5 per-category stubs (Stage 2, admission-triggered by Task 24/REQ-C6 — not yet
open). Unflattering as expected: unchanged from the redesign program's own start (25 → 25, cited
in the REAL architecture review Q2 table).

**(c) SessionStart spawns (live)** — same source, same method (total hook entries across every
`SessionStart` matcher block):
```
$ jq -r '[(.hooks.SessionStart // [])[] | (.hooks // []) | length] | add // 0' ~/.claude/settings.json
8
```
Template also 8. Target per R3.3: 1–2. Down from the program's original 16 (Stage 1's
consolidation), still 4-6× the target.

**(d) Machine-census scheduled tasks (enabled)** — HR-F12 fix: the dashboard's PRE-EXISTING
`legacy_scheduled_tasks_enabled.count` field counts only `schedule-manifest.json` mechanisms with
a non-null `legacy_task_name` (currently 0 of 5 enabled — all five legacy `NL-*` tasks stay
disabled per rollback policy). HR-F12 (`docs/reviews/2026-08-03-stage0-stage1-harness-review.md`
F12) proved that undercounts the real machine footprint: `downstream-product-health-monitor`
carries `legacy_task_name: null` yet has a live, Enabled `NL-product-health-monitor` schtasks
entry the old count never saw. The honest census enumerates every schtasks entry whose name starts
with `NL-` (the harness's own registration convention), independent of manifest content:
```
$ schtasks /Query /FO CSV | tr -d '\r' | grep -F '"\NL-' | grep -c '"Ready"$'
1
```
(Only `NL-product-health-monitor` is Enabled; `NL-CoordSync`, `NL-health-tick`,
`NL-session-resumer`, `NL-SupervisorTick`, `NL-workstreams-heartbeat` are all Disabled —
confirmed via `schtasks /Query /FO CSV | grep -i "NL-"`.) **Machine-census count = 1**, within the
design's ≤2 target — an improvement on HR-F12's measured-at-review count of 3
(`downstream-product-health-monitor` + 2 others were enabled at that point in the build; the
build's own 5 legacy tasks have since been disabled per policy, leaving only the one honestly-new
task). Both numbers now ship side by side in the dashboard (`count` = manifest-subset,
`machine_census_enabled` = honest total) so the HR-F12 gap stays visible, not just fixed once.

### Dashboard snapshot — end-to-end, live

```
$ bash -c "source adapters/claude-code/scripts/nl-maintenance.sh; _nm_refresh_dashboard_snapshot 1; cat \"\$(_nm_dashboard_path)\"" | jq '.inventory'
{
  "hooks_per_bash": { "template": 25, "live": 25, "target": 6 },
  "sessionstart_spawns": { "template": 8, "live": 8, "target": 2 },
  "legacy_scheduled_tasks_enabled": { "count": 0, "target_max": 2, "machine_census_enabled": 1 },
  "net_artifact_delta": { "value": 44, "restricted_to": "adapters/claude-code/**", "target": "<=0 (anti-bloat, D-07)" }
}
```
Live snapshot path: `~/.claude/state/nl-maintenance/snapshots/dashboard.json` (this session's
machine). This is the EXISTING artifact the task names — extended, not duplicated.

### Cross-check against the design's §7 anti-bloat ledger

`docs/designs/gated-pipeline-master-2026-08-03.md` §7's "Net" row states the gated-pipeline
DESIGN's own incremental additions: "+2 agents, +2 thin gates, +2 libs, +1 config+generator, +1
script, +1 template" against a named displacement list. This is a SUBSET of the +44 program-wide
total above (program start = predecessor plan's Stage 0/1, not this design's own start), and the
two numbers are expected to differ, not match:

- **+2 agents** — confirmed: `agents/design-author.md`, `agents/plan-fidelity-reviewer.md` both
  appear as `A` rows.
- **+1 template** — confirmed: `templates/design-template.md`.
- **+1 config+generator / +1 script** (directives) — confirmed: `config/operator-directives.json`,
  `scripts/gen-directives-view.sh`, `scripts/dispatch-directives.sh` all appear as `A` rows.
- **+2 thin gates — PARTIALLY MISMATCHED, recorded honestly:** the ledger names
  `hooks/design-ref-gate.sh` (G1) as a new thin gate file; it does not exist in the diff or the
  repo — G1's logic was folded into the EXISTING `plan-reviewer.sh` instead (confirmed:
  `grep -l "design-ref-gate\|REQ-B8" adapters/claude-code/hooks/*.sh` →
  `dispatch-chain-gate.sh plan-reviewer.sh`, not a new `design-ref-gate.sh` file — the design-ref
  Checks 20-22 logic lives in `plan-reviewer.sh:2039-2172`).
  Only `hooks/dispatch-chain-gate.sh` (G2) materialized as a genuinely new gate file; G3 is
  correctly described as an extension (`review-record-push-gate.sh` + `config/review-class-table.json`,
  the latter also an `A` row). Net: 1 new gate file shipped where the ledger's prose implies 2 — a
  real, minor fidelity gap between the design's own ledger and what was actually built, surfaced
  here rather than papered over.
- **+2 libs — UNDERCOUNTED by the ledger's own scope, correctly so:** 5 new `hooks/lib/*.sh` files
  appear in the `A` rows (`directives-register-lib.sh`, `gate-contract-lib.sh`,
  `review-chain-lib.sh`, `single-flight-lib.sh`, `workaround-sensor-lib.sh`). The ledger names only
  `review-chain-lib.sh` and `directives-register-lib.sh` as ITS additions — correctly, since
  `gate-contract-lib.sh`, `single-flight-lib.sh`, and `workaround-sensor-lib.sh` are predecessor-plan
  (Stage 0b/HR-F1/HR-F6) artifacts that predate this design cycle and are out of §7's scope by
  construction (§7 scopes to "every addition [this design cycle] makes", not the whole program).
- **The remaining ~30 `A` rows** (doctrine `-full.md` rewrites, `nl-maintenance.sh` itself,
  darwin/Windows installer scripts, `measure-design-ref-surface-trigger.sh`,
  `tests/bench-admission-hotpath.sh`, 12 test-fixture files) are predecessor-plan (Stage 0/1)
  artifacts, correctly absent from this design's own §7 ledger for the same reason. §7 was never
  meant to reconcile to +44 — it accounts for its own design's slice; the cross-check's honest
  finding is the G1-file gap above, not a magnitude mismatch.

### DEC-6 / DEC-7 — recorded in the considerations brief body

`docs/designs/harness-execution-redesign-considerations-2026-08-02.md`:
- §2 invariant 8 (line ~55): amended in place with an `**AMENDED 2026-08-03**` inline note citing
  the REAL architecture review's load-bearing premise 7 (F4) + Q2 item 1 + Q3 row 4 — the shipped coarse first-approximation
  fingerprint (`harness-doctor.sh:_doctor_compute_fingerprint`) is now the invariant's stated
  shipped form, not a deviation from it; full per-check declared-input machinery REJECTED per
  DEC-6, citing `docs/designs/gated-pipeline-master-2026-08-03.md` §3.
- §5 D5 (line ~224, after the existing `My pick`/`Reply with` lines): amended in place with a
  `**RESOLVED 2026-08-02** ... **cold-target re-scoped 2026-08-03**` paragraph citing the same
  review's Q3 row 1 + F2b (PROVEN: 9 m 12 s clean-sandbox cold measurement) — the cached contract
  (`ttl-30m`) stands unchanged; the previously-unstated cold-doctor target is re-scoped per DEC-7:
  cached < 2 s remains the closure bar, no fixed cold number ships until top-N check profiling.
- Top-of-file `**Changelog:**` line (line 5): extended (not replaced) with a dated
  `2026-08-03 ... Task 22, REQ-C4` entry naming both amendments and their locations, matching the
  changelog convention Task 19 established.
- No `## Addendum` / `## Round N` heading was introduced anywhere — both amendments are inline
  prose within existing sections. Confirmed via a direct run of the no-addendum lint against the
  amended file:
```
$ bash adapters/claude-code/hooks/harness-hygiene-scan.sh "docs/designs/harness-execution-redesign-considerations-2026-08-02.md"; echo "exit=$?"
exit=0
```

### Self-tests (verbatim, full suite re-run on the committed state)

```
$ bash adapters/claude-code/scripts/nl-maintenance.sh --self-test
...
Scenario 16: REQ-C3 net-artifact-delta arithmetic (Task 22) -- a REAL git fixture repo with a known start commit and a known set of adds/deletes under adapters/claude-code/** proves the counting logic itself, not just that it degrades honestly
PASS: S16a net delta = 2 added - 1 deleted = 1, restricted to adapters/claude-code/** (the outside-scope add/modify never counted)
PASS: S16b a directory with no .git degrades to empty (never a fabricated 0)
Scenario 17: REQ-C3 machine-census scheduled-task count (HR-F12, Task 22) never crashes and always returns numeric-or-empty, independent of any fixture manifest
PASS: S17 machine-census returns numeric-or-empty ('1'), never a crash or non-numeric value

self-test interpreter: 5.2.37(1)-release
self-test summary: 49 passed, 0 failed
```
All 49 scenarios pass (S1-S15 pre-existing/unaffected, S8 extended with two new assertions for the
`machine_census_enabled` and `net_artifact_delta` dashboard fields, S16-S17 new). A first version of
`_nm_count_scheduled_tasks_census` used `grep -i '"NL-'` and silently matched zero rows — PROVEN via
`od -c`: schtasks' CSV `TaskName` column prints root-folder tasks as `"\NL-...` (a literal backslash
between the opening quote and the name), so the quote-then-letter pattern never matched. Fixed to
`grep -F '"\NL-'` (fixed-string, sidesteps both the escaping bug and a separate PROVEN `grep -iF`
abort/SIGABRT on this machine's grep when `-i` and `-F` are combined).

### `bash -n` syntax check

```
$ bash -n adapters/claude-code/scripts/nl-maintenance.sh && echo "SYNTAX OK"
SYNTAX OK
```
