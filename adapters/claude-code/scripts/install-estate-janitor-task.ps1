# install-estate-janitor-task.ps1
#
# Installs ONE Windows Scheduled Task, 'NL-EstateJanitor', that runs
# estate-janitor.sh followed by estate-brief.sh --write on a cadence —
# the Accountable Estate program's T1 slice (docs/plans/
# accountable-estate-program-2026-07.md): "new janitor scheduled task
# (deterministic bash) reducing existing truth... -> snapshot.json +
# rendered brief."
#
# Same registration pattern as install-coord-sync-task.ps1 (hidden-window
# wrapper via a shared run-hidden.vbs launcher, quoting-collapse-proof
# action, machine STATE wrapper dir never touched by install.sh) — see
# that file's own header for the full rationale; not re-derived here.
#
# SHIP-ONLY, PER TASK SCOPE (accountable-estate-program-2026-07.md T1
# dispatch): this installer is WRITTEN and self-test-covered (-WhatIf is
# exercised by the self-test, proving the wrapper content + registration
# shape without touching Task Scheduler) but Register-ScheduledTask is
# NEVER invoked by an agent session — registration is the operator's own
# action, run manually once they choose to. This mirrors this program's
# own observe-first rule (Program rule 4) applied to the INSTALLER
# itself, not just the mechanism it installs.
#
# Both estate-janitor.sh and estate-brief.sh are READ-ONLY (T1 scope —
# see estate-janitor.sh's own header: "NO mutations of any kind this
# slice"), so this task carries none of install-coord-sync-task.ps1's
# lock/reclaim concerns beyond simple no-overlap hygiene.
#
# Task name: NL-EstateJanitor
# Cadence:   every -IntervalSeconds (default 300s = 5min), repeating ~10 years.
# Output:    ~/.claude/state/estate/snapshot.json (estate-janitor.sh run)
#            ~/.claude/state/estate/brief.txt     (estate-brief.sh --write)
#            ~/.claude/state/estate/cron-YYYY-MM-DD.log (tick stdout/stderr)
#
# Run ONCE per machine as a normal (non-elevated) user, when the operator
# chooses to. Re-running is safe (idempotent — Set- if already present,
# Register- if not).
#
# Usage:
#   powershell -File adapters/claude-code/scripts/install-estate-janitor-task.ps1
#   powershell -File ... -RepoPath "$env:USERPROFILE\dev\<work-org>\neural-lace"
#   powershell -File ... -IntervalSeconds 300
#   powershell -File ... -WhatIf      # dry-run: prints wrapper contents +
#                                     # registration WITHOUT touching disk
#                                     # or Task Scheduler
#   powershell -File ... -Uninstall  # unregisters the task
#
# Verification after install (operator-run, not agent-run):
#   Get-ScheduledTask -TaskName 'NL-EstateJanitor'
#   Start-ScheduledTask -TaskName 'NL-EstateJanitor'   # one-shot test
#   schtasks /Query /TN NL-EstateJanitor /V | findstr "Last Result"  # 0 = healthy
#   Get-Content "$env:USERPROFILE\.claude\state\estate\brief.txt"

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$RepoPath = "$HOME\dev\<work-org>\neural-lace",
    [int]$IntervalSeconds = 300,
    [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'
$TaskName = 'NL-EstateJanitor'

if ($Uninstall) {
    if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
        if ($PSCmdlet.ShouldProcess($TaskName, 'Unregister scheduled task')) {
            Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
            Write-Host "Uninstalled scheduled task: $TaskName"
        }
    } else {
        Write-Host "No scheduled task '$TaskName' found -- nothing to uninstall."
    }
    exit 0
}

# Locate bash.exe — prefer Git Bash (same candidate list as install-coord-sync-task.ps1).
$bashCandidates = @(
    "$env:ProgramFiles\Git\bin\bash.exe",
    "$env:ProgramFiles\Git\usr\bin\bash.exe",
    "$env:ProgramFiles(x86)\Git\bin\bash.exe",
    "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe"
)
$bash = $bashCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $bash) {
    Write-Error "Could not find bash.exe (Git Bash). Install Git for Windows or edit this script with the bash path."
    exit 1
}

function ConvertTo-Posix([string]$p) {
    $s = $p -replace '\\', '/'
    if ($s -match '^([A-Za-z]):(.*)$') { $s = '/' + $Matches[1].ToLower() + $Matches[2] }
    return $s
}

# Shared wrapper dir + hidden-window VBS launcher (machine STATE dir --
# never ~/.claude/scripts, which install.sh re-syncs and would wipe it;
# same as install-coord-sync-task.ps1's convention, reusing the SAME
# run-hidden.vbs if another NL task already wrote one).
$wrapperDir = Join-Path $env:USERPROFILE ".claude\state\task-wrappers"
$vbsPath    = Join-Path $wrapperDir "run-hidden.vbs"
$vbsContent = @'
Set sh = CreateObject("WScript.Shell")
cmd = ""
For i = 0 To WScript.Arguments.Count - 1
  cmd = cmd & """" & WScript.Arguments(i) & """" & " "
Next
sh.Run Trim(cmd), 0, False
'@
if ($PSCmdlet.ShouldProcess($wrapperDir, 'Write shared run-hidden.vbs launcher (if absent)')) {
    if (-not (Test-Path $wrapperDir)) { New-Item -ItemType Directory -Path $wrapperDir -Force | Out-Null }
    if (-not (Test-Path $vbsPath)) { Set-Content -Path $vbsPath -Value $vbsContent -Encoding ASCII }
} else {
    Write-Host "(-WhatIf) Would write $vbsPath (if absent)"
}

