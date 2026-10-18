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
        library        Publish a game, in one go. Since 2026-10-11 (Steven:
                       "list on the public one but reside in the private"):
                         - the FILE goes to the PRIVATE repo's "library"
                           release, with the shared key every wizard already
                           has. Strangers cannot download it; only a wizard
                           can (GameLibrary.ps1, Install-LibGame).
                         - the LISTING (name, console, players, words, size,
                           checksum) goes into the PUBLIC library\library.json,
                           with the file written as "private:<name>" instead
                           of a link. The website shows it with "Get it in
                           the wizard" instead of a download button.
                       Writing that public list needs a second key that can
                       write to the public repo, kept only on the admin's own
                       drive in social\library-key.txt (never shipped).
                       Since 2026-10-11 (Steven: "pull what is needed",
                       "upload multiple games at once"): several games in
                       one go (Publish-AdminLibraryGames), and each game's
                       box art goes to the PUBLIC repo as library\art\<id>.png
                       (or .jpg), listed as "art" for the website and wizard.
                       Since 2026-10-11 (Steven's first real test: "GitHub
                       took the file but did not say where it is"): GitHub
                       tidies file names on upload (a run of dots becomes
                       one), so the name it ANSWERS with is the one written
                       down; a file already up with the same fingerprint is
                       not sent again (a retry after a hiccup is instant);
                       older copies of the same game are cleared once the
                       list is saved. And Remove-AdminLibraryGames takes
                       games off again: the list entry, the box art, the
                       private file, plus any leftover upload not on the
                       list.

    ASCII ONLY, Windows PowerShell 5.1. Every root is a parameter.
#>

$script:AdminLibRepo = 'Feirzen/retrobat-wizard'           # the public list
# The files live in the private repo, whatever social\social.ini names
# (Get-SocialRepo). Set this only to override it, as the tests do.
$script:AdminFileRepo = ''
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
        if ([string]$g.art -ne '') { [void]$sb.Append('      "art": ' + (ConvertTo-AdminJsonString $g.art) + ",`n") }
        [void]$sb.Append('      "files": [')
        $ff = $true
        foreach ($f in @($g.files)) {
            if (-not $ff) { [void]$sb.Append(',') }
            $ff = $false
            [void]$sb.Append("`n        { `"name`": " + (ConvertTo-AdminJsonString $f.name) + ', "url": ' + (ConvertTo-AdminJsonString $f.url) +
                ', "size": ' + ([long]$f.size) + ', "sha256": ' + (ConvertTo-AdminJsonString $f.sha256) + ' }')
        }
        [void]$sb.Append("`n      ]")
        # A game too big for one GitHub file (2026-10-13): its pieces, and the
        # one file they glue back into. "files" is left empty for these, so a
        # wizard older than v3 (which cannot glue) simply does not offer it.
        if ($null -ne $g.parts -and @($g.parts.pieces).Count -gt 0) {
            [void]$sb.Append(",`n      `"parts`": { `"name`": " + (ConvertTo-AdminJsonString ([string]$g.parts.name)) + ', "size": ' + ([long]$g.parts.size) +
                ', "sha256": ' + (ConvertTo-AdminJsonString ([string]$g.parts.sha256)) + ', "pieces": [')
            $pf = $true
            foreach ($pc in @($g.parts.pieces)) {
                if (-not $pf) { [void]$sb.Append(',') }
                $pf = $false
                [void]$sb.Append("`n        { `"name`": " + (ConvertTo-AdminJsonString $pc.name) + ', "url": ' + (ConvertTo-AdminJsonString $pc.url) +
                    ', "size": ' + ([long]$pc.size) + ', "sha256": ' + (ConvertTo-AdminJsonString $pc.sha256) + ' }')
            }
            [void]$sb.Append("`n      ] }")
        }
        [void]$sb.Append("`n    }")
    }
    [void]$sb.Append("`n  ]`n}`n")
    return $sb.ToString()
}

# The name the file gets in the private release: <id>__<file name>, cleaned
# the way GitHub cleans names (anything but letters, digits, - and _ becomes
# a dot, a run of dots becomes one, none at either end). GitHub's answer is
# still what gets written down, in case it tidies something else one day.
function Get-AdminLibAssetName([string]$Id, [string]$Leaf) {
    $s = (([string]$Leaf) -replace '[^A-Za-z0-9_\-.]+', '.') -replace '\.{2,}', '.'
    $s = $s.Trim('.')
    if ($s -eq '') { $s = 'file' }
    return ($Id + '__' + $s)
}

