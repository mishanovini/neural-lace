# Plan — Status-event ledger: a deterministic trigger for EVERY status event

Status: ACTIVE
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
| 4 | handoff complete (builder commit landed) | estate-merge.sh + the orchestrator's cherry-pick → emit at the merge primitive (T5's single merge path IS the chokepoint) | **UNBUILT** — SE1 |
| 5 | suite run pass/fail counts | the sweep runner + a per-suite emit wrapper at the --self-test entry | **UNBUILT** — SE2 |
| 6 | review verdict INCLUDING non-PASS | write-review-record.sh emits every verdict; records index gains non-PASS entries (REVIEW-INDEX-FAILURE-BLIND-01) | **BUILT** — SE3 (cmd_capture emits a `review-verdict` ledger event on EVERY verdict, unconditionally; index already folded non-PASS rows, now proven by self-test S21/S22, 22/22 both interpreters. RESIDUAL: nothing forces capture to be CALLED for a non-queue-pathway review — an uncaptured verdict still emits nothing, honestly unchanged) |
| 7 | verification verdict + checkbox flip | plan-edit-validator already gates the flip; add emit at validation | **BUILT** — SE4 (emit_flip_ledger_event fires a `flip-verdict` ledger event {plan, task, verdict, confidence, verifier} on every AUTHORIZED flip; self-test F16/F17, 12/17 both interpreters — the 5 pre-existing F5-F9 failures are an unrelated, pre-existing `stat -c %Y` portability bug, PROVEN unchanged on the unmodified file, docs/backlog.md HARNESS-GAP-62) |
| 8 | blocked (gate/classifier) | stop-verdict-dispatcher + each blocking gate's block path emits | **PARTIAL** — ledger-24h counts exist; per-event rows unbuilt — SE5 |
| 9 | killed (limit/API death) + resumed | the wake/notification consumer + session-resumer emit kill/resume pairs | **UNBUILT** — SE6 (the 7-agent kill on 2026-07-30 is the golden scenario) |
| 10 | deploy (auto-install sync / LaunchAgent restart) | auto-install summary line → emit; ensure-* kickstart → emit (merged≠deployed bit twice on 2026-07-29) | **UNBUILT** — SE7 |
| 11 | heartbeat during long work (running vs parked) | agent-heartbeat.sh on a tick per live agent | **PARTIAL** — lib exists; per-agent wiring unbuilt — SE8 |
| 12 | decision asked/answered | needs-you.sh add/resolve emits | **PARTIAL** — ledger writes exist; governor-ledger mirror unbuilt — SE9 |
| 13 | incident/error observed | nl-issue.sh + observed-errors append emit | **PARTIAL** — own stores exist; unified feed unbuilt — SE9 |

## Tasks

- [ ] SE1 — Handoff-complete emit at estate-merge.sh (the single merge chokepoint) + the
      orchestrator cherry-pick path. Verification: full.
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
- SE1/SE2/SE5/SE6/SE7/SE8/SE9's own files are not yet declared — each builder adds its
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
- `adapters/claude-code/scripts/estate-merge.sh` — SE1 (handoff-complete emit at the merge chokepoint)
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
