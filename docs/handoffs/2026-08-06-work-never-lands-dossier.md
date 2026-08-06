# Dossier: work gets built and never lands

**For Fable on a second machine.** This is an evidence package, not a design. Read it, analyze
it, produce a design, then plan → build → deploy. Nothing here is a proposed solution the
operator has approved; the "what has already been tried" section exists so you do not re-propose
something that already failed.

Written 2026-08-06 from Office_PC at master `97f3bc6b`. Every number was measured on that
machine on that date with the command shown. Re-measure before relying on any of it.

---

## 1. The problem, in the operator's words

> "How many times have we resolved this? This keeps being an issue, and we keep coming back and
> fixing it, and then it keeps being an issue. How do we actually resolve this forever? I very
> specifically designed this harness to try to keep processes clean and deterministic, and yet
> you consistently keep making a mess of all of this. There are branches and worktrees and
> scattered sessions scattered all over the place, and it's leaving a mess. Work is not getting
> done, or is not getting deployed, is not getting completed, and we keep having to fix the same
> problems all over again."

The operator's stated goal for the system: **full accountability, good observability, and the
ability to work across multiple machines simultaneously and delegate work efficiently.**

This is a recurrence, not a first occurrence. Treat "why did the previous fixes not hold?" as a
first-class question — arguably *the* question.

---

## 2. Measured state (PROVEN 2026-08-06, Office_PC)

### 2.1 Unmerged work

```bash
git for-each-ref --format='%(refname:short)' refs/heads/ | grep -v '^master$' | while read b; do
  n=$(git rev-list --count master.."$b"); [ "$n" -gt 0 ] && echo "$n $b"; done
```

**25 branches carrying 71 commits that are not on master.** Oldest: 2026-07-15 (three weeks).
Largest single branch: 18 commits. This inventory is enumerable in about two seconds and is
surfaced nowhere.

### 2.2 Worktrees

