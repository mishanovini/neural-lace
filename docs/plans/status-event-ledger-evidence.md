# Evidence Log — status-event-ledger

## Task SE1

### Status

Handoff-complete/failed status-event emit at `adapters/claude-code/scripts/estate-merge.sh`'s
single merge chokepoint (`cmd_merge`). Original build landed at
**4a2ca134eb4bb2862d36f4529c359580affae73a** (4a2ca13) on
`wip/harness-hardening-2026-07-29`; this entry now also covers a same-day REFORMULATE round
(harness-reviewer, findings F1-F7) fixing the delta in the current worktree, not yet landed
under its own SHA at the time of this writing. All file:line citations below are against the
CURRENT worktree state (verified byte-identical against 4a2ca13 for every file untouched by
the REFORMULATE round; the REFORMULATE diff itself is the worktree's own uncommitted/committed
delta on top of 4a2ca13).

`estate-merge.sh --self-test`: 52/0 (pre-SE1) → 69/0 (original SE1 build) → **82/0** (post-
REFORMULATE) on both `/bin/bash` 3.2.57 and `/opt/homebrew/bin/bash` 5.3.15, absolute and
relative path. Two independent mutation-proofs from the REFORMULATE round (in addition to the
original build's own, described in the git history for 4a2ca13):
- F1: the lock-busy path's `_em_log_merge "blocked-lock-busy" ...` call
  (`estate-merge.sh:452`) was disabled in place (`: mutation_test_disabled _em_log_merge ...`),
  turning exactly the 3 new Scenario 12 assertions RED for the correct reason (no merges.log
  line, no ledger row), then restored byte-for-byte, reconfirmed 82/0.
- F7: the acknowledge path's `_em_log_merge "acknowledged" ...` call (`estate-merge.sh:767`)
  was disabled the same way, turning exactly 3 of Scenario 25's assertions RED for the correct
  reason, then restored byte-for-byte, reconfirmed 82/0.

REFORMULATE fixes applied (F1-F7):
- **F1** — the lock-busy refusal (`estate-merge.sh:444-453`) previously `return`ed before
  `_em_log_merge` was ever called — the ONE terminal `cmd_merge` outcome with no merges.log
  line and no ledger row. Now logs `blocked-lock-busy` (`estate-merge.sh:452`); Scenario 12
  extended with 3 new assertions (`estate-merge.sh:1048-1075`).
- **F2** — renamed `merge-completed`/`merge-failed` → `merge_completed`/`merge_failed`
  everywhere (progress-log-lib.sh, estate-merge.sh, manifest.json, both plan files), matching
  every other progress-log-lib.sh type's underscore convention (`task_done`, `plan_completed`,
  etc. — the hyphenated form was the one inconsistent type name).
