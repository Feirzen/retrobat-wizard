<#
    Show-Steam.ps1
    ---------------------------------------------------------------------------
    Prints what this drive knows about Steam on the computer it is plugged
    into. READ ONLY. It writes nothing, changes nothing, and closes nothing.
    Safe to run at any time, including while Steam and RetroBat are both open.

    It is the console front end for SteamEngine.ps1, so if the wizard's window
    ever breaks, everything underneath can still be checked from here.

    Run it from:  Maintenance Steps\Show My Steam Games.bat
#>

[CmdletBinding()]
param()

Set-StrictMode -Off
$ErrorActionPreference = 'Continue'

# This script lives in <RetroBat>\_Wizard\Program\scripts\
$Root = Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent

. (Join-Path $PSScriptRoot 'SteamEngine.ps1')
$profileEngine = Join-Path $PSScriptRoot 'ProfileEngine.ps1'
if (Test-Path -LiteralPath $profileEngine) { . $profileEngine }

function Line([string]$label, [string]$value, [string]$colour = 'Gray') {
    Write-Host ('  {0,-26}' -f ($label + ':')) -NoNewline -ForegroundColor DarkGray
    Write-Host $value -ForegroundColor $colour
}

function Head([string]$text) {
    Write-Host ''
    Write-Host ('  ' + $text) -ForegroundColor Cyan
    Write-Host ('  ' + ('-' * $text.Length)) -ForegroundColor DarkGray
}

Write-Host ''
Write-Host '  STEAM ON THIS COMPUTER' -ForegroundColor White

# --- this computer ---------------------------------------------------------
Head 'The computer'

Line 'Computer name' ([string]$env:COMPUTERNAME)

$steamRoot = Get-SteamRootOnComputer -Root $Root
if ($steamRoot -eq '') {
    Line 'Steam installed' 'NO' 'Yellow'
    Write-Host '                              Connect Steam can install it from this drive.' -ForegroundColor DarkGray
}
else {
    Line 'Steam installed' 'yes' 'Green'
    Line 'Steam folder' $steamRoot
}

if (Test-SteamRunning) { Line 'Steam running' 'yes' } else { Line 'Steam running' 'no' }

$user = Get-SteamLoginUser -Root $Root
if ($user.Account -eq '') {
    Line 'Signed in as' 'nobody' 'Yellow'
}
else {
    $who = $user.Account
    if ($user.Persona -ne '') { $who = $user.Persona + '  (' + $user.Account + ')' }
    Line 'Signed in as' $who 'Green'
}

# --- this drive ------------------------------------------------------------
Head 'The drive'

$lib = Get-SteamDriveLibrary -Root $Root
if ($lib -eq '') {
    Line 'Steam games folder' 'not found' 'Yellow'
    Write-Host '                              Expected a SteamLibrary folder beside RetroBat.' -ForegroundColor DarkGray
    Write-Host '                              Add this drive in Steam > Settings > Storage,' -ForegroundColor DarkGray
    Write-Host '                              then Move games onto it.' -ForegroundColor DarkGray
}
else {
    Line 'Steam games folder' $lib 'Green'

    if ($steamRoot -ne '') {
        if (Test-SteamLibraryRegistered -SteamRoot $steamRoot -LibraryPath $lib) {
            Line 'Steam knows about it' 'yes' 'Green'
        }
        else {
            Line 'Steam knows about it' 'NO - games will not launch' 'Yellow'
        }
    }
}

# --- the games -------------------------------------------------------------
Head 'The games'

