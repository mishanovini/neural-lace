# O.4 cockpit — acceptance scenarios (plan-time, end-user-advocate) + contract feedback

Authored 2026-07-06 by end-user-advocate (plan-time mode) against specs-o §O.4/§O.3
(@ a3744d8) and the design sketch's six operator questions. RUNTIME mode executes
these scenarios verbatim against the live cockpit at http://localhost:7733 and writes
the PASS/FAIL artifact O.4's Done-when requires. Verdict at authoring: FAIL
(1 Critical spec gap) — ALL flagged gaps were folded into specs-o §O.0.1-3, C4, and
§O.4.3/3b by the orchestrator on 2026-07-06 (same-day amendments); the Critical
interrupt-priority rule now binds the builder.

## Runtime conventions (apply to every scenario)

- Oracle CLI = `bash ~/.claude/scripts/nl.sh <sub> --json`. THE ACCEPTANCE BAR:
  what a pane displays must equal what the oracle returns when run within 5s of the
  pane's refreshed render (derived-vs-displayed equality — thin-view IS the spec).
- Fixture ids: `acc-o4-<role>-<rand4>`, randomized per run (defeats teach-to-the-test);
  prefix used for cleanup sweeps.
- Seeding surfaces (all mechanical): heartbeat files `~/.claude/state/heartbeats/<sid>.json`
  (C1 schema, tmp+mv); ledger lines via `CLAUDE_CODE_SESSION_ID=<sid> bash -c
  'source ~/.claude/hooks/lib/signal-ledger.sh && ledger_emit "<gate>" "<event>" "<detail>"'`;
  NEEDS-YOU entries ONLY via `needs-you.sh add` (capture printed id; never hand-edit);
  tree-state via `resolve_workstreams_state_path` (ALWAYS back up, restore after).
- Cleanup after every run: delete `acc-o4-*` heartbeats; `needs-you.sh resolve <id>
  --note "O.4 acceptance fixture"`; restore tree-state backups. Seeded ledger lines
  remain (append-only by design).
- "Force refresh" = the cockpit's refresh affordance / documented endpoint, else one
  cache cycle (35s). Exact selectors, tolerances, and fixture strings stay private to
  the advocate's runtime run (assertions-private discipline).

## The ten scenarios

1. **q1-session-board-derived-states** — seed heartbeats for working (fresh ts),
   stalled (ts−45min + recorded dead pid), waiting-on-me (fresh ts + needs-you entry
   joined on sid). Board must list all three + the real live session(s); every chip
   equals `nl status --json` same-moment; no extra, no missing sessions; Q1
   answerable at a glance. Artifacts: board screenshot + same-moment oracle JSON +
   network/console logs. Edges: throttled chip via seeded `throttle-detected` event;
   remote-ledger session renders consistent with oracle, never as local-live.
2. **q2-needs-me-ledger-parity** — seed a §3-format decision entry (with --link to
   the plan); pane's open ids/count equal `nl needs-me --json`; entry renders its
   block inline; link observably opens the target; after terminal
   `needs-you.sh resolve`, entry leaves the pane on next refresh (pane reflects
   ledger, not memory). Before/after screenshots + oracle JSON both moments.
3. **q3-diff-since-last-look** — set last-look T=now−24h; pane's four lists
   (shipped SHAs, plan transitions, decisions, failures) set-equal
   `nl shipped --since T --json`; after mark-seen + full reload the last-look
   reference persists (seen items don't re-present as new; nothing after the look
   is dropped).
4. **q4-harness-health-strip** — displayed doctor verdict equals the oracle's
   cached verdict AND shows its age (fresh GREEN distinguishable from stale GREEN);
   per-gate 7d block/waiver/downgrade counts equal oracle; waiver-dominant gates
   visibly flagged.
5. **q5-costs-strip-parity** — session set equals `nl costs --json`; quiescent
   sessions (heartbeat >2min old) match exactly, active ones within one refresh
   cycle; throttle counts + time-lost equal oracle; every number names its oracle
   inline or matches the CLI output that does. Edge: oracle-labeled stale/partial
   transcript sections carry the same label in the strip.
