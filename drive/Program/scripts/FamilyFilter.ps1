<#
    FamilyFilter.ps1 - the family-friendly filter: M-rated games out of sight.

    FUNCTIONS ONLY. Dot-source it. Steven, 2026-10-25: "hide games from the
    retrobat menu, from the wizard online library ... and prevent me from
    jumping in to any M rated games from the save menu."

    ON OR OFF: features.ini, "familyfilter = on". Off unless it says on.

    WHICH GAMES:
      defaults\mature-games.txt   the list that ships: games rated M (17+) in
                                  the US, one name per line. A name ending in
                                  * covers every game whose name starts that
                                  way (the whole series).
      family-hide.txt             this setup's own list, the same way, for
                                  games the shipped list does not know (custom
                                  games, ROM hacks). A line starting with !
                                  lets a game through that the shipped list
                                  hides.
    Names are compared loosely: case, accents, punctuation, "(USA)" style tags
    and a leading or trailing "The" do not matter. A game matches by its name
    in RetroBat's game list or by its file name.

    IN RETROBAT: the matching games get <hidden>true</hidden> in their
    gamelist.xml, and RetroBat's "show hidden games" is switched off. Every
    game the filter hid is written down (family-hidden.txt), so switching the
    filter off un-hides exactly those and never a game hidden by hand.
    RetroBat must be closed (it rewrites its game lists when it exits), so
    this runs in the PLAY flow, just before RetroBat starts.

    ASCII ONLY, Windows PowerShell 5.1.
#>

function Join-FfPath([string]$Base, [string]$Rel) {
    $p = $Base
    foreach ($seg in ($Rel -split '[\\/]')) { if ($seg -ne '') { $p = [System.IO.Path]::Combine($p, $seg) } }
    return $p
}

function Test-FfOn([string]$Ws) {
    $f = Join-FfPath $Ws 'Settings\features.ini'
    if (-not (Test-Path -LiteralPath $f)) { return $false }
    foreach ($l in [System.IO.File]::ReadAllLines($f)) { if ($l -match '^\s*familyfilter\s*=\s*(on|true|yes|1)\b') { return $true } }
    return $false
}

# A name, loosely: "Legend of Zelda, The - Twilight Princess (USA) [!]" and
# "The Legend of Zelda: Twilight Princess" both become
# "legend of zelda twilight princess".
function ConvertTo-FfKey([string]$Name) {
    if ($null -eq $Name) { return '' }
    $t = $Name.Replace([string][char]0x00A0, ' ').Normalize([System.Text.NormalizationForm]::FormD)
    $sb = New-Object System.Text.StringBuilder
    foreach ($ch in $t.ToCharArray()) {
        if ([System.Globalization.CharUnicodeInfo]::GetUnicodeCategory($ch) -ne [System.Globalization.UnicodeCategory]::NonSpacingMark) { [void]$sb.Append($ch) }
    }
    $t = $sb.ToString().ToLowerInvariant()
    $t = [regex]::Replace($t, '\.(zip|7z|iso|rvz|wbfs|ciso|wux|wud|rpx|nsp|xci|3ds|cci|cia|nds|gba|gbc|gb|sfc|smc|nes|z64|n64|v64|swf|bat|url|lnk|chd|cue|bin|xiso|elf|wad|nkit)$', '')
    $t = [regex]::Replace($t, '\([^)]*\)|\[[^\]]*\]', ' ')
    $t = $t.Replace('&', ' and ')
    $t = [regex]::Replace($t, '[^a-z0-9]+', ' ').Trim()
    $t = [regex]::Replace($t, '^the\s+', '')
    $t = [regex]::Replace($t, '\s+the(\s|$)', '$1')   # "Legend of Zelda, The - ..." style
    return ([regex]::Replace($t, '\s+', ' ')).Trim()
}

# @{ Exact = @{key=$true}; Prefix = @(keys); Allow = @{key=$true} }
function Get-FfList([string]$Ws) {
    $r = @{ Exact = @{}; Prefix = @(); Allow = @{} }
    foreach ($rel in @('Program\defaults\mature-games.txt', 'Settings\family-hide.txt')) {
        $f = Join-FfPath $Ws $rel
        if (-not (Test-Path -LiteralPath $f)) { continue }
        foreach ($raw in [System.IO.File]::ReadAllLines($f)) {
            $t = $raw.Trim()
            if ($t -eq '' -or $t.StartsWith(';') -or $t.StartsWith('#')) { continue }
            if ($t.StartsWith('!')) { $k = ConvertTo-FfKey $t.Substring(1); if ($k -ne '') { $r.Allow[$k] = $true }; continue }
            if ($t.EndsWith('*')) { $k = ConvertTo-FfKey $t.TrimEnd('*'); if ($k -ne '') { $r.Prefix += $k }; continue }
            $k = ConvertTo-FfKey $t
            if ($k -ne '') { $r.Exact[$k] = $true }
        }
    }
    return $r
}

