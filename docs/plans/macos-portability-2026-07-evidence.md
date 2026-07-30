# Evidence — macos-portability-2026-07 (task-verifier, 2026-07-29)

Verifier ran all suites under BOTH /bin/bash 3.2.57 AND /opt/homebrew/bin/bash 5.3.15 by
absolute path, BSD userland authentically in child PATH. M6 NOT flipped (S11 flake).

## Task M1
EVIDENCE BLOCK
==============
Task ID: M1
Verifier: task-verifier — PASS conf 9
PROVEN: pre-fix form RED-reproduced (`sed: 1: "SCRATCHPAD.md\n": invalid command code S`,
exit 1); post-fix `session-wrap.sh refresh` run live — stamp advanced, "all freshness
signals PASS". tmp+mv at session-wrap.sh:329-334 (NOT `sed -i ''`, per the plan's edge case).
Runtime verification: test adapters/claude-code/scripts/session-wrap.sh::--self-test (12/1 both interpreters; the 1 is a pre-existing tmpdir-symlink fixture issue, filed)
Runtime verification: file adapters/claude-code/scripts/session-wrap.sh::PORTABLE IN-PLACE EDIT (macos-portability M1

## Task M2
EVIDENCE BLOCK
==============
Task ID: M2
Verifier: task-verifier — PASS conf 9
PROVEN: supervisor-tick pre-fix form RED-reproduced (BSD bound -E as suffix, `rec.json-E`
litter); post-fix tmp+mv clean. ntfy-push 18/0 both interpreters. supervisor-tick 10/9 both,
DIFFERENTIALLY attributed (pre-M2 3e1da4f^ = 8/9 with the identical environmental leak —
post-M2 passes 2 more). Class sweep with /usr/bin/grep: zero suffix-less executed `sed -i`
remain in live scope. Plan's "3 callsites" was grep imprecision: 2 real, third was
non-executed command-string data.
Runtime verification: test adapters/claude-code/scripts/ntfy-push.sh::--self-test (18/0 both)
Runtime verification: test adapters/claude-code/scripts/supervisor-tick.sh::--self-test (10/9 both, differential vs 3e1da4f^ = 8/9)

## Task M3
EVIDENCE BLOCK
==============
Task ID: M3
Verifier: task-verifier — PASS conf 9
PROVEN: portable-timeout.sh 21/0 both interpreters AND 21/0 again under
PATH=/usr/bin:/bin:... where `command -v timeout` is EMPTY — the fallback itself ran.
Adversarial: 40-iteration stress + 12 real-script runs, 52/52 correct rc propagation, 0
spurious rc=0. Sweep: only remaining bare `timeout` is the lib's own guarded GNU branch;
all 11 adopters confirmed (incl. ask-registry.sh:445/:507, missed by a ugrep shell-function
anomaly and re-verified with /usr/bin/grep).
Runtime verification: test adapters/claude-code/hooks/lib/portable-timeout.sh::--self-test (21/0 both; 21/0 with GNU timeout absent from PATH)

## Task M4
EVIDENCE BLOCK
==============
Task ID: M4
Verifier: task-verifier — PASS conf 8
PROVEN: portable-time.sh 6/0 both (incl. metamorphic epoch round-trip). Sweep: every
surviving `date -d` in live scope carries a BSD fallback on the adjacent line (sites
enumerated in the verifier report). Behavioral floor: full M5 sweep under /bin/bash =
122 pass/46 fail, ZERO new vs baseline; residuals attributed to baselined non-M4 classes.
Conf 8: per-file verification partially delegated to the sweep oracle.
Runtime verification: test adapters/claude-code/hooks/lib/portable-time.sh::--self-test (6/0 both)
Runtime verification: file docs/backlog.md::PORTABILITY-GREP-PATTERN-01

## Task M5
EVIDENCE BLOCK
==============
Task ID: M5
Verifier: task-verifier — PASS conf 8
PROVEN: sweep 30/0 both interpreters; full run discovered=168 pass=122 fail=46 elapsed=623s
exit 0 "no new failures relative to the baseline"; RED-on-genuine-regression fixture (real
`date -d` GNU-ism) -> exit 1 REGRESSION line, baselined -> exit 0; doctor check fired LIVE
TWICE incl. a TRUE POSITIVE rc=1 against the real repo (the M6 flake) + the designed
stale-baseline WARN naming 7 now-passing rows. Housekeeping named, not absorbed: delete the
7 stale baseline rows + refresh the stale header comment.
Runtime verification: test adapters/claude-code/scripts/portability-sweep.sh::--self-test (30/0 both)
Runtime verification: file docs/portability-baseline.txt::^FAIL

## Task M6 — NOT FLIPPED (FAIL conf 8)
Disposition core fully verified green (fix 31/0 both; 2-entry ledger with root-caused
reasons; reader --list/--check/--verify stable; doctor RED fired live on a
ledger-without-reader fixture; manifest §10 satisfied; both excluded scripts
deterministically rc=1 12/12). THE GAP: selftest-sweep-exclusions.sh scenario S11
(:356-368) is FLAKY — 5/7 full-suite runs RED on BOTH interpreters incl. inside the
doctor's quiet sweep, so `doctor --portability` intermittently REDs the real repo.
Constitution-§7 "gate that false-fires" class. Fix + ≥10 stable runs both interpreters
required before re-verification.
