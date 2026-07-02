# Evidence Log — NL Overhaul Program — The Great Consolidation (Phases 0–5)

## Task B.0 — Wave-spec refinement for Wave B

EVIDENCE BLOCK
==============
Task ID: B.0
Task description: Wave-spec refinement for Wave B (exact per-task specs appendix; embed the audit's defect lists verbatim as work items, incl. the red-fixture list for B.1) — Verification: mechanical
Verified at: 2026-07-02T20:05:11Z
Verifier: task-verifier agent (Verification: mechanical)

Oracle: mechanical — deterministic file-existence + section-presence assertions from the plan's Done-when
Verification level: mechanical
Comprehension-gate: not applicable (rung < 2)

Commit: 259c3f1 (plan(nl-overhaul): fold harness-reviewer REFORMULATE findings (12/12) ... add Wave-B spec appendix (B.0)) — creates docs/plans/nl-overhaul-program-2026-07-specs-b.md (+90 lines)

Checks run:
1. specs-b file exists
   Command: test -f docs/plans/nl-overhaul-program-2026-07-specs-b.md
   Result: PASS (file present, 91 lines)
2. Every B-task (B.1–B.11) has a section
   Command: grep -n "^## §B\." docs/plans/nl-overhaul-program-2026-07-specs-b.md
   Output: 11 section headers — §B.1 (L7), §B.2 (L26), §B.3 (L32), §B.4 (L37), §B.5 (L45), §B.6 (L58), §B.7 (L67), §B.8 (L71), §B.9 (L75), §B.10 (L79), §B.11 (L83)
   Result: PASS (11/11 B-tasks covered; each section carries exact file paths + grep/self-test assertions)

Runtime verification: file docs/plans/nl-overhaul-program-2026-07-specs-b.md::## §B.11

Verdict: PASS
Confidence: 9
Reason: PROVEN: specs-b appendix exists at docs/plans/nl-overhaul-program-2026-07-specs-b.md (commit 259c3f1) and contains a §B.<n> section with mechanical assertions for every B-task B.1 through B.11.

## Task B.1 — harness-doctor.sh

EVIDENCE BLOCK
==============
Task ID: B.1
Task description: Build adapters/claude-code/hooks/harness-doctor.sh per ADR 058 D4 (--quick / --full / --self-test; checks: wiring live+template vs manifest-lite checklist, hook existence/executability, lib-dep resolution, legacy-path scan, always-loaded byte budget, template-vs-live diff) — Verification: mechanical
Verified at: 2026-07-02T20:06:30Z
Verifier: task-verifier agent (Verification: mechanical)

Oracle: mechanical — the hook's own sandboxed --self-test suite (specs-b §B.1: one red + one green fixture per check class 1–7)
Verification level: mechanical
Comprehension-gate: not applicable (rung < 2)

Commit: bfb9385 (overhaul(B.1): add adapters/claude-code/hooks/harness-doctor.sh per ADR 058 D4) — new file, 726 lines
Commit: 669c7b4 (overhaul(B-integration): doctor never self-matches its legacy-path pattern — split-literal + printf fixture, self-test 14/14)

Checks run:
1. Doctor self-test suite
   Command: HARNESS_SELFTEST=1 timeout 240 bash adapters/claude-code/hooks/harness-doctor.sh --self-test </dev/null
   Output: 14 scenario PASSes — red+green fixture pairs for all 7 check classes (1-wiring-resolves, 2-lib-deps, 3-legacy-paths, 4-template-live-drift, 5-claim-honesty, 6-byte-budget, 7-selftest-sweep); final line "self-test summary: 14 passed, 0 failed"
   Result: PASS (exit 0)

Runtime verification: file adapters/claude-code/hooks/harness-doctor.sh::--self-test

Verdict: PASS
Confidence: 9
Reason: PROVEN: HARNESS_SELFTEST=1 bash adapters/claude-code/hooks/harness-doctor.sh --self-test exited 0 reporting 14 passed, 0 failed on this branch (commits bfb9385 + 669c7b4), satisfying the specs-b §B.1 red-fixture-per-check-class Done-when.

## Task B.2 — Kill legacy-path family

EVIDENCE BLOCK
==============
Task ID: B.2
Task description: Kill legacy-path family: create hooks/lib/nl-paths.sh resolver (env NL_REPO_ROOT > ~/.claude/local/nl-repo-path > git-derived); replace every claude-projects/neural-lace reference in hooks/scripts/lib — Verification: mechanical
Verified at: 2026-07-02T20:07:30Z
Verifier: task-verifier agent (Verification: mechanical)

Oracle: mechanical — clean-grep assertion over hooks+scripts plus the affected hook's own self-test (specs-b §B.2)
Verification level: mechanical
Comprehension-gate: not applicable (rung < 2)

Commit: 06f933f (overhaul(B.2): kill legacy-path family) — touches check-harness-sync.sh, cross-repo-drift gates, decision-context family, Gen-6 trio (goal-coverage-on-stop, goal-extraction-on-prompt, imperative-evidence-linker), workstreams-task-bridge.js and siblings

Checks run:
1. Legacy-path grep is empty
   Command: grep -rl "claude-projects/neural-lace" adapters/claude-code/hooks adapters/claude-code/scripts
   Output: (no matches; grep exit 1)
   Result: PASS
2. workstreams-task-binding.sh self-test
   Command: timeout 120 bash adapters/claude-code/hooks/workstreams-task-binding.sh --self-test </dev/null
   Output: all scenarios ok; final line "self-test: OK"
   Result: PASS (exit 0)
3. nl-paths.sh resolver exists
   Command: test -f adapters/claude-code/hooks/lib/nl-paths.sh
   Output: file present; defines nl_repo_root (10 occurrences)
   Result: PASS

Runtime verification: file adapters/claude-code/hooks/lib/nl-paths.sh::nl_repo_root

Verdict: PASS
Confidence: 9
Reason: PROVEN: on commit 06f933f (as integrated at e2f9814) the legacy-path grep over adapters/claude-code/hooks + scripts returns zero files, workstreams-task-binding.sh --self-test exits 0, and hooks/lib/nl-paths.sh exists with the nl_repo_root resolver.

## Task B.3 — Install completeness

EVIDENCE BLOCK
==============
Task ID: B.3
Task description: Fix install completeness: install.sh deploys hooks/lib/ fully + tests/ fixtures + patterns/ (hygiene denylist — closes GAP-52) + examples/; add --verify mode running doctor --quick post-install — Verification: mechanical
Verified at: 2026-07-02T20:08:30Z
Verifier: task-verifier agent (Verification: mechanical)

Oracle: mechanical — presence-grep over install.sh copy steps + --verify flag + nl-repo-path write, per the caller-scoped acceptance. Per the plan's Decisions Log ("B.3 accepted with one assertion re-routed to B.6"), the decision-context-gate temp-HOME self-test is EXCLUDED from B.3 acceptance (pre-existing node_modules/zod provisioning gap, PROVEN by the builder via baseline comparison; re-checked at B.6 against the live machine). The other three temp-HOME self-tests were verified by the builder (commit summary evidence).
Verification level: mechanical
Comprehension-gate: not applicable (rung < 2)

Commit: e28c336 (overhaul(B.3): install.sh completeness — hooks/lib, tests, patterns, examples, data + --verify + nl-repo-path) — install.sh +135/-1

Checks run:
1. Copy steps + verify flag + repo-path write present
   Command: grep -c "hooks/lib\|tests/\|patterns/\|examples/\|nl-repo-path\|--verify" adapters/claude-code/install.sh
   Output: 38
   Result: PASS (38 >= 6)
2. --verify flag literal present
   Command: grep -c -- "--verify" adapters/claude-code/install.sh
   Output: 11
   Result: PASS

Runtime verification: file adapters/claude-code/install.sh::--verify

Verdict: PASS
Confidence: 8
Reason: PROVEN: install.sh at commit e28c336 contains the hooks/lib / tests/ / patterns/ / examples/ copy steps, the nl-repo-path write, and the --verify mode (grep count 38 >= 6); the decision-context-gate temp-HOME assertion is re-routed to B.6 per the plan's Decisions Log and is not part of B.3 acceptance.

## Task B.4 — Junk + dead-ref sweep

EVIDENCE BLOCK
==============
Task ID: B.4
Task description: Junk + dead-ref sweep (hook files only): delete the 6 expired conversation-tree-*/conv-tree-* shims and stray hooks/.claude/state/ files; fix the feature-completion-audit.sh dead ref in completion-criteria-gate.sh's header — Verification: mechanical
Verified at: 2026-07-02T20:09:30Z
Verifier: task-verifier agent (Verification: mechanical)

Oracle: mechanical — absence-greps + attic-count assertions from specs-b §B.4
Verification level: mechanical
Comprehension-gate: not applicable (rung < 2)

Commit: 887255b (overhaul(B.4): junk + dead-ref sweep — retire 6 expired conv-tree shims, fix feature-completion-audit + conversation-tree-emit.sh dead refs) — 6 git-mv to attic/ + attic/README.md + completion-criteria-gate.sh + workstreams-emit-reconciler.sh

Checks run:
1. Shim files absent from hooks/
   Command: ls adapters/claude-code/hooks/conversation-tree-*.sh adapters/claude-code/hooks/conv-tree-*.sh 2>/dev/null | wc -l
   Output: 0
   Result: PASS
2. Attic populated
   Command: ls adapters/claude-code/attic/ | wc -l
   Output: 7 (README.md + conv-tree-emit-reconciler.sh + conversation-tree-{emit,extract-pending,read,state-gate,stop-gate}.sh)
   Result: PASS (7 >= 7)
3. feature-completion-audit dead ref gone from hooks (non-attic)
   Command: grep -rn "feature-completion-audit" adapters/claude-code/hooks | grep -v attic
   Output: (empty; exit 1) — completion-criteria-gate.sh now references page-doc-accuracy-audit (1 occurrence)
   Result: PASS
4. conversation-tree-emit.sh dead fallback removed from reconciler
   Command: grep -n "conversation-tree-emit.sh" adapters/claude-code/hooks/workstreams-emit-reconciler.sh
   Output: (empty; exit 1)
   Result: PASS

Runtime verification: file adapters/claude-code/hooks/completion-criteria-gate.sh::page-doc-accuracy-audit

Verdict: PASS
Confidence: 9
Reason: PROVEN: at commit 887255b the six expired conv-tree shims are moved to adapters/claude-code/attic/ (7 entries incl. README), zero conversation-tree-*/conv-tree-* files remain under hooks/, the feature-completion-audit dead ref is gone from all non-attic hooks, and workstreams-emit-reconciler.sh no longer references conversation-tree-emit.sh.

## Task B.5 — Doc truth sweep

EVIDENCE BLOCK
==============
Task ID: B.5
Task description: Doc truth sweep (rules/docs files only): correct false/stale claims — git-discipline + INDEX force-push rows, INDEX feature-completion-audit dead ref, harness-hygiene /harness-review claim, automation-modes inventory counts, six files' "landing in Phase 1d-*" lines, sole-normative module paths, conv-tree-orchestrator-emit.md merged into workstreams-state.md, CLAUDE.md <=200-line trim, pending-Wave honesty markers — Verification: mechanical
Verified at: 2026-07-02T20:10:30Z
Verifier: task-verifier agent (Verification: mechanical)

Oracle: mechanical — per-item grep assertions from specs-b §B.5 + the rules-index-coverage golden eval as the regression floor
Verification level: mechanical
Comprehension-gate: not applicable (rung < 2)

Commit: e2f9814 (overhaul(B.5): doc truth sweep — 8 items correcting false/stale rule-file claims) — CLAUDE.md, INDEX.md, automation-modes, background-work-tracking, customer-facing-review, decision-context, definition-on-first-use, design-mode-planning, findings-ledger, git-discipline, harness-hygiene, session-end-protocol, workstreams-state, worktree-isolation + deletion of conv-tree-orchestrator-emit.md (-117 lines)

Checks run:
1. grep -c "not yet implemented" adapters/claude-code/rules/git-discipline.md → 0 — PASS
2. grep -c "no current hook" adapters/claude-code/rules/INDEX.md → 0 — PASS
3. grep -rl "landing in Phase 1d" adapters/claude-code/rules/ → empty (exit 1) — PASS
4. grep -rl "conversation-tree-ui/" adapters/claude-code/rules → empty (exit 1) — PASS
5. test ! -f adapters/claude-code/rules/conv-tree-orchestrator-emit.md → ABSENT — PASS
6. wc -l < adapters/claude-code/CLAUDE.md → 192 — PASS (<= 200)
7. grep -l "pending Wave" adapters/claude-code/rules/*.md | wc -l → 5 (background-work-tracking, customer-facing-review, session-end-protocol, workstreams-state, worktree-isolation — exactly the doctor check-5 honesty set) — PASS
8. bash evals/golden/rules-index-coverage.sh → "Indexed rules in sync: 59 / PASS", exit 0 — PASS

Runtime verification: file adapters/claude-code/rules/session-end-protocol.md::pending Wave

Verdict: PASS
Confidence: 9
Reason: PROVEN: all eight specs-b §B.5 assertions pass at commit e2f9814 — stale-claim strings zeroed, conv-tree-orchestrator-emit.md deleted and merged, CLAUDE.md at 192 lines, exactly 5 rules carry the "pending Wave" honesty marker, and the rules-index golden eval exits 0.

## Task B.11 — Plan-estate freeze (verification record)

EVIDENCE BLOCK
==============
Task ID: B.11
Task description: Plan-estate freeze: orchestrator-prime.md and workstreams-completed-filter-fix-2026-06-17.md flipped frozen: false → true with administrative rationale (full disposition remains F.3, operator-approved) — Verification: mechanical
Verified at: 2026-07-02T20:11:30Z
Verifier: task-verifier agent (Verification: mechanical)

Oracle: mechanical — header-field grep on both frozen plans + Decisions-Log-entry presence in the program plan (specs-b §B.11)
Verification level: mechanical
Comprehension-gate: not applicable (rung < 2)

Commit: 259c3f1 (plan(nl-overhaul): fold harness-reviewer REFORMULATE findings (12/12) — ... estate freeze (B.11) ...) — orchestrator-prime.md +1/-1, workstreams-completed-filter-fix-2026-06-17.md +1/-1

Checks run:
1. grep -c "^frozen: true" docs/plans/orchestrator-prime.md → 1 — PASS
2. grep -c "^frozen: true" docs/plans/workstreams-completed-filter-fix-2026-06-17.md → 1 — PASS
3. Decisions Log rationale entry present
   Command: grep -n "Administrative freeze" docs/plans/nl-overhaul-program-2026-07.md
   Output: line 211 — "### Decision: Administrative freeze of orchestrator-prime + workstreams-completed-filter-fix (B.11)" (Tier 1, reversible one-line flip, full disposition deferred to F.3)
   Result: PASS

Runtime verification: file docs/plans/orchestrator-prime.md::frozen: true

Verdict: PASS
Confidence: 9
Reason: PROVEN: both plans carry exactly one "^frozen: true" header line at commit 259c3f1 and the program plan's Decisions Log contains the "Administrative freeze" rationale entry (line 211), satisfying the B.11 Done-when.

## Task B.8 — Remote/account fetch-path fix

EVIDENCE BLOCK
==============
Task ID: B.8
Task description: Remote/account fetch-path fix: resolve the `Repository not found` on `git fetch origin` under the work gh account (remote URLs vs account mapping); verify both-remote sync works per the standing two-remote rule — Verification: mechanical
Verified at: 2026-07-02T20:19:47Z
Verifier: task-verifier agent (Verification: mechanical)

Oracle: mechanical — live both-remote fetch assertion from the MAIN checkout per specs-b §B.8 Done-when
Verification level: mechanical
Comprehension-gate: not applicable (rung < 2)

Commit: n/a — machine-state resolution (no repo diff; root cause was stale active gh account — the credential helper authenticates as the active account; the accounts.config dir-trigger mapping was already correct). Verified live at branch HEAD 2de07af.

Checks run:
1. Remote inventory at main checkout
   Command: cd "C:/Users/misha/dev/Pocket Technician/neural-lace" && git remote -v
   Output: origin = https://github.com/Pocket-Technician/neural-lace.git; personal = https://github.com/mishanovini/neural-lace.git (fetch+push each)
   Result: PASS
2. git fetch origin (main checkout, standing account state, no switch needed)
   Command: git fetch origin; echo $?
   Output: exit 0
   Result: PASS
3. git fetch personal (main checkout, same session)
   Command: git fetch personal; echo $?
   Output: exit 0
   Result: PASS
4. Account-switch fallback path (read-local-config match-dir + gh auth switch)
   Result: SKIPPED (not needed — both fetches exited 0 on first attempt under the standing account state, which per the spec IS the correct configuration for this directory)

Runtime verification: file docs/plans/nl-overhaul-program-2026-07-specs-b.md::git fetch origin && git fetch personal

Verdict: PASS
Confidence: 9
Reason: PROVEN: the specs-b §B.8 Done-when command pair was replayed live from the MAIN checkout "C:/Users/misha/dev/Pocket Technician/neural-lace" this session — `git fetch origin` exit 0 AND `git fetch personal` exit 0 with no account switch required, confirming the machine-state resolution holds as standing state.

## Task B.9 — Backlog reconciliation pass 1

EVIDENCE BLOCK
==============
Task ID: B.9
Task description: Backlog reconciliation pass 1: mark the entries this program absorbs with (absorbed by docs/plans/nl-overhaul-program-2026-07.md) — GAP-20/21/22, synthetic-session-runner P0, waiver-density alarm, continuation-enforcer wiring, GAP-52, GAP-53, tool-call-budget --ack HMAC item, GAP-42 — and close already-fixed-but-open items (GAP-19, STALE-PLANS-01) — Verification: mechanical
Verified at: 2026-07-02T20:19:47Z
Verifier: task-verifier agent (Verification: mechanical)

Oracle: mechanical — per-ID grep assertions on docs/backlog.md per specs-b §B.9 Done-when
Verification level: mechanical
Comprehension-gate: not applicable (rung < 2)

Commit: 18270b9 (overhaul(B.9): backlog reconciliation pass 1 — mark absorbed items, close 2 already-fixed) — docs/backlog.md

Checks run:
1. grep -c "absorbed by docs/plans/nl-overhaul-program-2026-07.md" docs/backlog.md → 11 — PASS (≥ 10)
2. grep -c "GAP-19" docs/backlog.md → 6 — PASS (≥ 1); entry line 112 reads "- **HARNESS-GAP-19 — [CLOSED 2026-07-02]** — ... **Evidence of closure:** grep -n \"session-wrap.sh refresh\" adapters/claude-code/settings.json.template matches" — CLOSED marker confirmed on the entry itself
3. Per-ID absorbed greps (each = count of that ID's lines carrying the absorbed marker): GAP-20 → 3, GAP-21 → 2, GAP-22 → 3, GAP-52 → 1, GAP-53 → 1, GAP-42 → 2, synthetic-session-runner → 1, waiver-density → 2, continuation-enforcer → 2, tool-call-budget --ack/HMAC → 1 — ALL PASS (≥ 1 each)
4. grep "STALE-PLANS-01" docs/backlog.md | grep -c "CLOSED" → 1 — PASS
5. Last-updated stamp refreshed
   Command: head -3 docs/backlog.md
   Output: line 3 = "**Last updated:** 2026-07-02 v59 — **NL overhaul program backlog reconciliation pass 1** (task B.9 ...)"; pre-B.9 state (git show 18270b9~1:docs/backlog.md) had the identical layout (line 1 title, line 2 blank, line 3 stamp) reading "2026-06-12 v58" — B.9 refreshed the stamp in place. Note: the stamp sits on line 3 (line 2 blank); this layout is pre-existing and unchanged by B.9, satisfying the plan's Done-when ("backlog Last updated line refreshed") and specs-b ("Refresh the Last updated line").
   Result: PASS

Runtime verification: file docs/backlog.md::absorbed by docs/plans/nl-overhaul-program-2026-07.md

Verdict: PASS
Confidence: 9
Reason: PROVEN: at commit 18270b9 the backlog carries 11 absorbed markers (≥ 10), every listed ID's entry greps to ≥ 1 absorbed/closed marker, GAP-19's entry carries "[CLOSED 2026-07-02]" with closure evidence, STALE-PLANS-01 is CLOSED, and the Last-updated line is refreshed to 2026-07-02 v59 (position line 3, pre-existing layout).

## Task B.10 — Baseline snapshot for D7 refutation criteria

EVIDENCE BLOCK
==============
Task ID: B.10
Task description: Baseline snapshot for D7 refutation criteria: record current metrics (downgrade counts, waiver counts, alert ack-rate, rules-dir bytes, Stop-chain length, live blocking-gate count) to docs/reviews/nl-overhaul-baseline-2026-07.md — Verification: mechanical
Verified at: 2026-07-02T20:19:47Z
Verifier: task-verifier agent (Verification: mechanical)

Oracle: mechanical — file-existence + six-section structure assertions per specs-b §B.10 Done-when ("file exists; all six sections have a number + command")
Verification level: mechanical
Comprehension-gate: not applicable (rung < 2)

Commit: 2de07af (overhaul(B.10): baseline snapshot for D7 refutation criteria — six metrics + reproduction commands; content authored by worker-B.10, integrated by orchestrator with In-flight scope line) — docs/reviews/nl-overhaul-baseline-2026-07.md, +162 lines (new file)

Checks run:
1. test -f docs/reviews/nl-overhaul-baseline-2026-07.md → exists — PASS
2. grep -c "^## [0-9]\." docs/reviews/nl-overhaul-baseline-2026-07.md → 6 — PASS (exactly six metric sections; the seventh "## Snapshot provenance" heading is non-metric)
3. Six required metric classes each present as a section heading: "## 1. Retry-guard downgrade entries" (L15) / "## 2. Acceptance waiver files count" (L34) / "## 3. External-monitor alert count + acked count" (L55) / "## 4. Live rules-dir byte size" (L74) / "## 5. Live Stop-chain entry count" (L90) / "## 6. Live blocking-gate count" (L129) — PASS
4. Each section carries a **Value:** line: 321 lines / 12 files / 33 total alerts, 0 acked / 883,882 bytes across 61 files / 20 hook entries / pending — PASS (section 6's "pending" is legitimate per the specs-b escape clause: "doctor output once B.6 lands — else note pending"; B.6 is unchecked at verification time, and the section includes the deferred reproduction command plus verified-absent evidence for harness-doctor.sh)
5. Reproduction command per section: grep -c '```bash' → 8 fenced bash blocks; sections 1–6 each contain ≥ 1 exact reproduction command — PASS
6. File tracked in git despite the docs/reviews date-prefix gitignore allowlist mismatch (documented one-time git add -f exception per the plan's In-flight scope updates)
   Command: git ls-files docs/reviews/nl-overhaul-baseline-2026-07.md
   Output: docs/reviews/nl-overhaul-baseline-2026-07.md
   Result: PASS

Runtime verification: file docs/reviews/nl-overhaul-baseline-2026-07.md::**Value:

Verdict: PASS
Confidence: 9
Reason: PROVEN: at commit 2de07af the baseline file exists and is git-tracked, contains exactly six metric sections matching the required classes (downgrade / acceptance-waiver / external-monitor / rules-dir bytes / Stop-chain / blocking-gate), each with a Value line and an exact reproduction command; section 6's "pending" value is explicitly sanctioned by the specs-b escape clause since B.6 has not landed.