# Every file in the private release (the release's own list).
function Get-AdminLibAssets($RelObj) {
    return @(@($RelObj.assets) | Where-Object { $null -ne $_ -and [string]$_.name -ne '' })
}

function Get-AdminLibId([string]$Title) {
    $id = (([string]$Title).ToLower() -replace '[^a-z0-9]+', '-').Trim('-')
    if ($id -eq '') { $id = 'game' }
    if ($id.Length -gt 40) { $id = $id.Substring(0, 40).Trim('-') }
    return $id
}

# --- games bigger than GitHub's 2 GB limit (2026-10-13) ----------------------
# Pieces just under 1.9 GB, so each is safely under the limit.
$script:AdminPieceSize = [long]1900MB

# SHA-256 of one stretch of a file, read in 4 MB steps (a piece never sits in
# memory whole).
function Get-AdminRangeHash([string]$File, [long]$Offset, [long]$Size) {
    $h = [System.Security.Cryptography.SHA256]::Create()
    $in = [System.IO.File]::OpenRead($File)
    try {
        [void]$in.Seek($Offset, 'Begin')
        $buf = New-Object byte[] (4MB); $left = $Size
        while ($left -gt 0) {
            $n = $in.Read($buf, 0, [int][math]::Min([long]$buf.Length, $left))
            if ($n -le 0) { break }
            [void]$h.TransformBlock($buf, 0, $n, $null, 0)
            $left -= $n
        }
        [void]$h.TransformFinalBlock((New-Object byte[] 0), 0, 0)
        return (([System.BitConverter]::ToString($h.Hash)) -replace '-', '').ToLower()
    }
    finally { $in.Close(); $h.Dispose() }
}

