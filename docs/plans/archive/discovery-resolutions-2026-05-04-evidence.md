# Evidence Log — Discovery Resolutions 2026-05-04 Session

EVIDENCE BLOCK
==============
Task ID: 1
Task description: Resolve Discovery #1 (sed-status-flip → option D). Implement plan-status-archival-sweep.sh SessionStart hook with 5-scenario --self-test (including a scenario that asserts git diff --cached --name-status reports R<num> so the rename-tracking path can't regress silently). Wire into live ~/.claude/settings.json AND adapters/claude-code/settings.json.template. Add Stage 3.5 to rules/planning.md Plan File Lifecycle section. Live-fire against the 3 stranded plans (document-freshness-system, harness-quick-wins-2026-04-22, public-release-hardening) and verify proper archival + git mv rename for the tracked plan. Mark the discovery file Status: decided with substantive Decision + Implementation log.
Verified at: 2026-05-04T00:00:00Z
Verifier: task-verifier agent

Checks run:
1. Hook file exists at expected path
   Command: ls -la adapters/claude-code/hooks/plan-status-archival-sweep.sh
   Output: -rwxr-xr-x 1 misha 197609 10661 May  4 13:31 (10661 bytes)
   Result: PASS

2. All 5 self-test scenarios pass
   Command: bash adapters/claude-code/hooks/plan-status-archival-sweep.sh --self-test
   Output: PASS: [no-directory] silent as expected | PASS: [active-stays] active plan untouched | PASS: [completed-archives] plan moved to archive AND git tracks rename | PASS: [with-evidence] plan and evidence both archived | PASS: [untracked-completed] untracked plan archived via plain mv | All 5 self-test scenarios PASSED
   Result: PASS

3. Hook wired in live settings.json
   Command: grep -c "plan-status-archival-sweep" ~/.claude/settings.json
   Output: 1
   Result: PASS

4. Hook wired in committed template
   Command: grep -c "plan-status-archival-sweep" adapters/claude-code/settings.json.template
   Output: 1
   Result: PASS

5. Stage 3.5 added to planning.md
   Command: grep -n "Stage 3.5" adapters/claude-code/rules/planning.md
   Output: 302:**Bash sed-based Status flips do NOT trigger this hook**... | 304:### Stage 3.5: Session-start safety-net sweep
   Result: PASS

6. Stranded plans archived (all 3 + evidence siblings)
   Command: ls docs/plans/archive/ | grep -E "document-freshness|harness-quick-wins|public-release"
   Output: document-freshness-system-evidence.md, document-freshness-system.md, harness-quick-wins-2026-04-22.md, public-release-hardening-evidence.md, public-release-hardening.md
   Result: PASS

7. Stranded plans no longer in top-level docs/plans/
   Command: ls docs/plans/ | grep -E "document-freshness|harness-quick-wins|public-release"
   Output: (empty)
   Result: PASS

8. Git tracks rename (R100) for the one tracked plan
   Command: git diff 2a49b11~1 2a49b11 --name-status -- docs/plans/
   Output: R100	docs/plans/harness-quick-wins-2026-04-22.md	docs/plans/archive/harness-quick-wins-2026-04-22.md | A	docs/plans/discovery-resolutions-2026-05-04.md
   Result: PASS — rename detected at 100% similarity (no content drift)

9. Discovery file marked decided + auto_applied
   Command: head -10 docs/discoveries/2026-05-04-sed-status-flip-bypasses-plan-lifecycle.md
   Output: status: decided, auto_applied: true (frontmatter lines 5-6); Decision section + Implementation log populated substantively (lines 36-50+)
   Result: PASS

Git evidence:
  Files modified in commit 2a49b11 (build-doctrine-integration):
    - adapters/claude-code/hooks/plan-status-archival-sweep.sh (NEW, 10661 bytes)
    - adapters/claude-code/rules/planning.md (Stage 3.5 added at line 304)
    - adapters/claude-code/settings.json.template (sweep wired in SessionStart matcher)
    - docs/plans/harness-quick-wins-2026-04-22.md → docs/plans/archive/... (R100 rename)
    - docs/discoveries/2026-05-04-sed-status-flip-bypasses-plan-lifecycle.md (status: decided)

