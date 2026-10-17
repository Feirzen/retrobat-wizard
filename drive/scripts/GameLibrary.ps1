<#
    GameLibrary.ps1 - the Games tab's engine: adding a game from this
    computer, and the online game library.

    FUNCTIONS ONLY. Dot-source it. Used by wizard\SetupWizard.ps1.

    ADDING A GAME (Steven, 2026-10-10: friends add their own games)
    ----------------------------------------------------------------
    Which console a file belongs to comes from RetroBat's OWN list,
    emulationstation\.emulationstation\es_systems.cfg, never from a list kept
    here: every console there names its folder and the file types it takes.
    Two things sharpen the guess:
      - a .zip is opened and the file inside it decides (a .zip of a .gba
        file is a GBA game)
      - a GameCube and a Wii disc look identical by name, but each has a
        fixed "magic number" at the start of the disc, which is read
    When it is still not sure, the person picks from the consoles that take
    that kind of file, with the Nintendo ones first. The file is COPIED into
    roms\<console>\, never moved, and an identical file already there is left
    alone. RetroBat finds it the next time it starts.

    THE ONLINE LIBRARY (Steven, 2026-10-10)
    ---------------------------------------
    Free, homebrew and fan-made games Steven puts online, which friends browse
    and add by hand. library\library.json in the public repo lists them; each
    file has its size and SHA-256, and a download is only moved into roms\
    once it matches. Nothing is ever added without somebody pressing Add.

    Admins add games from the Admin tab (Publish a game, AdminEngine.ps1),
    which uploads the file and updates library.json by itself. The
    library-to-publish functions below are the older by-hand route.

    PRIVATE FILES (2026-10-11). A file whose url is "private:<name>" lives
    in the PRIVATE repo's "library" release, not on the open internet. Only
    a wizard can fetch it: it asks GitHub for that release with the shared
    friends key (SocialEngine.ps1, Get-SocialToken) and downloads the file
    by name. The list stays public so the website can show what is there.

    ASCII ONLY, Windows PowerShell 5.1. Every root is a parameter. Test hook:
        $script:LibFetchOverride   { param($Url, $OutFile) ... }
#>

$script:LibRepo  = 'Feirzen/retrobat-wizard'
$script:LibFetchOverride = $null
# Where SocialEngine.ps1 is, for the friends key that private files need.
# Taken when this file is dot-sourced; inside a function it can be wrong.
$script:LibScriptsDir = $PSScriptRoot
# The order consoles are offered in when a file could be several: this
# drive's own focus first.
$script:LibPreferred = @('nes', 'snes', 'n64', 'gb', 'gbc', 'gba', 'nds', '3ds', 'gamecube', 'wii', 'wiiu',
                         'virtualboy', 'flash', 'scummvm')

function Join-LibPath([string]$Base, [string]$Rel) {
    $p = $Base
    foreach ($seg in ($Rel -split '[\\/]')) { if ($seg -ne '') { $p = [System.IO.Path]::Combine($p, $seg) } }
    return $p
}

# ---------------------------------------------------------------------------
#  RetroBat's console list
# ---------------------------------------------------------------------------
#  Every console with its folder and file types, from es_systems.cfg. The
#  path in there starts with ~, which is the emulationstation folder.
function Get-LibSystems([string]$Root) {
    $cfg = Join-LibPath $Root 'emulationstation\.emulationstation\es_systems.cfg'
    $out = New-Object System.Collections.ArrayList
    if (-not (Test-Path -LiteralPath $cfg)) { return @() }
    [xml]$x = [System.IO.File]::ReadAllText($cfg)
    $esDir = Join-LibPath $Root 'emulationstation'
    foreach ($s in @($x.systemList.system)) {
        $name = [string]$s.name
        $path = [string]$s.path
        if ($name -eq '' -or $path -eq '') { continue }
        $rel = $path.Trim()
        if ($rel.StartsWith('~')) { $rel = $rel.Substring(1) }
        $full = [System.IO.Path]::GetFullPath((Join-LibPath $esDir $rel))
        $exts = @(([string]$s.extension).ToLower().Split(' ', [StringSplitOptions]::RemoveEmptyEntries))
        $rank = [array]::IndexOf($script:LibPreferred, $name)
        if ($rank -lt 0) { $rank = 1000 }
        [void]$out.Add([pscustomobject]@{
            Name = $name; FullName = [string]$s.fullname; Folder = $full; Extensions = $exts; Rank = $rank
        })
    }
    return @($out | Sort-Object Rank, FullName)
}

