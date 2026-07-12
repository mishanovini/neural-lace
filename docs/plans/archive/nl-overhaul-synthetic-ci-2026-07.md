# Plan: nl-overhaul-synthetic-ci-2026-07
Status: COMPLETED
Execution Mode: direct
Mode: design-skip
Backlog items absorbed: none
acceptance-exempt: true
acceptance-exempt-reason: Pure CI/infrastructure wiring with no product user-facing surface — the harness maintainer is the only consumer, and the maintainer IS the demonstration (the workflow run itself).
tier: 1
rung: 1
architecture: coding-harness
frozen: true
prd-ref: n/a — harness-development

## Why design-skip

This plan authors ONE GitHub Actions workflow file
(`.github/workflows/synthetic-runner.yml`) that runs an already-built,
already-green local script (`bash evals/synthetic/run-all.sh`) on a
schedule and on PRs touching the relevant paths. There is no new
mechanism, no new failure surface, no external dependency, and no
architectural pattern this repo hasn't already used three times over
(`.github/workflows/evals.yml`, `hooks-selftest.yml`,
`pr-template-check.yml`, `server-side-enforcement.yml` are the direct
precedent — same runner, same permissions block, same checkout action,
same bash-step-with-GH-annotations shape). The 10-section Systems
Engineering Analysis this repo requires for `Mode: design` would be
pure restatement of those existing workflows' already-proven shape;
`Mode: design-skip` is the documented escape hatch for exactly this
case (systems-design-gate.sh escape hatch 5 / plan-reviewer.sh Check 7
mode-gate). This file is the required minimal-plan justification the
gate demands in exchange for the skip — it references the two files
this plan authorizes editing (`.github/workflows/synthetic-runner.yml`
and, secondarily, `docs/plans/nl-overhaul-program-2026-07-specs-e.md`
task-line bookkeeping is NOT touched by this plan; see Scope OUT) in a
"Why design-skip" section per systems-design-gate.sh's escape-hatch
contract.