$wscript = Join-Path $env:SystemRoot "System32\wscript.exe"

# Resolve BOTH scripts (prefer the live mirror, same fallback pattern as
# install-coord-sync-task.ps1 -- a partial install of one script must not
# block registering against the other).
$liveJanitor  = "$env:USERPROFILE\.claude\scripts\estate-janitor.sh"
$repoJanitor  = Join-Path $RepoPath "adapters\claude-code\scripts\estate-janitor.sh"
$janitorScript = if (Test-Path $liveJanitor) { $liveJanitor } else { $repoJanitor }

$liveBrief    = "$env:USERPROFILE\.claude\scripts\estate-brief.sh"
$repoBrief    = Join-Path $RepoPath "adapters\claude-code\scripts\estate-brief.sh"
$briefScript  = if (Test-Path $liveBrief) { $liveBrief } else { $repoBrief }

if (-not (Test-Path $janitorScript)) {
    Write-Warning "estate-janitor.sh not found at $liveJanitor or $repoJanitor. Run install.sh first (or pass -RepoPath)."
    exit 1
}
if (-not (Test-Path $briefScript)) {
    Write-Warning "estate-brief.sh not found at $liveBrief or $repoBrief. Run install.sh first (or pass -RepoPath)."
    exit 1
}

$posixJanitor = ConvertTo-Posix $janitorScript
$posixBrief   = ConvertTo-Posix $briefScript
$posixLogDir  = ConvertTo-Posix "$env:USERPROFILE\.claude\state\estate"
$cmdPath = Join-Path $wrapperDir "estate-janitor-tick.cmd"

# NOTE the doubled %% (batch semantics: %%Y reaches bash as %Y) -- same
# convention as install-coord-sync-task.ps1's own wrapper. Runs the
# janitor THEN the brief writer in one tick -- brief.txt is always a
# read of the snapshot THIS SAME tick just wrote, never a stale one.
$cmdContent = @"
@echo off
"$bash" -c "export PATH=/usr/bin:/mingw64/bin:`$PATH; mkdir -p '$posixLogDir'; { bash '$posixJanitor' run && bash '$posixBrief' --write; } >> '$posixLogDir/cron-`$(date +%%Y-%%m-%%d).log' 2>&1"
"@

if ($PSCmdlet.ShouldProcess($cmdPath, 'Write task wrapper .cmd')) {
    Set-Content -Path $cmdPath -Value $cmdContent -Encoding ASCII
    Write-Host "Wrote wrapper: $cmdPath"
} else {
    Write-Host "(-WhatIf) Would write $cmdPath with:"
    Write-Host $cmdContent
}

$Action = New-ScheduledTaskAction -Execute $wscript -Argument "`"$vbsPath`" `"$cmdPath`""

$startTime = (Get-Date).AddMinutes(1)
$Trigger = New-ScheduledTaskTrigger -Once -At $startTime `
    -RepetitionInterval (New-TimeSpan -Seconds $IntervalSeconds) `
    -RepetitionDuration (New-TimeSpan -Days 3650)

# ExecutionTimeLimit generous relative to the janitor's own measured cost
# (a full-estate reduction of heartbeats + ~94 worktrees + signal-ledger
# tail + ask-registry fold on this machine's real load) -- 10 minutes, not
# install-coord-sync-task.ps1's 5, since this task walks git worktree
# lists + branch enumerations across every configured repo rather than a
# single lightweight marker check.
$Settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 10) `
    -MultipleInstances IgnoreNew

$taskExists = [bool](Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue)
if ($PSCmdlet.ShouldProcess($TaskName, $(if ($taskExists) { 'Update scheduled task' } else { 'Register scheduled task' }))) {
    if ($taskExists) {
        Set-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger -Settings $Settings | Out-Null
        Write-Host "Updated existing scheduled task: $TaskName"
    } else {
        Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger -Settings $Settings `
            -Description "Accountable Estate program T1 (docs/plans/accountable-estate-program-2026-07.md): read-only estate inventory. Every ${IntervalSeconds}s runs estate-janitor.sh run (heartbeats + process table + git worktree list across configured repos + signal-ledger tail + ask-registry -> snapshot.json, zero mutations) then estate-brief.sh --write (renders snapshot.json to brief.txt). Source: adapters/claude-code/scripts/install-estate-janitor-task.ps1" | Out-Null
        Write-Host "Installed scheduled task: $TaskName"
    }
} else {
    Write-Host "(-WhatIf) Would $(if ($taskExists) { 'update' } else { 'register' }) scheduled task: $TaskName"
    Write-Host "(-WhatIf) Trigger StartBoundary:      $startTime"
    Write-Host "(-WhatIf) Trigger RepetitionInterval: $IntervalSeconds seconds"
    Write-Host "(-WhatIf) Settings MultipleInstances:  IgnoreNew"
    Write-Host "(-WhatIf) Settings ExecutionTimeLimit: 10 minutes"
    Write-Host "(-WhatIf) Action exec: $wscript"
    Write-Host "(-WhatIf) Action args: `"$vbsPath`" `"$cmdPath`""
}

Write-Host ""
Write-Host "Cadence:  every ${IntervalSeconds}s"
Write-Host "Wrapper:  $cmdPath -> $posixJanitor && $posixBrief"
Write-Host "Log:      $env:USERPROFILE\.claude\state\estate\cron-<date>.log"
Write-Host "One-shot full-cycle test (bypasses the schedule): bash '$posixJanitor' run && bash '$posixBrief' --write"
Write-Host "Brief:    $env:USERPROFILE\.claude\state\estate\brief.txt"
