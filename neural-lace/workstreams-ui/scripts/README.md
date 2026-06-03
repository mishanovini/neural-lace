# Conversation Tree UI — scripts

Two families of scripts live here:

1. **Launcher / autostart** (PowerShell) — one-click launch for the GUI plus an
   optional logon autostart so the server is always ready. No terminal required.
2. **State population** (Node) — populate the tree-state file the GUI reads, by
   replaying real Claude Code session history and today's pending items through
   the legitimate `appendEvent` state primitive.

## Launcher / autostart scripts

All three launcher scripts derive their paths at runtime (`$PSScriptRoot`,
`$env:USERPROFILE`, Windows special folders). **Nothing is hardcoded to a
specific machine or user** — the scripts are portable and contain no absolute
paths, which is why they are safe to commit to the harness repo.

| Script | What it does |
|---|---|
| `launch-gui.ps1` | Starts the server (hidden, detached) if port 7733 is free, waits for it, opens the browser. Re-running while up just opens the browser. |
| `install-shortcuts.ps1` | Creates "Conversation Tree" `.lnk` shortcuts on the Desktop and in the Start Menu that run `launch-gui.ps1`. |
| `register-autostart.ps1` | Registers a scheduled task that starts the server (no browser) at logon. |

## State-population scripts (Node)

These two scripts are what currently keep the tree populated. Both write only
through the frozen state-library facade (`../state/state.js` `appendEvent`) —
never hand-written state — and both are **idempotent**: every emitted event has
a deterministic `event_id`, so re-running a script is a per-file no-op (the
state library dedupes). Run them from this `scripts/` directory with `node`.

| Script | What it does | When to run |
|---|---|---|
| `backfill-from-sessions.js` | One-shot backfill of Claude Code / Cowork session history into the tree. Reads `~/.claude/projects/<encoded>/<session>.jsonl` (+ sibling `subagents/agent-*.jsonl`), extracts only what the JSONL verifiably contains (session id, first task, timestamps, Stop fires, cwd), and replays the equivalent `branch-opened` / `concluded` events. Honest by construction: titles come from the Dispatch-injected task body or the first real user message, never invented; sessions group by project (cross-session parentage is not recoverable from JSONL alone). | After a fresh install, or whenever you want the GUI to reflect recent session history. Safe to re-run. |
| `add-pending-items.js` | Appends a curated set of pending items (decisions / questions / actions) and harness-gap backlog entries to the tree, anchored to the matching project nodes (cross-cutting items attach to the day node; orphan gaps go to the backlog pane). The item list is **a hand-maintained snapshot** baked into the script — edit the `DECISIONS` / `ACTIONS` / `QUESTIONS` / `BACKLOG` arrays to change what it emits. | When you want today's known pending items surfaced in the GUI's "Waiting on you" / "Backlog" panes. Edit the arrays first, then run. |

```powershell
# Backfill today's sessions (or --since YYYY-MM-DD for a wider window)
node .\backfill-from-sessions.js
node .\backfill-from-sessions.js --since 2026-05-19
node .\backfill-from-sessions.js --dry-run            # preview, no writes

# Append the curated pending items
node .\add-pending-items.js
node .\add-pending-items.js --dry-run                 # preview, no writes
```

Both accept `--sink <path>` to target a tree-state file other than the default
`../state/tree-state.json`.

> **Note on `add-pending-items.js`:** it is a one-shot snapshot tool, not a live
> feed — the items it emits are hardcoded in the script. The live, automatic
> path for surfacing pending items from normal assistant output is the
> `conversation-tree-extract-pending.sh` Stop hook (see the harness `hooks/`
> directory); this script remains for manual / curated population.

## Regression test (browser e2e)

`regression.e2e.js` is a **real-headless-browser** regression suite that locks
the 8 GUI bugs fixed on 2026-06-02
(`docs/reviews/2026-06-02-workstreams-gui-8-bug-regression.md`). The DOM-free
node selftests (`../state/selftest.js`, `../web/responsive.selftest.js`) cannot
catch CSS footguns or DOM-wiring regressions — e.g. the `[hidden]` override that
squeezed the detail card into a 67px bottom strip, or the selection that never
highlighted the clicked tree row. This suite drives an actual browser to assert
each fix.

`puppeteer` is **dev-only — NOT a shipped dependency** (keeps the GUI's runtime
deps to just `zod`). Install it on demand:

```bash
# 1. start the server
node server/server.js
# 2. install puppeteer just for testing (dev-only; safe to delete after)
npm i -D puppeteer
# 3. run the suite (default WS_URL=http://127.0.0.1:7733/)
node scripts/regression.e2e.js
```

Exit 0 = all 9 checks pass (8 bugs + a no-page-errors guard); exit 1 = a
regression; exit 2 = harness error (e.g. puppeteer missing). Each assertion
prints its measured evidence (`cardH`, `selTreeRows`, badge counts, etc.).

## Quick start

From this `scripts/` directory, in PowerShell:

```powershell
# 1. Create the desktop + Start Menu shortcuts
powershell -ExecutionPolicy Bypass -File .\install-shortcuts.ps1

# 2. (optional) Make the server auto-start at every logon
powershell -ExecutionPolicy Bypass -File .\register-autostart.ps1
```

