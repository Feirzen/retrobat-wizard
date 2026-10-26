<#
    NetplayEngine.ps1 - the Netplay tab's engine.

    FUNCTIONS ONLY. Dot-source it. Used by wizard\SetupWizard.ps1 (the Netplay
    tab, and PLAY, which keeps the netplay name in step with the profile).

    THE APPROACH (Steven, 2026-10-10): use what already exists, put it all in
    one place, divided by console, with plain words on how each one works.
    Nothing here is a netplay system of its own:

      NES, SNES, N64 and the other RetroArch consoles   RetroBat's own netplay,
            which is RetroArch's: rollback, lowest lag there is. RetroBat
            keeps three settings for it in es_settings.cfg, written here:
              global.netplay.nickname   the name others see (= the profile)
              global.netplay.relay      '' = direct (default, least lag),
                                        'nyc' = through a relay server, for
                                        when friends cannot get in
              global.netplay.password   the shared wizard password = a
                                        PRIVATE room only wizard users can
                                        join; '' = a public room anyone can
      GameCube and Wii    Dolphin's own netplay, in Dolphin's own window.
                          RetroBat cannot start it, so the tab opens Dolphin
                          with the name and the "share a code" mode set.
      3DS                 Azahar's multiplayer rooms (experimental).
      Steam games         Steam Remote Play Together.
      the rest            Parsec (screen sharing).

    EmulationStation rewrites es_settings.cfg when it closes, so the settings
    are only ever written while RetroBat is closed. The caller checks.

    ASCII ONLY, Windows PowerShell 5.1. Every root is a parameter.
#>

# The password every wizard shares. It keeps strangers on RetroArch's public
# lobby out of a private room; it is not a secret and does not need to be.
$script:NetplaySharedPassword = 'rbwizard-friends'
$script:NetplayRelay = 'nyc'

function Get-NetplayEsPath([string]$Root) {
    return [System.IO.Path]::Combine([System.IO.Path]::Combine([System.IO.Path]::Combine($Root, 'emulationstation'), '.emulationstation'), 'es_settings.cfg')
}

# What RetroBat is set to now. Ok = $false when es_settings.cfg cannot be read.
function Get-NetplaySettings([string]$Root) {
    $r = [pscustomobject]@{ Ok = $false; Enabled = $false; Nickname = ''; Relay = ''; Private = $false }
    $p = Get-NetplayEsPath $Root
    if (-not (Test-Path -LiteralPath $p)) { return $r }
    try {
        [xml]$x = [System.IO.File]::ReadAllText($p)
        $c = $x.SelectSingleNode('/config')
        function V($n) { $node = $c.SelectSingleNode("*[@name='$n']"); if ($null -eq $node) { return '' } return [string]$node.GetAttribute('value') }
        $r.Enabled  = ((V 'global.netplay') -ne 'false')
        $r.Nickname = V 'global.netplay.nickname'
        $r.Relay    = V 'global.netplay.relay'
        $r.Private  = ((V 'global.netplay.password') -ne '')
        $r.Ok = $true
    } catch { }
    return $r
}

