---
title: Main checkout diverged from origin/master; hook-wiring-coverage gap
date: 2026-05-27
type: process
status: pending
auto_applied: false
originating_context: conv-tree project-root topology session (PR #20). Discovered while landing the topology fix — the "extract-pending hook was never wired" symptom traced to a diverged checkout, not a missing commit.
decision_needed: How should the main checkout (`feat/harness-principles-doc-and-gate` @5eecd69) be reconciled with origin/master, given it has 3 local-only commits AND is missing ~10 origin commits?
predicted_downstream:
  - the main checkout's branch state
  - docs/plans/conv-tree-project-root-topology.md (flip to COMPLETED on sync)
  - possibly a new hook-wiring-coverage lint (harness-improvement — discuss first)
---

## What was discovered

1. **Checkout divergence.** The main checkout (`~/dev/Pocket Technician/neural-lace`) sits on branch
   `feat/harness-principles-doc-and-gate` @ `5eecd69`, which forked from `origin/master` at merge-base
   `fff2de3`. It carries **3 local-only "design:" commits** (`03a7d2d`, `234950a`, `5eecd69` — Pattern-2
   sequencing + plan-lifecycle-redesign ADR 036) that were never pushed, AND is **missing ~10 origin/master
   commits** (PRs #2/#3/#5/#10/#12/#14/#15/#16/#17 + my #20), including the conv-tree backfill tracking (#3)
   and auto-extract hook (#10).

2. **Root-cause of the "hook never wired" symptom.** Misha's premise — `conversation-tree-extract-pending.sh`
   was authored but never wired into settings — was true for THIS checkout's live env, but origin/master
   *already* wired it (#10). The live `~/.claude` auto-deploys (post-commit `install.sh`) from whatever
   checkout commits; because this checkout is on the diverged line that predates #10, the live settings
   never received the wiring. So the bug was a *staleness/divergence* symptom, not a missing fix.

3. **Hook-wiring-coverage gap (harness-improvement candidate).** A hook can be authored, executable, and
   self-test-passing while never being referenced in `settings.json.template`'s hook chains — with no gate
   catching it. extract-pending sat in this state on the diverged line. A lint ("every hook in
   `adapters/claude-code/hooks/` is wired in `settings.json.template` OR explicitly marked standalone")
   would catch the class.

## Why it matters

Future sessions on this checkout will keep auto-deploying a stale harness to live (missing 10 commits of
fixes) and will keep mis-attributing "X was never done" when X exists on origin/master. The 3 local commits
are unpushed work at risk if the divergence is resolved carelessly (a wrong reset loses them; a force-push
is prohibited).

## Options

A. **Merge origin/master into the branch** (`git merge origin/master`) — keeps the 3 local commits, brings
   origin's 10 in, resolves conflicts once. Non-destructive; deepens history but loses nothing.
B. **PR the 3 design commits to origin/master first, then reset the local branch onto origin/master** —
   cleanest end state (everything on origin), but requires the 3 commits to land via review first.
C. **Reset the local branch onto origin/master, cherry-pick the 3 commits onto a fresh branch** — similar
   to B without a PR for the design commits yet.

## Recommendation

**A** as the immediate low-risk step (nothing lost, conflicts resolved once), then land the 3 design commits
via a normal PR when ready (B's end state). Reason: A is fully reversible and preserves all work; the
"clean single-line" end state (B) is reachable afterward without time pressure. This is a Tier-3 reconciliation
(non-fast-forward, risk to unpushed commits) so it was surfaced rather than auto-applied per
`git-discipline.md` Rule 2.

## Decision

(pending Misha's choice of A/B/C)

## Implementation log

(empty until decided)