# The extension that decides: the file's own, or for a .zip the biggest
# file inside it.
function Get-LibInnerExtension([string]$File) {
    $ext = [System.IO.Path]::GetExtension($File).ToLower()
    if ($ext -ne '.zip') { return $ext }
    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
        $z = [System.IO.Compression.ZipFile]::OpenRead($File)
        try {
            $big = @($z.Entries | Where-Object { $_.Name -ne '' } | Sort-Object Length -Descending | Select-Object -First 1)
            if ($big.Count -eq 1) { return [System.IO.Path]::GetExtension($big[0].Name).ToLower() }
        }
        finally { $z.Dispose() }
    } catch { }
    return $ext
}

# 'gamecube', 'wii' or '' for a plain disc image. Both keep a magic number
# in the disc header: Wii at 0x18, GameCube at 0x1C.
function Get-LibDiscKind([string]$File) {
    try {
        $fs = [System.IO.File]::OpenRead($File)
        try {
            $buf = New-Object byte[] 32
            if ($fs.Read($buf, 0, 32) -lt 32) { return '' }
            $wii = ($buf[0x18] -eq 0x5D -and $buf[0x19] -eq 0x1C -and $buf[0x1A] -eq 0x9E -and $buf[0x1B] -eq 0xA3)
            $gc  = ($buf[0x1C] -eq 0xC2 -and $buf[0x1D] -eq 0x33 -and $buf[0x1E] -eq 0x9F -and $buf[0x1F] -eq 0x3D)
            if ($wii) { return 'wii' }
            if ($gc)  { return 'gamecube' }
        }
        finally { $fs.Close() }
    } catch { }
    return ''
}

# Which consoles could take this file, best guess first. Sure = $true when
# there is only one real answer.
function Get-LibSystemGuess([string]$File, $Systems) {
    $ext = [System.IO.Path]::GetExtension($File).ToLower()
    $inner = Get-LibInnerExtension $File
    $cands = @($Systems | Where-Object { $_.Extensions -contains $ext })
    if ($inner -ne $ext) {
        $byInner = @($cands | Where-Object { $_.Extensions -contains $inner })
        if ($byInner.Count -gt 0) { $cands = $byInner }
    }
    if ($ext -eq '.iso' -or $ext -eq '.gcm') {
        $kind = Get-LibDiscKind $File
        if ($kind -ne '') { $cands = @(@($cands | Where-Object { $_.Name -eq $kind }) + @($cands | Where-Object { $_.Name -ne $kind })) }
        return [pscustomobject]@{ Candidates = $cands; Sure = ($kind -ne '') }
    }
    if ($ext -eq '.wbfs') { $cands = @(@($cands | Where-Object { $_.Name -eq 'wii' }) + @($cands | Where-Object { $_.Name -ne 'wii' })) ; return [pscustomobject]@{ Candidates = $cands; Sure = $true } }
    $nintendo = @($cands | Where-Object { $_.Rank -lt 1000 })
    return [pscustomobject]@{ Candidates = $cands; Sure = ($nintendo.Count -eq 1 -or $cands.Count -eq 1) }
}