# ---------------------------------------------------------------------------
#  ONE UPLOAD, WITH RETRIES, SPEED AND A CHECK                  (2026-10-17)
# ---------------------------------------------------------------------------
#  Steven: a 1.9 GB piece kept stopping with "connection forcibly closed",
#  and he wanted "a speed and estimated time", and to be sure "the upload
#  matches exactly the source material". So every upload (a whole game or
#  one piece):
#    - tries up to 3 times, clearing any half-sent copy GitHub kept
#    - says how fast and how long is left, in $Sync.Stage
#    - is checked afterwards: GitHub's size, and its own SHA-256 of the file
#      (the "digest") against the one worked out here
#  Returns @{ Ok; Name; Message; Checked }.
function Format-AdminEta([double]$Sec) {
    if ($Sec -lt 60) { return 'under a minute left' }
    if ($Sec -lt 3600) { return ('about {0} min left' -f [math]::Ceiling($Sec / 60)) }
    return ('about {0:N1} hours left' -f ($Sec / 3600))
}
function Clear-AdminHalfUpload([string]$Fkey, [string]$Fapi, $RelId, [string]$Name) {
    try {
        $r = Invoke-AdminLibApi $Fkey 'GET' "$Fapi/releases/$RelId/assets?per_page=100"
        if ($r.Status -ne 200) { return }
        foreach ($a in @($r.Body | ConvertFrom-Json)) {
            if ($null -ne $a -and [string]$a.name -eq $Name) { [void](Invoke-AdminLibApi $Fkey 'DELETE' "$Fapi/releases/assets/$($a.id)") }
        }
    } catch { }
}
function Send-AdminUpload([string]$Fkey, [string]$Fapi, [string]$Frepo, $RelId, [string]$AssetName, [string]$File, [long]$Offset, [long]$Size, [string]$Sha, $Sync, [string]$Label) {
    $res = @{ Ok = $false; Name = ''; Message = ''; Checked = $false }
    $upUrl = '{0}/repos/{1}/releases/{2}/assets?name={3}' -f $script:AdminUploadBase, $Frepo, $RelId, [Uri]::EscapeDataString($AssetName)
    for ($try = 1; $try -le 3; $try++) {
        if ($try -gt 1) {
            $Sync.Stage = ('{0}: the connection dropped, trying again ({1} of 3)...' -f $Label, $try)
            Clear-AdminHalfUpload $Fkey $Fapi $RelId $AssetName
            Start-Sleep -Seconds (5 * $try)
        }
        try {
            $req = [System.Net.HttpWebRequest]::Create($upUrl)
            $req.Method = 'POST'; $req.ContentType = 'application/octet-stream'; $req.ContentLength = $Size
            $req.AllowWriteStreamBuffering = $false; $req.SendChunked = $false
            $req.Timeout = 3600000; $req.ReadWriteTimeout = 3600000
            $req.UserAgent = 'RetroBat-Wizard'; $req.Accept = 'application/vnd.github+json'
            $req.Headers.Add('Authorization', "Bearer $Fkey")
            $req.Headers.Add('X-GitHub-Api-Version', '2022-11-28')
            $in = [System.IO.File]::OpenRead($File)
            try {
                [void]$in.Seek($Offset, 'Begin')
                $out = $req.GetRequestStream()
                try {
                    $buf = New-Object byte[] (1MB); $sent = [long]0
                    $clock = [System.Diagnostics.Stopwatch]::StartNew(); $lastShow = -1000
                    while ($sent -lt $Size) {
                        $n = $in.Read($buf, 0, [int][math]::Min([long]$buf.Length, $Size - $sent))
                        if ($n -le 0) { break }
                        $out.Write($buf, 0, $n); $sent += $n
                        $Sync.Percent = [int](100 * $sent / [math]::Max(1, $Size))
                        $ms = $clock.ElapsedMilliseconds
                        if ($ms - $lastShow -ge 1000 -and $ms -gt 0) {
                            $lastShow = $ms
                            $bps = $sent / ($ms / 1000.0)
                            $eta = $(if ($bps -gt 0) { Format-AdminEta (($Size - $sent) / $bps) } else { '' })
                            $Sync.Stage = ('{0}: {1}% at {2:N1} MB/s, {3}' -f $Label, $Sync.Percent, ($bps / 1MB), $eta)
                        }
                    }
                } finally { $out.Close() }
            } finally { $in.Close() }
            $resp = $req.GetResponse()
            $txt = (New-Object System.IO.StreamReader($resp.GetResponseStream())).ReadToEnd()
            $resp.Close()
            $obj = $txt | ConvertFrom-Json
            $res.Name = [string]$obj.name
            # --- the check: GitHub's copy against the file here -----------
            $Sync.Stage = ('{0}: checking GitHub''s copy matches...' -f $Label)
            $gotSize = [long]$obj.size; $dig = [string]$obj.digest
            if ($dig -eq '' -and $null -ne $obj.id) {
                Start-Sleep -Seconds 3
                $chk = Invoke-AdminLibApi $Fkey 'GET' "$Fapi/releases/assets/$($obj.id)"
                if ($chk.Status -eq 200) { $o2 = $chk.Body | ConvertFrom-Json; $dig = [string]$o2.digest; $gotSize = [long]$o2.size }
            }
            if ($gotSize -ne $Size -or ($dig -ne '' -and $Sha -ne '' -and $dig -ne ('sha256:' + $Sha))) {
                $res.Message = ('{0}: GitHub''s copy did not match the file here, so it was taken down. Press Publish to send it again.' -f $Label)
                Clear-AdminHalfUpload $Fkey $Fapi $RelId $AssetName
                return $res
            }
            $res.Checked = ($dig -ne '')
            $res.Ok = $true
            return $res
        }
        catch {
            $res.Message = ('{0} stopped uploading: {1}' -f $Label, $_.Exception.Message)
            if ($try -eq 3) { return $res }
        }
    }
    return $res
}

# Uploads every piece to the private release. A piece already up with the
# same fingerprint is not sent again, so a stopped publish carries on where it
# left off. Fills in each piece's UpName. Returns @{ Ok; Message }.
function Send-AdminLibPieces([string]$Fkey, [string]$Fapi, [string]$Frepo, $RelObj, [string]$Id, [string]$File, $Pieces, $Sync) {
    $assets = @(Get-AdminLibAssets $RelObj)
    foreach ($pc in $Pieces) {
        foreach ($a in $assets) {
            if ([string]$a.name -eq $pc.Asset -and [string]$a.state -eq 'uploaded' -and [string]$a.digest -eq ('sha256:' + $pc.Sha) -and [long]$a.size -eq $pc.Size) { $pc.UpName = [string]$a.name }
            elseif ([string]$a.name -eq $pc.Asset) { [void](Invoke-AdminLibApi $Fkey 'DELETE' "$Fapi/releases/assets/$($a.id)") }
        }
        if ($pc.UpName -ne '') { continue }
        $Sync.Percent = 0
        $u = Send-AdminUpload $Fkey $Fapi $Frepo $RelObj.id $pc.Asset $File $pc.Offset $pc.Size $pc.Sha $Sync ('Piece {0} of {1}' -f $pc.Index, @($Pieces).Count)
        if (-not $u.Ok) { return @{ Ok = $false; Message = ($u.Message + '. Press Publish again: pieces already up are not sent twice.') } }
        $pc.UpName = $u.Name
        if ($pc.UpName -notmatch '^[A-Za-z0-9._\-]{1,200}$') { return @{ Ok = $false; Message = 'GitHub took a piece but answered with an odd name. Press Publish again.' } }
    }
    return @{ Ok = $true; Message = '' }
}

