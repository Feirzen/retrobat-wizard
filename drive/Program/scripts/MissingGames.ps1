# ===========================================================================
#  MISSING GAMES FINDER (3.2, 2026-10-26)
# ---------------------------------------------------------------------------
#  Steven's flag: games that are on the drive but RetroBat does not show.
#  The Health page's "Look for missing games" runs Find-MissingGames, which
#  reads the console list (es_systems.cfg, through GameLibrary.ps1) and walks
#  roms\. Each find has a plain reason and, where it is safe, a fix:
#
#    wrongtype   a file whose type that console does not read. When exactly
#                one other console takes it, Fix moves it there.
#    loose       a game sitting in roms\ itself, outside any console folder.
#                Fix moves it into the console it belongs to (when sure).
#    nofolder    a folder in roms\ that no console in RetroBat uses.
#    hidden      hidden in RetroBat's game list by hand. Fix shows it again.
#    family      hidden by family-friendly on purpose. No fix here: that is
#                the Features page's switch.
#
#  Nothing is ever replaced: a move to a place that already has that file
#  name is refused. Needs GameLibrary.ps1 loaded first.
# ===========================================================================

# File types that are never games (pictures, notes, saves ...), unless the
# console itself reads that type.
$script:MgNotGames = @('.txt', '.xml', '.nfo', '.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp', '.mp4', '.mkv', '.avi', '.pdf',
    '.srm', '.sav', '.state', '.cfg', '.ini', '.dat', '.db', '.bak', '.log', '.url', '.lnk', '.md', '.json', '.old', '.tmp',
    '.sfv', '.md5', '.sha1', '.ds_store', '.ips', '.bps', '.ups', '.xdelta', '.cht', '.dll', '.exe', '.bat', '.vbs', '.ps1')
# Folders RetroBat keeps beside the games (art, videos ...): never looked in.
$script:MgSkipDirs = @('images', 'videos', 'manuals', 'media', 'downloaded_images', 'downloaded_videos', 'marquees', 'thumbnails',
    'screenshots', 'saves', 'snap', 'snaps', 'boxart', 'covers', 'fanart', 'wheel', 'titles', 'maps', 'music', 'bezels')

# The tracks and discs other files point at (a .cue's .bin, an .m3u's
# discs). RetroBat folds them into the game, so they are never "missing".
function Get-MgReferenced([string]$Folder) {
    $ref = @{}
    foreach ($f in @(Get-ChildItem -LiteralPath $Folder -Recurse -File -ErrorAction SilentlyContinue | Where-Object { @('.cue', '.gdi', '.m3u', '.ccd', '.mds') -contains $_.Extension.ToLower() })) {
        try {
            $gs = Get-LibGameSet $f.FullName $Folder
            foreach ($x in @($gs.Files | Select-Object -Skip 1)) { $ref[([string]$x.Path).ToLower()] = $true }
        } catch { }
    }
    return $ref
}

# Every game file under a folder, skipping RetroBat's art folders and the
# inside of folder games (a .ps3 folder is one game). @(FileInfo/DirInfo).
function Get-MgCandidates([string]$Folder, $Exts) {
    # 3.2 (Steven's test found 7316 "missing" things): a game's own folder
    # is full of data files (PC ports, Xbox 360 and PS3 games, Half-Life).
    # So: files at the console's top level are each looked at; a sub-folder
    # holding at least one game file is looked at for its game files only;
    # a sub-folder with no game file at all is ONE find, not one per file.
    $files = New-Object System.Collections.ArrayList
    $folders = New-Object System.Collections.ArrayList
    foreach ($f in @(Get-ChildItem -LiteralPath $Folder -File -Force -ErrorAction SilentlyContinue)) { [void]$files.Add($f) }
    foreach ($sub in @(Get-ChildItem -LiteralPath $Folder -Directory -Force -ErrorAction SilentlyContinue)) {
        if ($sub.Name.StartsWith('.') -or $script:MgSkipDirs -contains $sub.Name.ToLower()) { continue }
        $sx = [System.IO.Path]::GetExtension($sub.Name).ToLower()
        if ($sx -ne '' -and $Exts -contains $sx) { continue }   # a folder game: RetroBat lists the folder itself
        $all = @(Get-ChildItem -LiteralPath $sub.FullName -Recurse -File -Force -ErrorAction SilentlyContinue | Where-Object { $_.FullName -notmatch '[\\/](images|videos|manuals|media)[\\/]' })
        $game = @($all | Where-Object { $Exts -contains $_.Extension.ToLower() })
        if ($game.Count -gt 0) { foreach ($g in $game) { [void]$files.Add($g) }; continue }
        $other = @($all | Where-Object { $script:MgNotGames -notcontains $_.Extension.ToLower() })
        if ($other.Count -gt 0) { [void]$folders.Add(@{ Dir = $sub; Count = $other.Count }) }
    }
    return @{ Files = @($files); Folders = @($folders) }
}