Runtime verification: file adapters/claude-code/hooks/plan-status-archival-sweep.sh::--self-test
Runtime verification: file ~/.claude/settings.json::plan-status-archival-sweep
Runtime verification: file adapters/claude-code/settings.json.template::plan-status-archival-sweep
Runtime verification: file adapters/claude-code/rules/planning.md::Stage 3.5: Session-start safety-net sweep
Runtime verification: file docs/plans/archive/harness-quick-wins-2026-04-22.md::Status:
Runtime verification: file docs/discoveries/2026-05-04-sed-status-flip-bypasses-plan-lifecycle.md::status: decided

Verdict: PASS
Confidence: 9
Reason: All 7 acceptance criteria verified empirically: hook file exists with --self-test exercising 5 scenarios all PASS (including R-rename assertion), wired in both live + committed settings.json, Stage 3.5 added to planning.md with substantive content, all 3 stranded plans archived (with the one tracked plan landing as a proper R100 rename per git diff --name-status), discovery file frontmatter at status: decided + auto_applied: true with populated Decision + Implementation log sections.

EVIDENCE BLOCK
==============
Task ID: 2
Task description: Resolve Discovery #2 partial (template-vs-live divergence → option B now, A deferred). Implement settings-divergence-detector.sh SessionStart hook with 4-scenario --self-test. Wire into both live + template settings.json. Confirm via live-fire that the detector surfaces real divergence in production state. Add HARNESS-GAP-14 to docs/backlog.md with orchestrator-driven research methodology spelled out for the deferred reconciliation pass (per-hook git blame, commit log archaeology, author-intent recovery, canonical-side proposal for user review). Mark the discovery file Status: decided with split-decision rationale.
Verified at: 2026-05-04T00:00:00Z
Verifier: task-verifier agent

Checks run:
1. Hook file exists at expected path with --self-test flag
   Command: ls -la adapters/claude-code/hooks/settings-divergence-detector.sh
   Output: file present (193 lines, ~5.5KB); --self-test branch present at line 183
   Result: PASS

2. All 4 self-test scenarios pass
   Command: bash adapters/claude-code/hooks/settings-divergence-detector.sh --self-test
   Output: PASS: [template-missing] silent as expected | PASS: [live-missing] silent as expected | PASS: [byte-identical] silent as expected | PASS: [divergent] warning emitted naming Stop | All 4 self-test scenarios PASSED
   Result: PASS

3. Hook wired in live settings.json
   Command: grep -n "settings-divergence-detector" ~/.claude/settings.json
   Output: 414:            "command": "bash ~/.claude/hooks/settings-divergence-detector.sh",
   Result: PASS

4. Hook wired in committed template
   Command: grep -n "settings-divergence-detector" adapters/claude-code/settings.json.template
   Output: 337:            "command": "bash ~/.claude/hooks/settings-divergence-detector.sh",
   Result: PASS

5. Live-fire surfaces real divergence in production state
   Command: bash ~/.claude/hooks/settings-divergence-detector.sh < /dev/null
   Output: [settings-divergence] template and live ~/.claude/settings.json differ — at least one hook is wired in only one of the two files. | Hook entry-count differs for these events: PreToolUse: template=18, live=21 | SessionStart: template=3, live=2 | UserPromptSubmit: template=1, live=2
   Result: PASS — non-empty stdout naming three divergent event types proves detector observes real divergence; output matches the divergence values claimed in the plan's Testing Strategy section

