# 067 — Review independence: the pathway is the independence, not the machine

**Date:** 2026-07-29
**Status:** DECIDED. Supersedes the cross-machine framing in the original RI1/RI2 dispatch
prompt for `docs/plans/review-independence.md`.
**Tier:** 1 (reversible — a naming/scope change in an unmerged worktree; no data, no
migration, no third party, no unrecoverable spend).

## Problem (cold-read context)

The dispatch that started `docs/plans/review-independence.md` (task RI1-RI4) was scoped
around a **cross-machine** reviewer runner: "meant to run under a principal that did NOT
author the work — the desktop supervisor tick, a scheduled session, or a fresh headless
`claude -p` on this machine," with `independence: cross-machine` when the claimant hostname/
account differs from the enqueuer's and `independence: context-only` for same-machine.

Partway through the build, the operator challenged that framing directly (verbatim,
2026-07-29): **"I don't see how a different machine would change anything. It's all the
same claude, agents, harness, etc. We have several adversarial review agents already. Why
can't you utilize those to review what you're building in the short term? Can't that be
your principal?"**

## Decision

**The independence that matters is the PATHWAY, not the machine.** The three deterministic
points the operator named earlier this session (whether a review happens / what the
reviewer sees / what the verdict becomes) are what make a review trustworthy — every
Claude Code subagent dispatch already gets a fresh context window regardless of which
physical machine it runs on, so machine locality adds nothing to review quality that the
pathway doesn't already provide.

Concretely:

1. **`independence: pathway` replaces `context-only`** as the primary/expected tier —
   any run of `review-runner.sh` that went through the deterministic pipe (auto-enqueue
   trigger, versioned instruction template, runner-authored + runner-committed record)
   qualifies, on ANY machine, using the **existing adversarial reviewer agents**
   (`harness-reviewer` et al.) as its workforce. No new reviewer agent definitions.
2. **`independence: cross-machine` survives ONLY as optional additional hardening** — worth
   recording truthfully when the claimant's hostname genuinely differs (it does add one
   thing: unforgeable git authorship on the record's own commit, since a different
   machine more plausibly has a distinct git identity), but it is not built as a critical
   path and nothing blocks on it being absent.
3. **No desktop-runner critical path.** `review-runner.sh` is a plain CLI meant to be
   invoked from any fresh Claude Code session — this machine or another — never a
   dedicated scheduled daemon requirement.
4. **The doctor's WARN-on-`context-only`-for-constitution-tier-paths check is dropped**
   (there is no more `context-only` tier to warn about). The RED check survives and is
   the load-bearing one: a `harness-change-review` record is self-approval, and RED,
   whenever (a) the record's `reviewer_principal` session id matches the reviewed
   branch's authoring session id, OR (b) the record's own introducing commit's git
   author matches the reviewed commit's git author (the unforgeable half — see plan
   RI3). "Principal," for same-machine review (now the common case), means **the runner
   process that wrote and committed the record** — never the authoring session that
   enqueued the work.

## What does NOT change

The three deterministic points from the operator's earlier binding message stand exactly
as scoped: enqueue is TRIGGERED (never called) by the commit-time gate detecting an
uncovered in-surface blob; the reviewer sees ONLY a fixed, versioned instruction template
(`config/review-instructions.md`) plus the git diff the runner derives itself, never
enqueuer-supplied free text; the verdict is written AND committed by the runner's own
process, under its own git identity, never by the authoring session.

## Consequence for RI1/RI2/RI3

- RI1 (`review-queue.sh`): the queue directory default becomes a plain per-machine state
  dir (`~/.claude/state/review-queue`, mirroring `decision-queue.sh`'s own convention) —
  zero external configuration required for the primary path. It remains pointable (via
  `REVIEW_QUEUE_STATE_DIR`) at a coord-repo clone for an operator who wants cross-machine
  visibility for free through the pre-existing `coord-sync.sh` cadence (which already
  `git add -A`s its clone directory) — that is the "optional hardening," not new sync code
  this plan needed to build or self-test as a two-clone round trip.
- RI2 (`review-runner.sh`): split into deterministic subcommands (`claim`, `prepare`,
  `finalize`) with the one genuinely non-deterministic step — the actual review verdict —
  supplied as an external input to `finalize` from whichever calling session dispatched
  `harness-reviewer`. The self-claim refusal (comparing `CLAUDE_SESSION_ID` between
  enqueuer and claimant) is the mechanical guarantee that the authoring session can never
  become its own reviewer, on any machine.
- RI3 (doctor check): two RED predicates (principal-session match; record-commit-author
  match), no WARN tier.

## Evidence this is genuinely reversible

Nothing shipped under the old framing before this pivot landed (worktree-only, unmerged);
this is a rename + scope trim, not a rollback of deployed behavior.
