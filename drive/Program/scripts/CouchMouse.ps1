<#
    CouchMouse.ps1 - play mouse games from the couch with a controller.

    Started by the RetroBat game-start hook (scripts\game-start\
    zz-couch-mouse.bat) as every game starts. It works out which console the
    game is on (RetroBat's own localhost:1234/runningGame) and keeps going
    ONLY for the consoles listed in _Wizard\Settings\couch-mouse.txt (Flash
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

    WII U GAMEPAD-SCREEN GAMES (2026-10-14). Windows cannot hide the
    controller from Cemu, so a mouse on the left stick and A also walked the
    character and pressed the game's B. In these games the mouse lives on
    buttons the game does not use: the RIGHT stick moves the pointer and
    pushing the right stick in (R3) taps. L3 still turns it on and off.

    KEYBOARD GAMES (2026-10-14). A game's section in flash-games.ini or
    browser-games.ini can give the controller keyboard keys:
        keys  = A:S, X:D, B:Down      button:key, as many as you like
        stick = arrows                the left stick sends the arrow keys
    Buttons: A B X Y LB RB LT RT Up Down Left Right. Keys: a letter, a
    number, Space Enter Shift Ctrl Tab Esc Backspace Up Down Left Right, F1-F12.
    Such a game starts in its keyboard layout; L3 swaps to the mouse and back.
        SELECT + START   still RetroBat's own "quit the game"

    It stops by itself when the game ends (RetroBat says nothing is running)
    or when RetroBat closes. One copy only. Written for Steven, 2026-10-11:
    "play the point and click games with a controller, still on the couch".

    Reads pads through RetroBat's own SDL2.dll, like the wizard does
    (PadInput.ps1). Log: _Wizard\Cache\logs\couch-mouse.log.

    ASCII ONLY, Windows PowerShell 5.1. $PSScriptRoot is resolved in the body.
#>
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$Ws   = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$Root = Split-Path $Ws -Parent
$log  = Join-Path $Ws 'Cache\logs\couch-mouse.log'

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
    $f = Join-Path $Ws 'Settings\couch-mouse.txt'
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
        # a game with its own key layout (2026-10-17)
        if ($null -ne (Get-CmKeymap $Path)) { return $true }
        if ((Get-Item -LiteralPath $Path).Length -gt 16KB) { return $false }
        $t = [System.IO.File]::ReadAllText($Path)
        return ($t -match 'Launch-Browser' -or $t -match '(?i)couch\s*mouse\s*=\s*on')
    }
    catch { return $false }
}

$script:CmGamePath = ''

