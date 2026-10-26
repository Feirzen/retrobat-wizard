# Separate saves per person: SocialEngine Switch-SocialPerson / Switch-SocialSaves.
# Rebuilt 2026-10-25 after two switches ran at once on Steven's drive: these
# tests include that exact case (two programs switching at the same moment).
param([string]$Scripts = '/home/claude/work/new/_ClaudeWorkspace/scripts')
$ErrorActionPreference = 'Stop'
. (Join-Path $Scripts 'SocialEngine.ps1')
$script:SocialRunningOverride = { $false }
$pass = 0; $fail = 0
function Check([string]$n, [bool]$ok) { if ($ok) { $script:pass++ } else { $script:fail++; Write-Host "FAIL: $n" } }
function Put([string]$p, [string]$t) { New-Item -ItemType Directory -Path (Split-Path $p -Parent) -Force | Out-Null; [System.IO.File]::WriteAllText($p, $t) }
function Txt([string]$p) { if (Test-Path -LiteralPath $p) { return [System.IO.File]::ReadAllText($p) } else { return '<none>' } }
function Count([string]$d) { if (-not (Test-Path $d)) { return 0 }; return @(Get-ChildItem -LiteralPath $d -Recurse -File).Count }
function Owner { return (Get-SocialSavesOwner $Ws) }

$T = Join-Path ([System.IO.Path]::GetTempPath()) ('ss-' + [guid]::NewGuid().ToString('N'))
$Root = $T; $Ws = Join-Path $T '_ClaudeWorkspace'
New-Item -ItemType Directory -Path $Ws -Force | Out-Null
$S = Join-Path $Root 'saves'
# held back for 3.1: off unless features.ini says on
Check 'off by default' (-not (Test-SocialSeparateSaves $Ws))
[System.IO.File]::WriteAllText((Join-Path $Ws 'features.ini'), "separatesaves = on`n")
Put "$S/snes/zelda.srm" 'steven zelda'
Put "$S/n64/oot.eep" 'steven oot'
New-Item -ItemType Directory -Path "$S/nes" -Force | Out-Null     # an empty console folder
Put "$S/wii/dolphin-emu/User/Wii/title/00010000/RMGE/data/save.bin" 'steven galaxy'
Put "$S/wii/dolphin-emu/User/Wii/title/00000001/00000002/content/title.tmd" 'WII MENU'
Put "$S/wii/dolphin-emu/User/Wii/shared2/sys/SYSCONF" 'wii settings'
Put "$S/wiiu/cemu/mlc01/usr/save/00050000/101c9400/user/80000001/save.dat" 'steven mk8'
Put "$S/wiiu/cemu/mlc01/usr/title/00050000/101c9400/content/big.bin" 'MK8 UPDATE'
Put "$S/3ds/azahar/sdmc/Nintendo 3DS/x/save" 'shared 3ds'
# whoever played last owns what is in place, the first time
Put "$Ws/profile/play/open.txt" "id = steven1`n"
$all0 = Count $S

# 1. steven -> friend
Check 'switched' ((Switch-SocialPerson $Root $Ws 'friend22') -eq 'switched')
Check 'owner now friend' ((Owner) -eq 'friend22')
Check 'friend has no zelda' ((Txt "$S/snes/zelda.srm") -eq '<none>')
Check 'snes folder still there (empty)' (Test-Path "$S/snes")
Check 'empty nes folder left alone' ((Test-Path "$S/nes") -and -not (Test-Path "$Ws/profile/saves-of/steven1/nes"))
Check 'friend has no galaxy save' (-not (Test-Path "$S/wii/dolphin-emu/User/Wii/title/00010000/RMGE"))
Check 'Wii Menu stays' ((Txt "$S/wii/dolphin-emu/User/Wii/title/00000001/00000002/content/title.tmd") -eq 'WII MENU')
Check 'Wii settings stay' ((Txt "$S/wii/dolphin-emu/User/Wii/shared2/sys/SYSCONF") -eq 'wii settings')
Check 'Wii U update stays' ((Txt "$S/wiiu/cemu/mlc01/usr/title/00050000/101c9400/content/big.bin") -eq 'MK8 UPDATE')
Check 'friend has no mk8 save' (-not (Test-Path "$S/wiiu/cemu/mlc01/usr/save/00050000/101c9400"))
Check '3ds shared' ((Txt "$S/3ds/azahar/sdmc/Nintendo 3DS/x/save") -eq 'shared 3ds')
Check 'steven kept aside' ((Txt "$Ws/profile/saves-of/steven1/snes/zelda.srm") -eq 'steven zelda')
Check 'no journal left' (-not (Test-Path "$Ws/profile/saves-of/switch.txt"))
Check 'nothing set aside as .kept' (@(Get-ChildItem -LiteralPath $S -Recurse -Directory | Where-Object { $_.Name -match '\.kept-' }).Count -eq 0)
Check 'same again: nothing' ((Switch-SocialPerson $Root $Ws 'friend22') -eq 'same')
# friend plays
Put "$S/snes/zelda.srm" 'friend zelda'
Put "$S/gba/pokemon.sav" 'friend pokemon'

