# Windows Defender exclusions for Claude Code

**Audience:** Windows users running Claude Code (and/or the Neural Lace harness) who are seeing high background CPU usage from `Antimalware Service Executable` while developing.

**One-line summary:** Defender real-time-scans every file Claude Code touches. Adding the dev paths and processes to its exclusion list eliminates the scan overhead.

---

## Why this matters

Claude Code's normal operation produces a lot of file I/O:

- **Worktree creation and teardown.** Every parallel-builder dispatch creates a fresh git worktree (often with its own `node_modules`); Defender scans each new file as it's written.
- **`node_modules` churn.** `npm install` writes tens of thousands of small files. Defender scans every one of them, every time, even on a cached install.
- **Bash subprocess output.** `bash.exe` spawning, redirected stdio, tempfiles in `%TEMP%`, pipe buffers — each touches the disk.
- **JSONL transcript writes.** Claude Code records every tool call to a JSONL transcript in `%APPDATA%\Claude`. Each write is scanned.
- **Harness state writes.** `~/.claude/state/*` is updated frequently (audit logs, propagation telemetry, finding-marker files).
- **Cowork session storage.** `%APPDATA%\Claude` carries Chromium-style cache and storage directories that get touched every interaction.

The cumulative effect: `Antimalware Service Executable` regularly runs at 15-25% CPU even when the laptop appears idle. On battery, this is noticeable thermal and runtime cost.

Adding the relevant paths and processes to Defender's exclusion list means Defender skips real-time scanning for those specific surfaces. Files written into them are NOT scanned (see the [security tradeoff](#security-tradeoff) section below for what this means).

## What gets excluded

The setup script adds exclusions in two tiers — **CORE** (Claude Code's own paths and processes) and **ADDITIONAL** (broader dev-tooling caches and processes that the parent folder exclusions miss).

### CORE — folder exclusions (recursive)

| Path | What it covers |
|---|---|
| `%USERPROFILE%\claude-projects` | All Claude-driven repos: feature branches, worktrees, `node_modules`, `.next` build output, `.cache`, build artifacts. The single biggest source of file churn. |
| `%USERPROFILE%\.claude` | Harness state, hooks, agents, JSONL transcripts, cache, file-history, backups. Updated on every tool call. |
| `%APPDATA%\Claude` | Cowork session storage (Chromium-style: Cache, Code Cache, IndexedDB, Session Storage, Network, GPUCache). High I/O during active sessions. |

Defender folder exclusions are recursive by default — excluding `~/claude-projects` automatically covers every subdirectory, every worktree, every `node_modules` tree, every build artifact.

### CORE — process exclusions

| Process | Why |
|---|---|
| `bash.exe` | Git Bash is the harness's primary subprocess. Every hook, every script, every `Bash` tool call spawns it. |
| `node.exe` | Backs `npm install`, `tsc`, dev servers, test runners, audit scripts. High file-open rate. |
| `git.exe` | Frequent staging, diff, status, log, worktree-add/remove calls. |
| `claude.exe` | The Claude Code CLI itself — its own state/transcript writes. |

Process exclusions match by executable name only (no path), so they apply wherever the process runs from. A file written by `bash.exe` to `%TEMP%` is skipped even though `%TEMP%` is not in the folder list.

### ADDITIONAL — folder exclusions

These catch dev-tooling file churn that the parent-folder exclusions miss — package manager caches (which live OUTSIDE any specific repo), language server state, IDE program files. Per-user caches in particular are scanned aggressively because they sit under `%USERPROFILE%` and don't get the per-repo exemption that build folders inside `claude-projects` do.

| Path | What it covers |
|---|---|
| `%USERPROFILE%\.cache` | Generic dev tool cache used by Yarn classic and several other CLIs. |
| `%USERPROFILE%\.npm` | npm package cache (per-user). Touched on every `npm install` even when packages are already cached. |
| `%LOCALAPPDATA%\npm-cache` | Windows alternate npm cache location (newer npm versions). |
| `%APPDATA%\npm` | Global npm install dir and `npm.cmd` / `npx.cmd` shims. Read on every CLI invocation. |
| `%LOCALAPPDATA%\Yarn` | Yarn (modern) cache. |
| `%LOCALAPPDATA%\pnpm` | pnpm cache + content-addressed package store. pnpm's deduplication writes thousands of hardlinks. |
| `%LOCALAPPDATA%\Microsoft\TypeScript` | TypeScript language server cache. The TS server reads + writes constantly during dev. |
| `%USERPROFILE%\.vscode\extensions` | VS Code extensions (TS, ESLint, Prettier, etc.). Heavy file readers loaded on every editor start. |
| `%LOCALAPPDATA%\Programs\Microsoft VS Code` | VS Code program files. Read heavily on startup. |
| `%USERPROFILE%\.gitconfig` | The git config FILE (not a folder). Read on every git invocation — and git invocations are constant in a Claude Code session. |

### ADDITIONAL — process exclusions

| Process | Why |
|---|---|
| `Code.exe` | VS Code main process. |
| `tsserver.exe` | TypeScript language server. Watches every `.ts` / `.tsx` file in scope. Among the biggest single file-touch offenders during dev. |
| `tsc.exe` | TypeScript compiler. |
| `eslint.exe` | ESLint runner. |
| `prisma.exe` | Prisma ORM CLI (schema generation, migrations). |
| `next.exe` | Next.js dev server / build. |
| `python.exe` / `python3.exe` | Python interpreter (project scripts, tooling). Both names covered. |
| `cmd.exe` | Windows command shell. Frequently spawned as a subprocess by other tools. |
| `powershell.exe` | Windows PowerShell. Same — subprocess spawning. |
| `pwsh.exe` | PowerShell 7+ cross-platform. |

Some of these processes may not be installed on every machine (e.g., `prisma.exe`, `pwsh.exe`). Defender accepts process-name exclusions regardless of whether the executable currently exists — the exclusion applies whenever the process IS spawned, including after a later install.

### Why both folders AND processes?

Folder exclusions cover the static dev surface (known paths). Process exclusions cover the dynamic surface (tempfiles, pipe buffers, transient writes elsewhere). Together they catch both "bash reads this directory" and "bash creates a tempfile somewhere unexpected" — with neither alone, real-time scan overhead remains.

## How to run the script

```powershell
# From inside the neural-lace repo:
powershell -ExecutionPolicy Bypass -File adapters\claude-code\scripts\host-setup\setup-defender-exclusions.ps1
```

The script:

1. **Self-elevates** via UAC if you're not already running as admin. (`Add-MpPreference` requires admin; the UAC prompt is the real human-in-the-loop confirmation that you're authorizing the change.)
2. **Reads existing exclusions** with `Get-MpPreference` and skips anything already present.
3. **Skips paths that don't exist** on this machine (e.g., if `%APPDATA%\Claude` doesn't exist because Cowork was never launched, the script reports `[SKIP]` rather than failing).
4. **Reports** what was added, what was already present, and what was skipped.

