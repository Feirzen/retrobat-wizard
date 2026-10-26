<#
    Show-Features.ps1 - what this drive is set to do, and what it is not.

    READ-ONLY. It changes nothing, so it is safe to run at any time, even
    with RetroBat open.

    This is the Features tab without the window. The window is a convenience
    layer and must never be the only way to see something, so every tab has a
    button that does the same job from a console. This is that button.

    Run it from:  Maintenance Steps\Show My Features.bat
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
# This script lives in <RetroBat>\_Wizard\Program\scripts\, so RetroBat is
# always two folders up. No drive letter, no guessing, works on any machine.
$Root = Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent

if (-not (Test-Path (Join-Path $Root 'retrobat.ini'))) {
    Write-Host "ERROR: could not find retrobat.ini above this script." -ForegroundColor Red
    Write-Host "       Expected RetroBat at: $Root" -ForegroundColor Red
    exit 1
}

$featuresLib = Join-Path $PSScriptRoot 'Features.ps1'
if (-not (Test-Path -LiteralPath $featuresLib)) {
    Write-Host "ERROR: Features.ps1 is missing from the scripts folder." -ForegroundColor Red
    Write-Host "       Without it every feature simply stays on, which is the" -ForegroundColor Gray
    Write-Host "       safe answer, but nothing here can be listed." -ForegroundColor Gray
    exit 1
}

. $featuresLib

$cat  = Get-FeatureCatalogue
$feat = Get-Features $Root
$path = Get-FeaturesPath $Root

Say ""
Say "  What this setup does for you" 'White'
Say "  ---------------------------------------------------------------------" 'DarkGray'
Say ""

if (-not (Test-Path -LiteralPath $path)) {
    Say "  There is no features.ini yet, so everything below is on." 'Yellow'
    Say "  One is written the next time Apply My Settings runs." 'DarkGray'
    Say ""
}

$onCount = 0

foreach ($key in $cat.Keys) {
    $on = [bool]$feat[$key]
    if ($on) { $onCount++ }

    $mark   = if ($on) { '[ON ]' } else { '[off]' }
    $colour = if ($on) { 'Green' } else { 'DarkGray' }

    Say ("  {0}  {1}" -f $mark, $cat[$key].title) $colour
    if ($on) {
        Say ("         {0}" -f $cat[$key].desc) 'Gray'
    } else {
        Say ("         {0}" -f $cat[$key].off) 'Gray'
    }
    Say ""
}

Say "  ---------------------------------------------------------------------" 'DarkGray'
Say ("  {0} of {1} switched on." -f $onCount, $cat.Count) 'White'
Say ""
Say "  To change one:" 'White'
Say "    the Features tab in the Setup Wizard, or edit this file by hand:" 'Gray'
Say ("    {0}" -f $path) 'Cyan'
Say ""
Say "  A change only becomes real when the script that owns it runs. The" 'Gray'
Say "  Features tab does that for you. By hand, the one button that always" 'Gray'
Say "  covers it is RUN THIS AFTER AN UPDATE.bat, which runs all six steps." 'Gray'
Say ""

exit 0
