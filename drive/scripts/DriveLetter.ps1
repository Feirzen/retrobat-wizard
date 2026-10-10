<#
    DriveLetter.ps1
    ---------------------------------------------------------------------------
    Claims R: for this drive on the computer it is plugged into. FUNCTIONS
    ONLY - dot-source it.

    READ THIS BEFORE USING IT ANYWHERE.

    NOTHING ON THIS DRIVE MAY EVER DEPEND ON BEING R:. That rule has not
    changed and this file does not weaken it. Every script here still works
    out where it is from its own location, and still would if the drive came
    up as Q: on a stranger's laptop. This is a convenience and a safety net
    for the handful of things that cannot avoid a letter - a stray path left
    in an emulator's own config, a shortcut somebody made by hand - not a
    foundation to build on.

    WHY R:. High enough that no computer hands it out on its own. C: is
    always the system disk, D: and E: are the usual second drive and optical
    drive, and USB sticks climb from F: upwards. Nothing reaches R: by
    accident.

    A DRIVE LETTER IS NOT STORED ON THE DRIVE. Windows decides it per
    computer and remembers it in that computer's own registry. So there is no
    such thing as "this drive is R: everywhere". What there is: R: claimed
    once per computer, which Windows then remembers for this drive forever
    after on that computer. That is why this is offered on every new machine
    rather than done once and assumed.

    IT NEVER TAKES A LETTER SOMEBODY ELSE IS USING. If R: is occupied it
    says so and changes nothing. Quietly moving a stranger's network drive
    would be exactly the kind of surprise this project exists to avoid.

    IT NEEDS ADMINISTRATOR. Windows does not let an ordinary program reassign
    drive letters. Since 2026-09-25 Invoke-DriveLetterElevated asks Windows
    for permission itself (the usual "allow this app to make changes" box),
    so nobody has to know about right-click, Run as administrator. It runs a
    copy of this file from the computer's temp folder, so nothing on the
    drive is held open while its letter moves. Say No to the box and nothing
    happens.

    IF YOU EVER MAKE A BACKUP COPY OF THIS DRIVE: the copy cannot also be R:
    while the original is plugged in. Two volumes cannot share a letter.
    Give the backup a different one and never run this on it.

    RULES HONOURED HERE:
      - no function throws; a failure returns a result object saying why
      - Windows PowerShell 5.1 only
      - pure ASCII, no byte-order mark
#>

Set-StrictMode -Off

# Remembered at load time, for Invoke-DriveLetterElevated, because
# $PSScriptRoot inside a function is that of whoever dot-sourced this file.
$script:DriveLetterLibPath = $MyInvocation.MyCommand.Path

$script:PreferredDriveLetter = 'R'

