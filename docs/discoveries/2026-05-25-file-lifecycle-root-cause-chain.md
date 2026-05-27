---
title: File-lifecycle root-cause chain → Stop-loop, stranded deliverables, manual scripts
date: 2026-05-25
type: process
status: decided
auto_applied: false
originating_context: file-lifecycle-redesign design session (2026-05-25), Pattern 3 of 5 in the broader plan-lifecycle-redesign initiative. Misha authorized a Mode:design plan after a session looped 435× on a session-wrap staleness sentinel and after discovering Conv-Tree-populating scripts are untracked + the auto-extraction hook designed by nervous-lehmann (2026-05-20) was never built.
decision_needed: n/a — decided; design captured in docs/plans/file-lifecycle-redesign.md + docs/decisions/037-file-lifecycle-session-artifacts.md + docs/decisions/038-pending-items-marker-convention.md
predicted_downstream:
  - docs/plans/file-lifecycle-redesign.md
  - docs/decisions/037-file-lifecycle-session-artifacts.md
  - docs/decisions/038-pending-items-marker-convention.md
  - adapters/claude-code/scripts/session-wrap.sh
  - adapters/claude-code/hooks/docs-publish-on-stop.sh (new — roadmap R5)
  - adapters/claude-code/hooks/conversation-tree-extract-pending.sh (new — roadmap R4)
  - adapters/claude-code/rules/pending-items-marker-convention.md (new — roadmap R3)
  - neural-lace/conversation-tree-ui/scripts/backfill-from-sessions.js (track — roadmap R2)
---

## What was discovered

Four recurring failures in this harness share one structural root cause:
**session-generated files have no codified lifecycle — no policy for where they
live, when a write counts as durable, or how a worktree-write propagates to the
main checkout.** Each failure is a different face of that single gap.

### RC1 — `session-wrap.sh refresh` produces a `1666666 min stale` sentinel → Stop-hook loop

`cmd_refresh` (adapters/claude-code/scripts/session-wrap.sh ~line 259) only
edits an *existing* `SCRATCHPAD.md`:

```bash
if [ -f "$scratchpad" ]; then
  ... touch the timestamp marker ...
fi
cmd_verify "$repo" "$wt_repo"   # runs regardless
```

When `SCRATCHPAD.md` is absent, the `if` is a silent no-op and `cmd_verify`
Signal 1 runs `mtime_seconds_ago` on the missing file, which returns the
`99999999` sentinel → `99999999 / 60 = 1666666` "min stale". That fails the
30-minute freshness check, `cmd_refresh` returns exit 2, the Stop hook re-prompts,
and — because refresh *never creates the file it checks for* — the next attempt
produces the identical sentinel. The loop is unbreakable by retry. One session
today looped **435×**. This is distinct from the
[2026-05-17 Signal-3 transitive false-fire](2026-05-17-session-wrap-signal3-transitive-false-fire.md)
(that is wrong-*attribution* — which commits count; this is the missing-*file*
failure — refresh can't clear a signal for a file it won't create).

### RC2 — worktree-written durable docs never reach the main checkout → stranded deliverables

The orchestrator pattern runs build/analysis work in short-lived git worktrees
(`.claude/worktrees/<id>/`). When a session in a worktree writes a durable
deliverable — `docs/reviews/2026-05-20-conv-tree-session-harness-gaps.md`,
`docs/discoveries/…` — that file lives only in the worktree's working tree. It
reaches the main checkout ONLY if the worktree branch is committed AND merged AND
the main checkout pulls (git-discipline.md Rule 2, which is Pattern-only/
unenforced). When the worktree branch is discarded without a PR — the common case
for analysis/demo sessions — the deliverable is stranded. The canonical example:
the entire nervous-lehmann (2026-05-20) harness-gaps review, including the Gap-5
design for the auto-extraction hook (RC4), sat unread in
`.claude/worktrees/nervous-lehmann-35212e/docs/reviews/` until this session
harvested it by absolute path.

### RC3 — Conv-Tree-populating scripts are untracked → the only thing keeping the tree populated has no history

`neural-lace/conversation-tree-ui/scripts/add-pending-items.js` and
`backfill-from-sessions.js` are `git status: ??` (untracked). They are currently
the ONLY mechanism populating the Conversation-Tree GUI with today's branches +
pending items — yet they exist outside version control, can be wiped by a
`git clean`, and have no provenance. They split into two different problems:
- `backfill-from-sessions.js` is a genuine, reusable tool (reads `~/.claude/
  projects/**` JSONLs, replays through the frozen `appendEvent` facade). It belongs
  tracked.
- `add-pending-items.js` is a dated throwaway *instance* — it hardcodes today's
  9 decisions / 6 actions / 5 questions and node ids like `today-20260520`.
  Tracking it as-is would commit machine-specific, dated content (a harness-hygiene
  violation). Its *intent* — "get pending items from chat into the tree" — is
  exactly what RC4 mechanizes. It should be retired in favor of the mechanism, not
  tracked.

### RC4 — no auto-extraction hook for `**Questions / Action items / Decisions for Misha**` → pending items live only in chat

