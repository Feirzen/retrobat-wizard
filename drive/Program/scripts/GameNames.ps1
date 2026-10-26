<#
    GameNames.ps1   (v1)
    ---------------------------------------------------------------------------
    WORKS OUT WHAT A SAVE'S GAME CODE ACTUALLY IS, and finds its artwork.

    Functions only, no side effects when dot-sourced. Used by the wizard's
    Saves tab and by Buttons\Browse My Saves.bat, both through
    SaveIndex.ps1.

    THE PROBLEM
      Nintendo names save data by an internal code. A GameCube save is
      "01-GKYE-..." , a Wii save lives in a folder called 534a5845, a 3DS save
      in one called 00055f00, a Wii U save in one called 10143500. A list of
      forty of those is unreadable.

    THE ANSWER IS ALREADY ON THE DRIVE
      Every one of these can be resolved from files that are already here, with
      no internet and no list typed out by hand that would go stale:

      | Console        | Where the code comes from                              |
      |----------------|--------------------------------------------------------|
      | GameCube, Wii  | the game file's own header, and Dolphin's gamelist.cache|
      | 3DS            | the media id at offset 0x108 of the .cci / .3ds         |
      | Wii U          | the title id in each game's meta\meta.xml               |

      The friendly NAME and the ARTWORK then come from RetroBat's own
      roms\<system>\gamelist.xml, so what the Saves tab shows is the same name
      and the same picture the game menu shows.

    WHAT IT WRITES
      Backups\Saves\game-names-found.txt, a plain text cache, one line per code:

          GKYE | Kirby Air Ride | roms\gamecube\images\kirby-air-ride.png

      It is REGENERATED, never hand edited. Hand written names go in
      game-name-shortcuts.txt next to it, and those always win. That split is
      deliberate: scraping or adding games refreshes this file by itself, and
      nothing anyone typed is ever overwritten.

    NO DRIVE LETTERS ANYWHERE
      Dolphin's cache stores full paths with a drive letter in them. Only the
      FILE NAME is ever read out of it. Everything written to the cache file is
      relative to the RetroBat folder.

    RULES HONOURED: Windows PowerShell 5.1, pure ASCII, no $PSScriptRoot inside
    param(), and the caller wraps list results in @().
#>

