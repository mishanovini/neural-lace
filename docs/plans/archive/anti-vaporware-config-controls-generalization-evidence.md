# Evidence Log — Anti-vaporware config-control policy — the inverse shape (HARNESS-GAP-57)

## Task 1 — Build scripts/config-control-producer-scan.sh + allowlist + fixtures + doctrine/FM-038/manifest/INDEX/backlog

EVIDENCE BLOCK
==============
Task ID: 1
Description: Build `scripts/config-control-producer-scan.sh`: a standing, self-testing, bash-3.2-compatible scan over `hooks/`+`scripts/` that classifies every consumed `NL_*`-prefixed lever PRODUCED / MARKED / ALLOWLISTED / FLAGGED; build the allowlist file; build fixtures; generalize doctrine, FM-038, the manifest.json entry, and doctrine/INDEX.md; file the docs/backlog.md HARNESS-GAP-57 row.
Verified at: 2026-07-30T06:03:14Z
Verifier: task-verifier agent

Oracle: specified — the plan's Prove-it-works block (7/7 self-test PASS under both interpreters, mutation transcript RED->GREEN, manifest-check GREEN) plus derived-differential: the live mutation of config/config-control-allowlist.txt as the discriminating oracle proving the live-repo scenario reads real repo state, not fixtures.

Comprehension-gate: not applicable (rung < 2) — plan header declares rung: 1

Operator invariants: none registered (exit 3)

Checks run:
1. Self-test under /bin/bash 3.2.57
   Command: /bin/bash adapters/claude-code/scripts/config-control-producer-scan.sh --self-test
   Output: 7 scenario lines (produced, marked, flagged, allowlisted, golden-post-fix-shape, golden-pre-fix-shape, live-repo) all PASS; "all self-tests passed"; exit 0
   Result: PASS
2. Self-test under /opt/homebrew/bin/bash 5.3.15
   Command: /opt/homebrew/bin/bash adapters/claude-code/scripts/config-control-producer-scan.sh --self-test
   Output: identical 7/7 PASS; exit 0
   Result: PASS
3. Mutation transcript (reproduced by verifier, not trusted from commit message)
   Command: backup allowlist -> sed -i '' '/^NL_CHECKOUT_OVERRIDE/d' adapters/claude-code/config/config-control-allowlist.txt -> re-run --self-test under /bin/bash
   Output: live-repo scenario reported "exit=1" with "FLAGGED     NL_CHECKOUT_OVERRIDE" in captured output; suite ended "self-test failures detected"; exit 1. Restore from backup -> /bin/bash exit 0 "all self-tests passed"; /opt/homebrew/bin/bash exit 0 with 7 PASS lines. diff backup vs restored: identical; git diff a40da18 -- <allowlist>: clean; git status --porcelain: clean.
   Result: PASS (the check genuinely discriminates on real repo state; byte-exact restoration confirmed)
