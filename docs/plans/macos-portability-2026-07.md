# Plan — macOS portability (this Mac is a first-class harness-dev machine)

Status: ACTIVE
Mode: code
Owner: interactive session (2026-07-28, operator-directed)
Backlog items absorbed: none
acceptance-exempt: yes (harness-internal; the maintainer is the user, demonstrated by the
self-test sweep going green and by the Stop-hook false alarm ceasing)

## Why

Operator directive 2026-07-28: this Mac is a **first-class harness-dev machine**, not a
read-only satellite. The harness was authored on Windows (Git-bash, bash 5.x, GNU coreutils)
and this machine's defaults are Apple's bash 3.2.57 (2007, GPLv2 — Apple never upgraded) and
BSD userland. Measured baseline on the system interpreter: **14 of 52 self-test-capable
scripts FAILED**.

The environment half is already fixed and measured:

| Interpreter + tools | Pass | Fail |
|---|---|---|
| `/bin/bash` 3.2.57 + BSD userland | 38 | **14** |
| Homebrew bash 5.3.15 + GNU coreutils/sed/grep/findutils | 49 | **3** |

All 3 residual failures are `attic/` scripts (retired), so the environment change closes the
entire LIVE-harness portability class with zero code edits. That change is now durable: an
`env.PATH` block was added to this machine's `~/.claude/settings.json` (machine-local, not in
this repo) putting the GNU toolchain ahead of Apple's.

> **CORRECTION (2026-07-29, task M5 — the table above is WRONG and its conclusion does not
> hold).** M5 recovered the ad-hoc sweep's output files from the session scratchpad
> (`results-baseline-bash32.tsv`, `results-bash5-gnu.tsv`, 52 rows each) and its script
> (`sweep.sh`). Both result files end at the SAME row —
> `adapters/claude-code/hooks/gh-merge-canonical-gate.sh` — i.e. mid-alphabet inside `hooks/`.
> The script's inventory pathspec `git ls-files 'adapters/claude-code/**/*.sh'` resolves to
> **245** files in this repo, not 52. The run was TRUNCATED at 52 and its partial output was
> read as a complete inventory. Of those 52 rows, 24 are `attic/` and 28 are `hooks/a*`
> through `hooks/g*`; **`scripts/` was never reached at all**, so "all 3 residual failures are
> attic scripts" was a statement about a sample that could not contain a `scripts/` failure.
> The first COMPLETE measurement is M5's: 163 self-test-capable scripts (live scope: `hooks`,
> `hooks/lib`, `scripts` — attic and tests excluded by default), **111 pass / 52 fail** on
> `/bin/bash` 3.2.57 + BSD. 28 of the 52 failures are in `scripts/`, the directory the
> original sweep never saw. The `env.PATH` change therefore did NOT close the live-harness
> portability class; it hid it on this one machine. See `docs/portability-baseline.txt`.

What the environment does NOT fix is harness code that hard-codes GNU-only invocations and
therefore breaks for any operator on a Mac without that PATH — including a fresh checkout,
a cloud/scheduled session, or another person's machine. Measured counts in-repo:
`timeout` called by 12 files, `date -d` by 21, GNU `sed -i` (no suffix arg) by 4.

The recurring live symptom this plan exists to kill: `session-wrap.sh:319` runs
`sed -i "s|...|" "$scratchpad"`. BSD `sed -i` REQUIRES a backup-suffix argument, so it
consumes the script as the suffix and treats the path as the command —
`sed: 1: "/Users/misha/Claude/neu ...": invalid command code m`. The SCRATCHPAD stamp
therefore never refreshes, and the Stop hook reports `SCRATCHPAD.md is N min stale` forever,
unfixable by the agent. It fired 3+ times in one session and had to be hand-patched each time.

## Scope / Tasks

- [ ] M1 — Fix `session-wrap.sh:319`'s GNU-only `sed -i` so the SCRATCHPAD stamp refresh works
      on BSD sed. Use a portable form (`sed -i.bak … && rm -f …`, or tmp+mv) — NOT `sed -i ''`,
      which is itself GNU-incompatible. Outcome: running `session-wrap.sh refresh` on this Mac
      updates the stamp and the Stop hook stops reporting a false STALE.
      Verification: full (run it, observe the stamp change and the signal clear).
- [ ] M2 — Sweep the other 3 GNU-only `sed -i` callsites found by
      `grep -rlE "sed -i '?[^'\"]*'? " adapters/claude-code --include='*.sh'` and apply the
      same portable form. Decompose per-file before starting (planning doctrine: sweep tasks
      decompose per-target). Verification: full, per file.