- **F3** — the per-event-type dedup-key table was previously accurate in only ONE of its three
  documented locations (`progress-log-lib.sh`'s own header). Synced into
  `docs/runbooks/ask-workstreams.md`'s table and
  `adapters/claude-code/schemas/progress-log-event.schema.json`'s `type` field description —
  backfilling T9's own `plan_outcome_recorded`/`plan_reopened` rows too (the same sync gap
  pre-existed there since T9, unrelated to SE1, caught in passing while fixing SE1's own rows).
- **F4** — softened the self-test's static-guard comment (`estate-merge.sh:791-806`) from an
  unqualified "mutation-resistant" claim to an honest, scoped one (a syntactic check that
  catches whole-line deletion, not a semantic proof — see Edge cases covered below).
- **F5** — `merge_completed`'s `dedup_extra` was previously set to `"$outcome"`
  (a value `_pl_natural_key`'s `merge_completed` case never reads — the key is
  `plan_slug+task_id+sha`). Now left empty (`estate-merge.sh:301-312`) so the code never
  implies a dedup role that doesn't exist.
- **F6** — already resolved by the earlier Comprehension Articulation commit; no action here.
- **F7** — a new `--acknowledge <sha> --reason <text> [--into <target>]` subcommand
  (`estate-merge.sh:730-770`, wired at the dispatch table and documented in both `--help`'s
  usage summary and its own options block) resolves a legitimate out-of-band merge (one that
  bypassed the lock) from a permanent `--check` RED finding to CLEAN. `--reason` is REQUIRED.
  The `--check` RED finding itself now names the exact remediation command
  (`estate-merge.sh:698`). New Scenarios 25 (`estate-merge.sh:1345-1383`, the RED→CLEAN
  resolution + ledger emission) and 26 (`estate-merge.sh:1385-1400`, the two refusal paths).

## Comprehension Articulation

### Spec meaning

Taxonomy row 4 ("handoff complete (builder commit landed)") asks for a **deterministic,
mechanism-emitted** status event recording that a builder's work landed at — or was refused
by — the estate's single merge chokepoint, never an agent narrating "I merged it" after the
fact. Concretely: `estate-merge.sh`'s `cmd_merge` funnels every terminal outcome through one
function, `_em_log_merge` (`estate-merge.sh:329-352`); the spec is satisfied by making THAT
function itself emit a ledger event on every call, carrying branch, target, the post-merge SHA,
and machine, and distinguishing success (`merge_completed`) from refusal/failure
(`merge_failed`) honestly — not just logging the happy path. The REFORMULATE round sharpened
this further: F1 closed the one outcome (lock-busy) that was calling `return` BEFORE
`_em_log_merge` at all, so "every terminal outcome" is now literally true rather than "every
terminal outcome except one"; F7 extends the same honest-recording principle to merges that
happen OUTSIDE this script entirely — an out-of-band merge either stays a permanent RED
finding, or gets an explicit, reasoned, ledger-recorded acknowledgment, never a silent
one-time edit to merges.log. The task description also named "the orchestrator's cherry-pick
path" as part of the trigger; per my read of the plan's own parenthetical ("T5's single merge
path IS the chokepoint") and the existing `estate-merge` manifest entry's own honest disclosure
that today only `close-worktree.sh` routes through this script, I built the `estate-merge.sh`
half only and named the cherry-pick half as a disclosed, out-of-scope residual (see NOT-covered
below) rather than inventing a new cherry-pick wrapper script neither the original dispatch nor
the REFORMULATE findings asked for.

### Edge cases covered

- **Successful fast-forward / no-ff / already-integrated / acknowledged merges emit
  `merge_completed`** with the post-merge (or acknowledged) SHA, not an empty one: the
  outcome-to-type mapping is `estate-merge.sh:294`
  (`merged-ff|merged-noff|already-integrated|acknowledged) type="merge_completed"`), and
  Scenario 21 (`estate-merge.sh:1244-1275`) asserts the resulting JSONL row's `type`,
  `plan_slug`, `task_id`, `sha`, `emitter`, `provenance`, and `machine` fields against a real
  sandboxed merge of two live git fixture repos.
- **Any blocked/refused/conflict outcome (including the lock-busy refusal, F1) emits an
  honestly-empty-SHA `merge_failed`**: the `case` default arm at `estate-merge.sh:295`
  (`*) type="merge_failed"`) covers every non-success outcome uniformly since `_em_log_merge`
  is the ONE call site (`estate-merge.sh:350`) — the 11 individual outcome call sites
  (`estate-merge.sh:452,462,470,479,487,500,505,515,528,553,597`) each just pass their own
  outcome string plus `"$main"`, never a duplicated emit. Scenario 22
  (`estate-merge.sh:1277-1303`) proves this against a real `blocked-dirty` refusal.
- **The lock-busy refusal (F1) is no longer the one silent outcome.** Before this round,
  `cmd_merge`'s lock-acquisition failure (`estate-merge.sh:444-448`) returned exit 2 without
  ever calling `_em_log_merge` — the only terminal path with no merges.log line and no ledger
  row. Now instrumented at `estate-merge.sh:452`; Scenario 12
  (`estate-merge.sh:1048-1075`) asserts both the `merges.log` `outcome=blocked-lock-busy` line
  and a `merge_failed` ledger row with a summary naming the outcome.
- **Repeated failed attempts are never silently collapsed into one row**: the `merge_failed`
  dedup_extra is `"${outcome}-$$-$(_em_now_ms)"` (`estate-merge.sh:311`), a per-attempt
  pid+timestamp token; `merge_completed` deliberately gets an EMPTY dedup_extra (F5,
  `estate-merge.sh:301-312`) since its own natural key (`plan_slug+task_id+sha`,
  `progress-log-lib.sh:427-431`) never reads it — passing a non-empty value there would
  dishonestly imply participation in a formula that ignores it. Scenario 23
  (`estate-merge.sh:1305-1323`) runs the identical blocked-dirty merge twice as two separate OS
  processes and asserts 2 distinct `merge_failed` rows, not 1.
- **A missing/uninstalled `scripts/progress-log.sh` never blocks the merge itself**: the guard
  `[ -f "$pl_cli" ] || return 0` inside `_em_emit_ledger_event` (`estate-merge.sh:289-290`)
  fails open; Scenario 24 (`estate-merge.sh:1325-1343`) copies `estate-merge.sh` alone (no
  sibling `progress-log.sh`) into a scratch dir and asserts the merge still exits 0.
- **`estate-merge` is a registered, not-impersonatable emitter**: added to
  `_PL_KNOWN_EMITTERS` at `progress-log-lib.sh:167`, so `pl_emit`'s allowlist check stamps
  `"provenance":"known"` — asserted directly in Scenario 21's `provenance` check.
- **Empty `reason` produces a clean summary, not a garbled trailing parenthetical**: the guard
  `[ -n "${reason:-}" ] && summary="${summary} (reason: ${reason})"` (`estate-merge.sh:299`)
  only appends the suffix when non-empty. Scenario 22's `blocked-dirty` case is itself an
  empty-`--reason` call; its own `grep -q 'summary'` check only proves the substring is
  present, not the suffix's absence, so I independently re-ran that exact scenario by hand
  outside the suite and inspected the raw JSONL:
  `"summary":"estate-merge blocked-dirty: source -> target"`, no `(reason: )` suffix.
- **`--acknowledge` resolves a permanent `--check` RED bypass finding to CLEAN (F7)**: the RED
  finding message itself (`estate-merge.sh:698`) names the exact remediation command; Scenario
  25 (`estate-merge.sh:1345-1383`) proves the full loop — hand-merge a bypass, confirm RED
  (exit 4), run `--acknowledge <sha> --reason <text> --into target`, confirm exit 0, confirm
  `merges.log` gets `outcome=acknowledged` for the exact sha (`estate-merge.sh:767`), confirm
  `--check` on the SAME sha now returns CLEAN (exit 0), and confirm a `merge_completed` ledger
  row landed (acknowledged is a completed-outcome per the F7 case-arm addition at
  `estate-merge.sh:294`, since an acknowledged merge genuinely landed — it is not a failure).
- **`--acknowledge` refuses cleanly, never silently, on a missing `--reason` or an
  unresolvable `<sha>`** (F7): `estate-merge.sh:748-749` requires both explicitly, with a
  message naming which is missing; Scenario 26 (`estate-merge.sh:1385-1400`) asserts exit 2 for
  each case and confirms a refused call writes NOTHING to `merges.log` (no partial/garbled
  acknowledgment record).
- **The static self-test guard's real (narrow) guarantee, honestly restated (F4)**: the
  comment at `estate-merge.sh:791-806` no longer claims unqualified "mutation-resistant" —
  it now states the guard catches ONLY whole-line-deletion-class regressions, citing the
  build-time discovery that an earlier, unanchored version of the same pattern stayed green
  even when the call was disabled in place. The functional Scenarios 21-26 remain the
  load-bearing proof.

### Edge cases NOT covered

- **The orchestrator's own PARALLEL-mode cherry-pick.** Per the plan's own taxonomy-row-4
  RESIDUAL note and `estate-merge.sh`'s pre-existing manifest entry ("NOT yet the estate's
  ONLY merge path"), a PARALLEL-mode orchestrator today performs a direct `git cherry-pick`,
  not a call into `cmd_merge` — that path stays uninstrumented. Still the single biggest named
  gap; still out of this task's dispatched scope.
- **`--acknowledge` does not verify the acknowledged `<sha>` is actually a MERGE commit**, only
  that it resolves to SOME commit (`estate-merge.sh:756-759`, a plain `git rev-parse --verify`).
  An operator could acknowledge an arbitrary non-merge commit; the command trusts the caller's
  judgment here (the same trust model as the `--reason` field itself — a human is asserting
  this is legitimate) rather than re-deriving what `--check`'s own `--merges` filter would
  accept. Not tested by a dedicated scenario.
- **`--acknowledge`'s `source_branch` is always empty/unknown** (`estate-merge.sh:767` passes
  `""` as the third argument) — an out-of-band merge's origin branch is not knowable in
  general from the sha alone, so the resulting `task_id` reads `" -> <target>"` rather than
  `"<real-source> -> <target>"`. Honest gap, not tested with an assertion on the exact `task_id`
  string in Scenario 25 (only `type`/`sha` are asserted there).
