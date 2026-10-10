param([string]$Scripts = '/home/claude/work/new/_ClaudeWorkspace/scripts')
$ErrorActionPreference = 'Stop'
$script:pass = 0; $script:fail = 0
function Assert($c, [string]$n) { if ($c) { $script:pass++ } else { $script:fail++; Write-Host "FAIL: $n" -ForegroundColor Red } }
. (Join-Path $Scripts 'SocialEngine.ps1')

# --- a fake GitHub: files in memory, blob ids are sha1 of the content ---------
$script:files = @{}
$script:calls = New-Object System.Collections.ArrayList
$script:offline = $false
function BlobId([byte[]]$b) { $s=[System.Security.Cryptography.SHA1]::Create(); return (($s.ComputeHash($b) | ForEach-Object { $_.ToString('x2') }) -join '') }
$script:SocialApiOverride = {
    param($Method, $Url, $BodyText, $Accept)
    [void]$script:calls.Add("$Method $Url")
    if ($script:offline) { return @{ Status = 0; Body = 'offline' } }
    if ($Url -eq 'https://api.github.com/graphql') {
        $entries = @()
        foreach ($k in $script:files.Keys) {
            if ($k -notlike 'players/*') { continue }
            $f = $script:files[$k]
            $entries += @{ name = ($k -replace '^players/', ''); object = @{ oid = $f.sha; text = [Text.Encoding]::UTF8.GetString($f.bytes); byteSize = $f.bytes.Length } }
        }
        $obj = if ($entries.Count -gt 0) { @{ entries = $entries } } else { $null }
        $nm = @()
        foreach ($k in $script:files.Keys) { if ($k -like 'names/*') { $nm += @{ name = ($k -replace '^names/', ''); object = @{ text = [Text.Encoding]::UTF8.GetString($script:files[$k].bytes); byteSize = $script:files[$k].bytes.Length } } } }
        $names = if ($nm.Count -gt 0) { @{ entries = $nm } } else { $null }
        $adm = if ($script:files.ContainsKey('admin/admins.txt')) { @{ text = [Text.Encoding]::UTF8.GetString($script:files['admin/admins.txt'].bytes) } } else { $null }
        return @{ Status = 200; Body = (@{ data = @{ repository = @{ object = $obj; names = $names; admins = $adm } } } | ConvertTo-Json -Depth 10) }
    }
    $path = ($Url -split '/contents/')[1]
    if ($Method -eq 'GET') {
        if (-not $script:files.ContainsKey($path)) { return @{ Status = 404; Body = '' } }
        if ($Accept -eq 'application/vnd.github.raw') { return @{ Status = 200; Body = [Text.Encoding]::UTF8.GetString($script:files[$path].bytes) } }
        return @{ Status = 200; Body = (@{ sha = $script:files[$path].sha } | ConvertTo-Json) }
    }
    if ($Method -eq 'PUT') {
        $b = $BodyText | ConvertFrom-Json
        $exists = $script:files.ContainsKey($path)
        if ($exists -and [string]$b.sha -ne $script:files[$path].sha) { return @{ Status = 409; Body = 'sha mismatch' } }
        if (-not $exists -and $b.sha) { return @{ Status = 422; Body = 'no such file' } }
        $bytes = [Convert]::FromBase64String($b.content)
        $script:files[$path] = @{ bytes = $bytes; sha = (BlobId $bytes) }
        return @{ Status = $(if ($exists) { 200 } else { 201 }); Body = (@{ content = @{ sha = $script:files[$path].sha } } | ConvertTo-Json) }
    }
}

$base = Join-Path ([IO.Path]::GetTempPath()) ('soc-' + [guid]::NewGuid().ToString('N'))
function NewWs([string]$n) { $w = Join-Path $base "$n/_ClaudeWorkspace"; New-Item -ItemType Directory -Force $w | Out-Null; return $w }
$wsA = NewWs 'a'; $wsB = NewWs 'b'; $wsC = NewWs 'c'
$off = [pscustomobject]@{ State = 'on'; InGame = $false; Game = ''; Console = ''; Since = '' }

