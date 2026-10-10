<#
    Migrations.ps1 - one-time changes to the SHAPE of the drive.

    FUNCTIONS ONLY. Dot-source it, it never does anything by itself:

        . (Join-Path $PSScriptRoot 'Migrations.ps1')
        $done = Invoke-DriveMigrations -Ws $Ws

    WHY THIS EXISTS
    ---------------
    Sometimes a folder or a button has to change its name, and every drive
    that already exists has the old name. Code that looks only for the new
    name would quietly find nothing. So each rename lives here once, and two
    things run this list:

        scripts\UpdateEngine.ps1   before it installs an update, with a
                                   journal, so "Go back one update" can put
                                   every move back the way it was
        wizard\SetupWizard.ps1     at every start, as a safety net for a drive
                                   whose files were copied over by hand

    Every migration is SAFE TO RUN AGAIN. Once it has happened there is
    nothing left to do and it says nothing.

    NOTHING IS EVER DELETED. A file that has nowhere to go is moved into
    _ClaudeWorkspace\_SAFE TO DELETE\, which is the rule for this whole drive.

    THE JOURNAL. When a journal path is given, every move is written to it as
    one line, "from<TAB>to", both relative to _ClaudeWorkspace, IN THE ORDER
    THEY HAPPENED. Undo-DriveMigrations walks it backwards. A move whose way
    back is blocked (something new already sits where the old file was) is
    skipped and logged rather than forced.

    THE MIGRATIONS
    --------------
    2026-10-10  profiles\ -> machine\
                "Profile" now means the PERSON using the drive. The old
                profiles\ folder was always about the COMPUTER, and its tab is
                now called Machine. When both folders exist (an update put new
                tier files into machine\ first) the two are merged: anything
                machine\ does not have moves across, and anything it already
                has keeps the new copy while the old one goes to SAFE TO
                DELETE.
    2026-10-10  Maintenance Steps\Show My Profile.bat -> SAFE TO DELETE
                Replaced by Show My Machine.bat, which ships with the update.

    ASCII ONLY, Windows PowerShell 5.1. Every root is a parameter, so the test
    harness can run all of this against a fake drive.
#>

function Join-MigPath([string]$Base, [string]$Rel) {
    $p = $Base
    foreach ($seg in ($Rel -split '[\\/]')) {
        if ($seg -ne '') { $p = [System.IO.Path]::Combine($p, $seg) }
    }
    return $p
}

function Write-MigLine($Logger, [string]$Msg) {
    if ($null -ne $Logger) { try { & $Logger $Msg } catch { } }
}

# Where something with nowhere to go ends up. A name already taken there gets
# a number added, so two runs can never collide.
function Get-MigSafePath([string]$Ws, [string]$Bucket, [string]$Rel) {
    $safeRoot = Join-MigPath (Join-MigPath $Ws '_SAFE TO DELETE') $Bucket
    $dest = Join-MigPath $safeRoot $Rel
    $n = 2
    $try = $dest
    while (Test-Path -LiteralPath $try) { $try = "$dest ($n)"; $n++ }
    return $try
}

# Moves one file or folder, making the parent folders it needs, and writes
# the move to the journal. Both paths are relative to $Ws.
function Move-MigItem([string]$Ws, [string]$FromRel, [string]$ToRel, [string]$Journal) {
    $from = Join-MigPath $Ws $FromRel
    $to   = Join-MigPath $Ws $ToRel
    $parent = Split-Path -Parent $to
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        [void](New-Item -ItemType Directory -Path $parent -Force)
    }
    Move-Item -LiteralPath $from -Destination $to
    if ($Journal) {
        $jd = Split-Path -Parent $Journal
        if ($jd -and -not (Test-Path -LiteralPath $jd)) { [void](New-Item -ItemType Directory -Path $jd -Force) }
        [System.IO.File]::AppendAllText($Journal, ($FromRel + "`t" + $ToRel + "`r`n"))
    }
}

