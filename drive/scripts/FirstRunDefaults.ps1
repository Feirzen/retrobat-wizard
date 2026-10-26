<#
    FirstRunDefaults.ps1 - the RetroBat settings a NEW setup starts with.

    FUNCTIONS ONLY. Dot-source it. Used once, by the wizard's first-run setup
    (Start-SetupFlow), never on updates: Steven, 2026-10-17, "a lot of
    customizations I have made that I want to be the default for everyone ...
    I don't think we need the wizard reinforcing those little things on every
    update, but yes on the first run." Anything a person changes afterwards in
    RetroBat stays changed. (Apply-Settings.ps1 is the other list, the one
    that IS put back after every update, for things that break games.)

    THE LIST is defaults\retrobat-defaults.ini, one line each:
        bool   audio.bgmusic          = false
        string CollectionSystemsAuto  = 2players,4players,all
    so it can be changed without touching this file.

    THE SCRAPER LOGIN. defaults\scraper.txt, when it exists, holds a
    ScreenScraper user and password (scrambled the same way as the friends
    key: not secret, just not plain text). The Admin page makes it from the
    owner's own login, on purpose, after a warning that it ships to everybody.
    A setup that already has a login keeps its own.

    RetroBat must be closed (es_settings.cfg is rewritten when it exits). One
    backup of es_settings.cfg goes into archive\ first.

    ASCII ONLY, Windows PowerShell 5.1.
#>

function Get-FrdEsPath([string]$Root) {
    return [System.IO.Path]::Combine($Root, 'emulationstation', '.emulationstation', 'es_settings.cfg')
}

# 'rb1:' + base64 of the text backwards <-> the text.
function ConvertFrom-FrdScrambled([string]$T) {
    if (-not $T.StartsWith('rb1:')) { return $T }
    try {
        $rev = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($T.Substring(4)))
        $a = $rev.ToCharArray(); [array]::Reverse($a); return (-join $a)
    } catch { return '' }
}
function ConvertTo-FrdScrambled([string]$T) {
    $a = $T.ToCharArray(); [array]::Reverse($a)
    return ('rb1:' + [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes((-join $a))))
}

# The list: @( @{ Kind; Name; Value } ... ), in file order.
function Read-FrdList([string]$Ws) {
    $f = [System.IO.Path]::Combine($Ws, 'defaults', 'retrobat-defaults.ini')
    $out = @()
    if (-not (Test-Path -LiteralPath $f)) { return $out }
    foreach ($l in [System.IO.File]::ReadAllLines($f)) {
        $t = $l.Trim()
        if ($t -eq '' -or $t.StartsWith(';') -or $t.StartsWith('#')) { continue }
        if ($t -match '^(bool|int|string)\s+(\S+)\s*=\s*(.*)$') {
            $out += @{ Kind = $Matches[1]; Name = $Matches[2]; Value = $Matches[3].Trim() }
        }
    }
    return $out
}

function Read-FrdScraper([string]$Ws) {
    $f = [System.IO.Path]::Combine($Ws, 'defaults', 'scraper.txt')
    $r = @{ User = ''; Pass = '' }
    if (-not (Test-Path -LiteralPath $f)) { return $r }
    foreach ($l in [System.IO.File]::ReadAllLines($f)) {
        if ($l -match '^\s*user\s*=\s*(\S+)') { $r.User = ConvertFrom-FrdScrambled $Matches[1] }
        if ($l -match '^\s*pass\s*=\s*(\S+)') { $r.Pass = ConvertFrom-FrdScrambled $Matches[1] }
    }
    return $r
}

function Set-FrdNode($Xml, $Config, [string]$Kind, [string]$Name, [string]$Value) {
    # Any older node of another kind with the same name goes, so there is one.
    foreach ($k in @('bool', 'int', 'string')) {
        if ($k -eq $Kind) { continue }
        foreach ($n in @($Config.SelectNodes("$k[@name='$Name']"))) { [void]$Config.RemoveChild($n) }
    }
    $node = $Config.SelectSingleNode("$Kind[@name='$Name']")
    if ($null -ne $node -and [string]$node.GetAttribute('value') -eq $Value) { return $false }
    if ($null -eq $node) { $node = $Xml.CreateElement($Kind); $node.SetAttribute('name', $Name); [void]$Config.AppendChild($node) }
    $node.SetAttribute('value', $Value)
    return $true
}

