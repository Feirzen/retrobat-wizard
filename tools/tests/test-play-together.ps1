# Favourites, play-together invites, incognito, more than one person per drive
# (SocialEngine.ps1 + Social-Helper.ps1, 2026-10-12). PowerShell 7, Linux.
param([string]$Scripts = '/home/claude/work/new/_ClaudeWorkspace/scripts')
$ErrorActionPreference = 'Stop'
$script:pass = 0; $script:fail = 0
function Assert($c, [string]$n) { if ($c) { $script:pass++ } else { $script:fail++; Write-Host "FAIL: $n" -ForegroundColor Red } }
. (Join-Path $Scripts 'SocialEngine.ps1')

$base = Join-Path ([IO.Path]::GetTempPath()) ('ptg-' + [guid]::NewGuid().ToString('N'))
$Root = Join-Path $base 'RetroBat'
$Ws = Join-Path $Root '_ClaudeWorkspace'
New-Item -ItemType Directory -Force $Ws | Out-Null
function W([string]$p, [string]$t) { $d = Split-Path -Parent $p; if (-not (Test-Path $d)) { [void](New-Item -ItemType Directory -Path $d -Force) }; [IO.File]::WriteAllText($p, $t) }

# --- a little roms folder ---------------------------------------------------------
W (Join-Path $Root 'roms/n64/Mario Kart 64 (USA).z64') 'rom'
W (Join-Path $Root 'roms/n64/images/Mario Kart 64 (USA)-thumb.png') 'png'
W (Join-Path $Root 'roms/n64/gamelist.xml') '<?xml version="1.0"?><gameList><game><path>./Mario Kart 64 (USA).z64</path><name>Mario Kart 64</name></game></gameList>'
W (Join-Path $Root 'roms/gamecube/sub/Melee.iso') 'rom'

# --- favourite slots ----------------------------------------------------------------
Assert ((ConvertTo-SocialFavSlot 'N64|Mario Kart 64 (USA).z64|images/Mario Kart 64 (USA)-thumb.png') -eq 'n64|Mario Kart 64 (USA).z64|images/Mario Kart 64 (USA)-thumb.png') 'slot kept, system lower-cased'
Assert ((ConvertTo-SocialFavSlot 'n64|../../secret.txt|') -eq '') 'climbing out refused'
Assert ((ConvertTo-SocialFavSlot 'n64|C:/x.z64|') -eq '') 'drive letter refused'
Assert ((ConvertTo-SocialFavSlot 'n64|/x.z64|') -eq '') 'rooted refused'
Assert ((ConvertTo-SocialFavSlot 'bad sys|x|') -eq '') 'bad system refused'
Assert ((ConvertTo-SocialFavSlot 'n64|x') -eq '') 'two fields refused'
Assert ((ConvertTo-SocialFavSlot '') -eq '') 'empty is empty'

$f = Resolve-SocialFav $Root 'n64|Mario Kart 64 (USA).z64|images/Mario Kart 64 (USA)-thumb.png'
Assert ($null -ne $f -and $f.Name -eq 'Mario Kart 64') 'name from the game list'
Assert ($f.Image -like '*thumb.png') 'picture found'
$g = Resolve-SocialFav $Root 'gamecube|sub/Melee.iso|'
Assert ($null -ne $g -and $g.Name -eq 'Melee' -and $g.Image -eq '') 'no game list: file name, no picture'
Assert ($null -eq (Resolve-SocialFav $Root 'n64|Gone.z64|')) 'a vanished game is an empty slot'
Assert ((Get-SocialRelPath $Root 'n64' ([IO.Path]::Combine($Root, 'roms', 'n64', 'images', 'a.png'))) -eq 'images/a.png') 'relative path'
Assert ((Get-SocialRelPath $Root 'n64' '/elsewhere/a.png') -eq '') 'outside roms refused'

