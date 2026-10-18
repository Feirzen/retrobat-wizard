<#
    Apply-GraphicPacks.ps1 - per-game Cemu settings, for the handful of Wii U
    games that need them.

    Run it from:  Maintenance Steps\Apply Cemu Graphic Packs.bat

    WHY THIS EXISTS. RetroBat's tier system sets Wii U options for the whole
    console. It has no way to say "everything is fine except Breath of the
    Wild", which is the actual problem: BOTW is far heavier than anything else
    in this collection and dropping the whole console to Low to suit it would
    punish twenty other games.

    Cemu's own answer is graphic packs: per-game, already downloaded on this
    drive under emulators\cemu\portable\graphicPacks\downloadedGraphicPacks\,
    and switched on in Cemu's settings.xml. RetroBat does not expose them, so
    this does.

    IT IS A BUTTON, NOT A STEP. It is deliberately NOT part of
    RUN THIS AFTER AN UPDATE.bat. Cemu writes settings.xml itself every time
    it closes, and RetroBat edits it on every launch; a script that fought
    both of them on a schedule is exactly the trap this drive has already
    fallen into once. Press it when a pack is missing, which the button will
    tell you.

    IT IS ADDITIVE. It never removes an entry it did not put there, so any
    pack switched on by hand in Cemu's own window survives.

    IT VERIFIES BEFORE IT WRITES. Every preset name below is checked against
    that pack's own rules.txt first. A misspelt preset name is silently
    ignored by Cemu and falls back to the default, which is the kind of quiet
    wrong answer this drive has been bitten by before, so it is refused here
    instead.

    PURE ASCII on purpose. Windows PowerShell reads a script with no
    byte-order mark as ANSI.
#>

[CmdletBinding()]
param(
    # Empty and resolved in the body, never in the param block: under -File
    # $PSScriptRoot is not populated while defaults are worked out, and a
    # script that builds a path there dies before it can say why.
    [string] $RetroBatRoot = '',
    [switch] $WhatIf,
    [switch] $Quiet
)

$ErrorActionPreference = 'Stop'

function Say([string]$msg, [string]$colour = 'Gray') {
    if (-not $Quiet) { Write-Host $msg -ForegroundColor $colour }
}


# ===========================================================================
#  THE LIST - edit this and nothing else
# ===========================================================================
#  One entry per graphic pack to switch on.
#
#    pack     the folder under graphicPacks\downloadedGraphicPacks\,
#             using backslashes. The rules.txt inside it is what Cemu loads
#    why      one line, shown on screen. Say what it buys
#    vendor   ''       apply on any computer
#             'nvidia' only on an Nvidia card, and so on. Some packs exist
#                      purely to work around one brand's driver bugs, and
#                      applying those on another brand causes the artifact
#                      rather than fixing it
#    presets  category and preset name, both exactly as they appear in that
#             pack's rules.txt. Leave a category out to keep the pack's own
#             default for it
#
#  BREATH OF THE WILD is the only game here so far, because it is the only
#  one on this drive that misbehaves. The Quadro P2200 in the ZTower is
#  roughly a GTX 1060, which BOTW is genuinely heavy for.
#
#  DELIBERATELY NOT ENABLED: Mods\FPS++, the framerate unlock. It is the
#  first thing everybody reaches for and it is the wrong tool here. It helps
#  when a machine can comfortably beat 30fps and wants 60; on a card that is
#  hovering around 30 it makes the frame time less even, not more, and it
#  alters the game's own physics timing. Leave it off unless the machine is
#  clearly fast enough, and then turn it on from Cemu's own window rather
#  than from here.
# ---------------------------------------------------------------------------
$Packs = @(
    @{
        pack   = 'BreathOfTheWild\Graphics'
        why    = 'BOTW at 720p with cheap shadows. The biggest dial on this game.'
        vendor = ''
        presets = @(
            @{ category = 'Resolution';           preset = '1280x720 (HD, Default)' },
            @{ category = 'Shadows';              preset = 'Low (50%)' },
            @{ category = 'Shadow Draw Distance'; preset = 'Low (Low Draw Distance, Sharp Shadows)' }
        )
    },
    @{
        pack   = 'BreathOfTheWild\Enhancements'
        why    = 'Cheaper reflections and texture filtering. Barely visible, not free.'
        vendor = ''
        presets = @(
            @{ category = 'Anisotropic Filtering'; preset = 'Low (1x)' },
            @{ category = 'Reflection Range';      preset = 'Extra Low (2 samples)' }
        )
    },
    @{
        pack   = 'BreathOfTheWild\Workarounds\NVIDIAExplosionSmoke'
        why    = 'Fixes the huge square smoke on Nvidia cards. Not a speed change.'
        vendor = 'nvidia'
        presets = @()
    },
    @{
        pack   = 'BreathOfTheWild\Workarounds\NVIDIAStretchedClouds'
        why    = 'Fixes stretched clouds on Nvidia cards. Not a speed change.'
        vendor = 'nvidia'
        presets = @()
    }
)
# ===========================================================================


