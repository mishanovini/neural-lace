#requires -Version 5.1
<#
.SYNOPSIS
    One-click launcher for the Conversation Tree UI.

.DESCRIPTION
    Starts the conversation-tree-ui Node server (server/server.js) as a detached,
    window-less background process if it is not already listening on port 7733,
    waits for it to come up, then opens the GUI in the default browser.

    Re-running while the server is already up skips the start and just opens the
    browser. All actions are logged to ~/.claude/logs/conv-tree-launcher.log.

    No absolute paths are hardcoded: the project directory is derived from this
    script's own location ($PSScriptRoot's parent), and the log directory from
    $env:USERPROFILE. The script is therefore portable across machines/users.

.PARAMETER NoBrowser
    Start the server if needed but do not open the browser. Useful for testing
    and for headless "make sure the server is up" invocations.
#>
[CmdletBinding()]
param(
    [switch]$NoBrowser,
    # Server port. Defaults to 7733 (the server's own default). Override only
    # for testing/diagnostics; mirrors the server's CTREE_PORT env support.
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

# --- User-visible error surface (toast if available, else message box) -------
function Show-LauncherError {
    param([string]$Message)
    Write-Log $Message 'ERROR'
    $shown = $false
    if (Get-Command -Name New-BurntToastNotification -ErrorAction SilentlyContinue) {
        try {
            New-BurntToastNotification -Text 'Conversation Tree', $Message | Out-Null
            $shown = $true
        } catch { $shown = $false }
    }
    if (-not $shown) {
        try {
            Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
            [System.Windows.Forms.MessageBox]::Show(
                $Message, 'Conversation Tree - launch failed',
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        } catch {
            # Even the message box failed (no GUI session?). The log is the
            # last-resort record; nothing more we can do here.
        }
    }
}

# --- Port probe -------------------------------------------------------------
function Test-ServerListening {
    # Returns $true if something is listening on 127.0.0.1:$Port.
    try {
        $conn = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction Stop
        return [bool]$conn
    } catch {
        # Get-NetTCPConnection throws when no matching connection exists, OR the
        # cmdlet is unavailable. Fall back to a raw TCP connect attempt.
        try {
            $client = New-Object System.Net.Sockets.TcpClient
            $iar = $client.BeginConnect('127.0.0.1', $Port, $null, $null)
            $ok = $iar.AsyncWaitHandle.WaitOne(500)
            if ($ok -and $client.Connected) { $client.Close(); return $true }
            $client.Close()
            return $false
        } catch {
            return $false
        }
    }
}

# --- Main -------------------------------------------------------------------
try {
    Write-Log "Launcher invoked. ProjectDir=$ProjectDir Port=$Port"

    if (-not (Test-Path -LiteralPath $ServerPath)) {
        Show-LauncherError "Server file not found at: $ServerPath. The conversation-tree-ui project layout may have changed."
        exit 1
    }

    if (Test-ServerListening) {
        Write-Log "Server already listening on port $Port - skipping start."
    } else {
        # Resolve node from PATH. Clear, actionable error if it is missing.
        $node = Get-Command -Name 'node' -ErrorAction SilentlyContinue
        if (-not $node) {
            Show-LauncherError ("Node.js was not found on PATH. Install Node.js (https://nodejs.org) " +
                "and ensure 'node' is on your PATH, then click the shortcut again.")
            exit 1
        }
        $nodeExe = $node.Source
        Write-Log "Node found: $nodeExe"
        Write-Log "Starting server (hidden, detached): $nodeExe $ServerRel  (cwd=$ProjectDir, port=$Port)"

        # The server honors CTREE_PORT; the spawned process inherits this env.
        $env:CTREE_PORT = "$Port"

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
            if (Test-ServerListening) { $up = $true; break }
        }
        if ($up) {
            Write-Log "Server is up on port $Port after ~$([math]::Round(($i + 1) * 0.5, 1))s."
        } else {
            Show-LauncherError ("Started the server process but port $Port did not come up within 5s. " +
                "Check $LogFile and try again; the server may still be initializing.")
            # Do not exit - still attempt to open the browser; the server may
            # finish coming up by the time the page loads.
        }
    }

    if ($NoBrowser) {
        Write-Log "-NoBrowser set; not opening browser. Done."
        exit 0
    }

    Write-Log "Opening browser to $Url"
    Start-Process $Url | Out-Null
    Write-Log "Launcher complete."
    exit 0
}
catch {
    Show-LauncherError ("Unexpected launcher error: " + $_.Exception.Message)
    exit 1
}
