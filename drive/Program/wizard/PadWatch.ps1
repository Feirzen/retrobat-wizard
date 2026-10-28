<#
    PadWatch.ps1 - opens the Setup Wizard when SELECT + START is pressed.

    THIS COPY RUNS FROM THE COMPUTER, NOT THE DRIVE. The master lives on the
    drive at _Wizard\Program\wizard\PadWatch.ps1. Turning the controller
    shortcut on (SETUP RETROBAT asks, and there is a switch on the wizard's
    Features tab) copies it, PadInput.ps1 and SDL2.dll into
        %LOCALAPPDATA%\RetroBatDrive\pad\
    and puts a small starter in the Windows Startup folder, so it runs
    quietly from sign-in onwards. Nothing in it is held open on the drive,
    so the drive still ejects normally.

    WHAT IT DOES. Every 60 ms it reads the controllers. When SELECT and
    START are both held for a third of a second, on any pad, it:
      1. finds the drive, whatever letter it has today (it looks for
         <any folder>\_Wizard\Program\wizard\Launch-Wizard.vbs at the top
         of every drive)
      2. refuses if ANYTHING from the drive's RetroBat folder is running -
         a game, an emulator, or RetroBat's own menu. SELECT + START is
         also RetroBat's "quit the game" button, so this is what keeps the
         two from ever fighting. Also refuses while Steam is open on screen
         (its window or Big Picture) or a Steam game is running.
      3. refuses if the wizard is already open, or closed itself with
         SELECT + START in the last few seconds
      4. otherwise opens the wizard full screen, ready for the controller.
    Then it waits for both buttons to be let go before it will fire again.

    No drive plugged in simply means nothing happens.

    TO TURN IT OFF: the Features tab switch, or delete enabled.txt next to
    this file - it notices within a second and stops.

    PURE ASCII on purpose.
#>

$ErrorActionPreference = 'Stop'
$Here    = Split-Path -Parent $MyInvocation.MyCommand.Path
$LogPath = Join-Path $Here 'padwatch.log'
$Marker  = Join-Path $Here 'enabled.txt'
$ClosedStamp = Join-Path $Here 'wizard-closed.txt'

function Log([string]$msg) {
    try {
        if ((Test-Path -LiteralPath $LogPath) -and ((Get-Item -LiteralPath $LogPath).Length -gt 262144)) {
            Move-Item -LiteralPath $LogPath -Destination ($LogPath + '.old') -Force
        }
        $line = "{0}  {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg
        [System.IO.File]::AppendAllText($LogPath, $line + [Environment]::NewLine)
    } catch { }
}

# One copy at a time, however many times it gets started.
$created = $false
$mutex = [System.Threading.Mutex]::new($true, 'Local\RetroBatDrivePadWatch', [ref]$created)
if (-not $created) { exit 0 }

