#requires -Version 5.1
<#
.SYNOPSIS
    Creates (or removes) Desktop + Start Menu shortcuts for the Conversation
    Tree UI launcher.

.DESCRIPTION
    Generates two .lnk files named "Conversation Tree":
      - one on the current user's Desktop
      - one in the current user's Start Menu Programs folder
    Each shortcut runs:
      powershell.exe -ExecutionPolicy Bypass -NoProfile -WindowStyle Hidden -File "<launch-gui.ps1>"

    The .lnk files contain absolute, machine-specific paths and are therefore
    NOT committed to the repo - this script (which is committed) regenerates
    them on demand. Run it after pulling the repo to (re)create the shortcuts.

    All target paths are derived at runtime ($PSScriptRoot, [Environment]
    special folders) - nothing is hardcoded.

.PARAMETER Remove
    Delete the Desktop and Start Menu shortcuts instead of creating them.
#>
[CmdletBinding()]
param(
    [switch]$Remove
)

$ErrorActionPreference = 'Stop'

$LauncherPath  = Join-Path $PSScriptRoot 'launch-gui.ps1'
$ShortcutName  = 'Conversation Tree.lnk'

$DesktopDir    = [Environment]::GetFolderPath('Desktop')
$StartMenuDir  = [Environment]::GetFolderPath('Programs')
$DesktopLnk    = Join-Path $DesktopDir   $ShortcutName
$StartMenuLnk  = Join-Path $StartMenuDir $ShortcutName

if ($Remove) {
    foreach ($lnk in @($DesktopLnk, $StartMenuLnk)) {
        if (Test-Path -LiteralPath $lnk) {
            Remove-Item -LiteralPath $lnk -Force
            Write-Host "Removed: $lnk"
        } else {
            Write-Host "Not present (nothing to remove): $lnk"
        }
    }
    return
}

if (-not (Test-Path -LiteralPath $LauncherPath)) {
    throw "Launcher not found at $LauncherPath - cannot create shortcuts."
}

# Resolve the real powershell.exe path rather than trusting PATH.
$PsExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
if (-not (Test-Path -LiteralPath $PsExe)) {
    $cmd = Get-Command -Name 'powershell.exe' -ErrorAction SilentlyContinue
    if ($cmd) { $PsExe = $cmd.Source } else { throw 'powershell.exe could not be located.' }
}

$Arguments     = '-ExecutionPolicy Bypass -NoProfile -WindowStyle Hidden -File "{0}"' -f $LauncherPath
$WorkingDir    = Split-Path -Parent $LauncherPath   # ...\conversation-tree-ui\scripts

$wsh = New-Object -ComObject WScript.Shell
try {
    foreach ($lnk in @($DesktopLnk, $StartMenuLnk)) {
        $parent = Split-Path -Parent $lnk
        if (-not (Test-Path -LiteralPath $parent)) {
            New-Item -ItemType Directory -Path $parent -Force | Out-Null
        }
        $sc = $wsh.CreateShortcut($lnk)
        $sc.TargetPath       = $PsExe
        $sc.Arguments        = $Arguments
        $sc.WorkingDirectory = $WorkingDir
        $sc.WindowStyle      = 7   # 7 = minimized (defence-in-depth; the launcher already hides itself)
        $sc.Description      = 'Launch the Conversation Tree UI (starts the local server if needed, opens the browser)'
        # Default icon = powershell.exe's icon. There is no standard "tree"
        # icon shipped with Windows; a custom .ico can be dropped next to this
        # script as conv-tree.ico and this line uncommented to use it:
        # $sc.IconLocation = (Join-Path $PSScriptRoot 'conv-tree.ico')
        $sc.Save()
        Write-Host "Created shortcut: $lnk"
    }
}
finally {
    [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($wsh)
}

Write-Host ''
Write-Host 'Done. Two shortcuts created:'
Write-Host "  Desktop    : $DesktopLnk"
Write-Host "  Start Menu : $StartMenuLnk"