# profile.ini keeps them, and "reach"
$me = New-SocialProfile 'Steven' 'icon:n64'
$me.Favs = @('n64|Mario Kart 64 (USA).z64|images/Mario Kart 64 (USA)-thumb.png', '', 'gamecube|sub/Melee.iso|')
$me.Reach = $false
Write-SocialProfile $Ws $me
$back = Read-SocialProfile $Ws
Assert (@($back.Favs).Count -eq 3 -and $back.Favs[0] -like 'n64|*' -and $back.Favs[1] -eq '' -and $back.Favs[2] -like 'gamecube|*') 'three slots round trip'
Assert ($back.Reach -eq $false) 'reach off round trips'
$favs = @(Get-SocialFavs $Root $back)
Assert ($favs.Count -eq 3 -and $null -eq $favs[1] -and $favs[2].Name -eq 'Melee') 'Get-SocialFavs keeps slot positions'
W (Join-Path $Ws 'profile/old.ini') "id = abcdefghij`nusername = Old`n"
Assert ((Read-SocialProfile $Ws (Join-Path $Ws 'profile/old.ini')).Reach -eq $true) 'old profile: reach defaults on'

# --- the online record: favs, invite, reply ------------------------------------------
$inv = [pscustomobject]@{ Id = 'abc12345'; To = @('frienda001', 'bad id'); Game = 'Mario Kart 64'; System = 'n64'; Note = 'cups!'; Code = ''; At = (Format-SocialTime (Get-SocialNowUtc)) }
$rep = [pscustomobject]@{ To = 'frienda001'; Inv = 'zzz99999'; Ans = 'yes'; At = (Format-SocialTime (Get-SocialNowUtc)) }
$live = @{ Favs = @($favs | Where-Object { $null -ne $_ }); Invite = $inv; Reply = $rep }
$pres = [pscustomobject]@{ State = 'on'; InGame = $false; Game = ''; Console = ''; Since = '' }
$json = ConvertTo-SocialRecordJson $back $pres '2.4' $null $live
$rec = ConvertFrom-SocialRecord $json 'blob'
Assert ($null -ne $rec) 'record parses'
Assert (@($rec.Favs).Count -eq 2 -and $rec.Favs[0].Name -eq 'Mario Kart 64' -and $rec.Favs[0].System -eq 'n64') 'favs in the record'
Assert ($rec.Invite.Id -eq 'abc12345' -and @($rec.Invite.To).Count -eq 1 -and $rec.Invite.Game -eq 'Mario Kart 64' -and $rec.Invite.Note -eq 'cups!') 'invite in the record, bad id dropped'
Assert ($rec.Reply.To -eq 'frienda001' -and $rec.Reply.Ans -eq 'yes') 'reply in the record'
Assert ($json.Length -lt 8192) 'record stays under the 8 KB cap'
$plain = ConvertFrom-SocialRecord (ConvertTo-SocialRecordJson $back $pres '2.4') 'b'
Assert ($null -eq $plain.Invite -and $null -eq $plain.Reply -and @($plain.Favs).Count -eq 0) 'no live parts: none read'
$stats = @{ Top = @(); Recent = @(); Fav = @([pscustomobject]@{ Name = 'Starred'; System = 'nes'; Minutes = 1; Last = $null }) }
$sh = New-SocialProfile 'Sharer' 'icon:nes'; $sh.Friends = @('frienda001'); $sh.Share = @('frienda001')
$sj = ConvertTo-SocialRecordJson $sh $pres '2.4' $stats
Assert ($sj -match '"fav":\[\]') 'RetroBat stars are no longer sent'
Assert ($null -eq (ConvertFrom-SocialInvite ([pscustomobject]@{ id = 'x'; at = 'now' }))) 'bad invite dropped'
Assert ($null -eq (ConvertFrom-SocialReply ([pscustomobject]@{ to = 'frienda001'; inv = 'abc12345'; ans = 'maybe'; at = (Format-SocialTime (Get-SocialNowUtc)) }))) 'bad answer dropped'