# --- usernames, ids, token ------------------------------------------------------
Assert ((Test-SocialUsername 'Naverog') -eq '') 'good name'
Assert ((Test-SocialUsername 'ab') -ne '') 'too short'
Assert ((Test-SocialUsername 'a b_c-d.e') -eq '') 'name with symbols'
Assert ((Test-SocialUsername ' x') -ne '' -or (Test-SocialUsername 'x') -ne '') 'short trimmed'
Assert ((Test-SocialUsername 'bad!name') -ne '') 'bang refused'
Assert ((Test-SocialUsername ('n' * 21)) -ne '') 'too long'
Assert ((New-SocialId) -match '^[a-z0-9]{10}$') 'id shape'
Assert ((New-SocialId) -ne (New-SocialId)) 'ids differ'
$tok = 'github_pat_ABCdef123_xyz'
New-Item -ItemType Directory -Force (Join-Path $wsA 'social') | Out-Null
[IO.File]::WriteAllText((Join-Path $wsA 'social/social-token.txt'), (ConvertTo-SocialScrambled $tok))
Assert ((Get-SocialToken $wsA) -eq $tok) 'scrambled token round-trips'
Assert ((ConvertTo-SocialScrambled $tok) -notmatch 'github_pat_') 'scrambled hides the prefix'
[IO.File]::WriteAllText((Join-Path $wsA 'social/social-token.txt'), "  $tok `r`n")
Assert ((Get-SocialToken $wsA) -eq $tok) 'plain token read'
Assert ((Get-SocialToken $wsB) -eq '') 'no token file -> empty'
Assert ((Get-SocialRepo $wsA) -eq 'Feirzen/retrobat-wizard-social') 'default repo'

# --- profiles -------------------------------------------------------------------
Assert ($null -eq (Read-SocialProfile $wsA)) 'no profile yet'
Write-SocialProfile $wsC ([pscustomobject]@{ Guest = $true })
Assert ((Read-SocialProfile $wsC).Guest) 'guest profile'
$pubGuest = Publish-SocialRecord $wsC (Read-SocialProfile $wsC) $off '2.2.0'
Assert (-not $pubGuest.Ok -and $script:calls.Count -eq 0) 'guest never sends anything'

$A = New-SocialProfile 'Naverog' 'icon:n64'; Write-SocialProfile $wsA $A
$B = New-SocialProfile 'Ruby' 'icon:wiimote'; Write-SocialProfile $wsB $B
$A2 = Read-SocialProfile $wsA
Assert ($A2.Username -eq 'Naverog' -and $A2.Id -eq $A.Id -and $A2.Avatar -eq 'icon:n64' -and $A2.ShowGame -and $A2.Popups -and $A2.Status -eq 'online') 'profile round-trip'
Assert (@($A2.Friends).Count -eq 0) 'no friends yet'

# --- publishing and reading -------------------------------------------------------
$r = Publish-SocialRecord $wsA $A2 $off '2.2.0'
Assert $r.Ok ('A publishes: ' + $r.Message)
$r = Publish-SocialRecord $wsB (Read-SocialProfile $wsB) $off '2.2.0'
Assert $r.Ok 'B publishes'
$all = Get-SocialPlayers $wsA
Assert ($all.Ok -and @($all.Players).Count -eq 2) "two players read in one call (got $(@($all.Players).Count))"
Assert (Test-Path (Join-Path $wsA 'social/cache/players.json')) 'cache written'
Assert (@(Get-SocialCachedPlayers $wsA).Count -eq 2) 'cache reads back'
Assert (Test-SocialNameTaken $all.Players 'ruby' $A.Id) 'name taken is case-insensitive'
Assert (-not (Test-SocialNameTaken $all.Players 'naverog' $A.Id)) 'own name not taken'
# second publish without the blob id: 422/409 then retry
$r = Publish-SocialRecord $wsA $A2 $off '2.2.0'
Assert $r.Ok 'republish without knowing the blob id recovers'

