# Evidence Log — status-event-ledger

## Task SE1

### Status

Handoff-complete/failed status-event emit at `adapters/claude-code/scripts/estate-merge.sh`'s
single merge chokepoint (`cmd_merge`), landed at **4a2ca134eb4bb2862d36f4529c359580affae73a**
(4a2ca13) on `wip/harness-hardening-2026-07-29`. Worktree build commit was 2c86b60; 4a2ca13 is
the patch-identical landed equivalent (verified: `git diff 2c86b60 4a2ca13 -- adapters/claude-code/scripts/estate-merge.sh adapters/claude-code/hooks/lib/progress-log-lib.sh adapters/claude-code/manifest.json` is empty). All file:line citations below are against 4a2ca13's own diff hunks.

`estate-merge.sh --self-test`: 52/0 → 69/0 on both `/bin/bash` 3.2.57 and
`/opt/homebrew/bin/bash` 5.3.15, absolute and relative path. Mutation-proven: the
`_em_emit_ledger_event` call at `estate-merge.sh:323` was disabled in place mid-build
(prefixed `: disabled_for_mutation_test`), which turned the static guard
(`estate-merge.sh:706`) plus 15 of the 16 new Scenario 21-23 assertions RED for the correct
reason (the ledger file never populated), then was restored byte-for-byte and reconfirmed
69/0 GREEN on both interpreters.

## Comprehension Articulation

### Spec meaning

Taxonomy row 4 ("handoff complete (builder commit landed)") asks for a **deterministic,
mechanism-emitted** status event recording that a builder's work landed at — or was refused
by — the estate's single merge chokepoint, never an agent narrating "I merged it" after the
fact. Concretely: `estate-merge.sh`'s `cmd_merge` already funnels every terminal outcome (10
distinct blocked/failed/success paths) through one function, `_em_log_merge`
(`estate-merge.sh:302-324`); the spec is satisfied by making THAT function itself emit a
ledger event on every call, carrying branch, target, the post-merge SHA, and machine, and
distinguishing success (`merge-completed`) from refusal/failure (`merge-failed`) honestly —
not just logging the happy path. The task description also named "the orchestrator's cherry-
pick path" as part of the trigger; per my read of the plan's own parenthetical ("T5's single
merge path IS the chokepoint") and the existing `estate-merge` manifest entry's own honest
disclosure that today only `close-worktree.sh` routes through this script, I built the
`estate-merge.sh` half only and named the cherry-pick half as a disclosed, out-of-scope
residual (see NOT-covered below) rather than inventing a new cherry-pick wrapper script the
dispatch never asked for.

### Edge cases covered

- **Successful fast-forward / no-ff / already-integrated merges emit `merge-completed`** with
  the post-merge target SHA, not an empty one: the outcome-to-type mapping is
  `estate-merge.sh:270` (`merged-ff|merged-noff|already-integrated) type="merge-completed"`),
  and Scenario 21 (`estate-merge.sh:1132-1163`) asserts the resulting JSONL row's `type`,
  `plan_slug` (the `--slug` label), `task_id` (`source -> target`), `sha` (matches the real
  fast-forwarded tip), `emitter`, `provenance`, and `machine` fields against a real sandboxed
  merge of two live git fixture repos.
- **Any blocked/refused/conflict outcome emits an honestly-empty-SHA `merge-failed`**: the
  `case` default arm at `estate-merge.sh:270` (`*) type="merge-failed"`) covers all 9 non-
  success outcomes uniformly since `_em_log_merge` is the ONE call site
  (`estate-merge.sh:323`) — the 10 individual outcome call sites
  (`estate-merge.sh:429,437,446,454,467,472,482,495,520,564`) only had to gain a trailing
  `"$main"` argument, never a duplicated emit. Scenario 22 (`estate-merge.sh:1165-1191`)
  proves this against a real `blocked-dirty` refusal: `"sha":""` and the summary names the
  outcome.
- **Repeated failed attempts are never silently collapsed into one row**: the `merge-failed`
  dedup_extra is `"${outcome}-$$-$(_em_now_ms)"` (`estate-merge.sh:284`), a per-attempt
  pid+timestamp token, versus `merge-completed`'s stable `dedup_extra="$outcome"`
  (`estate-merge.sh:279`) which lets a byte-identical replay of the SAME successful merge
  dedup via the natural key `plan_slug+task_id+sha`
  (`progress-log-lib.sh:427-431`). Scenario 23 (`estate-merge.sh:1193-1211`) runs the
  identical blocked-dirty merge twice as two separate OS processes and asserts 2 distinct
  `merge-failed` rows, not 1.