$games = Get-SteamGamesOnDrive -Root $Root
if ($games.Count -eq 0) {
    Write-Host '  No Steam games are installed on this drive yet.' -ForegroundColor Yellow
}
else {
    $ready = @($games | Where-Object { $_.Installed })
    $busy  = @($games | Where-Object { -not $_.Installed })

    $patterns = @(Get-SteamHiddenPatterns -Root $Root)

    Write-Host ('  {0} of {1} finished downloading.' -f $ready.Count, $games.Count) -ForegroundColor Gray
    Write-Host ''

    foreach ($g in $ready) {
        if (Test-SteamGameHidden -Name $g.Name -Patterns $patterns) {
            Write-Host '    [kept out]  ' -NoNewline -ForegroundColor DarkCyan
            Write-Host ('{0,-40} {1}' -f $g.Name, $g.AppId) -ForegroundColor DarkGray
        }
        else {
            Write-Host '    [ready]     ' -NoNewline -ForegroundColor Green
            Write-Host ('{0,-40} {1}' -f $g.Name, $g.AppId) -ForegroundColor Gray
        }
    }
    foreach ($g in $busy) {
        Write-Host '    [not yet]   ' -NoNewline -ForegroundColor DarkYellow
        Write-Host ('{0,-40} {1}' -f $g.Name, $g.AppId) -ForegroundColor DarkGray
    }

    $keptOut = @($ready | Where-Object { Test-SteamGameHidden -Name $_.Name -Patterns $patterns })
    if ($keptOut.Count -gt 0) {
        Write-Host ''
        Write-Host ('  [kept out] means installed and working, but deliberately given no tile.') -ForegroundColor DarkGray
        Write-Host ('  Edit _Wizard\Settings\computers\steam-hidden.txt to change that.') -ForegroundColor DarkGray
    }
}

# --- the setting that decides whether they show ----------------------------
Head 'Shown in RetroBat on this computer'

$state = Get-SteamProfileState -Root $Root
if ($state.ProfileFile -eq '') {
    Line 'Profile' 'none for this computer yet' 'Yellow'
    Write-Host '                              Run SETUP RETROBAT once and it makes one.' -ForegroundColor DarkGray
}
else {
    Line 'Profile' $state.ProfileName
    if ($state.Connected) {
        Line 'Steam connected' 'yes' 'Green'
        if ($state.Account -ne '') { Line 'Connected as' $state.Account }
    }
    else {
        Line 'Steam connected' 'no - no Steam tiles here' 'Yellow'
    }
    Write-Host ('                              set in {0}' -f (Split-Path $state.ProfileFile -Leaf)) -ForegroundColor DarkGray
}

$romsDir = Join-Path $Root 'roms\steam'
$tiles = @()
if (Test-Path -LiteralPath $romsDir) {
    $tiles = @(Get-ChildItem -LiteralPath $romsDir -Filter '*.url' -File -ErrorAction SilentlyContinue |
               Where-Object { Test-OurSteamShortcut -Path $_.FullName })
}
Line 'Tiles in RetroBat now' ([string]$tiles.Count)
Line 'They live in' 'roms\steam  (the Steam shelf)'

$parked = Join-Path $Root '_Wizard\Settings\steam\parked'
if (Test-Path -LiteralPath $parked) {
    $p = @(Get-ChildItem -LiteralPath $parked -Filter '*.url' -File -ErrorAction SilentlyContinue)
    if ($p.Count -gt 0) { Line 'Tiles parked (hidden)' ([string]$p.Count) }
}

# --- what would happen if the tiles were rebuilt ---------------------------
Head 'What a rebuild would do'

$wouldShow = 0
if ($state.Connected) {
    $pats = @(Get-SteamHiddenPatterns -Root $Root)
    $wouldShow = @($games | Where-Object { $_.Installed -and -not (Test-SteamGameHidden -Name $_.Name -Patterns $pats) }).Count
}

if ($state.Connected) {
    Write-Host ('  Show {0} game tile(s) in RetroBat.' -f $wouldShow) -ForegroundColor Gray
}
else {
    Write-Host '  Hide every Steam tile, because Steam is not connected on this' -ForegroundColor Gray
    Write-Host '  computer. Run Connect Steam to change that.' -ForegroundColor Gray
}

Write-Host ''
Write-Host '  Nothing was changed. This only looks.' -ForegroundColor DarkGray
Write-Host ''