- **Push-failure is not folded into the ledger event's own type.** A local merge succeeding but
  the subsequent push failing still reads `merge_completed` — the event is honestly scoped to
  "this repo's local ref changed," not "this reached every remote." `pushed_summary` stays
  visible in `merges.log` only.
- **Cross-machine concurrent-write dedup was not independently re-verified for this caller.**
  `pl_emit`'s mkdir-atomic lock is reused unchanged; its own general concurrency proof
  (`progress-log.sh`'s Scenario E, unaffected by this task, still 6/0) covers the mechanism.

### Assumptions

- **`scripts/progress-log.sh` is a sibling of `estate-merge.sh`** in the same directory, so
  `_em_progress_log_cli` (`estate-merge.sh:283-285`) can resolve it via `$SCRIPT_DIR`. A
  relocation of either script independently of the other silently no-ops the emit (never
  blocks, but never surfaces the drift either).
- **`HARNESS_SELFTEST=1`, already exported by `_em_self_test`, is sufficient to also sandbox
  `progress-log-lib.sh`'s state directory** when no explicit `PROGRESS_LOG_STATE_DIR` is set
  (relied on by Scenarios 1-20, which predate SE1 and set neither var yet stayed
  0-real-state-pollution before and after every round of this change, confirmed via
  `grep -rl '"emitter":"estate-merge"' "$HOME/.claude/state/progress-logs"` returning nothing).
- **The pid+timestamp `dedup_extra` token for `merge_failed` (`estate-merge.sh:311`) is unique
  per invocation.** `$$` is the OS-assigned PID, not caller-controlled, so two genuinely
  concurrent failed attempts always get distinct tokens.
- **`--acknowledge`'s default `--into` resolution (master, else main, else current HEAD,
  `estate-merge.sh:761-765`) mirrors `--check`'s own default exactly** — a deliberate
  assumption so an operator acknowledging a bypass without specifying `--into` lands the
  merges.log row under the SAME target `--check` would have scanned by default, keeping the
  two commands' defaults from silently diverging.
