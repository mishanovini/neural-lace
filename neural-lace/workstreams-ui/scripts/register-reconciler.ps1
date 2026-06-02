#requires -Version 5.1
<#
.SYNOPSIS
    Registers (or unregisters) a Windows scheduled task that runs the Component B
    orchestrator reconciler (reconciler-run.js) every N minutes — the
    "scheduled runner is the trustworthy backbone" trigger from
    orchestration-architecture-2026-05-30.md §3.

.DESCRIPTION
    The reconciler is a PURE, IDEMPOTENT pass: it reads the Workstreams ADR-032
    event log, computes cascades (items blocked-on a just-shipped thing become
    unblocked), scans live sessions via transcript-mtime, fills free orchestrator
    slots from the prioritized backlog, surfaces Misha-attention items, and emits
    the resulting state-transition events. Running it twice is harmless.

    Two triggers compose (design §3): this scheduled task is the BACKBONE
    (default every 5 min); the `workstreams-orchestrator-queue.sh` Stop hook is
    the low-latency ICING (drops a wake file the next scheduled pass consumes —
    or, if a faster cadence is desired, lower -IntervalMinutes).

    SAFETY: by default the runner is SURFACE-ONLY (config.autoSpawn=false). It
    computes + writes the spawn surface (~/.claude/state/orchestrator/surface.json)
    but launches NOTHING. Auto-launching is gated behind config.autoSpawn AND only
    ever applies to headless-local `claude -p` spawns — Code/Cowork/Routine tasks
    are surfaced for Dispatch (a subprocess cannot call the MCP spawn tools).
    Do NOT flip autoSpawn on until Components A (/goal trust gate) and C
    (cross-machine claim-lease) are live.

    Task settings mirror register-heartbeat.ps1: hidden window, IgnoreNew
    (idempotent — never overlap; the runner also holds a lock), restart-on-fail
    up to 3x, 2-minute execution limit.

.PARAMETER Unregister
    Remove the scheduled task instead of registering it.

.PARAMETER RunNow
    After registering, start the task immediately for verification.

.PARAMETER IntervalMinutes
    Reconciler interval. Default 5 (matches the heartbeat cadence).
#>
[CmdletBinding()]
param(
    [switch]$Unregister,
    [switch]$RunNow,
    [int]$IntervalMinutes = 5
)

$ErrorActionPreference = 'Stop'

$TaskName = 'Workstreams-OrchestratorReconciler'

if ($Unregister) {
    $existing = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($existing) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Write-Host "Unregistered scheduled task: $TaskName"
    } else {
        Write-Host "Scheduled task '$TaskName' is not registered (nothing to remove)."
    }
    return
}

# Resolve node.exe — prefer PATH, fall back to common install locations.
$NodeExe = $null
$cmd = Get-Command -Name 'node.exe' -ErrorAction SilentlyContinue
if ($cmd) { $NodeExe = $cmd.Source }
if (-not $NodeExe) {
    foreach ($cand in @(
        "$env:ProgramFiles\nodejs\node.exe",
        "${env:ProgramFiles(x86)}\nodejs\node.exe",
        "$env:LOCALAPPDATA\Programs\nodejs\node.exe"
    )) { if (Test-Path -LiteralPath $cand) { $NodeExe = $cand; break } }
}
if (-not $NodeExe) {
    throw 'node.exe could not be located. Install Node.js or ensure it is on PATH.'
}

# The runner lives in the repo checkout (../state/reconciler-run.js relative to
# this script), NOT in ~/.claude (unlike hooks). Resolve from $PSScriptRoot.
$RunnerPath = Join-Path $PSScriptRoot '..\state\reconciler-run.js'
$RunnerPath = (Resolve-Path -LiteralPath $RunnerPath).Path
if (-not (Test-Path -LiteralPath $RunnerPath)) {
    throw "Reconciler runner not found at $RunnerPath"
}

$argLine = '"{0}"' -f $RunnerPath

$action = New-ScheduledTaskAction -Execute $NodeExe -Argument $argLine

$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date)
$trigger.Repetition = (New-ScheduledTaskTrigger -Once -At (Get-Date) `
    -RepetitionInterval (New-TimeSpan -Minutes $IntervalMinutes) `
    -RepetitionDuration (New-TimeSpan -Days 9999)).Repetition

$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" `
    -LogonType Interactive -RunLevel Limited

$settings = New-ScheduledTaskSettingsSet `
    -MultipleInstances IgnoreNew `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -RestartCount 3 `
    -RestartInterval (New-TimeSpan -Minutes 1) `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 2)

Register-ScheduledTask -TaskName $TaskName `
    -Action $action -Trigger $trigger -Principal $principal -Settings $settings `
    -Description ('Component B orchestrator reconciler: reconciles the Workstreams ' +
        'work-tracker every {0} minutes (cascades, stall detection, slot fill, ' +
        'Misha-attention surfacing). SURFACE-ONLY by default (autoSpawn off). ' +
        'Managed by workstreams-ui/scripts/register-reconciler.ps1.' -f $IntervalMinutes) `
    -Force | Out-Null

Write-Host "Registered scheduled task: $TaskName"
Write-Host ("  Action  : {0} {1}" -f $NodeExe, $argLine)
Write-Host ("  Trigger : every {0} minute(s), indefinitely" -f $IntervalMinutes)
Write-Host "  Mode    : SURFACE-ONLY (config.autoSpawn=false) — safe default"

if ($RunNow) {
    Write-Host ''
    Write-Host 'Starting task now for verification...'
    Start-ScheduledTask -TaskName $TaskName
    Start-Sleep -Seconds 4
    $info = Get-ScheduledTaskInfo -TaskName $TaskName
    Write-Host ("  LastRunTime    : {0}" -f $info.LastRunTime)
    Write-Host ("  LastTaskResult : {0}" -f $info.LastTaskResult)
}
