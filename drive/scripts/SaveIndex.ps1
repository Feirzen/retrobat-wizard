<#
    SaveIndex.ps1   (v1)
    ---------------------------------------------------------------------------
    THE SAVES ENGINE. Functions only, no side effects when dot-sourced, exactly
    like ProfileEngine.ps1. It is used by two front ends:

        scripts\Show-SaveHistory.ps1      the console version, on a button
        wizard\SetupWizard.ps1            the Saves tab

    WHAT IT IS FOR
      Backup-RetroBatSaves.ps1 keeps every version of every save file. That is
      the right thing to store and the wrong thing to READ, because it tracks
      about 1500 files and only about 80 of them are what a person would call
      "a save". The rest are Wii NAND, 3DS NAND and arcade NVRAM.

      This engine turns that pile into a list of GAMES, and lets a whole game
      be put back from one moment in time in one go.

    WHY IT READS index.json AND NOT THE FOLDERS
      Walking SaveBackups\Versions\ takes tens of seconds on a USB drive - the
      wii and 3ds folders alone hold thousands of entries. index.json already
      lists every tracked file and where its newest version went, in one read.
      A game's full history is then read from that game's own history folders,
      only when someone actually opens it. Instant list, cheap detail.

    THE DRIVE LETTER TRAP, AGAIN
      Until 2026-08-29 index.json stored version paths as full paths starting
      with a drive letter. On any machine that is not the one that wrote them,
      every single one of those paths is wrong. Resolve-VersionPath below
      copes with both shapes, and Backup-RetroBatSaves.ps1 now writes the
      relative shape. Never build an absolute path in here.

    RULES HONOURED: no drive letters, Windows PowerShell 5.1, pure ASCII,
    no $PSScriptRoot inside param().
#>

# ---------------------------------------------------------------------------
#  A NOTE ON HOW THESE FUNCTIONS RETURN LISTS
# ---------------------------------------------------------------------------
#  Every function below that returns a list returns it PLAINLY, which means an
#  empty list comes back as nothing at all. That is PowerShell's behaviour and
#  the customization record already warns about it: $null.Count is not 0.
#
#  So the rule for anything calling these is the project's existing one -
#  WRAP THE CALL IN @() BEFORE COUNTING OR INDEXING IT:
#
#      $versions = @(Get-SaveFileVersions $VersionRoot $rel)
#      if ($versions.Count -eq 0) { ... }
#
#  The tempting alternative, "return ,$out" to force an array out, was tried
#  on 2026-08-29 and is WRONG here: a caller that then also wraps it in @()
#  ends up with a list containing one item, which is the real list. The count
#  is 1 no matter how many versions there are, and nothing errors. One
#  convention, used everywhere, beats two that quietly disagree.
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
#  Reading the index
# ---------------------------------------------------------------------------

# Returns a hashtable of  relative save path -> entry object (s, m, h, v).
# Returns an EMPTY hashtable rather than $null if there is no index yet, so
# callers never have to test for $null before using it.
function Read-SaveIndex {
    param([string] $IndexPath)

    $table = @{}
    if (-not $IndexPath -or -not (Test-Path -LiteralPath $IndexPath)) { return $table }
    try {
        $raw = Get-Content -LiteralPath $IndexPath -Raw -ErrorAction Stop
        if (-not $raw) { return $table }
        ($raw | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $table[$_.Name] = $_.Value }
    }
    catch { return @{} }
    return $table
}