After step 1, double-click the **Conversation Tree** icon on the Desktop.
The server starts in the background if needed and the GUI opens in your
default browser at `http://127.0.0.1:7733`.

## launch-gui.ps1

```
powershell -ExecutionPolicy Bypass -File .\launch-gui.ps1
powershell -ExecutionPolicy Bypass -File .\launch-gui.ps1 -NoBrowser   # start server only
```

Behavior:

- **Port 7733 in use** → assumes the server is already running, skips the
  start, just opens the browser.
- **Port free** → starts `node server\server.js` from the
  `conversation-tree-ui` directory as a **detached, window-less** process
  (survives after the script exits), polls the port for up to 5 seconds,
  then opens the browser.
- **`node` not on PATH** → logs a clear error and shows a desktop notification
  (BurntToast if installed, otherwise a message box) telling you to install
  Node.js. The shortcut does not silently do nothing.
- **`-NoBrowser`** → start the server if needed but do not open the browser
  (used by the autostart task).

Log file (created automatically):

```
%USERPROFILE%\.claude\logs\conv-tree-launcher.log
```

Check this file first if a launch ever misbehaves — every run appends a
timestamped trace.

## install-shortcuts.ps1

Creates two shortcuts named **Conversation Tree**:

- Desktop: `[Desktop]\Conversation Tree.lnk`
- Start Menu: `[Start Menu Programs]\Conversation Tree.lnk`

Each runs:

```
powershell.exe -ExecutionPolicy Bypass -NoProfile -WindowStyle Hidden -File "<...>\launch-gui.ps1"
```

The shortcut window style is "minimized" as defence-in-depth; the launcher
also hides itself, so no console flashes.

Remove the shortcuts:

```powershell
powershell -ExecutionPolicy Bypass -File .\install-shortcuts.ps1 -Remove
```

### Why the `.lnk` files are not committed

`.lnk` files embed absolute paths that are specific to this machine and user
account (the Desktop path, the launcher path, the powershell.exe path). They
are intentionally **not** committed to the repo. Only the script that
*creates* them (`install-shortcuts.ps1`) is committed. After cloning/pulling
the repo on any machine, run `install-shortcuts.ps1` once to (re)generate the
shortcuts for that machine.

### Custom icon

Windows ships no standard "tree" icon, so the shortcut uses the default
PowerShell icon. To use a custom icon, drop a `conv-tree.ico` next to the
scripts and uncomment the `$sc.IconLocation` line in `install-shortcuts.ps1`,
then re-run it.

## register-autostart.ps1

Registers a scheduled task **`ConversationTreeUI-AutoStart`** that starts the
server at every logon of the current user, with **no browser**.

```powershell
powershell -ExecutionPolicy Bypass -File .\register-autostart.ps1
powershell -ExecutionPolicy Bypass -File .\register-autostart.ps1 -RunNow      # register + start now to verify
powershell -ExecutionPolicy Bypass -File .\register-autostart.ps1 -Unregister  # remove the task
```

Task properties:

- **Trigger**: at logon of the current user.
- **Action**: `launch-gui.ps1 -NoBrowser` (see note below).
- **Run as**: current user, interactive, non-elevated.
- **Window**: hidden.
- **Multiple instances**: `IgnoreNew` — if you already started the server
  manually, the task will not disturb it.
- **On failure**: restart up to 3 times, 1 minute apart.
- **Time limit**: none (the server is long-running).

### Why the task runs the launcher (`-NoBrowser`) and not `node` directly

The intent of "run the server, not the launcher" is *no browser window at
logon*. `launch-gui.ps1 -NoBrowser` satisfies that exactly **and** reuses the
launcher's port-7733 guard, so a logon start and a later manual desktop-icon
launch can never double-bind the port. This keeps a single, verified
server-start code path instead of duplicating port-check + node-spawn logic
in two places that could drift apart.

### Verify it works without waiting for next logon

```powershell
powershell -ExecutionPolicy Bypass -File .\register-autostart.ps1 -RunNow
```

This registers the task and immediately triggers it once, printing
`LastTaskResult` (0 = success). You can also open **Task Scheduler**
(`taskschd.msc`) → Task Scheduler Library → `ConversationTreeUI-AutoStart`.

## Uninstall everything

```powershell
powershell -ExecutionPolicy Bypass -File .\install-shortcuts.ps1 -Remove
powershell -ExecutionPolicy Bypass -File .\register-autostart.ps1 -Unregister
```

This removes both shortcuts and the scheduled task. It does not touch the
log file or the repo.

## Troubleshooting

- **Nothing happens when I double-click the icon** — open
  `%USERPROFILE%\.claude\logs\conv-tree-launcher.log`; the last lines say
  what happened. The most common cause is Node.js not on PATH.
- **Browser opens but page won't load** — the server may still be starting;
  refresh after a second. If it persists, check the log; the launcher waits
  up to 5 s for the port and logs if it timed out.
- **Port 7733 already used by something else** — the launcher assumes our
  server owns it and just opens the browser. If a different process holds
  7733, stop that process (the server port is fixed at 7733 unless you set
  the `CTREE_PORT` environment variable before the server starts).
- **Autostart task shows `LastTaskResult` non-zero** — run
  `launch-gui.ps1 -NoBrowser` by hand and read the log; the task runs the
  same code path, so the log explains the failure.