# --- search -------------------------------------------------------------------------
$found = @(Find-SocialPlayers $A2 $all.Players 'ru')
Assert ($found.Count -eq 1 -and $found[0].Username -eq 'Ruby') 'search finds Ruby'
Assert (@(Find-SocialPlayers $A2 $all.Players 'nav').Count -eq 0) 'search skips yourself'
Assert (@(Find-SocialPlayers $A2 $all.Players '').Count -eq 0) 'empty search finds nothing'

# --- friend requests ----------------------------------------------------------------
$now = Get-SocialNowUtc
Add-SocialFriend $A2 $B.Id; Write-SocialProfile $wsA $A2
[void](Publish-SocialRecord $wsA (Read-SocialProfile $wsA) $off '2.2.0')
$all = (Get-SocialPlayers $wsA).Players
$vA = Get-SocialView (Read-SocialProfile $wsA) $all $now
$vB = Get-SocialView (Read-SocialProfile $wsB) $all $now
Assert (@($vA.Outgoing).Count -eq 1 -and @($vA.Friends).Count -eq 0) 'A sees an outgoing request'
Assert (@($vB.Incoming).Count -eq 1 -and $vB.Incoming[0].Username -eq 'Naverog') 'B sees an incoming request'
# decline, then the request stays hidden for B
$Bp = Read-SocialProfile $wsB; Deny-SocialRequest $Bp $A.Id; Write-SocialProfile $wsB $Bp
$vB = Get-SocialView (Read-SocialProfile $wsB) $all $now
Assert (@($vB.Incoming).Count -eq 0) 'declined request hidden'
$vA = Get-SocialView (Read-SocialProfile $wsA) $all $now
Assert (@($vA.Outgoing).Count -eq 1) 'A still sees it as pending (no one is told they were declined)'
# B changes mind and accepts
$Bp = Read-SocialProfile $wsB; Add-SocialFriend $Bp $A.Id; Write-SocialProfile $wsB $Bp
Assert (@((Read-SocialProfile $wsB).Declined).Count -eq 0) 'accepting clears the decline'
[void](Publish-SocialRecord $wsB (Read-SocialProfile $wsB) $off '2.2.0')
$all = (Get-SocialPlayers $wsA).Players
$vA = Get-SocialView (Read-SocialProfile $wsA) $all $now
$vB = Get-SocialView (Read-SocialProfile $wsB) $all $now
Assert (@($vA.Friends).Count -eq 1 -and @($vB.Friends).Count -eq 1) 'mutual = friends'
Assert (@($vA.Outgoing).Count -eq 0 -and @($vB.Incoming).Count -eq 0) 'no pending left'
# one-item friend list survives JSON both ways
$recA = @($all | Where-Object Id -eq $A.Id)[0]
Assert (@($recA.Friends).Count -eq 1 -and $recA.Friends[0] -eq $B.Id) 'one-item friends list survives JSON'

