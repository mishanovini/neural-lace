<!-- scaffold-created: 2026-07-13T18:31:23Z by start-plan.sh slug=lessons-learned-fixes-2026-07-13 -->
# Plan: Lessons Learned Fixes 2026-07-13
Status: COMPLETED
Execution Mode: direct
Mode: code
Backlog items absorbed: none
acceptance-exempt: true
acceptance-exempt-reason: Harness-internal: the user is the maintainer; each fix is proven by its hook --self-test and harness-doctor staying GREEN, not by a product user flow.
tier: 2
rung: 2
architecture: coding-harness
frozen: true
lifecycle-schema: v2
owner: Misha
target-completion-date: 2026-07-14
prd-ref: n/a — harness-development
ask-id: none — no linked ask

## Goal
Implement the fixes that a full audit of the three neural-lace lessons-learned
(`docs/lessons/`) proved are STILL NEEDED. An assess+adversarially-verify workflow
(26 agents, 0 disagreements) classified every proposed fix as already-done,
still-needed, operator-only, or obsolete. This plan lands the still-needed,
agent-actionable ones and files backlog rows for the two that warrant their own
dedicated effort.

The load-bearing correction the audit produced: the 2026-07-13 efficiency lesson's
premise that "settings.json has no durable repo→live sync" is FALSE —
`session-start-auto-install.sh:merge_settings()` additively syncs new hook wirings
from `settings.json.template` (the canonical source) every SessionStart. So ADDITIONS
to hook wiring propagate live automatically; only removals need a manual reconcile.
That asymmetry sets this plan's scope: we ADD (find-warn hook) and edit scripts
(pre-filters, single-flight lock) — all repo-source-only changes that land live via
the normal sync — and DEFER the one removal (dead shim) to a backlog row so we never
hand-edit `~/.claude` nor race the 5 concurrent live sessions.

## User-facing Outcome
n/a — harness-internal: the user is the maintainer. After this plan ships:
- Every giant PreToolUse gate (`scope-enforcement-gate.sh`, `plan-deletion-protection.sh`)
  exits the common non-matching path ~70-90% faster (measured 612→182ms, 1194→125ms),
  cutting per-Bash-call latency and Defender-scanned spawns on Windows.
- A disk-wide `find /` / `find ~` scan emits a non-blocking nudge toward `Glob`/`git
  rev-parse` (the ~65%-of-a-core self-inflicted spike from Lesson 3 Finding 3).
- Simultaneously-starting sessions no longer run `session-start-auto-install` /
  `session-start-digest` concurrently — a single-flight lock makes the second session
  skip-and-reuse, killing the 34→81 `bash.exe` fork-storm at its source.
- The lessons themselves stop lying: the 2026-07-11 lesson reflects its SHIPPED gate;
  FM-029 / ADR-035 cross-refs point at the real post-consolidation `doctrine/` paths.