# The whole publish, meant to run in a background runspace. $Sync is a
# synchronized hashtable the window reads: Stage (words) and Percent.
# Returns @{ Ok; Message }.
#   1. fingerprint the file (SHA-256)
#   2. find the "library" release on the PRIVATE repo, or make it
#   3. upload the file to it (replacing one with the same name)
#   4. put its box art (Art, a picture file; '' for none) in the PUBLIC
#      repo's library\art\. A picture that fails never stops the game.
#   5. add the game to the PUBLIC library\library.json (replacing one with
#      the same id), its file written as "private:<name>"
function Publish-AdminLibraryGame([string]$Ws, [string]$File, [string]$System, [string]$Title, [string]$Players, [string]$Description, $Sync, [string]$Art = '') {
    $res = @{ Ok = $false; Message = '' }
    $key = Get-AdminLibKey $Ws
    if ($key -eq '') { $res.Message = 'There is no library key in this setup yet.'; return $res }
    $fkey = Get-SocialToken $Ws
    if ($fkey -eq '') { $res.Message = 'This setup has no friends key (social\social-token.txt), so there is nowhere private to put the file.'; return $res }
    if (-not (Test-Path -LiteralPath $File)) { $res.Message = 'The file is gone.'; return $res }
    $api = "$script:AdminApiBase/repos/$script:AdminLibRepo"
    $frepo = $(if ($script:AdminFileRepo -ne '') { $script:AdminFileRepo } else { Get-SocialRepo $Ws })
    $fapi = "$script:AdminApiBase/repos/$frepo"
    $id = Get-AdminLibId $Title
    $leaf = [System.IO.Path]::GetFileName($File)
    if ($leaf -match '[^\x20-\x7E]' -or $leaf -match '[\\/:*?"<>|]') { $res.Message = 'Rename the file to plain letters and numbers first.'; return $res }
    $len = (Get-Item -LiteralPath $File).Length
    # GitHub takes files under 2 GB. A bigger game goes up in pieces of
    # $script:AdminPieceSize and is glued back together by the wizard that
    # downloads it (2026-10-13). Nothing about it looks different anywhere.
    $pieces = @()
    $off = [long]0; $pn = 0
    while ($off -lt $len) {
        $pn++
        $sz = [long][math]::Min([long]$script:AdminPieceSize, $len - $off)
        $pieces += [pscustomobject]@{ Index = $pn; Offset = $off; Size = $sz; Sha = ''; Asset = ''; UpName = '' }
        $off += $sz
    }
    $split = ($pieces.Count -gt 1)
    if ($split -and $pieces.Count -gt 40) { $res.Message = 'This file is too big even in pieces (over 75 GB).'; return $res }

    $Sync.Stage = 'Fingerprinting the file...'; $Sync.Percent = 0
    $sha = (Get-FileHash -LiteralPath $File -Algorithm SHA256).Hash.ToLower()
    if ($split) {
        foreach ($pc in $pieces) {
            $Sync.Stage = ('Fingerprinting piece {0} of {1}...' -f $pc.Index, $pieces.Count)
            $pc.Sha = Get-AdminRangeHash $File $pc.Offset $pc.Size
            $pc.Asset = Get-AdminLibAssetName $id ($leaf + ('.part{0:D2}' -f $pc.Index))
        }
    }

    # Check the list can be written BEFORE uploading a big file, so a bad
    # library key fails in a second instead of after the upload.
    $Sync.Stage = 'Checking the library key...'
    $chk = Invoke-AdminLibApi $key 'GET' "$api/contents/library/library.json"
    if ($chk.Status -eq 401 -or $chk.Status -eq 403) { $res.Message = 'GitHub refused the library key. It may have expired, or it needs "Contents: Read and write" on retrobat-wizard.'; return $res }

    $Sync.Stage = 'Finding the private library on GitHub...'
    $rel = Invoke-AdminLibApi $fkey 'GET' "$fapi/releases/tags/library"
    if ($rel.Status -eq 404) {
        $body = '{"tag_name":"library","name":"Game library","body":"Files for the wizard''s online game library. Added from the Admin tab. Private: only a wizard can download them."}'
        $rel = Invoke-AdminLibApi $fkey 'POST' "$fapi/releases" $body
    }
    if ($rel.Status -ne 200 -and $rel.Status -ne 201) {
        $res.Message = $(if ($rel.Status -eq 401 -or $rel.Status -eq 403) { 'GitHub refused the friends key for the private library.' } else { "Could not reach the private library on GitHub ($($rel.Status))." })
        return $res
    }
    $relObj = $rel.Body | ConvertFrom-Json
    if ($split) {
        $up = Send-AdminLibPieces $fkey $fapi $frepo $relObj $id $File $pieces $Sync
        if (-not $up.Ok) { $res.Message = $up.Message; return $res }
        $upName = '<pieces>'
    }
    $asset = Get-AdminLibAssetName $id $leaf
    # Already up with the same fingerprint (a retry, or the same game again):
    # keep it and skip the upload. Anything else under that exact name goes,
    # or GitHub would refuse the new one.
    if (-not $split) { $upName = '' }
    if (-not $split) {
    foreach ($a in (Get-AdminLibAssets $relObj)) {
        $n = [string]$a.name
        if ($upName -eq '' -and $n.StartsWith($id + '__') -and [string]$a.state -eq 'uploaded' -and [string]$a.digest -eq ('sha256:' + $sha) -and [long]$a.size -eq $len) { $upName = $n; continue }
        if ($n -eq $asset) { [void](Invoke-AdminLibApi $fkey 'DELETE' "$fapi/releases/assets/$($a.id)") }
    }
    }

    # The upload streams the file, so a big disc never sits in memory.
    if ($upName -eq '') {
    $u = Send-AdminUpload $fkey $fapi $frepo $relObj.id $asset $File 0 $len $sha $Sync 'Uploading'
    if (-not $u.Ok) { $res.Message = $u.Message; return $res }
    $upName = $u.Name
    }
    else { $Sync.Stage = 'Already uploaded, skipping the upload...'; $Sync.Percent = 100 }
    # GitHub's own name for it is the one written down (it may tidy ours).
    if (-not $split -and $upName -notmatch '^[A-Za-z0-9._\-]{1,200}$') { $res.Message = 'GitHub took the file but answered with an odd name. Press Publish again: a file that is already up is not sent twice.'; return $res }
    $dlUrl = 'private:' + $upName

    $artPath = ''
    if ($Art -ne '') {
        $Sync.Stage = 'Adding the box art...'
        $artPath = Send-AdminLibArt $key $api $id $Art
    }

    $Sync.Stage = 'Adding it to the library list...'
    $lib = Invoke-AdminLibApi $key 'GET' "$api/contents/library/library.json"
    if ($lib.Status -ne 200) { $res.Message = "The file is up, but the library list could not be read ($($lib.Status)). Try Publish again."; return $res }
    $lo = $lib.Body | ConvertFrom-Json
    $cur = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String(([string]$lo.content -replace '\s', ''))) | ConvertFrom-Json
    # No new picture this time: keep the one it already had.
    $old = @(@($cur.games) | Where-Object { $null -ne $_ -and [string]$_.id -eq $id })
    if ($artPath -eq '' -and $old.Count -gt 0) { $artPath = [string]$old[0].art }
    $games = @(@($cur.games) | Where-Object { $null -ne $_ -and [string]$_.id -ne $id })
    if ($split) {
        $games += [pscustomobject]@{
            id = $id; title = $Title.Trim(); system = $System; players = $Players.Trim(); description = $Description.Trim()
            added = (Get-Date -Format 'yyyy-MM-dd'); art = $artPath
            files = @()
            parts = [pscustomobject]@{ name = $leaf; size = $len; sha256 = $sha
                pieces = @($pieces | ForEach-Object { [pscustomobject]@{ name = ($leaf + ('.part{0:D2}' -f $_.Index)); url = ('private:' + $_.UpName); size = $_.Size; sha256 = $_.Sha } }) }
        }
    }
    else {
    $games += [pscustomobject]@{
        id = $id; title = $Title.Trim(); system = $System; players = $Players.Trim(); description = $Description.Trim()
        added = (Get-Date -Format 'yyyy-MM-dd'); art = $artPath
        files = @([pscustomobject]@{ name = $leaf; url = $dlUrl; size = $len; sha256 = $sha })
    }
    }
    $games = @($games | Sort-Object @{ Expression = { [string]$_.system } }, @{ Expression = { ([string]$_.title).ToLower() } })
    $json = ConvertTo-AdminLibraryJson ([string]$cur.note) $games
    $b64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($json))
    $put = Invoke-AdminLibApi $key 'PUT' "$api/contents/library/library.json" ('{"message":' + (ConvertTo-AdminJsonString ("library: add " + $Title)) + ',"content":"' + $b64 + '","sha":"' + [string]$lo.sha + '"}')
    if ($put.Status -ne 200 -and $put.Status -ne 201) { $res.Message = "The file is up, but the library list could not be saved ($($put.Status)). Try Publish again."; return $res }
    # Older copies of this same game (another file name, or an upload that
    # never made the list) are not needed any more.
    $again = Invoke-AdminLibApi $fkey 'GET' "$fapi/releases/tags/library"
    if ($again.Status -eq 200) {
        $keepNames = @{ $upName = $true }
        if ($split) { foreach ($pc in $pieces) { $keepNames[$pc.UpName] = $true } }
        foreach ($a in (Get-AdminLibAssets ($again.Body | ConvertFrom-Json))) {
            if (-not $keepNames.ContainsKey([string]$a.name) -and ([string]$a.name).StartsWith($id + '__')) { [void](Invoke-AdminLibApi $fkey 'DELETE' "$fapi/releases/assets/$($a.id)") }
        }
    }
    $Sync.Percent = 100
    $res.Ok = $true
    $res.Message = "$($Title.Trim()) is in the online library. The file is private: only a wizard can download it. Friends see it within about 5 minutes (GitHub's copy refreshes)."
    return $res
}