# 2. friend -> steven
Check 'back to steven' ((Switch-SocialPerson $Root $Ws 'steven1') -eq 'switched')
Check 'steven zelda back' ((Txt "$S/snes/zelda.srm") -eq 'steven zelda')
Check 'steven oot back' ((Txt "$S/n64/oot.eep") -eq 'steven oot')
Check 'steven galaxy back' ((Txt "$S/wii/dolphin-emu/User/Wii/title/00010000/RMGE/data/save.bin") -eq 'steven galaxy')
Check 'steven mk8 back' ((Txt "$S/wiiu/cemu/mlc01/usr/save/00050000/101c9400/user/80000001/save.dat") -eq 'steven mk8')
Check 'friend pokemon not here' ((Txt "$S/gba/pokemon.sav") -eq '<none>')
Check 'friend saves kept' ((Txt "$Ws/profile/saves-of/friend22/snes/zelda.srm") -eq 'friend zelda' -and (Txt "$Ws/profile/saves-of/friend22/gba/pokemon.sav") -eq 'friend pokemon')

# 3. guest changes nothing
Check 'guest: skip' ((Switch-SocialPerson $Root $Ws 'guest') -eq 'skip')
Check 'guest: owner unchanged' ((Owner) -eq 'steven1')

# 4. reading play time never moves saves (that ran two switches at once)
[void](Update-SocialPlayLedger $Root $Ws 'friend22')
Check 'ledger alone: steven still in place' ((Txt "$S/snes/zelda.srm") -eq 'steven zelda' -and (Owner) -eq 'steven1')
[void](Update-SocialPlayLedger $Root $Ws 'friend22' -Switch)
Check 'ledger -Switch: friend in place' ((Txt "$S/snes/zelda.srm") -eq 'friend zelda' -and (Owner) -eq 'friend22')
[void](Switch-SocialPerson $Root $Ws 'steven1')

# 6. a cut-short switch is finished next time
$j = Join-Path $Ws 'profile/saves-of/switch.txt'
Move-Item "$S/n64" "$Ws/profile/saves-of/steven1/n64"     # as if the power went right after the first move
[System.IO.File]::WriteAllLines($j, [string[]]@('; test', ("$S/n64|$Ws/profile/saves-of/steven1/n64"), ("mkdir|$S/n64")))
Check 'resume: same person' ((Switch-SocialPerson $Root $Ws 'steven1') -eq 'same')
Check 'resumed: journal gone' (-not (Test-Path $j))
Check 'resumed: n64 folder made' (Test-Path "$S/n64")
Move-Item "$Ws/profile/saves-of/steven1/n64/oot.eep" "$S/n64/oot.eep"

# 8. RetroBat open: nothing moves
$script:SocialRunningOverride = { $true }
Check 'RetroBat open: skip' ((Switch-SocialPerson $Root $Ws 'friend22') -eq 'skip')
$script:SocialRunningOverride = { $false }

# 9. THE INCIDENT: two programs switch at the very same moment
$before = Count $S
$job = {
    param($lib, $Root, $Ws, $to)
    . $lib; $script:SocialRunningOverride = { $false }
    Switch-SocialPerson $Root $Ws $to
}
$lib = Join-Path $Scripts 'SocialEngine.ps1'
for ($round = 0; $round -lt 4; $round++) {
    $to = $(if ($round % 2 -eq 0) { 'friend22' } else { 'steven1' })
    $j1 = Start-Job -ScriptBlock $job -ArgumentList $lib, $Root, $Ws, $to
    $j2 = Start-Job -ScriptBlock $job -ArgumentList $lib, $Root, $Ws, $to
    $r1 = Receive-Job $j1 -Wait -AutoRemoveJob; $r2 = Receive-Job $j2 -Wait -AutoRemoveJob
    Check "round $round : exactly one switched ($r1 / $r2)" (@(@($r1, $r2) | Where-Object { $_ -eq 'switched' }).Count -eq 1)
    Check "round $round : owner is $to" ((Owner) -eq $to)
}
Check 'after the race: steven zelda in place' ((Txt "$S/snes/zelda.srm") -eq 'steven zelda')
Check 'after the race: galaxy in place' ((Txt "$S/wii/dolphin-emu/User/Wii/title/00010000/RMGE/data/save.bin") -eq 'steven galaxy')
Check 'after the race: friend pokemon kept' ((Txt "$Ws/profile/saves-of/friend22/gba/pokemon.sav") -eq 'friend pokemon')
Check 'after the race: no .kept anywhere' (@(Get-ChildItem -LiteralPath $T -Recurse -Directory | Where-Object { $_.Name -match '\.kept-' }).Count -eq 0)
Check 'after the race: no journal' (-not (Test-Path (Join-Path $Ws 'profile/saves-of/switch.txt')))

# 7. switched off: favourites only, saves stay
[System.IO.File]::WriteAllText((Join-Path $Ws 'features.ini'), "separatesaves = off`n")
Check 'off: switched (stars)' ((Switch-SocialPerson $Root $Ws 'friend22') -eq 'switched')
Check 'off: steven zelda stays' ((Txt "$S/snes/zelda.srm") -eq 'steven zelda')
[System.IO.File]::WriteAllText((Join-Path $Ws 'features.ini'), "separatesaves = on`n")
[void](Switch-SocialPerson $Root $Ws 'steven1')

# 5. a folder with saves in it is never put aside or replaced
Put "$Ws/profile/saves-of/steven1/snes/stray.srm" 'stray'     # should not happen, but if it does
[void](Switch-SocialPerson $Root $Ws 'friend22')
Check 'stray kept, steven zelda not lost' ((Txt "$Ws/profile/saves-of/steven1/snes/stray.srm") -eq 'stray' -and (Txt "$S/snes/zelda.srm") -eq 'steven zelda')
Check 'still no .kept anywhere' (@(Get-ChildItem -LiteralPath $T -Recurse -Directory | Where-Object { $_.Name -match '\.kept-' }).Count -eq 0)

Remove-Item $T -Recurse -Force
Write-Host ("separate saves tests: {0} passed, {1} failed" -f $pass, $fail)
if ($fail -gt 0) { exit 1 }
