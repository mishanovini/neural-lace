# Evidence Log - nl-issues ledger triage + fix sweep (2026-07-09)

Verifier: task-verifier agent, 2026-07-09. All oracles re-run against origin/master
43f76c2 (batch-2 evidence commit; batch-1 4504db0 is its ancestor) on a clean
branch build/sweep-verifier-flips checked out from origin/master.

NOTE - task-ID normalization: the live plan-edit-validator evidence-first hatch
extracts task IDs with a dotted regex; this plan dotless IDs (A1, B5, R1...)
never match, so a flip could never be authorized regardless of evidence. Each
flipped task line therefore normalizes its ID to dotted form (A1 -> A.1) in the
same edit. Validator gap filed to the nl-issues ledger this session. No other
task text changed.

EVIDENCE BLOCK
==============
Task ID: A.1
Task description: A1 [48]+[52] sandbox unresolved-gaps feed path under HARNESS_SELFTEST in session-start-digest self-test S2
Verified at: 2026-07-09T20:52:00Z
Verifier: task-verifier agent
Oracle: specified + house self-test - session-start-digest.sh --self-test is the artifact own oracle
Comprehension-gate: not applicable (plan has no rung field; treated as rung 0)
Checks run:
1. Re-ran self-test: bash adapters/claude-code/hooks/session-start-digest.sh --self-test
   Output: self-test summary: 74 passed, 0 failed / self-test: OK 74/74
   Result: PASS (matches expected 74/74)
2. Override present: UNRESOLVED_GAPS_PATH wins at session-start-digest.sh:600-601
3. Bidirectional sandbox: S2 passes nonexistent override path (line 1280, quiet
   direction); S2b passes a fixture WITH gaps via override (line 1300, emit direction)
Runtime verification: test adapters/claude-code/hooks/session-start-digest.sh::--self-test
Runtime verification: file adapters/claude-code/hooks/session-start-digest.sh::UNRESOLVED_GAPS_PATH
Verdict: PASS
Confidence: 9
Reason: PROVEN: oracle re-executed this session (74/74 green) and the override is exercised in both directions by S2/S2b.

EVIDENCE BLOCK
==============
Task ID: A.2
Task description: A2 [49] add info event (work-integrity-gate) to observability-consumer-map with named consumer, or constrain emitter
Verified at: 2026-07-09T20:52:00Z
Verifier: task-verifier agent
Oracle: contract - observability-consumer-map.json must be jq-valid and name a real consumer for the info event type
Comprehension-gate: not applicable (plan has no rung field; treated as rung 0)
Checks run:
1. jq . adapters/claude-code/observability-consumer-map.json parses clean (JQ-VALID)
2. .event_types.info.consumers[0] names selftest:stop-verdict-dispatcher.sh as the
   purpose-built consumer of the only work-integrity-gate.sh info emission
   (manifest-scoping active, work-integrity-gate.sh line ~956), explicitly closing
   NL-issue [49] as option (a); consumers[1] digest:feed_ledger_summary and
   consumers[2] cli:nl-status also listed
Runtime verification: file adapters/claude-code/observability-consumer-map.json::selftest:stop-verdict-dispatcher.sh
Verdict: PASS
Confidence: 9
Reason: PROVEN: entry read directly from origin/master content; jq parse green; the named consumer is the dispatcher self-test that mechanically greps the emission.

EVIDENCE BLOCK
==============
Task ID: A.3
Task description: A3 [51] cold-reader-lint: require sec-3 block shape, exclude negation; self-test scenario
Verified at: 2026-07-09T20:52:00Z
Verifier: task-verifier agent
Oracle: house self-test - stop-verdict-dispatcher.sh --self-test
Comprehension-gate: not applicable (plan has no rung field; treated as rung 0)
Checks run:
1. Re-ran self-test: bash adapters/claude-code/hooks/stop-verdict-dispatcher.sh --self-test
   Output: self-test summary: 66 passed, 0 failed
   Result: PASS (matches expected 66)
2. Scenario 24 negation direction PASS: cold-reader-lint-negated-decision-needed-not-flagged
   (s24neg fixture with a negated no-decision-needed sentence exits 0, hook lines 2227-2243)
