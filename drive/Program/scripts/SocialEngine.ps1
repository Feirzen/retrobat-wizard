<#
    SocialEngine.ps1 - profiles, friends and "now playing", through GitHub.

    FUNCTIONS ONLY. Dot-source it, it never does anything by itself. Used by:
        wizard\SetupWizard.ps1      the Profile tab
        scripts\Social-Helper.ps1   the background helper: check-ins, the
                                    "friend is online" popups

    THE IDEA (Steven, 2026-10-10)
    -----------------------------
    A light social layer with "no real protections", said plainly on screen.
    Everybody's wizard shares ONE fine-grained token that can only touch the
    private repo Feirzen/retrobat-wizard-social. Nobody needs a GitHub account.
    Worst case if the token is dug out: somebody scribbles on that repo, and
    git history puts it back.

    THE LOCAL PROFILE lives on the drive, in _Wizard\People\
    (never shipped, never touched by an update):
        profile.ini     id, username, picture, status, the toggles, and the
                        list of people this drive has friended
        avatar.png      a custom picture, 64 x 64, when one was chosen
    A guest has profile.ini with "guest = yes" and nothing is ever sent.

    ON GITHUB each person owns exactly ONE file, players\<id>.json, and only
    ever writes their own. That one rule is why two people can never overwrite
    each other, and it is enough for friend requests too:

        A lists B, B lists A        friends
        A lists B, B does not       A sent B a request (B sees it as incoming)
        B declines                  B puts A on B's own "declined" list,
                                    which only B's wizard reads

    READING EVERYBODY costs ONE request: a GraphQL query that returns every
    file in players\ with its text. With 20 people that keeps the whole group
    far under GitHub's 5000-requests-an-hour limit for the shared token.

    ASCII ONLY, Windows PowerShell 5.1. Every root is a parameter. One hook for
    the test harness:
        $script:SocialApiOverride   { param($Method, $Url, $BodyText, $Accept) -> @{ Status; Body } }
#>

$script:SocialDefaultRepo  = 'Feirzen/retrobat-wizard-social'
$script:SocialApiOverride  = $null
$script:SocialOnlineMinutes = 20     # seen within this long = online
$script:SocialIdPattern    = '^[a-z0-9]{10}$'

# ---------------------------------------------------------------------------
#  Paths and small helpers
# ---------------------------------------------------------------------------
function Join-SocialPath([string]$Base, [string]$Rel) {
    $p = $Base
    foreach ($seg in ($Rel -split '[\\/]')) { if ($seg -ne '') { $p = [System.IO.Path]::Combine($p, $seg) } }
    return $p
}

function Get-SocialPaths([string]$Ws) {
    return @{
        ProfileDir = Join-SocialPath $Ws 'People'
        Profile    = Join-SocialPath $Ws 'People\profile.ini'
        Avatar     = Join-SocialPath $Ws 'People\avatar.png'
        SocialDir  = Join-SocialPath $Ws 'People\social'
        Token      = Join-SocialPath $Ws 'People\social\social-token.txt'
        Config     = Join-SocialPath $Ws 'People\social\social.ini'
        Cache      = Join-SocialPath $Ws 'Cache\social'
        Players    = Join-SocialPath $Ws 'Cache\social\players.json'
        Log        = Join-SocialPath $Ws 'Cache\logs\social.log'
    }
}

function New-SocialDir([string]$Path) {
    if ($Path -and -not (Test-Path -LiteralPath $Path)) { [void](New-Item -ItemType Directory -Path $Path -Force) }
}

function Write-SocialLog([string]$Ws, [string]$Msg) {
    try {
        $P = Get-SocialPaths $Ws
        New-SocialDir (Split-Path -Parent $P.Log)
        if ((Test-Path -LiteralPath $P.Log) -and (Get-Item -LiteralPath $P.Log).Length -gt 512KB) {
            [System.IO.File]::WriteAllText($P.Log, '')    # a log, not a record: it just starts again
        }
        $line = "{0}  {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Msg
        [System.IO.File]::AppendAllText($P.Log, $line + "`r`n")
    } catch { }
}

function Get-SocialNowUtc { return [DateTime]::UtcNow }

function Format-SocialTime([DateTime]$Utc) { return $Utc.ToString('yyyy-MM-ddTHH:mm:ssZ', [Globalization.CultureInfo]::InvariantCulture) }

# PowerShell 7's ConvertFrom-Json turns a date string into a DateTime by
# itself and 5.1 does not, so a time read from JSON can arrive either way.
function Get-SocialTimeValue($Value) {
    if ($null -eq $Value) { return $null }
    if ($Value -is [DateTime]) { return $Value.ToUniversalTime() }
    return (ConvertFrom-SocialTime ([string]$Value))
}

function ConvertFrom-SocialTime([string]$Text) {
    $d = [DateTime]::MinValue
    $ok = [DateTime]::TryParseExact($Text, 'yyyy-MM-ddTHH:mm:ssZ', [Globalization.CultureInfo]::InvariantCulture,
        ([Globalization.DateTimeStyles]::AdjustToUniversal -bor [Globalization.DateTimeStyles]::AssumeUniversal), [ref]$d)
    if ($ok) { return $d }
    return $null
}

# Printable ASCII only, trimmed, capped. Everything that came from somebody
# else's file goes through here before it reaches the screen.
function Get-SocialClean([string]$Text, [int]$Max) {
    if ($null -eq $Text) { return '' }
    $t = ($Text -replace '[^\x20-\x7E]', '').Trim()
    if ($t.Length -gt $Max) { $t = $t.Substring(0, $Max).Trim() }
    return $t
}

function New-SocialId {
    $chars = 'abcdefghijklmnopqrstuvwxyz0123456789'
    $bytes = New-Object byte[] 10
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $rng.GetBytes($bytes)
    $out = ''
    foreach ($b in $bytes) { $out += $chars[$b % $chars.Length] }
    return $out
}

# '' when the name is fine, otherwise the reason in plain words.
function Test-SocialUsername([string]$Name) {
    $n = ([string]$Name).Trim()
    if ($n.Length -lt 3)  { return 'At least 3 letters.' }
    if ($n.Length -gt 20) { return 'At most 20 letters.' }
    if ($n -notmatch '^[A-Za-z0-9][A-Za-z0-9 _.\-]*[A-Za-z0-9]$') { return 'Letters, numbers, spaces, dots, dashes and underscores only, starting and ending with a letter or number.' }
    if ($n -match '  ') { return 'No double spaces.' }
    return ''
}

# ---------------------------------------------------------------------------
#  The token and the repo
# ---------------------------------------------------------------------------
#  social-token.txt holds the token either as it is (Steven's drive) or as
#  "rb1:" + base64 of the token backwards (what ships to friends). The second
#  form is not security, it only stops GitHub's secret scanner from spotting
#  a token in a download and switching it off.
function Get-SocialToken([string]$Ws) {
    $P = Get-SocialPaths $Ws
    if (-not (Test-Path -LiteralPath $P.Token)) { return '' }
    $t = ''
    try { $t = ([System.IO.File]::ReadAllText($P.Token)).Trim() } catch { return '' }
    if ($t.StartsWith('rb1:')) {
        try {
            $rev = [System.Text.Encoding]::ASCII.GetString([Convert]::FromBase64String($t.Substring(4)))
            $arr = $rev.ToCharArray(); [array]::Reverse($arr); $t = -join $arr
        } catch { return '' }
    }
    if ($t -notmatch '^(github_pat_|ghp_)[A-Za-z0-9_]+$') { return '' }
    return $t
}

function ConvertTo-SocialScrambled([string]$Token) {
    $arr = $Token.ToCharArray(); [array]::Reverse($arr)
    return ('rb1:' + [Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes((-join $arr))))
}

function Get-SocialRepo([string]$Ws) {
    $P = Get-SocialPaths $Ws
    if (Test-Path -LiteralPath $P.Config) {
        foreach ($line in [System.IO.File]::ReadAllLines($P.Config)) {
            $t = $line.Trim()
            if ($t -match '^repo\s*=\s*([A-Za-z0-9_.\-]+/[A-Za-z0-9_.\-]+)$') { return $Matches[1] }
        }
    }
    return $script:SocialDefaultRepo
}

# ---------------------------------------------------------------------------
#  The local profile
# ---------------------------------------------------------------------------
#  Returns $null when there is no profile at all (the first-run question has
#  not been answered). A guest comes back with Guest = $true.
function Read-SocialProfile([string]$Ws, [string]$File = '') {
    $P = Get-SocialPaths $Ws
    $pf = $(if ($File -ne '') { $File } else { $P.Profile })
    if (-not (Test-Path -LiteralPath $pf)) { return $null }
    $ini = @{}
    foreach ($line in [System.IO.File]::ReadAllLines($pf)) {
        $t = $line.Trim()
        if ($t -eq '' -or $t.StartsWith(';') -or $t.StartsWith('#')) { continue }
        $eq = $t.IndexOf('=')
        if ($eq -lt 1) { continue }
        $ini[$t.Substring(0, $eq).Trim().ToLower()] = $t.Substring($eq + 1).Trim()
    }
    function OnOff($v, [bool]$def) { if ($v -eq 'on') { return $true } elseif ($v -eq 'off') { return $false } else { return $def } }
    function IdList($v) { return @(([string]$v).Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ -match $script:SocialIdPattern } | Select-Object -Unique) }
    $status = [string]$ini['status']
    if (@('online', 'away', 'busy', 'invisible') -notcontains $status) { $status = 'online' }
    return [pscustomobject]@{
        Guest    = ([string]$ini['guest'] -eq 'yes')
        Id       = [string]$ini['id']
        Username = [string]$ini['username']
        Avatar   = $(if ($ini['avatar']) { [string]$ini['avatar'] } else { 'icon:gameboy' })
        Status   = $status
        Text     = Get-SocialClean ([string]$ini['text']) 40
        ShowGame = (OnOff $ini['showgame'] $true)
        Popups   = (OnOff $ini['popups'] $true)
        Friends  = (IdList $ini['friends'])
        Declined = (IdList $ini['declined'])
        Share    = (IdList $ini['share'])
        Created  = [string]$ini['created']
        Pw       = $(if ([string]$ini['pw'] -match '^[a-f0-9]{64}$') { [string]$ini['pw'] } else { '' })
        PwSet    = [string]$ini['pwset']
        NameReq  = Get-SocialClean ([string]$ini['namereq']) 20
        # 2026-10-12: three favourite games shown beside the name ("system|rom|picture",
        # paths relative to roms\<system>\), and whether the helper stays
        # running after the wizard and RetroBat close, so invites still arrive.
        Favs     = @((ConvertTo-SocialFavSlot ([string]$ini['fav1'])), (ConvertTo-SocialFavSlot ([string]$ini['fav2'])), (ConvertTo-SocialFavSlot ([string]$ini['fav3'])))
        Reach    = (OnOff $ini['reach'] $true)
    }
}

# One favourite slot as written in profile.ini: "system|rom|picture", or ''.
# Anything that does not look right is dropped, so a hand-edited file can
# never point the wizard outside roms\.
function ConvertTo-SocialFavSlot([string]$Text) {
    $t = $Text.Trim()
    if ($t -eq '') { return '' }
    $f = $t.Split('|')
    if ($f.Count -ne 3) { return '' }
    $sys = $f[0].Trim().ToLower()
    if ($sys -notmatch '^[a-z0-9\-]{1,20}$') { return '' }
    foreach ($rel in @($f[1], $f[2])) {
        if ($rel -match '\.\.' -or $rel -match '^[\\/]' -or $rel -match ':') { return '' }
    }
    if ($f[1].Trim() -eq '') { return '' }
    return ('{0}|{1}|{2}' -f $sys, $f[1].Trim(), $f[2].Trim())
}

