# Ask-rooted splice harness-review — diverse Opus panel (Task 7, 2nd half)

**Method:** Fable was cancelled (no longer subsidized; not worth regular API rate). Replaced by a
**diverse Opus review panel + adversarial verify** over the session-lifecycle hook splices
(`git diff f33e55b..origin/master` on the 13 splice files). 7 lenses ran in parallel — never-blocks,
never-flips, anti-noise/allowlist, dedup, builder-guard, injection, merge-attribution — and **every
finding was then attacked by an independent Opus skeptic** (default REFUTED) before counting. 15 agents.

**Why this over one deep pass (operator's design question):** diverse lenses + adversarial verify
catch failure classes a single reviewer structurally can't. This session's evidence: comprehension-
reviewer caught a model-vs-code mismatch, harness-reviewer caught a false-positive rate, end-user-
advocate caught a runtime UX clip, and this panel caught 3 session-degrading defects — no single pass
catches all. It is cheaper AND more robust than one expensive model. **Adopt as the standing deep-review
pattern.**

## Clean classes (verified, no defects)
- **never-flips (observe-only):** CLEAN. Every splice writes only derived state (progress-log JSONL,
  dispatch markers, append-only registry, AUTO-delimited operator-todo pointer). No checkbox flip, no
  authoritative Status write, no plan/registry-as-truth mutation. Check 16 WARNs to stderr only.
- **anti-noise + emitter-allowlist:** CLEAN. `pl_emit` stamps `provenance:unknown` for non-allowlisted
  emitters; literal (non-glob) list match, no wildcard/empty bypass. No gate/hook/pane identifier reaches
  any rendered narrative field (they live only in the emitter metadata column).
- **injection / path-traversal:** CLEAN. `_pl_sanitize_ask_id` (via `pl_path_for`, the only ask-id→path
  boundary) confines the value; no unsanitized attacker-influenced value reaches a path or shell.

## CONFIRMED findings (7; each live-reproduced in verify)

### Major
1. **never-blocks — `progress-log-lib.sh :: pl_classify_session` unbounded marker scan.** Dispatch-
   provenance markers are written per plan-rooted dispatch and **never pruned** (no rm/find-mtime/prune
   anywhere). `pl_classify_session` iterates the ENTIRE marker dir (~2-3 forks/marker via `_pl_marker_field`)
   on every SessionStart (`_ask_session_attach`) and first UserPromptSubmit (`_ask_capture_on_prompt`).
   Subshelled so non-fatal, but the **synchronous O(N) fork-heavy latency grows without bound** on the
   session hot path as the estate ages. Precedent: `session-start-digest.sh:1173` already BACKGROUNDS the
   heartbeat reap for this identical fork-per-file-over-growing-dir anti-pattern (measured ~11s). Fix:
   prune markers past a TTL / cap-to-newest-N on write, and/or scan only the N most-recent markers.
2. **dedup — `workstreams-emit.sh :: _emit_dispatch_provenance` (task_started) keys on parent session.**
   `task_started` natural key = plan_slug|task_id|session_id, but `session_id=$sid` = the DISPATCHING
   orchestrator's `CLAUDE_SESSION_ID`, invariant across all its dispatches. A within-session **re-dispatch
   of a failed task is DROPPED** (identical key). Violates the plan's audited superset rule (recurrence
   discriminator = child session; key uses parent). Self-tests hand-feed sess-A/sess-B the real caller
   never varies (false assurance). Fix: feed a genuinely per-dispatch discriminator (child session id /
   nonce) or add it to the key.
3. **builder-guard — `workstreams-emit.sh :: _emit_dispatch_provenance` records project-root cwd.** For a
   cross-repo `spawn_task` (documented estate workflow) the marker's `worktree_path` = the PROJECT ROOT
   (not the `.claude/worktrees/` child). Later an operator session at that repo root matches the ancestor
   predicate → classified `spawned` → its **opening ask is silently dropped** (`_ask_capture_on_prompt`
   skips register) AND grafted onto the unrelated dispatching ask (`_ask_session_attach`). Fix: don't pass
   the project-root cwd as `--worktree` (predicate (a) already catches the real child under
   `.claude/worktrees/`); or only honor a marker match whose `worktree_path` contains `/.claude/worktrees/`.

### Minor (latent)
4. **dedup — `plan-lifecycle.sh :: emit_plan_amended_progress_log_events` scope key hashes full post-scope,
   not the delta.** Returning the scope to a previously-seen exact state drops a genuine re-amendment. Fix:
   hash the pre→post delta and/or add a ts/sequence component.
5. **merge-attribution — `merge-scan-lib.sh :: _ms_plan_slugs_from_diff` evidence-dir `.md` mis-route.** The
   `docs/plans/*.md` case arm precedes `docs/plans/*-evidence/*` and bash `*` spans `/`, so
   `docs/plans/foo-evidence/summary.md` → slug `foo-evidence/summary` → unlinked.jsonl. Latent today
   (evidence dirs are .json-only). Fix: order the `-evidence/*` arm first / guard the `.md` arm.
6. **merge-attribution — `merge-scan-lib.sh` merge-commit blindness + false comment.** `git diff-tree …
   --root <sha>` emits NOTHING for a two-parent merge, so merge-unique plan touches (conflict resolution)
   are dropped, and the HONEST LIMITATION comment (~L100-109) is factually FALSE (claims first-parent files
   surface). Fix: add `-m` (existing awk dedups) or correct the comment.
7. **merge-attribution — `merge-scan-lib.sh :: _ms_commit_plan_slugs` unconditional token short-circuit.**
   A stray/typo'd `plan: <token>` line returns that slug without verifying it resolves, suppressing the
   reliable diff-touches-plan fallback → a real plan touch misroutes to unlinked.jsonl. Fix: fall through
   to `_ms_plan_slugs_from_diff` when no token slug resolves to an existing plan file.

## REFUTED (1)
- dedup — `close-plan.sh` plan_completed close_ts: refuted — no second emit lane exists, so the claimed
  replay cannot reproduce.

## Disposition
Majors 1-3 fixed in this pass (session-lifecycle blast radius). Minors 4-7 fixed where cheap/clear
(merge-scan arm ordering + token fallback + comment; scope-hash). Each fix gets a regression self-test.
