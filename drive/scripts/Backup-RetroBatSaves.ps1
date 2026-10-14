<#
    Backup-RetroBatSaves.ps1   (v7)
    -------------------------------------------------------------------------
    Keeps a full version history of RetroBat's save data, PER FILE.

    v7 CHANGES - THE INDEX NOW FORGETS FILES THAT ARE GONE
      It was append-only, so a deleted save stayed in the index forever. That
      was invisible until the Saves tab began reading the index and listed a
      WiiWare channel that had been removed from the Wii NAND weeks earlier as
      a game with saves. Entries not seen during a run are now dropped. The
      VERSION FILES are untouched; only the index's claim about the present is.

    v6 CHANGES - NO MORE DRIVE LETTERS IN THE INDEX
      index.json used to record each version as a full path beginning with a
      drive letter. On any computer where the drive is not R: those paths are
      all wrong, so the fast path below never matched and every backup re-read
      and re-hashed all 1500 save files. Silent, and slow only on the machines
      that are not this one. Versions are stored relative to the Versions
      folder now, and old entries upgrade themselves as they are touched.

    v5 CHANGES - SPEED
      The first run has to read and hash every save file, which is why it took
      over a minute. Every run after that was going to do the same work again
      for no reason.

      v5 keeps an index (index.json) of each file's timestamp, size, and the
      version last written for it. On later runs, a file whose timestamp and
      size are unchanged is skipped instantly - no hashing, no copying. Only
      files you actually touched get looked at.

      Expect the next run to finish in a second or two instead of 78.

      Also added: after copying, the new version's size is verified against
      the original. A copy interrupted by a shutdown gets deleted and retried
      next run rather than being trusted.

    LAYOUT
      SaveBackups\Versions\<mirrored folders>\<save name>\
          2026-08-20_161930_a3f9c1d2__Kirby Air Ride (USA).gci

    Run it with SaveBackups\Backup Saves Now.bat. It also runs automatically and
    invisibly after every game via the game-end hook.
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string] $SavesRoot   = '',
    [string] $BackupRoot  = '',
    [int]    $KeepPerFile = 200,
    [int]    $KeepDays    = 365,
    [int]    $MaxFileMB   = 128,
    [switch] $Full,          # ignore the index and re-check everything
    [switch] $Quiet
)

# ---------------------------------------------------------------------------
#  WHERE AM I?  (do not move this into the param block above)
# ---------------------------------------------------------------------------
#  $PSScriptRoot is EMPTY while PowerShell is working out parameter default
#  values in a script started with -File, which is how the EmulationStation
#  hooks start this one. Any path built up there silently comes out wrong, and
#  the script dies on its first Split-Path before it can even write to its own
#  log. That is exactly what happened here for a week in August 2026: saves
#  quietly stopped being backed up and nothing said a word.
#
#  In the body, below the param block, $PSScriptRoot is filled in properly. So
#  the paths get built here, and the parameters above just default to empty.
# ---------------------------------------------------------------------------
$ScriptDir = $PSScriptRoot
if (-not $ScriptDir) { $ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path }
if (-not $ScriptDir) { throw 'Could not work out which folder this script is in.' }
$WorkspaceDir = Split-Path $ScriptDir -Parent      # <RetroBat>\_ClaudeWorkspace
$RetroBatDir  = Split-Path $WorkspaceDir -Parent   # <RetroBat>

if (-not $SavesRoot)  { $SavesRoot  = Join-Path $RetroBatDir 'saves' }
if (-not $BackupRoot) { $BackupRoot = Join-Path $WorkspaceDir 'SaveBackups' }


$versionRoot = Join-Path $BackupRoot 'Versions'
$logPath     = Join-Path $BackupRoot 'backup.log'
$indexPath   = Join-Path $BackupRoot 'index.json'
$stamp       = Get-Date -Format 'yyyy-MM-dd_HHmmss'
$maxLogged   = 25
$logged      = 0