function Write-SocialProfile([string]$Ws, $Prof) {
    $P = Get-SocialPaths $Ws
    New-SocialDir $P.ProfileDir
    $oo = { param($b) if ($b) { 'on' } else { 'off' } }
    $lines = @(
        '; ===========================================================================',
        ';  WHO IS USING THIS DRIVE - written by the wizard''s Profile tab.',
        '; ===========================================================================',
        ';  Never shipped and never touched by an update. Delete this folder and the',
        ';  wizard simply asks again. The friend lists are ids, not names, because a',
        ';  name can change and an id never does.',
        ''
    )
    if ($Prof.Guest) {
        $lines += 'guest    = yes'
    }
    else {
        $lines += @(
            ('id       = ' + $Prof.Id),
            ('username = ' + $Prof.Username),
            ('avatar   = ' + $Prof.Avatar),
            ('status   = ' + $Prof.Status),
            ('text     = ' + (Get-SocialClean $Prof.Text 40)),
            ('showgame = ' + (& $oo $Prof.ShowGame)),
            ('popups   = ' + (& $oo $Prof.Popups)),
            ('friends  = ' + (@($Prof.Friends) -join ',')),
            ('declined = ' + (@($Prof.Declined) -join ',')),
            ('share    = ' + (@($Prof.Share) -join ',')),
            ('created  = ' + $Prof.Created),
            ('pw       = ' + [string]$Prof.Pw),
            ('pwset    = ' + [string]$Prof.PwSet),
            ('namereq  = ' + (Get-SocialClean ([string]$Prof.NameReq) 20))
        )
        $favs = @($Prof.Favs)
        for ($i = 0; $i -lt 3; $i++) {
            $v = ''
            if ($i -lt $favs.Count) { $v = ConvertTo-SocialFavSlot ([string]$favs[$i]) }
            $lines += ('fav{0}     = {1}' -f ($i + 1), $v)
        }
        $reach = $true
        if ($null -ne $Prof.PSObject.Properties['Reach']) { $reach = [bool]$Prof.Reach }
        $lines += ('reach    = ' + (& $oo $reach))
    }
    [System.IO.File]::WriteAllLines($P.Profile, [string[]]$lines)
}

function New-SocialProfile([string]$Username, [string]$Avatar) {
    return [pscustomobject]@{
        Guest = $false; Id = (New-SocialId); Username = $Username.Trim(); Avatar = $Avatar
        Status = 'online'; Text = ''; ShowGame = $true; Popups = $true
        Friends = @(); Declined = @(); Share = @(); Created = (Format-SocialTime (Get-SocialNowUtc))
        Pw = ''; PwSet = ''; NameReq = ''; Favs = @('', '', ''); Reach = $true
    }
}

# ---------------------------------------------------------------------------
#  Talking to GitHub
# ---------------------------------------------------------------------------
#  Returns @{ Status = <http code, 0 when unreachable>; Body = <text> }.
#  Never throws.
function Invoke-SocialApi([string]$Ws, [string]$Method, [string]$Url, [string]$BodyText = '', [string]$Accept = 'application/vnd.github+json', [string]$OutFile = '') {
    if ($null -ne $script:SocialApiOverride) { return (& $script:SocialApiOverride $Method $Url $BodyText $Accept) }
    $r = @{ Status = 0; Body = '' }
    $token = Get-SocialToken $Ws
    if ($token -eq '') { $r.Body = 'no token'; return $r }
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch { }
    $oldPref = $ProgressPreference
    $ProgressPreference = 'SilentlyContinue'
    try {
        $h = @{ Authorization = "Bearer $token"; Accept = $Accept; 'X-GitHub-Api-Version' = '2022-11-28' }
        $args2 = @{ Uri = $Url; Method = $Method; Headers = $h; UseBasicParsing = $true; TimeoutSec = 30; ErrorAction = 'Stop' }
        if ($BodyText -ne '') {
            $args2.Body = [System.Text.Encoding]::UTF8.GetBytes($BodyText)
            $args2.ContentType = 'application/json; charset=utf-8'
        }
        if ($OutFile -ne '') { $args2.OutFile = $OutFile }
        $resp = Invoke-WebRequest @args2
        if ($OutFile -ne '') { $r.Status = 200 }
        else {
            $r.Status = [int]$resp.StatusCode
            # THE 2026-10-11 FIX. Windows PowerShell 5.1 hands back a file
            # asked for "raw" (admin\notify.txt) as a list of BYTES, not
            # text, and [string] of that is "114 98 119 ...". That is why
            # phone alerts never fired: the channel name never matched.
            $c = $resp.Content
            if ($c -is [byte[]]) { $r.Body = [System.Text.Encoding]::UTF8.GetString($c) }
            else { $r.Body = [string]$c }
        }
    }
    catch {
        $code = 0
        try { $code = [int]$_.Exception.Response.StatusCode } catch { }
        $r.Status = $code
        $r.Body = $_.Exception.Message
    }
    finally { $ProgressPreference = $oldPref }
    return $r
}