function Get-LibHash([string]$Path) { return ((Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLower()) }

# Copies a file in pieces so a big disc image can report how far it has got.
# $Progress gets a number from 0 to 100.
function Copy-LibFile([string]$From, [string]$To, $Progress = $null) {
    $in = [System.IO.File]::OpenRead($From)
    try {
        $out = [System.IO.File]::Create($To)
        try {
            $buf = New-Object byte[] (4MB)
            $total = [double]$in.Length; $done = 0.0; $last = -1
            while (($n = $in.Read($buf, 0, $buf.Length)) -gt 0) {
                $out.Write($buf, 0, $n); $done += $n
                $pct = $(if ($total -gt 0) { [int](100 * $done / $total) } else { 100 })
                if ($null -ne $Progress -and $pct -ne $last) { $last = $pct; try { & $Progress $pct } catch { } }
            }
        }
        finally { $out.Close() }
    }
    finally { $in.Close() }
}

# Puts one file into roms\<system>\. Returns @{ Ok; Path; Message }.
#   same name, same file      -> nothing to do
#   same name, different file -> saved as "name (2).ext", nothing replaced
function Add-LibGameFile([string]$File, $System, $Progress = $null) {
    $res = @{ Ok = $false; Path = ''; Message = '' }
    if (-not (Test-Path -LiteralPath $File -PathType Leaf)) { $res.Message = 'That file is not there any more.'; return $res }
    if (-not (Test-Path -LiteralPath $System.Folder)) { [void](New-Item -ItemType Directory -Path $System.Folder -Force) }
    $name = [System.IO.Path]::GetFileName($File)
    $dest = Join-LibPath $System.Folder $name
    if (Test-Path -LiteralPath $dest) {
        if ((Get-Item -LiteralPath $dest).Length -eq (Get-Item -LiteralPath $File).Length -and (Get-LibHash $dest) -eq (Get-LibHash $File)) {
            $res.Ok = $true; $res.Path = $dest; $res.Message = 'Already there.'
            return $res
        }
        $stem = [System.IO.Path]::GetFileNameWithoutExtension($name); $ext = [System.IO.Path]::GetExtension($name)
        $n = 2
        do { $dest = Join-LibPath $System.Folder ("$stem ($n)$ext"); $n++ } while (Test-Path -LiteralPath $dest)
    }
    $tmp = $dest + '.copying'
    try {
        Copy-LibFile $File $tmp $Progress
        Move-Item -LiteralPath $tmp -Destination $dest
        $res.Ok = $true; $res.Path = $dest; $res.Message = 'Added.'
    }
    catch {
        try { if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force } } catch { }
        $res.Message = 'Could not copy it: ' + $_.Exception.Message
    }
    return $res
}

# ---------------------------------------------------------------------------
#  The online library
# ---------------------------------------------------------------------------
function Invoke-LibFetch([string]$Url, [string]$OutFile, [string]$Ws = '') {
    if ($null -ne $script:LibFetchOverride) { & $script:LibFetchOverride $Url $OutFile; return }
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch { }
    $old = $ProgressPreference; $ProgressPreference = 'SilentlyContinue'
    try {
        if ($Url -like 'private:*') { Get-LibPrivateFile $Ws $Url.Substring(8) $OutFile }
        else { Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing -TimeoutSec 600 -ErrorAction Stop }
    }
    finally { $ProgressPreference = $old }
}

# One file from the private repo's "library" release. Throws with plain
# words when it cannot, which Install-LibGame shows as it is.
#   1. the friends key, from social\social-token.txt
#   2. the release, to find the file's number by its name
#   3. the file itself, asked for as raw bytes. GitHub answers with a short
#      redirect to its file store; Windows drops the key on that hop by
#      itself, which is what the file store wants.
function Get-LibPrivateFile([string]$Ws, [string]$Name, [string]$OutFile) {
    if (-not (Get-Command Get-SocialToken -ErrorAction SilentlyContinue)) {
        $se = Join-LibPath ([string]$script:LibScriptsDir) 'SocialEngine.ps1'
        if (-not (Test-Path -LiteralPath $se)) { throw 'the friends part of the wizard is missing (SocialEngine.ps1)' }
        . $se
    }
    $key = Get-SocialToken $Ws
    if ($key -eq '') { throw 'this drive has no friends key, which private library games need' }
    $repo = Get-SocialRepo $Ws
    $h = @{ Authorization = "Bearer $key"; Accept = 'application/vnd.github+json'; 'X-GitHub-Api-Version' = '2022-11-28' }
    $rel = Invoke-WebRequest -Uri "https://api.github.com/repos/$repo/releases/tags/library" -Headers $h -UseBasicParsing -TimeoutSec 60 -ErrorAction Stop
    $c = $rel.Content
    if ($c -is [byte[]]) { $c = [System.Text.Encoding]::UTF8.GetString($c) }
    $asset = @((([string]$c) | ConvertFrom-Json).assets | Where-Object { $null -ne $_ -and [string]$_.name -eq $Name })
    if ($asset.Count -eq 0) { throw 'that game is not in the private library any more' }
    $h.Accept = 'application/octet-stream'
    Invoke-WebRequest -Uri ([string]$asset[0].url) -Headers $h -OutFile $OutFile -UseBasicParsing -TimeoutSec 3600 -ErrorAction Stop
}