6. HARNESS-GAP-14 entry exists in docs/backlog.md with orchestrator-driven research methodology
   Command: grep -n "HARNESS-GAP-14" docs/backlog.md
   Output: line 167 — "## HARNESS-GAP-14 — Template-vs-live settings.json reconciliation pass (added 2026-05-04; deferred from discovery 2026-05-04-template-vs-live-divergence-across-other-hooks)"
   Body content (lines 167-191): Source citation + The gap (5 named hooks) + 7-step orchestrator-driven Methodology (git log --all --follow, git blame on template lines, divergence shape analysis, commit-message + plan + decision record archaeology, harness-architecture.md cross-ref, per-hook proposal output, user-reviews-en-masse final step) + Companion mechanism note + Effort estimate (M, ~2-4h) + Why P2 + Originating context
   Result: PASS — entry is substantive (~25 lines), spells out per-hook git blame, commit log archaeology, author-intent recovery, and canonical-side-proposal-for-user-review as explicit numbered steps

7. Backlog version line updated to v9 referencing HARNESS-GAP-14
   Command: head -3 docs/backlog.md
   Output: "Last updated: 2026-05-04 v9: HARNESS-GAP-14 added — template-vs-live settings.json reconciliation pass deferred from discovery..."
   Result: PASS

8. Discovery file frontmatter shows status: decided + auto_applied: true
   Command: grep -n "^status:\|^auto_applied:\|^title:" docs/discoveries/2026-05-04-template-vs-live-divergence-across-other-hooks.md
   Output: 2:title: Pre-existing template-vs-live divergence across hooks not in Phase 1d-C-2 scope | 5:status: decided | 6:auto_applied: true
   Result: PASS

Git evidence:
  Files modified in commit 2a49b11 (build-doctrine-integration):
    - adapters/claude-code/hooks/settings-divergence-detector.sh (NEW)
    - adapters/claude-code/settings.json.template (detector wired in SessionStart matcher at line 337)
    - docs/backlog.md (HARNESS-GAP-14 added at line 167; version line updated to v9)
    - docs/discoveries/2026-05-04-template-vs-live-divergence-across-other-hooks.md (status: decided + auto_applied: true; split-decision rationale captured)
  Live (gitignored) edits:
    - ~/.claude/settings.json (detector wired at line 414)

Runtime verification: file adapters/claude-code/hooks/settings-divergence-detector.sh::--self-test
Runtime verification: file adapters/claude-code/settings.json.template::settings-divergence-detector
Runtime verification: file ~/.claude/settings.json::settings-divergence-detector
Runtime verification: file docs/backlog.md::HARNESS-GAP-14
Runtime verification: file docs/discoveries/2026-05-04-template-vs-live-divergence-across-other-hooks.md::status: decided

Verdict: PASS
Confidence: 9
Reason: All 6 acceptance criteria verified empirically: hook file exists at adapters/claude-code/hooks/settings-divergence-detector.sh with --self-test flag exercising 4 scenarios all PASS (template-missing silent, live-missing silent, byte-identical silent, divergent warning naming Stop); both live and committed-template settings.json reference the new hook in their SessionStart sections; live-fire emitted non-empty stdout naming three divergent event types (PreToolUse, SessionStart, UserPromptSubmit) which exactly matches the values claimed in the plan's Testing Strategy section, proving the detector is correctly observing real production-state divergence; HARNESS-GAP-14 entry in docs/backlog.md is substantive and includes the per-hook research methodology with explicit numbered steps for git log archaeology, git blame on template lines, commit-message + plan + decision-record author-intent recovery, and per-hook canonical-side proposal for user en-masse review (matching the user's directive that this be orchestrator-driven research, not user-judgment-cold); discovery file frontmatter shows status: decided + auto_applied: true with split-decision rationale.

EVIDENCE BLOCK
==============
Task ID: 3
Task description: Resolve Discovery #3 (worktree-base → option Q empirical). Empirically test option Q via read-only Agent dispatch with `isolation: "worktree"` to confirm the feature branch ref is visible inside worktrees rooted at master. Update `rules/orchestrator-pattern.md` dispatch-prompt template with the mandatory first-action step (`git checkout -b worker-<id> <feature-branch>`). Mark the discovery file `Status: decided` with empirical-test result + Implementation log.
Verified at: 2026-05-04T00:00:00Z
Verifier: task-verifier agent