There is no hook (on this machine or in the doctrine) that scans assistant output
for the pending-item marker convention and flows the items into the Conv Tree.
`conversation-tree-read.sh` runs the OPPOSITE direction (GUI→prompt);
`conversation-tree-emit.sh` emits lifecycle events on spawn/stop. Authoring items
from assistant text is a third pattern neither covers. nervous-lehmann designed
the fix (Gap 5, 2026-05-20) but it was never built — and that design itself was
stranded by RC2. **Update:** the design predates the 2026-05-21 `--emit-item` /
`--emit-branch` / `--emit-details` / `--resolve-item` modes added to
`conversation-tree-emit.sh`; the extraction hook can pipe to those existing modes
instead of reimplementing `appendEvent`, which materially shrinks RC4's scope.

## Why it matters — the causal chain

```
ROOT: session-generated files have NO codified lifecycle.
      (No durable/ephemeral classification; no worktree→main propagation
       mechanism; no policy for "tool vs instance" or "where does this live".)
   │
   ├─► EPHEMERAL state (SCRATCHPAD) has no create-on-missing contract.
   │   refresh edits-if-exists, never creates → missing file reads as a 31-year
   │   stale sentinel → Stop loop that retry cannot break.            (RC1)
   │
   ├─► DURABLE deliverables written in a worktree have no propagation path to
   │   main except "branch merges + main pulls" (unenforced). Discarded-branch
   │   sessions strand the deliverable silently.                      (RC2)
   │
   ├─► The scripts that keep the Conv Tree populated live OUTSIDE the lifecycle:
   │   untracked, no history, mixing a real tool with a dated instance. (RC3)
   │
   └─► Pending items surfaced in chat never enter durable structured storage
       (the tree) automatically — they require a manual script run, which is
       why RC3's instance script exists at all.                       (RC4)
```

RC3 and RC4 are causally linked: the manual `add-pending-items.js` exists
*because* RC4's mechanism is missing. Build RC4 and RC3's instance script
disappears. RC1 and RC2 are the ephemeral and durable faces of the same
missing-lifecycle root.

## Options (considered)

A. **Palliative — surface the loop + nudge.** Make `session-wrap` skip Signal 1
   when SCRATCHPAD is missing (treat as non-applicable, like the non-git case);
   add a SessionStart surfacer for stranded worktree docs; nudge the human to
   track the scripts. REJECTED: skipping the signal hides the gap rather than
   producing the artifact doctrine wants; nudging is advisory. Symptom-masking.
B. **Transparent path-redirect for worktree writes.** A PreToolUse hook that
   rewrites `tool_input.file_path` so `docs/reviews/X.md` in a worktree lands in
   the main checkout. REJECTED as infeasible: Claude Code PreToolUse hooks return
   allow/deny/context — they CANNOT mutate `tool_input`. A symlink variant breaks
   git worktree isolation + the PR flow. This is an important honest finding: the
   "path resolver" framing in the task brief is not mechanically buildable; RC2
   must be solved at session-end (publish), not at write-time (redirect).
C. **Mechanical curative redesign.** Codify a file-lifecycle policy (ephemeral vs
   durable; tool vs instance; worktree→main propagation) and back each class with
   a mechanism: (RC1) `cmd_refresh` create-on-missing-from-template — produce the
   artifact, don't skip the check; (RC2) a publish-on-stop hook that copies
   worktree-written durable docs into the main checkout copy-if-absent + a staging
   ledger backstop; (RC3) track the tool, retire the instance; (RC4) build the
   auto-extraction Stop hook against a narrow marker-convention contract, piping to
   the existing `--emit-item` modes. SELECTED.

## Recommendation

C — the mechanical curative redesign. Each failure is prevented by a mechanism
keyed to the file's lifecycle class, not by advisory discipline. RC1 is the
cheapest and stops active bleeding (the 435× loop) — it ships first. Detailed in
`docs/decisions/037-file-lifecycle-session-artifacts.md` (policy + RC1/RC2/RC3),
`docs/decisions/038-pending-items-marker-convention.md` (RC4 marker contract +
extraction), and the R1–R5 roadmap in `docs/plans/file-lifecycle-redesign.md`.

## Decision

C selected (2026-05-25, Misha-authorized design session). NOT auto-applied: this
is a design producing a Mode:design plan + 2 ADRs + roadmap. The reversible parts
(RC1 one-function fix, RC3 tracking the tool) are low-blast-radius; the
irreversible/higher-blast parts (RC2 publish hook writing into the operator's main
working tree; RC4 new Stop hook + marker rule) are gated on Misha's explicit go
and on the open Decisions-for-Misha in the plan. Coordinated with the parallel
plan-lifecycle-redesign session (ADR 036) — that session owns plan *closure*
machinery; this session owns file *lifecycle*. The only shared surface is
`session-wrap.sh`; integration handled at landing time, not now.

## Implementation log

- docs/plans/file-lifecycle-redesign.md — Mode:design plan authored (2026-05-25)
- docs/decisions/037-file-lifecycle-session-artifacts.md — ADR authored (2026-05-25)
- docs/decisions/038-pending-items-marker-convention.md — ADR authored (2026-05-25)
- Implementation hooks/scripts: NOT YET BUILT — roadmap R1–R5 in the plan, gated
  on Misha's authorization + the open decisions.