The deliverable outcome is each artifact's `--self-test` passing and `harness-doctor.sh
--quick` staying GREEN (no new reds vs. the pre-change baseline).

## Scope
- IN:
  - Fix the stale "(Pending build …)" bullet in the 2026-07-11 lesson (gate is live).
  - Fix stale `~/.claude/rules/{diagnosis,claims}.md` cross-refs (now `doctrine/`) in
    FM-029 (`docs/failure-modes.md`) and ADR-035.
  - Add a pure-bash substring pre-filter to `scope-enforcement-gate.sh` and
    `plan-deletion-protection.sh` (behavior-preserving; self-tests are the oracle).
  - Create `find-scan-warn.sh` (non-blocking, exit-0 warn) + wire it in
    `settings.json.template` + register in `manifest.json`.
  - Create `lib/sessionstart-singleflight.sh` (mkdir-lock) + gate the heavy SessionStart
    scripts; register in `manifest.json`. Route through `harness-reviewer` before merge.
  - Commit the uncommitted source lesson `docs/lessons/2026-07-13-agent-efficiency-…md`.
  - File deferred backlog rows (dispatcher, dead-shim-retire) + reconcile §8 bookkeeping.
- OUT:
  - Coalescing the 20 PreToolUse hooks into one dispatcher (Lesson 3 rec 4) — HIGH
    blast radius (every Bash call), needs its own plan + harness-reviewer + staged
    rollout. Filed as `PRETOOLUSE-DISPATCHER-01`.
  - Retiring `workstreams-state-gate.sh` from live wiring (Lesson 3 rec 3) — a REMOVAL,
    which `merge_settings()` cannot propagate; needs a live `~/.claude` reconcile that
    would race concurrent sessions + red the doctor. Filed as `HOOK-SHIM-RETIRE-01`.
  - Windows Defender exclusions (Lesson 3 rec 1) — OPERATOR_ONLY; the helper script
    already ships. Surfaced to the operator in NEEDS-YOU.
  - Tool-result trimming (Lesson 3 rec 7) — OBSOLETE; unbuildable as a hook.

## Tasks

- [ ] 1. Commit the uncommitted source lesson `docs/lessons/2026-07-13-agent-efficiency-bottlenecks-process-spawn-and-hook-latency.md` to master (the source doc behind this plan's efficiency fixes) — Verification: mechanical — Docs impact: adds the lesson doc to tracked history.
- [ ] 2. Fix the stale "(Pending build …)" bullet in `docs/lessons/2026-07-11-bulk-shared-state-mutation-without-ownership-check.md` to reflect the SHIPPED `concurrent-ownership-gate.sh` (19/19 self-test, live) — Verification: mechanical — Docs impact: corrects the lesson doc (Constitution §1 honesty).
- [ ] 3. Fix stale `~/.claude/rules/{diagnosis,claims}.md` cross-refs (now under `doctrine/`) in FM-029 (`docs/failure-modes.md`) and `docs/decisions/035-diagnostic-first-protocol.md` — Verification: mechanical — Docs impact: corrects two doc cross-references post ADR-058 consolidation.
- [ ] 4. Add a pure-bash substring pre-filter to `scope-enforcement-gate.sh` (guard `*commit*`) and `plan-deletion-protection.sh` (guard `*rm*|*mv*|*clean*|*stash*|*checkout*|*restore*|*reset*`), placed after the `--self-test` capture and before the first `jq`/`sed` spawn; re-export `CLAUDE_TOOL_INPUT` so the existing input-load path is unaffected — Verification: mechanical — Docs impact: none — behavior-preserving perf change, documented via in-file comment.
- [ ] 5. Create `adapters/claude-code/hooks/find-scan-warn.sh` (PreToolUse/Bash, always exit 0, warns only on broad `find /` / `find ~` / `find $HOME` roots, never scoped finds), wire it in `settings.json.template`, register in `manifest.json`, `chmod +x` — Verification: mechanical — Docs impact: adds a `manifest.json` hook entry.
- [ ] 6. Create `adapters/claude-code/hooks/lib/sessionstart-singleflight.sh` (mkdir-based `ss_singleflight <name> <ttl>` ttl-debounce, fail-open on error, stale-stamp reclaim) with a `--self-test`; gate `session-start-auto-install.sh` main body (skip-and-return-0 when another session synced within the window); inventory the lib in `manifest.json`. Digest is intentionally NOT gated — see Decisions Log — Verification: mechanical — Docs impact: adds the lib to the auto-install `manifest.json` entry.
- [ ] 7. Route the two behavior-touching changes (Task 4 pre-filters, Task 6 single-flight lock) through the `harness-reviewer` agent; address any Critical/Major findings before merge — Verification: mechanical — Docs impact: none — review artifact captured in evidence.
- [ ] 8. File deferred backlog rows `PRETOOLUSE-DISPATCHER-01` (rec 4) and `HOOK-SHIM-RETIRE-01` (rec 3) with deferral rationale; annotate `SESSIONSTART-SINGLEFLIGHT-01` (lock part landed here; Defender part = shipped helper) and mark recs 5/6 resolved in `docs/backlog.md` — Verification: mechanical — Docs impact: edits `docs/backlog.md` (Lesson 3 §8 bookkeeping reconciliation).

## Files to Modify/Create
- `docs/lessons/2026-07-13-agent-efficiency-bottlenecks-process-spawn-and-hook-latency.md` — Create (commit the currently-untracked source lesson).
- `docs/lessons/2026-07-11-bulk-shared-state-mutation-without-ownership-check.md` — Modify (fix "Pending build" bullet).
- `docs/failure-modes.md` — Modify (FM-029 stale `rules/`→`doctrine/` path refs).
- `docs/decisions/035-diagnostic-first-protocol.md` — Modify (stale cross-ref paths).
- `adapters/claude-code/hooks/scope-enforcement-gate.sh` — Modify (add pre-filter guard).
- `adapters/claude-code/hooks/plan-deletion-protection.sh` — Modify (add pre-filter guard).
- `adapters/claude-code/hooks/find-scan-warn.sh` — Create (non-blocking find-scan warn hook).
- `adapters/claude-code/settings.json.template` — Modify (wire find-scan-warn).
- `adapters/claude-code/hooks/lib/sessionstart-singleflight.sh` — Create (mkdir-lock lib).
- `adapters/claude-code/hooks/session-start-auto-install.sh` — Modify (gate main body with the debounce; add `SSF_DISABLE=1` to its self-test harness).
- `adapters/claude-code/hooks/session-start-digest.sh` — NOT modified (digest is per-session operator output; gating it would suppress a second concurrent session's summary — see Decisions Log).
- `adapters/claude-code/hooks/harness-doctor.sh` — NOT modified (the digest already reads a cached doctor verdict, so doctor is not re-run per session; nothing to debounce).
- `adapters/claude-code/manifest.json` — Modify (register find-scan-warn.sh + sessionstart-singleflight.sh).
- `docs/backlog.md` — Modify (file deferred rows + §8 bookkeeping reconciliation).
- `docs/decisions/queued-lessons-learned-fixes-2026-07-13.md` — Create (start-plan queued-decisions scaffold for this plan; empty unless a mid-build decision needs async operator override).
- `docs/plans/lessons-learned-fixes-2026-07-13-evidence.md` — Create (task-verifier evidence blocks for this plan's tasks).

## In-flight scope updates
- 2026-07-13: `docs/DECISIONS.md` — the decisions-index-gate requires index consistency when `docs/decisions/035-*.md` is edited (Task 3); the 035 index row also carries the same stale `~/.claude/rules/` pointer, so the fix belongs here too.
- 2026-07-13: `docs/harness-architecture.md` — GENERATED from `manifest.json` via `gen-architecture-doc.sh`; regenerated (not hand-edited) so it reflects the new `find-scan-warn` entry (Task 5), as the doc-gate requires for a new hook.

## Assumptions
- The audit's on-disk evidence (26-agent workflow, every verdict re-verified) is current
  as of `master@ccddda7`; the still-needed set has not changed under me since.
- `merge_settings()` in `session-start-auto-install.sh` will additively land the new
  `find-scan-warn.sh` wiring live on the next SessionStart (self-tested S1
  "settings-self-wire-prepends"); this plan does NOT need to touch live `~/.claude`.
- Each giant hook's existing `--self-test` (scope-enforcement 33 scenarios,
  plan-deletion 18 scenarios) is a faithful behavior oracle: a pre-filter that keeps
  them green has not changed gate behavior.
- `flock` is unreliable/absent under MSYS Git Bash on Windows; the repo's proven
  mkdir-lock pattern (`lib/progress-log-lib.sh`, `master-drift-autocorrect.sh`) is the
  portable primitive.

## Edge Cases
- **Pre-filter must be a strict superset of the trigger.** `scope-enforcement-gate` only
  ever acts on `git commit` segments (always contain literal `commit`); `plan-deletion`
  acts only on rm/mv/clean/stash/checkout/restore/reset. Loose over-matches (e.g.
  `transform` contains no `rm` boundary issue — substring match is intentional superset)
  merely fall through to full processing — never a false skip. Verified by self-tests.
- **stdin consumed once.** The pre-filter reads `CLAUDE_TOOL_INPUT` else `cat` stdin,
  then re-exports `CLAUDE_TOOL_INPUT` so the hook's own downstream input-load doesn't
  block on already-consumed stdin.
- **Single-flight fail-open.** If lock acquisition errors (permissions, disk), the lib
  returns "proceed" not "skip" — a broken lock must never prevent a session from
  starting. Stale locks (holder crashed) are reclaimed by mtime > ttl.
- **Single-flight is advisory.** A skipped auto-install/digest degrades gracefully (the
  session starts without a fresh sync/digest); it does not fail the session.
- **find-warn never blocks.** exit 0 always; a false positive costs one stderr line, not
  a blocked command. Scoped finds (`find .`, `find adapters/`) must stay silent.

## Acceptance Scenarios
n/a — acceptance-exempt: true (harness-dev plan, no product user; the closure target is
the self-test PASS set below, per acceptance-exempt-reason).

## Out-of-scope scenarios
None — all advocate-proposed scenarios are inapplicable to a harness-internal plan.

## Closure Contract
- **Commands that run:** the five artifact `--self-test` invocations listed below, plus `harness-doctor.sh --quick` for the no-new-reds regression check:
  - `bash adapters/claude-code/hooks/scope-enforcement-gate.sh --self-test`
  - `bash adapters/claude-code/hooks/plan-deletion-protection.sh --self-test`
  - `bash adapters/claude-code/hooks/find-scan-warn.sh --self-test`
  - `bash adapters/claude-code/hooks/lib/sessionstart-singleflight.sh --self-test`
  - `bash adapters/claude-code/hooks/harness-doctor.sh --quick`
- **Expected outputs:** every `--self-test` exits 0 (scope 33/33, pdp 18/18, find-warn all-PASS, singleflight race-PASS); `harness-doctor.sh --quick` shows no NEW reds versus the pre-change baseline captured at task start.
- **On-disk artifact location:** `docs/plans/lessons-learned-fixes-2026-07-13-evidence/` (task-verifier per-task evidence) + the completion report appended to this plan file.
- **Done when:** all tasks are `task-verifier` PASS AND every closure-contract self-test is green AND `harness-doctor.sh --quick` shows no regression.

## Testing Strategy
- Tasks 2/3/8 (doc/backlog edits): grep-verify the old string is gone and the new
  string is present; no runtime surface.
- Task 4 (pre-filters): run each giant hook's `--self-test` before and after — must stay
  scope 33/33 and pdp 18/18 (behavior preservation). Additionally, feed a real
  `git commit -m x` (scope) and `rm docs/plans/foo.md` (pdp) input and confirm the gate
  still blocks/acts; feed an `ls -la` input and confirm the fast-path exits 0.
- Task 5 (find-warn): `--self-test` table — `find /`→warn, `find ~`→warn, `find .
  -name x`→silent, `find adapters/`→silent; confirm always exit 0.
- Task 6 (single-flight): `--self-test` spawns N racing acquirers, asserts exactly one
  wins and the losers skip; asserts stale-lock reclaim and fail-open on error.
- Task 7: `harness-reviewer` verdict PASS (or PASS-WITH-CONCERNS, all Critical/Major
  resolved) on the Task-4 + Task-6 diffs.
- Whole-plan: `harness-doctor.sh --quick` no new reds; `manifest.json` claimed==actual.

## Walking Skeleton
Walking Skeleton: n/a — a batch of independent, individually-self-testing harness edits;
there is no single end-to-end user flow to slice. Each task's `--self-test` is its own
vertical proof.

## Decisions Log
- 2026-07-13: **Execution Mode = direct, not orchestrator.** These are surgical,
  file-entangled harness edits (shared `settings.json.template` + `manifest.json` +
  `docs/backlog.md`); parallel worktree builders would conflict on those shared files
  and their claims would need re-verification anyway. The parallelism was correctly
  spent on the 26-agent assessment; implementation is precise single-context surgery.
- 2026-07-13: **Defer rec 4 (dispatcher) + rec 3 (dead-shim removal).** Rationale in
  Scope OUT — high blast radius / removal-needs-live-reconcile respectively. Both filed
  as backlog rows (Task 8) rather than rushed (rushing under pressure is itself the
  anti-pattern the 2026-07-11 lesson documents).
- 2026-07-13: **Single-flight gates auto-install ONLY; digest + doctor-quick NOT gated.**
  The debounce suppresses re-running work across concurrent starts. That is correct for
  `session-start-auto-install.sh` because its product is a SHARED side-effect (syncing
  the one `~/.claude` all sessions read) — the first session's sync covers the rest.
  It is WRONG for `session-start-digest.sh`: the digest is PER-SESSION operator-facing
  output (the SessionStart summary), so debouncing it would leave a second concurrent
  session's operator with no summary at all — a UX regression. And the digest already
  reads a CACHED doctor verdict, so the expensive part isn't re-run per session anyway
  (the assessment called the digest the "lowest-value of the three" to gate). Net: the
  fork-storm's biggest source (auto-install's git fetch + full sync) is gated; the
  per-session summary is preserved. A cheaper-digest optimization is out of scope here.
  Design choice: a ttl-DEBOUNCE (stamp ages out; no release/EXIT-trap) over a held mutex
  — simpler, no release-on-crash hazard, and it also covers the just-finished case.
- 2026-07-13 (post harness-review): **Accepted residuals, named per §8.** (1) The
  single-flight stamp is claimed BEFORE the sync runs, so a session that crashes
  mid-sync leaves a fresh stamp and up to one ttl-window of skipping sessions get its
  partial sync. Accepted over moving the stamp after sync (which would let the first
  concurrent burst all sync — defeating the primary fork-storm benefit): auto-install
  writes per-file with backups and self-repairs on the next non-skipped session.
  (2) The two giant-gate pre-filters match the RAW payload, so a quote/escape-obfuscated
  destructive verb (`r""m`, `git co""mmit`) skips the pre-filter while the full tokenizer
  would block it. Accepted under the accidental-scope/accidental-deletion threat model
  (no human or LLM types `r""m` by accident); the comments were corrected to drop the
  false "strict SUPERSET / NEVER a false skip" claim and each gate now ships a self-test
  scenario that PINS the residual (plan-deletion S19, scope-enforcement S34). Both from
  the harness-reviewer PASS/REFORMULATE verdict (Change 2 PASS; Change 1 REFORMULATE →
  fixed here).

## Definition of Done
- [ ] All tasks checked off
- [ ] All self-tests pass (closure-contract command set)
- [ ] harness-doctor.sh --quick shows no new reds vs. baseline
- [ ] SCRATCHPAD.md updated with final state
- [ ] Completion report appended to this plan file

## Completion Report

_Generated by close-plan.sh on 2026-07-13T20:26:16Z._

### 1. Implementation Summary

Plan: `docs/plans/lessons-learned-fixes-2026-07-13.md` (slug: `lessons-learned-fixes-2026-07-13`).

Files touched (per plan's `## Files to Modify/Create`):

