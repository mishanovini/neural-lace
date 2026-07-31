# Review: build/cockpit-sessionstart (afdedee) — SessionStart cockpit-ensure

Date: 2026-07-09. Reviewers: harness-reviewer + code-reviewer (parallel), every
Critical/Major finding independently adversarially verified (refutation attempts with
live probes). Orchestrator independently re-proved builder evidence before review:
`ensure-cockpit.sh --self-test` 16/16 from the exact commit (detached worktree);
`session-start-digest.sh --self-test` 70/71 with the single failure confirmed as the
known pre-existing S2 "'all quiet'" fixture-isolation flake.

## Verdicts

- **harness-reviewer: PASS-conditional.** Classification: Mechanism-class,
  non-blocking (best-effort ensure, no gate — Rule 10 gate bar N/A). All headline
  claims reproduced mechanically (self-test, settings-template zero-diff, real 8/8
  SessionStart cap, fd-chain traced: nohup child never holds the hook's stdout pipe).
  Conditions: manifest entry before landing; coverage-intent recorded before the logon
  task is unregistered.
- **code-reviewer: FAIL (narrow remediation).** Mechanism well-built (`${$}` valid,
  set -u safe on all paths, argv quoting handles spaces, no orphan accumulation, TOCTOU
  race on cold port proven benign — losing nodes EADDRINUSE-exit); fails its own stated
  outcome on resolver scope + mechanism-less replacement claim.

## Findings (Majors adversarially verified NOT-refuted) and dispositions

1. **Major/PROVEN — cwd-scoped launcher resolution = coverage regression** vs the
   machine-wide logon task being replaced. Live-probed: from a sibling app repo the
   ensure silently no-ops ("launcher not found at <otherproj>/neural-lace/...") while
   `~/.claude/local/nl-repo-path` (canonical machine-wide resolver input) points at the
   real checkout. Escalates to Critical the moment the logon task is unregistered.
   **FIXED:** resolution is now machine-wide-first via `nl_repo_root()` (env → install
   config → lib-location git → probe), normalized through `nl_main_checkout_root()` run
   from the resolved root (never a worktree), with the original session-cwd derivation
   kept as fallback. New self-tests S10a (machine-wide from non-NL cwd) / S10b
   (worktree-pointing config normalizes to MAIN).
2. **Major/PROVEN — no manifest.json entry** for a SessionStart-fired spliced script
   (inventory-honesty drift; doctor-invisible because manifest-check's disk sweep covers
   `hooks/*.sh` only). **FIXED:** `ensure-cockpit` writer entry added (mirrors
   session-heartbeat). **Class follow-up filed as nl-issue:** extend manifest-check
   disk scope to hook-referenced `scripts/` files.
3. **Major/PROVEN — "replaces the logon task" claim had no retiring mechanism**
   (constitution §1 class). **FIXED:** header/callsite/manifest wording now names the
   retirement as a recorded integration step; the integrating session actually performs
   `register-autostart.ps1 -Unregister` and records it in the merge commit.
4. **Minor/PROVEN — no operator kill-switch.** **FIXED:** guard 0 —
   `ENSURE_COCKPIT_DISABLE=1` (env) or `~/.claude/local/cockpit-disabled` (durable
   flag file); self-tests S11a/S11b.
5. **Minor/PROVEN — unbounded log + leaked per-PID selftest tmp dirs.** **FIXED:**
   64KB/200-line tail-cap in `_ec_log`; entry point removes its own implicit selftest
   sandbox dir.
6. **Minor/PROVEN — S7 asserted intent not effect** (log line written before spawn; a
   broken spawn still passed). **FIXED:** stand-in writes a marker pre-sleep; S7 polls
   for it (proves child exec'd) while still asserting the ≤2s non-blocking return.

## Decision (decide-and-go, constitution §8 — presented for operator review)

**Coverage = MACHINE-WIDE** (cockpit ensured from any project's session, not only
NL-rooted sessions). Rationale: the replaced logon task was machine-wide; the cockpit
is a cross-project observability surface (`workstreams-ui/config/projects.js`
auto-discovers sibling projects); the digest hook fires in every session machine-wide.
Reversal = one revert of the resolver block. Accepted narrowing vs the logon task: the
logon-to-first-Claude-session window has no cockpit — inherent to the session-tied
lifecycle the operator chose ("ensured-up on every NL SessionStart instead of a
boot-time scheduled task").
