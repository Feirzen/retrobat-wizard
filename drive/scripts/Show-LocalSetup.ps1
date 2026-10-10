<#
    Show-LocalSetup.ps1 - put this drive's buttons on THIS computer.

    This is the "Set up this computer" button without the window. The window
    is a convenience layer and must never be the only way to do something, so
    every tab has a button that does the same job from a console. This is
    that button.

    WHAT IT IS FOR. The two icons at the top of the drive are lovely while
    the drive is plugged in. Copy one to the Start Menu, unplug the drive,
    and it goes blank, because a shortcut stores its icon as a path and that
    path just went away. This puts a copy of the icons on the computer and
    points the shortcuts at those, so they keep their face whether the drive
    is connected or not.

    It also adds a Controllers button, which opens Windows' own game
    controller list. That one has nothing to do with the drive and works
    with it unplugged.

    Everything it writes is on the COMPUTER, never on the drive, and it is
    all undoable from the Remove option below.

    Run it from:  Maintenance Steps\Set Up This Computer.bat
#>

[CmdletBinding()]
param(
    # Empty and resolved in the body, never in the param block: under -File
    # $PSScriptRoot is not populated yet while defaults are worked out, and a
    # script that builds a path there dies before it can say why.
    [string] $RetroBatRoot = '',
    [string] $Choice       = ''
)

$ErrorActionPreference = 'Stop'

function Say([string]$msg, [string]$colour = 'Gray') { Write-Host $msg -ForegroundColor $colour }

# --- locate RetroBat -------------------------------------------------------
if ([string]::IsNullOrWhiteSpace($RetroBatRoot)) {
    $RetroBatRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
}

if (-not (Test-Path (Join-Path $RetroBatRoot 'retrobat.ini'))) {
    Say "ERROR: could not find retrobat.ini above this script." 'Red'
    Say "       Expected RetroBat at: $RetroBatRoot" 'Red'
    exit 1
}

$scriptsDir = $PSScriptRoot
$wizardDir  = Join-Path (Split-Path $scriptsDir -Parent) 'wizard'

# --- the drive's name ------------------------------------------------------
# One place only, the "name =" line in wizard\wizard.ini, so a future owner
# renames everything by editing one line.
$driveName = 'RetroBat'
$iniPath = Join-Path $wizardDir 'wizard.ini'
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

# --- the engine ------------------------------------------------------------
$lib = Join-Path $scriptsDir 'LocalSetup.ps1'
if (-not (Test-Path -LiteralPath $lib)) {
    Say "ERROR: LocalSetup.ps1 is missing from the scripts folder." 'Red'
    Say "       Nothing is broken. The drive works exactly as before, this" 'Gray'
    Say "       button simply cannot do anything without it." 'Gray'
    exit 1
}
. $lib

# Shortcuts.ps1 is optional here. It is only used to find the wizard's .bat
# by what it does rather than by its name, for the fallback path when the
# .vbs is missing. Without it the fallback simply skips the wizard shortcut.
$scLib = Join-Path $scriptsDir 'Shortcuts.ps1'
if (Test-Path -LiteralPath $scLib) { . $scLib }

$logger = { param($m) }

# --- where things stand ----------------------------------------------------
$installed = Test-LocalSetupInstalled
$iconDir   = Get-LocalSetupFolder
$startDir  = Get-StartMenuFolder -DriveName $driveName

Say ""
Say "  Set up this computer" 'White'
Say "  ---------------------------------------------------------------------" 'DarkGray'
Say ""
Say ("  Drive        {0}" -f $driveName) 'Gray'
Say ("  Plugged in as {0}" -f $RetroBatRoot) 'Gray'
Say ""

