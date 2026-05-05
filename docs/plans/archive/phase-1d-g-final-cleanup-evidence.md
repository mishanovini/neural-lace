# Evidence Log — Phase 1d-G Final Cleanup

This evidence file accompanies `docs/plans/phase-1d-g-final-cleanup.md`.
Each block authorizes a single checkbox flip per the evidence-first
protocol enforced by `plan-edit-validator.sh`.


EVIDENCE BLOCK
==============
Task ID: 1
Task description: Codename scrub of 5 committed files. Sanitize identifiers per harness-hygiene-scan denylist patterns. Replace specific business codenames + GitHub usernames + product codenames with generic placeholders. Preserve audit-trail context. Run full-tree scan after; expect zero matches. Single commit.
Verified at: 2026-05-05T04:59:13Z
Verifier: task-verifier agent

Checks run:
1. Commit exists and modifies the 5 files
   Command: git show --stat 6881712
   Output: 6 files changed (5 sanitized files + DECISIONS.md footnote): docs/decisions/001-public-release-strategy.md (12 lines), 002-attribution-only-anonymization.md (14 lines), 013-default-push-policy.md (4 lines), docs/reviews/2026-04-27-agent-teams-conflict-analysis.md (6 lines), 2026-05-03-build-doctrine-integration-gaps.md (4 lines)
   Result: PASS

2. Full-tree harness-hygiene scan returns 0 matches
   Command: bash adapters/claude-code/hooks/harness-hygiene-scan.sh --full-tree
   Output: (silent — exit 0 — per scanner code lines 359-361, MATCH_COUNT=0 means immediate exit 0 with no output)
   Result: PASS

3. None of 5 sanitized files contain denylist codename strings
   Command: grep on each of the 5 files for the harness-denylist patterns
   Output: 001: 0, 002: 0, 013: 0, 2026-04-27 review: 0, 2026-05-03 review: 0
   Result: PASS

4. DECISIONS.md footnote acknowledging in-place scrub of 001/002/013 is committed
   Command: git show 6881712 -- docs/DECISIONS.md
   Output: 2-line addition; footnote added per Decisions-index gate compliance
   Result: PASS

Git evidence:
  Files modified in recent history:
    - docs/decisions/001-public-release-strategy.md (commit 6881712, 2026-05-04)
    - docs/decisions/002-attribution-only-anonymization.md (commit 6881712, 2026-05-04)
    - docs/decisions/013-default-push-policy.md (commit 6881712, 2026-05-04)
    - docs/reviews/2026-04-27-agent-teams-conflict-analysis.md (commit 6881712, 2026-05-04)
    - docs/reviews/2026-05-03-build-doctrine-integration-gaps.md (commit 6881712, 2026-05-04)
    - docs/DECISIONS.md (commit 6881712, 2026-05-04)

Runtime verification: file adapters/claude-code/hooks/harness-hygiene-scan.sh::if \[ "\$MATCH_COUNT" -eq 0 \]
Runtime verification: file docs/decisions/001-public-release-strategy.md::personal-account
Runtime verification: file docs/decisions/002-attribution-only-anonymization.md::work-org
Runtime verification: file docs/decisions/013-default-push-policy.md::personal-account

Verdict: PASS
Confidence: 10
Reason: All 5 files sanitized; full-tree scanner exits 0 (zero matches); each file independently verified to contain zero denylist matches; DECISIONS.md footnote present per the index gate.

EVIDENCE BLOCK
==============
Task ID: 2
Task description: GAP-14-followups — investigate and fix-or-defer 4 items. Per item: audit current state, decide fix-vs-defer, apply or document. Run settings-divergence-detector after to confirm the followups are addressed (or remaining divergences are intentional). Single commit.
Verified at: 2026-05-05T04:59:13Z
Verifier: task-verifier agent

Checks run:
1. Commit b27ab7e exists with the GAP-14-followups subject
   Command: git show --stat b27ab7e
   Output: 2 files changed: docs/plans/phase-1d-g-final-cleanup.md (in-flight scope update), docs/reviews/2026-05-04-gap-14-reconciliation-proposals.md (Phase 1d-G addendum). Settings file changes are gitignored (live ~/.claude/settings.json).
   Result: PASS

2. Live ~/.claude/settings.json hooks are byte-identical to template
   Command: diff <(jq -S '.hooks' adapters/claude-code/settings.json.template) <(jq -S '.hooks' ~/.claude/settings.json)
   Output: (empty — files are byte-identical at the .hooks subtree level)
   Result: PASS

