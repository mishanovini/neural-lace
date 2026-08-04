# Plan: harness-hygiene-scan self-service-escape incident fix
Status: ACTIVE
Execution Mode: single-session
Mode: code
Backlog items absorbed: none
acceptance-exempt: true
acceptance-exempt-reason: harness-internal mechanism work (pre-commit gate, shared lib, Stop-chain hook, SessionStart digest feed) with no user-facing UI surface; the self-test suites of each touched file ARE the acceptance oracle, per work-shapes/build-harness-infrastructure.md's harness-internal carve-out.
tier: 2
rung: 2
architecture: coding-harness
frozen: false
prd-ref: n/a — harness-development
design-ref: n/a — small, single-session incident fix dispatched directly by the operator; no design-doc cycle was run, matching the direct-dispatch harness-safety-fix shape (fix + self-test evidence + harness-reviewer, not a designed program).

## Intended Functionality

**Outcome (operator's terms):** When an agent's commit trips harness-hygiene-scan on a
personal/business/identity-bearing string, it can no longer quietly write itself a
waiver and ship the leak unnoticed — either the commit only ever touched content the
agent didn't add (and the gate says so instead of blocking), or the leak is real and
the agent is forced to stop and ask me before it can ship, and if it ever does use an
escape hatch I find out about it that same session and the next one, not a day later
by accident.

**Observation:** A commit whose staged diff never touches a denylisted line no longer
blocks even if the file historically contained one (delta-scoped scan). A commit whose
staged diff DOES introduce a denylisted line still blocks, and the block message no
longer hands the agent a fill-in-the-blank command to make it go away — it tells the
agent to stop and ask the operator. `bash adapters/claude-code/hooks/harness-hygiene-scan.sh --self-test` demonstrates both. Any gate escape used in a session shows up as a
`bypass-24h: <gate> <kind> x<n>` line in the next SessionStart digest, and the same
session's own Stop is blocked from ending DONE/CONTINUING unless it names the gate it
used an escape on (or the escape has since been fixed/acknowledged) —
`bash adapters/claude-code/hooks/stop-verdict-dispatcher.sh --self-test` and
`bash adapters/claude-code/hooks/session-start-digest.sh --self-test` demonstrate this.

**Deterministic pass/fail:** All four touched self-test suites (harness-hygiene-scan.sh,
lib/workaround-sensor-lib.sh, stop-verdict-dispatcher.sh, session-start-digest.sh) exit
0 with zero failures, including the specific pinned scenarios named in `## Testing
Strategy` below (the incident replayed as a fixture, the delta-scope false-fire case,
the escape-obligation block/pass/downgrade cycle).

**Explicitly NOT included:** Does not make a self-served escape technically
impossible — on a single-user machine there is no channel distinguishing "the operator
authorized this in chat" from "the agent wrote a file claiming so"; the fix makes a
self-served escape impossible to hide (same-turn notice, ledger record, digest
surfacing, Stop-blocking obligation), not impossible to commit. Does not add
FIXED-auto-close re-verification for any gate other than harness-hygiene-scan itself.
Does not wire the same-turn notice at the other four existing `ws_record` call sites
(concurrent-ownership-gate, dispatch-chain-gate, review-record-push-gate,
scope-enforcement-gate) — their escapes ARE obligation-tracked generically, just
without the in-turn heads-up yet (named follow-up in docs/backlog.md).

**Human dependencies:**
- None required at runtime — INTENDED (the whole point is the operator is no longer a
  required real-time approver for every hygiene-gate escape; they are pulled in only
  when an agent-authored waiver targets a genuine denylist hit, and even then only via
  the Stop-chain obligation and the digest surfacing, not a blocking synchronous ask).

## Goal
Fix the 2026-08-04 self-service-escape incident: four `bypass_kind=waiver-file` rows
against `harness-hygiene-scan` landed in `workaround-sensor.jsonl` from one session's
subagents with no operator turn — each was blocked, read the gate's own block message
(which printed the waiver recipe as a fill-in-the-blank command), self-authored the
waiver, and committed. Both underlying deltas were in fact clean; the gate had fired on
PRE-EXISTING content in the same files. Fix the false-fire engine, remove self-service
from the security class, make bypass usage visible in-session, and wire escapes onto an
accountability rail so a self-served escape can never again go unnoticed for a day.

## Scope
- **IN**: `adapters/claude-code/hooks/harness-hygiene-scan.sh` (delta-scoped pre-commit
  scanning; denylist/heuristic waiver-class split; operator-waiver marker); a new
  `feed_bypass_surface` feed in `adapters/claude-code/hooks/session-start-digest.sh`;
  escape-obligation tracking (`ws_open_escape_obligations`,
  `_ws_escape_ack_exists`, `_ws_escape_gate_fixed`) added to
  `adapters/claude-code/hooks/lib/workaround-sensor-lib.sh`; a matching
  `_svd_escape_naming_check` Stop-side check wired into
  `adapters/claude-code/hooks/stop-verdict-dispatcher.sh`; self-test coverage for every
  behavior above in each touched file; a `docs/backlog.md` entry naming the residual
  gaps.
- **OUT**: rewriting the denylist pattern set itself; changing the Layer 2 (heuristic)
  or Layer 3 (addendum-lint) detection logic (only their WAIVER eligibility changed,
  not their matching); wiring the same-turn notice at gates other than
  harness-hygiene-scan; adding FIXED-auto-close for any gate other than
  harness-hygiene-scan; touching `manifest.json`'s enforcement inventory (named as a
  follow-up, not done here); any change to `docs/plans/gated-pipeline-master-2026-08.md`,
  `docs/plans/cockpit-roadmap-redesign.md`, or
  `docs/plans/accountable-estate-program-2026-07.md` — this work is unrelated to those
  three concurrently-active plans and does not extend their scope.

