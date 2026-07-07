# Wave D specs — design freeze + exact per-task build specs (appendix to nl-overhaul-program-2026-07.md)
Status: REFERENCE (spec appendix, not an independent plan — task D.0 deliverable)
prd-ref: n/a — harness-development
rung: 1
architecture: coding-harness
frozen: true

Authored by the Wave-D orchestrator (D.0), 2026-07-03. The operator veto window on the
ADR 058 D5 gate-retirement map CLOSES with this freeze (Decisions Log: "Gate-retirement
map locked at D.0"). Every disposition below is reversible post-cutover via `attic/` +
exit-0 shims + the `pre-wave-d-cutover` tag (one settings re-add to restore any gate).

## §D.0.1 The definitive post-diet haiku probe (MEASURED, this session)

- Dispatch: one trivial `explorer` agent, `model: haiku`, fresh post-cutover top-level
  session (this one, booted on the dieted `~/.claude/rules/` = constitution only).
- Result: **PROBE-OK — booted and replied in 949 ms at 27,232 total tokens.**
- Baseline: pre-diet haiku dispatches could not boot at all (~207,334 tokens > 200,000
  window; measured twice — Wave-B batch-1 and the C.6 re-probe).
- Consequence: **haiku tier is USABLE for D.8 model routing from this session onward.**
  ~87% context reduction confirmed at the agent-boot level. This datum goes to the F.4
  retro. (First probe attempt note: `general-purpose` agents are write-capable and
  require `isolation: "worktree"` per teammate-spawn-validator — probe agents should be
  read-only types.)

## §D.0.2 Frozen Stop chain (22 → 6 entries)

| # | Entry | Status |
|---|-------|--------|
| 1 | `work-integrity-gate.sh` (NEW, D.2) | blocking — merges pre-stop-verifier + product-acceptance-gate (+ its runtime-verification invocation) + worktree-teardown-gate's uncommitted-work check; scoped to session-touched plans/files |
| 2 | `session-honesty-gate.sh` (NEW, D.3) | blocking on marker-absence/format or DONE-vs-block contradiction ONLY; absorbs continuation-enforcer semantics (finally live); narrate-and-wait / deferral-counter / transcript-lie-detector / goal-coverage heuristics DEMOTED to ledger warns inside it |
| 3 | `bug-persistence-gate.sh` (KEPT) | blocking — artifact-based; passes the §D.0.8 anti-pattern audit (remedy is a file write, never final-message content) |
| 4 | `workstreams-stop-writer.sh` (NEW, D.5 consolidation) | non-blocking — one entry chaining the 5 writer behaviors: workstreams-stop-gate, workstreams-emit, workstreams-extract-pending, workstreams-emit-reconciler, workstreams-orchestrator-queue. workstreams-task-binding's Stop BLOCK retires (§D.0.5); its mutation-count signal becomes a ledger warn here |
| 5 | `signal-ledger-flush.sh` (NEW, thin — D.5) | non-blocking — flushes/finalizes the session's ledger segment (lib from D.1) |
| 6 | `session-wrap.sh` (KEPT) | non-blocking |

Retired from Stop (→ `attic/` + exit-0 shim at old live path for one release):
narrate-and-wait-gate, deferral-counter, transcript-lie-detector,
imperative-evidence-linker, goal-coverage-on-stop, decision-context-gate (fence
ENFORCEMENT only — emit writers + pending-decision ledger stay), principles-compliance-gate
(→ ledger warn in session-honesty), pr-health-snapshot-gate (→ digest feed, D.4),
customer-facing-review-gate (→ spawn-time PreToolUse warn + ledger, D.4),
completion-criteria-gate (→ close-plan.sh + PR-merge boundary, D.4),
register-progress-gate, pre-stop-verifier + product-acceptance-gate +
worktree-teardown-gate (merged into #1), the 5 workstreams writers (merged into #4),
workstreams-task-binding --on-stop (retired, §D.0.5), continuation-enforcer.sh
(absorbed by #2; was the audit's flagship claimed-but-wired-nowhere gate).

## §D.0.3 Frozen SessionStart chain (24 → 8 entries)

| # | Entry |
|---|-------|
| 1 | compact-recovery echo (matcher: `compact`) — kept verbatim |
| 2 | `session-start-auto-install.sh` |
| 3 | `harness-doctor.sh --quick` (NEW wiring — replaces settings-divergence-detector, check-harness-sync's session role, cross-repo-drift-warn's local half, per ADR 058 D4) |
| 4 | config load: `automation-mode.js` + `read-local-config.sh` (one chained entry) |
| 5 | `gh-account-blindness-hint.sh` |
| 6 | `broadcast-active-session.sh` (liveness marker — B.12's interactive-session-lock feeds on it) |
| 7 | `workstreams-emit.sh --session-start` (GUI writer) |
| 8 | `session-start-surfacer-pack.sh` (NEW, TRANSITIONAL — one entry chaining the surviving surfacers: discovery-surfacer, register-surfacer, stalled-work-surfacer, spawned-task-result-surfacer, external-monitor-alert-surfacer, session-start-git-freshness, session-start-worktree-advisor, stale-active-plan-surfacer, plan-status-archival-sweep, decision-context-pending-surfacer, workstreams-task-binding --on-session-start, session-start-discovery-cheatsheet, orchestrate.sh, effort-policy-warn. **E.1's digest REPLACES this pack** — the pack is scaffolding so D.5 hits ≤8 without destroying signal before the digest exists; each member stays an unmodified script on disk) |

Retired outright at D.5 (not into the pack): settings-divergence-detector (→ doctor),
cross-repo-drift-warn (→ doctor), decision-context-replay (fence retired with its gate).

## §D.0.4 Frozen PreToolUse map + the ≤12 blocking-gate counting rule

**Counting rule (frozen):** the ADR 058 D5 "blocking gates ≤ 12 total" budget counts
manifest units with `blocking: true` wired to LIVE-SESSION events (PreToolUse, Stop,
TaskCreated/TaskCompleted, UserPromptSubmit). Git-native `precommit`/`prepush` hooks are
a separate budget class (`git-boundary`) — they gate git, not the model loop; F.1 may
budget them separately. A unit may comprise several small same-class hooks dispatched
from one consolidated entry.

**The 12 blocking session-event units after Wave D:**

| # | Unit (manifest id) | Members |
|---|--------------------|---------|
| 1 | bug-persistence | bug-persistence-gate.sh (Stop) |
| 2 | work-integrity (NEW) | work-integrity-gate.sh (Stop) |
| 3 | session-honesty (NEW) | session-honesty-gate.sh (Stop) |
| 4 | spec-freeze | spec-freeze-gate.sh + scope-enforcement-gate.sh (PreToolUse) |
| 5 | tdd / no-test-skip | no-test-skip-gate.sh (PreToolUse) |
| 6 | command-safety (consolidated) | env-local-protection.sh + inline .env/lockfile greps + inline curl-pipe-sh grep + inline force-push grep + automation-mode-gate.sh (all dangerous-command artifact screens) |
| 7 | migration-naming | migration-naming-gate.sh |
| 8 | local-edit-authorization | local-edit-gate.sh |
| 9 | plan-edit-validator | plan-edit-validator.sh |
| 10 | wire-check | wire-check-gate.sh |
| 11 | commit-boundary (consolidated) | pre-commit-gate.sh + findings-ledger-schema-gate.sh + plan-deletion-protection.sh + claude-md-hygiene-gate.sh (fire only on git-commit-shaped Bash commands; all get the §D.0.6 block-message banner) |
| 12 | agent-teams | teammate-spawn-validator.sh (+ dag-review-waiver folded in, D.6) + task-completed-evidence-gate.sh (plan-scoped form, §D.0.5) |

**Demoted to non-blocking warn + ledger (D.6):** observed-errors-gate,
outcome-evidence-gate, definition-on-first-use-gate, doc-gate, pr-template-inline-gate,
prd-validity-gate (mechanical shape-check becomes warn + recommend-invoke; substance
review stays the agent), systems-design-gate (plan-boundary substance stays in
plan-reviewer's precommit layer). **Retired (D.6):** tool-call-budget attestation loop
(0 attestations in 10,959 calls → soft counter event to ledger/digest),
check-harness-sync (doctor's remit), dag-review-waiver-gate (folded into
teammate-spawn-validator), vaporware-volume-gate (→ CI per D.4).

## §D.0.5 MANDATED ROW — workstreams-task-binding × task-completed-evidence-gate

**The collision (PROVEN, audit addendum lines 95–105 + code):**
`workstreams-task-binding.sh --on-stop` (workstreams-task-binding.sh:144-238) blocks any
session with >5 tool calls and 0 TaskCreate/TaskUpdate mutations, demanding the session
"call TaskCreate (and TaskUpdate it to completed)". Complying fires `TaskCompleted` →
`task-completed-evidence-gate.sh:386-513` blocks unless the task_id appears in an ACTIVE
plan's evidence log — but a task invented to satisfy the binding gate belongs to no
plan. Mutually unsatisfiable for any session whose work is outside the current ACTIVE
plans.

**Frozen disposition (kills the collision from both ends):**
- task-binding's Stop BLOCK retires (already implied by the §D.0.2 chain); its
  mutation-count signal becomes a non-blocking ledger warn emitted by
  workstreams-stop-writer. Its SessionStart listing survives in the surfacer pack; its
  SendUserMessage PreToolUse wiring retires with the Stop block (same mechanism, same
  false-demand).
- task-completed-evidence-gate Layer 1 becomes **plan-scoped**: it blocks ONLY when the
  completed task_id IS declared by an ACTIVE plan (i.e. the plan names the task and the
  evidence block is missing). Ad-hoc / session-log task completions get a ledger warn,
  never a block. (D.6 implements + self-test scenario "ad-hoc task completes without
  evidence → allow + warn"; "plan-declared task completes without evidence → block".)

**The unreachable `bypass_evidence_check` hatch (PROVEN unreachable):** read at
task-completed-evidence-gate.sh:395 from the TaskCompleted event JSON; no agent-facing
tool exposes the field (TaskUpdate has no such param; task metadata does not flow into
the hook event — verified in the audit addendum). **Disposition: DELETE the dead hatch**
(D.6). The legitimate valves are: the plan-scoping fix above (removes the false-positive
class that made a bypass tempting), `TASK_COMPLETED_BYPASS=1` (process-level,
maintainer-only, kept + documented in the hook header), and HARNESS_SELFTEST sandboxing.

## §D.0.6 MANDATED ROW — NL-FINDING-016: compound-command gate trap

Every PreToolUse gate that can block a `git commit`-bearing Bash command (the
commit-boundary unit members + scope-enforcement/spec-freeze + migration-naming +
findings-ledger-schema) MUST have this appended to its block message (D.4 sweep):

> NOTE: this block prevented the ENTIRE command from running — including any
> fix/edit/`git add` prefix before the `git commit`. Nothing was executed. Re-run the
> non-commit part as its own call first, then commit separately.

Done-when grep: `grep -l "ENTIRE command" <each member hook>` non-empty for all members.

## §D.0.7 MANDATED ROW — scope-enforcement-gate first-backtick parser (FIX, not document)

PROVEN duplicated bug: `scope-enforcement-gate.sh:1536-1538` and
`spec-freeze-gate.sh:193-197` — `tmp="${line#*\`}"; extracted="${tmp%%\`*}"` captures
only the first backtick-quoted token per bullet line (4 live occurrences: plan In-flight
lines 149–156). **D.6 fixes BOTH sites**: extract a shared
`hooks/lib/extract-backtick-paths.sh` helper that loops all backtick pairs and appends
EVERY token into SECTION_ENTRIES; both hooks source it; self-test adds a
multi-path-per-line scenario to each hook's suite (a bullet naming 2 paths must produce
2 scope entries). The plan's one-file-per-bullet In-flight workaround pattern becomes
unnecessary going forward (existing lines stay valid).

## §D.0.8 MANDATED ROW — session-wrap dual-path resolution: REFUTED as a bug; lib gap fixed

Investigated (scripts/session-wrap.sh:58-100, 189-192, 632-639): the split is
DELIBERATE and correct — SCRATCHPAD.md resolves to the MAIN checkout via
git-common-dir (ADR 028: worktrees are short-lived build isolation), while
backlog/roadmap/discoveries resolve to the CURRENT worktree (HARNESS-GAP-38: tracked
files ship via PR; parent-copy reads would make freshness structurally unpassable).
Frozen disposition: **no behavior change.** Two real gaps fixed in D.4: (a)
`hooks/lib/nl-paths.sh` gains `nl_main_checkout_root()` (the git-common-dir derivation)
so future hooks stop hand-duplicating it; session-wrap may source it or keep its local
copy; (b) session-wrap `--self-test` gains a caller-cwd scenario (invoked from a cwd
outside any worktree, both resolvers must fail safe together rather than silently
collapsing WT_REPO→REPO — the one path that could produce the reported symptom).

## §D.0.9 MANDATED AUDIT — requires-content-in-final-message anti-pattern (surviving Stop checks)

The operator-observed failure: gates scanning the final message force blocked sessions
to re-emit ever-thinner report copies. Audit of the 6 survivors:
- bug-persistence-gate: PASSES — scans the whole transcript for unpersisted bug
  mentions; remedy is a file write. No final-message content demand.
- work-integrity-gate (D.2 spec): remedy = fix artifacts (commit work, flip checkboxes,
  write waiver file). MUST NOT scan or demand final-message content. Pinned in §D.2.
- session-honesty-gate (D.3 spec): the ONLY surviving final-message check, by design,
  and its demand is bounded: one marker line + (on retry) a minimal delta. Explicitly
  satisfiable by `<MARKER>: <one line>` + "report above stands". Pinned in §D.3.
- workstreams-stop-writer / signal-ledger-flush / session-wrap: non-blocking writers.
Verdict: post-cutover, no blocking Stop check can demand report re-statement.

## §D.0.10 Estate reconcile record (runbook items, executed this session)

- `worker-D.1` (81f485f): deliverables (signal-ledger.sh + retry-guard routing) on
  master via PR #71 (65b7539); remaining branch delta = stale docs noise → DELETED.
- `worker-C.6` (d2f7ed6 + 58d91f1): sweep landed on master in amended form; the
  branch's residual edits point at pre-diet paths master has since improved
  (rules/plan-lifecycle.md vs doctrine/planning-full.md) → superseded → DELETED.
- `worker-E.4a` (3eff41c): scaffold + 5 scenarios + deferred.txt on master via PR #71
  → DELETED.
- Dirty worktree `agent-a2e9fdd2d16c316f8`: sole content one untracked stub
  `tests/jit-probe.test.ts` ("// jit probe", C.2 live-probe artifact) — worktree
  removed, branch deleted. Nothing salvageable (looked before deleting, §9).
- DISCOVERED during sweep: **30 stale `worktree-agent-*` / `worktree-wf_*` local
  branches** with no attached worktrees → explicit F.1 input (the accumulation class
  its digest-disposition machinery is being built for). Not hand-triaged here.
- `modest-satoshi-150d97` worktree (prior orchestrator, branch merged @ ef1c001):
  left in place — F.1's staleness machinery dispositions it; not this runbook's item.

## §D.2 work-integrity-gate.sh — exact spec

New `adapters/claude-code/hooks/work-integrity-gate.sh`, Stop event, blocking.
Merges, scoped to THIS session's touched plans/files (transcript-derived — parse
tool_use file paths from the transcript JSONL, same technique as pre-stop-verifier):
1. pre-stop-verifier's per-task evidence check — only for plans this session edited;
2. product-acceptance-gate's acceptance-artifact check — only for plans this session
   edited (honors `acceptance-exempt: true`);
3. worktree-teardown-gate's uncommitted-work check (worktree sessions: dirty tree at
   Stop = block with the exact rescue commands).
Requirements (non-negotiable, review finding 4):
- Registers itself in `RETRY_GUARD_VERIFICATION_HOOKS`: the lib default at
  `hooks/lib/stop-hook-retry-guard.sh:148` becomes
  `"pre-stop-verifier product-acceptance-gate work-integrity-gate"` (keep old names —
  shims may still fire during the release window).
- Ledger-logging via `hooks/lib/signal-ledger.sh` for every block/warn/downgrade.
- HARNESS_SELFTEST sandboxing; block messages carry remediation (artifact fixes only —
  NEVER final-message content demands, §D.0.9).
- `--self-test` ≥12 scenarios incl. MANDATED: "orthogonal ACTIVE plan does NOT block"
  (waiver-tax killer), "session-touched plan with unchecked tasks DOES block",
  "DONE-claimed + this gate blocking is NOT downgraded by retry-guard" (assert the
  retry-guard lib refuses the downgrade with work-integrity-gate in the verification
  list), "dirty worktree blocks with rescue text", "clean session passes".
Wiring lands in D.5, not here (build + self-test only; template untouched by D.2).

## §D.3 session-honesty-gate.sh — exact spec

New `adapters/claude-code/hooks/session-honesty-gate.sh`, Stop event, blocking (narrow).
- BLOCKS only on: (a) final assistant message lacks exactly one
  `DONE:`/`PAUSING:`/`BLOCKED:`/`CONTINUING:` marker on its last line; (b) marker is
  DONE while work-integrity-gate blocked this session later than the last DONE claim
  (flagrant self-contradiction — read the retry-guard/ledger state for the block
  record).
- CONTINUING requires naming a wake mechanism token (grep for one of: scheduled,
  watchdog, cron, wakeup, monitor, background task id) — warn (not block) if absent.
- PAUSING semantics per constitution §8: the message must contain an exact ask.
  Heuristic only → ledger warn, never block (PAUSING-only-for-irreversibles is
  doctrine, not mechanically decidable).
- DEMOTED heuristics inside this gate as ledger warns (never block): narrate-and-wait
  pattern, deferral phrases (deferral-counter), self-contradiction candidates below the
  flagrant bar (transcript-lie-detector), goal-coverage misses.
- DESIGN PIN (operator directive 2026-07-02): satisfiable by a minimal-delta closing —
  `<MARKER>: <one fix line>` (+ optionally "report above stands"). The gate NEVER
  demands report content be re-stated. Self-test scenario asserts a 2-line closing
  passes after a prior block.
- Ledger + HARNESS_SELFTEST as in D.2. `--self-test` ≥10 scenarios incl. MANDATED:
  "waiting-on-operator turn ending PAUSING: <exact ask> passes" (the audit's
  false-positive case), "DONE while work-integrity blocked this session fails",
  "CONTINUING with verified-running background work passes", "minimal-delta retry
  closing passes", "no marker blocks", "two markers blocks".
Wiring lands in D.5. continuation-enforcer.sh retires to attic at D.5 (absorbed here).

## §D.4 relocations — exact spec

1. completion-criteria → `scripts/close-plan.sh` gains the completion-criteria check
   (plan cannot flip to COMPLETED with unmet criteria) + the PR-merge boundary check
   (grep assertion in specs; closes GAP-53's preview-deploy false-pass by checking at
   close, not Stop).
2. customer-facing-review → teammate-spawn-validator gains a non-blocking spawn-time
   WARN (+ ledger event) when the spawned task prompt matches the customer-facing
   pattern list from customer-facing-review-gate.sh (pattern file extracted, gate body
   retires at D.5).
3. pr-health → a `scripts/pr-health-snapshot.sh` collector callable by the E.1 digest
   (Stop gate retires; script keeps the data flowing; digest consumes in Wave E —
   until then the collector is invocable manually and by session-wrap).
4. decision-context: fence ENFORCEMENT retires (gate to attic at D.5); emit-side
   writers + pending-decision ledger + decision-context-pending-surfacer stay.
5. vaporware-volume → CI: add its check to the E.4 design-skip companion plan's CI list
   (this task only writes the relocation note + retires the PreToolUse wiring at D.5).
6. NL-FINDING-016 block-message banner sweep (§D.0.6) across the commit-boundary
   members + scope/spec-freeze + migration-naming.
7. `nl-paths.sh` gains `nl_main_checkout_root()` + session-wrap caller-cwd self-test
   scenario (§D.0.8).
Done-when: per-item greps (banner presence, close-plan check block, spawn-warn pattern
file sourced, collector script exists + exits 0 on a fixture, fence gate body absent
from live wiring after D.5).

## §D.5 cutover (SERIAL, orchestrator-supervised) — runbook

1. Pre-flight: D.2/D.3/D.4/D.6 cherry-picked + verified; doctor --quick green; golden
   evals green; synthetic stable subset green. 2. `git tag pre-wave-d-cutover`.
3. Rewrite settings.json.template: Stop → §D.0.2 six; SessionStart → §D.0.3 eight;
   PreToolUse → §D.0.4 map. Build session-start-surfacer-pack.sh +
   workstreams-stop-writer.sh + signal-ledger-flush.sh (thin dispatchers over existing
   scripts). 4. Move retired hooks to `adapters/claude-code/attic/`; leave 3-line
   exit-0 shims at old LIVE paths (`~/.claude/hooks/<name>.sh`) via install.sh's shim
   list for one release. 5. Update manifest.json (wired_template, events, blocking per
   the frozen map; new units registered; retired units re-classed `attic`).
6. Install; doctor --quick + --full GREEN before AND after; golden evals + synthetic
   stable subset green before AND after; chain-count assertions (node): template AND
   live Stop ≤6, SessionStart ≤8; every retired live path exits 0. 7. Merge to master
   via PR when green; sync BOTH remotes (work-org origin + personal mirror; gh auth
   switch per the account map in ~/.claude/local, restore after). Long-lived sessions
   note: alive sessions snapshot hook config — shims keep them no-op-safe.

## §D.6 PreToolUse rationalization — exact spec

1. Retire tool-call-budget.sh from PreToolUse (template edit staged for D.5; hook to
   attic; its counter becomes a signal-ledger `soft-counter` event at the same
   thresholds, emitted by a 10-line `scripts/tool-call-counter.sh` the pack/digest can
   read).
2. Fold dag-review-waiver-gate.sh's check into teammate-spawn-validator.sh (one gate,
   one block message); gate file to attic at D.5.
3. task-completed-evidence-gate.sh → plan-scoped Layer 1 (§D.0.5) + DELETE the
   bypass_evidence_check hatch + self-test scenarios (ad-hoc allow+warn /
   plan-declared block).
4. workstreams-task-binding.sh: retire --on-stop block + SendUserMessage wiring
   (behavior moves per §D.0.5); --on-session-start survives (pack member).
5. Backtick-parser fix (§D.0.7): shared lib helper + both hooks + self-tests.
6. check-harness-sync.sh retired from PreToolUse (doctor's remit; attic at D.5).
7. Demotions (§D.0.4 list): observed-errors, outcome-evidence, definition-on-first-use,
   doc-gate, pr-template-inline, prd-validity(shape), systems-design(shape) → exit 0 +
   `hookSpecificOutput.additionalContext` warn + ledger event; blocking:false in
   manifest.
Done-when: each item's grep/self-test from this section passes; manifest blocking
session-event unit count = 12 (script assertion; doctor budget check itself lands F.1).

## §D.5 as-built amendments (orchestrator, 2026-07-03)

1. **Counting rule refined:** "blocking ≤12" counts entries with blocking:true AND
   `wired_template:true` (an unwired gate cannot fire; runtime-verification stays
   blocking-flagged but unwired+honest_status, so it does not consume a slot).
   Durable assertion: `adapters/claude-code/scripts/blocking-budget-check.js`
   (GREEN at 12/12); F.1 wires it into the doctor.
2. **commit-boundary unit membership += vaporware-volume-gate** (fires only on
   commit-shaped Bash commands; its CI relocation follows in the E.4 companion —
   keeping it blocking until then avoids a coverage gap).
3. **workstreams-state-gate.sh counted under the agent-teams unit** (same
   spawn-validation class); formal entry-fold deferred to F-wave to preserve
   its jit_triggers.
4. **Shim mechanism:** shims are real 3-line exit-0 files AT the retired names in
   `hooks/` (synced by the normal install flow — no install.sh surgery); originals
   in `attic/`. Manifest entry `wave-d-retired-shims` covers all 22 for disk↔manifest
   coverage. runtime-verification-executor/reviewer NOT atticked (still invoked by
   the kept plan-edit-validator.sh).
5. **Sole (A)-class breakages** (classifier-verified): tests/acceptance-loop-self-test.sh
   + tests/agent-teams-self-test.sh executed retired hooks — repointed to attic paths.
   Golden evals reference no retired hook.
6. **Golden eval fix:** credential-push-blocked.sh failed PRE-EXISTING on master
   (PROVEN) — its fixture `git commit` of leaked.txt was intercepted by the machine-
   global core.hooksPath pre-commit scan, killing the eval under set -e before the
   push-scan assertion ran. Fixture now sets repo-local empty core.hooksPath; eval
   passes and finally tests the unit it names.
7. **Template arithmetic:** Stop 22→6, SessionStart 24→8, PreToolUse 35→32 (the
   check-harness-sync+pre-commit-gate compound entry was split; pre-commit-gate
   re-added standalone). Manifest 90→79 entries.

## Dispatch map (orchestrator)

| Task | Model | Parallel | Builder branch |
|------|-------|----------|----------------|
| D.2 | sonnet | yes (batch 1) | worker-D.2 |
| D.3 | sonnet | yes (batch 1) | worker-D.3 |
| D.4 | sonnet | yes (batch 1) | worker-D.4 |
| D.6 | sonnet | yes (batch 1) | worker-D.6 |
| D.5 | sonnet, orchestrator-supervised | no (serial, after 1–4 verified) | worker-D.5 |

File-disjointness: D.2/D.3 create disjoint new hooks (+ D.2 edits retry-guard lib);
D.4 edits close-plan.sh, spawn-validator (warn side), nl-paths.sh, session-wrap
self-test, banner sweep on commit-boundary members; D.6 edits tool-call-budget
successor script, spawn-validator (dag-fold side), task-completed-evidence,
task-binding, backtick lib + scope/spec-freeze hooks. COLLISION: D.4 and D.6 both
touch teammate-spawn-validator.sh — D.4 adds the warn block, D.6 folds dag-review;
orchestrator resolves at cherry-pick (D.4 first, then D.6 rebased on it). Builders:
NL-FINDING-014 first-action self-check (`git rev-parse --git-dir` ≠ `--git-common-dir`
else STOP), first action `git checkout -b worker-<task>` from the dispatch branch, no
plan edits, fix-calls separate from commit-calls (NL-FINDING-016).