try {
    . (Join-Path $Here 'PadInput.ps1')
    if (-not [RBPad]::Init((Join-Path $Here 'SDL2.dll'))) {
        Log ("could not start the controller library: " + [RBPad]::LastError)
        exit 1
    }
    [RBPad]::Pump = $true
    Log ("watching for SELECT + START, {0} controller(s) connected" -f [RBPad]::Count)
    $lastCount = [RBPad]::Count

    $lastRootFile = Join-Path $Here 'lastroot.txt'

    function Find-RetroBatRoot {
        $cands = @()
        try { if (Test-Path -LiteralPath $lastRootFile) { $cands += ([System.IO.File]::ReadAllText($lastRootFile)).Trim() } } catch { }
        foreach ($d in [System.IO.DriveInfo]::GetDrives()) {
            try {
                if (-not $d.IsReady) { continue }
                if ($d.DriveType -ne 'Fixed' -and $d.DriveType -ne 'Removable') { continue }
                foreach ($dir in [System.IO.Directory]::GetDirectories($d.RootDirectory.FullName)) { $cands += $dir }
            } catch { }
        }
        foreach ($c in $cands) {
            if ([string]::IsNullOrWhiteSpace($c)) { continue }
            $vbs = Join-Path $c '_Wizard\Program\wizard\Launch-Wizard.vbs'
            if (Test-Path -LiteralPath $vbs) {
                try { [System.IO.File]::WriteAllText($lastRootFile, $c) } catch { }
                return $c
            }
        }
        return $null
    }

    function Invoke-Chord {
        # 3. the wizard just closed itself with this same chord
        try {
            if (Test-Path -LiteralPath $ClosedStamp) {
                $age = ((Get-Date) - (Get-Item -LiteralPath $ClosedStamp).LastWriteTime).TotalSeconds
                if ($age -lt 4) { Log 'ignored: the wizard just closed with SELECT + START'; return }
            }
        } catch { }

        $root = Find-RetroBatRoot
        if ($null -eq $root) { Log 'ignored: the RetroBat drive is not plugged in'; return }

        $prefix = $root.TrimEnd('\') + '\'
        $procs = @()
        try { $procs = @(Get-CimInstance Win32_Process -Property Name, ExecutablePath, CommandLine) } catch { }

        # 2. anything from the RetroBat folder running = a game or its menu
        foreach ($p in $procs) {
            $exe = [string]$p.ExecutablePath
            if ($exe -ne '' -and $exe.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
                Log ("ignored: {0} is running" -f $p.Name); return
            }
        }
        # 2b. Steam. Blocked while Steam is actually OPEN - its window or Big
        #     Picture on screen - or while a Steam game is running. Steam
        #     sitting quietly in the system tray does not count, or the
        #     shortcut would never work on a computer that starts Steam with
        #     Windows. (A process only has a MainWindowHandle when it has a
        #     visible window.)
        foreach ($p in $procs) {
            $exe = [string]$p.ExecutablePath
            if ($exe -like '*\steamapps\common\*') { Log ("ignored: a Steam game ({0}) is running" -f $p.Name); return }
        }
        try {
            $sw = @(Get-Process -Name 'steam', 'steamwebhelper' -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero })
            if ($sw.Count -gt 0) { Log 'ignored: Steam is open'; return }
        } catch { }

        # 3. the wizard is already open
        foreach ($p in $procs) {
            if ([string]$p.CommandLine -like '*SetupWizard.ps1*') { Log 'ignored: the wizard is already open'; return }
        }

        $vbs = Join-Path $root '_Wizard\Program\wizard\Launch-Wizard.vbs'
        $ws  = Join-Path $env:SystemRoot 'System32\wscript.exe'
        Log ("opening the wizard from {0}" -f $root)
        Start-Process -FilePath $ws -ArgumentList @('//nologo', ('"' + $vbs + '"'), '-pad')
    }

    $BACK  = 16
    $START = 64
    $armed = $true
    $heldSince = $null
    $tick = 0

    while ($true) {
        Start-Sleep -Milliseconds 60
        $tick++
        if (($tick % 16) -eq 0 -and -not (Test-Path -LiteralPath $Marker)) { Log 'switched off - stopping'; break }

        $s = [RBPad]::Poll()
        if (($tick % 50) -eq 0 -and [RBPad]::Count -ne $lastCount) {
            $lastCount = [RBPad]::Count
            Log ("{0} controller(s) connected" -f $lastCount)
        }
        $both = (($s -band $BACK) -ne 0) -and (($s -band $START) -ne 0)
        $none = (($s -band ($BACK -bor $START)) -eq 0)

        if ($none) { $armed = $true; $heldSince = $null; continue }
        if (-not $both) { $heldSince = $null; continue }
        if (-not $armed) { continue }

        if ($null -eq $heldSince) { $heldSince = [DateTime]::UtcNow; continue }
        if (([DateTime]::UtcNow - $heldSince).TotalMilliseconds -ge 350) {
            $armed = $false
            $heldSince = $null
            try { Invoke-Chord } catch { Log ("error: " + $_.Exception.Message) }
        }
    }
}
catch { Log ("stopped by an error: " + $_.Exception.Message) }
finally {
    try { [RBPad]::Quit() } catch { }
    try { $mutex.ReleaseMutex() } catch { }
}
