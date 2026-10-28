<#
    Maximize-GameWindow.ps1
    ---------------------------------------------------------------------------
    Makes the window of certain PC games fill the screen when they open.

    WHY. The Jackbox Megapicker always opens as a small window and has no
    setting of its own to change that (checked 2026-09-25). Windows can
    maximize any ordinary window from outside, so this does it for it.

    HOW IT IS STARTED. RetroBat runs every .bat in
        emulationstation\.emulationstation\scripts\game-start\
    as a game starts. zz-maximize-windows.bat there starts this, hidden, and
    returns at once so the game is not held up. This then watches for up to
    90 seconds for a window belonging to any program named in
        _Wizard\Settings\maximize-windows.txt
    maximizes it once, and exits. It never touches a window that is already
    maximized or full screen, and it never touches anything not on the list.

    TO ADD ANOTHER GAME: put the name of its program (the .exe, with or
    without ".exe") on its own line in maximize-windows.txt.

    RULES: no drive letters, Windows PowerShell 5.1, pure ASCII.
#>

Set-StrictMode -Off
$ErrorActionPreference = 'SilentlyContinue'

$Root = Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
$List = Join-Path $Root '_Wizard\Settings\maximize-windows.txt'
$Log  = Join-Path $Root '_Wizard\Backups\Saves\hook.log'

function Write-Log([string]$m) {
    try { [System.IO.File]::AppendAllText($Log, ('[' + (Get-Date -Format 'ddd MM/dd/yyyy HH:mm:ss') + '] window fix: ' + $m + "`r`n")) } catch { }
}

if (-not (Test-Path -LiteralPath $List)) { exit 0 }
$names = @()
foreach ($line in [System.IO.File]::ReadAllLines($List)) {
    $t = $line.Trim()
    if ($t -eq '' -or $t.StartsWith('#')) { continue }
    if ($t.ToLower().EndsWith('.exe')) { $t = $t.Substring(0, $t.Length - 4) }
    $names += $t
}
if ($names.Count -eq 0) { exit 0 }

try {
    Add-Type -Namespace RBWin -Name Maximize -ErrorAction Stop -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);
[DllImport("user32.dll")] public static extern bool IsZoomed(IntPtr hWnd);
[DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
[DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
'@
}
catch { exit 0 }

$done = @{}
$deadline = (Get-Date).AddSeconds(90)
while ((Get-Date) -lt $deadline) {
    foreach ($n in $names) {
        foreach ($p in @(Get-Process -Name $n -ErrorAction SilentlyContinue)) {
            $h = $p.MainWindowHandle
            if ($h -eq [IntPtr]::Zero -or $done.ContainsKey([string]$h)) { continue }
            if (-not [RBWin.Maximize]::IsWindowVisible($h)) { continue }
            # Give the program a moment to finish drawing its first frame;
            # maximizing a window that is still being built can be undone by
            # the program itself a split second later.
            Start-Sleep -Milliseconds 800
            if (-not [RBWin.Maximize]::IsZoomed($h)) {
                [void][RBWin.Maximize]::ShowWindowAsync($h, 3)   # 3 = maximize
                [void][RBWin.Maximize]::SetForegroundWindow($h)
                Write-Log ('maximized ' + $n)
            }
            $done[[string]$h] = $true
        }
    }
    if ($done.Count -gt 0) { exit 0 }
    Start-Sleep -Milliseconds 700
}
exit 0
