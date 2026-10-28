<#
    Fix-Portability.ps1
    ---------------------------------------------------------------------------
    Removes hardcoded drive letters from the RetroBat setup so the external
    drive behaves identically no matter what letter Windows assigns it
    (R: on the Ztower, D: on the Zbook, anything on someone else's PC).

    It does two jobs:

      1. Makes sure the Wii system's launch command in es_systems.cfg points at
         the NAND wrapper script using RetroBat's own %HOME% variable instead
         of a literal drive letter. This is also the repair step to re-run
         after a RetroBat update, because updates regenerate es_systems.cfg
         and wipe the custom command out.

      2. Rewrites any "<letter>:\RetroBat\..." path inside Dolphin's own
         config files to a relative one. Dolphin resolves relative paths
         against its exe folder, so this keeps the Wii NAND, save files and
         BIOS reachable on any machine. Dolphin re-saves this file every time
         it closes, so it is worth re-checking.

      3. Scans the whole setup for any other paths that still start with a
         literal drive letter, hiding in config and script files, and reports
         them so they can be dealt with.

    Safe to run as many times as you like. Changes nothing that is already
    correct. Backs up any file before touching it.

    Run it from:  Buttons\Fix Drive Letters.bat
#>

[CmdletBinding()]
param(
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'

function Say([string]$msg, [string]$colour = 'Gray') {
    if (-not $Quiet) { Write-Host $msg -ForegroundColor $colour }
}

# --- locate RetroBat -------------------------------------------------------
# This script lives in <RetroBat>\_Wizard\Program\scripts\
$Root = Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent

if (-not (Test-Path (Join-Path $Root 'retrobat.ini'))) {
    Write-Host "ERROR: could not find retrobat.ini above this script." -ForegroundColor Red
    Write-Host "       Expected RetroBat at: $Root" -ForegroundColor Red
    Write-Host "       This script must stay in <RetroBat>\_Wizard\Program\scripts\." -ForegroundColor Red
    exit 1
}

Say ""
Say "RetroBat found at: $Root" 'Cyan'
Say ""

# --- is the Wii System Menu boot switched on? ------------------------------
#  features.ini decides. EVERYTHING FAILS ON: a missing Features.ps1, a
#  missing or unreadable features.ini, or a value that is not on or off, all
#  mean ON, which is what this drive did before the switches existed.
#
#  This is not a skip. Job 1 writes a <command> line either way - ours when
#  the switch is on, RetroBat's own when it is off - because the line is
#  already sitting in es_systems.cfg and a switch that merely stopped
#  rewriting it would appear to do nothing at all.
$featWiiSystemMenu = $true
$featuresLib = Join-Path $PSScriptRoot 'Features.ps1'
if (Test-Path -LiteralPath $featuresLib) {
    . $featuresLib
    $featWiiSystemMenu = Test-Feature $Root 'wiisystemmenu'
}

$stamp     = Get-Date -Format 'yyyy-MM-dd_HHmmss'
$backupDir = Join-Path $Root "_Wizard\Backups\Archive\portability-fix_$stamp"

function Backup-Once([string]$path) {
    if (-not (Test-Path $backupDir)) { New-Item -ItemType Directory -Path $backupDir -Force | Out-Null }
    $dest = Join-Path $backupDir (Split-Path $path -Leaf)
    $n = 1
    while (Test-Path $dest) { $dest = Join-Path $backupDir ("{0}.{1}" -f (Split-Path $path -Leaf), $n); $n++ }
    Copy-Item $path $dest -Force
    Say "    backed up to: $dest" 'DarkGray'
}

# Read/write text while preserving whether the file had a UTF-8 BOM.
function Read-TextFile([string]$path) {
    $bytes = [System.IO.File]::ReadAllBytes($path)
    $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    $text = [System.IO.File]::ReadAllText($path)
    return @{ Text = $text; HasBom = $hasBom }
}
function Write-TextFile([string]$path, [string]$text, [bool]$hasBom) {
    $enc = New-Object System.Text.UTF8Encoding($hasBom)
    [System.IO.File]::WriteAllText($path, $text, $enc)
}

# ===========================================================================
#  JOB 1 - Wii launch command in es_systems.cfg
# ===========================================================================

Say "[1/3] Checking the Wii launch command in es_systems.cfg" 'White'

$esSystems = Join-Path $Root 'emulationstation\.emulationstation\es_systems.cfg'
$vbs       = Join-Path $Root 'system\scripts\wii-nand-launch.vbs'

if (-not (Test-Path $esSystems)) {
    Say "    es_systems.cfg not found. Skipping." 'Yellow'
}
elseif ($featWiiSystemMenu -and -not (Test-Path $vbs)) {
    Say "    wii-nand-launch.vbs is missing from system\scripts\." 'Yellow'
    Say "    Not touching es_systems.cfg - putting the command back without the" 'Yellow'
    Say "    script would break Wii launching entirely." 'Yellow'
}
else {
    # RetroBat expands %HOME% to <RetroBat>\emulationstation at launch time,
    # so both of these are drive-letter independent by design.
    #
    # The OFF line is RetroBat's own, read straight off this drive on
    # 2026-08-31: it is character for character what the gamecube and wiiu
    # blocks use, which is how we know it is the stock command and not a
    # guess. The wrapper script is left on disk either way, so switching
    # back on is one line and no file copying.
    if ($featWiiSystemMenu) {
        $wanted = 'wscript.exe //nologo "%HOME%\..\system\scripts\wii-nand-launch.vbs" -gameinfo %GAMEINFOXML% %CONTROLLERSCONFIG% -system %SYSTEM% -emulator %EMULATOR% -core %CORE% -rom %ROM%'
        $wantWhat = 'through the Wii System Menu'
    }
    else {
        $wanted = '"%HOME%\emulatorLauncher.exe" -gameinfo %GAMEINFOXML% %CONTROLLERSCONFIG% -system %SYSTEM% -emulator %EMULATOR% -core %CORE% -rom %ROM%'
        $wantWhat = "straight into the game ('wiisystemmenu' is switched off)"
    }

    $f    = Read-TextFile $esSystems
    $text = $f.Text

    # Isolate the <system> block whose <name> is exactly "wii".
    $blockPattern = '(?s)(<system>(?:(?!</system>).)*?<name>wii</name>.*?</system>)'
    $m = [regex]::Match($text, $blockPattern)

    if (-not $m.Success) {
        Say "    Could not locate the Wii system block. Skipping." 'Yellow'
    }
    else {
        $block    = $m.Groups[1].Value
        $cmdMatch = [regex]::Match($block, '(?s)<command>(.*?)</command>')

        if (-not $cmdMatch.Success) {
            Say "    Wii block has no <command> line. Skipping." 'Yellow'
        }
        elseif ($cmdMatch.Groups[1].Value -eq $wanted) {
            Say ("    Already correct - no drive letter, boots {0}." -f $wantWhat) 'Green'
        }
        else {
            $old = $cmdMatch.Groups[1].Value
            Say "    Current: $old" 'DarkGray'
            Say "    Fixing." 'Yellow'
            Backup-Once $esSystems

            $newBlock = $block.Remove($cmdMatch.Groups[1].Index, $cmdMatch.Groups[1].Length).Insert($cmdMatch.Groups[1].Index, $wanted)
            $text     = $text.Remove($m.Groups[1].Index, $m.Groups[1].Length).Insert($m.Groups[1].Index, $newBlock)

            Write-TextFile $esSystems $text $f.HasBom
            Say ("    Done. Wii now boots {0}, with no drive letter." -f $wantWhat) 'Green'
        }
    }
}

# ---------------------------------------------------------------------------
#  JOB 1b - Wii U launch command (added 2026-10-13)
#  Points Wii U at system\scripts\wiiu-launch.vbs, which asks "Wii Remotes
#  or Pro Controller?" before each game (scripts\ControllerChooser.ps1).
#  Switched by 'wiiuchooser' in features.ini - only a clear "off" turns it
#  off. Off, or the script missing, puts RetroBat's own command back.
#  Runs on its own after a RetroBat update (the wizard's update check).
# ---------------------------------------------------------------------------
Say "[1b] Checking the Wii U launch command in es_systems.cfg" 'White'
try {
    $wiiuVbs = Join-Path $Root 'system\scripts\wiiu-launch.vbs'
    $wiiuOn = $true
    $featIni = Join-Path $Root '_Wizard\Settings\features.ini'
    if (Test-Path -LiteralPath $featIni) {
        foreach ($fl in [System.IO.File]::ReadAllLines($featIni)) {
            if ($fl -match '^\s*wiiuchooser\s*=\s*off\b') { $wiiuOn = $false }
        }
    }
    if ($wiiuOn -and (Test-Path -LiteralPath $wiiuVbs)) {
        $wiiuWanted = 'wscript.exe //nologo "%HOME%\..\system\scripts\wiiu-launch.vbs" -gameinfo %GAMEINFOXML% %CONTROLLERSCONFIG% -system %SYSTEM% -emulator %EMULATOR% -core %CORE% -rom %ROM%'
    }
    else {
        $wiiuWanted = '"%HOME%\emulatorLauncher.exe" -gameinfo %GAMEINFOXML% %CONTROLLERSCONFIG% -system %SYSTEM% -emulator %EMULATOR% -core %CORE% -rom %ROM%'
    }
    if (Test-Path -LiteralPath $esSystems) {
        $f    = Read-TextFile $esSystems
        $text = $f.Text
        $m = [regex]::Match($text, '(?s)(<system>(?:(?!</system>).)*?<name>wiiu</name>.*?</system>)')
        if (-not $m.Success) { Say "    Could not locate the Wii U system block. Skipping." 'Yellow' }
        else {
            $block    = $m.Groups[1].Value
            $cmdMatch = [regex]::Match($block, '(?s)<command>(.*?)</command>')
            if (-not $cmdMatch.Success) { Say "    Wii U block has no <command> line. Skipping." 'Yellow' }
            elseif ($cmdMatch.Groups[1].Value -eq $wiiuWanted) { Say "    Already correct." 'Green' }
            else {
                Backup-Once $esSystems
                $newBlock = $block.Remove($cmdMatch.Groups[1].Index, $cmdMatch.Groups[1].Length).Insert($cmdMatch.Groups[1].Index, $wiiuWanted)
                $text     = $text.Remove($m.Groups[1].Index, $m.Groups[1].Length).Insert($m.Groups[1].Index, $newBlock)
                Write-TextFile $esSystems $text $f.HasBom
                if ($wiiuOn) { Say "    Done. Wii U games now ask Wii Remotes or Pro Controller." 'Green' }
                else { Say "    Done. Wii U is back to RetroBat's own launch." 'Green' }
            }
        }
    }
}
catch { Say ("    Wii U check failed, nothing changed: " + $_.Exception.Message) 'Yellow' }

# ---------------------------------------------------------------------------
#  JOB 1c - "How to play" before keyboard-and-mouse games (2026-10-17)
#  Flash, ScummVM and PC games go through system\scripts\game-launch.vbs,
#  which shows a short "how this game plays" screen first (the same screen
#  as Wii U, scripts\ControllerChooser.ps1): made for mouse and keyboard,
#  how the controller works in it, PLAY or Back. Switched by 'howtoplay' in
#  features.ini - only a clear "off" turns it off. Off, or the script
#  missing, puts RetroBat's own command back. Only the start of the line
#  changes (emulatorLauncher.exe <-> the wrapper), so whatever RetroBat puts
#  after it is kept as it is.
# ---------------------------------------------------------------------------
Say "[1c] Checking the launch commands for keyboard-and-mouse games" 'White'
try {
    $glVbs = Join-Path $Root 'system\scripts\game-launch.vbs'
    $glOn = $true
    $featIni = Join-Path $Root '_Wizard\Settings\features.ini'
    if (Test-Path -LiteralPath $featIni) {
        foreach ($fl in [System.IO.File]::ReadAllLines($featIni)) { if ($fl -match '^\s*howtoplay\s*=\s*off\b') { $glOn = $false } }
    }
    if (-not (Test-Path -LiteralPath $glVbs)) { $glOn = $false }
    $stockStart = '"%HOME%\emulatorLauncher.exe"'
    $wrapStart  = 'wscript.exe //nologo "%HOME%\..\system\scripts\game-launch.vbs"'
    if (Test-Path -LiteralPath $esSystems) {
        $f    = Read-TextFile $esSystems
        $text = $f.Text
        $changed = @()
        foreach ($sysName in @('flash', 'scummvm', 'windows')) {
            $m = [regex]::Match($text, ('(?s)(<system>(?:(?!</system>).)*?<name>{0}</name>.*?</system>)' -f $sysName))
            if (-not $m.Success) { continue }
            $block = $m.Groups[1].Value
            $cm = [regex]::Match($block, '(?s)<command>(.*?)</command>')
            if (-not $cm.Success) { continue }
            $cmd = $cm.Groups[1].Value.Trim()
            $new = $cmd
            if ($glOn -and $cmd.StartsWith($stockStart)) { $new = $wrapStart + $cmd.Substring($stockStart.Length) }
            elseif (-not $glOn -and $cmd.StartsWith($wrapStart)) { $new = $stockStart + $cmd.Substring($wrapStart.Length) }
            if ($new -eq $cmd) { continue }
            $newBlock = $block.Remove($cm.Groups[1].Index, $cm.Groups[1].Length).Insert($cm.Groups[1].Index, $new)
            $text = $text.Remove($m.Groups[1].Index, $m.Groups[1].Length).Insert($m.Groups[1].Index, $newBlock)
            $changed += $sysName
        }
        if ($changed.Count -gt 0) {
            Backup-Once $esSystems
            Write-TextFile $esSystems $text $f.HasBom
            if ($glOn) { Say ("    Done. These now show how to play first: " + ($changed -join ', ')) 'Green' }
            else { Say ("    Done. Back to RetroBat's own launch: " + ($changed -join ', ')) 'Green' }
        }
        else { Say "    Already correct." 'Green' }
    }
}
catch { Say ("    How-to-play check failed, nothing changed: " + $_.Exception.Message) 'Yellow' }

Say ""

# ===========================================================================
#  JOB 2 - Dolphin's own config files
# ===========================================================================

Say "[2/3] Checking Dolphin's config for hardcoded drive letters" 'White'

# Dolphin resolves relative paths against its exe folder
# (<RetroBat>\emulators\dolphin-emu), so ".\..\..\saves\..." lands in
# <RetroBat>\saves\... on any machine. Dolphin preserves relative paths when
# it re-saves, which it does every time it closes.
$dolphinConfig = Join-Path $Root 'emulators\dolphin-emu\User\Config'

if (-not (Test-Path $dolphinConfig)) {
    Say "    Dolphin config folder not found. Skipping." 'Yellow'
}
else {
    $totalFixed = 0

    foreach ($ini in (Get-ChildItem -Path $dolphinConfig -Filter '*.ini' -File)) {
        $f    = Read-TextFile $ini.FullName
        $new  = [regex]::Replace($f.Text, '[A-Za-z]:\\RetroBat\\', '.\..\..\')

        if ($new -ne $f.Text) {
            $count = ([regex]::Matches($f.Text, '[A-Za-z]:\\RetroBat\\')).Count
            Say ("    {0}: {1} path(s) to fix" -f $ini.Name, $count) 'Yellow'
            Backup-Once $ini.FullName
            Write-TextFile $ini.FullName $new $f.HasBom
            $totalFixed += $count
        }
    }

    if ($totalFixed -eq 0) {
        Say "    Already relative - nothing to do." 'Green'
    } else {
        Say "    Fixed $totalFixed path(s). The Wii NAND is reachable again." 'Green'
    }
}

Say ""

# ===========================================================================
#  JOB 3 - hunt for leftover drive letters
# ===========================================================================

Say "[3/3] Scanning for other hardcoded drive letters" 'White'

$scanPaths = @(
    (Join-Path $Root 'emulationstation\.emulationstation\es_systems.cfg'),
    (Join-Path $Root 'emulationstation\.emulationstation\scripts'),
    (Join-Path $Root 'system\scripts'),
    (Join-Path $Root '_Wizard\Program\scripts'),
    (Join-Path $Root 'emulators\dolphin-emu\User\Config')
) | Where-Object { Test-Path $_ }

$exts = @('.bat', '.cmd', '.ps1', '.vbs', '.cfg', '.ini', '.txt')
$hits = @()

foreach ($p in $scanPaths) {
    $files = if (Test-Path $p -PathType Container) {
        Get-ChildItem -Path $p -Recurse -File | Where-Object { $exts -contains $_.Extension.ToLower() }
    } else {
        Get-Item $p
    }

    foreach ($file in $files) {
        # @() matters: a ONE-LINE file otherwise comes back as a bare string,
        # and indexing a string walks its CHARACTERS instead of its lines.
        # Check-DriveHealth.ps1 already had this guard; this one did not.
        # Fixed 2026-08-29.
        $lines = @(Get-Content -LiteralPath $file.FullName -ErrorAction SilentlyContinue)
        for ($i = 0; $i -lt $lines.Count; $i++) {
            # A COMMENT IS NOT A BUG. Several scripts on this drive explain
            # the drive letter trap in their own comments, and to do that
            # one of them has to be able to write out a drive letter. The
            # scan flagged those, so this light sat permanently yellow on
            # 2026-08-29 with nothing actually wrong. Comment markers
            # covered: # (PowerShell, ini), ; (ini), REM and :: (batch),
            # ' (VBScript). A commented-out line does not run, so it
            # cannot be a portability bug either way.
            $t = $lines[$i].TrimStart()
            if ($t -match '^(#|;|::|'')' -or $t -match '^(?i)REM\s') { continue }
            if ($lines[$i] -match '[A-Za-z]:[\\/]RetroBat') {
                $hits += [pscustomobject]@{
                    File = $file.FullName.Replace($Root, '<RetroBat>')
                    Line = $i + 1
                    Text = $lines[$i].Trim()
                }
            }
        }
    }
}

if ($hits.Count -eq 0) {
    Say "    Clean. No hardcoded drive letters found." 'Green'
} else {
    Say "    Found $($hits.Count) line(s) still containing a drive letter:" 'Yellow'
    Say ""
    foreach ($h in $hits) {
        Say ("    {0}  (line {1})" -f $h.File, $h.Line) 'Yellow'
        Say ("        {0}" -f $h.Text) 'DarkGray'
    }
    Say ""
    Say "    These were NOT changed automatically - some drive letters are" 'Gray'
    Say "    legitimate (a path to something outside RetroBat, for example)." 'Gray'
    Say "    Show this list to Claude and it can sort out which are which." 'Gray'
}

Say ""
Say "Finished." 'Cyan'
Say ""
