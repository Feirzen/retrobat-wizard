<#
    Restore-ProtectedFiles.ps1
    ---------------------------------------------------------------------------
    Puts back the custom files that live inside RetroBat's own folders.

    THE PROBLEM THIS SOLVES

    Most of this setup is kept safe by Apply-Settings, which writes settings
    into config files. But a few customizations are whole FILES sitting in
    folders that RetroBat owns and replaces wholesale on an update:

        emulationstation\resources\locale\en_GB\...\emulationstation2.po
            the reworded menus - LAUNCH GAME, RESUME BACKUP SAVE, and so on

        system\loadingscreens\*.mp4
            the videos that play while an emulator starts, including the
            wii.mp4 that was added by hand and is not part of RetroBat

        system\scripts\wii-nand-launch.vbs
            the wrapper that makes Wii games boot through the Wii System Menu

    An update quietly deletes or overwrites all of those and there is no
    setting anywhere that brings them back.

    HOW IT WORKS

    A master copy of each one lives in

        _Wizard\Program\restore\

    laid out in exactly the same folder shape as RetroBat itself. This script
    walks that folder and, for every file in it, makes sure the real one
    matches. Anything missing gets put back. Anything that has been changed
    gets restored, with the version it replaced saved into archive first.

    TO PROTECT ANOTHER FILE

    Copy it into _Wizard\Program\restore\ keeping the same folder path
    it has inside RetroBat. That is the whole procedure - nothing to edit in
    this script.

        example:  system\sounds\launch.wav
        becomes:  _Wizard\Program\restore\system\sounds\launch.wav

    IF YOU CHANGE ONE OF THESE FILES ON PURPOSE

    Change it, then run this with  -Adopt  once. That pulls the live versions
    back into the master folder so your change becomes the new known-good.
    Otherwise the next run would helpfully undo it.

        Update Master Copies.bat

    Run it from:  Restore Protected Files.bat
                  (and automatically from RUN THIS AFTER AN UPDATE.bat)
#>