4. manifest-check
   Command: bash adapters/claude-code/scripts/manifest-check.sh
   Output: [manifest-check] GREEN — 146 entries, 120 hooks covered, 0 warn; exit 0 (exactly the plan's expected string)
   Result: PASS
5. Allowlist content
   Command: grep -cE "^NL_[A-Z_]+ " adapters/claude-code/config/config-control-allowlist.txt
   Output: 7 entries (NL_CHECKOUT_OVERRIDE, NL_CROSS_REPO_TOUCH_OK, NL_EXCLUSIONS_VERIFY_TIMEOUT, NL_ISSUES_BACKLOG_PATH, NL_ISSUE_CLI_OVERRIDE, NL_SELFTEST_EXCLUSIONS_FILE, NL_SPAWN_PROCESS_COUNT_OVERRIDE), each with read-site citation + justification
   Result: PASS
6. Fixture tree
   Output: adapters/claude-code/tests/config-control-producer-scan/ contains produced/, marked/, flagged/, golden-nl-protected-orchestrator-pre-fix/, golden-nl-protected-orchestrator-post-fix/ (each fixture.sh) + empty-allowlist.txt + covering-allowlist.txt — exactly the plan's Wire-checks inventory
   Result: PASS
7. Doctrine deltas
   Output: vaporware-prevention.md = 2914 bytes (under 3000B cap, matches claim), "Its inverse (non-UI config levers)" clause at line 11; vaporware-prevention-full.md "## The inverse shape: a consumed lever with no producer (HARNESS-GAP-57)" at line 34, names both artifact paths (lines 59, 70, 119-120)
   Result: PASS
8. FM-038 bullet
   Command: grep -n "Generalization — the inverse shape" docs/failure-modes.md
   Output: line 374, inside the FM-038 section (heading at line 366)
   Result: PASS
9. manifest.json entry
   Output: "config-control-producer-scan" entry present with added_after "2026-07", golden_scenario, fp_expectation, retirement_condition, honesty_rationale, honest_status all substantively populated (ADR 059 D4); blocking:false honestly matches actual wiring (manual/CI-invocable, not hooked)
   Result: PASS
10. INDEX.md regeneration
    Command: grep -n "config-control-producer-scan" adapters/claude-code/doctrine/INDEX.md
    Output: line 25 row present with matching id + honest_status text
    Result: PASS
11. Backlog row
    Command: grep -n "HARNESS-GAP-57" docs/backlog.md
    Output: line 26 — filed, disposition COMPLETED 2026-07-29, references docs/plans/anti-vaporware-config-controls-generalization.md
    Result: PASS
12. Script executability + git evidence
    Output: -rwxr-xr-x on config-control-producer-scan.sh; all 10 claimed files A/M in commit a40da18 (branch build/anti-vaporware-config-controls)
    Result: PASS

Runtime verification: test adapters/claude-code/scripts/config-control-producer-scan.sh::--self-test
Runtime verification: file adapters/claude-code/config/config-control-allowlist.txt::NL_CHECKOUT_OVERRIDE
Runtime verification: file adapters/claude-code/doctrine/vaporware-prevention-full.md::The inverse shape
Runtime verification: file docs/failure-modes.md::Generalization — the inverse shape
Runtime verification: file docs/backlog.md::HARNESS-GAP-57
Runtime verification: test adapters/claude-code/scripts/manifest-check.sh::GREEN
Runtime verification: functionality-verifier config-control-producer-scan::SKIP (rationale: no agent-dispatch capability in this verifier environment; the user-shaped exercise for this harness-internal class — maintainer invoking --self-test under both interpreters plus the live allowlist-mutation RED->GREEN transcript — was executed directly by task-verifier and cited in Checks 1-4 above, per constitution §4's maintainer-is-the-user carve-out)

Runtime verification (before): /bin/bash adapters/claude-code/scripts/config-control-producer-scan.sh --self-test
  Commit: a40da18 with adapters/claude-code/config/config-control-allowlist.txt mutated (NL_CHECKOUT_OVERRIDE line deleted)
  Expected: FAIL — live-repo scenario must flag the now-unallowlisted lever
  Observed: live-repo scenario exit=1, output contains "FLAGGED     NL_CHECKOUT_OVERRIDE", suite ends "self-test failures detected", overall exit 1

Runtime verification (after): /bin/bash adapters/claude-code/scripts/config-control-producer-scan.sh --self-test
  Commit: a40da18 with allowlist restored byte-exact (diff vs backup clean; git diff a40da18 clean)
  Expected: PASS — suite returns to green
  Observed: "all self-tests passed", exit 0 under /bin/bash 3.2.57 AND /opt/homebrew/bin/bash 5.3.15 (7/7 PASS both)

DEPENDENCY TRACE
================
Step 1: maintainer invokes the scan's --self-test (the user action for harness-internal work)
  ↓ Verified at: Checks 1-2 (both interpreters, 7/7 PASS, exit 0)
Step 2: script reads config/config-control-allowlist.txt (ALLOWLIST_FILE default path)
  ↓ Verified at: Check 3 — mutating that exact file flipped ONLY the live-repo scenario to FLAGGED/exit 1 while fixture scenarios stayed PASS (proves the wire is live, not decorative)
Step 3: script reads fixtures under tests/config-control-producer-scan/ (FIXTURE_ROOT)
  ↓ Verified at: Check 6 + scenarios 1-6 exercising produced/marked/flagged/allowlisted/golden-pre/golden-post, with the golden pair differing only in the marker comment and producing opposite verdicts
Step 4: manifest.json entry -> INDEX.md regenerated row
  ↓ Verified at: Checks 4, 9, 10 (manifest-check GREEN 146 entries; INDEX.md:25 same id)
Step 5: doctrine + FM-038 + backlog doc deltas (the task's Docs-impact obligation)
  ↓ Verified at: Checks 7, 8, 11 — all present in commit a40da18's diff

Git evidence:
  Files modified in recent history (all in commit a40da18, 2026-07-29):
    - adapters/claude-code/scripts/config-control-producer-scan.sh (A, executable)
    - adapters/claude-code/config/config-control-allowlist.txt (A)
    - adapters/claude-code/tests/config-control-producer-scan/ (A, 7 files)
    - adapters/claude-code/doctrine/vaporware-prevention.md (M)
    - adapters/claude-code/doctrine/vaporware-prevention-full.md (M)
    - adapters/claude-code/manifest.json (M)
    - adapters/claude-code/doctrine/INDEX.md (M)
    - docs/failure-modes.md (M)
    - docs/backlog.md (M)
    - docs/plans/anti-vaporware-config-controls-generalization.md (A)

Verdict: PASS
Confidence: 9
Reason: PROVEN: falsification attempted and failed — the mutation transcript was reproduced by the verifier (delete NL_CHECKOUT_OVERRIDE allowlist line -> suite RED with the exact predicted FLAGGED output and exit 1; byte-exact restore -> suite GREEN under both /bin/bash 3.2.57 and /opt/homebrew/bin/bash 5.3.15), all four Closure Contract commands were re-run live with outputs exactly matching the plan's expected strings, and every doc/manifest/backlog claim was grep-confirmed at cited line numbers against commit a40da18.
