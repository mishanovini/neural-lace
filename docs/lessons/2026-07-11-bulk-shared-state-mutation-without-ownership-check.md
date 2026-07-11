# Lesson — Bulk-Mutating Shared Plan State Without a Concurrent-Ownership Check

**Date:** 2026-07-11
**Source case:** a downstream-product repo-hygiene cleanup session. The product name is kept generic per `principles/harness-hygiene.md` (the operator knows the project). The operator had asked repeatedly for local-branch + stale-plan cleanup; frustration was explicit ("How many times do I have to tell you to clean this up?").
**Harness gap exposed:** `adapters/claude-code/rules/parallel-dev-discipline.md` **Practice 8** ("one item = one branch = one machine; claim before you build") is classified **Pattern (self-applied)** with **no Mechanism backing it** — nothing blocks a session from mutating a plan/branch that another live session owns. The one coordination surface that exists (`broadcast-active-session.sh`) is **per-hostname and only surfaces OTHER machines**, so it is structurally blind to a same-machine concurrent worktree.
**Harness fix:** nl-issue filed + the concurrent-ownership gate designed under "What must change."

## Case summary

Under operator pressure to stop asking and just execute the cleanup, the agent bulk-processed the stale-ACTIVE-plan list. It `grep -lE '^Status: ACTIVE' docs/plans/*.md`, flipped **all 8** matches to `Status: DEFERRED`, `git mv`'d them into `docs/plans/deferred/`, committed, and **pushed to `master`**.

One of the 8 — call it **plan P** — was **not stale**. It was that same day's plan, **being actively built right then by a concurrent session in a separate worktree on the same machine** (its own `feat/*` branch). Deferring it and pushing to trunk would have yanked the plan out from under the active builder the moment it reconciled with `master`.

The agent noticed only **after the push**, from the `git worktree list` output (which showed the second worktree and its checked-out branch), and reverted it (un-deferred, re-pushed). No work was ultimately lost, but shared trunk state was briefly corrupted for another session and recovery took two extra `master` pushes.

## What went wrong — the root causes

This is a discipline/enforcement failure, not a knowledge gap. The agent knew about worktree isolation and Practice 8. The failure was in the order of operations and in what a coarse category was trusted to mean.

### 1. Bulk-mutated shared state without a per-item ownership check
The load-bearing error. `docs/plans/` on `master` is **shared state** that concurrent sessions read and write. A bulk mutation of it (flip Status + move + push) is exactly the operation that needs a "does anyone else own any of these right now?" check first. The agent ran the mutation with **zero** ownership check — no `git worktree list`, no active-claims read — even though the SessionStart worktree-advisor had literally said "other sessions likely share this."

### 2. Conflated "don't ask permission" with "don't verify"
The behavioral root cause. The operator's "stop asking, just do it" was a directive against **permission-seeking** — surfacing decisions the agent could defend itself. The agent mis-applied it to also skip **verification** (due diligence). These are not the same thing. Running `git worktree list` before a bulk shared-state mutation is not asking permission; it is the two-second check that makes the operation safe. Frustration-driven speed collapsed "don't ask" into "don't look," and the look was the thing that would have prevented the error.

### 3. Trusted a coarse category instead of verifying each member
The SessionStart stale-plan surfacer had named a specific list of **7** genuinely-stale plans. The agent's own `grep '^Status: ACTIVE'` returned **8** — and the agent treated "everything ACTIVE" as synonymous with "the stale ones," never reconciling the count mismatch. The 8th was fresh (that day) and owned. A one-line cross-check ("is every plan I'm about to defer actually on the stale list AND not checked out in a worktree?") would have caught it.

