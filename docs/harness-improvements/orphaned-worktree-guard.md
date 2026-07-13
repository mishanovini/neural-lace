# Harness improvement: orphaned-worktree-work guard (stranded builder work)

**Status:** BUILT + HARNESS-REVIEWED → **REFORMULATE** (not landed; a headline false-positive
must be fixed first). Origin: operator directive 2026-07-13 — "how do we resolve this when you
don't remember? … do we need a hook for every failure mode?" The answer is one cause-agnostic
detector, not N hooks. This doc is the durable record so the reformulation isn't lost.

## The invariant (the design's core, which the review endorsed)
Regardless of HOW a builder stops (clean-end-without-commit, background-standing-by, crash,
SIGKILL/OOM, reboot, API-terminal death), the stranded state is one observable thing: **an agent
worktree holds dirty OR unintegrated content AND has no live owner.** One detector on that state
is cause-agnostic — it catches failure modes not yet imagined. Generalization review: **PASS
("exemplary class-not-instance design").**

## What was built (WIP — not on master)
Branch `worktree-wf_d88db003-879-5`, commit **`a4b6876`** (in shared .git; recover with
`git cherry-pick a4b6876` or `git show a4b6876`). 4 files, +826/-7, self-test **34/34**:
- `adapters/claude-code/scripts/worktree-hygiene-sweep.sh` — THE SHARED DETECTOR (extended, not
  duplicated: it already computed per-worktree dirty count + `git cherry` unintegrated-patch
  count). Added a `_live_owner` liveness join + `--stranded [--porcelain]` mode (SILENT unless ≥1
  orphaned). Already-merged exclusion via `git cherry -` (patch-id) + `merge-base --is-ancestor`.
- `session-start-digest.sh` — folds one `[stranded-work] …` line into the digest when non-empty
  (reuses the existing digest aggregator; NO parallel hook).
- `harness-doctor.sh` — `check_orphaned_worktree_work` WARN-only (not RED).
- `manifest.json` — registers the sweep + check with the §10 evidence bar (golden scenario / FP
  expectation / retirement condition).
- Correctly did NOT bolt onto `broadcast-active-session.sh` (that hook is cross-computer, keyed by
  hostname; it never inspects local per-worktree state — wrong host, per the Understand phase).

## The headline defect (why REFORMULATE) — PROVEN
The liveness join relies on **session heartbeats**, but **dispatched `plan-phase-builder` subagents
(isolation:worktree) do NOT write their own heartbeat file** — only the top-level session's
heartbeat writer runs (proven at `harness-doctor.sh:1033-1040`, a prior verifier-round fix). So an
**actively-running builder's dirty worktree would be classified "stranded"** and surfaced on every
parallel-build day. That is the cry-wolf failure: a detector that false-fires on live work trains
the reader to ignore it — recreating the very "a human must notice" problem it was meant to remove,
one level up. The review rightly blocks landing on this.

## Reformulation path (the fix)
The liveness signal must catch a live subagent builder WITHOUT depending on a subagent heartbeat:
1. **(Recommended interim) Subagent-transcript-mtime liveness.** A worktree is named
   `agent-<id>`; the harness writes that agent's transcript to `<session>/tasks/<id>.output` and
   updates its mtime as the agent works. Map `agent-<id>` → the transcript (search session
   `tasks/` dirs for `<id>.output`) → fresh mtime (within OBS_STALE_MIN) ⇒ LIVE-OWNED. No subagent
   heartbeat, no dispatch-path change. This is the direct, already-written liveness signal.
2. **(Durable P2 — the design's own named retirement condition) Dispatch-time lease.** The
   builder-dispatch path writes an authoritative per-worktree lease (worktree path + owning agent
   id + liveness pointer + expiry); a SessionEnd/agent-stop unclaim removes it. The detector then
   reads the lease instead of inferring liveness. Cleaner, but touches the spawn path.

Until reformulated + re-reviewed, DO NOT land. WARN-only + digest-line means the blast radius of
the FP is "noise," not "blocks work" — but noise is precisely what erodes the signal, so it still
must be fixed before landing.

## Next action
Reformulate with signal (1), re-run the harness-reviewer (must clear the FP finding), then land via
install to `~/.claude` (harness change is durable only once merged to master). Tracked as a
follow-up to the ask-rooted-workstreams-p1 build (not a blocker for it).
