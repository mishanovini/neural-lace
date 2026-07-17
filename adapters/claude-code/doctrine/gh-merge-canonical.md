# gh-merge canonical write-discipline — compact

> Enforcement: gh-merge-canonical-gate.sh (PreToolUse Bash — blocks `gh pr merge` /
> `gh api .../pulls/N/merge` whose RESOLVED target is the `pt` repo). DEFENSE-IN-DEPTH
> only — see below. Source of truth: `docs/decisions/064-never-diverge-single-canonical-master.md`.
> Full: gh-merge-canonical-full.md
> Applies: every `gh pr merge` / merge-shaped `gh api` call on a harnessed machine.

**The rule (decision 064, SOUND-WITH-AMENDMENTS 2026-07-16):** neural-lace is
dual-hosted — personal `origin` (canonical) and work-org `pt` (mirror). A PR merged
server-side on `pt` lands on `pt`'s master only, invisible to local hooks — two
independently-mergeable masters is a structural divergence generator (full: 2026-07-15
incident). The gate blocks the merge attempt itself on the one surface a PreToolUse
hook can inspect — the `gh` CLI.

**PRIMARY vs DEFENSE-IN-DEPTH.** This gate alone does NOT make divergence impossible —
it covers only a harnessed machine merging via `gh`. **PRIMARY:** GitHub branch
protection on `pt/master` (server-side, covers web-UI/CLI/CI/collaborators) — an
access-control change, OPERATOR-ONLY. Until enabled, this gate + FF-only
`master-drift-autocorrect.sh` + manual reconcile are the safety net, not a guarantee.

**Target resolution, offline (full: edge cases):**
1. Explicit repo wins — `gh api repos/OWNER/REPO/...` or `--repo`/`-R`.
2. Else a positional PR URL or `OWNER/REPO#N` on `gh pr merge`. A bare PR
   number/branch encodes no repo and falls through.
3. Else `gh repo set-default` state.
4. Else the sole github.com-hosted remote (an SSH host-alias like `pt` doesn't count).
5. Zero or >1 candidates -> AMBIGUOUS -> **fail loud and block**, never guess.

`pt`'s identity is read from `git remote get-url pt` at runtime — never hardcoded (no
`pt` remote = out of scope, fails OPEN). Gate is wired estate-wide but its `pt`-name
convention is neural-lace-specific — a differently-named mirror on another repo makes
this gate a silent no-op there.

**Known gaps (full: parser residual, §10 detail) — none misclassify; all fall through
to ambiguous-block or default-repo:** runtime-interpolated repo values, bundled
`-Rowner/repo`, non-literal-token shell aliases for `gh pr merge`.

**Not covered (A1) — only branch protection closes these:** GitHub web-UI merge; a
machine mid deploy-lag; un-harnessed/external machines; CI/Actions; scheduled/cloud
agents (Decision 011); direct `git push pt master`.

**Posture reversal (full: detail).** Reverses the 2026-05-29 "PT is canonical" posture
— WORK-side PR-merge habit migrates to personal-side.

**Retirement:** pt repo archived, OR branch protection enabled (gate becomes redundant
teaching surface).
