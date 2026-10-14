<#
    Rename-WizardButton.ps1 - make the button at the drive root match the name
    in wizard\wizard.ini.

    Run it from:  Maintenance Steps\Rename The Wizard Button.bat

    WHY IT EXISTS. The drive's name lives in ONE place, the "name =" line in
    wizard\wizard.ini. Everything follows it by itself: the window title, the
    Play tab, the Help page, status.json, and the icon at the top of the drive,
    which renames itself on every run. The one thing that does not follow is
    the .bat file at the drive root, because a file cannot rename itself while
    Windows is running it.

    So this does it. One button, and the drive is consistent again.

    NOTHING IS DELETED, EVER. The old .bat is MOVED into
    _ClaudeWorkspace\_SAFE TO DELETE\, which is this drive's rule for
    everything: scripts\Shortcuts.ps1 retires stale .lnk files the same way,
    and the archive folders work the same way. If this rename turns out to be
    a mistake, the old file is sitting right there.

    IT DOES BOTH COPIES. The root .bat is a protected file, so there is a
    master of it in _ClaudeWorkspace\update-restore\ as well. Renaming only
    the live one would mean the next repair put the old name straight back
    alongside the new one, forever.

    IT IS SAFE TO RUN WHEN THERE IS NOTHING TO DO. If the name already
    matches, it says so and changes nothing.

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

# --- locate RetroBat -------------------------------------------------------
if ([string]::IsNullOrWhiteSpace($RetroBatRoot)) {
    $RetroBatRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
}
if (-not (Test-Path (Join-Path $RetroBatRoot 'retrobat.ini'))) {
    Say "ERROR: could not find retrobat.ini above this script." 'Red'
    Say "       Expected RetroBat at: $RetroBatRoot" 'Red'
    exit 1
}

$Ws        = Join-Path $RetroBatRoot '_ClaudeWorkspace'
$WizardDir = Join-Path $Ws 'wizard'
$MasterDir = Join-Path $Ws 'update-restore'
$BinDir    = Join-Path $Ws '_SAFE TO DELETE'

Say ""
Say "  The button at the top of the drive" 'White'
Say "  ---------------------------------------------------------------------" 'DarkGray'
Say ""

# --- the drive's name, from the one place it lives -------------------------
$driveName = ''
$iniPath = Join-Path $WizardDir 'wizard.ini'
if (Test-Path -LiteralPath $iniPath) {
    foreach ($line in @([System.IO.File]::ReadAllLines($iniPath))) {
        $t = $line.Trim()
        if ($t -eq '' -or $t.StartsWith(';') -or $t.StartsWith('#')) { continue }
        $i = $t.IndexOf('=')
        if ($i -lt 1) { continue }
        if ($t.Substring(0, $i).Trim().ToLower() -eq 'name') {
            $v = $t.Substring($i + 1).Trim()
            if ($v -ne '') { $driveName = $v }
        }
    }
}
if ($driveName -eq '') {
    Say "  wizard\wizard.ini has no name line, so there is nothing to match." 'Yellow'
    Say ""
    exit 0
}