# Puts one game's box art in the PUBLIC repo at library/art/<id>.<ext>, the
# way the website and the wizard read it. Returns that path, or '' when the
# picture is missing, not a picture, too big (over 3 MB), or GitHub said no.
function Send-AdminLibArt([string]$Key, [string]$Api, [string]$Id, [string]$Art) {
    try {
        if (-not (Test-Path -LiteralPath $Art)) { return '' }
        $ext = ([System.IO.Path]::GetExtension($Art)).ToLower()
        if ($ext -eq '.jpeg') { $ext = '.jpg' }
        if (@('.png', '.jpg', '.gif', '.webp') -notcontains $ext) { return '' }
        $bytes = [System.IO.File]::ReadAllBytes($Art)
        if ($bytes.Length -eq 0 -or $bytes.Length -gt 3MB) { return '' }
        $rel = 'library/art/' + $Id + $ext
        # the same game again: replace its picture (GitHub wants the old one's sha)
        $shaPart = ''
        $have = Invoke-AdminLibApi $Key 'GET' "$Api/contents/$rel"
        if ($have.Status -eq 200) { $shaPart = ',"sha":"' + [string](($have.Body | ConvertFrom-Json).sha) + '"' }
        $body = '{"message":' + (ConvertTo-AdminJsonString ('library: art for ' + $Id)) + ',"content":"' + [Convert]::ToBase64String($bytes) + '"' + $shaPart + '}'
        $put = Invoke-AdminLibApi $Key 'PUT' "$Api/contents/$rel" $body
        if ($put.Status -eq 200 -or $put.Status -eq 201) { return $rel }
    } catch { }
    return ''
}