[CmdletBinding()]
param(
    [switch]$Quiet,
    [switch]$Adopt,      # copy the LIVE files back into the master folder
    [switch]$WhatIf      # show what would happen, change nothing
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

$MasterDir  = Join-Path $Root '_Wizard\Program\restore'
$ArchiveDir = Join-Path $Root '_Wizard\Backups\Archive'
$StockDir   = Join-Path $Root '_Wizard\Program\restore-off'

# --- which protected files belong to a switch ------------------------------
#  Most protected files are simply "ours" and are always put back. A few are
#  a FEATURE, and features.ini can turn a feature off. When one is off:
#
#    - if Program\restore-off\<same path> holds RetroBat's own version of the
#      file, that is put back instead. That is a real undo: the menus really
#      do go back to saying START NEW GAME
#    - if there is no stock copy to put back, the live file is left exactly
#      as it is and the line says so, rather than pretending to have done
#      something
#
#  EVERYTHING FAILS ON. A missing Features.ps1 or features.ini means every
#  feature is on, which is what this script did before any of this existed.
# ---------------------------------------------------------------------------
#  The map itself lives in Features.ps1 (Get-FeatureFileMap), because it used
#  to be written out here AND again in Check-DriveHealth.ps1 and the two had
#  to be kept in step by hand. If Features.ps1 is missing this stays empty, so
#  no file is treated as switched off and every master is put back, which is
#  the fails-ON direction.
$FeatureFiles = [ordered]@{}

$OffPaths  = @{}
$SkipPaths = @{}
$featuresLib = Join-Path $PSScriptRoot 'Features.ps1'
if (Test-Path -LiteralPath $featuresLib) {
    . $featuresLib
    if (Get-Command Get-FeatureFileMap -ErrorAction SilentlyContinue) {
        $FeatureFiles = Get-FeatureFileMap
    }
    $feat = Get-Features $Root
    foreach ($key in $FeatureFiles.Keys) {
        if ($feat.Contains($key) -and -not $feat[$key]) {
            foreach ($rp in $FeatureFiles[$key]) { $OffPaths[$rp.ToLower()] = $key }
        }
    }

    # And the other sense: files that are deliberately NOT on the drive while
    # a feature is ON. Putting one of those back would fight the script that
    # moved it away. See Get-FeatureSkipMap for the whole story.
    if (Get-Command Get-FeatureSkipMap -ErrorAction SilentlyContinue) {
        $skipMap = Get-FeatureSkipMap
        foreach ($key in $skipMap.Keys) {
            if (-not $feat.Contains($key)) { continue }
            $entry = $skipMap[$key]
            if (-not (Test-FeatureSkipApplies $entry ([bool]$feat[$key]))) { continue }
            foreach ($rp in $entry['Paths']) { $SkipPaths[$rp.ToLower()] = $key }
        }
    }
}


if (-not (Test-Path $MasterDir)) {
    Write-Host "ERROR: no master folder at _Wizard\Program\restore\." -ForegroundColor Red
    Write-Host "       Nothing to restore from." -ForegroundColor Red
    exit 1
}

# --- refuse to run while RetroBat is open ----------------------------------
$running = Get-Process -Name 'emulationstation', 'RetroBat', 'BatGui' -ErrorAction SilentlyContinue
if ($running) {
    Write-Host ""
    Write-Host "  RetroBat is currently running." -ForegroundColor Red
    Write-Host "  Close it completely, then run this again." -ForegroundColor Yellow
    Write-Host ""
    exit 1
}

Say ""
Say "RetroBat found at: $Root" 'Cyan'
if ($WhatIf) { Say "DRY RUN - nothing will be written" 'Magenta' }
Say ""

function Get-HashSafe([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

$masters = @(Get-ChildItem -LiteralPath $MasterDir -File -Recurse -ErrorAction SilentlyContinue)

if ($masters.Count -eq 0) {
    Say "The master folder is empty - nothing to do." 'Yellow'
    Say ""
    exit 0
}

$stamp     = Get-Date -Format 'yyyy-MM-dd_HHmmss'
$backupDir = Join-Path $ArchiveDir "protected-files_$stamp"

$same = 0; $restored = 0; $adopted = 0; $problems = 0

# ===========================================================================
#  ADOPT - take the live files as the new masters
# ===========================================================================
if ($Adopt) {
    Say "Updating the master copies from the live files." 'White'
    Say ""

    foreach ($m in $masters) {
        $rel  = $m.FullName.Substring($MasterDir.Length).TrimStart('\')
        $live = Join-Path $Root $rel

        if ($SkipPaths.ContainsKey($rel.ToLower())) {
            Say ("  skipped  $rel") 'DarkGray'
            Say ("           '{0}' is on, so this file is meant to be out of" -f $SkipPaths[$rel.ToLower()]) 'DarkGray'
            Say  "           the way - master left alone" 'DarkGray'
            continue
        }

        # A switched-off feature means the live file is RetroBat's, not ours.
        # Adopting it would overwrite our master with the stock file and the
        # customization would be gone for good, so it is skipped.
        if ($OffPaths.ContainsKey($rel.ToLower())) {
            Say ("  skipped  $rel") 'DarkGray'
            Say ("           '{0}' is switched off - master left alone" -f $OffPaths[$rel.ToLower()]) 'DarkGray'
            continue
        }

        if (-not (Test-Path -LiteralPath $live)) {
            Say ("  MISSING  $rel") 'Yellow'
            Say  "           the real file is not there, master left alone" 'DarkGray'
            $problems++
            continue
        }

        if ((Get-HashSafe $live) -eq (Get-HashSafe $m.FullName)) {
            Say ("  same     $rel") 'DarkGray'
            $same++
            continue
        }

        if (-not $WhatIf) { Copy-Item -LiteralPath $live -Destination $m.FullName -Force }
        Say ("  UPDATED  $rel") 'Green'
        $adopted++
    }

    Say ""
    Say "---------------------------------------------------------------------------" 'DarkGray'
    Say ("  masters updated : {0}" -f $adopted) $(if ($adopted) { 'Green' } else { 'Gray' })
    Say ("  already the same: {0}" -f $same) 'Gray'
    Say ("  could not check : {0}" -f $problems) $(if ($problems) { 'Yellow' } else { 'Gray' })
    Say "---------------------------------------------------------------------------" 'DarkGray'
    Say ""
    exit 0
}

# ===========================================================================
#  RESTORE - put the masters back where they belong
# ===========================================================================
Say "Checking the files that a RetroBat update would wipe out." 'White'
Say ""

foreach ($m in $masters) {
    $rel  = $m.FullName.Substring($MasterDir.Length).TrimStart('\')
    $live = Join-Path $Root $rel

    if ($SkipPaths.ContainsKey($rel.ToLower())) {
        Say ("  skipped  $rel") 'DarkGray'
        Say ("           '{0}' is on, so this one is meant to be out of the way" -f $SkipPaths[$rel.ToLower()]) 'DarkGray'
        $same++
        continue
    }

    $liveHash = Get-HashSafe $live

    # Normally the source is our master. If this file belongs to a feature
    # that is switched off, the source becomes RetroBat's own copy instead.
    $src    = $m.FullName
    $offKey = $null
    if ($OffPaths.ContainsKey($rel.ToLower())) {
        $offKey = $OffPaths[$rel.ToLower()]
        $stock  = Join-Path $StockDir $rel

        if (Test-Path -LiteralPath $stock) {
            $src = $stock
        }
        else {
            Say ("  left     $rel") 'Yellow'
            Say ("           '{0}' is off, but there is no stock copy in" -f $offKey) 'DarkGray'
            Say  "           Program\restore-off\ to put back - not guessing" 'DarkGray'
            $same++
            continue
        }
    }

    if ($liveHash -eq (Get-HashSafe $src)) {
        Say ("  ok       $rel") 'DarkGray'
        $same++
        continue
    }

    try {
        # save whatever is there now, so nothing is ever lost outright
        if ($null -ne $liveHash -and -not $WhatIf) {
            $bakPath = Join-Path $backupDir $rel
            New-Item -ItemType Directory -Path (Split-Path $bakPath -Parent) -Force | Out-Null
            Copy-Item -LiteralPath $live -Destination $bakPath -Force
        }

        if (-not $WhatIf) {
            $destDir = Split-Path $live -Parent
            if (-not (Test-Path -LiteralPath $destDir)) {
                New-Item -ItemType Directory -Path $destDir -Force | Out-Null
            }
            Copy-Item -LiteralPath $src -Destination $live -Force
        }

        if ($offKey) {
            Say ("  REVERTED $rel") 'Green'
            Say ("           '{0}' is switched off - RetroBat's own file is back" -f $offKey) 'DarkGray'
        } elseif ($null -eq $liveHash) {
            Say ("  PUT BACK $rel") 'Green'
            Say  "           it was gone - an update had removed it" 'DarkGray'
        } else {
            Say ("  RESTORED $rel") 'Green'
            Say  "           it had been changed - the old one is in archive" 'DarkGray'
        }
        $restored++
    }
    catch {
        Say ("  FAILED   $rel") 'Red'
        Say ("           $($_.Exception.Message)") 'DarkGray'
        $problems++
    }
}

# --- a quick sanity note about the Wii System Menu -------------------------
# The wrapper above only routes Wii games through the System Menu if the
# System Menu is actually installed in the emulated NAND. If it is not, Wii
# games still launch, they just boot straight into the game.
$sysmenu = Join-Path $Root 'saves\wii\dolphin-emu\User\Wii\title\00000001\00000002\content\title.tmd'
Say ""
if (Test-Path -LiteralPath $sysmenu) {
    Say "  Wii System Menu is installed in the NAND." 'DarkGray'
} else {
    Say "  NOTE: no Wii System Menu in the NAND." 'Yellow'
    Say "        Wii games will still run, they just boot straight into the" 'Gray'
    Say "        game instead of going through the Wii Menu first." 'Gray'
}

Say ""
Say "---------------------------------------------------------------------------" 'DarkGray'
Say ("  already correct : {0}" -f $same) 'Gray'
Say ("  put back        : {0}" -f $restored) $(if ($restored) { 'Green' } else { 'Gray' })
Say ("  problems        : {0}" -f $problems) $(if ($problems) { 'Yellow' } else { 'Gray' })
Say "---------------------------------------------------------------------------" 'DarkGray'

if ($restored -gt 0 -and (Test-Path $backupDir)) {
    Say ""
    Say "What was replaced is kept in:" 'DarkGray'
    Say ("  _Wizard\Backups\Archive\protected-files_{0}\" -f $stamp) 'DarkGray'
}

Say ""
if ($problems -gt 0) { exit 2 } else { exit 0 }
