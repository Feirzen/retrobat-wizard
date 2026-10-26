<#
    PadShortcut.ps1 - turns the SELECT + START controller shortcut on or off
    for THIS computer.

    FUNCTIONS ONLY. Dot-source it; nothing happens until something calls
    Install-PadShortcut, Remove-PadShortcut or Update-PadShortcut.

    ON means, all of it on the computer and none of it on the drive:
      %LOCALAPPDATA%\RetroBatDrive\pad\
          PadWatch.ps1   the helper       (copied from wizard\PadWatch.ps1)
          PadInput.ps1   the pad reader   (copied from scripts\PadInput.ps1)
          SDL2.dll       RetroBat's controller library, copied from
                         emulationstation\SDL2.dll so the helper never holds
                         a file open on the drive
          enabled.txt    the switch. Delete it and the helper stops.
      Startup folder\RetroBat Controller Shortcut.vbs
                         starts the helper, hidden, every time Windows signs
                         in. It holds no drive letter - the helper finds the
                         drive by itself each time.

    OFF stops the helper and deletes all of the above.

    It is per computer on purpose, like the Start Menu buttons: plugging the
    drive into a friend's computer does not start anything there unless they
    say yes during SETUP RETROBAT or flick the switch.

    IT CAN NEVER BREAK ANYTHING. Every entry point is wrapped and logged; the
    worst outcome is that the shortcut is not there.

    PURE ASCII on purpose.
#>

$script:PadStartupName = 'RetroBat Controller Shortcut.vbs'

function Get-PadFolder {
    $base = $env:LOCALAPPDATA
    if ([string]::IsNullOrWhiteSpace($base)) { return '' }
    return (Join-Path $base 'RetroBatDrive\pad')
}

function Get-PadStartupFile {
    try {
        $s = [Environment]::GetFolderPath('Startup')
        if ([string]::IsNullOrWhiteSpace($s)) { return '' }
        return (Join-Path $s $script:PadStartupName)
    } catch { return '' }
}

# Is it on for this computer?
function Test-PadShortcutOn {
    $f = Get-PadFolder
    if ($f -eq '') { return $false }
    return ((Test-Path -LiteralPath (Join-Path $f 'enabled.txt')) -and
            (Test-Path -LiteralPath (Join-Path $f 'PadWatch.ps1')))
}

# Stops every running copy of the helper. It is a hidden PowerShell, found by
# the script path in its command line.
function Stop-PadWatch {
    try {
        foreach ($p in @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -Property ProcessId, CommandLine)) {
            if ([string]$p.CommandLine -like '*RetroBatDrive\pad\PadWatch.ps1*') {
                try { Stop-Process -Id ([int]$p.ProcessId) -Force } catch { }
            }
        }
        Start-Sleep -Milliseconds 400
    } catch { }
}

function Start-PadWatch {
    $f = Get-PadFolder
    $vbs = Get-PadStartupFile
    if ($vbs -eq '' -or -not (Test-Path -LiteralPath $vbs)) { return }
    try {
        Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\wscript.exe') -ArgumentList @('//nologo', ('"' + $vbs + '"'))
    } catch { }
}

