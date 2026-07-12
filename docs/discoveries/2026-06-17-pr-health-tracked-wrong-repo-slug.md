---
title: PR-health snapshots emitted against the wrong repo slug
date: 2026-06-17
type: process
status: decided
auto_applied: true
originating_context: orchestrator-prime <product>-fix session; Misha asked "have you deployed the contacts-list updates?" and I queried gh against work-account/<product>, getting "0 open PRs" — wrong repo
decision_needed: n/a — auto-applied (behavioral discipline; optional gate enhancement noted)
predicted_downstream:
  - orchestrator PR-health discipline (always resolve the real origin before gh)
  - adapters/claude-code/hooks/pr-health-snapshot-gate.sh (optional: resolve slugs from active-repos.txt, surface mismatch)
---

## What was discovered

Across this session I emitted `## PR Health Snapshot` and ran `gh pr list` against
`work-account/<product>` — a stale, divergent, unrelated repo (isFork:false, parent:null, no
shared history) — instead of the real <product> repo `work-org/<product>`. Result:
the gate-satisfying snapshots reported "<product>: 0 open PRs" when in fact **#551**
(contacts-list cleanup, the exact thing Misha was asking about), **#555**, and later
**#556** were OPEN. The wrong slug also went into two dispatched builders' prompts
(they self-corrected, opening PRs against the right repo).

`~/.claude/config/active-repos.txt` was CORRECT the whole time — it lists
`work-org/<product>`. So the root cause was NOT a bad config; it was the
orchestrator hardcoding a *guessed* owner/repo slug instead of reading active-repos.txt
or `git remote -v` from the checkout.

## Why it matters

A PR-health snapshot against the wrong repo is worse than none — it reports a confident
"all clear / 0 open PRs" while real customer-facing PRs sit unmerged. It directly
produced a false "I can't find PR #551" claim to Misha before I corrected it. This is a
NO-TRUST failure: I trusted my own memory of the slug instead of verifying the artifact.

A second, related hazard surfaced: the orchestrator and concurrent write-builders SHARE
the global `gh` active account (`gh auth switch -u` mutates `~/.config/gh`). With
builders switching to work-account while the orchestrator interleaves queries, the active
account flips unpredictably → intermittent 404s on `work-org/*` (active account
momentarily personal). The repo is fine; the account is wrong for that instant.

## Options

A. Behavioral: always resolve the real repo from `git remote -v` (or active-repos.txt) before any `gh` query / snapshot. Never type a slug from memory.
B. Mechanical: extend `pr-health-snapshot-gate.sh` to resolve the canonical slug per repo from active-repos.txt and warn when the emitted snapshot names a slug not in the config.
C. For the gh-account race: serialize gh ops, or prefer `GH_TOKEN`-scoped invocations, or stop letting builders switch the global account.

## Recommendation

A now (auto-applied — pure discipline, reversible). B as a cheap follow-up that makes the
discipline mechanical (the gate already reads active-repos.txt; cross-checking the emitted
slug against it is a small add). C: note the account-race; defer a structural fix (it
needs design — per-invocation account scoping).

## Decision

A auto-applied this session: I now read `git remote -v` / active-repos.txt before gh
queries. B + C surfaced for the operator as optional harness follow-ups (not built).

## Implementation log

- This discovery (durable capture). B/C not yet built — flagged as follow-ups.
