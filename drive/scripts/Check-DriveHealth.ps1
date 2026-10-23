<#
    Check-DriveHealth.ps1
    ---------------------------------------------------------------------------
    READ-ONLY health check for the whole drive. Looks at six things and gives
    each one a light:

        green   fine
        yellow  worth knowing, nothing urgent
        red     something is actually wrong, and what to do about it

      1. Save backups     is the automatic backup still working?
      2. Protected files  are the custom files an update would wipe all
                          present and unmodified?
      3. Settings         does es_settings.cfg still hold what Apply My
                          Settings last wrote, and is this machine's own
                          profile the active one?
      4. Drive letters    is everything still portable - no hardcoded R:\ ?
      5. Video volume     are all the videos still levelled?
      6. Free space       how full is the drive?

    It changes NOTHING, so it is safe to run any time, even with RetroBat
    open. Its only output besides the screen is _ClaudeWorkspace\status.json,
    a machine-readable copy of the same report that later tools (the Setup
    Wizard window) read instead of re-doing the checks.

    It does not re-implement the other scripts' logic - it reads the records
    they already keep:
        SaveBackups\hook.log + backup.log        (the save backup)
        update-restore\                          (the protected file masters)
        machine\last-applied.json + active.txt  (what Apply last wrote)
        tools\video-loudness-checked.txt         (the volume checked-list)

    RULES HONOURED HERE (see the customization record):
      - no drive letters; everything derives from this script's location
      - no $PSScriptRoot inside a param() block
      - written for Windows PowerShell 5.1

    Run it from:  Maintenance Steps\Check Drive Health.bat
#>

[CmdletBinding()]
param(
    [switch]$Quiet     # still writes status.json, just prints nothing
)

$ErrorActionPreference = 'Stop'

function Say([string]$msg, [string]$colour = 'Gray') {
    if (-not $Quiet) { Write-Host $msg -ForegroundColor $colour }
}

# --- locate RetroBat -------------------------------------------------------
$Root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent

if (-not (Test-Path (Join-Path $Root 'retrobat.ini'))) {
    Write-Host "ERROR: could not find retrobat.ini above this script." -ForegroundColor Red
    Write-Host "       Expected RetroBat at: $Root" -ForegroundColor Red
    exit 1
}

. (Join-Path $PSScriptRoot 'ProfileEngine.ps1')

$Ws = Join-Path $Root '_ClaudeWorkspace'

# --- what this drive calls itself ------------------------------------------
#  wizard\wizard.ini is the ONE place the drive's name lives.
#  Read here so status.json can say what it is without anything else having
#  to know. A missing file is not a fault: the stamp is simply left empty.
$DriveName    = ''
$DriveVersion = ''
try {
    $wIni = Join-Path $Ws 'wizard\wizard.ini'
    if (Test-Path -LiteralPath $wIni) {
        foreach ($line in @([System.IO.File]::ReadAllLines($wIni))) {
            $t = $line.Trim()
            if ($t -eq '' -or $t.StartsWith(';') -or $t.StartsWith('#')) { continue }
            $eq = $t.IndexOf('=')
            if ($eq -lt 1) { continue }
            $k = $t.Substring(0, $eq).Trim().ToLower()
            $v = $t.Substring($eq + 1).Trim()
            if ($k -eq 'name')    { $DriveName    = $v }
            if ($k -eq 'version') { $DriveVersion = $v }
        }
    }
} catch { }
# The version moved to _ClaudeWorkspace\version.txt on 2026-10-10 (an update
# replaces that file and never touches wizard.ini). The wizard.ini line above
# only counts on a drive that has no version.txt yet.
try {
    $vTxt = Join-Path $Ws 'version.txt'
    if (Test-Path -LiteralPath $vTxt) {
        foreach ($line in @([System.IO.File]::ReadAllLines($vTxt))) {
            $t = $line.Trim()
            if ($t -ne '' -and -not $t.StartsWith(';') -and -not $t.StartsWith('#')) { $DriveVersion = $t; break }
        }
    }
} catch { }

# --- which switches are on -------------------------------------------------
#  A light must never go yellow or red because the drive did what it was
#  told. Two checks below ask about a feature that can be switched off, so
#  they need to know. EVERYTHING FAILS ON, as everywhere else: no
#  Features.ps1 and no features.ini means every feature is on.
$Feat = $null
$featuresLib = Join-Path $PSScriptRoot 'Features.ps1'
if (Test-Path -LiteralPath $featuresLib) {
    . $featuresLib
    $Feat = Get-Features $Root
}

