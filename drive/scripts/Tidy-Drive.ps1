<#
    Tidy-Drive.ps1 - the one-time clean-up of old backups and leftovers
    (Steven, 2026-10-13: "strip down all the extra stuff so the plumbing is
    solid and clear"). Run from Maintenance Steps\Tidy The Drive.bat.

    WHAT IT DELETES - only things nothing on the drive uses any more:
      * _ClaudeWorkspace\_SAFE TO DELETE   (the scripts make it again when
        they need it)
      * archive\ the "original" copies of videos and loading screens made
        before their volume was evened out
      * archive\ repeated dated backups of the same thing: the newest TWO of
        each kind are kept (settings_, steam-gamelist_, portability-fix_,
        protected-files_, emuconfig_, padtokey_, netplay_)
      * _ClaudeWorkspace\SteamArtworkDebug (made again if ever needed)
      * library-to-publish\star-fox-assault (Steven's call, 2026-10-13)
      * RetroBat\Claude outputs (old notes; the current ones are in docs\)
      * RetroBat\PowerShell Custom Themes (empty)
      * the old one-time Wii U test in game-start\zz-wiiu-chooser-test.bat
      * the online Poptropica on the Windows shelf and its pictures
        (Steven, 2026-10-14: it lands on an ad site, not the game)
      * wizard\profile-wiimote.png, the broken Wii Remote profile picture
      * the v3 test button and test copy, and the unused icon-potions pictures

    WHAT IT NEVER TOUCHES: archive\quarantined-savestates (the Saves tab's
    "jump in" states), decorations-hidden, the Wii NAND and Cemu key backups,
    update-restore-off, every save, every game, every setting.

    It lists everything with sizes first and does nothing until Y is typed.
    It refuses to run while RetroBat is open. A record goes in
    wizard\tidy.log. ASCII only, Windows PowerShell 5.1, no drive letters.
#>
$ErrorActionPreference = 'Continue'
$Ws   = Split-Path -Parent $PSScriptRoot
$Root = Split-Path -Parent $Ws
$log  = Join-Path $Ws 'wizard\tidy.log'
function Say([string]$t, [string]$c = 'Gray') { Write-Host $t -ForegroundColor $c }
function Get-Size([string]$p) {
    try {
        if (Test-Path -LiteralPath $p -PathType Leaf) { return (Get-Item -LiteralPath $p).Length }
        $s = (Get-ChildItem -LiteralPath $p -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
        if ($null -eq $s) { return 0 } else { return [long]$s }
    } catch { return 0 }
}
function Fmt([long]$b) { if ($b -ge 1GB) { '{0:N1} GB' -f ($b / 1GB) } elseif ($b -ge 1MB) { '{0:N0} MB' -f ($b / 1MB) } else { '{0:N0} KB' -f ($b / 1KB) } }

Say ''
Say '  TIDY THE DRIVE' 'White'
Say '  ------------------------------------------------------------'
if ($null -ne (Get-Process -Name 'emulationstation', 'RetroBat' -ErrorAction SilentlyContinue)) {
    Say '  RetroBat is open. Close it first, then run this again.' 'Yellow'
    Read-Host '  Press Enter to close' | Out-Null; exit 1
}
Say '  Looking...'

$list = New-Object System.Collections.ArrayList
function Add-Item([string]$Path, [string]$Why) {
    if (Test-Path -LiteralPath $Path) { [void]$list.Add([pscustomobject]@{ Path = $Path; Why = $Why; Size = (Get-Size $Path) }) }
}

Add-Item (Join-Path $Ws '_SAFE TO DELETE') 'already marked safe to delete'
Add-Item (Join-Path $Ws 'SteamArtworkDebug') 'old debug notes'
Add-Item (Join-Path $Ws 'library-to-publish\star-fox-assault') 'the Star Fox remake, retired'
Add-Item (Join-Path $Root 'Claude outputs') 'old notes (current ones are in docs)'
Add-Item (Join-Path $Root 'PowerShell Custom Themes') 'empty, no longer used'
Add-Item (Join-Path $Root 'emulationstation\.emulationstation\scripts\game-start\zz-wiiu-chooser-test.bat') 'old one-time test'
Add-Item (Join-Path $Root 'roms\windows\Poptropica.bat') 'online Poptropica, retired (an ad site, not the game)'
Add-Item (Join-Path $Ws 'wizard\profile-wiimote.png') 'the broken Wii Remote profile picture (no longer offered)'
Add-Item (Join-Path $Ws 'Try the new wizard look.vbs') 'the v3 test button (v3 is THE wizard now)'
Add-Item (Join-Path $Ws 'wizard\SetupWizard-v3.ps1') 'the v3 test copy (now wizard\SetupWizard.ps1)'
Add-Item (Join-Path $Ws 'wizard\icon-potions.png') 'a picture no longer used (the original potions came back)'
Add-Item (Join-Path $Ws 'wizard\icon-potions-anim.png') 'a picture no longer used'
foreach ($pic in @(Get-ChildItem -LiteralPath (Join-Path $Root 'roms\windows\images') -Filter 'Poptropica*' -File -ErrorAction SilentlyContinue)) {
    Add-Item $pic.FullName 'picture for the retired online Poptropica'
}

$arch = Join-Path $Ws 'archive'
if (Test-Path -LiteralPath $arch) {
    $dirs = @(Get-ChildItem -LiteralPath $arch -Directory -ErrorAction SilentlyContinue)
    foreach ($d in $dirs) {
        if ($d.Name -match '^(game|menu|intro)videos-original-|^loadingscreens-original-') { Add-Item $d.FullName 'original videos from before the volume fix' }
    }
    foreach ($series in @('settings_', 'steam-gamelist_', 'portability-fix_', 'protected-files_', 'emuconfig_', 'padtokey_', 'netplay_')) {
        $same = @($dirs | Where-Object { $_.Name.StartsWith($series) } | Sort-Object Name -Descending)
        if ($same.Count -le 2) { continue }
        foreach ($d in $same[2..($same.Count - 1)]) { Add-Item $d.FullName ('older ' + $series.TrimEnd('_') + ' backup (newest two kept)') }
    }
}

if ($list.Count -eq 0) { Say '  Nothing to tidy. The drive is already clean.' 'Green'; Read-Host '  Press Enter to close' | Out-Null; exit 0 }

$total = [long]0
Say ''
foreach ($i in $list) {
    $total += $i.Size
    $shown = $i.Path.Substring($Root.Length).TrimStart('\')
    Say ('  {0,9}   {1}' -f (Fmt $i.Size), $shown) 'White'
    Say ('              ' + $i.Why) 'DarkGray'
}
Say ''
Say ('  {0} item(s), {1} in all, will be DELETED for good.' -f $list.Count, (Fmt $total)) 'Yellow'
Say '  Saves, games, settings and the Saves tab''s save states are not touched.' 'Gray'
Say ''
$a = Read-Host '  Type Y and press Enter to delete them (anything else cancels)'
if ($a -notmatch '^[Yy]') { Say '  Cancelled. Nothing was changed.' 'Green'; Read-Host '  Press Enter to close' | Out-Null; exit 0 }

$done = 0; $freed = [long]0; $failed = @()
foreach ($i in $list) {
    try {
        Remove-Item -LiteralPath $i.Path -Recurse -Force -ErrorAction Stop
        $done++; $freed += $i.Size
    } catch { $failed += ($i.Path + ' - ' + $_.Exception.Message) }
}
Say ''
Say ('  Done: {0} item(s) deleted, {1} freed.' -f $done, (Fmt $freed)) 'Green'
foreach ($f in $failed) { Say ('  Could not delete: ' + $f) 'Yellow' }
try {
    $lines = @((Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + ('  tidy: {0} deleted, {1} freed' -f $done, (Fmt $freed))) + @($list | ForEach-Object { '    ' + $_.Path }) + @($failed | ForEach-Object { '    FAILED ' + $_ })
    [System.IO.File]::AppendAllText($log, (($lines -join "`r`n") + "`r`n"))
} catch { }
Say ''
Read-Host '  Press Enter to close' | Out-Null