Walking Skeleton: n/a — harness-internal work; the four self-test suites (one per
touched file, each exercising the real code path end-to-end: gate → waiver marker →
ledger row → digest feed / Stop check) are the end-to-end slice. No new user-facing UI
or API surface is introduced.

## Tasks
- [x] Delta-scope harness-hygiene-scan.sh's pre-commit path (`_hhs_build_delta_view`);
      preserve a non-blocking PRE-EXISTING notice for untouched pre-existing hits;
      leave `--full-tree` and explicit-file-arg modes whole-file, unchanged.
- [x] Split the waiver classes: the plain `harness-hygiene-waiver-*.txt` marker no
      longer suppresses a `[denylist]` match; a new `harness-hygiene-operator-waiver-
      *.txt` marker (Purpose/Because/Files + a required, non-placeholder
      `Operator-Authorized:` clause) is the only thing that can. Rewrite the block
      message's ESCAPE section to stop prescribing a self-service recipe for denylist
      hits.
- [x] Add `feed_bypass_surface` to session-start-digest.sh (new feed on the existing
      digest architecture) surfacing `bypass-24h: <gate> <kind> x<n>` per gate+kind in
      the last 24h.
- [x] Add `ws_open_escape_obligations` / `_ws_escape_ack_exists` / `_ws_escape_gate_fixed`
      to lib/workaround-sensor-lib.sh (open/fixed/acknowledged lifecycle for any gate's
      escape, keyed by session).
- [x] Add `_svd_escape_naming_check` to stop-verdict-dispatcher.sh, wired into the
      existing `all_gaps` aggregate so it rides the pre-existing block-once-then-
      downgrade cycle with no new downgrade logic.
- [x] Print a same-turn stderr NOTICE at harness-hygiene-scan.sh's own waiver-honored
      call sites, pointing at the obligation the escape just opened.
- [x] harness-hygiene-scan.sh self-test: pin the incident as a permanent fixture
      (agent-authored plain waiver against a denylist hit still blocks) plus the
      delta-scoping and operator-waiver scenarios.
- [x] lib/workaround-sensor-lib.sh self-test: pin the open/fixed/acknowledged escape-
      obligation lifecycle scenarios.
- [x] stop-verdict-dispatcher.sh self-test: pin the escape-obligation block/name/
      downgrade-cycle scenarios.
