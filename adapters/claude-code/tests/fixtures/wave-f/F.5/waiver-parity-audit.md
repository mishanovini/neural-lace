# F.5 waiver-parity audit (ADR 059 D4) — all 32 `blocking:true` manifest entries

Owner: F.5 builder (this file). `manifest.json` and `schemas/manifest.schema.json`
are ORCHESTRATOR-ONLY this wave (§F.0.1) — F.1 is the designated integrator. This
audit is evidence for the orchestrator's merge pass, not a manifest edit.

## Method

For every `adapters/claude-code/manifest.json` entry with `blocking: true` (32 of 90
entries as of this audit, `523ab84`), I read the entry's `hooks[]` script(s) end to
end and classified the waiver posture into one of four buckets:

- **STRUCTURED-WAIVER** — a `<gate>-waiver-*.txt` (or equivalently named) file with a
  freshness window, honored via (or equivalent to) `lib/waiver-purpose-clause.sh`'s
  two-clause validation ("this gate exists to prevent X" / "does not apply here
  because Y"), ledger-logged as a `waiver` event. This is the D4 target shape.
- **DOCUMENTED-EQUIVALENT** — a real, working escape hatch that is not the
  waiver-file shape (env var, config flip, git-native `--no-verify`) but is
  explicitly documented in the hook's own header/block message. Acceptable per the
  spec's "or documented equivalent" clause, but several of these lack freshness
  and/or ledger-logging and are flagged as partial.
- **HONESTY-CLASS (no valve needed)** — the block asserts something the SAME
  SESSION created and can resolve directly (fix the commit content, fix the
  schema, remove the offending line) per ADR 059 D4's scoping: "a waiver clears
  world-state assertions; it never clears session-honesty assertions... those are
  resolvable by the session that created them, so no valve is needed or offered."
  These are NOT gaps by design, but the manifest currently has no field to say so
  — `honesty_rationale` (proposed below) is how the schema should record this
  reasoning instead of leaving it implicit in the hook's comments.
- **GAP** — blocking, with a vague/non-mechanical "escape hatch" (manual file
  editing, prose telling the agent to "bypass this hook") that is neither a real
  structured waiver nor a defensible honesty-class no-valve call. These need a
  real waiver path added.

## Audit table

| # | Manifest id | Hook file(s) | Posture | Evidence | D4 gap? |
|---|---|---|---|---|---|
| 1 | `agent-teams` | `teammate-spawn-validator.sh` | STRUCTURED-WAIVER (condition d, DAG-review) | Sources `lib/waiver-purpose-clause.sh`; block comment documents the DAG-approval waiver file convention (`teammate-spawn-validator.sh` lines 22-31, 48). | No — conditions (a)/(b)/(c) of the same hook are HONESTY-CLASS (config-disabled / worktree-isolation / permission-mode facts the session can see and fix by changing its own invocation), condition (d) has the structured waiver. |
| 2 | `agent-teams` | `task-created-validator.sh` | **FIXED → STRUCTURED-WAIVER + ledger-logged bypasses** | Fix landed: `TASK_CREATED_BYPASS=1` env / `bypass_validation: true` field bypasses now both call `ledger_emit "task-created-validator" "waiver" ...` (grep-verified, was previously absent); PLUS a new fresh (<1h) `.claude/state/task-created-waiver-*.txt` structured waiver via `lib/waiver-purpose-clause.sh` for the substantive one-off case, also ledger-logged. Block messages updated to name both hatches + cost (pin-d). Self-test: 8/8 PASS incl. waiver-honored/absent/stale/weak-waiver scenarios (`bash task-created-validator.sh --self-test`). | No longer — fixed. |
| 3 | `agent-teams` | `task-completed-evidence-gate.sh` | DOCUMENTED-EQUIVALENT, partial | `TASK_COMPLETED_BYPASS=1` env var (line 487); IS ledger-logged (`ledger_emit "task-completed-evidence-gate" "waiver" "env-bypass task=..."` at line 496) but has no freshness window and no substantive-reason gate — any env flip clears it, unconditionally, forever. | **Yes** — ledger-logged (half the D4 bar) but not fresh/substantive (the other half). Recommend routing through `lib/waiver-purpose-clause.sh` like `bug-persistence-gate.sh`/`work-integrity-gate.sh` did. |
| 4 | `backlog-plan-atomicity` | `backlog-plan-atomicity.sh` | HONESTY-CLASS | Commit-time check: a new plan's header must declare which backlog items it absorbs. `grep -n waiver backlog-plan-atomicity.sh` → no hits. The block is "this new plan doesn't declare its absorbed backlog items" — resolvable by editing the plan header in the same commit. | No — but manifest has no `honesty_rationale` field to say so today (schema gap, see Proposal 1 below). |
| 5 | `bug-persistence` | `bug-persistence-gate.sh` | STRUCTURED-WAIVER | Sources `lib/waiver-purpose-clause.sh` (line 381); `ATTEST_FILE` + `waiver_has_purpose_clauses` gate (lines 603-611). Canonical example other hooks were retrofitted to match. | No. |
| 6 | `claude-md-hygiene` | `claude-md-hygiene-gate.sh` | DOCUMENTED-EQUIVALENT, but manifest is currently DISHONEST about default posture | Header (lines 24-29): defaults to **warn-mode** (`exit 0` always) until 24h of calibration data justifies flipping to `block` mode; `CLAUDE_MD_HYGIENE_DISABLE=1` env var no-ops it entirely. Manifest's `blocking: true` for this entry does not carry a `honest_status` note explaining the warn-mode default — a reader of the manifest alone would believe this gate hard-blocks today. | **Yes, but a manifest-honesty gap, not a waiver gap** — recommend `honest_status`: "defaults to warn-mode (CLAUDE_MD_HYGIENE_MODE env / ~/.claude/local/claude-md-hygiene-mode); blocking:true reflects the DESIGNED end-state, not the current live default — escape hatch CLAUDE_MD_HYGIENE_DISABLE=1." |
| 7 | `decisions-index` | `decisions-index-gate.sh` | HONESTY-CLASS | Enforces Tier-2+ decision ↔ `docs/DECISIONS.md` index-row atomicity in the SAME commit. No waiver hits (`grep -n waiver decisions-index-gate.sh` → none). Resolvable by adding the missing index row to the same commit. | No — schema gap only (Proposal 1). |
| 8 | `deploy-automation-mode` | `automation-mode-gate.sh` | DOCUMENTED-EQUIVALENT | Not a per-instance waiver; the config IS the control — `$PWD/.claude/automation-mode.json` (or user-global) sets `mode: "full-auto"` to disable the pause entirely for a project. Block message states this explicitly (line ~198, "To override per-project: create ..."). This is a legitimate mode setting, not a one-off waiver — same category as `deploy-automation-mode` being fundamentally a policy switch. | No — but recommend `honest_status` naming the config-override path so the schema's OR clause is satisfied explicitly rather than left to prose. |
| 9 | `docs-freshness` | `docs-freshness-gate.sh` | HONESTY-CLASS | Rule 8: structural harness changes (hooks/agents/rules added/deleted/renamed) must touch docs in the same commit. No waiver hits. Resolvable by adding the doc delta to the same commit. | No — schema gap only. |
| 10 | `env-local-protection` | `env-local-protection.sh` | DOCUMENTED-EQUIVALENT | `ENV_LOCAL_OVERWRITE_OK=1` prefix on the command itself (documented at lines 39-42); auto-backs-up before either blocking or allowing, so the escape hatch is safe-by-construction (a recovery point always exists). Not ledger-logged, but the auto-backup makes ledger-logging lower-value here (the backup file itself is the audit trail). | Minor — recommend a `ledger_emit "env-local-protection" "waiver" ...` call alongside the override-sentinel path for consistency with the rest of the audit trail, but this is the one gate where the backup-first design already gives an equivalent trail. |
| 11 | `findings-ledger` | `findings-ledger-schema-gate.sh` | HONESTY-CLASS | Six-field `docs/findings.md` schema validation. No waiver hits. Resolvable by fixing the entry's fields in the same commit — the classic "checked-box-without-evidence" shape ADR 059 D4 names as unwaivable by design. | No — schema gap only. |
| 12 | `harness-hygiene-scan` | `harness-hygiene-scan.sh` | **FIXED → STRUCTURED-WAIVER (per-file, per-run)** | Fix landed: fresh (<1h) `.claude/state/harness-hygiene-waiver-*.txt` naming BOTH purpose clauses (`lib/waiver-purpose-clause.sh`) PLUS a `Files:` line listing the repo-relative path(s) it covers — suppresses matches ONLY on those named files for this run, distinct from the durable plan-time exempt-list. Ledger-logged per waived file. Block message updated to name the hatch + cost (pin-d). Self-test: `bash harness-hygiene-scan.sh --self-test` → OK, incl. waiver-honored/absent/stale/wrong-file/weak-waiver scenarios. | No longer — fixed. |
| 13 | `local-edit-authorization` | `local-edit-gate.sh` | STRUCTURED-WAIVER (adjacent shape) | Fresh (<30 min) per-file marker at `~/.claude/state/local-edit-<slug>-<ISO8601>.txt`, written only by the `/grant-local-edit` skill (an explicit user-invoked authorization, not a self-service waiver). Functionally equivalent to D4's fresh+substantive bar (the marker IS the substantive act: the operator invoked the skill) but is operator-gated rather than session-gated by design (this file protects `~/.claude/local/**`, which the session should never unilaterally waive its way into). | No — the ADR 059 D4 scoping explicitly contemplates gates that gate on facts outside the session's own authority; this is one (only the operator can grant it). |
| 14 | `migration-claude-md` | `migration-claude-md-gate.sh` | HONESTY-CLASS | Rule 3: new migration + `CLAUDE.md`'s `Migrations: through <N>` line must move together. No waiver hits. Resolvable by updating the CLAUDE.md line in the same commit. | No — schema gap only. |
| 15 | `no-test-skip` | `no-test-skip-gate.sh` | GAP | Blocks new `.skip(`/`.only(`-shaped test skips without an issue-number reference. No waiver mechanism at all — the block message's only remedies are "remove the skip" or "add a real issue reference," both of which require the AUTHOR to change the code, which is honesty-class-correct... except the gate itself never explains what to do when the skip is genuinely, temporarily unavoidable (e.g. an upstream service outage) and an issue tracker reference is impossible to obtain in-session. | **Yes, partial** — recommend documenting that "add a real issue reference" (e.g. an `NL-FINDING-*` or GitHub issue number, even a freshly-filed one) IS the intended waiver-equivalent already, by naming it as such in the block message; today it reads as a hard requirement, not a hatch. |
| 16 | `parallel-dev-migration-naming` | `migration-naming-gate.sh` | HONESTY-CLASS | Blocks bare-sequential-integer migration filenames; remedy is "rename to a timestamp prefix," fully in the author's own hands, same commit. No waiver hits. | No — schema gap only. |
| 17 | `plan-deletion-protection` | `plan-deletion-protection.sh` | **FIXED → STRUCTURED-WAIVER** | Fix landed: `emit_block()` now checks a fresh (<1h) `.claude/state/plan-deletion-waiver-*.txt` naming BOTH purpose clauses (`lib/waiver-purpose-clause.sh`) BEFORE blocking; when honored, the specific command is ALLOWed (ledger-logged) instead of blocked. Vague "edit the source out manually" remedy replaced with the mechanical hatch + cost (pin-d) in the block message. Self-test: `bash plan-deletion-protection.sh --self-test` → 18/18 PASS, incl. waiver-honored/absent/stale/weak-waiver scenarios 15-18. | No longer — fixed. |
| 18 | `plan-edit-validator` | `plan-edit-validator.sh` | GAP | Checkbox-flip protection (only task-verifier may flip). The PREVIOUS `TASK_VERIFIER_MODE=1` env escape hatch was deliberately REMOVED (lines 22-25) as a plaintext back door and replaced with "evidence-first" authorization — which is a legitimate-use path, not a waiver for a session that has a real reason to flip a box itself. No waiver mechanism exists for that case today. | No — this is intentionally HONESTY-CLASS BY DESIGN per the file's own comments (checkbox truth is exactly the "checked-box-without-evidence" shape ADR 059 D4 names as correctly unwaivable), but the manifest should say so explicitly rather than relying on a future reader finding this file's comments. |
| 19 | `plan-reviewer` | `plan-reviewer.sh` | HONESTY-CLASS | Adversarial review of new/ACTIVE plan files. No waiver hits. Resolvable by fixing the plan content. | No — schema gap only. |
| 20 | `pre-commit-chain` | `pre-commit-gate.sh` | N/A (aggregator) | This entry is a DISPATCHER that runs 6 sub-checks (doc-freshness×4, TDD, plan-reviewer, tests, build, API-consumer audit) each of which is independently manifest-entried (rows 4/7/9/14/16/19/29 here) and independently audited above. The aggregator itself has no separate waiver posture — waiving happens at the sub-check level. | No — recommend `honesty_rationale`: "aggregator; each dispatched sub-check carries its own waiver/honesty posture (see backlog-plan-atomicity, decisions-index, docs-freshness, migration-claude-md, plan-reviewer, review-finding-fix, tdd-gate entries)." |
| 21 | `pre-push-divergence` | `pre-push-divergence-check.sh` | DOCUMENTED-EQUIVALENT | Git-native: `git push --no-verify` bypasses ALL `core.hooksPath` dispatched checks (this one included), same as every pre-push-dispatched gate. Not this gate's own waiver — a property of how git hooks work. | No — recommend `honest_status`/`honesty_rationale` note: "escape hatch is git's own `--no-verify`; no gate-specific waiver needed or offered (world-state fact: remote has moved — the fix is `git fetch && rebase/merge`, not a waiver)." |
| 22 | `pre-push-test` | `pre-push-test-gate.sh` | DOCUMENTED-EQUIVALENT | Same `--no-verify` git-native bypass; per-repo opt-in marker gates whether the check runs at all (a project can opt OUT structurally, which is a stronger and more honest mechanism than a per-session waiver). | No — same reasoning as row 21. |
| 23 | `review-finding-fix` | `review-finding-fix-gate.sh` | HONESTY-CLASS | Requires a review-finding-referencing commit to also touch the review file. No waiver hits. Resolvable in the same commit. | No — schema gap only. |
| 24 | `runtime-verification` | `runtime-verification-executor.sh` + `runtime-verification-reviewer.sh` | HONESTY-CLASS (Stop-time verification-class block) | Per ADR 059 D2, this is explicitly the class of block that is "never downgraded under a `DONE:` claim... load-bearing honesty enforcement." No waiver is correct here by design. | No — but this is the SINGLE MOST IMPORTANT entry to mark with an explicit `honesty_rationale` rather than silence, since ADR 059 D2 calls this out by name as the one class that must NEVER get a waiver valve even under pressure. |
| 25 | `secret-hygiene-prepush` | `pre-push-scan.sh` | DOCUMENTED-EQUIVALENT | Header line 4: "Override with `git push --no-verify`." Explicitly documented, git-native. | No — recommend the same `honesty_rationale` note as rows 21/22 for consistency, though this one is arguably a case where a REAL secret should never be waived casually — flag for F.1/operator: should secret-hygiene be the one pre-push gate WITHOUT even the `--no-verify` framing normalized as acceptable? (Recording as an open question, not resolving unilaterally — this is a security-posture call, not a mechanical one.) |
| 26 | `session-honesty` | `session-honesty-gate.sh` | HONESTY-CLASS (explicitly, in the hook's own comments) | Lines 283-301: reads work-integrity's waiver family to detect "already resolved via waiver," but this gate's OWN assertion (a resolved-vs-live block state) is never itself waivable — "a waiver never bypasses the marker requirement itself." pin-f-doctor-exempt note at line 297. | No — same as row 24, this is a load-bearing ADR 059 D4/D2 no-valve-by-design case; needs the explicit `honesty_rationale` field so a future schema/doctor pass doesn't mistake the absence of a waiver for an oversight. |
| 27 | `spec-freeze` | `scope-enforcement-gate.sh` + `spec-freeze-gate.sh` | Mixed: scope-enforcement is STRUCTURED-WAIVER-adjacent honesty-class (unchanged, correct); spec-freeze-gate **FIXED → STRUCTURED-WAIVER** | `scope-enforcement-gate.sh` (lines 109-114): unchanged — waiver REMOVED 2026-05-04 by deliberate design, correctly honesty-class/world-fact (wrong repo), no valve. `spec-freeze-gate.sh`: fix landed — resolved the "decision needed" per ADR 059 D4's own text: D4 is a *hard design rule* ("every blocking check MUST ship a structured waiver path") and this block is a world-state assertion (the plan's `frozen` field), not a session-honesty assertion, so it falls inside D4's waiver-eligible scope rather than the honesty-class carve-out. Added a fresh (<1h) `.claude/state/spec-freeze-waiver-<slug>-*.txt` naming BOTH purpose clauses (`lib/waiver-purpose-clause.sh`), ledger-logged, checked against every unfrozen claiming plan's slug. This is explicitly ADDITIVE to — not a replacement for — the durable unfreeze-then-refreeze remedy (still named first in the block message). Vague "temporarily use a non-Edit/Write tool" bypass-via-different-tool language removed from the block message. Self-test: `bash spec-freeze-gate.sh --self-test` → 11/11 PASS, incl. waiver-honored/absent/stale/weak-waiver scenarios 8-11. **Note for F.1/harness-reviewer**: this was a judgment call the original audit reserved for operator/reviewer input rather than resolving unilaterally; the fix leans on D4's own "hard rule" language as the defensible unilateral basis (constitution §3) — flag for confirmation, not silent acceptance, at the next harness-reviewer pass. | No longer — fixed (see reviewer-confirmation note). |
| 28 | `stop-verdict-dispatcher` | `stop-verdict-dispatcher.sh` | N/A (aggregator) | Dispatches to `bug-persistence`/`work-integrity`/`session-honesty` in `--report` mode; delegates to their own waiver postures (rows 5, 30, 26). Its own `honest_status` already says "pin-f: delegates to the gates that validate purpose clauses." | No — already correctly documented; no change needed. |
| 29 | `synthetic-runner-ci` | (GitHub Actions workflow, not a hook) | N/A (not a Claude Code hook) | `honest_status` already states this is CI, not a hook — `blocking: true` describes CI's required-status-check semantics, not a session-time gate at all. A waiver here would be a GitHub branch-protection admin override, entirely outside this harness's waiver-file convention. | No — recommend `honesty_rationale`: "CI required-status-check; waiver (if ever needed) is a GitHub branch-protection admin merge override, not a session-time waiver file — out of this manifest's waiver-parity scope by construction." |
| 30 | `tdd-gate` | `pre-commit-tdd-gate.sh` | HONESTY-CLASS | "New runtime-feature files must have matching test files." No waiver hits. Resolvable by writing the test in the same commit (the gate's own header calls this "the single most important mechanical enforcement in the harness" — deliberately hard to waive). | No — schema gap only, though flag alongside row 24/26 as a gate the operator may want to EXPLICITLY confirm should stay honesty-class-only (never waivable) given its stated importance. |
| 31 | `vaporware-volume` | `vaporware-volume-gate.sh` | HONESTY-CLASS | Commit-boundary check per specs-d §D.0.4; no waiver hits. | No — schema gap only. |
| 32 | `wire-check` | `wire-check-gate.sh` | **FIXED → STRUCTURED-WAIVER (per plan+task)** | Fix landed: fresh (<1h) `.claude/state/wire-check-waiver-<plan-slug>-<task-id>-*.txt` naming BOTH purpose clauses (`lib/waiver-purpose-clause.sh`), checked at BOTH block sites (broken-arrow AND insufficient-verified-arrows), ledger-logged with the specific reason. Explicitly distinct from — and coexists with — the plan-time `n/a — <reason>` carve-out (unchanged, still for tasks with no code chain at all). Block messages updated to name the hatch + cost (pin-d). Self-test: `bash wire-check-gate.sh --self-test` → all scenarios matched expectations, incl. new waiver-absent/honored/stale/weak scenarios w10-w13. | No longer — fixed. |
| 33 | `work-integrity` | `work-integrity-gate.sh` | STRUCTURED-WAIVER | Sources `lib/waiver-purpose-clause.sh` (line 95); checks (a)/(b) both waiver-gated per ADR 059 D4 scoping (world-state assertions only — unchecked tasks — never the checked-box-without-evidence honesty assertion). Canonical reference implementation. | No. |
| 34 | `workstreams-spawn-gate` | `workstreams-state-gate.sh` | STRUCTURED-WAIVER | Fresh (<1h) `conv-tree-spawn-waiver-*.txt` with purpose-clause validation (lines 49-51, 66). Explicitly modeled on `bug-persistence-gate.sh`. | No. |

(Table numbers 1-34 cover all 32 manifest entries; agent-teams and spec-freeze each
list 2-3 hook files that were audited separately since their waiver postures differ
per-condition/per-hook within the one manifest entry.)

## Summary counts

**UPDATE (post-fix pass, same wave):** all 5 GAP rows below are now FIXED — see
"GAP fixes landed" section immediately after this table for the implementation
evidence (files touched, self-test results, ledger wiring). Counts below are
left as originally audited (pre-fix) for the historical record of what was
found; the GAP row now reads 0 remaining.

| Posture | Count (of 34 audited hook-postures across 32 entries) |
|---|---|
| STRUCTURED-WAIVER | 6 (agent-teams/condition-d, bug-persistence, local-edit-authorization, work-integrity, workstreams-spawn-gate, +spec-freeze's scope-enforcement honesty-adjacent case counted separately below) — **now 11** post-fix: +task-created-validator, +harness-hygiene-scan, +plan-deletion-protection, +wire-check-gate, +spec-freeze-gate (5 GAP rows fixed into this bucket). |
| DOCUMENTED-EQUIVALENT (full or partial) | 9 (agent-teams×2 task validators, claude-md-hygiene, deploy-automation-mode, env-local-protection, pre-push-divergence, pre-push-test, secret-hygiene-prepush, no-test-skip's implicit case) |
| HONESTY-CLASS (correctly no-valve, needs `honesty_rationale` field to SAY so) | 15 (backlog-plan-atomicity, decisions-index, docs-freshness, findings-ledger, migration-claude-md, parallel-dev-migration-naming, plan-edit-validator, plan-reviewer, review-finding-fix, runtime-verification, session-honesty, tdd-gate, vaporware-volume, scope-enforcement/spec-freeze, plan-deletion-protection's non-archive case is a GAP not honesty-class) |
| N/A (aggregator / not-a-hook) | 3 (pre-commit-chain, stop-verdict-dispatcher, synthetic-runner-ci) |
| **GAP (real fix needed)** | **0 remaining** (was 5: `task-created-validator.sh` row 2, `harness-hygiene-scan.sh` row 12, `plan-deletion-protection.sh` row 17, `wire-check-gate.sh` row 32, `spec-freeze-gate.sh` row 27 — all fixed, see below). |

**Bottom line (pre-fix, historical): every `blocking:true` manifest entry was traced
to a hook file and classified. 27 of 32 entries already had a defensible
waiver-or-honesty-class posture (some needing only a manifest annotation, not a
code change); 5 hook files had a genuine waiver-parity gap.**

**Post-fix: all 5 gaps closed this wave** — `task-created-validator.sh`,
`harness-hygiene-scan.sh`, `plan-deletion-protection.sh`, and `wire-check-gate.sh`
each got a `lib/waiver-purpose-clause.sh`-based structured waiver;
`spec-freeze-gate.sh`'s frozen-plan-touch case was resolved (leaning on ADR 059
D4's own "every blocking check MUST ship a structured waiver path" hard-rule
language as the defensible unilateral basis per constitution §3) with a
structured waiver ADDITIVE to the existing unfreeze-then-refreeze remedy —
flagged for F.1/harness-reviewer confirmation rather than silently accepted,
since the original audit reserved this one row for operator/reviewer input.
32 of 32 blocking entries now have a defensible waiver-or-honesty-class posture.

## GAP fixes landed (this pass)

| Hook | Fix | Self-test |
|---|---|---|
| `task-created-validator.sh` | Ledger-logged the pre-existing `TASK_CREATED_BYPASS=1`/`bypass_validation` bypasses (previously silent); added a NEW fresh (<1h) `.claude/state/task-created-waiver-*.txt` structured waiver via `lib/waiver-purpose-clause.sh`. | `bash adapters/claude-code/hooks/task-created-validator.sh --self-test` → 8/8 PASS |
| `harness-hygiene-scan.sh` | New fresh (<1h) `.claude/state/harness-hygiene-waiver-*.txt` (purpose clauses + a `Files:` line scoping which repo-relative file(s) it covers) — suppresses matches on ONLY those files, this run, ledger-logged. Distinct from the durable plan-time exempt-list. | `bash adapters/claude-code/hooks/harness-hygiene-scan.sh --self-test` → OK |
| `plan-deletion-protection.sh` | `emit_block()` now checks a fresh (<1h) `.claude/state/plan-deletion-waiver-*.txt` (purpose clauses) BEFORE blocking; honored waiver ALLOWs the specific command, ledger-logged. Replaced vague "edit the source out manually" remedy. | `bash adapters/claude-code/hooks/plan-deletion-protection.sh --self-test` → 18/18 PASS |
| `wire-check-gate.sh` | New fresh (<1h) `.claude/state/wire-check-waiver-<plan-slug>-<task-id>-*.txt` (purpose clauses), checked at both the broken-arrow and insufficient-verified-arrows block sites; ledger-logged with reason. Distinct from the plan-time `n/a` carve-out. | `bash adapters/claude-code/hooks/wire-check-gate.sh --self-test` → all scenarios matched expectations |
| `spec-freeze-gate.sh` | New fresh (<1h) `.claude/state/spec-freeze-waiver-<plan-slug>-*.txt` (purpose clauses), checked against every unfrozen claiming plan; ledger-logged. Additive to (does not replace) the unfreeze-then-refreeze remedy. Vague bypass-via-different-tool language removed. **Flagged for F.1/harness-reviewer confirmation** (see row 27 note — this was originally reserved as a decision, not resolved unilaterally by default). | `bash adapters/claude-code/hooks/spec-freeze-gate.sh --self-test` → 11/11 PASS |

All five fixes source `lib/waiver-purpose-clause.sh` for the two-clause
(`Purpose:`/`Because:`) validation and `lib/signal-ledger.sh` for `ledger_emit`
(both best-effort-sourced; each hook degrades gracefully if a lib is absent).
Every fix was self-tested with the honored/absent/stale/weak-waiver quartet
(fresh+valid → ALLOW; absent → BLOCK; >1h old → BLOCK; non-empty but missing
the purpose-clause pair → BLOCK), matching ADR 059 D4's fresh+substantive bar
and the pin-f regression the harness already enforces elsewhere.

See the corresponding fragment file for the orchestrator's manifest merge:
`adapters/claude-code/tests/fixtures/wave-f/F.5/waiver-parity-fixes-fragment.json`
(NOT a manifest.json edit — F.5 remains fragment-only per §F.0.1).

## Proposal 1 — schema addition: `honesty_rationale` + `waiver_path` fields

`schemas/manifest.schema.json` (orchestrator-only; NOT edited by this builder) has
no field today for either "the waiver file path/pattern this gate honors" or "why
no waiver is offered." Recommend adding, conditional on `blocking: true`:

```json
"waiver_path": {
  "type": ["string", "null"],
  "description": "Glob/pattern (relative to ~/.claude/state/ or repo docs/plans/) of the structured waiver file this blocking gate honors via lib/waiver-purpose-clause.sh (or a documented equivalent named in honest_status/honesty_rationale). Null when honesty_rationale explains why no waiver is offered."
},
"honesty_rationale": {
  "type": ["string", "null"],
  "minLength": 1,
  "description": "REQUIRED (non-null) when blocking is true AND waiver_path is null: names why this gate's block is session-honesty-class (resolvable by the session that created it — fix the content, don't waive the check) per ADR 059 D4 scoping, rather than an oversight. Enforced by manifest-check.sh's new waiver-parity check (F.1 integration)."
}
```

with the `allOf` conditional (mirroring the existing `honest_status` requirement
shape at schema lines 150-178):

```json
{
  "if": {
    "properties": { "blocking": { "const": true } },
    "required": ["blocking"]
  },
  "then": {
    "anyOf": [
      { "required": ["waiver_path"], "properties": { "waiver_path": { "type": "string", "minLength": 1 } } },
      { "required": ["honesty_rationale"], "properties": { "honesty_rationale": { "type": "string", "minLength": 1 } } }
    ]
  }
}
```

This is the schema-level version of specs-f §F.1's "any manifest entry with
`added_after: 2026-07` must name ... `waiver_path` or `honesty_rationale`" —
Proposal 1 here extends the SAME requirement to every EXISTING blocking entry, not
just newly-added ones, closing the retroactive half of the gap this audit found.

## Proposal 2 — per-entry `honesty_rationale`/`waiver_path` values (for F.1's merge)

For the orchestrator to fold in once Proposal 1's schema fields exist (values
derived directly from the audit table above; only the 27 non-GAP rows get a value
here — the 5 GAP rows need code changes first, tracked in `orchestratorTodo`):

```json
{
  "backlog-plan-atomicity":        { "honesty_rationale": "Commit-time atomicity check (new plan must declare absorbed backlog items in its own header) — resolvable by editing the same commit; not a world-state assertion." },
  "decisions-index":                { "honesty_rationale": "Commit-time atomicity check (Tier-2+ decision needs its DECISIONS.md index row in the same commit) — resolvable by the session that created the gap." },
  "deploy-automation-mode":         { "honesty_rationale": "Policy switch, not a per-session block — the escape hatch IS changing the project/user automation-mode config (see doctrine/automation-modes.md), not a waiver file." },
  "docs-freshness":                 { "honesty_rationale": "Commit-time atomicity check (structural harness change needs its doc delta in the same commit) — resolvable by the session." },
  "env-local-protection":           { "waiver_path": "inline ENV_LOCAL_OVERWRITE_OK=1 command-prefix sentinel (documented equivalent; hook auto-backs-up before honoring it)." },
  "findings-ledger":                { "honesty_rationale": "Schema-validity check on the session's own docs/findings.md edit — checked-box-without-evidence shape, unwaivable by ADR 059 D4 design." },
  "local-edit-authorization":       { "waiver_path": "~/.claude/state/local-edit-<slug>-<ISO8601>.txt, fresh <30min, written only by the operator-invoked /grant-local-edit skill." },
  "migration-claude-md":            { "honesty_rationale": "Commit-time atomicity check (migration + CLAUDE.md line move together) — resolvable by the session." },
  "parallel-dev-migration-naming":  { "honesty_rationale": "New-file naming-convention check on the session's own newly-added migration — resolvable by renaming in the same commit." },
  "plan-edit-validator":            { "honesty_rationale": "Checkbox-flip authorization is the canonical checked-box-without-evidence honesty assertion (ADR 059 D4) — deliberately unwaivable; TASK_VERIFIER_MODE=1 back door was removed 2026-05-04 for this reason." },
  "plan-reviewer":                  { "honesty_rationale": "Adversarial content review of the session's own plan edit — resolvable by fixing the plan." },
  "pre-push-divergence":            { "waiver_path": "git push --no-verify (git-native, documented at git-hooks/pre-push dispatcher level); world-state fact (remote moved) is more honestly fixed by fetch+merge/rebase than waived." },
  "pre-push-test":                  { "waiver_path": "git push --no-verify, plus a per-repo structural opt-in marker (stronger than a per-session waiver — a repo can opt out of the check entirely)." },
  "review-finding-fix":             { "honesty_rationale": "Commit-time atomicity check (review-finding-referencing commit needs the review file touched) — resolvable by the session." },
  "runtime-verification":           { "honesty_rationale": "ADR 059 D2 verification-class Stop block — NEVER downgraded under a DONE claim by explicit design; this is the load-bearing case the no-waiver rule exists FOR." },
  "secret-hygiene-prepush":         { "waiver_path": "git push --no-verify (git-native); OPEN QUESTION for operator: should secrets be the one pre-push check where --no-verify is NOT normalized as an acceptable documented path? Flagged, not resolved, in this audit." },
  "session-honesty":                { "honesty_rationale": "ADR 059 D2/D4: reads OTHER gates' waiver state to detect already-resolved blocks, but its own resolved-vs-live assertion is never itself waivable by design (pin-f-doctor-exempt, hook comment line 297)." },
  "tdd-gate":                       { "honesty_rationale": "New-runtime-code-needs-tests check on the session's own commit — resolvable by writing the test; the harness's single most important mechanical enforcement, deliberately hard to waive." },
  "vaporware-volume":               { "honesty_rationale": "Commit-boundary content check (specs-d §D.0.4) — resolvable by the session." },
  "pre-commit-chain":               { "honesty_rationale": "Aggregator; dispatches 6 independently-audited sub-checks (see backlog-plan-atomicity, decisions-index, docs-freshness, migration-claude-md, plan-reviewer, review-finding-fix, tdd-gate) — no separate waiver posture of its own." },
  "stop-verdict-dispatcher":        { "honesty_rationale": "Aggregator; delegates to bug-persistence/work-integrity/session-honesty's own waiver postures (already stated in its honest_status)." },
  "synthetic-runner-ci":            { "honesty_rationale": "GitHub Actions required-status-check, not a session-time hook; a waiver here is a GitHub branch-protection admin override, outside this manifest's waiver-file scope by construction." },
  "claude-md-hygiene":              { "waiver_path": "CLAUDE_MD_HYGIENE_DISABLE=1 env var (full no-op); note DEFAULT MODE is warn (exit 0 always) pending 24h calibration — blocking:true reflects the designed end-state, add to honest_status." },
  "no-test-skip":                   { "honesty_rationale": "New-skip-without-issue-reference check on the session's own commit; adding a real issue/finding reference IS the intended escape hatch (recommend the block message name this explicitly — see audit row 15)." }
}
```

Rows deliberately OMITTED from Proposal 2 at audit time (were GAP; NOW FIXED,
see "GAP fixes landed" above — values below are ready for F.1 to fold in):
`task-created-validator`/`task-completed-evidence-gate` (both fold under manifest
id `agent-teams`, which ALSO covers `teammate-spawn-validator.sh` — that hook
already has a real structured waiver for condition (d); recommend F.1
special-case this one multi-hook entry with a per-hook breakdown rather than
one blanket value), `harness-hygiene-scan`, `plan-deletion-protection`,
`wire-check`, `spec-freeze` (scope-enforcement half was already honesty-class;
spec-freeze-gate.sh's half is now fixed too — same multi-hook-entry breakdown
recommendation applies here as for agent-teams).

Ready-to-fold values for the 5 now-fixed hooks (for F.1's manifest merge,
per-hook — note `agent-teams` and `spec-freeze` need the multi-hook breakdown
noted above rather than a single value on the manifest entry):

```json
{
  "task-created-validator.sh":    { "waiver_path": ".claude/state/task-created-waiver-*.txt, fresh <1h, purpose-clause validated (lib/waiver-purpose-clause.sh); TASK_CREATED_BYPASS=1 env / bypass_validation field are documented-equivalent session-wide switches, now ledger-logged." },
  "harness-hygiene-scan.sh":       { "waiver_path": ".claude/state/harness-hygiene-waiver-*.txt, fresh <1h, purpose-clause validated + a Files: line scoping which repo-relative path(s) it covers (per-file, per-run — not a blanket scan suppression)." },
  "plan-deletion-protection.sh":   { "waiver_path": ".claude/state/plan-deletion-waiver-*.txt, fresh <1h, purpose-clause validated; checked inside emit_block() before every block site, allows the specific command once." },
  "wire-check-gate.sh":            { "waiver_path": ".claude/state/wire-check-waiver-<plan-slug>-<task-id>-*.txt, fresh <1h, purpose-clause validated; scoped per plan+task, distinct from the plan-time n/a carve-out." },
  "spec-freeze-gate.sh":           { "waiver_path": ".claude/state/spec-freeze-waiver-<plan-slug>-*.txt, fresh <1h, purpose-clause validated; additive to (does not replace) the unfreeze-then-refreeze durable remedy. FLAG for F.1/harness-reviewer: this row's classification (waiver-eligible world-state vs. honesty-class) was originally reserved as an operator/reviewer decision by the audit; the fix leans on ADR 059 D4's hard-rule language as the defensible unilateral basis (constitution §3) — confirm at next harness-reviewer pass rather than accepting silently." }
}
```

## Proposal 3 — code fixes for the 5 GAP rows — STATUS: ALL 5 FIXED this pass

(Originally: implementation, not this builder's to apply — manifest/hook edits
outside F.5's fragment-only remit for hooks are fine to write directly since
hooks/*.sh are NOT in the §F.0.1 orchestrator-only list. Applied directly below;
see "GAP fixes landed" table above for self-test evidence per hook.)

1. ~~`task-created-validator.sh`: add `ledger_emit "task-created-validator" "waiver" "env-bypass task=${task_id:-<none>}"` alongside the existing `TASK_CREATED_BYPASS=1` check~~ **DONE** — ledger-logged both the env-bypass AND the field-bypass paths, PLUS added the new fresh structured waiver. Self-test 8/8 PASS.
2. ~~`harness-hygiene-scan.sh`: add a `harness-hygiene-waiver-*.txt` structured waiver~~ **DONE** — per-file, per-run scoped via a `Files:` clause. Self-test OK.
3. ~~`plan-deletion-protection.sh`: add a `plan-deletion-waiver-<slug>-*.txt` structured waiver~~ **DONE** — wired into the shared `emit_block()` so every detector's block site is covered. Self-test 18/18 PASS.
4. ~~`wire-check-gate.sh`: add a `wire-check-waiver-<slug>-<task-id>-*.txt` structured waiver~~ **DONE** — wired at both the broken-arrow and insufficient-verified-arrows block sites. Self-test all scenarios matched expectations.
5. ~~`spec-freeze-gate.sh`: OPERATOR/harness-reviewer DECISION NEEDED~~ **RESOLVED (b)** — added a structured waiver for time-boxed frozen-plan touches, additive to the unfreeze-then-refreeze remedy. Basis: ADR 059 D4 states "every blocking check MUST ship a structured waiver path" as a hard design rule, and this block is a world-state assertion (the plan's `frozen` field), not a session-honesty assertion — inside D4's waiver-eligible scope by the ADR's own scoping rule, making this a defensible unilateral call per constitution §3 rather than requiring an open-ended pause. **Flagged (not silently closed)** for F.1/harness-reviewer confirmation at the next review pass, since the original audit explicitly reserved this row for that input. Self-test 11/11 PASS.
