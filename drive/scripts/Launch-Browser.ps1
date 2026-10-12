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
    _ClaudeWorkspace\browser-profile\<chrome or edge>\, so it travels with
    the drive and never mixes with anybody's own browser. Never shipped.

    SELECT + START closes the game, like every other game on the drive. It
    is watched here, because RetroBat's own close button only works for
    games it starts itself.

    Log: _ClaudeWorkspace\wizard\browser-games.log.
    ASCII ONLY, Windows PowerShell 5.1. $PSScriptRoot is resolved in the body.
#>
param([string]$Game = '')
$ErrorActionPreference = 'Stop'
$Ws   = Split-Path $PSScriptRoot -Parent
$Root = Split-Path $Ws -Parent
$log  = Join-Path $Ws 'wizard\browser-games.log'
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

try {
    if ($Game -eq '' -and $env:RB_GAME) { $Game = $env:RB_GAME }
    if ($Game -eq '' -or -not (Test-Path -LiteralPath $Game)) { Write-BgLog ("no game file: " + $Game); exit 1 }
    $info = Read-WebFile $Game
    $target = Get-WebTarget $info $Game
    if ($target -eq '') { Write-BgLog ("nothing to open in " + (Split-Path -Leaf $Game) + " (needs url = https://... or file = ...)"); exit 1 }
    $exe = Find-AppBrowser
    if ($exe -eq '') { Write-BgLog 'no Edge or Chrome on this computer'; exit 1 }

    # One memory folder per browser: Chrome and Edge cannot share one safely.
    $profileDir = Join-Path (Join-Path $Ws 'browser-profile') $(if ((Split-Path -Leaf $exe) -ieq 'chrome.exe') { 'chrome' } else { 'edge' })
    if (-not (Test-Path -LiteralPath $profileDir)) { New-Item -ItemType Directory -Path $profileDir -Force | Out-Null }
    $args2 = @(
        ('--user-data-dir="' + $profileDir + '"'),
        ('--app="' + $target + '"'),
        '--start-fullscreen',
        '--no-first-run', '--no-default-browser-check',
        '--autoplay-policy=no-user-gesture-required',
        '--disable-features=msEdgeSidebarV2,msUndersideButton,TranslateUI',
        '--allow-file-access-from-files'
    )
    $zoom = [string]$info['zoom']
    if ($zoom -match '^\d(\.\d{1,2})?$') { $args2 += ('--force-device-scale-factor=' + $zoom) }
    Write-BgLog ("open " + (Split-Path -Leaf $Game) + " -> " + $target + " in " + (Split-Path -Leaf $exe))
    [void](Start-Process -FilePath $exe -ArgumentList $args2 -PassThru)

    # Watch for SELECT + START while the game is open.
    $padOk = $false
    try {
        . (Join-Path $PSScriptRoot 'PadInput.ps1')
        [RBPad]::Pump = $true
        $padOk = [RBPad]::Init((Join-Path $Root 'emulationstation\SDL2.dll'))
    } catch { }
    $B = $script:PadBit
    Start-Sleep -Seconds 3
    $quiet = 0; $n = 0
    while ($true) {
        Start-Sleep -Milliseconds 50
        if ($padOk) {
            $s = [RBPad]::Poll()
            if ((($s -band $B.Back) -ne 0) -and (($s -band $B.Start) -ne 0)) {
                Write-BgLog 'closed with SELECT + START'
                Close-ProfileBrowser $profileDir
                break
            }
        }
        $n++
        if ($n % 40 -eq 0) {
            # every two seconds: is the game window still open?
            if (@(Get-ProfileProcesses $profileDir).Count -eq 0) { $quiet++ } else { $quiet = 0 }
            if ($quiet -ge 2) { break }
        }
    }
    Write-BgLog 'closed'
}
catch { Write-BgLog ("stopped: " + $_.Exception.Message) }
finally { try { [RBPad]::Quit() } catch { } }
