# gh-merge canonical write-discipline — full

This is the detail companion to `gh-merge-canonical.md` (the compact). Everything
here was trimmed from the compact to hit its 2800-byte budget under
`evals/golden/rules-index-coverage.sh`; nothing here is new — it is the same rule
set at full elaboration.

## The 2026-07-15 divergence incident (referenced from "The rule")

The concrete event motivating decision 064: on 2026-07-15 the neural-lace repo's two
hosted masters (personal `origin`, work-org `pt`) diverged by a 14/10 commit split —
a PR had been merged server-side directly on `pt`, which no local hook observes
after the fact (server-side merges are invisible to any client-side mechanism once
they've happened). Two independently-mergeable masters is, structurally, a
divergence generator: any merge that lands on one side and not the other silently
forks history. The gate exists to block the merge ATTEMPT itself, pre-emptively, on
the one surface a PreToolUse hook can actually inspect — the `gh` CLI invocation
before it runs.

## PRIMARY vs DEFENSE-IN-DEPTH — the review's one finding (A1/A2)

The client-side gate alone does NOT make divergence structurally impossible — it
only covers a harnessed machine performing the merge via `gh`. The PRIMARY
mechanism is GitHub branch protection / restricted-push on `pt/master`
(server-side, and therefore covers web-UI merges, the CLI, CI, and all
collaborators uniformly, not just this one machine's hooked `gh` calls). Enabling
branch protection is an access-control change on the `pt` repo — therefore
OPERATOR-ONLY, never agent-executed, regardless of how routine it might otherwise
seem. Until the operator enables it, this gate plus the FF-only
`master-drift-autocorrect.sh` plus the manual reconcile runbook are the safety
net — explicitly described as a safety net, not a guarantee, because none of the
three closes the gaps listed below under "Not covered."

## Target resolution (A4), fully offline — edge cases

The full 5-step algorithm (steps 1-5 are in the compact) with the edge cases that
don't fit there:

1. Explicit repo in the command wins — `gh api repos/OWNER/REPO/pulls/N/merge`
   (**unless** OWNER/REPO is a literal `{owner}`/`{repo}` gh-api template
   placeholder, which gh fills from the CURRENT repo context rather than from this
   literal string — that case falls through to step 3/4, not step 1), or
   `--repo`/`-R` on `gh pr merge`.
2. Else a positional target on `gh pr merge` that itself encodes a repo — a pasted
   PR URL (`https://HOST/OWNER/REPO/pull/N`) or the `OWNER/REPO#N` shorthand —
   which gh honors over the default repo. A bare PR number/branch positional
   encodes no repo and falls through, unchanged.
3. Else the checkout's `gh repo set-default` state (`remote.<name>.gh-resolved
   base`).
4. Else a remote heuristic: the sole github.com-hosted remote. An SSH host-ALIAS
   remote, e.g. `pt` via `github-pt`, is NOT github.com-shaped and is not a
   candidate — this matches gh's own resolution behavior; verified empirically:
   `gh repo view` in this repo resolves to the personal repo despite `pt`
   existing, precisely because `pt`'s host token isn't literal `github.com`.
5. Zero or >1 candidates -> AMBIGUOUS -> fail loud and block, never guess. Never
   silently allow (could hide a real pt-merge) and never silently reinterpret
   ambiguity as pt (could block a legitimate personal merge) — the block message
   teaches `--repo` or `gh repo set-default` as the fix.

## Parser residual (named, harness-review 2026-07-16 fixup)

The command shape read is also fallback-checked at `.command` (flat tool-call
payloads, not only nested `.tool_input.command`), the merge-command match
tolerates irregular whitespace, and positional PR-URL/`OWNER/REPO#N` targets are
parsed. Still uncovered, in full:

- A runtime-interpolated value (`gh pr merge $N --repo "$REPO_VAR"`) — the
  variable's actual value is invisible to a static-string check, so this falls
  through to default-repo resolution rather than being read correctly.
- A bundled short flag with no space (`-Rowner/repo`) is not matched by the `-R`
  extractor and also falls through to default-repo resolution.
- A `gh pr merge` invoked via a shell alias/function whose name doesn't literally
  contain adjacent `gh`/`pr`/`merge` tokens is not recognized as a merge command at
  all.

None of these three silently misclassify a resolved target — they fall through to
the next resolution step (or all the way to the loud ambiguous-block) rather than
being read as a false ALLOW or false BLOCK. This is the load-bearing safety
property of the residual: worst case is "gate didn't fire" or "gate blocked
loudly," never "gate silently approved a pt-merge."

## §10 evidence bar (A3)

PR #100's actual merge PATH (web-UI vs `gh` CLI) is UNKNOWN — server-side merges
are indistinguishable from each other in the API record, so there is no way to
retroactively determine which surface performed a given historical merge. This
means the 2026-07-15 divergence golden scenario validates BRANCH PROTECTION as the
mechanism, not this gate (the gate could not have been proven to have caught or
missed that specific incident). Going forward, `fp_expectation` is defined against
the RESOLVED target (never the raw command string): zero legitimate `pt`-repo
`gh pr merge` calls are expected post-cutover, on this posture; any such call
appearing is itself the defect to investigate, not an accepted false positive.

## Posture reversal (A5), in full

This REVERSES the 2026-05-29 "PT is canonical" posture recorded in `sync.sh` and
the now-retired `sync-pt-to-personal.sh` (attic'd — see
`docs/decisions/064-never-diverge-single-canonical-master.md` element 4/A6). Under
the old posture, the standing habit was to merge work-side PRs on `pt` (not only
in-flight PRs at the time of the switch — the standing habit itself). That habit
now migrates to the personal side. `docs/RESUME-HERE.md` had already routed
cross-machine work through `origin/master` before this reversal, so in practice
only the observed merge BEHAVIOR changes with decision 064 — the documented
cross-machine flow itself does not need to change, since it was already pointing
at personal `origin`.

## Residual writers this gate does NOT cover (A1), in full

- GitHub web-UI merge (no PreToolUse hook observes browser actions).
- A machine that hasn't yet synced this hook — the deploy-lag window, since
  `session-start-auto-install.sh` only syncs at a NEW session start, not mid-session.
- Un-harnessed or external machines (no Claude Code harness installed at all).
- CI / GitHub Actions (runs server-side, no local hook surface).
- Scheduled / cloud agents (Decision 011 — these run without PreToolUse hooks by
  design).
- Direct `git push pt master` (a push, not a `gh` merge call — outside this gate's
  command-match surface entirely).

Only branch protection on `pt/master` closes all of these uniformly, which is why
it is designated PRIMARY and this gate DEFENSE-IN-DEPTH.