3. Positive control still detected PASS: cold-reader-lint-real-sec3-block-still-detected (s24pos)
Runtime verification: test adapters/claude-code/hooks/stop-verdict-dispatcher.sh::--self-test
Verdict: PASS
Confidence: 9
Reason: PROVEN: oracle re-executed (66/66); the [51] regression scenario passes in BOTH directions (negated prose not flagged, real sec-3 block still detected).

EVIDENCE BLOCK
==============
Task ID: A.4
Task description: A4 [31] install.sh sync loops gain skills/ + templates/
Verified at: 2026-07-09T20:52:00Z
Verifier: task-verifier agent
Oracle: specified - the sync loop must enumerate skills and templates; implicit floor bash -n
Comprehension-gate: not applicable (plan has no rung field; treated as rung 0)
Checks run:
1. bash -n adapters/claude-code/install.sh exits clean (BASH-N-CLEAN)
2. Real sync loop install.sh:928 enumerates rules agents hooks scripts
   pipeline-prompts pipeline-templates commands doctrine skills templates
3. Preview loop install.sh:452 mirrors the same list; stale repo-root
   patterns/templates source removed per comments at lines 1031-1032
4. install.sh NOT executed (per verification directive - sync-to-live out of scope)
Runtime verification: file adapters/claude-code/install.sh::doctrine skills templates
Verdict: PASS
Confidence: 8
Reason: PROVEN: loop content read from master; bash -n green. Execution of install.sh deliberately excluded by the caller directive, so evidence is structural per the declared oracle.

EVIDENCE BLOCK
==============
Task ID: A.5
Task description: A5 [47]+[25] denylist: narrow codename pattern + relocate literal test-password VALUE to gitignored business-patterns.d - harness-reviewer REQUIRED (security control)
Verified at: 2026-07-09T20:52:00Z
Verifier: task-verifier agent
Oracle: house self-test + independent adversarial probe (both directions, real shipped denylist)
Comprehension-gate: not applicable (plan has no rung field; treated as rung 0)
Checks run:
1. Re-ran self-test: bash adapters/claude-code/hooks/harness-hygiene-scan.sh --self-test
   Output: self-test: OK; grep counts over full output: 0 SKIP, 0 FAIL
   Result: PASS - c1-c9 codename scenarios exercised, not skipped
2. Narrowed pattern present at adapters/claude-code/patterns/harness-denylist.txt:38
   (prefix-complement alternation replacing the old right boundary; commented
   c1-c9 contract in the file at lines 23-36)
3. Independent fixture probe (git-init temp repo, shipped denylist copied to the
   adapters/claude-code/patterns/ relative path, global hooksPath cleared):
   idiom-with-space exits 0; idiom-with-hyphen exits 0; codename-in-prose exits 1
   with denylist label; codename-at-end-of-line exits 1 with denylist label
4. [25] relocation: scan self-test asserts the literal credential VALUE is out of
   the shipped denylist (self-test comment near line 341); relocation landed
   pre-sweep at bebe811
5. Known filed residual (not a blocker; ledger row [67]): scanner treats grep
   exit-2 as no-match; three non-POSIX lookahead lines remain in the denylist
Runtime verification: test adapters/claude-code/hooks/harness-hygiene-scan.sh::--self-test
Runtime verification: file adapters/claude-code/patterns/harness-denylist.txt::scenarios c1-c9
Verdict: PASS
Confidence: 9
Reason: PROVEN: no-weakening demonstrated adversarially this session - the generic idiom passes AND the codename trips via Layer 1 in an independent fixture, plus the 0-SKIP/0-FAIL self-test.

EVIDENCE BLOCK
==============
Task ID: A.6
Task description: A6 [54] verify/extend .gitattributes eol=lf coverage for workflow .js paths
Verified at: 2026-07-09T20:52:00Z
Verifier: task-verifier agent
Oracle: derived - committed blobs on origin/master; CR-detection grep control-proven (RED direction)
Comprehension-gate: not applicable (plan has no rung field; treated as rung 0)
Checks run:
1. .gitattributes:21 pins *.js text eol=lf (plus *.mjs at line 22)
2. git grep -l for the CR byte over origin/master limited to *.js returns zero files
3. RED control proving the oracle detects CR in committed blobs: the same pattern
   over *.md finds origin/master:docs/reviews/2026-05-25-harness-self-eval.md
   (3 matching lines), so the zero-result on .js is a real zero, not a masked grep
Runtime verification: file .gitattributes::eol=lf
Verdict: PASS
Confidence: 9
Reason: PROVEN: pin present and zero CR matches across committed .js blobs, with a positive control demonstrating the grep is CR-capable.

