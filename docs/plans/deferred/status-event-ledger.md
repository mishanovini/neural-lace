# Plan — Status-event ledger: a deterministic trigger for EVERY status event

Status: DEFERRED
Key: SE
Mode: code
rung: 2
Owner: 2026-07-30 operator directive (verbatim below); continues the attribution
pipeline (b93a7d5) which built the first two triggers.
parent-thread: verification-dispatch-directive (the enforcement-by-chokepoint doctrine)

## Operator requirement (verbatim, 2026-07-30 — the spec)

"I want to make it explicit that the event taxonomy that we discussed needs to have a
deterministic trigger for every single one of these events that reports status to the
ledger. That needs to be included in the plan."

And the companion requirement, same message: "the statuses that you report in this chat
need to match and need to clearly match what I see in the Workstreams UI. Every surface
needs to speak the same language."

## Design law

Every status event is emitted BY A MECHANISM AT A CHOKEPOINT the work must pass through —
never by an agent remembering. An event class without a named deterministic trigger is
UNBUILT, listed as such, never implied working. One vocabulary everywhere: the cockpit's
six-value enum (not-started / in-progress / running / complete / stalled(reason) /
unknown(reason)) + `<PlanKey><TaskId>` tokens; chat reports use EXACTLY these tokens.

## The taxonomy — event class → deterministic trigger → status