- [ ] M3 — Audit the 12 `timeout` callsites. GNU `timeout` is absent on stock macOS. Decide
      per callsite: guard with a `command -v timeout` fallback, or use the portable
      background+poll+kill idiom already written in this repo. Verification: full, per file.
- [ ] M4 — Audit the 21 `date -d` callsites (GNU-only; BSD needs `date -j -f`). Prefer
      eliminating the call (file mtime, `$EPOCHSECONDS`) over dual-syntax branching, since
      dual-syntax doubles the fork cost on any hot path. Verification: full, per file.
- [ ] M5 — Make portability a MECHANISM rather than a memory: a self-test sweep runner
      committed to the repo (the ad-hoc script used for the measurement above) plus a doctor
      check that runs it and REDs on a regression, so the next GNU-ism is caught at authoring
      time instead of by an operator hitting it. Verification: full.
- [ ] M6 — Decide the disposition of the 3 residual `attic/` failures: fix, or move them out
      of the self-test-capable set with a stated reason. They are retired scripts, so
      "documented as out of scope" is an acceptable outcome — silence is not.
      Verification: mechanical (disposition recorded).

## Files to Modify/Create
- `adapters/claude-code/scripts/session-wrap.sh` — M1
- the 3 other GNU-`sed -i` files identified by M2's grep — M2
- the 12 `timeout` callsites — M3
- the 21 `date -d` callsites — M4
- a sweep runner under `adapters/claude-code/scripts/` + a `harness-doctor.sh` check — M5
- `docs/plans/macos-portability-2026-07.md` — this plan

## Assumptions
- The `env.PATH` block in this machine's `~/.claude/settings.json` stays in place; it is
  machine-local and NOT committed, so it protects only this Mac. That is precisely why the
  code-level fixes (M2-M4) still matter: they protect every other macOS entry point.
- Windows machines are unaffected by making a call portable — GNU accepts the portable forms.
  Any change that would alter Windows behavior is out of scope and must be flagged.

## Edge Cases
- `sed -i ''` is the common macOS "fix" and is WRONG here: it breaks GNU sed, which would
  invert the bug onto the Windows machines. Use `-i.bak` + `rm`, or tmp+mv.
- A `timeout` fallback must not silently run unbounded — if no timeout mechanism exists, the
  callsite must say so rather than quietly dropping the bound.
- Hot paths (`admission-lib.sh` and any per-dispatch hook) must not gain forks from dual-syntax
  date handling; that trades one portability bug for a measured performance regression.

## Testing Strategy
The sweep runner is the oracle: 52 self-test-capable scripts, run under BOTH `/bin/bash` 3.2
and Homebrew bash 5.3, before and after each task. Baseline to beat: 38/14 on the system
interpreter. Every task cites its own before/after counts, and M5 makes that comparison a
doctor check so it cannot silently rot.