function ConvertTo-SocialJsonString([string]$s) {
    $o = $s.Replace('\', '\\').Replace('"', '\"')
    $o = $o -replace "[`r`n`t]", ' '
    return '"' + $o + '"'
}

# The one file each person owns. Written by hand rather than ConvertTo-Json,
# because Windows PowerShell 5.1 and 7 disagree about one-item lists.
function ConvertTo-SocialRecordJson($Prof, $Presence, [string]$Version, $Stats = $null, $Live = $null) {
    $j = New-Object System.Text.StringBuilder
    [void]$j.Append('{')
    [void]$j.Append('"v":1')
    [void]$j.Append(',"id":' + (ConvertTo-SocialJsonString $Prof.Id))
    [void]$j.Append(',"username":' + (ConvertTo-SocialJsonString $Prof.Username))
    [void]$j.Append(',"avatar":' + (ConvertTo-SocialJsonString $Prof.Avatar))
    [void]$j.Append(',"status":' + (ConvertTo-SocialJsonString $Prof.Status))
    [void]$j.Append(',"text":' + (ConvertTo-SocialJsonString (Get-SocialClean $Prof.Text 40)))
    [void]$j.Append(',"state":' + (ConvertTo-SocialJsonString $Presence.State))
    $game = ''; $console = ''; $since = ''
    if ($Presence.InGame) {
        if ($Prof.ShowGame) { $game = Get-SocialClean $Presence.Game 60; $console = Get-SocialClean $Presence.Console 30 }
        $since = [string]$Presence.Since
    }
    [void]$j.Append(',"ingame":' + $(if ($Presence.InGame) { 'true' } else { 'false' }))
    [void]$j.Append(',"game":' + (ConvertTo-SocialJsonString $game))
    [void]$j.Append(',"console":' + (ConvertTo-SocialJsonString $console))
    [void]$j.Append(',"since":' + (ConvertTo-SocialJsonString $since))
    [void]$j.Append(',"seen":' + (ConvertTo-SocialJsonString (Format-SocialTime (Get-SocialNowUtc))))
    [void]$j.Append(',"version":' + (ConvertTo-SocialJsonString $Version))
    [void]$j.Append(',"pw":' + (ConvertTo-SocialJsonString ([string]$Prof.Pw)))
    [void]$j.Append(',"pwset":' + (ConvertTo-SocialJsonString ([string]$Prof.PwSet)))
    [void]$j.Append(',"namereq":' + (ConvertTo-SocialJsonString (Get-SocialClean ([string]$Prof.NameReq) 20)))
    $ids = @(@($Prof.Friends) | Where-Object { $_ -match $script:SocialIdPattern } | ForEach-Object { '"' + $_ + '"' })
    [void]$j.Append(',"friends":[' + ($ids -join ',') + ']')
    # Played games (2026-10-11): only when this person shares them with at
    # least one friend ("for" lists who). Left out entirely otherwise.
    $for = @(@($Prof.Share) | Where-Object { $_ -match $script:SocialIdPattern -and @($Prof.Friends) -contains $_ })
    if ($null -ne $Stats -and $for.Count -gt 0) {
        $one = {
            param($g)
            $t = ''
            if ($null -ne $g.Last) { $t = ([DateTime]$g.Last).ToString('yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture) }
            '{"n":' + (ConvertTo-SocialJsonString (Get-SocialClean ([string]$g.Name) 60)) + ',"s":' + (ConvertTo-SocialJsonString ([string]$g.System)) +
            ',"m":' + ([int][math]::Round([double]$g.Minutes)) + ',"t":' + (ConvertTo-SocialJsonString $t) + '}'
        }
        $part = { param($list) (@(@($list) | Where-Object { $null -ne $_ } | ForEach-Object { & $one $_ }) -join ',') }
        [void]$j.Append(',"games":{"for":[' + ((@($for | ForEach-Object { '"' + $_ + '"' })) -join ',') + ']')
        [void]$j.Append(',"top":[' + (& $part $Stats.Top) + ']')
        [void]$j.Append(',"recent":[' + (& $part $Stats.Recent) + ']')
        # RetroBat's star list is no longer shown (Steven, 2026-10-12); the
        # three favourites picked on the profile go in "favs" below instead.
        [void]$j.Append(',"fav":[]}')
    }
    # 2026-10-12: the three favourite games (always sent: they are chosen to
    # be shown), the play-together invite, and the answer to one.
    if ($null -ne $Live) {
        $fv = @(@($Live.Favs) | Where-Object { $null -ne $_ } | Select-Object -First 3 | ForEach-Object {
            '{"n":' + (ConvertTo-SocialJsonString (Get-SocialClean ([string]$_.Name) 60)) + ',"s":' + (ConvertTo-SocialJsonString ([string]$_.System)) + '}'
        })
        [void]$j.Append(',"favs":[' + ($fv -join ',') + ']')
        $inv = $Live.Invite
        if ($null -ne $inv) {
            $to = @(@($inv.To) | Where-Object { $_ -match $script:SocialIdPattern } | ForEach-Object { '"' + $_ + '"' })
            [void]$j.Append(',"invite":{"id":' + (ConvertTo-SocialJsonString ([string]$inv.Id)) + ',"to":[' + ($to -join ',') + ']' +
                ',"n":' + (ConvertTo-SocialJsonString (Get-SocialClean ([string]$inv.Game) 60)) +
                ',"s":' + (ConvertTo-SocialJsonString ([string]$inv.System)) +
                ',"note":' + (ConvertTo-SocialJsonString (Get-SocialClean ([string]$inv.Note) 60)) +
                ',"code":' + (ConvertTo-SocialJsonString (Get-SocialClean ([string]$inv.Code) 40)) +
                ',"at":' + (ConvertTo-SocialJsonString ([string]$inv.At)) + '}')
        }
        $rp = $Live.Reply
        if ($null -ne $rp) {
            [void]$j.Append(',"reply":{"to":' + (ConvertTo-SocialJsonString ([string]$rp.To)) + ',"inv":' + (ConvertTo-SocialJsonString ([string]$rp.Inv)) +
                ',"ans":' + (ConvertTo-SocialJsonString ([string]$rp.Ans)) + ',"at":' + (ConvertTo-SocialJsonString ([string]$rp.At)) + '}')
        }
    }
    [void]$j.Append('}')
    return $j.ToString()
}

# One person's file, read back defensively. Anybody with the token can write
# anything, so a record that does not look right is dropped, never trusted.
function ConvertFrom-SocialRecord([string]$Text, [string]$BlobId) {
    try { $o = $Text | ConvertFrom-Json } catch { return $null }
    if ($null -eq $o) { return $null }
    $id = [string]$o.id
    if ($id -notmatch $script:SocialIdPattern) { return $null }
    $name = Get-SocialClean ([string]$o.username) 20
    if ($name -eq '') { return $null }
    $status = [string]$o.status
    if (@('online', 'away', 'busy', 'invisible') -notcontains $status) { $status = 'online' }
    $avatar = [string]$o.avatar
    if ($avatar -notmatch '^(icon:[a-z0-9\-]{1,30}|custom:[a-f0-9]{1,40})$') { $avatar = 'icon:gameboy' }
    return [pscustomobject]@{
        Id       = $id
        Username = $name
        Avatar   = $avatar
        Status   = $status
        Text     = Get-SocialClean ([string]$o.text) 40
        State    = $(if ([string]$o.state -eq 'offline') { 'offline' } else { 'on' })
        InGame   = ($o.ingame -eq $true)
        Game     = Get-SocialClean ([string]$o.game) 60
        Console  = Get-SocialClean ([string]$o.console) 30
        Since    = Get-SocialTimeValue $o.since
        Seen     = Get-SocialTimeValue $o.seen
        Friends  = @(@($o.friends) | ForEach-Object { [string]$_ } | Where-Object { $_ -match $script:SocialIdPattern } | Select-Object -Unique)
        Pw       = $(if ([string]$o.pw -match '^[a-f0-9]{64}$') { [string]$o.pw } else { '' })
        PwSet    = $(if ($o.pwset -is [DateTime]) { Format-SocialTime $o.pwset.ToUniversalTime() } else { Get-SocialClean ([string]$o.pwset) 20 })
        NameReq  = Get-SocialClean ([string]$o.namereq) 20
        Games    = (ConvertFrom-SocialGames $o.games)
        Favs     = @(@($o.favs) | Select-Object -First 3 | ForEach-Object { ConvertFrom-SocialGameItem $_ } | Where-Object { $null -ne $_ })
        Invite   = (ConvertFrom-SocialInvite $o.invite)
        Reply    = (ConvertFrom-SocialReply $o.reply)
        Blob     = $BlobId
    }
}

# Everybody, in one request. Returns @{ Ok; Players; Message }. On success the
# list is also saved to social\cache\players.json, so the wizard can draw the
# friend list straight away next time, before the network answers.
function Get-SocialPlayers([string]$Ws) {
    $res = @{ Ok = $false; Players = @(); Message = ''; Names = @{}; Admins = @(); Resets = @{} }
    $repo = Get-SocialRepo $Ws
    $owner, $name = $repo.Split('/')
    # One request for everything: players\ (the people), names\ (the admins'
    # answers to name requests) and admin\admins.txt (who the admins are).
    $q = 'query { repository(owner: \"' + $owner + '\", name: \"' + $name + '\") { object(expression: \"HEAD:players\") { ... on Tree { entries { name object { ... on Blob { oid text byteSize } } } } } names: object(expression: \"HEAD:names\") { ... on Tree { entries { name object { ... on Blob { text byteSize } } } } } admins: object(expression: \"HEAD:admin/admins.txt\") { ... on Blob { text } } } }'
    $r = Invoke-SocialApi $Ws 'POST' 'https://api.github.com/graphql' ('{"query":"' + $q + '"}')
    if ($r.Status -ne 200) {
        $res.Message = $(if ($r.Status -eq 0) { 'Could not reach GitHub.' } else { "GitHub said $($r.Status)." })
        Write-SocialLog $Ws ("players: fetch failed, {0} {1}" -f $r.Status, $r.Body)
        return $res
    }
    try { $d = $r.Body | ConvertFrom-Json } catch { $res.Message = 'GitHub sent something unreadable.'; return $res }
    if ($d.errors) { $res.Message = 'GitHub refused the question.'; Write-SocialLog $Ws ("players: " + ($d.errors | ConvertTo-Json -Compress)); return $res }
    $list = New-Object System.Collections.ArrayList
    $obj = $null
    try { $obj = $d.data.repository.object } catch { }
    if ($null -ne $obj) {
        foreach ($e in @($obj.entries)) {
            if ([string]$e.name -notmatch '^[a-z0-9]{10}\.json$') { continue }
            if ($null -eq $e.object -or [int]$e.object.byteSize -gt 8192) { continue }
            $rec = ConvertFrom-SocialRecord ([string]$e.object.text) ([string]$e.object.oid)
            if ($null -ne $rec -and ($rec.Id + '.json') -eq [string]$e.name) { [void]$list.Add($rec) }
        }
    }
    $res.Ok = $true
    $res.Players = $list.ToArray()
    $x = ConvertFrom-SocialExtras $d
    $res.Names = $x.Names; $res.Admins = $x.Admins; $res.Resets = $x.Resets
    try {
        $P = Get-SocialPaths $Ws
        New-SocialDir $P.Cache
        [System.IO.File]::WriteAllText($P.Players, ([string]$r.Body))
    } catch { }
    return $res
}

# The last list that arrived, from the cache, for drawing before the network
# answers. Empty when there is none.
function Get-SocialCachedPlayers([string]$Ws) {
    $P = Get-SocialPaths $Ws
    if (-not (Test-Path -LiteralPath $P.Players)) { return @() }
    try {
        $d = [System.IO.File]::ReadAllText($P.Players) | ConvertFrom-Json
        $out = @()
        foreach ($e in @($d.data.repository.object.entries)) {
            $rec = ConvertFrom-SocialRecord ([string]$e.object.text) ([string]$e.object.oid)
            if ($null -ne $rec) { $out += $rec }
        }
        return $out
    } catch { return @() }
}

# Writes this drive's own players\<id>.json. $Presence: State ('on' or
# 'offline'), InGame, Game, Console, Since. Returns @{ Ok; Message }.
function Publish-SocialRecord([string]$Ws, $Prof, $Presence, [string]$Version, [string]$KnownBlob = '', $Stats = $null, $Live = $null) {
    $res = @{ Ok = $false; Message = '' }
    if ($null -eq $Prof -or $Prof.Guest -or $Prof.Id -notmatch $script:SocialIdPattern) { $res.Message = 'No profile, nothing to send.'; return $res }
    $repo = Get-SocialRepo $Ws
    $url = "https://api.github.com/repos/$repo/contents/players/$($Prof.Id).json"
    $json = ConvertTo-SocialRecordJson $Prof $Presence $Version $Stats $Live
    $b64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($json))

    $sha = $KnownBlob
    for ($attempt = 1; $attempt -le 2; $attempt++) {
        $body = '{"message":' + (ConvertTo-SocialJsonString ("check-in " + $Prof.Id)) + ',"content":"' + $b64 + '"'
        if ($sha -ne '') { $body += ',"sha":"' + $sha + '"' }
        $body += '}'
        $r = Invoke-SocialApi $Ws 'PUT' $url $body
        if ($r.Status -eq 200 -or $r.Status -eq 201) { $res.Ok = $true; return $res }
        if ($attempt -eq 1 -and ($r.Status -eq 409 -or $r.Status -eq 422)) {
            # The file is there but the id we had for it is stale (or we had
            # none). Ask for the current one and try exactly once more.
            $g = Invoke-SocialApi $Ws 'GET' $url
            $sha = ''
            if ($g.Status -eq 200) { try { $sha = [string](($g.Body | ConvertFrom-Json).sha) } catch { } }
            continue
        }
        $res.Message = $(if ($r.Status -eq 0) { 'Could not reach GitHub.' } else { "GitHub said $($r.Status)." })
        Write-SocialLog $Ws ("publish: failed, {0} {1}" -f $r.Status, $r.Body)
        return $res
    }
    $res.Message = 'GitHub kept refusing the check-in.'
    return $res
}

# Uploads profile\avatar.png as avatars\<id>.png. Returns the new avatar value
# ("custom:<first 12 of its blob id>", so friends know to fetch it again when
# it changes) or '' on failure.
function Publish-SocialAvatar([string]$Ws, $Prof) {
    $P = Get-SocialPaths $Ws
    if (-not (Test-Path -LiteralPath $P.Avatar)) { return '' }
    $bytes = [System.IO.File]::ReadAllBytes($P.Avatar)
    if ($bytes.Length -gt 200KB) { Write-SocialLog $Ws 'avatar: too big, not sent'; return '' }
    $repo = Get-SocialRepo $Ws
    $url = "https://api.github.com/repos/$repo/contents/avatars/$($Prof.Id).png"
    $sha = ''
    $g = Invoke-SocialApi $Ws 'GET' $url
    if ($g.Status -eq 200) { try { $sha = [string](($g.Body | ConvertFrom-Json).sha) } catch { } }
    $body = '{"message":"avatar ' + $Prof.Id + '","content":"' + [Convert]::ToBase64String($bytes) + '"'
    if ($sha -ne '') { $body += ',"sha":"' + $sha + '"' }
    $body += '}'
    $r = Invoke-SocialApi $Ws 'PUT' $url $body
    if ($r.Status -ne 200 -and $r.Status -ne 201) { Write-SocialLog $Ws ("avatar: failed {0}" -f $r.Status); return '' }
    try {
        $new = [string](($r.Body | ConvertFrom-Json).content.sha)
        if ($new -match '^[a-f0-9]{12,}') { return ('custom:' + $new.Substring(0, 12)) }
    } catch { }
    return ('custom:' + ([Guid]::NewGuid().ToString('N').Substring(0, 12)))
}

# A friend's custom picture, fetched once per version and kept in
# social\cache\avatars\. Returns the local path, or '' when there is none.
function Get-SocialAvatarFile([string]$Ws, $Player) {
    if ([string]$Player.Avatar -notmatch '^custom:([a-f0-9]{1,40})$') { return '' }
    $tag = $Matches[1]
    $P = Get-SocialPaths $Ws
    $dir = Join-SocialPath $P.Cache 'avatars'
    $file = Join-SocialPath $dir ($Player.Id + '-' + $tag + '.png')
    if (Test-Path -LiteralPath $file) { return $file }
    New-SocialDir $dir
    $repo = Get-SocialRepo $Ws
    $tmp = $file + '.part'
    $r = Invoke-SocialApi $Ws 'GET' "https://api.github.com/repos/$repo/contents/avatars/$($Player.Id).png" '' 'application/vnd.github.raw' $tmp
    if ($r.Status -ne 200 -or -not (Test-Path -LiteralPath $tmp)) { return '' }
    if ((Get-Item -LiteralPath $tmp).Length -gt 200KB) { Remove-Item -LiteralPath $tmp -Force; return '' }
    Move-Item -LiteralPath $tmp -Destination $file -Force
    return $file
}

# ---------------------------------------------------------------------------
#  Making sense of everybody
# ---------------------------------------------------------------------------
#  What one person looks like from the outside right now:
#      Kind  = playing | online | away | busy | offline
#      Line  = the words under their name
function Get-SocialPresence($Player, [DateTime]$NowUtc) {
    $seenOk = ($null -ne $Player.Seen) -and (($NowUtc - $Player.Seen).TotalMinutes -le $script:SocialOnlineMinutes)
    if (-not $seenOk -or $Player.State -eq 'offline' -or $Player.Status -eq 'invisible') {
        $line = 'Offline'
        if ($null -ne $Player.Seen -and $Player.Status -ne 'invisible') {
            $ago = $NowUtc - $Player.Seen
            if     ($ago.TotalHours -lt 1)  { $line = 'Offline, here {0} min ago' -f [int][math]::Max(1, $ago.TotalMinutes) }
            elseif ($ago.TotalDays -lt 1)   { $line = 'Offline, here {0} h ago' -f [int]$ago.TotalHours }
            elseif ($ago.TotalDays -lt 60)  { $line = 'Offline, here {0} days ago' -f [int]$ago.TotalDays }
        }
        return [pscustomobject]@{ Kind = 'offline'; Line = $line }
    }
    if ($Player.InGame) {
        $mins = ''
        if ($null -ne $Player.Since) {
            $m = [int][math]::Max(0, ($NowUtc - $Player.Since).TotalMinutes)
            $mins = $(if ($m -lt 60) { " for $m min" } else { " for {0} h {1} min" -f [int][math]::Floor($m / 60), ($m % 60) })
        }
        if ($Player.Game -ne '') {
            $what = $Player.Game
            if ($Player.Console -ne '') { $what += " ($($Player.Console))" }
            return [pscustomobject]@{ Kind = 'playing'; Line = "Playing $what$mins" }
        }
        return [pscustomobject]@{ Kind = 'playing'; Line = "In a game$mins" }
    }
    $word = @{ online = 'Online'; away = 'Away'; busy = 'Busy' }[$Player.Status]
    if ($Player.Text -ne '') { $word += ' - ' + $Player.Text }
    return [pscustomobject]@{ Kind = $Player.Status; Line = $word }
}

# Splits everybody into the lists the Profile tab draws.
function Get-SocialView($Prof, $Players, [DateTime]$NowUtc) {
    $byId = @{}
    foreach ($p in @($Players | Where-Object { $null -ne $_ })) { if ($p.Id -ne $Prof.Id) { $byId[$p.Id] = $p } }
    $mine = @($Prof.Friends)
    $declined = @($Prof.Declined)
    $friends = @(); $incoming = @(); $outgoing = @()
    foreach ($id in $mine) {
        if (-not $byId.ContainsKey($id)) { continue }
        $p = $byId[$id]
        if (@($p.Friends) -contains $Prof.Id) { $friends += $p } else { $outgoing += $p }
    }
    foreach ($p in $byId.Values) {
        if ($mine -contains $p.Id) { continue }
        if ($declined -contains $p.Id) { continue }
        if (@($p.Friends) -contains $Prof.Id) { $incoming += $p }
    }
    $order = @{ playing = 0; online = 1; busy = 2; away = 3; offline = 4 }
    $friends = @($friends | Sort-Object @{ Expression = { $order[(Get-SocialPresence $_ $NowUtc).Kind] } }, @{ Expression = { $_.Username } })
    return [pscustomobject]@{
        Friends  = $friends
        Incoming = @($incoming | Sort-Object Username)
        Outgoing = @($outgoing | Sort-Object Username)
    }
}

# People whose name contains the words typed, not counting this drive's own
# profile. Capped at 20 - there are not many people, but a list should end.
function Find-SocialPlayers($Prof, $Players, [string]$Query) {
    $q = ([string]$Query).Trim()
    if ($q.Length -lt 1) { return @() }
    $found = @(@($Players) | Where-Object { $null -ne $_ -and $_.Id -ne $Prof.Id -and $_.Username.IndexOf($q, [StringComparison]::OrdinalIgnoreCase) -ge 0 } |
               Sort-Object @{ Expression = { -not $_.Username.StartsWith($q, [StringComparison]::OrdinalIgnoreCase) } }, Username)
    return @($found | Select-Object -First 20)
}

function Test-SocialNameTaken($Players, [string]$Name, [string]$MyId) {
    # Nulls skipped on purpose: an EMPTY player list that went through $( )
    # arrives as one $null, which is how making the very first profile
    # crashed the wizard on 2026-10-10.
    foreach ($p in @($Players | Where-Object { $null -ne $_ })) {
        if ($p.Id -ne $MyId -and ([string]$p.Username).Trim().ToLower() -eq $Name.Trim().ToLower()) { return $true }
    }
    return $false
}

# ---------------------------------------------------------------------------
#  Admins and name requests                                     (2026-10-10)
# ---------------------------------------------------------------------------
#  admin\admins.txt in the private repo: one player id per line. Being on it
#  shows the Admin tab in the wizard; that is all it does.
#  names\<id>.txt: an admin's answer to that person's name request, either
#  "approved:<name>" or "declined:<name>". The person's own wizard reads it
#  and changes (or keeps) the name, because only they write their own file.
#  names\<id>-pw.txt (2026-10-25): "reset:<time>", an admin's password reset.
#  Until that person sets a new password, they can log in without one.
function ConvertFrom-SocialExtras($Data) {
    $out = @{ Names = @{}; Admins = @(); Resets = @{} }
    try {
        foreach ($e in @($Data.data.repository.names.entries)) {
            if ([string]$e.name -match '^([a-z0-9]{10})-pw\.txt$') {
                $rid = $Matches[1]
                if ($null -ne $e.object -and [int]$e.object.byteSize -le 100 -and ([string]$e.object.text).Trim() -match '^reset:(\S+)$') { $out.Resets[$rid] = $Matches[1] }
                continue
            }
            if ([string]$e.name -notmatch '^([a-z0-9]{10})\.txt$') { continue }
            $id = $Matches[1]
            if ($null -eq $e.object -or [int]$e.object.byteSize -gt 200) { continue }
            $t = Get-SocialClean ([string]$e.object.text) 40
            if ($t -match '^(approved|declined):(.+)$') { $out.Names[$id] = @{ Answer = $Matches[1]; Name = $Matches[2].Trim() } }
        }
    } catch { }
    try {
        $txt = [string]$Data.data.repository.admins.text
        $out.Admins = @($txt -split '[\r\n, ]+' | ForEach-Object { $_.Trim() } | Where-Object { $_ -match $script:SocialIdPattern } | Select-Object -Unique)
    } catch { }
    return $out
}

function Get-SocialCachedExtras([string]$Ws) {
    $P = Get-SocialPaths $Ws
    if (-not (Test-Path -LiteralPath $P.Players)) { return @{ Names = @{}; Admins = @(); Resets = @{} } }
    try { return (ConvertFrom-SocialExtras ([System.IO.File]::ReadAllText($P.Players) | ConvertFrom-Json)) }
    catch { return @{ Names = @{}; Admins = @(); Resets = @{} } }
}

function Test-SocialIsAdmin($Prof, $Extras) {
    if ($null -eq $Prof -or $Prof.Guest) { return $false }
    return (@($Extras.Admins) -contains $Prof.Id)
}

# After a fetch: takes in what changed online for this drive's own profile.
#   - an admin answered the name request: the name changes, or stays
#   - the password was changed on another drive (newer pwset): take it
# Writes profile.ini only when something changed. Returns '' or a sentence
# for the person ("Your new name was approved.").
function Update-SocialFromOnline([string]$Ws, $Players, $Extras) {
    $p = $null
    try { $p = Read-SocialProfile $Ws } catch { return '' }
    if ($null -eq $p -or $p.Guest) { return '' }
    $note = ''; $changed = $false
    if ($p.NameReq -ne '' -and $Extras.Names.ContainsKey($p.Id)) {
        $a = $Extras.Names[$p.Id]
        if ($a.Name -eq $p.NameReq) {
            if ($a.Answer -eq 'approved') { $p.Username = $p.NameReq; $note = "Your new name, $($p.NameReq), was approved." }
            else { $note = "Your name request ($($p.NameReq)) was not approved." }
            $p.NameReq = ''; $changed = $true
        }
    }
    foreach ($r in @($Players | Where-Object { $null -ne $_ -and $_.Id -eq $p.Id })) {
        if ($r.Pw -ne '' -and $r.Pw -ne $p.Pw -and [string]$r.PwSet -gt [string]$p.PwSet) { $p.Pw = $r.Pw; $p.PwSet = $r.PwSet; $changed = $true }
    }
    if ($changed) { Write-SocialProfile $Ws $p }
    return $note
}

# ---------------------------------------------------------------------------
#  Passwords and logging in                                     (2026-10-10)
# ---------------------------------------------------------------------------
#  A light lock, said plainly on screen: it keeps friends from logging in as
#  each other on a shared drive, nothing more. Only a hash is stored (in
#  profile.ini and in the person's own file online), never the password.
function Get-SocialPasswordHash([string]$Id, [string]$Password) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $b = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes('rbw-pw:' + $Id + ':' + $Password))
    return (($b | ForEach-Object { $_.ToString('x2') }) -join '')
}

