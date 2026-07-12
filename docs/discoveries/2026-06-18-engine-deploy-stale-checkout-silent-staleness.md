---
title: Engine deploy shipped STALE code — git HTTPS auth failed silently, fetch/pull no-op'd, deploy ran from a behind-HEAD checkout
date: 2026-06-18
type: failure-mode
status: pending
auto_applied: false
originating_context: Deploying the <product> conversation engine to production (One Season, real customer) via `npx trigger.dev@latest deploy`. Misha had just greenlit the engine deploy.
decision_needed: Should the orchestrator-prime deploy-serialization step (decision c "full") enforce "clean + verified-true-master HEAD" as a hard precondition before any production deploy, so a silent-staleness deploy is structurally impossible?
predicted_downstream:
  - docs/plans/orchestrator-prime.md (deploy-serialization task: add a verify-deployed-HEAD precondition)
  - a deploy-preflight helper that fails closed when the checkout is not at true origin/master
---

## What was discovered

Deploying the <product> engine from `~/claude-projects/work-org/<product>`:

1. The checkout's remote is `https://work-account@github.com/...` (HTTPS with an embedded username). In the
   non-interactive Bash environment there was **no git credential helper configured for that remote**, so
   `git fetch origin` and `git pull --ff-only` BOTH failed with `fatal: could not read Password for
   'https://work-account@github.com'` — but the script continued (no `set -e`), and `origin/master` resolved to a
   **stale cached ref** from a much earlier fetch.
2. The checkout's local `master` was **4 commits behind** true `origin/master` (missing #556 — the
   validators-on-all-states fix that was the entire point of the deploy — plus #563/#564/#565).
3. `npx trigger.dev@latest deploy` deployed whatever was in the working tree → shipped **stale engine code**
   and printed a confident `Successfully deployed version 20260618.1`. A naive reading of that output would
   have reported "engine deployed ✅" while One Season ran an engine **without its safety guards**.

## Why it matters

A production deploy of stale code to a real customer, masked by a green "Successfully deployed" message, is
the exact silent-staleness failure that erodes trust. The deploy tool deploys the working tree — it has no
idea the tree is behind. The "success" is real (it deployed *something*); the *content* was wrong.

## How it was caught + fixed (this session)

NO-TRUST verification: after the first "success", I checked the deploy checkout's HEAD (`be376f74`, #562)
against the intended engine PRs and found #556/#559 absent. Root-caused to the silent git-auth failure.
Fixed the fetch with `git -c credential.helper='!gh auth git-credential' fetch origin`, confirmed true
`origin/master` (`562349df`, includes #556 + #557 + #559), `git reset --hard origin/master`, re-verified the
three engine commits present, then re-deployed → `20260618.3` from true master. (An intermediate `20260618.2`
came from a still-stale ref because that fetch ALSO silently failed before the credential-helper fix.)

## The generalizable finding (the real lesson)

A deploy mechanism MUST, as a hard precondition that **fails closed**:
1. Ensure the checkout is at **true current `origin/master`** — with a working credential path (use
   `git -c credential.helper='!gh auth git-credential'` or `gh auth setup-git`; never rely on an implicit
   HTTPS password prompt in a non-interactive env). A failed fetch must ABORT the deploy, not proceed on a
   stale ref.
2. **Verify the deployed HEAD includes the intended changes** (e.g., assert the target commits/PRs are
   ancestors of HEAD) BEFORE declaring success.

This is a concrete requirement for the orchestrator-prime "full" deploy-serialization step (decision c): the
single deploy point should run this preflight so a silent-staleness deploy is structurally impossible. It is
also the same class as the cross-repo / account-flip gate issues — all symptoms of deploys/operations running
against an unverified-state checkout.

## Options

A. Add a deploy-preflight helper (`clean + git-auth-via-gh + reset-to-origin/master + assert-target-commits-present`) that fails closed; wire it into the orchestrator-prime deploy-serialization step.
B. Document the manual discipline (use the gh credential helper + verify-HEAD before every `trigger.dev deploy`) until A lands.

## Recommendation

A (preempt the class — Rule 6), folded into orchestrator-prime "full". B as the interim discipline. Surfaced
to Misha as part of the orchestrator-prime greenlight; not auto-applied (it touches the deploy mechanism).
