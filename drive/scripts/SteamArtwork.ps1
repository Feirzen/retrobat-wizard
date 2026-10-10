<#
    SteamArtwork.ps1
    ---------------------------------------------------------------------------
    Proper artwork and trailers for the Steam shelf. FUNCTIONS ONLY -
    dot-source it.

    WHY THIS EXISTS. RetroBat scrapes from ScreenScraper, which is a retro
    games database and is excellent at Wind Waker and hopeless at a party game
    that came out last year. Half the Steam shelf came back with nothing.

    WHERE IT GETS IT INSTEAD. From Steam, which obviously has perfect artwork
    for every game it sells, in two places:

      1. STEAM'S OWN CACHE ON THIS COMPUTER, in appcache\librarycache. If the
         game has ever been looked at in the Steam library, the pictures are
         already sitting on the disk and nothing needs downloading at all.
      2. STEAM'S PUBLIC ARTWORK ADDRESSES, which are the same predictable
         shape for every game: the app number, then the file name. No account,
         no key, no scraping of web pages.

    The trailer and the written description come from Steam's own store
    information service, which answers with the same facts the store page
    shows.

    WHAT LANDS WHERE. RetroBat's naming, so EmulationStation and the shortcut
    maker both pick them up with no further work:

        logo.png            ->  images\<game>-marquee.png    the logo
        library_600x900.jpg ->  images\<game>-thumb.jpg      tall box art
        header.jpg          ->  images\<game>-image.jpg      the wide banner
        library_hero.jpg    ->  images\<game>-fanart.jpg     the backdrop
        the trailer         ->  videos\<game>-video.mp4

    IT NEVER OVERWRITES BY ACCIDENT. A file that is already there is left
    alone unless -Force is passed, so running it again after buying two more
    games only fetches those two. gamelist.xml is copied to the archive before
    it is rewritten, and no file on this drive is ever deleted.

    RULES HONOURED HERE:
      - no drive letters; everything derives from -Root
      - Windows PowerShell 5.1 only
      - pure ASCII, no byte-order mark
      - no function throws; failures come back as $false or an empty result
#>

Set-StrictMode -Off

# Windows PowerShell 5.1 still defaults to an ancient TLS version that every
# modern site now refuses. Without this line every single download fails with
# a baffling "connection was closed" and nothing explains why.
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
}
catch { }

# What to fetch, in RetroBat's language.
#   SteamName  the file as Steam calls it
#   Suffix     what RetroBat wants it called
#   Tag        the gamelist.xml element it belongs in
# Names is every name Steam has used for that picture. The banner is called
# header.jpg in the old layout and library_header.jpg in the new one, and a
# drive holding games from both eras meets both. The first name is the one
# asked for on the web; all of them are looked for in the cache.
$script:SaWanted = @(
    @{ Names = @('logo.png');                          Suffix = '-marquee.png'; Tag = 'marquee' }
    @{ Names = @('library_600x900.jpg');               Suffix = '-thumb.jpg';   Tag = 'thumbnail' }
    @{ Names = @('header.jpg', 'library_header.jpg');  Suffix = '-image.jpg';   Tag = 'image' }
    @{ Names = @('library_hero.jpg');                  Suffix = '-fanart.jpg';  Tag = 'fanart' }
)

# WHERE STEAM KEEPS THE PICTURES, and why there is more than one answer.
#
# The old address worked for every game for years. Newer titles have been
# moved to a second one, which is why a game from 2025 came back with nothing
# while a game from 2011 came back complete. Both are tried, in order, and the
# first that answers wins. Adding a third later costs one line.
$script:SaCdnBases = @(
    'https://cdn.cloudflare.steamstatic.com/steam/apps/{0}/{1}'
    'https://shared.cloudflare.steamstatic.com/store_item_assets/steam/apps/{0}/{1}'
)
$script:SaStoreApi = 'https://store.steampowered.com/api/appdetails?appids={0}&l=english'

# STEAM'S OWN LIST OF A GAME'S ARTWORK (added 2026-09-25). Newer games keep
# their pictures under a hash-named folder, e.g.
#   store_item_assets/steam/apps/<appid>/<long hash>/logo.png
# so a guessed address without the hash comes back "not found" - which is
# why Fireboy & Watergirl had no logo. Steam's store service hands out the
# real addresses, hash and all, with no account or key.
$script:SaAssetApi  = 'https://api.steampowered.com/IStoreBrowseService/GetItems/v1/?input_json='
$script:SaAssetBase = 'https://shared.akamai.steamstatic.com/store_item_assets/'
# Our picture tag -> the names Steam's asset list uses for it, best first.
$script:SaAssetKeys = @{
    marquee   = @('library_logo')
    thumbnail = @('library_capsule')
    image     = @('header', 'main_capsule')
    fanart    = @('library_hero')
}