# Is a game with this name (and/or file name) on the list?
function Test-FfMature($List, [string]$Name, [string]$File = '') {
    foreach ($cand in @($Name, $(if ($File -ne '') { [System.IO.Path]::GetFileName($File.Replace('/', '\')) } else { '' }))) {
        $k = ConvertTo-FfKey $cand
        if ($k -eq '') { continue }
        if ($List.Allow.ContainsKey($k)) { return $false }
        if ($List.Exact.ContainsKey($k)) { return $true }
        foreach ($p in $List.Prefix) { if ($k -eq $p -or $k.StartsWith($p + ' ')) { return $true } }
    }
    return $false
}

$script:FfGameRx = New-Object System.Text.RegularExpressions.Regex('<game\b[^>]*>.*?</game>', 'Singleline')
$script:FfPathRx = New-Object System.Text.RegularExpressions.Regex('<path>(.*?)</path>', 'Singleline')
$script:FfNameRx = New-Object System.Text.RegularExpressions.Regex('<name>(.*?)</name>', 'Singleline')
$script:FfHidRx  = New-Object System.Text.RegularExpressions.Regex('[ \t]*<hidden>\s*true\s*</hidden>[ \t]*\r?\n?', 'IgnoreCase')

# Brings every game list in line with the filter. Returns @{ Hidden; Shown; Message }.
function Sync-FamilyFilter([string]$Root, [string]$Ws) {
    $res = @{ Hidden = 0; Shown = 0; Message = '' }
    $on = Test-FfOn $Ws
    $recF = Join-FfPath $Ws 'Settings\family-hidden.txt'
    # Off, with nothing it hid before: nothing to do, no game list is opened.
    if (-not $on -and -not (Test-Path -LiteralPath $recF)) { $res.Message = 'off'; return $res }
    $list = Get-FfList $Ws
    $rec = @{}
    if (Test-Path -LiteralPath $recF) { foreach ($l in [System.IO.File]::ReadAllLines($recF)) { if ($l -ne '' -and -not $l.StartsWith(';')) { $rec[$l] = $true } } }
    $newRec = @{}
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    $roms = Join-FfPath $Root 'roms'
    if (-not (Test-Path -LiteralPath $roms)) { $res.Message = 'no roms folder'; return $res }
    foreach ($dir in @(Get-ChildItem -LiteralPath $roms -Directory -ErrorAction SilentlyContinue)) {
        $gl = Join-Path $dir.FullName 'gamelist.xml'
        if (-not (Test-Path -LiteralPath $gl)) { continue }
        $text = [System.IO.File]::ReadAllText($gl, $utf8)
        $changed = $false
        $sys = $dir.Name.ToLowerInvariant()
        $out = $script:FfGameRx.Replace($text, [System.Text.RegularExpressions.MatchEvaluator]{
            param($m)
            $g = $m.Value
            $pm = $script:FfPathRx.Match($g)
            if (-not $pm.Success) { return $g }
            $path = [System.Net.WebUtility]::HtmlDecode($pm.Groups[1].Value).Trim()
            $nm = $script:FfNameRx.Match($g)
            $name = $(if ($nm.Success) { [System.Net.WebUtility]::HtmlDecode($nm.Groups[1].Value) } else { '' })
            $id = $sys + '|' + $path
            $isHidden = $script:FfHidRx.IsMatch($g)
            $want = $on -and (Test-FfMature $list $name $path)
            if ($want) {
                if (-not $isHidden) {
                    $ind = '    '
                    $im = [regex]::Match($g, '\n([ \t]*)<path>')
                    if ($im.Success) { $ind = $im.Groups[1].Value }
                    $nl = $(if ($g.Contains("`r`n")) { "`r`n" } else { "`n" })
                    $g = [regex]::Replace($g, '(\r?\n)?([ \t]*)</game>$', ($nl + $ind + '<hidden>true</hidden>' + $nl + '$2</game>'))
                    $script:ffCount.Hidden++; $script:ffChanged = $true
                    $newRec[$id] = $true
                }
                elseif ($rec.ContainsKey($id)) { $newRec[$id] = $true }    # ours from before, still ours
                return $g
            }
            if ($isHidden -and $rec.ContainsKey($id)) {
                # hidden by the filter, and no longer wanted hidden: show it again
                $g = $script:FfHidRx.Replace($g, '', 1)
                $script:ffCount.Shown++; $script:ffChanged = $true
            }
            return $g
        })
        if ($script:ffChanged) {
            $tmp = $gl + '.family-tmp'
            [System.IO.File]::WriteAllText($tmp, $out, $utf8)
            Copy-Item -LiteralPath $tmp -Destination $gl -Force
            Remove-Item -LiteralPath $tmp -Force
            $script:ffChanged = $false
        }
    }
    $res.Hidden = $script:ffCount.Hidden; $res.Shown = $script:ffCount.Shown
    $script:ffCount.Hidden = 0; $script:ffCount.Shown = 0
    if ($newRec.Count -gt 0) {
        [System.IO.File]::WriteAllLines($recF, [string[]](@('; Games the family-friendly filter hid (console|file). It shows exactly these again when switched off.') + @($newRec.Keys | Sort-Object)))
    }
    elseif (Test-Path -LiteralPath $recF) { Remove-Item -LiteralPath $recF -Force }
    if ($on) { [void](Set-FfShowHiddenOff $Root) }
    $res.Message = $(if ($on) { ('on: {0} game(s) newly hidden, {1} hidden in all' -f $res.Hidden, $newRec.Count) } else { ('off: {0} game(s) shown again' -f $res.Shown) })
    return $res
}
$script:ffCount = @{ Hidden = 0; Shown = 0 }
$script:ffChanged = $false

# RetroBat's own "show hidden games" off, or the filter would do nothing.
function Set-FfShowHiddenOff([string]$Root) {
    $p = Join-FfPath $Root 'emulationstation\.emulationstation\es_settings.cfg'
    if (-not (Test-Path -LiteralPath $p)) { return $false }
    $t = [System.IO.File]::ReadAllText($p)
    if ($t -match '<bool name="ShowHiddenGames" value="false"\s*/>') { return $false }
    if ($t -match '<bool name="ShowHiddenGames" value="true"\s*/>') { $t = $t -replace '<bool name="ShowHiddenGames" value="true"\s*/>', '<bool name="ShowHiddenGames" value="false" />' }
    elseif ($t -match '</config>') { $t = $t -replace '</config>', ("`t<bool name=`"ShowHiddenGames`" value=`"false`" />`r`n</config>") }
    else { return $false }
    [System.IO.File]::WriteAllText($p, $t, (New-Object System.Text.UTF8Encoding($false)))
    return $true
}

# Every game name RetroBat shows on this setup (each console's gamelist.xml),
# for the family list's search box (3.2, Steven's flag: "search the games
# instead of typing the name"). Returns @(@{ Name; Console }) sorted by name.
function Get-FfDriveGameNames([string]$Root) {
    $out = @{}
    $roms = Join-FfPath $Root 'roms'
    if (-not (Test-Path -LiteralPath $roms)) { return @() }
    $rx = New-Object System.Text.RegularExpressions.Regex('<game\b[^>]*>.*?<name>(.*?)</name>', 'Singleline')
    foreach ($d in @(Get-ChildItem -LiteralPath $roms -Directory -ErrorAction SilentlyContinue)) {
        $gl = Join-Path $d.FullName 'gamelist.xml'
        if (-not (Test-Path -LiteralPath $gl)) { continue }
        try { $t = [System.IO.File]::ReadAllText($gl) } catch { continue }
        foreach ($m in $rx.Matches($t)) {
            $n = [System.Net.WebUtility]::HtmlDecode($m.Groups[1].Value).Trim()
            if ($n -eq '') { continue }
            $k = $n.ToLower() + '|' + $d.Name.ToLower()
            if (-not $out.ContainsKey($k)) { $out[$k] = [pscustomobject]@{ Name = $n; Console = $d.Name } }
        }
    }
    return @($out.Values | Sort-Object Name, Console)
}

# Adds a name to this setup's own list (family-hide.txt). $Allow: let it
# through instead.
function Add-FfName([string]$Ws, [string]$Name, [bool]$Allow = $false) {
    $f = Join-FfPath $Ws 'Settings\family-hide.txt'
    if (-not (Test-Path -LiteralPath $f)) {
        [System.IO.File]::WriteAllLines($f, [string[]]@(
            '; This setup''s own family-friendly list. One game name per line.',
            '; A name ending in * hides the whole series. A line starting with ! lets a',
            '; game through that the shipped list (defaults\mature-games.txt) hides.'))
    }
    $line = $(if ($Allow) { '!' + $Name.Trim() } else { $Name.Trim() })
    Add-Content -LiteralPath $f -Value $line
}
