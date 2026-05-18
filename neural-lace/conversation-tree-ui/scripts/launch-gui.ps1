#requires -Version 5.1
<#
.SYNOPSIS
    One-click launcher for the Conversation Tree UI.

.DESCRIPTION
    Opens the Conversation Tree GUI in the default browser, starting the local
    Node server (server/server.js) first if it is not already up.

    Order of operations (port-check FIRST, deliberately):
      1. Probe the server. If it is already up on the port, the launcher
         NEVER touches Node at all - it just opens the browser. This is the
         common case (the autostart task already started it at logon).
      2. Only if the server is NOT up does the launcher resolve Node and
         start it. Node is resolved robustly (PATH, then a list of common
         install locations incl. nvm/Volta/fnm/asdf) so a missing or
         not-yet-populated PATH does not break the launch.

    Error policy: everything is logged to
    ~/.claude/logs/conv-tree-launcher.log. A Windows dialog is shown ONLY
    for a genuinely user-actionable error AND only in interactive mode.
    In background mode (-NoBrowser, used by the logon autostart task) the
    launcher NEVER shows any UI - it logs and exits quietly. No raw
    exception text or stack traces are ever shown to the user.

    No absolute paths are hardcoded: the project directory is derived from
    this script's own location, the log directory from $env:USERPROFILE,
    and Node candidate locations from standard environment variables.

.PARAMETER NoBrowser
    Background mode. Ensure the server is up but do NOT open the browser and
    NEVER show any dialog (used by the logon autostart scheduled task).

.PARAMETER Port
    Server port. Defaults to 7733 (the server's own default). Override only
    for testing/diagnostics; mirrors the server's CTREE_PORT env support.
#>
[CmdletBinding()]
param(
    [switch]$NoBrowser,
    [int]$Port = 7733
)

$ErrorActionPreference = 'Stop'

# --- Paths (all derived, none hardcoded) ------------------------------------
$ProjectDir = Split-Path -Parent $PSScriptRoot          # ...\conversation-tree-ui
$ServerRel  = Join-Path 'server' 'server.js'
$ServerPath = Join-Path $ProjectDir $ServerRel
$Url        = "http://127.0.0.1:$Port"

$LogDir  = Join-Path $env:USERPROFILE '.claude\logs'
$LogFile = Join-Path $LogDir 'conv-tree-launcher.log'

# --- Logging ----------------------------------------------------------------
function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $ts = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $line = "[$ts] [$Level] $Message"
    try {
        if (-not (Test-Path -LiteralPath $LogDir)) {
            New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
        }
        Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8
    } catch {
        # Logging must never be the thing that breaks the launcher.
    }
    Write-Verbose $line
}

# --- User-actionable error surface ------------------------------------------
# Always logs. Shows a single clean dialog ONLY when interactive (NOT
# -NoBrowser) AND the message is something the user can act on. Background
# mode logs only - a logon task must never pop a dialog in the user's face.
function Show-ActionableError {
    param([string]$Message)
    Write-Log $Message 'ERROR'
    if ($NoBrowser) { return }   # background/autostart: log only, no UI ever
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        [System.Windows.Forms.MessageBox]::Show(
            $Message, 'Conversation Tree',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
    } catch {
        # No GUI session available - the log is the record.
    }
}

# --- Robust Node resolution -------------------------------------------------
# PATH first, then a prioritized list of common install locations so a
# missing/not-yet-populated PATH (e.g. early logon, scheduled-task env) does
# not break the launch. Returns the node.exe full path, or $null.
function Resolve-NodeExe {
    $cmd = Get-Command -Name 'node' -CommandType Application -ErrorAction SilentlyContinue |
           Select-Object -First 1
    if ($cmd -and (Test-Path -LiteralPath $cmd.Source)) { return $cmd.Source }

    $candidates = New-Object System.Collections.Generic.List[string]

    # Standard installer locations
    if ($env:ProgramFiles)          { $candidates.Add((Join-Path $env:ProgramFiles 'nodejs\node.exe')) }
    if (${env:ProgramFiles(x86)})   { $candidates.Add((Join-Path ${env:ProgramFiles(x86)} 'nodejs\node.exe')) }
    if ($env:LOCALAPPDATA)          { $candidates.Add((Join-Path $env:LOCALAPPDATA 'Programs\nodejs\node.exe')) }

    # nvm-windows: explicit env vars first, then well-known layouts
    if ($env:NVM_SYMLINK)           { $candidates.Add((Join-Path $env:NVM_SYMLINK 'node.exe')) }
    if ($env:NVM_HOME)              { $candidates.Add((Join-Path $env:NVM_HOME 'node.exe')) }
    if ($env:USERPROFILE)           { $candidates.Add((Join-Path $env:USERPROFILE '.nvm\nvm-current\node.exe')) }

    # Helper: newest child matching a pattern that actually contains node.exe
    function Add-NewestNode {
        param([string]$Root, [string]$Filter, [string]$RelExe)
        if (-not $Root -or -not (Test-Path -LiteralPath $Root)) { return }
        try {
            Get-ChildItem -LiteralPath $Root -Directory -Filter $Filter -ErrorAction SilentlyContinue |
                Sort-Object Name -Descending |
                ForEach-Object {
                    $p = Join-Path $_.FullName $RelExe
                    if (Test-Path -LiteralPath $p) { $candidates.Add($p) }
                }
        } catch { }
    }

    # nvm-windows installs: %APPDATA%\nvm\v<ver>\node.exe (newest first)
    if ($env:APPDATA) { Add-NewestNode -Root (Join-Path $env:APPDATA 'nvm') -Filter 'v*' -RelExe 'node.exe' }

    # Volta
    if ($env:LOCALAPPDATA) { $candidates.Add((Join-Path $env:LOCALAPPDATA 'Volta\bin\node.exe')) }
    if ($env:USERPROFILE)  { $candidates.Add((Join-Path $env:USERPROFILE '.volta\bin\node.exe')) }

    # fnm
    if ($env:LOCALAPPDATA) {
        $candidates.Add((Join-Path $env:LOCALAPPDATA 'fnm\aliases\default\node.exe'))
        Add-NewestNode -Root (Join-Path $env:LOCALAPPDATA 'fnm_multishells') -Filter '*' -RelExe 'node.exe'
        Add-NewestNode -Root (Join-Path $env:LOCALAPPDATA 'fnm\node-versions') -Filter 'v*' -RelExe 'installation\node.exe'
    }

    # asdf (rare on Windows, but covered): ~/.asdf/installs/nodejs/<ver>/bin/node.exe
    if ($env:USERPROFILE) {
        Add-NewestNode -Root (Join-Path $env:USERPROFILE '.asdf\installs\nodejs') -Filter '*' -RelExe 'bin\node.exe'
    }

    foreach ($c in $candidates) {
        if ($c -and (Test-Path -LiteralPath $c)) { return $c }
    }
    return $null
}

