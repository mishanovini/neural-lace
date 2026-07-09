# GH-AUTH-AUTOSWITCH-WORKORG-01 — crash-recovery continuation evidence

The prior in-process builder died mid-build; its salvaged partial work landed
in commit `0b8a09ab52ffe45e7be2802ef9c52c653ac66855` (branch
`origin/gh-account-autoswitch`, no `build/` prefix — the dispatch note's
`origin/build/gh-account-autoswitch` name did not exist; this is the actual
ref that carries the same SHA). This continuation session
(`build/gh-account-autoswitch-v2`, branched from that SHA) reviewed the
salvage in full and found it CODE-COMPLETE: `gh-account-autoswitch.sh`,
`hooks/lib/gh-account-lib.sh`, the `gh-account-blindness-hint.sh` refactor,
`doctrine/git.md`'s note, and both orchestrator fragments were all already
written and internally consistent. No production code needed changes. What
this session ADDED is the verification the salvage commit had not yet
recorded: self-tests actually executed, syntax-checked, CRLF-checked, and a
real (non-stubbed) `gh` livesmoke run.

## Self-test results (re-executed this session, not carried over from claims)

```
$ bash adapters/claude-code/hooks/gh-account-autoswitch.sh --self-test
  S1 personal-repo merge from work-active -> switches: PASS
  S2 work-repo push from personal-active -> switches: PASS
  S3 already-correct account -> no-op: PASS (no switch, as expected)
  S4 unresolvable owner -> no-op: PASS (no switch, as expected)
  S5 read-only op -> no switch: PASS (no switch, as expected)
  S6 gh pr view wrong-account -> switches: PASS
  S7 flagless PreToolUse stdin JSON shape -> switches: PASS
  S8 non-gh command -> no-op: PASS (no switch, as expected)
  S9 signal-ledger warn emitted on switch: PASS
  S10 idempotent — second (already-correct) call performs no extra switch: PASS

[self-test] 10 passed, 0 failed
```

```
$ bash adapters/claude-code/hooks/lib/gh-account-lib.sh --self-test
  L1 direct owner match: PASS
  L2 owners[] match: PASS
  L3 unknown owner -> empty: PASS
  L4 gh_ci_eq case-insensitive: PASS

[gh-account-lib self-test] 4 passed, 0 failed
```

```
$ bash adapters/claude-code/hooks/gh-account-blindness-hint.sh --self-test
  C1..C9: all PASS (9/9) — confirms the lib-delegation refactor did not
  regress the pre-existing REACTIVE hook's own suite.
```

`bash -n` syntax check: clean on all three shell files. No `shellcheck`
binary available in this environment to run further static analysis.

## CRLF check (per this machine's LF-pinning convention, NL-FINDING-038)

Raw CR (0x0D) byte count via `od -An -tx1 -v <file> | tr -s ' ' '\n' | grep
-c '^0d$'` (byte-exact; MSYS text tools silently strip `\r` so a naive
`grep -c $'\r'` is unreliable — see project memory
`project_msys_tools_mask_crlf_use_od`):

| file | raw CR bytes |
|---|---|
| `hooks/gh-account-autoswitch.sh` | 0 |
| `hooks/lib/gh-account-lib.sh` | 0 |
| `hooks/gh-account-blindness-hint.sh` | 0 |

`git check-attr eol` reports `lf` for both new files. `file(1)` reports no
CRLF line terminators on any of the three.

## Livesmoke — real `gh`, no stub (operator-authorized: both accounts are
## the operator's own)

Before: active account was `MishaPT` (this session's default, per
`~/.claude/local/accounts.config.json` dir-trigger for
`~/dev/Pocket Technician`).

```
$ payload='{"tool_name":"Bash","tool_input":{"command":"gh pr view 63 --repo mishanovini/neural-lace"},"cwd":"<this-worktree>"}'
$ echo "$payload" | bash adapters/claude-code/hooks/gh-account-autoswitch.sh
(exit 0, no stdout — hook only side-effects)

$ gh auth status   # re-checked immediately after
  ✓ Logged in to github.com account mishanovini (keyring)
  - Active account: true
```

The hook pre-emptively switched the REAL `gh` CLI's active account from
`MishaPT` to `mishanovini` before the tool call ran, using the exact
flagless PreToolUse stdin-JSON shape Claude Code sends. Then the actual
command was run for real and succeeded (it would have 403'd
"Repository not found" pre-switch, since PR #63 lives on the
`mishanovini`-owned mirror and the active account was `MishaPT`):

```
$ gh pr view 63 --repo mishanovini/neural-lace
title:  doctrine(frontend-conventions): prerequisite unblocking — never a dead end
state:  OPEN
author: mishanovini (Misha)
number: 63
url:    https://github.com/mishanovini/neural-lace/pull/63
...
```

After the livesmoke, this session explicitly switched the real `gh` CLI
back to `MishaPT` (`gh auth switch -u MishaPT`) before doing any further
`origin`-repo (Pocket-Technician-owned) git/gh work in this same session —
NOT a change to the hook's own documented "leave-on-target, do not
switch back" design (that design governs what the HOOK itself does
post-switch for FUTURE tool calls; it does not obligate this human/session
narrative to leave real system auth state pointed at the wrong account for
the remainder of an unrelated continuation session where the hook itself
is not yet wired into this live session's own PreToolUse chain — this
fragment hasn't been merged into the live `settings.json` yet, only into
the orchestrator-fragment files below).

## Fragments (already present in the salvage; unchanged by this session)

- `adapters/claude-code/tests/fixtures/gh-autoswitch/template-wiring.md` —
  the exact `settings.json.template` PreToolUse "Bash" matcher block to add
  (new entry, positioned immediately before the existing
  `gh-account-blindness-hint.sh` PostToolUse "Bash" block).
- `adapters/claude-code/tests/fixtures/gh-autoswitch/manifest-amendments.md`
  — the exact `manifest.json` entry to add (`id: gh-account-autoswitch`,
  sorts between `gen-architecture-doc` and `gh-account-hint`, verified
  against this worktree's live manifest.json this session: confirmed those
  two are in fact adjacent neighbors and `gh-account-hint`'s existing entry
  is unchanged). No `observability-consumer-map.json` edit needed — the
  `warn` event type's consumers (`digest:feed_ledger_summary`,
  `kpi:harness-kpis.sh`) already exist; re-verified live this session via
  `jq '.event_types.warn.consumers' observability-consumer-map.json`.

Neither `settings.json.template` nor `manifest.json` was hand-edited by
either builder — both remain orchestrator-only, per the dispatch note.

## Design choice: leave-on-target, do not switch back

Documented in `gh-account-autoswitch.sh`'s own header (lines ~32-52):
after a pre-emptive switch, the hook does NOT add a PostToolUse
switch-back. Rationale (unchanged from the salvage, re-affirmed this
session as correct): (1) consecutive commands in a session commonly target
the SAME just-switched-to owner, so switching back after each one would
cause MORE total switches, not fewer; (2) the pre-existing SessionStart
directory-based switcher already re-asserts the cwd's correct default
account at the start of every NEW session, self-correcting any leftover
wrong-for-this-dir active account. Accepted residual risk: mid-session, a
subsequent gh command with NO resolvable target owner could run against
whichever account was last left active rather than the cwd's "true"
default — mitigated by re-deriving the cwd-default as a fallback in
`_ghas_resolve_target_owner`.