# --- invites between two friends --------------------------------------------------------
$now = Get-SocialNowUtc
$A = New-SocialProfile 'Alice' 'icon:nes'; $B = New-SocialProfile 'Bob' 'icon:snes'; $C = New-SocialProfile 'Cara' 'icon:gba'
$A.Friends = @($B.Id, $C.Id); $B.Friends = @($A.Id); $C.Friends = @()
function Rec($p, $l) { ConvertFrom-SocialRecord (ConvertTo-SocialRecordJson $p $pres '2.4' $null $l) 'b' }
$invA = [pscustomobject]@{ Id = 'inv00001'; To = @($B.Id, $C.Id); Game = 'Smash'; System = 'n64'; Note = ''; Code = ''; At = (Format-SocialTime $now) }
$players = @((Rec $A @{ Favs = @(); Invite = $invA; Reply = $null }), (Rec $B @{ Favs = @(); Invite = $null; Reply = $null }), (Rec $C @{ Favs = @(); Invite = $null; Reply = $null }))
$forB = @(Get-SocialInvitesFor $B $players $now)
Assert ($forB.Count -eq 1 -and $forB[0].From.Id -eq $A.Id -and $forB[0].Invite.Game -eq 'Smash') 'Bob (a friend) sees the invite'
Assert (@(Get-SocialInvitesFor $C $players $now).Count -eq 0) 'Cara is named but not a friend back: no invite'
Assert (@(Get-SocialInvitesFor $B $players $now.AddMinutes(16)).Count -eq 0) 'an invite runs out after 15 minutes'
Assert (@(Get-SocialInvitesFor $A $players $now).Count -eq 0) 'nobody sees their own invite'
# Bob says yes; Alice sees it
$players2 = @($players[0], (Rec $B @{ Favs = @(); Invite = $null; Reply = [pscustomobject]@{ To = $A.Id; Inv = 'inv00001'; Ans = 'yes'; At = (Format-SocialTime $now) } }), $players[2])
$mine = $players2[0].Invite
$reps = @(Get-SocialRepliesFor $A $players2 $mine)
Assert ($reps.Count -eq 1 -and $reps[0].Yes -and $reps[0].From.Username -eq 'Bob') 'Alice sees Bob is joining'
Assert (@(Get-SocialRepliesFor $A $players2 $null).Count -eq 0) 'no invite, no answers'

# this drive's own invite and answer files
$id = Write-SocialInvite $Ws @($B.Id, 'nonsense') 'Smash' 'N64' 'now?' ''
$ri = Read-SocialInvite $Ws (Get-SocialNowUtc)
Assert ($ri.Id -eq $id -and @($ri.To).Count -eq 1 -and $ri.System -eq 'n64' -and $ri.Note -eq 'now?') 'invite file round trip'
Assert ($null -eq (Read-SocialInvite $Ws (Get-SocialNowUtc).AddMinutes(20))) 'old invite file reads as none'
Write-SocialReply $Ws $A.Id 'inv00001' $true
Assert ((Read-SocialReply $Ws (Get-SocialNowUtc)).Ans -eq 'yes') 'answer file round trip'
Clear-SocialInvite $Ws
Assert ($null -eq (Read-SocialInvite $Ws (Get-SocialNowUtc)) -and $null -eq (Read-SocialReply $Ws (Get-SocialNowUtc))) 'cleared'
Assert (-not (Test-SocialSeen $Ws 'inv:x:1')) 'not seen yet'
Add-SocialSeen $Ws 'inv:x:1'; Add-SocialSeen $Ws 'inv:x:1'
Assert ((Test-SocialSeen $Ws 'inv:x:1') -and @([IO.File]::ReadAllLines((Join-Path $Ws 'social/invites-seen.txt'))).Count -eq 1) 'seen once, kept once'

