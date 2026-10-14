<#
    SaveStates.ps1 - the drive's save-state rules, in one place.

    FUNCTIONS ONLY. Dot-source it. Used by Quarantine-Savestates.ps1 (the
    game-end hook), Watch-Dolphin.ps1 (the watcher while RetroBat runs) and the
    wizard's Saves tab.

    THE DESIGN (Steven's, written down 2026-10-11)
        - RetroBat's launch menu only ever says "Launch game?". It is a
          confirmation screen, never a place to load an emulator's own save
          states. Apply-Settings.ps1 lists every emulator for it.
        - When a game closes, its ordinary saves are backed up
          (Backup-RetroBatSaves.ps1) and show on the Saves tab.
        - Any save state an emulator makes anyway (a button pressed by
          accident, or the auto-save timer below) is SWEPT into
          archive\quarantined-savestates\<date>\, so nothing can load it by
          accident. Every sweep notes where each file came from in that day's
          origins.txt.
        - "Jump in here" on the Saves tab puts one swept state back exactly
          where RetroBat's own launch menu looks for save states, and holds it
          there for one game. The launch menu then lists it next to "Launch
          game?"; picking it starts the game at that moment (RetroBat's own
          feature). When that game closes, the held copy goes away again.
        - No in-game save or load buttons are set up by the drive (Steven: no
          button mashing into a reload). Loading lives on the Saves tab.
        - The auto-save timer (Watch-Dolphin.ps1) presses the emulator's own
          save-state key at 45 minutes into a game and then every 30, only for
          emulators whose key is known for sure (RetroArch, Dolphin: F2,
          checked in their own config each time). Those states are swept like
          any other.

    WHERE STATES ARE LOOKED FOR (Get-SavestateSources)
        - every folder RetroBat's own es_savestates.cfg names (RetroArch per
          core, Dolphin, DuckStation, PCSX2, PPSSPP...), for every console
          folder under saves\. Read from the file, so a new RetroBat that
          adds an emulator is covered by itself.
        - emulators\retroarch\states: where RetroArch puts states when its
          per-core folder is blocked (the empty placeholder files in
          saves\n64, gba, gbc and nds, which keep the launch menu plain).
        - emulators\dolphin-emu\User\StateSaves (Dolphin's own copy).
        - melonDS (saves\nds\melonds\sstates) and Azahar (user\states).
      Only files shaped like a save state (and their screenshots) are ever
      moved. Nothing is deleted, with one exception: a held "jump in" copy
      that is still byte-for-byte the archived original is removed after the
      game, because the original never left the archive.

    ASCII ONLY, Windows PowerShell 5.1. Every root is a parameter.
#>

# ---------------------------------------------------------------------------
#  Small helpers
# ---------------------------------------------------------------------------
function Join-SsPath([string]$Base, [string]$Rel) {
    $p = $Base
    foreach ($seg in ($Rel -split '[\\/]')) { if ($seg -ne '') { $p = [System.IO.Path]::Combine($p, $seg) } }
    return $p
}

function Get-SsRel([string]$Root, [string]$Full) {
    $r = $Root.TrimEnd('\', '/')
    if ($Full.Length -gt $r.Length -and $Full.StartsWith($r, [System.StringComparison]::OrdinalIgnoreCase)) {
        return ($Full.Substring($r.Length).TrimStart('\', '/') -replace '/', '\')
    }
    return $Full
}

function Get-SsArchiveRoot([string]$Root) { return (Join-SsPath $Root '_ClaudeWorkspace\archive\quarantined-savestates') }
function Get-SsHoldPath([string]$Root)    { return (Join-SsPath $Root '_ClaudeWorkspace\SaveBackups\jump-in.txt') }

function Get-SsHash([string]$Path) {
    try { return (Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash } catch { return '' }
}

# A RetroBat file template ({{romfilename}}.state{{slot}}) as a regex.
function Convert-SsTemplateToRegex([string]$Tpl) {
    if ([string]::IsNullOrWhiteSpace($Tpl)) { return '' }
    $out = ''
    $rest = $Tpl
    while ($rest -ne '') {
        $i = $rest.IndexOf('{{')
        if ($i -lt 0) { $out += [regex]::Escape($rest); break }
        $out += [regex]::Escape($rest.Substring(0, $i))
        $j = $rest.IndexOf('}}', $i)
        if ($j -lt 0) { $out += [regex]::Escape($rest.Substring($i)); break }
        $tok = $rest.Substring($i + 2, $j - $i - 2)
        switch -regex ($tok) {
            '^romfilename$' { $out += '.+?'; break }
            '^slot$'        { $out += '\d*'; break }
            '^slot\w*$'     { $out += '\d+'; break }
            default         { $out += '.*?' }
        }
        $rest = $rest.Substring($j + 2)
    }
    return ('^' + $out + '$')
}

# ---------------------------------------------------------------------------
#  Where save states live
# ---------------------------------------------------------------------------
#  Returns a list of @{ Dir; Regex; Kind; Menu }:
#    Dir    a folder that exists right now
#    Regex  the file names in it that count (states AND their screenshots)
#    Kind   retroarch, retroarch-loose, dolphin, dolphin-own, melonds,
#           azahar, or the emulator name from es_savestates.cfg
#    Menu   $true when RetroBat's launch menu reads this folder, which is what
#           makes "jump in" possible for what came out of it
function Get-SavestateSources([string]$Root) {
    $out = @()
    $saves = Join-SsPath $Root 'saves'
    $sysDirs = @()
    if ([System.IO.Directory]::Exists($saves)) {
        try { $sysDirs = @([System.IO.Directory]::GetDirectories($saves)) } catch { $sysDirs = @() }
    }

    # 1. RetroBat's own list
    $ssPath = Join-SsPath $Root 'emulationstation\.emulationstation\es_savestates.cfg'
    if (Test-Path -LiteralPath $ssPath) {
        $x = $null
        try { [xml]$x = [System.IO.File]::ReadAllText($ssPath) } catch { $x = $null }
        if ($null -ne $x) {
            foreach ($e in @($x.SelectNodes('/savestates/emulator'))) {
                if ($null -eq $e) { continue }
                $name = [string]$e.GetAttribute('name')
                $dn = $e.SelectSingleNode('directory'); $fn = $e.SelectSingleNode('file')
                if ($null -eq $dn -or $null -eq $fn) { continue }
                $dirT = [string]$dn.InnerText; $fileT = [string]$fn.InnerText
                # an entry Apply-Settings.ps1 made only for the confirmation
                # screen points at a folder nothing ever writes to: skip it
                if ($dirT -eq "{{system}}/$name" -and $fileT -eq '{{romfilename}}.state{{slot2d}}') { continue }
                $regs = @()
                foreach ($tag in @('file', 'image', 'autosave_file', 'autosave_image')) {
                    $n = $e.SelectSingleNode($tag)
                    if ($null -ne $n) { $r = Convert-SsTemplateToRegex ([string]$n.InnerText); if ($r) { $regs += $r } }
                }
                $regs += ((Convert-SsTemplateToRegex $fileT).TrimEnd('$') + '\.png$')
                $rx = '(' + ($regs -join ')|(') + ')'
                $segs = @($dirT -split '/' | Where-Object { $_ -ne '' })
                if ($segs.Count -eq 0 -or $segs[0] -ne '{{system}}') { continue }
                $cands = @($sysDirs)
                for ($k = 1; $k -lt $segs.Count -and $cands.Count -gt 0; $k++) {
                    $seg = $segs[$k]
                    $next = @()
                    if ($seg.Contains('{{')) {
                        $sr = Convert-SsTemplateToRegex $seg
                        foreach ($c in $cands) {
                            $kids = @()
                            try { $kids = @([System.IO.Directory]::GetDirectories($c)) } catch { }
                            foreach ($kd in $kids) { if ([System.IO.Path]::GetFileName($kd) -match $sr) { $next += $kd } }
                        }
                    }
                    else {
                        foreach ($c in $cands) { $p = [System.IO.Path]::Combine($c, $seg); if ([System.IO.Directory]::Exists($p)) { $next += $p } }
                    }
                    $cands = $next
                }
                $kind = $(if ($name -eq 'libretro') { 'retroarch' } elseif ($name -eq 'dolphin') { 'dolphin' } else { $name })
                foreach ($c in $cands) { $out += [pscustomobject]@{ Dir = $c; Regex = $rx; Kind = $kind; Menu = $true } }
            }
        }
    }

    # 2. the extras RetroBat's list does not name
    $extras = @(
        @('emulators\retroarch\states',             '\.state(\d+|\.auto)?(\.png)?$', 'retroarch-loose', $false),
        @('emulators\dolphin-emu\User\StateSaves',  '\.s\d{2}(\.png)?$',             'dolphin-own',     $false),
        @('saves\gamecube\dolphin',                 '\.s\d{2}(\.png)?$',             'dolphin',         $true),
        @('saves\wii\dolphin',                      '\.s\d{2}(\.png)?$',             'dolphin',         $true),
        @('saves\nds\melonds\sstates',              '\.ml\d+(\.png)?$',              'melonds',         $false),
        @('emulators\azahar\user\states',           '\.cst(\.png)?$',                'azahar',          $false),
        @('saves\3ds\azahar\states',                '\.cst(\.png)?$',                'azahar',          $false),
        @('saves\3ds\azahar\sstates',               '\.cst(\.png)?$',                'azahar',          $false)
    )
    $have = @{}
    foreach ($o in $out) { $have[$o.Dir.ToLower()] = $true }
    foreach ($ex in $extras) {
        $d = Join-SsPath $Root $ex[0]
        if (-not [System.IO.Directory]::Exists($d)) { continue }
        if ($have.ContainsKey($d.ToLower())) { continue }
        $have[$d.ToLower()] = $true
        $out += [pscustomobject]@{ Dir = $d; Regex = $ex[1]; Kind = $ex[2]; Menu = $ex[3] }
    }
    return $out
}

# ---------------------------------------------------------------------------
#  The "jump in" hold list: SaveBackups\jump-in.txt
# ---------------------------------------------------------------------------
#  One line per thing being held for the next game, tab separated:
#    file <TAB> <placed, relative to RetroBat> <TAB> <the archived original, full path>
#    placeholder <TAB> <placeholder, relative> <TAB> <where it waits, relative>
#    game <TAB> <console> <TAB> <rom key>|<yyyy-MM-dd HH:mm:ss>|<name shown>
#  The game line (2026-10-12, Steven: "only there once and then gone", and he
#  had only LOOKED at the menu): the hold now waits for THAT game. Another
#  game ending leaves it ready. A hold with no game line (made before) clears
#  at the next game end, as it used to.
function Get-SsLastGamePath([string]$Root) { return (Join-SsPath $Root '_ClaudeWorkspace\SaveBackups\last-game.txt') }

# The watcher writes this whenever a game starts: "<yyyy-MM-dd HH:mm:ss><TAB><rom path>".
function Set-SsLastGame([string]$Root, [string]$Path) {
    try { [System.IO.File]::WriteAllText((Get-SsLastGamePath $Root), ('{0}{1}{2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), "`t", $Path)) } catch { }
}

function Get-SsLastGame([string]$Root) {
    $r = @{ When = [datetime]::MinValue; Path = '' }
    $p = Get-SsLastGamePath $Root
    if (-not (Test-Path -LiteralPath $p)) { return $r }
    try {
        $f = ([System.IO.File]::ReadAllText($p)).Trim() -split "`t", 2
        if ($f.Count -eq 2) { $r.When = [datetime]::ParseExact($f[0], 'yyyy-MM-dd HH:mm:ss', $null); $r.Path = $f[1] }
    } catch { }
    return $r
}

# The rom a placed state belongs to: its name without the state ending.
function Get-SsRomKey([string]$Leaf) {
    return (([string]$Leaf -replace '\.png$', '') -replace '(\.state(\d+|\.auto)?|\.s\d{2}|_state\d+\.bigpstate|\.QuickSave\d\.State|_\d\.state)$', '')
}

# Was the held game the one that just ran? $Game is the hold's game line.
function Test-SsHoldUsed([string]$Root, $Game) {
    if ($null -eq $Game) { return $true }
    $f = ([string]$Game.Other) -split '\|', 3
    $key = $f[0]
    $since = [datetime]::MinValue
    try { $since = [datetime]::ParseExact($f[1], 'yyyy-MM-dd HH:mm:ss', $null) } catch { return $true }
    $last = Get-SsLastGame $Root
    if ($last.Path -eq '' -or $last.When -lt $since) { return $false }
    $p = ([string]$last.Path) -replace '\\', '/'
    $sys = [string]$Game.Rel
    if ($sys -ne '' -and $p -notmatch ('/roms/' + [regex]::Escape($sys) + '/')) { return $false }
    if ($key -eq '') { return $true }
    $leaf = $p.Substring($p.LastIndexOf('/') + 1)
    $noExt = $leaf; if ($leaf.LastIndexOf('.') -gt 0) { $noExt = $leaf.Substring(0, $leaf.LastIndexOf('.')) }
    return ($key -eq $noExt -or $key -eq $leaf)
}

function Get-SsHolds([string]$Root) {
    $out = @()
    $p = Get-SsHoldPath $Root
    if (-not (Test-Path -LiteralPath $p)) { return $out }
    foreach ($line in @([System.IO.File]::ReadAllLines($p))) {
        $f = $line -split "`t"
        if ($f.Count -lt 3) { continue }
        $out += [pscustomobject]@{ Type = $f[0]; Rel = $f[1]; Other = $f[2] }
    }
    return $out
}

function Set-SsHolds([string]$Root, $Holds) {
    $p = Get-SsHoldPath $Root
    $lines = @(@($Holds) | Where-Object { $null -ne $_ } | ForEach-Object { '{0}{3}{1}{3}{2}' -f $_.Type, $_.Rel, $_.Other, "`t" })
    if ($lines.Count -eq 0) {
        if (Test-Path -LiteralPath $p) { try { [System.IO.File]::WriteAllText($p, '') } catch { } }
        return
    }
    $dir = Split-Path -Parent $p
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    [System.IO.File]::WriteAllText($p, (($lines -join "`r`n") + "`r`n"))
}

# ---------------------------------------------------------------------------
#  The sweep
# ---------------------------------------------------------------------------
#  -MidGame: a game is running. Held "jump in" copies are left alone, and
#  placeholders are not put back yet.
#  Without it (the game-end hook): a held copy that is still the archived
#  original is removed, anything changed is swept like any other state, the
#  placeholders go back, and the hold list is cleared.
#  Returns @{ Moved; Dropped; Restored; Messages }.
function Invoke-SavestateSweep([string]$Root, [switch]$MidGame) {
    $res = @{ Moved = 0; Dropped = 0; Restored = 0; Pruned = 0; Retired = 0; Messages = @() }
    $holds = @(Get-SsHolds $Root)
    $held = @{}
    foreach ($h in $holds) { if ($h.Type -eq 'file') { $held[(Join-SsPath $Root $h.Rel).ToLower()] = $h } }

    # A hold for a game that has not been played yet stays as it is: another
    # game ending is just another game.
    $gameHold = @($holds | Where-Object { $_.Type -eq 'game' }) | Select-Object -First 1
    if (-not $MidGame -and @($holds).Count -gt 0 -and -not (Test-SsHoldUsed $Root $gameHold)) { $MidGame = [switch]$true; $res.Messages += 'jump in still waiting for its game' }

    if (-not $MidGame) {
        foreach ($h in @($holds | Where-Object { $_.Type -eq 'file' })) {
            $placed = Join-SsPath $Root $h.Rel
            if (-not (Test-Path -LiteralPath $placed)) { continue }
            $same = $false
            if (Test-Path -LiteralPath $h.Other) { $same = ((Get-SsHash $placed) -ne '' -and (Get-SsHash $placed) -eq (Get-SsHash $h.Other)) }
            if ($same) {
                try { Remove-Item -LiteralPath $placed -Force -ErrorAction Stop; $res.Dropped++ } catch { }
            }
        }
        $held = @{}
    }

    $archive = Get-SsArchiveRoot $Root
    $now = Get-Date
    $stamp = $now.ToString('HHmmss')
    $dayDir = Join-SsPath $archive $now.ToString('yyyy-MM-dd')
    $origins = @()
    foreach ($src in @(Get-SavestateSources $Root)) {
        $files = @()
        try { $files = @([System.IO.Directory]::GetFiles($src.Dir)) } catch { continue }
        foreach ($f in $files) {
            $leaf = [System.IO.Path]::GetFileName($f)
            if ($leaf -notmatch $src.Regex) { continue }
            if ($held.ContainsKey($f.ToLower())) { continue }
            if (-not [System.IO.Directory]::Exists($dayDir)) {
                try { New-Item -ItemType Directory -Path $dayDir -Force -ErrorAction Stop | Out-Null } catch { $res.Messages += "could not make $dayDir"; return $res }
            }
            $destName = '{0}__{1}' -f $stamp, $leaf
            $dest = Join-SsPath $dayDir $destName
            $n = 2
            while (Test-Path -LiteralPath $dest) { $destName = '{0}__{1}-{2}' -f $stamp, $n, $leaf; $dest = Join-SsPath $dayDir $destName; $n++ }
            try {
                [System.IO.File]::Move($f, $dest)
                $res.Moved++
                $origins += ('{0}{2}{1}{2}{3}' -f $destName, (Get-SsRel $Root $f), "`t", $src.Kind)
            }
            catch { }   # still in use: the next sweep gets it
        }
    }
    if ($origins.Count -gt 0) {
        try { [System.IO.File]::AppendAllText((Join-SsPath $dayDir 'origins.txt'), (($origins -join "`r`n") + "`r`n")) } catch { }
    }

    if (-not $MidGame) {
        $keep = @()
        foreach ($h in @($holds | Where-Object { $_.Type -eq 'placeholder' })) {
            $ph = Join-SsPath $Root $h.Rel
            $wait = Join-SsPath $Root $h.Other
            $ok = $false
            try {
                if ([System.IO.Directory]::Exists($ph)) {
                    if (@([System.IO.Directory]::GetFileSystemEntries($ph)).Count -eq 0) { [System.IO.Directory]::Delete($ph) }
                }
                if (-not (Test-Path -LiteralPath $ph) -and (Test-Path -LiteralPath $wait)) {
                    [System.IO.File]::Move($wait, $ph); $ok = $true; $res.Restored++
                }
                elseif ((Test-Path -LiteralPath $ph) -and -not [System.IO.Directory]::Exists($ph)) { $ok = $true }
            } catch { }
            if (-not $ok) { $keep += $h; $res.Messages += ('placeholder not put back yet: ' + $h.Rel) }
        }
        Set-SsHolds $Root $keep
        if ($keep.Count -eq 0) { $res.Retired = Invoke-SsRetirePlaceholders $Root }
        $lim = Get-SsStorage $Root
        if ($lim.States -gt 0) { $res.Pruned = Invoke-SsStatePrune $Root $lim.States }
    }
    return $res
}

# ---------------------------------------------------------------------------
#  The old RetroArch placeholders, retired (2026-10-12)
# ---------------------------------------------------------------------------
#  Four empty FILES from 2026-08-20 (saves\n64\libretro.mupen64plus_next,
#  gba\libretro.mgba, gbc\libretro.gambatte, nds\libretro.melonds) sat where
#  RetroArch's per-core state folders go, to keep the launch menu plain.
#  The sweep does that job for every console now (Steven checked NES and
#  SNES, which never had one), so any empty file named libretro.<core> in a
#  console's saves folder is moved to _SAFE TO DELETE\retroarch-placeholders.
#  Nothing is deleted. Returns how many moved.
function Invoke-SsRetirePlaceholders([string]$Root) {
    $n = 0
    $saves = Join-SsPath $Root 'saves'
    $dirs = @()
    try { $dirs = @([System.IO.Directory]::GetDirectories($saves)) } catch { return 0 }
    foreach ($d in $dirs) {
        $files = @()
        try { $files = @([System.IO.Directory]::GetFiles($d, 'libretro.*')) } catch { continue }
        foreach ($f in $files) {
            try {
                if ((New-Object System.IO.FileInfo($f)).Length -ne 0) { continue }
                $sys = [System.IO.Path]::GetFileName($d)
                $toDir = Join-SsPath $Root ('_ClaudeWorkspace\_SAFE TO DELETE\retroarch-placeholders\saves\' + $sys)
                if (-not [System.IO.Directory]::Exists($toDir)) { New-Item -ItemType Directory -Path $toDir -Force | Out-Null }
                $to = Join-SsPath $toDir ([System.IO.Path]::GetFileName($f))
                $k = 2
                while (Test-Path -LiteralPath $to) { $to = Join-SsPath $toDir ([System.IO.Path]::GetFileName($f) + '.' + $k); $k++ }
                [System.IO.File]::Move($f, $to)
                $n++
            } catch { }
        }
    }
    return $n
}

# ---------------------------------------------------------------------------
#  Jump in here
# ---------------------------------------------------------------------------
#  RetroArch's core for a console: es_settings.cfg first (<system>.core),
#  else the first core RetroBat lists for its libretro emulator.
function Get-SsRetroArchCore([string]$Root, [string]$System) {
    $es = Join-SsPath $Root 'emulationstation\.emulationstation\es_settings.cfg'
    if (Test-Path -LiteralPath $es) {
        $t = [System.IO.File]::ReadAllText($es)
        $m = [regex]::Match($t, ('<string name="' + [regex]::Escape($System) + '\.core" value="([^"]+)"'))
        if ($m.Success) { return $m.Groups[1].Value }
    }
    $dir = Join-SsPath $Root 'emulationstation\.emulationstation'
    foreach ($sf in @(Get-ChildItem -LiteralPath $dir -Filter 'es_systems*.cfg' -File -ErrorAction SilentlyContinue)) {
        $x = $null
        try { [xml]$x = [System.IO.File]::ReadAllText($sf.FullName) } catch { continue }
        foreach ($s in @($x.SelectNodes('//system'))) {
            if ($null -eq $s -or [string]$s.SelectSingleNode('name').InnerText -ne $System) { continue }
            foreach ($e in @($s.SelectNodes('.//emulator'))) {
                if ([string]$e.GetAttribute('name') -ne 'libretro') { continue }
                $c = $e.SelectSingleNode('.//core')
                if ($null -ne $c) { return [string]$c.InnerText }
            }
        }
    }
    return ''
}

# Can this swept state be jumped into? Needs a copy whose origin RetroBat's
# launch menu reads, or a RetroArch one whose console is known.
function Test-SavestateJumpIn($Savestate, [string]$System) {
    foreach ($c in @($Savestate.Copies)) {
        $k = [string]$c.Kind
        if ($k -eq 'retroarch' -or $k -eq 'dolphin') { return $true }
        if ($k -eq 'retroarch-loose' -and $System -and $System -ne 'autosave') { return $true }
        if ([bool]$c.Menu) { return $true }
        # swept before origins were written down: Dolphin only, and its id-named
        # copy (G8ME01.s01) can always go back to Dolphin's own folder
        if (($k -eq '' -or $k -eq 'dolphin-legacy') -and [string]$c.File -match '\.s\d{2}$' -and
            ($System -eq 'gamecube' -or $System -eq 'wii' -or [string]$c.File -match '__[A-Za-z0-9]{6}\.s\d{2}$')) { return $true }
    }
    return $false
}

# Puts the state back where the launch menu looks and holds it for one game.
# Returns @{ Ok; Message; Placed }.
function Set-SavestateJumpIn([string]$Root, $Savestate, [string]$System, [string]$Display = '') {
    $res = @{ Ok = $false; Message = ''; Placed = 0 }
    # one at a time: anything already waiting is cleared first
    if (@(Get-SsHolds $Root).Count -gt 0) { [void](Clear-SavestateJumpIn $Root) }
    $holds = @(Get-SsHolds $Root)
    $plan = @()   # @{ Src; Dest }
    $placeholders = @()
    foreach ($c in @($Savestate.Copies)) {
        $name = ([string]$c.File -replace '^\d{6}__(\d+-)?', '') -replace '^(StateSaves|dolphin)__', ''
        $k = [string]$c.Kind
        $dest = ''
        if ($k -eq 'retroarch-loose' -or ($k -eq 'retroarch' -and -not $c.Origin)) {
            if (-not $System -or $System -eq 'autosave') { continue }
            $core = Get-SsRetroArchCore $Root $System
            if (-not $core) { continue }
            $dirRel = 'saves\{0}\libretro.{1}' -f $System, $core
            $dir = Join-SsPath $Root $dirRel
            if ((Test-Path -LiteralPath $dir) -and -not [System.IO.Directory]::Exists($dir)) {
                # the empty placeholder file that keeps the menu plain: moved
                # aside for this one game, put back by the game-end sweep
                $waitRel = '_ClaudeWorkspace\SaveBackups\jump-in-placeholders\{0}\libretro.{1}' -f $System, $core
                $placeholders += @{ Rel = $dirRel; Wait = $waitRel }
            }
            $n2 = $name -replace '\.state\.auto$', '.state1'
            $dest = Join-SsPath $dir $n2
        }
        elseif ($c.Origin -and ([bool]$c.Menu -or $k -eq 'dolphin-own' -or $k -eq 'retroarch' -or $k -eq 'dolphin')) {
            $dest = Join-SsPath $Root $c.Origin
        }
        elseif (-not $c.Origin -and $name -match '\.s\d{2}$') {
            # swept before origins were written down (Dolphin only)
            if ($name -match '^[A-Za-z0-9]{6}\.s\d{2}$') { $dest = Join-SsPath $Root ('emulators\dolphin-emu\User\StateSaves\' + $name) }
            elseif ($System -eq 'gamecube' -or $System -eq 'wii') { $dest = Join-SsPath $Root ('saves\{0}\dolphin\{1}' -f $System, $name) }
        }
        if (-not $dest) { continue }
        $plan += @{ Src = [string]$c.Path; Dest = $dest }
        if ($c.Thumb -and (Test-Path -LiteralPath $c.Thumb)) { $plan += @{ Src = [string]$c.Thumb; Dest = ($dest + '.png') } }
    }
    if (@($plan | Where-Object { $_.Src -notmatch '\.png$' }).Count -eq 0) {
        $res.Message = 'This one cannot be jumped into: RetroBat has no way to start this console at a save state.'
        return $res
    }
    $romKey = ''
    try {
        foreach ($ph in $placeholders) {
            $phFull = Join-SsPath $Root $ph.Rel
            $wFull = Join-SsPath $Root $ph.Wait
            if (-not (Test-Path -LiteralPath $phFull) -or [System.IO.Directory]::Exists($phFull)) { continue }
            $wd = Split-Path -Parent $wFull
            if (-not (Test-Path -LiteralPath $wd)) { New-Item -ItemType Directory -Path $wd -Force | Out-Null }
            if (Test-Path -LiteralPath $wFull) { throw ('something is already waiting at ' + $ph.Wait) }
            [System.IO.File]::Move($phFull, $wFull)
            $holds += [pscustomobject]@{ Type = 'placeholder'; Rel = $ph.Rel; Other = $ph.Wait }
            Set-SsHolds $Root $holds
        }
        foreach ($p in $plan) {
            $d = Split-Path -Parent $p.Dest
            if (-not [System.IO.Directory]::Exists($d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
            Copy-Item -LiteralPath $p.Src -Destination $p.Dest -Force -ErrorAction Stop
            $res.Placed++
            $rel = Get-SsRel $Root $p.Dest
            if ($romKey -eq '' -and $p.Dest -notmatch '\.png$') {
                $lf = [System.IO.Path]::GetFileName($p.Dest)
                if ($lf -notmatch '^[A-Za-z0-9]{6}\.s\d{2}$') { $romKey = Get-SsRomKey $lf }
            }
            $holds = @($holds | Where-Object { -not ($_.Type -eq 'file' -and $_.Rel -eq $rel) })
            $holds += [pscustomobject]@{ Type = 'file'; Rel = $rel; Other = $p.Src }
            Set-SsHolds $Root $holds
        }
    }
    catch {
        $res.Message = 'Could not put it back: ' + $_.Exception.Message
        return $res
    }
    $disp = ([string]$Display -replace '[\t\r\n|]', ' ')
    $holds += [pscustomobject]@{ Type = 'game'; Rel = $System; Other = ('{0}|{1}|{2}' -f $romKey, (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $disp) }
    Set-SsHolds $Root $holds
    $res.Ok = $true
    $res.Message = 'ready'
    return $res
}

# What is waiting to be jumped into, for the Saves tab: @{ Ready; Name; Since }.
function Get-SavestateJumpInState([string]$Root) {
    $r = @{ Ready = $false; Name = ''; Since = '' }
    $holds = @(Get-SsHolds $Root)
    if ($holds.Count -eq 0) { return $r }
    $r.Ready = $true
    $g = @($holds | Where-Object { $_.Type -eq 'game' }) | Select-Object -First 1
    if ($null -ne $g) { $f = ([string]$g.Other) -split '\|', 3; $r.Since = $f[1]; if ($f.Count -gt 2) { $r.Name = $f[2] } }
    return $r
}

# Cancel a jump in: the placed copies go (only when unchanged), the
# placeholders come back, the hold list empties. Returns the sweep's answer.
function Clear-SavestateJumpIn([string]$Root) {
    $holds = @(Get-SsHolds $Root)
    if ($holds.Count -eq 0) { return @{ Moved = 0; Dropped = 0; Restored = 0; Messages = @() } }
    # mark it used so the sweep below clears it whatever game ran last
    Set-SsHolds $Root @($holds | Where-Object { $_.Type -ne 'game' })
    if (@(Get-SsHolds $Root).Count -eq 0) { Set-SsHolds $Root @(); return @{ Moved = 0; Dropped = 0; Restored = 0; Messages = @() } }
    return (Invoke-SavestateSweep -Root $Root)
}

# ---------------------------------------------------------------------------
#  Storage limits (SaveBackups\storage.ini, set from the Saves tab)
# ---------------------------------------------------------------------------
#  versions = N   keep the newest N backed-up versions of each save file
#                 (Backup-RetroBatSaves.ps1 reads it). 0 or missing: its own
#                 default (200, and nothing younger than a year is trimmed).
#  states   = N   keep the newest N save states per game in the archive.
#                 0 or missing: keep every one.
#  Both are for friends with small drives. Trimming deletes the oldest for
#  good, which the Saves tab says before anything is set.
function Get-SsStorage([string]$Root) {
    $r = @{ Versions = 0; States = 0 }
    $p = Join-SsPath $Root '_ClaudeWorkspace\SaveBackups\storage.ini'
    if (-not (Test-Path -LiteralPath $p)) { return $r }
    foreach ($line in @([System.IO.File]::ReadAllLines($p))) {
        if ($line -match '^\s*versions\s*=\s*(\d+)') { $r.Versions = [int]$Matches[1] }
        if ($line -match '^\s*states\s*=\s*(\d+)')   { $r.States = [int]$Matches[1] }
    }
    return $r
}

function Set-SsStorage([string]$Root, [int]$Versions, [int]$States) {
    $p = Join-SsPath $Root '_ClaudeWorkspace\SaveBackups\storage.ini'
    $d = Split-Path -Parent $p
    if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
    $t = "; How much the save backups keep. Set from the wizard's Saves tab (Storage).`r`n" +
         "; 0 = keep everything (the default). Trimming deletes the oldest for good.`r`n" +
         "versions = $Versions`r`nstates = $States`r`n"
    [System.IO.File]::WriteAllText($p, $t)
}

# Keeps the newest $Keep save states of each game in the archive, deleting the
# older ones (and their pictures). A game is the file name with its time stamp
# and slot taken off, so Dolphin's two copies of one moment count separately.
function Invoke-SsStatePrune([string]$Root, [int]$Keep) {
    if ($Keep -le 0) { return 0 }
    $arch = Get-SsArchiveRoot $Root
    if (-not [System.IO.Directory]::Exists($arch)) { return 0 }
    $groups = @{}
    foreach ($day in @([System.IO.Directory]::GetDirectories($arch))) {
        $dn = [System.IO.Path]::GetFileName($day)
        if ($dn -notmatch '^\d{4}-\d{2}-\d{2}$') { continue }
        foreach ($f in @([System.IO.Directory]::GetFiles($day))) {
            $leaf = [System.IO.Path]::GetFileName($f)
            if ($leaf -match '\.(png|txt)$') { continue }
            if ($leaf -notmatch '^(\d{6})__(\d+-)?(.+)$') { continue }
            $when = $dn + $Matches[1]
            $base = $Matches[3] -replace '^(StateSaves|dolphin)__', ''
            $base = $base -replace '(\.s\d{2}|\.state(\d*|\.auto)|\.ml\d+|\.\d+\.cst|\.\d{2}\.p2s|\.resume\.p2s|_resume\.sav|_\d{2}\.sav|\.QuickSave\d\.State|\.st\d|\.ds\d|[._]\d{1,3}\.[A-Za-z0-9]+)$', ''
            $k = $base.ToLower()
            if (-not $groups.ContainsKey($k)) { $groups[$k] = New-Object System.Collections.ArrayList }
            [void]$groups[$k].Add(@{ When = $when; Path = $f })
        }
    }
    $gone = 0
    foreach ($k in @($groups.Keys)) {
        $list = @($groups[$k] | Sort-Object { $_.When } -Descending)
        if ($list.Count -le $Keep) { continue }
        foreach ($old in @($list | Select-Object -Skip $Keep)) {
            foreach ($x in @($old.Path, ($old.Path + '.png'), [System.IO.Path]::ChangeExtension($old.Path, '.png'))) {
                if (Test-Path -LiteralPath $x) { try { Remove-Item -LiteralPath $x -Force -ErrorAction Stop } catch { } }
            }
            $gone++
        }
    }
    return $gone
}

# ---------------------------------------------------------------------------
#  The running game (RetroBat's own localhost:1234/runningGame)
# ---------------------------------------------------------------------------
#  Returns @{ Running = $true/$false; Path; System; Known = $false when the
#  answer could not be read }.
function Get-SsRunningGame {
    $r = @{ Running = $false; Path = ''; System = ''; Known = $false }
    try {
        $req = [System.Net.HttpWebRequest]::Create('http://127.0.0.1:1234/runningGame')
        $req.Method = 'GET'; $req.Proxy = $null; $req.Timeout = 1500; $req.ReadWriteTimeout = 1500
        $resp = $req.GetResponse()
        $sr = New-Object System.IO.StreamReader($resp.GetResponseStream())
        $body = $sr.ReadToEnd(); $sr.Close(); $resp.Close()
        $r.Known = $true
        if ($body.Trim() -eq '') { return $r }
        $g = $body | ConvertFrom-Json
        $r.Path = [string]$g.path
        $r.System = [string]$g.systemName
        if ($r.System -eq '') { $r.System = [string]$g.system }
        $r.Running = ($r.Path -ne '' -or $r.System -ne '')
    }
    catch {
        # 404 or similar while nothing runs on some builds: still an answer
        try { if ($_.Exception.Response) { $r.Known = $true } } catch { }
    }
    return $r
}

# ---------------------------------------------------------------------------
#  The auto-save timer
# ---------------------------------------------------------------------------
#  When is a save due? First at FirstMin, then every EveryMin after that.
function Test-SsTimerDue([double]$MinutesIn, [int]$Done, [int]$FirstMin = 45, [int]$EveryMin = 30) {
    $due = $FirstMin + ($Done * $EveryMin)
    return ($MinutesIn -ge $due)
}

# Which emulator owns the window in front, and is its save-state key F2 for
# sure? Returns 'retroarch', 'dolphin' or '' (do nothing).
function Get-SsTimerTarget([string]$Root, [string]$ProcessName) {
    $p = ([string]$ProcessName).ToLower()
    if ($p -like 'retroarch*') {
        $cfg = Join-SsPath $Root 'emulators\retroarch\retroarch.cfg'
        if (Test-Path -LiteralPath $cfg) {
            $t = [System.IO.File]::ReadAllText($cfg)
            if ($t -match '(?m)^input_save_state\s*=\s*"f2"' -and $t -match '(?m)^input_enable_hotkey\s*=\s*"nul"') { return 'retroarch' }
        }
        return ''
    }
    if ($p -like 'dolphin*') {
        $hk = Join-SsPath $Root 'emulators\dolphin-emu\User\Config\Hotkeys.ini'
        if (Test-Path -LiteralPath $hk) {
            $t = [System.IO.File]::ReadAllText($hk)
            if ($t -match '(?m)^Save State/Save to Selected Slot\s*=.*Keyboard Mouse:F2') { return 'dolphin' }
        }
        return ''
    }
    return ''
}