### Preview without modifying state

```powershell
powershell -ExecutionPolicy Bypass -File adapters\claude-code\scripts\host-setup\setup-defender-exclusions.ps1 -DryRun
```

`-DryRun` skips elevation (read-only operations don't need admin) and reports `[WOULD ADD]` for everything that would be added. Useful for auditing before committing to the change.

### Re-running

The script is idempotent. Running it twice produces identical state — the second run reports `[EXISTS]` for everything. Safe to re-run any time you suspect drift (e.g., after a Defender policy update or a Windows feature reinstall that wiped custom exclusions).

## How to verify exclusions are in place

```powershell
# List all current folder exclusions (sorted):
Get-MpPreference | Select-Object -ExpandProperty ExclusionPath | Sort-Object

# List all current process exclusions (sorted):
Get-MpPreference | Select-Object -ExpandProperty ExclusionProcess | Sort-Object
```

Expected paths after first successful run (folder exclusions, sorted; paths that don't exist on your machine will be reported `[SKIP]` and not added):

```
C:\Users\<you>\.cache
C:\Users\<you>\.claude
C:\Users\<you>\.gitconfig
C:\Users\<you>\.npm
C:\Users\<you>\.vscode\extensions
C:\Users\<you>\AppData\Local\Microsoft\TypeScript
C:\Users\<you>\AppData\Local\npm-cache
C:\Users\<you>\AppData\Local\pnpm
C:\Users\<you>\AppData\Local\Programs\Microsoft VS Code
C:\Users\<you>\AppData\Local\Yarn
C:\Users\<you>\AppData\Roaming\Claude
C:\Users\<you>\AppData\Roaming\npm
C:\Users\<you>\claude-projects
```

Expected processes (sorted):

```
bash.exe
claude.exe
cmd.exe
Code.exe
eslint.exe
git.exe
next.exe
node.exe
powershell.exe
prisma.exe
pwsh.exe
python.exe
python3.exe
tsc.exe
tsserver.exe
```

If any are missing, re-run the script — it will add the missing ones and leave the rest alone.

## How to remove exclusions

Remove a single folder exclusion:

```powershell
Remove-MpPreference -ExclusionPath "$env:USERPROFILE\claude-projects"
```

Remove a single process exclusion:

```powershell
Remove-MpPreference -ExclusionProcess "bash.exe"
```

Remove every exclusion this script added at once:

```powershell
# Folders (CORE + ADDITIONAL):
@(
    # CORE
    "$env:USERPROFILE\claude-projects",
    "$env:USERPROFILE\.claude",
    "$env:APPDATA\Claude",
    # ADDITIONAL
    "$env:USERPROFILE\.cache",
    "$env:USERPROFILE\.npm",
    "$env:LOCALAPPDATA\npm-cache",
    "$env:APPDATA\npm",
    "$env:LOCALAPPDATA\Yarn",
    "$env:LOCALAPPDATA\pnpm",
    "$env:LOCALAPPDATA\Microsoft\TypeScript",
    "$env:USERPROFILE\.vscode\extensions",
    "$env:LOCALAPPDATA\Programs\Microsoft VS Code",
    "$env:USERPROFILE\.gitconfig"
) | ForEach-Object { Remove-MpPreference -ExclusionPath $_ -ErrorAction SilentlyContinue }

# Processes (CORE + ADDITIONAL):
@(
    # CORE
    "bash.exe","node.exe","git.exe","claude.exe",
    # ADDITIONAL
    "Code.exe","tsserver.exe","tsc.exe","eslint.exe","prisma.exe",
    "next.exe","python.exe","python3.exe","cmd.exe","powershell.exe","pwsh.exe"
) | ForEach-Object { Remove-MpPreference -ExclusionProcess $_ -ErrorAction SilentlyContinue }
```

These commands also require admin. They are non-destructive — they only remove the named exclusion, leaving any other custom exclusions you set up separately intact.

## Security tradeoff

Excluding a path or process from Defender's real-time protection means **files written into those paths, or by those processes, are not scanned for malware as they hit the disk**. This is a standard dev-machine optimization, but it is worth understanding the implications:

- **Dependencies installed via `npm install` are not scanned.** A malicious npm package's post-install script writing a payload into `node_modules` would not be flagged in real time. Mitigation: be deliberate about what packages you install; use `npm audit`; the broader supply-chain story is handled at install time (lockfiles, package signing), not at file-write time.
- **Cloned repos are not scanned.** A `git clone` of a hostile repo into `~/claude-projects` would not have its files real-time-scanned. Mitigation: only clone repos from sources you trust.
- **Files written by `bash.exe` or `node.exe` anywhere on disk are not scanned.** This widens the blast radius beyond the named folders. Mitigation: don't pipe untrusted content through bash/node tooling and expect Defender to catch it.

**What still protects you:**

- Defender's **full scans** (the periodic background ones) still scan excluded paths. The exclusions only affect real-time protection.
- Defender's **download/email scans** at other ingestion points still fire.
- The Neural Lace harness's own **pre-commit and pre-push credential scanners** still run on every commit and push, catching credential leaks in code regardless of Defender state.
- Defender's **process behavior analysis** (anti-ransomware, exploit prevention) is separate from the exclusion list — those protections continue.
- Files OUTSIDE the excluded paths, written by processes NOT on the exclusion list, are still scanned normally.

This tradeoff is standard practice for developers running JavaScript/Node tooling on Windows. Microsoft documents the approach for dev scenarios in their own guidance for [excluding Windows Defender Antivirus](https://learn.microsoft.com/en-us/microsoft-365/security/defender-endpoint/configure-extension-file-exclusions-microsoft-defender-antivirus). If you regularly install untrusted packages or clone unknown repos, you may want to leave the exclusions out and tolerate the CPU cost.

## Granular `node_modules` exclusions (optional)

The folder exclusion for `~/claude-projects` is **recursive** and already covers every `node_modules` directory under it. You do NOT need to add per-`node_modules` exclusions separately.

The script includes a commented-out `Add-NodeModulesExclusions` function that enumerates every `node_modules` directory under `~/claude-projects` at runtime and excludes each individually. **This is only useful if you later remove the parent-folder exclusion** (e.g., you decide you want Defender scanning your dev sources but not the dependency trees specifically). Activate it by uncommenting the `Add-NodeModulesExclusions` call at the end of the script and re-running.

The function uses `Get-ChildItem -Recurse -Force -Directory -Filter node_modules`, so it picks up `node_modules` directories anywhere under `~/claude-projects`, including:

- `~/claude-projects/<repo>/node_modules` (the typical one)
- `~/claude-projects/<repo>/.next/node_modules` (sub-`node_modules` in Next.js builds)
- `~/claude-projects/<org>/<repo>/.claude/worktrees/<branch>/node_modules` (worktree-local installs)
- Any other transitive `node_modules` directory created by package managers

Because the function enumerates at runtime, it stays accurate as projects come and go. There is no stale hardcoded list to maintain.

## Related references

- Microsoft docs: [Configure custom exclusions for Microsoft Defender Antivirus](https://learn.microsoft.com/en-us/microsoft-365/security/defender-endpoint/configure-exclusions-microsoft-defender-antivirus)
- Microsoft docs: [Common mistakes to avoid when defining exclusions](https://learn.microsoft.com/en-us/microsoft-365/security/defender-endpoint/common-exclusion-mistakes-microsoft-defender-antivirus)
- The script itself: [`adapters/claude-code/scripts/host-setup/setup-defender-exclusions.ps1`](../../adapters/claude-code/scripts/host-setup/setup-defender-exclusions.ps1)
- Harness setup guide: [`SETUP.md`](../../SETUP.md) — points at this doc under "Optional: host performance tuning"