function Install-PadShortcut {
    [CmdletBinding()]
    param([string]$Root, [scriptblock]$Logger = { param($m) })

    try {
        $ws  = Join-Path $Root '_Wizard'
        $src = @{
            'PadWatch.ps1' = (Join-Path $ws 'Program\wizard\PadWatch.ps1')
            'PadInput.ps1' = (Join-Path $ws 'Program\scripts\PadInput.ps1')
            'SDL2.dll'     = (Join-Path $Root 'emulationstation\SDL2.dll')
        }
        foreach ($k in $src.Keys) {
            if (-not (Test-Path -LiteralPath $src[$k])) { & $Logger ("pad shortcut: {0} is missing, not turning it on" -f $src[$k]); return $false }
        }
        $f = Get-PadFolder
        if ($f -eq '') { & $Logger 'pad shortcut: no LOCALAPPDATA'; return $false }
        [void](New-Item -ItemType Directory -Force -Path $f)

        # The helper has SDL2.dll open, so it has to stop before a fresh copy
        # can go over it.
        Stop-PadWatch
        foreach ($k in $src.Keys) { Copy-Item -LiteralPath $src[$k] -Destination (Join-Path $f $k) -Force }
        [System.IO.File]::WriteAllText((Join-Path $f 'enabled.txt'), "on`r`nDelete this file to switch the controller shortcut off.`r`n")
        [System.IO.File]::WriteAllText((Join-Path $f 'lastroot.txt'), $Root)

        # The starter in the Startup folder. Window style 0 = no console ever,
        # the same trick as Launch-Wizard.vbs. The path is to the COMPUTER's
        # copy, so there is no drive letter in it.
        $ps  = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $scr = Join-Path $f 'PadWatch.ps1'
        $q = '""'
        $vbsText = @(
            "' Starts the RetroBat controller shortcut (SELECT + START opens the Setup Wizard).",
            "' Written by the Setup Wizard. Turn it off on the wizard's Features tab.",
            ('CreateObject("WScript.Shell").Run "' + $q + $ps + $q + ' -NoProfile -ExecutionPolicy Bypass -Command ' + $q + "& '" + $scr + "'" + $q + '", 0, False')
        ) -join "`r`n"
        $startup = Get-PadStartupFile
        if ($startup -eq '') { & $Logger 'pad shortcut: no Startup folder'; return $false }
        [System.IO.File]::WriteAllText($startup, $vbsText + "`r`n", (New-Object System.Text.ASCIIEncoding))

        Start-PadWatch
        & $Logger 'pad shortcut: on for this computer'
        return $true
    }
    catch { & $Logger ("pad shortcut: could not turn on - {0}" -f $_.Exception.Message); return $false }
}

function Remove-PadShortcut {
    [CmdletBinding()]
    param([scriptblock]$Logger = { param($m) })
    try {
        $f = Get-PadFolder
        if ($f -ne '' -and (Test-Path -LiteralPath (Join-Path $f 'enabled.txt'))) {
            Remove-Item -LiteralPath (Join-Path $f 'enabled.txt') -Force
        }
        Stop-PadWatch
        $startup = Get-PadStartupFile
        if ($startup -ne '' -and (Test-Path -LiteralPath $startup)) { Remove-Item -LiteralPath $startup -Force }
        if ($f -ne '' -and (Test-Path -LiteralPath $f)) { Remove-Item -LiteralPath $f -Recurse -Force -ErrorAction SilentlyContinue }
        & $Logger 'pad shortcut: off for this computer'
        return $true
    }
    catch { & $Logger ("pad shortcut: could not turn off - {0}" -f $_.Exception.Message); return $false }
}

# Called every time the wizard opens. If the shortcut is on here and the
# drive has a newer helper than the computer, copy the new one over. If it is
# on but the helper is not running (it was stopped, or crashed), start it.
function Update-PadShortcut {
    [CmdletBinding()]
    param([string]$Root, [scriptblock]$Logger = { param($m) })
    try {
        if (-not (Test-PadShortcutOn)) { return }
        $f = Get-PadFolder
        $stale = $false
        foreach ($pair in @(@('Program\wizard\PadWatch.ps1', 'PadWatch.ps1'), @('Program\scripts\PadInput.ps1', 'PadInput.ps1'))) {
            $a = Join-Path (Join-Path $Root '_Wizard') $pair[0]
            $b = Join-Path $f $pair[1]
            if (-not (Test-Path -LiteralPath $a)) { continue }
            if (-not (Test-Path -LiteralPath $b)) { $stale = $true; continue }
            if ((Get-FileHash -LiteralPath $a).Hash -ne (Get-FileHash -LiteralPath $b).Hash) { $stale = $true }
        }
        if ($stale) {
            & $Logger 'pad shortcut: the drive has a newer helper, updating this computer'
            [void](Install-PadShortcut -Root $Root -Logger $Logger)
            return
        }
        $running = $false
        foreach ($p in @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -Property CommandLine)) {
            if ([string]$p.CommandLine -like '*RetroBatDrive\pad\PadWatch.ps1*') { $running = $true }
        }
        if (-not $running) { & $Logger 'pad shortcut: helper was not running, starting it'; Start-PadWatch }
    }
    catch { & $Logger ("pad shortcut: update check failed - {0}" -f $_.Exception.Message) }
}