# --- locate RetroBat -------------------------------------------------------
if ([string]::IsNullOrWhiteSpace($RetroBatRoot)) {
    $RetroBatRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
}
if (-not (Test-Path (Join-Path $RetroBatRoot 'retrobat.ini'))) {
    Say "ERROR: could not find retrobat.ini above this script." 'Red'
    Say "       Expected RetroBat at: $RetroBatRoot" 'Red'
    exit 1
}

$CemuPortable = Join-Path $RetroBatRoot 'emulators\cemu\portable'
$SettingsPath = Join-Path $CemuPortable 'settings.xml'
$PackRoot     = Join-Path $CemuPortable 'graphicPacks\downloadedGraphicPacks'
$ArchiveDir   = Join-Path $RetroBatRoot '_ClaudeWorkspace\archive'

Say ""
Say "  Cemu graphic packs" 'White'
Say "  ---------------------------------------------------------------------" 'DarkGray'
Say ""

if (-not (Test-Path -LiteralPath $SettingsPath)) {
    Say "  Cemu has no settings.xml yet." 'Yellow'
    Say "  Launch a Wii U game once so Cemu writes one, then run this again." 'Gray'
    Say ""
    exit 0
}

# --- nothing may be holding the file --------------------------------------
# Cemu rewrites settings.xml when it closes and RetroBat edits it on every
# launch. Writing underneath either of them means the change is thrown away a
# minute later, silently, which is the worst way for this to fail.
foreach ($p in @('cemu', 'emulationstation', 'retrobat')) {
    if (@(Get-Process -Name $p -ErrorAction SilentlyContinue).Count -gt 0) {
        Say ("  {0} is running. Close it first." -f $p) 'Yellow'
        Say  "  Cemu and RetroBat both rewrite this file, so anything written" 'Gray'
        Say  "  now would be thrown away when they close." 'Gray'
        Say ""
        exit 1
    }
}

# --- which brand of card is in this machine --------------------------------
$vendor = 'unknown'
$engine = Join-Path $PSScriptRoot 'ProfileEngine.ps1'
if (Test-Path -LiteralPath $engine) {
    try {
        . $engine
        $gpu    = Get-GpuName
        $vendor = Get-GpuVendor $gpu
        Say ("  Graphics card   {0}  ({1})" -f $gpu, $vendor) 'Gray'
    }
    catch { Say ("  Could not read the graphics card: {0}" -f $_.Exception.Message) 'Yellow' }
}
else {
    Say "  ProfileEngine.ps1 is missing, so brand-specific packs are skipped." 'Yellow'
}
Say ""


# ---------------------------------------------------------------------------
#  Is a preset name real? Read the pack's own rules.txt and find out.
# ---------------------------------------------------------------------------
#  Cemu silently ignores a preset name it does not recognise and quietly uses
#  the default instead, so a typo here would look exactly like the pack not
#  working. Checking costs one file read.
# ---------------------------------------------------------------------------
function Get-PackPresets([string]$RulesPath) {
    $out = @{}
    if (-not (Test-Path -LiteralPath $RulesPath)) { return $out }
    $lines = @()
    try { $lines = @([System.IO.File]::ReadAllLines($RulesPath)) } catch { return $out }

    $name = ''; $cat = ''; $inPreset = $false
    foreach ($raw in $lines) {
        $t = $raw.Trim()
        if ($t -eq '[Preset]') {
            if ($inPreset -and $cat -ne '' -and $name -ne '') {
                if (-not $out.ContainsKey($cat)) { $out[$cat] = @() }
                $out[$cat] += $name
            }
            $inPreset = $true; $name = ''; $cat = ''
            continue
        }
        if ($t.StartsWith('[')) {
            if ($inPreset -and $cat -ne '' -and $name -ne '') {
                if (-not $out.ContainsKey($cat)) { $out[$cat] = @() }
                $out[$cat] += $name
            }
            $inPreset = $false; $name = ''; $cat = ''
            continue
        }
        if (-not $inPreset) { continue }
        $eq = $t.IndexOf('=')
        if ($eq -lt 1) { continue }
        $k = $t.Substring(0, $eq).Trim().ToLower()
        $v = $t.Substring($eq + 1).Trim()
        if ($k -eq 'name')     { $name = $v }
        elseif ($k -eq 'category') { $cat = $v }
    }
    # the last block in the file has no following [ to close it
    if ($inPreset -and $cat -ne '' -and $name -ne '') {
        if (-not $out.ContainsKey($cat)) { $out[$cat] = @() }
        $out[$cat] += $name
    }
    return $out
}


