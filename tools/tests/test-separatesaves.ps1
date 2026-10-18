# Separate saves per person (2026-10-17): SocialEngine Switch-SocialSaves.
param([string]$Scripts = '/home/claude/work/new/_ClaudeWorkspace/scripts')
$ErrorActionPreference = 'Stop'
. (Join-Path $Scripts 'SocialEngine.ps1')
$script:SocialRunningOverride = { $false }
$pass = 0; $fail = 0
function Check([string]$n, [bool]$ok) { if ($ok) { $script:pass++ } else { $script:fail++; Write-Host "FAIL: $n" } }
function Put([string]$p, [string]$t) { New-Item -ItemType Directory -Path (Split-Path $p -Parent) -Force | Out-Null; [System.IO.File]::WriteAllText($p, $t) }
function Txt([string]$p) { if (Test-Path -LiteralPath $p) { return [System.IO.File]::ReadAllText($p) } else { return '<none>' } }
$T = Join-Path ([System.IO.Path]::GetTempPath()) ('ss-' + [guid]::NewGuid().ToString('N'))
$Root = $T; $Ws = Join-Path $T '_ClaudeWorkspace'
New-Item -ItemType Directory -Path $Ws -Force | Out-Null
$S = Join-Path $Root 'saves'
Put "$S/snes/zelda.srm" 'steven zelda'
Put "$S/wii/dolphin-emu/User/Wii/title/00010000/RMGE/data/save.bin" 'steven galaxy'
Put "$S/wii/dolphin-emu/User/Wii/title/00000001/00000002/content/title.tmd" 'WII MENU'
Put "$S/wii/dolphin-emu/User/Wii/shared2/sys/SYSCONF" 'wii settings'
Put "$S/wiiu/cemu/mlc01/usr/save/00050000/101c9400/user/80000001/save.dat" 'steven mk8'
Put "$S/wiiu/cemu/mlc01/usr/title/00050000/101c9400/content/big.bin" 'MK8 UPDATE'
Put "$S/3ds/azahar/sdmc/Nintendo 3DS/x/save" 'shared 3ds'
# 1. steven -> friend
Check 'switched' (Switch-SocialSaves $Root $Ws 'steven1' 'friend22')
Check 'friend has no zelda' ((Txt "$S/snes/zelda.srm") -eq '<none>')
Check 'snes folder still there (empty)' (Test-Path "$S/snes")
Check 'friend has no galaxy save' (-not (Test-Path "$S/wii/dolphin-emu/User/Wii/title/00010000/RMGE"))
Check 'Wii Menu stays' ((Txt "$S/wii/dolphin-emu/User/Wii/title/00000001/00000002/content/title.tmd") -eq 'WII MENU')
Check 'Wii settings stay' ((Txt "$S/wii/dolphin-emu/User/Wii/shared2/sys/SYSCONF") -eq 'wii settings')
Check 'Wii U update stays' ((Txt "$S/wiiu/cemu/mlc01/usr/title/00050000/101c9400/content/big.bin") -eq 'MK8 UPDATE')
Check 'friend has no mk8 save' (-not (Test-Path "$S/wiiu/cemu/mlc01/usr/save/00050000/101c9400"))
Check '3ds shared' ((Txt "$S/3ds/azahar/sdmc/Nintendo 3DS/x/save") -eq 'shared 3ds')
Check 'steven kept aside' ((Txt "$Ws/profile/saves-of/steven1/snes/zelda.srm") -eq 'steven zelda')
Check 'no journal left' (-not (Test-Path "$Ws/profile/saves-of/switch.txt"))
# friend plays
Put "$S/snes/zelda.srm" 'friend zelda'
Put "$S/gba/pokemon.sav" 'friend pokemon'
# 2. friend -> steven
$null = Switch-SocialSaves $Root $Ws 'friend22' 'steven1'
Check 'steven zelda back' ((Txt "$S/snes/zelda.srm") -eq 'steven zelda')
Check 'steven galaxy back' ((Txt "$S/wii/dolphin-emu/User/Wii/title/00010000/RMGE/data/save.bin") -eq 'steven galaxy')
Check 'steven mk8 back' ((Txt "$S/wiiu/cemu/mlc01/usr/save/00050000/101c9400/user/80000001/save.dat") -eq 'steven mk8')
Check 'friend pokemon not here' ((Txt "$S/gba/pokemon.sav") -eq '<none>')
Check 'friend saves kept' ((Txt "$Ws/profile/saves-of/friend22/snes/zelda.srm") -eq 'friend zelda' -and (Txt "$Ws/profile/saves-of/friend22/gba/pokemon.sav") -eq 'friend pokemon')
# 3. back to friend: their own again
$null = Switch-SocialSaves $Root $Ws 'steven1' 'friend22'
Check 'friend zelda back' ((Txt "$S/snes/zelda.srm") -eq 'friend zelda')
Check 'friend pokemon back' ((Txt "$S/gba/pokemon.sav") -eq 'friend pokemon')
# 4. guest changes nothing
Check 'guest: no switch' (-not (Switch-SocialSaves $Root $Ws 'friend22' 'guest'))
# 5. a cut-short switch is finished next time
$null = Switch-SocialSaves $Root $Ws 'friend22' 'steven1'
$j = Join-Path $Ws 'profile/saves-of/switch.txt'
Move-Item "$S/snes" "$Ws/profile/saves-of/steven1/snes"     # as if the power went right after the first move
[System.IO.File]::WriteAllLines($j, [string[]]@('; test', ("$S/snes|$Ws/profile/saves-of/steven1/snes"), ("$Ws/profile/saves-of/friend22/snes|$S/snes")))
$null = Switch-SocialSaves $Root $Ws 'steven1' 'steven1'
Check 'resumed: friend snes in place' ((Txt "$S/snes/zelda.srm") -eq 'friend zelda')
Check 'resumed: journal gone' (-not (Test-Path $j))
# 6. switched off: nothing moves
[System.IO.File]::WriteAllText((Join-Path $Ws 'features.ini'), "separatesaves = off`n")
Check 'off: no switch' (-not (Switch-SocialSaves $Root $Ws 'steven1' 'friend22'))
# 7. RetroBat open: nothing moves
Remove-Item (Join-Path $Ws 'features.ini')
$script:SocialRunningOverride = { $true }
Check 'RetroBat open: no switch' (-not (Switch-SocialSaves $Root $Ws 'steven1' 'friend22'))
Remove-Item $T -Recurse -Force
Write-Host ("separate saves tests: {0} passed, {1} failed" -f $pass, $fail)
if ($fail -gt 0) { exit 1 }