# --- incognito ---------------------------------------------------------------------------
Assert (-not (Test-SocialIncognito $Ws)) 'not incognito by default'
Set-SocialIncognito $Ws $true
Assert (Test-SocialIncognito $Ws) 'incognito on'
Set-SocialIncognito $Ws $false
Assert (-not (Test-SocialIncognito $Ws)) 'incognito off'

# --- the "Who's playing?" switch and remembered passwords ---------------------------------
Assert (Get-SocialAskWho $Ws) 'ask is on by default'
Set-SocialAskWho $Ws $false
Assert (-not (Get-SocialAskWho $Ws)) 'ask off'
Set-SocialAskWho $Ws $true
$p1 = New-SocialProfile 'One' 'icon:nes'; $p2 = New-SocialProfile 'Two' 'icon:snes'
Add-SocialLogin $Ws $p1
Assert (-not (Test-SocialLoginTrusted $Ws $p1.Id)) 'not trusted until a password is typed'
Add-SocialLogin $Ws $p2 $true
Assert (Test-SocialLoginTrusted $Ws $p2.Id) 'trusted after typing'
Add-SocialLogin $Ws $p2
Assert (Test-SocialLoginTrusted $Ws $p2.Id) 'logging in again keeps the trust date'
$lf = Join-Path $Ws 'profile/logins.txt'
[IO.File]::WriteAllText($lf, ([IO.File]::ReadAllText($lf) -replace '\d{4}-\d{2}-\d{2}', '2020-01-01'))
Assert (-not (Test-SocialLoginTrusted $Ws $p2.Id)) 'trust runs out after 60 days'
Set-SocialLoginTrusted $Ws $p2.Id
Assert (Test-SocialLoginTrusted $Ws $p2.Id) 'trusted again'
[IO.File]::WriteAllText($lf, "$($p1.Id)|One|icon:nes`n")
Assert (@(Get-SocialLogins $Ws).Count -eq 1 -and -not (Test-SocialLoginTrusted $Ws $p1.Id)) 'an old three-field line still reads'

# --- more than one person per drive -----------------------------------------------------------
$pa = New-SocialProfile 'Anna' 'icon:nes'; $pa.ShowGame = $false; $pa.Favs = @('n64|Mario Kart 64 (USA).z64|', '', '')
Write-SocialProfile $Ws $pa
Set-SocialHiddenGame $Ws 'n64' './secret.z64' $true
Assert (Save-SocialPersonCopy $Ws) 'Anna put away'
$pb = New-SocialProfile 'Ben' 'icon:snes'
Write-SocialProfile $Ws $pb
Remove-Item (Join-Path $Ws 'profile/hidden-games.txt')
Assert ($null -eq (Read-SocialPersonCopy $Ws $pb.Id)) 'Ben has no copy yet'
Assert ((Read-SocialPersonCopy $Ws $pa.Id).Username -eq 'Anna') 'Anna''s copy reads'
Assert (Save-SocialPersonCopy $Ws) 'Ben put away'
Assert (Restore-SocialPersonCopy $Ws $pa.Id) 'Anna back'
$now2 = Read-SocialProfile $Ws
Assert ($now2.Id -eq $pa.Id -and $now2.ShowGame -eq $false -and $now2.Favs[0] -like 'n64|*') 'Anna''s own switches and favourites came back'
Assert ((Get-SocialHiddenGames $Ws).ContainsKey('n64|./secret.z64')) 'Anna''s hidden games came back'
Assert (Restore-SocialPersonCopy $Ws $pb.Id) 'Ben back'
Assert ((Read-SocialProfile $Ws).Username -eq 'Ben' -and -not (Test-Path (Join-Path $Ws 'profile/hidden-games.txt'))) 'Ben has no hidden games (Anna''s did not leak)'
Assert (-not (Restore-SocialPersonCopy $Ws 'nobodyxxxx')) 'nobody to bring back'
Assert (-not (Restore-SocialPersonCopy $Ws '../../../x')) 'a bad id is refused'

