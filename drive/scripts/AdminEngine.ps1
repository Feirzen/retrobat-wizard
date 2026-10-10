<#
    AdminEngine.ps1 - what the Admin tab does.

    FUNCTIONS ONLY. Dot-source it AFTER SocialEngine.ps1, whose GitHub helpers
    it uses. Used by wizard\SetupWizard.ps1.

    THE IDEA (Steven, 2026-10-10): one extra tab with the admin things in it,
    seen only by people on admin\admins.txt in the private repo. Steven is
    the first; he can add more from the tab. Everything else in the wizard
    stays the same for an admin.

    It is a light lock like the rest of the friends system: the shared key
    can write anything in the private repo, so the list only decides who SEES
    the tab. That is said on the tab itself.

    WHAT IT DOES
        reports        the open bug reports and suggestions (GitHub issues in
                       the private repo): read them, mark them done
        name requests  approve or decline: writes names\<id>.txt, and that
                       person's own wizard changes their name
        admins         who has the tab
        phone alerts   the ntfy channel in admin\notify.txt
        library        Publish a game: uploads the file to the PUBLIC repo's
                       "library" release and adds it to library\library.json,
                       in one go. This needs a second key that can write to
                       the public repo, kept only on the admin's own drive in
                       social\library-key.txt (never shipped, never sent).

    ASCII ONLY, Windows PowerShell 5.1. Every root is a parameter.
#>

$script:AdminLibRepo = 'Feirzen/retrobat-wizard'
$script:AdminApiBase = 'https://api.github.com'          # the tests point these
$script:AdminUploadBase = 'https://uploads.github.com'   # at a fake GitHub

# ---------------------------------------------------------------------------
#  Small file writes in the private repo
# ---------------------------------------------------------------------------
# Creates or replaces one text file. Returns $true when GitHub took it.
function Set-AdminRepoFile([string]$Ws, [string]$Path, [string]$Text, [string]$Message) {
    $repo = Get-SocialRepo $Ws
    $url = "https://api.github.com/repos/$repo/contents/$Path"
    $sha = ''
    $g = Invoke-SocialApi $Ws 'GET' $url
    if ($g.Status -eq 200) { try { $sha = [string](($g.Body | ConvertFrom-Json).sha) } catch { } }
    $b64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($Text))
    $body = '{"message":' + (ConvertTo-SocialJsonString $Message) + ',"content":"' + $b64 + '"'
    if ($sha -ne '') { $body += ',"sha":"' + $sha + '"' }
    $body += '}'
    $r = Invoke-SocialApi $Ws 'PUT' $url $body
    if ($r.Status -ne 200 -and $r.Status -ne 201) { Write-SocialLog $Ws ("admin: write $Path failed {0}" -f $r.Status); return $false }
    return $true
}

# ---------------------------------------------------------------------------
#  Reports
# ---------------------------------------------------------------------------
# The open ones, newest first. @{ Ok; Items; Message }
function Get-AdminReports([string]$Ws) {
    $res = @{ Ok = $false; Items = @(); Message = '' }
    $repo = Get-SocialRepo $Ws
    $r = Invoke-SocialApi $Ws 'GET' "https://api.github.com/repos/$repo/issues?state=open&per_page=50"
    if ($r.Status -ne 200) { $res.Message = $(if ($r.Status -eq 0) { 'Could not reach GitHub.' } else { "GitHub said $($r.Status)." }); return $res }
    try { $d = $r.Body | ConvertFrom-Json } catch { $res.Message = 'GitHub sent something unreadable.'; return $res }
    $items = @()
    foreach ($i in @($d)) {
        if ($null -eq $i -or $null -ne $i.pull_request) { continue }
        $when = Get-SocialTimeValue $i.created_at
        $items += [pscustomobject]@{
            Number = [int]$i.number
            Title  = Get-SocialClean ([string]$i.title) 120
            Body   = [string]$i.body
            When   = $(if ($null -ne $when) { $when.ToLocalTime().ToString('MMM d, h:mm tt') } else { '' })
            Url    = [string]$i.html_url
        }
    }
    $res.Ok = $true; $res.Items = $items
    return $res
}

function Close-AdminReport([string]$Ws, [int]$Number) {
    $repo = Get-SocialRepo $Ws
    $r = Invoke-SocialApi $Ws 'PATCH' "https://api.github.com/repos/$repo/issues/$Number" '{"state":"closed","state_reason":"completed"}'
    return ($r.Status -eq 200)
}