# --- presence -----------------------------------------------------------------------
$playing = [pscustomobject]@{ State = 'on'; InGame = $true; Game = 'Mario Kart Wii'; Console = 'Wii'; Since = (Format-SocialTime $now.AddMinutes(-25)) }
[void](Publish-SocialRecord $wsB (Read-SocialProfile $wsB) $playing '2.2.0')
$all = (Get-SocialPlayers $wsA).Players
$b = @($all | Where-Object Id -eq $B.Id)[0]
$pr = Get-SocialPresence $b (Get-SocialNowUtc)
Assert ($pr.Kind -eq 'playing' -and $pr.Line -eq 'Playing Mario Kart Wii (Wii) for 25 min') "playing line ($($pr.Line))"
# hide the game
$Bp = Read-SocialProfile $wsB; $Bp.ShowGame = $false; Write-SocialProfile $wsB $Bp
[void](Publish-SocialRecord $wsB (Read-SocialProfile $wsB) $playing '2.2.0')
$b = @((Get-SocialPlayers $wsA).Players | Where-Object Id -eq $B.Id)[0]
Assert ((Get-SocialPresence $b (Get-SocialNowUtc)).Line -eq 'In a game for 25 min') 'hidden game says In a game'
Assert ($script:files["players/$($B.Id).json"].bytes.Length -gt 0 -and [Text.Encoding]::UTF8.GetString($script:files["players/$($B.Id).json"].bytes) -notmatch 'Mario') 'hidden game never leaves the drive'
# statuses and custom text
$Bp = Read-SocialProfile $wsB; $Bp.Status = 'busy'; $Bp.Text = 'down for "Smash"'; Write-SocialProfile $wsB $Bp
[void](Publish-SocialRecord $wsB (Read-SocialProfile $wsB) $off '2.2.0')
$b = @((Get-SocialPlayers $wsA).Players | Where-Object Id -eq $B.Id)[0]
Assert ((Get-SocialPresence $b (Get-SocialNowUtc)).Line -eq 'Busy - down for "Smash"') "busy with text ($((Get-SocialPresence $b (Get-SocialNowUtc)).Line))"
$Bp.Status = 'invisible'; Write-SocialProfile $wsB $Bp
[void](Publish-SocialRecord $wsB (Read-SocialProfile $wsB) $off '2.2.0')
$b = @((Get-SocialPlayers $wsA).Players | Where-Object Id -eq $B.Id)[0]
Assert ((Get-SocialPresence $b (Get-SocialNowUtc)).Line -eq 'Offline') 'invisible looks offline, no last-seen'
$Bp.Status = 'online'; Write-SocialProfile $wsB $Bp
# stale = offline
$b.Status = 'online'
Assert ((Get-SocialPresence $b (Get-SocialNowUtc).AddMinutes(45)).Line -eq 'Offline, here 45 min ago') 'stale -> offline with time'
$goneP = [pscustomobject]@{ State = 'offline'; InGame = $false; Game = ''; Console = ''; Since = '' }
[void](Publish-SocialRecord $wsB (Read-SocialProfile $wsB) $goneP '2.2.0')
$b = @((Get-SocialPlayers $wsA).Players | Where-Object Id -eq $B.Id)[0]
Assert ((Get-SocialPresence $b (Get-SocialNowUtc)).Kind -eq 'offline') 'signed off -> offline'

# --- garbage on GitHub is dropped, never trusted ----------------------------------
function PutRaw($k, $t) { $bytes=[Text.Encoding]::UTF8.GetBytes($t); $script:files[$k] = @{ bytes = $bytes; sha = (BlobId $bytes) } }
PutRaw 'players/zzzzzzzzzz.json' 'not json at all'
PutRaw 'players/yyyyyyyyyy.json' '{"id":"xxxxxxxxxx","username":"impostor"}'
PutRaw 'players/../evil.json' '{"id":"aaaaaaaaaa","username":"x"}'
PutRaw 'players/wwwwwwwwww.json' ('{"id":"wwwwwwwwww","username":"' + ('L' * 300) + "`u{263A}" + '","avatar":"C:/x.png","friends":["bad id","' + $A.Id + '"]}')
$all = (Get-SocialPlayers $wsA).Players
Assert (@($all | Where-Object Id -eq 'zzzzzzzzzz').Count -eq 0) 'non-json dropped'
Assert (@($all | Where-Object Id -eq 'xxxxxxxxxx').Count -eq 0) 'id not matching file name dropped'
$w = @($all | Where-Object Id -eq 'wwwwwwwwww')[0]
Assert ($null -ne $w -and $w.Username.Length -eq 20 -and $w.Avatar -eq 'icon:gameboy' -and @($w.Friends).Count -eq 1) 'long name cut, bad avatar replaced, bad ids dropped'
$vA = Get-SocialView (Read-SocialProfile $wsA) $all (Get-SocialNowUtc)
Assert (@($vA.Incoming | Where-Object Id -eq 'wwwwwwwwww').Count -eq 1) 'a new person listing me shows as a request'

