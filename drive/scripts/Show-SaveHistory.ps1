<#
    Show-SaveHistory.ps1   (v1)
    ---------------------------------------------------------------------------
    Browse your saves by GAME, and put a whole game back the way it was on a
    given day. Use the SaveBackups\Browse My Saves.bat button rather than
    calling this directly.

    This is the console version of the wizard's Saves tab, and it exists on
    purpose. The rule on this drive is that the window is a convenience layer
    and never a dependency: if the Setup Wizard ever breaks, this button still
    does the whole job.

    All the real work is in scripts\SaveIndex.ps1, which both front ends share,
    so there is only one set of rules about what counts as a game.

    WHY THIS IS NOT "Restore A Save.bat" WITH A NEW COAT OF PAINT
      The old button lists individual FILES and prints a warning telling you
      that Wii and 3DS saves are spread over several of them, so you have to
      restore each one by hand and match the dates yourself. This one groups
      the files into games and puts the whole set back from one moment. The old
      button still works and is still there, for one-file jobs.

    RULES HONOURED: no drive letters, Windows PowerShell 5.1, pure ASCII,
    no $PSScriptRoot inside param().
#>

[CmdletBinding()]
param(
    [switch] $All,          # also list arcade memory and system files
    [string] $RetroBatRoot = '',
    [string] $SavesRoot  = '',
    [string] $BackupRoot = '',
    [string] $QuarantineRoot = ''
)

# ---------------------------------------------------------------------------
#  WHERE AM I?  (do not move this into the param block above)
# ---------------------------------------------------------------------------
#  $PSScriptRoot is EMPTY while PowerShell works out parameter defaults under
#  -File. Building a path up there kills the script before it can say why.
#  See the same comment in Backup-RetroBatSaves.ps1 for the full story.
# ---------------------------------------------------------------------------
$ScriptDir = $PSScriptRoot
if (-not $ScriptDir) { $ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path }
if (-not $ScriptDir) { throw 'Could not work out which folder this script is in.' }
$WorkspaceDir = Split-Path $ScriptDir -Parent      # <RetroBat>\_ClaudeWorkspace
$RetroBatDir  = Split-Path $WorkspaceDir -Parent   # <RetroBat>

# Every root is overridable and every one is resolved HERE rather than in the
# param block, the same shape Quarantine-Savestates.ps1 uses. It is what makes
# the whole script runnable against a fake drive in a test.
if ($RetroBatRoot) { $RetroBatDir = $RetroBatRoot }
if (-not $SavesRoot)  { $SavesRoot  = Join-Path $RetroBatDir 'saves' }
if (-not $BackupRoot) { $BackupRoot = Join-Path $WorkspaceDir 'SaveBackups' }
# Same shape as the parameters above, and for the same reason: named here so it
# can be pointed somewhere else for testing, resolved in the body so
# $PSScriptRoot is actually populated. Matches Quarantine-Savestates.ps1.
if (-not $QuarantineRoot) { $QuarantineRoot = Join-Path $WorkspaceDir 'archive\quarantined-savestates' }

. (Join-Path $ScriptDir 'SaveIndex.ps1')
. (Join-Path $ScriptDir 'GameNames.ps1')

$VersionRoot = Join-Path $BackupRoot 'Versions'
$IndexPath   = Join-Path $BackupRoot 'index.json'
$NamesPath   = Join-Path $BackupRoot 'game-name-shortcuts.txt'

function Write-Rule { Write-Host ('  ' + ('-' * 71)) -ForegroundColor DarkGray }