EVIDENCE BLOCK
==============
Task ID: B.1
Task description: B1 [26]+[27]+[30]+[45]+[53] end-manifest cluster (residuals after verify-first: [45] jq slurp any(), [53] sanctioned resolution path)
Verified at: 2026-07-09T20:52:00Z
Verifier: task-verifier agent
Oracle: house self-test - end-manifest.sh --self-test
Comprehension-gate: not applicable (plan has no rung field; treated as rung 0)
Checks run:
1. Re-ran self-test: bash adapters/claude-code/scripts/end-manifest.sh --self-test
   Output: self-test summary: 32 passed, 0 failed
   Result: PASS (matches expected 32)
2. s13b both directions PASS: untracked file outside .claude/state keeps gap
   listed AND same file inside .claude/state is excluded - gap resolves
3. s13c fail-closed PASS: apostrophe-containing path fails closed (gap stays
   listed) - the harness-reviewer Major fix, proven in this run
Runtime verification: test adapters/claude-code/scripts/end-manifest.sh::--self-test
Verdict: PASS
Confidence: 9
Reason: PROVEN: oracle re-executed (32/32) including resolution-path scenarios s13b/s13c; the fail-closed edge is demonstrated, honoring the plan edge case that gaps never silently vanish.

EVIDENCE BLOCK
==============
Task ID: B.5
Task description: B5 [37]+[39]+[55] cockpit/derive-cache: single-instance lock or listen-gate before cache.start(); single-flight poll guard; OBS_NL_TIMEOUT_MS review
Verified at: 2026-07-09T20:52:00Z
Verifier: task-verifier agent
Oracle: house self-test - node server/server.selftest.js (workstreams-ui)
Comprehension-gate: not applicable (plan has no rung field; treated as rung 0)
Checks run:
1. Re-ran from neural-lace/workstreams-ui: node server/server.selftest.js
   Output: self-test summary: 35 passed, 0 failed
   Result: PASS (matches expected 35)
2. [39] single-flight poll guard scenarios green: S17/S17b/S17c/S17d (skipped cycle
   never notifies; real cycle notifies exactly once; next cycle runs normally)
3. [55] single-instance guard scenarios green: S18/S18b/S18c (second instance on an
   occupied port exits 0, logs the one-line guard message, never starts the poll loop)
Runtime verification: test neural-lace/workstreams-ui/server/server.selftest.js::node selftest 35 passed
Verdict: PASS
Confidence: 9
Reason: PROVEN: oracle re-executed (35/35) with the [55] and [39] scenarios individually green in this session run output.

EVIDENCE BLOCK
==============
Task ID: B.6
Task description: B6 [23]+[35]+[38] (+[63]) doctrine/docs: orchestrator-pattern shared-checkout disciplines; acceptance conventions registered-event-types-only + scrub coordination
Verified at: 2026-07-09T20:52:00Z
Verifier: task-verifier agent
Oracle: specified (required sections present, substantive) + golden eval (rules-index-coverage)
Comprehension-gate: not applicable (plan has no rung field; treated as rung 0)
Checks run:
1. adapters/claude-code/doctrine/orchestrator-pattern-full.md:105 is the header
   Shared-checkout git-state disciplines (incident-derived)
2. Compact adapters/claude-code/doctrine/orchestrator-pattern.md is 2870 bytes
   (under the 3000 cap) and carries all three disciplines: WORKTREE-CHECK brief
   line, BRANCH-VERIFY plus ls-remote push proof, COMMIT-VERIFY-AFTER-DENIAL
3. docs/reviews/2026-07-06-o4-acceptance-scenarios.md line 27 REGISTERED-EVENT-TYPES-ONLY
   and line 31 FIXTURE-SCRUB COORDINATION, both with incident dates
4. bash evals/golden/rules-index-coverage.sh: Checks passed: 4, PASS line, exit 0
Runtime verification: test evals/golden/rules-index-coverage.sh::4 checks PASS
Runtime verification: file adapters/claude-code/doctrine/orchestrator-pattern-full.md::Shared-checkout git-state disciplines
Runtime verification: file docs/reviews/2026-07-06-o4-acceptance-scenarios.md::REGISTERED-EVENT-TYPES-ONLY
Verdict: PASS
Confidence: 9
Reason: PROVEN: all four caller-named oracles re-run or read directly on master content; the 3000-byte compact cap is mechanically enforced by the passing golden eval.

