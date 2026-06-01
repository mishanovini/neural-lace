#requires -Version 5.1
<#
.SYNOPSIS
    Registers (or unregisters) a Windows scheduled task that runs the
    Conversation Tree heartbeat every 5 minutes, so the tree stays current
    automatically even when no orchestrator-side spawn or stop event fires.

.DESCRIPTION
    The heartbeat scans `~/.claude/projects/*/*.jsonl` for transcript files
    modified within the last 15 minutes (configurable) and refreshes the
    matching live-marker file under `~/.claude/state/conversation-tree-emit/
    live/<session-id>`. For markers older than the staleness threshold
    (60 min by default), it emits a `concluded` event for every branch
    that session opened (per the correlation ledger) and removes the marker.

    The mechanism is fail-safe by construction: every event is idempotent
    on a deterministic event_id, so a heartbeat fired twice for the same
    transcript is a per-file no-op. The session emit hook (`--on-session-
    start` mode) writes the live-marker on session start; the heartbeat
    refreshes it as the session does work; staleness triggers conclusion.

    Why a scheduled task and not the GUI server: the GUI server is, by
    design (ADR-031 Option 2), a passive observer that never originates
    events. The heartbeat is a writer — it belongs in its own process so
    the GUI invariant remains intact and the heartbeat survives a GUI
    server restart.

    Task settings:
      - Trigger        : every 5 minutes, indefinitely
      - Run as         : current user, interactive, non-elevated
      - Window         : hidden
      - Multiple runs  : IgnoreNew (heartbeat is cheap; never overlap)
      - On failure     : restart up to 3 times, 1-minute interval
      - Time limit     : 1 minute (heartbeat should complete in seconds)

    No paths are hardcoded — the bash invocation and the hook path are
    derived from $env:USERPROFILE and the harness layout at registration.

.PARAMETER Unregister
    Remove the scheduled task instead of registering it.

.PARAMETER RunNow
    After registering, start the task immediately for verification.

.PARAMETER IntervalMinutes
    Heartbeat interval. Default 5. Faster than 1 is not useful; slower
    than 10 makes "live" sessions look stale to operators.
#>
[CmdletBinding()]
param(
    [switch]$Unregister,
    [switch]$RunNow,
    [int]$IntervalMinutes = 5
)

$ErrorActionPreference = 'Stop'

$TaskName = 'ConversationTreeUI-Heartbeat'

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

# Resolve bash.exe — prefer Git for Windows, fall back to WSL/PATH.
$BashExe = $null
foreach ($cand in @(
    "$env:ProgramFiles\Git\bin\bash.exe",
    "$env:ProgramFiles\Git\usr\bin\bash.exe",
    "${env:ProgramFiles(x86)}\Git\bin\bash.exe"
)) {
    if (Test-Path -LiteralPath $cand) { $BashExe = $cand; break }
}
if (-not $BashExe) {
    $cmd = Get-Command -Name 'bash.exe' -ErrorAction SilentlyContinue
    if ($cmd) { $BashExe = $cmd.Source }
}
if (-not $BashExe) {
    throw 'bash.exe could not be located. Install Git for Windows or ensure bash is on PATH.'
}

$HookPath = Join-Path $env:USERPROFILE '.claude\hooks\conversation-tree-emit.sh'
if (-not (Test-Path -LiteralPath $HookPath)) {
    throw "Heartbeat hook not found at $HookPath - run install.sh first to populate ~/.claude/hooks/."
}

# Convert Windows path to a bash-friendly path the hook can source.
$HookBashPath = $HookPath -replace '\\','/' -replace '^C:','/c'

$argLine = '-c "{0} --heartbeat"' -f $HookBashPath

$action = New-ScheduledTaskAction -Execute $BashExe -Argument $argLine

# Trigger: every $IntervalMinutes minutes, starting now, indefinitely.
# Use the legacy COM API to express "repeat every N min for the lifetime"
# because New-ScheduledTaskTrigger does not natively express it cleanly.
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
    -ExecutionTimeLimit (New-TimeSpan -Minutes 1)

Register-ScheduledTask -TaskName $TaskName `
    -Action $action -Trigger $trigger -Principal $principal -Settings $settings `
    -Description ('Heartbeat for the Conversation Tree UI: refreshes live ' +
        'session markers and concludes stale ones every {0} minutes. ' +
        'Managed by conversation-tree-ui/scripts/register-heartbeat.ps1.' -f $IntervalMinutes) `
    -Force | Out-Null

Write-Host "Registered scheduled task: $TaskName"
Write-Host ("  Action  : {0} {1}" -f $BashExe, $argLine)
Write-Host ("  Trigger : every {0} minute(s), indefinitely" -f $IntervalMinutes)

if ($RunNow) {
    Write-Host ''
    Write-Host 'Starting task now for verification...'
    Start-ScheduledTask -TaskName $TaskName
    Start-Sleep -Seconds 3
    $info = Get-ScheduledTaskInfo -TaskName $TaskName
    Write-Host ("  LastRunTime    : {0}" -f $info.LastRunTime)
    Write-Host ("  LastTaskResult : {0}" -f $info.LastTaskResult)
}
