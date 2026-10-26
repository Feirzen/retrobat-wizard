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

    THE SCRAPER LOGIN (moved 2026-10-26, wizard 3.2). The admin presses
    Share my ScreenScraper login on the Admin page. That keeps the owner's
    copy in Owner\scraper.txt and puts a LOCKED copy (AES, keyed with the
    friends key) in the private friends store, shared/scraper.txt - never in
    the public download. A new setup fetches it into People\social\
    scraper.txt during its first-run setup and unlocks it with its friends
    key. A setup that already has a login keeps its own.

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
    $f = [System.IO.Path]::Combine($Ws, 'Program', 'defaults', 'retrobat-defaults.ini')
    $out = @()
    if (-not (Test-Path -LiteralPath $f)) { return $out }
    foreach ($l in [System.IO.File]::ReadAllLines($f)) {
        $t = $l.Trim()
        if ($t -eq '' -or $t.StartsWith(';') -or $t.StartsWith('#')) { continue }
        if ($t -match '^(bool|int|string|ini)\s+(\S+)\s*=\s*(.*)$') {
            $out += @{ Kind = $Matches[1]; Name = $Matches[2]; Value = $Matches[3].Trim() }
        }
    }
    return $out
}

# Locks a short text with the friends key: "rb2:" + base64(IV + AES-256-CBC).
# Anyone with a friends key can open it; the public download never has it.
function Get-FrdKeyBytes([string]$Key) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { return $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes('rbw-scraper:' + $Key)) } finally { $sha.Dispose() }
}
function Protect-FrdText([string]$Text, [string]$Key) {
    $aes = [System.Security.Cryptography.Aes]::Create()
    try {
        $aes.Key = Get-FrdKeyBytes $Key; $aes.GenerateIV()
        $enc = $aes.CreateEncryptor()
        $plain = [System.Text.Encoding]::UTF8.GetBytes($Text)
        $c = $enc.TransformFinalBlock($plain, 0, $plain.Length)
        $all = New-Object byte[] ($aes.IV.Length + $c.Length)
        [Array]::Copy($aes.IV, 0, $all, 0, $aes.IV.Length); [Array]::Copy($c, 0, $all, $aes.IV.Length, $c.Length)
        return ('rb2:' + [Convert]::ToBase64String($all))
    } finally { $aes.Dispose() }
}
function Unprotect-FrdText([string]$T, [string]$Key) {
    if (-not $T.StartsWith('rb2:') -or $Key -eq '') { return '' }
    try {
        $all = [Convert]::FromBase64String($T.Substring(4))
        $aes = [System.Security.Cryptography.Aes]::Create()
        try {
            $aes.Key = Get-FrdKeyBytes $Key
            $iv = New-Object byte[] 16; [Array]::Copy($all, 0, $iv, 0, 16); $aes.IV = $iv
            $dec = $aes.CreateDecryptor()
            $p = $dec.TransformFinalBlock($all, 16, $all.Length - 16)
            return [System.Text.Encoding]::UTF8.GetString($p)
        } finally { $aes.Dispose() }
    } catch { return '' }
}

# The login to start with: the owner's own (Owner\scraper.txt), else the
# shared one fetched from the friends store (People\social\scraper.txt),
# unlocked with $Key (the friends key).
function Read-FrdScraper([string]$Ws, [string]$Key = '') {
    $r = @{ User = ''; Pass = '' }
    foreach ($rel in @(@('Owner', 'scraper.txt'), @('People', 'social', 'scraper.txt'))) {
        $f = $Ws; foreach ($seg in $rel) { $f = [System.IO.Path]::Combine($f, $seg) }
        if (-not (Test-Path -LiteralPath $f)) { continue }
        foreach ($l in [System.IO.File]::ReadAllLines($f)) {
            foreach ($k in @('user', 'pass')) {
                if ($l -match ('^\s*' + $k + '\s*=\s*(\S+)')) {
                    $v = $Matches[1]
                    $v = $(if ($v.StartsWith('rb2:')) { Unprotect-FrdText $v $Key } else { ConvertFrom-FrdScrambled $v })
                    if ($k -eq 'user') { $r.User = $v } else { $r.Pass = $v }
                }
            }
        }
        if ($r.User -ne '' -and $r.Pass -ne '') { return $r }
        $r = @{ User = ''; Pass = '' }
    }
    return $r
}

