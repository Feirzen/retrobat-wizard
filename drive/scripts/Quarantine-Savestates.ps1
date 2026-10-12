<#
    Quarantine-Savestates.ps1
    -------------------------------------------------------------------------
    Moves EVERY emulator's save states out of reach so they can't be loaded
    by accident (Dolphin only until 2026-10-11; every emulator since). The
    rules live in SaveStates.ps1; this is the button and the game-end hook's
    way in.

    Swept files go to:
        _ClaudeWorkspace\archive\quarantined-savestates\<date>\
    with origins.txt in that folder saying where each one came from, which is
    what lets the Saves tab's "Jump in here" put one back in the right place.

    Run by the game-end hook (scripts\game-end\zz-backup-saves.bat) with no
    switch: that run also clears a "jump in" hold and puts the RetroArch
    placeholders back. Watch-Dolphin.ps1 runs it with -MidGame while a game
    is on, which leaves a held "jump in" copy alone.

    Nothing is deleted, with one exception: a held "jump in" copy that is
    still byte-for-byte its archived original (the original never left).
#>

param(
    [string] $RetroBatRoot   = '',
    [string] $QuarantineRoot = '',   # kept for old callers; the folder is fixed
    [switch] $Quiet,
    [switch] $MidGame
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
# ---------------------------------------------------------------------------
$ScriptDir = $PSScriptRoot
if (-not $ScriptDir) { $ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path }
if (-not $ScriptDir) { throw 'Could not work out which folder this script is in.' }
$WorkspaceDir = Split-Path $ScriptDir -Parent      # <RetroBat>\_ClaudeWorkspace
$RetroBatDir  = Split-Path $WorkspaceDir -Parent   # <RetroBat>
if (-not $RetroBatRoot) { $RetroBatRoot = $RetroBatDir }

$engine = Join-Path $ScriptDir 'SaveStates.ps1'
if (-not (Test-Path -LiteralPath $engine)) { if (-not $Quiet) { Write-Host '  SaveStates.ps1 is missing - nothing swept.' }; exit 0 }
. $engine

$r = Invoke-SavestateSweep -Root $RetroBatRoot -MidGame:$MidGame
if (-not $Quiet) {
    Write-Host ''
    Write-Host ("  {0} save state file(s) moved aside." -f $r.Moved)
    if ($r.Dropped -gt 0)  { Write-Host ("  {0} unchanged 'jump in' copy(ies) removed (the originals are in the archive)." -f $r.Dropped) }
    if ($r.Restored -gt 0) { Write-Host ("  {0} RetroArch placeholder(s) put back." -f $r.Restored) }
    foreach ($m in @($r.Messages)) { Write-Host ('  ' + $m) }
}
else {
    Write-Output ("sweep: moved {0}, dropped {1}, placeholders back {2}, retired {4}{3}" -f $r.Moved, $r.Dropped, $r.Restored, $(if (@($r.Messages).Count) { '; ' + (@($r.Messages) -join '; ') } else { '' }), [int]$r.Retired)
}
exit 0