EVIDENCE BLOCK
==============
Task ID: R.1
Task description: R1 [34]+[46]+[40]+[43]/[44] mechanism proposals routed to backlog rows with fold-in points
Verified at: 2026-07-09T20:52:00Z
Verifier: task-verifier agent
Oracle: specified - the four named rows exist in docs/backlog.md, each with a fold-in point
Comprehension-gate: not applicable (plan has no rung field; treated as rung 0)
Checks run:
1. docs/backlog.md:15 SHARED-CHECKOUT-BRANCH-GUARD-01 (fold-in: orchestration-hardening plan)
2. docs/backlog.md:17 CRED-403-JIT-TRIGGER-01 (fold-in: doctrine-jit trigger inventory)
3. docs/backlog.md:19 COLD-READER-MECH-LAYER-01 (fold-in: decision-surfaces/UX plan)
4. docs/backlog.md:21 BG-AGENT-AUTO-RETRY-01 (fold-in: ADR-061 Phase 3)
   All four dated 2026-07-09, sourced to this sweep R1, labeled, with golden scenarios.
Runtime verification: file docs/backlog.md::SHARED-CHECKOUT-BRANCH-GUARD-01
Runtime verification: file docs/backlog.md::CRED-403-JIT-TRIGGER-01
Runtime verification: file docs/backlog.md::COLD-READER-MECH-LAYER-01
Runtime verification: file docs/backlog.md::BG-AGENT-AUTO-RETRY-01
Verdict: PASS
Confidence: 9
Reason: PROVEN: all four rows grep-confirmed on master content with substantive bodies and explicit fold-in points, not placeholders.

EVIDENCE BLOCK
==============
Task ID: R.2
Task description: R2 [21] GAP-54 backlog row current + [32] Claude_Preview parent-worktree launch.json documented upstream
Verified at: 2026-07-09T20:52:00Z
Verifier: task-verifier agent
Oracle: specified (caller Done-state) - GAP-54 row exists + CLAUDE-PREVIEW-WORKTREE-01 row exists in docs/backlog.md
Comprehension-gate: not applicable (plan has no rung field; treated as rung 0)
Checks run:
1. docs/backlog.md:928 HARNESS-GAP-54 (2026-07-06) section - current, with still-open
   items (a)/(b) enumerated; deferral state intact
2. docs/backlog.md:29 CLAUDE-PREVIEW-WORKTREE-01 - labeled upstream, self-contained
   documented-upstream note (symptom, mechanism, workaround, revisit condition)
3. Caveat (named, non-blocking versus the caller Done-state): the task text said
   document-upstream note in doctrine; the note is homed in docs/backlog.md, not
   doctrine/ (grep of adapters/claude-code/doctrine/ finds no [32] note). Substance
   present, location deviates; the caller explicit oracle is the two rows.
Runtime verification: file docs/backlog.md::CLAUDE-PREVIEW-WORKTREE-01
Runtime verification: file docs/backlog.md::HARNESS-GAP-54
Verdict: PASS
Confidence: 8
Reason: PROVEN: both rows grep-confirmed on master content. Confidence 8 not 9 because the [32] note home deviates from the task literal wording (backlog, not doctrine) - verified against the caller-declared Done-state.

EVIDENCE BLOCK
==============
Task ID: R.3
Task description: R3 mark every ledger row disposition via nl-issue.sh (terminal state; zero untriaged in sweep scope 21-56)
Verified at: 2026-07-09T20:52:00Z
Verifier: task-verifier agent
Oracle: derived - live ledger query via the ledger own CLI
Comprehension-gate: not applicable (plan has no rung field; treated as rung 0)
Checks run:
1. bash ~/.claude/scripts/nl-issue.sh --list --untriaged returned untriaged rows
   [57] [58] [61] [66] [67] [68] [69] [70] only. None fall inside the sweep scope
   [21]-[56]; all are post-sweep rows, out of scope per the caller directive.
Runtime verification: test ~/.claude/scripts/nl-issue.sh::--list --untriaged zero rows in 21-56
Verdict: PASS
Confidence: 9
Reason: PROVEN: the ledger CLI re-queried this session; every sweep-scope row 21-56 has a terminal disposition (absent from the untriaged listing).