# Windows will not accept these in a file name. Same rules as
# ConvertTo-ShortcutName in Shortcuts.ps1, with .bat on the end instead.
$safe = $driveName
foreach ($c in @('\', '/', ':', '*', '?', '"', '<', '>', '|')) { $safe = $safe.Replace($c, '') }
$safe = $safe.Trim().Trim('.')
if ($safe -eq '') { $safe = 'Setup Wizard' }
$wantName = $safe + '.bat'

Say ("  The drive is called   {0}" -f $driveName) 'Gray'
Say ("  So its button wants to be   {0}" -f $wantName) 'Gray'
Say ""

# --- find the one that opens the wizard, by what it DOES --------------------
# Never by its name. The whole point of this script is that the name is wrong.
function Find-WizardBat([string]$Folder) {
    if (-not (Test-Path -LiteralPath $Folder)) { return '' }
    foreach ($b in @(Get-ChildItem -LiteralPath $Folder -Filter '*.bat' -File -ErrorAction SilentlyContinue)) {
        if ($b.Name -eq 'PLAY.bat') { continue }
        $txt = ''
        try { $txt = [System.IO.File]::ReadAllText($b.FullName) } catch { continue }
        # SETUP RETROBAT.bat matches the rule below - it mentions
        # SetupWizard.ps1 and passes -Setup, not -Play - and it sorts first
        # alphabetically, so without this line the rename button would rename
        # the SETUP button. See the same skip in scripts\Shortcuts.ps1.
        if ($txt -like '*ROOT-SETUP-BUTTON*') { continue }
        # PLAY.bat is the one that passes -Play. The other opens the window.
        if ($txt -like '*SetupWizard.ps1*' -and $txt -notlike '*-Play*') { return $b.FullName }
    }
    return ''
}

# --- nothing may be holding either file ------------------------------------
foreach ($p in @('emulationstation', 'retrobat')) {
    if (@(Get-Process -Name $p -ErrorAction SilentlyContinue).Count -gt 0) {
        Say ("  {0} is running. Close it first." -f $p) 'Yellow'
        Say ""
        exit 1
    }
}

# --- move something into the bin, never delete it --------------------------
function Move-ToBin([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return 'gone already' }
    if ([System.IO.Path]::GetExtension($Path).ToLower() -ne '.bat') { return 'not a .bat, left alone' }
    try {
        if (-not (Test-Path -LiteralPath $BinDir)) {
            New-Item -ItemType Directory -Path $BinDir -Force -ErrorAction Stop | Out-Null
        }
        $name = Split-Path $Path -Leaf
        $dest = Join-Path $BinDir $name
        if (Test-Path -LiteralPath $dest) {
            $stamp = Get-Date -Format 'yyyy-MM-dd_HHmmss'
            $dest  = Join-Path $BinDir ("{0}_{1}.bat" -f [System.IO.Path]::GetFileNameWithoutExtension($name), $stamp)
        }
        Move-Item -LiteralPath $Path -Destination $dest -Force -ErrorAction Stop
        return 'moved'
    }
    catch { return ("could not move it: " + $_.Exception.Message) }
}

$done = 0; $already = 0; $problems = 0

foreach ($place in @(
        @{ Label = 'at the drive root';   Folder = $RetroBatRoot },
        @{ Label = 'in update-restore\'; Folder = $MasterDir }
    )) {

    $found = Find-WizardBat $place.Folder
    if ($found -eq '') {
        Say ("  none found {0}" -f $place.Label) 'Yellow'
        Say  "             nothing there opens the wizard window" 'DarkGray'
        $problems++
        continue
    }

    $have = Split-Path $found -Leaf
    if ($have -eq $wantName) {
        Say ("  ok         {0}   {1}" -f $have, $place.Label) 'DarkGray'
        $already++
        continue
    }

    $target = Join-Path $place.Folder $wantName
    if (Test-Path -LiteralPath $target) {
        Say ("  ALREADY    {0} exists {1}, and so does {2}" -f $wantName, $place.Label, $have) 'Yellow'
        Say  "             move one of them aside by hand, then run this again" 'DarkGray'
        $problems++
        continue
    }

    Say ("  RENAME     {0}" -f $place.Label) 'Green'
    Say ("             {0}" -f $have) 'Gray'
    Say ("             {0}" -f $wantName) 'Gray'
    if ($WhatIf) { $done++; continue }

    # Copy FIRST, move the old one second. If the copy fails there is still a
    # working button; if it is done the other way round and the copy fails,
    # there is none at all.
    try { Copy-Item -LiteralPath $found -Destination $target -ErrorAction Stop }
    catch {
        Say ("             could not write the new name: {0}" -f $_.Exception.Message) 'Red'
        Say  "             nothing was moved, the old button still works" 'Gray'
        $problems++
        continue
    }

    $r = Move-ToBin $found
    if ($r -ne 'moved') {
        Say ("             the new one is there, but the old one {0}" -f $r) 'Yellow'
        Say  "             both exist now. Drag the old one into _SAFE TO DELETE" 'DarkGray'
        $problems++
        continue
    }
    Say  "             old one moved into _SAFE TO DELETE, not deleted" 'DarkGray'
    $done++
}

Say ""

if ($WhatIf) {
    Say ("  {0} would be renamed. Nothing was changed." -f $done) 'Yellow'
    Say ""
    exit 0
}

if ($done -eq 0 -and $problems -eq 0) {
    Say "  Already correct. Nothing to do." 'Green'
}
else {
    Say ("  {0} renamed, {1} already right, {2} problems." -f $done, $already, $problems) 'White'
}

# --- the icons at the top of the drive (added 2026-10-14) ------------------
# They used to wait for the SETUP button, which nobody presses twice, so a
# rename left "Old Name.lnk" sitting there. Now this button does them too.
# Update-RootShortcuts writes the icon under the new name and retires the old
# one into _SAFE TO DELETE, the same way this .bat was. Safe when nothing
# changed: identical icons are left alone.
if (-not $WhatIf) {
    $lib = Join-Path $PSScriptRoot 'Shortcuts.ps1'
    if (Test-Path -LiteralPath $lib) {
        try {
            . $lib
            $r = Update-RootShortcuts -Root $RetroBatRoot -WizardName $driveName
            Say ""
            foreach ($k in @($r.Results.Keys | Sort-Object)) {
                Say ("  icon       {0}   {1}" -f $k, $r.Results[$k]) 'DarkGray'
            }
            if ($r.Problem -ne '') { Say ("  icons: " + $r.Problem) 'Yellow' }
        }
        catch { Say ("  the icons could not be redone: " + $_.Exception.Message) 'Yellow' }
    }
}

Say ""
Say "  Nothing here deletes anything. Everything it replaced is in" 'DarkGray'
Say "  _ClaudeWorkspace\_SAFE TO DELETE, which you can empty whenever." 'DarkGray'
Say ""

exit $(if ($problems -gt 0) { 1 } else { 0 })