Checks run:
1. New section heading present in repo orchestrator-pattern.md
   Command: grep -n "Worktree base is master HEAD" adapters/claude-code/rules/orchestrator-pattern.md
   Output: 57:### Worktree base is master HEAD — builders MUST switch to feature branch first
   Result: PASS

2. Mandatory first-action command template present in repo file
   Command: grep -n "git checkout -b worker" adapters/claude-code/rules/orchestrator-pattern.md
   Output: 69:    git checkout -b worker-<task-id> <feature-branch-name>
   Result: PASS — literal command template embedded in dispatch-prompt section

3. Same heading present in live ~/.claude/rules/orchestrator-pattern.md
   Command: grep -n "Worktree base is master HEAD" ~/.claude/rules/orchestrator-pattern.md
   Output: 57:### Worktree base is master HEAD — builders MUST switch to feature branch first
   Result: PASS

4. Same command template present in live ~/.claude/rules/orchestrator-pattern.md
   Command: grep -n "git checkout -b worker" ~/.claude/rules/orchestrator-pattern.md
   Output: 69:    git checkout -b worker-<task-id> <feature-branch-name>
   Result: PASS

5. Live and repo orchestrator-pattern.md are byte-identical
   Command: diff ~/.claude/rules/orchestrator-pattern.md adapters/claude-code/rules/orchestrator-pattern.md
   Output: (empty — files match)
   Result: PASS — confirms harness-maintenance sync is complete

6. Discovery file frontmatter shows status: decided + auto_applied: true
   Command: head -10 docs/discoveries/2026-05-04-worktree-base-points-at-master-not-branch-head.md
   Output: status: decided (line 5), auto_applied: true (line 6), originating_context populated, decision_needed annotated as resolved
   Result: PASS

7. Discovery file Decision section is substantive and references empirical test
   Command: sed -n '52,75p' docs/discoveries/2026-05-04-worktree-base-points-at-master-not-branch-head.md
   Output: Decision section is ~24 lines, names option Q, cites empirical findings (worktree at master HEAD 10adac2, feature ref visible in .git/refs, git checkout -b succeeded landing HEAD at 866a8d6, plan files visible), enumerates rejected options (A/D/B/C/M/N) with rationale, marks auto_applied yes with reversibility note
   Result: PASS — substantively > 20 chars, clearly references the empirical test

8. Implementation log section present and cites empirical test agentId
   Command: sed -n '76,81p' docs/discoveries/2026-05-04-worktree-base-points-at-master-not-branch-head.md
   Output: 78:- 2026-05-04 — Empirical test confirmed Q works (`agentId: af323f2b20494375a`). Worktree rooted at `10adac2`, feature ref visible, `git checkout -b worker-N build-doctrine-integration` succeeded, HEAD landed at `866a8d6`. | 79:- 2026-05-04 — Updating `rules/orchestrator-pattern.md` to add Q as the first action in the parallel-mode dispatch-prompt template (this session).
   Result: PASS — Implementation log populated with empirical agentId citation

9. New section content correspondence — what the new section says matches the option Q semantics in the discovery file
   Command: sed -n '57,90p' adapters/claude-code/rules/orchestrator-pattern.md
   Output: Section explains worktree IS at master HEAD (not feature branch HEAD); explains feature ref IS visible inside worktree; provides mandatory first-action command (git checkout -b worker-<task-id> <feature-branch-name>); explains why it works (worktrees share .git/refs); names what it does NOT solve (uncommitted orchestrator state); notes auto-cleanup interaction
   Result: PASS — correspondence confirmed: section content faithfully encodes the option Q decision from the discovery file

Git evidence:
  Files modified in commit 2a49b11 (build-doctrine-integration):
    - adapters/claude-code/rules/orchestrator-pattern.md (+32 lines, new section between "Why worktrees" and "Build-in-parallel, verify-sequentially")
    - docs/discoveries/2026-05-04-worktree-base-points-at-master-not-branch-head.md (status flipped to decided + auto_applied: true; Decision + Implementation log populated)
  Live (gitignored) edits synced from repo:
    - ~/.claude/rules/orchestrator-pattern.md (byte-identical to repo file)

