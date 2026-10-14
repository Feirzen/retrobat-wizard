<#
    PlayerCounts.ps1
    ---------------------------------------------------------------------------
    Keeps the "players" number in every game list matching the hand-checked
    list in _ClaudeWorkspace\player-counts.ini.

    WHY IT EXISTS (2026-09-25)
    The scraper fills in "players" from ScreenScraper, which often gives the
    ONLINE count (Call of Duty said 1-12), and a re-scrape silently undid the
    hand fixes made on 2026-09-06. So the checked numbers now live in one
    plain file on the drive, and PLAY copies them back in every launch,
    before RetroBat reads its game lists. A re-scrape can only be wrong until
    the next launch.

    WHAT IT TOUCHES
    Only the <players> line of games that are in player-counts.ini, and only
    in a game list where something actually disagrees. If every number is
    already right, no file is written at all. Everything else in the game
    list - names, art, descriptions, the scraper's other work - is left
    byte for byte as it was. It edits the text rather than re-saving the XML,
    so the layout RetroBat wrote is kept exactly.

    Games matched by FILE NAME, never by title: a title can hide a
    non-breaking space the scraper put there (found 2026-09-06), a file name
    cannot.

    Handheld systems (DS, 3DS, Game Boy...) give 1 to any game not in the
    list (added 2026-10-13). Other games not in the list are left alone and written to
    player-counts-todo.txt, so new games are never missed. That file is
    removed again once every game is covered.

    Loaded by the wizard's Play flow (SetupWizard.ps1, Start-PlayFlow).
    No drive letters: everything comes from the -Root it is handed.
    Windows PowerShell 5.1.
#>