# --- reading a log somebody else may be writing ----------------------------
#  hook.log and backup.log are written by the game-end hook, which can be
#  running at the exact moment somebody opens the wizard or presses Play.
#  [System.IO.File]::ReadAllLines asks for a share mode the hook already
#  holds, throws, and the Save backups light goes UNKNOWN - a yellow light
#  because the drive was busy doing its job, which is the noise this project
#  has fought twice already. Caught on 2026-09-02 in the drive's own
#  status.json, not by any unit test.
#
#  FileShare::ReadWrite says "read it even though someone else has it open".
#  Callers still wrap the result in @(), because a function that returns an
#  empty array returns nothing at all.
function Read-LogLines([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return @() }
    $fs = $null; $sr = $null
    try {
        $fs = New-Object System.IO.FileStream($Path, [System.IO.FileMode]::Open,
                  [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        $sr = New-Object System.IO.StreamReader($fs)
        $text = $sr.ReadToEnd()
        if ($text -eq '') { return @() }
        # ReadAllLines drops the empty string a trailing newline would leave
        # behind. Match it exactly, or a caller that indexes the last line
        # silently gets '' instead of the last thing the log actually said.
        if ($text.EndsWith("`r`n"))                                   { $text = $text.Substring(0, $text.Length - 2) }
        elseif ($text.EndsWith("`n") -or $text.EndsWith("`r"))        { $text = $text.Substring(0, $text.Length - 1) }
        return @($text -split "`r`n|`n|`r")
    }
    catch { return @() }
    finally {
        if ($null -ne $sr) { $sr.Dispose() }
        if ($null -ne $fs) { $fs.Dispose() }
    }
}

function Test-FeatureOn([string]$Key) {
    if ($null -eq $Feat) { return $true }
    if (-not $Feat.Contains($Key)) { return $true }
    return [bool]$Feat[$Key]
}

# Protected files that belong to a switch. The list itself lives in
# Features.ps1 (Get-FeatureFileMap): it used to be written out here AND in
# Restore-ProtectedFiles.ps1, with a comment in each asking whoever edited one
# to remember the other, which is exactly the shape of bug this project keeps
# finding. Empty when Features.ps1 is missing, so nothing reads as switched
# off - the fails-ON direction.
$FeatureFiles = [ordered]@{}
if (Get-Command Get-FeatureFileMap -ErrorAction SilentlyContinue) {
    $FeatureFiles = Get-FeatureFileMap
}

# --- one check's result, uniformly -----------------------------------------
#  status: ok / warn / bad / unknown
function New-Check([string]$Status, [string]$Summary, [string[]]$Detail = @()) {
    New-Object psobject -Property @{ status = $Status; summary = $Summary; detail = @($Detail) }
}

$checks = [ordered]@{}

# ===========================================================================
#  1. SAVE BACKUPS
# ===========================================================================
#  hook.log is written by the EmulationStation hooks (game end, and RetroBat
#  start); backup.log by the backup script itself. The failure that actually
#  happened in August 2026 was: hook fires, PowerShell side dies silently.
#  So the test is exactly that: after the last "game-end hook fired" line
#  there must be a "backup finished, exit code 0" line.
try {
    # Green, not yellow or red. Backing saves up is switched off, so a light
    # that nagged about it would be complaining that the drive did what it
    # was told - and this project already knows what a permanently unhappy
    # light does to somebody's willingness to read the other six.
    if (-not (Test-FeatureOn 'savebackup')) {
        $checks['savebackups'] = New-Check 'ok' 'Switched off. Saves are not being backed up.' @(
            'What was already backed up is still there and can still be put back.'
            'Turn it back on in the Features tab, or in features.ini.'
        )
    }
    else {
        $hookLog   = Join-Path $Ws 'SaveBackups\hook.log'
        $backupLog = Join-Path $Ws 'SaveBackups\backup.log'

        if (-not (Test-Path $hookLog) -and -not (Test-Path $backupLog)) {
            $checks['savebackups'] = New-Check 'warn' 'No backup has ever run on this machine yet.' @(
                'The logs appear after the first game finishes, or run',
                'SaveBackups\Backup Saves Now.bat to do one by hand.')
        }
        else {
            $hookLines = @()
            if (Test-Path $hookLog) { $hookLines = @(Read-LogLines $hookLog) }

            $lastFired = -1; $lastFinish = -1; $lastCode = $null
            for ($i = 0; $i -lt $hookLines.Count; $i++) {
                if ($hookLines[$i] -match 'game-end hook fired')                { $lastFired  = $i }
                if ($hookLines[$i] -match 'backup finished, exit code (\d+)')  { $lastFinish = $i; $lastCode = [int]$Matches[1] }
            }

            # last completed run, from backup.log's own summary line
            $lastRunText = ''
            $failedCount = 0
            if (Test-Path $backupLog) {
                foreach ($line in @(Read-LogLines $backupLog)) {
                    if ($line -match '^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}) \[INFO\] Run .*?:\s*(.+?)\s*$') {
                        $lastRunText = "$($Matches[1]): $($Matches[2])"
                        if ($Matches[2] -match '(\d+) failed') { $failedCount = [int]$Matches[1] }
                    }
                }
            }

            if ($lastFired -ge 0 -and $lastFinish -lt $lastFired) {
                $checks['savebackups'] = New-Check 'bad' 'The last game-end backup started but never finished.' @(
                    'EmulationStation ran the hook, but the backup script did not report back.',
                    'Run SaveBackups\Backup Saves Now.bat by hand and read the error it shows.',
                    "hook log: _ClaudeWorkspace\SaveBackups\hook.log")
            }
            elseif ($null -ne $lastCode -and $lastCode -ne 0) {
                $checks['savebackups'] = New-Check 'bad' "The last backup ended with an error (exit code $lastCode)." @(
                    'Run SaveBackups\Backup Saves Now.bat by hand and read the error it shows.')
            }
            elseif ($failedCount -gt 0) {
                $checks['savebackups'] = New-Check 'warn' "The last backup could not copy $failedCount file(s)." @(
                    'Usually an emulator still holding a file open. It retries after the next game.',
                    "detail: _ClaudeWorkspace\SaveBackups\backup.log")
            }
            else {
                $summary = 'Working. Backups run automatically after every game.'
                $detail  = @()
                if ($lastRunText) { $detail += "last run  $lastRunText" }
                $checks['savebackups'] = New-Check 'ok' $summary $detail
            }
        }
    }
}
catch { $checks['savebackups'] = New-Check 'unknown' "Could not check: $($_.Exception.Message)" }

# ===========================================================================
#  2. PROTECTED FILES
# ===========================================================================
#  Every file in update-restore\ must exist in RetroBat's own folders with
#  identical content. Same comparison Restore-ProtectedFiles.ps1 makes, done
#  read-only.
try {
    $masterDir = Join-Path $Ws 'update-restore'
    if (-not (Test-Path $masterDir)) {
        $checks['protectedfiles'] = New-Check 'unknown' 'No update-restore folder found.'
    }
    else {
        $masters = @(Get-ChildItem -LiteralPath $masterDir -File -Recurse -ErrorAction SilentlyContinue)
        $stockDir = Join-Path $Ws 'update-restore-off'

        # A file whose feature is switched off is SUPPOSED to be RetroBat's
        # own copy, not ours. Comparing it to our master would light this red
        # for doing exactly what it was told, so it is compared to the stock
        # copy instead, or left out of the count when there is not one.
        $offPaths = @{}
        foreach ($key in $FeatureFiles.Keys) {
            if (Test-FeatureOn $key) { continue }
            foreach ($rp in $FeatureFiles[$key]) { $offPaths[$rp.ToLower()] = $key }
        }

        # And the other sense: a file that a switched-ON feature deliberately
        # moves off the drive. Counting it as missing would light this red for
        # the drive doing what it was told. See Get-FeatureSkipMap.
        $skipPaths = @{}
        if (Get-Command Get-FeatureSkipMap -ErrorAction SilentlyContinue) {
            $sm = Get-FeatureSkipMap
            foreach ($key in $sm.Keys) {
                $entry = $sm[$key]
                if (-not (Test-FeatureSkipApplies $entry (Test-FeatureOn $key))) { continue }
                foreach ($rp in $entry['Paths']) { $skipPaths[$rp.ToLower()] = $key }
            }
        }

        $missing = @(); $differs = @(); $switchedOff = 0; $putAside = 0
        foreach ($m in $masters) {
            $rel  = $m.FullName.Substring($masterDir.Length).TrimStart('\')
            $live = Join-Path $Root $rel

            if ($skipPaths.ContainsKey($rel.ToLower())) { $putAside++; continue }

            $want = $m.FullName
            if ($offPaths.ContainsKey($rel.ToLower())) {
                $switchedOff++
                $stock = Join-Path $stockDir $rel
                if (-not (Test-Path -LiteralPath $stock)) { continue }
                $want = $stock
            }

            if (-not (Test-Path -LiteralPath $live)) { $missing += $rel; continue }
            $a = (Get-FileHash -LiteralPath $live -Algorithm SHA256).Hash
            $b = (Get-FileHash -LiteralPath $want -Algorithm SHA256).Hash
            if ($a -ne $b) { $differs += $rel }
        }

        if ($missing.Count -eq 0 -and $differs.Count -eq 0) {
            $summary = "All $($masters.Count) protected files present and matching."
            $notes = @()
            if ($switchedOff -gt 0) { $notes += "$switchedOff switched off" }
            if ($putAside -gt 0)    { $notes += "$putAside put aside on purpose" }
            if ($notes.Count -gt 0) {
                $summary = "All $($masters.Count) present and matching ({0})." -f ($notes -join ', ')
            }
            $checks['protectedfiles'] = New-Check 'ok' $summary
        }
        else {
            $detail = @()
            foreach ($x in $missing) { $detail += "MISSING  $x" }
            foreach ($x in $differs) { $detail += "CHANGED  $x" }
            $detail += 'Fix: run Maintenance Steps\Restore Protected Files.bat (RetroBat closed).'
            $detail += 'If YOU changed one on purpose, run Update Master Copies.bat instead.'
            $checks['protectedfiles'] = New-Check 'bad' "$($missing.Count) missing, $($differs.Count) changed of $($masters.Count) protected files." $detail
        }
    }
}
catch { $checks['protectedfiles'] = New-Check 'unknown' "Could not check: $($_.Exception.Message)" }

# ===========================================================================
#  3. SETTINGS
# ===========================================================================
#  Apply-Settings saves a snapshot of everything it wrote (machine\
#  last-applied.json). If es_settings.cfg no longer matches that snapshot,
#  something reverted it - usually an update, sometimes a menu change.
#  Also: is the profile that was applied actually THIS machine's?
try {
    $snapPath = Join-Path $Ws 'machine\last-applied.json'
    $cfgPath  = Join-Path $Root 'emulationstation\.emulationstation\es_settings.cfg'

    if (-not (Test-Path $cfgPath)) {
        $checks['settings'] = New-Check 'bad' 'es_settings.cfg is missing entirely.' @(
            'Start RetroBat once so it creates one, then run Apply My Settings.')
    }
    elseif (-not (Test-Path $snapPath)) {
        $checks['settings'] = New-Check 'warn' 'Apply My Settings has not been run since the health check was added.' @(
            'Run Maintenance Steps\Apply My Settings.bat once (RetroBat closed) and',
            'this light will know what to compare against.')
    }
    else {
        $snap = Get-Content -LiteralPath $snapPath -Raw | ConvertFrom-Json
        [xml]$cfgXml = Get-Content -LiteralPath $cfgPath -Raw
        $cfg = $cfgXml.SelectSingleNode('/config')

        # --- keys EmulationStation throws away on purpose -------------------
        #  EmulationStation drops any key whose value equals its own built-in
        #  default when it rewrites es_settings.cfg on exit. Four of ours are
        #  like that, and they used to make this light go red forever: the Fix
        #  button wrote them back, the next game night stripped them again.
        #
        #  Nothing is wrong when one of those is missing, because missing IS
        #  the value we asked for. So an ABSENT key on this list is fine. A
        #  key on this list that is PRESENT with the wrong value is still
        #  drift, which is the case this must not paper over.
        #
        #  The list is not kept here. Apply-Settings.ps1 owns it and writes it
        #  into last-applied.json, so there is one copy of it and this follows
        #  any future edit. An older snapshot simply has no list, and then
        #  this behaves exactly as it did before - nothing is forgiven.
        $esDefaults = @()
        if ($snap.PSObject.Properties.Name -contains 'esdefaults') {
            $esDefaults = @($snap.esdefaults)
        }
        $forgiven = 0

        $drift = @()
        foreach ($p in $snap.strings.PSObject.Properties) {
            $node = $cfg.SelectSingleNode("string[@name='$($p.Name)']")
            $liveVal = if ($node) { $node.GetAttribute('value') } else { $null }
            if ($liveVal -ne [string]$p.Value) {
                if ($null -eq $liveVal -and $esDefaults -contains $p.Name) { $forgiven++; continue }
                $shown = if ($null -eq $liveVal) { '(gone)' } else { $liveVal }
                $drift += "$($p.Name): should be '$($p.Value)', is $shown"
            }
        }
        foreach ($p in $snap.bools.PSObject.Properties) {
            $node = $cfg.SelectSingleNode("bool[@name='$($p.Name)']")
            $liveVal = if ($node) { $node.GetAttribute('value') } else { $null }
            if ($liveVal -ne [string]$p.Value) {
                if ($null -eq $liveVal -and $esDefaults -contains $p.Name) { $forgiven++; continue }
                $shown = if ($null -eq $liveVal) { '(gone)' } else { $liveVal }
                $drift += "$($p.Name): should be '$($p.Value)', is $shown"
            }
        }
        foreach ($name in @($snap.removed)) {
            if ($cfg.SelectSingleNode("*[@name='$name']")) {
                $drift += "${name}: should not exist, but it is back"
            }
        }

        # --- the per-game settings this drive wrote -------------------------
        #  Walked rather than queried with XPath on purpose: one of these
        #  names is Yoshi's Woolly World, and an apostrophe inside an XPath
        #  [@name='...'] predicate throws rather than simply not matching.
        #  Apply-Settings.ps1 avoids XPath for the same reason.
        if ($snap.PSObject.Properties.Name -contains 'games' -and $null -ne $snap.games) {
            $live = @{}
            foreach ($n in @($cfg.ChildNodes)) {
                if ($n.NodeType -ne 'Element') { continue }
                if ($n.get_Name() -ne 'string') { continue }
                $live[$n.GetAttribute('name')] = $n.GetAttribute('value')
            }
            foreach ($p in $snap.games.PSObject.Properties) {
                if (-not $live.ContainsKey($p.Name)) {
                    $drift += ("{0}: should be '{1}', is (gone)" -f $p.Name, $p.Value)
                }
                elseif ([string]$live[$p.Name] -ne [string]$p.Value) {
                    $drift += ("{0}: should be '{1}', is {2}" -f $p.Name, $p.Value, $live[$p.Name])
                }
            }
        }

        # is the active profile this machine's?
        $wrongMachine = $false
        $activePath = Join-Path $Ws 'machine\active.txt'
        $thisMachine = [string]$env:COMPUTERNAME
        if ((Test-Path $activePath) -and $thisMachine) {
            $activeText = Get-Content -LiteralPath $activePath -Raw
            if ($activeText -match 'machine\s*=\s*(.+)') {
                $activeMachine = $Matches[1].Trim()
                if ($activeMachine -ine $thisMachine) { $wrongMachine = $true }
            }
        }

        if ($wrongMachine) {
            $checks['settings'] = New-Check 'warn' "The settings in this setup were applied for another computer ($activeMachine)." @(
                "This machine is $thisMachine. Run Apply My Settings to switch over.")
        }
        elseif ($drift.Count -eq 0) {
            $total = @($snap.strings.PSObject.Properties).Count + @($snap.bools.PSObject.Properties).Count
            $note = @()
            if ($forgiven -gt 0) {
                $note += "$forgiven of them are not written into the file at all, because the value"
                $note += "we want is EmulationStation's own default and it removes those when it"
                $note += "closes. They are doing exactly what they should. Nothing to fix."
            }
            $checks['settings'] = New-Check 'ok' "All $total managed settings match what was last applied." $note
        }
        else {
            $detail = @($drift | Select-Object -First 12)
            if ($drift.Count -gt 12) { $detail += "...and $($drift.Count - 12) more" }
            $detail += 'Fix: run Maintenance Steps\Apply My Settings.bat (RetroBat closed).'
            $detail += 'If you changed one of these in the RetroBat menu ON PURPOSE, tell Claude'
            $detail += 'or pin it on the Machine tab so it stops counting as drift.'
            $checks['settings'] = New-Check 'bad' "$($drift.Count) setting(s) no longer match what was applied." $detail
        }
    }
}
catch { $checks['settings'] = New-Check 'unknown' "Could not check: $($_.Exception.Message)" }

# ===========================================================================
#  4. DRIVE LETTERS
# ===========================================================================
#  The Wii launch command must go through %HOME%, and none of the config or
#  script files in the known trouble spots may contain a literal
#  <letter>:\RetroBat path. Same scan Fix-Portability.ps1 does, read-only.
try {
    $detail = @()
    $bad = $false

    $esSystems = Join-Path $Root 'emulationstation\.emulationstation\es_systems.cfg'
    if (Test-Path $esSystems) {
        $text = [System.IO.File]::ReadAllText($esSystems)
        $m = [regex]::Match($text, '(?s)<system>(?:(?!</system>).)*?<name>wii</name>.*?</system>')
        if ($m.Success) {
            $cmd = [regex]::Match($m.Value, '(?s)<command>(.*?)</command>')
            if ($cmd.Success) {
                # Which command is CORRECT depends on the switch. With
                # 'wiisystemmenu' off, RetroBat's own command is what should
                # be there, and complaining about it would light this red for
                # a deliberate choice. The drive letter check applies either
                # way, because that is a portability bug in any command.
                $wantsWrapper = Test-FeatureOn 'wiisystemmenu'

                if ($wantsWrapper -and $cmd.Groups[1].Value -notmatch 'wii-nand-launch\.vbs') {
                    $detail += 'The Wii launch command is not going through the System Menu wrapper.'
                    $bad = $true
                }
                elseif (-not $wantsWrapper -and $cmd.Groups[1].Value -match 'wii-nand-launch\.vbs') {
                    $detail += "The Wii launch command still goes through the System Menu wrapper, but 'wiisystemmenu' is switched off."
                    $bad = $true
                }
                elseif ($cmd.Groups[1].Value -match '[A-Za-z]:[\\/]') {
                    $detail += 'The Wii launch command contains a hardcoded drive letter.'
                    $bad = $true
                }
            }
        }
    }

    # Dolphin's User\Config is deliberately NOT scanned. RetroBat's launcher
    # rewrites those paths (NANDRootPath, ISOPaths, defaultISO, memcards...)
    # with the CURRENT drive letter every time a game starts, so absolute
    # paths there are self-repairing on any machine - the same story as
    # Cemu's mlc_path in the customization record. Flagging them made every
    # play session raise a false alarm (seen 2026-08-27).
    $scanPaths = @(
        $esSystems,
        (Join-Path $Root 'emulationstation\.emulationstation\scripts'),
        (Join-Path $Root 'system\scripts'),
        (Join-Path $Root '_ClaudeWorkspace\scripts')
    ) | Where-Object { Test-Path $_ }

    $exts = @('.bat', '.cmd', '.ps1', '.vbs', '.cfg', '.ini', '.txt')
    $hits = 0
    foreach ($p in $scanPaths) {
        $files = if (Test-Path $p -PathType Container) {
            @(Get-ChildItem -Path $p -Recurse -File | Where-Object { $exts -contains $_.Extension.ToLower() })
        } else { @(Get-Item $p) }
        foreach ($file in $files) {
            # @() matters: a one-line file would otherwise come back as a bare
            # string, and indexing a string walks its CHARACTERS.
            $lines = @(Get-Content -LiteralPath $file.FullName -ErrorAction SilentlyContinue)
            for ($i = 0; $i -lt $lines.Count; $i++) {
                # A COMMENT IS NOT A BUG. Several scripts on this drive explain
                # the drive letter trap in their own comments, and to do that
                # one of them has to be able to write out a drive letter. The
                # scan flagged those, so this light sat permanently yellow on
                # 2026-08-29 with nothing actually wrong. Comment markers
                # covered: # (PowerShell, ini), ; (ini), REM and :: (batch),
                # ' (VBScript). A commented-out line does not run, so it
                # cannot be a portability bug either way.
                $t = $lines[$i].TrimStart()
                if ($t -match '^(#|;|::|'')' -or $t -match '^(?i)REM\s') { continue }
                if ($lines[$i] -match '[A-Za-z]:[\\/]RetroBat') {
                    $hits++
                    if ($hits -le 8) {
                        $detail += ('{0} (line {1})' -f $file.FullName.Replace($Root, '<RetroBat>'), ($i + 1))
                    }
                }
            }
        }
    }
    if ($hits -gt 0) {
        $detail += 'Fix: run Maintenance Steps\Fix Drive Letters.bat (RetroBat closed).'
    }

    if ($bad) {
        $detail += 'Fix: run Maintenance Steps\Fix Drive Letters.bat (RetroBat closed).'
        $checks['driveletters'] = New-Check 'bad' 'The Wii launch command needs repairing.' $detail
    }
    elseif ($hits -gt 0) {
        $checks['driveletters'] = New-Check 'warn' "$hits line(s) still contain a hardcoded drive letter." $detail
    }
    else {
        $checks['driveletters'] = New-Check 'ok' 'Portable. No hardcoded drive letters anywhere they matter.'
    }
}
catch { $checks['driveletters'] = New-Check 'unknown' "Could not check: $($_.Exception.Message)" }

# ===========================================================================
#  5. VIDEO VOLUME
# ===========================================================================
#  Fix-VideoVolume.ps1 keeps a checked-list: one line per video recording its
#  size, timestamp, and the target it was levelled to. A video counts as
#  levelled if its line still matches the file AND the current targets.
#  The targets are read out of Fix-VideoVolume.ps1 itself, so there is only
#  one place they live.
#
#  Game previews and intro videos are enumerated directly. Theme menu videos
#  are validated from the checked-list only (working out WHICH of the theme's
#  400+ videos are on the menu is the volume script's job - a brand-new menu
#  video is picked up by the next run of Fix Video Volume, which the update
#  button already includes).
try {
    $volScript = Join-Path $Ws 'scripts\Fix-VideoVolume.ps1'
    $ledger    = Join-Path $Ws 'tools\video-loudness-checked.txt'

    if (-not (Test-FeatureOn 'videovolume')) {
        # Green, not yellow. The drive is doing what it was told, and a light
        # that nags about a deliberate choice is a light people stop reading.
        $checks['videovolume'] = New-Check 'ok' 'Switched off. New videos are left alone.' @(
            'Turn it back on in the Features tab, or in features.ini.'
        )
    }
    elseif (-not (Test-Path $volScript)) {
        $checks['videovolume'] = New-Check 'unknown' 'Fix-VideoVolume.ps1 not found.'
    }
    else {
        $volText = [System.IO.File]::ReadAllText($volScript)
        # Cast through [double] so "-24.0" in the script becomes "-24", which
        # is exactly how the volume script stringifies it into its keys.
        $tPrev  = [string][double][regex]::Match($volText, '\$PreviewTargetLufs\s*=\s*(-?[\d.]+)').Groups[1].Value
        $tMenu  = [string][double][regex]::Match($volText, '\$MenuTargetLufs\s*=\s*(-?[\d.]+)').Groups[1].Value
        $tIntro = [string][double][regex]::Match($volText, '\$IntroTargetLufs\s*=\s*(-?[\d.]+)').Groups[1].Value
        $tol    = [string][double][regex]::Match($volText, '\$Tolerance\s*=\s*(-?[\d.]+)').Groups[1].Value

        $checkedSet = @{}
        if (Test-Path $ledger) {
            foreach ($line in [System.IO.File]::ReadAllLines($ledger)) {
                if ($line.Trim()) { $checkedSet[$line] = $true }
            }
        }

        # same key the volume script builds: rel|size|ticks|target|tolerance
        function Get-VolKey([System.IO.FileInfo]$f, [string]$target) {
            $rel = $f.FullName.Substring($Root.Length).TrimStart('\')
            "$rel|$($f.Length)|$($f.LastWriteTimeUtc.Ticks)|$target|$tol"
        }

        $unlevelled = @()
        # counted separately: one MESSAGE can stand for several videos,
        # and the summary line should say how many videos, not how many lines.
        $unlevelledCount = 0

        # game previews
        $romsDir = Join-Path $Root 'roms'
        foreach ($sysDir in @(Get-ChildItem -Path $romsDir -Directory -ErrorAction SilentlyContinue)) {
            $vidDir = Join-Path $sysDir.FullName 'videos'
            if (-not (Test-Path $vidDir)) { continue }
            foreach ($v in @(Get-ChildItem -Path $vidDir -File -Include *.mp4,*.webm,*.mkv -Recurse -ErrorAction SilentlyContinue)) {
                if (-not $checkedSet.ContainsKey((Get-VolKey $v $tPrev))) { $unlevelled += "preview  $($sysDir.Name)\$($v.Name)"; $unlevelledCount++ }
            }
        }

        # intro videos
        $introDir = Join-Path $Root 'emulationstation\.emulationstation\video'
        if (Test-Path $introDir) {
            foreach ($v in @(Get-ChildItem -Path $introDir -File -Include *.mp4,*.webm,*.mkv -Recurse -ErrorAction SilentlyContinue)) {
                if (-not $checkedSet.ContainsKey((Get-VolKey $v $tIntro))) { $unlevelled += "intro    $($v.Name)"; $unlevelledCount++ }
            }
        }

        # menu videos: re-validate every theme entry already on the list
        $staleMenu = 0
        foreach ($key in $checkedSet.Keys) {
            $parts = $key.Split('|')
            if ($parts.Count -ne 5) { continue }
            if ($parts[3] -ne $tMenu) { continue }              # not a menu entry
            $rel = $parts[0]
            if ($rel -notmatch 'themes') { continue }
            $live = Join-Path $Root $rel
            if (-not (Test-Path -LiteralPath $live)) { continue }  # video removed; fine
            $f = Get-Item -LiteralPath $live
            if (("$($f.Length)" -ne $parts[1]) -or ("$($f.LastWriteTimeUtc.Ticks)" -ne $parts[2]) -or ($parts[4] -ne $tol)) {
                $staleMenu++
            }
        }
        if ($staleMenu -gt 0) {
            $unlevelled += "menu     $staleMenu theme video(s) changed since they were levelled"
            $unlevelledCount += $staleMenu
        }

        $levelled = $checkedSet.Count
        if ($unlevelled.Count -eq 0) {
            $checks['videovolume'] = New-Check 'ok' "All levelled ($levelled on the checked-list, targets $tPrev / $tMenu / $tIntro LUFS)."
        }
        else {
            $detail = @($unlevelled | Select-Object -First 10)
            if ($unlevelled.Count -gt 10) { $detail += "...and $($unlevelled.Count - 10) more" }
            $detail += 'Fix: run Maintenance Steps\Fix Video Volume.bat (RetroBat closed).'
            $checks['videovolume'] = New-Check 'warn' "$unlevelledCount video(s) not levelled yet." $detail
        }
    }
}
catch { $checks['videovolume'] = New-Check 'unknown' "Could not check: $($_.Exception.Message)" }

# ===========================================================================
#  6. FREE SPACE
# ===========================================================================
try {
    $drive = New-Object System.IO.DriveInfo([System.IO.Path]::GetPathRoot($Root))
    $freeGB  = [math]::Round($drive.AvailableFreeSpace / 1GB, 1)
    $totalGB = [math]::Round($drive.TotalSize / 1GB, 0)
    if     ($freeGB -lt 5)  { $checks['freespace'] = New-Check 'bad'  "Only $freeGB GB free of $totalGB GB - backups and new games will start failing." }
    elseif ($freeGB -lt 25) { $checks['freespace'] = New-Check 'warn' "$freeGB GB free of $totalGB GB - getting tight." }
    else                    { $checks['freespace'] = New-Check 'ok'   "$freeGB GB free of $totalGB GB." }
}
catch { $checks['freespace'] = New-Check 'unknown' "Could not check: $($_.Exception.Message)" }

# ===========================================================================
#  7. MID-GAME AUTOSAVES
# ===========================================================================
#  Quarantine-Savestates.ps1 moves savestates out of reach after every game so
#  one cannot be loaded by accident. That is the system working, not a fault,
#  so this light is GREEN whenever it can read the folder. It exists because
#  Steven asked to be able to SEE that it is happening; a light that went
#  yellow every time the drive did its job correctly would be noise, and this
#  project has already learned what a permanently yellow light does to
#  somebody's willingness to look at the others.
# ===========================================================================
try {
    $qRoot   = Join-Path $Ws 'archive\quarantined-savestates'
    $qFiles  = @()
    $qNewest = $null

    if (Test-Path -LiteralPath $qRoot) {
        $qFiles = @(Get-ChildItem -LiteralPath $qRoot -Recurse -File -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -notmatch '\.(png|txt)$' })   # every emulator since 2026-10-11
        if ($qFiles.Count -gt 0) {
            $qNewest = ($qFiles | Sort-Object LastWriteTime -Descending | Select-Object -First 1).LastWriteTime
        }
    }

    if ($qFiles.Count -eq 0) {
        $checks['savestates'] = New-Check 'ok' 'None being held.'
    }
    else {
        # Dolphin keeps a savestate in two places, one named by game id and one
        # by rom file name, so the raw file count is about double the number of
        # actual moments. Saying "about" is more honest than halving it and
        # being wrong when only one copy exists.
        $detail = @( ('Newest: {0}. Listed against their games on the Saves tab.' -f $qNewest.ToString('ddd yyyy-MM-dd HH:mm')) )
        $checks['savestates'] = New-Check 'ok' ("{0} held aside. That is normal." -f $qFiles.Count) $detail
    }
}
catch { $checks['savestates'] = New-Check 'unknown' "Could not check: $($_.Exception.Message)" }

# ===========================================================================
#  REPORT
# ===========================================================================
$profileInfo = $null
try { $profileInfo = Resolve-MachineProfile -Root $Root -NoWrite } catch { }

$order  = @('savebackups','protectedfiles','settings','driveletters','videovolume','freespace','savestates')
$titles = @{
    savebackups    = 'Save backups'
    protectedfiles = 'Protected files'
    settings       = 'Settings'
    driveletters   = 'Drive letters'
    videovolume    = 'Video volume'
    freespace      = 'Free space'
    savestates     = 'Mid-game autosaves'
}
$colours = @{ ok = 'Green'; warn = 'Yellow'; bad = 'Red'; unknown = 'DarkGray' }

$overall = 'ok'
foreach ($k in $order) {
    if ($checks[$k].status -eq 'bad') { $overall = 'bad'; break }
    if ($checks[$k].status -in @('warn','unknown')) { $overall = 'warn' }
}

Say ""
Say "  Drive health" 'White'
if ($DriveName -ne '') {
    if ($DriveVersion -ne '') { Say ("  {0}  -  version {1}" -f $DriveName, $DriveVersion) 'DarkGray' }
    else                      { Say ("  {0}" -f $DriveName) 'DarkGray' }
}
Say "  ------------"
foreach ($k in $order) {
    $c = $checks[$k]
    Say ("  [{0,-4}]  {1,-16} {2}" -f $c.status.ToUpper(), $titles[$k], $c.summary) $colours[$c.status]
    foreach ($d in $c.detail) { Say ("           {0}" -f $d) 'DarkGray' }
}
Say ""
if ($profileInfo -and $profileInfo.Ok) {
    Say ("  {0} - {1} tier - overall: {2}" -f $profileInfo.Machine, $profileInfo.Tier.ToUpper(), $overall.ToUpper()) 'Cyan'
}
else {
    Say ("  overall: {0}" -f $overall.ToUpper()) 'Cyan'
}

# --- status.json ------------------------------------------------------------
try {
    $status = [ordered]@{
        generated = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        drive     = $DriveName
        version   = $DriveVersion
        machine   = [string]$env:COMPUTERNAME
        profile   = ''
        tier      = ''
        overall   = $overall
        checks    = [ordered]@{}
    }
    if ($profileInfo -and $profileInfo.Ok) {
        $status['profile'] = $profileInfo.ProfileName
        $status['tier']    = $profileInfo.Tier
    }
    foreach ($k in $order) {
        $status['checks'][$k] = [ordered]@{
            title   = $titles[$k]
            status  = $checks[$k].status
            summary = $checks[$k].summary
            detail  = @($checks[$k].detail)
        }
    }
    $json = $status | ConvertTo-Json -Depth 5
    [System.IO.File]::WriteAllText((Join-Path $Ws 'status.json'), $json, (New-Object System.Text.UTF8Encoding($false)))
    Say ""
    Say "  Full report saved: _ClaudeWorkspace\status.json" 'DarkGray'
}
catch {
    Say ("  (could not write status.json: {0})" -f $_.Exception.Message) 'Yellow'
}

Say ""
if ($overall -eq 'bad') { exit 2 } elseif ($overall -eq 'warn') { exit 1 } else { exit 0 }