# The locked copy for the friends store, from the owner's Owner\scraper.txt.
function Get-FrdSharedScraperText([string]$Ws, [string]$Key) {
    $sc = Read-FrdScraper $Ws ''
    if ($sc.User -eq '' -or $Key -eq '') { return '' }
    return ((@('; The shared ScreenScraper login, locked with the friends key. Made by the Admin page.',
               ('user = ' + (Protect-FrdText $sc.User $Key)),
               ('pass = ' + (Protect-FrdText $sc.Pass $Key)))) -join "`n") + "`n"
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

# One Key=Value in one [Section] of RetroBat's own retrobat.ini. $Name is
# 'Section.Key'. Only changes that one line. Returns $true when it changed.
function Set-FrdRetroBatIni([string]$Root, [string]$Name, [string]$Value) {
    $p = [System.IO.Path]::Combine($Root, 'retrobat.ini')
    if (-not (Test-Path -LiteralPath $p)) { return $false }
    $dot = $Name.IndexOf('.')
    if ($dot -lt 1) { return $false }
    $sec = $Name.Substring(0, $dot); $key = $Name.Substring($dot + 1)
    $lines = [System.Collections.ArrayList]@([System.IO.File]::ReadAllLines($p))
    $in = $false; $at = -1; $secEnd = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $t = ([string]$lines[$i]).Trim()
        if ($t -match '^\[(.+)\]$') { if ($in) { $secEnd = $i; break }; $in = ($Matches[1] -ieq $sec); continue }
        if ($in -and $t -match ('^' + [regex]::Escape($key) + '\s*=\s*(.*)$')) {
            if ($Matches[1].Trim() -eq $Value) { return $false }
            $lines[$i] = $key + '=' + $Value; $at = $i; break
        }
    }
    if ($at -lt 0) {
        if (-not $in -and $secEnd -lt 0) { return $false }     # no such section: leave the file alone
        if ($secEnd -lt 0) { $secEnd = $lines.Count }
        $lines.Insert($secEnd, ($key + '=' + $Value))
    }
    [System.IO.File]::WriteAllLines($p, [string[]]$lines.ToArray())
    return $true
}

# Writes the list (and the scraper login, if there is one and none is set).
# Returns @{ Ok; Changed; Message }.
function Set-FirstRunDefaults([string]$Root, [string]$Ws, [string]$Key = '') {
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
        $all = @(Read-FrdList $Ws)
        foreach ($e in @($all | Where-Object { $_.Kind -ne 'ini' })) { if (Set-FrdNode $x $c $e.Kind $e.Name $e.Value) { $n++ } }
        # 'ini Section.Key = value' lines go to retrobat.ini (2026-10-25: the
        # language switch lives there).
        foreach ($e in @($all | Where-Object { $_.Kind -eq 'ini' })) { try { if (Set-FrdRetroBatIni $Root $e.Name $e.Value) { $n++ } } catch { } }
        $sc = Read-FrdScraper $Ws $Key
        $have = $c.SelectSingleNode("string[@name='ScreenScraperUser']")
        $haveUser = ($null -ne $have -and [string]$have.GetAttribute('value') -ne '')
        if (-not $haveUser -and $sc.User -ne '' -and $sc.Pass -ne '') {
            if (Set-FrdNode $x $c 'string' 'ScreenScraperUser' $sc.User) { $n++ }
            if (Set-FrdNode $x $c 'string' 'ScreenScraperPass' $sc.Pass) { $n++ }
            if (Set-FrdNode $x $c 'string' 'Scraper' 'ScreenScraper') { $n++ }
        }
        if ($n -eq 0) { return @{ Ok = $true; Changed = 0; Message = 'RetroBat already had these settings.' } }
        $bak = [System.IO.Path]::Combine([System.IO.Path]::Combine($Ws, 'Backups', 'Archive'), ('settings-firstrun_' + (Get-Date -Format 'yyyy-MM-dd_HHmmss')))
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
        $od = [System.IO.Path]::Combine($Ws, 'Owner')
        if (-not (Test-Path -LiteralPath $od)) { [void](New-Item -ItemType Directory -Path $od -Force) }
        $f = [System.IO.Path]::Combine($od, 'scraper.txt')
        $lines = @('; The owner''s ScreenScraper login, kept on this drive only. The Admin',
                   '; page puts a LOCKED copy in the private friends store for new setups.',
                   ('user = ' + (ConvertTo-FrdScrambled ([string]$u.GetAttribute('value')))),
                   ('pass = ' + (ConvertTo-FrdScrambled ([string]$pw.GetAttribute('value')))))
        [System.IO.File]::WriteAllLines($f, [string[]]$lines)
        return @{ Ok = $true; Message = 'Saved on this drive.' }
    }
    catch { return @{ Ok = $false; Message = ('Could not save it: ' + $_.Exception.Message) } }
}
