<#
    Launch-Browser.ps1 - plays one browser game.

    Browser games live on RetroBat's OWN Windows shelf (roms\windows), so no
    custom shelf is needed (Steven, 2026-10-11: "I don't want to make another
    custom one"). Each is a small .bat file there that hands itself to
    Launch-Browser.vbs (no console window), which runs this. The game opens in
    the browser's APP MODE: its own window, full screen, no tabs and no
    address bar, so it feels like a program rather than a web page. RetroBat
    waits until it is closed, exactly like any other game.

    WHICH BROWSER: Chrome when the computer has it (Steven's default), else
    Microsoft Edge, which every Windows 10 and 11 has. Both have the same app
    mode. (Windows' "default browser" setting cannot do app mode, which is
    why it is not simply asked to open the address.)

    THE GAME'S LINES, in its .bat, each after REM:
        REM url  = https://www.poptropica.com/   a game on the internet
        REM file = My Game\index.html            a downloaded game in a folder
                                                beside the .bat (plays
                                                offline, no ads)
        REM zoom = 1.25                           optional, makes it bigger
    One of url / file is needed.

    THE BROWSER'S MEMORY (logins, game progress) is kept ON THE DRIVE, in
    _Wizard\People\browser\<chrome or edge>\, so it travels with
    the drive and never mixes with anybody's own browser. Never shipped.

    SELECT + START closes the game, like every other game on the drive. It
    is watched here, because RetroBat's own close button only works for
    games it starts itself.

    APP GAMES (added 2026-10-13). Some old games no longer run in any
    browser - New Club Penguin is Flash, which browsers dropped - and come as
    their own small program instead. Their .bat says:
        REM app = NewCP                      the program's folder name
        REM get = https://.../x-full.nupkg   where to fetch it the first time
    The first launch downloads it (with a progress window) and unpacks it
    into _Wizard\Apps\<name>\ ON THE DRIVE, so it then travels with
    the drive and starts on any computer with nothing installed. Only the
    program's own files are kept; its logins live on each computer, like any
    program's.

    WHITE SCREEN FIX (2026-10-13, Steven on the ZBook: "Edge in full screen,
    stayed a white screen"). The browser used to be started straight into
    full screen. On a computer whose browser has never seen the drive's
    profile, Edge first builds that profile on the (slow) drive and may put
    up its own one-time welcome questions - hidden behind a full-screen
    window that shows nothing. Now it opens MAXIMISED, a small "Opening..."
    window shows while it loads, and it is switched to full screen (F11)
    only once the page has a title. If Edge asks anything, it can be seen.

    Log: _Wizard\Cache\logs\browser-games.log.
    ASCII ONLY, Windows PowerShell 5.1. $PSScriptRoot is resolved in the body.
#>
param([string]$Game = '')
$ErrorActionPreference = 'Stop'
$Ws   = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$Root = Split-Path $Ws -Parent
$log  = Join-Path $Ws 'Cache\logs\browser-games.log'
function Write-BgLog([string]$m) {
    try { [System.IO.File]::AppendAllText($log, ((Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + '  ' + $m + "`r`n")) } catch { }
}

# key = value lines of a .web file.
function Read-WebFile([string]$Path) {
    $o = @{}
    foreach ($line in [System.IO.File]::ReadAllLines($Path)) {
        $t = $line.Trim()
        if ($t -match '^(?i)(@?rem|::)\s+(.*)$') { $t = $Matches[2].Trim() }
        if ($t -eq '' -or $t.StartsWith(';') -or $t.StartsWith('#')) { continue }
        $eq = $t.IndexOf('=')
        if ($eq -lt 1) { continue }
        $o[$t.Substring(0, $eq).Trim().ToLower()] = $t.Substring($eq + 1).Trim()
    }
    return $o
}

# What to open: an https address, or a file:// address for a downloaded game
# that sits inside roms\browser (never anywhere else). '' when neither.
function Get-WebTarget($Info, [string]$WebPath) {
    $u = [string]$Info['url']
    if ($u -match '^https?://[^\s"]+$') { return $u }
    $f = [string]$Info['file']
    if ($f -ne '' -and $f -notmatch '^[A-Za-z]:' -and $f -notmatch '\.\.' -and -not $f.StartsWith('\') -and -not $f.StartsWith('/')) {
        $p = Join-Path (Split-Path $WebPath -Parent) $f
        if (Test-Path -LiteralPath $p) { return ([System.Uri]([System.IO.Path]::GetFullPath($p))).AbsoluteUri }
    }
    return ''
}

# Chrome first, then Edge (every Windows 10 and 11 has it). '' when neither.
function Find-AppBrowser {
    $c = @()
    foreach ($pf in @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:LOCALAPPDATA)) {
        if ([string]::IsNullOrEmpty($pf)) { continue }
        $c += (Join-Path $pf 'Google\Chrome\Application\chrome.exe')
    }
    foreach ($pf in @(${env:ProgramFiles(x86)}, $env:ProgramFiles, $env:LOCALAPPDATA)) {
        if ([string]::IsNullOrEmpty($pf)) { continue }
        $c += (Join-Path $pf 'Microsoft\Edge\Application\msedge.exe')
    }
    foreach ($k in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe', 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\msedge.exe')) {
        try { $v = (Get-ItemProperty -Path $k -ErrorAction Stop).'(default)'; if ($v) { $c += $v } } catch { }
    }
    foreach ($p in $c) { if (Test-Path -LiteralPath $p) { return $p } }
    return ''
}

# Every browser process using the drive's profile folder. A second game
# started while one is open is handed to the first process, which is why
# the wait below follows the profile rather than the process it started.
function Get-ProfileProcesses([string]$ProfileDir) {
    try {
        $key = $ProfileDir.ToLower()
        return @(Get-CimInstance Win32_Process -Filter "Name='msedge.exe' OR Name='chrome.exe'" -ErrorAction Stop |
                 Where-Object { ([string]$_.CommandLine).ToLower().Contains($key) })
    }
    catch { return @() }
}

function Close-ProfileBrowser([string]$ProfileDir) {
    $procs = @(Get-ProfileProcesses $ProfileDir)
    foreach ($p in $procs) { try { [void](Get-Process -Id $p.ProcessId -ErrorAction Stop).CloseMainWindow() } catch { } }
    Start-Sleep -Milliseconds 2500
    foreach ($p in @(Get-ProfileProcesses $ProfileDir)) { try { Stop-Process -Id $p.ProcessId -Force -ErrorAction Stop } catch { } }
}

# --- the "Opening..." window: something on screen while it loads ------------
$script:Splash = $null
function Show-Opening([string]$Text) {
    try {
        Add-Type -AssemblyName System.Windows.Forms
        Add-Type -AssemblyName System.Drawing
        $f = New-Object System.Windows.Forms.Form
        $f.FormBorderStyle = 'None'; $f.StartPosition = 'CenterScreen'; $f.TopMost = $true
        $f.ShowInTaskbar = $false; $f.Width = 440; $f.Height = 120
        $f.BackColor = [System.Drawing.Color]::FromArgb(30, 31, 38)
        $l = New-Object System.Windows.Forms.Label
        $l.Text = $Text; $l.ForeColor = [System.Drawing.Color]::FromArgb(232, 232, 236)
        $l.Font = New-Object System.Drawing.Font('Segoe UI', 14)
        $l.Dock = 'Fill'; $l.TextAlign = 'MiddleCenter'
        $f.Controls.Add($l)
        $f.Show(); [System.Windows.Forms.Application]::DoEvents()
        $script:Splash = $f
        $script:SplashLabel = $l
    } catch { }
}
function Set-Opening([string]$Text) {
    try { if ($null -ne $script:Splash) { $script:SplashLabel.Text = $Text; [System.Windows.Forms.Application]::DoEvents() } } catch { }
}
function Close-Opening { try { if ($null -ne $script:Splash) { $script:Splash.Close(); $script:Splash = $null } } catch { } }
function Wait-Pump([int]$Ms) {
    $end = [DateTime]::UtcNow.AddMilliseconds($Ms)
    while ([DateTime]::UtcNow -lt $end) { try { [System.Windows.Forms.Application]::DoEvents() } catch { }; Start-Sleep -Milliseconds 30 }
}

if (-not ([System.Management.Automation.PSTypeName]'RBWin').Type) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class RBWin
{
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
    [DllImport("user32.dll")] static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
    public static void Tap(byte vk) { keybd_event(vk, 0, 0, UIntPtr.Zero); keybd_event(vk, 0, 2, UIntPtr.Zero); }
}
'@
}

# The browser's game window, once the page inside it has a real title.
function Find-GameWindow([string]$ProfileDir) {
    foreach ($p in @(Get-ProfileProcesses $ProfileDir)) {
        try {
            $gp = Get-Process -Id $p.ProcessId -ErrorAction Stop
            if ($gp.MainWindowHandle -ne [IntPtr]::Zero) { return $gp }
        } catch { }
    }
    return $null
}

# --- app games: fetched once onto the drive, then run from it --------------
function Get-AppExe([string]$AppDir) {
    $marker = Join-Path $AppDir 'app.txt'
    if (Test-Path -LiteralPath $marker) {
        $rel = ([System.IO.File]::ReadAllText($marker)).Trim()
        $exe = Join-Path $AppDir $rel
        if ($rel -ne '' -and $rel -notmatch '\.\.' -and (Test-Path -LiteralPath $exe)) { return $exe }
    }
    return ''
}

function Install-AppGame([string]$Name, [string]$Url, [string]$AppDir) {
    if ($Url -notmatch '^https://[^\s"]+\.(nupkg|zip)$') { Write-BgLog ("app " + $Name + ": no usable get = address"); return '' }
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch { }
    $tmp = Join-Path $Ws ('Apps\_download-' + $Name + '.zip')
    New-Item -ItemType Directory -Path (Split-Path $tmp -Parent) -Force | Out-Null
    Set-Opening ("Getting " + $Name + " for the first time..." + [Environment]::NewLine + "(only once, then it lives on the drive)")
    Write-BgLog ("app " + $Name + ": downloading " + $Url)
    try {
        $wc = New-Object System.Net.WebClient
        $task = $wc.DownloadFileTaskAsync($Url, $tmp)
        while (-not $task.IsCompleted) {
            $mb = 0; try { if (Test-Path -LiteralPath $tmp) { $mb = [math]::Round((Get-Item -LiteralPath $tmp).Length / 1MB) } } catch { }
            Set-Opening ("Getting " + $Name + " for the first time... " + $mb + " MB" + [Environment]::NewLine + "(only once, then it lives on the drive)")
            Wait-Pump 400
        }
        if ($task.IsFaulted) { throw $task.Exception.InnerException }
    }
    catch { Write-BgLog ("app " + $Name + ": download failed - " + $_.Exception.Message); try { Remove-Item -LiteralPath $tmp -Force } catch { }; return '' }

    Set-Opening ("Unpacking " + $Name + "...")
    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $part = $AppDir + '.part'
        if (Test-Path -LiteralPath $part) { Remove-Item -LiteralPath $part -Recurse -Force }
        New-Item -ItemType Directory -Path $part -Force | Out-Null
        $zip = [System.IO.Compression.ZipFile]::OpenRead($tmp)
        try {
            # A .nupkg (the Windows program inside a Squirrel installer) keeps
            # the program under lib\net45\. A plain zip is taken whole.
            $prefix = ''
            foreach ($e in $zip.Entries) { if ($e.FullName -like 'lib/net45/*') { $prefix = 'lib/net45/'; break } }
            foreach ($e in $zip.Entries) {
                if ($e.FullName.EndsWith('/')) { continue }
                if ($prefix -ne '' -and -not $e.FullName.StartsWith($prefix)) { continue }
                $rel = [Uri]::UnescapeDataString($e.FullName.Substring($prefix.Length))   # .nupkg names spaces %20
                if ($rel -match '\.\.' -or $rel.StartsWith('/')) { continue }
                $dest = Join-Path $part ($rel -replace '/', '\')
                New-Item -ItemType Directory -Path (Split-Path $dest -Parent) -Force | Out-Null
                [System.IO.Compression.ZipFileExtensions]::ExtractToFile($e, $dest, $true)
                [System.Windows.Forms.Application]::DoEvents()
            }
        }
        finally { $zip.Dispose() }
        # The program is the biggest .exe that is not an updater.
        $exe = Get-ChildItem -LiteralPath $part -Filter '*.exe' -File -Recurse |
               Where-Object { $_.Name -notmatch '(?i)^(squirrel|update|setup|uninstall|elevate|crashpad)' } |
               Sort-Object Length -Descending | Select-Object -First 1
        if ($null -eq $exe) { throw 'no program found inside the download' }
        $relExe = $exe.FullName.Substring($part.Length).TrimStart('\')
        [System.IO.File]::WriteAllText((Join-Path $part 'app.txt'), $relExe)
        if (Test-Path -LiteralPath $AppDir) { Rename-Item -LiteralPath $AppDir -NewName ((Split-Path $AppDir -Leaf) + '.old-' + (Get-Date -Format 'yyyyMMddHHmmss')) }
        Rename-Item -LiteralPath $part -NewName (Split-Path $AppDir -Leaf)
        Remove-Item -LiteralPath $tmp -Force
        Write-BgLog ("app " + $Name + ": ready, " + $relExe)
        return (Join-Path $AppDir $relExe)
    }
    catch { Write-BgLog ("app " + $Name + ": unpack failed - " + $_.Exception.Message); return '' }
}

function Get-AppProcesses([string]$AppDir) {
    $key = $AppDir.ToLower()
    return @(Get-Process -ErrorAction SilentlyContinue | Where-Object { try { ([string]$_.Path).ToLower().StartsWith($key) } catch { $false } })
}

# --- SELECT + START, and "is it still open?" ---------------------------------
function Wait-GameClosed([scriptblock]$StillOpen, [scriptblock]$CloseIt) {
    $padOk = $false
    try {
        . (Join-Path $PSScriptRoot 'PadInput.ps1')
        [RBPad]::Pump = $true
        $padOk = [RBPad]::Init((Join-Path $Root 'emulationstation\SDL2.dll'))
    } catch { }
    $B = $script:PadBit
    $quiet = 0; $n = 0
    while ($true) {
        Start-Sleep -Milliseconds 50
        if ($padOk) {
            $s = [RBPad]::Poll()
            if ((($s -band $B.Back) -ne 0) -and (($s -band $B.Start) -ne 0)) {
                Write-BgLog 'closed with SELECT + START'
                & $CloseIt
                break
            }
        }
        $n++
        if ($n % 40 -eq 0) {
            if (-not (& $StillOpen)) { $quiet++ } else { $quiet = 0 }
            # 4 checks (8 seconds): a launcher that hands over to its game can
            # leave a short gap with nothing running (Monkey Quest, 2026-10-14).
            if ($quiet -ge 4) { break }
        }
    }
}

try {
    if ($Game -eq '' -and $env:RB_GAME) { $Game = $env:RB_GAME }
    if ($Game -eq '' -or -not (Test-Path -LiteralPath $Game)) { Write-BgLog ("no game file: " + $Game); exit 1 }
    $info = Read-WebFile $Game
    $title = [System.IO.Path]::GetFileNameWithoutExtension($Game)
    Show-Opening ("Opening " + $title + "...")

    # ---- an app game -------------------------------------------------------
    $appName = [string]$info['app']
    if ($appName -match '^[A-Za-z0-9 _\-]{1,40}$') {
        $appDir = Join-Path $Ws ('Apps\' + $appName)
        $exe = Get-AppExe $appDir
        if ($exe -eq '') { $exe = Install-AppGame $appName ([string]$info['get']) $appDir }
        if ($exe -eq '') {
            Set-Opening ($title + " could not be set up." + [Environment]::NewLine + "Check the internet, then try again.")
            Wait-Pump 4000; Close-Opening; exit 1
        }
        Write-BgLog ("open " + (Split-Path -Leaf $Game) + " -> app " + $exe)
        [void](Start-Process -FilePath $exe -WorkingDirectory (Split-Path $exe -Parent) -PassThru)
        for ($i = 0; $i -lt 60; $i++) {
            if (@(Get-AppProcesses $appDir | Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero }).Count -gt 0) { break }
            Wait-Pump 500
        }
        Close-Opening
        Start-Sleep -Seconds 2
        Wait-GameClosed { @(Get-AppProcesses $appDir).Count -gt 0 } {
            foreach ($p in @(Get-AppProcesses $appDir)) { try { [void]$p.CloseMainWindow() } catch { } }
            Start-Sleep -Milliseconds 2500
            foreach ($p in @(Get-AppProcesses $appDir)) { try { Stop-Process -Id $p.Id -Force } catch { } }
        }
        Write-BgLog 'closed'
        exit 0
    }

    # ---- a browser game ----------------------------------------------------
    $target = Get-WebTarget $info $Game
    if ($target -eq '') { Write-BgLog ("nothing to open in " + (Split-Path -Leaf $Game) + " (needs url = https://... or file = ...)"); Close-Opening; exit 1 }
    $exe = Find-AppBrowser
    if ($exe -eq '') { Write-BgLog 'no Edge or Chrome on this computer'; Close-Opening; exit 1 }

    # One memory folder per browser: Chrome and Edge cannot share one safely.
    $profileDir = Join-Path (Join-Path $Ws 'People\browser') $(if ((Split-Path -Leaf $exe) -ieq 'chrome.exe') { 'chrome' } else { 'edge' })
    if (-not (Test-Path -LiteralPath $profileDir)) { New-Item -ItemType Directory -Path $profileDir -Force | Out-Null }
    $args2 = @(
        ('--user-data-dir="' + $profileDir + '"'),
        ('--app="' + $target + '"'),
        '--start-maximized',
        '--no-first-run', '--no-default-browser-check',
        '--autoplay-policy=no-user-gesture-required',
        '--disable-features=msEdgeSidebarV2,msUndersideButton,TranslateUI',
        '--allow-file-access-from-files'
    )
    $zoom = [string]$info['zoom']
    if ($zoom -match '^\d(\.\d{1,2})?$') { $args2 += ('--force-device-scale-factor=' + $zoom) }
    Write-BgLog ("open " + (Split-Path -Leaf $Game) + " -> " + $target + " in " + (Split-Path -Leaf $exe))
    [void](Start-Process -FilePath $exe -ArgumentList $args2 -PassThru)

    # Wait (up to 40 s) for the page to show a title, then full screen.
    $win = $null
    for ($i = 0; $i -lt 80; $i++) {
        Wait-Pump 500
        $win = Find-GameWindow $profileDir
        if ($null -ne $win) {
            $t = [string]$win.MainWindowTitle
            if ($t -ne '' -and $t -notmatch '^(about:blank|data:|https?://)' ) { break }
        }
    }
    Close-Opening
    if ($null -ne $win) {
        try {
            [void][RBWin]::SetForegroundWindow($win.MainWindowHandle)
            Start-Sleep -Milliseconds 300
            if ([string]$win.MainWindowTitle -notmatch '(?i)welcome|sign in|get started|set up') { [RBWin]::Tap(0x7A) }   # F11
            else { Write-BgLog ('browser asked something first: ' + $win.MainWindowTitle + ' - left in a window') }
        } catch { }
    }
    else { Write-BgLog 'no game window showed within 40 s' }

    Wait-GameClosed { @(Get-ProfileProcesses $profileDir).Count -gt 0 } { Close-ProfileBrowser $profileDir }
    Write-BgLog 'closed'
}
catch { Write-BgLog ("stopped: " + $_.Exception.Message); Close-Opening }
finally { try { [RBPad]::Quit() } catch { } }
