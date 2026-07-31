# 066 — macOS coord-sync scheduled runner: StartInterval LaunchAgent + a URL-scoped git credential fix for same-person/different-GitHub-account machines

**Date:** 2026-07-29
**Status:** DECIDED and DEPLOYED (LaunchAgent installed + verified live on the operator's
machine this session — see Evidence below). The credential fix is BUILT + self-tested but
NOT yet applied for real on this machine — see Blockers.
**Tier:** 1 (reversible — `launchctl bootout gui/$UID/local.neurallace.coord-sync` +
`rm ~/Library/LaunchAgents/local.neurallace.coord-sync.plist` for the scheduler;
`git config --global --unset-all credential."<url>".helper` for the credential fix;
no data surgery, no third parties beyond already-authorized `gh` tokens, no unrecoverable
spend, no public exposure).

## Problem (cold-read context)

Operator, 2026-07-29: "The cockpit is also supposed to show work across multiple machines.
When is that actually going to be a reality?" Measured: `coord-sync.sh` (the exporter+push+
pull cadence that feeds the cockpit's Peers pane, `docs/runbooks/coord-sync.md`) had NO
scheduled runner on macOS at all — `~/.claude/state/coord-sync/cycles.log` was absent,
meaning the script had never run on this machine. Windows drives it via the `NL-CoordSync`
scheduled task (`install-coord-sync-task.ps1`); macOS had nothing analogous.

A second, independent gap surfaced while wiring the first: this machine's only SSH key
authenticates to GitHub as a DIFFERENT account than the one that privately owns the
`workstreams-coordination` coordination repo. Neither plain SSH nor `gh auth setup-git`'s
own HTTPS credential helper (which resolves to whichever `gh` account is *currently active*,
not to whichever account actually has access) can reach the repo without either switching
the machine's active `gh` account (a global, cross-cutting side effect touching every other
repo's `gh`-CLI usage on this machine) or fixing this per-repository.

## Decision 1 — StartInterval LaunchAgent, not RunAtLoad+KeepAlive

Same platform primitive as decision 065 (`065-macos-cockpit-launchagent.md`), different
shape: `ensure-coord-sync.sh` installs `local.neurallace.coord-sync` with `StartInterval=60`
(matches the Windows task's default `-IntervalSeconds`) + `RunAtLoad=true`, and deliberately
**no `KeepAlive` key at all**. `coord-sync.sh` is a short-lived cadence script that is
SUPPOSED to exit after each debounced fire (Task 7's marker-check/event/floor logic) — the
opposite shape from the cockpit's persistent node server. `KeepAlive` expects a long-running
daemon and fights `StartInterval`'s "run briefly, then wait" contract; overlap is instead
prevented by `coord-sync.sh`'s own mkdir lock (`STATE_DIR/coord-sync.lock`, 900s stale
reclaim), exactly mirroring the Windows task's own `-MultipleInstances IgnoreNew`.

No liveness probe (contrast with ensure-cockpit.sh's port poll): a periodic cadence script
has no listening socket. "Did it actually run" is answered by `cycles.log`'s own freshness,
checked by hand (or by the source plan's own staleness contract), not by an active probe in
the ensure script.

## Decision 2 — fix the credential class with a URL-scoped git credential helper, not an SSH key swap or a `gh auth switch`

| Option | What happens | Cost / risk |
|---|---|---|
| A. Generate a second SSH key for the coord-repo-owning account + a `~/.ssh/config` `Host` alias | Matches the runbook's existing "Second-account access" doc (written for a genuinely different *person*'s machine) | New key material to manage; the runbook's own doc frames this as the two-different-PEOPLE case, not the one-person-two-accounts-per-machine case this actually is |
| B. `gh auth switch -u <owner>` and leave it switched | Makes plain `git@github.com` SSH... no — protocol is still SSH-locked to the one key; switching `gh`'s active account does not change which SSH key authenticates at all. For an HTTPS remote it WOULD work, but persistently — every other `gh` CLI command on this machine (e.g. this repo's own `gh pr`/`gh issue` usage, which uses a DIFFERENT account) silently starts using the wrong account until switched back | Global, persistent, cross-cutting; conflicts with the per-directory gh-account auto-switch this machine already relies on |
| **C. A `credential.<exact-url>.helper` override in the GLOBAL gitconfig, fetching the token fresh via `gh auth token -u <owner>` on every git operation** | Coexists with `gh auth setup-git`'s own host-level helper (git tries configured helpers in order; the reset-then-set trick — an empty `credential.<url>.helper` entry followed by the real one — is the SAME idempotent-reset pattern `gh auth setup-git` itself uses, just scoped to one URL); resolves the CORRECT account deterministically regardless of which account is "active"; never persists the token to disk (fetched fresh each time from `gh`'s own keyring-backed store); reversible with one `git config --global --unset-all` | Modifies the global `~/.gitconfig` (not per-repo) — but the entry is scoped to the EXACT repo URL, so it provably cannot affect any other clone/push/fetch on this machine |

