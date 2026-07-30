# Evidence — perf-telemetry-2026-07

## Task P2 (at-HEAD re-verification, supersedes the stale 7506451 block)
EVIDENCE BLOCK
==============
Task ID: P2
Verified at: 2026-07-29T17:10:00-07:00 (flip same day)
Verifier: task-verifier — PASS conf 7 (re-derivation at HEAD e8c74cb; the prior 7506451
verification was proven PARTLY STALE and is superseded by this block)
PROVEN first-hand at HEAD: one schema-correct JSONL line per tick (real degraded macOS run:
wmic absent -> degraded:true, honest; worktree_count real at 30); orphan detection with all
five guards green both interpreters; unarmed-never-kills proven by marker file; ARMED reap
proven by an actually-dead real process (sleep pid killed, ledger action="reaped");
health-tick 25/0 INCLUDING the P2 scenario; supervisor-tick's P2 scenario green.
AT-HEAD ADDENDUM replacing three stale evidence pillars: (1) perf-tick-snapshot's Scenario 9
is deterministic-RED on macOS (Windows-only ps -W), NOT the old "bookkeeping race" story —
needs capability-gating, filed; (2) the old byte-identical-blob claim is void (blob changed
in 9eb14b1/3e1da4f; the P2 surface re-verified green at the new blob); (3) health-tick is
25/0 now, superseding 24/25. Production enumeration degrades honestly on macOS until the
portability plan ports it — named, not silent. Arming on this Mac = no LaunchAgent yet
(operator step), absence of ticks.jsonl is the arming gap, not a build gap.
Runtime verification: test adapters/claude-code/scripts/health-tick.sh::--self-test (25/0 at HEAD, incl. P2 Scenario 7)
Runtime verification: file adapters/claude-code/scripts/supervisor-tick.sh::pts_run_tick
Runtime verification: file adapters/claude-code/scripts/health-tick.sh::pts_run_tick