function Get-LibCacheDir([string]$Ws) { return (Join-LibPath $Ws 'library') }

# Reads the list from GitHub (or the last copy when offline). Returns
# @{ Ok; Games; Message; FromCache }. Every entry is checked before use:
# a console name that is not a plain word, a file name with a path in it, a
# download that is not from GitHub, or a bad checksum means it is dropped.
function Get-LibCatalog([string]$Ws) {
    $res = @{ Ok = $false; Games = @(); Message = ''; FromCache = $false }
    $dir = Get-LibCacheDir $Ws
    if (-not (Test-Path -LiteralPath $dir)) { [void](New-Item -ItemType Directory -Path $dir -Force) }
    $cache = Join-LibPath $dir 'library.json'
    $tmp = $cache + '.new'
    $url = 'https://raw.githubusercontent.com/{0}/main/library/library.json?t={1}' -f $script:LibRepo, [DateTime]::UtcNow.Ticks
    try {
        Invoke-LibFetch $url $tmp
        $null = [System.IO.File]::ReadAllText($tmp) | ConvertFrom-Json
        Copy-Item -LiteralPath $tmp -Destination $cache -Force
        Remove-Item -LiteralPath $tmp -Force
    }
    catch {
        try { if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force } } catch { }
        if (-not (Test-Path -LiteralPath $cache)) { $res.Message = 'Could not reach GitHub.'; return $res }
        $res.FromCache = $true
        $res.Message = 'Offline: showing the last list.'
    }
    try { $d = [System.IO.File]::ReadAllText($cache) | ConvertFrom-Json } catch { $res.Message = 'The library list is damaged.'; return $res }
    $games = New-Object System.Collections.ArrayList
    foreach ($g in @($d.games)) {
        $sys = [string]$g.system
        if ($sys -notmatch '^[a-z0-9\-]{1,20}$') { continue }
        $files = @()
        $bad = $false
        foreach ($f in @($g.files)) {
            $fn = [string]$f.name
            $u = [string]$f.url
            if ($fn -eq '' -or $fn -match '[\\/:*?"<>|]' -or $fn -match '^\.') { $bad = $true; break }
            if ($u -notmatch '^https://(raw\.githubusercontent\.com|github\.com)/' -and $u -notmatch '^private:[A-Za-z0-9._\-]{1,200}$') { $bad = $true; break }
            if ([string]$f.sha256 -notmatch '^[0-9a-f]{64}$') { $bad = $true; break }
            $files += [pscustomobject]@{ Name = $fn; Url = $u; Size = [long]$f.size; Sha = [string]$f.sha256 }
        }
        # A game too big for one GitHub file comes in pieces (2026-10-13):
        # shown and installed as ONE file, glued back together on download.
        if (-not $bad -and $files.Count -eq 0 -and $null -ne $g.parts) {
            $pn = [string]$g.parts.name
            $pieces = @()
            foreach ($pc in @($g.parts.pieces)) {
                $u = [string]$pc.url
                if ($u -notmatch '^https://(raw\.githubusercontent\.com|github\.com)/' -and $u -notmatch '^private:[A-Za-z0-9._\-]{1,200}$') { $bad = $true; break }
                if ([string]$pc.sha256 -notmatch '^[0-9a-f]{64}$') { $bad = $true; break }
                $pieces += [pscustomobject]@{ Url = $u; Size = [long]$pc.size; Sha = [string]$pc.sha256 }
            }
            if ($pn -eq '' -or $pn -match '[\\/:*?"<>|]' -or $pn -match '^\.' -or [string]$g.parts.sha256 -notmatch '^[0-9a-f]{64}$' -or $pieces.Count -lt 2) { $bad = $true }
            if (-not $bad) { $files += [pscustomobject]@{ Name = $pn; Url = ''; Size = [long]$g.parts.size; Sha = [string]$g.parts.sha256; Pieces = $pieces } }
        }
        if ($bad -or $files.Count -eq 0) { continue }
        [void]$games.Add([pscustomobject]@{
            Id = ([string]$g.id -replace '[^a-z0-9\-]', '')
            Title = (([string]$g.title) -replace '[^\x20-\x7E]', '').Trim()
            System = $sys
            Players = (([string]$g.players) -replace '[^\x20-\x7E]', '').Trim()
            Description = (([string]$g.description) -replace '[^\x20-\x7E]', '').Trim()
            Files = $files
            Size = [long](($files | Measure-Object -Property Size -Sum).Sum)
            ArtRel = $(if ([string]$g.art -match '^library/art/[a-z0-9\-]{1,40}\.(png|jpg|gif|webp)$') { [string]$g.art } else { '' })
            Art = ''
        })
    }
    # Box art (2026-10-12, Steven: "box art there, small"): each picture is
    # fetched once into library\art\ and fetched again after a week, in case
    # it was replaced. Offline, the copy already here is used. A picture that
    # cannot be had just means the console's picture shows instead.
    $artDir = Join-LibPath $dir 'art'
    foreach ($gm in $games) {
        if ($gm.ArtRel -eq '') { continue }
        try {
            if (-not (Test-Path -LiteralPath $artDir)) { [void](New-Item -ItemType Directory -Path $artDir -Force) }
            $leaf = $gm.ArtRel.Substring(12)
            $local = Join-LibPath $artDir $leaf
            $fresh = (Test-Path -LiteralPath $local) -and ((Get-Item -LiteralPath $local).LastWriteTime -gt (Get-Date).AddDays(-7))
            if (-not $fresh -and -not $res.FromCache) {
                $part = $local + '.part'
                try {
                    Invoke-LibFetch ('https://raw.githubusercontent.com/{0}/main/{1}?t={2}' -f $script:LibRepo, $gm.ArtRel, [DateTime]::UtcNow.Ticks) $part
                    if ((Get-Item -LiteralPath $part).Length -gt 0 -and (Get-Item -LiteralPath $part).Length -le 3MB) { Move-Item -LiteralPath $part -Destination $local -Force }
                } catch { }
                if (Test-Path -LiteralPath $part) { Remove-Item -LiteralPath $part -Force -ErrorAction SilentlyContinue }
            }
            if (Test-Path -LiteralPath $local) { $gm.Art = $local }
        } catch { }
    }
    $res.Ok = $true
    $res.Games = @($games | Sort-Object System, Title)
    return $res
}

