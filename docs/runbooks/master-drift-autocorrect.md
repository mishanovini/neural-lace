# Runbook: master-drift auto-correction

Mechanism: `adapters/claude-code/scripts/master-drift-autocorrect.sh`, dispatched
backgrounded by `adapters/claude-code/hooks/session-start-git-freshness.sh` at
session start (plan: `docs/plans/master-drift-autocorrection-2026-07.md`; manifest
entry: `master-drift-autocorrect`). The repo has two masters — `origin/master`
(personal remote) and the mirror remote's master (work-org remote; locally often
named `pt`). Local pushes dual-push both, but GitHub server-side PR merges land on
exactly one, so the masters drift until corrected.

Status file: `~/.claude/state/master-drift/<repo-basename>.status` (one line).
Phase log: `~/.claude/logs/master-drift-autocorrect.log`.
On-demand run: `bash adapters/claude-code/scripts/master-drift-autocorrect.sh`
from anywhere inside the repo (no arguments; exit 0 in every path).

## What auto-corrects — and what never will

| Shape | What happens |
|---|---|
| Masters EQUAL | `CONVERGED <sha7>` status; zero digest lines. |
| One master STRICTLY BEHIND the other (`git merge-base --is-ancestor` proves it) | Plain (never forced) push fast-forwards the behind master inside the dedicated sync clone (`~/.claude/sync-clone/<repo>` — never a live checkout). Status `CORRECTED <remote> <sha7>`; one digest line next session, retired once a re-evaluation writes CONVERGED. |
| TRUE DIVERGENCE (neither SHA an ancestor of the other) | **Never auto-merged. Nothing is pushed.** Status `DIVERGED <sha7-origin> <sha7-mirror>`; one `[master-drift] DIVERGED …` digest line per session until a human runs the reviewed-merge procedure below. |
| Push rejected (race, auth, hook decline) | No retry loop. Status `PUSH-REJECTED <remote> <reason>`; next session start re-evaluates from scratch (a lost race usually resolves to CONVERGED on its own). |

Also never: tokens/PATs (the corrector uses the machine's ambient git
credentials and never prompts — `GIT_TERMINAL_PROMPT=0`), force pushes (no force
flag exists in the script; self-test T5 greps for it), non-`master` refs,
mutations of any live checkout (all git mutation happens in the dedicated clone),
and any GitHub Action mirror (deliberately reverted 2026-05-28, commit `5bf55c7`).

## DIVERGED: the reviewed-merge procedure

Verbatim the 2026-07-11 reconciliation procedure
(`docs/handoffs/masters-reconciled-remaining-2026-07-11.md`). Never force-push.
`<mirror>` below is the work-org remote name in your checkout (commonly `pt`).

```bash
# 1. Re-verify the divergence from fresh refs
git fetch origin && git fetch <mirror>
git rev-parse origin/master <mirror>/master        # unequal, neither an ancestor

# 2. Merge in a TEMP WORKTREE off origin/master — never the shared main checkout
git worktree add ../nl-reconcile origin/master
cd ../nl-reconcile
git merge --no-ff <mirror>/master

# 3. Resolve conflicts. docs/DECISIONS.md rule: UNION of ADR rows (keep both
#    sides' rows — the 99841c0 precedent: each side had ADR rows the other lacked).

# 4. Dual push (plain; PT master protection admits an admin merge commit via
#    enforce_admins:false — that is how 99841c0 landed, no force)
git push origin HEAD:master
git push <mirror> HEAD:master

# 5. Re-verify EQUAL, then clean up
git fetch origin && git fetch <mirror>
git rev-parse origin/master <mirror>/master        # must be EQUAL
cd - && git worktree remove ../nl-reconcile
```

The next session start (or an on-demand corrector run) observes convergence and
writes `CONVERGED`, retiring the digest line.

## Kill switch

`MASTER_DRIFT_AUTOCORRECT=0` in the environment:

- The git-freshness hook **skips the corrector dispatch entirely** (the
  detection line still renders, so drift stays visible).
- The corrector itself also honors it (defense in depth): it exits 0 before any
  mutation, logging `kill-switch`.

Set it machine-wide (e.g. in the shell profile) while investigating suspected
misbehavior, and file the defect: `nl-issue.sh "master-drift: <what happened>"`.
Unset to re-arm. The switch is a present-moment env check, not a deferred audit
entry (loud-is-not-rare lesson).

## PUSH-REJECTED triage

Read the reason word in the status line / the `phase=push` log line:

- **`auth`** (403 / authentication / permission): almost always WRONG ACCOUNT —
  the credential in use cannot push the target remote. Fix:
  `gh auth switch -u <owner-of-target-remote>`, then rerun the corrector by
  hand and switch back. No token is ever created for this — the corrector uses
  whatever the credential store already holds.
- **`non-ff`**: a concurrent push advanced the target between the ancestor
  check and the push (the designed race backstop). No action needed — the next
  session start re-evaluates; it is usually CONVERGED by then.
- **`timeout`**: network. No action; next session retries.
- **`rejected`** (anything else, e.g. a server-side hook declined): inspect the
  `phase=push` log line for the server's message; if branch protection changed,
  reconcile by hand per the DIVERGED procedure's push step.
- **`verify-mismatch`**: the push succeeded but the post-push re-fetch did not
  observe the expected SHA (another race). Re-run by hand; escalate only if it
  repeats.

## Other operational notes

- **Lock**: single-instance `mkdir` lock at
  `~/.claude/sync-clone/<repo>/.master-drift-lock`; a crashed run's stale lock
  is broken automatically after 30 min. `phase=lock` log lines show holds/breaks.
- **Clone corruption**: the dedicated clone is disposable — delete
  `~/.claude/sync-clone/<repo>` and the next run re-bootstraps it from the
  caller's remote URLs.
- **ISL refusals**: the corrector sources
  `hooks/lib/interactive-session-lock.sh`; a live session on a normal checkout
  is LOG-AND-PROCEED (the corrector never touches that tree). It REFUSES only
  when invoked from inside the dedicated clone itself
  (`~/.claude/logs/interactive-session-lock.log` records verdicts).
- **Doctor**: `harness-doctor.sh --quick` checks the mechanism structurally
  (script + `--self-test` entrypoint + hook wiring); `--full` also runs the
  corrector's self-test.
