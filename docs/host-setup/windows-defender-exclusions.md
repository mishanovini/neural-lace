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

The setup script adds three folder exclusions and four process exclusions.

### Folder exclusions (recursive)

| Path | What it covers |
|---|---|
| `%USERPROFILE%\claude-projects` | All Claude-driven repos: feature branches, worktrees, `node_modules`, `.next` build output, `.cache`, build artifacts. The single biggest source of file churn. |
| `%USERPROFILE%\.claude` | Harness state, hooks, agents, JSONL transcripts, cache, file-history, backups. Updated on every tool call. |
| `%APPDATA%\Claude` | Cowork session storage (Chromium-style: Cache, Code Cache, IndexedDB, Session Storage, Network, GPUCache). High I/O during active sessions. |

Defender folder exclusions are recursive by default — excluding `~/claude-projects` automatically covers every subdirectory, every worktree, every `node_modules` tree, every build artifact.

### Process exclusions

| Process | Why |
|---|---|
| `bash.exe` | Git Bash is the harness's primary subprocess. Every hook, every script, every `Bash` tool call spawns it. |
| `node.exe` | Backs `npm install`, `tsc`, dev servers, test runners, audit scripts. High file-open rate. |
| `git.exe` | Frequent staging, diff, status, log, worktree-add/remove calls. |
| `claude.exe` | The Claude Code CLI itself — its own state/transcript writes. |

Process exclusions match by executable name only (no path), so they apply wherever the process runs from. A file written by `bash.exe` to `%TEMP%` is skipped even though `%TEMP%` is not in the folder list.

### Why both?

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
# List all current folder exclusions:
Get-MpPreference | Select-Object -ExpandProperty ExclusionPath

# List all current process exclusions:
Get-MpPreference | Select-Object -ExpandProperty ExclusionProcess
```

Expected paths after first successful run:

```
C:\Users\<you>\claude-projects
C:\Users\<you>\.claude
C:\Users\<you>\AppData\Roaming\Claude
```

Expected processes:

```
bash.exe
node.exe
git.exe
claude.exe
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
@(
    "$env:USERPROFILE\claude-projects",
    "$env:USERPROFILE\.claude",
    "$env:APPDATA\Claude"
) | ForEach-Object { Remove-MpPreference -ExclusionPath $_ }

@("bash.exe","node.exe","git.exe","claude.exe") |
    ForEach-Object { Remove-MpPreference -ExclusionProcess $_ }
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
