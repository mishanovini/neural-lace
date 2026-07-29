# Plan: Problems-persist mechanism (inline ledger IDs + Stop-time WARN + operator auto-file)
Status: COMPLETED
Execution Mode: direct
Mode: code
Backlog items absorbed: none
acceptance-exempt: true
acceptance-exempt-reason: Harness-internal mechanism with no product user — the maintainer is the user, and --self-test passing is the demonstration (constitution §4).
tier: 2
rung: 2
architecture: coding-harness
frozen: true
prd-ref: n/a — harness-development
ask-id: none — no linked ask

<!--
Retroactive plan (written after the build, in the same session): the
operator's dispatch (verbatim, 2026-07-29) already specified the full
three-part design in detail — see docs/reviews/2026-07-29-operator-five-
questions.md Q2 and docs/decisions/065-problems-persist-warn-consolidation.md
for the WARN-vs-block reasoning. This plan file exists to satisfy
scope-enforcement-gate.sh (a commit governed by an ACTIVE plan's declared
`## Files to Modify/Create` scope) and to give the work a durable,
closeable record — not as a planning exercise that preceded the build.
lifecycle-schema: v2 intentionally omitted (grandfathered v1 shape): this
plan is opened and closed in the same session with no multi-day ownership
window, so owner/target-completion-date/Closure Contract do not apply.
-->

## Goal

Operator directive (2026-07-29, verbatim): "Can we enforce a system where
anytime you tell me about a problem that should probably be fixed, you
never just allow it to not be addressed? ... I need these concerns to
persist until we actually address them." Constitution §5 already says
bugs/gaps/findings get written to their durable home in the same response
that surfaces them — but filing was entirely discretionary, so the ledger
reflected what a session remembered to file, not what it found. This plan
builds the three-part mechanism that makes an unfiled problem statement
mechanically visible and, where the operator is the one naming it,
mechanically captured.

## User-facing Outcome

The operator can no longer have a raised concern silently vanish because
they didn't have time to read the whole response: (1) every problem
statement in chat now carries its ledger ID inline, so a missing ID is
visible at read time without an audit; (2) if a session ends a turn with
problem-shaped prose and no inline ID, a teaching WARN fires (visible in
the signal ledger + stderr) naming the exact `nl-issue.sh` command to file
it; (3) if the OPERATOR is the one who names a problem in their own prompt
("why is X broken", "critical problem"), it is filed into the nl-issue.sh
ledger automatically, tagged `source: operator-verbatim`, with no session
action required at all.

## Scope

In scope: doctrine amendment (inline ledger IDs), a WARN-only Stop-time
check consolidated into `stop-verdict-dispatcher.sh`, a UserPromptSubmit
splice in `workstreams-read.sh`, the `nl-issue.sh` schema/dedup changes
part 3 depends on, and the portability fix to `_nli_json_field` found
while testing part 3 on this machine's BSD sed (in-scope because it
directly affects the correctness of this build's own new dedup-exemption
logic — see docs/backlog.md `NL-ISSUE-JSON-FIELD-BSD-SED-ALTERNATION-BUG-01`
for the full write-up).

Out of scope: the pre-existing `workstreams-read.sh` Scenario R20 mtime
flake and the `INDEX.md`/manifest.json drift noticed in passing (both
logged to `docs/backlog.md` / `nl-issue.sh`, confirmed pre-existing via
git-stash A/B, not touched here); the broader verification-dispatch
enforcement gap (Q1 of the five-questions review, tracked by its own plan
`docs/plans/verification-dispatch-directive.md`); the 110-file review
backlog (Q5).

## Tasks

