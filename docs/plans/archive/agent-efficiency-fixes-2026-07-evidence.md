# Evidence Log — Agent Efficiency Fixes (Windows spawn tax + self-test-sweep fork storm)

Verifier: task-verifier agent (session 29f2930a). Master converged both remotes at d048b65.
Batch-wide oracles executed this session: harness-doctor --self-test 129/129 (EXIT 0);
manifest-check GREEN (130 entries, 0 warn); blocking-budget GREEN 14/14; review records
hcr-20260724-63b76ebb (PASS, 46 files) + hcr-20260724-44ab0857 (PASS, 2 files).

## Task T1 — Land the two diagnosis lessons + this plan on master
EVIDENCE BLOCK
==============
Task ID: T1
Verified at: 2026-07-23T19:00:00Z
Verifier: task-verifier agent
Oracle: derived — the three files present in HEAD tree (git ls-tree) with commit history
Runtime verification: file docs/lessons/2026-07-20-efficiency-recurrence-live-diagnosis.md::Recurrence Diagnosis
Runtime verification: file docs/plans/agent-efficiency-fixes-2026-07.md::agent-efficiency-fixes
Checks run: git ls-tree -r HEAD confirms all three paths tracked; both lessons substantive (305 + 80 lines); plan 97 lines.
Verdict: PASS
Confidence: 9

## Task T2 — Gate session-start-digest.sh --self-test off the --quick path
EVIDENCE BLOCK
==============
Task ID: T2
Verified at: 2026-07-23T19:00:00Z
Verifier: task-verifier agent
Oracle: specified — the E.1 predicate must never execute the digest suite on --quick (docs/lessons/2026-07-20)
Runtime verification: test adapters/claude-code/hooks/harness-doctor.sh::c10-e1-no-exec (stub digest --self-test exit 1; --quick must emit NO e1-digest finding)
Runtime verification: test adapters/claude-code/hooks/session-start-digest.sh::--self-test (90/90)
Checks run: harness-doctor.sh E.1 predicate (lines 734-741) does only structural checks (exists/executable/declares --self-test), never `bash ... --self-test`; c10-e1-no-exec fixture green inside doctor --self-test 129/129; digest --self-test 90/90 EXIT 0.
Verdict: PASS
Confidence: 9

## Task T3 — SESSIONSTART-SINGLEFLIGHT-01 single-flight lock
EVIDENCE BLOCK
==============
Task ID: T3
Verified at: 2026-07-23T19:00:00Z
Verifier: task-verifier agent
Oracle: derived (lib self-test) + specified (live SessionStart skip reproduced against the deployed doctor)
Runtime verification: test adapters/claude-code/hooks/lib/sessionstart-singleflight.sh::--self-test (11/11)
Runtime verification: test adapters/claude-code/hooks/harness-doctor.sh::9-ssf-sessionstart-origin-skips-on-held-lock
Runtime verification: file adapters/claude-code/hooks/harness-doctor.sh::SESSIONSTART-SINGLEFLIGHT-01
Checks run: lib self-test 11/11; guard wired in all 3 hooks (auto-install/doctor/digest); LIVE reproduction — fresh held stamp then NL_SESSIONSTART_ORIGIN=1 doctor --quick skipped in 1s with the exact SESSIONSTART-SINGLEFLIGHT-01 message, rc 0; digest S20a/b/c green in 90/90; doctor check 9 green in 129/129.
Verdict: PASS
Confidence: 9

## Task T4 — find-disk-scan-gate.sh (BLOCK drive-wide find /)
EVIDENCE BLOCK
==============
Task ID: T4
Verified at: 2026-07-23T19:00:00Z
Verifier: task-verifier agent
Oracle: specified — the 2026-07-20 golden scenario `find / -iname scope-enforcement-gate*` must be blocked
Runtime verification: test adapters/claude-code/hooks/find-disk-scan-gate.sh::--self-test (19/19)
Runtime verification: file adapters/claude-code/hooks/find-disk-scan-gate.sh::BLOCKED
Checks run: self-test 19/19; golden probe `find / -iname "scope-enforcement-gate*"` -> rc 2 (BLOCK, message names own path); scoped `find ./src -name "*.ts"` -> rc 0; quoted-prose `git commit -m "guard against && find / scans"` -> rc 0; wired live PreToolUse (settings line 460) + template (line 274); manifest entry full section-10 bar (golden_scenario, fp_expectation, retirement_condition, waiver_path, honest_status); blocking-budget GREEN 14/14 includes it.
Verdict: PASS
Confidence: 9

## Task T5 — Retire dead exit 0 hook shims (workstreams-state-gate.sh) from live wiring
EVIDENCE BLOCK
==============
Task ID: T5
Verified at: 2026-07-23T19:00:00Z
Verifier: task-verifier agent
Oracle: contract — the shim removed from template + repo hooks/ + manifest, attic copy preserved, install prune added
Runtime verification: file adapters/claude-code/settings.json.template::(0 matches of workstreams-state-gate)
Runtime verification: test adapters/claude-code/scripts/manifest-check.sh::GREEN-130
Checks run: gone from template (0), repo hooks/ (absent), LIVE ~/.claude/hooks/ (absent); attic/workstreams-state-gate.sh present (49221 bytes); manifest entry removed (0 matches); manifest-check GREEN 130. Documented residual: live settings.json still wires it TWICE (merge_settings additive-only, no removal path) — honestly tracked in docs/backlog.md HOOK-SHIM-RETIRE-01; live doctor --quick surfaces this exact residual as RED (wiring-resolves + template-live-drift). Template-side retirement (the task) is complete.
Verdict: PASS (template+file+manifest+attic+install-prune done; live settings entries pending reconcile — documented HOOK-SHIM-RETIRE-01)
Confidence: 8

## Task T6 — Operator: Windows Defender exclusions
EVIDENCE BLOCK
==============
Task ID: T6
Verified at: 2026-07-23T19:00:00Z
Verifier: task-verifier agent
Oracle: human/operator — Verification: manual; operator attested via screenshots 2026-07-23
Runtime verification: file docs/plans/agent-efficiency-fixes-2026-07.md::Defender exclusions verified
Checks run: operator attestation committed to the plan In-flight amendments (lines 63-65, commit 275700e): exclusions incl. ~/.claude, claude-projects, Temp/claude, Temp/claude-scratch, C:/Program Files/Git; process exclusions bash/git/claude/node. Independent corroboration not possible in this session (Get-MpPreference requires admin — exactly why the task is designated manual/operator).
Verdict: PASS
Confidence: 7