# ---------------------------------------------------------------------------

# Steam's picture cache for one game on this computer, or '' when there is
# none.
#
# STEAM HAS CHANGED THIS LAYOUT AT LEAST TWICE, which is the whole reason a
# game from 2025 came back blank while a game from 2011 came back complete.
# Confirmed by looking at a real cache on 2026-09-21:
#
#   oldest   librarycache\<appid>_header.jpg
#   older    librarycache\<appid>\header.jpg
#   current  librarycache\<appid>\<long hash>\library_header.jpg
#
# The current one buries each picture in its own hash-named folder AND
# renamed the banner. So this does not try to predict the shape any more: it
# looks in the obvious places, then simply searches the whole folder for a
# file by any of the names that picture is known by. A fourth layout would
# cost nothing.
function Get-SaCachedImage {
    param([string]$SteamRoot, [string]$AppId, [string[]]$Names)
    try {
        if ([string]::IsNullOrWhiteSpace($SteamRoot)) { return '' }
        $cache = Join-Path $SteamRoot 'appcache\librarycache'
        if (-not (Test-Path -LiteralPath $cache)) { return '' }

        $appDir = Join-Path $cache $AppId

        foreach ($n in $Names) {
            # A folder per game, pictures directly inside it.
            $p = Join-Path $appDir $n
            if (Test-Path -LiteralPath $p) { return $p }

            # Everything flat, named <appid>_<file>.
            $p2 = Join-Path $cache ($AppId + '_' + $n)
            if (Test-Path -LiteralPath $p2) { return $p2 }
        }

        # A folder per game, each picture inside its own hash-named folder.
        # Searched by exact file name, so library_hero_blur.jpg is never
        # mistaken for library_hero.jpg.
        if (Test-Path -LiteralPath $appDir) {
            foreach ($n in $Names) {
                $hit = @(Get-ChildItem -LiteralPath $appDir -Filter $n -File -Recurse -ErrorAction SilentlyContinue |
                         Where-Object { $_.Name -ieq $n } |
                         Sort-Object Length -Descending)
                if ($hit.Count -gt 0) { return $hit[0].FullName }
            }
        }
    }
    catch { }
    return ''
}

function Get-SaDownload {
    param([string]$Url, [string]$DestPath)
    try {
        $dir = Split-Path $DestPath -Parent
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

        # To a temporary name first. A half-written picture left behind by a
        # dropped connection would look like a finished one to every later run.
        $tmp = $DestPath + '.part'
        Invoke-WebRequest -Uri $Url -OutFile $tmp -UseBasicParsing -TimeoutSec 40 -ErrorAction Stop | Out-Null

        if (-not (Test-Path -LiteralPath $tmp)) { return $false }
        if ((Get-Item -LiteralPath $tmp).Length -lt 100) {
            Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
            return $false
        }

        Move-Item -LiteralPath $tmp -Destination $DestPath -Force
        return $true
    }
    catch {
        try { if (Test-Path -LiteralPath ($DestPath + '.part')) { Remove-Item -LiteralPath ($DestPath + '.part') -Force } } catch { }
        return $false
    }
}

# The real address of every picture Steam lists for one game, as a table of
# our tag -> list of addresses. Empty when the service cannot be reached.
$script:SaAssetError = ''
function Get-SaAssetUrls {
    param([string]$AppId)
    $out = @{}
    $script:SaAssetError = ''
    try {
        $req = '{"ids":[{"appid":' + [int]$AppId + '}],"context":{"language":"english","country_code":"US"},"data_request":{"include_assets":true}}'
        $url = $script:SaAssetApi + [uri]::EscapeDataString($req)
        $r = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 30 -ErrorAction Stop
        $j = ConvertFrom-SaJson (Get-SaText $r)
        if ($null -eq $j) { $script:SaAssetError = ('Steam''s artwork list could not be read: ' + $script:SaJsonError); return $out }
        $item = @($j.response.store_items)[0]
        if ($null -eq $item -or $null -eq $item.assets) { $script:SaAssetError = 'Steam''s artwork list has nothing for this game'; return $out }
        $a = $item.assets
        $fmt = [string]$a.asset_url_format
        if ($fmt -eq '') { return $out }
        foreach ($tag in $script:SaAssetKeys.Keys) {
            $list = @()
            foreach ($k in $script:SaAssetKeys[$tag]) {
                $file = [string]$a.$k
                if ($file -eq '') { continue }
                $list += ($script:SaAssetBase + $fmt.Replace('${FILENAME}', $file))
            }
            if ($list.Count -gt 0) { $out[$tag] = $list }
        }
    }
    catch { $script:SaAssetError = ('Steam''s artwork list could not be reached: ' + $_.Exception.Message) }
    return $out
}