**Pick: C.** It is HTTPS+`git`-native (not the `gh` Contents API — preserves the original
design's "avoid gh-account-blindness" intent, coord-push.sh's own header rationale, just via
a different transport than SSH), it is provably scoped to one URL, it needs no new key
material, and it never touches `gh auth switch`'s global, persistent state. Built as
`_ecs_ensure_repo_credential()` inside `ensure-coord-sync.sh` (idempotent; runs on every
ensure) rather than a one-off manual `git config` command, so it self-heals and is
documented in code, not just in this file.

**Hygiene preserved:** the committed script never hardcodes the coord repo's owner/URL —
it resolves `COORD_REPO_URL` the identical 3-tier way `coord-push.sh` already does (env >
`~/.claude/local/coord-repo-url.txt` > existing clone's origin), parses `<owner>/<repo>`
generically from whatever URL that resolves to, and only proceeds if `gh auth token -u
<owner>` actually returns a token on this machine (tolerate-absent otherwise, with a log
line naming exactly what the operator must provision).

## Why this is mine to decide

Reversible in one command per mechanism (see Tier above); no third party is granted
anything new (the fix only uses tokens the operator already authorized via their own prior
`gh auth login`); no data surgery; no public exposure. This is a "can I defend one answer
from principles + evidence" call (constitution §3), not a business-intent/taste call.

## Blockers hit this session (see build session's own report for the exact commands)

- `~/.claude/local/coord-repo-url.txt` is gated by `local-edit-authorization.md`
  (`/grant-local-edit` — a mechanical, per-file authorization the operator must invoke
  themselves; an agent session's own dispatch instructions do not count as that
  authorization). The LaunchAgent scheduler (Decision 1) is installed and PROVEN firing
  for real on its own (see Evidence); the credential fix (Decision 2) is built + unit-
  self-tested but has not yet been exercised against the real `~/.gitconfig` on this
  machine, because doing so requires the coord-repo-url file to exist first.

## Evidence (this session, this machine)

- Self-test: `bash adapters/claude-code/scripts/ensure-coord-sync.sh --self-test` — 34/34
  on BOTH `/bin/bash` (3.2.57) and `/opt/homebrew/bin/bash` (5.3.15).
- Mutation transcript: neutering the `launchctl print` idempotency check in
  `_ecs_darwin_ensure` (forcing `was_loaded=1` unconditionally) turned D2 (idempotent
  second run) and D3 (content-change bootout+rebootstrap) RED — 30/34, 4 failed — proving
  the suite has real discriminating power over that control. Reverted; file is unchanged
  from its committed state.
- Real (non-self-test) install on this machine: `ensure-coord-sync.sh` invoked directly
  wrote `~/Library/LaunchAgents/local.neurallace.coord-sync.plist`, ran `launchctl
  bootstrap` successfully, and `launchctl print gui/501/local.neurallace.coord-sync` shows
  it genuinely loaded (`type = LaunchAgent`, correct program/arguments/working directory).
  `~/.claude/state/coord-sync/cycles.log` — ABSENT before this session — now has two real
  entries 60s apart (`trigger=event+floor` at RunAtLoad, `trigger=event` at the first
  StartInterval fire), both `outcome=skipped-no-coord-repo` (the honest degradation path,
  since the URL is not yet configured) — this is the scheduling mechanism proven live, not
  self-tested.
- Credential mechanism (`_ecs_ensure_repo_credential` design) proven correct in a sandbox:
  a scratch clone with a URL-scoped `credential."https://github.com/mishanovini/
  workstreams-coordination.git".helper` (reset-then-set, `gh auth token -u mishanovini`)
  reached the real private coord repo (`git fetch origin main` succeeded, real refs
  returned) from a machine whose default SSH identity and `gh`-active account are a
  DIFFERENT GitHub account with no access to that repo — reproducing exactly the
  production fix, just not yet wired into the real `~/.gitconfig` (see Blockers).
