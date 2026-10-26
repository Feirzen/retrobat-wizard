# Play time per person (2026-10-17): SocialEngine Update-SocialPlayLedger.
param([string]$Scripts = '/home/claude/work/new/_ClaudeWorkspace/scripts')
$ErrorActionPreference = 'Stop'
. (Join-Path $Scripts 'SocialEngine.ps1')
$pass = 0; $fail = 0
function Check([string]$n, [bool]$ok) { if ($ok) { $script:pass++ } else { $script:fail++; Write-Host "FAIL: $n" } }
$T = Join-Path ([System.IO.Path]::GetTempPath()) ('pt-' + [guid]::NewGuid().ToString('N'))
$Root = $T; $Ws = Join-Path $T '_ClaudeWorkspace'
New-Item -ItemType Directory -Path (Join-Path $Root 'roms/snes') -Force | Out-Null
New-Item -ItemType Directory -Path $Ws -Force | Out-Null
function Set-Game([int]$secsA, [string]$lastA, [int]$secsB) {
    $xml = '<?xml version="1.0"?><gameList><game><path>./zelda.sfc</path><name>Zelda</name><gametime>' + $secsA + '</gametime><lastplayed>' + $lastA + '</lastplayed></game>' +
           '<game><path>./mario.sfc</path><name>Mario</name><gametime>' + $secsB + '</gametime><favorite>true</favorite></game></gameList>'
    [System.IO.File]::WriteAllText((Join-Path $Root 'roms/snes/gamelist.xml'), $xml)
}
Set-Game 3600 '20261001T100000' 600
# 1. first settle: the owner gets what is already there
$l = Update-SocialPlayLedger $Root $Ws 'steven1'
Check 'owner gets existing zelda time' ($l['snes|./zelda.sfc'].Secs -eq 3600)
Check 'owner gets existing mario time' ($l['snes|./mario.sfc'].Secs -eq 600)
# 2. Steven plays 30 more minutes of Zelda, then a friend picks PLAY
Set-Game 5400 '20261002T100000' 600
$f = Update-SocialPlayLedger $Root $Ws 'friend22' -Switch
Check 'friend starts with nothing' ($f.Count -eq 0)
$s = Read-SocialTimesFile (Join-Path (Get-SocialPlayDir $Ws) 'steven1.txt')
Check 'steven got the 30 minutes' ($s['snes|./zelda.sfc'].Secs -eq 5400)
Check 'steven last played updated' ($s['snes|./zelda.sfc'].Last -eq '20261002T100000')
# 3. the friend plays Mario for 20 minutes; the helper settles (no new person)
Set-Game 5400 '20261002T100000' 1800
$f = Update-SocialPlayLedger $Root $Ws ''
Check 'friend has their 20 minutes' ($f['snes|./mario.sfc'].Secs -eq 1200)
Check 'friend has no zelda' (-not $f.ContainsKey('snes|./zelda.sfc'))
$s = Read-SocialTimesFile (Join-Path (Get-SocialPlayDir $Ws) 'steven1.txt')
Check 'steven mario unchanged' ($s['snes|./mario.sfc'].Secs -eq 600)
# 4. settling again with nothing new changes nothing
$f2 = Update-SocialPlayLedger $Root $Ws 'friend22'
Check 'no double counting' ($f2['snes|./mario.sfc'].Secs -eq 1200)
# 5. the stats use the ledger
$st = Get-SocialGameStats $Root @{} 3 3 6 $f2
Check 'friend top game is mario' ($st.Top.Count -eq 1 -and $st.Top[0].Name -eq 'Mario' -and $st.Top[0].Minutes -eq 20)
Check 'favourite still shows' ($st.Fav.Count -eq 1)
$all = Get-SocialGameStats $Root @{}
Check 'without a ledger, the drive totals' (($all.Top | Where-Object Name -eq 'Zelda').Minutes -eq 90)
# 6. favourites per person: friend22 is open; steven1 picks PLAY
$script:SocialRunningOverride = { $false }
$gl = Join-Path $Root 'roms/snes/gamelist.xml'
$null = Update-SocialPlayLedger $Root $Ws 'steven1' -Switch
$favs = Read-SocialFavorites $Root
Check 'steven gets back the star he had (mario)' ($favs.ContainsKey('snes|./mario.sfc'))
# steven stars zelda too, then the friend picks PLAY: the friend starts with the stars they had (mario)
$t = [System.IO.File]::ReadAllText($gl).Replace('<name>Zelda</name>', '<name>Zelda</name><favorite>true</favorite>')
[System.IO.File]::WriteAllText($gl, $t)
$null = Update-SocialPlayLedger $Root $Ws 'friend22' -Switch
$favs = Read-SocialFavorites $Root
Check 'friend gets their own stars back' ($favs.ContainsKey('snes|./mario.sfc') -and -not $favs.ContainsKey('snes|./zelda.sfc'))
$null = Update-SocialPlayLedger $Root $Ws 'steven1' -Switch
$favs = Read-SocialFavorites $Root
Check 'steven gets zelda and mario back' ($favs.ContainsKey('snes|./zelda.sfc') -and $favs.ContainsKey('snes|./mario.sfc'))
Check 'names and times untouched' ([System.IO.File]::ReadAllText($gl) -match '<gametime>5400</gametime>')
# a newcomer starts with no stars; a guest changes nothing
$null = Update-SocialPlayLedger $Root $Ws 'newbie9' -Switch
Check 'newcomer: no stars' ((Read-SocialFavorites $Root).Count -eq 0)
$null = Update-SocialPlayLedger $Root $Ws 'guest' -Switch
Check 'guest: nothing changed' ((Read-SocialFavorites $Root).Count -eq 0)
# RetroBat open: no swapping
$script:SocialRunningOverride = { $true }
$null = Update-SocialPlayLedger $Root $Ws 'steven1' -Switch
Check 'while RetroBat is open nothing is swapped' ((Read-SocialFavorites $Root).Count -eq 0)

Remove-Item $T -Recurse -Force
Write-Host ("play time tests: {0} passed, {1} failed" -f $pass, $fail)
if ($fail -gt 0) { exit 1 }
