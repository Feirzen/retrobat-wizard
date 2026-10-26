<#
    Watch-Dolphin.ps1
    -------------------------------------------------------------------------
    The save-state watcher while RetroBat is open. (Still called
    Watch-Dolphin because the start hook and its master copy in
    update-restore start it by this name; since 2026-10-11 it covers every
    emulator, not just Dolphin.)

    While a game is running it does two things:

      1. SWEEPS every few minutes (SaveStates.ps1, -MidGame): any save state
         an emulator made moves into the archive, so a button pressed by
         accident cannot load it. A held "jump in" copy is left alone.

      2. THE AUTO-SAVE TIMER (Steven, 2026-10-11): 45 minutes into a game, and
         every 30 minutes after that, it presses the emulator's own
         save-state key - only for RetroArch and Dolphin, only when their own
         config says that key is F2, and only when that emulator's window is
         the one in front. Anything else and it does nothing. The state it
         makes is swept like any other and shows on the Saves tab, where
         "Jump in here" can start the game from it. Switch: 'autosavetimer'
         in features.ini (the Features tab).

    3. WHICH GAME (2026-10-12): every game it sees start is written to
         SaveBackups\last-game.txt. A "Jump in here" waits for that one game,
         and the game-end sweep reads this to know if it was the one. While
         a jump in is waiting it checks every 5 seconds, so even a quick look
         at a game counts.

    When no game is running it checks twice a minute, which costs nothing.
    When RetroBat closes, this exits. Log: SaveBackups\watcher.log.

    Started by scripts\start\zz-backup-watcher.bat. Runs hidden.
#>

param(
    [int]    $SweepMinutes = 3,
    [string] $ScriptDir    = ''
)

if (-not $ScriptDir) { $ScriptDir = $PSScriptRoot }
if (-not $ScriptDir) { $ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path }
if (-not $ScriptDir) { return }

$engine = Join-Path $ScriptDir 'SaveStates.ps1'
if (-not (Test-Path -LiteralPath $engine)) { return }
. $engine
$WorkspaceDir = Split-Path (Split-Path $ScriptDir -Parent) -Parent
$Root = Split-Path $WorkspaceDir -Parent
$featLib = Join-Path $ScriptDir 'Features.ps1'
if (Test-Path -LiteralPath $featLib) { . $featLib }

$logPath = Join-Path $WorkspaceDir 'Backups\Saves\watcher.log'
function Write-WatchLog([string]$Text) {
    try {
        if ((Test-Path -LiteralPath $logPath) -and (Get-Item -LiteralPath $logPath).Length -gt 262144) {
            [System.IO.File]::WriteAllText($logPath, '')
        }
        [System.IO.File]::AppendAllText($logPath, ('[{0}] {1}{2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Text, "`r`n"))
    } catch { }
}

function Running { param([string] $Name) [bool](Get-Process -Name $Name -ErrorAction SilentlyContinue) }

# The window in front, and a key press for it.
try {
    Add-Type -ErrorAction Stop -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class RBWatchKeys {
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
    public static uint FrontPid() { uint pid; GetWindowThreadProcessId(GetForegroundWindow(), out pid); return pid; }
    public static void Tap(byte vk, byte scan) {
        keybd_event(vk, scan, 0, UIntPtr.Zero);
        System.Threading.Thread.Sleep(80);
        keybd_event(vk, scan, 2, UIntPtr.Zero);
    }
}
'@
} catch { }

function Get-FrontProcessName {
    try {
        $pid0 = [RBWatchKeys]::FrontPid()
        if ($pid0 -eq 0) { return '' }
        return [string](Get-Process -Id $pid0 -ErrorAction Stop).ProcessName
    } catch { return '' }
}

Start-Sleep -Seconds 20   # let RetroBat finish starting
Write-WatchLog 'watcher started'

$gameKey   = ''
$gameStart = $null
$saved     = 0
$lastSweep = [datetime]::MinValue

while (Running 'emulationstation') {
    $g = Get-SsRunningGame
    $running = $g.Running
    if (-not $g.Known) { $running = (Running 'Dolphin') -or (Running 'retroarch') }

    if ($running) {
        $id = $(if ($g.Path) { $g.Path } else { 'unknown game' })
        if ($id -ne $gameKey) {
            $gameKey = $id; $gameStart = Get-Date; $saved = 0
            if ($g.Path) { Set-SsLastGame $Root $g.Path }
            Write-WatchLog ('game started: ' + $id)
        }

        if (((Get-Date) - $lastSweep).TotalMinutes -ge $SweepMinutes) {
            try {
                $r = Invoke-SavestateSweep -Root $Root -MidGame
                if ($r.Moved -gt 0) { Write-WatchLog ('swept {0} file(s) mid-game' -f $r.Moved) }
            } catch { Write-WatchLog ('sweep failed: ' + $_.Exception.Message) }
            $lastSweep = Get-Date
        }

        $timerOn = $true
        if (Get-Command Test-Feature -ErrorAction SilentlyContinue) { try { $timerOn = Test-Feature $Root 'autosavetimer' } catch { $timerOn = $true } }
        if ($timerOn -and $null -ne $gameStart) {
            $mins = ((Get-Date) - $gameStart).TotalMinutes
            if (Test-SsTimerDue $mins $saved) {
                $front = Get-FrontProcessName
                $target = Get-SsTimerTarget $Root $front
                if ($target) {
                    try {
                        [RBWatchKeys]::Tap(0x71, 0x3C)   # F2
                        # next one 30 minutes on from the last due time, so a
                        # long spell out of focus never fires a burst
                        $saved = [int][math]::Floor(($mins - 45) / 30) + 1
                        Write-WatchLog ('auto-save {0} ({1}) at {2:N0} min' -f $saved, $target, $mins)
                    } catch { Write-WatchLog ('auto-save key failed: ' + $_.Exception.Message) }
                }
                # not in front, or not an emulator the timer knows: try again
                # next pass, and the timer keeps its place
            }
        }
    }
    elseif ($gameKey -ne '') {
        Write-WatchLog ('game ended: ' + $gameKey)
        $gameKey = ''; $gameStart = $null; $saved = 0
    }

    # A jump in waiting: look often, so a short game is not missed.
    $wait = 30
    try { if (@(Get-SsHolds $Root).Count -gt 0) { $wait = 5 } } catch { }
    Start-Sleep -Seconds $wait
}
Write-WatchLog 'RetroBat closed, watcher stopped'
