# FamilyFilter.ps1 (2026-10-25): M-rated games hidden from RetroBat's lists.
param([string]$Scripts = (Join-Path $PSScriptRoot '../../drive/Program/scripts'))
$ErrorActionPreference = 'Stop'
. (Join-Path $Scripts 'FamilyFilter.ps1')
$pass = 0; $fail = 0
function Check([string]$n, [bool]$ok) { if ($ok) { $script:pass++ } else { $script:fail++; Write-Host "FAIL: $n" } }
function Put([string]$p, [string]$t) { New-Item -ItemType Directory -Path (Split-Path $p -Parent) -Force | Out-Null; [System.IO.File]::WriteAllText($p, $t) }
$Base = Join-Path ([System.IO.Path]::GetTempPath()) ('ff-' + [guid]::NewGuid().ToString('N'))
$Root = $Base; $Ws = Join-Path $Base '_Wizard'
Copy-Item -LiteralPath (Join-Path (Split-Path $Scripts -Parent) 'defaults') -Destination (Join-Path $Ws 'Program\defaults') -Recurse
# names, loosely
Check 'zelda style' ((ConvertTo-FfKey 'Legend of Zelda, The - Twilight Princess (USA) [!]') -eq (ConvertTo-FfKey 'The Legend of Zelda: Twilight Princess'))
Check 'file name' ((ConvertTo-FfKey 'Call of Duty - Black Ops II (USA) (En,Fr).wux') -eq 'call of duty black ops ii')
Check 'trademark' ((ConvertTo-FfKey ('HELLDIVERS' + [char]0x2122 + ' 2')) -eq 'helldivers 2')
$L = Get-FfList $Ws
Check 'list loaded' ($L.Exact.Count -gt 100 -and $L.Prefix.Count -gt 10)
Check 'cod bo2 mature' (Test-FfMature $L 'Call of Duty: Black Ops II')
Check 'by file name' (Test-FfMature $L '' './Call of Duty - Black Ops II (USA) (En,Fr).wux')
Check 'series prefix' (Test-FfMature $L 'Resident Evil 4: Wii Edition')
Check 'prefix needs a word break' (-not (Test-FfMature $L 'Resident Evilish Kart'))
Check 'mario kart fine' (-not (Test-FfMature $L 'Mario Kart 8'))
Check 'goldeneye (T) fine' (-not (Test-FfMature $L 'GoldenEye 007'))
Check 'bayonetta origins (E10) fine' (-not (Test-FfMature $L 'Bayonetta Origins: Cereza and the Lost Demon'))
Check 'steam url' (Test-FfMature $L '' ('./HELLDIVERS' + [char]0x2122 + ' 2.url'))
# game lists
Put "$Root/roms/wiiu/gamelist.xml" "<?xml version=`"1.0`"?>`r`n<gameList>`r`n`t<game>`r`n`t`t<path>./Call of Duty - Black Ops II (USA) (En,Fr).wux</path>`r`n`t`t<name>Call of Duty: Black Ops II</name>`r`n`t</game>`r`n`t<game>`r`n`t`t<path>./Mario Kart 8 (USA).wux</path>`r`n`t`t<name>Mario Kart 8</name>`r`n`t</game>`r`n`t<game>`r`n`t`t<path>./Yoshi.wux</path>`r`n`t`t<name>Yoshi's Woolly World</name>`r`n`t`t<hidden>true</hidden>`r`n`t</game>`r`n</gameList>`r`n"
Put "$Root/emulationstation/.emulationstation/es_settings.cfg" "<?xml version=`"1.0`"?>`r`n<config>`r`n`t<bool name=`"ShowHiddenGames`" value=`"true`" />`r`n</config>`r`n"
$gl = "$Root/roms/wiiu/gamelist.xml"
$r = Sync-FamilyFilter $Root $Ws
Check 'off: nothing hidden' ($r.Hidden -eq 0 -and ([System.IO.File]::ReadAllText($gl) -split '<hidden>').Count -eq 2)
Put "$Ws/Settings/features.ini" "familyfilter = on`n"
$r = Sync-FamilyFilter $Root $Ws
$t = [System.IO.File]::ReadAllText($gl)
Check 'on: one hidden' ($r.Hidden -eq 1)
Check 'cod hidden' ($t -match '(?s)Black Ops II</name>\s*<hidden>true</hidden>\s*</game>')
Check 'mario not hidden' ($t -notmatch '(?s)Mario Kart 8</name>\s*<hidden>')
Check 'indent kept' ($t -match "`r`n`t`t<hidden>true</hidden>`r`n`t</game>")
Check 'xml still reads' ($null -ne ([xml]$t).gameList)
Check 'show hidden switched off' ([System.IO.File]::ReadAllText("$Root/emulationstation/.emulationstation/es_settings.cfg") -match 'ShowHiddenGames" value="false"')
Check 'recorded' ((Get-Content "$Ws/Settings/family-hidden.txt" -Raw) -match 'wiiu\|\./Call of Duty')
$r = Sync-FamilyFilter $Root $Ws
Check 'again: nothing new' ($r.Hidden -eq 0 -and ([System.IO.File]::ReadAllText($gl) -split '<hidden>').Count -eq 3)
# own list
Add-FfName $Ws "Yoshi's Woolly World"
Add-FfName $Ws 'Call of Duty: Black Ops II' $true
$r = Sync-FamilyFilter $Root $Ws
$t = [System.IO.File]::ReadAllText($gl)
Check 'let through: cod shown again' ($t -notmatch '(?s)Black Ops II</name>\s*<hidden>')
Check 'hand-hidden yoshi still hidden' ($t -match "(?s)Woolly World</name>\s*<hidden>true</hidden>")
# off: shows exactly what it hid
[System.IO.File]::WriteAllText("$Ws/Settings/family-hide.txt", "; mine`n")
Put "$Ws/Settings/features.ini" "familyfilter = on`n"
[void](Sync-FamilyFilter $Root $Ws)
Put "$Ws/Settings/features.ini" "familyfilter = off`n"
$r = Sync-FamilyFilter $Root $Ws
$t = [System.IO.File]::ReadAllText($gl)
Check 'off: cod shown' ($t -notmatch '(?s)Black Ops II</name>\s*<hidden>' -and $r.Shown -eq 1)
Check 'off: yoshi (hidden by hand) left hidden' ($t -match "(?s)Woolly World</name>\s*<hidden>true</hidden>")
Check 'off: record gone' (-not (Test-Path "$Ws/Settings/family-hidden.txt"))
$names = @(Get-FfDriveGameNames $Root)
Check 'search: names from the game lists, decoded' (@($names.Name) -contains "Yoshi's Woolly World" -and @($names.Name) -contains 'Call of Duty: Black Ops II')
Check 'search: console kept with each name' (@($names | Where-Object { $_.Name -eq 'Mario Kart 8' })[0].Console -eq 'wiiu')
Check 'search: no roms folder, empty list' (@(Get-FfDriveGameNames (Join-Path $Base 'nowhere')).Count -eq 0)
Remove-Item $Base -Recurse -Force
Write-Host ("family filter tests: {0} passed, {1} failed" -f $pass, $fail)
if ($fail -gt 0) { exit 1 }