## In-flight scope updates
- 2026-07-29: docs/plans/macos-portability-2026-07.md — this plan
- 2026-07-29: adapters/claude-code/git-hooks/pre-commit — exec bit restored; git silently ignores a non-executable hook, so this gate had never fired on this Mac
- 2026-07-29: adapters/claude-code/git-hooks/post-commit — same
- 2026-07-29: adapters/claude-code/git-hooks/pre-push — same
- 2026-07-29: adapters/claude-code/git-hooks/pre-push-pr-template.sh — same
- 2026-07-29: adapters/claude-code/scripts/ntfy-push.sh — M2: GNU-only `sed -i` -> tmp+mv (the primary invocation always failed on BSD; a `||` fallback was silently carrying the self-test)
- 2026-07-29: adapters/claude-code/scripts/supervisor-tick.sh — M2: GNU-only `sed -i -E` -> tmp+mv (BSD bound `-E` as the backup suffix, littering the orphans ledger with `<key>.json-E`)
- 2026-07-29: adapters/claude-code/hooks/harness-claim-lint.sh — CLASS3 rewritten from a text match to a BEHAVIORAL oracle + discovered host list (1 lib/3 hosts -> 8 libs/33 hosts)
- 2026-07-29: docs/harness-architecture.md — regenerated for the new manifest entries; closes the doctor's wave-f-f2-docs RED
- 2026-07-29: `adapters/claude-code/hooks/lib/portable-timeout.sh` — M3: shared `nl_run_bounded` primitive (GNU timeout when present, else background+bounded-spin+process-tree kill; returns 124 like GNU)
- 2026-07-29: `adapters/claude-code/hooks/harness-doctor.sh` — M3 callsite
- 2026-07-29: `adapters/claude-code/hooks/runtime-verification-executor.sh` — M3 callsite
- 2026-07-29: `adapters/claude-code/hooks/propagation-trigger-router.sh` — M3 callsite
- 2026-07-29: `adapters/claude-code/hooks/session-start-git-freshness.sh` — M3 callsite
- 2026-07-29: `adapters/claude-code/hooks/session-start-auto-install.sh` — M3 callsite
- 2026-07-29: `adapters/claude-code/scripts/ask-registry.sh` — M3 callsite
- 2026-07-29: `adapters/claude-code/scripts/master-drift-autocorrect.sh` — M3 callsite
- 2026-07-29: `adapters/claude-code/scripts/supervisor-tick.sh` — M3 callsite
- 2026-07-29: `adapters/claude-code/scripts/health-tick.sh` — M3 callsite
- 2026-07-29: `adapters/claude-code/scripts/f4-retro.sh` — M3 callsite
- M4 — decomposed per-target (planning doctrine: sweep tasks decompose before
- `adapters/claude-code/hooks/lib/portable-time.sh` — M4 (NEW: the one portable helper)
- `adapters/claude-code/hooks/concurrent-ownership-gate.sh` — M4
- `adapters/claude-code/hooks/harness-hygiene-scan.sh` — M4
- `adapters/claude-code/hooks/lib/interactive-session-lock.sh` — M4
- `adapters/claude-code/hooks/lib/perf-tick-snapshot.sh` — M4
- `adapters/claude-code/hooks/plan-deletion-protection.sh` — M4
- `adapters/claude-code/hooks/spec-freeze-gate.sh` — M4
- `adapters/claude-code/hooks/stalled-work-surfacer.sh` — M4
- `adapters/claude-code/hooks/task-created-validator.sh` — M4
- `adapters/claude-code/hooks/wire-check-gate.sh` — M4
- `adapters/claude-code/hooks/workstreams-stop-gate.sh` — M4
- `adapters/claude-code/scripts/broadcast-active-session.sh` — M4
- `adapters/claude-code/scripts/measure-claim-reviewer-rate.sh` — M4
- `adapters/claude-code/scripts/mine-misha-asked.sh` — M4
- `adapters/claude-code/scripts/session-snapshot.sh` — M4
- `adapters/claude-code/scripts/worktree-hygiene-sweep.sh` — M4
- `docs/backlog.md` — M4 (follow-ups: the sibling `touch -d` class, the audit
- 2026-07-29: `adapters/claude-code/scripts/portability-sweep.sh` — M5: NEW. The committed replacement for the lost ad-hoc measurement script. Discovers every script that really dispatches on the self-test flag, runs each under one named interpreter with a bounded per-script and total budget, pins child interpreter resolution so the interpreter it reports is the one that actually ran, and compares the failing set to a committed baseline.
- 2026-07-29: `docs/portability-baseline.txt` — M5: NEW. The committed known-failing set the doctor compares against. Raising it is a reviewable diff, not a number edited inside a script.
- 2026-07-29: `adapters/claude-code/hooks/harness-doctor.sh` — M5: new check 9 plus a new portability-only mode; ALSO the check-8 scope fix, whose top-level glob had never matched the hooks lib subdirectory, so 20 libraries' self-test assertions had never run under the doctor.
- 2026-07-29: `adapters/claude-code/hooks/lib/nl-paths.sh` — M5: added an explicit self-test flag dispatch. It previously ran its suite on any direct execution, which no discovery predicate could safely detect, so it sat outside the sweep.
- NOT changed by M4, deliberately: `adapters/claude-code/install.sh` and
- 2026-07-29: `docs/reviews/2026-07-14-mac-setup-incident.md` — the first-install record for this Mac; documents the symlink-based install whose source==target collision destroyed hooks/lib/ today
- 2026-07-29: `docs/operator-todo.md` — needs-you mirror entries accumulated this session
- 2026-07-29: `adapters/claude-code/install.sh` — SELF-SYNC-01 guard, the fix for the collision recorded in the incident file above. Detection only; no redesign. Path resolution is cd + pwd -P because stock macOS has no realpath and no readlink -f, so this is portability work in the same class as M2/M3/M4.
- 2026-07-29: `adapters/claude-code/tests/install-self-sync-guard-test.sh` — NEW. Twelve scenarios pinning SELF-SYNC-01: six same-path topologies that must skip, five different-path topologies that must behave exactly as before, one path-resolution unit check. Verified on bash 3.2.57 and 5.3.15.
- 2026-07-29: `docs/decisions/065-macos-cockpit-launchagent.md` — operator directive "I want the macOS launch permanent"; ensure-cockpit.sh gains a Darwin LaunchAgent branch (Windows path unchanged) so the cockpit auto-starts on this Mac and survives a reboot, closing the same "this Mac is a first-class harness-dev machine" gap this plan tracks
- 2026-07-29: `docs/DECISIONS.md` — index row for 065
- 2026-07-29: `adapters/claude-code/scripts/ensure-cockpit.sh` — tracked as git mode 100644 since introduction; `session-start-digest.sh` execs it directly, so the ENTIRE mechanism (Windows included) was inert on any POSIX checkout. `chmod +x` in the same commit. Same class as the 2026-07-14 incident's I3 exec-bit finding — a repo-wide sweep of `git ls-files -s | grep '^100644.*\.sh$'` against direct-exec callsites is filed in `docs/backlog.md`.

- 2026-07-29: `docs/decisions/065-self-sync-guard-signal-level.md` — NEW Tier-2 decision doc: shared-lib-vs-fork, skip-vs-louder signal level, the kill-switch addendum, and the declined "refuse locally-newer content in general" judgment call.
- 2026-07-29: `adapters/claude-code/hooks/lib/self-sync-guard.sh` — NEW. SELF-SYNC-01 detection primitives (`resolve_real_path`, `_sync_self_check`, `_resolves_into_dir`) extracted so `session-start-auto-install.sh` doesn't fork a second copy of install.sh's hand-rolled path resolution. `install.sh` itself not yet retrofitted to source it (docs/backlog.md SELF-SYNC-GUARD-INSTALLSH-RETROFIT-01; reasoning in docs/decisions/065-self-sync-guard-signal-level.md).
- 2026-07-29: `adapters/claude-code/hooks/session-start-auto-install.sh` — SELF-SYNC-01 guard: the SAME incident (27 files of committed branch work overwritten with older origin/master content, including hooks/model-pin-gate.sh 265 -> pre-change) via a DIFFERENT code path than install.sh's `rm -rf` (this hook's `cp "$tmp" "$target"` per-file overwrite in `sync_canonical_files`, plus the stale-flat-skill prune's `rm -f` and the settings-merge's `mv`). All three write/delete paths now guarded. Decision (docs/decisions/065): fold every skip into the existing always-printed per-run summary line (`N_SELF_SYNC_SKIPPED`) rather than install.sh's per-call verbose block — this hook runs unattended on every SessionStart, where the verbose form would be spam on a permanently-symlinked machine and a silent form would mean nobody learns.
- 2026-07-29: `adapters/claude-code/hooks/session-start-auto-install.sh` self-test — 4 new scenarios (19-22): the GOLDEN scenario (symlinked hooks/, newer repo content survives), the settings-merge guard (found mid-build that a symlinked LEAF does not reproduce the hazard — `mv` onto a symlink-to-a-file replaces the symlink rather than writing through it; the real hazard needs a symlinked PARENT dir, confirmed by direct experiment), the prune-path guard, and a "guard is silent in copy mode" check. 22/22 on bash 3.2.57 and 5.3.15. Mutation-tested: removing the three guard call sites turns exactly scenarios 19-21 RED (19 passed, 3 failed), everything else stays green. Also fixed a PRE-EXISTING self-test trap while here: `_run_main` and 4 other call sites re-exec'd via a bare `bash`, which resolves via PATH (Homebrew 5.3.15 on this machine) regardless of which interpreter `--self-test` itself was invoked under — so a prior "tested on bash 3.2.57" claim for scenarios 1-18 was never actually true for the re-exec'd main() logic. Fixed by re-exec'ing via `"$BASH"` (the running interpreter's own absolute path); PROVEN via `/bin/bash -c 'echo $BASH; echo $(bash -c "echo \$BASH")'` printing `/bin/bash` then `/opt/homebrew/bin/bash`. Windows/copy-mode unaffected: scenarios 1-18 never call `ln`; ran byte-identical (diff-confirmed PASS/FAIL text AND installed file trees) before/after this change, both under a shadowed `ln` (stub that exits 1, simulating Windows Git-Bash) and normally.
- 2026-07-29: `adapters/claude-code/hooks/session-start-auto-install.sh` — machine-local kill-switch (mid-build addition, second incident: this hook overwrote committed branch work again, 39 files, while the guard above was being built). `$LIVE_DIR/local/no-auto-install` marker, checked as `main()`'s first action, before any checkout discovery/fetch/sync. Marker file (not env var) per docs/decisions/065's addendum: an env var doesn't survive into this hook's own separately-invoked process, and the fix must not require touching machine-local settings.json. Self-test scenarios 23-24 (24/24 total now), asserted on the filesystem (zero dirs/files created when the marker is present), not just the log line. Declined a broader "refuse to overwrite locally-newer content in general" ask — reasoning (contradicts this file's own documented master-wins design, would break already-tested Scenario 4, no reliable newer/older signal exists outside the self-sync case) written into docs/decisions/065-self-sync-guard-signal-level.md.
