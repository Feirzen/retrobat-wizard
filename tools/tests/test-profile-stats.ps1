# Played games on the profile (SocialEngine.ps1, 2026-10-11): stats from
# RetroBat's own gamelist.xml, hidden games, per-friend sharing, the record
# round trip.
param([string]$Scripts = (Join-Path $PSScriptRoot '../../drive/Program/scripts'))
$ErrorActionPreference = 'Stop'
$script:pass = 0; $script:fail = 0
function A($c, [string]$n) { if ($c) { $script:pass++ } else { $script:fail++; Write-Host "FAIL: $n" -ForegroundColor Red } }
. (Join-Path $Scripts 'SocialEngine.ps1')

$TR = Join-Path ([IO.Path]::GetTempPath()) ('ps' + [guid]::NewGuid().ToString('N').Substring(0, 6))
$Ws = Join-Path $TR '_Wizard'
New-Item -ItemType Directory -Force (Join-Path $TR 'roms/n64/images'), (Join-Path $TR 'roms/gamecube'), $Ws | Out-Null
[IO.File]::WriteAllText((Join-Path $TR 'roms/n64/images/smash.png'), 'x')
[IO.File]::WriteAllText((Join-Path $TR 'roms/n64/gamelist.xml'), @'
<?xml version="1.0"?>
<gameList>
  <game><path>./Smash.z64</path><name>Super Smash Bros.</name><image>./images/smash.png</image><gametime>36000</gametime><lastplayed>20261004T201500</lastplayed><playcount>9</playcount><favorite>true</favorite></game>
  <game><path>./Mario Kart 64.z64</path><name>Mario Kart 64</name><gametime>5400</gametime><lastplayed>20260926T101000</lastplayed></game>
  <game><path>./Paper Mario.z64</path><name>Paper Mario</name><gametime>120</gametime><lastplayed>20261010T090000</lastplayed></game>
  <game><path>./Unplayed.z64</path><name>Never Played</name></game>
  <game><path>./Secret.z64</path><name>Secret Game</name><gametime>99999</gametime><lastplayed>20261011T090000</lastplayed></game>
</gameList>
'@)
[IO.File]::WriteAllText((Join-Path $TR 'roms/gamecube/gamelist.xml'), @'
<?xml version="1.0"?>
<gameList><game><path>./Melee.iso</path><name>Melee</name><gametime>7200</gametime><lastplayed>20261001T120000</lastplayed><favorite>true</favorite></game></gameList>
'@)

$st = Get-SocialGameStats $TR @{}
A ($st.Top.Count -eq 3 -and $st.Top[0].Name -eq 'Secret Game' -and $st.Top[1].Name -eq 'Super Smash Bros.') 'top 3 by time played'
A ($st.Recent[0].Name -eq 'Secret Game' -and $st.Recent[1].Name -eq 'Paper Mario') 'recent by last played'
A ($st.Fav.Count -eq 2) 'favourites from the star'
A ($st.Top[1].Image -like '*smash.png') 'box art from the game list'
A (@($st.All | Where-Object Name -eq 'Never Played').Count -eq 0) 'never-played games left out'
A ($st.Top[1].Minutes -eq 600) 'seconds turned into minutes'

Set-SocialHiddenGame $Ws 'n64' './Secret.z64' $true
$h = Get-SocialHiddenGames $Ws
$st2 = Get-SocialGameStats $TR $h
A (@($st2.All | Where-Object Name -eq 'Secret Game').Count -eq 0) 'a hidden game is left out everywhere'
A ($st2.Top[0].Name -eq 'Super Smash Bros.') 'the next one moves up'
Set-SocialHiddenGame $Ws 'n64' './Secret.z64' $false
A ((Get-SocialHiddenGames $Ws).Count -eq 0) 'unhide'

# profile.ini keeps the share list
$p = New-SocialProfile 'Tester' 'icon:nes'
$p.Friends = @('aaaaaaaaaa', 'bbbbbbbbbb'); $p.Share = @('aaaaaaaaaa')
Write-SocialProfile $Ws $p
$p2 = Read-SocialProfile $Ws
A (@($p2.Share).Count -eq 1 -and @($p2.Share)[0] -eq 'aaaaaaaaaa') 'share list saved and read back'

# the record: games only when shared, only with friends, read back cleanly
$pres = [pscustomobject]@{ State = 'on'; InGame = $false; Game = ''; Console = ''; Since = '' }
$j = ConvertTo-SocialRecordJson $p2 $pres '2.4.0' $st2
$rec = ConvertFrom-SocialRecord $j 'blob'
A ($null -ne $rec.Games -and @($rec.Games.For).Count -eq 1) 'record carries games for one friend'
A (@($rec.Games.Top).Count -eq 3 -and $rec.Games.Top[0].Name -eq 'Super Smash Bros.' -and $rec.Games.Top[0].Minutes -eq 600) 'top games read back'
A ($rec.Games.Recent[0].Last -eq '2026-10-10') 'last played date read back'
A ([Text.Encoding]::UTF8.GetByteCount($j) -lt 8192) ('record stays under the 8 KB limit (' + [Text.Encoding]::UTF8.GetByteCount($j) + ')')
$p2.Share = @()
$j2 = ConvertTo-SocialRecordJson $p2 $pres '2.4.0' $st2
A ($j2 -notmatch '"games"') 'shared with nobody: no games at all'
$p2.Share = @('cccccccccc')
$j3 = ConvertTo-SocialRecordJson $p2 $pres '2.4.0' $st2
A ($j3 -notmatch '"games"') 'shared only with a non-friend: no games'
$one = @{ Top = @($st2.Top[0]); Recent = @(); Fav = @() }
$p2.Share = @('aaaaaaaaaa')
$rec1 = ConvertFrom-SocialRecord (ConvertTo-SocialRecordJson $p2 $pres '2.4.0' $one) 'b'
A (@($rec1.Games.Top).Count -eq 1 -and @($rec1.Games.Recent).Count -eq 0) 'one-item and empty lists survive'
$bad = ConvertFrom-SocialRecord '{"id":"aaaaaaaaaa","username":"x","games":{"for":["../x","bbbbbbbbbb"],"top":[{"n":"ok","s":"../evil","m":5},{"n":"Fine","s":"snes","m":-4,"t":"nope"}]}}' 'b'
A (@($bad.Games.For).Count -eq 1 -and @($bad.Games.Top).Count -eq 1 -and $bad.Games.Top[0].Minutes -eq 0 -and $bad.Games.Top[0].Last -eq '') 'odd values from someone else are cleaned'
$old = ConvertFrom-SocialRecord '{"id":"aaaaaaaaaa","username":"x"}' 'b'
A ($null -eq $old.Games) 'an older record without games still reads'
$fromRec = New-SocialProfileFromRecord $rec
A (@($fromRec.Share).Count -eq 1) 'logging in elsewhere keeps who you share with'
A ((Format-SocialPlaytime 135) -eq '2 h 15 min' -and (Format-SocialPlaytime 40) -eq '40 min' -and (Format-SocialPlaytime 120) -eq '2 h') 'play time in words'

# "Log back in" keeps a custom picture (2026-10-12)
$pp = Get-SocialPaths $Ws
New-SocialDir $pp.ProfileDir
[IO.File]::WriteAllBytes($pp.Avatar, [byte[]](137, 80, 78, 71, 1, 2))
$cp = New-SocialProfile 'Picture' 'custom:ee7d4d0f4dfa'
Add-SocialLogin $Ws $cp
$lg = @(Get-SocialLogins $Ws | Where-Object Id -eq $cp.Id)[0]
A ($lg.Avatar -eq 'custom:ee7d4d0f4dfa') ('login keeps the custom picture: ' + $lg.Avatar)
A (Test-Path (Join-SocialPath (Join-SocialPath $pp.Cache 'avatars') ($cp.Id + '-ee7d4d0f4dfa.png'))) 'a copy waits in the cache for the list'
$ip = New-SocialProfile 'Icon' 'icon:n64'; Add-SocialLogin $Ws $ip
A (@(Get-SocialLogins $Ws | Where-Object Id -eq $ip.Id)[0].Avatar -eq 'icon:n64') 'icons kept as before'
[IO.File]::AppendAllText((Join-SocialPath $pp.ProfileDir 'logins.txt'), "bbbbbbbbbb|Odd|../../x`r`n")
A (@(Get-SocialLogins $Ws | Where-Object Id -eq 'bbbbbbbbbb')[0].Avatar -eq 'icon:gameboy') 'an odd picture value falls back'

Remove-Item -Recurse -Force $TR
Write-Host ("profile stats tests: {0} passed, {1} failed" -f $script:pass, $script:fail)
if ($script:fail -gt 0) { exit 1 }
