<!-- scaffold-created: 2026-07-30 (retroactive — see note below) -->
# Plan: limit-resume auto-resume watchdog
Status: COMPLETED
Execution Mode: direct
Mode: code
Backlog items absorbed: none
acceptance-exempt: true
acceptance-exempt-reason: harness-development — the maintainer is the user; no product/UI surface. The self-test suites (limit-resume.sh --self-test, install-limit-resume.sh --self-test, harness-doctor.sh --self-test) plus a real launchd end-to-end demonstration are the functional demonstration.
tier: 3
rung: 4
architecture: coding-harness
frozen: true
lifecycle-schema: v2
loe-class: harness-mechanism
owner: misha
target-completion-date: 2026-07-30
prd-ref: n/a — harness-development
ask-id: none — no linked ask

<!--
RETROACTIVE NOTE: this plan was authored after the build (single
dispatched, self-contained ad hoc task, operator directive verbatim
below) to satisfy scope-enforcement-gate.sh's commit-time requirement
that every staged file fall within an active plan's declared scope.
The build itself, the 5-round harness-reviewer history, and all
self-test evidence predate this file; this plan documents work already
done and verified, not prospective work. It will be closed via
close-plan.sh in the same session once every commit lands.
-->

## Goal

Operator (verbatim, 2026-07-30): "I'm guessing you're still not retriggering
yourself after the limits reset. How do we make that actually work?"

Replace the machine-local, hand-made, never-in-this-repo predecessor
(`~/.claude/state/limit-resume/resume.sh` + a manually-armed LaunchAgent) with a
repo-resident, self-tested, auto-arming watchdog that actually resumes a Claude
Code session killed by a usage limit, on macOS, without ever resuming a session
that is still alive.

## Files to Modify/Create

- `adapters/claude-code/scripts/limit-resume.sh` (new)
- `adapters/claude-code/scripts/install-limit-resume.sh` (new)
- `adapters/claude-code/scripts/install-limit-resume-task.ps1` (new, Windows, untested)
- `adapters/claude-code/hooks/session-start-digest.sh` (splice: arm + ensure)
- `adapters/claude-code/hooks/workstreams-stop-writer.sh` (splice: disarm)
- `adapters/claude-code/settings.json.template` (new UserPromptSubmit entry)
- `adapters/claude-code/hooks/harness-doctor.sh` (new check_limit_resume_watchdog)
- `adapters/claude-code/manifest.json` (new "limit-resume" entry)
- `docs/decisions/068-macos-limit-resume-turn-scoped-auto-arm.md` (new)
- `docs/backlog.md` (three gaps noticed in passing: HARNESS-GAP-64/65/66)
- `docs/reviews/records/2026-07-30-harness-change-review-3f821afe.json` (new, harness-reviewer PASS record)
- `docs/reviews/records/index.json` (regenerated index)
- `.claude/state/observed-errors.md` (machine-local, gitignored — not committed)