# A trailer that Steam only offers as a STREAM, saved as an ordinary .mp4.
#
# WHY THIS EXISTS (2026-09-25). Steam stopped giving plain .mp4 addresses
# for trailers. The store now lists each one only as a streaming playlist
# (hls_h264 / dash_h264), the kind a web page plays in chunks. The old code
# looked only for .mp4 and .webm, found none, and reported "the store lists
# no trailer" for games that obviously have one.
#
# ffmpeg (already on the drive for the video volume fix) can fetch a stream
# and join it into a normal file. For HLS the playlist is read first and
# the version nearest 480p picked, so a two-minute trailer is a few MB
# rather than a 1080p monster; -c copy means nothing is re-encoded, so it is
# as fast as the download. If the playlist cannot be read, ffmpeg is simply
# given the whole thing and chooses for itself.
function Get-SaStreamVideo {
    param([string]$Ffmpeg, [string]$Url, [string]$DestPath)
    $tmp = $DestPath + '.part.mp4'
    try {
        if (-not (Test-Path -LiteralPath $Ffmpeg)) { return $false }
        $dir = Split-Path $DestPath -Parent
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

        $videoIn = $Url
        $audioIn = ''
        if ($Url -match '\.m3u8') {
            try {
                $r = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 30 -ErrorAction Stop
                $txt = $r.Content
                if ($txt -is [byte[]]) { $txt = [System.Text.Encoding]::UTF8.GetString($txt) }
                $lines = @($txt -split "`r?`n")
                $base = New-Object System.Uri($Url)
                $bestUri = ''; $bestScore = [int]::MaxValue; $bestAudio = ''
                $audioGroups = @{}
                for ($i = 0; $i -lt $lines.Count; $i++) {
                    $ln = $lines[$i].Trim()
                    if ($ln.StartsWith('#EXT-X-MEDIA:') -and $ln -match 'TYPE=AUDIO' -and $ln -match 'GROUP-ID="([^"]+)"' ) {
                        $g = $Matches[1]
                        if ($ln -match 'URI="([^"]+)"') {
                            $u = (New-Object System.Uri($base, $Matches[1])).AbsoluteUri
                            if (-not $audioGroups.ContainsKey($g) -or $ln -match 'DEFAULT=YES') { $audioGroups[$g] = $u }
                        }
                    }
                    if ($ln.StartsWith('#EXT-X-STREAM-INF:')) {
                        $h = 0
                        if ($ln -match 'RESOLUTION=\d+x(\d+)') { $h = [int]$Matches[1] }
                        $grp = ''
                        if ($ln -match 'AUDIO="([^"]+)"') { $grp = $Matches[1] }
                        $next = ''
                        for ($k = $i + 1; $k -lt $lines.Count; $k++) {
                            $c = $lines[$k].Trim()
                            if ($c -ne '' -and -not $c.StartsWith('#')) { $next = $c; break }
                        }
                        if ($next -eq '') { continue }
                        $score = 100000
                        if ($h -gt 0) { $score = [Math]::Abs($h - 480); if ($h -lt 360) { $score += 1000 } }
                        if ($score -lt $bestScore) {
                            $bestScore = $score
                            $bestUri = (New-Object System.Uri($base, $next)).AbsoluteUri
                            $bestAudio = $grp
                        }
                    }
                }
                if ($bestUri -ne '') {
                    $videoIn = $bestUri
                    if ($bestAudio -ne '' -and $audioGroups.ContainsKey($bestAudio)) { $audioIn = $audioGroups[$bestAudio] }
                }
            }
            catch { $videoIn = $Url; $audioIn = '' }
        }

        $a = @('-y', '-loglevel', 'error', '-i', ('"' + $videoIn + '"'))
        if ($audioIn -ne '') {
            $a += @('-i', ('"' + $audioIn + '"'), '-map', '0:v:0', '-map', '1:a:0')
        }
        else {
            $a += @('-map', '0:v:0', '-map', '0:a:0?')
        }
        $a += @('-c', 'copy', '-movflags', '+faststart', '-f', 'mp4', ('"' + $tmp + '"'))

        $p = Start-Process -FilePath $Ffmpeg -ArgumentList ($a -join ' ') -WindowStyle Hidden -PassThru -ErrorAction Stop
        if (-not $p.WaitForExit(300000)) { try { $p.Kill() } catch { }; throw 'ffmpeg took more than five minutes' }

        if ((Test-Path -LiteralPath $tmp) -and (Get-Item -LiteralPath $tmp).Length -gt 100KB) {
            Move-Item -LiteralPath $tmp -Destination $DestPath -Force
            return $true
        }
    }
    catch { }
    try { if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force } } catch { }
    return $false
}

