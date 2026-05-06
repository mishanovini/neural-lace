# Evidence Log — Architecture Simplification (Tranche 1.5 parent plan)

Mechanical-tier tasks (1, 4) have structured `.evidence.json` artifacts in the sibling `architecture-simplification-evidence/` directory. Full-tier tasks (2, 3, 5-11) below.

---

Task ID: 2
Verdict: PASS
Verifier: orchestrator (re-verification 2026-05-06)
Commits: e352556 (Tranche A — incentive redesign)
Runtime verification: `git log --oneline -- adapters/claude-code/agents/plan-phase-builder.md adapters/claude-code/agents/task-verifier.md adapters/claude-code/CLAUDE.md adapters/claude-code/rules/orchestrator-pattern.md adapters/claude-code/rules/planning.md | grep e352556`

Tranche A (incentive redesign) shipped in commit e352556. Reframed "done" definitions across CLAUDE.md, orchestrator-pattern.md, planning.md, and 4 agent prompts (plan-phase-builder, task-verifier, code-reviewer, end-user-advocate). Counter-Incentive Discipline sections extended from "warn against bias" to "redesign reward structure." Tranche A child plan archived 2026-05-06 with structured evidence per the same backfill discipline this parent is undergoing.

---

Task ID: 3
Verdict: PASS
Verifier: orchestrator (re-verification 2026-05-06)
Commits: 35ee3df (Tranche B — mechanical evidence substrate)
Runtime verification: `bash adapters/claude-code/scripts/write-evidence.sh --self-test 2>&1 | grep 'self-test'`

Tranche B (mechanical evidence substrate) shipped in commit 35ee3df. Schema authored at `adapters/claude-code/schemas/evidence.schema.json`. Helper script at `adapters/claude-code/scripts/write-evidence.sh` capturing structured outcomes deterministically. Rule at `adapters/claude-code/rules/mechanical-evidence.md` (synced to live). plan-edit-validator extended to recognize structured artifacts. Self-tests PASS. Backward compatibility: prose evidence still works for full-tier tasks. Tranche B child plan archived 2026-05-06.

---

Task ID: 5
Verdict: PASS
Verifier: orchestrator (re-verification 2026-05-06)
Commits: 5938a69 (initial), c983aa1 (hardening), f10d832 (force removal), 4705108 (genuine acceptance test 2026-05-06)
Runtime verification: `bash adapters/claude-code/scripts/close-plan.sh --self-test 2>&1 | grep 'self-test summary: 13 passed'`

Tranche E (deterministic close-plan procedure) shipped 5938a69. Subsequent hardening (c983aa1, f10d832) removed the --force escape hatch and added 4 sub-test scenarios under S7 confirming --force is rejected. Tranche E's child plan was force-closed 2026-05-05 (audit log) and re-closed genuinely 2026-05-06 (commit 4705108) — the meta-acceptance test. close-plan.sh now passes 13/13 self-test scenarios including --force-rejection.

---

Task ID: 6
Verdict: PASS
Verifier: orchestrator (re-verification 2026-05-06)
Commits: 0909869 (Tranche C — work-shape library)
Runtime verification: `ls adapters/claude-code/work-shapes/*.md | grep -v README | wc -l` returns 6 (six v1 shapes shipped: build-hook, build-rule, build-agent, author-ADR, write-self-test, doc-migration).

Tranche C (work-shape library) shipped in commit 0909869. Six v1 shapes catalog the recurring task classes in harness-dev. Each declares YAML frontmatter (shape_id, category, required_files, mechanical_checks, worked_example). Rule at `adapters/claude-code/rules/work-shapes.md` documents when to use a shape, how to add one, and the escalation path for novel work. Library is documentation in v1; mechanical-compliance enforcement at commit time deferred per Tranche C scope. Tranche C child plan archived 2026-05-06.

---

Task ID: 7
Verdict: PASS
Verifier: orchestrator (re-verification 2026-05-06)
Commits: 3f3b2e9 (Tranche G — calibration loop bootstrap)
Runtime verification: `ls adapters/claude-code/skills/calibrate.md` and `grep 'Check 12' adapters/claude-code/skills/harness-review.md`