- **A `<sha>` passed to `--acknowledge` is assumed to already exist in the target repo's
  history** (`git rev-parse --verify --quiet`, `estate-merge.sh:756-759`); the command does not
  fetch or search for it elsewhere, matching every other subcommand's local-repo-only scope.

## Task SE4

### Status

Flip-time ledger emit at `adapters/claude-code/hooks/plan-edit-validator.sh`'s checkbox-flip
authorization chokepoint. Two commits on `wip/harness-hardening-2026-07-29`: the original
mechanism, **930a369eb0502832cad63c5166d7d8d8445a895c** (930a369, "feat(status-event-ledger
SE3/SE4/SE10)"), which added `emit_flip_ledger_event`/`flip_ledger_fields`/
`_pev_extract_prose_flip_fields`/`_pev_extract_json_flip_fields` and wired the emit into both
the mechanical/contract and full authorization branches; and a follow-on fix,
**8dd8c7f3c0ff829dfbb361f8ddca119edb7beff4** (8dd8c7f, "fix(plan-edit-validator SE4):
flip-ledger emit reads the LAST matching evidence block + the level-authorizer's own evidence
source"), closing two defects a harness-change-review REFORMULATE found in 930a369's design:
(a) the prose extractor reported the FIRST matching evidence block instead of the LAST on a
FAIL-then-fix-then-PASS re-verification, and (b) the field extractor always tried prose
before structured JSON regardless of the task's `VERIFICATION_LEVEL`, so a mechanical/
contract flip authorized by structured JSON could report a stale/unrelated prose block
instead. I am the author of both commits (930a369 as part of building SE3/SE4/SE10 together;
8dd8c7f as the harness-review fix); this entry covers the mechanism as it stands now — 930a369
plus 8dd8c7f's corrections, not 930a369 in isolation, since 930a369 alone had exactly the two
defects (a)/(b) above and would give a materially incomplete account of what the CURRENT code
does. All file:line citations below are against the current file on
`wip/harness-hardening-2026-07-29` (HEAD 69f00d97ed29abc476de7f1831da0b9d139de5b4), where both
commits are landed.

`plan-edit-validator.sh --self-test`: 14 passed, 5 failed (of 19 scenarios) on both `/bin/bash`
3.2.57 and `/opt/homebrew/bin/bash` 5.3.15, absolute path, re-run at this HEAD immediately
before writing this entry. The 5 failures (F5-F9) are a pre-existing, unrelated `stat -c %Y`
portability bug (docs/backlog.md HARNESS-GAP-63 territory's sibling issue, tracked separately
under PORTABILITY-STAT-SED-SWEEP-01/02), confirmed unchanged by either commit. Mutation-proven
at 8dd8c7f's own build time: reverting `_pev_extract_prose_flip_fields`'s last-match fix to
its original `emit(); exit 0` form turned scenario F18 red (reporting the stale first block's
`verdict=FAIL confidence=3` instead of the real `verdict=PASS confidence=8`) while F16/F17/F19
stayed green; restoring the fix returned all four to green.

## Comprehension Articulation

### Spec meaning

Taxonomy row 7 ("verification verdict + checkbox flip") and task bullet SE4
(`docs/plans/status-event-ledger.md:67-70`) ask for a **deterministic, mechanism-emitted**
ledger event recording the real verification outcome at the moment a task's checkbox is
authorized to flip — "plan-edit-validator already gates the flip; add emit at validation."
`plan-edit-validator.sh` is already the sole chokepoint every checkbox flip must pass through
(its own docstring: "the only entity allowed to flip a checkbox is task-verifier"), and by the
time either authorization path (`check_mechanical_or_contract_evidence`,
`plan-edit-validator.sh:1452`, or `check_evidence_first`, `:1522`) returns success the decision
to allow the flip has already been made — so the spec is satisfied by RE-READING that same
evidence at the moment of `exit 0` and emitting `{plan, task, verdict, confidence, verifier}`,
never by changing the authorization decision itself (`emit_flip_ledger_event` is called inside
`{ ... } 2>/dev/null || true`, `:1946`/`:1954`, so it can never turn an authorized flip into a
blocked one). The plan's own design law — "One vocabulary everywhere... never by an agent
remembering" — is why I read the spec as requiring the REPORTED verdict/confidence to be the
REAL, current one, not merely SOME verdict from SOME evidence block for that task id: a ledger
row that faithfully emits on every flip but reports a stale or mismatched-source verdict would
satisfy the letter of "add emit at validation" while violating the same design law's actual
intent (a status event that doesn't match reality is the exact drift class taxonomy row 7
exists to prevent). That reading is what turned 930a369's SE4 addition, correct as far as its
own two self-tests (F16/F17) proved, into 8dd8c7f's fix once a FAIL-then-fix-then-PASS
re-verification and a mechanical-level task with a stale co-resident prose file were
constructed as fixtures and shown to report the wrong fields.

### Edge cases covered

- **FAIL-then-fix-then-PASS re-verification reports the LAST block, not the first.**
  `_pev_extract_prose_flip_fields` (`plan-edit-validator.sh:1741-1777`) tracks
  `record_if_match()` (`:1751-1753`) at every `EVIDENCE BLOCK` header (`:1755-1758`) and again
  at the true `END` (`:1775`), overwriting `lv/lc/lr` each time a block's `Task ID:` matches
  `wanted_id` — so whichever matching block is LAST in file order is what gets emitted, exactly
  once. Scenario F18 (`plan-edit-validator.sh:1164-1230`) constructs a real evidence.md with two
  `Task ID: SE.4.3` blocks (an earlier FAIL, a later PASS confidence 8) and asserts the emitted
  ledger row says `verdict=PASS confidence=8`, never `FAIL`.
- **Mechanical/contract-level flips read the structured `.evidence.json` first, never a
  stale co-resident prose block.** `flip_ledger_fields` (`:1809-1847`) branches on `level`
  (`:1817`): mechanical/contract tries the structured file first (`:1818-1821`), falling back
  to prose only if absent (`:1822-1829`) — mirroring `check_mechanical_or_contract_evidence`'s
  own Path-A-structured/Path-B-prose preference (`:1452-1465` is Path A); `full` keeps the
  original prose-first/structured-fallback order (`:1834-1846`), mirroring
  `check_evidence_first`'s own Path-A-prose/Path-B-structured preference (`:1527`
  is Path A). Scenario F19 (`:1232-1285`) constructs a mechanical-level task with BOTH a stale
  prose block (verdict FAIL, verifier "stale-source-must-not-be-read") and a valid PASS
  structured JSON, and asserts the ledger reports the structured file's fields
  (`verdict=PASS confidence=unknown verifier=write-evidence.sh`), never the stale prose's.