# Several games in one go (the Admin tab's multi-pick). $Items is a list of
# @{ File; System; Title; Players; Description; Art }. Each one is published
# on its own, so one that fails never stops the rest. $Sync.Prefix says which
# game it is on ("Game 2 of 5: "). Returns @{ Ok; Message; Done; Failed }.
function Publish-AdminLibraryGames([string]$Ws, $Items, $Sync) {
    $list = @($Items | Where-Object { $null -ne $_ })
    $done = @(); $failed = @(); $lastMsg = ''
    $n = 0
    $skipped = @()
    foreach ($it in $list) {
        $n++
        # (2026-10-17) A game crossed off the queue while others upload.
        if ($null -ne $Sync.Skip -and $Sync.Skip.ContainsKey([string]$n)) { $skipped += [string]$it.Title; continue }
        $Sync.Current = $n
        $Sync.Prefix = $(if ($list.Count -gt 1) { "Game $n of $($list.Count): " } else { '' })
        $Sync.Percent = 0
        $r = Publish-AdminLibraryGame $Ws ([string]$it.File) ([string]$it.System) ([string]$it.Title) ([string]$it.Players) ([string]$it.Description) $Sync ([string]$it.Art)
        if ($r.Ok) { $done += [string]$it.Title } else { $failed += ('{0}: {1}' -f $it.Title, $r.Message); if ($lastMsg -eq '') { $lastMsg = [string]$r.Message } }
        # A missing key stops every game the same way: say it once.
        if (-not $r.Ok -and ($r.Message -like '*library key*' -or $r.Message -like '*friends key*')) { break }
    }
    $Sync.Prefix = ''
    $Sync.Current = 0
    $res = @{ Ok = ($failed.Count -eq 0 -and $done.Count -gt 0); Done = $done; Failed = $failed; Message = '' }
    if ($list.Count -eq 1) {
        $res.Message = $(if ($res.Ok) { "$($done[0]) is in the online library, and GitHub's copy was checked against the file here. The file is private: only a wizard can download it. Friends see it within about 5 minutes (GitHub's copy refreshes)." } elseif ($skipped.Count -gt 0) { 'Crossed off, nothing was sent.' } else { $lastMsg })
        return $res
    }
    $m = @()
    if ($done.Count -gt 0) { $m += ('In the online library ({0}), each checked against the file here: {1}.' -f $done.Count, ($done -join ', ')) }
    if ($skipped.Count -gt 0) { $m += ('Crossed off: {0}.' -f ($skipped -join ', ')) }
    if ($failed.Count -gt 0) { $m += ("Did not go up:`n" + ($failed -join "`n")) }
    if ($done.Count -gt 0) { $m += "Friends see them within about 5 minutes (GitHub's copy refreshes)." }
    $res.Message = ($m -join "`n`n")
    return $res
}

