# Harness improvement: orphaned-worktree-work guard (stranded builder work)

**Status:** BUILT + HARNESS-REVIEWED (REFORMULATE) → REFORMULATED (round 1, 39/39) →
**harness-review round-2 finding fixed (43/43), pending re-verification** — not yet merged to
master ("landed" per the constitution means merged, and this is not that yet). Origin: operator
directive 2026-07-13 — "how do we resolve this when you don't remember? … do we need a hook for
every failure mode?" The answer is one cause-agnostic detector, not N hooks. This doc is the
durable record so neither reformulation round is lost.

## The invariant (the design's core, which the review endorsed)
Regardless of HOW a builder stops (clean-end-without-commit, background-standing-by, crash,
SIGKILL/OOM, reboot, API-terminal death), the stranded state is one observable thing: **an agent
worktree holds dirty OR unintegrated content AND has no live owner.** One detector on that state
is cause-agnostic — it catches failure modes not yet imagined. Generalization review: **PASS
("exemplary class-not-instance design").**

**Round-2 correction to this invariant's own implementation (not the invariant itself):** the
round-1 build did not actually REACH this invariant for every worktree the invariant's own
wording covers. A crashed/SIGKILLed/OOM-killed dispatched agent is exactly the "crash, SIGKILL/OOM"
case the invariant names — but the isolation/dispatch mechanism `git worktree lock`s an agent's
worktree for the full dispatch duration and only unlocks on clean completion, so that exact case
leaves the worktree `locked` forever. `worktree-hygiene-sweep.sh`'s own PRE-EXISTING (pre-dating
this whole reformulation) `*,locked,*` structural-skip returned before the liveness split ever ran,
for ANY locked worktree — so the crash/SIGKILL/OOM case was silently unreachable, invariant text
notwithstanding, until the round-2 fix below. The invariant was always the right target; the
round-1 implementation just didn't fully hit it for this one topology.

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

## Reformulation path (the fix) — BUILT
The liveness signal must catch a live subagent builder WITHOUT depending on a subagent heartbeat:
1. **(Built) Subagent-transcript-mtime liveness.** A worktree is named `agent-<id>`. The REAL
   layout (verified empirically against a live session, NOT assumed — the original note above
   guessed wrong):
   `~/.claude/projects/<project-slug>/<session-id>/subagents/agent-<id>.jsonl` (+ a sidecar
   `agent-<id>.meta.json` carrying worktreePath/worktreeBranch/agentType, not needed for the join
   since the worktree's own basename already equals the transcript's filename stem exactly).
   `worktree-hygiene-sweep.sh`'s `_live_owner` now checks, for any `agent-*`-named worktree,
   whether that exact transcript's mtime is within `AGENT_TX_FRESH_MIN` (default = OBS_STALE_MIN,
   30 min) — checked FIRST, before the heartbeat/claim join, since a dispatched subagent has no
   heartbeat to find. A one-time bounded `find` (`_build_agent_tx_cache`, cached per sweep-script
   process — never a per-worktree tree-walk) locates every `agent-*.jsonl` under the transcripts
   root; `_agent_tx_fresh_min` looks up the cache, never re-walking the tree. The heartbeat/claim
   join is unchanged and remains the ONLY signal for non-agent (named) worktrees. Self-test: 39/39
   (34 original + 5 new REFORMULATION assertions covering fresh-agent-transcript / stale-agent-
   transcript / non-agent-worktree-unaffected). manifest.json's stranded-worktree-work
   fp_expectation/honesty_rationale updated with the new design + residual (an agent silent past
   the freshness window while genuinely still working could false-fire — accepted for a WARN-
   only, never-auto-pruning surfacer).
2. **(Durable P2 — the design's own named retirement condition, unchanged) Dispatch-time lease.**
   The builder-dispatch path writes an authoritative per-worktree lease (worktree path + owning
   agent id + liveness pointer + expiry); a SessionEnd/agent-stop unclaim removes it. The detector
   then reads the lease instead of inferring liveness from either signal above. Cleaner, but
   touches the spawn path — still not built.

## Round 2 (harness-reviewer re-pass finding) — FIXED
The re-pass confirmed round 1's fix genuinely closed the cry-wolf FP (39/39 re-run independently by
the reviewer; transcript layout re-confirmed against its own live agent; the bounded `find` measured
at 0.385s) — but found a NEW Critical the round-1 golden_scenario rewrite itself exposed:

1. **CRITICAL — locked worktrees never reached the liveness split.** Proven on the reviewing
   machine: three dead-pid locked worktrees existed (pids confirmed dead via `tasklist`, since
   `kill -0` is unreliable on that MSYS setup) whose worktrees never reached `_live_owner` at all —
   `classify_worktree`'s pre-existing `*,locked,*` structural-skip (predates this whole
   reformulation) returned before the liveness split ever ran, for ANY locked worktree. Root cause:
   the dispatch/isolation mechanism locks an agent's worktree for the full dispatch duration and
   unlocks only on clean completion, so a crashed/SIGKILLed/OOM-killed agent's worktree stays
   `locked` FOREVER — exactly the golden_scenario's own "crashes, is SIGKILLed/OOM-killed" claim,
   which was therefore unreachable for this (very real) topology. **Fix:** `classify_worktree` no
   longer lets `locked` preempt an `agent-*`-named worktree — it falls through to the normal
   dirty/unique computation and the liveness split (transcript-mtime decides, exactly as unlocked);
   `_live_owner` takes a third `is_locked` argument, reporting the distinct verdict
   `agent-crashed-locked` for stale-and-locked (vs. plain `agent-transcript-stale` for
   stale-but-unlocked) so salvage text can name the extra step a locked row needs. Non-agent locked
   worktrees are UNCHANGED (still structural-skip — presumed intentionally persistent). A locked
   worktree is still NEVER SAFE-PRUNE (excluded explicitly, and `git worktree remove` itself refuses
   on locked regardless).
2. **MAJOR — the round-1 (b) stale-scenario fixture was UNLOCKED**, a topology real crashed agents
   never have. Added (d) a LOCKED + stale-transcript + content fixture asserting the
   `agent-crashed-locked` verdict, and (e) the inverse (LOCKED + FRESH transcript stays live,
   proving lock status alone never causes a false ORPHANED).
3. **MINOR — `find -maxdepth 6`'s comment claimed slack it didn't have.** Measured: the
   Workflow-dispatch transcript variant (`.../subagents/workflows/wf_<id>/agent-<id>.jsonl`) sits at
   EXACTLY depth 6 — zero margin. Bumped to `-maxdepth 7` (still sub-second) and corrected the
   comment to state the measured depth.
4. **Reconciled every coverage phrase** (manifest.json's `golden_scenario`/`fp_expectation` and this
   doc's own invariant section above) with what the code now actually reaches — the crash/SIGKILL/
   OOM claim is true as of this fix, not before it.

Verified: `worktree-hygiene-sweep.sh --self-test` → **43/43** (round-1's 39 + 4 new: (d) 3
assertions, (e) 1 assertion). `harness-doctor.sh`'s `oww-agent-live-green` fixture re-confirmed.

## Next action
A harness-reviewer re-pass on this round-2 fix is required before this is considered landed (this
doc's Status line tracks that explicitly — "landed" means merged to master with a SHA, which has
not happened yet). Once it clears review: land via merge to master, then install to `~/.claude`
(harness change is durable only once merged). Tracked as a follow-up to the ask-rooted-workstreams-p1
build (not a blocker for it).