# Writes only what differs. $Changes: any of Nickname (string), Relay
# (bool), Private (bool), Enabled (bool). Returns @{ Ok; Changed; Message }.
# A copy of es_settings.cfg goes into archive\netplay_<date>\ first (once a day).
function Set-NetplaySettings([string]$Root, [hashtable]$Changes) {
    $res = @{ Ok = $false; Changed = 0; Message = '' }
    $p = Get-NetplayEsPath $Root
    if (-not (Test-Path -LiteralPath $p)) { $res.Message = 'es_settings.cfg not found.'; return $res }
    try {
        [xml]$x = [System.IO.File]::ReadAllText($p)
        $c = $x.SelectSingleNode('/config')
        if ($null -eq $c) { $res.Message = 'es_settings.cfg has no <config>.'; return $res }
        $want = @{}
        if ($Changes.ContainsKey('Nickname')) {
            $n = ([string]$Changes.Nickname -replace '[^A-Za-z0-9 _.\-]', '').Trim()
            if ($n.Length -gt 32) { $n = $n.Substring(0, 32) }
            if ($n -ne '') { $want['global.netplay.nickname'] = @('string', $n) }
        }
        if ($Changes.ContainsKey('Relay'))   { $want['global.netplay.relay']    = @('string', $(if ($Changes.Relay) { $script:NetplayRelay } else { '' })) }
        if ($Changes.ContainsKey('Private')) { $want['global.netplay.password'] = @('string', $(if ($Changes.Private) { $script:NetplaySharedPassword } else { '' })) }
        if ($Changes.ContainsKey('Enabled')) { $want['global.netplay']          = @('bool',   $(if ($Changes.Enabled) { 'true' } else { 'false' })) }

        foreach ($k in $want.Keys) {
            $type = $want[$k][0]; $val = $want[$k][1]
            $node = $c.SelectSingleNode("*[@name='$k']")
            if ($null -ne $node -and $node.get_Name() -ne $type) { [void]$c.RemoveChild($node); $node = $null }
            if ($null -eq $node) {
                if ($val -eq '' -and $type -eq 'string') { continue }   # absent already means "none"
                $node = $x.CreateElement($type); $node.SetAttribute('name', $k); $node.SetAttribute('value', $val)
                [void]$c.AppendChild($node); $res.Changed++
            }
            elseif ([string]$node.GetAttribute('value') -ne $val) {
                $node.SetAttribute('value', $val); $res.Changed++
            }
        }
        if ($res.Changed -gt 0) {
            $ws = [System.IO.Path]::Combine($Root, '_Wizard')
            # One copy a day, the first one: the settings as they were before
            # the Netplay tab touched them that day (not a folder per click).
            $bak = [System.IO.Path]::Combine([System.IO.Path]::Combine($ws, 'archive'), ('netplay_' + (Get-Date -Format 'yyyy-MM-dd')))
            $bakFile = [System.IO.Path]::Combine($bak, 'es_settings.cfg')
            if (-not (Test-Path -LiteralPath $bakFile)) {
                [void](New-Item -ItemType Directory -Path $bak -Force)
                Copy-Item -LiteralPath $p -Destination $bakFile -Force
            }
            $settings = New-Object System.Xml.XmlWriterSettings
            $settings.Indent = $true; $settings.IndentChars = "`t"
            $settings.Encoding = New-Object System.Text.UTF8Encoding($false)
            $w = [System.Xml.XmlWriter]::Create($p, $settings)
            try { $x.Save($w) } finally { $w.Close() }
        }
        $res.Ok = $true
    }
    catch { $res.Message = $_.Exception.Message }
    return $res
}