# Is this library game already on the drive? (every file there, right size)
function Test-LibGameInstalled($Game, $Systems) {
    $sys = @($Systems | Where-Object { $_.Name -eq $Game.System })
    if ($sys.Count -eq 0) { return $false }
    foreach ($f in $Game.Files) {
        $p = Join-LibPath $sys[0].Folder $f.Name
        if (-not (Test-Path -LiteralPath $p)) { return $false }
        if ((Get-Item -LiteralPath $p).Length -ne $f.Size) { return $false }
    }
    return $true
}

# Downloads every piece of a split game (each checked against its own
# fingerprint; a piece already downloaded and correct is kept, so a stopped
# download carries on), glues them in order into $OutFile, and deletes each
# piece as soon as it is glued, so the drive never needs room for much more
# than the game itself. The whole file is checked by the caller.
function Join-LibPieces([string]$Ws, $File, [string]$Dir, [string]$OutFile) {
    $res = @{ Ok = $false; Message = '' }
    $paths = @()
    $i = 0
    foreach ($pc in @($File.Pieces)) {
        $i++
        $pp = Join-LibPath $Dir ('{0}.piece{1:D2}' -f $File.Name, $i)
        $good = (Test-Path -LiteralPath $pp) -and ((Get-Item -LiteralPath $pp).Length -eq $pc.Size) -and ((Get-LibHash $pp) -eq $pc.Sha)
        if (-not $good) {
            try { Invoke-LibFetch $pc.Url $pp $Ws }
            catch { $res.Message = ('The download stopped on piece {0}: {1}' -f $i, $_.Exception.Message); return $res }
            if ((Get-Item -LiteralPath $pp).Length -ne $pc.Size -or (Get-LibHash $pp) -ne $pc.Sha) {
                Remove-Item -LiteralPath $pp -Force
                $res.Message = ('Piece {0} of {1} did not match its checksum, so it was not added.' -f $i, $File.Name)
                return $res
            }
        }
        $paths += $pp
    }
    try {
        $out = [System.IO.File]::Create($OutFile)
        try {
            $buf = New-Object byte[] (4MB)
            foreach ($pp in $paths) {
                $in = [System.IO.File]::OpenRead($pp)
                try { while (($n = $in.Read($buf, 0, $buf.Length)) -gt 0) { $out.Write($buf, 0, $n) } } finally { $in.Close() }
                Remove-Item -LiteralPath $pp -Force -ErrorAction SilentlyContinue
            }
        } finally { $out.Close() }
    }
    catch { $res.Message = 'Putting the pieces back together failed: ' + $_.Exception.Message; return $res }
    $res.Ok = $true
    return $res
}