# An admin reset this person's password after they last set one?
function Test-SocialPwReset($Record, $Resets) {
    if ($null -eq $Record -or $null -eq $Resets -or -not $Resets.ContainsKey([string]$Record.Id)) { return $false }
    return ([string]$Resets[[string]$Record.Id] -gt [string]$Record.PwSet)
}

function Test-SocialPassword($Record, [string]$Password) {
    if ($null -eq $Record) { return $false }
    if ([string]$Record.Pw -eq '') { return $true }     # no password set yet
    return ((Get-SocialPasswordHash $Record.Id $Password) -eq $Record.Pw)
}

# The profile a drive gets when somebody logs in: everything that is online.
function New-SocialProfileFromRecord($Rec) {
    return [pscustomobject]@{
        Guest = $false; Id = $Rec.Id; Username = $Rec.Username; Avatar = $Rec.Avatar
        Status = $(if ($Rec.Status) { $Rec.Status } else { 'online' }); Text = $Rec.Text
        ShowGame = $true; Popups = $true; Friends = @($Rec.Friends); Declined = @()
        Share = $(if ($null -ne $Rec.Games) { @($Rec.Games.For) } else { @() })
        Created = ''; Pw = $Rec.Pw; PwSet = $Rec.PwSet; NameReq = $Rec.NameReq
        Favs = @('', '', ''); Reach = $true
    }
}

# Previous logins on this drive: profile\logins.txt, "id|name|avatar" lines.
function Get-SocialLogins([string]$Ws) {
    $P = Get-SocialPaths $Ws
    $f = Join-SocialPath $P.ProfileDir 'logins.txt'
    $out = @()
    if (Test-Path -LiteralPath $f) {
        foreach ($l in [System.IO.File]::ReadAllLines($f)) {
            $parts = $l.Split('|')
            if ($parts.Count -ge 3 -and $parts[0] -match $script:SocialIdPattern) {
                $av = [string]$parts[2]
                if ($av -notmatch '^(icon:[a-z0-9\-]{1,30}|custom:[a-f0-9]{1,40})$') { $av = 'icon:gameboy' }
                $tr = ''
                if ($parts.Count -ge 4 -and $parts[3] -match '^\d{4}-\d{2}-\d{2}$') { $tr = $parts[3] }
                $out += [pscustomobject]@{ Id = $parts[0]; Username = (Get-SocialClean $parts[1] 20); Avatar = $av; Trusted = $tr }
            }
        }
    }
    # The one kept by "play as a guest" before logins existed.
    $old = Join-SocialPath $P.ProfileDir 'profile-before-guest.ini'
    if ((Test-Path -LiteralPath $old) -and -not (Test-Path -LiteralPath $f)) {
        try {
            $oid = ''; $oname = ''
            foreach ($l in [System.IO.File]::ReadAllLines($old)) { if ($l -match '^\s*id\s*=\s*([a-z0-9]{10})\s*$') { $oid = $Matches[1] }; if ($l -match '^\s*username\s*=\s*(.+)$') { $oname = $Matches[1].Trim() } }
            if ($oid -and $oname) { $out += [pscustomobject]@{ Id = $oid; Username = $oname; Avatar = 'icon:gameboy'; Trusted = '' } }
        } catch { }
    }
    # one per profile, newest first (Group-Object would sort them in PS 7)
    $seen = @{}; $uniq = @()
    foreach ($o in $out) { if (-not $seen.ContainsKey($o.Id)) { $seen[$o.Id] = $true; $uniq += $o } }
    return $uniq
}

function Save-SocialLogins([string]$Ws, $List) {
    $P = Get-SocialPaths $Ws
    New-SocialDir $P.ProfileDir
    $lines = @($List | ForEach-Object { '{0}|{1}|{2}|{3}' -f $_.Id, $_.Username, $_.Avatar, [string]$_.Trusted })
    [System.IO.File]::WriteAllLines((Join-SocialPath $P.ProfileDir 'logins.txt'), [string[]]$lines)
}