### 4. The harness let it — Practice 8 is a Pattern, not a Mechanism
The systemic cause, and the reason this must be fixed in the harness rather than resolved to "be more careful." The discipline that prevents this — claim-before-touch / check-ownership-before-mutating-shared-state — exists in `parallel-dev-discipline.md`, but as a **self-applied Pattern**. A memory-reliant Pattern is precisely what gets skipped under pressure. And the coordination surface meant to make ownership visible (`broadcast-active-session.sh`) writes one `state.json` per **hostname** and its `check` subcommand surfaces only **other** hostnames — so a same-machine concurrent worktree (what was actually collided with) is invisible to it. The safety net had a same-machine-shaped hole.

## What must change in the harness

**Promote Practice 8 from Pattern to Mechanism: a concurrent-ownership gate.**

A **PreToolUse gate** (Bash + Edit/Write) that fires before a session performs a shared-state mutation and BLOCKS when the target is owned by another live session. Targets to guard:
- Flipping a plan file's `Status:` (ACTIVE to DEFERRED/COMPLETED/ABANDONED) or moving a file in/out of `docs/plans/`.
- A **bulk** plan or branch operation (a loop over `docs/plans/*.md`; multiple `git branch -D`).
- `git branch -D` / `git worktree remove` of a branch/worktree.

Ownership check (block if any is true):
1. **`git worktree list`** — the target branch is checked out in ANOTHER worktree on this machine, so a live same-machine session owns it. This is the check that was missing and is the cheapest, most reliable signal.
2. **Active-session claims** — the target branch/plan appears in a fresh (< staleness window) claim from another session (see broadcast extension below).

Block message names the owning worktree/session and the coordination path; override requires explicit operator authorization in-session (never a silent bypass).

**Extend `broadcast-active-session.sh`** so ownership is actually visible:
- Record and surface **same-machine** concurrent worktrees (today: other-hostnames only).
- Record **per-branch / per-plan** claims (today: per-hostname only), so the gate has branch-level ownership to check.

**Golden scenario the gate must catch:** the case above — a session bulk-defers `docs/plans/*.md` including a plan whose branch is checked out in another worktree; the gate blocks the Status flip / `git mv` and names the owning worktree.
**Expected false-positive rate:** low — the gate fires only on plan-Status / bulk / branch-delete operations, and only when a *fresh* competing claim or a live worktree checkout exists.
**Retirement condition:** if worktree-per-session claiming is ever enforced upstream (e.g. the launcher writes an authoritative per-branch lock the gate can trust exclusively), this gate's `git worktree list` heuristic can be simplified to a lock read.

## The standard, restated (answer to "is it just one-item = one-branch = one-worktree + prune on merge?")

Yes — that IS the design, and it already lives in the harness:
- **one-item = one-branch = one-worktree** via Practice 1 + Practice 8 + `worktree-isolation.md` + `spawn-worktree.sh`.
- **prune on merge** via `worktree-teardown-gate.sh` + `worktree-prune.sh` + `worktree-hygiene-sweep.sh`.

The missing middle is **claim-before-touch / check-ownership-before-mutating-shared-state**. That is Practice 8's second half, and it is the one piece with no Mechanism. The worktree/branch accumulation the operator keeps hitting is the *prune* half degrading; the plan-deferral collision is the *claim* half degrading. Both are Pattern-class today; both regenerate clutter/collisions because sessions skip self-applied discipline under load. The fix is to make the load-bearing halves Mechanisms, not reminders.

## What was changed in the harness (in response)

- This lesson.
- nl-issue filed: concurrent-ownership gate (promote Practice 8 to Mechanism) + broadcast same-machine / per-branch extension.
- (Pending build — the gate + broadcast extension go through the normal harness-reviewer + `--self-test` process; deliberately NOT rushed, since rushing is a contributing cause above.)

## Meta-note (a second, smaller lesson this same session)

The first attempt to commit THIS lesson was blocked by `harness-hygiene` because the draft named the downstream product and its feature by name. That gate worked as designed — harness docs stay product-name-free. Recorded as confirmation that the hygiene Mechanism is load-bearing, and as the reason this file speaks in generic terms ("plan P", "a downstream product").