# ---------------------------------------------------------------------------
#  Work out what needs doing, without touching anything
# ---------------------------------------------------------------------------
$wanted   = @()
$skipped  = 0
$problems = 0

foreach ($p in $Packs) {
    $packPath = [string]$p.pack
    $need     = [string]$p.vendor

    if ($need -ne '' -and $need -ne $vendor) {
        Say ("  skipped  {0}" -f $packPath) 'DarkGray'
        Say ("           only for {0} cards, this one is {1}" -f $need, $vendor) 'DarkGray'
        $skipped++
        continue
    }

    $rules = Join-Path (Join-Path $PackRoot $packPath) 'rules.txt'
    if (-not (Test-Path -LiteralPath $rules)) {
        Say ("  MISSING  {0}" -f $packPath) 'Yellow'
        Say  "           that pack is not in this setup, nothing done for it" 'DarkGray'
        $problems++
        continue
    }

    $known = Get-PackPresets $rules
    $ok    = $true
    foreach ($pre in @($p.presets)) {
        $c = [string]$pre.category
        $n = [string]$pre.preset
        if (-not $known.ContainsKey($c)) {
            Say ("  REFUSED  {0}" -f $packPath) 'Red'
            Say ("           that pack has no category called '{0}'" -f $c) 'DarkGray'
            $ok = $false; $problems++
            break
        }
        if (@($known[$c]) -notcontains $n) {
            Say ("  REFUSED  {0}" -f $packPath) 'Red'
            Say ("           '{0}' is not a preset in '{1}'. Real ones:" -f $n, $c) 'DarkGray'
            foreach ($real in @($known[$c])) { Say ("             {0}" -f $real) 'DarkGray' }
            $ok = $false; $problems++
            break
        }
    }
    if (-not $ok) { continue }

    # The path Cemu stores is relative to the portable folder, forward
    # slashed, exactly as Cemu writes it itself.
    $wanted += @{
        Key     = ('graphicPacks/downloadedGraphicPacks/{0}/rules.txt' -f ($packPath -replace '\\', '/'))
        Pack    = $packPath
        Why     = [string]$p.why
        Presets = @($p.presets)
    }
}

if ($wanted.Count -eq 0) {
    Say ""
    Say "  Nothing to apply." 'Yellow'
    Say ""
    exit $(if ($problems -gt 0) { 1 } else { 0 })
}


# ---------------------------------------------------------------------------
#  Read settings.xml and work out what would change
# ---------------------------------------------------------------------------
$xml = New-Object System.Xml.XmlDocument
try { $xml.Load($SettingsPath) }
catch {
    Say ("  settings.xml could not be read: {0}" -f $_.Exception.Message) 'Red'
    Say  "  Nothing was changed." 'Gray'
    Say ""
    exit 1
}

$root = $xml.DocumentElement
$gp   = $root.SelectSingleNode('GraphicPack')
if ($null -eq $gp) {
    $gp = $xml.CreateElement('GraphicPack')
    [void]$root.AppendChild($gp)
}

$changed = 0
$same    = 0

