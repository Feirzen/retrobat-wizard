<#
    FlashArtwork.ps1 - names, words and pictures for the Flash shelf.

    FUNCTIONS ONLY. Dot-source it (after SteamEngine.ps1 and
    SteamArtwork.ps1, whose helpers it borrows). Used by
    Maintenance Steps\Get Flash Artwork.bat through Show-FlashArtwork.ps1.

    WHY (Steven, 2026-10-11). RetroBat's scraper knows almost no Flash games,
    so the Flash shelf showed ckau-book's blank cartridge for every game, and
    scraping again changed nothing. The list lives in
    _ClaudeWorkspace\flash-games.ini instead (one section per .swf), and this
    writes it into roms\flash\gamelist.xml and fetches the pictures:

      steam = <exact store name or app number>
          Steam's logo, tall box art, wide banner and backdrop, exactly like
          the Steam shelf: from this computer's Steam cache first (a game you
          own has usually been seen in the library, so no download at all),
          then from Steam's public addresses. A NAME is looked up in Steam's
          store search and used only on an exact match, so a wrong guess
          finds nothing rather than the wrong game.
      archive = <archive.org item name>
          The item's cover picture, used when Steam gave nothing.
      picture = <https address> [<another> ...]       (added 2026-10-13)
          An official picture straight from the web (the game's own site,
          its official account's avatar, its wiki's logo file). The first
          address that gives a real picture is used as the main picture and
          box art.
      logo = <https address> [...]
          The same, for the logo (marquee).

    THE BROWSER SHELF TOO (2026-10-13). The same job runs for the browser
    and online games on RetroBat's Windows shelf, from
    _ClaudeWorkspace\browser-games.ini into roms\windows. Pictures under
    10 KB there were early hand-made stand-ins (Steven: never make artwork,
    always use the real thing), so they are moved to archive\ and replaced
    as soon as a real one is found.

    WHAT LANDS WHERE (RetroBat's own names, so the theme picks them up):
        images\<file>-image.<jpg|png>     the main picture
        images\<file>-thumb.<jpg|png>     box art
        images\<file>-marquee.png         the logo
        images\<file>-fanart.jpg          the backdrop

    NEVER OVERWRITES BY ACCIDENT. A picture already there is kept, and a
    name or description somebody typed in RetroBat is kept, unless -Force.
    gamelist.xml is copied into archive\ before every write. Nothing is
    deleted. No function throws.

    ASCII ONLY, Windows PowerShell 5.1. Every root is a parameter. Test hook:
        $script:FaFetchOverride   { param($Url, $OutFile) ... }   (downloads)
        $script:FaTextOverride    { param($Url) -> text }           (lookups)
#>

$script:FaFetchOverride = $null
$script:FaTextOverride  = $null
$script:FaSearchApi = 'https://store.steampowered.com/api/storesearch/?term={0}&l=english&cc=US'
$script:FaArchiveImg = 'https://archive.org/services/img/{0}'

# --- the list ----------------------------------------------------------------
# One object per section of flash-games.ini, in file order.
function Read-FlashGames([string]$Path) {
    $out = New-Object System.Collections.ArrayList
    if (-not (Test-Path -LiteralPath $Path)) { return @() }
    $cur = $null
    foreach ($line in [System.IO.File]::ReadAllLines($Path)) {
        $t = $line.Trim()
        if ($t -eq '' -or $t.StartsWith(';') -or $t.StartsWith('#')) { continue }
        if ($t -match '^\[(.+)\]$') {
            $file = $Matches[1].Trim()
            # A file name, never a path: anything else is ignored.
            if ($file -match '[\\/:*?"<>|]' -or $file.StartsWith('.')) { $cur = $null; continue }
            $cur = [pscustomobject]@{ File = $file; Name = ''; Players = ''; Genre = ''; Developer = ''; Year = ''; Desc = ''; Steam = ''; Archive = ''; Picture = @(); Logo = @() }
            [void]$out.Add($cur)
            continue
        }
        if ($null -eq $cur) { continue }
        $eq = $t.IndexOf('=')
        if ($eq -lt 1) { continue }
        $k = $t.Substring(0, $eq).Trim().ToLower()
        $v = $t.Substring($eq + 1).Trim()
        switch ($k) {
            'name'      { $cur.Name = $v }
            'players'   { $cur.Players = $v }
            'genre'     { $cur.Genre = $v }
            'developer' { $cur.Developer = $v }
            'year'      { if ($v -match '^\d{4}$') { $cur.Year = $v } }
            'desc'      { $cur.Desc = $v }
            'steam'     { $cur.Steam = $v }
            'archive'   { if ($v -match '^[A-Za-z0-9._\-]{1,120}$') { $cur.Archive = $v } }
            'picture'   { $cur.Picture = @($v -split '\s+' | Where-Object { $_ -match '^https://[^\s"]+$' }) }
            'logo'      { $cur.Logo = @($v -split '\s+' | Where-Object { $_ -match '^https://[^\s"]+$' }) }
        }
    }
    return $out.ToArray()
}

# --- the network, behind the test hooks ----------------------------------------
function Get-FaText([string]$Url) {
    if ($null -ne $script:FaTextOverride) { return [string](& $script:FaTextOverride $Url) }
    try {
        $old = $ProgressPreference; $ProgressPreference = 'SilentlyContinue'
        $r = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 30 -ErrorAction Stop
        $ProgressPreference = $old
        return (Get-SaText $r)
    }
    catch { return '' }
}

function Save-FaDownload([string]$Url, [string]$Dest) {
    if ($null -ne $script:FaFetchOverride) {
        try { & $script:FaFetchOverride $Url $Dest; return (Test-Path -LiteralPath $Dest) } catch { return $false }
    }
    $old = $ProgressPreference; $ProgressPreference = 'SilentlyContinue'
    try { return (Get-SaDownload -Url $Url -DestPath $Dest) }
    finally { $ProgressPreference = $old }
}

# PNG or JPEG, by the file's first bytes rather than by the address, because
# archive.org hands out either under the same kind of address.
function Get-FaPictureExt([string]$Path) {
    try {
        $fs = [System.IO.File]::OpenRead($Path)
        try { $b = New-Object byte[] 8; [void]$fs.Read($b, 0, 8) } finally { $fs.Close() }
        if ($b[0] -eq 0x89 -and $b[1] -eq 0x50 -and $b[2] -eq 0x4E -and $b[3] -eq 0x47) { return '.png' }
        if ($b[0] -eq 0xFF -and $b[1] -eq 0xD8) { return '.jpg' }
        if ($b[0] -eq 0x47 -and $b[1] -eq 0x49 -and $b[2] -eq 0x46) { return '.gif' }
    }
    catch { }
    return ''
}

# The picture for one slot, whichever extension it has, or ''.
function Find-FaPicture([string]$ImagesDir, [string]$Stem, [string]$Suffix) {
    foreach ($ext in @('.png', '.jpg', '.gif')) {
        $p = Join-Path $ImagesDir ($Stem + $Suffix + $ext)
        if (Test-Path -LiteralPath $p) { return $p }
    }
    return ''
}

# --- Steam --------------------------------------------------------------------
function ConvertTo-FaKey([string]$s) { return (([string]$s).ToLower() -replace '[^a-z0-9]', '') }

# An app number for a "steam =" value: a number as it is, a name only on an
# exact match in Steam's store search. '' when there is none.
function Resolve-FaSteamId([string]$Value) {
    $v = ([string]$Value).Trim()
    if ($v -eq '') { return '' }
    if ($v -match '^\d{1,9}$') { return $v }
    $txt = Get-FaText ($script:FaSearchApi -f [uri]::EscapeDataString($v))
    if ($txt -eq '') { return '' }
    $j = ConvertFrom-SaJson $txt
    if ($null -eq $j) { return '' }
    $want = ConvertTo-FaKey $v
    foreach ($it in @($j.items)) {
        if ($null -eq $it) { continue }
        if ((ConvertTo-FaKey ([string]$it.name)) -eq $want) { return [string]$it.id }
    }
    return ''
}

# Steam's four pictures for one game into images\. Returns how many landed.
function Get-FaSteamPictures([string]$AppId, [string]$ImagesDir, [string]$Stem, [string]$SteamRoot, [bool]$Force) {
    $n = 0
    $assets = $null
    $slots = @(
        @{ Names = @('logo.png');                         Suffix = '-marquee'; Tag = 'marquee' },
        @{ Names = @('library_600x900.jpg');              Suffix = '-thumb';   Tag = 'thumbnail' },
        @{ Names = @('header.jpg', 'library_header.jpg'); Suffix = '-image';   Tag = 'image' },
        @{ Names = @('library_hero.jpg');                 Suffix = '-fanart';  Tag = 'fanart' }
    )
    foreach ($s in $slots) {
        $have = Find-FaPicture $ImagesDir $Stem $s.Suffix
        if ($have -ne '' -and -not $Force) { continue }
        $ext = [System.IO.Path]::GetExtension($s.Names[0])
        $dest = Join-Path $ImagesDir ($Stem + $s.Suffix + $ext)
        $got = $false
        # 1. this computer's Steam cache
        $c = Get-SaCachedImage -SteamRoot $SteamRoot -AppId $AppId -Names $s.Names
        if ($c -ne '') {
            try { Copy-Item -LiteralPath $c -Destination $dest -Force; $got = $true } catch { }
        }
        # 2. Steam's own list of the real addresses
        if (-not $got) {
            if ($null -eq $assets) { $assets = $(if ($null -ne $script:FaFetchOverride) { @{} } else { Get-SaAssetUrls -AppId $AppId }) }
            foreach ($u in @($assets[$s.Tag])) {
                if ([string]$u -eq '') { continue }
                if (Save-FaDownload $u $dest) { $got = $true; break }
            }
        }
        # 3. the predictable addresses
        if (-not $got) {
            foreach ($base in $script:SaCdnBases) {
                if (Save-FaDownload ($base -f $AppId, $s.Names[0]) $dest) { $got = $true; break }
            }
        }
        if ($got) { $n++ }
    }
    return $n
}

# --- archive.org ----------------------------------------------------------------
# The item's cover, as both the main picture and the box art.
function Get-FaArchivePicture([string]$Item, [string]$ImagesDir, [string]$Stem, [bool]$Force) {
    $n = 0
    $needImage = ($Force -or (Find-FaPicture $ImagesDir $Stem '-image') -eq '')
    $needThumb = ($Force -or (Find-FaPicture $ImagesDir $Stem '-thumb') -eq '')
    if (-not $needImage -and -not $needThumb) { return 0 }
    $tmp = Join-Path $ImagesDir ($Stem + '-archive.part')
    if (-not (Save-FaDownload ($script:FaArchiveImg -f $Item) $tmp)) { return 0 }
    $ext = Get-FaPictureExt $tmp
    if ($ext -eq '') { try { Remove-Item -LiteralPath $tmp -Force } catch { }; return 0 }
    foreach ($pair in @(@($needImage, '-image'), @($needThumb, '-thumb'))) {
        if (-not $pair[0]) { continue }
        try { Copy-Item -LiteralPath $tmp -Destination (Join-Path $ImagesDir ($Stem + $pair[1] + $ext)) -Force; $n++ } catch { }
    }
    try { Remove-Item -LiteralPath $tmp -Force } catch { }
    return $n
}

# --- a picture straight from an address -------------------------------------------
# The first address that gives a real PNG, JPEG or GIF goes into every slot
# asked for (e.g. -image and -thumb). Returns how many slots were filled.
function Get-FaDirectPicture($Urls, [string]$ImagesDir, [string]$Stem, [string[]]$Suffixes, [bool]$Force) {
    $need = @($Suffixes | Where-Object { $Force -or (Find-FaPicture $ImagesDir $Stem $_) -eq '' })
    if ($need.Count -eq 0) { return 0 }
    $tmp = Join-Path $ImagesDir ($Stem + '-direct.part')
    foreach ($u in @($Urls)) {
        if (-not (Save-FaDownload $u $tmp)) { continue }
        $ext = Get-FaPictureExt $tmp
        if ($ext -eq '') { try { Remove-Item -LiteralPath $tmp -Force } catch { }; continue }
        $n = 0
        foreach ($suf in $need) {
            try { Copy-Item -LiteralPath $tmp -Destination (Join-Path $ImagesDir ($Stem + $suf + $ext)) -Force; $n++ } catch { }
        }
        try { Remove-Item -LiteralPath $tmp -Force } catch { }
        return $n
    }
    return 0
}

# Hand-made stand-ins (under 10 KB) go to archive\ before real pictures are
# fetched, so the real ones can take their place. Only ever on request.
function Move-FaPlaceholders([string]$Root, [string]$ImagesDir, [string]$Stem) {
    $moved = 0
    foreach ($suf in @('-image', '-thumb', '-marquee')) {
        $p = Find-FaPicture $ImagesDir $Stem $suf
        if ($p -eq '') { continue }
        try {
            if ((Get-Item -LiteralPath $p).Length -ge 10KB) { continue }
            $dest = Join-Path $Root '_ClaudeWorkspace\archive\placeholder-pictures'
            New-Item -ItemType Directory -Path $dest -Force | Out-Null
            Move-Item -LiteralPath $p -Destination (Join-Path $dest ((Get-Date -Format 'yyyyMMdd-HHmmss') + '_' + [System.IO.Path]::GetFileName($p))) -Force
            $moved++
        } catch { }
    }
    return $moved
}

# --- the game list ----------------------------------------------------------------
function Set-FaField($Xml, $Game, [string]$Tag, [string]$Value, [bool]$Always) {
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

# Writes every listed game that is actually in roms\flash into its
# gamelist.xml. Returns how many were written, or -1 if it could not.
function Update-FaGameList([string]$Root, $Games, [bool]$Force, [string]$System = 'flash') {
    $dir = Join-Path $Root ('roms\' + $System)
    $listPath = Join-Path $dir 'gamelist.xml'
    $imgDir = Join-Path $dir 'images'
    $xml = New-Object System.Xml.XmlDocument
    if (Test-Path -LiteralPath $listPath) {
        try { $xml.Load($listPath) } catch { $xml = New-Object System.Xml.XmlDocument }
        try {
            $b = Join-Path $Root ('_ClaudeWorkspace\archive\' + $System + '-gamelist_' + (Get-Date -Format 'yyyy-MM-dd_HHmmss'))
            New-Item -ItemType Directory -Path $b -Force | Out-Null
            Copy-Item -LiteralPath $listPath -Destination (Join-Path $b 'gamelist.xml') -Force
        } catch { }
    }
    $list = $xml.SelectSingleNode('/gameList')
    if ($null -eq $list) {
        $xml.RemoveAll()
        [void]$xml.AppendChild($xml.CreateXmlDeclaration('1.0', $null, $null))
        $list = $xml.CreateElement('gameList')
        [void]$xml.AppendChild($list)
    }
    $n = 0
    foreach ($g in @($Games)) {
        if (-not (Test-Path -LiteralPath (Join-Path $dir $g.File))) { continue }
        $rel = './' + $g.File
        $node = $null
        # Walked by hand, never XPath: an apostrophe in a file name throws.
        foreach ($e in @($list.SelectNodes('game'))) {
            $p = [string]$e.SelectSingleNode('path').InnerText
            if ($p -eq $rel -or $p -eq $g.File) { $node = $e; break }
        }
        if ($null -eq $node) {
            $node = $xml.CreateElement('game')
            $pn = $xml.CreateElement('path'); $pn.InnerText = $rel
            [void]$node.AppendChild($pn)
            [void]$list.AppendChild($node)
        }
        Set-FaField $xml $node 'name' $g.Name $Force
        Set-FaField $xml $node 'desc' $g.Desc $Force
        Set-FaField $xml $node 'genre' $g.Genre $Force
        Set-FaField $xml $node 'developer' $g.Developer $Force
        Set-FaField $xml $node 'players' $g.Players $Force
        if ($g.Year -ne '') { Set-FaField $xml $node 'releasedate' ($g.Year + '0101T000000') $Force }
        $stem = [System.IO.Path]::GetFileNameWithoutExtension($g.File)
        foreach ($slot in @(@('image', '-image'), @('thumbnail', '-thumb'), @('marquee', '-marquee'), @('fanart', '-fanart'))) {
            $pic = Find-FaPicture $imgDir $stem $slot[1]
            if ($pic -ne '') { Set-FaField $xml $node $slot[0] ('./images/' + [System.IO.Path]::GetFileName($pic)) $true }
        }
        $n++
    }
    try {
        $set = New-Object System.Xml.XmlWriterSettings
        $set.Indent = $true; $set.IndentChars = "`t"
        $set.Encoding = New-Object System.Text.UTF8Encoding($false)
        $w = [System.Xml.XmlWriter]::Create($listPath, $set)
        try { $xml.Save($w) } finally { $w.Close() }
    }
    catch { return -1 }
    return $n
}

# --- the whole job ------------------------------------------------------------------
# Returns @{ Ok; Lines (what happened, one per game); Message }.
function Invoke-FlashArtwork([string]$Root, [bool]$Force = $false, [string]$SteamRoot = '', [string]$System = 'flash', [string]$IniName = 'flash-games.ini') {
    $res = @{ Ok = $false; Lines = @(); Message = '' }
    $ini = Join-Path $Root ('_ClaudeWorkspace\' + $IniName)
    $games = @(Read-FlashGames $ini)
    if ($games.Count -eq 0) { $res.Message = $IniName + ' is missing or lists no games.'; return $res }
    $dir = Join-Path $Root ('roms\' + $System)
    if (-not (Test-Path -LiteralPath $dir)) { $res.Message = 'There is no roms\' + $System + ' folder.'; return $res }
    $imgDir = Join-Path $dir 'images'
    if (-not (Test-Path -LiteralPath $imgDir)) { New-Item -ItemType Directory -Path $imgDir -Force | Out-Null }
    $lines = @()
    foreach ($g in $games) {
        if (-not (Test-Path -LiteralPath (Join-Path $dir $g.File))) { $lines += ('  {0,-36} not in roms\{1}, skipped' -f $g.File, $System); continue }
        $stem = [System.IO.Path]::GetFileNameWithoutExtension($g.File)
        $from = @()
        $hasSource = ($g.Steam -ne '' -or $g.Archive -ne '' -or @($g.Picture).Count -gt 0 -or @($g.Logo).Count -gt 0)
        if ($System -eq 'windows' -and $hasSource) {
            $mv = Move-FaPlaceholders $Root $imgDir $stem
            if ($mv -gt 0) { $from += ($mv.ToString() + ' stand-in(s) moved to archive') }
        }
        if ($g.Steam -ne '') {
            $id = Resolve-FaSteamId $g.Steam
            if ($id -ne '') {
                $k = Get-FaSteamPictures $id $imgDir $stem $SteamRoot $Force
                $from += ('Steam ' + $id + ': ' + $k + ' new')
            }
            else { $from += 'not on Steam by that name' }
        }
        if ($g.Archive -ne '') {
            $k = Get-FaArchivePicture $g.Archive $imgDir $stem $Force
            $from += ('archive.org: ' + $k + ' new')
        }
        if (@($g.Picture).Count -gt 0) {
            $k = Get-FaDirectPicture $g.Picture $imgDir $stem @('-image', '-thumb') $Force
            $from += ('official picture: ' + $k + ' new')
        }
        if (@($g.Logo).Count -gt 0) {
            $k = Get-FaDirectPicture $g.Logo $imgDir $stem @('-marquee') $Force
            $from += ('official logo: ' + $k + ' new')
        }
        if ($from.Count -eq 0) { $from += 'no picture source listed' }
        $lines += ('  {0,-36} {1}' -f $g.Name, ($from -join ', '))
    }
    $w = Update-FaGameList $Root $games $Force $System
    if ($w -lt 0) { $res.Message = 'The pictures are in, but gamelist.xml could not be written.'; $res.Lines = $lines; return $res }
    $res.Ok = $true
    $res.Lines = $lines
    $res.Message = ('{0} game(s) written into the {1} game list.' -f $w, $System)
    return $res
}
