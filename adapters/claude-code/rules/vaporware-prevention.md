# Anti-Vaporware Rule (Stub — enforcement is in hooks)

**Rule:** a feature is not done until the user's actual path has been exercised at runtime.

This file is intentionally short. The enforcement lives in hooks, not prose. If a rule below isn't backed by a hook, it's theater.

## Enforcement map (hook-backed)

Every row below points at an artifact that exists on disk. If you notice
a row whose File column doesn't resolve, STOP and either (a) create the
file or (b) delete the row. Advertising hallucinated enforcement was the
single biggest hole in the first Gen 4 pass.

| Rule | Hook / agent that enforces it | File |
|---|---|---|
| Runtime files require tests (new + modified) | `pre-commit-tdd-gate.sh` diff-symbol scan (Layer 1-2) | `~/.claude/hooks/pre-commit-tdd-gate.sh` |
| Integration tests cannot mock | `pre-commit-tdd-gate.sh` mock ban (Layer 3) | same |
| Tests cannot use trivial assertions alone | `pre-commit-tdd-gate.sh` trivial-assertion ban (Layer 4) | same |
| Plan checkboxes cannot be self-flipped | `plan-edit-validator.sh` evidence-first protocol | `~/.claude/hooks/plan-edit-validator.sh` |
| Runtime verification entries must be replayable commands | `runtime-verification-executor.sh` parser + executor | `~/.claude/hooks/runtime-verification-executor.sh` |
| Runtime verification must correspond to the feature | `runtime-verification-reviewer.sh` cross-reference hook | `~/.claude/hooks/runtime-verification-reviewer.sh` |
| Plans must have runtime verification specs | `plan-reviewer.sh` bash heuristics (invoked from pre-commit-gate) | `~/.claude/hooks/plan-reviewer.sh` |
| Plain-text manual verification is rejected | `task-verifier` agent + pre-stop-verifier Check 4 | `~/.claude/agents/task-verifier.md` |
| Session-end plan integrity sweep | `pre-stop-verifier.sh` + `plan-evidence-reviewer` agent | `~/.claude/hooks/pre-stop-verifier.sh` |
| Tool-call budget forces periodic audit | `tool-call-budget.sh` PreToolUse blocker (every 30 Edit/Write/Bash calls) | `~/.claude/hooks/tool-call-budget.sh` |
| Product Q&A claims need file:line citations | `claim-reviewer` agent + `verify-feature` skill (self-invoked, residual risk) | `~/.claude/agents/claim-reviewer.md` + `~/.claude/skills/verify-feature.md` |
| PRs with high docs/config volume but zero execution evidence are blocked | `vaporware-volume-gate.sh` PreToolUse on `gh pr create` (A8 — Gen 6) | `~/.claude/hooks/vaporware-volume-gate.sh` |
| First-message goal extraction with checksummed integrity (tamper-detected; covers UNHONORED user goals) | `goal-extraction-on-prompt.sh` UserPromptSubmit + `goal-coverage-on-stop.sh` Stop hook (A1 — Gen 6) | `~/.claude/hooks/goal-extraction-on-prompt.sh` + `~/.claude/hooks/goal-coverage-on-stop.sh` |
| Builder commits cannot extend scope beyond plan's declared `## Files to Modify/Create` OR `## In-flight scope updates` sections. Block-message presents three tiered options: (1) update plan's in-flight-scope-updates section, (2) open a new plan if work is genuinely separate, (3) defer to backlog. System-managed paths (`docs/plans/archive/*`) are exempt. Emergency override via `git commit --no-verify` only. | `scope-enforcement-gate.sh` PreToolUse Bash blocker on `git commit` | `~/.claude/hooks/scope-enforcement-gate.sh` |
| Mode: design plans must show inline arithmetic for any comparative quantitative claim | `plan-reviewer.sh` Check 9 — comparative-phrase + paragraph-window arithmetic detection (FM-013 / FM-014) | `~/.claude/hooks/plan-reviewer.sh` |
| Tier 3+ plans cannot dispatch first Task invocation without DAG-approval waiver | `dag-review-waiver-gate.sh` PreToolUse Task blocker (per-session marker after first allow) | `~/.claude/hooks/dag-review-waiver-gate.sh` |
| Mid-process discovery capture | `bug-persistence-gate.sh` extended Stop hook accepts `docs/discoveries/YYYY-MM-DD-*.md` | `~/.claude/hooks/bug-persistence-gate.sh` + `~/.claude/rules/discovery-protocol.md` |
| Pending discoveries surfaced at session start | `discovery-surfacer.sh` SessionStart hook | `~/.claude/hooks/discovery-surfacer.sh` |
| Spawn_task results surfaced at session start | `spawned-task-result-surfacer.sh` SessionStart hook + `spawn-task-report-back.md` rule (convention sentinel + JSON schema + ack marker) | `~/.claude/hooks/spawned-task-result-surfacer.sh` + `~/.claude/rules/spawn-task-report-back.md` |
| Findings persisted to durable ledger with schema validation — every entry in `docs/findings.md` validated against the locked six-field schema (ID / Severity / Scope / Source / Location / Status + non-empty Description body) on every commit; malformed entries blocked with stderr message naming the failing entry + reason; no-op when `docs/findings.md` is not staged | `findings-ledger-schema-gate.sh` PreToolUse Bash blocker on `git commit` (Phase 1d-C-3 / C9, 2026-05-04) | `~/.claude/hooks/findings-ledger-schema-gate.sh` + `~/.claude/rules/findings-ledger.md` + Decision 019 (`docs/decisions/019-findings-ledger-format.md`) |
| Class-aware findings count as legitimate session-end persistence (extends bug-persistence) — `docs/findings.md` is accepted as the fourth durable-storage target alongside `docs/backlog.md`, `docs/reviews/YYYY-MM-DD-*.md`, and `docs/discoveries/YYYY-MM-DD-*.md`; trigger phrases that signal a class-aware finding (gates emitting `Class:` blocks, adversarial-review agents surfacing sibling regressions) are satisfied by an entry in the findings ledger | `bug-persistence-gate.sh` extension (Phase 1d-C-3 / Task 4, 2026-05-04) | `~/.claude/hooks/bug-persistence-gate.sh` + `~/.claude/rules/findings-ledger.md` |
| Plan creation requires valid PRD (Mode-agnostic, ACTIVE plans) — plan-file `Write` blocked when `prd-ref:` resolves to a missing-or-incomplete `docs/prd.md`; harness-dev carve-out via exact-string `n/a — harness-development` | `prd-validity-gate.sh` PreToolUse Write blocker + `prd-validity-reviewer` agent (substance review) | `~/.claude/hooks/prd-validity-gate.sh` (landing in Phase 1d-C-2) + `~/.claude/agents/prd-validity-reviewer.md` |
| Edits to declared files blocked when spec is not frozen — Edit/Write on any file in an ACTIVE plan's `## Files to Modify/Create` (or `## In-flight scope updates`) section is blocked unless that plan has `frozen: true` | `spec-freeze-gate.sh` PreToolUse Edit/Write blocker | `~/.claude/hooks/spec-freeze-gate.sh` (landing in Phase 1d-C-2) |
| Plan headers require all 5 fields (`tier`, `rung`, `architecture`, `frozen`, `prd-ref`) on `Status: ACTIVE` plans with no defaults; missing or invalid values FAIL | `plan-reviewer.sh` Check 10 — 5-field plan-header schema | `~/.claude/hooks/plan-reviewer.sh` (landing in Phase 1d-C-2) |
| R3+ plans require `## Behavioral Contracts` section with 4 sub-entries (`### Idempotency`, `### Performance budget`, `### Retry semantics`, `### Failure modes`), each ≥ 30 non-ws chars and non-placeholder | `plan-reviewer.sh` Check 11 — C16 behavioral-contracts schema check | `~/.claude/hooks/plan-reviewer.sh` (landing in Phase 1d-C-2) |
| Comprehension articulation required at rung >= 2 (builders must articulate `Spec meaning` / `Edge cases covered` / `Edge cases NOT covered` / `Assumptions` inside their evidence entry; `comprehension-reviewer` agent verifies match-to-diff via three-stage rubric — schema / substance / diff correspondence — before `task-verifier` flips the checkbox; FAIL or INCOMPLETE blocks the flip; below R2 the gate is a no-op) | `comprehension-reviewer` agent + `task-verifier` extension (auto-invokes at rung >= 2; Phase 1d-C-4 / C15, 2026-05-04) | `~/.claude/agents/comprehension-reviewer.md` + `~/.claude/agents/task-verifier.md` |
| Definition-on-first-use enforcement at neural-lace/build-doctrine/ | `definition-on-first-use-gate.sh` PreToolUse Bash on `git commit` (Phase 1d-F / sub-gap G) | `~/.claude/hooks/definition-on-first-use-gate.sh` |
| Plan-closure validation gate — Edits flipping `Status: ACTIVE → COMPLETED` on a `docs/plans/<slug>.md` file are blocked unless five mechanical closure checks pass: (a) every `## Tasks` checkbox flipped, (b) every task has a `Verdict: PASS` evidence block, (c) `## Completion Report` populated with a substantive Implementation Summary, (d) every `Backlog items absorbed:` entry reconciled in `docs/backlog.md`, (e) `SCRATCHPAD.md` mtime fresh (< 60 min) and mentions the slug. Non-COMPLETED terminal flips (DEFERRED/ABANDONED/SUPERSEDED) are not gated. The `/close-plan <slug>` skill walks the orchestrator through closure mechanically so the right path is the path of least resistance. | `plan-closure-validator.sh` PreToolUse Edit/Write blocker + `close-plan` skill (Phase 1d-H, 2026-05-05) | `~/.claude/hooks/plan-closure-validator.sh` + `~/.claude/skills/close-plan.md` |
| Mechanical evidence substrate (Build Doctrine Principle 7 — "Visibility lives in artifacts, not narration") — replaces prose evidence blocks with locked-schema JSON artifacts. Six required fields (`task_id`, `verdict`, `commit_sha`, `files_modified`, `mechanical_checks`, `timestamp`) plus optional escalation fields (`runtime_evidence`, `prose_supplement`). Helper script `write-evidence.sh capture` captures mechanical-check outcomes deterministically; `plan-edit-validator.sh` recognizes both new structured artifacts (`<plan-slug>-evidence/<task-id>.evidence.json`) and legacy prose blocks at checkbox-flip time. Closure cost drops because the closure-validator can check structured fields rather than parse prose. Backward compatible — existing closed plans with prose evidence remain valid. | `evidence.schema.json` + `write-evidence.sh capture` + `plan-edit-validator.sh` extension + `task-verifier` agent helper-script preference (Tranche B of architecture-simplification, 2026-05-05) | `~/.claude/schemas/evidence.schema.json` + `~/.claude/scripts/write-evidence.sh` + `~/.claude/hooks/plan-edit-validator.sh` + `~/.claude/agents/task-verifier.md` + `~/.claude/rules/mechanical-evidence.md` |