## Behavioral Contracts
<!-- Required at rung: 4 per plan-reviewer.sh Check 11. -->
- **Idempotency:** `arm` is safe to call repeatedly for the same session id —
  each call overwrites that session's own marker file (`$STATE_DIR/armed/<key>.json`)
  with a fresh `armed_at`, never appending or duplicating state. `install-limit-
  resume.sh ensure` only rewrites the LaunchAgent plist when its content actually
  differs and only re-bootstraps when not already loaded (self-tested S5:
  idempotent second `ensure` does not touch the plist's mtime).
- **Performance budget:** Each LaunchAgent tick (every 900s) is a no-op unless a
  marker is armed. When armed, the `claude -p --resume` child is bounded by
  `LIMIT_RESUME_TIMEOUT_SECONDS` (default 1800s) via `hooks/lib/portable-
  timeout.sh`'s `nl_run_bounded`; the tick itself takes an mkdir-based lock so at
  most one such child ever runs at a time, machine-wide.
- **Retry semantics:** Bounded exponential backoff after each failed attempt
  (900s/1800s/3600s, capped at 7200s), plus an unconditional 1800s floor before
  the FIRST attempt (never races the CLI's own internal retry). A hard stop at
  `LIMIT_RESUME_MAX_RETRIES` (default 8) writes a `giveup` sentinel that pins all
  further ticks for that session to a silent no-op (self-test S6, mutation-proof:
  pins the stub call count at MAX_RETRIES across further ticks) — surfaced, not
  silent, via `harness-doctor.sh`'s new WARN.
- **Failure modes:** (1) `claude` not on PATH → logged, tick no-ops, no crash.
  (2) Target session still alive (heartbeat classifies `live`/`throttled`/`stale`,
  or the 1800s floor hasn't elapsed) → skip, never spawn (self-tests S11/S12/S15).
  (3) Heartbeat oracle entirely unavailable → fails closed (`skip-no-oracle`), never
  assumes dead. (4) Recorded cwd no longer exists → disarms that session
  (`cwd-gone`) rather than running blind. (5) The spawn-concurrency lock's owner
  process crashes without releasing it → reclaimed only once the recorded owner
  pid is CONFIRMED DEAD via `kill -0` AND the lock is older than
  `TIMEOUT_SECONDS+120s` (self-tests S20/S21) — age alone is never sufficient
  (harness-reviewer round 4 PROVEN finding). (6) An automation-resumed child
  inherits `NL_HOOK_REENTRY=1`; `arm`/`tick` both check and no-op on that flag so
  a resumed child can never re-arm or re-tick itself (self-tests S18/S19).

## Tasks

- [x] 1 — Build the limit-resume watchdog (arm/disarm/tick/status +
      installer), wire it into the SessionStart/Stop/UserPromptSubmit chain,
      add doctor visibility + manifest entry, reconcile against FM-037/ADR-061,
      and land a harness-reviewer PASS.
      Verification: full

      **Prove it works:**
      1. `bash adapters/claude-code/scripts/install-limit-resume.sh install` on
         this Mac → real plist written, real `launchctl bootstrap` succeeds.
      2. `launchctl list | grep limit-resume` / `launchctl print
         gui/$UID/local.neurallace.limit-resume` → shows it loaded, pointing at
         the main-checkout script path (not a worktree).
      3. `bash adapters/claude-code/scripts/limit-resume.sh arm --session <id>
         --cwd <main-checkout>` → writes `~/.claude/state/limit-resume/armed/
         <id>.json`.
      4. `launchctl kickstart -k gui/$UID/local.neurallace.limit-resume` → a
         real launchd-triggered tick fires; `~/.claude/state/limit-resume/
         log.txt` shows a real `claude` invocation attempt (no PATH/env error)
         and a clean CLI-level outcome.
      5. `bash .../limit-resume.sh disarm <reason> --session <id>` (from the
         main checkout) → marker removed, logged.
      Executed and evidenced in this session (see commit 884537e's message and
      docs/decisions/068-macos-limit-resume-turn-scoped-auto-arm.md's Evidence
      sections) — captured at build time, not reconstructed after the fact.

      **Wire checks:**
      `adapters/claude-code/hooks/session-start-digest.sh` (run_digest, LIMIT-
      RESUME SESSIONSTART CALLSITE) → `adapters/claude-code/scripts/install-
      limit-resume.sh` (`cmd_ensure`) + `adapters/claude-code/scripts/limit-
      resume.sh` (`cmd_arm`) → `adapters/claude-code/hooks/workstreams-stop-
      writer.sh` (LIMIT-RESUME STOP CALLSITE) → `limit-resume.sh` (`cmd_disarm`)
      → `adapters/claude-code/settings.json.template` (new `UserPromptSubmit`
      entry invoking `limit-resume.sh arm`) → `adapters/claude-code/hooks/
      harness-doctor.sh` (`check_limit_resume_watchdog`, reads `${live_home}/
      state/limit-resume/armed/*.json`) → `adapters/claude-code/manifest.json`
      (`"id": "limit-resume"` entry).

      **Integration points:**
      - `hooks/lib/session-heartbeat-lib.sh`'s `hb_classify`/`hb_path_for` —
        verified via self-test (S12/S13/S15) and via a real dead session on
        this machine (`bash -c 'source .../session-heartbeat-lib.sh;
        hb_classify ~/.claude/state/heartbeats/<real-dead-sid>.json 30'` →
        `crashed`).
      - `hooks/lib/portable-timeout.sh`'s `nl_run_bounded` — bounds the
        `claude -p --resume` child; verified present and callable.
      - `hooks/lib/hook-reentry-guard.sh`'s `NL_HOOK_REENTRY` contract —
        verified the resumed child is spawned with it set (self-test S9) and
        that `arm`/`tick` themselves no-op under it (self-test S18).
      - `manifest-check.sh check` → GREEN, 150 entries, 0 warn.

## Testing Strategy

- `bash adapters/claude-code/scripts/limit-resume.sh --self-test` — 21 scenarios,
  run under both `/bin/bash` (3.2.57) and `/opt/homebrew/bin/bash` (5.3.15).
- `bash adapters/claude-code/scripts/install-limit-resume.sh --self-test` — 7
  scenarios, both interpreters.
- `bash adapters/claude-code/hooks/harness-doctor.sh --self-test` — 5 new
  `limit-resume-watchdog-*` scenarios; full suite 153/154 in this session's
  environment (the 1 failure pre-existing and unrelated, confirmed by diff).
- `bash adapters/claude-code/scripts/manifest-check.sh check` — GREEN.
- Real (non-self-test) end-to-end demonstration on this machine, twice (before and
  after the review-driven rewrite): real `install`, real `launchctl bootstrap`,
  `launchctl list`/`print` confirms loaded, armed manually, real `launchctl
  kickstart -k` forces an immediate tick, the real `claude` binary resolves and
  runs under real launchd's minimal environment (no PATH/env error), a clean
  CLI-level failure (fake session id, never against anything live), logged,
  disarmed. See the completion evidence in commit 884537e and
  docs/decisions/068-macos-limit-resume-turn-scoped-auto-arm.md.
- `harness-reviewer` dispatched 5 times (adversarial, independent probes each
  round, not code-read-only): REJECT x4 (every finding PROVEN before being fixed),
  PASS on round 5. Record: `docs/reviews/records/2026-07-30-harness-change-review-3f821afe.json`.

## Decisions Log

- 2026-07-30: Turn-scoped arming (SessionStart + UserPromptSubmit arm, Stop
  disarm) chosen over session-scoped arming because Claude Code's Stop hook fires
  per-turn, not per-session — session-scoped arming would only ever protect a
  session's first turn. See `docs/decisions/068-macos-limit-resume-turn-scoped-
  auto-arm.md` for the full reconciliation against FM-037 and ADR-061.
- 2026-07-30: One genuinely new `UserPromptSubmit` hooks[] entry accepted (not a
  splice) because that event carries no doctor-enforced chain budget today,
  unlike SessionStart (8/8 cap) and Stop.
- 2026-07-30: Liveness gate is an ALLOWLIST (proceed only on `hb_classify ==
  "crashed"`), not a deny-list — reached via harness-reviewer round 2's PROVEN
  finding that a deny-list spawned on `throttled`/`stale`. This also means the
  `throttled` (alive, limit-paused) subset has NO live auto-resume coverage in
  this repo — a named, accepted scope boundary (ADR-061 D4 owns that subset via
  its own still-unarmed deferral ladder).
- 2026-07-30: Lock release/reclaim made ownership-token-scoped (harness-reviewer
  round 4 PROVEN finding that age-only reclaim + an unconditional EXIT-trap
  `rmdir` together allowed 2 concurrent spawn children).

## Evidence Log

### Task 1 — Build the limit-resume watchdog, wire it in, land a harness-reviewer PASS

Task ID: 1

Verdict: PASS

Runtime verification (this session):
- `bash adapters/claude-code/scripts/limit-resume.sh --self-test` → "21 passed,
  0 failed" on both `/bin/bash` 3.2.57 and `/opt/homebrew/bin/bash` 5.3.15.
- `bash adapters/claude-code/scripts/install-limit-resume.sh --self-test` →
  "7 passed, 0 failed", both interpreters.
- `bash adapters/claude-code/hooks/harness-doctor.sh --self-test` → "153 passed,
  1 failed" (the 1 failure, `orphaned-worktree-work-live-owned-green`,
  pre-existing and unrelated — `git diff --stat` on harness-doctor.sh is purely
  additive, 146 insertions/0 deletions, touching neither that check nor its
  dependencies). All 5 `limit-resume-watchdog-*` scenarios pass.
- `bash adapters/claude-code/scripts/manifest-check.sh check` → "GREEN — 150
  entries, 123 hooks covered, 0 warn".
- Real end-to-end demonstration (twice — before and after the review-driven
  rewrite): `install-limit-resume.sh install` → real `launchctl bootstrap` →
  `launchctl list`/`print` confirms loaded → armed manually → real `launchctl
  kickstart -k` forces an immediate tick → the real `claude` binary resolves
  under real launchd's minimal environment (no PATH/env error — DEFECT 1
  proven fixed) → a clean CLI-level failure (fake session id, never against
  anything live) → logged → disarmed. Re-verified with the corrected scripts
  temporarily placed at the real main-checkout path: the installed plist's
  `ProgramArguments` resolved there, not a worktree.
- `harness-reviewer` (opus, 5 independent dispatches, each running its own
  adversarial probes rather than reading code): REJECT (8 findings) → REJECT
  (2 Critical) → REJECT (1 Critical) → REJECT (1 Critical + 2 Major) → **PASS**
  (0 Critical, 0 Major, 3 Minor advisories, all addressed in the same commit
  series). Round 5's own controlled A/B probe: current code held concurrency at
  1 child; a control arm with only the ownership token stripped reproduced 2
  concurrent children — proving the fix, not just asserting it. Record:
  `docs/reviews/records/2026-07-30-harness-change-review-3f821afe.json`.

Known residual gap (named, not hidden): a literal observed SUCCESS
(`claude -p --resume` returning a continued transcript against a real session)
was not captured — the auto-mode classifier blocked further manipulation of a
real session's identifiable state mid-demonstration; not circumvented. The
success PATH is proven by self-test (stub-based) and by construction (identical
code path, differing only in the target CLI call's outcome), and the SAME
liveness oracle was independently confirmed correct against a real dead session
on this machine.

Commits: 884537e (core scripts), 65ae44a (hook splices), 05a6693 (doctor +
manifest), 31b9e92 (decision doc + backlog).

## Completion Report

_Generated by close-plan.sh on 2026-07-30T22:37:29Z._

### 1. Implementation Summary

Plan: `docs/plans/limit-resume-watchdog-2026-07-30.md` (slug: `limit-resume-watchdog-2026-07-30`).

Files touched (per plan's `## Files to Modify/Create`):

- `.claude/state/observed-errors.md`
- `adapters/claude-code/hooks/harness-doctor.sh`
- `adapters/claude-code/hooks/session-start-digest.sh`
- `adapters/claude-code/hooks/workstreams-stop-writer.sh`
- `adapters/claude-code/manifest.json`
- `adapters/claude-code/scripts/install-limit-resume-task.ps1`
- `adapters/claude-code/scripts/install-limit-resume.sh`
- `adapters/claude-code/scripts/limit-resume.sh`
- `adapters/claude-code/settings.json.template`
- `docs/backlog.md`
- `docs/decisions/068-macos-limit-resume-turn-scoped-auto-arm.md`
- `docs/reviews/records/2026-07-30-harness-change-review-3f821afe.json`
- `docs/reviews/records/index.json`

Commits referencing these files:

```
00293c4 docs(discoveries): triage remaining pending — 4 status flips + 1 current-state note + HARNESS-GAP-50
0090d4b feat(hook): bug-persistence-gate.sh — mechanical enforcement of testing.md rule
00d592d fix(macos-portability M6): S11 flake root-caused + fixed (retry-guard state leak) + baseline housekeeping
038503e fix(D.5 remediation): doctor --full REDs — pr-template repo-root class fix + pin-d command repair, extract-pending runtime repoint (feature was dead live), heartbeat-theater doc honesty — findings 022/023
038a0a9 fix(review-record): index honesty-laundering (REFORMULATE finding 2)
038c648 fix(session-start-digest): honor the reentry guard at the --self-test entry point (T2); single-flight the SessionStart default path per repo root (T3)
03a7827 evidence(D.5 addendum): doctor --full LITERAL GREEN 8/8 — first full-sweep green; backlog v64
05a6693 feat(limit-resume): doctor visibility check + manifest entry
05db587 chore(wave-o): orchestrator fragment application — manifest, template, consumer-map
0758232 fix(harness): ask-id sentinel class — extend the '<'-placeholder guard to the literal 'none' spelling (re-review REFORMULATE fixes)
07691d5 feat(conv-tree): Claude-side event emitter — Dispatch conversations auto-populate the GUI
07a114d NL Overhaul Wave E batch 2: E.3 waiver-density, E.4 synthetic-runner, E.5 KPIs, E.6 NEEDS-YOU, E.10 incentive-pin retrofit (#82)
07c9f8e review-record(batch): real harness-reviewer PASS record hcr-20260716-30d61135 supersedes placeholder
086fcd5 NL Overhaul §E.W integration cutover: template wiring + manifest merge (Wave-E live wiring) (#86)
08a3351 sweep batch 4 + adr061-P1b: verifier flips, set-e class sweep [24], reentry-safe heartbeats (D2), health tick (D6, unarmed) (#97)
099d4e2 feat(phase-1d-c-2): Task 9 — wire prd-validity-gate + spec-freeze-gate into settings.json (template + live)
0b14705 fix(scope-gate): Windows drive-letter git-dir recognized as absolute (+ HARNESS-GAP-27 docs superseded) (#27)
0b56c31 docs(strategy): capture Claude Code quality strategy + backlog gaps
0be6526 feat(hook): A1 — independent goal extraction (UserPromptSubmit + Stop)
0debef7 review-record(rq-20260730-7fc41fb1): PASS on 1 file(s) by harness-reviewer (independence: pathway)
1007841 fix(review-record): surface-vs-enforcement parity (REFORMULATE finding 1)
10adac2 feat(plan-reviewer): land Check 8A — Pre-Submission Audit gate on Mode: design plans
10effe9 verify(wave-o): O.6 flipped by task-verifier — PASS conf 9 (hb_classify fix proven 3 ways; 2 live REDs = truthful estate debt, filed) + auto-triage row
119bd26 fix(wave-o-o6): re-point obs-heartbeats-fresh to the canonical staleness oracle
11c9d13 docs(backlog): correct decision-context finding — bug #3 (Windows node-path) REFUTED; gate core verified working post path-fix + zod (P1->P2)
120593c feat(harness): plan-closure-validator gate + /close-plan skill (HARNESS-GAP-16, Phase 1d-H)
123dcaa fix-trivial(agent-efficiency T5): correct the hook-shim backlog row honesty gap
1397c34 feat(continuous-operation): supervisor-tick — orphan detection + alerting (squash of build/supervisor-tick)
14c4dfc feat(hook): session-start-git-freshness — fetch + behind + WIP-branch warns (#46)
1505d27 fix(gate): repo-scope ownership claims + reviewer minors (harness-review round 1)
```

Backlog items absorbed: see plan header `Backlog items absorbed:` field;
the orchestrator can amend this section post-procedure with shipped/deferred
status per item.

### 2. Design Decisions & Plan Deviations

See the plan's `## Decisions Log` section for the inline record. Tier 2+
decisions should each have a `docs/decisions/NNN-*.md` record landed in
their implementing commit per `~/.claude/rules/planning.md`.

### 3. Known Issues & Gotchas

(orchestrator may amend post-procedure)

### 4. Manual Steps Required

(orchestrator may amend post-procedure — env vars, deploys, third-party setup)

### 5. Testing Performed & Recommended

See the plan's `## Testing Strategy` and `## Evidence Log` sections.
This procedure verifies that every task has its declared verification level
satisfied before allowing closure.

### 6. Cost Estimates

(orchestrator may amend; harness-development plans typically have no recurring cost — n/a)

## Closure Outcome

_Written by close-plan.sh at closure (2026-07-30T22:37:28Z)._

Outcome metric: no outcome metric declared by the plan at close time
Re-check date: 2026-08-13T15:37:28Z (default)

Evidence pointers:
- 00293c4 docs(discoveries): triage remaining pending — 4 status flips + 1 current-state note + HARNESS-GAP-50
- 0090d4b feat(hook): bug-persistence-gate.sh — mechanical enforcement of testing.md rule
- 00d592d fix(macos-portability M6): S11 flake root-caused + fixed (retry-guard state leak) + baseline housekeeping
- 038503e fix(D.5 remediation): doctor --full REDs — pr-template repo-root class fix + pin-d command repair, extract-pending runtime repoint (feature was dead live), heartbeat-theater doc honesty — findings 022/023
- 038a0a9 fix(review-record): index honesty-laundering (REFORMULATE finding 2)
- 038c648 fix(session-start-digest): honor the reentry guard at the --self-test entry point (T2); single-flight the SessionStart default path per repo root (T3)
- 03a7827 evidence(D.5 addendum): doctor --full LITERAL GREEN 8/8 — first full-sweep green; backlog v64
- 05a6693 feat(limit-resume): doctor visibility check + manifest entry
- 05db587 chore(wave-o): orchestrator fragment application — manifest, template, consumer-map
- 0758232 fix(harness): ask-id sentinel class — extend the '<'-placeholder guard to the literal 'none' spelling (re-review REFORMULATE fixes)
