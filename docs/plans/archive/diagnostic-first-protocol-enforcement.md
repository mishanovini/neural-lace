# Plan: Diagnostic-first protocol + hypothesis-vs-proof labeling enforcement
Status: COMPLETED
Execution Mode: orchestrator
Mode: code
tier: 2
rung: 1
architecture: pattern
frozen: true
prd-ref: n/a — harness-development
acceptance-exempt: true
acceptance-exempt-reason: harness-internal rule + lessons-doc work; the "user" is the maintainer running future sessions, and the verification artifact is the new rule files loading via the harness boot path plus self-test grep against CLAUDE.md
Backlog items absorbed: none
Work-shape: build-harness-infrastructure (every file under `adapters/claude-code/`, `~/.claude/` mirror, or `docs/` of the neural-lace repo)

## Goal

Bake three protocols into the harness rules system so they apply by default in every future Claude session, including the Dispatch orchestrator, without requiring memory or willpower:

1. **Diagnostic-first protocol** — first tool call on any production-failure investigation MUST be a runtime / error-log pull; inferential evidence is permitted only AFTER actual logs are examined or after an explicit "logs are inaccessible because X" acknowledgment with a concrete reason.
2. **Hypothesis-vs-proof labeling** — every causal claim must be tagged PROVEN (with cited evidence) or HYPOTHESIZED (with refutation criterion); naked confident phrasing is prohibited.
3. **Refutation-criteria requirement** — before authoring an implementation plan on top of a hypothesis, explicitly write what observable evidence would refute the hypothesis, and look for that evidence before committing engineering resources.

Originating context: 8+ days of FM-001 misdiagnosis chronicled at the originating downstream project's `docs/reviews/fm-001-rigorous-diagnosis-2026-05-22.md` (the downstream project is intentionally unnamed in harness docs per harness-hygiene policy; the harness-side case-study recap is `docs/lessons/2026-05-22-fm-001-misdiagnosis.md`). Confidence-sounding causal narrative ("Lambda 10s INIT cap cold-init deadlock") was built from bisect correlation and code reading; runtime logs were never pulled. The actual error (`You cannot use different slug names for the same dynamic path ('id' !== 'orgId')`) was sitting in `vercel logs` the whole time, appearing 1760 times in 2000 log lines on the broken deployment. A friend running `vercel logs --since 24h --limit 2000 --json` found it in ~30 seconds. Misha repeatedly course-corrected the orchestrator in chat across multiple sessions; the corrections didn't persist because chat is not the harness's durable rule layer. The fix is rule files in `~/.claude/rules/` (auto-loaded into every session) plus a pointer in `CLAUDE.md` so the rules are discoverable.

## User-facing Outcome

The "user" for this harness work is the maintainer (Misha) running future investigation sessions. After this plan ships:

- Any future session (interactive, orchestrator-dispatched, or Dispatch-spawned) that begins investigating a production failure has `diagnosis.md` (the diagnostic-first protocol) and `claims.md` (hypothesis-vs-proof labeling + refutation criteria) loaded into its context per the harness boot path documented in `~/.claude/CLAUDE.md`.
- The session can be observed in its tool-call sequence: the first investigation tool call is a runtime-log retrieval (`vercel logs`, Sentry query, etc.) or a substantive in-band "logs inaccessible because X" acknowledgment.
- Status updates emit each causal claim tagged PROVEN (with citation) or HYPOTHESIZED (with refutation criterion); naked phrasing like "X is caused by Y" without a tag does not appear.
- A plan authored on top of a hypothesis carries an explicit `Refutation criterion:` line.

Demonstrable by: a session prompted with "investigate this 504 on /api/foo" produces, as its first tool call, a log retrieval. Reproduce by re-reading the rule files via `grep -l "DIAGNOSTIC-FIRST" ~/.claude/rules/*.md` and verifying they're referenced from `~/.claude/CLAUDE.md` "Detailed Protocols" block.

## Scope