# ---------------------------------------------------------------------------
#  WHERE A VERSION LIVES, WITHOUT A DRIVE LETTER   (added 2026-08-29, v6)
# ---------------------------------------------------------------------------
#  Until now the index stored each version as a FULL path, so index.json was
#  full of lines saying R:\RetroBat\... . That is the drive letter trap this
#  project keeps falling into: plug the drive into a machine where it is D:
#  and every one of those paths points at nothing. The fast path below then
#  failed for every file, so a backup on any other computer re-hashed all
#  1500 saves instead of skipping them. Nothing errored. It was just slow,
#  quietly, on exactly the machines that are not this one.
#
#  Versions are now stored RELATIVE to the Versions folder. Old absolute
#  entries are still understood, and are rewritten to the new shape as each
#  file is looked at, so the index upgrades itself with no migration step and
#  nothing to remember.
# ---------------------------------------------------------------------------
function Get-RelativeVersionPath([string] $Full) {
    if (-not $Full) { return '' }
    if ($Full.StartsWith($versionRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $Full.Substring($versionRoot.Length).TrimStart('\')
    }
    $i = $Full.IndexOf('\Versions\', [System.StringComparison]::OrdinalIgnoreCase)
    if ($i -ge 0) { return $Full.Substring($i + 10) }
    return $Full
}

function Get-FullVersionPath([string] $Stored) {
    if (-not $Stored) { return '' }
    if ($Stored -match '^[A-Za-z]:\\' -or $Stored -match '^\\\\') {
        $i = $Stored.IndexOf('\Versions\', [System.StringComparison]::OrdinalIgnoreCase)
        if ($i -lt 0) { return '' }
        return (Join-Path $versionRoot $Stored.Substring($i + 10))
    }
    return (Join-Path $versionRoot $Stored)
}

if (-not (Get-Command Get-ShortSaveLeaf -ErrorAction SilentlyContinue)) {
    # A save file whose NAME is very long (Paper Mario Color Splash keeps one of
    # about 190 letters) made its backup path longer than Windows allows, so it
    # was never backed up and Health said "could not copy 1 file" (2026-10-14).
    # Long names are shortened, the same way everywhere, for the history folder
    # and the copies in it. The original name lives on in the index, and a
    # restore always puts the file back under its real name.
    function Get-ShortSaveLeaf([string]$Leaf) {
        if ($Leaf.Length -le 60) { return $Leaf }
        $sha = [System.Security.Cryptography.SHA1]::Create()
        try { $h = -join ($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Leaf)) | Select-Object -First 4 | ForEach-Object { $_.ToString('x2') }) }
        finally { $sha.Dispose() }
        $ext = [System.IO.Path]::GetExtension($Leaf)
        if ($ext.Length -gt 8) { $ext = '' }
        return ($Leaf.Substring(0, 24) + '~' + $h + $ext)
    }
}

function Write-Log {
    param([string] $Message, [string] $Level = 'INFO')
    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    if (-not $Quiet) { Write-Host $line }
    try { Add-Content -LiteralPath $logPath -Value $line -Encoding UTF8 -ErrorAction Stop } catch { }
}

function Write-Problem {
    param([string] $Message)
    $script:logged++
    if ($script:logged -le $maxLogged) { Write-Log $Message 'ERROR' }
    elseif ($script:logged -eq $maxLogged + 1) { Write-Log 'Further errors suppressed; see summary.' 'ERROR' }
}

# ---------------------------------------------------------------------------
#  IS THE AUTOMATIC BACKUP SWITCHED ON?
# ---------------------------------------------------------------------------
#  This has to stay BELOW Write-Log, because it writes a line saying it did
#  nothing. That line matters: this script is run by the EmulationStation
#  game-end hook, which nobody watches, and a backup that stops silently is
#  exactly the failure that went unnoticed here for a week in August 2026.
#  With a line in backup.log there is always a trail.
#
#  It exits 0, not 1. The hook treats a non-zero exit as a failure and would
#  report a broken backup when the truth is that somebody switched it off.
#
#  EVERYTHING FAILS ON: no Features.ps1, no features.ini, an unreadable file
#  or a value that is not on or off all mean ON, so a broken file can never
#  quietly stop your saves being backed up.
#
#  The mid-game savestate quarantine is NOT covered by this switch. It is a
#  different job, it has its own button and its own health light, and turning
#  it off would change how games behave rather than what the drive stores.
# ---------------------------------------------------------------------------
$featuresLib = Join-Path $ScriptDir 'Features.ps1'
if (Test-Path -LiteralPath $featuresLib) {
    . $featuresLib
    if (-not (Test-Feature $RetroBatDir 'savebackup')) {
        Write-Log 'Skipped: automatic save backup is switched off in features.ini.'
        exit 0
    }
}

if (-not (Test-Path -LiteralPath $SavesRoot)) { throw "Saves folder not found: $SavesRoot" }

# The shared table of save folders OUTSIDE saves\ (the PC ports), 2026-10-11.
$extraRoots = @()
$saveIndexLib = Join-Path $ScriptDir 'SaveIndex.ps1'
if (Test-Path -LiteralPath $saveIndexLib) {
    try { . $saveIndexLib; $extraRoots = @($script:SaveExtraRoots) } catch { $extraRoots = @() }
}

# How much to keep (SaveBackups\storage.ini, set from the Saves tab, 2026-10-11).
# "versions = N" keeps the newest N of each save, whatever their age. Missing
# or 0: the defaults above (200, and nothing younger than a year is trimmed).
$keepAnyAge = $false
$storageIni = Join-Path $BackupRoot 'storage.ini'
if (-not $PSBoundParameters.ContainsKey('KeepPerFile') -and (Test-Path -LiteralPath $storageIni)) {
    foreach ($line in @([System.IO.File]::ReadAllLines($storageIni))) {
        if ($line -match '^\s*versions\s*=\s*(\d+)' -and [int]$Matches[1] -gt 0) { $KeepPerFile = [int]$Matches[1]; $keepAnyAge = $true }
    }
}
foreach ($d in @($BackupRoot, $versionRoot)) {
    if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
}

# --- Load the index -------------------------------------------------------
$index = @{}
if (-not $Full -and (Test-Path -LiteralPath $indexPath)) {
    try {
        (Get-Content -LiteralPath $indexPath -Raw | ConvertFrom-Json).PSObject.Properties |
            ForEach-Object { $index[$_.Name] = $_.Value }
    } catch { Write-Log 'Index unreadable, rebuilding from scratch.' 'WARN'; $index = @{} }
}

# --- Savestate filename shapes, from RetroBat's own es_savestates.cfg -------
$statePatterns = @(
    '\.s\d{2}$', '\.state(\d+)?(\.auto)?$', '\.p2s$', '_\d{2}\.sav$', '_resume\.sav$',
    '\.ppst$', '\.jst$', '\.oms$', '\.bigpstate$', '\.State$', '\.st\d$', '\.ds\d$'
)
$junkPatterns = @('\.png$', '\.jpe?g$', '\.log$', '\.tmp$', '\.txt$')
$excludeFile  = ($statePatterns + $junkPatterns) -join '|'

$excludeDirs = @(
    'artwork', 'ctrlr', 'Load', 'TEXTURES', 'Cache', 'ShaderCache', 'Logs', 'Dump',
    'nvram', 'states', 'diff', 'snap', 'inp', 'cfg', 'hi', 'comments'
)
$excludeDirRegex = '(^|\\)(' + (($excludeDirs | ForEach-Object { [regex]::Escape($_) }) -join '|') + ')(\\|$)'

# Folders excluded by their WHOLE PATH, not just their name, because the same
# folder name means something different elsewhere.
#
#   wiiu\cemu\mlc01\usr\title  is where Cemu installs game updates and DLC.
#       That is gigabytes of downloaded content, not save data, and versioning
#       it would balloon the backup for no benefit. Cemu's actual saves live
#       next door in ...\usr\save, which IS backed up.
#
#   The same folder name 'title' under Azahar holds the real 3DS saves, which
#   is exactly why this cannot be a plain name match.
#
# Paths are relative to the saves folder and use backslashes.
$excludePaths = @(
    'wiiu\cemu\mlc01\usr\title'

    # Cemu's play-activity diary. Not save data, and Cemu is usually still
    # holding it open when the game-end backup fires, which put a harmless but
    # noisy "cannot access the file" error in the log after every Wii U session.
    'wiiu\cemu\mlc01\usr\save\system\pdm'
)
$excludePathRegex = '^(' + (($excludePaths | ForEach-Object { [regex]::Escape($_) }) -join '|') + ')(\\|$)'

$maxBytes = $MaxFileMB * 1MB
$new = 0; $same = 0; $pruned = 0; $failed = 0; $skipped = 0; $bytes = 0

# ---------------------------------------------------------------------------
#  THE INDEX MUST FORGET FILES THAT ARE GONE   (added 2026-08-29, v7)
# ---------------------------------------------------------------------------
#  The index was append-only, so an entry stayed forever after its save file
#  was deleted or moved into the excluded list. Harmless while nothing read the
#  index except this script - and then the Saves tab started reading it, and
#  listed "Sonic the Hedgehog 4: Episode I" as a game with saves on the drive.
#  That WiiWare channel had been removed from the Wii NAND weeks earlier. Nine
#  dead entries, one phantom game.
#
#  This is the same lesson as the video volume checked-list, which grew 491
#  entries for 140 files and kept a health light yellow for weeks. An
#  append-only ledger always ends up lying about the present.
#
#  So: every file actually visited this run is recorded here, and anything in
#  the index that was NOT visited is dropped at the end. THE VERSION FILES ARE
#  NOT TOUCHED - they stay in Versions\ exactly where they were. Only the
#  index's claim that the save is still on this drive goes away.
# ---------------------------------------------------------------------------
$seen       = @{}
$enumerated = $false

try {
    $files = @(Get-ChildItem -LiteralPath $SavesRoot -Recurse -File -Force -ErrorAction SilentlyContinue |
             Where-Object { $_.Name -notmatch $excludeFile -and $_.Length -le $maxBytes })

    # the PC ports' own save folders, filed as <system>\_port\<file>
    $portRel = @{}
    $seenDir = @{}
    foreach ($xr in $extraRoots) {
        $xd = Join-Path $RetroBatDir $xr.Dir
        if (-not (Test-Path -LiteralPath $xd) -or $seenDir.ContainsKey($xr.System)) { continue }
        $seenDir[$xr.System] = $true
        foreach ($pf in @(Get-ChildItem -LiteralPath $xd -Recurse -File -Force -ErrorAction SilentlyContinue |
                          Where-Object { $_.Name -notmatch $excludeFile -and $_.Length -le $maxBytes })) {
            $portRel[$pf.FullName] = ('{0}\_port\{1}' -f $xr.System, $pf.FullName.Substring($xd.Length).TrimStart('\'))
            $files += $pf
        }
    }

    if (-not $files) { Write-Log "No save data found under $SavesRoot." 'WARN'; return }

    # Only from here on is it safe to conclude that a missing entry really is
    # gone rather than that the scan failed. Nothing is pruned otherwise.
    $enumerated = $true

    foreach ($f in $files) {

        $rel    = $(if ($portRel.ContainsKey($f.FullName)) { $portRel[$f.FullName] } else { $f.FullName.Substring($SavesRoot.Length).TrimStart('\') })
        $relDir = Split-Path $rel -Parent

        if ($relDir -and $relDir -match $excludeDirRegex)  { $skipped++; continue }
        if ($relDir -and $relDir -match $excludePathRegex) { $skipped++; continue }

        # Marked AFTER the exclusion checks on purpose: a file that is now
        # excluded should have its old index entry dropped too, which is what
        # cleared out Cemu's play-diary leftovers.
        $seen[$rel] = $true

        # --- FAST PATH -----------------------------------------------------
        # Unchanged timestamp + size, and the version we recorded is still on
        # disk? Then there is nothing to do. No hashing, no copying.
        $entry = $index[$rel]
        $entryFull = ''
        if ($entry) { $entryFull = Get-FullVersionPath $entry.v }
        if ($entry -and
            $entry.m -eq $f.LastWriteTimeUtc.Ticks -and
            $entry.s -eq $f.Length -and
            $entryFull -and (Test-Path -LiteralPath $entryFull)) {
            # Upgrade an old absolute entry to the relative shape in passing.
            $entryRel = Get-RelativeVersionPath $entry.v
            if ($entryRel -ne $entry.v) {
                $index[$rel] = @{ m = $entry.m; s = $entry.s; h = $entry.h; v = $entryRel }
            }
            $same++
            continue
        }

        $shortLeaf = Get-ShortSaveLeaf $f.Name
        $safeName = $shortLeaf -replace '\.', '_'
        $histDir  = if ($relDir) { Join-Path (Join-Path $versionRoot $relDir) $safeName }
                    else         { Join-Path $versionRoot $safeName }

        try   { $short = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256 -ErrorAction Stop).Hash.Substring(0,8).ToLower() }
        catch { Write-Problem "Could not read $rel - $($_.Exception.Message)"; $failed++; continue }

        $existingVersion = $null
        if (Test-Path -LiteralPath $histDir) {
            $existingVersion = Get-ChildItem -LiteralPath $histDir -File -ErrorAction SilentlyContinue |
                               Where-Object { $_.Name -like "*_$short`__*" } | Select-Object -First 1
        }
        else {
            if (-not $PSCmdlet.ShouldProcess($histDir, 'Create history folder')) { continue }
            try   { New-Item -ItemType Directory -Path $histDir -Force -ErrorAction Stop | Out-Null }
            catch { Write-Problem "Could not create folder for $rel - $($_.Exception.Message)"; $failed++; continue }
        }

        if ($existingVersion) {
            # Content already captured (file was touched but not really changed).
            $index[$rel] = @{ m = $f.LastWriteTimeUtc.Ticks; s = $f.Length; h = $short; v = (Get-RelativeVersionPath $existingVersion.FullName) }
            $same++
            continue
        }

        $dest = Join-Path $histDir ('{0}_{1}__{2}' -f $stamp, $short, $shortLeaf)
        if (-not $PSCmdlet.ShouldProcess($dest, 'Save new version')) { continue }

        try {
            Copy-Item -LiteralPath $f.FullName -Destination $dest -Force -ErrorAction Stop

            # Verify the copy landed whole. A shutdown mid-copy would otherwise
            # leave a truncated file that the index would wrongly trust.
            $written = Get-Item -LiteralPath $dest -ErrorAction Stop
            if ($written.Length -ne $f.Length) {
                Remove-Item -LiteralPath $dest -Force -ErrorAction SilentlyContinue
                throw "copy was incomplete ($($written.Length) of $($f.Length) bytes)"
            }

            $new++; $bytes += $f.Length
            $index[$rel] = @{ m = $f.LastWriteTimeUtc.Ticks; s = $f.Length; h = $short; v = (Get-RelativeVersionPath $dest) }
        }
        catch { Write-Problem "Failed to version $rel - $($_.Exception.Message)"; $failed++; continue }

        # --- Prune this file's history ------------------------------------
        $cutoff  = (Get-Date).AddDays(-$KeepDays)
        $history = Get-ChildItem -LiteralPath $histDir -File -ErrorAction SilentlyContinue | Sort-Object Name -Descending
        if ($history.Count -gt $KeepPerFile) {
            foreach ($old in $history | Select-Object -Skip $KeepPerFile) {
                if (-not $keepAnyAge -and $old.LastWriteTime -gt $cutoff) { continue }
                try { Remove-Item -LiteralPath $old.FullName -Force -ErrorAction Stop; $pruned++ } catch { }
            }
        }
    }
}
finally {
    # --- forget files that are no longer here -----------------------------
    $forgotten = 0
    if ($enumerated -and -not $WhatIfPreference) {
        # @() matters: $index.Keys is live, and removing from a hashtable while
        # walking its own key collection throws.
        foreach ($old in @($index.Keys)) {
            if (-not $seen.ContainsKey($old)) { $index.Remove($old); $forgotten++ }
        }
    }

    try { $index | ConvertTo-Json -Depth 4 -Compress | Set-Content -LiteralPath $indexPath -Encoding UTF8 -ErrorAction Stop }
    catch { Write-Log "Could not save index - next run will be slow. $($_.Exception.Message)" 'WARN' }

    $mb = [math]::Round($bytes / 1MB, 2)
    Write-Log ("Run {0}: {1} new ({2} MB), {3} unchanged, {4} skipped, {5} pruned, {6} failed, {7} no longer on the drive." -f `
               $stamp, $new, $mb, $same, $skipped, $pruned, $failed, $forgotten)
}