# ---------------------------------------------------------------------------
#  RetroBat's own game lists: file name -> name and artwork
# ---------------------------------------------------------------------------
#  gamelist.xml holds <path>./Some Game.iso</path>, <name>, and <image>, with
#  paths relative to that system's rom folder. Matching on the FILE NAME only
#  keeps this working no matter where the drive is mounted.
# ---------------------------------------------------------------------------
function Read-RomGameList {
    param([string] $Root, [string] $System)

    $map = @{}
    $listPath = Join-Path (Join-Path (Join-Path $Root 'roms') $System) 'gamelist.xml'
    if (-not (Test-Path -LiteralPath $listPath)) { return $map }

    try {
        [xml]$xml = Get-Content -LiteralPath $listPath -Raw -ErrorAction Stop
    }
    catch { return $map }

    foreach ($g in @($xml.gameList.game)) {
        if (-not $g) { continue }
        $p = [string]$g.path
        if (-not $p) { continue }
        $clean = ($p -replace '/', '\') -replace '^\.\\', ''
        $leaf  = Split-Path $clean -Leaf
        if (-not $leaf) { continue }

        $img = [string]$g.image
        $rel = ''
        if ($img) {
            # './images/x.png' -> 'roms\<system>\images\x.png'
            $rel = 'roms\{0}\{1}' -f $System, (($img -replace '^\./', '') -replace '/', '\')
        }
        $entry = [pscustomobject]@{
            Name  = [string]$g.name
            Image = $rel
            Leaf  = $leaf
        }
        if (-not $map.ContainsKey($leaf.ToLower())) { $map[$leaf.ToLower()] = $entry }

        # A Wii U game that is a decrypted FOLDER is listed by the .rpx file
        # buried inside it, for example
        #   ./Twilight Princess HD [AZAP01]/Twilight Princess HD [AZAP01]/code/Zelda.rpx
        # so the leaf is "Zelda.rpx" and matching on it finds nothing. The
        # TOP folder is what the rest of this script has in hand, so register
        # that as a key too. Found 2026-08-29 by reading the real gamelist.
        $first = ($clean -split '\\')[0]
        if ($first -and $first -ne $leaf -and -not $map.ContainsKey($first.ToLower())) {
            $map[$first.ToLower()] = $entry
        }
    }
    return $map
}

# ---------------------------------------------------------------------------
#  A name reduced to something comparable
# ---------------------------------------------------------------------------
#  "Pokemon XD : Gale of Darkness" and "Pokemon XD - Gale of Darkness" are the
#  same game. Punctuation and case are dropped so the two match.
# ---------------------------------------------------------------------------
function ConvertTo-NameKey {
    param([string] $Name = '')
    if (-not $Name) { return '' }
    return (($Name.ToLower()) -replace '[^a-z0-9]', '')
}


# ---------------------------------------------------------------------------
#  The games on one console that no save has been matched to yet
# ---------------------------------------------------------------------------
#  A save still showing a bare code is one whose game could not be worked out
#  from anything on this drive. The one thing that IS known about it is which
#  console it belongs to, and that console's gamelist.xml is a short list of
#  real names. Offering that list is far kinder than an empty text box, and it
#  keeps this project's rule intact: every name still comes from a file on
#  this drive or from a line somebody typed, never from a guess.
#
#  $UsedNames is the names already showing against a save on that console, so
#  what comes back is only what is still unaccounted for.
#
#  Returns plainly, so the CALLER wraps it in @() - the convention used
#  everywhere here. A function that returns an empty array returns nothing at
#  all, and $null.Count is not 0.
# ---------------------------------------------------------------------------
function Get-UnmatchedGameNames {
    param([string] $Root = '', [string] $System = '', [string[]] $UsedNames = @())

    $out = @()
    if (-not $Root -or -not $System) { return $out }

    $used = @{}
    foreach ($n in @($UsedNames)) {
        $k = ConvertTo-NameKey $n
        if ($k) { $used[$k] = $true }
    }

    $map = $null
    try { $map = Read-RomGameList -Root $Root -System $System } catch { return $out }
    if ($null -eq $map) { return $out }

    # The same entry is registered under more than one key in that map (a
    # Wii U folder game is filed under both its .rpx leaf and its top folder),
    # so the same name can come round twice. $seen catches that.
    $seen = @{}
    foreach ($e in @($map.Values)) {
        $n = [string]$e.Name
        if (-not $n) { continue }
        $k = ConvertTo-NameKey $n
        if (-not $k) { continue }
        if ($used.ContainsKey($k)) { continue }
        if ($seen.ContainsKey($k)) { continue }
        $seen[$k] = $true
        $out += $n
    }

    return ($out | Sort-Object)
}


# ---------------------------------------------------------------------------
#  GameCube and Wii: the game id out of the game file itself
# ---------------------------------------------------------------------------
#  Six characters at the very start of the disc, with a magic number a little
#  further in that proves it really is a disc and not a coincidence.
#
#    .iso .gcm .nkit.iso   the disc starts at byte 0
#    .wbfs               a 0x200 byte wrapper, then the disc
#    .ciso               a 0x8000 byte header, then the disc
#    .rvz .wia           COMPRESSED. Cannot be read this way, which is what
#                        Dolphin's cache below is for.
# ---------------------------------------------------------------------------
function Get-DiscGameId {
    param([string] $Path)

    $offsets = @(0, 0x200, 0x8000)
    $fs = $null
    try {
        $fs = [System.IO.File]::Open($Path, 'Open', 'Read', 'ReadWrite')
        foreach ($off in $offsets) {
            if ($fs.Length -lt ($off + 0x20)) { continue }
            $buf = New-Object byte[] 0x20
            [void]$fs.Seek($off, 'Begin')
            if ($fs.Read($buf, 0, 0x20) -lt 0x20) { continue }

            $id = ''
            $ok = $true
            for ($i = 0; $i -lt 6; $i++) {
                $c = $buf[$i]
                if (-not (($c -ge 48 -and $c -le 57) -or ($c -ge 65 -and $c -le 90))) { $ok = $false; break }
                $id += [char]$c
            }
            if (-not $ok) { continue }

            # Wii magic 5D 1C 9E A3 at +0x18, GameCube magic C2 33 9F 3D at +0x1C
            $wii = ($buf[0x18] -eq 0x5D -and $buf[0x19] -eq 0x1C -and $buf[0x1A] -eq 0x9E -and $buf[0x1B] -eq 0xA3)
            $gc  = ($buf[0x1C] -eq 0xC2 -and $buf[0x1D] -eq 0x33 -and $buf[0x1E] -eq 0x9F -and $buf[0x1F] -eq 0x3D)
            if ($wii -or $gc) { return $id }
        }
    }
    catch { return '' }
    finally { if ($fs) { $fs.Dispose() } }
    return ''
}

# ---------------------------------------------------------------------------
#  Dolphin's own cache, which knows the compressed formats too
# ---------------------------------------------------------------------------
#  emulators\dolphin-emu\User\Cache\gamelist.cache is Dolphin's private binary
#  index of every game it has scanned, .rvz and .ciso included, which is
#  exactly the set the header reader above cannot handle.
#
#  Its format is undocumented and could change, so this does not try to parse
#  it properly. It pulls the readable text out and uses the ONE thing that is
#  stable: each game's file path is followed, a few strings later, by its six
#  character game id. Pairing those two is enough.
#
#  It is a suggestion source, never the authority. Anything it produces that
#  does not correspond to a game code actually in the save backup is thrown
#  away, so a wrong guess cannot reach the screen. And the cache is Dolphin's,
#  so it may be absent on a computer where Dolphin has not run yet; everything
#  still works, those games just stay as codes until Dolphin has seen them.
# ---------------------------------------------------------------------------
function Get-DolphinCacheIds {
    param([string] $Root)

    $pairs = @{}
    $cache = Join-Path $Root 'emulators\dolphin-emu\User\Cache\gamelist.cache'
    if (-not (Test-Path -LiteralPath $cache)) { return $pairs }

    try {
        $bytes = [System.IO.File]::ReadAllBytes($cache)
        # Latin-1 maps every byte to one character, so no byte is lost or
        # merged, which is what makes a plain regex safe over binary here.
        $text  = [System.Text.Encoding]::GetEncoding(28591).GetString($bytes)
    }
    catch { return $pairs }

    $lastLeaf = ''
    foreach ($m in [regex]::Matches($text, '[\x20-\x7E]{4,}')) {
        $s = $m.Value.Trim()

        # A path or file name for a disc image. Only the LEAF is kept - the
        # cache stores the full path with the drive letter Dolphin last saw.
        if ($s -match '\.(iso|gcm|wbfs|rvz|wia|ciso|gcz|wad|nkit\.iso)[^A-Za-z0-9]*$') {
            $leaf = Split-Path ($s -replace '/', '\') -Leaf
            # Dolphin writes stray bytes around some strings; trim anything
            # after the extension.
            if ($leaf -match '^(.*\.(?:iso|gcm|wbfs|rvz|wia|ciso|gcz|wad))') { $leaf = $Matches[1] }

            # A leaf that is not plausibly a file name means the text scan
            # landed in the middle of something binary. Seen for real on
            # 2026-08-29: one game paired with the single character "<".
            # Forgetting it is right - pairing an id with the WRONG game would
            # put a wrong name on somebody's save, and that is far worse than
            # leaving that one as a code. It resolves from its own file header
            # anyway unless it is a compressed format.
            if ($leaf.Length -lt 6 -or $leaf -notmatch '\.[A-Za-z0-9]{2,8}$') { $lastLeaf = ''; continue }

            $lastLeaf = $leaf
            continue
        }

        if ($lastLeaf -and $s -match '^[A-Z0-9]{6}$') {
            $code = $s.Substring(0, 4)
            if (-not $pairs.ContainsKey($code)) { $pairs[$code] = $lastLeaf }
            $lastLeaf = ''
        }
    }
    return $pairs
}

# ---------------------------------------------------------------------------
#  3DS: the media id in the cartridge header
# ---------------------------------------------------------------------------
#  A .cci / .3ds is an NCSD image: magic "NCSD" at 0x100, and the 64 bit title
#  id at 0x108, little endian. Azahar stores that game's save under the low
#  eight hex digits of it, so 0004000000055F00 becomes the folder 00055f00.
# ---------------------------------------------------------------------------
function Get-3dsTitleId {
    param([string] $Path)

    $fs = $null
    try {
        $fs = [System.IO.File]::Open($Path, 'Open', 'Read', 'ReadWrite')
        if ($fs.Length -lt 0x110) { return '' }
        $buf = New-Object byte[] 0x10
        [void]$fs.Seek(0x100, 'Begin')
        if ($fs.Read($buf, 0, 0x10) -lt 0x10) { return '' }
        if ($buf[0] -ne 0x4E -or $buf[1] -ne 0x43 -or $buf[2] -ne 0x53 -or $buf[3] -ne 0x44) { return '' }  # NCSD
        # bytes 8..11 of the buffer are the low half of the title id
        return ('{0:X2}{1:X2}{2:X2}{3:X2}' -f $buf[11], $buf[10], $buf[9], $buf[8])
    }
    catch { return '' }
    finally { if ($fs) { $fs.Dispose() } }
}

# ---------------------------------------------------------------------------
#  Wii U: the title id in each game's meta\meta.xml
# ---------------------------------------------------------------------------
#  A decrypted Wii U game folder carries meta\meta.xml with <title_id>. Cemu
#  stores that game's save under the low eight hex digits of it. If a game is
#  not present as a folder, the save's OWN meta\meta.xml is used as a fallback,
#  because Cemu copies one in next to every save it creates.
# ---------------------------------------------------------------------------
function Get-WiiUTitleId {
    param([string] $MetaXmlPath)

    try {
        $raw = Get-Content -LiteralPath $MetaXmlPath -Raw -ErrorAction Stop
        if ($raw -match '<title_id[^>]*>\s*([0-9a-fA-F]{16})\s*</title_id>') {
            return $Matches[1].Substring(8).ToUpper()
        }
    }
    catch { }
    return ''
}

function Get-WiiUMetaName {
    param([string] $MetaXmlPath)

    try {
        $raw = Get-Content -LiteralPath $MetaXmlPath -Raw -ErrorAction Stop
        foreach ($tag in @('longname_en', 'shortname_en')) {
            if ($raw -match ('<{0}[^>]*>([^<]+)</{0}>' -f $tag)) {
                $n = $Matches[1]
                $n = $n -replace '&apos;', "'" -replace '&amp;', '&' -replace '&quot;', '"'
                $n = ($n -replace '\s+', ' ').Trim()
                if ($n) { return $n }
            }
        }
    }
    catch { }
    return ''
}

# ---------------------------------------------------------------------------
#  Cemu's own title list, which knows the games it cannot read a header from
# ---------------------------------------------------------------------------
#  emulators\cemu\portable\title_list_cache.xml is Cemu's index of every Wii U
#  game it has seen, and unlike Dolphin's it is plain XML:
#
#      <title titleId="0005000010143500" ...>
#        <name>THE LEGEND OF ZELDA The Wind Waker HD</name>
#        <path>...\roms\wiiu\The Legend of Zelda - The Wind Waker HD</path>
#
#  That matters because a .wux is an encrypted disc image whose title id
#  cannot be read directly, so those saves have no other honest source. The
#  <path> is used only for its LAST SEGMENT, to look the game up in
#  gamelist.xml for a tidier name and its box art; the paths in that file
#  carry whatever drive letter Cemu last saw and are never used as paths.
# ---------------------------------------------------------------------------
function Get-CemuTitleList {
    param([string] $Root)

    $out = @()
    $cache = Join-Path $Root 'emulators\cemu\portable\title_list_cache.xml'
    if (-not (Test-Path -LiteralPath $cache)) { return $out }

    try { [xml]$xml = Get-Content -LiteralPath $cache -Raw -ErrorAction Stop }
    catch { return $out }

    foreach ($t in @($xml.title_list.title)) {
        if (-not $t) { continue }
        $tid = [string]$t.titleId
        if ($tid -notmatch '^[0-9a-fA-F]{16}$') { continue }
        # Only base games. 0005000E is an update and 0005000C is DLC, and
        # neither has its own save folder.
        if ($tid.Substring(0, 8).ToUpper() -ne '00050000') { continue }

        $leaf = ''
        $p = [string]$t.path
        if ($p) { $leaf = Split-Path ($p -replace '/', '\').TrimEnd('\') -Leaf }

        $out += [pscustomobject]@{
            Code = $tid.Substring(8).ToUpper()
            Name = ([string]$t.name -replace '\s+', ' ').Trim()
            Leaf = $leaf
        }
    }
    return $out
}

# ---------------------------------------------------------------------------
#  Build the whole lookup
# ---------------------------------------------------------------------------
#  Returns a hashtable of CODE -> @{ Name; Image }, where CODE is upper case
#  and is exactly what appears as a save's GameId: four letters for GameCube
#  and Wii, eight hex characters for 3DS and Wii U.
# ---------------------------------------------------------------------------
function Build-GameNameLookup {
    param([string] $Root)

    $found = @{}
    function Add-Found([string]$Code, [string]$Name, [string]$Image) {
        if (-not $Code -or -not $Name) { return }
        $k = $Code.ToUpper()
        # First writer wins, and the sources are ordered best first.
        if (-not $found.ContainsKey($k)) {
            $found[$k] = [pscustomobject]@{ Name = $Name; Image = $Image }
        }
    }

    # --- GameCube and Wii ---------------------------------------------------
    # Formats whose disc header can be read straight off the file. .rvz, .wia
    # and .gcz are COMPRESSED, so their first bytes are the archive's own
    # header, not the disc's - they are deliberately not attempted here and are
    # picked up from Dolphin's cache instead. .wad is not a disc at all.
    $headerExt = @('.iso', '.gcm', '.wbfs', '.ciso')
    # Read Dolphin's cache ONCE. It is 750 KB; reading it per game code, which
    # an earlier draft did, turned a one second job into a minute.
    $dolphin = Get-DolphinCacheIds -Root $Root
    foreach ($sys in @('gamecube', 'wii')) {
        $list    = Read-RomGameList -Root $Root -System $sys
        $romsDir = Join-Path (Join-Path $Root 'roms') $sys
        if (-not (Test-Path -LiteralPath $romsDir)) { continue }

        # Pass 1: read the id straight out of every game file that allows it.
        foreach ($f in @(Get-ChildItem -LiteralPath $romsDir -File -ErrorAction SilentlyContinue)) {
            if ($headerExt -notcontains $f.Extension.ToLower()) { continue }
            $id = Get-DiscGameId $f.FullName
            if (-not $id) { continue }
            $entry = $list[$f.Name.ToLower()]
            $name  = if ($entry) { $entry.Name } else { [System.IO.Path]::GetFileNameWithoutExtension($f.Name) }
            $img   = if ($entry) { $entry.Image } else { '' }
            Add-Found $id.Substring(0, 4) $name $img
        }

        # Pass 2: Dolphin's cache, for the compressed formats pass 1 skipped.
        foreach ($code in @($dolphin.Keys)) {
            $leaf = $dolphin[$code]
            if (-not $leaf) { continue }
            $entry = $list[$leaf.ToLower()]
            if (-not $entry) { continue }
            Add-Found $code $entry.Name $entry.Image
        }
    }

    # --- 3DS ----------------------------------------------------------------
    $list3   = Read-RomGameList -Root $Root -System '3ds'
    $roms3   = Join-Path (Join-Path $Root 'roms') '3ds'
    if (Test-Path -LiteralPath $roms3) {
        foreach ($f in @(Get-ChildItem -LiteralPath $roms3 -File -ErrorAction SilentlyContinue)) {
            if (@('.cci', '.3ds', '.cxi') -notcontains $f.Extension.ToLower()) { continue }
            $tid = Get-3dsTitleId $f.FullName
            if (-not $tid) { continue }
            $entry = $list3[$f.Name.ToLower()]
            $name  = if ($entry) { $entry.Name } else { [System.IO.Path]::GetFileNameWithoutExtension($f.Name) }
            $img   = if ($entry) { $entry.Image } else { '' }
            Add-Found $tid $name $img
        }
    }

    # --- Wii U --------------------------------------------------------------
    $listU = Read-RomGameList -Root $Root -System 'wiiu'
    $romsU = Join-Path (Join-Path $Root 'roms') 'wiiu'
    if (Test-Path -LiteralPath $romsU) {
        foreach ($d in @(Get-ChildItem -LiteralPath $romsU -Directory -ErrorAction SilentlyContinue)) {
            $meta = Join-Path $d.FullName 'meta\meta.xml'
            if (-not (Test-Path -LiteralPath $meta)) { continue }
            $tid = Get-WiiUTitleId $meta
            if (-not $tid) { continue }
            $entry = $listU[$d.Name.ToLower()]
            $name  = if ($entry) { $entry.Name } else { Get-WiiUMetaName $meta }
            if (-not $name) { $name = $d.Name }
            $img   = if ($entry) { $entry.Image } else { '' }
            Add-Found $tid $name $img
        }
    }
    # Cemu's own list, which covers the .wux games whose title id cannot be
    # read from the file. Runs after the rom folders (whose meta.xml is the
    # most direct evidence) and before the save-side fallback.
    foreach ($t in @(Get-CemuTitleList -Root $Root)) {
        $entry = $null
        if ($t.Leaf) { $entry = $listU[$t.Leaf.ToLower()] }
        if ($entry) { Add-Found $t.Code $entry.Name $entry.Image }
        else        { Add-Found $t.Code $t.Name '' }
    }

    # Fallback: the meta.xml Cemu drops next to every save it makes. Lower
    # quality (several Zelda games just call themselves "THE LEGEND OF ZELDA")
    # which is why it runs last and only fills in what is still missing.
    $saveU = Join-Path $Root 'saves\wiiu\cemu\mlc01\usr\save\00050000'
    if (Test-Path -LiteralPath $saveU) {
        foreach ($d in @(Get-ChildItem -LiteralPath $saveU -Directory -ErrorAction SilentlyContinue)) {
            $meta = Join-Path $d.FullName 'meta\meta.xml'
            if (-not (Test-Path -LiteralPath $meta)) { continue }
            Add-Found $d.Name (Get-WiiUMetaName $meta) ''
        }
    }

    # --- Everything else: the save is named after the rom ------------------
    #  N64, DS, GBA, GBC, arcade and the like keep one save file named after
    #  the game, so the "code" is already the rom's file name. Registering
    #  every rom by its base name therefore gets those a tidy name and box art
    #  too, for free: "Banjo-Kazooie (USA) (Rev 1)" becomes "Banjo-Kazooie".
    #
    #  These keys are long text, never four letters or eight hex digits, so
    #  they cannot collide with a real game code.
    $romsRoot = Join-Path $Root 'roms'
    if (Test-Path -LiteralPath $romsRoot) {
        foreach ($sysDir in @(Get-ChildItem -LiteralPath $romsRoot -Directory -ErrorAction SilentlyContinue)) {
            $list = Read-RomGameList -Root $Root -System $sysDir.Name
            foreach ($k in @($list.Keys)) {
                $e = $list[$k]
                if (-not $e.Name) { continue }
                $base = [System.IO.Path]::GetFileNameWithoutExtension($e.Leaf)
                # ".nkit.iso" and the like leave a second extension behind
                $base = $base -replace '\.nkit$', ''
                if (-not $base) { continue }
                Add-Found $base $e.Name $e.Image
            }
        }
    }

    return $found
}

# ---------------------------------------------------------------------------
#  The cache file
# ---------------------------------------------------------------------------

function Get-GameNameCachePath {
    param([string] $BackupRoot)
    return (Join-Path $BackupRoot 'game-names-found.txt')
}

function Read-GameNameCache {
    param([string] $CachePath, [string] $Root)

    $map = @{}
    if (-not (Test-Path -LiteralPath $CachePath)) { return $map }
    foreach ($line in @(Get-Content -LiteralPath $CachePath -Encoding UTF8 -ErrorAction SilentlyContinue)) {
        $t = "$line".Trim()
        if (-not $t -or $t.StartsWith('#')) { continue }
        $parts = $t -split '\|'
        if ($parts.Count -lt 2) { continue }
        $code = $parts[0].Trim().ToUpper()
        $name = $parts[1].Trim()
        $img  = if ($parts.Count -ge 3) { $parts[2].Trim() } else { '' }
        if (-not $code -or -not $name) { continue }
        $full = ''
        if ($img) { $full = Join-Path $Root $img }
        $map[$code] = [pscustomobject]@{ Name = $name; Image = $img; ImageFull = $full }
    }
    return $map
}

function Write-GameNameCache {
    param([string] $CachePath, [hashtable] $Lookup)

    $out = @(
        '# ---------------------------------------------------------------------------'
        '#  FOUND AUTOMATICALLY. DO NOT EDIT THIS FILE.'
        '# ---------------------------------------------------------------------------'
        '#  It is rebuilt from the game files on this drive, RetroBat''s own'
        '#  gamelist.xml files, and Dolphin''s game cache. Anything you type in here'
        '#  will be wiped the next time it is rebuilt.'
        '#'
        '#  To name something yourself, or to correct one of these, use'
        '#  game-name-shortcuts.txt next to this file. That one is yours, it is never'
        '#  overwritten, and it always wins over anything here.'
        '#'
        ('#  Rebuilt {0}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm'))
        '#'
        '#  code | name | picture (relative to the RetroBat folder, never a drive letter)'
        '# ---------------------------------------------------------------------------'
        ''
    )
    foreach ($code in ($Lookup.Keys | Sort-Object)) {
        $e = $Lookup[$code]
        $out += ('{0} | {1} | {2}' -f $code, $e.Name, $e.Image)
    }
    try {
        # UTF8, not ASCII: real game names carry accents (this drive has two
        # Pokemon titles with an accented e), and ASCII would turn them into
        # question marks. PowerShell 5.1 writes a byte-order mark here, and
        # everything that reads this file passes -Encoding UTF8, which is what
        # stops the same file being read back as ANSI later. Note this is a
        # DATA file - the pure-ASCII rule on this drive is about .ps1 scripts,
        # which PowerShell reads as ANSI when they have no mark.
        Set-Content -LiteralPath $CachePath -Value $out -Encoding UTF8 -ErrorAction Stop
        return $true
    }
    catch { return $false }
}

# Rebuilds the cache if it is missing, older than $MaxAgeDays, or older than
# any gamelist.xml (which changes when games are added or re-scraped).
# Returns $true if it rebuilt.
function Update-GameNameCache {
    param(
        [string] $Root,
        [string] $BackupRoot,
        [int]    $MaxAgeDays = 30,
        [switch] $Force
    )

    $cachePath = Get-GameNameCachePath $BackupRoot
    $needed = $Force -or (-not (Test-Path -LiteralPath $cachePath))

    if (-not $needed) {
        try {
            $cacheTime = (Get-Item -LiteralPath $cachePath).LastWriteTimeUtc
            if ((Get-Date).ToUniversalTime().AddDays(-$MaxAgeDays) -gt $cacheTime) { $needed = $true }
            if (-not $needed) {
                $romsDir = Join-Path $Root 'roms'
                foreach ($gl in @(Get-ChildItem -LiteralPath $romsDir -Filter 'gamelist.xml' -Recurse -File -ErrorAction SilentlyContinue)) {
                    if ($gl.LastWriteTimeUtc -gt $cacheTime) { $needed = $true; break }
                }
            }
        }
        catch { $needed = $true }
    }

    if (-not $needed) { return $false }

    $lookup = Build-GameNameLookup -Root $Root
    [void](Write-GameNameCache -CachePath $cachePath -Lookup $lookup)
    return $true
}
