<#
    GameInfo.ps1
    ---------------------------------------------------------------------------
    Keeps three hand-checked lists in charge of what the game menus say.
    Run by PLAY (SetupWizard.ps1, Start-PlayFlow) before RetroBat opens, the
    same moment and for the same reason as the Steam shelf: the game lists
    and collections must be right before RetroBat reads them.

        _Wizard\Settings\player-counts.ini  -> <players> in every game list
                                               (scripts\PlayerCounts.ps1)
        _Wizard\Settings\controllers.ini    -> a "Controllers: ..." line at
                                               the top of each Wii and Wii U
                                               description, and the Wii U
                                               controller settings
        _Wizard\Settings\collections.ini    -> which games are in the Zelda
                                               and Pokemon collections

    Anything a list does not cover yet goes into ONE file,
    _Wizard\Settings\new-games-to-check.txt, which disappears once every
    game is covered.

    Added 2026-09-25. Everything here edits TEXT rather than re-saving XML,
    so every other byte RetroBat wrote stays exactly as it was, and a file is
    only written when something in it actually needs to change.

    WINDOWS POWERSHELL 5.1, PURE ASCII, NO DRIVE LETTERS: everything comes
    from the -Root it is handed.
#>

# --- shared helpers ---------------------------------------------------------

# lower case, accents off (e-acute -> e), non-breaking spaces to spaces.
# So "Pokemon" with or without its accent matches "pokemon".
function ConvertTo-GiPlain([string]$Text) {
    if ($null -eq $Text) { return '' }
    $t = $Text.Replace([string][char]0x00A0, ' ').Normalize([System.Text.NormalizationForm]::FormD)
    $sb = New-Object System.Text.StringBuilder
    foreach ($ch in $t.ToCharArray()) {
        if ([System.Globalization.CharUnicodeInfo]::GetUnicodeCategory($ch) -ne [System.Globalization.UnicodeCategory]::NonSpacingMark) {
            [void]$sb.Append($ch)
        }
    }
    return $sb.ToString().ToLowerInvariant()
}

