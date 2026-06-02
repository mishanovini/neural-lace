# Evidence Log — Auto-install harness changes on SessionStart

EVIDENCE BLOCK
==============
Task ID: 1
Task description: Build session-start-auto-install.sh with NL-checkout discovery, ref-sourced file sync, surgical settings.json additive-merge, logging, idempotency, and --self-test (10+ scenarios).
Verified at: 2026-06-02
Verifier: task-verifier agent

Comprehension-gate: not applicable (rung < 2)

Checks run:
1. Hook file exists and is committed (git log: 2c265c0, 8fa7957) - PASS
2. Self-test suite: bash adapters/claude-code/hooks/session-start-auto-install.sh --self-test -> 13 passed, 0 failed (exceeds 10-scenario target) - PASS
3. Mechanism correspondence: canonical reads via git -C nl show ref:path at line 190 (origin/master ref NOT working tree); validate-before-swap; master-wins-with-backup; logging; self-wire at line 252 - PASS

Git evidence: adapters/claude-code/hooks/session-start-auto-install.sh (last commit 2c265c0)

Runtime verification: test adapters/claude-code/hooks/session-start-auto-install.sh::--self-test
Runtime verification: file adapters/claude-code/hooks/session-start-auto-install.sh::git -C

Verdict: PASS
Confidence: 9
Reason: Self-test 13/13 green. Claimed mechanisms all correspond to actual code. Harness-internal; --self-test is the maintainer-facing acceptance artifact per the plan acceptance-exempt rationale.

EVIDENCE BLOCK
==============
Task ID: 2
Task description: Wire the hook into settings.json.template SessionStart matcher, ordered FIRST in the block; sync the live ~/.claude/settings.json wiring (preserve live drift).
Verified at: 2026-06-02
Verifier: task-verifier agent

Comprehension-gate: not applicable (rung < 2)

Checks run:
1. settings.json.template valid JSON and committed (1fb3bb2; jq empty OK) - PASS
2. Auto-install command is the FIRST command of a SessionStart empty-matcher block; contains-any check returns true - PASS
3. Live settings.json wiring synced: jq first SessionStart command = bash ~/.claude/hooks/session-start-auto-install.sh - PASS

Git evidence: adapters/claude-code/settings.json.template (last commit 1fb3bb2)

Runtime verification: file adapters/claude-code/settings.json.template::session-start-auto-install.sh

Verdict: PASS
Confidence: 9
Reason: Verification mechanical. Template valid JSON; auto-install is the first command of a SessionStart empty-matcher block. Live settings wiring also synced (first SessionStart command live).

EVIDENCE BLOCK
==============
Task ID: 3
Task description: Author ADR docs/decisions/NNN-auto-install-on-session-start.md + index row in docs/DECISIONS.md.
Verified at: 2026-06-02
Verifier: task-verifier agent

Comprehension-gate: not applicable (rung < 2)

Checks run:
1. ADR file exists and committed (f6ccd11; 6996 bytes) - PASS
2. Structure: Context/Decision/Consequences/Refutation criterion present; Sub-decisions A/B/C/D (exactly 4) - PASS
3. DECISIONS.md index row: grep -c 048 row = 1 - PASS

Git evidence: docs/decisions/048-auto-install-on-session-start.md, docs/DECISIONS.md (last commit f6ccd11)

Runtime verification: file docs/decisions/048-auto-install-on-session-start.md::Refutation criterion

Verdict: PASS
Confidence: 9
Reason: Verification mechanical. ADR 048 has all required sections + exactly 4 sub-decisions matching the plan Decisions Log. Exactly one DECISIONS.md index row.

EVIDENCE BLOCK
==============
Task ID: 4
Task description: Re-sync this machine: run the hook live against current ~/.claude/ state; confirm it installs missing master-canonical hooks/scripts (e.g. session-start-git-freshness.sh), preserves drift, and produces the log + summary.
Verified at: 2026-06-02
Verifier: task-verifier agent

Comprehension-gate: not applicable (rung < 2)

Checks run:
1. Live idempotency run (Prove-it-works step 2): bash ~/.claude/hooks/session-start-auto-install.sh -> 0 installed, 0 updated, 111 unchanged, 1 preserved-as-drift (NL ref origin/master). No-op against real machine state - PASS
2. Previously-missing canonical hook now live and byte-identical (step 1): diff -q ~/.claude/hooks/session-start-git-freshness.sh vs git show origin/master:... -> exit 0 byte-identical; live file 11630 bytes - PASS
3. Log artifact produced: ~/.claude/state/auto-install-log-20260602-135747.txt - PASS

Git evidence: live machine state exercised; hook script committed at 2c265c0.

Runtime verification: file ~/.claude/hooks/session-start-git-freshness.sh::session-start-git-freshness

Verdict: PASS
Confidence: 9
Reason: Verification full. Hook ran live against real ~/.claude/. A previously-missing canonical hook is now present and byte-identical to origin/master. Second live run is a clean no-op (0 installed, 0 updated), proving idempotency. Log artifact exists. User-observable outcome (maintainer live ~/.claude/ stays current automatically) demonstrated end-to-end.

EVIDENCE BLOCK
==============
Task ID: 5
Task description: Update docs/backlog.md (note install-footgun gap addressed; file v2 residual). Update docs/harness-architecture.md with the new hook.
Verified at: 2026-06-02
Verifier: task-verifier agent

Comprehension-gate: not applicable (rung < 2)

Checks run:
1. Backlog updated: Last updated 2026-06-02 v48 line documents the shipped hook; AUTO-INSTALL-V2 residual count = 2 - PASS
2. harness-architecture.md row: grep -c session-start-auto-install.sh >= 1 - PASS

Git evidence: docs/backlog.md, docs/harness-architecture.md (last commit f6ccd11)

Runtime verification: file docs/backlog.md::AUTO-INSTALL-V2

Verdict: PASS
Confidence: 9
Reason: Verification mechanical. Backlog has the v48 Last-updated line documenting the shipped hook and the AUTO-INSTALL-V2 residual (2 occurrences). harness-architecture.md has the new inventory row.