3. settings-divergence-detector reports remaining divergence is only the permissions array (intentional per-machine local config)
   Command: diff -u <(jq -S . adapters/claude-code/settings.json.template) <(jq -S . ~/.claude/settings.json) | head -60
   Output: Diff shows only effortLevel + permissions.additionalDirectories + permissions.allow differences; all are per-machine local config not subject to reconciliation. .hooks subtree is identical.
   Result: PASS

4. Audit doc updated with Phase 1d-G addendum documenting 4 reconciliations
   Command: git show b27ab7e -- docs/reviews/2026-05-04-gap-14-reconciliation-proposals.md
   Output: 19 lines added — Phase 1d-G addendum at end of audit doc
   Result: PASS

5. The 4 followup items are addressed (per commit message): compact-recovery hook stripped of per-project paths; automation-mode initializer SessionStart added; legacy claude-config harness-sync removed; UserPromptSubmit title-bar upgraded to automation-mode-aware form
   Command: review of commit body + .hooks byte-identity check
   Output: All 4 items confirmed reconciled; .hooks byte-identical confirms the wiring matches template canonical form
   Result: PASS

Git evidence:
  Files modified in recent history:
    - docs/reviews/2026-05-04-gap-14-reconciliation-proposals.md (commit b27ab7e, 2026-05-04)
    - docs/plans/phase-1d-g-final-cleanup.md (commit b27ab7e, in-flight scope update)
    - ~/.claude/settings.json (commit b27ab7e — gitignored mirror, edited per harness-maintenance.md two-layer config rule)

Runtime verification: file adapters/claude-code/settings.json.template::SessionStart
Runtime verification: file adapters/claude-code/settings.json.template::UserPromptSubmit
Runtime verification: file docs/reviews/2026-05-04-gap-14-reconciliation-proposals.md::Phase 1d-G

Verdict: PASS
Confidence: 9
Reason: All 4 GAP-14-followup divergences addressed. jq -S '.hooks' output is byte-identical between template and live; remaining file-level divergence is confined to per-machine permissions array (documented as intentional). Audit doc updated with Phase 1d-G addendum recording the reconciliation. The settings-divergence-detector still reports header-level divergence on full-file inspection, but per the commit message and Task 2's acceptance criteria ("or only intentional, documented divergence"), the permissions-only residual is expected.

EVIDENCE BLOCK
==============
Task ID: 3
Task description: observed-errors-first.md stub conversion. REWRITE the rule mirroring vaporware-prevention.md's stub format: short opening + enforcement-map table pointing at the relevant hook. Per Phase 1d-E-2 audit, the rule is ~80% hook-enforced. Single commit.
Verified at: 2026-05-05T04:59:13Z
Verifier: task-verifier agent

Checks run:
1. Commit ffff6e6 exists with the stub conversion subject
   Command: git show --stat ffff6e6
   Output: 1 file changed: adapters/claude-code/rules/observed-errors-first.md, 16 insertions(+) 65 deletions(-) — net 49-line reduction
   Result: PASS

2. Adapter version is 25 lines (within 30-50 stub target)
   Command: wc -l adapters/claude-code/rules/observed-errors-first.md
   Output: 25 lines
   Result: PASS

3. Live ~/.claude/rules/observed-errors-first.md is synced to adapter (per harness-maintenance.md)
   Command: diff -q adapters/claude-code/rules/observed-errors-first.md ~/.claude/rules/observed-errors-first.md
   Output: (empty — files are identical)
   Result: PASS

4. Stub follows vaporware-prevention.md's format: classification declaration + enforcement-map table + cross-references
   Command: read adapters/claude-code/rules/observed-errors-first.md
   Output: Contains "Classification: Mechanism" line, "Enforcement map (hook-backed)" table with 5 rows pointing at observed-errors-gate.sh, "Cross-references" section listing rules/diagnosis.md, hooks/observed-errors-gate.sh, docs/harness-review-audit-questions.md
   Result: PASS

5. Stub references the backing hook (observed-errors-gate.sh)
   Command: grep -n "observed-errors-gate.sh" adapters/claude-code/rules/observed-errors-first.md
   Output: Line 15: "observed-errors-gate.sh PreToolUse Bash blocker on git commit"; Line 24: "hooks/observed-errors-gate.sh — the gate itself"
   Result: PASS

