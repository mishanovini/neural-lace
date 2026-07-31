# Plan: Supervisor tick — the operator's never-stall mechanism
Status: ACTIVE
Execution Mode: direct
Mode: code
Backlog items absorbed: none
acceptance-exempt: true
acceptance-exempt-reason: Harness-internal mechanism with no product UI user — the maintainer (operator) is the user, and the `--self-test` suite is the demonstration per constitution §4's harness carve-out.
tier: 2
rung: 4
architecture: coding-harness
frozen: true
lifecycle-schema: v2
owner: mishanovini
target-completion-date: 2026-07-20
prd-ref: n/a — harness-development
ask-id: none — no linked ask (direct operator chat mandate, 2026-07-20)

## Goal
Operator mandate (verbatim, 2026-07-20): "Aren't you supposed to have mechanisms in
place to keep things from stopping and going stale? I told you to design this system
so that it is continuously always making progress and never stops." The observed
failure class (named in `docs/reviews/2026-07-19-continuous-operation-design-input.md`'s
own "Sessions are mortal" section, plus a fourth git-provable instance found during this
plan's own build): background agents and their completion notifications die with the
Claude Code process; orphaned obligations (uncommitted worktree fixes, dead fix-waves)
sit stale until the operator manually notices — sometimes weeks later. The existing
stranded-worktree-work detector (`worktree-hygiene-sweep.sh --stranded`) is only
consumed at SessionStart or an on-demand `harness-doctor.sh --quick` run — invisible
whenever no session happens to be open. This plan builds the minimal supervisor tick
that closes that specific gap: a scheduled, session-independent tick that runs the
already-deployed detector and durably alerts the moment an obligation goes orphaned,
plus the installer that registers it alongside the existing coordination cadence.

## User-facing Outcome
n/a — harness-internal: the operator (maintainer) is the user. After this plan ships
and the operator runs the one-line installer command, the operator can leave the
machine unattended for hours; if a session dies mid-work leaving an uncommitted or
unintegrated worktree behind, within one tick cadence (default 5 min) a NEEDS-YOU.md
entry appears naming the exact worktree, branch, and salvage command — without the
operator having to open a session or run the doctor by hand to discover it. The
`--self-test` suite (16 assertions against the real, unmodified detector) is the
mechanical demonstration that this actually fires.

## Scope
- IN: `adapters/claude-code/scripts/supervisor-tick.sh` (new tick script: runs
  `worktree-hygiene-sweep.sh --stranded --porcelain` + `session-heartbeat.sh sweep
  --json`, alerts via `needs-you.sh` + the existing external-monitor-alerts surface,
  bounded/idempotent/log-rotated, `--self-test`).
- IN: `adapters/claude-code/scripts/install-coord-sync-task.ps1` (extended to also
  register `NL-SupervisorTick` from the same operator run, per the round-2 design
  doc's Q6 disposition folding the coord floor and the supervisor tick into one
  installer).
- IN: `adapters/claude-code/manifest.json` (new `supervisor-tick` entry).
- OUT: the round-2 design doc's full REAPER (auto-cherry-pick / auto-purge), the
  orchestrator engine-check relaunch branch, and any session/build RESPAWN
  mechanism — named explicitly as a follow-up gap (SUPERVISOR-TICK-RESPAWN-GAP-01,
  filed via `nl-issue.sh`), not built here. Circuit-specific work (Google Docs
  connector, D3/D4) from the sibling design sketch is explicitly out of scope —
  this plan builds only the tick.

## Tasks

- [x] 1. Build `supervisor-tick.sh`, extend `install-coord-sync-task.ps1`, and add
  the manifest entry — Verification: full — Docs impact: none — the script's own
  header doc is the runbook; no separate README/runbook file exists for
  scheduled-tick scripts in this codebase (health-tick.sh / coord-sync.sh set the
  precedent of header-doc-as-runbook).
  **Prove it works:**
  1. `bash adapters/claude-code/scripts/supervisor-tick.sh --self-test` — 4
     fixture-driven scenarios (fake stranded worktree + dead heartbeat fires an
     alert once and stays idempotent on re-fire; live-heartbeat-owned worktree
     stays silent; missing detector WARNs gracefully; a backdated-past-TTL orphan
     re-alerts) against the REAL unmodified `worktree-hygiene-sweep.sh` — 16/16
     PASS.
  2. `powershell -File adapters/claude-code/scripts/install-coord-sync-task.ps1
     -RepoPath <repo> -WhatIf` — registers BOTH `NL-CoordSync` and
     `NL-SupervisorTick` from one run, touching neither disk nor Task Scheduler;
     exit 0.
  3. `jq empty adapters/claude-code/manifest.json` — valid JSON; `bash
     adapters/claude-code/scripts/manifest-check.sh` — GREEN.
  **Wire checks:**
  - `adapters/claude-code/scripts/supervisor-tick.sh` `run_tick` → invokes
    `worktree-hygiene-sweep.sh` `--stranded --porcelain`
  - `adapters/claude-code/scripts/supervisor-tick.sh` `run_tick` → invokes
    `needs-you.sh` `add --section question`
  - `adapters/claude-code/scripts/install-coord-sync-task.ps1` `$Tasks` array →
    references `supervisor-tick.sh` as `ScriptName`
  **Integration points:**
  - `worktree-hygiene-sweep.sh --stranded --porcelain` (pre-existing, deployed
    detector) — verified live in this session: real fixture worktrees (dirty +
    dead heartbeat vs. dirty + live heartbeat) classified ORPHANED /
    LIVE-OWNED correctly by the unmodified script.
  - `needs-you.sh add --section question` (pre-existing ledger writer) —
    verified live: NEEDS-YOU.md gained the expected entry naming the orphaned
    worktree; a second immediate fire added no duplicate.
  - `external-monitor-alert-surfacer.sh` schema (pre-existing SessionStart
    surfacer) — this tick reuses health-tick.sh's exact alert JSON shape
    byte-for-byte; not independently re-verified against the live surfacer in
    this session (health-tick.sh's own self-test already proves the surfacer
    consumes that schema; this tick's JSON was hand-verified to match field-
    for-field).

## Files to Modify/Create
- `adapters/claude-code/scripts/supervisor-tick.sh` — new tick script (create)
- `adapters/claude-code/scripts/install-coord-sync-task.ps1` — extended to register
  a second scheduled task, `NL-SupervisorTick`, from the same operator run (modify)
- `adapters/claude-code/manifest.json` — new `supervisor-tick` entry (modify)

## In-flight scope updates
- 2026-07-22: `docs/plans/supervisor-tick-evidence.md` — Task 1 evidence companion
  (gate input; the retroactive plan omitted its own evidence log from the files list —
  scope-enforcement-gate flagged it at the master squash-merge).

## Assumptions
- The existing `worktree-hygiene-sweep.sh --stranded --porcelain` detector's
  heartbeat-based liveness join is correct and does not need re-verification here
  (it is a separately-reviewed, already-deployed mechanism — reusing it, not
  re-implementing it, is this plan's explicit design choice).
- `needs-you.sh` and `session-heartbeat.sh` are stable CLIs whose contracts
  (documented in their own file headers) will not change out from under this
  tick without a corresponding update here.
- The operator will run the extended `install-coord-sync-task.ps1` manually
  (agent sessions cannot register scheduled tasks — permission-blocked) — this
  plan does not claim the task is actually registered on any machine yet.
- `git`, `bash`, `cksum`, `date -u -d`, and `timeout` are available in the Git
  Bash environment this tick runs in (all already relied upon by sibling scripts
  in this codebase).

## Edge Cases
- Detector script missing or unreadable at tick time → WARN + one DETECTOR_MISSING
  alert, exit 0 (self-test scenario 3).
- Detector hangs past the wall-clock budget → SWEEP_TIMEOUT alert via the
  timeout-wrapped fork, exit 0 (never blocks the scheduled task queue).
- Same orphan present across many consecutive ticks → idempotent via the
  per-orphan ledger; re-alerted only after `SUPERVISOR_TICK_REALERT_HOURS`
  (default 24h) so NEEDS-YOU.md/the alert dir are never spammed (self-test
  scenarios 1b and 4).
- Orphan resolves (worktree cleaned up, or becomes live-owned) → its ledger
  record is pruned on the next fire that no longer observes it as orphaned, so a
  LATER re-orphaning of the same path/branch alerts fresh rather than silently
  inheriting stale state.
- Repo path contains spaces (this very machine's own checkout, under "Pocket
  Technician") → repo list is resolved into a bash array, never naive
  word-split, so multi-word paths survive intact end to end.
- One of the two scheduled-task scripts (`coord-sync.sh` / `supervisor-tick.sh`)
  is missing from a given machine's checkout at install time → the installer
  WARNs and skips only that one task, still registering the other (verified live
  against this worktree vs. the main checkout, which lacked `supervisor-tick.sh`
  until this plan's own commit lands there).

## Acceptance Scenarios
n/a — harness-dev plan, no product user; see acceptance-exempt-reason above.

## Out-of-scope scenarios
None — all scope is harness-internal (acceptance-exempt: true), so no
user-facing acceptance scenarios were proposed to reject.

## Closure Contract
- **Commands that run:** `bash adapters/claude-code/scripts/supervisor-tick.sh
  --self-test`; `jq empty adapters/claude-code/manifest.json`; `bash
  adapters/claude-code/scripts/manifest-check.sh`; a PowerShell syntax parse of
  `install-coord-sync-task.ps1` plus a `-WhatIf` dry run.
- **Expected outputs:** self-test "16 passed, 0 failed"; manifest valid JSON +
  `manifest-check.sh` GREEN; PowerShell parse reports zero errors; `-WhatIf` run
  registers both `NL-CoordSync` and `NL-SupervisorTick` with exit 0 and touches
  neither disk nor Task Scheduler.
- **On-disk artifact location:** this plan file's own evidence is the commands'
  live output captured in this session's transcript and cited in the task-verifier
  invocation and the completion report appended below; no separate
  `.claude/state/acceptance/` artifact applies (acceptance-exempt).
- **Done when:** Task 1 is task-verifier PASS and the self-test/manifest-check/
  PowerShell-parse commands above all show the expected outputs.

## Testing Strategy
- `supervisor-tick.sh --self-test`: 4 fixture-driven scenarios / 16 assertions,
  run against the real, unmodified `worktree-hygiene-sweep.sh` (the pre-existing
  oracle for "is this worktree orphaned"), never a stub of it.
- `install-coord-sync-task.ps1`: PowerShell AST parse for syntax validity, plus a
  `-WhatIf` dry run against both a repo path missing `supervisor-tick.sh` (proves
  the graceful per-task skip) and a repo path carrying both scripts (proves both
  tasks register).
- `manifest.json`: `jq empty` for JSON validity + `manifest-check.sh` for schema
  conformance.
- No live-model / AI-output testing applies — this is a deterministic bash/
  PowerShell mechanism with no LLM-generated user-facing text.

## Walking Skeleton
Walking Skeleton: n/a — the "skeleton" for a detect-then-alert tick IS Task 1 in
full (detector invocation → classification → dual alert write → ledger dedup);
there is no thinner meaningful slice to build first for a single-task plan whose
entire scope is one cohesive mechanism.

## Decisions Log
- 2026-07-20: Plan authored AFTER the build (not before), because this task was
  dispatched directly by the operator outside the orchestrator-pattern flow (no
  pre-existing plan file was handed to the builder) and the work had already
  landed in the worktree by the time `scope-enforcement-gate.sh` blocked the
  commit. Per the gate's own option 2 ("open a new plan... for genuinely
  separate work... not part of an active plan"), this plan was created to
  retroactively and honestly govern the already-built, already-self-tested
  change, rather than forcing it into one of the four unrelated pre-existing
  active plans (`cockpit-roadmap-redesign`, `flat-skills-directory-form-migration`,
  `orphaned-worktree-guard-reformulation`, `ps51-emdash-parse-hotfix`) it has no
  real connection to. Reversible, low-risk, decide-and-go per constitution §8.
- 2026-07-20: `Execution Mode: direct` (not `orchestrator`) — single cohesive
  task, one session did the work directly, no sub-agent dispatch was warranted
  for a ~250-line script + a PowerShell extension + one manifest entry.
- 2026-07-20: `rung: 4` (autonomous) chosen honestly over a lower rung — the
  tick, once the operator registers its scheduled task, DOES operate
  autonomously post-deploy on a timer with no human in the loop per fire. This
  triggers the Behavioral Contracts requirement below rather than
  under-claiming a lower rung to dodge it.
- 2026-07-20: RESPAWN GAP named, not built. The round-2 design doc's fuller
  REAPER vision includes auto-triage/auto-cherry-pick and an orchestrator
  engine-check relaunch branch. This plan deliberately ships detect+alert only
  (the prompt's own explicit fallback clause) and files the gap as
  SUPERVISOR-TICK-RESPAWN-GAP-01 via `nl-issue.sh` rather than building an
  unreviewed, unguarded second respawn mechanism — the exact anti-pattern
  `docs/reviews/2026-07-17-circuit-continuous-building-design-sketch.md` §4
  warns against for this program's D3 problem.

## Behavioral Contracts
<!-- Required at rung: 4 per plan-reviewer.sh Check 11. -->
- **Idempotency:** A given orphaned worktree (keyed by `cksum(path|branch)`) is
  alerted (NEEDS-YOU.md entry + external-monitor-alerts JSON) at most once per
  `SUPERVISOR_TICK_REALERT_HOURS` window (default 24h), regardless of how many
  times the tick fires against it in between — enforced by the per-orphan ledger
  record's `last_alerted` timestamp, proven by self-test scenarios 1b (immediate
  re-fire, zero duplicates) and 4 (backdated past TTL, re-alerts — proving the
  design forgets nothing rather than staying silent forever).
- **Performance budget:** Every fire is bounded by `SUPERVISOR_TICK_BUDGET_SECS`
  (default 120s in production; the self-test raises this to 600s because the
  real detector forks dozens of git subprocesses and this machine was observed,
  live, taking up to ~90s for a two-worktree fixture under heavy concurrent
  session load). Every subprocess fork (the sweep, the heartbeat sweep, each
  `needs-you.sh add`) is individually `timeout`-wrapped against the remaining
  budget, so a single hung fork cannot consume the whole allowance silently.
- **Retry semantics:** None — this is an observe-only tick with no mutating
  action to retry. A timed-out or missing detector produces exactly one
  SWEEP_TIMEOUT/DETECTOR_MISSING alert for that fire and returns; the NEXT
  scheduled fire (per the installer's cadence, default 300s) is the retry,
  naturally, with no special-cased backoff logic needed since each fire is
  already cheap and independent.
- **Failure modes:** (1) Detector binary missing → WARN + DETECTOR_MISSING
  alert, exit 0. (2) Detector or heartbeat-sweep times out → WARN +
  SWEEP_TIMEOUT alert, exit 0. (3) `needs-you.sh add` itself fails (e.g. lock
  contention) → best-effort, swallowed (`|| true`) — the external-monitor-alert
  JSON is still written independently, so the orphan is never silently
  unreported even if the needs-you write fails. (4) Ledger write fails (disk
  full, permissions) → best-effort (`|| true`); the NEXT fire will simply
  re-detect and re-attempt, since a missing ledger record is indistinguishable
  from a new orphan (fail-open toward re-alerting, never toward silent loss).

## Evidence Log

### Task 1 — Build supervisor-tick.sh, extend install-coord-sync-task.ps1, add the manifest entry

Runtime verification (re-run live in this session, cebc26f):
- `bash adapters/claude-code/scripts/supervisor-tick.sh --self-test` → "self-test
  summary: 16 passed, 0 failed", exit 0.
- `jq empty adapters/claude-code/manifest.json` → valid; `bash
  adapters/claude-code/scripts/manifest-check.sh` → "[manifest-check] GREEN —
  130 entries, 110 hooks covered, 0 warn".
- PowerShell AST parse of `install-coord-sync-task.ps1` → 0 parse errors;
  `-WhatIf -RepoPath <this worktree>` → both `NL-CoordSync` and
  `NL-SupervisorTick` register (exit 0), Task Scheduler untouched.

## Comprehension Articulation

### Spec meaning

The spec (this plan's own Goal/Scope, which I authored from the operator's
2026-07-20 verbatim mandate plus the round-2 continuous-operation design doc)
asks for the MINIMAL slice of the "never-stall" mechanism: a scheduled,
session-independent tick that (a) detects orphaned git-worktree obligations by
running the ALREADY-DEPLOYED `worktree-hygiene-sweep.sh --stranded --porcelain`
detector rather than re-implementing its heartbeat-based liveness join, (b)
durably alerts via two existing surfaces (`needs-you.sh` and the
external-monitor-alerts JSON schema) without ever destroying, cherry-picking,
or respawning anything, (c) is bounded, idempotent per fire, and log-rotated,
and (d) ships with an installer extension so ONE operator PowerShell run
registers both the pre-existing coordination cadence and this new tick. The
respawn/auto-triage half of the round-2 design's fuller vision is explicitly
named as future work, not built here — the spec's own fallback clause
sanctions shipping detect+alert only when no safe respawn primitive exists.

### Edge cases covered

- Same orphan present across many consecutive ticks does not spam
  NEEDS-YOU.md/the alert dir: a per-orphan ledger record's `last_alerted`
  timestamp gates re-alerting to once per `SUPERVISOR_TICK_REALERT_HOURS`
  (default 24h) — `supervisor-tick.sh:380-389`, proven by self-test scenario
  1b (immediate re-fire, zero new NEEDS-YOU mentions, alert-file count stays
  at 1).
- An orphan is never permanently forgotten once past the re-alert window —
  `supervisor-tick.sh:385-386` (`now_epoch - last_alerted_epoch >=
  realert_after` → `should_alert=1` again), proven by self-test scenario 4
  (backdating a ledger record's `last_alerted` to 2020 and re-firing produces
  a fresh alert).
- Live-heartbeat-owned dirty worktree is never mistaken for an orphan (the
  cry-wolf false-positive class the underlying detector's own reformulation
  fixed): this tick does not re-derive that judgment at all — it only ever
  sees `ORPHANED-HOLDS-CONTENT` rows from the detector's `--stranded`
  porcelain output (`supervisor-tick.sh:361`, `[[ "$tag" ==
  "ORPHANED-HOLDS-CONTENT" ]] || continue`, filtering the loop over each
  parsed porcelain row) — proven by self-test scenario 2 (the live-owned
  `wt-live` fixture never appears in NEEDS-YOU.md, the alert dir, or the
  ledger).
- Detector binary missing at fire time → graceful WARN + one DETECTOR_MISSING
  alert, not a crash: `supervisor-tick.sh:313-319` checks `[[ ! -f
  "$sweep_bin" ]]` before ever invoking it and returns 0 immediately — proven
  by self-test scenario 3.
- Detector or a fork hangs past budget → bounded by `_st_run`'s
  `timeout`-wrap (`supervisor-tick.sh:228-236`, `_st_run() { ...; timeout
  "${secs}s" "$@"; ... }`) against the remaining wall-clock allowance
  (`remaining=$(( budget - SECONDS ))`, `supervisor-tick.sh:325,345,409`); a
  `sweep_rc -eq 124` produces a SWEEP_TIMEOUT alert
  (`supervisor-tick.sh:330-334`) rather than hanging the scheduled task
  indefinitely.
- Repo paths containing spaces (this very machine's own checkout path
  contains "Pocket Technician") survive intact: `_st_resolve_repos` reads
  candidate repos line-by-line into the `ST_REPOS` bash array
  (`supervisor-tick.sh:243-262`), never word-splits, and every consumer
  expands it as `"${ST_REPOS[@]}"` (`supervisor-tick.sh:327`) — verified live
  in this session's own `-WhatIf` run, which correctly resolved and quoted
  `C:\Users\misha\dev\Pocket Technician\neural-lace\...` end to end.
- Orphan resolves (worktree cleaned up, merged, or becomes live-owned) → its
  ledger record is pruned so a later re-orphaning of the same path/branch
  re-alerts fresh instead of inheriting stale `last_alerted` state:
  `supervisor-tick.sh:421-429` diffs the ledger directory against a
  per-fire `seen_file` of currently-orphaned keys and removes any record not
  re-seen this fire.
- One of the two scheduled-task scripts missing on a given machine at
  install time → the installer WARNs and skips only that one task
  (`install-coord-sync-task.ps1:212-222`, `Write-Warning` chosen deliberately
  over `Write-Error` because `$ErrorActionPreference = 'Stop'` would
  otherwise terminate the whole script on the first missing script) — I hit
  this live: the real main checkout at `C:\Users\misha\dev\Pocket
  Technician\neural-lace` lacks `supervisor-tick.sh` until this commit lands
  there, and the first `-WhatIf` attempt against that path surfaced exactly
  this path (initially as a hard `Write-Error` abort, which I then fixed to
  `Write-Warning` + `continue` after observing the exit-1 failure).

### Edge cases NOT covered

- No orphaned-worktree-specific RESPAWN or auto-cherry-pick exists — named
  honestly as SUPERVISOR-TICK-RESPAWN-GAP-01 (filed via `nl-issue.sh`,
  confirmed on disk at `~/.claude/state/nl-issues.jsonl` line 144) rather than
  built. This plan's own Scope section names it OUT explicitly.
- Cross-machine deduplication: if two machines each ran their own
  `NL-SupervisorTick` against the SAME shared network path (not this
  machine's actual setup, but a hypothetical), each machine's ledger is
  independent (`~/.claude/state/supervisor/` is per-machine, per
  `session-heartbeat-lib.sh`'s own established per-machine-state
  convention) — no cross-machine coordination was designed or needed for
  this slice, since worktrees are inherently per-machine filesystem objects.
- The external-monitor-alerts JSON schema reuse (`supervisor-tick.sh:279-292`
  `_st_flush_alert`) was hand-verified field-for-field against
  `health-tick.sh`'s own alert-writing code, but I did not additionally run
  the REAL `external-monitor-alert-surfacer.sh` against one of this tick's
  own alert files in this session (health-tick.sh's self-test already proves
  that surfacer consumes this exact schema; I relied on that rather than
  re-proving it here). Flagged in the plan's own Task 1 Integration points
  sub-block rather than silently assumed.
- Performance under this machine's currently heavy concurrent-session load
  was OBSERVED (a two-worktree fixture sweep took up to ~90s) but not
  formally load-tested against a target throughput; the 120s production
  budget default is a judgment call informed by that one observation, not a
  benchmarked SLA.

### Assumptions

- `worktree-hygiene-sweep.sh --stranded --porcelain`'s existing
  heartbeat-based liveness classification is correct and does not need
  re-verification here — this task's explicit design choice is to REUSE that
  already-reviewed detector rather than re-implement or second-guess its
  join logic (stated in the plan's own Assumptions section and in
  `supervisor-tick.sh`'s file-header "WHY THIS EXISTS" block).
- `needs-you.sh`, `session-heartbeat.sh`, and `worktree-hygiene-sweep.sh`'s
  CLIs (flags, output shapes, sandboxing env vars) are stable contracts that
  will not change out from under this tick without a corresponding update —
  verified against their current file-header documentation in this session,
  not assumed from memory.
- `cksum`, `git`, `bash`, `timeout`, and `date -u -d` are available in the
  Git Bash environment this tick runs in — confirmed present on this machine
  in this session (`command -v cksum md5sum sha1sum jq timeout` all
  resolved) and already relied upon by sibling scripts in this codebase
  (`close-plan.sh`, `plan-lifecycle.sh` use `cksum`; `agent-commit-gate.sh`
  uses the same 200KB tail-keep log-rotation idiom this tick reuses).
- The operator will run the extended installer manually — agent sessions
  cannot register scheduled tasks (permission-blocked); this plan does not
  claim `NL-SupervisorTick` is actually registered on any real machine yet,
  only that the installer correctly WOULD register it (proven via `-WhatIf`,
  never via a live, non-dry-run registration in this session).

## Definition of Done
- [ ] All tasks checked off
- [x] All tests pass (self-test 16/16, manifest-check GREEN, PS parse clean)
- [x] Linting/formatting clean (no linter configured for adapters/claude-code/
  scripts/ beyond the self-tests themselves)
- [ ] SCRATCHPAD.md updated with final state
- [ ] Completion report appended to this plan file

## Completion report

Task 1 (the plan's only task) is task-verifier PASS as of 2026-07-21T03:46:22Z.
Confidence 9. Full evidence: `docs/plans/supervisor-tick-evidence.md`.

This was the SECOND task-verifier invocation for this task. The first pass
independently re-ran and PASSED every Closure Contract / Prove-it-works /
wire-check / integration-point item, but blocked the checkbox flip on a
missing precondition: this is a `rung: 4` plan and no `## Comprehension
Articulation` block existed yet (Decision 020a/020d). Between the two
passes: commit `a44a6c6` added the four required sub-sections (Spec meaning
/ Edge cases covered / Edge cases NOT covered / Assumptions); comprehension-
reviewer's first pass on that block found two mis-cited file:line references
in "Edge cases covered" (Stage 3b FAIL); commit `2651f59` fixed both
mis-citations against the on-disk file; comprehension-reviewer's second pass
returned PASS (confidence 9, all stages 1/2/3a-3e green, all 13 citations
grounded). This second task-verifier invocation independently re-spot-checked
all 13 citations against the on-disk `supervisor-tick.sh` /
`install-coord-sync-task.ps1` (all confirmed verbatim — see the evidence
file), confirmed via `git log --oneline` that both docs commits touched only
`docs/plans/supervisor-tick.md` (the three code files — `supervisor-tick.sh`,
`install-coord-sync-task.ps1`, `manifest.json` — remain at `cebc26f`,
unchanged since the first pass), and independently re-executed all four
Closure Contract commands live in this session with results matching the
documented expectations exactly:
  - `bash adapters/claude-code/scripts/supervisor-tick.sh --self-test` →
    "self-test summary: 16 passed, 0 failed"
  - `jq empty adapters/claude-code/manifest.json` (valid) + `bash
    adapters/claude-code/scripts/manifest-check.sh` → "GREEN — 130 entries,
    110 hooks covered, 0 warn"
  - PowerShell AST parse of `install-coord-sync-task.ps1` → 0 errors
  - `-WhatIf -RepoPath <this worktree>` → both `NL-CoordSync` and
    `NL-SupervisorTick` register, Task Scheduler untouched

Known, honestly-named gaps (unchanged from the build, not new):
`SUPERVISOR-TICK-RESPAWN-GAP-01` (auto-triage/cherry-pick — out of scope,
filed via `nl-issue.sh`); the operator must still run
`install-coord-sync-task.ps1` (without `-WhatIf`) on each real machine to
actually register `NL-SupervisorTick` — no session in this harness can do
that itself (Task Scheduler registration is permission-blocked for agent
sessions).

Remaining `## Definition of Done` items (`SCRATCHPAD.md updated`,
`Completion report appended` — this entry satisfies that one) and the plan
`Status:` transition are left to the closing session/orchestrator; per
task-verifier scope this report covers Task 1's verification only.
