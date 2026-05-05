# Decision 021 — DRIFT-02 resolution: SessionStart account-switching hook is config-driven

**Date:** 2026-05-04
**Status:** Active
**Stakeholders:** Maintainer (sole)
**Related plan:** `docs/plans/phase-1d-e-1-p1-drift-fixes.md` (Status: ACTIVE → COMPLETED)
**Related backlog item:** HARNESS-DRIFT-02 (closed by this plan)

## Context

HARNESS-DRIFT-02 was surfaced in the 2026-04-27 harness audit. The
SessionStart account-switching hook (`settings.json:273-279` and the
push-time variant at line 178) was implemented as a hardcoded
inline shell snippet that tested whether `$PWD` contained a literal
substring naming a specific business codename. If the substring matched,
the hook ran `gh auth switch --user <work-account-name>`; otherwise it
fell through to `gh auth switch --user <personal-account-name>`. The
substring, the work account name, and the personal account name were
all baked into the hook body verbatim.

The brittleness this caused:

1. **Identity leakage.** Real codenames + real GitHub usernames lived
   inside `settings.json.template` (the committed file shipped with
   `install.sh`). This violated `~/.claude/rules/harness-hygiene.md`'s
   "no real account names in committed harness code" rule. Every fresh
   install propagated the maintainer's personal identifiers to whoever
   ran `install.sh`.
2. **Single-organization assumption.** The hook had two branches: the
   one substring matched (work) and everything else (personal). A user
   working across more than two accounts had no path other than editing
   the hook body and adding more `if` branches.
3. **New-account-requires-code-edit failure mode.** Adding a new account
   meant a `git commit` to the harness repo. There was no per-machine
   override path. A user could not say "on this machine, also map
   directory pattern X to account Y" without rewriting the hook.
4. **Working-directories-not-matching-the-substring fall through.** Any
   working directory not containing the literal codename (a common case:
   working on a personal repo whose name didn't include the codename)
   silently fell into the personal branch — even when the user was
   currently inside a different account's repo. The result was the hook
   "switching" the user to the wrong account at session start.

The infrastructure to do better already existed:
`adapters/claude-code/scripts/read-local-config.sh` ships a `match-dir`
mode that reads `~/.claude/local/accounts.config.json`
(gitignored, per-machine), iterates the account entries, and for each
account scans the `dir_triggers` array for substring matches against
`$PWD`. On match, it prints `<account-tag> <username>` to stdout. On no
match, it prints nothing and exits 0. The script's `--self-test` mode
exercises work-org-match, personal-match, and no-match scenarios.

The fix was to replace the hardcoded inline body with a call to the
existing script.

## Decision

Both hook locations (SessionStart line 273 and push-time line 178 in
`settings.json.template`, and the live mirror at `~/.claude/settings.json`)
read account state via:

```sh
match=$(bash ~/.claude/scripts/read-local-config.sh match-dir "$PWD" 2>/dev/null)
if [ -n "$match" ]; then
  account_tag=$(echo "$match" | awk '{print $1}')
  username=$(echo "$match" | awk '{print $2}')
  gh auth switch --user "$username" 2>/dev/null
fi
```

When `~/.claude/local/accounts.config.json` is absent, the script exits
0 with empty stdout and the hook is a no-op. When the config exists but
the working directory matches no `dir_triggers` entry, same: no-op. When
`gh auth switch` itself fails (account not yet logged in via
`gh auth login`), stderr is suppressed and the hook degrades gracefully
without aborting the session start.

The schema for `accounts.config.json` is documented at
`adapters/claude-code/examples/accounts.config.example.json`. Adding a
new account is a per-machine config edit; no harness commit is required.

## Alternatives considered

- **Alt 1 — Keep the hardcoded approach but add tiebreaker logic for
  dual-hosted repos.** Rejected. Doesn't solve the
  new-account-requires-code-edit problem, doesn't solve the identity
  leakage in `settings.json.template`, and inflates the hook body with
  per-user logic that doesn't generalize. The brittleness is structural,
  not a missing edge case.
- **Alt 2 — Read account directly from a `.gh-account` file in each
  project.** Rejected. Per-repo file management doesn't scale across
  many projects (one file per repo, plus a convention for what goes in
  it, plus a discovery rule for sub-directory cases). Pushes the
  configuration burden onto every project rather than centralizing it
  per-machine.
- **Alt 3 — Derive account from `gh auth status` and never switch (let
  the user manage).** Rejected. Doesn't help when the user is logged
  into the wrong account when starting a session in a directory where
  the right account is unambiguous. The whole point of the hook is to
  fix that case automatically.
- **Alt 4 — Keep the hardcoded literal-substring approach.** Rejected
  per its brittleness (identity leakage, single-org assumption,
  code-edit-to-add-account, false-positive fall-through to personal).

## Consequences

**Enables:**
- Adding a new account is a per-machine config edit. No harness commit
  is required.
- The committed harness code carries no real usernames or codenames.
  `harness-hygiene-scan.sh` is satisfied.
- Sessions in directories not matching any pattern degrade gracefully
  to no-op (rather than the previous false-positive switch to personal).
- The script's `--self-test` mode is the regression check; passing it
  confirms behavior across the work-org / personal / no-match cases
  without depending on the user's actual `~/.claude/local/`.

**Costs:**
- One extra subprocess invocation per session start (`bash` running the
  script). Latency is sub-100ms in practice; not user-visible.
- Users who haven't created `~/.claude/local/accounts.config.json` get
  no auto-switch. They keep whichever account `gh` is currently logged
  into; if that's the wrong account, they `gh auth switch` manually. The
  example file at
  `adapters/claude-code/examples/accounts.config.example.json` is the
  starting point; users copy it to `~/.claude/local/` and edit.
- Schema mismatches surface as no-op (not as errors). If a user's
  existing config uses old field names, the hook silently no-ops until
  the user updates the schema. This is an acceptable trade-off vs. the
  alternative of erroring at session start.

**Depends on:**
- `adapters/claude-code/scripts/read-local-config.sh` and its `match-dir`
  mode are stable. The script has `--self-test` coverage and shipped
  before this decision; the dependency is verified.
- `gh` CLI is installed. If `gh` is not present, the call to `gh auth
  switch` fails silently and the hook degrades. The fallback is the same
  as before this decision.

**Propagates downstream:**
- `docs/harness-architecture.md` SessionStart inventory (line 84) was
  already generic ("detects the current directory against configured
  account `dir_triggers` in `~/.claude/local/accounts.config.json`"); no
  inventory edit needed in this commit.

**Blocks:** nothing. The change is backward-compatible; users who had
the hardcoded behavior working get the no-op on first install (until
they add an `accounts.config.json`), then opt in by editing the per-machine
config.

## Cross-references

- `docs/plans/phase-1d-e-1-p1-drift-fixes.md` — the implementing plan
- `adapters/claude-code/scripts/read-local-config.sh` — the existing
  script with `match-dir` mode
- `adapters/claude-code/examples/accounts.config.example.json` — schema
  example users copy to `~/.claude/local/accounts.config.json`
- `adapters/claude-code/settings.json.template` — committed
  source-of-truth where the SessionStart and push-time hook bodies were
  replaced (commits f2d812a + 430365c)
- `~/.claude/rules/harness-hygiene.md` — the hygiene rule the previous
  hardcoded approach violated
- `docs/harness-architecture.md` — SessionStart inventory entry already
  generic; no update needed
- HARNESS-DRIFT-02 — the backlog item closed by this decision