# ---------------------------------------------------------------------------
#  Name requests, admins, phone alerts
# ---------------------------------------------------------------------------
# People asking for a new name that no admin has answered yet.
function Get-AdminNameRequests($Players, $Extras) {
    $out = @()
    foreach ($p in @($Players | Where-Object { $null -ne $_ -and $_.NameReq -ne '' })) {
        $a = $Extras.Names[$p.Id]
        if ($null -ne $a -and $a.Name -eq $p.NameReq) { continue }   # answered, waiting for them to pick it up
        $out += $p
    }
    return $out
}

function Set-AdminNameAnswer([string]$Ws, [string]$Id, [string]$Name, [bool]$Approve) {
    if ($Id -notmatch '^[a-z0-9]{10}$') { return $false }
    $word = $(if ($Approve) { 'approved' } else { 'declined' })
    return (Set-AdminRepoFile $Ws "names/$Id.txt" ($word + ':' + (Get-SocialClean $Name 20)) "name $word for $Id")
}

function Set-AdminList([string]$Ws, [string[]]$Ids) {
    $clean = @($Ids | Where-Object { $_ -match '^[a-z0-9]{10}$' } | Select-Object -Unique)
    if ($clean.Count -eq 0) { return $false }      # never leave nobody in charge
    $text = "# Player ids that see the Admin tab, one per line.`n" + ($clean -join "`n") + "`n"
    return (Set-AdminRepoFile $Ws 'admin/admins.txt' $text 'admins list')
}

function Set-AdminNotifyTopic([string]$Ws, [string]$Topic) {
    if ($Topic -notmatch '^[A-Za-z0-9_\-]{8,64}$') { return $false }
    return (Set-AdminRepoFile $Ws 'admin/notify.txt' ($Topic + "`n") 'phone alert channel')
}

function New-AdminNotifyTopic {
    return ('rbw-' + (New-SocialId) + (New-SocialId).Substring(0, 6))
}

# ---------------------------------------------------------------------------
#  Publishing a game to the online library
# ---------------------------------------------------------------------------
function Get-AdminLibKeyPath([string]$Ws) { return (Join-SocialPath $Ws 'social\library-key.txt') }

function Get-AdminLibKey([string]$Ws) {
    $f = Get-AdminLibKeyPath $Ws
    if (-not (Test-Path -LiteralPath $f)) { return '' }
    $t = ([System.IO.File]::ReadAllText($f)).Trim()
    if ($t -match '^(github_pat_|ghp_)[A-Za-z0-9_]+$') { return $t }
    return ''
}

function Set-AdminLibKey([string]$Ws, [string]$Key) {
    $k = ([string]$Key).Trim()
    if ($k -notmatch '^(github_pat_|ghp_)[A-Za-z0-9_]+$') { return $false }
    New-SocialDir (Join-SocialPath $Ws 'social')
    [System.IO.File]::WriteAllText((Get-AdminLibKeyPath $Ws), $k)
    return $true
}

# Like Invoke-SocialApi, but with the library key and any URL.
function Invoke-AdminLibApi([string]$Key, [string]$Method, [string]$Url, [string]$BodyText = '') {
    $r = @{ Status = 0; Body = '' }
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch { }
    $old = $ProgressPreference; $ProgressPreference = 'SilentlyContinue'
    try {
        $h = @{ Authorization = "Bearer $Key"; Accept = 'application/vnd.github+json'; 'X-GitHub-Api-Version' = '2022-11-28' }
        $a = @{ Uri = $Url; Method = $Method; Headers = $h; UseBasicParsing = $true; TimeoutSec = 60; ErrorAction = 'Stop' }
        if ($BodyText -ne '') { $a.Body = [System.Text.Encoding]::UTF8.GetBytes($BodyText); $a.ContentType = 'application/json; charset=utf-8' }
        $resp = Invoke-WebRequest @a
        $r.Status = [int]$resp.StatusCode; $r.Body = [string]$resp.Content
    }
    catch {
        try { $r.Status = [int]$_.Exception.Response.StatusCode } catch { }
        $r.Body = $_.Exception.Message
    }
    finally { $ProgressPreference = $old }
    return $r
}

