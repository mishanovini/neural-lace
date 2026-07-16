# gh-merge canonical write-discipline — compact
> Enforcement: gh-merge-canonical-gate.sh (PreToolUse Bash — blocks `gh pr merge` /
> `gh api .../pulls/N/merge` whose RESOLVED target is the `pt` repo). DEFENSE-IN-DEPTH
> only — see below. Source of truth: `docs/decisions/064-never-diverge-single-canonical-master.md`.
> Applies: every `gh pr merge` / merge-shaped `gh api` call on a harnessed machine.

**The rule (decision 064, amended 2026-07-16, SOUND-WITH-AMENDMENTS):** the neural-lace
repo is dual-hosted — personal `origin` (canonical) and work-org `pt` (mirror). A PR
merged server-side on `pt` lands on `pt`'s master only; no local hook observes it after
the fact, and two independently-mergeable masters is a structural divergence generator
(2026-07-15: 14/10 split). The gate blocks the merge attempt itself, pre-emptively, on
the one surface a PreToolUse hook can inspect — the `gh` CLI.

**PRIMARY vs DEFENSE-IN-DEPTH (the review's ONE finding, A1/A2).** The client-side gate
alone does NOT make divergence structurally impossible — it only covers a harnessed
machine performing the merge via `gh`. **PRIMARY mechanism:** GitHub branch protection /
restricted-push on `pt/master` (server-side, covers web-UI, CLI, CI, collaborators
uniformly) — an access-control change, therefore OPERATOR-ONLY, never agent-executed.
Until enabled, this gate + the FF-only `master-drift-autocorrect.sh` + the manual
reconcile runbook are the safety net, not a guarantee.

**Target resolution (A4), fully offline:**
1. Explicit repo in the command wins — `gh api repos/OWNER/REPO/pulls/N/merge` (unless
   OWNER/REPO is a literal `{owner}`/`{repo}` gh-api template placeholder, which gh fills
   from the CURRENT repo context, not from this string — that falls through to step 3/4),
   or `--repo`/`-R` on `gh pr merge`.
2. Else a positional target on `gh pr merge` that itself encodes a repo — a pasted PR URL
   (`https://HOST/OWNER/REPO/pull/N`) or the `OWNER/REPO#N` shorthand — which gh honors
   over the default repo. A bare PR number/branch positional encodes no repo and falls
   through, unchanged.
3. Else the checkout's `gh repo set-default` state (`remote.<name>.gh-resolved base`).
4. Else a remote heuristic: the sole github.com-hosted remote (an SSH host-ALIAS remote,
   e.g. `pt` via `github-pt`, is NOT github.com-shaped and is not a candidate — matching
   gh's own resolution; verified empirically: `gh repo view` in this repo resolves to the
   personal repo despite `pt` existing, precisely because `pt`'s host token isn't literal
   `github.com`).
5. Zero or >1 candidates -> AMBIGUOUS -> **fail loud and block**, never guess. Never
   silently allow (could hide a real pt-merge) and never silently reinterpret ambiguity as
   pt (could block a legitimate personal merge) — the message teaches `--repo` or
   `gh repo set-default`.

`pt`'s identity is read from `git remote get-url pt` at runtime — never hardcoded (a repo
with no remote literally named `pt` is out of scope for this gate; fail OPEN, not block).
**This scopes the gate by the remote NAME `pt`, a neural-lace-specific convention.** The
gate is wired estate-wide (every harnessed repo gets it), so on any OTHER dual-hosted repo
that names its mirror remote something other than `pt`, this gate is a silent no-op for
that repo — not a guarantee, and not repo-specific in its deployment even though its
identity check is repo-specific in effect.

**Parser residual (named, harness-review 2026-07-16 fixup):** the command shape read is
also fallback-checked at `.command` (flat tool-call payloads, not only nested
`.tool_input.command`), the merge-command match tolerates irregular whitespace, and
positional PR-URL/`OWNER/REPO#N` targets are parsed — but the parser inspects only the
LITERAL pre-expansion command string. Still uncovered: a runtime-interpolated value
(`gh pr merge $N --repo "$REPO_VAR"` — the variable's value is invisible to a static-string
check) falls through to default-repo resolution; a bundled short flag with no space
(`-Rowner/repo`) is not matched by the `-R` extractor and also falls through; a `gh pr
merge` invoked via a shell alias/function whose name doesn't literally contain adjacent
`gh`/`pr`/`merge` tokens is not recognized as a merge command at all. None of these
silently misclassify a resolved target — they fall through to the next resolution step (or
to the loud ambiguous-block) rather than being read as a false ALLOW/BLOCK.

**§10 evidence bar (A3).** PR #100's actual merge PATH (web-UI vs `gh` CLI) is UNKNOWN —
server-side merges are indistinguishable in the API record — so the 2026-07-15 divergence
golden scenario validates BRANCH PROTECTION, not this gate. `fp_expectation` is defined
against the RESOLVED target (never the raw command string): zero legitimate `pt`-repo
`gh pr merge` calls are expected post-cutover; any is itself the defect.

**Residual writers this gate does NOT cover (A1):** GitHub web-UI merge; a machine that
hasn't yet synced this hook (deploy-lag window — auto-install syncs only at a NEW
session); un-harnessed/external machines; CI/GitHub Actions; scheduled/cloud agents
(Decision 011 — no PreToolUse); direct `git push pt master`. Only branch protection
closes these.

**Posture reversal (A5).** This REVERSES the 2026-05-29 "PT is canonical" posture
recorded in `sync.sh` and the now-retired `sync-pt-to-personal.sh` (attic'd — see
`docs/decisions/064-...md` element 4/A6). The standing WORK-side PR-merge habit (not only
in-flight PRs) migrates to personal-side; `docs/RESUME-HERE.md` already routed
cross-machine work through `origin/master`, so only the observed merge behavior changes,
not the documented flow.

**Retirement:** pt repo archived, OR operator enables branch protection (at which point
this gate is a redundant teaching surface — may be retired or kept as UX).
