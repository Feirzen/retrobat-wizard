# Play time online (3.3): each drive writes only its own part of playtime/<id>.json; every drive adds the others' time.
param([string]$Scripts = (Join-Path $PSScriptRoot '../../drive/Program/scripts'))
$ErrorActionPreference='Stop'
$T = Join-Path ([System.IO.Path]::GetTempPath()) ('pto-' + [guid]::NewGuid().ToString('N'))
foreach ($d in 'A','B') { New-Item -ItemType Directory -Force "$T/$d/roms/snes","$T/$d/_Wizard/People/play","$T/$d/_Wizard/People/social" | Out-Null; 'tok' | Set-Content "$T/$d/_Wizard/People/social/social-token.txt" }
[IO.File]::WriteAllText("$T/A/roms/snes/gamelist.xml", '<?xml version="1.0"?><gameList><game><path>./smw.sfc</path><name>Super Mario World</name></game><game><path>./zelda.sfc</path><name>The Legend of Zelda: A Link to the Past</name></game></gameList>')
[IO.File]::WriteAllText("$T/B/roms/snes/gamelist.xml", '<?xml version="1.0"?><gameList><game><path>./Super Mario World (USA).sfc</path><name>Super Mario World</name><gametime>600</gametime><lastplayed>20261104T100000</lastplayed></game></gameList>')
. (Join-Path $Scripts 'SocialEngine.ps1')
$pass=0;$fail=0; function A($c,$n){ if($c){$script:pass++}else{$script:fail++;"FAIL $n"} }
$script:store=@{}; $script:shas=@{}; $script:puts=0
$script:SocialApiOverride = { param($m,$u,$b,$a)
  $k = $u -replace '^.*/contents/',''
  if ($m -eq 'GET') { if ($script:store.ContainsKey($k)) { return @{ Status=200; Body=('{"sha":"'+$script:shas[$k]+'","content":"'+[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($script:store[$k]))+'"}') } } else { return @{ Status=404; Body='' } } }
  if ($m -eq 'PUT') { $o = $b | ConvertFrom-Json; if ($script:shas.ContainsKey($k) -and [string]$o.sha -ne $script:shas[$k]) { return @{ Status=409; Body='' } }; $script:store[$k]=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($o.content)); $script:shas[$k]=[guid]::NewGuid().ToString('N'); $script:puts++; return @{ Status=200; Body='{}' } }
}
$id='abcdefghij'
$ledA = @{ 'snes|./smw.sfc' = @{ Secs = 3600; Last = '20261101T120000' }; 'snes|./zelda.sfc' = @{ Secs = 1800; Last = '20261102T120000' } }
$r = Sync-SocialPlaytime "$T/A" "$T/A/_Wizard" $id $ledA; A ($r -eq 'sent') "A sent ($r)"
$r = Sync-SocialPlaytime "$T/A" "$T/A/_Wizard" $id $ledA; A ($r -eq 'same') "A unchanged is not sent again ($r)"
$ledB = @{ 'snes|./Super Mario World (USA).sfc' = @{ Secs = 600; Last = '20261104T100000' } }
$r = Sync-SocialPlaytime "$T/B" "$T/B/_Wizard" $id $ledB; A ($r -eq 'sent') "B sent ($r)"
$d = $script:store['playtime/abcdefghij.json'] | ConvertFrom-Json; A (@($d.drives.PSObject.Properties).Count -eq 2) 'both drives kept in the file'
$oth = Get-SocialOtherPlaytime "$T/B/_Wizard" $id $true; A ($oth.Count -eq 2 -and $oth['snes|super mario world'].Secs -eq 3600) 'B sees A time by game name'
$st = Get-SocialGameStats "$T/B" @{} 3 3 6 $ledB $oth
$smw = @($st.All | ? Name -eq 'Super Mario World')[0]; A ($smw.Minutes -eq 70) "Mario: 60 + 10 min = $($smw.Minutes)"
$z = @($st.All | ? Name -like '*Link to the Past*')[0]; A ($null -ne $z -and $z.Minutes -eq 30 -and $z.Image -eq '') 'Zelda only on A still listed, no picture'
A ($st.Top[0].Name -eq 'Super Mario World') 'most played first'
A ($st.Recent[0].Name -eq 'Super Mario World') 'recent uses the newest play on any drive'
# A plays more while B also wrote: the other part is kept
$ledA['snes|./smw.sfc'].Secs = 7200
$r = Sync-SocialPlaytime "$T/A" "$T/A/_Wizard" $id $ledA; A ($r -eq 'sent') 'A sends again after more play'
$othA = Get-SocialOtherPlaytime "$T/A/_Wizard" $id $true; A ($othA['snes|super mario world'].Secs -eq 600) 'A sees B part untouched'
A ((Get-SocialDriveId "$T/A/_Wizard") -ne (Get-SocialDriveId "$T/B/_Wizard")) 'drives get different ids'
A (@(Get-ChildItem "$T/A/_Wizard/People/play" -Filter '*.txt').Count -eq 0) 'no .txt files that look like a ledger'
Remove-Item -Recurse -Force $T
"play time online tests: $pass passed, $fail failed"