# 2026-10-13: Wii U games that need the GamePad's touch screen open it in a
# second window that you click. 'wiiu-touch' in couch-mouse.txt gives those
# games the couch mouse in STANDBY: it starts OFF, so the controller plays the
# game as normal, and L3 switches it on to tap the GamePad window, then off
# again. Which games: controllers.ini kinds pro-touch and touch-extras-wiimote.
function Test-CmWiiuTouch([string]$Path) {
    try {
        if ($Path -eq '') { return $false }
        $rel = $Path.Replace('/', '\')
        $ix = $rel.ToLowerInvariant().IndexOf('\roms\wiiu\')
        if ($ix -ge 0) { $rel = $rel.Substring($ix + 11) } else { $rel = [System.IO.Path]::GetFileName($rel) }
        $key = $rel.Replace('\', '/').Trim().ToLowerInvariant()
        $ci = Join-Path $Ws 'Settings\controllers.ini'
        if (-not (Test-Path -LiteralPath $ci)) { return $false }
        $sec = ''
        foreach ($raw in [System.IO.File]::ReadAllLines($ci)) {
            $t = $raw.Trim()
            if ($t -eq '' -or $t.StartsWith(';')) { continue }
            if ($t -match '^\[([^\]]+)\]') { $sec = $Matches[1].Trim().ToLowerInvariant(); continue }
            if ($sec -ne 'wiiu') { continue }
            $p = $t.Split('|')
            if ($p.Count -lt 2) { continue }
            if ($p[1].Trim().Replace('\', '/').ToLowerInvariant() -eq $key) {
                return (@('pro-touch', 'touch-extras-wiimote') -contains $p[0].Trim().ToLowerInvariant())
            }
        }
    } catch { }
    return $false
}
# A game's own keyboard layout, from its section in flash-games.ini or
# browser-games.ini (headed by the game's file name). $null = none.
$script:CmVk = @{ space = 0x20; enter = 0x0D; shift = 0x10; ctrl = 0x11; tab = 0x09; esc = 0x1B; backspace = 0x08
                  up = 0x26; down = 0x28; left = 0x25; right = 0x27 }
# (2026-10-25) through KeyLayouts.ps1: the person playing's own layout when
# they made one, else the game's default. Read fresh each game.
function Get-CmKeymap([string]$Path) {
    try {
        if ($Path -eq '') { return $null }
        if (-not (Get-Command Get-KlLayout -ErrorAction SilentlyContinue)) { . (Join-Path $PSScriptRoot 'KeyLayouts.ps1') }
        $l = Get-KlLayout $Ws ([System.IO.Path]::GetFileName($Path))
        if ($l.Keys -ne '' -or $l.Stick -ne '') { return @{ Keys = $l.Keys; Stick = $l.Stick } }
    } catch { }
    return $null
}
function ConvertTo-CmVk([string]$Name) {
    $n = $Name.Trim().ToLower()
    if ($n -match '^[a-z]$') { return [int][char]$n.ToUpper() }
    if ($n -match '^[0-9]$') { return [int][char]$n }
    if ($n -match '^f([1-9]|1[0-2])$') { return 0x6F + [int]$Matches[1] }
    if ($script:CmVk.ContainsKey($n)) { return [int]$script:CmVk[$n] }
    return 0
}

# Game FILE names in couch-mouse.txt (a line with a dot in it).
function Get-CmFiles {
    $f = Join-Path $Ws 'Settings\couch-mouse.txt'
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


# --- the little pop-up (2026-10-13, Steven: "a little mouse icon when it
# turns on, and a little controller icon when it turns back off") --------
# A small square in the bottom right corner of the screen: a pixel mouse for ON, the
# drive's own controller picture for OFF. It never takes the focus away from
# the game and clicks pass straight through it. Shown for about a second and
# a half, then it fades. If anything about it fails, the couch mouse carries
# on without it.
$script:Toast = $null; $script:ToastShownAt = [DateTime]::MinValue
function Initialize-CmToast {
    try {
        Add-Type -AssemblyName System.Windows.Forms
        Add-Type -AssemblyName System.Drawing
        if (-not ([System.Management.Automation.PSTypeName]'RBToast').Type) {
            Add-Type -ReferencedAssemblies System.Windows.Forms, System.Drawing -TypeDefinition @'
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Windows.Forms;
public class RBToast : Form
{
    Image pic; string line1 = ""; string line2 = "";
    public RBToast()
    {
        FormBorderStyle = FormBorderStyle.None; ShowInTaskbar = false; TopMost = true;
        StartPosition = FormStartPosition.Manual; Width = 250; Height = 180;
        BackColor = Color.FromArgb(24, 24, 30); DoubleBuffered = true;
        // Bottom right, out of the way of the game (Steven, 2026-10-25).
        Rectangle wa = Screen.PrimaryScreen.WorkingArea;
        Left = wa.Right - Width - 28; Top = wa.Bottom - Height - 28;
    }
    protected override bool ShowWithoutActivation { get { return true; } }
    protected override CreateParams CreateParams
    {
        get
        {
            CreateParams cp = base.CreateParams;
            // no focus, no taskbar button, clicks pass through, always on top
            cp.ExStyle |= 0x08000000 | 0x00000080 | 0x00000020 | 0x00080000 | 0x00000008;
            return cp;
        }
    }
    public void Set(Image p, string a, string b) { pic = p; line1 = a; line2 = b; Invalidate(); }
    // A pixel computer mouse, drawn from a little map: # edge, f body, w wheel.
    public static Bitmap MouseIcon()
    {
        string[] m = {
            "    ######    ",
            "  ##ff##ff##  ",
            " #ffffwwffff# ",
            " #ffffwwffff# ",
            "#fffff##fffff#",
            "#fffff##fffff#",
            "##############",
            "#ffffffffffff#",
            "#ffffffffffff#",
            "#ffffffffffff#",
            "#ffffffffffff#",
            " #ffffffffff# ",
            " #ffffffffff# ",
            "  ##ffffff##  ",
            "    ######    " };
        Bitmap b = new Bitmap(14, 15);
        for (int y = 0; y < m.Length; y++)
            for (int x = 0; x < m[y].Length; x++)
            {
                char c = m[y][x];
                if (c == '#') b.SetPixel(x, y, Color.FromArgb(232, 232, 236));
                else if (c == 'f') b.SetPixel(x, y, Color.FromArgb(120, 124, 140));
                else if (c == 'w') b.SetPixel(x, y, Color.FromArgb(229, 184, 59));
                else b.SetPixel(x, y, Color.Transparent);
            }
        return b;
    }
    protected override void OnPaint(PaintEventArgs e)
    {
        Graphics g = e.Graphics;
        using (Pen edge = new Pen(Color.FromArgb(229, 184, 59), 4)) g.DrawRectangle(edge, 2, 2, Width - 5, Height - 5);
        if (pic != null)
        {
            g.InterpolationMode = InterpolationMode.NearestNeighbor;
            g.PixelOffsetMode = PixelOffsetMode.Half;
            int scale = Math.Max(1, Math.Min(84 / pic.Width, 84 / pic.Height));
            int w = pic.Width * scale, h = pic.Height * scale;
            g.DrawImage(pic, (Width - w) / 2, 16 + (84 - h) / 2, w, h);
        }
        StringFormat c = new StringFormat(); c.Alignment = StringAlignment.Center;
        using (Font f1 = new Font("Segoe UI", 13, FontStyle.Bold))
        using (Font f2 = new Font("Segoe UI", 9))
        {
            g.DrawString(line1, f1, Brushes.White, new RectangleF(0, 108, Width, 26), c);
            using (Brush dim = new SolidBrush(Color.FromArgb(170, 172, 184)))
                g.DrawString(line2, f2, dim, new RectangleF(8, 134, Width - 16, 36), c);
        }
    }
}
'@
        }
        $script:Toast = New-Object RBToast
        # Steven's pictures (2026-10-17): a mouse and a controller, both with
        # little waves, on a light square. Missing: the drawn mouse and the
        # Controllers picture, as before.
        function Get-CmPic([string]$Name) {
            $f = Join-Path $Ws ('Program\wizard\' + $Name)
            if (-not (Test-Path -LiteralPath $f)) { return $null }
            return [System.Drawing.Image]::FromStream((New-Object System.IO.MemoryStream(,[System.IO.File]::ReadAllBytes($f))))
        }
        $script:ToastMouse = Get-CmPic 'cm-mouse.png'
        if ($null -eq $script:ToastMouse) { $script:ToastMouse = [RBToast]::MouseIcon() }
        $script:ToastPad = Get-CmPic 'cm-pad.png'
        if ($null -eq $script:ToastPad) { $script:ToastPad = Get-CmPic 'controllers.png' }
    }
    catch { Write-CmLog ('pop-up unavailable: ' + $_.Exception.Message); $script:Toast = $null }
}
function Show-CmToast([string]$Layout) {
    if ($null -eq $script:Toast) { return }
    try {
        switch ($Layout) {
            'mouse' { $script:Toast.Set($script:ToastMouse, 'Mouse ON', 'Push in the left stick to switch off') }
            'touch' { $script:Toast.Set($script:ToastMouse, 'Mouse ON', 'Right stick moves, push it in to tap') }
            'keys'  { $script:Toast.Set($script:ToastPad, 'Controller', 'Push in the left stick for the mouse') }
            default { $script:Toast.Set($script:ToastPad, 'Controller', 'Push in the left stick for the mouse') }
        }
        $script:Toast.Opacity = 0.95
        if (-not $script:Toast.Visible) { $script:Toast.Show() }
        $script:Toast.Refresh()
        $script:ToastShownAt = [DateTime]::UtcNow
        [System.Windows.Forms.Application]::DoEvents()
    } catch { }
}
# Called every tick: fades the pop-up out and hides it.
function Update-CmToast {
    if ($null -eq $script:Toast -or -not $script:Toast.Visible) { return }
    try {
        $ms = ([DateTime]::UtcNow - $script:ToastShownAt).TotalMilliseconds
        if ($ms -gt 1900) { $script:Toast.Hide() }
        elseif ($ms -gt 1400) { $script:Toast.Opacity = 0.95 * (1 - ($ms - 1400) / 500) }
        [System.Windows.Forms.Application]::DoEvents()
    } catch { }
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
    $standby = ($sys -eq 'wiiu' -and $want -contains 'wiiu-touch' -and (Test-CmWiiuTouch $script:CmGamePath))
    if ($want -notcontains $sys -and -not $standby -and -not (Test-CmGameWants $script:CmGamePath)) { exit 0 }

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

    Initialize-CmToast
    $B = $script:PadBit
    # THE LAYOUTS. 'mouse' is the usual one below; 'touch' is the Wii U
    # GamePad-screen one (right stick + R3); 'keys' is a game's own keyboard
    # layout; 'off' sends nothing. L3 swaps between a game's two.
    $km = Get-CmKeymap $script:CmGamePath
    $keyHolds = @()
    $stickArrows = $false
    if ($null -ne $km) {
        $btn = @{ a = $B.A; b = $B.B; x = $B.X; y = $B.Y; lb = $B.LB; rb = $B.RB; lt = $B.LT; rt = $B.RT
                  up = $B.Up; down = $B.Down; left = $B.Left; right = $B.Right }
        $map = @{}
        foreach ($d in @(@('up', 0x26), @('down', 0x28), @('left', 0x25), @('right', 0x27))) { $map[$d[0]] = $d[1] }
        foreach ($pair in ([string]$km.Keys).Split(',')) {
            $kv = $pair.Split(':')
            if ($kv.Count -ne 2) { continue }
            $bn = $kv[0].Trim().ToLower(); $vk = ConvertTo-CmVk $kv[1]
            if ($btn.ContainsKey($bn) -and $vk -gt 0) { $map[$bn] = $vk }
        }
        foreach ($bn in $map.Keys) { $keyHolds += @{ Bit = $btn[$bn]; Kind = 'key'; Vk = $map[$bn] } }
        if ($km.Stick -eq 'arrows') {
            $stickArrows = $true
            $keyHolds += @{ Bit = $B.StickUp; Kind = 'key'; Vk = 0x26 }, @{ Bit = $B.StickDown; Kind = 'key'; Vk = 0x28 },
                         @{ Bit = $B.StickLeft; Kind = 'key'; Vk = 0x25 }, @{ Bit = $B.StickRight; Kind = 'key'; Vk = 0x27 }
        }
    }
    $touchHolds = @(@{ Bit = $B.R3; Kind = 'mouse'; Right = $false })
    if ($standby) { $layout = 'off'; $other = 'touch' }
    elseif ($null -ne $km) { $layout = 'keys'; $other = 'mouse' }
    else { $layout = 'mouse'; $other = 'off' }
    if ($standby) { Write-CmLog ('standby for ' + $sys + ' (GamePad screen game): L3 switches it on, right stick + R3') }
    else { Write-CmLog ("on for " + $sys + ", " + $layout); Show-CmToast $layout }
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
    $mouseHolds = $holds
    function Get-CmHolds([string]$l) { switch ($l) { 'mouse' { return $mouseHolds } 'touch' { return $touchHolds } 'keys' { return $keyHolds } default { return @() } } }
    function Clear-CmHolds([string]$l, [int]$was) {
        foreach ($h in @(Get-CmHolds $l)) { if (($was -band $h.Bit) -ne 0) { if ($h.Kind -eq 'mouse') { [RBCouch]::Button($h.Right, $false) } else { [RBCouch]::Key([byte]$h.Vk, $false) } } }
    }
    $prev = 0; $tick = 0; $wheelWait = 0
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
            Clear-CmHolds $layout $prev
            $t = $layout; $layout = $other; $other = $t
            Write-CmLog ('L3: ' + $layout)
            Show-CmToast $layout
        }
        if ($layout -ne 'off' -and -not $quit) {
            if ($layout -eq 'mouse') { [RBCouch]::Move([RBPad]::LX, [RBPad]::LY, $scale) }
            elseif ($layout -eq 'touch') {
                # A pushed-in stick wobbles; hold the pointer still while R3 is down.
                if (($s -band $B.R3) -eq 0) { [RBCouch]::Move([RBPad]::RX, [RBPad]::RY, $scale) }
            }
            foreach ($h in @(Get-CmHolds $layout)) {
                $d = (($new -band $h.Bit) -ne 0); $u = (($gone -band $h.Bit) -ne 0)
                if (-not $d -and -not $u) { continue }
                if ($h.Kind -eq 'mouse') { [RBCouch]::Button($h.Right, $d) } else { [RBCouch]::Key([byte]$h.Vk, $d) }
            }
            if ($layout -eq 'mouse') {
                if ($wheelWait -gt 0) { $wheelWait-- }
                elseif ($s -band ($B.RStickUp -bor $B.RStickDown)) { [RBCouch]::Wheel((($s -band $B.RStickDown) -ne 0)); $wheelWait = 5 }
            }
        }
        $prev = $s
        Update-CmToast
        # Every two seconds: is the game still running?
        $tick++
        if ($tick % 125 -eq 0) {
            if ((Get-CmRunningSystem) -eq '') { break }
        }
    }
    # Let go of anything still held, so no button is left stuck down.
    Clear-CmHolds $layout $prev
    Write-CmLog 'game over, off'
}
catch { Write-CmLog ("stopped: " + $_.Exception.Message) }
finally {
    try { [RBPad]::Quit() } catch { }
    try { if ($null -ne $script:Toast) { $script:Toast.Close() } } catch { }
    try { if ($null -ne $mutex) { $mutex.ReleaseMutex(); $mutex.Dispose() } } catch { }
}