# The relative path of $Full under $Base, with backslashes. .NET Framework has
# no GetRelativePath, so this is done by hand.
function Get-MigRel([string]$Base, [string]$Full) {
    $b = [System.IO.Path]::GetFullPath($Base).TrimEnd('\', '/')
    $f = [System.IO.Path]::GetFullPath($Full)
    return ($f.Substring($b.Length).TrimStart('\', '/') -replace '/', '\')
}

# Merges folder $FromRel into folder $ToRel. Anything the destination lacks
# moves across. Anything it already has stays, and the old copy goes to SAFE
# TO DELETE, so nothing is lost and the newer file wins.
function Merge-MigFolder([string]$Ws, [string]$FromRel, [string]$ToRel, [string]$Bucket, [string]$Journal, $Logger) {
    $fromFull = Join-MigPath $Ws $FromRel
    foreach ($item in @(Get-ChildItem -LiteralPath $fromFull -Force)) {
        $subFrom = $FromRel + '\' + $item.Name
        $subTo   = $ToRel + '\' + $item.Name
        $destFull = Join-MigPath $Ws $subTo
        if (-not (Test-Path -LiteralPath $destFull)) {
            Move-MigItem $Ws $subFrom $subTo $Journal
        }
        elseif ($item.PSIsContainer) {
            Merge-MigFolder $Ws $subFrom $subTo $Bucket $Journal $Logger
        }
        else {
            $safe = Get-MigSafePath $Ws $Bucket $subFrom
            Move-MigItem $Ws $subFrom (Get-MigRel $Ws $safe) $Journal
            Write-MigLine $Logger ("migration: kept the new " + $subTo + ", old copy moved to SAFE TO DELETE")
        }
    }
    # The folder is empty now. An empty folder holds nothing to lose.
    if (@(Get-ChildItem -LiteralPath $fromFull -Force).Count -eq 0) {
        Remove-Item -LiteralPath $fromFull -Force
        if ($Journal) { [System.IO.File]::AppendAllText($Journal, ("mkdir`t" + $FromRel + "`r`n")) }
    }
}

# Runs every migration that still has something to do. Returns the list of
# short descriptions of what happened (empty when the drive is already in
# shape, which is the normal case).
function Invoke-DriveMigrations {
    param(
        [Parameter(Mandatory = $true)][string]$Ws,
        [string]$Journal = '',
        $Logger = $null
    )
    $done = New-Object System.Collections.ArrayList

    # --- 2026-10-10: profiles\ -> machine\ ---------------------------------
    $old = Join-MigPath $Ws 'profiles'
    $new = Join-MigPath $Ws 'machine'
    if (Test-Path -LiteralPath $old -PathType Container) {
        if (-not (Test-Path -LiteralPath $new)) {
            Move-MigItem $Ws 'profiles' 'machine' $Journal
            [void]$done.Add('renamed profiles to machine')
        }
        else {
            Merge-MigFolder $Ws 'profiles' 'machine' 'migration-2026-10-10' $Journal $Logger
            [void]$done.Add('merged profiles into machine')
        }
    }

    # --- 2026-10-10: Show My Profile.bat -> SAFE TO DELETE -----------------
    $oldBat = 'Maintenance Steps\Show My Profile.bat'
    if (Test-Path -LiteralPath (Join-MigPath $Ws $oldBat)) {
        $safe = Get-MigSafePath $Ws 'migration-2026-10-10' $oldBat
        Move-MigItem $Ws $oldBat (Get-MigRel $Ws $safe) $Journal
        [void]$done.Add('moved Show My Profile.bat to SAFE TO DELETE')
    }

    foreach ($d in $done) { Write-MigLine $Logger ("migration: " + $d) }
    # Callers wrap this in @(): an empty list comes back as nothing at all.
    return $done.ToArray()
}

# Walks a journal backwards. Returns the number of moves put back.
function Undo-DriveMigrations {
    param(
        [Parameter(Mandatory = $true)][string]$Ws,
        [Parameter(Mandatory = $true)][string]$Journal,
        $Logger = $null
    )
    if (-not (Test-Path -LiteralPath $Journal)) { return 0 }
    $lines = @([System.IO.File]::ReadAllLines($Journal) | Where-Object { $_ -ne '' })
    [array]::Reverse($lines)
    $n = 0
    foreach ($line in $lines) {
        $parts = $line.Split("`t")
        if ($parts.Count -ne 2) { continue }
        if ($parts[0] -eq 'mkdir') {
            $d = Join-MigPath $Ws $parts[1]
            if (-not (Test-Path -LiteralPath $d)) { [void](New-Item -ItemType Directory -Path $d -Force) }
            continue
        }
        $from = $parts[1]; $to = $parts[0]
        if (-not (Test-Path -LiteralPath (Join-MigPath $Ws $from))) {
            Write-MigLine $Logger ("undo migration: " + $from + " is gone, skipped")
            continue
        }
        if (Test-Path -LiteralPath (Join-MigPath $Ws $to)) {
            Write-MigLine $Logger ("undo migration: something is already at " + $to + ", skipped")
            continue
        }
        Move-MigItem $Ws $from $to ''
        $n++
    }
    Write-MigLine $Logger ("undo migration: put back " + $n + " move(s)")
    return $n
}