foreach ($w in $wanted) {
    $entry = $null
    foreach ($e in @($gp.SelectNodes('Entry'))) {
        if ([string]$e.GetAttribute('filename') -eq $w.Key) { $entry = $e; break }
    }

    # what it should look like, as a plain list of "category|preset"
    $want = @()
    foreach ($pre in @($w.Presets)) { $want += ('{0}|{1}' -f $pre.category, $pre.preset) }

    $have = @()
    if ($null -ne $entry) {
        foreach ($pn in @($entry.SelectNodes('Preset'))) {
            $c = $pn.SelectSingleNode('category'); $n = $pn.SelectSingleNode('preset')
            if ($null -ne $c -and $null -ne $n) { $have += ('{0}|{1}' -f $c.InnerText, $n.InnerText) }
        }
    }

    if ($null -ne $entry -and (($have -join "`n") -eq ($want -join "`n"))) {
        Say ("  ok       {0}" -f $w.Pack) 'DarkGray'
        $same++
        continue
    }

    Say ("  APPLY    {0}" -f $w.Pack) 'Green'
    Say ("           {0}" -f $w.Why) 'Gray'
    foreach ($pre in @($w.Presets)) {
        Say ("             {0}: {1}" -f $pre.category, $pre.preset) 'Gray'
    }
    $changed++

    if ($WhatIf) { continue }

    if ($null -eq $entry) {
        $entry = $xml.CreateElement('Entry')
        [void]$entry.SetAttribute('filename', $w.Key)
        [void]$gp.AppendChild($entry)
    }
    else {
        # Only our own presets are replaced. The entry itself, and anything
        # else in the file, is left alone.
        foreach ($old in @($entry.SelectNodes('Preset'))) { [void]$entry.RemoveChild($old) }
    }

    foreach ($pre in @($w.Presets)) {
        $pn = $xml.CreateElement('Preset')
        $c  = $xml.CreateElement('category'); $c.InnerText = [string]$pre.category
        $n  = $xml.CreateElement('preset');   $n.InnerText = [string]$pre.preset
        [void]$pn.AppendChild($c); [void]$pn.AppendChild($n)
        [void]$entry.AppendChild($pn)
    }
}

Say ""

if ($changed -eq 0) {
    Say "  Everything is already set. Nothing written." 'Green'
    Say ""
    exit $(if ($problems -gt 0) { 1 } else { 0 })
}

if ($WhatIf) {
    Say ("  {0} would change. Nothing was written." -f $changed) 'Yellow'
    Say ""
    exit 0
}

# --- back up, then write ---------------------------------------------------
try {
    $stamp = Get-Date -Format 'yyyy-MM-dd_HHmmss'
    $bdir  = Join-Path $ArchiveDir ("cemu-graphicpacks_" + $stamp)
    New-Item -ItemType Directory -Path $bdir -Force | Out-Null
    Copy-Item -LiteralPath $SettingsPath -Destination (Join-Path $bdir 'settings.xml') -Force
    Say ("  A copy of the old settings.xml is in archive\cemu-graphicpacks_{0}\." -f $stamp) 'DarkGray'
}
catch {
    Say ("  Could not back settings.xml up: {0}" -f $_.Exception.Message) 'Red'
    Say  "  Refusing to write without a backup." 'Red'
    Say ""
    exit 1
}

try {
    # UTF-8 WITH a byte-order mark, because that is what Cemu writes and what
    # its own reader expects. XmlWriterSettings is used rather than Save(path)
    # so the encoding and the indentation are both ours to decide.
    $ws = New-Object System.Xml.XmlWriterSettings
    $ws.Indent = $true
    $ws.IndentChars = '  '
    $ws.Encoding = New-Object System.Text.UTF8Encoding($true)
    $writer = [System.Xml.XmlWriter]::Create($SettingsPath, $ws)
    try { $xml.Save($writer) } finally { $writer.Close() }
}
catch {
    Say ("  Could not write settings.xml: {0}" -f $_.Exception.Message) 'Red'
    Say  "  The backup above is untouched. Copy it back if anything looks wrong." 'Gray'
    Say ""
    exit 1
}

Say ""
Say ("  {0} applied, {1} already set, {2} skipped, {3} problems." -f $changed, $same, $skipped, $problems) 'White'
Say ""
Say "  Launch the game from RetroBat as normal. Cemu picks these up at" 'Gray'
Say "  launch, so there is nothing else to press." 'Gray'
Say ""
Say "  To change what gets applied, edit the list at the top of" 'Gray'
Say "  _ClaudeWorkspace\scripts\Apply-GraphicPacks.ps1. It says how." 'Gray'
Say ""

exit $(if ($problems -gt 0) { 1 } else { 0 })
