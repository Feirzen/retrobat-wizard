<#
    Show-ShortcutMaker.ps1
    ---------------------------------------------------------------------------
    Opens the "Add a shortcut to a game" window. This is the console front end;
    the wizard's Help tab calls the same function directly, so if the wizard
    ever breaks this window is still reachable from a .bat.

    Run it from:  Maintenance Steps\Add A Game Shortcut.bat

    WHAT IT CHANGES. Nothing on the drive. Everything it writes goes on the
    COMPUTER: a .lnk on the desktop or in the Start Menu, and a .ico in the
    user's own app-data folder. Deleting either is safe and undoes it.
#>

[CmdletBinding()]
param()

Set-StrictMode -Off
$ErrorActionPreference = 'Continue'

# This script lives in <RetroBat>\_Wizard\Program\scripts\
$Root = Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent

function Fail([string]$why) {
    Write-Host ''
    Write-Host ('  ' + $why) -ForegroundColor Yellow
    Write-Host ''
    exit 1
}

foreach ($lib in @('ShortcutMaker.ps1', 'ShortcutMakerUI.ps1')) {
    $p = Join-Path $PSScriptRoot $lib
    if (-not (Test-Path -LiteralPath $p)) { Fail ("Could not find $lib in the scripts folder, so this cannot run.") }
    try { . $p }
    catch { Fail ("Could not load ${lib}: " + $_.Exception.Message) }
}

# The Start Menu folder is named after the drive, the same single line in
# wizard.ini that names everything else, so a renamed drive renames this too.
$folder = 'RetroBat Games'
try {
    $ini = Join-Path $Root '_Wizard\Settings\wizard.ini'
    if (Test-Path -LiteralPath $ini) {
        foreach ($line in [System.IO.File]::ReadAllLines($ini)) {
            $t = $line.Trim()
            if ($t -match '^name\s*=\s*(.+)$') { $folder = ($Matches[1].Trim() + ' Games'); break }
        }
    }
}
catch { }

Write-Host ''
Write-Host '  Opening the shortcut window...' -ForegroundColor Gray

$r = Show-ShortcutMakerWindow -Root $Root -StartMenuFolder $folder

if ($r -eq 'made') { Write-Host '  Shortcut made.' -ForegroundColor Green }
else { Write-Host '  Nothing was made.' -ForegroundColor Gray }
Write-Host ''