- **IN:**
  - Extend `adapters/claude-code/rules/diagnosis.md` with a new "Diagnostic-First Protocol" section at the top of the file (before the FM-catalog reflex, since pulling logs reveals the symptom the catalog grep then keys on).
  - Create `adapters/claude-code/rules/claims.md` combining Task 2 (hypothesis-vs-proof labeling) and Task 3 (refutation-criteria requirement) from the user spec.
  - Extend `adapters/claude-code/agents/plan-phase-builder.md` with the 3-clause investigation-work requirement from Task 4 of the user spec.
  - Update `adapters/claude-code/CLAUDE.md` "Detailed Protocols" list with a pointer to `claims.md` and a refreshed pointer to `diagnosis.md` mentioning the new diagnostic-first section.
  - Extend `adapters/claude-code/rules/vaporware-prevention.md` enforcement map with rows pointing at `claims.md` and the new `diagnosis.md` section.
  - Append `FM-029` to `docs/failure-modes.md` cataloging the failure class ("Investigation proceeds from inferential evidence without first capturing runtime/error logs from the affected system").
  - Author `docs/decisions/035-diagnostic-first-protocol.md` ADR locking the rule.
  - Add an index row to `docs/DECISIONS.md`.
  - Author `docs/lessons/2026-05-22-fm-001-misdiagnosis.md` with case-summary + 6 root causes + cross-links + discriminator (Task 6 of user spec).
  - Sync all `adapters/claude-code/` changes to live `~/.claude/` mirror per `harness-maintenance.md`.