# Read Steam's JSON answers. (2026-09-25)
#
# WHY NOT ConvertFrom-Json. Windows PowerShell 5.1's ConvertFrom-Json refuses
# any answer holding two names that differ only in capitals, and gives up on
# very long ones. Steam's store pages for older, bigger games trip it, which
# is why eight games came back "no store information" while three newer ones
# worked. .NET's own JavaScriptSerializer has neither limit and hands back
# dictionaries, which PowerShell reads with the same $x.name dots, so nothing
# else in this file had to change. ConvertFrom-Json stays as the fallback.
# The body of a web answer as text, always read as UTF-8. Windows PowerShell
# guesses the text encoding from the reply's headers and can guess wrong,
# which mangles names like "Pokemon" with an accent or a trademark sign.
function Get-SaText {
    param($Response)
    try { return [System.Text.Encoding]::UTF8.GetString($Response.RawContentStream.ToArray()) }
    catch { return [string]$Response.Content }
}

$script:SaJsonError = ''
$script:SaJsonParser = ''
function ConvertFrom-SaJson {
    param([string]$Text)
    $script:SaJsonError = ''
    try {
        Add-Type -AssemblyName System.Web.Extensions -ErrorAction Stop
        $ser = New-Object System.Web.Script.Serialization.JavaScriptSerializer
        $ser.MaxJsonLength = [int]::MaxValue
        $ser.RecursionLimit = 256
        $obj = $ser.DeserializeObject($Text)
        $script:SaJsonParser = 'JavaScriptSerializer'
        if ($null -eq $obj) { $script:SaJsonError = 'the answer was empty (the word null)'; return $null }
        # The comma stops PowerShell unrolling the dictionary into its entries.
        return ,$obj
    }
    catch { $script:SaJsonError = $_.Exception.Message }
    try { $script:SaJsonParser = 'ConvertFrom-Json'; return ($Text | ConvertFrom-Json -ErrorAction Stop) }
    catch { $script:SaJsonError = $_.Exception.Message; return $null }
}

# What Steam's store says about one game: description, genre, date, makers,
# and the address of its trailer. Returns $null when it cannot be reached,
# which is not an error worth stopping for - the pictures are the main prize.
# When the store's answer cannot be used, keep a copy of exactly what came
# back, so the reason can be read rather than guessed. Small text files in
# _ClaudeWorkspace\SteamArtworkDebug, one per game, replaced each run.
# (2026-09-25: eight games failed on Windows for a reason that could not be
# reproduced anywhere else.)
function Save-SaStoreDebug {
    param([string]$AppId, [string]$Text, $Response, $Parsed)
    try {
        $dir = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) '_ClaudeWorkspace\SteamArtworkDebug'
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        $info = @()
        $info += ('appid: ' + $AppId)
        $info += ('status: ' + [string]$Response.StatusCode)
        try { $info += ('content-type: ' + [string]$Response.Headers['Content-Type']) } catch { }
        $info += ('text length: ' + $Text.Length)
        $info += ('parser: ' + $script:SaJsonParser)
        $info += ('parser error: ' + $script:SaJsonError)
        $info += ('parsed type: ' + $(if ($null -eq $Parsed) { 'null' } else { $Parsed.GetType().FullName }))
        try { $info += ('top-level keys: ' + ((@($Parsed.Keys) | ForEach-Object { [string]$_ }) -join ', ')) } catch { }
        $info += ''
        $info += '--- first 3000 characters of the answer ---'
        $info += $Text.Substring(0, [Math]::Min(3000, $Text.Length))
        [System.IO.File]::WriteAllLines((Join-Path $dir ($AppId + '.txt')), $info)
    }
    catch { }
}