Runtime verification: file adapters/claude-code/rules/orchestrator-pattern.md::Worktree base is master HEAD
Runtime verification: file adapters/claude-code/rules/orchestrator-pattern.md::git checkout -b worker
Runtime verification: file ~/.claude/rules/orchestrator-pattern.md::Worktree base is master HEAD
Runtime verification: file ~/.claude/rules/orchestrator-pattern.md::git checkout -b worker
Runtime verification: file docs/discoveries/2026-05-04-worktree-base-points-at-master-not-branch-head.md::status: decided
Runtime verification: file docs/discoveries/2026-05-04-worktree-base-points-at-master-not-branch-head.md::auto_applied: true
Runtime verification: file docs/discoveries/2026-05-04-worktree-base-points-at-master-not-branch-head.md::agentId: af323f2b20494375a

Verdict: PASS
Confidence: 9
Reason: All 5 acceptance criteria verified empirically against the working tree at HEAD 2a49b11. The new section heading "Worktree base is master HEAD — builders MUST switch to feature branch first" is present in adapters/claude-code/rules/orchestrator-pattern.md at line 57. The mandatory builder first-action command template (`git checkout -b worker-<task-id> <feature-branch-name>`) appears verbatim at line 69 inside a fenced dispatch-prompt code block, embedded in a substantive ~32-line section explaining the empirical confirmation, the why-it-works mechanism (worktrees share .git/refs with parent repo), what the workaround does NOT solve (uncommitted orchestrator state, requiring commit-before-dispatch discipline), and the auto-cleanup interaction with the cherry-pick protocol. The same content is byte-identical in ~/.claude/rules/orchestrator-pattern.md (confirmed via `diff` returning empty). The discovery file `2026-05-04-worktree-base-points-at-master-not-branch-head.md` shows `status: decided` and `auto_applied: true` in frontmatter (lines 5-6); its Decision section is substantive (~24 lines, well over the 20-char threshold) and cites the empirical test result with concrete commit SHAs (worktree at 10adac2, feature ref visible in .git/refs, post-checkout HEAD at 866a8d6) and explicitly enumerates rejected options A/B/C/D/M/N with rationale; its Implementation log section cites the empirical test's agentId (`af323f2b20494375a`) at line 78.
Caveat / catalog cross-check: the user is correct that this resolution updates a documentation rule, not a hook-enforced gate. The class-of-failure here is "parallel-mode dispatch silently broken on feature branches with commits ahead of master" — that class is closed via Pattern (builder dispatch-prompt template) rather than Mechanism (no hook detects "builder forgot to checkout feature branch"). This is consistent with the orchestrator-pattern.md rule's existing classification as Pattern-not-Mechanism. No FM-NNN catalog entry is created because the failure class is now documented as a known-and-mitigated workaround within the rule itself rather than an open failure mode.

EVIDENCE BLOCK
==============
Task ID: 4
Task description: Companion housekeeping. Update .gitignore (archive paths for pre-sanitization plans, broaden .claude/state/ from acceptance/ only, add .claude/worktrees/). Update docs/harness-architecture.md SessionStart inventory + Hook Scripts table for both new hooks and the previously-unlisted discovery-surfacer.sh.
Verified at: 2026-05-04T22:10:00Z
Verifier: task-verifier agent
Re-verification: YES — this is a re-verification of Task 4 after a regression-fix landed. Prior verification at commit 2a49b11 returned FAIL because that commit inadvertently overwrote 8 rows of pre-existing Phase 1d-C-2/1d-C-3 documentation in docs/harness-architecture.md (root cause: live ~/.claude/docs/harness-architecture.md was missing entries the user's other session had added to the repo file; when this session edited the live file and copied to repo, it overwrote the user's work — confirms the value of shipping settings-divergence-detector.sh). Followup commit 0e2c3a6 (now at HEAD) restored all 8 rows from canonical state at e95313b AND re-applied the Task 4 additions on top.