# ---------------------------------------------------------------------------
#  Dolphin
# ---------------------------------------------------------------------------
#  Sets [NetPlay] in Dolphin's own Dolphin.ini right before opening it:
#  the name, and TraversalChoice = traversal, which is what gives the host a
#  short code to share instead of needing an open port. RetroBat writes
#  "direct" back when it next starts a game, which does not matter: this runs
#  every time the button is pressed.
function Set-DolphinNetplayIni([string]$Root, [string]$Nickname) {
    $ini = [System.IO.Path]::Combine($Root, 'emulators\dolphin-emu\User\Config\Dolphin.ini')
    $ini = $ini -replace '\\', [string][System.IO.Path]::DirectorySeparatorChar
    if (-not (Test-Path -LiteralPath $ini)) { return $false }
    $lines = New-Object System.Collections.ArrayList
    foreach ($l in [System.IO.File]::ReadAllLines($ini)) { [void]$lines.Add($l) }
    $want = [ordered]@{ TraversalChoice = 'traversal'; TraversalServer = 'stun.dolphin-emu.org'; TraversalPort = '6262' }
    $n = ([string]$Nickname -replace '[^A-Za-z0-9 _.\-]', '').Trim()
    if ($n -ne '') { $want['Nickname'] = $n }

    $start = -1
    for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i].Trim() -eq '[NetPlay]') { $start = $i; break } }
    if ($start -lt 0) { [void]$lines.Add('[NetPlay]'); $start = $lines.Count - 1 }
    $end = $lines.Count
    for ($i = $start + 1; $i -lt $lines.Count; $i++) { if ($lines[$i].Trim().StartsWith('[')) { $end = $i; break } }
    foreach ($k in @($want.Keys)) {
        $found = $false
        for ($i = $start + 1; $i -lt $end; $i++) {
            if ($lines[$i] -match ('^\s*' + [regex]::Escape($k) + '\s*=')) { $lines[$i] = "$k = $($want[$k])"; $found = $true; break }
        }
        if (-not $found) { $lines.Insert($end, "$k = $($want[$k])"); $end++ }
    }
    [System.IO.File]::WriteAllLines($ini, [string[]]$lines.ToArray())
    return $true
}

function Get-DolphinExe([string]$Root) {
    $p = [System.IO.Path]::Combine($Root, 'emulators\dolphin-emu\Dolphin.exe')
    if (Test-Path -LiteralPath $p) { return $p }
    return ''
}
function Get-AzaharExe([string]$Root) {
    $p = [System.IO.Path]::Combine($Root, 'emulators\azahar\azahar.exe')
    if (Test-Path -LiteralPath $p) { return $p }
    return ''
}

# Parsec installs per user or for everyone. '' when it is not on this computer.
function Get-ParsecExe {
    foreach ($base in @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:APPDATA, $env:LOCALAPPDATA)) {
        if (-not $base) { continue }
        foreach ($rel in @('Parsec\parsecd.exe', 'Parsec\app\parsecd.exe')) {
            $p = Join-Path $base $rel
            if (Test-Path -LiteralPath $p) { return $p }
        }
    }
    return ''
}

# ---------------------------------------------------------------------------
#  One plain es_settings.cfg value, for the first-run setup (the theme).
#  Same rules as above: RetroBat closed, only written when it differs, a
#  backup first. Returns $true when something changed.
# ---------------------------------------------------------------------------
function Set-EsStringSetting([string]$Root, [string]$Name, [string]$Value) {
    $p = Get-NetplayEsPath $Root
    if (-not (Test-Path -LiteralPath $p)) { return $false }
    [xml]$x = [System.IO.File]::ReadAllText($p)
    $c = $x.SelectSingleNode('/config')
    if ($null -eq $c) { return $false }
    $node = $c.SelectSingleNode("string[@name='$Name']")
    if ($null -ne $node -and [string]$node.GetAttribute('value') -eq $Value) { return $false }
    if ($null -eq $node) {
        $node = $x.CreateElement('string'); $node.SetAttribute('name', $Name); [void]$c.AppendChild($node)
    }
    $node.SetAttribute('value', $Value)
    $ws = [System.IO.Path]::Combine($Root, '_Wizard')
    $bak = [System.IO.Path]::Combine([System.IO.Path]::Combine($ws, 'archive'), ('settings-setup_' + (Get-Date -Format 'yyyy-MM-dd_HHmmss')))
    [void](New-Item -ItemType Directory -Path $bak -Force)
    Copy-Item -LiteralPath $p -Destination ([System.IO.Path]::Combine($bak, 'es_settings.cfg')) -Force
    $settings = New-Object System.Xml.XmlWriterSettings
    $settings.Indent = $true; $settings.IndentChars = "`t"
    $settings.Encoding = New-Object System.Text.UTF8Encoding($false)
    $w = [System.Xml.XmlWriter]::Create($p, $settings)
    try { $x.Save($w) } finally { $w.Close() }
    return $true
}
