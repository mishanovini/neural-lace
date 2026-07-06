# workstreams-ui

<!-- last-verified: 2026-07-05 (doctor-checked) -->

A localhost passive-observer GUI for Neural Lace's cross-session workstream
state (ADR-031 r7 / ADR-032 §8): a three-pane view (tree / actions-list /
backlog) over the same append-only, schema-versioned `tree-state.json` the
Claude Code hooks write to as they work. This app never spawns, steers, or
becomes the chat — it is a read/observe surface plus the return channel the
hooks poll for operator responses (annotations, deferrals, backlog adds).

## Layout

| Path | Contents |
|---|---|
| `server/server.js` | Minimal Node HTTP server: static asset serving, state read, SSE push. No framework dependency beyond `zod` (schema validation) and Node's built-in `http`. |
| `web/` | Static three-pane front end (`index.html`, `app.js`, `app.css`) consuming the server's state + SSE endpoints. |
| `state/` | The frozen state-library facade (`state.js` `appendEvent`/`readState`), the Zod schema (`schema.js`, `decision-context-schema.js`), the reconciler, and backfill/migration one-off scripts. Hooks and this app both write ONLY through this facade — never hand-written state. |
| `scripts/` | Launcher/autostart PowerShell scripts (`launch-gui.ps1`, `install-shortcuts.ps1`, `register-autostart.ps1`) + Node state-population scripts (`add-pending-items.js`, `backfill-from-sessions.js`, `surface-pending-asks.js`, `work-in-motion-sweep.js`). See `scripts/README.md` for the full breakdown — it is the more detailed, actively-maintained sibling of this file for that directory. |
| `config/` | Runtime configuration (topology/project-root mapping). |
| `docs/` | Module-specific docs (e.g. `docs/ux-audit-2026-05-23.md`). |

## Running it

```bash
cd neural-lace/workstreams-ui
node server/server.js          # starts on http://127.0.0.1:7733 by default (CTREE_PORT overrides)
```

Or, on Windows, the one-click path:

```powershell
neural-lace/workstreams-ui/scripts/launch-gui.ps1   # starts the server (if not already up) and opens the browser
```

`scripts/register-autostart.ps1` registers a scheduled task that starts the
server (no browser) at logon, so the GUI is warm before the first session of
the day.

## Where the enforcement side lives

The Claude Code hook wiring that writes to and gates this app's state file
lives in `adapters/claude-code/hooks/` (see the `workstreams-emitters`,
`workstreams-spawn-gate`, and `workstreams-stop-writer` entries in
`adapters/claude-code/manifest.json`, and
[`docs/harness-architecture.md`](../../docs/harness-architecture.md) for the
generated inventory). The Pattern-class rule documenting the semantic
(unenforceable) half of "write a true tree" is
`adapters/claude-code/doctrine/workstreams-state.md`.

## Cross-references

- ADR-031 r7 (`docs/decisions/031-conversation-tree-ui-architecture.md`) — architecture + enforcement design + plan-safety pins.
- ADR-032 §8 r2.1 (`docs/decisions/032-conversation-tree-state-schema.md`) — the frozen state schema + attestation primitive.
- `docs/harness-architecture-history.md` "Conversation-Tree UI Module" section — the original build narrative (Phases 0–E).