# The mid-game autosaves for one game. A function rather than inline code
# because it has to appear in three places, always UNDERNEATH the ordinary
# saves, including on the two paths where there are no ordinary saves to show.
function Write-SavestateList($game) {
    if (-not $game.Savestates -or $game.Savestates.Count -eq 0) { return }
    Write-Host ''
    Write-Host '   MID-GAME AUTOSAVES' -ForegroundColor Yellow
    Write-Host '   Snapshots taken mid-play, not ordinary saves. Held aside on purpose.' -ForegroundColor DarkGray
    foreach ($st in @($game.Savestates | Select-Object -First 8)) {
        Write-Host ('      {0}   slot {1}   ({2})' -f `
            $st.When.ToString('ddd yyyy-MM-dd HH:mm'), $st.Slot, (Format-SaveSize $st.Size)) -ForegroundColor DarkGray
    }
    if ($game.Savestates.Count -gt 8) {
        Write-Host ('      ... and {0} older ones.' -f ($game.Savestates.Count - 8)) -ForegroundColor DarkGray
    }
    Write-Host '   Put one back from the wizard''s Saves tab.' -ForegroundColor DarkGray
    Write-Host ''
}

function Test-RetroBatRunning {
    $p = Get-Process -Name 'emulationstation', 'RetroBat', 'BatGui' -ErrorAction SilentlyContinue
    return ($null -ne $p)
}

if (-not (Test-Path -LiteralPath $IndexPath)) {
    Write-Host ''
    Write-Host '  There is no backup list yet.' -ForegroundColor Yellow
    Write-Host '  Press the "Backup Saves Now" button once, then come back here.'
    Write-Host ''
    return
}

# Work out what the game codes mean. Cached in game-names-found.txt and only
# rebuilt when it is missing, a month old, or a gamelist.xml has changed.
try {
    if (Update-GameNameCache -Root $RetroBatDir -BackupRoot $BackupRoot) {
        Write-Host '  Working out game names for the first time...' -ForegroundColor DarkGray
    }
}
catch { Write-Host ('  (could not work out game names: {0})' -f $_.Exception.Message) -ForegroundColor DarkGray }

$found = Read-GameNameCache (Get-GameNameCachePath $BackupRoot) $RetroBatDir
$index = Read-SaveIndex $IndexPath
$names = Read-GameNames $NamesPath
$games = @(Get-SaveGames -Index $index -Names $names -Found $found)

# The mid-game autosaves that Quarantine-Savestates.ps1 has put aside, attached
# to the games they belong to rather than listed on their own.
$states = @(Get-QuarantinedSavestates $QuarantineRoot)
$games  = @(Add-SavestatesToGames -Games $games -Savestates $states -Found $found)
if ($games.Count -eq 0) {
    Write-Host ''
    Write-Host '  Nothing has been backed up yet.' -ForegroundColor Yellow
    Write-Host ''
    return
}

$showAll = [bool]$All

# ---------------------------------------------------------------------------
while ($true) {

    $list = @($games | Where-Object { $showAll -or $_.Category -eq 'game' })

    Write-Host ''
    Write-Rule
    Write-Host '   YOUR SAVES' -ForegroundColor Cyan
    Write-Rule
    Write-Host ''
    $n = 0
    foreach ($g in $list) {
        $n++
        $when = if ($g.Changed -gt [datetime]::MinValue) { $g.Changed.ToString('ddd yyyy-MM-dd HH:mm') } else { '' }
        $tag  = ''
        if ($g.Category -eq 'arcade') { $tag = '  [arcade memory]' }
        if ($g.Category -eq 'system') { $tag = '  [system files]' }
        if ($g.Savestates -and $g.Savestates.Count -gt 0) {
            $tag += ('  * {0} MID-GAME AUTOSAVE{1}' -f $g.Savestates.Count,
                     $(if ($g.Savestates.Count -eq 1) { '' } else { 'S' }))
        }
        Write-Host ('   {0,3}.  {1,-42} {2,-10} {3} {4}' -f `
            $n, $g.DisplayName, $g.System, $when, $tag)
    }
    Write-Host ''
    Write-Rule
    if (-not $showAll) {
        Write-Host '   Type A to also show arcade memory (one per arcade rom, made by the'  -ForegroundColor DarkGray
        Write-Host '   emulator rather than by you) and system files (Wii and 3DS internal' -ForegroundColor DarkGray
        Write-Host '   memory, and emulator settings).'                                     -ForegroundColor DarkGray
    }
    Write-Host '   Names are worked out from the game files on this drive. Anything'   -ForegroundColor DarkGray
    Write-Host '   still shown as a code, like GKYE, could not be worked out - add it'  -ForegroundColor DarkGray
    Write-Host '   to game-name-shortcuts.txt in this folder, or use the wizard''s'      -ForegroundColor DarkGray
    Write-Host '   Saves tab, which has a button for it.'                                -ForegroundColor DarkGray
    Write-Host ''
    $pick = Read-Host '   Number to open, A for everything, or Enter to quit'
    if (-not $pick) { break }
    if ($pick.Trim().ToUpper() -eq 'A') { $showAll = -not $showAll; continue }

    $num = 0
    if (-not [int]::TryParse($pick.Trim(), [ref]$num) -or $num -lt 1 -or $num -gt $list.Count) {
        Write-Host '   That is not one of the numbers above.' -ForegroundColor Yellow
        continue
    }
    $game = $list[$num - 1]

    # -----------------------------------------------------------------------
    while ($true) {
        $points = @(Get-SaveRestorePoints $VersionRoot $game.Files)

        Write-Host ''
        Write-Rule
        Write-Host ('   {0}   ({1})' -f $game.DisplayName, $game.System) -ForegroundColor Cyan
        Write-Rule
        Write-Host ''
        if ($game.Files.Count -gt 0) {
            Write-Host ('   This save is made of {0} file(s):' -f $game.Files.Count)
            foreach ($f in $game.Files) { Write-Host ('      ' + (Split-Path $f -Leaf)) -ForegroundColor DarkGray }
            Write-Host ''
        }

        if ($game.Files.Count -eq 0) {
            Write-Host '   No ordinary save data for this game, only the autosaves below.' -ForegroundColor Yellow
            Write-SavestateList $game
            [void](Read-Host '   Press Enter to go back')
            break
        }

        if ($points.Count -eq 0) {
            Write-Host '   No backed up versions of this one yet.' -ForegroundColor Yellow
            Write-SavestateList $game
            [void](Read-Host '   Press Enter to go back')
            break
        }

        Write-Host '   Versions you can go back to, newest first:'
        Write-Host ''
        $i = 0
        foreach ($p in $points) {
            $i++
            $note = if ($i -eq 1) { '   (this is what you have now)' } else { '' }
            Write-Host ('   {0,3}.  {1}      {2} of the files changed here{3}' -f `
                $i, $p.When, $p.Changed, $note)
        }
        Write-SavestateList $game
        Write-Host ''
        Write-Rule
        Write-Host ''
        $pp = Read-Host '   Number to restore, or Enter to go back'
        if (-not $pp) { break }
        $pn = 0
        if (-not [int]::TryParse($pp.Trim(), [ref]$pn) -or $pn -lt 1 -or $pn -gt $points.Count) {
            Write-Host '   That is not one of the numbers above.' -ForegroundColor Yellow
            continue
        }
        $point = $points[$pn - 1]

        # --- preview, then ask ---------------------------------------------
        $snap = @(Resolve-SaveSnapshot $VersionRoot $game.Files $point.Stamp)
        Write-Host ''
        Write-Rule
        Write-Host ('   ABOUT TO PUT {0} BACK TO {1}' -f $game.DisplayName.ToUpper(), $point.When) -ForegroundColor Yellow
        Write-Rule
        Write-Host ''
        foreach ($s in $snap) {
            if ($s.Missing) {
                Write-Host ('      leave alone   {0}   (did not exist yet)' -f (Split-Path $s.Rel -Leaf)) -ForegroundColor DarkGray
            } else {
                Write-Host ('      put back      {0}   from {1}  ({2})' -f `
                    (Split-Path $s.Rel -Leaf), $s.When, (Format-SaveSize $s.Size))
            }
        }
        Write-Host ''
        Write-Host '   What is there now is kept first, as a "prerestore" version,' -ForegroundColor DarkGray
        Write-Host '   so this can be undone by restoring the newest version again.' -ForegroundColor DarkGray
        Write-Host ''

        if (Test-RetroBatRunning) {
            Write-Host '   RetroBat is open. Close it first - a running game will write its' -ForegroundColor Yellow
            Write-Host '   own save over anything restored now.' -ForegroundColor Yellow
            Write-Host ''
            [void](Read-Host '   Press Enter to go back')
            continue
        }

        $yes = Read-Host '   Type YES to go ahead, anything else to cancel'
        if ($yes.Trim().ToUpper() -ne 'YES') {
            Write-Host '   Cancelled. Nothing was changed.' -ForegroundColor DarkGray
            continue
        }

        $res = Restore-SaveSnapshot -SavesRoot $SavesRoot -VersionRoot $VersionRoot -Snapshot $snap
        Write-Host ''
        foreach ($m in @($res.Messages)) { Write-Host ('      ' + $m) -ForegroundColor DarkGray }
        Write-Host ''
        if ($res.Failed -gt 0) {
            Write-Host ('   {0} put back, {1} left alone, {2} FAILED.' -f $res.Restored, $res.Skipped, $res.Failed) -ForegroundColor Red
        } else {
            Write-Host ('   Done. {0} put back, {1} left alone.' -f $res.Restored, $res.Skipped) -ForegroundColor Green
        }
        Write-Host ''
        [void](Read-Host '   Press Enter to continue')
    }
}

Write-Host ''