6. **q6-why-drawer-causal-chain** — seed the 024-class chain under a fixture sid
   (spawn-dispatched → workstreams-state-gate block → retry/allow, mirroring
   tests/fixtures/wave-o/O.3/); drawer renders the time-ordered chain equal to
   `nl why <sid> --last-block` incl. the one-line verdict; transcript absence
   labeled honestly. Edges: nonexistent sid → clear no-data message (no spinner,
   no crash); a real recent blocked session → chain includes transcript-side steps.
7. **drift-badge-on-seeded-mismatch** — inject a ghost live-node claim into
   tree-state (backed up); badge visible in normal viewport + ledger warn
   (gate=cockpit-reconciler) recorded; ghost session appears in NO pane (derived
   truth only); after restore, badge clears (not latched). If retirement already
   removed all tree-state reads: record superseded-with-evidence, not SKIP.
8. **degraded-cli-honest-errors** — relaunch server with NL_BIN=failing-stub; every
   pane shows an explicit derivation-unavailable ERROR state (no blanks, no eternal
   spinners, no unlabeled cached numbers); endpoints return error signals; page
   survives; after restoring the real CLI the panes recover via push/refresh with
   no reload ritual.
9. **unobserved-cloud-honest-label** — seed a ledger session-start with NO
   heartbeat/transcript; board labels it unobserved-cloud exactly as the oracle
   does; unknown fields read unknown, never fabricated.
10. **interrupt-priority-visual-primacy** — seed competing working/stalled sessions
    + one WAITING-ON-ME pair (fresh heartbeat + open needs-you entry); on COLD LOAD
    at desktop viewport, both the WAITING-ON-ME row (sorted above all states) and
    the needs-you entry (above Q3/Q4/Q5 in reading order) sit inside the initial
    viewport with mechanically distinct emphasis; no neutral content outranks them.
    Adversarial demotion: resolve the entry + refresh the heartbeat to DONE —
    both demote on next refresh (primacy is derived, not sticky).

## Out-of-scope (with owner)

Trust-path retirement mechanics (orchestrator: manifest/doctor + O.6 predicates;
browser proxy covered by #7/#8) · ntfy push drill (O.5, orchestrator-run) ·
`nl`/derivation correctness in isolation (O.3 Done-when drills — here the CLI is the
ORACLE; if cockpit and CLI agree but are both wrong, that is an O.3 failure caught
there) · cross-machine rendering fidelity (O.3 read-both; one soft edge in #1) ·
cockpit autostart/scheduled-task health (O.6) · real-time streaming latency (sketch
non-goal; 30s cadence accepted).

## Plan-time feedback (all dispositioned same-day by orchestrator)

- CRITICAL unranked-surface-priority: interrupt-priority rule absent from builder
  spec → ADDED as specs-o §O.4.3b (binding).
- IMPORTANT derived-state-without-named-ground-truth-rule: blocked/unobserved-cloud/
  throttled had no computable rules → ADDED to C4 od_sessions (rules + tie priority);
  routed to the live O.3 builder.
- IMPORTANT ground-truth-source-without-sandbox-override: OBS_TRANSCRIPTS_ROOT,
  OBS_MAIN_CHECKOUT, OBS_DOCTOR_CACHE_DIR, OBS_BACKLOG_PATH → ADDED to §O.0.1-3;
  routed to the live O.3 builder.
- IMPORTANT alert-without-lifecycle-spec: drift badge fire/clear/dedup/placement →
  ADDED to §O.4.3.
- IMPORTANT trust-surface-without-freshness-contract: per-pane derived-as-of labels,
  stale labeling, visible Refresh control → ADDED to §O.4.3b (converges with
  ux-review amendments 1/4).
- NICE-TO-HAVE state-without-user-control: Q3 last-look visible + Mark-seen control
  → ADDED to §O.4.3b (converges with ux-review amendment 3).