EVIDENCE BLOCK
==============
Task ID: B.2
Task description: B2 [42] dispatcher: surface combined verdict in the block message (stderr never reaches session context)
Verified at: 2026-07-10T00:57:15Z
Verifier: task-verifier agent (round 2)
Oracle: house self-test - stop-verdict-dispatcher.sh --self-test (specified: block-JSON reason on stdout carries per-gate verdict + pin-d remediation; truncation names a full-verdict state file)
Comprehension-gate: not applicable (plan has no rung field; treated as rung 0)
Checks run:
1. Re-ran self-test: bash adapters/claude-code/hooks/stop-verdict-dispatcher.sh --self-test
   Output: self-test summary: 73 passed, 0 failed
   Result: PASS (matches expected 73)
2. [42] scenarios green in this run: s25 (reason-carries-per-gate-line-with-remediation,
   reason-lists-EVERY-gate-not-just-the-first, stale-see-stderr-pointer-gone-and-no-truncation-
   at-default-cap) and s26 (truncation-caps-reason-and-names-full-verdict-file,
   full-verdict-state-file-written-with-ALL-gaps)
3. Diff correspondence (3ba155c): reason entries built as "[gate/check] msg -> pin-d
   remediation" INSIDE the stdout block-JSON; truncation writes state/stop-verdict-full-<short>.txt
Anomaly note: first run this session reported 61/12 FAIL — root-caused to the agent worktree
being externally pruned MID-RUN (tree emptied, exit 127 inside scenarios; subsequent invocation
"No such file or directory"). Worktree re-registered on build/sweep-verifier-flips-2 at 08a3351;
clean re-run is 73/0. Not a product defect.
Runtime verification: test adapters/claude-code/hooks/stop-verdict-dispatcher.sh::--self-test
Verdict: PASS
Confidence: 9
Reason: PROVEN: oracle re-executed 73/73 at origin/master 08a3351 including both [42] scenario groups; diff shows the per-gate+remediation reason construction and the full-verdict state file writer.

EVIDENCE BLOCK
==============
Task ID: B.3
Task description: B3 [22] live ~/.claude CRLF drift — docs-only close (verify-first: both remedies already landed 1d6954a; drift converged 0/166 CR)
Verified at: 2026-07-10T00:57:15Z
Verifier: task-verifier agent (round 2)
Oracle: derived-preexisting - the 1d6954a mechanism (doctor live-mirror scan + install.sh normalize-on-copy) is the fix; the plan Decisions-Log entry is the docs deliverable
Comprehension-gate: not applicable (plan has no rung field; treated as rung 0)
Checks run:
1. grep -c LIVE-MIRROR-CRLF adapters/claude-code/hooks/harness-doctor.sh -> 5 occurrences
   (live-mirror WARN scan present at master tip)
2. git merge-base --is-ancestor 1d6954a 08a3351 -> yes (fix commit is on master)
3. cp_normalized present in install.sh (:134; call sites :364, :857) — normalize-on-copy live
4. Plan note present: Decisions Log :131 records the B3 verify-first (already-fixed 1d6954a,
   live convergence 0/166 CR, stale-memory note routed to orchestrator)
5. Doctor self-test re-run this session: 83 passed, 0 failed — includes the line-endings
   live-mirror fixtures (line-endings-live-mirror-warns/-lib-warns/-green/-never-red)
Runtime verification: file adapters/claude-code/hooks/harness-doctor.sh::LIVE-MIRROR-CRLF
Runtime verification: test adapters/claude-code/hooks/harness-doctor.sh::--self-test
Verdict: PASS
Confidence: 9
Reason: PROVEN: docs-only close verified — the claimed pre-existing fix is on master ancestry, its scan + fixtures re-exercised green (83/83), and the plan carries the verify-first record at :131.

EVIDENCE BLOCK
==============
Task ID: B.4
Task description: B4 [56] scheduled-task naming drift: doctor check_obs_cockpit_fresh re-pointed (mechanism gate = ensure-cockpit.sh presence, nested workstreams-ui path, curl liveness probe; WARN-never-RED)
Verified at: 2026-07-10T00:57:15Z
Verifier: task-verifier agent (round 2)
Oracle: house self-test - harness-doctor.sh --self-test (incl. cockpit fixtures warn-fires / green-up / green-nomech)
Comprehension-gate: not applicable (plan has no rung field; treated as rung 0)
Checks run:
1. Re-ran self-test: bash adapters/claude-code/hooks/harness-doctor.sh --self-test
   Output: self-test summary: 83 passed, 0 failed
   Result: PASS (matches expected 83)