- `adapters/claude-code/hooks/find-scan-warn.sh`
- `adapters/claude-code/hooks/harness-doctor.sh`
- `adapters/claude-code/hooks/lib/sessionstart-singleflight.sh`
- `adapters/claude-code/hooks/plan-deletion-protection.sh`
- `adapters/claude-code/hooks/scope-enforcement-gate.sh`
- `adapters/claude-code/hooks/session-start-auto-install.sh`
- `adapters/claude-code/hooks/session-start-digest.sh`
- `adapters/claude-code/manifest.json`
- `adapters/claude-code/settings.json.template`
- `docs/backlog.md`
- `docs/decisions/035-diagnostic-first-protocol.md`
- `docs/decisions/queued-lessons-learned-fixes-2026-07-13.md`
- `docs/failure-modes.md`
- `docs/lessons/2026-07-11-bulk-shared-state-mutation-without-ownership-check.md`
- `docs/lessons/2026-07-13-agent-efficiency-bottlenecks-process-spawn-and-hook-latency.md`
- `docs/plans/lessons-learned-fixes-2026-07-13-evidence.md`

Commits referencing these files:

```
00293c4 docs(discoveries): triage remaining pending — 4 status flips + 1 current-state note + HARNESS-GAP-50
0090d4b feat(hook): bug-persistence-gate.sh — mechanical enforcement of testing.md rule
0291279 feat(workstreams): shared canonical-state-path resolver — converge 9-file scatter onto one file
038503e fix(D.5 remediation): doctor --full REDs — pr-template repo-root class fix + pin-d command repair, extract-pending runtime repoint (feature was dead live), heartbeat-theater doc honesty — findings 022/023
03a7827 evidence(D.5 addendum): doctor --full LITERAL GREEN 8/8 — first full-sweep green; backlog v64
05db587 chore(wave-o): orchestrator fragment application — manifest, template, consumer-map
0658758 feat(phase-1d-c-2): Task 10 — failure-mode catalog +4 entries (unfrozen-spec-edit, missing-PRD, missing-plan-header-field, missing-behavioral-contracts-at-r3+)
07691d5 feat(conv-tree): Claude-side event emitter — Dispatch conversations auto-populate the GUI
07a114d NL Overhaul Wave E batch 2: E.3 waiver-density, E.4 synthetic-runner, E.5 KPIs, E.6 NEEDS-YOU, E.10 incentive-pin retrofit (#82)
086fcd5 NL Overhaul §E.W integration cutover: template wiring + manifest merge (Wave-E live wiring) (#86)
08a3351 sweep batch 4 + adr061-P1b: verifier flips, set-e class sweep [24], reentry-safe heartbeats (D2), health tick (D6, unarmed) (#97)
099d4e2 feat(phase-1d-c-2): Task 9 — wire prd-validity-gate + spec-freeze-gate into settings.json (template + live)
0b14705 fix(scope-gate): Windows drive-letter git-dir recognized as absolute (+ HARNESS-GAP-27 docs superseded) (#27)
0b56c31 docs(strategy): capture Claude Code quality strategy + backlog gaps
0be6526 feat(hook): A1 — independent goal extraction (UserPromptSubmit + Stop)
0d6bc43 feat(scope-gate): full-skip scope check during rebase/merge conflict resolution (#26)
10adac2 feat(plan-reviewer): land Check 8A — Pre-Submission Audit gate on Mode: design plans
10effe9 verify(wave-o): O.6 flipped by task-verifier — PASS conf 9 (hb_classify fix proven 3 ways; 2 live REDs = truthful estate debt, filed) + auto-triage row
119bd26 fix(wave-o-o6): re-point obs-heartbeats-fresh to the canonical staleness oracle
11c9d13 docs(backlog): correct decision-context finding — bug #3 (Windows node-path) REFUTED; gate core verified working post path-fix + zod (P1->P2)
120593c feat(harness): plan-closure-validator gate + /close-plan skill (HARNESS-GAP-16, Phase 1d-H)
14c4dfc feat(hook): session-start-git-freshness — fetch + behind + WIP-branch warns (#46)
1505d27 fix(gate): repo-scope ownership claims + reviewer minors (harness-review round 1)
17db609 docs(1d-E-1): Decision 021 + backlog cleanup + inventory (Phase 1d-E-1 Task 4)
18270b9 overhaul(B.9): backlog reconciliation pass 1 — mark absorbed items, close 2 already-fixed
18d3911 feat(incentive-map): proactive shift — catalog agent incentives + counter-incentive prompts
1900089 feat(harness): static-trace.sh — auto-detect chain tracer for modified files
19715b9 fix(hooks): F.5 waiver-parity GAP hooks — structured waivers, ADR 059 D4
19a7ab7 Component B reconciler v1 — orchestrator wake-trigger + reconcile loop (single-machine, surface-first) (#58)
19af838 plan(amend): capture-codify — pass-5 generalization sweep + harness-improvement backlog
```

Backlog items absorbed: see plan header `Backlog items absorbed:` field;
the orchestrator can amend this section post-procedure with shipped/deferred
status per item.

### 2. Design Decisions & Plan Deviations

See the plan's `## Decisions Log` section for the inline record. Tier 2+
decisions should each have a `docs/decisions/NNN-*.md` record landed in
their implementing commit per `~/.claude/rules/planning.md`.

### 3. Known Issues & Gotchas

(orchestrator may amend post-procedure)

### 4. Manual Steps Required

(orchestrator may amend post-procedure — env vars, deploys, third-party setup)

### 5. Testing Performed & Recommended

See the plan's `## Testing Strategy` and `## Evidence Log` sections.
This procedure verifies that every task has its declared verification level
satisfied before allowing closure.

### 6. Cost Estimates

(orchestrator may amend; harness-development plans typically have no recurring cost — n/a)
