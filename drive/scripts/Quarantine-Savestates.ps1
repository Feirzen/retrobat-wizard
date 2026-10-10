<#
    Quarantine-Savestates.ps1
    -------------------------------------------------------------------------
    Moves Dolphin savestates out of reach so they can't be loaded by accident.
    That's all it does.

    Checks three folders:
        emulators\dolphin-emu\User\StateSaves    <- where Dolphin actually writes
        saves\gamecube\dolphin                   <- RetroBat's copy
        saves\wii\dolphin

    Anything savestate-shaped gets MOVED to:
        _ClaudeWorkspace\archive\quarantined-savestates\<date>\

    Nothing is deleted. If you ever want one back, it's sitting right there.

    If the emulator still has a file open the move fails silently and the next
    pass picks it up. No errors, no crashes.
#>

param(
    [string] $RetroBatRoot   = '',
    [string] $QuarantineRoot = '',
    [switch] $Quiet
)

# ---------------------------------------------------------------------------
#  WHERE AM I?  (do not move this into the param block above)
# ---------------------------------------------------------------------------
#  $PSScriptRoot is EMPTY while PowerShell is working out parameter default
#  values in a script started with -File, which is how the EmulationStation
#  hooks start this one. Any path built up there silently comes out wrong, and
#  the script dies on its first Split-Path before it can even write to its own
#  log. That is exactly what happened here for a week in August 2026: saves
#  quietly stopped being backed up and nothing said a word.
#
#  In the body, below the param block, $PSScriptRoot is filled in properly. So
#  the paths get built here, and the parameters above just default to empty.
# ---------------------------------------------------------------------------
$ScriptDir = $PSScriptRoot
if (-not $ScriptDir) { $ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path }
if (-not $ScriptDir) { throw 'Could not work out which folder this script is in.' }
$WorkspaceDir = Split-Path $ScriptDir -Parent      # <RetroBat>\_ClaudeWorkspace
$RetroBatDir  = Split-Path $WorkspaceDir -Parent   # <RetroBat>

if (-not $RetroBatRoot)   { $RetroBatRoot   = $RetroBatDir }
if (-not $QuarantineRoot) { $QuarantineRoot = Join-Path $WorkspaceDir 'archive\quarantined-savestates' }


$dirs = @(
    "$RetroBatRoot\emulators\dolphin-emu\User\StateSaves"
    "$RetroBatRoot\saves\gamecube\dolphin"
    "$RetroBatRoot\saves\wii\dolphin"
)

# Dolphin savestates are .s01 through .s10, plus their thumbnail .png.
# .txt is deliberately left alone - RetroBat writes a .txt sidecar on exit
# and throws an unhandled exception if things vanish underneath it.
$pattern = '\.s\d{2}$|\.s\d{2}\.png$'

$moved = 0

foreach ($dir in $dirs) {
    if (-not (Test-Path -LiteralPath $dir -PathType Container)) { continue }

    foreach ($f in (Get-ChildItem -LiteralPath $dir -File -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -match $pattern })) {

        $destDir = Join-Path $QuarantineRoot (Get-Date -Format 'yyyy-MM-dd')
        if (-not (Test-Path -LiteralPath $destDir)) {
            try { New-Item -ItemType Directory -Path $destDir -Force -ErrorAction Stop | Out-Null } catch { continue }
        }

        $dest = Join-Path $destDir ('{0}__{1}' -f (Get-Date -Format 'HHmmss'), $f.Name)

        try {
            Move-Item -LiteralPath $f.FullName -Destination $dest -Force -ErrorAction Stop
            $moved++
            if (-not $Quiet) { Write-Host "  moved: $($f.Name)" }
        }
        catch { }   # still in use - next pass gets it
    }
}

if (-not $Quiet) {
    Write-Host ''
    Write-Host "  $moved savestate(s) moved."
}