$script:SaStoreError = ''
function Get-SaStoreInfo {
    param([string]$AppId)
    $script:SaStoreError = ''
    try {
        $url = ($script:SaStoreApi -f $AppId)
        # One retry: the store sometimes refuses a quick run of requests.
        $r = $null
        for ($try = 1; $try -le 2 -and $null -eq $r; $try++) {
            try { $r = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 30 -ErrorAction Stop }
            catch { $script:SaStoreError = ('could not reach the store: ' + $_.Exception.Message); if ($try -lt 2) { Start-Sleep -Seconds 3 } }
        }
        if ($null -eq $r) { return $null }
        $text = Get-SaText $r
        $j = ConvertFrom-SaJson $text
        if ($null -eq $j) {
            $script:SaStoreError = ('the store answered but it could not be read: ' + $script:SaJsonError)
            Save-SaStoreDebug -AppId $AppId -Text $text -Response $r -Parsed $j
            return $null
        }
        $node = $null
        if ($j -is [System.Collections.IDictionary]) { $node = $j[[string]$AppId] }
        if ($null -eq $node) { $node = $j.([string]$AppId) }
        # STEAM'S OWN QUIRK (found 2026-09-25 from the saved answers). For a
        # game that has DLC, the store files its answer under the number of
        # the game's LAST DLC instead of the game's own: asking for Golf With
        # Your Friends (431240) came back labelled 2456991. The contents are
        # the right game. So when the label does not match, take the entry
        # whose steam_appid is the game asked for, or the only entry there is.
        if ($null -eq $node) {
            $entries = @()
            if ($j -is [System.Collections.IDictionary]) { foreach ($k in @($j.Keys)) { $entries += ,$j[$k] } }
            else { foreach ($pp in @($j.PSObject.Properties)) { $entries += ,$pp.Value } }
            foreach ($cand in $entries) {
                try { if ([string]$cand.data.steam_appid -eq [string]$AppId) { $node = $cand; break } } catch { }
            }
            if ($null -eq $node -and $entries.Count -eq 1) { $node = $entries[0] }
        }
        $ok = $false
        if ($node -is [System.Collections.IDictionary]) { $ok = [bool]$node['success'] } elseif ($null -ne $node) { $ok = [bool]$node.success }
        if ($null -eq $node -or -not $ok) {
            $script:SaStoreError = 'the store''s answer did not contain this game - details saved in _ClaudeWorkspace\SteamArtworkDebug'
            Save-SaStoreDebug -AppId $AppId -Text $text -Response $r -Parsed $j
            return $null
        }
        $d = $node.data

        # EVERY trailer, not just the first. Several games came back with no
        # video at all because their first entry had no usable address, and
        # stopping there threw away two or three perfectly good ones sitting
        # behind it. They are tried in order until one downloads.
        #
        # The store still hands these out as http addresses; forcing https
        # avoids a redirect that Windows PowerShell handles inconsistently.
        $videos = @()
        try {
            foreach ($m in @($d.movies)) {
                foreach ($pick in @($m.mp4.'480', $m.mp4.max, $m.webm.'480', $m.webm.max)) {
                    $u = [string]$pick
                    if ($u -eq '') { continue }
                    # The address AS GIVEN first, then the secure version of
                    # it. Forcing https on its own was a guess and could just
                    # as easily break a host that only answers on http, so
                    # both are tried rather than one being assumed right.
                    if ($videos -notcontains $u) { $videos += $u }
                    if ($u.StartsWith('http://')) {
                        $alt = 'https://' + $u.Substring(7)
                        if ($videos -notcontains $alt) { $videos += $alt }
                    }
                }
            }
        }
        catch { }

        # The streaming versions, which is all most games offer now. See
        # Get-SaStreamVideo.
        $streams = @()
        try {
            foreach ($m in @($d.movies)) {
                foreach ($pick in @($m.hls_h264, $m.dash_h264)) {
                    $u = [string]$pick
                    if ($u -ne '' -and $streams -notcontains $u) { $streams += $u }
                }
            }
        }
        catch { }

        $genre = ''
        try { if ($d.genres) { $genre = (@($d.genres) | ForEach-Object { [string]$_.description }) -join ', ' } } catch { }

        $devs = ''
        try { if ($d.developers) { $devs = (@($d.developers)) -join ', ' } } catch { }

        $pubs = ''
        try { if ($d.publishers) { $pubs = (@($d.publishers)) -join ', ' } } catch { }

        $released = ''
        try { if ($d.release_date -and $d.release_date.date) { $released = [string]$d.release_date.date } } catch { }

        $desc = ''
        try {
            $desc = [string]$d.short_description
            # The store writes these in HTML. A game list wants plain words.
            $desc = $desc -replace '<[^>]+>', ''
            $desc = $desc.Replace('&amp;', '&').Replace('&quot;', '"').Replace('&#39;', "'").Replace('&lt;', '<').Replace('&gt;', '>')
            $desc = $desc.Trim()
        }
        catch { }

        # The store tells us outright where its own banner lives, which beats
        # guessing at an address every time. A screenshot is kept as a last
        # resort so a game with no banner at all still gets a picture rather
        # than a blank tile.
        $header = ''
        try { if ($d.header_image) { $header = [string]$d.header_image } } catch { }

        $shot = ''
        try {
            if ($d.screenshots -and @($d.screenshots).Count -gt 0) {
                $shot = [string](@($d.screenshots)[0].path_full)
            }
        }
        catch { }

        # What kind of game it is, for the couch-multiplayer filter in Steam
        # setup (2026-09-25). Category numbers are Steam's own.
        $type = ''
        try { $type = ([string]$d.type).ToLower() } catch { }
        $cats = @()
        try { foreach ($c in @($d.categories)) { if ($null -ne $c -and [string]$c.id -match '^\d+$') { $cats += [int]$c.id } } } catch { }
        $ctrl = 'none'
        try { if ([string]$d.controller_support -ne '') { $ctrl = ([string]$d.controller_support).ToLower() } } catch { }

        return [pscustomobject]@{
            Type        = $type
            Categories  = $cats
            Controller  = $ctrl
            Name        = [string]$d.name
            Desc        = $desc
            Genre       = $genre
            Developer   = $devs
            Publisher   = $pubs
            Released    = $released
            VideoUrls   = $videos
            StreamUrls  = $streams
            HeaderImage = $header
            Screenshot  = $shot
        }
    }
    catch { return $null }
}