2. Static correspondence, check_obs_cockpit_fresh (:1263-1307): mechanism gate =
   ${live_home}/scripts/ensure-cockpit.sh presence (:1276); cockpit dir = nested canonical
   ${repo_root}/neural-lace/workstreams-ui/server (:1266-1267); liveness = curl probe of
   http://127.0.0.1:7733/ (:1303) with curl-absent green skip (:1299); sole non-green path
   is one _warn call (:1304) — WARN-never-RED preserved
3. Dead layers gone: no schtasks query and no derived-cache-stamp read remain in the function
   (full function read this session)
Runtime verification: test adapters/claude-code/hooks/harness-doctor.sh::--self-test
Verdict: PASS
Confidence: 9
Reason: PROVEN: oracle re-executed 83/83 at 08a3351; the re-pointed gates match the task's three claimed fixes line-for-line and the WARN-only contract is structurally intact.

EVIDENCE BLOCK
==============
Task ID: B.7
Task description: B7 [24] set-e assignment-from-failing-pipeline audit across hooks/*.sh; tdd-gate deletion-only-diff guard + record-test-pass outside-repo guard + plan-edit-validator replica alignment
Verified at: 2026-07-10T00:57:15Z
Verifier: task-verifier agent (round 2)
Oracle: house self-tests - pre-commit-tdd-gate.sh --self-test AND plan-edit-validator.sh --self-test
Comprehension-gate: not applicable (plan has no rung field; treated as rung 0)
Checks run:
1. Re-ran: bash adapters/claude-code/hooks/pre-commit-tdd-gate.sh --self-test
   Output: ALL SELF-TESTS PASSED (6/6) — incl. E-deletion-only-test-diff-allowed
   Result: PASS (matches expected 6/6)
2. Re-ran: bash adapters/claude-code/hooks/plan-edit-validator.sh --self-test
   Output: self-test summary: 15 passed, 0 failed (of 15 scenarios)
   Result: PASS (matches expected 15/15)
3. Diff correspondence (08a3351): tdd-gate Layer-5 added=$(... | grep ... || true) guard +
   scenario E (suite 5/5 -> 6/6, red-green per commit message); record-test-pass.sh
   repo_root=$(git rev-parse ... || true) making the graceful not-a-repo exit-2 reachable;
   plan-edit-validator selftest_check_docs_impact_warn replica gains || true mirroring the
   fixed production check_docs_impact_warn
Runtime verification: test adapters/claude-code/hooks/pre-commit-tdd-gate.sh::--self-test
Runtime verification: test adapters/claude-code/hooks/plan-edit-validator.sh::--self-test
Verdict: PASS
Confidence: 9
Reason: PROVEN: both oracles re-executed green at 08a3351 (6/6 incl. the deletion-only scenario; 15/15) and all three claimed [24]-class guards are present in the merged diff.

EVIDENCE BLOCK
==============
Task ID: B.8
Task description: B8 [59] pr-template-inline-gate: skip existence test on unexpandable --body-file paths (expand shell vars where defined; never false-WARN)
Verified at: 2026-07-10T00:57:15Z
Verifier: task-verifier agent (round 2)
Oracle: house self-test - pr-template-inline-gate.sh --self-test
Comprehension-gate: not applicable (plan has no rung field; treated as rung 0)
Checks run:
1. Re-ran self-test: bash adapters/claude-code/hooks/pr-template-inline-gate.sh --self-test
   Output: all 17 self-tests passed
   Result: PASS (matches expected 17/17)
2. [59] scenarios individually green in this run: T13 undefined var -> ALLOW,
   skipped-unexpandable, no false WARN; T14 defined var valid -> ALLOW after env expansion;
   T15 defined var invalid -> ALLOW + template WARN after expansion (gate still does its job
   when the path IS expandable); T16 command substitution -> skipped-unexpandable;
   T17 ${VAR:-x} operator form -> skipped-unexpandable
Runtime verification: test adapters/claude-code/hooks/pr-template-inline-gate.sh::--self-test
Verdict: PASS
Confidence: 9
Reason: PROVEN: oracle re-executed 17/17 at 08a3351; the false-WARN class from the ledger ([59], 3x this session) is covered both directions — unexpandable paths skip, expandable paths still validate.