# Downloads a library game, checks every file, then moves it into place.
# Returns @{ Ok; Message }.
function Install-LibGame([string]$Ws, $Game, $Systems) {
    $res = @{ Ok = $false; Message = '' }
    $sys = @($Systems | Where-Object { $_.Name -eq $Game.System })
    if ($sys.Count -eq 0) { $res.Message = "This RetroBat has no '$($Game.System)' console."; return $res }
    $dl = Join-LibPath (Get-LibCacheDir $Ws) 'downloads'
    if (-not (Test-Path -LiteralPath $dl)) { [void](New-Item -ItemType Directory -Path $dl -Force) }
    $ready = @()
    foreach ($f in $Game.Files) {
        $tmp = Join-LibPath $dl ($f.Name + '.part')
        if ($null -ne $f.PSObject.Properties['Pieces'] -and @($f.Pieces).Count -gt 0) {
            $j = Join-LibPieces $Ws $f $dl $tmp
            if (-not $j.Ok) { $res.Message = $j.Message; return $res }
        }
        else {
        try { Invoke-LibFetch $f.Url $tmp $Ws }
        catch { $res.Message = 'The download stopped: ' + $_.Exception.Message; return $res }
        }
        if ((Get-Item -LiteralPath $tmp).Length -ne $f.Size -or (Get-LibHash $tmp) -ne $f.Sha) {
            Remove-Item -LiteralPath $tmp -Force
            $res.Message = "$($f.Name) did not match its checksum, so it was not added."
            return $res
        }
        $ready += ,@($tmp, $f.Name)
    }
    if (-not (Test-Path -LiteralPath $sys[0].Folder)) { [void](New-Item -ItemType Directory -Path $sys[0].Folder -Force) }
    foreach ($r in $ready) {
        $dest = Join-LibPath $sys[0].Folder $r[1]
        if (Test-Path -LiteralPath $dest) { Remove-Item -LiteralPath $r[0] -Force; continue }   # never replace a file already there
        Move-Item -LiteralPath $r[0] -Destination $dest
    }
    $res.Ok = $true
    $res.Message = "$($Game.Title) is in your games, checked: every file matches the online library. It shows up the next time RetroBat starts."
    return $res
}