- [ ] T1. **Doctrine: inline ledger IDs.** Amend
  `adapters/claude-code/doctrine/findings-ledger.md` establishing that
  every problem statement in operator-facing chat carries its ledger ID
  inline (`NL-FINDING-###`, `NL-ISSUE-###`, or the row's own slug).
  Verification: mechanical (doctrine-text amendment, no runtime behavior
  of its own).

- [ ] T2. **Stop-time WARN check.** Add `_svd_problems_persist_check` to
  `adapters/claude-code/hooks/stop-verdict-dispatcher.sh` (consolidated
  into the existing dispatcher per `docs/decisions/065-problems-persist-
  warn-consolidation.md`, not a new hook file) — scans the final assistant
  message paragraph-by-paragraph for problem vocabulary
  (defect/bug/broken/silently/data loss/root cause) with no inline ledger
  ID, warns (never blocks) with a pre-filled `nl-issue.sh` command.
  Verification: mechanical (harness-internal Stop hook; `--self-test` is
  the demonstration per constitution §4).
  **Prove it works:** `bash adapters/claude-code/hooks/stop-verdict-
  dispatcher.sh --self-test` — scenarios 27-30 exercise unfiled/filed/
  ordinary-prose/multi-paragraph cases; RED-GREEN proven by disabling the
  call site (80/3 fail) then restoring it (83/0 pass).
  **Wire checks:** `adapters/claude-code/hooks/stop-verdict-dispatcher.sh`
  `_svd_main` → `_svd_problems_persist_check` → `_svd_paragraph_is_problem_shaped`
  / `_svd_paragraph_has_ledger_id` → `_svd_ledger "warn"`.
  **Integration points:** signal ledger (`lib/signal-ledger.sh`'s
  `ledger_emit`) — verified via `grep '"gate":"stop-verdict-dispatcher".*problems-persist' <ledger>` in self-test scenarios 27/30.

- [ ] T3. **Operator-named auto-file.** Add `_problem_capture_on_prompt`
  splice to `adapters/claude-code/hooks/workstreams-read.sh` (following its
  existing ASK-CAPTURE splice precedent, zero new settings.json entries),
  plus the `source` field / dedup-exemption / BSD-sed portability fix in
  `adapters/claude-code/scripts/nl-issue.sh` it depends on.
  Verification: mechanical (harness-internal UserPromptSubmit splice;
  `--self-test` is the demonstration).
  **Prove it works:** `bash adapters/claude-code/hooks/workstreams-read.sh
  --self-test` (scenarios PC1-PC4) and `bash adapters/claude-code/scripts/
  nl-issue.sh --self-test` (scenarios 11-15) — RED-GREEN proven by
  disabling the splice call site (58/5 fail) then restoring it (62/1 pass,
  the 1 being the pre-existing unrelated R20 flake).
  **Wire checks:** `adapters/claude-code/hooks/workstreams-read.sh`
  `_run_read` → `_problem_capture_on_prompt` → `_nli_capture_cli_path` →
  `adapters/claude-code/scripts/nl-issue.sh` `nli_append` (NLI_SOURCE=operator-verbatim).
  **Integration points:** `nl-issue.sh`'s ledger at `$NL_ISSUES_PATH` —
  verified via `grep '"source":"operator-verbatim"'` in nl-issue.sh
  self-test scenarios 12-15.

## Files to Modify/Create

- `adapters/claude-code/doctrine/findings-ledger.md` — inline-ledger-ID doctrine amendment (T1).
- `adapters/claude-code/hooks/stop-verdict-dispatcher.sh` — PROBLEMS-PERSIST WARN check + self-test scenarios 27-30 (T2).
- `adapters/claude-code/hooks/workstreams-read.sh` — PROBLEM-CAPTURE splice + self-test scenarios PC1-PC4 (T3).
- `adapters/claude-code/scripts/nl-issue.sh` — `source` field, dedup exemption, BSD-sed portability fix, self-test scenarios 11-15 (T3).
- `adapters/claude-code/manifest.json` — `honest_status` updates on `stop-verdict-dispatcher`, `workstreams-emitters`, `nl-issue-capture-loop` entries (no new entries, no budget-class changes).
- `docs/backlog.md` — two pre-existing, unrelated findings noticed in passing (nl-issue.sh BSD-sed bug — since fixed — and workstreams-read.sh R20 flake).
- `docs/decisions/065-problems-persist-warn-consolidation.md` — Decisions-Log entry for the WARN-vs-block / file-placement choice (created alongside this plan).

## Assumptions

- The operator's five-questions review (`docs/reviews/2026-07-29-operator-
  five-questions.md`, reachable via `git show 1a2ba8a:...` from this
  worktree's lineage) is the authoritative design source; this plan does
  not re-litigate its content.
- `stop-verdict-dispatcher.sh` is confirmed the live Stop-chain entry point
  (verified: `adapters/claude-code/settings.json.template`'s `Stop` array
  wires it directly; the three member gates are invoked internally via
  `--report` mode, not as separate settings.json entries) — this is the
  premise the WARN-consolidation decision rests on.
- `blocking session-event units` measured 14/14 in this worktree's own
  `manifest.json` (not 16/14 as the original dispatch prompt cited) —
  likely a different measurement surface (live `~/.claude/manifest.json`
  vs this worktree's repo copy; harness-doctor.sh confirmed 16/14 against
  the LIVE manifest during this same session). Either number supports the
  same conclusion: zero headroom for a new blocking unit.

## Edge Cases

- A problem-shaped paragraph split across the Stop-time check's paragraph
  boundary from its citing ID (ID in an adjacent paragraph, not the same
  one) still warns — a known, accepted false-positive documented in the
  check's own header (start narrow, precision over recall).
- An operator prompt containing the named vocabulary as an aside, not a
  real problem report (e.g., "why is the sky blue" mid-conversation),
  still files a row — accepted; `nl-issue.sh --triage <n> wontfix <reason>`
  is the correct disposition, not a smarter heuristic that risks missing
  real reports.
- Pre-existing `nl-issues.jsonl` lines with no `source` field read as
  `"session"` by every consumer (nli_list, nli_triage) — additive schema
  change, verified backward compatible.
- An operator-verbatim row is exempted from dedup in BOTH directions
  (never a merge target, never merged from) — verified by nl-issue.sh
  self-test scenarios 13-14.

## Testing Strategy

Every part is harness-internal (Verification: mechanical) — the test IS
the artifact's own `--self-test`, run under BOTH `/opt/homebrew/bin/bash`
(5.3) and `/bin/bash` (3.2.57, the portability floor), per file:

- `stop-verdict-dispatcher.sh --self-test`: 83/0 both interpreters.
- `nl-issue.sh --self-test`: 32/0 both interpreters (was 13/11 pre-fix;
  the BSD-sed regex bug explains all 11 pre-existing failures).
- `workstreams-read.sh --self-test`: 62/1 both interpreters (the 1 is
  the pre-existing, unrelated R20 mtime flake — confirmed via git-stash
  A/B on the unmodified file, filed in docs/backlog.md).

RED-GREEN mutation proof for every new check (not just "tests pass"):
disabling each new call site (via a temporary comment-out, restored
immediately after) reproduces the exact pre-fix failure count, proving
the self-test scenarios exercise the real behavior, not a vacuous pass.

## Evidence Log

### Task T1 — Doctrine: inline ledger IDs
Verdict: PASS
commit: bdb3295
`adapters/claude-code/doctrine/findings-ledger.md` amended with the
"Inline ledger IDs" section (NL-FINDING-###/NL-ISSUE-###/slug convention).
Doctrine-text only, no runtime behavior of its own to self-test.

### Task T2 — Stop-time WARN check
Verdict: PASS
commit: bdb3295
`bash adapters/claude-code/hooks/stop-verdict-dispatcher.sh --self-test`:
83 passed, 0 failed under both `/opt/homebrew/bin/bash` (5.3) and
`/bin/bash` (3.2.57). RED-GREEN mutation proof: commenting out the
`_svd_problems_persist_check "$transcript_path"` call site in `_svd_main`
reproduces 80 passed / 3 failed (exactly scenarios 27's/30's
warn-requires-the-check assertions), restoring the call site returns
83/0.

### Task T3 — Operator-named auto-file
Verdict: PASS
commit: bdb3295
`bash adapters/claude-code/hooks/workstreams-read.sh --self-test`: 62
passed, 1 failed (the 1 is the pre-existing, unrelated R20 mtime flake —
confirmed via `git stash` A/B against the unmodified file, same 57/1
result) under both bash interpreters. `bash adapters/claude-code/scripts/
nl-issue.sh --self-test`: 32 passed, 0 failed under both interpreters (was
13/11 before the BSD-sed `_nli_json_field` portability fix this task also
required). RED-GREEN mutation proof: commenting out the
`_problem_capture_on_prompt "$input" "$sid"` call site in `_run_read`
reproduces 58 passed / 5 failed (exactly the PC1/PC3/PC4 assertions
requiring the splice to fire), restoring it returns 62/1.

## Closure

All three tasks are built, self-tested (including RED-GREEN mutation
proof) under both bash interpreters, and committed at bdb3295. Closeable
via the `close-plan` skill (harness-internal → Verification: mechanical
routing; no runtime instance beyond `--self-test` to exercise).

## Completion Report

_Generated by close-plan.sh on 2026-07-29T21:18:47Z._

### 1. Implementation Summary

Plan: `docs/plans/problems-persist-mechanism.md` (slug: `problems-persist-mechanism`).

Files touched (per plan's `## Files to Modify/Create`):

- `adapters/claude-code/doctrine/findings-ledger.md`
- `adapters/claude-code/hooks/stop-verdict-dispatcher.sh`
- `adapters/claude-code/hooks/workstreams-read.sh`
- `adapters/claude-code/manifest.json`
- `adapters/claude-code/scripts/nl-issue.sh`
- `docs/backlog.md`
- `docs/decisions/065-problems-persist-warn-consolidation.md`

Commits referencing these files:

```
00293c4 docs(discoveries): triage remaining pending — 4 status flips + 1 current-state note + HARNESS-GAP-50
00d5db8 feat(cold-reader-lint): decision-entry lint, WARN-only (constitution §3 amendment 53d3bee)
038503e fix(D.5 remediation): doctor --full REDs — pr-template repo-root class fix + pin-d command repair, extract-pending runtime repoint (feature was dead live), heartbeat-theater doc honesty — findings 022/023
03a7827 evidence(D.5 addendum): doctor --full LITERAL GREEN 8/8 — first full-sweep green; backlog v64
05db587 chore(wave-o): orchestrator fragment application — manifest, template, consumer-map
0758232 fix(harness): ask-id sentinel class — extend the '<'-placeholder guard to the literal 'none' spelling (re-review REFORMULATE fixes)
086fcd5 NL Overhaul §E.W integration cutover: template wiring + manifest merge (Wave-E live wiring) (#86)
0b14705 fix(scope-gate): Windows drive-letter git-dir recognized as absolute (+ HARNESS-GAP-27 docs superseded) (#27)
0b56c31 docs(strategy): capture Claude Code quality strategy + backlog gaps
1007841 fix(review-record): surface-vs-enforcement parity (REFORMULATE finding 1)
10adac2 feat(plan-reviewer): land Check 8A — Pre-Submission Audit gate on Mode: design plans
10effe9 verify(wave-o): O.6 flipped by task-verifier — PASS conf 9 (hb_classify fix proven 3 ways; 2 live REDs = truthful estate debt, filed) + auto-triage row
11c9d13 docs(backlog): correct decision-context finding — bug #3 (Windows node-path) REFUTED; gate core verified working post path-fix + zod (P1->P2)
123dcaa fix-trivial(agent-efficiency T5): correct the hook-shim backlog row honesty gap
1397c34 feat(continuous-operation): supervisor-tick — orphan detection + alerting (squash of build/supervisor-tick)
1505d27 fix(gate): repo-scope ownership claims + reviewer minors (harness-review round 1)
15afcb2 plan(harness-governance-batch): open batch plan + follow-up handoff + decision 063 + ws-UI status-page reference
17db609 docs(1d-E-1): Decision 021 + backlog cleanup + inventory (Phase 1d-E-1 Task 4)
18270b9 overhaul(B.9): backlog reconciliation pass 1 — mark absorbed items, close 2 already-fixed
18d3911 feat(incentive-map): proactive shift — catalog agent incentives + counter-incentive prompts
18e8f65 feat(cockpit-roadmap-redesign): R11 hierarchy renderer — master/child tree, batches, active-path expansion, four-bucket strip (builder squash + orchestrator gap-closures)
19af838 plan(amend): capture-codify — pass-5 generalization sweep + harness-improvement backlog
1a452d3 HARNESS-GAP-45: decorative config controls as a named, checked vaporware class (#100)
1a67d05 docs(handoff): SCRATCHPAD + roadmap + backlog + discovery state for next-session pickup
1b708c0 plan(evidence-bar-enforcement) + feat(gates): agent-commit-gate (GATE 3, SubagentStop) — builder cannot end with uncommitted work
1b738fb feat(wave-o): O.1 emit extension + turn-traces + consumer map
1d485de plan(1d-F): definition-on-first-use enforcement (sub-gap G absorbed)
1d80926 feat(model-pin): PreToolUse gate blocking silent model-inherit + doctrine (Task 3+5)
1e0a515 feat(F.L): WARN-only functional-link check in stop-verdict-dispatcher.sh
1fa7fd9 build(R3): gh-merge canonical write-discipline gate + retire sync-pt-to-personal.sh
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