**Missing from the enforcement map (explicitly acknowledged as gaps):**
- `test-quality-reviewer` as a separate agent does NOT exist. The trivial-assertion ban lives inside `pre-commit-tdd-gate.sh` Layer 4. Test quality is not reviewed adversarially outside the gate.
- PostMessage verification for verbal vaporware does NOT exist. `claim-reviewer` is self-invoked and can be skipped.
- **`tool-call-budget.sh --ack` attestation is bypassable by direct file write.** The hook greps for `REVIEW COMPLETE` + `VERDICT:` sentinel lines in a fresh file under `~/.claude/state/reviews/`. A builder could Write that file directly without invoking `plan-evidence-reviewer`. Friction is raised (the bypass requires knowing the sentinel format and writing a plausible review body) but not cryptographically closed. Closing this requires either per-session HMAC signing the agent knows but the builder cannot easily extract, or Claude Code architectural support for observing Task-tool invocations. Accepted residual risk for Gen 4.

## Residual gap (honest)

**Verbal vaporware in conversation is not mechanically blocked.** Claude Code has no PostMessage hook. `claim-reviewer` is self-invoked and can be skipped. This is the single unclosed gap from Generation 4. The mitigation is behavioral: every feature claim must cite file:line, and the user retains interrupt authority when they see an uncited claim.

## Pattern recognition (stop if you catch yourself)

- "I built X and it typechecks, so task is done"
- "The code exists" as the only evidence of completion
- Describing a feature without citing the file
- Answering "yes it works" without exercising it in the current session
- Confusing "I planned this" with "I built this"
- "This should work" instead of "I verified this works"
- Marking a task complete because adjacent tasks are complete
- Skipping a runtime test because "typecheck passed"
- Rationalizing "this task is obvious, verification is overkill"

The correction is always: run the command, capture the output, cite the artifact.

## Cost

Every vaporware shipment costs user trust (slow to repair), cleanup work, regression risk, and harness credibility. A Playwright test is always cheaper.