- **OUT:**
  - No new PreToolUse hook gating "first tool call must be a log pull" (mechanical detection of "this session is investigating a production failure" is itself a hypothesis; the rule is Pattern-class with the operator's interrupt authority as backstop).
  - No changes to other rule files than diagnosis.md / claims.md / vaporware-prevention.md / CLAUDE.md.
  - No changes to downstream-product repos — they inherit via the harness load path.
  - No edits to the existing FM-001 catalog entry (that's a separate decision; this plan's FM-029 is the meta-class about HOW the misdiagnosis happened, not about FM-001's substance).

## Tasks

- [ ] 1. Author `docs/lessons/2026-05-22-fm-001-misdiagnosis.md` (case summary + 6 root causes + harness changes + discriminator) — Verification: mechanical
- [ ] 2. Author `docs/decisions/035-diagnostic-first-protocol.md` ADR + add row to `docs/DECISIONS.md` — Verification: mechanical
- [ ] 3. Append `FM-029` entry to `docs/failure-modes.md` — Verification: mechanical
- [ ] 4. Extend canonical `adapters/claude-code/rules/diagnosis.md` with "Diagnostic-First Protocol" section — Verification: mechanical
- [ ] 5. Create canonical `adapters/claude-code/rules/claims.md` (hypothesis-vs-proof + refutation-criteria) — Verification: mechanical
- [ ] 6. Extend canonical `adapters/claude-code/agents/plan-phase-builder.md` with 3-clause investigation-work requirement — Verification: mechanical
- [ ] 7. Update canonical `adapters/claude-code/CLAUDE.md` "Detailed Protocols" list — Verification: mechanical
- [ ] 8. Extend canonical `adapters/claude-code/rules/vaporware-prevention.md` enforcement map with two new rows — Verification: mechanical
- [ ] 9. Sync all canonical changes to `~/.claude/` mirror; verify byte-identical via `diff -q` — Verification: mechanical
- [ ] 10. Commit feature branch + PR + merge to master per pre-customer auto-merge directive — Verification: mechanical

## Files to Modify/Create

- `docs/lessons/2026-05-22-fm-001-misdiagnosis.md` — new lessons-learned doc
- `docs/decisions/035-diagnostic-first-protocol.md` — new ADR
- `docs/DECISIONS.md` — index row added
- `docs/failure-modes.md` — FM-029 entry appended
- `adapters/claude-code/rules/diagnosis.md` — new "Diagnostic-First Protocol" section
- `adapters/claude-code/rules/claims.md` — new file
- `adapters/claude-code/agents/plan-phase-builder.md` — new "Investigation-work mandate" section
- `adapters/claude-code/CLAUDE.md` — Detailed Protocols list updated
- `adapters/claude-code/rules/vaporware-prevention.md` — enforcement map rows
- `~/.claude/rules/diagnosis.md` — mirror sync
- `~/.claude/rules/claims.md` — mirror sync (new file)
- `~/.claude/agents/plan-phase-builder.md` — mirror sync
- `~/.claude/CLAUDE.md` — mirror sync
- `~/.claude/rules/vaporware-prevention.md` — mirror sync

## In-flight scope updates

(none yet)

## Assumptions

- The harness boot path documented in `~/.claude/CLAUDE.md` (system-instructions reference) loads every `*.md` file in `~/.claude/rules/` contextually into every Claude session. Verified by direct observation: the current session has all 39 existing `rules/*.md` files visible in its system context.
- `claims.md` as a new file name does not collide with any existing rule. Verified: `ls ~/.claude/rules/` and `ls adapters/claude-code/rules/` — no `claims.md` present.
- The active plans on master (`conv-tree-ui-v1.1.2-polish`, `misha-decision-batch-handoff-2026-05-20`, `tranche-4-canonical-pilot-handoff`) do NOT declare any of this plan's `## Files to Modify/Create` paths in their own scope — so `scope-enforcement-gate.sh` will not fire on commits to those paths. (To verify before commit: `grep -l "rules/diagnosis.md\|rules/claims.md\|plan-phase-builder.md" docs/plans/*.md`.)
- Pre-customer auto-merge directive applies (per `~/.claude/rules/git.md`): once green on the feature branch, auto-merge to master without pausing for explicit authorization.

## Edge Cases

- **Diagnostic-first rule applies to "production failure" — what counts?** The rule is scoped to "anything where a deployed system is misbehaving." A unit-test failure does NOT trigger the rule; a 504 on a live endpoint does. The rule body enumerates concrete classes (web app, API, database, external integration) to make the boundary mechanical.
- **What if logs are genuinely inaccessible?** The rule allows inferential evidence "after explicit acknowledgment in the response of 'logs are inaccessible because X' with a concrete reason." This is the escape hatch for situations like provider outages, missing credentials, or self-hosted systems without log infrastructure. The escape requires substantive justification — a perfunctory "logs aren't easy" doesn't qualify.
- **Hypothesis-vs-proof labeling cost.** Every claim being tagged adds friction. The rule scopes this to "causal claims in a status update, report, or session output" — not every sentence. Descriptive statements ("I read the file") don't need tags; causal statements ("the file was missing because X") do.
- **Refutation criteria are sometimes unknowable upfront.** When a hypothesis is genuinely the only viable starting point and no refutation criterion is obvious, the rule says "the hypothesis is not falsifiable and the plan is built on speculation." The required action is to surface this honestly: either find a refutation criterion before plan-authoring, or note explicitly "no refutation criterion identified — plan is speculative-prior-to-evidence."
- **CLAUDE.md sync drift.** The mirror at `~/.claude/CLAUDE.md` and the canonical at `adapters/claude-code/CLAUDE.md` are independent files on Windows. The session-start `[settings-divergence]` warning suggests they may already drift on `settings.json`. Verify byte-identical AFTER editing CLAUDE.md to prevent further drift.

## Testing Strategy

- **Task 1 (lessons doc):** file exists at the declared path with the required six sections (case summary, 6 root causes, harness changes with file refs, discriminator). `test -f docs/lessons/2026-05-22-fm-001-misdiagnosis.md && grep -c "^## " docs/lessons/2026-05-22-fm-001-misdiagnosis.md` returns ≥ 4.
- **Task 2 (ADR):** ADR file exists; `docs/DECISIONS.md` has a new row pointing to it.
- **Task 3 (FM-029):** `grep -n "## FM-029" docs/failure-modes.md` returns one line; the six fields (Symptom, Root cause, Detection, Prevention, Example, Discriminator, Recovery) are populated.
- **Task 4 (diagnosis.md):** `grep -n "DIAGNOSTIC-FIRST PROTOCOL" adapters/claude-code/rules/diagnosis.md` returns one line.
- **Task 5 (claims.md):** file exists at `adapters/claude-code/rules/claims.md` AND contains both "HYPOTHESIS-VS-PROOF LABELING" and "REFUTATION-CRITERIA REQUIREMENT" sections.
- **Task 6 (plan-phase-builder):** `grep -n "Investigation-work mandate\|runtime/error logs" adapters/claude-code/agents/plan-phase-builder.md` returns lines.
- **Task 7 (CLAUDE.md):** `grep -n "claims.md" adapters/claude-code/CLAUDE.md` returns a line in the Detailed Protocols block.
- **Task 8 (vaporware-prevention.md):** `grep -nE "claims\.md|diagnostic-first" adapters/claude-code/rules/vaporware-prevention.md` returns ≥ 2 lines.
- **Task 9 (sync):** `diff -q ~/.claude/rules/claims.md adapters/claude-code/rules/claims.md` returns no output for every modified file.
- **Task 10 (merge):** PR opened, CI green (no CI required for harness-only changes — only the pre-commit hooks), merged to master, master pushed.

## Walking Skeleton

The thinnest end-to-end slice is the rule files themselves loading into a future session's context. Verification at landing: open a fresh Claude session in a different worktree, observe whether the system reminder lists `claims.md` among the loaded rules. (Mechanically equivalent: grep the live session's CLAUDE.md context for `claims.md` and `DIAGNOSTIC-FIRST`.) That round-trip is the whole architecture.

## Decisions Log

### Decision: Single new rule file (claims.md) for Tasks 2+3 vs two separate files
- **Tier:** 1 (Continue + Document — reversible; can be split later)
- **Status:** proceeded with recommendation
- **Chosen:** Combine hypothesis-vs-proof labeling and refutation-criteria requirement into a single `claims.md`.
- **Alternatives:** (a) two files (`claims-labeling.md` + `claims-refutation.md`) — finer-grained but duplicates the discoverability cost in CLAUDE.md, and the rules are about the same surface (causal claims). (b) extend `diagnosis.md` further — diagnosis.md already covers WHEN/WHERE to investigate; claims.md covers WHAT TO WRITE about findings. Different scopes warrant separate files.
- **Reasoning:** Both rules govern causal claims. A single file with two named sections gives the rules a unified home and one entry in CLAUDE.md, which keeps the discoverability layer thin.
- **Checkpoint:** N/A (Tier 1)
- **To reverse:** split `claims.md` into two files; add a second pointer in CLAUDE.md.

### Decision: Diagnostic-First section placed at TOP of diagnosis.md (before FM-catalog reflex)
- **Tier:** 1
- **Status:** proceeded with recommendation
- **Chosen:** New section goes ABOVE the existing "Check the Failure-Mode Catalog Before Forming a Hypothesis" section.
- **Alternatives:** (a) append at the bottom — would not be the first instruction encountered when a session reads the rule. (b) replace the FM-catalog section — the two are complementary, not redundant (pull logs to OBSERVE the symptom precisely; then grep the catalog with those precise keywords).
- **Reasoning:** Order matters here. Logs reveal the symptom signature; the FM catalog grep is most useful when the symptom is precise. "Pull logs first" is therefore upstream of "grep catalog." Placing it at the top makes the read order match the protocol order.
- **Checkpoint:** N/A
- **To reverse:** move the section; one Edit operation.

### Decision: Pattern enforcement, no PreToolUse hook
- **Tier:** 2 (Continue + Checkpoint — touches the enforcement-map's class boundaries)
- **Status:** proceeded with recommendation
- **Chosen:** All three protocols are documented as Pattern-class rules (self-applied), not Mechanism-class hooks. Add to enforcement map clearly labeled as Pattern.
- **Alternatives:** (a) add a PreToolUse hook that detects "is this an investigation session" and asserts the first tool call is a log pull — but detection requires the agent to self-classify the session type, which is exactly the failure mode chat-level enforcement has. (b) add a Stop hook that scans the transcript for unlabeled causal claims and blocks — but distinguishing "causal claim" from "descriptive statement" is non-trivial for a regex and would generate false positives.
- **Reasoning:** Mechanism-class enforcement requires a stable detection signal. The signal here ("the session is investigating a production failure" / "this sentence is a causal claim") is not mechanically observable without LLM-grade reading at hook fire time. Pattern enforcement with the operator's interrupt authority as backstop is the correct shape for now. An ADR (Decision 035) locks the choice; if a stable detection signal emerges, a future hook can land as an extension.
- **Checkpoint:** commit after the canonical rule files land, before the mirror sync.
- **To reverse:** the rules remain valuable as documentation even if mechanization later supersedes them.

## Definition of Done

- [ ] All 10 tasks checked off
- [ ] `diff -q` between canonical and mirror returns no differences for every modified file
- [ ] Mirror's `~/.claude/CLAUDE.md` references `claims.md` in the Detailed Protocols list
- [ ] FM-029 appears in the live catalog
- [ ] ADR 035 appears in `docs/DECISIONS.md`
- [ ] Lessons doc cross-links from FM-029 + ADR 035 + diagnosis.md's new section
- [ ] Completion report appended
- [ ] Status flipped to COMPLETED → auto-archival fires
- [ ] Merged to master

## Completion Report

_Generated by close-plan.sh on 2026-05-22T23:52:22Z._

### 1. Implementation Summary

Plan: `docs/plans/diagnostic-first-protocol-enforcement.md` (slug: `diagnostic-first-protocol-enforcement`).

Files touched (per plan's `## Files to Modify/Create`):

- `adapters/claude-code/CLAUDE.md`
- `adapters/claude-code/agents/plan-phase-builder.md`
- `adapters/claude-code/rules/claims.md`
- `adapters/claude-code/rules/diagnosis.md`
- `adapters/claude-code/rules/vaporware-prevention.md`
- `docs/DECISIONS.md`
- `docs/decisions/035-diagnostic-first-protocol.md`
- `docs/failure-modes.md`
- `docs/lessons/2026-05-22-fm-001-misdiagnosis.md`
- `~/.claude/CLAUDE.md`
- `~/.claude/agents/plan-phase-builder.md`
- `~/.claude/rules/claims.md`
- `~/.claude/rules/diagnosis.md`
- `~/.claude/rules/vaporware-prevention.md`

Commits referencing these files:

```
03e4883 feat(harness): credentials inventory mechanism for cross-session auth visibility
0658758 feat(phase-1d-c-2): Task 10 — failure-mode catalog +4 entries (unfrozen-spec-edit, missing-PRD, missing-plan-header-field, missing-behavioral-contracts-at-r3+)
0909869 feat(work-shapes): Tranche C — work-shape library + rule + integrations
0be6526 feat(hook): A1 — independent goal extraction (UserPromptSubmit + Stop)
0c1c4d8 docs(adr): ADR-032 — conversation-tree JSON state-schema field-layout contract (Task A1)
0f34109 feat(phase-1d-c-3): Tasks 1+2+6 — Decision 019 + findings-template + findings-ledger rule + docs/findings.md bootstrap
10adac2 feat(plan-reviewer): land Check 8A — Pre-Submission Audit gate on Mode: design plans
120593c feat(harness): plan-closure-validator gate + /close-plan skill (HARNESS-GAP-16, Phase 1d-H)
167a188 feat(harness): class-aware reviewer feedback contract (Mods 1+3)
17db609 docs(1d-E-1): Decision 021 + backlog cleanup + inventory (Phase 1d-E-1 Task 4)
18d3911 feat(incentive-map): proactive shift — catalog agent incentives + counter-incentive prompts
19bb3fc feat: B-DEC-D — resolve NL-FINDING-003 per DEC-D = option (d) snapshot-integrity attestation (REPLACES (b))
25465b6 feat(phase-1d-c-3): Tasks 5+7 — wire findings-ledger-schema-gate + FM-022 + vaporware-prevention enforcement-map
2fa15d8 docs(adr): ADR-031 r2 — harden after systems-designer Phase-3 FAIL
343d5c6 docs(vaporware-prevention): add enforcement-map row for spawn_task report-back (GAP-08 Task 4)
35ee3df feat(harness): mechanical evidence substrate (Tranche B)
3f3b2e9 feat(harness): Tranche G — calibration loop bootstrap
460519e feat(build-doctrine): Tranche 5a-integration ritual wired audit analyzer pilot template
46616ba feat(build-doctrine): Tranche 6a — propagation engine framework + 8 starter rules + audit log
4ae6f46 fix: B-DEC-D r2.1 — §8 sole-normative library verifier + real-path P14 (systems-designer FAIL)
50d670d feat(harness): integration-verification gate — plan-time Check 13 + runtime wire-check-gate
51016b9 feat(harness): context-aware permission gates — session-wrap worktree fall-back + local-edit authorization
5161a4c docs(adr): ADR-031 r3 — stakeholder struck Option 4; option space now 1/2/3
549f70d feat(plan #4): Phase A complete — research-substitute investigation + Tier 2 decision record 011
54aac98 docs(adr): ADR-031 Conversation Tree UI architecture — Phase 3 proposed
55742f2 docs(rules): SCRATCHPAD triggers (Rule 2) + review-finding IDs (Rule 4) + memory last_verified (Rule 7)
566ffa6 feat(harness): D1-D5 educational re-do follow-through (Decision 014, GAP-12, gitignore fix)
588b6db verify(pre-submission-audit): reconcile stranded plan — Tasks 1-4 evidence + FM-007 SHA fix
5938a69 feat(tranche-e): deterministic close-plan procedure
605b81a docs(adr): ADR 033 — FM catalog as cross-project convention on canonical schema
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