- **A missing/uninstalled `scripts/progress-log.sh` never blocks the merge itself**: the
  guard `[ -f "$pl_cli" ] || return 0` inside `_em_emit_ledger_event`
  (`estate-merge.sh:265-266`) fails open; Scenario 24 (`estate-merge.sh:1213-1230`) copies
  `estate-merge.sh` alone (no sibling `progress-log.sh`) into a scratch dir and asserts the
  merge still exits 0.
- **`estate-merge` is a registered, not-impersonatable emitter**: added to
  `_PL_KNOWN_EMITTERS` at `progress-log-lib.sh:167`, so `pl_emit`'s allowlist check stamps
  `"provenance":"known"` rather than `"unknown"` — asserted directly in Scenario 21's
  `provenance` check.
- **Empty `reason` (the common case — most calls to `_em_log_merge` pass no `--reason`)
  produces a clean summary, not a garbled trailing parenthetical**: the guard
  `[ -n "${reason:-}" ] && summary="${summary} (reason: ${reason})"` (`estate-merge.sh:275`)
  only appends the "(reason: ...)" suffix when non-empty. Scenario 22's `blocked-dirty` case
  (`estate-merge.sh:1165-1191`) is itself an empty-`--reason` call, and its own `grep -q
  'summary'` check (`estate-merge.sh:1187-1188`) only proves the substring is present, not
  the suffix's absence — so I independently re-ran that exact scenario by hand outside the
  suite and inspected the raw JSONL: `"summary":"estate-merge blocked-dirty: source ->
  target"`, with no `(reason: )` suffix, confirming the guard at `estate-merge.sh:275`
  behaves as claimed.

### Edge cases NOT covered

- **The orchestrator's own PARALLEL-mode cherry-pick.** Per the plan's own taxonomy-row-4
  RESIDUAL note (added in this same task) and `estate-merge.sh`'s pre-existing manifest
  entry ("NOT yet the estate's ONLY merge path"), a PARALLEL-mode orchestrator today performs
  a direct `git cherry-pick`, not a call into `cmd_merge` — that path stays uninstrumented.
  This is the single biggest named gap and was out of this task's dispatched scope (dispatched
  as "the handoff-complete emit at estate-merge.sh, the single merge chokepoint"), not silently
  dropped.
- **Push-failure is not folded into the ledger event's own type.** If a local merge succeeds
  but the subsequent push to a remote fails (`estate-merge.sh`'s push loop around
  `pushed_summary`), `_em_log_merge` is still called with a success `outcome`
  (`merged-ff`/`merged-noff`), so the ledger event still reads `merge-completed` — the event
  is honestly scoped to "this repo's local ref changed," not "this reached every remote."
  `pushed_summary` remains visible in `merges.log` but is not one of the ledger event's
  fields; not tested by a dedicated scenario here.
- **Cross-machine concurrent-write dedup was not independently re-verified for this caller.**
  `pl_emit`'s underlying mkdir-atomic lock (`progress-log-lib.sh`) is reused unchanged and its
  own general concurrency proof (`progress-log.sh`'s Scenario E, unaffected by this task,
  still 6/0) covers the mechanism; this task did not add an estate-merge-specific concurrent-
  writer scenario, since `_em_acquire_lock`'s own pre-existing merge-lock already serializes
  concurrent `estate-merge.sh` invocations on one machine ahead of the ledger emit ever firing.

### Assumptions

- **`scripts/progress-log.sh` is a sibling of `estate-merge.sh`** in the same directory, so
  `_em_progress_log_cli` (`estate-merge.sh:259-261`) can resolve it via `$SCRIPT_DIR`. If
  either script is ever relocated independently of the other, the emit silently no-ops
  (never blocks, per the guard above, but also never surfaces the drift) — an assumption the
  diff depends on but does not validate at runtime.
- **`HARNESS_SELFTEST=1`, already exported by `_em_self_test` for its own sandboxing, is
  sufficient to also sandbox `progress-log-lib.sh`'s state directory** when no explicit
  `PROGRESS_LOG_STATE_DIR` is set (relied on by Scenarios 1-20, which predate this task and
  set neither var yet stayed 0-real-state-pollution both before and after this change,
  confirmed via `grep -rl '"emitter":"estate-merge"' "$HOME/.claude/state/progress-logs"`
  returning nothing post-run).
- **The pid+timestamp `dedup_extra` token for `merge-failed` (`estate-merge.sh:284`) is
  unique per invocation.** `$$` is the OS-assigned PID of the `bash estate-merge.sh` child
  process, not caller-controlled, so two genuinely concurrent failed attempts always get
  distinct tokens; this assumption is not violated anywhere in the diff (each `_em_log_merge`
  call happens inside its own top-level script invocation, never forked internally).