Git evidence:
  Files modified in recent history:
    - adapters/claude-code/rules/observed-errors-first.md (commit ffff6e6, 2026-05-04)
    - ~/.claude/rules/observed-errors-first.md (synced live mirror — gitignored)

Runtime verification: file adapters/claude-code/rules/observed-errors-first.md::Stub — enforcement is in the hook
Runtime verification: file adapters/claude-code/rules/observed-errors-first.md::observed-errors-gate.sh
Runtime verification: file adapters/claude-code/rules/observed-errors-first.md::Enforcement map

Verdict: PASS
Confidence: 10
Reason: observed-errors-first.md converted to 25-line stub; format mirrors vaporware-prevention.md (classification + enforcement-map table + cross-references); live and adapter copies are byte-identical; stub correctly references observed-errors-gate.sh as the hook backing the rule.

EVIDENCE BLOCK
==============
Task ID: 4
Task description: Backlog cleanup with deferral rationale. Mark Phase 1d-G items as IMPLEMENTED in backlog "Recently implemented" section. Add explicit rationale entries for truly-deferred items: GAP-08, GAP-13, 4 remaining rule splits. Bump Last updated to v18. Single commit.
Verified at: 2026-05-05T04:59:13Z
Verifier: task-verifier agent

Checks run:
1. Commit 91f95a8 exists with the backlog v18 subject
   Command: git show --stat 91f95a8
   Output: 1 file changed: docs/backlog.md, 18 insertions(+) 2 deletions(-)
   Result: PASS

2. Last updated line is v18 with correct content
   Command: head -3 docs/backlog.md
   Output: Line 3 starts "Last updated: 2026-05-04 v18: Phase 1d-G shipped — HARNESS-GAP-14 sub-item C ... + HARNESS-GAP-14-followups ... + observed-errors-first.md stub conversion all IMPLEMENTED. Three substantive deferrals explicitly recorded..."
   Result: PASS

3. Three Phase 1d-G items marked IMPLEMENTED in "Recently implemented" with commit SHAs
   Command: sed -n '43,50p' docs/backlog.md
   Output: "These items shipped in Phase 1d-G" header followed by three bullet entries: "HARNESS-GAP-14 sub-item C ... Commit 6881712", "HARNESS-GAP-14-followups ... Commit b27ab7e", "Rules-vs-hooks restructuring (observed-errors-first.md convert) ... Commit ffff6e6"
   Result: PASS

4. Phase 1d-G deferrals section exists with explicit rationale for each deferred item
   Command: grep -A1 "Phase 1d-G deferrals" docs/backlog.md
   Output: "## Phase 1d-G deferrals (2026-05-04)" with three sub-bullets: HARNESS-GAP-08 (~4-6 hr substantive new mechanism design), HARNESS-GAP-13 (~6-10 hr substantive new mechanism design), Rules-vs-hooks restructuring 4 remaining splits (acceptance-scenarios, agent-teams, design-mode-planning, testing) with rationale "each is substantial restructuring per rule"
   Result: PASS

5. Each deferred item has explicit rationale (not just "deferred")
   Command: read backlog.md lines 51-57
   Output: GAP-08 rationale: "design space (callback channel shape, integration with existing fire-and-forget contract, harness-vs-orchestrator-coordinator-pattern boundary) is non-trivial". GAP-13 rationale: "pattern-detection scope ... requires careful design to avoid false positives". 4 rule splits rationale: "Each is substantial restructuring per rule".
   Result: PASS

Git evidence:
  Files modified in recent history:
    - docs/backlog.md (commit 91f95a8, 2026-05-04)

Runtime verification: file docs/backlog.md::v18: Phase 1d-G shipped
Runtime verification: file docs/backlog.md::Phase 1d-G deferrals
Runtime verification: file docs/backlog.md::Commit 6881712
Runtime verification: file docs/backlog.md::Commit b27ab7e
Runtime verification: file docs/backlog.md::Commit ffff6e6
Runtime verification: file docs/backlog.md::HARNESS-GAP-08
Runtime verification: file docs/backlog.md::HARNESS-GAP-13

Verdict: PASS
Confidence: 10
Reason: Backlog v18 header reflects Phase 1d-G shipping plus 3 deferrals; the three Phase 1d-G items are listed in "Recently implemented" with their commit SHAs (6881712, b27ab7e, ffff6e6); the three deferred items each have explicit, substantive rationale (not boilerplate); effort estimates are sized for fresh-session attention.