Checks run:
1. AC1 — .gitignore contains all 4 archive paths for pre-sanitization plans
   Command: grep -n "archive/document-freshness-system\|archive/public-release-hardening" .gitignore
   Output: lines 101-104 show all 4 paths present:
     docs/plans/archive/document-freshness-system.md
     docs/plans/archive/document-freshness-system-evidence.md
     docs/plans/archive/public-release-hardening.md
     docs/plans/archive/public-release-hardening-evidence.md
   Result: PASS

2. AC2 — .gitignore broadened from .claude/state/acceptance/ to .claude/state/
   Command: grep -n "^\.claude/state/" .gitignore
   Output: line 118 shows broadened ".claude/state/" (no /acceptance/ suffix)
   Result: PASS

3. AC3 — .gitignore contains .claude/worktrees/
   Command: grep -n "^\.claude/worktrees/" .gitignore
   Output: line 125 shows ".claude/worktrees/"
   Result: PASS

4. AC4 — SessionStart subsection enumerates 6 default-matcher hooks
   Command: sed -n '75,90p' docs/harness-architecture.md
   Output: line 75 heading "SessionStart (2 matcher entries; multiple hooks per matcher)" — corrected from prior "(2 entries)"; lines 84-89 enumerate all 6 hooks: account switcher (84), pipeline detector (85), effort-policy-warn.sh (86), discovery-surfacer.sh (87), plan-status-archival-sweep.sh (88), settings-divergence-detector.sh (89).
   Result: PASS

5. AC5 — Hook Scripts table contains rows for all 3 new hooks
   Command: grep -n "discovery-surfacer\.sh\|plan-status-archival-sweep\.sh\|settings-divergence-detector\.sh" docs/harness-architecture.md
   Output: line 178 (discovery-surfacer.sh row in Hook Scripts table); lines 179-180 (the other 2 new hooks). Plus the SessionStart subsection enumeration at lines 87-89.
   Result: PASS

6. AC6 — Live ~/.claude/docs/harness-architecture.md byte-identical to repo
   Command: diff "$HOME/.claude/docs/harness-architecture.md" "$(pwd)/docs/harness-architecture.md"
   Output: empty (BYTE-IDENTICAL)
   Result: PASS

7. AC7 — Regression check: 8 previously-overwritten Phase 1d-C-2/1d-C-3 rows restored
   Command: grep -cE "prd-validity-gate|spec-freeze-gate|findings-ledger-schema-gate|prd-validity-reviewer\.md|prd-validity\.md|spec-freeze\.md|findings-ledger\.md|findings-template\.md" docs/harness-architecture.md
   Output: 9 (matches canonical e95313b count of 9 — verified by `git show e95313b:docs/harness-architecture.md | grep -cE ...` returning 9)
   Result: PASS — regression fully restored

8. AC8 — Last-updated banner has 2026-05-04 entry for discovery resolutions, AND the prior chain of "Earlier 2026-05-04 (Scope-enforcement-gate ..." entries preserved (not erased)
   Command: head -2 docs/harness-architecture.md
   Output: Line 2 begins with "Last updated: 2026-05-04 (Discovery resolutions for sed-status-flip bypass + template-vs-live divergence + worktree-base-at-master ..." THEN chains backward through "Earlier 2026-05-04 (Scope-enforcement-gate second-pass redesign ...", "Earlier 2026-05-04 (Scope-enforcement-gate redesign ...", "Earlier 2026-05-03 (Discovery Protocol ...", "Earlier 2026-05-03 (Agent Incentive Map ...", "Earlier 2026-05-03: Phase 1d-C-1 ...", "Earlier 2026-04-28 (Agent Teams integration ...", and back further to 2026-04-26, 2026-04-24 entries.
   Result: PASS — chain preserved end-to-end