| # | Event | Deterministic trigger (chokepoint) | Status |
|---|---|---|---|
| 1 | dispatch started (plan/task/role attributed) | PreToolUse Task\|Agent\|Workflow → workstreams-emit --on-builder-dispatch parses NL-ATTRIBUTION | **BUILT** b93a7d5 |
| 2 | dispatch concluded (paired ids) | Stop → --on-stop reads the stopping session's header | **BUILT** b93a7d5 |
| 3 | task started/done | plan-lifecycle + progress-log emit task_started/task_done | **PARTIAL** — events exist; done-emit fires only via checkbox flip path |
| 4 | handoff complete (builder commit landed) | estate-merge.sh + the orchestrator's cherry-pick → emit at the merge primitive (T5's single merge path IS the chokepoint) | **BUILT** 4a2ca13 — SE1 (`_em_log_merge`, the single funnel every terminal `cmd_merge` outcome already passes through, now calls `_em_emit_ledger_event`; two new progress-log-lib.sh types, `merge_completed`/`merge_failed`, field-reuse per the plan_outcome_recorded/plan_reopened idiom; `estate-merge` registered in `_PL_KNOWN_EMITTERS`. estate-merge.sh --self-test 52/0 → 82/0 both /bin/bash 3.2.57 and /opt/homebrew/bin/bash 5.3.15, mutation-proven. **REFORMULATE round 2026-07-30** (harness-reviewer F1-F7, see evidence file): F1 the lock-busy refusal now logs+emits too (was the one terminal outcome bypassing `_em_log_merge` entirely); F2 renamed `merge-completed`/`merge-failed` → `merge_completed`/`merge_failed` (underscore convention, matching every other type); F3 the dedup table synced across all three sites (`progress-log-lib.sh`, `docs/runbooks/ask-workstreams.md`, `schemas/progress-log-event.schema.json`), backfilling T9's own two rows too; F4 softened an overclaiming static-guard comment; F5 dropped a dead `dedup_extra` value for `merge_completed`; F7 a new `--acknowledge <sha> --reason <text>` subcommand resolves a legitimate out-of-band-merge RED finding to CLEAN, named by both the RED finding and `--help`. RESIDUAL, named not hidden: today only close-worktree.sh routes through estate-merge.sh (per its own manifest entry: "NOT yet the estate's ONLY merge path"); the orchestrator's own PARALLEL-mode cherry-pick is a direct `git cherry-pick` an agent performs, not a call into this script, so that path stays uninstrumented until it too is routed through estate-merge.sh or gets its own emit) |
| 5 | suite run pass/fail counts | the sweep runner + a per-suite emit wrapper at the --self-test entry | **UNBUILT** — SE2 |
| 6 | review verdict INCLUDING non-PASS | write-review-record.sh emits every verdict; records index gains non-PASS entries (REVIEW-INDEX-FAILURE-BLIND-01) | **BUILT** — SE3 (cmd_capture emits a `review-verdict` ledger event on EVERY verdict, unconditionally; index already folded non-PASS rows, now proven by self-test S21/S22, 22/22 both interpreters. RESIDUAL: nothing forces capture to be CALLED for a non-queue-pathway review — an uncaptured verdict still emits nothing, honestly unchanged) |
| 7 | verification verdict + checkbox flip | plan-edit-validator already gates the flip; add emit at validation | **BUILT** — SE4 (emit_flip_ledger_event fires a `flip-verdict` ledger event {plan, task, verdict, confidence, verifier} on every AUTHORIZED flip; self-test F16/F17, 12/17 both interpreters — the 5 pre-existing F5-F9 failures are an unrelated, pre-existing `stat -c %Y` portability bug, PROVEN unchanged on the unmodified file, docs/backlog.md HARNESS-GAP-62). **EXTENDED 2026-08-04**: detail gains `evidence=<file>#task=<id>`, `plan=` is now the bare slug; new consumer `verify-event-audit.sh`; PROVEN 0/926 real production rows exist (HARNESS-GAP-62's TASK_ID regex also blocks bare-numeric ids, not just fused ones — see the 2026-08-04 backlog amendment) |
| 8 | blocked (gate/classifier) | stop-verdict-dispatcher + each blocking gate's block path emits | **PARTIAL** — ledger-24h counts exist; per-event rows unbuilt — SE5 |
| 9 | killed (limit/API death) + resumed | the wake/notification consumer + session-resumer emit kill/resume pairs | **UNBUILT** — SE6 (the 7-agent kill on 2026-07-30 is the golden scenario) |
| 10 | deploy (auto-install sync / LaunchAgent restart) | auto-install summary line → emit; ensure-* kickstart → emit (merged≠deployed bit twice on 2026-07-29) | **UNBUILT** — SE7 |
| 11 | heartbeat during long work (running vs parked) | agent-heartbeat.sh on a tick per live agent | **PARTIAL** — lib exists; per-agent wiring unbuilt — SE8 |
| 12 | decision asked/answered | needs-you.sh add/resolve emits | **PARTIAL** — ledger writes exist; governor-ledger mirror unbuilt — SE9 |
| 13 | incident/error observed | nl-issue.sh + observed-errors append emit | **PARTIAL** — own stores exist; unified feed unbuilt — SE9 |

## Tasks

- [ ] SE1 — Handoff-complete emit at estate-merge.sh (the single merge chokepoint) + the
      orchestrator cherry-pick path. Verification: full.
      **BUILT 2026-07-30** (4a2ca13) — see taxonomy row 4. `_em_log_merge` (already the
      one funnel every terminal `cmd_merge` outcome passes through) now calls
      `_em_emit_ledger_event`, emitting `merge_completed`/`merge_failed` progress-log-lib.sh
      events with branch/target/sha/machine on every success/failure path. Suite 82/0 both
      interpreters (was 52/0), mutation-proven (disabling the emit call in place turned the
      static guard + 15 of 16 new scenario assertions RED for the correct reason, then
      restored to exactly 69/0; F1/F7's own mutation-proofs below repeated this exercise
      independently). RESIDUAL: the orchestrator's own PARALLEL-mode cherry-pick is a direct
      `git cherry-pick`, not a call into estate-merge.sh, and stays uninstrumented (see
      taxonomy row 4's own RESIDUAL note) — out of this task's scope (dispatched as
      "the handoff-complete emit at estate-merge.sh, the single merge chokepoint").
      **REFORMULATE FIXED 2026-07-30** (harness-reviewer F1-F7, see
      `docs/plans/status-event-ledger-evidence.md` for the full Comprehension Articulation
      and `docs/plans/status-event-ledger.md` taxonomy row 4 for the summary) — F1 lock-busy
      instrumentation, F2 underscore rename, F3 three-site dedup-table sync (+ T9 backfill),
      F4 softened static-guard comment, F5 dropped dead `dedup_extra`, F6 already resolved by
      the Comprehension Articulation commit, F7 `--acknowledge` escape hatch. 52/0 → 82/0,
      both interpreters, both new mechanisms (F1, F7) independently mutation-proven.
- [ ] SE2 — Per-suite emit: pass/fail counts + interpreter, emitted from the sweep runner and
      a shared --self-test entry helper; NEVER from inside suites by hand. Verification: full.
- [ ] SE3 — write-review-record.sh emits EVERY verdict; index records non-PASS (the gate
      matches PASS only, so no behavior change). Verification: full.
      **BUILT 2026-07-30** — see taxonomy row 6. Suite 22/22 both interpreters (was 20/20);
      review-record-commit-gate.sh 62/62 unchanged before/after.
- [ ] SE4 — Flip-time emit in plan-edit-validator (verifier, verdict, confidence).
      Verification: full.
      **BUILT 2026-07-30** — see taxonomy row 7. Suite 12/17 both interpreters (the 5
      failures are pre-existing and unrelated, docs/backlog.md HARNESS-GAP-62).
      **EXTENDED 2026-08-04** (operator directive, this session — "check off the check
      boxes in two places (plan file and ledger)"; not a new SE task number, an additive
      field-contract change to the same mechanism): `flip_ledger_fields`/
      `emit_flip_ledger_event` now also emit `plan=<bare slug, no .md>` (was the filename
      with extension) and `evidence=<file>#task=<id>` (a pointer to whichever evidence
      source authorized the flip). New self-test scenarios F25-F27 (27/0, both mutation-
      proven: reverting the evidence-pointer append turns F25/F26 red with the exact
      expected-vs-actual diff; reverting the bare-slug fix turns F27 red the same way).
      New read-only consumer: `adapters/claude-code/scripts/verify-event-audit.sh`
      (self-tested 7/7, mutation-proven on 3 independent fix points) cross-checks a
      plan's checked boxes against the ledger's flip-verdict events and reports the
      honest "no verification event on record" state — never fabricated. **Also found
      while extending this (see docs/backlog.md HARNESS-GAP-62's 2026-08-04 amendment):**
      the pre-existing TASK_ID regex gap is WORSE than previously scoped — it also blocks
      bare-numeric ids (this repo's dominant real convention), so the flip-verdict
      mechanism has fired ZERO times in production despite being BUILT since 2026-07-30.
      Measured via the new sweep tool: 926 currently-checked tasks across
      docs/plans/**/*.md, 0 with a matching event. Not fixed here (authorization-path
      surgery, deliberately not bundled with this additive change) — filed, not silently
      worked around.
- [ ] SE5 — Per-block emit rows (gate id, command shape) from the dispatcher's combined
      verdict. Verification: full.
- [ ] SE6 — Kill/resume pairing: the notification consumer emits agent-killed(cause) and
      resume emits agent-resumed(from) — closes the loop T11's watchdog will consume.
      Verification: full.
- [ ] SE7 — Deploy emits from auto-install + ensure-* restarts. Verification: full.
- [ ] SE8 — Per-agent heartbeat wiring so running vs parked is derivable. Verification: full.
- [ ] SE9 — Unified feed view: the cockpit reads one merged event stream; decision + incident
      stores mirror in. Verification: full.
- [ ] SE10 — VOCABULARY LOCK: doctrine amendment making the cockpit enum + `<Key><Task>`
      tokens the ONLY status vocabulary in chat reports, sign-offs, and markers; the
      problems-persist Stop-WARN gains a vocabulary check (WARN on off-vocabulary status
      words in the final message). Verification: full.
      **BUILT 2026-07-30** — (a) doctrine/claims.md "Status vocabulary lock" section (the
      compact host; findings-ledger.md was the other candidate but is already over the
      3000B soft cap and topically further from claim-tagging discipline); (b)
      stop-verdict-dispatcher.sh gains `_svd_vocabulary_lock_check` (WARN-only, same
      non-contributing shape as COLD-READER-LINT/PROBLEMS-PERSIST), self-tested scenarios
      31-34, 92/0 both interpreters (was 83/0), mutation-proven (disabling the call site
      turns exactly 2 of the 9 new assertions red — 90/2). A bare-task-id ("task 9" with no
      plan-key prefix) check was DRAFTED and DEFERRED after measurement showed 163/1673
      (~9.7%) of this repo's own commit subjects use bare numeric ids for pre-existing
      plans that never adopted the fused convention — see doctrine/claims.md and
      docs/backlog.md HARNESS-GAP-62 for the full measurement and the separate,
      more-severe finding it surfaced (plan-edit-validator.sh's own checkbox-flip TASK_ID
      regex still rejects SE3/RI1-style fused ids outright — not fixed here, out of scope).

## Files to Modify/Create
<!-- Added retroactively 2026-07-30 during SE3/SE4/SE10's build (scope-enforcement-gate
requires this section before ANY commit touching these files can land) — populated with
what has ACTUALLY been touched so far; SE1/SE2/SE5-SE9's own files are added by whichever
session builds them, per `## In-flight scope updates` below. -->
- `adapters/claude-code/hooks/workstreams-emit.sh` — SE taxonomy events #1/#2 (dispatch
  started/concluded), built in b93a7d5, prior to this plan's own file.
- `adapters/claude-code/scripts/write-review-record.sh` — SE3: cmd_capture emits a
  `review-verdict` signal-ledger event on every verdict (PASS/REFORMULATE/REJECT).
- `adapters/claude-code/hooks/plan-edit-validator.sh` — SE4: emit_flip_ledger_event fires
  a `flip-verdict` signal-ledger event on every authorized checkbox flip.
- `adapters/claude-code/hooks/stop-verdict-dispatcher.sh` — SE10(b): vocabulary-lock
  Stop-WARN check (off-vocabulary status phrasing denylist).
- `adapters/claude-code/doctrine/claims.md` — SE10(a): "Status vocabulary lock" doctrine
  section.
- `adapters/claude-code/hooks/lib/signal-ledger.sh` — KNOWN EVENT TYPES registry comment
  gains `review-verdict` + `flip-verdict`.
- `adapters/claude-code/observability-consumer-map.json` — real-consumer entries for the
  same two new event types (harness-doctor's check_obs_consumer_map law-2 requirement).
- `adapters/claude-code/manifest.json` — honest_status updates for review-before-deploy,
  plan-edit-validator, and stop-verdict-dispatcher entries.
- `docs/backlog.md` — HARNESS-GAP-62 (plan-edit-validator.sh's fused-id TASK_ID regex gap,
  found while building SE4, filed not fixed — out of this plan's scope).
- `docs/plans/status-event-ledger.md` — this file: taxonomy status column + task-list
  BUILT annotations for SE3/SE4/SE10 (checkboxes untouched — task-verifier's job).

## In-flight scope updates
- SE1's files are now declared in the `## Files to Modify/Create` section below
  (estate-merge.sh, progress-log-lib.sh, manifest.json).
- 2026-07-30: `docs/plans/status-event-ledger-evidence.md` (new) — SE1's rung-2
  `## Comprehension Articulation` evidence entry, required before task-verifier can flip the
  checkbox; also carries the corrected row-4/SE1 BUILT SHA (4a2ca13, the landed commit, not
  the worktree-local 2c86b60).
- 2026-07-30: SE1 REFORMULATE fixes (F1-F7, harness-reviewer) — `docs/runbooks/ask-workstreams.md`
  and `adapters/claude-code/schemas/progress-log-event.schema.json` (F3: three-site dedup-table
  sync, backfilling T9's plan_outcome_recorded/plan_reopened rows too).
- SE2/SE5/SE6/SE7/SE8/SE9's own files are not yet declared — each builder adds its
  actual touched files here (or to the list above) when that task lands, per this
  section's standard purpose.

## Assumptions
- The governor ledger (T3) is the substrate; events append there with source= names per class.
- Hot-path cost discipline binds every emitter (T6's <5ms budget is the ceiling reference).

## Edge Cases
- An emitter must NEVER block or fail its host chokepoint (fail-open, logged).
- Classifier denials are invisible to hooks — SE5 records them only via the session's retry
  path; stated as an honest limit, not implied covered.

## Testing Strategy
Each SE task: discriminating scenarios + mutation transcripts, both interpreters by absolute
path, sandboxed state (the Scenario-16b idiom). The golden scenario for the plan: replay
2026-07-30's seven-agent spend-limit kill and show every kill/resume/landing as ledger rows.

## Files to Modify/Create
(Structural-completeness fix, 2026-07-30 — this plan was missing this required section
entirely, tripping `scope-enforcement-gate.sh`'s repo-wide PLAN_ERRORS check for every commit
in the repo, not just this plan's own. Derived STRICTLY from file/mechanism names already
named in the taxonomy table + Tasks above — no new scope invented. Vague entries (no exact
filename given yet by the table) are named honestly as TBD; the plan's actual owner should
pin these down as each SE task starts, not this fix.)
- `adapters/claude-code/scripts/estate-merge.sh` — SE1 (handoff-complete emit at the merge chokepoint):
  _em_log_merge now calls a new _em_emit_ledger_event at every terminal cmd_merge outcome.
- `adapters/claude-code/hooks/lib/progress-log-lib.sh` — SE1: two new event types, `merge_completed`
  and `merge_failed` (added to _pl_natural_key + the header's DEDUP table), and `estate-merge` added
  to `_PL_KNOWN_EMITTERS`.
- `adapters/claude-code/manifest.json` — SE1: `estate-merge` entry's golden_scenario updated (69/0
  self-test, was 52/0) and `progress-log` entry's honest_status gains splice (7) for estate-merge.sh.
- SE2's "sweep runner + a shared --self-test entry helper" — exact file TBD by SE2's own builder
- `adapters/claude-code/scripts/write-review-record.sh` — SE3 (emit every verdict, not PASS-only)
- plan-edit-validator (verifier) — SE4 (flip-time emit); exact path TBD by SE4's own builder
- stop-verdict-dispatcher + each blocking gate's block path — SE5; exact gate list TBD by SE5's own builder
- `adapters/claude-code/scripts/session-resumer.sh` + the notification consumer — SE6 (kill/resume pairing)
- auto-install summary line + ensure-* scripts — SE7 (deploy emits); exact files TBD by SE7's own builder
- `adapters/claude-code/hooks/lib/agent-heartbeat.sh` — SE8 (per-agent heartbeat wiring); path TBD if this
  lib does not yet exist under this exact name
- `adapters/claude-code/scripts/needs-you.sh` + `adapters/claude-code/scripts/nl-issue.sh` — SE9
  (decision/incident emits feeding the unified view)
- doctrine amendment (file TBD) — SE10 (vocabulary-lock doctrine + Stop-WARN vocabulary check)

## Drain disposition (gated-pipeline-master-2026-08 Task 21, REQ-C2, 2026-08-03)

DEFERRED, not closed: this plan uses a custom BUILT/PARTIAL/UNBUILT taxonomy table (SE1-SE13),
not `- [ ]` checkboxes, so the naive 0/10 checkbox count is a false-stale signal (correctly
flagged as such by the 2026-08-02 estate-entropy triage). Re-verified this pass: SE1/SE3/SE4/
SE10 confirmed BUILT (SHAs `4a2ca13`->`37b2a59f` reformulate); SE2, SE6, SE7 still genuinely
UNBUILT; SE5, SE8, SE9 still PARTIAL — real, substantial remaining work (5 of 13 taxonomy rows).
No commit to this plan since 2026-07-30 (4 days stale at drain time), no session currently
working it. "Not stale" is not the same claim as "currently active" — DEFERRED reflects that
distinction honestly. Status flipped ACTIVE -> DEFERRED. Resume trigger: next session building
SE2 (per-suite emit, the simplest fully-unbuilt row).