# A game's file as a comparable key: forward slashes, no leading ./, lower.
function ConvertTo-GiKey([string]$File) {
    $k = $File.Trim().Replace([string][char]0x00A0, ' ').Replace('\', '/')
    if ($k.StartsWith('./')) { $k = $k.Substring(2) }
    return $k.ToLowerInvariant()
}

# An ini as an ordered list of sections, each an ordered list of its
# non-comment lines. Sections keep their original name.
function Read-GiIni([string]$Path) {
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    $out = [ordered]@{}
    $cur = $null
    foreach ($raw in [System.IO.File]::ReadAllLines($Path, $utf8)) {
        $t = $raw.Trim()
        if ($t -eq '' -or $t.StartsWith(';') -or $t.StartsWith('#')) { continue }
        if ($t -match '^\[([^\]]+)\]\s*$') {
            $cur = $Matches[1].Trim()
            if (-not $out.Contains($cur)) { $out[$cur] = New-Object System.Collections.ArrayList }
            continue
        }
        if ($null -ne $cur) { [void]$out[$cur].Add($t) }
    }
    return $out
}

# Every roms\<console>\gamelist.xml on the drive.
function Get-GiGameLists([string]$Root) {
    $romsDir = Join-Path $Root 'roms'
    $lists = @()
    if (-not (Test-Path -LiteralPath $romsDir)) { return $lists }
    foreach ($dir in @(Get-ChildItem -LiteralPath $romsDir -Directory)) {
        $gl = Join-Path $dir.FullName 'gamelist.xml'
        if (Test-Path -LiteralPath $gl) {
            $lists += (New-Object psobject -Property @{ Console = $dir.Name; Path = $gl })
        }
    }
    return $lists
}

# Writes a file only through a temporary copy, so a failure part way never
# leaves half a game list behind.
function Write-GiText([string]$Path, [string]$Text) {
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    $tmp = $Path + '.gameinfo-tmp'
    [System.IO.File]::WriteAllText($tmp, $Text, $utf8)
    Copy-Item -LiteralPath $tmp -Destination $Path -Force
    Remove-Item -LiteralPath $tmp -Force
}

$script:GiGameRx = New-Object System.Text.RegularExpressions.Regex('<game\b[^>]*>.*?</game>', 'Singleline')
$script:GiPathRx = New-Object System.Text.RegularExpressions.Regex('<path>(.*?)</path>', 'Singleline')
$script:GiNameRx = New-Object System.Text.RegularExpressions.Regex('<name>(.*?)</name>', 'Singleline')
$script:GiDescRx = New-Object System.Text.RegularExpressions.Regex('<desc>(.*?)</desc>', 'Singleline')
$script:GiIndentRx = New-Object System.Text.RegularExpressions.Regex('\n([ \t]*)<path>')

# ===========================================================================
#  CONTROLLERS
# ===========================================================================
$script:GiControllerPrefix = 'Controllers: '
$script:GiBlockStart = '; === BEGIN: written by PLAY from controllers.ini. Edit controllers.ini, not these lines. ==='
$script:GiBlockEnd   = '; === END: written by PLAY from controllers.ini ==='

function Read-ControllerList([string]$Path) {
    $ini = Read-GiIni $Path
    $kinds = @{}
    $games = @{}     # console -> @{ key -> psobject(Kind, File, Note) }
    foreach ($sec in $ini.Keys) {
        if ($sec -match '^kind\s+(.+)$') {
            $kname = $Matches[1].Trim().ToLowerInvariant()
            $k = New-Object psobject -Property @{ Name = $kname; Label = ''; Menu = ''; Console = ''; Sets = [ordered]@{} }
            foreach ($line in $ini[$sec]) {
                $eq = $line.IndexOf('=')
                if ($eq -lt 1) { continue }
                $key = $line.Substring(0, $eq).Trim()
                $val = $line.Substring($eq + 1).Trim()
                if ($key -ieq 'label') { $k.Label = $val }
                elseif ($key -ieq 'menu') { $k.Menu = $val }
                elseif ($key -ieq 'console') { $k.Console = $val.ToLowerInvariant() }
                elseif ($key.ToLowerInvariant().StartsWith('set.') -and $key.Length -gt 4) { $k.Sets[$key.Substring(4)] = $val }
            }
            $kinds[$kname] = $k
        }
        else {
            $console = $sec.ToLowerInvariant()
            if (-not $games.ContainsKey($console)) { $games[$console] = @{} }
            foreach ($line in $ini[$sec]) {
                $parts = $line.Split('|')
                if ($parts.Count -lt 2) { continue }
                $kind = $parts[0].Trim().ToLowerInvariant()
                $file = $parts[1].Trim()
                if ($kind -eq '' -or $file -eq '') { continue }
                $note = ''
                if ($parts.Count -ge 4) { $note = (($parts[3..($parts.Count - 1)]) -join '|').Trim() }
                $games[$console][(ConvertTo-GiKey $file)] = New-Object psobject -Property @{ Kind = $kind; File = $file; Note = $note }
            }
        }
    }
    return New-Object psobject -Property @{ Kinds = $kinds; Games = $games }
}

# Takes any "Controllers: ..." line this script put at the top of a
# description back off, so it can be written fresh. Works on the escaped
# XML text. The line is always followed by a blank line, or is all there is.
function Remove-ControllerLine([string]$Body) {
    if (-not $Body.StartsWith($script:GiControllerPrefix)) { return $Body }
    foreach ($sep in @("`r`n`r`n", "`n`n")) {
        $at = $Body.IndexOf($sep)
        if ($at -ge 0) { return $Body.Substring($at + $sep.Length) }
    }
    return ''
}

function Sync-Controllers {
    param([Parameter(Mandatory = $true)][string]$Root)

    $ws = Join-Path $Root '_Wizard'
    $listPath = Join-Path $ws 'Settings\controllers.ini'
    $r = New-Object psobject -Property @{ Ok = $true; Fixed = 0; SettingsChanged = $false; TodoLines = @(); Message = '' }
    if (-not (Test-Path -LiteralPath $listPath)) { $r.Message = 'no controllers.ini, nothing to do'; return $r }

    $list = Read-ControllerList $listPath
    $utf8 = New-Object System.Text.UTF8Encoding($false)

    # 2026-10-13: Wii U games that ASK "Wii Remotes or Pro Controller?" as
    # they start (scripts\ControllerChooser.ps1) no longer need the line in
    # their description - the question says it. Their old line is taken back
    # off. Since 2026-10-14 that is every Wii U game (the screen shows a
    # GamePad game's needs too). Wii games keep theirs.
    # With the question switched off ('wiiuchooser = off') every line comes back.
    $chooserOn = $true
    try {
        $featIni = Join-Path $ws 'Settings\features.ini'
        if (Test-Path -LiteralPath $featIni) {
            foreach ($fl in [System.IO.File]::ReadAllLines($featIni)) { if ($fl -match '^\s*wiiuchooser\s*=\s*off\b') { $chooserOn = $false } }
        }
    } catch { }
    $todo = New-Object System.Collections.ArrayList
    $problems = @()
    $settingLines = New-Object System.Collections.ArrayList

    foreach ($gl in @(Get-GiGameLists $Root)) {
        $console = $gl.Console.ToLowerInvariant()
        if (-not $list.Games.ContainsKey($console)) { continue }
        $wanted = $list.Games[$console]
        try {
            $text = [System.IO.File]::ReadAllText($gl.Path, $utf8)
            $nl = "`n"
            if ($text.Contains("`r`n")) { $nl = "`r`n" }
            $out = New-Object System.Text.StringBuilder
            $last = 0
            $fixedHere = 0
            foreach ($m in $script:GiGameRx.Matches($text)) {
                $block = $m.Value
                $pm = $script:GiPathRx.Match($block)
                if (-not $pm.Success) { continue }
                $path = [System.Net.WebUtility]::HtmlDecode($pm.Groups[1].Value)
                $key = ConvertTo-GiKey $path
                $shown = $path.Trim()
                if ($shown.StartsWith('./')) { $shown = $shown.Substring(2) }
                $nm = $script:GiNameRx.Match($block)
                $title = $shown
                if ($nm.Success) { $title = [System.Net.WebUtility]::HtmlDecode($nm.Groups[1].Value).Trim() }

                if (-not $wanted.ContainsKey($key)) {
                    [void]$todo.Add(("[{0}]  {1} | {2}   (no controller line yet - add it to controllers.ini)" -f $console, $shown, $title))
                    continue
                }
                $g = $wanted[$key]
                if (-not $list.Kinds.ContainsKey($g.Kind)) {
                    [void]$todo.Add(("[{0}]  {1} | {2}   (controllers.ini says '{3}', which is not one of its kinds)" -f $console, $shown, $title, $g.Kind))
                    continue
                }
                $kind = $list.Kinds[$g.Kind]

                # the settings this game should have (Wii U, or any kind with set. lines)
                if ($kind.Sets.Count -gt 0) {
                    $leaf = Split-Path $shown -Leaf
                    foreach ($s in $kind.Sets.Keys) {
                        [void]$settingLines.Add(("{0}[{1}].{2} = {3}" -f $console, $leaf, $s, $kind.Sets[$s]))
                    }
                }

                # Asked at launch instead: take any old line back off, write none.
                # 2026-10-14: EVERY Wii U game now opens on that screen (the
                # GamePad ones show what they need instead of a question), so
                # no Wii U game keeps the line.
                if ($chooserOn -and $console -eq 'wiiu') {
                    $dm0 = $script:GiDescRx.Match($block)
                    if (-not $dm0.Success) { continue }
                    $rest0 = Remove-ControllerLine $dm0.Groups[1].Value
                    if ($rest0 -eq $dm0.Groups[1].Value) { continue }
                    $newBlock = $block.Substring(0, $dm0.Index) + '<desc>' + $rest0 + '</desc>' + $block.Substring($dm0.Index + $dm0.Length)
                    [void]$out.Append($text.Substring($last, $m.Index - $last))
                    [void]$out.Append($newBlock)
                    $last = $m.Index + $m.Length
                    $fixedHere++
                    continue
                }

                # the line at the top of the description
                $line = $script:GiControllerPrefix + $kind.Label
                if ($g.Note -ne '') { $line += ' ' + $g.Note }
                $esc = [System.Security.SecurityElement]::Escape($line)
                $dm = $script:GiDescRx.Match($block)
                if ($dm.Success) {
                    $rest = Remove-ControllerLine $dm.Groups[1].Value
                    $body = $esc
                    if ($rest.Trim() -ne '') { $body = $esc + $nl + $nl + $rest }
                    if ($body -eq $dm.Groups[1].Value) { continue }
                    $newBlock = $block.Substring(0, $dm.Index) + '<desc>' + $body + '</desc>' + $block.Substring($dm.Index + $dm.Length)
                }
                else {
                    $indent = "`t`t"
                    $im = $script:GiIndentRx.Match($block)
                    if ($im.Success) { $indent = $im.Groups[1].Value }
                    $anchor = $block.IndexOf('</name>')
                    if ($anchor -ge 0) { $at = $anchor + 7 } else { $at = $pm.Index + $pm.Length }
                    $newBlock = $block.Substring(0, $at) + $nl + $indent + '<desc>' + $esc + '</desc>' + $block.Substring($at)
                }
                [void]$out.Append($text.Substring($last, $m.Index - $last))
                [void]$out.Append($newBlock)
                $last = $m.Index + $m.Length
                $fixedHere++
            }
            if ($fixedHere -gt 0) {
                [void]$out.Append($text.Substring($last))
                Write-GiText $gl.Path $out.ToString()
                $r.Fixed += $fixedHere
            }
        }
        catch { $problems += ("{0}: {1}" -f $console, $_.Exception.Message) }
    }

    # --- keep machine\game-settings.ini in step -------------------------
    #  Only the block between the two markers is ours. Everything else in
    #  that file - its comments, any line somebody typed - is left alone.
    #  SettingsChanged tells PLAY to run Apply-Settings once, so the change
    #  reaches RetroBat before it opens.
    try {
        $gsPath = Join-Path $ws 'Settings\game-settings.ini'
        if (Test-Path -LiteralPath $gsPath) {
            $gsText = [System.IO.File]::ReadAllText($gsPath, $utf8)
            $gnl = "`n"
            if ($gsText.Contains("`r`n")) { $gnl = "`r`n" }
            $sorted = @($settingLines | Sort-Object)
            $block = $script:GiBlockStart + $gnl + (($sorted | ForEach-Object { $_ + $gnl }) -join '') + $script:GiBlockEnd
            $s = $gsText.IndexOf($script:GiBlockStart)
            $e = $gsText.IndexOf($script:GiBlockEnd)
            if ($s -ge 0 -and $e -gt $s) {
                $newText = $gsText.Substring(0, $s) + $block + $gsText.Substring($e + $script:GiBlockEnd.Length)
            }
            else {
                $newText = $gsText.TrimEnd("`r", "`n") + $gnl + $gnl + $block + $gnl
            }
            if ($newText -ne $gsText) {
                Write-GiText $gsPath $newText
                $r.SettingsChanged = $true
            }
        }
        else { $problems += 'Settings\game-settings.ini not found, Wii U settings not written' }
    }
    catch { $problems += ('game-settings.ini: ' + $_.Exception.Message) }

    $r.TodoLines = @($todo)
    $r.Message = ("{0} description line(s) written, settings {1}, {2} game(s) not checked yet" -f $r.Fixed, $(if ($r.SettingsChanged) { 'changed' } else { 'unchanged' }), $todo.Count)
    if ($problems.Count -gt 0) { $r.Ok = $false; $r.Message += '; problems: ' + ($problems -join '; ') }
    return $r
}

# ===========================================================================
#  COLLECTIONS
# ===========================================================================
function Sync-Collections {
    param([Parameter(Mandatory = $true)][string]$Root)

    $ws = Join-Path $Root '_Wizard'
    $listPath = Join-Path $ws 'Settings\collections.ini'
    $colDir = Join-Path $Root 'emulationstation\.emulationstation\collections'
    $r = New-Object psobject -Property @{ Ok = $true; Added = 0; Dropped = 0; Message = '' }
    if (-not (Test-Path -LiteralPath $listPath)) { $r.Message = 'no collections.ini, nothing to do'; return $r }

    $ini = Read-GiIni $listPath
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    $problems = @()
    $notes = @()

    # every game on the drive once: entry as a collection writes it, plus
    # the plain name and plain file name to search in
    $all = New-Object System.Collections.ArrayList
    foreach ($gl in @(Get-GiGameLists $Root)) {
        try {
            $text = [System.IO.File]::ReadAllText($gl.Path, $utf8)
            foreach ($m in $script:GiGameRx.Matches($text)) {
                $pm = $script:GiPathRx.Match($m.Value)
                if (-not $pm.Success) { continue }
                $path = [System.Net.WebUtility]::HtmlDecode($pm.Groups[1].Value).Trim()
                if ($path.StartsWith('./')) { $path = $path.Substring(2) }
                $nm = $script:GiNameRx.Match($m.Value)
                $name = ''
                if ($nm.Success) { $name = [System.Net.WebUtility]::HtmlDecode($nm.Groups[1].Value) }
                [void]$all.Add((New-Object psobject -Property @{
                    Entry = ('./roms/{0}/{1}' -f $gl.Console, $path.Replace('\', '/'))
                    Plain = (ConvertTo-GiPlain ($name + ' | ' + $path))
                    Leaf  = (Split-Path $path -Leaf).ToLowerInvariant()
                }))
            }
        }
        catch { $problems += ("{0}: {1}" -f $gl.Console, $_.Exception.Message) }
    }

    foreach ($sec in $ini.Keys) {
        $cfg = Join-Path $colDir ('custom-' + $sec + '.cfg')
        if (-not (Test-Path -LiteralPath $cfg)) { $notes += ("no collection called {0} in RetroBat" -f $sec); continue }
        try {
            $terms = @(); $never = @{}
            foreach ($line in $ini[$sec]) {
                $eq = $line.IndexOf('=')
                if ($eq -lt 1) { continue }
                $k = $line.Substring(0, $eq).Trim().ToLowerInvariant()
                $v = $line.Substring($eq + 1).Trim()
                if ($k -eq 'match') { foreach ($w in $v.Split(',')) { $p = ConvertTo-GiPlain $w.Trim(); if ($p -ne '') { $terms += $p } } }
                elseif ($k -eq 'never' -and $v -ne '') { $never[(Split-Path $v.Replace('/', '\') -Leaf).ToLowerInvariant()] = $true }
            }

            $text = [System.IO.File]::ReadAllText($cfg, $utf8)
            $nl = "`n"
            if ($text.Contains("`r`n")) { $nl = "`r`n" }
            $old = @([System.Text.RegularExpressions.Regex]::Split($text, "`r?`n") | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })

            $keep = New-Object System.Collections.ArrayList
            $seen = @{}
            foreach ($e in $old) {
                $k = $e.ToLowerInvariant().Replace('\', '/')
                if ($seen.ContainsKey($k)) { $r.Dropped++; continue }
                $rel = $e
                if ($rel.StartsWith('./')) { $rel = $rel.Substring(2) }
                $full = Join-Path $Root $rel.Replace('/', '\')
                $leaf = (Split-Path $rel -Leaf).ToLowerInvariant()
                if ($never.ContainsKey($leaf) -or -not (Test-Path -LiteralPath $full)) { $r.Dropped++; continue }
                $seen[$k] = $true
                [void]$keep.Add($e)
            }
            foreach ($g in $all) {
                $k = $g.Entry.ToLowerInvariant()
                if ($seen.ContainsKey($k) -or $never.ContainsKey($g.Leaf)) { continue }
                $hit = $false
                foreach ($t in $terms) { if ($g.Plain.Contains($t)) { $hit = $true; break } }
                if (-not $hit) { continue }
                $full = Join-Path $Root $g.Entry.Substring(2).Replace('/', '\')
                if (-not (Test-Path -LiteralPath $full)) { continue }
                $seen[$k] = $true
                [void]$keep.Add($g.Entry)
                $r.Added++
            }

            $newText = (($keep | ForEach-Object { $_ + $nl }) -join '')
            if ($newText -ne $text) { Write-GiText $cfg $newText }
        }
        catch { $problems += ("{0}: {1}" -f $sec, $_.Exception.Message) }
    }

    $r.Message = ("{0} added, {1} dead entries dropped" -f $r.Added, $r.Dropped)
    if ($notes.Count -gt 0) { $r.Message += '; ' + ($notes -join '; ') }
    if ($problems.Count -gt 0) { $r.Ok = $false; $r.Message += '; problems: ' + ($problems -join '; ') }
    return $r
}

# ---------------------------------------------------------------------------
#  For the Setup Wizard (Machine tab, One game at a time): read and change
#  one game's kind. The wizard never edits controllers.ini any other way.
# ---------------------------------------------------------------------------

# The kinds one console can use, in the order controllers.ini lists them.
function Get-ControllerKinds([string]$Root, [string]$Console) {
    $listPath = Join-Path $Root '_Wizard\Settings\controllers.ini'
    $out = @()
    if (-not (Test-Path -LiteralPath $listPath)) { return $out }
    $ini = Read-GiIni $listPath
    $list = Read-ControllerList $listPath
    foreach ($sec in $ini.Keys) {
        if ($sec -match '^kind\s+(.+)$') {
            $k = $list.Kinds[$Matches[1].Trim().ToLowerInvariant()]
            if ($null -ne $k -and ($k.Console -eq '' -or $k.Console -eq $Console.ToLowerInvariant())) { $out += $k }
        }
    }
    return $out
}

# console -> @{ game key -> kind name } for every game with a line.
function Get-ControllerAssignments([string]$Root) {
    $listPath = Join-Path $Root '_Wizard\Settings\controllers.ini'
    $out = @{}
    if (-not (Test-Path -LiteralPath $listPath)) { return $out }
    $list = Read-ControllerList $listPath
    foreach ($c in $list.Games.Keys) {
        $out[$c] = @{}
        foreach ($k in $list.Games[$c].Keys) { $out[$c][$k] = $list.Games[$c][$k].Kind }
    }
    return $out
}

# Changes is a list of psobjects: Console, Path (as in the game list, no ./),
# Name, Kind. Rewrites only those games' lines, keeps every comment, and adds
# a line (and the console's section) when the game has none yet. A game's
# extra note is dropped when its kind changes, because a note is written for
# the kind it sat under.
function Set-ControllerKinds([string]$Root, $Changes) {
    $listPath = Join-Path $Root '_Wizard\Settings\controllers.ini'
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    $text = [System.IO.File]::ReadAllText($listPath, $utf8)
    $nl = "`n"
    if ($text.Contains("`r`n")) { $nl = "`r`n" }
    $lines = New-Object System.Collections.ArrayList
    foreach ($l in [System.Text.RegularExpressions.Regex]::Split($text, "`r?`n")) { [void]$lines.Add($l) }
    if ($lines.Count -gt 0 -and [string]$lines[$lines.Count - 1] -eq '') { $lines.RemoveAt($lines.Count - 1) }

    foreach ($ch in @($Changes)) {
        $console = ([string]$ch.Console).ToLowerInvariant()
        $key = ConvertTo-GiKey ([string]$ch.Path)
        $section = ''
        $sectionEnd = -1       # index after the last line of the console's section
        $done = $false
        for ($i = 0; $i -lt $lines.Count; $i++) {
            $t = ([string]$lines[$i]).Trim()
            if ($t -match '^\[([^\]]+)\]') {
                if ($section -eq $console) { $sectionEnd = $i }
                $section = $Matches[1].Trim().ToLowerInvariant()
                continue
            }
            if ($section -ne $console -or $t -eq '' -or $t.StartsWith(';')) { continue }
            $parts = $t.Split('|')
            if ($parts.Count -lt 2) { continue }
            if ((ConvertTo-GiKey $parts[1]) -ne $key) { continue }
            $oldKind = $parts[0].Trim().ToLowerInvariant()
            $name = ''
            if ($parts.Count -ge 3) { $name = $parts[2].Trim() }
            $new = ('{0,-19}| {1} | {2}' -f $ch.Kind, $parts[1].Trim(), $name)
            if ($oldKind -eq ([string]$ch.Kind).ToLowerInvariant() -and $parts.Count -ge 4) {
                $new += ' | ' + (($parts[3..($parts.Count - 1)]) -join '|').Trim()
            }
            $lines[$i] = $new.TrimEnd()
            $done = $true
            break
        }
        if ($done) { continue }
        if ($section -eq $console -and $sectionEnd -lt 0) { $sectionEnd = $lines.Count }
        $line = ('{0,-19}| {1} | {2}' -f $ch.Kind, ([string]$ch.Path).Replace('\', '/'), [string]$ch.Name).TrimEnd()
        if ($sectionEnd -ge 0) {
            # after the section's last non-blank line
            $at = $sectionEnd
            while ($at -gt 0 -and ([string]$lines[$at - 1]).Trim() -eq '') { $at-- }
            $lines.Insert($at, $line)
        }
        else {
            [void]$lines.Add('')
            [void]$lines.Add('[' + $console + ']')
            [void]$lines.Add($line)
        }
    }
    Write-GiText $listPath ((($lines | ForEach-Object { [string]$_ }) -join $nl) + $nl)
}

# ===========================================================================
#  ALL THREE, AND THE ONE TO-DO FILE
# ===========================================================================
function Invoke-GameInfoSync {
    param([Parameter(Mandatory = $true)][string]$Root)

    $ws = Join-Path $Root '_Wizard'
    $todoPath = Join-Path $ws 'Settings\new-games-to-check.txt'
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    $msgs = @()
    $todo = @()
    $settingsChanged = $false

    if (Get-Command Sync-PlayerCounts -ErrorAction SilentlyContinue) {
        try {
            $pc = Sync-PlayerCounts -Root $Root -NoTodoFile
            $msgs += ('player counts: ' + $pc.Message)
            foreach ($l in @($pc.TodoLines)) { $todo += ($l + '   [player count]') }
        }
        catch { $msgs += ('player counts: failed - ' + $_.Exception.Message) }
        # the file it used to write on its own, before this one gathered them
        $oldTodo = Join-Path $ws 'Settings\player-counts-todo.txt'
        if (Test-Path -LiteralPath $oldTodo) { try { Remove-Item -LiteralPath $oldTodo -Force } catch { } }
    }
    try {
        $cr = Sync-Controllers -Root $Root
        $msgs += ('controllers: ' + $cr.Message)
        $todo += @($cr.TodoLines)
        $settingsChanged = [bool]$cr.SettingsChanged
    }
    catch { $msgs += ('controllers: failed - ' + $_.Exception.Message) }
    try {
        $co = Sync-Collections -Root $Root
        $msgs += ('collections: ' + $co.Message)
    }
    catch { $msgs += ('collections: failed - ' + $_.Exception.Message) }

    try {
        if ($todo.Count -gt 0) {
            $head = @(
                'Games that one of the hand-checked lists does not cover yet.',
                'Until they are added they keep whatever the scraper said. The fix for each line:',
                '  [player count]  add a line to player-counts.ini',
                '  controller      add a line to controllers.ini',
                'Or ask Claude to check them. This file is rewritten every time PLAY runs,',
                'and disappears once every game is covered.',
                ''
            )
            [System.IO.File]::WriteAllLines($todoPath, [string[]]($head + $todo), $utf8)
        }
        elseif (Test-Path -LiteralPath $todoPath) { Remove-Item -LiteralPath $todoPath -Force }
    }
    catch { $msgs += ('to-check list: ' + $_.Exception.Message) }

    return New-Object psobject -Property @{ SettingsChanged = $settingsChanged; Messages = $msgs; Todo = $todo.Count }
}