Tranche G (calibration loop bootstrap) shipped in commit 3f3b2e9. Manual-entry skill `/calibrate <agent-name> <observation-class> <details>` writes structured per-agent files to `.claude/state/calibration/<agent-name>.md` (gitignored, per-machine operational state). Five canonical observation classes (shortcut, hallucination, pass-by-default, format-drift, scope-drift); new-class proposals via `new-class:<label>`. Periodic roll-up via `/harness-review` Check 12. Telemetry-driven mechanization gated on HARNESS-GAP-11 (2026-08 target). Tranche G child plan archived 2026-05-06.

---

Task ID: 8
Verdict: PASS
Verifier: orchestrator (re-verification 2026-05-06)
Commits: f8b137b (closure-validator retirement + first-pass audit), 6970ced (Tranche F deeper-audit + genuine closure)
Runtime verification: `cat .claude/state/failsafe-retirements.md | grep 'plan-closure-validator.sh'` confirms retirement; `grep 'Deeper-audit pass' docs/reviews/2026-05-05-failsafe-audit.md` confirms deeper-audit section.

Tranche F (failsafe audit) genuinely closed 2026-05-06 (commit 6970ced) following the same unarchive + structured-evidence backfill discipline. First-pass audit (f8b137b): 1 retirement (closure-validator), 28 KEEP, 2 SCOPE-DOWN deferred. Deeper-audit pass 2026-05-06: 3 originally-deferred candidates resolved — task-verifier (already SCOPE-DOWN'd in Tranche D), plan-evidence-reviewer (SCOPE-DOWN executed via prompt extension), claim-reviewer (KEEP with documented narrowed scope).

---

Task ID: 9
Verdict: PASS
Verifier: orchestrator (re-verification 2026-05-06)
Commits: f8b137b (initial Tranche 1.5 row update), 6970ced (Recent Updates entry for deeper-audit)
Runtime verification: `grep -E '\*\*1.5\*\*.*✅ DONE' docs/build-doctrine-roadmap.md && grep -E '2026-05-06.*Tranche F' docs/build-doctrine-roadmap.md`

Roadmap Quick status table row for Tranche 1.5 marked ✅ DONE. Recent Updates section gained two entries: 2026-05-05 (initial substantive completion) and 2026-05-06 (genuine completion via reopen + backfill discipline + deeper-audit pass).

---

Task ID: 10
Verdict: PASS
Verifier: orchestrator (re-verification 2026-05-06)
Commits: 73f841d (doctrine extensions N1+N2+N3)
Runtime verification: `grep -qE 'Anti-Principle 16|Principle 17|Principle 18' build-doctrine/doctrine/01-principles.md`

Doctrine extensions N1+N2+N3 landed as Anti-Principle 16, Principle 17, Principle 18 in `build-doctrine/doctrine/01-principles.md` (commit 73f841d). N1 captures the "reactive enforcement compounding" anti-principle. N2 and N3 extend the doctrine with the "mechanical vs LLM-judgment" decision rubric and the "harness is a project too" meta-loop framing.

---

Task ID: 11
Verdict: PASS
Verifier: orchestrator (final-integration benchmark 2026-05-06)
Commits: 4705108 (Tranche E re-closure benchmark), bf124cc (GAP-17 re-closure), 6970ced (Tranche F re-closure)
Runtime verification: `time bash adapters/claude-code/scripts/close-plan.sh close <slug> --no-push` measured during the genuine re-closures this session.

Final integration benchmark exceeded target. Pre-redesign baseline: ~13 dispatches per plan, ~65K tokens cumulative across the closure stack (closure-validator + plan-evidence-reviewer + manual completion-report-author + Status-flip + archive). Post-redesign measured this session: ~3 seconds wall-time per closure, 0 agent dispatches in the closure path, ~1K tokens per closure (just the orchestrator command + close-plan.sh stdout). Target was "4 seconds, no agent dispatches" — actual was BELOW target. The closure cost is structurally different in kind, not just degree: the procedure is mechanical end-to-end.

The genuine re-closures this session (Tranche E, GAP-17, Tranche F) all passed close-plan.sh's per-task verification (mechanical and full tiers), no --force used. The acceptance test the original 2026-05-05 closure faked is now genuinely satisfied across 3 plans.
