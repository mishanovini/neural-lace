<!-- scaffold-created: 2026-07-30 (retroactive — see note below) -->
# Plan: limit-resume auto-resume watchdog
Status: ACTIVE
Execution Mode: direct
Mode: code
Backlog items absorbed: HARNESS-GAP-64, HARNESS-GAP-65, HARNESS-GAP-66
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

## Closure Outcome

<!-- Populated at close via close-plan.sh -->