# ---------------------------------------------------------------------------
#  Steven's side: putting a game up for publishing
# ---------------------------------------------------------------------------
function Get-LibPublishDir([string]$Ws) { return (Join-LibPath $Ws 'library-to-publish') }
function Test-LibCanPublish([string]$Ws) { return (Test-Path -LiteralPath (Get-LibPublishDir $Ws) -PathType Container) }

# Copies a game file into library-to-publish\<id>\ with a game.ini Claude
# reads when publishing. Returns @{ Ok; Message; Folder }.
function New-LibPublishEntry([string]$Ws, [string]$File, [string]$System, [string]$Title, [string]$Players, [string]$Description) {
    $res = @{ Ok = $false; Message = ''; Folder = '' }
    $id = (($Title.ToLower() -replace '[^a-z0-9]+', '-').Trim('-'))
    if ($id -eq '') { $id = 'game' }
    if ($id.Length -gt 40) { $id = $id.Substring(0, 40).Trim('-') }
    $dir = Join-LibPath (Get-LibPublishDir $Ws) $id
    if (Test-Path -LiteralPath $dir) { $res.Message = 'That game is already waiting to be published.'; $res.Folder = $dir; return $res }
    [void](New-Item -ItemType Directory -Path $dir -Force)
    Copy-LibFile $File (Join-LibPath $dir ([System.IO.Path]::GetFileName($File)))
    $clean = { param($t) (([string]$t) -replace '[\r\n]+', ' ' -replace '[^\x20-\x7E]', '').Trim() }
    [System.IO.File]::WriteAllLines((Join-LibPath $dir 'game.ini'), [string[]]@(
        '; Waiting to be published to the online library. Tell Claude: "publish the library".',
        '; Only games that may be shared: homebrew, freeware, fan-made, your own.',
        ('title       = ' + (& $clean $Title)),
        ('system      = ' + $System),
        ('players     = ' + (& $clean $Players)),
        ('description = ' + (& $clean $Description)),
        ('file        = ' + [System.IO.Path]::GetFileName($File)),
        ('queued      = ' + (Get-Date -Format 'yyyy-MM-dd HH:mm'))))
    $res.Ok = $true; $res.Folder = $dir
    $res.Message = 'Ready to publish. Tell Claude "publish the library" when you have added everything you want.'
    return $res
}

# What RetroBat already knows about a game (its gamelist.xml): name, players,
# description, and its box art (Art: a full path, or '' when there is none).
# Works for games in sub-folders too (2026-10-11, for the multi-upload).
function Get-LibGamelistInfo($System, [string]$File) {
    $out = @{ Title = [System.IO.Path]::GetFileNameWithoutExtension($File); Players = ''; Description = ''; Art = '' }
    $gl = Join-LibPath $System.Folder 'gamelist.xml'
    if (-not (Test-Path -LiteralPath $gl)) { return $out }
    try {
        [xml]$x = [System.IO.File]::ReadAllText($gl)
        $want = './' + [System.IO.Path]::GetFileName($File)
        $base = ([string]$System.Folder).TrimEnd('\', '/')
        if ($File.Length -gt $base.Length -and $File.StartsWith($base, [System.StringComparison]::OrdinalIgnoreCase)) {
            $want = './' + ($File.Substring($base.Length).TrimStart('\', '/') -replace '\\', '/')
        }
        foreach ($g in @($x.gameList.game)) {
            if ($null -eq $g) { continue }
            if (([string]$g.path -replace '\\', '/') -eq $want) {
                if ($g.name) { $out.Title = [string]$g.name }
                if ($g.players) { $out.Players = [string]$g.players }
                if ($g.desc) { $out.Description = [string]$g.desc }
                foreach ($k in @('image', 'thumbnail')) {
                    $rel = [string]$g.$k
                    if ($rel -eq '') { continue }
                    $full = $(if ($rel.StartsWith('./') -or $rel.StartsWith('.\')) { Join-LibPath $System.Folder $rel.Substring(2) } else { $rel })
                    if (Test-Path -LiteralPath $full) { $out.Art = $full; break }
                }
                break
            }
        }
    } catch { }
    return $out
}