# Paths (as the game list writes them, "./x.iso") hidden in a console's
# gamelist.xml. @{ lowercase path = $true }
function Get-MgHiddenPaths([string]$GameList) {
    $out = @{}
    if (-not (Test-Path -LiteralPath $GameList)) { return $out }
    try { $t = [System.IO.File]::ReadAllText($GameList) } catch { return $out }
    foreach ($m in [regex]::Matches($t, '<game\b[^>]*>.*?</game>', 'Singleline')) {
        if ($m.Value -notmatch '<hidden>\s*true\s*</hidden>') { continue }
        $pm = [regex]::Match($m.Value, '<path>(.*?)</path>', 'Singleline')
        if ($pm.Success) { $out[([System.Net.WebUtility]::HtmlDecode($pm.Groups[1].Value).Trim()).ToLower()] = $true }
    }
    return $out
}

# The look. Returns @{ Items; Consoles; Message }. Each item:
#   @{ Path; Show (the path from roms\); Console; Kind; Reason; Fix; To }
#   Fix is '' (nothing to press), 'move' (To = the console folder) or 'unhide'.
function Find-MissingGames([string]$Root, [string]$Ws) {
    $res = @{ Items = @(); Consoles = 0; Message = ''; Family = 0 }
    $roms = Join-LibPath $Root 'roms'
    if (-not (Test-Path -LiteralPath $roms)) { $res.Message = 'There is no roms folder.'; return $res }
    $systems = @(Get-LibSystems $Root)
    if ($systems.Count -eq 0) { $res.Message = 'RetroBat''s console list (es_systems.cfg) could not be read.'; return $res }
    $romsFull = [System.IO.Path]::GetFullPath($roms).TrimEnd('\', '/')
    $byFolder = @{}
    foreach ($s in $systems) { $byFolder[([string]$s.Folder).TrimEnd('\', '/').ToLower()] = $s }
    $family = @{}
    $recF = Join-LibPath $Ws 'Settings\family-hidden.txt'
    if (Test-Path -LiteralPath $recF) { foreach ($l in [System.IO.File]::ReadAllLines($recF)) { if ($l -ne '' -and -not $l.StartsWith(';')) { $family[$l.ToLower()] = $true } } }
    $items = New-Object System.Collections.ArrayList
    $show = { param($p) $p.Substring($romsFull.Length).TrimStart('\', '/') -replace '/', '\' }
    $guess = {
        param($p)
        try {
            $g = Get-LibSystemGuess $p $systems
            if ($g.Sure -and @($g.Candidates).Count -gt 0) { return $g.Candidates[0] }
        } catch { }
        return $null
    }

    # games lying loose in roms\ itself
    foreach ($f in @(Get-ChildItem -LiteralPath $roms -File -Force -ErrorAction SilentlyContinue)) {
        $ext = $f.Extension.ToLower()
        if ($script:MgNotGames -contains $ext -or $f.Name.StartsWith('.')) { continue }
        $to = & $guess $f.FullName
        [void]$items.Add(@{ Path = $f.FullName; Show = $f.Name; Console = ''; Kind = 'loose'
            Reason = $(if ($null -ne $to) { "Sits in roms itself, not in a console's folder. It looks like a $($to.FullName) game." } else { "Sits in roms itself, not in a console's folder, and its type does not say which console it is for." })
            Fix = $(if ($null -ne $to) { 'move' } else { '' }); To = $(if ($null -ne $to) { [string]$to.Name } else { '' }); ToFolder = $(if ($null -ne $to) { [string]$to.Folder } else { '' }) })
    }

    foreach ($d in @(Get-ChildItem -LiteralPath $roms -Directory -Force -ErrorAction SilentlyContinue)) {
        if ($d.Name.StartsWith('.')) { continue }
        $sys = $byFolder[$d.FullName.TrimEnd('\', '/').ToLower()]
        if ($null -eq $sys) {
            $n = @(Get-ChildItem -LiteralPath $d.FullName -Recurse -File -Force -ErrorAction SilentlyContinue | Where-Object { $script:MgNotGames -notcontains $_.Extension.ToLower() }).Count
            if ($n -gt 0) {
                [void]$items.Add(@{ Path = $d.FullName; Show = ($d.Name + '\'); Console = ''; Kind = 'nofolder'
                    Reason = ("No console in RetroBat uses a folder called '{0}', so its {1} file(s) never show. Check the name (for example gc should be gamecube), or move the games by hand." -f $d.Name, $n); Fix = ''; To = ''; ToFolder = '' })
            }
            continue
        }
        $res.Consoles++
        $exts = @($sys.Extensions)
        $ref = Get-MgReferenced $d.FullName
        $hidden = Get-MgHiddenPaths (Join-Path $d.FullName 'gamelist.xml')
        $cand = Get-MgCandidates $d.FullName $exts
        foreach ($fd in @($cand.Folders)) {
            [void]$items.Add(@{ Path = $fd.Dir.FullName; Show = ((& $show $fd.Dir.FullName) + '\'); Console = $sys.Name; Kind = 'nogame'
                Reason = ('A folder with {0} file(s), none of a type {1} reads ({2}).' -f $fd.Count, $sys.FullName, (($exts | Select-Object -First 8) -join ' ')); Fix = ''; To = ''; ToFolder = '' })
        }
        foreach ($f in @($cand.Files)) {
            if ($f.Name -eq 'gamelist.xml' -or $f.Name.StartsWith('.')) { continue }
            $ext = $f.Extension.ToLower()
            $low = $f.FullName.ToLower()
            if ($ref.ContainsKey($low)) { continue }
            $glPath = './' + ($f.FullName.Substring($d.FullName.TrimEnd('\', '/').Length).TrimStart('\', '/') -replace '\\', '/')
            if ($exts -contains $ext) {
                if ($hidden.ContainsKey($glPath.ToLower())) {
                    if ($family.ContainsKey(($d.Name + '|' + $glPath).ToLower())) {
                        $res.Family++   # hidden on purpose: counted, not listed
                    }
                    else {
                        [void]$items.Add(@{ Path = $f.FullName; Show = (& $show $f.FullName); Console = $sys.Name; Kind = 'hidden'; Reason = 'Hidden in RetroBat''s game list (someone hid it).'; Fix = 'unhide'; To = $glPath; ToFolder = '' })
                    }
                }
                continue
            }
            if ($script:MgNotGames -contains $ext) { continue }
            if ($sys.Name -eq 'scummvm' -and @('.iso', '.bin', '.cue') -contains $ext) {
                [void]$items.Add(@{ Path = $f.FullName; Show = (& $show $f.FullName); Console = $sys.Name; Kind = 'scummvm'
                    Reason = 'A ScummVM disc needs a small .scummvm file beside it saying which game it is. Drag the disc onto _Wizard\Buttons\Add-ScummVM-Disc.bat and it makes one.'; Fix = ''; To = ''; ToFolder = '' })
                continue
            }
            $to = & $guess $f.FullName
            if ($null -ne $to -and $to.Name -eq $sys.Name) { $to = $null }
            [void]$items.Add(@{ Path = $f.FullName; Show = (& $show $f.FullName); Console = $sys.Name; Kind = 'wrongtype'
                Reason = $(if ($null -ne $to) { ("{0} does not read {1} files. It looks like a {2} game." -f $sys.FullName, $ext, $to.FullName) } else { ("{0} does not read {1} files{2}." -f $sys.FullName, $(if ($ext -eq '') { 'extension-less' } else { $ext }), $(if ($exts.Count -gt 0) { ' (it reads ' + (($exts | Select-Object -First 8) -join ' ') + $(if ($exts.Count -gt 8) { ' ...' } else { '' }) + ')' } else { '' })) })
                Fix = $(if ($null -ne $to) { 'move' } else { '' }); To = $(if ($null -ne $to) { [string]$to.Name } else { '' }); ToFolder = $(if ($null -ne $to) { [string]$to.Folder } else { '' }) })
        }
    }
    $res.Items = @($items)
    $fam = $(if ($res.Family -gt 0) { (' ({0} more hidden by family-friendly on purpose, not listed.)' -f $res.Family) } else { '' })
    $res.Message = $(if ($items.Count -eq 0) { ('Every game in {0} console folders shows in RetroBat.{1}' -f $res.Consoles, $fam) } else { ('{0} thing(s) RetroBat is not showing.{1}' -f $items.Count, $fam) })
    return $res
}

# One fix. Returns @{ Ok; Message }. RetroBat must be closed (the caller
# checks): it rewrites its game lists when it exits.
function Repair-MissingGame($Item) {
    $res = @{ Ok = $false; Message = '' }
    try {
        if ($Item.Fix -eq 'move') {
            $dir = [string]$Item.ToFolder
            if ($dir -eq '') { $res.Message = 'There is nowhere sure to move it.'; return $res }
            if (-not (Test-Path -LiteralPath $dir)) { [void](New-Item -ItemType Directory -Path $dir -Force) }
            $dest = Join-LibPath $dir ([System.IO.Path]::GetFileName([string]$Item.Path))
            if (Test-Path -LiteralPath $dest) { $res.Message = "The $($Item.To) folder already has a file with that name. Nothing was moved."; return $res }
            Move-Item -LiteralPath ([string]$Item.Path) -Destination $dest
            $res.Ok = $true; $res.Message = "Moved to roms\$(Split-Path $dir -Leaf)."
            return $res
        }
        if ($Item.Fix -eq 'unhide') {
            $gl = Join-LibPath (Split-Path ([string]$Item.Path) -Parent) 'gamelist.xml'
            # the game list is in the console folder, which may be higher up
            $p = Split-Path ([string]$Item.Path) -Parent
            while ($null -ne $p -and $p -ne '' -and -not (Test-Path -LiteralPath (Join-LibPath $p 'gamelist.xml'))) { $p = Split-Path $p -Parent }
            if ($null -eq $p -or $p -eq '') { $res.Message = 'Its game list was not found.'; return $res }
            $gl = Join-LibPath $p 'gamelist.xml'
            $utf8 = New-Object System.Text.UTF8Encoding($false)
            $t = [System.IO.File]::ReadAllText($gl, $utf8)
            $want = ([string]$Item.To).ToLower()
            $done = $false
            $out = [regex]::Replace($t, '<game\b[^>]*>.*?</game>', [System.Text.RegularExpressions.MatchEvaluator]{
                param($m)
                $g = $m.Value
                $pm = [regex]::Match($g, '<path>(.*?)</path>', 'Singleline')
                if (-not $pm.Success -or ([System.Net.WebUtility]::HtmlDecode($pm.Groups[1].Value).Trim()).ToLower() -ne $want) { return $g }
                $script:mgDone = $true
                return ([regex]::Replace($g, '[ \t]*<hidden>\s*true\s*</hidden>[ \t]*\r?\n?', '', 'IgnoreCase'))
            }, 'Singleline')
            $done = [bool]$script:mgDone; $script:mgDone = $false
            if (-not $done) { $res.Message = 'It is not hidden any more.'; $res.Ok = $true; return $res }
            $tmp = $gl + '.missing-tmp'
            [System.IO.File]::WriteAllText($tmp, $out, $utf8)
            Copy-Item -LiteralPath $tmp -Destination $gl -Force
            Remove-Item -LiteralPath $tmp -Force
            $res.Ok = $true; $res.Message = 'Shown again.'
            return $res
        }
        $res.Message = 'There is no fix for this one.'
    }
    catch { $res.Message = 'That did not work: ' + $_.Exception.Message }
    return $res
}
$script:mgDone = $false
