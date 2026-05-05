# GAP-14 — Per-hook reconciliation proposals (template vs live)

Date: 2026-05-04
Plan: `docs/plans/phase-1d-e-3-gap-14-reconciliation.md`
Originating discovery: `docs/discoveries/2026-05-04-template-vs-live-divergence-across-other-hooks.md`

## Methodology

For each divergent hook in the `settings.json.template` (committed source-of-truth for `install.sh`) vs `~/.claude/settings.json` (gitignored live config the running session reads), this document records:

- **Originating commit / plan / decision** — when the hook entered the repo and the design intent.
- **Where wired today** — present in template, in live, or both.
- **Verdict** — `live → template` (add to template), `template → live` (add to live), `intentional divergence` (document and keep), or `live drift, remove from live`.
- **Reversibility** — REVERSIBLE or IRREVERSIBLE per the discovery-protocol decide-and-apply discipline.
- **Evidence** — commit SHAs, plan paths, doc references.

The detector (`settings-divergence-detector.sh`) was the worklist source. The user reviews the proposals; the orchestrator applies REVERSIBLE outcomes autonomously.

## Hook 1 — `outcome-evidence-gate.sh`

- **Originating commit:** `e3d5f0a` (2026-04-19) — `feat(task-verifier + hook): require before/after reproduction for fix tasks`.
- **Design intent:** Fix tasks (matching fix/bug/broken/etc.) require before/after reproduction evidence — same runtime verification command showing FAIL pre-fix and PASS post-fix.
- **Inventory entry:** `docs/harness-architecture.md` line 25 — Gen 5 mechanism, classified Mechanical (PreToolUse).
- **Where wired today:**
  - Live `~/.claude/settings.json` lines 133-141 — PreToolUse `Edit|Write` matcher.
  - Template `adapters/claude-code/settings.json.template` — NOT WIRED.
- **Verdict:** **`live → template`** — add to template at the matching position.
- **Reversibility:** REVERSIBLE — single JSON insertion; revert via single removal.
- **Rationale:** The hook exists in `adapters/claude-code/hooks/outcome-evidence-gate.sh` (committed file), is documented in `docs/harness-architecture.md` as canonical Gen 5 mechanism, and the originating commit `e3d5f0a` modified hooks but never updated the template. The template lag is drift, not intent.

## Hook 2 — `systems-design-gate.sh`

- **Originating commit:** `483f5f6` (2026-04-19) — `feat(harness): Gen 5 — design-mode planning + outcome-focused reviewers`.
- **Design intent:** Edits to design-mode files (CI/CD workflows, migrations, vercel.json, Dockerfile, etc.) require an active plan with `Mode: design` in `docs/plans/`. Escape hatch: `Mode: design-skip`.
- **Inventory entry:** `docs/harness-architecture.md` line 26 + line 163 — Gen 5 mechanism, classified Mechanical (PreToolUse).
- **Where wired today:**
  - Live `~/.claude/settings.json` lines 142-150 — PreToolUse `Edit|Write` matcher.
  - Template — NOT WIRED.
- **Verdict:** **`live → template`** — add to template adjacent to outcome-evidence-gate.
- **Reversibility:** REVERSIBLE.
- **Rationale:** Same pattern as Hook 1. The Gen 5 commit shipped the hook file + rule + agent + architecture-doc inventory entry but did not update the template. Cross-referenced from `rules/design-mode-planning.md` "Enforcement summary" table as `landed`.

## Hook 3 — `no-test-skip-gate.sh`