function ConvertTo-AdminJsonString([string]$s) {
    if ($null -eq $s) { $s = '' }
    $o = $s.Replace('\', '\\').Replace('"', '\"') -replace "[`r`n`t]", ' '
    $o = $o -replace '[^\x20-\x7E]', ''
    return '"' + $o + '"'
}

# library.json written by hand: Windows PowerShell 5.1's ConvertTo-Json
# flattens a one-item list, which would break a game with one file.
function ConvertTo-AdminLibraryJson($Note, $Games) {
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append("{`n  `"version`": 1,`n  `"note`": " + (ConvertTo-AdminJsonString $Note) + ",`n  `"games`": [")
    $first = $true
    foreach ($g in @($Games)) {
        if (-not $first) { [void]$sb.Append(',') }
        $first = $false
        [void]$sb.Append("`n    {`n")
        [void]$sb.Append('      "id": ' + (ConvertTo-AdminJsonString $g.id) + ",`n")
        [void]$sb.Append('      "title": ' + (ConvertTo-AdminJsonString $g.title) + ",`n")
        [void]$sb.Append('      "system": ' + (ConvertTo-AdminJsonString $g.system) + ",`n")
        [void]$sb.Append('      "players": ' + (ConvertTo-AdminJsonString $g.players) + ",`n")
        [void]$sb.Append('      "description": ' + (ConvertTo-AdminJsonString $g.description) + ",`n")
        [void]$sb.Append('      "added": ' + (ConvertTo-AdminJsonString $g.added) + ",`n")
        [void]$sb.Append('      "files": [')
        $ff = $true
        foreach ($f in @($g.files)) {
            if (-not $ff) { [void]$sb.Append(',') }
            $ff = $false
            [void]$sb.Append("`n        { `"name`": " + (ConvertTo-AdminJsonString $f.name) + ', "url": ' + (ConvertTo-AdminJsonString $f.url) +
                ', "size": ' + ([long]$f.size) + ', "sha256": ' + (ConvertTo-AdminJsonString $f.sha256) + ' }')
        }
        [void]$sb.Append("`n      ]`n    }")
    }
    [void]$sb.Append("`n  ]`n}`n")
    return $sb.ToString()
}

function Get-AdminLibId([string]$Title) {
    $id = (([string]$Title).ToLower() -replace '[^a-z0-9]+', '-').Trim('-')
    if ($id -eq '') { $id = 'game' }
    if ($id.Length -gt 40) { $id = $id.Substring(0, 40).Trim('-') }
    return $id
}

# The whole publish, meant to run in a background runspace. $Sync is a
# synchronized hashtable the window reads: Stage (words) and Percent.
# Returns @{ Ok; Message }.
#   1. fingerprint the file (SHA-256)
#   2. find the "library" release on the public repo, or make it
#   3. upload the file to it (replacing one with the same name)
#   4. add the game to library\library.json (replacing one with the same id)
function Publish-AdminLibraryGame([string]$Ws, [string]$File, [string]$System, [string]$Title, [string]$Players, [string]$Description, $Sync) {
    $res = @{ Ok = $false; Message = '' }
    $key = Get-AdminLibKey $Ws
    if ($key -eq '') { $res.Message = 'There is no library key on this drive yet.'; return $res }
    if (-not (Test-Path -LiteralPath $File)) { $res.Message = 'The file is gone.'; return $res }
    $api = "$script:AdminApiBase/repos/$script:AdminLibRepo"
    $id = Get-AdminLibId $Title
    $leaf = [System.IO.Path]::GetFileName($File)
    if ($leaf -match '[^\x20-\x7E]' -or $leaf -match '[\\/:*?"<>|]') { $res.Message = 'Rename the file to plain letters and numbers first.'; return $res }
    $len = (Get-Item -LiteralPath $File).Length
    if ($len -ge 2GB) { $res.Message = 'GitHub takes files under 2 GB. This one is bigger.'; return $res }

    $Sync.Stage = 'Fingerprinting the file...'; $Sync.Percent = 0
    $sha = (Get-FileHash -LiteralPath $File -Algorithm SHA256).Hash.ToLower()

    $Sync.Stage = 'Finding the library on GitHub...'
    $rel = Invoke-AdminLibApi $key 'GET' "$api/releases/tags/library"
    if ($rel.Status -eq 404) {
        $body = '{"tag_name":"library","target_commitish":"main","name":"Game library","body":"Files for the wizard''s online game library. Added from the Admin tab."}'
        $rel = Invoke-AdminLibApi $key 'POST' "$api/releases" $body
    }
    if ($rel.Status -ne 200 -and $rel.Status -ne 201) {
        $res.Message = $(if ($rel.Status -eq 401 -or $rel.Status -eq 403) { 'GitHub refused the library key. It may have expired, or it needs "Contents: Read and write" on retrobat-wizard.' } else { "Could not reach the library on GitHub ($($rel.Status))." })
        return $res
    }
    $relObj = $rel.Body | ConvertFrom-Json
    $asset = ($id + '__' + ($leaf -replace '[^A-Za-z0-9._\-]', '.'))
    foreach ($a in @($relObj.assets)) {
        if ($null -ne $a -and [string]$a.name -eq $asset) { [void](Invoke-AdminLibApi $key 'DELETE' "$api/releases/assets/$($a.id)") }
    }

    # The upload streams the file, so a big disc never sits in memory.
    $Sync.Stage = 'Uploading...'
    $upUrl = '{0}/repos/{1}/releases/{2}/assets?name={3}' -f $script:AdminUploadBase, $script:AdminLibRepo, $relObj.id, [Uri]::EscapeDataString($asset)
    $dlUrl = ''
    try {
        $req = [System.Net.HttpWebRequest]::Create($upUrl)
        $req.Method = 'POST'; $req.ContentType = 'application/octet-stream'; $req.ContentLength = $len
        $req.AllowWriteStreamBuffering = $false; $req.SendChunked = $false
        $req.Timeout = 3600000; $req.ReadWriteTimeout = 3600000
        $req.UserAgent = 'RetroBat-Wizard'; $req.Accept = 'application/vnd.github+json'
        $req.Headers.Add('Authorization', "Bearer $key")
        $req.Headers.Add('X-GitHub-Api-Version', '2022-11-28')
        $in = [System.IO.File]::OpenRead($File)
        try {
            $out = $req.GetRequestStream()
            try {
                $buf = New-Object byte[] (1MB); $sent = [long]0
                while (($n = $in.Read($buf, 0, $buf.Length)) -gt 0) {
                    $out.Write($buf, 0, $n); $sent += $n
                    $Sync.Percent = [int](100 * $sent / [math]::Max(1, $len))
                }
            } finally { $out.Close() }
        } finally { $in.Close() }
        $resp = $req.GetResponse()
        $txt = (New-Object System.IO.StreamReader($resp.GetResponseStream())).ReadToEnd()
        $resp.Close()
        $dlUrl = [string](($txt | ConvertFrom-Json).browser_download_url)
    }
    catch {
        $res.Message = 'The upload stopped: ' + $_.Exception.Message
        return $res
    }
    if ($dlUrl -notmatch '^https://github\.com/') { $res.Message = 'GitHub took the file but did not say where it is.'; return $res }

    $Sync.Stage = 'Adding it to the library list...'
    $lib = Invoke-AdminLibApi $key 'GET' "$api/contents/library/library.json"
    if ($lib.Status -ne 200) { $res.Message = "The file is up, but the library list could not be read ($($lib.Status)). Try Publish again."; return $res }
    $lo = $lib.Body | ConvertFrom-Json
    $cur = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String(([string]$lo.content -replace '\s', ''))) | ConvertFrom-Json
    $games = @(@($cur.games) | Where-Object { $null -ne $_ -and [string]$_.id -ne $id })
    $games += [pscustomobject]@{
        id = $id; title = $Title.Trim(); system = $System; players = $Players.Trim(); description = $Description.Trim()
        added = (Get-Date -Format 'yyyy-MM-dd')
        files = @([pscustomobject]@{ name = $leaf; url = $dlUrl; size = $len; sha256 = $sha })
    }
    $games = @($games | Sort-Object @{ Expression = { [string]$_.system } }, @{ Expression = { ([string]$_.title).ToLower() } })
    $json = ConvertTo-AdminLibraryJson ([string]$cur.note) $games
    $b64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($json))
    $put = Invoke-AdminLibApi $key 'PUT' "$api/contents/library/library.json" ('{"message":' + (ConvertTo-AdminJsonString ("library: add " + $Title)) + ',"content":"' + $b64 + '","sha":"' + [string]$lo.sha + '"}')
    if ($put.Status -ne 200 -and $put.Status -ne 201) { $res.Message = "The file is up, but the library list could not be saved ($($put.Status)). Try Publish again."; return $res }
    $Sync.Percent = 100
    $res.Ok = $true
    $res.Message = "$($Title.Trim()) is in the online library. Friends see it within about 5 minutes (GitHub's copy refreshes)."
    return $res
}