- **Structured `.evidence.json` has no `confidence` field, so mechanical/contract flips
  honestly report `confidence=unknown`, never a fabricated number.**
  `_pev_extract_json_flip_fields` (`:1779-1791`) hardcodes the middle field as the literal
  string `unknown` in its `printf` (`:1790`, `'%s|unknown|%s'`) since the schema
  (`adapters/claude-code/schemas/evidence.schema.json`) carries no such field. Proven by F17
  (`:1127-1163`, unchanged from 930a369) and F19 alike.
- **The emit never fires on a blocked flip.** Both call sites (`:1946`, `:1954`) sit inside the
  `if check_mechanical_or_contract_evidence ... then` / `if check_evidence_first ... then`
  bodies that lead to `exit 0` — a denied authorization never reaches either line, so there is
  never a "verdict" reported for a rejected edit, honestly matching the taxonomy's own "verdict
  + checkbox flip" framing (no flip, no verdict to log).
- **A missing/unloaded `ledger_emit_typed` (e.g. `lib/signal-ledger.sh` failed to source)
  never blocks the flip.** `emit_flip_ledger_event`'s first line (`:1855`,
  `command -v ledger_emit_typed >/dev/null 2>&1 || return 0`) fails open before touching
  anything else, and both call sites additionally wrap the whole call in
  `{ ... } 2>/dev/null || true` (`:1946`, `:1954`) as a second layer of the same guarantee.