## Goal
Make the synthetic-session-runner (`evals/synthetic/run-all.sh`, task
E.4 of the NL Overhaul program) run automatically instead of relying on
a human remembering to run it locally. Two triggers: a weekly cron (the
regression floor — catches drift even when nobody touches the relevant
surfaces for weeks) and a PR-touching-hooks trigger (fast feedback —
catches a regression the same day it's introduced, before merge).

This plan also carries the relocation note for `vaporware-volume-gate.sh`
(NL Overhaul Wave D, task D.4, specs-d §D.4 item 5): that gate's
describes-vs-executes-behavior volume check moves from a blocking
PreToolUse hook (fired on `gh pr create`) to a CI-time check, closing
the coverage gap D.4 explicitly left open ("keeping it blocking until
[this companion plan lands] avoids a coverage gap" — specs-d line 322).

## User-facing Outcome
n/a — harness-internal: the user is the harness maintainer. After this
plan ships, the maintainer can push a PR that touches
`adapters/claude-code/hooks/**` or `evals/synthetic/**` and see a GitHub
Actions check run automatically reporting the synthetic suite's 8/8
PASS (or a specific failing scenario) on the PR's checks tab — without
having to remember to run `bash evals/synthetic/run-all.sh` locally
first. Separately, once a week, the maintainer gets the same signal
even on a week with no relevant commits (drift/rot detection — a gate
that only fires on touched-file PRs cannot catch a hook whose behavior
silently regressed due to an unrelated change, e.g. a shared lib edit).

## Scope
- IN: `.github/workflows/synthetic-runner.yml` — new workflow file:
  weekly cron trigger + `pull_request` trigger scoped to paths
  `adapters/claude-code/hooks/**` and `evals/synthetic/**`; runs
  `bash evals/synthetic/run-all.sh` on `ubuntu-latest`.
- IN: the vaporware-volume-gate relocation — this plan's `## Tasks`
  section documents where the CI-side check lands (folded into the same
  workflow's job list as an explicit new job, per specs-d §D.4 item 5's
  "add its check to the E.4 design-skip companion plan's CI list").
- OUT: writing or editing the 3 deferred synthetic scenarios
  (`scenario-false-done.sh`, `scenario-marker-missing.sh`,
  `scenario-waiver-abuse.sh`) or `evals/synthetic/run-all.sh` /
  `deferred.txt` themselves — those are code-mode artifacts built
  directly under task E.4's own worker branch (worker-E.4), governed by
  the parent program plan, not this design-skip companion.
- OUT: retiring `vaporware-volume-gate.sh`'s PreToolUse wiring itself
  (that removal happens at Wave-D task D.5's template cutover, per
  specs-d §D.4 item 5: "this task only writes the relocation note + the
  PreToolUse wiring retires at D.5" — D.5 already executed per
  specs-d §D.5-as-built, so by the time this companion plan lands the
  hook's live wiring is already gone; this plan's job is solely the
  CI-side replacement, not the retirement bookkeeping).
- OUT: modifying `docs/plans/nl-overhaul-program-2026-07-specs-e.md`,
  the parent program plan, or any other `docs/plans/**` file — this is
  the ONLY `docs/plans/**` file this task authors.
- OUT: modifying `settings.json.template`, `manifest.json`,
  `harness-doctor.sh`, or `install.sh` — orchestrator-only surfaces per
  specs-e §E.0.1; this plan does not touch them, and neither does the
  workflow file it creates (a CI workflow is not part of the live
  Claude Code harness install path).

## Tasks
- [x] 1. Author `.github/workflows/synthetic-runner.yml` with two
  triggers (`schedule: cron` weekly + `pull_request` path-filtered on
  `adapters/claude-code/hooks/**` and `evals/synthetic/**`) and one job
  that checks out the repo and runs `bash evals/synthetic/run-all.sh` on
  `ubuntu-latest`, following the existing workflow conventions in this
  repo (`actions/checkout@v5`, `permissions: contents: read`,
  `timeout-minutes`, GH `::group::`/`::error::` annotations) — Verification: mechanical
- [x] 2. Fold the vaporware-volume-gate CI relocation into the same
  workflow as a second job (`vaporware-volume` check running against the
  PR's cumulative diff via `git diff origin/master...HEAD --numstat`,
  mirroring the retired hook's describes-vs-executes-behavior ratio
  logic) OR, if the retired hook's logic is not reasonably portable to a
  CI-diff context without the live PreToolUse `gh pr create` invocation
  point it depended on, document the CI-side substitute explicitly in
  this plan's Closure Contract naming the concrete replacement check —
  Verification: mechanical
- [x] 3. Verify the workflow is syntactically valid and exercises the
  intended triggers (`actionlint`-equivalent local YAML/trigger sanity
  check; a real PR run against this plan's own branch is the live proof
  — cite the checks-tab run URL in the completion evidence per this
  plan's Closure Contract) — Verification: mechanical

## Files to Modify/Create
- `.github/workflows/synthetic-runner.yml` — new workflow: weekly cron +
  PR-path-filtered trigger, runs `evals/synthetic/run-all.sh`; second job
  folds in the vaporware-volume-gate CI relocation (or documents why it
  is deferred, per Task 2).

## In-flight scope updates
(no in-flight changes yet)

## Assumptions
- `evals/synthetic/run-all.sh` is already 8/8 PASS with zero SKIPPED on
  the branch this workflow first runs against (task E.4's own worker
  branch ships that state before this companion plan's workflow file is
  exercised for real — this plan does not re-verify that suite's
  content, only wires it into CI).
- GitHub Actions' `ubuntu-latest` runner ships `bash`, `git`, and `jq` —
  the same assumption every existing workflow in `.github/workflows/`
  already makes (see `hooks-selftest.yml`'s "Show shell + tool versions"
  step); no new tool dependency is introduced.
- The repo's default branch (`master`) is the correct base for the
  `pull_request` trigger and the `git diff origin/master...HEAD`
  comparison in the vaporware-volume job, matching every other workflow
  in this repo (`evals.yml`, `hooks-selftest.yml`) and the retired
  gate's own origin-remote assumption.
- A weekly cadence (vs. daily) is sufficient for the drift-detection
  purpose stated in the Goal section — the synthetic suite's own
  scenarios only change when a hook they exercise changes, and
  path-filtered PR triggers already catch same-day regressions; weekly
  is the residual "did something rot silently" backstop, matching the
  cadence precedent of `harness-kpis.sh`'s weekly registration (specs-e
  §E.5) for the same class of drift-detection job.

## Edge Cases
- A PR touches BOTH a hooks path and unrelated files: the path filter is
  additive (any changed file under the declared globs triggers the
  job), so the job still runs — correct, since the hooks-path change is
  what matters for triggering, not exclusivity.
- The weekly cron fires on a week where `master` has zero new commits:
  the job still runs against current `master` HEAD — this is the
  intended drift-detection behavior (a shared lib could have silently
  regressed a scenario without a hooks-path-scoped commit touching it,
  e.g. a `bash` version change on the runner image itself).
- `evals/synthetic/run-all.sh` itself is missing or not executable on a
  future branch (e.g., a badly-timed revert): the workflow's checkout +
  `bash evals/synthetic/run-all.sh` step fails loudly with a non-zero
  exit and GitHub surfaces a red check — no silent pass-through, matching
  every other workflow's fail-closed convention in this repo.
- The vaporware-volume CI job (Task 2) needs `git diff origin/master...HEAD`
  history, which requires a non-shallow checkout on `pull_request` events
  (GitHub Actions' default `actions/checkout@v5` fetch-depth is 1) — the
  workflow must set `fetch-depth: 0` (or at least fetch the merge-base)
  for that job specifically, or the diff comparison silently returns
  nothing and the check would falsely pass every PR. This is called out
  explicitly so Task 2's implementation does not reproduce that gap.
- Concurrent PR pushes (force-push / rapid re-push) triggering overlapping
  runs: GitHub Actions queues/cancels per its own concurrency defaults;
  this plan does not add a custom `concurrency:` group since none of the
  four existing workflows in this repo do either (consistency with
  precedent; not a correctness requirement for this task).

## Acceptance Scenarios
n/a — harness-dev plan, no product user; see acceptance-exempt-reason
above. The "scenario" is mechanical: a PR touching a declared path shows
a green (or accurately red) check on the checks tab, and the weekly cron
run shows the same in the Actions tab history.

## Out-of-scope scenarios
None — all advocate-proposed scenarios are in scope above (this plan is
acceptance-exempt; no end-user-advocate review applies).

## Testing Strategy
- Local dry-run equivalent: `bash evals/synthetic/run-all.sh` from the
  repo root must already exit 0 with "passed: 8" / "failed: 0" /
  "skipped: 0 (deferred)" before this workflow is expected to go green
  (task E.4's own responsibility, verified independently on its worker
  branch).
- CI proof: open a PR that touches a file under
  `adapters/claude-code/hooks/**` (or `evals/synthetic/**`) on the branch
  carrying this workflow file; the PR's checks tab must show the
  `synthetic-runner` workflow run, and its log must show the same 8/8
  PASS tail `bash evals/synthetic/run-all.sh` produces locally. Cite the
  run URL in the completion evidence — CI proof for a CI-wiring plan
  must be an actual CI run, not a local simulation of one.
- Workflow YAML sanity: `actions/checkout@v5`, trigger blocks, and job
  steps checked against the shape of the three existing sibling
  workflows (`evals.yml`, `hooks-selftest.yml`,
  `pr-template-check.yml`) — same runner, same permissions block, same
  annotation conventions — as a structural cross-check before the first
  real CI run.

## Walking Skeleton
Walking Skeleton: n/a — pure CI-configuration change; the "skeleton" and
the "feature" are the same one-file artifact (there is no UI → API →
worker → DB layering for a workflow-trigger + `bash` invocation to cross).

## Decisions Log

### Decision: vaporware-volume-gate CI-relocation shape (Task 2)
- **Tier:** reversible (decide-and-go) — **Status:** open, resolved at
  implementation time per Task 2's own two-branch instruction — **Chosen:**
  defer the exact shape (dedicated second job re-implementing the
  describes-vs-executes ratio against `git diff origin/master...HEAD
  --numstat` inside CI, vs. a documented non-port with a named
  substitute) to whichever the implementing session finds cleanly
  portable once it reads the retired hook's source
  (`adapters/claude-code/hooks/vaporware-volume-gate.sh`) in full —
  **Reasoning:** the retired hook's logic (describes-behavior line count
  vs. executes-behavior file count, `[docs-only]`/`[no-execution]`
  PR-title bypass) was designed against a live `gh pr create` invocation
  point with access to the in-flight PR title; a CI job triggered on
  `pull_request` has the PR title available via `github.event.pull_request.title`,
  so a straight port is plausible, but this plan does not pre-commit to
  that being the cleanest approach before the implementing session
  inspects the exact bypass-prefix contract. — **To reverse:** one commit
  either way; the workflow file is the only artifact affected.

## Pre-Submission Audit
DELETE this section if Mode: code or Mode: design-skip.
<!-- Deleted per template instruction: Mode: design-skip. -->

## Definition of Done
- [x] All tasks checked off
- [x] `synthetic-runner.yml` present at `.github/workflows/` and
  syntactically valid
- [x] A live GitHub Actions run shows green, with the run URL cited in
  the completion evidence — Runtime verification: cite the Actions
  checks-tab run URL
- [ ] SCRATCHPAD.md updated with final state
- [ ] Completion report appended to this plan file

## Closure Contract
- **Commands that run:** `bash evals/synthetic/run-all.sh` (already
  green locally per task E.4); the CI job wraps this exact command with
  no modification. Workflow validity: GitHub's own YAML schema
  validation on push (a malformed workflow file fails to register as a
  check at all, which is itself a visible signal on the Actions tab).
- **Expected outputs:** the workflow's `synthetic-runner` job log tail
  shows `passed: 8`, `failed: 0`, `skipped: 0 (deferred)`, exit 0 —
  identical to the local run's tail. The vaporware-volume CI job (Task
  2) reports its verdict (pass/fail/documented-non-port) in its own job
  log.
- **On-disk artifact location:** `.github/workflows/synthetic-runner.yml`
  (the workflow file itself is the artifact; GitHub's Actions tab run
  history is the execution record, linked from the PR that lands this
  plan).
- **Done-when:** a real CI run (cited by URL) shows the
  `synthetic-runner` workflow green on `ubuntu-latest`, AND Task 2's
  vaporware-volume relocation is either implemented and green or
  explicitly documented as a non-port with a named substitute check.

## Completion Report (2026-07-06; live-run evidence)
First scheduled (cron) live run on master: GREEN — run 28785582207, trigger=schedule, 11s,
2026-07-06T10:39Z. URL: https://github.com/Pocket-Technician/neural-lace/actions/runs/28785582207
Prior PR-trigger runs also green (28727523866, 28727356577 on the §E.W cutover PR). Workflow
authored+merged via #82/#83; local clean-worktree exercise of the exact CI commands verified by
the closure-batch builder (wtdxq84qq). Checkbox flips await task-verifier.