# --- Authoritative "is OUR server up" probe ---------------------------------
# Strongest signal: an HTTP 200 from the server's own /api/state endpoint.
# Falls back to a TCP listen check. One short retry absorbs a transient miss
# so the launcher does not falsely decide "not up" and needlessly touch Node.
function Test-ServerUp {
    for ($attempt = 0; $attempt -lt 2; $attempt++) {
        if ($attempt -gt 0) { Start-Sleep -Milliseconds 300 }

        # 1. HTTP probe (definitive: confirms it is the conv-tree server)
        try {
            $resp = Invoke-WebRequest -Uri "$Url/api/state" -UseBasicParsing `
                        -TimeoutSec 2 -ErrorAction Stop
            if ($resp.StatusCode -eq 200) { return $true }
        } catch {
            # fall through to the TCP check
        }

        # 2. TCP listen check via cmdlet
        try {
            $conn = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction Stop
            if ($conn) { return $true }
        } catch {
            # 3. Raw TCP connect fallback (cmdlet absent / no match)
            try {
                $client = New-Object System.Net.Sockets.TcpClient
                $iar = $client.BeginConnect('127.0.0.1', $Port, $null, $null)
                $ok = $iar.AsyncWaitHandle.WaitOne(700)
                $connected = ($ok -and $client.Connected)
                $client.Close()
                if ($connected) { return $true }
            } catch { }
        }
    }
    return $false
}

# --- Main -------------------------------------------------------------------
try {
    $mode = if ($NoBrowser) { 'background' } else { 'interactive' }
    Write-Log "Launcher invoked ($mode). ProjectDir=$ProjectDir Port=$Port"

    # STEP 1 - port-check FIRST. If the server is up, never touch Node.
    if (Test-ServerUp) {
        Write-Log "Server already up on port $Port - skipping start (Node not needed)."
    }
    else {
        # Server is down: we must start it. Validate layout, resolve Node.
        if (-not (Test-Path -LiteralPath $ServerPath)) {
            Show-ActionableError ("Conversation Tree server file is missing at: $ServerPath. " +
                "The project layout may have changed - reinstall or re-pull the repo.")
            exit 1
        }

        $nodeExe = Resolve-NodeExe
        if (-not $nodeExe) {
            Show-ActionableError ("Conversation Tree could not find Node.js. Install it from " +
                "https://nodejs.org (or via nvm/Volta/fnm), then click the shortcut again. " +
                "Details are in $LogFile.")
            exit 1
        }
        Write-Log "Node resolved: $nodeExe"
        Write-Log "Starting server (hidden, detached): $nodeExe $ServerRel (cwd=$ProjectDir, port=$Port)"

        $env:CTREE_PORT = "$Port"   # server honors CTREE_PORT; child inherits env

        # Start-Process launches an independent process that survives this
        # script's exit. -WindowStyle Hidden suppresses the console window.
        Start-Process -FilePath $nodeExe `
                      -ArgumentList $ServerRel `
                      -WorkingDirectory $ProjectDir `
                      -WindowStyle Hidden | Out-Null

        # Poll for the server to come up (max ~5s).
        $up = $false
        for ($i = 0; $i -lt 10; $i++) {
            Start-Sleep -Milliseconds 500
            if (Test-ServerUp) { $up = $true; break }
        }
        if ($up) {
            Write-Log "Server is up on port $Port after ~$([math]::Round(($i + 1) * 0.5, 1))s."
        } else {
            # Not a popup-worthy event by itself: log it. In interactive mode
            # we still try the browser (it may finish coming up); in
            # background mode we just record it and stop.
            Write-Log ("Started the server process but port $Port did not respond within 5s; " +
                "it may still be initializing.") 'WARN'
        }
    }

    if ($NoBrowser) {
        Write-Log "Background mode; not opening browser. Done."
        exit 0
    }

    Write-Log "Opening browser to $Url"
    Start-Process $Url | Out-Null
    Write-Log "Launcher complete."
    exit 0
}
catch {
    # Never surface raw exception text to the user. Log the detail; show a
    # friendly dialog only in interactive mode.
    Write-Log ("Unexpected launcher error: " + $_.Exception.Message) 'ERROR'
    Show-ActionableError ("Conversation Tree could not start. Technical details were written to " +
        "$LogFile.")
    exit 1
}