### Edge cases NOT covered

- **`check_evidence_first`'s own awk (the AUTHORIZER, not the emitter) double-prints "MATCH"
  under the same two-same-id-block shape this task's fixtures exercise, wrongly BLOCKING an
  otherwise-authorized flip.** Its `exit 0` at `plan-edit-validator.sh:1557` runs inside the
  main body, not `END`, but POSIX awk still executes the `END` rule afterward against the
  pre-reset state, so a block that already satisfies `(task_id==wanted_id && has_runtime)`
  followed by another `EVIDENCE BLOCK` header prints `MATCH` twice, and the caller's exact
  `[[ "$result" == "MATCH" ]]` comparison then fails, blocking a flip that real evidence
  should authorize. Found while building F18, filed as `docs/backlog.md` HARNESS-GAP-63, not
  fixed by either 930a369 or 8dd8c7f (out of SE4's own scope — it lives in the AUTHORIZER, not
  the ledger-emit code SE4 is about). F18's own fixture sidesteps it (its first block omits
  `Runtime verification:` so it never satisfies check_evidence_first's condition) rather than
  papering over it.
- **The checkbox-flip `TASK_ID` extraction regex (`:1902`,
  `grep -oE '[A-Z]+\.[0-9]+(\.[0-9]+)*'`) still requires a dotted id and rejects the fused
  `<Key><TaskId>` format (`SE3`, `RI1`, and this very plan's own `SE4`) outright** — filed as
  HARNESS-GAP-62 during 930a369's build, not fixed by either commit (out of scope, another
  session owns it per that entry). Practical consequence for THIS entry: a real flip of THIS
  plan's own `SE4` checkbox is refused today regardless of how much genuine evidence exists,
  which is also why F16-F19's fixtures all use the dotted form (`SE.4.1`-`SE.4.4`) to stay
  in scope rather than reproducing the blocked case.
