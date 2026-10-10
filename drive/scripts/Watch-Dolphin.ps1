<#
    Watch-Dolphin.ps1
    -------------------------------------------------------------------------
    Sweeps Dolphin savestates into quarantine every few minutes, but ONLY
    while Dolphin is actually running.

    When Dolphin isn't running it does nothing but check once a minute whether
    it has started - that check is a single process lookup and costs nothing.
    When RetroBat closes, this exits.

    That's the whole thing. No backups here, no other emulators, no
    every-few-seconds polling.

    Started by scripts\start\zz-backup-watcher.bat. Runs hidden.
#>

param(
    [int]    $SweepMinutes = 3,
    [string] $ScriptDir    = ''
)

# $PSScriptRoot is empty while parameter defaults are worked out in a script
# started with -File, so $ScriptDir is filled in here instead. See the same
# note in Backup-RetroBatSaves.ps1 for the full story.
if (-not $ScriptDir) { $ScriptDir = $PSScriptRoot }
if (-not $ScriptDir) { $ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path }
if (-not $ScriptDir) { return }


$quarantine = Join-Path $ScriptDir 'Quarantine-Savestates.ps1'
if (-not (Test-Path -LiteralPath $quarantine)) { return }

function Running { param([string] $Name) [bool](Get-Process -Name $Name -ErrorAction SilentlyContinue) }

Start-Sleep -Seconds 20   # let RetroBat finish starting

while (Running 'emulationstation') {

    if (Running 'Dolphin') {
        try { & $quarantine -Quiet } catch { }
        Start-Sleep -Seconds ($SweepMinutes * 60)
    }
    else {
        Start-Sleep -Seconds 60
    }
}