# Writes the list (and the scraper login, if there is one and none is set).
# Returns @{ Ok; Changed; Message }.
function Set-FirstRunDefaults([string]$Root, [string]$Ws) {
    $p = Get-FrdEsPath $Root
    if (-not (Test-Path -LiteralPath $p)) {
        # RetroBat never opened yet: start the file; RetroBat fills in the rest.
        $d = Split-Path $p -Parent
        if (-not (Test-Path -LiteralPath $d)) { return @{ Ok = $false; Changed = 0; Message = 'RetroBat''s settings folder is not there.' } }
        [System.IO.File]::WriteAllText($p, "<?xml version=`"1.0`"?>`r`n<config>`r`n</config>`r`n")
    }
    try {
        [xml]$x = [System.IO.File]::ReadAllText($p)
        $c = $x.SelectSingleNode('/config')
        if ($null -eq $c) { return @{ Ok = $false; Changed = 0; Message = 'es_settings.cfg could not be read.' } }
        $n = 0
        foreach ($e in (Read-FrdList $Ws)) { if (Set-FrdNode $x $c $e.Kind $e.Name $e.Value) { $n++ } }
        $sc = Read-FrdScraper $Ws
        $have = $c.SelectSingleNode("string[@name='ScreenScraperUser']")
        $haveUser = ($null -ne $have -and [string]$have.GetAttribute('value') -ne '')
        if (-not $haveUser -and $sc.User -ne '' -and $sc.Pass -ne '') {
            if (Set-FrdNode $x $c 'string' 'ScreenScraperUser' $sc.User) { $n++ }
            if (Set-FrdNode $x $c 'string' 'ScreenScraperPass' $sc.Pass) { $n++ }
            if (Set-FrdNode $x $c 'string' 'Scraper' 'ScreenScraper') { $n++ }
        }
        if ($n -eq 0) { return @{ Ok = $true; Changed = 0; Message = 'RetroBat already had these settings.' } }
        $bak = [System.IO.Path]::Combine([System.IO.Path]::Combine($Ws, 'archive'), ('settings-firstrun_' + (Get-Date -Format 'yyyy-MM-dd_HHmmss')))
        [void](New-Item -ItemType Directory -Path $bak -Force)
        Copy-Item -LiteralPath $p -Destination ([System.IO.Path]::Combine($bak, 'es_settings.cfg')) -Force
        $set = New-Object System.Xml.XmlWriterSettings
        $set.Indent = $true; $set.IndentChars = '  '
        $set.Encoding = New-Object System.Text.UTF8Encoding($false)
        $w = [System.Xml.XmlWriter]::Create($p, $set)
        try { $x.Save($w) } finally { $w.Close() }
        return @{ Ok = $true; Changed = $n; Message = ("{0} RetroBat setting(s) set to the drive's defaults." -f $n) }
    }
    catch { return @{ Ok = $false; Changed = 0; Message = ('The defaults could not be written: ' + $_.Exception.Message) } }
}

# The owner's own login -> defaults\scraper.txt, so new setups scrape by
# themselves. Only from the Admin page, after a warning. @{ Ok; Message }.
function Save-FrdScraperFromThisSetup([string]$Root, [string]$Ws) {
    $p = Get-FrdEsPath $Root
    try {
        [xml]$x = [System.IO.File]::ReadAllText($p)
        $u = $x.SelectSingleNode("/config/string[@name='ScreenScraperUser']")
        $pw = $x.SelectSingleNode("/config/string[@name='ScreenScraperPass']")
        if ($null -eq $u -or $null -eq $pw -or [string]$u.GetAttribute('value') -eq '' -or [string]$pw.GetAttribute('value') -eq '') {
            return @{ Ok = $false; Message = 'No ScreenScraper login is saved in RetroBat on this setup. Sign in first: open RetroBat, press START, SCRAPER, then your ScreenScraper user and password.' }
        }
        $f = [System.IO.Path]::Combine($Ws, 'defaults', 'scraper.txt')
        $lines = @('; The ScreenScraper login every new setup starts with. Made by the Admin',
                   '; page from the owner''s own login. Scrambled, NOT secret: it ships to',
                   '; everybody with the next published update. Delete this file to stop.',
                   ('user = ' + (ConvertTo-FrdScrambled ([string]$u.GetAttribute('value')))),
                   ('pass = ' + (ConvertTo-FrdScrambled ([string]$pw.GetAttribute('value')))))
        [System.IO.File]::WriteAllLines($f, [string[]]$lines)
        return @{ Ok = $true; Message = 'Saved. New setups will scrape with this login once the next update is published.' }
    }
    catch { return @{ Ok = $false; Message = ('Could not save it: ' + $_.Exception.Message) } }
}
