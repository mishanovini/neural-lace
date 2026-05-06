# Evidence: Tranche G — Calibration Loop Bootstrap

Companion evidence file for `docs/plans/architecture-simplification-tranche-g-calibration-loop.md`.

## Tasks 1-7 — single-commit batch

**Verification:** mechanical (bash syntax check + 7-case self-test on calibrate skill + smoke-test on harness-review Check 12 logic).

**What shipped:**

- `adapters/claude-code/skills/calibrate.md` — NEW. Manual-entry calibration capture. Five canonical observation classes; bash implementation with arg validation; entry-format spec; self-test cases documented inline.
- `adapters/claude-code/rules/calibration-loop.md` — NEW. Discipline rule with three trigger conditions, observation-class semantics, routing logic (prompt update vs. work-shape extension vs. telemetry-defer), explicit exclusions, cross-references to Build Doctrine Principle 9 + Role 9 + ADR 026.
- `adapters/claude-code/skills/harness-review.md` — MODIFIED. Added Check 12 ("Calibration roll-up") between Check 11 and the Summary block. Reads `.claude/state/calibration/*.md` files; emits per-agent total entry count, top-3 observation classes, most-recent entry per class. Always PASS (informational); volume warning triggers at >100 entries per agent.
- `adapters/claude-code/rules/vaporware-prevention.md` — MODIFIED. Added one row to the enforcement map citing the calibrate skill + harness-review Check 12 + calibration-loop rule + Build Doctrine Principle 9 / Role 9.
- `docs/harness-architecture.md` — MODIFIED. Added `calibrate.md` row to Skills table. New "Calibration Loop (Tranche G, 2026-05-05)" section between Skills and Docs tables describing the three-component substrate.
- Sync to `~/.claude/`: all three modified/new files (`calibrate.md`, `calibration-loop.md`, `harness-review.md`, `vaporware-prevention.md`) byte-identical between repo and `~/.claude/`.

**Self-test results (7/7 PASS):**

```
PASS T1 (missing args → exit 1 with Usage)
PASS T2 (invalid agent name uppercase → exit 1)
PASS T3 (missing details → exit 1)
PASS T4 (valid invocation → file created with header + entry)
PASS T5 (second invocation → entry appended, header preserved)
PASS T6 (' || ' separator → mitigation captured)
PASS T7 (no mitigation → placeholder text in entry)
```

**Smoke-test on Check 12 logic** (synthetic 5-entry calibration file):
```
**task-verifier**: 5 entries; top classes: shortcut (2), pass-by-default (2), hallucination (1); most-recent: hallucination (2026-05-05T10:30:00Z)
```
Verifies entry-count, top-3 ranking, most-recent extraction all correct.

**Bash syntax checks:**
- `bash -n` on harness-review.md extracted bash block → OK
- `bash -n` on calibrate.md extracted bash block → OK

**Cross-references intact:**
- ADR 026 (`docs/decisions/026-harness-catches-up-to-doctrine.md`) referenced from skill + rule + architecture section.
- Build Doctrine Principle 9 (`build-doctrine/doctrine/01-principles.md`) referenced from skill + rule + architecture section + enforcement-map row.
- Build Doctrine Role 9 Knowledge Integrator (`build-doctrine/doctrine/02-roles.md`) referenced from skill + rule + architecture section + enforcement-map row.
- Decision G.1, G.2 (`docs/decisions/queued-tranche-1.5.md`) referenced from skill + rule.
- HARNESS-GAP-11 (`docs/backlog.md`) referenced from skill + rule + architecture section + enforcement-map row.

**Verdict:** PASS — Tasks 1-6 shipped + synced + self-tested. Task 7 (parent plan checkbox flip) is for the orchestrator per the verifier-mandate; this builder did not touch the parent plan file.

## Decisions during build

- Em-dash regex bug surfaced during smoke-test of Check 12 (the `Z .* — ` pattern with a multibyte em-dash failed to match under bash). Reverted to a simpler `Z` pattern with sed splitting on em-dash. Reasoning: locale-dependent multibyte handling in `grep -E` is unreliable on Windows Git Bash; sed splits work the same way regardless. Documented inline in the harness-review.md Check 12 block.
- Mitigation parsing uses ` || ` separator (typed inline) rather than a separate prompt. Reason: keeps the skill non-interactive and one-shot. If no mitigation is supplied, the entry shows a placeholder so the roll-up reviewer knows to populate later.
- Calibration directory location: `.claude/state/calibration/` (per-agent files, gitignored) per Decision G.1 option A. The state path `.claude/state/` is already in `.gitignore` (line 119 — confirmed during build), no new gitignore entry required.