# --- the helper: incognito check-in, live parts, banners ----------------------------------------
$ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $Scripts 'Social-Helper.ps1'), [ref]$null, [ref]$null)
foreach ($fn in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false)) {
    if (@('Show-Popup', 'Show-InviteBanner', 'Open-WizardNetplay') -notcontains $fn.Name) { . ([scriptblock]::Create($fn.Extent.Text)) }
}
$script:banners = @(); $script:popups = @(); $script:opened = 0; $script:answer = 'join'
function Show-InviteBanner($Player, [string]$Title, [string]$Line) { $script:banners += $Title; return $script:answer }
function Show-Popup($Player, [string]$Title, [string]$Line) { $script:popups += $Title }
function Open-WizardNetplay { $script:opened++ }
$script:sent = @()
$script:SocialApiOverride = { param($M, $U, $Bd, $Acc) if ($M -eq 'PUT') { $script:sent += $Bd; return @{ Status = 201; Body = '{}' } }; return @{ Status = 404; Body = '' } }
$version = '2.4'; $game = $null; $since = ''
$bob = $B; $bob.Favs = @('n64|Mario Kart 64 (USA).z64|', '', '')
Write-SocialProfile $Ws $bob
Set-SocialIncognito $Ws $true
Assert (Send-CheckIn 'on') 'check-in ok'
$sentRec = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String(($script:sent[-1] | ConvertFrom-Json).content)) | ConvertFrom-Json
Assert ($sentRec.status -eq 'invisible') 'incognito sends invisible'
Assert (@($sentRec.favs).Count -eq 1 -and $sentRec.favs[0].n -eq 'Mario Kart 64') 'favourites sent by name'
Set-SocialIncognito $Ws $false
[void](Send-CheckIn 'on')
$sentRec = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String(($script:sent[-1] | ConvertFrom-Json).content)) | ConvertFrom-Json
Assert ($sentRec.status -eq 'online') 'back to online after incognito'

Invoke-HelperInvites (Read-SocialProfile $Ws) $players
Assert ($script:banners.Count -eq 1 -and $script:banners[0] -like 'Alice wants to play Smash') 'banner for Alice''s invite'
Assert ($script:opened -eq 1) 'Join opened the Netplay tab'
$myReply = Read-SocialReply $Ws (Get-SocialNowUtc)
Assert ($myReply.To -eq $A.Id -and $myReply.Inv -eq 'inv00001' -and $myReply.Ans -eq 'yes') 'Join answered yes'
$sentRec = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String(($script:sent[-1] | ConvertFrom-Json).content)) | ConvertFrom-Json
Assert ($sentRec.reply.ans -eq 'yes') 'the answer was sent straight away'
Invoke-HelperInvites (Read-SocialProfile $Ws) $players
Assert ($script:banners.Count -eq 1) 'the same invite is never shown twice'

# Bob invites Alice, Alice says no: Bob gets a popup once
$bobInv = Write-SocialInvite $Ws @($A.Id) 'Brawl' 'wii' '' ''
$aliceNo = Rec $A @{ Favs = @(); Invite = $null; Reply = [pscustomobject]@{ To = $B.Id; Inv = $bobInv; Ans = 'no'; At = (Format-SocialTime (Get-SocialNowUtc)) } }
Invoke-HelperInvites (Read-SocialProfile $Ws) @($aliceNo)
Invoke-HelperInvites (Read-SocialProfile $Ws) @($aliceNo)
Assert ($script:popups.Count -eq 1 -and $script:popups[0] -like "Alice can't play*") 'one popup for the answer'

Remove-Item -Recurse -Force $base
Write-Host ("play-together tests: {0} passed, {1} failed" -f $script:pass, $script:fail)
if ($script:fail -gt 0) { exit 1 }