# ---------------------------------------------------------------------------
#  Fill in the game information cache (SteamEngine.ps1, machine\steam-game-
#  info.txt) for any of these games it does not know yet. One store lookup per
#  unknown game, and then never again for that game.
#
#  -Progress is an optional scriptblock called with (done, total, name) so a
#  window can say what it is doing. Returns how many were newly learned.
# ---------------------------------------------------------------------------
function Update-SaGameInfoCache {
    param([string]$Root, [object[]]$Games, [scriptblock]$Progress = $null)
    $learned = 0
    try {
        $table = Get-SteamGameInfo -Root $Root
        $todo = @($Games | Where-Object { -not $table.ContainsKey([string]$_.AppId) })
        $n = 0
        foreach ($g in $todo) {
            $n++
            if ($null -ne $Progress) { try { & $Progress $n $todo.Count ([string]$g.Name) } catch { } }
            $i = $null
            try { $i = Get-SaStoreInfo -AppId ([string]$g.AppId) } catch { }
            if ($null -eq $i) { continue }
            $table[[string]$g.AppId] = [pscustomobject]@{
                AppId      = [string]$g.AppId
                Type       = [string]$i.Type
                Couch      = (Test-SteamCouchCategories -Categories $i.Categories)
                Categories = @($i.Categories)
                Controller = [string]$i.Controller
                Name       = [string]$g.Name
            }
            $learned++
            Start-Sleep -Milliseconds 300   # be gentle with the store
        }
        if ($learned -gt 0) { [void](Set-SteamGameInfo -Root $Root -Table $table) }
    }
    catch { }
    return $learned
}