- [x] session-start-digest.sh self-test: pin the bypass-24h surfacing scenarios.
- [x] `docs/backlog.md` entry naming the residual gaps (same-turn notice not wired at
      four other `ws_record` call sites; FIXED auto-close scoped to
      harness-hygiene-scan only; manifest.json not yet updated).

## Files to Modify/Create
- `adapters/claude-code/hooks/harness-hygiene-scan.sh` — delta-scoped pre-commit scan,
  denylist/heuristic waiver-class split, operator-waiver marker, same-turn notice.
- `adapters/claude-code/hooks/lib/workaround-sensor-lib.sh` — escape-obligation
  tracking (open/fixed/acknowledged).
- `adapters/claude-code/hooks/stop-verdict-dispatcher.sh` — escape-obligation Stop-side
  naming check, wired into the existing gap aggregate.
- `adapters/claude-code/hooks/session-start-digest.sh` — new `feed_bypass_surface` feed
  surfacing same-session/24h gate-bypass usage.
- `docs/backlog.md` — residual-gap disclosure entry
  (`HYGIENE-GATE-ESCAPE-ACCOUNTABILITY-FOLLOWUPS-2026-08-04`).

## Assumptions
- The operator's own directive (embedded in this session's dispatch) is authoritative
  on scope: fix the false-fire engine, split the waiver classes, and wire an
  accountability rail on top — no assumption was needed on WHETHER to build the
  accountability rail, only on its exact shape (session-scoping, closure conditions),
  which is documented as a named decision in `lib/workaround-sensor-lib.sh`'s own
  header rather than left implicit.
- `--full-tree` (already run by the `harness-review` skill and the secret-backstop CI
  workflow) is assumed to remain the periodic whole-tree net for pre-existing content;
  this plan does not change or re-verify that cadence, only confirms the mechanism
  still exists and is unmodified.
- The three OTHER `Status: ACTIVE` plans in this repo
  (`gated-pipeline-master-2026-08`, `cockpit-roadmap-redesign`,
  `accountable-estate-program-2026-07`) are unrelated to this fix; this plan exists
  specifically so `scope-enforcement-gate.sh` has a correctly-scoped home for this
  commit rather than the work being mis-attributed to one of them.

## Edge Cases
- A file with BOTH a denylist match AND a heuristic match in the same batch: the
  operator-waiver marker suppresses both (one obligation, not two); the plain waiver
  suppresses only the heuristic one, leaving the denylist match blocking — pinned by
  the SEC1-SEC4 self-test scenarios in harness-hygiene-scan.sh.
- A file with no trailing newline whose last line is the one containing the denylisted
  content: `_hhs_build_delta_view`'s `maxn` tracking (driven off the diff's own hunk
  line numbers, not just `wc -l`) covers the common case; documented as a known,
  non-byte-exact limitation in the function's own header rather than silently assumed
  solved.
- An escape obligation for a gate OTHER than harness-hygiene-scan: `_ws_escape_gate_fixed`
  always returns "not fixed" (fails closed) rather than silently auto-closing a gate it
  cannot honestly re-verify — pinned by workaround-sensor-lib.sh Scenario 15.
- A session that names the escaped gate in one Stop's terminal marker but never
  actually fixes or gets it acknowledged: a LATER Stop in the same session still gaps
  on it if still open and still unnamed — naming satisfies transparency for that one
  Stop, not permanent closure; documented explicitly in
  `_svd_escape_naming_check`'s own header.
- Two consecutive Stops with the identical unresolved escape gap-set: the first blocks,
  the second auto-downgrades (ADR 059 D2 block-once-then-ledger, the SAME generic cycle
  every other gap type already rides) rather than nagging forever — pinned by
  stop-verdict-dispatcher.sh Scenario 40.
- `feed_bypass_surface` running during a self-test with `HARNESS_SELFTEST=1` set but no
  `WORKAROUND_SENSOR_LEDGER_PATH` override: must resolve to a sandboxed, PID-keyed path
  and never read this machine's real production ledger — a real bug of exactly this
  shape was found and fixed during this plan's own verification pass (see Testing
  Strategy).

