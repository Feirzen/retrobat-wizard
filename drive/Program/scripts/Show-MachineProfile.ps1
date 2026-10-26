<#
    Show-MachineProfile.ps1
    ---------------------------------------------------------------------------
    READ-ONLY. Shows what the machine profile system knows about this
    computer and exactly which settings Apply My Settings would give it -
    without changing a single file. Safe to run any time, even with RetroBat
    open.

    Run it from:  Maintenance Steps\Show My Machine.bat
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# ($PSScriptRoot is resolved here in the body, never in param() - it is
#  empty inside param() when a script is started with -File, and that
#  failure mode is completely silent. See the customization record.)
$Root = Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent

if (-not (Test-Path (Join-Path $Root 'retrobat.ini'))) {
    Write-Host "ERROR: could not find retrobat.ini above this script." -ForegroundColor Red
    exit 1
}

. (Join-Path $PSScriptRoot 'ProfileEngine.ps1')

$mp = Resolve-MachineProfile -Root $Root -NoWrite

Write-Host ""
Write-Host "  This computer" -ForegroundColor White
Write-Host "  -------------"
Write-Host ("  Name          : {0}" -f $mp.Machine)
Write-Host ("  Graphics card : {0}" -f $mp.Gpu)
Write-Host ("  Brand rules   : {0}" -f $mp.Vendor)
Write-Host ("  Tier          : {0}  ({1})" -f $mp.Tier.ToUpper(), $mp.TierSource)
if ($mp.Created) {
    Write-Host "  Machine       : none yet - Apply My Settings will create one" -ForegroundColor Yellow
}
else {
    Write-Host ("  Machine       : {0}" -f $mp.ProfileFile)
}

if ($mp.ConsoleTiers -and $mp.ConsoleTiers.Count -gt 0) {
    Write-Host "  Console tiers : (this machine runs these at a different tier)"
    foreach ($c in ($mp.ConsoleTiers.Keys | Sort-Object)) {
        Write-Host ("                  {0,-9} {1}" -f $c, ([string]$mp.ConsoleTiers[$c]).ToUpper())
    }
}

foreach ($m in $mp.Messages) { Write-Host "  $m" -ForegroundColor Yellow }

if (-not $mp.Ok) {
    Write-Host ""
    Write-Host "  The machine settings could not produce a result - see above." -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "  What Apply My Settings would write for this machine" -ForegroundColor White
Write-Host "  ---------------------------------------------------"
Write-Host "  (source: tier = from the $($mp.Tier) tier file, console = from a"
Write-Host "   different tier chosen for that console, brand = from"
Write-Host "   vendor-rules.ini, PINNED = this machine's own override)"
Write-Host ""

$labels = @{ 'tier' = 'tier'; 'console-tier' = 'console'; 'vendor' = 'brand'; 'override' = 'PINNED' }
foreach ($key in $mp.Settings.Keys) {
    $src = $labels[$mp.Origin[$key]]
    Write-Host ("   {0,-38} = {1,-12} ({2})" -f $key, $mp.Settings[$key], $src)
}

Write-Host ""
Write-Host "  Nothing was changed. To apply: Maintenance Steps\Apply My Settings.bat" -ForegroundColor DarkGray
Write-Host ""
