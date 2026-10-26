<#
    Show-ConnectSteam.ps1
    ---------------------------------------------------------------------------
    Opens the Connect Steam window, or with -Disconnect the Disconnect Steam
    window. This is the console front end: the wizard's Machine tab calls the
    same two functions directly, so if the wizard ever breaks, both windows are
    still reachable from a .bat.

    Run it from:  Buttons\Connect Steam.bat

    WHAT IT CHANGES. Connect writes a [steam] section into THIS computer's
    machine profile, and adds this drive to Steam's list of game folders on
    this computer (after backing that list up). Nothing else on the drive is
    touched. Disconnect undoes whichever parts you tick.
#>

[CmdletBinding()]
param(
    [switch]$Disconnect
)

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

# --- load the engines, loudly rather than silently -------------------------
# A missing file here is worth a plain sentence, not a stack trace: whoever is
# reading it may have no idea what a dot-source is.
foreach ($lib in @('SteamEngine.ps1', 'ProfileEngine.ps1', 'SteamUI.ps1')) {
    $p = Join-Path $PSScriptRoot $lib
    if (-not (Test-Path -LiteralPath $p)) { Fail ("Could not find $lib in the scripts folder, so this cannot run.") }
    try { . $p }
    catch { Fail ("Could not load ${lib}: " + $_.Exception.Message) }
}

# --- RetroBat has to be closed ---------------------------------------------
# EmulationStation only reads roms\windows when it starts, so tiles written
# underneath a running RetroBat would not show until it was restarted anyway,
# and the confusion that causes is worse than the wait.
$running = Get-Process -Name 'emulationstation', 'RetroBat', 'BatGui' -ErrorAction SilentlyContinue
if ($null -ne $running) {
    Write-Host ''
    Write-Host '  Close RetroBat first.' -ForegroundColor Yellow
    Write-Host ''
    Write-Host '  RetroBat only reads its game list when it starts, so any tiles added' -ForegroundColor Gray
    Write-Host '  now would not appear until it was closed and opened again.' -ForegroundColor Gray
    Write-Host ''
    exit 1
}

if ($Disconnect) {
    Write-Host ''
    Write-Host '  Opening the Disconnect Steam window...' -ForegroundColor Gray
    $r = Show-DisconnectSteamWindow -Root $Root
    if ($r -eq 'disconnected') { Write-Host '  Done.' -ForegroundColor Green }
    else { Write-Host '  Nothing was changed.' -ForegroundColor Gray }
    Write-Host ''
    exit 0
}

Write-Host ''
Write-Host '  Opening the Connect Steam window...' -ForegroundColor Gray
$r = Show-ConnectSteamWindow -Root $Root

switch ($r) {
    'connected'      { Write-Host '  Steam is connected on this computer.' -ForegroundColor Green }
    'nothing to do'  { Write-Host '  There are no Steam games on this drive yet.' -ForegroundColor Yellow }
    default          { Write-Host '  Cancelled. Nothing was changed.' -ForegroundColor Gray }
}
Write-Host ''