**36 worktrees** exist under `.claude/worktrees/`, reported by the `active-session-broadcast`
SessionStart hook every session. That hook prints them as *ownership signals* ("do not mutate
these without coordinating") — it does **not** report whether any of them contain unmerged
commits. The information that matters is adjacent to the information that is printed.

### 2.3 Three concrete instances found in a single day

All three were discovered only because the operator asked a question, not by any mechanism:

| Work | Built | Status when found |
|---|---|---|
| OD-024 + the directives elaboration layer | 2026-08-04, commits `579b25bc` + `28608138` | unmerged 2 days; **the building agent was recorded as STOPPED with no completion record** |
| Fable→Opus model-fallback resolver, 72/72 | 2026-08-05, commit `3c83bf07` | unmerged, verified-correct, never picked up |
| Cockpit green "currently building" highlight | 2026-08-05, `c8df1d2c` + `5c95b277` | unmerged, browser-verified, blocked only by a rebase |

The first is the sharpest: the harness **emitted a notification** saying the agent had stopped
with no completion record. Nothing consumed it. The information existed and was not an
obligation.

### 2.4 CI

- `Evals` is failing on master and has been across at least three consecutive SHAs
  (`a5ce6da6`, `e246feeb`, and pending on `24ccc3f1`). The failure is
  **`Golden suite: 5 passed, 1 failed (total 6)`** — one golden behavioral test, persistently red.
- Three runs on `24ccc3f1` have been **`queued` for over four hours** while the operator received
  "Run failed" notifications for them. Queue state and notification state disagree; establish
  which is true before theorising.
- Branch protection is bypassed on direct pushes to master ("Bypassed rule violations for
  refs/heads/master — Required status check *validate* is expected").

### 2.5 The keystone: the governing directive was never written down

On 2026-08-06 the operator said:

> "What do you mean, nothing makes the landing mandatory? I've told you dozens of times that the
> harness needs to be designed so that it is mechanically impossible for an agent or an effort to
> call itself finished before everything is deployed."

He is right that he said it. **It is not in the register.** The 24 entries are:

```
OD-001 no-wsl-dependency          OD-013 maximize-parallelization
OD-002 anti-bloat-modify-not-add  OD-014 sessions-247-with-headroom
OD-003 no-new-hardware            OD-015 measure-real-loe-at-plan-time
OD-004 gate-philosophy-…          OD-016 observability-equal-clarity
OD-005 workaround-as-sensor       OD-017 self-learning-closed-loop
OD-006 push-over-pull-…           OD-018 incentive-by-design-cheapest-path
OD-007 cleanup-and-prevention-…   OD-019 branch-protection-work-org-mirror
OD-008 concurrency-pressure-…     OD-020 cowork-policy-registry-key
OD-009 graceful-stop-drain        OD-021 ci-is-read-mandatory
OD-010 disposition-everything     OD-022 merge-verify-mechanization
OD-011 agent-world-class-standard OD-023 task-id-determinism
OD-012 standing-autonomy-…        OD-024 solution-shape-layer-sweep
```

`grep -i "deploy\|finished\|not done until\|merged to master"` over the register's instruction
text returns **nothing**. OD-022 (merge-verify-mechanization) is adjacent but scoped to the
build→verify closure, not to deploy-completion.

**This is the single most important fact in this dossier.** The directive that would have
prevented every stranding in §2.3 has been stated repeatedly by the operator over months and has
no entry, therefore no requirements, no anti-patterns, no gate, and no carrier. Meanwhile 24
directives that *were* captured are enforced to varying degrees.

The failure is not that the harness ignored a rule. It is that **the rule never became a
representable object**, so there was nothing to ignore. Any design that addresses stranded work
without also making directive capture mechanical will regress the moment the operator states the
next directive out loud.

Corollary worth testing: how many *other* directives has the operator stated that never became
entries? The register is the only inventory, and it cannot list what it never captured.

### 2.6 The push-side funnel is disabled in this repo

A **local `core.hooksPath`** in `.git/config` points at `<repo>/.git/hooks`, overriding the
adapter hooks path. `.git/hooks` contains no `pre-push`. Two gates therefore never run:
`pre-push-divergence-check.sh` and **`review-record-push-gate.sh` — the authoritative
review-coverage funnel.** Proven with `GIT_TRACE=1 git hook run --ignore-missing pre-push`.

This matters enormously for your analysis: [`docs/designs/end-to-end-process.md`](../designs/end-to-end-process.md)
§"The cherry-pick problem" makes `pre-push` **the authoritative enforcement point** for the
entire pipeline, precisely because the commit-time gate deadlocks builders who cannot dispatch
reviewers. That design decision is sound *and the mechanism it depends on is not executing.*

---

## 3. Why the current design does not catch this

State the mechanism, not the intention, for each.

**"Done" is defined locally.** For a builder agent in a worktree, done = committed. The
orchestrator is supposed to cherry-pick and merge. Nothing makes that transition mandatory, and
nothing makes its *absence* representable — there is no state anywhere meaning "built, not
landed." Absence of a merge is indistinguishable from absence of work.

**The obligation ledgers are per-session and per-plan, not per-artifact.** `stop-verdict-dispatcher`
enforces verify-obligations and escape-obligations at session end. Neither asks "did anything you
built reach master?" A session can end clean with 18 unmerged commits in its worktree.

**Notifications are not obligations.** The stopped-agent notification is the proof.

**The enforcement point that would catch it is disabled** (§2.6).

**Self-tests verify the artifact, not the path.** A related class documented the same day: a suite
that dies midway (`server.selftest.js` crashes at line 893, so scenario S64 at line 1663 has never
run) looks identical to a suite that passed. Silence reads as health throughout this system.

---

## 4. What has already been tried — do not re-propose without addressing why it failed

- **The orchestrator pattern** (`doctrine/orchestrator-pattern.md`): builders in worktrees, the
  orchestrator cherry-picks and verifies. This *is* the current design. It fails when the
  orchestrator's session ends, compacts, or is interrupted — the obligation lives only in the
  orchestrator's context.
- **`SCRATCHPAD.md`** as session working memory. On 2026-08-04 it recorded the elaboration layer
  as "landing." It never landed. A hand-maintained status file records intent, not state.
- **The operator-directives register** (`docs/operator-directives.md`, OD-001..OD-024). Entries
  are created *after* work is done, so a directive that was never built has no entry to be
  missing from. The register on master stopped at OD-023 while OD-024 sat in an unmerged commit.
- **`nl-issue.sh`** machine-wide ledger — captures friction, but is per-machine and advisory.
- **The concurrent-ownership gate** — prevents two sessions colliding on a branch; says nothing
  about whether a branch ever lands.
- **The blocking-gate budget** — the count was raised 12 → 13 → 14 and currently measures 16,
  each raise happening *after* the ceiling bound. Adding a gate is the reflex; it has not worked.

---

## 5. Binding constraints on any design

These are standing operator directives. A design that violates one will be rejected.

1. **Make the wrong state unrepresentable, not detectable** (2026-08-06). *"Prefer doing it right
   the first time over adding reviewers and checkers that find it afterward and tax every
   session."* A monitoring dashboard for unmerged branches is the wrong shape.
2. **Comprehensive, class-level solutions** — OD-024, the six-layer sweep: schema/data model,
   mechanical gate, parser/renderer, migration of the existing estate, doctrine, agent prompt.
   Each used or explicitly waived with a stated reason.
3. **Modify, do not add** — OD-002 anti-bloat. Extend existing machinery in preference to new.
4. **Incentive by design** — OD-018: the compliant path must be the *cheapest* path. A gate that
   is slower than bypassing it manufactures the workaround.
5. **Everlasting and cross-machine.** Memory files on one machine do not qualify. It must live in
   the repo and install everywhere.
6. **Migration is required, not optional.** 71 existing commits across 25 branches need
   disposition — merge, rebase, or abandon-with-reason. A design that only prevents *new*
   strandings leaves the current mess in place.

---

## 6. Questions the design must answer

1. What is the durable representation of "built but not landed," and where does it live such that
   it survives session end, compaction, and machine boundaries?
2. What makes landing the cheapest path rather than an extra step (OD-018)?
3. Where is the enforcement point, given that the designed one (`pre-push`) is currently disabled
   by a local git config — and what prevents a config override from silently disabling it again?
4. Who or what is accountable when the orchestrator session dies mid-flight? The current answer is
   "nobody," which is how three pieces of work were stranded in two days.
5. How does a *second machine* discover work stranded on a *first* machine? Today: it cannot —
   worktrees are local, and the coordination repo carries no branch state.
6. What is the disposition procedure for the existing 71 commits, and who runs it?
7. Why did the previous attempts (§4) not hold, and what is structurally different this time?

---

## 7. Related evidence in the repo

- [`docs/designs/end-to-end-process.md`](../designs/end-to-end-process.md) — the ten-stage
  pipeline, its handoff contracts, and its own honest status table. Stage 7 (integration) is
  where this failure lives; stage 8 (the funnel) is the disabled enforcement point.
- [`docs/handoffs/2026-08-06-cross-machine-process-and-cockpit-handoff.md`](2026-08-06-cross-machine-process-and-cockpit-handoff.md)
  — the same day's cross-machine findings, including the gate/stage mapping results (4 of 16
  blocking units guard no pipeline stage; a 16→13 consolidation reproduced GREEN) and the queued
  work items Q1–Q3.
- [`docs/operator-directives.md`](../operator-directives.md) — the standing directive register.
- `adapters/claude-code/doctrine/orchestrator-pattern.md` — the current, insufficient design.
- `adapters/claude-code/hooks/stop-verdict-dispatcher.sh` — the session-end obligation machinery
  that exists and does not cover this case.

---

## 8. Adjacent defect, same class, cheap to fold in

The **directives elaboration layer** (merged or merging as OD-024) is carried by
`doctrine-jit.sh`, which is wired at **`PostToolUse` on `Edit|Write|MultiEdit`** — so it does work
after every file edit. The operator's correction, 2026-08-06:

> "Why would you have the elaboration layer do work on every single tool call? The purpose of this
> is just to elaborate on the directives that I give you. This is something that should only be
> part of the orchestrator or whichever session is responding back to me directly. It does not
> need to be anywhere else."

He is right, and this is the same class as everything above: a signal delivered to a surface that
does not consume it. Correct scope is the session that talks to the operator — SessionStart
digest and/or dispatch time — not a per-edit hook. Fixing the scope also dissolves the open
timing residual (measured 71.3ms average against a nominal <50ms budget, on a machine loaded
enough that the *unmodified* code measured 45–65ms, so the number is untrustworthy rather than
known-bad).
