<#
    Show-FlashArtwork.ps1 - the console front end for
    Buttons\Get Flash Artwork.bat. See FlashArtwork.ps1.
    -Force fetches every picture again and replaces names and descriptions
    typed in by hand. ASCII ONLY, Windows PowerShell 5.1.
#>
param([switch]$Force)
$ErrorActionPreference = 'Continue'
$Ws = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$Root = Split-Path -Parent $Ws
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch { }

Write-Host ''
Write-Host '  NAMES AND PICTURES FOR THE FLASH AND BROWSER GAME SHELVES'
Write-Host '  ------------------------------------------------------------'
$busy = Get-Process -Name 'emulationstation', 'RetroBat' -ErrorAction SilentlyContinue
if ($null -ne $busy) {
    Write-Host '  RetroBat is open. Close it first: it rewrites the game list when it'
    Write-Host '  exits, which would throw away everything written here.'
    Write-Host ''
    Read-Host '  Press Enter to close' | Out-Null
    exit 1
}
. (Join-Path $PSScriptRoot 'SteamEngine.ps1')
. (Join-Path $PSScriptRoot 'SteamArtwork.ps1')
. (Join-Path $PSScriptRoot 'FlashArtwork.ps1')
$steamRoot = ''
try { $steamRoot = Get-SteamRootOnComputer -Root $Root } catch { }
Write-Host ('  Steam on this computer: ' + $(if ($steamRoot) { $steamRoot } else { 'not found (pictures come from the web)' }))
Write-Host '  Working...'
Write-Host ''
# 2026-10-13: the browser and online games on the Windows shelf too, from
# browser-games.ini, the same way.
foreach ($job in @(@('flash', 'flash-games.ini', 'FLASH'), @('windows', 'browser-games.ini', 'BROWSER AND ONLINE GAMES'))) {
    Write-Host ('  ' + $job[2])
    $r = Invoke-FlashArtwork -Root $Root -Force:([bool]$Force) -SteamRoot $steamRoot -System $job[0] -IniName $job[1]
    foreach ($l in @($r.Lines)) { Write-Host $l }
    Write-Host ('  ' + $r.Message)
    Write-Host ''
    try {
        $log = Join-Path $Ws 'Cache\logs\flash-artwork.log'
        $text = @((Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + '  ' + $job[0] + '  force=' + [bool]$Force) + @($r.Lines) + @('  ' + $r.Message, '')
        [System.IO.File]::AppendAllText($log, (($text -join "`r`n") + "`r`n"))
    } catch { }
}
Write-Host ''
Read-Host '  Press Enter to close' | Out-Null