# ---------------------------------------------------------------------------
#  Taking games off the online library (Steven, 2026-10-11: "is there any
#  way to remove games from the online library? There had better be")
# ---------------------------------------------------------------------------
# The private file names a list of games uses (their "private:<name>" files).
function Get-AdminLibUsedNames($Games) {
    $used = @{}
    foreach ($g in @($Games)) {
        if ($null -eq $g) { continue }
        $all = @($g.files)
        if ($null -ne $g.parts) { $all += @($g.parts.pieces) }
        foreach ($f in $all) {
            if ($null -eq $f) { continue }
            $u = [string]$f.url
            if ($u -like 'private:*') { $used[$u.Substring(8)] = $true }
        }
    }
    return $used
}

# What is up there now. Returns @{ Ok; Message; Games; Leftovers }:
#   Games      the list's entries (id, title, system, files, art)
#   Leftovers  files in the private release that no game on the list uses
#              (an upload that stopped before the list was saved)
function Get-AdminLibraryContents([string]$Ws) {
    $res = @{ Ok = $false; Message = ''; Games = @(); Leftovers = @() }
    $key = Get-AdminLibKey $Ws
    if ($key -eq '') { $res.Message = 'There is no library key in this setup yet.'; return $res }
    $fkey = Get-SocialToken $Ws
    $api = "$script:AdminApiBase/repos/$script:AdminLibRepo"
    $frepo = $(if ($script:AdminFileRepo -ne '') { $script:AdminFileRepo } else { Get-SocialRepo $Ws })
    $fapi = "$script:AdminApiBase/repos/$frepo"
    $lib = Invoke-AdminLibApi $key 'GET' "$api/contents/library/library.json"
    if ($lib.Status -ne 200) { $res.Message = "Could not read the library list ($($lib.Status))."; return $res }
    $cur = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String(([string](($lib.Body | ConvertFrom-Json).content) -replace '\s', ''))) | ConvertFrom-Json
    $res.Games = @(@($cur.games) | Where-Object { $null -ne $_ -and [string]$_.id -ne '' })
    $used = Get-AdminLibUsedNames $res.Games
    if ($fkey -ne '') {
        $rel = Invoke-AdminLibApi $fkey 'GET' "$fapi/releases/tags/library"
        if ($rel.Status -eq 200) {
            $res.Leftovers = @(Get-AdminLibAssets ($rel.Body | ConvertFrom-Json) | Where-Object { -not $used.ContainsKey([string]$_.name) })
        }
    }
    $res.Ok = $true
    return $res
}