# Does this tile still lack its pictures or trailer? Used to decide whether
# to offer fetching artwork at the end of Steam setup. The logo does not
# count on its own, because some games simply have none on Steam.
function Test-SaArtworkMissing {
    param([string]$Root, [string]$TileName)
    try {
        $romsDir = Join-Path $Root 'roms\steam'
        foreach ($f in @(('images\' + $TileName + '-thumb.jpg'), ('images\' + $TileName + '-image.jpg'), ('videos\' + $TileName + '-video.mp4'))) {
            if (-not (Test-Path -LiteralPath (Join-Path $romsDir $f))) { return $true }
        }
    }
    catch { }
    return $false
}

# ---------------------------------------------------------------------------
#  The whole job for ONE game.
#  Returns an object: Name, Got (list of tags), Skipped, Failed, Info.
# ---------------------------------------------------------------------------
function Get-SaGameArtwork {
    param(
        [string]$Root,
        [string]$SteamRoot,
        [string]$AppId,
        [string]$TileName,
        [switch]$Force,
        [switch]$NoVideo
    )

    $got     = @()
    $skipped = @()
    $failed  = @()
    $notes   = @()

    $romsDir   = Join-Path $Root 'roms\steam'
    $imagesDir = Join-Path $romsDir 'images'
    $videosDir = Join-Path $romsDir 'videos'

    $info = $null
    try { $info = Get-SaStoreInfo -AppId $AppId } catch { $script:SaStoreError = $_.Exception.Message }
    if ($null -eq $info -and $script:SaStoreError -ne '') { $notes += ('store: ' + $script:SaStoreError) }

    $assets = @{}
    try { $assets = Get-SaAssetUrls -AppId $AppId } catch { }

    foreach ($want in $script:SaWanted) {
        try {
            $dest = Join-Path $imagesDir ($TileName + $want.Suffix)

            if ((Test-Path -LiteralPath $dest) -and -not $Force) {
                $skipped += $want.Tag
                continue
            }

            # Steam's own cache first. Free, instant, and works with no
            # internet at all.
            $cached = Get-SaCachedImage -SteamRoot $SteamRoot -AppId $AppId -Names $want.Names
            if ($cached -ne '') {
                if (-not (Test-Path -LiteralPath $imagesDir)) { New-Item -ItemType Directory -Path $imagesDir -Force | Out-Null }
                Copy-Item -LiteralPath $cached -Destination $dest -Force
                $got += $want.Tag
                continue
            }

            # Every address worth trying for this one picture, best first.
            $urls = @()
            if ($assets.ContainsKey($want.Tag)) { $urls += @($assets[$want.Tag]) }
            if ($want.Tag -eq 'image' -and $null -ne $info -and [string]$info.HeaderImage -ne '') {
                $urls += [string]$info.HeaderImage
            }
            foreach ($n in $want.Names) {
                foreach ($base in $script:SaCdnBases) { $urls += ($base -f $AppId, $n) }
            }
            if ($want.Tag -eq 'image' -and $null -ne $info -and [string]$info.Screenshot -ne '') {
                $urls += [string]$info.Screenshot
            }

            $done = $false
            foreach ($u in $urls) {
                if (Get-SaDownload -Url $u -DestPath $dest) { $done = $true; break }
            }

            if ($done) {
                $got += $want.Tag
            }
            else {
                # Name the addresses that were tried. Without this a miss is
                # just a shrug, and somebody has to come back and ask.
                $failed += $want.Tag
                $why = ('{0}: nothing at any of {1} address(es), and not in Steam''s cache' -f $want.Tag, @($urls).Count)
                if ($script:SaAssetError -ne '') { $why += ('; ' + $script:SaAssetError) }
                elseif (-not $assets.ContainsKey($want.Tag)) { $why += '; Steam lists no picture of this kind for this game' }
                $notes += $why
            }
        }
        catch { $failed += $want.Tag }
    }

    $haveVideo = ($null -ne $info -and (@($info.VideoUrls).Count + @($info.StreamUrls).Count) -gt 0)
    if (-not $NoVideo -and $null -ne $info -and -not $haveVideo) {
        $notes += 'video: the store lists no trailer for this game'
    }
    if (-not $NoVideo -and $haveVideo) {
        try {
            $vdest = Join-Path $videosDir ($TileName + '-video.mp4')
            if ((Test-Path -LiteralPath $vdest) -and -not $Force) {
                $skipped += 'video'
            }
            else {
                $vdone = $false
                foreach ($vu in @($info.VideoUrls)) {
                    if (Get-SaDownload -Url $vu -DestPath $vdest) { $vdone = $true; break }
                }
                if (-not $vdone -and @($info.StreamUrls).Count -gt 0) {
                    $ff = Join-Path $Root '_ClaudeWorkspace\tools\ffmpeg.exe'
                    if (-not (Test-Path -LiteralPath $ff)) {
                        $notes += 'video: the trailer is a stream and needs _ClaudeWorkspace\tools\ffmpeg.exe, which is missing'
                    }
                    else {
                        foreach ($su in @($info.StreamUrls)) {
                            if (Get-SaStreamVideo -Ffmpeg $ff -Url $su -DestPath $vdest) { $vdone = $true; break }
                        }
                    }
                }
                if ($vdone) {
                    $got += 'video'
                }
                else {
                    $failed += 'video'
                    $notes += ('video: {0} trailer(s) offered by the store, none downloaded' -f (@($info.VideoUrls).Count + @($info.StreamUrls).Count))
                }
            }
        }
        catch { $failed += 'video' }
    }

    return [pscustomobject]@{
        Name    = $TileName
        Got     = $got
        Skipped = $skipped
        Failed  = $failed
        Notes   = $notes
        Info    = $info
    }
}

# ---------------------------------------------------------------------------
#  gamelist.xml
#
#  EmulationStation reads this, not the images folder, so a picture nobody
#  told it about might as well not be there. Each game gets its <path> looked
#  up and the fields filled in beneath it.
#
#  IT ADDS AND UPDATES, IT DOES NOT REPLACE. A name or description somebody
#  typed by hand stays unless -Force is passed, because a person's own words
#  beating an automatic lookup is the rule this whole drive runs on.
# ---------------------------------------------------------------------------
function Update-SaGameList {
    param(
        [string]$Root,
        [object[]]$Results,
        [switch]$Force
    )

    $summary = [pscustomobject]@{ Ok = $false; Updated = 0; Message = '' }

    try {
        $romsDir = Join-Path $Root 'roms\steam'
        if (-not (Test-Path -LiteralPath $romsDir)) {
            $summary.Message = 'There is no Steam shelf folder yet.'
            return $summary
        }

        $listPath = Join-Path $romsDir 'gamelist.xml'

        $xml = New-Object System.Xml.XmlDocument
        if (Test-Path -LiteralPath $listPath) {
            try { $xml.Load($listPath) } catch { $xml = New-Object System.Xml.XmlDocument }
        }

        # NOT called $root. PowerShell variable names ignore capitals, so
        # $root and the $Root parameter holding the drive path are the SAME
        # variable - naming this one $root silently replaced the drive path
        # with an XML node and every path built afterwards came out as
        # "System.Xml.XmlElement\roms\steam\...". Caught by a test on
        # 2026-09-19 and worth never repeating.
        $listRoot = $xml.SelectSingleNode('/gameList')
        if ($null -eq $listRoot) {
            $xml.RemoveAll()
            [void]$xml.AppendChild($xml.CreateXmlDeclaration('1.0', $null, $null))
            $listRoot = $xml.CreateElement('gameList')
            [void]$xml.AppendChild($listRoot)
        }

        # Back it up before writing, every time. Cheap, and it is the file
        # holding every scrape this shelf has ever had.
        if (Test-Path -LiteralPath $listPath) {
            try {
                $bdir = Join-Path $Root ('_ClaudeWorkspace\archive\steam-gamelist_' + (Get-Date -Format 'yyyy-MM-dd_HHmmss'))
                New-Item -ItemType Directory -Path $bdir -Force | Out-Null
                Copy-Item -LiteralPath $listPath -Destination (Join-Path $bdir 'gamelist.xml') -Force
            }
            catch { }
        }

        foreach ($r in $Results) {
            try {
                $relPath = './' + $r.Name + '.url'

                $game = $null
                foreach ($g in @($listRoot.SelectNodes('game'))) {
                    $p = [string]$g.SelectSingleNode('path').InnerText
                    if ($p -eq $relPath -or $p -eq ($r.Name + '.url')) { $game = $g; break }
                }

                if ($null -eq $game) {
                    $game = $xml.CreateElement('game')
                    $pn = $xml.CreateElement('path')
                    $pn.InnerText = $relPath
                    [void]$game.AppendChild($pn)
                    [void]$listRoot.AppendChild($game)
                }

                # --- the pictures, which are always ours to set -------------
                $files = @(
                    @('image',     ($r.Name + '-image.jpg')),
                    @('marquee',   ($r.Name + '-marquee.png')),
                    @('thumbnail', ($r.Name + '-thumb.jpg')),
                    @('fanart',    ($r.Name + '-fanart.jpg'))
                )
                foreach ($f in $files) {
                    $full = Join-Path (Join-Path $romsDir 'images') $f[1]
                    if (-not (Test-Path -LiteralPath $full)) { continue }
                    Set-SaField -Xml $xml -Game $game -Tag $f[0] -Value ('./images/' + $f[1]) -Always
                }

                $vfull = Join-Path (Join-Path $romsDir 'videos') ($r.Name + '-video.mp4')
                if (Test-Path -LiteralPath $vfull) {
                    Set-SaField -Xml $xml -Game $game -Tag 'video' -Value ('./videos/' + $r.Name + '-video.mp4') -Always
                }

                # --- the words, which a person may have written themselves --
                if ($null -ne $r.Info) {
                    Set-SaField -Xml $xml -Game $game -Tag 'name'      -Value $r.Name             -Always:$Force
                    Set-SaField -Xml $xml -Game $game -Tag 'desc'      -Value $r.Info.Desc        -Always:$Force
                    Set-SaField -Xml $xml -Game $game -Tag 'genre'     -Value $r.Info.Genre       -Always:$Force
                    Set-SaField -Xml $xml -Game $game -Tag 'developer' -Value $r.Info.Developer   -Always:$Force
                    Set-SaField -Xml $xml -Game $game -Tag 'publisher' -Value $r.Info.Publisher   -Always:$Force
                    Set-SaField -Xml $xml -Game $game -Tag 'releasedate' -Value (ConvertTo-SaDate $r.Info.Released) -Always:$Force
                }

                $summary.Updated++
            }
            catch { continue }
        }

        $set = New-Object System.Xml.XmlWriterSettings
        $set.Indent = $true
        $set.IndentChars = "`t"
        $set.Encoding = New-Object System.Text.UTF8Encoding($false)
        $w = [System.Xml.XmlWriter]::Create($listPath, $set)
        try { $xml.Save($w) } finally { $w.Close() }

        $summary.Ok = $true
        $summary.Message = ('{0} game(s) written into the Steam shelf''s game list.' -f $summary.Updated)
        return $summary
    }
    catch {
        $summary.Message = 'Could not update the game list: ' + $_.Exception.Message
        return $summary
    }
}

# Set one field. Without -Always an existing value is left alone, because a
# name or description somebody typed by hand always beats a lookup.
function Set-SaField {
    param($Xml, $Game, [string]$Tag, [string]$Value, [switch]$Always)
    try {
        if ([string]::IsNullOrWhiteSpace($Value)) { return }
        $node = $Game.SelectSingleNode($Tag)
        if ($null -ne $node) {
            if (-not $Always -and [string]$node.InnerText -ne '') { return }
            $node.InnerText = $Value
            return
        }
        $node = $Xml.CreateElement($Tag)
        $node.InnerText = $Value
        [void]$Game.AppendChild($node)
    }
    catch { }
}

# EmulationStation wants 20260919T000000. Steam writes "19 Sep, 2026".
# An unreadable date is left out rather than guessed at.
function ConvertTo-SaDate {
    param([string]$Text)
    try {
        if ([string]::IsNullOrWhiteSpace($Text)) { return '' }
        $d = [datetime]::MinValue
        if ([datetime]::TryParse($Text, [ref]$d)) { return $d.ToString('yyyyMMddT000000') }
    }
    catch { }
    return ''
}
