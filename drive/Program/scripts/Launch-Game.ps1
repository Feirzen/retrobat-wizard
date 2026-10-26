<#
    Launch-Game.ps1
    ---------------------------------------------------------------------------
    What a desktop shortcut to one game actually runs. Started (hidden) by
    Launch-Game.vbs, which hands over the game in the RB_GAME variable.

    THE IDEA. A shortcut must NOT start the emulator itself. EmulationStation
    (RetroBat's menu) hands every emulator a live description of the pads
    plugged in right now, picks the emulator and core, and runs the drive's
    game-end hook that backs up saves. A shortcut that skipped it had dead
    controllers, no SELECT + START, and no save backup (paused 2026-09-21).

    So this asks EmulationStation to launch the game instead, through the
    small web service it runs for programs on the same computer
    (http://localhost:1234 - /launch, /runningGame, /quit). The game then
    starts exactly as if it had been picked from the menu.

      1. If RetroBat's menu is not running, start it (straight to
         emulationstation.exe, with the same switches RetroBat.exe uses, so
         the intro video is skipped).
      2. Ask it to launch the game. Retry until it has finished loading.
      3. Wait for the game to start, then to end.
      4. If THIS script started the menu, wait for the save backup to finish
         and close the menu again, so the shortcut lands back on the desktop.
         If the menu was already open, leave it open.

    If anything goes wrong the menu is simply left open, so the worst case is
    ordinary RetroBat. Everything is written to
    _Wizard\Cache\logs\game-shortcut.log.

    RULES: no drive letters (all from this file's own location), Windows
    PowerShell 5.1, pure ASCII.
#>

Set-StrictMode -Off
$ErrorActionPreference = 'Continue'

$Root   = Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
$EsDir  = Join-Path $Root 'emulationstation'
$EsExe  = Join-Path $EsDir 'emulationstation.exe'
$LogDir = Join-Path $Root '_Wizard\Cache\logs'
$Log    = Join-Path $LogDir 'game-shortcut.log'
$Api    = 'http://127.0.0.1:1234'

function Write-Log([string]$msg) {
    try {
        if ((Test-Path -LiteralPath $Log) -and ((Get-Item -LiteralPath $Log).Length -gt 200KB)) {
            Move-Item -LiteralPath $Log -Destination ($Log + '.old') -Force
        }
        $line = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + '  ' + $msg
        [System.IO.File]::AppendAllText($Log, $line + "`r`n")
    }
    catch { }
}

# One call to EmulationStation's web service. Returns Status (0 = nothing
# answered) and Body. No proxy, ever: this only talks to this computer.
function Invoke-EsApi([string]$Method, [string]$Path, [string]$Body = '') {
    $r = [pscustomobject]@{ Status = 0; Body = '' }
    try {
        $req = [System.Net.HttpWebRequest]::Create($Api + $Path)
        $req.Method = $Method
        $req.Proxy = $null
        $req.Timeout = 4000
        $req.ReadWriteTimeout = 4000
        # [string] turns a missing body into '' rather than null, so decide by
        # the verb: a GET must not carry a body at all.
        if ($Method -ne 'GET') {
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($Body)
            $req.ContentType = 'text/plain; charset=utf-8'
            $req.ContentLength = $bytes.Length
            $s = $req.GetRequestStream(); $s.Write($bytes, 0, $bytes.Length); $s.Close()
        }
        $resp = $req.GetResponse()
        $r.Status = [int]$resp.StatusCode
        $sr = New-Object System.IO.StreamReader($resp.GetResponseStream())
        $r.Body = $sr.ReadToEnd(); $sr.Close(); $resp.Close()
    }
    catch [System.Net.WebException] {
        $resp = $_.Exception.Response
        if ($resp) { $r.Status = [int]$resp.StatusCode; try { $resp.Close() } catch { } }
    }
    catch { }
    return $r
}

# RetroBat's menu, but only the copy that lives on THIS drive.
function Get-EsProcess {
    foreach ($p in @(Get-Process -Name 'emulationstation' -ErrorAction SilentlyContinue)) {
        try { if ($p.Path -and $p.Path.StartsWith($EsDir, [System.StringComparison]::OrdinalIgnoreCase)) { return $p } }
        catch { }
    }
    return $null
}

function Test-GameRunning {
    $r = Invoke-EsApi 'GET' '/runningGame'
    return ($r.Status -eq 200 -and $r.Body.Trim() -ne '')
}

# The switches RetroBat.exe itself passes (see RetroBat.log), read from
# retrobat.ini so a change made in RetroBat's own settings still counts.
function Get-EsArguments {
    $ini = @{}
    try {
        $section = ''
        foreach ($line in [System.IO.File]::ReadAllLines((Join-Path $Root 'retrobat.ini'))) {
            $t = $line.Trim()
            if ($t -match '^\[(.+)\]$') { $section = $Matches[1]; continue }
            if ($section -eq 'EmulationStation' -and $t -match '^([^;=]+)=(.*)$') { $ini[$Matches[1].Trim()] = $Matches[2].Trim() }
        }
    }
    catch { }
    $a = @()
    if ($ini['Fullscreen'] -eq '0') { $a += '--windowed' }
    elseif ($ini['FullscreenBorderless'] -eq '0') { $a += '--fullscreen' }
    else { $a += '--fullscreen-borderless' }
    if ($ini['VSync'] -eq '0') { $a += '"--vsync 0"' } else { $a += '"--vsync 1"' }
    if ($ini['MonitorIndex'] -and $ini['MonitorIndex'] -ne '0') { $a += ('--monitor ' + $ini['MonitorIndex']) }
    if ($ini['GameListOnly'] -eq '1') { $a += '--gamelist-only' }
    $a += ('--home "' + $EsDir + '"')
    return ($a -join ' ')
}


# ---------------------------------------------------------------------------
#  Muting RetroBat's menu, and ONLY RetroBat's menu (2026-09-25).
#
#  Hiding the window after a game was not enough: its menu music kept
#  playing for the half minute the save backup takes. Windows keeps a volume
#  control per program (the Volume Mixer), and this reaches it through
#  Windows' own audio interfaces, so nothing else on the computer goes quiet.
#
#  WINDOWS REMEMBERS A PROGRAM'S MUTE. So the menu is always unmuted again
#  just before it closes, and unmuted at the start of every shortcut launch
#  as well, in case an earlier run was interrupted half way. Otherwise
#  RetroBat opened normally next time would be silent for no visible reason.
# ---------------------------------------------------------------------------
$script:AudioOk = $false
try {
    Add-Type -ErrorAction Stop -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

namespace RBAudio
{
    [ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")] class MMDeviceEnumeratorCo { }

    [Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IMMDeviceEnumerator
    {
        [PreserveSig] int EnumAudioEndpoints(int dataFlow, int stateMask, out IMMDeviceCollection devices);
    }

    [Guid("0BD7A1BE-7A1A-44DB-8397-CC5392387B5E"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IMMDeviceCollection
    {
        [PreserveSig] int GetCount(out int count);
        [PreserveSig] int Item(int index, out IMMDevice device);
    }

    [Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IMMDevice
    {
        [PreserveSig] int Activate(ref Guid iid, int clsCtx, IntPtr activationParams, [MarshalAs(UnmanagedType.IUnknown)] out object iface);
    }

    [Guid("77AA99A0-1BD6-484F-8BC7-2C654C9A9B6F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IAudioSessionManager2
    {
        [PreserveSig] int GetAudioSessionControl(IntPtr a, int b, out IntPtr c);
        [PreserveSig] int GetSimpleAudioVolume(IntPtr a, int b, out IntPtr c);
        [PreserveSig] int GetSessionEnumerator(out IAudioSessionEnumerator sessions);
    }

    [Guid("E2F5BB11-0570-40CA-ACDD-3AA01277DEE8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IAudioSessionEnumerator
    {
        [PreserveSig] int GetCount(out int count);
        [PreserveSig] int GetSession(int index, out IAudioSessionControl2 session);
    }

    [Guid("bfb7ff88-7239-4fc9-8fa2-07c950be9c6d"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IAudioSessionControl2
    {
        // The nine methods of IAudioSessionControl, unused here but they
        // must be declared so the ones below land in the right slots.
        [PreserveSig] int GetState(out int state);
        [PreserveSig] int GetDisplayName(out IntPtr name);
        [PreserveSig] int SetDisplayName(IntPtr name, IntPtr ctx);
        [PreserveSig] int GetIconPath(out IntPtr path);
        [PreserveSig] int SetIconPath(IntPtr path, IntPtr ctx);
        [PreserveSig] int GetGroupingParam(out Guid g);
        [PreserveSig] int SetGroupingParam(IntPtr g, IntPtr ctx);
        [PreserveSig] int RegisterAudioSessionNotification(IntPtr n);
        [PreserveSig] int UnregisterAudioSessionNotification(IntPtr n);
        [PreserveSig] int GetSessionIdentifier(out IntPtr id);
        [PreserveSig] int GetSessionInstanceIdentifier(out IntPtr id);
        [PreserveSig] int GetProcessId(out uint pid);
    }

    [Guid("87CE5498-68D6-44E5-9215-6DA47EF883D8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface ISimpleAudioVolume
    {
        [PreserveSig] int SetMasterVolume(float level, ref Guid ctx);
        [PreserveSig] int GetMasterVolume(out float level);
        [PreserveSig] int SetMute([MarshalAs(UnmanagedType.Bool)] bool mute, ref Guid ctx);
        [PreserveSig] int GetMute([MarshalAs(UnmanagedType.Bool)] out bool mute);
    }

    public static class Mixer
    {
        // Mute or unmute every sound session belonging to one program, on
        // every active speaker. Returns how many sessions were changed.
        public static int SetProcessMute(int pid, bool mute)
        {
            int changed = 0;
            IMMDeviceEnumerator en = (IMMDeviceEnumerator)(new MMDeviceEnumeratorCo());
            IMMDeviceCollection devs;
            if (en.EnumAudioEndpoints(0, 1, out devs) != 0 || devs == null) return 0;
            int n; devs.GetCount(out n);
            Guid iidMgr = typeof(IAudioSessionManager2).GUID;
            for (int d = 0; d < n; d++)
            {
                try
                {
                    IMMDevice dev; if (devs.Item(d, out dev) != 0 || dev == null) continue;
                    object o; if (dev.Activate(ref iidMgr, 23, IntPtr.Zero, out o) != 0 || o == null) continue;
                    IAudioSessionManager2 mgr = (IAudioSessionManager2)o;
                    IAudioSessionEnumerator sessions; if (mgr.GetSessionEnumerator(out sessions) != 0 || sessions == null) continue;
                    int c; sessions.GetCount(out c);
                    for (int i = 0; i < c; i++)
                    {
                        try
                        {
                            IAudioSessionControl2 ctl; if (sessions.GetSession(i, out ctl) != 0 || ctl == null) continue;
                            uint p; ctl.GetProcessId(out p);
                            if ((int)p != pid) continue;
                            ISimpleAudioVolume vol = (ISimpleAudioVolume)ctl;
                            Guid none = Guid.Empty;
                            if (vol.SetMute(mute, ref none) == 0) changed++;
                        }
                        catch { }
                    }
                }
                catch { }
            }
            return changed;
        }
    }
}
'@
    $script:AudioOk = $true
}
catch { $script:AudioOk = $false }

function Set-MenuMute($Process, [bool]$Mute) {
    if (-not $script:AudioOk -or $null -eq $Process) { return }
    try {
        $n = [RBAudio.Mixer]::SetProcessMute($Process.Id, $Mute)
        if ($n -gt 0) { Write-Log ($(if ($Mute) { 'Muted' } else { 'Unmuted' }) + ' RetroBat''s menu.') }
    }
    catch { Write-Log ('Could not change the menu''s sound: ' + $_.Exception.Message) }
}

# ---------------------------------------------------------------------------

$game = [string]$env:RB_GAME
if ($game -eq '') { Write-Log 'No game was handed over. Nothing to do.'; exit 1 }
if ($game -notmatch '^[A-Za-z]:\\' -and $game -notmatch '^\\\\') { $game = Join-Path $Root $game }
Write-Log ('--- Shortcut for ' + $game)

if (-not (Test-Path -LiteralPath $game)) { Write-Log 'That game is not on the drive. Stopping.'; exit 1 }
if (-not (Test-Path -LiteralPath $EsExe)) { Write-Log ('No emulationstation.exe at ' + $EsExe); exit 1 }

$weStarted = $false
$es = Get-EsProcess
if ($null -eq $es) {
    $esArgs = Get-EsArguments
    Write-Log ('Starting RetroBat''s menu: ' + $esArgs)
    try {
        $es = Start-Process -FilePath $EsExe -ArgumentList $esArgs -WorkingDirectory $EsDir -PassThru -ErrorAction Stop
        $weStarted = $true
    }
    catch { Write-Log ('Could not start it: ' + $_.Exception.Message); exit 1 }
}
else {
    if (Test-GameRunning) { Write-Log 'A game is already running. Leaving it alone.'; exit 0 }
}

# Ask for the game. The service answers 404 until the game lists are loaded,
# and nothing at all before that, so keep asking for up to two minutes.
$forms = @($game, ($game -replace '\\', '/')) | Select-Object -Unique
$launched = $false
$deadline = (Get-Date).AddSeconds(120)
$lastStatus = -1
while ((Get-Date) -lt $deadline) {
    if ($es.HasExited) { Write-Log 'RetroBat''s menu closed before the game could be asked for.'; exit 1 }
    foreach ($f in $forms) {
        $r = Invoke-EsApi 'POST' '/launch' $f
        if ($r.Status -ne $lastStatus) { Write-Log ('Asked to launch, answer ' + $r.Status); $lastStatus = $r.Status }
        if ($r.Status -ge 200 -and $r.Status -lt 300) { $launched = $true; break }
        if ($r.Status -eq 0) { break }   # not listening yet; the other form will not help
    }
    if ($launched) { break }
    Start-Sleep -Milliseconds 1000
}
if (-not $launched) {
    Write-Log 'RetroBat never accepted the game. Leaving the menu open so it can be picked by hand.'
    exit 1
}

# Wait for it to start. Generous, because some systems show RetroBat's
# launch menu first and a person may take a while to choose.
$started = $false
$deadline = (Get-Date).AddMinutes(30)
while ((Get-Date) -lt $deadline -and -not $es.HasExited) {
    if (Test-GameRunning) { $started = $true; break }
    Start-Sleep -Milliseconds 1000
}
if (-not $started) { Write-Log 'The game never started (backed out of the menu?). Leaving RetroBat open.'; exit 0 }
Write-Log 'Game running.'
# Undo any mute an interrupted earlier run left behind (see above).
Set-MenuMute $es $false

while (-not $es.HasExited -and (Test-GameRunning)) { Start-Sleep -Seconds 2 }
Write-Log 'Game ended.'

if (-not $weStarted -or $es.HasExited) { exit 0 }

# Hide the menu straight away. RetroBat comes back to the game list while
# the save backup runs, which can take half a minute or more, and seeing it
# sit there reads as "it did not close". It is still running (and still
# finishing the backup) - just out of sight until it is closed below.
try {
    Add-Type -Namespace RBWin -Name User32 -MemberDefinition '[DllImport("user32.dll")] public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);' -ErrorAction Stop
    for ($i = 0; $i -lt 10; $i++) {
        $es.Refresh()
        if ($es.MainWindowHandle -ne [IntPtr]::Zero) { [void][RBWin.User32]::ShowWindowAsync($es.MainWindowHandle, 0); Write-Log 'Hid RetroBat''s menu while the save backup finishes.'; break }
        Start-Sleep -Milliseconds 300
    }
}
catch { Write-Log ('Could not hide the menu: ' + $_.Exception.Message) }
Set-MenuMute $es $true

# Let the game-end hook (save backup) finish. It runs as a child of the menu.
$deadline = (Get-Date).AddSeconds(120)
while ((Get-Date) -lt $deadline) {
    $kids = @()
    try {
        $kids = @(Get-CimInstance Win32_Process -Filter ('ParentProcessId=' + $es.Id) -ErrorAction Stop |
                  Where-Object { $_.Name -notmatch '^(conhost|WerFault)\.exe$' })
    }
    catch { }
    if ($kids.Count -eq 0) { break }
    Start-Sleep -Seconds 1
}
Start-Sleep -Seconds 1

Write-Log 'Closing RetroBat''s menu, since the shortcut opened it.'
$q = Invoke-EsApi 'GET' '/quit'
if ($q.Status -lt 200 -or $q.Status -ge 300) { [void](Invoke-EsApi 'POST' '/quit' '') }
# Unmute AFTER asking it to close (so the music does not come back while it
# is still on its way out) but BEFORE it is gone (so Windows does not
# remember it as muted). It takes a moment to close, which is the window.
Start-Sleep -Milliseconds 300
Set-MenuMute $es $false
if (-not $es.WaitForExit(15000)) {
    Write-Log 'It did not close when asked. Closing its window.'
    try { [void]$es.CloseMainWindow() } catch { }
    if (-not $es.WaitForExit(10000)) { Write-Log 'Still open. Left it running rather than force it.' }
}
Write-Log 'Done.'
exit 0
