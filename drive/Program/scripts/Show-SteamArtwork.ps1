<#
    Show-SteamArtwork.ps1
    ---------------------------------------------------------------------------
    Fetches proper artwork and trailers for every Steam game on the shelf, from
    Steam itself, and writes them into the game list so RetroBat shows them.

    Run it from:  Maintenance Steps\Get Steam Artwork.bat

    WHY NOT JUST SCRAPE. RetroBat scrapes from ScreenScraper, a retro games
    database, which knows Wind Waker inside out and has never heard of a party
    game from last year. Steam obviously has perfect artwork for everything it
    sells, so for this one shelf it is the better source by a mile.

    IT IS SAFE TO RUN AS OFTEN AS YOU LIKE. Anything already downloaded is
    left alone, so a second run after buying two more games only fetches those
    two. gamelist.xml is backed up into the archive before every write, and
    nothing is ever deleted.

    -Force re-fetches everything, including overwriting any name or
    description that was typed by hand. Without it, a person's own words
    always win.

    RETROBAT MUST BE CLOSED. It rewrites gamelist.xml when it exits, which
    would throw away everything this just wrote.
#>

[CmdletBinding()]
param(
    [switch]$Force,
    [switch]$NoVideo,
    [string]$Only = ''
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

foreach ($lib in @('SteamEngine.ps1', 'SteamArtwork.ps1')) {
    $p = Join-Path $PSScriptRoot $lib
    if (-not (Test-Path -LiteralPath $p)) { Fail ("Could not find $lib in the scripts folder.") }
    try { . $p } catch { Fail ("Could not load ${lib}: " + $_.Exception.Message) }
}

if ($null -ne (Get-Process -Name 'emulationstation', 'RetroBat', 'BatGui' -ErrorAction SilentlyContinue)) {
    Write-Host ''
    Write-Host '  Close RetroBat first.' -ForegroundColor Yellow
    Write-Host ''
    Write-Host '  RetroBat rewrites the game list when it closes, which would throw' -ForegroundColor Gray
    Write-Host '  away everything this is about to write into it.' -ForegroundColor Gray
    Write-Host ''
    exit 1
}

Write-Host ''
Write-Host '  ARTWORK FOR THE STEAM SHELF' -ForegroundColor White
Write-Host ''

$steamRoot = Get-SteamRootOnComputer -Root $Root
if ($steamRoot -eq '') {
    Write-Host '  Steam is not installed on this computer, so its picture cache cannot' -ForegroundColor Yellow
    Write-Host '  be used. Everything will be downloaded instead, which still works.' -ForegroundColor Yellow
    Write-Host ''
}

# Only games that actually have a tile on THIS computer - the same list PLAY
# uses (Get-SteamWantedGames), so a friend's games are covered while the drive
# is at their place, and the Jackbox packs that steam-hidden.txt keeps out are
# never fetched for nothing. On a computer where Steam is not set up, fall
# back to every game on the drive, which is what this always did.
$games = @(Get-SteamWantedGames -Root $Root)
if ($games.Count -eq 0) {
    $patterns = @(Get-SteamHiddenPatterns -Root $Root)
    $games = @(Get-SteamGamesOnDrive -Root $Root |
               Where-Object { $_.Installed -and -not (Test-SteamGameHidden -Name $_.Name -Patterns $patterns) })
}

# While the store is being asked anyway, remember what kind of game each one
# is (couch multiplayer or not) for Steam setup's game picker.
try { [void](Update-SaGameInfoCache -Root $Root -Games $games) } catch { }

# -Only narrows it to one game, or a few. Part of a name is enough, and
# capitals do not matter, so "jackbox" finds The Jackbox Megapicker. Together
# with -Force this is how one game that came out wrong gets redone without
# touching the rest.
if ($Only -ne '') {
    $games = @($games | Where-Object { $_.Name -like ('*' + $Only + '*') })
    if ($games.Count -eq 0) {
        Write-Host ''
        Write-Host ("  Nothing on the shelf matches '" + $Only + "'.") -ForegroundColor Yellow
        Write-Host ''
        exit 0
    }
    Write-Host ("  Narrowed to '" + $Only + "'.") -ForegroundColor Cyan
}

if ($games.Count -eq 0) {
    Write-Host '  No Steam games have a tile on this drive yet.' -ForegroundColor Yellow
    Write-Host ''
    exit 0
}

Write-Host ("  {0} game(s) to look at." -f $games.Count) -ForegroundColor Gray
if ($Force) { Write-Host '  -Force: everything will be fetched again.' -ForegroundColor Yellow }
Write-Host ''

$results = @()
$n = 0

foreach ($g in $games) {
    $n++
    $tile = ConvertTo-SafeShortcutName -Name $g.Name

    Write-Host ('  [{0}/{1}] {2}' -f $n, $games.Count, $g.Name) -ForegroundColor White

    $r = Get-SaGameArtwork -Root $Root -SteamRoot $steamRoot -AppId $g.AppId -TileName $tile -Force:$Force -NoVideo:$NoVideo
    $results += $r

    if (@($r.Got).Count -gt 0)     { Write-Host ('          got:     ' + (($r.Got) -join ', ')) -ForegroundColor Green }
    if (@($r.Skipped).Count -gt 0) { Write-Host ('          had:     ' + (($r.Skipped) -join ', ')) -ForegroundColor DarkGray }
    if (@($r.Failed).Count -gt 0)  { Write-Host ('          missed:  ' + (($r.Failed) -join ', ')) -ForegroundColor DarkYellow }
    if ($null -eq $r.Info)         { Write-Host '          (no store information - pictures only)' -ForegroundColor DarkYellow }
    foreach ($note in @($r.Notes)) {
        # @($null) is ONE empty element, not none, so an unset Notes printed a
        # bare "why:" under every single game. Skip the blanks.
        if ([string]::IsNullOrWhiteSpace([string]$note)) { continue }
        Write-Host ('          why:     ' + $note) -ForegroundColor DarkGray
    }

    # Steam is generous but not infinitely so, and a hammered service starts
    # refusing. A breath between games costs nothing on a list this size.
    Start-Sleep -Milliseconds 400
}

Write-Host ''
Write-Host '  Writing the game list...' -ForegroundColor Gray
$u = Update-SaGameList -Root $Root -Results $results -Force:$Force
if ($u.Ok) { Write-Host ('  ' + $u.Message) -ForegroundColor Green }
else       { Write-Host ('  ' + $u.Message) -ForegroundColor Yellow }

$totalGot = 0
foreach ($r in $results) { $totalGot += @($r.Got).Count }

Write-Host ''
Write-Host ('  {0} new file(s) fetched.' -f $totalGot) -ForegroundColor White
Write-Host '  Open RetroBat and the Steam shelf should look a lot better.' -ForegroundColor Gray
Write-Host '  The new pictures also show up as icon choices in Add A Game Shortcut.' -ForegroundColor DarkGray
Write-Host ''