if ($installed) {
    Say "  This computer is already set up." 'Green'
    Say ""
    $rec = @(Get-LocalSetupRecord)
    if ($rec.Count -eq 0) {
        Say "  ...but nothing is recorded, which means the shortcuts were" 'Yellow'
        Say "  removed by hand. Choose 1 or 2 below to put them back." 'Gray'
    }
    else {
        foreach ($p in $rec) {
            $mark = '     '
            if (-not (Test-Path -LiteralPath $p)) { $mark = '  (gone)' }
            Say ("  {0} {1}" -f $mark, $p) 'Gray'
        }
    }
}
else {
    Say "  This computer has not been set up yet." 'Yellow'
    Say ""
    Say "  Nothing is wrong. The drive works perfectly without this. All it" 'Gray'
    Say "  adds is buttons on this computer's Start Menu that keep their" 'Gray'
    Say "  icons when the drive is unplugged." 'Gray'
}

Say ""
Say "  ---------------------------------------------------------------------" 'DarkGray'
Say ""
Say "  What would you like to do?" 'White'
Say ""
Say "    1   Add the buttons to the Start Menu" 'Gray'
Say "    2   Add them to the Start Menu AND the desktop" 'Gray'
Say "    3   Refresh what is already there (after the drive changed letter)" 'Gray'
Say "    4   Remove everything this put on this computer" 'Gray'
Say "    Q   Do nothing and quit" 'Gray'
Say ""

if ([string]::IsNullOrWhiteSpace($Choice)) {
    $Choice = Read-Host "  Type a number and press Enter"
}
$Choice = ([string]$Choice).Trim().ToUpper()

Say ""

switch ($Choice) {
    '1' { $places = @('start') }
    '2' { $places = @('start', 'desktop') }
    '3' {
        if (-not $installed) {
            Say "  There is nothing on this computer to refresh yet." 'Yellow'
            Say "  Choose 1 or 2 first." 'Gray'
            Say ""
            exit 0
        }
        $places = $null
    }
    '4' {
        $r = Remove-LocalSetup -Logger $logger
        Say ("  Removed {0} shortcuts, and the icon folder with them." -f @($r.Removed).Count) 'Green'
        if ($r.Problem -ne '') { Say ("  Note: {0}" -f $r.Problem) 'Yellow' }
        Say ""
        Say "  The drive itself is untouched and works exactly as before." 'Gray'
        Say ""
        exit 0
    }
    default {
        Say "  Nothing done." 'Gray'
        Say ""
        exit 0
    }
}

if ($null -eq $places) {
    $res = Update-LocalSetup -Root $RetroBatRoot -WizardName $driveName -Logger $logger
}
else {
    $res = Install-LocalSetup -Root $RetroBatRoot -WizardName $driveName -Places $places -Logger $logger
}

if ($res.Problem -ne '') {
    Say ("  It did not work: {0}" -f $res.Problem) 'Red'
    Say "  Nothing was changed on the drive. Nothing is broken." 'Gray'
    Say ""
    exit 1
}

$made = 0
foreach ($k in @($res.Results.Keys)) {
    $v = [string]$res.Results[$k]
    if ($v -eq 'written' -or $v -eq 'unchanged') { $made++ }
    else { Say ("  {0}" -f $v) 'Yellow' }
}

Say ("  {0} buttons are on this computer now." -f $made) 'Green'
Say ""
Say ("  Icons kept in   {0}" -f $iconDir) 'Gray'
if ($res.StartMenu -ne '') { Say ("  Start Menu      {0}" -f $res.StartMenu) 'Gray' }
Say ""
Say "  To pin one to the Start screen or the taskbar: open Start, find the" 'White'
Say ("  {0} folder, right-click a button and choose Pin." -f $driveName) 'White'
Say ""
Say "  Windows removed the ability for a script to pin things itself, and" 'DarkGray'
Say "  every trick that still does it breaks on the next Windows update, so" 'DarkGray'
Say "  this deliberately leaves that one click to you." 'DarkGray'
Say ""
Say "  The buttons keep their icons when the drive is unplugged. Clicking" 'Gray'
Say "  one without the drive plugged in will simply say it cannot find it," 'Gray'
Say "  which is correct. The Controllers button works either way." 'Gray'
Say ""

exit 0
