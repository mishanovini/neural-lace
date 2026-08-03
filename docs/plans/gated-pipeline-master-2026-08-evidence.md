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
Reason: PROVEN: the bootstrap self-review's full mechanical contract re-observed — committed substantive record (REFORMULATE → fixes → delta PASS with fresh attestation), chain entry appended with the canonicalized anchor, and the three-way blob equality recomputed independently by this verifier through the production lib rather than trusted from any artifact. The one deviation (protocol-host execution instead of registry dispatch) is disclosed in the record, the chain entry, and an nl-issue — honest, not silent.
