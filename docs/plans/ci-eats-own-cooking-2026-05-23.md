# Plan: ci/eats-own-cooking — run the harness's own evals + hook self-tests on every push and PR
Status: ACTIVE
Execution Mode: orchestrator
Mode: code
tier: 1
rung: 0
architecture: pattern
frozen: true
prd-ref: n/a — harness-development
acceptance-exempt: true
acceptance-exempt-reason: harness-internal CI wiring; no user-observable runtime — the verification artifact is the workflow runs reported by GitHub Actions, exercised in a draft PR before merge.
Backlog items absorbed: none

## Goal

The expert review of 2026-05-23 surfaced that the harness ships 44 hooks with
`--self-test` blocks, 5 golden behavioral tests under `evals/golden/`, and 7+
standalone test scripts under `adapters/claude-code/tests/`, but nothing on the
server side ever runs them. The harness's claim "the AI cannot bypass the gate"
silently degrades when the self-tests rot. This plan wires GitHub Actions to
exercise every self-test on every push and pull request, fails the workflow on
any non-zero exit, and adds README status badges so the eat-your-own-cooking
signal is visible from the repo front page.

## User-facing Outcome

A green CI run on every PR confirms (a) all 5 golden behavioral tests pass,
(b) every hook with a `--self-test` block passes, (c) every standalone test
script under `adapters/claude-code/tests/` passes, and (d) the
`validate-pr-template.sh --self-test` battery passes. Red CI on any of these
is a stop-the-line signal — the README badge surfaces it without anyone having
to open the Actions tab.

## Scope

- IN: `.github/workflows/evals.yml` (new), `.github/workflows/hooks-selftest.yml`
  (new), `README.md` (workflow descriptions + badge-URL template), this plan
  file.
- OUT: smoke-vs-full split (deferred — local sweep shows the full suite runs in
  under ~2 min, no need to split yet); inline-PR-comment reporter beyond the
  standard GitHub checks UI (deferred — checks UI + `::error file=` annotations
  are sufficient signal for v1).

## Tasks

- [ ] 1. Land workflows + badges + plan, open draft PR — Verification: mechanical

## Files to Modify/Create

- `.github/workflows/evals.yml` — runs `evals/golden/*.sh` + the PR-template
  validator self-test on every push to master and every PR event.
- `.github/workflows/hooks-selftest.yml` — discovers every
  `adapters/claude-code/hooks/*.sh` that ships a `--self-test` block (44 as of
  this commit), runs each one with `::group::` blocks for diagnostics, plus
  runs the standalone test scripts under `adapters/claude-code/tests/`.
- `README.md` — workflow descriptions, badge-URL template, and a paragraph
  explaining what red means. Hard-coded badges are not pasted (hygiene gate
  blocks owner/org strings in shipped kit files).
- `docs/plans/ci-eats-own-cooking-2026-05-23.md` — this plan file.

## Assumptions

- GitHub Actions Ubuntu runners ship modern bash, git, and jq — all confirmed
  available via `runs-on: ubuntu-latest`.
- The hook self-tests are designed to be self-contained — they `git init`
  temporary repos when needed and exit non-zero on failure. Local sweep
  confirms this for the sampled set.
- The badge URLs would use the personal-account fetch-origin; the org-account
  push-mirror surfaces the same workflows via its own Actions tab. Hard-coded
  badge URLs in `README.md` are blocked by `harness-hygiene-scan.sh` (denylist
  catches the owner/org strings), so the README documents the workflow names
  and the badge URL template generically and the actual badges live in the PR
  body where the kit-shipping hygiene rule does not apply.
- A CI environment lacks the operator's `~/.claude/` mirror. Hooks that read
  from `~/.claude/` will see absences gracefully (most degrade to no-op when
  state files are missing). Any hook whose self-test actually requires the
  mirror will surface as a CI failure and is in scope to fix or skip.

## Edge Cases

- A hook whose `--self-test` requires a writable `~/.claude/state/` directory
  may fail in CI. Workaround: CI `HOME` is writable, so `~/.claude/state/` is
  creatable; hooks that need it should `mkdir -p` on their own.
- A standalone test under `adapters/claude-code/tests/` may be a directory of
  fixtures rather than an executable. The runner uses `tests/*.sh` glob to
  filter to executables only.
- A self-test that depends on cross-hook state (e.g., a marker file written by
  another hook) is structurally fragile and out of scope to fix here — it
  surfaces as a CI failure and gets logged as a follow-up.

## Testing Strategy

- Local: run `bash adapters/claude-code/hooks/<hook>.sh --self-test` for a
  representative sample (harness-hygiene-scan, plan-edit-validator,
  validate-pr-template) to confirm exit-0. A full sweep runs in the background
  and informs the PR body. Run `bash evals/golden/<test>.sh` for the 5 golden
  tests.
- CI: opening the draft PR is itself the test — GitHub Actions runs both
  workflows and reports pass/fail. PR description includes the green-or-red
  outcome and the specific failures (if any).

## In-flight scope updates

(none yet)

## Decisions Log

### Decision: separate workflows for evals vs hooks-selftest vs PR-template
- **Tier:** 1
- **Status:** proceeded with recommendation
- **Chosen:** three independent workflows (evals.yml, hooks-selftest.yml,
  existing pr-template-check.yml) with their own badges.
- **Alternatives:** one mega-workflow; pros = one badge, one log. Cons = a
  failure in one suite shows up as failure of the whole thing, making the
  badge less actionable.
- **Reasoning:** independent badges surface independent rot. A failing
  hooks-selftest tells the user the hook layer is broken; a failing evals
  badge tells them the golden behavioral assertions drifted. Conflating
  them muddies the signal.
- **Checkpoint:** n/a (single commit)
- **To reverse:** delete `evals.yml` + `hooks-selftest.yml`, remove badges.

## Definition of Done

- [ ] Both workflows land on the branch and are referenced from the PR body.
- [ ] README has the three badges + explanation paragraph.
- [ ] Draft PR is open against master, NOT merged.
- [ ] The PR body documents the local-sweep result so a reviewer can see the
      expected baseline before reading the live CI run.
