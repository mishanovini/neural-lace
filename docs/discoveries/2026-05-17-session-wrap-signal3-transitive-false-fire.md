---
title: session-wrap Signal 3 transitively false-fires on cross-session merges
date: 2026-05-17
type: process
status: decided
auto_applied: true
originating_context: dreamy-black-dd82c1 worktree-cleanup session; session-wrap.sh Stop hook re-fired ~15+ times on a stale Build-Doctrine roadmap that this session has no scope or honest basis to touch
decision_needed: Should session-wrap.sh Signal 3 (and the same `$touched` dependency in Signals 5/6) scope "plans touched this session" to the CURRENT session's own commits rather than any archive-rename in a global `git log --since="4 hours ago"` window?
predicted_downstream:
  - adapters/claude-code/scripts/session-wrap.sh
  - docs/backlog.md (HARNESS-GAP entry if accepted)
---

## What was discovered

`session-wrap.sh` (Stop-hook freshness gate, ADR 027/028 Layer 5)
computes `plans_touched_this_session()` as:

```
git log --since="4 hours ago" --pretty=format: --name-status
  | grep -E '^R[0-9]*\s+docs/plans/[^/]+\.md\s+docs/plans/archive/[^/]+\.md$'
```

This is a **global 4-hour wall-clock window over the whole repo**, not
the current session's own commits. Signal 3 then requires
`docs/build-doctrine-roadmap.md` to be < 2h fresh whenever that window
is non-empty.

Concrete false-fire (this session): a *different* session's harness-infra
work archived `session-end-protocol-enforcer.md` at commit `21ded0e`
(2026-05-17 11:25). This worktree-cleanup session later merged master
into the main checkout, pulling `21ded0e` into the 4h window. Signal 3
then blocked session end demanding the Build-Doctrine roadmap (last
touched 2026-05-06, an unrelated workstream) be refreshed. The
worktree-cleanup commits (`f09de3b`, `4a8fa7a`) archived **zero** plans —
confirmed via `git show --name-status`.

The gate re-fired ~15+ times. The `stop-hook-retry-guard` 3-strike
block→warn downgrade did **not** engage for `session-wrap.sh` (it may
not be wired through the retry-guard library). The only natural
resolution is the 4h window aging past `21ded0e` (~15:26 local) — i.e.
the session is blocked by time, not by any unresolved work.

## Why it matters

Any session that merges master while *any* plan (even an unrelated
harness-infra plan archived by a *different* session) sits in the global
4h window is forced to treat the Build-Doctrine roadmap as a Stop
precondition. The session has no legitimate way out:
- Faking roadmap mtime / writing spurious roadmap content = dishonest
  freshness (anti-vaporware ethos forbids).
- Editing the hook mid-session to escape = prohibited (git-discipline
  Rule 3).
- Bypassing = needs explicit per-chat user authorization (gate-respect
  Step 3) the agent may not have.
- The roadmap content is genuinely another workstream's responsibility.

Result: a correct, complete session is held hostage by a defective
transitive attribution until a wall-clock window expires, and the
agent is pushed toward either prohibited self-clearing actions or
prohibited idle-stalling.

## Options

A. Scope `plans_touched_this_session()` to the current session's own
   commits (e.g. commits since the session's start SHA, or
   `@{push}..HEAD`, or commits not reachable from `origin/master` at
   session start) instead of a global `--since="4 hours ago"` window.
   Tradeoff: needs a reliable "session start" anchor; merges still pull
   others' commits into HEAD, so anchor choice matters.
B. Restrict Signal 3 specifically to archived plans that are
   Build-Doctrine-tagged (e.g. plan header references a Build-Doctrine
   tranche), so unrelated harness-infra archivals don't demand a
   Build-Doctrine roadmap refresh. Tradeoff: couples the gate to a
   plan-tagging convention.
C. Wire `session-wrap.sh` through `stop-hook-retry-guard.sh` so an
   unresolvable identical-signature fire downgrades block→warn after 3
   retries (consistent with the other 8 blocking Stop hooks). Tradeoff:
   treats the symptom (loop) not the root cause (false attribution);
   best combined with A or B.
D. Add a per-session acknowledgment escape (mirroring
   `product-acceptance-gate.sh`'s waiver) so a session that legitimately
   has nothing to add to the roadmap can record a justification and
   proceed. Tradeoff: another escape-hatch to audit.

## Recommendation

**A + C.** A fixes the root cause (the attribution is wrong); C is the
safety net so a future unforeseen unresolvable Stop signal downgrades
instead of looping ~15+ times. B is attractive but adds a tagging
coupling; D is a workaround, not a fix. Reversible — single-script
change plus a one-line wiring; revert is one commit. Defer
implementation to a dedicated harness session (editing this Stop hook
from the session it is currently blocking is prohibited by
git-discipline Rule 3).

## Decision

**A + C adopted (auto-applied decision, 2026-06-10 pending-discoveries
triage); implementation deferred to a dedicated session as
HARNESS-GAP-50.** Re-verified against the 2026-06-10 repo: the defect is
still live — `plans_touched_this_session()` (session-wrap.sh:107) still
uses the global `git log --since="4 hours ago"` window, and session-wrap
is still not wired through `lib/stop-hook-retry-guard.sh`. The
recommendation's own analysis holds (A fixes the false attribution; C is
the loop-break safety net; B couples to a tagging convention; D is a
workaround). The decision itself is reversible (single-script change),
so it is taken here per discovery-protocol; the BUILD is a load-bearing
Stop-hook rework with extensive self-tests (>30 min) and lands via the
backlog entry, not this triage branch. Signals 5/6 share the `$touched`
dependency — the GAP-50 entry mandates fixing the class, not the
instance.

## Implementation log

- `docs/backlog.md` HARNESS-GAP-50 (added 2026-06-10) — carries the
  decided A+C remediation, anchor candidates for "session's own
  commits," and the Signals-5/6 class note. Implementation pending that
  entry's pickup; this discovery flips to `implemented` when GAP-50
  ships.