# --- offline ---------------------------------------------------------------------------
$script:offline = $true
$g = Get-SocialPlayers $wsA
Assert (-not $g.Ok -and $g.Message -eq 'Could not reach GitHub.') 'offline read fails softly'
$p = Publish-SocialRecord $wsA (Read-SocialProfile $wsA) $off '2.2.0'
Assert (-not $p.Ok) 'offline publish fails softly'
Assert (@(Get-SocialCachedPlayers $wsA).Count -ge 2) 'cache still there offline'

Assert (-not (Test-SocialNameTaken $null 'x' 'abc')) 'empty list as null: no crash'
Assert (-not (Test-SocialNameTaken $(@()) 'x' 'abc')) 'empty list through $(): no crash'
Assert (@(Find-SocialPlayers (Read-SocialProfile $wsA) $null 'a').Count -eq 0) 'search over nobody'
$v0 = Get-SocialView (Read-SocialProfile $wsA) $null (Get-SocialNowUtc); Assert (@($v0.Friends).Count -eq 0) 'view over nobody'
# --- 2026-10-10 b: passwords, logins, admins, name requests -------------------
$script:offline = $false
. (Join-Path $Scripts 'AdminEngine.ps1')
$pa = Read-SocialProfile $wsA
$h1 = Get-SocialPasswordHash $pa.Id 'hunter22'
Assert ($h1 -match '^[a-f0-9]{64}$') 'password hash is hex'
Assert ($h1 -ne (Get-SocialPasswordHash 'zzzzzzzzzz' 'hunter22')) 'hash depends on the id'
$pa.Pw = $h1; $pa.PwSet = '2026-10-10T10:00:00Z'; $pa.NameReq = 'Newname'
Write-SocialProfile $wsA $pa
$pb = Read-SocialProfile $wsA
Assert ($pb.Pw -eq $h1 -and $pb.NameReq -eq 'Newname' -and $pb.PwSet -eq '2026-10-10T10:00:00Z') 'pw and namereq survive profile.ini'
$on = [pscustomobject]@{ State = 'on'; InGame = $false; Game = ''; Console = ''; Since = '' }
Assert ((Publish-SocialRecord $wsA $pb $on '2.3.0').Ok) 'publish with password'
$all = Get-SocialPlayers $wsA
$recA = @($all.Players | Where-Object Id -eq $pb.Id)[0]
Assert ($recA.Pw -eq $h1 -and $recA.NameReq -eq 'Newname') 'record carries pw and namereq'
Assert (Test-SocialPassword $recA 'hunter22') 'right password'
Assert (-not (Test-SocialPassword $recA 'hunter23')) 'wrong password'
Assert (Test-SocialPassword ([pscustomobject]@{ Id = 'x'; Pw = '' }) 'anything') 'no password set: open'
$np = New-SocialProfileFromRecord $recA
Assert ($np.Id -eq $pb.Id -and $np.Pw -eq $h1 -and @($np.Friends).Count -eq @($recA.Friends).Count) 'profile from record'
# admins and name answers
Assert (@($all.Admins).Count -eq 0) 'no admins file: nobody'
Assert (Set-AdminList $wsA @($pb.Id)) 'write admins'
Assert (-not (Set-AdminList $wsA @())) 'never an empty admins list'
$reqs = @(Get-AdminNameRequests $all.Players @{ Names = @{}; Admins = @() })
Assert ($reqs.Count -eq 1 -and $reqs[0].NameReq -eq 'Newname') 'name request listed'
Assert (Set-AdminNameAnswer $wsA $pb.Id 'Newname' $true) 'approve name'
$all2 = Get-SocialPlayers $wsA
Assert (@($all2.Admins) -contains $pb.Id) 'admins read back'
Assert (Test-SocialIsAdmin $pb @{ Admins = $all2.Admins }) 'is admin'
Assert ($all2.Names[$pb.Id].Answer -eq 'approved') 'name answer read back'
Assert (@(Get-AdminNameRequests $all2.Players @{ Names = $all2.Names; Admins = @() }).Count -eq 0) 'answered request leaves the list'
$ex = Get-SocialCachedExtras $wsA
Assert (@($ex.Admins) -contains $pb.Id -and $ex.Names.ContainsKey($pb.Id)) 'extras from the cache'
$note = Update-SocialFromOnline $wsA $all2.Players $ex
$pc = Read-SocialProfile $wsA
Assert ($pc.Username -eq 'Newname' -and $pc.NameReq -eq '' -and $note -like '*approved*') 'approved name taken in'
Assert ((Update-SocialFromOnline $wsA $all2.Players $ex) -eq '') 'nothing twice'
# a newer password from another drive wins, an older one does not
$h2 = Get-SocialPasswordHash $pc.Id 'other'
$fake = [pscustomobject]@{ Id = $pc.Id; Pw = $h2; PwSet = '2026-10-11T10:00:00Z' }
[void](Update-SocialFromOnline $wsA @($fake) @{ Names = @{}; Admins = @() })
Assert ((Read-SocialProfile $wsA).Pw -eq $h2) 'newer password adopted'
$fake.Pw = $h1; $fake.PwSet = '2026-10-01T10:00:00Z'
[void](Update-SocialFromOnline $wsA @($fake) @{ Names = @{}; Admins = @() })
Assert ((Read-SocialProfile $wsA).Pw -eq $h2) 'older password ignored'
# logins
$pd = Read-SocialProfile $wsA
Add-SocialLogin $wsA $pd
Add-SocialLogin $wsA $pd
Assert (@(Get-SocialLogins $wsA).Count -eq 1) 'one login per profile'
Add-SocialLogin $wsA ([pscustomobject]@{ Id = 'bbbbbbbbbb'; Username = 'Bee'; Avatar = 'custom:abc' })
$lg = @(Get-SocialLogins $wsA)
Assert ($lg.Count -eq 2 -and $lg[0].Id -eq 'bbbbbbbbbb' -and $lg[0].Avatar -eq 'icon:gameboy') 'newest first, custom picture not kept'
Remove-SocialLogin $wsA 'bbbbbbbbbb'
Assert (@(Get-SocialLogins $wsA).Count -eq 1) 'forget a login'
# notify channel
Assert ((Get-SocialNotifyTopic $wsA) -eq '') 'no channel yet'
$tp = New-AdminNotifyTopic
Assert ($tp -match '^rbw-[a-z0-9]{16}$') 'channel name'
Assert (Set-AdminNotifyTopic $wsA $tp) 'save channel'
Assert ((Get-SocialNotifyTopic $wsA) -eq $tp) 'read channel'
# library.json writer: one game with one file stays a list
$j = ConvertTo-AdminLibraryJson 'a note \ with "quotes"' @([pscustomobject]@{ id = 'x'; title = 'X'; system = 'snes'; players = '1'; description = 'd'; added = '2026-10-10'; files = @([pscustomobject]@{ name = 'x.sfc'; url = 'https://github.com/a'; size = 5; sha256 = ('a' * 64) }) })
$jo = $j | ConvertFrom-Json
Assert ($jo.note -eq 'a note \ with "quotes"') 'note escaped'
Assert (@($jo.games).Count -eq 1 -and @($jo.games[0].files).Count -eq 1 -and $jo.games[0].files[0].size -eq 5) 'library json round trip'
Assert ($j -match '"files": \[') 'files written as a list'
Assert ((ConvertTo-AdminLibraryJson 'n' @() | ConvertFrom-Json).games.Count -eq 0) 'empty library'
Assert ((Get-AdminLibId 'Star Fox: The Sequel!!') -eq 'star-fox-the-sequel') 'library id'

Remove-Item -Recurse -Force $base
Write-Host ("social tests: {0} passed, {1} failed" -f $script:pass, $script:fail)
if ($script:fail -gt 0) { exit 1 }
