<#
    CouchMouse.ps1 - play mouse games from the couch with a controller.

    Started by the RetroBat game-start hook (scripts\game-start\
    zz-couch-mouse.bat) as every game starts. It works out which console the
    game is on (RetroBat's own localhost:1234/runningGame) and keeps going
    ONLY for the consoles listed in _ClaudeWorkspace\couch-mouse.txt (Flash
    to start with), or for one game whose file says so: every browser game
    (its .bat runs Launch-Browser), and any game file with the words
    "couch mouse = on" in it (a .bat or .url on the Windows shelf, say).
    Anything else: it exits at once and the game never knows it ran.

    WHILE THE GAME RUNS
        left stick       moves the mouse pointer (slow near the middle, fast
                         at the edge)
        A                left mouse button (held = held, so dragging works)
        B                right mouse button
        right stick      scroll wheel
        D-pad            arrow keys
        X                Space
        Y                Enter
        L3 (stick in)    switch the couch mouse off and on, for a game that
                         understands the controller by itself
        SELECT + START   still RetroBat's own "quit the game"

    It stops by itself when the game ends (RetroBat says nothing is running)
    or when RetroBat closes. One copy only. Written for Steven, 2026-10-11:
    "play the point and click games with a controller, still on the couch".

    Reads pads through RetroBat's own SDL2.dll, like the wizard does
    (PadInput.ps1). Log: _ClaudeWorkspace\wizard\couch-mouse.log.

    ASCII ONLY, Windows PowerShell 5.1. $PSScriptRoot is resolved in the body.
#>
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$Ws   = Split-Path $PSScriptRoot -Parent
$Root = Split-Path $Ws -Parent
$log  = Join-Path $Ws 'wizard\couch-mouse.log'

function Write-CmLog([string]$m) {
    try {
        if ((Test-Path -LiteralPath $log) -and (Get-Item -LiteralPath $log).Length -gt 256KB) {
            Move-Item -LiteralPath $log -Destination ($log + '.old') -Force
        }
        [System.IO.File]::AppendAllText($log, ((Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + '  ' + $m + "`r`n"))
    } catch { }
}

# Which consoles get the couch mouse. One name per line, as RetroBat names
# them (the folder in roms\). No file, or an empty one, means none.
function Get-CmSystems {
    $f = Join-Path $Ws 'couch-mouse.txt'
    if (-not (Test-Path -LiteralPath $f)) { return @() }
    return @([System.IO.File]::ReadAllLines($f) | ForEach-Object { ($_ -replace '[;#].*$', '').Trim().ToLower() } | Where-Object { $_ -match '^[a-z0-9_\-]{1,30}$' })
}

# The running game's file says it wants the couch mouse. Only small text
# files are looked at.
function Test-CmGameWants([string]$Path) {
    try {
        if ($Path -eq '' -or -not (Test-Path -LiteralPath $Path)) { return $false }

        # a game named in couch-mouse.txt by its file name (for a shortcut,
        # which cannot carry the words itself)
        $leaf = ([System.IO.Path]::GetFileName($Path)).ToLower()
        if (@(Get-CmFiles) -contains $leaf) { return $true }
        if ((Get-Item -LiteralPath $Path).Length -gt 16KB) { return $false }
        $t = [System.IO.File]::ReadAllText($Path)
        return ($t -match 'Launch-Browser' -or $t -match '(?i)couch\s*mouse\s*=\s*on')
    }
    catch { return $false }
}

$script:CmGamePath = ''
# Game FILE names in couch-mouse.txt (a line with a dot in it).
function Get-CmFiles {
    $f = Join-Path $Ws 'couch-mouse.txt'
    if (-not (Test-Path -LiteralPath $f)) { return @() }
    return @([System.IO.File]::ReadAllLines($f) | ForEach-Object { ($_ -replace '[;#].*$', '').Trim().ToLower() } | Where-Object { $_ -match '\.' -and $_ -notmatch '[\\/]' })
}

function Get-CmRunningSystem {
    try {
        $req = [System.Net.HttpWebRequest]::Create('http://127.0.0.1:1234/runningGame')
        $req.Method = 'GET'; $req.Proxy = $null; $req.Timeout = 1000; $req.ReadWriteTimeout = 1000
        $resp = $req.GetResponse()
        $sr = New-Object System.IO.StreamReader($resp.GetResponseStream())
        $body = $sr.ReadToEnd(); $sr.Close(); $resp.Close()
        if ($body.Trim() -eq '') { return '' }
        $g = $body | ConvertFrom-Json
        if ([string]$g.path -ne '') { $script:CmGamePath = [string]$g.path }
        $sys = [string]$g.systemName
        if ($sys -eq '') { $sys = [string]$g.system }
        if ($sys -eq '' -and [string]$g.path -match '[\\/]roms[\\/]([^\\/]+)[\\/]') { $sys = $Matches[1] }
        return $sys.ToLower()
    }
    catch { return '' }
}

$mutex = $null
try {
    $created = $false
    $mutex = New-Object System.Threading.Mutex($true, 'Local\RetroBatCouchMouse', [ref]$created)
    if (-not $created) { exit 0 }

    $want = @(Get-CmSystems)

    # The game is only just starting; RetroBat answers within a few seconds.
    $sys = ''
    for ($i = 0; $i -lt 30 -and $sys -eq ''; $i++) { Start-Sleep -Milliseconds 700; $sys = Get-CmRunningSystem }
    if ($sys -eq '') { exit 0 }
    if ($want -notcontains $sys -and -not (Test-CmGameWants $script:CmGamePath)) { exit 0 }

    . (Join-Path $PSScriptRoot 'PadInput.ps1')
    $dll = Join-Path $Root 'emulationstation\SDL2.dll'
    [RBPad]::Pump = $true
    if (-not [RBPad]::Init($dll)) { Write-CmLog ("could not read controllers: " + [RBPad]::LastError); exit 0 }

    if (-not ([System.Management.Automation.PSTypeName]'RBCouch').Type) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class RBCouch
{
    [StructLayout(LayoutKind.Sequential)] struct PT { public int X; public int Y; }
    [DllImport("user32.dll")] static extern bool GetCursorPos(out PT p);
    [DllImport("user32.dll")] static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] static extern void mouse_event(uint f, uint dx, uint dy, int data, UIntPtr extra);
    [DllImport("user32.dll")] static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
    static double fx, fy; static bool have = false;
    public static void Move(int lx, int ly, double scale)
    {
        PT p; if (!GetCursorPos(out p)) return;
        if (!have || Math.Abs(p.X - fx) > 2 || Math.Abs(p.Y - fy) > 2) { fx = p.X; fy = p.Y; have = true; }
        fx += Speed(lx) * scale; fy += Speed(ly) * scale;
        SetCursorPos((int)Math.Round(fx), (int)Math.Round(fy));
    }
    static double Speed(int v)
    {
        double a = Math.Abs(v) / 32767.0;
        if (a < 0.18) return 0;
        a = (a - 0.18) / 0.82;
        return Math.Sign(v) * (0.8 + a * a * 15.0);
    }
    // left: down 0x0002 up 0x0004   right: down 0x0008 up 0x0010
    public static void Button(bool right, bool down) { mouse_event(right ? (down ? 0x0008u : 0x0010u) : (down ? 0x0002u : 0x0004u), 0, 0, 0, UIntPtr.Zero); }
    public static void Wheel(bool down) { mouse_event(0x0800, 0, 0, down ? -40 : 40, UIntPtr.Zero); }
    // Arrow keys are "extended" keys (flag 1); key up adds flag 2.
    public static void Key(byte vk, bool down)
    {
        uint ext = (vk >= 0x25 && vk <= 0x28) ? 1u : 0u;
        keybd_event(vk, 0, ext | (down ? 0u : 2u), UIntPtr.Zero);
    }
}
'@
    }

    Write-CmLog ("on for " + $sys)
    $B = $script:PadBit
    # button bit -> what it holds down. Each is pressed when the button goes
    # down and released when it comes up, so holding works like a real mouse
    # and keyboard.
    $holds = @(
        @{ Bit = $B.A;     Kind = 'mouse'; Right = $false },
        @{ Bit = $B.B;     Kind = 'mouse'; Right = $true },
        @{ Bit = $B.Up;    Kind = 'key';   Vk = 0x26 },
        @{ Bit = $B.Down;  Kind = 'key';   Vk = 0x28 },
        @{ Bit = $B.Left;  Kind = 'key';   Vk = 0x25 },
        @{ Bit = $B.Right; Kind = 'key';   Vk = 0x27 },
        @{ Bit = $B.X;     Kind = 'key';   Vk = 0x20 },
        @{ Bit = $B.Y;     Kind = 'key';   Vk = 0x0D }
    )
    $prev = 0; $on = $true; $tick = 0; $wheelWait = 0
    $scale = 1.0
    try { Add-Type -AssemblyName System.Windows.Forms; $scale = [math]::Max(1.0, [System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Width / 1920.0) } catch { }
    while ($true) {
        Start-Sleep -Milliseconds 16
        $s = [RBPad]::Poll()
        $new = $s -band (-bnot $prev)
        $gone = $prev -band (-bnot $s)
        # SELECT + START is RetroBat's quit: never send anything for it.
        $quit = (($s -band $B.Back) -ne 0) -and (($s -band $B.Start) -ne 0)
        if (($new -band $B.L3) -ne 0) {
            $on = -not $on
            Write-CmLog ($(if ($on) { 'switched back on' } else { 'switched off with L3' }))
            if (-not $on) { foreach ($h in $holds) { if (($prev -band $h.Bit) -ne 0) { if ($h.Kind -eq 'mouse') { [RBCouch]::Button($h.Right, $false) } else { [RBCouch]::Key([byte]$h.Vk, $false) } } } }
        }
        if ($on -and -not $quit) {
            [RBCouch]::Move([RBPad]::LX, [RBPad]::LY, $scale)
            foreach ($h in $holds) {
                $d = (($new -band $h.Bit) -ne 0); $u = (($gone -band $h.Bit) -ne 0)
                if (-not $d -and -not $u) { continue }
                if ($h.Kind -eq 'mouse') { [RBCouch]::Button($h.Right, $d) } else { [RBCouch]::Key([byte]$h.Vk, $d) }
            }
            if ($wheelWait -gt 0) { $wheelWait-- }
            elseif ($s -band ($B.RStickUp -bor $B.RStickDown)) { [RBCouch]::Wheel((($s -band $B.RStickDown) -ne 0)); $wheelWait = 5 }
        }
        $prev = $s
        # Every two seconds: is the game still running?
        $tick++
        if ($tick % 125 -eq 0) {
            if ((Get-CmRunningSystem) -eq '') { break }
        }
    }
    # Let go of anything still held, so no button is left stuck down.
    foreach ($h in $holds) { if (($prev -band $h.Bit) -ne 0) { if ($h.Kind -eq 'mouse') { [RBCouch]::Button($h.Right, $false) } else { [RBCouch]::Key([byte]$h.Vk, $false) } } }
    Write-CmLog 'game over, off'
}
catch { Write-CmLog ("stopped: " + $_.Exception.Message) }
finally {
    try { [RBPad]::Quit() } catch { }
    try { if ($null -ne $mutex) { $mutex.ReleaseMutex(); $mutex.Dispose() } } catch { }
}
