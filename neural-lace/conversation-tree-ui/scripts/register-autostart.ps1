#requires -Version 5.1
<#
.SYNOPSIS
    Registers (or unregisters) a Windows scheduled task that starts the
    Conversation Tree UI server at user logon - so the GUI is always ready.

.DESCRIPTION
    Registers a scheduled task named "ConversationTreeUI-AutoStart" that, at
    logon of the current user, starts the conversation-tree-ui server in a
    hidden window. It does NOT open a browser.

    Implementation note (deliberate, documented in scripts/README.md):
    the task action invokes  launch-gui.ps1 -NoBrowser  rather than calling
    `node server/server.js` directly. -NoBrowser starts ONLY the server (no
    browser, exactly the spec's intent) AND reuses the launcher's port-7733
    guard, so a logon-start and a later manual desktop-icon launch never
    double-bind the port. One code path is verified and maintained instead of
    two divergent server-start implementations.

    Task settings:
      - Trigger        : at logon of the current user
      - Run as         : current user, interactive, non-elevated
      - Window         : hidden
      - Multiple runs  : IgnoreNew (a manual launch already up is not disturbed)
      - On failure     : restart up to 3 times, 1-minute interval
      - Time limit     : none (long-running server)

    No paths are hardcoded - the launcher path and working directory are
    derived from $PSScriptRoot at registration time. The task definition that
    Task Scheduler stores does contain absolute paths, but that is per-machine
    state, not committed content.

.PARAMETER Unregister
    Remove the scheduled task instead of registering it.

.PARAMETER RunNow
    After registering, start the task immediately (for verification - confirms
    the action actually brings the server up without waiting for next logon).
#>
[CmdletBinding()]
param(
    [switch]$Unregister,
    [switch]$RunNow
)

$ErrorActionPreference = 'Stop'

$TaskName     = 'ConversationTreeUI-AutoStart'
$LauncherPath = Join-Path $PSScriptRoot 'launch-gui.ps1'
$ProjectDir   = Split-Path -Parent $PSScriptRoot   # ...\conversation-tree-ui

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

if (-not (Test-Path -LiteralPath $LauncherPath)) {
    throw "Launcher not found at $LauncherPath - cannot register the autostart task."
}

$PsExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
if (-not (Test-Path -LiteralPath $PsExe)) {
    $cmd = Get-Command -Name 'powershell.exe' -ErrorAction SilentlyContinue
    if ($cmd) { $PsExe = $cmd.Source } else { throw 'powershell.exe could not be located.' }
}

$argLine = '-ExecutionPolicy Bypass -NoProfile -WindowStyle Hidden -File "{0}" -NoBrowser' -f $LauncherPath

$action  = New-ScheduledTaskAction -Execute $PsExe -Argument $argLine -WorkingDirectory $ProjectDir
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Limited
$settings  = New-ScheduledTaskSettingsSet `
                -MultipleInstances IgnoreNew `
                -AllowStartIfOnBatteries `
                -DontStopIfGoingOnBatteries `
                -StartWhenAvailable `
                -RestartCount 3 `
                -RestartInterval (New-TimeSpan -Minutes 1) `
                -ExecutionTimeLimit ([TimeSpan]::Zero)   # PT0S = no time limit

Register-ScheduledTask -TaskName $TaskName `
    -Action $action -Trigger $trigger -Principal $principal -Settings $settings `
    -Description 'Starts the Conversation Tree UI local server at logon (no browser). Managed by conversation-tree-ui/scripts/register-autostart.ps1.' `
    -Force | Out-Null

Write-Host "Registered scheduled task: $TaskName"
Write-Host "  Action : $PsExe $argLine"
Write-Host "  Trigger: at logon of $env:USERDOMAIN\$env:USERNAME"

if ($RunNow) {
    Write-Host ''
    Write-Host "Starting task now for verification..."
    Start-ScheduledTask -TaskName $TaskName
    Start-Sleep -Seconds 3
    $info = Get-ScheduledTaskInfo -TaskName $TaskName
    Write-Host ("  LastRunTime    : {0}" -f $info.LastRunTime)
    Write-Host ("  LastTaskResult : {0}" -f $info.LastTaskResult)
}