- **Originating commit:** `5c8e3e4` (2026-04-20) — `feat(harness): no-test-skip gate + deploy-to-production rule`.
- **Design intent:** Staged `*.spec.ts` / `*.test.ts` diffs are scanned for new `test.skip(`, `it.skip(`, `.skip(` on describe blocks, and `xtest(` / `xdescribe(`. Blocked unless the skip line references an issue number.
- **Inventory entry:** `docs/harness-architecture.md` line 40 — classified Mechanical (pre-commit).
- **Where wired today:**
  - Live `~/.claude/settings.json` lines 160-167 — PreToolUse `Bash` matcher (fires on `git commit`-style flow per the hook's own internal triggers).
  - Template — NOT WIRED.
- **Verdict:** **`live → template`** — add to template at matching position.
- **Reversibility:** REVERSIBLE.
- **Rationale:** Cross-referenced from `rules/testing.md` ("No Skipped Tests" enforcement). The originating commit shipped the hook file + rule but never updated the template.

## Hook 4 — `check-harness-sync.sh`

- **Originating commit:** `fa50661` (2026-04-18) — `Initial release v1.0` (the hook file shipped with the v1.0 baseline).
- **Design intent:** Warns if `~/.claude/` files have diverged from the harness repo. Originally a SessionStart hook, then composed into the pre-commit-gate flow.
- **Inventory entry:** `docs/harness-architecture.md` line 170.
- **Where wired today:**
  - Live `~/.claude/settings.json` line 220 — composed into the pre-commit Bash hook: `bash ~/.claude/hooks/check-harness-sync.sh || exit 1; bash ~/.claude/hooks/pre-commit-gate.sh || exit 1`.
  - Template line 111 — pre-commit hook only invokes `pre-commit-gate.sh` directly, no harness-sync check.
- **Verdict:** **`live → template`** — update the template's pre-commit hook composition to match live (run `check-harness-sync.sh` before `pre-commit-gate.sh`, both hard-failing).
- **Reversibility:** REVERSIBLE — JSON command-string edit.
- **Rationale:** The composition reflects deliberate ordering: harness-sync check first (cheap; exits early if drift exists), then pre-commit-gate (expensive). Live form is canonical per the architecture-doc entry. Template's older form (using `|| true`) was correct at v1.0 release before pre-commit-gate matured into a hard-fail mechanism.

## Hook 5 — Public-repo blocker variants (template canonical, live needs upgrade)

This is the only divergence going the OPPOSITE direction.

- **Originating evolution:** The public-repo blocker started simple (the live form: detect `gh repo create --public` etc., always block) and was later upgraded in the template with a `read-local-config.sh public-blocked` lookup so the block message can identify whether the current account/directory is policy-blocked vs. just guard-blocked.
- **Inventory entry:** `docs/harness-architecture.md` doesn't itemize this inline-Bash hook by name; it's documented in `rules/security.md` "Public Repositories (Strict)".
- **Where wired today:**
  - Live `~/.claude/settings.json` lines 196-203 — SIMPLE form, no policy-config lookup.
  - Template lines 87-95 — ELABORATE form with `POLICY_BLOCK` check via `read-local-config.sh`.
- **Verdict:** **`template → live`** — upgrade live to match template.
- **Reversibility:** REVERSIBLE — JSON command-string replacement; both forms produce the same block-with-exit-1 outcome on the trigger pattern, the elaborate form just adds an additional informational line about policy-block status.
- **Rationale:** The elaborate form is strictly more informative — it produces the same block with a richer error message when the account is policy-blocked. The simple form in live is older and missed the upgrade. Template form is canonical because it's the documented `~/.claude/scripts/read-local-config.sh` integration form referenced in `rules/security.md`.

## Hook 6 — Force-push / `--no-verify` Bash blocker (in-scope adjunct)

The plan's "public-repo-blocker variants" reference resolved on inspection: the variant cluster includes the adjacent force-push / `--no-verify` blocker which is similarly divergent.

- **Design intent:** Blocks `git push --force` / `-f` and any command containing `--no-verify`, requiring explicit user authorization.
- **Cross-reference:** `rules/git.md` "Safe push methods", `rules/security.md` destructive-ops clause.
- **Where wired today:**
  - Live `~/.claude/settings.json` lines 187-195 — present, Bash matcher.
  - Template — NOT WIRED.
- **Verdict:** **`live → template`** — add to template adjacent to the public-repo blocker.
- **Reversibility:** REVERSIBLE.
- **Rationale:** Same drift pattern. The blocker enforces existing rule-level discipline (`rules/git.md`) and should fire on every install, not just this maintainer's machine.

## Out-of-scope divergences (flagged for future work)

The detector also surfaced these template-vs-live divergences that are NOT in this plan's scope. They should be tracked separately — proposing one new backlog entry to bundle the cleanup.

- **SessionStart compact-recovery hook** — live has hardcoded per-project subdirectory paths in its `for BACKLOG in ...` and plan-glob lists; template lacks them. Likely live drift (machine-specific tweak that crept in); template canonical for new installs. Per-project paths shouldn't live in the global hook.
- **SessionStart automation-mode initializer** — present in template, NOT in live. Template canonical; live missed the wiring update when automation-mode shipped.
- **SessionStart `claude-config` harness-sync warn hook** — present in template but references legacy `~/claude-projects/claude-config` path (predates the rename to `neural-lace`). Live correctly omits it. Template needs path correction or removal; this is template drift.
- **UserPromptSubmit title-bar hook** — template version reads `automation-mode` from local config and includes it in the title; live version is older (just basename). Template canonical.
- **PreToolUse `tool-call-budget.sh` matcher** — template `.*`, live `Edit|Write|Bash`. Live form is more targeted (avoids firing on Read-only tools); the architecture-doc description aligns with the budget-counter applying to Edit/Write/Bash specifically. Live canonical.

These six divergences are real but out of GAP-14's named scope. They will surface again on the next `settings-divergence-detector.sh` run; the recommendation is to track as a follow-up backlog item (`HARNESS-GAP-14-extra` or similar).

## Summary table

| Hook | Direction | Reversibility | Action |
|------|-----------|---------------|--------|
| `outcome-evidence-gate.sh` | live → template | REVERSIBLE | Add Edit\|Write entry to template |
| `systems-design-gate.sh` | live → template | REVERSIBLE | Add Edit\|Write entry to template |
| `no-test-skip-gate.sh` | live → template | REVERSIBLE | Add Bash entry to template |
| `check-harness-sync.sh` (composition) | live → template | REVERSIBLE | Update template's pre-commit Bash command-string to call `check-harness-sync.sh` first, both hard-fail |
| Public-repo blocker | template → live | REVERSIBLE | Upgrade live's command-string to match template's elaborate form |
| Force-push / `--no-verify` blocker | live → template | REVERSIBLE | Add Bash entry to template |

All six are REVERSIBLE per the discovery-protocol decide-and-apply discipline; auto-applying without further pause.

## Post-reconciliation expected state

After Task 2 applies these proposals:

- `settings-divergence-detector.sh` reports remaining divergences only in the six "out-of-scope" buckets above.
- A follow-up backlog entry should be opened to absorb those into a future cleanup pass.
- The plan-named four hooks + public-repo variants are reconciled.

## Phase 1d-G addendum (2026-05-04)

The four out-of-scope SessionStart / UserPromptSubmit divergences flagged
above were resolved in Phase 1d-G Task 2. The template was canonical for
all four; live `~/.claude/settings.json` was updated to match:

1. **Compact-recovery hook** — removed hardcoded per-project subdirectory paths (project-specific backlog and plans paths). The global hook should not enumerate downstream-project paths.
2. **Automation-mode initializer** — added missing SessionStart block (template line 348 form).
3. **Legacy `claude-config` harness-sync hook** — removed (referenced pre-rename path; template correctly omits it).
4. **UserPromptSubmit title-bar** — upgraded to automation-mode-aware form (template line 274 form).

After these edits, `jq -S '.hooks'` output of live and template is byte-
identical. Remaining file-level divergence is confined to the
`permissions` array (per-machine local config — intentional, not subject
to reconciliation).

The fifth out-of-scope item (`tool-call-budget.sh` matcher: live
canonical) remains as documented; no change needed.