# Are we running with administrator rights?
function Test-IsAdministrator {
    try {
        $id = [Security.Principal.WindowsIdentity]::GetCurrent()
        $pr = New-Object Security.Principal.WindowsPrincipal($id)
        return $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch { return $false }
}

# The letter this drive currently has, as a single character, or ''.
function Get-CurrentDriveLetter {
    param([string]$Root)
    try {
        if ([string]::IsNullOrWhiteSpace($Root)) { return '' }
        $q = Split-Path -Path $Root -Qualifier -ErrorAction SilentlyContinue
        if ($q -and $q.Length -ge 1) { return $q.Substring(0, 1).ToUpper() }
    }
    catch { }
    return ''
}

# Is a letter free on this computer? A letter is only free if nothing at all
# answers to it - no disk, no network drive, no mapped folder.
function Test-DriveLetterFree {
    param([string]$Letter)
    try {
        $L = $Letter.Substring(0, 1).ToUpper()
        if (Test-Path -LiteralPath ($L + ':\')) { return $false }
        $used = @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue | ForEach-Object { $_.Name.ToUpper() })
        if ($used -contains $L) { return $false }
        return $true
    }
    catch { return $false }
}

# What is sitting on a letter, in words, so a refusal can say what it found.
function Get-DriveLetterOccupant {
    param([string]$Letter)
    try {
        $L = $Letter.Substring(0, 1).ToUpper()
        $v = Get-CimInstance -ClassName Win32_LogicalDisk -Filter ("DeviceID='" + $L + ":'") -ErrorAction SilentlyContinue
        if ($null -eq $v) { return 'something' }
        $name = [string]$v.VolumeName
        switch ([int]$v.DriveType) {
            2 { if ($name -ne '') { return "a removable drive called '$name'" } else { return 'a removable drive' } }
            3 { if ($name -ne '') { return "a hard drive called '$name'" } else { return 'a hard drive' } }
            4 { return ('a network drive (' + [string]$v.ProviderName + ')') }
            5 { return 'a CD or DVD drive' }
        }
        if ($name -ne '') { return "a drive called '$name'" }
        return 'something'
    }
    catch { return 'something' }
}

# ---------------------------------------------------------------------------
#  Claim R: for this drive on this computer.
#
#  Returns an object: Changed, Ok, Message, From, To.
#  Ok means "nothing is wrong", which includes the case where it was already
#  R: and nothing needed doing. Changed means a letter actually moved.
# ---------------------------------------------------------------------------
function Set-PreferredDriveLetter {
    param([string]$Root, [string]$Letter = '')

    if ($Letter -eq '') { $Letter = $script:PreferredDriveLetter }
    $L = $Letter.Substring(0, 1).ToUpper()

    $result = [pscustomobject]@{
        Changed = $false
        Ok      = $false
        Message = ''
        From    = ''
        To      = $L
    }

    try {
        $current = Get-CurrentDriveLetter -Root $Root
        $result.From = $current

        if ($current -eq '') {
            $result.Message = 'This drive does not have a letter of its own, so there is nothing to change. That usually means RetroBat is in a folder rather than on a drive of its own.'
            return $result
        }

        if ($current -eq $L) {
            $result.Ok = $true
            $result.Message = ('This drive is already ' + $L + ': on this computer. Nothing to do.')
            return $result
        }

        if (-not (Test-DriveLetterFree $L)) {
            $what = Get-DriveLetterOccupant $L
            $result.Message = ($L + ': is already taken on this computer by ' + $what + '. Nothing was changed - taking somebody else''s drive letter would break whatever is using it. The drive works fine as ' + $current + ':.')
            return $result
        }

        if (-not (Test-IsAdministrator)) {
            $result.Message = ('Windows only lets an administrator change drive letters. Nothing was changed, and the drive works fine as ' + $current + ':.')
            return $result
        }

        $done = $false

        # First choice: Windows' own storage commands. Present on Windows 8
        # and newer, which is everything this drive will ever meet.
        try {
            $part = Get-Partition -DriveLetter $current -ErrorAction Stop
            Set-Partition -InputObject $part -NewDriveLetter $L -ErrorAction Stop
            $done = $true
        }
        catch { $done = $false }

        # Fallback: the old mountvol route, by the volume's own permanent id.
        if (-not $done) {
            try {
                $vol = Get-CimInstance -ClassName Win32_Volume -Filter ("DriveLetter='" + $current + ":'") -ErrorAction Stop
                if ($null -ne $vol -and [string]$vol.DeviceID -ne '') {
                    & mountvol.exe ($current + ':') /D | Out-Null
                    & mountvol.exe ($L + ':') ([string]$vol.DeviceID) | Out-Null
                    Start-Sleep -Milliseconds 700
                    if (Test-Path -LiteralPath ($L + ':\')) { $done = $true }
                }
            }
            catch { $done = $false }
        }

        if (-not $done) {
            $result.Message = ('Windows refused to move the drive from ' + $current + ': to ' + $L + ':. Nothing was changed and the drive still works as ' + $current + ':. This usually means a file on the drive is open in another program.')
            return $result
        }

        $result.Changed = $true
        $result.Ok = $true
        $result.Message = ('This drive is now ' + $L + ': on this computer, and Windows will give it that letter from now on. Anything you had open from ' + $current + ': should be closed and opened again.')
        return $result
    }
    catch {
        $result.Message = 'Could not change the drive letter: ' + $_.Exception.Message
        return $result
    }
}

# A plain-English description of where things stand, for a window or a
# console to print without having to work any of it out itself.
function Get-DriveLetterStatus {
    param([string]$Root, [string]$Letter = '')

    if ($Letter -eq '') { $Letter = $script:PreferredDriveLetter }
    $L = $Letter.Substring(0, 1).ToUpper()
    $current = Get-CurrentDriveLetter -Root $Root

    $state = 'other'
    $line  = ''

    if ($current -eq '') {
        $state = 'none'
        $line  = 'This RetroBat is not on a drive of its own, so drive letters do not apply.'
    }
    elseif ($current -eq $L) {
        $state = 'already'
        $line  = ('This drive is ' + $L + ': on this computer.')
    }
    elseif (-not (Test-DriveLetterFree $L)) {
        $state = 'taken'
        $line  = ($L + ': is taken by ' + (Get-DriveLetterOccupant $L) + ', so this drive stays as ' + $current + ':. Everything still works.')
    }
    elseif (-not (Test-IsAdministrator)) {
        $state = 'needsadmin'
        $line  = ('This drive is ' + $current + ':. ' + $L + ': is free, so it can be moved. Windows will ask for permission first.')
    }
    else {
        $state = 'canchange'
        $line  = ('This drive is ' + $current + ':. ' + $L + ': is free, so it can be moved.')
    }

    return [pscustomobject]@{
        State   = $state
        Current = $current
        Wanted  = $L
        Line    = $line
    }
}

# ---------------------------------------------------------------------------
#  Claim R: WITHOUT the wizard having been started as an administrator.
#
#  Windows shows its own permission box. Yes runs Set-PreferredDriveLetter
#  in a separate, elevated PowerShell; No changes nothing. Returns the same
#  kind of object as Set-PreferredDriveLetter.
#
#  The elevated copy runs from %TEMP%, not from the drive, so the drive is
#  not busy while its letter changes, and it hands its answer back through a
#  small JSON file because an elevated process cannot talk to this one any
#  other way.
# ---------------------------------------------------------------------------
function Invoke-DriveLetterElevated {
    param([string]$Root, [string]$Letter = '')

    if ($Letter -eq '') { $Letter = $script:PreferredDriveLetter }
    $L = $Letter.Substring(0, 1).ToUpper()

    if (Test-IsAdministrator) { return (Set-PreferredDriveLetter -Root $Root -Letter $L) }

    $result = [pscustomobject]@{
        Changed = $false; Ok = $false; Message = ''
        From = (Get-CurrentDriveLetter -Root $Root); To = $L
    }

    try {
        $me = Join-Path $PSScriptRoot 'DriveLetter.ps1'
        if (-not (Test-Path -LiteralPath $me)) { $me = $script:DriveLetterLibPath }
        $work = Join-Path ([System.IO.Path]::GetTempPath()) ('RetroBatDriveLetter_' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $work -Force | Out-Null
        Copy-Item -LiteralPath $me -Destination (Join-Path $work 'DriveLetter.ps1') -Force

        $out    = Join-Path $work 'result.json'
        $runner = Join-Path $work 'run.ps1'
        $code = @'
param([string]$Root, [string]$Letter, [string]$Out)
. (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'DriveLetter.ps1')
$r = Set-PreferredDriveLetter -Root $Root -Letter $Letter
[System.IO.File]::WriteAllText($Out, ($r | ConvertTo-Json -Compress))
'@
        [System.IO.File]::WriteAllText($runner, $code)

        $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $rootArg = $Root.TrimEnd('\')
        $argLine = ('-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}" -Root "{1}" -Letter {2} -Out "{3}"' -f $runner, $rootArg, $L, $out)

        try {
            $p = Start-Process -FilePath $ps -ArgumentList $argLine -Verb RunAs -WindowStyle Hidden -WorkingDirectory $work -PassThru -ErrorAction Stop
            [void]$p.WaitForExit(120000)
        }
        catch {
            $result.Message = ('Windows'' permission box was closed or answered No, so nothing was changed. The drive works fine as ' + $result.From + ':.')
            return $result
        }

        if (Test-Path -LiteralPath $out) {
            $j = [System.IO.File]::ReadAllText($out) | ConvertFrom-Json
            $result.Changed = [bool]$j.Changed
            $result.Ok      = [bool]$j.Ok
            $result.Message = [string]$j.Message
            if ([string]$j.From -ne '') { $result.From = [string]$j.From }
        }
        else {
            $result.Message = 'The permission was given, but the change did not report back. Check whether the drive letter changed; if not, nothing happened.'
        }
        try { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue } catch { }
        return $result
    }
    catch {
        $result.Message = 'Could not ask Windows for permission: ' + $_.Exception.Message
        return $result
    }
}