Git evidence:
  Files modified at HEAD (0e2c3a6):
    - docs/harness-architecture.md (regression-restored + Task 4 additions reapplied)
    - docs/plans/discovery-resolutions-2026-05-04-evidence.md (Task 1/2/3 evidence staged)
    - docs/plans/discovery-resolutions-2026-05-04.md (in-flight scope updates entries)
  Earlier Task 4 work commit:
    - 2a49b11 — feat(harness): resolve 3 pending discoveries (introduced regression in harness-architecture.md)
  Regression-fix commit:
    - 0e2c3a6 — fix(harness-architecture): restore 8 regressed Phase 1d-C-2/1d-C-3 doc rows + Task 1-3 evidence

Runtime verification: file .gitignore::docs/plans/archive/document-freshness-system.md
Runtime verification: file .gitignore::docs/plans/archive/public-release-hardening.md
Runtime verification: file .gitignore::^\.claude/state/$
Runtime verification: file .gitignore::^\.claude/worktrees/
Runtime verification: file docs/harness-architecture.md::SessionStart \(2 matcher entries; multiple hooks per matcher\)
Runtime verification: file docs/harness-architecture.md::discovery-surfacer\.sh
Runtime verification: file docs/harness-architecture.md::plan-status-archival-sweep\.sh
Runtime verification: file docs/harness-architecture.md::settings-divergence-detector\.sh
Runtime verification: file docs/harness-architecture.md::prd-validity-gate
Runtime verification: file docs/harness-architecture.md::findings-ledger-schema-gate
Runtime verification: file docs/harness-architecture.md::Last updated: 2026-05-04 \(Discovery resolutions

Verdict: PASS
Confidence: 9
Reason: All 8 acceptance criteria verified at HEAD 0e2c3a6. The regression that caused the prior FAIL has been fully resolved: the canonical e95313b count of 9 references for Phase 1d-C-2/1d-C-3 mechanisms is restored byte-identically (`prd-validity-gate`, `spec-freeze-gate`, `findings-ledger-schema-gate`, `prd-validity-reviewer.md`, `prd-validity.md`, `spec-freeze.md`, `findings-ledger.md`, `findings-template.md` — total 9 matches at HEAD vs 9 at e95313b). The Task 4 additions are correctly re-applied on top: the SessionStart heading is rewritten from "(2 entries)" to "(2 matcher entries; multiple hooks per matcher)" and enumerates all 6 default-matcher hooks (account switcher, pipeline detector, effort-policy-warn.sh, discovery-surfacer.sh, plan-status-archival-sweep.sh, settings-divergence-detector.sh) at lines 84-89; the Hook Scripts table contains rows for all 3 new hooks at lines 178-180; the Last-updated banner at line 2 has a fresh 2026-05-04 entry for the discovery resolutions AND preserves the backward chain through prior 2026-05-04 / 2026-05-03 / 2026-04-28 / 2026-04-26 / 2026-04-24 entries (not erased). The `.gitignore` file contains all 4 archive paths (lines 101-104), the broadened `.claude/state/` (line 118), and `.claude/worktrees/` (line 125). Live `~/.claude/docs/harness-architecture.md` is byte-identical to the repo file (`diff` returns empty). All acceptance criteria pass; the regression-fix is verified.
Caveat / lessons-from-the-regression: the root cause of the prior FAIL was the very template-vs-live divergence Discovery #2 surfaced — the live `~/.claude/docs/harness-architecture.md` was missing 8 rows the user's other session had added to the repo file. When this session edited the live file and copied to repo, it overwrote the user's uncommitted work. This confirms the value of shipping `settings-divergence-detector.sh` (Task 2 work): going forward, the next session's SessionStart will surface this class of divergence before any work begins. A natural follow-up would be a similar "doc divergence detector" for `~/.claude/docs/*` files — logged as a candidate HARNESS-GAP in the next session's discovery sweep. No new FM-NNN catalog entry is created because the failure class ("live config / live doc edits overwrite uncommitted user-side changes from the other repo copy") is now structurally surfaced by `settings-divergence-detector.sh` for settings.json; an analogous detector for harness docs would close the doc side of the same class.