- **Two verifiers racing to append evidence blocks to the SAME `evidence.md` concurrently**
  is not tested by F16-F19 (each fixture writes its evidence file once, synchronously, before
  the flip). `acquire_plan_lock` (`plan-edit-validator.sh:90`) serializes concurrent flips on
  the same plan file, but the ledger-emit's own read of `evidence.md` happens after
  authorization already succeeded and is not itself lock-protected against a THIRD process
  appending a block mid-read; not exercised here.
- **`flip_ledger_fields`/`_pev_extract_prose_flip_fields` apply no freshness (mtime) check of
  their own** — unlike the authorizers, which gate on a <=120s mtime window
  (`:1534-1537` full path, structured-file mtime check inside `check_mechanical_or_contract_
  evidence`). The ledger-emit trusts that if authorization just succeeded, the evidence it
  re-reads moments later is still the same evidence; a pathological reordering where the
  evidence file is rewritten in the instant between authorization and emit is not guarded
  against or tested.

### Assumptions

- **task-verifier APPENDS a new evidence block for a re-verification rather than replacing
  the old one.** This is the load-bearing assumption behind the last-match fix's entire
  premise (and behind F18's fixture): if a re-verification instead overwrote/truncated the
  prior block, first-match and last-match would coincide and 930a369's original bug would
  never have manifested. Grounded in the real 3404bd1 T7 FLIP history the harness-review cited
  as precedent, not invented for this fix.
- **`VERIFICATION_LEVEL` is always a valid non-empty value (`mechanical`/`contract`/`full`) by
  the time either call site (`:1946`, `:1954`) is reached.** Both call sites are inside
  branches already guarded by `[[ -n "$TASK_ID" ]]` (`:1941`, `:1952`), and
  `extract_verification_level` (`:1410`) always returns one of the three literal strings,
  defaulting to `full` when it cannot determine a level — so `flip_ledger_fields`'s own
  `level="${3:-full}"` default (`:1810`) is a belt-and-suspenders fallback that should never
  actually trigger via these call sites, only via direct/test invocation.
- **The structured `.evidence.json`'s `task_id` field, once matched by
  `check_mechanical_or_contract_evidence`, is the SAME file `flip_ledger_fields` re-resolves.**
  Both derive `structured_file` identically from `plan_dir`/`plan_slug`/`task_id`
  (`:1461-1462` in the authorizer, `:1811-1814` in the emit path) — no race is assumed between
  the two reads beyond what the "no freshness check of its own" gap above already names.