# Takes the games with these ids off: the list FIRST (so nobody is offered a
# game whose file is gone), then each one's box art and private file. Also
# deletes $Leftovers (unused files Get-AdminLibraryContents found).
# Returns @{ Ok; Message; Removed (titles); Cleared (leftover count) }.
function Remove-AdminLibraryGames([string]$Ws, [string[]]$GameIds, $Leftovers = @()) {
    $res = @{ Ok = $false; Message = ''; Removed = @(); Cleared = 0 }
    $key = Get-AdminLibKey $Ws
    if ($key -eq '') { $res.Message = 'There is no library key in this setup yet.'; return $res }
    $fkey = Get-SocialToken $Ws
    $api = "$script:AdminApiBase/repos/$script:AdminLibRepo"
    $frepo = $(if ($script:AdminFileRepo -ne '') { $script:AdminFileRepo } else { Get-SocialRepo $Ws })
    $fapi = "$script:AdminApiBase/repos/$frepo"
    $want = @(@($GameIds) | Where-Object { [string]$_ -ne '' })
    $gone = @()

    if ($want.Count -gt 0) {
        $lib = Invoke-AdminLibApi $key 'GET' "$api/contents/library/library.json"
        if ($lib.Status -ne 200) { $res.Message = "Could not read the library list ($($lib.Status)). Nothing was removed."; return $res }
        $lo = $lib.Body | ConvertFrom-Json
        $cur = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String(([string]$lo.content -replace '\s', ''))) | ConvertFrom-Json
        $gone = @(@($cur.games) | Where-Object { $null -ne $_ -and $want -contains [string]$_.id })
        $keep = @(@($cur.games) | Where-Object { $null -ne $_ -and $want -notcontains [string]$_.id })
        if ($gone.Count -gt 0) {
            $json = ConvertTo-AdminLibraryJson ([string]$cur.note) $keep
            $b64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($json))
            $msg = 'library: remove ' + ((@($gone | ForEach-Object { [string]$_.title })) -join ', ')
            $put = Invoke-AdminLibApi $key 'PUT' "$api/contents/library/library.json" ('{"message":' + (ConvertTo-AdminJsonString $msg) + ',"content":"' + $b64 + '","sha":"' + [string]$lo.sha + '"}')
            if ($put.Status -ne 200 -and $put.Status -ne 201) { $res.Message = "The library list could not be saved ($($put.Status)). Nothing was removed."; return $res }
        }
    }

    $problems = 0
    # their box art (only ever our own library/art/ files)
    foreach ($g in $gone) {
        $art = [string]$g.art
        if ($art -notmatch '^library/art/[A-Za-z0-9._\-]+$') { continue }
        $have = Invoke-AdminLibApi $key 'GET' "$api/contents/$art"
        if ($have.Status -ne 200) { continue }
        $body = '{"message":' + (ConvertTo-AdminJsonString ('library: remove art for ' + [string]$g.id)) + ',"sha":"' + [string](($have.Body | ConvertFrom-Json).sha) + '"}'
        $d = Invoke-AdminLibApi $key 'DELETE' "$api/contents/$art" $body
        if ($d.Status -ne 200) { $problems++ }
    }

    # their private files, any older copy of them, and the leftovers
    $names = Get-AdminLibUsedNames $gone
    $extra = @{}
    foreach ($l in @($Leftovers)) { if ($null -ne $l -and [string]$l.name -ne '') { $names[[string]$l.name] = $true; $extra[[string]$l.name] = $true } }
    $goneIds = @($gone | ForEach-Object { [string]$_.id })
    if ($names.Count -gt 0 -or $goneIds.Count -gt 0) {
        if ($fkey -eq '') { $problems++ }
        else {
            $rel = Invoke-AdminLibApi $fkey 'GET' "$fapi/releases/tags/library"
            if ($rel.Status -eq 200) {
                foreach ($a in (Get-AdminLibAssets ($rel.Body | ConvertFrom-Json))) {
                    $n = [string]$a.name
                    $hit = $names.ContainsKey($n)
                    foreach ($gi in $goneIds) { if ($n.StartsWith($gi + '__')) { $hit = $true } }
                    if (-not $hit) { continue }
                    $d = Invoke-AdminLibApi $fkey 'DELETE' "$fapi/releases/assets/$($a.id)"
                    if ($d.Status -eq 204 -or $d.Status -eq 200) { if ($extra.ContainsKey($n)) { $res.Cleared++ } }
                    else { $problems++ }
                }
            }
            elseif ($rel.Status -ne 404) { $problems++ }
        }
    }

    $res.Removed = @($gone | ForEach-Object { [string]$_.title })
    $res.Ok = ($problems -eq 0)
    $m = @()
    if ($res.Removed.Count -gt 0) { $m += ('Taken off the online library: {0}. It leaves the website and friends'' wizards within about 5 minutes (GitHub''s copy refreshes). Anyone who already downloaded it keeps their copy.' -f ($res.Removed -join ', ')) }
    if ($res.Cleared -gt 0) { $m += ('Cleared {0} leftover upload(s) that were not on the list.' -f $res.Cleared) }
    if ($problems -gt 0) { $m += 'GitHub would not delete everything. Open Remove games again to clear what is left.' }
    if ($m.Count -eq 0) { $m += 'Nothing to remove.' }
    $res.Message = ($m -join "`n`n")
    return $res
}
