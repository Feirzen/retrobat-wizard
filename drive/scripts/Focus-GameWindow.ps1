<#
    Focus-GameWindow.ps1 - bring a game's window to the front once it opens.
    ---------------------------------------------------------------------------
    WHY (2026-10-14). Windows only lets a program jump to the front if the
    program that started it was at the front. EmulationStation is at the
    front, and normally starts the emulator itself, so that works. The Wii U
    goes through a small helper first (system\scripts\wiiu-launch.vbs, for the
    "Wii Remotes or Pro Controller?" screen), and that helper is not at the
    front, so Cemu opened BEHIND RetroBat (Paper Mario, 2026-10-13).

    WHAT IT DOES. Started hidden by wiiu-launch.vbs just before the game. It
    waits up to -Seconds for a visible window from a program named in -Name,
    brings it to the front once, checks again a few seconds later in case the
    emulator was still opening, then exits. It never touches anything else.

    THE ALT TAP. Windows lets the program that received the last key press
    move a window to the front. A single Alt press and release, sent just
    before, is the standard way to qualify. Alt on its own does nothing in a
    game.

    RULES: no drive letters, Windows PowerShell 5.1, pure ASCII.
#>
param(
    [string] $Name    = 'cemu',
    [int]    $Seconds = 90,
    [string] $Log     = ''
)

Set-StrictMode -Off
$ErrorActionPreference = 'SilentlyContinue'

function Write-FgLog([string]$m) {
    if ($Log -eq '') { return }
    try { [System.IO.File]::AppendAllText($Log, ((Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + '  focus: ' + $m + "`r`n")) } catch { }
}

try {
    Add-Type -Namespace RBFocus -Name W -ErrorAction Stop -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
[DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
[DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
[DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
[DllImport("user32.dll")] public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);
[DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
[DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
'@
}
catch { exit 0 }

$names = @($Name -split ',' | ForEach-Object { $_.Trim() -replace '\.exe$', '' } | Where-Object { $_ -ne '' })

function Find-Window {
    foreach ($n in $names) {
        foreach ($p in @(Get-Process -Name $n -ErrorAction SilentlyContinue)) {
            $h = $p.MainWindowHandle
            if ($h -ne [IntPtr]::Zero -and [RBFocus.W]::IsWindowVisible($h)) { return @{ H = $h; Id = [uint32]$p.Id } }
        }
    }
    return $null
}

function Test-InFront($w) {
    $fg = [RBFocus.W]::GetForegroundWindow()
    $fgPid = [uint32]0
    [void][RBFocus.W]::GetWindowThreadProcessId($fg, [ref]$fgPid)
    return ($fgPid -eq $w.Id)
}

function Push-Front($w) {
    if ([RBFocus.W]::IsIconic($w.H)) { [void][RBFocus.W]::ShowWindowAsync($w.H, 9) }   # 9 = restore
    [RBFocus.W]::keybd_event(0x12, 0, 0, [UIntPtr]::Zero)   # Alt down
    [RBFocus.W]::keybd_event(0x12, 0, 2, [UIntPtr]::Zero)   # Alt up
    [void][RBFocus.W]::SetForegroundWindow($w.H)
}

$deadline = (Get-Date).AddSeconds($Seconds)
$w = $null
while ((Get-Date) -lt $deadline) {
    $w = Find-Window
    if ($null -ne $w) { break }
    Start-Sleep -Milliseconds 500
}
if ($null -eq $w) { Write-FgLog ("no {0} window within {1}s" -f $Name, $Seconds); exit 0 }

Start-Sleep -Milliseconds 700
$pushed = 0
for ($i = 0; $i -lt 3; $i++) {
    $w2 = Find-Window
    if ($null -ne $w2) { $w = $w2 }
    if (-not (Test-InFront $w)) { Push-Front $w; $pushed++ }
    Start-Sleep -Seconds 3
}
Write-FgLog ("{0}: {1}" -f $Name, $(if ($pushed -gt 0) { "brought to the front ($pushed)" } else { 'already in front' }))
exit 0
