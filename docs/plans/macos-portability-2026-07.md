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
