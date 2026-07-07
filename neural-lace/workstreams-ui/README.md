# workstreams-ui

<!-- last-verified: 2026-07-06 (O.4 cockpit rebuild) -->

The Workstreams cockpit — a localhost, READ-ONLY operator dashboard answering
the NL Observability Program's six operator questions (design sketch:
`docs/reviews/2026-07-04-observability-design-sketch.md`; binding spec:
`docs/plans/nl-observability-program-2026-08-specs-o.md` §O.4). It is a THIN
VIEW over the derivation lib (`adapters/claude-code/hooks/lib/
observability-derive.sh`, contract C4) via the `nl` CLI (contract C5) —
DERIVE, DON'T MAINTAIN (law 1). It NEVER renders the legacy event-sourced
tree-state as truth and ships NO write affordances: this app cannot spawn,
steer, or answer for you. Answering "what needs me" happens in your
sessions/chat; this cockpit only tells you WHAT needs an answer and WHERE.

This replaces the pre-O.4 three-pane tree/accordion GUI (retired — see
`attic/README.md`), whose event-sourced `tree-state.json` truth model
repeatedly drifted from reality (WORKSTREAMS-UI-PURPOSE-AUDIT-01, operator
verdict "failed completely"; NL-FINDING-024).

## The six questions (+ backlog health)

| # | Question | Pane | Oracle |
|---|---|---|---|
| 1 | What's running | session board | `nl status` / `od_sessions` |
| 2 | What needs me | needs-me list | `nl needs-me` / `od_needs_me` |
| 3 | What happened since I last looked | diff-since-last-look | `nl shipped` / `od_shipped_since` |
| 4 | Is the harness working | health strip | `nl status`'s doctor header / `od_harness_health` |
| 5 | What's it costing | costs strip | `nl costs` / `od_costs` |
| 6 | Why did X happen (on demand) | why-drawer | `nl why <session>` / `od_why` |
| — | Backlog health | backlog strip | `nl backlog` / `od_backlog_health` |

Every pane's `derived_at` timestamp, `rc`, and `stderr_tail` are carried
straight from the CLI invocation the server made (`server/derive-cache.js`)
— a failed derivation renders a named ERROR state with the exact failing
command line, never a blank pane (see the acceptance scenarios below).

## Layout

| Path | Contents |
|---|---|
| `server/server.js` | Node HTTP server: static asset serving, the six `/api/pane/*` endpoints, `/api/reconciler`, `/api/refresh`, SSE push, the KEPT docs browser (`/api/docs`, `/api/doc`, `/api/doc/open`). No write endpoint — `POST /api/event` is RETIRED. |
| `server/derive-cache.js` | The server-side derived-JSON cache: shells `nl <sub> --json` (NL_BIN overridable), batch-refreshes every 30s, keeps last-known-good data alongside the latest rc/stderr for honest error rendering. |
| `server/reconciler.js` | The divergence reconciler (specs-o §O.4 deliverable 3): compares any REMAINING legacy tree-state session/branch claims against derived truth and flags mismatches — comparison-only, never a data source for a pane. |
| `web/` | The six-question front end (`index.html`, `app.js`, `app.css`). `app.js` polls the pane endpoints and renders; ONE link-resolver component (`resolveLink`) backs every pane's links. |
| `state/` | The (mostly legacy) event-sourced state library. Still used ONLY by `reconciler.js`'s comparison read while any tree-state consumer remains elsewhere in the harness; no longer the cockpit's data source. |
| `scripts/` | Launcher/autostart PowerShell scripts. The Node state-population scripts here (`add-pending-items.js`, `backfill-from-sessions.js`, etc.) targeted the retired write path and are no longer relevant to this app's day-to-day operation. |
| `config/` | Runtime configuration (topology/project-root mapping) — still used by the docs browser. |
| `attic/` | Retired pre-O.4 test files, kept per salvage-before-reset. See `attic/README.md`. |

## Running it

```bash
cd neural-lace/workstreams-ui
node server/server.js          # starts on http://127.0.0.1:7733 by default (CTREE_PORT overrides)
                                # NL_BIN overrides the `nl` CLI path (tests point this at a fixture stub)
```

Or, on Windows, the one-click path:

```powershell
neural-lace/workstreams-ui/scripts/launch-gui.ps1   # starts the server (if not already up) and opens the browser
```

`scripts/register-autostart.ps1` registers a scheduled task that starts the
server (no browser) at logon (per the runbook's wrapper-cmd registration
pattern — see `docs/runbooks/session-resumer.md` §Registration pattern).

## Self-tests

```bash
node server/server.selftest.js   # server wiring: pane endpoints, error-state rendering, reconciler
node web/cockpit.selftest.js     # DOM-free structural self-test of the six-question layout
```

## Where the enforcement side lives

The legacy Claude Code hook wiring that wrote to and gated the OLD
event-sourced tree (`workstreams-emit.sh`, `workstreams-state-gate.sh`,
`workstreams-stop-writer.sh`) is documented in `adapters/claude-code/
manifest.json` and `adapters/claude-code/doctrine/workstreams-state.md`.
NL Observability Program Wave O, task O.4 retires the two gates whose ONLY
protected consumer was this UI's old tree read (`workstreams-state-gate.sh`,
`workstreams-stop-gate.sh` — the latter already attic'd at D.5) once this
cockpit stops reading `tree-state.json` as truth — see the retirement
fragments under `adapters/claude-code/tests/fixtures/wave-o/O.4/` for the
exact `template-wiring.md` / `manifest-amendments.md` diffs the orchestrator
applies. `workstreams-emit.sh`'s spawn/stop paths are KEPT as ledger
emitters (O.1) — the signal ledger, not the tree, is the spine going
forward.
