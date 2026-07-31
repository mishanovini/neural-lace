# install-limit-resume-task.ps1
#
# Windows equivalent of install-limit-resume.sh's macOS LaunchAgent:
# registers ONE Windows Scheduled Task, 'NL-LimitResume', that runs
# `bash adapters/claude-code/scripts/limit-resume.sh tick` on a cadence —
# the watchdog itself (arm/disarm/tick/status, bounded retries, real
# backoff, hard stop) is fully OS-agnostic bash; only the OS-level
# "run this every N seconds forever" registration differs per platform.
#
# Same registration pattern as install-coord-sync-task.ps1 /
# install-estate-janitor-task.ps1 (hidden-window wrapper via a shared
# run-hidden.vbs launcher, quoting-collapse-proof action, machine STATE
# wrapper dir never touched by install.sh) — see those files' own headers
# for the full rationale; not re-derived here.
#
# ============================================================
# NAMED GAP (constitution §1 — say exactly what was not demonstrated)
# ============================================================
# This script is written to the SAME established pattern as the three
# sibling install-*-task.ps1 files already in this directory (structural
# consistency reviewed against install-estate-janitor-task.ps1 line by
# line), but it has NOT been run, registered, or exercised on a real
# Windows machine this session — there is no Windows box available on
# this Mac. It is UNTESTED. Do not read its presence as "the Windows path
# works"; read it as "the Windows path is written, following the
# repo's own proven pattern, and needs a Windows-box verification pass
# before anyone relies on it." Logged as a gap in docs/backlog.md.
#
# SHIP-ONLY, PER TASK SCOPE (same posture as install-estate-janitor-
# task.ps1): this installer is written and -WhatIf-exercisable (proving
# the wrapper content + registration shape without touching Task
# Scheduler), but Register-ScheduledTask is never invoked by an agent
# session — registration is the operator's own action on their own
# Windows machine, run manually once they choose to.
#
# Task name: NL-LimitResume
# Cadence:   every -IntervalSeconds (default 900s = 15min, matching the
#            macOS LaunchAgent's StartInterval and limit-resume.sh's own
#            default backoff base).
# Output:    ~/.claude/state/limit-resume/log.txt (the watchdog's own log;
#            written by limit-resume.sh itself, not by this wrapper)
#            ~/.claude/state/task-wrappers/limit-resume-tick.log (this
#            wrapper's own stdout/stderr, for diagnosing a tick that never
#            reaches limit-resume.sh at all — the Windows analog of
#            DEFECT 1's "env: node" class failure)
#
# Run ONCE per machine as a normal (non-elevated) user, when the operator
# chooses to. Re-running is safe (idempotent — Set- if already present,
# Register- if not).
#
# Usage:
#   powershell -File adapters/claude-code/scripts/install-limit-resume-task.ps1
#   powershell -File ... -RepoPath "$env:USERPROFILE\dev\<work-org>\neural-lace"
#   powershell -File ... -IntervalSeconds 900
#   powershell -File ... -WhatIf      # dry-run: prints wrapper contents +
#                                     # registration WITHOUT touching disk
#                                     # or Task Scheduler
#   powershell -File ... -Uninstall  # unregisters the task
#
# Verification after install (operator-run, not agent-run):
#   Get-ScheduledTask -TaskName 'NL-LimitResume'
#   Start-ScheduledTask -TaskName 'NL-LimitResume'   # one-shot test tick
#   schtasks /Query /TN NL-LimitResume /V | findstr "Last Result"  # 0 = healthy
#   Get-Content "$env:USERPROFILE\.claude\state\limit-resume\log.txt"

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$RepoPath = "$HOME\dev\<work-org>\neural-lace",
    [int]$IntervalSeconds = 900,
    [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'
$TaskName = 'NL-LimitResume'

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

# Locate bash.exe -- prefer Git Bash (same candidate list as the sibling installers).
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
# same convention as the sibling installers, reusing the SAME
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

# Resolve the watchdog script (prefer the live mirror, same fallback
# pattern as the sibling installers -- a fresh checkout that has not run
# install.sh yet must still be able to register against the repo copy).
$liveScript = "$env:USERPROFILE\.claude\scripts\limit-resume.sh"
$repoScript = Join-Path $RepoPath "adapters\claude-code\scripts\limit-resume.sh"
$watchdogScript = if (Test-Path $liveScript) { $liveScript } else { $repoScript }

if (-not (Test-Path $watchdogScript)) {
    Write-Warning "limit-resume.sh not found at $liveScript or $repoScript. Run install.sh first (or pass -RepoPath)."
    exit 1
}

$posixScript = ConvertTo-Posix $watchdogScript
$posixLogDir = ConvertTo-Posix (Join-Path $env:USERPROFILE ".claude\state\task-wrappers")
$cmdPath = Join-Path $wrapperDir "limit-resume-tick.cmd"

# NOTE the doubled %% (batch semantics: %%Y reaches bash as %Y) -- same
# convention as the sibling wrappers. `tick` is a no-op (exit 0, no log
# growth) unless the watchdog's own marker is armed, so running this
# every IntervalSeconds forever is cheap and safe even when nothing is
# tracked.
$cmdContent = @"
@echo off
"$bash" -c "export PATH=/usr/bin:/mingw64/bin:`$PATH; mkdir -p '$posixLogDir'; bash '$posixScript' tick >> '$posixLogDir/limit-resume-tick-`$(date +%%Y-%%m-%%d).log' 2>&1"
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

# ExecutionTimeLimit generous relative to limit-resume.sh's own
# TIMEOUT_SECONDS bound (default 1800s = 30 min) on the `claude -p
# --resume` child it may spawn -- give the tick itself a little headroom
# beyond that bound rather than racing it.
$Settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 35) `
    -MultipleInstances IgnoreNew

$taskExists = [bool](Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue)
if ($PSCmdlet.ShouldProcess($TaskName, $(if ($taskExists) { 'Update scheduled task' } else { 'Register scheduled task' }))) {
    if ($taskExists) {
        Set-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger -Settings $Settings | Out-Null
        Write-Host "Updated existing scheduled task: $TaskName"
    } else {
        Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger -Settings $Settings `
            -Description "limit-resume watchdog (docs/decisions/068-macos-limit-resume-turn-scoped-auto-arm.md): every ${IntervalSeconds}s runs limit-resume.sh tick -- a no-op unless the watchdog's own marker is armed (via SessionStart/UserPromptSubmit hook splices), bounded retries with real backoff, hard stop after MAX_RETRIES. Source: adapters/claude-code/scripts/install-limit-resume-task.ps1" | Out-Null
        Write-Host "Installed scheduled task: $TaskName"
    }
} else {
    Write-Host "(-WhatIf) Would $(if ($taskExists) { 'update' } else { 'register' }) scheduled task: $TaskName"
    Write-Host "(-WhatIf) Trigger StartBoundary:      $startTime"
    Write-Host "(-WhatIf) Trigger RepetitionInterval: $IntervalSeconds seconds"
    Write-Host "(-WhatIf) Settings MultipleInstances:  IgnoreNew"
    Write-Host "(-WhatIf) Settings ExecutionTimeLimit: 35 minutes"
    Write-Host "(-WhatIf) Action exec: $wscript"
    Write-Host "(-WhatIf) Action args: `"$vbsPath`" `"$cmdPath`""
}

Write-Host ""
Write-Host "Cadence:  every ${IntervalSeconds}s"
Write-Host "Wrapper:  $cmdPath -> bash $posixScript tick"
Write-Host "Log:      $env:USERPROFILE\.claude\state\task-wrappers\limit-resume-tick-<date>.log (wrapper stdout/stderr)"
Write-Host "          $env:USERPROFILE\.claude\state\limit-resume\log.txt (the watchdog's own attempt log)"
Write-Host "One-shot test tick (bypasses the schedule): bash '$posixScript' tick"
Write-Host "Status:   bash '$posixScript' status"