# Since 2026-10-12 (Steven: the picture in "Log back in" was not his) a
# custom picture is remembered too: its value is kept, and a copy goes into
# social\cache\avatars\ where the list reads it after logging out.
function Add-SocialLogin([string]$Ws, $Prof, [bool]$Trusted = $false) {
    $all = @(Get-SocialLogins $Ws)
    $was = @($all | Where-Object { $_.Id -eq $Prof.Id }) | Select-Object -First 1
    $tr = $(if ($Trusted) { (Get-Date).ToString('yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture) } elseif ($null -ne $was) { [string]$was.Trusted } else { '' })
    $list = @($all | Where-Object { $_.Id -ne $Prof.Id })
    $av = [string]$Prof.Avatar
    if ($av -match '^custom:([a-f0-9]{1,40})$') {
        $tag = $Matches[1]
        try {
            $P = Get-SocialPaths $Ws
            if (Test-Path -LiteralPath $P.Avatar) {
                $d = Join-SocialPath $P.Cache 'avatars'
                New-SocialDir $d
                Copy-Item -LiteralPath $P.Avatar -Destination (Join-SocialPath $d ($Prof.Id + '-' + $tag + '.png')) -Force
            }
        } catch { }
    }
    elseif ($av -notmatch '^icon:[a-z0-9\-]{1,30}$') { $av = 'icon:gameboy' }
    Save-SocialLogins $Ws (@([pscustomobject]@{ Id = $Prof.Id; Username = $Prof.Username; Avatar = $av; Trusted = $tr }) + $list)
}

function Remove-SocialLogin([string]$Ws, [string]$Id) {
    Save-SocialLogins $Ws @(Get-SocialLogins $Ws | Where-Object { $_.Id -ne $Id })
}

# ---------------------------------------------------------------------------
#  Phone alerts for admins (ntfy)                               (2026-10-10)
# ---------------------------------------------------------------------------
#  admin\notify.txt in the private repo names an ntfy.sh channel. A new
#  report or name request pings it, and an admin's phone with the free ntfy
#  app buzzes. No channel there, no ping. Never throws, never waits long.
function Get-SocialNotifyTopic([string]$Ws) {
    $repo = Get-SocialRepo $Ws
    $r = Invoke-SocialApi $Ws 'GET' "https://api.github.com/repos/$repo/contents/admin/notify.txt" '' 'application/vnd.github.raw'
    if ($r.Status -ne 200) { return '' }
    $t = ([string]$r.Body).Trim()
    if ($t -match '^[A-Za-z0-9_\-]{8,64}$') { return $t }
    return ''
}

function Send-SocialNotify([string]$Ws, [string]$Title, [string]$Text) {
    try {
        $topic = Get-SocialNotifyTopic $Ws
        if ($topic -eq '') { Write-SocialLog $Ws 'notify: no alert channel found online, nothing sent'; return $false }
        $h = @{ Title = (Get-SocialClean $Title 80); Tags = 'video_game' }
        Invoke-WebRequest -Uri ("https://ntfy.sh/" + $topic) -Method Post -Headers $h -Body ([System.Text.Encoding]::UTF8.GetBytes((Get-SocialClean $Text 300))) -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop | Out-Null
        Write-SocialLog $Ws ('notify: sent "' + (Get-SocialClean $Title 40) + '"')
        return $true
    } catch { Write-SocialLog $Ws ("notify: " + $_.Exception.Message); return $false }
}

# --- friend actions: each one changes ONLY this drive's lists ----------------
#  The caller writes the profile and publishes afterwards.
function Add-SocialFriend($Prof, [string]$Id) {
    if ($Id -notmatch $script:SocialIdPattern -or $Id -eq $Prof.Id) { return }
    if (@($Prof.Friends) -notcontains $Id) { $Prof.Friends = @(@($Prof.Friends) + $Id) }
    $Prof.Declined = @(@($Prof.Declined) | Where-Object { $_ -ne $Id })
}
function Remove-SocialFriend($Prof, [string]$Id) {
    $Prof.Friends = @(@($Prof.Friends) | Where-Object { $_ -ne $Id })
}
function Deny-SocialRequest($Prof, [string]$Id) {
    Remove-SocialFriend $Prof $Id
    if ($Id -match $script:SocialIdPattern -and @($Prof.Declined) -notcontains $Id) { $Prof.Declined = @(@($Prof.Declined) + $Id) }
}

# ===========================================================================
#  PLAYED GAMES ON THE PROFILE   (Steven, 2026-10-11)
# ===========================================================================
#  RetroBat already keeps, for every game, how long it has been played
#  (<gametime>, seconds), when it was last played (<lastplayed>) and whether it
#  is a favourite (<favorite>, the star in RetroBat's game list). This reads
#  those from roms\<system>\gamelist.xml - nothing new is tracked.
#
#  Shared per friend: profile.ini "share" lists who may see them (asked when a
#  request is sent or accepted). A game can be hidden: profile\hidden-games.txt,
#  one "system|path" line each. Hidden games never leave the drive.
#  The light-lock rule holds: anyone with the shared key could read the file;
#  the wizard only SHOWS a friend's games when their "for" list names you.

function Get-SocialHiddenGames([string]$Ws) {
    $P = Get-SocialPaths $Ws
    $f = Join-SocialPath $P.ProfileDir 'hidden-games.txt'
    $out = @{}
    if (-not (Test-Path -LiteralPath $f)) { return $out }
    foreach ($line in @([System.IO.File]::ReadAllLines($f))) {
        $t = $line.Trim()
        if ($t -eq '' -or $t.StartsWith(';')) { continue }
        $out[$t.ToLower()] = $true
    }
    return $out
}

function Set-SocialHiddenGame([string]$Ws, [string]$System, [string]$Path, [bool]$Hide) {
    $P = Get-SocialPaths $Ws
    New-SocialDir $P.ProfileDir
    $f = Join-SocialPath $P.ProfileDir 'hidden-games.txt'
    $key = ('{0}|{1}' -f $System, $Path)
    $lines = @()
    if (Test-Path -LiteralPath $f) { $lines = @([System.IO.File]::ReadAllLines($f) | Where-Object { $_.Trim() -ne '' -and $_.Trim().ToLower() -ne $key.ToLower() }) }
    if ($Hide) { $lines += $key }
    if (@($lines | Where-Object { -not $_.StartsWith(';') }).Count -eq 0) { $lines = @() }
    $head = @('; Games kept off your profile (the wizard''s Profile tab, Hide). system|path, one per line.')
    [System.IO.File]::WriteAllLines($f, [string[]](@($head) + @($lines | Where-Object { -not $_.StartsWith(';') })))
}

# Every played or starred game on this drive. Returns @{ Top; Recent; Fav; All }
# of @{ Name; System; Path; Minutes; Last; Image; Favorite }. $Hidden is the
# table Get-SocialHiddenGames returns.
# ---------------------------------------------------------------------------
#  PLAY TIME PER PERSON                                          (2026-10-17)
# ---------------------------------------------------------------------------
#  Steven: play data "tracked per logged-in profile rather than per drive, so
#  a friend streaming to his device shows as themselves". RetroBat keeps ONE
#  play time per game (gametime and lastplayed in each gamelist.xml), for
#  the whole drive. So the wizard keeps a small ledger per person:
#      profile\play\<person id>.txt    sys|path|seconds|lastplayed
#      profile\play\open.txt           who is playing now, and RetroBat's
#                                      totals at the moment they started
#  Settling (Update-SocialPlayLedger) gives everything RetroBat counted since
#  that moment to the person in open.txt, then starts a new moment for
#  whoever is playing now. It runs when PLAY is pressed (after "Who's
#  playing?"), when the wizard shows play times, and when the background
#  helper checks in. The very first settle on a drive gives the times
#  already there to whoever is logged in then (the owner, normally).
#  Favourites stay the drive's own: RetroBat has one star per game.
function Get-SocialPlayDir([string]$Ws) { return (Join-SocialPath $Ws 'People\play') }

# RetroBat's own totals now: key "sys|path" -> @{ Secs; Last } ("yyyyMMddTHHmmss").
function Read-SocialRetroBatTimes([string]$Root) {
    $out = @{}
    $roms = Join-SocialPath $Root 'roms'
    if (-not (Test-Path -LiteralPath $roms)) { return $out }
    foreach ($sd in @([System.IO.Directory]::GetDirectories($roms))) {
        $gl = Join-Path $sd 'gamelist.xml'
        if (-not (Test-Path -LiteralPath $gl)) { continue }
        $sys = ([System.IO.Path]::GetFileName($sd)).ToLower()
        $txt = ''
        try { $txt = [System.IO.File]::ReadAllText($gl) } catch { continue }
        if ($txt -notmatch '<gametime>|<lastplayed>') { continue }
        $x = $null
        try { [xml]$x = $txt } catch { continue }
        foreach ($g in @($x.SelectNodes('/gameList/game'))) {
            if ($null -eq $g) { continue }
            $secs = 0; $last = ''
            $n1 = $g.SelectSingleNode('gametime'); if ($null -ne $n1) { [int]::TryParse([string]$n1.InnerText, [ref]$secs) | Out-Null }
            $n2 = $g.SelectSingleNode('lastplayed'); if ($null -ne $n2) { $last = ([string]$n2.InnerText).Trim() }
            if ($secs -le 0 -and $last -eq '') { continue }
            $pn = $g.SelectSingleNode('path'); if ($null -eq $pn) { continue }
            $out[('{0}|{1}' -f $sys, ([string]$pn.InnerText).Trim())] = @{ Secs = $secs; Last = $last }
        }
    }
    return $out
}

function Read-SocialTimesFile([string]$Path) {
    $out = @{}
    if (-not (Test-Path -LiteralPath $Path)) { return $out }
    foreach ($l in [System.IO.File]::ReadAllLines($Path)) {
        if ($l.StartsWith(';') -or $l.StartsWith('id =')) { continue }
        $p = $l.Split('|')
        if ($p.Count -lt 4) { continue }
        $secs = 0; [int]::TryParse($p[$p.Count - 2], [ref]$secs) | Out-Null
        $key = (($p[0..($p.Count - 3)]) -join '|')
        $out[$key] = @{ Secs = $secs; Last = $p[$p.Count - 1] }
    }
    return $out
}

function Write-SocialTimesFile([string]$Path, $Map, [string]$Head) {
    $lines = New-Object System.Collections.ArrayList
    [void]$lines.Add('; Play time, written by the wizard (SocialEngine.ps1, PLAY TIME PER PERSON). sys|path|seconds|last played')
    if ($Head -ne '') { [void]$lines.Add($Head) }
    foreach ($k in @($Map.Keys | Sort-Object)) { [void]$lines.Add(('{0}|{1}|{2}' -f $k, [int]$Map[$k].Secs, [string]$Map[$k].Last)) }
    $tmp = $Path + '.tmp'
    [System.IO.File]::WriteAllLines($tmp, [string[]]$lines.ToArray())
    Move-Item -LiteralPath $tmp -Destination $Path -Force
}

# ---- favourites per person (2026-10-17) -----------------------------------
#  RetroBat has one favourite star per game for the whole drive. When a
#  DIFFERENT person picks PLAY, the stars of the person who was playing are
#  kept in profile\play\<id>.fav and the new person's stars are put on
#  instead (none, the first time). Only while RetroBat is closed (it
#  rewrites gamelist.xml as it closes), only between two people with a
#  profile: a guest changes nothing. Only the <favorite> lines are touched.
function Test-SocialRetroBatOpen {
    if ($null -ne $script:SocialRunningOverride) { return [bool](& $script:SocialRunningOverride) }
    foreach ($n in @('emulationstation', 'retrobat')) { if (@(Get-Process -Name $n -ErrorAction SilentlyContinue).Count -gt 0) { return $true } }
    return $false
}
$script:SocialRunningOverride = $null

function Read-SocialFavorites([string]$Root) {
    $set = @{}
    $roms = Join-SocialPath $Root 'roms'
    if (-not (Test-Path -LiteralPath $roms)) { return $set }
    foreach ($sd in @([System.IO.Directory]::GetDirectories($roms))) {
        $gl = Join-Path $sd 'gamelist.xml'
        if (-not (Test-Path -LiteralPath $gl)) { continue }
        $txt = ''; try { $txt = [System.IO.File]::ReadAllText($gl) } catch { continue }
        if ($txt -notmatch '<favorite>') { continue }
        $x = $null; try { [xml]$x = $txt } catch { continue }
        $sys = ([System.IO.Path]::GetFileName($sd)).ToLower()
        foreach ($g in @($x.SelectNodes('/gameList/game[favorite]'))) {
            if ($null -eq $g) { continue }
            if (([string]$g.SelectSingleNode('favorite').InnerText).Trim() -ne 'true') { continue }
            $pn = $g.SelectSingleNode('path'); if ($null -eq $pn) { continue }
            $set[('{0}|{1}' -f $sys, ([string]$pn.InnerText).Trim())] = $true
        }
    }
    return $set
}

function Set-SocialFavorites([string]$Root, $Set) {
    $roms = Join-SocialPath $Root 'roms'
    if (-not (Test-Path -LiteralPath $roms)) { return 0 }
    $changed = 0
    foreach ($sd in @([System.IO.Directory]::GetDirectories($roms))) {
        $gl = Join-Path $sd 'gamelist.xml'
        if (-not (Test-Path -LiteralPath $gl)) { continue }
        $sys = ([System.IO.Path]::GetFileName($sd)).ToLower()
        $x = New-Object System.Xml.XmlDocument
        $x.PreserveWhitespace = $true
        try { $x.Load($gl) } catch { continue }
        $dirty = $false
        foreach ($g in @($x.SelectNodes('/gameList/game'))) {
            if ($null -eq $g) { continue }
            $pn = $g.SelectSingleNode('path'); if ($null -eq $pn) { continue }
            $want = $Set.ContainsKey(('{0}|{1}' -f $sys, ([string]$pn.InnerText).Trim()))
            $fn = $g.SelectSingleNode('favorite')
            $has = ($null -ne $fn -and ([string]$fn.InnerText).Trim() -eq 'true')
            if ($want -eq $has) { continue }
            if ($want) {
                if ($null -eq $fn) { $fn = $x.CreateElement('favorite'); [void]$g.AppendChild($fn) }
                $fn.InnerText = 'true'
            }
            else { [void]$g.RemoveChild($fn) }
            $dirty = $true; $changed++
        }
        if ($dirty) {
            $tmp = $gl + '.fav-tmp'
            $x.Save($tmp)
            Move-Item -LiteralPath $tmp -Destination $gl -Force
        }
    }
    return $changed
}

function Switch-SocialFavorites([string]$Root, [string]$Ws, [string]$FromId, [string]$ToId) {
    if ($FromId -eq $ToId -or $FromId -eq 'guest' -or $ToId -eq 'guest' -or $FromId -eq '' -or $ToId -eq '') { return }
    if ($FromId -notmatch '^[A-Za-z0-9_\-]{1,40}$' -or $ToId -notmatch '^[A-Za-z0-9_\-]{1,40}$') { return }
    if (Test-SocialRetroBatOpen) { return }
    $dir = Get-SocialPlayDir $Ws
    $cur = Read-SocialFavorites $Root
    [System.IO.File]::WriteAllLines((Join-SocialPath $dir ($FromId + '.fav')), [string[]]@(@('; favourite games (sys|path), kept by the wizard') + @($cur.Keys | Sort-Object)))
    $want = @{}
    $toF = Join-SocialPath $dir ($ToId + '.fav')
    if (Test-Path -LiteralPath $toF) { foreach ($l in [System.IO.File]::ReadAllLines($toF)) { if ($l -ne '' -and -not $l.StartsWith(';')) { $want[$l] = $true } } }
    [void](Set-SocialFavorites $Root $want)
}

# ---- separate saves per person (2026-10-17, "streaming profiles") --------
#  Steven: "his profile keeps the drive's current saves, every other profile
#  gets its own separate saves". When a DIFFERENT person with a profile picks
#  PLAY, the save places below are MOVED (a rename on the same drive: instant,
#  nothing copied) into profile\saves-of\<who was playing>\, and the new
#  person's own are moved back in (empty folders the first time). Guests use
#  whatever saves are in place, as before. Only while RetroBat is closed.
#  Switched by 'separatesaves' in features.ini (on unless it says off).
#
#  WHAT MOVES. Every console folder in saves\ that holds only saves (NES,
#  SNES, N64, GB/GBC/GBA, DS, PlayStation 1 and so on) moves whole. Consoles
#  whose folder also holds system files keep that folder, and only their
#  save folder moves:
#      Wii        wii\dolphin-emu\User\Wii\title\00010000   (disc game saves)
#      GameCube   gamecube\dolphin-emu\User\GC, dolphin\User\GC (memory cards)
#      Wii U      wiiu\cemu\mlc01\usr\save\00050000
#      PS2        ps2\pcsx2\memcards, ps2\pcsx2-16\memcards
#      PS3        ps3\rpcs3\dev_hdd0\home
#      PS Vita    psvita\vita3k\ux0\user
#  Left shared on purpose (the save sits among installed content, accounts or
#  system files, so moving it could break the console): 3DS, Switch, Xbox,
#  Xbox 360, PSP, Flash, PC, Steam, arcade (mame and friends) and the ports.
#
#  A JOURNAL (profile\saves-of\switch.txt) lists every move before it starts
#  and is deleted when all are done, so a switch cut short (power, unplugged
#  drive) is finished the next time, never half-done for good.
#
#  REBUILT 2026-10-25 after it went wrong on Steven's drive: the background
#  helper and the wizard both ran a switch at the same moment, and the two
#  tripped over each other (saves renamed aside, nothing lost; all put back
#  by hand). Now:
#    - ONE place decides: Switch-SocialPerson, called only when someone signs
#      in to the wizard or picks at PLAY. Reading play time never switches.
#    - ONE at a time: a lock file held for the whole switch, across programs.
#    - WHOSE SAVES ARE IN PLACE is written down (profile\saves-of\owner.txt),
#      not guessed from the play-time records.
#    - A folder that has saves in it is NEVER moved aside or replaced: that
#      place is skipped and logged instead.
$script:SwapShared = @('3ds', 'switch', 'xbox', 'xbox360', 'psp', 'flash', 'windows', 'steam', 'ports', 'mame', 'hbmame', 'psxmame',
                       'wii', 'wiiu', 'gamecube', 'dolphin', 'ps2', 'ps3', 'ps4', 'psvita', 'teknoparrot', 'epic', 'gog', 'eagames', 'amazon')
$script:SwapInner = @('wii\dolphin-emu\User\Wii\title\00010000', 'gamecube\dolphin-emu\User\GC', 'dolphin\User\GC',
                      'wiiu\cemu\mlc01\usr\save\00050000', 'ps2\pcsx2\memcards', 'ps2\pcsx2-16\memcards',
                      'ps3\rpcs3\dev_hdd0\home', 'psvita\vita3k\ux0\user')

# OFF unless features.ini says "separatesaves = on" (2026-10-25: held back
# from 3.1 after the mix-up on Steven's drive; ready, tested, not yet tried
# on real hardware). Not on the Features page until then.
function Test-SocialSeparateSaves([string]$Ws) {
    $f = Join-SocialPath $Ws 'Settings\features.ini'
    if (-not (Test-Path -LiteralPath $f)) { return $false }
    foreach ($l in [System.IO.File]::ReadAllLines($f)) { if ($l -match '^\s*separatesaves\s*=\s*(on|true|yes|1)\b') { return $true } }
    return $false
}

function Test-SocialHasFiles([string]$Dir) {
    if (-not (Test-Path -LiteralPath $Dir)) { return $false }
    try { foreach ($f in [System.IO.Directory]::EnumerateFiles($Dir, '*', [System.IO.SearchOption]::AllDirectories)) { return $true } } catch { return $true }
    return $false
}

function Get-SocialSavePlaces([string]$Root, [string]$Ws, [string]$Ids) {
    $places = New-Object System.Collections.ArrayList
    $saves = Join-SocialPath $Root 'saves'
    $tops = @{}
    if (Test-Path -LiteralPath $saves) { foreach ($d in [System.IO.Directory]::GetDirectories($saves)) { $tops[[System.IO.Path]::GetFileName($d).ToLower()] = [System.IO.Path]::GetFileName($d) } }
    foreach ($id in ($Ids -split ',')) {
        $st = Join-SocialPath $Ws ('People\saves-of\' + $id)
        if (Test-Path -LiteralPath $st) { foreach ($d in [System.IO.Directory]::GetDirectories($st)) { $n = [System.IO.Path]::GetFileName($d); if (-not $tops.ContainsKey($n.ToLower())) { $tops[$n.ToLower()] = $n } } }
    }
    foreach ($k in @($tops.Keys | Sort-Object)) {
        if ($script:SwapShared -contains $k) { continue }
        if ($k -match '\.kept-\d') { continue }   # never treat a set-aside folder as a console
        [void]$places.Add($tops[$k])
    }
    foreach ($p in $script:SwapInner) { [void]$places.Add($p) }
    return @($places)
}

# Moves a save folder. The place it goes to must be missing or EMPTY (an
# empty one is cleared first); one with files in it is never touched.
function Move-SocialPlace([string]$From, [string]$To) {
    if (-not (Test-Path -LiteralPath $From)) { return $true }
    if (Test-Path -LiteralPath $To) {
        if (Test-SocialHasFiles $To) { return $false }
        Remove-Item -LiteralPath $To -Recurse -Force
    }
    $parent = Split-Path $To -Parent
    if (-not (Test-Path -LiteralPath $parent)) { [void](New-Item -ItemType Directory -Path $parent -Force) }
    Move-Item -LiteralPath $From -Destination $To
    return $true
}

# Runs (or finishes) the moves in the journal. Each line: from|to, or mkdir|path.
# Call only while holding the lock.
function Invoke-SocialSwapJournal([string]$Ws) {
    $j = Join-SocialPath $Ws 'People\saves-of\switch.txt'
    if (-not (Test-Path -LiteralPath $j)) { return 0 }
    $skipped = 0
    foreach ($l in [System.IO.File]::ReadAllLines($j)) {
        if ($l -eq '' -or $l.StartsWith(';')) { continue }
        $p = $l.Split('|')
        if ($p.Count -lt 2) { continue }
        if ($p[0] -eq 'mkdir') { if (-not (Test-Path -LiteralPath $p[1])) { [void](New-Item -ItemType Directory -Path $p[1] -Force) }; continue }
        if (-not (Move-SocialPlace $p[0] $p[1])) { $skipped++; Write-SocialLog $Ws ('saves switch: left alone, it already has saves in it: ' + $p[1]) }
    }
    if (Test-Path -LiteralPath $j) { Remove-Item -LiteralPath $j -Force }
    return $skipped
}

function Get-SocialSavesOwner([string]$Ws) {
    $f = Join-SocialPath $Ws 'People\saves-of\owner.txt'
    if (-not (Test-Path -LiteralPath $f)) { return '' }
    $t = ([System.IO.File]::ReadAllText($f)).Trim()
    if ($t -match '^[A-Za-z0-9_\-]{1,40}$') { return $t }
    return ''
}
function Set-SocialSavesOwner([string]$Ws, [string]$Id) {
    New-SocialDir (Join-SocialPath $Ws 'People\saves-of')
    [System.IO.File]::WriteAllText((Join-SocialPath $Ws 'People\saves-of\owner.txt'), $Id)
}

# The saves of $FromId go to profile\saves-of\<FromId>, those of $ToId come in.
# Call only while holding the lock (Switch-SocialPerson does).
function Switch-SocialSaves([string]$Root, [string]$Ws, [string]$FromId, [string]$ToId) {
    [void](Invoke-SocialSwapJournal $Ws)     # a switch cut short last time is finished first
    if ($FromId -eq $ToId -or $FromId -eq '' -or $ToId -eq '') { return $false }
    if ($FromId -notmatch '^[A-Za-z0-9_\-]{1,40}$' -or $ToId -notmatch '^[A-Za-z0-9_\-]{1,40}$') { return $false }
    $saves = Join-SocialPath $Root 'saves'
    if (-not (Test-Path -LiteralPath $saves)) { return $false }
    $out = Join-SocialPath $Ws ('People\saves-of\' + $FromId)
    $in  = Join-SocialPath $Ws ('People\saves-of\' + $ToId)
    $places = Get-SocialSavePlaces $Root $Ws ($FromId + ',' + $ToId)
    $lines = New-Object System.Collections.ArrayList
    [void]$lines.Add(('; Saves switching from {0} to {1}, {2}. Finished by the wizard if it was cut short.' -f $FromId, $ToId, (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')))
    foreach ($pl in $places) {
        $live = Join-SocialPath $saves $pl
        $mineOut = Join-SocialPath $out $pl
        $theirs = Join-SocialPath $in $pl
        $liveHas = Test-SocialHasFiles $live
        $theirsHas = Test-SocialHasFiles $theirs
        if (-not $liveHas -and -not $theirsHas) { continue }   # nothing either way
        if ($liveHas) { [void]$lines.Add(($live + '|' + $mineOut)) }
        if ($theirsHas) { [void]$lines.Add(($theirs + '|' + $live)) }
        else { [void]$lines.Add(('mkdir|' + $live)) }
    }
    New-SocialDir (Join-SocialPath $Ws 'People\saves-of')
    [System.IO.File]::WriteAllLines((Join-SocialPath $Ws 'People\saves-of\switch.txt'), [string[]]$lines.ToArray())
    $sk = Invoke-SocialSwapJournal $Ws
    if ($sk -gt 0) { Write-SocialLog $Ws ("saves switch: {0} place(s) left as they were" -f $sk) }
    return $true
}

# THE one entry point (2026-10-25). $ToId is now using this setup: their
# favourite stars, and their saves (when 'separatesaves' is on), are put in
# place. Guests use whatever is in place. Returns 'switched', 'same', 'skip'
# or 'busy'.
function Switch-SocialPerson([string]$Root, [string]$Ws, [string]$ToId) {
    if ($ToId -eq '' -or $ToId -eq 'guest' -or $ToId -notmatch '^[A-Za-z0-9_\-]{1,40}$') { return 'skip' }
    if (Test-SocialRetroBatOpen) { return 'skip' }
    $dir = Join-SocialPath $Ws 'People\saves-of'
    New-SocialDir $dir
    $lockF = Join-SocialPath $dir 'switch.lock'
    $lock = $null
    try { $lock = [System.IO.File]::Open($lockF, 'OpenOrCreate', 'ReadWrite', 'None') }
    catch { Write-SocialLog $Ws 'saves switch: another switch is running, this one is skipped'; return 'busy' }
    try {
        $owner = Get-SocialSavesOwner $Ws
        if ($owner -eq '') {
            # the first time: whoever was playing last owns what is in place
            $openF = Join-SocialPath (Get-SocialPlayDir $Ws) 'open.txt'
            if (Test-Path -LiteralPath $openF) { foreach ($l in [System.IO.File]::ReadAllLines($openF)) { if ($l -match '^id = ([A-Za-z0-9_\-]{1,40})$' -and $Matches[1] -ne 'guest') { $owner = $Matches[1] } } }
            if ($owner -eq '') { $owner = $ToId }
            Set-SocialSavesOwner $Ws $owner
        }
        if ($owner -eq $ToId) { [void](Invoke-SocialSwapJournal $Ws); return 'same' }
        try { Switch-SocialFavorites $Root $Ws $owner $ToId } catch { Write-SocialLog $Ws ('favourites switch: ' + $_.Exception.Message) }
        if (Test-SocialSeparateSaves $Ws) { [void](Switch-SocialSaves $Root $Ws $owner $ToId) }
        Set-SocialSavesOwner $Ws $ToId
        Write-SocialLog $Ws ("switched this setup from {0} to {1}" -f $owner, $ToId)
        return 'switched'
    }
    catch { Write-SocialLog $Ws ('saves switch: ' + $_.Exception.Message); return 'skip' }
    finally { try { $lock.Close() } catch { } }
}

# Settles the open moment and opens a new one for $PersonId ('' = keep
# whoever is open). Returns that person's ledger (key -> @{ Secs; Last }).
function Update-SocialPlayLedger([string]$Root, [string]$Ws, [string]$PersonId = '', [switch]$Switch) {
    $dir = Get-SocialPlayDir $Ws
    New-SocialDir $dir
    $openF = Join-SocialPath $dir 'open.txt'
    $now = Read-SocialRetroBatTimes $Root
    $openId = ''
    if (Test-Path -LiteralPath $openF) { foreach ($l in [System.IO.File]::ReadAllLines($openF)) { if ($l -match '^id = (.+)$') { $openId = $Matches[1].Trim() } } }
    if ($openId -ne '' -and $openId -match '^[A-Za-z0-9_\-]{1,40}$') {
        $snap = Read-SocialTimesFile $openF
        $ledF = Join-SocialPath $dir ($openId + '.txt')
        $led = Read-SocialTimesFile $ledF
        $changed = $false
        foreach ($k in $now.Keys) {
            $before = $(if ($snap.ContainsKey($k)) { [int]$snap[$k].Secs } else { 0 })
            $lastBefore = $(if ($snap.ContainsKey($k)) { [string]$snap[$k].Last } else { '' })
            $add = [int]$now[$k].Secs - $before
            $newLast = ([string]$now[$k].Last -ne '' -and [string]$now[$k].Last -ne $lastBefore)
            if ($add -le 0 -and -not $newLast) { continue }
            if (-not $led.ContainsKey($k)) { $led[$k] = @{ Secs = 0; Last = '' } }
            if ($add -gt 0) { $led[$k].Secs = [int]$led[$k].Secs + $add }
            if ($newLast) { $led[$k].Last = [string]$now[$k].Last }
            $changed = $true
        }
        if ($changed) { Write-SocialTimesFile $ledF $led '' }
    }
    elseif ($PersonId -ne '' -and $PersonId -ne 'guest' -and @(Get-ChildItem -LiteralPath $dir -Filter '*.txt' -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne 'open.txt' }).Count -eq 0) {
        # the first time on this drive: the times already here are the owner's
        Write-SocialTimesFile (Join-SocialPath $dir ($PersonId + '.txt')) $now ''
    }
    $who = $(if ($PersonId -ne '') { $PersonId } elseif ($openId -ne '') { $openId } else { 'guest' })
    # Saves and favourite stars move ONLY when asked (sign-in, PLAY), never
    # because play time was read (2026-10-25: that ran two switches at once).
    if ($Switch) { [void](Switch-SocialPerson $Root $Ws $who) }
    Write-SocialTimesFile $openF $now ('id = ' + $who)
    if ($who -match '^[A-Za-z0-9_\-]{1,40}$') { return (Read-SocialTimesFile (Join-SocialPath $dir ($who + '.txt'))) }
    return @{}
}

function Get-SocialGameStats([string]$Root, $Hidden = @{}, [int]$TopN = 3, [int]$RecentN = 3, [int]$FavN = 6, $Ledger = $null) {
    $all = New-Object System.Collections.ArrayList
    $roms = Join-SocialPath $Root 'roms'
    if (Test-Path -LiteralPath $roms) {
        foreach ($sd in @([System.IO.Directory]::GetDirectories($roms))) {
            $gl = Join-Path $sd 'gamelist.xml'
            if (-not (Test-Path -LiteralPath $gl)) { continue }
            $sys = ([System.IO.Path]::GetFileName($sd)).ToLower()
            if ($sys -notmatch '^[a-z0-9\-]{1,20}$') { continue }
            $x = $null
            try { [xml]$x = [System.IO.File]::ReadAllText($gl) } catch { continue }
            foreach ($g in @($x.SelectNodes('/gameList/game'))) {
                if ($null -eq $g) { continue }
                $secs = 0; $last = $null; $fav = $false
                $n1 = $g.SelectSingleNode('gametime');   if ($null -ne $n1) { [int]::TryParse([string]$n1.InnerText, [ref]$secs) | Out-Null }
                $n2 = $g.SelectSingleNode('lastplayed'); if ($null -ne $n2) {
                    $d = [DateTime]::MinValue
                    if ([DateTime]::TryParseExact(([string]$n2.InnerText).Trim(), 'yyyyMMddTHHmmss', [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$d)) { $last = $d }
                }
                $n3 = $g.SelectSingleNode('favorite');   if ($null -ne $n3 -and ([string]$n3.InnerText).Trim() -eq 'true') { $fav = $true }
                $path = ''; $pn = $g.SelectSingleNode('path'); if ($null -ne $pn) { $path = ([string]$pn.InnerText).Trim() }
                # (2026-10-17) With a person's ledger, their own time and last
                # play replace the drive's.
                if ($null -ne $Ledger) {
                    $lk = '{0}|{1}' -f $sys, $path
                    $secs = 0; $last = $null
                    if ($Ledger.ContainsKey($lk)) {
                        $secs = [int]$Ledger[$lk].Secs
                        $d = [DateTime]::MinValue
                        if ([DateTime]::TryParseExact([string]$Ledger[$lk].Last, 'yyyyMMddTHHmmss', [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$d)) { $last = $d }
                    }
                }
                if ($secs -le 0 -and $null -eq $last -and -not $fav) { continue }
                if ($Hidden.ContainsKey(('{0}|{1}' -f $sys, $path).ToLower())) { continue }
                $name = ''; $nn = $g.SelectSingleNode('name'); if ($null -ne $nn) { $name = ([string]$nn.InnerText).Trim() }
                if ($name -eq '') { $name = [System.IO.Path]::GetFileNameWithoutExtension($path) }
                $img = ''
                foreach ($tag in @('image', 'thumbnail')) {
                    $im = $g.SelectSingleNode($tag)
                    if ($null -eq $im) { continue }
                    $rel = ([string]$im.InnerText).Trim()
                    if ($rel -eq '') { continue }
                    $full = $(if ($rel.StartsWith('./') -or $rel.StartsWith('.\')) { Join-SocialPath $sd $rel.Substring(2) } else { $rel })
                    if (Test-Path -LiteralPath $full) { $img = $full; break }
                }
                [void]$all.Add([pscustomobject]@{ Name = $name; System = $sys; Path = $path; Minutes = [math]::Round($secs / 60.0, 1)
                                                 Last = $last; Image = $img; Favorite = $fav })
            }
        }
    }
    $list = @($all.ToArray())
    return @{
        Top    = @($list | Where-Object { $_.Minutes -gt 0 } | Sort-Object Minutes -Descending | Select-Object -First $TopN)
        Recent = @($list | Where-Object { $null -ne $_.Last } | Sort-Object Last -Descending | Select-Object -First $RecentN)
        Fav    = @($list | Where-Object { $_.Favorite } | Sort-Object Minutes -Descending | Select-Object -First $FavN)
        All    = $list
    }
}

# A friend's "games" block, read back defensively like the rest.
function ConvertFrom-SocialGameItem($x) {
    if ($null -eq $x) { return $null }
    $sys = ([string]$x.s).ToLower()
    if ($sys -notmatch '^[a-z0-9\-]{1,20}$') { return $null }
    $n = Get-SocialClean ([string]$x.n) 60
    if ($n -eq '') { return $null }
    $m = 0; [int]::TryParse([string]$x.m, [ref]$m) | Out-Null
    if ($m -lt 0 -or $m -gt 10000000) { $m = 0 }
    $t = [string]$x.t
    if ($x.t -is [DateTime]) { $t = ([DateTime]$x.t).ToString('yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture) }
    if ($t -notmatch '^\d{4}-\d{2}-\d{2}$') { $t = '' }
    return [pscustomobject]@{ Name = $n; System = $sys; Minutes = $m; Last = $t }
}

function ConvertFrom-SocialGames($G) {
    if ($null -eq $G) { return $null }
    $item = { param($x) $r = ConvertFrom-SocialGameItem $x; if ($null -ne $r) { $r } }
    return [pscustomobject]@{
        For    = @(@($G.for) | ForEach-Object { [string]$_ } | Where-Object { $_ -match $script:SocialIdPattern } | Select-Object -Unique)
        Top    = @(@($G.top)    | Select-Object -First 3 | ForEach-Object { & $item $_ })
        Recent = @(@($G.recent) | Select-Object -First 3 | ForEach-Object { & $item $_ })
        Fav    = @(@($G.fav)    | Select-Object -First 6 | ForEach-Object { & $item $_ })
    }
}

# How long, in plain words: "2 h 15 min", "40 min".
function Format-SocialPlaytime([double]$Minutes) {
    $m = [int][math]::Round($Minutes)
    if ($m -lt 1) { return 'under a minute' }
    if ($m -lt 60) { return "$m min" }
    $h = [math]::Floor($m / 60); $r = $m % 60
    if ($r -eq 0) { return "$h h" }
    return "$h h $r min"
}

# ===========================================================================
#  FAVOURITES, PLAY TOGETHER, AND MORE THAN ONE PERSON PER DRIVE (2026-10-12)
# ===========================================================================

# --- the three favourite games ---------------------------------------------
#  Picked on the Profile tab from the same console > game > picture choices
#  as the shortcut maker. profile.ini keeps "system|rom|picture" per slot.
#  This turns a slot into what the screen and the online file need, from the
#  game list: @{ Slot; System; Rom; Name; Image } or $null for an empty or
#  vanished slot.
function Resolve-SocialFav([string]$Root, [string]$Slot) {
    $s = ConvertTo-SocialFavSlot $Slot
    if ($s -eq '') { return $null }
    $f = $s.Split('|')
    $sys = $f[0]; $rom = $f[1]; $pic = $f[2]
    $sd = Join-SocialPath (Join-SocialPath $Root 'roms') $sys
    $romFull = Join-SocialPath $sd $rom
    if (-not (Test-Path -LiteralPath $romFull)) { return $null }
    $name = [System.IO.Path]::GetFileNameWithoutExtension($rom)
    $gl = Join-SocialPath $sd 'gamelist.xml'
    if (Test-Path -LiteralPath $gl) {
        try {
            [xml]$x = [System.IO.File]::ReadAllText($gl)
            $want = ($rom -replace '\\', '/').TrimStart('.', '/').ToLower()
            foreach ($g in @($x.SelectNodes('/gameList/game'))) {
                if ($null -eq $g) { continue }
                $pn = $g.SelectSingleNode('path'); if ($null -eq $pn) { continue }
                $p = (([string]$pn.InnerText).Trim() -replace '\\', '/').TrimStart('.', '/').ToLower()
                if ($p -ne $want) { continue }
                $nn = $g.SelectSingleNode('name')
                if ($null -ne $nn -and ([string]$nn.InnerText).Trim() -ne '') { $name = ([string]$nn.InnerText).Trim() }
                break
            }
        } catch { }
    }
    $img = ''
    if ($pic -ne '') {
        $pf = Join-SocialPath $sd $pic
        if (Test-Path -LiteralPath $pf) { $img = $pf }
    }
    return [pscustomobject]@{ Slot = $s; System = $sys; Rom = $rom; Name = $name; Image = $img }
}

function Get-SocialFavs([string]$Root, $Prof) {
    $out = @()
    foreach ($slot in @($Prof.Favs)) { $out += , (Resolve-SocialFav $Root ([string]$slot)) }
    while ($out.Count -lt 3) { $out += , $null }
    return $out
}

# A path inside roms\<system>\, written the way profile.ini keeps it.
function Get-SocialRelPath([string]$Root, [string]$System, [string]$Full) {
    $base = Join-SocialPath (Join-SocialPath $Root 'roms') $System
    $b = $base.TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
    if (-not $Full.StartsWith($b, [StringComparison]::OrdinalIgnoreCase)) { return '' }
    return ($Full.Substring($b.Length) -replace '\\', '/')
}

# --- play together ------------------------------------------------------------
#  An invite lives in the SENDER's own file (the one rule: nobody writes
#  anybody else's), for $SocialInviteMinutes. The friends it names see a
#  banner from their helper, even with the wizard closed, and their answer
#  goes in THEIR own file as "reply". profile\invite.ini and
#  profile\reply.ini hold this drive's own; the helper sends them.
$script:SocialInviteMinutes = 15

function ConvertFrom-SocialInvite($o) {
    if ($null -eq $o) { return $null }
    $id = [string]$o.id
    if ($id -notmatch '^[a-z0-9]{6,12}$') { return $null }
    $at = Get-SocialTimeValue $o.at
    if ($null -eq $at) { return $null }
    $sys = ([string]$o.s).ToLower()
    if ($sys -notmatch '^[a-z0-9\-]{0,20}$') { $sys = '' }
    return [pscustomobject]@{
        Id = $id
        To = @(@($o.to) | ForEach-Object { [string]$_ } | Where-Object { $_ -match $script:SocialIdPattern } | Select-Object -Unique)
        Game = Get-SocialClean ([string]$o.n) 60; System = $sys
        Note = Get-SocialClean ([string]$o.note) 60; Code = Get-SocialClean ([string]$o.code) 40
        At = $at
    }
}

function ConvertFrom-SocialReply($o) {
    if ($null -eq $o) { return $null }
    $to = [string]$o.to; $inv = [string]$o.inv; $ans = [string]$o.ans
    if ($to -notmatch $script:SocialIdPattern -or $inv -notmatch '^[a-z0-9]{6,12}$') { return $null }
    if (@('yes', 'no') -notcontains $ans) { return $null }
    $at = Get-SocialTimeValue $o.at
    if ($null -eq $at) { return $null }
    return [pscustomobject]@{ To = $to; Inv = $inv; Ans = $ans; At = $at }
}

function Read-SocialSmallIni([string]$Path) {
    $o = @{}
    if (-not (Test-Path -LiteralPath $Path)) { return $o }
    foreach ($line in [System.IO.File]::ReadAllLines($Path)) {
        $t = $line.Trim()
        if ($t -eq '' -or $t.StartsWith(';')) { continue }
        $eq = $t.IndexOf('=')
        if ($eq -lt 1) { continue }
        $o[$t.Substring(0, $eq).Trim().ToLower()] = $t.Substring($eq + 1).Trim()
    }
    return $o
}

# This drive's own invite, or $null when there is none or it has run out.
function Read-SocialInvite([string]$Ws, [DateTime]$NowUtc) {
    $P = Get-SocialPaths $Ws
    $i = Read-SocialSmallIni (Join-SocialPath $P.ProfileDir 'invite.ini')
    if ($i.Count -eq 0) { return $null }
    $inv = ConvertFrom-SocialInvite ([pscustomobject]@{ id = $i['id']; to = @(([string]$i['to']).Split(',') | ForEach-Object { $_.Trim() }); n = $i['game']; s = $i['system']; note = $i['note']; code = $i['code']; at = $i['at'] })
    if ($null -eq $inv) { return $null }
    if (($NowUtc - $inv.At).TotalMinutes -gt $script:SocialInviteMinutes) { return $null }
    return $inv
}

function Write-SocialInvite([string]$Ws, [string[]]$To, [string]$Game, [string]$System, [string]$Note, [string]$Code) {
    $P = Get-SocialPaths $Ws
    New-SocialDir $P.ProfileDir
    $id = (New-SocialId).Substring(0, 8)
    $lines = @('; A play-together invite this drive sent. It runs out by itself after 15 minutes.',
        ('id     = ' + $id),
        ('to     = ' + ((@($To) | Where-Object { $_ -match $script:SocialIdPattern }) -join ',')),
        ('game   = ' + (Get-SocialClean $Game 60)),
        ('system = ' + (([string]$System).ToLower() -replace '[^a-z0-9\-]', '')),
        ('note   = ' + (Get-SocialClean $Note 60)),
        ('code   = ' + (Get-SocialClean $Code 40)),
        ('at     = ' + (Format-SocialTime (Get-SocialNowUtc))))
    [System.IO.File]::WriteAllLines((Join-SocialPath $P.ProfileDir 'invite.ini'), [string[]]$lines)
    return $id
}

function Clear-SocialInvite([string]$Ws) {
    $P = Get-SocialPaths $Ws
    foreach ($n in @('invite.ini', 'reply.ini')) {
        $f = Join-SocialPath $P.ProfileDir $n
        if (Test-Path -LiteralPath $f) { Remove-Item -LiteralPath $f -Force }
    }
}

function Read-SocialReply([string]$Ws, [DateTime]$NowUtc) {
    $P = Get-SocialPaths $Ws
    $i = Read-SocialSmallIni (Join-SocialPath $P.ProfileDir 'reply.ini')
    if ($i.Count -eq 0) { return $null }
    $r = ConvertFrom-SocialReply ([pscustomobject]@{ to = $i['to']; inv = $i['inv']; ans = $i['ans']; at = $i['at'] })
    if ($null -eq $r -or ($NowUtc - $r.At).TotalMinutes -gt $script:SocialInviteMinutes) { return $null }
    return $r
}

function Write-SocialReply([string]$Ws, [string]$To, [string]$Inv, [bool]$Yes) {
    $P = Get-SocialPaths $Ws
    New-SocialDir $P.ProfileDir
    [System.IO.File]::WriteAllLines((Join-SocialPath $P.ProfileDir 'reply.ini'), [string[]]@(
        '; This drive''s answer to a friend''s invite.',
        ('to  = ' + $To), ('inv = ' + $Inv), ('ans = ' + $(if ($Yes) { 'yes' } else { 'no' })),
        ('at  = ' + (Format-SocialTime (Get-SocialNowUtc)))))
}

# Invites friends sent to $Prof that are still live, newest first.
function Get-SocialInvitesFor($Prof, $Players, [DateTime]$NowUtc) {
    if ($null -eq $Prof -or $Prof.Guest) { return @() }
    $view = Get-SocialView $Prof $Players $NowUtc
    $out = @()
    foreach ($f in @($view.Friends)) {
        $inv = $f.Invite
        if ($null -eq $inv) { continue }
        if (@($inv.To) -notcontains $Prof.Id) { continue }
        $age = ($NowUtc - $inv.At).TotalMinutes
        if ($age -lt -5 -or $age -gt $script:SocialInviteMinutes) { continue }
        $out += [pscustomobject]@{ From = $f; Invite = $inv }
    }
    return @($out | Sort-Object { $_.Invite.At } -Descending)
}

# Answers to THIS drive's live invite: @(@{ From; Yes }).
function Get-SocialRepliesFor($Prof, $Players, $MyInvite) {
    if ($null -eq $MyInvite) { return @() }
    $out = @()
    foreach ($p in @($Players)) {
        if ($null -eq $p -or $null -eq $p.Reply) { continue }
        if ($p.Reply.To -ne $Prof.Id -or $p.Reply.Inv -ne $MyInvite.Id) { continue }
        if (@($MyInvite.To) -notcontains $p.Id) { continue }
        $out += [pscustomobject]@{ From = $p; Yes = ($p.Reply.Ans -eq 'yes') }
    }
    return $out
}

# Invites and answers already shown on this drive, so the helper and the
# wizard never show the same one twice. social\invites-seen.txt, newest last.
function Test-SocialSeen([string]$Ws, [string]$Key) {
    $f = Join-SocialPath (Get-SocialPaths $Ws).SocialDir 'invites-seen.txt'
    if (-not (Test-Path -LiteralPath $f)) { return $false }
    return (@([System.IO.File]::ReadAllLines($f)) -contains $Key)
}

function Add-SocialSeen([string]$Ws, [string]$Key) {
    $P = Get-SocialPaths $Ws
    New-SocialDir $P.SocialDir
    $f = Join-SocialPath $P.SocialDir 'invites-seen.txt'
    $lines = @()
    if (Test-Path -LiteralPath $f) { $lines = @([System.IO.File]::ReadAllLines($f) | Where-Object { $_ -ne $Key }) }
    $lines = @(@($lines | Select-Object -Last 199) + $Key)
    [System.IO.File]::WriteAllLines($f, [string[]]$lines)
}

# --- this session only: incognito --------------------------------------------
#  profile\session.ini, written by the "Who's playing?" box on PLAY. While
#  it says incognito, the check-ins say "invisible" whatever the profile's
#  own status is. The helper deletes it when it signs off, so the next time
#  is back to normal by itself.
function Test-SocialIncognito([string]$Ws) {
    $P = Get-SocialPaths $Ws
    $i = Read-SocialSmallIni (Join-SocialPath $P.ProfileDir 'session.ini')
    return ([string]$i['incognito'] -eq 'yes')
}

function Set-SocialIncognito([string]$Ws, [bool]$On) {
    $P = Get-SocialPaths $Ws
    $f = Join-SocialPath $P.ProfileDir 'session.ini'
    if ($On) {
        New-SocialDir $P.ProfileDir
        [System.IO.File]::WriteAllLines($f, [string[]]@('; This session only. Deleted when the session ends.', 'incognito = yes'))
    }
    elseif (Test-Path -LiteralPath $f) { Remove-Item -LiteralPath $f -Force }
}

# --- more than one person per drive ----------------------------------------------
#  Each person who logs in on this drive keeps their own copy of the things
#  that only live here - their switches, favourites, hidden games and
#  picture - in profile\people\<id>\. Switching person puts the current one
#  away and brings the other back, so everybody's settings come back as
#  they left them.
$script:SocialPersonFiles = @('profile.ini', 'hidden-games.txt', 'avatar.png')

function Get-SocialPersonDir([string]$Ws, [string]$Id) {
    return (Join-SocialPath (Join-SocialPath (Get-SocialPaths $Ws).ProfileDir 'people') $Id)
}

function Save-SocialPersonCopy([string]$Ws) {
    $prof = Read-SocialProfile $Ws
    if ($null -eq $prof -or $prof.Guest -or $prof.Id -notmatch $script:SocialIdPattern) { return $false }
    $P = Get-SocialPaths $Ws
    $dir = Get-SocialPersonDir $Ws $prof.Id
    New-SocialDir $dir
    foreach ($n in $script:SocialPersonFiles) {
        $src = Join-SocialPath $P.ProfileDir $n
        $dst = Join-SocialPath $dir $n
        if (Test-Path -LiteralPath $src) { Copy-Item -LiteralPath $src -Destination $dst -Force }
        elseif (Test-Path -LiteralPath $dst) { Remove-Item -LiteralPath $dst -Force }
    }
    return $true
}

# The saved profile for $Id, read without bringing it back, or $null.
function Read-SocialPersonCopy([string]$Ws, [string]$Id) {
    if ($Id -notmatch $script:SocialIdPattern) { return $null }
    $f = Join-SocialPath (Get-SocialPersonDir $Ws $Id) 'profile.ini'
    if (-not (Test-Path -LiteralPath $f)) { return $null }
    $p = Read-SocialProfile $Ws $f
    if ($null -ne $p -and -not $p.Guest -and $p.Id -eq $Id) { return $p }
    return $null
}

# Brings $Id's own files back as the current profile. Returns $true when
# there was a copy to bring back. The current person must be put away first.
function Restore-SocialPersonCopy([string]$Ws, [string]$Id) {
    if ($null -eq (Read-SocialPersonCopy $Ws $Id)) { return $false }
    $P = Get-SocialPaths $Ws
    $dir = Get-SocialPersonDir $Ws $Id
    foreach ($n in $script:SocialPersonFiles) {
        $src = Join-SocialPath $dir $n
        $dst = Join-SocialPath $P.ProfileDir $n
        if (Test-Path -LiteralPath $src) { Copy-Item -LiteralPath $src -Destination $dst -Force }
        elseif (Test-Path -LiteralPath $dst) { Remove-Item -LiteralPath $dst -Force }
    }
    return $true
}

# --- remembering a password ---------------------------------------------------------
#  profile\logins.txt gains a fourth field: the day the password was last
#  typed on this drive. Within $SocialTrustDays of it, the "Who's playing?"
#  box lets that person straight in.
$script:SocialTrustDays = 60

function Set-SocialLoginTrusted([string]$Ws, [string]$Id) {
    $today = (Get-Date).ToString('yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)
    $list = @(Get-SocialLogins $Ws | ForEach-Object { if ($_.Id -eq $Id) { $_.Trusted = $today }; $_ })
    Save-SocialLogins $Ws $list
}

function Test-SocialLoginTrusted([string]$Ws, [string]$Id) {
    $l = @(Get-SocialLogins $Ws | Where-Object { $_.Id -eq $Id }) | Select-Object -First 1
    if ($null -eq $l -or [string]$l.Trusted -eq '') { return $false }
    $d = [DateTime]::MinValue
    if (-not [DateTime]::TryParseExact([string]$l.Trusted, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$d)) { return $false }
    return (((Get-Date) - $d).TotalDays -le $script:SocialTrustDays)
}

# The drive's own picker switch: profile\picker.ini, "ask = on|off".
function Get-SocialAskWho([string]$Ws) {
    $i = Read-SocialSmallIni (Join-SocialPath (Get-SocialPaths $Ws).ProfileDir 'picker.ini')
    return ([string]$i['ask'] -ne 'off')
}

function Set-SocialAskWho([string]$Ws, [bool]$On) {
    $P = Get-SocialPaths $Ws
    New-SocialDir $P.ProfileDir
    [System.IO.File]::WriteAllLines((Join-SocialPath $P.ProfileDir 'picker.ini'), [string[]]@(
        '; Show "Who''s playing?" when PLAY is pressed. off = go straight in as whoever is logged in.',
        ('ask = ' + $(if ($On) { 'on' } else { 'off' }))))
}
