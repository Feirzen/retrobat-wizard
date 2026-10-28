<#
    Show-Help.ps1 - the Help tab without the window.

    READ-ONLY. It changes nothing, so it is safe to run at any time, even
    with RetroBat open.

    The window is a convenience layer and must never be the only way to see
    something, so every tab has a button that does the same job from a
    console. This is that button for Help. It and the wizard's Help tab both
    read scripts\HelpText.ps1, so they cannot drift apart.

    Run it from:  Buttons\Show Help.bat
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
$Ws   = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent

if (-not (Test-Path (Join-Path $Root 'retrobat.ini'))) {
    Write-Host "ERROR: could not find retrobat.ini above this script." -ForegroundColor Red
    Write-Host "       Expected RetroBat at: $Root" -ForegroundColor Red
    exit 1
}

$helpLib = Join-Path $PSScriptRoot 'HelpText.ps1'
if (-not (Test-Path -LiteralPath $helpLib)) {
    Write-Host "ERROR: HelpText.ps1 is missing from the scripts folder." -ForegroundColor Red
    Write-Host "       Nothing else depends on it, so the drive still works." -ForegroundColor Gray
    Write-Host "       The full explanation is in docs\CUSTOMIZATION-RECORD.md." -ForegroundColor Gray
    exit 1
}

. $helpLib

# --- the drive's own name and version, from the one place they live --------
# Settings\wizard.ini is the single source. A missing file is not an error
# here; the page just carries no version stamp.
$name    = 'the Setup Wizard'
$version = ''
$iniPath = Join-Path $Ws 'Settings\wizard.ini'
if (Test-Path -LiteralPath $iniPath) {
    foreach ($line in @([System.IO.File]::ReadAllLines($iniPath))) {
        $t = $line.Trim()
        if ($t -eq '' -or $t.StartsWith(';') -or $t.StartsWith('#')) { continue }
        $eq = $t.IndexOf('=')
        if ($eq -lt 1) { continue }
        $k = $t.Substring(0, $eq).Trim().ToLower()
        $v = $t.Substring($eq + 1).Trim()
        if ($k -eq 'name')    { $name    = $v }
        if ($k -eq 'version') { $version = $v }
    }
}

$sections = @(Get-HelpSections -WizardName $name -Version $version)

Say ''
Say "  $name  -  Help" 'White'
Say '  ---------------------------------------------------------------------' 'DarkGray'

foreach ($s in $sections) {
    Say ''
    $heading = [string]$s.heading
    if ($heading -ne '') { Say ("  {0}" -f $heading) 'White' }
    foreach ($line in @($s.lines)) {
        Say ("    {0}" -f [string]$line) 'Gray'
    }
}

Say ''
Say '  ---------------------------------------------------------------------' 'DarkGray'
Say '  The same page is the Help tab in the Setup Wizard window.' 'DarkGray'
Say ''

exit 0
