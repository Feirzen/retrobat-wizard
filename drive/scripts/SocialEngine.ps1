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

    THE LOCAL PROFILE lives on the drive, in _ClaudeWorkspace\profile\
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
        ProfileDir = Join-SocialPath $Ws 'profile'
        Profile    = Join-SocialPath $Ws 'profile\profile.ini'
        Avatar     = Join-SocialPath $Ws 'profile\avatar.png'
        SocialDir  = Join-SocialPath $Ws 'social'
        Token      = Join-SocialPath $Ws 'social\social-token.txt'
        Config     = Join-SocialPath $Ws 'social\social.ini'
        Cache      = Join-SocialPath $Ws 'social\cache'
        Players    = Join-SocialPath $Ws 'social\cache\players.json'
        Log        = Join-SocialPath $Ws 'social\social.log'
    }
}

function New-SocialDir([string]$Path) {
    if ($Path -and -not (Test-Path -LiteralPath $Path)) { [void](New-Item -ItemType Directory -Path $Path -Force) }
}

function Write-SocialLog([string]$Ws, [string]$Msg) {
    try {
        $P = Get-SocialPaths $Ws
        New-SocialDir $P.SocialDir
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
function Read-SocialProfile([string]$Ws) {
    $P = Get-SocialPaths $Ws
    if (-not (Test-Path -LiteralPath $P.Profile)) { return $null }
    $ini = @{}
    foreach ($line in [System.IO.File]::ReadAllLines($P.Profile)) {
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
        Created  = [string]$ini['created']
        Pw       = $(if ([string]$ini['pw'] -match '^[a-f0-9]{64}$') { [string]$ini['pw'] } else { '' })
        PwSet    = [string]$ini['pwset']
        NameReq  = Get-SocialClean ([string]$ini['namereq']) 20
    }
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
            ('created  = ' + $Prof.Created),
            ('pw       = ' + [string]$Prof.Pw),
            ('pwset    = ' + [string]$Prof.PwSet),
            ('namereq  = ' + (Get-SocialClean ([string]$Prof.NameReq) 20))
        )
    }
    [System.IO.File]::WriteAllLines($P.Profile, [string[]]$lines)
}

function New-SocialProfile([string]$Username, [string]$Avatar) {
    return [pscustomobject]@{
        Guest = $false; Id = (New-SocialId); Username = $Username.Trim(); Avatar = $Avatar
        Status = 'online'; Text = ''; ShowGame = $true; Popups = $true
        Friends = @(); Declined = @(); Created = (Format-SocialTime (Get-SocialNowUtc))
        Pw = ''; PwSet = ''; NameReq = ''
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
            $r.Body = [string]$resp.Content
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
function ConvertTo-SocialRecordJson($Prof, $Presence, [string]$Version) {
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
        Blob     = $BlobId
    }
}

# Everybody, in one request. Returns @{ Ok; Players; Message }. On success the
# list is also saved to social\cache\players.json, so the wizard can draw the
# friend list straight away next time, before the network answers.
function Get-SocialPlayers([string]$Ws) {
    $res = @{ Ok = $false; Players = @(); Message = ''; Names = @{}; Admins = @() }
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
    $res.Names = $x.Names; $res.Admins = $x.Admins
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
function Publish-SocialRecord([string]$Ws, $Prof, $Presence, [string]$Version, [string]$KnownBlob = '') {
    $res = @{ Ok = $false; Message = '' }
    if ($null -eq $Prof -or $Prof.Guest -or $Prof.Id -notmatch $script:SocialIdPattern) { $res.Message = 'No profile, nothing to send.'; return $res }
    $repo = Get-SocialRepo $Ws
    $url = "https://api.github.com/repos/$repo/contents/players/$($Prof.Id).json"
    $json = ConvertTo-SocialRecordJson $Prof $Presence $Version
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
function ConvertFrom-SocialExtras($Data) {
    $out = @{ Names = @{}; Admins = @() }
    try {
        foreach ($e in @($Data.data.repository.names.entries)) {
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
    if (-not (Test-Path -LiteralPath $P.Players)) { return @{ Names = @{}; Admins = @() } }
    try { return (ConvertFrom-SocialExtras ([System.IO.File]::ReadAllText($P.Players) | ConvertFrom-Json)) }
    catch { return @{ Names = @{}; Admins = @() } }
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
        Created = ''; Pw = $Rec.Pw; PwSet = $Rec.PwSet; NameReq = $Rec.NameReq
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
                $out += [pscustomobject]@{ Id = $parts[0]; Username = (Get-SocialClean $parts[1] 20); Avatar = $parts[2] }
            }
        }
    }
    # The one kept by "play as a guest" before logins existed.
    $old = Join-SocialPath $P.ProfileDir 'profile-before-guest.ini'
    if ((Test-Path -LiteralPath $old) -and -not (Test-Path -LiteralPath $f)) {
        try {
            $oid = ''; $oname = ''
            foreach ($l in [System.IO.File]::ReadAllLines($old)) { if ($l -match '^\s*id\s*=\s*([a-z0-9]{10})\s*$') { $oid = $Matches[1] }; if ($l -match '^\s*username\s*=\s*(.+)$') { $oname = $Matches[1].Trim() } }
            if ($oid -and $oname) { $out += [pscustomobject]@{ Id = $oid; Username = $oname; Avatar = 'icon:gameboy' } }
        } catch { }
    }
    return @($out | Group-Object Id | ForEach-Object { $_.Group[0] })
}

function Save-SocialLogins([string]$Ws, $List) {
    $P = Get-SocialPaths $Ws
    New-SocialDir $P.ProfileDir
    $lines = @($List | ForEach-Object { '{0}|{1}|{2}' -f $_.Id, $_.Username, $_.Avatar })
    [System.IO.File]::WriteAllLines((Join-SocialPath $P.ProfileDir 'logins.txt'), [string[]]$lines)
}

function Add-SocialLogin([string]$Ws, $Prof) {
    $list = @(Get-SocialLogins $Ws | Where-Object { $_.Id -ne $Prof.Id })
    $av = $(if ([string]$Prof.Avatar -like 'icon:*') { $Prof.Avatar } else { 'icon:gameboy' })
    Save-SocialLogins $Ws (@([pscustomobject]@{ Id = $Prof.Id; Username = $Prof.Username; Avatar = $av }) + $list)
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
        if ($topic -eq '') { return $false }
        $h = @{ Title = (Get-SocialClean $Title 80); Tags = 'video_game' }
        Invoke-WebRequest -Uri ("https://ntfy.sh/" + $topic) -Method Post -Headers $h -Body ([System.Text.Encoding]::UTF8.GetBytes((Get-SocialClean $Text 300))) -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop | Out-Null
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
