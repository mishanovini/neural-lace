# Windows Machine Performance Setup — one-time cleanup for a new Claude Code machine

Run this once per Windows machine running Claude Code / Claude Desktop. Ordered by impact.
Everything here is reversible. Admin PowerShell required for steps 2 and 3; steps 1 and 4-5 are
normal PowerShell.

## 1. Disable the Cowork VM (if you don't use Cowork)

The Cowork VM idles at ~1.8 GB RAM + ~10 GB disk, and its `CoworkVMService` locks the Claude
Desktop MSIX package while running — causing "Another program is currently using this file" on
relaunch, clearable only by reboot. There is no official off-switch (tracked upstream:
[anthropics/claude-code#57371](https://github.com/anthropics/claude-code/issues/57371)) — use both
of the following together; the config toggle alone does not survive a reboot.

**1a. App-level toggle** (normal PowerShell — stops the VM from being requested):
```powershell
$cfg = "$env:APPDATA\Claude\claude_desktop_config.json"
Copy-Item $cfg "$cfg.bak" -Force
$raw = Get-Content $cfg -Raw
if ($raw -notmatch 'secureVmFeaturesEnabled') {
  $new = $raw -replace '("preferences"\s*:\s*\{)', "`$1`r`n    `"secureVmFeaturesEnabled`": false,"
  $null = $new | ConvertFrom-Json   # validates before writing — aborts silently on bad JSON
  [System.IO.File]::WriteAllText($cfg, $new, (New-Object System.Text.UTF8Encoding($false)))
  "toggle set — fully quit and relaunch Claude Desktop to apply"
} else { "already set" }
```

**1b. Boot-time service stop** (admin PowerShell — `Set-Service`/`sc config` will fail with Access
Denied on this packaged service; `Stop-Service` works, so a scheduled task does the job):
```powershell
$act = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument '-NoProfile -WindowStyle Hidden -Command "Stop-Service CoworkVMService -Force -ErrorAction SilentlyContinue"'
$trg = New-ScheduledTaskTrigger -AtStartup
$prc = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -RunLevel Highest
Register-ScheduledTask -TaskName 'Kill-Cowork-OnBoot' -Action $act -Trigger $trg -Principal $prc -Force
```

**Verify:** `Get-Service CoworkVMService` should show `Stopped` after a reboot.

## 2. Windows Defender exclusions (the biggest CPU win)

Windows has no `fork()` — every git/bash/node subprocess Claude Code spawns is a full
`CreateProcess` (~190 ms measured), and Defender real-time protection scans each one. On a machine
running Claude Code this can pin Antimalware Service Executable at 30%+ CPU. Excluding the trusted
dev working set removes that scan cost. **Tradeoff:** only exclude paths/processes you trust — this
reduces real-time scanning there.

```powershell
Add-MpPreference -ExclusionPath "C:\Program Files\Git"
Add-MpPreference -ExclusionPath "$env:USERPROFILE\.claude"
Add-MpPreference -ExclusionPath "$env:USERPROFILE\claude-projects"
Add-MpPreference -ExclusionPath "C:\Program Files\nodejs"
Add-MpPreference -ExclusionProcess "bash.exe"
Add-MpPreference -ExclusionProcess "node.exe"
Add-MpPreference -ExclusionProcess "git.exe"
Get-MpPreference | Select-Object -ExpandProperty ExclusionPath   # verify
```

## 3. Fix a split Desktop (OneDrive Known-Folder-Move)

If OneDrive has taken over your Desktop, `C:\Users\<you>\Desktop` and
`C:\Users\<you>\OneDrive\Desktop` can silently become two different folders — anything that
hardcodes `%USERPROFILE%\Desktop` writes to the wrong one and "vanishes."

**Check which is canonical:**
```powershell
[Environment]::GetFolderPath('Desktop')   # what Windows actually uses
```
If that returns the OneDrive path and `C:\Users\<you>\Desktop` still exists as a real folder,
reconcile then merge:
```powershell
$real = "$env:USERPROFILE\Desktop"; $od = [Environment]::GetFolderPath('Desktop')
# reconcile: move anything in $real not already in $od
$odNames = (Get-ChildItem $od -Force -EA SilentlyContinue).Name
Get-ChildItem $real -Force -EA SilentlyContinue | Where-Object { $_.Name -notin $odNames } |
  ForEach-Object { Move-Item $_.FullName -Destination $od -Force }
# verify empty, then merge permanently
if ((Get-ChildItem $real -Force -EA SilentlyContinue | Measure-Object).Count -eq 0) {
  Remove-Item $real -Force
  New-Item -ItemType Junction -Path $real -Target $od
  "merged — both paths are now the same folder"
} else { "NOT empty after reconcile — inspect manually before deleting" }
```

## 4. One-time process check

```powershell
Get-Process | Group-Object ProcessName |
  Select-Object Name, Count, @{N='RAM_MB';E={[math]::Round((($_.Group|Measure-Object WorkingSet64 -Sum).Sum)/1MB)}} |
  Sort-Object RAM_MB -Descending | Select-Object -First 15 | Format-Table -AutoSize
```
What to look for:
- **Antimalware Service Executable high (>15%)** → step 2 not applied yet, or exclusions too narrow.
- **Many `bash.exe` (>30-40) with no active Claude session doing heavy work** → orphaned processes;
  see the reaper below. If it recurs constantly, check whether many Claude Code sessions/worktrees
  are open at once — that's expected load, not a bug, but it adds up.
- **`CoworkVMService`/`vmcompute`/`hns` running and you don't use Cowork** → step 1 not applied yet.

## 5. Safe orphan-process reaper (as-needed, never touches active sessions)

Kills only `bash.exe` whose parent process is already dead or whose command line is empty (stuck
shells) — active session processes have a live parent and are never touched:
```powershell
$live={};Get-Process|%{$live[[int]$_.Id]=$true}
Get-CimInstance Win32_Process -Filter "Name='bash.exe'" | Where-Object {
  ((-not $live.ContainsKey([int]$_.ParentProcessId)) -or [string]::IsNullOrWhiteSpace($_.CommandLine)) `
  -and $_.CreationDate -and (((Get-Date)-$_.CreationDate).TotalSeconds -gt 30)
} | ForEach-Object { Stop-Process -Id ([int]$_.ProcessId) -Force -EA SilentlyContinue }
```

## Notes
- Steps 1-3 are one-time per machine. Step 4 is a quick sanity check any time things feel slow.
  Step 5 is safe to run any time you want immediate relief.
- The Claude Code **harness** fixes (SessionStart single-flight lock, self-test-sweep gate, dispatch
  governor) are NOT per-machine — they live in this repo and apply automatically via git pull +
  the harness's own auto-install, on every machine that syncs from the canonical remote.
- Source session / full context: [docs/lessons/2026-07-13-agent-efficiency-bottlenecks-process-spawn-and-hook-latency.md](../lessons/2026-07-13-agent-efficiency-bottlenecks-process-spawn-and-hook-latency.md), [docs/lessons/2026-07-20-efficiency-recurrence-live-diagnosis.md](../lessons/2026-07-20-efficiency-recurrence-live-diagnosis.md).