function ConvertTo-PcKey([string]$File) {
    $k = $File.Trim().Replace([string][char]0x00A0, ' ').Replace('\', '/')
    if ($k.StartsWith('./')) { $k = $k.Substring(2) }
    return $k.ToLowerInvariant()
}

function Read-PlayerCountList([string]$Path) {
    # console -> @{ file key -> count }. A count that is not a plain number
    # or range (like ?) is "not checked yet" and treated as missing.
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    $list = @{}
    $section = ''
    foreach ($raw in [System.IO.File]::ReadAllLines($Path, $utf8)) {
        $t = $raw.Trim()
        if ($t -eq '' -or $t.StartsWith(';') -or $t.StartsWith('#')) { continue }
        if ($t -match '^\[([^\]]+)\]') {
            $section = $Matches[1].Trim().ToLowerInvariant()
            if (-not $list.ContainsKey($section)) { $list[$section] = @{} }
            continue
        }
        if ($section -eq '') { continue }
        $parts = $t.Split('|')
        if ($parts.Count -lt 2) { continue }
        $count = $parts[0].Trim()
        $file  = $parts[1].Trim()
        if ($file -eq '' -or $count -notmatch '^\d+(-\d+)?$') { continue }
        $list[$section][(ConvertTo-PcKey $file)] = $count
    }
    return $list
}

function Sync-PlayerCounts {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        # Set by GameInfo.ps1, which gathers every "not checked yet" list
        # into ONE file, new-games-to-check.txt. Without it this still
        # writes its own player-counts-todo.txt, as it always did.
        [switch]$NoTodoFile
    )

    $ws       = Join-Path $Root '_ClaudeWorkspace'
    $listPath = Join-Path $ws 'player-counts.ini'
    $todoPath = Join-Path $ws 'player-counts-todo.txt'
    $romsDir  = Join-Path $Root 'roms'
    $utf8     = New-Object System.Text.UTF8Encoding($false)

    $r = New-Object psobject -Property @{ Ok = $true; Fixed = 0; Files = 0; Todo = 0; TodoLines = @(); Message = '' }
    if (-not (Test-Path -LiteralPath $listPath)) { $r.Message = 'no player-counts.ini, nothing to do'; return $r }
    if (-not (Test-Path -LiteralPath $romsDir))  { $r.Ok = $false; $r.Message = 'no roms folder found'; return $r }

    $list = Read-PlayerCountList $listPath

    # Systems where one screen means one player. A game on one of these that
    # is not in player-counts.ini gets 1 automatically instead of whatever
    # the scraper said (the scraper reports link-cable / wireless counts,
    # which is why DS games showed up as 4 players). To give one of these
    # games a different number, just add it to player-counts.ini.
    $handhelds = @('gb','gbc','gba','nds','3ds','gamegear','psp','ngp','ngpc',
                   'wonderswan','wonderswancolor','pokemini','virtualboy','gw',
                   'flash','scummvm')
    $todo = New-Object System.Collections.ArrayList
    $problems = @()

    $gameRx    = New-Object System.Text.RegularExpressions.Regex('<game\b[^>]*>.*?</game>', 'Singleline')
    $pathRx    = New-Object System.Text.RegularExpressions.Regex('<path>(.*?)</path>', 'Singleline')
    $nameRx    = New-Object System.Text.RegularExpressions.Regex('<name>(.*?)</name>', 'Singleline')
    $playersRx = New-Object System.Text.RegularExpressions.Regex('<players>(.*?)</players>', 'Singleline')
    $indentRx  = New-Object System.Text.RegularExpressions.Regex('\n([ \t]*)<path>')

    foreach ($dir in @(Get-ChildItem -LiteralPath $romsDir -Directory)) {
        $gl = Join-Path $dir.FullName 'gamelist.xml'
        if (-not (Test-Path -LiteralPath $gl)) { continue }
        $console = $dir.Name.ToLowerInvariant()
        $wanted = @{}
        if ($list.ContainsKey($console)) { $wanted = $list[$console] }

        try {
            $text = [System.IO.File]::ReadAllText($gl, $utf8)
            $nl = "`n"
            if ($text.Contains("`r`n")) { $nl = "`r`n" }

            $out = New-Object System.Text.StringBuilder
            $last = 0
            $fixedHere = 0
            foreach ($m in $gameRx.Matches($text)) {
                $block = $m.Value
                $pm = $pathRx.Match($block)
                if (-not $pm.Success) { continue }
                $path = [System.Net.WebUtility]::HtmlDecode($pm.Groups[1].Value)
                $key = ConvertTo-PcKey $path
                $pl = $playersRx.Match($block)
                $current = ''
                if ($pl.Success) { $current = $pl.Groups[1].Value.Trim() }

                if ($wanted.ContainsKey($key)) {
                    $count = [string]$wanted[$key]
                }
                elseif ($handhelds -contains $console) {
                    # Handheld and one-person systems: couch count is 1
                    # unless the list says otherwise (2026-10-13).
                    $count = '1'
                }
                else {
                    $nm = $nameRx.Match($block)
                    $title = $path
                    if ($nm.Success) { $title = [System.Net.WebUtility]::HtmlDecode($nm.Groups[1].Value).Trim() }
                    $says = $current
                    if ($says -eq '') { $says = 'nothing' }
                    $shown = $path.Trim()
                    if ($shown.StartsWith('./')) { $shown = $shown.Substring(2) }
                    [void]$todo.Add(("[{0}]  {1} | {2}   (scraper says {3})" -f $console, $shown, $title, $says))
                    continue
                }

                if ($current -eq $count) { continue }

                if ($pl.Success) {
                    $newBlock = $block.Substring(0, $pl.Index) + '<players>' + $count + '</players>' + $block.Substring($pl.Index + $pl.Length)
                }
                else {
                    $indent = "`t`t"
                    $im = $indentRx.Match($block)
                    if ($im.Success) { $indent = $im.Groups[1].Value }
                    $line = $nl + $indent + '<players>' + $count + '</players>'
                    $anchor = $block.IndexOf('</name>')
                    if ($anchor -ge 0) { $at = $anchor + 7 } else { $at = $pm.Index + $pm.Length }
                    $newBlock = $block.Substring(0, $at) + $line + $block.Substring($at)
                }
                [void]$out.Append($text.Substring($last, $m.Index - $last))
                [void]$out.Append($newBlock)
                $last = $m.Index + $m.Length
                $fixedHere++
            }

            if ($fixedHere -gt 0) {
                [void]$out.Append($text.Substring($last))
                $tmp = $gl + '.players-tmp'
                [System.IO.File]::WriteAllText($tmp, $out.ToString(), $utf8)
                Copy-Item -LiteralPath $tmp -Destination $gl -Force
                Remove-Item -LiteralPath $tmp -Force
                $r.Fixed += $fixedHere
                $r.Files++
            }
        }
        catch {
            $problems += ("{0}: {1}" -f $console, $_.Exception.Message)
        }
    }

    # The to-do list: exists only while something is unchecked.
    try {
        if ($NoTodoFile) { }
        else {
        if ($todo.Count -gt 0) {
            $head = @(
                'Games whose player count has not been checked yet.',
                'They show whatever the scraper said until they are added to player-counts.ini.',
                'This file is rewritten every time PLAY runs, and disappears once every game is covered.',
                ''
            )
            [System.IO.File]::WriteAllLines($todoPath, [string[]]($head + @($todo)), $utf8)
        }
        elseif (Test-Path -LiteralPath $todoPath) {
            Remove-Item -LiteralPath $todoPath -Force
        }
        }
    }
    catch { $problems += ('to-do list: ' + $_.Exception.Message) }

    $r.Todo = $todo.Count
    $r.TodoLines = @($todo)
    $r.Message = ("fixed {0} in {1} game list(s), {2} game(s) not checked yet" -f $r.Fixed, $r.Files, $r.Todo)
    if ($problems.Count -gt 0) {
        $r.Ok = $false
        $r.Message += '; problems: ' + ($problems -join '; ')
    }
    return $r
}