## Testing Strategy
Each touched file's own `--self-test` suite is the oracle (harness-internal work; no
separate test framework). Concrete pins added by this fix, verified by direct
execution (verbatim totals below):
- `harness-hygiene-scan.sh --self-test`: `self-test: OK` (1 SKIP: machine-local secret
  layer absent, expected off-CI). New/changed scenarios: D1 (new denylist hit in the
  staged delta blocks), D2 (delta clean but whole-file pre-existing hit does not block
  and emits a PRE-EXISTING notice), SEC1 (the incident replayed — an agent-authored
  plain waiver against a denylist hit still blocks, and the block message carries
  "NOT SELF-WAIVABLE" instead of the old recipe), SEC2 (a genuine
  operator-waiver marker suppresses the denylist hit), SEC3/SEC4 (an operator-waiver
  marker missing the clause, or carrying a placeholder clause, still blocks), W1-W5
  (retargeted from the denylist fixture to a heuristic fixture, since the plain waiver
  no longer covers denylist matches), A8 (unchanged — addendum-lint waiver still
  self-service).
- `lib/workaround-sensor-lib.sh --self-test`: 23 passed, 0 failed. New Scenarios 10-16:
  no rows for a session → 0 open obligations; a fresh row → 1 open obligation naming
  the right gate; a valid acknowledgment closes it; a placeholder acknowledgment does
  not; `_ws_escape_gate_fixed` recognizes a re-scanned-clean file for
  harness-hygiene-scan and correctly refuses to auto-close for any other gate; distinct
  sessions never leak obligations into each other.
- `stop-verdict-dispatcher.sh --self-test`: 105 passed, 0 failed. New Scenarios 38-41:
  an open+unnamed escape blocks the first Stop and names the gate in the block
  message; naming the gate in the terminal marker passes; a second identical Stop
  downgrades instead of blocking again (no nag loop); a session that never used an
  escape gets no gap at all.
- `session-start-digest.sh --self-test`: 105 passed, 0 failed (confirmed via a direct
  re-run after the HARNESS_SELFTEST-sandboxing bug below was fixed). New Scenario 24:
  fresh incident-shaped rows surface grouped by gate+kind within the 24h window; a row
  older than 24h is excluded; an empty ledger produces no output.
- **Bug found and fixed during this plan's own verification**: the first
  `feed_bypass_surface` implementation did not respect `HARNESS_SELFTEST` sandboxing
  (unlike every sibling path resolver in `session-start-digest.sh`), so a self-test run
  read this machine's REAL `$HOME/.claude/state/workaround-sensor.jsonl` and surfaced
  22 live operator waiver-file rows inside a test assertion. Caught via a
  baseline-vs-modified self-test diff (102/0 clean baseline vs 103 passed/2 failed with
  the bug, both failures in the same "all quiet" scenario); fixed with the identical
  `HARNESS_SELFTEST` branch this file's own `_unresolved_gaps_path` already uses;
  re-verified both by the full suite (105/0 clean) and by two direct, isolated
  invocations of the fixed function (silent when sandboxed and empty; correct
  `bypass-24h: harness-hygiene-scan waiver-file x1` output when populated via
  `WORKAROUND_SENSOR_LEDGER_PATH`).
- Regression check on the shared lib's other consumers: `concurrent-ownership-gate.sh
  --self-test`: 22 passed, 0 failed (of 22 scenarios) — confirms the additive
  `workaround-sensor-lib.sh` changes do not break an unrelated caller.

## Definition of Done
All four touched self-test suites pass with zero failures (verbatim totals in Testing
Strategy above); the incident's exact shape (agent-authored waiver against a denylist
hit) is pinned as a permanent regression fixture and fails closed; `docs/backlog.md`
carries the residual-gap disclosure; the commit lands on this worktree's branch with a
harness-reviewer pass still owed (per this session's dispatch — routed to
harness-reviewer after this commit, not through task-verifier/close-plan, since this
plan exists to satisfy scope-enforcement-gate rather than to run the full
orchestrator-pattern plan lifecycle).
