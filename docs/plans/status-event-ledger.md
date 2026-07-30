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
| 6 | review verdict INCLUDING non-PASS | write-review-record.sh emits every verdict; records index gains non-PASS entries (REVIEW-INDEX-FAILURE-BLIND-01) | **UNBUILT** — SE3 |
| 7 | verification verdict + checkbox flip | plan-edit-validator already gates the flip; add emit at validation | **UNBUILT** — SE4 |
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
- [ ] SE4 — Flip-time emit in plan-edit-validator (verifier, verdict, confidence).
      Verification: full.
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