# The version path stored in the index may be either shape:
#   new  Versions-relative   wii\...\00000000_app\2026-08-20_114317_20591cf0__00000000.app
#   old  a full path         R:\RetroBat\_ClaudeWorkspace\SaveBackups\Versions\wii\...
# An old entry is salvaged by cutting everything up to and including
# "\Versions\", which is drive-letter proof. Anything else comes back empty
# rather than pointing at a file on a drive that is not there.
function Resolve-VersionPath {
    param([string] $VersionRoot, [string] $Stored)

    if (-not $Stored) { return '' }
    if ($Stored -match '^[A-Za-z]:\\' -or $Stored -match '^\\\\') {
        $i = $Stored.IndexOf('\Versions\')
        if ($i -lt 0) { return '' }
        $Stored = $Stored.Substring($i + 10)
    }
    return (Join-Path $VersionRoot $Stored)
}

# Where one save file's version history lives. Must match the folder naming
# in Backup-RetroBatSaves.ps1 exactly: every dot in the file name becomes an
# underscore, so "00000000.app" is stored under "00000000_app".
function Get-SaveHistoryDir {
    param([string] $VersionRoot, [string] $Rel)

    $relDir = Split-Path $Rel -Parent
    $leaf   = Split-Path $Rel -Leaf
    $safe   = $leaf -replace '\.', '_'
    if ($relDir) { return (Join-Path (Join-Path $VersionRoot $relDir) $safe) }
    return (Join-Path $VersionRoot $safe)
}

# ---------------------------------------------------------------------------
#  Friendly names
# ---------------------------------------------------------------------------

# game-name-shortcuts.txt, one "name = code" per line. It has always been the
# place a human writes down that GKYE means Kirby Air Ride. This reads it into
# code -> first name given for that code, and remembers every name as a search
# term. Codes are compared in UPPER case; the 3DS and Wii U ids in the file
# may be written in either case.
function Read-GameNames {
    param([string] $NamesPath)

    $map = @{}
    if (-not $NamesPath -or -not (Test-Path -LiteralPath $NamesPath)) { return $map }
    foreach ($line in @(Get-Content -LiteralPath $NamesPath -ErrorAction SilentlyContinue)) {
        $t = "$line".Trim()
        if (-not $t -or $t.StartsWith('#') -or $t -notmatch '=') { continue }
        $name = ($t -split '=', 2)[0].Trim()
        $code = ($t -split '=', 2)[1].Trim().ToUpper()
        if (-not $name -or -not $code) { continue }
        if (-not $map.ContainsKey($code)) { $map[$code] = $name }
    }
    return $map
}

# Wii stores a game's save under a folder named with the game's four letter
# code written in hex: 534a5845 is "SJXE". Anything that does not decode to
# plain printable text is handed back as the raw hex instead of guessed at.
function ConvertFrom-HexCode {
    param([string] $Hex)

    if ($Hex -notmatch '^[0-9a-fA-F]{8}$') { return $Hex }
    $out = ''
    for ($i = 0; $i -lt 8; $i += 2) {
        $b = [Convert]::ToInt32($Hex.Substring($i, 2), 16)
        if ($b -lt 32 -or $b -gt 126) { return $Hex.ToUpper() }
        $out += [char]$b
    }
    return $out
}

# ---------------------------------------------------------------------------
#  Which game does a file belong to?
# ---------------------------------------------------------------------------
#  Returns: System, GameId, Kind ('name' = already readable, 'code' = an id
#  that wants a friendly name), Category, and Why (shown for system files).
#
#  THERE ARE THREE CATEGORIES, not two, and the third one was added after
#  running this against the real drive on 2026-08-29:
#
#    game    a save a person made by playing a game. About 35 of them here.
#    arcade  the little memory chip an arcade board keeps. Technically one per
#            game, but reicast writes one for EVERY rom in the set, so there
#            are nearly 200, all created on the same day and all the same
#            size. Left in with the games, they buried the 35 that matter, so
#            they get their own category and are off by default.
#    system  Wii and 3DS internal memory, and emulator settings files. Over a
#            thousand of them here.
#
#  EVERY RULE BELOW WAS READ OFF THE REAL DRIVE, not guessed. When a rule does
#  not match, the file is called a system file rather than invented into a
#  game. Nothing is ever hidden - the front ends have a switch that shows
#  everything - it is only sorted.
# ---------------------------------------------------------------------------

$script:SaveDataExtensions = @(
    'srm','sav','dsv','eep','fla','mpk','sra','rtc','bsv','sram','mcr','mcd','gme','nvm'
)

# ---------------------------------------------------------------------------
#  Saves that live OUTSIDE saves\   (2026-10-11)
# ---------------------------------------------------------------------------
#  The PC ports keep their saves next to their own program, not in saves\.
#  Backup-RetroBatSaves.ps1 copies these too, filed as '<system>\_port\<file>'
#  in the index and in Versions\, and putting one back goes to its real
#  folder (Resolve-SaveTarget). A folder that does not exist is skipped.
$script:SaveExtraRoots = @(
    @{ System = 'soh';       Dir = 'emulators\soh\Save';        Name = 'Ship of Harkinian' }
    @{ System = '2ship';     Dir = 'emulators\2ship\Save';      Name = '2 Ship 2 Harkinian' }
    @{ System = '2ship';     Dir = 'emulators\2ship\saves';     Name = '2 Ship 2 Harkinian' }
    @{ System = 'starship';  Dir = 'emulators\starship\Save';   Name = 'Starship' }
    @{ System = 'ghostship'; Dir = 'emulators\ghostship\Save';  Name = 'Ghostship' }
)

# Where a backed-up file really lives: saves\<rel>, or the port's own folder.
function Resolve-SaveTarget([string]$SavesRoot, [string]$Rel) {
    if ($Rel -match '^([^\\]+)\\_port\\(.+)$') {
        $sys = $Matches[1]; $rest = $Matches[2]
        $rb = Split-Path $SavesRoot -Parent
        foreach ($x in $script:SaveExtraRoots) {
            if ($x.System -ne $sys) { continue }
            $d = Join-Path $rb $x.Dir
            if (Test-Path -LiteralPath $d) { return (Join-Path $d $rest) }
        }
        foreach ($x in $script:SaveExtraRoots) { if ($x.System -eq $sys) { return (Join-Path (Join-Path $rb $x.Dir) $rest) } }
    }
    return (Join-Path $SavesRoot $Rel)
}

function Get-SaveGroupInfo {
    param([string] $Rel)

    $parts  = $Rel -split '\\'
    $system = $parts[0]
    $leaf   = $parts[$parts.Count - 1]

    $r = [ordered]@{
        System = $system; GameId = ''; Kind = 'code'; Category = 'system'; Why = ''
    }

    # a PC port's own save folder: one game per port
    if ($parts.Count -ge 3 -and $parts[1] -eq '_port') {
        $nm = @($script:SaveExtraRoots | Where-Object { $_.System -eq $system } | ForEach-Object { $_.Name })
        $r.GameId = $(if ($nm.Count -gt 0) { $nm[0] } else { $system }); $r.Kind = 'name'; $r.Category = 'game'
        return $r
    }

    switch ($system) {

        'gamecube' {
            # 01-GKYE-KA030621_0100_T030529_2154.gci  ->  GKYE
            if ($leaf -match '^\d+-([A-Za-z0-9]{4})-') {
                $r.GameId = $Matches[1].ToUpper(); $r.Category = 'game'; return $r
            }
            # A whole memory card image holds every GameCube game at once.
            if ($leaf -match '^(MemoryCard[AB])\.([A-Za-z]+)\.raw$') {
                $r.GameId = '{0} {1}' -f $Matches[1], $Matches[2].ToUpper()
                $r.Kind = 'name'; $r.Category = 'game'; return $r
            }
            $r.Why = 'Dolphin setting'; return $r
        }

        'wii' {
            # Disc and channel saves:  ...\title\0001000X\<code in hex>\data\...
            # 00000001 is the console's own system titles (IOS), never a game.
            if ($Rel -match '\\title\\0001000[0-9a-fA-F]\\([0-9a-fA-F]{8})\\data(\\|$)') {
                $r.GameId = (ConvertFrom-HexCode $Matches[1]); $r.Category = 'game'; return $r
            }
            $r.Why = 'Wii system memory'; return $r
        }

        '3ds' {
            # Real saves are on the emulated SD card, never in the NAND.
            # ...\sdmc\Nintendo 3DS\<32 hex>\<32 hex>\title\00040000\<id>\data\...
            if ($Rel -match '\\sdmc\\.*\\title\\[0-9a-fA-F]{8}\\([0-9a-fA-F]{8})\\data(\\|$)') {
                $r.GameId = $Matches[1].ToUpper(); $r.Category = 'game'; return $r
            }
            $r.Why = '3DS system memory'; return $r
        }

        'wiiu' {
            # ...\mlc01\usr\save\00050000\<title id>\...
            if ($Rel -match '\\usr\\save\\[0-9a-fA-F]{8}\\([0-9a-fA-F]{8})(\\|$)') {
                $r.GameId = $Matches[1].ToUpper(); $r.Category = 'game'; return $r
            }
            $r.Why = 'Cemu system file'; return $r
        }

        default {
            # Arcade boards keep a small memory file per ROM, and SOME BOARDS
            # KEEP TWO: reicast writes both .nvmem and .nvmem2 for a fair
            # number of Atomiswave games. The first version of this rule only
            # matched .nvmem, so 28 of the 56 Atomiswave files were filed as
            # emulator junk while the other 28 were filed as games, splitting
            # one game's memory across two places. Found by running this
            # against the real drive, not by reading the code.
            if ($leaf -match '^(.+?)\.(zip|7z)\.(nvmem\d*|eeprom|nvram)$') {
                $r.GameId = $Matches[1]; $r.Kind = 'name'; $r.Category = 'arcade'; return $r
            }
            # Everything else: a save sitting directly in the system folder and
            # named after the game, which is how the libretro cores do it.
            if ($parts.Count -eq 2 -and $leaf.Contains('.')) {
                $ext = $leaf.Substring($leaf.LastIndexOf('.') + 1).ToLower()
                if ($script:SaveDataExtensions -contains $ext) {
                    $r.GameId = $leaf.Substring(0, $leaf.LastIndexOf('.'))
                    $r.Kind = 'name'; $r.Category = 'game'; return $r
                }
            }
            $r.Why = 'emulator file'; return $r
        }
    }
    return $r
}

# ---------------------------------------------------------------------------
#  The games list
# ---------------------------------------------------------------------------
#  Built entirely from index.json. NOTHING here touches the Versions folders,
#  which is what makes opening the tab instant on a USB drive.
#
#  Each game comes back with:
#     System DisplayName GameId Kind Category Files Changed Bytes
#  Files is the list of save files that make up this one game, which is the
#  whole point: Wii and 3DS split a single save across several of them.
# ---------------------------------------------------------------------------
function Get-SaveGames {
    param(
        [hashtable] $Index,
        [hashtable] $Names = @{},   # game-name-shortcuts.txt   - written by a person
        [hashtable] $Found = @{}    # game-names-found.txt      - worked out by GameNames.ps1
    )

    $groups = @{}
    foreach ($rel in $Index.Keys) {
        $info = Get-SaveGroupInfo $rel
        $key  = '{0}|{1}|{2}' -f $info.System, $info.Category, $info.GameId

        if (-not $groups.ContainsKey($key)) {
            $groups[$key] = [pscustomobject]@{
                System      = $info.System
                GameId      = $info.GameId
                Kind        = $info.Kind
                Category    = $info.Category
                Why         = $info.Why
                DisplayName = ''
                Name        = ''      # the friendly name, if there is one
                NameSource  = ''      # 'yours' or 'found', for the detail panel
                Image       = ''      # box art, relative to the RetroBat folder
                Files       = New-Object System.Collections.ArrayList
                Changed     = [datetime]::MinValue
                Bytes       = [long]0
            }
        }
        $g = $groups[$key]
        [void]$g.Files.Add($rel)

        $e = $Index[$rel]
        if ($null -ne $e) {
            if ($null -ne $e.s) { $g.Bytes += [long]$e.s }
            if ($null -ne $e.m) {
                try {
                    $when = (New-Object DateTime([long]$e.m, [DateTimeKind]::Utc)).ToLocalTime()
                    if ($when -gt $g.Changed) { $g.Changed = $when }
                } catch { }
            }
        }
    }

    $out = @()
    foreach ($g in $groups.Values) {
        if ($g.Category -ne 'system') {
            # A NAME YOU TYPED ALWAYS WINS over one that was worked out. That
            # is the whole reason there are two files: game-name-shortcuts.txt
            # is yours and is never rewritten, game-names-found.txt is rebuilt
            # from the game files whenever they change.
            $key    = $g.GameId.ToUpper()
            $manual = $Names[$key]
            $auto   = $Found[$key]

            if ($manual)   { $g.Name = $manual;    $g.NameSource = 'yours' }
            elseif ($auto) { $g.Name = $auto.Name; $g.NameSource = 'found' }
            if ($auto -and $auto.Image) { $g.Image = $auto.Image }

            if ($g.Name) { $g.DisplayName = $g.Name }
            else         { $g.DisplayName = $g.GameId }
        }
        else {
            $label = $g.Why; if (-not $label) { $label = 'other files' }
            $g.DisplayName = '{0} {1}' -f $g.System, $label
        }
        $out += $g
    }

    # Real game saves first, then arcade memory, then system files; inside
    # each, most recently played first, then by name.
    $order = @{ game = 0; arcade = 1; system = 2 }
    $out = @($out | Sort-Object @{ Expression = { $order[[string]$_.Category] } },
                                @{ Expression = 'Changed'; Descending = $true },
                                DisplayName)
    return $out
}

# ---------------------------------------------------------------------------
#  Turning a version stamp into something a person can read
# ---------------------------------------------------------------------------
#  Version files are named 2026-08-25_120000_<hash>__<file>. The stamp sorts
#  correctly as plain text, which is why that shape is used, but nobody thinks
#  in stamps. The day of the week is included because "was that Saturday?" is
#  how people actually remember when they last played something.
# ---------------------------------------------------------------------------
function Format-SaveStamp {
    param([string] $Stamp)

    if ($Stamp -match '^(\d{4})-(\d{2})-(\d{2})_(\d{2})(\d{2})(\d{2})$') {
        try {
            $dt = New-Object DateTime(
                [int]$Matches[1], [int]$Matches[2], [int]$Matches[3],
                [int]$Matches[4], [int]$Matches[5], [int]$Matches[6])
            return $dt.ToString('ddd  yyyy-MM-dd  HH:mm')
        }
        catch { }
    }
    return $Stamp
}

# ---------------------------------------------------------------------------
#  History for ONE save file. Reads that file's own folder and nothing else.
# ---------------------------------------------------------------------------
function Get-SaveFileVersions {
    param([string] $VersionRoot, [string] $Rel)

    $dir = Get-SaveHistoryDir $VersionRoot $Rel
    $out = @()
    if (-not (Test-Path -LiteralPath $dir)) { return $out }

    foreach ($f in @(Get-ChildItem -LiteralPath $dir -File -ErrorAction SilentlyContinue)) {
        if ($f.Name -notmatch '__') { continue }
        if ($f.Name -notmatch '^(\d{4}-\d{2}-\d{2})_(\d{2})(\d{2})(\d{2})_') { continue }
        $stamp = '{0}_{1}{2}{3}' -f $Matches[1], $Matches[2], $Matches[3], $Matches[4]
        $when  = Format-SaveStamp $stamp
        $out += [pscustomobject]@{
            Rel   = $Rel
            Stamp = $stamp          # sortable as plain text, which is why the format matters
            When  = $when
            Size  = $f.Length
            Path  = $f.FullName
            IsPreRestore = ($f.Name -match '_prerestore__')
        }
    }
    $out = @($out | Sort-Object Stamp -Descending)
    return $out
}

# ---------------------------------------------------------------------------
#  Restore points for a WHOLE GAME
# ---------------------------------------------------------------------------
#  This is the piece the old Restore A Save.bat did not have, and the reason
#  it printed a warning telling you to restore five files by hand and match
#  the dates yourself.
#
#  A restore point is a moment in time. Restoring to it means: for every file
#  belonging to this game, put back the newest version that existed AT OR
#  BEFORE that moment. A file with no version that old did not exist yet, so
#  it is left alone and reported, never guessed at.
# ---------------------------------------------------------------------------
function Get-SaveRestorePoints {
    param([string] $VersionRoot, [string[]] $Files)

    $all = @{}
    foreach ($rel in @($Files)) { $all[$rel] = @(Get-SaveFileVersions $VersionRoot $rel) }

    $stamps = @{}
    foreach ($rel in $all.Keys) {
        foreach ($v in $all[$rel]) {
            if (-not $stamps.ContainsKey($v.Stamp)) { $stamps[$v.Stamp] = 0 }
            $stamps[$v.Stamp] = $stamps[$v.Stamp] + 1
        }
    }

    $out = @()
    foreach ($s in ($stamps.Keys | Sort-Object -Descending)) {
        $out += [pscustomobject]@{ Stamp = $s; When = (Format-SaveStamp $s); Changed = $stamps[$s] }
    }
    return $out
}

# What restoring to a given moment would actually copy. Read-only: this is
# what a front end shows before it asks "are you sure".
function Resolve-SaveSnapshot {
    param([string] $VersionRoot, [string[]] $Files, [string] $Stamp)

    $out = @()
    foreach ($rel in @($Files)) {
        $versions = @(Get-SaveFileVersions $VersionRoot $rel)
        $pick = $null
        foreach ($v in $versions) {           # already newest first
            if ($v.Stamp -le $Stamp) { $pick = $v; break }
        }
        if ($pick) {
            $out += [pscustomobject]@{
                Rel = $rel; Stamp = $pick.Stamp; When = $pick.When
                Size = $pick.Size; Path = $pick.Path; Missing = $false
            }
        }
        else {
            $out += [pscustomobject]@{
                Rel = $rel; Stamp = ''; When = ''; Size = 0; Path = ''; Missing = $true
            }
        }
    }
    return $out
}

# ---------------------------------------------------------------------------
#  Doing the restore
# ---------------------------------------------------------------------------
#  The file that is being replaced is copied into its own history folder first,
#  named <now>_prerestore__<file>, so an unwanted restore is itself undoable.
#  That behaviour is inherited from Restore-RetroBatSave.ps1 and kept on
#  purpose.
# ---------------------------------------------------------------------------
function Restore-SaveSnapshot {
    param(
        [string] $SavesRoot,
        [string] $VersionRoot,
        [object[]] $Snapshot
    )

    $now      = Get-Date -Format 'yyyy-MM-dd_HHmmss'
    $restored = 0; $skipped = 0; $failed = 0
    $messages = @()

    foreach ($item in @($Snapshot)) {
        if ($item.Missing) {
            $skipped++
            $messages += ('Left alone (did not exist yet): {0}' -f (Split-Path $item.Rel -Leaf))
            continue
        }
        $target = Resolve-SaveTarget $SavesRoot $item.Rel
        try {
            if (Test-Path -LiteralPath $target) {
                $histDir = Get-SaveHistoryDir $VersionRoot $item.Rel
                if (-not (Test-Path -LiteralPath $histDir)) {
                    New-Item -ItemType Directory -Path $histDir -Force -ErrorAction Stop | Out-Null
                }
                $leaf   = Split-Path $item.Rel -Leaf
                $safety = Join-Path $histDir ('{0}_prerestore__{1}' -f $now, $leaf)
                Copy-Item -LiteralPath $target -Destination $safety -Force -ErrorAction Stop
            }
            $targetDir = Split-Path $target -Parent
            if (-not (Test-Path -LiteralPath $targetDir)) {
                New-Item -ItemType Directory -Path $targetDir -Force -ErrorAction Stop | Out-Null
            }
            Copy-Item -LiteralPath $item.Path -Destination $target -Force -ErrorAction Stop

            # Verify. A copy cut short by a shutdown must not be trusted, the
            # same lesson Backup-RetroBatSaves.ps1 learned.
            $written = Get-Item -LiteralPath $target -ErrorAction Stop
            if ($written.Length -ne $item.Size) {
                throw ('copy was incomplete ({0} of {1} bytes)' -f $written.Length, $item.Size)
            }
            $restored++
        }
        catch {
            $failed++
            $messages += ('FAILED {0} - {1}' -f (Split-Path $item.Rel -Leaf), $_.Exception.Message)
        }
    }

    return [pscustomobject]@{
        Restored = $restored; Skipped = $skipped; Failed = $failed; Messages = $messages
    }
}

# ---------------------------------------------------------------------------
#  Small helpers the front ends share
# ---------------------------------------------------------------------------
function Format-SaveSize {
    param([long] $Bytes)
    if ($Bytes -ge 1048576) { return ('{0:N1} MB' -f ($Bytes / 1MB)) }
    if ($Bytes -ge 1024)    { return ('{0:N0} KB' -f ($Bytes / 1KB)) }
    return ('{0} bytes' -f $Bytes)
}

# Adds "name = code" to game-name-shortcuts.txt. Appends only, so every
# comment in that file survives - those comments are what explain the file to
# whoever ends up owning this drive.
function Add-GameName {
    param([string] $NamesPath, [string] $Name, [string] $Code)

    $clean = ("$Name" -replace '[=\r\n]', ' ').Trim()
    if (-not $clean -or -not $Code) { return $false }
    $line = '{0,-12}= {1}' -f $clean, $Code
    try {
        if (-not (Test-Path -LiteralPath $NamesPath)) {
            Set-Content -LiteralPath $NamesPath -Value '# name = code' -Encoding ASCII -ErrorAction Stop
        }
        Add-Content -LiteralPath $NamesPath -Value $line -Encoding ASCII -ErrorAction Stop
        return $true
    }
    catch { return $false }
}

# ---------------------------------------------------------------------------
#  MID-GAME AUTOSAVES (quarantined savestates)
# ---------------------------------------------------------------------------
#  Dolphin writes a savestate when RetroBat's launch menu asks it to, and
#  Quarantine-Savestates.ps1 moves those out of reach so one cannot be loaded
#  by accident. They land in
#
#      _ClaudeWorkspace\archive\quarantined-savestates\<date>\
#
#  named  <HHmmss>__<original file name>, for example:
#
#      202413__G8ME01.s02
#      202413__Paper Mario - The Thousand-Year Door (USA).s02
#      202413__Paper Mario - The Thousand-Year Door (USA).s02.png
#      131653__StateSaves__GSNE8P.s01        (an older naming, still handled)
#
#  Three things that shape the code below, all read off the real drive:
#
#  1. THE SAME MOMENT APPEARS TWICE. Dolphin keeps savestates in two places,
#     one named by game id and one named by rom file name, and both get
#     quarantined. Listed raw, every autosave shows up twice. They are matched
#     up and merged.
#  2. THE .png IS A SCREENSHOT of that exact moment, sitting next to the state
#     file. It is not a savestate itself and must not be listed as one - it is
#     the picture to show for it.
#  3. THE NAME SAYS WHICH GAME IT IS, in one of two shapes: a six character
#     game id like G8ME01, or the rom's file name. Both are keys the game name
#     lookup already understands.
#
#  Reading only, here. Putting one back for "Jump in here" is in SaveStates.ps1
#  (Set-SavestateJumpIn), since 2026-10-11.
# ---------------------------------------------------------------------------
function Get-QuarantinedSavestates {
    param([string] $QuarantineRoot)

    # Since 2026-10-11 every emulator's states are swept here (SaveStates.ps1),
    # and each day folder has an origins.txt saying where each file came from:
    #   <name in this folder> <TAB> <where it was, relative to RetroBat> <TAB> <kind>
    # Older days have no origins.txt and hold only Dolphin states.
    $out = @()
    if (-not $QuarantineRoot -or -not (Test-Path -LiteralPath $QuarantineRoot)) { return $out }

    # name shape -> where the game name and slot are. First match wins.
    $shapes = @(
        @('^(.+)\.s(\d{2})$',              'dolphin'),
        @('^(.+)\.state(\d*)$',            'retroarch'),
        @('^(.+)\.state\.(auto)$',         'retroarch'),
        @('^(.+)\.ml(\d+)$',               'melonds'),
        @('^([0-9A-Fa-f]{16})\.(\d+)\.cst$','azahar'),
        @('^(.+)\.(\d{2})\.p2s$',          'pcsx2'),
        @('^(.+)\.(resume)\.p2s$',         'pcsx2'),
        @('^(.+)_(resume)\.sav$',          'duckstation'),
        @('^(.+)_(\d{2})\.sav$',           'duckstation'),
        @('^(.+)\.QuickSave(\d)\.State$',  'bizhawk'),
        @('^(.+)\.st(\d)$',                'mupen64'),
        @('^(.+)\.ds(\d)$',                'desmume'),
        @('^(.+?)[._](\d{1,3})\.[A-Za-z0-9]+$', '')
    )

    foreach ($dayDir in @(Get-ChildItem -LiteralPath $QuarantineRoot -Directory -ErrorAction SilentlyContinue)) {
        if ($dayDir.Name -notmatch '^(\d{4})-(\d{2})-(\d{2})$') { continue }
        $y = [int]$Matches[1]; $mo = [int]$Matches[2]; $d = [int]$Matches[3]

        $origin = @{}
        $op = Join-Path $dayDir.FullName 'origins.txt'
        if (Test-Path -LiteralPath $op) {
            foreach ($line in @([System.IO.File]::ReadAllLines($op))) {
                $f3 = $line -split "`t"
                if ($f3.Count -ge 2) { $origin[$f3[0]] = @{ Rel = $f3[1]; Kind = $(if ($f3.Count -ge 3) { $f3[2] } else { '' }) } }
            }
        }

        foreach ($f in @(Get-ChildItem -LiteralPath $dayDir.FullName -File -ErrorAction SilentlyContinue)) {
            # the screenshots are picked up through their state file, not listed
            if ($f.Name -match '\.png$' -or $f.Name -eq 'origins.txt') { continue }
            if ($f.Name -notmatch '^(\d{2})(\d{2})(\d{2})__(\d+-)?(.+)$') { continue }
            $hh = [int]$Matches[1]; $mi = [int]$Matches[2]; $ss = [int]$Matches[3]
            $rest = $Matches[5]

            # an older quarantine build put the source folder in the name
            $rest = $rest -replace '^(StateSaves|dolphin)__', ''

            $base = ''; $slot = ''; $shape = ''
            foreach ($sh in $shapes) {
                if ($rest -match $sh[0]) { $base = $Matches[1]; $slot = $Matches[2]; $shape = $sh[1]; break }
            }
            if (-not $base) { continue }

            $when = $null
            try { $when = New-Object DateTime($y, $mo, $d, $hh, $mi, $ss) } catch { continue }

            $o = $origin[$f.Name]
            $rel = $(if ($o) { [string]$o.Rel } else { '' })
            $kind = $(if ($o) { [string]$o.Kind } elseif ($shape -eq 'dolphin') { 'dolphin-legacy' } else { $shape })
            $system = ''
            if ($rel -match '^saves\\([^\\]+)\\') { $system = $Matches[1] }

            # ".nkit" is a packaging suffix, not part of the game's name
            $key = ($base -replace '\.nkit$', '')
            # Dolphin's own copy is named by game id (G8ME01): the save groups
            # use its first four characters. Only for Dolphin's id-named files.
            if ($shape -eq 'dolphin' -and $key -match '^[A-Za-z0-9]{6}$' -and ($kind -eq 'dolphin-own' -or $kind -eq 'dolphin-legacy')) { $key = $key.Substring(0, 4) }
            # Azahar names states by the 16-digit title id; the 3DS save groups
            # use its last eight digits.
            if ($shape -eq 'azahar') { $key = $key.Substring(8) }

            $thumb = ''
            foreach ($cand in @(($f.FullName + '.png'), ([System.IO.Path]::ChangeExtension($f.FullName, '.png')))) {
                if (Test-Path -LiteralPath $cand) { $thumb = $cand; break }
            }

            $copy = [pscustomobject]@{ Path = $f.FullName; File = $f.Name; Thumb = $thumb; Origin = $rel; Kind = $kind
                                       Menu = ($kind -eq 'retroarch' -or $kind -eq 'dolphin' -or ($kind -ne '' -and $kind -notmatch '^(retroarch-loose|dolphin-own|dolphin-legacy|melonds|azahar)$' -and $rel -ne '')) }
            $out += [pscustomobject]@{
                Key    = $key.ToUpper()
                Slot   = $slot
                When   = $when
                Size   = $f.Length
                Path   = $f.FullName
                Thumb  = $thumb
                File   = $f.Name
                System = $system
                Kind   = $kind
                # Every copy of this moment is kept, not just the one shown:
                # Dolphin saves one moment twice (by game id and by rom name),
                # and putting one back means putting each copy where it came from.
                Copies = @($copy)
            }
        }
    }
    return $out
}

# Attaches the autosaves to the games they belong to, and merges the duplicate
# copies of one moment. Call it AFTER Get-SaveGames, with the same $Found so
# both sides resolve names the same way.
#
# Returns the games list with a Savestates list on each, plus a new group for
# any autosave whose game has no save data on the drive - because an autosave
# with nowhere to appear would be an autosave nobody ever sees, which is the
# thing this was built to fix.
function Add-SavestatesToGames {
    param(
        [object[]]  $Games,
        [object[]]  $Savestates,
        [hashtable] $Found = @{}
    )

    $games = @($Games)
    foreach ($g in $games) {
        $g | Add-Member -NotePropertyName Savestates -NotePropertyValue (New-Object System.Collections.ArrayList) -Force
    }

    # Matching a savestate to its game.
    #
    #   by key   the state is named by game id (G8ME01.s02) and the save group
    #            is keyed the same way. Direct hit.
    #   by name  the state is named after the ROM FILE (Paper Mario - The
    #            Thousand-Year Door (USA).s02) while the save group is keyed
    #            G8ME. Different words for the same game, so they can only be
    #            matched through the name both resolve to.
    #
    # THE NAME USED FOR MATCHING IS THE AUTO-FOUND ONE, NOT WHAT IS ON SCREEN.
    # That distinction cost a bug on 2026-08-29: if the user has typed their
    # own short name for a game ("paper mario = G8ME"), the group DISPLAYS that
    # and the state resolves to the full scraped title, the two never match,
    # and the same autosave appears twice - once against the game and once as a
    # row of its own. Both sides now look up the found name, which is the same
    # string for both no matter what anybody typed.
    $byKey  = @{}
    $byName = @{}
    foreach ($g in $games) {
        $k = ([string]$g.GameId).ToUpper()
        if ($k -and -not $byKey.ContainsKey($k)) { $byKey[$k] = $g }

        foreach ($n in @($(if ($Found[$k]) { [string]$Found[$k].Name } else { '' }), [string]$g.Name)) {
            if (-not $n) { continue }
            $u = $n.ToUpper()
            if (-not $byName.ContainsKey($u)) { $byName[$u] = $g }
        }
    }

    $extra = @{}
    $seen  = @{}

    foreach ($s in @($Savestates)) {

        # Resolve the game the same way the list does, so both sides agree.
        $name = ''
        $entry = $Found[$s.Key]
        if ($entry) { $name = [string]$entry.Name }

        $target = $null
        if ($byKey.ContainsKey($s.Key))                      { $target = $byKey[$s.Key] }
        elseif ($name -and $byName.ContainsKey($name.ToUpper())) { $target = $byName[$name.ToUpper()] }

        # One moment, saved twice under two names. Merge on the game it belongs
        # to plus the exact second plus the slot. Keep the copy that has the
        # screenshot with it.
        $ident = '{0}|{1}|{2}' -f `
                 $(if ($target) { $target.System + '/' + $target.GameId } elseif ($name) { $name } else { $s.Key }),
                 $s.When.ToString('yyyy-MM-dd_HHmmss'), $s.Slot

        if ($seen.ContainsKey($ident)) {
            $already = $seen[$ident]
            if (-not $already.Thumb -and $s.Thumb) { $already.Thumb = $s.Thumb }
            $already.Copies = @($already.Copies) + @($s.Copies)
            continue
        }

        # A COPY, not the caller's object. Merging writes into Copies, and
        # writing into what was passed in means calling this twice on the same
        # list counts every duplicate again - three copies of a savestate that
        # only has two. Nothing errors; the number just quietly grows.
        $seen[$ident] = [pscustomobject]@{
            Key = $s.Key; Slot = $s.Slot; When = $s.When; Size = $s.Size
            Path = $s.Path; Thumb = $s.Thumb; File = $s.File
            System = [string]$s.System; Kind = [string]$s.Kind
            Copies = @($s.Copies)
        }
        $s = $seen[$ident]

        if ($target) {
            [void]$target.Savestates.Add($s)
            continue
        }

        # No save data for this game on the drive. Give it a row of its own so
        # the autosave is still visible.
        $ek = 'x|' + $s.Key
        if (-not $extra.ContainsKey($ek)) {
            $disp = if ($name) { $name } else { $s.Key }
            $ng = [pscustomobject]@{
                System      = 'autosave'
                GameId      = $s.Key
                Kind        = 'code'
                Category    = 'game'
                Why         = ''
                DisplayName = $disp
                Name        = $name
                NameSource  = $(if ($name) { 'found' } else { '' })
                Image       = $(if ($entry) { [string]$entry.Image } else { '' })
                Files       = New-Object System.Collections.ArrayList
                Changed     = $s.When
                Bytes       = [long]0
                Savestates  = New-Object System.Collections.ArrayList
            }
            $extra[$ek] = $ng
        }
        $eg = $extra[$ek]
        [void]$eg.Savestates.Add($s)
        if ($s.When -gt $eg.Changed) { $eg.Changed = $s.When }
    }

    # newest autosave first inside every game
    foreach ($g in $games) {
        if ($g.Savestates.Count -gt 1) {
            $sorted = @($g.Savestates | Sort-Object When -Descending)
            $g.Savestates.Clear()
            foreach ($x in $sorted) { [void]$g.Savestates.Add($x) }
        }
    }

    $all = @($games) + @($extra.Values)
    $order = @{ game = 0; arcade = 1; system = 2 }
    $all = @($all | Sort-Object @{ Expression = { $order[[string]$_.Category] } },
                                @{ Expression = 'Changed'; Descending = $true },
                                DisplayName)
    return $all
}

# ---------------------------------------------------------------------------
#  Putting a mid-game autosave back
# ---------------------------------------------------------------------------
#  Each copy goes back to the folder it came from, and those are different
#  folders. The quarantine did not record which, but the NAME says it:
#
#      GKYE01.s01                      Dolphin's own StateSaves folder
#      Kirby Air Ride (USA).s01        RetroBat's saves\<system>\dolphin copy
#
#  Dolphin only loads a state named by game id, so putting back only the
#  rom-named copy would look like it worked and do nothing.
#
#  The file is COPIED, never moved. The archive keeps its copy either way, so a
#  restore can always be undone by deleting what was put back.
#
#  WORTH KNOWING, AND THE SCREEN SAYS IT: the game-end hook quarantines
#  savestates again after the next game exits. A restored autosave has to be
#  loaded before that happens, or it simply goes back to the archive.
# ---------------------------------------------------------------------------
function Restore-Savestate {
    param(
        [string] $Root,
        [object] $Savestate,
        [string] $System
    )

    $restored = 0; $skipped = 0
    $messages = @()

    foreach ($c in @($Savestate.Copies)) {
        $name = [string]$c.File -replace '^\d{6}__', ''
        $name = $name -replace '^(StateSaves|dolphin)__', ''

        if ($name -match '^[A-Za-z0-9]{6}\.s\d{2}$') {
            $destDir = Join-Path $Root 'emulators\dolphin-emu\User\StateSaves'
        }
        elseif ($System -eq 'gamecube' -or $System -eq 'wii') {
            $destDir = Join-Path (Join-Path (Join-Path $Root 'saves') $System) 'dolphin'
        }
        else {
            $skipped++
            $messages += ('Left alone: {0} (not sure which folder it came from)' -f $name)
            continue
        }

        try {
            if (-not (Test-Path -LiteralPath $destDir)) {
                New-Item -ItemType Directory -Path $destDir -Force -ErrorAction Stop | Out-Null
            }
            Copy-Item -LiteralPath $c.Path -Destination (Join-Path $destDir $name) -Force -ErrorAction Stop
            $restored++

            if ($c.Thumb -and (Test-Path -LiteralPath $c.Thumb)) {
                Copy-Item -LiteralPath $c.Thumb -Destination (Join-Path $destDir ($name + '.png')) -Force -ErrorAction SilentlyContinue
            }
        }
        catch {
            $messages += ('FAILED {0} - {1}' -f $name, $_.Exception.Message)
        }
    }

    return [pscustomobject]@{ Restored = $restored; Skipped = $skipped; Messages = $messages }
}
